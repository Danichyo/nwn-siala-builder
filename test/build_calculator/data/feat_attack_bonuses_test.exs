defmodule BuildCalculator.Data.FeatAttackBonusesTest do
  @moduledoc """
  Сторож ручной разметки `priv/rules/vanilla/feat_attack_bonuses.json`
  (задача 1.12b).

  Файл существует потому, что связь «умение → бросок атаки» в корпусе не лежит
  ни в одном поле. Сплошная разведка по 517 записям девяти файлов нашла её
  только прозой — в `description` фита, в колонке таблицы прогрессии класса, а
  у `Small stature` вообще не на странице фита, а на странице расы. Значит
  числа сюда переносил человек, и проверять здесь надо то, что человек может
  испортить: что цитата **дословна**, а не пересказана, что вердикт с величиной
  не разъехались, и что счётчики шапки не соврали о полноте разведки.

  ⚠️ Шестой и последний файл этого семейства, и у него три отличия от пятого
  (`feat_save_bonuses.json`), каждое проверяется здесь:

    * **нет поля `saves`** — у атаки один получатель;
    * **есть поле `condition`**, обязательное у `not_modelled`: прибавки
      к атаке почти все условные (79 из 81 кандидата), и ядро читает из этого
      поля одно различие — «оружие» против всего остального;
    * **числа бывают ОТРИЦАТЕЛЬНЫМИ** — боевые режимы и специальные атаки
      (`Expertise` −5, `Disarm` −6). Ни в одном соседнем файле такого не было.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader

  @markup "priv/rules/vanilla/feat_attack_bonuses.json" |> File.read!() |> Jason.decode!()
  @feats "priv/rules/vanilla/feats.json" |> File.read!() |> Jason.decode!()
  @classes "priv/rules/vanilla/classes.json" |> File.read!() |> Jason.decode!()
  @skills "priv/rules/vanilla/skills.json" |> File.read!() |> Jason.decode!()
  @races "priv/rules/vanilla/races.json" |> File.read!() |> Jason.decode!()
  @weapons "priv/rules/vanilla/weapons.json" |> File.read!() |> Jason.decode!()
  # ⚠️ ДРУГОЙ classes.json, чем @classes выше: этот несёт `_receivers` —
  # закрытый словарь получателей, ОДИН на весь проект (задача 3.28).
  @shard_classes "priv/rules/siala_41/classes.json" |> File.read!() |> Jason.decode!()

  @verdicts ~w(applied counted_elsewhere not_modelled not_an_attack_bonus)
  @amount_kinds ~w(flat ability_modifier attack_at_class_level)
  @sources ~w(feat class skill race_feat race)
  @conditions ~w(weapon activated combat_mode enemy_type relative_size area range mounted
                 attack_of_opportunity special_attack dual_wield unknown_amount)

  # `owned_by` называет либо запись этого файла, либо МЕХАНИЗМ ядра. Второе —
  # то же расширение, что 1.12a сделала для имени задачи, и здесь оно нужно
  # четырём: смена характеристики атаки, расовый бонус Сиалы, атаки в раунд
  # и — с 28.08.2026 (задача 3.132) — штрафы боя двумя оружиями.
  @mechanisms ~w(attack_ability Rules.RacialBonus Rules.Progression Rules.DualWield)

  defp entries, do: @markup["bonuses"]

  defp name(entry),
    do: entry["feat"] || entry["class"] || entry["skill"] || entry["race_feat"] || entry["race"]

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

  # Викитекст переносит строки там, где в цитате пробел (колонки таблиц лежат
  # столбиком). Сравнение по «схлопнутым» пробелам — единственный способ
  # сверить дословно, не переписывая цитату в одну строку.
  defp squeeze(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  # У какой цитаты какой источник. ⚠️ Пар больше, чем у 1.12a, и это не
  # украшение: у `Small stature` ТРИ страницы (две расы и фит), и число стоит
  # на расовых, а условие — на фитовой. Разложить их по разным ключам —
  # единственный способ проверить, что ни одна не приписана чужой странице.
  @quote_sources %{
    "quote" => "source",
    "quote_epic_table" => "source",
    "quote_row_5" => "source",
    "quote_flurry" => "source",
    "quote_prone" => "source",
    "quote_monk" => "source",
    "quote_mounted" => "source",
    "quote_column" => "source_2",
    "quote_siala" => "source_2",
    "quote_feat_page" => "source_3",
    "quote_desc" => "source",
    # Прямое утверждение «без этого фита остальные умения ВМ не применяются
    # ни к какому оружию» — основание гейта колонки (14.08.2026, указал Dan).
    # Лежит на той же странице, что и `quote`, в разделе Notes.
    "quote_without_it" => "source",
    "quote_prereq" => "source",
    "quote_cap" => "source",
    "quote_class_column" => "source_2",
    # 🔴 Задача 3.101: у ДВУХ записей оружие названо классом, и состав класса
    # называет НЕ страница фита, а страница самого оружия. Отсюда по три-четыре
    # цитаты на запись и по три источника: у `Good aim` это `Throwing weapon`
    # (весь класс) и `Sling` (единственный спорный член), у `Enchant arrow` —
    # `Bow` (состав «луков»). Ключи разложены по источникам ровно затем, зачем
    # это сделано у `Small stature`: чтобы цитату нельзя было приписать чужой
    # странице.
    "quote_only_bows" => "source",
    "quote_bows" => "source_3",
    "quote_builder_note" => "source",
    "quote_weapon_class" => "source_2",
    "quote_weapon_class_purpose" => "source_2",
    "quote_sling" => "source_3"
  }

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

    # Ловушка, на которой 1.12a потеряла бы шесть цитат: ключ, которого нет
    # в @quote_sources, тест молча пропустил бы, и цитата уехала бы непроверенной.
    test "ни один ключ-цитата не остался вне проверки" do
      declared = MapSet.new(Map.keys(@quote_sources))

      unchecked =
        for entry <- entries(),
            key <- Map.keys(entry),
            String.starts_with?(key, "quote"),
            not MapSet.member?(declared, key),
            uniq: true,
            do: key

      assert unchecked == [], "цитаты под непроверяемыми ключами: #{inspect(unchecked)}"
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
        "class" => MapSet.new(@classes, & &1["id"]),
        "skill" => MapSet.new(@skills, & &1["id"]),
        # race_feat — id фита (владение читается по расе, а не по слоту).
        "race_feat" => MapSet.new(@feats, & &1["id"]),
        # race — сам id расы, пятый вид источника; нужен одной записи, где
        # прибавка принадлежит расе, а не её склонности.
        "race" => MapSet.new(@races, & &1["id"])
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
      for entry <- entries(), entry["verdict"] in ~w(not_modelled not_an_attack_bonus) do
        assert is_binary(entry["why"]) and entry["why"] != "",
               "#{name(entry)}: вердикт #{entry["verdict"]} без причины"
      end

      for entry <- entries(), entry["verdict"] == "counted_elsewhere" do
        assert is_binary(entry["owned_by"]),
               "#{name(entry)}: не сказано, кто учитывает вместо неё"

        assert entry["owned_by"] in (Enum.map(entries(), &name/1) ++ @mechanisms),
               "#{name(entry)}: owned_by #{entry["owned_by"]} — не запись файла и не механизм"
      end
    end

    # ⚠️ Поля `saves` здесь нет и быть не должно: у атаки один получатель.
    # Проверяется явно, потому что файл скопирован по форме с сейвового, и
    # забытое поле выглядело бы совершенно нормально.
    test "поля saves нет ни у одной записи" do
      for entry <- entries(), do: refute(Map.has_key?(entry, "saves"), name(entry))
    end

    # `condition` обязателен у not_modelled и запрещён у остальных: ядро читает
    # из него, какую из двух форм гэпа выдать, и запись без него выдала бы
    # общую там, где нужна оружейная.
    test "condition стоит ровно у not_modelled и из известного набора" do
      for entry <- entries() do
        case entry["verdict"] do
          "not_modelled" ->
            assert entry["condition"] in @conditions,
                   "#{name(entry)}: условие #{inspect(entry["condition"])}"

          _other ->
            refute entry["condition"], "#{name(entry)}: условие у вердикта #{entry["verdict"]}"
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

    # 🔴 Ядро считает `flat` и `attack_at_class_level`; третья форма,
    # `ability_modifier`, лежит материалом — и сторож стоит вместо реализации:
    # применят, не реализовав, — сборка упадёт (тест на это ниже).
    #
    # ⚠️ Здесь стояло «у applied только форма flat» и список из двух записей.
    # Задача 3.5 (часть B) перевела в applied три записи «выбранным оружием»,
    # и колонка Мастера оружия принесла с собой таблицу по уровням класса.
    test "у applied формы flat и attack_at_class_level, но не ability_modifier" do
      applied = for e <- entries(), e["verdict"] == "applied", do: {name(e), e["amount"]["kind"]}

      # ⚠️ Семь с 25.08.2026 (задача 3.101): `enchant_arrow` и `good_aim` тоже
      # переведены в applied. Форм по-прежнему две, и вторая (таблица по
      # уровням класса) больше не принадлежит одному Мастеру оружия.
      #
      # ⚠️ Стало ШЕСТЬ 30.08.2026 (задача 3.143): `small_stature` перешёл
      # в `not_modelled` — цитата в разметке была обрезана перед условием
      # «когда противник крупнее персонажа» (`condition: relative_size`).
      assert Enum.sort(applied) == [
               {"enchant_arrow", "attack_at_class_level"},
               {"epic_prowess", "flat"},
               {"epic_weapon_focus", "flat"},
               {"good_aim", "flat"},
               {"weapon_focus", "flat"},
               {"weapon_master", "attack_at_class_level"}
             ]

      refute Enum.any?(applied, &(elem(&1, 1) == "ability_modifier"))
    end

    # 🔴 Оружие названо ТОЛЬКО у applied-записей и ровно ОДНИМ из трёх способов.
    # Три, а не один, потому что источники называют оружие тремя разными
    # способами и вывести их друг из друга нельзя (задача 3.101):
    #
    #   * `choice_of` — оружие называет ВЫБОР фита (семейство фокуса, 3.5 B);
    #   * `weapon_must_be` — СВОЙСТВО, которое справочник утверждает полем
    #     (`Good aim` — «with throwing weapons», и `thrown` это категория вики);
    #   * `weapon_one_of` — ПЕРЕЧИСЛЕНИЕ, потому что перечисляет источник
    #     (`Enchant arrow` — «only for bows», а состав «луков» даёт `fandom:Bow`).
    test "applies_to_weapon стоит только у applied и называет оружие ровно одним способом" do
      feats = MapSet.new(@feats, & &1["id"])
      weapons = MapSet.new(@weapons["weapons"], & &1["id"])
      keys = ~w(choice_of weapon_must_be weapon_one_of)

      by_key =
        for entry <- entries(), spec = entry["applies_to_weapon"], reduce: %{} do
          acc ->
            assert entry["verdict"] == "applied",
                   "#{name(entry)}: applies_to_weapon у вердикта #{entry["verdict"]}"

            assert [key] = Enum.filter(keys, &Map.has_key?(spec, &1)),
                   "#{name(entry)}: applies_to_weapon называет оружие не ровно одним способом"

            case key do
              "choice_of" ->
                assert is_list(spec["choice_of"]) and spec["choice_of"] != [],
                       "#{name(entry)}: choice_of пуст"

                for feat <- spec["choice_of"] do
                  assert MapSet.member?(feats, feat),
                         "#{name(entry)}: фита #{feat} нет в справочнике"
                end

              "weapon_must_be" ->
                assert is_binary(spec["weapon_must_be"])

              "weapon_one_of" ->
                assert is_list(spec["weapon_one_of"]) and spec["weapon_one_of"] != [],
                       "#{name(entry)}: weapon_one_of пуст"

                for weapon <- spec["weapon_one_of"] do
                  assert MapSet.member?(weapons, weapon),
                         "#{name(entry)}: оружия #{weapon} нет в справочнике"
                end
            end

            Map.update(acc, key, [name(entry)], &[name(entry) | &1])
        end

      assert Map.new(by_key, fn {key, names} -> {key, Enum.sort(names)} end) == %{
               "choice_of" => ~w(epic_weapon_focus weapon_focus weapon_master),
               "weapon_must_be" => ~w(good_aim),
               "weapon_one_of" => ~w(enchant_arrow)
             }
    end

    test "у flat названо целое число, и знак — часть факта" do
      flats =
        for entry <- entries(),
            amount = entry["amount"],
            is_map(amount),
            amount["kind"] == "flat" do
          assert is_integer(amount["bonus"]), "#{name(entry)}: flat без целого bonus"
          {name(entry), amount["bonus"]}
        end

      # ⚠️ Отрицательные числа есть, и это первый файл семейства, где они
      # есть. Проверяется поимённо: потерянный минус у боевого режима выглядел
      # бы как обычная прибавка.
      negative = for {id, bonus} <- flats, bonus < 0, do: {id, bonus}

      assert Enum.sort(negative) == [
               {"called_shot", -4},
               {"disarm", -6},
               {"expertise", -5},
               {"flurry_of_blows", -2},
               {"improved_disarm", -4},
               {"improved_expertise", -10},
               {"improved_power_attack", -10},
               {"knockdown", -4},
               {"power_attack", -5},
               {"rapid_shot", -2},
               {"sap", -4},
               {"stunning_fist", -4}
             ]
    end

    test "у ability_modifier названа существующая характеристика" do
      abilities = ~w(str dex con int wis cha)

      for entry <- entries(),
          amount = entry["amount"],
          is_map(amount),
          amount["kind"] == "ability_modifier" do
        assert amount["ability"] in abilities,
               "#{name(entry)}: характеристика #{amount["ability"]}"
      end
    end

    test "у attack_at_class_level назван существующий класс и целые ступени" do
      class_ids = MapSet.new(@classes, & &1["id"])

      tables =
        for entry <- entries(),
            amount = entry["amount"],
            is_map(amount),
            amount["kind"] == "attack_at_class_level" do
          assert MapSet.member?(class_ids, amount["class"])

          for {level, bonus} <- amount["attack_at_class_level"] do
            assert {parsed, ""} = Integer.parse(level)
            assert parsed >= 1
            assert is_integer(bonus)
          end

          name(entry)
        end

      # ⚠️ До задачи про `progression[].extra` (09.08.2026) была единственной
      # записью этой формы и одновременно самым крупным непосчитанным числом
      # файла (+7 на 28 уровнях класса). Теперь их две: `enchant_arrow`
      # (Тайный лучник, растущий бонус атаки зачарованной стрелой, тот же
      # довод «только выбранным оружием» — _weapon_decision) обгоняет её
      # собственным потолком +15 на 29-м уровне класса, и это теперь самое
      # крупное непосчитанное число файла среди всех форм, не только этой.
      assert tables == ["weapon_master", "enchant_arrow"]
    end

    # ⚠️ Требуется у applied-записей, чей источник — ФИТ (или расовая склонность
    # в форме фита): вопрос «есть ли у него другой, непосчитанный эффект» задаётся
    # про фит, и ответ читает `FeatChoices.gaps/3`, чтобы не печатать «прибавку от
    # фита не считаем» рядом с посчитанным термом. У КОЛОНКИ КЛАССА фита нет вовсе
    # (`weapon_master`, задача 3.5 часть B), и приписывать ей «покрывает ли она
    # класс целиком» значило бы отвечать на вопрос, которого никто не задавал.
    #
    # ⚠️ С 14.08.2026 поле допустимо и у `counted_elsewhere` — и ровно у записи
    # о ФИТЕ, по той же причине. `Weapon of choice` собственного числа не даёт,
    # но весь его эффект доезжает до билда колонкой Мастера оружия, и без этого
    # поля оговорка «прибавку от фита не считаем» осталась бы висеть рядом
    # с посчитанным термом. Два утверждения при этом остаются раздельными:
    # ВЕРДИКТ говорит «эффект доезжает», ПОЛЕ — «доезжает целиком».
    test "effect_coverage стоит у записей о фите, чей эффект посчитан, и из известного набора" do
      for entry <- entries() do
        feat_record? = is_binary(entry["feat"]) or is_binary(entry["race_feat"])

        case entry["effect_coverage"] do
          nil -> refute entry["verdict"] == "applied" and feat_record?
          value -> assert value in ~w(whole_feat partial)
        end

        if entry["effect_coverage"] do
          assert entry["verdict"] in ~w(applied counted_elsewhere), name(entry)
          assert feat_record?, "#{name(entry)}: покрытие у записи, у которой фита нет"
        end
      end

      # ⚠️ У `Enchant arrow` непосчитанный остаток — ВТОРАЯ половина того же
      # усиления, урон стрелы и пробивание сопротивления урону. Оба получателя
      # не наши, оговорки билд не получает, но покрытие — про эффект фита,
      # а не про видимость.
      #
      # ⚠️ Был ещё `small_stature` до задачи 3.143 (30.08.2026): запись стала
      # `not_modelled`, а `effect_coverage` допустим только у applied/
      # counted_elsewhere (проверено выше в этом же тесте) — поле убрано
      # вместе с вердиктом.
      partial = for e <- entries(), e["effect_coverage"] == "partial", do: name(e)
      assert partial == ["enchant_arrow"]

      # Положительный контроль: у фитов-прибавок покрытие объявлено целиком,
      # а не пропущено вместе с колонкой класса.
      whole = for e <- entries(), e["effect_coverage"] == "whole_feat", do: name(e)

      assert Enum.sort(whole) ==
               ~w(epic_prowess epic_weapon_focus good_aim weapon_focus weapon_of_choice)

      # ⚠️ И отрицательный контроль к нему же: единственная запись, объявившая
      # покрытие БЕЗ вердикта `applied`, — та самая. Появится вторая — это
      # решение, а не мелочь: она снимет с билда оговорку про свой фит.
      not_applied =
        for e <- entries(), e["effect_coverage"], e["verdict"] != "applied", do: name(e)

      assert not_applied == ["weapon_of_choice"]
    end
  end

  # ⚠️ Задача «пять файлов прибавок» (17.08.2026) — получатель факта (`affects`)
  # у not_modelled-записей этого файла. Словарь общий на весь проект,
  # siala_41/classes.json → `_receivers`; этот файл своего не заводит.
  #
  # ⚠️ Сегодня НИКТО не читает это поле для этого файла на уровне ruleset.gaps
  # (в отличие от feat_skill_bonuses.json → {:not_modelled, :feat_skill_bonus},
  # у которого есть ruleset-wide цикл в Data.Loader.gaps/15): у AB нет такого
  # цикла вовсе, а гэп {:not_modelled, {:attack_bonus, id}} / {…,
  # :attack_bonus_weapon, …} строит `Rules.AttackBonuses` — а это `rules/`,
  # чужая граница (CLAUDE.md §8). Поле лежит материалом ровно на тот день,
  # когда `Rules.Bonuses`/`Rules.AttackBonuses` научатся его слушать; сегодня
  # оно не меняет ни одного гэпа НИ У ОДНОГО билда.
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

    # Снимок всех двадцати девяти — по условию (`_conditions`), а не по
    # случайному порядку файла, чтобы разбор по группам был виден сразу.
    # ⚠️ Было 28 до задачи 3.143 (30.08.2026): `small_stature` добавлена
    # (была applied, цитата обрезана перед условием «когда противник крупнее
    # персонажа»), своё условие — `relative_size`.
    test "снимок классификации двадцати девяти not_modelled записей, по условию" do
      by_condition =
        for entry <- entries(), entry["verdict"] == "not_modelled", reduce: %{} do
          acc -> Map.update(acc, entry["condition"], [name(entry)], &[name(entry) | &1])
        end
        |> Map.new(fn {cond, names} -> {cond, Enum.sort(names)} end)

      # `enemy_type`/`relative_size`/`area`/`range`/`attack_of_opportunity` —
      # постоянные черты персонажа или снаряжения, условные лишь по ситуации,
      # которую билд не описывает: affects остаётся attack_bonus (наше).
      # ⚠️ `weapon` из этого перечисления УШЁЛ 25.08.2026 (задача 3.101):
      # носителей у условия не осталось ни одного, обе записи стали applied.
      # ⚠️ `dual_wield` ушёл оттуда же 28.08.2026 (задача 3.132) и по той же
      # причине, только сильнее: у билда появилась вторая рука, штрафы стиля
      # стали СЧИТАТЬСЯ, и все три записи стали counted_elsewhere. Значение
      # в `_conditions` живо и обязано быть живо — носителей у него ноль.
      # ⚠️ `relative_size` пришло 30.08.2026 (задача 3.143), тем же путём,
      # что `enemy_type`: размер противника — постоянное свойство персонажа
      # относительно того, кто перед ним, а не включаемое состояние.
      for cond <- ~w(enemy_type relative_size area range attack_of_opportunity) do
        for name <- by_condition[cond] do
          entry = Enum.find(entries(), &(name(&1) == name))
          assert entry["affects"] == ["attack_bonus"], "#{name}: condition #{cond}"
        end
      end

      # `mounted` — свой получатель, дословно совпадающий по смыслу.
      for name <- by_condition["mounted"] do
        entry = Enum.find(entries(), &(name(&1) == name))
        assert entry["affects"] == ["mounted_combat"], name
      end

      # `activated`/`combat_mode`/`special_attack` — временное, включаемое,
      # состояние боя: тот же критерий, каким в siala_41/classes.json под
      # баффы ушли Rage/Bull's strength/Shadow Evade.
      for cond <- ~w(activated combat_mode special_attack) do
        for name <- by_condition[cond] do
          entry = Enum.find(entries(), &(name(&1) == name))
          assert entry["affects"] == ["buff"], "#{name}: condition #{cond}"
        end
      end

      # Положительный контроль на сам снимок: групп ровно восемь из
      # одиннадцати возможных, и сумма размеров групп равна двадцати шести.
      # ⚠️ Не встречаются `unknown_amount` (см. `_conditions` в файле), `weapon`
      # (с 25.08.2026) и `dual_wield` (с 28.08.2026): все три значения живы
      # в словаре и обязаны быть живы, носителей у них сегодня ноль.
      # ⚠️ Было «семь… двадцати пяти» до задачи 3.143 (30.08.2026):
      # `relative_size` — восьмая группа, с единственным носителем.
      assert Map.keys(by_condition) |> Enum.sort() ==
               ~w(activated area attack_of_opportunity combat_mode
                  enemy_type mounted range relative_size special_attack)

      assert by_condition |> Map.values() |> List.flatten() |> length() == 26
    end

    test "affects доезжает до ruleset без изменения формы" do
      ruleset = Data.ruleset!("siala_41")
      unmodelled = Map.new(ruleset.attack_bonuses.unmodelled, &{&1.id, &1})

      assert unmodelled[:oath_of_wrath].affects == ["buff"]
      assert unmodelled[:mounted_archery].affects == ["mounted_combat"]
      assert unmodelled[:opportunist].affects == ["attack_bonus"]

      applied = Map.new(ruleset.attack_bonuses.applied, &{&1.id, &1})
      refute applied[:epic_prowess].affects
    end
  end

  describe "загрузчик падает на получателе вне словаря" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      root = Path.join(dir, "rules")
      File.cp_r!("priv/rules", root)

      %{root: root, path: Path.join([root, "vanilla", "feat_attack_bonuses.json"])}
    end

    defp rewrite2!(path, fun) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> fun.()
      |> Jason.encode!()
      |> then(&File.write!(path, &1))
    end

    defp patch2(path, name, fun) do
      rewrite2!(path, fn markup ->
        update_in(markup["bonuses"], fn entries ->
          Enum.map(entries, fn entry ->
            if name(entry) == name, do: fun.(entry), else: entry
          end)
        end)
      end)
    end

    test "получатель с опечаткой", %{root: root, path: path} do
      patch2(path, "oath_of_wrath", &Map.put(&1, "affects", ["buf"]))

      assert_raise RuntimeError, ~r/"buf".*neither/s, fn -> Loader.load!(root) end
    end

    test "affects строкой вместо списка", %{root: root, path: path} do
      patch2(path, "oath_of_wrath", &Map.put(&1, "affects", "buff"))

      assert_raise RuntimeError, ~r/Expected a non-empty list/, fn -> Loader.load!(root) end
    end

    test "пустой affects", %{root: root, path: path} do
      patch2(path, "oath_of_wrath", &Map.put(&1, "affects", []))

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
      assert sweep["candidates"] == length(entries())

      # ⚠️ 517, а не 507 как у 1.12a: корпус вырос между 08.08 и 09.08
      # (`siala_41/classes.json` и `siala_41/races.json` пополнились).
      assert sweep["records_checked"] == 517
      assert length(sweep["corpus"]) == 9
    end

    # Три имени, названные в постановке задачи заранее, — все три в файле, и
    # с теми вердиктами, которые дала разведка.
    test "имена из постановки размечены" do
      by_name = Map.new(entries(), &{name(&1), &1})

      # Единственная безусловная прибавка от обычного фита.
      assert by_name["epic_prowess"]["verdict"] == "applied"

      # Два фита Мастера оружия: решение принимается один раз, записью класса,
      # потому что колонка «AB bonus» — их сумма.
      #
      # ⚠️ С 14.08.2026 их ТРОЕ. `weapon_of_choice` числа не даёт вовсе — он
      # НАЗНАЧАЕТ оружие, на которое колонка действует, — но эффект его в билд
      # доезжает и доезжает целиком, значит и указывать он обязан туда же. Пока
      # он стоял `not_an_attack_bonus`, загрузчик выбрасывал запись вовсе, и
      # у каждого билда с этим фитом висела оговорка «прибавку от фита не
      # считаем» рядом с посчитанным термом `weapon_master`.
      for id <- ~w(superior_weapon_focus epic_superior_weapon_focus weapon_of_choice) do
        assert by_name[id]["verdict"] == "counted_elsewhere", id
        assert by_name[id]["owned_by"] == "weapon_master", id
      end

      # ⚠️ И `owned_by` обязан указывать на запись, которая ДЕЙСТВИТЕЛЬНО
      # применяется: «учтено вон там» снимает оговорку с билда, а указатель
      # в пустоту снял бы её ни за что.
      assert by_name["weapon_master"]["verdict"] == "applied"
    end

    # Граница с 1.12a: обе записи, помеченные там как `owned_by: "1.12b"`,
    # ЗДЕСЬ обязаны быть разобраны — иначе «передали в другую задачу» осталось
    # бы обещанием.
    test "оба маркера границы, переданные задачей 1.12a, разобраны" do
      saves =
        "priv/rules/vanilla/feat_save_bonuses.json" |> File.read!() |> Jason.decode!()

      handed_over =
        for e <- saves["bonuses"], e["owned_by"] == "1.12b", do: e["feat"] || e["class"]

      assert Enum.sort(handed_over) == ~w(epic_prowess superior_weapon_focus)

      by_name = Map.new(entries(), &{name(&1), &1})
      for id <- handed_over, do: assert(by_name[id], "#{id} передан из 1.12a и не разобран")
    end

    # Ловушки, которые легко разметить по имени вместо содержания. Все четыре
    # названы в файле явно с доводом.
    test "ловушки по имени размечены как отказы" do
      by_name = Map.new(entries(), &{name(&1), &1})

      # Урон выбранным оружием — не атака, хотя имя из того же семейства.
      for id <- ~w(weapon_specialization epic_weapon_specialization) do
        assert by_name[id]["verdict"] == "not_an_attack_bonus", id
      end

      # Критический диапазон и множитель — тоже не бросок атаки.
      for id <- ~w(improved_critical ki_critical increased_multiplier overwhelming_critical) do
        assert by_name[id]["verdict"] == "not_an_attack_bonus", id
      end

      # `Improved parry` — встречный бросок парирования; на странице Fandom
      # слово «attack» в этой фразе даже зачёркнуто.
      assert by_name["improved_parry"]["verdict"] == "not_an_attack_bonus"
      # Инициатива, а не попадание.
      assert by_name["superior_initiative"]["verdict"] == "not_an_attack_bonus"
    end

    # ⚠️ Решение по оружию — самое дорогое в файле, и оно обязано быть
    # записано, а не подразумеваться: без него следующая разведка «починит»
    # мнимый пропуск и посчитает фокус.
    test "решение по оружию записано и распространено на всё семейство" do
      decision = @markup["_weapon_decision"]

      assert decision["answer"] =~ "НЕ считать"
      # Четыре довода и цена решения — все названы.
      for key <- ~w(why_1_precedent_in_this_project why_2_finesse_precedent_does_not_transfer
                    why_3_the_cap_compounds_the_error why_4_the_error_must_be_discoverable
                    what_it_costs how_to_flip_it) do
        assert is_binary(decision[key]) and decision[key] != "", key
      end

      # 🔴 И РАЗВЁРНУТО 10.08.2026 — ровно так, как предписывал его собственный
      # `how_to_flip_it`. Разбор оставлен целиком (проверено выше), плюс объявлен
      # статус: без него следующий читатель решит, что вердикт `applied`
      # поставили, не заметив решения.
      assert decision["_status"] =~ "РАЗВЁРНУТО"

      # 🔴 И РАЗВЁРНУТО ДО КОНЦА 25.08.2026 (задача 3.101): записей с условием
      # `weapon` не осталось НИ ОДНОЙ. Двое последних — `Enchant arrow`
      # и `Good aim` — упирались не в вердикт и не в отсутствие оружия в билде,
      # а в таксономию: оружие названо классом («лук», «метательное»). Оба
      # класса оказались названы источником поимённо, и обе цитаты лежали
      # в кэше на страницах САМОГО ОРУЖИЯ, а не фитов.
      weapon_conditional =
        for e <- entries(), e["condition"] == "weapon", do: name(e)

      assert weapon_conditional == []

      # Положительный контроль к предыдущей строке: все пятеро действительно
      # уехали в applied, а не потерялись.
      applied_on_weapon =
        for e <- entries(), e["applies_to_weapon"], do: name(e)

      assert Enum.sort(applied_on_weapon) ==
               ~w(enchant_arrow epic_weapon_focus good_aim weapon_focus weapon_master)

      assert @markup["_conditions"]["weapon"] =~ "НЕ ОСТАЛОСЬ НИ ОДНОЙ"
      assert decision["_status"] =~ "ДОВЕДЕНО ДО КОНЦА"
    end
  end

  describe "загрузчик роняет сборку на битой разметке" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      root = Path.join(dir, "rules")
      File.cp_r!("priv/rules", root)

      %{root: root, path: Path.join([root, "vanilla", "feat_attack_bonuses.json"])}
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
      applied = Map.new(ruleset.attack_bonuses.applied, &{&1.id, &1})
      unmodelled = Map.new(ruleset.attack_bonuses.unmodelled, &{&1.id, &1})

      assert applied[:epic_prowess].amount == %{kind: :flat, bonus: 1}
      assert applied[:epic_prowess].source == {:feat, :epic_prowess}
      assert applied[:epic_prowess].covers_feat?

      # ⚠️ small_stature стал not_modelled задачей 3.143 (30.08.2026) — цитата
      # в разметке была обрезана перед условием «когда противник крупнее
      # персонажа», и запись считалась безусловной.
      assert unmodelled[:small_stature].amount == %{kind: :flat, bonus: 1}
      assert unmodelled[:small_stature].source == {:race_feat, :small_stature}
      assert unmodelled[:small_stature].condition == :relative_size

      # 🔴 Три записи «выбранным оружием» — теперь applied, с оружием, взятым от
      # выбора названных фитов (задача 3.5, часть B).
      assert applied[:weapon_focus].weapon == [:weapon_focus]
      assert applied[:epic_weapon_focus].weapon == [:epic_weapon_focus, :weapon_focus]
      assert applied[:weapon_master].weapon == [:weapon_of_choice, :weapon_focus]
      assert applied[:weapon_master].amount.attack_at_class_level[28] == 7

      # 🔴 И две записи «классом оружия» — applied с задачи 3.101, и называют
      # они оружие ДРУГИМ полем: `weapon` у них пуст, потому что назначающего
      # фита у такой прибавки нет вовсе.
      assert applied[:good_aim].weapon_kind == {:property, :thrown}
      refute applied[:good_aim].weapon

      assert applied[:enchant_arrow].weapon_kind ==
               {:one_of, MapSet.new([:longbow, :shortbow, :light_crossbow, :heavy_crossbow])}

      refute applied[:enchant_arrow].weapon
      assert applied[:enchant_arrow].amount.attack_at_class_level[29] == 15

      # ⚠️ Отрицательный контроль к предыдущему: арбалеты в списке — это факт
      # ШАРДА («Все классовые умения Тайного лучника теперь распространяются
      # на малый и большие арбалеты»), и у ванильного ruleset'а их там нет.
      vanilla_applied =
        Map.new(Loader.load!(root)["vanilla"].attack_bonuses.applied, &{&1.id, &1})

      assert vanilla_applied[:enchant_arrow].weapon_kind ==
               {:one_of, MapSet.new([:longbow, :shortbow])}

      unmodelled = Map.new(ruleset.attack_bonuses.unmodelled, &{&1.id, &1})
      assert unmodelled[:expertise].condition == :combat_mode

      # Отрицательный контроль к строке выше: у посчитанной записи `condition`
      # нет вовсе, он остался только у отвергнутых.
      refute applied[:weapon_focus].condition

      # 🔴 Третья половина, заведённая 14.08.2026: до неё загрузчик выбрасывал
      # `counted_elsewhere` вовсе, и запись «этот факт учтён вон там» доезжала
      # до ядра как отсутствие записи.
      elsewhere = Map.new(ruleset.attack_bonuses.counted_elsewhere, &{&1.id, &1})

      assert elsewhere[:weapon_of_choice].owned_by == "weapon_master"
      assert elsewhere[:weapon_of_choice].covers_feat?
      assert elsewhere[:superior_weapon_focus].owned_by == "weapon_master"

      # ⚠️ И `owned_by` у остальных вердиктов пуст — поле только у этого.
      refute applied[:epic_prowess].owned_by
      refute unmodelled[:expertise].owned_by
    end

    # ⚠️ И положительный контроль механизма честности: без файла ядро молчать
    # не имеет права — applied/unmodelled обязаны вернуться пустыми, а не
    # приподняться из кэша прошлой сборки.
    test "без файла возвращается пустая разметка", %{root: root, path: path} do
      File.rm!(path)
      ruleset = Loader.load!(root)["siala_41"]

      assert ruleset.attack_bonuses == %{applied: [], unmodelled: [], counted_elsewhere: []}
    end

    test "имя несуществующего фита", %{root: root, path: path} do
      rewrite!(path, fn markup ->
        update_in(markup["bonuses"], &[%{"feat" => "not_a_feat", "verdict" => "applied"} | &1])
      end)

      assert_raise RuntimeError, ~r/not_a_feat/, fn -> Loader.load!(root) end
    end

    test "имя несуществующей расы", %{root: root, path: path} do
      patch(path, "half_elf", &Map.put(&1, "race", "moon_elf"))

      assert_raise RuntimeError, ~r/moon_elf/, fn -> Loader.load!(root) end
    end

    test "два источника в одной записи", %{root: root, path: path} do
      patch(path, "epic_prowess", &Map.put(&1, "class", "monk"))

      assert_raise RuntimeError, ~r/2 sources/, fn -> Loader.load!(root) end
    end

    test "applied без величины", %{root: root, path: path} do
      patch(path, "epic_prowess", &Map.delete(&1, "amount"))

      assert_raise RuntimeError, ~r/states no amount/, fn -> Loader.load!(root) end
    end

    test "неизвестная форма величины", %{root: root, path: path} do
      patch(path, "epic_prowess", &put_in(&1, ["amount", "kind"], "per_moon_phase"))

      assert_raise RuntimeError, ~r/per_moon_phase/, fn -> Loader.load!(root) end
    end

    # 🔴 Сторож вместо реализации: форма, которую ядро считать не умеет, на
    # applied-записи роняет сборку, а не считается молча нулём. Ровно этим
    # держится решение «реализуем только flat».
    test "applied с формой, которую ядро не считает", %{root: root, path: path} do
      patch(path, "epic_prowess", fn entry ->
        put_in(entry, ["amount"], %{"kind" => "ability_modifier", "ability" => "str"})
      end)

      assert_raise RuntimeError, ~r/not one the rules core computes/, fn -> Loader.load!(root) end
    end

    # ⚠️ Жертва сменилась 25.08.2026: раньше здесь портили `enchant_arrow`,
    # а он стал `applied`, у которого `condition` не читается вовсе. Взят
    # `expertise` — первая попавшаяся живая `not_modelled`-запись.
    test "not_modelled без условия", %{root: root, path: path} do
      patch(path, "expertise", &Map.delete(&1, "condition"))

      assert_raise RuntimeError, ~r/names no condition/, fn -> Loader.load!(root) end
    end

    test "неизвестное условие", %{root: root, path: path} do
      patch(path, "expertise", &Map.put(&1, "condition", "full_moon"))

      assert_raise RuntimeError, ~r/full_moon/, fn -> Loader.load!(root) end
    end

    # 🔴 Сторожа поля `owned_by` (14.08.2026). Оно решает, снимется ли с билда
    # оговорка «прибавку от фита в статы не считаем», — то есть запись без него
    # молча оставила бы оговорку висеть, а запись с ним не на том вердикте
    # молча сняла бы её ни за что.
    test "counted_elsewhere без owned_by", %{root: root, path: path} do
      patch(path, "weapon_of_choice", &Map.delete(&1, "owned_by"))

      assert_raise RuntimeError, ~r/does not say who counts the fact/, fn ->
        Loader.load!(root)
      end
    end

    test "owned_by на вердикте, которому его иметь нечем", %{root: root, path: path} do
      patch(path, "epic_prowess", &Map.put(&1, "owned_by", "weapon_master"))

      assert_raise RuntimeError, ~r/anywhere to point/, fn -> Loader.load!(root) end
    end

    # 🔴 Сторожа поля `applies_to_weapon` (задача 3.5, часть B). Каждый закрывает
    # свою форму молчаливого нуля: без них прибавка, объявленная «выбранным
    # оружием», не считалась бы НИКОГДА, и заметить это было бы нечем.
    test "applies_to_weapon называет несуществующий фит", %{root: root, path: path} do
      patch(path, "weapon_focus", &put_in(&1, ["applies_to_weapon", "choice_of"], ["not_a_feat"]))

      assert_raise RuntimeError, ~r/not_a_feat/, fn -> Loader.load!(root) end
    end

    test "applies_to_weapon называет фит, который оружия не выбирает", %{root: root, path: path} do
      patch(path, "weapon_focus", &put_in(&1, ["applies_to_weapon", "choice_of"], ["toughness"]))

      assert_raise RuntimeError, ~r/could never be known/, fn -> Loader.load!(root) end
    end

    test "applies_to_weapon с пустым списком", %{root: root, path: path} do
      patch(path, "weapon_focus", &put_in(&1, ["applies_to_weapon", "choice_of"], []))

      assert_raise RuntimeError, ~r/non-empty/, fn -> Loader.load!(root) end
    end

    test "applies_to_weapon у отвергнутой записи", %{root: root, path: path} do
      patch(
        path,
        "expertise",
        &Map.put(&1, "applies_to_weapon", %{"choice_of" => ["weapon_focus"]})
      )

      assert_raise RuntimeError, ~r/where it decides nothing/, fn -> Loader.load!(root) end
    end

    # 🔴 Сторожа ВТОРОГО способа назвать оружие (задача 3.101). Каждый закрывает
    # свою форму молчаливого нуля: условие, которое не выполнится никогда, —
    # это прибавка, которой не получит никто, и заметить это изнутри
    # инструмента нечем.
    test "два способа назвать оружие сразу", %{root: root, path: path} do
      patch(path, "good_aim", &put_in(&1, ["applies_to_weapon", "weapon_one_of"], ["sling"]))

      assert_raise RuntimeError, ~r/exactly one of/, fn -> Loader.load!(root) end
    end

    test "applies_to_weapon без единого способа", %{root: root, path: path} do
      patch(path, "good_aim", &Map.put(&1, "applies_to_weapon", %{}))

      assert_raise RuntimeError, ~r/exactly one of/, fn -> Loader.load!(root) end
    end

    test "свойство оружия, которого ядро не умеет читать", %{root: root, path: path} do
      patch(path, "good_aim", &put_in(&1, ["applies_to_weapon"], %{"weapon_must_be" => "shiny"}))

      assert_raise RuntimeError, ~r/cannot read that property/, fn -> Loader.load!(root) end
    end

    test "weapon_one_of называет несуществующее оружие", %{root: root, path: path} do
      patch(
        path,
        "enchant_arrow",
        &put_in(&1, ["applies_to_weapon"], %{"weapon_one_of" => ["bow"]})
      )

      assert_raise RuntimeError, ~r/dictionary does not carry/, fn -> Loader.load!(root) end
    end

    test "weapon_one_of пустым списком", %{root: root, path: path} do
      patch(path, "enchant_arrow", &put_in(&1, ["applies_to_weapon"], %{"weapon_one_of" => []}))

      assert_raise RuntimeError, ~r/non-empty list of weapon ids/, fn -> Loader.load!(root) end
    end

    # 🔴 И сторож СТЫКА двух правил: шард расширяет оружие классовых умений
    # (`siala_41/classes.json` → `class_ability_weapons`), и расширить можно
    # только перечисление. Запись, чьё оружие названо выбором фита или
    # свойством, обязана уронить сборку — применить правило шарда наполовину
    # значит завести ровно тот молчаливый разъезд, ради которого правило
    # и живёт в одном месте (урок задачи 3.85).
    test "шард расширяет оружие записи, названное не перечислением", %{root: root, path: path} do
      patch(path, "enchant_arrow", fn entry ->
        Map.put(entry, "applies_to_weapon", %{"weapon_must_be" => "ranged"})
      end)

      assert_raise RuntimeError, ~r/only an enumeration can be widened/, fn ->
        Loader.load!(root)
      end
    end

    test "несуществующая характеристика", %{root: root, path: path} do
      patch(path, "smite_evil", &put_in(&1, ["amount", "ability"], "luck"))

      assert_raise RuntimeError, ~r/ability luck/, fn -> Loader.load!(root) end
    end

    test "ступень таблицы, названная не уровнем", %{root: root, path: path} do
      patch(path, "weapon_master", fn entry ->
        update_in(entry["amount"]["attack_at_class_level"], &Map.put(&1, "пятый", 1))
      end)

      assert_raise RuntimeError, ~r/class level/, fn -> Loader.load!(root) end
    end

    test "несуществующий класс в таблице", %{root: root, path: path} do
      patch(path, "weapon_master", &put_in(&1, ["amount", "class"], "blade_dancer"))

      assert_raise RuntimeError, ~r/blade_dancer/, fn -> Loader.load!(root) end
    end
  end

  describe "оба ruleset'а несут разметку" do
    # Файл ванильный и накладывается на оба: своих ЗАПИСЕЙ про атаку у шарда
    # нет ни одной (`_sweep.shard_layer`).
    test "состав разметки одинаковый на обоих ruleset'ах" do
      for version <- ~w(vanilla siala_41) do
        ruleset = Data.ruleset!(version)

        # ⚠️ 7 и 25, а не 5 и 30: задача 3.101 перевела в applied последние две
        # записи «оружием» — `Enchant arrow` и `Good aim`, — а задача 3.132
        # увела из `unmodelled` три записи боя двумя оружиями (28 → 25): штрафы
        # стиля теперь СЧИТАЮТСЯ, и записи стали `counted_elsewhere`. Счёт
        # одинаков на ОБОИХ ruleset'ах: записей шард не добавляет и не убирает.
        #
        # ⚠️ Стало 6 и 26 30.08.2026 (задача 3.143): `small_stature` перешёл
        # в `unmodelled` — цитата в разметке была обрезана перед условием
        # «когда противник крупнее персонажа».
        assert length(ruleset.attack_bonuses.applied) == 6
        assert length(ruleset.attack_bonuses.unmodelled) == 26

        assert Enum.map(ruleset.attack_bonuses.applied, & &1.id) ==
                 ~w(epic_prowess weapon_focus epic_weapon_focus weapon_master
                    enchant_arrow good_aim)a
      end
    end

    # 🔴 И РОВНО ОДНО ПОЛЕ, которое у двух ruleset'ов РАЗНОЕ (задача 3.101).
    # Файл по-прежнему ванильный и один на оба, но шард дописывает оружие
    # УМЕНИЯМ КЛАССА («Все классовые умения Тайного лучника теперь
    # распространяются на малый и большие арбалеты»), и правило это живёт
    # на стороне класса — второй записи о нём в файле прибавок нет.
    #
    # ⚠️ Проверяется парой: расхождение названо поимённо, а всё остальное
    # обязано совпадать до последнего поля. Без второй половины молчаливое
    # расползание разметки шарда по файлу выглядело бы как эта же правка.
    test "шард расширяет оружие ровно одной записи, и остальное совпадает" do
      by_id = fn version ->
        Data.ruleset!(version).attack_bonuses.applied |> Map.new(&{&1.id, &1})
      end

      vanilla = by_id.("vanilla")
      siala = by_id.("siala_41")

      assert vanilla[:enchant_arrow].weapon_kind == {:one_of, MapSet.new([:longbow, :shortbow])}

      assert siala[:enchant_arrow].weapon_kind ==
               {:one_of, MapSet.new([:longbow, :shortbow, :light_crossbow, :heavy_crossbow])}

      differing =
        for {id, record} <- siala, record != vanilla[id], do: id

      assert differing == [:enchant_arrow]
    end
  end
end
