defmodule BuildCalculator.DataTest do
  @moduledoc """
  The ruleset loader: layering, configuration-not-constants, and honest gaps.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Abilities
  alias BuildCalculator.Rules.Build

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  describe "versions" do
    test "both layers are compiled in" do
      assert Enum.sort(Data.versions()) == ["siala_41", "vanilla"]
      assert Data.default_version() == "siala_41"
    end

    test "an unknown version is an error, not a crash" do
      assert Data.ruleset("nwn_ee") == {:error, {:unknown_ruleset, "nwn_ee"}}
      assert_raise ArgumentError, fn -> Data.ruleset!("nwn_ee") end
    end

    test "the shard layer sits on top of vanilla", %{siala: siala, vanilla: vanilla} do
      assert vanilla.layers == ["vanilla"]
      assert siala.layers == ["vanilla", "siala_41"]
    end
  end

  describe "configuration rather than constants" do
    # source: siala_41/overrides.json (wiki "41-ый уровень" revid 20387, and
    # max_classes from Dan). Both differ from vanilla, which is the whole point
    # of them living in data.
    test "cap and class limit differ per ruleset", %{siala: siala, vanilla: vanilla} do
      assert siala.level_cap == 41
      assert siala.max_classes == 4
      assert vanilla.level_cap == 40
      assert vanilla.max_classes == nil
    end

    test "the epic threshold comes from epic.json", %{siala: siala} do
      assert siala.epic_starts_at == 21
      assert siala.epic.class_levels_count_up_to == 20
    end

    # source: siala_41/overrides.json `epic.spell_selection_at_41` («На 41-м
    # уровне нельзя выбирать заклинания», wiki «41-ый уровень» revid 20387,
    # `verified`). Both directions matter: vanilla states no such rule, and an
    # absent statement is not a prohibition — so its flag has to be `true`
    # rather than merely falsy.
    test "the shard's ban on choosing spells at the cap is a flag, not a literal", %{
      siala: siala,
      vanilla: vanilla
    } do
      refute siala.epic.spell_selection_at_level_cap?
      assert vanilla.epic.spell_selection_at_level_cap?
    end
  end

  describe "reference data" do
    test "classes carry a progression row per class level", %{vanilla: ruleset} do
      fighter = ruleset.classes[:fighter]

      assert fighter.hit_die == 10
      assert fighter.skill_points == 2
      assert map_size(fighter.progression) == 20
      assert fighter.progression[20] == %{bab: 20, fort: 12, ref: 6, will: 6}
    end

    # Задача 3.37. Двадцать два класса называют хит-дайс одним числом, двадцать
    # третий — колонкой на каждой строке своей таблицы прогрессии, потому что
    # у него дайс растёт. Оба поля лежат в ВАНИЛЬНОМ слое: шкалу печатает
    # `fandom:Red dragon disciple`, а замер Dan (`GAME_CHECKS.md` G2) говорит,
    # что шард её не трогал, — значит правка чинит оба ruleset'а разом, и
    # проверяется это тоже на обоих.
    test "растущий хит-дайс лежит шкалой по уровням класса", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala] do
        rdd = ruleset.classes[:red_dragon_disciple]

        # Лейбл страницы — диапазон («d6 to d12»), числом он не стал и не должен.
        assert rdd.hit_die == nil

        assert rdd.hit_die_by_class_level == [
                 %{from: 1, die: 6},
                 %{from: 4, die: 8},
                 %{from: 6, die: 10},
                 %{from: 11, die: 12}
               ]

        # ...и ровно один класс во всём корпусе такой.
        growing = for {id, c} <- ruleset.classes, c.hit_die_by_class_level, do: id
        assert growing == [:red_dragon_disciple]
      end
    end

    test "feats carry the bonus_for list the slot model needs", %{vanilla: ruleset} do
      assert MapSet.member?(ruleset.feats[:power_attack].bonus_for, :fighter)
      assert ruleset.feats[:epic_toughness].epic?
      refute ruleset.feats[:power_attack].epic?
    end

    test "races carry ability modifiers and the human's extras", %{vanilla: ruleset} do
      assert ruleset.races[:dwarf].ability_modifiers == %{con: 2, cha: -2}
      assert ruleset.races[:human].bonus_skill_points == %{level: 1, per_level: 1, extra: 4}
      assert ruleset.races[:human].extra_feats == %{level: 1, count: 1}
    end

    # source: CLAUDE.md §4 — the shard rebuilt the races rather than translating
    # them, so its name is the primary one. Watch the collision: Гном is Dwarf.
    test "the shard layer supplies the Siala race names", %{siala: siala, vanilla: vanilla} do
      assert siala.races[:dwarf].ru == "Гном"
      assert siala.races[:gnome].ru == "Карлик"
      assert siala.races[:halfling].ru == "Гоблин"
      assert vanilla.races[:dwarf].ru == nil
    end

    test "class skills are populated for every class", %{siala: ruleset} do
      assert Enum.all?(ruleset.classes, fn {_id, class} ->
               MapSet.size(class.class_skills) > 0
             end)
    end
  end

  describe "derived tables" do
    # The loader cross-checks the "character_level + 3" formula against the
    # tabulated epic rows in epic.json at compile time, so this only pins the
    # bounds the table itself does not reach.
    test "skill rank caps cover every level up to the cap", %{siala: ruleset} do
      assert map_size(ruleset.skill_rank_caps) == 41
      assert ruleset.skill_rank_caps[1] == %{class: 4, cross_class: 2}
      assert ruleset.skill_rank_caps[41] == %{class: 44, cross_class: 22}
    end

    # source: fandom "Attacks per round" revid 52042
    test "the attacks-per-round table matches the wiki column", %{siala: ruleset} do
      for {bab, attacks} <- [{0, 1}, {5, 1}, {6, 2}, {10, 2}, {11, 3}, {15, 3}, {16, 4}, {20, 4}] do
        assert ruleset.attacks_per_round[bab] == attacks, "BAB #{bab}"
      end
    end
  end

  # ⚠️ Шкала читается по ПОСЛЕДНЕЙ подошедшей ступени, поэтому её порядок —
  # это её смысл: ступени вразнобой или начало не с первого уровня класса
  # молча назначили бы какому-то уровню чужой дайс. Такую шкалу загрузчик
  # обязан не «починить», а уронить сборку — снапшот машинный, и человек
  # читает его глазами один раз.
  describe "битая шкала хит-дайса роняет сборку" do
    test "ступени не по возрастанию" do
      assert_raise RuntimeError, ~r/steps are/, fn ->
        load_with_scale([
          %{"from" => 1, "die" => 6},
          %{"from" => 11, "die" => 12},
          %{"from" => 6, "die" => 10}
        ])
      end
    end

    test "шкала начинается не с первого уровня класса" do
      assert_raise RuntimeError, ~r/starts at class level 4/, fn ->
        load_with_scale([%{"from" => 4, "die" => 8}])
      end
    end

    test "ступень не пара «уровень + число граней»" do
      assert_raise RuntimeError, ~r/is not/, fn ->
        load_with_scale([%{"from" => 1, "die" => "d6"}])
      end
    end

    # Положительный контроль: та же машинерия с ПРАВИЛЬНОЙ шкалой грузится,
    # иначе три `assert_raise` выше зеленели бы и у загрузчика, который
    # падает на чём угодно.
    test "правильная шкала грузится" do
      ruleset = load_with_scale([%{"from" => 1, "die" => 6}, %{"from" => 4, "die" => 8}])

      assert ruleset.classes[:red_dragon_disciple].hit_die_by_class_level == [
               %{from: 1, die: 6},
               %{from: 4, die: 8}
             ]
    end

    defp load_with_scale(steps) do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      path = Path.join([root, "vanilla", "classes.json"])
      classes = path |> File.read!() |> Jason.decode!()

      patched =
        Enum.map(classes, fn class ->
          if class["id"] == "red_dragon_disciple",
            do: Map.put(class, "hit_die_by_class_level", steps),
            else: class
        end)

      File.write!(path, Jason.encode!(patched))

      Loader.load!(root)["siala_41"]
    end
  end

  # ⚠️ Шард может переписать хит-дайс одним числом (`what: "hit_die"`), и над
  # РАСТУЩИМ дайсом это утверждение неоднозначно: заменить всю шкалу или
  # подвинуть одну ступень? Выбирать за источник загрузчик не имеет права
  # (CLAUDE.md §3), поэтому такая запись не применяется, а становится видимым
  # гэпом. Записи такой сегодня нет ни в одном слое — форма проверяется
  # на подложенной.
  describe "одно число поверх шкалы не применяется молча" do
    test "у класса со шкалой правка уезжает в гэп, а шкала остаётся" do
      ruleset = with_hit_die_change("red_dragon_disciple")
      rdd = ruleset.classes[:red_dragon_disciple]

      assert {:not_modelled, {:class_change, :red_dragon_disciple, "hit_die"}} in ruleset.gaps
      assert rdd.hit_die == nil
      assert hd(rdd.hit_die_by_class_level) == %{from: 1, die: 6}
    end

    # Положительный контроль: у класса БЕЗ шкалы та же самая запись
    # применяется — иначе тест выше зеленел бы и у загрузчика, который
    # перестал понимать `hit_die` вовсе.
    test "у класса с одним числом та же правка применяется" do
      ruleset = with_hit_die_change("fighter")

      assert ruleset.classes[:fighter].hit_die == 7
      refute {:not_modelled, {:class_change, :fighter, "hit_die"}} in ruleset.gaps
    end

    defp with_hit_die_change(class_id) do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      path = Path.join([root, "siala_41", "classes.json"])
      data = path |> File.read!() |> Jason.decode!()

      change = %{
        "what" => "hit_die",
        "value" => 7,
        "status" => "verified",
        "quote" => "фикстура теста, не факт вики",
        "source" => %{"kind" => "user", "who" => "тест"}
      }

      classes =
        Enum.map(data["classes"], fn class ->
          if class["id"] == class_id,
            do: Map.put(class, "changes", (class["changes"] || []) ++ [change]),
            else: class
        end)

      File.write!(path, Jason.encode!(Map.put(data, "classes", classes)))

      Loader.load!(root)["siala_41"]
    end
  end

  describe "gaps" do
    test "record what is missing, derived or assumed", %{siala: ruleset} do
      # ⚠️ Здесь первой строкой стояло `{:missing_data, {:hit_die,
      # :red_dragon_disciple}}` — «дайс растёт, значит числа нет». Снято задачей
      # 3.37: шкала прочитана, а форма гэпа осталась на случай, когда снапшот
      # потеряет оба поля разом. Проверяется теперь ОТСУТСТВИЕ — и не по одному
      # классу, а по всем: «ни у одного класса нет хит-дайса» — это то, что
      # правка обязана была сделать, и то, что она может тихо откатить.
      refute Enum.any?(ruleset.gaps, &match?({:missing_data, {:hit_die, _}}, &1))
      # class-skill membership is reconciled from two independent wiki sources
      assert {:derived, :class_skills, :union_of_class_and_skill_pages} in ruleset.gaps
      # base AC is a universal constant, cited off `_vanilla_constants_confirmed`
      # (task 3.49, 18.08.2026) — the caveat stays (10 is still a modelling
      # choice worth naming), but it now names `fandom:Armor class` rather than
      # claiming no page states it.
      assert {:assumed, :base_ac, 10, "fandom:Armor class"} in ruleset.gaps
      # ⚠️ Здесь стояло `assert {:not_modelled, :metamagic} in ruleset.gaps`
      # с комментарием «one piece of spellcasting has no table in the data at
      # all». Снято 22.08.2026 решением Dan (задача 3.80): «метамагию можно
      # закрыть, конструктора не касается».
      #
      # 🔴 И комментарий был неверен по СУТИ, а не только устарел: дело
      # не в отсутствии таблицы. Девять фитов метамагии смоделированы целиком,
      # с требованиями; не считается эффект, а он выбирается при подготовке
      # или в бою — не при левелапе. Таблица бы тут ничего не изменила.
      refute {:not_modelled, :metamagic} in ruleset.gaps

      # ⚠️ Первой из этой пары стояла `{:not_modelled, :cleric_domains}` —
      # «домены записываем, но что они дают, не считаем». Снята 22.08.2026
      # решением Dan (задача 3.79): активные умения доменов — баффы, пассивные
      # калькулятор не считает вовсе, а заклинания домена ВЫДАЮТСЯ, то есть
      # выбирать нечего. Проверяется теперь ОТСУТСТВИЕ, как у двух соседей
      # выше и ниже, — вернуться такой пункт может только молча.
      # ⚠️ Положительный контроль на то, что ушло признание, а не механика,
      # стоит там, где живёт сама механика: `ClassChoicesTest`, «гэп снят,
      # а выбор двух доменов остался обязательным».
      refute {:not_modelled, :cleric_domains} in ruleset.gaps
      # ⚠️ Третьей строкой здесь стояло `{:not_modelled,
      # :bonus_spell_slots_from_ability}`. Снято задачей 3.70 (21.08.2026):
      # таблица бонусных слотов за высокую характеристику каста перенесена
      # в `vanilla/spellcasting.json` и считается. Проверяется теперь
      # ОТСУТСТВИЕ — ровно то, что правка обязана была сделать и что она
      # может тихо откатить; форма гэпа при этом жива, но проверяемая
      # (`{:missing_data, :bonus_spell_slots}`, см. `SpellcastingTest`).
      refute {:not_modelled, :bonus_spell_slots_from_ability} in ruleset.gaps
      refute {:missing_data, :bonus_spell_slots} in ruleset.gaps

      # ⚠️ Здесь стояло `assert` с комментарием «six spells write their circle
      # as patch history, not a number». **Снято 21.08.2026 решением Dan**
      # (задача 3.71): у всех шести стоит слово `epic`, то есть источник
      # не грязный, а правдив — круга у эпического заклинания не бывает, — и все
      # шесть берутся ФИТАМИ, которые в справочнике есть. Dan: «все эпические
      # заклинания в игре — одноразовые раз в сон, слоты обычных кругов
      # не тратят». Проверяется теперь ОТСУТСТВИЕ: пункт был переучётом
      # в баннере, и вернуться он может только молча.
      refute Enum.any?(ruleset.gaps, &match?({:missing_data, {:spell_circles, _}}, &1))
    end

    # A ceiling becomes a rule only with a `verified` status a human put there,
    # and stays a gap otherwise. All five crossed that line on 03.08.2026 — the
    # 127 skill value and the dodge +20 by the player's word, the general AC
    # ceiling by his decision that there is none.
    #
    # ⚠️ That leaves no ceiling to hold as a positive control here, and a bare
    # `refute` goes green just as readily when the mechanism breaks. Two things
    # stand in its place: the assertions below fail if a ceiling stops being
    # carried at all, and `siala_skill_layer_test.exs` demotes one to `unclear`
    # in a copy of `priv/rules` and asserts its gap comes back — the mechanism is
    # exercised there rather than assumed here.
    test "a ceiling is a rule only once a human has verified it", %{siala: ruleset} do
      for form <- [:ac, :max_skill_value, :attack_bonus, :dodge_ac] do
        refute {:missing_data, {:stat_cap, form}} in ruleset.gaps
      end

      assert ruleset.stat_caps.max_skill_value == 127
      assert ruleset.stat_caps.dodge_ac == 20
      # «no general ceiling» is a decision, so it is an absence of a number and
      # not an absence of an answer
      assert ruleset.gear.ac_cap == nil
      # and what is left of the item side of the caps is still something the
      # player has to be told. ⚠️ Форму сужали ДВАЖДЫ, и оба раза с
      # переименованием — имя, переросшее свой смысл, это и есть тихо устаревшая
      # справка. 09.08.2026 (задача 3.20) отделилась половина про навыки;
      # 10.08.2026 (задача 3.5, часть B) ушла половина про атаку с ОРУЖИЯ — она
      # вводится и в кап +20 входит. Осталось то, чего поля нет вовсе: бонус
      # к атаке с других предметов, баффы, песня барда.
      #
      # ⚠️ **Третье сужение — до нуля, 21.08.2026 (задача 3.71).** Из трёх
      # оставшихся вещей две (баффы и песня барда) Dan вывел из области ответа
      # ещё 10.08.2026, а §9 запрещает такому быть гэпом вовсе; третью снял
      # он же: «бонуса к атаке с прочих вещей я не припоминаю, мы уже учитываем
      # всё что надо». Форма удалена вместе с русской подписью — ровно так же,
      # как ниже поступили со штрафом брони.
      refute {:not_modelled, :attack_bonus_outside_weapon} in ruleset.gaps
      refute {:not_modelled, :item_attack_and_skill_bonuses} in ruleset.gaps
      refute {:not_modelled, :item_attack_bonus} in ruleset.gaps

      # ⚠️ Штраф брони стоял здесь `assert`'ом рядом с атакой, и это была вторая
      # половина той же мысли: «предметов у нас нет, значит и штрафа не знаем».
      # Половины разошлись 16.08.2026 (задача 3.42) — доспех и щит стали
      # предметами (3.41), штраф считается термом значения навыка, и форма
      # снята. `refute` вместо удаления строки: он ловит возврат оговорки
      # к посчитанному, а такой возврат уже случался в этом проекте.
      refute {:not_modelled, :armor_check_penalty} in ruleset.gaps
    end

    # ⚠️ Гэп снят 03.08.2026: правило измерено в игре (Dan, тестовый сервер,
    # `source: user`) и применяется. Раньше здесь стоял `assert` — Fandom давал
    # один пример соркерера и общего правила не давал, поэтому число лежало
    # мёртвым. Замер покрыл все семь классов и обе расы со штрафом.
    #
    # Правило живёт ВНУТРИ таблицы поинт-бая: пол списывается из того же
    # бюджета, и пола без бюджета не бывает. Обе секции — `_vanilla_constants_
    # confirmed`, поэтому их видят оба ruleset'а.
    test "the caster point-buy floor is carried, not extrapolated", %{
      siala: siala,
      vanilla: vanilla
    } do
      for ruleset <- [siala, vanilla] do
        refute {:missing_data, :caster_minimum_ability} in ruleset.gaps
        refute {:missing_data, :point_buy_costs} in ruleset.gaps

        assert ruleset.point_buy.caster_minimum == %{
                 value: 11,
                 applies_to: :final_score,
                 applies_when: :first_class_level
               }
      end
    end

    # ⚠️ Положительный контроль к `refute` выше. Оба ruleset'а правило несут,
    # значит гэпа не поднимает никто — а набор `refute` на умершем механизме
    # зеленеет от начала до конца. Поэтому статус понижается здесь, в копии
    # `priv/rules`, и гэп обязан вернуться вместе с исчезновением пола.
    test "понижение статуса возвращает гэп и убирает пол" do
      ruleset = with_override(fn entry -> Map.put(entry, "status", "unclear") end)

      assert {:missing_data, :caster_minimum_ability} in ruleset.gaps
      assert ruleset.point_buy.caster_minimum == nil

      assert Abilities.creation_floor(Build.new(race: :human, levels: [:sorcerer]), ruleset) ==
               nil

      # ...а таблица цен рядом цела: механизм по-записный, а не «всё или ничего»
      assert ruleset.point_buy.budget == 30
      refute {:missing_data, :point_buy_costs} in ruleset.gaps
    end

    # Схема выражает ровно два слова, и оба — те, что ядро действительно умеет.
    # Запись, говорящая, что минимум применяется к чему-то ещё, — это правило,
    # которого у нас нет; половина правила, применённая молча, и есть то, против
    # чего выстроен весь загрузчик.
    test "незнакомая формулировка правилом не становится" do
      ruleset = with_override(fn entry -> Map.put(entry, "applies_to", "purchased_score") end)

      assert {:missing_data, :caster_minimum_ability} in ruleset.gaps
      assert ruleset.point_buy.caster_minimum == nil
    end

    defp with_override(change) do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      path = Path.join([root, "siala_41", "overrides.json"])
      overrides = path |> File.read!() |> Jason.decode!()

      patched =
        update_in(
          overrides["_vanilla_constants_confirmed"]["caster_minimum_ability"],
          change
        )

      File.write!(path, Jason.encode!(patched))

      Loader.load!(root)["siala_41"]
    end

    # Every vanilla requirement block now reads into structure, so nothing is
    # flagged as prose any more — but the parts the schema cannot carry are
    # flagged one by one, under the wiki's own label, and a class is checked on
    # the rest rather than on nothing.
    #
    # ⚠️ Since 03.08.2026 nothing is left unread at all. Shifter was the last one,
    # and it closed on an observation rather than on a page: a druid 5 with WIS 12
    # casts two circles, not three, and the game offers him the class anyway — so
    # the line cannot be about casting third-circle spells, and `wild shape`
    # already forces the five druid levels that satisfy it either way.
    #
    # ⚠️ That takes away the positive control this test used to carry, and an
    # empty `refute` is exactly the shape that goes green when the mechanism is
    # broken. Two things stand in its place: the loop below fails on any class
    # that grows an unread key, and `class_requirements_test.exs` deletes the
    # hand-written file from a copy of `priv/rules` and asserts the gaps come
    # back — the mechanism is exercised there, not assumed here.
    test "no class requirement is left unread, and none is swallowed", %{siala: ruleset} do
      refute Enum.any?(ruleset.gaps, &match?({:missing_data, {:class_requirements, _}}, &1))
      refute Enum.any?(ruleset.gaps, &match?({:missing_data, {:requirement, _, _}}, &1))

      for {id, class} <- ruleset.classes do
        assert class.requirements_unsupported == [],
               "#{id} carries unread requirements #{inspect(class.requirements_unsupported)}. " <>
                 "Read them into vanilla/class_requirements.json, or record there why they " <>
                 "cannot be read — an unread key must never simply vanish."
      end

      assert ruleset.classes[:shifter].requirements[:feats] == ["alertness", "wild_shape"]
    end

    # The other half of the same idea: a requirement whose meaning is in the
    # page's prose is read by a human into `vanilla/class_requirements.json` and
    # checked like any other. Before that, Pale Master's whole requirement block
    # was a gap and the class could be taken at character level 1.
    #
    # source: fandom "Pale master" revid 71581 — «The spellcasting requirement
    # refers to the caster level required, not the level of spell that can be
    # cast. Three levels of bard, sorcerer, or wizard fulfills this requirement.»
    # source: fandom "Red dragon disciple" revid 71919 — «Class: bard or sorcerer»
    for version <- ["vanilla", "siala_41"] do
      test "prose requirements read by hand are checked, not reported (#{version})" do
        ruleset = Data.ruleset!(unquote(version))

        refute {:missing_data, {:requirement, :pale_master, "arcane_spellcasting"}} in ruleset.gaps
        refute {:missing_data, {:requirement, :red_dragon_disciple, "unparsed"}} in ruleset.gaps
        refute {:missing_data, {:requirement, :arcane_archer, "spellcasting"}} in ruleset.gaps

        assert ruleset.classes[:pale_master].requirements[:any_of] == [
                 %{"class_levels" => %{"bard" => 3}},
                 %{"class_levels" => %{"sorcerer" => 3}},
                 %{"class_levels" => %{"wizard" => 3}}
               ]

        # the readable half of the block is untouched by the merge
        assert ruleset.classes[:red_dragon_disciple].requirements[:skills] == %{"lore" => 8}

        # ⚠️ Здесь стояло `assert … requirements[:qualifiers] == ["(longbow or
        # shortbow)"]` для ОБОИХ ruleset'ов с доводом «оружие не моделируется
        # до армори». Довод верен только для ванили и устарел для Сиалы
        # 17.08.2026: ответ Dan назвал требование поимённо (Weapon Focus на одно
        # из четырёх дальнобойных), а домен `weapon` получил справочник ещё
        # задачей 3.5 — то есть на Сиале это уже не оговорка, а проверка
        # (`feat_choices`, `Rules.Prereqs`).
        #
        # Ванильная половина осталась оговоркой намеренно: её список — два лука,
        # это ванильный факт, и переписывать его вслед за сиальским значило бы
        # протащить правило шарда в ваниль.
        assert ruleset.classes[:arcane_archer].requirements[:qualifiers] ==
                 if(unquote(version) == "vanilla", do: ["(longbow or shortbow)"])

        assert "weapon_focus" in ruleset.classes[:arcane_archer].requirements[:feats]
      end
    end

    # ⚠️ Здесь стояло `assert Enum.any?(ruleset.gaps, &match?({:not_modelled,
    # {:class_change, _, _}}, &1))` — «хоть один факт класса доезжает до списка
    # неточностей». С 24.08.2026 (задача 3.85) таких фактов НЕТ НИ ОДНОГО:
    # последние две записи (`bonus_feat_pool` Чемпиона Торма и Рейнджера)
    # применены по замерам U1 и U2. Утверждать прежнее — значит требовать
    # от данных недостачи.
    #
    # Проверяется поэтому ровно то, ради чего тест заводился: механизм жив
    # и назвал бы факт, у которого нет механического дома. Ноль — утверждение
    # (`== []`), а не отсутствие строки: он обязан поймать возврат гэпа.
    test "shard class changes with no mechanical home are listed — сегодня их ноль",
         %{siala: ruleset} do
      assert for({:not_modelled, {:class_change, id, what}} <- ruleset.gaps, do: {id, what}) == []

      # Положительный контроль: беспризорные факты у классов ЕСТЬ (79 штук),
      # просто ни один не про наши числа — то есть ноль выше про фильтр
      # получателей, а не про опустевшие данные.
      # ⚠️ 80 → 79 (задача 3.101, 25.08.2026): у Тайного лучника получил
      # механический дом факт `class_ability_weapons` («Все классовые умения
      # теперь распространяются на малый и большие арбалеты»). До этой задачи
      # он был не «не наш», а РАНО: единственное умение класса, падающее в наше
      # число, само стояло `not_modelled`.
      assert Enum.sum_by(Map.values(ruleset.classes), &length(&1.siala_unapplied)) == 79
    end

    # AGENT_QUEUE.md §1.10 шаг 3: `arcane_archer` — единственный класс, где Сиала
    # прямо высказалась про владения («Оружие и Доспехи: Простое оружие, Легкая
    # и Средняя броня, Щиты» — воинское оружие убрано по сравнению с ванилью).
    # У `apply_change/2` сегодня нет обработчика `"proficiencies"`, так что этот
    # факт НЕ применяется — и он лежит непрочитанным на виду.
    #
    # ⚠️ Здесь стояло `assert {:not_modelled, {:class_change, :arcane_archer,
    # "proficiencies"}} in siala.gaps` — «молчать он не имеет права». Задача 3.28
    # (решение Dan 10.08.2026) это пересмотрела: гэп — дырка в нашем ОТВЕТЕ,
    # а владение оружием и бронёй калькулятор не считает вовсе, поэтому факт
    # помечен `affects: ["weapon_armor_proficiency"]` и в список неточностей
    # не идёт. Проверяется теперь то же самое, но по данным: факт прочитан,
    # не применён и назвал своего получателя. Исчезни он из данных — тест упадёт
    # так же, как падал раньше.
    test "arcane_archer proficiency override has no handler yet, and says which receiver", %{
      siala: siala,
      vanilla: vanilla
    } do
      fact =
        Enum.find(siala.classes[:arcane_archer].siala_unapplied, &(&1["what"] == "proficiencies"))

      assert fact["affects"] == ["weapon_armor_proficiency"]
      refute {:not_modelled, {:class_change, :arcane_archer, "proficiencies"}} in siala.gaps

      # ⚠️ Здесь положительным контролем был гэп `extra_attacks` того же класса
      # («гэпы этой формы у этого же класса живы»). Задача 3.72 его сняла:
      # правило посчитано, и у Тайного лучника не осталось ни одного гэпа
      # этой формы. Контроль поэтому раздвоен, и обе половины нужны:
      #
      #   * форма жива вообще — иначе `refute` выше зеленел бы на пустом
      #     списке;
      #   * запись `extra_attacks` НЕ пропала из данных, а переехала
      #     в применённые. «Гэпа нет, потому что посчитали» и «гэпа нет,
      #     потому что факт потеряли» выглядят одинаково, и различить их
      #     может только это.
      # ⚠️ Первая половина контроля («форма жива вообще») снята 24.08.2026,
      # задача 3.85: гэпов этой формы не осталось ни одного — обе записи
      # `bonus_feat_pool` применены по замерам. Замена ей — соседний тест
      # «shard class changes with no mechanical home are listed», где ноль
      # утверждается явно и с собственным контролем; дублировать его здесь
      # значило бы держать две копии одного утверждения.
      #
      # Вторая половина работает и осталась главной: запись `extra_attacks`
      # НЕ пропала из данных, а переехала в применённые. «Гэпа нет, потому
      # что посчитали» и «гэпа нет, потому что факт потеряли» выглядят
      # одинаково, и различить их может только это.
      assert Enum.any?(
               siala.classes[:arcane_archer].siala_changes,
               &(&1["what"] == "extra_attacks")
             )

      refute Enum.any?(
               siala.classes[:arcane_archer].siala_unapplied,
               &(&1["what"] == "extra_attacks")
             )

      assert [%{source: {:class, :arcane_archer}}] = siala.attack_modifiers

      # ⚠️ Здесь стояло `assert :weapon_proficiency_martial in
      # siala.classes[:arcane_archer].granted_feats[1]` — «обработчика нет,
      # поэтому класс несёт ванильный список, воинское оружие включительно».
      # Волна 13 (09.08.2026) это ОБЕССМЫСЛИЛА, и по другой причине, чем чинила
      # бы задача 1.10: замер H5 выключил ванильные владения оружием у всех
      # (`GAME_CHECKS.md`), а выключенный фит не выдаётся никем — значит
      # `martial` ушёл из выдачи Лучника не потому, что его сняли по требованию
      # источника, а потому, что его больше нет ни у кого.
      #
      # Гэп при этом остаётся ПРАВДОЙ, и утверждение у него ровно одно:
      # обработчика `"proficiencies"` нет, то есть шардовое перечисление
      # («Простое оружие, Легкая и Средняя броня, Щиты») ни на что не влияет.
      # ⚠️ Но указывать на неверное число он перестал: единственное расхождение
      # с ванилью, которое эта фраза называла, — как раз воинское оружие, а
      # броня и щиты совпадают (сказано и в примечании самой записи).
      refute :weapon_proficiency_martial in siala.classes[:arcane_archer].granted_feats[1]
      assert :weapon_proficiency_martial in vanilla.classes[:arcane_archer].granted_feats[1]

      # Остальное перечисление шарда сходится с тем, что класс несёт, — то есть
      # неприменённый факт сегодня ничего не искажает.
      granted = siala.classes[:arcane_archer].granted_feats[1]
      assert :armor_proficiency_light in granted
      assert :armor_proficiency_medium in granted
      assert :shield_proficiency in granted
      refute :armor_proficiency_heavy in granted
    end

    # AGENT_QUEUE.md §1.10 шаг 3: до правки `armor_proficiency_heavy` ложно
    # отказывала Чемпиону Торма прерогативой «нет Light/Medium» — вики прямо
    # разрешает взять его бонусным фитом (`bonus_for == ["champion_of_torm"]`),
    # но ни один слой данных не знал, что класс владеет Light и Medium.
    # Проверено вызовом ядра (`Rules.validate_feat/3`), не по сырому полю.
    test "champion_of_torm no longer falsely refuses its own bonus feat (Armor proficiency heavy)",
         %{siala: siala} do
      build =
        Build.new(alignment: :lawful_good, race: :human) |> Build.add_level(:champion_of_torm)

      assert Rules.validate_feat(build, :armor_proficiency_heavy, siala) == :ok
    end

    # Второй случай того же Источника 2: "all [[armor]]" — прозаическая ссылка
    # на общую статью «Armor», не на конкретный фит, поэтому сама по себе не
    # резолвится ни в один ярус. Всё, чем сегодня владеют dwarven_defender
    # и blackguard, пришло со страниц самих фитов (Источник 3, `granted_by`) —
    # без него оба класса остались бы вовсе без брони и щита.
    test "dwarven_defender and blackguard own every armor tier despite \"all [[armor]]\" prose",
         %{siala: siala} do
      for class_id <- [:dwarven_defender, :blackguard] do
        granted = siala.classes[class_id].granted_feats[1]

        for tier <- [
              :armor_proficiency_light,
              :armor_proficiency_medium,
              :armor_proficiency_heavy,
              :shield_proficiency
            ] do
          assert tier in granted, "#{class_id} missing #{tier}"
        end
      end
    end

    # Источник 1 (запреты, задача 1.10 шаг 2) и Источники 2/3 (выдача, шаг 3)
    # читают вики независимо и не обязаны соглашаться — если бы класс запрещал
    # общему слоту фит, который сам же выдаёт даром, это было бы противоречием
    # вики самой себе. Проверено по ВСЕЙ выборке (23 класса × оба ruleset'а),
    # а не по паре примеров — see also AGENT_QUEUE.md §1.10, «противоречие
    # вики самой себе».
    #
    # ⚠️ Источник 4 (AGENT_QUEUE.md §1.10, «Источник 4») переворачивает этот
    # довод для РОВНО трёх пар — и легально, не как противоречие. Страница
    # самого фита говорит «выдаёт» и «запрещает» ОДНИМ предложением: «Since
    # monks receive this feat automatically, it cannot be selected when
    # gaining a monk level (even prior to level 6)». Это не два источника,
    # разошедшихся между собой, а один источник, объявивший оба факта сразу —
    # класс дарит фит на одном уровне и не даёт купить его слотом ни на каком.
    # Четвёртая пара источника 4 (`blinding_speed` × `harper_scout`) в выдаче
    # Арфиста не участвует вовсе (страница ничего не грантует) и здесь не
    # всплывает.
    # 🔴 ВТОРОЙ ЗАКОННЫЙ СЛУЧАЙ, и половины у него с РАЗНЫХ вики (задача 3.112,
    # 26.08.2026). Fandom запрещает druid/pale_master/shifter брать
    # `weapon_proficiency_simple` слотом; Сиала выдаёт этот фит даром всем
    # 23 классам. Спора тут нет — это ровно та же форма, что у монаха с
    # `knockdown` («получает даром и потому не выбирает»), просто утверждения
    # приехали из двух источников, а не из одного предложения.
    #
    # ⚠️ И запрет НЕ снят: Dan сказал «выдаётся всем», а не «druid может купить
    # его слотом», а выдумывать второе из первого запрещено (CLAUDE.md §3).
    # Поэтому ожидание стало ПОРУЛЬСЕТНЫМ: на ванили тех же трёх классов в
    # пересечении нет вовсе (там фит им никто не выдаёт), и одно общее ожидание
    # на два ruleset'а спрятало бы разницу.
    #
    # ⚠️ Классов ровно три, а не 23: `weapon_proficiency_simple` запрещают себе
    # только druid, pale_master и shifter, у остальных двадцати пересечение
    # пустое — выдача сама по себе в него не попадает.
    test "no class both forbids and grants the same feat — except where a feat's own page says both on purpose",
         %{siala: siala, vanilla: vanilla} do
      granted_to_everyone = MapSet.new([:weapon_proficiency_simple])

      expected = %{
        {"vanilla", :monk} => MapSet.new([:knockdown, :improved_knockdown]),
        {"vanilla", :ranger} => MapSet.new([:improved_two_weapon_fighting]),
        {"siala_41", :monk} => MapSet.new([:knockdown, :improved_knockdown]),
        {"siala_41", :ranger} => MapSet.new([:improved_two_weapon_fighting]),
        {"siala_41", :druid} => granted_to_everyone,
        {"siala_41", :pale_master} => granted_to_everyone,
        {"siala_41", :shifter} => granted_to_everyone
      }

      for ruleset <- [siala, vanilla], {class_id, class} <- ruleset.classes do
        granted_ids =
          for {_level, ids} <- class.granted_feats,
              feat_id <- ids,
              into: MapSet.new(),
              do: feat_id

        overlap = MapSet.intersection(granted_ids, class.unavailable_feats)

        assert overlap == Map.get(expected, {ruleset.version, class_id}, MapSet.new()),
               "#{ruleset.version}/#{class.name}: forbids and grants #{inspect(MapSet.to_list(overlap))}"
      end
    end

    # Class-skill membership is stated twice on Fandom — on the class page and on
    # each skill page — and the two disagree in a handful of places. The union is
    # taken and every disagreement is recorded rather than resolved by the parser.
    test "class-skill disagreements between the two wiki sources are recorded", %{siala: ruleset} do
      assert {:conflict, {:class_skill, :harper_scout, :pick_pocket, :class_page_only}} in ruleset.gaps

      assert {:conflict, {:class_skill, :purple_dragon_knight, :discipline, :class_page_only}} in ruleset.gaps
    end

    # `alchemy` used to be the one dangling reference: harper_scout takes it as a
    # class skill (siala_41/classes.json) and the vanilla dictionary has no such
    # skill, so it was reported as missing. Loading siala_41/skills.json gives it
    # a record, and the gap is gone because the hole is gone — the check itself
    # stays, asserted from the other side so it cannot rot.
    test "every class skill resolves in the dictionary", %{siala: ruleset} do
      assert %{siala_only?: true} = ruleset.skills[:alchemy]
      refute {:missing_data, {:skill, :alchemy}} in ruleset.gaps

      dangling =
        for {id, class} <- ruleset.classes,
            skill <- class.class_skills,
            not Map.has_key?(ruleset.skills, skill),
            do: {id, skill}

      assert dangling == []
      refute Enum.any?(ruleset.gaps, &match?({:missing_data, {:skill, _}}, &1))
    end
  end

  describe "missing optional files" do
    # vanilla/skills.json does not exist yet (data-miner is on it). The loader
    # must degrade, not raise.
    test "an absent dictionary is empty and recorded", %{siala: ruleset} do
      if ruleset.skills == %{} do
        assert {:missing_file, "vanilla/skills.json"} in ruleset.gaps
      else
        refute {:missing_file, "vanilla/skills.json"} in ruleset.gaps
      end
    end

    test "the loader survives a rules directory with nothing optional in it" do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      source = Path.join(File.cwd!(), "priv/rules/vanilla")
      File.mkdir_p!(Path.join(root, "vanilla"))

      for file <- ~w(classes.json epic.json) do
        File.cp!(Path.join(source, file), Path.join([root, "vanilla", file]))
      end

      on_exit(fn -> File.rm_rf!(root) end)

      loaded = BuildCalculator.Data.Loader.load!(root)
      minimal = loaded["siala_41"]

      assert minimal.races == %{}
      assert minimal.feats == %{}
      assert minimal.skills == %{}
      # with no shard overrides, the cap falls back to vanilla's
      assert minimal.level_cap == 40
      assert minimal.max_classes == nil
      assert {:missing_file, "vanilla/races.json"} in minimal.gaps
      assert {:missing_data, :max_classes} in minimal.gaps
      # and the classes it does have are intact
      assert minimal.classes[:fighter].progression[20].bab == 20
      # the absent shard class layer overrides nothing: monk stays vanilla
      assert minimal.classes[:monk].bab_progression == "medium"
      assert minimal.attack_modifiers == []
    end
  end

  describe "feats taken with a parameter" do
    # Растяжка на время, пока данные писались: до их прихода загрузчик обязан
    # был деградировать, а не падать, и ничего не выдумывать. Данные приехали,
    # тест перевёрнут — теперь он держит, что словари **реальные**, а не что их
    # нет. Оба ruleset'а: сиальский слой повторяемость не переопределяет, но
    # обязан её донести.
    test "повторяемость и словари выбора приехали в оба ruleset'а", %{
      siala: siala,
      vanilla: vanilla
    } do
      for ruleset <- [siala, vanilla] do
        repeatable = for {_id, feat} <- ruleset.feats, not is_nil(feat.repeatable), do: feat

        assert repeatable != []
        assert ruleset.choice_domains != %{}

        # Домен, названный фитом, обязан резолвиться — иначе выбор не с чем
        # сверять, и «проверили» превращается в «приняли что угодно».
        #
        # ⚠️ Именно НАЗВАННЫЙ. `choice: null` — это тоже ответ страницы: фит
        # повторяется, не называя ничего (`Epic toughness`), и домена у него нет
        # не по недосмотру. Раньше здесь стояло «домен обязателен у всех», и это
        # отсекало 16 фитов, у которых параметра нет по источнику.
        for feat <- repeatable, not is_nil(feat.repeatable.choice) do
          assert Map.has_key?(ruleset.choice_domains, feat.repeatable.choice),
                 "домен #{inspect(feat.repeatable.choice)} у #{feat.id} не резолвится"
        end
      end
    end

    # Счётчик, а не выбор. `Epic toughness` на рядовом эпическом билде берут по
    # 10 раз, и до появления этой формы он был одноразовым.
    test "повторяемость без параметра приехала и она не пустая", %{vanilla: vanilla} do
      counters =
        for {id, feat} <- vanilla.feats,
            is_map(feat.repeatable),
            is_nil(feat.repeatable.choice),
            do: id

      assert :epic_toughness in counters
      assert length(counters) >= 16

      # Различаться нечему, значит и вопроса «должны ли picks отличаться» нет:
      # `nil` говорит «неприменимо», а не «нет» — булево здесь читалось бы как
      # ответ, которого никто не давал.
      assert vanilla.feats[:epic_toughness].repeatable.distinct? == nil
      refute {:missing_data, {:feat_repeatable, :epic_toughness}} in vanilla.gaps
    end

    # Ключ есть и он null — страница отвечена; ключа нет вовсе — не отвечена.
    # Читать их одинаково значило бы превратить недописанный блок в фит, сквозь
    # который проходит любой дубль.
    test "явный null и отсутствующий ключ — разные утверждения" do
      counter = load_fixture(repeatable: %{"choice" => nil, "quote" => "…"})
      silent = load_fixture(repeatable: %{"quote" => "…"})

      assert counter.feats[:fixture].repeatable.choice == nil
      refute {:missing_data, {:feat_repeatable, :fixture}} in counter.gaps

      assert silent.feats[:fixture].repeatable == nil
      assert {:missing_data, {:feat_repeatable, :fixture}} in silent.gaps
    end

    # Допущение «picks обязаны отличаться» — про домен. У счётчика домена нет,
    # значит и допущения про него никто не делал, и записывать его в гэпы
    # означало бы засчитать оговорку, которая неверна.
    test "у счётчика distinct не становится допущением ruleset'а" do
      loaded = load_fixture(repeatable: %{"choice" => nil})

      refute {:assumed, :repeatable_choices_must_differ} in loaded.gaps
    end

    # ⚠️ Потолок берётся только тот, что записан человеком со статусом.
    # «to a maximum of 200 hit points» — это потолок эффекта, а эффект фита ядро
    # не считает вовсе; делить одно на другое значило бы выдумать число.
    test "потолок взятий читается только со статусом verified или derived" do
      stated =
        load_fixture(
          repeatable: %{
            "choice" => nil,
            "max_takes" => %{"value" => 3, "status" => "verified", "quote" => "up to three times"}
          }
        )

      derived = load_fixture(repeatable: %{"choice" => nil, "max_takes" => counted_tiers(3)})

      assert stated.feats[:fixture].repeatable.max_takes.value == 3
      assert stated.feats[:fixture].repeatable.max_takes.status == "verified"

      # У прочитанного числа показывать нечего, и `from: nil` здесь — ответ,
      # а не пропуск.
      assert stated.feats[:fixture].repeatable.max_takes.from == nil

      # А у сосчитанного работа лежит рядом — иначе арифметику не перепроверить,
      # не возвращаясь на вики. Тег операции разобран, а не пронесён сырьём:
      # читатель обязан спросить `counted` вместе с нагрузкой и потому не может
      # прочитать чужую форму по совпадению ключей.
      assert derived.feats[:fixture].repeatable.max_takes.value == 3

      assert derived.feats[:fixture].repeatable.max_takes.from == %{
               counted: :tiers,
               tiers: ["Ступень I", "Ступень II", "Ступень III"]
             }
    end

    # ⚠️ Отрицательный контроль к тесту выше: без него «форма читается верно»
    # зеленело бы и на загрузчике, который читает что угодно. Под одним именем
    # `from` жили две формы — тегированное перечисление в данных и пара чисел
    # эффекта в докстринге, — и разбирались они пробой ключей: спросивший не тот
    # ключ получал `nil` и шёл дальше. Теперь любая запись, по которой нельзя
    # однозначно сказать, какой операцией получено число, роняет сборку.
    test "сторож роняет сборку на записи, форму которой пришлось бы угадывать" do
      # {что записано, что обязано прозвучать в сообщении}
      broken = [
        # Прежняя вторая форма: тега нет вовсе, ключи надо угадывать.
        {%{"value" => 10, "status" => "derived", "from" => %{"per_take" => 20, "maximum" => 200}},
         "names no `counted`"},
        # Тег есть, но операции с таким именем никто не реализовывал: прочитать
        # такую запись можно только наугад.
        {%{"value" => 3, "status" => "derived", "from" => %{"counted" => "steps"}},
         "not one of [\"tiers\"]"},
        # Смешанная запись: тег одной операции, ключи двух.
        {%{
           "value" => 3,
           "status" => "derived",
           "from" => %{"counted" => "tiers", "tiers" => ~w(I II III), "per_take" => 20}
         }, "carries [\"per_take\"]"},
        # Работа показана и не сходится с числом — то самое молчаливое
        # правдоподобие: «derived» стоит, а перепроверка его не подтверждает.
        {%{
           "value" => 4,
           "status" => "derived",
           "from" => %{"counted" => "tiers", "tiers" => ~w(I II III)}
         }, "counts 3 tiers"},
        # Повтор в перечислении завысил бы потолок молча.
        {%{
           "value" => 3,
           "status" => "derived",
           "from" => %{"counted" => "tiers", "tiers" => ["I", "II", "II"]}
         }, "Expected the distinct"},
        # Статус говорит «число прочитано», а рядом лежит арифметика, которой не
        # было. Обе половины пары проверяются, потому что каждая по отдельности
        # выглядит правдоподобно.
        {Map.put(counted_tiers(3), "status", "verified"), "at status \"verified\""},
        # И обратная половина: работа объявлена и не показана.
        {%{"value" => 3, "status" => "derived"}, "shows no `from`"},
        # `from` не объект вовсе.
        {%{"value" => 3, "status" => "derived", "from" => "три ступени"}, "carries from:"}
      ]

      for {block, said} <- broken do
        assert_raise RuntimeError, ~r/#{Regex.escape(said)}/, fn ->
          load_fixture(repeatable: %{"choice" => nil, "max_takes" => block})
        end
      end
    end

    # Положительный контроль к сторожу: он обязан ловить форму, а не всё подряд.
    # Запись без `from` при статусе, который вовсе не читается, — это
    # недописанная запись, а не порча формы, и правильный ответ на неё прежний:
    # потолок неизвестен.
    test "сторож молчит там, где запись просто не дописана" do
      loaded = load_fixture(repeatable: %{"choice" => nil, "max_takes" => %{"value" => 3}})

      assert loaded.feats[:fixture].repeatable.max_takes == nil
    end

    # ⚠️ Форма проверяется независимо от того, читается ли число сегодня: иначе
    # битый `from` отсиделся бы за `unclear` до того дня, когда кто-нибудь
    # поправит статус — и вылез бы уже другой правкой.
    test "битую форму не прячет ни нечитаемый статус, ни нечитаемый домен" do
      hidden = %{"value" => 3, "status" => "unclear", "from" => %{"counted" => "steps"}}

      # Статус, при котором число сегодня не читается вовсе. Запись всё равно
      # обязана упасть: у неё две беды сразу, и о первой сторож говорит первой.
      assert_raise RuntimeError, ~r/at status "unclear"/, fn ->
        load_fixture(repeatable: %{"choice" => nil, "max_takes" => hidden})
      end

      # Домена нет вовсе — блок в ruleset не едет ни при каком статусе, и это
      # ровно то место, где проверка формы могла бы промолчать. Не молчит.
      assert_raise RuntimeError, ~r/not one of/, fn ->
        load_fixture(repeatable: %{"max_takes" => %{hidden | "status" => "derived"}})
      end
    end

    test "потолок без статуса, с чужим статусом или голым числом не читается" do
      for block <- [
            %{"value" => 3},
            %{"value" => 3, "status" => "unclear"},
            %{"value" => 0, "status" => "verified"},
            3
          ] do
        loaded = load_fixture(repeatable: %{"choice" => nil, "max_takes" => block})

        assert loaded.feats[:fixture].repeatable.max_takes == nil,
               "потолок #{inspect(block)} прочитан, а не должен был"
      end
    end

    # ⚠️ Число из ПРОЗЫ страницы `Favored enemy`, а не из длины списка: «There
    # are 24 favored enemy races available; of the 25 standard races, only ooze
    # cannot be selected». Список, который сошёлся сам с собой, ничего не
    # доказывает — сверять надо с утверждением источника.
    test "расовые типы: 25 всего, 24 доступны, исключён ровно ooze", %{siala: siala} do
      domain = Map.fetch!(siala.choice_domains, :creature_type)
      gate = Map.get(domain.flags, :favored_enemy, MapSet.new())

      assert MapSet.size(domain.values) == 25
      assert MapSet.size(gate) == 24
      assert MapSet.difference(domain.values, gate) == MapSet.new([:ooze])
    end

    test "школы магии: 8 доступных, universal не школа", %{siala: siala} do
      domain = Map.fetch!(siala.choice_domains, :spell_school)

      assert MapSet.member?(domain.values, :universal)
      assert MapSet.size(domain.values) == 9
    end

    test "the block is read, and the domain resolved from a file", %{siala: _} do
      loaded = load_fixture(repeatable: %{"choice" => "fixture_kind", "quote" => "…"})
      feat = loaded.feats[:fixture]

      assert feat.repeatable.choice == :fixture_kind
      # Not stated in the block, so assumed — and the assumption is on record.
      assert feat.repeatable.distinct? == true
      refute feat.repeatable.distinct_stated?
      assert {:assumed, :repeatable_choices_must_differ} in loaded.gaps

      # `fixture_kinds.json` was found by the domain's own name; the wrapping key
      # inside it ("things") is not prescribed anywhere.
      assert loaded.choice_domains[:fixture_kind].values == MapSet.new([:one, :two, :three])
      refute {:missing_data, {:choice_domain, :fixture_kind}} in loaded.gaps
    end

    test "a per-entry boolean gates the values for the feat it names" do
      loaded = load_fixture(repeatable: %{"choice" => "fixture_kind"})

      assert loaded.choice_domains[:fixture_kind].flags[:fixture] == MapSet.new([:one, :two])
    end

    test "an explicit distinct flag is carried and stops the assumption" do
      loaded = load_fixture(repeatable: %{"choice" => "fixture_kind", "distinct" => false})

      assert loaded.feats[:fixture].repeatable.distinct? == false
      assert loaded.feats[:fixture].repeatable.distinct_stated?
      refute {:assumed, :repeatable_choices_must_differ} in loaded.gaps
    end

    # A domain nothing resolves — weapons today, and forever until the armoury.
    # The answer is a gap, never an empty dictionary that would refuse every value.
    test "a domain with no dictionary is a gap, not an empty list" do
      loaded = load_fixture(repeatable: %{"choice" => "weapon"})

      assert loaded.choice_domains[:weapon].values == nil
      assert {:missing_data, {:choice_domain, :weapon}} in loaded.gaps
    end

    # `skill` needs no file: the ruleset already carries 29 of them, and writing
    # them out a second time would be two lists to keep in step.
    test "a domain resolves to a dictionary the ruleset already carries" do
      loaded = load_fixture(repeatable: %{"choice" => "class"})

      assert loaded.choice_domains[:class].source == {:ruleset, :classes}
      assert MapSet.member?(loaded.choice_domains[:class].values, :fighter)
    end

    # "Present and unreadable" is not "absent": the feat stays single-take, which
    # is the safe direction, and says so instead of looking unmarked.
    test "a block with no usable choice leaves the feat single-take, and says so" do
      loaded = load_fixture(repeatable: %{"quote" => "…"})

      assert loaded.feats[:fixture].repeatable == nil
      assert {:missing_data, {:feat_repeatable, :fixture}} in loaded.gaps
    end
  end

  # A rules directory holding one class, the epic table, one feat and one choice
  # dictionary. Built rather than mocked so the file discovery is exercised too.
  defp load_fixture(opts) do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    source = Path.join(File.cwd!(), "priv/rules/vanilla")
    File.mkdir_p!(Path.join(root, "vanilla"))
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root) end)

    for file <- ~w(classes.json epic.json) do
      File.cp!(Path.join(source, file), Path.join([root, "vanilla", file]))
    end

    feat =
      %{
        "id" => "fixture",
        "name" => "Fixture",
        "type" => "general",
        "epic" => false,
        "bonus_for" => [],
        "granted_by" => [],
        "unlocks" => []
      }
      |> Map.merge(
        case Keyword.fetch(opts, :repeatable) do
          {:ok, block} -> %{"repeatable" => block}
          :error -> %{}
        end
      )

    File.write!(Path.join([root, "vanilla", "feats.json"]), Jason.encode!([feat]))

    # The wrapper key is deliberately not the plural of the domain: the loader
    # must not require the two to agree.
    File.write!(
      Path.join([root, "vanilla", "fixture_kinds.json"]),
      Jason.encode!(%{
        "things" => [
          %{"id" => "one", "name" => "One", "fixture" => true},
          %{"id" => "two", "name" => "Two", "fixture" => true},
          %{"id" => "three", "name" => "Three", "fixture" => false}
        ]
      })
    )

    BuildCalculator.Data.Loader.load!(root)["siala_41"]
  end

  # Единственная сегодня операция «показанной работы»: страница вместо числа
  # перечисляет именованные ступени, и потолок равен их количеству. Собирается
  # хелпером, чтобы у отрицательных контролей ниже ломалась ровно одна вещь за
  # раз, а не «где-то в этом блоке».
  defp counted_tiers(n) do
    tiers = Enum.map(1..n, &"Ступень #{String.duplicate("I", &1)}")

    %{
      "value" => n,
      "status" => "derived",
      "from" => %{"counted" => "tiers", "tiers" => tiers}
    }
  end
end
