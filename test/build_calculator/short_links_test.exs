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

  # Генератор ключей, выдающий заданную последовательность. Иначе ветку повтора
  # не воспроизвести: у случайного совпадения шести символов вероятность
  # порядка 10^(−6).
  defp fixed(keys) do
    # `id` уникальный: в одном тесте генераторов бывает два, а у двух детей
    # с одинаковой спецификацией супервизор не заводится.
    spec = Supervisor.child_spec({Agent, fn -> keys end}, id: {:keys, System.unique_integer()})
    agent = start_supervised!(spec)

    fn -> Agent.get_and_update(agent, fn [key | rest] -> {key, rest} end) end
  end
end
