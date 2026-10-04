defmodule BuildCalculatorWeb.Edition do
  @moduledoc """
  Редакция — какой это САЙТ (VANILLA.md §2, задача 4.2).

  Одна кодовая база поднимается двумя развёртками: сиальская (`siala_41`,
  русский интерфейс, `builder.dondryanich.ru`) и ванильная (`vanilla`,
  английский). Всё, чем они различаются как сайты, — здесь, одним модулем:

    * **ruleset** сайта — механика, которую он считает. Ссылка с другим
      ruleset'ом не пересчитывается по чужим правилам молча, а открывается
      мостиком на сайт той редакции, что его считает (`serves?/1`, `bridge/2`);
    * **язык** интерфейса (`locale/0`) — его ставит `BuildCalculatorWeb.Locale`;
    * **бренд** — шапка, имя продукта, заголовок вкладки, фразы футера,
      подпись текстового экспорта;
    * **привычки аудитории** — вид гида в текстовом экспорте (`export_guide/1`);
    * **флаги** интерфейса — их умолчание (`flag?/1`, читатель —
      `BuildCalculatorWeb.Layouts`).

  Механики игры здесь нет и быть не должно: отличие ИГРЫ — данные ruleset'а,
  отличие САЙТА и аудитории — редакция (VANILLA.md §2 п. 3).

  ## Откуда берётся

  Пресеты — `config/config.exs` → `:editions`, по списку на редакцию; какая
  работает — `config :build_calculator, :edition`, по умолчанию Сиала,
  при запуске — переменная `EDITION` через белый список в `config/runtime.exs`.
  Имена ruleset'ов стоят в конфиге, а не здесь: сторож «код не спрашивает имя
  ruleset'а» считает упоминания в `lib/` (VANILLA.md §2 п. 1).

  🔴 **Шаблон спрашивает у редакции СТРОКУ или ВОЗМОЖНОСТЬ, а не её имя.**
  Никаких `if edition == :siala` в разметке: имя редакции наружу не отдаётся
  ни одной функцией, кроме `current/0`, и та нужна запуску, тестам и строке
  аналитики (задача 4.54: какой сайт записал строку — метка, а не развилка).

  ## Ядро

  Ядро (`lib/build_calculator/`) имён редакций не знает. Из всей редакции оно
  видит один ключ — `config :build_calculator, :default_ruleset`
  (`BuildCalculator.Data.default_version/0`), и пишет его `configure!/0` один
  раз при запуске приложения. Отдельным ключом, а не вызовом сюда, — чтобы
  зависимость шла от веба к ядру, а не обратно.
  """

  alias BuildCalculator.Data

  @keys [
    :ruleset,
    :locale,
    :site,
    :eyebrow,
    :brand_title,
    :product_name,
    :export_name,
    :footer_adapted,
    :footer_disclaimer,
    :rules_name,
    :export_guide,
    :accounts_ui,
    :import_ui,
    :game_log_import_ui,
    :guide_first,
    :analytics
  ]

  @flags [:accounts_ui, :import_ui, :game_log_import_ui, :guide_first, :analytics]

  # Два вида гида по уровням в текстовом экспорте (`Builder.Export`):
  # `:ecb` — два блока формата гильдии Epic Character Builders (`LEVELING GUIDE`
  # и `SKILL GUIDE`), `:merged` — всё, что даёт уровень, одной строкой.
  @export_guides [:ecb, :merged]

  # Разделитель в заголовке вкладки: «Источники · Калькулятор билдов Сиалы».
  # Один на обе редакции — он не бренд, а типографика.
  @title_separator " · "

  @typedoc "Флаг интерфейса, умолчание которого несёт пресет."
  @type flag :: :accounts_ui | :import_ui | :game_log_import_ui | :guide_first | :analytics

  @typedoc "Вид гида по уровням в текстовом экспорте — `export_guide/1`."
  @type export_guide :: :ecb | :merged

  @typedoc """
  Мостик на сайт-близнец для ссылки с чужим ruleset'ом.

  `rules` — как читателю назвать чужие правила на ЕГО языке (`nil`, когда
  ruleset не считает ни одна редакция); `url` — тот же путь на том сайте
  (`nil`, когда сайта нет); `host` — имя сайта для подписи ссылки.
  """
  @type bridge :: %{rules: String.t() | nil, url: String.t() | nil, host: String.t() | nil}

  @doc """
  Какая редакция работает. Нужна запуску (`configure!/0`), тестам и строке
  аналитики (`BuildCalculatorWeb.Analytics`, метка сайта); шаблону имя
  редакции не нужно никогда — он спрашивает строку или возможность.
  """
  @spec current() :: atom()
  def current, do: Application.fetch_env!(:build_calculator, :edition)

  @doc "Ruleset, который считает этот сайт."
  @spec ruleset() :: Data.version()
  def ruleset, do: fetch!(:ruleset)

  @doc """
  Считает ли этот сайт ссылки с таким ruleset'ом.

  «Разрешённые в ссылке» (VANILLA.md §2) сегодня совпадают с ruleset'ом
  сайта: у каждой редакции он один. Чужой — не ошибка, а мостик (`bridge/2`).
  """
  @spec serves?(Data.version()) :: boolean()
  def serves?(version) when is_binary(version), do: version == ruleset()

  @doc "Язык интерфейса сайта — локаль `gettext` и `lang` у `<html>`."
  @spec locale() :: String.t()
  def locale, do: fetch!(:locale)

  @doc "Надстрочник бренда в шапке («Сиала · NWN»)."
  @spec eyebrow() :: String.t()
  def eyebrow, do: fetch!(:eyebrow)

  @doc "Имя в шапке под надстрочником («Калькулятор билдов»)."
  @spec brand_title() :: String.t()
  def brand_title, do: fetch!(:brand_title)

  @doc "Имя продукта — заголовок вкладки конструктора и хвост любого другого."
  @spec product_name() :: String.t()
  def product_name, do: fetch!(:product_name)

  @doc """
  Заголовок вкладки: имя страницы и имя продукта, либо имя продукта одно.

  ⚠️ Хвост пристёгивается здесь, в назначении `page_title`, а не атрибутом
  `suffix` у `<.live_title>` в `root.html.heex`: у конструктора заголовок —
  само имя продукта, и клиентский `suffix` LiveView дописывается к любому
  заголовку, включая умолчание, — вкладка конструктора читалась бы
  «Калькулятор билдов Сиалы · Калькулятор билдов Сиалы». `root.html.heex`
  берёт из редакции только умолчание.
  """
  @spec page_title(String.t() | nil) :: String.t()
  def page_title(nil), do: product_name()
  def page_title(page) when is_binary(page), do: page <> @title_separator <> product_name()

  @doc """
  Имя продукта, которым подписан текстовый экспорт: «Посчитано Siala Build
  Calculator» (задача 4.4).

  Своё поле, а не `product_name/0`: экспорт — английский формат комьюнити,
  его читают на форумах и в Discord, и русский сайт подписывает его
  латиницей («Siala Build Calculator»), тогда как вкладка у него русская
  («Калькулятор билдов Сиалы»). Рамка вокруг имени — `gettext`
  (`Builder.Export`), само имя — бренд, его язык решает сайт.
  """
  @spec export_name() :: String.t()
  def export_name, do: fetch!(:export_name)

  @doc """
  Вид гида по уровням в текстовом экспорте билда с этими правилами (задача 4.4):
  `:ecb` — два блока формата гильдии Epic Character Builders, `:merged` — одна
  строка на уровень.

  Форма гида — привычка АУДИТОРИИ, а не механика игры (VANILLA.md §2 п. 3):
  ванильные билды ходят по форумам в формате гильдии, и его же читает наш
  импорт текста; игрокам Сиалы нужен весь уровень одной строкой (Dan
  30.08.2026, задача 3.145). До 4.4 это решала ветка по имени ruleset'а
  в `Builder.Export`.

  Пресет ищется по ruleset'у БИЛДА среди всех редакций — тем же приёмом, что
  у `bridge/2`, — а не берётся у работающего сайта: аудитория у правил, по
  которым собран билд. С задачи 4.2 сайт считает только свой ruleset (чужая
  ссылка — мостик), так что на живом сайте это одно и то же, а экспорт
  ванильного билда, собранный вызовом в обход сайта, остаётся в формате
  гильдии. Ruleset, который не считает ни одна редакция, получает формат
  гильдии — формат комьюнити по умолчанию.
  """
  @spec export_guide(Data.version()) :: export_guide()
  def export_guide(version) when is_binary(version) do
    case preset_for(version) do
      nil -> :ecb
      preset -> preset[:export_guide]
    end
  end

  @doc """
  Оборот футера про переработку материала Fandom — лицензия CC BY-SA требует
  сказать, что материал изменён; как именно, сайты говорят по-своему.
  """
  @spec footer_adapted() :: String.t()
  def footer_adapted, do: fetch!(:footer_adapted)

  @doc "Оговорка футера о неаффилированности — целиком, у сайтов она своя."
  @spec footer_disclaimer() :: String.t()
  def footer_disclaimer, do: fetch!(:footer_disclaimer)

  @doc """
  Включён ли флаг интерфейса.

  Умолчание — из пресета редакции; явный `config :build_calculator, <флаг>`
  его перекрывает. Перекрытие оставлено ради тестов: они включают спрятанное
  через `Application.put_env/3` и так получают положительный контроль
  к каждому `refute` (`launch_ui_test.exs`, `import_ui_test.exs`).
  """
  @spec flag?(flag()) :: boolean()
  def flag?(name) when name in @flags do
    Application.get_env(:build_calculator, name, fetch!(name))
  end

  @doc """
  Мостик для ссылки, чей ruleset этот сайт не считает.

  `path` — путь той же страницы (`"/?b=<код>"`, `"/b/<код>"`): код билда
  несёт свой ruleset сам, и на сайте, который этот ruleset считает, откроется
  тот же билд. Сайт ищется по ruleset'у среди пресетов, а не по имени.
  """
  @spec bridge(Data.version(), String.t()) :: bridge()
  def bridge(version, path) when is_binary(version) and is_binary(path) do
    case preset_for(version) do
      nil ->
        %{rules: nil, url: nil, host: nil}

      preset ->
        site = preset[:site]

        %{
          rules: Map.get(preset[:rules_name], locale()),
          url: site && String.trim_trailing(site, "/") <> path,
          host: site && URI.parse(site).host
        }
    end
  end

  # Пресет редакции, которая считает этот ruleset, — `nil`, если такой нет.
  # По ruleset'у, а не по имени редакции: `configure!/0` гарантирует, что
  # у ruleset'а не больше одного сайта.
  defp preset_for(version) do
    case Enum.find(editions(), fn {_name, preset} -> preset[:ruleset] == version end) do
      {_name, preset} -> preset
      nil -> nil
    end
  end

  @doc """
  Проверяет пресеты и отдаёт ядру ruleset по умолчанию.

  Зовётся один раз при запуске (`BuildCalculator.Application.start/2`) и ещё
  тестами, которые переключают редакцию. Кривой пресет роняет запуск сразу,
  а не первый запрос: неизвестная редакция, пропущенный ключ, ruleset, которого
  нет в сборке, язык, которого нет в `gettext`, два сайта на одном ruleset'е
  (мостику было бы не выбрать), `rules_name` без языка другого сайта.
  """
  @spec configure!() :: :ok
  def configure! do
    editions = editions()
    current = current()

    unless Keyword.has_key?(editions, current) do
      raise ArgumentError,
            "config :build_calculator, :edition is #{inspect(current)}, " <>
              "which is not one of the presets in :editions: #{inspect(Keyword.keys(editions))}"
    end

    locales = for {_name, preset} <- editions, do: preset[:locale]
    Enum.each(editions, &check_preset!(&1, locales))

    rulesets = for {_name, preset} <- editions, do: preset[:ruleset]

    if Enum.uniq(rulesets) != rulesets do
      raise ArgumentError, "two editions compute the same ruleset: #{inspect(rulesets)}"
    end

    Application.put_env(:build_calculator, :default_ruleset, ruleset())
  end

  defp check_preset!({name, preset}, locales) do
    missing = Enum.reject(@keys, &Keyword.has_key?(preset, &1))

    if missing != [] do
      raise ArgumentError, "edition #{inspect(name)} misses #{inspect(missing)}"
    end

    unless preset[:ruleset] in Data.versions() do
      raise ArgumentError,
            "edition #{inspect(name)} computes #{inspect(preset[:ruleset])}, " <>
              "which is not compiled in: #{inspect(Data.versions())}"
    end

    unless preset[:locale] in Gettext.known_locales(BuildCalculatorWeb.Gettext) do
      raise ArgumentError,
            "edition #{inspect(name)} speaks #{inspect(preset[:locale])}, " <>
              "which gettext does not know"
    end

    unless is_nil(preset[:site]) or match?("http" <> _, preset[:site]) do
      raise ArgumentError, "edition #{inspect(name)}: site must be an absolute URL or nil"
    end

    unless is_map(preset[:rules_name]) and
             Enum.all?(locales, &Map.has_key?(preset[:rules_name], &1)) do
      raise ArgumentError,
            "edition #{inspect(name)}: rules_name must name its rules in every " <>
              "edition's language #{inspect(Enum.uniq(locales))}"
    end

    for flag <- @flags, not is_boolean(preset[flag]) do
      raise ArgumentError, "edition #{inspect(name)}: #{flag} must be true or false"
    end

    unless preset[:export_guide] in @export_guides do
      raise ArgumentError,
            "edition #{inspect(name)}: export_guide must be one of #{inspect(@export_guides)}"
    end

    :ok
  end

  defp editions, do: Application.fetch_env!(:build_calculator, :editions)

  defp fetch!(key) do
    editions()
    |> Keyword.fetch!(current())
    |> Keyword.fetch!(key)
  end
end
