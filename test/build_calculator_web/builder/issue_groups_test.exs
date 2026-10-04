defmodule BuildCalculatorWeb.Builder.IssueGroupsTest do
  @moduledoc """
  Задача 4.35: замечания импорта группами, с потолком на группу
  (`BuildCalculatorWeb.Builder.IssueGroups`). Враждебная вставка давала
  32 000 строк отчёта; группа рисует первые 150 и говорит, сколько ещё,
  а «показать все» раскрывает её целиком до тысячи.

  Замечания здесь — синтетические кортежи: модуль не знает, чьи они (импорт
  текста или лог игры), и получает вид и текст функциями.
  """
  use ExUnit.Case, async: true

  alias BuildCalculatorWeb.Builder.IssueGroups

  defp kind_of({kind, _n}), do: kind
  defp text_of({kind, n}), do: "#{kind} #{n}"

  defp issues(kind, count), do: for(n <- 1..count//1, do: {kind, n})

  defp group(issues), do: IssueGroups.group(issues, &kind_of/1, &text_of/1)

  test "потолок — 150 на группу, раскрытие — до тысячи" do
    assert IssueGroups.shown() == 150
    assert IssueGroups.listed_max() == 1_000
  end

  describe "группы" do
    test "в порядке первого появления; id — место замечания в отчёте, с единицы" do
      list = [{"b", 1}, {"a", 1}, {"b", 2}, {"c", 1}, {"a", 2}]

      assert [
               %{kind: "b", total: 2, items: [%{id: 1, text: "b 1"}, %{id: 3, text: "b 2"}]},
               %{kind: "a", total: 2, items: [%{id: 2, text: "a 1"}, %{id: 5, text: "a 2"}]},
               %{kind: "c", total: 1, items: [%{id: 4, text: "c 1"}]}
             ] = group(list)
    end

    test "короткая группа рисуется целиком, без строки «ещё»" do
      for count <- [1, 149, 150] do
        [g] = group(issues("x", count))

        assert length(g.items) == count
        assert g.total == count
        assert g.hidden == 0
        refute g.expandable?
      end
    end

    test "длиннее 150 — первые 150 и сколько ещё; до тысячи — можно раскрыть" do
      for count <- [151, 400, 1_000] do
        [g] = group(issues("x", count))

        assert length(g.items) == 150
        assert List.last(g.items).id == 150
        assert g.total == count
        assert g.hidden == count - 150
        assert g.expandable?
      end
    end

    test "длиннее тысячи — первые 150, сколько ещё, и раскрыть нельзя" do
      [g] = group(issues("x", 1_001))

      assert length(g.items) == 150
      assert g.total == 1_001
      assert g.hidden == 851
      refute g.expandable?
      assert g.rest == []
    end

    test "потолок у каждой группы свой: соседняя короткая группа рисуется целиком" do
      interleaved = Enum.flat_map(1..300, fn n -> [{"long", n}, {"short", n}] end)
      list = Enum.take(interleaved, 600) ++ issues("tail", 3)

      [long, short, tail] = group(list)

      assert {long.kind, length(long.items), long.hidden} == {"long", 150, 150}
      assert {short.kind, length(short.items), short.hidden} == {"short", 150, 150}
      assert {tail.kind, length(tail.items), tail.hidden} == {"tail", 3, 0}

      # Место в отчёте, а не в группе: 150-я строка «long» — 299-е замечание.
      assert List.last(long.items).id == 299
    end

    # Тексты — только тому, что рисуется: иначе враждебная вставка заставляла
    # бы сочинить 32 000 фраз, чтобы показать 150.
    test "текст делается только для нарисованного" do
      counter = :counters.new(1, [])

      text_of = fn issue ->
        :counters.add(counter, 1, 1)
        text_of(issue)
      end

      groups = IssueGroups.group(issues("x", 32_000) ++ [{"y", 1}], &kind_of/1, text_of)

      assert :counters.get(counter, 1) == 151
      assert Enum.map(groups, & &1.total) == [32_000, 1]
    end
  end

  describe "показать все" do
    test "раскрывает группу целиком: тексты остальных, строки «ещё» больше нет" do
      [g] = group(issues("x", 400))
      g = IssueGroups.expand(g, &text_of/1)

      assert length(g.items) == 400
      assert Enum.map(g.items, & &1.id) == Enum.to_list(1..400)
      assert List.last(g.items).text == "x 400"
      assert g.hidden == 0
      refute g.expandable?
      # Второй раз — ничего нового.
      assert IssueGroups.expand(g, &text_of/1) == g
    end

    test "раскрытие по номеру группы из `phx-value-group`; чужой номер ничего не меняет" do
      groups = group(issues("a", 3) ++ issues("b", 200))

      assert [%{hidden: 0}, %{hidden: 0, items: items}] =
               IssueGroups.expand_at(groups, "1", &text_of/1)

      assert length(items) == 200

      for bad <- ["2", "-1", "x", "1.5", nil] do
        assert IssueGroups.expand_at(groups, bad, &text_of/1) == groups
      end
    end

    test "группа длиннее тысячи не раскрывается и событием, собранным руками" do
      groups = group(issues("x", 5_000))

      assert IssueGroups.expand_at(groups, "0", &text_of/1) == groups
    end
  end
end
