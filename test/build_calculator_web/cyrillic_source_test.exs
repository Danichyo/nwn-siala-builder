defmodule BuildCalculatorWeb.CyrillicSourceTest do
  @moduledoc """
  Сторож кириллицы в ИСХОДНИКАХ веб-слоя (задача 4.11, VANILLA.md §4, этап C).

  Решение Dan 27.09.2026 (CLAUDE.md §4): любой текст интерфейса вводится
  только через `gettext` — английский msgid, русский `msgstr` в `ru/*.po`.
  En-храповик `EnGuardTest` меряет кириллицу в ОТРИСОВКЕ, но только там, куда
  доходят его зоны; текст, который ни одна зона не рисует, он не видит. Этот
  тест читает сами файлы `lib/build_calculator_web/**/*.{ex,heex}` и
  не даёт кириллице вне комментариев ни расти, ни незаметно стоять на месте:

    * **число на каждый файл записано здесь** (`@ceilings`, путь от
      `lib/build_calculator_web/`; файла нет в карте — его число 0);
    * **выросло** — тест падает и называет новые фразы с номерами строк:
      новый текст заводится через `gettext`, а не литералом;
    * **уменьшилось** — тест падает с просьбой опустить число: каждый заход
      перевода (4.11–4.17, 4.47, 4.48) обязан сдвинуть храповик, а откат
      незаметно не пройдёт. Цель этапа C — пустая `@ceilings`.

  **С задачи 4.48 этап C закрыт:** `@ceilings` пуста, и это стережёт отдельный
  тест — храповик стал нулём для каждого файла веб-слоя, старого и нового.
  Новый файл с литералом падает так же, как старый: «файла нет в карте — его
  число 0».

  ## Что считается

  Кириллические слова вне комментариев — счётчик и его правило
  «что такое комментарий» описаны в `BuildCalculatorWeb.SourceCyrillic`
  (`test/support/source_cyrillic.ex`): в `.ex` — литералы дерева разбора без
  `@moduledoc`/`@doc`/`@typedoc` и `doc:` у `attr`/`slot` (`#` в дереве нет);
  в HEEx — текст без `<%!-- --%>`, `<!-- -->`, комментариев JS в `<script>`
  и строк, начинающихся с `#` (комментарий Elixir в выражении).

  ## Кириллица, которая не текст интерфейса, — закрытый список

  `@not_interface`: файл, место (`функция/арность`) и фразы со счётом —
  и у каждой записи «почему не интерфейс». Записи сверяются точно: фраза
  в этом месте встречается ровно столько раз, сколько записано; запись,
  которой нет в коде, — тоже падение (список не копит мёртвое). Та же фраза
  в другом месте файла — уже интерфейс и идёт в счёт.

  ## Опись — чтобы «называет новое» было правдой

  Рядом с числами лежит опись `test/fixtures/cyrillic_source/inventory.txt`,
  строка «файл⇥сколько раз⇥фраза». По ней тест называет, какие фразы
  прибавились или ушли. Когда храповик сдвинулся, в одном изменении меняются
  двое: число в `@ceilings` — руками (тест называет, на какое), и опись —
  командой (`git diff test/fixtures/cyrillic_source` после неё показывает,
  что именно переведено):

      CYRILLIC_SOURCE_WRITE=1 mix test test/build_calculator_web/cyrillic_source_test.exs

  Опись, не переписанная вместе с числом, роняет тест сама: её сумма слов
  по файлу обязана равняться числу.

  ## Положительный контроль

  Блок «правило комментария» гоняет счётчик по синтетическим исходникам:
  литерал, интерполяция, текст `~H`, строка JS считаются; `#`, `@doc`, `doc:`,
  `<%!-- --%>`, `<!-- -->`, `//` и `/* */` хука, `#`-строка в выражении HEEx —
  нет. Без него ноль у файла выглядел бы победой и тогда, когда счётчик ослеп.

  Тест только читает файлы — `async: true`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculatorWeb.SourceCyrillic

  @root "lib/build_calculator_web"

  # Храповик: кириллических слов вне комментариев и вне `@not_interface`,
  # по файлу. Двигается только вниз — вместе с описью в `@inventory`.
  #
  # ⚠️ С задачи 4.48 карта ПУСТА и обязана такой остаться (тест «этап C
  # закрыт» ниже): весь текст веб-слоя идёт через gettext, и у любого файла —
  # старого или нового — число 0. Кириллица, которая не текст интерфейса, —
  # запись в `@not_interface` с причиной, а не строка здесь.
  @ceilings %{}

  # Кириллица, которая не текст интерфейса. Закрытый список: у каждой
  # записи — место и почему; сверяется точно (см. moduledoc).
  @not_interface [
    %{
      file: "builder/game_log_import.ex",
      where: "issue_forms/0",
      phrases: %{
        "какая-то строка чата" => 1,
        "Неведомый фит" => 1,
        "что-то совсем не по форме" => 1
      },
      why:
        "образцы строк игрового лога `.билд` в каталоге форм замечаний — там, где сервер " <>
          "шарда печатает по-русски (реплика чата, фит шарда, строка предмета; по 20 логам " <>
          "`test/fixtures/game_logs*/`, задача 4.47): вход из игры, а не наш текст; подпись " <>
          "замечания цитирует их как прочитанное. Где сервер печатает по-английски (раса, " <>
          "навык, значение фита), образцы английские. Каталог питает тесты, игроку " <>
          "не показывается"
    },
    %{
      file: "builder/import/names.ex",
      where: "norm/1",
      phrases: %{"ё" => 1, "е" => 1},
      why:
        "нормализация имени для поиска: `ё` и `е` в русском написании, которое вставил " <>
          "игрок, считаются одной буквой. Буквы ввода, а не подпись"
    },
    %{
      file: "builder/import/names.ex",
      where: "name_words/1",
      phrases: %{"ё" => 1, "е" => 1},
      why: "та же нормализация `ё` → `е` для слов имени, по которым ищется совпадение"
    },
    %{
      file: "builder/choice_index.ex",
      where: "norm/1",
      phrases: %{"ё" => 1, "е" => 1},
      why:
        "нормализация значения выбора фита из лога `.билд` и вставки: `ё` и `е` — одна " <>
          "буква. Буквы ввода, а не подпись"
    },
    %{
      file: "builder/import/lines.ex",
      where: "header_words/1",
      phrases: %{"а-яё" => 1},
      why:
        "класс символов регулярки, которая оставляет в заголовке вставки латиницу " <>
          "и кириллицу: разбор чужого текста, а не подпись"
    }
  ]

  @inventory "test/fixtures/cyrillic_source/inventory.txt"
  @write_env "CYRILLIC_SOURCE_WRITE"
  @command "CYRILLIC_SOURCE_WRITE=1 mix test test/build_calculator_web/cyrillic_source_test.exs"

  # ---- храповик ---------------------------------------------------------------

  test "храповик по файлам: кириллица вне комментариев и вне списка «не интерфейс»" do
    scans = Map.new(SourceCyrillic.files(@root), &{relative(&1), SourceCyrillic.scan(&1)})
    current = Map.new(scans, fn {file, found} -> {file, interface(file, found)} end)

    recorded = read_inventory()

    baseline =
      if System.get_env(@write_env) in ["1", "true"] do
        write_inventory!(current)
        inventory_of(current)
      else
        recorded
      end

    files = Enum.uniq(Map.keys(current) ++ Map.keys(ceilings())) |> Enum.sort()

    problems =
      for file <- files,
          problem = check_file(file, Map.get(current, file), recorded, baseline),
          do: problem

    assert problems == [], Enum.join(problems, "\n\n")
  end

  # Задача 4.48: последняя зона (библиотека и аккаунты) переведена, храповик
  # стал нулём для всего веб-слоя. Вернуть файлу число в `@ceilings` значило бы
  # снова пустить литерал мимо gettext (CLAUDE.md §4) — поэтому пустота карты
  # проверяется отдельно, а не только тем, что её никто не трогает.
  test "этап C закрыт: храповик — ноль для всего веб-слоя" do
    assert ceilings() == %{}, """
    @ceilings снова не пуст: #{inspect(ceilings())}.
    Текст интерфейса — только через gettext (английский msgid, русский msgstr).
    Кириллица, которая не текст интерфейса (образец чужого ввода, буквы разбора),
    — запись в @not_interface с причиной, а не число в храповике.
    """
  end

  test "список «не интерфейс» сходится с кодом точно" do
    problems =
      for %{file: file, where: where, phrases: phrases} <- @not_interface,
          path = Path.join(@root, file),
          found =
            if(File.exists?(path),
              do: path |> SourceCyrillic.scan() |> Enum.filter(&(&1.where == where)),
              else: []
            ),
          {phrase, count} <- Enum.sort(phrases),
          actual = Enum.count(found, &(&1.phrase == phrase)),
          actual != count do
        "  #{file} · #{where}: «#{phrase}» записано #{count}, в коде #{actual}"
      end

    assert problems == [], """
    @not_interface разошёлся с кодом:
    #{Enum.join(problems, "\n")}

    Запись списка — точное место и счёт: фраза ушла — убери её из записи;
    переехала в другую функцию — поправь `where`; новая кириллица «не интерфейс» —
    заведи запись с причиной (а если это текст, который видит игрок, — gettext).
    """
  end

  test "у каждой записи «не интерфейс» есть причина" do
    for entry <- @not_interface do
      assert is_binary(entry.why) and String.length(entry.why) > 20,
             "#{entry.file} · #{entry.where}: нет причины"
    end
  end

  # ---- правило комментария: положительный контроль -------------------------

  describe "правило комментария" do
    test "Elixir: литерал и интерполяция считаются, # и документация — нет" do
      source = ~S'''
      defmodule Probe do
        @moduledoc """
        Документация модуля.
        """

        @typedoc "Тип с описанием."
        @type t :: term()

        # Комментарий строкой.
        @doc "Функция с описанием."
        def label(n) do
          # ещё комментарий
          gettext("Plain") <> "Новый текст" <> "#{n} уровней" # хвост
        end

        @label "Атрибут модуля"

        attr :name, :string, doc: "Имя атрибута"
        slot :inner_block, doc: "Слот компонента"
        attr :title, :string, default: "Подпись по умолчанию"
      end
      '''

      found = SourceCyrillic.scan_source(source, ".ex")

      assert phrases(found) == [
               "Новый текст",
               "уровней",
               "Атрибут модуля",
               "Подпись по умолчанию"
             ]

      assert where(found, "Новый текст") == "label/1"
      assert where(found, "Атрибут модуля") == "@label"
      assert line(found, "Новый текст") == 13
    end

    test "HEEx: текст, атрибут и строка выражения считаются, комментарии — нет" do
      source = """
      <div title="Подсказка">
        <%!-- Комментарий HEEx
              в две строки. --%>
        <!-- Комментарий HTML -->
        Видимый текст
        <span :if={@x}>{if @y, do: "Строка выражения", else: nil}</span>
        <.section
          warn={
            # Комментарий Elixir внутри выражения
            "Предупреждение"
          }
        />
        <a href="#раздел">ссылка</a>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Probe">
        export default {
          mounted() {
            // Комментарий хука
            /* Блочный
               комментарий */
            this.el.dataset.label = "Строка хука // не комментарий"
          }
        }
      </script>
      """

      found = SourceCyrillic.scan_source(source, ".heex")

      assert phrases(found) == [
               "Подсказка",
               "Видимый текст",
               "Строка выражения",
               "Предупреждение",
               "раздел",
               "ссылка",
               # `/` — знак препинания: слова по обе стороны — одна фраза.
               "Строка хука // не комментарий"
             ]

      assert line(found, "Видимый текст") == 5
      assert line(found, "Предупреждение") == 10
      assert line(found, "Строка хука // не комментарий") == 21
      assert Enum.all?(found, &(&1.where == "template"))
    end

    test "~H внутри .ex — шаблон HEEx: те же правила, место — функция" do
      source = ~S'''
      defmodule Probe do
        def card(assigns) do
          ~H"""
          <%!-- Комментарий --%>
          <span>Подпись карточки</span>
          """
        end
      end
      '''

      found = SourceCyrillic.scan_source(source, ".ex")

      assert phrases(found) == ["Подпись карточки"]
      assert where(found, "Подпись карточки") == "card/1"
      assert line(found, "Подпись карточки") == 5
    end

    test "единица — слово: фраза из трёх слов весит три" do
      [occurrence] = SourceCyrillic.scan_source(~s|"Убрать последний уровень"|, ".ex")
      assert occurrence.words == 3
    end
  end

  # ---- счёт ---------------------------------------------------------------------

  defp relative(path), do: Path.relative_to(path, @root)

  # Фразы файла без записей `@not_interface` — точно по месту и счёту.
  defp interface(file, found) do
    exempt =
      for %{file: ^file, where: where, phrases: phrases} <- @not_interface,
          phrase <- Map.keys(phrases),
          into: MapSet.new(),
          do: {where, phrase}

    Enum.reject(found, &MapSet.member?(exempt, {&1.where, &1.phrase}))
  end

  # Через функцию, а не атрибутом в месте вызова: в конце этапа C карта пуста,
  # и проверка типов на `Map.get(%{}, …)` предупреждала бы, что ключа нет никогда.
  defp ceilings, do: Map.new(@ceilings)

  defp count(found), do: found |> Enum.map(& &1.words) |> Enum.sum()

  defp inventory_of(current) do
    Map.new(current, fn {file, found} -> {file, Enum.frequencies_by(found, & &1.phrase)} end)
    |> Map.reject(fn {_file, phrases} -> phrases == %{} end)
  end

  defp check_file(file, found, recorded, baseline) do
    found = found || []
    count = count(found)
    ceiling = Map.get(ceilings(), file, 0)
    now = Enum.frequencies_by(found, & &1.phrase)
    was = Map.get(recorded, file, %{})
    base = Map.get(baseline, file, %{})
    changes = changes(was, now, found)

    cond do
      count > ceiling ->
        """
        #{file}: кириллических слов #{count}, храповик #{ceiling} — стало больше на #{count - ceiling}.
          Текст интерфейса — только через gettext (английский msgid, русский msgstr —
          прежний литерал байт в байт). Не интерфейс (образец чужого ввода и т. п.) —
          запись в @not_interface с причиной.
        #{changes}
        """

      count < ceiling and count == 0 ->
        """
        #{file}: кириллицы больше нет — убери файл из @ceilings (было #{ceiling})
          и перепиши опись: #{@command}
        #{changes}
        """

      count < ceiling ->
        """
        #{file}: кириллических слов #{count}, храповик #{ceiling} — меньше на #{ceiling - count}.
          Храповик идёт за переводом: опусти число в @ceilings до #{count}
          и перепиши опись: #{@command}
        #{changes}
        """

      words_in(base) != ceiling ->
        "#{file}: опись (#{words_in(base)} слов) не сходится с числом #{ceiling} в @ceilings — " <>
          "перепиши её: #{@command}"

      base != now ->
        """
        #{file}: число прежнее (#{count}), а состав кириллицы другой — перепиши опись:
          #{@command}
        #{changes}
        """

      true ->
        nil
    end
  end

  defp words_in(phrases) do
    phrases |> Enum.map(fn {phrase, n} -> SourceCyrillic.words(phrase) * n end) |> Enum.sum()
  end

  # Что прибавилось (с номерами строк) и что ушло — для сообщения.
  defp changes(was, now, found) do
    phrases = Enum.uniq(Map.keys(was) ++ Map.keys(now)) |> Enum.sort()

    lines =
      for phrase <- phrases,
          before = Map.get(was, phrase, 0),
          after_ = Map.get(now, phrase, 0),
          before != after_ do
        at =
          found
          |> Enum.filter(&(&1.phrase == phrase))
          |> Enum.map_join(", ", &"#{&1.line}")

        sign = if after_ > before, do: "+", else: "−"
        where = if at == "", do: "", else: "  (строки #{at})"
        "    #{sign} «#{phrase}» #{before} → #{after_}#{where}"
      end

    case lines do
      [] -> ""
      _ -> Enum.join(lines, "\n")
    end
  end

  defp read_inventory do
    case File.read(@inventory) do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        |> Enum.reduce(%{}, fn line, acc ->
          [file, count, phrase] = String.split(line, "\t", parts: 3)

          Map.update(
            acc,
            file,
            %{phrase => String.to_integer(count)},
            &Map.put(&1, phrase, String.to_integer(count))
          )
        end)

      {:error, :enoent} ->
        %{}
    end
  end

  defp write_inventory!(current) do
    File.mkdir_p!(Path.dirname(@inventory))

    lines =
      for {file, phrases} <- current |> inventory_of() |> Enum.sort(),
          {phrase, count} <- Enum.sort(phrases),
          do: "#{file}\t#{count}\t#{phrase}\n"

    File.write!(@inventory, lines)
  end

  # ---- синтетика ---------------------------------------------------------------

  defp phrases(found), do: Enum.map(found, & &1.phrase)
  defp where(found, phrase), do: Enum.find(found, &(&1.phrase == phrase)).where
  defp line(found, phrase), do: Enum.find(found, &(&1.phrase == phrase)).line
end
