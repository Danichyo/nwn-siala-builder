defmodule BuildCalculator.Data.BaseAcRecordTest do
  @moduledoc """
  База AC — запись данных, а не литерал загрузчика (задача 4.65).

  `vanilla/rules.json` → `_vanilla_constants_confirmed.base_ac` (10, `verified`,
  Fandom «Armor class» rev 71718, в кэше): «AC = 10 + armor bonus + …» и «The
  average, unarmored peasant has an AC of 10». До 4.65 число жило литералом
  `@base_ac 10` в `Data.Loader.Reading` с комментарием «Not stated in any file …
  TODO: verify», а из записи читался только источник подписи
  `{:assumed, :base_ac, 10, "fandom:Armor class"}` — число подписи и цитата
  могли разойтись молча. Таблицы игры базы не называют (в `ruleset.2da` строки
  нет), вики Сиалы о ней молчит, слой Сиалы запись наследует.

  🔴 Умолчания нет: записи нет (или она не `verified`) — `{:missing_data, :base_ac}`
  вместо подписи, AC голым и в экипировке — `nil`; подписанная битая запись роняет
  сборку. Положительный контроль — полная загрузка копии данных без записи и с
  другим числом.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Data.Loader.Character
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}

  @vanilla_rules "priv/rules/vanilla/rules.json"
  @siala_overrides "priv/rules/siala_41/overrides.json"
  @page "priv/wiki_cache/fandom/Armor class.wikitext"
  @gap {:missing_data, :base_ac}

  setup_all do
    vanilla_ov = @vanilla_rules |> File.read!() |> Jason.decode!()
    %{vanilla_ov: vanilla_ov, record: vanilla_ov["_vanilla_constants_confirmed"]["base_ac"]}
  end

  defp load_with(vanilla_ov, record) do
    root = BuildCalculator.TmpDir.unique_path!("base_ac_")
    File.cp_r!("priv/rules", root)

    ov =
      case record do
        nil -> update_in(vanilla_ov, ["_vanilla_constants_confirmed"], &Map.delete(&1, "base_ac"))
        _ -> put_in(vanilla_ov, ["_vanilla_constants_confirmed", "base_ac"], record)
      end

    File.write!(Path.join(root, "vanilla/rules.json"), Jason.encode!(ov))

    try do
      Loader.load!(root)
    after
      File.rm_rf!(root)
    end
  end

  defp normalize(text) do
    text
    |> String.replace(~r/\[\[(?:[^\]|]*\|)?([^\]]+)\]\]/, "\\1")
    |> String.replace(~r/'''/, "")
    |> String.replace(~r/\s+/u, " ")
  end

  # Воин 3, DEX 14 (+2), в латах и с башенным щитом и вписанным отклонением —
  # чтобы «в экипировке» отличалось от «голым».
  defp build(version) do
    Build.new(
      ruleset_version: version,
      race: :human,
      levels: List.duplicate(:fighter, 3),
      base_abilities: %{str: 14, dex: 14, con: 14, int: 10, wis: 10, cha: 10},
      gear: %Gear{worn: %{armor: :full_plate, shield: :tower}, ac: %{deflection: 2}}
    )
  end

  describe "запись в ванильном слое" do
    # source: fandom:Armor class rev 71718 (priv/wiki_cache/fandom/Armor class.wikitext)
    test "база — 10, проверена, со страницы Fandom «Armor class» rev 71718", %{record: record} do
      assert %{
               "value" => 10,
               "status" => "verified",
               "source" => %{
                 "kind" => "wiki",
                 "wiki" => "fandom",
                 "page" => "Armor class",
                 "revid" => 71_718,
                 "in_cache" => true
               }
             } = record
    end

    test "значение — то самое число, которое называют обе цитаты", %{record: record} do
      assert [_, formula] = Regex.run(~r/AC = (\d+) \+/, record["quote"])
      assert String.to_integer(formula) == record["value"]
      assert [_, peasant] = Regex.run(~r/has an AC of (\d+)/, record["quote_2"])
      assert String.to_integer(peasant) == record["value"]
    end

    test "обе цитаты дословно стоят на странице кэша той же ревизии", %{record: record} do
      page = @page |> File.read!() |> normalize()

      for key <- ~w(quote quote_2) do
        assert String.contains?(page, normalize(record[key])), key
      end

      index =
        "priv/wiki_cache/fandom/_index.json"
        |> File.read!()
        |> Jason.decode!()
        |> Enum.find(&(&1["title"] == "Armor class"))

      assert index["revid"] == record["source"]["revid"]
    end

    test "слой Сиалы базу не переопределяет; число и подпись — из одной записи", %{record: record} do
      siala_ov = @siala_overrides |> File.read!() |> Jason.decode!()
      refute Map.has_key?(siala_ov["_vanilla_constants_confirmed"] || %{}, "base_ac")

      for version <- ["vanilla", "siala_41"] do
        ruleset = Data.ruleset!(version)
        assert ruleset.base_ac == record["value"]
        assert {:assumed, :base_ac, record["value"], "fandom:Armor class"} in ruleset.gaps
        refute @gap in ruleset.gaps
      end
    end
  end

  describe "Character.base_ac/1 — умолчания нет" do
    @good %{
      "value" => 10,
      "quote" => "The average, unarmored peasant has an AC of 10.",
      "source" => %{"kind" => "wiki", "wiki" => "fandom", "page" => "Armor class"},
      "status" => "verified"
    }

    defp ov(record), do: %{"_vanilla_constants_confirmed" => %{"base_ac" => record}}

    test "проверенная запись с цитатой и источником отдаёт своё число" do
      assert Character.base_ac(ov(@good)) == 10
      assert Character.base_ac(ov(%{@good | "value" => 11})) == 11
    end

    test "записи нет или она не проверена — nil, а не «10»" do
      for record <- [
            %{@good | "status" => "unclear"},
            Map.delete(@good, "status"),
            %{"status" => "assumed", "value" => "ten"}
          ] do
        assert Character.base_ac(ov(record)) == nil, inspect(record)
      end

      assert Character.base_ac(%{"_vanilla_constants_confirmed" => %{}}) == nil
      assert Character.base_ac(%{}) == nil
    end

    test "проверенная, но битая запись роняет сборку" do
      for record <- [
            Map.delete(@good, "value"),
            %{@good | "value" => 0},
            %{@good | "value" => "10"},
            Map.delete(@good, "quote"),
            Map.delete(@good, "source"),
            %{@good | "source" => %{}},
            10
          ] do
        assert_raise RuntimeError, ~r/_vanilla_constants_confirmed\.base_ac/, fn ->
          Character.base_ac(ov(record))
        end
      end
    end
  end

  describe "положительный контроль — полная загрузка копии данных" do
    test "без записи — гэп вместо подписи и AC нет ни голым, ни в экипировке", %{vanilla_ov: ov} do
      loaded = load_with(ov, nil)

      for version <- ["vanilla", "siala_41"] do
        ruleset = Map.fetch!(loaded, version)
        real = Data.ruleset!(version)
        caveat = Enum.find(real.gaps, &match?({:assumed, :base_ac, _, _}, &1))

        assert ruleset.base_ac == nil
        assert @gap in ruleset.gaps
        refute Enum.any?(ruleset.gaps, &match?({:assumed, :base_ac, _, _}, &1))
        assert ruleset.gaps -- [@gap] == real.gaps -- [caveat]
        assert %{ruleset | base_ac: real.base_ac, gaps: real.gaps} == real

        stats = Rules.compute(build(version), ruleset)
        assert stats.ac_naked == nil
        assert stats.ac_geared == nil
        assert @gap in stats.gaps

        # Положительный контроль: на настоящем ruleset'е тот же билд считается.
        control = Rules.compute(build(version), real)
        assert is_integer(control.ac_naked) and is_integer(control.ac_geared)
        refute @gap in control.gaps
      end
    end

    # Подписанная битая запись роняет загрузку целиком — тот же путь, каким
    # `mix compile` роняет сборку (`Data` грузит ruleset на этапе компиляции).
    test "подписанная битая запись в копии данных роняет загрузку", %{
      vanilla_ov: ov,
      record: record
    } do
      assert_raise RuntimeError, ~r/_vanilla_constants_confirmed\.base_ac/, fn ->
        load_with(ov, %{record | "value" => 0})
      end
    end

    test "другое число в записи — другой AC у обоих ruleset'ов и та же подпись с ним", %{
      vanilla_ov: ov,
      record: record
    } do
      loaded = load_with(ov, %{record | "value" => record["value"] + 1})

      for version <- ["vanilla", "siala_41"] do
        ruleset = Map.fetch!(loaded, version)
        real = Data.ruleset!(version)

        assert ruleset.base_ac == record["value"] + 1
        assert {:assumed, :base_ac, record["value"] + 1, "fandom:Armor class"} in ruleset.gaps

        raised = Rules.compute(build(version), ruleset)
        stats = Rules.compute(build(version), real)
        assert raised.ac_naked - stats.ac_naked == 1
        assert raised.ac_geared - stats.ac_geared == 1
      end
    end
  end
end
