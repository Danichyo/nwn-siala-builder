defmodule BuildCalculator.Data.VanillaLayerTest do
  @moduledoc """
  Ванильный ruleset самодостаточен и берёт уровни — задача 4.1 (25.09.2026,
  `VANILLA.md` §4.1, принцип 1 §2: «`vanilla` самодостаточен, `siala_41` =
  `vanilla` + только отличия шарда»).

  До задачи ваниль собиралась из четырёх секций СИАЛЬСКОГО `overrides.json`
  (`@vanilla_sections` загрузчика: stat_caps, gear, formulas,
  _vanilla_constants_confirmed), секция `character` до неё не доезжала вовсе,
  а словарь получателей лежал в шапке `siala_41/classes.json`. Итог разведки
  25.09.2026 (`VANILLA.md` §3.1–3.2):

    * без каталога `siala_41/` загрузка не падала, но ваниль молча теряла
      11 полей — поинт-бай, потолки, круги заклинаний, ввод вещей;
    * `max_classes: nil` — и ни один из 23 классов не брался на 1-м уровне ни
      при одном из 10 мировоззрений: `{:missing_data, :max_classes}` у всех.

  Теперь ванильные правила лежат в `vanilla/rules.json`, Сиала кладёт свой
  `overrides.json` поверх по тем же ключам (`Data.Loader.Layers`), и три
  утверждения этого файла держат это состояние — каждое с контролем.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp copy_rules do
    root = BuildCalculator.TmpDir.unique_path!()
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  describe "ваниль самодостаточна" do
    # 🔴 Главное утверждение задачи 4.1: ванильный ruleset не читает ни одного
    # файла шарда. Копия без каталога `siala_41/` обязана дать ваниль, равную
    # скомпилированной, — поле в поле, а не «похожую».
    #
    # ⚠️ С задачи 4.4 у слоя шарда есть файл ВНЕ его каталога — `name_map.json`
    # в корне `priv/rules/` (там его пишет `mix wiki.fetch`): написания вики
    # Сиалы. Он уходит из копии вместе с каталогом.
    test "без каталога siala_41/ ваниль та же, что скомпилированная", %{
      vanilla: vanilla,
      siala: siala
    } do
      root = copy_rules()
      File.rm_rf!(Path.join(root, "siala_41"))
      File.rm!(Path.join(root, "name_map.json"))

      # Положительный контроль к самой копии: сиального слоя в ней нет вовсе.
      refute File.exists?(Path.join(root, "siala_41"))
      refute File.exists?(Path.join(root, "name_map.json"))
      assert File.exists?(Path.join(root, "vanilla/rules.json"))

      loaded = Loader.load!(root)

      assert loaded["vanilla"] == vanilla

      # ...и копия действительно другая: собранная из неё «Сиала» от настоящей
      # отличается, то есть равенство выше не про копию, которая всё ещё несёт
      # сиальские файлы.
      refute loaded["siala_41"] == siala
      assert loaded["siala_41"].max_classes == 3
      assert loaded["siala_41"].level_cap == 40
    end

    # ⚠️ Без сиального слоя «Сиала» совпадает с ванилью во всём, кроме имени
    # и слоёв. До задачи 4.6 (26.09.2026) отличалось ещё одно поле — резисты:
    # сиальский двойник `Epic energy resistance` (15/150 вместо ванильных
    # 10/100) лежал в ВАНИЛЬНОМ файле разметки и выбирался сравнением имени
    # ruleset'а с полем данных — последняя такая ветка загрузчика. Теперь он в
    # слое Сиалы (`siala_41/feat_resistance_bonuses.json`), и без этого слоя
    # имя не решает ничего; тест стоит, чтобы двойник не вернулся в ванильный
    # файл незамеченным.
    test "без сиального слоя имя ruleset'а не решает ничего" do
      # Слой шарда — каталог `siala_41/` и `name_map.json` в корне (задача 4.4,
      # см. тест выше): без второго «Сиала» несла бы написания вики, которых
      # у ванили нет, и сравнение ниже сравнивало бы не то.
      root = copy_rules()
      File.rm_rf!(Path.join(root, "siala_41"))
      File.rm!(Path.join(root, "name_map.json"))
      loaded = Loader.load!(root)
      bare_siala = %{loaded["siala_41"] | version: "vanilla", layers: ["vanilla"]}

      assert bare_siala == loaded["vanilla"]

      epic = fn ruleset ->
        Enum.find(ruleset.resistance_bonuses.applied, &(&1.id == :epic_energy_resistance))
      end

      assert epic.(bare_siala).amount == %{kind: :per_take, bonus: 10, max_total: 100}

      # ...а со своим слоем Сиала получает свои числа — положительный контроль
      # того, что равенство выше не про слой, который молча перестал читаться.
      assert epic.(Data.ruleset!("siala_41")).amount == %{
               kind: :per_take,
               bonus: 15,
               max_total: 150
             }
    end

    # Файл ванильного слоя зарегистрирован там, где его правка обязана
    # пересобирать `BuildCalculator.Data`, и не читается как словарь выбора.
    test "vanilla/rules.json — исходник ruleset'а, а не словарь выбора", %{vanilla: vanilla} do
      assert "vanilla/rules.json" in Loader.source_files()
      refute Map.has_key?(vanilla.choice_domains, :rules)
      refute Map.has_key?(vanilla.choice_domains, :rule)
    end
  end

  # Задача 4.4: `priv/rules/name_map.json` — английские имена и их написания
  # на вики Сиалы (редиректы шарда). До 4.4 он грузился в оба ruleset'а, и
  # ваниль показывала под заклинанием «на вики — «…»» и искала по русским
  # алиасам. Это данные шарда (VANILLA.md §2, принцип 1) — теперь их читает
  # только слой шарда, а файл лежит, где его пишет `mix wiki.fetch`.
  describe "name_map — написания вики Сиалы, слой шарда (задача 4.4)" do
    test "у ванили словаря нет, у Сиалы он есть", %{vanilla: vanilla, siala: siala} do
      assert vanilla.name_map == %{}

      # Положительный контроль: у Сиалы словарь на месте.
      assert siala.name_map["Toughness"] == "Живучесть"
    end

    test "ваниль файл не читает: правка name_map.json меняет только Сиалу" do
      root = copy_rules()
      File.write!(Path.join(root, "name_map.json"), Jason.encode!(%{"Toughness" => "Проба"}))

      loaded = Loader.load!(root)

      assert loaded["vanilla"].name_map == %{}
      assert loaded["siala_41"].name_map == %{"Toughness" => "Проба"}
    end
  end

  describe "лимит классов ванили — три, из данных" do
    # source: vanilla/rules.json → character.max_classes — fandom «Character
    # level», rev 71153 (в кэше, строка 1): «(with up to three classes
    # allowed)»; fandom «Class», rev 70979 (снята через api.php 25.09.2026):
    # «Neverwinter Nights Enhanced Edition since update 35 internally allows up
    # to eight classes, through the true limit depends on ruleset.2da settings
    # on the client or module … As a result, the limit is set to three by
    # default». Сиала переопределяет своим 4 (слово Dan, 01.08.2026).
    test "три у ванили, четыре у Сиалы, и оба — из слоя", %{vanilla: vanilla, siala: siala} do
      assert vanilla.max_classes == 3
      assert siala.max_classes == 4

      for ruleset <- [vanilla, siala] do
        refute {:missing_data, :max_classes} in ruleset.gaps
      end

      rules = "priv/rules/vanilla/rules.json" |> File.read!() |> Jason.decode!()
      record = rules["character"]["max_classes"]

      assert record["value"] == 3
      assert record["status"] == "verified"
      assert record["source"]["page"] == "Character level"
      assert record["source"]["revid"] == 71_153
      assert record["source_2"]["page"] == "Class"
      assert record["source_2"]["revid"] == 70_979
      assert record["source_2"]["in_cache"] == false

      # Цитата первого источника стоит в кэше посимвольно.
      cached = File.read!("priv/wiki_cache/fandom/Character level.wikitext")
      assert String.contains?(cached, record["quote"])
    end

    # 🔴 Положительный контроль к `refute` выше: гэп жив и приходит, как только
    # слой лимит не называет, — у ОБОИХ ruleset'ов. До задачи 4.1 он стоял
    # на имени ruleset'а: ванили — всегда, с данными или без.
    test "без записи в слое лимит пропадает у обоих — и они об этом говорят" do
      root = copy_rules()
      path = Path.join(root, "vanilla/rules.json")
      rules = path |> File.read!() |> Jason.decode!()

      File.write!(
        path,
        Jason.encode!(update_in(rules["character"], &Map.delete(&1, "max_classes")))
      )

      overrides_path = Path.join(root, "siala_41/overrides.json")
      overrides = overrides_path |> File.read!() |> Jason.decode!()

      File.write!(
        overrides_path,
        Jason.encode!(update_in(overrides["character"], &Map.delete(&1, "max_classes")))
      )

      for {_name, ruleset} <- Loader.load!(root) do
        assert ruleset.max_classes == nil
        assert {:missing_data, :max_classes} in ruleset.gaps
      end
    end

    test "четвёртый класс ваниль не пускает, и только из-за лимита", %{vanilla: vanilla} do
      three =
        Build.new(
          ruleset_version: "vanilla",
          race: :human,
          alignment: :true_neutral,
          levels: [:fighter, :rogue, :wizard]
        )

      assert Rules.validate_level_up(three, :cleric, vanilla) == {:error, [max_classes: 3]}
      assert Rules.validate_level_up(three, :wizard, vanilla) == :ok
    end
  end

  describe "1-й уровень ванили" do
    @alignments [nil | Enum.map(BuildCalculator.Ids.alignments(), &elem(&1, 0))]

    # Кого пускает на 1-й уровень каждое из десяти мировоззрений. Таблица —
    # из ограничений базовых классов, как их пишут страницы Fandom
    # (`vanilla/classes.json` → `alignment_restriction_raw`): Barbarian «any
    # non-lawful» (rev 71571), Bard «any non-lawful» (rev 71572), Druid «any
    # neutral» (rev 71575), Monk «any lawful» (rev 71589), Paladin «lawful good
    # only» (rev 71580); у Cleric, Fighter, Ranger, Rogue, Sorcerer и Wizard
    # ограничения нет. Мировоззрение не выбрано (`nil`) — ограниченный класс
    # не проходит (гейт `requires_alignment`).
    #
    # ⚠️ Сравнение с Сиалой — в отчёте задачи 4.1, не здесь: на 25.09.2026
    # наборы совпали на всех десяти (от 6 до 9 классов), но Сиала вправе
    # переписать ограничения своих классов, и ванильный тест за ней ходить
    # не должен.
    @free ~w(cleric fighter ranger rogue sorcerer wizard)a
    @expected %{
      nil => @free,
      lawful_good: @free ++ [:monk, :paladin],
      neutral_good: @free ++ [:barbarian, :bard, :druid],
      chaotic_good: @free ++ [:barbarian, :bard],
      lawful_neutral: @free ++ [:druid, :monk],
      true_neutral: @free ++ [:barbarian, :bard, :druid],
      chaotic_neutral: @free ++ [:barbarian, :bard, :druid],
      lawful_evil: @free ++ [:monk],
      neutral_evil: @free ++ [:barbarian, :bard, :druid],
      chaotic_evil: @free ++ [:barbarian, :bard]
    }

    defp first_level(alignment) do
      Build.new(
        ruleset_version: "vanilla",
        race: :human,
        alignment: alignment,
        base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14}
      )
    end

    test "ни одного отказа по лимиту классов — ни у одного класса, ни при одном мировоззрении",
         %{vanilla: vanilla} do
      for alignment <- @alignments, class <- Map.keys(vanilla.classes) do
        case Rules.validate_level_up(first_level(alignment), class, vanilla) do
          :ok ->
            :ok

          {:error, reasons} ->
            refute {:missing_data, :max_classes} in reasons,
                   "#{class} при #{inspect(alignment)}: #{inspect(reasons)}"
        end
      end
    end

    test "базовые классы проходят при совместимом мировоззрении, и только они", %{
      vanilla: vanilla
    } do
      assert map_size(@expected) == length(@alignments)

      for alignment <- @alignments do
        results =
          for class <- Map.keys(vanilla.classes),
              do: {class, Rules.validate_level_up(first_level(alignment), class, vanilla)}

        passed = for {class, :ok} <- results, do: class

        assert Enum.sort(passed) == Enum.sort(Map.fetch!(@expected, alignment)),
               "#{inspect(alignment)}: #{inspect(Enum.sort(passed))}"

        # Базовый класс, который не прошёл, отказан ТОЛЬКО мировоззрением —
        # ни лимитом, ни чем-то ещё.
        for {class, {:error, reasons}} <- results, not vanilla.classes[class].prestige? do
          assert Enum.all?(reasons, &match?({:requires_alignment, _}, &1)),
                 "#{class} при #{inspect(alignment)}: #{inspect(reasons)}"
        end

        # Положительный контроль: престиж-класс на 1-м уровне не берётся ни при
        # каком мировоззрении — иначе «прошли все базовые» могло бы значить
        # «проверки не было вовсе».
        refute Enum.any?(passed, &vanilla.classes[&1].prestige?)
      end
    end
  end
end
