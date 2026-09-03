defmodule Mix.Tasks.Code.Comments do
  @shortdoc "Считает строки комментариев и документации по файлам (сторож рефакторинга)"

  @moduledoc """
  Сколько в коде объяснений, и не уносит ли их правка.

      mix code.comments                     # весь lib/, по файлам
      mix code.comments lib/build_calculator/data
      mix code.comments --top 15            # только самые густые файлы
      mix code.comments --total             # одна строка итога

  Задача 3.46: комментарии здесь — **актив, а не шум**. В `loader.ex` их 36%, и
  это цитаты источников с датами замеров, отвергнутые альтернативы и предупреждения
  «не чини это обратно». Заход, который «почистит» их заодно с кодом, выглядит
  успешным ровно до первого вопроса «а почему тут так».

  ⚠️ Это **повод посмотреть, а не запрет**. Слияние двух копий одного читателя
  законно уносит второй экземпляр одного и того же комментария, и число упадёт
  без потери смысла. Инструмент отвечает на «сколько унесли», а «правильно ли» —
  вопрос к глазам.

  Считаются две разные вещи, и они не смешиваются в одно число:

    * `#` — строка-комментарий (символ первый в строке после отступа);
    * `@doc` — строка внутри heredoc'а `@moduledoc` / `@doc` / `@typedoc`.

  ⚠️ Счёт приблизительный по построению, и приблизителен он в одну сторону:
  комментарий в конце строки кода (`x = 1 # почему`) не считается вовсе, а `#`
  внутри строкового литерала посчитается комментарием. Для вопроса «сколько
  строк объяснений было до правки и сколько стало» этого достаточно; для любого
  другого — нет.
  """

  use Mix.Task

  @doc_start ~r/^\s*@(module|type)?doc\s+(~[a-zA-Z])?"""/
  @heredoc_end ~r/^\s*"""/
  @comment ~r/^\s*#/

  @impl Mix.Task
  def run(args) do
    {opts, paths, _invalid} =
      OptionParser.parse(args, strict: [top: :integer, total: :boolean])

    roots = if paths == [], do: ["lib"], else: paths

    rows =
      roots |> Enum.flat_map(&files/1) |> Enum.map(&count/1) |> Enum.sort_by(& &1.comment, :desc)

    unless opts[:total] do
      rows
      |> then(fn rows -> if opts[:top], do: Enum.take(rows, opts[:top]), else: rows end)
      |> Enum.each(&Mix.shell().info(row(&1)))
    end

    Mix.shell().info(row(total(rows, roots)))
  end

  defp files(root) do
    cond do
      File.dir?(root) ->
        root
        |> Path.join("**/*.{ex,exs}")
        |> Path.wildcard()
        |> Enum.sort()

      File.regular?(root) ->
        [root]

      true ->
        Mix.raise("нет такого пути: #{root}")
    end
  end

  defp count(path) do
    {comment, doc, blank, _} =
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.reduce({0, 0, 0, false}, &tally/2)

    lines = path |> File.read!() |> String.split("\n") |> length()

    %{
      path: path,
      lines: lines,
      comment: comment,
      doc: doc,
      blank: blank,
      code: lines - comment - doc - blank
    }
  end

  defp tally(line, {comment, doc, blank, in_doc?}) do
    cond do
      in_doc? and Regex.match?(@heredoc_end, line) -> {comment, doc + 1, blank, false}
      in_doc? -> {comment, doc + 1, blank, true}
      Regex.match?(@doc_start, line) -> {comment, doc + 1, blank, true}
      Regex.match?(@comment, line) -> {comment + 1, doc, blank, false}
      String.trim(line) == "" -> {comment, doc, blank + 1, false}
      true -> {comment, doc, blank, false}
    end
  end

  defp total(rows, roots) do
    Enum.reduce(rows, %{path: "ИТОГО #{Enum.join(roots, " ")} (#{length(rows)} файлов)"}, fn row,
                                                                                             acc ->
      Enum.reduce([:lines, :comment, :doc, :blank, :code], acc, fn key, acc ->
        Map.update(acc, key, Map.fetch!(row, key), &(&1 + Map.fetch!(row, key)))
      end)
    end)
  end

  defp row(%{lines: 0} = row), do: "#{row.path}: пусто"

  defp row(row) do
    share = round(100 * (row.comment + row.doc) / row.lines)

    [
      String.pad_trailing(row.path, 56),
      String.pad_leading("#{row.lines}", 7),
      " строк | # ",
      String.pad_leading("#{row.comment}", 6),
      " | @doc ",
      String.pad_leading("#{row.doc}", 6),
      " | код ",
      String.pad_leading("#{row.code}", 6),
      " | объяснений ",
      String.pad_leading("#{share}", 3),
      "%"
    ]
    |> IO.iodata_to_binary()
  end
end
