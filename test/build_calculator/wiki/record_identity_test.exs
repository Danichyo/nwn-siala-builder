defmodule BuildCalculator.Wiki.RecordIdentityTest do
  @moduledoc """
  Чем запись отличается от соседней — и чем НЕ отличается.

  Ключ у записи один — `id`. `name` ключом не является и являться не может:
  у сиальских слоёв несколько страниц законно смотрят на одну ванильную запись
  и получают её английское имя.

    * `Energy Drain` и `Essence Drain` — два РАЗНЫХ заклинания шарда
      (Колдун/Волшебник 9 против Священника 9), но обе страницы ссылаются
      в «Ссылках» на одну и ту же страницу Fandom, и обе получают
      `name: "Energy drain"`;
    * пять `Epic energy resistance (…)` — одно ванильное умение с пятью
      значениями выбора, и все пять получают `name: "Epic energy resistance"`.

  ⚠️ Чинится это НЕ переименованием в данных. `name` — английское имя ванильной
  записи как есть, дорисовывать к нему уточнения («Energy drain (cleric)»)
  значило бы выдумать имя, которого нет ни на одной вики (CLAUDE.md §3).
  Различать надо по `id`.

  ⚠️ Почему тест, а не внимательность. Ровно этот класс ошибок уже был с
  суффиксом `~pageid` в именах файлов кэша: две страницы Сиалы отличались
  только регистром, ФС macOS регистронезависима, и одна затирала другую.
  Тогда спасло то, что кто-то заметил расхождение в счёте. Механизм тот же —
  сходятся два разных ключа, — поэтому и защита та же: сверка числа.
  Код, который сложит записи в мапу по `name`, потеряет их молча и без ошибки.
  """

  use ExUnit.Case, async: true

  @vanilla_files ~w(feats spells classes skills races)
  @siala_files ~w(feats spells)

  defp records(path) do
    decoded = path |> File.read!() |> Jason.decode!()

    case decoded do
      list when is_list(list) -> list
      %{} = map -> map |> Map.values() |> Enum.find(&is_list/1)
    end
  end

  defp vanilla(name), do: records("priv/rules/vanilla/#{name}.json")
  defp siala(name), do: records("priv/rules/siala_41/generated/#{name}.json")

  defp collisions(records, field) do
    records
    |> Enum.filter(&is_binary(&1[field]))
    |> Enum.group_by(& &1[field], & &1["id"])
    |> Enum.filter(fn {_value, ids} -> length(ids) > 1 end)
    |> Map.new(fn {value, ids} -> {value, Enum.sort(ids)} end)
  end

  describe "id — единственный ключ, и он обязан быть уникален" do
    test "в каждом ванильном файле число записей равно числу различных id" do
      for name <- @vanilla_files do
        records = vanilla(name)
        ids = Enum.map(records, & &1["id"])

        # Сверка числа, а не «на глаз похоже»: дубль id — это молча съеденная
        # запись у любого, кто сложит файл в мапу.
        assert length(ids) == length(Enum.uniq(ids)),
               "vanilla/#{name}.json: дубли id #{inspect(ids -- Enum.uniq(ids))}"

        refute records == [], "vanilla/#{name}.json пуст — проверка выше ничего не видела"
      end
    end

    test "в машинных слоях Сиалы то же самое" do
      for name <- @siala_files do
        records = siala(name)
        ids = Enum.map(records, & &1["id"])

        assert length(ids) == length(Enum.uniq(ids)),
               "siala_41/generated/#{name}.json: дубли id #{inspect(ids -- Enum.uniq(ids))}"

        refute records == []
      end
    end

    # `ru` — заголовок страницы вики Сиалы. Он тоже уникален, но по другой
    # причине: заголовки страниц уникальны на самой вики. Проверяется потому,
    # что именно здесь ФС macOS однажды уже склеила две страницы, различавшиеся
    # только регистром.
    test "заголовки страниц Сиалы не склеились между собой" do
      for name <- @siala_files do
        records = siala(name)
        titles = for r <- records, is_binary(r["ru"]), do: r["ru"]

        assert length(titles) == length(records)
        assert length(titles) == length(Enum.uniq(titles)), "siala/#{name}: дубли ru"

        # И отдельно — что регистр не склеил их тоже, независимо от ФС.
        folded = Enum.map(titles, &String.downcase/1)

        assert length(folded) == length(Enum.uniq(folded)),
               "siala/#{name}: два заголовка различаются только регистром: " <>
                 inspect(folded -- Enum.uniq(folded))
      end
    end
  end

  describe "name ключом не является — и это закреплено, а не подразумевается" do
    # ⚠️ Известные коллизии перечислены поимённо. Новая — это ПАДЕНИЕ теста,
    # то есть видимое событие, а не тихая потеря записи у следующего, кто
    # напишет `Map.new(spells, &{&1["name"], &1})`.
    test "у заклинаний Сиалы ровно одна коллизия имён, и она известна" do
      assert collisions(siala("spells"), "name") == %{
               "Energy drain" => ["energy_drain", "essence_drain"]
             }
    end

    test "у фитов Сиалы ровно одна, и это пять страниц одного умения" do
      assert collisions(siala("feats"), "name") == %{
               "Epic energy resistance" => [
                 "epic_energy_resistance_acid",
                 "epic_energy_resistance_cold",
                 "epic_energy_resistance_electrical",
                 "epic_energy_resistance_fire",
                 "epic_energy_resistance_sonic"
               ]
             }
    end

    # Положительный контроль к обоим тестам выше: детектор коллизий вообще
    # работает. Без него `== %{...}` зеленел бы и на пустом файле, и на
    # сломанном чтении.
    test "детектор коллизий не слеп" do
      assert collisions(
               [
                 %{"id" => "a", "name" => "Same"},
                 %{"id" => "b", "name" => "Same"},
                 %{"id" => "c", "name" => "Other"}
               ],
               "name"
             ) == %{"Same" => ["a", "b"]}

      assert collisions([%{"id" => "a", "name" => "Only"}], "name") == %{}
    end

    # В ванили коллизий нет — там одна страница на запись. Проверяется, чтобы
    # разница между слоями была утверждением, а не совпадением: если она
    # появится и в ванили, это уже сломанный разбор, а не законное «две
    # страницы про одно».
    test "в ванильном слое имена всё-таки уникальны" do
      for name <- @vanilla_files do
        assert collisions(vanilla(name), "name") == %{}, "vanilla/#{name}.json"
      end
    end
  end

  describe "причина коллизий: несколько страниц Сиалы на одну ванильную запись" do
    defp shared_vanilla(records) do
      records
      |> Enum.filter(&is_binary(&1["vanilla_id"]))
      |> Enum.group_by(& &1["vanilla_id"], & &1["id"])
      |> Enum.filter(fn {_id, ids} -> length(ids) > 1 end)
      |> Map.new(fn {id, ids} -> {id, Enum.sort(ids)} end)
    end

    # ⚠️ Живое место, в отличие от заклинаний: `Data.Loader.feat_target_id/2`
    # сводит такие страницы на ОДНУ запись ruleset'а. Пять страниц про
    # сопротивление говорят одно и то же, поэтому это верно; страницы,
    # говорящие разное, слились бы в одну запись, и факты обеих легли бы
    # на неё вперемешку. Новая группа — повод это перечитать.
    test "у фитов такая группа одна" do
      assert shared_vanilla(siala("feats")) == %{
               "epic_energy_resistance" => [
                 "epic_energy_resistance_acid",
                 "epic_energy_resistance_cold",
                 "epic_energy_resistance_electrical",
                 "epic_energy_resistance_fire",
                 "epic_energy_resistance_sonic"
               ]
             }
    end

    # ⚠️ А эта группа — НЕ «одно и то же разными словами». `Energy drain`
    # у шарда бьёт процентом от недостающего здоровья заклинателя
    # (Колдун / Волшебник 9), `Essence Drain` вытягивает 2d6 уровней
    # (Священник 9). Совпали они только тем, что обе страницы ссылаются
    # на одну статью Fandom, и `Essence Drain` сопоставлен `matched_by:
    # "fandom_link"`, а не по заголовку. Загрузчик заклинания Сиалы сегодня
    # не читает вовсе, поэтому в расчёт это не идёт; в день, когда начнёт
    # читать, слить их по `vanilla_id` будет НЕЛЬЗЯ — вопрос человеку.
    test "у заклинаний такая группа одна, и она подозрительная" do
      assert shared_vanilla(siala("spells")) == %{
               "energy_drain" => ["energy_drain", "essence_drain"]
             }

      essence = Enum.find(siala("spells"), &(&1["id"] == "essence_drain"))

      assert essence["matched_by"] == "fandom_link"
      assert essence["vanilla_id"] == "energy_drain"
    end
  end
end
