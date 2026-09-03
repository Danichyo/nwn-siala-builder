defmodule BuildCalculatorWeb.BuilderLive do
  @moduledoc """
  The build constructor.

  Three columns (CLAUDE.md §6): the progression ladder on the left, the current
  level's decisions in the middle, the totals panel on the right. On a narrow
  screen the columns become steps, the ladder a horizontal strip and the totals
  a bottom sheet.

  ## What lives here and what does not

  Not one game formula. Every number comes from `BuildCalculator.Rules` and
  `BuildCalculator.Data`; the refusals the core hands back are tuples
  (`{:requires_bab, 4}`) and this module's only opinion about them is which
  Russian sentence to print (`BuildCalculatorWeb.Builder.Labels`).

  State lives in the socket, and the socket's build is mirrored into the URL on
  every change (`BuildCalculator.Encoding`) — v1 has no database, so
  the link *is* the save file.

  ## Recomputation

  One `Rules.compute/2` per event for the build itself; the class cards need one
  more per candidate class, which is why they are only built when their section
  is open. Deltas are always `compute(base) -> compute(base + candidate)`, never
  an incremental shortcut — two implementations would eventually disagree and
  the player would be shown one number and given another.
  """
  use BuildCalculatorWeb, :live_view

  import BuildCalculatorWeb.BuilderComponents

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Ids
  alias BuildCalculator.Rules
  alias BuildCalculator.ShortLinks

  alias BuildCalculator.Rules.{
    Abilities,
    Build,
    ClassChoices,
    FeatSlots,
    Gear,
    LevelUp,
    Skills,
    Spells
  }

  alias BuildCalculatorWeb.Builder.{
    Export,
    Feats,
    Fuzzy,
    GameLogImport,
    GameLogImportPanel,
    Gaps,
    GearPanel,
    Icons,
    Import,
    ImportPanel,
    Labels,
    LevelPicks,
    Palette,
    PointBuy,
    TotalsPanel
  }

  # Сколько РАЗНЫХ билдов одно соединение может сократить. Настоящий игрок
  # нажимает эту кнопку единицы раз за сеанс; предел стоит против зациклившегося
  # клиента, а не против бота (тот переподключится). Отказ ничего не теряет:
  # длинная ссылка остаётся на экране и работает.
  @short_links_per_socket 50

  @impl true
  def mount(params, _session, socket) do
    ruleset = Data.ruleset!()

    socket =
      socket
      |> assign(:page_title, "Калькулятор билдов Сиалы")
      |> assign(:ruleset, ruleset)
      |> assign(:build, empty_build(ruleset))
      |> assign(:ladder_issues, %{})
      # Задача 3.17: нулевой и первый уровни слиты в один редактор, поэтому
      # `active` больше никогда не бывает 0 — раса/мировоззрение/статы теперь
      # часть уровня 1, а не отдельного экрана. Строка `#level-0` в лестнице
      # осталась (решение Дана), но ведёт на тот же уровень 1, что и `#level-1`
      # (см. `select_level`, где нижняя граница `max(1)`, а не `max(0)`).
      |> assign(:active, 1)
      |> assign(:hold, nil)
      # Сброс распределения поинт-бая при смене класса первого уровня, если
      # принудительная покупка не помещается в свободные очки (AGENT_QUEUE
      # §3.17, решение 3) — заполняется и очищается только в `put_build/2`,
      # единственной воронке правок билда.
      |> assign(:point_buy_reset, nil)
      |> assign(:preview, nil)
      |> assign(:code, nil)
      |> assign(:base_url, "/")
      # Короткие ссылки, выданные ЭТИМ соединением: `код => ключ`. Память, а не
      # состояние билда — билд по-прежнему целиком живёт в `:code`.
      #
      # ⚠️ Ключ к памяти — сам код, и это не мелочь: правка билда меняет код,
      # значит короткая ссылка на прежний билд перестаёт описывать то, что на
      # экране, и блок с ней исчезает сам. Показать её рядом со свежей длинной
      # значило бы соврать. Вернулся к прежнему билду (отмена правки) — ключ
      # находится в памяти, без похода в базу.
      |> assign(:short_links, %{})
      |> assign(:short_key, nil)
      |> assign(:feat_query, "")
      |> assign(:feat_type, "all")
      |> assign(:feat_slot, nil)
      # Второй шаг выбора: `%{feat:, slot:, level:}`, пока игрок не назвал школу
      # (расу, навык). До этого в билд НИЧЕГО не пишется — см. `pick_feat`.
      |> assign(:feat_choice, nil)
      |> assign(:skill_add?, false)
      |> assign(:skill_query, "")
      |> assign(:spell_query, "")
      |> assign(:spell_circles, %{})
      |> assign(:sections, %{})
      # Задача 3.157 (просьба владельца шарда через Dan, 01.09.2026): вернуть
      # автоскролл к следующей секции, но ТОЛЬКО за этой галочкой — 3.30 сняла
      # безусловный автоскролл по жалобе «дёргается» (см. `put_build/2`,
      # `guide_scroll/2`). Состояние живёт СНАЧАЛА здесь, в сокете
      # (`Rules.compute` до него не доходит и повлиять на билд не может), НЕ
      # в билде и НЕ в URL — это настройка читателя, а не свойство билда
      # (постановка прямо это называет). Источник истины при этом —
      # `localStorage` на клиенте («переживает перезагрузку, как тема»):
      # сюда попадает лишь ЗЕРКАЛО, которое хук `.GuidedMode` синхронизирует
      # при монтировании и на каждый клик (`"set_guided_mode"` ниже),
      # поэтому дефолт тут не обязан совпадать с тем, что игрок увидит —
      # первый же кадр после подключения хука его подравняет.
      |> assign(:guided_mode, false)
      |> assign(:export_open?, false)
      |> assign(:export_text, "")
      # Автоматические (`○`) фиты в сиальском гиде экспорта — переключатель,
      # скрыты по умолчанию (задача 3.146, жалоба игрока через Dan
      # 30.08.2026, глядя на свежий слитый гид 3.145: «скрыть фиты,
      # получаемые автоматически… по дефолту можно их спрятать, чтоб UI
      # почище был»). `Export.text/4`'s own default stays `true` — this
      # assign is the constructor dialog's own choice, not a module-wide
      # change (see `Export`'s moduledoc: `BuildViewLive`'s copy-to-clipboard
      # text keeps showing them, that is a separate, already-argued-for
      # decision this task does not touch).
      |> assign(:export_show_granted?, false)
      |> assign(:import_open?, false)
      |> assign(:import_form, ImportPanel.import_form(""))
      |> assign(:import_report, nil)
      |> assign(:game_log_import_open?, false)
      |> assign(:game_log_import_form, GameLogImportPanel.form(""))
      |> assign(:game_log_import_report, nil)
      |> assign(:build_title, nil)
      |> assign(:gaps_open?, false)
      |> assign(:gear_open?, false)
      |> assign(:gear_feat_add?, false)
      |> assign(:gear_feat_query, "")
      # Второй шаг у фита с вещи (задача 3.97, заход 2): поиск по значению —
      # свой на каждый ОБЪЯВЛЕННЫЙ, но ещё не выбранный фит, а не один общий.
      # Ключ — id фита: `Gear.toggle_feat/3` не допускает двух ГОЛЫХ записей
      # одного фита разом (это один и тот же переключаемый элемент), поэтому
      # одновременно ждать значение может только одна запись на фит.
      |> assign(:gear_feat_choice_query, %{})
      |> assign(:gear_skill_add?, false)
      |> assign(:gear_skill_query, "")
      |> assign(:gear_weapon_add?, false)
      |> assign(:gear_weapon_query, "")
      # Вторая рука (задача 3.132, Dan 28.08.2026: «можем ввести вторую руку?
      # с возможностью выбрать оружие вместо щита»). Свой список добавления,
      # своя строка поиска — как у главной руки, но не смешиваются: у каждой
      # руки свой пул отказов.
      |> assign(:gear_off_weapon_add?, false)
      |> assign(:gear_off_weapon_query, "")
      # Строки навыков с вещи, у которых числа пока нет. Ноль в билд не пишется
      # (`Gear.skills` хранит только ненулевое, и кодировка тоже), поэтому
      # «добавил навык, ещё не набрал число» — состояние ИНТЕРФЕЙСА, а не билда.
      # ⚠️ Без него строка исчезала бы под пальцами: стёр значение до нуля —
      # и поле ввода пропало вместе с ним.
      |> assign(:gear_skill_open, MapSet.new())
      |> stream_configure(:gear_feat_options, dom_id: &("gear-pick-" <> Atom.to_string(&1.id)))
      |> stream_configure(:gear_weapon_options,
        dom_id: &("gear-weapon-" <> Atom.to_string(&1.id))
      )
      |> stream_configure(:gear_off_weapon_options,
        dom_id: &("gear-off-weapon-" <> Atom.to_string(&1.id))
      )
      |> stream_configure(:feats_available, dom_id: &("feat-ok-" <> Atom.to_string(&1.feat.id)))
      |> stream_configure(:feats_blocked, dom_id: &("feat-no-" <> Atom.to_string(&1.feat.id)))
      |> stream_configure(:spells, dom_id: &("spell-" <> Atom.to_string(&1.id)))

    # ⚠️ Задача 3.66 (баг, нашёл Dan 20.08.2026): если в адресе уже есть
    # `?b=…`, `handle_params/3` тут же вызовет `load_code/3`, а тот —
    # СВОЙ `refresh()`, который перепишет и `:build`, и всё, что от него
    # зависит. Между `mount/3` и `handle_params/3` рендера не бывает ни
    # разу — ни в статике (`Phoenix.LiveView.Static`), ни при коннекте
    # (`Phoenix.LiveView.Channel`): оба зовут `mount/3`, затем немедленно
    # `handle_params/3`, с ОДНИМ И ТЕМ ЖЕ `params` (проверено по исходникам
    # `phoenix_live_view` — `mount_params = if socket.router, do: params,
    # else: :not_mounted_at_router`, дальше та же переменная идёт и в
    # `mount`, и в `handle_params`).
    #
    # А `stream(socket, name, items, reset: true)` не чистит накопленное
    # немедленно: `Phoenix.LiveView.LiveStream.reset/1` только ставит флаг
    # для клиентского диффа, сам список `inserts` пруднится хуком
    # `:after_render` — то есть ПОСЛЕ рендера. Значит два `refresh()` подряд
    # без рендера между ними не перезаписывают все пять потоков (фиты
    # доступные/недоступные, заклинания, предметы под фит/оружие) — они их
    # СКЛАДЫВАЮТ: второй вызов прибавляет свои вставки к первым, а не
    # заменяет их. Первый рендер получал объединение
    # двух билдов — пустого 1-го уровня из этого `mount/3` и настоящего
    # из `handle_params/3` — с разными причинами отказа на одинаковых id.
    # Это и есть баг 3.66: «фиты для первого уровня» на экране, «потом
    # фильтр срабатывает и они пропадают» — на самом деле не фильтр, а
    # первый же `refresh()` ПОСЛЕ рендера, у которого поток уже пуст
    # и складывать было не с чем.
    #
    # Фикс: не звать `refresh/1` здесь, если адрес всё равно несёт код —
    # тогда единственный вызов до первого рендера тот, что сделает
    # `handle_params/3` → `load_code/3` (он зовёт `refresh/1` что на
    # успешный декод, что на битую ссылку — обе ветки `load_code/3`).
    # Без кода в адресе `handle_params/3` молчит (ветка `nil` в его
    # `case`), и тогда `refresh/1` обязан отработать здесь сам — иначе
    # пустой конструктор открылся бы без списка фитов 1-го уровня вовсе.
    {:ok, if(params["b"], do: socket, else: refresh(socket))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :base_url, URI.parse(uri) |> Map.put(:query, nil) |> URI.to_string())

    case params["b"] do
      nil ->
        {:noreply, socket}

      code when code == socket.assigns.code ->
        # Our own push_patch coming back around.
        {:noreply, socket}

      code ->
        {:noreply, load_code(socket, code, params)}
    end
  end

  # Задача 3.61: `l` — необязательная вторая половина адреса, уровень
  # редактора. Обычная ссылка «поделиться» его не несёт (`view_url/1` строит
  # адрес из одного `code`), а адрес можно поправить руками — оба случая
  # читаются одинаково, как «нет запроса», и `requested_level/1` отдаёт `nil`,
  # который здесь же откатывает к прежнему поведению: следующий уровень после
  # последнего взятого. Итог идёт в тот же `clamp_level/3`, каким пользуется
  # клик по лестнице (`select_level`) — один зажим на оба источника, а не два
  # переписанных друг под друга (форма бага 1.2, CLAUDE.md §8).
  defp load_code(socket, code, params) do
    case Encoding.decode(code) do
      {:ok, %{ruleset: ruleset, build: build, dropped: dropped}} ->
        taken = Build.character_level(build)

        active =
          clamp_level(
            requested_level(params) || taken + 1,
            level_ceiling(build, taken),
            ruleset.level_cap
          )

        socket
        |> assign(:ruleset, ruleset)
        |> assign(:build, build)
        |> assign(:ladder_issues, ladder_issues(ruleset, build))
        |> assign(:code, code)
        |> assign(:active, active)
        |> assign(:hold, nil)
        |> assign(:sections, %{})
        |> assign(:feat_choice, nil)
        |> assign(:build_title, nil)
        # Билд из ссылки идёт МИМО воронки `put_build/2` (решение 1.7) — значит
        # мимо и нового сброса распределения; никакого «только что сброшено»
        # рассказывать не о чем.
        |> assign(:point_buy_reset, nil)
        |> forget_gear_ui()
        |> warn_dropped(dropped)
        |> refresh()

      {:error, reason} ->
        socket
        |> put_flash(:error, Labels.decode_error(reason))
        |> assign(:code, nil)
        |> refresh()
    end
  end

  # `"20"` → `20`. Отсутствие параметра и любой мусор (`"abc"`, `"5abc"`,
  # `""`) — всё одно и то же `nil`, не отдельные ветки: диапазон (`-5`, `0`,
  # `999`) обрабатывает уже `clamp_level/3` ниже, здесь только формат.
  defp requested_level(params) do
    with level when is_binary(level) <- params["l"],
         {n, ""} <- Integer.parse(level) do
      n
    else
      _ -> nil
    end
  end

  # ⚠️ Задача 3.69 (Dan 21.08.2026) — ПЕРЕСМОТР задачи 3.68. Вчера раса
  # и мировоззрение получили янтарь в ленте секций БЕЗ запрета («нам не нужны
  # ограничения, просто цвет» — `creation_hold?/2`, там же остальная история
  # 3.68). Сегодня Dan попросил обратное, дословно: «кнопку перевода на
  # 2 уровень я бы все-таки блокировал, пока раса и мировоззрение не выбраны,
  # так будет логичнее». Оба решения остаются записанными — 3.68 не была
  # ошибкой, она честно называла то, что мы тогда умели; 3.69 умеет больше.
  #
  # `true`, когда решений создания персонажа, без которых игра дальше 1-го
  # уровня не пускает, не осталось — то есть названы раса и мировоззрение.
  # ⚠️ Ровно два поля, не три: поинт-бай сюда сознательно не входит, решение
  # 3.32 не пересматривается (см. `creation_hold?/2` — там же почему).
  # ⚠️ И это правило ИНТЕРФЕЙСА, а не игры: `Rules.validate_level_up/3` расу
  # и мировоззрение не спрашивает и не должен — легальность билда считает
  # ядро, а куда пускать курсор решает веб-слой (CLAUDE.md §5).
  defp creation_complete?(%Build{race: race, alignment: alignment}),
    do: not is_nil(race) and not is_nil(alignment)

  # Потолок «докуда можно долистать лестницу» — ОДНА формула на ДВУХ
  # читателей: `clamp_level/3` ниже (клик по лестнице — `select_level`
  # и `jump_to_gap` через `go_to_level/2`; адрес `?l=`; применённый импорт)
  # и `assign_stage_nav/1` (кнопка «Уровень N →», включая её текст «сначала
  # …»). Задача 3.69 просит ИМЕННО этого — кнопка и лестница обязаны
  # соглашаться, а не каждая по-своему решать, что дальше нельзя (форма
  # бага 1.2, CLAUDE.md §8).
  #
  # ⚠️ Формула — «нельзя уйти НА уровень, который ещё не взят», а НЕ «нельзя
  # уйти С 1-го уровня»: билд с пятью уровнями класса, но без указанной расы
  # (старая ссылка — понятие «раса обязательна» моложе многих сохранённых
  # билдов), обязан листаться до 5-го как и раньше. Блокируется только
  # ДОБАВЛЕНИЕ нового, шестого уровня. Поэтому пол — `max(taken, 1)`, а не
  # голое `taken`: на пустом билде (`taken == 0`) смотреть по-прежнему можно
  # ровно на уровень 1, а не «никуда» (тот же пол, что у `clamp_level/3`
  # своим `max(1)` — здесь он же, но до, а не после сравнения с потолком).
  defp level_ceiling(%Build{} = build, taken) do
    if creation_complete?(build), do: taken + 1, else: max(taken, 1)
  end

  # ⚠️ ОДНА реализация зажима на все места, куда уровень приходит не изнутри
  # приложения (клик по лестнице — `select_level`; адрес ссылки — `load_code/3`;
  # чужой билд — `import_apply`). Раньше формула стояла в `load_code/2`
  # и `import_apply` отдельно от `select_level` (оба — старым `min/2` без
  # верхней границы по запрошенному `n`, та половина не была нужна, пока
  # единственным «запросом» был сам `taken + 1`). Задача 3.61 завела источник,
  # где `n` — чужой ввод (`?l=999`, `?l=-5`, `?l=0`), и раздельные копии этой
  # формулы разошлись бы первой же следующей правкой (форма бага 1.2,
  # CLAUDE.md §8).
  #
  # ⚠️ Задача 3.69: второй параметр — уже готовый ПОТОЛОК (`level_ceiling/2`),
  # а не голое `taken`. Раньше верхняя граница была одним и тем же `taken + 1`
  # для всех трёх источников, и складывать её внутри `clamp_level/3` было
  # можно; теперь она условная (зависит от расы и мировоззрения billed'а),
  # и это условие знает только `level_ceiling/2`. Сам `clamp_level/3` от
  # этого не усложнился — он как был, так и остался зажимом ЧИСЛА в готовые
  # границы, а не местом, где эти границы вычисляются.
  defp clamp_level(n, ceiling, cap), do: n |> min(ceiling) |> min(cap) |> max(1)

  # ⚠️ Задача 3.60 вынесла тело клика по лестнице в отдельную функцию, чтобы
  # переиспользовать его в `jump_to_gap` — прыжок на пропущенный уровень
  # обязан сбрасывать состояние уровня и зажимать `n` ТЕМ ЖЕ кодом, что и клик
  # по лестнице, а не второй копией формулы (форма бага 1.2, CLAUDE.md §8).
  # `n` здесь уже целое число — разбор строки из `phx-value-level` остаётся
  # в `select_level`, единственном месте, где уровень приходит текстом.
  #
  # ⚠️ Живёт здесь, а не рядом с `handle_event`-обработчиками, которые её
  # зовут: все клаузы `handle_event/3` обязаны идти подряд без чужих
  # определений между ними (предупреждение компилятора при попытке
  # разместить её между `select_level` и `jump_to_gap`), а `go_to_level/2`
  # и так по смыслу — продолжение `clamp_level/3` прямо над ней.
  defp go_to_level(socket, n) do
    taken = Build.character_level(socket.assigns.build)
    was = socket.assigns.active

    # ⚠️ Задача 3.17: пол `max(1)`, а не `max(0)`. `#level-0` в лестнице
    # остался (решение Дана) и шлёт `"0"` тем же событием — но раса,
    # мировоззрение и статы теперь часть единого редактора уровня 1, а не
    # отдельного экрана, так что «выбрать уровень 0» и «выбрать уровень 1»
    # ведут на один и тот же `active`. Отдельного состояния «нулевой
    # уровень» больше не существует нигде в этом модуле.
    #
    # ⚠️ Задача 3.69: верхняя граница — `level_ceiling/2`, тот же потолок,
    # каким пользуется кнопка «Уровень N →» (`assign_stage_nav/1`). Без расы
    # и мировоззрения он не превышает уже взятое — это и есть просьба Dan
    # «блокировать переход, пока раса и мировоззрение не выбраны», применённая
    # к клику по лестнице, а не только к кнопке (§1 задачи, CLAUDE.md §8).
    active =
      clamp_level(n, level_ceiling(socket.assigns.build, taken), socket.assigns.ruleset.level_cap)

    socket =
      socket
      |> assign(:active, active)
      |> assign(:hold, nil)
      |> assign(:sections, %{})
      |> assign(:feat_slot, nil)
      |> assign(:feat_choice, nil)
      |> assign(:preview, nil)
      |> refresh()

    # Задача 3.61: уровень — в адрес, рядом с билдом. `replace: true`, как
    # у `put_build/2` (переключение уровня не событие истории браузера).
    # ⚠️ Только когда `active` ДЕЙСТВИТЕЛЬНО меняется: повторный клик по
    # уже активному уровню (в игре — «сверни секции заново»; в тестах —
    # частый «на всякий случай, точно ли мы здесь» перед следующим шагом)
    # не имеет права плодить лишний патч. Адрес и так уже верный, а лишнее
    # событие путает `Phoenix.LiveViewTest.assert_patch/1` — он читает
    # ОДНО сообщение из почтового ящика в порядке прихода (FIFO), и
    # непотреблённый патч от такого клика подменял бы собой патч
    # следующей, настоящей правки (найдено регрессией существующего
    # теста «a shared link opens the same build»).
    if active == was,
      do: socket,
      else: push_patch(socket, to: ~p"/?b=#{socket.assigns.code}&l=#{active}", replace: true)
  end

  defp warn_dropped(socket, []), do: socket

  defp warn_dropped(socket, dropped) do
    put_flash(socket, :info, "Из ссылки выпало: " <> Labels.dropped(dropped))
  end

  # ------------------------------------------------------------------ events --

  @impl true
  def handle_event("select_level", %{"level" => level}, socket) do
    with {n, ""} <- Integer.parse(level) do
      {:noreply, go_to_level(socket, n)}
    else
      _ -> {:noreply, socket}
    end
  end

  # Задача 3.60 (предложение Dan): клик по «N не выбрано» переводит на самый
  # маленький уровень с пропуском и подводит экран к его секции — то самое
  # действие, которое иначе означает открыть гид по билду и искать глазами
  # среди 41 строки.
  #
  # 🔴 Это НЕ противоречит задаче 3.30 (Dan 15.08.2026, `assign_stage_nav/1`).
  # 3.30 сняла ДВА автодвижения — хук `.FocusPending` и `settle/2`, — потому
  # что оба двигали экран БЕЗ ЗАПРОСА игрока. Здесь запрос есть: это прямое
  # следствие нажатой кнопки, тем же приёмом, что уже применён к «Уровень
  # N →» (`BuilderComponents.next_level/1` — «нажал «перейти» — перешёл,
  # включая вид»). 3.30 запрещала прыжок САМ ПО СЕБЕ, а не прыжок по клику.
  def handle_event("jump_to_gap", _params, socket) do
    case first_gap(socket.assigns.ladder, socket.assigns.character_level) do
      nil ->
        {:noreply, socket}

      {level, section} ->
        {:noreply,
         socket
         |> go_to_level(level)
         |> push_event("scroll_to_section", %{id: section})}
    end
  end

  def handle_event("pick_race", %{"race" => race}, socket) do
    %Build{} = build = socket.assigns.build

    case Ids.fetch(socket.assigns.ruleset, :races, race) do
      {:ok, id} -> {:noreply, put_build(socket, %Build{build | race: id})}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("pick_alignment", %{"alignment" => alignment}, socket) do
    %Build{} = build = socket.assigns.build

    case Ids.fetch(socket.assigns.ruleset, :alignments, alignment) do
      {:ok, id} -> {:noreply, put_build(socket, %Build{build | alignment: id})}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("point_buy", %{"ability" => ability, "delta" => delta}, socket) do
    %{build: %Build{} = build, ruleset: ruleset} = socket.assigns

    with {:ok, id} <- Ids.fetch(ruleset, :abilities, ability),
         {step, ""} when step in [-1, 1] <- Integer.parse(delta) do
      score = Map.get(build.base_abilities, id, PointBuy.floor(ruleset, build, id))

      allowed? =
        if step > 0,
          do: PointBuy.can_raise?(ruleset, build.base_abilities, score),
          else: PointBuy.can_lower?(ruleset, build, id, score)

      if allowed? do
        scores = Map.put(build.base_abilities, id, score + step)
        {:noreply, put_build(socket, %Build{build | base_abilities: scores})}
      else
        {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("pick_class", %{"class" => class}, socket) do
    %{ruleset: ruleset, build: %Build{} = build, active: active} = socket.assigns
    before = Build.truncate(build, active - 1)

    # `at:` matters: the class limit is a property of the finished build, so it
    # has to see the levels after this one too (see `Rules.LevelUp`).
    with {:ok, id} <- Ids.fetch(ruleset, :classes, class),
         choice = %{class: id, at: active},
         :ok <- LevelUp.validate(build, choice, ruleset, Rules.compute(before, ruleset)) do
      taken = Build.character_level(build)
      build = build |> Build.replace_level(active, id) |> prune_slots(ruleset, active)

      {:noreply,
       socket
       |> assign(:preview, nil)
       |> assign(:sections, %{})
       |> assign(:hold, levelling_hold(socket.assigns, taken))
       |> put_build(build)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("drop_level", _params, socket) do
    level = Build.character_level(socket.assigns.build)

    if level == 0 do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:active, min(socket.assigns.active, level))
       |> assign(:hold, nil)
       |> assign(:sections, %{})
       |> assign(:feat_slot, nil)
       |> put_build(Build.truncate(socket.assigns.build, level - 1))}
    end
  end

  def handle_event("pick_increase", %{"ability" => ability}, socket) do
    %{build: %Build{} = build, active: active} = socket.assigns

    case Ids.fetch(socket.assigns.ruleset, :abilities, ability) do
      {:ok, id} ->
        increases =
          if Map.get(build.ability_increases, active) == id,
            do: Map.delete(build.ability_increases, active),
            else: Map.put(build.ability_increases, active, id)

        build = %Build{build | ability_increases: increases}

        # Задача 3.30: здесь стоял `settle/2` — конструктор сам уезжал на
        # следующий уровень, как только этот закрывался. Автоперехода больше
        # нет (решение Dan 15.08.2026), и клик по уже выбранной характеристике
        # снимает её ровно так же, как раньше: разница только в том, что экран
        # никуда не едет ни в ту, ни в другую сторону.
        {:noreply, put_build(socket, build)}

      :error ->
        {:noreply, socket}
    end
  end

  # A domain chip's click means one of three things, and `Rules.ClassChoices.
  # click/4` is the single place that decides which: take a held value back
  # (always legal, same as clearing a feat slot), add a fresh one outright,
  # or — a `count == 1` choice already full, задача 3.171, Dan: «не
  # блокировать другие школы, просто выделить ту что выбрали, с
  # возможностью выбрать другую» — REPLACE the one held value with the
  # clicked one, a radio button rather than a capped list. This handler only
  # turns that answer into the matching `Build` primitive; it never
  # re-derives which one applies.
  #
  # ⚠️ No slot, no second step — unlike a feat with a parameter, a class's
  # choice does not sit *in* anything, so there is nothing to open first
  # (CLAUDE.md §6's slot model is about feats; this is `Rules.ClassChoices`,
  # a deliberately simpler mechanism — see its moduledoc).
  #
  # ⚠️ Параметр называется `choice`, а НЕ `value` — та же ловушка, что
  # у второго шага фита (см. `pick_choice`): `<button>` несёт родное свойство
  # `value`, браузер шлёт его пустым и затирает `phx-value-*` с тем же именем.
  def handle_event("toggle_class_choice", %{"class" => class, "choice" => value}, socket) do
    %{ruleset: ruleset, build: %Build{} = build} = socket.assigns

    with {:ok, class_id} <- Ids.fetch(ruleset, :classes, class),
         {:ok, value_id} <- Ids.fetch_class_choice(ruleset, class_id, value) do
      build =
        case ClassChoices.click(build, class_id, value_id, ruleset) do
          :toggle -> Build.toggle_class_choice(build, class_id, value_id)
          :replace -> Build.replace_class_choice(build, class_id, value_id)
          {:error, _reasons} -> build
        end

      {:noreply, put_build(socket, build)}
    else
      _ -> {:noreply, socket}
    end
  end

  # Выбор для фита, который класс ВЫДАЛ (задача 3.26): у выдачи нет слота, поэтому
  # нет и второго шага — чип пишет значение сразу, ровно как чип домена клирика
  # выше. Повторный клик по выбранному снимает его: забрать свой выбор законно
  # всегда, как законно освободить слот.
  #
  # ⚠️ Параметр снова называется `choice`, а не `value` — та же ловушка родного
  # свойства `<button value>`, что у `pick_choice` и `toggle_class_choice`.
  def handle_event("toggle_granted_choice", %{"feat" => feat, "choice" => value}, socket) do
    %{ruleset: ruleset, build: %Build{} = build, active: active} = socket.assigns

    with {:ok, feat_id} <- Ids.fetch(ruleset, :feats, feat),
         {:ok, choice} <- Ids.fetch_choice(ruleset, feat_id, value) do
      if Build.granted_choice(build, active, feat_id) == choice do
        {:noreply, put_build(socket, Build.put_granted_choice(build, active, feat_id, nil))}
      else
        put_granted_choice(socket, build, active, feat_id, choice)
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("pick_feat", %{"feat" => feat}, socket) do
    %{ruleset: ruleset, build: %Build{} = build, active: active, feat_slot: filter} =
      socket.assigns

    with {:ok, id} <- Ids.fetch(ruleset, :feats, id_or_nil(feat)),
         slot when not is_nil(slot) <- target_slot(ruleset, build, active, filter, id) do
      # ⚠️ Фит с параметром в слот НЕ кладётся первым же кликом. Пик без
      # записанного выбора неотличим от другого такого же — ровно то, чего
      # слотовая модель не допускает (CLAUDE.md §6), — и ядро отбило бы его
      # `{:requires_choice, …}`. Поэтому клик открывает второй шаг, а билд
      # до ответа не меняется вовсе.
      case Feats.choice_options(ruleset, build, active, id, slot.id) do
        nil -> {:noreply, put_feat(socket, build, active, slot.id, id, nil)}
        _options -> {:noreply, open_choice(socket, id, slot.id, active)}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  # ⚠️ Ключ `"choice"`, а не `"value"`: у `<button>` есть родное свойство
  # `value`, браузер шлёт его пустым и затирает наш `phx-value-*`.
  # `Phoenix.LiveViewTest` этого не воспроизводит — он читает только
  # `phx-value-*`, поэтому баг жил при зелёных тестах (02.08.2026).
  def handle_event("pick_choice", %{"choice" => value}, socket) do
    %{ruleset: ruleset, build: %Build{} = build, feat_choice: pending} = socket.assigns

    with %{feat: id, slot: slot_id, level: level} <- pending,
         {:ok, choice} <- Ids.fetch_choice(ruleset, id, value),
         # Последняя проверка — у ядра, а не у списка: список нарисован до
         # клика, а между отрисовкой и кликом билд мог поменяться.
         :ok <-
           Rules.validate_feat_pick(
             build,
             %{feat: id, choice: choice, at: level, slot: slot_id},
             ruleset
           ) do
      {:noreply,
       socket
       |> assign(:feat_choice, nil)
       |> put_feat(build, level, slot_id, id, choice)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_choice", _params, socket) do
    {:noreply, socket |> assign(:feat_choice, nil) |> refresh()}
  end

  def handle_event("clear_slot", %{"slot" => slot}, socket) do
    %{ruleset: ruleset, build: %Build{} = build, active: active} = socket.assigns

    case Ids.fetch_slot(ruleset, slot) do
      {:ok, slot_id} ->
        at_level = build.feats |> Map.get(active, %{}) |> Map.delete(slot_id)

        feats =
          if at_level == %{},
            do: Map.delete(build.feats, active),
            else: Map.put(build.feats, active, at_level)

        {:noreply, socket |> assign(:feat_choice, nil) |> put_build(%Build{build | feats: feats})}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("filter_slot", %{"slot" => slot}, socket) do
    case Ids.fetch_slot(socket.assigns.ruleset, slot) do
      {:ok, slot_id} ->
        next = if socket.assigns.feat_slot == slot_id, do: nil, else: slot_id
        {:noreply, socket |> assign(:feat_slot, next) |> refresh()}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("feat_search", params, socket) do
    {:noreply, socket |> assign(:feat_query, params["q"] || "") |> refresh()}
  end

  def handle_event("feat_type", %{"type" => type}, socket) when is_binary(type) do
    {:noreply, socket |> assign(:feat_type, type) |> refresh()}
  end

  def handle_event("skill_rank", %{"skill" => skill, "delta" => delta}, socket) do
    with {:ok, id} <- Ids.fetch(socket.assigns.ruleset, :skills, skill),
         {step, ""} <- Integer.parse(delta) do
      {:noreply, put_build(socket, buy_ranks(socket.assigns, id, step))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("skill_max", %{"skill" => skill}, socket) do
    case Ids.fetch(socket.assigns.ruleset, :skills, skill) do
      {:ok, id} -> {:noreply, put_build(socket, buy_ranks(socket.assigns, id, :max))}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("toggle_skill_add", _params, socket) do
    {:noreply, socket |> assign(:skill_add?, not socket.assigns.skill_add?) |> refresh()}
  end

  def handle_event("skill_search", params, socket) do
    {:noreply, socket |> assign(:skill_query, params["q"] || "") |> refresh()}
  end

  # ⚠️ Задача 3.18: раньше умолчание брали из `section_default/2` — «щёлкнуть
  # по уже свёрнутой самой собой секции значит раскрыть её». Умолчание стало
  # «открыто», и клик теперь всегда переворачивает то, что игрок видит.
  def handle_event("toggle_section", %{"key" => key}, socket) when is_binary(key) do
    open? = section_open?(socket.assigns, key)

    {:noreply,
     socket |> assign(:sections, Map.put(socket.assigns.sections, key, not open?)) |> refresh()}
  end

  def handle_event("preview", %{"kind" => kind, "id" => id}, socket) do
    ruleset = socket.assigns.ruleset

    preview =
      case kind do
        "class" -> with({:ok, v} <- Ids.fetch(ruleset, :classes, id), do: {:class, v})
        "race" -> with({:ok, v} <- Ids.fetch(ruleset, :races, id), do: {:race, v})
        "increase" -> with({:ok, v} <- Ids.fetch(ruleset, :abilities, id), do: {:increase, v})
        _ -> :error
      end

    cond do
      preview == :error -> {:noreply, socket}
      # `mouseover` fires again for every child the pointer crosses, so the
      # hook that now sends this (`.Preview`, see the template) can repeat
      # itself; without this the same preview would be recomputed several
      # times per card. ⚠ The hook filters by id too — both halves are
      # deliberate: the client stops the traffic, this stops the work, and
      # neither is a substitute for the other if the other is edited.
      preview == socket.assigns.preview -> {:noreply, socket}
      true -> {:noreply, socket |> assign(:preview, preview) |> refresh()}
    end
  end

  def handle_event("clear_preview", _params, socket) do
    if socket.assigns.preview,
      do: {:noreply, socket |> assign(:preview, nil) |> refresh()},
      else: {:noreply, socket}
  end

  # Задача 3.157 — единственный сервер-читатель галочки «Режим гида»
  # (`.GuidedMode` в шаблоне, `#guided-toggle-input`). Хук шлёт это на
  # монтировании (подравнивает сокет под `localStorage`, где живёт настоящее
  # состояние) и на каждый клик; сам билд и код в URL не трогает — только
  # `guide_scroll/2` внутри `put_build/2` читает этот флаг, ничего больше
  # от него не зависит, поэтому `refresh/1` не нужен.
  def handle_event("set_guided_mode", %{"value" => value}, socket) when is_boolean(value) do
    {:noreply, assign(socket, :guided_mode, value)}
  end

  def handle_event("toggle_gaps", _params, socket) do
    {:noreply, assign(socket, :gaps_open?, not socket.assigns.gaps_open?)}
  end

  def handle_event("toggle_gear", _params, socket) do
    {:noreply, socket |> assign(:gear_open?, not socket.assigns.gear_open?) |> refresh()}
  end

  # Клик по сводке предупреждений «Вещей» (задача 3.133, `GearPanel.
  # gear_issues/2`) — тот же приём, что у `jump_to_gap/2`: ОТКРЫТЬ нужный
  # блок и подвезти экран к контролу, а не только патчить состояние. Без
  # `assign(:gear_open?, true)` клик по сводке при свёрнутых «Вещах» бил бы
  # в пустоту — `scroll_to_section` ищет узел, которого ещё нет в DOM
  # (`.ScrollBus`, `builder_live.html.heex`: «событие приходит вместе
  # с ответом, когда нужная секция уже в DOM» — этот ответ обязан её нести).
  #
  # ⚠️ Не toggle, а безусловное `true`: сводка всегда хочет ПОКАЗАТЬ, а не
  # переключить, — повторный клик по той же находке не обязан закрывать блок.
  #
  # 🔴 Хвост задачи 3.134 (проверка координатора 28.08.2026): ЭТОГО `assign`
  # достаточно на десктопе (`.stats` там `position: sticky`, вся панель
  # видна целиком, у неё нет своего «свёрнуто/развёрнуто»), но НЕ на
  # мобильном — там «Итого» ЕЩЁ ОДНА шторка, отдельная от `gear_open?`
  # (`#totals-panel[data-open]`, `< 940px`), и она живёт ЦЕЛИКОМ на клиенте:
  # переключает её JS-команда на `#sheet-toggle`, сервер о её состоянии
  # не знает вовсе. Без второй половины (`gear_issue_jump/1` в шаблоне)
  # счёт был верным (`gear_open?` → true, `ScrollBus` двигал `scrollTop`
  # контейнера туда, куда нужно), а показать было нечего: шторка оставалась
  # свёрнутой, и прокрутка внутри неё проходила НЕВИДИМО, в полосе высотой
  # `--sheet-h` (~88px) под кнопкой-сводкой чисел, а не в развёрнутой
  # панели — замер headless Chrome с `mobile: true`, скриншот до/после
  # клика: контейнер после клика показывает обрывок строки щита в той же
  # свёрнутой полосе, где секунду назад стояли HP/AC/AB.
  def handle_event("jump_to_gear_issue", %{"target" => target}, socket) do
    {:noreply,
     socket
     |> assign(:gear_open?, true)
     |> refresh()
     |> push_event("scroll_to_section", %{id: target})}
  end

  # One form for four number/choice groups: the whole set is rewritten on
  # every keystroke, so what the panel above shows is always what was typed.
  #
  # ⚠️ Обновляется СУЩЕСТВУЮЩИЙ набор, а не собирается новый через `Gear.new/1`,
  # и это не стилистика. У вещей есть части, которых в ЭТОЙ форме нет: фиты
  # с вещи (кнопки, не поля), прибавки к навыкам и оба числа оружия (свои формы
  # в другом месте разметки, потому что вложенных `<form>` в HTML не бывает —
  # рядом с ними живёт поиск). `Gear.new/1` подставил бы им дефолты, то есть
  # первое же нажатие в поле CON молча стирало бы объявленный фит вместе со
  # всеми его прибавками. Каждая форма и каждая кнопка переписывает **только
  # своё**.
  #
  # ⚠️ Задача 3.134 (Dan: «АБ от оружия вбивается в одном месте, а само оружие
  # выбирается в другом»): оба числа оружия отсюда УЕХАЛИ в `"gear_weapon_attack"`
  # и `"gear_off_weapon_attack"` — своя форма рядом с самим оружием, тем же
  # приёмом, что уже был у навыков с вещи. Раньше здесь стоял `weapon =
  # params["weapon"] || %{}`; в браузере это было безопасно, потому что все
  # поля `#gear-form` сериализуются форматом ОДНИМ куском на любое изменение
  # внутри — но именно поэтому вынести число оружия в СВОЮ форму, оставив его
  # читаться тут, значило бы стирать характеристики/AC/сейвы при каждой правке
  # AB (и наоборот): у отдельной формы своих полей не было бы в этом `params`
  # вовсе, а `gear_numbers/3`/`gear_number/1` от `nil` отдают пустой набор/0.
  def handle_event("gear", params, socket) do
    %{ruleset: ruleset, build: %Build{gear: %Gear{} = gear} = build} = socket.assigns

    gear = %Gear{
      gear
      | abilities: gear_numbers(ruleset, :abilities, params["ability"]),
        ac: gear_numbers(ruleset, :ac_types, params["ac"]),
        # Надетое (задача 3.41) — выбор из списка, а не число, но живёт в ЭТОЙ
        # же форме: `<select>` шлёт `phx-change` тем же событием, что и поля.
        # Отдельной кнопкой, как оружие, он быть не может — там выбор из 41
        # строки с причинами отказа, а тут из девяти и трёх без единого отказа.
        worn: gear_worn(ruleset, params["worn"]),
        saves: gear_number(params["saves"])
    }

    {:noreply, put_build(socket, %Build{build | gear: gear})}
  end

  # Прибавки к навыкам — своя форма и своё событие, потому что рядом с ними
  # стоит поиск, а `<form>` внутри `<form>` браузер выбрасывает. Переписывается
  # ровно `skills`: остальные части набора эта форма не видит и не трогает.
  #
  # ⚠️ Все id из формы попадают в `gear_skill_open`, а не только ненулевые.
  # Ноль в билд не пишется (`gear_numbers/3` его отбрасывает, и кодировка тоже),
  # поэтому без этого строка исчезала бы в тот момент, когда игрок стёр число,
  # чтобы набрать другое.
  def handle_event("gear_skill", params, socket) do
    %{ruleset: ruleset, build: %Build{gear: %Gear{} = gear} = build} = socket.assigns
    typed = params["skill"]

    open =
      MapSet.union(
        socket.assigns.gear_skill_open,
        MapSet.new(gear_param_ids(ruleset, :skills, typed))
      )

    {:noreply,
     socket
     |> assign(:gear_skill_open, open)
     |> put_build(%Build{
       build
       | gear: %Gear{gear | skills: gear_numbers(ruleset, :skills, typed)}
     })}
  end

  # Строка навыка появляется без числа: писать в билд ноль нельзя (это не
  # прибавка, а её отсутствие), а поле ввода игроку нужно уже сейчас.
  def handle_event("add_gear_skill", %{"skill" => skill}, socket) do
    case Ids.fetch(socket.assigns.ruleset, :skills, skill) do
      {:ok, id} ->
        {:noreply,
         socket
         |> assign(:gear_skill_open, MapSet.put(socket.assigns.gear_skill_open, id))
         |> refresh()}

      :error ->
        {:noreply, socket}
    end
  end

  # Снятие — и число из билда, и строка из интерфейса. Одно без другого оставило
  # бы либо невидимую прибавку, либо строку, которую нельзя убрать.
  def handle_event("drop_gear_skill", %{"skill" => skill}, socket) do
    %{ruleset: ruleset, build: %Build{gear: %Gear{} = gear} = build} = socket.assigns

    case Ids.fetch(ruleset, :skills, skill) do
      {:ok, id} ->
        skills = Map.delete(gear.skills, id)

        {:noreply,
         socket
         |> assign(:gear_skill_open, MapSet.delete(socket.assigns.gear_skill_open, id))
         |> put_build(%Build{build | gear: %Gear{gear | skills: skills}})}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_gear_skill_add", _params, socket) do
    {:noreply,
     socket |> assign(:gear_skill_add?, not socket.assigns.gear_skill_add?) |> refresh()}
  end

  def handle_event("gear_skill_search", params, socket) do
    {:noreply, socket |> assign(:gear_skill_query, params["q"] || "") |> refresh()}
  end

  # Один обработчик на «надеть» и «снять» — это `Gear.toggle_feat/3` и есть
  # (ядро держит список отсортированным и уникальным, чтобы код ссылки у одного
  # билда был один и тот же).
  #
  # ⚠️ Проверка — `Rules.validate_gear_feat/2`, а НЕ то, что принимает слот.
  # Фит с вещи слота не занимает, требований персонажа не проверяет и не обязан
  # быть общим: `Riding Sprint` и `Smile of Death` слотом не берутся вовсе
  # (`{:not_selectable_at_level_up, …}`), а с предмета приходят — и это
  # единственный путь, которым они попадают в билд.
  #
  # ⚠️ Снятие идёт БЕЗ проверки: объявление, которое ядро отбивает
  # (`{:feat_disabled, …}` у ссылки, выпущенной до того, как шард выключил фит),
  # обязано сниматься — иначе билд из старой ссылки не починить.
  #
  # 🔴 Задача 3.97, заход 2: с записью-парой снятие обязано называть, КАКУЮ
  # именно запись снимать — `phx-value-choice` есть только у «×» уже выбранной
  # строки (список добавления и «×» ещё пустой строки его не шлют вовсе, и это
  # разводит два случая без явного if в шаблоне). Добавление по-прежнему кладёт
  # только ГОЛЫЙ id: записать значение сразу — работа `pick_gear_feat_choice`
  # ниже, у которой есть на это своя проверка (`validate_gear_feat_choice/4`).
  def handle_event("toggle_gear_feat", %{"feat" => feat} = params, socket) do
    %{ruleset: ruleset, build: %Build{gear: %Gear{} = gear} = build} = socket.assigns

    with {:ok, id} <- Ids.fetch(ruleset, :feats, id_or_nil(feat)),
         {:ok, choice} <- gear_feat_toggle_choice(ruleset, id, params["choice"]) do
      entry = if choice, do: {id, choice}, else: id

      # Снятие уже записанного (голого или с парой) не спрашивает ядро вообще
      # — та же безусловность, что была у голого снятия. Добавление нового
      # проходит через `validate_gear_feat/2`, и только для ГОЛОЙ формы:
      # `choice` сюда никогда не приходит с добавляющего клика (см. выше).
      if entry in gear.feats or (is_nil(choice) and Rules.validate_gear_feat(id, ruleset) == :ok) do
        {:noreply, put_build(socket, %Build{build | gear: Gear.toggle_feat(gear, id, choice)})}
      else
        {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_gear_feat_add", _params, socket) do
    {:noreply, socket |> assign(:gear_feat_add?, not socket.assigns.gear_feat_add?) |> refresh()}
  end

  def handle_event("gear_feat_search", params, socket) do
    {:noreply, socket |> assign(:gear_feat_query, params["q"] || "") |> refresh()}
  end

  # Второй шаг фита с вещи (задача 3.97, заход 2) — тот же вопрос, что у
  # выдачи класса (`toggle_granted_choice`), просто без уровня и без слота:
  # запись живёт в `gear.feats`, а не в карте по уровням, и записей одного
  # фита может быть несколько (решение Дана: «разные значения — разные
  # записи»). Ключ запроса — id фита: голая запись, которая ждёт значение,
  # всегда ровно одна на фит (`Gear.toggle_feat/3` не даёт завестись второй).
  def handle_event("gear_feat_choice_search", %{"feat" => feat} = params, socket) do
    case Ids.fetch(socket.assigns.ruleset, :feats, feat) do
      {:ok, id} ->
        queries = Map.put(socket.assigns.gear_feat_choice_query, id, params["q"] || "")
        {:noreply, socket |> assign(:gear_feat_choice_query, queries) |> refresh()}

      :error ->
        {:noreply, socket}
    end
  end

  # Записывает значение для ГОЛОГО объявления — снимает голую запись (если она
  # есть) и кладёт пару, одним движением. `Gear.toggle_feat/3` — переключатель,
  # а не «положить»: не убрать голую запись перед добавлением пары значило бы
  # оставить рядом бесхозный дубль того же фита, который тут же снова попросил
  # бы значение.
  #
  # ⚠️ Проверок ДВЕ, и вторая — не «на всякий случай». `Gear.feats` уникален
  # по паре, и запись ТОЙ ЖЕ пары ещё раз не добавит вторую копию, а СНИМЕТ
  # первую (`Gear.toggle_feat/3`). Ядро это не запрещает — у
  # `epic_energy_resistance` `distinct?: false` разрешает то же значение
  # снова (Дан, 02.08.2026: «на один тип урона, не более 10 раз», а не «не
  # более одного»), — так что без этой строки повторный клик по уже
  # объявленному значению тихо стёр бы его. `GearPanel` эту же пару кнопкой
  # не предлагает (`gear_choice_value_reason/3`), но список нарисован до
  # клика, а между отрисовкой и кликом билд мог поменяться — тот же довод,
  # что у `pick_choice`.
  def handle_event("pick_gear_feat_choice", %{"feat" => feat, "choice" => value}, socket) do
    %{ruleset: ruleset, build: %Build{gear: %Gear{} = gear} = build} = socket.assigns

    with {:ok, id} <- Ids.fetch(ruleset, :feats, feat),
         {:ok, choice} <- Ids.fetch_choice(ruleset, id, value),
         false <- {id, choice} in gear.feats,
         :ok <- Rules.validate_gear_feat_choice(build, ruleset, id, choice) do
      gear = if id in gear.feats, do: Gear.toggle_feat(gear, id), else: gear
      gear = Gear.toggle_feat(gear, id, choice)

      {:noreply,
       socket
       |> assign(:gear_feat_choice_query, Map.delete(socket.assigns.gear_feat_choice_query, id))
       |> put_build(%Build{build | gear: gear})}
    else
      _ -> {:noreply, socket}
    end
  end

  # ---- вторая рука: обработчики делят тело, не только имя (3.138, П3) ----
  #
  # Раньше тело каждой пары повторялось до буквы, с разницей только в имени
  # поля гира/ассайна. Форма уже была известна и жила рядом (`GearPanel`
  # решает те же вопросы одной функцией с клаузами `weapon_add?(_, :main)` /
  # `(_, :off)`, `Rules.validate_gear_weapon/4` уже принимает `hand`) — здесь
  # она доехала до LiveView: тело каждой пары ниже общее, `hand` решает поле
  # и ассайн. События и их имена не меняются — шаблон (заход П4) шлёт их по
  # строке и читает ассайн плоско (`@gear_weapon_add?` / `@gear_off_weapon_add?`).

  # AB каждой руки (задача 3.134): своя форма рядом с самим оружием на
  # экране, а не общий `#gear-form` за 210 строк разметки — тем же приёмом,
  # что уже у навыков с вещи (`"gear_skill"` выше). Переписывается РОВНО
  # своё поле гира: эта форма не несёт ни характеристик, ни AC, ни сейвов,
  # и `"gear"` больше не читает `params["weapon"]` вовсе (см. её же
  # комментарий выше) — обе формы не видят чужих полей, значит и стереть их
  # не могут.
  def handle_event("gear_weapon_attack", params, socket),
    do: handle_gear_weapon_attack(:main, params, socket)

  def handle_event("gear_off_weapon_attack", params, socket),
    do: handle_gear_weapon_attack(:off, params, socket)

  # Оружие в руках (задача 3.5, часть B). Один обработчик на «взять» и
  # «снять», как у фита с вещи: повторный клик по выбранному снимает его.
  #
  # ⚠️ Проверка — `Rules.validate_gear_weapon/4`, и она про ЭТОГО персонажа:
  # список фильтруется по взятым фитам владения (Dan 10.08.2026). Снятие
  # идёт БЕЗ проверки — оружие, потерявшее основание (игрок убрал фит
  # владения), обязано сниматься, иначе билд из старой ссылки не починить.
  #
  # ⚠️ Обе руки — задача 3.132: `validate_gear_weapon/4` принимает `hand`
  # (главная зовёт с `:main`, вторая — с `:off`, вместо прежнего умолчания).
  # Щит эта проверка не спрашивает вовсе — взаимное исключение решено
  # В ПОЛЬЗУ ОРУЖИЯ (`Rules.Worn`, Dan: «щит и второе оружие одновременно
  # взять нельзя»), и отказ достаётся щиту, а не оружию: щит просто
  # перестаёт засчитываться и называет причину сам (`@gear.worn_illegal`),
  # ровно как уже происходит с двуручным оружием в главной руке.
  def handle_event("pick_gear_weapon", %{"weapon" => weapon}, socket),
    do: pick_gear_weapon(:main, weapon, socket)

  def handle_event("pick_gear_off_weapon", %{"weapon" => weapon}, socket),
    do: pick_gear_weapon(:off, weapon, socket)

  # Снятие оружия числа НЕ стирает: игрок меняет скимитар на длинный меч
  # (или катану на короткий меч во второй руке), и заново вбивать «+5» —
  # лишнее движение. Числа без оружия и так ни во что не идут
  # (`Rules.GearWeapon.attack_terms/2` возвращает пусто).
  def handle_event("drop_gear_weapon", _params, socket),
    do: drop_gear_weapon(:main, socket)

  def handle_event("drop_gear_off_weapon", _params, socket),
    do: drop_gear_weapon(:off, socket)

  def handle_event("toggle_gear_weapon_add", _params, socket),
    do: toggle_gear_weapon_add(:main, socket)

  def handle_event("toggle_gear_off_weapon_add", _params, socket),
    do: toggle_gear_weapon_add(:off, socket)

  def handle_event("gear_weapon_search", params, socket),
    do: gear_weapon_search(:main, params, socket)

  def handle_event("gear_off_weapon_search", params, socket),
    do: gear_weapon_search(:off, params, socket)

  def handle_event("clear_gear", _params, socket) do
    %Build{} = build = socket.assigns.build

    # Открытые строки забываем, а списки добавления оставляем как были: «сбросить»
    # — это про содержимое, и захлопывать под игроком поиск, который он только
    # что открыл, значило бы сделать за него ещё одно движение.
    {:noreply,
     socket
     |> assign(:gear_skill_open, MapSet.new())
     |> put_build(%Build{build | gear: %Gear{}})}
  end

  def handle_event("pick_spell", %{"spell" => spell}, socket) do
    %{ruleset: ruleset, build: %Build{} = build, active: active} = socket.assigns

    with {:ok, id} <- Ids.fetch(ruleset, :spells, spell),
         slot when not is_nil(slot) <- open_spell_slot(socket.assigns, id) do
      at_level = build.spells |> Map.get(active, %{}) |> Map.put(slot.id, id)

      {:noreply,
       put_build(socket, %Build{build | spells: Map.put(build.spells, active, at_level)})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear_spell", %{"slot" => slot}, socket) do
    %{build: %Build{} = build, active: active} = socket.assigns

    case Ids.fetch_spell_slot(slot) do
      {:ok, slot_id} ->
        at_level = build.spells |> Map.get(active, %{}) |> Map.delete(slot_id)

        spells =
          if at_level == %{},
            do: Map.delete(build.spells, active),
            else: Map.put(build.spells, active, at_level)

        {:noreply, put_build(socket, %Build{build | spells: spells})}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("spell_search", params, socket) do
    {:noreply, socket |> assign(:spell_query, params["q"] || "") |> refresh()}
  end

  # ------------------------------------------------------------ short link --
  #
  # Длинная ссылка остаётся канонической и остаётся первой: билд живёт внутри
  # неё и переживёт нашу базу. Короткая только дополняет её — и в интерфейсе
  # честно сказано, что она живёт, пока жива запись.
  #
  # ⚠️ Предел на СОЕДИНЕНИЕ, а не на IP: за Caddy приложение видит адрес
  # прокси у каждого посетителя (`config/prod.exs` переписывает только
  # `:x_forwarded_proto`), так что счётчик «по IP» сложил бы всех игроков
  # в одно ведро. Этот предел — страховка от зациклившегося клиента, а не
  # от бота; от бота защищает дедупликация (`BuildCalculator.ShortLinks`).
  # Повторное нажатие на том же билде сюда не доходит вовсе: кнопки на экране
  # нет, пока ссылка уже выдана, — а если событие всё же придёт (устаревший
  # DOM), память отвечает на него без похода в базу.
  def handle_event("short_link", _params, socket) do
    %{code: code, short_links: made} = socket.assigns

    cond do
      Map.has_key?(made, code) ->
        {:noreply, socket}

      map_size(made) >= @short_links_per_socket ->
        {:noreply, put_flash(socket, :error, Labels.short_link_error(:too_many))}

      true ->
        case ShortLinks.shorten(code) do
          {:ok, %{key: key}} ->
            made = Map.put(made, code, key)

            {:noreply, socket |> assign(:short_links, made) |> assign(:short_key, key)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, Labels.short_link_error(reason))}
        end
    end
  end

  def handle_event("export", _params, socket) do
    {:noreply, socket |> assign(:export_open?, true) |> assign(:export_text, export_text(socket))}
  end

  def handle_event("close_export", _params, socket) do
    {:noreply, assign(socket, :export_open?, false)}
  end

  # Задача 3.146 — сам чекбокс несёт только своё состояние; текст в
  # `#export-text` обязан обновиться в том же ответе, иначе игрок увидит
  # переключившийся переключатель и прежний текст под ним до следующего
  # события.
  def handle_event("toggle_export_granted", _params, socket) do
    socket = assign(socket, :export_show_granted?, not socket.assigns.export_show_granted?)
    {:noreply, assign(socket, :export_text, export_text(socket))}
  end

  # ---------------------------------------------------------------- import --
  #
  # The import lives here, beside the export, and not on a screen of its own:
  # it is the same dialog about the same text format, and the place a pasted
  # build has to land is this constructor — with the report saying what did not
  # read, and the level it did not read on one click away.
  #
  # Two steps, always: paste, then read the report, then accept. Nothing is
  # applied to the build the player already has until they say so.
  def handle_event("open_import", _params, socket) do
    {:noreply, assign(socket, :import_open?, true)}
  end

  def handle_event("close_import", _params, socket) do
    {:noreply, assign(socket, :import_open?, false)}
  end

  # Отчёт описывает КОНКРЕТНЫЙ текст, поэтому переживает только его. Стоило бы
  # оставить старый разбор рядом с изменённой вставкой — и человек принимал бы
  # решение по числам, которых в окне уже нет.
  def handle_event("import_change", params, socket) do
    text = ImportPanel.import_text(params)
    stale? = match?(%{text: parsed} when parsed != text, socket.assigns.import_report)

    {:noreply,
     socket
     |> assign(:import_form, ImportPanel.import_form(text))
     |> assign(:import_report, if(stale?, do: nil, else: socket.assigns.import_report))}
  end

  def handle_event("import_parse", params, socket) do
    text = ImportPanel.import_text(params)
    result = Import.parse(text, socket.assigns.ruleset)

    {:noreply,
     socket
     |> assign(:import_form, ImportPanel.import_form(text))
     |> assign(:import_report, ImportPanel.import_report(result, text, socket.assigns.ruleset))}
  end

  def handle_event("import_apply", _params, socket) do
    case socket.assigns.import_report do
      %{result: %{build: %Build{} = build, title: title, issues: issues}} ->
        ruleset = socket.assigns.ruleset
        taken = Build.character_level(build)

        {:noreply,
         socket
         |> assign(:import_open?, false)
         |> assign(:build_title, title)
         |> assign(
           :active,
           clamp_level(taken + 1, level_ceiling(build, taken), ruleset.level_cap)
         )
         |> assign(:hold, nil)
         |> assign(:sections, %{})
         |> assign(:feat_slot, nil)
         |> assign(:preview, nil)
         |> forget_gear_ui()
         |> put_flash(:info, ImportPanel.import_flash(issues))
         # ⚠️ В отличие от ссылки (решение 1.7), импорт УЖЕ шёл через эту
         # воронку и до задачи 3.17 (ради `enforce_floor/2`) — значит и новый
         # сброс распределения применится к нему точно так же, если чужой
         # текст принёс нелегальную покупку. `put_build/2` сам решит и сам
         # выставит `:point_buy_reset`, ничего доопределять здесь не нужно.
         |> put_build(build)}

      _ ->
        {:noreply, socket}
    end
  end

  # ---------------------------------------------------------- game log import --
  #
  # Задача 3.111, заход 2: своё же приключение персонажа из клиентского лога
  # команды `.билд`, а не чужой билд с форума — другой источник, другой
  # разбор (`GameLogImport`, а не `Import`), но то же двухшаговое окно
  # (вставил → увидел отчёт → принял), потому что вопрос у игрока тот же:
  # что из вставленного текста реально доехало.
  def handle_event("open_game_log_import", _params, socket) do
    {:noreply, assign(socket, :game_log_import_open?, true)}
  end

  def handle_event("close_game_log_import", _params, socket) do
    {:noreply, assign(socket, :game_log_import_open?, false)}
  end

  def handle_event("game_log_import_change", params, socket) do
    text = GameLogImportPanel.text(params)

    stale? =
      match?(%{text: parsed} when parsed != text, socket.assigns.game_log_import_report)

    {:noreply,
     socket
     |> assign(:game_log_import_form, GameLogImportPanel.form(text))
     |> assign(
       :game_log_import_report,
       if(stale?, do: nil, else: socket.assigns.game_log_import_report)
     )}
  end

  def handle_event("game_log_import_parse", params, socket) do
    text = GameLogImportPanel.text(params)
    result = GameLogImport.parse(text, socket.assigns.ruleset)

    {:noreply,
     socket
     |> assign(:game_log_import_form, GameLogImportPanel.form(text))
     |> assign(
       :game_log_import_report,
       GameLogImportPanel.report(result, text, socket.assigns.ruleset)
     )}
  end

  def handle_event("game_log_import_apply", _params, socket) do
    case socket.assigns.game_log_import_report do
      %{result: %{build: %Build{} = build, title: title, issues: issues}} ->
        ruleset = socket.assigns.ruleset
        taken = Build.character_level(build)

        {:noreply,
         socket
         |> assign(:game_log_import_open?, false)
         |> assign(:build_title, title)
         |> assign(
           :active,
           clamp_level(taken + 1, level_ceiling(build, taken), ruleset.level_cap)
         )
         |> assign(:hold, nil)
         |> assign(:sections, %{})
         |> assign(:feat_slot, nil)
         |> assign(:preview, nil)
         |> forget_gear_ui()
         |> put_flash(:info, GameLogImportPanel.flash(issues))
         # Та же воронка, что у текстового импорта (см. комментарий там):
         # `put_build/2` сам решит про потолок поинт-бая и сам выставит
         # `:point_buy_reset`, если принудительная покупка не влезла.
         |> put_build(build)}

      _no_report_yet ->
        {:noreply, socket}
    end
  end

  def handle_event("reset", _params, socket) do
    ruleset = socket.assigns.ruleset

    {:noreply,
     socket
     |> assign(:active, 1)
     |> assign(:hold, nil)
     |> assign(:preview, nil)
     |> assign(:sections, %{})
     |> assign(:feat_query, "")
     |> assign(:feat_slot, nil)
     # Второй шаг выбора: `%{feat:, slot:, level:}`, пока игрок не назвал школу
     # (расу, навык). До этого в билд НИЧЕГО не пишется — см. `pick_feat`.
     |> assign(:feat_choice, nil)
     |> assign(:skill_add?, false)
     |> assign(:skill_query, "")
     |> assign(:build_title, nil)
     |> forget_gear_ui()
     # `put_build/2` ниже само пересчитает `:point_buy_reset` с нуля — на
     # пустом билде класса первого уровня нет, значит и сбрасывать нечего.
     |> put_build(empty_build(ruleset))}
  end

  # Один читатель `opts[:show_granted_feats]` (CLAUDE.md §9: две копии одного
  # правила расходятся) — `"export"` и `"toggle_export_granted"` оба зовут
  # это, а не собирают вызов `Export.text/4` каждый по-своему.
  defp export_text(socket) do
    Export.text(socket.assigns.build, socket.assigns.ruleset, socket.assigns.stats,
      show_granted_feats: socket.assigns.export_show_granted?
    )
  end

  # ------------------------------------------------------------- build edits --

  defp empty_build(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      base_abilities: PointBuy.starting_scores(ruleset)
    )
  end

  defp id_or_nil(value) when is_binary(value), do: value
  defp id_or_nil(_), do: nil

  # `params["choice"]` из `toggle_gear_feat`: отсутствует (`nil`) у добавления
  # и у снятия голой записи, строка — у снятия записи-пары. Оба случая честно
  # различены формой ответа `with` в вызывающем месте: `{:ok, nil}` — а не
  # `nil <- nil`, — потому что второй пункт `with` обязан выглядеть так же,
  # как у ветки со значением, а не быть особым случаем без пары.
  defp gear_feat_toggle_choice(_ruleset, _id, nil), do: {:ok, nil}
  defp gear_feat_toggle_choice(ruleset, id, value), do: Ids.fetch_choice(ruleset, id, value)

  # Gear numbers are whitelisted like every other id and never turned into atoms
  # by hand. The ceilings are the rules core's business, not the form's — the
  # form only refuses nonsense.
  defp gear_numbers(ruleset, kind, params) when is_map(params) do
    for {name, value} <- params,
        {:ok, id} <- [Ids.fetch(ruleset, kind, name)],
        number = gear_number(value),
        number != 0,
        into: %{},
        do: {id, number}
  end

  defp gear_numbers(_ruleset, _kind, _params), do: %{}

  # Надетое из формы: `%{"armor" => "full_plate", "shield" => ""}`. Обе половины
  # пары проходят белый список справочника (`Ids.fetch_worn/3`) — из браузера
  # приходит строка, и `String.to_atom/1` на ней утёк бы в таблицу атомов
  # (AGENTS.md).
  #
  # ⚠️ Пустая строка — это «не указано», и она не попадает в билд ключом со
  # значением `nil`: «снял» и «не выбирал» обязаны быть ОДНИМ состоянием, иначе
  # у одного билда получились бы два разных кода ссылки.
  defp gear_worn(ruleset, params) when is_map(params) do
    for {category, item} <- params,
        {:ok, category_id, item_id} <- [Ids.fetch_worn(ruleset, category, item)],
        into: %{},
        do: {category_id, item_id}
  end

  defp gear_worn(_ruleset, _params), do: %{}

  # ---- вторая рука: тела обработчиков выше (3.138, П3) --------------------

  defp handle_gear_weapon_attack(hand, params, socket) do
    %{build: %Build{gear: %Gear{} = gear} = build} = socket.assigns
    attack = gear_number(params["attack"])
    gear = Map.put(gear, Gear.weapon_bonus_field(:attack, hand), attack)

    {:noreply, put_build(socket, %Build{build | gear: gear})}
  end

  defp pick_gear_weapon(hand, weapon, socket) do
    %{ruleset: ruleset, build: %Build{gear: %Gear{} = gear} = build} = socket.assigns
    held = Gear.weapon(gear, hand)

    with {:ok, id} <- Ids.fetch(ruleset, :weapons, id_or_nil(weapon)),
         true <- held == id or Rules.validate_gear_weapon(build, id, ruleset, hand) == :ok do
      chosen = if held == id, do: nil, else: id

      {:noreply, put_build(socket, %Build{build | gear: gear_put_weapon(gear, hand, chosen)})}
    else
      _ -> {:noreply, socket}
    end
  end

  defp drop_gear_weapon(hand, socket) do
    %{build: %Build{gear: %Gear{} = gear} = build} = socket.assigns

    {:noreply, put_build(socket, %Build{build | gear: gear_put_weapon(gear, hand, nil)})}
  end

  # `Rules.Gear` знает читателя этой пары (`weapon/2`), но не писателя —
  # заводить его в `rules/` ради одной задачи веб-слоя не входит в заход П3
  # (границы §5 — это `dev-rules`). Две клаузы, зеркально `Gear.weapon/2`.
  defp gear_put_weapon(%Gear{} = gear, :main, id), do: %Gear{gear | weapon: id}
  defp gear_put_weapon(%Gear{} = gear, :off, id), do: %Gear{gear | off_hand_weapon: id}

  defp toggle_gear_weapon_add(hand, socket) do
    key = gear_weapon_add_key(hand)
    {:noreply, socket |> assign(key, not Map.fetch!(socket.assigns, key)) |> refresh()}
  end

  defp gear_weapon_add_key(:main), do: :gear_weapon_add?
  defp gear_weapon_add_key(:off), do: :gear_off_weapon_add?

  defp gear_weapon_search(hand, params, socket) do
    {:noreply, socket |> assign(gear_weapon_query_key(hand), params["q"] || "") |> refresh()}
  end

  defp gear_weapon_query_key(:main), do: :gear_weapon_query
  defp gear_weapon_query_key(:off), do: :gear_off_weapon_query

  # Состояние ИНТЕРФЕЙСА блока «Вещи»: строки навыков, открытые без числа, и оба
  # списка добавления с их запросами. Всё это принадлежит билду, который на
  # экране: открытая строка «Discipline» у другого билда не объясняет ничего,
  # а запрос в поиске — тем более. Поэтому забывается везде, где билд заменяется
  # ЦЕЛИКОМ: ссылкой, импортом, сбросом.
  #
  # Одной функцией на все три места намеренно: три руками написанных списка
  # одних и тех же ассайнов разошлись бы — ровно форма бага 1.2.
  defp forget_gear_ui(socket) do
    socket
    |> assign(:gear_skill_open, MapSet.new())
    |> assign(:gear_skill_add?, false)
    |> assign(:gear_skill_query, "")
    |> assign(:gear_feat_add?, false)
    |> assign(:gear_feat_query, "")
    # Задача 3.97, заход 2: поисковые запросы второго шага (значение фита
    # с вещи), по одному на объявленный, но не выбранный фит — та же природа,
    # что у `gear_feat_query` строкой выше, поэтому забывается тем же путём.
    |> assign(:gear_feat_choice_query, %{})
    |> assign(:gear_weapon_add?, false)
    |> assign(:gear_weapon_query, "")
    # Вторая рука (задача 3.132) — то же забывание, что у главной руки.
    |> assign(:gear_off_weapon_add?, false)
    |> assign(:gear_off_weapon_query, "")
  end

  # Какие строки формы вообще пришли — включая те, где набран ноль. Нужно ровно
  # там, где «поле есть, а числа нет» — законное состояние интерфейса: см.
  # `gear_skill_open` и событие `"gear_skill"`.
  defp gear_param_ids(ruleset, kind, params) when is_map(params) do
    for {name, _value} <- params, {:ok, id} <- [Ids.fetch(ruleset, kind, name)], do: id
  end

  defp gear_param_ids(_ruleset, _kind, _params), do: []

  # ⚠️ Минус проходит. Раньше стояло `max(0)`, и введённое `−2` молча
  # становилось нулём — а штрафы со шмота реальны и важны ровно там, где важен
  # калькулятор: `Ability cap` (revid 68173) прямо говорит, что штрафы понижают
  # кап (при STR −2 предметы дадут не больше +10 чистыми). Отбрасывать знак
  # значило считать билд не тот, что ввели.
  #
  # ±255 — это НЕ игровой потолок, а граница формы: она отсекает бессмыслицу
  # (мусор из буфера, залипшую цифру), и только. Игровые потолки живут в
  # `Rules.Caps` и в `priv/rules/` (CLAUDE.md §6) — своего числа форма не
  # выдумывает. Границы симметричны, потому что у штрафа нет причины иметь
  # другой предел, чем у бонуса: асимметрия здесь и была багом.
  @gear_input_limit 255

  # Тот же предел — публичным геттером, а не вторым числом: `Builder.GearPanel`
  # печатает его в `input_min`, а модульный атрибут виден только своему модулю
  # (задача 3.46, заход 4). Дублировать `255` во втором файле значило бы
  # завести две границы формы вместо одной.
  @doc false
  def gear_input_limit, do: @gear_input_limit

  defp gear_number(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, _rest} -> number |> max(-@gear_input_limit) |> min(@gear_input_limit)
      :error -> 0
    end
  end

  defp gear_number(_value), do: 0

  # Отображаемое значение числового поля «Вещей» — задача 3.63 (Dan, мобильный:
  # «дефолтно стоят нули и когда вводишь что-то, например „6“… получается „60“
  # за счёт нуля»). Поле несло РЕАЛЬНЫЙ символ «0» (`value={row.value}` при
  # нетронутом поле), и любой набранный символ приписывался к нему — на
  # телефоне курсор встаёт перед существующим текстом, а не выделяет его.
  #
  # `nil` — не пустая строка: HEEx опускает атрибут `value` целиком
  # (`Phoenix.HTML.attributes_escape/1` роняет пары со значением `nil`), то
  # есть поле рендерится без единого символа, а `placeholder="0"` рядом в
  # разметке несёт то же «сейчас 0», но не лежит в поле, куда печатает игрок.
  #
  # ⚠️ Raw `row.value` / `@gear.save_value` / `@gear.weapon_attack` остаются
  # целыми числами везде, где их читает КОД — `Builder.GearPanel.gear_summary/5`
  # фильтрует и форматирует их как числа (`&(&1.value != 0)`, `signed/1`),
  # а кодировка и потолки вообще не видят эту функцию. Поэтому подмена —
  # только в разметке, в самой точке `value={...}`, а не в сборке `@gear`:
  # перепиши она `row.value` там, `GearPanel.gear_summary/5` сравнивала бы
  # строку с числом и увидела бы ложное «не ноль» у только что стёртого поля.
  defp gear_input_value(0), do: nil
  defp gear_input_value(value), do: value

  # The narrowest free slot of the spell's own circle. A spell of circle 3 can
  # only go into a circle 3 slot — spell slots are no more interchangeable than
  # feat slots (CLAUDE.md §6).
  #
  # ⚠️ Круг, который персонаж не умеет кастовать, слота не получает вовсе
  # (задача 3.125): список рисуется до клика, а между отрисовкой и кликом
  # характеристика могла упасть — тот же довод, что у `put_granted_choice/4`
  # и `pick_choice`. Проверка спрашивает ЯДРО (`Spells.unmet_circles/5`),
  # а не читает подпись, которую сама же и нарисовала.
  defp open_spell_slot(assigns, spell_id) do
    %{ruleset: ruleset, build: build, active: level} = assigns
    filled = Map.get(build.spells, level, %{})
    circle = spell_circle(assigns, spell_id)
    class = Build.class_at(build, level)

    slots = Spells.slots_at(build, ruleset, level)

    if class && Spells.unmet_circles(build, ruleset, class, [circle], level) == %{} do
      Enum.find(slots, fn slot ->
        slot.circle == circle and not Map.has_key?(filled, slot.id)
      end)
    end
  end

  defp spell_circle(%{spell_circles: circles}, spell_id), do: Map.get(circles, spell_id)

  # Последняя проверка — у ядра, а не у списка: список нарисован до клика, а
  # между отрисовкой и кликом билд мог поменяться (тот же довод, что у
  # `pick_choice`).
  defp put_granted_choice(socket, build, level, feat_id, choice) do
    %{ruleset: ruleset} = socket.assigns

    case Rules.validate_granted_feat_choice(build, ruleset, feat_id, choice, level) do
      :ok ->
        {:noreply, put_build(socket, Build.put_granted_choice(build, level, feat_id, choice))}

      {:error, _reasons} ->
        {:noreply, socket}
    end
  end

  defp open_choice(socket, feat_id, slot_id, level) do
    socket
    |> assign(:feat_choice, %{feat: feat_id, slot: slot_id, level: level})
    |> assign(:sections, Map.put(socket.assigns.sections, "feats", true))
    |> refresh()
  end

  # Единственный путь записи фита в билд — и он же единственный, кто зовёт
  # `Build.put_feat/5`: при `choice == nil` тот кладёт голый атом, и от этого
  # зависит байтовая совместимость ссылок (`Encoding`).
  defp put_feat(socket, %Build{} = build, level, slot_id, feat_id, choice) do
    build = Build.put_feat(build, level, slot_id, feat_id, choice)

    socket |> assign(:feat_choice, nil) |> put_build(build)
  end

  defp target_slot(ruleset, build, level, filter, feat_id) do
    explicit =
      filter &&
        Enum.find(Feats.open_slots(ruleset, build, level), fn slot ->
          slot.id == filter and FeatSlots.accepts?(ruleset, slot, feat_id)
        end)

    explicit || Feats.best_slot(ruleset, build, level, feat_id)
  end

  # Changing a level's class can leave a feat sitting in a bonus slot that level
  # no longer grants. Dropping it is the only honest option: keeping it would be
  # an illegal build we would then go on to compute happily.
  defp prune_slots(build, ruleset, level) do
    kept =
      build.feats
      |> Map.get(level, %{})
      |> Map.take(Enum.map(FeatSlots.at(build, ruleset, level), & &1.id))

    feats =
      if kept == %{},
        do: Map.delete(build.feats, level),
        else: Map.put(build.feats, level, kept)

    %Build{build | feats: feats}
  end

  # ⚠️ Потолок ограничивает ПОКУПКУ НА ЭТОМ УРОВНЕ, а не итог: ранги, купленные
  # раньше, не отбираются, но и не дают докупать там, где класс уровня навык
  # не жалует (`Skills.rank_room/4`, наблюдение Дана 03.08.2026).
  defp buy_ranks(%{ruleset: ruleset, build: %Build{} = build, active: level}, skill, step) do
    here = build.skills |> Map.get(level, %{}) |> Map.get(skill, 0)
    cost = Skills.rank_cost(build, ruleset, skill, level)
    free = Skills.budget(build, ruleset, level).free

    room = min(Skills.rank_room(build, ruleset, skill, level) - here, div(free, cost))

    delta =
      case step do
        :max -> max(room, 0)
        n when n > 0 -> min(n, max(room, 0))
        n -> max(n, -here)
      end

    if delta == 0 do
      build
    else
      at_level = Map.get(build.skills, level, %{})
      ranks = here + delta

      at_level =
        if ranks <= 0, do: Map.delete(at_level, skill), else: Map.put(at_level, skill, ranks)

      skills =
        if at_level == %{},
          do: Map.delete(build.skills, level),
          else: Map.put(build.skills, level, at_level)

      %Build{build | skills: skills}
    end
  end

  # Every build change goes through here: recompute once, then mirror the build
  # into the URL so the address bar is always a shareable save.
  # -------------------------------------------------------- advancing levels --

  # «Уровень закрыт» — то есть все решения, без которых левелап не считается
  # законченным, приняты.
  #
  # ⚠️ Задача 3.30: у этого предиката СМЕНИЛСЯ ПОТРЕБИТЕЛЬ, а не формула.
  # Раньше он решал, пора ли автоматически перейти на следующий уровень
  # (`settle/2`, снят по решению Dan 15.08.2026). Теперь он никуда не двигает,
  # а отличает в ленте секций янтарное «держит уровень» от стального «можно
  # доделать» (`assign_stage_nav/1`) и питает `hold_note/4`. Ни одна строка
  # формулы при этом не изменилась — переписывать её под ленту было бы вторым
  # правилом там, где нужно одно.
  #
  # ⚠️ Условие живёт ЗДЕСЬ И ТОЛЬКО ЗДЕСЬ. Читателей у него теперь тоже
  # несколько, и три копии правила разъехались бы не сразу, а на четвёртом
  # читателе, которого кто-нибудь добавит потом.
  #
  # Что держит переход, а что нет (решение Дана, 02.08.2026):
  #
  #   * слоты фитов — держат: слот, оставленный пустым, теряется навсегда.
  #     ⚠️ Незакрытый ВТОРОЙ ШАГ выбора держит уровень тем же самым правилом
  #     и без единой новой строки здесь: пока школа не названа, в слот ничего
  #     не записано, и слот пуст. Заводить отдельное условие «а ещё не висит ли
  #     панель выбора» значило бы описать один факт дважды — а две записи
  #     одного факта разъезжаются (та же причина, по которой счётчик взятий
  #     не хранится рядом с пиками);
  #   * прибавка к характеристике — держит, на тех уровнях, где она даётся;
  #   * выбор класса (домены клирика, задача 3.14) — держит, но только на
  #     СОБСТВЕННОМ первом уровне класса и только если выбор обязателен
  #     (`ClassChoices.required?/2`); на всех остальных уровнях того же
  #     класса нечего ждать, выбор уже сделан раз и навсегда;
  #   * известные заклинания — НЕ держат. Соркерер выбирает их пачками (шесть
  #     штук на 1-м уровне), и ждать все шесть значило бы запирать игрока
  #     в самом частом сценарии;
  #   * навыки — не держат, как и раньше.
  defp level_settled?(ruleset, %Build{} = build, level) do
    slots = FeatSlots.at(build, ruleset, level)
    filled = Map.get(build.feats, level, %{})

    Enum.all?(slots, &Map.has_key?(filled, &1.id)) and
      (not MapSet.member?(ruleset.epic.ability_increase_levels, level) or
         Map.has_key?(build.ability_increases, level)) and
      class_choice_settled?(ruleset, build, level)
  end

  defp class_choice_settled?(ruleset, build, level) do
    with class when not is_nil(class) <- Build.class_at(build, level),
         1 <- Build.class_level_at(build, level) do
      ClassChoices.complete?(build, class, ruleset)
    else
      _ -> true
    end
  end

  # `hold` — уровень, на котором мы остались ждать решений, или `nil`. Он же
  # отличает «игрок сейчас поднимает уровень» от «игрок листает готовый билд»:
  # правка старого уровня никуда не перебрасывает, как и раньше.
  #
  # ⚠️ Задача 3.30: после снятия `settle/2` он уже ничего не переключает —
  # остался ровно один читатель, `hold_note/4`, то есть `hold` теперь значит
  # «показывать ли словами, что здесь осталось». На капе не держим вовсе,
  # и довод у этого стал другой: раньше «перейдём дальше сами» было бы
  # обещанием, которого некому исполнить, а теперь на капе просто нет
  # следующего уровня, к которому эта строка отправляла бы игрока.
  defp levelling_hold(%{ruleset: ruleset, active: active, hold: hold}, taken_before) do
    if active < ruleset.level_cap and (active > taken_before or hold == active),
      do: active,
      else: nil
  end

  # ⚠️ Задача 3.30 (решение Dan 15.08.2026): здесь жил `settle/2` —
  # единственная точка АВТОПЕРЕХОДА на следующий уровень. Он снят вместе
  # с хуком `.FocusPending`: оба двигали экран сами, и тестировщик Dan
  # сказал про это «принудительный скролл в следующую секцию не понравился».
  #
  # ⚠️ Снят именно переход, а не правило. `level_settled?/3` осталось на месте
  # и работает как раньше — просто теперь оно ничего не двигает, а красит:
  # лента секций (`assign_stage_nav/1`) спрашивает его же слагаемые, чтобы
  # отличить «держит уровень» от «можно доделать». Второй читатель того же
  # правила — `hold_note/4` ниже, он же и остался единственным местом, где
  # написано СЛОВАМИ, что именно держит.
  #
  # Путь вперёд от снятия не пострадал и был проверен до правки:
  # `handle_event("select_level", …)` зажимает выбор через `clamp_level/3`,
  # то есть следующий уровень кликается в лестнице всегда. Лента секций
  # добавила ему второй, более заметный вход — рядом с местом, где игрок
  # заканчивает уровень, а не в шапке страницы.
  #
  # ⚠️ «Всегда» здесь сужено задачей 3.69: потолок клика — `level_ceiling/2`,
  # а не голое `taken + 1`, и без расы с мировоззрением он дальше уже взятого
  # не пускает. «Следующий уровень кликается всегда» по-прежнему верно для
  # ЛИСТАНИЯ уже взятого — не для добавления нового; подробности и таблица
  # случаев — у `level_ceiling/2`.

  # Что именно держит уровень, словами. Считается ТОЛЬКО пока мы держим: иначе
  # `fillable?/4` (полный проход по трём сотням фитов на каждый пустой слот)
  # платился бы на каждой перерисовке, а нужен он на одном экране из сорока.
  defp hold_note(%{hold: hold}, _ruleset, _build, level) when hold != level, do: nil

  defp hold_note(_assigns, ruleset, build, level) do
    filled = Map.get(build.feats, level, %{})
    pending = Enum.reject(FeatSlots.at(build, ruleset, level), &Map.has_key?(filled, &1.id))

    increase? =
      MapSet.member?(ruleset.epic.ability_increase_levels, level) and
        not Map.has_key?(build.ability_increases, level)

    # Заполнимое и незаполнимое разведены намеренно: свалив их в один список,
    # строка сначала просила выбрать фит в слот, а потом сама же сообщала, что
    # выбирать там нечего — и называла слот дважды.
    {dead, todo} = Enum.split_with(pending, &(not fillable?(ruleset, build, level, &1)))

    parts =
      Enum.map(todo, &"слот «#{Labels.slot_label(ruleset, &1)}»") ++
        if(increase?, do: ["прибавка к характеристике"], else: []) ++
        class_choice_note(ruleset, build, level)

    if parts == [] and dead == [] do
      nil
    else
      %{
        what: if(parts == [], do: nil, else: Enum.join(parts, ", ") <> "."),
        dead: dead_text(Enum.map(dead, &"«#{Labels.slot_label(ruleset, &1)}»"))
      }
    end
  end

  defp class_choice_note(ruleset, build, level) do
    with class when not is_nil(class) <- Build.class_at(build, level),
         1 <- Build.class_level_at(build, level),
         %{required?: true} = spec <- ClassChoices.spec(class, ruleset),
         false <- ClassChoices.complete?(build, class, ruleset) do
      missing = spec.count - length(Build.class_choice(build, class))
      [Labels.class_choice_pending_text(class) <> " (#{max(missing, 0)})"]
    else
      _ -> []
    end
  end

  defp dead_text([]), do: nil

  defp dead_text(slots) do
    "#{Enum.join(slots, ", ")} заполнить нечем — уровень так и не закроется. " <>
      "Следующий выбери в колонке слева."
  end

  # «Есть ли хоть один фит, который этот слот примет прямо сейчас» — без фильтров
  # поиска: вопрос про сам слот, а не про то, что игрок набрал в строке поиска.
  defp fillable?(ruleset, build, level, slot) do
    Feats.lists(ruleset, build, level, query: "", type: "all", slot: slot.id).available != []
  end

  # ⚠️ Единственная воронка правок билда — поэтому принудительная покупка
  # ключевой характеристики (и, с задачи 3.17, сброс распределения, когда она
  # не помещается) стоит здесь, а не в `pick_class` и `pick_race` по
  # отдельности: два места, где написано одно правило, — это форма бага 1.2.
  #
  # ⚠️ С задачи 3.17 раса, класс и характеристики — на одном экране (уровень
  # 1), и играть их можно в любом порядке: раньше здесь стояло «класс
  # спрашивается ПОСЛЕ характеристик», это было ложью с самого объединения
  # экранов и вычеркнуто, а не оставлено рядом с новым текстом (HANDOFF.md:
  # неверная справка дороже отсутствующей).
  #
  # Порядок применения — `PointBuy.reset_needed?/2` спрашивает, а
  # `PointBuy.reset_to_floor/2` (если да) отвечает, оба ДО `enforce_floor/2`,
  # рядом друг с другом (AGENT_QUEUE §3.17, решение 3):
  #
  #   * «свободных не хватает на принудительную покупку» — распределение
  #     сбрасывается к табличному полу целиком (`PointBuy.reset_to_floor/2`),
  #     и уже НА НЁМ `enforce_floor/2` без труда докупает минимум: по замеру
  #     Дана худший случай (полуорк) стоит 5 из 30, так что после сброса
  #     покупка минимума помещается всегда;
  #   * иначе — то же самое, что и раньше: `enforce_floor/2` просто поднимает
  #     недостающую характеристику, не трогая остальные.
  #
  # Докупить руками до перебора игрок не может (`can_raise?/3` не даёт), так
  # что перебор бюджета живым кликом теперь ВООБЩЕ не возникает — единственный
  # путь к нему остался прежним: билд, пришедший по ссылке в обход воронки
  # (`load_code/2`, решение 1.7), пока его не коснулась хоть одна правка.
  # `.pb-budget[data-over]` и подпись под ним остаются на этот случай.
  #
  # Сброс обязан привлечь внимание — не флешем, который гаснет на первом
  # несвязанном клике (прецедент — кап AC), а отдельным assign'ом
  # `:point_buy_reset`: держится ровно пока ЭТОТ ЖЕ проход funnel'а сбрасывает
  # заново, и гаснет сам, как только следующая правка ничего не сбрасывает —
  # то есть описывает текущее состояние, а не разовое уведомление.
  defp put_build(socket, %Build{} = build) do
    ruleset = socket.assigns.ruleset
    before_abilities = build.base_abilities
    reset? = PointBuy.reset_needed?(ruleset, build)

    # Задача 3.157 — снимок ДО правки, единственная воронка и есть
    # единственное правильное место для него: `first_guide_target/1` читает
    # `nav_sections/1` + `section_pending?/2`, те же assign'ы, что refresh/1
    # ниже вот-вот пересчитает, так что «до» обязано быть снято раньше
    # `refresh()`, а не после. См. `guide_scroll/2` ниже — там же и разбор,
    # почему сравнение «до/после» живёт здесь, а не в каждом `pick_*`
    # по отдельности.
    before_target = first_guide_target(socket.assigns)

    build =
      if reset?, do: PointBuy.reset_to_floor(ruleset, build), else: build

    build = PointBuy.enforce_floor(ruleset, build)
    code = Encoding.encode(build)

    # Задача 3.162: снимок уровня ДО этой правки — не просто `socket.assigns.
    # active` россыпью ниже, а именованная переменная, потому что она нужна
    # ДВАЖДЫ по двум разным причинам (куда попробовать перейти, и с чем
    # сравнить результат), и второе чтение обязано увидеть то же число, что
    # и первое, а не то, что мог переставить `go_to_level/2` между ними.
    was = socket.assigns.active

    socket =
      socket
      |> assign(:build, build)
      |> assign(:point_buy_reset, point_buy_reset_note(reset?, ruleset, before_abilities, build))
      |> assign(:ladder_issues, ladder_issues(ruleset, build))
      |> assign(:code, code)
      |> refresh()

    # Задача 3.162 (просьба владельца шарда через Dan, 01.09.2026): гид не
    # просто останавливается, когда на уровне не осталось решений, — он едет
    # дальше, ЕСЛИ это фронтир билда (см. `guide_advance?/2`). Переход —
    # `go_to_level/2`, ТА ЖЕ функция, что стоит за кнопкой «Уровень N →»
    # и кликом по лестнице: один формула на все три триггера (форма бага 1.2,
    # CLAUDE.md §8), а не вторая копия сброса уровневого UI-состояния
    # (`:hold`, `:sections`, `:feat_slot`, `:feat_choice`, `:preview`).
    socket =
      if guide_advance?(socket, before_target) do
        go_to_level(socket, was + 1)
      else
        socket
      end

    # 🔴 РОВНО ОДИН `push_patch` на событие — второй вызов на том же сокете
    # ПАДАЕТ (`Phoenix.LiveView.push_patch/2`: `put_redirect/2` делает
    # `raise`, если `socket.redirected` уже занят, а не молча перезаписывает
    # прежний адрес новым). Поэтому здесь развилка по ФАКТУ, а не по
    # предсказанию: если `active` уже сдвинут — значит `go_to_level/2` выше
    # только что толкнул СВОЙ `push_patch` (с новым `l=`), и патчить второй
    # раз нельзя, только довезти вид. Сверяется РЕЗУЛЬТАТ
    # (`socket.assigns.active != was`), а не ответ `guide_advance?/2` — тот
    # может сказать «да» и всё равно ничего не сдвинуть: `go_to_level/2` сам
    # зажимает переход через `level_ceiling/2` (легаси-ссылка без расы,
    # довезённая до фронтира правкой на нём же, — редкий, но настоящий
    # случай, см. её же комментарий). Тогда обычный `push_patch` обязан уйти
    # как ни в чём не бывало — иначе адрес в браузере разойдётся с `@code`
    # молча, не дождавшись вообще никакого патча на это событие.
    if socket.assigns.active != was do
      guide_scroll_landing(socket)
    else
      socket
      # Задача 3.61: `l` рядом с `b` — эта воронка задевает КАЖДУЮ правку
      # билда, значит без него редактирование на уровне 20 стирало бы
      # позицию, оставленную `select_level`, при первом же следующем клике.
      # `active` читается уже ПОСЛЕ того, как вызывающий код мог его
      # переставить в этом же событии (`drop_level` двигает его в своём
      # пайпе раньше, чем зовёт эту функцию) — значение здесь всегда то, что
      # видит игрок прямо сейчас. Оно же равно `was` в этой ветке (иначе мы
      # были бы в ветке выше), но читается заново по той же причине, по
      # которой читалось заново и до 3.162 — единообразия ради, а не потому
      # что могло разойтись именно здесь.
      |> push_patch(to: ~p"/?b=#{code}&l=#{socket.assigns.active}", replace: true)
      |> guide_scroll(before_target)
    end
  end

  # Задача 3.157 (просьба владельца шарда через Dan, 01.09.2026, «guided
  # mode»): гейт задачи 3.30 остаётся — экран сам никуда не едет, ПОКА игрок
  # не включил галочку сам (`#guided-toggle-input`, `.GuidedMode`). С
  # галочкой цену «дёргается» платит тот, кто её включил, — ровно довод
  # постановки.
  #
  # ⚠️ Живёт ВНУТРИ `put_build/2`, не в `pick_race`/`pick_class`/`pick_feat`
  # по отдельности — та же причина, по которой сама воронка существует
  # (комментарий выше: «два места, где написано одно правило, — форма бага
  # 1.2»). Из этого следует бесплатно: поинт-бай и домены клирика/школа
  # волшебника — всё, что проходит через `put_build/2`, — тоже двигает
  # экран, хотя постановка называла только «расу / мировоззрение / класс /
  # фита». Это не расширение сверх постановки, а то же самое правило,
  # применённое ОДНИМ местом: воронка не различает, какой `pick_*` её
  # вызвал, и не обязана — `first_guide_target/1` сама решает, сдвинулась
  # ли цель (и `@guide_excluded_sections` ниже сама решает, какие цели
  # вообще считаются — заклинания среди них нет, см. критерий там же).
  #
  # ⚠️ Скроллит, только если ЦЕЛЬ ПОМЕНЯЛАСЬ (`target != before`), а не при
  # каждом вызове воронки — иначе, например, клик по уже выбранному общему
  # фиту (снятие) слал бы тот же самый `scroll_to_section` заново, хотя
  # экран и так там. Тот же принцип, каким старый `.FocusPending` сравнивал
  # `token()` (снят задачей 3.30, см. её комментарии в `builder_live.html.heex`)
  # — просто снимок теперь берёт сервер, а не хук чтением DOM.
  #
  # ⚠️ `drop_level` — единственный вызывающий, который двигает `:active` ДО
  # прихода сюда (см. комментарий у `push_patch` выше). «До» в этом одном
  # случае уже смотрит на НОВЫЙ активный уровень чужими, ещё не обновлёнными
  # `assigns` (`class_choice`/`spell_note`/… с прежнего уровня) — цена этого
  # редкая и разрушительная кнопка «−», а не докупка билда, и худшее
  # следствие — лишний или пропущенный скролл на одном действии, а не порча
  # билда. Отдельный проход ради него не заведён сознательно: он вернул бы
  # ту же «два места пишут одно правило» форму бага, которую сама воронка
  # существует, чтобы не плодить.
  #
  # `block: "nearest"` — НЕ то же самое, что у `jump_to_gap`/
  # `jump_to_gear_issue` (те просят `.ScrollBus` про `"start"`, дефолт).
  # Разница воспроизводит урок, уже найденный и записанный в СНЯТОМ коде
  # 3.18: «первая редакция подтягивала цель к верху всегда, и клик по расе
  # прокручивал страницу на 602px, хотя секция мировоззрения была полностью
  # видна — то есть лечение оказалось хуже болезни». Прыжок через много
  # уровней (`jump_to_gap`) и переход к следующей секции ТОГО ЖЕ уровня —
  # разные по масштабу движения, и повторять здесь `"start"` значило бы
  # наступить на грабли, по которым уже прошли один раз.
  #
  # ⚠️ Задача 3.162: с появлением автоперехода эта функция перестала быть
  # безусловным последним шагом `put_build/2` — только его НЕадвансящей
  # половины (развилка в самом `put_build/2`, по факту `active != was`).
  # Код ниже от этого не изменился ни на строку: когда уровень не завершён
  # или ехать дальше нельзя/некуда (не фронтир, нет следующего уровня,
  # галочка выключена), решение «скроллить ли в пределах уровня» принимает
  # ровно эта функция, как и раньше.
  defp guide_scroll(socket, before_target) do
    with true <- socket.assigns.guided_mode,
         target when not is_nil(target) <- first_guide_target(socket.assigns),
         true <- target != before_target do
      push_event(socket, "scroll_to_section", %{id: target, block: "nearest"})
    else
      _ -> socket
    end
  end

  # Критерий, а не список по вкусу (задача 3.157, второе уточнение владельца
  # шарда через Dan в ходе работы над задачей — первое называло только
  # навыки, список без критерия следующий читатель начал бы править по
  # вкусу): **guided mode ведёт к решениям, которые НЕЛЬЗЯ ОТЛОЖИТЬ.**
  # Отложить можно ровно две вещи, обе по устройству продукта, а не по
  # прихоти этой функции:
  #
  # 🔴 Навыки: `section_pending?(_, "skills")` истинно, пока `free > 0` —
  # «не потрачено», а не «не решено». Копить скилл-поинты и вложить их
  # позже — законная и частая стратегия, и интерфейс сам говорит это рядом
  # со счётчиком; у билда с высоким INT свободные очки есть почти на каждом
  # уровне, и без исключения guided mode тащило бы туда постоянно — ровно
  # то, на что жаловались в 3.18.
  #
  # 🔴 Заклинания: `section_pending?(_, "spells")` истинно и когда СЛОТ не
  # заполнен, и когда есть предупреждение — но известные заклинания у
  # спонтанных кастеров необязательны РЕШЕНИЕМ владельца, не нашим выводом.
  # Dan дословно: «тот кто будет билдить барда или колдуна может залениться
  # заполнять все заклинания, это довольно утомительно, поэтому изначально
  # я хотел сделать их необязательными, как навыки. Guided mode
  # соответственно никогда не должен скроллить к заклинаниям» — сам владелец
  # называет ту же пару, что и здесь: заклинания необязательны ТЕМ ЖЕ
  # способом, что и навыки, а не по отдельной причине. У колдуна 41 известное
  # заклинание за 20 уровней, и большинству нужны боевые числа, а не полный
  # список. §6 говорит только, ГДЕ живёт этот выбор (рядом с фитами) — а
  # ОБЯЗАТЕЛЕН ли он, решает владелец, и здесь он решил «нет». ⚠️ Заодно и по
  # существу: половина предиката (`spell_note != nil`) срабатывает ровно
  # тогда, когда решать НЕЧЕГО ВООБЩЕ — примечание печатается только при
  # пустом списке слотов («класс новых заклинаний не даёт» или стена
  # 20-го уровня), а у кастера после 20-го это каждый уровень до 41-го.
  #
  # Всё остальное — раса, мировоззрение, класс уровня, прибавка
  # характеристики, поинт-бай, домен клирика/школа волшебника, слоты
  # фитов — либо блокирует билд целиком, либо принадлежит ИМЕННО этому
  # уровню и позже не наверстывается: пропущенный слот фита 5-го уровня
  # нельзя закрыть на 6-м, а свободные очки навыков — можно перенести куда
  # угодно. Критерий переживает появление новой секции: будет ещё одна
  # отложимая — ответ на «отложить можно?» уже известен, менять только
  # список ниже.
  #
  # ⚠️ `section_pending?/2` этой функцией НЕ переопределяется и не должна —
  # обе секции ЧЕСТНО незакончены, и лента (`nav_state/2`) обязана
  # продолжать подсвечивать их тем же жёлтым: это верный ответ на «не
  # закрыто ли», просто не годится ответом на «куда ехать». Guided mode
  # фильтрует ЦЕЛИ поверх готового предиката, а не переписывает сам предикат.
  #
  # ⚠️ Задача 3.162: тот же список исключений решает и «отложимое ли это
  # для перехода на следующий уровень», без единой новой строки здесь —
  # `guide_advance?/2` смотрит на `first_guide_target/1` ПОСЛЕ правки и, если
  # тот `nil`, считает уровень закрытым, даже когда открыты только навыки
  # или заклинания. Последовательно с тем, что «незакрыто» для них уже
  # значит «есть что отложить», а не «билд неполон» — но стоит назвать
  # прямо: билд, который копит скилл-поинты, гид унесёт вперёд ВМЕСТЕ
  # с ними, не дожидаясь, пока они будут потрачены.
  @guide_excluded_sections ["skills", "spells"]

  # Первая (в порядке `nav_sections/1`, том же, что рисует ленту и страницу
  # сверху вниз) секция, которая и «незакрыта» (`section_pending?/2`), и
  # разрешена как цель (не входит в `@guide_excluded_sections`) — или `nil`,
  # если такой нет. Один и тот же вызов служит и «до», и «после» снимком
  # в `put_build/2`: `nav_sections/1` сам фильтрует по `:if` шаблона (не
  # предложит `section-race` на уровне 5), так что здесь не нужно повторять
  # эту фильтрацию отдельно.
  defp first_guide_target(assigns) do
    Enum.find_value(nav_sections(assigns), fn {key, id, _label} ->
      if key not in @guide_excluded_sections and section_pending?(assigns, key), do: id
    end)
  end

  # Задача 3.162: КОГДА гиду ехать на следующий уровень, а не КАК (это
  # `go_to_level/2`, уже существующая формула перехода — см. её вызов
  # в `put_build/2`). Оба условия ниже обязаны выполниться разом:
  #
  # 🔴 «Мы только что закрыли последнее решение» — `before_target != nil`,
  # а не голое `is_nil(after)`. Иначе КАЖДАЯ правка уже полностью готового
  # уровня (например, замена фита в уже заполненном слоте — `before`
  # и `after` оба `nil`) толкала бы игрока вперёд без единого закрытого
  # решения, и не один раз, а на каждом таком клике подряд.
  #
  # 🔴 «Это фронтир, а не любой активный уровень» — решение Dan 01.09.2026,
  # единственный названный открытым краем постановки: «переходить только
  # если это последний заполненный уровень билда». Игрок, вернувшийся на
  # 5-й уровень поменять фит и закрывший там последнее решение, гид уносить
  # не должен — там меняется не прокрутка (жалоба 3.18, «зачастую хочется
  # изменить выбор»), а сам РЕДАКТИРУЕМЫЙ УРОВЕНЬ, и цена ошибки выше.
  # `Build.character_level/1` — длина `levels`, то есть ровно «последний
  # заполненный».
  #
  # ⚠️ Проверено и СОЗНАТЕЛЬНО не заведено третье условие про `drop_level`
  # (кнопка «−») — единственный вызывающий, что двигает `:active` ДО
  # прихода в `put_build/2` (см. комментарий у `push_patch` в `put_build/2`
  # про «чужие, ещё не обновлённые assigns»). Гипотеза при разборе задачи
  # была прямой: усечение билда может ВЫГЛЯДЕТЬ отсюда как «фронтир
  # и только что закрытое последнее решение» одновременно, а `before_target`
  # при этом читает assigns УДАЛЯЕМОГО уровня — и гид толкнёт игрока НАЗАД,
  # на только что убранный уровень. Живым прогоном (`drop_level` со
  # стоящего на фронтире уровня, с уровня НИЖЕ фронтира, со «свободного»
  # уровня-подсмотра за фронтиром — три раскладки, все три возможные)
  # гипотеза не подтвердилась НИ РАЗУ, и вот почему структурно не может:
  #
  #   * у `drop_level` формула `min(active, level)`, где `level` берётся
  #     ДО усечения — переставляет `:active` только на ТОТ ЖЕ номер, каким
  #     был счётчик уровней ДО дропа, никогда меньше. Стоял игрок на
  #     фронтире или ЗА ним (пустой «подсмотр») — новый `:active` всегда
  #     садится на позицию РОВНО ЗА новым, укороченным фронтиром, то есть
  #     на пустой уровень. «Класс» показан безусловно на любом уровне
  #     (`nav_sections/1`), значит СРАЗУ после такого дропа он снова
  #     пендинг, и `first_guide_target/1` физически не может вернуть `nil`
  #     — первое условие выше не проходит;
  #   * стоял игрок НИЖЕ фронтира — `:active` вообще не двигается (тот же
  #     `min` берёт уже меньшее значение), а дроп верхних уровней данных
  #     ЭТОГО уровня не касается: «до» и «после» читают ОДИН И ТОТ ЖЕ,
  #     не тронутый правкой уровень — расхождения снимка нет вовсе, и
  #     `before_target != after_target` быть не может.
  #
  # То есть «лишний или пропущенный скролл», которым `guide_scroll/2`
  # предупреждает про стек `drop_level`, не может перерасти в «лишний
  # переход»: переход требует `nil` ПОСЛЕ, а свежепустой уровень этого
  # не даёт никогда. Добавлять третье условие ради сценария, который
  # не воспроизводится, значило бы держать в комментарии причину, которой
  # не было, — решение зафиксировано тестом, а не забыто:
  # `builder_live_test.exs`, describe «guided mode», кейс drop_level.
  #
  # ⚠️ Кап (`active < ruleset.level_cap`) проверяется здесь тоже — не
  # потому что `go_to_level/2` сам не остановится на нём (остановится,
  # `level_ceiling/2` не пускает дальше `ruleset.level_cap`), а чтобы
  # не звать его лишний раз (это ещё один `refresh/1`) там, где заранее
  # известно, что ехать некуда. Это оптимизация и явное имя для edge case
  # «на капе гид молчит», а не единственная защита от прыжка в никуда: если
  # `go_to_level/2` всё равно откажет несмотря на «да» отсюда (легаси-ссылка
  # без расы — см. её же комментарий), вызывающий код `put_build/2` сверяет
  # `active` ДО и ПОСЛЕ и не полагается на то, что этот предикат предсказал
  # результат верно на все сто.
  #
  # ⚠️ Отложимое (навыки, заклинания) отдельно не проверяется — оно уже
  # исключено из `first_guide_target/1` через `@guide_excluded_sections`
  # (см. её же комментарий про это), так что «после» здесь `nil` и тогда,
  # когда на уровне остались только они.
  defp guide_advance?(socket, before_target) do
    %{guided_mode: guided_mode, build: build, active: active, ruleset: ruleset} = socket.assigns

    guided_mode and before_target != nil and is_nil(first_guide_target(socket.assigns)) and
      active == Build.character_level(build) and active < ruleset.level_cap
  end

  # Довозит вид ПОСЛЕ того, как `go_to_level/2` (вызванный из `put_build/2`)
  # уже сменил `:active` и толкнул свой `push_patch`. Цель — ПОСТОЯННАЯ
  # `#stage-head`, а не `first_guide_target/1` нового уровня (тот почти
  # всегда «section-class» — свежий уровень класса ещё не выбрал), и это
  # не совпадение, а выбор:
  #
  #   * `#stage-head` рендерится безусловно на КАЖДОМ уровне (см. комментарий
  #     у `#scroll-bus` в шаблоне) — цель гарантированно уже в DOM, никакого
  #     случая «а если на новом уровне вдруг нечего показать»;
  #   * это ТА ЖЕ цель, к которой ведёт нативный `href="#stage-head"` у
  #     кнопки «Уровень N →» (`BuilderComponents.next_level/1`) — ручной клик
  #     и автопереход гида обязаны приземлять игрока в ОДНО и то же место
  #     (форма бага 1.2, CLAUDE.md §8), а заодно заголовок «Уровень N»
  #     гарантированно виден: без него автопереход сменил бы контент экрана
  #     под игроком молча, а сам факт «уровень изменился» остался бы
  #     незамеченным — та же ловушка, что нашла задача 3.33 у ссылки самой
  #     кнопки («шаг вперёд с глубины 2600px оставлял игрока… с заголовком
  #     за краем экрана»).
  #
  # `block: "nearest"`, не `"start"` — тот же довод, что у within-level
  # скролла (3.157, требование 6): переход триггерится КОСВЕННО, побочным
  # эффектом клика по чему-то другому (фиту, стату — не по самой кнопке
  # «вперёд»), значит обязан уважать прокрутку, которую игрок ведёт прямо
  # сейчас, тем же 500мс гвардом `.ScrollBus`. Прямой клик по кнопке «Уровень
  # N →» этого довода не касается — у неё нативный якорь, не `push_event`,
  # и это отдельный, более сильный сигнал намерения.
  defp guide_scroll_landing(socket) do
    push_event(socket, "scroll_to_section", %{id: "stage-head", block: "nearest"})
  end

  # `false` from `PointBuy.reset_needed?/2` — cheapest and most common case,
  # nothing to diff.
  defp point_buy_reset_note(false, _ruleset, _before, _build), do: nil

  # `true` — diff every ability against what it was going INTO this call
  # (before `reset_to_floor/2` and `enforce_floor/2` ran), not against some
  # remembered history: this is "what THIS pass of the funnel just changed",
  # which is what makes the note a state and not a stored event. A manual −1
  # click never reaches here at all (`PointBuy.reset_needed?/2`'s own doc
  # explains why raising or lowering one ability on its own cannot retrigger
  # this), so there is no risk of reading an ordinary purchase as a reset.
  defp point_buy_reset_note(true, ruleset, before, %Build{base_abilities: now}) do
    terms =
      for ability <- Labels.ability_order(),
          from = Map.get(before, ability, PointBuy.min_score(ruleset)),
          to = Map.get(now, ability, PointBuy.min_score(ruleset)),
          from != to,
          do: %{ability: ability, label: Labels.ability(ability), from: from, to: to}

    %{abilities: MapSet.new(terms, & &1.ability), terms: terms}
  end

  # ------------------------------------------------------------------ render --

  defp refresh(socket) do
    %{ruleset: ruleset, build: build} = socket.assigns
    stats = Rules.compute(build, ruleset)
    code = socket.assigns.code || Encoding.encode(build)

    socket
    |> assign(:stats, stats)
    |> assign(:code, code)
    # Ключ ищется по КОДУ, а не запоминается отдельно: иначе после правки билда
    # на экране осталась бы короткая ссылка на прежний билд.
    |> assign(:short_key, Map.get(socket.assigns.short_links, code))
    |> assign(:gaps, Gaps.summary(ruleset, build, stats))
    |> assign_ladder()
    |> assign_stage()
    |> TotalsPanel.assign_panel()
  end

  # Задача 1.3 (доп. задача — экран просмотра и экспорт, см. отчёт): список
  # форм и сама прогонка лестницы (`Rules.illegal_class_levels/2` +
  # `Rules.illegal_feats/2`, перевод причин, группировка по уровню) переехали
  # в `Builder.Labels.ladder_issues/2` — экран просмотра билда
  # (`BuildViewLive`) отвечает на тот же вопрос по тому же ПОЛНОМУ состоянию
  # билда (та же кодировка `Builder.Encoding`, что пишет конструктор), и
  # держать здесь ещё одну ручную копию значило бы повторить историю бага 1.2:
  # `Prereqs.keys()` против `@requirement_keys` загрузчика, два списка,
  # написанных руками дважды и разошедшихся. `Builder.Import` в этом сведении
  # не участвует — его список уже, по другой причине (см. его файл).
  #
  # Что осталось здесь, а не переехало: КОГДА пересчитывать, а не КАКИЕ формы
  # показывать — это знание принадлежит конструктору, а не переводчику.
  #
  # ⚠️ Дороже, чем `Rules.compute/2`: на живом 40-уровневом билде с ~20
  # фитами замерено ~2.5–3.6мс на `illegal_class_levels/2` и ~1.2–1.7мс на
  # `illegal_feats/2` (сорок с лишним усечений билда и полных `compute` —
  # против ~0.1мс у самого `compute/2` на том же билде). Мало в абсолютных
  # цифрах, но не «дёшево» в духе moduledoc — поэтому не на каждый `refresh/1`
  # (там осело бы и на нажатие в поиске фитов, который билд не трогает
  # вовсе), а только там, где `:build` меняется на самом деле: `mount/3`,
  # `load_code/2`, `put_build/2` — три места, что видно по `grep -n
  # 'assign(:build'`. `assign_ladder/1` результат только читает.
  defp ladder_issues(ruleset, build), do: Labels.ladder_issues(ruleset, build)

  # Тоже переехало в `Labels.level_word/1` — экран просмотра считает те же
  # уровни тем же словом (счётчик там свой, но грамматика общая).
  defp level_word(n), do: Labels.level_word(n)

  defp assign_ladder(socket) do
    %{ruleset: ruleset, build: build, active: active, stats: stats, ladder_issues: issues} =
      socket.assigns

    taken = Build.character_level(build)

    # Классы этого билда, у которых вообще есть свой выбор (задача 3.14) —
    # считаем ОДИН раз за `refresh/1`, а не по разу на каждую из 41 строки.
    # Множество почти всегда пустое (обычный билд без Cleric), и тогда
    # `ladder_class_choice/5` отбивает каждую строку одним `MapSet.member?`
    # вместо похода в `ClassChoices.spec/2` — дёшево должен быть КАЖДЫЙ
    # `refresh/1` целиком, а он вызывается на каждое событие, включая
    # наведение мышью, а не только на смену билда.
    classes_with_choice =
      for class <- Build.classes_used(build),
          ClassChoices.spec(class, ruleset),
          into: MapSet.new(),
          do: class

    rows =
      for level <- 1..ruleset.level_cap//1 do
        class = Build.class_at(build, level)

        %{
          level: level,
          class: class,
          short: if(class, do: Labels.class_short(ruleset, class), else: nil),
          hue: hue(class),
          prc: Palette.prc(ruleset, class),
          run_start?: level == 1 or Build.class_at(build, level - 1) != class,
          epic_start?: level == ruleset.epic.starts_at,
          active?: level == active,
          reachable?: level <= taken + 1,
          slots: ladder_slots(ruleset, build, level),
          spells: ladder_spells(ruleset, build, stats, level),
          increase: ladder_increase(ruleset, build, level),
          domain_choice: ladder_class_choice(ruleset, build, level, class, classes_with_choice),
          granted_choices: ladder_granted_choices(ruleset, build, level),
          skills: ladder_skills(ruleset, build, level),
          issues: Map.get(issues, level, [])
        }
      end

    start = Abilities.scores_at(build, ruleset, 0)

    socket
    |> assign(:ladder, rows)
    |> assign(:todo, Enum.reduce(rows, 0, &(&2 + row_todo(&1, taken))))
    |> assign(:illegal_count, map_size(issues))
    |> assign(:split, split(ruleset, build))
    |> assign(:character_level, taken)
    |> assign(
      :start_abilities,
      for(
        a <- Labels.ability_order(),
        do: %{label: Labels.ability(a), value: Map.get(start, a, 0)}
      )
    )
    |> assign(:stage_sub, stage_sub(ruleset, build, active))
  end

  # Задача 3.17: нулевой и первый уровни слиты — «Раса, мировоззрение,
  # стартовые характеристики» больше не отдельная фраза для отдельного
  # экрана, а ПРЕФИКС уровня 1, который встаёт перед обычным разбором того же
  # уровня (класс, слоты, прибавка). Текст оставлен дословно тем же, каким он
  # был у прежнего «нулевого» экрана — задача 3.8 (04.08.2026) его уже
  # вычистила от лишнего, второй раз сокращать нечего.
  defp stage_sub(ruleset, build, level) do
    parts =
      if(level == 1, do: ["Раса, мировоззрение, стартовые характеристики"], else: []) ++
        level_stage_parts(ruleset, build, level)

    case Enum.join(parts, " · ") do
      "" -> "Выбери класс для этого уровня."
      text -> text
    end
  end

  defp level_stage_parts(ruleset, build, level) do
    slots = FeatSlots.at(build, ruleset, level)

    [
      case Build.class_at(build, level) do
        nil -> nil
        class -> "сейчас: " <> Labels.class_name(ruleset, class)
      end,
      case length(slots) do
        0 -> nil
        1 -> "✦ фит"
        n -> "✦ #{n} слота фитов"
      end,
      case length(Feats.granted(ruleset, build, level)) do
        0 -> nil
        n -> "○ #{n} от класса"
      end,
      if(MapSet.member?(ruleset.epic.ability_increase_levels, level),
        do: "▲ +1 к характеристике"
      ),
      if(level >= ruleset.epic.starts_at, do: "эпический уровень")
    ]
    |> Enum.reject(&is_nil/1)
  end

  # ⚠️ A row per slot, and every row has to say WHICH slot. A Fighter's first
  # level holds three (общий + расовый человека + бонус Fighter) and used to
  # print «✦ выбрать фит» three times over — the pools behind those three are
  # different, and a bonus slot spent on the wrong list is exactly how an
  # illegal build gets assembled (CLAUDE.md §6).
  #
  # Filled and empty say different things on purpose: a filled slot names the
  # feat (the name is what the column exists for), an empty one names the slot.
  # For a filled slot the kind therefore rides entirely on the glyph and its
  # colour, which is why `slot_glyph/1` has to stay legible at 9.5px.
  defp ladder_slots(ruleset, build, level) do
    filled = Map.get(build.feats, level, %{})
    takes = Feats.take_numbers(build, level)

    # Один вызов на уровень, а не на слот: уровень редко несёт больше двух
    # слотов, но `free_later/3` сканирует билд вперёд от уровня до конца, и
    # считать его дважды на одном и том же уровне незачем.
    later = Feats.free_later(ruleset, build, level)

    for slot <- FeatSlots.at(build, ruleset, level) do
      pick = Map.get(filled, slot.id)

      %{
        dom_id: "lv#{level}-slot-#{Ids.slot_dom_id(slot.id)}",
        label: Labels.slot_label(ruleset, slot),
        todo: Labels.slot_ladder_label(ruleset, slot),
        glyph: Labels.slot_glyph(slot),
        bonus?: slot.kind == :class_bonus,
        hue: hue(slot.class),
        prc: Palette.prc(ruleset, slot.class),
        # ⚠️ Имя ВМЕСТЕ с выбором и счётчиком: `Spell focus (Evocation)`,
        # `Epic toughness ×3`. Без выбора строка называла бы фит, но не решение
        # (школ восемь, и они не взаимозаменяемы), а без счётчика десять
        # взятий подряд читались бы как одно и то же — та же болезнь, что была
        # у соркерера с шестью «выбрать заклинание».
        name: pick && Labels.feat_pick_name(ruleset, pick, Map.get(takes, slot.id, 1)),
        # Слот уже потрачен, а фит всё равно есть даром — «✓ взят» само по себе
        # этого не говорит. Решение Дана 02.08.2026 (HANDOFF §A.3): глиф `○`
        # рядом с основным, а не молчание. `nil`, пока слот пуст — предупреждать
        # про пустоту нечего, для неё уже есть «не выбрано».
        #
        # ⚠️ Даром — двумя разными способами: класс выдаст его позже, или его
        # лендит вещь (задача 3.3). Оба считает `Feats.wasted_text/4`, поэтому
        # здесь ничего не различается: строка колонки одна, и решение «какое
        # из двух предложений сильнее» принято там, а не тут.
        wasted_text: pick && Feats.wasted_text(ruleset, build, later, pick)
      }
    end
  end

  # Feeds the "Класс даёт сам" line of the feat section and nothing in the
  # ladder: the progression column shows decisions, and a granted feat is not
  # one — the player cannot influence it, yet it took as much room as a choice
  # (CLAUDE.md §6, decision of 02.08.2026).
  #
  # `granted_display/3`, not `granted_named/3` — задача 1.10 шаг 4: 08.08.2026
  # владения доехали до `granted_feats`, и семь строк («Armor proficiency
  # (light)», «(medium)», «(heavy)», «Shield proficiency», «Weapon proficiency
  # (martial)», «(simple)», плюс `Toughness`) превратили эту строку в сплошной
  # абзац. Возвращает уже готовые СТРОКИ (не пары `%{id:, name:}`), поэтому
  # оба шаблона, читающие `@granted`, склеивают их напрямую (`Enum.join`),
  # без `& &1.name`.
  #
  # ⚠️ Внутри — ПРИРОСТ владения, а не сырая выдача классового уровня (баг 1.14,
  # `Feats.granted/3`): на первом уровне второго класса строка называла шесть
  # имён, из которых пять персонаж уже получил первым классом. Ступень того же
  # класса (`Defensive awareness` II) при этом остаётся — она настоящее событие.
  defp granted_rows(ruleset, build, level),
    do: Feats.granted_display(ruleset, build, level)

  # A known spell is a decision of the level exactly like a feat — chosen once
  # and for good — so it belongs in the ladder beside them (CLAUDE.md §6). The
  # circle travels as the digit of a badge rather than as yet another glyph: the
  # column's alphabet (✦ фит, ▲ стат, ▪ навык) is dense enough already, and the
  # circle is the most informative thing about a spell anyway.
  #
  # ⚠️ **Слоты группируются по кругу, а не идут по одному.** Соркерер на первом
  # уровне знает 4 нулевого круга и 2 первого — шесть строк, из которых шесть
  # раз подряд написано одно и то же «выбрать заклинание». Строка уровня
  # раздувалась вчетверо, и лестницу переставало быть видно целиком.
  #
  # Это не то сворачивание, которое отвергнуто (§6): там прятали шесть **разных
  # именованных** навыков за счётчиком. Здесь у невыбранного имени нет вовсе —
  # шесть одинаковых плашек несут ровно столько же, сколько «выбрать ×4» и
  # «выбрать ×2», и ни байтом больше. Выбранные заклинания при этом остаются
  # названными поимённо: их имена — как раз то, ради чего колонка существует.
  defp ladder_spells(ruleset, build, stats, level) do
    chosen = Map.get(build.spells, level, %{})

    stats.spell_slots
    |> Map.get(level, [])
    |> Enum.group_by(& &1.circle)
    |> Enum.sort()
    |> Enum.map(fn {circle, slots} ->
      names =
        slots
        |> Enum.map(&Map.get(chosen, &1.id))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&Labels.spell_name(ruleset, &1))

      pending = length(slots) - length(names)

      %{
        circle: circle,
        names: names,
        pending: pending,
        todo: spell_todo(names, pending),
        title: "Заклинания #{circle} круга — выбор навсегда"
      }
    end)
  end

  # Слово одно, число — множителем: «выбрать заклинание ×4» на 11.5px не влезает
  # в колонку по умолчанию (316px), а русские окончания («2 заклинания», «5
  # заклинаний») пришлось бы склонять ради текста, который и так дублирует
  # бейдж. «ещё» отличает «ничего не выбрано» от «выбрано не всё» — иначе
  # наполовину собранный уровень читался бы как пустой.
  defp spell_todo(_names, 0), do: nil
  defp spell_todo([], 1), do: "выбрать"
  defp spell_todo([], pending), do: "выбрать ×#{pending}"
  defp spell_todo(_names, 1), do: "ещё"
  defp spell_todo(_names, pending), do: "ещё ×#{pending}"

  defp ladder_increase(ruleset, build, level) do
    if MapSet.member?(ruleset.epic.ability_increase_levels, level) do
      case Map.get(build.ability_increases, level) do
        nil ->
          %{chosen: nil, label: "выбрать стат", hue: nil}

        ability ->
          score = build |> Abilities.scores_at(ruleset, level) |> Map.get(ability, 0)

          %{
            chosen: ability,
            label: "#{Labels.ability(ability)} #{score}",
            hue: Palette.ability_hue(ability)
          }
      end
    end
  end

  # `nil` on every level except a class's own first — same shape everywhere
  # else in the ladder, where a row that has nothing to show carries `nil`
  # rather than an empty placeholder (`ladder_increase/3` above does the
  # same). Fires on ANY class the level's own `class_level_at` says is 1, not
  # only on character level 1: a Cleric taken fifth, at character level 30,
  # gets its domain row on level 30, never on level 1 (AGENT_QUEUE.md §3.14).
  #
  # `class` and `classes_with_choice` are computed once by the caller
  # (`assign_ladder/1`) and passed in rather than recomputed here: this runs
  # on all 41 rows of every `refresh/1`, including ones a mouse hover
  # triggers, and `MapSet.member?/2` is the whole cost for the overwhelming
  # majority of builds, which use no class with a choice at all.
  defp ladder_class_choice(_ruleset, _build, _level, nil, _classes_with_choice), do: nil

  defp ladder_class_choice(ruleset, build, level, class, classes_with_choice) do
    if MapSet.member?(classes_with_choice, class) and Build.class_level_at(build, level) == 1 do
      %{} = spec = ClassChoices.spec(class, ruleset)
      chosen = Build.class_choice(build, class)

      # Задача 3.171: пустой выбор печатает `no_selection_name`, когда
      # ruleset называет для него слово (Wizard's `General`) — тот же
      # `ClassChoices.no_selection_name/2`, что `Summary.guide_domains/3`
      # уже читает для гида просмотра (задача 3.170). Панель итогов
      # («что выбрано») и лестница читали один билд и говорили о нём
      # разное — панель уже печатала «General», лестница молчала и звала
      # «выбрать школу магии» вечно (Dan: «можно было бы отображать, что
      # выбрано general»). `nil` у Клирика (обязательный выбор не имеет
      # слова для «ничего», `Loader.Classes.
      # build_class_choice_no_selection/2` роняет сборку при попытке его
      # завести) оставляет `names` пустым, и `todo` печатается как раньше.
      names =
        case chosen do
          [] -> List.wrap(ClassChoices.no_selection_name(class, ruleset))
          chosen -> Enum.map(chosen, &Labels.class_choice_value_name(ruleset, class, &1))
        end

      %{
        label: Labels.class_choice_heading(class),
        todo: "выбрать " <> Labels.class_choice_pending_text(class),
        required?: spec.required?,
        names: names,
        missing: max(spec.count - length(chosen), 0)
      }
    end
  end

  # A feat a class HANDS OVER can still owe a value — `Weapon of choice` for a
  # Weapon Master (Dan, 10.08.2026: «ВМ получает weapon of choice автоматически,
  # но для него ещё надо выбрать оружие»). CLAUDE.md §6 keeps the grant itself
  # out of the ladder — the player cannot influence a class handing over a feat —
  # but the *value* is a decision exactly like a Cleric's domains, so it rides
  # the same rule `ladder_class_choice/5` uses: reuse the row the level's own
  # panel already computes (`Feats.granted_choice_rows/3`) rather than a second
  # implementation that could drift from it.
  #
  # ⚠️ `[]` on the overwhelming majority of rows — `weapon_of_choice` is the
  # only grant of either ruleset that owes a value at all (moduledoc of
  # `BuildCalculator.Rules.FeatChoices.granted_choices_owed/3`), so this is a
  # single cheap `Build.granted_feats_at/3` lookup on every row that is not it.
  defp ladder_granted_choices(ruleset, build, level) do
    for choice <- Feats.granted_choice_rows(ruleset, build, level) do
      %{
        dom_id: "level-#{level}-granted-#{choice.feat}",
        text: choice.feat_name <> ": " <> (choice.chosen_name || "выбрать"),
        title: granted_choice_title(choice),
        # ⚠️ The trap here is not `required?` (there is no such thing for a
        # feat's own value — a grant's value is always eventually needed) but
        # an EMPTY domain: `Weapon of choice` demands `Weapon focus` on the
        # same weapon (`same_choice_as`), and until one is taken there is
        # nothing to choose FROM. Painting "не выбрано" then would accuse the
        # player of skipping a step they have no way to take — the same trap
        # `required?` guards against for the optional Wizard school below, just
        # sprung by a different condition. `choice.values` is exactly what the
        # picker itself would offer (`Rules.granted_feat_choice_candidates/4`).
        todo?: choice.values != [] and is_nil(choice.chosen)
      }
    end
  end

  defp granted_choice_title(%{empty_texts: [_ | _] = texts}), do: Enum.join(texts, "; ")
  defp granted_choice_title(%{feat_name: name}), do: name

  defp ladder_skills(ruleset, build, level) do
    build.skills
    |> Map.get(level, %{})
    |> Enum.sort_by(fn {id, ranks} -> {-ranks, Labels.skill_name(ruleset, id)} end)
    |> Enum.map(fn {id, ranks} ->
      class? = Skills.class_skill_at?(build, ruleset, id, level)

      %{
        id: id,
        name: Labels.skill_name(ruleset, id),
        ranks: ranks,
        total: Build.skill_ranks(build, id, level),
        cross?: not class?
      }
    end)
  end

  defp row_todo(%{level: level}, taken) when level > taken, do: 0

  # ⚠️ Задача 3.9: известные заклинания в сумму НЕ идут — так же, как
  # необязательный выбор класса ниже (`domain_choice.required?`). Раньше
  # здесь стояло `Enum.sum(Enum.map(row.spells, & &1.pending))`, и счётчик
  # в шапке лестницы («N не выбрано») рос на каждый нерасписанный слот
  # соркерера — до восьмидесяти с лишним на билде до капа, хотя
  # `level_settled?/3` их не спрашивает вовсе и переход они не держат.
  # Число, которое ничего не блокирует, не должно называть себя долгом.
  defp row_todo(row, _taken) do
    # ⚠️ Same gate as the row's own amber (`ladder_granted_choices/3`), not a
    # third rule: a Wizard's specialization is skippable forever (задача
    # 3.171: было по имени неверного класса — Cleric's domains are the
    # OPPOSITE, required and never skippable) and never counts even though
    # choosing is always possible (`required?` above), but a grant's own
    # value has no such "legitimate blank" reading anywhere in
    # `Rules.FeatChoices` — the schema carries no `required?` for it at all.
    # So the one condition that already decides the paint decides the count.
    Enum.count(row.slots, &is_nil(&1.name)) +
      if(row.increase && is_nil(row.increase.chosen), do: 1, else: 0) +
      if(row.domain_choice && row.domain_choice.required?, do: row.domain_choice.missing, else: 0) +
      Enum.count(row.granted_choices, & &1.todo?)
  end

  # Задача 3.60: «куда вести» для клика по «N не выбрано» — ТЕ ЖЕ четыре
  # источника, что суммирует `row_todo/2` выше, иначе кнопка обещала бы одно
  # число, а вела бы совсем к другому пропуску. Навыки и заклинания сюда не
  # попадают по той же причине, по которой их нет в самой сумме (см.
  # комментарий `row_todo/2` про задачу 3.9) — прыжок не может отвечать
  # за долг, которого не показывает даже сам счётчик.
  #
  # Два прохода по лестнице, а не один: сперва ЛЮБОЙ `:hold` во всём билде
  # (без него левелап не проходит — то же деление, что у `nav_state/2` через
  # `holds_level?/2`), и только если holds нет ни одного — `:todo` (не мешает
  # левелапу, только полноте билда: значение выданного фита с выбором,
  # `Weapon of choice`). Уклон координатора (AGENT_QUEUE §3.60, вопрос 1):
  # счётчик наверху смешивает оба рода не выбора, а вести к нерастраченным
  # очкам навыка, которые игрок СОЗНАТЕЛЬНО решил не тратить, — ровно та
  # ошибка, из-за которой 3.30 сняла автодвижение (они сюда и не попадают,
  # но принцип «не тащи туда, где решение уже принято» тот же).
  defp first_gap(ladder, taken) do
    first_gap_of_kind(ladder, taken, :hold) || first_gap_of_kind(ladder, taken, :todo)
  end

  defp first_gap_of_kind(ladder, taken, kind) do
    Enum.find_value(ladder, fn row ->
      if row.level <= taken do
        case row_gap_section(row, kind) do
          nil -> nil
          section -> {row.level, section}
        end
      end
    end)
  end

  # Порядок внутри уровня — как в `nav_sections/1` сверху вниз (домены → стат
  # → фиты): пропущен на одном уровне сразу не один род решения — прыжок
  # ведёт к тому, что стоит на экране выше.
  defp row_gap_section(row, :hold) do
    cond do
      row.domain_choice && row.domain_choice.required? && row.domain_choice.missing > 0 ->
        "section-domains"

      row.increase && is_nil(row.increase.chosen) ->
        "section-increase"

      Enum.any?(row.slots, &is_nil(&1.name)) ->
        "section-feats"

      true ->
        nil
    end
  end

  # Выданный фит со своим выбором (`Weapon of choice`) держит уровень не
  # больше, чем необязательная школа волшебника (CLAUDE.md §6), и
  # `holds_level?(assigns, "feats")` его не спрашивает — но он всё ещё
  # «не выбрано» в счётчике, поэтому у второго прохода своя ветка. Секция
  # та же, что у пустого слота: обе строки живут в одной разметке,
  # `#section-feats` (`granted-choice-*` рядом со `slot-chips`).
  defp row_gap_section(row, :todo) do
    row_gap_section(row, :hold) ||
      if Enum.any?(row.granted_choices, & &1.todo?), do: "section-feats"
  end

  defp split(ruleset, build) do
    counts = Build.class_levels(build)

    for class <- Enum.uniq(build.levels) do
      %{
        id: class,
        name: Labels.class_name(ruleset, class),
        hue: hue(class),
        prc: Palette.prc(ruleset, class),
        count: Map.fetch!(counts, class)
      }
    end
  end

  # ---- stage ----

  # Задача 3.17: раньше уровень 0 (раса/мировоззрение/статы) и уровень 1+
  # (класс/фиты/навыки) были ДВУМЯ разными экранами с двумя разными наборами
  # assign'ов — `active` больше не бывает 0 (см. `mount/3`, `select_level`),
  # так что «сцена» всегда как минимум уровень, а на уровне 1 к ней ещё
  # ДОБАВЛЯЕТСЯ раса/мировоззрение/статы, а не заменяет её собой.
  defp assign_stage(socket) do
    socket =
      socket
      |> assign_stage_defaults()
      |> assign_level()
      |> LevelPicks.assign_feat_streams()
      |> assign_choice_panel()
      |> LevelPicks.assign_spells()

    socket = if socket.assigns.active == 1, do: assign_creation(socket), else: socket

    # ⚠️ Строго последним: лента читает ГОТОВЫЕ assign'ы уровня (`slots`,
    # `class_choice`, `budget`, `spell_class`) — те самые, по которым шаблон
    # решает, рисовать ли секцию. Посчитай её раньше — и на уровне 1 она
    # соврала бы про секции, которых ещё нет в assign'ах.
    assign_stage_nav(socket)
  end

  # ---- лента секций (задача 3.30) ----

  # Заменяет собой ДВА снятых автодвижения: хук `.FocusPending`, который
  # подвозил экран к первой невыполненной секции, и `settle/2`, который сам
  # переключал уровень. Оба двигали экран без запроса — теперь то же самое
  # делает игрок кликом, а лента отвечает на «куда ещё надо зайти».
  #
  # 🔴 Главное в ней — РАЗВЯЗКА двух состояний, которые `data-pending="1"`
  # склеивал в одно (и из-за которой экран увозило к нерастраченным очкам
  # навыков — к тому, что игрок сознательно решил не тратить):
  #
  #   * `:hold`  — уровень без этого не закрыт. Янтарь `--todo`, громко.
  #   * `:todo`  — решение висит, но левелапу не мешает. Сталь `--todo-abil`,
  #                тише по построению (CLAUDE.md §6: десатурирована и потому
  #                не спорит с янтарём).
  #   * `:done`  — закрыто. Цвет снят, `--muted`: сделанное не тянет глаз.
  #
  # Красного здесь нет и быть не может: `--loss` уже значит «нарушение
  # правил» и горит на уровнях лестницы (`data-illegal="1"`, задача 1.3).
  # Два разных смысла одним цветом на одном экране — это и есть та ошибка,
  # ради которой в палитре два токена «не выбрано», а не один.
  defp assign_stage_nav(socket) do
    %{ruleset: ruleset, build: build, active: active} = socket.assigns
    taken = Build.character_level(build)

    items =
      for {key, id, label} <- nav_sections(socket.assigns) do
        %{key: key, id: id, label: label, state: nav_state(socket.assigns, key)}
      end

    next =
      if active < ruleset.level_cap do
        %{
          level: active + 1,
          # Тот же зажим, что у клика по лестнице (`clamp_level/3` через
          # `level_ceiling/2`, задача 3.69) — кнопка и лестница обязаны
          # соглашаться (CLAUDE.md §8): у обеих одна формула потолка, а не
          # каждая решает по-своему, что дальше нельзя.
          ready?: active + 1 <= level_ceiling(build, taken),
          # Причина, ПОЧЕМУ не готова — на кнопке она печатается словами
          # (`BuilderComponents.next_level/1`, `:if={not @next.ready?}`),
          # поэтому `nil`, когда готова, не мешает: шаблон её тогда не читает.
          why: next_level_reason(build, active, taken),
          # Единственный читатель «уровень закрыт целиком» после снятия
          # `settle/2`. Уйти вперёд можно всегда — но если уходишь с
          # незакрытого, об этом сказано словами прямо на кнопке.
          settled?: level_settled?(ruleset, build, active)
        }
      end

    assign(socket, :stage_nav, %{items: items, next: next})
  end

  # ⚠️ Единственный источник текста «недоступно почему» у кнопки «Уровень
  # N →» — задача 3.69 добавила ВТОРУЮ причину к прежней единственной,
  # и обе обязаны звучать словами, а не пряткой (CLAUDE.md §6). Ровно два
  # взаимоисключающих случая, оба выводятся из ТОГО ЖЕ сравнения, что
  # и `level_ceiling/2`, а не из отдельной формулы:
  #
  #   * `active > taken` — на текущем уровне ещё нет класса (это он и есть,
  #     свежий, никем не взятый), шагать дальше буквально некуда. Тот же
  #     случай, что был единственным до 3.69, текст не менялся;
  #   * `active == taken` — класс уже есть (иначе не совпало бы с `taken`),
  #     но потолок всё равно на месте: `level_ceiling/2` не даёт нового
  #     уровня без расы и мировоззрения. Называем ровно то, чего не хватает.
  #
  # `active < taken` (листаем уже взятое) сюда не попадает вовсе — там
  # `ready?` истинно, шаблон текст не запросит, а функция возвращает `nil`
  # на всякий случай (защита от рассинхрона, а не рабочая ветка).
  defp next_level_reason(_build, active, taken) when active > taken, do: "сначала класс"

  defp next_level_reason(%Build{race: race, alignment: alignment}, active, taken)
       when active == taken do
    case {is_nil(race), is_nil(alignment)} do
      {true, true} -> "сначала раса и мировоззрение"
      {true, false} -> "сначала раса"
      {false, true} -> "сначала мировоззрение"
      {false, false} -> nil
    end
  end

  defp next_level_reason(_build, _active, _taken), do: nil

  # ⚠️ Список ОБЯЗАН повторять `:if` секций в `builder_live.html.heex`: лента,
  # которая ведёт к несуществующей секции, — это ссылка в никуда. Под тестом
  # («лента называет ровно те секции, что нарисованы»), потому что копия
  # условий, которую никто не сверяет, разъезжается на первой же правке.
  defp nav_sections(assigns) do
    first? = assigns.active == 1

    [
      {"race", "section-race", "Раса", first?},
      {"alignment", "section-alignment", "Мировоззрение", first?},
      # Подписи короче, чем `eyebrow` у самих секций («Класс уровня»,
      # «Прибавка к характеристике», «Фиты уровня»): в горизонтальной ленте
      # платит ширина, а слово и так однозначно рядом с номером уровня.
      # Слова, а не иконки — какая иконка у «Мировоззрения»?
      {"class", "section-class", "Класс", true},
      {"point_buy", "section-point-buy", "Характеристики", first?},
      {"domains", "section-domains", assigns.class_choice && assigns.class_choice.heading,
       not is_nil(assigns.class_choice)},
      # ⚠️ «Стат», а не «Прибавка» — правка Dan 15.08.2026, дословно:
      # «"Прибавка" сама по себе не несёт смысла о том, что именно
      # прибавляется». Подпись секции («Прибавка к характеристике») при этом
      # осталась как была: там рядом есть место договорить, в ленте — нет.
      # Слово из глоссария (CLAUDE.md §4, «статы, характеристики»), а не
      # выдуманное сокращение.
      {"increase", "section-increase", "Стат", assigns.increase_level?},
      {"feats", "section-feats", "Фиты", assigns.slots != [] or assigns.granted != []},
      {"spells", "section-spells", "Заклинания", not is_nil(assigns.spell_class)},
      {"skills", "section-skills", "Навыки", not is_nil(assigns.budget)}
    ]
    |> Enum.filter(fn {_key, _id, _label, shown?} -> shown? end)
    |> Enum.map(fn {key, id, label, _shown?} -> {key, id, label} end)
  end

  defp nav_state(assigns, key) do
    cond do
      not section_pending?(assigns, key) -> :done
      holds_level?(assigns, key) -> :hold
      creation_hold?(assigns, key) -> :hold
      true -> :todo
    end
  end

  # ⚠️ Единственное исключение из «янтарь = держит уровень», и оно НЕ про
  # правила игры (задача 3.32, требование Dan 15.08.2026, дословно: «на этапе
  # создания персонажа "Характеристики" должны быть выделены обязательным
  # цветом, в поинт-бае должно остаться 0 очков, после этого они считаются
  # заполненными»).
  #
  # Почему отдельной функцией, а не веткой `holds_level?/2`: очки поинт-бая
  # уровень НЕ держат, и `level_settled?/3` их не спрашивает — уйти на 2-й
  # уровень с нераспределёнными очками игра позволяет, и запрещать это мы
  # не имеем права. Дописать сюда ветку значило бы соврать в названии функции,
  # а следом и в кнопке «Уровень N →», которая читает то же правило.
  #
  # Но уровень 1 — это создание персонажа, и нераспределённый поинт-бай там
  # не «можно доделать»: персонажа с восьмёрками во всех характеристиках
  # не собирают, а стальной цвет говорит «необязательно». Условие «заполнено»
  # новое не заводится — это ровно `section_pending?(assigns, "point_buy")`,
  # то есть «свободных очков 0 и кастерский пол не нарушен».
  #
  # ⚠️ **Раса и мировоззрение жили здесь РОВНО ОДИН ДЕНЬ, 21.08.2026**
  # (задача 3.68, запрос Dan: «на 1 уровне расу и мировоззрение выделим тем
  # же "обязательным" цветом… В самой игре пока их не выберешь дальше не
  # продвинешься. Нам не нужны ограничения, просто цвет»). В тот момент это
  # было точным описанием: игра дальше не пускает, но перехода в самом
  # конструкторе ещё не было, и заводить им ветку в `holds_level?/2` значило
  # бы соврать — та ветка держит ПЕРЕХОД, а его нечем было держать.
  #
  # 🔴 Задача 3.69, ПЕРЕСМОТР В ТОТ ЖЕ ДЕНЬ: Dan передумал, дословно —
  # «кнопку перевода на 2 уровень я бы все-таки блокировал, пока раса
  # и мировоззрение не выбраны, так будет логичнее». Как только переход стал
  # настоящим (`creation_complete?/1`, `level_ceiling/2`), держать эти два
  # ключа здесь стало ложью В ДРУГУЮ СТОРОНУ: функция уже называется «цвет
  # БЕЗ запрета», а запрет появился. Оба переехали в `holds_level?/2` —
  # единственное место, где «янтарь» и значит «держит», без оговорок.
  #
  # `point_buy` остался: 3.32 просила цвет без запрета, и 3.69 этот запрос
  # не трогает — переход с нераспределёнными очками по-прежнему легален
  # что в ядре, что в этом конструкторе (см. `holds_level?/2` — там же
  # почему заводить ему ветку означало бы соврать).
  #
  # ⚠️ Своего условия «заполнено» не заводится: `section_pending?(assigns,
  # "point_buy")` уже отвечает на этот вопрос, и `nav_state/2` спрашивает
  # его первым.
  defp creation_hold?(assigns, "point_buy"), do: assigns.active == 1
  defp creation_hold?(_assigns, _key), do: false

  # ⚠️ У класса, прибавки, фитов и классового выбора — ни одной новой
  # формулы: спрашиваются те же три слагаемых `level_settled?/3` и ничего
  # сверх них. Ответ читается как «ЕСЛИ секция ждёт решения
  # (`section_pending?/2`), то держит ли оно уровень».
  #
  #   * класс — `true` без условий: секция ждёт ровно тогда, когда класса
  #     на уровне нет, а без класса уровня не существует вовсе;
  #   * прибавка — `true` без условий: секция вообще рисуется только на
  #     кратных четырём, и её `section_pending?/2` — дословно второе
  #     слагаемое `level_settled?/3`;
  #   * фиты — держат ТОЛЬКО пустые слоты. `section_pending?/2` шире: он ждёт
  #     ещё и невыбранное значение у ВЫДАННОГО фита, а оно уровень не держит
  #     (см. его же комментарий — в `level_settled?/3` это заблокировало бы
  #     переход насовсем);
  #   * классовый выбор — держит только ОБЯЗАТЕЛЬНЫЙ (домены клирика).
  #     Школа волшебника необязательна, `complete?/3` для неё тривиально
  #     `true` — и `class_choice_settled?/3` отвечает ровно это.
  #
  # Статы, заклинания, навыки — уровень НЕ держат, и это не мнение: замерено
  # живьём 15.08.2026 — класс берётся на билде без расы и без мировоззрения,
  # и ЯДРО (`Rules.validate_level_up/3`) этот левелап проходит.
  #
  # 🔴 **Раса и мировоззрение — держат, но по формуле СВОЕЙ, не общей
  # (задача 3.69, ПЕРЕСМОТР 3.68 — история у `creation_hold?/2` выше).**
  # Единственная пара в списке, которая держит не потому, что об этом просит
  # `level_settled?/3` (ядро про расу и мировоззрение не знает и не должно —
  # `creation_complete?/1` и его doc), а потому что БЕЗ них веб-слой сам
  # отказывается пускать курсор дальше 1-го уровня. Измерение 15.08.2026
  # не опровергнуто — ЯДРО такой левелап по-прежнему разрешает; с 21.08.2026
  # НЕ РАЗРЕШАЕТ конкретно этот конструктор, и это разные утверждения.
  # `assigns.active == 1` — тот же зажим, что был у обеих в `creation_hold?/2`
  # весь день 3.68: секции «Раса»/«Мировоззрение» и не рисуются на других
  # уровнях (`nav_sections/1`), так что практического отличия от голого
  # `true` нет, а условие явно называет, откуда берётся факт.
  #
  # ⚠️ Но янтарь в ленте эта функция раздаёт НЕ ОДНА: рядом стоит
  # `creation_hold?/2` — исключение для поинт-бая на уровне 1 (задача 3.32).
  # Оно про громкость сигнала БЕЗ запрета; здесь — про сам запрет.
  # Кто ищет «что мешает левелапу» — читает эту функцию, `level_ceiling/2`
  # и `level_settled?/3`.
  defp holds_level?(_assigns, "class"), do: true
  defp holds_level?(_assigns, "increase"), do: true

  defp holds_level?(assigns, "feats"),
    do: Feats.open_slots(assigns.ruleset, assigns.build, assigns.active) != []

  defp holds_level?(assigns, "domains"),
    do: not class_choice_settled?(assigns.ruleset, assigns.build, assigns.active)

  defp holds_level?(assigns, key) when key in ["race", "alignment"],
    do: assigns.active == 1

  defp holds_level?(_assigns, _key), do: false

  @doc false
  # Состояние словами — для тех, кто цвета и подчёркивания не видит вовсе.
  # Печатается в `.sr-only` рядом с подписью: на экране состояние несут цвет
  # И форма подчёркивания, а скринридеру нужна третья, текстовая копия.
  def nav_state_word(:hold), do: "— здесь нужно решение"
  def nav_state_word(:todo), do: "— можно доделать"
  def nav_state_word(:done), do: "— готово"

  # Общие defaults для всех уровней; `assign_creation/1` поверх них наполняет
  # `races`/`point_buy_*` только на уровне 1 — на остальных они так и остаются
  # пустыми/нулевыми, и шаблон их для этих уровней не читает (обе группы
  # секций в `stage-body` завязаны на `@active == 1`).
  defp assign_stage_defaults(socket) do
    assign(socket,
      races: [],
      point_buy_rows: [],
      point_buy_left: 0,
      point_buy_budget: PointBuy.budget(socket.assigns.ruleset),
      point_buy_floor: nil,
      class_cards: [],
      increase_cards: [],
      slots: [],
      granted: [],
      granted_choices: [],
      skill_rows: [],
      skill_chips: [],
      spell_slots: [],
      spell_circles: %{},
      spell_class: nil,
      spell_class_level: nil,
      spell_note: nil,
      spell_count: 0,
      budget: nil,
      chosen_class: nil,
      increase_level?: false,
      increase_chosen: nil,
      epic?: false,
      before_stats: nil,
      hold_note: nil,
      available_count: 0,
      blocked_total: 0,
      searching?: false,
      choice_panel: nil,
      class_choice: nil
    )
  end

  # Панель второго шага, собранная заново на каждой перерисовке — а не
  # сохранённая при клике.
  #
  # ⚠️ Так она не может протухнуть. Список значений зависит от билда (какие
  # школы уже заняты, где есть базовый `Spell focus`), а билд между открытием
  # панели и кликом по значению меняется: игрок мог освободить слот или сменить
  # класс уровня. Снимок значений, снятый один раз, показывал бы вчерашнее.
  # Заодно панель сама закрывается, когда слот перестал существовать.
  defp assign_choice_panel(socket) do
    %{ruleset: ruleset, build: build, active: active, feat_choice: pending} = socket.assigns

    panel =
      with %{feat: id, slot: slot_id, level: ^active} <- pending,
           true <- Enum.any?(FeatSlots.at(build, ruleset, active), &(&1.id == slot_id)),
           %{} = options <- Feats.choice_options(ruleset, build, active, id, slot_id) do
        options
        |> Map.put(:feat, id)
        |> Map.put(:feat_name, Labels.feat_name(ruleset, id))
        |> Map.put(:slot, slot_id)
        |> Map.put(:slot_label, slot_label(ruleset, build, active, slot_id))
        |> Map.put(:blocked, Enum.map(options.blocked, &blocked_option(&1, ruleset)))
      else
        _ -> nil
      end

    assign(socket, :choice_panel, panel)
  end

  defp blocked_option(option, ruleset) do
    Map.put(option, :reason_texts, Enum.map(option.reasons, &Feats.reason(&1, ruleset)))
  end

  defp slot_label(ruleset, build, level, slot_id) do
    case Enum.find(FeatSlots.at(build, ruleset, level), &(&1.id == slot_id)) do
      nil -> nil
      slot -> Labels.slot_label(ruleset, slot)
    end
  end

  defp racial_modifiers(race) do
    for ability <- Labels.ability_order(),
        value = Map.get(race.ability_modifiers, ability, 0),
        value != 0,
        do: %{label: Labels.ability(ability), value: value}
  end

  # Задача 3.17: раньше это была вся «сцена» нулевого уровня; теперь это
  # надстройка НАД обычным уровнем 1 (`assign_level/1` уже отработал) —
  # только раса, мировоззрение и статы, только на уровне 1 (см. `assign_stage/1`).
  defp assign_creation(socket) do
    %{ruleset: ruleset, build: build, point_buy_reset: reset} = socket.assigns

    races =
      for {id, race} <- Enum.sort_by(ruleset.races, fn {_id, r} -> r.ru || r.name end) do
        %{
          id: id,
          ru: Labels.race_ru(ruleset, id),
          en: Labels.race_en(ruleset, id),
          chosen?: build.race == id,
          modifiers: racial_modifiers(race)
        }
      end

    # Финал — с прибавками каждые 4 уровня и вещами — переехал в разбор
    # характеристик панели итогов (CLAUDE.md §6, задача 3.2): здесь остался
    # ровно тот каскад, что решается на этом шаге — покупка → раса → старт.
    start = Abilities.scores_at(build, ruleset, 0)
    reset_abilities = if reset, do: reset.abilities, else: MapSet.new()

    # ⚠️ Задача 3.156: степпер печатает `row.start`/`row.start_mod` (итог,
    # с расой) — то самое число, что стоит в списке характеристик у самой
    # игры, а не `row.base` (покупку). Кнопки по-прежнему двигают ПОКУПКУ —
    # `can_raise?`/`can_lower?` ниже читают локальный `base`, не то, что
    # печатается, — и это не меняется: игрок кликает «+», видит итог +1,
    # ровно так это выглядит и в игре. `base`/`racial` остаются в строке
    # (дёшево посчитаны, и на них может опереться будущая подсказка),
    # просто шаблон их больше не печатает отдельными колонками — двое живых
    # игроков читали степпер как окончательное значение и путали характеристику.
    rows =
      for ability <- Labels.ability_order() do
        base = Map.get(build.base_abilities, ability, PointBuy.floor(ruleset, build, ability))

        %{
          id: ability,
          label: Labels.ability(ability),
          base: base,
          racial: Map.get(start, ability, base) - base,
          start: Map.get(start, ability, base),
          start_mod: Abilities.modifier(Map.get(start, ability, base)),
          can_raise?: PointBuy.can_raise?(ruleset, build.base_abilities, base),
          can_lower?: PointBuy.can_lower?(ruleset, build, ability, base),
          # Подсветка сброшенной строки (AGENT_QUEUE §3.17, решение 3) —
          # `nil`, пока `:point_buy_reset` пуст, так же как остальная колонка
          # молчит про непроисходившее.
          reset?: MapSet.member?(reset_abilities, ability)
        }
      end

    socket
    |> assign(:races, races)
    |> assign(:point_buy_rows, rows)
    |> assign(:point_buy_left, PointBuy.remaining(ruleset, build.base_abilities))
    |> assign(:point_buy_budget, PointBuy.budget(ruleset))
    # Почему очков 27, а не 30 — см. `Labels.point_buy_floor/2`. Молча
    # уменьшенный бюджет читается как ошибка калькулятора.
    |> assign(:point_buy_floor, Labels.point_buy_floor(ruleset, build))
  end

  defp assign_level(socket) do
    %{ruleset: ruleset, build: build, active: level} = socket.assigns
    before = Build.truncate(build, level - 1)
    before_stats = Rules.compute(before, ruleset)

    socket
    |> assign(:before_stats, before_stats)
    |> assign(:chosen_class, Build.class_at(build, level))
    |> assign(:increase_level?, MapSet.member?(ruleset.epic.ability_increase_levels, level))
    |> assign(:increase_chosen, Map.get(build.ability_increases, level))
    |> assign(:epic?, level >= ruleset.epic.starts_at)
    |> assign(:slots, Feats.slots(ruleset, build, level))
    |> assign(:granted, granted_rows(ruleset, build, level))
    |> assign(:granted_choices, Feats.granted_choice_rows(ruleset, build, level))
    |> assign(:class_choice, class_choice_panel(ruleset, build, level))
    |> assign(:hold_note, hold_note(socket.assigns, ruleset, build, level))
    |> assign_class_cards(before, before_stats)
    |> assign_increase_cards()
    |> assign_skills()
  end

  # The stage panel for a class's own choice — `nil` everywhere except the
  # class's own first class level, same rule `ladder_class_choice/3` uses for
  # the ladder's mark, so the two never disagree about which row this is.
  #
  # Unlike `assign_choice_panel/1` (a feat's second step), there is no pending
  # state to read here: a domain chip toggles straight into the build on
  # click (`toggle_class_choice`), so this is rebuilt from `build` alone on
  # every render — the same "never a stale snapshot" reasoning, just with one
  # fewer moving part because there is no open/closed panel to track.
  defp class_choice_panel(ruleset, build, level) do
    with class when not is_nil(class) <- Build.class_at(build, level),
         1 <- Build.class_level_at(build, level),
         %{} = spec <- ClassChoices.spec(class, ruleset) do
      chosen = Build.class_choice(build, class)

      %{
        class: class,
        heading: Labels.class_choice_heading(class),
        count: spec.count,
        required?: spec.required?,
        complete?: ClassChoices.complete?(build, class, ruleset),
        # Raw ids, not just names — задача 3.170's «General» button toggles
        # OFF whatever is currently held (`Build.toggle_class_choice/3` needs
        # the id, `phx-value-choice` cannot round-trip a printed name back
        # through `Ids.fetch_class_choice/3`).
        chosen: chosen,
        chosen_names: Enum.map(chosen, &Labels.class_choice_value_name(ruleset, class, &1)),
        # Задача 3.86: что специализация ДАЁТ — одной строкой над чипами,
        # потому что у всех восьми школ это одно и то же предложение; что она
        # ОТНИМАЕТ — на каждом чипе своё число (`class_choice_values/4`).
        # `nil` у клирика: его выбор арифметики за собой не несёт вовсе.
        gain: Labels.specialization_gain(Spells.specialization(ruleset, class)),
        # `spec.count`, not the `full?` boolean the panel used to compute
        # here — задача 3.171 needs the count itself inside
        # `class_choice_values/4` to tell a full ONE-value choice (a
        # Wizard's school: a fresh click REPLACES, so nothing there is
        # disabled) from a full MULTI-value one (a Cleric's two domains:
        # still refused, no rule says which held value a click should
        # evict).
        values: class_choice_values(ruleset, class, chosen, spec.count),
        # Задача 3.170: слово клиента для «ничего не выбрано» — Волшебника
        # `General`. `nil` у клирика (обязательный выбор, «без домена» —
        # незаконное состояние) и у любого будущего класса с обязательным
        # выбором: гейт по данным (`Loader.Classes.
        # build_class_choice_no_selection/2` роняет сборку, если факт назван
        # для required?: true класса), а не по `not spec.required?` здесь —
        # кнопка появляется только там, где данные прямо назвали слово.
        no_selection_name: ClassChoices.no_selection_name(class, ruleset)
      }
    else
      _ -> nil
    end
  end

  # 🔴 Цена выбора считается ОДИН раз на всю панель, а не по чипу: за каждым
  # числом стоит проход по всем 304 заклинаниям ruleset'а, и восемь одинаковых
  # проходов на один рендер — ровно та экономия, которую легко потерять,
  # спрятав вызов внутрь `Labels`.
  defp class_choice_values(ruleset, class, chosen, count) do
    costs = Spells.specialization_costs(ruleset, class)
    full? = length(chosen) >= count

    case ClassChoices.values(class, ruleset) do
      {:ok, values} ->
        for value <- values do
          chosen? = value in chosen

          %{
            id: value,
            name: Labels.class_choice_value_name(ruleset, class, value),
            chosen?: chosen?,
            # A value that is not held and there is no room left for is shown,
            # never hidden — CLAUDE.md §6 hides a value only when *this same*
            # choice already holds it (`chosen?` above already covers that);
            # "no room left" is a fact about the moment, not about the value,
            # so the button stays visible and simply refuses the click.
            #
            # ⚠️ Задача 3.171: `and count > 1` — a full ONE-value choice is
            # not a wall, it is "something is already picked": a click on a
            # fresh value there REPLACES it (`Rules.ClassChoices.click/4`
            # answers `:replace`, never `{:error, [class_choice_full: …]}`,
            # for exactly this shape), so nothing here has a reason to
            # refuse the click. `count > 1` (a Cleric's two domains) keeps
            # the wall: which of several held values a click should evict
            # has no rule anywhere.
            disabled?: not chosen? and full? and count > 1,
            # Задача 3.86: цена специализации — противоположная школа И сколько
            # заклинаний она закрывает. ⚠️ Раньше здесь стояло имя школы
            # в `title` кнопки, то есть на мобильном не существовало вовсе —
            # та же ошибка, за которую §6 убрал плашку «от класса ×N».
            # `nil` у клирика: у его доменов цены в числах нет.
            cost: Labels.specialization_cost(ruleset, Map.get(costs, value))
          }
        end

      :none ->
        []
    end
  end

  defp assign_class_cards(socket, before, before_stats) do
    %{ruleset: ruleset, build: build, active: level} = socket.assigns

    if section_open?(socket.assigns, "class") do
      cards =
        for {id, class} <- Enum.sort_by(ruleset.classes, fn {_id, c} -> c.name end) do
          reasons =
            case LevelUp.validate(build, %{class: id, at: level}, ruleset, before_stats) do
              :ok -> []
              {:error, reasons} -> reasons
            end

          # The card describes the CANDIDATE, so its slots are computed from the
          # build this class would produce — the same hypothetical the delta is
          # computed from. Reading them off `build` instead was a real bug: a
          # Fighter card on level 1 promised one feat where the class grants two
          # (общий + бонус Fighter), and once a class was chosen every card
          # inherited *its* slots.
          candidate = Build.add_level(before, id)

          %{
            id: id,
            name: class.name,
            prestige?: class.prestige?,
            hue: hue(id),
            prc: if(class.prestige?, do: "1"),
            next: Map.get(before_stats.class_levels, id, 0) + 1,
            chosen?: Build.class_at(build, level) == id,
            reasons: Enum.map(reasons, &Labels.reason(&1, ruleset)),
            locked?: reasons != [],
            divider?: false,
            deltas:
              if reasons == [] do
                before_stats
                |> GearPanel.delta_chips(Rules.compute(candidate, ruleset))
                |> GearPanel.card_chips(GearPanel.choice_chips(ruleset, candidate, level))
              else
                []
              end
          }
        end

      assign(socket, :class_cards, order_class_cards(cards))
    else
      assign(socket, :class_cards, [])
    end
  end

  # Available first, then the locked ones, both alphabetical. Interleaving the
  # two makes the eye hunt for what can be taken at all; the locked half is still
  # shown, because the reason is the part that teaches the rules (CLAUDE.md §6).
  # The first locked card carries the divider that separates the groups.
  defp order_class_cards(cards) do
    {available, locked} = Enum.split_with(cards, &(not &1.locked?))

    case locked do
      [] -> available
      [first | rest] -> available ++ [%{first | divider?: true} | rest]
    end
  end

  defp assign_increase_cards(socket) do
    %{ruleset: ruleset, build: build, active: level} = socket.assigns

    cards =
      if socket.assigns.increase_level? do
        current = Abilities.scores_at(build, ruleset, level - 1)

        for ability <- Labels.ability_order() do
          score = Map.get(current, ability, 0)

          %{
            id: ability,
            label: Labels.ability(ability),
            from: score,
            to: score + 1,
            mod_from: Abilities.modifier(score),
            mod_to: Abilities.modifier(score + 1),
            chosen?: socket.assigns.increase_chosen == ability
          }
        end
      else
        []
      end

    assign(socket, :increase_cards, cards)
  end

  defp assign_skills(socket) do
    %{ruleset: ruleset, build: build, active: level} = socket.assigns

    if Build.class_at(build, level) do
      budget = Skills.budget(build, ruleset, level)
      carried = Skills.budget(build, ruleset, level - 1).free
      here = Map.get(build.skills, level, %{})
      character_level = Build.character_level(build)

      invested =
        for {id, skill} <- ruleset.skills,
            Build.skill_ranks(build, id, character_level) > 0 or Map.has_key?(here, id),
            do: {id, skill}

      rows = Enum.map(invested, &skill_row(&1, ruleset, build, level, budget, here))
      shown = MapSet.new(invested, &elem(&1, 0))

      socket
      |> assign(:budget, %{
        free: budget.free,
        earned: budget.earned,
        per_level: Skills.points_at(build, ruleset, level),
        carried: carried
      })
      |> assign(:skill_rows, Enum.sort_by(rows, & &1.name))
      |> assign(:skill_chips, skill_chips(socket.assigns, shown))
    else
      socket
      |> assign(:budget, nil)
      |> assign(:skill_rows, [])
      |> assign(:skill_chips, [])
    end
  end

  defp skill_row({id, skill}, ruleset, build, level, budget, here) do
    total = Build.skill_ranks(build, id, level)
    cap = Skills.rank_cap(build, ruleset, id, level)
    cost = Skills.rank_cost(build, ruleset, id, level)
    at_level = Map.get(here, id, 0)

    # Сколько ещё разрешают правила на ЭТОМ уровне и сколько позволяет кошелёк —
    # два разных ограничения, и упереться можно в любое, поэтому они считаются
    # порознь и объясняются порознь.
    headroom = Skills.rank_room(build, ruleset, id, level) - at_level
    affordable = div(budget.free, cost)
    room = min(headroom, affordable)

    row = %{
      id: id,
      name: skill.name,
      ability: skill.key_ability && Labels.ability(skill.key_ability),
      class?: cost == 1,
      cost: cost,
      total: total,
      cap: cap,
      at_level: at_level,
      capped?: headroom <= 0,
      can_raise?: room > 0,
      can_lower?: at_level > 0,
      room: room
    }

    Map.put(row, :why, rank_block(ruleset, build, level, row, headroom, budget.free))
  end

  # ⚠️ Молча заблокированный степпер читается как поломка калькулятора, а не как
  # правило игры (CLAUDE.md §6: недоступное показываем С ПРИЧИНОЙ). Самый частый
  # и самый неочевидный случай — уровень непрофильного класса: Sorcerer 1–39
  # с 35 рангами Spellcraft берёт 40-м уровнем Fighter, и добавить нельзя ни
  # одного ранга, хотя купленные 35 никуда не деваются.
  #
  # Пустой кошелёк здесь НЕ объясняется: «0 очков свободно» стоит крупно над
  # списком, и повторить это на каждой из десяти строк значило бы завалить
  # шумом ровно ту строку, ради которой блок и заведён. Объясняется только
  # случай, где кошелёк не пуст, а ранга всё равно не хватает.
  defp rank_block(ruleset, build, level, row, headroom, free) do
    class = Labels.class_name(ruleset, Build.class_at(build, level))

    cond do
      headroom > 0 and free >= row.cost -> nil
      row.cap == 0 and Skills.exclusive?(ruleset, row.id) -> "#{class} его не качает вовсе"
      row.total > row.cap -> "на уровне #{class} потолок #{row.cap} — купленное остаётся"
      headroom <= 0 -> "на уровне #{class} потолок #{row.cap}"
      free > 0 -> "не хватает очков: ранг стоит #{row.cost}"
      true -> nil
    end
  end

  defp skill_chips(assigns, shown) do
    %{ruleset: ruleset, build: build, active: level, skill_query: query} = assigns

    if assigns.skill_add? do
      ruleset.skills
      |> Enum.reject(fn {id, _} -> MapSet.member?(shown, id) end)
      |> Enum.flat_map(fn {id, skill} ->
        case Fuzzy.match(query, skill.name) do
          nil ->
            []

          match ->
            [
              %{
                id: id,
                name: skill.name,
                segments: Fuzzy.segments(skill.name, match.positions),
                score: match.score,
                class?: Skills.class_skill_at?(build, ruleset, id, level),
                cost: Skills.rank_cost(build, ruleset, id, level),
                open?: Skills.rank_room(build, ruleset, id, level) > 0,
                why: chip_why(ruleset, build, level, id)
              }
            ]
        end
      end)
      |> Enum.sort_by(&{-&1.score, &1.name})
    else
      []
    end
  end

  # ⚠️ Чип — второй вход в ту же покупку, и он умел проваливаться молча: клик
  # по навыку, который этот уровень взять не даёт, просто ничего не делал, и
  # строка не появлялась. Правило «потолок по классу уровня» делает такие чипы
  # чаще: эксклюзивный навык (UMD, Perform, Animal Empathy) закрыт на КАЖДОМ
  # уровне, чей класс его не даёт, а не только у билда без такого класса вовсе.
  #
  # Цена у закрытого чипа не печатается: «2» значило бы «можно за два очка».
  defp chip_why(ruleset, build, level, id) do
    class = Labels.class_name(ruleset, Build.class_at(build, level))
    cap = Skills.rank_cap(build, ruleset, id, level)

    cond do
      Skills.rank_room(build, ruleset, id, level) > 0 -> nil
      Skills.exclusive?(ruleset, id) -> "#{class} этот навык не качает вовсе"
      true -> "на уровне #{class} потолок #{cap}"
    end
  end

  # The delta is the difference between two full computations of the whole
  # build — the candidate replaces the active level, everything after it stays.
  @row_order ~w(main save skill choice)

  @doc false
  def chip_rows(chips) do
    for row <- @row_order,
        in_row = Enum.filter(chips, &(&1.row == row)),
        in_row != [],
        do: %{row: row, chips: in_row}
  end

  # ------------------------------------------------------------------ helpers --

  # Клик по находке в сводке «Вещей» (`builder_live.html.heex`, кнопки
  # в `#gear-issues-refused`/`#gear-issues-capped`) — `JS.push/2` вместо
  # голого `phx-click="jump_to_gear_issue"` + `phx-value-target`, тот же
  # server round-trip, но с добавкой на КЛИЕНТЕ.
  #
  # 🔴 Хвост задачи 3.134 (проверка координатора 28.08.2026, живой Chrome
  # 1440×900): счёт сервера уже был верным на десктопе (`.stats` там
  # `position: sticky`, вся панель видна целиком, у неё нет своего
  # «свёрнуто/развёрнуто»), а на мобильном (`< 940px`) «Итого» — ЕЩЁ ОДНА
  # шторка, `#totals-panel[data-open]`, отдельная от `gear_open?`
  # (`handle_event("jump_to_gear_issue", …)` рядом), и живёт она ЦЕЛИКОМ
  # на клиенте — переключает её JS-команда на `#sheet-toggle`, сервер о её
  # состоянии не знает вовсе. Без этой добавки клик по находке на телефоне
  # СЧИТАЛ верно (`gear_open?` → true, `ScrollBus` сдвигал `scrollTop`
  # контейнера туда, куда нужно), а показать было НЕЧЕГО: шторка оставалась
  # свёрнутой, и прокрутка проходила НЕВИДИМО — в полосе высотой
  # `--sheet-h` (~88px) под кнопкой-сводкой чисел, а не в развёрнутой
  # панели. Замер: скриншот headless Chrome (`mobile: true`) до/после клика
  # по находке «щит не считается» — после клика та же свёрнутая полоса
  # вместо HP/AC/AB показывает обрывок строки щита, сама шторка не открылась.
  #
  # ⚠️ `set_attribute`, а не `toggle_attribute`: находка всегда хочет
  # ПОКАЗАТЬ (тот же довод, что у безусловного `assign(:gear_open?, true)`
  # на сервере) — повторный клик не обязан закрывать шторку, которую
  # он же и открыл.
  #
  # ⚠️ Оба атрибута ставятся ВМЕСТЕ, а не только `data-open`: собственный
  # клик `#sheet-toggle` переключает `data-open` на `#totals-panel`
  # и `aria-expanded` на себе одной парой (см. разметку кнопки), и
  # рассинхрон здесь означал бы, что следующий клик по самой кнопке-шторке
  # дважды отрицает — например, `data-open` уйдёт `1→0` (закрыть), пока
  # `aria-expanded` в тот же момент уйдёт `false→true` (открыть), если бы
  # мы тронули только первый атрибут.
  #
  # ⚠️ На десктопе (`≥ 940px`) у `data-open`/`aria-expanded` нет
  # соответствующего CSS-правила вовсе — команда там безвредна, а не
  # «работает иначе»: `.stats[data-open="1"]` живёт только внутри
  # мобильного `@media (max-width: 940px)`.
  @doc false
  def gear_issue_jump(target) do
    JS.push("jump_to_gear_issue", value: %{"target" => target})
    |> JS.set_attribute({"data-open", "1"}, to: "#totals-panel")
    |> JS.set_attribute({"aria-expanded", "true"}, to: "#sheet-toggle")
  end

  @doc false
  def signed(nil), do: "?"
  def signed(value) when value >= 0, do: "+#{value}"
  def signed(value), do: Integer.to_string(value)

  @doc false
  def number(nil), do: "?"
  def number(value), do: to_string(value)

  # Hues are an assigned table, not a hash of the id — see
  # `BuildCalculatorWeb.Builder.Palette` for why a hash was the wrong tool.
  @doc false
  defdelegate hue(id), to: Palette

  # ⚠️ Задача 3.18 (наблюдение Dan 05.08.2026): секция БОЛЬШЕ НЕ сворачивается
  # сама. Умолчание — «открыта», а свёрнутой её делает только сам игрок,
  # кликом по шапке; `sections` теперь означает ровно «что игрок сложил».
  #
  # Раньше здесь стояло `Map.get(assigns.sections, key, section_default(...))`,
  # то есть готовая секция схлопывалась сама — «готовое не занимает экран»
  # (CLAUDE.md §6). Довод не отменён, он ПРОИГРАЛ второму: правка сделанного
  # выбора должна оставаться дешёвой. Почему именно так и что это стоило —
  # в `section_pending?/2` ниже.
  @doc false
  def section_open?(assigns, key), do: Map.get(assigns.sections, key, true)

  # «На этой секции ещё висит решение» — то же самое, чем эта функция была
  # всегда, но уже в ТРЕТЬЕЙ роли, и ни одна из формул ниже за все три раза
  # не изменилась ни на бит. Менялся только потребитель:
  #
  #   * до 3.18 — «открыта ли секция по умолчанию» (звалась `section_default/2`);
  #   * 3.18 — цель, к которой хук `.FocusPending` подвозил экран;
  #   * 3.30 — состояние пункта в ленте секций (`assign_stage_nav/1`), плюс
  #     всё тот же `data-pending="1"` на самой секции.
  #
  # ⚠️ Ответ этой функции — «висит решение», и только. «Держит ли оно
  # уровень» — ДРУГОЙ вопрос, и его задаёт `holds_level?/2`: у секции фитов
  # эта функция ждёт ещё и невыбранное значение выданного фита, которое
  # уровень не держит (см. её ветку ниже).
  #
  # ⚠️ Почему сворачивание убрано, а не отложено (задача 3.18, замеры
  # designer 09.08.2026, Chromium 1440×900, `liveSocket.enableLatencySim(300)`).
  # Жалоба Dan была двойная: «экран дёргается, элементы слегка ездят» и
  # «зачастую хочется изменить выбор, а секция уже скрыта».
  #
  #   * Клик по расе на пустом билде: документ 3302 → 2956 px, и всё, что
  #     ниже расы, прыгало вверх на 346 px. Клик по классу с курсором на
  #     карточках: 3302 → 2285 px, секция статов уезжала на 1213 px, и на
  #     месте курсора оказывался `#point-buy-budget` — другая секция.
  #   * Штатное scroll anchoring это НЕ ЛОВИТ и не могло: в первом случае
  #     `scrollY` уже 0 и компенсировать нечем, во втором браузер выбирает
  #     якорь среди видимого, а видимое — те самые карточки, которые клик
  #     удаляет. Замерено: компенсация 0 px в обоих сценариях. Никакой CSS
  #     тут не помогает — помогает только не удалять содержимое.
  #   * «Схлопывать позже, когда игрок сделал выбор в СЛЕДУЮЩЕЙ секции»
  #     (вариант координатора) рывок бы НЕ убрало: весь редактор уровня 1
  #     живёт при `scrollY == 0`, а значит секция расы, схлопываясь под уже
  #     открытой секцией мировоззрения, сдвинула бы её на те же 346 px. Рывок
  #     сдвинулся бы на один шаг, а не исчез.
  #
  # Оплачено длиной страницы: уровень 1 со всеми решениями — 1821 → 3352 px
  # (1440×900).
  #
  # ⚠️ Здесь стояло «плата возвращается прокруткой: `.FocusPending` подвозит
  # экран к первой секции» — УСТАРЕЛО, задача 3.30 (решение Dan 15.08.2026).
  # Хука нет: он двигал экран сам, и тестировщику это не понравилось. Плату
  # теперь возвращают две вещи, и обе — по клику игрока: липкая лента секций
  # (навигация вместо прокрутки руками) и вторая колонка у сетки классов
  # на узких экранах.
  #
  # ⚠️ И вторая половина той же строки — «второй рычаг (своя область
  # прокрутки у сетки классов) СОЗНАТЕЛЬНО не тронут: он ухудшил бы главное
  # действие ради второстепенного» — ПЕРЕСМОТРЕНА той же задачей. Довод
  # не отменён; он проиграл тому, что страница на телефоне всё равно вдвое
  # длиннее экрана. Тронут при этом не он, а соседний: минимум колонки
  # в `.cards` опущен до 430px ширины окна (app.css, `#class-cards`), и
  # сетка на 360px усохла 2828 → 1845 px БЕЗ вложенной прокрутки. Сама
  # прокрутка так и не заведена — она остаётся предложением для Dan.
  #
  # ⚠️ Задача 3.17: раньше здесь стояло `section_default(%{active: 0}, _key),
  # do: true` — «на нулевом уровне открыто всё», и годилось это только пока
  # нулевой уровень был отдельным экраном на три секции. После слияния на
  # уровне 1 бывает до семи секций разом (раса, мировоззрение, класс, статы,
  # домены/школа, фиты, навыки — решение Дана, AGENT_QUEUE §3.17), и
  # раскрывать их все одной строкой уже нельзя: три новые секции ниже несут
  # каждая СВОЮ формулу «не закончено», тем же приёмом, что и класс ниже.
  # `point_buy` — не исключение: ждёт, пока есть что тратить, той же формулой,
  # что у секции навыков (с одной оговоркой — см. её комментарий).
  @doc false
  def section_pending?(assigns, "race"), do: is_nil(assigns.build.race)
  def section_pending?(assigns, "alignment"), do: is_nil(assigns.build.alignment)

  # ⚠️ «Свободные очки есть» — не вся история. Билд, пришедший по ссылке в
  # обход воронки `put_build/2` (решение 1.7), может стоять на нелегальной
  # покупке — все 30 потрачены, а кастерский пол ещё не выкуплен, потому что
  # `enforce_floor/2` его не коснулся. Формула «ждёт, если свободно > 0» тогда
  # называла бы секцию законченной как раз там, где игроку нужно увидеть
  # нарушение, — ровно та ложная законность, на которой проект уже обжигался
  # (§1.6, §1.8). Ждёт, если ЛИБО есть что тратить, ЛИБО пол нарушен.
  def section_pending?(assigns, "point_buy") do
    %{ruleset: ruleset, build: build} = assigns

    PointBuy.remaining(ruleset, build.base_abilities) > 0 or
      point_buy_floor_violated?(ruleset, build)
  end

  def section_pending?(assigns, "class"),
    do: is_nil(Build.class_at(assigns.build, assigns.active))

  def section_pending?(assigns, "increase"),
    do: is_nil(Map.get(assigns.build.ability_increases, assigns.active))

  # ⚠ Не `not @class_choice.complete?` — эта формула молчала о находке задачи
  # 3.10. `complete?/3` для НЕОБЯЗАТЕЛЬНОГО выбора (волшебник, `required?:
  # false`) тривиально `true` ещё до первого клика (см. `ClassChoices.
  # complete?/3`), а значит секция считалась бы законченной с самого первого
  # захода на 1-й уровень волшебника — то есть экран не подвёз бы игрока к
  # выбору школы вовсе. ⚠️ До задачи 3.18 цена была ещё выше: секция была бы
  # СВЁРНУТА — заголовок «Школа магии» без сводки, без warn (он тоже гейтится
  # на `complete?`), без hint (`hint={@hint && @open}` в
  # `BuilderComponents.section/1` печатает подсказку только пока секция
  # открыта), и игрок физически не увидел бы, что тут есть выбор. Сворачивания
  # больше нет, находка задачи 3.10 — есть.
  #
  # Верное условие — «остались ли значения, которые ещё МОЖНО добавить»,
  # то есть `length(chosen) < count`. Для обязательного выбора (клирик) это
  # ДРУГАЯ ЗАПИСЬ ТОЙ ЖЕ формулы (`complete?/3`'s `required?: true`-ветка сама
  # определена как `length(chosen) >= count`), так что уже протестированное
  # поведение клирика («ждёт после ПЕРВОГО из двух доменов, заканчивается
  # только после второго») не меняется ни на бит. Меняется только волшебник:
  # секция ждёт, пока школа ещё не названа, и перестаёт сразу же — у него
  # `count: 1`, так что «частично выбрано» не бывает.
  def section_pending?(assigns, "domains") do
    case assigns.class_choice do
      nil -> false
      %{chosen_names: chosen, count: count} -> length(chosen) < count
    end
  end

  # ⚠️ Не только пустые слоты: выданный фит с невыбранным значением — тоже
  # решение уровня (задача 3.26, `Weapon of choice` Мастера оружия). Ждём ровно
  # пока выбирать ЕСТЬ ИЗ ЧЕГО: у билда, где `Weapon focus` взят без записанного
  # оружия (ссылка старше задачи 3.5), предлагать нечего, и подвозить экран к
  # секции, где ничего не сделать, значило бы гонять игрока по кругу.
  #
  # ⚠️ И это НЕ входит в `level_settled?/3`: там оно заблокировало бы автопереход
  # на следующий уровень насовсем у тех же билдов. Ядро в обычном случае оружие
  # выводит само (`Rules.AttackBonuses`), так что незаписанный выбор — повод
  # показать, а не повод запретить.
  def section_pending?(assigns, "feats") do
    Feats.open_slots(assigns.ruleset, assigns.build, assigns.active) != [] or
      Enum.any?(assigns.granted_choices, &(is_nil(&1.chosen) and &1.values != []))
  end

  # Pending while a spell is still unchosen — and also when there is a note to
  # read, because the note is the level-20 wall and this section exists to give
  # exactly that warning (CLAUDE.md §6). ⚠️ До 3.18 это же условие держало
  # секцию РАСКРЫТОЙ, чтобы стену нельзя было схлопнуть мимо глаз; сворачивания
  # больше нет, а «подвезти экран к предупреждению» — та же мысль в новой роли.
  # ⚠️ Заблокированный слот в «незавершённое» НЕ идёт (задача 3.125): подвозить
  # экран к решению, которого игрок принять не может, — это нытьё, а не
  # подсказка. Причина у него написана на самом чипе, и она не про «выбери»,
  # а про «подними характеристику», то есть решается в другой секции.
  def section_pending?(assigns, "spells") do
    assigns.spell_note != nil or
      Enum.any?(assigns.spell_slots, &(is_nil(&1.spell) and is_nil(&1.blocked)))
  end

  def section_pending?(assigns, "skills") do
    case Build.class_at(assigns.build, assigns.active) do
      nil -> false
      _ -> Skills.budget(assigns.build, assigns.ruleset, assigns.active).free > 0
    end
  end

  # ⚠️ `false`, а не `true`. В прежней роли («открыта по умолчанию») безопасным
  # ответом на незнакомый ключ было «открыть» — лучше показать лишнее, чем
  # спрятать нужное. В роли цели прокрутки безопасно ровно обратное: секция,
  # про которую мы ничего не знаем, не имеет права перетягивать на себя экран.
  def section_pending?(_assigns, _key), do: false

  defp point_buy_floor_violated?(ruleset, build) do
    case PointBuy.forced(ruleset, build) do
      nil ->
        false

      %{ability: ability, base: base} ->
        Map.get(build.base_abilities, ability, PointBuy.min_score(ruleset)) < base
    end
  end

  @doc false
  # The link people actually paste points at the read-only screen: whoever opens
  # it usually did not build this and is usually on a phone (CLAUDE.md §6). Same
  # code, different route — there is only ever one encoding.
  def view_url(assigns), do: "#{assigns.base_url}b/#{assigns.code}"

  @doc false
  # Короткая форма той же ссылки. Не заменяет длинную и стоит ПОСЛЕ неё:
  # длинная несёт билд в себе и переживёт нашу базу, короткая живёт, пока жива
  # запись (`BuildCalculator.ShortLinks`).
  def short_url(assigns), do: "#{assigns.base_url}s/#{assigns.short_key}"

  @doc false
  # An imported block carries the build's name, and the save form is the only
  # place that name has to live — the constructor itself never shows it. Passing
  # it on is what keeps «Ruby Knight» from becoming «Fighter 4 / Weapon master 30».
  def save_url(%{build_title: title} = assigns) when is_binary(title),
    do: ~p"/builds/new?#{[b: assigns.code, name: title]}"

  def save_url(assigns), do: ~p"/builds/new?#{[b: assigns.code]}"
end
