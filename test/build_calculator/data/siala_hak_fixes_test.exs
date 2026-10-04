defmodule BuildCalculator.Data.SialaHakFixesTest do
  @moduledoc """
  Правки задачи 4.49 — находки (a) сверки хака Сиалы `mix hak2da.diff`:

    * Lasting inspiration на Сиале — снова бард 20 (`siala_41/feats.json`);
    * Mount actions — не выбирается при левелапе на обоих ruleset'ах
      (`vanilla/feat_level_up_selectable.json`, новый ванильный слой);
    * Summon mount паладину Сиалы не выдаётся (`siala_41/classes.json`,
      `what: "granted_feat_removed"`);
    * Mounted combat и Mounted archery на Сиале не выбираются
      (`siala_41/feats.json`, `level_up_selectable: false`);
    * Brew Potion — бонусный слот Друида и Арфиста, не Волшебника
      (`what: "bonus_for"`);
    * бонусный слот по значению: Weapon focus и Improved critical (trident)
      у Чемпиона Торма, Overwhelming critical (club) у паладина, Epic skill
      focus (Верховая езда, Алхимия) у барда, Арфиста, вора и Теневого
      танцора (`what: "bonus_slot_refusals"`).

  И два вердикта «до печатаемого не доезжает» пункта (1) постановки —
  Point blank shot и Called shot, — доказанные вызовом, а не чтением. С задачи
  4.57 их числа шарда (+5 и +2) лежат в слое `siala_41/feat_attack_bonuses.json`,
  и вызов сравнивает записи Сиалы с ванильными, то есть с состоянием до 4.57.

  Сценарии собираются по одному левелапу (`Rules.validate_level_up/3`), как
  у игрока. Сторожа загрузчика портят копию `priv/rules`
  (`BuildCalculator.TmpDir`). Сверка строк таблиц — только при обеих выгрузках
  (`priv/hak/2da`, `priv/base_2da`), иначе её `describe` пропускается.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.GameFiles.TwoDA
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatSlots}

  @hak Path.expand("../../../priv/hak/2da", __DIR__)
  @base Path.expand("../../../priv/base_2da", __DIR__)
  @dumps? File.regular?(Path.join(@hak, "manifest.json")) and
            File.regular?(Path.join(@base, "manifest.json"))

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  # Билд, собранный по одному левелапу: каждый уровень обязан пройти
  # `validate_level_up/3` на том, что набрано до него.
  defp level_up!(ruleset, classes, fields) do
    Enum.reduce(classes, Build.new(fields), fn class, build ->
      assert Rules.validate_level_up(build, class, ruleset) == :ok,
             "уровень #{Build.character_level(build) + 1} (#{class}) не прошёл"

      Build.add_level(build, class)
    end)
  end

  @abilities %{str: 14, dex: 14, con: 14, int: 12, wis: 10, cha: 16}

  defp copy_rules do
    root = BuildCalculator.TmpDir.unique_path!()
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp edit_json!(root, rel, fun) do
    path = Path.join(root, rel)

    path
    |> File.read!()
    |> Jason.decode!()
    |> fun.()
    |> Jason.encode!()
    |> then(&File.write!(path, &1))
  end

  defp table(dir, name), do: dir |> Path.join(name <> ".2da") |> File.read!() |> TwoDA.parse!()

  # ------------------------------------------------- Lasting inspiration --

  describe "Lasting inspiration на Сиале — бард 20 (п. 3)" do
    # Исполнение — навык одного барда: ранги идут только на бардовских уровнях.
    # Потолок класса — уровень + 3, так что 25 рангов набираются ровно к 22-му.
    defp perform_ranks(classes) do
      first_bard = Enum.find_index(classes, &(&1 == :bard)) + 1

      for {class, level} <- Enum.with_index(classes, 1), class == :bard, into: %{} do
        {level, %{perform: if(level == first_bard, do: level + 3, else: 1)}}
      end
    end

    defp bard_build(ruleset, fighters) do
      classes = List.duplicate(:fighter, fighters) ++ List.duplicate(:bard, 22 - fighters)

      level_up!(ruleset, classes,
        race: :human,
        alignment: :chaotic_good,
        base_abilities: @abilities,
        skills: perform_ranks(classes)
      )
    end

    test "сценарий: бард 19 на 22-м уровне — отказ, бард 20 — можно; как у ванили", %{
      siala: siala,
      vanilla: vanilla
    } do
      for ruleset <- [siala, vanilla] do
        bard_20 = bard_build(ruleset, 2)
        bard_19 = bard_build(ruleset, 3)

        assert Build.skill_ranks(bard_19, :perform, 22) == 25

        assert Rules.validate_feat_pick(bard_20, %{feat: :lasting_inspiration, at: 22}, ruleset) ==
                 :ok

        assert Rules.validate_feat_pick(bard_19, %{feat: :lasting_inspiration, at: 22}, ruleset) ==
                 {:error, [{:requires_class_level, :bard, 20}]}
      end
    end

    test "требование Сиалы — страница плюс ступень 20, у ванили то же", %{
      siala: siala,
      vanilla: vanilla
    } do
      expected = %{
        "character_level" => 21,
        "class_levels" => %{"bard" => 20},
        "feats" => ["bard_song"],
        "skills" => %{"perform" => 25}
      }

      assert siala.feats[:lasting_inspiration].prereqs == expected
      assert vanilla.feats[:lasting_inspiration].prereqs == expected
    end

    # Запись повторяет блок страницы дословно — он замещает `prereqs` целиком.
    # Парсер изменит машинный блок — запись устареет молча; здесь это красное.
    test "ручная запись повторяет машинный блок страницы слово в слово" do
      generated =
        "priv/rules/siala_41/generated/feats.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.fetch!("feats")
        |> Enum.find(&(&1["id"] == "lasting_inspiration"))
        |> Map.fetch!("changes")
        |> Enum.find(&(&1["what"] == "requirements"))

      manual =
        "priv/rules/siala_41/feats.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.fetch!("feats")
        |> Enum.find(&(&1["id"] == "lasting_inspiration"))
        |> Map.fetch!("changes")
        |> hd()

      assert manual["quote"] == generated["quote"]
      assert Enum.take(manual["value"], 3) == generated["value"]

      assert [%{"kind" => "class_level", "class" => "bard", "level" => 20}] =
               Enum.drop(manual["value"], 3)
    end

    # 🔴 Положительный контроль: без записи у Сиалы снова «любая песня барда».
    test "без ручной записи Сиала пускает барда 19" do
      root = copy_rules()

      edit_json!(root, "siala_41/feats.json", fn json ->
        update_in(json["feats"], &Enum.reject(&1, fn e -> e["id"] == "lasting_inspiration" end))
      end)

      siala = Loader.load!(root)["siala_41"]
      refute Map.has_key?(siala.feats[:lasting_inspiration].prereqs, "class_levels")

      assert Rules.validate_feat_pick(
               bard_build(siala, 3),
               %{feat: :lasting_inspiration, at: 22},
               siala
             ) == :ok
    end
  end

  # ------------------------------------------------------- Mount actions --

  describe "Mount actions — не выбирается при левелапе (п. 4, оба ruleset'а)" do
    test "сценарий: человек-воин 1 — ни общий, ни расовый слот не берут", %{
      siala: siala,
      vanilla: vanilla
    } do
      for ruleset <- [siala, vanilla] do
        build =
          level_up!(ruleset, [:fighter],
            race: :human,
            alignment: :true_neutral,
            base_abilities: @abilities
          )

        slots = FeatSlots.at(build, ruleset, 1)
        assert Enum.any?(slots, &(&1.id == :racial))

        for slot <- slots do
          refute FeatSlots.accepts?(ruleset, slot, :mount_actions), inspect(slot.id)

          assert {:error, reasons} =
                   Rules.validate_feat_pick(
                     build,
                     %{feat: :mount_actions, at: 1, slot: slot.id},
                     ruleset
                   )

          assert {:not_selectable_at_level_up, :mount_actions} in reasons
        end
      end
    end

    test "у ванили выдача на 1-м уровне осталась, у Сиалы её нет (за капом)", %{
      siala: siala,
      vanilla: vanilla
    } do
      assert :mount_actions in vanilla.classes[:fighter].granted_feats[1]
      refute :mount_actions in Map.get(siala.classes[:fighter].granted_feats, 1, [])
    end

    test "сторож слоя: значение не false, повтор, без строки feat.2da — сборка падает" do
      broken = [
        {&put_in(&1, ["feats", Access.at(0), "level_up_selectable"], true), ~r/must be false/},
        {&update_in(&1, ["feats"], fn [e] -> [e, e] end), ~r/stated twice/},
        {&update_in(&1, ["feats", Access.at(0)], fn e -> Map.drop(e, ~w(source source_2)) end),
         ~r/no source is a feat.2da row/},
        {&put_in(&1, ["feats", Access.at(0), "status"], "assumed"), ~r/not "verified"/},
        {&put_in(&1, ["feats", Access.at(0), "levelup"], false), ~r/does not read/}
      ]

      for {fun, message} <- broken do
        root = copy_rules()
        edit_json!(root, "vanilla/feat_level_up_selectable.json", fun)
        assert_raise RuntimeError, message, fn -> Loader.load!(root) end
      end
    end

    if @dumps? do
      test "строка 1089: у базы MinLevel 99 и ALLCLASSESCANUSE 0, у хака ещё MINSTR 99" do
        base = table(@base, "feat")
        hak = table(@hak, "feat")

        for t <- [base, hak] do
          assert TwoDA.get(t, 1089, "LABEL") == "HORSE_MENU"
          assert TwoDA.get(t, 1089, "MinLevel") == "99"
          assert TwoDA.get(t, 1089, "ALLCLASSESCANUSE") == "0"
        end

        assert TwoDA.get(base, 1089, "MINSTR") == nil
        assert TwoDA.get(hak, 1089, "MINSTR") == "99"
      end
    end
  end

  # -------------------------------------------------------- Summon mount --

  describe "Summon mount паладину Сиалы не выдаётся (п. 5)" do
    test "паладин 5: у ванили выдача есть, у Сиалы нет", %{siala: siala, vanilla: vanilla} do
      assert :summon_mount in vanilla.classes[:paladin].granted_feats[5]
      refute :summon_mount in Map.get(siala.classes[:paladin].granted_feats, 5, [])

      paladin =
        level_up!(siala, List.duplicate(:paladin, 5),
          race: :human,
          alignment: :lawful_good,
          base_abilities: @abilities
        )

      refute :summon_mount in Build.granted_feats(paladin, siala, 5)
    end

    test "сторож: снять выдачу, которой на этом уровне нет, — сборка падает" do
      root = copy_rules()

      edit_json!(root, "siala_41/classes.json", fn json ->
        update_in(json["classes"], fn classes ->
          Enum.map(classes, fn
            %{"id" => "paladin"} = c ->
              update_in(c["changes"], fn changes ->
                Enum.map(changes, fn
                  %{"what" => "granted_feat_removed"} = ch ->
                    put_in(ch, ["value", Access.at(0), "from"], 6)

                  ch ->
                    ch
                end)
              end)

            c ->
              c
          end)
        end)
      end)

      assert_raise RuntimeError,
                   ~r/granted_feat_removed says summon_mount is granted at class level 6/,
                   fn ->
                     Loader.load!(root)
                   end
    end

    if @dumps? do
      test "строки 1095 в cls_feat_pal.2da хака нет, у базы — List 3, 5-й уровень" do
        rows = fn t -> for {_i, r} <- TwoDA.rows(t), r["FeatIndex"] == "1095", do: r end

        assert rows.(table(@hak, "cls_feat_pal")) == []

        assert [%{"List" => "3", "GrantedOnLevel" => "5"}] = rows.(table(@base, "cls_feat_pal"))
        assert TwoDA.get(table(@hak, "feat"), 1095, "MINSTR") == "99"
      end
    end
  end

  # ---------------------------------------------- Mounted combat/archery --

  describe "Mounted combat и Mounted archery на Сиале не выбираются" do
    test "воин 2 с Верховой ездой 4: у ванили можно, у Сиалы — нет", %{
      siala: siala,
      vanilla: vanilla
    } do
      for ruleset <- [siala, vanilla] do
        build =
          level_up!(ruleset, [:fighter, :fighter],
            race: :human,
            alignment: :true_neutral,
            base_abilities: @abilities,
            skills: %{1 => %{ride: 4}}
          )

        verdict = Rules.validate_feat_pick(build, %{feat: :mounted_combat, at: 2}, ruleset)

        if ruleset == siala,
          do: assert(verdict == {:error, [{:not_selectable_at_level_up, :mounted_combat}]}),
          else: assert(verdict == :ok)
      end

      refute siala.feats[:mounted_archery].level_up_selectable?
      assert vanilla.feats[:mounted_archery].level_up_selectable?
    end

    if @dumps? do
      test "MINSTR 99 — правка шарда: у базы порога нет" do
        for row <- [1087, 1088] do
          assert TwoDA.get(table(@hak, "feat"), row, "MINSTR") == "99"
          assert TwoDA.get(table(@base, "feat"), row, "MINSTR") == nil
        end
      end
    end
  end

  # --------------------------------------------------------- Brew Potion --

  describe "Brew Potion — бонусный слот Друида и Арфиста, не Волшебника" do
    test "волшебник 5: бонусный слот Сиалы не берёт, ванильный — берёт", %{
      siala: siala,
      vanilla: vanilla
    } do
      assert siala.feats[:brew_potion].bonus_for == MapSet.new([:druid, :harper_scout])
      assert vanilla.feats[:brew_potion].bonus_for == MapSet.new([:wizard])

      for ruleset <- [siala, vanilla] do
        build =
          level_up!(ruleset, List.duplicate(:wizard, 5),
            race: :human,
            alignment: :true_neutral,
            base_abilities: %{@abilities | int: 16}
          )

        slot = Enum.find(FeatSlots.at(build, ruleset, 5), &match?({:class_bonus, :wizard}, &1.id))
        assert slot

        assert FeatSlots.accepts?(ruleset, slot, :brew_potion) == (ruleset == vanilla)
      end
    end

    test "сторож: `from` разошёлся со списком под записью — сборка падает" do
      root = copy_rules()

      edit_json!(root, "siala_41/feats.json", fn json ->
        update_in(json["feats"], fn feats ->
          Enum.map(feats, fn
            %{"id" => "brew_potion"} = e ->
              update_in(e["changes"], fn changes ->
                Enum.map(changes, fn
                  %{"what" => "bonus_for"} = ch -> put_in(ch, ["value", "from"], ["sorcerer"])
                  ch -> ch
                end)
              end)

            e ->
              e
          end)
        end)
      end)

      assert_raise RuntimeError, ~r/brew_potion \/ bonus_for says it replaces/, fn ->
        Loader.load!(root)
      end
    end
  end

  # ------------------------------------------- bonus slot by value (8, 9) --

  describe "бонусный слот по значению (пп. 8 и 9)" do
    @refusals [
      {:weapon_focus, :champion_of_torm, :trident, :longsword},
      {:improved_critical, :champion_of_torm, :trident, :longsword},
      {:overwhelming_critical, :paladin, :club, :longsword},
      {:epic_skill_focus, :rogue, :ride, :hide},
      {:epic_skill_focus, :bard, :alchemy, :perform}
    ]

    test "Сиала: значение отбито в бонусном слоте класса, соседнее — нет, общий слот — нет",
         %{siala: siala, vanilla: vanilla} do
      for {feat, class, value, other} <- @refusals do
        slot = {:class_bonus, class}

        assert FeatSlots.choice_refusals(siala, slot, feat, value) ==
                 [{:not_in_class_bonus_slot, class}],
               "#{feat} #{value}"

        assert FeatSlots.choice_refusals(siala, slot, feat, other) == []
        assert FeatSlots.choice_refusals(siala, :general, feat, value) == []
        assert FeatSlots.choice_refusals(vanilla, slot, feat, value) == []
      end
    end

    test "сторож: класс не в бонусном списке или значение вне домена — сборка падает" do
      broken = [
        {%{"class" => "wizard", "choice" => "trident"}, ~r/not on that feat's bonus list/},
        {%{"class" => "champion_of_torm", "choice" => "tridnet"},
         ~r/not in the\s+feat's choice domain/}
      ]

      for {pair, message} <- broken do
        root = copy_rules()

        edit_json!(root, "siala_41/feats.json", fn json ->
          update_in(json["feats"], fn feats ->
            Enum.map(feats, fn
              %{"id" => "weapon_focus"} = e ->
                put_in(e, ["changes", Access.at(0), "value"], [pair])

              e ->
                e
            end)
          end)
        end)

        assert_raise RuntimeError, message, fn -> Loader.load!(root) end
      end
    end

    if @dumps? do
      test "хак: у Чемпиона Торма нет строк 1072/1074, у паладина 746 на месте 709" do
        indexes = fn t -> for {_i, r} <- TwoDA.rows(t), do: r["FeatIndex"] end

        divcha = indexes.(table(@hak, "cls_feat_divcha"))
        refute "1072" in divcha or "1074" in divcha
        assert "1072" in indexes.(table(@base, "cls_feat_divcha"))

        pal = indexes.(table(@hak, "cls_feat_pal"))
        assert "746" in pal
        refute "709" in pal
        assert "709" in indexes.(table(@base, "cls_feat_pal"))
      end
    end
  end

  # ----------------------------------------- п. 1: не доезжает — вызовом --

  # С задачи 4.57 числа шарда лежат в слое `siala_41/feat_attack_bonuses.json`
  # (+5 и +2 вместо ванильных +1 и −4), а у Point blank shot сменён и довод
  # `not_a_gap` (`feat_description` → `world_state`). Вердикт «до печатаемого
  # не доезжает» остаётся вызовом: билд Сиалы с ванильными записями (ровно
  # состояние до 4.57) печатает то же, что с записями шарда.
  describe "Point blank shot и Called shot — до печатаемого не доезжают (п. 1)" do
    defp archer(ruleset) do
      level_up!(ruleset, List.duplicate(:fighter, 6),
        race: :human,
        alignment: :true_neutral,
        base_abilities: %{@abilities | dex: 16},
        gear: %BuildCalculator.Rules.Gear{weapon: :longbow}
      )
      |> Build.put_feat(1, :general, :siala_ranged_proficiency)
      |> Build.put_feat(1, :racial, :point_blank_shot)
      |> Build.put_feat(3, :general, :called_shot)
    end

    defp unmodelled(ruleset, id), do: Enum.find(ruleset.attack_bonuses.unmodelled, &(&1.id == id))

    defp with_record(ruleset, id, fun) do
      update_in(ruleset, [:attack_bonuses, :unmodelled], fn records ->
        Enum.map(records, fn
          %{id: ^id} = record -> fun.(record)
          record -> record
        end)
      end)
    end

    test "у Сиалы числа шарда, у ванили — ванильные; вердикт и условие те же", %{
      siala: siala,
      vanilla: vanilla
    } do
      for {id, shard, base} <- [{:point_blank_shot, 5, 1}, {:called_shot, 2, -4}] do
        assert unmodelled(siala, id).amount == %{kind: :flat, bonus: shard}
        assert unmodelled(vanilla, id).amount == %{kind: :flat, bonus: base}

        for field <- [:verdict, :condition, :affects, :source] do
          assert Map.fetch!(unmodelled(siala, id), field) ==
                   Map.fetch!(unmodelled(vanilla, id), field),
                 "#{id}.#{field}"
        end
      end

      assert unmodelled(siala, :point_blank_shot).not_a_gap["basis"] == "world_state"
      assert unmodelled(vanilla, :point_blank_shot).not_a_gap["basis"] == "feat_description"
      assert unmodelled(siala, :called_shot).not_a_gap == nil
    end

    test "лучник с обоими фитами: с записями Сиалы и с ванильными (до 4.57) печатается одно и то же",
         %{siala: siala, vanilla: vanilla} do
      build = archer(siala)
      assert Rules.illegal_feats(build, siala) == []

      before_4_57 =
        Enum.reduce([:point_blank_shot, :called_shot], siala, fn id, ruleset ->
          with_record(ruleset, id, fn _shard -> unmodelled(vanilla, id) end)
        end)

      refute before_4_57 == siala
      assert Rules.compute(build, before_4_57) == Rules.compute(build, siala)
    end

    # 🔴 Положительный контроль: сравнение выше не слепое. Лучник держит обе
    # записи, и без того, что гасит оговорку (`not_a_gap` у Point blank shot,
    # получатель `buff` у Called shot), каждая печаталась бы гэпом.
    test "без довода и без получателя-баффа у лучника печатались бы обе оговорки", %{siala: siala} do
      build = archer(siala)
      gap = &{:not_modelled, {:attack_bonus, &1}}

      assert Enum.filter(
               Rules.compute(build, siala).gaps,
               &(&1 in [gap.(:point_blank_shot), gap.(:called_shot)])
             ) == []

      exposed =
        siala
        |> with_record(:point_blank_shot, &%{&1 | not_a_gap: nil})
        |> with_record(:called_shot, &%{&1 | affects: ["attack_bonus"]})

      gaps = Rules.compute(build, exposed).gaps
      assert gap.(:point_blank_shot) in gaps
      assert gap.(:called_shot) in gaps
    end
  end
end
