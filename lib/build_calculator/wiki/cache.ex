defmodule BuildCalculator.Wiki.Cache do
  @moduledoc """
  On-disk layout of the raw wiki snapshot (`priv/wiki_cache/`).

      priv/wiki_cache/
        fandom/_index.json
        fandom/<Page Title>.wikitext
        siala/_index.json
        siala/<Заголовок страницы>.wikitext

  The raw wikitext is kept separately from the parsed data on purpose: when the
  parsed format changes we re-run `mix wiki.parse` over this cache instead of
  hammering the wikis again, and a reviewer can diff a parsed value against the
  exact source bytes it came from.

  Titles are kept verbatim as file names (Cyrillic is *not* transliterated); only
  characters that are unsafe in a path are replaced with `_`. Because the default
  macOS filesystem is case-insensitive, titles that differ only in case (the Siala
  wiki has `Ученик красного дракона` the class and `Ученик Красного дракона` the
  build) would silently overwrite each other, so all members of such a group get a
  `~pageid` suffix. Each index entry therefore records the `file` it lives in
  rather than leaving readers to re-derive it.
  """

  alias BuildCalculator.Wiki.Json

  @root "priv/wiki_cache"
  @index "_index.json"
  @categories "_categories.json"
  @extension ".wikitext"

  # Everything forbidden on macOS/Linux/Windows paths, plus control characters.
  @unsafe ~r/[\/\\:*?"<>|\x00-\x1f]/u

  @doc "Absolute path of the cache root."
  @spec root() :: binary
  def root, do: Path.join(File.cwd!(), @root)

  @doc "Absolute path of one wiki's cache directory."
  @spec dir(binary) :: binary
  def dir(wiki), do: Path.join(root(), wiki)

  @doc "Absolute path of a cached `.wikitext` file."
  @spec page_path(binary, binary) :: binary
  def page_path(wiki, file), do: Path.join(dir(wiki), file)

  @doc """
  File names for a set of entries, as `%{title => file_name}`.

  Titles colliding case-insensitively are all suffixed with `~pageid`, so the
  result never depends on which title happened to be written first.
  """
  @spec file_names([map]) :: %{binary => binary}
  def file_names(entries) do
    entries
    |> Enum.group_by(&(&1.title |> sanitize() |> String.downcase()))
    |> Enum.flat_map(fn
      {_key, [entry]} ->
        [{entry.title, sanitize(entry.title) <> @extension}]

      {_key, clashing} ->
        Enum.map(clashing, &{&1.title, sanitize(&1.title) <> "~#{&1.pageid}" <> @extension})
    end)
    |> Map.new()
  end

  defp sanitize(title), do: String.replace(title, @unsafe, "_")

  @doc """
  Writes one wiki's cache directory: a `.wikitext` file per entry plus `_index.json`.

  `entries` are maps with `:title`, `:pageid`, `:revid`, `:fetched`, `:categories`
  and `:content`, plus an optional `:aliases`. Files in the directory that are not
  part of `entries` are removed, so the cache always reflects exactly one fetch run.
  """
  @spec write!(binary, [map]) :: :ok
  def write!(wiki, entries) do
    dir = dir(wiki)
    File.mkdir_p!(dir)
    entries = Enum.sort_by(entries, & &1.title)
    names = file_names(entries)

    for entry <- entries do
      File.write!(Path.join(dir, Map.fetch!(names, entry.title)), entry.content)
    end

    keep = MapSet.new([@index, @categories | Map.values(names)])

    for name <- File.ls!(dir), not MapSet.member?(keep, name) do
      File.rm!(Path.join(dir, name))
    end

    entries = Enum.map(entries, &Map.put(&1, :file, Map.fetch!(names, &1.title)))
    write_index!(wiki, entries)
  end

  @doc """
  Adds pages to a cache that already exists, leaving every page in it untouched.

  Returns `{added, already_present}` as lists of titles.

  This is the difference between "we need six more pages" and "re-fetch the wiki".
  A full `write!/2` run re-downloads every page, and every `revid` in the parsed
  snapshot then cites a revision nobody looked at — the exact hazard this module's
  own docs warn about ("without a wiki edit made in between quietly rewriting the
  data underneath the parsed files"). So a title already in the index **wins over
  the freshly downloaded one**: its `revid`, its `fetched` date and its bytes stay
  exactly as they were, and the caller is told which titles were refused for that
  reason rather than left to assume they were written.

  Existing pages are read off disk and handed back to `write!/2` unchanged, so
  file naming, the case-collision suffix and `_index.json` all keep coming from
  one writer.
  """
  @spec add!(binary, [map]) :: {[binary], [binary]}
  def add!(wiki, entries) do
    existing = read_index!(wiki)
    present = MapSet.new(existing, & &1.title)
    {refused, new} = Enum.split_with(entries, &MapSet.member?(present, &1.title))

    kept = for entry <- existing, do: Map.put(entry, :content, read_page!(wiki, entry))

    write!(wiki, kept ++ new)

    {new |> Enum.map(& &1.title) |> Enum.sort(), refused |> Enum.map(& &1.title) |> Enum.sort()}
  end

  @doc """
  Records the titles that redirect onto pages already in the cache.

  An alias is not a page, so nothing is downloaded and nothing on disk moves:
  `_index.json` alone is rewritten, and every `.wikitext` byte — and every
  `revid` the parsed snapshot cites as its source — stays exactly where it was.

  Titles absent from `aliases` keep whatever they already had, so this can be run
  for one wiki without disturbing the other.
  """
  @spec put_aliases!(binary, %{binary => [binary]}) :: :ok
  def put_aliases!(wiki, aliases) do
    entries =
      for entry <- read_index!(wiki) do
        Map.put(entry, :aliases, Map.get(aliases, entry.title, entry.aliases))
      end

    write_index!(wiki, entries)
  end

  @doc """
  Records the membership of whole categories, as the category itself reports it.

  `_index.json` already stores the categories of every page it holds, but that is
  the view from the pages we happened to download: a race nobody linked would be
  missing from both, and the count would look right. Asking the category
  directly is the independent view, and it is what lets `mix wiki.parse` check
  its dictionaries against a number the wiki states in prose.

  `listings` is `%{category => [member]}` with members as returned by
  `BuildCalculator.Wiki.Api.category_members/2`. Like `put_aliases!/2` this
  downloads no page and moves no `revid`, so it can be added to a snapshot taken
  on another day.
  """
  @spec put_categories!(binary, %{binary => [map]}, binary) :: :ok
  def put_categories!(wiki, listings, fetched) do
    categories =
      for {category, members} <- Enum.sort_by(listings, &elem(&1, 0)) do
        {:obj,
         [
           {"category", category},
           {"members",
            members
            |> Enum.sort_by(& &1["title"])
            |> Enum.map(
              &{:obj, [{"title", &1["title"]}, {"ns", &1["ns"]}, {"pageid", &1["pageid"]}]}
            )}
         ]}
      end

    json = {:obj, [{"fetched", fetched}, {"categories", categories}]}

    File.mkdir_p!(dir(wiki))
    File.write!(Path.join(dir(wiki), @categories), Json.encode!(json))
    :ok
  end

  @doc """
  Reads the category membership snapshot as `%{category => [member]}`.

  Members keep the API's own keys (`"title"`, `"ns"`, `"pageid"`). Raises when the
  snapshot was never taken, rather than returning an empty map: "this category has
  no members" and "nobody ever asked" must not look the same to a caller that is
  about to count them.
  """
  @spec read_categories!(binary) :: %{binary => [map]}
  def read_categories!(wiki) do
    path = Path.join(dir(wiki), @categories)

    unless File.exists?(path) do
      raise "no category snapshot at #{path} — run `mix wiki.fetch --categories-only`"
    end

    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("categories")
    |> Map.new(&{&1["category"], &1["members"]})
  end

  defp write_index!(wiki, entries) do
    index =
      Enum.map(entries, fn entry ->
        {:obj,
         [
           {"title", entry.title},
           {"pageid", entry.pageid},
           {"revid", entry.revid},
           {"fetched", entry.fetched},
           {"categories", Enum.sort(entry.categories)},
           {"aliases", entry |> Map.get(:aliases, []) |> Enum.sort()},
           {"file", entry.file}
         ]}
      end)

    File.write!(Path.join(dir(wiki), @index), Json.encode!(index))
    :ok
  end

  @doc """
  Reads one wiki's `_index.json`.

  Returns entries as maps with atom keys, sorted by title. Raises when the wiki has
  not been fetched yet.

  `aliases` is empty for a cache fetched before redirect titles were collected —
  the same answer as "nothing redirects here", which for a lookup is what it means.
  """
  @spec read_index!(binary) :: [map]
  def read_index!(wiki) do
    path = Path.join(dir(wiki), @index)

    unless File.exists?(path) do
      raise "no wiki cache at #{path} — run `mix wiki.fetch` first"
    end

    path
    |> File.read!()
    |> Jason.decode!()
    |> Enum.map(fn entry ->
      %{
        title: entry["title"],
        pageid: entry["pageid"],
        revid: entry["revid"],
        fetched: entry["fetched"],
        categories: entry["categories"] || [],
        aliases: entry["aliases"] || [],
        file: entry["file"]
      }
    end)
    |> Enum.sort_by(& &1.title)
  end

  @doc "Reads the cached wikitext of an index entry."
  @spec read_page!(binary, map) :: binary
  def read_page!(wiki, entry), do: File.read!(page_path(wiki, entry.file))
end
