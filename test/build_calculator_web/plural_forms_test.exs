defmodule BuildCalculatorWeb.PluralFormsTest do
  @moduledoc """
  Задача 4.3: русское согласование числа, написанное руками в четырёх местах
  (`Labels.plural/4` и `plural_word/4`, `ranks_word/1` в `Summary`,
  `slots_word/1` в `TotalsPanel`, `pieces_word/1` в `GameLogImportPanel`),
  переехало в `ngettext` — английскому интерфейсу согласовывать русские слова
  было нечем.

  Обещание задачи — **русский вывод байт в байт прежний**. Здесь это
  проверяется не на трёх числах, а сплошь: прежние функции переписаны сюда
  дословно как эталон, и на каждом числе диапазона фраза `ngettext` под `ru`
  обязана совпасть с тем, что они печатали. Ловит и перепутанные формы
  (`msgstr[1]` на месте `msgstr[2]`), и исключение 11..14, и ноль.

  Под `en` — положительный контроль: формы английские, две.
  """
  use ExUnit.Case, async: true

  @backend BuildCalculatorWeb.Gettext
  @range 0..130

  setup do
    Gettext.put_locale(@backend, "ru")
    :ok
  end

  defp ng(msgid, plural, n, bindings \\ []) do
    Gettext.dngettext(@backend, "default", msgid, plural, n, bindings)
  end

  # ---- прежние функции, дословно (эталон) ---------------------------------

  # `Labels.plural_word/4` (задача 3.225).
  defp old_plural_word(n, one, few, many) do
    abs_n = abs(n)

    cond do
      rem(abs_n, 100) in 11..14 -> many
      rem(abs_n, 10) == 1 -> one
      rem(abs_n, 10) in 2..4 -> few
      true -> many
    end
  end

  defp old_plural(n, one, few, many), do: "#{n} #{old_plural_word(n, one, few, many)}"

  # `Summary.ranks_word/1`.
  defp old_ranks_word(n) do
    cond do
      rem(n, 100) in 11..14 -> "рангов"
      rem(n, 10) == 1 -> "ранг"
      rem(n, 10) in 2..4 -> "ранга"
      true -> "рангов"
    end
  end

  # `TotalsPanel.slots_word/1`.
  defp old_slots_word(count) do
    last_two = rem(abs(count), 100)
    last = rem(last_two, 10)

    cond do
      last_two in 11..14 -> "слотов"
      last == 1 -> "слот"
      last in 2..4 -> "слота"
      true -> "слотов"
    end
  end

  # `GameLogImportPanel.pieces_word/1`.
  defp old_pieces_word(n) when rem(n, 10) == 1 and rem(n, 100) != 11, do: "#{n} кусок"
  defp old_pieces_word(n) when rem(n, 10) in 2..4 and rem(n, 100) not in 12..14, do: "#{n} куска"
  defp old_pieces_word(n), do: "#{n} кусков"

  # ---- сверка ---------------------------------------------------------------

  test "подсказка кнопки «макс»: «Добавить N рангов за M очков»" do
    for room <- 1..60, cost <- [1, 2] do
      new =
        Gettext.dgettext(@backend, "default", "Add %{ranks} for %{points}",
          ranks: ng("%{count} rank", "%{count} ranks", room),
          points: ng("%{count} point", "%{count} points", room * cost)
        )

      old =
        "Добавить #{old_plural(room, "ранг", "ранга", "рангов")} " <>
          "за #{old_plural(room * cost, "очко", "очка", "очков")}"

      assert new == old
    end
  end

  test "секция навыков: «N очков не потрачено» и «очков свободно»" do
    for n <- @range, n > 0 do
      assert ng("%{count} point unspent", "%{count} points unspent", n) ==
               "#{old_plural(n, "очко", "очка", "очков")} не потрачено"
    end

    # Перерасход (`free < 0`) приезжает по ссылке — форма по модулю, как была.
    for n <- -40..130 do
      assert ng("point free", "points free", abs(n)) ==
               "#{old_plural_word(n, "очко", "очка", "очков")} свободно"
    end
  end

  test "разбор «против заклинаний»: «Spellcraft 25 (20 рангов)»" do
    for n <- @range, n > 0 do
      assert ng(
               "%{skill} %{total} (%{count} rank)",
               "%{skill} %{total} (%{count} ranks)",
               n,
               skill: "Spellcraft",
               total: n + 5
             ) == "Spellcraft #{n + 5} (#{n} #{old_ranks_word(n)})"

      assert ng("%{skill} (%{count} rank)", "%{skill} (%{count} ranks)", n, skill: "Spellcraft") ==
               "Spellcraft (#{n} #{old_ranks_word(n)})"
    end
  end

  test "слоты за характеристику: «CHA +10: +17 слотов»" do
    for n <- @range do
      assert ng(
               "%{ability} %{modifier}: +%{count} slot",
               "%{ability} %{modifier}: +%{count} slots",
               n,
               ability: "CHA",
               modifier: "+10"
             ) == "CHA +10: +#{n} #{old_slots_word(n)}"
    end
  end

  test "куски мини-сетов — число и три фразы, где оно стоит" do
    for n <- @range do
      assert ng("%{count} piece", "%{count} pieces", n) == old_pieces_word(n)

      assert ng(
               "mini-sets: the server counted %{count} piece, but the pieces print no set numbers — recorded as one set, the same number for the calculation",
               "mini-sets: the server counted %{count} pieces, but the pieces print no set numbers — recorded as one set, the same number for the calculation",
               n
             ) ==
               "мини-сеты: сервер насчитал #{old_pieces_word(n)}, а наборы у кусков не напечатаны — " <>
                 "записано одним набором, для расчёта это то же число"

      assert ng(
               "mini-sets: the server counted %{count} piece, but the set numbers add up to %{groups} — recorded as the server's number, as one set",
               "mini-sets: the server counted %{count} pieces, but the set numbers add up to %{groups} — recorded as the server's number, as one set",
               n,
               groups: "3 + 2 + 2"
             ) ==
               "мини-сеты: сервер насчитал #{old_pieces_word(n)}, а по номерам наборов выходит " <>
                 "3 + 2 + 2 — записано числом сервера, одним набором"

      # Задача 4.18: после «при» — предложный падеж («при 1 куске», «при 2 кусках»),
      # прежние формы были родительным («при 1 кусок», «при 2 куска»).
      assert ng(
               "crafted items: the header says %{craft} with %{count} mini-set piece — the difference is negative, recorded as zero",
               "crafted items: the header says %{craft} with %{count} mini-set pieces — the difference is negative, recorded as zero",
               n,
               craft: 3
             ) ==
               "крафтовые вещи: шапка называет 3 при " <>
                 old_plural(n, "куске", "кусках", "кусках") <>
                 " мини-сетов — разность отрицательна, записан ноль"
    end
  end

  # Задача 4.4: пометка о дырах в данных и замечание импорта о лимите классов
  # стали `ngettext`. ⚠️ Прежние литералы печатали ОДНУ форму на все числа
  # («#{n} пробелов», «#{n} классов») — эталон здесь поэтому не прежняя
  # функция, а правильное согласование прежним же правилом `old_plural/4`:
  # на числах формы «много» (0, 5–20, 25–30 …) оно совпадает с прежним
  # литералом байт в байт, на остальных — это и есть починка.
  test "пометка о дырах в данных: «N пробелов», и прежний текст там, где форма была верна" do
    for n <- @range do
      banner =
        ng(
          "We can't calculate part of the rules yet — %{count} missing piece of data. The numbers are not final.",
          "We can't calculate part of the rules yet — %{count} missing pieces of data. The numbers are not final.",
          n
        )

      assert banner ==
               "Часть правил Сиалы ещё не в расчёте — " <>
                 old_plural(n, "пробел", "пробела", "пробелов") <>
                 " в данных. Числа не окончательные."

      if old_plural_word(n, "one", "few", "many") == "many" do
        assert banner ==
                 "Часть правил Сиалы ещё не в расчёте — #{n} пробелов в данных. Числа не окончательные."
      end

      assert ng(
               "We can't calculate part of the rules yet — %{count} missing piece of data.",
               "We can't calculate part of the rules yet — %{count} missing pieces of data.",
               n
             ) ==
               "Часть правил Сиалы ещё не в расчёте — " <>
                 old_plural(n, "пробел", "пробела", "пробелов") <> " в данных."
    end
  end

  test "импорт: «в билде N классов при лимите M»" do
    for n <- @range do
      text =
        ng(
          "the build has %{count} class, the limit is %{limit} — the rules do not allow such a build",
          "the build has %{count} classes, the limit is %{limit} — the rules do not allow such a build",
          n,
          limit: 4
        )

      assert text ==
               "в билде #{old_plural(n, "класс", "класса", "классов")} при лимите 4 — " <>
                 "на Сиале такой билд не собрать"
    end
  end

  # Положительный контроль: под `en` те же сообщения английские, в две формы.
  test "под en — английский msgid, единственное и множественное" do
    Gettext.put_locale(@backend, "en")

    assert ng("%{count} rank", "%{count} ranks", 1) == "1 rank"
    assert ng("%{count} rank", "%{count} ranks", 21) == "21 ranks"
    assert ng("point free", "points free", 1) == "point free"
    assert ng("point free", "points free", 0) == "points free"
    assert ng("%{count} piece", "%{count} pieces", 2) == "2 pieces"

    # Задача 4.4: ваниль с одной дырой в данных — единственное число, а не
    # «1 пробелов»; с 4.18 без слова «gap» (§7 VANILLA.md).
    assert ng(
             "We can't calculate part of the rules yet — %{count} missing piece of data.",
             "We can't calculate part of the rules yet — %{count} missing pieces of data.",
             1
           ) == "We can't calculate part of the rules yet — 1 missing piece of data."
  end

  # Задача 4.18: формы, которые до неё были одним прежним литералом на все
  # числа («3 очков», «сейчас 2 вещей», «на 1 уровнях»…) — починены правкой
  # `msgstr`. Эталон — правильное согласование `old_plural/4`; на числах формы
  # «много» он совпадает с прежним литералом, на остальных — это и есть починка.
  test "4.18: согласование, починенное правкой msgstr" do
    for n <- @range do
      assert ng("point left of %{budget}", "points left of %{budget}", n, budget: 30) ==
               old_plural_word(n, "очко", "очка", "очков") <> " осталось из 30"

      assert ng("now %{count} item", "now %{count} items", n) ==
               "сейчас " <> old_plural(n, "вещь", "вещи", "вещей")

      assert ng(
               "thing we can't calculate in this build",
               "things we can't calculate in this build",
               n
             ) == old_plural_word(n, "пробел", "пробела", "пробелов") <> " в этом билде"

      assert ng(
               "boost the weapon type and racial bonuses: pieces count from sets of at least %{count} piece",
               "boost the weapon type and racial bonuses: pieces count from sets of at least %{count} pieces",
               n
             ) ==
               "усиливают бонусы за тип оружия и расу: считаются куски наборов, собранных от " <>
                 old_plural(n, "штуки", "штук", "штук")

      assert ng("HP · with %{count} crafted item", "HP · with %{count} crafted items", n) ==
               "HP · с " <> old_plural(n, "крафтовой", "крафтовыми", "крафтовыми")

      assert ng(
               "skill ranks at %{count} level past the leveling guide we read are dropped",
               "skill ranks at %{count} levels past the leveling guide we read are dropped",
               n
             ) ==
               "ранги навыков на " <>
                 old_plural(n, "уровне", "уровнях", "уровнях") <>
                 " выше прочитанной лестницы отброшены"

      assert ng(
               "the text is cut at %{count} byte — the rest was not read",
               "the text is cut at %{count} bytes — the rest was not read",
               n
             ) ==
               "текст обрезан на " <>
                 old_plural(n, "байте", "байтах", "байтах") <> " — дальше не читали"

      assert ng(
               "the starting abilities are not restored: it came to %{count} point instead of %{budget} — no such build exists in the game (all %{budget} are always spent), so something is missing from our data on this build's feats or classes, not wrong with the character — enter the point buy by hand",
               "the starting abilities are not restored: it came to %{count} points instead of %{budget} — no such build exists in the game (all %{budget} are always spent), so something is missing from our data on this build's feats or classes, not wrong with the character — enter the point buy by hand",
               n,
               budget: 30
             ) ==
               "стартовые характеристики не восстановлены: получилось " <>
                 old_plural(n, "очко", "очка", "очков") <>
                 " вместо 30 — такого билда в игре не бывает (все 30 всегда потрачены), значит " <>
                 "это пробел в наших данных о фитах или классах этого билда, а не что-то не так " <>
                 "с персонажем — впиши поинт-бай вручную"
    end
  end

  # Задача 4.18: цена ранга — из ядра (`Skills.rank_cost/4`), а не литерал «1»
  # и «2» в тексте; на ценах 1 и 2 русский прежний байт в байт.
  test "4.18: цена ранга в подписях — прежний русский на ценах ядра" do
    assert ng(
             "%{skill}: class skill, %{count} point per rank",
             "%{skill}: class skill, %{count} points per rank",
             1,
             skill: "Hide"
           ) == "Hide: классовый, 1 очко за ранг"

    assert ng(
             "%{skill}: cross-class, %{count} point per rank",
             "%{skill}: cross-class, %{count} points per rank",
             2,
             skill: "Hide"
           ) == "Hide: кросс-классовый, 2 очка за ранг"

    assert ng("Class skill: %{count} point per rank", "Class skill: %{count} points per rank", 1) ==
             "Классовый: 1 очко за ранг"

    assert ng("Cross-class: %{count} point per rank", "Cross-class: %{count} points per rank", 2) ==
             "Кросс-классовый: 2 очка за ранг"

    assert Gettext.dgettext(@backend, "default", "class · %{cost}", cost: 1) == "класс · 1"
    assert Gettext.dgettext(@backend, "default", "cross · %{cost}", cost: 2) == "кросс · 2"
  end
end
