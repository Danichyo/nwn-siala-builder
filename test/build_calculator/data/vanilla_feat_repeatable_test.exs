defmodule BuildCalculator.Data.VanillaFeatRepeatableTest do
  @moduledoc """
  Повторяемость фитов ВАНИЛИ — `priv/rules/vanilla/feat_repeatable.json`
  (задача 4.7), ручной слой поверх машинного `vanilla/feats.json`.

  До задачи у ванили было три дыры одной природы, и все три — в данных, а не
  в правилах игры:

    * шесть семейств «по фиту на значение» (Epic skill focus, Epic spell focus,
      Epic weapon focus, Epic weapon specialization, Arcane defense, Resist
      energy) не несли блока повторяемости — Fandom описывает их выбором,
      а не словами «may be taken multiple times», — и выбор не записывался:
      +10 Epic skill focus не считался вовсе, «with the chosen weapon» у Epic
      weapon focus не сравнивалось;
    * у семнадцати фитов со ступенями не было потолка взятий, и Fighter 40
      брал Epic toughness семнадцать раз;
    * `distinct` у Favored enemy и Weapon of choice не был сказан, и
      загрузчик держал его допущением на весь ruleset.

  Ответ на все три — таблица игры feat.2da: строка на значение, цепочка
  ступеней I…X. Здесь проверяется, что записанное доехало до ядра, что
  Сиала от файла не зависит вовсе, что сторожа загрузчика падают, и — при
  наличии выгрузки `priv/base_2da/` — что каждая цифра и каждое имя ступени
  совпадают с таблицей.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.{Diff, Source}
  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.GameFiles.TwoDA
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}

  @file_path "priv/rules/vanilla/feat_repeatable.json"
  @raw @file_path |> File.read!() |> Jason.decode!()

  # Дословно то, что записано, — таблица продублирована намеренно: тест,
  # читающий ожидания из проверяемого файла, зеленеет и на пустом файле.
  @blocks %{
    arcane_defense: :spell_school,
    devastating_critical: :weapon,
    epic_skill_focus: :skill,
    epic_spell_focus: :spell_school,
    epic_weapon_focus: :weapon,
    epic_weapon_specialization: :weapon,
    overwhelming_critical: :weapon,
    resist_energy: :energy_type
  }

  # Две записи файла, которые ДОЕЗЖАЮТ до Сиалы (задача 4.30): её слой их
  # повторяемость не перекрывает. Законно это потому, что хак несёт те же
  # семейства строк feat.2da — `weapon_feat_tables_hak_test.exs`.
  @reaching_siala [:devastating_critical, :overwhelming_critical]

  @ceilings %{
    automatic_quicken_spell: 3,
    automatic_silent_spell: 3,
    automatic_still_spell: 3,
    epic_damage_reduction: 3,
    epic_energy_resistance: 10,
    epic_toughness: 10,
    great_charisma: 10,
    great_constitution: 10,
    great_dexterity: 10,
    great_intelligence: 10,
    great_smiting: 10,
    great_strength: 10,
    great_wisdom: 10,
    improved_sneak_attack: 10,
    improved_spell_resistance: 10,
    improved_stunning_fist: 10,
    self_concealment: 5
  }

  # Число взятий названо страницей Fandom словами — работы показывать нечего.
  @ceilings_named [:great_smiting, :epic_damage_reduction]

  @distinct [:favored_enemy, :weapon_of_choice]

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp copy_rules do
    root = BuildCalculator.TmpDir.unique_path!("feat_repeatable_")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp edit(root, relative, fun) do
    path = Path.join(root, relative)
    File.write!(path, path |> File.read!() |> Jason.decode!() |> fun.() |> Jason.encode!())
    root
  end

  defp edit_entries(root, fun),
    do: edit(root, "vanilla/feat_repeatable.json", &Map.update!(&1, "feats", fun))

  defp entry(id), do: Enum.find(@raw["feats"], &(&1["id"] == Atom.to_string(id)))

  describe "файл подключён" do
    test "зарегистрирован по имени и не стал доменом выбора", %{vanilla: v, siala: s} do
      assert "vanilla/feat_repeatable.json" in Loader.source_files()

      for ruleset <- [v, s], do: refute(Map.has_key?(ruleset.choice_domains, :feat_repeatable))
    end

    test "таблица теста покрывает файл целиком" do
      ids = @raw["feats"] |> Enum.map(&String.to_existing_atom(&1["id"])) |> Enum.sort()

      assert ids ==
               Enum.sort(Map.keys(@blocks) ++ Map.keys(@ceilings) ++ @distinct)
    end
  end

  describe "записанное доехало до ванили" do
    test "восемь блоков — выбор, distinct сказан, источник ванильный", %{vanilla: v} do
      for {id, domain} <- @blocks do
        block = v.feats[id].repeatable

        assert block.choice == domain, "#{id}"
        assert block.distinct? == true, "#{id}"
        assert block.distinct_stated?, "#{id}: distinct читается как допущение"
        assert block.status == "verified", "#{id}"
        assert block.source["wiki"] == "fandom", "#{id}"
        assert block.max_takes == nil, "#{id}: у семейства выбора потолок — домен, а не число"
      end
    end

    test "семнадцать потолков — число таблицы, работа показана", %{vanilla: v} do
      for {id, value} <- @ceilings do
        ceiling = v.feats[id].repeatable.max_takes

        assert ceiling.value == value, "#{id}"

        if id in @ceilings_named do
          assert ceiling.status == "verified", "#{id}"
          assert ceiling.from == nil, "#{id}"
          assert ceiling.source["wiki"] == "fandom", "#{id}"
        else
          assert ceiling.status == "derived", "#{id}"
          assert %{counted: :tiers, tiers: tiers} = ceiling.from
          assert length(tiers) == value, "#{id}"
          assert ceiling.source["kind"] == "2da", "#{id}"
        end
      end
    end

    # Выбор и `distinct` машинного блока не тронуты — потолок ложится ВНУТРЬ.
    test "потолок не переписал машинный блок", %{vanilla: v} do
      eer = v.feats[:epic_energy_resistance].repeatable
      assert eer.choice == :energy_type
      assert eer.distinct? == false
      assert eer.source["page"] == "Epic energy resistance"

      assert v.feats[:epic_toughness].repeatable.choice == nil
      assert v.feats[:epic_toughness].repeatable.source["page"] == "Epic toughness"
    end

    test "distinct сказан у двух, и допущение с ruleset'а ушло", %{vanilla: v} do
      for id <- @distinct do
        assert v.feats[id].repeatable.distinct? == true, "#{id}"
        assert v.feats[id].repeatable.distinct_stated?, "#{id}"
      end

      refute {:assumed, :repeatable_choices_must_differ} in v.gaps
    end

    # «Последняя настоящая дыра ванили» — постановка задачи 4.7 дословно.
    test "прибавка Epic skill focus больше не дыра данных", %{vanilla: v} do
      refute {:not_modelled, {:feat_skill_bonus, :epic_skill_focus}} in v.gaps
      assert Enum.any?(v.skill_bonuses.applied, &(&1.id == :epic_skill_focus))
    end
  end

  describe "в расчёте ванили" do
    defp takes(feat, count) do
      Enum.reduce(1..count//1, Build.new(levels: List.duplicate(:fighter, 40)), fn n, build ->
        Build.put_feat(build, 20 + n, :general, feat)
      end)
    end

    # Критерий приёмки 4.7: Fighter 40 не берёт Epic toughness 11-й раз.
    # Близнецы — девять взятий и десять: по отдельности каждая половина
    # зеленела бы и при неверной модели.
    test "Epic toughness: десятое взятие законно, одиннадцатое отказано", %{vanilla: v} do
      assert Rules.validate_feat_pick(takes(:epic_toughness, 9), :epic_toughness, v) == :ok

      assert Rules.validate_feat_pick(takes(:epic_toughness, 10), :epic_toughness, v) ==
               {:error, [{:max_takes, :epic_toughness, 10}]}

      refute {:missing_data, {:feat_max_takes, :epic_toughness}} in Rules.compute(
               takes(:epic_toughness, 3),
               v
             ).gaps
    end

    # Критерий приёмки 4.7: Epic skill focus +10 считается.
    test "Epic skill focus прибавляет +10 к выбранному навыку", %{vanilla: v} do
      rogue =
        Build.new(
          levels: List.duplicate(:rogue, 21),
          skills: Map.new(1..21, fn level -> {level, %{hide: if(level == 1, do: 4, else: 1)}} end)
        )

      bare = Rules.compute(rogue, v).skill_values[:hide]
      focused = Rules.compute(Build.put_feat(rogue, 21, :general, :epic_skill_focus, :hide), v)

      assert focused.skill_values[:hide].total == bare.total + 10
      assert :epic_skill_focus in focused.skill_values[:hide].feat_bonus_from

      # Контроль: соседний навык не тронут — получателя называет выбор.
      assert focused.skill_values[:hide].total != bare.total

      refute :epic_skill_focus in (focused.skill_values[:move_silently] || %{feat_bonus_from: []}).feat_bonus_from
    end

    # Критерий приёмки 4.7: Fighter 20 / WM 20 с длинным мечом — гэпов нет.
    # Разведка 25.09.2026 насчитала у такого билда 13; 4.1 сняла восемь
    # (словарь получателей), 4.7 — оставшиеся пять: квалификатор «with the
    # chosen weapon» у Epic weapon focus, два потолка взятий и владение
    # длинным мечом (дублем).
    test "Fighter 20 / Weapon master 20 с длинным мечом — ни одного гэпа", %{vanilla: v} do
      picks = [
        {1, :general, :weapon_focus, :longsword},
        {1, {:class_bonus, :fighter}, :power_attack, nil},
        {2, {:class_bonus, :fighter}, :dodge, nil},
        {3, :general, :expertise, nil},
        {4, {:class_bonus, :fighter}, :weapon_specialization, :longsword},
        {6, :general, :mobility, nil},
        {6, {:class_bonus, :fighter}, :spring_attack, nil},
        {8, {:class_bonus, :fighter}, :improved_critical, :longsword},
        {9, :general, :whirlwind_attack, nil},
        {21, :general, :epic_weapon_focus, :longsword},
        {24, :general, :epic_toughness, nil},
        {27, :general, :epic_toughness, nil},
        {30, :general, :great_strength, nil},
        {33, :general, :great_strength, nil}
      ]

      build =
        picks
        |> Enum.reduce(
          Build.new(
            race: :human,
            alignment: :lawful_neutral,
            base_abilities: %{str: 16, dex: 14, con: 14, int: 13, wis: 10, cha: 8},
            levels: List.duplicate(:fighter, 20) ++ List.duplicate(:weapon_master, 20),
            skills: Map.new(1..40, fn level -> {level, %{discipline: 1}} end),
            gear: %Gear{weapon: :longsword}
          ),
          fn {level, slot, feat, choice}, b -> Build.put_feat(b, level, slot, feat, choice) end
        )
        |> Build.put_granted_choice(21, :weapon_of_choice, :longsword)

      stats = Rules.compute(build, v)

      assert stats.gaps == []

      # Положительный контроль: пустой список — не пустой билд. Оружие в руках
      # посчитано, эпический фокус тоже, и выбор оружия у него законен.
      assert Enum.any?(stats.own_attack_terms, &(&1.id == :epic_weapon_focus and &1.bonus == 2))
      assert Rules.illegal_feats(build, v) == []
      assert Rules.illegal_gear_weapon(build, v) == []
    end
  end

  # Критерий приёмки 4.30: Overwhelming и Devastating critical берутся на
  # второе оружие, повтор того же оружия — отказ. До записи выбор оружия у них
  # не записывался вовсе: фит брался один раз, а «(chosen weapon)» печаталось
  # оговоркой.
  describe "Overwhelming и Devastating critical — фит на каждое оружие" do
    # Воин 40: STR 18 и все десять прибавок в силу — 23 на 21-м (Overwhelming),
    # 25 на 28-м (Devastating). Каждое оружие проходит всю цепочку: Improved
    # critical → Overwhelming → Devastating.
    defp crit_fighter(picks) do
      base =
        Build.new(
          race: :human,
          alignment: :true_neutral,
          levels: List.duplicate(:fighter, 40),
          base_abilities: %{str: 18, dex: 10, con: 14, int: 10, wis: 10, cha: 8},
          ability_increases: Map.new(4..40//4, &{&1, :str})
        )

      Enum.reduce(
        [
          {1, :general, :power_attack, nil},
          {1, {:class_bonus, :fighter}, :cleave, nil},
          {4, {:class_bonus, :fighter}, :great_cleave, nil},
          {8, {:class_bonus, :fighter}, :improved_critical, :longsword},
          {10, {:class_bonus, :fighter}, :improved_critical, :greataxe}
        ] ++ picks,
        base,
        fn {level, slot, feat, choice}, b -> Build.put_feat(b, level, slot, feat, choice) end
      )
    end

    test "на ванили оба фита берутся на второе оружие", %{vanilla: v} do
      build =
        crit_fighter([
          {21, :general, :overwhelming_critical, :longsword},
          {22, {:class_bonus, :fighter}, :overwhelming_critical, :greataxe},
          {28, {:class_bonus, :fighter}, :devastating_critical, :longsword},
          {30, :general, :devastating_critical, :greataxe}
        ])

      assert Rules.illegal_feats(build, v) == []

      # Выбор сравнивается, и оговорки «(chosen weapon)» больше нет — ни
      # квалификатора, ни «прибавку не считаем» (получатель — урон и крит,
      # `vanilla/feat_effect_receivers.json`).
      gaps = Rules.compute(build, v).gaps

      for id <- [:overwhelming_critical, :devastating_critical] do
        refute Enum.any?(gaps, &match?({:not_modelled, {_kind, ^id, _}}, &1)),
               "#{id}: #{inspect(gaps)}"

        refute {:not_modelled, {:feat_bonus, id}} in gaps
      end
    end

    test "на ванили повтор того же оружия — отказ, чужое оружие без ступени ниже — отказ", %{
      vanilla: v
    } do
      build =
        crit_fighter([
          {21, :general, :overwhelming_critical, :longsword},
          {28, {:class_bonus, :fighter}, :devastating_critical, :longsword}
        ])

      assert Rules.validate_feat_pick(
               build,
               %{feat: :overwhelming_critical, choice: :longsword, at: 24},
               v
             ) == {:error, [{:choice_already_taken, :overwhelming_critical, :longsword}]}

      assert Rules.validate_feat_pick(
               build,
               %{feat: :devastating_critical, choice: :longsword, at: 30},
               v
             ) == {:error, [{:choice_already_taken, :devastating_critical, :longsword}]}

      # «(chosen weapon)» проверяется: на скимитаре нет Improved critical.
      assert Rules.validate_feat_pick(
               build,
               %{feat: :overwhelming_critical, choice: :scimitar, at: 24},
               v
             ) == {:error, [{:requires_same_choice, :improved_critical, :scimitar}]}

      # Положительный контроль: второе оружие со своей цепочкой — законно.
      assert Rules.validate_feat_pick(
               build,
               %{feat: :overwhelming_critical, choice: :greataxe, at: 24},
               v
             ) == :ok
    end

    # На Сиале Overwhelming critical живой, и до 4.30 на второе оружие
    # не брался — дефект, названный входом задачи 4.7. Devastating critical
    # там выключен, и повторяемость этого не меняет.
    test "на Сиале Overwhelming critical берётся на второе оружие, Devastating — по-прежнему нет",
         %{siala: s} do
      build =
        Enum.reduce(
          [
            {1, :general, :siala_blade_proficiency, nil},
            {1, {:class_bonus, :fighter}, :power_attack, nil},
            {2, {:class_bonus, :fighter}, :cleave, nil},
            {3, :general, :siala_axe_proficiency, nil},
            {4, {:class_bonus, :fighter}, :great_cleave, nil},
            {8, {:class_bonus, :fighter}, :improved_critical, :longsword},
            {10, {:class_bonus, :fighter}, :improved_critical, :greataxe},
            {21, :general, :overwhelming_critical, :longsword},
            {22, {:class_bonus, :fighter}, :overwhelming_critical, :greataxe}
          ],
          Build.new(
            race: :human,
            alignment: :true_neutral,
            levels: List.duplicate(:fighter, 24),
            base_abilities: %{str: 18, dex: 10, con: 14, int: 10, wis: 10, cha: 8},
            ability_increases: Map.new(4..24//4, &{&1, :str})
          ),
          fn {level, slot, feat, choice}, b -> Build.put_feat(b, level, slot, feat, choice) end
        )

      assert Rules.illegal_feats(build, s) == []

      assert Rules.validate_feat_pick(
               build,
               %{feat: :overwhelming_critical, choice: :longsword, at: 24},
               s
             ) == {:error, [{:choice_already_taken, :overwhelming_critical, :longsword}]}

      assert Rules.validate_feat_pick(
               build,
               %{feat: :devastating_critical, choice: :longsword, at: 24},
               s
             ) == {:error, [{:feat_disabled, :devastating_critical}]}
    end
  end

  describe "Сиала от файла зависит ровно двумя записями" do
    # 🔴 Слой Сиалы ЗАМЕЩАЕТ блок повторяемости целиком у 25 фитов файла, и от
    # них Сиала не зависит. Две записи задачи 4.30 — Overwhelming critical
    # и Devastating critical — доезжают до неё сознательно: слой Сиалы их
    # повторяемость не перекрывает, а хак несёт те же семейства строк
    # (`weapon_feat_tables_hak_test.exs`). Здесь стоял тест «без файла Сиала
    # та же» с пометкой, что запись о фите, которого Сиала не перекрывает,
    # уронит его первым, — так и вышло, и это было решение постановки
    # («оба ruleset'а, меняет Сиалу»), а не недосмотр. Теперь тест называет
    # разницу поимённо: без файла Сиала отличается РОВНО блоками этих двух,
    # и больше ничем.
    test "без файла Сиала отличается ровно повторяемостью двух фитов", %{vanilla: v, siala: s} do
      root = copy_rules()
      File.rm!(Path.join(root, "vanilla/feat_repeatable.json"))
      loaded = Loader.load!(root)
      without = loaded["siala_41"]

      for id <- @reaching_siala do
        assert without.feats[id].repeatable == nil, "#{id}"
        assert s.feats[id].repeatable.choice == :weapon, "#{id}"
      end

      restored =
        Enum.reduce(@reaching_siala, without, fn id, acc ->
          put_in(acc.feats[id].repeatable, s.feats[id].repeatable)
        end)

      assert restored == s

      # Положительный контроль: ваниль файл читает — без него она другая.
      refute loaded["vanilla"] == v
      assert loaded["vanilla"].feats[:epic_skill_focus].repeatable == nil
      assert loaded["vanilla"].feats[:epic_toughness].repeatable.max_takes == nil
    end
  end

  describe "сторож загрузчика роняет сборку, а не молчит" do
    test "фита нет" do
      root =
        copy_rules()
        |> edit_entries(&[%{"id" => "epic_nonsense", "max_takes" => %{}} | &1])

      assert_raise RuntimeError, ~r/names a feat that does not exist/, fn ->
        Loader.load!(root)
      end
    end

    test "запись дважды" do
      root = copy_rules() |> edit_entries(&(&1 ++ [entry(:epic_toughness)]))

      assert_raise RuntimeError, ~r/epic_toughness is stated twice/, fn -> Loader.load!(root) end
    end

    test "два факта в одной записи — или незнакомый ключ" do
      root =
        copy_rules()
        |> edit_entries(fn entries ->
          for e <- entries do
            if e["id"] == "epic_toughness",
              do: Map.put(e, "distinct", %{"value" => true}),
              else: e
          end
        end)

      assert_raise RuntimeError, ~r/states \["distinct", "max_takes"\]/, fn ->
        Loader.load!(root)
      end
    end

    # Парсер научился читать повторяемость сам — ручной блок надо снять,
    # а не держать тенью поверх машинного.
    test "блок поверх машинного блока" do
      weapon_focus = %{
        "id" => "weapon_focus",
        "repeatable" => entry(:epic_weapon_focus)["repeatable"]
      }

      root = copy_rules() |> edit_entries(&[weapon_focus | &1])

      assert_raise RuntimeError, ~r/already carries a repeatable block for weapon_focus/, fn ->
        Loader.load!(root)
      end
    end

    test "потолок поверх машинного потолка" do
      root =
        edit(copy_rules(), "vanilla/feats.json", fn feats ->
          for f <- feats do
            if f["id"] == "epic_toughness",
              do:
                put_in(f, ["repeatable", "max_takes"], %{
                  "value" => 10,
                  "status" => "verified",
                  "quote" => "…"
                }),
              else: f
          end
        end)

      assert_raise RuntimeError, ~r/already states a ceiling for epic_toughness/, fn ->
        Loader.load!(root)
      end
    end

    # Названное страницей число со статусом, которого никто не ставил: запись
    # выглядела бы потолком и не делала бы ничего. (У выведенного потолка
    # тот же статус роняет сборку раньше — работа при неверном статусе.)
    test "потолок, которого загрузчик прочитать не может" do
      root =
        copy_rules()
        |> edit_entries(fn entries ->
          for e <- entries do
            if e["id"] == "great_smiting",
              do: put_in(e, ["max_takes", "status"], "unclear"),
              else: e
          end
        end)

      assert_raise RuntimeError, ~r/max_takes is not readable/, fn -> Loader.load!(root) end
    end

    test "работа не даёт записанного числа" do
      root =
        copy_rules()
        |> edit_entries(fn entries ->
          for e <- entries do
            if e["id"] == "epic_toughness",
              do: update_in(e, ["max_takes", "from", "tiers"], &Enum.drop(&1, 1)),
              else: e
          end
        end)

      assert_raise RuntimeError, ~r/counts 9 tiers/, fn -> Loader.load!(root) end
    end

    test "блок с выбором без distinct" do
      root =
        copy_rules()
        |> edit_entries(fn entries ->
          for e <- entries do
            if e["id"] == "arcane_defense",
              do: update_in(e, ["repeatable"], &Map.delete(&1, "distinct")),
              else: e
          end
        end)

      assert_raise RuntimeError, ~r/does not say `distinct`/, fn -> Loader.load!(root) end
    end

    test "distinct поверх сказанного машинным слоем" do
      again = %{"id" => "weapon_focus", "distinct" => entry(:favored_enemy)["distinct"]}
      root = copy_rules() |> edit_entries(&[again | &1])

      assert_raise RuntimeError, ~r/already says `distinct` for weapon_focus/, fn ->
        Loader.load!(root)
      end
    end
  end

  describe "сверка с таблицей игры" do
    @base2da Path.expand("../../../priv/base_2da", __DIR__)

    unless File.regular?(Path.join(@base2da, "manifest.json")) do
      @describetag skip:
                     "нет priv/base_2da (публичный репозиторий, CI) — выгрузка: mix base2da.extract"
    end

    setup %{vanilla: v} do
      {:ok, source} = Source.load(@base2da)
      %{ctx: Diff.context(source, v, "priv/rules"), source: source}
    end

    # Семейство выбора: строк больше одной, и ни одна не повторяется сама
    # (GAINMULTIPLE 0) — значит значение берётся однажды.
    test "восемь блоков и два distinct — семейства по строке на значение", %{ctx: ctx} do
      for id <- Map.keys(@blocks) ++ @distinct do
        rows = ctx.families[id]

        assert length(rows) > 1, "#{id}: у семейства одна строка"

        assert Enum.all?(rows, &(TwoDA.get(ctx.feat, &1, "GAINMULTIPLE") == "0")),
               "#{id}: строка повторяема сама"

        assert Enum.all?(
                 rows,
                 &(TwoDA.get(ctx.feat, &1, "PREREQFEAT1")
                   |> TwoDA.to_int()
                   |> then(fn r -> ctx.feat_rows[r] != id end))
               ),
               "#{id}: строка требует строку своего семейства — это ступени, а не значения"
      end
    end

    # Потолок — длина цепочки; имена ступеней — те, что печатает игра.
    test "семнадцать потолков — длина цепочки ступеней, имена — из dialog.tlk", %{
      ctx: ctx,
      source: source,
      vanilla: v
    } do
      for {id, value} <- @ceilings do
        chains = chains(ctx, id)

        assert Enum.uniq(Enum.map(chains, &length/1)) == [value], "#{id}"

        ceiling = v.feats[id].repeatable.max_takes

        cited =
          (ceiling.source["kind"] == "2da" && ceiling.source) ||
            entry(id)["max_takes"]["source_2"]

        chain = Enum.find(chains, &(List.last(&1) == cited["row"]))
        assert chain, "#{id}: цитата называет строку #{cited["row"]}, а она не последняя ступень"

        if ceiling.from do
          names = Enum.map(chain, &Source.row_name(source, "feat", &1, "FEAT"))
          assert names == ceiling.from.tiers, "#{id}: имена ступеней разошлись с таблицей"
        end
      end
    end

    defp chains(ctx, id) do
      rows = ctx.families[id]
      in_family = MapSet.new(rows)
      prev = fn row -> TwoDA.int(ctx.feat, row, "PREREQFEAT1") end
      next = Map.new(rows, fn row -> {prev.(row), row} end)

      for head <- Enum.sort(rows), not MapSet.member?(in_family, prev.(head)) do
        Stream.unfold(head, fn
          nil -> nil
          row -> {row, Map.get(next, row)}
        end)
        |> Enum.to_list()
      end
    end
  end
end
