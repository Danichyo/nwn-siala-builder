defmodule BuildCalculator.Rules.PrestigeEpicScalesTest do
  @moduledoc """
  Эпические шкалы престиж-классов после 30-го уровня класса — задача 4.26.

  Эпические таблицы престиж-классов на Fandom кончаются на 30-м уровне класса,
  а таблицы игры идут дальше. Задача продлила по ним три шкалы:

    * **бонусные фиты** десяти престиж-классов — `cls_bfeat_*.2da`
      (`vanilla/class_bonus_feat_levels.json`);
    * **естественный AC** Бледного мастера (+18/+20/+22 на 32/36/40) и РДД
      (+9/+10 на 35/40) — `cls_stat_*.2da` (`vanilla/ac_bonuses.json`);
    * **Enchant Arrow** Тайного лучника (+16 … +20 на 31 … 39) —
      `cls_feat_archer.2da` и `ruleset.2da` (`vanilla/feat_attack_bonuses.json`).

  И четвёртая — задача 4.46, **только у Сиалы и не по таблице игры**:

    * **колонка «AB bonus» Мастера оружия** (`Superior weapon focus` +1 на 5-м
      плюс `Epic superior weapon focus` «at 13th level and every 3 levels
      afterwards») — ступень 31 → +8 в слое Сиалы
      (`siala_41/feat_attack_bonuses.json`). 🔴 Это **решение Dan** (кейс `BC1`,
      27.09.2026: «игра потолок не ограничивает»), **а не замер**: таблицы
      клиента рост не решают — `cls_feat_wm.2da` выдаёт фит один раз, на 13-м,
      шаг считает движок. Ванильная таблица кончается на 28 → +7 и
      не сдвинута: 31-й уровень класса у ванили недостижим.

  🔴 **Достижимость — главное, что здесь закреплено.** Престиж-класс берёт
  не больше 10 уровней до 20-го уровня персонажа (`vanilla/epic.json` →
  `epic_thresholds`, `Rules.LevelUp`), поэтому потолок уровня класса у ванили
  10 + 20 = **30** — ровно там, где кончаются таблицы Fandom, — а у Сиалы
  (кап 41) 10 + 21 = **31**. Постановка задачи исходила из «ваниль доходит
  до 30+ уровней класса»; это не так, и тест ниже держит это прогоном ядра.

  Отсюда две половины файла:

    * **ваниль** — числа за 30-м лежат в данных и доезжают до ядра, но собрать
      такой билд лестницей нельзя. Проверяется прямым билдом: `compute/2`
      о законности не спрашивает (тот же приём, что в `compute_test.exs`),
      то есть здесь проверяются ДАННЫЕ, а не достижимость;
    * **Сиала** — 31-й уровень класса достижим, и он собирается лестницей, по
      одному проверенному левелапу, как его пройдёт игрок (CLAUDE.md §3). Здесь
      правка сдвигает живые числа: бонусный слот на 31-м у Чёрного стража,
      Бледного мастера, Теневого танцора, Оборотня и Мастера оружия и Enchant
      Arrow +16 вместо +15. Почему это законно для Сиалы — хак шарда этих
      таблиц не переопределяет (`test/build_calculator/data/epic_scales_hak_test.exs`).
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}

  @flat %{str: 10, dex: 10, con: 10, int: 16, wis: 10, cha: 10}

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  # Лестница: каждый уровень проверен ядром до того, как взят.
  defp ladder(build, classes, ruleset) do
    Enum.reduce(classes, build, fn class, acc ->
      level = Build.character_level(acc) + 1

      assert Rules.validate_level_up(acc, class, ruleset) == :ok,
             "#{class} на #{level}-м уровне персонажа отказан"

      Build.add_level(acc, class)
    end)
  end

  defp caster(version),
    do:
      Build.new(
        ruleset_version: version,
        race: :human,
        alignment: :neutral_evil,
        base_abilities: @flat
      )

  # Волшебник 10 / Бледный мастер N: три уровня волшебника на вход, десять
  # уровней мастера до 20-го уровня персонажа, остальные волшебником, и мастер
  # на каждом эпическом уровне.
  defp pale_master_ladder(version, ruleset, epic_levels) do
    ladder(
      caster(version),
      List.duplicate(:wizard, 3) ++
        List.duplicate(:pale_master, 10) ++
        List.duplicate(:wizard, 7) ++ List.duplicate(:pale_master, epic_levels),
      ruleset
    )
  end

  defp class_bonus_slots(stats, level),
    do: for(%{kind: :class_bonus} = slot <- Map.get(stats.feat_slots, level, []), do: slot.id)

  defp ac_term(stats, id),
    do: Enum.find_value(stats.ac_own_terms, 0, &if(&1.id == id, do: &1.ac))

  defp enchant(stats),
    do: Enum.find_value(stats.own_attack_terms, 0, &if(&1.id == :enchant_arrow, do: &1.bonus))

  defp bow, do: Gear.new(weapon: :longbow, feats: [:siala_ranged_proficiency])

  # Воин 6 / Мастер оружия 10 / Воин 4 / Мастер оружия на всех эпических
  # уровнях: у Сиалы это Мастер оружия 31 на 41-м, у ванили — 30 на 40-м.
  #
  # Требования класса (BAB +5, Dodge, Mobility, Expertise, Spring attack,
  # Whirlwind attack, Weapon focus в рукопашном оружии, Intimidate 4) закрыты
  # фитами воина и человека до 7-го уровня; `Weapon of choice` — длинный меч,
  # в слоте Мастера оружия на его 1-м уровне. Без него колонки нет вовсе
  # (замер M2b), и тест мерил бы не то.
  #
  # ⚠️ У Сиалы до фокуса нужен фит владения (3.99: «фит владения платит
  # дважды»), поэтому первый бонусный слот воина уходит под него; у ванили
  # длинный меч воину и так по руке.
  defp wm_ladder(version, ruleset, epic_levels) do
    {first_bonus, second_bonus, third_general} =
      case version do
        "siala_41" -> {:siala_blade_proficiency, {:weapon_focus, :longsword}, :mobility}
        "vanilla" -> {{:weapon_focus, :longsword}, :mobility, :power_attack}
      end

    start =
      Build.new(
        ruleset_version: version,
        race: :human,
        alignment: :lawful_neutral,
        base_abilities: %{str: 14, dex: 13, con: 12, int: 13, wis: 10, cha: 10},
        feats: %{
          1 => %{
            :general => :dodge,
            :racial => :expertise,
            {:class_bonus, :fighter} => first_bonus
          },
          2 => %{{:class_bonus, :fighter} => second_bonus},
          3 => %{general: third_general},
          4 => %{{:class_bonus, :fighter} => :spring_attack},
          6 => %{general: :whirlwind_attack},
          7 => %{{:class_bonus, :weapon_master} => {:weapon_of_choice, :longsword}}
        },
        skills: %{1 => %{intimidate: 4}}
      )

    built =
      ladder(
        start,
        List.duplicate(:fighter, 6) ++
          List.duplicate(:weapon_master, 10) ++
          List.duplicate(:fighter, 4) ++ List.duplicate(:weapon_master, epic_levels),
        ruleset
      )

    armed = %{built | gear: Gear.new(weapon: :longsword)}

    # Законен целиком, а не только классами: ни фит, ни оружие в руках
    # не держатся на том, чего игра не дала бы.
    assert Rules.illegal_class_levels(armed, ruleset) == []
    assert Rules.illegal_feats(armed, ruleset) == []
    assert Rules.illegal_gear_weapon(armed, ruleset) == []

    armed
  end

  # Вклад ОДНОЙ записи — колонки «AB bonus» (`{:class, :weapon_master}`), а не
  # весь AB: фокус, расовый бонус и прочие термы этот тест не касаются.
  defp wm_column(stats),
    do: Enum.find_value(stats.own_attack_terms, 0, &if(&1.id == :weapon_master, do: &1.bonus))

  describe "потолок уровня престиж-класса: ваниль 30, Сиала 31" do
    test "одиннадцатый уровень до 20-го уровня персонажа ядро не даёт — на обоих", %{
      vanilla: vanilla,
      siala: siala
    } do
      for {version, ruleset} <- [{"vanilla", vanilla}, {"siala_41", siala}] do
        early = ladder(caster(version), List.duplicate(:wizard, 3), ruleset)
        early = ladder(early, List.duplicate(:pale_master, 10), ruleset)

        assert Rules.validate_level_up(early, :pale_master, ruleset) ==
                 {:error, [{:requires_character_level, 20}]},
               version
      end
    end

    test "ваниль: Бледный мастер 30 на 40-м уровне — и 31-го не взять", %{vanilla: vanilla} do
      build = pale_master_ladder("vanilla", vanilla, 20)

      assert Build.class_levels(build) == %{wizard: 10, pale_master: 30}
      assert Rules.validate_level_up(build, :pale_master, vanilla) == {:error, [level_cap: 40]}

      # Та же арифметика данными: 10 уровней до 20-го + эпические уровни
      # до капа. У ванили потолка престижа сверх этого нет (`level_cap: nil`).
      assert vanilla.prestige.pre_epic_class_level_cap +
               (vanilla.level_cap - (vanilla.epic.starts_at - 1)) == 30

      assert vanilla.prestige.level_cap == nil
    end

    test "Сиала: Бледный мастер 31 на 41-м уровне — потолок её престижа", %{siala: siala} do
      build = pale_master_ladder("siala_41", siala, 21)

      assert Build.class_levels(build) == %{wizard: 10, pale_master: 31}

      assert Rules.validate_level_up(build, :pale_master, siala) ==
               {:error, [{:level_cap, 41}, {:class_level_cap, :pale_master, 31}]}

      assert siala.prestige.pre_epic_class_level_cap +
               (siala.level_cap - (siala.epic.starts_at - 1)) == 31

      assert siala.prestige.level_cap == 31
    end
  end

  describe "ваниль: шкалы за 30-м лежат в данных и доезжают до ядра (прямым билдом)" do
    # Уровни взяты прямым списком, без лестницы: у ванили такой билд
    # недостижим (см. выше), и проверяется путь данных — таблица → ruleset →
    # число в `compute/2`.
    defp direct(prefix, class, class_levels, fields \\ []) do
      Build.new(
        [
          levels: prefix ++ List.duplicate(class, class_levels),
          base_abilities: @flat,
          race: :elf,
          alignment: :neutral_evil
        ] ++ fields
      )
    end

    test "Enchant Arrow: +15 на 30-м, +16 на 31-м, +17 на 33-м", %{vanilla: vanilla} do
      prefix = [:wizard] ++ List.duplicate(:fighter, 6)

      for {class_levels, expected} <- [{29, 15}, {30, 15}, {31, 16}, {32, 16}, {33, 17}] do
        stats = Rules.compute(direct(prefix, :arcane_archer, class_levels, gear: bow()), vanilla)
        assert enchant(stats) == expected, "Тайный лучник #{class_levels}"
      end
    end

    test "бонусный фит на уровне класса больше 30 — слот есть", %{vanilla: vanilla} do
      prefix = List.duplicate(:wizard, 3)

      # Бледный мастер 31 на 34-м уровне персонажа (3 + 31): слот мастера есть;
      # на 33-м (мастер 30) — нет, у мастера после 28-го до 31-го бонусов нет.
      stats = Rules.compute(direct(prefix, :pale_master, 31), vanilla)

      assert class_bonus_slots(stats, 34) == [{:class_bonus, :pale_master}]
      assert class_bonus_slots(stats, 33) == []

      # Тот же вопрос у всех десяти — прямо по данным: уровень 31 (у кого шаг
      # три) или 34 (у кого четыре) лежит в эпических уровнях класса.
      for {class, level} <- [
            arcane_archer: 34,
            assassin: 34,
            blackguard: 31,
            champion_of_torm: 34,
            dwarven_defender: 34,
            pale_master: 31,
            red_dragon_disciple: 34,
            shadowdancer: 31,
            shifter: 31,
            weapon_master: 31
          ] do
        assert MapSet.member?(vanilla.classes[class].epic_bonus_feat_levels, level), "#{class}"
      end
    end

    test "естественный AC: Бледный мастер 32/36/40, РДД 35/40 — по таблице игры", %{
      vanilla: vanilla
    } do
      for {class_levels, expected} <- [{28, 16}, {31, 16}, {32, 18}, {36, 20}, {37, 20}] do
        stats =
          Rules.compute(direct([:wizard, :wizard, :wizard], :pale_master, class_levels), vanilla)

        assert ac_term(stats, :bone_skin) == expected, "Бледный мастер #{class_levels}"
      end

      # 40 уровней класса — вне любого билда (40 из 40 уровней персонажа
      # в престиж-классе), поэтому таблица спрашивается напрямую.
      pale = Enum.find(vanilla.ac_bonuses.applied, &(&1.id == :bone_skin))
      assert pale.amount.ac_at_class_level[40] == 22

      for {class_levels, expected} <- [{30, 8}, {34, 8}, {35, 9}] do
        stats =
          Rules.compute(
            direct(List.duplicate(:sorcerer, 5), :red_dragon_disciple, class_levels),
            vanilla
          )

        assert ac_term(stats, :draconic_armor) == expected, "РДД #{class_levels}"
      end

      dragon = Enum.find(vanilla.ac_bonuses.applied, &(&1.id == :draconic_armor))
      assert dragon.amount.ac_at_class_level[40] == 10
    end
  end

  describe "ваниль: колонка «AB bonus» Мастера оружия не сдвинута (лестницей)" do
    # Задача 4.46 положила ступень 31 → 8 в слой Сиалы. Ванили она не видна:
    # её таблица — ровно Fandom, и на потолке её престижа (30) держится +7.
    test "Мастер оружия 28–30 — +7, 31-го не взять", %{vanilla: vanilla} do
      build = wm_ladder("vanilla", vanilla, 20)

      assert Build.class_levels(build) == %{fighter: 10, weapon_master: 30}
      assert Rules.validate_level_up(build, :weapon_master, vanilla) == {:error, [level_cap: 40]}

      for {character_level, class_level, expected} <- [
            {37, 27, 6},
            {38, 28, 7},
            {39, 29, 7},
            {40, 30, 7}
          ] do
        truncated = Build.truncate(build, character_level)
        assert Build.class_levels(truncated).weapon_master == class_level

        assert wm_column(Rules.compute(truncated, vanilla)) == expected,
               "ваниль, Мастер оружия #{class_level}"
      end

      wm = Enum.find(vanilla.attack_bonuses.applied, &(&1.id == :weapon_master))

      assert wm.amount.attack_at_class_level ==
               %{5 => 1, 13 => 2, 16 => 3, 19 => 4, 22 => 5, 25 => 6, 28 => 7}
    end
  end

  describe "Сиала: что даёт 31-й уровень престиж-класса (лестницей)" do
    # 🔴 Решение Dan `BC1` (27.09.2026), НЕ замер: «Epic superior weapon focus
    # у WM 31 — +8 („игра потолок не ограничивает“)». До задачи 4.46 здесь
    # печаталось +7 — таблица Fandom кончается на 28-м.
    test "Мастер оружия 31: колонка «AB bonus» +8; на 28–30 — +7", %{siala: siala} do
      build = wm_ladder("siala_41", siala, 21)

      assert Build.class_levels(build) == %{fighter: 10, weapon_master: 31}

      for {character_level, class_level, expected} <- [
            {37, 27, 6},
            {38, 28, 7},
            {39, 29, 7},
            {40, 30, 7},
            {41, 31, 8}
          ] do
        truncated = Build.truncate(build, character_level)
        assert Build.class_levels(truncated).weapon_master == class_level

        assert wm_column(Rules.compute(truncated, siala)) == expected,
               "Сиала, Мастер оружия #{class_level}"
      end

      # Отрицательный контроль: колонка условна оружием выбора, и без меча
      # в руках ступени 31 нет так же, как всех остальных.
      assert wm_column(Rules.compute(%{build | gear: Gear.new()}, siala)) == 0
    end

    test "Бледный мастер 31: бонусный слот на 41-м уровне персонажа, AC тот же", %{siala: siala} do
      at_30 = Rules.compute(pale_master_ladder("siala_41", siala, 20), siala)
      at_31 = Rules.compute(pale_master_ladder("siala_41", siala, 21), siala)

      assert class_bonus_slots(at_31, 41) == [{:class_bonus, :pale_master}]

      # Положительный контроль: на 40-м (мастер 30) классового слота нет.
      assert class_bonus_slots(at_30, 40) == []

      # Костяная кожа следующей ступени достигает только на 32-м — у Сиалы
      # недостижимом: +16 на 30-м и на 31-м.
      assert ac_term(at_30, :bone_skin) == 16
      assert ac_term(at_31, :bone_skin) == 16
    end

    test "Тайный лучник 31: Enchant Arrow +16, а не +15", %{siala: siala} do
      start =
        Build.new(
          ruleset_version: "siala_41",
          race: :elf,
          alignment: :true_neutral,
          base_abilities: %{@flat | dex: 14},
          feats: %{1 => %{general: {:weapon_focus, :longbow}}, 3 => %{general: :point_blank_shot}}
        )

      # Воин 6 даёт BAB +6, волшебник — аркановый уровень; десять уровней
      # лучника до 17-го, три воина до 20-го, лучник на всех 21 эпическом.
      archer =
        ladder(
          start,
          List.duplicate(:fighter, 6) ++
            [:wizard] ++
            List.duplicate(:arcane_archer, 10) ++
            List.duplicate(:fighter, 3) ++ List.duplicate(:arcane_archer, 21),
          siala
        )

      assert Build.class_levels(archer) == %{fighter: 9, wizard: 1, arcane_archer: 31}

      assert enchant(Rules.compute(%{archer | gear: bow()}, siala)) == 16
    end

    test "у пяти классов с шагом три на 31-м есть бонусный уровень, у пяти с шагом четыре — нет",
         %{siala: siala} do
      for class <- [:blackguard, :pale_master, :shadowdancer, :shifter, :weapon_master] do
        assert MapSet.member?(siala.classes[class].epic_bonus_feat_levels, 31), "#{class}"
      end

      for class <- [
            :arcane_archer,
            :assassin,
            :champion_of_torm,
            :dwarven_defender,
            :red_dragon_disciple
          ] do
        refute MapSet.member?(siala.classes[class].epic_bonus_feat_levels, 31), "#{class}"
      end
    end
  end
end
