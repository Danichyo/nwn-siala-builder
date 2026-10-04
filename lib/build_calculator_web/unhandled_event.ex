defmodule BuildCalculatorWeb.UnhandledEvent do
  @moduledoc """
  The last clause of every LiveView's `handle_event/3` (task 4.76): an event
  that no clause of the screen takes is dropped, not crashed on.

  ## Why a clause, and why every screen

  Until 4.76 an event with an unknown name — or a known name with a payload
  none of its clauses matches (`pick_race` without `race`) — raised
  `FunctionClauseError` and took the LiveView process down. The client
  rejoins in a moment, so a player loses nothing they could see, but every
  such event put a crash report of about a kilobyte into the log (measured:
  twenty events — 21 838 bytes), and the log in production is Docker's,
  rotated at 30 MB (`DEPLOY.md`). A hand-made client writes them as fast as it
  can send, and real errors are rotated out under it. Every one of the twelve
  LiveViews went down this way, not only the two the constructor is made of.

  `BuildCalculatorWeb.live_view/0` puts this module's `__before_compile__/1`
  into every LiveView of the web layer, so the clause is the LAST one of
  `handle_event/3` — after every clause the screen declares — and a new screen
  gets it without anyone remembering to.

  ## The price, and what pays it

  A catch-all also swallows a typo: `phx-click="pick_fet"` in a template would
  be dropped silently where it used to crash in the first test that clicked
  it. That is what `live_event_names_test.exs` is for: it reads every event
  name the templates, hooks and `JS.push/2` can send (`LiveEventScan`) and
  checks each against the clauses of the screen that renders it
  (`__handled_events__/0` below). A name without a clause fails the build.

  ## What goes to the log

  One `warning` line per screen per minute at most (`BuildCalculator.RateLimit`),
  and no value from the client in it — the event name is the client's text
  (a hand-made one can be a build code or two megabytes), so it is printed only
  when it is one of the screen's own names (`__handled_events__/0`): then the
  line tells a payload our template sends wrongly from a name nobody sends.
  More often than once a minute it is the same client again, and a line per
  event would rebuild the very flood the clause removes.

  ⚠️ Events named `lv:…` never reach `handle_event/3`: LiveView answers them
  itself and raises on any but `lv:clear-flash`
  (`Phoenix.LiveView.Channel.view_handle_event/3`), before any hook or clause
  of ours. That crash is still possible and is not this module's to remove.
  """

  require Logger

  alias BuildCalculator.RateLimit

  # Не чаще одной строки в минуту на экран.
  @window_seconds 60
  @lines_per_window 1

  @doc false
  defmacro __before_compile__(env) do
    handled = handled_events(env.module)

    quote do
      @doc false
      # Имена событий, у которых в этом экране есть своя клауза
      # `handle_event/3` (задача 4.76, `BuildCalculatorWeb.UnhandledEvent`).
      def __handled_events__, do: unquote(handled)

      @impl true
      def handle_event(event, _params, socket),
        do: BuildCalculatorWeb.UnhandledEvent.ignore(__MODULE__, event, socket)
    end
  end

  @doc """
  The answer of the last clause: the socket untouched, and one warning line
  if this screen has not had one in the current minute.
  """
  @spec ignore(module(), term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def ignore(view, event, socket) do
    {window, expires} = RateLimit.window(System.system_time(:second), @window_seconds)

    case RateLimit.hit({__MODULE__, view, window}, @lines_per_window, expires) do
      {:ok, _count} -> Logger.warning(fn -> line(view, event) end)
      {:limited, _count} -> :ok
    end

    {:noreply, socket}
  end

  @doc false
  # Строка без значений клиента: имя события печатается, только если оно —
  # одно из имён самого экрана.
  @spec line(module(), term()) :: String.t()
  def line(view, event) do
    if is_binary(event) and event in view.__handled_events__() do
      "#{inspect(view)}: event #{inspect(event)} came with a payload no clause of " <>
        "handle_event/3 takes; ignored (more this minute are not logged)"
    else
      "#{inspect(view)}: an event no clause of handle_event/3 takes; ignored " <>
        "(more this minute are not logged)"
    end
  end

  @doc """
  The event names the module's own `handle_event/3` clauses name — read from
  the clauses at compile time.

  A clause names an event by its first argument when that is a string, or by
  a guard that compares the argument with strings (`when event in @names`).
  A clause whose first argument is anything else would take every event; there
  is none in the web layer, and one would make this function raise at compile
  time — the screen would have its own catch-all, and the names this module
  prints and the event guard checks would be wrong.
  """
  @spec handled_events(module()) :: [String.t()]
  def handled_events(module) do
    case Module.get_definition(module, {:handle_event, 3}) do
      nil ->
        []

      {:v1, _kind, _meta, clauses} ->
        clauses
        |> Enum.flat_map(&clause_events(module, &1))
        |> Enum.uniq()
        |> Enum.sort()
    end
  end

  defp clause_events(_module, {_meta, [event | _], _guards, _body}) when is_binary(event),
    do: [event]

  defp clause_events(module, {_meta, [{name, _, context} = var | _], guards, _body})
       when is_atom(name) and is_atom(context) do
    case Enum.flat_map(guards, &guard_names(&1, var)) do
      [] ->
        raise ArgumentError,
              "#{inspect(module)}: a handle_event/3 clause takes any event name; " <>
                "the last clause is BuildCalculatorWeb.UnhandledEvent's"

      names ->
        names
    end
  end

  defp clause_events(module, _clause) do
    raise ArgumentError,
          "#{inspect(module)}: a handle_event/3 clause whose event is neither a string " <>
            "nor a variable compared with strings"
  end

  # `event in ["a", "b"]` в охраннике разворачивается в цепочку
  # `:erlang.orelse(:erlang."=:="(event, "a"), …)`.
  defp guard_names({{:., _, [:erlang, op]}, _, [left, right]}, var)
       when op in [:orelse, :or] do
    guard_names(left, var) ++ guard_names(right, var)
  end

  defp guard_names({{:., _, [:erlang, op]}, _, [left, right]}, var)
       when op in [:"=:=", :==] do
    cond do
      same_var?(left, var) and is_binary(right) -> [right]
      same_var?(right, var) and is_binary(left) -> [left]
      true -> []
    end
  end

  defp guard_names({{:., _, [:erlang, :andalso]}, _, [left, right]}, var),
    do: guard_names(left, var) ++ guard_names(right, var)

  defp guard_names(_guard, _var), do: []

  defp same_var?({name, meta, context}, {name, var_meta, context}),
    do: Keyword.get(meta, :version) == Keyword.get(var_meta, :version)

  defp same_var?(_left, _var), do: false
end
