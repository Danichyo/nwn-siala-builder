defmodule BuildCalculator.Data.SkillPointsRecordTest do
  @moduledoc """
  Пол скилл-поинтов за уровень и множитель первого уровня — записи данных,
  а не литералы ядра (задача 4.65).

  `vanilla/rules.json` → `character.skill_points_floor_per_level` (1) и
  `character.skill_points_first_level_multiplier` (4). Источник — одна фраза
  Fandom «Skill point» (rev 55950, в кэше): «To this is added the intelligence
  modifier, subject to a minimum of 1 skill point, and the sum is quadrupled at
  character level 1»; вторые цитаты — Fandom «Intelligence» (rev 71527): тот же
  пол и порядок «пол раньше умножения». До 4.65 оба числа жили в
  `Rules.Skills.points_at/3` как `max(1, …)` и `* 4`. Вики Сиалы общего правила
  не пишет, слой Сиалы записи наследует; таблица игры держит множитель по расе
  (`racialtypes.2da` → `FirstLevelSkillPointsMultiplier`, 4 у всех семи рас базы
  и хака) — это сверяет `mix base2da.diff` / `mix hak2da.diff` с числом ruleset'а.

  🔴 Умолчания нет. Записи нет (или она не `verified`) — ruleset говорит
  `{:missing_data, …}`, ядро скилл-поинты не считает (`earned`/`free` — `nil`,
  тот же гэп у билда); подписанная битая запись роняет сборку. Положительный
  контроль — полная загрузка копии данных без записи и с другими числами.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Data.Loader.Character
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Skills}

  @vanilla_rules "priv/rules/vanilla/rules.json"
  @siala_overrides "priv/rules/siala_41/overrides.json"
  @floor "skill_points_floor_per_level"
  @multiplier "skill_points_first_level_multiplier"
  @floor_gap {:missing_data, :skill_points_floor_per_level}
  @multiplier_gap {:missing_data, :skill_points_first_level_multiplier}

  setup_all do
    vanilla_ov = @vanilla_rules |> File.read!() |> Jason.decode!()

    %{
      vanilla_ov: vanilla_ov,
      floor: vanilla_ov["character"][@floor],
      multiplier: vanilla_ov["character"][@multiplier]
    }
  end

  # Копия `priv/rules`, у которой ванильные записи заменены (`nil` — вырезана).
  defp load_with(vanilla_ov, records) do
    root = BuildCalculator.TmpDir.unique_path!("skill_points_")
    File.cp_r!("priv/rules", root)

    ov =
      Enum.reduce(records, vanilla_ov, fn
        {key, nil}, acc -> update_in(acc, ["character"], &Map.delete(&1, key))
        {key, record}, acc -> put_in(acc, ["character", key], record)
      end)

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

  # Полуорк (INT −2, races.json) с INT 8 → 6, модификатор −2: у воина
  # (2 очка, classes.json ← fandom:Fighter) сумма 0 — пол срабатывает. Человек
  # INT 10 — над полом, и с расовой прибавкой (+1 за уровень, races.json ←
  # fandom:Human rev 70207) внутри умножения.
  defp fighter(version, race, int, levels) do
    Build.new(
      ruleset_version: version,
      race: race,
      levels: List.duplicate(:fighter, levels),
      base_abilities: %{str: 14, dex: 12, con: 14, int: int, wis: 10, cha: 10}
    )
  end

  describe "записи в ванильном слое" do
    # source: fandom:Skill point rev 55950, fandom:Intelligence rev 71527 (priv/wiki_cache/fandom/)
    test "пол — 1, множитель — 4, оба проверены, со страниц кэша", ctx do
      for {record, value} <- [{ctx.floor, 1}, {ctx.multiplier, 4}] do
        assert %{
                 "value" => ^value,
                 "status" => "verified",
                 "source" => %{
                   "kind" => "wiki",
                   "wiki" => "fandom",
                   "page" => "Skill point",
                   "revid" => 55_950,
                   "in_cache" => true
                 },
                 "source_2" => %{
                   "kind" => "wiki",
                   "wiki" => "fandom",
                   "page" => "Intelligence",
                   "revid" => 71_527,
                   "in_cache" => true
                 }
               } = record
      end
    end

    test "значения — те самые числа, которые называют цитаты", ctx do
      assert [_, named] = Regex.run(~r/a minimum of (\d+) skill point/, ctx.floor["quote"])
      assert String.to_integer(named) == ctx.floor["value"]
      assert [_, again] = Regex.run(~r/a minimum of (\d+) skill point/, ctx.floor["quote_2"])
      assert String.to_integer(again) == ctx.floor["value"]

      # «quadrupled» — слово, а не цифра: словарь ровно на этот глагол.
      times = %{"doubled" => 2, "tripled" => 3, "quadrupled" => 4}
      assert [_, word] = Regex.run(~r/the sum is (\w+) at/, ctx.multiplier["quote"])
      assert Map.fetch!(times, word) == ctx.multiplier["value"]
      assert ctx.multiplier["quote_2"] =~ "before quadrupling"
    end

    test "цитаты дословно стоят на страницах кэша тех же ревизий", ctx do
      index = "priv/wiki_cache/fandom/_index.json" |> File.read!() |> Jason.decode!()

      for record <- [ctx.floor, ctx.multiplier], n <- ["", "_2"] do
        source = record["source" <> n]
        page = "priv/wiki_cache/fandom/#{source["page"]}.wikitext" |> File.read!() |> normalize()

        assert String.contains?(page, normalize(record["quote" <> n])), source["page"]
        assert Enum.find(index, &(&1["title"] == source["page"]))["revid"] == source["revid"]
      end
    end

    # Вики Сиалы общего правила не пишет — записи наследуются, слой их не называет.
    test "слой Сиалы чисел не переопределяет, у обоих ruleset'ов они одни", ctx do
      siala_ov = @siala_overrides |> File.read!() |> Jason.decode!()

      for key <- [@floor, @multiplier] do
        refute Map.has_key?(siala_ov["character"] || %{}, key)
      end

      for version <- ["vanilla", "siala_41"] do
        ruleset = Data.ruleset!(version)
        assert ruleset.skill_points_floor_per_level == ctx.floor["value"]
        assert ruleset.skill_points_first_level_multiplier == ctx.multiplier["value"]
        refute @floor_gap in ruleset.gaps
        refute @multiplier_gap in ruleset.gaps
      end
    end
  end

  describe "Character — умолчания нет" do
    @good %{
      "value" => 1,
      "quote" => "subject to a minimum of 1 skill point",
      "source" => %{"kind" => "wiki", "wiki" => "fandom", "page" => "Skill point"},
      "status" => "verified"
    }

    defp ov(key, record), do: %{"character" => %{key => record}}

    defp read(@floor, ov), do: Character.skill_points_floor_per_level(ov)
    defp read(@multiplier, ov), do: Character.skill_points_first_level_multiplier(ov)

    test "проверенная запись с цитатой и источником отдаёт своё число" do
      for key <- [@floor, @multiplier] do
        assert read(key, ov(key, @good)) == 1
        assert read(key, ov(key, %{@good | "value" => 4})) == 4
      end
    end

    test "записи нет или она не проверена — nil, а не «1» и не «4»" do
      for key <- [@floor, @multiplier],
          record <- [
            %{@good | "status" => "unclear"},
            %{@good | "status" => "assumed"},
            Map.delete(@good, "status"),
            %{"status" => "unclear", "value" => "four"}
          ] do
        assert read(key, ov(key, record)) == nil, "#{key}: #{inspect(record)}"
      end

      for key <- [@floor, @multiplier] do
        assert read(key, %{"character" => %{}}) == nil
        assert read(key, %{}) == nil
      end
    end

    test "проверенная, но битая запись роняет сборку" do
      broken = [
        Map.delete(@good, "value"),
        %{@good | "value" => 0},
        %{@good | "value" => -1},
        %{@good | "value" => "4"},
        %{@good | "value" => 4.0},
        Map.delete(@good, "quote"),
        %{@good | "quote" => "  "},
        Map.delete(@good, "source"),
        %{@good | "source" => %{}},
        %{@good | "source" => "fandom:Skill point"},
        4,
        "4"
      ]

      for key <- [@floor, @multiplier], record <- broken do
        assert_raise RuntimeError, ~r/character\.#{key}/, fn -> read(key, ov(key, record)) end
      end
    end
  end

  describe "положительный контроль — полная загрузка копии данных" do
    test "без записи пола — гэп ruleset'а и скилл-поинтов нет ни на одном уровне", ctx do
      loaded = load_with(ctx.vanilla_ov, [{@floor, nil}])

      for version <- ["vanilla", "siala_41"] do
        ruleset = Map.fetch!(loaded, version)
        real = Data.ruleset!(version)

        assert ruleset.skill_points_floor_per_level == nil
        assert ruleset.gaps -- [@floor_gap] == real.gaps
        assert @floor_gap in ruleset.gaps

        assert %{
                 ruleset
                 | skill_points_floor_per_level: real.skill_points_floor_per_level,
                   gaps: real.gaps
               } ==
                 real

        build = fighter(version, :human, 10, 3)
        stats = Rules.compute(build, ruleset)

        assert %{earned: nil, free: nil, spent: 0} = stats.skill_points
        assert @floor_gap in stats.gaps
        refute @multiplier_gap in stats.gaps
        assert Skills.gaps(build, ruleset) == [@floor_gap]
        for level <- 1..3, do: assert(Skills.points_at(build, ruleset, level) == nil)

        # Пустой билд ничего не получает и ничего не просит.
        empty = Rules.compute(fighter(version, :human, 10, 0), ruleset)
        assert empty.skill_points == %{earned: 0, spent: 0, free: 0}
        refute @floor_gap in empty.gaps

        # Положительный контроль: на настоящем ruleset'е тот же билд считается.
        assert %{earned: 18, free: 18} = Rules.compute(build, real).skill_points
        assert Skills.gaps(build, real) == []

        # Граничные уровни и четыре класса: пол нужен КАЖДОМУ уровню — первому,
        # 20-му и 21-му (эпик), 41-му (кап Сиалы; ваниль 41-го не даёт, но
        # `points_at/3` спрашивает число, а не законность), — и гэп назван один раз.
        wide =
          Build.new(
            ruleset_version: version,
            race: :human,
            levels:
              List.duplicate(:barbarian, 11) ++
                List.duplicate(:fighter, 10) ++
                List.duplicate(:rogue, 10) ++ List.duplicate(:wizard, 10),
            base_abilities: %{str: 14, dex: 12, con: 14, int: 10, wis: 10, cha: 10}
          )

        for level <- [1, 20, 21, 41] do
          assert Skills.points_at(wide, ruleset, level) == nil, "уровень #{level}"
          assert is_integer(Skills.points_at(wide, real, level)), "уровень #{level}"
        end

        assert Skills.gaps(wide, ruleset) == [@floor_gap]
        assert Skills.gaps(wide, real) == []
      end
    end

    # Множитель нужен только первому уровню персонажа — второй считается.
    test "без записи множителя — гэп, первый уровень без очков, второй с очками", ctx do
      loaded = load_with(ctx.vanilla_ov, [{@multiplier, nil}])

      for version <- ["vanilla", "siala_41"] do
        ruleset = Map.fetch!(loaded, version)
        real = Data.ruleset!(version)

        assert ruleset.skill_points_first_level_multiplier == nil
        assert ruleset.gaps -- [@multiplier_gap] == real.gaps

        build = fighter(version, :human, 10, 2)
        stats = Rules.compute(build, ruleset)

        assert Skills.points_at(build, ruleset, 1) == nil
        assert Skills.points_at(build, ruleset, 2) == Skills.points_at(build, real, 2)
        assert %{earned: nil, free: nil} = stats.skill_points
        assert Skills.gaps(build, ruleset) == [@multiplier_gap]
        assert @multiplier_gap in stats.gaps
        refute @floor_gap in stats.gaps
      end
    end

    # Подписанная битая запись роняет загрузку целиком — тот же путь, каким
    # `mix compile` роняет сборку (`Data` грузит ruleset на этапе компиляции).
    test "подписанная битая запись в копии данных роняет загрузку", ctx do
      for {key, record} <- [{@floor, ctx.floor}, {@multiplier, ctx.multiplier}] do
        assert_raise RuntimeError, ~r/character\.#{key}/, fn ->
          load_with(ctx.vanilla_ov, [{key, %{record | "value" => "1"}}])
        end
      end
    end

    test "без обеих записей билд называет обе, а не первую попавшуюся", ctx do
      loaded = load_with(ctx.vanilla_ov, [{@floor, nil}, {@multiplier, nil}])
      ruleset = loaded["vanilla"]
      build = fighter("vanilla", :half_orc, 8, 2)

      assert Skills.gaps(build, ruleset) == [@floor_gap, @multiplier_gap]
      assert @floor_gap in Rules.compute(build, ruleset).gaps
      assert @multiplier_gap in Rules.compute(build, ruleset).gaps
    end

    # Другие числа в записях доходят до обоих ruleset'ов и до очков: пол 2 и
    # множитель 3 — не правило игры, а метка пути числа из данных в ответ.
    test "другие числа в записях — другие очки, и только там, где число решает", ctx do
      loaded =
        load_with(ctx.vanilla_ov, [
          {@floor, %{ctx.floor | "value" => ctx.floor["value"] + 1}},
          {@multiplier, %{ctx.multiplier | "value" => ctx.multiplier["value"] - 1}}
        ])

      for version <- ["vanilla", "siala_41"] do
        ruleset = Map.fetch!(loaded, version)
        real = Data.ruleset!(version)
        assert ruleset.skill_points_floor_per_level == 2
        assert ruleset.skill_points_first_level_multiplier == 3

        floored = fighter(version, :half_orc, 8, 2)

        # Полуорк воин INT 6: 2 − 2 = 0 → пол. Настоящие числа: 1 × 4, затем 1.
        assert Skills.points_at(floored, real, 1) == 4
        assert Skills.points_at(floored, real, 2) == 1
        # Пол 2 и множитель 3: 2 × 3, затем 2.
        assert Skills.points_at(floored, ruleset, 1) == 6
        assert Skills.points_at(floored, ruleset, 2) == 2

        above = fighter(version, :human, 10, 2)

        # Человек воин INT 10: (2 + 0) + 1 — над обоими полами; меняет только множитель.
        assert Skills.points_at(above, real, 1) == 12
        assert Skills.points_at(above, ruleset, 1) == 9
        assert Skills.points_at(above, ruleset, 2) == Skills.points_at(above, real, 2)

        assert %{
                 ruleset
                 | skill_points_floor_per_level: real.skill_points_floor_per_level,
                   skill_points_first_level_multiplier: real.skill_points_first_level_multiplier
               } == real
      end
    end
  end
end
