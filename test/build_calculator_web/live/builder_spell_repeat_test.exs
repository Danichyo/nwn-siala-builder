defmodule BuildCalculatorWeb.BuilderSpellRepeatTest do
  @moduledoc """
  Задача 4.64: одно известное заклинание дважды.

  Находка 4.63: колдун 1 / колдун 2, Daze выбран на 2-м уровне, игрок
  возвращается на 1-й — там Daze предлагался свободным (список спрашивал
  известное только на уровнях РАНЬШЕ), клик клал его второй раз, ссылка
  и экспорт несли Daze дважды, а ядро повтор не называло.

  Группы:

    * **репро** — 1-й уровень показывает Daze заблокированным с причиной «уже
      выбрано на уровне 2», и событие `pick_spell` его не кладёт (до задачи
      обработчик известное не спрашивал вовсе);
    * **старая ссылка с повтором** — не снимается: ⚠ на лестнице (у позднего
      уровня) и в ленте секций, чип показывает и снимает;
    * **просмотр `/b/…`** — ⚠ в строке гида, подвал экспорта;
    * **два класса** — бард и колдун знают каждый своё: Daze барда не
      блокирует Daze колдуна (`Spells.known_reason/0`; открытый вопрос, тест
      держит сегодняшний ответ).

  Положительный контроль у каждой группы: разные заклинания не блокируются
  сверх выбранного и ⚠ не получают.

  Редакция — умолчательная (Сиала), тексты по-русски; английский — `labels_test.exs`.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.{Data, Encoding, Rules}
  alias BuildCalculator.Rules.{Build, Spells}
  alias BuildCalculatorWeb.Builder.{Export, Summary}

  setup do
    %{ruleset: Data.ruleset!(Data.default_version())}
  end

  @abilities %{str: 8, dex: 14, con: 14, int: 10, wis: 10, cha: 18}
  @sorcerer_1 [:electric_jolt, :ray_of_frost, :flare, :daze, :burning_hands, :grease]

  defp build(ruleset, levels, spells) do
    b =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: levels,
        base_abilities: @abilities
      )

    picks =
      for {level, names} <- spells, into: %{} do
        slots = Enum.map(Spells.slots_at(b, ruleset, level), & &1.id)
        {level, Map.new(Enum.zip(slots, names))}
      end

    %Build{b | spells: picks}
  end

  # Колдун 1 / колдун 2; на 1-м уровне — все шесть, на 2-м — `spell`.
  defp sorcerer_2(ruleset, spell),
    do: build(ruleset, [:sorcerer, :sorcerer], %{1 => @sorcerer_1, 2 => [spell]})

  defp open(conn, %Build{} = build, level),
    do: live(conn, ~p"/?b=#{Encoding.encode(build)}&l=#{level}")

  defp shared(view) do
    [value] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#share-link")
      |> LazyHTML.attribute("value")

    [_, code] = Regex.run(~r{/b/([^/?#]+)$}, value)
    {:ok, %{build: build}} = Encoding.decode(code)
    {code, build}
  end

  defp illegal_rows?(view), do: has_element?(view, "#level-ladder [data-illegal='1']")

  # Заблокированные строки списка — по `disabled`, а не по тексту.
  defp disabled_spells(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#spell-list button[disabled]")
    |> LazyHTML.attribute("id")
    |> MapSet.new()
  end

  # ------------------------------------------------------------------ репро --

  describe "репро: колдун 1 / колдун 2, Daze выбран на 2-м" do
    test "1-й уровень: Daze заблокирован с причиной, клик его не кладёт", %{
      conn: conn,
      ruleset: ruleset
    } do
      empty = build(ruleset, [:sorcerer, :sorcerer], %{})
      {:ok, view, _html} = open(conn, empty, 2)

      view |> element("#spell-daze") |> render_click()
      view |> element("#level-1") |> render_click()

      assert has_element?(view, "#spell-daze[disabled]")
      assert render(element(view, "#spell-daze")) =~ "уже выбрано на уровне 2"

      # Событие мимо кнопки (устаревший DOM, подделка) — тот же отказ.
      render_click(view, "pick_spell", %{"spell" => "daze"})

      {_code, shared} = shared(view)
      assert shared.spells == %{2 => %{{:circle, 0, 0} => :daze}}
      assert Rules.illegal_spells(shared, ruleset) == []
      refute illegal_rows?(view)
    end

    test "2-й уровень, как и раньше: Daze с 1-го заблокирован", %{conn: conn, ruleset: ruleset} do
      daze_1 = build(ruleset, [:sorcerer, :sorcerer], %{1 => [:daze]})
      {:ok, view, _html} = open(conn, daze_1, 2)

      assert has_element?(view, "#spell-daze[disabled]")
      assert render(element(view, "#spell-daze")) =~ "уже выбрано на уровне 1"
    end

    # Положительный контроль: на 2-м Light, а не Daze — Daze на 1-м свободен
    # и кладётся; заблокировано ровно выбранное (на любом уровне) — и ничего
    # больше.
    test "контроль: другое заклинание на 2-м — Daze на 1-м свободен", %{
      conn: conn,
      ruleset: ruleset
    } do
      light_2 = build(ruleset, [:sorcerer, :sorcerer], %{1 => [:electric_jolt], 2 => [:light]})
      {:ok, view, _html} = open(conn, light_2, 1)

      assert has_element?(view, "#spell-daze:not([disabled])")
      assert render(element(view, "#spell-light")) =~ "уже выбрано на уровне 2"
      assert render(element(view, "#spell-electric_jolt")) =~ "уже выбрано на уровне 1"
      assert disabled_spells(view) == MapSet.new(["spell-electric_jolt", "spell-light"])

      view |> element("#spell-daze") |> render_click()

      {_code, shared} = shared(view)
      assert shared.spells[1] |> Map.values() |> Enum.sort() == [:daze, :electric_jolt]
      assert shared.spells[2] == %{{:circle, 0, 0} => :light}
      refute illegal_rows?(view)
    end
  end

  # ------------------------------------------------- старая ссылка с повтором --

  describe "старая ссылка: Daze на 1-м и на 2-м" do
    test "не снимается: ⚠ у 2-го уровня и в ленте, чип показывает и снимает", %{
      conn: conn,
      ruleset: ruleset
    } do
      dup = sorcerer_2(ruleset, :daze)

      assert Rules.illegal_spells(dup, ruleset) == [
               {2, {:circle, 0, 0}, :daze, {:spell_already_known, :sorcerer, 1}}
             ]

      {:ok, view, _html} = open(conn, dup, 2)

      # Ссылка открылась как пришла: ни флеша, ни переписанного кода.
      refute has_element?(view, "#flash-info")
      assert {code, ^dup} = shared(view)
      assert code == Encoding.encode(dup)

      # Обвиняется поздний: ⚠ у 2-го, у 1-го — нет.
      assert has_element?(view, "#level-2[data-illegal='1']")
      refute has_element?(view, "#level-1[data-illegal='1']")
      assert render(element(view, "#level-2")) =~ "Daze: уже выбрано на уровне 1"
      assert has_element?(view, "#stage-nav-spells[data-illegal='1']")

      assert render(element(view, "#spell-slot-circle-0-0")) =~ "Daze"
      view |> element("#spell-clear-circle-0-0") |> render_click()

      refute illegal_rows?(view)
      refute has_element?(view, "#stage-nav-spells[data-illegal='1']")
      assert {_code, %Build{spells: spells}} = shared(view)
      refute Map.has_key?(spells, 2)
    end

    test "контроль: разные заклинания — без ⚠", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = open(conn, sorcerer_2(ruleset, :light), 2)

      refute illegal_rows?(view)
      refute has_element?(view, "#stage-nav-spells[data-illegal='1']")
    end

    # Повтор в двух слотах ОДНОГО уровня: данные его держат (ссылка), значит
    # рендер обязан его пережить — DOM-id у чипов и лестницы собраны из слота
    # и круга, не из заклинания (HANDOFF, дубль id: LiveViewTest упал бы сам).
    test "повтор в двух слотах одного уровня: ⚠ у уровня, оба чипа на месте", %{
      conn: conn,
      ruleset: ruleset
    } do
      same_level = build(ruleset, [:sorcerer, :sorcerer], %{1 => [:daze, :flare, :daze]})

      assert Rules.illegal_spells(same_level, ruleset) == [
               {1, {:circle, 0, 2}, :daze, {:spell_already_known, :sorcerer, 1}}
             ]

      {:ok, view, _html} = open(conn, same_level, 1)

      assert render(element(view, "#spell-slot-circle-0-0")) =~ "Daze"
      assert render(element(view, "#spell-slot-circle-0-2")) =~ "Daze"
      assert render(element(view, "#level-1")) =~ "Daze: уже выбрано на уровне 1"
      assert has_element?(view, "#spell-daze[disabled]")

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(same_level)}")
      assert render(element(view, "#view-guide-level-1-issue")) =~ "Daze: уже выбрано на уровне 1"
    end
  end

  # -------------------------------------------------------- экран просмотра --

  describe "просмотр /b/ старой ссылки с повтором" do
    test "строка гида — с ⚠ и причиной, экспорт — с подвалом", %{conn: conn, ruleset: ruleset} do
      dup = sorcerer_2(ruleset, :daze)
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(dup)}")

      assert render(element(view, "#view-guide-level-2")) =~ "Daze"
      assert render(element(view, "#view-guide-level-2-issue")) =~ "Daze: уже выбрано на уровне 1"
      refute has_element?(view, "#view-guide-level-1-issue")
      assert has_element?(view, "#view-illegal-2")
      assert has_element?(view, "#view-illegal-note-edit")

      [pre] =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#view-export-text")
        |> Enum.map(&LazyHTML.text/1)

      stats = Rules.compute(dup, ruleset)

      assert pre ==
               Export.text(dup, ruleset, stats,
                 title: Summary.title(ruleset, dup, stats),
                 show_granted_feats: false
               )

      assert pre =~ "02: Sorcerer(2): [0] Daze"
      assert pre =~ "⚠ У билда 1 уровень с нарушением правил"
    end

    test "контроль: разные заклинания — без ⚠", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(sorcerer_2(ruleset, :light))}")

      refute has_element?(view, "#view-guide-level-2-issue")
      refute has_element?(view, "#view-illegal")
    end
  end

  # ------------------------------------------------------------- два класса --

  # Сегодняшний ответ на открытый вопрос (`Spells.known_reason/0`): у класса
  # свой список известных — Daze барда не блокирует Daze колдуна. До задачи
  # список колдуна отбивал всё, что знал бард на уровнях раньше.
  describe "бард 1 / колдун 1" do
    test "Daze барда не блокирует Daze колдуна; свой повтор колдуна — блокирует", %{
      conn: conn,
      ruleset: ruleset
    } do
      bard_sorc =
        build(ruleset, [:bard, :sorcerer], %{1 => [:daze, :flare, :light, :resistance]})

      {:ok, view, _html} = open(conn, bard_sorc, 2)

      assert has_element?(view, "#spell-daze:not([disabled])")
      view |> element("#spell-daze") |> render_click()

      refute illegal_rows?(view)

      # Колдун свой Daze знает — второй раз его список не предлагает.
      assert has_element?(view, "#spell-daze[disabled]")
      assert render(element(view, "#spell-daze")) =~ "уже выбрано на уровне 2"

      {_code, shared} = shared(view)
      assert shared.spells[2] == %{{:circle, 0, 0} => :daze}
      assert Rules.illegal_spells(shared, ruleset) == []
    end
  end
end
