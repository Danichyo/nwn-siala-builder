defmodule BuildCalculatorWeb.Locale do
  @moduledoc """
  Язык интерфейса — из редакции (`BuildCalculatorWeb.Edition.locale/0`),
  задача 4.2.

  Локаль `gettext` живёт в словаре ПРОЦЕССА, поэтому ставится дважды:

    * plug'ом в пайплайне `:browser` — для HTTP-запроса: мёртвый рендер
      LiveView, корневой макет (`lang` у `<html>`), контроллеры и их флеши;
    * `on_mount` в каждом `live_session` — у подключённого LiveView свой
      процесс, и локаль HTTP-запроса туда не переезжает.

  ⚠️ Собранная локаль бэкенда (`config :build_calculator,
  BuildCalculatorWeb.Gettext, default_locale: "ru"`) остаётся запасной и
  в `runtime.exs` не переносится: бэкенд читает её через
  `Application.compile_env`, и расхождение роняет запуск релиза
  (VANILLA.md §3.5).
  """

  @behaviour Plug

  alias BuildCalculatorWeb.Edition

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    put_locale()
    conn
  end

  @doc "`on_mount` для `live_session`: та же локаль в процессе LiveView."
  def on_mount(:default, _params, _session, socket) do
    put_locale()
    {:cont, socket}
  end

  defp put_locale, do: Gettext.put_locale(BuildCalculatorWeb.Gettext, Edition.locale())
end
