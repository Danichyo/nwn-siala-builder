defmodule BuildCalculator.GameLogOneLogTest do
  @moduledoc """
  Задача 4.40, заход 3, пункт 21: одна вставка — один персонаж.

  Два лога в одной вставке читались один поверх другого: шапка второго — молча
  поверх шапки первого (имя, раса, листы характеристик), лестница второго — после
  лестницы первого (сорок «уровень повторяется», а на ruleset'е с капом 41 его
  `LEVEL 1` становился 41-м уровнем билда), экипировка второго — к экипировке
  первого (22 предмета, сумма вдвое). Теперь читается ПЕРВЫЙ лог: строка
  `CHARACTER BUILD:`, когда что-то из лога уже прочитано, начинает следующий,
  и дальше не читается ничего — каждый следующий лог назван одним замечанием
  `{:another_log_not_read, имя, с_экипировкой?}`. Второй раздел `=== Equipped`
  в том же логе — так же: не читается, `{:equipment_section_not_read, имя}`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, GameLog}
  alias BuildCalculatorWeb.Builder.GameLogImport

  setup_all do
    read = fn dir, name ->
      "fixtures/#{dir}/#{name}.log" |> Path.expand(Path.join(__DIR__, "..")) |> File.read!()
    end

    %{
      ruleset: Data.ruleset!("siala_41"),
      plus: &read.("game_logs_plus", &1),
      plain: &read.("game_logs", &1)
    }
  end

  defp kinds(problems), do: Enum.map(problems, &elem(&1, 0))

  describe "два лога в одной вставке" do
    test "тот же персонаж дважды — читается один раз, второй назван", ctx do
      once = GameLog.parse(ctx.plus.("hnyupius"), ctx.ruleset)
      twice = GameLog.parse(ctx.plus.("hnyupius") <> "\n" <> ctx.plus.("hnyupius"), ctx.ruleset)

      # Положительный контроль: лог читается целиком.
      assert length(once.levels) == 40
      assert length(once.equipment) == 11

      assert twice.levels == once.levels
      assert twice.equipment == once.equipment
      assert twice.equipment_counts == once.equipment_counts
      assert twice.problems == [{:another_log_not_read, "Хнюпиус", true}]
      refute :level_duplicate in kinds(twice.problems)
    end

    test "два разных персонажа — читается первый, второй назван с экипировкой", ctx do
      bor = GameLog.parse(ctx.plus.("bor"), ctx.ruleset)
      both = GameLog.parse(ctx.plus.("bor") <> "\n" <> ctx.plus.("brunna"), ctx.ruleset)

      assert both.name == bor.name
      assert both.race == bor.race
      assert both.white_abilities == bor.white_abilities
      assert both.levels == bor.levels
      assert both.equipment == bor.equipment
      assert both.equipment_counts == bor.equipment_counts
      assert both.problems == [{:another_log_not_read, "Брунна *Пылечих*", true}]
    end

    test "обычный лог, потом .билд+ — экипировка второго не ложится на первый", ctx do
      both = GameLog.parse(ctx.plain.("trina") <> "\n" <> ctx.plus.("bor"), ctx.ruleset)

      assert both.name == "Trina Patson"
      assert both.equipment == []
      assert both.equipment_counts == %{}
      assert {:another_log_not_read, "Бор *Труповоз*", true} in both.problems
    end

    test ".билд+, потом обычный лог — второй назван без экипировки", ctx do
      moxie = GameLog.parse(ctx.plus.("moxie"), ctx.ruleset)
      both = GameLog.parse(ctx.plus.("moxie") <> "\n" <> ctx.plain.("aley"), ctx.ruleset)

      assert both.levels == moxie.levels
      assert both.equipment == moxie.equipment
      assert {:another_log_not_read, "Aley Blake", false} in both.problems

      # До правки — 87 строк Эли «не по форме экипировки»; осталась одна:
      # разделитель «-----» перед её шапкой ещё внутри раздела Мокси.
      assert Enum.count(both.problems, &match?({:unrecognized_equipment_line, _}, &1)) == 1
    end

    test "три лога — двое названы, по порядку текста", ctx do
      text = Enum.join([ctx.plus.("bor"), ctx.plain.("aley"), ctx.plus.("brunna")], "\n")

      # Разделитель, которым открывается лог Эли, стоит ещё в разделе экипировки
      # Бора и назван строкой не по форме, как до правки (одна строка, а не
      # весь лог Эли).
      assert [
               {:another_log_not_read, "Aley Blake", false},
               {:another_log_not_read, "Брунна *Пылечих*", true},
               {:unrecognized_equipment_line, "-----" <> _}
             ] = GameLog.parse(text, ctx.ruleset).problems
    end

    # Шапка следующего лога начинает его и внутри раздела экипировки: строки
    # клиента с префиксом между ними может не быть (вставка без них).
    test "шапка сразу после раздела экипировки — следующий лог, а не строка экипировки", ctx do
      # Без строк клиента — кроме метки раздела: она той же строкой клиента.
      second =
        ctx.plus.("brunna")
        |> String.split("\n")
        |> Enum.reject(
          &(String.starts_with?(&1, "[CHAT WINDOW TEXT]") and
              not String.contains?(&1, "Equipped:"))
        )
        |> Enum.join("\n")

      bor = GameLog.parse(ctx.plus.("bor"), ctx.ruleset)
      both = GameLog.parse(ctx.plus.("bor") <> "\n" <> second, ctx.ruleset)

      assert both.equipment == bor.equipment
      assert {:another_log_not_read, "Брунна *Пылечих*", true} in both.problems

      # Разделитель перед шапкой Брунны — одна строка не по форме, шапка — нет.
      assert [{:unrecognized_equipment_line, "-----" <> _}] =
               for({:unrecognized_equipment_line, _} = issue <- both.problems, do: issue)
    end

    # Чат перед первым логом — не лог: его шапка первая, а не следующая.
    test "чат перед логом не делает лог вторым", ctx do
      chat = "[CHAT WINDOW TEXT] [Fri Sep 18 00:17:40] [Talk] Хнюпиус: сейчас скину билд\n"
      with_chat = GameLog.parse(chat <> ctx.plus.("hnyupius"), ctx.ruleset)

      assert with_chat.problems == []
      assert length(with_chat.equipment) == 11
    end
  end

  describe "второй раздел экипировки в одном логе" do
    test "не читается и не складывается с первым — назван", ctx do
      gear_only =
        ctx.plus.("brunna")
        |> String.split("\n")
        |> Enum.drop_while(&(not String.contains?(&1, "=== Equipped")))
        |> Enum.join("\n")

      bor = GameLog.parse(ctx.plus.("bor"), ctx.ruleset)
      both = GameLog.parse(ctx.plus.("bor") <> "\n" <> gear_only, ctx.ruleset)

      # Положительный контроль: раздел Брунны сам по себе — экипировка.
      assert GameLog.parse(ctx.plus.("brunna"), ctx.ruleset).equipment != []

      assert both.equipment == bor.equipment
      assert both.equipment_counts == bor.equipment_counts
      assert both.problems == [{:equipment_section_not_read, "Брунна *Пылечих*"}]
    end
  end

  describe "окно лога" do
    test "сумма экипировки и билд — как у одного лога; замечание первым", ctx do
      once = GameLogImport.parse(ctx.plus.("hnyupius"), ctx.ruleset)

      twice =
        GameLogImport.parse(ctx.plus.("hnyupius") <> "\n" <> ctx.plus.("hnyupius"), ctx.ruleset)

      assert twice.build == once.build
      assert length(twice.build.levels) == 40
      assert twice.gear_report == once.gear_report
      assert twice.title == once.title
      assert twice.issues == [{:another_log_not_read, "Хнюпиус", true} | once.issues]
    end

    test "замечания названы словами в обеих локалях, с именем лога", ctx do
      issues = [
        {:another_log_not_read, "Брунна *Пылечих*", true},
        {:another_log_not_read, "Aley Blake", false},
        {:equipment_section_not_read, "Брунна *Пылечих*"}
      ]

      for locale <- ["ru", "en"], issue <- issues do
        Gettext.with_locale(BuildCalculatorWeb.Gettext, locale, fn ->
          text = GameLogImport.issue_text(issue, ctx.ruleset)
          assert text =~ elem(issue, 1), "#{locale} #{inspect(issue)}"
          refute text =~ ~r/^\{/, "#{locale} #{inspect(issue)}"
        end)
      end

      Gettext.with_locale(BuildCalculatorWeb.Gettext, "ru", fn ->
        assert GameLogImport.issue_text(hd(issues), ctx.ruleset) =~ "экипировк"
        refute GameLogImport.issue_text(Enum.at(issues, 1), ctx.ruleset) =~ "экипировк"
        assert GameLogImport.issue_kind(hd(issues)) == "Не перенесено"
      end)
    end
  end
end
