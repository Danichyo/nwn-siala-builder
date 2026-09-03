defmodule BuildCalculator.Data.ClassRequirementsTest do
  @moduledoc """
  The hand-written layer over a prestige class's requirements.

  `priv/rules/vanilla/class_requirements.json` exists because some requirements
  are *stated* in the requirements block and *explained* somewhere else on the
  page: Pale Master asks for «arcane spellcasting: level 3 or higher», and only
  the Notes section says that this is a caster level rather than a spell circle,
  and which three classes satisfy it. No parser reaches a sentence like that.

  Half of what is pinned here is about the file being **read at all** — the
  lesson `feat_skill_bonuses.json` and `spellcasting.json` already paid for — and
  half about its two compile-time guards, which are the only thing keeping a hand
  written entry from silently outliving the machine layer it was written against.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}

  @path "vanilla/class_requirements.json"

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  describe "the file is wired in" do
    # ⚠ `source_files/0` registers the `vanilla` **directory**, whose mtime moves
    # when a file is added and not when one is edited. A hand-written file that
    # is only covered by the directory entry would go on being compiled from a
    # stale copy after every edit.
    test "registered by name, not merely by its directory" do
      assert @path in Loader.source_files()
    end

    # Every `vanilla/*.json` that is not a rules file is read as a dictionary a
    # feat's parameter may be drawn from. A new rules file that forgets to say so
    # would quietly become a choice domain named `class_requirements`.
    test "is not mistaken for a choice domain", %{siala: siala} do
      refute Map.has_key?(siala.choice_domains, :class_requirements)
      refute Map.has_key?(siala.choice_domains, :class_requirement)

      # Positive control: the mechanism it is being kept out of is alive.
      assert Map.has_key?(siala.choice_domains, :creature_type)
    end

    # It is a vanilla fact — Fandom's own prose about a vanilla class — so the
    # shard ruleset inherits it rather than restating it.
    test "both rulesets carry the readings", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        assert ruleset.classes[:pale_master].requirements[:any_of] != nil
        assert ruleset.classes[:red_dragon_disciple].requirements[:any_of] != nil
        assert ruleset.classes[:arcane_archer].requirements[:any_of] != nil
      end
    end
  end

  describe "what the file does, shown by taking it away" do
    # The strongest positive control available: without the file, the three
    # requirements go back to being gaps and Pale Master goes back to being
    # takeable at character level 1. If something else in the loader were doing
    # this work, this test would not change when the file disappears.
    test "removing it brings the gaps and the false legality back" do
      %{"siala_41" => shard, "vanilla" => vanilla} = load_without_file()

      assert {:missing_data, {:requirement, :pale_master, "arcane_spellcasting"}} in shard.gaps
      assert {:missing_data, {:requirement, :red_dragon_disciple, "unparsed"}} in shard.gaps

      # ⚠️ Тайный лучник спрашивается у ВАНИЛИ, а не у Сиалы, и с 17.08.2026
      # иначе нельзя. Ответ Dan сделал сиальскую запись требований применяемой,
      # а `apply_change` для `what: "requirements"` заменяет блок ЦЕЛИКОМ —
      # значит у Сиалы ванильный ключ `spellcasting` до гэпа не доживает,
      # сколько бы файлов мы ни убирали. Утверждение теста от этого не
      # ослабло: оно про то, что ручной слой — единственное, что закрывает
      # эту дыру там, где сверху ничего не лежит.
      assert {:missing_data, {:requirement, :arcane_archer, "spellcasting"}} in vanilla.gaps

      naked = BuildCalculator.Rules.Build.new(alignment: :neutral_evil)
      assert BuildCalculator.Rules.validate_level_up(naked, :pale_master, shard) == :ok
    end
  end

  # Строка «Заклинания» Тайного лучника — единственное место файла, где мы
  # выбрали Fandom ПРОТИВ страницы Сиалы, и до 17.08.2026 выбор держался
  # на разборе, а не на наблюдении: Сиала пишет «Способность читать тайные
  # заклинания 1-го уровня», Fandom называет такую формулировку неверной
  # документацией и требует УРОВЕНЬ арканового класса.
  #
  # Замер Dan 17.08.2026 («1 бард + 6 воин, на 7 уровне arcane archer доступен»)
  # подтвердил ванильное чтение. Значение не изменилось — изменилось его
  # основание, и тест ровно об этом: он фиксирует не «требование такое»,
  # а «требование такое, и вот наблюдение, которое его отличает от другого».
  describe "требование к заклинаниям Тайного лучника — замер 17.08.2026" do
    # Билд замера, собранный целиком: раса и два фита нужны, иначе `:ok`
    # не отличить от отказа по соседней строке требований.
    defp measured_build do
      BuildCalculator.Rules.Build.new(
        race: :half_elf,
        levels: [:bard] ++ List.duplicate(:fighter, 6),
        feats: %{
          1 => %{{:general, 1} => {:point_blank_shot, nil}},
          2 => %{{:class_bonus, :fighter, 2} => {:weapon_focus, :longbow}}
        }
      )
    end

    # ⚠️ Только siala_41, и это не забывчивость: у ванильного ruleset'а нет
    # `max_classes` (лимит классов — правило шарда), поэтому там любой
    # левелап отказывает с `{:missing_data, :max_classes}` — свойство
    # ruleset'а, а не этого требования. Ванильная сторона проверяется формой
    # требования в тесте ниже.
    test "бард 1 + воин 6 берёт класс на 7-м уровне", %{siala: siala} do
      assert BuildCalculator.Rules.validate_level_up(measured_build(), :arcane_archer, siala) ==
               :ok
    end

    # 🔴 Несущая половина замера. Без неё «класс доступен» ничего не различает:
    # у билда с кастером повыше оба чтения дали бы одинаковый ответ, и тест
    # проверял бы, что требование вообще существует, а не КАКОЕ оно.
    test "и заклинаний 1-го круга у него при этом НЕТ", %{siala: siala} do
      assert BuildCalculator.Rules.Spells.casters_for_circle(measured_build(), siala, 1) == []

      # Положительный контроль: круг достижим, просто не на этом билде — иначе
      # пустой список значил бы «функция сломана», а не «бард 1 не кастует».
      later = BuildCalculator.Rules.Build.new(levels: List.duplicate(:bard, 5))
      assert [%{class: :bard}] = BuildCalculator.Rules.Spells.casters_for_circle(later, siala, 1)

      # ⚠️ И вторая половина контроля, ради которой он тут вообще нужен:
      # у ВОЛШЕБНИКА круг есть с первого же уровня. То есть буквальное чтение
      # («нужна способность читать заклинания 1-го круга») сделало бы требование
      # разным для разных классов одного и того же `any_of` — ровно то, что
      # Fandom называет неверным прочтением в своих «Notes».
      wizard = BuildCalculator.Rules.Build.new(levels: [:wizard])

      assert [%{class: :wizard}] =
               BuildCalculator.Rules.Spells.casters_for_circle(wizard, siala, 1)
    end

    # Отрицательный контроль: требование существует и отказывает, то есть `:ok`
    # выше — про уровень барда, а не про то, что строку никто не проверяет.
    test "а чистый воин 7 получает отказ, и он называет три класса", %{siala: siala} do
      fighter =
        BuildCalculator.Rules.Build.new(
          race: :half_elf,
          levels: List.duplicate(:fighter, 7),
          feats: %{
            1 => %{{:general, 1} => {:point_blank_shot, nil}},
            2 => %{{:class_bonus, :fighter, 2} => {:weapon_focus, :longbow}}
          }
        )

      assert {:error, reasons} =
               BuildCalculator.Rules.validate_level_up(fighter, :arcane_archer, siala)

      assert reasons == [
               requires_any_of: [
                 [{:requires_class_level, :bard, 1}],
                 [{:requires_class_level, :sorcerer, 1}],
                 [{:requires_class_level, :wizard, 1}]
               ]
             ]
    end

    # И то, чем буквальное чтение страницы Сиалы отличалось бы от нашего —
    # не словами, а формой требования. `casts_spell_level` в записи нет и быть
    # не должно: именно его вернул бы тот, кто «починит» требование по цитате.
    test "требование записано уровнем класса, а не кругом заклинаний",
         %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        requirements = ruleset.classes[:arcane_archer].requirements

        refute Map.has_key?(requirements, :casts_spell_level)

        assert requirements[:any_of] == [
                 %{"class_levels" => %{"bard" => 1}},
                 %{"class_levels" => %{"sorcerer" => 1}},
                 %{"class_levels" => %{"wizard" => 1}}
               ]
      end
    end
  end

  describe "the guards against drifting apart from the machine layer" do
    # `replaces` is what stood in `vanilla/classes.json` when the entry was
    # written. A re-parse that changes the wording — the page edited, the parser
    # improved — must not leave a human reading attached to a requirement that no
    # longer says what it said.
    test "a requirement whose wording moved raises instead of applying" do
      root = copy_rules()

      edit_entry(root, "pale_master", fn entry ->
        put_in(entry["replaces"]["arcane_spellcasting"], "level 9 or higher")
      end)

      assert_raise RuntimeError, ~r/page moved under the entry/, fn -> Loader.load!(root) end
    end

    # The other direction, and the happier one: `mix wiki.parse` learns to read
    # the place itself. Then the entry is not wrong, it is *redundant* — and a
    # redundant hand-written reading sitting on top of a parsed one is exactly
    # how two sources of truth start.
    test "a requirement the parser now reads by itself raises as stale" do
      root = copy_rules()

      # simulate the parser having grown a reading of its own by naming a key it
      # already understands
      edit_entry(root, "red_dragon_disciple", fn entry ->
        %{entry | "replaces" => %{"skills" => %{"lore" => 8}}}
      end)

      assert_raise RuntimeError, ~r/stale/, fn -> Loader.load!(root) end
    end

    test "an entry naming a class that does not exist raises" do
      root = copy_rules()

      edit_entry(root, "pale_master", fn entry -> %{entry | "id" => "pale_mistress"} end)

      assert_raise RuntimeError, ~r/not a class/, fn -> Loader.load!(root) end
    end

    # The hand-written block goes through the same filter the machine one does,
    # so a key nothing checks cannot be smuggled in under a verdict of `applied`.
    test "an entry using a key the interpreter does not know raises" do
      root = copy_rules()

      edit_entry(root, "pale_master", fn entry ->
        put_in(entry["requirements"]["arcane_spellcasting"], 3)
      end)

      assert_raise RuntimeError, ~r/unknown keys/, fn -> Loader.load!(root) end
    end
  end

  describe "a `not_binding` entry closes the key without adding a check" do
    # Shifter's «Spellcasting: level 3 or higher» carries no «arcane» and no note
    # anywhere on its page saying what counts — so the page alone cannot settle
    # it. The game did: Dan, 03.08.2026 on the test server, a druid 5 with WIS 12
    # casts two circles of spells and is still offered the class. The line
    # therefore is not «able to cast third-circle spells», and since `wild shape`
    # has exactly one class as its source in the data — Druid, never available
    # before its 5th level — every legal shifter already satisfies it whatever
    # it means. Nothing left to check, so no gap either.
    test "the key leaves the unread list and no requirement appears", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala] do
        refute "spellcasting" in ruleset.classes[:shifter].requirements_unsupported
        refute {:missing_data, {:requirement, :shifter, "spellcasting"}} in ruleset.gaps

        # ...and the class is no harder to take than its feats make it: the entry
        # states no requirements, so none may appear. This is the half that
        # would turn a closed gap into a false refusal.
        refute Map.has_key?(ruleset.classes[:shifter].requirements, :any_of)
        refute Map.has_key?(ruleset.classes[:shifter].requirements, :caster_level)
        refute Map.has_key?(ruleset.classes[:shifter].requirements, :casts_spell_level)
        assert ruleset.classes[:shifter].requirements[:feats] == ["alertness", "wild_shape"]
      end
    end

    # ⚠️ The whole verdict rests on two facts about the data, so both are held
    # here rather than trusted: `wild shape` comes from no class but Druid, and
    # Druid never hands it out before its 5th level. Five druid levels are five
    # caster levels, which covers the three the requirement asks for — that is
    # *why* there is nothing left to check. The day a second class grants it, or
    # Druid starts granting it earlier, the reasoning stops holding and the
    # entry has to be reread. This is the test that will say so, instead of the
    # calculator quietly offering the class to someone the game refuses.
    #
    # ⚠️ 08.08.2026 (AGENT_QUEUE.md §7, волна 10): fixing the "bone_skin" parser
    # bug (`ClassPage.feat_grants/1`) also surfaced that Druid's own progression
    # table hands out `wild shape` again at levels 6, 7, 10, 14 and 18 — plain
    # text without a link, right after the linked grant at 5 — because it is a
    # growing uses-per-day count on the SAME ability, not a second class. That
    # is exactly what this test is set up to notice, so the assertion is split
    # into the two things the verdict actually needs — one class, one earliest
    # level — instead of one exact list of pairs that a correct fix like this
    # one was always going to grow.
    test "and the fact the verdict rests on is still true", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        granting =
          for {id, class} <- ruleset.classes,
              {level, feats} <- class.granted_feats,
              :wild_shape in feats,
              do: {id, level}

        classes = granting |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

        assert classes == [:druid],
               "wild shape is granted by #{inspect(granting)}, not by Druid alone — " <>
                 "the shifter entry in class_requirements.json argues from Druid being " <>
                 "the only source, so reread it."

        earliest = granting |> Enum.map(&elem(&1, 1)) |> Enum.min()

        assert earliest == 5,
               "wild shape's earliest grant is #{inspect(granting)}, not Druid 5 — " <>
                 "the shifter entry in class_requirements.json argues from level 5 being " <>
                 "the earliest it is ever available, so reread it."

        assert ruleset.feats[:wild_shape].prereqs["class_levels"] == %{"druid" => 5}
      end
    end

    # The verdict is a claim about *why* there is nothing to check, so an entry
    # cannot make it while also stating requirements — that would be an `applied`
    # entry wearing the wrong label, and the check would be silently ignored.
    test "and it may not state requirements while claiming to bind nothing" do
      root = copy_rules()

      edit_entry(root, "shifter", fn entry ->
        Map.put(entry, "requirements", %{"casts_spell_level" => 3})
      end)

      assert_raise RuntimeError, ~r/is "not_binding" but states requirements/, fn ->
        Loader.load!(root)
      end
    end

    # ...and it is still held to the machine layer, so the day the parser reads
    # that line the entry cannot go on quietly describing a place that changed.
    test "and it is guarded exactly like an applied one" do
      root = copy_rules()

      edit_entry(root, "shifter", fn entry ->
        put_in(entry["replaces"]["spellcasting"], "level 4 or higher")
      end)

      assert_raise RuntimeError, ~r/page moved under the entry/, fn -> Loader.load!(root) end
    end
  end

  # Требование к ЗНАЧЕНИЮ, с которым взят фит (`feat_choices`, 17.08.2026,
  # ответ Dan по Тайному лучнику). Ошибиться в такой записи можно тремя
  # способами, и все три молчат В СТОРОНУ РАЗРЕШЕНИЯ: правило считает
  # «значение не записано» за «не проверяем», поэтому опечатка не делает
  # требование строже — она стирает его целиком. Отсюда сторож в загрузчике,
  # а не отчёт.
  describe "сторож у требования к выбранному значению" do
    test "чистая копия грузится — иначе три `assert_raise` ниже зеленели бы впустую" do
      root = copy_rules()

      assert %{"siala_41" => siala} = Loader.load!(root)

      assert siala.classes[:arcane_archer].requirements[:feat_choices] == %{
               "weapon_focus" => ["shortbow", "longbow", "light_crossbow", "heavy_crossbow"]
             }
    end

    test "фит, которого нет в справочнике, роняет сборку" do
      root = copy_rules()
      edit_shard_choices(root, %{"weapon_focus_ranged" => ["longbow"]})

      assert_raise RuntimeError, ~r/which is not a feat/, fn -> Loader.load!(root) end
    end

    test "фит без выбора роняет сборку" do
      root = copy_rules()
      edit_shard_choices(root, %{"toughness" => ["longbow"]})

      assert_raise RuntimeError, ~r/takes no choice at all/, fn -> Loader.load!(root) end
    end

    test "значение вне домена роняет сборку" do
      root = copy_rules()
      edit_shard_choices(root, %{"weapon_focus" => ["longbow", "long_bow"]})

      assert_raise RuntimeError, ~r/not in domain weapon/, fn -> Loader.load!(root) end
    end

    test "пустой список роняет сборку" do
      root = copy_rules()
      edit_shard_choices(root, %{"weapon_focus" => []})

      assert_raise RuntimeError, ~r/non-empty list of values/, fn -> Loader.load!(root) end
    end
  end

  # 🔴 Задача 3.99, разряд 2. Требование «weapon focus **in a melee weapon**»
  # у Мастера оружия и Чемпиона Торма было непроверяемой оговоркой, и
  # `Weapon Focus (Longbow)` открывал оба класса — ложная легальность.
  describe "«в ближнем оружии» — требование, а не оговорка" do
    # Правило одно на оба ruleset'а: `ranged` заполнено у всех 47 записей
    # справочника в обоих, а Сиала требований этих классов не трогала.
    test "записано у обоих классов и на обоих ruleset'ах", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala], class <- [:weapon_master, :champion_of_torm] do
        assert ruleset.classes[class].requirements[:feat_choice_properties] ==
                 %{"weapon_focus" => %{"ranged" => false}}
      end
    end

    # ⚠ Оговорка снята ровно у того, у кого требование её заменило, и ровно
    # та фраза.
    #
    # ⚠ Здесь стояло, что у Мастера оружия остался ЧЕСТНЫЙ остаток — «unarmed
    # strike is excluded from the prerequisites», второе исключение его
    # страницы. Задача 3.107 выразила и его (`feat_choice_excludes`), поэтому
    # оговорок не осталось ни у одного из двух: печатать «не проверяем» про
    # проверенное запрещает CLAUDE.md §6 ровно так же, как молчать
    # о непосчитанном.
    test "фраза, ставшая правилом, из оговорок ушла", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala], class <- [:champion_of_torm, :weapon_master] do
        assert ruleset.classes[class].requirements[:qualifiers] == nil
      end

      # Положительный контроль: механизм оговорок жив, просто у этих двух
      # классов носителей не осталось. У ванильного Тайного лучника фраза
      # на месте — её требование выражено только у Сиалы.
      assert vanilla.classes[:arcane_archer].requirements[:qualifiers] ==
               ["(longbow or shortbow)"]
    end

    # Прогон по настоящему билду: лук отказывает, меч проходит. Обе половины
    # одним тестом — поодиночке каждая зеленеет на сломанной модели.
    test "лук закрывает класс, ближнее оружие открывает", %{siala: siala} do
      base =
        Build.new(
          levels: List.duplicate(:fighter, 8),
          base_abilities: %{str: 16, dex: 16, con: 14, int: 13, wis: 10, cha: 10},
          skills: Map.new(1..8, &{&1, %{intimidate: 1}}),
          feats: %{
            1 => %{general: :dodge},
            2 => %{{:class_bonus, :fighter} => :mobility},
            3 => %{general: :expertise},
            4 => %{{:class_bonus, :fighter} => :spring_attack},
            6 => %{general: :whirlwind_attack}
          }
        )

      bow = Build.put_feat(base, 5, {:class_bonus, :fighter}, :weapon_focus, :longbow)
      sword = Build.put_feat(base, 5, {:class_bonus, :fighter}, :weapon_focus, :longsword)

      assert Rules.validate_level_up(bow, :weapon_master, siala) ==
               {:error, [{:requires_feat_choice_property, :weapon_focus, :ranged, false}]}

      assert Rules.validate_level_up(sword, :weapon_master, siala) == :ok

      # Тот же контраст у Чемпиона Торма — у него своё требование по БАБ
      # и мировоззрению, поэтому билд другой.
      cot =
        Build.new(
          levels: List.duplicate(:fighter, 8),
          alignment: :lawful_good,
          base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 10}
        )

      assert Rules.validate_level_up(
               Build.put_feat(cot, 1, :general, :weapon_focus, :longbow),
               :champion_of_torm,
               siala
             ) == {:error, [{:requires_feat_choice_property, :weapon_focus, :ranged, false}]}

      assert Rules.validate_level_up(
               Build.put_feat(cot, 1, :general, :weapon_focus, :longsword),
               :champion_of_torm,
               siala
             ) == :ok
    end

    # 🔴 Гировый маршрут: требование КЛАССА фит с вещи выполняет (замер H7),
    # а с задачи 3.97 объявление несёт ЗНАЧЕНИЕ — значит и оно проверяется.
    # Именно так собран референсный билд Dan.
    test "значение с вещи класс видит", %{siala: siala} do
      base =
        Build.new(
          levels: List.duplicate(:fighter, 8),
          alignment: :lawful_good,
          base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 10}
        )

      worn = fn weapon -> %{base | gear: %Gear{feats: [{:weapon_focus, weapon}]}} end

      assert Rules.validate_level_up(worn.(:longbow), :champion_of_torm, siala) ==
               {:error, [{:requires_feat_choice_property, :weapon_focus, :ranged, false}]}

      assert Rules.validate_level_up(worn.(:longsword), :champion_of_torm, siala) == :ok

      # Значение не названо — молчим, а не отказываем: то же правило, что
      # у `feat_choices` (ссылка старше 3.97, текстовый импорт).
      assert Rules.validate_level_up(worn.(nil), :champion_of_torm, siala) == :ok
    end

    # ⚠ Метательное оружие Fandom объявляет дальнобойным (`ranged: true`
    # у всех четырёх), значит `Weapon Focus (Throwing axe)` Мастера оружия
    # не открывает. Следствие данных, и оно названо тестом, а не оставлено
    # молчаливым.
    test "метательное считается дальнобойным", %{siala: siala} do
      for id <- [:dart, :shuriken, :sling, :throwing_axe] do
        assert siala.weapons[id].ranged?, "#{id}"
      end

      # Положительный контроль: поле различает состояния, а не всегда true.
      refute siala.weapons[:handaxe].ranged?
    end
  end

  # 🔴 Задача 3.107. Замер Dan 26.08.2026 (кейс AC1): «сначала взял weapon focus
  # на unarmed strike и данные престиж классы были мне НЕ ДОСТУПНЫ. Как только
  # взял weapon focus на club, оба сразу появились в доступе».
  #
  # 🔴 Дубина здесь — не третий пример, а суть замера: она не требует владения
  # ВОВСЕ (`no_proficiency_required`, замер Dan 16.08.2026). Значит дело не во
  # владении оружием — иначе дубина открыла бы классы не лучше рукопашного
  # удара, — а в том, что рукопашный удар для этого требования оружием
  # не считается.
  #
  # Источник правила — `fandom:Unarmed strike` (revid 66545, Notes), и он
  # называет ОБА класса поимённо: «this focus does not satisfy the "weapon focus
  # in a melee ''weapon''" requirement for the champion of Torm and weapon
  # master prestige classes».
  describe "рукопашный удар требование Weapon focus не удовлетворяет" do
    # Правило ванильное (страница оружия — про ванильные классы), поэтому оно
    # одно на оба ruleset'а, как и `ranged: false` рядом.
    test "записано у обоих классов и на обоих ruleset'ах", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala], class <- [:weapon_master, :champion_of_torm] do
        assert ruleset.classes[class].requirements[:feat_choice_excludes] ==
                 %{"weapon_focus" => ["unarmed_strike"]}
      end
    end

    # Таблица целиком, одним тестом: четыре оружия × два класса × два ruleset'а.
    # Порознь любая строка зеленеет и на сломанной модели — «рукопашный
    # отказывает» верно и у модели, которая отказывает всем.
    #
    # 🔴 Дубина — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ и главная строка таблицы: ложная
    # нелегальность здесь была бы прямым опровержением замера.
    test "дубина открывает, рукопашный удар — нет", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        assert refusal(ruleset, :weapon_master, :unarmed_strike) ==
                 [{:requires_feat_choice_other_than, :weapon_focus, [:unarmed_strike]}]

        assert refusal(ruleset, :champion_of_torm, :unarmed_strike) ==
                 [{:requires_feat_choice_other_than, :weapon_focus, [:unarmed_strike]}]

        assert refusal(ruleset, :weapon_master, :club) == []
        assert refusal(ruleset, :champion_of_torm, :club) == []

        assert refusal(ruleset, :weapon_master, :longsword) == []
        assert refusal(ruleset, :champion_of_torm, :longsword) == []

        # Правило задачи 3.99 цело: дальнобойное по-прежнему отказывает,
        # и отказывает СВОИМ отказом, а не новым.
        assert refusal(ruleset, :weapon_master, :longbow) ==
                 [{:requires_feat_choice_property, :weapon_focus, :ranged, false}]

        assert refusal(ruleset, :champion_of_torm, :longbow) ==
                 [{:requires_feat_choice_property, :weapon_focus, :ranged, false}]
      end
    end

    # 🔴 Исключение СУЖАЕТ то, что считается взятием, а не проверяется отдельно
    # от свойства, — и вот билд, на котором разница видна. Двумя независимыми
    # проверками он прошёл бы: «ближний фокус есть» (рукопашный не
    # дальнобойный) И «неисключённый фокус есть» (лук), — хотя в игре
    # не годится ни один из двух. Фит повторяем, билд собирается без единой
    # правки руками.
    test "лук плюс рукопашный удар не складываются в годное взятие", %{siala: siala} do
      both =
        base_fighter()
        |> Build.put_feat(5, {:class_bonus, :fighter}, :weapon_focus, :longbow)
        |> Build.put_feat(7, :general, :weapon_focus, :unarmed_strike)

      for class <- [:weapon_master, :champion_of_torm] do
        assert Rules.validate_level_up(both, class, siala) ==
                 {:error, [{:requires_feat_choice_property, :weapon_focus, :ranged, false}]}
      end

      # Положительный контроль той же формы: лишний рукопашный фокус рядом
      # с ГОДНЫМ ничего не отбирает — в игре мечом владеет тот же персонаж.
      ok =
        base_fighter()
        |> Build.put_feat(5, {:class_bonus, :fighter}, :weapon_focus, :longsword)
        |> Build.put_feat(7, :general, :weapon_focus, :unarmed_strike)

      for class <- [:weapon_master, :champion_of_torm] do
        assert Rules.validate_level_up(ok, class, siala) == :ok
      end
    end

    # Отказ печатается только тогда, когда взятия БЫЛИ, а после сужения
    # не осталось ни одного. Фита нет вовсе — про это говорит ключ `feats`,
    # и две причины на один пустой слот читались бы как две разные пропажи.
    test "без фита вовсе причина прежняя", %{siala: siala} do
      for class <- [:weapon_master, :champion_of_torm] do
        assert Rules.validate_level_up(base_fighter(), class, siala) ==
                 {:error, [{:requires_feat, :weapon_focus}]}
      end
    end

    # 🔴 Гировый маршрут: требование КЛАССА фит с вещи выполняет (замер H7),
    # значение объявления читается с 3.97 — значит и исключение действует.
    test "значение с вещи исключается так же", %{siala: siala} do
      worn = fn weapon -> %{base_fighter() | gear: %Gear{feats: [{:weapon_focus, weapon}]}} end

      for class <- [:weapon_master, :champion_of_torm] do
        assert Rules.validate_level_up(worn.(:unarmed_strike), class, siala) ==
                 {:error, [{:requires_feat_choice_other_than, :weapon_focus, [:unarmed_strike]}]}

        assert Rules.validate_level_up(worn.(:club), class, siala) == :ok

        # Значение не названо — молчим, а не отказываем: то же правило, что
        # у `feat_choices` (ссылка старше 3.97, текстовый импорт).
        assert Rules.validate_level_up(worn.(nil), class, siala) == :ok
      end
    end

    # ⚠ Соседнее природное оружие НЕ тронуто и намеренно: предложение источника
    # его не называет, замер его не проверял, а страница `Unarmed strike`
    # в соседнем абзаце природное оружие и рукопашный удар прямо РАЗВОДИТ.
    # Растянуть замер на соседа — ход, которым дважды ломались потолки (§9).
    test "оружие существа под исключение не попало", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala], class <- [:weapon_master, :champion_of_torm] do
        assert refusal(ruleset, class, :creature_weapon) == []
      end
    end
  end

  describe "сторож у требования к свойству выбранного значения" do
    test "свойство, которого ядро не читает, роняет сборку" do
      root = copy_rules()

      edit_entry(root, "weapon_master", fn entry ->
        put_in(entry["requirements"]["feat_choice_properties"], %{
          "weapon_focus" => %{"shiny" => true}
        })
      end)

      assert_raise RuntimeError, ~r/cannot read off a weapon record/, fn -> Loader.load!(root) end
    end

    test "фит, которого нет в справочнике, роняет сборку" do
      root = copy_rules()

      edit_entry(root, "weapon_master", fn entry ->
        put_in(entry["requirements"]["feat_choice_properties"], %{
          "weapon_focus_melee" => %{"ranged" => false}
        })
      end)

      assert_raise RuntimeError, ~r/which is not a feat/, fn -> Loader.load!(root) end
    end

    test "пустая карта свойств роняет сборку" do
      root = copy_rules()

      edit_entry(root, "weapon_master", fn entry ->
        put_in(entry["requirements"]["feat_choice_properties"], %{"weapon_focus" => %{}})
      end)

      assert_raise RuntimeError, ~r/not a non-empty map/, fn -> Loader.load!(root) end
    end

    # 🔴 Сторож у исключения (задача 3.107). Ошибка в имени молчит в сторону
    # РАЗРЕШЕНИЯ: исключение не совпадёт ни с чем, класс откроется тому, кому
    # в игре он закрыт, — ровно та ложная легальность, ради снятия которой ключ
    # и заведён.
    test "исключённое значение вне домена роняет сборку" do
      root = copy_rules()

      edit_entry(root, "weapon_master", fn entry ->
        put_in(entry["requirements"]["feat_choice_excludes"], %{
          "weapon_focus" => ["unarmed_strikes"]
        })
      end)

      assert_raise RuntimeError, ~r/not in domain weapon/, fn -> Loader.load!(root) end
    end

    test "исключение у фита без выбора роняет сборку" do
      root = copy_rules()

      edit_entry(root, "weapon_master", fn entry ->
        put_in(entry["requirements"]["feat_choice_excludes"], %{"toughness" => ["unarmed_strike"]})
      end)

      assert_raise RuntimeError, ~r/takes no choice at all/, fn -> Loader.load!(root) end
    end

    test "пустой список исключений роняет сборку" do
      root = copy_rules()

      edit_entry(root, "weapon_master", fn entry ->
        put_in(entry["requirements"]["feat_choice_excludes"], %{"weapon_focus" => []})
      end)

      assert_raise RuntimeError, ~r/non-empty list of values/, fn -> Loader.load!(root) end
    end

    # ⚠ Снятая фраза сверяется с тем, что реально написано в машинном слое:
    # опечатка здесь означала бы, что оговорка осталась на месте, а запись
    # выглядит применённой — молчаливое расхождение того же вида, что ловит
    # `replaces` у соседей.
    test "снимаемая фраза обязана быть на месте" do
      root = copy_rules()

      edit_entry(root, "weapon_master", fn entry ->
        Map.put(entry, "supersedes_qualifiers", ["in a melee weapons"])
      end)

      assert_raise RuntimeError, ~r/which vanilla\/classes.json does not state/, fn ->
        Loader.load!(root)
      end
    end
  end

  # A full copy of `priv/rules`, so `load!/1` sees everything it normally does
  # and only the one file under test differs.
  # Воин 12 со всеми прочими требованиями обоих классов: фиты Мастера оружия,
  # ранги Устрашения, мировоззрение и БАБ Чемпиона Торма. Фокус оружия НЕ взят —
  # его добавляет каждый вызов, и он и есть переменная таблицы.
  defp base_fighter do
    Build.new(
      levels: List.duplicate(:fighter, 12),
      alignment: :lawful_good,
      base_abilities: %{str: 16, dex: 16, con: 14, int: 13, wis: 10, cha: 10},
      skills: Map.new(1..12, &{&1, %{intimidate: 1}}),
      feats: %{
        1 => %{general: :dodge},
        2 => %{{:class_bonus, :fighter} => :mobility},
        3 => %{general: :expertise},
        4 => %{{:class_bonus, :fighter} => :spring_attack},
        6 => %{general: :whirlwind_attack}
      }
    )
  end

  # Причины отказа взять класс с `Weapon focus` на названном оружии.
  #
  # ⚠ Одна причина отбрасывается, и она не про это правило: у ВАНИЛЬНОГО
  # ruleset'а нет лимита классов вовсе, поэтому каждый его левелап в престиж
  # несёт `{:missing_data, :max_classes}` — одинаково на всех восьми клетках
  # таблицы, до правки и после. Оставить её значило бы писать одно и то же
  # в каждой строке; отбросить молча — потерять причину, поэтому она названа.
  defp refusal(ruleset, class, weapon) do
    build = Build.put_feat(base_fighter(), 5, {:class_bonus, :fighter}, :weapon_focus, weapon)

    case Rules.validate_level_up(build, class, ruleset) do
      :ok -> []
      {:error, reasons} -> reasons -- [{:missing_data, :max_classes}]
    end
  end

  defp copy_rules do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  # Оба ruleset'а, а не один: слой Сиалы может перекрыть требование сверху, и
  # тогда «убрали файл — гэп вернулся» надо спрашивать у ванили, где над ним
  # ничего не лежит.
  defp load_without_file do
    root = copy_rules()
    File.rm!(Path.join(root, @path))
    Loader.load!(root)
  end

  # Правит `feat_choices` внутри применяемого требования Тайного лучника
  # в СИАЛЬСКОМ слое — там, где эта запись и живёт (ванильная половина её
  # не несёт вовсе и не должна).
  defp edit_shard_choices(root, choices) do
    path = Path.join(root, "siala_41/classes.json")
    data = path |> File.read!() |> Jason.decode!()

    classes =
      Enum.map(data["classes"], fn class ->
        if class["id"] == "arcane_archer" do
          changes =
            Enum.map(class["changes"], fn change ->
              if change["what"] == "requirements",
                do: put_in(change["value"]["feat_choices"], choices),
                else: change
            end)

          %{class | "changes" => changes}
        else
          class
        end
      end)

    File.write!(path, Jason.encode!(%{data | "classes" => classes}))
  end

  defp edit_entry(root, id, fun) do
    path = Path.join(root, @path)
    data = path |> File.read!() |> Jason.decode!()

    entries =
      Enum.map(data["classes"], fn entry ->
        if entry["id"] == id, do: fun.(entry), else: entry
      end)

    File.write!(path, Jason.encode!(%{data | "classes" => entries}))
  end
end
