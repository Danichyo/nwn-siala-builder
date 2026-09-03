defmodule BuildCalculator.Rules.SaveBonusesTest do
  @moduledoc """
  Прибавки к спасброскам от фитов, классов, навыков и рас — задача 1.12a.

  До неё `Rules.compute/2` складывал сейв из двух save-agnostic источников
  (то, что игрок вписал под «Вещи», и Spellcraft) и молчал про фиты и
  классовые умения совсем: ни числа, ни гэпа. Паладин 41-го уровня с CHA 18
  показывал сейвы БЕЗ модификатора харизмы Divine grace и не говорил, что
  чего-то не хватает — «форма уже закрытого бага 1.9, но по двум другим
  числам».

  Источники, по которым здесь считаются ожидания — все дословно в
  `priv/rules/vanilla/feat_save_bonuses.json`:

    * `fandom:Divine grace` (revid 71687) — «adds charisma ability modifier
      bonus **(if positive)** to all saving throws», и её же раздел Notes —
      «unlike divine grace, if the character has a negative charisma
      modifier, his saving throws are reduced instead of increased» (то есть
      это описание `Dark blessing`, а не Divine grace);
    * `fandom:Dark blessing` (revid 40991) — «add their charisma ability
      modifier bonus to all saving throws», без «if positive»;
    * `fandom:Sacred defense` (revid 41213) — «+1 bonus to all saving throws
      for every 2 levels of champion of Torm», подтверждено колонкой «Save
      bonus» таблицы класса (`fandom:Champion of Torm`, revid 71573) число
      в число;
    * `fandom:Iron will` / `Lightning reflexes` / `Great fortitude` (revid
      41151 / 41159 / 41091) — по +2 к одному сейву каждый;
    * `fandom:Epic fortitude` / `Epic reflexes` / `Epic will` (revid 41049 /
      41051 / 41423) — по +4 к одному сейву каждый;
    * `fandom:Luck of heroes` (revid 41163) — «+1 bonus on all saving
      throws», общий эпический фит;
    * `fandom:Lucky` (revid 41164) — тот же +1 ко всем трём, но расовая
      склонность Халфлинга (`type: "race"`), а не выбираемый фит.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @flat %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

  defp build(levels, fields \\ []) do
    Build.new([levels: levels, base_abilities: @flat, race: :human] ++ fields)
  end

  defp own_terms(stats, id), do: Enum.filter(stats.own_save_terms, &(&1.id == id))

  # Порча стороны капа У ЗАПИСИ — там, где она с 09.08.2026 и живёт («Divine
  # grace не входит в кап +20, а Sacred Defence входит»).
  defp with_record_cap(ruleset, id, inside?) do
    update_in(ruleset, [Access.key!(:save_bonuses), :applied], fn records ->
      for record <- records do
        if record.id == id, do: put_in(record, [:cap, :inside?], inside?), else: record
      end
    end)
  end

  describe "Divine grace / Dark blessing — модификатор харизмы, и почему они не близнецы" do
    # 🔴 Обязательная проверка задания: разница ровно модификатор CHA на всех
    # трёх, и терм назван. Сиала сдвигает выдачу фита с 1-го уровня класса на
    # 4-й (siala_41/classes.json → feat_level_shift) — сравниваются уровни
    # 3 и 4, чтобы граница выдачи сама была частью проверки.
    test "Divine grace добавляет модификатор CHA ко всем трём сейвам, поимённо", %{
      ruleset: ruleset
    } do
      before =
        Rules.compute(
          build(List.duplicate(:paladin, 3), base_abilities: %{@flat | cha: 18}),
          ruleset
        )

      after_ =
        Rules.compute(
          build(List.duplicate(:paladin, 4), base_abilities: %{@flat | cha: 18}),
          ruleset
        )

      assert after_.ability_modifiers.cha == 4
      assert before.own_save_bonus == %{fort: 0, ref: 0, will: 0}
      assert after_.own_save_bonus == %{fort: 4, ref: 4, will: 4}

      # …и весь прирост — от Grace, не от того, что 4-й уровень паладина сам
      # по себе поднимает базовую прогрессию на 4.
      base_delta = {
        after_.base_fort - before.base_fort,
        after_.base_ref - before.base_ref,
        after_.base_will - before.base_will
      }

      full_delta = {after_.fort - before.fort, after_.ref - before.ref, after_.will - before.will}

      grace_only =
        Tuple.to_list(full_delta)
        |> Enum.zip(Tuple.to_list(base_delta))
        |> Enum.map(fn {f, b} -> f - b end)

      assert grace_only == [4, 4, 4]

      assert [
               %{id: :divine_grace, save: :fort, bonus: 4},
               %{id: :divine_grace, save: :ref, bonus: 4},
               %{id: :divine_grace, save: :will, bonus: 4}
             ] = Enum.sort_by(own_terms(after_, :divine_grace), & &1.save)
    end

    # На 3-м уровне паладина фита ещё нет (Сиала выдаёт с 4-го) — ни числа,
    # ни терма.
    test "на 3-м уровне паладина Divine grace ещё не выдан", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build(List.duplicate(:paladin, 3), base_abilities: %{@flat | cha: 18}),
          ruleset
        )

      assert own_terms(stats, :divine_grace) == []
    end

    # ⚠️ Асимметрия, которую легко упустить: обе страницы описывают, казалось
    # бы, одно и то же умение, но Notes страницы Divine grace называет
    # разницу прямо. При ОТРИЦАТЕЛЬНОМ модификаторе харизмы Divine grace даёт
    # 0 (floor), а Dark blessing вычитает по-настоящему.
    test "при отрицательной харизме Divine grace даёт 0, а Dark blessing вычитает", %{
      ruleset: ruleset
    } do
      paladin =
        Rules.compute(
          build(List.duplicate(:paladin, 4), base_abilities: %{@flat | cha: 6}),
          ruleset
        )

      blackguard =
        Rules.compute(
          build(List.duplicate(:blackguard, 4), base_abilities: %{@flat | cha: 6}),
          ruleset
        )

      assert paladin.ability_modifiers.cha == -2
      assert blackguard.ability_modifiers.cha == -2

      # Divine grace: floored at 0, никакого терма (bonus == 0 не печатается).
      assert paladin.own_save_bonus == %{fort: 0, ref: 0, will: 0}
      assert own_terms(paladin, :divine_grace) == []

      # Dark blessing: честный минус, и терм назван со своим знаком.
      assert blackguard.own_save_bonus == %{fort: -2, ref: -2, will: -2}
      assert [%{bonus: -2}, %{bonus: -2}, %{bonus: -2}] = own_terms(blackguard, :dark_blessing)
    end
  end

  describe "плоское семейство — один сейв на фит" do
    # Одной таблицей: имя фита, сейв, число, и то, что два ДРУГИХ сейва не
    # трогаются (перепутанный ключ выглядел бы правильно на тесте по одной
    # строке — тот же приём, что у `Great *` в feat_ability_bonuses_test.exs).
    for {feat, save, bonus} <- [
          {:iron_will, :will, 2},
          {:great_fortitude, :fort, 2},
          {:lightning_reflexes, :ref, 2},
          {:epic_fortitude, :fort, 4},
          {:epic_reflexes, :ref, 4},
          {:epic_will, :will, 4}
        ] do
      test "#{feat} поднимает #{save} на #{bonus} и ничего больше", %{ruleset: ruleset} do
        feat = unquote(feat)
        save = unquote(save)
        bonus = unquote(bonus)

        stats =
          Rules.compute(build([:fighter], feats: %{1 => %{general: feat}}), ruleset)

        assert Map.fetch!(stats.own_save_bonus, save) == bonus

        for other <- [:fort, :ref, :will], other != save do
          assert Map.fetch!(stats.own_save_bonus, other) == 0, "#{feat} задел #{other}"
        end

        assert [%{save: ^save, bonus: ^bonus}] = own_terms(stats, feat)
      end
    end

    # Luck of heroes и Lucky дают одно и то же число (+1, все три) двумя
    # разными путями — общий эпический фит и расовая склонность — и оба
    # должны считаться, а не задваиваться при совпадении.
    test "Luck of heroes поднимает все три сейва на 1", %{ruleset: ruleset} do
      stats =
        Rules.compute(build([:fighter], feats: %{1 => %{general: :luck_of_heroes}}), ruleset)

      assert stats.own_save_bonus == %{fort: 1, ref: 1, will: 1}
    end
  end

  describe "Lucky — расовая склонность, а не выбираемый фит" do
    test "Халфлинг получает +1 ко всем трём без единого фита", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter], race: :halfling), ruleset)

      assert stats.own_save_bonus == %{fort: 1, ref: 1, will: 1}
      assert [%{source: {:race_feat, :lucky}}, _, _] = own_terms(stats, :lucky)
    end

    test "другие расы не получают Lucky", %{ruleset: ruleset} do
      for race <- [:human, :dwarf, :elf, :half_elf, :half_orc, :gnome] do
        stats = Rules.compute(build([:fighter], race: race), ruleset)
        assert own_terms(stats, :lucky) == [], "#{race}: Lucky там, где его нет"
      end
    end

    # ⚠️ Гейт — раса, а не владение фитом (тот же контроль, что у
    # `small_stature` в armor_class_test.exs): тот же id, будто бы взятый в
    # общий слот человеком, не даёт ничего — фит нельзя выбрать, потому что
    # он не общий, а расовый.
    test "Lucky, взятый будто бы в слот человеком, не даёт ничего", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter], feats: %{1 => %{general: :lucky}}), ruleset)

      assert stats.own_save_bonus == %{fort: 0, ref: 0, will: 0}
    end
  end

  describe "Sacred defense — таблица класса, а не арифметика" do
    # 🔴 Обязательная проверка задания. Плато на нечётных уровнях — то, что
    # формула `div(level, 2)` тоже дала бы (правило и правда линейное), но
    # само значение приходит из ТАБЛИЦЫ (Rules.SaveBonuses читает по шагам
    # `<= уровень`, а не считает по level), и это видно по тому, что запись
    # не эктраполирует за 30-й уровень — держит последнюю ступень.
    test "ступени держатся между чётными уровнями, не растут на нечётных", %{ruleset: ruleset} do
      table = [{1, 0}, {2, 1}, {3, 1}, {4, 2}, {6, 3}, {7, 3}, {29, 14}, {30, 15}]

      for {class_level, total} <- table do
        stats = Rules.compute(build(List.duplicate(:champion_of_torm, class_level)), ruleset)

        assert stats.own_save_bonus.fort == total, "CoT #{class_level}: fort"
        assert stats.own_save_bonus == %{fort: total, ref: total, will: total}
      end
    end

    # ⚠️ Уровень 41 — не произвольный: `div(41, 2) = 20`, а таблица за 30-м
    # держит последнее значение (15). Формула и таблица здесь РАСХОДЯТСЯ на
    # целых 5 очков — единственная точка на всей лестнице, где «читаем
    # таблицу» и «считаем по формуле» дают разный ответ (на 31-м, например,
    # `div(31, 2) = 15` совпадает с таблицей случайно). Без этой проверки
    # порча «замени таблицу на `div(level, 2)`» зеленеет все тесты файла —
    # уже наступали при написании этого самого теста.
    test "за 30-м уровнем таблицы держится последнее известное значение, не арифметика", %{
      ruleset: ruleset
    } do
      at_31 = Rules.compute(build(List.duplicate(:champion_of_torm, 31)), ruleset)
      at_41 = Rules.compute(build(List.duplicate(:champion_of_torm, 41)), ruleset)

      assert at_31.own_save_bonus == %{fort: 15, ref: 15, will: 15}
      assert at_41.own_save_bonus == %{fort: 15, ref: 15, will: 15}
    end
  end

  describe "частичное покрытие — фит даёт больше, чем мы считаем" do
    # Snake blood: +1 Reflex безусловно, плюс ДОПОЛНИТЕЛЬНЫЙ +2 Fortitude
    # только против яда. Считается первая половина, вторая не считается и не
    # подмешивается в Fort.
    test "Snake blood поднимает только Reflex", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter], feats: %{1 => %{general: :snake_blood}}), ruleset)

      assert stats.own_save_bonus == %{fort: 0, ref: 1, will: 0}
    end

    # Strong soul: +1 Fort и Will безусловно, плюс ДОПОЛНИТЕЛЬНЫЙ +1 к любому
    # сейву против death magic — вторая половина не считается.
    test "Strong soul поднимает Fort и Will, но не Reflex", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter], feats: %{1 => %{general: :strong_soul}}), ruleset)

      assert stats.own_save_bonus == %{fort: 1, ref: 0, will: 1}
    end

    # Bullheaded: +1 Will безусловно, плюс +2 сопротивления Насмешке — которое
    # не сейв вовсе (уже отдельно в feat_skill_bonuses.json).
    test "Bullheaded поднимает только Will", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter], feats: %{1 => %{general: :bullheaded}}), ruleset)

      assert stats.own_save_bonus == %{fort: 0, ref: 0, will: 1}
    end
  end

  describe "узкие прибавки — не число, и с 3.95 не оговорка" do
    # Каждая своим билдом: класс/раса действительно владеет умением, а число
    # НЕ входит в own_save_bonus. Это половина, которая не менялась ни разу.
    #
    # ⚠️ Вторая половина менялась: здесь стояло `assert {:not_modelled,
    # {:save_bonus, …}} in stats.gaps` — «гэп называет источник поимённо».
    # Задача 3.95 (25.08.2026) оговорку сняла решением владельца
    # (`not_a_gap`, довод `feat_description`): описание фита называет и число,
    # и условие («+2 racial bonus on saving throws vs. poison»), и видно оно
    # в конструкторе (3.87) и на экране просмотра (3.94), то есть наша фраза
    # «не всегда и не против всего» ничего к нему не добавляла.
    #
    # 🔴 Числа при этом обязаны остаться прежними, и проверяются они здесь
    # ПЕРВОЙ строкой: правка про признание, а не про расчёт. Тест на том же
    # билде, что и раньше, — иначе «ноль прибавки» и «ноль оговорок» нельзя
    # было бы прочитать как одно наблюдение.
    test "Hardiness vs. poisons Гнома (Dwarf) не считается и не оговаривается",
         %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter], race: :dwarf), ruleset)

      assert stats.own_save_bonus == %{fort: 0, ref: 0, will: 0}
      refute {:not_modelled, {:save_bonus, :hardiness_vs_poisons}} in stats.gaps
      refute {:not_modelled, {:save_bonus, :hardiness_vs_spells}} in stats.gaps
    end

    test "Poison save ассасина не считается и не оговаривается", %{ruleset: ruleset} do
      stats = Rules.compute(build(List.duplicate(:assassin, 2)), ruleset)

      assert stats.own_save_bonus == %{fort: 0, ref: 0, will: 0}
      refute {:not_modelled, {:save_bonus, :poison_save}} in stats.gaps
    end

    # 🔴 Отрицательный контроль: без него две строки выше зеленели бы и на
    # модели, которая перестала считать сейвы вовсе или выбросила форму гэпа.
    # Запись СИНТЕТИЧЕСКАЯ и решения владельца не несёт — то есть проверяется
    # механизм, а не сегодняшний состав данных. Живой пример здесь был бы
    # ловушкой: завтра решение получит и он.
    test "механизм оговорки жив — запись без решения владельца её приносит",
         %{ruleset: ruleset} do
      record = %{
        id: :made_up_narrow_bonus,
        source: {:race_feat, :hardiness_vs_poisons},
        verdict: :not_modelled,
        saves: [:fort],
        amount: nil,
        affects: ["saving_throws"]
      }

      synthetic = Map.put(ruleset, :save_bonuses, %{applied: [], unmodelled: [record]})
      stats = Rules.compute(build([:fighter], race: :dwarf), synthetic)

      assert {:not_modelled, {:save_bonus, :made_up_narrow_bonus}} in stats.gaps
    end

    # ⚠️ Положительный контроль к нему же: билд без единого такого умения
    # не несёт ни одного гэпа `save_bonus` и на живых данных.
    test "у билда без таких умений ни одного гэпа save_bonus нет", %{ruleset: ruleset} do
      stats = Rules.compute(build(List.duplicate(:wizard, 20)), ruleset)

      refute Enum.any?(stats.gaps, &match?({:not_modelled, {:save_bonus, _}}, &1))
    end
  end

  # ⚠️ Здесь стояли «ярость варвара», «стойка Гномьего защитника» и
  # «Divine wrath» как тесты на ОГОВОРКУ — ровно так же, как узкие прибавки
  # блоком выше. ПЕРЕСМОТРЕНО 18.08.2026 (шестой файл семейства прибавок,
  # `feat_save_bonuses.json`): все три — «включается и кончается» (раз в
  # день / ограниченное число раз, на время режима), получатель `buff`,
  # а бафф — не наш ответ (решение Dan 10.08.2026, CLAUDE.md §9). Первая
  # половина каждого теста не тронута и осталась главной: прибавка
  # по-прежнему не в числе. Вторая — про то, что оговорка называет себя, —
  # верна теперь только на ванили, у которой словаря получателей нет вовсе.
  describe "условные прибавки: считать нельзя, а называть — только у ванили" do
    # Ярость и стойка — каждая своим билдом, число не приезжает ни одним
    # путём, а оговорка снимается словарём получателей и только им.
    for {levels, id, note} <- [
          {List.duplicate(:barbarian, 2), :barbarian_rage, "ярость варвара"},
          {List.duplicate(:dwarven_defender, 1), :defensive_stance, "стойка Гномьего защитника"}
        ] do
      test "#{note}: не в числе, а оговорка — только у ванили", %{
        ruleset: ruleset,
        vanilla: vanilla
      } do
        levels = unquote(Macro.escape(levels))
        id = unquote(id)

        b = build(levels)
        stats = Rules.compute(b, ruleset)

        assert stats.own_save_bonus == %{fort: 0, ref: 0, will: 0}
        refute {:not_modelled, {:save_bonus, id}} in stats.gaps

        # 🔴 Отрицательный контроль: запись жива, снимает её только словарь
        # получателей, которого у ванили нет вовсе.
        vanilla_stats = Rules.compute(b, vanilla)
        assert {:not_modelled, {:save_bonus, id}} in vanilla_stats.gaps
        assert vanilla_stats.own_save_bonus == %{fort: 0, ref: 0, will: 0}
      end
    end

    # 🔴 Divine wrath — своя форма теста: владение начинается на 5-м уровне
    # класса (Сиала сдвигает выдачу с 1-го), и это единственная запись файла,
    # у которой граница выдачи сама себя проверяет. До правки Сиала на 4-м
    # молчала (умения ещё нет), на 5-м говорила; теперь молчит на обоих
    # уровнях, но по разным причинам — «не владеет» и «бафф».
    test "Divine wrath Чемпиона Торма: оговорки нет ни на 4-м, ни на 5-м — только у ванили", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      below = Rules.compute(build(List.duplicate(:champion_of_torm, 4)), ruleset)
      at = Rules.compute(build(List.duplicate(:champion_of_torm, 5)), ruleset)

      refute {:not_modelled, {:save_bonus, :divine_wrath}} in below.gaps
      refute {:not_modelled, {:save_bonus, :divine_wrath}} in at.gaps
      assert at.own_save_bonus.fort == below.own_save_bonus.fort

      # На ванили граница выдачи по-прежнему видна: молчание на 4-м (умения
      # ещё нет) и оговорка на 5-м (умение есть, но не посчитано).
      vanilla_below = Rules.compute(build(List.duplicate(:champion_of_torm, 4)), vanilla)
      vanilla_at = Rules.compute(build(List.duplicate(:champion_of_torm, 5)), vanilla)

      refute {:not_modelled, {:save_bonus, :divine_wrath}} in vanilla_below.gaps
      assert {:not_modelled, {:save_bonus, :divine_wrath}} in vanilla_at.gaps
    end

    # ⚠️ Положительный контроль: у билда без этих умений оговорки нет нигде —
    # ни на Сиале (никогда не было бы), ни на ванили (умения нет вовсе).
    test "у билда без таких умений оговорки нет ни там, ни там", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      wizard = build(List.duplicate(:wizard, 20))

      refute Enum.any?(Rules.compute(wizard, ruleset).gaps, &buff_save_gap?/1)
      refute Enum.any?(Rules.compute(wizard, vanilla).gaps, &buff_save_gap?/1)
    end
  end

  defp buff_save_gap?(gap) do
    match?(
      {:not_modelled, {:save_bonus, id}}
      when id in [:barbarian_rage, :defensive_stance, :divine_wrath],
      gap
    )
  end

  describe "граница с задачей 1.12b — атака, не сейв" do
    # Epic prowess и Superior weapon focus — маркеры, а не находки: они
    # принадлежат атаке и не должны ни считаться, ни давать гэп про сейвы.
    test "Epic prowess не двигает сейвы и не оставляет гэп про сейвы", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 21)
      plain = Rules.compute(build(levels), ruleset)

      with_feat =
        Rules.compute(build(levels, feats: %{21 => %{general: :epic_prowess}}), ruleset)

      assert {plain.fort, plain.ref, plain.will} ==
               {with_feat.fort, with_feat.ref, with_feat.will}

      refute Enum.any?(with_feat.gaps, &match?({:not_modelled, {:save_bonus, :epic_prowess}}, &1))
    end
  end

  describe "потолок +20: один клип на сейв, и он покрывает НЕ ВСЕ прибавки" do
    # 🔴 Обязательная проверка задания (правка 09.08.2026). Dan, из игрового
    # опыта: «У сейвов тоже фиты не входят в кап +20. Можешь взять и luck of
    # heroes, и форту +2, и форту +4, и потом ещё с вещей набрать +20» — то есть
    # ровно этот билд, названный им своими числами.
    #
    # До правки все три фита клипались вместе с вещами и Fort был 42; теперь
    # вещи +20 упираются в потолок сами, а +7 от фитов ложатся сверху → 49.
    test "воин 41 с тремя фитами и вещами +20: Fort 49, а не 42", %{ruleset: ruleset} do
      alias BuildCalculator.Rules.Gear

      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 41),
            gear: Gear.new(saves: 20),
            feats: %{
              1 => %{general: :great_fortitude},
              3 => %{general: :luck_of_heroes},
              21 => %{general: :epic_fortitude}
            }
          ),
          ruleset
        )

      # Предпосылка: 2 + 4 + 1 = 7 к Fort, по +1 к Ref и Will от Luck of heroes.
      assert stats.own_save_bonus == %{fort: 7, ref: 1, will: 1}
      assert stats.gear_save_bonus == 20

      # Вещи +20 = ровно потолок, поэтому клипа НЕТ вовсе, а фиты идут сверху.
      assert stats.save_bonus == %{fort: 27, ref: 21, will: 21}
      assert stats.save_cap_clipped == %{fort: 0, ref: 0, will: 0}
      assert {stats.fort, stats.ref, stats.will} == {49, 37, 37}
      assert Enum.filter(stats.capped, &(&1 in [:fort_save, :ref_save, :will_save])) == []
    end

    # 🔴 Вторая обязательная проверка: `Sacred defense` — ЕДИНСТВЕННАЯ запись
    # обоих файлов разметки, которая осталась ВНУТРИ капа («Divine grace не
    # входит в кап +20, а Sacred Defence входит»). Она обязана срезаться, и флаг
    # капа обязан стоять.
    test "Sacred defense режется: Чемпион Торма 10 с вещами +20", %{ruleset: ruleset} do
      alias BuildCalculator.Rules.Gear

      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 10) ++ List.duplicate(:champion_of_torm, 10),
            gear: Gear.new(saves: 20)
          ),
          ruleset
        )

      assert stats.own_save_bonus == %{fort: 5, ref: 5, will: 5}
      assert Enum.map(own_terms(stats, :sacred_defense), & &1.under_cap?) == [true, true, true]

      # 20 + 5 = 25 → 20, срезано 5, и по всем трём сейвам сразу.
      assert stats.save_bonus == %{fort: 20, ref: 20, will: 20}
      assert stats.save_cap_clipped == %{fort: -5, ref: -5, will: -5}

      for flag <- [:fort_save, :ref_save, :will_save], do: assert(flag in stats.capped)
    end

    # 🔴 Третья обязательная проверка: ОБЕ стороны на одном билде. Паладин
    # с `Divine grace` (поверх) плюс Чемпион Торма с `Sacred defense` (внутри)
    # плюс вещи +20 — срезается только вторая часть.
    test "Divine grace поверх, Sacred defense внутри, один билд", %{ruleset: ruleset} do
      alias BuildCalculator.Rules.Gear

      stats =
        Rules.compute(
          build(List.duplicate(:paladin, 10) ++ List.duplicate(:champion_of_torm, 10),
            base_abilities: %{@flat | cha: 18},
            gear: Gear.new(saves: 20)
          ),
          ruleset
        )

      assert Enum.map(stats.own_save_terms, &{&1.id, &1.save, &1.bonus, &1.under_cap?}) == [
               {:divine_grace, :fort, 4, false},
               {:divine_grace, :ref, 4, false},
               {:divine_grace, :will, 4, false},
               {:sacred_defense, :fort, 5, true},
               {:sacred_defense, :ref, 5, true},
               {:sacred_defense, :will, 5, true}
             ]

      # Внутри: вещи 20 + Sacred defense 5 = 25 → 20 (срезано 5).
      # Поверх: Divine grace +4. Итого 24, а не 20 (как было) и не 29.
      assert stats.save_bonus == %{fort: 24, ref: 24, will: 24}
      assert stats.save_cap_clipped == %{fort: -5, ref: -5, will: -5}
      assert {stats.fort, stats.ref, stats.will} == {38, 34, 30}
    end

    # 🔴 ПОРЧА №1 из задания: `Sacred defense` наружу — число обязано поехать.
    # ⚠️ Сравнивается СПИСОК ТЕРМОВ и клип, а не только итог: у терма, ставшего
    # внешним, сумма-то как раз меняется, но именно проверка стороны у каждого
    # терма ловит порчу, которая случайно сойдётся по сумме.
    test "порча: Sacred defense вынесли из-под капа", %{ruleset: ruleset} do
      alias BuildCalculator.Rules.Gear

      broken = with_record_cap(ruleset, :sacred_defense, false)

      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 10) ++ List.duplicate(:champion_of_torm, 10),
            gear: Gear.new(saves: 20)
          ),
          broken
        )

      assert Enum.map(own_terms(stats, :sacred_defense), & &1.under_cap?) == [false, false, false]
      assert stats.save_bonus == %{fort: 25, ref: 25, will: 25}
      assert stats.save_cap_clipped == %{fort: 0, ref: 0, will: 0}
    end

    # 🔴 ПОРЧА №2 из задания, обратная: какой-нибудь фит внутрь капа.
    test "порча: Luck of heroes загнали под кап", %{ruleset: ruleset} do
      alias BuildCalculator.Rules.Gear

      broken = with_record_cap(ruleset, :luck_of_heroes, true)

      stats =
        Rules.compute(
          build([:fighter],
            gear: Gear.new(saves: 20),
            feats: %{1 => %{general: :luck_of_heroes}}
          ),
          broken
        )

      assert Enum.map(own_terms(stats, :luck_of_heroes), & &1.under_cap?) == [true, true, true]
      assert stats.save_bonus == %{fort: 20, ref: 20, will: 20}
      assert stats.save_cap_clipped == %{fort: -1, ref: -1, will: -1}
    end

    # 🔴 ПОРЧА №3 из задания: вещи наружу. Их сторона лежит НЕ у записи, а у вида
    # источника (записи у вещей нет вовсе) — то есть эта порча проверяет второй
    # уровень правила, и без неё две первые зеленели бы у кода, который читает
    # только записи.
    test "порча: вещи вынесли из-под капа", %{ruleset: ruleset} do
      alias BuildCalculator.Rules.Gear

      broken =
        put_in(
          ruleset,
          [Access.key!(:stat_cap_sources), :saving_throw_bonus, :gear, :inside?],
          false
        )

      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 10) ++ List.duplicate(:champion_of_torm, 10),
            gear: Gear.new(saves: 20)
          ),
          broken
        )

      # Под капом остаётся один Sacred defense (+5) — потолок не задет вовсе.
      assert stats.save_bonus == %{fort: 25, ref: 25, will: 25}
      assert stats.save_cap_clipped == %{fort: 0, ref: 0, will: 0}
    end

    # 🔴 ПОРЧА №4 из задания: признак записи игнорируется и берётся вид
    # источника. Вид подложен прямо в копию ruleset'а (загрузчик такую копию не
    # собрал бы — вид, у которого есть записи, роняет сборку), и запись обязана
    # победить. Без этого теста код, читающий `covers_source?/3` вместо
    # `covers_record?/3`, зеленел бы: у настоящих данных вид `feat` не назван, а
    # неназванный по умолчанию считается ВНУТРИ капа — то есть ошибка вернула бы
    # ровно прежнее, неверное поведение.
    test "запись перекрывает вид источника", %{ruleset: ruleset} do
      alias BuildCalculator.Rules.Gear

      lying_kind =
        put_in(ruleset, [Access.key!(:stat_cap_sources), :saving_throw_bonus, :feat], %{
          inside?: true,
          assumed?: false
        })

      stats =
        Rules.compute(
          build([:fighter], gear: Gear.new(saves: 20), feats: %{1 => %{general: :iron_will}}),
          lying_kind
        )

      assert Enum.map(own_terms(stats, :iron_will), & &1.under_cap?) == [false]
      assert stats.save_bonus == %{fort: 20, ref: 20, will: 22}
    end

    # ⚠️ Обратный контроль — сердце задачи 1.12a, и оно осталось верным: клип
    # независим по сейву. `Iron will` трогает только Will, поэтому в потолок
    # упирается только Will.
    test "клип независим по сейву: под капом только Sacred defense", %{ruleset: ruleset} do
      alias BuildCalculator.Rules.Gear

      # Вещи 19 + Sacred defense 2 = 21 → 20 по всем трём… но проверять
      # независимость надо на источнике, который бьёт в ОДИН сейв, а такой
      # внутри капа остался ровно один — вещи. Поэтому Will поднимаем поверх
      # капа фитом и смотрим, что флаг капа он не ставит.
      stats =
        Rules.compute(
          build(List.duplicate(:champion_of_torm, 4),
            gear: Gear.new(saves: 19),
            feats: %{1 => %{general: :iron_will}}
          ),
          ruleset
        )

      # Внутри: 19 + 2 (Sacred defense на 4-м уровне класса) = 21 → 20.
      # Поверх: Iron will +2 к Will.
      assert stats.save_bonus == %{fort: 20, ref: 20, will: 22}
      assert stats.save_cap_clipped == %{fort: -1, ref: -1, will: -1}
    end

    # ⚠️ И проверка того, что раньше ломалось и не должно сломаться снова: клип
    # по СУММЕ источников, а не по каждому в отдельности. Ни вещи (14), ни
    # Spellcraft (8) не превышают +20 сами по себе — только сумма (22). Клип
    # «по частям» пропустил бы 22 без среза (CLAUDE.md §9).
    test "клип считает СУММУ вещей и Spellcraft, а не каждое по отдельности", %{ruleset: ruleset} do
      alias BuildCalculator.Rules.Gear

      stats =
        Rules.compute(
          build(List.duplicate(:wizard, 40),
            base_abilities: %{@flat | int: 14},
            gear: Gear.new(saves: 14),
            skills: %{40 => %{spellcraft: 40}}
          ),
          ruleset
        )

      assert stats.gear_save_bonus == 14
      assert stats.skill_save_bonus == 8
      assert stats.save_bonus == %{fort: 20, ref: 20, will: 20}
      assert stats.save_cap_clipped == %{fort: -2, ref: -2, will: -2}
      assert :fort_save in stats.capped
    end

    # 🔴 Spellcraft ОСТАЛСЯ ВНУТРИ капа, и это проверено примером самого Dan:
    # 30 рангов дают +6, значит с вещей до потолка добирается ровно +14. Ни один
    # источник по отдельности потолка не касается — только сумма, и она обязана
    # дать ровно 20 без флага. Вторая половина теста двигает вещи до +20: 6 + 20
    # = 26 → срез до 20 с флагом.
    #
    # ⚠️ Обе половины в одном тесте намеренно: поодиночке каждая зеленела бы и
    # у кода, который вынес Spellcraft из-под капа (тогда первая дала бы те же 20
    # другим путём, а вторая — 26 вместо 20).
    test "Spellcraft внутри капа: 6 + 14 = ровно 20, 6 + 20 = срез", %{ruleset: ruleset} do
      alias BuildCalculator.Rules.Gear

      levels = List.duplicate(:wizard, 30)
      ranks = %{30 => %{spellcraft: 30}}

      exact =
        Rules.compute(
          build(levels,
            base_abilities: %{@flat | int: 14},
            skills: ranks,
            gear: Gear.new(saves: 14)
          ),
          ruleset
        )

      assert exact.skill_save_bonus == 6
      assert exact.gear_save_bonus == 14
      assert exact.save_bonus == %{fort: 20, ref: 20, will: 20}
      assert exact.save_cap_clipped == %{fort: 0, ref: 0, will: 0}
      assert Enum.filter(exact.capped, &(&1 in [:fort_save, :ref_save, :will_save])) == []

      over =
        Rules.compute(
          build(levels,
            base_abilities: %{@flat | int: 14},
            skills: ranks,
            gear: Gear.new(saves: 20)
          ),
          ruleset
        )

      assert over.save_bonus == %{fort: 20, ref: 20, will: 20}
      assert over.save_cap_clipped == %{fort: -6, ref: -6, will: -6}

      for flag <- [:fort_save, :ref_save, :will_save], do: assert(flag in over.capped)
    end

    # Граничный случай по обоим измерениям сразу: **41-й уровень и четыре
    # класса** (кап Сиалы и лимит классов), три источника собственных прибавок
    # по разные стороны потолка и вещи +20. Тест стоит здесь, а не в
    # `compute_test`, потому что ловит он именно сторону капа: у трёх сейвов
    # РАЗНЫЕ итоги (Will выше на +4 за `Epic will`), при одном и том же срезе −5.
    test "четыре класса на 41-м: обе стороны капа и три разных сейва", %{ruleset: ruleset} do
      alias BuildCalculator.Rules.Gear

      levels =
        List.duplicate(:paladin, 10) ++
          List.duplicate(:champion_of_torm, 10) ++
          List.duplicate(:fighter, 10) ++ List.duplicate(:monk, 11)

      stats =
        Rules.compute(
          build(levels,
            base_abilities: %{@flat | cha: 18},
            gear: Gear.new(saves: 20),
            feats: %{21 => %{general: :epic_will}}
          ),
          ruleset
        )

      assert map_size(stats.class_levels) == 4
      assert stats.character_level == 41

      assert Enum.map(stats.own_save_terms, &{&1.id, &1.save, &1.bonus, &1.under_cap?}) == [
               {:divine_grace, :fort, 4, false},
               {:divine_grace, :ref, 4, false},
               {:divine_grace, :will, 4, false},
               {:sacred_defense, :fort, 5, true},
               {:sacred_defense, :ref, 5, true},
               {:sacred_defense, :will, 5, true},
               {:epic_will, :will, 4, false}
             ]

      # Внутри: 20 вещей + 5 Sacred defense = 25 → 20 (срезано 5, одинаково на
      # всех трёх). Поверх: Divine grace +4 на все три и Epic will +4 на Will.
      assert stats.save_bonus == %{fort: 24, ref: 24, will: 28}
      assert stats.save_cap_clipped == %{fort: -5, ref: -5, will: -5}
      assert {stats.fort, stats.ref, stats.will} == {48, 44, 44}
    end

    # Холостой контроль: ничего не введено, ничего не взято — капа нет вовсе.
    test "без источников клипа нет", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter]), ruleset)

      assert stats.save_bonus == %{fort: 0, ref: 0, will: 0}
      assert stats.save_cap_clipped == %{fort: 0, ref: 0, will: 0}
      assert Enum.filter(stats.capped, &(&1 in [:fort_save, :ref_save, :will_save])) == []
    end
  end

  describe "двойной учёт: старые источники не сдвинулись" do
    # gear_save_bonus и skill_save_bonus остаются save-agnostic скалярами —
    # задача 1.12a добавляет третий источник, а не переписывает эти два.
    test "вещи и Spellcraft остаются одним числом на все три сейва", %{ruleset: ruleset} do
      alias BuildCalculator.Rules.Gear

      stats =
        Rules.compute(
          build(List.duplicate(:wizard, 20),
            gear: Gear.new(saves: 5),
            skills: %{20 => %{spellcraft: 23}}
          ),
          ruleset
        )

      assert stats.gear_save_bonus == 5
      assert stats.skill_save_bonus == 4
      assert stats.own_save_bonus == %{fort: 0, ref: 0, will: 0}
      assert stats.save_bonus == %{fort: 9, ref: 9, will: 9}
    end

    # Ванильный ruleset несёт ту же разметку (файл общий), поэтому Iron will
    # считается одинаково на обоих.
    test "числа одинаковы на обоих ruleset'ах", %{ruleset: ruleset, vanilla: vanilla} do
      b = build([:fighter], feats: %{1 => %{general: :iron_will}})

      assert Rules.compute(b, ruleset).own_save_bonus == Rules.compute(b, vanilla).own_save_bonus
    end
  end

  # `saves_naked` — сейвы персонажа, у которого блок «Вещи» пуст. Заведено
  # 16.08.2026 задачей S2: требование фита по сейву сравнивается с ним, а не
  # с тем, что показано в панели («вещи на спасы также не откроют фит, должен
  # быть закрыт» — Dan, `GAME_CHECKS.md` S2).
  #
  # Здесь проверяется САМО ЧИСЛО; что его читает требование — в
  # `prereqs_test.exs`. Разделено намеренно: поле обязано быть верным и для
  # интерфейса тоже, а тест «фит не открылся» зеленел бы и на числе,
  # ошибающемся в ту же сторону.
  describe "saves_naked — сейв без блока «Вещи»" do
    alias BuildCalculator.Rules.Gear

    # Вещь добирается до сейва ТРЕМЯ дорогами, и «голое» число обязано терять
    # все три. Одна дорога в тесте выглядела бы правильно и при двух других
    # незакрытых — ровно так правка и могла бы остаться половинчатой.
    test "уходят все три дороги вещи: число, характеристика и фит с предмета", %{
      ruleset: ruleset
    } do
      levels = List.duplicate(:fighter, 11)
      bare = Rules.compute(build(levels), ruleset)

      typed = Rules.compute(build(levels, gear: Gear.new(saves: 20)), ruleset)
      belt = Rules.compute(build(levels, gear: Gear.new(abilities: %{con: 12})), ruleset)
      amulet = Rules.compute(build(levels, gear: Gear.new(feats: [:great_fortitude])), ruleset)

      # Положительный контроль: все три вещи настоящие и до числа доезжают.
      assert {bare.fort, typed.fort, belt.fort, amulet.fort} == {7, 27, 13, 9}

      # …и ни одна из трёх не двигает голое.
      for stats <- [bare, typed, belt, amulet] do
        assert stats.saves_naked == %{fort: 7, ref: 3, will: 3}
      end
    end

    # ⚠️ Своё остаётся своим: ранги Spellcraft и фит из слота — это не вещь,
    # снять их нельзя, и в голом числе они обязаны быть. Без этой половины
    # правка ушла бы в другую крайность: «голым» стало бы значить «без всего».
    test "Spellcraft и фит из слота в голое число входят", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 11)

      spellcraft = Rules.compute(build(levels, skills: %{11 => %{spellcraft: 5}}), ruleset)
      slot = Rules.compute(build(levels, feats: %{1 => %{general: :great_fortitude}}), ruleset)

      assert spellcraft.saves_naked.fort == 8
      assert slot.saves_naked.fort == 9

      # …и оба совпадают со своим одетым числом, потому что вещей нет вовсе.
      assert spellcraft.saves_naked.fort == spellcraft.fort
      assert slot.saves_naked.fort == slot.fort
    end

    # 🔴 Главное, ради чего голое число считается ВТОРЫМ ПРОХОДОМ, а не
    # вычитанием: потолок +20 стоит внутри формулы. Здесь Spellcraft даёт +8,
    # вещи +20, оба под капом — после клипа остаётся ровно 20, и «итог минус
    # вещи» напечатало бы, что своего у билда нет вообще.
    test "голое число — не «итог минус вещи», когда кап кусает", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build(List.duplicate(:rogue, 41),
            skills: %{41 => %{spellcraft: 40}},
            gear: Gear.new(saves: 20)
          ),
          ruleset
        )

      assert stats.skill_save_bonus == 8
      assert stats.gear_save_bonus == 20
      assert stats.save_bonus.fort == 20
      assert stats.save_cap_clipped.fort == -8

      # Своих +8 никуда не делось: их съел не потолок, а вещи, которых
      # у голого персонажа нет.
      assert stats.fort - stats.saves_naked.fort == 12
      assert stats.fort - stats.gear_save_bonus != stats.saves_naked.fort
    end

    # Разметка сейвов лежит в общем файле, поэтому число обязано совпасть
    # на обоих ruleset'ах — как совпадает `own_save_bonus` выше.
    test "число одинаково на обоих ruleset'ах", %{ruleset: ruleset, vanilla: vanilla} do
      b =
        build(List.duplicate(:fighter, 11),
          feats: %{1 => %{general: :great_fortitude}},
          gear: Gear.new(saves: 20)
        )

      assert Rules.compute(b, ruleset).saves_naked == Rules.compute(b, vanilla).saves_naked
    end
  end

  # `saves_for_prereqs` — число, с которым сравнивается ТРЕБОВАНИЕ фита по сейву.
  # Заведено 17.08.2026 задачей S3: у `Luck of heroes` источник исключает
  # прибавку из требования поимённо («The fortitude bonus from ''luck of heroes''
  # does not count towards the fortitude required», `fandom:Resist energy`,
  # revid 63837), и **замер Dan подтвердил строку на Сиале**:
  #
  #   > «Проверил, на 9 уровне со взятым luck of heroes фит Resist energy был
  #   > не доступен. На 12 уже доступен».
  #
  # Здесь проверяется САМО ЧИСЛО, а что его читает требование — в
  # `prereqs_test.exs`. Разделено по той же причине, что и у `saves_naked`
  # выше: «фит не открылся» зеленел бы и на числе, ошибающемся в ту же сторону.
  describe "saves_for_prereqs — что засчитывает требование" do
    alias BuildCalculator.Rules.SaveBonuses

    defp with_luck(levels) do
      build(levels,
        base_abilities: %{@flat | con: 12},
        feats: %{1 => %{{:general, 1} => :luck_of_heroes}}
      )
    end

    # 🔴 Оба числа замера, в одном тесте с эффектом: на 9-м в листе стоит ровно
    # требуемая Стойкость 8, а засчитывается 7 — это и есть та единица, на
    # которой в игре фита нет. На 12-м базовой Стойкости хватает без Удачи,
    # и обе половины сходятся.
    test "воин 9 с Удачей: в листе 8, в требовании 7; на 12-м — 10 и 9", %{ruleset: ruleset} do
      nine = Rules.compute(with_luck(List.duplicate(:fighter, 9)), ruleset)
      twelve = Rules.compute(with_luck(List.duplicate(:fighter, 12)), ruleset)

      assert {nine.fort, nine.saves_naked.fort, nine.saves_for_prereqs.fort} == {8, 8, 7}
      assert {twelve.fort, twelve.saves_naked.fort, twelve.saves_for_prereqs.fort} == {10, 10, 9}
    end

    # 🔴 Половина, без которой правку легко «доделать» до отмены эффекта:
    # исключена прибавка ИЗ ТРЕБОВАНИЯ, а не из сейва. В листе Удача по-прежнему
    # даёт +1 на все три и стоит своей строкой в разборе.
    test "эффект не тронут: +1 на все три сейва и терм на месте", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 9)
      luck = Rules.compute(with_luck(levels), ruleset)
      plain = Rules.compute(build(levels, base_abilities: %{@flat | con: 12}), ruleset)

      for save <- [:fort, :ref, :will] do
        assert Map.fetch!(luck, save) - Map.fetch!(plain, save) == 1
      end

      assert Enum.map(own_terms(luck, :luck_of_heroes), &{&1.save, &1.bonus}) ==
               [{:fort, 1}, {:ref, 1}, {:will, 1}]

      # …и вычтено ровно то же самое: голое минус засчитанное = один Luck.
      for save <- [:fort, :ref, :will] do
        assert Map.fetch!(luck.saves_naked, save) - Map.fetch!(luck.saves_for_prereqs, save) == 1
      end
    end

    # 🔴 Положительный контроль, без которого правка ушла бы в ложную
    # НЕлегальность: остальные тринадцать прибавок требование выполняют.
    # Взяты все четыре формы разметки — плоский фит, модификатор характеристики,
    # таблица по уровню класса и навык, — и обе стороны капа.
    test "остальные прибавки засчитываются: фит, классовое умение, таблица, Spellcraft", %{
      ruleset: ruleset
    } do
      fighter = List.duplicate(:fighter, 9)
      paladin = List.duplicate(:paladin, 9)
      torm = List.duplicate(:fighter, 10) ++ List.duplicate(:champion_of_torm, 10)

      cases = [
        {:great_fortitude, fighter, [feats: %{1 => %{{:general, 1} => :great_fortitude}}], 2},
        {:spellcraft, fighter, [skills: %{9 => %{spellcraft: 5}}], 1},
        {:divine_grace, paladin, [base_abilities: %{@flat | cha: 18}], 4},
        {:sacred_defense, torm, [], 5}
      ]

      # ⚠️ Телосложение у всех четырёх ровно 10, то есть модификатор ноль —
      # поэтому `base_fort + прибавка` и есть весь сейв, и сверять можно
      # напрямую, не собирая второй билд «без этого умения» (у классового
      # умения такого билда и не бывает: убрать уровни Чемпиона Торма значит
      # изменить и базовую прогрессию).
      for {name, levels, fields, expected} <- cases do
        stats = Rules.compute(build(levels, fields), ruleset)

        # Прибавка настоящая и до листа доезжает…
        assert stats.save_bonus.fort == expected, inspect(name)
        assert stats.fort == stats.base_fort + expected, inspect(name)

        # …и ровно та же прибавка стоит в числе, которое видит требование.
        assert stats.saves_for_prereqs.fort == stats.base_fort + expected, inspect(name)
        assert stats.saves_for_prereqs == stats.saves_naked, inspect(name)
      end
    end

    # 🔴 Тот же самый +1 на те же три сейва, той же формы `flat` — и он
    # засчитывается. Это и есть доказательство, что признак принадлежит ЗАПИСИ,
    # а не виду источника и не форме прибавки: две записи неотличимы во всех
    # полях, кроме этого одного (та же ловушка, что у стороны капа с
    # `Divine grace` против `Sacred defense`).
    test "расовая склонность Lucky — тот же +1, и она засчитывается", %{ruleset: ruleset} do
      goblin =
        Build.new(
          levels: List.duplicate(:fighter, 9),
          base_abilities: %{@flat | con: 12},
          race: :halfling
        )

      stats = Rules.compute(goblin, ruleset)

      assert Enum.map(own_terms(stats, :lucky), &{&1.save, &1.bonus}) ==
               [{:fort, 1}, {:ref, 1}, {:will, 1}]

      assert stats.fort == 8
      assert stats.saves_for_prereqs.fort == 8
    end

    # Исключённая запись ровно одна на оба ruleset'а — Сиала про это не
    # высказывалась ни словом, значит действует ваниль (CLAUDE.md §3). Тест
    # ловит и обратное: признак, поехавший на соседние записи, виден сразу.
    test "исключена ровно одна запись, и одна и та же на обоих ruleset'ах", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      assert SaveBonuses.not_counted_for_prerequisites(ruleset) == [:luck_of_heroes]
      assert SaveBonuses.not_counted_for_prerequisites(vanilla) == [:luck_of_heroes]
    end

    test "числа одинаковы на обоих ruleset'ах", %{ruleset: ruleset, vanilla: vanilla} do
      b = with_luck(List.duplicate(:fighter, 9))

      assert Rules.compute(b, ruleset).saves_for_prereqs ==
               Rules.compute(b, vanilla).saves_for_prereqs
    end

    # ⚠️ Признак снимается ИЗ ДАННЫХ, а не именем фита в ядре: сними его —
    # и число возвращается к голому. Тест держит эту границу с той стороны,
    # с какой её легко потерять при рефакторинге.
    test "снять признак в данных — и прибавка снова засчитывается", %{ruleset: ruleset} do
      counted =
        update_in(ruleset, [Access.key!(:save_bonuses), :applied], fn records ->
          for record <- records do
            if record.id == :luck_of_heroes, do: Map.put(record, :prereq, nil), else: record
          end
        end)

      b = with_luck(List.duplicate(:fighter, 9))

      assert Rules.compute(b, ruleset).saves_for_prereqs.fort == 7
      assert Rules.compute(b, counted).saves_for_prereqs.fort == 8
      assert SaveBonuses.not_counted_for_prerequisites(counted) == []
    end
  end
end
