defmodule BuildCalculatorWeb.BuildViewFiltersTest do
  @moduledoc """
  Пять чекбоксов «что показывать» на гиде экрана просмотра, плюс компактный
  список фитов внизу файла — задача 3.175, просьба Dan 03.09.2026 со
  скриншотом: у прокачанного вора гид превращается в стену — на каждом
  уровне по 5–7 строк навыков, за которыми не видно ни фитов, ни прибавок.

  Дословно: «надо нам ввести галочки в просмотре как минимум… хочешь узнать
  только статы, поднимаемые на каждом 4 уровне — поставил соответствующие
  чекбоксы и видишь только статы. Потом захотел только фиты — выставил
  чекбоксы и готово».

  Пять фильтров, а не три (Dan назвал скиллы/статы/фиты) — постановка сама
  называет это границей на обдумывание: «фильтры просят «полностью»», а
  «видишь ТОЛЬКО статы» неверно буквально, пока не гасятся ещё и заклинания,
  и разовый выбор класса (домены/школа) — иначе они остались бы висеть там,
  где по условию должны быть только статы.

  Образец устройства — `#view-granted-checkbox` (задача 3.147): состояние
  живёт в СОКЕТЕ, не в URL, и один клик не должен требовать перезагрузки
  страницы или менять адрес билда.
  """
  # ⚠️ `async: false` — последний тест меняет глобальный `Application.put_env/3`
  # (`:build_calculator, :guide_first`), тем же приёмом и по той же причине,
  # что `build_view_guide_test.exs`: параллельный сосед увидел бы чужой
  # порядок секций.
  use BuildCalculatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.Build

  setup do
    ruleset = Data.ruleset!()

    # Один билд, который на 1-м и 4-м уровнях персонажа несёт ВСЕ ПЯТЬ
    # фильтруемых полей `Summary.guide_rows/2` разом — так каждый чекбокс
    # проверяется на реальном, а не на синтетически урезанном билде:
    #
    #   уровень 1 (Cleric 1): фит, навык, заклинание, домены — четыре из пяти
    #   уровень 4 (Cleric 4): только прибавка к характеристике — пятое поле,
    #     И единственное содержимое уровня, поэтому выключение фильтра
    #     «Характеристики» обязано опустошить именно этот уровень целиком.
    #
    # ⚠️ Заклинание на 1-м уровне клирика — не проверка легальности спелл-
    # каста (её тут никто не считает), а данные для строки `row.spells`:
    # `Summary.guide_rows/2` читает `build.spells[level]` буквально, без
    # опроса ruleset'а о том, кому такая запись «положена» по правилам, —
    # тот же приём, каким и другие тесты гида (`build_view_live_test.exs`,
    # «a known spell is a line of the guide») кладут заклинание любому классу.
    build =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :lawful_good,
        levels: List.duplicate(:cleric, 4),
        class_choices: %{cleric: [:air, :war]},
        feats: %{1 => %{general: :toughness}},
        skills: %{1 => %{discipline: 4}},
        spells: %{1 => %{{:circle, 1, 0} => :magic_missile}},
        ability_increases: %{4 => :wis}
      )

    %{ruleset: ruleset, build: build, code: Encoding.encode(build)}
  end

  describe "умолчание — всё включено" do
    test "все пять чекбоксов отмечены, и весь контент виден", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      for key <- ~w(feats increase skills spells domains) do
        assert has_element?(view, "#view-filter-#{key}-checkbox[checked]"),
               "чекбокс #{key} обязан быть отмечен по умолчанию"
      end

      level1 = render(element(view, "#view-guide-level-1"))
      assert level1 =~ "Toughness"
      assert level1 =~ "Discipline"
      assert level1 =~ "Magic missile"
      assert level1 =~ "Air"
      assert level1 =~ "War"

      assert render(element(view, "#view-guide-level-4")) =~ "WIS"
      refute has_element?(view, "#view-guide-level-4[data-empty='1']")
    end
  end

  describe "каждый фильтр гасит СВОЙ разряд и ничего больше" do
    test "«Фиты» прячет фит, но не навык/заклинание/домены на том же уровне", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      view |> element("#view-filter-feats-checkbox") |> render_click()

      level1 = render(element(view, "#view-guide-level-1"))
      refute level1 =~ "Toughness"
      assert level1 =~ "Discipline"
      assert level1 =~ "Magic missile"
      assert level1 =~ "Air"

      # Уровень не опустел целиком — по-прежнему есть что показывать.
      refute has_element?(view, "#view-guide-level-1[data-empty='1']")

      refute render(element(view, "#view-guide-legend")) =~ "фит выбран"
    end

    test "«Характеристики» прячет ▲ и опустошает 4-й уровень целиком", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      refute has_element?(view, "#view-guide-level-4[data-empty='1']")

      view |> element("#view-filter-increase-checkbox") |> render_click()

      refute render(element(view, "#view-guide-level-4")) =~ "WIS"

      # На 4-м уровне этого билда прибавка — ЕДИНСТВЕННОЕ содержимое, поэтому
      # выключение фильтра обязано превратить строку в «нечего выбирать» —
      # тот же прочерк и то же утончение, что у по-настоящему пустого уровня
      # (`nothing_to_choose?/2`, build_view_live.ex).
      assert has_element?(view, "#view-guide-level-4[data-empty='1']")
      assert render(element(view, "#view-guide-level-4")) =~ "—"

      refute render(element(view, "#view-guide-legend")) =~ "к характеристике"
    end

    test "«Навыки» прячет ▪, но не соседей на том же уровне", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      view |> element("#view-filter-skills-checkbox") |> render_click()

      level1 = render(element(view, "#view-guide-level-1"))
      refute level1 =~ "Discipline"
      assert level1 =~ "Toughness"
      assert level1 =~ "Magic missile"

      refute render(element(view, "#view-guide-legend")) =~ "навык"
    end

    test "«Заклинания» прячет круг+имя, но не соседей", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      view |> element("#view-filter-spells-checkbox") |> render_click()

      level1 = render(element(view, "#view-guide-level-1"))
      refute level1 =~ "Magic missile"
      assert level1 =~ "Toughness"
      assert level1 =~ "Discipline"

      refute render(element(view, "#view-guide-legend")) =~ "круг заклинания"
    end

    test "«Выбор класса» прячет домены, но не соседей", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      view |> element("#view-filter-domains-checkbox") |> render_click()

      refute has_element?(view, "#view-guide-level-1-domains")
      level1 = render(element(view, "#view-guide-level-1"))
      assert level1 =~ "Toughness"
      assert level1 =~ "Discipline"

      refute render(element(view, "#view-guide-legend")) =~ "выбор класса"
    end
  end

  describe "«видишь только статы» — Dan'а собственный пример" do
    test "выключить всё, кроме характеристик — 1-й уровень пустеет, 4-й нет", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      for key <- ~w(feats skills spells domains) do
        view |> element("#view-filter-#{key}-checkbox") |> render_click()
      end

      # 1-й уровень нёс только эти четыре — теперь ему нечего показать.
      assert has_element?(view, "#view-guide-level-1[data-empty='1']")
      refute render(element(view, "#view-guide-level-1")) =~ "Toughness"
      refute render(element(view, "#view-guide-level-1")) =~ "Discipline"
      refute render(element(view, "#view-guide-level-1")) =~ "Magic missile"

      # Номер уровня остаётся — findability по номеру НЕ теряется (постановка
      # прямо предупреждает: «скрывать строку целиком опасно»).
      assert has_element?(view, "#view-guide-level-1 a[href='#view-guide-level-1']")

      # А 4-й уровень как раз про характеристику — он единственный, где что-то
      # ещё видно.
      assert render(element(view, "#view-guide-level-4")) =~ "WIS"
      refute has_element?(view, "#view-guide-level-4[data-empty='1']")
    end
  end

  describe "состояние живёт в сокете, а не в URL" do
    test "свежий заход по той же ссылке снова открывается с умолчанием", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")
      view |> element("#view-filter-skills-checkbox") |> render_click()
      refute render(element(view, "#view-guide-level-1")) =~ "Discipline"

      # Новый процесс LiveView по ТОЙ ЖЕ ссылке — если бы состояние кодировалось
      # в адресе или в query, второй заход унаследовал бы выключенный фильтр.
      {:ok, view2, html2} = live(conn, ~p"/b/#{code}")
      assert html2 =~ "Discipline"
      assert has_element?(view2, "#view-filter-skills-checkbox[checked]")
    end
  end

  describe "список фитов внизу (`#view-feats`)" do
    test "показывает взятые фиты по именам, со счётчиком и легендой", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert render(element(view, "#view-feats-count")) =~ "Фиты — 1"
      assert render(element(view, "#view-feat-1-0-toughness")) =~ "Toughness"
      assert has_element?(view, "#view-feats-legend")
    end

    # ⚠️ Список — про ВЗЯТЫЕ фиты («берущихся», слово Dan), а не про все:
    # выданное классом сюда не идёт (решение 3.175, тот же довод, что уже
    # отверг общий счётчик у старой переписи фитов, CLAUDE.md §6).
    test "выданные классом фиты в список НЕ попадают", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: [:ranger]
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      # Ranger 1-го уровня выдаёт СЕМЬ фитов классом (включая Toughness —
      # CLAUDE.md §3, «Ranger получает бонусный фит и на 1-м уровне»), но не
      # кладёт слотом ни одного — проверено вызовом `Feats.granted_named/3`
      # при написании теста. Значит «Фиты — 0» здесь не вырожденный случай
      # пустого билда, а настоящая проверка: билд полон фитов, список внизу
      # честно молчит про все семь, потому что ни один не взят слотом.
      assert render(element(view, "#view-feats-count")) =~ "Фиты — 0"
      assert render(element(view, "#view-feats-list")) =~ "Фитов пока нет."
    end

    # Фильтры гида — про строки ГИДА; список внизу — второе, отдельное
    # решение той же проблемы («в целом чекбоксы решат данную проблему, но
    # раз попросили можно и отдельно список фитов добавить»), и одно не
    # должно опустошать другое.
    test "фильтры гида НЕ трогают список фитов внизу", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      view |> element("#view-filter-feats-checkbox") |> render_click()

      assert render(element(view, "#view-feats-count")) =~ "Фиты — 1"
      assert render(element(view, "#view-feat-1-0-toughness")) =~ "Toughness"
    end

    test "список стоит ПОСЛЕДНИМ на странице при обоих положениях флага guide_first?", %{
      conn: conn,
      code: code
    } do
      on_exit(fn -> Application.put_env(:build_calculator, :guide_first, true) end)

      {:ok, view, _html} = live(conn, ~p"/b/#{code}")
      assert has_element?(view, "#view-picks ~ #view-feats")

      Application.put_env(:build_calculator, :guide_first, false)
      {:ok, view2, _html2} = live(conn, ~p"/b/#{code}")
      assert has_element?(view2, "#view-picks ~ #view-feats")
      assert has_element?(view2, "#view-guide ~ #view-feats")
    end
  end
end
