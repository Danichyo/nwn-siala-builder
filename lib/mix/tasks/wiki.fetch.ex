defmodule Mix.Tasks.Wiki.Fetch do
  @shortdoc "Downloads raw wikitext from both wikis into priv/wiki_cache/"

  @moduledoc """
  Fills the raw wiki cache and the EN↔RU name map. Network-bound; run rarely.

      mix wiki.fetch                 # both wikis + name map
      mix wiki.fetch --wiki fandom   # one wiki only
      mix wiki.fetch --skip-names    # no name map
      mix wiki.fetch --aliases-only  # redirect titles into the existing cache
      mix wiki.fetch --add           # only titles the cache does not have yet

  Writes:

    * `priv/wiki_cache/fandom/` — vanilla NWN1 rules (EN), the base layer
    * `priv/wiki_cache/siala/` — Siala shard rules (RU), the override layer
    * `priv/rules/name_map.json` — EN name → Siala RU name, from the shard wiki's
      own redirects

  `--aliases-only` refreshes just the `aliases` of `_index.json` — the titles
  that redirect onto each cached page. It downloads no page and rewrites no
  `.wikitext`, so it can be run against an existing snapshot without moving a
  single `revid` the parsed data cites.

  `--add` collects titles exactly as a full run does but downloads only the ones
  the cache has not got, so a category added to the lists below arrives without
  the other 850 pages being re-fetched underneath the parsed snapshot. Same
  reason as `--aliases-only`: a `revid` the data cites must not move because
  somebody wanted six more pages. A title already cached is reported and left
  alone; refreshing one is a full run, deliberately.

  Nothing here parses game data — that is `mix wiki.parse`, which is offline on
  purpose so the parsed snapshot can be regenerated without touching the wikis.

  The Siala wiki describes only *differences* from vanilla, so the Fandom layer is
  not optional: see CLAUDE.md §3.
  """

  use Mix.Task

  alias BuildCalculator.Wiki.Api
  alias BuildCalculator.Wiki.Cache
  alias BuildCalculator.Wiki.Json

  @fandom_categories [
    "Category:Feats",
    "Category:Spells",
    "Category:Classes",
    "Category:Skills",
    "Category:Prestige classes",
    "Category:Races",
    # Задача 3.5. Оружие — домен выбора восьми фитов (`Weapon focus` и семья), и
    # у Сиалы своих характеристик оружия по-английски нет вовсе, поэтому
    # справочник строится только отсюда. Подкатегории (`Simple/Martial/Exotic
    # weapons`) обходятся вместе с остальными на @max_depth, и категория
    # владения читается из них независимо от параметра `proficiency=` шаблона.
    "Category:Weapons"
  ]

  # Character-wide rules that live on no class page. The epic (21+) attack and
  # save progressions are the reason this list exists: on Fandom they are not
  # class data at all, they hang off character level and are written up on these
  # pages only — see `BuildCalculator.Wiki.EpicRules`.
  @fandom_pages [
    "Ability score",
    "Attacks per round",
    "Base attack",
    "Base attack bonus",
    "Base save",
    "Bonus feat",
    "Character level",
    "Epic character",
    "Epic class",
    "General feat",
    "Hit point",
    "Level progression",
    "Prestige class",
    "Skill point",
    "Unarmed base attack bonus"
  ]

  @siala_categories [
    "Категория:Классы",
    "Категория:Фиты",
    "Категория:Навыки",
    "Категория:Заклинания",
    "Категория:Домены"
  ]

  # Shard-specific systems that have no vanilla counterpart, plus the hub of
  # ready-made builds — those pages carry target numbers (AC/AB/HP/skills) and
  # become qa's test cases.
  #
  # `Система оружия` and `Воины Сагры` are here because `Расы` cannot be read
  # without them: every Siala racial bonus is defined as "identical to the bonus
  # for wielding <weapon type>" and every one of them has a larger variant "for a
  # Sagra warrior", which is a group of classes, not a class.
  @siala_pages [
    "Расы",
    "Рост персонажа",
    "41-ый уровень",
    "Билды для новичков",
    "Система оружия",
    "Воины Сагры"
  ]
  @siala_link_hubs ["Билды для новичков"]

  # Categories whose *membership* is data in its own right, not just a way of
  # finding pages to download. `priv/rules/vanilla/creature_types.json` and
  # `spell_schools.json` are the category's contents minus the articles filed
  # under it, and the only honest way to know nothing was missed is to ask the
  # category rather than to count what we happened to fetch.
  @membership_categories %{
    "fandom" => [
      "Category:Races",
      "Category:Spell schools",
      # `weapons.json` is checked against this the same way: the weapon domain is
      # the pages carrying `{{Weapon}}`, and "we fetched everything the category
      # holds" is a claim only the category itself can settle.
      "Category:Weapons",
      # ⚠ And these three are data, not a route to pages: they are the only place
      # the proficiency category of a weapon is stated other than the hand-typed
      # `proficiency=` parameter, so `mix wiki.parse` checks one against the other.
      "Category:Simple weapons",
      "Category:Martial weapons",
      "Category:Exotic weapons",
      # ⚠ And these are how Fandom groups weapons by *kind*, which is the thing
      # Siala's five proficiency feats regroup — so `weapons.json` states both
      # counts side by side instead of letting our assignment look read-off.
      # `Category:Ranged weapons` is also load-bearing on its own: it is the only
      # place the wiki says `Category:Throwing weapons` sits under it, and without
      # that a dart is never labelled ranged by its own page.
      "Category:Ranged weapons",
      "Category:Throwing weapons",
      "Category:Bladed weapons",
      "Category:Blunt weapons",
      "Category:Axes",
      "Category:Polearms"
    ],
    "siala" => []
  }

  # Subcategories are followed two levels deep: Category:Feats -> Category:Class
  # feats -> Category:Fighter bonus feats.
  @max_depth 2

  @name_map_path "priv/rules/name_map.json"

  @impl Mix.Task
  def run(args) do
    {opts, _rest} =
      OptionParser.parse!(args,
        strict: [
          wiki: :string,
          skip_names: :boolean,
          aliases_only: :boolean,
          categories_only: :boolean,
          add: :boolean
        ]
      )

    {:ok, _apps} = Application.ensure_all_started(:req)

    fetched = Date.utc_today() |> Date.to_iso8601()
    wikis = List.wrap(opts[:wiki] || Api.wikis())

    cond do
      opts[:aliases_only] ->
        for wiki <- wikis, do: fetch_aliases(wiki)

      opts[:categories_only] ->
        for wiki <- wikis, do: fetch_memberships(wiki, fetched)

      opts[:add] ->
        for wiki <- wikis do
          add_wiki(wiki, fetched)
          fetch_memberships(wiki, fetched)
        end

      true ->
        for wiki <- wikis do
          fetch_wiki(wiki, fetched)
          fetch_memberships(wiki, fetched)
        end

        if !opts[:skip_names] and "siala" in wikis, do: fetch_name_map()
    end

    :ok
  end

  # Runs after `fetch_wiki/2` because `Cache.write!/2` clears the directory of
  # anything it did not just write; the membership snapshot is preserved across
  # that (it is in the keep set) but there is no reason to write it twice.
  defp fetch_memberships(wiki, fetched) do
    case Map.get(@membership_categories, wiki, []) do
      [] ->
        :ok

      categories ->
        Mix.shell().info("[#{wiki}] fetching membership of #{length(categories)} categories…")

        listings = Map.new(categories, &{&1, Api.category_members(wiki, &1)})

        Cache.put_categories!(wiki, listings, fetched)

        for {category, members} <- Enum.sort_by(listings, &elem(&1, 0)) do
          pages = Enum.count(members, &(&1["ns"] == 0))

          Mix.shell().info(
            "[#{wiki}] #{category}: #{pages} pages, #{length(members) - pages} subcategories"
          )
        end

        :ok
    end
  end

  defp fetch_wiki(wiki, fetched), do: cache(wiki, titles(wiki), fetched)

  defp titles("fandom" = wiki) do
    Mix.shell().info("[#{wiki}] collecting titles from #{length(@fandom_categories)} categories…")
    from_categories = Api.category_tree(wiki, @fandom_categories, @max_depth)
    Enum.uniq(from_categories ++ @fandom_pages)
  end

  defp titles("siala" = wiki) do
    Mix.shell().info("[#{wiki}] collecting titles from #{length(@siala_categories)} categories…")
    from_categories = Api.category_tree(wiki, @siala_categories, @max_depth)
    from_hubs = Enum.flat_map(@siala_link_hubs, &Api.links(wiki, &1))

    Enum.uniq(from_categories ++ @siala_pages ++ from_hubs)
  end

  # The same title collection, minus everything the cache already holds. See the
  # module doc: a title already there keeps its bytes and its `revid`, because the
  # parsed snapshot cites them.
  defp add_wiki(wiki, fetched) do
    cached = wiki |> Cache.read_index!() |> MapSet.new(& &1.title)
    wanted = wiki |> titles() |> Enum.uniq() |> Enum.sort()
    missing = Enum.reject(wanted, &MapSet.member?(cached, &1))

    Mix.shell().info(
      "[#{wiki}] #{length(wanted)} titles wanted, #{MapSet.size(cached)} already cached, " <>
        "#{length(missing)} to fetch"
    )

    if missing == [] do
      :ok
    else
      {added, refused} = Cache.add!(wiki, entries(wiki, missing, fetched))

      # A redirect resolving onto a page already in the cache is the ordinary
      # case, not a problem — but it has to be *said*, or "we asked for 74 and
      # added 60" looks like fourteen silent losses.
      for title <- refused do
        Mix.shell().info("[#{wiki}] already cached, left untouched: #{title}")
      end

      Mix.shell().info(
        "[#{wiki}] added #{length(added)} pages to #{Cache.dir(wiki)}; " <>
          "#{length(refused)} resolved onto pages already there"
      )
    end
  end

  defp cache(wiki, titles, fetched) do
    entries = entries(wiki, titles, fetched)
    Cache.write!(wiki, entries)

    Mix.shell().info(
      "[#{wiki}] cached #{length(entries)} pages from #{length(Enum.uniq(titles))} requested " <>
        "titles (the rest were redirects onto pages already in the set) in #{Cache.dir(wiki)}"
    )
  end

  defp entries(wiki, titles, fetched) do
    titles = titles |> Enum.uniq() |> Enum.sort()
    Mix.shell().info("[#{wiki}] fetching wikitext for #{length(titles)} titles…")

    pages = Api.contents(wiki, titles)
    {present, missing} = Enum.split_with(pages, &revision/1)

    for page <- missing, do: Mix.shell().error("[#{wiki}] missing page: #{page["title"]}")

    resolved = Enum.map(present, & &1["title"])
    Mix.shell().info("[#{wiki}] fetching categories for #{length(resolved)} pages…")
    categories = Api.categories(wiki, resolved)

    Mix.shell().info("[#{wiki}] fetching redirect titles for #{length(resolved)} pages…")
    aliases = Api.redirects_to(wiki, resolved)

    present
    |> Enum.map(fn page ->
      revision = revision(page)

      %{
        title: page["title"],
        pageid: page["pageid"],
        revid: revision["revid"],
        fetched: fetched,
        categories: Map.get(categories, page["title"], []),
        aliases: Map.get(aliases, page["title"], []),
        content: get_in(revision, ["slots", "main", "content"]) || ""
      }
    end)
    |> Enum.uniq_by(& &1.title)
  end

  defp revision(page), do: page |> Map.get("revisions", []) |> List.first()

  # Adds the redirect titles to a cache that already exists. Kept separate from
  # `cache/3` so that a snapshot taken on one day can gain its aliases on another
  # without every page being re-downloaded — and without a wiki edit made in
  # between quietly rewriting the data underneath the parsed files.
  defp fetch_aliases(wiki) do
    titles = wiki |> Cache.read_index!() |> Enum.map(& &1.title)
    Mix.shell().info("[#{wiki}] fetching redirect titles for #{length(titles)} cached pages…")

    aliases = Api.redirects_to(wiki, titles)
    Cache.put_aliases!(wiki, aliases)

    total = aliases |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
    pages = Enum.count(aliases, fn {_title, names} -> names != [] end)

    Mix.shell().info(
      "[#{wiki}] #{total} redirect titles onto #{pages} of #{length(titles)} pages " <>
        "recorded in the cache index"
    )
  end

  # The Siala wiki keeps redirects between the English engine names and its own
  # Russian page titles (`Toughness` -> `Живучесть`). That is a ready-made EN↔RU
  # mapping we get for free, and the only non-guessed source for it — CLAUDE.md
  # forbids transliterating names by hand.
  #
  # Redirects point both ways: usually EN page -> RU page, but a few Siala pages
  # keep the English title and are aliased from Russian (`Кислотный туман` ->
  # `Acid Fog`). Both express the same fact, so the Russian-sourced ones are simply
  # recorded flipped. Redirects between two names of the same language (`Перформ`
  # -> `Исполнение`) are not a translation and are dropped.
  defp fetch_name_map do
    Mix.shell().info("[siala] collecting redirects for the EN↔RU name map…")
    redirects = Api.redirect_titles("siala")
    resolved = Api.resolve_redirects("siala", redirects)

    {pairs, conflicts} =
      resolved
      |> Enum.flat_map(fn {from, to} ->
        cond do
          latin?(from) and cyrillic?(to) -> [{from, to}]
          cyrillic?(from) and latin?(to) -> [{to, from}]
          true -> []
        end
      end)
      |> Enum.group_by(fn {en, _ru} -> en end, fn {_en, ru} -> ru end)
      |> Enum.split_with(fn {_en, russians} -> length(Enum.uniq(russians)) == 1 end)

    # Two different Russian names for one English name is a wiki contradiction, not
    # something to resolve by picking a favourite.
    for {en, russians} <- conflicts do
      Mix.shell().error(
        "[siala] ambiguous name mapping, skipped: #{en} -> #{Enum.join(Enum.uniq(russians), " / ")}"
      )
    end

    pairs = pairs |> Enum.map(fn {en, [ru | _]} -> {en, ru} end) |> Enum.sort()

    path = Path.join(File.cwd!(), @name_map_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Json.encode!({:obj, pairs}))

    Mix.shell().info(
      "[siala] name map: #{length(pairs)} EN↔RU pairs from #{map_size(resolved)} redirects " <>
        "written to #{@name_map_path}"
    )
  end

  defp latin?(text), do: Regex.match?(~r/\p{Latin}/u, text) and not cyrillic?(text)
  defp cyrillic?(text), do: Regex.match?(~r/\p{Cyrillic}/u, text)
end
