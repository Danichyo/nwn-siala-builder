defmodule BuildCalculatorWeb.LogRedaction do
  @moduledoc """
  Фильтр лога: ни кода билда, ни самого билда в логе приложения (задача 4.75).

  Слово Dan про аналитику — «главное, чтобы мы не логировали билды» (4.54) —
  касается и лога: в проде его пишет Docker (`json-file`, 10 МБ × 3,
  `DEPLOY.md`). Строку запроса без кода печатает `BuildCalculatorWeb.RequestLog`;
  здесь — всё остальное, что приложение и его зависимости кладут в лог:
  отчёты о падении процессов, строки ошибок Bandit, предупреждения
  `Phoenix.LiveView` с адресом страницы.

  Стоит **первичным фильтром `:logger`** (`install/0` из
  `BuildCalculator.Application.start/2`): видит каждое событие до любого
  обработчика — консоли, файла, `ExUnit.CaptureLog` — и раньше переводчика
  отчётов Elixir (`logger_translator`): добавленный фильтр встаёт первым в
  списке, поэтому отчёт о падении приходит сюда ещё структурой, а не текстом.

  ## Что делается — по форме события, а не догадкой по тексту

    * **Отчёт о падении процесса** (`gen_server`, `gen_statem`, `gen_event`,
      `proc_lib`, задача `Task.Supervisor`, супервизор): последнее сообщение,
      состояние, аргументы задачи, очередь сообщений и словарь процесса
      заменяются пометкой `#Withheld<…>` — вид и размер без содержимого.
      Процесс LiveView держит в состоянии ВЕСЬ сокет — код из адреса,
      раскодированный билд, текст импорта, — а последнее сообщение несёт
      адрес страницы (вход) или параметры события. Имя события LiveView
      остаётся: без него отчёт не говорит, что упало.
    * **Стек**: аргументы кадра (`{m, f, args, loc}` — так OTP сохраняет кадр,
      где не нашлось клаузы) заменяются арностью. В кадре `handle_event/3`
      сидит сокет целиком.
    * **Исключение**, которое носит чужое значение (`KeyError` — карту,
      `MatchError`, `CaseClauseError` … — значение), — значение заменяется
      пометкой: `socket.assigns.x` без ключа печатал бы все ассайны. Остальные
      поля любого исключения проходят сетью ниже.
    * **Строка ошибки Bandit** (падение запроса — 500): Bandit кладёт в
      метаданные `crash_reason` то, из чего собрал текст. Если текст события —
      ровно `Exception.format/3` (или баннер) этой причины, он собирается
      заново из очищенной; метаданные `crash_reason` очищаются, `conn` (весь
      запрос) снимается.
    * **Сеть по тексту** — для всего остального, включая чужие строки
      (`Phoenix.LiveView` пишет «navigate event to "<адрес>" failed …» при
      переходе между `live_session`): адрес `http(s)://…` сводится к хосту
      и **шаблону маршрута** (`/b/:code`, query выбрасывается), а код билда
      по форме (`<версия>.<base64url>`, `BuildCalculator.Encoding`) —
      к `[build code]`.

  ## Закрытие сокета за нарушение протокола — не ошибка

  Сообщение сверх потолка сокета и кадр против RFC 6455 Bandit закрывает
  остановкой процесса соединения; это приходило отчётом `error` о падении.
  С 4.76 такие события — одна строка `warning` (`ProtocolClose`): событие
  клиента, а не ошибка приложения.

  ## Чего фильтр НЕ делает

  Не ищет билд по смыслу: раскодированный билд вне перечисленных форм (свой
  `Logger.info(inspect(build))`) сеть не увидит. Поэтому в веб-слое и ядре
  билд в лог не пишется вовсе — сторож `log_leak_test.exs` проходит маршруты,
  события и падения с настоящими кодами и ищет в захваченном логе код, его
  куски и id классов и фитов билда.

  ## Не роняет лог

  Исключение внутри фильтра `:logger` наказывает снятием фильтра — и всё
  дальнейшее пошло бы без него. Поэтому фильтр ловит всё сам и на отказе
  отдаёт событие без содержимого (вид отказа — да, текст — нет).
  """

  alias BuildCalculatorWeb.LogRedaction.{ProtocolClose, Withheld}
  alias BuildCalculatorWeb.RequestLog

  @filter_id :build_code_redaction

  # Код билда: версия схемы, точка, base64url без паддинга
  # (`BuildCalculator.Encoding.encode/1`, `"2." <> …`). Восемь знаков после
  # точки — меньше, чем у кода пустого билда (сторож в тесте). Перед версией —
  # не буква, не цифра, не `_` и не точка: иначе пометкой стали бы имена
  # модулей и функций (`Phoenix.Socket.V2.JSONSerializer`,
  # `:elixir_compiler_1.__FILE__`); исключение — `%3D` и `%2F` (`=` и `/`
  # в закодированном адресе).
  @code ~r/(?:(?<![A-Za-z0-9_.])|(?<=%3D)|(?<=%3d)|(?<=%2F)|(?<=%2f))[1-9][0-9]?\.[A-Za-z0-9_-]{8,}/
  @code_mark "[build code]"

  @url ~r{https?://[^\s"'<>\\]+}

  # Поля отчётов OTP и Elixir, несущие данные процесса, а не описание падения.
  @withheld_keys [
    :state,
    :last_message,
    :message,
    :args,
    :messages,
    :dictionary,
    :queue,
    :postponed,
    :log,
    :data
  ]

  # Исключения, чьё поле — чужое значение целиком.
  @term_fields %{
    MatchError => [:term],
    CaseClauseError => [:term],
    WithClauseError => [:term],
    TryClauseError => [:value],
    BadMapError => [:term],
    BadBooleanError => [:term],
    BadFunctionError => [:term],
    BadStructError => [:term],
    BadArityError => [:args],
    Protocol.UndefinedError => [:value],
    ErlangError => [:original]
  }

  @max_depth 64

  @doc "Ставит фильтр первичным фильтром `:logger` (повторно — без ошибки)."
  @spec install() :: :ok
  def install do
    case :logger.add_primary_filter(@filter_id, {&__MODULE__.filter/2, []}) do
      :ok -> :ok
      {:error, {:already_exist, @filter_id}} -> :ok
    end
  end

  @doc "Снимает фильтр — только для положительного контроля в тестах."
  @spec uninstall() :: :ok
  def uninstall do
    _ = :logger.remove_primary_filter(@filter_id)
    :ok
  end

  @doc "Стоит ли фильтр сейчас."
  @spec installed?() :: boolean()
  def installed?, do: Keyword.has_key?(:logger.get_primary_config().filters, @filter_id)

  @doc false
  @spec filter(:logger.log_event(), term()) :: :logger.filter_return()
  def filter(event, _extra) do
    redact(event)
  rescue
    error -> fallback(event, inspect(error.__struct__))
  catch
    kind, _reason -> fallback(event, Atom.to_string(kind))
  end

  # Отказ фильтра: событие уходит без содержимого — вид отказа, время, pid;
  # событие без привычной формы не уходит вовсе (`:stop`).
  defp fallback(%{msg: _msg, meta: meta} = event, why) when is_map(meta) do
    %{
      event
      | msg: {:string, "log event withheld: redaction failed (" <> why <> ")"},
        meta: Map.take(meta, [:time, :pid, :gl, :domain, :request_id])
    }
  end

  defp fallback(_event, _why), do: :stop

  @doc """
  Событие лога без кода билда и без данных процесса — см. moduledoc.
  """
  @spec redact(:logger.log_event()) :: :logger.log_event()
  def redact(%{msg: msg, meta: meta} = event) do
    # Задача 4.76: закрытие сокета за нарушение протокола клиентом — одна
    # строка `warning` вместо отчёта `error` (`ProtocolClose`).
    case ProtocolClose.rewrite(event) do
      {:ok, line} -> line
      :keep -> redact_event(event, msg, meta)
    end
  end

  def redact(event), do: event

  defp redact_event(event, msg, meta) do
    msg =
      case msg do
        {:string, text} -> {:string, rebuilt_crash(text, meta) || text(text)}
        {:report, report} -> {:report, report(report)}
        {format, args} when is_list(args) -> {format, term(args, 0)}
        other -> other
      end

    %{event | msg: msg, meta: redact_meta(meta)}
  end

  # ------------------------------------------------------------------ text --

  @doc "Текст без кода билда и с адресами, сведёнными к шаблону маршрута."
  @spec text(IO.chardata()) :: String.t()
  def text(chardata) do
    chardata
    |> to_binary()
    |> scrub_binary()
  end

  defp to_binary(text) when is_binary(text), do: text

  defp to_binary(chardata) do
    IO.chardata_to_string(chardata)
  rescue
    _ -> IO.iodata_to_binary(chardata)
  end

  defp scrub_binary(text) do
    text
    |> then(&Regex.replace(@url, &1, fn url -> url_template(url) end))
    |> then(&Regex.replace(@code, &1, @code_mark))
  end

  defp url_template(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, path: path, port: port} = uri
      when is_binary(scheme) and is_binary(host) and is_binary(path) and path != "" ->
        port = if port == URI.default_port(scheme), do: "", else: ":#{port}"
        query = if uri.query || uri.fragment, do: "?…", else: ""
        "#{scheme}://#{host}#{port}#{RequestLog.route(path, host)}#{query}"

      _no_path ->
        url
    end
  rescue
    _ -> @code_mark
  end

  # --------------------------------------------------------------- reports --

  # Отчёт — карта или список ключ-значение; вложенный отчёт (`report:`
  # у `Task.Supervisor` и супервизора, `offender:`) разбирается так же.
  defp report(report) when is_map(report), do: Map.new(report, &report_field/1)

  defp report(report) when is_list(report) do
    if Keyword.keyword?(report),
      do: Enum.map(report, &report_field/1),
      else: Enum.map(report, &report_or_term/1)
  end

  defp report(other), do: term(other, 0)

  defp report_or_term(entry) when is_list(entry) or is_map(entry), do: report(entry)
  defp report_or_term(entry), do: term(entry, 0)

  defp report_field({key, value}) when key in @withheld_keys, do: {key, withhold(value)}
  defp report_field({:reason, reason}), do: {:reason, reason(reason)}

  defp report_field({:error_info, {kind, reason, stack}}),
    do: {:error_info, {kind, reason(reason), stack(stack)}}

  # Кто звал упавший `GenServer`: pid и стек вызывающего (`current_stacktrace` —
  # с арностью, без аргументов); остаётся, но стек — через ту же чистку.
  defp report_field({:client_info, {pid, {name, stack}}}) when is_list(stack),
    do: {:client_info, {pid, {term(name, 0), stack(stack)}}}

  defp report_field({:mfargs, {m, f, a}}), do: {:mfargs, {m, f, withhold(a)}}
  defp report_field({:report, nested}), do: {:report, report(nested)}

  defp report_field({:offender, offender}) when is_list(offender),
    do: {:offender, report(offender)}

  defp report_field({key, value}), do: {key, term(value, 0)}

  # --------------------------------------------------------------- reasons --

  @doc false
  def reason({%{__exception__: true} = exception, stack}) when is_list(stack),
    do: {exception(exception), stack(stack)}

  def reason({:nocatch, value}), do: {:nocatch, withhold(value)}

  def reason({kind, reason, stack}) when kind in [:error, :exit, :throw] and is_list(stack),
    do: {kind, reason(reason), stack(stack)}

  def reason({reason, stack}) when is_list(stack) do
    if stacktrace?(stack),
      do: {reason(reason), stack(stack)},
      else: {reason(reason), term(stack, 0)}
  end

  def reason({reason, {m, f, args}}) when is_atom(m) and is_atom(f) and is_list(args),
    do: {reason(reason), {m, f, withhold(args)}}

  def reason(%{__exception__: true} = exception), do: exception(exception)
  def reason(other), do: term(other, 0)

  defp stacktrace?(stack), do: stack != [] and Enum.all?(stack, &frame?/1)

  defp frame?({m, f, a, loc}) when is_atom(m) and is_atom(f) and (is_list(a) or is_integer(a)),
    do: is_list(loc)

  defp frame?({fun, a, loc}) when is_function(fun) and (is_list(a) or is_integer(a)),
    do: is_list(loc)

  defp frame?(_), do: false

  @doc false
  def stack(stack) when is_list(stack) do
    Enum.map(stack, fn
      {m, f, args, loc} when is_list(args) -> {m, f, length(args), loc}
      {fun, args, loc} when is_function(fun) and is_list(args) -> {fun, length(args), loc}
      frame -> frame
    end)
  end

  def stack(other), do: other

  @doc false
  def exception(%KeyError{key: key, term: term, message: message} = error) do
    message =
      case message do
        nil -> "key #{inspect(term(key, 0))} not found in: #{inspect(withhold(term))}"
        text -> text(text)
      end

    %{error | key: term(key, 0), term: withhold(term), message: message}
  end

  def exception(%FunctionClauseError{} = error), do: %{error | args: nil}

  def exception(%module{} = error) do
    case Map.fetch(@term_fields, module) do
      {:ok, fields} ->
        Enum.reduce(fields, scrub_fields(error, fields), fn field, acc ->
          Map.update!(acc, field, &withhold/1)
        end)

      :error ->
        scrub_fields(error, [])
    end
  end

  defp scrub_fields(error, skip) do
    error
    |> Map.from_struct()
    |> Map.drop([:__exception__ | skip])
    |> Enum.reduce(error, fn {field, value}, acc -> Map.put(acc, field, term(value, 0)) end)
  end

  # ------------------------------------------------------------------ meta --

  defp redact_meta(meta) do
    meta
    |> Map.delete(:conn)
    |> then(fn meta ->
      case meta do
        %{crash_reason: crash} -> Map.put(meta, :crash_reason, reason(crash))
        _ -> meta
      end
    end)
  end

  # Строка ошибки Bandit (`Bandit.Pipeline.handle_error/7`, `Bandit.Logger`):
  # текст — `Exception.format/3` или баннер той причины, что лежит
  # в `crash_reason`. Совпал — собирается заново из очищенной причины; текст
  # другой формы — `nil`, и его чистит сеть.
  defp rebuilt_crash(text, %{crash_reason: {reason, stack}}) when is_list(stack) do
    {kind, error, clean} = crash_kind(reason)
    text = to_binary(text)
    clean_stack = stack(stack)

    cond do
      text == Exception.format(kind, error, stack) ->
        text(Exception.format(kind, clean, clean_stack))

      text == Exception.format_banner(kind, error, stack) ->
        text(Exception.format_banner(kind, clean, clean_stack))

      true ->
        nil
    end
  end

  defp rebuilt_crash(_text, _meta), do: nil

  defp crash_kind({:nocatch, value}), do: {:throw, value, withhold(value)}
  defp crash_kind(%{__exception__: true} = error), do: {:error, error, exception(error)}
  defp crash_kind(reason), do: {:exit, reason, reason(reason)}

  # ---------------------------------------------------------------- terms --

  @doc """
  Пометка на месте значения: вид и размер без содержимого. Атомы, числа,
  pid и ссылки остаются как есть — кода билда в них быть не может (атом из
  пользовательского ввода в проекте не создаётся, `AGENTS.md`).
  """
  @spec withhold(term()) :: term()
  def withhold(value)
      when is_atom(value) or is_number(value) or is_pid(value) or is_reference(value) or
             is_port(value),
      do: value

  def withhold(%Phoenix.Socket.Message{topic: topic, event: event, payload: payload}) do
    inner = if is_map(payload) and is_binary(payload["event"]), do: payload["event"]

    what =
      ["%Phoenix.Socket.Message{topic: ", inspect(text(topic)), ", event: ", inspect(text(event))] ++
        if(inner, do: [", payload.event: ", inspect(text(inner))], else: []) ++ ["}"]

    %Withheld{what: IO.iodata_to_binary(what)}
  end

  def withhold(value), do: %Withheld{what: describe(value)}

  defp describe(%module{}), do: "%" <> inspect(module) <> "{}"
  defp describe(map) when is_map(map), do: "map, #{map_size(map)} keys"
  defp describe(binary) when is_binary(binary), do: "binary, #{byte_size(binary)} bytes"

  defp describe(list) when is_list(list) do
    if List.improper?(list), do: "improper list", else: "list, #{length(list)} items"
  end

  defp describe(tuple) when is_tuple(tuple) and tuple_size(tuple) > 0 and is_atom(elem(tuple, 0)),
    do: "{#{inspect(elem(tuple, 0))}, …} of #{tuple_size(tuple)}"

  defp describe(tuple) when is_tuple(tuple), do: "tuple of #{tuple_size(tuple)}"
  defp describe(fun) when is_function(fun), do: inspect(fun)
  defp describe(_other), do: "term"

  # Обход любого значения: строки — через сеть, структура — как была.
  defp term(_value, depth) when depth > @max_depth, do: %Withheld{what: "too deep"}
  defp term(value, _depth) when is_binary(value), do: scrub_maybe_text(value)

  defp term([_ | _] = list, depth) do
    if not List.improper?(list) and charlist_text?(list),
      do: list |> List.to_string() |> scrub_binary() |> String.to_charlist(),
      else: list_term(list, depth)
  end

  defp term(%{__exception__: true} = exception, _depth), do: exception(exception)

  defp term(%module{} = struct, depth) do
    struct
    |> Map.from_struct()
    |> Enum.reduce(struct, fn {key, value}, acc -> Map.put(acc, key, term(value, depth + 1)) end)
    |> Map.put(:__struct__, module)
  end

  defp term(map, depth) when is_map(map),
    do: Map.new(map, fn {k, v} -> {term(k, depth + 1), term(v, depth + 1)} end)

  defp term(tuple, depth) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&term(&1, depth + 1)) |> List.to_tuple()

  defp term(other, _depth), do: other

  defp list_term([head | tail], depth) when is_list(tail),
    do: [term(head, depth + 1) | list_term(tail, depth)]

  defp list_term([head | tail], depth), do: [term(head, depth + 1) | term(tail, depth + 1)]
  defp list_term([], _depth), do: []

  # Код в charlist (`~c"2.…"`) печатается строкой — его ловит та же сеть.
  defp charlist_text?(list), do: length(list) >= 10 and List.ascii_printable?(list)

  defp scrub_maybe_text(binary) do
    if String.valid?(binary), do: scrub_binary(binary), else: binary
  end
end
