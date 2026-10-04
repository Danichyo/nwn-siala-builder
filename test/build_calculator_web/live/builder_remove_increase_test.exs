defmodule BuildCalculatorWeb.BuilderRemoveIncreaseTest do
  @moduledoc """
  Задача 4.38: прибавку к характеристике, которую ядро называет нелегальной
  (`Rules.illegal_increases/2`, задача 4.37), конструктор даёт снять на её
  уровне, не трогая остального билда, — а поставить прибавку на уровень,
  который её не даёт, нельзя ни кликом, ни событием, собранным руками.

  До задачи ⚠ на лестнице стояла, а снять прибавку было негде: секция прибавки
  рисовалась только на уровнях, которые её дают, и билд чинился лишь обрезкой
  ниже этого уровня — вместе со всем, что выше. Обработчик при этом ставил
  прибавку на ЛЮБОЙ уровень (находка 4.36).

  Билд приходит ссылкой, как приходит к игроку: такие прибавки несут старые
  ссылки и записи библиотеки, собранные импортом текста до 4.36. Редакция —
  умолчательная (Сиала): прибавки там на тех же уровнях, что у ванили
  (`vanilla/epic.json` → `ability_increases`), таблица ядра для обоих
  ruleset'ов — `test/build_calculator/rules/illegal_increases_test.exs`.

  Прибавка с ключом `0` в ссылке не доезжает до билда вовсе — декодер
  выбрасывает её с пометкой (`Encoding.to_increases/3`); последний блок.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.{Data, Encoding}
  alias BuildCalculator.Rules.Build

  setup do
    %{ruleset: Data.ruleset!(Data.default_version())}
  end

  # Тот же билд, что у 4.37 (`builder_illegal_increase_test.exs`): человек
  # (без расовых модификаторов), воин 8, STR 14 и DEX 14 покупкой. Прибавки на
  # 4-м и 8-м — там, где их даёт источник, `DEX +1` на 5-м — там, где её нет.
  # Итог: STR 16 (14 + 4-й + 8-й), DEX 15 с лишней прибавкой и 14 без неё.
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

  defp open(conn, %Build{} = build), do: live(conn, ~p"/?b=#{Encoding.encode(build)}")

  # Код, который держит конструктор, — он же в ссылке «поделиться». Сверка по
  # нему отвечает «билд не изменился» / «билд стал ровно таким» целиком, а не
  # по одному числу на экране.
  defp holds?(view, %Build{} = build),
    do: has_element?(view, "#share-link[value$='/b/#{Encoding.encode(build)}']")

  @reason "уровень 5 прибавки к характеристике не даёт"

  describe "прибавка не на своём уровне" do
    test "ссылка с прибавкой на 5-м — ⚠ на строке 5-го уровня", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = open(conn, stray(ruleset))

      assert has_element?(view, "#level-5[data-illegal='1']")
      assert has_element?(view, "#level-5-issue")
      assert has_element?(view, "#stat-ability-dex b", "15")
    end

    test "на 5-м уровне — прибавка, причина и «убрать»; выбора новой нет", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = open(conn, stray(ruleset))
      view |> element("#level-5") |> render_click()

      assert has_element?(view, "#stage-title", "Уровень 5")
      assert has_element?(view, "#section-increase")
      # Лента секций повторяет `:if` секции (`nav_sections/1`).
      assert has_element?(view, "#stage-nav-increase")

      assert has_element?(view, "#increase-remove", "Убрать +1 DEX")

      # Во что обойдётся снятие — два расчёта, с прибавкой и без.
      assert has_element?(view, "#increase-remove .card-lv", "15 → 14")
      assert has_element?(view, "#increase-stray-reason", @reason)

      # Шести карточек выбора здесь нет: поставить новую прибавку нельзя.
      refute has_element?(view, "#increase-cards")
      refute has_element?(view, "[id^='increase-card-']")
    end

    test "«убрать» — ⚠ пропадает, DEX на единицу меньше, остальное на месте", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = open(conn, stray(ruleset))
      view |> element("#level-5") |> render_click()
      view |> element("#increase-remove") |> render_click()

      refute has_element?(view, "#level-5[data-illegal='1']")
      refute has_element?(view, "#level-5-issue")
      refute has_element?(view, "#spine-illegal")

      assert has_element?(view, "#stat-ability-dex b", "14")
      assert has_element?(view, "#stat-ability-str b", "16")

      # Остальное не тронуто: билд теперь ровно тот же, только без прибавки
      # на 5-м, — и адрес это же и несёт.
      assert holds?(view, legal(ruleset))
      assert_patch(view, ~p"/?b=#{Encoding.encode(legal(ruleset))}&l=5")

      # Уровень снова без прибавки — и без её секции.
      assert has_element?(view, "#stage-title", "Уровень 5")
      refute has_element?(view, "#section-increase")
      refute has_element?(view, "#stage-nav-increase")
    end

    # «Убрать — можно всегда»: снятие уровень не спрашивает. Событие то же,
    # что шлёт `#increase-remove`, только собрано руками.
    test "снять событием, собранным руками, тоже можно", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = open(conn, stray(ruleset))
      view |> element("#level-5") |> render_click()

      render_click(view, "pick_increase", %{"ability" => "dex"})

      assert holds?(view, legal(ruleset))
      refute has_element?(view, "#level-5-issue")
    end
  end

  describe "обработчик проверяет уровень" do
    test "поставить прибавку на 5-й уровень событием, собранным руками, — отказ", %{
      conn: conn,
      ruleset: ruleset
    } do
      # На пустое место: у законного билда на 5-м ничего нет.
      {:ok, view, _html} = open(conn, legal(ruleset))
      view |> element("#level-5") |> render_click()
      refute has_element?(view, "#section-increase")

      render_click(view, "pick_increase", %{"ability" => "str"})

      assert holds?(view, legal(ruleset))
      refute has_element?(view, "#level-5[data-illegal='1']")
      assert has_element?(view, "#stat-ability-str b", "16")

      # Замена одной характеристики другой — тоже постановка, и тоже отказ:
      # DEX на 5-м остаётся, STR не прибавляется.
      {:ok, view, _html} = open(conn, stray(ruleset))
      view |> element("#level-5") |> render_click()

      render_click(view, "pick_increase", %{"ability" => "str"})

      assert holds?(view, stray(ruleset))
      assert has_element?(view, "#stat-ability-str b", "16")
      assert has_element?(view, "#stat-ability-dex b", "15")
      assert has_element?(view, "#increase-remove", "DEX")
    end

    # Положительный контроль отказа выше: ТО ЖЕ событие, собранное руками, на
    # 4-м уровне проходит, — значит на 5-м его отбил уровень, а не форма
    # параметров.
    test "на 4-м уровне — как прежде: шесть карточек, замена, снятие, то же событие", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = open(conn, legal(ruleset))
      view |> element("#level-4") |> render_click()

      assert has_element?(view, "#increase-cards")

      for ability <- ~w(str dex con int wis cha) do
        assert has_element?(view, "#increase-card-#{ability}")
      end

      assert has_element?(view, "#increase-card-str[data-chosen='1']")
      refute has_element?(view, "#increase-stray")
      refute has_element?(view, "#increase-remove")

      view |> element("#increase-card-dex") |> render_click()
      assert has_element?(view, "#increase-card-dex[data-chosen='1']")
      assert has_element?(view, "#stat-ability-dex b", "15")
      assert has_element?(view, "#stat-ability-str b", "15")

      view |> element("#increase-card-dex") |> render_click()
      refute has_element?(view, "[id^='increase-card-'][data-chosen='1']")
      assert has_element?(view, "#stat-ability-dex b", "14")

      render_click(view, "pick_increase", %{"ability" => "str"})
      assert holds?(view, legal(ruleset))
      assert has_element?(view, "#increase-card-str[data-chosen='1']")
    end
  end

  # Попутное (a): блок честности экрана просмотра говорил о любом нарушении
  # «обычно это след правки более раннего решения», а прибавку не на своём
  # уровне оставляет не правка, а старая ссылка из импорта текста.
  describe "экран просмотра — фраза по виду нарушения" do
    test "прибавка не на своём уровне — своя фраза, «следа правки» нет", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(stray(ruleset))}")

      assert has_element?(view, "#view-illegal-note-increase", "не след правки")
      assert has_element?(view, "#view-illegal-note-increase", "на её уровне")
      refute has_element?(view, "#view-illegal-note-edit")

      # Фраза встала рядом со списком, а не вокруг него (`ul` внутри `span`
      # браузер вынес бы из блока, как когда-то из `p`).
      assert has_element?(view, "div#view-illegal > #view-illegal-list")
    end

    # Положительный контроль: у нарушения другого вида фраза прежняя — значит
    # выше её убрал вид причины, а не что-то в блоке.
    test "класс не по мировоззрению — прежняя фраза про правку", %{conn: conn, ruleset: ruleset} do
      barbarian =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: List.duplicate(:barbarian, 3),
          base_abilities: %{str: 14, dex: 14, con: 12, int: 10, wis: 10, cha: 8}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(barbarian)}")

      assert has_element?(
               view,
               "#view-illegal-note-edit",
               "Обычно это след правки более раннего решения"
             )

      refute has_element?(view, "#view-illegal-note-increase")
    end
  end

  describe "ключ 0 в ссылке" do
    # Уровня 0 у персонажа нет, а число считало бы такую прибавку на каждом
    # уровне. Декодер выбрасывает её с пометкой, как прочие строки, которых
    # билд держать не может.
    test "выпадает с пометкой: флеш называет её, DEX не прибавлен, ⚠ нет", %{
      conn: conn,
      ruleset: ruleset
    } do
      zero = build(ruleset, %{0 => :dex, 4 => :str, 8 => :str})
      {:ok, view, _html} = open(conn, zero)

      assert render(element(view, "#flash-info")) =~
               "Из ссылки выпало: прибавка к характеристике 0|dex"

      assert has_element?(view, "#stat-ability-dex b", "14")
      refute has_element?(view, "#spine-illegal")

      # ⚠️ Адрес до первой правки несёт пришедший код целиком — так с любой
      # выпавшей строкой (`load_code/3` хранит код как пришёл). Первая же
      # правка пишет код билда, в котором прибавки с ключом 0 уже нет.
      view |> element("#level-4") |> render_click()
      render_click(view, "pick_increase", %{"ability" => "str"})
      render_click(view, "pick_increase", %{"ability" => "str"})
      assert holds?(view, legal(ruleset))
    end
  end
end
