defmodule BuildCalculatorWeb.BuilderLostSpellTest do
  @moduledoc """
  Задача 4.63: известное заклинание, чей уровень больше не даёт его слота,
  в конструкторе не остаётся — ни после правки, ни после открытия ссылки;
  экран просмотра старой ссылки его не печатает как законное.

  Находка 4.62: колдун 1 с выбранными заклинаниями, класс 1-го уровня сменён
  на воина. Заклинания оставались в билде; лестница их не показывала (рисует
  по слотам уровня), а гид просмотра и экспорт печатали «01: Fighter(1): [0]
  Electric jolt, …», и следующие уровни колдуна отказывали им как «уже
  известным».

  Группы по входам:

    * **правка, класс 1-го уровня → воин** — воронка `put_build/2` снимает все
      шесть, заметка `#spell-prune` называет снятое, ⚠ нет; 2-й уровень снова
      предлагает снятое;
    * **правка, → бард** — снят только 1-й круг (слота нет), два кантрипа не из
      списка барда остаются в своих чипах с ⚠ на лестнице и в ленте секций;
    * **ссылка** — тот же путь при открытии, флеш «Из ссылки выпало», адрес
      и «Скопировать ссылку» — код того, что на экране;
    * **просмотр `/b/…` старой ссылки** — билд не переписывается: строка гида
      несёт ⚠ с причиной, экспорт — подвал «уровень с нарушением правил».

  Положительный контроль у каждой группы: законное (колдун остался колдуном,
  ссылка без таких заклинаний) не трогается.

  Редакция — умолчательная (Сиала), тексты по-русски; английские — `labels_test.exs`.
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

  # Колдун 1 / колдун 2: шесть заклинаний 1-го уровня и Light на 2-м — так, как
  # их кладёт `pick_spell`, в слоты уровня по порядку.
  defp sorcerer_2(ruleset) do
    %Build{} =
      b =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: [:sorcerer, :sorcerer],
        base_abilities: @abilities
      )

    slots = fn level -> Enum.map(Spells.slots_at(b, ruleset, level), & &1.id) end

    b = %Build{
      b
      | spells: %{
          1 => Map.new(Enum.zip(slots.(1), @sorcerer_1)),
          2 => Map.new(Enum.zip(slots.(2), [:light]))
        }
    }

    assert Rules.illegal_spells(b, ruleset) == []
    b
  end

  # Ровно то, что оставлял конструктор до задачи: 1-й уровень стал воинским.
  defp fighter_with_spells(ruleset), do: Build.replace_level(sorcerer_2(ruleset), 1, :fighter)

  defp clean_fighter(ruleset) do
    %Build{} = edited = fighter_with_spells(ruleset)
    %Build{edited | spells: %{2 => %{{:circle, 0, 0} => :light}}}
  end

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

  defp prune_text(view, level, slot_dom_id),
    do: render(element(view, "#spell-prune-#{level}-#{slot_dom_id}"))

  defp illegal_rows?(view), do: has_element?(view, "#level-ladder [data-illegal='1']")

  # ---------------------------------------------------- правка: класс → воин --

  describe "правка: колдун 1 / колдун 2, 1-й уровень → воин" do
    test "шесть заклинаний сняты, ⚠ нет, заметка называет снятое", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = open(conn, sorcerer_2(ruleset), 1)

      assert has_element?(view, "#spell-slot-circle-0-0[data-filled='1']")
      refute has_element?(view, "#spell-prune")

      view |> element("#class-card-fighter") |> render_click()

      refute illegal_rows?(view)
      refute has_element?(view, "#section-spells")
      # Фитов эта правка не сняла — их заметки нет.
      refute has_element?(view, "#feat-prune")

      assert render(element(view, "#spell-prune")) =~ "Эти заклинания сняты с билда:"

      assert prune_text(view, 1, "circle-0-0") =~
               "уровень 1: Electric jolt — этот уровень не даёт заклинаний 0 круга"

      assert prune_text(view, 1, "circle-1-1") =~
               "уровень 1: Grease — этот уровень не даёт заклинаний 1 круга"

      # Ровно шесть строк — Light 2-го уровня не тронут.
      html = render(element(view, "#spell-prune"))
      assert length(Regex.scan(~r/id="spell-prune-\d+-circle-/, html)) == 6

      {code, %Build{} = shared} = shared(view)
      assert shared.levels == [:fighter, :sorcerer]
      assert shared.spells == %{2 => %{{:circle, 0, 0} => :light}}
      assert_patch(view, "/?b=#{code}&l=1")
    end

    # `Spells.known/2` следующих уровней: снятое снова предлагается.
    test "2-й уровень (теперь колдун 1) снова предлагает снятое", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = open(conn, sorcerer_2(ruleset), 1)
      view |> element("#class-card-fighter") |> render_click()
      view |> element("#level-2") |> render_click()

      # Light стоит в своём слоте, остальные слоты колдуна 1 пусты.
      assert has_element?(view, "#spell-slot-circle-0-0[data-filled='1']")
      refute has_element?(view, "#spell-slot-circle-0-1[data-filled='1']")

      assert has_element?(view, "#spell-electric_jolt:not([disabled])")
      assert has_element?(view, "#spell-burning_hands:not([disabled])")
      # Контроль: известное (Light) по-прежнему отбито.
      assert has_element?(view, "#spell-light[disabled]")
    end

    test "заметка переживает переход по уровням и гаснет на правке без снятого", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = open(conn, sorcerer_2(ruleset), 1)
      view |> element("#class-card-fighter") |> render_click()
      assert has_element?(view, "#spell-prune")

      view |> element("#level-2") |> render_click()
      assert has_element?(view, "#spell-prune-1-circle-0-0")

      view |> element("#level-1") |> render_click()
      view |> element("#alignment-chaotic_neutral") |> render_click()
      refute has_element?(view, "#spell-prune")
    end

    test "контроль: правка, которая слотов не трогает, ничего не снимает", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = sorcerer_2(ruleset)
      {:ok, view, _html} = open(conn, build, 1)

      view |> element("#alignment-chaotic_neutral") |> render_click()

      refute has_element?(view, "#spell-prune")
      assert {_code, %Build{spells: spells}} = shared(view)
      assert spells == build.spells
    end
  end

  # ---------------------------------------------------- правка: класс → бард --

  describe "правка: 1-й уровень → бард" do
    test "снят 1-й круг; кантрипы не из списка барда — в чипах, с ⚠", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = open(conn, sorcerer_2(ruleset), 1)
      view |> element("#class-card-bard") |> render_click()

      assert prune_text(view, 1, "circle-1-0") =~ "уровень 1: Burning hands"
      assert prune_text(view, 1, "circle-1-1") =~ "уровень 1: Grease"
      refute has_element?(view, "#spell-prune-1-circle-0-0")

      # Electric jolt — в своём чипе (✕ его снимает), лестница и лента — с ⚠.
      assert render(element(view, "#spell-slot-circle-0-0")) =~ "Electric jolt"
      assert has_element?(view, "#level-1[data-illegal='1']")

      # Задача 4.40, пункт 17: одна причина — одна строка, имена через запятую.
      assert render(element(view, "#level-1")) =~
               "Electric jolt, Ray of frost: нет в списке заклинаний 0 круга Bard"

      assert has_element?(view, "#stage-nav-spells[data-illegal='1']")

      # Снять чипом — ⚠ уходит, когда не из списка не осталось ни одного.
      view |> element("#spell-clear-circle-0-0") |> render_click()
      assert render(element(view, "#level-1")) =~ "Ray of frost"
      view |> element("#spell-clear-circle-0-1") |> render_click()
      refute has_element?(view, "#level-1[data-illegal='1']")
      refute has_element?(view, "#stage-nav-spells[data-illegal='1']")
    end
  end

  # ------------------------------------------------------------------ ссылка --

  describe "ссылка с заклинаниями, которых уровень не держит" do
    test "открытие: сняты, флеш называет, ⚠ нет, «Скопировать ссылку» — свой код", %{
      conn: conn,
      ruleset: ruleset
    } do
      edited = fighter_with_spells(ruleset)
      assert length(Rules.illegal_spells(edited, ruleset)) == 6

      {:ok, view, _html} = open(conn, edited, 1)

      flash = render(element(view, "#flash-info"))

      assert flash =~
               "Из ссылки выпало: уровень 1: Electric jolt — этот уровень не даёт заклинаний 0 круга"

      assert flash =~ "уровень 1: Grease — этот уровень не даёт заклинаний 1 круга"
      refute flash =~ "Light"
      refute illegal_rows?(view)
      refute has_element?(view, "#spell-prune")

      clean = clean_fighter(ruleset)
      assert {code, ^clean} = shared(view)
      assert code == Encoding.encode(clean)
    end

    # Адрес на подключённом монтировании `assert_patch/2` не видит (3.228) —
    # проверяется переходом в живой сессии.
    test "адрес переписывается на код того, что на экране", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = open(conn, sorcerer_2(ruleset), 1)

      html = render_patch(view, "/?b=#{Encoding.encode(fighter_with_spells(ruleset))}&l=1")

      assert html =~ "Из ссылки выпало"
      assert_patch(view, "/?b=#{Encoding.encode(clean_fighter(ruleset))}&l=1")
    end

    test "контроль: ссылка без таких заклинаний открывается как пришла", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = sorcerer_2(ruleset)
      {:ok, view, _html} = open(conn, build, 2)

      refute has_element?(view, "#flash-info")
      assert {code, ^build} = shared(view)
      assert code == Encoding.encode(build)
    end
  end

  # -------------------------------------------------------- экран просмотра --

  describe "просмотр /b/ старой ссылки" do
    test "строка гида — с ⚠ и причиной, экспорт — с подвалом о нарушении", %{
      conn: conn,
      ruleset: ruleset
    } do
      edited = fighter_with_spells(ruleset)
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(edited)}")

      # Билд не переписан: заклинания в строке гида есть, но с ⚠.
      assert render(element(view, "#view-guide-level-1")) =~ "Electric jolt"

      # Задача 4.40, пункт 17: шесть заклинаний, две причины — по кругу. До задачи
      # шесть строк «имя: причина» склеивались «; » в одну длинную строку.
      issue = render(element(view, "#view-guide-level-1-issue"))

      assert issue =~
               "<span>Electric jolt, Ray of frost, Flare, Daze: этот уровень не даёт заклинаний 0 круга; " <>
                 "Burning hands, Grease: этот уровень не даёт заклинаний 1 круга</span>"

      assert render(element(view, "#view-illegal-1")) =~
               "Electric jolt, Ray of frost, Flare, Daze: этот уровень не даёт заклинаний 0 круга; " <>
                 "Burning hands, Grease: этот уровень не даёт заклинаний 1 круга"

      assert has_element?(view, "#view-illegal-1")
      assert has_element?(view, "#view-illegal-note-edit")

      # Экспорт — `Export.text/4` байт в байт, тот же, что копирует «скопировать».
      [pre] =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#view-export-text")
        |> Enum.map(&LazyHTML.text/1)

      stats = Rules.compute(edited, ruleset)

      expected =
        Export.text(edited, ruleset, stats,
          title: Summary.title(ruleset, edited, stats),
          show_granted_feats: false
        )

      assert pre == expected
      assert pre =~ "01: Fighter(1): [0] Electric jolt"
      assert pre =~ "⚠ У билда 1 уровень с нарушением правил"
    end

    test "контроль: законный билд — без ⚠", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(sorcerer_2(ruleset))}")

      refute has_element?(view, "#view-guide-level-1-issue")
      refute has_element?(view, "#view-illegal")
      assert render(element(view, "#view-export-text")) =~ "01: Sorcerer(1): [0] Electric jolt"
    end
  end
end
