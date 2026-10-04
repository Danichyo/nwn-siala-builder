defmodule BuildCalculatorWeb.BuilderLostSlotTest do
  @moduledoc """
  Задача 4.62: пик в слоте, которого его уровень не даёт, в конструкторе
  не остаётся — ни после правки, ни после открытия ссылки.

  До задачи такие пики оставлял сам конструктор: `pick_race` не чистил
  расовый слот (человек → эльф с фитом в «Бонусе расы»), а смена класса
  раннего уровня перенумеровывала классовые уровни после себя, и бонусный слот
  позднего уровня пропадал (`prune_slots/3` чистил только правленый уровень).
  С 4.61 лестница ставила на них ⚠ «этот уровень не даёт слота …», но чипа
  у пропавшего слота нет — снять пик было нечем, а число фит считало.

  Три входа — три группы:

    * **правка, раса** — воронка `put_build/2` снимает расовый пик, заметка
      `#feat-prune` называет снятое (по образцу `#point-buy-reset`), ⚠ нет;
    * **правка, класс 1-го уровня у воина 4** — сняты пики 1-го и 4-го уровня,
      пик 2-го (слот с тем же id на том же уровне) остался; заметка держится
      при переходе по уровням и гаснет на следующей правке, которая ничего
      не сняла;
    * **ссылка** — тот же путь при открытии, снятое называет флеш «Из ссылки
      выпало», адрес и «Скопировать ссылку» — код того, что на экране.

  Положительный контроль у каждой группы: законное (общий пик, слот, который
  остался, ссылка без таких пиков) не трогается.

  Редакция — умолчательная (Сиала), тексты по-русски; английские — `labels_test.exs`.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.{Data, Encoding, Ids, Rules}
  alias BuildCalculator.Rules.Build

  setup do
    %{ruleset: Data.ruleset!(Data.default_version())}
  end

  @fighter_abilities %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8}
  @wizard_abilities %{str: 8, dex: 14, con: 14, int: 18, wis: 10, cha: 8}
  @bonus {:class_bonus, :fighter}

  defp build(ruleset, race, levels, abilities, feats),
    do:
      Build.new(
        ruleset_version: ruleset.version,
        race: race,
        alignment: :true_neutral,
        levels: levels,
        base_abilities: abilities,
        feats: feats
      )

  # Человек-волшебник 1: Alertness в общем слоте, Iron will в расовом — у числа
  # есть что терять (+2 Will).
  defp human_wizard(ruleset),
    do:
      build(ruleset, :human, [:wizard], @wizard_abilities, %{
        1 => %{general: :alertness, racial: :iron_will}
      })

  # Человек-воин 4: бонусные фиты Воина на 1, 2 и 4-м (`fandom:Fighter`),
  # общие на 1 и 3-м, расовый на 1-м.
  defp fighter_4(ruleset),
    do:
      build(ruleset, :human, List.duplicate(:fighter, 4), @fighter_abilities, %{
        1 => %{:general => :alertness, :racial => :iron_will, @bonus => :blind_fight},
        2 => %{@bonus => :dodge},
        3 => %{general: :lightning_reflexes},
        4 => %{@bonus => :mobility}
      })

  # Ровно то, что оставлял конструктор до задачи: эльф с Iron will в «Бонусе расы».
  defp elf_with_racial(ruleset) do
    %Build{} = human = human_wizard(ruleset)
    %Build{human | race: :elf}
  end

  # Воин 4 после смены 1-го уровня на волшебника до задачи — чистка только 1-го.
  defp shifted_fighter(ruleset) do
    %Build{} = edited = Build.replace_level(fighter_4(ruleset), 1, :wizard)
    %Build{edited | feats: Map.update!(edited.feats, 1, &Map.delete(&1, @bonus))}
  end

  defp open(conn, %Build{} = build, level),
    do: live(conn, ~p"/?b=#{Encoding.encode(build)}&l=#{level}")

  # Билд, который сейчас отдаёт «Скопировать ссылку», — из самого `#share-link`,
  # а не из того, что тест ожидает увидеть.
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

  defp prune_text(view, level, slot),
    do: render(element(view, "#feat-prune-#{level}-#{Ids.slot_dom_id(slot)}"))

  defp illegal_rows?(view), do: has_element?(view, "#level-ladder [data-illegal='1']")

  # ------------------------------------------------------------- правка: раса --

  describe "правка: человек с Iron will в расовом слоте стал эльфом" do
    test "пик снят, ⚠ нет, заметка называет снятое; общий пик на месте", %{
      conn: conn,
      ruleset: ruleset
    } do
      human = human_wizard(ruleset)
      assert Rules.illegal_feats(human, ruleset) == []

      {:ok, view, _html} = open(conn, human, 1)

      # До: расовый чип с пиком, заметки нет.
      assert has_element?(view, "#slot-chip-racial[data-filled='1']")
      refute has_element?(view, "#feat-prune")

      view |> element("#race-card-elf") |> render_click()

      # После: слота нет и пика нет — ни ⚠, ни чипа.
      refute illegal_rows?(view)
      refute has_element?(view, "#stage-nav-feats[data-illegal='1']")
      refute has_element?(view, "#slot-chip-racial")

      assert render(element(view, "#feat-prune")) =~ "Эти фиты сняты с билда:"

      assert prune_text(view, 1, :racial) =~
               "уровень 1: Iron will — этот уровень не даёт слота «Бонус расы»"

      # Билд и адрес — без Iron will; законное (Alertness в общем слоте) осталось.
      {code, %Build{} = shared} = shared(view)
      assert shared.race == :elf
      assert shared.feats == %{1 => %{general: :alertness}}
      assert_patch(view, "/?b=#{code}&l=1")

      # Число больше не держит Iron will: эльф с ним (как его оставлял
      # конструктор до задачи) на 2 Will выше того, что на экране.
      kept = Rules.compute(%Build{shared | feats: human.feats}, ruleset)
      assert Rules.compute(shared, ruleset).will == kept.will - 2
    end

    test "контроль: смена расы без расового пика не снимает ничего", %{
      conn: conn,
      ruleset: ruleset
    } do
      %Build{} = human = human_wizard(ruleset)
      human = %Build{human | feats: %{1 => %{general: :alertness}}}
      {:ok, view, _html} = open(conn, human, 1)

      view |> element("#race-card-elf") |> render_click()

      refute has_element?(view, "#feat-prune")
      assert {_code, %Build{feats: %{1 => %{general: :alertness}}}} = shared(view)
    end
  end

  # -------------------------------------------------- правка: класс 1-го уровня --

  describe "правка: воин 4, класс 1-го уровня → волшебник" do
    test "сняты пики 1-го и 4-го, пик 2-го остался; ⚠ нет", %{conn: conn, ruleset: ruleset} do
      fighter = fighter_4(ruleset)
      assert Rules.illegal_feats(fighter, ruleset) == []

      {:ok, view, _html} = open(conn, fighter, 1)
      refute has_element?(view, "#feat-prune")

      view |> element("#class-card-wizard") |> render_click()

      refute illegal_rows?(view)

      assert prune_text(view, 1, @bonus) =~
               "уровень 1: Blind fight — этот уровень не даёт слота «Бонус Fighter»"

      assert prune_text(view, 4, @bonus) =~
               "уровень 4: Mobility — этот уровень не даёт слота «Бонус Fighter»"

      refute has_element?(view, "#feat-prune-2-#{Ids.slot_dom_id(@bonus)}")

      {code, shared} = shared(view)
      assert_patch(view, "/?b=#{code}&l=1")
      assert shared.levels == [:wizard, :fighter, :fighter, :fighter]

      # Законное — на месте: общие и расовый пики, Dodge во 2-м (теперь 1-й
      # уровень Воина, бонусный слот с тем же id); 3-й получил пустой бонусный.
      assert shared.feats == %{
               1 => %{general: :alertness, racial: :iron_will},
               2 => %{@bonus => :dodge},
               3 => %{general: :lightning_reflexes}
             }

      assert Rules.illegal_feats(shared, ruleset) == []

      # 2-й уровень: чип с Dodge стоит.
      view |> element("#level-2") |> render_click()
      assert has_element?(view, "#slot-chip-#{Ids.slot_dom_id(@bonus)}[data-filled='1']")
    end

    test "заметка переживает переход по уровням и гаснет на правке без снятого", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = open(conn, fighter_4(ruleset), 1)
      view |> element("#class-card-wizard") |> render_click()
      assert has_element?(view, "#feat-prune")

      # Переход — не правка билда: заметка остаётся, снятое можно пойти выбрать.
      view |> element("#level-4") |> render_click()
      assert has_element?(view, "#feat-prune-4-#{Ids.slot_dom_id(@bonus)}")

      # Правка, которая ничего не сняла, — заметка гаснет, как сброс поинт-бая.
      view |> element("#level-1") |> render_click()
      view |> element("#alignment-lawful_neutral") |> render_click()
      refute has_element?(view, "#feat-prune")
    end

    # Правленый уровень чистился и до задачи (молча); теперь снятое названо.
    test "смена класса на самом уровне: бонусный пик этого уровня снят и назван", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = open(conn, fighter_4(ruleset), 4)
      view |> element("#class-card-wizard") |> render_click()

      assert prune_text(view, 4, @bonus) =~ "уровень 4: Mobility"
      refute has_element?(view, "#feat-prune-1-#{Ids.slot_dom_id(@bonus)}")

      {_code, shared} = shared(view)
      assert shared.levels == [:fighter, :fighter, :fighter, :wizard]
      refute Map.has_key?(shared.feats, 4)
      assert shared.feats[1][@bonus] == :blind_fight
    end
  end

  # ------------------------------------------------------------------ ссылка --

  describe "ссылка с пиком в слоте, которого уровень не даёт" do
    test "открытие: пик снят, флеш «Из ссылки выпало» называет его, ⚠ нет", %{
      conn: conn,
      ruleset: ruleset
    } do
      elf = elf_with_racial(ruleset)

      assert [{1, :racial, :iron_will, {:slot_not_granted, :racial}}] =
               Rules.illegal_feats(elf, ruleset)

      {:ok, view, _html} = open(conn, elf, 1)

      assert render(element(view, "#flash-info")) =~
               "Из ссылки выпало: уровень 1: Iron will — этот уровень не даёт слота «Бонус расы»"

      refute illegal_rows?(view)

      # Заметка — про правку; снятое из ссылки называет флеш.
      refute has_element?(view, "#feat-prune")

      # «Скопировать ссылку» — код того, что на экране, а не пришедший.
      clean = %Build{elf | feats: %{1 => %{general: :alertness}}}
      assert {code, ^clean} = shared(view)
      assert code == Encoding.encode(clean)
    end

    test "смена класса раннего уровня: снят пик 4-го, пик 2-го на месте", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = open(conn, shifted_fighter(ruleset), 4)

      flash = render(element(view, "#flash-info"))
      assert flash =~ "уровень 4: Mobility — этот уровень не даёт слота «Бонус Fighter»"
      refute flash =~ "Dodge"
      refute illegal_rows?(view)

      {_code, shared} = shared(view)
      assert shared.feats[2] == %{@bonus => :dodge}
      refute Map.has_key?(shared.feats, 4)
    end

    # Адрес переписывается, как у битой ссылки (3.228). На подключённом
    # монтировании патч приезжает в ответе на join, и `assert_patch/2` его
    # не видит по построению (`HANDOFF.md`, 3.228) — проверяется переходом
    # в живой сессии; на свежем открытии — значением `#share-link` выше.
    test "адрес переписывается на код того, что на экране", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = open(conn, human_wizard(ruleset), 1)

      elf = elf_with_racial(ruleset)
      html = render_patch(view, "/?b=#{Encoding.encode(elf)}&l=1")

      assert html =~ "Из ссылки выпало"
      clean = %Build{elf | feats: %{1 => %{general: :alertness}}}
      assert_patch(view, "/?b=#{Encoding.encode(clean)}&l=1")
    end

    test "контроль: ссылка без таких пиков открывается как пришла", %{
      conn: conn,
      ruleset: ruleset
    } do
      fighter = fighter_4(ruleset)
      {:ok, view, _html} = open(conn, fighter, 4)

      refute has_element?(view, "#flash-info")
      assert {code, ^fighter} = shared(view)
      assert code == Encoding.encode(fighter)
    end
  end
end
