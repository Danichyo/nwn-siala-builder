defmodule BuildCalculatorWeb.BuilderComponents do
  @moduledoc """
  The builder's own components.

  Written by hand on the design system in `assets/css/app.css` — no daisyUI
  (AGENTS.md), no borrowed palette. Each one carries a piece of the reasoning
  the prototype settled on, because the reasoning is the part that gets lost.
  """
  use Phoenix.Component
  use Gettext, backend: BuildCalculatorWeb.Gettext

  @doc """
  A collapsible stage section.

  Collapsing must never hide *state*: the header keeps showing what is chosen
  and what is missing, and only the body folds away. That is what makes this
  different from tabs — tabs hide the very thing this design is built to keep
  visible, and would still need a "⚠ 8 очков" badge on top (CLAUDE.md §6).

  ⚠️ **Задача 3.18 (Dan 05.08.2026): секции больше НЕ сворачиваются сами.**
  Здесь стояло «Unfinished sections open themselves» — обратная половина того
  же правила («сделанное сворачивается само») отменена, и с ней ушёл смысл
  первой: сворачивать нечего, если ничего не свернулось. Кто и почему это
  решил — в `BuilderLive.section_pending?/2`, там же замеры.

  `pending` — не «открыта»: это «на этой секции ещё висит решение». Открытость
  целиком в руках игрока (`sections` в сокете).

  ⚠️ **Задача 3.30 (Dan 15.08.2026): читателя у `data-pending` сменили.**
  Здесь стояло «нужен хуку `.FocusPending`, который подвозит экран к первой
  такой секции» — хука больше нет, экран сам не двигается. Тот же вопрос
  теперь задаёт лента секций (`BuilderLive.assign_stage_nav/1`), а атрибут
  остался на месте и означает ровно то же самое.

  ⚠️ Лента при этом красит ДВУМЯ цветами то, что здесь одна булева: «держит
  уровень» и «можно доделать» — разные состояния, и различает их
  `BuilderLive.nav_state/2` (через `holds_level?/2` и исключение
  `creation_hold?/2` для расы, мировоззрения и статов на создании персонажа),
  а не этот атрибут.
  Добавлять сюда второй флаг незачем: секция и так называет своё несделанное
  словами (`warn`), а лента отвечает на другой вопрос — «куда идти».

  Атрибут стоит на самой `<section>`, а не на кнопке: он про блок целиком,
  и по нему же секция служит целью якоря из ленты.
  """
  attr :id, :string, required: true
  attr :key, :string, required: true
  attr :eyebrow, :string, required: true
  attr :summary, :string, default: nil
  attr :warn, :string, default: nil
  attr :hint, :string, default: nil
  attr :open, :boolean, required: true
  attr :pending, :boolean, default: false
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <section class="sect" id={@id} data-pending={if @pending, do: "1", else: "0"}>
      <button
        type="button"
        class="sect-toggle"
        id={@id <> "-toggle"}
        data-open={if @open, do: "1", else: "0"}
        aria-expanded={to_string(@open)}
        aria-controls={@id <> "-body"}
        phx-click="toggle_section"
        phx-value-key={@key}
      >
        <span class="sect-chev" aria-hidden="true">▸</span>
        <span class="eyebrow">{@eyebrow}</span>
        <span :if={@summary} class="sect-summary">{@summary}</span>
        <span :if={@warn} class="warn">{@warn}</span>
        <span :if={@hint && @open} class="hint">{@hint}</span>
      </button>
      <div :if={@open} class="sect-body" id={@id <> "-body"}>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @doc """
  Шаг на следующий уровень.

  ⚠️ **Одна разметка, но ДВА места на экране, и это не дубль ради дубля**
  (задача 3.30, второй заход по отзыву Dan 15.08.2026 — не 3.32, та про сокет).
  Дословно: «липкая панель всегда сверху,
  а выбираю я обычно что-то в центре экрана. Приходится второй рукой тянуться
  к верху экрана». Значит место у этого действия разное по построению:

    * телефон — правый край НИЖНЕЙ панели (`#stage-nav-next`), в зоне большого
      пальца, рядом с лентой секций, которая туда же и переехала;
    * десктоп — правый край липкой панели уровня (`#stage-nav-next`) И шапка
      колонки прогрессии (`#spine-next`).

  ⚠️ **На десктопе видно ОБЕ, и это пересмотр задачи 3.33.** Здесь стояло
  «видим всегда ровно один — второй `display: none` по медиа-запросу, то есть
  из порядка обхода с клавиатуры он выпадает целиком», с доводом «иначе игрок
  выбирал бы между двумя одинаковыми кнопками». Довод не отменён — он проиграл
  отзыву Dan 15.08.2026 («кнопка над лестницей выглядит хорошо, но по UX
  не очень удобна из-за большой удалённости; возможно оставить её, но добавить
  полный аналог куда-то ближе к центру») и замеру: от сетки классов до кнопки
  у лестницы курсор проходил 600px на 1280 и 985px на 2000, а в конце уровня
  (секция навыков) липкая колонка упирается в конец сетки и кнопку срезает —
  на 1280 её не видно вовсе. Копия в ленте короче на 132–192px и видна всегда.

  Один элемент на два места не годится: медиа-запросом разметку не переносят,
  а на мобильном он обязан лежать вне ленты по-другому, чем на десктопе.

  Ссылка, а не кнопка, и это несёт смысл: `href="#stage-head"` заодно приводит
  экран к началу нового уровня. Без него шаг вперёд с глубины 2600px оставлял
  игрока на 2582px — посреди сетки классов уже ДРУГОГО уровня, с заголовком
  за краем экрана (замерено 15.08.2026). И это не возврат снятого автоскролла
  (задача 3.30): тот двигал экран ПОСЛЕ решения, сам по себе, а здесь движение —
  прямое следствие нажатого «Уровень N →». Нажал «перейти» — перешёл, включая
  вид.

  ⚠️ LiveView пропускает оба действия сразу: `preventDefault` он зовёт только
  при `href="#"` (`live_socket.ts`, `bindClick`), так что событие уходит
  на сервер, а браузер отрабатывает якорь. Прокрутка плавная —
  `scroll-behavior` в app.css, с оговоркой на `prefers-reduced-motion`.

  Недоступное состояние — без `href` и без `phx-click`: у ссылки нет
  `disabled`, а «ведёт в никуда, но кликается» хуже, чем «не ведёт и говорит
  почему» (CLAUDE.md §6).

  ⚠️ **Задача 3.69: причин недоступности теперь до трёх, и текст приходит
  готовым.** Раньше единственной причиной было отсутствие класса на текущем
  уровне, и текст был зашит здесь же. Теперь у лестницы и у кнопки один
  и тот же потолок (`BuilderLive.level_ceiling/2`), а значит и причина
  обязана быть одна на оба места — `@next.why` вычисляется один раз
  в `BuilderLive.assign_stage_nav/1` (`next_level_reason/3`) и просто
  печатается здесь, а не придумывается по месту.
  """
  attr :id, :string, required: true
  attr :class, :string, required: true, doc: "stage-nav-next | spine-next"
  attr :next, :map, required: true, doc: "%{level:, ready?:, settled?:, why:}"

  def next_level(assigns) do
    ~H"""
    <a
      class={@class}
      id={@id}
      href={@next.ready? && "#stage-head"}
      phx-click={@next.ready? && "select_level"}
      phx-value-level={@next.level}
      aria-disabled={not @next.ready? && "true"}
      data-disabled={not @next.ready? && "1"}
      data-hold={if not @next.settled?, do: "1"}
    >
      <%!-- Число — моноширинным, как и все числа в этом интерфейсе: иначе на
            переходе 9 → 10 подпись меняет ширину непредсказуемо, а кнопка
            стоит у правого края панели.

            ⚠️ Слово написано ДВАЖДЫ, и это не дубль: на телефоне печатается
            «Ур.», на десктопе «Уровень» (выбор Dan 15.08.2026). Причина —
            место: на 360px в ленту помещались 3 пункта из 6, и короткая форма
            освобождает их часть. На десктопе теснить нечего, и резать слово
            там незачем. Переключает CSS (`.lvl-full` / `.lvl-abbr`), а не
            вторая ветка в разметке: у кнопки два места вызова, и условие
            в шаблоне пришлось бы держать синхронным с медиа-запросом. --%>
      <span class="stage-nav-next-t">
        <span class="lvl-full">Уровень</span><span class="lvl-abbr">Ур.</span>
        <b>{@next.level}</b> →
      </span>
      <%!-- Недоступное не прячем, а объясняем. Текст — не наш: он приходит
            из `@next.why`, посчитанным ОДИН раз для обеих копий кнопки
            (задача 3.69, doc модуля выше). --%>
      <span :if={not @next.ready?} class="stage-nav-why" id={"#{@id}-why"}>
        {@next.why}
      </span>
      <%!-- Уйти с незакрытого уровня можно всегда — но молча уводить нельзя.
            На экране это янтарь кнопки, а СЛОВАМИ то же самое сказано рядом:
            `#stage-hold` называет оставшийся слот поимённо, и секция в ленте
            горит тем же янтарём. Здесь — только для скринридера. --%>
      <span :if={@next.ready? && not @next.settled?} class="sr-only">
        уровень не закрыт
      </span>
    </a>
    """
  end

  @doc """
  Renders a name with the fuzzy-matched letters marked.

  Without the highlight a subsequence match looks like a random result
  (CLAUDE.md §6) — `pwatk` finding "Power Attack" only reads as correct once you
  can see which letters matched.

  ⚠️ **Ни одного переноса строки внутри — иначе подсветка РВЁТ СЛОВО**
  (жалоба Dan 15.08.2026: «Dodge» с искомым «dod» читался как «Dod» «ge»).
  Здесь стоял `<%= if %>` в четыре строки с отступами, и каждый перенос вокруг
  `<mark>` становился текстовым узлом — то есть настоящим пробелом в HTML.
  У нечёткого поиска совпадение почти всегда лежит ВНУТРИ слова
  (подпоследовательность, а не префикс), поэтому рвалась каждая вторая строка
  выдачи.

  ⚠️ Чинилось это дважды, и первый раз не туда: сняли `padding: 0 1px` у `.hl`
  (он давал ещё 2px сверху), а зазор остался — потому что причина была
  в разметке. **Сначала посмотри отрендеренный HTML, потом правь CSS.**

  Поэтому здесь ОДИН тег на сегмент и `:for` на нём самом: между итерациями
  вставить пробел уже нечему, и формат-инструменту нечего переносить внутри.
  `<mark>` ради этого потерян сознательно — семантика «выделенный кусок» на
  отдельных БУКВАХ внутри слова всё равно сомнительна: скринридер читал бы
  «Uncanny д-о-д ge» с границами эмфазы посреди слова.
  """
  attr :segments, :list, required: true

  def highlight(assigns) do
    ~H"""
    <span :for={{kind, text} <- @segments} class={kind == :hit && "hl"}>{text}</span>
    """
  end

  @doc """
  A feat's or a spell's 32×32 Fandom icon, shown at 16 CSS px — or our own
  fallback glyph in its place (AGENT_QUEUE.md 3.50).

  `path` comes from `BuildCalculatorWeb.Builder.Icons.feat_path/1` /
  `spell_path/1`, already resolved against the manifest; this component never
  touches the filesystem or the manifest itself, only lays out whatever it was
  handed.

  ## Why the box renders even with nothing inside it

  16×16, fixed, regardless of whether `path` or `glyph` end up filling it —
  Dan's requirement was that the list must not "jump" between a row that has
  art and a row that does not (a row's name has to start at the same left
  edge either way). A spell with no icon (9 of 303, several of them not
  exotic — `Shapechange`, `Polymorph self`) gets an empty box rather than an
  invented mark: CLAUDE.md §6 already reserves a spell's own identity to the
  circle badge, not a glyph, and inventing one here for a handful of rows
  would be exactly the kind of decoration §6 warns against making up on the
  spot.

  ## Why `glyph` replaces the feat row's old bare `✦`/`★`, not sits beside it

  A feat with no icon (23 of 299 — tiered families such as `Automatic quicken
  spell`, one Fandom page per whole family, not a data gap) falls back to the
  same general/epic marker the row always showed before this task. It moved
  *into* this box rather than gaining a second copy next to it: showing both
  an image and a `✦`/`★` for every single feat that does have art would print
  "general or epic" twice per row for no reason, and showing the fallback
  glyph a second time on the 23 icon-less rows specifically would be worse —
  the one piece of information in the box would visibly repeat itself. One
  slot, one answer, same as `.circle-badge` is the one answer for a spell's
  circle.

  ## `loading="lazy"`

  Measured, not guessed (AGENT_QUEUE.md 3.50): a feat list with an open
  general slot and no search query streams roughly 80 rows into the DOM at
  once (32 available + up to the blocked list's own cap of 50, plus a
  handful of "already own it" rows the cap does not trim) — `BuilderComponents`
  has nothing that virtualises `phx-update="stream"`, so every one of those
  rows' `<img>` tags exists in the DOM whether or not the row is scrolled into
  view. `loading="lazy"` costs nothing on the handful actually on screen and
  defers the other 70-odd — the same reasoning applies to the known-spell
  picker, which runs smaller (≈30-60 rows for one circle or two) but is built
  from the same component.

  ## Always `alt=""`

  Every call site prints the feat's or spell's own name as text immediately
  beside this component (`.feat-name`) — the icon is never the only thing
  naming the row. A non-empty `alt` here would therefore read the same name
  twice to a screen reader for no reason; an empty one lets it skip the image
  outright, which is the correct reading for a decoration that duplicates
  adjacent text (CLAUDE.md §6 — icons *add to* a name, they never stand in
  for one).
  """
  attr :path, :string, default: nil, doc: "resolved static path, or nil"

  attr :glyph, :string,
    default: nil,
    doc: "fallback text shown when path is nil; nil prints nothing"

  attr :epic?, :boolean, default: false
  attr :class, :any, default: nil

  def game_icon(assigns) do
    ~H"""
    <span class={["game-icon", @class]} data-epic={@epic? && "1"}>
      <img :if={@path} src={@path} width="16" height="16" alt="" loading="lazy" />
      <i :if={!@path && @glyph} aria-hidden="true">{@glyph}</i>
    </span>
    """
  end

  @doc """
  «Из чего собрано число» — a hover/click toggletip (CLAUDE.md §6, задача 3.13).

  General on purpose, not an ability-score component: `terms` is a plain list
  of `%{label:, value:}` and nothing here knows whether the value in front of
  it is an ability score, AB, AC, a saving throw or HP — task 3.6 wires the
  same component to all four, and 3.1 grows the ability terms list without
  either this markup or the colocated hook changing.

  The wrapped value (`inner_block`) keeps rendering exactly as it always did,
  reactively, on every diff — this component only *adds* a trigger around it.
  The breakdown itself never gets printed as text anywhere in the response:
  it travels inert as JSON in `data-pop-terms`, a plain attribute that
  LiveView diffs like any other (`data-active` on `#level-ladder` in
  `builder_live.html.heex` is the same idea) rather than a
  `phx-update="ignore"` island, so editing point buy with the popover pinned
  open keeps it honest. The one colocated hook `.StatPop` decides — only once
  it has checked `matchMedia("(max-width: 940px)")`, on mount *and* on every
  live resize across that threshold — whether to ever turn that attribute
  into a floating panel. Below the threshold no listener is ever attached, so
  the breakdown is not merely hidden by CSS on a phone: it never becomes
  visible markup at all (AGENT_QUEUE.md §3.13, Dan 03.08.2026).

  ⚠️ The hook's `<script>` lives *inside this function*, not next to a call
  site in `builder_live.html.heex`. A colocated hook's `phx-hook=".Name"` is
  expanded at compile time to `"<calling module>.Name"` — the module whose
  template the literal attribute is written in, not the module the matching
  `<script :type={ColocatedHook}>` happens to sit in
  (`Phoenix.LiveView.TagEngine.Compiler.postprocess_attrs/2`). Since
  `phx-hook=".StatPop"` is written here, in `BuilderComponents`, the
  `<script name=".StatPop">` has to compile as part of `BuilderComponents`
  too, or the two names never match and the hook silently never mounts —
  found by a LiveView test showing `phx-hook="…BuilderLive.StatPop"` on the
  element while the compiled bundle only registered
  `"…BuilderComponents.StatPop"`; `Phoenix.LiveViewTest` does not run JS, so
  nothing failed loudly. Compiling once inside a function called many times
  is not wasteful: `ColocatedHook.transform/2` runs on the template's AST at
  compile time and rewrites the `<script>` node to `""` once, for good —
  calling `stat_pop/1` six times does not emit the hook's source six times.

  Gaps do not belong inside this popover. `ruleset.gaps` prints outside it,
  unconditionally (CLAUDE.md §6, §9) — an admission of "not computed" is
  exactly the kind of thing a popup must never require a click to discover.
  """
  attr :id, :string, required: true, doc: "unique slug, e.g. \"ability-str\""
  attr :title, :string, required: true, doc: "heading printed inside the panel"
  attr :terms, :list, default: [], doc: "[%{label:, value:}], in cascade order"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def stat_pop(assigns) do
    ~H"""
    <span
      class={["stat-pop-trigger", @class]}
      id={"stat-pop-#{@id}"}
      phx-hook=".StatPop"
      data-pop-title={@title}
      data-pop-terms={Jason.encode!(@terms)}
    >{render_slot(@inner_block)}</span>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".StatPop">
      // Загружается один раз и делится состоянием между ВСЕМИ триггерами
      // `stat_pop/1` на странице: один плавающий узел на всю панель итогов,
      // один открытый поп-ап единовременно — не по одному на строку.
      const PANEL_ID = "stat-pop-panel"
      let panel = null
      let openTrigger = null
      let pinned = false
      let openTimer = null
      let globalBound = false

      function ensurePanel() {
        if (panel) return panel
        panel = document.createElement("div")
        panel.id = PANEL_ID
        panel.className = "stat-pop-panel"
        panel.setAttribute("role", "tooltip")
        panel.setAttribute("aria-live", "polite")
        document.body.appendChild(panel)
        return panel
      }

      // DOM-узлами, а не `innerHTML` со строкой: термы приходят из данных
      // шарда и когда-нибудь понесут имена фитов (задача 3.1) — экранировать
      // самим не нужно вовсе, если строить узлы через `textContent`.
      function renderTerms(trigger) {
        const p = ensurePanel()
        p.replaceChildren()

        const title = document.createElement("p")
        title.className = "stat-pop-title"
        title.textContent = trigger.dataset.popTitle || ""
        p.appendChild(title)

        let terms = []
        try { terms = JSON.parse(trigger.dataset.popTerms || "[]") } catch (_e) { terms = [] }

        for (const term of terms) {
          const row = document.createElement("p")
          row.className = "stat-pop-term"
          const l = document.createElement("span")
          l.className = "stat-pop-l"
          l.textContent = term.label
          const v = document.createElement("span")
          v.className = "stat-pop-v"
          v.textContent = term.value
          row.append(l, v)
          p.appendChild(row)
        }
      }

      // `position: fixed` + `right`, не `left`: панель итогов прижата
      // к правому краю окна, поп-ап обязан раскрываться влево
      // (CLAUDE.md §6, задача 3.13), а `fixed` считает координаты от
      // viewport — учитывать прокрутку `.stats` не нужно.
      function place(trigger) {
        const rect = trigger.getBoundingClientRect()
        const p = ensurePanel()
        p.style.top = `${Math.round(rect.bottom + 6)}px`
        p.style.right = `${Math.round(window.innerWidth - rect.right)}px`
      }

      function open(trigger, pin) {
        if (openTrigger && openTrigger !== trigger) close()
        const reopening = openTrigger === trigger
        openTrigger = trigger
        pinned = pin || (reopening && pinned)
        renderTerms(trigger)
        place(trigger)
        const p = ensurePanel()
        p.dataset.open = "1"
        p.removeAttribute("aria-hidden")
        trigger.setAttribute("aria-expanded", "true")
        trigger.setAttribute("aria-describedby", PANEL_ID)
      }

      function close(opts = {}) {
        if (!openTrigger) return
        const trigger = openTrigger
        if (panel) {
          panel.dataset.open = "0"
          // Узел переиспользуется между открытиями, а не пересоздаётся —
          // закрытый обязан быть недостижим и для скринридера в режиме
          // просмотра, а не только невидим глазом (`opacity` в CSS этого
          // не делает сама по себе).
          panel.setAttribute("aria-hidden", "true")
        }
        trigger.setAttribute("aria-expanded", "false")
        trigger.removeAttribute("aria-describedby")
        openTrigger = null
        pinned = false
        if (opts.restoreFocus) trigger.focus()
      }

      // Клик вне, Esc, скролл — регистрируются один раз на документ,
      // а не по разу на триггер, иначе шесть характеристик означали бы
      // шесть слушателей `document.click`.
      function bindGlobalOnce() {
        if (globalBound) return
        globalBound = true

        document.addEventListener("click", e => {
          if (!openTrigger) return
          if (openTrigger.contains(e.target)) return
          if (panel && panel.contains(e.target)) return
          close()
        }, true)

        document.addEventListener("keydown", e => {
          if (e.key !== "Escape" || !openTrigger) return
          // Фокус возвращаем, только если он и так у триггера — иначе
          // Esc, нажатый совсем по другому поводу, выдернул бы фокус
          // туда, куда пользователь его не направлял.
          close({ restoreFocus: document.activeElement === openTrigger })
        })

        // Оторванный от триггера поп-ап (проскроллили или ужали окно)
        // хуже отсутствующего — закрываем, а не пытаемся переместить.
        window.addEventListener("scroll", () => { if (openTrigger) close() }, true)
        window.addEventListener("resize", () => { if (openTrigger) close() })
      }

      export default {
        mounted() {
          bindGlobalOnce()
          this.enabled = false
          this.mq = matchMedia("(max-width: 940px)")
          this.onMqChange = () => this.applyMode()
          this.mq.addEventListener("change", this.onMqChange)
          this.onEnter = () => this.scheduleOpen()
          this.onLeave = () => this.scheduleClose()
          this.onFocus = () => { clearTimeout(openTimer); open(this.el, false) }
          this.onBlur = () => this.scheduleClose()
          this.onClick = () => this.toggle()
          this.onKeydown = e => this.handleKeydown(e)
          this.applyMode()
        },
        // ⚠️ Патч LiveView'а перерисовывает ЭТУ строку при правке, которая её
        // не касается вовсе (например, поинт-бай другой характеристики или
        // выбор расы, задевающий соседнюю карточку) — диффер сверяет DOM
        // с разметкой от СЕРВЕРА, а `role`/`tabindex`/`aria-expanded`/
        // `.stat-pop-ready` на этом узле расставил КЛИЕНТ; сервер про них не
        // знает, и патч снимает их как «лишние». Без переприменения здесь
        // это было незаметно и коварно: пришпиленный поп-ап молча закрывался
        // первым же несвязанным изменением билда, а пунктир-подсказка гас
        // после первого клика по чему угодно ещё в форме. Найдено прогоном
        // живьём (Playwright) — `Phoenix.LiveViewTest` этого разойтись не
        // заметил бы вовсе, патчинг он не выполняет.
        updated() {
          if (this.enabled) this.applyState()
          // Число могло поменяться, пока поп-ап открыт (например, правкой
          // поинт-бая на 0-м уровне) — обновляем без перещёлкивания.
          if (openTrigger === this.el) renderTerms(this.el)
        },
        destroyed() {
          this.mq.removeEventListener("change", this.onMqChange)
          this.disable()
        },
        // Порог тот же, что у мобильной шторки (`@media (max-width: 940px)`
        // в app.css), и решение принимается заново при каждом пересечении
        // порога живьём — не только при первой загрузке страницы, иначе
        // растянутое из мобильной ширины окно оставляло бы триггер немым
        // при уже «десктопной» раскладке.
        applyMode() { this.mq.matches ? this.disable() : this.enable() },
        // Атрибуты — отдельно от подписки на события: `applyState()` обязана
        // отрабатывать на КАЖДОМ `updated()`, а слушатели вешаются только
        // один раз (иначе клик открывал бы поп-ап по два раза за клик).
        // Смешивать оба в одном флаге `this.enabled` и было причиной бага
        // выше.
        applyState() {
          this.el.setAttribute("role", "button")
          this.el.setAttribute("tabindex", "0")
          this.el.classList.add("stat-pop-ready")
          if (openTrigger === this.el) {
            this.el.setAttribute("aria-expanded", "true")
            this.el.setAttribute("aria-describedby", PANEL_ID)
          } else {
            this.el.setAttribute("aria-expanded", "false")
            this.el.removeAttribute("aria-describedby")
          }
        },
        enable() {
          this.applyState()
          if (this.enabled) return
          this.enabled = true
          this.el.addEventListener("mouseenter", this.onEnter)
          this.el.addEventListener("mouseleave", this.onLeave)
          this.el.addEventListener("focus", this.onFocus)
          this.el.addEventListener("blur", this.onBlur)
          this.el.addEventListener("click", this.onClick)
          this.el.addEventListener("keydown", this.onKeydown)
        },
        // На телефоне не вызывается вовсе — обычный `<span>` без роли,
        // без `tabindex`, без единого слушателя: разбор «не рендерится
        // вовсе», а не скрыт стилями (CLAUDE.md §6, задача 3.13).
        disable() {
          if (!this.enabled) return
          this.enabled = false
          clearTimeout(openTimer)
          if (openTrigger === this.el) close()
          this.el.removeAttribute("role")
          this.el.removeAttribute("tabindex")
          this.el.removeAttribute("aria-expanded")
          this.el.removeAttribute("aria-describedby")
          this.el.classList.remove("stat-pop-ready")
          this.el.removeEventListener("mouseenter", this.onEnter)
          this.el.removeEventListener("mouseleave", this.onLeave)
          this.el.removeEventListener("focus", this.onFocus)
          this.el.removeEventListener("blur", this.onBlur)
          this.el.removeEventListener("click", this.onClick)
          this.el.removeEventListener("keydown", this.onKeydown)
        },
        // 150–250 мс (CLAUDE.md §6, задача 3.13): без задержки панель
        // мигала бы на каждый проход мыши через панель итогов.
        scheduleOpen() {
          clearTimeout(openTimer)
          if (openTrigger === this.el) return
          openTimer = setTimeout(() => open(this.el, false), 200)
        },
        scheduleClose() {
          clearTimeout(openTimer)
          if (pinned && openTrigger === this.el) return
          if (openTrigger === this.el) close()
        },
        // Клик — всегда пин: закрывает уже закреплённый, закрепляет любой
        // другой (открытый по ховеру или ещё не открытый вовсе).
        toggle() {
          clearTimeout(openTimer)
          if (openTrigger === this.el && pinned) close({ restoreFocus: true })
          else open(this.el, true)
        },
        handleKeydown(e) {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault()
            this.toggle()
          } else if (e.key === "Escape" && openTrigger === this.el) {
            e.preventDefault()
            close({ restoreFocus: true })
          }
        }
      }
    </script>
    """
  end

  @doc """
  "What this feat does" — a hover/click/tap toggletip (task 3.87, Dan
  24.08.2026), the same family as `stat_pop/1` above and built the same way
  for the same reasons: one shared floating node reused by every trigger on
  the page rather than one per row (up to ~350 feats render this), content
  built through `textContent` rather than `innerHTML` (the description is a
  quote off a wiki page, never our markup), and the whole thing lives as
  inert `data-*` on a plain server-rendered `<span>` until the hook decides
  to turn it into visible content — LiveView diffs the attribute like any
  other, so nothing here needs `phx-update="ignore"`.

  ⚠️ **Where this genuinely differs from `stat_pop/1`, and why it is its own
  component rather than a second call shape on that one:** `stat_pop`
  disables itself below 940px on purpose — CLAUDE.md §6/task 3.13, the
  breakdown must not even reach the DOM as visible markup on a phone. This
  trigger does the opposite: task 3.87 asks for the mobile affordance to be
  a *bottom sheet*, not nothing, so it is never disabled — only the shared
  panel's positioning switches, in CSS (`@media (max-width: 940px)`), from a
  small card anchored under the trigger to a sheet docked to the viewport
  bottom. Trying to fold a "stay enabled, just reposition" mode into
  `stat_pop`'s "vanish below the threshold" one would have made neither
  behaviour readable from the code.

  ⚠️ **The trigger sits inside the row's own `<button class="feat"
  phx-click="pick_feat">` — nesting a real `<button>` there would be
  invalid**, and not academically: the HTML parser closes an open `<button>`
  the moment it meets another `<button>` start tag and reopens the second
  one as a *sibling*, silently flattening exactly the markup meant to nest.
  The trigger is therefore a `<span role="button" tabindex="0">`, and because
  a click on it must never reach the row's own `phx-click` (CLAUDE.md §6 —
  this is the mobile-tap-selects-the-wrong-thing shape bug 1.11 already
  cost the project once), its own click/keydown handlers call
  `stopPropagation()` before LiveView's single window-level click listener
  ever sees the event — not merely before it walks up the DOM to find a
  binding, which is why this is a hook and not a `phx-click={JS...}`
  attribute the way `#sheet-toggle` does it elsewhere in this template.

  ⚠️ **`description` gates the whole thing, in the caller, not here**: a
  `nil` — the eleven shard-only weapon-proficiency feats, task 3.87 — means
  there is nothing to show, so the row simply carries no trigger at all
  rather than one that opens onto an empty panel.

  ⚠️ **`DISMISS_GUARD_MS`/`recentlyOpened()` exist because a tap closes what
  it just opened, on real touch emulation, not in theory.** Found by a full
  CDP event trace (24.08.2026), not by reading the code: a tap synthesises a
  whole legacy mouse sequence for compatibility
  (pointerdown→mouseover→…→mouseenter→focus→…→mouseout→mouseleave→click), and
  once the panel is open and happens to sit under the tap point — a "sheet"
  on a short phone screen with a long quote is exactly that — the synthesised
  `mouseenter`/`mouseover` land **on the panel**, not the trigger, so
  `mouseleave` fires **on the trigger** milliseconds later, and the
  eventual `click` lands on `<body>`, neither ever reaching a listener that
  would keep the panel open. `Evasion` (a long shard quote, a tall sheet)
  reproduced it every time; `Iron will` (one short sentence, a small sheet)
  never did — which is why eyeballing one example is not enough. The guard
  does not touch the *deliberate* ways to close (Esc, the "×" button, a
  second click on the same trigger) — those have to work the instant they
  are asked for; it only holds off the *passive* ones (scroll, leave, a
  click that lands elsewhere) for a moment, on the theory that a passive
  signal arriving within a heartbeat of opening is far more likely to be an
  echo of the very tap that opened it than a second, separate action.
  """
  attr :id, :string, required: true, doc: "unique slug, e.g. \"feat-ok-toughness-info\""
  attr :name, :string, required: true, doc: "the feat's own English name"
  attr :description, :string, required: true, doc: "Fandom's prose, never nil at the call site"
  attr :siala_changed?, :boolean, default: false
  attr :siala_notes, :list, default: []
  attr :siala_notes_more_text, :string, default: nil
  attr :source_url, :string, default: nil
  attr :source_link_text, :string, default: nil

  def feat_info(assigns) do
    ~H"""
    <span
      class="feat-info"
      id={@id}
      role="button"
      tabindex="0"
      phx-hook=".FeatInfo"
      aria-haspopup="dialog"
      aria-label={gettext("What %{feat} does", feat: @name)}
      data-feat-name={@name}
      data-feat-description={@description}
      data-feat-changed={to_string(@siala_changed?)}
      data-feat-notes={Jason.encode!(@siala_notes)}
      data-feat-notes-more={@siala_notes_more_text}
      data-feat-source-url={@source_url}
      data-feat-source-text={@source_link_text}
      data-label-changed={gettext("Changed on Siala")}
      data-label-changed-generic={
        gettext(
          "The shard changed this feat's requirements or availability — see this feat's own row for details."
        )
      }
      data-label-vanilla={gettext("Vanilla description (Fandom)")}
      data-label-close={gettext("Close")}
    >ⓘ</span>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".FeatInfo">
      // Единственный узел на всю страницу, как у `.StatPop` — переиспользуется
      // между открытиями, а не плодится по одному на строку.
      const PANEL_ID = "feat-info-panel"
      const MARGIN = 12
      const MAX_WIDTH = 340
      // Сколько ждать после открытия, прежде чем «пассивные» сигналы закрытия
      // (скролл, курсор ушёл, клик мимо) считаются настоящими — см.
      // `recentlyOpened()` ниже, зачем это вообще нужно. Не трогает
      // «активные» способы закрыть — Esc, кнопку «×», повторный клик по
      // самому триггеру: те обязаны срабатывать сразу, это осознанное
      // действие, а не что-то, что можно принять за случайность.
      const DISMISS_GUARD_MS = 300
      let panel = null
      let openTrigger = null
      let pinned = false
      let openTimer = null
      let globalBound = false
      let openedAt = 0
      // ⚠️ Без этого «× закрыть» превращается в «закрыть и тут же открыть
      // заново»: `close({restoreFocus: true})` вызывает `trigger.focus()`,
      // а на триггере висит СВОЙ слушатель "focus", открывающий панель —
      // тот же элемент, тот же хук. Найдено CDP-прогоном (24.08.2026): кнопка
      // «×» не закрывала панель ни разу, хотя код выглядел рабочим на глаз.
      // `.focus()` шлёт событие "focus" СИНХРОННО, поэтому снять флаг можно
      // сразу после вызова, без `setTimeout`.
      let suppressAutoOpen = false

      const mobile = () => matchMedia("(max-width: 940px)").matches

      function ensurePanel() {
        if (panel) return panel
        panel = document.createElement("div")
        panel.id = PANEL_ID
        panel.className = "feat-info-panel"
        panel.setAttribute("role", "dialog")
        panel.setAttribute("aria-modal", "false")
        document.body.appendChild(panel)
        return panel
      }

      function line(className, text) {
        const p = document.createElement("p")
        p.className = className
        p.textContent = text
        return p
      }

      // DOM-узлами, а не строкой `innerHTML`: описание — цитата с вики,
      // а не наша разметка, и её не нужно (и нельзя) считать доверенным HTML.
      //
      // ⚠️ Задача 3.94: у триггера теперь ДВЕ формы данных, и обе ведут
      // в эту же функцию — `d.featEntries` (JSON-список, `feats_info/1`)
      // против одиночных `d.feat*` (`feat_info/1`). Один хук на оба, а не
      // копия: позиционирование, открытие/закрытие, мобильная шторка — вся
      // машинерия ниже общая, и второй такой не должно быть НИКОГДА,
      // расходится только то, что рисуется внутри панели.
      //
      // ⚠️ Заголовок с крестиком строится ОДИН раз (`buildHead`) и живёт ВНЕ
      // прокручиваемой части (`.feat-info-scroll`) — до задачи 3.94 у панели
      // не было своей прокрутки вовсе (одно описание фита туда всегда
      // помещалось), а стопка из нескольких описаний подряд (Barbarian 1 —
      // шесть) переросла экран по высоте первой же проверкой в браузере.
      // Без разделения на «шапка» и «скролл» крестик уезжал бы вместе
      // с прокруткой — закрыть панель можно было бы, только домотав её
      // назад до верха.
      function buildHead(p, titleText, closeLabel) {
        const head = document.createElement("div")
        head.className = "feat-info-head"
        const title = document.createElement("p")
        title.className = "feat-info-title"
        title.textContent = titleText || ""
        const closeBtn = document.createElement("button")
        closeBtn.type = "button"
        closeBtn.className = "feat-info-close"
        closeBtn.setAttribute("aria-label", closeLabel || "")
        closeBtn.textContent = "×"
        closeBtn.addEventListener("click", (e) => {
          e.preventDefault()
          e.stopPropagation()
          close({ restoreFocus: true })
        })
        head.append(title, closeBtn)
        p.appendChild(head)

        const scroll = document.createElement("div")
        scroll.className = "feat-info-scroll"
        p.appendChild(scroll)
        return scroll
      }

      function renderContent(trigger) {
        const p = ensurePanel()
        p.replaceChildren()
        const d = trigger.dataset

        if (d.featEntries) {
          renderEntries(p, trigger, d)
          return
        }

        const body = buildHead(p, d.featName, d.labelClose)

        if (d.featChanged === "true") {
          const warn = document.createElement("div")
          warn.className = "feat-info-shard"
          warn.appendChild(line("feat-info-shard-title", d.labelChanged || ""))

          let notes = []
          try { notes = JSON.parse(d.featNotes || "[]") } catch (_e) { notes = [] }

          if (notes.length) {
            notes.forEach((note) => warn.appendChild(line("feat-info-shard-note", note)))
            if (d.featNotesMore) {
              warn.appendChild(line("feat-info-shard-note feat-info-more", d.featNotesMore))
            }
          } else {
            warn.appendChild(line("feat-info-shard-note", d.labelChangedGeneric || ""))
          }
          body.appendChild(warn)
          body.appendChild(line("feat-info-vanilla-label", d.labelVanilla || ""))
        }

        body.appendChild(line("feat-info-body", d.featDescription || ""))

        if (d.featSourceUrl && d.featSourceText) {
          const link = document.createElement("a")
          link.className = "feat-info-source"
          link.href = d.featSourceUrl
          link.target = "_blank"
          link.rel = "noopener noreferrer"
          link.textContent = d.featSourceText
          body.appendChild(link)
        }
      }

      // `feats_info/1` — несколько фитов в одной панели, задача 3.94.
      // Общий заголовок берёт `aria-label` триггера (уже полная фраза,
      // «Что дают фиты уровня N» — заводить для того же текста ещё один
      // `data-*` незачем), а дальше по разделу на фит, той же формы, что
      // у одиночной панели (имя → предупреждение шарда → ванильная пометка
      // → описание → ссылка на источник), просто повторённой.
      function renderEntries(p, trigger, d) {
        let entries = []
        try { entries = JSON.parse(d.featEntries || "[]") } catch (_e) { entries = [] }

        const body = buildHead(p, trigger.getAttribute("aria-label"), d.labelClose)

        entries.forEach((entry, index) => {
          const wrap = document.createElement("div")
          wrap.className = index > 0 ? "feat-info-entry feat-info-entry-sep" : "feat-info-entry"

          wrap.appendChild(line("feat-info-entry-name", entry.name || ""))

          if (entry.changed) {
            const warn = document.createElement("div")
            warn.className = "feat-info-shard"
            warn.appendChild(line("feat-info-shard-title", d.labelChanged || ""))

            const notes = Array.isArray(entry.notes) ? entry.notes : []
            if (notes.length) {
              notes.forEach((note) => warn.appendChild(line("feat-info-shard-note", note)))
              if (entry.notesMore) {
                warn.appendChild(line("feat-info-shard-note feat-info-more", entry.notesMore))
              }
            } else {
              warn.appendChild(line("feat-info-shard-note", d.labelChangedGeneric || ""))
            }
            wrap.appendChild(warn)
            wrap.appendChild(line("feat-info-vanilla-label", d.labelVanilla || ""))
          }

          wrap.appendChild(line("feat-info-body", entry.description || ""))

          if (entry.sourceUrl && entry.sourceText) {
            const link = document.createElement("a")
            link.className = "feat-info-source"
            link.href = entry.sourceUrl
            link.target = "_blank"
            link.rel = "noopener noreferrer"
            link.textContent = entry.sourceText
            wrap.appendChild(link)
          }

          body.appendChild(wrap)
        })
      }

      // На телефоне якорь ни при чём — панель докована к низу вьюпорта
      // (`@media (max-width: 940px)` в app.css), и любые инлайновые
      // top/left/width от прошлого открытия обязаны уйти, иначе унесённый
      // с десктопа инлайн-стиль победит специфичностью медиа-запрос.
      // На десктопе бок и верх/низ считаются ПОСЛЕ того, как контент уже
      // в панели — высота и ширина известны только тогда.
      function place(trigger) {
        const p = ensurePanel()
        if (mobile()) {
          p.style.removeProperty("top")
          p.style.removeProperty("bottom")
          p.style.removeProperty("left")
          p.style.removeProperty("width")
          return
        }
        const rect = trigger.getBoundingClientRect()
        const width = Math.min(MAX_WIDTH, window.innerWidth - MARGIN * 2)
        let left = Math.min(rect.left, window.innerWidth - width - MARGIN)
        left = Math.max(MARGIN, left)
        p.style.width = `${Math.round(width)}px`
        p.style.left = `${Math.round(left)}px`
        const panelHeight = p.getBoundingClientRect().height
        // ⚠️ Задача 3.94: третья ветка добавлена, когда `feats_info/1`
        // (стопка из нескольких описаний, у Barbarian 1 — шесть) впервые
        // сделала панель ВЫШЕ доступного места И сверху, И снизу от
        // триггера — то, чего одиночная `feat_info/1` практически никогда
        // не задевала. Без неё «не влезает снизу» безусловно вело в «встать
        // низом к триггеру», и верх панели уезжал ЗА пределы вьюпорта вверх
        // без какого-либо способа его увидеть — `max-height` в app.css
        // ограничивает СОБСТВЕННУЮ высоту панели, но не чинит, ГДЕ эту
        // высоту поставили. Раз `max-height: calc(100vh - 2 * MARGIN)`,
        // прижатая к верху панель ГАРАНТИРОВАННО не достаёт до низа —
        // фолбэк безопасен всегда, а не только «обычно».
        if (rect.bottom + 6 + panelHeight <= window.innerHeight - MARGIN) {
          p.style.top = `${Math.round(rect.bottom + 6)}px`
          p.style.removeProperty("bottom")
        } else if (rect.top - 6 - panelHeight >= MARGIN) {
          p.style.bottom = `${Math.round(window.innerHeight - rect.top + 6)}px`
          p.style.removeProperty("top")
        } else {
          p.style.top = `${MARGIN}px`
          p.style.removeProperty("bottom")
        }
      }

      function open(trigger, pin) {
        if (openTrigger && openTrigger !== trigger) close()
        const reopening = openTrigger === trigger
        openTrigger = trigger
        pinned = pin || (reopening && pinned)
        openedAt = performance.now()
        renderContent(trigger)
        place(trigger)
        const p = ensurePanel()
        p.dataset.open = "1"
        p.removeAttribute("aria-hidden")
        applyExpandedState(trigger)
      }

      function close(opts = {}) {
        if (!openTrigger) return
        const trigger = openTrigger
        if (panel) {
          panel.dataset.open = "0"
          panel.setAttribute("aria-hidden", "true")
        }
        openTrigger = null
        pinned = false
        applyExpandedState(trigger)
        if (opts.restoreFocus) {
          suppressAutoOpen = true
          trigger.focus()
          suppressAutoOpen = false
        }
      }

      // ⚠️ `aria-expanded`/`aria-describedby` — состояние КЛИЕНТА, и разметка
      // от сервера про них не знает вовсе (ни то, ни другое не написано
      // в HEEx статикой, ровно как у `.StatPop` выше). Патч LiveView, задевший
      // эту строку по НЕСВЯЗАННОЙ причине — правка соседнего пика, поиск,
      // смена уровня, — иначе стёр бы «открыто», выставленное кликом секунду
      // назад: тот же баг, что стоит в комментарии у `.StatPop.updated()`.
      function applyExpandedState(el) {
        if (openTrigger === el) {
          el.setAttribute("aria-expanded", "true")
          el.setAttribute("aria-describedby", PANEL_ID)
        } else {
          el.setAttribute("aria-expanded", "false")
          el.removeAttribute("aria-describedby")
        }
      }

      // ⚠️ Открытие тапом само устраивает мышиный хаос: у сенсорных
      // устройств нет настоящего курсора, и Chrome достраивает связку
      // touchstart→(pointerdown/mousedown/focus/pointerup/mouseup)→click
      // сама, ДЛЯ СОВМЕСТИМОСТИ со старым кодом. Как только панель открылась
      // и легла ровно под точку тапа (а на телефоне это нередкость — узкая
      // колонка, шторка снизу), достроенные `mouseover`/`mouseenter` начинают
      // попадать уже В ПАНЕЛЬ, а не в триггер, и следом летит `mouseleave`
      // С ТРИГГЕРА — панель, которую только что открыли тем же тапом, гасится
      // им же меньше чем через 3мс. `click`, который в итоге долетает,
      // попадает вообще не в триггер (мимо, часто в `<body>`) — то же самое
      // избегание, которым CLAUDE.md уже объясняет ловушку `pushEvent`.
      // Найдено CDP-прогоном 24.08.2026 (полная трассировка событий,
      // `Evasion` в недоступных — длинная цитата раздувает панель настолько,
      // что она перекрывает точку тапа; `Iron will` короче и не перекрывает,
      // поэтому там глазами баг было не поймать).
      //
      // Лечится не запретом слушателей, а тем же приёмом, что у скролла ниже:
      // «пассивные» сигналы закрытия (мышь ушла, клик мимо) в первые
      // `DISMISS_GUARD_MS` после открытия не считаются — они с большей
      // вероятностью эхо самого открытия, чем второе, отдельное действие.
      // «Активные» — Esc, «×», повторный клик по триггеру — эту защиту не
      // спрашивают вовсе, им и не нужно.
      function recentlyOpened() {
        return performance.now() - openedAt < DISMISS_GUARD_MS
      }

      // Клик вне, Esc — один раз на документ, а не по разу на триггер.
      // Скролл закрывает ТОЛЬКО заякоренную (десктопную) панель: шторка
      // не привязана к триггеру и от прокрутки фона не «отрывается».
      function bindGlobalOnce() {
        if (globalBound) return
        globalBound = true

        document.addEventListener("click", e => {
          if (!openTrigger || recentlyOpened()) return
          if (openTrigger.contains(e.target)) return
          if (panel && panel.contains(e.target)) return
          close()
        }, true)

        document.addEventListener("keydown", e => {
          if (e.key !== "Escape" || !openTrigger) return
          close({ restoreFocus: document.activeElement === openTrigger })
        })

        // ⚠️ Открытие фокусом САМО двигает скролл: браузер подводит только что
        // сфокусированный элемент в видимую область, если он не весь виден
        // (нередкость — список фитов длинный и скроллится), и это тоже
        // событие «scroll». Без защиты страница закрывала бы панель тем же
        // действием, которым её открыла клавиатура, — открыть Tab'ом было
        // физически невозможно ни разу (найдено CDP-прогоном, 24.08.2026,
        // не в теории, а по трассировке: `close()` шёл через ~16мс после
        // `open()`, вызванный ровно этим слушателем).
        window.addEventListener("scroll", () => {
          if (openTrigger && !mobile() && !recentlyOpened()) close()
        }, true)
        window.addEventListener("resize", () => { if (openTrigger) close() })
      }

      export default {
        mounted() {
          bindGlobalOnce()
          applyExpandedState(this.el)

          this.onEnter = () => this.scheduleOpen()
          this.onLeave = () => this.scheduleClose()
          this.onFocus = () => {
            if (suppressAutoOpen) return
            clearTimeout(openTimer)
            open(this.el, false)
          }
          this.onBlur = () => this.scheduleClose()

          this.el.addEventListener("mouseenter", this.onEnter)
          this.el.addEventListener("mouseleave", this.onLeave)
          this.el.addEventListener("focus", this.onFocus)
          this.el.addEventListener("blur", this.onBlur)

          // preventDefault + stopPropagation ДО того, как событие дойдёт до
          // единственного window-слушателя LiveView (`bindClick`): иначе тап
          // по ⓘ, лежащему внутри `<button class="feat" phx-click="pick_feat">`,
          // выбрал бы фит — ровно та ловушка, что уже стоила проекту бага 1.11.
          this.el.addEventListener("click", (e) => {
            e.preventDefault()
            e.stopPropagation()
            this.toggle()
          })
          this.el.addEventListener("keydown", (e) => {
            if (e.key === "Enter" || e.key === " " || e.key === "Spacebar") {
              e.preventDefault()
              e.stopPropagation()
              this.toggle()
            } else if (e.key === "Escape" && openTrigger === this.el) {
              e.preventDefault()
              e.stopPropagation()
              close({ restoreFocus: true })
            }
          })
        },
        // Патч LiveView'а может перерисовать эту строку по несвязанной причине
        // (правка соседнего пика, поиск, смена уровня) — `aria-expanded`
        // обязана переприменяться КАЖДЫЙ раз (см. `applyExpandedState`), иначе
        // клик, открывший панель секунду назад, откатывается первым же чужим
        // патчем. Контент («изменено на Сиале» и всё остальное) пересобирается
        // только если панель открыта именно на нас — на случай, если диффер
        // вместе с атрибутами обновил и данные фита.
        updated() {
          applyExpandedState(this.el)
          if (openTrigger === this.el) renderContent(this.el)
        },
        destroyed() {
          clearTimeout(openTimer)
          if (openTrigger === this.el) close()
        },
        scheduleOpen() {
          clearTimeout(openTimer)
          if (openTrigger === this.el) return
          openTimer = setTimeout(() => open(this.el, false), 200)
        },
        // `mouseleave`/`blur` — та же «пассивная» ветка, что у скролла и
        // клика мимо (`recentlyOpened()`): курсор touch-устройства «уходит»
        // с триггера через пару миллисекунд после того же тапа, которым его
        // открыли, а не потому что пользователь передумал.
        scheduleClose() {
          clearTimeout(openTimer)
          if (pinned && openTrigger === this.el) return
          if (openTrigger === this.el && !recentlyOpened()) close()
        },
        toggle() {
          clearTimeout(openTimer)
          if (openTrigger === this.el && pinned) close({ restoreFocus: true })
          else open(this.el, true)
        }
      }
    </script>
    """
  end

  @doc """
  `feat_info/1`, opening onto SEVERAL feats at once instead of one —
  task 3.94, and the reason it exists rather than a loop calling `feat_info/1`
  once per feat.

  The view screen's levelling guide joins every feat a class grants at one
  level into ONE line of copy-pasteable text (`build_view_live.ex`,
  `.v-g-granted` — "Deflect arrows, Wholeness of body", CLAUDE.md §6). A
  per-feat trigger there measurably grows the row: even a single extra pixel
  of width on one interior name can push the whole line's greedy word-wrap
  into an extra visual line, and it happens at real, unremarkable widths —
  measured live over CDP (25.08.2026), Fighter's five level-1 grants add one
  text-line at 420–440px, 768–800px and 1000px; the same reflow happens with
  just one long-named *picked* feat sharing a line with them.

  ⚠️ **One combined trigger, placed once after every name, is not enough by
  itself** — the first thing tried here, and CDP measurement caught it as
  wrong before it shipped: at 768px specifically the line's last visual row
  has only ~5–9px of leftover space, and the trigger's ordinary 14–17px
  footprint (`.feat-info`'s own `width`/`border`/`margin-left`) is enough on
  its own to push a *second* extra line — no interior word involved at all.
  A synthetic marker up to 80px wide once measured as harmless there, but
  that measurement compared against a DOM that *still carried the five
  per-name triggers*, i.e. against a baseline that had already wrapped; it
  proved a marker on top of an already-broken row doesn't break it *worse*,
  not that a marker is safe against the correct, trigger-free baseline. Redone
  against that baseline, the real threshold at 768px turned out to be
  somewhere between 5px and 10px.

  So the trigger this component renders (`feat-info-trailing`, `app.css`)
  contributes **zero width to the line**: `width: 0`, `overflow: visible`,
  with the visible dot and its larger tap zone drawn by two absolutely
  positioned pseudo-elements that read from the anchor's position but do not
  size it — verified by the same CDP sweep coming back all-zero afterwards,
  360–1400px. `feat_info/1`'s own per-pick trigger (`row.feats`, the
  constructor's picker) is untouched and keeps its ordinary box: nothing else
  there shares a line with a sibling feat, so it was never at risk, and giving
  it up would only cost precision (its bigger, centred tap zone) for no gain.

  Shares `feat_info/1`'s hook and panel — same module, so the dot-prefixed
  `phx-hook=".FeatInfo"` resolves to the identical
  `BuildCalculatorWeb.BuilderComponents.FeatInfo` compiled once from that
  component's colocated `<script>`, and `renderContent`'s `d.featEntries`
  branch (that script, above) is the only thing that differs — positioning,
  open/close, the mobile sheet, the tap-echo guard: one copy, not two.

  ⚠️ `entries` MUST already be filtered to items with a `description` — same
  contract `feat_info/1` leaves to *its* caller (`:if={feat.info.description}`
  at the call site), kept here rather than re-checked inside: the caller
  already knows which of a level's several grants have nothing to show
  (CLAUDE.md §3, the eleven Siala-only feats), and re-filtering here would be
  a second place that same decision could drift from the first.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "aria-label AND the panel's own visible heading"

  attr :entries, :list,
    required: true,
    doc:
      "[%{name:, description:, siala_changed?:, siala_notes:, siala_notes_more_text:, source_url:, source_link_text:}, …] — same shape `Labels.feat_info/2` returns, plus :name"

  def feats_info(assigns) do
    entries_json =
      Enum.map(assigns.entries, fn entry ->
        %{
          name: entry.name,
          description: entry.description,
          changed: entry.siala_changed?,
          notes: entry.siala_notes,
          notesMore: entry.siala_notes_more_text,
          sourceUrl: entry.source_url,
          sourceText: entry.source_link_text
        }
      end)

    assigns = assign(assigns, :entries_json, Jason.encode!(entries_json))

    ~H"""
    <%!-- `feat-info-trailing` (app.css) strips this element's own layout
    width to zero — the visible dot is drawn by a pseudo-element instead, see
    the moduledoc above for why the ordinary `.feat-info` box is unsafe right
    here. The literal "ⓘ" stays in the DOM (screen readers/copy-paste see
    something even if CSS fails to load) but is visually suppressed —
    `aria-label` already carries the accessible name, so nothing is lost. --%>
    <span
      class="feat-info feat-info-trailing"
      id={@id}
      role="button"
      tabindex="0"
      phx-hook=".FeatInfo"
      aria-haspopup="dialog"
      aria-label={@label}
      data-feat-entries={@entries_json}
      data-label-changed={gettext("Changed on Siala")}
      data-label-changed-generic={
        gettext(
          "The shard changed this feat's requirements or availability — see this feat's own row for details."
        )
      }
      data-label-vanilla={gettext("Vanilla description (Fandom)")}
      data-label-close={gettext("Close")}
    >ⓘ</span>
    """
  end

  @doc """
  Delta pills, laid out in meaning rows.

  Not one flat row in field order: `Fort` used to land next to `HP` and `Will`
  next to `СП`, and the card read as a random pile of numbers. Four rows —
  what the level *gives* (HP, BAB, AC, attacks), the saves, the skill points,
  and the *decisions* it opens (a feat slot, +1 to an ability) — each with its
  own colour, so the eye sorts them before it reads a single label.

  A chip may carry a `:title`: the "от класса ×3" pill names the three feats
  there, because a count without names answers "how many" and not "which".
  """
  attr :id, :string, default: nil
  attr :rows, :list, required: true

  def delta_chips(assigns) do
    ~H"""
    <div class="deltas" id={@id}>
      <div :for={row <- @rows} class="d-row" data-row={row.row}>
        <span
          :for={chip <- row.chips}
          class={["d", chip.kind]}
          data-row={row.row}
          title={Map.get(chip, :title)}
        >
          <%!-- Подпись и число — разными элементами, а не одной строкой: подпись
                идёт интерфейсным шрифтом, число моноширинным. Кириллицы в SF Mono
                и Menlo нет, и «общий фит» одним куском в моношрифте падал в другой
                шрифт с другими метриками — плашка вырастала вдвое. --%>
          <i>{chip.text}</i>
          <b :if={Map.get(chip, :value)}>{Map.get(chip, :value)}</b>
        </span>
      </div>
    </div>
    """
  end

  @doc """
  «Кнопка → поиск → стрим → „ещё N"» — the workflow the "Вещи" block
  repeated eight times before this task (AGENT_QUEUE.md 3.135, Dan
  28.08.2026: «Если мы сможем выработать какой-то удобный компонент
  интерфейса, то потом если что можно в разных местах его применить
  разными агентами»). Covers five of the seven parts that task's own audit
  found identical at four of those eight call sites: the toggle button, the
  search form, the candidate stream, the empty state, and the "…и ещё N"
  overflow line. The other two — an already-chosen row and its remove
  button — are `picked_item/1`, on purpose and not folded in here: Dan's
  second note warned that one all-purpose component is a known way to make
  things worse ("орган с пятнадцатью attr… читается тяжелее трёх честных"),
  and picking and un-picking answer different questions.

  Wired up at exactly two of the eight sites this task names when it first
  landed — `gear-weapon` and `gear-feat` — chosen because they are
  DISSIMILAR (weapon rules versus feat rules), not near-clones like
  `gear-weapon`/`gear-off-weapon` would have been: a contract proven against
  two genuinely different shapes of data is worth more than one proven
  against two copies of the same shape.

  A third site landed the day after, once Dan had seen that pair and said
  "go ahead" (AGENT_QUEUE.md 3.135's own rollout note, 29.08.2026):
  `gear-off-weapon`. The note checked each of the remaining six against
  this component's *real* `attr` list, not the part-presence table the task
  opened with, and only this one turned out to fit — it is the near-clone
  of `gear-weapon` the moduledoc above already set aside on purpose. The
  other five (`gear-skill`, `spell`, the scene's own `feat` slot, `skill`,
  `gear-feat-choice`) are not thinner copies of this control, they are
  *different* controls that happen to also carry a search box:
  `gear-skill`'s candidates are chips off an assign, not a stream, and its
  chosen row carries a numeric field `picked_item/1` has no attr for;
  `spell` and the scene's `feat` have no toggle button; `skill` has neither
  a stream nor an overflow line; `gear-feat-choice` is a search box and
  nothing else. Each would turn off more of this component than it turns
  on — the rollout note's own rule for "does not fit" — so none of them are
  wired up here, and none should be without re-checking against whatever
  this component's contract has grown into by then.

  ## Every child id is `"\#{id}-…"`, not invented per call site

  `\#{id}-add-toggle`, `\#{id}-search-form`, `\#{id}-search`, `\#{id}-none`,
  `\#{id}-options` (the stream container), `\#{id}-body` (new — see below),
  `\#{id}-more`. This is not a new scheme: it is the one `gear-weapon-*`/
  `gear-feat-*`/`gear-off-weapon-*` already used before their call sites
  moved here (and `gear-skill-*` still does, outside this component's
  border), so `id="gear-weapon"` / `id="gear-feat"` / `id="gear-off-weapon"`
  reproduce every pre-existing id byte for byte — the LiveView tests
  asserting `#gear-weapon-add-toggle`, `#gear-feat-options`,
  `#gear-off-weapon-options` and their siblings did not need to change.

  ## `stream` is the raw `@streams.*` entry, not a plain list

  A `phx-update="stream"` container nested inside a function component call
  reconciles the same way as one written inline: function components are
  inlined into the caller's rendered tree at compile time, they are not
  their own diff boundary the way `Phoenix.LiveComponent` is, so LiveView's
  stream diffing does not know or care that the `:for` consuming it sits one
  call deeper. Each row still carries whatever `dom_id`
  `stream_configure/2` gave it in `BuilderLive.mount/3` (untouched by this
  task and its rollout) — the three wired-up call sites keep their
  pre-existing, *different* prefixes (`"gear-weapon-"` for the main hand,
  `"gear-off-weapon-"` for the off hand, `"gear-pick-"` for feats) on
  purpose; this component reads the `dom_id` the stream tuple already
  carries, it never reconstructs one.

  ## Rows arrive pre-translated — this component calls neither `Labels` nor `Feats`

  CLAUDE.md §5: the core hands back machine reasons, the web layer turns
  them into Russian. A shared *presentational* component is the wrong place
  to decide which translator a given reason deserves — weapon rows use
  `Labels.reason/2`, feat rows use the shorter `Feats.reason/2` (a feat's
  own name is already on its row, so `Feats.reason/2` does not repeat it —
  see that function's own doc). Both callers (`GearPanel`) keep deciding
  that; every row this component receives already carries the finished
  Russian string in `reason_text`/`caveats`/`alias_note`.

  ## `🔒` now prefixes a feat pick's reason too — a deliberate content change

  Before this task the lock glyph only sat on weapon rows: it reuses the
  class card's "unavailable" language on purpose, and a *caveat* — an
  available item with an unproven aspect, e.g. a club needing no
  proficiency at all — never got it, because a lock on an available item
  would be a lie. A shard-disabled feat pick (`Devastating critical`) is
  exactly the same kind of "unavailable, here is why" as a weapon missing
  its proficiency feat; it simply never got the glyph, because the two
  lists grew on different days by different tasks. Folding both into one
  component makes that inconsistency visible, and closing it is exactly the
  "однородность" Dan asked for — called out here, and in this task's own
  report, so it reads as a decision on record rather than a side effect.

  ## `row.pick_attrs` — a per-row dynamic `phx-value-*`, without `String.to_atom/1`

  A weapon pick fires `phx-value-weapon`; a feat pick (adding *and* removing
  share one handler, `"toggle_gear_feat"`) fires `phx-value-feat`. Renaming
  either handler's param to a generic name, so this component would not
  need to know which one to use, was rejected on purpose — it would touch
  `BuilderLive`'s event contract for no benefit beyond saving one attribute
  here. Instead every row already carries its own finished
  `["phx-click": …, "phx-value-…": row.id]` (`GearPanel` builds it, spread
  onto the button with `{row.pick_attrs}`) — every key is a literal atom
  written in `GearPanel`'s own source at compile time (`"phx-value-weapon":
  id` is sugar for `:"phx-value-weapon" => id`, per `Phoenix.Component`'s
  own docs on dynamic attributes), never an atom built from a runtime
  string, so nothing here calls the forbidden `String.to_atom/1` on
  anything resembling user input.
  """
  attr :id, :string,
    required: true,
    doc: "id prefix — every child id below is \"\#{id}-…\", e.g. \"gear-weapon\""

  attr :open?, :boolean, required: true
  attr :toggle_label, :string, required: true
  attr :toggle_event, :string, required: true

  attr :search_event, :string, required: true, doc: "fires on both phx-change and phx-submit"
  attr :query, :string, required: true
  attr :search_placeholder, :string, required: true
  attr :search_label, :string, required: true, doc: "aria-label on the search input"

  attr :stream, :any,
    required: true,
    doc: "the raw @streams.* entry (a LiveStream of {dom_id, row} pairs), not a list"

  attr :total, :integer, required: true
  attr :shown, :integer, required: true

  attr :show_icons?, :boolean,
    default: false,
    doc: "weapons carry no icon art at all (no asset, not a data gap); feats do"

  attr :chosen_label, :string, default: "✓ выбрано", doc: "печатается у row.chosen? == true"

  def pick_list(assigns) do
    ~H"""
    <div class="gear-add">
      <button
        type="button"
        class="btn"
        id={@id <> "-add-toggle"}
        phx-click={@toggle_event}
        aria-expanded={to_string(@open?)}
        aria-controls={@id <> "-body"}
      >
        {@toggle_label}
      </button>
    </div>

    <div :if={@open?} id={@id <> "-body"}>
      <form phx-change={@search_event} phx-submit={@search_event} id={@id <> "-search-form"}>
        <input
          type="search"
          class="feat-search"
          id={@id <> "-search"}
          name="q"
          value={@query}
          placeholder={@search_placeholder}
          aria-label={@search_label}
          phx-debounce="120"
          autocomplete="off"
        />
      </form>

      <p :if={@total == 0} class="empty-row" id={@id <> "-none"}>
        Ничего не нашлось.
      </p>

      <%!-- Недоступное не прячем, а показываем с причиной (CLAUDE.md §6) —
          `🔒` перед причиной переиспользует язык замков карточки класса
          (`card-lock`), оговорка (`row.caveats`) его не получает: она стоит
          и на доступном предмете, там замок был бы неправдой. --%>
      <div class="gear-picks" id={@id <> "-options"} phx-update="stream">
        <button
          :for={{dom_id, row} <- @stream}
          type="button"
          class="gear-pick"
          id={dom_id}
          data-on={if row.chosen?, do: "1"}
          disabled={row.reason_text != nil}
          {row.pick_attrs}
        >
          <.game_icon
            :if={@show_icons?}
            path={row.icon_path}
            glyph={row.icon_glyph}
            epic?={row.icon_epic?}
            class="gear-pick-icon"
          />
          <span class="gear-pick-n"><.highlight segments={row.segments} /></span>
          <span :if={row.alias_note} class="feat-alias">{row.alias_note}</span>
          <span :if={row.reason_text} class="feat-why">🔒 {row.reason_text}</span>
          <span :for={caveat <- row.caveats} class="feat-why">{caveat}</span>
          <span :if={row.chosen?} class="gear-pick-on">{@chosen_label}</span>
        </button>
      </div>

      <p :if={@total > @shown} class="empty-row" id={@id <> "-more"}>
        …и ещё {@total - @shown}. Уточни поиск.
      </p>
    </div>
    """
  end

  @doc """
  One already-chosen, removable row — the other two of the seven parts
  `pick_list/1`'s own doc names (AGENT_QUEUE.md 3.135).

  Deliberately NOT a list-owning component. `gear-feat`'s `<ul>` has to
  interleave this simple row with the domain-choice sub-widget's much
  richer, multi-entry markup (`Skill focus`, `Weapon focus`…) in the SAME
  list, in the order `@gear.feats` already gives them — and that sub-widget
  (`gear-feat-choice`) is explicitly outside this task's border (the plan's
  own "НЕ брать" row). A component that owned the whole `<ul>` would have to
  either grow a data shape for that nested widget too — defeating the point
  of staying small, per Dan's second note — or split into two `<ul>`s and
  break the interleaved order. Called with `:for` at each site instead,
  exactly like `<.highlight>`/`<.game_icon>` already are: the call site
  keeps its own `<ul>`, and `gear-feat` keeps its own
  `if row.domain do … else <.picked_item …> end` branch untouched on the
  `if` side.

  `remove_attrs` is the same dynamic-`phx-value` trick as `pick_list/1`'s
  `row.pick_attrs` — see that component's own moduledoc for why it exists
  instead of a renamed event param.

  ⚠️ No `note` attr here — AGENT_QUEUE.md 3.136 (29.08.2026, Dan's screenshots)
  found that an in-`<li>` note (weapon's "вытеснило щит" line) widens this
  `<li>`'s hypothetical one-line width enough that the sibling `<form>` in
  `.gear-weapon-line` (Attack bonus) gets pushed to a second row — `<ul>`'s
  own `flex: 1 1 auto` can shrink, but the OUTER flex container's line-break
  decision is made against each item's unshrunk (content) size, so a wide
  `<li>` still wins even though it could visually shrink. Moving the note
  markup OUT of this `<li>`, to a plain sibling `<p>` below `.gear-weapon-line`
  at each of the two call sites, sidesteps that nested-flex sizing question
  entirely instead of fighting it with `flex-basis: 100%` (which forces a
  line break WITHIN the `<li>`, but doesn't reliably shrink the `<li>`'s
  intrinsic/hypothetical width contribution to its own flex ancestor — the
  very edge case this bug lives in). Re-adding `note` here would silently
  restore the old bug for both hands.

  ⚠️ `reason`/`reason_id` are still here — 3.136 only fixed the note, and
  AGENT_QUEUE.md 3.137 (29.08.2026, coordinator's own measurement) found the
  SAME bug still lived one attr over: a weapon's `reason` ("нужен фит
  Владение молотами") is exactly as wide as the note was, and both call
  sites were still passing it, so the fix from 3.136 was only half done.
  3.137 stopped the two weapon call sites (`#gear-weapon`, `#gear-off-weapon`,
  folded by AGENT_QUEUE.md 3.138 заход П4 into `gear_weapon_hand/1` below)
  from passing `reason`/`reason_id` at all — each now prints its own reason
  as a sibling `<p class="gear-feat-bad">` below `.gear-weapon-line`, first
  in the stack (before the note, before `.gear-capped`), by the exact same
  reasoning as the note's move.

  The attrs themselves are NOT removed, because the third call site — the
  "Фиты с вещи" feat list (`#gear-feat-list`) — still uses them, and correctly
  so: that `<li>` sits in a `flex-wrap: wrap` list with no sibling `<form>`
  to push around, so an in-row reason has nothing to break (Dan was never
  shown a complaint about it, and the postmortem confirms there's nothing to
  fix there). Dropping `reason`/`reason_id` from the component to "finish the
  job" would have broken that call site for no reason — the bug lives in
  `.gear-weapon-line`'s nested-flex sizing, not in the attr itself.
  """
  attr :id, :string, required: true, doc: "the <li> id"
  attr :name, :string, required: true

  attr :show_icon?, :boolean,
    default: false,
    doc: "weapons carry no icon art at all (no asset, not a data gap); feats do"

  attr :icon_path, :string, default: nil
  attr :icon_glyph, :string, default: nil
  attr :icon_epic?, :boolean, default: false

  attr :reason, :string, default: nil, doc: "already translated; nil means nothing to show"
  attr :reason_id, :string, default: nil

  attr :remove_id, :string, required: true
  attr :remove_label, :string, required: true, doc: "aria-label AND title on the × button"
  attr :remove_attrs, :list, required: true, doc: "e.g. [\"phx-click\": \"drop_gear_weapon\"]"

  def picked_item(assigns) do
    ~H"""
    <li id={@id}>
      <.game_icon :if={@show_icon?} path={@icon_path} glyph={@icon_glyph} epic?={@icon_epic?} />
      <span class="gear-feat-n">{@name}</span>
      <span :if={@reason} class="gear-feat-bad" id={@reason_id}>{@reason}</span>
      <button
        type="button"
        class="gear-x"
        id={@remove_id}
        aria-label={@remove_label}
        title={@remove_label}
        {@remove_attrs}
      >
        ×
      </button>
    </li>
    """
  end

  @doc """
  One weapon hand's whole zone in «Вещи»: picked row + its own Attack bonus
  number + "can't hold it" reason + "displaced the shield" note + cap notice
  + the picker. `builder_live.html.heex` carried this shape TWICE — main
  hand and off hand, ~280 lines together — differing only in ids, event
  names and four short strings (AGENT_QUEUE.md 3.138, заход П4). Composes
  `picked_item/1` and `pick_list/1`, the same way those two are themselves
  composed of `game_icon/1`/`highlight/1`; nothing here duplicates their
  markup.

  ## Two calls, one component: `id="gear-weapon"` and `id="gear-off-weapon"`

  Every child id below is `"\#{id}-…"` — the same scheme `pick_list/1` and
  `picked_item/1` already use — so `id="gear-weapon"` reproduces
  `gear-weapon-line`, `gear-weapon-attack`, `gear-weapon-attack-input`,
  `gear-weapon-bad`, `gear-weapon-blocks-worn`, `gear-weapon-capped` byte
  for byte, and `id="gear-off-weapon"` reproduces their off-hand twins the
  same way. The LiveView tests asserting each of those
  (`builder_gear_weapon_test.exs`, `builder_off_hand_weapon_test.exs`,
  `builder_gear_issues_test.exs`) did not need to change. `pick_list/1`'s
  own five ids (`-add-toggle`, `-search`, `-options`…) come from the nested
  `<.pick_list id={@id} …/>` call, not reconstructed here a second time —
  and, as before this task, the OUTER `<div id={@id}>` and the nested
  `<.pick_list id={@id}>` sharing one literal string never collide, because
  `pick_list/1` never emits a bare `id={@id}` of its own.

  ## Event names stay two per hand — merging THAT is a different task

  `attack_event`, `drop_event`, `toggle_event`, `search_event` are still
  passed in as literal strings, one call site per hand, exactly as they
  were written twice in `builder_live.html.heex` before this task. Giving
  both hands the SAME event name (so `BuilderLive` tells them apart by a
  `hand` param instead) was considered and turned down one заход earlier —
  AGENT_QUEUE.md 3.138 заход П3, "Развилка (а)/(б): выбрано (а)" — because
  it would touch `GearPanel`'s and `BuilderLive`'s event contract for a
  display-only win, and that task's scope was `builder_live.ex` alone. This
  component only folds the MARKUP that was identical in shape; it is
  variant (a) carried one step further, not variant (b).

  ## `cap` is ONE pool shared by both hands, not two

  `GearPanel.assign_gear_map/12` computes `weapon_cap` exactly once
  (`Caps.cap(ruleset, :attack_bonus)`) — the main hand and the off hand
  spend down the same +20 attack-bonus cap (CLAUDE.md §3, "Кап атаки
  снова НЕДОСТИЖИМ"), so both calls are handed the identical `cap` value on
  purpose, not two different numbers that happen to match today. `capped?`
  is NOT shared the same way — `:attack_bonus in stats.capped` for the main
  hand, `stats.off_hand.attack_capped?` for the off hand (see
  `GearPanel.gear_weapon_row/4`'s own comment) — a weapon in one hand can
  push the shared pool over the top while the other hand's own arithmetic
  still fits under it.

  ## `attack_value` arrives already resolved

  `gear_input_value/1` (a zero prints as an empty field, so the box does
  not lie about "0" being typed) is `defp` on `BuilderLive`; a function
  component in a different module cannot reach a private function of the
  LiveView, so both call sites in `builder_live.html.heex` still resolve it
  before handing the number over — exactly what they did inline before this
  component existed, just one call instead of a duplicated one.

  ## Every reason/note/cap paragraph stays a DIRECT sibling of `.gear-weapon-line`

  `assets/css/app.css`'s `.gear-weapon-line + .gear-feat-bad` rule only
  fires when `.gear-feat-bad` is that `<div>`'s immediate next sibling —
  the mechanism AGENT_QUEUE.md 3.136/3.137 built so the "can't hold it"
  reason and the "displaced the shield" note stop widening
  `.gear-weapon-line`'s own hypothetical flex width and pushing the Attack
  bonus `<form>` onto a second line (see that CSS rule's own comment for
  the layout math). A function component does not add a wrapping DOM node
  of its own — it inlines its `~H` output into the caller's tree at compile
  time — so copying this markup in here, unchanged in order, preserves
  that adjacency exactly; reordering the four elements below would break
  the CSS silently, with no test catching it (the suite asserts ids and
  visible text, not sibling order).
  """
  attr :id, :string,
    required: true,
    doc: "\"gear-weapon\" or \"gear-off-weapon\" — every child id is \"\#{id}-…\""

  attr :title, :string, required: true, doc: "«Оружие в руках» / «Оружие второй руки»"
  attr :rule, :string, required: true

  attr :weapon, :map,
    default: nil,
    doc: "%{id:, name:, reason_text:, blocks_worn_note:} or nil — GearPanel.gear_weapon_row/4"

  attr :attack_event, :string, required: true

  attr :attack_value, :any,
    default: nil,
    doc: "already run through BuilderLive.gear_input_value/1"

  attr :attack_filled?, :boolean, required: true
  attr :attack_hint, :string, required: true, doc: "title on the Attack bonus input"
  attr :input_min, :integer, required: true

  attr :drop_event, :string, required: true
  attr :capped?, :boolean, required: true

  attr :cap, :integer,
    default: nil,
    doc: "the shared +20 attack-bonus pool — same value both hands"

  attr :open?, :boolean, required: true
  attr :toggle_event, :string, required: true

  attr :empty_toggle_label, :string,
    required: true,
    doc: "«+ Выбрать оружие» / «+ Выбрать оружие второй руки»"

  attr :search_event, :string, required: true
  attr :query, :string, required: true
  attr :search_label, :string, required: true, doc: "«Поиск оружия» / «Поиск оружия второй руки»"

  attr :stream, :any, required: true, doc: "the raw @streams.* entry, see pick_list/1"
  attr :total, :integer, required: true
  attr :shown, :integer, required: true

  def gear_weapon_hand(assigns) do
    ~H"""
    <div class="gear-feats" id={@id}>
      <span class="eyebrow">{@title}</span>
      <p class="gear-rule">{@rule}</p>

      <%!-- Оружие и его Attack bonus на одной строке, если влезает (задача
            3.134, идея Dan: «двумя соседними инпутами на одной строке»).
            `.gear-weapon-line` — флекс с переносом, а не брейкпоинт: у
            короткого имени (Mace, Club, Dagger) поле само встаёт рядом на
            одной строке, у длинного (Two-bladed sword) переносится под —
            шириной решает контент колонки, которая и так тянется мышью
            (CLAUDE.md §6), а не медиа-запрос. --%>
      <div class="gear-weapon-line" id={@id <> "-line"}>
        <ul :if={@weapon} id={@id <> "-list"}>
          <.picked_item
            id={"#{@id}-row-#{@weapon.id}"}
            name={@weapon.name}
            remove_id={@id <> "-drop"}
            remove_label={"Снять #{@weapon.name}"}
            remove_attrs={["phx-click": @drop_event]}
          />
        </ul>

        <form phx-change={@attack_event} id={@id <> "-attack-form"}>
          <label class="gear-cell" id={@id <> "-attack"} data-filled={if @attack_filled?, do: "1"}>
            <%!-- ⚠️ `Attack bonus` — ИГРОВОЕ имя свойства предмета, как оно
                  написано на самом оружии в NWN (§4: имя из игры показываем,
                  фанатский перевод — нет). Здесь стояло «атака» — наше
                  слово, которого нет ни в игре, ни на вики, и Dan
                  26.08.2026 назвал его непонятным. --%>
            <span class="gear-k">Attack bonus</span>
            <input
              type="number"
              class="gear-num"
              id={@id <> "-attack-input"}
              name="attack"
              value={@attack_value}
              placeholder="0"
              min={@input_min}
              inputmode="numeric"
              autocomplete="off"
              phx-debounce="150"
              title={@attack_hint}
            />
          </label>
        </form>
      </div>

      <%!-- Причина ПЕРВОЙ, до примечания и до `.gear-capped` (задача 3.137)
            — она про само оружие («можно ли его вообще держать»), а не про
            побочный эффект. Все три — прямые СОСЕДИ `.gear-weapon-line`,
            не третий спан внутри `<li>` (см. moduledoc выше и
            `.gear-weapon-line + .gear-feat-bad` в app.css). --%>
      <p :if={@weapon && @weapon.reason_text} class="gear-feat-bad" id={@id <> "-bad"}>
        {@weapon.reason_text}
      </p>
      <p :if={@weapon && @weapon.blocks_worn_note} class="gear-feat-note" id={@id <> "-blocks-worn"}>
        {@weapon.blocks_worn_note}
      </p>
      <%!-- Срез называет себя, как у сейвов: кап один на число оружия и
            расовый бонус Сиалы, поэтому срезать может и при вводе меньше
            потолка. --%>
      <p :if={@capped?} class="gear-capped" id={@id <> "-capped"}>
        Вместе с остальным внутрикапным выходит больше потолка: в атаку идёт +{@cap}.
      </p>

      <.pick_list
        id={@id}
        open?={@open?}
        toggle_event={@toggle_event}
        toggle_label={
          cond do
            @open? -> "Свернуть список"
            @weapon -> "Сменить оружие"
            true -> @empty_toggle_label
          end
        }
        search_event={@search_event}
        query={@query}
        search_placeholder="Поиск обрывками: scim, lngsw"
        search_label={@search_label}
        stream={@stream}
        total={@total}
        shown={@shown}
        chosen_label="✓ в руках"
      />
    </div>
    """
  end
end
