defmodule BuildCalculatorWeb.BuildViewLive do
  @moduledoc """
  Read-only view of a shared build, at `/b/:code`.

  This is where a link lands — often on a phone, often on somebody who did not
  build it. So it answers a different question from the constructor: not "what
  do I press" but "what is this build and is it any good" (CLAUDE.md §6).
  Nothing is chosen here, which frees the whole page for totals — shown **with
  the arithmetic that produced them**, see `BuildCalculatorWeb.Builder.Summary`.

  Two things are deliberately louder here than in the constructor:

    * the standing note that Siala's rules are not fully transcribed, and the
      build's own `gaps`, **always open rather than behind a click** — a visitor
      who arrived from Discord does not know the project's history and will
      believe the numbers by default;
    * the way out: open the same build in the constructor, or copy the canonical
      text block.

  The code in the path is the same one the constructor writes. There is exactly
  one encoding (`BuildCalculator.Encoding`); the two screens differ
  by route, never by format.

  ## Two doors, one room

  `/b/:code` is the shared link and `/builds/:id` is a saved row, and they render
  the same page — because a saved build *is* a code plus a name
  (`BuildCalculator.Library.Build`). The id route fetches through
  `Library.fetch_build/2`, whose `where` already carries the visibility rules, so
  somebody else's private build is «не найден» here and never a page that says
  "you may not see this" — that answer would itself confirm the build exists.
  """
  use BuildCalculatorWeb, :live_view

  # `feat_info/1` — the "what this does" trigger the guide reuses on both
  # picked and class-granted feats (task 3.94). Same import the constructor
  # already carries; `BuilderComponents` is not part of the shared `:live_view`
  # helpers precisely because most LiveViews never need a feat row at all.
  import BuildCalculatorWeb.BuilderComponents

  alias BuildCalculator.Encoding
  alias BuildCalculator.Library
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}
  alias BuildCalculatorWeb.Builder.{Export, Feats, Gaps, Labels, Palette, Summary}

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    {:ok, socket |> prepare(code) |> assign(:saved, nil) |> open(code)}
  end

  def mount(%{"id" => id}, _session, socket) do
    case Library.fetch_build(socket.assigns.current_scope, id) do
      {:ok, saved} ->
        {:ok,
         socket
         |> prepare(saved.code)
         |> assign(:saved, saved)
         |> assign(:page_title, "#{saved.name} · Калькулятор билдов Сиалы")
         |> open(saved.code)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> prepare(nil)
         |> assign(:saved, nil)
         |> assign(:error, "Такого билда нет — или он не публичный, и вам его не показывают.")}
    end
  end

  defp prepare(socket, code) do
    socket
    |> assign(:page_title, "Билд · Калькулятор билдов Сиалы")
    |> assign(:code, code)
    |> assign(:error, nil)
    |> assign(:text_open?, false)
    # Задача 3.147 (Dan, 30.08.2026: «Давай ещё добавим эту галочку в
    # просмотр билда» — продолжение 3.146, конструктор). ОДИН переключатель
    # на весь экран: живёт на гиде (`guide_section/1`, всегда виден, не
    # спрятан в диалоге «показать текст»), а его состояние двигает и гид,
    # и текст диалога одним и тем же чтением (`export_text/1` ниже) — не два
    # независимых контрола, которые могли бы разойтись.
    #
    # ⚠️ Дефолт — РЕШЕНИЕ ВЛАДЕЛЬЦА, не наш выбор. Dan, тем же днём, вторым
    # сообщением: «Лучше выключить по дефолту, чтобы разгрузить UI» — тот же
    # довод и тот же дефолт, что у `BuilderLive`'s `:export_show_granted?`
    # (3.146), сознательно применённый к экрану с другой аудиторией (сюда
    # приходят по чужой ссылке, а не редактируют свой билд): решение Dan
    # прямо накрывает эту разницу, а не оставляет её на усмотрение агента.
    # Довод CLAUDE.md §6 («человек пришёл по ссылке и не знает, что `○`
    # и `✦` — разные вещи») не отменяется — он верен для того, кто выданное
    # включит; см. правку §6 тем же коммитом.
    |> assign(:view_show_granted?, false)
    # Задача 3.175 (Dan, 03.09.2026, со скриншотом): у прокачанного вора гид
    # превращается в стену — 5–7 строк навыков на уровень, за которыми не
    # видно ни фитов, ни прибавок. «надо нам ввести галочки в просмотре как
    # минимум… хочешь узнать только статы — поставил чекбоксы и видишь
    # только статы. Потом захотел только фиты — выставил чекбоксы и готово».
    #
    # Пять переключателей, а не три (Dan назвал скиллы/статы/фиты) — потому
    # что «фильтры просят «полностью»»: чтобы «видишь ТОЛЬКО статы» было
    # буквально верно, обязаны гаситься и заклинания, и разовый выбор класса
    # (домены клирика, школа волшебника) — иначе они остались бы висеть на
    # экране, где по условию должны быть только статы. Пять ключей —
    # буквально пять полей `Summary.guide_rows/2`: `feats`, `increase`,
    # `skills`, `spells`, `domains`.
    #
    # ⚠️ Умолчание — ВСЁ ВКЛЮЧЕНО (постановка): читатель приходит по чужой
    # ссылке и не знает, что что-то можно спрятать. Живёт в сокете и НЕ
    # кодируется в URL — тот же довод и то же устройство, что у
    # `view_show_granted?` выше: это свойство ПРОСМОТРА, а не билда, и ссылка
    # на билд не должна менять смысл от того, что читатель что-то спрятал.
    #
    # ⚠️ Независимо от `view_show_granted?` (○ выдано классом) — тот
    # переключатель отвечает на другой вопрос («показать то, что я не
    # выбирал») и не тронут этой задачей.
    |> assign(:view_filters, %{
      feats: true,
      increase: true,
      skills: true,
      spells: true,
      domains: true
    })
    # Читается один раз в ассайн, а не вызовом из шаблона в двух местах:
    # шаблон спрашивает про порядок дважды (гид до итогов или после), и два
    # независимых чтения конфига — это две возможности разойтись.
    |> assign(:guide_first?, BuildCalculatorWeb.Layouts.guide_first?())
  end

  # Пять ключей `view_filters`, ЗАКРЫТЫЙ список — единственное место, где он
  # назван буквально, и `handle_event/3` ниже спрашивает именно этот список
  # в guard'е, а не строит атом из произвольной строки клиента.
  @view_filter_keys ~w(feats increase skills spells domains)

  @doc """
  Гид по прокачке: по строке на уровень персонажа, в две колонки.

  ⚠️ **Отдельный компонент ровно потому, что его позиция — флаг.** Гид стоит либо
  первой секцией (`Layouts.guide_first?/0`, решение Dan 10.08.2026, §3.24), либо,
  если Dan скажет «нет», последней — как было. Две копии этой разметки разъехались
  бы на первой же правке, поэтому копия одна, а `:if` выбирает место.

  Порядок внутри строки — **сначала решения, потом выданное**. Выбор (`✦` фит,
  `▲` характеристика, `▪` навык, круг заклинания, `◆` выбор класса) отвечает
  на вопрос, с которым игрок пришёл; выданное классом (`○`) он изменить не может,
  и до 10.08.2026 оно стояло вторым и вытесняло выбор — на 1-м уровне пять строк
  выдачи против двух строк выбора (дефект 2 постановки §3.24).

  ⚠️ **`○` собран в ОДНУ строку, а не в столбик по строке на фит** — но имена
  остались все, и каждое со своим DOM-id. Счётчик вместо имён («○ 5 от класса»)
  здесь запрещён: ровно такую плашку убрали с карточки класса 02.08.2026 за то,
  что она называет количество и не называет ни одного имени.

  ## Цвет класса — полосой по краю строки, а не заливкой

  Решение Dan 10.08.2026: «может нам раскрасить строки таблицы в цвет класса?
  Сейчас однотонно». Механизм тот же, что у полос лестницы конструктора —
  `hsl(var(--h) var(--cls-s) var(--cls-l))` с оттенком из `Palette.hue/1`,
  поэтому обе темы работают сами, а престиж-класс приглушается через
  `data-class-prc` (CLAUDE.md §6). ⚠️ Имя атрибута СВОЁ, не общее `data-prc`:
  общее подменило бы `--cls-s`/`--cls-l` всему поддереву строки, включая
  оттенки характеристик, — разбор у самого правила в `app.css`.

  ⚠️ **Именно полоса по краю и тонированное имя, а НЕ заливка строки** — и это
  ограничение, а не вкус. Внутри строки цвет уже несёт смысл: янтарь `--todo`
  («фит не выбран»), стальной `--todo-abil` («стат не выбран») и шесть
  оттенков характеристик (`STR` 4°, `CON` 30°, `DEX` 130°, `INT` 215°,
  `WIS` 275°, `CHA` 325°). Тёплая заливка под тёплым `▲ STR 23` погасила бы
  оба, а полоса живёт в собственном жёлобе строки и ни с чем не соседствует.

  Выигрыш больше, чем «не однотонно»: имя класса печатается только там, где
  прогон начинается (у референсного билда Dan это 6 строк из 40), а полоса
  стоит на каждой — то есть на вопрос «каким классом я беру 34-й уровень»
  гид отвечает **не прокручивая наверх**, и прогоны читаются формой, как
  в лестнице конструктора.
  """
  attr :columns, :list, required: true, doc: "две колонки строк из `Summary.guide_columns/2`"

  attr :wasted?, :boolean,
    required: true,
    doc: "есть ли в билде фит, взятый слотом, который класс отдал бы даром — от него легенда"

  attr :show_granted?, :boolean,
    required: true,
    doc:
      "переключатель `○` (задача 3.147) — печатать ли фиты, которые класс выдаёт сам, и в самом гиде, и в легенде"

  attr :has_granted?, :boolean,
    required: true,
    doc:
      "есть ли в билде хоть один автоматический фит — гейтит сам переключатель, чтобы не показывать бесполезный контрол (та же осторожность, что у ванильной ветки диалога экспорта, 3.146)"

  attr :filters, :map,
    required: true,
    doc:
      "задача 3.175 — пять переключателей «что показывать» (`feats`/`increase`/`skills`/`spells`/`domains`), см. `view_filters` в `prepare/2`"

  def guide_section(assigns) do
    ~H"""
    <section class="v-sect" id="view-guide">
      <span class="eyebrow">Гид по прокачке</span>
      <%!-- Задача 3.175: чекбоксы — ДО легенды, а не внутри неё. Легенда
            отвечает «что значит этот глиф», фильтры — «что показывать»,
            и это два разных вопроса на одном экране; смешать их в одну
            строку значило бы сделать легенду ещё и органом управления,
            которым она не была ни разу за всю историю экрана.
            `id` на каждом чекбоксе и лейбле — по образцу `#view-granted-*`
            (3.147), а не общий класс без адреса: тесты и будущие правки
            обращаются к конкретному переключателю, а не «к любому».

            ⚠️ Задача 3.178 (Dan, скриншот: «5 новых чекбоксов и еще один
            чекбокс старый отбился от стаи… по логике он должен быть вместе
            с новыми»): `#view-granted-toggle` переехал сюда ИЗ `.v-legend`,
            вторым по счёту. Он такой же ответ на «что показывать», как
            остальные пять, и Dan подтвердил это прямо: «"Фиты" показывают
            только фиты, которые выбирает игрок, а "фиты, выданные классом"
            показывает все пассивные фиты, которые не надо брать» — то есть
            два РАЗНЫХ разряда контента, а не родитель и ребёнок. Отсюда
            никакого `disabled`, вложенности или отступа у шестого — он
            ровно такой же `.v-filter`, как соседи.

            ⚠️ Подпись шестого — «Выданные классом», задача 3.178, решение
            designer'а по прямому делегированию Dan («сам тут не уверен,
            пускай дизайнер поразмыслит»), а НЕ «Показывать фиты, выданные
            классом» как раньше: глагол был уместен у одинокого контрола
            и в ряду существительных-подписей выбивался. Само «Фиты» рядом
            намеренно НЕ переименовано в «Выбранные фиты» — источник
            неоднозначности не в имени, а в его одиночестве, и пара решает
            его проксимити: «Фиты» / «Выданные классом» друг за другом —
            то же самое сообщение, что и «Выбранные фиты» / «Выданные
            классом», но без второй половины сообщения дороже первой.
            Проксимити не рвётся и при переносе строк на узкой ширине:
            оба лейбла ИДУТ ПОДРЯД в DOM (соседний узел, не через один),
            значит и скринридер, линеаризующий поток, слышит их одной
            парой независимо от того, легли они визуально на одну строку
            или на разные.
            ⚠️ Переименование пробовалось и БЫЛО ОТКАЧЕНО измерением:
            «Выбранные фиты» (111px) вместо «Фиты» (48px) при том же
            121px-виджете сдвигают сумму первых двух лейблов с 169px до
            232px — а бюджет ряда на 620px ровно 592 минус хвост
            из четырёх фиксированных подписей (407px) даёт 185px. 169 ≤ 185
            (умещается в одну строку, высота ряда не растёт), 232 > 185
            (ряд ломается на вторую строку, +23px к высоте шапки — замер
            `tools/ui_probe`, отчёт задачи). Голое «Фиты» стоит здесь не
            по умолчанию, а по числу. --%>
      <div class="v-filters" id="view-guide-filters">
        <label class="v-filter" id="view-filter-feats-toggle">
          <input
            type="checkbox"
            id="view-filter-feats-checkbox"
            checked={@filters.feats}
            phx-click="toggle_view_filter"
            phx-value-filter="feats"
          /> Фиты
        </label>
        <%!-- Задача 3.178: `phx-click` на самом `<input>`, не на `<label>` —
              тот же приём, что у пяти соседей и у `#export-granted-toggle`
              (3.146): клик по подписи иначе бьёт дважды, браузер сам
              генерирует второй `click` на инпуте.
              `:if={@has_granted?}` не тронут переносом — контрол,
              которому нечего переключать, свой сорт путаницы (3.147); без
              него билд без единого автоматического фита получал бы ряд
              из шести пустых слов вместо пяти осмысленных.
              Ни `class="v-filter"`, ни `id="view-filter-*"` — у чекбокса
              своя пара id (`view-granted-toggle`/`view-granted-checkbox`,
              задача 3.147), и её незачем менять: она нигде не завязана на
              префикс `view-filter-`, а тесты уже держат её как есть.

              ⚠️ РЕШЕНИЕ ПРО АСИММЕТРИЮ (задача 3.178, «нельзя схлопнуть
              молча»): визуально этот чекбокс НИЧЕМ не отмечен среди пяти,
              хотя двигает не только гид, но и текст диалога «показать
              текст» (`export_text/1`), а те пять — только сам экран.
              Решение — оставить как есть, без иконки/сноски, по трём
              причинам: (1) это НЕ новая асимметрия, а перевезённая —
              контрол уже двигал оба представления, стоя в легенде, и там
              это было объяснено ничуть не заметнее (никакой пометки
              «влияет на экспорт» не было и там); (2) поведение само по
              себе не сюрприз в плохую сторону — то, что видно в гиде,
              совпадает с тем, что получишь при копировании, это ожидаемая
              согласованность, а не скрытый побочный эффект, который
              был бы обязан быть подписан по CLAUDE.md §6; (3) на `vanilla`
              разницы для экспорта нет вовсе (его текст `○` никогда
              не читал), то есть пометка была бы верна для одного
              ruleset'а и лишней для другого — сама асимметрия
              ruleset-зависима, а метка в разметке — нет. Если экспорт
              обрастёт ЕЩЁ контролами вида «влияет и на текст тоже»,
              стоит завести общий язык для этого разряда (например,
              общий глиф-пометку у всех таких чекбоксов сразу), а не
              точечно у одного — это и есть точка, где вопрос стоит
              переоткрыть. --%>
        <label :if={@has_granted?} class="v-filter" id="view-granted-toggle">
          <input
            type="checkbox"
            id="view-granted-checkbox"
            checked={@show_granted?}
            phx-click="toggle_view_granted"
          /> {gettext("Granted by class")}
        </label>
        <label class="v-filter" id="view-filter-increase-toggle">
          <input
            type="checkbox"
            id="view-filter-increase-checkbox"
            checked={@filters.increase}
            phx-click="toggle_view_filter"
            phx-value-filter="increase"
          /> Характеристики
        </label>
        <label class="v-filter" id="view-filter-skills-toggle">
          <input
            type="checkbox"
            id="view-filter-skills-checkbox"
            checked={@filters.skills}
            phx-click="toggle_view_filter"
            phx-value-filter="skills"
          /> Навыки
        </label>
        <label class="v-filter" id="view-filter-spells-toggle">
          <input
            type="checkbox"
            id="view-filter-spells-checkbox"
            checked={@filters.spells}
            phx-click="toggle_view_filter"
            phx-value-filter="spells"
          /> Заклинания
        </label>
        <label class="v-filter" id="view-filter-domains-toggle">
          <input
            type="checkbox"
            id="view-filter-domains-checkbox"
            checked={@filters.domains}
            phx-click="toggle_view_filter"
            phx-value-filter="domains"
          /> Выбор класса
        </label>
      </div>
      <div class="v-legend" id="view-guide-legend">
        <%!-- Задача 3.175: легенда следует фильтрам — строка про глиф,
              который сейчас нигде не рендерится, хуже отсутствующей строки
              (тот же довод, что уже был у `○`/`show_granted?` ниже,
              распространённый на новые пять переключателей). --%>
        <span :if={@filters.feats}><i aria-hidden="true">✦</i> фит выбран</span>
        <%!-- ⚠️ `★` доехал до гида 10.08.2026 вместе со снятием переписи фитов:
              до этого гид печатал `✦` любому фиту, а эпический отличался
              звёздочкой ТОЛЬКО в переписи — то есть вместе с ней эта
              разница исчезла бы с экрана вовсе. --%>
        <span :if={@filters.feats}><i aria-hidden="true">★</i> эпический фит</span>
        <%!-- Задача 3.176: `⚔` — третий пункт алфавита §6 (`✦` общий,
              `★` эпический, `⚔` бонусный), а не второй такой же `✦`. До
              этой правки гид красил глиф ПО ФИТУ (`ruleset.feats[id].epic?`)
              и не различал бонусный слот от общего вовсе — конструктор же
              всегда решал по СЛОТУ (`Labels.slot_glyph/1`), поэтому один
              и тот же `Power attack` во взятом Fighter'ом бонусном слоте
              показывал `✦` здесь и `⚔` в цвете класса на лестнице. Легенда
              обязана назвать глиф раньше, чем он появится на строке —
              условие то же, что у `★` выше. --%>
        <span :if={@filters.feats}><i aria-hidden="true">⚔︎</i> бонусный фит класса</span>
        <%!-- Задача 3.147: легенда молчит про `○`, когда переключатель его
              прячет — «легенда, называющая отсутствующее, хуже отсутствующей
              легенды» (тот же довод, что у `Export.guide_legend/1`, 3.146). --%>
        <span :if={@show_granted?}><i aria-hidden="true">○</i> фит выдан классом</span>
        <%!-- Та же пара из двух глифов, что и в легенде списка фитов ниже
              (`view-feats-legend`, задача 3.175) — один и тот же факт, один
              и тот же символ, просто другой блок. `@feat_list` и гид смотрят
              на один и тот же `build.feats` (гид флаттенится в список, а не
              считается заново), поэтому условие «есть ли вообще впустую
              потраченные» верно для обоих (HANDOFF §A.3, §B.1, решение Дана
              02.08.2026). Гейт — ещё и `@filters.feats`: без него виден
              комбинированный глиф от фита, самой строки которого на экране
              уже нет. --%>
        <span :if={@wasted? and @filters.feats}>
          <i aria-hidden="true">✦</i><i aria-hidden="true">○</i>
          взят слотом, но и так вышел бы даром — подписано под строкой
        </span>
        <span :if={@filters.increase} data-abil="1"><i aria-hidden="true">▲</i> +1 к характеристике</span>
        <span :if={@filters.skills} data-skill="1"><i aria-hidden="true">▪</i> навык</span>
        <span :if={@filters.spells}><span class="circle-badge">N</span> круг заклинания</span>
        <%!-- ⚠️ Найдено попутно задачей 3.170 (волшебник-универсал): `◆`
              рендерится в строке гида с задачи 3.14 (домены клирика) и
              назван в её же вокабуляре решений («✦ фит, ▲ характеристика,
              ▪ навык, круг заклинания, ◆ выбор класса» — этот же moduledoc,
              выше) — но в ЭТУ легенду не попал никогда, хотя у экспорта
              (`Export.guide_legend/1`) он есть с той же задачи. До 3.170
              носитель был один-единственный (клирик) и редкий; теперь его
              несёт КАЖДЫЙ волшебник, включая того, кто остался
              универсалистом, и непояснённый глиф на самой частой строке
              гида — то самое «разгадывать глиф» (CLAUDE.md §6), которое
              легенда и обязана снимать. --%>
        <span :if={@filters.domains}><i aria-hidden="true">◆</i> выбор класса</span>
        <span data-none="1"><i aria-hidden="true">—</i> выбирать нечего</span>
      </div>
      <div class="v-guide">
        <div :for={{column, index} <- Enum.with_index(@columns)} id={"view-guide-#{index}"}>
          <%!-- `style` — тот же способ покрасить, что у полос лестницы
                конструктора: оттенок приезжает переменной `--h`, насыщенность
                и светлоту выбирает тема. Ни одной краски в разметке.

                ⚠️ Атрибут называется `data-class-prc`, а НЕ общим `data-prc`,
                и это не описка: глобальное правило `[data-prc="1"]` подменяет
                `--cls-s`/`--cls-l` всему поддереву, а внутри строки на той же
                машинерии живут шесть оттенков характеристик — `▲ STR 24` на
                уровне престиж-класса выцветал бы, а на уровне базового нет
                (замер это и показал, подробности у правила в app.css). --%>
          <div
            :for={row <- column}
            class="v-g"
            id={"view-guide-level-#{row.level}"}
            data-run={if row.run_start?, do: "1"}
            data-illegal={if row.issues != [], do: "1"}
            data-empty={if nothing_to_choose?(row, @filters), do: "1"}
            data-class-prc={row.prc}
            style={Palette.style(row.hue)}
          >
            <%!-- Номер уровня — ссылка на самого себя, и это весь механизм
                  «мой следующий уровень» (вариант 2 постановки §3.24) без
                  единого байта состояния: тап ставит `#view-guide-level-24`
                  в адрес, `:target` подсвечивает строку, ссылка становится
                  шарибельной вместе с уровнем. Экран остаётся без состояния,
                  и вопроса «а почему тут 24-й, я 30-й» не возникает —
                  уровень выбрал сам читатель.

                  ⚠️ `v-lv`, а не `lv`: короткий `.lv` — строка колонки
                  прогрессии КОНСТРУКТОРА (`display: block; width: 100%;
                  padding: 5px 12px 7px 15px`), и правило доставало сюда
                  по-настоящему — номер уровня был 28px высотой, поэтому все
                  40 строк упирались в 38px независимо от содержимого. --%>
            <a
              class="v-lv"
              href={"#view-guide-level-#{row.level}"}
              aria-label={"Уровень #{row.level}"}
            >
              {String.pad_leading(to_string(row.level), 2, "0")}
            </a>
            <span class="cls" title={row.class_name}>{row.short}</span>
            <span class="picks">
              <%!-- ○ рядом с ✦ — слот потрачен, а класс всё равно отдал бы этот
                    фит даром позже (та же пометка, что в колонке прогрессии
                    конструктора, HANDOFF §A.3/§B.1).

                    ⚠️ Полное предложение теперь ЗДЕСЬ, второй строкой. Раньше
                    его печатала перепись фитов, а гид держал одну пару глифов
                    и ссылался на неё; переписи с 10.08.2026 нет («перепись
                    фитов можно удалить, будем их в гиде смотреть», Dan), и
                    вместе с ней исчезло бы единственное место, где сказано, ЧТО
                    именно не так — то есть остался бы ребус из двух значков.
                    Правило экрана просмотра это запрещает прямо (CLAUDE.md §6).
                    Строк это стоит ровно столько, сколько в билде впустую
                    потраченных слотов, — обычно нуль.

                    ⚠️ Задача 3.176: `data-bonus` красит ТОЛЬКО глиф (app.css,
                    `.v-g .pick[data-bonus="1"] i`), не всю строку — решение,
                    а не недосмотр. Строка уже несёт цвет класса своей ЛЕВОЙ
                    полосой (`.v-g` выше, `data-class-prc`), и это отвечает
                    на «чей это уровень»; глиф отвечает на другой вопрос —
                    «из какого пула этот пик» — и красится ТЕМ ЖЕ приёмом,
                    что уже красит `▲` прибавки характеристики двумя пикселями
                    ниже (`--cls-l-text`, не полосовая `--cls-l`, задача 3.155),
                    а не заливкой всей строки, которая спорила бы с янтарём
                    «не выбрано» и с шестью оттенками характеристик внутри
                    той же строки (тот же довод, каким полоса `.v-g`
                    объясняет себе выбор «полоса, а не заливка»). Ровно то же
                    решение, что уже стоит в конструкторе
                    (`.lv-feat[data-bonus="1"] i`, а не `.lv-feat[data-bonus="1"]`
                    целиком) — повторено, а не изобретено заново. --%>
              <span
                :for={{feat, index} <- Enum.with_index(row.feats)}
                :if={@filters.feats}
                class="pick"
                data-bonus={if feat.kind == :class_bonus, do: "1"}
                data-wasted={if feat.wasted_text, do: "1"}
              >
                <i aria-hidden="true">{feat.glyph}</i>
                <i :if={feat.wasted_text} aria-hidden="true">○</i>
                <span>{feat.name}</span>
                <%!-- Задача 3.94: тот же триггер, что у конструктора
                      (`BuilderComponents.feat_info/1`), и та же охрана —
                      `description` пуст только у 11 сиальских фитов владения
                      оружием без страницы на Fandom, и строка тогда просто не
                      несёт кружка. `index`, а не `feat.id`, потому что один
                      уровень МОЖЕТ выбрать один и тот же повторяемый фит
                      дважды из двух разных слотов (`Spell focus` с двух
                      разных школ на одном уровне) — id тогда не уникален
                      внутри строки, а `index` уникален всегда. --%>
                <.feat_info
                  :if={feat.info.description}
                  id={"info-view-guide-level-#{row.level}-feat-#{index}-#{feat.id}"}
                  name={feat.name}
                  description={feat.info.description}
                  siala_changed?={feat.info.siala_changed?}
                  siala_notes={feat.info.siala_notes}
                  siala_notes_more_text={feat.info.siala_notes_more_text}
                  source_url={feat.info.source_url}
                  source_link_text={feat.info.source_link_text}
                />
                <span :if={feat.wasted_text} class="v-g-note">{feat.wasted_text}</span>
              </span>
              <span
                :if={row.increase && @filters.increase}
                class="pick"
                data-abil="1"
                style={Palette.style(row.increase.hue)}
              >
                <i aria-hidden="true">▲</i>
                <span>{row.increase.label}</span>
              </span>
              <span :for={skill <- row.skills} :if={@filters.skills} class="pick" data-skill="1">
                <i aria-hidden="true">▪</i>
                <span>{skill.name}</span>
                <span class="n">+{skill.ranks}→{skill.total}</span>
              </span>
              <span :for={spell <- row.spells} :if={@filters.spells} class="pick" data-spell="1">
                <span class="circle-badge" title={"Круг #{spell.circle}"}>{spell.circle}</span>
                <span>{spell.name}</span>
              </span>
              <%!-- Выбор класса (домены клирика, задача 3.14) — тот же
                    глиф-заглушка `◆`, что в конструкторе (пометка про
                    временность там же, в CSS). --%>
              <span
                :if={row.domains && @filters.domains}
                class="pick"
                data-domain="1"
                id={"view-guide-level-#{row.level}-domains"}
              >
                <i aria-hidden="true">◆</i>
                <span>{row.domains.label}: {Enum.join(row.domains.names, ", ")}</span>
              </span>
              <%!-- ○, а не ✦: выданное классом не выбиралось. В лестнице
                    конструктора его нет вовсе, но гид читают целиком как
                    документацию — там оно на месте (CLAUDE.md §6).

                    ⚠️ Здесь стоит ПРИРОСТ владения, а не сырая выдача классового
                    уровня (баг 1.14, `Feats.granted/3`): фит, который персонаж
                    уже получил раньше, второй раз не приходит, а ступень того же
                    класса — приходит.

                    ⚠️ Одна строка на все выданные, а не строка на каждый: имена
                    целы и у каждого свой DOM-id, но глиф и перевод строки — один.
                    Глиф при этом НЕ гасится, гасится текст: погасить оба значило
                    бы оставить `○` и `▪` различимыми только формой значка
                    (CLAUDE.md §6).

                    ⚠️ Задача 3.147: `@show_granted?` — переключатель, по
                    умолчанию скрыт (решение Dan). --%>
              <span :if={@show_granted? and row.granted != []} class="pick" data-granted="1">
                <i aria-hidden="true">○</i>
                <%!-- ⚠️ Запятая — В РАЗМЕТКЕ, а не `::after` в CSS. Сначала было
                      через CSS (разметка чище), но тогда строка не копируется:
                      в буфер уезжает «Deflect arrowsWholeness of body». Гид
                      держат открытым рядом с игрой и из него копируют, так что
                      запятая обязана быть текстом.
                      ⚠️ Имя и теги на ОДНОЙ строке, без переносов внутри span:
                      иначе HEEx оставляет пробел перед запятой — «Increased
                      multiplier , Superior weapon focus».
                      ⚠️ Задача 3.94: описание идёт ОДНИМ триггером на всю
                      строку, а не по одному на имя, и это измеренное, а не
                      вкусовое решение (`BuilderComponents.feats_info/1`).
                      Триггер на каждое имя реально ломает высоту: даже 1px
                      лишней ширины на ОДНОМ внутреннем имени сдвигает жадный
                      перенос всей строки на лишнюю визуальную линию на
                      конкретных ширинах (замерено CDP 25.08.2026 — пятёрка
                      выдачи Fighter 1 растит строку на 420–440/768–800/1000px
                      именно так). ⚠️ И ОДНОГО хвостового триггера обычного
                      размера тоже не хватает — на 768px хватало и 1px лишней
                      ширины в конце строки, чтобы повторить тот же перенос
                      без единого соседнего имени. Поэтому у самого триггера
                      (`feat-info-trailing`, app.css) СОБСТВЕННЫЙ бокс нулевой
                      ширины — разбор и цифры там же. Триггер стоит СРАЗУ
                      после закрывающего `</span>` последнего имени, без
                      переноса, той же причине, что и выше: перенос вклеил бы
                      пробел. --%>
                <span class="v-g-granted"><span
                  :for={{feat, index} <- Enum.with_index(row.granted)}
                  id={"view-guide-level-#{row.level}-granted-#{feat.id}"}
                >{if index > 0, do: ", "}{feat.name}</span><.feats_info
                  :if={row.granted_info != []}
                  id={"info-view-guide-level-#{row.level}-granted"}
                  label={gettext("What this level's feats give")}
                  entries={row.granted_info}
                /></span>
              </span>
              <%!-- Прочерк — видимый ответ «на этом уровне ничего не надо», а не
                    пустое место: строка без правой половины читается как сбой
                    вёрстки. Ради него строка и остаётся на месте: перебежку
                    «05–07» вместо трёх строк искать по номеру уже нельзя, а
                    именно так гид и читают.

                    ⚠️ Условие — «нет вообще ничего», а не «нечего выбирать»:
                    у строки, где класс что-то выдал, содержимое есть, и прочерк
                    под ним был бы лишней строкой (5 таких у референсного билда
                    Dan) при том, что глиф `○` и приглушённый текст и так
                    говорят «это не твой выбор».

                    ⚠️ Задача 3.147: с переключателем это верно, только пока
                    `○` виден. Скрыт — и уровень, чьё ЕДИНСТВЕННОЕ содержимое
                    было выдачей, показывает пустую правую половину без
                    прочерка, то есть тот самый «сбой вёрстки», от которого
                    прочерк и придуман. `nothing_at_all?/2` поэтому читает
                    переключатель, а не только `row.granted` само по себе —
                    в отличие от `Export.granted_item/2` (3.146), которому
                    заполнитель не нужен: пустой хвост текстовой строки
                    «02: Monk(2):» — не сбой, это ровно то, как `vanilla`
                    печатает любой пустой уровень всегда.

                    ⚠️ Задача 3.175: тот же довод, распространённый на пять
                    новых фильтров — уровень, чьё содержимое ЦЕЛИКОМ спрятано
                    фильтрами (например, только фиты, а «Фиты» выключены),
                    для читателя неотличим от уровня, где выбирать было
                    нечего, и заслуживает того же прочерка, а не пустой
                    правой половины. --%>
              <span :if={nothing_at_all?(row, @filters, @show_granted?)} class="v-g-none">—</span>
              <%!-- Задача 1.3: этот уровень (или фит, взятый на нём) не
                    выдерживает проверку по билду, как он выглядит прямо сейчас —
                    обычно след правки более раннего решения. Привязана
                    к КОНКРЕТНОМУ уровню, а не только к сводке выше: гид — то
                    самое место, куда смотрят, чтобы понять, ГДЕ чинить.
                    Видимый текст, а не только `title` — правило экрана
                    просмотра, глиф без подписи не работает (CLAUDE.md §6). --%>
              <span
                :if={row.issues != []}
                class="v-g-issue"
                id={"view-guide-level-#{row.level}-issue"}
              >
                <i aria-hidden="true">⚠</i><span>{Enum.join(row.issues, "; ")}</span>
              </span>
            </span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  # «Выбирать нечего» — это про ВЫБОР, а не про пустую строку: уровень, на
  # котором класс что-то выдал сам, для игрока на левелапе так же пуст, как
  # уровень, где не случилось вообще ничего. У референсного билда Dan таких
  # 16 из 40 (11 совсем пустых плюс 5 с одной выдачей) — то есть 40% строк,
  # и именно они и есть цена гида, а не кегль.
  #
  # ⚠️ `issues` в счёт не идут: нарушение правил — не выбор, но и не «нечего
  # смотреть», а ровно наоборот, самое важное на строке.
  #
  # ⚠️ Задача 3.175: `filters` — второй аргумент, не факт про билд, тем же
  # устройством, что `show_granted?` у `nothing_at_all?/3` ниже. «Нечего
  # выбирать» теперь читается ОТНОСИТЕЛЬНО текущих фильтров: уровень,
  # у которого есть только фиты, при выключенном фильтре «Фиты» обязан
  # выглядеть и вести себя так же, как уровень, где фитов не было вовсе, —
  # иначе прочерк и утончение строки (`data-empty`) не поспевали бы за тем,
  # что реально видно на экране.
  defp nothing_to_choose?(row, filters) do
    (row.feats == [] or not filters.feats) and
      (row.skills == [] or not filters.skills) and
      (row.spells == [] or not filters.spells) and
      (is_nil(row.increase) or not filters.increase) and
      (is_nil(row.domains) or not filters.domains) and
      row.issues == []
  end

  # Строка, на которой нет вообще ничего — ни выбора, ни выдачи. Только у такой
  # печатается прочерк: он отвечает «ничего не надо», а не «твоего тут нет».
  # У референсного билда Dan таких 11 из 40, ещё 5 несут одну выдачу.
  #
  # ⚠️ Задача 3.147: `show_granted?` — второй … ныне третий (3.175) аргумент,
  # не факт про билд. Скрытый переключатель делает выдачу невидимой, а не
  # отменяет её, и строка с одной лишь выдачей обязана получить прочерк
  # ровно тогда, когда эта выдача с экрана не видна — иначе правая половина
  # строки пустая без какого-либо объяснения, тот самый «сбой вёрстки», ради
  # которого прочерк и придуман (комментарий у самого `<span>` выше).
  defp nothing_at_all?(row, filters, show_granted?) do
    nothing_to_choose?(row, filters) and (row.granted == [] or not show_granted?)
  end

  defp open(socket, code) do
    case Encoding.decode(code) do
      {:ok, %{ruleset: ruleset, build: build, dropped: dropped}} ->
        socket |> warn_dropped(dropped) |> load(ruleset, build)

      {:error, reason} ->
        assign(socket, :error, Labels.decode_error(reason))
    end
  end

  defp warn_dropped(socket, []), do: socket

  defp warn_dropped(socket, dropped) do
    put_flash(socket, :info, "Из ссылки выпало: " <> Labels.dropped(dropped))
  end

  defp load(socket, ruleset, %Build{} = build) do
    stats = Rules.compute(build, ruleset)
    later_by_level = later_by_level(ruleset, build)

    # Задача 1.3 (продолжение): та же прогонка лестницы, что уже стоит в
    # конструкторе (`BuilderLive.ladder_issues/2`), теперь и здесь — билд,
    # открытый по ссылке, обязан говорить о нарушении так же честно, как
    # конструктор, а не молчать до тех пор, пока его не вставят в импорт.
    # Общий код для обоих входов лежит в `Labels.ladder_issues/2`.
    issues_by_level = Labels.ladder_issues(ruleset, build)
    guide_columns = annotated_guide_columns(ruleset, build, later_by_level, issues_by_level)

    socket =
      socket
      |> assign(:ruleset, ruleset)
      |> assign(:build, build)
      |> assign(:stats, stats)
      |> assign(:character_level, Build.character_level(build))
      |> assign(:title, Summary.title(ruleset, build, stats))
      |> assign(:stat_cards, Summary.stat_cards(ruleset, stats))
      # Правило «уровни после 20-го в BAB и сейвы не идут» — одной строкой под
      # сеткой итогов и только у билдов, которых оно касается (задача 3.16).
      # Разбор в карточке BAB называет, у кого уровни отброшены; строка называет
      # правило, и этот экран существует ровно для того, чтобы правило назвать:
      # пришедший по ссылке не знает, почему у 40-уровневого мага 2 атаки.
      |> assign(:counted_window_note, Summary.counted_window_note(stats))
      # Справка к ПОСЧИТАННОМУ расовому бонусу (задача 3.102, решение Dan
      # 25.08.2026) — той же строкой под сеткой итогов, что и правило окна
      # выше, и по той же причине: пришедший по ссылке не знает, почему
      # у Светлого эльфа-сагровика AB на 9 больше, чем складывается из BAB
      # и характеристики. У Человека адрес другой — значение навыка, — и
      # строка тогда стоит в секции навыков; решает это ядро через
      # `Summary.racial_bonus_note/2`, а не разметка.
      |> assign(:racial_bonus_note, Summary.racial_bonus_note(ruleset, stats))
      # Сагровик / адровец — тот же флажок, что в панели итогов конструктора
      # (запрос Dan 08.08.2026), и на этом экране он нужен даже больше: пришедший
      # по ссылке не знает состава билда наизусть, а группа объясняет, почему
      # расовый бонус в разборе AB больше базового.
      |> assign(:class_group_flags, Summary.class_group_flags(ruleset, stats))
      |> assign(:ability_rows, Summary.ability_view_rows(ruleset, build))
      |> assign(:skill_rows, Summary.skill_rows(ruleset, build, stats))
      |> assign(:guide_columns, guide_columns)
      # Считается по строкам ГИДА, а не по переписи фитов: перепись убрана
      # 10.08.2026 («перепись фитов можно удалить, будем их в гиде смотреть»,
      # Dan), а легенда про пару `✦○` обязана появляться ровно тогда, когда в гиде
      # есть что ею объяснять. Один источник факта, а не два — иначе легенда и
      # строка разъезжаются, и это уже случалось на этом экране (подпись AB).
      |> assign(:wasted?, Enum.any?(guide_columns, &wasted_column?/1))
      # Задача 3.147 — гейтит сам переключатель `○`: билд, где ни один взятый
      # уровень ничего не выдал, не должен показывать контрол, которому нечего
      # переключать (в реальных билдах это практически недостижимо — все 23
      # класса обоих ruleset'ов выдают что-то на своём 1-м уровне, — но чтение
      # осталось честным на пустом краю, а не «всегда true»).
      |> assign(:has_granted?, Enum.any?(guide_columns, &granted_column?/1))
      # Задача 3.175: «просто список берущихся фитов внизу файла» — Dan,
      # 03.09.2026, отдельно от чекбоксов («в целом чекбоксы решат данную
      # проблему, но раз попросили можно и отдельно список фитов добавить»).
      # Флаттенится из уже АННОТИРОВАННЫХ строк гида, а не считается заново:
      # `id`/`name`/`info`/`wasted_text`/`glyph` там уже есть, и та же
      # идентичность фита, что видит гид, видит и этот список — им нельзя
      # разойтись (CLAUDE.md §9 про две копии одного правила).
      |> assign(:feat_list, feat_list(guide_columns))
      |> assign(:gaps, Gaps.summary(ruleset, build, stats))
      # Задача 3.148 (Dan, 31.08.2026: «предупреждение убрать, вместо него
      # рекомендацию экипировать персонажа»): гейт для `#view-gear-hint`,
      # той же формы, что уже решает, показывать ли каскад «Из этого
      # следует» в конструкторе (`Gear.any?/1`'s own moduledoc) — «билд
      # ничего не сказал про вещи», а не «числа неполные». Единственный
      # читатель — сам этот флаг; ни один посчитанный стат от него не зависит.
      |> assign(:gear_entered?, Gear.any?(build.gear))
      # `@illegal_levels` — сортированный по уровню список `{level, [текст, …]}`
      # для постоянного блока честности; `@illegal_count` — для его заголовка
      # и для того, чтобы `.heex` мог решить, показывать ли блок вообще
      # (`Enum.sort/1` на списке пар `{level, texts}` сортирует по уровню —
      # это первый элемент кортежа, второго ни разу не касается).
      |> assign(:illegal_levels, Enum.sort(issues_by_level))
      |> assign(:illegal_count, map_size(issues_by_level))

    assign(socket, :export_text, export_text(socket))
  end

  # Один индекс «что выдастся позже» на весь билд, а не на каждого читателя
  # по отдельности: `Feats.free_later/3` за уровень — это проход по хвосту
  # билда, а спрашивают про него все фиты уровня сразу.
  defp later_by_level(ruleset, build) do
    for level <- 1..max(Build.character_level(build), 0)//1, into: %{} do
      {level, Feats.free_later(ruleset, build, level)}
    end
  end

  # Есть ли в колонке гида хоть один фит с подписью «и так вышел бы даром».
  defp wasted_column?(column) do
    Enum.any?(column, fn row -> Enum.any?(row.feats, & &1.wasted_text) end)
  end

  # Есть ли в колонке гида хоть один автоматический (`○`) фит — задача 3.147,
  # тот же приём, что у `wasted_column?/1` рядом.
  defp granted_column?(column), do: Enum.any?(column, fn row -> row.granted != [] end)

  # Плоский список ВЗЯТЫХ фитов всего билда, для секции `#view-feats`
  # (задача 3.175). Только `row.feats` (то, что выбрал слот), НЕ `row.granted`
  # (то, что дал класс) — Dan сказал «берущихся», а не «все», и смешивать их
  # в одно число уже было отвергнутым решением: счётчик «Фиты — 38» старой
  # переписи (снятой 10.08.2026) складывал оба источника и не отвечал ни
  # на «что получу», ни на «что решать» (CLAUDE.md §6). Выданное классом
  # по-прежнему смотрят через `○`-переключатель гида, у которого свой смысл.
  #
  # `level`/`index` кладутся рядом с уже готовым `feat` — тот же приём, что
  # у `.feat_info`'s DOM-id внутри `guide_section/1`: `index`, а не `feat.id`,
  # потому что один уровень может выбрать один и тот же повторяемый фит
  # дважды из двух разных слотов (`Spell focus` с двух школ на одном уровне).
  defp feat_list(guide_columns) do
    for column <- guide_columns,
        row <- column,
        {feat, index} <- Enum.with_index(row.feats) do
      Map.merge(feat, %{level: row.level, index: index})
    end
  end

  # Один читатель `assigns.view_show_granted?` (CLAUDE.md §9: две копии одного
  # правила расходятся) — mount-time `load/3` и `handle_event("toggle_view_granted", …)`
  # оба зовут это, а не собирают вызов `Export.text/4` каждый по-своему. Тот же
  # приём, что у `BuilderLive`'s `export_text/1` (задача 3.146).
  defp export_text(socket) do
    Export.text(socket.assigns.build, socket.assigns.ruleset, socket.assigns.stats,
      title: socket.assigns.title,
      show_granted_feats: socket.assigns.view_show_granted?
    )
  end

  # Волна 6 (HANDOFF §B.1): `Summary.guide_feats/3` несёт `id` рядом с готовым
  # именем, и это ровно то, чего не хватало волне 5, чтобы довести пометку
  # «слот потрачен зря» до гида — раньше сопоставлять пришлось бы по строке
  # имени. С 10.08.2026 гид — единственное место экрана, где эта пометка есть
  # вовсе (перепись фитов убрана), поэтому она печатается здесь целым
  # предложением, а не парой глифов.
  defp annotated_guide_columns(ruleset, build, later_by_level, issues_by_level) do
    ruleset
    |> Summary.guide_columns(build)
    |> Enum.map(fn column ->
      Enum.map(column, &annotate_guide_row(ruleset, build, &1, later_by_level, issues_by_level))
    end)
  end

  defp annotate_guide_row(ruleset, build, row, later_by_level, issues_by_level) do
    later = Map.get(later_by_level, row.level, %{})

    feats =
      for feat <- row.feats do
        feat
        |> Map.put(:wasted_text, Feats.wasted_text(ruleset, build, later, feat.id))
        # ⚠️ Задача 3.176: было `Labels.feat_glyph(ruleset, feat.id)` — глиф
        # ПО ФИТУ (только эпический/обычный), а конструктор красит глиф ПО
        # СЛОТУ (`Labels.slot_glyph/1`, читает `feat.kind`, поставленный
        # `Summary.guide_feats/3`) и умеет третий случай, `⚔` бонусный.
        # `Labels.slot_glyph/1` — тот же читатель, что уже красит лестницу
        # конструктора (`builder_live.ex`, `Feats.slots/3`), поэтому один
        # и тот же фит на одном уровне не может разойтись глифом между
        # экранами: оба зовут одну функцию на одной и той же карте `%{kind:
        # …}`, просто добытой разными путями (там — из живого слота, здесь —
        # из RAW-ключа `build.feats[level]`, см. `guide_feat_kind/3`).
        |> Map.put(:glyph, Labels.slot_glyph(feat))
      end

    # `:issues` — ключ, которого `Summary.guide_rows/2` не задаёт (та же
    # обёртка-не-правка чужого файла, что и у `wasted_text` выше), поэтому
    # `Map.put/3`, а не `%{row | …}`: структурное обновление упало бы
    # `KeyError` на ключе, которого в исходной карте ещё нет.
    row
    |> Map.put(:feats, feats)
    |> Map.put(:issues, Map.get(issues_by_level, row.level, []))
    # Цвет класса строки — оттенком из таблицы `Palette`, а не hash'ем: две
    # соседние ступени билда обязаны различаться (см. moduledoc `Palette`).
    |> Map.put(:hue, Palette.hue(row.class))
    |> Map.put(:prc, Palette.prc(ruleset, row.class))
    |> Map.put(:granted_info, granted_info_entries(row.granted))
  end

  # `BuilderComponents.feats_info/1`'s `entries` — task 3.94. One combined
  # trigger per level, not one per granted feat: `.v-g-granted` joins every
  # name onto ONE line of text ("Deflect arrows, Wholeness of body"), and a
  # per-name `ⓘ` there measurably grows the row — even a single extra pixel
  # of width on one interior name can push the whole line's greedy word-wrap
  # into an extra line at specific widths (measured live, CDP, 25.08.2026:
  # Fighter's five level-1 grants add one text-line at
  # 420–440px/768–800px/1000px). See `feats_info/1`'s own moduledoc for why
  # a single ordinary-sized trailing trigger is not enough by itself either,
  # and what `feat-info-trailing` (app.css) does instead. `row.feats`
  # (`Summary.guide_feats/3`'s own picks, annotated above) has no such
  # neighbour to share a line with — each pick is its own full-width row —
  # so its per-pick triggers stay as they are.
  defp granted_info_entries(granted) do
    for feat <- granted, feat.info.description, do: Map.put(feat.info, :name, feat.name)
  end

  @impl true
  def handle_event("show_text", _params, socket) do
    {:noreply, assign(socket, :text_open?, true)}
  end

  def handle_event("close_text", _params, socket) do
    {:noreply, assign(socket, :text_open?, false)}
  end

  # Задача 3.147 — ОДИН переключатель на весь экран (checkbox лежит на гиде,
  # `guide_section/1`), а его состояние обязано двигать и гид, и текст
  # диалога «показать текст» в том же ответе — иначе игрок увидит
  # переключившийся чекбокс и прежний текст под ним до следующего события
  # (тот же довод, что у `BuilderLive`'s `"toggle_export_granted"`, 3.146).
  def handle_event("toggle_view_granted", _params, socket) do
    socket = assign(socket, :view_show_granted?, not socket.assigns.view_show_granted?)
    {:noreply, assign(socket, :export_text, export_text(socket))}
  end

  # Задача 3.175 — пять чекбоксов «что показывать» на гиде, один обработчик:
  # `phx-value-filter` называет, какой из пяти щёлкнули, `guard` пускает
  # только эти пять строк, поэтому `String.to_existing_atom/1` безопасен —
  # все пять атомов уже существуют как ключи `view_filters` (задаются
  # литералом в `prepare/2`), новых атомов из чужого ввода тут не родится.
  # Ни экспорта, ни URL это не касается (та же граница, что у
  # `toggle_view_granted` выше, только фильтры не двигают даже текст —
  # `export_text/1` их не читает вовсе).
  def handle_event("toggle_view_filter", %{"filter" => key}, socket)
      when key in @view_filter_keys do
    filters = Map.update!(socket.assigns.view_filters, String.to_existing_atom(key), &(not &1))
    {:noreply, assign(socket, :view_filters, filters)}
  end

  @doc false
  def signed(nil), do: "?"
  def signed(value) when value >= 0, do: "+#{value}"
  def signed(value), do: Integer.to_string(value)

  @doc false
  # ⚠️ Значение навыка — это значение, а не прибавка. Печаталось через `signed/1`,
  # и рядом с рангами выходило «4 (+8)» — то есть «4 ранга и ещё восемь сверху»,
  # хотя 8 и есть весь результат. Знак тут не украшение, а другое утверждение.
  def number(nil), do: "?"
  def number(value), do: Integer.to_string(value)
end
