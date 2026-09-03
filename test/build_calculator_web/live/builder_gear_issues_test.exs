defmodule BuildCalculatorWeb.BuilderGearIssuesTest do
  @moduledoc """
  Сводка предупреждений «Вещей» — задача 3.133, замечание 2.

  Dan, 28.08.2026: «у меня был выбран щит и это не помешало мне выбрать
  второе оружие. Щит перестал считаться… не очень понятно, что именно щит
  не работает, для этого надо лезть в итоговые цифры» → «блокировать не
  обязательно, просто предупреждение более явно выводить… можно где-то
  сверху в одном месте выводить все вонинги один за одним списком».

  Три вещи проверяются здесь: сама сводка (`GearPanel.gear_issues/2`,
  `#gear-issues`) как ТРЕТИЙ список — не дубль `#builder-notice` и не дубль
  «N пробелов в этом билде»; клик по находке открывает «Вещи» и подводит
  экран к контролу (`jump_to_gear_issue`, `#scroll-bus`); и зеркальная
  пометка на СТОРОНЕ ОРУЖИЯ («на обе стороны конфликта» — раньше сообщение
  висело только на щите).

  ⚠️ Разбросанные отметки (`gear-worn-illegal-*`, `gear-weapon-bad`,
  `gear-off-weapon-bad`, все `*-capped`) уже покрыты `builder_off_hand_
  weapon_test.exs`, `builder_gear_weapon_test.exs` и `builder_live_test.exs`
  — здесь их текст не переоткрывается, только то, что сводка ведёт к ним
  точным DOM-id.
  """

  use BuildCalculatorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.{Build, Gear}

  setup do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  defp open(conn, build), do: live(conn, ~p"/?b=#{Encoding.encode(build)}")

  # Воин 20 с обоими сиальскими владениями (клинковым и молотами) в
  # бонусных слотах — та же фикстура, что уже проверяет ядро дуал-вилда
  # (`dual_wield_test.exs`) и сам блок второй руки (`builder_off_hand_
  # weapon_test.exs`), чтобы билд был узнаваемым между файлами.
  defp dual_wield_build(ruleset, fields) do
    Build.new(
      [
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: List.duplicate(:fighter, 20),
        base_abilities: %{str: 18, dex: 14, con: 14, int: 10, wis: 10, cha: 10},
        feats: %{
          1 => %{
            :general => :siala_blade_proficiency,
            {:class_bonus, :fighter} => :siala_hammer_proficiency
          }
        }
      ] ++ fields
    )
  end

  describe "нет проблем — блока нет вовсе (задача 3.88: тот же приём ворот)" do
    test "пустые «Вещи» не рисуют сводку", %{conn: conn, ruleset: ruleset} do
      build = dual_wield_build(ruleset, gear: Gear.new(weapon: :katana))
      {:ok, view, _html} = open(conn, build)

      refute has_element?(view, "#gear-issues")
    end

    test "билд без единого уровня — тоже без сводки", %{conn: conn, ruleset: ruleset} do
      build = Build.new(ruleset_version: ruleset.version, levels: [])
      {:ok, view, _html} = open(conn, build)

      refute has_element?(view, "#gear-issues")
    end
  end

  describe "щит вытеснен второй рукой — разряд «не считается»" do
    setup %{ruleset: ruleset} do
      build =
        dual_wield_build(ruleset,
          gear: Gear.new(weapon: :katana, off_hand_weapon: :mace, worn: %{shield: :large})
        )

      %{build: build}
    end

    test "сводка называет находку меткой «не считается», а не «срезано потолком»", %{
      conn: conn,
      build: build
    } do
      {:ok, view, _html} = open(conn, build)

      assert has_element?(view, "#gear-issues")
      assert render(element(view, "#gear-issues-title")) =~ "1"
      assert has_element?(view, "#gear-issues-refused")
      refute has_element?(view, "#gear-issues-capped")

      text = render(element(view, "#gear-issue-refused-worn-shield-large"))
      assert text =~ "не считается"
      refute text =~ "срезано потолком"

      # То же самое, что уже печатает `#gear-worn-illegal-shield-large` —
      # сводка не изобретает свой текст, а составляет его из тех же полей.
      assert text =~ "Large shield"
      assert text =~ "Mace занимает вторую руку"
    end

    # 🔴 Главный контракт замечания 2: клик по находке ОТКРЫВАЕТ «Вещи»
    # (если свёрнуты) и подводит экран к СЕЛЕКТУ щита, а не просто листает
    # страницу — иначе клик по сводке в свёрнутых «Вещах» бил бы в пустоту.
    test "клик открывает «Вещи» и ведёт к селекту щита", %{conn: conn, build: build} do
      {:ok, view, _html} = open(conn, build)

      refute has_element?(view, "#gear-body")

      view |> element("#gear-issue-refused-worn-shield-large") |> render_click()

      assert has_element?(view, "#gear-body")
      assert has_element?(view, "#gear-worn-input-shield")
      assert_push_event(view, "scroll_to_section", %{id: "gear-worn-input-shield"})
    end

    # Повторный клик — снова открыть и снова подвезти (не toggle): сводка
    # всегда хочет ПОКАЗАТЬ, а не переключить состояние блока.
    test "повторный клик не закрывает уже открытые «Вещи»", %{conn: conn, build: build} do
      {:ok, view, _html} = open(conn, build)

      view |> element("#gear-issue-refused-worn-shield-large") |> render_click()
      assert has_element?(view, "#gear-body")

      view |> element("#gear-issue-refused-worn-shield-large") |> render_click()
      assert has_element?(view, "#gear-body")
      assert_push_event(view, "scroll_to_section", %{id: "gear-worn-input-shield"})
    end

    # 🔴 «На обе стороны конфликта» (задача 3.133): раньше сообщение висело
    # ТОЛЬКО на щите (`gear-worn-illegal-shield-large`) — Dan наткнулся на
    # пропажу щита именно в момент выбора второго оружия, а не на щите.
    test "зеркальная пометка стоит у самого оружия второй руки", %{conn: conn, build: build} do
      {:ok, view, _html} = open(conn, build)

      view |> element("#gear-toggle") |> render_click()

      # Существующая отметка на щите остаётся на месте (граница 1: не убирать).
      assert has_element?(view, "#gear-worn-illegal-shield-large")

      assert render(element(view, "#gear-worn-illegal-shield-large")) =~
               "Large shield в расчёт не идёт: Mace занимает вторую руку."

      # И у ВТОРОЙ РУКИ теперь тоже есть пометка — та же причина другими
      # словами, у ДРУГОГО органа управления.
      assert has_element?(view, "#gear-off-weapon-blocks-worn")

      assert render(element(view, "#gear-off-weapon-blocks-worn")) =~
               "Large shield в расчёт не идёт."

      # Главная рука (катана) щит не трогает — пометки у неё нет.
      refute has_element?(view, "#gear-weapon-blocks-worn")
    end

    # Положительный контроль к предыдущему: без конфликта пометки нет
    # ни у одной руки.
    test "без конфликта зеркальной пометки нет ни у одной руки", %{conn: conn, ruleset: ruleset} do
      build = dual_wield_build(ruleset, gear: Gear.new(weapon: :katana, off_hand_weapon: :mace))
      {:ok, view, _html} = open(conn, build)

      view |> element("#gear-toggle") |> render_click()

      refute has_element?(view, "#gear-off-weapon-blocks-worn")
      refute has_element?(view, "#gear-weapon-blocks-worn")
      refute has_element?(view, "#gear-issues")
    end
  end

  describe "двуручное оружие вытесняет щит — то же обращение (задача 3.43/3.132)" do
    test "зеркальная пометка стоит у оружия ГЛАВНОЙ руки", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :true_neutral,
          levels: List.duplicate(:fighter, 20),
          base_abilities: %{str: 18, dex: 14, con: 14, int: 10, wis: 10, cha: 10},
          feats: %{1 => %{general: :siala_blade_proficiency}},
          gear: Gear.new(weapon: :greatsword, worn: %{shield: :large})
        )

      {:ok, view, _html} = open(conn, build)
      view |> element("#gear-toggle") |> render_click()

      assert has_element?(view, "#gear-weapon-blocks-worn")

      assert render(element(view, "#gear-weapon-blocks-worn")) =~
               "Large shield в расчёт не идёт."

      # Сводка та же самая — «не считается» с той же целью, селект щита.
      assert has_element?(view, "#gear-issue-refused-worn-shield-large")
    end
  end

  describe "оружие без владения — тоже разряд «не считается»" do
    test "булава во второй руке без фита владения молотами", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :true_neutral,
          levels: List.duplicate(:fighter, 20),
          base_abilities: %{str: 18, dex: 14, con: 14, int: 10, wis: 10, cha: 10},
          feats: %{1 => %{general: :siala_blade_proficiency}},
          gear: Gear.new(weapon: :katana, off_hand_weapon: :mace)
        )

      {:ok, view, _html} = open(conn, build)

      assert has_element?(view, "#gear-issues-refused")
      assert has_element?(view, "#gear-issue-refused-gear-off-weapon")

      text = render(element(view, "#gear-issue-refused-gear-off-weapon"))
      assert text =~ "Mace"
      assert text =~ "Владение молотами"

      view |> element("#gear-issue-refused-gear-off-weapon") |> render_click()

      assert has_element?(view, "#gear-body")
      assert_push_event(view, "scroll_to_section", %{id: "gear-off-weapon"})
    end
  end

  describe "срез потолком — разряд «срезано потолком»" do
    setup %{ruleset: ruleset} do
      build =
        dual_wield_build(ruleset,
          gear:
            Gear.new(
              weapon: :katana,
              off_hand_weapon: :mace,
              abilities: %{str: 99},
              saves: 99,
              weapon_attack: 99,
              off_hand_weapon_attack: 99
            )
        )

      %{build: build}
    end

    test "сводка называет каждый срез меткой «срезано потолком», без «не считается»", %{
      conn: conn,
      build: build
    } do
      {:ok, view, _html} = open(conn, build)

      refute has_element?(view, "#gear-issues-refused")
      assert has_element?(view, "#gear-issues-capped")

      text = render(element(view, "#gear-issues-capped"))
      assert text =~ "срезано потолком"
      refute text =~ "не считается"

      assert has_element?(view, "#gear-issue-capped-abilities")
      assert has_element?(view, "#gear-issue-capped-saves")
      assert has_element?(view, "#gear-issue-capped-weapon")
      assert has_element?(view, "#gear-issue-capped-off-weapon")
    end

    test "клик по срезу сейвов ведёт к своему полю", %{conn: conn, build: build} do
      {:ok, view, _html} = open(conn, build)

      view |> element("#gear-issue-capped-saves") |> render_click()

      assert has_element?(view, "#gear-body")
      assert_push_event(view, "scroll_to_section", %{id: "gear-saves-capped"})
    end

    test "клик по срезу AB второй руки ведёт к СВОЕМУ полю, не к главной руке", %{
      conn: conn,
      build: build
    } do
      {:ok, view, _html} = open(conn, build)

      view |> element("#gear-issue-capped-off-weapon") |> render_click()

      assert_push_event(view, "scroll_to_section", %{id: "gear-off-weapon-capped"})
    end
  end

  describe "срез по типу AC и по навыку — свой пункт на каждую строку" do
    test "уклонение (AC) и навык, срезанные потолком, — обе своя запись со своей целью", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 20),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          gear: Gear.new(ac: %{dodge: 999}, skills: %{discipline: 999})
        )

      {:ok, view, _html} = open(conn, build)

      assert has_element?(view, "#gear-issue-capped-ac-dodge")
      assert has_element?(view, "#gear-issue-capped-skill-discipline")

      view |> element("#gear-issue-capped-ac-dodge") |> render_click()
      assert_push_event(view, "scroll_to_section", %{id: "gear-ac-capped-dodge"})

      view |> element("#gear-issue-capped-skill-discipline") |> render_click()
      assert_push_event(view, "scroll_to_section", %{id: "gear-skill-capped-discipline"})
    end
  end

  describe "третий список — не дубль двух существующих (задача 3.133, граница 3)" do
    test "«Проблемы в вещах», «N пробелов в этом билде» и данные — три разных числа", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Билд без расы/мировоззрения несёт СВОИ пробелы (раса не выбрана и
      # т.п.) через `#gaps-panel`, а «Вещи» здесь чисты — сводка не рисуется
      # вовсе, и оба списка не путаются друг с другом ни в одну, ни в другую
      # сторону.
      build =
        Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:fighter, 5))

      {:ok, view, _html} = open(conn, build)

      refute has_element?(view, "#gear-issues")
      assert has_element?(view, "#gaps-build-count")

      # Билд с проблемами В ВЕЩАХ — сводка появляется, а «N пробелов
      # в этом билде» продолжает отвечать за СВОЙ, другой вопрос (сегодня
      # у обоих ruleset'ов это только расовый бонус/бонус оружия ниже
      # 40-го уровня — задача 3.12/3.35 — и сводка их не пересказывает).
      dual =
        dual_wield_build(ruleset,
          gear: Gear.new(weapon: :katana, off_hand_weapon: :mace, worn: %{shield: :large})
        )

      {:ok, view2, _html} = open(conn, dual)

      assert has_element?(view2, "#gear-issues")
      refute render(element(view2, "#gear-issues")) =~ "пробелов"
    end
  end

  # Проверка координатора 28.08.2026 (живой Chrome, 1440×900) нашла, что две
  # находки из трёх сводки уводили экран мимо цели. Живая перепроверка тем же
  # методом (клик + `getBoundingClientRect().top`, headless Chrome по CDP,
  # `Emulation.setDeviceMetricsOverride`) на ТЕКУЩЕМ коде НЕ подтвердила это
  # на десктопе 1440×900 — все три находки, кликнутые и измеренные ПО
  # ОДНОЙ (со свежей навигацией на каждую), попадают в `top ≈ 0` что через
  # `.click()`, что через настоящий клик мышью по актуальным координатам.
  # Симптом координатора («−271 / −384», общая осевшая точка контейнера)
  # воспроизводится ТОЛЬКО двумя способами, и оба — не про геометрию
  # `scrollIntoView`, а про то, КАК был получен клик: (а) настоящий клик по
  # координатам, вычисленным ДО того, как предыдущий клик увёл кнопку
  # за пределы экрана (клик по невидимой точке не долетает до кнопки
  # вовсе), и (б) несколько находок кликаются подряд БЕЗ ожидания оседания
  # предыдущей анимации — тогда побеждает ПОСЛЕДНИЙ клик (и побеждает
  # корректно — именно его цель в итоге стоит на месте), а более ранние
  # остаются там, где их застал более поздний запрос. Это стандартное
  # поведение конкурирующих `scrollIntoView({behavior:"smooth"})`, а не
  # дефект: единичный клик по КАЖДОЙ находке (тот метод, которым просит
  # проверять сама постановка) ни разу не промахнулся ни в одном заходе.
  #
  # ✅ Настоящий, воспроизводимый дефект нашёлся не в геометрии, а
  # в СОСТОЯНИИ — и только на узких раскладках (`< 940px`, CLAUDE.md §6):
  # там «Итого» — ЕЩЁ ОДНА шторка, `#totals-panel[data-open]`, отдельная
  # от `gear_open?` и живущая ЦЕЛИКОМ на клиенте (`#sheet-toggle`
  # переключает её собственной JS-командой, сервер о её состоянии не
  # знает вовсе). `jump_to_gear_issue` трогал только `gear_open?` —
  # счёт был верным (`scrollTop` контейнера действительно уезжал куда
  # нужно), но сама шторка оставалась свёрнутой, и прокрутка проходила
  # НЕВИДИМО, в полосе высотой `--sheet-h` (~88px) под кнопкой-сводкой
  # чисел. Замер headless Chrome (`mobile: true`, 390×844) со скриншотом
  # до/после клика подтвердил: контейнер после клика показывает обрывок
  # строки щита в ТОЙ ЖЕ свёрнутой полосе, где секунду назад стояли
  # HP/AC/AB, — сама шторка не разворачивается.
  #
  # Правка — `BuilderLive.gear_issue_jump/1`: `phx-click` обеих кнопок
  # сводки несёт теперь не голое имя события, а `JS.push/2`
  # (тот же server round-trip) плюс два `JS.set_attribute/3`, безусловно
  # открывающих `#totals-panel`/`#sheet-toggle`. На десктопе у этих
  # атрибутов нет соответствующего CSS-правила вовсе (`.stats[data-open]`
  # живёт только внутри `@media (max-width: 940px)`), так что команда там
  # безвредна. Тесты ниже проверяют то, что `Phoenix.LiveViewTest` МОЖЕТ
  # проверить, не запуская браузер, — присутствие правильно нацеленной
  # JS-команды в атрибуте; сам клиентский эффект (шторка правда
  # разворачивается) проверен живым Chrome, а не ExUnit.
  describe "мобильная шторка «Итого» тоже открывается кликом — хвост задачи 3.134" do
    setup %{ruleset: ruleset} do
      build =
        dual_wield_build(ruleset,
          gear:
            Gear.new(
              weapon: :katana,
              off_hand_weapon: :mace,
              worn: %{shield: :large},
              saves: 99
            )
        )

      %{build: build}
    end

    test "кнопка разряда «не считается» несёт команду разворота шторки", %{
      conn: conn,
      build: build
    } do
      {:ok, view, _html} = open(conn, build)

      html = view |> element("#gear-issue-refused-worn-shield-large") |> render()

      assert html =~ "jump_to_gear_issue"
      assert html =~ "gear-worn-input-shield"
      assert html =~ "#totals-panel"
      assert html =~ "data-open"
      assert html =~ "#sheet-toggle"
      assert html =~ "aria-expanded"
    end

    test "кнопка разряда «срезано потолком» несёт ту же команду", %{conn: conn, build: build} do
      {:ok, view, _html} = open(conn, build)

      html = view |> element("#gear-issue-capped-saves") |> render()

      assert html =~ "jump_to_gear_issue"
      assert html =~ "gear-saves-capped"
      assert html =~ "#totals-panel"
      assert html =~ "data-open"
      assert html =~ "#sheet-toggle"
      assert html =~ "aria-expanded"
    end

    # Положительный контроль: сам server round-trip (`push`) не сломан этой
    # правкой — `render_click` на LiveViewTest выполняет `push`-операцию
    # JS-команды тем же способом, что и голый `phx-click`, поэтому уже
    # существующие тесты выше это покрывают, а это — явное подтверждение
    # рядом с новыми, чтобы никто не спутал «несёт команду» с «команда
    # работает».
    test "клик по кнопке всё ещё доезжает до сервера и открывает «Вещи»", %{
      conn: conn,
      build: build
    } do
      {:ok, view, _html} = open(conn, build)

      refute has_element?(view, "#gear-body")

      view |> element("#gear-issue-capped-saves") |> render_click()

      assert has_element?(view, "#gear-body")
      assert_push_event(view, "scroll_to_section", %{id: "gear-saves-capped"})
    end
  end
end
