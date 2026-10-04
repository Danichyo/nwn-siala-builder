defmodule BuildCalculatorWeb.BuilderGearFeatStackTest do
  @moduledoc """
  Степпер повторных взятий у фита с вещи — задачи 3.204 (часть B) и 3.224.

  Ядро (часть A, `c4b20bc`) уже умеет `Gear.add_feat/3`/`remove_feat/3`,
  `GearFeats.stackable?/2`/`max_takes/2`/`add_reasons/3` — здесь проверяется
  только то, что интерфейс этим пользуется: строка со счётчиком вместо
  списка записей, «+»/«−» вместо единственного «×», и что счёт сходится
  с тем, что печатает игра на билде самого Dan.

  Задача 3.224 добавила сюда второй вид того же счётчика — по ЗНАЧЕНИЮ
  (`Epic energy resistance (Fire) ×2`): пара, объявленная дважды, законна
  с 3.210 и до этой задачи рисовалась двумя чипами с одним DOM-id.

  Файл отдельный от `builder_gear_feats_test.exs` — тот проверяет форму
  «слот/выбор/снятие» вообще, этот — только развилку «повторяется / нет»,
  которой до 3.204 не существовало.
  """

  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.{Build, Gear}

  defp fixture_code do
    [File.cwd!(), "test/fixtures/dan_build_2026-09-13.code"]
    |> Path.join()
    |> File.read!()
    |> String.trim()
  end

  # Билд, у которого пара с вещи стоит `takes` раз — ровно то, что приходит
  # импортом `.билд+` со ступенями (`Epic Energy Resistance II`+`III`) или
  # уже расшаренной ссылкой.
  defp pair_code(takes, extra \\ []) do
    ruleset = Data.ruleset!("siala_41")

    build =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: List.duplicate(:fighter, 21),
        base_abilities: %{str: 14, dex: 12, con: 14, int: 10, wis: 10, cha: 8},
        gear: Gear.new(feats: List.duplicate({:epic_energy_resistance, :fire}, takes) ++ extra)
      )

    Encoding.encode(build)
  end

  defp open_gear(view) do
    view |> element("#gear-toggle") |> render_click()
    view
  end

  defp open_picker(view) do
    view |> open_gear() |> element("#gear-feat-add-toggle") |> render_click()
    view
  end

  defp search(view, query) do
    view |> element("#gear-feat-search-form") |> render_change(%{"q" => query})
    view
  end

  # Подпись «уже отмечено» у строки списка выбора, текстом без разметки:
  # у неё три вида (задача 3.226), и различить их можно только ТОЧНЫМ
  # сравнением — «✓ надет» лежит подстрокой внутри «✓ надет · ещё значение»,
  # так что `=~` пропустил бы ровно тот дефект, который 3.226 и чинит.
  defp pick_label(view, id) do
    view
    |> element("#gear-pick-#{id} .gear-pick-on")
    |> render()
    |> String.replace(~r{<[^>]*>}, "")
    |> String.trim()
  end

  describe "билд Dan: 1437 → 1470 → 1503, степпером" do
    test "первое взятие с пик-листа, второе степпером — HP сходится с игрой", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{fixture_code()}")

      refute render(element(view, "#stat-hp")) =~ "1470"

      view |> open_picker() |> search("epic toughness")
      view |> element("#gear-pick-epic_toughness") |> render_click()

      assert has_element?(view, "#gear-feat-epic_toughness")
      assert render(element(view, "#gear-feat-count-epic_toughness")) =~ "×1"
      assert render(element(view, "#stat-hp")) =~ "1470"

      view |> element("#gear-feat-more-epic_toughness") |> render_click()

      assert render(element(view, "#gear-feat-count-epic_toughness")) =~ "×2"
      assert render(element(view, "#stat-hp")) =~ "1503"

      view |> element("#gear-feat-less-epic_toughness") |> render_click()

      assert render(element(view, "#gear-feat-count-epic_toughness")) =~ "×1"
      assert render(element(view, "#stat-hp")) =~ "1470"
    end

    test "потолок из данных виден рядом со счётчиком: «×2 из 10»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{fixture_code()}")

      view |> open_picker() |> search("epic toughness")
      view |> element("#gear-pick-epic_toughness") |> render_click()
      view |> element("#gear-feat-more-epic_toughness") |> render_click()

      assert render(element(view, "#gear-feat-count-epic_toughness")) =~ "×2 из 10"
    end

    # 3.205 (дизайнерский проход): строка стакающегося фита в списке выбора
    # обязана отличаться от нестакающегося — у того повторный клик СНИМАЕТ,
    # у этого ДОБАВЛЯЕТ взятие. Здесь стояло статичное «✓ надет» компонента
    # `pick_list/1` на обоих; теперь у стакающегося — «надето ×N · ещё раз»,
    # тем же словом, что у слотовых фитов на сцене («взят ×2 · ещё раз»).
    test "в списке выбора стакающийся фит подписан «надето ×N · ещё раз», а не «✓ надет»", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{fixture_code()}")

      view |> open_picker() |> search("epic toughness")
      view |> element("#gear-pick-epic_toughness") |> render_click()
      assert render(element(view, "#gear-pick-epic_toughness")) =~ "надето ×1 · ещё раз"

      view |> element("#gear-feat-more-epic_toughness") |> render_click()
      assert render(element(view, "#gear-pick-epic_toughness")) =~ "надето ×2 · ещё раз"
      refute render(element(view, "#gear-pick-epic_toughness")) =~ "✓ надет"
    end

    test "десятое взятие блокирует «+» с причиной потолка", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{fixture_code()}")

      view |> open_picker() |> search("epic toughness")
      view |> element("#gear-pick-epic_toughness") |> render_click()

      view =
        Enum.reduce(1..9, view, fn _n, view ->
          view |> element("#gear-feat-more-epic_toughness") |> render_click()
          view
        end)

      assert render(element(view, "#gear-feat-count-epic_toughness")) =~ "×10 из 10"
      assert has_element?(view, "#gear-feat-more-epic_toughness[disabled]")
      assert render(element(view, "#gear-feat-more-why-epic_toughness")) =~ "больше 10 раз нельзя"

      # Кнопка задизаблена в разметке, но `handle_event("gear_feat_more", …)`
      # обязан проверять потолок САМ — правленая руками форма прислала бы
      # событие и без атрибута `disabled`. `render_click/3` без DOM-элемента
      # шлёт событие напрямую, тем же путём.
      render_click(view, "gear_feat_more", %{"feat" => "epic_toughness"})
      assert render(element(view, "#gear-feat-count-epic_toughness")) =~ "×10 из 10"
    end

    test "ссылка после правок декодируется в те же записи", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{fixture_code()}")

      # ⚠️ `assert_patch/1` разбирает СВОЮ почту в порядке FIFO: не осушив её
      # после первого клика, второй `assert_patch/1` вернул бы ссылку ПЕРВОГО
      # взятия, а не второго.
      view |> open_picker() |> search("epic toughness")
      view |> element("#gear-pick-epic_toughness") |> render_click()
      assert_patch(view)
      view |> element("#gear-feat-more-epic_toughness") |> render_click()

      path = assert_patch(view)
      {:ok, shared, _html} = live(conn, path)

      open_gear(shared)

      assert render(element(shared, "#gear-feat-count-epic_toughness")) =~ "×2"
      assert render(element(shared, "#stat-hp")) =~ "1503"
    end
  end

  describe "нестакающийся фит — поведение прежнее" do
    test "клик по уже объявленному в пик-листе снимает, а не добавляет", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{fixture_code()}")

      view |> open_picker() |> search("cleave")
      view |> element("#gear-pick-cleave") |> render_click()
      assert has_element?(view, "#gear-feat-cleave")

      # У нестакающегося фита нет своего степпера вовсе.
      refute has_element?(view, "#gear-feat-more-cleave")
      refute has_element?(view, "#gear-feat-less-cleave")

      view |> element("#gear-pick-cleave") |> render_click()
      refute has_element?(view, "#gear-feat-cleave")
    end
  end

  # ---------------------------------------------------- задача 3.224 --
  #
  # 🔴 До правки этот describe падал целиком, и падал САМ: у
  # `Phoenix.LiveViewTest` дубль DOM-id — исключение, а не предупреждение
  # («Duplicate id found while testing LiveView: gear-feat-entry-
  # epic_energy_resistance-fire»). Живьём (замер координатора, CDP) это
  # выглядело так: два одинаковых чипа, «Multiple IDs detected» в консоли,
  # и после клика «×» сервер взятие снимал (Fire 145 → 130), а патч по дублю
  # не применялся — экран оставался с фитом, которого в билде нет.
  describe "пара, взятая дважды: один чип со счётчиком" do
    test "две записи одной пары — одна строка, без дублей id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{pair_code(2)}")

      view |> element("#gear-toggle") |> render_click()

      assert has_element?(view, "#gear-feat-entry-epic_energy_resistance-fire")

      assert render(element(view, "#gear-feat-count-epic_energy_resistance-fire")) =~
               "×2 из 10"

      # Взятий два, значит и поглощение двойное (`Rules.Resistances`, 3.210).
      assert render(element(view, "#stat-resist-fire")) =~ "30"
    end

    # ⚠️ Строка значения ведёт себя как строка `Epic toughness`, а не как чип:
    # «×» у неё нет вовсе, последний «−» убирает значение целиком.
    test "«−» снимает одно взятие, второй — значение целиком", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{pair_code(2)}")

      view |> element("#gear-toggle") |> render_click()
      refute has_element?(view, "#gear-feat-drop-epic_energy_resistance-fire")

      view |> element("#gear-feat-less-epic_energy_resistance-fire") |> render_click()

      assert render(element(view, "#gear-feat-count-epic_energy_resistance-fire")) =~
               "×1 из 10"

      refute render(element(view, "#gear-feat-count-epic_energy_resistance-fire")) =~ "×2"
      assert render(element(view, "#stat-resist-fire")) =~ "15"

      view |> element("#gear-feat-less-epic_energy_resistance-fire") |> render_click()

      refute has_element?(view, "#gear-feat-entry-epic_energy_resistance-fire")
      refute has_element?(view, "#stat-resist-fire")
    end

    # «+» — единственный путь объявить второе взятие из интерфейса: второй шаг
    # (список значений) это переключатель и ту же пару предлагать не может.
    test "«+» добавляет взятие и упирается в потолок объявлений", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{pair_code(1)}")

      view |> element("#gear-toggle") |> render_click()
      view |> element("#gear-feat-more-epic_energy_resistance-fire") |> render_click()

      assert render(element(view, "#gear-feat-count-epic_energy_resistance-fire")) =~
               "×2 из 10"

      view =
        Enum.reduce(3..10, view, fn _n, view ->
          view |> element("#gear-feat-more-epic_energy_resistance-fire") |> render_click()
          view
        end)

      assert render(element(view, "#gear-feat-count-epic_energy_resistance-fire")) =~
               "×10 из 10"

      assert has_element?(view, "#gear-feat-more-epic_energy_resistance-fire[disabled]")

      assert render(element(view, "#gear-feat-more-why-epic_energy_resistance-fire")) =~
               "больше 10 раз нельзя"

      # Кнопка задизаблена в разметке, но событие обязано проверять потолок
      # само — правленая руками форма прислала бы его и без атрибута.
      render_click(view, "gear_feat_more", %{
        "feat" => "epic_energy_resistance",
        "choice" => "fire"
      })

      assert render(element(view, "#gear-feat-count-epic_energy_resistance-fire")) =~
               "×10 из 10"
    end

    # Потолок — ПО ПАРЕ, а не по имени фита: десять взятий огня не мешают
    # объявить холод (`GearFeats.add_reasons/3`, «десять на каждый вид урона»).
    test "соседняя стихия считается отдельно и своим степпером", %{conn: conn} do
      code = pair_code(2, [{:epic_energy_resistance, :cold}])
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      view |> element("#gear-toggle") |> render_click()

      assert render(element(view, "#gear-feat-count-epic_energy_resistance-fire")) =~ "×2"
      assert render(element(view, "#gear-feat-count-epic_energy_resistance-cold")) =~ "×1"

      view |> element("#gear-feat-less-epic_energy_resistance-cold") |> render_click()

      refute has_element?(view, "#gear-feat-entry-epic_energy_resistance-cold")
      assert render(element(view, "#gear-feat-count-epic_energy_resistance-fire")) =~ "×2"
      assert render(element(view, "#stat-resist-fire")) =~ "30"
    end

    test "ссылка после правок декодируется в те же взятия", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{pair_code(1)}")

      view |> element("#gear-toggle") |> render_click()
      view |> element("#gear-feat-more-epic_energy_resistance-fire") |> render_click()

      path = assert_patch(view)
      {:ok, shared, _html} = live(conn, path)

      open_gear(shared)

      assert render(element(shared, "#gear-feat-count-epic_energy_resistance-fire")) =~
               "×2 из 10"

      assert render(element(shared, "#stat-resist-fire")) =~ "30"
    end
  end

  # ---------------------------------------------------- задача 3.226 B --
  #
  # Третий вид подписи «уже отмечено». Находка агента 3.224 называла её
  # у `epic_energy_resistance`, но при прогоне оказалась ШИРЕ: клик по строке
  # фита, объявленного только значениями, добавляет ЕЩЁ одно объявление
  # у всех 15 фитов с доменом, а не у одного повторяемого, — и подпись
  # «✓ надет» («добавлять больше нечего») врала у всех 15 одинаково.
  # Поэтому в тестах и `epic_energy_resistance`, и `skill_focus`: они по-разному
  # отвечают на `GearFeats.repeats?/2` (true/false) и одинаково — на вопрос
  # «что сделает клик».
  describe "подпись строки списка выбора говорит то, что делает клик" do
    test "фит, объявленный ЗНАЧЕНИЕМ: «✓ надет · ещё значение»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{pair_code(1)}")

      view |> open_picker() |> search("epic energy")

      assert pick_label(view, "epic_energy_resistance") == "✓ надет · ещё значение"
    end

    # ⚠️ Не про подпись, а про то, ЧТО она обещает: тот же клик обязан завести
    # новое объявление со вторым шагом, а не снять уже объявленное значение.
    test "и клик по нему правда открывает второй шаг под новое значение", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{pair_code(1)}")

      view |> open_picker() |> search("epic energy")
      view |> element("#gear-pick-epic_energy_resistance") |> render_click()

      # Объявленное значение на месте, рядом появился второй шаг, а сама
      # подпись стала «✓ надет»: теперь клик СНИМЕТ голое объявление.
      assert has_element?(view, "#gear-feat-entry-epic_energy_resistance-fire")
      assert has_element?(view, "#gear-feat-pending-epic_energy_resistance")
      assert pick_label(view, "epic_energy_resistance") == "✓ надет"
    end

    # 14 из 15 фитов с доменом (`distinct?: true`) — `repeats?/2` у них `false`,
    # а подпись и клик ведут себя ровно так же, как у пятнадцатого.
    test "то же у Skill focus, который значение повторять НЕ умеет", %{conn: conn} do
      code =
        Encoding.encode(
          Build.new(
            ruleset_version: Data.ruleset!("siala_41").version,
            race: :human,
            alignment: :true_neutral,
            levels: List.duplicate(:fighter, 21),
            base_abilities: %{str: 14, dex: 12, con: 14, int: 10, wis: 10, cha: 8},
            gear: Gear.new(feats: [{:skill_focus, :discipline}])
          )
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      view |> open_picker() |> search("skill focus")
      assert pick_label(view, "skill_focus") == "✓ надет · ещё значение"

      view |> element("#gear-pick-skill_focus") |> render_click()

      assert has_element?(view, "#gear-feat-entry-skill_focus-discipline")
      assert has_element?(view, "#gear-feat-pending-skill_focus")
      assert pick_label(view, "skill_focus") == "✓ надет"
    end

    # Отрицательный контроль 1: фит БЕЗ значения. Клик по нему снимает
    # объявление — подпись обязана остаться прежней, «✓ надет» без приписки.
    test "фит без значения подписан по-прежнему", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{fixture_code()}")

      view |> open_picker() |> search("cleave")
      view |> element("#gear-pick-cleave") |> render_click()

      assert pick_label(view, "cleave") == "✓ надет"
    end

    # Отрицательный контроль 2: голое объявление фита С доменом (значение ещё
    # не названо). Клик снимает именно его, значит приписки быть не должно —
    # иначе подпись обещала бы добавление там, где будет снятие.
    test "голое объявление фита с доменом подписано «✓ надет»", %{conn: conn} do
      code = pair_code(0, [:epic_energy_resistance])
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      view |> open_picker() |> search("epic energy")
      assert pick_label(view, "epic_energy_resistance") == "✓ надет"

      view |> element("#gear-pick-epic_energy_resistance") |> render_click()
      refute has_element?(view, "#gear-feat-epic_energy_resistance")
    end
  end

  describe "фит с выбором дважды одной пары — по-прежнему одно" do
    test "повторный выбор той же пары не заводит вторую запись", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{fixture_code()}")

      view |> open_picker() |> search("skill focus")
      view |> element("#gear-pick-skill_focus") |> render_click()
      assert_patch(view)
      view |> element("#gear-feat-choice-skill_focus-discipline") |> render_click()

      assert has_element?(view, "#gear-feat-entry-skill_focus-discipline")

      path = assert_patch(view)
      {:ok, shared, _html} = live(conn, path)

      open_gear(shared)

      # Одна запись, не две: строка со счётчиком (`×2`) появилась бы только
      # у СТАКАЮЩЕГОСЯ фита без выбора — `skill_focus` им не является.
      assert has_element?(shared, "#gear-feat-entry-skill_focus-discipline")
      refute has_element?(shared, "#gear-feat-more-skill_focus")
    end
  end
end
