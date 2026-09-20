defmodule BuildCalculator.GameLogEquipmentTest do
  @moduledoc """
  `=== Equipped: <name> ===` — разбор раздела экипировки шардовой команды
  `.билд+` (задачи 3.187, 3.206, 3.213).

  🔴 **Оракул — сам файл лога, прочитанный НЕЗАВИСИМЫМ зеркалом** (`mirror/1`
  ниже): регулярка вытаскивает из текста слоты, напечатанные имена и строки
  свойств, и разбор обязан дать ровно их. До 18.09.2026 оракулом был набранный
  руками набор структур (`test/support/equipped_fixtures.ex`, 1049 строк), и он
  ушёл вместе с первым поколением печати: зеркало над файлом дешевле, не
  устаревает при смене формата и проверяет ровно то, ради чего оракул нужен —
  что при переносе не потерялась и не переехала ни одна строка.

  ⚠️ Зеркало сверяет и то, чем обрезано имя: ПОМЕТКИ (`(Bracer)`,
  `[BaseItem:78]`, `[BaseAC:8]`, `[CRAFT]`) обязаны быть сняты с имени и
  прочитаны в свои ключи, а остатка между именем и пометками остаться
  не должно. Иначе «`[BaseAC:8]` приклеился к имени» зеленело бы.

  ## Одно живое поколение печати, и старые формы тоже читаются

  Фикстуры в `test/fixtures/game_logs_plus/` — **третьего** поколения (все
  четыре, слово Dan 18.09.2026: «старые версии можно не хранить, заменить их
  новыми»). Формы ДВУХ прежних поколений — `AC Bonus (0) N`, `AC Bonus
  (65535) N`, имя без пометок, кусок без `[SetID]`, раздел без шапки —
  проверяются **короткими фрагментами текста** здесь же: у игроков остались
  сохранённые логи, и импорт обязан открывать их так же.

  Байт-в-байт регрессия шестнадцати `.билд` фикстур (без раздела экипировки
  вовсе) живёт отдельно, `game_log_test.exs`: этот файл её не повторяет, только
  проверяет, что `equipment` у них пуст и что новый код не добавил ни одной
  строки в их `problems`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, GameLog}

  @ruleset Data.ruleset!("siala_41")
  @names ~w(hnyupius brunna moxie bor)

  defp fixture(name) do
    [File.cwd!(), "test/fixtures/game_logs_plus", name <> ".log"]
    |> Path.join()
    |> File.read!()
  end

  defp parse(name), do: GameLog.parse(fixture(name), @ruleset)

  # Независимое зеркало текста: слот, НАПЕЧАТАННОЕ имя (с пометками, как есть)
  # и строки свойств. Ничего не классифицирует и ничего не снимает — именно
  # поэтому им можно проверять разбор.
  defp mirror(name) do
    [_header, equipped] = String.split(fixture(name), "=== Equipped", parts: 2)

    equipped
    |> String.split("\n")
    |> Enum.reduce([], fn line, items ->
      cond do
        m = Regex.run(~r/^\[([A-ZА-Я]+)\] (.*)$/u, line) ->
          [_, slot, printed] = m
          [%{slot: slot, printed: String.trim(printed), raws: []} | items]

        m = Regex.run(~r/^  (\[\d+\] .*)$/u, line) ->
          [_, raw] = m
          [item | rest] = items
          [%{item | raws: item.raws ++ [raw]} | rest]

        true ->
          items
      end
    end)
    |> Enum.reverse()
  end

  # Что осталось от напечатанного имени после того, как разбор отрезал своё:
  # хвост обязан состоять ТОЛЬКО из пометок, которые разбор прочитал.
  @marks ~r/\s*(\[CRAFT\]|\[BaseItem:\d+\]|\[BaseAC:\d+\]|\([^()]+\))/u

  defp name_tail(printed, item) do
    printed |> String.replace_prefix(item.name, "") |> String.replace(@marks, "")
  end

  describe "разбор повторяет файл лога" do
    for name <- @names do
      test "#{name}.log: слоты, имена и все строки свойств на месте" do
        log = parse(unquote(name))
        want = mirror(unquote(name))

        assert length(log.equipment) == length(want)

        for {{got, expected}, index} <- log.equipment |> Enum.zip(want) |> Enum.with_index() do
          assert Atom.to_string(got.slot) == slot_id(expected.slot),
                 "предмет #{index}: слот разошёлся"

          assert String.starts_with?(expected.printed, got.name),
                 "предмет #{index}: имя #{inspect(got.name)} не начало " <>
                   "напечатанного #{inspect(expected.printed)}"

          assert name_tail(expected.printed, got) == "",
                 "предмет #{index} (#{got.name}): в хвосте имени остался текст, " <>
                   "который не пометка — #{inspect(name_tail(expected.printed, got))}"

          assert Enum.map(got.properties, & &1.raw) == expected.raws,
                 "предмет #{index} (#{inspect(got.slot)}): строки свойств разошлись"
        end

        # Ни один непонятый токен не ушёл в общий `problems` молча.
        assert log.problems == []
      end
    end

    # Счёт строк — `sed -n '/=== Equipped/,$p' | grep -c '^  \[[0-9]'`
    # по каждому файлу, 18.09.2026.
    for {name, lines} <- [{"hnyupius", 92}, {"brunna", 40}, {"moxie", 88}, {"bor", 58}] do
      test "#{name}.log: #{lines} строк свойств" do
        assert BuildCalculator.Rules.GearImport.property_count(parse(unquote(name)).equipment) ==
                 unquote(lines)
      end
    end
  end

  # Токен лога → id слота у нас: сверять надо с таблицей ruleset'а, а не
  # со `String.downcase` наугад (`RIGHTHAND` → `right_hand`).
  defp slot_id(token) do
    row = Enum.find(@ruleset.gear.item_slot_ac_types, &(&1.log == token))
    Atom.to_string(row.id)
  end

  # --------------------------------------------------------------- шапка --

  describe "шапка раздела" do
    # Числа — как напечатаны в самих логах (`grep "MINI SET PIECES\|CRAFT ITEMS"`),
    # и это ЧИСЛА СЕРВЕРА, а не наш счёт по предметам: у Бора четыре куска
    # по шапке и ни одной строки `Use Item (Mini Set)` в предметах.
    for {name, pieces, craft} <- [
          {"hnyupius", 7, 7},
          {"brunna", 0, 6},
          {"moxie", 0, 3},
          {"bor", 4, 4}
        ] do
      test "#{name}: MINI SET PIECES #{pieces}, CRAFT ITEMS #{craft}" do
        assert parse(unquote(name)).equipment_counts == %{
                 mini_set_pieces: unquote(pieces),
                 craft_items: unquote(craft)
               }
      end
    end

    # Сервер напечатает третий счётчик — игрок услышит, что мы его видели
    # и не прочли, а не «строка не по форме».
    test "неизвестный счётчик в шапке назван, а известные читаются" do
      text =
        String.replace(
          fixture("bor"),
          "CRAFT ITEMS: 4\n",
          "CRAFT ITEMS: 4\nARTIFACT SET PIECES: 2\n"
        )

      log = GameLog.parse(text, @ruleset)

      assert log.equipment_counts == %{mini_set_pieces: 4, craft_items: 4}
      assert {:unknown_equipment_count, "ARTIFACT SET PIECES"} in log.problems
      assert length(log.equipment) == 11
    end
  end

  # ----------------------------------------------------------- базовый тип --

  describe "базовый тип предмета" do
    # Строки `baseitems.2da` сверены руками с `priv/hak/2da/baseitems.2da`
    # (3 bastardsword, 5 warhammer, 13 greatsword, 36 gloves, 45 magicstaff,
    # 57 towershield, 78 bracer). 🔴 У строки 36 метка хака — `gloves`,
    # а сервер печатает `Gauntlet`: имя и метка РАСХОДЯТСЯ, и ключом остаётся
    # имя (задача 3.206 — «сверяется ИМЯ, а не строка baseitems.2da»).
    for {name, slot, item, type, row} <- [
          {"hnyupius", :right_hand, "Меч Драконов", "Bastard Sword", 3},
          {"hnyupius", :left_hand, "Башенный щит Черной Инквизиции", "Tower Shield", 57},
          {"hnyupius", :arms, "Нарукавник Ратника", "Bracer", 78},
          {"bor", :right_hand, "Ург Шак", "Warhammer", 5},
          {"bor", :left_hand, "Щит Приграничного Королевства", "Tower Shield", 57},
          {"bor", :arms, "Прочные Браслеты", "Bracer", 78},
          {"brunna", :right_hand, "Посох Волшебства", "Magic Staff", 45},
          {"brunna", :arms, "Перчатки", "Gauntlet", 36},
          {"moxie", :right_hand, "Меч Света Сагры", "Greatsword", 13},
          {"moxie", :arms, "Перчатки Мокси", "Gauntlet", 36}
        ] do
      test "#{name} #{slot}: «#{item}» — #{type} [BaseItem:#{row}]" do
        found = Enum.find(parse(unquote(name)).equipment, &(&1.slot == unquote(slot)))

        assert found.name == unquote(item)
        assert found.base_type == unquote(type)
        assert found.base_item == unquote(row)
      end
    end

    # Третье поколение печатает тип в трёх слотах из одиннадцати — и ни в одном
    # другом. Проверяется ОБА направления: где ключ есть и где его нет вовсе.
    test "тип печатается только в руках и в ARMS" do
      for name <- @names,
          item <- parse(name).equipment,
          item.slot not in [:right_hand, :left_hand, :arms] do
        refute Map.has_key?(item, :base_type), "#{name}: #{item.name}"
        refute Map.has_key?(item, :base_item), "#{name}: #{item.name}"
      end
    end

    # Скобки в самом имени предмета — не базовый тип: без `[BaseItem:n]`
    # рядом группа остаётся частью имени. Это и есть форма первого поколения.
    test "скобки без [BaseItem] остаются именем" do
      text =
        String.replace(
          fixture("bor"),
          "[HEAD] Шлем Капитана Форта Авендума",
          "[HEAD] Шлем (старый)"
        )

      head = Enum.find(GameLog.parse(text, @ruleset).equipment, &(&1.slot == :head))

      assert head.name == "Шлем (старый)"
      refute Map.has_key?(head, :base_type)
    end

    test "пометки читаются в любом порядке" do
      text =
        fixture("bor")
        |> String.replace(
          "[RIGHTHAND] Ург Шак (Warhammer) [BaseItem:5]",
          "[RIGHTHAND] Ург Шак (Warhammer) [CRAFT] [BaseItem:5]"
        )
        |> String.replace(
          "[CHEST] Доспехи Стражника Хаоса [BaseAC:7]",
          "[CHEST] Доспехи Стражника Хаоса [CRAFT] [BaseAC:7]"
        )

      log = GameLog.parse(text, @ruleset)
      main = Enum.find(log.equipment, &(&1.slot == :right_hand))
      chest = Enum.find(log.equipment, &(&1.slot == :chest))

      assert %{name: "Ург Шак", base_type: "Warhammer", base_item: 5, craft?: true} = main
      assert %{name: "Доспехи Стражника Хаоса", base_ac: 7, craft?: true} = chest
      assert log.problems == []
    end
  end

  # -------------------------------------------------- база доспеха (3.213) --

  describe "[BaseAC:n] у доспеха" do
    # Числа — как напечатаны в логах 18.09.2026. ⚠️ Ноль у робы и туники —
    # ЗНАЧАЩЕЕ значение, а не «сервер промолчал»: свод кладёт по нему строку
    # «нет / одежда», и AC-бонусы монаха остаются целы (Мокси 72 = 72).
    for {name, base} <- [{"hnyupius", 8}, {"bor", 7}, {"brunna", 0}, {"moxie", 0}] do
      test "#{name}: база #{base}, и из имени она убрана" do
        chest = Enum.find(parse(unquote(name)).equipment, &(&1.slot == :chest))

        assert chest.base_ac == unquote(base)
        refute String.contains?(chest.name, "BaseAC")
      end
    end

    test "база печатается только у CHEST — у остальных слотов ключа нет вовсе" do
      for name <- @names, item <- parse(name).equipment, item.slot != :chest do
        refute Map.has_key?(item, :base_ac), "#{name}: #{item.name}"
      end
    end

    # Форма прежних поколений: у `CHEST` базы нет вовсе, и ключа быть не должно
    # — «лог не сказал» и «сказал ноль» это разные ответы.
    test "лог без [BaseAC] ключа не заводит" do
      text = String.replace(fixture("bor"), " [BaseAC:7]", "")
      chest = Enum.find(GameLog.parse(text, @ruleset).equipment, &(&1.slot == :chest))

      assert chest.name == "Доспехи Стражника Хаоса"
      refute Map.has_key?(chest, :base_ac)
    end
  end

  # ---------------------------------------------------------------- крафт --

  describe "пометка [CRAFT]" do
    # Имена — как в логах; пометка снята с имени, а не оставлена в нём.
    for {name, marked} <- [
          {"hnyupius", []},
          {"brunna",
           [
             "Сапоги",
             "Перчатки",
             "Серебряное кольцо с изумрудом",
             "Серебряное кольцо с рубином",
             "Амулет",
             "Пояс"
           ]},
          {"moxie", ["Перчатки Мокси", "Кольцо Мокси", "Пояс Мокси"]},
          {"bor", []}
        ] do
      test "#{name}: помечено #{length(marked)}" do
        log = parse(unquote(name))

        assert for(%{craft?: true, name: item} <- log.equipment, do: item) == unquote(marked)
        refute Enum.any?(log.equipment, &String.contains?(&1.name, "[CRAFT]"))
      end
    end

    # Форма прежних поколений: пометки нет ни у одного предмета, и ключа
    # не должно быть — лог до пометки не утверждает «не крафт» ни про кого.
    test "лог без пометок ключа не заводит" do
      text = String.replace(fixture("brunna"), " [CRAFT]", "")

      for item <- GameLog.parse(text, @ruleset).equipment do
        refute Map.has_key?(item, :craft?), item.name
      end
    end
  end

  # ------------------------------------------------------------- мини-сеты --

  describe "номер набора у куска" do
    test "hnyupius: семь кусков, три набора, номера как в логе" do
      pieces =
        for item <- parse("hnyupius").equipment,
            %{kind: :mini_set} = property <- item.properties,
            do: {item.slot, property.param}

      assert pieces == [
               head: 22,
               boots: 73,
               arms: 73,
               left_hand: 22,
               cloak: 73,
               neck: 59,
               belt: 59
             ]
    end

    # `[SetID:22]` стоит ПОСЛЕ скобок параметра — читается отдельным ключом,
    # а не как «значение» свойства (у куска значения нет).
    test "номер не попадает в value" do
      for item <- parse("hnyupius").equipment, %{kind: :mini_set} = property <- item.properties do
        refute Map.has_key?(property, :value), inspect(property)
      end
    end

    # Форма первого поколения: кусок без номера набора.
    test "кусок без [SetID] читается без param" do
      text = String.replace(fixture("hnyupius"), ~r/ \[SetID:\d+\]/u, "")

      pieces =
        for item <- GameLog.parse(text, @ruleset).equipment,
            %{kind: :mini_set} = property <- item.properties,
            do: property

      assert length(pieces) == 7

      for property <- pieces do
        refute Map.has_key?(property, :param), inspect(property)
      end
    end
  end

  # ------------------------------------------------- формы прежних печатей --
  #
  # 🔴 РАДИ ЧЕГО ЭТОТ РАЗДЕЛ: сохранённые логи прежних поколений у игроков
  # остались, и импорт обязан открывать их так же. Фрагментами текста, а не
  # файлами — файлы заменены (слово Dan 18.09.2026).

  @minimal """
  [CHAT WINDOW TEXT] [Wed Aug 26 00:00:00] Command detected: .билд+
  ------------------------------------------------
      CHARACTER BUILD: Тест
      Current: 1 FTR
  ------------------------------------------------

  CURRENT ABILITIES: STR 16 DEX 12 CON 14 INT 10 WIS 10 CHA 8
  COMBAT STATS: AB 1 AC 10 Fort 2 Refl 1 Will 1
  SKILLS WITH RANKS:
    Discipline 4

  (WHITE) ABILITIES: STR 16 DEX 12 CON 14 INT 10 WIS 10 CHA 8
  RACE: Human

  ------------------------------------------------
  LEVEL 1: FIGHTER
    FEATS: Toughness
  ------------------------------------------------

  [CHAT WINDOW TEXT] [Wed Aug 26 00:00:00] Build sent to! Тест
  [CHAT WINDOW TEXT] [Wed Aug 26 00:00:00] === Equipped: Тест ===
  """

  describe "`AC Bonus` во всех трёх формах" do
    # 🔴 Третье поколение перестало печатать параметр (`AC Bonus 5`), и на
    # прежнем коде эта строка не совпадала ни с одним именем таблицы — уходила
    # в `not_ours` молча: свод по четырём логам давал 128 / 148 / 2 вместо
    # 142 / 134 / 2, а AC Хнюпиуса 38 вместо 58.
    for {label, line, value} <- [
          {"без параметра (третье поколение)", "AC Bonus 5", 5},
          {"с (0) (первое и второе)", "AC Bonus (0) 5", 5},
          {"с (65535) (первое и второе)", "AC Bonus (65535) 5", 5},
          {"с отрицательным числом", "AC Bonus -2", -2}
        ] do
      test "#{label}" do
        text = @minimal <> "[HEAD] Шлем\n  [1] #{unquote(line)}\n"
        log = GameLog.parse(text, @ruleset)

        assert [%{slot: :head, properties: [property]}] = log.equipment
        assert property.kind == :ac_bonus
        assert property.value == unquote(value)
        assert property.raw == "[1] #{unquote(line)}"
        assert log.problems == []
      end
    end

    # ⚠️ ОБОБЩАТЬ НЕЛЬЗЯ, и это под тестом: остальные свойства параметр
    # сохранили, и «имя без скобок» у них означало бы форму, которой сервер
    # не печатает. Строка `Attack Bonus 5` формой третьего поколения НЕ стала.
    for line <- ["Attack Bonus (0) 5", "Enhancement Bonus (0) 6", "Regeneration (65535) 8"] do
      test "параметр у «#{line}» сохранён — строка читается как раньше" do
        text = @minimal <> "[RIGHTHAND] Меч\n  [1] #{unquote(line)}\n"
        log = GameLog.parse(text, @ruleset)

        assert [%{properties: [property]}] = log.equipment
        assert property.kind in [:attack_bonus, :enhancement_bonus, :other]
        assert log.problems == []
      end
    end
  end

  describe "`Damage Resistance (<вид>) N` (задача 3.210)" do
    # 🔴 Стихия разрешается против ТОГО ЖЕ словаря, который называет стихии
    # секции «Резисты» (`ruleset.resistance_energy_types`), а не против второго
    # списка в разборе: имена в логе — те же английские, что несёт словарь,
    # и регистр снимает нормализация (`Positive Energy` = `Positive energy`).
    for {line, type, value} <- [
          {"Damage Resistance (Fire) 15", :fire, 15},
          {"Damage Resistance (Cold) 15", :cold, 15},
          {"Damage Resistance (Acid) 5", :acid, 5},
          {"Damage Resistance (Positive Energy) 20", :positive_energy, 20}
        ] do
      test "«#{line}» читается как #{type}" do
        text = @minimal <> "[NECK] Амулет\n  [1] #{unquote(line)}\n"
        log = GameLog.parse(text, @ruleset)

        assert [%{slot: :neck, properties: [property]}] = log.equipment
        assert property.kind == :damage_resistance
        assert property.param == unquote(type)
        assert property.value == unquote(value)
        assert log.problems == []
      end
    end

    # ⚠️ Имя вне словаря едет как `{:unresolved, text}` — ровно как
    # неразобранная характеристика или навык, — и решает его судьбу СВОД
    # (`Rules.GearImport`): физическое поглощение он назовёт решением
    # владельца, божественное — не нашей механикой. Здесь об этом знать нечего.
    for {line, text} <- [
          {"Damage Resistance (Bludgeoning) 10", "Bludgeoning"},
          {"Damage Resistance (Divine) 15", "Divine"},
          {"Damage Resistance (Nonsense) 1", "Nonsense"}
        ] do
      test "«#{line}» — имя не разрешено, но строка прочитана" do
        text = @minimal <> "[NECK] Амулет\n  [1] #{unquote(line)}\n"
        log = GameLog.parse(text, @ruleset)

        assert [%{properties: [property]}] = log.equipment
        assert property.kind == :damage_resistance
        assert property.param == {:unresolved, unquote(text)}
        assert log.problems == []
      end
    end

    # 🔴 `Damage Reduction` рядом — ДРУГАЯ механика (физическая, варварская),
    # и её вид не сдвинулся: `:other`. Ровно тот случай, где одна буква
    # в имени меняет получателя.
    test "«Damage Reduction (+7) 2» остаётся не нашей механикой" do
      text = @minimal <> "[NECK] Амулет\n  [1] Damage Reduction (+7) 2\n"
      log = GameLog.parse(text, @ruleset)

      assert [%{properties: [property]}] = log.equipment
      assert property.kind == :other
      assert property.param == :damage_reduction
    end
  end

  describe "раздел прежних поколений целиком" do
    test "без шапки: equipment_counts пуст — пустая мапа, а не нули" do
      text = @minimal <> "[HEAD] Шлем\n  [1] AC Bonus (0) 5\n"

      assert GameLog.parse(text, @ruleset).equipment_counts == %{}
    end

    test "имя без единой пометки: ни одного нового ключа" do
      text = @minimal <> "[CHEST] Нагрудник\n  [1] AC Bonus (0) 6\n"

      assert [item] = GameLog.parse(text, @ruleset).equipment
      assert item.name == "Нагрудник"

      for key <- [:base_type, :base_item, :base_ac, :craft?] do
        refute Map.has_key?(item, key), inspect(key)
      end
    end
  end

  # -------------------------------------------------- шестнадцать .билд --

  describe "шестнадцать старых .билд фикстур не задеты" do
    for name <- ~w(aley babuka boido brunna elith frah_hall froim hana hela
                    hnyupius hnyupius_alignment moxie nathan nicha timonall trina) do
      test "#{name}.log: equipment пуст, problems не выросли" do
        text =
          [File.cwd!(), "test/fixtures/game_logs", unquote(name) <> ".log"]
          |> Path.join()
          |> File.read!()

        log = GameLog.parse(text, @ruleset)

        assert log.equipment == []
        # Ни одна из новых форм проблем (`:unresolved_equipment_slot`,
        # `:equipment_property_before_slot`, `:unrecognized_equipment_line`)
        # не имеет права появиться на дампе без раздела экипировки вовсе.
        refute Enum.any?(
                 log.problems,
                 &match?(
                   {kind, _}
                   when kind in [
                          :unresolved_equipment_slot,
                          :equipment_property_before_slot,
                          :unrecognized_equipment_line
                        ],
                   &1
                 )
               )
      end
    end
  end

  # ------------------------------------------------------------ честность --

  describe "битый раздел не роняет разбор" do
    test "неизвестный слот назван, а не отброшен молча" do
      text = @minimal <> "[WAIST] Пояс без слота\n  [1] AC Bonus 3\n"
      log = GameLog.parse(text, @ruleset)

      assert log.equipment == []
      assert {:unresolved_equipment_slot, "WAIST"} in log.problems
    end

    test "свойство до первого слота названо, а не роняет разбор" do
      text = @minimal <> "  [1] AC Bonus 3\n[HEAD] Шлем\n  [1] AC Bonus 5\n"
      log = GameLog.parse(text, @ruleset)

      assert [%{slot: :head, name: "Шлем"}] = log.equipment
      assert {:equipment_property_before_slot, "[1] AC Bonus 3"} in log.problems
    end

    test "нераспознанная строка внутри раздела не теряется молча" do
      text = @minimal <> "[HEAD] Шлем\n  что-то совсем не по форме\n"
      log = GameLog.parse(text, @ruleset)

      assert [%{slot: :head, name: "Шлем", properties: []}] = log.equipment
      assert {:unrecognized_equipment_line, "что-то совсем не по форме"} in log.problems
    end

    test "лог без раздела вовсе даёт пустой equipment и не падает" do
      log = GameLog.parse(@minimal, @ruleset)

      assert log.equipment == []
      assert log.problems == []
    end
  end

  # ------------------------------------------------------- нашла сама себя --

  describe "фит с вещи против фита в слоте — один словарь" do
    # Не round-trip, а сторож: `equip_feat_property/3` обязан использовать
    # ТОТ ЖЕ словарь, что `resolve_feats/4` для `FEATS:` — если однажды кто-то
    # заведёт для вещей отдельный маленький словарь, этот тест это заметит,
    # взяв реальный ванильный фит, который есть в обоих.
    test "Cleave резолвится вещевым разбором так же, как в FEATS:" do
      text =
        String.replace(@minimal, "FEATS: Toughness", "FEATS: Toughness, Power Attack, Cleave") <>
          "[ARMS] Нарукавники\n  [1] Bonus Feat (Cleave)\n"

      log = GameLog.parse(text, @ruleset)

      ladder_cleave =
        log.levels
        |> hd()
        |> Map.fetch!(:feats)
        |> Enum.find(&(&1.id == :cleave))

      assert ladder_cleave.kind == :feat

      assert [%{slot: :arms, properties: [%{kind: :bonus_feat, param: :cleave}]}] = log.equipment
    end
  end
end
