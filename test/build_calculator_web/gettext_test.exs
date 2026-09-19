defmodule BuildCalculatorWeb.GettextTest do
  @moduledoc """
  Сторож русской локали.

  Экран русский (CLAUDE.md §4), а сообщения валидации пишут Ecto и Phoenix —
  по-английски. Пока их некому перевести, на русской форме соседствуют два
  языка, причём заметно это только тому, кто дошёл до ошибки. Поэтому здесь
  не «пример перевода работает», а два вопроса, на которые обязан отвечать
  каждый прогон:

    1. **Всё ли из `errors.pot` переведено** — новый `msgid` без русской
       строки молча показывается по-английски, а не падает.
    2. **Всё ли попало в `errors.pot`** — сообщение, написанное прямо
       в `message:` или `add_error/4` и не заведённое в шаблон, не переводится
       вообще и мимо первой проверки проходит.

  Тот же приём, что у реестра форм гэпов в ядре: список ведётся руками,
  но забыть его пополнить нельзя.

  ⚠️ Модуль СИНХРОННЫЙ (`async: false`), и это задача 3.139, а не стиль.
  «Каждый вызов gettext/1 из исходников заведён в default.pot» гоняет
  `mix gettext.extract` ОТДЕЛЬНЫМ процессом с `--force-elixir`, который
  пересобирает `_build/test` — тот самый каталог, откуда ЛЮБОЙ другой
  `async: true`-тест берёт уже загруженные модули. Под `async: true` это
  дало гонку взаправду: 95 тестов из НИКАК не связанных файлов (`ClassPage`,
  `FeatNotes`) падали `UndefinedFunctionError`, потому что подпроцесс
  переписывал `.beam`-файлы в момент, когда другой тестовый процесс их же
  и грузил. `async: false` гарантирует у ExUnit («runner.ex» → `async_loop/4`):
  синхронные модули стартуют, только когда ВСЕ асинхронные полностью
  завершились, и идут один за другим — во время подпроцесса больше никто
  ничего не компилирует и не грузит. Цена — этот файл (11 тестов, из них
  один тяжёлый) не бежит параллельно с остальными; выигрыш — воспроизводимый
  прогон вместо гонки, которая либо есть, либо в этот раз повезло.
  """

  use ExUnit.Case, async: false

  @pot "priv/gettext/errors.pot"
  @ru "priv/gettext/ru/LC_MESSAGES/errors.po"

  # Домен `default` — то, что зовётся голым `gettext/1`. До 15.08.2026 его
  # переводов не было вовсе, и три строки баннеров соединения печатались
  # по-английски на русском экране (AGENT_QUEUE §3.32). Сторож ниже — тот же,
  # что у `errors`: молчаливый откат к английскому должен падать тестом,
  # а не обнаруживаться жалобой.
  @default_pot "priv/gettext/default.pot"
  @default_ru "priv/gettext/ru/LC_MESSAGES/default.po"

  # Сообщения, которые уже написаны по-русски в исходниках, переводить нечем
  # и незачем: `msgid` и есть перевод. Отличаем их по алфавиту, а не по списку
  # исключений — список пришлось бы пополнять руками, а это ровно то, от чего
  # тест и страхует.
  @latin ~r/^[^\p{Cyrillic}]+$/u

  describe "локаль" do
    test "по умолчанию русская" do
      assert BuildCalculatorWeb.Gettext.__gettext__(:default_locale) == "ru"
    end

    test "английская осталась собранной — вопрос RU/EN ещё открыт" do
      assert "en" in BuildCalculatorWeb.Gettext.__gettext__(:known_locales)
      assert "ru" in BuildCalculatorWeb.Gettext.__gettext__(:known_locales)
    end
  end

  describe "перевод" do
    test "сообщение Ecto приходит по-русски" do
      assert translate("can't be blank") == "не может быть пустым"
    end

    test "собственное сообщение приложения тоже" do
      assert translate("group builds must name a group") ==
               "билд с видимостью «группа» должен её называть"
    end

    # Три формы, а не две: английский msgid_plural на русском разложился бы
    # в «1 символ / 2 символов», если бы формула была взята от английского.
    test "множественное число русское, все три формы" do
      assert plural("should be at least %{count} character(s)", 1) =~ "минимум 1 символ"
      assert plural("should be at least %{count} character(s)", 2) =~ "минимум 2 символа"
      assert plural("should be at least %{count} character(s)", 5) =~ "минимум 5 символов"
      assert plural("should be at least %{count} character(s)", 21) =~ "минимум 21 символ"
    end
  end

  describe "баннеры соединения" do
    test "плашка обрыва по-русски" do
      assert plain("We can't find the internet") == "Нет связи с сервером"
      assert plain("Attempting to reconnect") == "Пытаемся переподключиться"
    end

    test "плашка серверной ошибки по-русски" do
      assert plain("Something went wrong!") == "Что-то пошло не так"
    end
  end

  describe "сторож" do
    test "у каждого msgid из errors.pot есть русская строка" do
      translated = translated_ids(@ru)

      untranslated =
        for id <- message_ids(@pot), id not in translated, do: id

      assert untranslated == [],
             "нет русского перевода (добавь в #{@ru}): " <> Enum.join(untranslated, ", ")
    end

    test "у каждого msgid из default.pot есть русская строка" do
      translated = translated_ids(@default_ru)

      untranslated =
        for id <- message_ids(@default_pot), id not in translated, do: id

      assert untranslated == [],
             "нет русского перевода (добавь в #{@default_ru}): " <> Enum.join(untranslated, ", ")
    end

    # Шаблон домена собирается `mix gettext.extract`, и забыть его пересобрать
    # так же легко, как забыть перевод: строка в исходниках есть, в `.pot` её
    # нет, проверка выше её не видит и молчит.
    #
    # ⚠️ До задачи 3.139 источником списка «что есть в исходниках» была
    # регулярка `~r/(?<![a-z_])gettext\("([^"]+)"\)/`, построчно. Закрывающая
    # скобка обязана была стоять сразу за текстом, поэтому регулярка не видела
    # ни `gettext("…", n: 5)` (аргумент до скобки — 118 вызовов), ни
    # `gettext(\n  "…"\n)` (перенос строки — 66 вызовов). Расширять регулярку
    # значило чинить одно и оставлять другое: построчный разбор в принципе
    # не видит многострочный вызов. Вместо своего текстового разбора здесь
    # спрашиваем сам `mix gettext.extract` — он читает AST при реальной
    # компиляции и слепых пятен по построению не имеет (то же свойство уже
    # отмечено ниже про `@moduledoc`-примеры бэкенда).
    test "каждый вызов gettext/1 из исходников заведён в default.pot" do
      known = MapSet.new(message_ids(@default_pot))

      missing =
        with_fresh_default_pot(fn pot_contents ->
          for {message, reference} <- fresh_default_domain_messages(pot_contents),
              not MapSet.member?(known, message),
              do: "#{message} (#{reference})"
        end)

      assert missing == [],
             "строка не заведена в #{@default_pot}, значит не переводится " <>
               "(сверено настоящим mix gettext.extract, а не регуляркой): " <>
               Enum.join(missing, ", ")
    end

    test "каждое сообщение из исходников заведено в errors.pot" do
      known = message_ids(@pot)

      missing =
        for {file, message} <- source_messages(),
            message not in known,
            do: "#{message} (#{file})"

      assert missing == [],
             "сообщение не заведено в #{@pot}, значит не переводится: " <>
               Enum.join(missing, ", ")
    end
  end

  defp translate(msgid), do: Gettext.dgettext(BuildCalculatorWeb.Gettext, "errors", msgid)

  defp plain(msgid), do: Gettext.gettext(BuildCalculatorWeb.Gettext, msgid)

  defp plural(msgid, count) do
    Gettext.dngettext(BuildCalculatorWeb.Gettext, "errors", msgid, msgid, count, count: count)
  end

  defp message_ids(path) do
    path
    |> Expo.PO.parse_file!()
    |> Map.fetch!(:messages)
    |> Enum.map(&(&1.msgid |> IO.iodata_to_binary()))
  end

  # Переведённым считается только тот, у которого строка непустая: `msgstr ""`
  # — это не перевод, а молчаливый откат к английскому.
  defp translated_ids(path) do
    path
    |> Expo.PO.parse_file!()
    |> Map.fetch!(:messages)
    |> Enum.filter(&translated?/1)
    |> Enum.map(&(&1.msgid |> IO.iodata_to_binary()))
  end

  defp translated?(%Expo.Message.Singular{msgstr: msgstr}), do: filled?(msgstr)

  defp translated?(%Expo.Message.Plural{msgstr: forms}),
    do: map_size(forms) > 0 and Enum.all?(forms, fn {_index, str} -> filled?(str) end)

  defp filled?(iodata), do: iodata |> IO.iodata_to_binary() |> String.trim() != ""

  # Строковые литералы, которые Ecto положит в ошибку changeset'а: `message:`
  # у валидаций и третий аргумент `add_error/4`. Комментарии пропускаем —
  # в `Accounts.User` закомментированы правила сложности пароля, и они
  # обвинили бы файл в непереведённом сообщении, которого нет.
  defp source_messages do
    for path <- Path.wildcard("lib/**/*.ex"),
        line <- File.read!(path) |> String.split("\n"),
        not comment?(line),
        message <- literals(line),
        Regex.match?(@latin, message),
        do: {Path.relative_to_cwd(path), message}
  end

  defp comment?(line), do: line |> String.trim_leading() |> String.starts_with?("#")

  # Реальное извлечение домена `default` — задача 3.139. `gettext`/`ngettext`
  # (без домена) идут сюда все вместе: и то и другое кладёт сообщение
  # в `default.pot`, а различие «один текст / пара текстов» несёт сама
  # Expo-структура (`Singular` против `Plural`), не наш код.
  #
  # ⚠️ Файл самого бэкенда `lib/build_calculator_web/gettext.ex` раньше
  # исключался из обхода явным списком — в его `@moduledoc` стоят примеры
  # `gettext("Here is the string to translate")`, и это документация Gettext,
  # а не вызов. Явное исключение больше не нужно и убрано вместе с
  # комментарием: `mix gettext.extract` разбирает AST при настоящей
  # компиляции, а строка внутри `"""`-хередока `@moduledoc` — это текст
  # строкового литерала атрибута, а не вызов макроса `gettext/1`, и в pot
  # никогда не попадала (проверено: "Here is the string to translate"
  # в `default.pot` нет ни до, ни после этой правки).
  #
  # ⚠️ `mix gettext.extract` ПИШЕТ `.pot`-файлы на диск, и тест не имеет права
  # оставить репозиторий изменённым. Снимаем байтовый снимок ДО запуска,
  # запускаем извлечение ОТДЕЛЬНЫМ процессом (не в этой VM — форс-компиляция
  # `lib/` посреди уже выполняющегося тестового прогона рискует перезагрузкой
  # модулей, которые в этот момент могут исполнять другие тесты), читаем
  # получившийся `default.pot` и восстанавливаем снимок СРАЗУ — до всякого
  # assert, — и ещё раз через `on_exit`, если тест упадёт раньше явного
  # восстановления. Восстановление байт-в-байт, а не через `git checkout`:
  # git откатил бы и любую НЕсвязанную незакоммиченную правку тех же файлов,
  # если бы она случайно была в рабочем дереве в момент прогона.
  defp with_fresh_default_pot(fun) do
    snapshot = pot_snapshot()
    on_exit(fn -> restore_pot_snapshot!(snapshot) end)

    {output, exit_code} =
      System.cmd("mix", ["gettext.extract"],
        cd: File.cwd!(),
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    fresh_default_pot = if File.exists?(@default_pot), do: File.read!(@default_pot), else: ""

    restore_pot_snapshot!(snapshot)

    if exit_code != 0 do
      flunk(
        "mix gettext.extract завершился с ошибкой (код #{exit_code}), " <>
          "сравнение с #{@default_pot} невозможно:\n\n" <> output
      )
    end

    fun.(fresh_default_pot)
  end

  defp pot_snapshot do
    "priv/gettext/*.pot"
    |> Path.wildcard()
    |> Map.new(&{&1, File.read!(&1)})
  end

  defp restore_pot_snapshot!(snapshot) do
    # Файлы, которых до запуска не было (extract мог бы завести новый домен),
    # убираем; всё, что было, — переписываем исходными байтами. Идемпотентно:
    # вызвать дважды (явно и затем ещё раз из on_exit) безопасно.
    "priv/gettext/*.pot"
    |> Path.wildcard()
    |> Enum.reject(&Map.has_key?(snapshot, &1))
    |> Enum.each(&File.rm!/1)

    Enum.each(snapshot, fn {path, content} -> File.write!(path, content) end)
  end

  # Сравниваем МНОЖЕСТВА msgid, а не файл целиком байт-в-байт (то есть не
  # `mix gettext.extract --check-up-to-date`). У записи есть ссылка
  # `#: файл:строка`, и она законно съезжает при любой правке НАД вызовом
  # gettext в том же файле — это не пропущенный перевод, а просто другая
  # строка исходника (живой пример: `build_view_live.ex:321` → `:322` без
  # единой смысловой правки поблизости). `--check-up-to-date` посчитал бы
  # такой сдвиг «файл устарел» и падал бы на нём тоже; нам нужно ловить
  # пропавшую СТРОКУ, а не сдвинувшийся номер строки в комментарии.
  defp fresh_default_domain_messages(pot_contents) do
    pot_contents
    |> Expo.PO.parse_string!()
    |> Map.fetch!(:messages)
    |> Enum.map(fn message ->
      {IO.iodata_to_binary(message.msgid), message_reference(message)}
    end)
  end

  defp message_reference(message) do
    message.references
    |> List.flatten()
    |> Enum.map(fn
      {file, line} -> "#{file}:#{line}"
      file -> file
    end)
    |> Enum.join(", ")
  end

  defp literals(line) do
    message = Regex.run(~r/message:\s+"([^"]+)"/, line, capture: :all_but_first) || []

    added =
      Regex.run(~r/add_error\([^,]+,\s*:[a-z_]+,\s*"([^"]+)"/, line, capture: :all_but_first)

    message ++ (added || [])
  end
end
