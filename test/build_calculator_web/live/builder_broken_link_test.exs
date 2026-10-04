defmodule BuildCalculatorWeb.BuilderBrokenLinkTest do
  @moduledoc """
  Задача 3.228: битый код в `?b=`, приехавший В ЖИВУЮ СЕССИЮ, обязан открыть
  ПУСТОЙ конструктор — ровно то, что обещают все пять текстов
  `Labels.decode_error/1` («открыт пустой конструктор») и `.claude/agents/
  dev-web.md`.

  До правки ветка `{:error, _}` в `load_code/3` ставила флеш и оставляла на
  экране прежний билд: сообщение говорило одно, экран показывал другое, а
  перезагрузка той же страницы давала третье — пустой конструктор. Оба теста
  первой группы до правки падали (уровень персонажа оставался `3`).

  ## ⚠️ Достижимость: сегодня пути игроку НЕТ, и это записано, а не умолчано

  Проверено обходом всех входов 20.09.2026:

    * `<.link patch>` в этот LiveView не ведёт **ниоткуда** (в шаблоне
      конструктора их нет вовсе, `JS.patch` не используется), значит
      `handle_params/3` без перемонтирования вызывает только наш собственный
      `push_patch` — а он всегда несёт `@code`, то есть валидную строку;
    * `/s/:key` — HTTP-редирект контроллера, переходы из библиотеки и с экрана
      просмотра — `<.link navigate>`; и то и другое даёт свежий `mount/3`,
      где билд и так пуст;
    * «Назад»/«Вперёд» браузера патчат LiveView только если запись истории
      помечена `type: "patch"` И принадлежит тому же `main.id`
      (`phoenix_live_view.esm.js`, слушатель `popstate`); прочие записи идут
      через `replaceMain`, то есть тоже через `mount/3`.

  Значит эти тесты — **страховка и согласованность экрана с сообщением**,
  а не починка бага прода: `render_patch/2` здесь делает то, чего интерфейс
  сегодня сделать не даёт. Цена страховки — одна строка в `load_code/3`; цена
  её отсутствия — экран, спорящий со своим сообщением, в день, когда такой
  путь появится (`<.link patch>` на лестницу уровней хватит).
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.PointBuy

  setup do
    %{ruleset: Data.ruleset!(Data.default_version())}
  end

  defp build(ruleset, levels) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: levels,
      base_abilities: %{str: 13, dex: 15, con: 10, int: 10, wis: 10, cha: 10}
    )
  end

  # Ровно тот билд, которым открывается свежий конструктор
  # (`BuilderLive.empty_build/1`): пустая лестница плюс пол поинт-бая. Собран
  # здесь заново, а не взят из адреса, — чтобы проверка не свелась к «код
  # такой, какой мы только что показали».
  defp empty_code(ruleset) do
    Encoding.encode(
      Build.new(
        ruleset_version: ruleset.version,
        base_abilities: PointBuy.starting_scores(ruleset)
      )
    )
  end

  # ⚠️ Раса и мировоззрение не названы намеренно — тот же довод, что
  # в `builder_load_code_reset_test.exs`: без них `level_ceiling/2` держит
  # `active` на последнем ВЗЯТОМ уровне, где слоты фитов есть, а не уносит
  # на пустой `taken + 1`.
  defp open_with_build(conn, ruleset, levels) do
    code = Encoding.encode(build(ruleset, levels))
    {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

    assert has_element?(view, "#character-level", to_string(length(levels)))

    view
  end

  describe "битый код в живой сессии" do
    test "открывает пустой конструктор, а не оставляет прежний билд", %{
      conn: conn,
      ruleset: ruleset
    } do
      view = open_with_build(conn, ruleset, [:fighter, :fighter, :fighter])

      html = render_patch(view, "/?b=1.not-a-real-code")

      assert html =~ "битая"
      assert has_element?(view, "#character-level", "0")

      # Лестница пуста не «в среднем», а на первой же строке — там, где у воина
      # 1-3 стояла полоса класса.
      assert has_element?(view, "#level-1[data-empty='1']")
      refute has_element?(view, "#split-fighter")
    end

    test "незнакомая версия кодировки ведёт себя так же", %{conn: conn, ruleset: ruleset} do
      view = open_with_build(conn, ruleset, [:fighter, :fighter, :fighter])

      html = render_patch(view, "/?b=99.abcdef")

      assert html =~ "версией кодировки"
      assert has_element?(view, "#character-level", "0")
    end

    # Пункт 3 постановки: битый код не имеет права остаться источником ссылки.
    # `#share-link` строится из `@code`, а тот после сброса — код того самого
    # пустого билда, что на экране.
    test "«Скопировать ссылку» отдаёт ссылку на то, что на экране", %{
      conn: conn,
      ruleset: ruleset
    } do
      view = open_with_build(conn, ruleset, [:fighter, :fighter, :fighter])

      render_patch(view, "/?b=1.not-a-real-code")

      assert has_element?(view, "#share-link[value$='/b/#{empty_code(ruleset)}']")
    end

    # И сам адрес (`patch_to_own_code/1`): битый код в `?b=` не остаётся даже
    # до первой правки билда, поэтому перезагрузка страницы больше не даёт
    # третьего состояния и не повторяет сообщение об ошибке.
    test "адрес переписывается на то, что на экране", %{conn: conn, ruleset: ruleset} do
      view = open_with_build(conn, ruleset, [:fighter, :fighter, :fighter])

      render_patch(view, "/?b=1.not-a-real-code")

      assert_patch(view, "/?b=#{empty_code(ruleset)}&l=1")
    end

    # UI-состояние прежнего билда уезжает вместе с ним — той же
    # `forget_build_ui/1`, которой его забывают ссылка и импорт (3.226).
    test "уровневое UI-состояние прежнего билда не остаётся на экране", %{
      conn: conn,
      ruleset: ruleset
    } do
      view = open_with_build(conn, ruleset, [:fighter, :fighter])

      view |> element("#slot-filter-class_bonus-fighter") |> render_click()
      assert has_element?(view, "#slot-filter-hint")
      render_hook(view, "preview", %{"kind" => "class", "id" => "fighter"})
      assert has_element?(view, "#delta-box[data-live='1']")

      render_patch(view, "/?b=1.not-a-real-code")

      refute has_element?(view, "#slot-filter-hint")
      assert has_element?(view, "#delta-box[data-live='0']")
    end
  end

  describe "битый код на свежей загрузке" do
    # Регрессия задачи 3.228 против собственной правки: мёртвый рендер обязан
    # остаться страницей (200), а не стать HTTP-редиректом. `push_patch`,
    # не пойманный на мёртвом рендере, `Phoenix.LiveView.Static` превращает
    # в 302 — и вместе со страницей исчез бы предмет регрессии 3.66
    # («битая ссылка не удваивает список фитов»).
    #
    # ⚠️ Проверено снятием гейта, а не вычитано: без `connected?/1`
    # в `patch_to_own_code/1` этот тест отвечает «expected response with
    # status 200, got: 302», а соседний перестаёт монтироваться вовсе
    # (`live/2` возвращает `{:error, {:live_redirect, …}}`).
    test "мёртвый рендер отдаёт страницу, а не редирект", %{conn: conn} do
      conn = get(conn, ~p"/?b=1.not-a-real-code")

      assert html_response(conn, 200) =~ "битая"
    end

    # ⚠️ Патч адреса на ПОДКЛЮЧЁННОМ монтировании `assert_patch/2` увидеть
    # не может, и это свойство тестового клиента, а не наше: `live_patch`
    # приезжает в ответе на join, а `ClientProxy.mount_view/4` читает оттуда
    # только `%{rendered: …}` — в браузере его применяет `applyJoinPatch`
    # (`phoenix_live_view.esm.js`), в тесте он просто теряется. Поэтому здесь
    # проверяется то, что наблюдаемо: экран и ссылка на билд уже не от битого
    # кода. Сам механизм патча закрыт тестом живой сессии выше.
    test "подключённая сессия той же страницы открывает пустой конструктор", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, html} = live(conn, ~p"/?b=1.not-a-real-code")

      assert html =~ "битая"
      assert has_element?(view, "#character-level", "0")
      assert has_element?(view, "#share-link[value$='/b/#{empty_code(ruleset)}']")
    end
  end
end
