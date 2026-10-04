defmodule BuildCalculatorWeb.Analytics.Client do
  @moduledoc """
  Что приходит от посетителя — и что из этого остаётся полем строки аналитики
  (задача 4.54). Чистые функции, без сокета.

  ## Настоящий IP за Caddy

  Топология прода (`DEPLOY.md`): Caddy на хосте → `127.0.0.1:5000` →
  контейнер, где Bandit слушает `::`. Пир, которого видит приложение, — не
  посетитель, а прокси: адрес моста Docker или петля, причём IPv4 в сокете `::`
  приходит адресом вида `::ffff:a.b.c.d`. Настоящий адрес — в `X-Forwarded-For`,
  который ставит Caddy.

  Верим заголовку ровно тогда, когда пир — свой: петля или частная сеть
  (`trusted_proxy?/1`, IPv4-mapped разворачивается). Берём ПРАВЫЙ адрес
  заголовка — тот, что дописал ближайший к нам прокси. Caddy без
  `trusted_proxies` присланный клиентом `X-Forwarded-For` не продолжает,
  а заменяет адресом клиента, так что подделка до нас не доходит; а если
  когда-нибудь станет продолжать, левые адреса — клиентские, и правый
  по-прежнему Caddy. Пир публичный (к приложению пришли мимо прокси) —
  заголовок не читается вовсе: его написал сам клиент, и он раздувал бы
  уникальных. Правый адрес не читается — тоже пир, а не соседний левый.

  ## Источник и метки

  Хост источника присылает `app.js` (`document.referrer` → `hostname`; путь
  страницы-источника браузер не отдаёт вовсе), но сокет — поле ввода, поэтому
  здесь он читается заново как имя хоста: строчные буквы, цифры, точки
  и дефисы, до 253 знаков, без `www.`. Свой хост — не источник.

  `utm_*` — пять стандартных ключей, остальной query отбрасывается целиком.
  Значение — до 64 знаков без управляющих; значение, которое раскодируется
  как код билда, выбрасывается (билд не уходит в аналитику и меткой ссылки).
  """

  import Bitwise

  alias BuildCalculator.Analytics
  alias BuildCalculator.Encoding

  @max_host 253
  @max_utm 64

  @host_shape ~r/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\z/

  # Управляющие и форматные символы (`\p{Cc}`, `\p{Cf}`) — не метка, а мусор.
  @printable ~r/\A[^\p{Cc}\p{Cf}]+\z/u

  @doc """
  Адрес посетителя: `peer_data` и `x_headers` из `connect_info` LiveView.

  `nil` — адреса нет (сокет без `peer_data`).
  """
  @spec ip(map() | nil, [{String.t(), String.t()}] | nil) :: :inet.ip_address() | nil
  def ip(peer_data, x_headers) do
    case peer(peer_data) do
      nil -> nil
      peer -> if trusted_proxy?(peer), do: forwarded(x_headers) || peer, else: peer
    end
  end

  defp peer(%{address: address}) when is_tuple(address), do: unmap(address)
  defp peer(_peer_data), do: nil

  # Правый адрес `X-Forwarded-For`; заголовков несколько — их значения
  # склеиваются по порядку, как это делает сам HTTP.
  defp forwarded(x_headers) when is_list(x_headers) do
    entries =
      for {"x-forwarded-for", value} <- x_headers,
          entry <- String.split(value, ","),
          do: String.trim(entry)

    case List.last(entries) do
      nil ->
        nil

      entry ->
        case :inet.parse_strict_address(String.to_charlist(entry)) do
          {:ok, address} -> unmap(address)
          {:error, _} -> nil
        end
    end
  end

  defp forwarded(_x_headers), do: nil

  @doc """
  Публичный ли адрес посетителя: есть и не петля, не частная сеть,
  не link-local (`trusted_proxy?/1`).

  Непубличный адрес у посетителя значит, что `X-Forwarded-For` до приложения
  не дошёл (или это машина разработчика): все за прокси видны одним адресом.
  Счёт «на адрес» (потолки аналитики и коротких ссылок, задача 4.75) такому
  адресу не ставится — он сложил бы всех игроков в одно ведро.
  """
  @spec public?(:inet.ip_address() | nil) :: boolean()
  def public?(nil), do: false
  def public?(address), do: not trusted_proxy?(address)

  @doc """
  Свой ли это прокси: петля, частная сеть (RFC 1918, ULA), link-local.

  IPv4 внутри IPv6 (`::ffff:a.b.c.d`) сравнивается как IPv4.
  """
  @spec trusted_proxy?(:inet.ip_address()) :: boolean()
  def trusted_proxy?(address) do
    case unmap(address) do
      {127, _, _, _} -> true
      {10, _, _, _} -> true
      {172, b, _, _} when b in 16..31 -> true
      {192, 168, _, _} -> true
      {169, 254, _, _} -> true
      {0, 0, 0, 0, 0, 0, 0, 1} -> true
      {a, _, _, _, _, _, _, _} when (a &&& 0xFE00) == 0xFC00 -> true
      {a, _, _, _, _, _, _, _} when (a &&& 0xFFC0) == 0xFE80 -> true
      _ -> false
    end
  end

  defp unmap({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: {high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF}

  defp unmap(address), do: address

  @doc """
  Хост источника — или `nil`: пусто, не похоже на имя хоста, свой хост.

  `raw` — что прислал клиент (имя хоста или адрес целиком), `own_host` —
  хост страницы, на которую пришли.
  """
  @spec referrer_host(term(), String.t() | nil) :: String.t() | nil
  def referrer_host(raw, own_host) when is_binary(raw) do
    host = raw |> host_part() |> normalize_host()

    cond do
      host == nil -> nil
      own_host && host == normalize_host(own_host) -> nil
      true -> host
    end
  end

  def referrer_host(_raw, _own_host), do: nil

  defp host_part(raw) do
    raw = String.trim(raw)

    if String.contains?(raw, "://") do
      URI.parse(raw).host || ""
    else
      raw |> String.split(["/", "?", "#", ":"], parts: 2) |> hd()
    end
  rescue
    _ -> ""
  end

  defp normalize_host(nil), do: nil

  defp normalize_host(host) do
    host =
      host
      |> String.downcase()
      |> String.trim_trailing(".")
      |> String.replace_prefix("www.", "")

    if byte_size(host) <= @max_host and Regex.match?(@host_shape, host), do: host
  end

  @doc """
  Пять `utm_*` из параметров страницы: ключ → значение или `nil`.

  Все прочие параметры (и `b` с кодом билда) не читаются.
  """
  @spec utm(map()) :: %{atom() => String.t() | nil}
  def utm(params) when is_map(params) do
    Map.new(Analytics.utm_keys(), fn key ->
      {key, params |> Map.get(Atom.to_string(key)) |> utm_value()}
    end)
  end

  def utm(_params), do: Map.new(Analytics.utm_keys(), &{&1, nil})

  defp utm_value(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      not String.valid?(value) -> nil
      value == "" or String.length(value) > @max_utm -> nil
      not Regex.match?(@printable, value) -> nil
      build_code?(value) -> nil
      true -> value
    end
  end

  defp utm_value(_value), do: nil

  defp build_code?(value), do: match?({:ok, _}, Encoding.decode(value))

  @doc """
  Что считать у этого подключения — по параметрам подключения LiveView
  и хосту своего сайта (`own_host`, `Endpoint.host/0`).

    * `visit?` — первый join страницы (`_mounts` 0): повторный — обрыв связи
      или выкат, та же страница, посещением не считается;
    * `referrer_host` — хост источника (`referrer_host/2`), кроме живой
      навигации (`_live_referer`: источник — своя же страница) и своего хоста;
    * `link_open?` — первый join, не живая навигация, не перезагрузка и не
      «Назад» (`_analytics_nav`, `fresh_navigation?/1`) и пришли не со своего
      сайта: полная загрузка страницы со своей же (переход между
      `live_session`, обычная ссылка) — не «открыт по ссылке».

  ⚠️ `Phoenix.LiveViewTest` всегда шлёт `_mounts` 0 (`ClientProxy`), поэтому
  повторный join проверяется здесь, вызовом, а не в тесте экрана.
  """
  @spec plan(map() | nil, String.t() | nil) :: %{
          visit?: boolean(),
          link_open?: boolean(),
          referrer_host: String.t() | nil
        }
  def plan(params, own_host) when is_map(params) do
    first? = params["_mounts"] in [nil, 0]
    live_nav? = is_binary(params["_live_referer"]) and params["_live_referer"] != ""
    raw = params["_analytics_ref"]
    from_own_site? = referrer_host(raw, nil) != nil and referrer_host(raw, own_host) == nil

    %{
      visit?: first?,
      link_open?:
        first? and not live_nav? and not from_own_site? and
          fresh_navigation?(params["_analytics_nav"]),
      referrer_host: if(live_nav?, do: nil, else: referrer_host(raw, own_host))
    }
  end

  def plan(_params, own_host), do: plan(%{}, own_host)

  @doc """
  Свежий ли это переход по ссылке, а не перезагрузка и не «Назад»/«Вперёд».

  `nav` — `PerformanceNavigationTiming.type`, его присылает `app.js`.
  Нет значения (старый браузер, тест) — считается свежим.
  """
  @spec fresh_navigation?(term()) :: boolean()
  def fresh_navigation?(nav), do: nav not in ["reload", "back_forward"]
end
