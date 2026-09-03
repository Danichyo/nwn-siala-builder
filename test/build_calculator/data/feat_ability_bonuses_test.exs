defmodule BuildCalculator.Data.FeatAbilityBonusesTest do
  @moduledoc """
  Сторож ручной разметки `priv/rules/vanilla/feat_ability_bonuses.json`
  (задача 3.1).

  Файл существует потому, что связи «умение → характеристика» в корпусе нет ни
  в одном поле. Сплошная разведка по тем же 507 записям девяти файлов нашла её
  только прозой: в `description` фита (у РДД — таблицей сырого викитекста
  внутри описания) и колонкой таблицы прогрессии класса. Значит числа сюда
  переносил человек, и проверять надо ровно то, что человек может испортить:
  что цитата **дословна**, а не пересказана, и что вердикт с величиной
  не разъехались.

  ⚠️ Прочтение таблицы у соседних файлов РАЗНОЕ, и это главное, что здесь
  стережётся: `ac_at_class_level` в `ac_bonuses.json` — итог на ступени,
  `gains_at_class_level` здесь — приращение, ступени суммируются. Переписанная
  «как у соседа» таблица дала бы у РДД +4 силы вместо +8 и выглядела бы
  совершенно нормально.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader

  @markup "priv/rules/vanilla/feat_ability_bonuses.json" |> File.read!() |> Jason.decode!()
  @feats "priv/rules/vanilla/feats.json" |> File.read!() |> Jason.decode!()
  @classes "priv/rules/vanilla/classes.json" |> File.read!() |> Jason.decode!()
  # ⚠️ ДРУГОЙ classes.json — несёт `_receivers`, словарь получателей `affects`,
  # ОДИН на весь проект (задача 3.28).
  @shard_classes "priv/rules/siala_41/classes.json" |> File.read!() |> Jason.decode!()

  @verdicts ~w(applied counted_elsewhere not_modelled not_an_ability_bonus)
  @amount_kinds ~w(per_take ability_at_class_level)
  @sources ~w(feat class)
  @abilities ~w(str dex con int wis cha)

  # Какая цитата чьей страницей подтверждается. Пар несколько, потому что
  # у записи бывает больше одного источника: сам эффект, его таблица, и
  # сиальская правка того же умения.
  @quote_sources %{
    "quote" => "source",
    "quote_table" => "source",
    "quote_greater" => "source",
    "quote_prose" => "source",
    "quote_siala" => "source_2"
  }

  defp entries, do: @markup["bonuses"]
  defp name(entry), do: entry["feat"] || entry["class"]

  defp cached!(source) do
    index =
      case source["wiki"] do
        "fandom" -> "priv/wiki_cache/fandom/_index.json"
        "siala" -> "priv/wiki_cache/siala/_index.json"
      end

    file =
      index
      |> File.read!()
      |> Jason.decode!()
      |> Enum.find(&(&1["title"] == source["page"]))
      |> case do
        %{"file" => file} -> file
        nil -> flunk("страницы #{source["page"]} нет в кэше — цитату не с чем сверить")
      end

    index |> Path.dirname() |> Path.join(file) |> File.read!()
  end

  # Викитекст переносит строки там, где в цитате пробел (таблица РДД лежит
  # в описании фита многострочной). Сравнение по «схлопнутым» пробелам —
  # единственный способ сверить её дословно, не переписывая цитату в одну
  # строку с потерей читаемости.
  defp squeeze(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  describe "цитаты" do
    # Единственная проверка, ради которой этот файл тестируется вообще. Всё
    # остальное — про схему; эта — про честность.
    test "каждая цитата дословно лежит на своей странице в кэше" do
      for entry <- entries(),
          {quote_key, source_key} <- @quote_sources,
          quote = entry[quote_key] do
        source = entry[source_key] || entry["source"]

        assert String.contains?(squeeze(cached!(source)), squeeze(quote)),
               "#{name(entry)} / #{quote_key}: цитаты нет на странице #{source["page"]}"
      end
    end

    # Развилки решены не «по здравому смыслу», а по источнику, и цитаты в них
    # такие же настоящие, как у записей.
    test "цитаты трёх решений тоже лежат на своих страницах" do
      # ⚠️ У двух решений цитаты с РАЗНЫХ страниц, и какая с какой — часть
      # утверждения: ретроактивность хитов написана на странице класса, а
      # правило про скилл-поинты — на странице фита.
      decisions = [
        {"_order_decision", "quote", "source"},
        {"_order_decision", "quote_2", "source"},
        {"_cap_decision", "quote_ability_cap", "source"},
        {"_cap_decision", "quote_great", "source_2"},
        {"_retroactivity_decision", "quote_hp", "source"},
        {"_retroactivity_decision", "quote_skill_points", "source_2"}
      ]

      for {key, quote_key, source_key} <- decisions do
        decision = @markup[key]
        source = decision[source_key]

        assert String.contains?(squeeze(cached!(source)), squeeze(decision[quote_key])),
               "#{key} / #{quote_key}: цитаты нет на странице #{source["page"]}"
      end
    end

    test "у каждой записи есть источник страницы с revid" do
      for entry <- entries() do
        assert entry["source"]["wiki"] in ~w(fandom siala)
        assert is_binary(entry["source"]["page"])
        assert is_integer(entry["source"]["revid"]), "#{name(entry)}: нет revid"
      end
    end
  end

  describe "схема" do
    test "вердикт у каждой записи из известного набора" do
      for entry <- entries(), do: assert(entry["verdict"] in @verdicts)
    end

    test "у записи ровно один источник, и он существует" do
      known = %{
        "feat" => MapSet.new(@feats, & &1["id"]),
        "class" => MapSet.new(@classes, & &1["id"])
      }

      for entry <- entries() do
        keys = for key <- @sources, is_binary(entry[key]), do: key

        assert [key] = keys, "#{name(entry)}: источников #{length(keys)}, ожидался один"

        assert MapSet.member?(known[key], entry[key]),
               "#{name(entry)}: такого #{key} нет в справочнике"
      end
    end

    test "запись на каждую сущность одна" do
      pairs =
        for entry <- entries(), key <- @sources, is_binary(entry[key]), do: {key, entry[key]}

      assert pairs == Enum.uniq(pairs)
    end

    # Отвергнутая запись без причины через полгода читается как чей-то
    # недосмотр — и следующая разведка «починит» мнимый пропуск.
    test "у каждого отказа названа причина" do
      for entry <- entries(), entry["verdict"] in ~w(not_modelled not_an_ability_bonus) do
        assert is_binary(entry["why"]) and entry["why"] != "",
               "#{name(entry)}: вердикт #{entry["verdict"]} без причины"
      end

      for entry <- entries(), entry["verdict"] == "counted_elsewhere" do
        assert is_binary(entry["owned_by"]), "#{name(entry)}: не сказано, кто считает вместо неё"
        assert entry["owned_by"] in Enum.map(entries(), &name/1)
      end
    end

    test "величина стоит только там, где ей место, и только известной формы" do
      for entry <- entries() do
        case {entry["verdict"], entry["amount"]} do
          {"applied", amount} ->
            assert is_map(amount), "#{name(entry)}: applied без величины"
            assert amount["kind"] in @amount_kinds

          {"not_modelled", amount} ->
            if is_map(amount), do: assert(amount["kind"] in @amount_kinds)

          {_rejected, amount} ->
            refute is_map(amount),
                   "#{name(entry)}: у отвергнутой записи не должно быть величины"
        end
      end
    end

    # ⚠️ Здесь ступени СУММИРУЮТСЯ, в отличие от таблицы AC в соседнем файле.
    # Монотонность поэтому НЕ проверяется — она была бы проверкой чужого
    # прочтения; проверяется то, что каждая ступень называет существующую
    # характеристику и целое число.
    test "таблица по уровням класса называет существующий класс и характеристики" do
      class_ids = MapSet.new(@classes, & &1["id"])

      for entry <- entries(),
          amount = entry["amount"],
          is_map(amount),
          amount["kind"] == "ability_at_class_level" do
        assert MapSet.member?(class_ids, amount["class"])

        for {level, gains} <- amount["gains_at_class_level"] do
          assert {parsed, ""} = Integer.parse(level)
          assert parsed >= 1

          for {ability, bonus} <- gains do
            assert ability in @abilities, "#{name(entry)}: характеристика #{ability}"
            assert is_integer(bonus)
          end
        end
      end
    end

    test "у per_take названы характеристика, шаг и потолок эффекта" do
      for entry <- entries(),
          amount = entry["amount"],
          is_map(amount),
          amount["kind"] == "per_take" do
        assert amount["ability"] in @abilities
        assert is_integer(amount["bonus"])
        assert is_integer(amount["max_total"])
      end
    end

    # `effect_coverage` — суждение читателя страницы, и оно снимает с билда
    # общую оговорку про непосчитанную прибавку. Значит стоять оно может
    # только у applied и только известным значением.
    test "effect_coverage стоит только у applied и из известного набора" do
      for entry <- entries() do
        case entry["effect_coverage"] do
          nil -> assert entry["verdict"] != "applied" or is_nil(entry["effect_coverage"])
          value -> assert value in ~w(whole_feat abilities_only)
        end

        if entry["effect_coverage"], do: assert(entry["verdict"] == "applied")
      end
    end
  end

  # ⚠️ Задача «пять файлов прибавок» (17.08.2026). Как и у соседей, сегодня
  # НИКТО не читает поле для гэпов ЭТОГО файла: {:not_modelled,
  # :ability_bonus_feats_and_class} строится `if(ability_bonuses.applied ==
  # [], ...)` в Data.Loader.gaps/15 (общий гэп «нет файла вовсе», не по
  # записи), а не-ruleset-wide {:not_modelled, {:ability_bonus, id}} —
  # `Rules.AbilityBonuses`, чужая граница (CLAUDE.md §8). Поле лежит
  # материалом.
  describe "получатели факта (affects)" do
    defp known_receivers do
      MapSet.union(
        MapSet.new(Map.keys(@shard_classes["_receivers"]["our"])),
        MapSet.new(Map.keys(@shard_classes["_receivers"]["not_our"]))
      )
    end

    test "метка стоит ровно у not_modelled и нигде больше" do
      for entry <- entries() do
        case entry["verdict"] do
          "not_modelled" ->
            assert is_list(entry["affects"]) and entry["affects"] != [],
                   "#{name(entry)}: not_modelled без affects"

          _other ->
            refute Map.has_key?(entry, "affects"), "#{name(entry)}: affects у #{entry["verdict"]}"
        end
      end
    end

    test "каждый получатель — из закрытого словаря siala_41/classes.json" do
      known = known_receivers()

      for entry <- entries(), receiver <- entry["affects"] || [] do
        assert receiver in known, "#{name(entry)}: получатель #{receiver} вне словаря"
      end
    end

    # Все четыре — buff, и по одной и той же причине: временные, активируемые,
    # ограниченные числом применений в день. Ни одна не про постоянную
    # характеристику. См. affects_note у bulls_strength_feat в самом файле —
    # CLAUDE.md §9 называет его буфом поимённо, рядом с Rage.
    test "все четыре not_modelled — buff, и это одна и та же причина" do
      by_name =
        for entry <- entries(), entry["verdict"] == "not_modelled", into: %{} do
          {name(entry), entry["affects"]}
        end

      assert by_name == %{
               "barbarian_rage" => ["buff"],
               "mighty_rage" => ["buff"],
               "defensive_stance" => ["buff"],
               "bulls_strength_feat" => ["buff"]
             }
    end

    test "affects доезжает до ruleset без изменения формы" do
      ruleset = Data.ruleset!("siala_41")
      unmodelled = Map.new(ruleset.ability_bonuses.unmodelled, &{&1.id, &1})

      assert unmodelled[:barbarian_rage].affects == ["buff"]

      applied = Map.new(ruleset.ability_bonuses.applied, &{&1.id, &1})
      refute applied[:great_strength].affects
    end
  end

  describe "загрузчик падает на получателе вне словаря" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      root = Path.join(dir, "rules")
      File.cp_r!("priv/rules", root)

      %{root: root, path: Path.join([root, "vanilla", "feat_ability_bonuses.json"])}
    end

    test "получатель с опечаткой", %{root: root, path: path} do
      patch(path, "barbarian_rage", &Map.put(&1, "affects", ["buf"]))

      assert_raise RuntimeError, ~r/"buf".*neither/s, fn -> Loader.load!(root) end
    end

    test "affects строкой вместо списка", %{root: root, path: path} do
      patch(path, "barbarian_rage", &Map.put(&1, "affects", "buff"))

      assert_raise RuntimeError, ~r/Expected a non-empty list/, fn -> Loader.load!(root) end
    end
  end

  describe "разведка" do
    # Шапка `_sweep` — не украшение: по ней следующий человек решает, нужно ли
    # перепроверять корпус. Разошедшийся счёт значит, что решать он будет
    # по неправде.
    test "счётчики шапки сходятся с содержимым файла" do
      sweep = @markup["_sweep"]

      assert sweep["by_verdict"] == Enum.frequencies_by(entries(), & &1["verdict"])
      assert sweep["found"] == length(entries())

      # Тот же корпус, что у задачи 3.11: 299 + 66 + 25 фитов, 23 + 23 класса,
      # 28 + 29 навыков, 7 + 7 рас.
      assert sweep["records_checked"] == 507
      assert length(sweep["corpus"]) == 9
    end

    # ⚠️ Утверждение о полноте, которое можно проверить, а не принять на веру:
    # источник сам перечисляет, что поднимает базовые характеристики, и
    # называет ровно два семейства. Это перечисление лежит у нас в данных
    # с 01.08.2026 — сверяем разметку с ним, а не с памятью разведчика.
    test "applied-записи совпадают с тем, что перечисляет сам источник" do
      epic = "priv/rules/vanilla/epic.json" |> File.read!() |> Jason.decode!()
      rule = epic["ability_increases"]["rule_raw"]

      assert rule =~ "dragon abilities"
      assert rule =~ "great ability"

      applied = for entry <- entries(), entry["verdict"] == "applied", do: name(entry)

      assert Enum.sort(applied) == [
               "dragon_abilities",
               "great_charisma",
               "great_constitution",
               "great_dexterity",
               "great_intelligence",
               "great_strength",
               "great_wisdom"
             ]
    end

    # Ловушка имени, названная бэклогом заранее, и обратная к ней — обе
    # проверяются по данным, а не по тексту заметки.
    test "ловушки по имени стоят в файле как отказы" do
      by_name = Map.new(entries(), &{name(&1), &1})

      # `great_` в имени, а даёт урон / спасбросок.
      assert by_name["great_smiting"]["verdict"] == "not_an_ability_bonus"
      assert by_name["great_fortitude"]["verdict"] == "not_an_ability_bonus"
      # «dexterity» внутри имени, а к ловкости отношения нет.
      assert by_name["ambidexterity"]["verdict"] == "not_an_ability_bonus"

      # И обратный случай: имя не называет ни одной характеристики, а даёт пять.
      assert by_name["dragon_abilities"]["verdict"] == "applied"
    end
  end

  describe "загрузчик роняет сборку на битой разметке" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      root = Path.join(dir, "rules")
      File.cp_r!("priv/rules", root)

      %{root: root, path: Path.join([root, "vanilla", "feat_ability_bonuses.json"])}
    end

    defp rewrite!(path, fun) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> fun.()
      |> Jason.encode!()
      |> then(&File.write!(path, &1))
    end

    defp patch(path, name, fun) do
      rewrite!(path, fn markup ->
        update_in(markup["bonuses"], fn entries ->
          Enum.map(entries, fn entry ->
            if name(entry) == name, do: fun.(entry), else: entry
          end)
        end)
      end)
    end

    # ⚠️ Положительный контроль ко всем падениям ниже: нетронутая копия обязана
    # грузиться, и разметка в ней обязана доехать. Без него `assert_raise`
    # зеленел бы и на копии, которая не грузится вовсе.
    test "нетронутая копия грузится, и разметка в ней есть", %{root: root} do
      ruleset = Loader.load!(root)["siala_41"]
      applied = Map.new(ruleset.ability_bonuses.applied, &{&1.id, &1})

      assert applied[:great_strength].amount ==
               %{kind: :per_take, ability: :str, bonus: 1, max_total: 10}

      assert applied[:dragon_abilities].amount.class == :red_dragon_disciple
      assert applied[:dragon_abilities].amount.gains_at_class_level[10] == %{str: 4, cha: 2}
      assert applied[:great_strength].covers_feat?
      assert :barbarian_rage in Enum.map(ruleset.ability_bonuses.unmodelled, & &1.id)
    end

    # ⚠️ И положительный контроль механизма честности: без файла ядро молчать
    # не имеет права — гэп «прибавки не считаются» обязан вернуться. Иначе
    # его исчезновение из рабочего ruleset'а нечем отличить от того, что
    # форму просто перестали выдавать.
    test "без файла возвращается гэп о непосчитанных прибавках", %{root: root, path: path} do
      File.rm!(path)
      ruleset = Loader.load!(root)["siala_41"]

      assert ruleset.ability_bonuses == %{applied: [], unmodelled: [], counted_elsewhere: []}
      assert {:not_modelled, :ability_bonus_feats_and_class} in ruleset.gaps
      refute {:not_modelled, :ability_bonus_feats_and_class} in Data.ruleset!("siala_41").gaps
    end

    test "имя несуществующего фита", %{root: root, path: path} do
      rewrite!(path, fn markup ->
        update_in(markup["bonuses"], &[%{"feat" => "not_a_feat", "verdict" => "applied"} | &1])
      end)

      assert_raise RuntimeError, ~r/not_a_feat/, fn -> Loader.load!(root) end
    end

    test "два источника в одной записи", %{root: root, path: path} do
      patch(path, "great_strength", &Map.put(&1, "class", "monk"))

      assert_raise RuntimeError, ~r/2 sources/, fn -> Loader.load!(root) end
    end

    test "applied без величины", %{root: root, path: path} do
      patch(path, "great_strength", &Map.delete(&1, "amount"))

      assert_raise RuntimeError, ~r/states no amount/, fn -> Loader.load!(root) end
    end

    test "неизвестная форма величины", %{root: root, path: path} do
      patch(path, "great_strength", &put_in(&1, ["amount", "kind"], "per_moon_phase"))

      assert_raise RuntimeError, ~r/per_moon_phase/, fn -> Loader.load!(root) end
    end

    test "несуществующая характеристика", %{root: root, path: path} do
      patch(path, "great_strength", &put_in(&1, ["amount", "ability"], "luck"))

      assert_raise RuntimeError, ~r/ability luck/, fn -> Loader.load!(root) end
    end

    test "нецелый потолок эффекта", %{root: root, path: path} do
      patch(path, "great_strength", &put_in(&1, ["amount", "max_total"], "десять"))

      assert_raise RuntimeError, ~r/whole number/, fn -> Loader.load!(root) end
    end

    test "ступень таблицы, названная не уровнем", %{root: root, path: path} do
      patch(path, "dragon_abilities", fn entry ->
        update_in(entry["amount"]["gains_at_class_level"], &Map.put(&1, "второй", %{"str" => 2}))
      end)

      assert_raise RuntimeError, ~r/class level/, fn -> Loader.load!(root) end
    end

    test "несуществующий класс в таблице", %{root: root, path: path} do
      patch(path, "dragon_abilities", &put_in(&1, ["amount", "class"], "dragon_rider"))

      assert_raise RuntimeError, ~r/dragon_rider/, fn -> Loader.load!(root) end
    end
  end

  describe "оба ruleset'а несут разметку" do
    # Файл ванильный и накладывается на оба: своих прибавок к характеристикам
    # у шарда нет ни одной (`_sweep.shard_layer`). А вот потолок ЧИСЛА взятий
    # есть только у шарда, со слов Dan, — и это уже не здесь, а в
    # `siala_41/feats.json`.
    test "разметка одинакова, а потолок числа взятий — только у шарда" do
      for version <- ~w(vanilla siala_41) do
        ruleset = Data.ruleset!(version)

        assert length(ruleset.ability_bonuses.applied) == 7
        assert length(ruleset.ability_bonuses.unmodelled) == 4
      end

      max_takes = fn version ->
        get_in(Data.ruleset!(version).feats[:great_strength].repeatable, [:max_takes, :value])
      end

      assert max_takes.("vanilla") == nil
      assert max_takes.("siala_41") == 10
    end
  end
end
