defmodule BuildCalculatorWeb.InputMaxlengthSourceTest do
  @moduledoc """
  Сторож задачи 4.41: у каждого текстового поля веб-слоя, чьё значение уходит
  на сервер, в разметке стоит `maxlength`.

  Без него законный ввод достаёт до потолка сообщения сокета
  (`BuildCalculatorWeb.Endpoint.max_message_bytes/0`): вставка в поле поиска
  в 300 000 знаков «漢» — 2,7 МБ, и сервер рвёт соединение. Числа полей —
  `BuildCalculatorWeb.InputLimits`.

  Читаются сами исходники `lib/build_calculator_web/**/*.{ex,heex}` — шаблоны
  `.heex` целиком и блоки `~H` в `.ex`, без комментариев `<%!-- --%>`,
  `<!-- -->` и без `<script>` хуков. Отрисовку тех же полей проверяет
  `InputLimitsLiveTest`; здесь — и те, до которых ни одно состояние теста
  не доходит.

  **Что считается полем:** `<textarea>`, `<.input type="textarea">` и `<input>`
  или `<.input>` текстового типа (тип не указан — текст) с `name` или `field`.
  Не считаются: поле без имени (браузер его не шлёт — `#share-link`),
  `number` (атрибута `maxlength` у него нет по HTML, браузер его не читает),
  `hidden`, флажки, переключатели, кнопки, `select`. Тип, вычисляемый
  выражением, считается текстовым — сторож строже, а не слепее.

  `core_components.ex` не читается: его `<.input>` — общий компонент, он
  передаёт `maxlength` от звавшего через `@rest`.
  """
  use ExUnit.Case, async: true

  @root "lib/build_calculator_web"
  @skip ["components/core_components.ex"]
  @not_text ~w(hidden checkbox radio number range color date datetime-local month week time
               file submit button reset image select)

  test "у каждого текстового поля веб-слоя есть maxlength" do
    files =
      for path <- Path.wildcard(Path.join(@root, "**/*.{ex,heex}")),
          Path.relative_to(path, @root) not in @skip,
          do: path

    fields = Enum.flat_map(files, fn path -> path |> File.read!() |> fields(path) end)

    # положительный контроль охвата: поля нашлись, и среди них оба окна вставки
    assert length(fields) >= 20
    assert Enum.any?(fields, &(&1.tag =~ ~s(id="import-text")))
    assert Enum.any?(fields, &(&1.tag =~ ~s(id="game-log-import-text")))

    missing = for f <- fields, not f.maxlength?, do: "#{f.file}:#{f.line}  #{f.head}"
    assert missing == [], "поля без maxlength:\n" <> Enum.join(missing, "\n")
  end

  # Положительный контроль самого разбора — на синтетических исходниках.
  describe "разбор" do
    test "поле без maxlength названо, с ним — нет" do
      heex = """
      <input type="search" name="q" phx-change={@x} />
      <.input field={@f[:name]} type="text" maxlength="80" />
      <.input field={@f[:body]} type="textarea" />
      <textarea name="t" maxlength={InputLimits.import_text()}></textarea>
      <input name="plain" />
      """

      got = for f <- fields(heex, "x.heex"), not f.maxlength?, do: f.line
      assert got == [1, 3, 5]
    end

    test "не поля: без имени, number, hidden, флажок, select" do
      heex = """
      <input type="text" id="share-link" value={@url} readonly />
      <input type="number" name="n" value={@n} />
      <input type="hidden" name="h" value="1" />
      <input type="checkbox" name="c" />
      <.input field={@f[:kind]} type="select" options={@o} />
      """

      assert fields(heex, "x.heex") == []
    end

    test "комментарии и скрипты не читаются, в .ex — только ~H" do
      ex = ~S'''
      defmodule X do
        # <input name="in_comment" />
        @doc "<input name=\"in_doc\" />"
        def a(assigns) do
          ~H"""
          <%!-- <input name="in_heex_comment" /> --%>
          <!-- <textarea name="in_html_comment"></textarea> -->
          <script :type={Phoenix.LiveView.ColocatedHook} name=".H">
            const s = '<input name="in_script">'
          </script>
          <input name="real" />
          """
        end
      end
      '''

      assert [%{line: 11, maxlength?: false}] = fields(ex, "x.ex")
    end

    test "выражение в атрибуте с `>` и вложенными скобками не обрывает тег" do
      heex = """
      <input
        name="q"
        value={if(@a > 1, do: %{x: 1}[:x], else: 2)}
        maxlength={@m}
      />
      """

      assert [%{maxlength?: true}] = fields(heex, "x.heex")
    end
  end

  # ------------------------------------------------------------------ разбор --

  defp fields(source, file) do
    for {markup, offset} <- markup_blocks(source, file),
        {start, len} <- tag_starts(markup),
        tag = tag_text(markup, start, len),
        field?(tag) do
      line = offset + count_lines(binary_part(markup, 0, start))

      %{
        file: file,
        line: line,
        tag: tag,
        head:
          tag |> String.split("\n") |> Enum.map_join(" ", &String.trim/1) |> String.slice(0, 120),
        maxlength?: Regex.match?(~r/(?<![\w-])maxlength=/, tag)
      }
    end
  end

  # Разметка файла: `.heex` — весь файл, `.ex` — тела `~H"""…"""` с номером строки
  # их начала. Комментарии и `<script>` заменяются пробелами с теми же переводами
  # строк, чтобы номера строк остались верными.
  defp markup_blocks(source, file) do
    blocks =
      if String.ends_with?(file, ".heex") do
        [{source, 1}]
      else
        for [{from, len}] <-
              Regex.scan(~r/~H"""(.*?)"""/s, source, return: :index, capture: :all_but_first) do
          {binary_part(source, from, len), count_lines(binary_part(source, 0, from)) + 1}
        end
      end

    for {markup, line} <- blocks, do: {blank_out(markup), line}
  end

  defp blank_out(markup) do
    Enum.reduce([~r/<%!--.*?--%>/s, ~r/<!--.*?-->/s, ~r/<script\b.*?<\/script>/s], markup, fn re,
                                                                                              acc ->
      Regex.replace(re, acc, fn match -> String.replace(match, ~r/[^\n]/, " ") end)
    end)
  end

  defp tag_starts(markup),
    do:
      Regex.scan(~r/<(?:input|\.input|textarea)(?=[\s\/>])/, markup, return: :index)
      |> List.flatten()

  # Текст тега до его `>`, не считая `>` внутри `{…}` и кавычек.
  defp tag_text(markup, start, _len) do
    rest = binary_part(markup, start, byte_size(markup) - start)
    size = tag_end(rest, 0, 0, nil)
    binary_part(rest, 0, size)
  end

  defp tag_end(<<>>, at, _depth, _quote), do: at

  defp tag_end(<<q, rest::binary>>, at, depth, q) when q in [?", ?'],
    do: tag_end(rest, at + 1, depth, nil)

  defp tag_end(<<_, rest::binary>>, at, depth, q) when q != nil,
    do: tag_end(rest, at + 1, depth, q)

  defp tag_end(<<q, rest::binary>>, at, depth, nil) when q in [?", ?'],
    do: tag_end(rest, at + 1, depth, q)

  defp tag_end(<<?{, rest::binary>>, at, depth, nil), do: tag_end(rest, at + 1, depth + 1, nil)
  defp tag_end(<<?}, rest::binary>>, at, depth, nil), do: tag_end(rest, at + 1, depth - 1, nil)
  defp tag_end(<<?>, _rest::binary>>, at, 0, nil), do: at + 1
  defp tag_end(<<_, rest::binary>>, at, depth, nil), do: tag_end(rest, at + 1, depth, nil)

  defp field?(tag) do
    named? = Regex.match?(~r/(?<![\w-])(name|field)=/, tag)
    named? and text_type?(tag)
  end

  defp text_type?("<textarea" <> _), do: true

  defp text_type?(tag) do
    case Regex.run(~r/(?<![\w-])type="([^"]*)"/, tag, capture: :all_but_first) do
      [type] -> type not in @not_text
      nil -> true
    end
  end

  defp count_lines(text), do: text |> :binary.matches("\n") |> length()
end
