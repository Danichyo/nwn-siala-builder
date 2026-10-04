defmodule BuildCalculator.Data.FeatBonusSlotValuesTest do
  @moduledoc """
  Бонусный слот класса берёт фит с выбором только с ЭТИМИ значениями — задача
  4.50, `vanilla/feat_bonus_slot_values.json` → поле фита `bonus_for_only`,
  читает `Rules.FeatSlots.choice_refusals/4`.

  Источник — строки `cls_feat_*.2da` базовой игры (List 1, бонусный список):

    * `cls_feat_archer.2da`, позиции 42–47 — Тайный лучник берёт бонусным
      слотом Epic weapon focus, Overwhelming critical и Devastating critical
      только с длинным и коротким луком;
    * `cls_feat_asasin.2da`, позиции 63–64 — Убийца берёт Epic skill focus
      только в Hide и Move silently.

  Fandom говорит то же на страницах классов (`fandom:Arcane archer` rev 71569,
  «Epic bonus feats: … epic weapon focus (longbow, shortbow) …»;
  `fandom:Assassin` rev 71570, «epic skill focus (hide, move silently only)»).
  Хак Сиалы несёт те же строки — запись доезжает до Сиалы сама.

  Сценарии собираются по одному левелапу (`Rules.validate_level_up/3`), как у
  игрока. Сторожа загрузчика портят копию `priv/rules`
  (`BuildCalculator.TmpDir`). Сверка строк таблиц — только при выгрузках
  (`priv/base_2da`, `priv/hak/2da`), иначе её `describe` пропускается.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.GameFiles.TwoDA
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatChoices, FeatSlots}

  @base Path.expand("../../../priv/base_2da", __DIR__)
  @hak Path.expand("../../../priv/hak/2da", __DIR__)
  @dumps? File.regular?(Path.join(@base, "manifest.json")) and
            File.regular?(Path.join(@hak, "manifest.json"))

  @rel "vanilla/feat_bonus_slot_values.json"

  # Что записано — и что обязано доехать до обоих ruleset'ов.
  @records [
    {:epic_weapon_focus, :arcane_archer, [:longbow, :shortbow]},
    {:overwhelming_critical, :arcane_archer, [:longbow, :shortbow]},
    {:devastating_critical, :arcane_archer, [:longbow, :shortbow]},
    {:epic_skill_focus, :assassin, [:hide, :move_silently]}
  ]

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  # Билд, собранный по одному левелапу: каждый уровень обязан пройти
  # `validate_level_up/3` на том, что набрано до него, и каждый фит — свою
  # проверку на своём уровне.
  defp level_up!(ruleset, steps, fields) do
    Enum.reduce(steps, Build.new(fields), fn {class, picks}, build ->
      level = Build.character_level(build) + 1

      assert Rules.validate_level_up(build, class, ruleset) == :ok,
             "уровень #{level} (#{class}) не прошёл"

      build = Build.add_level(build, class)

      Enum.reduce(picks, build, fn {slot, feat, choice}, build ->
        pick = %{feat: feat, at: level, slot: slot, choice: choice}

        assert Rules.validate_feat_pick(build, pick, ruleset) == :ok,
               "уровень #{level}: #{feat} (#{inspect(choice)}) в #{inspect(slot)}"

        Build.put_feat(build, level, slot, feat, choice)
      end)
    end)
  end

  # Эльф: волшебник 1 → воин 9 → Тайный лучник 14 = 24-й уровень, первый
  # эпический бонусный фит Тайного лучника (уровень класса 14, `cls_bfeat_archer`).
  # На ванили фокус на лук и длинный меч даёт воинское владение; у Сиалы владения
  # свои — пять фитов «Системы оружия» (CLAUDE.md §6), их берёт бонусный слот воина.
  defp archer_head(%{version: "siala_41"}) do
    [
      {:wizard, [{:general, :point_blank_shot, nil}]},
      {:fighter, [{{:class_bonus, :fighter}, :siala_ranged_proficiency, nil}]},
      {:fighter,
       [
         {:general, :weapon_focus, :longbow},
         {{:class_bonus, :fighter}, :siala_blade_proficiency, nil}
       ]},
      {:fighter, []},
      {:fighter, [{{:class_bonus, :fighter}, :weapon_focus, :longsword}]}
    ]
  end

  defp archer_head(_vanilla) do
    [
      {:wizard, [{:general, :point_blank_shot, nil}]},
      {:fighter, [{{:class_bonus, :fighter}, :weapon_focus, :longbow}]},
      {:fighter, [{:general, :weapon_focus, :longsword}]}
    ]
  end

  defp archer(ruleset, archer_levels \\ 14) do
    head = archer_head(ruleset)

    steps =
      head ++
        List.duplicate({:fighter, []}, 10 - length(head)) ++
        List.duplicate({:arcane_archer, []}, archer_levels)

    level_up!(ruleset, steps,
      race: :elf,
      alignment: :chaotic_good,
      base_abilities: %{str: 14, dex: 18, con: 12, int: 14, wis: 8, cha: 8}
    )
  end

  # Человек, нейтрально-злой: вор 5 → Убийца 10 → вор 5 → Убийца 4 = 24-й
  # уровень, Убийца 14. Скрытность, Тихий шаг и Акробатика — по потолку на
  # каждом уровне (4 на 1-м, дальше +1), к 24-му по 27 рангов.
  defp assassin(ruleset) do
    classes =
      List.duplicate(:rogue, 5) ++
        List.duplicate(:assassin, 10) ++
        List.duplicate(:rogue, 5) ++ List.duplicate(:assassin, 4)

    skills =
      Map.new(1..24, fn level ->
        ranks = if level == 1, do: 4, else: 1
        {level, %{hide: ranks, move_silently: ranks, tumble: ranks}}
      end)

    level_up!(ruleset, Enum.map(classes, &{&1, []}),
      race: :human,
      alignment: :neutral_evil,
      base_abilities: %{str: 12, dex: 18, con: 12, int: 14, wis: 10, cha: 8},
      skills: skills
    )
  end

  # Значения, которые фит даёт выбрать на этом ruleset'е, — словарь домена,
  # пропущенный через ворота (`FeatChoices.choice_reasons/3`, без персонажа).
  defp offered(ruleset, feat_id) do
    case FeatChoices.domain(feat_id, ruleset) do
      nil ->
        []

      domain ->
        for value <- Enum.sort(ruleset.choice_domains[domain].values),
            FeatChoices.choice_reasons(feat_id, value, ruleset) == [],
            do: value
    end
  end

  defp pick(build, ruleset, feat, slot, choice, level \\ 24),
    do:
      Rules.validate_feat_pick(
        build,
        %{feat: feat, at: level, slot: slot, choice: choice},
        ruleset
      )

  # ------------------------------------------------------------ records --

  describe "записи доезжают до обоих ruleset'ов" do
    test "поле bonus_for_only — ровно четыре записи, на ванили и на Сиале", ctx do
      for ruleset <- [ctx.vanilla, ctx.siala] do
        loaded =
          for {id, feat} <- ruleset.feats,
              {class, values} <- feat.bonus_for_only,
              do: {id, class, values |> MapSet.to_list() |> Enum.sort()}

        assert Enum.sort(loaded) == Enum.sort(@records), ruleset.version
      end
    end

    test "у каждого фита, у которого записи нет, — пустая карта, а не отсутствующий ключ", ctx do
      for ruleset <- [ctx.vanilla, ctx.siala], {id, feat} <- ruleset.feats do
        assert is_map(feat.bonus_for_only), "#{ruleset.version}: #{id}"
      end
    end
  end

  # ---------------------------------------------------------- scenarios --

  describe "сценарий по одному левелапу: Тайный лучник 14 на 24-м уровне" do
    test "Epic weapon focus (longbow) бонусным слотом — да, (longsword) — нет; общий слот — да",
         ctx do
      for ruleset <- [ctx.vanilla, ctx.siala] do
        build = archer(ruleset)
        assert Build.class_level_at(build, 24) == 14
        bonus = {:class_bonus, :arcane_archer}
        assert Enum.map(FeatSlots.at(build, ruleset, 24), & &1.id) == [:general, bonus]

        assert pick(build, ruleset, :epic_weapon_focus, bonus, :longbow) == :ok

        assert pick(build, ruleset, :epic_weapon_focus, bonus, :longsword) ==
                 {:error, [{:not_in_class_bonus_slot, :arcane_archer}]},
               ruleset.version

        # Тот же фит с тем же мечом — законный пик общего слота того же уровня:
        # запись не трогает общий слот (строки feat.2da — ALLCLASSESCANUSE 1).
        assert pick(build, ruleset, :epic_weapon_focus, :general, :longsword) == :ok
      end
    end

    test "Rules.illegal_feats/2 называет меч в бонусном слоте и молчит, когда он в общем", ctx do
      for ruleset <- [ctx.vanilla, ctx.siala] do
        build = archer(ruleset)
        bonus = {:class_bonus, :arcane_archer}

        wrong = Build.put_feat(build, 24, bonus, :epic_weapon_focus, :longsword)

        assert Rules.illegal_feats(wrong, ruleset) == [
                 {24, bonus, :epic_weapon_focus, {:not_in_class_bonus_slot, :arcane_archer}}
               ]

        right =
          build
          |> Build.put_feat(24, bonus, :epic_weapon_focus, :longbow)
          |> Build.put_feat(24, :general, :epic_weapon_focus, :longsword)

        assert Rules.illegal_feats(right, ruleset) == []
      end
    end

    # Граница капа и четыре класса — только у Сиалы: ваниль держит три класса
    # и кап 40. Тайный лучник 30 на 40-м — последний эпический бонусный уровень
    # класса до капа; 41-й берётся четвёртым классом.
    test "Сиала: Тайный лучник 30 на 40-м, четвёртый класс на 41-м — тот же ответ слота", ctx do
      ruleset = ctx.siala
      build = archer(ruleset, 30)
      assert Build.character_level(build) == 40
      assert Rules.validate_level_up(build, :rogue, ruleset) == :ok
      build = Build.add_level(build, :rogue)
      assert Build.character_level(build) == ruleset.level_cap
      assert map_size(Build.class_levels(build)) == ruleset.max_classes

      bonus = {:class_bonus, :arcane_archer}
      assert Enum.any?(FeatSlots.at(build, ruleset, 40), &(&1.id == bonus))
      assert pick(build, ruleset, :epic_weapon_focus, bonus, :longbow, 40) == :ok

      assert pick(build, ruleset, :epic_weapon_focus, bonus, :longsword, 40) ==
               {:error, [{:not_in_class_bonus_slot, :arcane_archer}]}
    end
  end

  describe "сценарий по одному левелапу: Убийца 14 на 24-м уровне" do
    test "Epic skill focus (hide) бонусным слотом — да, (tumble) — нет; общий слот — да", ctx do
      for ruleset <- [ctx.vanilla, ctx.siala] do
        build = assassin(ruleset)
        assert Build.class_level_at(build, 24) == 14
        bonus = {:class_bonus, :assassin}

        assert pick(build, ruleset, :epic_skill_focus, bonus, :hide) == :ok
        assert pick(build, ruleset, :epic_skill_focus, bonus, :move_silently) == :ok

        assert pick(build, ruleset, :epic_skill_focus, bonus, :tumble) ==
                 {:error, [{:not_in_class_bonus_slot, :assassin}]},
               ruleset.version

        assert pick(build, ruleset, :epic_skill_focus, :general, :tumble) == :ok
      end
    end

    # Use magic device на уровне Убийцы отбивает ещё и правило уровня
    # (`feat_requirements.json` → epic_skill_focus, only_on_class_levels_for_skill):
    # у пары две причины, и обе верны — одна про уровень, другая про слот.
    test "Use magic device: и слот, и правило уровня — обе причины, общий слот — одна", ctx do
      for ruleset <- [ctx.vanilla, ctx.siala] do
        build = assassin(ruleset)

        assert {:error, bonus} =
                 pick(
                   build,
                   ruleset,
                   :epic_skill_focus,
                   {:class_bonus, :assassin},
                   :use_magic_device
                 )

        assert {:not_in_class_bonus_slot, :assassin} in bonus
        assert {:requires_leveling_as, [:bard, :rogue, :shadowdancer]} in bonus

        assert {:error, general} =
                 pick(build, ruleset, :epic_skill_focus, :general, :use_magic_device)

        refute {:not_in_class_bonus_slot, :assassin} in general
        assert {:requires_leveling_as, [:bard, :rogue, :shadowdancer]} in general
      end
    end
  end

  # ------------------------------------------------------- choice_refusals --

  describe "FeatSlots.choice_refusals/4 — таблица по всем значениям" do
    # Источник — строки `cls_feat_archer.2da` (42–47) и `cls_feat_asasin.2da`
    # (63–64): бонусный слот отбивает всё, что фит даёт выбрать, кроме названных.
    test "у записанной пары отбито всё, кроме перечисленного; общий слот не отбивает ничего",
         ctx do
      for ruleset <- [ctx.vanilla, ctx.siala], {feat, class, listed} <- @records do
        offered = offered(ruleset, feat)
        assert Enum.all?(listed, &(&1 in offered)), "#{ruleset.version}: #{feat}"

        refused =
          for value <- offered,
              FeatSlots.choice_refusals(ruleset, {:class_bonus, class}, feat, value) != [],
              do: value

        assert Enum.sort(refused) == Enum.sort(offered -- listed), "#{ruleset.version}: #{feat}"

        for value <- offered do
          assert FeatSlots.choice_refusals(ruleset, :general, feat, value) == []

          # Второй бонусный слот того же класса — тот же пул (FeatSlots, `bonus_slot_class/1`).
          assert FeatSlots.choice_refusals(ruleset, {:class_bonus, class, 2}, feat, value) ==
                   FeatSlots.choice_refusals(ruleset, {:class_bonus, class}, feat, value)
        end
      end
    end

    # Воин и паладин — классы с теми же оружейными фитами в бонусном списке.
    # Запись их не задевает: отбито ровно то, что отбивали исключения до неё
    # (у ванили — ничего, у Сиалы — паладину Overwhelming critical (club), 4.49).
    test "воин и паладин не задеты: отбито ровно bonus_for_except", ctx do
      for ruleset <- [ctx.vanilla, ctx.siala],
          class <- [:fighter, :paladin],
          {id, feat} <- ruleset.feats,
          MapSet.member?(feat.bonus_for, class) do
        refute Map.has_key?(feat.bonus_for_only, class)
        offered = offered(ruleset, id)

        refused =
          for value <- offered,
              FeatSlots.choice_refusals(ruleset, {:class_bonus, class}, id, value) != [],
              do: value

        excepted = for {^class, value} <- feat.bonus_for_except, value in offered, do: value
        assert Enum.sort(refused) == Enum.sort(excepted), "#{ruleset.version}: #{class} #{id}"
      end

      assert FeatSlots.choice_refusals(
               ctx.siala,
               {:class_bonus, :paladin},
               :overwhelming_critical,
               :club
             ) ==
               [{:not_in_class_bonus_slot, :paladin}]

      assert FeatSlots.choice_refusals(
               ctx.vanilla,
               {:class_bonus, :paladin},
               :overwhelming_critical,
               :club
             ) ==
               []
    end
  end

  # ------------------------------------- creature weapon: the (b) of the diff --

  describe "оружие существ на ванили — вид (b) сверки, проверено вызовом" do
    # `Base2da.Classification`, правило `:creature_weapon_only`: таблица не кладёт
    # строки оружия существ ни в один бонусный список, у нас слот значение не
    # отбивает — но ядро отбивает пик раньше, требованием. Weapon focus и
    # Improved critical требуют владения выбранным оружием (Weapon proficiency
    # (creature)), остальные пять семейств стоят на них же тем же оружием.
    @creature_families [
      :weapon_focus,
      :weapon_specialization,
      :improved_critical,
      :epic_weapon_focus,
      :epic_weapon_specialization,
      :overwhelming_critical,
      :devastating_critical
    ]

    test "Weapon proficiency (creature) не берёт ни один слот и не выдаёт ни один класс", ctx do
      ruleset = ctx.vanilla

      refute Enum.any?(ruleset.classes, fn {_id, class} ->
               Enum.any?(class.granted_feats, fn {_level, feats} ->
                 :weapon_proficiency_creature in feats
               end)
             end)

      for class <- Map.keys(ruleset.classes) do
        build = Build.new(levels: [class])

        for slot <- FeatSlots.at(build, ruleset, 1) do
          refute FeatSlots.accepts?(ruleset, slot, :weapon_proficiency_creature),
                 "#{class}: #{inspect(slot.id)}"
        end
      end
    end

    # ⚠️ Воин 6, а не 4, с задачи 4.61: вопрос задаётся об ОБОИХ слотах одного
    # уровня, а общего слота на 4-м уровне нет (общие — 1, 3, 6 …); с 4.61 ядро
    # спрашивает, даёт ли уровень слот пика, и про общий слот 4-го уровня отвечало
    # бы `{:slot_not_granted, :general}`. На 6-м есть оба — бонус Воина и общий.
    test "воин 6: Weapon focus (creature) — отказ требованием, в бонусном и в общем слоте", ctx do
      ruleset = ctx.vanilla

      build =
        level_up!(ruleset, List.duplicate({:fighter, []}, 6),
          race: :human,
          alignment: :true_neutral,
          base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8}
        )

      assert Enum.map(FeatSlots.at(build, ruleset, 6), & &1.id) == [
               :general,
               {:class_bonus, :fighter}
             ]

      for slot <- [{:class_bonus, :fighter}, :general] do
        assert pick(build, ruleset, :weapon_focus, slot, :creature_weapon, 6) ==
                 {:error, [{:requires_feat, :weapon_proficiency_creature}]}
      end

      # …и остальные шесть семейств требуют фит того же оружия.
      for id <- @creature_families -- [:weapon_focus, :improved_critical] do
        same = ruleset.feats[id].prereqs["same_choice_as"]
        assert Enum.any?(same, &(&1 in ["weapon_focus", "improved_critical"])), "#{id}"
      end

      assert ruleset.feats[:improved_critical].prereqs["proficiency_with_chosen_weapon"] == true
    end
  end

  # ------------------------------------------------------ loader guards --

  describe "сторожа загрузчика" do
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

    test "кривая запись роняет сборку — каждый из тринадцати случаев" do
      first = fn fun -> &update_in(&1, ["feats", Access.at(0)], fun) end

      broken = [
        {"пустой список", first.(&Map.put(&1, "values", [])), ~r/non-empty list/},
        {"повтор значения", first.(&Map.put(&1, "values", ["longbow", "longbow"])),
         ~r/names a value twice/},
        {"повтор пары фит — класс", &update_in(&1, ["feats"], fn [e | rest] -> [e, e | rest] end),
         ~r/stated twice/},
        {"неизвестный ключ", first.(&Map.put(&1, "only", ["longbow"])), ~r/does not read/},
        {"нет источников-строк", first.(&Map.drop(&1, ~w(source source_2))),
         ~r/no source is a cls_feat_\*\.2da row list/},
        {"строк меньше, чем значений", first.(&Map.drop(&1, ~w(source_2))),
         ~r/no source is a cls_feat_\*\.2da row list/},
        {"источник — не таблица класса", first.(&put_in(&1, ["source", "table"], "feat.2da")),
         ~r/no source is a cls_feat_\*\.2da row list/},
        {"строки из двух таблиц",
         first.(&put_in(&1, ["source_2", "table"], "cls_feat_asasin.2da")),
         ~r/no source is a cls_feat_\*\.2da row list/},
        {"одна строка дважды", first.(&put_in(&1, ["source_2", "row"], 42)),
         ~r/no source is a cls_feat_\*\.2da row list/},
        {"не verified", first.(&Map.put(&1, "status", "assumed")), ~r/not "verified"/},
        {"фита нет", first.(&Map.put(&1, "feat", "epic_weapon_fokus")), ~r/does not exist/},
        {"класс не в bonus_for", first.(&Map.put(&1, "class", "wizard")),
         ~r/not on that feat's bonus list/},
        {"значение вне домена", first.(&Map.put(&1, "values", ["longbow", "long_bow"])),
         ~r/not in the feat's choice domain/}
      ]

      for {name, fun, message} <- broken do
        root = copy_rules()
        edit_json!(root, @rel, fun)

        error = assert_raise RuntimeError, fn -> Loader.load!(root) end
        assert Exception.message(error) =~ message, name
      end
    end

    test "значение и в списке, и в исключениях того же класса — сборка падает" do
      root = copy_rules()

      # Ванильная пара-исключение «вор — Use magic device» (`feat_requirements.json`)
      # и запись, которая ставит Use magic device вору в список.
      edit_json!(root, @rel, fn json ->
        update_in(json["feats"], fn feats ->
          feats ++
            [
              feats
              |> List.last()
              |> Map.merge(%{"class" => "rogue", "values" => ["hide", "use_magic_device"]})
            ]
        end)
      end)

      assert_raise RuntimeError, ~r/both lists :use_magic_device/, fn -> Loader.load!(root) end
    end

    # Положительный контроль: без записи бонусный слот снова берёт меч — тот
    # самый пик, который запись закрывает.
    test "без записи бонусный слот Тайного лучника берёт Epic weapon focus (longsword)" do
      root = copy_rules()
      edit_json!(root, @rel, &Map.put(&1, "feats", []))

      for {_version, ruleset} <- Loader.load!(root) do
        assert FeatSlots.choice_refusals(
                 ruleset,
                 {:class_bonus, :arcane_archer},
                 :epic_weapon_focus,
                 :longsword
               ) == []
      end
    end
  end

  # --------------------------------------------------------- the tables --

  if @dumps? do
    describe "строки таблиц — база и хак" do
      defp table(dir, name),
        do: dir |> Path.join(name <> ".2da") |> File.read!() |> TwoDA.parse!()

      # FeatIndex строк записи — то, что пишет цитата; позиция в `rows` должна
      # держать ровно эти строки с List 1.
      @rows [
        {"cls_feat_archer", [42, 43], ~w(631 632), [79, 80]},
        {"cls_feat_archer", [44, 45], ~w(721 722), [81, 82]},
        {"cls_feat_archer", [46, 47], ~w(507 508), [30, 31]},
        {"cls_feat_asasin", [63, 64], ~w(594 597), [100, 101]}
      ]

      test "позиции из записи — строки семейства с List 1 у базы и у хака" do
        for {name, base_rows, indexes, hak_rows} <- @rows do
          base = table(@base, name)
          hak = table(@hak, name)

          assert Enum.map(base_rows, &TwoDA.get(base, &1, "FeatIndex")) == indexes
          assert Enum.map(base_rows, &TwoDA.get(base, &1, "List")) == ["1", "1"]
          assert Enum.map(hak_rows, &TwoDA.get(hak, &1, "FeatIndex")) == indexes
          assert Enum.map(hak_rows, &TwoDA.get(hak, &1, "List")) == ["1", "1"]
        end
      end

      test "запись в JSON ссылается на те же позиции" do
        json = "priv/rules" |> Path.join(@rel) |> File.read!() |> Jason.decode!()

        cited =
          for entry <- json["feats"] do
            {entry["source"]["table"], [entry["source"]["row"], entry["source_2"]["row"]],
             entry["hak"]["source"]["rows"]}
          end

        assert cited ==
                 for(
                   {name, base_rows, _idx, hak_rows} <- @rows,
                   do: {name <> ".2da", base_rows, hak_rows}
                 )
      end
    end
  end
end
