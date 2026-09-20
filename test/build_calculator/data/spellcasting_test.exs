defmodule BuildCalculator.Data.SpellcastingTest do
  @moduledoc """
  The hand-written casting file, and the two things it makes checkable.

  `priv/rules/vanilla/spellcasting.json` is hand written and sits next to the
  machine-generated dictionaries, so half of what is pinned here is about it
  being **read at all**: registered by name for staleness, kept out of the choice
  domains, and its ids resolved against the real class dictionary.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  describe "the file is wired in" do
    # ⚠ `source_files/0` registers the `vanilla` **directory**, whose mtime moves
    # when a file is added and not when one is edited. A hand-written file that
    # is only covered by the directory entry would go on being compiled from a
    # stale copy after every edit — the lesson wave 5 paid for with
    # `feat_skill_bonuses.json`.
    test "registered by name, not merely by its directory" do
      assert "vanilla/spellcasting.json" in Loader.source_files()
    end

    # Every `vanilla/*.json` that is not a rules file is read as a dictionary a
    # feat's parameter may be drawn from. A new rules file that forgets to say so
    # would quietly become a choice domain named `spellcasting`.
    test "is not mistaken for a choice domain", %{siala: siala} do
      refute Map.has_key?(siala.choice_domains, :spellcasting)

      # Positive control: the mechanism it is being kept out of is alive.
      assert Map.has_key?(siala.choice_domains, :creature_type)
    end

    test "both rulesets carry the rules, since they are vanilla facts", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala] do
        assert ruleset.casting.ability_minimum == %{base: 10, per_circle: 1}
        assert Map.has_key?(ruleset.casting.advancement, :pale_master)
      end
    end
  end

  describe "casting ability, off each class page's own label" do
    # source: vanilla/classes.json → `primary_ability_raw`, e.g. `"[[wisdom]]"`.
    # The seven are exactly the classes whose progression tables carry spell
    # rows, which is a second and independent statement of the same fact.
    test "every class with a spell table has one, and no other class does", %{siala: siala} do
      casters =
        for {id, class} <- siala.classes, map_size(class.spells_per_day) > 0, do: {id, class}

      assert length(casters) == 7

      for {id, class} <- casters do
        assert class.casting_ability in [:str, :dex, :con, :int, :wis, :cha],
               "#{id} casts and names no ability"
      end

      for {_id, class} <- siala.classes, map_size(class.spells_per_day) == 0 do
        assert class.casting_ability == nil
      end
    end

    # The wiki writes the word, not the three-letter key, and writes it inside
    # links. Pinned per class because a mapping that got two of them the wrong
    # way round would still pass a "all seven are set" check.
    test "the six words map to the six abilities", %{siala: siala} do
      assert siala.classes.wizard.casting_ability == :int
      assert siala.classes.sorcerer.casting_ability == :cha
      assert siala.classes.bard.casting_ability == :cha
      assert siala.classes.cleric.casting_ability == :wis
      assert siala.classes.druid.casting_ability == :wis
      assert siala.classes.paladin.casting_ability == :wis
      assert siala.classes.ranger.casting_ability == :wis
    end
  end

  describe "the prestige advancement record" do
    test "reads as the page states it", %{siala: siala} do
      assert siala.casting.advancement.pale_master == %{
               class: :pale_master,
               advances: :spells_per_day,
               hosts: [:bard, :sorcerer, :wizard],
               host_choice: :highest_class_level,
               at_class_levels: :odd,
               levels_per_grant: 1
             }
    end

    # Nothing else in the data advances anybody's casting. Pinned so a second
    # record arriving is a visible event rather than a silent one — every other
    # prestige class in NWN leaves casting alone, and one that did not would
    # change what a whole shape of build may take.
    test "is the only one", %{siala: siala} do
      assert Map.keys(siala.casting.advancement) == [:pale_master]
    end
  end

  describe "the school specialization record (task 3.10)" do
    test "reads as the page states it", %{siala: siala} do
      assert siala.casting.school_specialization.wizard == %{
               class: :wizard,
               bonus_per_circle: 1,
               min_circle: 1,
               opposed_schools: %{
                 abjuration: :conjuration,
                 conjuration: :transmutation,
                 divination: :illusion,
                 enchantment: :illusion,
                 evocation: :conjuration,
                 illusion: :enchantment,
                 necromancy: :divination,
                 transmutation: :conjuration
               }
             }
    end

    # `opposed_schools` — направленная таблица, не пары. Abjuration теряет
    # Conjuration, но у Conjuration в противниках Transmutation, а не
    # Abjuration — источник прямо говорит, что таблица не симметричная
    # («different from those in pencil-and-paper»). Три школы никогда не
    # стоят справа ни у кого — их не запрещает НИКАКАЯ специализация.
    test "the table is directed, not a set of symmetric pairs", %{siala: siala} do
      opposed = siala.casting.school_specialization.wizard.opposed_schools

      refute Map.get(opposed, :conjuration) == :abjuration
      assert Map.get(opposed, :conjuration) == :transmutation

      never_forbidden =
        MapSet.new(Map.keys(opposed)) |> MapSet.difference(MapSet.new(Map.values(opposed)))

      assert never_forbidden == MapSet.new([:abjuration, :evocation, :necromancy])
    end

    # `universal` не входит ни в один домен доменного словаря `spell_school`
    # для выбора — его исключает флаг `selectable` (см. `spell_schools.json`),
    # тот же самый гейт, что и у `Spell focus`. Это не про специализацию
    # (`school_specialization` не несёт `universal` вовсе — его там нет
    # физически), а про то, что «без специализации» выражается ОТСУТСТВИЕМ
    # значения, а не выбором псевдошколы.
    test "universal is not a key anywhere in the record", %{siala: siala} do
      entry = siala.casting.school_specialization.wizard

      refute Map.has_key?(entry.opposed_schools, :universal)
      refute :universal in Map.values(entry.opposed_schools)
    end

    # Сиала про специализацию молчит целиком (страница «Волшебник» не
    # содержит слова «школа») — правило ванильное и одинаковое в обоих
    # ruleset'ах, тем же способом, что уже проверено для доменов клирика.
    test "vanilla carries the same record — Siala renamed nothing about it", %{siala: siala} do
      vanilla = Data.ruleset!("vanilla")
      assert vanilla.casting.school_specialization == siala.casting.school_specialization
    end

    # Положительный контроль: обычный кастер без записи специализации не
    # тянет за собой пустую карту, которую легко спутать с «есть, но пустая».
    test "a caster with no specialization record simply has no key", %{siala: siala} do
      refute Map.has_key?(siala.casting.school_specialization, :sorcerer)
      assert Map.keys(siala.casting.school_specialization) == [:wizard]
    end
  end

  # source: `fandom:Spell focus`, Notes, revid 69073 — «Spontaneous casters
  # ([[bard]]s and [[sorcerer]]s) can take this feat without being able to cast
  # first level spells as long as their class level qualifies for at least 0
  # level one spell slots»; corroborated per class by the `Spellcasting:` label
  # («and [[spontaneous cast]] (no spell preparation required)» on Bard revid
  # 71572 and Sorcerer revid 71586, «and requires preparation» on the other
  # five).
  describe "the spontaneous caster record (task 3.124)" do
    test "reads as the sentence names it, in both rulesets", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala] do
        assert ruleset.casting.spontaneous == MapSet.new([:bard, :sorcerer])
      end
    end

    # 🔴 Два независимых утверждения об одном свойстве, и они обязаны сходиться.
    # Список выше — цитата источника про подготовку заклинаний; `spells_known`
    # приезжает машинным слоем из таблиц прогрессии и говорит про каталог
    # известных. Сегодня они дают одно и то же множество, и это не совпадение:
    # таблицу известных в NWN имеет ровно спонтанный кастер.
    #
    # ⚠ Выводить одно из другого ядро при этом НЕ должно, и ровно поэтому здесь
    # тест, а не вывод в загрузчике: расхождение — событие, которое надо
    # увидеть и решить руками, а не молча переопределить смысл записи.
    test "совпадает с «непустой spells_known», и расхождение станет видно", %{siala: siala} do
      knows =
        for {id, class} <- siala.classes, map_size(class.spells_known) > 0, into: MapSet.new() do
          id
        end

      assert knows == siala.casting.spontaneous

      # Отрицательный контроль: у остальных пяти кастеров таблицы известных нет
      # вовсе, то есть множество выше не «все, кто кастует».
      casters =
        for {id, class} <- siala.classes,
            map_size(class.spells_per_day) > 0,
            into: MapSet.new() do
          id
        end

      assert MapSet.size(casters) == 7
      assert MapSet.size(MapSet.difference(casters, knows)) == 5
    end

    # 🔴 Клирик — контрпример, ради которого список лежит руками: слово
    # `spontaneous` на его странице есть («which can be [[spontaneous cast]]»),
    # а классом спонтанного каста он не является. Тест держит именно это: любой
    # будущий парсер, выводящий признак поиском слова, свалится здесь.
    test "клирик в множество не входит, хотя слово на его странице есть", %{siala: siala} do
      refute MapSet.member?(siala.casting.spontaneous, :cleric)

      cleric = File.read!("priv/wiki_cache/fandom/Cleric.wikitext")
      assert cleric =~ "spontaneous cast"
      assert cleric =~ "requires preparation"
    end

    # Положительный контроль к сторожу загрузчика: файл, называющий прочтение,
    # которого ядро не реализует, роняет сборку, а не применяется наполовину.
    @tag :tmp_dir
    test "запись с чужим прочтением роняет сборку", %{tmp_dir: tmp_dir} do
      root = Path.join(tmp_dir, "rules")
      File.cp_r!("priv/rules", root)
      path = Path.join(root, "vanilla/spellcasting.json")

      file = path |> File.read!() |> Jason.decode!()

      broken =
        put_in(file, ["spontaneous_casters", "feat_prerequisite"], "any_level_of_a_caster")

      File.write!(path, Jason.encode!(broken))

      assert_raise RuntimeError, ~r/spontaneous_casters\.feat_prerequisite/, fn ->
        Loader.load!(root)
      end
    end

    # И на несуществующий класс — та же реакция, что у соседних записей файла:
    # опечатка в ручном файле молча выключила бы правило.
    @tag :tmp_dir
    test "несуществующий класс в списке роняет сборку", %{tmp_dir: tmp_dir} do
      root = Path.join(tmp_dir, "rules")
      File.cp_r!("priv/rules", root)
      path = Path.join(root, "vanilla/spellcasting.json")

      file = path |> File.read!() |> Jason.decode!()
      broken = put_in(file, ["spontaneous_casters", "classes"], ["bard", "sorceror"])

      File.write!(path, Jason.encode!(broken))

      assert_raise RuntimeError, ~r/sorceror/, fn -> Loader.load!(root) end
    end

    # ⚠️ Без записи исключение не достаётся НИКОМУ — сторона строгая, — и об
    # этом сказано вслух. Проверяется на копии `priv/rules` с убранной записью,
    # а не на сегодняшнем файле, тем же приёмом, что у бонусных слотов.
    @tag :tmp_dir
    test "ruleset без записи говорит об этом гэпом", %{tmp_dir: tmp_dir} do
      root = Path.join(tmp_dir, "rules")
      File.cp_r!("priv/rules", root)
      path = Path.join(root, "vanilla/spellcasting.json")

      file = path |> File.read!() |> Jason.decode!()
      File.write!(path, Jason.encode!(Map.delete(file, "spontaneous_casters")))

      ruleset = Loader.load!(root)["siala_41"]

      assert ruleset.casting.spontaneous == nil
      assert {:missing_data, :spontaneous_casters} in ruleset.gaps

      # И положительный контроль: у сегодняшнего файла этого гэпа нет.
      refute {:missing_data, :spontaneous_casters} in Data.ruleset!("siala_41").gaps
    end
  end

  describe "the bonus spell slot record (task 3.70)" do
    test "reads as the page states it", %{siala: siala} do
      rule = siala.casting.bonus_slots

      assert rule.min_circle == 1
      assert rule.modifier_source == "modified"
      assert rule.circle_must_be_in_class_row == true
      assert rule.zero_slots_count == true
      assert rule.formula == %{divisor: 4, plus: 1, minimum: 0}
    end

    # Ровно те 26 строк, что напечатаны на странице: от −4 («cannot cast
    # spells tied to this ability») до +21 (характеристика 52, потолок,
    # достижимый ровно на капе: 18 поинт-бай + 2 раса + 10 прибавок за уровни
    # + 10 `Great …` + 2 РДД + 12 с вещей).
    test "the table covers modifiers -4 through +21, nine circles each", %{siala: siala} do
      table = siala.casting.bonus_slots.by_modifier

      assert table |> Map.keys() |> Enum.sort() == Enum.to_list(-4..21)

      for {_modifier, row} <- table do
        assert row |> Map.keys() |> Enum.sort() == Enum.to_list(1..9)
      end
    end

    # 🔴 Таблица против формулы, ячейка за ячейкой. Источник печатает обе,
    # и это не два факта: формула — правило, таблица — её табуляция, поэтому
    # расхождение было бы ошибкой переноса. 26 × 9 = 234 ячейки.
    #
    # ⚠️ Загрузчик проверяет то же самое и роняет сборку, так что зелёный
    # здесь ничего не доказывает сам по себе — доказывает соседний тест,
    # который эту проверку ЛОМАЕТ и ждёт падения.
    test "every cell of the table equals the formula the same paragraph states", %{siala: siala} do
      rule = siala.casting.bonus_slots

      cells =
        for {modifier, row} <- rule.by_modifier, {circle, count} <- row do
          assert count ==
                   BuildCalculator.Rules.Spells.bonus_slots_by_formula(
                     rule.formula,
                     modifier,
                     circle
                   ),
                 "модификатор #{modifier}, круг #{circle}"

          :ok
        end

      assert length(cells) == 234
    end

    # Положительный контроль к предыдущему: сторож загрузчика жив. Одна
    # испорченная ячейка в копии `priv/rules` — и сборка ruleset'а падает
    # с обеими величинами в сообщении.
    @tag :tmp_dir
    test "a table that disagrees with its own formula stops the build", %{tmp_dir: tmp_dir} do
      root = Path.join(tmp_dir, "rules")
      File.cp_r!("priv/rules", root)
      path = Path.join(root, "vanilla/spellcasting.json")

      file = path |> File.read!() |> Jason.decode!()

      broken =
        put_in(file, ["bonus_spell_slots", "by_modifier", "5"], [9, 1, 1, 1, 1, 0, 0, 0, 0])

      File.write!(path, Jason.encode!(broken))

      assert_raise RuntimeError, ~r/disagrees with its own formula/, fn ->
        Loader.load!(root)
      end
    end

    # Сиала про бонусные слоты не говорит ничего — ни слова «слот», ни
    # «заклинаний в день» на 282 закэшированных страницах. Значит правило
    # ванильное и одинаковое в обоих ruleset'ах, тем же способом, что уже
    # проверено для доменов клирика и специализации волшебника.
    test "vanilla carries the same record — Siala says nothing about it", %{siala: siala} do
      vanilla = Data.ruleset!("vanilla")

      assert vanilla.casting.bonus_slots == siala.casting.bonus_slots
    end

    # ⚠️ Форма гэпа осталась жива, и утверждение «таблицы нет» вместе с ней —
    # просто теперь оно проверяемое: печатается ровно тогда, когда таблицы
    # и правда нет, а не всегда. Проверяется на копии `priv/rules` с убранной
    # записью, а не на сегодняшнем файле.
    @tag :tmp_dir
    test "a ruleset with no table says so out loud", %{tmp_dir: tmp_dir} do
      root = Path.join(tmp_dir, "rules")
      File.cp_r!("priv/rules", root)
      path = Path.join(root, "vanilla/spellcasting.json")

      file = path |> File.read!() |> Jason.decode!()
      File.write!(path, Jason.encode!(Map.delete(file, "bonus_spell_slots")))

      ruleset = Loader.load!(root)["siala_41"]

      assert ruleset.casting.bonus_slots == nil
      assert {:missing_data, :bonus_spell_slots} in ruleset.gaps

      # И положительный контроль: у сегодняшнего файла этого гэпа нет.
      refute {:missing_data, :bonus_spell_slots} in Data.ruleset!("siala_41").gaps
    end
  end

  describe "what the file records and refuses to apply" do
    # ⚠ The finding of 03.08.2026, **applied** 15.08.2026 (task 3.31) — and this
    # test is upside down from what it was, on purpose. It used to require the
    # gap: all six epic-spell pages say in their own Notes that the printed
    # requirement is not the real one («the actual prerequisite is not the
    # ability to cast level 9 spells, but … at least 15 pale master levels»),
    # and only half of that was thought to fit the schema.
    #
    # Both halves fit. What «epic» means is on a page of its own
    # (`fandom:Epic class`: 21 levels of a base class, 11 of a prestige one,
    # with this rule naming 15 for the pale master), and the differing class
    # lists are just different values of one key. Dan measured the rest
    # (Бард 10 / ПМ 15 — the game offers `Epic spell: mummy dust`).
    #
    # So the gap has to be gone: a rule that is counted and still announced as
    # unknown is the false uncertainty CLAUDE.md §6 forbids — the same shape as
    # the cantrip caveat two tests below, which was inverted for the same reason.
    test "the epic-spell prerequisite override is applied, so it is not a gap", %{siala: siala} do
      refute {:not_modelled, {:caster_advancement, :epic_spell_access}} in siala.gaps

      # And it is applied rather than merely dropped: the requirement the pages
      # call wrong is gone, and the one they state is in its place.
      prereqs = siala.feats.epic_spell_hellball.prereqs

      refute Map.has_key?(prereqs, "casts_spell_level")

      assert prereqs["qualifying_class_levels"] == %{
               "cleric" => 21,
               "druid" => 21,
               "sorcerer" => 21,
               "wizard" => 21,
               "pale_master" => 15
             }
    end

    # The narrower list, read off its own page rather than carried over from the
    # neighbouring one: `Epic mage armor` and `Epic warding` are arcane-only, and
    # two of the six saying something different is exactly why each page is read
    # separately.
    test "two of the six name a shorter list of qualifying classes", %{siala: siala} do
      for id <- [:epic_spell_epic_mage_armor, :epic_spell_epic_warding] do
        assert siala.feats[id].prereqs["qualifying_class_levels"] == %{
                 "sorcerer" => 21,
                 "wizard" => 21,
                 "pale_master" => 15
               }
      end
    end

    test "nothing in the file failed to load", %{siala: siala} do
      refute {:missing_file, "vanilla/spellcasting.json"} in siala.gaps
      refute {:missing_data, :casting_ability_minimum} in siala.gaps

      unreadable =
        for {:missing_data, {:caster_advancement, class}} <- siala.gaps, do: class

      assert unreadable == []
    end

    # Задача 3.10. Число (+1 слот на круг) СЧИТАЕТСЯ (`Rules.Spells`).
    #
    # ⚠️ Здесь было ДВА гэпа, и не осталось ни одного — оба ушли по-разному,
    # и разница важнее самих строк:
    #
    #   * «включает ли бонус круг 0» снят 09.08.2026 ЗАМЕРОМ (волшебник 1,
    #     INT 11, Conjuration → круг 0 показывает 3, круг 1 — 2);
    #   * `{:not_modelled, :wizard_opposed_school}` снят 24.08.2026 (задача
    #     3.86) ОТВЕТОМ: он говорил, что выгоду специализации мы считаем,
    #     а цену — потерю противоположной школы — нет. Теперь цена названа
    #     числом в самом месте выбора (`Rules.Spells.specialization_costs/2`).
    #
    # Оба `refute`, а не удалённые строки: печатать «не знаем» про посчитанное
    # запрещено так же прямо, как обратное (CLAUDE.md §6), и вернувшийся гэп
    # обязан упасть тестом, а не тихо появиться на экране.
    test "neither school-specialization caveat is declared any more", %{siala: siala} do
      refute {:not_modelled, :wizard_opposed_school} in siala.gaps

      refute {:assumed, :wizard_specialization_excludes_cantrips} in siala.gaps
    end

    # Положительный контроль к `refute` выше: оговорки нет не потому, что гэпов
    # у ruleset'а вообще не осталось и не потому, что специализация перестала
    # читаться, — а потому что этот конкретный вопрос закрыт замером.
    test "the cantrip rule is measured, not silently baked in", %{siala: siala} do
      assert siala.gaps != []

      spec = siala.casting.school_specialization.wizard
      assert spec.min_circle == 1
      assert spec.bonus_per_circle == 1
    end
  end
end
