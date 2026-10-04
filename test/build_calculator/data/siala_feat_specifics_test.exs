defmodule BuildCalculator.Data.SialaFeatSpecificsTest do
  @moduledoc """
  `:siala_specifics` — the shard page's own «Особенности», carried beside a
  feat record wherever the parser had Fandom prose to compare it with (task
  4.67 took the pages whose numbers differ, task 4.70 added those whose
  numbers match and the page's other labels; `Data.Loader.Feats.put_siala_specifics/2`).

  Read only by the feat info popover (`Labels.feat_info/2`); the census here is
  against the machine layer itself, page by page, so a page the loader dropped
  or a record it filled from the wrong page shows up by name.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data

  @generated "priv/rules/siala_41/generated/feats.json"
  @cache "priv/wiki_cache/siala"

  setup_all do
    pages = @generated |> File.read!() |> Jason.decode!() |> Map.fetch!("feats")
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla"), pages: pages}
  end

  defp differing(pages), do: Enum.filter(pages, &(&1["numbers_differ"] == true))

  # Every page with «Особенности» and Fandom prose to compare it with —
  # `numbers_differ` true or false; null means there was nothing to compare.
  defp carried(pages),
    do: Enum.filter(pages, &(is_binary(&1["special_raw"]) and is_boolean(&1["numbers_differ"])))

  # The record a page lands on: `vanilla_id` when the vanilla dictionary has it,
  # the same rule `Loader.Feats.feat_target_id/2` applies — five
  # `Epic energy resistance (…)` pages share one record.
  defp target(page, ruleset) do
    Enum.find(ruleset.feats, fn {id, _} -> Atom.to_string(id) == page["vanilla_id"] end) ||
      Enum.find(ruleset.feats, fn {id, _} -> Atom.to_string(id) == page["id"] end)
  end

  defp entry_of(page, ruleset) do
    {_id, feat} = target(page, ruleset)

    Enum.find(Map.get(feat, :siala_specifics, []), fn entry ->
      entry["quote"] == page["special_raw"] and entry["source"] == page["source"]
    end)
  end

  test "every page whose numbers differ lands verbatim, with its own source, on its record",
       %{siala: siala, pages: pages} do
    pages = differing(pages)

    # The count the task was set on (find 4.57); a new page on the wiki moves
    # it, and that is a reason to look, not to rewrite the number blindly.
    assert length(pages) == 33

    landed = for page <- pages, entry_of(page, siala), do: page["id"]

    assert Enum.sort(landed) == Enum.sort(Enum.map(pages, & &1["id"]))
  end

  # Task 4.70: nine pages state the shard's own mechanic in «Особенности» with
  # numbers matching Fandom's (or none on either side) — Wholeness of body's
  # Heal and Restoration, Summon shadow's teleporting shadow. They land too,
  # and carry the parser's flag so the popover can tell them apart.
  test "pages whose numbers match land too, each with the parser's own flag", %{
    siala: siala,
    pages: pages
  } do
    matching =
      Enum.filter(pages, &(is_binary(&1["special_raw"]) and &1["numbers_differ"] == false))

    assert Enum.sort(Enum.map(matching, & &1["id"])) ==
             ~w(craft_harper_item dark_blessing divine_grace hide_in_plain_sight keen_sense
                monk_ac_bonus summon_shadow weapon_finesse wholeness_of_body)

    for page <- carried(pages) do
      entry = entry_of(page, siala)
      assert entry, page["id"]
      assert entry["numbers_differ"] == page["numbers_differ"], page["id"]
    end
  end

  test "exactly the records those pages land on carry the key — 38, five pages share one",
       %{siala: siala, pages: pages} do
    expected =
      pages |> carried() |> Enum.map(&elem(target(&1, siala), 0)) |> Enum.uniq() |> Enum.sort()

    carrying =
      for {id, feat} <- siala.feats, Map.has_key?(feat, :siala_specifics), do: id

    assert Enum.sort(carrying) == expected
    assert length(expected) == 29 + 9
    assert length(siala.feats[:epic_energy_resistance].siala_specifics) == 5
  end

  # `numbers_differ: null` is «nothing to compare against», and today all five
  # such pages with «Особенности» are shard-only feats: no Fandom prose to
  # stand beside. Their text travels in `:siala_pages` instead (task 4.71,
  # `siala_feat_pages_test.exs`), never in this key.
  test "pages with nothing to compare against carry nothing — the five shard-only feats",
       %{siala: siala, pages: pages} do
    others = Enum.filter(pages, &(is_binary(&1["special_raw"]) and &1["numbers_differ"] == nil))

    # Positive control: the set is not empty, so the refutes below check something.
    assert Enum.sort(Enum.map(others, & &1["id"])) ==
             ~w(instinctive_throw riding_sprint shades_feat smile_of_death teleportation)

    for page <- others do
      {id, feat} = target(page, siala)
      refute Map.has_key?(feat, :siala_specifics), "#{page["id"]} → #{id}"
      assert feat.siala_only?, "#{page["id"]} → #{id}"
      assert feat.description == nil, "#{page["id"]} → #{id}"
    end
  end

  # Task 4.70, item 1: the shard's numbers outside «Особенности» — duration,
  # cooldown, uses — travel in the same entry, label and all.
  test "Called shot carries its duration label beside its «Особенности»", %{siala: siala} do
    assert [entry] = siala.feats[:called_shot].siala_specifics
    assert entry["labels"] == [%{"label" => "продолжительность", "quote" => "8 секунд."}]
    assert entry["numbers_differ"] == true
  end

  test "every label of a carried page lands, except the one naming a feat it unlocks",
       %{siala: siala, pages: pages} do
    for page <- carried(pages) do
      expected =
        for {label, quote} <- Enum.sort(page["extra_labels"] || %{}),
            label != "требуется для умения",
            do: %{"label" => label, "quote" => quote}

      assert entry_of(page, siala)["labels"] == expected, page["id"]
    end

    # Positive control for the exclusion: the one page that has it.
    whirlwind = Enum.find(pages, &(&1["id"] == "whirlwind_attack"))
    assert Map.has_key?(whirlwind["extra_labels"], "требуется для умения")
    assert entry_of(whirlwind, siala)["labels"] == []
  end

  # The popover prints a label as the page does — «Продолжительность:» — from
  # the parser's lower-cased key with its first letter raised
  # (`Labels.feat_info/2`). That is verbatim only if the page wrote it so;
  # checked against each page's own wikitext rather than trusted.
  test "every carried label is printed on its page exactly as the popover prints it",
       %{siala: siala, pages: pages} do
    index = Path.join(@cache, "_index.json") |> File.read!() |> Jason.decode!()

    checked =
      for page <- carried(pages),
          %{"label" => label} <- entry_of(page, siala)["labels"] do
        title = page["source"]["page"]
        cached = Enum.find(index, &(&1["title"] == title or title in (&1["aliases"] || [])))
        assert cached, title
        wikitext = File.read!(Path.join(@cache, cached["file"]))
        {first, rest} = String.split_at(label, 1)
        printed = String.upcase(first) <> rest
        assert wikitext =~ "'''#{printed}:'''", "#{page["id"]}: «#{printed}:»"
        label
      end

    # Positive control: there is something to check (17 pages, 21 labels).
    assert length(checked) == 21
  end

  # The parser's own promise (`mix wiki.parse`, `@siala_feat_field_note`):
  # these numbers are kept out of `changes`, so they never reach
  # `siala_unapplied` and never hang a gap on a build. The field sits beside
  # `siala_changes`, not inside it.
  test "the quote is not a shard fact: nothing about it reaches siala_changes or siala_unapplied",
       %{siala: siala} do
    for id <- [:point_blank_shot, :called_shot, :wholeness_of_body] do
      feat = siala.feats[id]
      assert [%{"quote" => quote} = entry] = feat.siala_specifics
      quotes = [quote | Enum.map(entry["labels"], & &1["quote"])]

      for change <- feat.siala_changes ++ feat.siala_unapplied do
        refute change["quote"] in quotes, "#{id}"
      end
    end

    assert [%{"quote" => quote}] = siala.feats[:point_blank_shot].siala_specifics
    assert quote =~ "+5"
  end

  test "the vanilla ruleset never grows the key", %{vanilla: vanilla} do
    refute Enum.any?(vanilla.feats, fn {_id, feat} -> Map.has_key?(feat, :siala_specifics) end)
    # Positive control: the records exist there, Fandom's prose and all.
    assert vanilla.feats[:point_blank_shot].description =~ "within 15 feet"
    assert vanilla.feats[:wholeness_of_body].description =~ "twice her class level"
  end
end
