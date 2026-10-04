defmodule BuildCalculator.Data.SialaFeatPagesTest do
  @moduledoc """
  `:siala_pages` — the shard's own page, carried on the eleven shard-only feat
  records, whose feat info popover has no Fandom prose to show and shows
  this instead (task 4.71, Dan 04.10.2026: «Ок, давай добавим попап»;
  `Data.Loader.Feats.put_siala_pages/2`).

  Checked page by page against the machine layer itself, so a page the loader
  dropped, or a part it hid that it should not have, shows up by name — and
  against the wiki cache for the one transformation the popover applies to a
  label's name.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data

  @generated "priv/rules/siala_41/generated/feats.json"
  @cache "priv/wiki_cache/siala"

  @eleven ~w(instinctive_throw riding_sprint shades_feat siala_axe_proficiency
             siala_blade_proficiency siala_hammer_proficiency siala_polearm_proficiency
             siala_ranged_proficiency siala_spell_school_focus smile_of_death teleportation)a

  @proficiencies ~w(siala_axe_proficiency siala_blade_proficiency siala_hammer_proficiency
                    siala_polearm_proficiency siala_ranged_proficiency)

  setup_all do
    pages = @generated |> File.read!() |> Jason.decode!() |> Map.fetch!("feats")
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla"), pages: pages}
  end

  defp page(pages, id), do: Enum.find(pages, &(&1["id"] == id))

  test "exactly the eleven shard-only records carry the key, one page each",
       %{siala: siala} do
    carrying = for {id, feat} <- siala.feats, Map.has_key?(feat, :siala_pages), do: id
    assert Enum.sort(carrying) == Enum.sort(@eleven)

    only = for {id, feat} <- siala.feats, feat.siala_only?, do: id
    assert Enum.sort(only) == Enum.sort(@eleven)

    for id <- @eleven do
      assert [_one] = siala.feats[id].siala_pages, "#{id}"
      # No Fandom prose behind any of them — the reason the key exists.
      assert siala.feats[id].description == nil, "#{id}"
    end
  end

  test "the vanilla ruleset never grows the key", %{vanilla: vanilla} do
    refute Enum.any?(vanilla.feats, fn {_id, feat} -> Map.has_key?(feat, :siala_pages) end)
    # Positive control: vanilla has feats, Fandom's prose and all.
    assert vanilla.feats[:point_blank_shot].description =~ "within 15 feet"
  end

  test "each page lands verbatim: «Особенности», every label, every section but one",
       %{siala: siala, pages: pages} do
    for id <- @eleven do
      source = page(pages, Atom.to_string(id))
      [carried] = siala.feats[id].siala_pages

      assert carried["quote"] == source["special_raw"], "#{id}"
      assert carried["source"] == source["source"], "#{id}"

      assert carried["labels"] ==
               for(
                 {label, quote} <- Enum.sort(source["extra_labels"] || %{}),
                 do: %{"label" => label, "quote" => quote}
               ),
             "#{id}"

      assert carried["sections"] ==
               for(
                 %{"title" => title, "body" => body} <- source["sections"],
                 title != "Возможность взятия фита",
                 do: %{"title" => title, "body" => body}
               ),
             "#{id}"
    end

    # «Особенности» on exactly the five that have one on the page.
    with_quote = for id <- @eleven, is_binary(hd(siala.feats[id].siala_pages)["quote"]), do: id

    assert Enum.sort(with_quote) ==
             ~w(instinctive_throw riding_sprint shades_feat smile_of_death teleportation)a
  end

  # 🔴 «Возможность взятия фита» names the slots that take a proficiency and
  # misses the Paladin's epic bonus slot (case AK1, CLAUDE.md §3) — so it is
  # not carried. Positive control first: the machine layer does have it, on
  # all five proficiency pages, so the refute below checks something.
  test "the slot list of the proficiency pages is left out — it is incomplete (AK1)",
       %{siala: siala, pages: pages} do
    for id <- @proficiencies do
      titles = Enum.map(page(pages, id)["sections"], & &1["title"])
      assert "Возможность взятия фита" in titles, id

      [carried] = siala.feats[String.to_existing_atom(id)].siala_pages
      assert Enum.map(carried["sections"], & &1["title"]) == ["Общая информация"], id
    end
  end

  # The coordinator's reading of Dan's word (task 4.71): Instinctive throw's
  # «Пометка» is shown as the shard's quote, while the model still neither
  # prints nor checks that threshold (case L3). Hiding it is one line in
  # `@not_feat_text` (`Data.Loader.Feats`) — and this test is the one that
  # would then have to change with it.
  test "Instinctive throw carries its «Пометка» with the shard's own words",
       %{siala: siala} do
    [carried] = siala.feats[:instinctive_throw].siala_pages

    assert %{"label" => "пометка", "quote" => "Использовать умение можно с 15 уровня Монаха."} in carried[
             "labels"
           ]

    assert Enum.map(carried["sections"], & &1["title"]) == ["Общие"]
  end

  # Shades and Teleportation have no section at all — only labels.
  test "pages without sections carry their labels alone", %{siala: siala} do
    for id <- [:shades_feat, :teleportation] do
      [carried] = siala.feats[id].siala_pages
      assert carried["sections"] == [], "#{id}"
      assert carried["labels"] != [], "#{id}"
    end

    [teleportation] = siala.feats[:teleportation].siala_pages

    assert Enum.map(teleportation["labels"], & &1["label"]) == [
             "количество",
             "общая дистанция"
           ]
  end

  # The one transformation the popover applies to a page part's name: a
  # label's first letter raised (the parser lower-cased the page's own word).
  # Checked against the page's wikitext like the 21 labels of task 4.70 —
  # and, unlike them, two labels of Instinctive throw are written with a
  # capital second word on the page («Звезда Беспорядочности»), which the
  # lower-cased key cannot give back. Named here rather than hidden; the
  # page's own spelling needs the parser to keep it (a data-miner task).
  test "every carried label is on its page — case aside for the two named ones",
       %{siala: siala} do
    index = Path.join(@cache, "_index.json") |> File.read!() |> Jason.decode!()

    case_differs = [
      {"instinctive_throw", "звезда беспорядочности"},
      {"instinctive_throw", "звезда ошеломления"}
    ]

    checked =
      for id <- @eleven,
          [carried] = siala.feats[id].siala_pages,
          %{"label" => label} <- carried["labels"] do
        title = carried["source"]["page"]
        cached = Enum.find(index, &(&1["title"] == title or title in (&1["aliases"] || [])))
        assert cached, title
        wikitext = File.read!(Path.join(@cache, cached["file"]))
        {first, rest} = String.split_at(label, 1)
        printed = String.upcase(first) <> rest

        if {Atom.to_string(id), label} in case_differs do
          refute wikitext =~ "'''#{printed}:'''",
                 "#{id}: «#{printed}:» now matches — drop it from the list"

          assert String.downcase(wikitext) =~ "'''#{label}:'''", "#{id}: «#{label}:»"
        else
          assert wikitext =~ "'''#{printed}:'''", "#{id}: «#{printed}:»"
        end

        label
      end

    # Positive control: 8 labels on 4 pages.
    assert length(checked) == 8
  end

  # A quote, not a fact: the rules never read the key.
  test "nothing in the rules core reads the key" do
    sources = Path.wildcard("lib/build_calculator/rules/**/*.ex")
    assert sources != []
    refute Enum.any?(sources, &(File.read!(&1) =~ "siala_pages"))
  end
end
