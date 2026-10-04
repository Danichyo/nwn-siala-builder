defmodule BuildCalculatorWeb.BuilderLoadCodeResetTest do
  @moduledoc """
  Задача 3.226, часть A: билд, пришедший ИЗ АДРЕСА, обязан забывать уровневое
  UI-состояние прежнего билда так же полно, как его забывают клик по лестнице
  (`go_to_level/2`) и применённый импорт (`apply_imported/5`).

  `handle_params/3` зовёт `load_code/3` всякий раз, когда `b` в адресе
  разошёлся с `@code`; в тесте это и есть `render_patch/2`.

  ⚠️ **Здесь стояло «путь достижим в живой сессии… „Назад“/„Вперёд“ браузера
  и переход по другой ссылке `?b=` в той же вкладке» — проверено 20.09.2026
  (задача 3.228) и не подтвердилось.** Набор адреса руками даёт полную загрузку,
  то есть свежий `mount/3`; «Назад»/«Вперёд» патчат LiveView только на записи
  истории с `type: "patch"` И тем же `main.id`
  (`phoenix_live_view.esm.js`, слушатель `popstate`), а такие записи пишем
  только мы сами — и всегда валидным `@code` (все наши `push_patch` идут
  с `replace: true`, новых записей не создавая). `<.link patch>` в этот
  LiveView не ведёт ниоткуда. Разбор целиком — модульдок
  `builder_broken_link_test.exs`.

  **Сами проверки от этого не обесценились:** ту же `forget_build_ui/1` зовёт
  `apply_imported/5`, а импорт игрок проходит руками — эта половина закрыта
  тестом про «+ добавить навык» ниже. `render_patch/2` остаётся самым дешёвым
  способом позвать `load_code/3`.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.Build

  setup do
    %{ruleset: Data.ruleset!(Data.default_version())}
  end

  # ⚠️ Раса и мировоззрение НЕ названы намеренно: без них `level_ceiling/2`
  # держит `active` на уже взятом уровне (задача 3.69), то есть и открытая
  # ссылка, и патч приземляются на последний уровень билда, где слоты фитов
  # есть. С расой оба уехали бы на `taken + 1` — пустой уровень без класса,
  # без слотов и без карточки, и предмет проверки исчез бы с экрана.
  defp build(ruleset, levels) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: levels,
      base_abilities: %{str: 13, dex: 15, con: 10, int: 10, wis: 10, cha: 10}
    )
  end

  describe "чип слота фита" do
    # Воин 1 → воин 1-2: бонусный слот Воина есть на ОБОИХ уровнях, значит
    # тот же самый узел DOM остаётся на экране, и подсветку можно спросить
    # у него напрямую, а не по её отсутствию.
    test "подсветка не переезжает на билд из адреса", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter]))}")

      view |> element("#slot-filter-class_bonus-fighter") |> render_click()
      assert has_element?(view, "#slot-chip-class_bonus-fighter[data-focused='1']")
      assert has_element?(view, "#slot-filter-hint")

      render_patch(view, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter, :fighter]))}")

      assert has_element?(view, "#slot-chip-class_bonus-fighter")
      refute has_element?(view, "#slot-chip-class_bonus-fighter[data-focused='1']")
      refute has_element?(view, "#slot-filter-hint")
    end

    # Хуже того: слота, которым отфильтрован список, на новом уровне может
    # не быть вовсе. Волшебник 1 бонусного слота не имеет — подсказка
    # «показаны только фиты, которые примет этот слот» указывала бы на чип,
    # которого на экране нет, а список фитов оставался бы урезанным.
    test "фильтр снимается, даже если такого слота у нового билда нет", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter]))}")

      view |> element("#slot-filter-class_bonus-fighter") |> render_click()
      assert has_element?(view, "#slot-filter-hint")

      render_patch(view, ~p"/?b=#{Encoding.encode(build(ruleset, [:wizard]))}")

      refute has_element?(view, "#slot-chip-class_bonus-fighter")
      refute has_element?(view, "#slot-filter-hint")

      # Положительный контроль: общий слот 1-го уровня на экране есть и
      # ничем не подсвечен — то есть чипы рисуются, просто фильтр снят.
      assert has_element?(view, "#slot-chip-general")
      refute has_element?(view, "#slot-chip-general[data-focused='1']")
    end
  end

  # Задача 3.228, пункт 4 — хвост 3.221/3.226 на том же наборе ассайнов: кнопка
  # «сбросить» чистила `:feat_query`, `:skill_add?` и `:skill_query` с самого
  # начала, а ссылка и оба импорта — нет. Оба теста ниже до правки падали.
  describe "поиск и открытые списки прежнего билда" do
    test "набранный запрос фитов не переезжает на билд из адреса", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter]))}")

      view |> form("#feat-search-form", %{"q" => "pow"}) |> render_change()
      assert has_element?(view, "#feat-search[value='pow']")

      render_patch(view, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter, :fighter]))}")

      # Положительный контроль: поле поиска на экране есть (на 2-м уровне воина
      # слоты фитов есть), просто пустое — то есть запрос сброшен, а не унесён
      # вместе с формой.
      assert has_element?(view, "#feat-search")
      refute has_element?(view, "#feat-search[value='pow']")
    end

    # 🔴 Тот же ассайн, но путём, который игрок ПРОХОДИТ: импорт игрового лога
    # — единственный вход `forget_build_ui/1`, достижимый из интерфейса (у `?b=`
    # в живой сессии пути нет вовсе, разбор — модульдок
    # `builder_broken_link_test.exs`). Проверяется список навыков, а не поиск
    # фитов: Хнюпиус приземляется на 40-й уровень, где слотов фитов нет и поля
    # поиска на экране не бывает, а «+ добавить навык» есть на каждом уровне.
    test "открытый список «+ добавить навык» не переживает применённый импорт", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter]))}")

      view |> element("#skill-add-toggle") |> render_click()
      view |> form("#skill-search-form", %{"q" => "disc"}) |> render_change()
      assert has_element?(view, "#skill-search[value='disc']")

      log = "../../fixtures/game_logs/hnyupius.log" |> Path.expand(__DIR__) |> File.read!()

      view |> element("#game-log-import-button") |> render_click()

      view
      |> form("#game-log-import-form", %{"game_log_import" => %{"text" => log}})
      |> render_submit()

      view |> element("#game-log-import-apply") |> render_click()

      assert has_element?(view, "#character-level", "40")
      refute has_element?(view, "#skill-search")

      # Положительный контроль: сама кнопка на месте, значит секция навыков
      # нарисована и список именно свёрнут.
      assert has_element?(view, "#skill-add-toggle")
    end
  end

  # Задача 3.229 (20.09.2026). Кандидат записан агентом 3.228: «`:feat_type`,
  # `:spell_query`, `:spell_circles` не чистит НИКТО, даже „Сброс“». Проверено
  # координатором: `:spell_circles` — НЕ состояние игрока, а производная
  # (`Builder.LevelPicks` пересобирает его из каталога активного уровня на каждой
  # перерисовке), чистить там нечего. Остальные два — настоящие: выбранный чип
  # типа фитов и набранный поиск заклинаний переживали замену билда целиком.
  #
  # ⚠ Между уровнями ОДНОГО билда оба живут намеренно (`forget_level_ui/1` их
  # не трогает, как и `:feat_query`): чип подсвечен над списком, то есть фильтр
  # виден, а «Эпические» на 21-м и 22-м уровне подряд — удобство, а не дефект.
  describe "фильтры списков прежнего билда (3.229)" do
    test "чип типа фитов возвращается к «Все»", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter]))}")

      view |> element("#feat-type-epic") |> render_click()
      assert has_element?(view, "#feat-type-epic[data-on='1']")

      render_patch(view, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter, :fighter]))}")

      # Положительный контроль: чипы на экране есть — сброшен выбор, а не форма.
      assert has_element?(view, "#feat-type-filters")
      assert has_element?(view, "#feat-type-all[data-on='1']")
      refute has_element?(view, "#feat-type-epic[data-on='1']")
    end

    test "кнопка «Сброс» тоже возвращает чип к «Все»", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter]))}")

      view |> element("#feat-type-bonus") |> render_click()
      assert has_element?(view, "#feat-type-bonus[data-on='1']")

      render_click(view, "reset", %{})

      refute has_element?(view, "#feat-type-bonus[data-on='1']")
    end

    test "набранный поиск заклинаний не переезжает на билд из адреса", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} =
        live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:bard, :bard]))}&l=2")

      assert has_element?(view, "#spell-search")
      view |> form("#spell-search-form", %{"q" => "cure"}) |> render_change()
      assert has_element?(view, "#spell-search[value='cure']")

      render_patch(view, ~p"/?b=#{Encoding.encode(build(ruleset, [:sorcerer]))}&l=1")

      assert has_element?(view, "#spell-search")
      refute has_element?(view, "#spell-search[value='cure']")
    end
  end

  describe "превью (призрачные +N)" do
    test "наведение прежнего билда не переезжает на билд из адреса", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter]))}")

      render_hook(view, "preview", %{"kind" => "class", "id" => "fighter"})
      assert has_element?(view, "#delta-box[data-live='1']")

      render_patch(view, ~p"/?b=#{Encoding.encode(build(ruleset, [:wizard]))}")

      assert has_element?(view, "#delta-box[data-live='0']")
    end

    # Вторая форма превью — наведение на РАСУ; она живёт в том же ассайне,
    # но приходит с карточки уровня 1, то есть с другого места экрана.
    test "наведение на расу снимается тем же патчем", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter]))}")

      render_hook(view, "preview", %{"kind" => "race", "id" => "human"})
      assert has_element?(view, "#delta-box[data-live='1']")

      render_patch(view, ~p"/?b=#{Encoding.encode(build(ruleset, [:wizard]))}")

      assert has_element?(view, "#delta-box[data-live='0']")
    end
  end
end
