defmodule BuildCalculator.Data.FeatSkillBonusesTest do
  @moduledoc """
  Сторож ручной разметки `priv/rules/vanilla/feat_skill_bonuses.json`.

  Файл существует потому, что связи «фит → навык» в корпусе нет ни в одном поле:
  все 299 записей `feats.json` держат её только английской прозой в
  `description`. Значит числа сюда переносил человек, и проверять надо ровно то,
  что человек может испортить, — что цитата **дословна**, а не пересказана, и что
  число рядом с ней взято из этой самой цитаты.

  ⚠️ Главная ловушка, которую тест закрывает отдельно: девять расовых
  `skill affinity` дают ту же прибавку, что уже лежит в `races.json`. Пометить их
  «считаем» — значит выдать каждому эльфу +4 к Обнаружению вместо +2.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules.{Build, Skills}

  @markup "priv/rules/vanilla/feat_skill_bonuses.json" |> File.read!() |> Jason.decode!()
  @feats "priv/rules/vanilla/feats.json" |> File.read!() |> Jason.decode!()
  @skills "priv/rules/vanilla/skills.json" |> File.read!() |> Jason.decode!()
  @classes "priv/rules/siala_41/classes.json" |> File.read!() |> Jason.decode!()

  @verdicts ~w(applied counted_elsewhere not_modelled not_a_skill_bonus)

  # Ревизии, на которые ссылается сторона капа у applied-записей: общее правило
  # `fandom:Skill level` и собственная страница `Bardic knowledge`. См. тест
  # «cap объявлен у каждой applied-записи».
  @cap_sources [56_492, 51_806]

  # Виды источника, ровно те же четыре, что у ac_bonuses.json и
  # feat_save_bonuses.json (задача 3.25). До неё ключ был всегда `feat`, и именно
  # это отнимало оговорку у расовых склонностей.
  @source_keys ~w(feat class skill race_feat)

  defp entries, do: @markup["bonuses"]
  defp feat(id), do: Enum.find(@feats, &(&1["id"] == id))
  defp skill_ids, do: MapSet.new(@skills, & &1["id"])

  # Имя источника записи вне зависимости от того, каким из четырёх ключей он
  # назван, и сам ключ рядом.
  defp source(entry) do
    case for(key <- @source_keys, is_binary(entry[key]), do: {key, entry[key]}) do
      [pair] -> pair
    end
  end

  defp source_id(entry), do: entry |> source() |> elem(1)
  defp bonus(entry), do: entry["amount"]["bonus"]

  # Одна запись, как она доезжает до ядра — списком под `ruleset.skill_bonuses`,
  # а не полем фита (задача 3.25). Две половины спрашиваются отдельно: `nil`
  # у одной при непустой другой — это и есть «вердикт такой-то», а не «записи
  # нет».
  defp rejected(ruleset, id), do: Enum.find(ruleset.skill_bonuses.unmodelled, &(&1.id == id))
  defp applied(ruleset, id), do: Enum.find(ruleset.skill_bonuses.applied, &(&1.id == id))

  describe "цитаты" do
    # Единственная проверка, ради которой этот файл тестируется вообще. Всё
    # остальное — про схему; это — про честность: цитата обязана быть куском
    # источника, а не его пересказом.
    test "каждая цитата — дословная подстрока description своего фита" do
      for entry <- entries() do
        id = source_id(entry)
        source = feat(id)

        assert source, "#{id}: такого фита нет в vanilla/feats.json"

        assert String.contains?(source["description"] || "", entry["quote"]),
               "#{id}: цитата не найдена в description дословно"
      end
    end

    test "у каждой записи есть источник страницы, с которой снята цитата" do
      for entry <- entries() do
        assert entry["source"]["wiki"] == "fandom"
        assert is_binary(entry["source"]["page"])
        assert is_integer(entry["source"]["revid"])
      end
    end
  end

  describe "схема" do
    test "вердикт у каждой записи из известного набора" do
      for entry <- entries(), do: assert(entry["verdict"] in @verdicts)
    end

    test "фит упомянут не больше одного раза" do
      ids = Enum.map(entries(), &source_id/1)
      assert ids == Enum.uniq(ids)
    end

    test "все навыки существуют" do
      known = skill_ids()

      for entry <- entries(), skill <- entry["skills"] do
        assert MapSet.member?(known, skill), "#{source_id(entry)}: навыка #{skill} нет"
      end
    end

    # `applied` без числа или без навыка — это запись, которая выглядит как факт
    # и не является им. Загрузчик на такой падает; здесь то же самое сказано
    # тестом, чтобы поломка называлась своим именем, а не «не собирается».
    #
    # ⚠️ Формы величины теперь ДВЕ, и у каждой свой обязательный минимум:
    # у плоской — число, у суммы уровней — непустой список классов. Здесь стояло
    # `kind == "flat"` для всех applied — верно до 16.08.2026, когда замер F7
    # сделал `class_level_sum` считаемой формой.
    #
    # ⚠️ И ОДНО ИСКЛЮЧЕНИЕ по навыкам с 25.08.2026 (задача 3.92): запись может
    # вместо списка объявить `skills_from: "feat_choice"` — «получателя называет
    # пик, а не страница». Тогда пустой список обязателен, а не допустим:
    # два ответа на вопрос «кому прибавили» и есть та поломка, от которой стоит
    # весь этот файл. Загрузчик роняет сборку на обоих перекосах.
    test "у applied названы и навыки, и величина в форме, которую ядро читает" do
      for entry <- entries(), entry["verdict"] == "applied" do
        case entry["skills_from"] do
          nil -> assert entry["skills"] != []
          "feat_choice" -> assert entry["skills"] == []
          other -> flunk("#{source_id(entry)}: skills_from #{inspect(other)} без читателя")
        end

        case entry["amount"]["kind"] do
          "flat" -> assert is_integer(bonus(entry))
          "class_level_sum" -> assert entry["amount"]["classes"] != []
          other -> flunk("#{source_id(entry)}: форма величины #{inspect(other)} без читателя")
        end
      end
    end

    test "у не-applied записи сказано, почему её не считают" do
      for entry <- entries(), entry["verdict"] != "applied" do
        assert is_binary(entry["why"]) or is_binary(entry["owned_by"]),
               "#{source_id(entry)}: вердикт #{entry["verdict"]} без объяснения"
      end
    end

    # ---------------------------------- схема, приведённая к общей (3.25) --

    # Ровно один ключ источника — иначе загрузчик не знает, каким гейтом
    # проверять владение, и «две записи в одной» прошли бы молча.
    test "у каждой записи ровно один вид источника, и он из известной четвёрки" do
      for entry <- entries() do
        named = for key <- @source_keys, is_binary(entry[key]), do: key

        assert length(named) == 1, "#{inspect(entry)}: видов источника #{length(named)}"
      end
    end

    # ⚠️ Регрессия на саму дыру задачи 3.25: расовая склонность обязана быть
    # `race_feat`, потому что от вида источника зависит ГЕЙТ ВЛАДЕНИЯ, а не
    # только красота схемы. Стояли под `feat` — оговорка не доезжала ни до кого.
    #
    # Список — не «все, у кого type == race»: `keen_sense` намеренно оставлен
    # под `feat` (на Сиале это `classrace`, и ни один ключ не верен для обоих
    # путей), и это сказано в его `note`.
    test "расовые склонности помечены race_feat, а не feat" do
      race_feats = for entry <- entries(), is_binary(entry["race_feat"]), do: entry["race_feat"]

      assert Enum.sort(race_feats) == [
               "partial_skill_affinity_listen",
               "partial_skill_affinity_search",
               "partial_skill_affinity_spot",
               "skill_affinity_concentration",
               "skill_affinity_listen",
               "skill_affinity_lore",
               "skill_affinity_move_silently",
               "skill_affinity_search",
               "skill_affinity_spot",
               "skilled",
               "small_stature",
               "stonecunning"
             ]

      # Положительный контроль: у каждой из них `type: "race"` в самом справочнике
      # фитов — то есть ключ поставлен по факту, а не по нашему мнению.
      for id <- race_feats, do: assert(feat(id)["type"] in ~w(race classrace), id)

      # И обратная половина: `keen_sense` под `feat` СОЗНАТЕЛЬНО, и запись это
      # объясняет. Без этой строки список выше зеленел бы и от того, что кто-то
      # просто забыл перевести ещё одну склонность.
      keen = Enum.find(entries(), &(&1["feat"] == "keen_sense"))
      assert keen, "keen_sense должен остаться под ключом feat"
      assert keen["note"] =~ "classrace"
    end

    # Сторона капа — обязательна у applied и запрещена у остальных. Тот же
    # контракт, что у feat_save_bonuses.json и feat_attack_bonuses.json.
    #
    # ⚠️ Источников стороны ДВА, и здесь стояло жёсткое `revid == 56492`.
    # Восемь записей ссылаются на общее правило (`fandom:Skill level`, revid
    # 56492) — про них самих не написал никто; у `bardic_knowledge` про сторону
    # говорит его СОБСТВЕННАЯ страница («This bonus does not contribute to the
    # +50 skill cap», revid 51806), и ответ у них один и тот же. Проверяем, что
    # revid из известной пары, а не что он один: сторона объявляется у каждой
    # записи именно затем, чтобы ближний источник мог перебить общий.
    test "cap объявлен у каждой applied-записи и ни у одной другой" do
      for entry <- entries() do
        if entry["verdict"] == "applied" do
          assert entry["cap"]["inside_cap"] == false, "#{source_id(entry)}: сторона капа"
          assert entry["cap"]["status"] in ~w(verified assumed)
          assert is_binary(entry["cap"]["quote"])
          assert entry["cap"]["source"]["revid"] in @cap_sources, source_id(entry)
        else
          refute Map.has_key?(entry, "cap"), "#{source_id(entry)}: cap у не-applied записи"
        end
      end
    end

    # `effect_coverage` — то же поле, что у сейвов и характеристик: суждение
    # человека, а не вывод из того, что прибавка применена.
    test "effect_coverage стоит у каждой applied-записи и только у них" do
      for entry <- entries() do
        if entry["verdict"] == "applied" do
          assert entry["effect_coverage"] in ~w(whole_feat partial), source_id(entry)
        else
          refute Map.has_key?(entry, "effect_coverage"), source_id(entry)
        end
      end
    end
  end

  # ⚠️ Задача «пять файлов прибавок» (17.08.2026): получатель факта (`affects`)
  # доехал сюда последним из пяти — classes.json и skills.json несли его с
  # 10–14.08.2026. Словарь по-прежнему ОДИН на весь проект и живёт в
  # siala_41/classes.json → `_receivers`; этот файл своего не заводит и его не
  # проверяет — то, что словарь непуст и `our`/`not_our` не пересекаются, уже
  # стережёт `ClassChangeReceiversTest`. Здесь — то, что специфично для файла:
  # что метка стоит РОВНО у not_modelled (см. схема.affects) и что гэп у
  # siala_41 её действительно слушает.
  describe "получатели факта (affects)" do
    defp known_receivers do
      MapSet.union(
        MapSet.new(Map.keys(@classes["_receivers"]["our"])),
        MapSet.new(Map.keys(@classes["_receivers"]["not_our"]))
      )
    end

    # ⚠️ И только у него: applied/counted_elsewhere уже в числе (или в чужом
    # числе) и гэпом не бывают по построению (`Rules.Bonuses.rejected/2`
    # читает только `not_modelled`), а not_a_skill_bonus не переживает
    # `markup_buckets/1` вовсе — ей нечем стать гэпом. Метка там не значила бы
    # ничего проверяемого, см. `_schema.affects` в самом файле.
    #
    # ⚠️ И у записи с `skills_from` — с 25.08.2026 (задача 3.92). Исключение
    # не спорит с правилом выше, а следует из него: такая запись РЕЗОЛВИТСЯ
    # ПО RULESET-У и на ruleset'е, который не знает про выбор навыка, снова
    # становится `not_modelled` (`epic_skill_focus` на ванили). Без метки она
    # вернулась бы туда гэпом «на всякий случай».
    test "метка стоит ровно у not_modelled и у записи с выбором, и нигде больше" do
      for entry <- entries() do
        case {entry["verdict"], entry["skills_from"]} do
          {"not_modelled", _} ->
            assert is_list(entry["affects"]) and entry["affects"] != [],
                   "#{source_id(entry)}: not_modelled без affects"

          {"applied", "feat_choice"} ->
            assert is_list(entry["affects"]) and entry["affects"] != [],
                   "#{source_id(entry)}: запись с выбором без affects"

          {other, _} ->
            refute Map.has_key?(entry, "affects"),
                   "#{source_id(entry)}: affects у вердикта #{other}"
        end
      end
    end

    test "каждый получатель — из закрытого словаря siala_41/classes.json" do
      known = known_receivers()

      for entry <- entries(), receiver <- entry["affects"] || [] do
        assert receiver in known,
               "#{source_id(entry)}: получатель #{receiver} вне словаря"
      end
    end

    # Снимок: молчаливый дрейф здесь и есть та ошибка, ради которой поле
    # заведено. Названо поимённо, а не одним числом.
    #
    # ⚠️ Записей стало ПЯТЬ, а было семь (25.08.2026, задача 3.92): `skill_focus`
    # и `epic_skill_focus` перешли в `applied`. Их классификация при этом
    # не изменилась ни на строку — `skill_values` как был, так и есть, и обе
    # записи проверяются вторым списком ниже: получатель никуда не делся,
    # он перестал быть ОГОВОРКОЙ и стал ЧИСЛОМ.
    test "снимок классификации пяти not_modelled записей" do
      by_id =
        for entry <- entries(), entry["verdict"] == "not_modelled", into: %{} do
          {source_id(entry), entry["affects"]}
        end

      assert by_id == %{
               "favored_enemy" => ["skill_values"],
               "trackless_step" => ["skill_values"],
               "stonecunning" => ["skill_values"],
               "oath_of_wrath" => ["buff"],
               "small_stature" => ["special_ability"]
             }

      by_choice =
        for entry <- entries(), entry["skills_from"] == "feat_choice", into: %{} do
          {source_id(entry), {entry["verdict"], entry["affects"]}}
        end

      assert by_choice == %{
               "skill_focus" => {"applied", ["skill_values"]},
               "epic_skill_focus" => {"applied", ["skill_values"]}
             }
    end

    # Идёт ли метка ДАЛЬШЕ файла — до `ruleset.skill_bonuses.unmodelled`, а не
    # только до сырого JSON. Список ключей ровно тот же, что несёт JSON:
    # строки, не атомы — `Rules.GapReceivers.ours?/2` читает `fact["affects"]`
    # как строки, и переводить их в атомы значило бы завести вторую форму
    # одного и того же поля.
    test "affects доезжает до ruleset без изменения формы" do
      ruleset = Data.ruleset!("siala_41")

      assert rejected(ruleset, :oath_of_wrath).affects == ["buff"]
      assert rejected(ruleset, :small_stature).affects == ["special_ability"]
      assert rejected(ruleset, :trackless_step).affects == ["skill_values"]

      # Положительный контроль формы: applied-записи тоже несут поле, и у них
      # оно `nil` — не значит «не проверено», значит «не заводили».
      refute applied(ruleset, :alertness).affects
    end

    # ⚠️ Главная проверка задачи: гэп siala_41 действительно перестал
    # печатать `oath_of_wrath` и `small_stature`, потому что оба помечены
    # НЕ нашим получателем — а `stonecunning`/`trackless_step` остались,
    # потому что помечены skill_values. Прогон, а не чтение JSON.
    # ⚠️ 22.08.2026 (задача 3.76) список опустел, и название теста стало
    # неверным наполовину: `buff` и `special_ability` ушли по ПОЛУЧАТЕЛЮ,
    # а `stonecunning` и `trackless_step` — по РЕШЕНИЮ владельца (условие
    # у обеих — местность, состояние мира). Две разные причины, и они
    # обязаны быть различимы, иначе следующий читатель решит, что у записей
    # сменился `affects`.
    test "ruleset.gaps siala_41: пусто — по получателю и по решению владельца" do
      ruleset = Data.ruleset!("siala_41")
      ids = for {:not_modelled, {:feat_skill_bonus, id}} <- ruleset.gaps, do: id

      assert ids == []

      # 🔴 И это НЕ «разметка растерялась»: обе записи на месте, с прежним
      # вердиктом и прежним получателем, — ушло только признание.
      for id <- [:stonecunning, :trackless_step] do
        record = Enum.find(ruleset.skill_bonuses.unmodelled, &(&1.id == id))

        assert record.verdict == :not_modelled
        assert record.affects == ["skill_values"]
        assert is_map(record.not_a_gap)
      end
    end

    # ⚠️ И обратная сторона, которую легко упустить: у `vanilla` словаря нет
    # вовсе (`gap_receivers!(:missing)` отдаёт два пустых множества), а пустой
    # `our` — это «фильтра нет вообще», а не «ничего не наше» (тот же принцип,
    # что у siala-слоёв: «vanilla, синтетический ruleset» в moduledoc
    # `Rules.GapReceivers`). Поэтому у vanilla список НЕ сузился — в нём
    # по-прежнему пять записей, включая `epic_skill_focus`, которого нет
    # у siala_41 вовсе (он repeatable только на шардовом слое фитов).
    test "ruleset.gaps vanilla: список не сузился — словаря нет, фильтра нет" do
      ids = for {:not_modelled, {:feat_skill_bonus, id}} <- Data.ruleset!("vanilla").gaps, do: id

      # ⚠️ 22.08.2026 (задача 3.76): пятёрка стала тройкой, и НЕ потому, что
      # у vanilla появился фильтр получателей — его по-прежнему нет. Решение
      # владельца (`not_a_gap`) читается ДО проверки словаря и применяется
      # к обоим ruleset'ам, и это правильно: `Stonecunning` и `Trackless step`
      # — ванильные фиты, условие у них ванильное (местность), и решение
      # «до нашего ответа не доезжает» не может быть верным на одном слое
      # и неверным на другом.
      assert Enum.sort(ids) == [:epic_skill_focus, :oath_of_wrath, :small_stature]
    end
  end

  describe "загрузчик падает на получателе вне словаря (пять файлов прибавок)" do
    defp copy_and_edit(fun) do
      root = copy_rules()
      edit_entry(root, "trackless_step", fun)
      root
    end

    test "чистая копия по-прежнему грузится — иначе assert_raise ниже зеленел бы впустую" do
      assert %{"vanilla" => _, "siala_41" => _} = Loader.load!(copy_rules())
    end

    test "получатель с опечаткой" do
      root = copy_and_edit(&Map.put(&1, "affects", ["skil_values"]))

      assert_raise RuntimeError, ~r/"skil_values".*neither/s, fn -> Loader.load!(root) end
    end

    test "affects строкой вместо списка" do
      root = copy_and_edit(&Map.put(&1, "affects", "skill_values"))

      assert_raise RuntimeError, ~r/Expected a non-empty list/, fn -> Loader.load!(root) end
    end

    test "пустой affects: он ничего не утверждает, и молчать про это нельзя" do
      root = copy_and_edit(&Map.put(&1, "affects", []))

      assert_raise RuntimeError, ~r/Expected a non-empty list/, fn -> Loader.load!(root) end
    end

    # ⚠️ И обратная сторона: отсутствие поля — законный случай для `applied`,
    # а не порча, и для not_modelled это тоже так же законно, пока где-то
    # выше вопрос не задан заново. Проверяется тем, что снятие поля у
    # применённой записи не роняет сборку.
    test "affects можно не заводить у applied — не порча" do
      root = copy_rules()
      edit_entry(root, "alertness", &Map.put(&1, "affects", ["skill_values"]))

      # applied c affects — тоже легальная форма (задача только требует ЕГО
      # ОТСУТСТВИЯ у не-not_modelled в ЭТОМ файле как соглашение, а не как
      # запрет схемы) — но соглашение стережёт тест выше в «получателях
      # факта», не загрузчик. Загрузчик обязан принять любую корректную форму
      # affects независимо от вердикта, иначе поле навсегда осталось бы
      # привязано к одному вердикту кодом, а не решением.
      assert %{"siala_41" => siala} = Loader.load!(root)
      applied = Enum.find(siala.skill_bonuses.applied, &(&1.id == :alertness))
      assert applied.affects == ["skill_values"]
    end
  end

  describe "расовые склонности не считаются дважды" do
    # ⚠️ Регрессия на конкретную ошибку, а не на общее правило. Прибавка
    # `skill affinity` уже приезжает из `races.json` → `skill_bonuses`; если
    # кто-то переведёт эти девять в `applied`, у эльфа станет +4 к Обнаружению,
    # и ни один другой тест этого не заметит — число просто вырастет.
    test "девять записей помечены counted_elsewhere и ни одна не применена" do
      affinities =
        Enum.filter(entries(), &String.contains?(source_id(&1), "skill_affinity"))

      assert length(affinities) == 9

      for entry <- affinities do
        assert entry["verdict"] == "counted_elsewhere"
        assert entry["owned_by"] =~ "races.json"
      end
    end

    # Положительный контроль: механизм, который их пропускает, вообще работает —
    # иначе тест выше зеленел бы и от того, что файл не читается.
    test "загрузчик не пускает их в применённые записи, а Alertness пускает" do
      ruleset = Data.ruleset!("siala_41")
      applied = MapSet.new(ruleset.skill_bonuses.applied, & &1.id)

      refute MapSet.member?(applied, :skill_affinity_spot)
      assert MapSet.member?(applied, :alertness)

      alertness = Enum.find(ruleset.skill_bonuses.applied, &(&1.id == :alertness))
      assert alertness.skills == [:listen, :spot]
      assert alertness.amount == %{kind: :flat, bonus: 2}

      # ⚠️ И ни в одной половине: `counted_elsewhere` не должен превратиться
      # в оговорку — прибавка не «не посчитана», она посчитана расой.
      refute Enum.any?(ruleset.skill_bonuses.unmodelled, &(&1.id == :skill_affinity_spot))
    end

    # Число в разметке обязано совпадать с тем, что реально едет от расы, иначе
    # «уже посчитано в другом месте» — заявление, которое никто не проверял.
    test "число в записи совпадает с расовым, которое её заменяет" do
      ruleset = Data.ruleset!("siala_41")

      from_races =
        for {_id, race} <- ruleset.races,
            {skill, bonus} <- race.skill_bonuses,
            into: MapSet.new(),
            do: {skill, bonus}

      for entry <- entries(), entry["verdict"] == "counted_elsewhere", skill <- entry["skills"] do
        assert MapSet.member?(from_races, {String.to_existing_atom(skill), bonus(entry)}),
               "#{source_id(entry)}: +#{bonus(entry)} к #{skill} ни у одной расы не значится"
      end
    end

    # ⚠️ Почему величина у `counted_elsewhere` СОХРАНЕНА, хотя у четырёх соседей
    # она там запрещена: это единственное независимое подтверждение числа из
    # races.json, и тест выше без неё проверять было бы нечем. Строка стоит
    # затем, чтобы «привести к общей схеме» не выкинуло её при следующей уборке.
    test "у расовых записей величина осталась — на ней стоит сверка выше" do
      for entry <- entries(), entry["verdict"] == "counted_elsewhere" do
        assert is_integer(bonus(entry)), "#{source_id(entry)}: величина потеряна"
      end
    end
  end

  # ⚠️ РАЗДЕЛ ПЕРЕПИСАН 16.08.2026 по замеру Dan (`GAME_CHECKS.md`, F7). Здесь
  # стояло «уже посчитано — это про ruleset, а не про файл»: `bardic_knowledge`
  # был `not_modelled` с `counted_for_classes: [harper_scout]`, то есть один id
  # умения с двумя судьбами — версию Арфиста считал шардовый слой, бардовскую
  # не считал никто. Замер показал, что судьба одна: прибавка равна СУММЕ
  # уровней барда и Арфиста, ровно как говорит Notes ванильной страницы.
  # Запись стала `applied`, `counted_for_classes` ушёл вместе с вердиктом, и
  # проверять теперь надо другое — что прибавка едет ОДИН раз и на обоих
  # ruleset'ах.
  #
  # source (правило прибавки): fandom «Bardic knowledge» revid 51806 —
  # «It grants the character a bonus equal to their [[class level]] to any
  # [[lore]] checks», Notes: «Harper scout and bard levels stack for the bonus
  # granted by this feat» (снято 2026-08-01, цитаты лежат в записи файла).
  # source (шардовая половина): siala «Арфист-скаут» revid 19414 (снято
  # 2026-08-01) — умение выдаётся со 2-го уровня класса.
  describe "прибавка равна сумме уровней названных классов" do
    setup do
      %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
    end

    # Правило ВАНИЛЬНОЕ по источнику, значит правка легла на оба ruleset'а —
    # и числа у них обязаны совпасть везде, кроме одного места: уровня, на
    # котором Арфист выдаёт сам фит.
    test "у чистого Арфиста 3 оба ruleset'а дают одно и то же", ctx do
      build = harper_lore()

      for ruleset <- [ctx.vanilla, ctx.siala] do
        value = Skills.value(build, ruleset, :lore, 9)

        # 4 ранга + INT 10 (0) + 3 уровня Арфиста
        assert {value.class_bonus, value.class_bonus_from, value.total} == {3, [:harper_scout], 7}
        assert value.unmodelled_feats == []
      end
    end

    # 🔴 И единственное расхождение — оно правильное, а не баг. Шард сдвинул
    # ВЫДАЧУ умения Арфисту с 1-го классового уровня на 2-й
    # (`siala_41/classes.json` → harper_scout → feat_level_shift), в ванили она
    # осталась на 1-м. Значит воин 6 + Арфист 1 получает +1 в ванили и ноль
    # на Сиале, при том что правило суммы у них одно.
    test "воин 6 + Арфист 1 расходится ровно на сдвиг выдачи фита", ctx do
      build =
        Build.new(
          race: :human,
          levels: List.duplicate(:fighter, 6) ++ [:harper_scout],
          skills: %{1 => %{lore: 4}}
        )

      assert Skills.value(build, ctx.vanilla, :lore, 7).class_bonus == 1
      assert Skills.value(build, ctx.siala, :lore, 7).class_bonus == 0
    end

    # Половина, которой не было вовсе: бардовские уровни. До правки бард 9
    # получал ноль и оговорку на обоих ruleset'ах.
    test "бардовская половина считается на обоих ruleset'ах", ctx do
      build =
        Build.new(race: :human, levels: List.duplicate(:bard, 9), skills: %{1 => %{lore: 4}})

      for ruleset <- [ctx.vanilla, ctx.siala] do
        value = Skills.value(build, ruleset, :lore, 9)

        assert {value.class_bonus, value.class_bonus_from} == {9, [:bard]}
        assert value.unmodelled_feats == []
      end
    end

    # Положительный контроль к трём пустым `unmodelled_feats` выше: механизм
    # оговорок жив и просто перестал быть должен ЭТУ. Ловим его на соседней
    # записи того же файла.
    # ⚠️ Пример сменился ТРИЖДЫ и на третий раз стал синтетическим. 22.08.2026
    # (3.76) ушёл `trackless_step` у друида — решением Dan, условие по
    # местности; 25.08.2026 (3.92) ушёл `Skill focus` — его +3 теперь
    # считаются; в тот же день (3.95) ушёл `Favored enemy` — решением
    # владельца, потому что описание фита называет и число, и условие.
    #
    # 🔴 Живых записей с нашим получателем в этой разметке не осталось ни одной,
    # и назначать четвёртую жертву незачем: вопрос теста — про МЕХАНИЗМ
    # доставки адресной оговорки, а не про состав данных. Запись выдуманная,
    # фит и маршрут владения настоящие; вторая половина (соседний навык молчит)
    # не изменилась ни на строку.
    test "механизм оговорок жив — их лишилась одна запись, а не все", ctx do
      hunter =
        Build.new(
          race: :human,
          levels: List.duplicate(:ranger, 9),
          skills: %{1 => %{spot: 4, lore: 4}},
          feats: %{1 => %{{:class_bonus, :ranger} => {:favored_enemy, :goblinoid}}}
        )

      narrow = fn ruleset ->
        record = %{
          id: :favored_enemy,
          source: {:feat, :favored_enemy},
          verdict: :not_modelled,
          skills: [:spot],
          amount: %{kind: :flat, bonus: 1},
          counted_for_classes: [],
          affects: ["skill_values"]
        }

        %{ruleset | skill_bonuses: %{ruleset.skill_bonuses | unmodelled: [record]}}
      end

      for ruleset <- [ctx.vanilla, ctx.siala] do
        rs = narrow.(ruleset)

        assert :favored_enemy in Skills.value(hunter, rs, :spot, 9).unmodelled_feats
        assert Skills.value(hunter, rs, :lore, 9).unmodelled_feats == []

        # И на живых данных — ни у одного навыка: решение владельца снимает
        # оговорку на ОБОИХ ruleset'ах, потому что читается раньше словаря
        # получателей (у ванили его нет вовсе).
        assert Skills.value(hunter, ruleset, :spot, 9).unmodelled_feats == []
      end
    end

    # Запись доезжает до ядра применённой и в форме, которую ядро читает.
    test "в ruleset запись лежит применённой, с обоими классами", ctx do
      for ruleset <- [ctx.siala, ctx.vanilla] do
        record = applied(ruleset, :bardic_knowledge)

        assert record.amount == %{kind: :class_level_sum, classes: [:bard, :harper_scout]}
        assert record.skills == [:lore]
        # Снаружи капа +50 — «This bonus does not contribute to the +50 skill cap».
        refute record.cap.inside?
        assert is_nil(rejected(ruleset, :bardic_knowledge))
      end
    end

    # ---------------------------------------------------------------- порча --
    #
    # ⚠️ Порча с двух сторон, как требует §7: и «посчитали дважды», и «не
    # посчитали вовсе».

    # 🔴 Сторона первая, и она — главная опасность этой правки. Шардовая запись
    # про то же умение осталась в данных ради провенанса и помечена
    # `counted_elsewhere`. Сними пометку — и уровни Арфиста снова считают ДВА
    # механизма; число выросло бы правдоподобно (у Арфиста 3 стало бы 6 вместо
    # 3), и поймать это было бы нечем. Поэтому сборка падает.
    test "убери пометку у шардовой записи — сборка падает на двойном счёте" do
      root = copy_rules()

      edit_skill(root, "lore", fn entry ->
        changes =
          Enum.map(entry["changes"], fn change ->
            Map.delete(change, "counted_elsewhere")
          end)

        %{entry | "changes" => changes}
      end)

      assert_raise RuntimeError, ~r/the skill would carry them twice/, fn ->
        Loader.load!(root)
      end
    end

    # Сторона вторая: указатель, ведущий в никуда. «Учтено вон там» —
    # единственная пометка, которая одновременно убирает правило И убирает
    # оговорку, поэтому опечатка в имени записи стирала бы факт целиком.
    test "указатель на несуществующую запись роняет сборку" do
      root = copy_rules()

      edit_skill(root, "lore", fn entry ->
        changes =
          Enum.map(entry["changes"], fn change ->
            if is_map(change["counted_elsewhere"]),
              do: put_in(change, ["counted_elsewhere", "record"], "bardic_knowldge"),
              else: change
          end)

        %{entry | "changes" => changes}
      end)

      assert_raise RuntimeError, ~r/no `applied` record/, fn -> Loader.load!(root) end
    end

    # И третья: указатель на запись, которая этот класс не считает. Проверяется
    # СОДЕРЖАНИЕ, а не только имя, — иначе «учтено вон там» подтверждалось бы
    # существованием любой записи с подходящим названием.
    test "указатель на запись, не считающую этот класс, роняет сборку" do
      root = copy_rules()

      edit_entry(root, "bardic_knowledge", fn entry ->
        put_in(entry, ["amount", "classes"], ["bard"])
      end)

      assert_raise RuntimeError, ~r/does not count harper_scout levels/, fn ->
        Loader.load!(root)
      end
    end

    # ⚠️ Опечатка в имени класса ВНУТРИ величины роняет сборку с 16.08.2026, и
    # до этой правки не роняла: пока форму не считал никто, имена в ней были
    # материалом. Теперь несуществующий класс молча вычитался бы из суммы —
    # правдоподобное число вместо верного, ровно то, ради чего файл заведён.
    test "опечатка в классе величины роняет сборку" do
      root = copy_rules()

      edit_entry(root, "bardic_knowledge", fn entry ->
        put_in(entry, ["amount", "classes"], ["bard", "harper_scut"])
      end)

      assert_raise RuntimeError, ~r/which does not exist/, fn -> Loader.load!(root) end
    end

    # ⚠️ Механизм `counted_for_classes` не носит сегодня ни одна запись (его
    # единственным носителем был `bardic_knowledge`), и его сторож проверяется
    # порчей: иначе «поля нет ни у кого» тихо превратилось бы в «поле больше
    # не работает». Вопрос, на который он отвечает, никуда не делся — запись
    # `not_modelled`, чью версию считает класс, появится снова.
    test "сторож counted_for_classes жив, хотя поля не носит никто" do
      assert Enum.all?(entries(), &is_nil(&1["counted_for_classes"]))

      root = copy_rules()

      edit_entry(root, "trackless_step", fn entry ->
        Map.put(entry, "counted_for_classes", ["harper_scut"])
      end)

      assert_raise RuntimeError, ~r/which is not a class/, fn -> Loader.load!(root) end
    end
  end

  # ⚠️ Порча разметки — с положительным контролем на нетронутой копии, иначе
  # `assert_raise` зеленел бы и от копии, которая не грузится вовсе.
  #
  # Все три падения защищают одно и то же: запись, которая ВЫГЛЯДИТ фактом и
  # молча не считается. Именно за этим весь файл и заведён.
  describe "загрузчик роняет сборку на битой разметке" do
    test "нетронутая копия грузится, и обе половины в ней есть" do
      ruleset = Loader.load!(copy_rules())["siala_41"]

      # ⚠️ Здесь стояло 8 и 8; стало 9 и 7 замером F7 (16.08.2026):
      # `bardic_knowledge` переехал из непосчитанных в применённые. Стало 11 и 5
      # решением Dan 25.08.2026 (задача 3.92): `Skill focus` и `Epic skill focus`
      # переехали туда же.
      assert length(ruleset.skill_bonuses.applied) == 11

      # ⚠️ А до того здесь стояло 10 — стало 8 замерами F4 и F5 (13.08.2026):
      # у `bullheaded` в листе видно только +1 Will, а прибавка `improved_parry`
      # работает лишь при включённом Парировании, то есть под баффом. Ни та,
      # ни другая не про ЗНАЧЕНИЕ навыка, и обе переехали в `not_a_skill_bonus`.
      assert length(ruleset.skill_bonuses.unmodelled) == 5

      # 🔴 А на ВАНИЛИ их 10 и 6, и это не рассинхрон файла с ruleset'ом,
      # а правило: `epic_skill_focus` объявил, что навык-получателя называет
      # ПИК, и ванильный корпус про выбор навыка у него не знает вовсе
      # (`repeatable` приходит ручным слоем Сиалы). Раз назвать получателя
      # нечем — запись опускается обратно в непосчитанные, и оговорка живёт.
      vanilla = Loader.load!(copy_rules())["vanilla"]

      assert length(vanilla.skill_bonuses.applied) == 10
      assert length(vanilla.skill_bonuses.unmodelled) == 6

      assert Enum.any?(vanilla.skill_bonuses.unmodelled, &(&1.id == :epic_skill_focus))
      assert Enum.any?(vanilla.skill_bonuses.applied, &(&1.id == :skill_focus))
    end

    # ------------------------------------ навык-получатель из выбора (3.92) --

    # 🔴 Четыре сторожа вокруг `skills_from`, и все четыре — про одну ошибку:
    # ДВА ОТВЕТА НА ВОПРОС «кому прибавили». Ни один из них не может быть
    # заменён «разумным умолчанием»: любое умолчание здесь прибавляет число
    # не тому навыку либо не прибавляет вовсе, и оба провала молчаливы.
    test "skills_from на неприменяемой записи роняет сборку" do
      root = copy_rules()

      edit_entry(root, "skill_focus", fn entry ->
        Map.put(entry, "verdict", "not_modelled")
      end)

      assert_raise RuntimeError, ~r/states skills_from on a `not_modelled` record/, fn ->
        Loader.load!(root)
      end
    end

    test "skills_from вместе с названными навыками роняет сборку" do
      root = copy_rules()

      edit_entry(root, "skill_focus", fn entry ->
        Map.put(entry, "skills", ["discipline"])
      end)

      assert_raise RuntimeError, ~r/states skills_from and names skills too/, fn ->
        Loader.load!(root)
      end
    end

    # У класса, навыка и расовой склонности пиков нет вовсе — спрашивать выбор
    # было бы не у кого, и запись молча не дала бы ничего.
    test "skills_from у источника, который не фит, роняет сборку" do
      root = copy_rules()

      edit_entry(root, "skill_focus", fn entry ->
        entry |> Map.delete("feat") |> Map.put("class", "bard")
      end)

      assert_raise RuntimeError, ~r/states skills_from without naming a feat/, fn ->
        Loader.load!(root)
      end
    end

    # Плоское число ложится термом, подписанным именем ФИТА; сумма уровней —
    # термом классов. Выбор навыка со второй формой не сочетается ничем, и
    # «сойдёт» здесь было бы догадкой.
    test "skills_from с величиной не той формы роняет сборку" do
      root = copy_rules()

      edit_entry(root, "skill_focus", fn entry ->
        put_in(entry, ["amount", "kind"], "class_level_sum")
      end)

      assert_raise RuntimeError, ~r/only a flat bonus lands in the term/, fn ->
        Loader.load!(root)
      end
    end

    test "незнакомое значение skills_from роняет сборку" do
      root = copy_rules()

      edit_entry(root, "skill_focus", fn entry ->
        Map.put(entry, "skills_from", "gear_slot")
      end)

      assert_raise RuntimeError, ~r/states skills_from "gear_slot"/, fn ->
        Loader.load!(root)
      end
    end

    # ⚠️ Здесь стояло «applied с формой, которую ядро не считает» и порчей был
    # сам `class_level_sum` — с 16.08.2026 ядро его считает, и форм без читателя
    # не осталось ни одной. Сторож при этом на месте, и проверяется он тем, что
    # у него ЕСТЬ: форма, которой загрузчик не знает вовсе. Обе ветки — про одну
    # ошибку, «величина есть, а посчитать её некому», и обе обязаны ронять
    # сборку, а не давать молчаливый ноль.
    test "applied с формой величины, которой загрузчик не знает" do
      root = copy_rules()

      edit_entry(root, "bardic_knowledge", fn entry ->
        put_in(entry, ["amount", "kind"], "per_class_level")
      end)

      assert_raise RuntimeError, ~r/which this loader does not know/, fn ->
        Loader.load!(root)
      end
    end

    # ⚠️ Сторона капа объявлена данными, а КЛИП живёт в коде — и клипа для записи
    # этого файла у `Rules.Skills` нет: пул +50 собирается из вещей и расового
    # бонуса шарда, а прибавка фита кладётся поверх среза. Значит запись,
    # объявившая себя внутрикапной, прошла бы потолок молча.
    test "applied внутри капа +50 — сторож вместо реализации" do
      root = copy_rules()

      edit_entry(root, "alertness", fn entry ->
        put_in(entry, ["cap", "inside_cap"], true)
      end)

      assert_raise RuntimeError, ~r/claims to be inside stat_caps.skill_bonus/, fn ->
        Loader.load!(root)
      end
    end

    # И обратная половина того же контракта: applied БЕЗ стороны капа тоже
    # роняет сборку — у вопроса «внутри или снаружи» нет нейтрального ответа.
    test "applied без объявленной стороны капа" do
      root = copy_rules()

      edit_entry(root, "alertness", &Map.delete(&1, "cap"))

      assert_raise RuntimeError, ~r/does not state which side/, fn -> Loader.load!(root) end
    end

    test "имя несуществующего навыка" do
      root = copy_rules()

      edit_entry(root, "alertness", &Map.put(&1, "skills", ["listen", "not_a_skill"]))

      assert_raise RuntimeError, ~r/not_a_skill/, fn -> Loader.load!(root) end
    end
  end

  describe "разведка записана целиком" do
    # Сплошной проход по 299 записям стоил заметно дороже, чем его результат
    # весит в файле. Эти числа — чтобы следующий не начинал с нуля и чтобы
    # молчаливая пропажа записи была видна.
    test "итоги прохода совпадают с содержимым" do
      by_verdict = Enum.frequencies_by(entries(), & &1["verdict"])

      assert @markup["_sweep"]["found"] == length(entries())
      assert @markup["_sweep"]["by_verdict"] == Map.new(by_verdict, fn {k, v} -> {k, v} end)

      # ⚠️ 8/8 → 9/7 замером F7 (16.08.2026): `bardic_knowledge` стал применённым.
      assert by_verdict == %{
               "applied" => 11,
               "counted_elsewhere" => 9,
               "not_modelled" => 5,
               "not_a_skill_bonus" => 8
             }
    end
  end

  # Воин 6 + Арфист-скаут 3 с 4 рангами Знания и INT 10 — билд, на котором дыра
  # и была измерена: уровней барда в нём нет вовсе, поэтому вся разница между
  # ruleset'ами приходится ровно на прибавку Арфиста.
  defp harper_lore do
    Build.new(
      race: :human,
      levels: List.duplicate(:fighter, 6) ++ List.duplicate(:harper_scout, 3),
      skills: %{1 => %{lore: 4}}
    )
  end

  # Полная копия `priv/rules`, чтобы `load!/1` видел всё как обычно и отличался
  # только испорченный файл.
  defp copy_rules do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp edit_entry(root, feat, fun) do
    edit_json(root, "vanilla/feat_skill_bonuses.json", "bonuses", "feat", feat, fun)
  end

  defp edit_skill(root, skill, fun) do
    edit_json(root, "siala_41/skills.json", "skills", "id", skill, fun)
  end

  defp edit_json(root, file, collection, key, id, fun) do
    path = Path.join(root, file)
    data = path |> File.read!() |> Jason.decode!()

    entries =
      Enum.map(data[collection], fn entry ->
        if entry[key] == id, do: fun.(entry), else: entry
      end)

    File.write!(path, Jason.encode!(Map.put(data, collection, entries)))
  end
end
