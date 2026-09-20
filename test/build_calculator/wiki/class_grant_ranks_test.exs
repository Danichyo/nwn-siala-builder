defmodule BuildCalculator.Wiki.ClassGrantRanksTest do
  @moduledoc """
  `granted_feat_ranks` as `mix wiki.parse` writes it into the vanilla snapshot.

  Fandom keeps **one page per ability family**, so `Defensive Awareness` I, II and
  III are one page, one feat id and three grants — and `granted_feats`, keyed by
  feat id alone, cannot say which of the three a level hands out. The rank is on
  the page all the same, and this file checks that it arrives:

      dwarven defender  2/5/10          [[defensive awareness]] I / II / III
      pale master       5/6/7/8/9/10    [[deathless vigor]] (+3HP), …, 15/20/25/30 (+5HP)
      barbarian         1/4/8/12        [[barbarian rage]] (1x/day), …, 15/16/20 [[greater rage]]

  Every expectation below is read off `priv/rules/vanilla/classes.json`, which is
  read off the cached wikitext — nothing here is a number this project chose.

  ⚠️ 08.08.2026 (AGENT_QUEUE.md §7, волна 10): `pale_master` and `barbarian`
  above used to show only their FIRST and LAST rank (5/15, 1/15) — the class
  page repeats a rank family's name in plain text once the link has been used
  once, and `ClassPage.feat_grants/1` only followed links. Fixed generally, not
  per class: `deathless_vigor`, `barbarian_rage`, `bone_skin`, `sacred_defense`,
  `divine_wrath`, `wild_shape`, `uncanny_dodge` and seven more families across
  twelve classes all gained the levels their own feat page already named. Every
  one of the 19 changed (class, feat) pairs was cross-checked against that
  feat's own page independently of the class table it came from — see the git
  history of this file's pinned counts below for what changed and why.
  """
  use ExUnit.Case, async: true

  setup_all do
    classes =
      Path.join(File.cwd!(), "priv/rules/vanilla/classes.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.new(&{&1["id"], &1})

    %{classes: classes}
  end

  defp ranks(classes, id), do: classes |> Map.fetch!(id) |> Map.get("granted_feat_ranks", %{})

  defp entries(classes) do
    for {id, class} <- classes,
        {level, feats} <- Map.get(class, "granted_feat_ranks", %{}),
        {feat, rank} <- feats,
        do: {id, level, feat, rank}
  end

  describe "the shape of the field" do
    test "every rank belongs to a grant the same class record already lists", %{classes: classes} do
      for {id, level, feat, _rank} <- entries(classes) do
        granted = classes |> Map.fetch!(id) |> Map.fetch!("granted_feats") |> Map.get(level, [])

        assert feat in granted,
               "#{id} #{level}: ранг у #{feat}, которого нет в granted_feats этого уровня"
      end
    end

    test "the level keys are the same class levels granted_feats uses", %{classes: classes} do
      for {id, level, _feat, _rank} <- entries(classes) do
        assert {_int, ""} = Integer.parse(level), "#{id}: ключ уровня #{inspect(level)} не число"
      end
    end

    test "no rank is empty", %{classes: classes} do
      for {id, level, feat, rank} <- entries(classes) do
        assert rank != "", "#{id} #{level} #{feat}: пустой ранг вместо отсутствия записи"
      end
    end
  end

  # The negative half, and the one that keeps the field meaning what it says: a
  # link with nothing after it says nothing about rank, and a record standing
  # there anyway would be a rank this project made up.
  describe "a grant the page did not label gets no entry" do
    test "a bare link at a level that has no other grant leaves no level key", %{classes: classes} do
      # champion of Torm 5 is `[[divine wrath]]` — the (+2) only appears at 15.
      assert ranks(classes, "champion_of_torm")["5"] == nil
      # dwarven defender 1 is `[[defensive stance]]`; its ranks start at 2.
      assert ranks(classes, "dwarven_defender")["1"] == nil
    end

    test "a class that labels no grant at all has no key", %{classes: classes} do
      # The paladin hands out four feats and ranks none of them.
      refute Map.has_key?(Map.fetch!(classes, "paladin"), "granted_feat_ranks")
      # The fighter hands out nothing at all under vanilla.
      refute Map.has_key?(Map.fetch!(classes, "fighter"), "granted_feat_ranks")
    end

    test "the disambiguating suffix the wiki hides is not read as a rank", %{classes: classes} do
      # `[[animal companion (feat)|animal companion]]` — display and page title
      # differ, but only by the `(feat)` the link hides. Nothing was labelled.
      assert ranks(classes, "druid")["1"] == nil
      # Same link shape *with* a rank behind it: only the `I` is the rank.
      assert ranks(classes, "barbarian")["11"] == %{"damage_reduction_barbarian" => "I"}
    end
  end

  describe "the rank is copied exactly as the page prints it" do
    test "a roman numeral stays a roman numeral", %{classes: classes} do
      assert ranks(classes, "dwarven_defender") == %{
               "2" => %{"defensive_awareness" => "I"},
               "5" => %{"defensive_awareness" => "II"},
               "10" => %{"defensive_awareness" => "III"}
             }
    end

    test "a magnitude keeps its brackets and its spacing", %{classes: classes} do
      assert ranks(classes, "pale_master")["15"] == %{"deathless_vigor" => "(+5HP)"}
      assert ranks(classes, "monk")["10"] == %{"ki_strike" => "+1"}
      assert ranks(classes, "weapon_master")["5"] == %{"superior_weapon_focus" => "(+1 AB)"}
      assert ranks(classes, "purple_dragon_knight")["2"] == %{"inspire_courage" => "1/day"}
    end

    # Bone skin is +2 AC at pale master 1 and +2 AC again at 12 — the page names
    # no ordinal, and inventing "I"/"II" to tell them apart would be inventing a
    # game fact. Two identical labels at two levels is what the source says.
    test "two ranks the page wrote identically stay identical", %{classes: classes} do
      assert ranks(classes, "pale_master")["1"] == %{"bone_skin" => "(+2AC)"}
      assert ranks(classes, "pale_master")["12"] == %{"bone_skin" => "(+2AC)"}
    end
  end

  # Three grants are labelled by the *link title* rather than by anything after
  # it: the author linked the rank's own redirect, which resolves onto the family
  # page. `(4x/day)` alone would read like the rage a barbarian has had since
  # level 1, and at shifter 13 and druid 20 there is no tail at all — so the
  # display text is kept, and it is the wiki's own wording, not ours.
  describe "a rank the page wrote as the link title" do
    test "greater rage, infinite humanoid shape, improved elemental shape", %{classes: classes} do
      assert ranks(classes, "barbarian")["15"] == %{"barbarian_rage" => "greater rage (4x/day)"}

      assert ranks(classes, "shifter")["13"] == %{
               "infinite_greater_wildshape" => "infinite humanoid shape"
             }

      assert ranks(classes, "druid")["20"] == %{
               "elemental_shape" => "improved elemental shape"
             }
    end

    test "the same family linked under its own title keeps a plain tail", %{classes: classes} do
      assert ranks(classes, "shifter")["4"] == %{"infinite_greater_wildshape" => "I"}
      assert ranks(classes, "shifter")["16"] == %{"infinite_greater_wildshape" => "IV"}
      assert ranks(classes, "barbarian")["1"] == %{"barbarian_rage" => "(1x/day)"}
    end
  end

  describe "coverage of the grants that need it" do
    # A grant of a feat id the class already granted lower down is the only place
    # where `granted_feats` is actively ambiguous, and it is what the field is
    # for. Recomputed here from `granted_feats` alone so the check does not
    # depend on the loader's own list.
    defp repeats(class) do
      class
      |> Map.fetch!("granted_feats")
      |> Enum.sort_by(fn {level, _} -> String.to_integer(level) end)
      |> Enum.reduce({MapSet.new(), []}, fn {level, feats}, {seen, again} ->
        {fresh, repeated} = Enum.split_with(feats, &(not MapSet.member?(seen, &1)))
        {MapSet.union(seen, MapSet.new(fresh)), again ++ for(f <- repeated, do: {level, f})}
      end)
      |> elem(1)
    end

    test "every repeated grant is told apart from the one before it", %{classes: classes} do
      repeated =
        for {id, class} <- classes, {level, feat} <- repeats(class), do: {id, level, feat}

      for {id, level, feat} <- repeated do
        assert ranks(classes, id)[level][feat],
               "#{id} #{level}: #{feat} выдан повторно и ничем не отличён от прошлого раза"
      end

      # Pinned: a parser change that starts collapsing more ids, or a cache
      # update that adds a family, shows up here instead of passing quietly.
      #
      # ⚠️ 10 -> 87 (08.08.2026, AGENT_QUEUE.md §7, волна 10): `feat_grants/1`
      # used to see a rank family's name only where it was linked, so a class
      # page repeating the name in plain text (`bone skin (+2AC)` with no
      # `[[…]]`, right after the linked one two rows up) fell through to
      # `prose` and never became a second grant at all — this file could not
      # even count it as "repeated". Now it does, and every one of the 87 was
      # cross-checked against the feat's own page as part of the fix.
      assert length(repeated) == 87
    end

    # Pinned for the same reason as the count above — and because these are
    # the whole of what the 23 pages label, so a drop is a regression and a rise
    # means the cache moved.
    #
    # ⚠️ 26 -> 103 (08.08.2026, AGENT_QUEUE.md §7, волна 10), same cause as the
    # count above: the eight extra ranks `bone_skin` alone gained are 8 of the
    # 77 new entries. The class COUNT held at 13 — every class that gained a
    # rank this way (`druid`, `barbarian`, `champion_of_torm`, …) already
    # carried at least one rank before the fix, from a family whose SECOND
    # appearance was already linked (`druid`'s own `elemental_shape` at level
    # 20, for one).
    test "a hundred and three grants across thirteen classes carry a rank", %{classes: classes} do
      assert length(entries(classes)) == 103
      assert Enum.count(classes, fn {_id, c} -> Map.has_key?(c, "granted_feat_ranks") end) == 13
    end
  end
end
