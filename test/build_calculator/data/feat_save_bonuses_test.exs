defmodule BuildCalculator.Data.FeatSaveBonusesTest do
  @moduledoc """
  Сторож ручной разметки `priv/rules/vanilla/feat_save_bonuses.json`
  (задача 1.12a).

  Файл существует потому, что связь «умение → сейв» в корпусе не лежит ни в
  одном поле. Сплошная разведка по тем же 507 записям девяти файлов нашла её
  только прозой — в `description` фита или колонке таблицы прогрессии
  класса. Значит числа сюда переносил человек, и проверять здесь надо то, что
  человек может испортить: что цитата **дословна**, а не пересказана, что
  вердикт с величиной не разъехались, и что счётчики шапки не соврали о
  полноте разведки.

  ⚠️ Пятый файл этой формы (`feat_hp_bonuses.json` — 1.9, `ac_bonuses.json` и
  `feat_ability_bonuses.json` — 3.11/3.1) — и единственный без поля `type`:
  движок NWN складывает источники сейва в одно число, без отдельных типов
  «resistance»/«luck», которые реально стакались бы по-разному, как у AC.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader

  @markup "priv/rules/vanilla/feat_save_bonuses.json" |> File.read!() |> Jason.decode!()
  @feats "priv/rules/vanilla/feats.json" |> File.read!() |> Jason.decode!()
  @classes "priv/rules/vanilla/classes.json" |> File.read!() |> Jason.decode!()
  @skills "priv/rules/vanilla/skills.json" |> File.read!() |> Jason.decode!()
  # ⚠️ ДРУГОЙ classes.json — несёт `_receivers`, словарь получателей `affects`,
  # ОДИН на весь проект (задача 3.28).
  @shard_classes "priv/rules/siala_41/classes.json" |> File.read!() |> Jason.decode!()

  @verdicts ~w(applied counted_elsewhere not_modelled not_a_save_bonus)
  @amount_kinds ~w(flat ability_modifier save_at_class_level)
  @sources ~w(feat class skill race_feat)
  @saves ~w(fort ref will)

  # `owned_by` обычно называет id другой записи ЭТОГО файла (bone_skin/
  # pale_master style), но у Epic prowess / Superior weapon focus называет
  # ЗАДАЧУ — 1.12b, атака, чьих данных ещё не существует (`_task_boundary`).
  @task_names ~w(1.12b)

  defp entries, do: @markup["bonuses"]
  defp name(entry), do: entry["feat"] || entry["class"] || entry["skill"] || entry["race_feat"]

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

  # Викитекст переносит строки там, где в цитате пробел (таблица Champion of
  # Torm лежит колонкой). Сравнение по «схлопнутым» пробелам — единственный
  # способ сверить дословно, не переписывая цитату в одну строку.
  defp squeeze(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  @quote_keys ~w(quote quote_table quote_greater quote_siala quote_notes quote_prose)

  describe "цитаты" do
    # Единственная проверка, ради которой этот файл тестируется вообще. Всё
    # остальное — про схему; эта — про честность.
    test "каждая цитата дословно лежит на своей странице в кэше" do
      for entry <- entries(),
          quote_key <- @quote_keys,
          quote = entry[quote_key] do
        source_key = if quote_key == "quote_siala", do: "source_2", else: "source"
        source = entry[source_key] || entry["source"]

        assert String.contains?(squeeze(cached!(source)), squeeze(quote)),
               "#{name(entry)} / #{quote_key}: цитаты нет на странице #{source["page"]}"
      end
    end

    test "у каждой записи есть источник страницы с revid" do
      for entry <- entries() do
        assert entry["source"]["wiki"] in ~w(fandom siala)
        assert is_binary(entry["source"]["page"])
        assert is_integer(entry["source"]["revid"]), "#{name(entry)}: нет revid"
      end
    end

    # 🔴 Цитата исключения из требования (задача S3) лежит НЕ на странице самой
    # прибавки, а на странице фита-получателя — и потому сверяется своим
    # источником, а не общим `source` записи. Проверка та же и по той же
    # причине: единственное, что человек может здесь испортить незаметно, —
    # пересказать цитату своими словами.
    test "цитата исключения дословно лежит на странице своего источника" do
      excluded = for entry <- entries(), entry["prerequisite"], do: entry

      assert excluded != [], "исключение исчезло из файла — правка S3 отменена?"

      for entry <- excluded do
        prereq = entry["prerequisite"]

        assert String.contains?(squeeze(cached!(prereq["source"])), squeeze(prereq["quote"])),
               "#{name(entry)}: цитаты нет на странице #{prereq["source"]["page"]}"
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
        "class" => MapSet.new(@classes, & &1["id"]),
        "skill" => MapSet.new(@skills, & &1["id"]),
        # race_feat — id фита (владение читается по расе, а не по слоту), и
        # проверяется против того же справочника фитов.
        "race_feat" => MapSet.new(@feats, & &1["id"])
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
      for entry <- entries(), entry["verdict"] in ~w(not_modelled not_a_save_bonus) do
        assert is_binary(entry["why"]) and entry["why"] != "",
               "#{name(entry)}: вердикт #{entry["verdict"]} без причины"
      end

      for entry <- entries(), entry["verdict"] == "counted_elsewhere" do
        assert is_binary(entry["owned_by"]), "#{name(entry)}: не сказано, кто считает вместо неё"

        assert entry["owned_by"] in (Enum.map(entries(), &name/1) ++ @task_names),
               "#{name(entry)}: owned_by #{entry["owned_by"]} — не запись файла и не известная задача"
      end
    end

    # `saves` обязателен у applied и опционален у not_modelled (см. _schema),
    # и в обоих случаях — только известные три имени, без повторов.
    test "saves стоит только там, где ему место, называет известные сейвы без повторов" do
      for entry <- entries() do
        case {entry["verdict"], entry["saves"]} do
          {"applied", saves} ->
            assert is_list(saves) and saves != [], "#{name(entry)}: applied без saves"

          {"not_modelled", saves} ->
            if saves, do: assert(is_list(saves) and saves != [])

          {_rejected, saves} ->
            refute saves, "#{name(entry)}: у #{entry["verdict"]} не должно быть saves"
        end

        if is_list(entry["saves"]) do
          assert Enum.all?(entry["saves"], &(&1 in @saves)), "#{name(entry)}: неизвестный сейв"
          assert Enum.uniq(entry["saves"]) == entry["saves"], "#{name(entry)}: сейв повторён"
        end
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
            refute is_map(amount), "#{name(entry)}: у отвергнутой записи не должно быть величины"
        end
      end
    end

    test "у flat названо целое число" do
      for entry <- entries(),
          amount = entry["amount"],
          is_map(amount),
          amount["kind"] == "flat" do
        assert is_integer(amount["bonus"]), "#{name(entry)}: flat без целого bonus"
      end
    end

    test "у ability_modifier названа существующая характеристика, floor — только у Divine grace" do
      abilities = ~w(str dex con int wis cha)

      for entry <- entries(),
          amount = entry["amount"],
          is_map(amount),
          amount["kind"] == "ability_modifier" do
        assert amount["ability"] in abilities,
               "#{name(entry)}: характеристика #{amount["ability"]}"
      end

      floored = for e <- entries(), get_in(e, ["amount", "floor"]), do: name(e)
      assert floored == ["divine_grace"]
    end

    test "у save_at_class_level назван существующий класс и целые ступени" do
      class_ids = MapSet.new(@classes, & &1["id"])

      for entry <- entries(),
          amount = entry["amount"],
          is_map(amount),
          amount["kind"] == "save_at_class_level" do
        assert MapSet.member?(class_ids, amount["class"])

        for {level, bonus} <- amount["save_at_class_level"] do
          assert {parsed, ""} = Integer.parse(level)
          assert parsed >= 1
          assert is_integer(bonus)
        end
      end
    end

    # `effect_coverage` — суждение читателя страницы, снимает общую оговорку
    # про непосчитанную прибавку. Значит стоять может только у applied и
    # только известным значением — включая `partial` у трёх смешанных фитов.
    test "effect_coverage стоит только у applied и из известного набора" do
      for entry <- entries() do
        case entry["effect_coverage"] do
          nil -> assert entry["verdict"] != "applied"
          value -> assert value in ~w(whole_feat partial)
        end

        if entry["effect_coverage"], do: assert(entry["verdict"] == "applied")
      end

      partial = for e <- entries(), e["effect_coverage"] == "partial", do: name(e)
      assert Enum.sort(partial) == ~w(bullheaded snake_blood strong_soul)
    end

    # `prerequisite` — второй признак записи рядом со стороной капа (задача S3):
    # идёт ли прибавка в число, с которым сравнивается требование фита по сейву.
    # Ключ означает ОТКЛОНЕНИЕ от умолчания «идёт», поэтому его отсутствие —
    # норма, а его наличие обязано быть полностью обосновано.
    test "prerequisite стоит только у applied, только verified и только с цитатой" do
      for entry <- entries(), prereq = entry["prerequisite"] do
        assert entry["verdict"] == "applied",
               "#{name(entry)}: у непосчитанной прибавки в требовании нечему участвовать"

        assert is_boolean(prereq["counts"]), "#{name(entry)}: counts не булево"

        assert prereq["status"] == "verified",
               "#{name(entry)}: исключение по догадке — это ложная нелегальность"

        assert is_binary(prereq["quote"]) and prereq["quote"] != ""
        assert is_map(prereq["source"])
      end
    end

    # ⚠️ Поимённо, а не «сколько-то»: правка S3 держится ровно на одной записи,
    # и признак, уехавший на соседнюю, — это уже другое правило («прибавки
    # фитов в требование не идут»), которое источник НЕ утверждает. Список
    # обязан меняться замером, а не рефакторингом.
    test "исключена ровно одна запись — Luck of heroes" do
      excluded = for e <- entries(), e["prerequisite"]["counts"] == false, do: name(e)

      assert excluded == ["luck_of_heroes"]
    end
  end

  # ⚠️ Задача «пять файлов прибавок» (17.08.2026) разметила пять из шести файлов
  # этой формы; этот, шестой, дошёл 18.08.2026 — тем же полем и правилом
  # (см. `_schema.affects` в самом файле). Словарь получателей общий на весь
  # проект, siala_41/classes.json → `_receivers`; этот файл своего не заводит.
  #
  # ⚠️ В отличие от AC/атаки/характеристик (чужая граница CLAUDE.md §8), гэп
  # {:not_modelled, {:save_bonus, id}} строит `Rules.SaveBonuses`, а фильтр
  # по получателю — общий плумбинг `Rules.Bonuses.held_rejected/4`, заведённый
  # 18.08.2026 (коммит `f3eb2de`) ЗАРАНЕЕ, до этой разметки: маршрут для
  # шестого файла уже стоял, ждал только данных. Значит сегодня, в отличие от
  # AC/атаки/характеристик, поле здесь — не материал, а РАБОТАЮЩИЙ ФИЛЬТР:
  # у Ярости и Стойки Гномьего защитника оговорка про сейвы пропадает с экрана
  # siala_41 в тот же момент, когда эта разметка попадает в ruleset.
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

    # Снимок всех двадцати одной — по критерию (временное/активируемое против
    # пассивного и узкого по цели), а не по случайному порядку файла, чтобы
    # разбор по группам был виден сразу. Шесть `buff` и пятнадцать
    # `saving_throws`, ни одного третьего получателя.
    test "снимок классификации двадцати одной not_modelled записи" do
      by_name =
        for entry <- entries(), entry["verdict"] == "not_modelled", into: %{} do
          {name(entry), entry["affects"]}
        end

      assert by_name == %{
               "arcane_defense" => ["saving_throws"],
               "barbarian_rage" => ["buff"],
               "mighty_rage" => ["buff"],
               "defensive_stance" => ["buff"],
               "divine_wrath" => ["buff"],
               "hardiness_vs_poisons" => ["saving_throws"],
               "hardiness_vs_spells" => ["saving_throws"],
               "hardiness_vs_enchantments" => ["saving_throws"],
               "hardiness_vs_illusions" => ["saving_throws"],
               "fearless" => ["saving_throws"],
               "resist_disease" => ["saving_throws"],
               "resist_poison" => ["saving_throws"],
               "resist_natures_lure" => ["saving_throws"],
               "poison_save" => ["saving_throws"],
               "still_mind" => ["saving_throws"],
               "tymoras_smile" => ["buff"],
               "lliiras_heart" => ["saving_throws"],
               "deneirs_eye" => ["saving_throws"],
               "uncanny_dodge" => ["saving_throws"],
               "defensive_awareness" => ["saving_throws"],
               "perform" => ["buff"]
             }
    end

    # 🔴 Обязательная сверка задания: три из шести `buff` — вторая половина
    # умения, чья ПЕРВАЯ половина уже несла эту метку в соседнем файле про
    # другой стат. До этой правки одно и то же умение оговаривалось по-разному
    # в разных панелях «Итого» — теперь обе половины сошлись.
    test "у Ярости, Стойки Гномьего защитника и Divine wrath обе половины сошлись" do
      ac = "priv/rules/vanilla/ac_bonuses.json" |> File.read!() |> Jason.decode!()
      ability = "priv/rules/vanilla/feat_ability_bonuses.json" |> File.read!() |> Jason.decode!()
      attack = "priv/rules/vanilla/feat_attack_bonuses.json" |> File.read!() |> Jason.decode!()

      find = fn markup, id ->
        Enum.find(markup["bonuses"], &(&1["feat"] == id))
      end

      by_name = for entry <- entries(), into: %{}, do: {name(entry), entry}

      for {id, sibling_file} <- [
            {"barbarian_rage", ac},
            {"defensive_stance", ac},
            {"barbarian_rage", ability},
            {"defensive_stance", ability},
            {"divine_wrath", attack}
          ] do
        assert find.(sibling_file, id)["affects"] == ["buff"], "#{id}: соседняя запись не buff"
        assert by_name[id]["affects"] == ["buff"], "#{id}: своя запись не buff"
      end
    end

    test "affects доезжает до ruleset без изменения формы" do
      ruleset = Data.ruleset!("siala_41")
      unmodelled = Map.new(ruleset.save_bonuses.unmodelled, &{&1.id, &1})

      assert unmodelled[:barbarian_rage].affects == ["buff"]
      assert unmodelled[:hardiness_vs_poisons].affects == ["saving_throws"]

      applied = Map.new(ruleset.save_bonuses.applied, &{&1.id, &1})
      refute applied[:iron_will].affects
    end
  end

  describe "загрузчик падает на получателе вне словаря" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      root = Path.join(dir, "rules")
      File.cp_r!("priv/rules", root)

      %{root: root, path: Path.join([root, "vanilla", "feat_save_bonuses.json"])}
    end

    test "получатель с опечаткой", %{root: root, path: path} do
      patch(path, "barbarian_rage", &Map.put(&1, "affects", ["buf"]))

      assert_raise RuntimeError, ~r/"buf".*neither/s, fn -> Loader.load!(root) end
    end

    test "affects строкой вместо списка", %{root: root, path: path} do
      patch(path, "barbarian_rage", &Map.put(&1, "affects", "buff"))

      assert_raise RuntimeError, ~r/Expected a non-empty list/, fn -> Loader.load!(root) end
    end

    test "пустой affects", %{root: root, path: path} do
      patch(path, "barbarian_rage", &Map.put(&1, "affects", []))

      assert_raise RuntimeError, ~r/Expected a non-empty list/, fn -> Loader.load!(root) end
    end
  end

  describe "разведка" do
    # Шапка `_sweep` — не украшение: по ней следующий человек решает, нужно
    # ли перепроверять корпус. Разошедшийся счёт значит, что решать он будет
    # по неправде.
    test "счётчики шапки сходятся с содержимым файла" do
      sweep = @markup["_sweep"]

      assert sweep["by_verdict"] == Enum.frequencies_by(entries(), & &1["verdict"])
      assert sweep["found"] == length(entries())

      # Тот же корпус, что у задач 3.1/3.11: 299 + 66 + 25 фитов, 23 + 23
      # класса, 28 + 29 навыков, 7 + 7 рас.
      assert sweep["records_checked"] == 507
      assert length(sweep["corpus"]) == 9
    end

    # Ловушки, названные в постановке задачи заранее, стоят в файле как
    # отказы — а не потерялись при переписывании находок в данные.
    test "ловушки, названные координатором, стоят как отказы" do
      by_name = Map.new(entries(), &{name(&1), &1})

      # Сейв ЦЕЛИ, не своего — вся семья «удар или умри».
      for id <- ~w(arrow_of_death quivering_palm death_attack deathless_master_touch) do
        assert by_name[id]["verdict"] == "not_a_save_bonus", "#{id}"
      end

      # Формула разрешения броска, не бонус к числу.
      for id <- ~w(evasion improved_evasion defensive_roll deflect_arrows) do
        assert by_name[id]["verdict"] == "not_a_save_bonus", "#{id}"
      end

      # Monster uncanny reflex — ловушка по имени, названная координатором
      # заранее: монстровый фит, к Reflex saving throw отношения не имеет.
      assert by_name["monster_uncanny_reflex"]["verdict"] == "not_a_save_bonus"

      # А это — настоящие applied-находки.
      for id <- ~w(divine_grace dark_blessing sacred_defense iron_will) do
        assert by_name[id]["verdict"] == "applied", "#{id}"
      end
    end

    # Граница с 1.12b поимённая: обе записи — counted_elsewhere, обе не
    # содержат amount (это чужой стат), обе называют задачу, а не запись.
    test "маркеры границы 1.12b размечены, а не посчитаны" do
      by_name = Map.new(entries(), &{name(&1), &1})

      for id <- ~w(epic_prowess superior_weapon_focus) do
        entry = by_name[id]
        assert entry["verdict"] == "counted_elsewhere", id
        assert entry["owned_by"] == "1.12b", id
        refute is_map(entry["amount"]), id
      end
    end
  end

  describe "загрузчик роняет сборку на битой разметке" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      root = Path.join(dir, "rules")
      File.cp_r!("priv/rules", root)

      %{root: root, path: Path.join([root, "vanilla", "feat_save_bonuses.json"])}
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

    # ⚠️ Положительный контроль ко всем падениям ниже: нетронутая копия
    # обязана грузиться, и разметка в ней обязана доехать. Без него
    # `assert_raise` зеленел бы и на копии, которая не грузится вовсе.
    test "нетронутая копия грузится, и разметка в ней есть", %{root: root} do
      ruleset = Loader.load!(root)["siala_41"]
      applied = Map.new(ruleset.save_bonuses.applied, &{&1.id, &1})

      assert applied[:iron_will].amount == %{kind: :flat, bonus: 2}
      assert applied[:iron_will].saves == [:will]
      assert applied[:divine_grace].amount == %{kind: :ability_modifier, ability: :cha, floor: 0}

      assert applied[:dark_blessing].amount ==
               %{kind: :ability_modifier, ability: :cha, floor: nil}

      assert applied[:sacred_defense].amount.class == :champion_of_torm
      assert applied[:sacred_defense].amount.save_at_class_level[30] == 15
      assert applied[:iron_will].covers_feat?
      refute applied[:snake_blood].covers_feat?

      unmodelled_ids = Enum.map(ruleset.save_bonuses.unmodelled, & &1.id)
      assert :barbarian_rage in unmodelled_ids
      assert :hardiness_vs_poisons in unmodelled_ids
    end

    # ⚠️ И положительный контроль механизма честности: без файла ядро молчать
    # не имеет права — applied/unmodelled обязаны вернуться пустыми, а не
    # приподняться из кэша прошлой сборки.
    test "без файла возвращается пустая разметка", %{root: root, path: path} do
      File.rm!(path)
      ruleset = Loader.load!(root)["siala_41"]

      assert ruleset.save_bonuses == %{applied: [], unmodelled: [], counted_elsewhere: []}
    end

    test "имя несуществующего фита", %{root: root, path: path} do
      rewrite!(path, fn markup ->
        update_in(markup["bonuses"], &[%{"feat" => "not_a_feat", "verdict" => "applied"} | &1])
      end)

      assert_raise RuntimeError, ~r/not_a_feat/, fn -> Loader.load!(root) end
    end

    test "два источника в одной записи", %{root: root, path: path} do
      patch(path, "iron_will", &Map.put(&1, "class", "monk"))

      assert_raise RuntimeError, ~r/2 sources/, fn -> Loader.load!(root) end
    end

    test "applied без saves", %{root: root, path: path} do
      patch(path, "iron_will", &Map.delete(&1, "saves"))

      assert_raise RuntimeError, ~r/names no saves/, fn -> Loader.load!(root) end
    end

    test "applied без величины", %{root: root, path: path} do
      patch(path, "iron_will", &Map.delete(&1, "amount"))

      assert_raise RuntimeError, ~r/states no amount/, fn -> Loader.load!(root) end
    end

    test "неизвестная форма величины", %{root: root, path: path} do
      patch(path, "iron_will", &put_in(&1, ["amount", "kind"], "per_moon_phase"))

      assert_raise RuntimeError, ~r/per_moon_phase/, fn -> Loader.load!(root) end
    end

    test "неизвестное имя сейва", %{root: root, path: path} do
      patch(path, "iron_will", &put_in(&1, ["saves"], ["luck"]))

      assert_raise RuntimeError, ~r/save luck/, fn -> Loader.load!(root) end
    end

    test "несуществующая характеристика", %{root: root, path: path} do
      patch(path, "divine_grace", &put_in(&1, ["amount", "ability"], "luck"))

      assert_raise RuntimeError, ~r/ability luck/, fn -> Loader.load!(root) end
    end

    test "нецелый floor", %{root: root, path: path} do
      patch(path, "divine_grace", &put_in(&1, ["amount", "floor"], "ноль"))

      assert_raise RuntimeError, ~r/whole number or nothing/, fn -> Loader.load!(root) end
    end

    test "ступень таблицы, названная не уровнем", %{root: root, path: path} do
      patch(path, "sacred_defense", fn entry ->
        update_in(entry["amount"]["save_at_class_level"], &Map.put(&1, "второй", 1))
      end)

      assert_raise RuntimeError, ~r/class level/, fn -> Loader.load!(root) end
    end

    test "несуществующий класс в таблице", %{root: root, path: path} do
      patch(path, "sacred_defense", &put_in(&1, ["amount", "class"], "torm_knight"))

      assert_raise RuntimeError, ~r/torm_knight/, fn -> Loader.load!(root) end
    end

    # ⚠️ Положительный контроль к трём падениям ниже: признак нетронутой копии
    # обязан доехать до ядра. Без него они зеленели бы и на загрузчике, который
    # ключ вовсе не читает, — то есть на ровно той ошибке, которую правка S3
    # и убирает.
    test "признак исключения доезжает до ядра", %{root: root} do
      applied = Map.new(Loader.load!(root)["siala_41"].save_bonuses.applied, &{&1.id, &1})

      assert applied[:luck_of_heroes].prereq == %{counts?: false}
      refute applied[:iron_will].prereq
    end

    test "исключение объявлено у непосчитанной записи", %{root: root, path: path} do
      patch(path, "resist_poison", fn entry ->
        Map.put(entry, "prerequisite", %{
          "counts" => false,
          "status" => "verified",
          "quote" => "…",
          "source" => %{"kind" => "user"}
        })
      end)

      assert_raise RuntimeError, ~r/is in nobody's requirement either/, fn ->
        Loader.load!(root)
      end
    end

    test "исключение объявлено не булевым", %{root: root, path: path} do
      patch(path, "luck_of_heroes", &put_in(&1, ["prerequisite", "counts"], "нет"))

      assert_raise RuntimeError, ~r/no boolean prerequisite.counts/, fn -> Loader.load!(root) end
    end

    # 🔴 Строже, чем у стороны капа, где `assumed` — законный статус. Исключение
    # двигает ответ в сторону ОТКАЗА, и догадка в эту сторону даёт ложную
    # нелегальность: игрок изнутри инструмента её не обойдёт и не распознает.
    test "исключение по догадке правилом не становится", %{root: root, path: path} do
      patch(path, "luck_of_heroes", &put_in(&1, ["prerequisite", "status"], "assumed"))

      assert_raise RuntimeError, ~r/only "verified" takes a bonus out/, fn ->
        Loader.load!(root)
      end
    end

    test "исключение без цитаты", %{root: root, path: path} do
      patch(
        path,
        "luck_of_heroes",
        &update_in(&1["prerequisite"], fn p -> Map.delete(p, "quote") end)
      )

      assert_raise RuntimeError, ~r/without a verbatim quote and a source/, fn ->
        Loader.load!(root)
      end
    end
  end

  describe "оба ruleset'а несут разметку" do
    # Файл ванильный и накладывается на оба: своих прибавок к сейвам у шарда
    # нет ни одной (`_sweep.shard_layer`).
    test "разметка одинаковая на обоих ruleset'ах" do
      for version <- ~w(vanilla siala_41) do
        ruleset = Data.ruleset!(version)

        assert length(ruleset.save_bonuses.applied) == 14
        assert length(ruleset.save_bonuses.unmodelled) == 21
      end
    end
  end
end
