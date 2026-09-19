defmodule BuildCalculator.Wiki.Api do
  @moduledoc """
  Thin MediaWiki `api.php` client for the two wikis this project mines.

  Only used from `mix wiki.fetch`; the application itself never talks to a wiki at
  runtime (see CLAUDE.md §3 — data is a reviewed snapshot in the repository).

  Behaves politely: identifying User-Agent, strictly sequential requests with a
  pause between them, and full `continue` pagination rather than first-page-only.
  """

  @user_agent "SialaBuildCalculator/0.1 (NWN build calculator for the Siala shard; dan.bykov@gmail.com)"

  # Anonymous MediaWiki clients may pass at most 50 titles per query.
  @batch_size 50
  @delay_ms 200

  @endpoints %{
    "fandom" => "https://nwn.fandom.com/api.php",
    "siala" => "https://wiki.siala.kiev.ua/api.php"
  }

  @doc "Known wiki keys, in a stable order."
  @spec wikis() :: [binary]
  def wikis, do: @endpoints |> Map.keys() |> Enum.sort()

  @doc "`api.php` endpoint for a wiki key."
  @spec endpoint(binary) :: binary
  def endpoint(wiki), do: Map.fetch!(@endpoints, wiki)

  @doc """
  Members of a category tree, `max_depth` levels of subcategories deep.

  Returns only main-namespace page titles, deduplicated and sorted.
  """
  @spec category_tree(binary, [binary], non_neg_integer) :: [binary]
  def category_tree(wiki, roots, max_depth) do
    {pages, _seen} = walk_categories(wiki, roots, max_depth, MapSet.new(), MapSet.new())
    pages |> MapSet.to_list() |> Enum.sort()
  end

  defp walk_categories(_wiki, [], _depth, pages, seen), do: {pages, seen}
  defp walk_categories(_wiki, _roots, depth, pages, seen) when depth < 0, do: {pages, seen}

  defp walk_categories(wiki, roots, depth, pages, seen) do
    {pages, seen, next} =
      Enum.reduce(roots, {pages, seen, []}, fn root, {pages, seen, next} ->
        if MapSet.member?(seen, root) do
          {pages, seen, next}
        else
          members = category_members(wiki, root)

          pages =
            members
            |> Enum.filter(&(&1["ns"] == 0))
            |> Enum.reduce(pages, &MapSet.put(&2, &1["title"]))

          subcats = members |> Enum.filter(&(&1["ns"] == 14)) |> Enum.map(& &1["title"])
          {pages, MapSet.put(seen, root), next ++ subcats}
        end
      end)

    walk_categories(wiki, Enum.uniq(next), depth - 1, pages, seen)
  end

  @doc "Direct members of a single category (pages and subcategories), all pages of results."
  @spec category_members(binary, binary) :: [map]
  def category_members(wiki, category) do
    paginate(
      wiki,
      %{
        "action" => "query",
        "list" => "categorymembers",
        "cmtitle" => category,
        "cmlimit" => "500"
      },
      &(get_in(&1, ["query", "categorymembers"]) || [])
    )
  end

  @doc "Main-namespace titles a page links to."
  @spec links(binary, binary) :: [binary]
  def links(wiki, title) do
    wiki
    |> paginate(
      %{
        "action" => "query",
        "prop" => "links",
        "titles" => title,
        "plnamespace" => "0",
        "pllimit" => "500"
      },
      fn body ->
        for page <- get_in(body, ["query", "pages"]) || [],
            link <- page["links"] || [],
            do: link["title"]
      end
    )
    |> Enum.uniq()
  end

  @doc "All main-namespace redirect page titles of a wiki."
  @spec redirect_titles(binary) :: [binary]
  def redirect_titles(wiki) do
    wiki
    |> paginate(
      %{
        "action" => "query",
        "list" => "allpages",
        "apnamespace" => "0",
        "apfilterredir" => "redirects",
        "aplimit" => "500"
      },
      fn body -> Enum.map(get_in(body, ["query", "allpages"]) || [], & &1["title"]) end
    )
    |> Enum.sort()
  end

  @doc """
  Resolves redirect titles to their targets.

  Returns `%{redirect_title => target_title}`; titles that turn out not to be
  redirects simply do not appear in the result.
  """
  @spec resolve_redirects(binary, [binary]) :: %{binary => binary}
  def resolve_redirects(wiki, titles) do
    titles
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce(%{}, fn chunk, acc ->
      body =
        request(wiki, %{
          "action" => "query",
          "prop" => "info",
          "redirects" => "1",
          "titles" => Enum.join(chunk, "|")
        })

      body
      |> get_in(["query", "redirects"])
      |> Kernel.||([])
      |> Enum.reduce(acc, &Map.put(&2, &1["from"], &1["to"]))
    end)
  end

  @doc """
  Raw wikitext of the given titles.

  Redirects are followed, so the returned `"title"` is the resolved one. Missing
  pages are returned with `"missing" => true` and no revision.
  """
  @spec contents(binary, [binary]) :: [map]
  def contents(wiki, titles) do
    titles
    |> Enum.chunk_every(@batch_size)
    |> Enum.flat_map(fn chunk ->
      wiki
      |> request(%{
        "action" => "query",
        "prop" => "revisions",
        "rvprop" => "content|ids",
        "rvslots" => "main",
        "redirects" => "1",
        "titles" => Enum.join(chunk, "|")
      })
      |> get_in(["query", "pages"])
      |> Kernel.||([])
    end)
  end

  @doc """
  Titles that redirect **onto** the given pages, as `%{title => [redirect title]}`.

  The other direction from `resolve_redirects/2`, and the one wikitext needs: a
  link inside a page names whatever title its author typed, and that title is
  often a redirect. The barbarian's progression table links `[[Damage Reduction
  (feat)]]`, which is a redirect onto `Damage reduction (barbarian)` — without
  this the grant reads as naming no page at all, and the class quietly stops
  handing the feat out.

  Only main-namespace redirects are asked for, and pages nothing redirects to
  simply come back with an empty list.
  """
  @spec redirects_to(binary, [binary]) :: %{binary => [binary]}
  def redirects_to(wiki, titles) do
    titles
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce(%{}, fn chunk, acc ->
      collect_redirects(
        wiki,
        %{
          "action" => "query",
          "prop" => "redirects",
          "rdnamespace" => "0",
          "rdlimit" => "500",
          "titles" => Enum.join(chunk, "|")
        },
        acc
      )
    end)
  end

  defp collect_redirects(wiki, params, acc) do
    body = request(wiki, params)

    acc =
      body
      |> get_in(["query", "pages"])
      |> Kernel.||([])
      |> Enum.reduce(acc, fn page, acc ->
        names = Enum.map(page["redirects"] || [], & &1["title"])
        Map.update(acc, page["title"], names, &(&1 ++ names))
      end)

    case body["continue"] do
      nil -> acc
      continue -> collect_redirects(wiki, Map.merge(params, continue), acc)
    end
  end

  @doc """
  Image metadata (`File:` page) for a set of file names, keyed by the *exact*
  name requested — not by the wiki's own canonical title.

  This is `File:` namespace, unlike every other function in this module, so it
  cannot reuse `redirects_to/2` or `resolve_redirects/2` as-is: those resolve a
  title to *another title in our list*, but a bare `redirects=1` query resolves
  through MediaWiki's own normalisation (only the first character of a title is
  auto-capitalised; space and underscore are interchangeable) *and* through
  `File:` redirect pages in one step, and does it for every title whether or
  not it happens to be a redirect. Two different `icon` spellings recorded in
  our data (`Ife_ambidex.gif` vs `ife ambidex.gif`) can both land on that one
  step — a caller that only compared strings would download the same bytes
  twice under two names and never notice.

  Returns `%{requested_name => info | :missing}`, where `info` is
  `%{title:, pageid:, url:, size:, width:, height:, sha1:, mime:, timestamp:}`.
  Two entries with the same `:pageid` are the wiki itself saying they are one
  file. `width`/`height` ride along for free — MediaWiki bundles them into the
  same `imageinfo` entry whenever `size` is requested, no extra `iiprop`.
  """
  @spec image_info(binary, [binary]) :: %{binary => map | :missing}
  def image_info(wiki, names) do
    names
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce(%{}, fn chunk, acc ->
      titles = Enum.map(chunk, &"File:#{&1}")

      body =
        request(wiki, %{
          "action" => "query",
          "titles" => Enum.join(titles, "|"),
          "prop" => "imageinfo",
          "iiprop" => "url|size|sha1|mime|timestamp",
          "redirects" => "1"
        })

      query = body["query"] || %{}
      normalized = Map.new(query["normalized"] || [], &{&1["from"], &1["to"]})
      redirected = Map.new(query["redirects"] || [], &{&1["from"], &1["to"]})
      by_title = Map.new(query["pages"] || [], &{&1["title"], &1})

      Enum.reduce(titles, acc, fn title, acc ->
        resolved =
          title
          |> then(&Map.get(normalized, &1, &1))
          |> then(&Map.get(redirected, &1, &1))

        Map.put(acc, String.trim_leading(title, "File:"), image_result(by_title[resolved]))
      end)
    end)
  end

  defp image_result(%{"imageinfo" => [info | _]} = page) do
    %{
      title: page["title"],
      pageid: page["pageid"],
      url: info["url"],
      size: info["size"],
      width: info["width"],
      height: info["height"],
      sha1: info["sha1"],
      mime: info["mime"],
      timestamp: info["timestamp"]
    }
  end

  defp image_result(_missing_or_no_revision), do: :missing

  @doc """
  Downloads raw bytes from an absolute URL — an image CDN link, not `api.php`.

  Same politeness as `request/2`: identifying User-Agent, a retrying `Req`,
  and the same explicit `https_proxy` workaround (`Req`/`Mint` do not read
  that environment variable on their own — see `proxy_options/0`).

  Raises on a non-200 status, and on a body shorter than the response's own
  `content-length` (a truncated transfer). Neither is enough to trust the
  bytes are really *the* image a caller asked for — a CDN can answer 200 with
  a complete, correctly-sized HTML error page, or transparently substitute a
  transcoded file at the same URL (`mix wiki.fetch.icons` hit exactly that:
  Fandom's CDN serves WebP by default for these old GIFs and only the literal
  bytes MediaWiki's own database describes when `&format=original` is added
  to the URL) — so the caller still has to check the magic bytes against the
  MIME type it actually asked for.
  """
  @spec download!(binary) :: binary
  def download!(url) do
    response =
      Req.get!(
        url,
        [
          headers: [{"user-agent", @user_agent}],
          retry: :transient,
          max_retries: 3,
          receive_timeout: 60_000
        ] ++ proxy_options()
      )

    Process.sleep(@delay_ms)

    case response.status do
      200 -> check_length!(response, url)
      status -> raise "download failed (HTTP #{status}): #{url}"
    end
  end

  defp check_length!(response, url) do
    declared =
      case Req.Response.get_header(response, "content-length") do
        [value] -> Integer.parse(value)
        _otherwise -> :error
      end

    actual = byte_size(response.body)

    case declared do
      {^actual, ""} ->
        response.body

      {other, ""} ->
        raise "truncated download (content-length said #{other}, got #{actual} bytes): #{url}"

      :error ->
        response.body
    end
  end

  @doc "Category titles per page, as `%{title => [category_title]}`."
  @spec categories(binary, [binary]) :: %{binary => [binary]}
  def categories(wiki, titles) do
    titles
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce(%{}, fn chunk, acc ->
      collect_categories(
        wiki,
        %{
          "action" => "query",
          "prop" => "categories",
          "cllimit" => "500",
          "titles" => Enum.join(chunk, "|")
        },
        acc
      )
    end)
  end

  defp collect_categories(wiki, params, acc) do
    body = request(wiki, params)

    acc =
      body
      |> get_in(["query", "pages"])
      |> Kernel.||([])
      |> Enum.reduce(acc, fn page, acc ->
        cats = Enum.map(page["categories"] || [], & &1["title"])
        Map.update(acc, page["title"], cats, &(&1 ++ cats))
      end)

    case body["continue"] do
      nil -> acc
      continue -> collect_categories(wiki, Map.merge(params, continue), acc)
    end
  end

  defp paginate(wiki, params, extract, acc \\ []) do
    body = request(wiki, params)
    acc = acc ++ extract.(body)

    case body["continue"] do
      nil -> acc
      continue -> paginate(wiki, Map.merge(params, continue), extract, acc)
    end
  end

  defp request(wiki, params) do
    params = Map.merge(params, %{"format" => "json", "formatversion" => "2"})

    response =
      Req.get!(
        endpoint(wiki),
        [
          params: params,
          headers: [{"user-agent", @user_agent}],
          retry: :transient,
          max_retries: 3,
          receive_timeout: 60_000
        ] ++ proxy_options()
      )

    Process.sleep(@delay_ms)

    case response.body do
      %{"error" => error} ->
        raise "MediaWiki API error on #{wiki}: #{inspect(error)} (params: #{inspect(params)})"

      body when is_map(body) ->
        body

      other ->
        raise "unexpected #{wiki} response: #{inspect(other)}"
    end
  end

  # Unlike curl, Req/Mint ignores the `https_proxy` environment variable. On a
  # machine that can only reach the wikis through a local proxy this shows up as a
  # bare TLS handshake timeout, so honour the variable explicitly.
  defp proxy_options do
    url = System.get_env("https_proxy") || System.get_env("HTTPS_PROXY")

    case url && URI.parse(url) do
      %URI{host: host, port: port} when is_binary(host) and is_integer(port) ->
        [connect_options: [proxy: {:http, host, port, []}]]

      _otherwise ->
        []
    end
  end
end
