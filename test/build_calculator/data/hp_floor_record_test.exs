defmodule BuildCalculator.Data.HpFloorRecordTest do
  @moduledoc """
  Пол HP за уровень — запись данных, а не литерал ядра (задача 4.56).

  `vanilla/rules.json` → `character.hit_points_floor_per_level`, источник —
  Fandom «Hit point» (rev 62785, в кэше): «There is a minimum of 1 hit point
  for each level, though, after combining the base and bonus hit points
  associated with that level». Таблицы игры пола не называют (в `ruleset.2da`
  такой строки нет — движок), вики Сиалы о нём молчит, слой Сиалы запись
  наследует.

  🔴 Умолчания у пола нет. Записи нет (или она не `verified`) — ruleset
  говорит `{:missing_data, :hp_floor_per_level}`, а ядро отказывается считать
  HP тем же гэпом, как у `max_classes`; подписанная, но битая запись роняет
  сборку (`Character.hp_floor_per_level/1`). Единица вместо `nil` не
  подставляется нигде. Положительный контроль — полная загрузка копии данных
  без записи и с другим числом: первая даёт гэп и отказ HP и больше ничего
  не сдвигает, вторая доносит число до обоих ruleset'ов и до HP билда.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Data.Loader.Character
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build

  @vanilla_rules "priv/rules/vanilla/rules.json"
  @siala_overrides "priv/rules/siala_41/overrides.json"
  @page "priv/wiki_cache/fandom/Hit point.wikitext"

  setup_all do
    vanilla_ov = @vanilla_rules |> File.read!() |> Jason.decode!()
    %{vanilla_ov: vanilla_ov, record: vanilla_ov["character"]["hit_points_floor_per_level"]}
  end

  # Копия `priv/rules`, у которой ванильная запись пола заменена (`nil` — вырезана).
  defp load_with(vanilla_ov, record) do
    root = BuildCalculator.TmpDir.unique_path!("hp_floor_")
    File.cp_r!("priv/rules", root)

    ov =
      case record do
        nil -> update_in(vanilla_ov, ["character"], &Map.delete(&1, "hit_points_floor_per_level"))
        _ -> put_in(vanilla_ov, ["character", "hit_points_floor_per_level"], record)
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
    |> String.replace(~r/\s+/u, " ")
  end

  describe "запись в ванильном слое" do
    # source: fandom:Hit point, rev 62785 (priv/wiki_cache/fandom/Hit point.wikitext)
    test "пол — 1, проверен, со страницы Fandom «Hit point» rev 62785", %{record: record} do
      assert %{
               "value" => 1,
               "status" => "verified",
               "source" => %{
                 "kind" => "wiki",
                 "wiki" => "fandom",
                 "page" => "Hit point",
                 "revid" => 62_785,
                 "in_cache" => true
               }
             } = record
    end

    test "значение — то самое число, которое называет цитата", %{record: record} do
      assert [_, named] =
               Regex.run(~r/a minimum of (\d+) hit points? for each level/, record["quote"])

      assert String.to_integer(named) == record["value"]

      assert [_, again] =
               Regex.run(~r/the same (\d+) hit points? per level minimum/, record["quote_2"])

      assert String.to_integer(again) == record["value"]
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
        |> Enum.find(&(&1["title"] == "Hit point"))

      assert index["revid"] == record["source"]["revid"]
      assert index["revid"] == record["source_2"]["revid"]
    end

    # Вики Сиалы о поле молчит — запись наследуется, слой её не называет.
    test "слой Сиалы пол не переопределяет, у обоих ruleset'ов он один", %{record: record} do
      siala_ov = @siala_overrides |> File.read!() |> Jason.decode!()
      refute Map.has_key?(siala_ov["character"] || %{}, "hit_points_floor_per_level")

      assert Data.ruleset!("vanilla").hp_floor_per_level == record["value"]
      assert Data.ruleset!("siala_41").hp_floor_per_level == record["value"]
    end
  end

  describe "Character.hp_floor_per_level/1 — умолчания нет" do
    @good %{
      "value" => 1,
      "quote" => "a minimum of 1 hit point for each level",
      "source" => %{"kind" => "wiki", "wiki" => "fandom", "page" => "Hit point"},
      "status" => "verified"
    }

    defp ov(record), do: %{"character" => %{"hit_points_floor_per_level" => record}}

    test "проверенная запись с цитатой и источником отдаёт своё число" do
      assert Character.hp_floor_per_level(ov(@good)) == 1
      assert Character.hp_floor_per_level(ov(%{@good | "value" => 3})) == 3
    end

    # Как у соседей по секции: «никто не утвердил» — дыра, а не падение.
    test "записи нет или она не проверена — nil, а не «1»" do
      for record <- [
            %{@good | "status" => "unclear"},
            %{@good | "status" => "assumed"},
            Map.delete(@good, "status"),
            # Неподписанная запись не обязана быть целой: она ничего не решает.
            %{"status" => "unclear", "value" => "one"}
          ] do
        assert Character.hp_floor_per_level(ov(record)) == nil, inspect(record)
      end

      assert Character.hp_floor_per_level(%{"character" => %{}}) == nil
      assert Character.hp_floor_per_level(%{}) == nil
    end

    # Подписанная запись, которая не может быть правилом, тихо сняла бы гэп или
    # дала бы число без опоры — поэтому падение, как у `hit_points_roll`.
    test "проверенная, но битая запись роняет сборку" do
      broken = [
        Map.delete(@good, "value"),
        %{@good | "value" => 0},
        %{@good | "value" => -1},
        %{@good | "value" => "1"},
        %{@good | "value" => 1.0},
        Map.delete(@good, "quote"),
        %{@good | "quote" => "  "},
        Map.delete(@good, "source"),
        %{@good | "source" => %{}},
        %{@good | "source" => "fandom:Hit point"},
        # Не карта вовсе — это не «записи нет».
        1,
        "1"
      ]

      for record <- broken do
        assert_raise RuntimeError, ~r/hit_points_floor_per_level/, fn ->
          Character.hp_floor_per_level(ov(record))
        end
      end
    end
  end

  describe "положительный контроль — полная загрузка копии данных" do
    # Без записи — гэп ruleset'а у обоих и отказ HP у каждого билда, тем же
    # кортежем; и ничего больше в ruleset'ах не сдвигается (`max_classes` ведёт
    # себя так же — `data_test.exs`, «missing optional files»).
    test "без записи пола — гэп и отказ HP, а не единица", %{vanilla_ov: ov} do
      loaded = load_with(ov, nil)
      gap = {:missing_data, :hp_floor_per_level}

      for version <- ["vanilla", "siala_41"] do
        ruleset = Map.fetch!(loaded, version)
        real = Data.ruleset!(version)

        assert ruleset.hp_floor_per_level == nil
        assert gap in ruleset.gaps
        refute gap in real.gaps
        assert ruleset.gaps -- [gap] == real.gaps
        assert %{ruleset | hp_floor_per_level: real.hp_floor_per_level, gaps: real.gaps} == real

        build =
          Build.new(
            ruleset_version: version,
            levels: [:fighter],
            base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
          )

        stats = Rules.compute(build, ruleset)

        assert stats.hp == nil
        assert stats.hp_naked == nil
        assert stats.hp_breakdown == nil
        assert gap in stats.gaps

        # Положительный контроль: на настоящем ruleset'е тот же билд считается.
        assert is_integer(Rules.compute(build, real).hp)
      end
    end

    # Число из данных доходит до обоих ruleset'ов и до HP: другое число в записи —
    # другое HP у билда, где пол срабатывает, и то же HP у билда, где не срабатывает.
    test "другое число в записи — другой пол у обоих ruleset'ов и другое HP", %{
      vanilla_ov: ov,
      record: record
    } do
      # На единицу выше записанного, а не литерал: тест про путь числа из данных
      # в ответ, само число держат тесты выше.
      higher = record["value"] + 1
      loaded = load_with(ov, %{record | "value" => higher})

      floored = fn version ->
        Build.new(
          ruleset_version: version,
          levels: List.duplicate(:wizard, 3),
          base_abilities: %{str: 10, dex: 10, con: 3, int: 10, wis: 10, cha: 10}
        )
      end

      for version <- ["vanilla", "siala_41"] do
        ruleset = Map.fetch!(loaded, version)
        real = Data.ruleset!(version)
        assert ruleset.hp_floor_per_level == higher

        # Wizard d4 (fandom:Wizard rev 72067), CON 3 → −4: 0 за уровень — ровно пол,
        # три уровня, на единицу выше — три хита сверху.
        raised = Rules.compute(floored.(version), ruleset)
        stats = Rules.compute(floored.(version), real)

        assert raised.hp - stats.hp == 3
        assert raised.hp_breakdown.floor_per_level == higher
        assert raised.hp_breakdown.floor_adjustment == 3 * higher

        # Всё остальное в ruleset'е — то же самое, поле в поле.
        assert %{ruleset | hp_floor_per_level: real.hp_floor_per_level} == real
      end
    end
  end
end
