defmodule BuildCalculator.Data.RulesetSnapshotTest do
  @moduledoc """
  Побайтовая страховка под разрезание `loader.ex` (задача 3.46, заход 0).

  Здесь сверяется **загруженная структура** — то, что отдаёт
  `BuildCalculator.Data.ruleset!/1`, — с эталоном в `test/snapshots/`.
  Вопрос, на который отвечает файл, ровно один: «ruleset не изменился ни в одном
  поле». Он не зависит от того, о чём мы подумали, когда писали остальные 3300
  тестов, и именно поэтому нужен: впереди несколько заходов рефакторинга подряд,
  каждый объявит себя сохраняющим поведение по тестам, а покрытие ловит только
  задуманное.

  ⚠️ **Это НЕ дубль `BuildCalculator.Wiki.ParsedSnapshotTest`.** Тот стережёт
  JSON-файлы в `priv/rules/` — выход `mix wiki.parse`, то есть парсеры вики.
  Этот стережёт то, что из тех же файлов собрал `loader.ex`. Слои соседние, и ни
  один не следует из другого: парсер может стоять на месте, пока загрузчик
  начинает читать поле иначе, и наоборот. Снять один «как дубль второго» —
  это снять сторожа, а не дубль.

  ⚠️ **Упал — не значит «перезаписать эталон».** `mix data.snapshot --write`
  законен, когда правка задумана (поменялись данные или правило загрузчика),
  и обязателен `git diff test/snapshots` глазами. Рефакторинг, сохраняющий
  поведение, эталона не касается вовсе.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Snapshot

  @versions Data.versions()

  setup_all do
    snapshots =
      Map.new(@versions, fn version ->
        path = Snapshot.golden_path(version)

        committed =
          if File.exists?(path) do
            File.read!(path)
          else
            flunk("нет эталона #{path} — создать `mix data.snapshot --write`")
          end

        {version, %{path: path, committed: committed, current: render(version)}}
      end)

    {:ok, snapshots: snapshots}
  end

  defp render(version), do: version |> Data.ruleset!() |> Snapshot.render()

  # --- сам сторож ---------------------------------------------------------

  describe "загруженный ruleset против эталона" do
    # Тест на каждую версию, а не один цикл: во-первых, падение называет версию
    # заголовком, во-вторых, новый ruleset получит свой тест сам и упадёт до тех
    # пор, пока эталон не закоммитят.
    for version <- @versions do
      test "#{version} не изменился ни в одном поле", %{snapshots: snapshots} do
        %{committed: committed, current: current} = snapshots[unquote(version)]

        case Snapshot.compare(committed, current) do
          :ok -> :ok
          {:mismatch, report} -> flunk(Snapshot.explain(unquote(version), report))
        end
      end
    end

    # Два похожих файла рядом — приглашение перепутать их местами при
    # перегенерации. Строка версии внутри слепка это ловит, а сравнение самих
    # слепков ловит вырожденный случай «оба ruleset'а стали одним».
    test "эталоны не перепутаны местами и не совпали друг с другом", %{snapshots: snapshots} do
      for version <- @versions do
        assert snapshots[version].committed =~ ":version = #{inspect(version)}\n",
               "в #{snapshots[version].path} лежит слепок не той версии"
      end

      assert snapshots["vanilla"].committed != snapshots["siala_41"].committed
    end
  end

  # --- инварианты самого формата -----------------------------------------

  describe "формат слепка" do
    # Путь обязан быть уникальным: два разных места структуры, дающие один путь,
    # маскировали бы друг друга — изменение одного из них не было бы видно.
    test "ни один путь не встречается дважды", %{snapshots: snapshots} do
      for version <- @versions do
        paths = paths(snapshots[version].current)
        assert length(paths) == length(Enum.uniq(paths)), "#{version}: путь повторяется"
      end
    end

    # `compare/2` делит строку по первому " = ". Пока разделителя нет в путях,
    # деление точное, а не «обычно верное». Появится ключ с таким текстом —
    # узнаем здесь, а не по кривому отчёту о расхождении.
    test "разделитель не встречается внутри пути", %{snapshots: snapshots} do
      for version <- @versions do
        assert Enum.filter(paths(snapshots[version].current), &String.contains?(&1, " = ")) == []
      end
    end

    test "каждая строка данных — ровно одна строка файла", %{snapshots: snapshots} do
      for version <- @versions do
        lines = snapshots[version].current |> String.split("\n", trim: true)
        {header, data} = Enum.split_with(lines, &String.starts_with?(&1, "#"))

        assert length(header) == 3
        assert Enum.filter(data, &(not String.contains?(&1, " = "))) == []
      end
    end

    test "два прогона рендера дают побайтово одно и то же" do
      for version <- @versions do
        assert render(version) == render(version)
      end
    end
  end

  defp paths(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(&(&1 |> :binary.split(" = ") |> hd()))
  end

  # --- канонизация: что именно нельзя перепутать -------------------------

  describe "канонизация" do
    test "тип виден в значении: атом, строка, число и число с точкой различимы" do
      rendered = Enum.map([:foo, "foo", 1, "1", 1.0, nil, true, "true"], &Snapshot.term/1)

      assert rendered == [":foo", "\"foo\"", "1", "\"1\"", "1.0", "nil", "true", "\"true\""]
      assert length(Enum.uniq(rendered)) == length(rendered)
    end

    test "пустые контейнеры различимы и всё равно печатаются строкой" do
      assert Snapshot.lines(%{a: %{}, b: [], c: MapSet.new()}) == [
               ":a = %{}",
               ":b = []",
               ":c = #set[]"
             ]
    end

    # Ключ, который исчез, и ключ, у которого пустое значение, — разные события,
    # и второе гораздо интереснее. Без строки на пустой контейнер они выглядели
    # бы одинаково: отсутствием строк.
    test "исчезнувший ключ и опустевший ключ дают разный слепок" do
      assert Snapshot.lines(%{a: %{b: 1}}) != Snapshot.lines(%{a: %{}})
      assert Snapshot.lines(%{a: %{}}) != Snapshot.lines(%{})
    end

    test "ключи мапы сортируются, порядок объявления не виден" do
      assert Snapshot.lines(%{b: 1, a: 2}) == Snapshot.lines(%{a: 2, b: 1})
      assert Snapshot.lines(%{b: 1, a: 2}) == [":a = 2", ":b = 1"]
    end

    test "числовые ключи идут числовым порядком, а не строковым" do
      assert Snapshot.lines(%{2 => :b, 10 => :c, 1 => :a}) == ["1 = :a", "2 = :b", "10 = :c"]
    end

    test "множество сортируется и печатается одной строкой" do
      assert Snapshot.term(MapSet.new([40, 4, 8])) == "#set[4, 8, 40]"
      assert Snapshot.lines(%{levels: MapSet.new([3, 1])}) == [":levels = #set[1, 3]"]
    end

    # Список — это данные, а не мешок: порядок решает, какое правило атаки
    # сработает первым и что билд скажет игроку первым. Сортировать его значило
    # бы спрятать настоящее изменение.
    test "порядок списка сохраняется" do
      assert Snapshot.lines(%{rules: [3, 1, 2]}) == [
               ":rules/[0] = 3",
               ":rules/[1] = 1",
               ":rules/[2] = 2"
             ]
    end

    test "кортеж — одна строка, порядок членов свой" do
      assert Snapshot.term({:missing_data, {:racial_bonus_level, :elf}}) ==
               "{:missing_data, {:racial_bonus_level, :elf}}"
    end

    # `inspect/1` по умолчанию режет строку на 4096 байтах, а сиальский слой
    # классов носит цитаты длиннее. Обрезанная цитата сравнялась бы с ДРУГОЙ
    # обрезанной цитатой — единственная поломка, которой у слепка быть не может.
    test "длинная строка не обрезается" do
      long = String.duplicate("я", 5000)

      assert Snapshot.term(long) == inspect(long, printable_limit: :infinity)
      assert String.contains?(Snapshot.term(long), String.duplicate("я", 5000))
      refute String.contains?(Snapshot.term(long), "...")
    end

    test "перевод строки внутри значения не разрывает строку слепка" do
      assert Snapshot.lines(%{quote: "первая\nвторая"}) == [":quote = \"первая\\nвторая\""]
    end
  end

  # --- отчёт о расхождении ------------------------------------------------

  describe "падение называет место" do
    setup %{snapshots: snapshots} do
      {:ok, text: snapshots["vanilla"].committed}
    end

    test "изменённое значение: путь, раздел и обе стороны", %{text: text} do
      {before, changed} = replace_first_value(text, ":classes/:monk/:progression/1/:bab = ", "99")

      assert {:mismatch, report} = Snapshot.compare(before, changed)
      assert {:changed, _index, ":classes/:monk/:progression/1/:bab", both} = report.first
      assert both =~ "→  99"
      assert report.changed == 1
      assert report.added == 0
      assert report.removed == 0
      assert report.sections == [{":classes", 1}]

      message = Snapshot.explain("vanilla", report)
      assert message =~ ":classes/:monk/:progression/1/:bab"
      assert message =~ "раздел :classes"
      assert message =~ "mix data.snapshot --write"
    end

    test "исчезнувшая строка названа исчезнувшей", %{text: text} do
      shortened = drop_line(text, ":classes/:monk/:progression/1/:bab = ")

      assert {:mismatch, report} = Snapshot.compare(text, shortened)
      assert {:removed, _index, ":classes/:monk/:progression/1/:bab", _value} = report.first
      assert report.removed == 1
      assert report.changed == 0
    end

    test "появившаяся строка названа появившейся", %{text: text} do
      shortened = drop_line(text, ":classes/:monk/:progression/1/:bab = ")

      assert {:mismatch, report} = Snapshot.compare(shortened, text)
      assert {:added, _index, ":classes/:monk/:progression/1/:bab", _value} = report.first
      assert report.added == 1
    end

    # Расхождение в одном заголовке — не «ruleset изменился», и отчёт обязан
    # сказать это словами, а не упасть при подсчёте первой разошедшейся строки.
    test "правка только заголовка не роняет сам отчёт", %{text: text} do
      assert {:mismatch, report} = Snapshot.compare(text, "# другой заголовок\n" <> text)
      assert {:changed, _index, ".", _} = report.first
      assert report.changed == 0
      assert Snapshot.explain("vanilla", report) =~ "заголовок файла"
    end

    test "совпадение — это :ok, а не отчёт с нулями", %{text: text} do
      assert Snapshot.compare(text, text) == :ok
    end
  end

  defp replace_first_value(text, prefix, value) do
    line = Enum.find(String.split(text, "\n"), &String.starts_with?(&1, prefix))
    {text, String.replace(text, line, prefix <> value, global: false)}
  end

  defp drop_line(text, prefix) do
    text
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(&1, prefix))
    |> Enum.join("\n")
  end
end
