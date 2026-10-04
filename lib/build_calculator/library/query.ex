defmodule BuildCalculator.Library.Query do
  @moduledoc """
  Query fragments for the build feeds. No `Repo` calls live here.

  ## Visibility is a `where`, not an `if`

  `visible_to/2` is composed into every read before the filters are, so a build
  the caller may not see is never fetched in the first place. Checking after the
  fact works right up until one code path forgets, and the failure mode of that
  bug is a leak, not an error — which is exactly the kind of bug nobody notices.

  ## Ordering and the cursor

  Every feed reads `updated_at DESC, id DESC` and pages with `seek/2`, never
  `OFFSET`. A backwards page is the same seek with the comparison and the scan
  order both flipped — see `BuildCalculator.Library.Cursor`.
  """

  import Ecto.Query

  alias BuildCalculator.Accounts.{GroupMember, Scope, User}
  alias BuildCalculator.Library.{Build, BuildClass, Cursor}

  @doc "The base query, with the `:build` binding every helper below expects."
  @spec base() :: Ecto.Query.t()
  def base, do: from(b in Build, as: :build)

  @doc """
  Restricts a query to what the caller is allowed to see.

  Three cases, and nothing else can widen them:

    * `public`  — everyone, signed in or not
    * anything owned by the caller, whatever its visibility
    * `group`   — only while a `group_members` row for the caller exists

  The group test is an `EXISTS` rather than a join so a build can never appear
  twice, which would quietly corrupt keyset paging.

  Гость — это `%Scope{user: nil}`, и другого написания у него нет:
  ветка `visible_to(query, nil)` убрана вместе со сменой контракта
  `Scope.for_user/1`. Скоуп теперь есть всегда, а `nil` — это ошибка
  вызывающего, и пусть она падает громко, а не превращается молча
  в «показать только публичное».
  """
  @spec visible_to(Ecto.Query.t(), Scope.t()) :: Ecto.Query.t()
  def visible_to(query, %Scope{user: nil}),
    do: where(query, [build: b], b.visibility == ^:public)

  def visible_to(query, %Scope{user: %User{id: user_id}}) do
    where(
      query,
      [build: b],
      b.visibility == ^:public or
        b.user_id == type(^user_id, :binary_id) or
        (b.visibility == ^:group and
           exists(
             from m in GroupMember,
               where:
                 m.group_id == parent_as(:build).group_id and
                   m.user_id == type(^user_id, :binary_id),
               select: 1
           ))
    )
  end

  @doc """
  Applies the search filters.

  Recognised options — all optional, all narrowing:

    * `:author_id`    — `%User{}` or a user id
    * `:visibility`   — narrow to one visibility (the public feed uses this)
    * `:group_id`     — `%Group{}` or a group id (the group feed)
    * `:race`         — race id, string or atom
    * `:name`         — substring, case-insensitive
    * `:class`        — class id, string or atom
    * `:class_levels` — a `Range` or `{min, max}`; only read together with `:class`
    * `:total_level`  — a `Range` or `{min, max}`

  Unknown options are ignored: the feed is driven straight off query params and
  a stray key should not crash a page.
  """
  @spec filter(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
  def filter(query, opts) do
    query
    |> by_author(Keyword.get(opts, :author_id))
    |> by_visibility(Keyword.get(opts, :visibility))
    |> by_group(Keyword.get(opts, :group_id))
    |> by_race(Keyword.get(opts, :race))
    |> by_name(Keyword.get(opts, :name))
    |> by_class(Keyword.get(opts, :class), Keyword.get(opts, :class_levels))
    |> by_total_level(Keyword.get(opts, :total_level))
  end

  @doc """
  Newest edit first. The `id` tiebreaker is what makes the cursor exact.

  `:asc` is not another sort order on screen — it is how a *backwards* page is
  read. Walking up from a boundary means scanning the index the other way and
  stopping after one page; the rows come back nearest-boundary first and the
  caller flips them, so what the reader sees stays newest-first either way.
  """
  @spec order(Ecto.Query.t(), :desc | :asc) :: Ecto.Query.t()
  def order(query, direction \\ :desc)
  def order(query, :desc), do: order_by(query, [build: b], desc: b.updated_at, desc: b.id)
  def order(query, :asc), do: order_by(query, [build: b], asc: b.updated_at, asc: b.id)

  @doc """
  Positions the query just past a cursor key, on whichever side the cursor names.

  A row-value comparison rather than `updated_at < ? or (updated_at = ? and id < ?)`:
  Postgres can drive an index scan straight off `(updated_at, id)` with the
  former, and the hand-expanded version is where off-by-one bugs at page
  boundaries come from.

  Both sides are strict. `(updated_at, id)` is a total order — `id` is unique,
  so no two rows compare equal — which means `<` and `>` around the same key
  cut the feed into two halves that share no row and lose none. That is the
  whole reason paging back and forth cannot duplicate or drop a build.
  """
  @spec seek(Ecto.Query.t(), Cursor.position() | nil) :: Ecto.Query.t()
  def seek(query, nil), do: query
  def seek(query, {:after, key}), do: seek(query, key, "<")
  def seek(query, {:before, key}), do: seek(query, key, ">")

  defp seek(query, {at, id}, "<") do
    where(
      query,
      [build: b],
      fragment(
        "(?, ?) < (?, ?)",
        b.updated_at,
        b.id,
        type(^at, :utc_datetime),
        type(^id, :binary_id)
      )
    )
  end

  defp seek(query, {at, id}, ">") do
    where(
      query,
      [build: b],
      fragment(
        "(?, ?) > (?, ?)",
        b.updated_at,
        b.id,
        type(^at, :utc_datetime),
        type(^id, :binary_id)
      )
    )
  end

  # ----------------------------------------------------------------- filters --

  defp by_author(query, nil), do: query
  defp by_author(query, %User{id: id}), do: by_author(query, id)

  defp by_author(query, id),
    do: where(query, [build: b], b.user_id == type(^id, :binary_id))

  defp by_visibility(query, nil), do: query

  defp by_visibility(query, visibility) when visibility in [:public, :private, :group],
    do: where(query, [build: b], b.visibility == ^visibility)

  defp by_group(query, nil), do: query
  defp by_group(query, %{id: id}), do: by_group(query, id)

  defp by_group(query, id),
    do: where(query, [build: b], b.group_id == type(^id, :binary_id))

  defp by_race(query, nil), do: query
  defp by_race(query, race), do: where(query, [build: b], b.race == ^to_string(race))

  defp by_name(query, nil), do: query
  defp by_name(query, ""), do: query

  defp by_name(query, term) when is_binary(term) do
    where(query, [build: b], ilike(b.name, ^"%#{escape_like(term)}%"))
  end

  # The wiki's own search shape: "class X, somewhere between N and M levels".
  # `EXISTS` over `build_classes` rather than a join — one build, one row, no
  # matter how many class filters get added later.
  defp by_class(query, nil, _levels), do: query

  defp by_class(query, class, levels) do
    class_id = to_string(class)
    {min, max} = bounds(levels)

    sub =
      from c in BuildClass,
        where: c.build_id == parent_as(:build).id and c.class_id == ^class_id,
        select: 1

    sub = if min, do: where(sub, [c], c.levels >= ^min), else: sub
    sub = if max, do: where(sub, [c], c.levels <= ^max), else: sub

    where(query, [build: b], exists(sub))
  end

  defp by_total_level(query, nil), do: query

  defp by_total_level(query, levels) do
    {min, max} = bounds(levels)

    query
    |> then(&if min, do: where(&1, [build: b], b.total_level >= ^min), else: &1)
    |> then(&if max, do: where(&1, [build: b], b.total_level <= ^max), else: &1)
  end

  defp bounds(nil), do: {nil, nil}
  defp bounds(first..last//_), do: {min(first, last), max(first, last)}
  defp bounds({min, max}), do: {min, max}
  defp bounds(n) when is_integer(n), do: {n, n}

  # `%` and `_` are wildcards to LIKE; a build actually named "Fighter 100%"
  # must not turn into a wildcard search.
  defp escape_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
