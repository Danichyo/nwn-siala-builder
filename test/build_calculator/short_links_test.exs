defmodule BuildCalculator.ShortLinksTest do
  @moduledoc """
  Короткая ссылка: круг, дедупликация и то, на чём держится гонка.

  Все коды сделаны настоящим кодировщиком, а не руками: запись валидируется
  разбором кода, поэтому подделка не проверила бы ничего.
  """
  use BuildCalculator.DataCase, async: true

  alias BuildCalculator.Encoding
  alias BuildCalculator.Repo
  alias BuildCalculator.Rules.Build
  alias BuildCalculator.ShortLinks
  alias BuildCalculator.ShortLinks.ShortLink

  # Билд, у которого есть что терять при неверном круге: раса, мировоззрение,
  # три класса в определённом порядке (после 20-го он решает BAB), статы,
  # прибавки характеристик, фит в слоте и купленные ранги.
  defp rich_build do
    Build.new(
      ruleset_version: "siala_41",
      race: :dwarf,
      alignment: :lawful_good,
      base_abilities: %{str: 16, dex: 12, con: 16, int: 12, wis: 10, cha: 8},
      levels: List.duplicate(:fighter, 10) ++ List.duplicate(:dwarven_defender, 11),
      ability_increases: %{4 => :str, 8 => :str, 12 => :con, 16 => :str, 20 => :str},
      feats: %{1 => %{general: :toughness}},
      skills: %{1 => %{discipline: 4}, 2 => %{discipline: 1}}
    )
  end

  describe "круг" do
    test "код → короткая ссылка → тот же самый билд" do
      build = rich_build()
      code = Encoding.encode(build)

      assert {:ok, %ShortLink{key: key}} = ShortLinks.shorten(code)
      assert {:ok, %ShortLink{code: stored}} = ShortLinks.fetch(key)

      # Строка совпала посимвольно — и билд за ней совпал структурно целиком.
      # Одного равенства кодов мало: оно ничего не сказало бы, если бы
      # кодировщик однажды начал терять поле.
      assert stored == code
      assert {:ok, %{build: decoded}} = Encoding.decode(stored)
      assert decoded == build
    end

    test "версия набора правил лежит вместе с кодом" do
      assert {:ok, %ShortLink{ruleset_version: "siala_41"}} =
               ShortLinks.shorten(Encoding.encode(rich_build()))
    end
  end

  describe "дедупликация" do
    # Обе половины правила — одним тестом: «тот же код даёт тот же ключ»
    # зеленеет и при генераторе, который выдаёт один ключ на всё, а «разные
    # коды дают разные ключи» — при полном отсутствии дедупликации.
    test "одинаковый код даёт тот же ключ, разные коды — разные" do
      one = Encoding.encode(rich_build())
      other = Encoding.encode(%{rich_build() | race: :elf})

      assert {:ok, %ShortLink{key: first}} = ShortLinks.shorten(one)
      assert {:ok, %ShortLink{key: again}} = ShortLinks.shorten(one)
      assert {:ok, %ShortLink{key: second}} = ShortLinks.shorten(other)

      assert again == first
      refute second == first
      assert Repo.aggregate(ShortLink, :count) == 2
    end

    # То, на чём держится безопасность гонки: решение принимает индекс, а не
    # наш SELECT. Две одновременные вставки одного кода в тесте с песочницей
    # не воспроизвести (обе идут по одному соединению), но проверить можно
    # ровно тот механизм, который их разводит.
    test "второй ряд с тем же кодом база не принимает, а с другим — принимает" do
      code = Encoding.encode(rich_build())
      hash = ShortLink.fingerprint(code)

      assert {:ok, _} = Repo.insert(ShortLink.insert_changeset(code, hash, "aaaaaa", "siala_41"))

      assert {:error, changeset} =
               Repo.insert(ShortLink.insert_changeset(code, hash, "bbbbbb", "siala_41"))

      assert Keyword.has_key?(changeset.errors, :code_hash)

      # Положительный контроль: отказ выдаёт именно совпавший код, а не любая
      # вторая вставка в эту таблицу.
      other = Encoding.encode(%{rich_build() | race: :elf})

      assert {:ok, _} =
               Repo.insert(
                 ShortLink.insert_changeset(
                   other,
                   ShortLink.fingerprint(other),
                   "cccccc",
                   "siala_41"
                 )
               )
    end
  end

  describe "ключ" do
    test "base62 шести символов" do
      assert {:ok, %ShortLink{key: key}} = ShortLinks.shorten(Encoding.encode(rich_build()))
      assert String.length(key) == 6
      assert Regex.match?(~r/\A[0-9A-Za-z]{6}\z/, key)
    end

    test "совпавший ключ не отдаётся дважды — берётся следующий" do
      taken = Encoding.encode(rich_build())

      assert {:ok, %ShortLink{key: first}} =
               ShortLinks.shorten(taken, key_source: fixed(["zzzzzz"]))

      # Тот же генератор на ДРУГОМ билде: первый ключ занят, значит запись
      # обязана получить второй.
      other = Encoding.encode(%{rich_build() | race: :elf})

      assert {:ok, %ShortLink{key: second}} =
               ShortLinks.shorten(other, key_source: fixed(["zzzzzz", "yyyyyy"]))

      assert first == "zzzzzz"
      assert second == "yyyyyy"
    end

    # Задача 4.76: совпавший ключ — не ошибка базы. Ошибку уникальности
    # Postgres пишет в СВОЙ журнал строкой «DETAIL: Key (key)=(…) already
    # exists.» — чужой ключ, по которому открывается чужой билд (замер на
    # журнале dev-базы, `tmp/4.76/pg_detail.exs`). Журнал базы тесту не виден;
    # виден ответ на запрос — `{:error, %Postgrex.Error{}}` и есть та ошибка.
    test "совпавший ключ разводится без ошибки в базе (её журнал несёт ключ)" do
      taken = Encoding.encode(rich_build())
      other = Encoding.encode(%{rich_build() | race: :elf})

      assert {:ok, _} = ShortLinks.shorten(taken, key_source: fixed(["zzzzzz"]))

      {result, errors} =
        query_errors(fn -> ShortLinks.shorten(other, key_source: fixed(["zzzzzz", "yyyyyy"])) end)

      assert {:ok, %ShortLink{key: "yyyyyy"}} = result
      assert errors == []

      # Положительный контроль: прежняя вставка на тот же ключ — ошибка базы
      # с нарушением уникальности, и измеритель её видит.
      {_result, errors} =
        query_errors(fn ->
          Repo.insert(
            ShortLink.insert_changeset(other, ShortLink.fingerprint(other), "zzzzzz", "siala_41")
          )
        end)

      assert [:unique_violation] = errors
    end

    test "если свободного ключа так и не нашлось — отказ, а не чужая запись" do
      assert {:ok, _} =
               ShortLinks.shorten(Encoding.encode(rich_build()), key_source: fixed(["zzzzzz"]))

      other = Encoding.encode(%{rich_build() | race: :elf})

      assert {:error, :unavailable} =
               ShortLinks.shorten(other, key_source: fn -> "zzzzzz" end)

      # Положительный контроль: дело в занятом ключе, а не в самом билде —
      # со свободным ключом тот же код сокращается.
      assert {:ok, %ShortLink{key: "wwwwww"}} =
               ShortLinks.shorten(other, key_source: fixed(["wwwwww"]))
    end
  end

  describe "мусор на входе" do
    test "код, который не читается, не сохраняется вовсе" do
      for bad <- ["", "не код", "9.zzzz", nil, 42] do
        assert ShortLinks.shorten(bad) == {:error, :invalid_code}
      end

      # Положительный контроль рядом: отказ выдаёт разбор кода, а не сама
      # функция, которая иначе могла бы отказывать всем.
      assert {:ok, %ShortLink{}} = ShortLinks.shorten(Encoding.encode(rich_build()))
      assert Repo.aggregate(ShortLink, :count) == 1
    end

    test "неизвестный ключ и мусор вместо ключа — «нет такой ссылки»" do
      assert {:ok, %ShortLink{key: key}} = ShortLinks.shorten(Encoding.encode(rich_build()))

      assert ShortLinks.fetch("000000") == :error
      assert ShortLinks.fetch("не ключ") == :error
      assert ShortLinks.fetch(String.duplicate("a", 400)) == :error
      assert ShortLinks.fetch(nil) == :error

      # Положительный контроль: настоящий ключ находится.
      assert {:ok, %ShortLink{}} = ShortLinks.fetch(key)
    end
  end

  describe "потолок новых ссылок с одного адреса (задача 4.75)" do
    # Разные билды: сила 8..40 даёт 33 разных кода — больше потолка (30).
    defp codes(count) do
      for str <- 8..(7 + count) do
        Encoding.encode(%{
          rich_build()
          | base_abilities: %{str: str, dex: 12, con: 16, int: 12, wis: 10, cha: 8}
        })
      end
    end

    # Ключ адреса — свой на тест: счёт в памяти общий на приложение.
    defp address, do: {:test, make_ref()}

    test "30 новых ссылок в час — дальше :rate_limited, строк ровно 30" do
      address = address()
      [extra | allowed] = codes(31)

      for code <- allowed,
          do: assert({:ok, %ShortLink{}} = ShortLinks.shorten(code, address: address))

      assert ShortLinks.shorten(extra, address: address) == {:error, :rate_limited}
      assert Repo.aggregate(ShortLink, :count) == 30
    end

    test "уже сокращённый код выдаётся и за потолком — он не новая строка" do
      address = address()
      [first | rest] = codes(31)

      for code <- rest, do: {:ok, _} = ShortLinks.shorten(code, address: address)
      assert {:ok, %ShortLink{key: key}} = ShortLinks.shorten(hd(rest), address: address)
      assert ShortLinks.shorten(first, address: address) == {:error, :rate_limited}
      assert {:ok, %ShortLink{key: ^key}} = ShortLinks.shorten(hd(rest), address: address)
    end

    test "другой адрес и вызов без адреса — свой счёт и без потолка (контроль)" do
      address = address()
      [a, b | rest] = codes(32)
      for code <- rest, do: {:ok, _} = ShortLinks.shorten(code, address: address)
      assert ShortLinks.shorten(a, address: address) == {:error, :rate_limited}

      assert {:ok, %ShortLink{}} = ShortLinks.shorten(a, address: address())
      assert {:ok, %ShortLink{}} = ShortLinks.shorten(b)
    end
  end

  # Генератор ключей, выдающий заданную последовательность. Иначе ветку повтора
  # не воспроизвести: у случайного совпадения шести символов вероятность
  # порядка 10^(−6).
  # Ошибки базы у запросов ЭТОГО процесса: обработчик telemetry Ecto
  # вызывается синхронно в процессе, сделавшем запрос.
  defp query_errors(fun) do
    test = self()
    ref = make_ref()
    handler = {__MODULE__, ref}

    :telemetry.attach(
      handler,
      [:build_calculator, :repo, :query],
      fn _event, _measure, meta, _config ->
        with true <- self() == test,
             {:error, %Postgrex.Error{postgres: %{code: code}}} <- meta.result do
          send(test, {ref, code})
        end
      end,
      nil
    )

    try do
      result = fun.()
      {result, drain_errors(ref, [])}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain_errors(ref, acc) do
    receive do
      {^ref, code} -> drain_errors(ref, acc ++ [code])
    after
      0 -> acc
    end
  end

  defp fixed(keys) do
    # `id` уникальный: в одном тесте генераторов бывает два, а у двух детей
    # с одинаковой спецификацией супервизор не заводится.
    spec = Supervisor.child_spec({Agent, fn -> keys end}, id: {:keys, System.unique_integer()})
    agent = start_supervised!(spec)

    fn -> Agent.get_and_update(agent, fn [key | rest] -> {key, rest} end) end
  end
end
