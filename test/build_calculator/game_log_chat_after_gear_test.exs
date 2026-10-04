defmodule BuildCalculator.GameLogChatAfterGearTest do
  @moduledoc """
  Задача 4.40, пункт 5: чат, вставленный ПОСЛЕ лога `.билд+`, — не экипировка.

  Раздел `=== Equipped: <имя> ===` — одно сообщение клиентского лога: строка
  метки с префиксом `[CHAT WINDOW TEXT]` и строки продолжения без него (слоты,
  свойства). До 4.40 `GameLog.scan_line/2`, увидев метку, читал экипировкой всё
  до конца вставки, и реплики чата после неё приходили замечаниями «экипировка:
  строка не по форме» — по одному на реплику. Чат ВОКРУГ обычного `.билд` окно
  отбрасывало всегда (строки с префиксом клиента — `@boilerplate`); теперь
  строка с префиксом закрывает и раздел экипировки — это общий случай, а не одна
  фраза `Build sent to!`: реплика, эхо следующей команды, второй лог.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, GameLog}
  alias BuildCalculatorWeb.Builder.GameLogImport

  @plus Path.expand("../fixtures/game_logs_plus/hnyupius.log", __DIR__)

  # Реплики в форме клиентского лога — те же, что у варианта «чат вокруг» стенда
  # `tools/game_log/equivalence.exs`, плюс эхо второй команды.
  @chat "[CHAT WINDOW TEXT] [Fri Sep 18 00:18:30] [Talk] Хнюпиус: вот он (40 уровней)\n" <>
          "[CHAT WINDOW TEXT] [Fri Sep 18 00:18:41] [Tell] Мокси: ок, смотрю\n" <>
          "[CHAT WINDOW TEXT] [Fri Sep 18 00:18:52] Build sent to! Хнюпиус\n"

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), plus: File.read!(@plus)}
  end

  defp gear_lines(issues),
    do: for({:unrecognized_equipment_line, _} = issue <- issues, do: issue)

  test "реплики после раздела экипировки не читаются экипировкой", %{ruleset: rs, plus: plus} do
    alone = GameLog.parse(plus, rs)
    with_chat = GameLog.parse(plus <> @chat, rs)

    # Положительный контроль: раздел прочитан, предметов одиннадцать.
    assert length(alone.equipment) == 11

    assert gear_lines(with_chat.problems) == []
    assert with_chat.equipment == alone.equipment
    assert with_chat.equipment_counts == alone.equipment_counts
    assert with_chat.problems == alone.problems
  end

  test "окно: замечаний столько же, сколько без чата, сумма экипировки та же", %{
    ruleset: rs,
    plus: plus
  } do
    alone = GameLogImport.parse(plus, rs)
    with_chat = GameLogImport.parse(plus <> @chat, rs)

    assert with_chat.issues == alone.issues
    assert with_chat.build.gear == alone.build.gear
    assert with_chat.gear_report == alone.gear_report
  end

  # Строка продолжения после реплики — уже не экипировка: её читают как любую
  # строку вне раздела, и она называется своим замечанием, а не пропадает.
  test "строка без префикса после реплики — «не распознана», не свойство предмета", %{
    ruleset: rs,
    plus: plus
  } do
    parsed = GameLog.parse(plus <> @chat <> "  [9] Ability Bonus (Strength) 12\n", rs)

    assert parsed.equipment == GameLog.parse(plus, rs).equipment
    assert {:unrecognized_line, "  [9] Ability Bonus (Strength) 12"} in parsed.problems
    assert gear_lines(parsed.problems) == []
  end

  # Строка, которая в разделе стоит без префикса, по-прежнему свойство: правка
  # закрывает раздел только строкой клиентского лога.
  test "свойство в конце раздела без префикса — по-прежнему свойство", %{ruleset: rs, plus: plus} do
    parsed = GameLog.parse(plus <> "  [5] Ability Bonus (Strength) 2\n", rs)
    belt = List.last(parsed.equipment)

    assert belt.slot == :belt
    assert Enum.any?(belt.properties, &(&1.raw == "[5] Ability Bonus (Strength) 2"))
  end

  # Строка с префиксом, которая за ним похожа на строку раздела, — не чат: так
  # выглядела бы печать сервера, который стал слать каждый предмет отдельным
  # сообщением. Молча её выбросить значило бы потерять экипировку без слова
  # (правка чужой печати ломает разбор молча — задача 3.213); она остаётся
  # в разделе и называется, как до 4.40.
  test "строка раздела с префиксом клиента не выбрасывается молча", %{ruleset: rs, plus: plus} do
    slot = "[CHAT WINDOW TEXT] [Fri Sep 18 00:18:03] [HEAD] Шлем Сержанта"
    property = "[CHAT WINDOW TEXT] [Fri Sep 18 00:18:03]   [1] AC Bonus 5"
    count = "[CHAT WINDOW TEXT] MINI SET PIECES: 7"

    parsed = GameLog.parse(plus <> Enum.join([slot, property, count], "\n") <> "\n", rs)

    assert gear_lines(parsed.problems) == [
             {:unrecognized_equipment_line, slot},
             {:unrecognized_equipment_line, String.trim(property)},
             {:unrecognized_equipment_line, count}
           ]
  end

  # Два лога `.билд+` подряд: второй — не 172 строки «не по форме» (заход 1),
  # а лог. С захода 3 (пункт 21) он не читается вовсе — одна вставка, один
  # персонаж — и называется одним замечанием (`game_log_one_log_test.exs`).
  test "второй лог после раздела экипировки — лог, а не экипировка", %{ruleset: rs, plus: plus} do
    twice = GameLog.parse(plus <> "\n" <> plus, rs)

    assert gear_lines(twice.problems) == []
    assert twice.problems == [{:another_log_not_read, "Хнюпиус", true}]
  end
end
