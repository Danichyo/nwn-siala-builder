defmodule BuildCalculatorWeb.Layouts do
  @moduledoc """
  Layouts.

  `app/1` is deliberately thin: the builder is a full-bleed three column shell
  and owns its own header, so a second chrome around it would only fight it.
  `site_footer/1` is the one exception — CC BY-SA attribution is a property
  of the site, not of any one screen (CLAUDE.md §3 "Лицензии — не забыть"),
  so it is stitched into every page from here rather than repeated per
  template.
  """
  use BuildCalculatorWeb, :html

  embed_templates "layouts/*"

  @doc """
  Показывать ли в интерфейсе вход в аккаунты, «Сохранить» и библиотеку.

  ⚠️ **Спрятан ИНТЕРФЕЙС, а не фича** — решение Dan 10.08.2026 (AGENT_QUEUE §3.23):
  «для запуска нужны только конструктор и просмотр». Роуты `/users/register`,
  `/users/log-in`, `/library`, `/builds/new`, `/builds/:id` **остались живыми** и
  достижимы по прямому адресу. Так сделано намеренно: скрытая кнопка возвращается
  правкой одной строки здесь, а закрытый роут ломает ссылки, которые уже могут
  существовать — `/builds/:id` это шаренный сохранённый билд. Решение Dan названо
  временным, поэтому и способ возврата должен быть в одну строку.

  Шаринг билда от этого не страдает и не должен: длинная ссылка и короткая
  (`/s/<key>`) живут в панели итогов конструктора и аккаунта не требуют.

  Что осталось видимым сознательно: у **вошедшего** пользователя остаются его
  почта, «Выйти» и ссылки на свои билды и группы. Спрятать их значило бы запереть
  человека внутри сессии без выхода — а вошедший про аккаунты и так знает.

  ⚠️ Значение читается из конфига (`config :build_calculator, :accounts_ui`),
  а не стоит константой здесь: типизатор Elixir сворачивает `do: false` в
  `dynamic(false)` и роняет сборку предупреждением о недостижимой ветке `:if`
  во всех шаблонах-потребителях. Побочная выгода важнее обхода: тест может
  включить флаг и убедиться, что кнопки возвращаются, — значит у каждого
  `refute` есть положительный контроль, а не зелёный цвет по опечатке
  в селекторе.
  """
  def accounts_ui?, do: Application.get_env(:build_calculator, :accounts_ui, false)

  @doc """
  Показывать ли в интерфейсе вход в импорт билда из текста.

  ⚠️ **Спрятан ИНТЕРФЕЙС, а не код** — задача 3.89, решение Dan 24.08.2026:
  «спрятать импорт, импортировать билды к нам никто не будет, а вот экспорт
  может пригодиться — сбилдил и сохранил в текстовом виде на всякий случай».
  Экспорт (`#export-button` / `#export-dialog` / `BuildCalculatorWeb.Builder.Export`)
  этим флагом не задет — владелец просил сохранить именно его.

  `BuildCalculatorWeb.Builder.Import` остаётся рабочим модулем: на нём стоит план
  проверки ванильных чисел (`docs/VANILLA_SPLIT.md` §4, §7.4) — прогнать через него
  эталонные билды NWN-комьюнити в каноническом текстовом формате, единственный
  найденный способ сверить BAB/сейвы/HP/скилл-поинты ванильного ruleset'а с
  реальными билдами. Его тесты (`builder/import_test.exs`,
  `rules/illegal_levels_test.exs`) флага не касаются и продолжают идти как шли.

  ⚠️ Значение читается из конфига (`config :build_calculator, :import_ui`),
  а не стоит константой здесь — по тем же двум причинам, что у `accounts_ui?/0`:
  типизатор Elixir сворачивает `do: false` в `dynamic(false)` и роняет сборку
  предупреждением о недостижимой ветке `:if` во всех шаблонах-потребителях,
  а тест умеет включить флаг через `Application.put_env/3` — у `refute`
  появляется положительный контроль, а не просто зелёный цвет по опечатке
  в селекторе.
  """
  def import_ui?, do: Application.get_env(:build_calculator, :import_ui, false)

  @doc """
  Показывать ли в интерфейсе вставку билда из лога команды `.билд`.

  Другой сценарий, чем `import_ui?/0`, и потому свой, отдельный флаг —
  **не** тот же переключатель, спрятанный задачей 3.89. Там Dan прятал
  вставку ЧУЖОГО билда в каноническом текстовом формате («импортировать
  билды к нам никто не будет»); здесь он сам просит вставку СВОЕГО
  персонажа из клиентского лога (задача 3.111, 26.08.2026, заход 2): «давай
  добавим UI куда лог вставлять». Довод, которым закрыт первый сценарий, ко
  второму не относится — путать их флагом значило бы спрятать то, что Dan
  явно просил показать.

  ⚠️ По умолчанию `true`, в отличие от `import_ui?/0` и `accounts_ui?/0`:
  эти два спрятаны решением владельца, а этот — активная фича, которую он
  запросил только что. Флаг всё равно заведён, а не зашита видимость в
  разметку — тот же довод, что у обоих соседей: формат лога видели три
  примера (§9 CLAUDE.md — «на трёх примерах правила не выводить»), и если
  игроки начнут присылать логи, которые парсер читает иначе, откат должен
  стоить одну строку конфига, а не деплой.

  ⚠️ Значение читается из конфига (`config :build_calculator, :game_log_import_ui`),
  а не стоит константой здесь — по тем же двум причинам, что у соседей: типизатор
  Elixir сворачивает `do: true` в `dynamic(true)` и роняет сборку предупреждением
  о недостижимой ветке `:if` во всех шаблонах-потребителях (симметрично тому, что
  случилось бы с `do: false`), а тест умеет выключить флаг через
  `Application.put_env/3` и получить положительный контроль на `refute`.
  """
  def game_log_import_ui?,
    do: Application.get_env(:build_calculator, :game_log_import_ui, true)

  @doc """
  Стоит ли на экране просмотра гид по прокачке ПЕРВЫМ, а итоги после него.

  Решение Dan 10.08.2026 (AGENT_QUEUE §3.24): «когда берешь уровень в игре, надо
  зайти в билд и посмотреть что же надо прокачать… при прокачке итоговые статы
  уже не интересны, они уже известны». У экрана два читателя, и приоритет между
  ними назван — сначала игрок на левелапе, потом согласование билда.

  ⚠️ **Это пересмотр записанного решения.** CLAUDE.md §6 обосновывал прежний
  порядок так: «ничего не выбирается, поэтому вся страница отдана итогам».
  Довод верен, пока итоги — главное на экране; Dan назвал главным другое.
  Оба решения записаны и здесь, и в `config.exs`, чтобы следующий читатель
  не «починил» пересмотренное.

  ⚠️ Флаг переключает **только порядок секций и плотность гида**. Починка
  столкновения `.lv` (короткий класс колонки прогрессии конструктора доставал
  до этого экрана) и разбор итогов списком вместо прозы к нему НЕ привязаны:
  первое — баг, второе — дословная просьба Dan в том же разговоре, и терять их
  вместе с порядком было бы неправильно.

  Значение — из конфига, по тем же двум причинам, что у `accounts_ui?/0`:
  типизатор сворачивает константу в `dynamic(…)` и роняет сборку на недостижимой
  ветке `:if`, а тест умеет выключить флаг и проверить прежний порядок — то есть
  у каждого утверждения про новый порядок есть отрицательный контроль.
  """
  def guide_first?, do: Application.get_env(:build_calculator, :guide_first, true)

  @doc """
  Renders the app layout: the page frame, the footer and the flash group.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="app">
      {render_slot(@inner_block)}
      <.site_footer />
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The CC BY-SA attribution strip, on every page (`app/1` renders it, nothing
  else does). Names the source and the license with links to both, says the
  material was changed, and points at `/sources` for the rest — that quartet
  is what the license actually asks for, no more
  (`BuildCalculatorWeb.SourcesLive` carries the reasoning and the verified
  license text). The second line is the non-affiliation disclaimer Dan asked
  to sit right next to it, not buried a click away.
  """
  def site_footer(assigns) do
    ~H"""
    <footer class="site-footer" id="site-footer">
      <p>
        Игровые данные основаны на материалах
        <.link
          href="https://nwn.fandom.com/"
          target="_blank"
          rel="noopener noreferrer"
          id="footer-fandom-link"
        >
          NWN Wiki (Fandom)
        </.link>
        , переработанных под правила Сиалы, и распространяются по лицензии
        <.link
          href="https://creativecommons.org/licenses/by-sa/3.0/"
          target="_blank"
          rel="license noopener noreferrer"
          id="footer-license-link"
        >
          CC BY-SA 3.0
        </.link>
        — как и наш производный слой правил. Подробнее — страница <.link
          navigate={~p"/sources"}
          id="footer-sources-link"
        >«Источники»</.link>.
      </p>
      <p>
        Проект не связан с BioWare, Beamdog, Wizards of the Coast, Fandom или администрацией шарда.
      </p>
    </footer>
    """
  end

  @doc """
  The site header used by every screen that is not the builder.

  The builder and the read-only view own their own headers (they carry the
  build's own chrome), so this one exists for the library, the groups and the
  account pages. The account block is the same everywhere, which is why it is
  factored out as `account/1` and dropped into those two headers too.
  """
  attr :current_scope, :map, default: nil
  attr :active, :atom, default: nil, doc: "which nav entry to mark: :library | :mine | :groups"

  def site_header(assigns) do
    ~H"""
    <header class="top" id="site-header">
      <div class="brand">
        <span class="eyebrow">Сиала · NWN</span>
        <.link navigate={~p"/"} id="brand-home"><b>Калькулятор билдов</b></.link>
      </div>

      <.nav current_scope={@current_scope} active={@active} />

      <div class="top-right">
        <.theme_toggle />
        <.account current_scope={@current_scope} />
      </div>
    </header>
    """
  end

  @doc """
  Library / my builds / groups links. Signed-out visitors see the public feed only.

  ⚠️ **Вся тройка спрятана флагом `accounts_ui?/0`, включая ссылки вошедшего.**
  Постановка §3.23 называет только «Библиотеку», но «Мои билды» и «Группы» ведут
  в тот же спрятанный раздел — оставить их значило бы спрятать раздел наполовину,
  а половинчатое скрытие хуже отсутствующего: шапка выглядит убранной, а входы
  в неё есть. Сами ленты живы по прямым адресам, и переключатель разделов
  (`#library-sections`) стоит внутри `/library`, так что попавший туда человек
  навигацию не теряет.
  """
  attr :current_scope, :map, default: nil
  attr :active, :atom, default: nil

  def nav(assigns) do
    ~H"""
    <nav class="nav" id="site-nav">
      <.link
        :if={accounts_ui?()}
        navigate={~p"/library"}
        id="nav-library"
        data-on={on(@active == :library)}
      >
        Библиотека
      </.link>
      <.link
        :if={accounts_ui?() && @current_scope && @current_scope.user}
        navigate={~p"/library/mine"}
        id="nav-mine"
        data-on={on(@active == :mine)}
      >
        Мои билды
      </.link>
      <.link
        :if={accounts_ui?() && @current_scope && @current_scope.user}
        navigate={~p"/groups"}
        id="nav-groups"
        data-on={on(@active == :groups)}
      >
        Группы
      </.link>
    </nav>
    """
  end

  @doc """
  Who is signed in, and the way in or out.

  Log out is a `DELETE` form rather than a link: it changes server state, so a
  prefetching browser must not be able to trip it.

  ⚠️ Гостевая половина («Войти» / «Регистрация») спрятана флагом
  `accounts_ui?/0`, и тогда блока в шапке нет вовсе — пустой контейнер занимал бы
  место и ловил бы фокус ни за что. Половина вошедшего остаётся: без неё из
  сессии некуда выйти.
  """
  attr :current_scope, :map, default: nil

  def account(assigns) do
    ~H"""
    <div :if={(@current_scope && @current_scope.user) || accounts_ui?()} class="who" id="account">
      <%= if @current_scope && @current_scope.user do %>
        <.link navigate={~p"/users/settings"} id="account-email">
          <b>{@current_scope.user.email}</b>
        </.link>
        <.link href={~p"/users/log-out"} method="delete" id="log-out" class="btn">Выйти</.link>
      <% else %>
        <.link navigate={~p"/users/log-in"} id="log-in" class="btn">Войти</.link>
        <.link navigate={~p"/users/register"} id="register" class="btn">Регистрация</.link>
      <% end %>
    </div>
    """
  end

  defp on(true), do: "1"
  defp on(_), do: nil

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
      </.flash>
    </div>
    """
  end

  @doc """
  Одна кнопка, переворачивающая тему (решение Dan 10.08.2026, AGENT_QUEUE §3.23).

  Оба режима равноправны (CLAUDE.md §6), поэтому это не «тумблер тёмного режима»,
  а переворот: контрол описывает **вид**, а не предпочтение, и у вида не бывает
  третьего, ненарисованного состояния — `phx:theme` может быть пуст, а
  отрисованная тема пустой быть не может.

  ⚠️ **Дефолт для НОВОГО посетителя — тёмная тема, а не системная** (пересмотр
  10.08.2026 → 02.09.2026, задача 3.165, Dan: «тёмная тема должна быть включена
  по дефолту, только если юзер сам себе поставит светлую мы её сохраняем»).
  Довод «равноправны» абзацем выше остаётся верным для самих ПАЛИТР — ни одна
  не хуже другой по контрасту, плотности, шрифтам; меняется только УМОЛЧАНИЕ.
  Системная тема (`prefers-color-scheme`) при этом не спрашивается вовсе —
  ни при первой отрисовке, ни на лету при смене темы ОС, — поэтому слушателя
  `matchMedia(...).addEventListener("change", …)`, который раньше жил
  в `<head>` и следил за темой ОС, больше нет: с фиксированным дефолтом ему
  нечего было бы делать. Явный выбор («включить светлую» / «включить тёмную»)
  по-прежнему сохраняется в `localStorage` и переживает визит — это вторая
  половина той же просьбы Dan, и её уже обеспечивало решение 3.23.

  ⚠️ **Выбрана одна традиция и держится целиком: иконка и подпись называют
  ДЕЙСТВИЕ, а не текущее состояние.** В светлой теме это луна и «Включить тёмную
  тему», в тёмной — солнце и «Включить светлую». Смешивать традиции («иконка
  текущей темы» + «подпись про действие») запрещено постановкой, и запрет разумный:
  тогда кнопка противоречит сама себе. Довод в пользу действия — довод Dan:
  состояние человек и так видит, это весь экран целиком; у кнопки ровно одна работа.

  ⚠️ **Почему в разметке ДВЕ кнопки, а видна одна.** Тему применяет клиент
  (`root.html.heex` ставит `data-theme` на `<html>` до первой отрисовки), сервер
  о ней не знает вовсе — значит статически он не может выбрать, какое значение
  положить в `data-phx-theme`. Поэтому в DOM лежат оба направления, а показывает
  нужное **чистый CSS** по `:root[data-theme]` (`assets/css/app.css`, `.theme-b`).
  Нулевой JS, никакого мигания, и работает даже до подключения сокета.
  Скринридер видит ровно одну кнопку: скрытая через `display: none` для него
  не существует, поэтому её подпись не мешает — «`aria-label`, меняющийся вместе
  с темой» здесь достигнут подменой самой кнопки.

  ⚠️ **Кнопки «Авто» больше нет, и цена этого принята сознательно** (постановка
  §3.23): `localStorage.removeItem("phx:theme")` вызывала только она, значит
  вернуться к прежнему умолчанию из интерфейса теперь нельзя — первый же клик
  записывает предпочтение навсегда. Пострадавший — только тот, кто нажал тему
  руками и потом передумал; кнопка вернётся вместе с аккаунтами. Скрытый жест
  («повторный клик по активной сбрасывает») отвергнут: недискаверабелен, а
  объяснять его негде.

  ⚠️ **Следствие 3.23 про «клик в ту сторону, где уже находишься» СНЯТО
  задачей 3.165, а не забыто.** При системном дефолте оно было реальным: видимая
  кнопка могла случайно указывать туда же, куда уже смотрел OS-производный вид,
  и клик тогда ничего не менял на экране, лишь фиксировал предпочтение. При
  фиксированном дефолте это больше не может произойти по конструкции — из
  дефолтного состояния (всегда тёмного) видна ровно кнопка «включить светлую»,
  и её клик — всегда настоящая, видимая смена.

  См. `<head>` в `root.html.heex` — там хранение выбора и применение до первой
  отрисовки. Этот скрипт править не надо.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="theme-toggle" id="theme-toggle">
      <button
        class="theme-b"
        type="button"
        id="theme-to-dark"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        data-shown-when="light"
        title="Включить тёмную тему"
        aria-label="Включить тёмную тему"
      >
        <.icon name="hero-moon" />
      </button>
      <button
        class="theme-b"
        type="button"
        id="theme-to-light"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        data-shown-when="dark"
        title="Включить светлую тему"
        aria-label="Включить светлую тему"
      >
        <.icon name="hero-sun" />
      </button>
    </div>
    """
  end
end
