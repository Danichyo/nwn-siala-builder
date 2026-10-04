defmodule BuildCalculatorWeb.LiveEventScan do
  @moduledoc """
  Which event names each LiveView of the web layer can be sent — read from the
  sources (task 4.76), for `live_event_names_test.exs`.

  Every screen's `handle_event/3` ends in a catch-all that drops an event no
  clause takes (`BuildCalculatorWeb.UnhandledEvent`), so a typo in a template
  no longer crashes the first test that clicks it. This scan is what catches
  the typo instead: every name the browser can send is collected here and must
  have a clause of its own in the screen that renders it.

  ## Where a name comes from

    * `phx-click`, `phx-change`, `phx-submit`, `phx-blur`, `phx-focus`, the key
      and window bindings — a literal value, or the strings at the value
      positions of an expression (`{@ready && "select_level"}`,
      `{if(…, do: "a", else: "b")}`), or `JS.push/1,2` inside it;
    * `JS.push/1,2` anywhere in a module's code (a helper that returns a JS
      command: `gear_issue_jump/1`);
    * `this.pushEvent(…)` / `pushEventTo(…)` in a colocated hook's `<script>` —
      counted for every function of the module that names the hook
      (`phx-hook=".X"`) and for the one that holds the script;
    * an attribute of a function component that the component uses as an event
      (`phx-click={@toggle_event}`, `"phx-click": @drop_event`, or passed on to
      another component's event attribute) — the literal value at the call
      site (`toggle_event="toggle_gear_feat_add"`).

  ## Whose name it is

  A LiveView module owns every name in its own code and in its colocated
  `.html.heex`. A function component's names go to the screens that call it —
  `<.name>` resolved through the module's own functions and its imports,
  `<Alias.name>` through the scanned modules — and on through the components
  it calls. A tag that resolves nowhere and is not one of Phoenix's own
  components stops the scan (`ArgumentError`): a name the scan cannot place is
  a name the guard would miss.

  `pushEvent` in `assets/js` (hooks outside the templates) is not attributed —
  there is none; one would stop the scan the same way.
  """

  @event_bindings ~w(click change submit blur focus keydown keyup window-keydown
                     window-keyup window-blur window-focus click-away capture-click
                     viewport-top viewport-bottom)

  @binding_alt Enum.map_join(@event_bindings, "|", &Regex.escape/1)

  # Компоненты Phoenix, у которых своих событий нет.
  @phoenix_components ~w(link form inputs_for live_title focus_wrap dynamic_tag
                         live_file_input live_img_preview async_result intersperse portal
                         live_component)a

  @typedoc "One function of a scanned module."
  @type fun_info :: %{
          events: MapSet.t(String.t()),
          event_attrs: MapSet.t(atom()),
          hooks: MapSet.t(String.t()),
          tags: [{:local | {:remote, String.t()}, atom(), [{atom(), term()}]}],
          calls: MapSet.t(atom())
        }

  @doc """
  Reads the web layer from disk: every `.ex` under `lib/build_calculator_web`
  and each LiveView's colocated `.html.heex`. `overrides` replaces the text of
  a file by its path — the guard's positive controls plant a name in a real
  template without touching the file.
  """
  @spec read_sources(%{optional(String.t()) => String.t()}) :: [{String.t(), String.t()}]
  def read_sources(overrides \\ %{}) do
    root = File.cwd!()

    files =
      Path.wildcard(Path.join(root, "lib/build_calculator_web/**/*.{ex,heex}")) ++
        [Path.join(root, "lib/build_calculator_web.ex")]

    for path <- Enum.uniq(files) do
      relative = Path.relative_to(path, root)
      {relative, Map.get_lazy(overrides, relative, fn -> File.read!(path) end)}
    end
  end

  @doc """
  Scans `{path, text}` pairs. Returns `%{module => %{functions: …, imports: …,
  aliases: …}}` for every module found in the `.ex` texts; a `.html.heex`
  next to a `.ex` becomes that module's `:render` function.
  """
  @spec scan([{String.t(), String.t()}]) :: map()
  def scan(sources) do
    {ex, heex} = Enum.split_with(sources, fn {path, _} -> String.ends_with?(path, ".ex") end)

    units =
      for {path, text} <- ex, unit <- modules(path, text), into: %{} do
        {unit.module, unit}
      end

    Enum.reduce(heex, units, fn {path, text}, units ->
      owner = String.replace_suffix(path, ".html.heex", ".ex")

      case Enum.find(Map.values(units), &(&1.path == owner)) do
        nil ->
          units

        unit ->
          render = template_info(text, [])
          functions = Map.update(unit.functions, :render, render, &merge_info(&1, render))
          Map.put(units, unit.module, %{unit | functions: functions})
      end
    end)
  end

  @doc """
  The event names `module` can be sent, as `%{name => [where]}` — `where` is
  `{module, function}` of the template the name was read from.
  """
  @spec emitted(map(), module()) :: %{String.t() => [{module(), atom()}]}
  def emitted(units, module) do
    unit = Map.fetch!(units, module)
    event_attrs = event_attrs(units)

    roots = for {name, _info} <- unit.functions, do: {module, name}

    {_seen, found} = walk(roots, units, event_attrs, MapSet.new(), %{})
    found
  end

  @doc """
  Names a LiveView can be sent that no clause of its own takes: `emitted/2`
  minus `handled`. `[]` is the guard's pass.
  """
  @spec unhandled(map(), module(), [String.t()]) :: [{String.t(), [{module(), atom()}]}]
  def unhandled(units, module, handled) do
    handled = MapSet.new(handled)

    units
    |> emitted(module)
    |> Enum.reject(fn {name, _where} -> MapSet.member?(handled, name) end)
    |> Enum.sort()
  end

  @doc "`pushEvent` calls in `assets/js` — the guard expects none."
  @spec asset_push_events(String.t()) :: [String.t()]
  def asset_push_events(dir \\ "assets/js") do
    for path <- Path.wildcard(Path.join(dir, "**/*.{js,mjs,ts}")),
        text = File.read!(path),
        Regex.match?(~r/\bpushEvent(To)?\s*\(/, text),
        do: path
  end

  # ----------------------------------------------------------------- walk --

  defp walk([], _units, _attrs, seen, found), do: {seen, found}

  defp walk([{module, name} = key | rest], units, attrs, seen, found) do
    if MapSet.member?(seen, key) do
      walk(rest, units, attrs, seen, found)
    else
      unit = Map.fetch!(units, module)
      info = Map.fetch!(unit.functions, name)
      hook_events = hook_events(unit, info)

      own =
        info.events
        |> MapSet.union(hook_events)
        |> MapSet.union(call_site_events(unit, info, units, attrs))

      found =
        Enum.reduce(own, found, fn event, acc ->
          Map.update(acc, event, [key], &Enum.uniq([key | &1]))
        end)

      callees =
        for {kind, tag, _attrs} <- info.tags,
            target = resolve(unit, kind, tag, units),
            target != :phoenix,
            do: target

      local = for call <- info.calls, Map.has_key?(unit.functions, call), do: {module, call}

      remote =
        for {parts, fun} <- info.remote,
            target = remote_module(unit, parts),
            defines?(units, target, fun),
            do: {target, fun}

      walk(callees ++ local ++ remote ++ rest, units, attrs, MapSet.put(seen, key), found)
    end
  end

  # Литералы атрибутов-событий на месте вызова: `toggle_event="…"` у тега,
  # который разрешается в компонент с таким атрибутом-событием.
  defp call_site_events(unit, info, units, attrs) do
    for {kind, tag, tag_attrs} <- info.tags,
        target = resolve(unit, kind, tag, units),
        target != :phoenix,
        {attr, value} <- tag_attrs,
        MapSet.member?(Map.get(attrs, target, MapSet.new()), attr),
        event <- value_events(value),
        into: MapSet.new(),
        do: event
  end

  defp value_events({:literal, value}), do: [value]
  defp value_events({:expr, events}), do: events

  # `attr={@attr}` — передача дальше: имя придёт литералом у вызова выше.
  defp value_events({:assign, _assign}), do: []

  # События хуков: скрипты самой функции и скрипты хуков, которые функция
  # называет (`phx-hook=".X"`), где бы в модуле ни лежал `<script name=".X">`.
  defp hook_events(unit, info) do
    named =
      for hook <- info.hooks,
          {_name, other} <- unit.functions,
          event <- Map.get(other.scripts, hook, []),
          do: event

    own = info.scripts |> Map.values() |> List.flatten()

    MapSet.new(named ++ own)
  end

  # Атрибуты-события компонента — неподвижная точка: свой `phx-…={@attr}`
  # и передача `@attr` в атрибут-событие другого компонента.
  defp event_attrs(units) do
    direct =
      for {module, unit} <- units, {name, info} <- unit.functions, into: %{} do
        {{module, name}, info.event_attrs}
      end

    fixpoint(units, direct)
  end

  defp fixpoint(units, attrs) do
    next =
      for {module, unit} <- units, {name, info} <- unit.functions, into: %{} do
        passed =
          for {kind, tag, tag_attrs} <- info.tags,
              target = resolve(unit, kind, tag, units),
              target != :phoenix,
              {attr, {:assign, assign}} <- tag_attrs,
              MapSet.member?(Map.get(attrs, target, MapSet.new()), attr),
              into: MapSet.new(),
              do: assign

        {{module, name}, MapSet.union(Map.fetch!(attrs, {module, name}), passed)}
      end

    if next == attrs, do: attrs, else: fixpoint(units, next)
  end

  defp resolve(unit, :local, tag, units) do
    cond do
      Map.has_key?(unit.functions, tag) ->
        {unit.module, tag}

      target = Enum.find(unit.imports, &defines?(units, &1, tag)) ->
        {target, tag}

      tag in @phoenix_components ->
        :phoenix

      true ->
        raise ArgumentError, "#{inspect(unit.module)}: <.#{tag}> resolves to no component"
    end
  end

  defp resolve(unit, {:remote, alias_text}, tag, units) do
    module =
      Map.get(unit.aliases, alias_text) ||
        Enum.find(Map.keys(units), &(inspect(&1) == alias_text)) ||
        raise ArgumentError, "#{inspect(unit.module)}: <#{alias_text}.#{tag}> — unknown module"

    if defines?(units, module, tag) do
      {module, tag}
    else
      raise ArgumentError, "#{inspect(unit.module)}: <#{alias_text}.#{tag}> resolves to nothing"
    end
  end

  # `Alias.Rest` → модуль: первый сегмент — алиас модуля, иначе имя целиком.
  defp remote_module(unit, [first | rest] = parts) do
    case Map.get(unit.aliases, Atom.to_string(first)) do
      nil -> Module.concat(parts)
      module -> Module.concat([module | rest])
    end
  end

  defp defines?(units, module, tag) do
    case Map.get(units, module) do
      nil -> false
      unit -> Map.has_key?(unit.functions, tag)
    end
  end

  # -------------------------------------------------------------- modules --

  defp modules(path, text) do
    ast = Code.string_to_quoted!(text, file: path, columns: true)

    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [{:__aliases__, _, parts}, [do: body]]} = node, acc ->
          {node, [{Module.concat(parts), body} | acc]}

        node, acc ->
          {node, acc}
      end)

    for {module, body} <- acc do
      %{
        module: module,
        path: path,
        functions: functions(body),
        imports: imports(body, text),
        aliases: aliases(body)
      }
    end
  end

  defp functions(body) do
    {_ast, acc} =
      Macro.prewalk(body, %{}, fn
        {:defmodule, _, _}, acc ->
          {nil, acc}

        {kind, _meta, [head | rest]} = node, acc when kind in [:def, :defp] ->
          case fun_name(head) do
            nil ->
              {node, acc}

            name ->
              info = fun_info(rest)
              {node, Map.update(acc, name, info, &merge_info(&1, info))}
          end

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp fun_name({:when, _, [head | _]}), do: fun_name(head)
  defp fun_name({name, _, args}) when is_atom(name) and is_list(args), do: name
  defp fun_name(_head), do: nil

  defp fun_info(body) do
    templates = sigils(body)
    pushes = js_pushes(body)
    keywords = keyword_events(body)
    calls = local_calls(body)

    info =
      Enum.reduce(templates, empty_info(), fn template, acc ->
        merge_info(acc, template_info(template, []))
      end)

    %{
      info
      | events: info.events |> MapSet.union(pushes) |> MapSet.union(keywords),
        calls: MapSet.union(info.calls, calls),
        remote: Enum.uniq(info.remote ++ remote_calls(body))
    }
  end

  # Атрибуты, собранные в коде: `["phx-click": "pick_gear_weapon", …]`
  # (`Builder.GearPanel`), раскрываемые потом в шаблоне `{@attrs}`.
  defp keyword_events(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, MapSet.new(), fn
        {key, event} = node, acc when is_atom(key) and is_binary(event) ->
          if event_binding?(key), do: {node, MapSet.put(acc, event)}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp event_binding?(key) do
    case Atom.to_string(key) do
      "phx-" <> binding -> binding in @event_bindings
      _other -> false
    end
  end

  # Вызовы `Alias.fun(…)` и захваты `&Alias.fun/1` — обход идёт и по ним:
  # помощник другого модуля может вернуть атрибуты с событием.
  defp remote_calls(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, parts}, fun]}, _, args} = node, acc
        when is_atom(fun) and is_list(args) ->
          {node, [{parts, fun} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(acc)
  end

  defp empty_info do
    %{
      events: MapSet.new(),
      event_attrs: MapSet.new(),
      hooks: MapSet.new(),
      scripts: %{},
      tags: [],
      calls: MapSet.new(),
      remote: []
    }
  end

  defp merge_info(a, b) do
    %{
      events: MapSet.union(a.events, b.events),
      event_attrs: MapSet.union(a.event_attrs, b.event_attrs),
      hooks: MapSet.union(a.hooks, b.hooks),
      scripts: Map.merge(a.scripts, b.scripts, fn _k, x, y -> Enum.uniq(x ++ y) end),
      tags: a.tags ++ b.tags,
      calls: MapSet.union(a.calls, b.calls),
      remote: Enum.uniq(a.remote ++ b.remote)
    }
  end

  defp sigils(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {:sigil_H, _, [{:<<>>, _, parts}, _mods]} = node, acc ->
          {node, [Enum.map_join(parts, &if(is_binary(&1), do: &1, else: "")) | acc]}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp js_pushes(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, MapSet.new(), fn
        {{:., _, [{:__aliases__, _, alias_parts}, :push]}, _, args} = node, acc ->
          if List.last(alias_parts) == :JS do
            {node, Enum.reduce(push_name(args), acc, &MapSet.put(&2, &1))}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # `JS.push("e")`, `JS.push("e", opts)`, `JS.push(js, "e")`, `JS.push(js, "e", opts)`.
  defp push_name([event | _]) when is_binary(event), do: [event]
  defp push_name([_js, event | _]) when is_binary(event), do: [event]
  defp push_name(_args), do: []

  defp local_calls(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, MapSet.new(), fn
        {name, _meta, args} = node, acc when is_atom(name) and is_list(args) ->
          {node, MapSet.put(acc, name)}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp imports(body, text) do
    explicit =
      for {:import, _, [{:__aliases__, _, parts} | _]} <- flatten(body),
          do: Module.concat(parts)

    helpers =
      if Regex.match?(~r/use BuildCalculatorWeb,\s*:(html|live_view|live_component)\b/, text),
        do: [BuildCalculatorWeb.CoreComponents],
        else: []

    explicit ++ helpers
  end

  defp aliases(body) do
    base = %{"Layouts" => BuildCalculatorWeb.Layouts}

    Enum.reduce(flatten(body), base, fn
      {:alias, _, [{:__aliases__, _, parts}]}, acc ->
        Map.put(acc, parts |> List.last() |> Atom.to_string(), Module.concat(parts))

      {:alias, _, [{:__aliases__, _, parts}, [as: {:__aliases__, _, [as]}]]}, acc ->
        Map.put(acc, Atom.to_string(as), Module.concat(parts))

      {:alias, _, [{{:., _, [{:__aliases__, _, prefix}, :{}]}, _, children}]}, acc ->
        Enum.reduce(children, acc, fn {:__aliases__, _, parts}, acc ->
          Map.put(acc, parts |> List.last() |> Atom.to_string(), Module.concat(prefix ++ parts))
        end)

      _node, acc ->
        acc
    end)
  end

  defp flatten(ast) do
    {_ast, acc} = Macro.prewalk(ast, [], fn node, acc -> {node, [node | acc]} end)
    acc
  end

  # ------------------------------------------------------------- template --

  @doc false
  # Разбор одного шаблона: события, атрибуты-события, хуки, скрипты, теги.
  def template_info(text, _opts) do
    text = Regex.replace(~r/<%!--.*?--%>/s, text, "")
    {markup, scripts} = split_scripts(text)

    literal =
      for [_, value] <- Regex.scan(~r/\bphx-(?:#{@binding_alt})="([^"]*)"/, markup),
          value != "",
          do: value

    {dynamic, dynamic_attrs, dynamic_calls} =
      Regex.scan(~r/\bphx-(?:#{@binding_alt})=\{/, markup, return: :index)
      |> Enum.reduce({[], [], []}, fn [{at, length}], {events, attrs, calls} ->
        expr = balanced(markup, at + length)
        {e, a, c} = expr_events(expr)
        {e ++ events, a ++ attrs, c ++ calls}
      end)

    keyword_literals =
      for [_, value] <- Regex.scan(~r/"phx-(?:#{@binding_alt})":\s*"([^"]+)"/, markup), do: value

    keyword_attrs =
      for [_, attr] <- Regex.scan(~r/"phx-(?:#{@binding_alt})":\s*@(\w+)/, markup),
          do: String.to_atom(attr)

    hooks =
      for [_, hook] <- Regex.scan(~r/\bphx-hook="(\.[A-Za-z0-9_]+)"/, markup),
          into: MapSet.new(),
          do: hook

    %{
      events: MapSet.new(literal ++ dynamic ++ keyword_literals),
      event_attrs: MapSet.new(dynamic_attrs ++ keyword_attrs),
      hooks: hooks,
      scripts: scripts,
      tags: tags(markup),
      calls: MapSet.new(dynamic_calls),
      remote: []
    }
  end

  defp split_scripts(text) do
    scripts =
      for [tag, body] <-
            Regex.scan(~r/<script\b([^>]*)>(.*?)<\/script>/s, text, capture: :all_but_first),
          into: %{} do
        name =
          case Regex.run(~r/\bname="(\.[A-Za-z0-9_]+)"/, tag) do
            [_, name] -> name
            nil -> :anonymous
          end

        {name, push_events_js(body)}
      end

    {Regex.replace(~r/<script\b[^>]*>.*?<\/script>/s, text, ""), scripts}
  end

  defp push_events_js(js) do
    direct = for [_, _q, name] <- Regex.scan(~r/\bpushEvent\(\s*(["'`])([^"'`]+)\1/, js), do: name

    to =
      for [_, _q, name] <- Regex.scan(~r/\bpushEventTo\([^,]+,\s*(["'`])([^"'`]+)\1/, js),
          do: name

    direct ++ to
  end

  # Выражение `{…}` после `=`: до парной скобки, с учётом строк.
  defp balanced(text, from), do: balanced(text, from, 1, false, [])

  defp balanced(text, at, depth, in_string, acc) do
    case binary_part(text, at, 1) do
      "\"" ->
        balanced(text, at + 1, depth, not in_string, ["\"" | acc])

      "\\" when in_string ->
        balanced(text, at + 2, depth, in_string, [binary_part(text, at, 2) | acc])

      "{" when not in_string ->
        balanced(text, at + 1, depth + 1, in_string, ["{" | acc])

      "}" when not in_string and depth == 1 ->
        acc |> Enum.reverse() |> IO.iodata_to_binary()

      "}" when not in_string ->
        balanced(text, at + 1, depth - 1, in_string, ["}" | acc])

      char ->
        balanced(text, at + 1, depth, in_string, [char | acc])
    end
  end

  # Строки на месте значения, атрибуты `@x` на месте значения, локальные
  # вызовы (помощник, возвращающий `JS.push`).
  defp expr_events(expr) do
    case Code.string_to_quoted(expr) do
      {:ok, ast} -> value_positions(ast)
      {:error, _} -> raise ArgumentError, "phx binding expression does not parse: #{expr}"
    end
  end

  defp value_positions(event) when is_binary(event), do: {[event], [], []}

  defp value_positions({:@, _, [{attr, _, _}]}) when is_atom(attr), do: {[], [attr], []}

  defp value_positions({op, _, [_left, right]}) when op in [:&&, :and],
    do: value_positions(right)

  defp value_positions({op, _, [left, right]}) when op in [:||, :or, :|>],
    do: join(value_positions(left), value_positions(right))

  defp value_positions({:if, _, [_cond, branches]}) when is_list(branches),
    do:
      branches
      |> Keyword.values()
      |> Enum.map(&value_positions/1)
      |> Enum.reduce({[], [], []}, &join/2)

  defp value_positions({kind, _, [_subject, [do: clauses]]}) when kind in [:case, :cond],
    do:
      clauses
      |> Enum.map(fn {:->, _, [_, value]} -> value_positions(value) end)
      |> Enum.reduce({[], [], []}, &join/2)

  defp value_positions({{:., _, [{:__aliases__, _, parts}, :push]}, _, args}) do
    if List.last(parts) == :JS, do: {push_name(args), [], []}, else: {[], [], []}
  end

  defp value_positions({{:., _, [{:__aliases__, _, _parts}, _fun]}, _, _args}),
    do: {[], [], []}

  defp value_positions({name, _, args}) when is_atom(name) and is_list(args),
    do: {[], [], [name]}

  defp value_positions(_other), do: {[], [], []}

  defp join({a1, b1, c1}, {a2, b2, c2}), do: {a1 ++ a2, b1 ++ b2, c1 ++ c2}

  # Теги компонентов: `<.name …>` и `<Alias.name …>` с атрибутами
  # `name="литерал"` и `name={выражение}`.
  @tag ~r/<(?:([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)\.|\.)([a-z_][A-Za-z0-9_]*)/

  defp tags(markup) do
    for [{at, _len}, alias_index, {name_at, name_len}] <- Regex.scan(@tag, markup, return: :index) do
      name = markup |> binary_part(name_at, name_len) |> String.to_atom()

      kind =
        case alias_index do
          {alias_at, alias_len} when alias_at >= 0 ->
            {:remote, binary_part(markup, alias_at, alias_len)}

          _unmatched ->
            :local
        end

      {kind, name, tag_attrs(markup, at + 1)}
    end
  end

  defp tag_attrs(markup, from) do
    head = tag_head(markup, from, 0, false, [])

    literal =
      for [_, attr, value] <- Regex.scan(~r/\s([a-z_][A-Za-z0-9_]*)="([^"]*)"/, head),
          do: {String.to_atom(attr), {:literal, value}}

    dynamic =
      for [{_, _}, {attr_at, attr_len}, {open_at, open_len}] <-
            Regex.scan(~r/\s([a-z_][A-Za-z0-9_]*)=(\{)/, head, return: :index) do
        attr = head |> binary_part(attr_at, attr_len) |> String.to_atom()
        expr = balanced(head, open_at + open_len)

        case expr |> String.trim() |> Code.string_to_quoted() do
          {:ok, {:@, _, [{assign, _, _}]}} when is_atom(assign) -> {attr, {:assign, assign}}
          {:ok, ast} -> {attr, {:expr, ast |> value_positions() |> elem(0)}}
          {:error, _} -> {attr, {:expr, []}}
        end
      end

    literal ++ dynamic
  end

  # Голова тега — до `>` вне строк и выражений.
  defp tag_head(text, at, depth, in_string, acc) do
    if at >= byte_size(text) do
      acc |> Enum.reverse() |> IO.iodata_to_binary()
    else
      case binary_part(text, at, 1) do
        "\"" -> tag_head(text, at + 1, depth, not in_string, ["\"" | acc])
        "{" when not in_string -> tag_head(text, at + 1, depth + 1, in_string, ["{" | acc])
        "}" when not in_string -> tag_head(text, at + 1, depth - 1, in_string, ["}" | acc])
        ">" when not in_string and depth == 0 -> acc |> Enum.reverse() |> IO.iodata_to_binary()
        char -> tag_head(text, at + 1, depth, in_string, [char | acc])
      end
    end
  end
end
