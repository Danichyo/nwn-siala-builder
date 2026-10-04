defmodule BuildCalculatorWeb.SourceCyrillic do
  @moduledoc """
  Перепись кириллицы в ИСХОДНИКАХ веб-слоя без комментариев (задача 4.11) —
  счётчик, на котором стоит сторож `BuildCalculatorWeb.CyrillicSourceTest`
  и счёт зоны захода `tools/i18n/census.exs`.

  ## Что считается комментарием (и потому не считается)

  В `.ex` файл разбирается публичным `Code.string_to_quoted/2`, и в счёт идут
  только ЛИТЕРАЛЫ дерева — строки, части интерполяции, содержимое сигилов,
  чарлисты, атомы. Отсюда правило:

    * **Elixir `#`** — в дереве его нет вовсе, разбор отличает его от `#` внутри
      строки сам;
    * **`@moduledoc`, `@doc`, `@typedoc`** — документация модуля, ветка дерева
      пропускается целиком;
    * **`doc:` у `attr`/`slot`** — документация атрибута компонента, та же
      природа, что `@doc`.

  Шаблон HEEx — файл `.heex` целиком или содержимое сигила `~H` — считается
  как текст (подпись, атрибут, строка в выражении `{…}` — всё это видит
  игрок), из которого вынуты:

    * **`<%!-- … --%>`** — комментарий HEEx, в разметку не попадает;
    * **`<!-- … -->`** — HTML-комментарий: в DOM он есть, но на экране — нет;
    * **комментарии JS внутри `<script>`** (колокированные хуки): `// …`
      до конца строки и `/* … */`; строки JS в кавычках `'…'`, `"…"`, `` `…` ``
      остаются в счёте — это текст, который хук может показать;
    * **строка, первый непробельный знак которой `#`** (но не `\#{`), — комментарий
      Elixir внутри многострочного выражения `{…}` или `<% … %>`. В разметке
      строка текста с `#` в начале не встречается; в выражении это ровно
      комментарий, и разбирать HEEx ради него вторым токенизатором незачем.

  Вынутое заменяется своими переводами строк, поэтому номер строки у находки —
  настоящий.

  ## Единица — кириллическое СЛОВО

  Как у en-храповика (`EnGuardTest`): слово — `\\p{Cyrillic}+`, фраза — слова
  подряд через пробелы и знаки препинания. Между литералами фраза рвётся:
  соседние строки кода — разные сообщения.

  У находки есть `where` — где она в модуле: `"имя/арность"` функции,
  `"@атрибут"`, `"module"` (тело модуля вне функций) или `"template"` (файл
  `.heex`). По нему закрытый список «не интерфейс» называет место поимённо.
  """

  @word ~r/\p{Cyrillic}+/u
  @phrase ~r/\p{Cyrillic}+(?:[\s\p{P}]+\p{Cyrillic}+)*/u
  @docs [:moduledoc, :doc, :typedoc]
  @defs [:def, :defp, :defmacro, :defmacrop]

  @typedoc "Одна фраза кириллицы: текст, число слов, строка в файле, место в модуле."
  @type occurrence :: %{
          phrase: String.t(),
          words: pos_integer(),
          line: pos_integer(),
          where: String.t()
        }

  @doc "Файлы веб-слоя, которые читает перепись: `.ex` и `.heex` под `root`."
  @spec files(Path.t()) :: [Path.t()]
  def files(root \\ "lib/build_calculator_web") do
    root |> Path.join("**/*.{ex,heex}") |> Path.wildcard() |> Enum.sort()
  end

  @doc "Все фразы кириллицы файла вне комментариев."
  @spec scan(Path.t()) :: [occurrence()]
  def scan(path), do: scan_source(File.read!(path), Path.extname(path), path)

  @doc """
  То же для исходника строкой — `ext` `".ex"` или `".heex"`. Для синтетики
  (положительный контроль правила комментария) и для `scan/1`.
  """
  @spec scan_source(String.t(), String.t(), Path.t()) :: [occurrence()]
  def scan_source(source, ext, file \\ "nofile")

  def scan_source(source, ".heex", _file), do: heex(source, 1, "template")

  def scan_source(source, ".ex", file) do
    ast =
      Code.string_to_quoted!(source,
        file: file,
        columns: true,
        token_metadata: true,
        literal_encoder: &{:ok, {:__block__, &2, [&1]}}
      )

    ast |> walk("module", []) |> Enum.reverse() |> List.flatten()
  end

  @doc "Кириллических слов в тексте."
  @spec words(String.t()) :: non_neg_integer()
  def words(text), do: @word |> Regex.scan(text) |> length()

  # ------------------------------------------------------------------ Elixir --

  defp walk({:@, _, [{attr, _, _}]}, _where, acc) when attr in @docs, do: acc

  defp walk({:@, _, [{attr, _, value}]}, _where, acc) when is_atom(attr) and is_list(value),
    do: walk(value, "@#{attr}", acc)

  defp walk({kind, _, [head | body]}, _where, acc) when kind in @defs do
    where = def_name(head)
    acc = walk(head, where, acc)
    walk(body, where, acc)
  end

  defp walk({call, meta, args}, where, acc) when call in [:attr, :slot] and is_list(args) do
    walk({:__attr_call__, meta, Enum.map(args, &drop_doc/1)}, where, acc)
  end

  defp walk({:sigil_H, meta, [{:<<>>, _, parts}, _modifiers]}, where, acc) do
    text = Enum.map_join(parts, &(unwrap(&1) |> binary_or_empty()))
    [heex(text, content_line(meta), where) | acc]
  end

  defp walk({:__block__, meta, [literal]}, where, acc)
       when is_binary(literal) or is_atom(literal) or is_list(literal) do
    case literal_text(literal) do
      nil -> walk(literal, where, acc)
      text -> [text(text, content_line(meta), where) | acc]
    end
  end

  defp walk({:<<>>, meta, parts}, where, acc) when is_list(parts) do
    Enum.reduce(parts, acc, fn
      part, acc when is_binary(part) -> [text(part, meta[:line] || 1, where) | acc]
      part, acc -> walk(part, where, acc)
    end)
  end

  defp walk({left, _meta, right}, where, acc) do
    acc = walk(left, where, acc)
    walk(right, where, acc)
  end

  defp walk({left, right}, where, acc), do: walk(right, where, walk(left, where, acc))
  defp walk(list, where, acc) when is_list(list), do: Enum.reduce(list, acc, &walk(&1, where, &2))
  defp walk(_other, _where, acc), do: acc

  defp literal_text(bin) when is_binary(bin), do: bin
  defp literal_text(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp literal_text(list) when is_list(list) do
    if list != [] and Enum.all?(list, &is_integer/1) do
      case :unicode.characters_to_binary(list) do
        bin when is_binary(bin) -> bin
        _ -> nil
      end
    end
  end

  # Содержимое heredoc начинается со СЛЕДУЮЩЕЙ строки после открывающих кавычек.
  defp content_line(meta) do
    line = meta[:line] || 1
    if meta[:delimiter] in [~s("""), "'''"], do: line + 1, else: line
  end

  defp def_name({:when, _, [head | _]}), do: def_name(head)

  defp def_name({name, _, args}) when is_atom(name) and is_list(args),
    do: "#{name}/#{length(args)}"

  defp def_name({name, _, _}) when is_atom(name), do: "#{name}/0"
  defp def_name(_), do: "def"

  defp drop_doc(args) do
    case unwrap(args) do
      list when is_list(list) -> Enum.reject(list, &doc_pair?/1)
      _ -> args
    end
  end

  defp doc_pair?({key, _value}), do: unwrap(key) == :doc
  defp doc_pair?(_), do: false

  defp unwrap({:__block__, _, [literal]}), do: literal
  defp unwrap(other), do: other

  defp binary_or_empty(bin) when is_binary(bin), do: bin
  defp binary_or_empty(_), do: ""

  # -------------------------------------------------------------------- HEEx --

  defp heex(text, line, where) do
    text
    |> blank(~r/<%!--.*?--%>/su)
    |> blank(~r/<!--.*?-->/su)
    |> then(
      &Regex.replace(~r/(<script\b[^>]*>)(.*?)(<\/script>)/su, &1, fn _, open, body, close ->
        open <> strip_js(body) <> close
      end)
    )
    |> blank(~r/^[ \t]*#(?!\{)[^\n]*/mu)
    |> text(line, where)
  end

  # Вынутое заменяется своими переводами строк — номера строк остаются верными.
  defp blank(text, regex), do: Regex.replace(regex, text, &newlines/1)

  defp newlines(text), do: String.duplicate("\n", length(:binary.matches(text, "\n")))

  # Комментарии JS — с учётом кавычек: `//` внутри строки комментарием не считается.
  defp strip_js(js), do: strip_js(js, :code, [])

  defp strip_js(<<>>, _state, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp strip_js(<<"//", rest::binary>>, :code, acc) do
    case :binary.split(rest, "\n") do
      [_comment, tail] -> strip_js(tail, :code, ["\n" | acc])
      [_comment] -> strip_js(<<>>, :code, acc)
    end
  end

  defp strip_js(<<"/*", rest::binary>>, :code, acc) do
    case :binary.split(rest, "*/") do
      [comment, tail] -> strip_js(tail, :code, [newlines(comment) | acc])
      [comment] -> strip_js(<<>>, :code, [newlines(comment) | acc])
    end
  end

  defp strip_js(<<q, rest::binary>>, :code, acc) when q in [?", ?', ?`],
    do: strip_js(rest, {:string, q}, [<<q>> | acc])

  defp strip_js(<<?\\, c::utf8, rest::binary>>, {:string, _} = state, acc),
    do: strip_js(rest, state, [<<?\\, c::utf8>> | acc])

  defp strip_js(<<q, rest::binary>>, {:string, q}, acc), do: strip_js(rest, :code, [<<q>> | acc])

  defp strip_js(<<c::utf8, rest::binary>>, state, acc),
    do: strip_js(rest, state, [<<c::utf8>> | acc])

  defp strip_js(<<byte, rest::binary>>, state, acc), do: strip_js(rest, state, [<<byte>> | acc])

  # ---------------------------------------------------------------- phrases --

  defp text(text, line, where) do
    for [{offset, length}] <- Regex.scan(@phrase, text, return: :index) do
      phrase = text |> binary_part(offset, length) |> String.replace(~r/\s+/u, " ")
      before = binary_part(text, 0, offset)

      %{
        phrase: phrase,
        words: words(phrase),
        line: line + length(:binary.matches(before, "\n")),
        where: where
      }
    end
  end
end
