defmodule BuildCalculatorWeb.BuilderIllegalIncreaseTest do
  @moduledoc """
  Задача 4.37 на экране: прибавка к характеристике, записанная на уровне,
  который её не даёт, — ⚠ на строке этого уровня, та же фраза в сводке экрана
  просмотра и счёт в подвале экспорта. Один источник на все три —
  `Labels.ladder_issues/2` (CLAUDE.md §6).

  Билд приходит ССЫЛКОЙ, как приходит к игроку Сиалы: конструктор такую
  прибавку не ставит (выбор рисуется только на уровнях прибавки), а текстовый
  импорт до задачи 4.36 ставил её молча, и ссылки и записи библиотеки с ней
  остались. Редакция — умолчательная (Сиала), потому что видно это прежде
  всего там; обе редакции читают одну функцию ядра, её таблица для обоих
  ruleset'ов — `test/build_calculator/rules/illegal_increases_test.exs`.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.{Data, Encoding, Rules}
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.Export

  setup do
    %{ruleset: Data.ruleset!(Data.default_version())}
  end

  # Человек (без расовых модификаторов), воин 8: прибавки на 4-м и 8-м стоят
  # там, где их даёт источник (`vanilla/epic.json` → `ability_increases`),
  # а `DEX +1` на 5-м — там, где её нет. DEX 14 покупкой, 15 с этой прибавкой.
  defp build(ruleset, increases) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :human,
      alignment: :lawful_good,
      levels: List.duplicate(:fighter, 8),
      base_abilities: %{str: 14, dex: 14, con: 12, int: 10, wis: 10, cha: 8},
      ability_increases: increases
    )
  end

  defp stray(ruleset), do: build(ruleset, %{4 => :str, 5 => :dex, 8 => :str})
  defp legal(ruleset), do: build(ruleset, %{4 => :str, 8 => :str})

  @said "+1 DEX: уровень 5 прибавки к характеристике не даёт"

  describe "конструктор" do
    test "⚠ стоит на строке 5-го уровня и называет прибавку; число её держит", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(stray(ruleset))}")

      assert has_element?(view, "#level-5[data-illegal='1']")
      assert has_element?(view, "#level-5-issue")
      assert render(element(view, "#level-5-issue")) =~ @said

      # Уровни, где прибавка на месте, не помечены: обвиняется ровно та,
      # что стоит не на своём уровне.
      for level <- [4, 8] do
        refute has_element?(view, "#level-#{level}[data-illegal='1']")
        refute has_element?(view, "#level-#{level}-issue")
      end

      assert render(element(view, "#spine-illegal")) =~ "1 уровень с нарушением правил"

      # Число не тронуто (прецедент семейства: нелегальный фит ядро тоже
      # считает): DEX 14 покупкой + 1 этой прибавкой.
      assert has_element?(view, "#stat-ability-dex b", "15")
    end

    # Положительный контроль (HANDOFF, «пустые проверки»): без лишней
    # прибавки тот же билд не помечен нигде — значит выше отметку поставила
    # прибавка, а не что-то ещё в билде.
    test "тот же билд без прибавки на 5-м не помечен", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(legal(ruleset))}")

      for level <- 1..8 do
        refute has_element?(view, "#level-#{level}[data-illegal='1']")
        refute has_element?(view, "#level-#{level}-issue")
      end

      refute has_element?(view, "#spine-illegal")
      assert has_element?(view, "#stat-ability-dex b", "14")
    end

    # Решение задачи 4.37 о прибавке ЗА ПРЕДЕЛОМ длины билда — «не считается
    # и не называется, пока лестница до неё не дошла» — и вот где оно нужно не
    # только ссылке: сам конструктор кладёт такую прибавку, когда игрок открыл
    # ещё не взятый уровень и выбрал прибавку раньше класса. Воин 3, уровень 4
    # открыт, класса на нём нет, прибавка записана — и это выбор, ждущий своего
    # уровня, а не нарушение.
    test "прибавка, выбранная на ещё не взятом уровне, не помечается", %{
      conn: conn,
      ruleset: ruleset
    } do
      three = ruleset |> legal() |> Build.truncate(3)
      assert three.ability_increases == %{}
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(three)}")

      view |> element("#level-4") |> render_click()
      view |> element("#increase-card-str") |> render_click()

      # Положительный контроль: выбор записан, а уровень 4 ещё не взят.
      assert has_element?(view, "#increase-card-str[data-chosen='1']")
      refute has_element?(view, "#level-4[data-empty='0']")

      refute has_element?(view, "#level-4-issue")
      refute has_element?(view, "#spine-illegal")
    end
  end

  describe "экран просмотра" do
    test "сводка и гид называют прибавку на её уровне", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(stray(ruleset))}")

      assert render(element(view, "#view-illegal")) =~ "1 уровень с нарушением правил"
      assert render(element(view, "#view-illegal-5")) =~ @said

      assert has_element?(view, "#view-guide-level-5[data-illegal='1']")
      assert render(element(view, "#view-guide-level-5-issue")) =~ @said
    end

    test "без прибавки на 5-м блока нарушений нет", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(legal(ruleset))}")

      refute has_element?(view, "#view-illegal")
      refute has_element?(view, "#view-guide-level-5-issue")
    end
  end

  # ⚠️ Подвал экспорта называет не причину, а СЧЁТ уровней с нарушением и
  # отсылает в конструктор («там названы причины») — так он устроен для всех
  # трёх прогонок (`Export.footer/3`), и прибавка в этот счёт входит. Строка
  # уровня при этом печатает саму прибавку с её числом: экспорт показывает то
  # же, что считает ядро.
  describe "экспорт" do
    test "подвал считает уровень с прибавкой, строка уровня её печатает", %{ruleset: ruleset} do
      build = stray(ruleset)
      text = Export.text(build, ruleset, Rules.compute(build, ruleset))

      assert text =~ "05: Fighter(5): ▲ DEX 15"
      assert text =~ "⚠ У билда 1 уровень с нарушением правил"

      clean = legal(ruleset)
      refute Export.text(clean, ruleset, Rules.compute(clean, ruleset)) =~ "с нарушением правил"
    end
  end
end
