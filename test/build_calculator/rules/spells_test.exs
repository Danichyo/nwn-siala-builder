defmodule BuildCalculator.Rules.SpellsTest do
  @moduledoc """
  `Spells.per_day/2`, and the two things that bend a class's own row: the
  Wizard's one-time choice of a school (AGENT_QUEUE.md §3.10) and the bonus
  slots a high casting ability grants every caster (task 3.70).

  The real `siala_41` ruleset is used throughout rather than a hand-built
  fixture, the same choice `PrereqsTest` makes for its Pale Master cases:
  both bonuses are read off `ruleset.casting`, which only a real loader run
  populates, and the progression tables themselves are real game data worth
  pinning against (`priv/rules/vanilla/classes.json`).

  ⚠ The specialization block below deliberately holds INT at **11**, the
  lowest score Siala lets a caster start with. It used to be 14, which is a
  +2 modifier — and since 3.70 that is a bonus slot of its own, so every
  assertion there would have been measuring two rules at once and a failure
  could not have said which one moved. The two bonuses are shown stacking in
  one named test at the end instead.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Abilities, Build, Gear, Spells}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  # `base_abilities` replaces the whole map, and a partial one reads as zero
  # everywhere it is silent — every wizard below needs INT raised.
  defp abilities(overrides), do: Map.merge(Build.new().base_abilities, overrides)

  # A ladder climbed the way a player climbs it: one level at a time, each one
  # through `validate_level_up/3`. Building the same list straight into
  # `Build.new(levels: …)` skips validation entirely (CLAUDE.md §3), and an
  # impossible ladder would then be measured as though it were legal.
  defp climb(%Build{} = build, ruleset, class, count) do
    Enum.reduce(1..count//1, build, fn _, %Build{} = acc ->
      assert :ok = Rules.validate_level_up(acc, class, ruleset)
      Build.add_level(acc, class)
    end)
  end

  defp caster(ruleset, class, levels, abilities, opts \\ []) do
    ruleset.version
    |> fresh(Keyword.get(opts, :alignment, :true_neutral), abilities(abilities))
    |> climb(ruleset, class, levels)
  end

  defp fresh(version, alignment, abilities) do
    %Build{} =
      Build.new(
        ruleset_version: version,
        race: :human,
        alignment: alignment,
        base_abilities: abilities
      )
  end

  describe "school specialization — the +1 slot (task 3.10)" do
    # ⚠️ Обязательный положительный контроль: без него тест «+1» ниже мог бы
    # зеленеть и у реализации, которая раздаёт бонус любому волшебнику молча,
    # специализировался он или нет.
    test "a wizard who stays general gets the baseline row, no bonus", %{ruleset: ruleset} do
      wizard = Build.new(levels: [:wizard], base_abilities: abilities(%{int: 11}))

      assert [%{slots: slots, specialized_school: nil}] = Spells.per_day(wizard, ruleset)

      # Строка 1-го уровня волшебника в vanilla/classes.json: {"0": 3, "1": 1}.
      assert slots == %{0 => 3, 1 => 1}
    end

    test "a specialized wizard gets +1 at every circle the row already has", %{ruleset: ruleset} do
      wizard =
        Build.new(
          levels: [:wizard],
          base_abilities: abilities(%{int: 11}),
          class_choices: %{wizard: [:evocation]}
        )

      assert [%{slots: slots, specialized_school: :evocation}] = Spells.per_day(wizard, ruleset)
      assert slots == %{0 => 3, 1 => 2}
    end

    # ⚠️ Решение, не забытый случай: ни одна из двух цитат не говорит явно,
    # входит ли круг 0 (заговоры) в «per spell level» — `min_circle: 1`
    # в `spellcasting.json` исключает его сознательно (см. файл). Порча,
    # которая применила бы бонус ко ВСЕМ кругам без разбора, дала бы здесь
    # `0 => 5`, а не `0 => 4`.
    test "circle 0 (cantrips) does not share in the bonus", %{ruleset: ruleset} do
      wizard =
        Build.new(
          levels: List.duplicate(:wizard, 3),
          base_abilities: abilities(%{int: 11}),
          class_choices: %{wizard: [:necromancy]}
        )

      assert [%{offered_slots: slots, specialized_school: :necromancy}] =
               Spells.per_day(wizard, ruleset)

      # Строка 3-го уровня: {"0": 4, "1": 2, "2": 1} → бонус только на 1 и 2.
      assert slots == %{0 => 4, 1 => 3, 2 => 2}
    end

    # ⚠️ `offered_slots`, а не `slots`, у теста выше — и это не обход упавшего
    # ожидания, а разделение двух вопросов (задача 3.125). Волшебник с
    # интеллектом 11 второй круг не кастует вовсе, так что в `slots` его нет;
    # но спрашивают здесь про БОНУС ЗА ШКОЛУ, то есть про строку, и порча
    # «бонус на все круги» обязана ловиться независимо от того, до какого
    # круга дотянулась характеристика этого билда.
    test "the floor is a separate question from the school bonus", %{ruleset: ruleset} do
      wizard =
        Build.new(
          levels: List.duplicate(:wizard, 3),
          base_abilities: abilities(%{int: 11}),
          class_choices: %{wizard: [:necromancy]}
        )

      assert [%{slots: slots, unmet_circles: unmet}] = Spells.per_day(wizard, ruleset)
      assert slots == %{0 => 4, 1 => 3}
      assert unmet == %{2 => {:requires_ability, :int, 12}}
    end

    test "the bonus never invents a circle the row does not already list", %{ruleset: ruleset} do
      wizard =
        Build.new(
          levels: [:wizard],
          base_abilities: abilities(%{int: 11}),
          class_choices: %{wizard: [:evocation]}
        )

      assert [%{slots: slots}] = Spells.per_day(wizard, ruleset)
      refute Map.has_key?(slots, 2)
    end

    # «First clerical level» и его аналог у волшебника — это уровень КЛАССА,
    # а не персонажа (`Rules.ClassChoices`' moduledoc, задача 3.14). Здесь —
    # то же самое ядром: выбор, записанный в билде, применяется независимо
    # от того, на каком уровне персонажа волшебник вообще появился.
    test "the bonus applies no matter which character level the choice sits on", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          levels: List.duplicate(:fighter, 5) ++ [:wizard],
          base_abilities: abilities(%{int: 11, str: 14}),
          class_choices: %{wizard: [:illusion]}
        )

      assert [%{class: :wizard, specialized_school: :illusion, slots: slots}] =
               Spells.per_day(build, ruleset)

      assert slots == %{0 => 3, 1 => 2}
    end

    # Ничего не хардкожено под «волшебник»: класс без записи в
    # `ruleset.casting.school_specialization` игнорирует `class_choices`
    # целиком, даже если он там почему-то есть (билд — просто данные,
    # `Rules.Spells` не обязан знать, что это бессмысленно для соркерера).
    test "a class_choices entry on a class with no specialization record is a no-op", %{
      ruleset: ruleset
    } do
      %Build{} = base = Build.new(levels: [:sorcerer], base_abilities: abilities(%{cha: 11}))
      with_bogus_choice = %Build{base | class_choices: %{sorcerer: [:fire]}}

      assert Spells.per_day(base, ruleset) == Spells.per_day(with_bogus_choice, ruleset)
    end

    # Композиция с продвижением слотов Бледного мастера (задача из
    # `prereqs_test.exs`, тот же приём): бонус ложится на СТРОКУ, которую
    # выбрало продвижение, а не на строку голого класса. Волшебник 10 /
    # Бледный мастер 19 читает строку 20-го уровня волшебника — та же строка,
    # что даёт Sorcerer 20 в соседнем тесте `PrereqsTest`.
    test "composes with Pale Master's slot lending — the bonus lands on the lent row", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          levels: List.duplicate(:wizard, 10) ++ List.duplicate(:pale_master, 19),
          base_abilities: abilities(%{int: 11}),
          class_choices: %{wizard: [:transmutation]}
        )

      assert [%{table_level: 20, specialized_school: :transmutation, offered_slots: slots}] =
               Spells.per_day(build, ruleset)

      # Строка 20-го уровня волшебника — все круги по 4 без бонуса.
      assert slots[0] == 4
      assert slots[9] == 5
    end

    # Бонус не создаёт способность кастовать более высокий круг — он делает
    # существующий слот больше, не открывает новый. `casters_for_circle/3`
    # и `Prereqs.casts_spell_level` держатся на `highest_circle/2`.
    test "the bonus does not raise the highest castable circle", %{ruleset: ruleset} do
      wizard =
        Build.new(
          levels: [:wizard],
          base_abilities: abilities(%{int: 11}),
          class_choices: %{wizard: [:evocation]}
        )

      assert Spells.highest_circle(wizard, ruleset) == 1
    end
  end

  describe "bonus slots for a high casting ability (task 3.70)" do
    # Таблица `Modifier and spell slots` со страницы-источника, столбец за
    # столбцом: `fandom:Ability modifier#Spellcasting`, revid 71035 (страница
    # `Bonus spells` — редирект на неё; в `priv/wiki_cache/` её нет, снята
    # через `api.php`, как `Point buy`).
    #
    # Проверяется НЕ формула, а перенос: числа ниже выписаны из таблицы
    # руками, а формулу источника загрузчик уже прогнал по всем 234 ячейкам
    # и уронил бы сборку при расхождении. Два независимых способа сойтись.
    @table [
      # {модификатор, %{круг => бонусных слотов}} — только ненулевые
      {0, %{}},
      {1, %{1 => 1}},
      {2, %{1 => 1, 2 => 1}},
      {4, %{1 => 1, 2 => 1, 3 => 1, 4 => 1}},
      {5, %{1 => 2, 2 => 1, 3 => 1, 4 => 1, 5 => 1}},
      {9, %{1 => 3, 2 => 2, 3 => 2, 4 => 2, 5 => 2, 6 => 1, 7 => 1, 8 => 1, 9 => 1}},
      {21, %{1 => 6, 2 => 5, 3 => 5, 4 => 5, 5 => 5, 6 => 4, 7 => 4, 8 => 4, 9 => 4}}
    ]

    test "the wiki table, row by row, against a row that lists every circle", %{ruleset: ruleset} do
      # Строка 20-го уровня волшебника несёт все круги 0..9, поэтому на ней
      # видно каждую колонку таблицы разом.
      row = Map.new(0..9, &{&1, 4})

      for {modifier, expected} <- @table do
        assert Spells.ability_bonus(ruleset, row, modifier) == expected,
               "модификатор #{modifier}"
      end
    end

    # ⚠️ Отрицательные модификаторы и ноль — это ОТВЕТ, а не пробел: источник
    # печатает там прочерк и прозу «cannot cast spells tied to this ability»,
    # и то и другое означает ноль бонусных слотов.
    test "a modifier of zero or below adds nothing at all", %{ruleset: ruleset} do
      row = Map.new(0..9, &{&1, 4})

      for modifier <- [-4, -1, 0] do
        assert Spells.ability_bonus(ruleset, row, modifier) == %{}
      end
    end

    # «There are never bonus spell slots for cantrips (level 0 spells)» —
    # прямой строкой источника, в отличие от той же границы у специализации
    # волшебника, которую пришлось решать и потом измерять.
    test "circle 0 never gets a bonus, however high the ability", %{ruleset: ruleset} do
      refute Map.has_key?(Spells.ability_bonus(ruleset, %{0 => 6, 1 => 6}, 21), 0)
    end

    # «the caster must have spell slots of that level by virtue of class level»
    # — бонус делает существующий слот больше и никогда не открывает круг,
    # которого в строке класса нет вовсе.
    test "a circle absent from the class row gets nothing", %{ruleset: ruleset} do
      bonus = Spells.ability_bonus(ruleset, %{1 => 3}, 21)

      assert Map.keys(bonus) == [1]
    end

    # 🔴 Половина правила, которую теряют первой: «For this purpose, having "0"
    # spell slots counts (but having "-" spell slots does not)». В машинном
    # слое это разные вещи — напечатанный ноль есть ключ строки, пустая ячейка
    # ключа не даёт, — и здесь проверяется, что ядро на них отвечает по-разному.
    test "a printed zero is a slot and an empty cell is not", %{ruleset: ruleset} do
      assert Spells.ability_bonus(ruleset, %{1 => 0}, 1) == %{1 => 1}
      assert Spells.ability_bonus(ruleset, %{}, 1) == %{}
    end

    # Живой случай той же половины правила, и он двигает игру: у паладина
    # строка 4-го уровня класса — `{"1": 0}` (`fandom:Paladin`, колонка
    # «1st level spells»), то есть с мудростью 12 он кастует на 4-м, а с
    # мудростью 10 только на 6-м.
    test "a Paladin with wisdom 12 casts three class levels earlier", %{ruleset: ruleset} do
      dull = paladin(ruleset, 4, 10)
      bright = paladin(ruleset, 4, 12)

      assert [%{offered_slots: %{1 => 0}, ability_bonus: %{}}] = Spells.per_day(dull, ruleset)
      assert [%{slots: %{1 => 1}, ability_bonus: %{1 => 1}}] = Spells.per_day(bright, ruleset)

      assert Spells.highest_circle(dull, ruleset) == 0
      assert Spells.highest_circle(bright, ruleset) == 1
    end

    # 🔴 ЛОВУШКА ЗАДАЧИ 3.125, и она стоит здесь, а не среди её собственных
    # тестов: потолок каста режет круги ПОСЛЕ бонуса за характеристику, и
    # паладин с мудростью 12 — единственный билд, на котором обратный порядок
    # виден числом. Срежь строку до бонуса — и `{1 => 0}` не проходит потолок
    # (11 > 10 + 1 ему хватает, но слот при этом нулевой), а после бонуса это
    # настоящий слот, ради которого мудрость и качали.
    test "the floor is applied after the ability bonus, not before", %{ruleset: ruleset} do
      assert [%{slots: %{1 => 1}, unmet_circles: %{}}] =
               Spells.per_day(paladin(ruleset, 4, 12), ruleset)

      # А с мудростью 10 круга нет вовсе: строка его называет, кастовать нечем.
      assert [%{slots: slots, offered_slots: %{1 => 0}, unmet_circles: unmet}] =
               Spells.per_day(paladin(ruleset, 4, 10), ruleset)

      assert slots == %{}
      assert unmet == %{1 => {:requires_ability, :wis, 11}}
    end

    # Тот же паладин на 8-м: круг 2 напечатан нулём, значит мудрость 14
    # (модификатор +2) открывает и его, а мудрость 12 — ещё нет.
    test "a Paladin 8 opens circle 2 on wisdom 14 and not on wisdom 12", %{ruleset: ruleset} do
      assert [%{slots: %{1 => 2, 2 => 0}}] = Spells.per_day(paladin(ruleset, 8, 12), ruleset)
      assert [%{slots: %{1 => 2, 2 => 1}}] = Spells.per_day(paladin(ruleset, 8, 14), ruleset)
    end

    # Полукастер до своей первой строки — не «ноль бонусов», а вообще не
    # кастер: строк ниже 4-го уровня класса у таблицы нет, и запись про него
    # не появляется совсем.
    test "a Paladin below class level 4 has no row and therefore no entry", %{ruleset: ruleset} do
      assert Spells.per_day(paladin(ruleset, 3, 18), ruleset) == []
    end

    # Спонтанный кастер: колдун 41 читает строку 20-го уровня (стена из
    # моддока), и бонус ложится на неё.
    test "a Sorcerer 41 with charisma 30 gains seventeen slots a day", %{ruleset: ruleset} do
      rich = caster(ruleset, :sorcerer, 41, %{cha: 30})
      poor = caster(ruleset, :sorcerer, 41, %{cha: 10})

      assert [%{ability: :cha, ability_modifier: 10, offered_slots: rich_slots} = entry] =
               Spells.per_day(rich, ruleset)

      assert [%{ability_modifier: 0, ability_bonus: %{}, offered_slots: poor_slots}] =
               Spells.per_day(poor, ruleset)

      assert total(poor_slots) == 54
      assert total(rich_slots) == 71
      assert total(rich_slots) - total(poor_slots) == Enum.sum(Map.values(entry.ability_bonus))

      # ⚠️ Строка, а не то, что у персонажа на руках (задача 3.125): 71 слот
      # колдун с харизмой 30 и правда имеет — потолок каста ему не мешает
      # нигде, — а вот у бедного из этих 54 остаются шесть заговоров: харизма
      # 10 не даёт даже первого круга. Разные вопросы, разные ключи.
      assert [%{slots: ^rich_slots}] = Spells.per_day(rich, ruleset)
      assert [%{slots: %{0 => 6} = kept}] = Spells.per_day(poor, ruleset)
      assert map_size(kept) == 1
    end

    # Готовящий кастер, другая таблица — то же правило.
    test "a Cleric 20 with wisdom 24 gains one or two at every circle", %{ruleset: ruleset} do
      cleric = caster(ruleset, :cleric, 20, %{wis: 24})

      assert [%{ability: :wis, ability_modifier: 7, ability_bonus: bonus}] =
               Spells.per_day(cleric, ruleset)

      assert bonus == %{1 => 2, 2 => 2, 3 => 2, 4 => 1, 5 => 1, 6 => 1, 7 => 1}
    end

    test "a non-caster gains nothing to gain it on", %{ruleset: ruleset} do
      fighter = caster(ruleset, :fighter, 10, %{str: 14, wis: 18, cha: 18})

      assert Spells.per_day(fighter, ruleset) == []
    end

    # 🔴 Модификатор берётся от ИТОГОВОЙ характеристики, вещи включены:
    # «bonus spells are based on modified charisma» — та же фраза, что ставит
    # требование каста на БАЗОВОЕ значение. Требования фитов (S1/S2) вещи не
    # засчитывают, и это другое правило: контроль на него — ниже.
    test "gear counts: the modifier is the modified one", %{ruleset: ruleset} do
      %Build{} = naked = caster(ruleset, :sorcerer, 20, %{cha: 18})

      geared = %Build{naked | gear: Gear.new(abilities: %{cha: 12})}

      assert [%{ability_modifier: 4}] = Spells.per_day(naked, ruleset)
      assert [%{ability_modifier: 10}] = Spells.per_day(geared, ruleset)

      # И «голое» значение при этом не сдвинулось — вещи прибавляют к итогу,
      # а не к базе (`Abilities.scores/2` против `modifiers_at/3`).
      assert Abilities.scores(geared, ruleset).cha == 18

      # 🔴 Та же одна фраза источника разводит два ответа, и здесь видно оба
      # сразу (задача 3.125): «a base charisma score of 10 + the spell's level
      # is required to cast a spell, **bonus spells are based on modified
      # charisma**». Плащ на +12 даёт кучу слотов и НЕ открывает 9-й круг —
      # для него нужна базовая харизма 19, а её ни один предмет не поднимает.
      assert [%{unmet_circles: %{9 => {:requires_ability, :cha, 19}}}] =
               Spells.per_day(geared, ruleset)

      refute Map.has_key?(hd(Spells.per_day(geared, ruleset)).slots, 9)
      assert Map.has_key?(hd(Spells.per_day(geared, ruleset)).offered_slots, 9)
    end

    # Два бонуса на одной строке независимы и просто складываются: школа даёт
    # +1 на круг, характеристика — своё число. Оба читают ИСХОДНУЮ строку
    # класса, поэтому порядок сложения ничего не решает.
    test "the school bonus and the ability bonus stack", %{ruleset: ruleset} do
      %Build{} = plain = caster(ruleset, :wizard, 3, %{int: 11})
      specialist = %Build{plain | class_choices: %{wizard: [:evocation]}}
      %Build{} = clever = caster(ruleset, :wizard, 3, %{int: 14})

      clever_specialist = %Build{clever | class_choices: %{wizard: [:evocation]}}

      # Строка 3-го уровня волшебника: {"0": 4, "1": 2, "2": 1}.
      #
      # ⚠️ `offered_slots` у первых двух: интеллект 11 второго круга не
      # кастует вовсе (задача 3.125), а вопрос теста — про сложение двух
      # бонусов, то есть про строку. У двух умных билдов интеллекта хватает
      # на оба круга, и там `slots` совпадает со строкой — это и проверено
      # строкой ниже, чтобы «взял другой ключ» не превратилось в «не проверил».
      assert [%{offered_slots: %{0 => 4, 1 => 2, 2 => 1}}] = Spells.per_day(plain, ruleset)
      assert [%{offered_slots: %{0 => 4, 1 => 3, 2 => 2}}] = Spells.per_day(specialist, ruleset)
      assert [%{slots: %{0 => 4, 1 => 3, 2 => 2}}] = Spells.per_day(clever, ruleset)
      assert [%{slots: %{0 => 4, 1 => 4, 2 => 3}}] = Spells.per_day(clever_specialist, ruleset)

      assert [%{slots: %{0 => 4, 1 => 2}, unmet_circles: %{2 => {:requires_ability, :int, 12}}}] =
               Spells.per_day(plain, ruleset)
    end

    # Композиция с продвижением Бледного мастера: бонус ложится на строку,
    # которую билд в итоге читает, а не на строку голого класса.
    test "the bonus lands on the row Pale Master lent, not the class's own", %{ruleset: ruleset} do
      %Build{} = alone = caster(ruleset, :wizard, 10, %{int: 30}, alignment: :neutral_evil)
      lent = climb(alone, ruleset, :pale_master, 19)

      # Голый волшебник 10 читает строку с кругами 0..5, продвинутый — строку
      # 20-го уровня со всеми девятью. Модификатор один и тот же, а бонус
      # ложится на разное число кругов: он свойство СТРОКИ, а не билда.
      assert [%{table_level: 10, ability_modifier: 10, ability_bonus: bare}] =
               Spells.per_day(alone, ruleset)

      assert [%{class: :wizard, table_level: 20, ability_modifier: 10, ability_bonus: bonus}] =
               Spells.per_day(lent, ruleset)

      assert bare |> Map.keys() |> Enum.sort() == Enum.to_list(1..5)
      assert bonus |> Map.keys() |> Enum.sort() == Enum.to_list(1..9)
    end

    # ⚠️ Требования ФИТОВ вещи не выполняют (кейсы S1/S2), и эта правка их не
    # трогает: бонусные слоты и требование по характеристике — разные вопросы,
    # и вещь отвечает на них по-разному. Контроль ровно на это.
    test "gear moves the slots and still does not open a feat", %{ruleset: ruleset} do
      %Build{} = naked = caster(ruleset, :sorcerer, 1, %{cha: 11, dex: 12})
      geared = %Build{naked | gear: Gear.new(abilities: %{cha: 12, dex: 2})}

      # Ловкость 12 базой + 2 с вещей: `Dodge` требует 13 и остаётся закрытым.
      assert {:error, reasons} = Rules.validate_feat(geared, :dodge, ruleset)
      assert {:requires_ability, :dex, 13} in List.flatten(reasons)

      # А слоты за харизму при этом выросли — то же самое снаряжение.
      assert [%{ability_bonus: %{}}] = Spells.per_day(naked, ruleset)
      assert [%{ability_bonus: %{1 => 2}}] = Spells.per_day(geared, ruleset)
    end

    # Если таблицы в данных нет вовсе — бонуса нет и `{:missing_data,
    # :bonus_spell_slots}` сказано вслух. Синтетический ruleset, а не правка
    # `priv/`: проверяется механизм, а не сегодняшний файл.
    test "a ruleset carrying no table adds nothing", %{ruleset: ruleset} do
      без_таблицы = put_in(ruleset.casting.bonus_slots, nil)

      assert Spells.ability_bonus(без_таблицы, %{1 => 3}, 21) == %{}
    end

    defp paladin(ruleset, levels, wisdom) do
      caster(ruleset, :paladin, levels, %{str: 14, wis: wisdom}, alignment: :lawful_good)
    end

    defp total(slots), do: Enum.sum(for {circle, count} <- slots, circle > 0, do: count)
  end

  describe "the casting floor — circles the ability does not reach (task 3.125)" do
    # 🔴 Замер Dan (`GAME_CHECKS.md` AE2, 27.08.2026): у волшебника 8 с
    # интеллектом 11 «2 круг так и не появился». Строка класса даёт ему три
    # слота второго круга, и до этой задачи панель их печатала.
    #
    # Правило прежнее и с прежней цитатой: «In order to prepare or cast a known
    # spell, the caster must have both a base casting ability score and a
    # modified casting ability score of at least 10 + spell level»
    # (`fandom:Ability score`, revid 71148). Ново здесь только то, что его
    # читает число, которое видит игрок.
    #
    # Таблица — шесть билдов из постановки задачи, круги по кругам.
    @floor [
      # {класс, уровень, характеристика, значение, оставшиеся круги}
      {:wizard, 8, :int, 11, [0, 1]},
      {:wizard, 8, :int, 12, [0, 1, 2]},
      {:paladin, 4, :wis, 10, []},
      {:paladin, 4, :wis, 12, [1]},
      {:bard, 9, :cha, 11, [0, 1]},
      {:sorcerer, 8, :cha, 11, [0, 1]},
      # Контроль: характеристики хватает на всё, и не пропадает ничего.
      {:wizard, 20, :int, 19, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]},
      {:sorcerer, 41, :cha, 30, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]},
      # 🔴 И контроль в другую сторону, живой: клирику 20 с мудростью 18
      # девятый круг НЕ положен — для него нужна 19. Число сдвинулось этой
      # задачей, и сдвинулось верно.
      {:cleric, 20, :wis, 18, [0, 1, 2, 3, 4, 5, 6, 7, 8]},
      {:cleric, 20, :wis, 19, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]}
    ]

    for {class, levels, ability, score, circles} <- @floor do
      test "#{class} #{levels} с #{ability} #{score} кастует круги #{inspect(circles)}", %{
        ruleset: ruleset
      } do
        build =
          caster(
            ruleset,
            unquote(class),
            unquote(levels),
            %{unquote(ability) => unquote(score), str: 14},
            alignment: alignment_for(unquote(class))
          )

        # ⚠️ `flat_map` по всем записям, а не `[entry]`: у паладина с мудростью
        # 10 запись ЕСТЬ (строка таблицы никуда не делась), а кастовать нечего,
        # и оба случая обязаны читаться одинаково — пустым списком кругов.
        circles =
          build
          |> Spells.per_day(ruleset)
          |> Enum.flat_map(&Map.keys(&1.slots))
          |> Enum.sort()

        assert circles == unquote(circles)
      end
    end

    # ⚠️ ЛОВУШКА, названная владельцем отдельно: резать надо ПОСЛЕ бонуса за
    # характеристику. У паладина 4 в строке напечатан `0`, и настоящим слотом
    # его делает мудрость 12 — режь до бонуса, и он потеряет ровно тот слот,
    # ради которого мудрость поднимал.
    test "паладин 4 с мудростью 12 свой единственный слот сохраняет", %{ruleset: ruleset} do
      assert [%{slots: %{1 => 1}, unmet_circles: %{}}] =
               Spells.per_day(paladin(ruleset, 4, 12), ruleset)
    end

    # 🔴 Требование ФИТА эта правка не двигает, и вот измеренная точка, на
    # которой это видно: бард 4 с харизмой 11 второго круга не кастует (его
    # нет в `slots`) и `Empower Spell` при этом получает — поблажка спонтанным
    # кастерам стоит на СТРОКЕ таблицы (задача 3.124), а строка на месте.
    test "бард 4 с харизмой 11 круг теряет, а фит спонтанного кастера — нет", %{
      ruleset: ruleset
    } do
      bard = caster(ruleset, :bard, 4, %{cha: 11, dex: 12}, alignment: :chaotic_good)

      assert [%{slots: slots, offered_slots: offered, unmet_circles: unmet}] =
               Spells.per_day(bard, ruleset)

      refute Map.has_key?(slots, 2)
      assert Map.has_key?(offered, 2)
      assert unmet == %{2 => {:requires_ability, :cha, 12}}

      assert Spells.casters_offered_circle(bard, ruleset, 2) == [:bard]
      assert Spells.spontaneous_casters_offered_circle(bard, ruleset, 2) == [:bard]
      assert :ok = Rules.validate_feat(bard, :empower_spell, ruleset)
    end

    # И зеркало той же границы у готовящего кастера: у него отказ остаётся
    # ИМЕННО про характеристику, а не превращается в «нет такого круга».
    # `{:requires_ability, …}` — та причина, с которой игрок может что-то
    # сделать, `{:requires_spell_level, …}` — нет.
    test "у волшебника 8 с интеллектом 11 отказ фита по-прежнему называет интеллект", %{
      ruleset: ruleset
    } do
      wizard = caster(ruleset, :wizard, 8, %{int: 11})

      assert {:error, reasons} = Rules.validate_feat(wizard, :empower_spell, ruleset)
      assert {:requires_ability, :int, 12} in List.flatten(reasons)
    end

    # Правила нет в данных — резать нечем, и круг остаётся видимым. Умолчание
    # направлено в сторону показа: спрятать по правилу, которого у нас нет,
    # игрок изнутри инструмента не обнаружит никак. Синтетический ruleset,
    # потому что на живых данных запись есть.
    test "ruleset без правила не режет ничего", %{ruleset: ruleset} do
      без_правила = put_in(ruleset.casting.ability_minimum, nil)
      wizard = caster(ruleset, :wizard, 8, %{int: 11})

      assert [%{slots: cut}] = Spells.per_day(wizard, ruleset)
      assert [%{slots: whole, unmet_circles: %{}}] = Spells.per_day(wizard, без_правила)

      assert Map.keys(cut) == [0, 1]
      assert whole |> Map.keys() |> Enum.sort() == [0, 1, 2, 3, 4]
    end

    # Класса, чью характеристику каста никто не назвал, потолок не касается —
    # сравнивать не с чем. Гэп про это ruleset уже несёт своим порядком
    # (`{:missing_data, {:casting_ability, class}}`), выдумывать второй ответ
    # здесь нельзя.
    test "класс без названной характеристики каста не режется", %{ruleset: ruleset} do
      без_характеристики = put_in(ruleset.classes.wizard.casting_ability, nil)
      wizard = caster(ruleset, :wizard, 8, %{int: 11})

      assert [%{slots: slots, unmet_circles: %{}}] = Spells.per_day(wizard, без_характеристики)
      assert slots |> Map.keys() |> Enum.sort() == [0, 1, 2, 3, 4]
    end

    # `unmet_circles/5` — тот же вопрос, заданный про КОНКРЕТНЫЙ уровень, и
    # это не украшение API: известное заклинание выбирается навсегда на своём
    # уровне, значит и решает его характеристика того уровня. Колдун,
    # поднявший харизму на 12-м, на 8-м второго круга ещё не кастовал.
    test "unmet_circles/5 отвечает про уровень, а не про конец билда", %{ruleset: ruleset} do
      early = caster(ruleset, :sorcerer, 8, %{cha: 11}, alignment: :chaotic_good)

      %Build{} = twelve = climb(early, ruleset, :sorcerer, 4)
      grown = %Build{twelve | ability_increases: %{12 => :cha}}

      assert Spells.unmet_circles(grown, ruleset, :sorcerer, [1, 2], 8) ==
               %{2 => {:requires_ability, :cha, 12}}

      assert Spells.unmet_circles(grown, ruleset, :sorcerer, [1, 2], 12) == %{}
    end

    # Список кругов приходит от вызывающего: спросили про пустой — ответ пуст,
    # и функция не додумывает диапазон, которого никто не называл.
    test "unmet_circles/5 не выдумывает круги за вызывающего", %{ruleset: ruleset} do
      wizard = caster(ruleset, :wizard, 8, %{int: 11})

      assert Spells.unmet_circles(wizard, ruleset, :wizard, [], 8) == %{}
      assert Spells.unmet_circles(wizard, ruleset, :fighter, [1, 2], 8) == %{}
    end

    defp alignment_for(:paladin), do: :lawful_good
    defp alignment_for(:bard), do: :chaotic_good
    defp alignment_for(:sorcerer), do: :chaotic_good
    defp alignment_for(:cleric), do: :true_neutral
    defp alignment_for(_class), do: :true_neutral
  end
end
