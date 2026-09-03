defmodule BuildCalculator.Data.FeatRequirementsTest do
  @moduledoc """
  The hand-written layer over a feat's own prerequisites.

  `priv/rules/vanilla/feat_requirements.json` exists for the same reason
  `class_requirements.json` does, one level down: `Curse song` carries
  `prereq=-` on Fandom, and the class it is actually usable by («Harper scout
  is the only other class that can select this») sits in a "Notes" sentence a
  parser never reaches. Before this file, `prereqs: null` read as "anyone may
  take it" — a false legality (AGENT_QUEUE.md §1.6).

  Mirrors `class_requirements_test.exs` on purpose: same wiring guard, same
  two drift guards, same "take the file away and watch the bug come back".

  ⚠️ Файл несёт **пять семейств**, и только первые два — про требования
  к персонажу (третье заведено 10.08.2026, пятое 11.08.2026).

    1. ограничение по классу, названное прозой вне блока `prereq=` (`curse_song`):
       ошибка была «слишком можно»;
    2. требование, называющее СТУПЕНЬ фита (`[[greater rage]] (6x per day)`),
       которую страница переводит в уровень класса в собственных «Notes». Три
       эпических фита варвара были из-за этой ступени **недостижимы вовсе** —
       ошибка «слишком нельзя», зеркало первой;
    3. ограничение на то, НА КАКОМ уровне тратится слот — «only be selected when
       leveling as a barbarian». Не требование вовсе: `only_on_class_levels`
       разворачивается в дополнение по классам и попадает в `unavailable_feats`,
       то есть в тот же механизм, которым работают запреты со страниц классов.
       Своей формы причины у него нет намеренно — довод в `_note` файла.
    4. то же ограничение, но зависящее от **выбранного значения**, а не от фита
       (`Epic skill focus`): «in [[perform]] can be taken only when gaining a
       [[bard]] level». Запретить фит классу целиком здесь нельзя — воин законно
       берёт его на 26 других навыках, — поэтому ключ
       `only_on_class_levels_for_skill` читает `Rules.Prereqs`, и форма отказа
       СВОЯ: `{:requires_leveling_as, [классы]}`;
    5. ограничение на **слот**, тоже зависящее от значения (та же страница):
       «in ''use magic device'' cannot be selected as a rogue bonus feat, but
       otherwise bonus feat availability matches general feat availability».
       Ключ `not_in_class_bonus_slot_for_skill`, читает
       `Rules.FeatSlots.choice_refusals/4` — единственное место, где в руках
       и слот, и выбор, — форма `{:not_in_class_bonus_slot, class}`;
    6. требование к ЗНАЧЕНИЮ, включаемое СВОЙСТВОМ значения, а не списком имён
       (`skill_focus`, задача 3.104): «in a skill that requires training … has
       at least one rank in it». Ключ `chosen_skill_ranks_if_trained_only`
       читает признак навыка из словаря ruleset'а, поэтому ни одного имени
       навыка в требовании нет;
    7. требование к СОСТАВУ БИЛДА, включаемое значением (там же): «in perform
       can be taken when leveling in ANY class, as long as … at least one bard
       level». Ключ `class_levels_for_skill`. ⚠️ С четвёртым не схлопывается
       и схлопнуться не может: то про класс УРОВНЯ, это про состав билда,
       и бард-воин на воинском уровне разводит их живьём;
    8. отсутствие ПАРЫ «фит + значение» (там же): «There is no skill focus in
       ride». Не требование вовсе, поэтому и форма отказа не «чего-то
       не хватает», а `{:invalid_choice, feat, value}` — та же, которой словарь
       выбора отбивает значение вне домена.

  Все восемь проверяются здесь, и сторожа у них общие.

  ⚠️ Семейства 6–8 пришли одной задачей и с одной страницы: `fandom:Skill
  focus` несёт четыре предложения `Notes` четырёх разных форм, и попытка
  выразить их одним ключом соврала бы минимум дважды.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatSlots, Gear}
  alias BuildCalculatorWeb.Builder.Feats

  @path "vanilla/feat_requirements.json"

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  describe "the file is wired in" do
    # ⚠ `source_files/0` registers the `vanilla` **directory**, whose mtime
    # moves when a file is added and not when one is edited. A hand-written
    # file only covered by the directory entry would go on being compiled
    # from a stale copy after every edit.
    test "registered by name, not merely by its directory" do
      assert @path in Loader.source_files()
    end

    # Every `vanilla/*.json` that is not a rules file is read as a dictionary
    # a feat's parameter may be drawn from. A new rules file that forgets to
    # say so would quietly become a choice domain named `feat_requirements`.
    test "is not mistaken for a choice domain", %{siala: siala} do
      refute Map.has_key?(siala.choice_domains, :feat_requirements)
      refute Map.has_key?(siala.choice_domains, :feat_requirement)

      # Positive control: the mechanism it is being kept out of is alive.
      assert Map.has_key?(siala.choice_domains, :creature_type)
    end

    # It is a vanilla fact — Fandom's own prose about a vanilla feat — so the
    # shard ruleset inherits it rather than restating it.
    test "both rulesets carry the reading", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        assert ruleset.feats[:curse_song].prereqs == %{
                 "any_of" => [
                   %{"class_levels" => %{"bard" => 1}},
                   %{"class_levels" => %{"harper_scout" => 1}}
                 ]
               }
      end
    end
  end

  describe "curse_song is takeable by exactly the two classes the page names" do
    # The bug as Dan found it: `prereqs: null` meant "anyone". Fighter is not
    # named anywhere on the page, in `bonus_for` (`bard`, `harper_scout` only)
    # or in Notes, so a fighter must be refused.
    test "a class the source does not name is refused", %{vanilla: vanilla, siala: siala} do
      build = Build.new(alignment: :neutral, race: :human) |> Build.add_level(:fighter)

      for ruleset <- [vanilla, siala] do
        assert {:error, reasons} = Rules.validate_feat(build, :curse_song, ruleset)
        assert {:requires_any_of, _branches} = List.keyfind(reasons, :requires_any_of, 0)
      end
    end

    test "no class at all is refused the same way", %{vanilla: vanilla, siala: siala} do
      build = Build.new(alignment: :neutral, race: :human)

      for ruleset <- [vanilla, siala] do
        assert {:error, _reasons} = Rules.validate_feat(build, :curse_song, ruleset)
      end
    end

    # The two classes the source names, each on its own — «Harper scout is
    # the only OTHER class that can select this» is a second, independent
    # branch, not a synonym for bard.
    test "a bard may take it", %{vanilla: vanilla, siala: siala} do
      build = Build.new(alignment: :neutral, race: :human) |> Build.add_level(:bard)

      for ruleset <- [vanilla, siala] do
        assert Rules.validate_feat(build, :curse_song, ruleset) == :ok
      end
    end

    test "a harper scout may take it", %{vanilla: vanilla, siala: siala} do
      build = Build.new(alignment: :neutral, race: :human) |> Build.add_level(:harper_scout)

      for ruleset <- [vanilla, siala] do
        assert Rules.validate_feat(build, :curse_song, ruleset) == :ok
      end
    end

    # ⚠ Positive control required by AGENT_QUEUE.md §1.6: a feat that carries
    # no class restriction at all must stay open to a class named nowhere
    # near it, so this suite cannot pass by having quietly restricted
    # everything. `toughness` names no class in its own prereqs.
    test "a feat with no restriction stays open to any class (positive control)", %{
      vanilla: vanilla,
      siala: siala
    } do
      build = Build.new(alignment: :neutral, race: :human) |> Build.add_level(:fighter)

      for ruleset <- [vanilla, siala] do
        assert Rules.validate_feat(build, :toughness, ruleset) == :ok
      end
    end
  end

  describe "the other three feats named in the ticket are left untouched" do
    # `two_weapon_fighting`, `weapon_proficiency_martial` and
    # `weapon_proficiency_simple` carry the same category and the same
    # `prereqs: null`, but no page names which classes — inventing a list
    # would be exactly what CLAUDE.md §3 forbids. They stay open to everyone,
    # same as before this file existed. Что с ними делает ШАРД — три разные
    # истории (ничего / выключил / выдаёт всем), и ни одна из них не про
    # требования, ради которых этот файл заведён.
    test "still available to any class — no source names one to exclude", %{
      vanilla: vanilla,
      siala: siala
    } do
      build = Build.new(alignment: :neutral, race: :human) |> Build.add_level(:wizard)

      # То, ради чего этот файл существует, у всех трёх не изменилось: ни у одного
      # нет требований вовсе, значит и списка классов, который этот файл мог бы
      # придумать, нет ни в одном ruleset'е.
      for ruleset <- [vanilla, siala],
          id <- [:two_weapon_fighting, :weapon_proficiency_martial, :weapon_proficiency_simple] do
        assert ruleset.feats[id].prereqs == nil
      end

      # А доступность разошлась, и разошлась НЕ по классу — по совсем другому
      # правилу: замер H5 (`GAME_CHECKS.md`, Dan 09.08.2026) выключил ванильные
      # владения оружием на Сиале. Отказ приходит формой `{:feat_disabled, id}`,
      # а не `{:forbidden_by_class, …}`, и именно это тест обязан различать —
      # иначе выключение фита однажды спрячется за ограничением по классу,
      # которого никто не вводил.
      assert Rules.validate_feat(build, :two_weapon_fighting, vanilla) == :ok
      assert Rules.validate_feat(build, :two_weapon_fighting, siala) == :ok

      assert Rules.validate_feat(build, :weapon_proficiency_martial, vanilla) == :ok

      assert Rules.validate_feat(build, :weapon_proficiency_martial, siala) ==
               {:error, [{:feat_disabled, :weapon_proficiency_martial}]}

      # ⚠️ `weapon_proficiency_simple` из этой пары ВЫБЫЛ 26.08.2026 (задача
      # 3.112): здесь стояло «выключил владения оружием ЦЕЛИКОМ» и цикл по двум
      # id сразу. Прочтение замера H5 оказалось неверным именно для `simple` —
      # шард его не выключал, а выдаёт всем классам на 1-м уровне, что показали
      # три игровых лога `.билд`. Требований у фита по-прежнему нет, поэтому сам
      # по себе он законен на обоих ruleset'ах; слот на него не тратится потому,
      # что персонаж им уже владеет, а это уже вопрос билда, а не требований, —
      # и он под тестом в `siala_feat_layer_test.exs`.
      assert Rules.validate_feat(build, :weapon_proficiency_simple, vanilla) == :ok
      assert Rules.validate_feat(build, :weapon_proficiency_simple, siala) == :ok
    end

    # 🔴 ЗДЕСЬ СТОЯЛО «skill_focus and improved_sneak_attack still refuse on their
    # own unrelated gap» — а потом «верно только для ПЕРВОГО» (3.103). С задачи
    # 3.104 (25.08.2026) неверно и это: `skill_focus` прочитан тоже, и настоящих
    # сырых остатков в справочнике не осталось ни одного. Тест переписан, а не
    # удалён, потому что он держит ту же РАЗНИЦУ, только с другой стороны: у обоих
    # фитов отказ сменил природу с «мы не прочитали требование» на «требование
    # не выполнено», и обвинять пустой пик `skill_focus` больше нечем.
    test "оба фита прочитаны: отказ по требованию, а не по непрочитанной прозе", %{
      vanilla: vanilla,
      siala: siala
    } do
      rogue1 = Build.new(alignment: :neutral, race: :human) |> Build.add_level(:rogue)
      rogue15 = Build.new(alignment: :neutral, race: :human, levels: List.duplicate(:rogue, 15))

      for ruleset <- [vanilla, siala] do
        # ⚠️ Пик БЕЗ значения: все четыре ключа `skill_focus` спрашивают про
        # выбранный навык, значит сравнивать не с чем — и молчание тут верное,
        # то же самое, что у `feat_choices` и `only_on_class_levels_for_skill`.
        # До 3.104 здесь стоял безусловный отказ ВСЕМ.
        assert Rules.validate_feat(rogue1, :skill_focus, ruleset) == :ok

        # А с названным значением правило работает: Вор 1 без рангов Кувырка
        # (навык требует тренировки) фит не получает, с одним рангом — получает.
        assert Rules.validate_feat(rogue1, %{feat: :skill_focus, choice: :tumble}, ruleset) ==
                 {:error, [{:requires_chosen_skill_ranks, :tumble, 1}]}

        # А у соседа отказ сменил природу: был «мы не прочитали требование»,
        # стал «требование не выполнено», и он называет все три ветки сразу.
        assert Rules.validate_feat(rogue1, :improved_sneak_attack, ruleset) ==
                 {:error,
                  [
                    requires_any_of: [
                      [{:requires_class_level, :rogue, 15}],
                      [{:requires_class_level, :blackguard, 25}],
                      [{:requires_class_level, :assassin, 15}]
                    ]
                  ]}

        # 🔴 Главная половина: раньше фит отказывал СТРОЖЕ нужного — не пускал
        # и тех, у кого сникдайс есть по-настоящему. Ложная нелегальность снята.
        assert Rules.validate_feat(rogue15, :improved_sneak_attack, ruleset) == :ok
      end
    end

    # ⚠ Ловушка, из-за которой ветки записаны уровнем класса, а не фитом: id
    # `sneak_attack` вор получает на ПЕРВОМ уровне, то есть `feats:
    # ["sneak_attack"]` не ослабило бы требование, а стёрло бы его. Та же пара
    # тестов уже стоит у `mighty_rage` (`Data.RepeatedGrantsTest`); здесь она
    # повторена потому, что ловушка сработала бы на другом фите и другой семье.
    test "ветка вора стоит на 15-м уровне, а не на владении сникдайсом", %{
      vanilla: vanilla,
      siala: siala
    } do
      rogue1 = Build.new(alignment: :neutral, race: :human) |> Build.add_level(:rogue)

      for ruleset <- [vanilla, siala] do
        # Фит у вора 1 уже есть — и требование это НЕ засчитывает.
        assert MapSet.member?(Build.feats_owned(rogue1, ruleset, 1), :sneak_attack)
        assert Rules.validate_feat(rogue1, :improved_sneak_attack, ruleset) != :ok

        refute "feats" in Map.keys(ruleset.feats[:improved_sneak_attack].prereqs)
      end
    end
  end

  describe "what the file does, shown by taking it away" do
    # The strongest positive control available: without the file, curse_song
    # goes back to being takeable by a character the source never names — the
    # exact false legality AGENT_QUEUE.md §1.6 was opened over.
    #
    # ⚠️ Здесь стояло «без файла воин берёт Curse song», и с 08.08.2026 это
    # больше не так — но не потому, что файл перестал работать, а потому что
    # ту же дыру закрыл ВТОРОЙ, независимый источник: у 21 класса из 23
    # `curse_song` стоит в `unavailable_feats` («These general feats cannot be
    # selected when taking a level of fighter»), и не стоит ровно у двух — барда
    # и Арфиста, то есть у тех же, что называет проза Notes, прочитанная в этот
    # файл руками. Две стороны вики сошлись на одном списке.
    #
    # Поэтому «легальность возвращается» проверяется там, где перекрытия нет —
    # у персонажа БЕЗ уровней: списка класса тогда никакого, и остаётся ровно
    # то, что даёт файл. А на воине показано, какая именно причина исчезает.
    test "removing it brings the false legality back" do
      root = copy_rules()
      File.rm!(Path.join(root, @path))
      drop_shard_readers_of_this_file(root)
      ruleset = Loader.load!(root)["siala_41"]

      refute Map.has_key?(ruleset.feats[:curse_song].prereqs || %{}, "any_of")

      assert Rules.validate_feat(Build.new(race: :human), :curse_song, ruleset) == :ok

      build = Build.new(alignment: :neutral, race: :human) |> Build.add_level(:fighter)

      assert Rules.validate_feat(build, :curse_song, ruleset) ==
               {:error, [forbidden_by_class: :fighter]}
    end

    # Позитивный контроль к предыдущему: с файлом у воина причин ДВЕ, и одна
    # из них — та самая, что исчезает без файла. Без этой пары обе половины
    # выглядят правильными и при сломанном файле тоже.
    test "with the file the same fighter is refused twice, by two sources", %{siala: siala} do
      build = Build.new(alignment: :neutral, race: :human) |> Build.add_level(:fighter)

      assert {:error, reasons} = Rules.validate_feat(build, :curse_song, siala)
      assert {:forbidden_by_class, :fighter} in reasons
      assert {:requires_any_of, _branches} = List.keyfind(reasons, :requires_any_of, 0)
    end
  end

  # Второе семейство этого файла (10.08.2026): требование называет СТУПЕНЬ фита
  # (`[[greater rage]] (6x per day)`), а страница переводит её в уровень класса
  # сама. До этого три эпических фита варвара были недостижимы ВОВСЕ — не
  # «трудны», а отказывали каждому билду формой `{:missing_data,
  # {:feat_prerequisites, id}}`, потому что `prereqs.unparsed` заставляет ядро
  # отказаться проверять фит целиком (`Rules.Prereqs.unread/1`).
  #
  # source: fandom:Mighty rage (revid 69992) — Notes: «This feat's prerequisites
  # require barbarian level 20»; fandom:Thundering rage (revid 68111) — «obtained
  # at barbarian level 15»; fandom:Terrifying rage (revid 70525) — «only 15 of
  # them need to be barbarian levels». Все три снято 01.08.2026.
  describe "три эпических фита варвара: ступень записана уровнем класса" do
    # ⚠️ Порядок уровней важен: intimidate — классовый навык варвара, и потолок
    # ранга берётся от класса, взятого ИМЕННО на этом уровне (CLAUDE.md §6).
    # Варварские уровни поэтому стоят последними, иначе 25 рангов не набрать.
    defp barbarian_build(barbarian_levels, total) do
      filler = total - barbarian_levels

      ranks =
        for level <- (filler + 1)..total, into: %{} do
          if level == filler + 1,
            do: {level, %{intimidate: level + 3}},
            else: {level, %{intimidate: 1}}
        end

      Build.new(
        race: :human,
        alignment: :chaotic_good,
        base_abilities: %{str: 25, dex: 12, con: 21, int: 14, wis: 10, cha: 8},
        levels: List.duplicate(:fighter, filler) ++ List.duplicate(:barbarian, barbarian_levels),
        skills: ranks
      )
    end

    @levels [mighty_rage: 20, thundering_rage: 15, terrifying_rage: 15]

    test "требование прочитано в структуру, `unparsed` не осталось", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala], {id, level} <- @levels do
        prereqs = ruleset.feats[id].prereqs

        assert prereqs["class_levels"] == %{"barbarian" => level}
        assert prereqs["character_level"] == 21
        refute Map.has_key?(prereqs, "unparsed")
      end
    end

    # ⚠️ Две половины одной проверки, и по отдельности каждая зеленеет при
    # неверной модели: «стало можно» проходит и у требования, выкинутого вовсе,
    # а «на уровень раньше нельзя» — и у фита, недоступного всем.
    test "на нужном уровне класса берётся, на уровень раньше — нет", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala], {id, level} <- @levels do
        assert Rules.validate_feat(barbarian_build(level, 24), id, ruleset) == :ok,
               ":#{id} недоступен варвару #{level} — тому самому уровню, который называет вики"

        assert {:error, reasons} =
                 Rules.validate_feat(barbarian_build(level - 1, 24), id, ruleset)

        assert {:requires_class_level, :barbarian, level} in reasons,
               ":#{id} открылся варвару #{level - 1}"
      end
    end

    # `character_level: 21` рядом с `class_levels` не избыточен: варвар 20 — это
    # 20 уровней персонажа, а страница требует 21-й. Без этой проверки запись
    # могла бы потерять половину требования незаметно.
    test "уровень персонажа проверяется отдельно от уровня класса", %{siala: siala} do
      # Варвар 20 и ровно 20 уровней персонажа: класс набран, персонаж — нет.
      build = barbarian_build(20, 20)

      assert {:error, reasons} = Rules.validate_feat(build, :mighty_rage, siala)
      assert {:requires_character_level, 21} in reasons
      refute {:requires_class_level, :barbarian, 20} in reasons
    end

    # Положительный контроль к трём `refute` выше: 21-й уровень у билда есть, и
    # эпический фит, требования которого схема несла и раньше, на нём берётся —
    # значит отказы выше про ступень, а не про «в эпике всё запрещено».
    test "положительный контроль: другой эпический фит на том же билде берётся", %{siala: siala} do
      assert Rules.validate_feat(barbarian_build(14, 24), :epic_prowess, siala) == :ok
    end

    # Порча, которая и есть та самая ошибка: ступень, записанная как владение
    # фитом семьи. `barbarian_rage` есть у варвара с 1-го уровня, поэтому
    # требование не ослабевает, а ИСЧЕЗАЕТ — воин 20 / варвар 1 получает `:ok`.
    test "записать ступень как `feats: [barbarian_rage]` — ложная легальность", %{siala: siala} do
      root = copy_rules()

      edit_entry(root, "mighty_rage", fn entry ->
        put_in(entry["requirements"], %{
          "character_level" => 21,
          "abilities" => %{"con" => 21, "str" => 21},
          "feats" => ["barbarian_rage"]
        })
      end)

      ruleset = Loader.load!(root)["siala_41"]

      dip =
        Build.new(
          race: :human,
          alignment: :chaotic_good,
          base_abilities: %{str: 21, dex: 12, con: 21, int: 10, wis: 10, cha: 8},
          levels: List.duplicate(:fighter, 20) ++ [:barbarian]
        )

      # Положительный контроль: id действительно на руках, иначе `:ok` ниже
      # ничего бы не доказывал.
      assert :barbarian_rage in Build.feats_permanent(dip, ruleset, 21)
      assert Rules.validate_feat(dip, :mighty_rage, ruleset) == :ok

      # А с настоящей записью тот же билд получает отказ по уровню класса.
      assert {:error, reasons} = Rules.validate_feat(dip, :mighty_rage, siala)
      assert {:requires_class_level, :barbarian, 20} in reasons
    end

    # Обратная порча: без файла все три возвращаются в «недостижимы вовсе».
    test "без файла три фита снова отказывают всем «требование не прочитано»" do
      root = copy_rules()
      File.rm!(Path.join(root, @path))
      drop_shard_readers_of_this_file(root)
      ruleset = Loader.load!(root)["siala_41"]

      for {id, level} <- @levels do
        assert Rules.validate_feat(barbarian_build(level, 24), id, ruleset) ==
                 {:error, [missing_data: {:feat_prerequisites, id}]}
      end
    end
  end

  # Третье семейство файла (10.08.2026): ограничение не на характеристики и не на
  # состав билда, а на то, НА КАКОМ уровне тратится слот — «This feat can only be
  # selected when leveling as a [[barbarian]]» (`fandom:Mighty rage`, revid 69992).
  #
  # Своей формы причины у него нет намеренно: список разворачивается в дополнение
  # по классам ruleset'а и попадает в `unavailable_feats`, то есть в тот же
  # механизм и ту же причину `{:forbidden_by_class, class}`, которыми работают
  # 229 пар запрета со страниц классов. Довод — измерение: у четырёх НЕэпических
  # членов семейства класс-листы вики совпадают с этим дополнением точно.
  # 🔴 Задача 3.99, разряд 2. «proficiency with the chosen weapon» у
  # `Weapon focus` и `Improved critical` стояло непроверяемой оговоркой, и
  # `Weapon Focus (Scimitar)` брался персонажем без единого фита владения.
  describe "«владение выбранным оружием»: правило одно, ответ зависит от данных" do
    @asks [:weapon_focus, :improved_critical]

    test "ключ записан у обоих фитов и на обоих ruleset'ах, оговорки нет", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala], id <- @asks do
        assert ruleset.feats[id].prereqs["proficiency_with_chosen_weapon"] == true
        refute Map.has_key?(ruleset.feats[id].prereqs, "qualifiers")
        assert Rules.feat_caveats(id, ruleset) == []
      end

      # Пороги БАБ повторены записью, потому что она заменяет блок целиком.
      # Потеряться они не имеют права.
      assert siala.feats[:weapon_focus].prereqs["base_attack_bonus"] == 1
      assert siala.feats[:improved_critical].prereqs["base_attack_bonus"] == 8
    end

    # 🔴 Правило одно, ОТВЕТ разный, и разница — состав справочника: у Сиалы
    # владение названо у 42 записей из 47, у ванили ни у одной.
    test "Сиала отказывает, ваниль молчит", %{vanilla: vanilla, siala: siala} do
      fighter = Build.new(levels: List.duplicate(:fighter, 8))
      pick = %{feat: :weapon_focus, choice: :scimitar}

      assert Rules.validate_feat(fighter, pick, siala) ==
               {:error, [{:requires_feat, :siala_blade_proficiency}]}

      assert Rules.validate_feat(fighter, pick, vanilla) == :ok
    end

    # 🔴 Положительный контроль, важнее самой правки: ложная нелегальность
    # здесь была бы хуже исходного дефекта.
    test "с владением клинковым фокус на скимитар законен", %{siala: siala} do
      armed =
        Build.new(levels: List.duplicate(:fighter, 8))
        |> Build.put_feat(1, :general, :siala_blade_proficiency)

      for id <- @asks do
        assert Rules.validate_feat(armed, %{feat: id, choice: :scimitar}, siala) == :ok,
               "#{id} отказал персонажу с владением"
      end
    end

    # ⚠️ Владение с вещи требование ФИТА не выполняет (замер H7), хотя то же
    # владение позволяет взять это оружие В РУКИ (`Rules.GearWeapon`). Две
    # разные линии, и обе измерены — под одним тестом, чтобы их не «починили».
    test "владение с вещи оружие в руки даёт, а фит не открывает", %{siala: siala} do
      worn =
        Build.new(
          levels: List.duplicate(:fighter, 8),
          gear: %Gear{feats: [{:siala_blade_proficiency, nil}], weapon: :scimitar}
        )

      assert Rules.validate_feat(worn, %{feat: :weapon_focus, choice: :scimitar}, siala) ==
               {:error, [{:requires_feat, :siala_blade_proficiency}]}

      assert Rules.validate_gear_weapon(worn, :scimitar, siala) == :ok
    end

    # Там, где справочник владения не называет, отказать нечем — и билд
    # говорит об этом сам, поимённо по оружию.
    test "неназванное владение становится оговоркой билда", %{vanilla: vanilla, siala: siala} do
      focus = fn weapon ->
        Build.new(levels: List.duplicate(:fighter, 8))
        |> Build.put_feat(3, :general, :weapon_focus, weapon)
      end

      assert {:missing_data, {:weapon_proficiency, :creature_weapon}} in Rules.compute(
               focus.(:creature_weapon),
               siala
             ).gaps

      assert {:missing_data, {:weapon_proficiency, :longsword}} in Rules.compute(
               focus.(:longsword),
               vanilla
             ).gaps

      # Положительный контроль: у названного владения оговорки нет — иначе
      # она стояла бы всегда и не значила бы ничего.
      refute {:missing_data, {:weapon_proficiency, :longsword}} in Rules.compute(
               focus.(:longsword),
               siala
             ).gaps
    end
  end

  # 🔴 Задача 3.99, разряд 3. Второе семейство файла, четвёртая его запись:
  # требование называет СТУПЕНЬ фита («[[ki strike]] +3»), а схема умеет
  # требовать фит, но не ступень — на Fandom вся семья живёт одной страницей
  # и одним id.
  describe "`Improved ki strike 4`: ступень записана уровнем класса" do
    defp monk_build(levels) do
      Build.new(
        race: :human,
        alignment: :lawful_good,
        base_abilities: %{str: 12, dex: 14, con: 12, int: 10, wis: 21, cha: 8},
        levels: List.duplicate(:monk, levels)
      )
    end

    test "требование прочитано в уровень класса, оговорки не осталось", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala] do
        prereqs = ruleset.feats[:improved_ki_strike_4].prereqs

        assert prereqs["class_levels"] == %{"monk" => 16}
        assert prereqs["abilities"] == %{"wis" => 21}
        refute Map.has_key?(prereqs, "qualifiers")

        assert Rules.feat_caveats(:improved_ki_strike_4, ruleset) == []
      end
    end

    # 🔴 Ложная легальность, которую правка убирает: до неё требование стояло
    # как `class_levels: {monk: 1}` плюс `feats: [ki_strike]`, а id первой
    # ступени монах получает уже на 10-м — то есть фит открывался на шесть
    # классовых уровней раньше, чем в игре.
    test "на монахе 16 берётся, на 13 и 10 — нет", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        assert Rules.validate_feat(monk_build(16), :improved_ki_strike_4, ruleset) == :ok

        for level <- [10, 13] do
          assert {:error, reasons} =
                   Rules.validate_feat(monk_build(level), :improved_ki_strike_4, ruleset)

          assert {:requires_class_level, :monk, 16} in reasons,
                 "монах #{level} открыл `Improved ki strike 4`"
        end
      end
    end

    # ⚠️ Перекрёстная проверка, независимая от прозы описания: третья выдача
    # `ki_strike` и «+3» приходятся на один и тот же уровень. Разъедутся —
    # значит источник переписан, и запись надо перечитать, а не подогнать.
    test "16 — это уровень ТРЕТЬЕЙ выдачи ki_strike", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        grants =
          for {level, feats} <- ruleset.classes[:monk].granted_feats,
              :ki_strike in feats,
              do: level

        assert Enum.sort(grants) == [10, 13, 16]
      end
    end

    # ⚠️ Ловушка, названная `_note` файла: `feats: [ki_strike]` САМ ПО СЕБЕ
    # требования не выражает — id есть у монаха с 10-го. Если кто-то уберёт
    # уровень класса, оставив список фитов, требование не ослабнет, а ИСЧЕЗНЕТ.
    test "одного `feats: [ki_strike]` не хватило бы", %{siala: siala} do
      assert :ki_strike in Build.feats_permanent(monk_build(10), siala, 10)
    end
  end

  # ===========================================================================
  # СЕДЬМАЯ семья файла (задача 3.103): ступень фита, переведённая в уровень
  # класса ТАБЛИЦЕЙ этого класса, а не прозой.
  #
  # Источники, все с обеих сторон (проза плюс клетка таблицы):
  #   * `fandom:Sneak attack` (revid 68062) — «+1[[d6]] at first level and an
  #     additional +1d6 every two [[class level|level]]s thereafter»;
  #   * `fandom:Sneak attack, blackguard` (revid 68063) — «+1[[d6]] at fourth
  #     level and an additional +1d6 every three levels thereafter»;
  #   * `fandom:Assassin` (revid 71570), раздел «Epic assassin» — «Death attack:
  #     improves by +1d6 every two levels after 9th»;
  #   * `fandom:Wild shape` (revid 69979) — «…and six times per day at
  #     eighteenth level».
  # ===========================================================================
  describe "ступень фита, сверенная с таблицей класса" do
    # ⚠️ Пороги пересчитываются ЗДЕСЬ ЗАНОВО, из тех же таблиц, но своим кодом:
    # загрузчик уже сверяет запись со своей стороны (`verify_class_level_
    # witnesses!/2`), и повторять его вызов значило бы проверять код им же самим.
    # Здесь читается сырой JSON классов, и совпасть эти два чтения обязаны.
    defp raw_class(id) do
      "priv/rules/vanilla/classes.json"
      |> File.read!()
      |> Jason.decode!()
      |> Enum.find(&(&1["id"] == id))
    end

    defp first_class_level_with(class_id, column, cell) do
      class = raw_class(class_id)

      ((class["progression"] || []) ++ (class["epic_progression"] || []))
      |> Enum.filter(&(get_in(&1, ["extra", column]) == cell))
      |> Enum.map(& &1["level"])
      |> Enum.min(fn -> nil end)
    end

    # Таблица кейсов: ветка → колонка таблицы класса → клетка → уровень.
    @sneak_thresholds [
      {:rogue, "Sneak attack", "8d6", 15},
      {:blackguard, "Sneak attack", "8d6", 25},
      {:assassin, "Death attack", "8d6", 15}
    ]

    test "+8d6 приходится ровно на те уровни, что записаны в требовании", %{
      vanilla: vanilla,
      siala: siala
    } do
      for {class, column, cell, level} <- @sneak_thresholds do
        assert first_class_level_with(Atom.to_string(class), column, cell) == level,
               "таблица #{class} больше не читает #{cell} впервые на #{level}"

        for ruleset <- [vanilla, siala] do
          branches = ruleset.feats[:improved_sneak_attack].prereqs["any_of"]

          assert %{"class_levels" => %{Atom.to_string(class) => level}} in branches
        end
      end
    end

    # ⚠️ Вторая половина того же: у друида ступень лежит НЕ в колонке таблицы,
    # а рангом выданного фита, поэтому свидетель у неё другой формы.
    test "«wild shape 6x/day» — это друид 18, по рангу выдачи", %{
      vanilla: vanilla,
      siala: siala
    } do
      levels =
        for {level, ranks} <- raw_class("druid")["granted_feat_ranks"],
            ranks["wild_shape"] == "(6x/day)",
            do: String.to_integer(level)

      assert levels == [18]

      for ruleset <- [vanilla, siala] do
        assert %{"class_levels" => %{"druid" => 18}} in ruleset.feats[:dragon_shape].prereqs[
                 "any_of"
               ]
      end
    end

    # 🔴 Главное, ради чего свидетель вообще заведён: он держит число
    # в `requirements`, а не украшает запись. Оба конца проверяются на самой
    # записи — если завтра кто-нибудь поправит одно и забудет другое, сборка
    # упадёт, но этот тест назовёт место раньше и понятнее.
    test "у каждого свидетеля есть свой уровень в требованиях" do
      entries = file_entries()

      witnessed =
        for entry <- entries,
            witness <- entry["class_level_witnesses"] || [],
            do: {entry, witness}

      assert witnessed != [], "ключ `class_level_witnesses` исчез из файла целиком"

      for {entry, witness} <- witnessed do
        block = entry["requirements"]

        thresholds =
          [block | List.wrap(block["any_of"])]
          |> Enum.flat_map(&List.wrap(get_in(&1, ["class_levels", witness["class"]])))

        assert witness["level"] in thresholds,
               "#{entry["id"]}: свидетель #{witness["class"]} #{witness["level"]} " <>
                 "не подписывает ни одного требования"

        # Свидетель обязан называть ОДНУ таблицу — иначе непонятно, что сверено.
        forms = Enum.filter(~w(progression_column granted_feat_rank), &witness[&1])
        assert length(forms) == 1, "#{entry["id"]}: свидетель называет #{inspect(forms)}"

        assert is_binary(witness["quote"]) and witness["quote"] != ""
      end
    end

    # ⚠️ Достижимость каждой ветки посчитана, а не предположена: требование,
    # которое не выполнит никто, — это ложная нелегальность, замаскированная
    # под прочитанное правило. Ветка Убийцы ВЫГЛЯДЕЛА недостижимой (описание
    # `Death attack` обрывается на «5d6 at level 9»), и это оказалось свойством
    # ОПИСАНИЯ, а не механики: эпическая таблица класса продолжает прогрессию.
    #
    # Считается по потолкам самого ruleset'а, поэтому тест верен и на ванили
    # (кап 40, престиж ограничен только капом персонажа), и на Сиале (кап 41,
    # престиж до 31).
    test "все три ветки достижимы на обоих ruleset'ах", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala],
          {class, _column, _cell, level} <- @sneak_thresholds do
        definition = ruleset.classes[class]

        ceiling =
          if definition.prestige?,
            do: ruleset.prestige.level_cap || ruleset.level_cap,
            else: ruleset.level_cap

        assert level <= ceiling,
               "#{class} #{level} выше потолка класса (#{ceiling}) — ветка недостижима"

        # И по уровню персонажа: у престижного класса первые 10 уровней
        # укладываются до 20-го, остальные идут эпическими сверх него.
        character_level =
          if definition.prestige?,
            do: max(level, 20 + max(level - ruleset.prestige.pre_epic_class_level_cap, 0)),
            else: level

        assert character_level <= ruleset.level_cap,
               "#{class} #{level} требует персонажа #{character_level}, кап #{ruleset.level_cap}"
      end
    end
  end

  describe "«только на уровне класса X»: слот тратится не где угодно" do
    defp epic_build(levels) do
      Build.new(
        race: :human,
        alignment: :chaotic_good,
        base_abilities: %{str: 21, dex: 21, con: 21, int: 21, wis: 21, cha: 21},
        levels: levels
      )
    end

    # ⚠️ Две половины ОДНОЙ проверки, и по отдельности каждая зеленеет при
    # неверной модели: «на уровне варвара берётся» проходит и у запрета,
    # выброшенного вовсе, а «на уровне воина не берётся» — и у фита,
    # недоступного всем. Билды-близнецы: один и тот же варвар 20, один и тот же
    # 24-й уровень, отличается только класс ЭТОГО уровня.
    #
    # ⚠️ Порядок уровней подобран так, чтобы к 24-му у ОБОИХ билдов было ровно
    # по 20 уровней варвара: `validate_feat/3` с `at:` обрезает билд по этот
    # уровень, поэтому «варвар 20 последними» дало бы на 24-м всего 14 уровней
    # класса и отказ не про класс уровня.
    test "`mighty_rage` берётся на уровне варвара и не берётся на уровне воина", %{
      vanilla: vanilla,
      siala: siala
    } do
      on_barbarian = epic_build(List.duplicate(:fighter, 4) ++ List.duplicate(:barbarian, 20))
      on_fighter = epic_build(List.duplicate(:barbarian, 20) ++ List.duplicate(:fighter, 4))

      for ruleset <- [vanilla, siala] do
        assert Build.class_at(on_barbarian, 24) == :barbarian
        assert Build.class_at(on_fighter, 24) == :fighter

        assert Rules.validate_feat(on_barbarian, %{feat: :mighty_rage, at: 24}, ruleset) == :ok

        assert {:error, reasons} =
                 Rules.validate_feat(on_fighter, %{feat: :mighty_rage, at: 24}, ruleset)

        assert {:forbidden_by_class, :fighter} in reasons

        # ...и требование по уровню класса при этом ВЫПОЛНЕНО — то есть отказ
        # именно про уровень взятия, а не про состав билда, который у обоих
        # билдов одинаков.
        refute {:requires_class_level, :barbarian, 20} in reasons
      end
    end

    @rage_family [:mighty_rage, :thundering_rage, :terrifying_rage]

    # Билд захода E: варвар 20 плюс четыре уровня воина, а класс 24-го уровня —
    # тот, про который спрашиваем.
    #
    # ⚠️ Ранги Запугивания покупаются ТОЛЬКО на варварских уровнях: у воина навык
    # кросс-классовый, и потолок берётся от класса ИМЕННО этого уровня
    # (CLAUDE.md §6). Первый варварский уровень выкупает свой потолок целиком,
    # дальше по рангу за уровень — так 25 рангов набираются у обоих близнецов,
    # хотя варварские уровни стоят у них на разных местах лестницы.
    defp rage_build(levels) do
      [first | rest] = for {:barbarian, level} <- Enum.with_index(levels, 1), do: level

      ranks =
        Map.new([{first, %{intimidate: first + 3}}] ++ Enum.map(rest, &{&1, %{intimidate: 1}}))

      Build.new(
        race: :human,
        alignment: :chaotic_good,
        base_abilities: %{str: 25, dex: 12, con: 21, int: 14, wis: 10, cha: 8},
        levels: levels,
        skills: ranks
      )
    end

    # ✅ Замер Dan 16.08.2026 (`GAME_CHECKS.md`, кейсы E7b и E7c, персонаж
    # воин 6 / варвар 18–20): «По поводу обоих mighty rage и terrifying rage,
    # если взять вместо варвара воина, даже при соблюдении всех условий данные
    # фиты не доступны при прокачке. Получается, любые rage-ы доступны
    # исключительно на уровне варвара».
    #
    # 🔴 До него ограничение стояло только у `mighty_rage` — там, где предложение
    # написано на странице словами, — и `terrifying_rage` на ВОИНСКОМ уровне
    # отвечал `:ok`. Ложная легальность, измеренная вызовами и здесь же закрытая.
    #
    # ⚠️ Билды-близнецы отличаются РОВНО классом 24-го уровня: состав (варвар 20
    # + воин 4), характеристики и ранги Запугивания у них общие. Иначе «на
    # воинском нельзя» не отличить от «фит недоступен вовсе», а «на варварском
    # можно» — от «запрет выброшен».
    #
    # ⚠️ `thundering_rage` держится не на замере, а на обобщении Dan: силу 25
    # до 36-го уровня персонажа не набрать, статы с вещей при выборе фитов
    # не работают, и посмотреть этот фит в игре было нечем. В тесте он рядом
    # с двумя измеренными сознательно — правило у семейства одно, а провенанс
    # у него слабее, и это сказано в самой записи (`status: unclear`).
    test "все три rage берутся только на уровне варвара — замер Dan 16.08.2026", %{
      vanilla: vanilla,
      siala: siala
    } do
      on_barbarian = rage_build(List.duplicate(:fighter, 4) ++ List.duplicate(:barbarian, 20))

      on_fighter =
        rage_build(
          List.duplicate(:fighter, 2) ++
            List.duplicate(:barbarian, 20) ++ List.duplicate(:fighter, 2)
        )

      assert Build.class_at(on_barbarian, 24) == :barbarian
      assert Build.class_at(on_fighter, 24) == :fighter

      for ruleset <- [vanilla, siala], id <- @rage_family do
        # Положительный контроль: без него тест зеленел бы и на модели, которая
        # запрещает фит везде.
        assert Rules.validate_feat(on_barbarian, %{feat: id, at: 24}, ruleset) == :ok,
               ":#{id} недоступен на ВАРВАРСКОМ уровне — запрет вышел шире замера"

        assert {:error, reasons} = Rules.validate_feat(on_fighter, %{feat: id, at: 24}, ruleset)

        assert {:forbidden_by_class, :fighter} in reasons,
               ":#{id} берётся на ВОИНСКОМ уровне, отказы: #{inspect(reasons)}"

        # ...и отказ именно про класс уровня: состав билда у близнецов один и тот
        # же, поэтому требование по уровню класса выполнено у обоих.
        refute Enum.any?(reasons, &match?({:requires_class_level, :barbarian, _}, &1)),
               ":#{id} отказывает по составу билда — близнецы разъехались"
      end
    end

    # Та же половина правила, но та, которую видит игрок: список эпического
    # общего слота. `validate_feat/3` и слоты обязаны сходиться, иначе
    # конструктор предложит то, что билд потом откажется держать.
    test "эпический слот на воинском уровне ни одного rage не предлагает", %{siala: siala} do
      on_fighter =
        rage_build(
          List.duplicate(:fighter, 2) ++
            List.duplicate(:barbarian, 20) ++ List.duplicate(:fighter, 2)
        )

      on_barbarian = rage_build(List.duplicate(:fighter, 4) ++ List.duplicate(:barbarian, 20))

      general = fn build ->
        Enum.find(FeatSlots.at(build, siala, 24), &(&1.kind == :epic_general))
      end

      for id <- @rage_family do
        refute FeatSlots.accepts?(siala, general.(on_fighter), id)
        assert FeatSlots.accepts?(siala, general.(on_barbarian), id)
      end

      # Положительный контроль: слот на воинском уровне жив и другой эпический
      # фит принимает — значит `refute` выше про запрет, а не про пустой слот.
      assert FeatSlots.accepts?(siala, general.(on_fighter), :epic_prowess)
    end

    # Порча: убрать ключ у `terrifying_rage` — и ложная легальность возвращается
    # ровно там, где её измерил Dan. Сторож против «правки заодно»: без него
    # тесты выше зеленели бы и на записи, которую кто-нибудь тихо снял.
    #
    # ⚠️ Порча делается на `terrifying_rage`, а не на `thundering_rage`: первый
    # измерен в игре прямо, второй стоит на обобщении — если однажды окажется,
    # что обобщение шире правды, снимать придётся его, и сторож не должен этому
    # мешать.
    test "без `only_on_class_levels` `terrifying_rage` снова берётся на уровне воина" do
      root = copy_rules()
      edit_entry(root, "terrifying_rage", &Map.delete(&1, "only_on_class_levels"))
      ruleset = Loader.load!(root)["siala_41"]

      on_fighter =
        rage_build(
          List.duplicate(:fighter, 2) ++
            List.duplicate(:barbarian, 20) ++ List.duplicate(:fighter, 2)
        )

      assert Rules.validate_feat(on_fighter, %{feat: :terrifying_rage, at: 24}, ruleset) == :ok
    end

    # То же на списке из двух классов: разрешённый — не единственный, и второй
    # разрешён так же. Без этой проверки правило могло бы читать только первый
    # элемент списка и выглядеть работающим.
    test "`epic_weapon_specialization` разрешён обоим названным классам", %{siala: siala} do
      for class <- [:fighter, :champion_of_torm] do
        refute {:forbidden_by_class, class} in Rules.class_feat_refusals(
                 epic_build(List.duplicate(class, 24)),
                 24,
                 :epic_weapon_specialization,
                 siala
               )
      end

      for class <- [:barbarian, :monk, :wizard] do
        assert {:forbidden_by_class, class} in Rules.class_feat_refusals(
                 epic_build(List.duplicate(class, 24)),
                 24,
                 :epic_weapon_specialization,
                 siala
               )
      end
    end

    # Шесть эпических заклинаний, и списки у них РАЗНЫЕ: у четырёх божественные
    # классы разрешены, у двух арканных — нет. Список читается по каждой странице
    # отдельно, и этот тест ловит перенос списка с соседней страницы.
    test "у эпических заклинаний списки разные, а не общий", %{siala: siala} do
      divine = epic_build(List.duplicate(:cleric, 24))

      refute {:forbidden_by_class, :cleric} in Rules.class_feat_refusals(
               divine,
               24,
               :epic_spell_hellball,
               siala
             )

      assert {:forbidden_by_class, :cleric} in Rules.class_feat_refusals(
               divine,
               24,
               :epic_spell_epic_mage_armor,
               siala
             )
    end

    # Тот же запрет — в СЛОТАХ, а не только в `validate_feat/3`: до правки фит
    # предлагался в списке эпического общего слота на воинском уровне, и именно
    # это игрок видел. Две стороны одного правила обязаны сходиться (иначе
    # предложим то, что билд потом откажется держать).
    test "слот на уровне воина фит не предлагает, на уровне варвара предлагает", %{siala: siala} do
      on_fighter = epic_build(List.duplicate(:barbarian, 20) ++ List.duplicate(:fighter, 4))
      on_barbarian = epic_build(List.duplicate(:fighter, 4) ++ List.duplicate(:barbarian, 20))

      general = fn build ->
        Enum.find(FeatSlots.at(build, siala, 24), &(&1.kind == :epic_general))
      end

      refute FeatSlots.accepts?(siala, general.(on_fighter), :mighty_rage)
      assert FeatSlots.accepts?(siala, general.(on_barbarian), :mighty_rage)

      # Положительный контроль: слот на воинском уровне жив и принимает другой
      # эпический фит — значит `refute` выше про запрет, а не про пустой слот.
      assert FeatSlots.accepts?(siala, general.(on_fighter), :epic_prowess)
    end

    # Порча первого рода: убрать ключ — ложная легальность возвращается ровно
    # там, где была измерена до правки.
    test "без `only_on_class_levels` фит снова берётся на уровне воина" do
      root = copy_rules()
      edit_entry(root, "mighty_rage", &Map.delete(&1, "only_on_class_levels"))
      ruleset = Loader.load!(root)["siala_41"]

      on_fighter = epic_build(List.duplicate(:barbarian, 20) ++ List.duplicate(:fighter, 4))

      assert Rules.validate_feat(on_fighter, %{feat: :mighty_rage, at: 24}, ruleset) == :ok
    end

    # Порча второго рода: опечатка в имени класса. Дополнение считается, поэтому
    # имя, не совпавшее ни с чем, ЗАПРЕТИЛО БЫ фит всем — то есть ошибка данных
    # превратилась бы в ложную нелегальность без единого предупреждения.
    test "имя класса, которого нет, роняет сборку" do
      root = copy_rules()
      edit_entry(root, "mighty_rage", &Map.put(&1, "only_on_class_levels", ["barbarain"]))

      assert_raise RuntimeError, ~r/which are not classes/, fn -> Loader.load!(root) end
    end

    # Пустой список — не «никому нельзя», а другая механика целиком
    # (`level_up_selectable?`, «умение нельзя выбрать при росте персонажа»).
    test "пустой список роняет сборку, а не запрещает всем" do
      root = copy_rules()
      edit_entry(root, "mighty_rage", &Map.put(&1, "only_on_class_levels", []))

      assert_raise RuntimeError, ~r/not a non-empty list of class ids/, fn ->
        Loader.load!(root)
      end
    end

    # Сторож против молчаливого конфликта двух сторон вики: если страница класса
    # запрещает фит, а страница фита этот класс разрешает, выбирать за источник
    # нельзя. Сегодня таких пар нет ни одной — порча их создаёт.
    #
    # ⚠️ Порча делается на `curse_song`, а не на `mighty_rage`: конфликт возможен
    # только там, где класс-лист вики этот фит вообще называет, а `mighty_rage`
    # не называет ни один из 23 (в том и была дыра). `curse_song` воин запрещает
    # своей страницей — значит «разрешить его воину» и есть настоящий спор.
    test "разрешённый класс, который сам запрещает фит, роняет сборку" do
      root = copy_rules()
      edit_entry(root, "curse_song", &Map.put(&1, "only_on_class_levels", ["fighter"]))

      assert_raise RuntimeError, ~r/already refuses it/, fn -> Loader.load!(root) end
    end

    # `improved_stunning_fist` НЕ применён, и это решение: ограничение действует
    # со второго взятия, плоский запрет сделал бы первое ложно нелегальным.
    # Проверка стоит здесь, чтобы «забыли применить» и «решили не применять»
    # нельзя было спутать.
    test "`improved_stunning_fist` остаётся без запрета — ограничение со 2-го взятия", %{
      siala: siala
    } do
      monk_rogue = epic_build(List.duplicate(:monk, 20) ++ List.duplicate(:rogue, 10))

      assert Rules.class_feat_refusals(monk_rogue, 24, :improved_stunning_fist, siala) == []

      assert Rules.validate_feat(monk_rogue, %{feat: :improved_stunning_fist, at: 24}, siala) ==
               :ok
    end
  end

  # То же ТРЕТЬЕ семейство, но с самым большим списком разрешённых классов
  # из всех четырнадцати записей — девять из 23, — и с провенансом, какого
  # у остальных нет: состав стоит на ТРЁХ независимых линиях, и они сходятся.
  #
  # 🔴 До 17.08.2026 у этих четырёх фитов не было ограничения НИ ОДНОГО:
  # `unavailable_feats` не называл их ни у одного из 23 классов на обоих
  # ruleset'ах (посчитано вызовом). Ложная легальность — воин с 9-м кругом
  # в билде брал `Automatic quicken spell` на своём уровне.
  #
  # source: замер Dan 17.08.2026 (`GAME_CHECKS.md`, кейсы S4, S4b, S5) —
  # «на уровне воина он не доступен, у меня он доступен на уровнях колдуна,
  # волшебника, друида, клерика, бледного мастера и барда»; «рейнджеру
  # и паладину они не доступны, я проверил»; «20 колдун 1 РДД, на уровне РДД
  # epic spell penetration доступен… Аналогично проверил Шифтера и Чемпиона
  # Торма». Плюс проза трёх страниц `Automatic *` (девятый класс — бард)
  # и шаблон `bonus1..8` (восемь из девяти).
  describe "четыре эпических фита кастера: слот тратится только на своём классе" do
    @spell_family [
      :automatic_quicken_spell,
      :automatic_silent_spell,
      :automatic_still_spell,
      :epic_spell_penetration
    ]

    # Девять разрешённых — замер. Восемь из них независимо предсказаны шаблоном
    # `bonus1..8`, девятого (барда) называет проза трёх страниц из четырёх.
    @spell_family_allowed [
      :bard,
      :champion_of_torm,
      :cleric,
      :druid,
      :pale_master,
      :red_dragon_disciple,
      :shifter,
      :sorcerer,
      :wizard
    ]

    # Три запрещённых, названных Dan поимённо. Ни один не попал ни в одну
    # из трёх линий — это и делает совпадение линий перекрёстной проверкой,
    # а не совпадением.
    @spell_family_measured_forbidden [:fighter, :paladin, :ranger]

    # …и одиннадцать, которых никто не смотрел. Запрет у них стоит на одном
    # признаке — они вне `bonus_for`, том же, по которому запрещены три
    # измеренных. Список ЗАФИКСИРОВАН здесь именно потому, что это допущение:
    # день, когда замер его сузит или расширит, обязан быть виден диффом.
    @spell_family_assumed_forbidden [
      :arcane_archer,
      :assassin,
      :barbarian,
      :blackguard,
      :dwarven_defender,
      :harper_scout,
      :monk,
      :purple_dragon_knight,
      :rogue,
      :shadowdancer,
      :weapon_master
    ]

    # 21 уровень волшебника даёт билду и эпический уровень, и 9-й круг, а хвост
    # называет класс, про который спрашиваем. Значит билды отличаются РОВНО
    # классом 24-го уровня, и отказ не может прийти от состава.
    defp spell_family_build(class) do
      epic_build(List.duplicate(:wizard, 21) ++ List.duplicate(class, 3))
    end

    # Сторож против дрейфа самих списков: три множества обязаны в сумме давать
    # все классы ruleset'а и не пересекаться. Без него новый класс в данных
    # молча выпал бы из проверки, а перенос класса из «запрещён» в «разрешён»
    # прошёл бы, забыв вторую половину.
    test "три списка покрывают все 23 класса и не пересекаются", %{siala: siala} do
      forbidden = @spell_family_measured_forbidden ++ @spell_family_assumed_forbidden
      all = @spell_family_allowed ++ forbidden

      assert Enum.sort(all) == siala.classes |> Map.keys() |> Enum.sort()
      assert length(all) == length(Enum.uniq(all))
      assert length(@spell_family_allowed) == 9
    end

    # Половина «можно»: на уровне каждого из девяти отказа по классу нет.
    # Без неё тест зеленел бы и на запрете, вышедшем шире замера, — а именно
    # это и была самая дорогая из возможных ошибок правки (координатор
    # собирался запретить РДД, Оборотня и Чемпиона Торма).
    test "на уровне девяти разрешённых классов отказа по классу нет", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala],
          class <- @spell_family_allowed,
          id <- @spell_family do
        build = spell_family_build(class)
        assert Build.class_at(build, 24) == class

        assert Rules.class_feat_refusals(build, 24, id, ruleset) == [],
               ":#{id} запрещён на уровне :#{class}, хотя замер его разрешает"
      end
    end

    # Половина «нельзя», и ровно та, которую Dan назвал поимённо.
    test "на уровне воина, паладина и рейнджера все четыре отбиты", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala],
          class <- @spell_family_measured_forbidden,
          id <- @spell_family do
        build = spell_family_build(class)

        assert Rules.class_feat_refusals(build, 24, id, ruleset) == [
                 {:forbidden_by_class, class}
               ],
               ":#{id} берётся на уровне :#{class} — замер говорит обратное"
      end
    end

    # ⚠️ ДОПУЩЕНИЕ, а не замер, и тест сторожит именно его, а не правило.
    # Направление ошибки названо в записи: если правило шире замера, это ложная
    # НЕлегальность на редком билде (уровень вора у персонажа с 9-м кругом),
    # и игрок её увидит. Обратная ошибка — та, что стояла до правки, — давала
    # нелегальный билд молча.
    test "одиннадцать неизмеренных классов запрещены — допущением", %{siala: siala} do
      for class <- @spell_family_assumed_forbidden, id <- @spell_family do
        assert Rules.class_feat_refusals(spell_family_build(class), 24, id, siala) == [
                 {:forbidden_by_class, class}
               ]
      end
    end

    # Билд, у которого выполнено ВСЁ остальное: 27 уровней волшебника несут
    # 9-й круг и 30 рангов Знания магии (потолок классового навыка на 27-м
    # ровно 30), пять базовых фитов лежат в общих слотах. Хвост из трёх
    # уровней называет класс 30-го — а 30-й эпический общий слот у билда есть.
    #
    # ⚠️ Ранги покупаются ТОЛЬКО на волшебничьих уровнях: у воина Знание магии
    # кросс-классовое, и потолок берётся от класса ИМЕННО этого уровня. Ровно
    # эта ловушка и заставила Dan мерить `Epic spell penetration`, а не
    # `Automatic silent spell` (у первого требований по навыкам нет вовсе).
    defp full_caster_build(tail_class) do
      Build.new(
        race: :human,
        # Не lawful: у барда мировоззрение ограничено, а он тут разрешённый
        # близнец. Воину всё равно, так что пара остаётся законной с обеих сторон.
        alignment: :neutral_good,
        base_abilities: %{str: 10, dex: 10, con: 14, int: 21, wis: 10, cha: 10},
        levels: List.duplicate(:wizard, 27) ++ List.duplicate(tail_class, 3),
        skills:
          Map.new(1..27, fn level -> {level, %{spellcraft: if(level == 1, do: 4, else: 1)}} end),
        feats: %{
          1 => %{general: :spell_penetration},
          3 => %{general: :silent_spell},
          6 => %{general: :still_spell},
          9 => %{general: :quicken_spell},
          12 => %{general: :greater_spell_penetration}
        }
      )
    end

    # Сквозная проверка через `validate_feat/3`, а не через изолированный
    # `class_feat_refusals/4`: у близнецов выполнены ВСЕ прочие требования, и
    # доказывает это единственность причины отказа — списком ровно из одного
    # элемента. Иначе «отбит» нельзя отличить от «не хватило рангов».
    test "близнецы 27 волшебника + 3: на бардском уровне :ok, на воинском отказ", %{
      vanilla: vanilla,
      siala: siala
    } do
      on_bard = full_caster_build(:bard)

      for ruleset <- [vanilla, siala], id <- @spell_family do
        assert Build.class_at(on_bard, 30) == :bard

        # Бард — тот самый девятый класс, которого нет в шаблоне: его называет
        # только проза. И его же случай объясняет, почему уровень класса
        # и требование к персонажу — независимые ворота: 9-й круг барду
        # приходит от волшебника, а слот тратится на бардском уровне.
        assert Rules.validate_feat(on_bard, %{feat: id, at: 30}, ruleset) == :ok,
               ":#{id} недоступен на уровне барда при выполненных требованиях"

        for class <- @spell_family_measured_forbidden do
          build = full_caster_build(class)

          assert Rules.validate_feat(build, %{feat: id, at: 30}, ruleset) ==
                   {:error, [forbidden_by_class: class]},
                 ":#{id} на уровне :#{class} отказан не только классом — " <>
                   "значит билд не дотягивает и проверяется не то"
        end
      end
    end

    # Та же половина правила, но та, которую видит игрок: список эпического
    # общего слота. `validate_feat/3` и слоты обязаны сходиться, иначе
    # конструктор предложит то, что билд потом откажется держать.
    test "эпический общий слот на воинском уровне ни одного из четырёх не предлагает", %{
      siala: siala
    } do
      general = fn build ->
        Enum.find(FeatSlots.at(build, siala, 30), &(&1.kind == :epic_general))
      end

      on_bard = general.(full_caster_build(:bard))
      on_fighter = general.(full_caster_build(:fighter))

      for id <- @spell_family do
        assert FeatSlots.accepts?(siala, on_bard, id)
        refute FeatSlots.accepts?(siala, on_fighter, id)
      end

      # Положительный контроль: слот на воинском уровне жив и другой эпический
      # фит принимает — значит `refute` выше про запрет, а не про пустой слот.
      assert FeatSlots.accepts?(siala, on_fighter, :epic_prowess)
    end

    # 🔴 РАЗВИЛКА КЕЙСА S5: координатор опасался, что запрет по уровню отнимет
    # бонусный слот у Чемпиона Торма — фит, который его собственная страница ему
    # бонусным и выдаёт. Развилка снялась ЗАМЕРОМ: все три «слотовых» класса
    # оказались разрешены и по уровню тоже.
    #
    # ⚠️ Тест зелен и БЕЗ правки, и это сказано прямо, чтобы его силу не
    # переоценили: он сторожит не механизм, а состав списка. Сузить девятку
    # (например выкинуть Оборотня «за неизмеренностью») — и второе утверждение
    # упадёт, а ПЕРВОЕ нет: бонусный слот `unavailable_feats` не читает вовсе,
    # так что игрок получил бы фит в бонусном слоте и отказ в общем на том же
    # уровне. Именно это расхождение здесь и ловится.
    #
    # Уровни взяты настоящие, а не собранные руками: Чемпион Торма даёт
    # бонусный слот на своём 2-м уровне класса, РДД — на 14-м, Оборотень —
    # на 13-м (эпические уровни класса, поэтому хвост длиннее).
    test "бонусный слот трёх «слотовых» классов все четыре фита принимает", %{siala: siala} do
      slot = fn class, class_levels, at ->
        build =
          epic_build(List.duplicate(:wizard, 21) ++ List.duplicate(class, class_levels))

        FeatSlots.at(build, siala, at)
        |> Enum.find(&(&1.kind == :class_bonus and &1.class == class))
      end

      for {class, class_levels, at} <- [
            {:champion_of_torm, 10, 23},
            {:red_dragon_disciple, 14, 35},
            {:shifter, 13, 34}
          ] do
        bonus = slot.(class, class_levels, at)
        assert bonus, "у :#{class} нет бонусного слота на #{at}-м — проверять нечего"

        for id <- @spell_family do
          assert FeatSlots.accepts?(siala, bonus, id),
                 "бонусный слот :#{class} перестал принимать :#{id}"
        end
      end

      # …и ВТОРОЕ утверждение, ради которого тест и стоит: ни один класс
      # не может одновременно получать фит бонусным и терять его на своём
      # уровне. Сегодня это верно по построению — все восемь классов
      # `bonus_for` лежат внутри девяти разрешённых, — и ровно это делает
      # первую половину безопасной.
      for id <- @spell_family do
        assert MapSet.subset?(
                 siala.feats[id].bonus_for,
                 MapSet.new(@spell_family_allowed)
               ),
               "у :#{id} есть класс, которому фит даётся бонусным и запрещён на его же уровне"
      end
    end

    # Отрицательный контроль к предыдущему: бонусный слот класса, которого нет
    # в `bonus_for`, эти фиты не принимал и не должен — иначе «принимает»
    # выше ничего не значило бы.
    test "бонусный слот воина ни одного из четырёх не принимает", %{siala: siala} do
      build = epic_build(List.duplicate(:fighter, 24))

      bonus =
        FeatSlots.at(build, siala, 24)
        |> Enum.find(&(&1.kind == :class_bonus and &1.class == :fighter))

      assert bonus

      for id <- @spell_family, do: refute(FeatSlots.accepts?(siala, bonus, id))

      # …а другой эпический фит из своего списка принимает.
      assert FeatSlots.accepts?(siala, bonus, :epic_prowess)
    end

    # Порча: убрать запись целиком — ложная легальность возвращается ровно
    # такой, какой её измерил Dan. Удаляется вся запись, а не один ключ:
    # `requirements` у этих четырёх нет (пререквизиты парсер читает сам), и
    # «applied без требований и без ограничения» роняет сборку сторожем —
    # то есть порча ключом проверила бы сторож, а не правило.
    test "без записи `epic_spell_penetration` снова берётся на уровне воина" do
      root = copy_rules()
      drop_entry(root, "epic_spell_penetration")
      ruleset = Loader.load!(root)["siala_41"]

      on_fighter = full_caster_build(:fighter)

      assert Rules.validate_feat(on_fighter, %{feat: :epic_spell_penetration, at: 30}, ruleset) ==
               :ok

      # …а три соседа по семейству запрет сохранили: правило записью на фит,
      # а не одной общей строкой на всех.
      for id <- @spell_family -- [:epic_spell_penetration] do
        assert Rules.validate_feat(on_fighter, %{feat: id, at: 30}, ruleset) ==
                 {:error, [forbidden_by_class: :fighter]}
      end
    end

    # Порча второго рода, та же, что у `mighty_rage`: дополнение считается,
    # поэтому имя класса, не совпавшее ни с чем, ЗАПРЕТИЛО БЫ фит всем —
    # ошибка данных превратилась бы в ложную нелегальность без предупреждения.
    # Проверяется на этой записи отдельно: список тут девять имён вместо одного,
    # и опечатка в нём вероятнее.
    test "опечатка в одном из девяти имён роняет сборку" do
      root = copy_rules()

      edit_entry(root, "automatic_quicken_spell", fn entry ->
        Map.put(entry, "only_on_class_levels", ["bard", "sorceror"])
      end)

      assert_raise RuntimeError, ~r/which are not classes/, fn -> Loader.load!(root) end
    end

    # Сторож шестого семейства не должен срабатывать здесь ложно: он сверяет
    # `only_on_class_levels` с `qualifying_class_levels`, а у этих четырёх
    # второго ключа нет вовсе — их девятка не обязана совпадать с пятёркой
    # эпических заклинаний и не совпадает.
    test "списки эпических заклинаний и этой четвёрки — разные", %{siala: siala} do
      wizard = spell_family_build(:wizard)
      bard = spell_family_build(:bard)

      # Волшебник разрешён обоим семействам…
      assert Rules.class_feat_refusals(wizard, 24, :epic_spell_hellball, siala) == []
      assert Rules.class_feat_refusals(wizard, 24, :epic_spell_penetration, siala) == []

      # …а бард — только нашему: у эпических заклинаний его в списке нет.
      assert Rules.class_feat_refusals(bard, 24, :epic_spell_hellball, siala) == [
               {:forbidden_by_class, :bard}
             ]

      assert Rules.class_feat_refusals(bard, 24, :epic_spell_penetration, siala) == []
    end
  end

  # То же ТРЕТЬЕ семейство, и здесь список разрешённых самый короткий из всех —
  # один класс. Три «эпические формы Оборотня»: `construct_shape`,
  # `outsider_shape`, `undead_shape`.
  #
  # source: замер Dan 17.08.2026 (`GAME_CHECKS.md`, кейс S8) — «проверил, Undead
  # shape на уровне рейнджера не доступен, я думаю все шифтерские фиты доступны
  # исключительно на уровне шифтера».
  #
  # 🔴 До правки ограничения не было ни у одного из трёх: билд «друид 10 /
  # Оборотень 11 / рейнджер 3» получал `Undead shape` на РЕЙНДЖЕРСКОМ 24-м
  # со вердиктом `:ok` (измерено вызовом). Ложная легальность — калькулятор
  # отдавал билд, которого в игре нет.
  #
  # ⚠️ Прозы нужной формы («only … when leveling/advancing as Y») ни на одной
  # из трёх страниц НЕТ — их собственный текст переводит СТУПЕНЬ («can be taken
  # starting on shifter level 10»), то есть отвечает на другой вопрос. Правило
  # целиком стоит на замере, ровно как у `terrifying_rage`.
  describe "три эпических фита форм Оборотня: слот тратится только на его уровне" do
    @shape_family [:construct_shape, :outsider_shape, :undead_shape]

    # МУДРОСТЬ 27 выше поинт-бая (максимум 18, бонуса к ней не даёт ни одна
    # из семи рас) — в игре её набирают прибавками за уровни и `Great wisdom`.
    # Здесь она проставлена базово намеренно: тест обязан отличать «отбит
    # классом уровня» от «не дотянул характеристикой», а для этого прочие
    # требования у близнецов должны быть выполнены ОБА, и одинаково.
    #
    # ⚠️ Мировоззрение нейтральное: друид без него не берётся, а класс уровня —
    # единственное, чем близнецы имеют право отличаться.
    defp shape_build(levels) do
      Build.new(
        race: :human,
        alignment: :neutral,
        base_abilities: %{str: 10, dex: 12, con: 14, int: 12, wis: 27, cha: 8},
        levels: levels
      )
    end

    # Билды-близнецы: у обоих к 24-му ровно 11 уровней Оборотня и 10 друида,
    # отличается только класс САМОГО 24-го уровня. Иначе «на рейнджерском
    # нельзя» не отличить от «не хватает уровней класса».
    #
    # Состав взят с персонажа замера (друид 10 / Оборотень 11), к нему дописан
    # хвост из трёх уровней — тот самый рейнджерский уровень, на котором Dan
    # фит и не увидел.
    defp shape_on_shifter,
      do: shape_build(List.duplicate(:druid, 10) ++ List.duplicate(:ranger, 3) ++ shifter_tail())

    defp shape_on_ranger,
      do: shape_build(List.duplicate(:druid, 10) ++ shifter_tail() ++ List.duplicate(:ranger, 3))

    defp shifter_tail, do: List.duplicate(:shifter, 11)

    # ✅ Обе половины замера, и по отдельности каждая зеленела бы при неверной
    # модели: «на рейнджерском нельзя» пройдёт и у фита, запрещённого всем,
    # а «на оборотневом можно» — у запрета, выброшенного вовсе.
    #
    # ⚠️ Отказ на рейнджерском уровне сверяется СПИСКОМ ЦЕЛИКОМ, а не
    # вхождением: единственность причины и доказывает, что прочие требования
    # (МУДРОСТЬ и 11 уровней Оборотня) выполнены, то есть проверяется ровно
    # класс уровня.
    test "на уровне рейнджера все три отбиты, на уровне Оборотня берутся — замер S8", %{
      vanilla: vanilla,
      siala: siala
    } do
      on_shifter = shape_on_shifter()
      on_ranger = shape_on_ranger()

      assert Build.class_at(on_shifter, 24) == :shifter
      assert Build.class_at(on_ranger, 24) == :ranger

      for ruleset <- [vanilla, siala], id <- @shape_family do
        assert Rules.validate_feat(on_shifter, %{feat: id, at: 24}, ruleset) == :ok,
               ":#{id} недоступен на ОБОРОТНЕВОМ уровне — запрет вышел шире замера"

        assert Rules.validate_feat(on_ranger, %{feat: id, at: 24}, ruleset) ==
                 {:error, [forbidden_by_class: :ranger]},
               ":#{id} на рейнджерском уровне отказан не только классом — " <>
                 "значит билд не дотягивает и проверяется не то"
      end
    end

    # Обобщение владельца («все шифтерские фиты») запрещает фит и 21 классу,
    # которых никто не смотрел, — тест сторожит именно это, а не замер.
    #
    # ⚠️ ДРУИД НАЗВАН ПОИМЁННО, потому что он единственный класс, у которого
    # доступ был бы правдоподобен: `dragon_shape` из той же семьи разрешён ему
    # прямо, и «за компанию» его легко было бы сюда дописать. Источник этого
    # не даёт — та же страница `Dragon shape` говорит, что он единственный,
    # «available to druids without shifter levels», то есть остальным трём
    # друида как раз не хватает.
    test "запрет накрыл все 22 класса, кроме Оборотня", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala], id <- @shape_family do
        banning =
          for {class_id, class} <- ruleset.classes,
              MapSet.member?(class.unavailable_feats, id),
              do: class_id

        assert length(banning) == 22, ":#{id} запрещён #{length(banning)} классам вместо 22"
        refute :shifter in banning, ":#{id} запрещён Оборотню — правило перевёрнуто"
        assert :druid in banning, ":#{id} разрешён друиду, чего источник не говорит"
      end
    end

    # ⚠️ ОГРАНИЧЕНИЕ — НЕ ПРЕРЕКВИЗИТ, и это видно по тому, что `prereqs`
    # у всех трёх остались ровно теми, что прочитал `mix wiki.parse`. Уехав
    # в требования, правило стало бы фактом о ПЕРСОНАЖЕ («в билде нет уровней
    # Оборотня») и соврало бы дважды: билд с Оборотнем 11 брал бы фит на любом
    # уровне, а причина отказа называла бы состав вместо класса уровня.
    test "`prereqs` не тронуты — запись говорит про уровень, а не про персонажа", %{
      vanilla: vanilla,
      siala: siala
    } do
      expected = %{
        construct_shape: %{"abilities" => %{"wis" => 27}, "class_levels" => %{"shifter" => 11}},
        outsider_shape: %{"abilities" => %{"wis" => 25}, "class_levels" => %{"shifter" => 11}},
        undead_shape: %{"class_levels" => %{"shifter" => 11}}
      }

      for ruleset <- [vanilla, siala], {id, prereqs} <- expected do
        assert ruleset.feats[id].prereqs == prereqs
      end
    end

    # Та же половина правила, но со стороны, которую видит игрок: список
    # эпического общего слота. `validate_feat/3` и слоты обязаны сходиться,
    # иначе конструктор предложит то, что билд потом откажется держать.
    test "эпический общий слот на рейнджерском уровне ни один из трёх не предлагает", %{
      siala: siala
    } do
      general = fn build ->
        Enum.find(FeatSlots.at(build, siala, 24), &(&1.kind == :epic_general))
      end

      on_ranger = general.(shape_on_ranger())
      on_shifter = general.(shape_on_shifter())

      for id <- @shape_family do
        refute FeatSlots.accepts?(siala, on_ranger, id)
        assert FeatSlots.accepts?(siala, on_shifter, id)
      end

      # Положительный контроль: слот на рейнджерском уровне жив и другой
      # эпический фит принимает — значит `refute` выше про запрет, а не про
      # отсутствующий слот.
      assert FeatSlots.accepts?(siala, on_ranger, :epic_prowess)
    end

    # ⚠️ ГРАНИЦА, КОТОРУЮ ПРАВКА МОГЛА БЫ ЗАДЕТЬ И НЕ ЗАДЕЛА (развилка кейса S5):
    # запрет по уровню и бонусный слот — независимые оси, и запрет, вышедший
    # шире, отнял бы у Оборотня фит из его собственного бонусного пула.
    # Здесь пересечения нет по построению: `bonus_for` у всех трёх — ровно
    # `[shifter]`, и он же единственный разрешённый класс. Проверяется, а не
    # выводится, потому что «по построению» держится ровно до правки данных.
    test "бонусный слот Оборотня все три принимает", %{siala: siala} do
      # 13 уровней Оборотня: 11-й и дальше — эпические классовые, и на 13-м
      # у класса стоит эпический бонусный слот.
      build = shape_build(List.duplicate(:druid, 10) ++ List.duplicate(:shifter, 13))

      assert Build.class_at(build, 23) == :shifter

      bonus = Enum.find(FeatSlots.at(build, siala, 23), &(&1.kind == :class_bonus))
      assert bonus.class == :shifter

      for id <- @shape_family do
        assert FeatSlots.accepts?(siala, bonus, id),
               ":#{id} выпал из бонусного пула Оборотня — запрет вышел шире оси"

        assert MapSet.member?(siala.feats[id].bonus_for, :shifter)
      end
    end

    # 🔴 ГРАНИЦА ОБОБЩЕНИЯ, и это главный тест блока. Dan сказал «все шифтерские
    # фиты», но у `dragon_shape` — четвёртого фита той же семьи — источник
    # называет ДВА класса прямо: «This feat can only be acquired when advancing
    # in [[druid]] or [[shifter]] levels». Приписать ему `[shifter]` значило бы
    # сузить источник и отнять у друида доступ, который страница даёт в явном
    # виде.
    #
    # ⚠️ ЗДЕСЬ СТОЯЛО «`dragon_shape` ограничения по классу НЕ получил», и это
    # было верно, пока верна была его ПОСЫЛКА: под вердиктом `not_binding`
    # загрузчик `only_on_class_levels` не читает вовсе, а вердикт был
    # `not_binding` потому, что фит отказывал всем по непрочитанному фрагменту.
    # Задача 3.103 фрагмент прочитала («wild shape 6x/day» = друид 18, названо
    # описанием самого `Wild shape` и таблицей класса), вердикт стал `applied` —
    # и ключ заработал сам. Тест держит ту же ГРАНИЦУ, только с другой стороны:
    # разрешены ДВА класса, а не один.
    test "`dragon_shape` разрешён друиду И Оборотню, а не одному Оборотню", %{
      vanilla: vanilla,
      siala: siala
    } do
      entry = Enum.find(file_entries(), &(&1["id"] == "dragon_shape"))

      assert entry["verdict"] == "applied"
      assert entry["only_on_class_levels"] == ["druid", "shifter"]
      assert Enum.any?(entry["quotes"], &String.contains?(&1["text"], "druid]] or [[shifter"))

      # 1. Запрещены ровно все ОСТАЛЬНЫЕ классы — список считается дополнением,
      #    а не переписывается руками.
      for ruleset <- [vanilla, siala] do
        banning =
          for {class_id, class} <- ruleset.classes,
              MapSet.member?(class.unavailable_feats, :dragon_shape),
              do: class_id

        refute :druid in banning
        refute :shifter in banning
        assert length(banning) == map_size(ruleset.classes) - 2
      end

      # 2. Поведение на ДРУИДСКОМ уровне: друиду без единого уровня Оборотня фит
      #    доступен, и это ровно то, что страница утверждает отдельным
      #    предложением («the only epic shape feat that is available to druids
      #    without shifter levels»). Ложная нелегальность здесь была бы дороже
      #    исходной дыры.
      # ⚠️ Своя мудрость, а не `shape_build/1`: у трёх соседних фитов порог 25 и 27,
      # а у этого — 30, и общий помощник дал бы отказ по характеристике вместо
      # ответа на вопрос теста.
      dragon_build = fn levels ->
        Build.new(
          race: :human,
          alignment: :neutral,
          base_abilities: %{str: 10, dex: 12, con: 14, int: 12, wis: 30, cha: 8},
          levels: levels
        )
      end

      pure_druid = dragon_build.(List.duplicate(:druid, 21))
      assert Build.class_at(pure_druid, 21) == :druid

      for ruleset <- [vanilla, siala] do
        assert Rules.validate_feat(pure_druid, %{feat: :dragon_shape, at: 21}, ruleset) == :ok
      end

      # 3. И вторая ветка дизъюнкции жива своим ходом: Оборотень 10 владеет
      #    `greater wildshape IV`, и друида 18 ему не нужно.
      shifted = dragon_build.(List.duplicate(:shifter, 11) ++ List.duplicate(:druid, 13))
      assert Build.class_at(shifted, 24) == :druid
      assert Rules.validate_feat(shifted, %{feat: :dragon_shape, at: 24}, siala) == :ok

      # 4. Отрицательный контроль обеих веток сразу: друид 17 (дикий облик 5 раз
      #    в день) плюс Оборотень 4 — ни одна ветка не пройдена, а уровень
      #    законный, поэтому отказ ровно один и он про дизъюнкцию.
      short = dragon_build.(List.duplicate(:druid, 17) ++ List.duplicate(:shifter, 4))

      assert Rules.validate_feat(short, :dragon_shape, siala) ==
               {:error,
                [
                  requires_any_of: [
                    [{:requires_class_level, :druid, 18}],
                    [{:requires_feat, :greater_wildshape_iv}]
                  ]
                ]}
    end

    # ⚠️ ПРОВЕНАНС РАЗВЕДЁН, и стирать разницу нельзя: измерен ОДИН фит из трёх.
    # У двух других требования по МУДРОСТИ (27 и 25) поинт-баем не набираются,
    # а статы с вещей требований не выполняют (кейс S1) — на персонаже замера
    # они не показались бы и без всякого запрета по классу, то есть «не вижу»
    # там не значило бы ничего.
    #
    # Тест ловит день, когда кто-нибудь выровняет три записи «для единообразия»:
    # `verified` у неизмеренного — это утверждение, которого никто не делал.
    test "измерен один из трёх, и записи это говорят" do
      by_id = Map.new(file_entries(), &{&1["id"], &1})

      measured = by_id["undead_shape"]["only_on_class_levels_source"]
      assert measured["basis"] == "measurement"
      assert measured["status"] == "verified"

      for id <- ["construct_shape", "outsider_shape"] do
        source = by_id[id]["only_on_class_levels_source"]

        assert source["basis"] == "generalisation",
               "#{id} измерен не был — основание обязано называться обобщением"

        assert source["status"] == "unclear"
      end

      # …и все три стоят на одном и том же ответе Dan, а не на трёх разных.
      assert by_id
             |> Map.take(["undead_shape", "construct_shape", "outsider_shape"])
             |> Enum.map(fn {_id, e} -> e["only_on_class_levels_source"]["quote"] end)
             |> Enum.uniq()
             |> length() == 1
    end

    # Порча: убрать запись `undead_shape` — и ложная легальность возвращается
    # ровно там, где Dan её и измерил. Сторож против «правки заодно».
    #
    # ⚠️ Убирается ЗАПИСЬ целиком, а не ключ: у неё нет `requirements`, и
    # удаление одного ключа уронило бы сборку сторожем «applied обязан сказать,
    # что теперь проверяется» — то есть проверило бы сторож вместо правила.
    #
    # ⚠️ Порча делается на измеренном фите намеренно: если однажды окажется,
    # что обобщение шире правды, снимать придётся `construct_shape`
    # и `outsider_shape`, и сторож не должен этому мешать.
    test "без записи `undead_shape` снова берётся на уровне рейнджера" do
      root = copy_rules()
      drop_entry(root, "undead_shape")
      ruleset = Loader.load!(root)["siala_41"]

      on_ranger = shape_on_ranger()

      assert Rules.validate_feat(on_ranger, %{feat: :undead_shape, at: 24}, ruleset) == :ok

      # …а два соседа запрет сохранили: правило записано на каждый фит, а не
      # одной строкой на семью.
      for id <- @shape_family -- [:undead_shape] do
        assert Rules.validate_feat(on_ranger, %{feat: id, at: 24}, ruleset) ==
                 {:error, [forbidden_by_class: :ranger]}
      end
    end
  end

  # Четвёртая форма того же семейства: ограничение висит на ВЫБРАННОМ значении,
  # а не на фите. Механизм другой (`only_on_class_levels_for_skill`, читает
  # `Rules.Prereqs`), и форма отказа другая — `{:requires_leveling_as, [классы]}`,
  # потому что `{:forbidden_by_class, :fighter}` здесь сказал бы неправду: воин
  # берёт `Epic skill focus (discipline)` на своём уровне без всяких оговорок.
  #
  # source: fandom «Epic skill focus» revid 72105 (снято 2026-08-01), Notes —
  # «''Epic skill focus'' in [[animal empathy]] can be taken only when gaining a
  # [[druid]], [[ranger]], or [[shifter]] level. ''Epic skill focus'' in
  # [[perform]] can be taken only when gaining a [[bard]] level. ''Epic skill
  # focus'' in [[use magic device]] can be taken only when gaining a [[bard]] or
  # [[rogue]], or [[shadowdancer]] level».
  #
  # ⚠️ Проверяется на `siala_41`: в ванильном слое у фита нет `repeatable` вовсе
  # (страница не объявляет его повторяемым — это `siala_41/feats.json`,
  # `source.kind: user`), значит пик не несёт выбранного навыка и связать
  # ограничение не с чем. Отдельный тест ниже это и закрепляет, чтобы разница
  # между ruleset'ами не выглядела случайной.
  describe "«только на уровне класса X», когда X зависит от ВЫБОРА" do
    # 20 рангов навыка + 21-й уровень — оба настоящих требования страницы, иначе
    # отказ пришёл бы не про класс уровня. Ранги куплены на уровнях того класса,
    # которому навык классовый: у трёх ограниченных навыков кросс-классово их
    # не купить вовсе (`exclusive?: true`).
    defp focus_build(first, first_levels, then, then_levels, skill) do
      Build.new(
        race: :human,
        alignment: :true_neutral,
        base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
        levels: List.duplicate(first, first_levels) ++ List.duplicate(then, then_levels),
        skills: %{first_levels => %{skill => 20}}
      )
    end

    defp focus_pick(skill), do: %{feat: :epic_skill_focus, choice: skill, at: 24}

    # ⚠️ Билды-близнецы: одинаковые 20 уровней друида и одинаковый 24-й уровень,
    # отличается только класс ЭТОГО уровня. По отдельности каждая половина
    # зеленела бы и при неверной модели — «на друидском берётся» проходит и при
    # выброшенном ограничении, «на воинском нет» — и при фите, недоступном всем.
    test "`(animal empathy)` берётся на уровне друида и не берётся на уровне воина", %{
      siala: siala
    } do
      on_druid = focus_build(:fighter, 4, :druid, 20, :animal_empathy)
      on_fighter = focus_build(:druid, 20, :fighter, 4, :animal_empathy)

      assert Build.class_at(on_druid, 24) == :druid
      assert Build.class_at(on_fighter, 24) == :fighter

      assert Rules.validate_feat(on_druid, focus_pick(:animal_empathy), siala) == :ok

      assert Rules.validate_feat(on_fighter, focus_pick(:animal_empathy), siala) ==
               {:error, [{:requires_leveling_as, [:druid, :ranger, :shifter]}]}
    end

    # Второй список, и он короче первого: у `perform` разрешён ровно один класс.
    # Без этой проверки правило могло бы применять один список ко всем навыкам.
    test "`(perform)` разрешён только барду", %{siala: siala} do
      on_bard = focus_build(:fighter, 4, :bard, 20, :perform)
      on_fighter = focus_build(:bard, 20, :fighter, 4, :perform)

      assert Rules.validate_feat(on_bard, focus_pick(:perform), siala) == :ok

      assert Rules.validate_feat(on_fighter, focus_pick(:perform), siala) ==
               {:error, [{:requires_leveling_as, [:bard]}]}
    end

    # ⚠️ Главный контроль против ОБРАТНОЙ ошибки, ради которого форма и заведена
    # своя: у 26 навыков из 29 ограничения нет вовсе, и запрет фита на воинском
    # уровне целиком (тот механизм, которым сделаны девять остальных членов
    # семейства) сделал бы этот законный пик ложно нелегальным.
    test "навык без ограничения берётся на уровне любого класса", %{siala: siala} do
      on_fighter = focus_build(:fighter, 20, :fighter, 4, :discipline)

      assert Rules.validate_feat(on_fighter, focus_pick(:discipline), siala) == :ok

      # И сам фит на воинском уровне слотом принимается — то есть ограничение
      # не переехало в `unavailable_feats`, где ему делать нечего.
      slot = Enum.find(FeatSlots.at(on_fighter, siala, 24), &(&1.kind == :epic_general))
      assert FeatSlots.accepts?(siala, slot, :epic_skill_focus)
      assert Rules.class_feat_refusals(on_fighter, 24, :epic_skill_focus, siala) == []
    end

    # Игрок видит это на втором шаге, где значения перечислены поимённо: панель
    # обязана показать ограниченный навык В СПИСКЕ, с причиной, а не спрятать.
    test "во втором шаге ограниченное значение стоит с причиной", %{siala: siala} do
      on_fighter = focus_build(:druid, 20, :fighter, 4, :animal_empathy)

      options = Feats.choice_options(siala, on_fighter, 24, :epic_skill_focus)
      blocked = Map.new(options.blocked, &{&1.value, &1.reasons})

      assert {:requires_leveling_as, [:druid, :ranger, :shifter]} in blocked[:animal_empathy]
      refute Enum.any?(options.allowed, &(&1.value == :animal_empathy))
    end

    # ⚠️ Разница между ruleset'ами названа, а не оставлена случайностью: на
    # `vanilla` фит не объявлен повторяемым, поэтому выбор не записывается и
    # ограничение связать не с чем. Ключ при этом в `prereqs` лежит на обоих —
    # он ванильного слоя, — и это ровно то, что тест различает.
    test "на `vanilla` ключ лежит, но выбора у пика нет", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        assert ruleset.feats[:epic_skill_focus].prereqs["only_on_class_levels_for_skill"] == %{
                 "animal_empathy" => ["druid", "ranger", "shifter"],
                 "perform" => ["bard"],
                 "use_magic_device" => ["bard", "rogue", "shadowdancer"]
               }
      end

      assert vanilla.feats[:epic_skill_focus].repeatable == nil
      assert siala.feats[:epic_skill_focus].repeatable.choice == :skill
    end

    # Пик без выбора не становится нелегальным: ограничение про значение, а
    # значения ещё нет — легальность пары проверяется на втором шаге.
    test "без выбора проверка ровно та, что была", %{siala: siala} do
      on_fighter = focus_build(:druid, 20, :fighter, 4, :animal_empathy)

      assert Rules.validate_feat(on_fighter, %{feat: :epic_skill_focus, at: 24}, siala) == :ok
    end

    # --------------------------------------------------------------- порча --

    # Сторона первая: убрать ключ — ложная легальность возвращается ровно там,
    # где была измерена до правки (оба навыка, один и тот же воинский уровень).
    test "без ключа фит снова берётся с ограниченным навыком на уровне воина" do
      root = copy_rules()

      edit_entry(root, "epic_skill_focus", fn entry ->
        %{
          entry
          | "requirements" => Map.delete(entry["requirements"], "only_on_class_levels_for_skill")
        }
      end)

      ruleset = Loader.load!(root)["siala_41"]

      for {skill, first} <- [animal_empathy: :druid, perform: :bard] do
        build = focus_build(first, 20, :fighter, 4, skill)

        assert Rules.validate_feat(
                 build,
                 %{feat: :epic_skill_focus, choice: skill, at: 24},
                 ruleset
               ) == :ok
      end
    end

    # Сторона вторая: разрешить воина — отказ обязан пропасть ровно там, где он
    # сейчас стоит. Обе половины «на друиде да / на воине нет» лежат в одном
    # тесте намеренно, поэтому эта порча роняет его.
    test "дописать воина в разрешённые — отказ пропадает" do
      root = copy_rules()

      edit_entry(root, "epic_skill_focus", fn entry ->
        put_in(entry, ["requirements", "only_on_class_levels_for_skill", "animal_empathy"], [
          "druid",
          "ranger",
          "shifter",
          "fighter"
        ])
      end)

      ruleset = Loader.load!(root)["siala_41"]
      build = focus_build(:druid, 20, :fighter, 4, :animal_empathy)

      assert Rules.validate_feat(
               build,
               %{feat: :epic_skill_focus, choice: :animal_empathy, at: 24},
               ruleset
             ) == :ok
    end

    # ⚠️ Опечатка в имени НАВЫКА роняет сборку: иначе ограничение просто не
    # совпало бы ни с чем и ложная легальность вернулась бы молча — та самая
    # дыра, которую запись закрывает.
    test "опечатка в имени навыка роняет сборку" do
      root = copy_rules()

      edit_entry(root, "epic_skill_focus", fn entry ->
        requirements =
          entry["requirements"]
          |> update_in(["only_on_class_levels_for_skill"], &Map.delete(&1, "perform"))
          |> put_in(["only_on_class_levels_for_skill", "preform"], ["bard"])

        %{entry | "requirements" => requirements}
      end)

      assert_raise RuntimeError, ~r/which is not a skill/, fn -> Loader.load!(root) end
    end

    # А опечатка в имени КЛАССА ошибается в другую сторону: список становится
    # короче, и законный пик делается нелегальным. Тоже молча — тоже сборкой.
    test "опечатка в имени класса роняет сборку" do
      root = copy_rules()

      edit_entry(root, "epic_skill_focus", fn entry ->
        put_in(entry, ["requirements", "only_on_class_levels_for_skill", "perform"], ["bardd"])
      end)

      assert_raise RuntimeError, ~r/which are not classes/, fn -> Loader.load!(root) end
    end

    # Пустой список — не «никому нельзя с этим навыком», а почти наверняка
    # авария разбора: такого правила нет ни на одной странице корпуса.
    test "пустой список классов роняет сборку" do
      root = copy_rules()

      edit_entry(root, "epic_skill_focus", fn entry ->
        put_in(entry, ["requirements", "only_on_class_levels_for_skill", "perform"], [])
      end)

      assert_raise RuntimeError, ~r/not a non-empty list of class ids/, fn ->
        Loader.load!(root)
      end
    end
  end

  # ПЯТАЯ форма, и единственная про СЛОТ: «''Epic skill focus'' in ''use magic
  # device'' cannot be selected as a rogue [[bonus feat]], but otherwise bonus
  # feat availability matches [[general feat]] availability» (fandom «Epic skill
  # focus» revid 72105, снято 2026-08-01, Notes).
  #
  # ⚠️ Запрет узок по ДВУМ осям сразу, и по отдельности каждая половина зеленеет
  # при слишком широком запрете: «в бонус вора с UMD нельзя» проходит и у фита,
  # выброшенного из бонусного пула вовсе, и у запрета на уровнях вора целиком.
  # Поэтому все три случая лежат в ОДНОМ тесте.
  describe "«не в бонусный слот класса X», когда X зависит от ВЫБОРА" do
    # Оба навыка классовые для вора и куплены на его уровнях: без 20 рангов
    # отказ пришёл бы про ранги, а не про слот, и тест не отличал бы одно
    # от другого. 24-й — первый эпический бонусный уровень вора (24, 28, 32,
    # 36, 40), а фиту нужен 21-й уровень персонажа, значит слот достижим.
    defp rogue_build do
      Build.new(
        race: :human,
        alignment: :true_neutral,
        base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
        levels: List.duplicate(:rogue, 24),
        skills: %{20 => %{use_magic_device: 20, discipline: 20}}
      )
    end

    defp slot_pick(slot, skill),
      do: %{feat: :epic_skill_focus, choice: skill, at: 24, slot: slot}

    test "бонусный слот вора не берёт `use magic device`, но берёт другой навык — и общий слот берёт оба",
         %{siala: siala} do
      build = rogue_build()
      bonus = {:class_bonus, :rogue}

      # (в) запрещённая пара — единственная из четырёх
      assert Rules.validate_feat_pick(build, slot_pick(bonus, :use_magic_device), siala) ==
               {:error, [{:not_in_class_bonus_slot, :rogue}]}

      # (б) тот же слот, другое значение — «cannot be selected as a rogue bonus
      # feat» сказано про UMD, а не про фит
      assert Rules.validate_feat_pick(build, slot_pick(bonus, :discipline), siala) == :ok

      # (а) то же значение, общий слот того же уровня — «otherwise bonus feat
      # availability matches general feat availability», то есть в общий слот
      # на уровне вора пара законна
      assert Rules.validate_feat_pick(build, slot_pick(:general, :use_magic_device), siala) == :ok
      assert Rules.validate_feat_pick(build, slot_pick(:general, :discipline), siala) == :ok
    end

    # ⚠️ И то же самое на ДОЭПИЧЕСКОМ бонусном слоте вора (классовый 19-й,
    # персонаж 21-й — самый дешёвый способ дотянуться до этого слота, кейс E8
    # в `GAME_CHECKS.md`): правило про слот, а не про эпичность слота. Порядок
    # уровней тут — половина смысла: у вора с 1-го уровня классовый 19-й
    # приходится на 19-й персонажа, где эпического фита нет вовсе.
    test "то же на доэпическом бонусном слоте вора — классовый 19-й на 21-м персонажа", %{
      siala: siala
    } do
      build =
        Build.new(
          race: :human,
          alignment: :true_neutral,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
          levels: List.duplicate(:fighter, 2) ++ List.duplicate(:rogue, 19),
          skills: %{21 => %{use_magic_device: 20, discipline: 20}}
        )

      assert Build.class_level_at(build, 21) == 19
      assert {:class_bonus, :rogue} in Enum.map(FeatSlots.at(build, siala, 21), & &1.id)

      assert Rules.validate_feat_pick(
               build,
               %{
                 feat: :epic_skill_focus,
                 choice: :use_magic_device,
                 at: 21,
                 slot: {:class_bonus, :rogue}
               },
               siala
             ) == {:error, [{:not_in_class_bonus_slot, :rogue}]}

      assert Rules.validate_feat_pick(
               build,
               %{
                 feat: :epic_skill_focus,
                 choice: :discipline,
                 at: 21,
                 slot: {:class_bonus, :rogue}
               },
               siala
             ) == :ok

      assert Rules.validate_feat_pick(
               build,
               %{feat: :epic_skill_focus, choice: :use_magic_device, at: 21, slot: :general},
               siala
             ) == :ok
    end

    # Слот принимает фит и после правки: ограничение висит на паре, а не на
    # членстве в бонусном пуле (`bonus4=rogue` на той же странице). Убери фит
    # из пула — и `Epic skill focus (discipline)` стал бы ложно нелегальным.
    test "фит остаётся в бонусном пуле вора", %{siala: siala} do
      slot = Enum.find(FeatSlots.at(rogue_build(), siala, 24), &(&1.kind == :class_bonus))

      assert slot.id == {:class_bonus, :rogue}
      assert FeatSlots.accepts?(siala, slot, :epic_skill_focus)
      assert :epic_skill_focus in FeatSlots.candidates(siala, slot)
      assert Rules.class_feat_refusals(rogue_build(), 24, :epic_skill_focus, siala) == []
    end

    # Игрок видит запрет на втором шаге, где значения перечислены поимённо:
    # ограниченное значение стоит В СПИСКЕ с причиной, а не спрятано (§6 прячет
    # только то, что этот же фит уже занял).
    test "во втором шаге запрещённое значение стоит с причиной, а в общем слоте — нет", %{
      siala: siala
    } do
      build = rogue_build()

      bonus = Feats.choice_options(siala, build, 24, :epic_skill_focus, {:class_bonus, :rogue})
      blocked = Map.new(bonus.blocked, &{&1.value, &1.reasons})

      assert blocked[:use_magic_device] == [{:not_in_class_bonus_slot, :rogue}]
      refute Enum.any?(bonus.allowed, &(&1.value == :use_magic_device))
      assert Enum.any?(bonus.allowed, &(&1.value == :discipline))

      general = Feats.choice_options(siala, build, 24, :epic_skill_focus, :general)
      assert Enum.any?(general.allowed, &(&1.value == :use_magic_device))
    end

    # Пик БЕЗ слота (тот же вопрос, но про персонажа) остаётся ровно тем, что
    # был: ограничение про слот, а `validate_feat/3` слота не знает и знать
    # не должен — иначе пара стала бы нелегальной и в общем слоте.
    test "без слота проверка ровно та, что была", %{siala: siala} do
      build = rogue_build()

      assert Rules.validate_feat(
               build,
               %{feat: :epic_skill_focus, choice: :use_magic_device, at: 24},
               siala
             ) ==
               :ok

      assert Rules.validate_feat_pick(
               build,
               %{feat: :epic_skill_focus, choice: :use_magic_device, at: 24},
               siala
             ) == :ok
    end

    # Уже поставленный пик (вставка текстом или правленая ссылка) обвиняется:
    # `Feats.best_slot/4` про выбор не знает и кладёт пару именно в бонусный
    # слот, поэтому без этого билд читался бы как законный.
    test "уже стоящая в бонусном слоте пара становится обвинением", %{siala: siala} do
      build = rogue_build()

      held =
        Build.put_feat(build, 24, {:class_bonus, :rogue}, :epic_skill_focus, :use_magic_device)

      assert Rules.illegal_feats(held, siala) == [
               {24, {:class_bonus, :rogue}, :epic_skill_focus, {:not_in_class_bonus_slot, :rogue}}
             ]

      # Обе половины узости — тем же вызовом, иначе обвинение могло бы стоять
      # на любом пике этого фита.
      legal = Build.put_feat(build, 24, :general, :epic_skill_focus, :use_magic_device)
      other = Build.put_feat(build, 24, {:class_bonus, :rogue}, :epic_skill_focus, :discipline)

      assert Rules.illegal_feats(legal, siala) == []
      assert Rules.illegal_feats(other, siala) == []
    end

    # ⚠️ На `vanilla` правило молчит — и это свойство ДАННЫХ, а не механизма:
    # повторяемость с выбором навыка объявил только шардовый слой, значит пик
    # там не несёт значения и пары не существует вовсе. Ключ при этом ванильный
    # и лежит на обоих ruleset'ах — ровно это тест и различает.
    test "на `vanilla` пара не складывается, и отказ не печатается", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala] do
        assert ruleset.feats[:epic_skill_focus].bonus_for_except ==
                 MapSet.new([{:rogue, :use_magic_device}])
      end

      build = rogue_build()

      # ⚠️ Ответ ровно тот, что был до правки: «значение записать нечем».
      # Печатать рядом ещё и отказ про слот значило бы объяснять, куда нельзя
      # положить пару, которой в этом ruleset'е не бывает.
      assert Rules.validate_feat_pick(
               build,
               slot_pick({:class_bonus, :rogue}, :use_magic_device),
               vanilla
             ) == {:error, [{:invalid_choice, :epic_skill_focus, :use_magic_device}]}

      assert FeatSlots.choice_refusals(
               vanilla,
               {:class_bonus, :rogue},
               :epic_skill_focus,
               :use_magic_device
             ) == []
    end

    # --------------------------------------------------------------- порча --

    # Сторона первая: убрать ключ — ложная легальность возвращается ровно
    # в том виде, в каком была измерена 11.08.2026.
    test "без ключа пара снова ложится в бонусный слот вора" do
      root = copy_rules()

      edit_entry(root, "epic_skill_focus", &Map.delete(&1, "not_in_class_bonus_slot_for_skill"))
      ruleset = Loader.load!(root)["siala_41"]

      assert Rules.validate_feat_pick(
               rogue_build(),
               slot_pick({:class_bonus, :rogue}, :use_magic_device),
               ruleset
             ) == :ok
    end

    # Сторона вторая: назвать другое значение — отказ обязан переехать на него
    # целиком, а не добавиться. Иначе правило читало бы карту не по ключу.
    test "другое значение в ключе — отказ переезжает" do
      root = copy_rules()

      edit_entry(root, "epic_skill_focus", fn entry ->
        Map.put(entry, "not_in_class_bonus_slot_for_skill", %{"discipline" => ["rogue"]})
      end)

      ruleset = Loader.load!(root)["siala_41"]
      bonus = {:class_bonus, :rogue}

      assert Rules.validate_feat_pick(rogue_build(), slot_pick(bonus, :discipline), ruleset) ==
               {:error, [{:not_in_class_bonus_slot, :rogue}]}

      assert Rules.validate_feat_pick(rogue_build(), slot_pick(bonus, :use_magic_device), ruleset) ==
               :ok
    end

    # ⚠️ Опечатка в имени НАВЫКА роняет сборку: иначе запрет не совпал бы ни
    # с одним пиком и ложная легальность вернулась бы молча.
    test "опечатка в имени навыка роняет сборку" do
      root = copy_rules()

      edit_entry(root, "epic_skill_focus", fn entry ->
        Map.put(entry, "not_in_class_bonus_slot_for_skill", %{"use_magick_device" => ["rogue"]})
      end)

      assert_raise RuntimeError, ~r/which is not a skill/, fn -> Loader.load!(root) end
    end

    # ⚠️ А класс, которого нет в бонусном пуле фита, — вторая половина той же
    # тишины: запрет существует и не запрещает ничего. Ошибиться так можно
    # опечаткой в имени класса и выпавшим из `bonus_for` классом, и оба случая
    # требуют перечитать страницу, а не подправить файл.
    test "класс не из бонусного пула роняет сборку" do
      root = copy_rules()

      edit_entry(root, "epic_skill_focus", fn entry ->
        Map.put(entry, "not_in_class_bonus_slot_for_skill", %{"use_magic_device" => ["fighter"]})
      end)

      assert_raise RuntimeError, ~r/is not on that feat's bonus list/, fn ->
        Loader.load!(root)
      end
    end

    test "пустой список классов роняет сборку" do
      root = copy_rules()

      edit_entry(root, "epic_skill_focus", fn entry ->
        Map.put(entry, "not_in_class_bonus_slot_for_skill", %{"use_magic_device" => []})
      end)

      assert_raise RuntimeError, ~r/not a non-empty list of class ids/, fn ->
        Loader.load!(root)
      end
    end

    test "пустая карта роняет сборку" do
      root = copy_rules()

      edit_entry(root, "epic_skill_focus", fn entry ->
        Map.put(entry, "not_in_class_bonus_slot_for_skill", %{})
      end)

      assert_raise RuntimeError, ~r/not a non-empty map/, fn -> Loader.load!(root) end
    end
  end

  # ---------------------------------------------------------------------------
  # Задача 3.104: `Skill focus` — «able to use the skill» расшифровано.
  #
  # Источник у всех кейсов один: `fandom:Skill focus`, revid 72101, секция
  # `Notes`. Четыре предложения, четыре ключа, и вся суть в том, что формы
  # у них разные:
  #
  #   1. «Skill focus in a skill that requires training can only be taken if the
  #      character is trained in that skill (has at least one rank in it)»;
  #   2. «Skill focus in animal empathy can be taken only when gaining a druid
  #      or ranger level, but not a shifter level. Skill focus in use magic
  #      device can be taken only when gaining a bard or rogue level, but not
  #      an assassin level»;
  #   3. «Skill focus in perform can be taken when leveling in ANY class, as
  #      long as the skill has been made accessible by taking at least one bard
  #      level»;
  #   4. «There is no skill focus in ride».
  #
  # ⚠️ До 25.08.2026 не проверялось НИЧЕГО из этого: фрагмент лежал в `unparsed`,
  # и `Rules.Prereqs.unread/1` отказывал фиту всем и на любой навык — ложная
  # нелегальность шириной во весь справочник навыков.
  describe "`Skill focus`: ранг там, где навык требует тренировки" do
    defp trained_build(skills) do
      Build.new(
        race: :human,
        alignment: :true_neutral,
        base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
        levels: List.duplicate(:rogue, 9),
        skills: skills
      )
    end

    defp focus(skill, level \\ 9), do: %{feat: :skill_focus, choice: skill, at: level}

    # Близнецы: один и тот же вор, одна и та же пара, разница ровно в ОДНОМ
    # ранге. По отдельности каждая половина зеленела бы и при неверной модели —
    # «без ранга нельзя» проходит и при фите, недоступном всем, «с рангом
    # можно» — и при выброшенном правиле.
    test "навык с тренировкой: 0 рангов — отказ, 1 ранг — можно", %{
      vanilla: vanilla,
      siala: siala
    } do
      none = trained_build(%{})
      one = trained_build(%{1 => %{tumble: 1}})

      for ruleset <- [vanilla, siala] do
        assert Rules.validate_feat(none, focus(:tumble), ruleset) ==
                 {:error, [{:requires_chosen_skill_ranks, :tumble, 1}]}

        assert Rules.validate_feat(one, focus(:tumble), ruleset) == :ok
      end
    end

    # ⚠️ Главный контроль против ОБРАТНОЙ ошибки: правило включает свойство
    # навыка, и навык без тренировки не должен требовать ничего. Иначе ложная
    # нелегальность просто сменила бы адрес.
    test "навык без тренировки берётся с нулём рангов", %{vanilla: vanilla, siala: siala} do
      none = trained_build(%{})

      for ruleset <- [vanilla, siala] do
        refute Map.fetch!(ruleset.skills, :listen).trained_only?
        assert Rules.validate_feat(none, focus(:listen), ruleset) == :ok
      end
    end

    # -------------------------------------------------------------------------
    # Задача 3.109 (26.08.2026): спор Fandom про `perform` разрешён ЗАМЕРОМ.
    #
    # `vanilla/skills.json` → perform несёт `status: "conflict"` с первого
    # разбора: лейбл страницы говорит «Requires training: no», а
    # `Category:Skills that require training` числит её своей. Задача 3.104
    # выбрала ЛЕЙБЛ по источниковому доводу (`fandom:Untrained skill check`:
    # «NWNWiki uses the former») и назвала выбор вслух гэпом.
    #
    # ✅ Замер Dan (`GAME_CHECKS.md` AC8), экран СОЗДАНИЯ персонажа, бард 1,
    # в Исполнение не вложено ни одного очка: «skill focus - perform доступен».
    # Лейбл прав, категория проставлена ошибочно.
    #
    # ⚠️ Замер стал возможен вопросом Dan, а не планом: состояние «нуль рангов,
    # список фитов открыт» дважды объявляли ненаблюдаемым, а на создании
    # персонажа навыки идут РАНЬШЕ фитов, и оно видно прямо там.

    # ⚠️ Тест держит ДВА разных утверждения сразу, и поодиночке каждое зеленело
    # бы при неверной модели: (а) фит доступен барду с НУЛЁМ рангов — это и есть
    # измеренное; (б) без уровня барда он по-прежнему отказан — часть правила
    # про КЛАСС замер не трогал вовсе (бард им и мерил), и растянуть измерение
    # на неё было бы выдумкой.
    test "измеренный билд: `(perform)` у барда 1 с НУЛЁМ рангов Исполнения", %{
      vanilla: vanilla,
      siala: siala
    } do
      bard = Build.new(race: :human, alignment: :true_neutral, levels: [:bard])
      wizard = Build.new(race: :human, alignment: :true_neutral, levels: [:wizard])

      # Ровно то состояние, которое Dan видел на экране: очков не вложено.
      assert Build.skill_ranks(bard, :perform, 1) == 0

      for ruleset <- [vanilla, siala] do
        assert Rules.validate_feat(bard, focus(:perform, 1), ruleset) == :ok

        assert Rules.validate_feat(wizard, focus(:perform, 1), ruleset) ==
                 {:error, [{:requires_class_level, :bard, 1}]}
      end
    end

    # Обе половины спора лежат в словаре РЯДОМ, и это не дубль: читается лейбл
    # (`trained_only?`), а вторая половина (`trained_only_category?`) существует
    # ровно затем, чтобы расхождение можно было НАЗВАТЬ. Свернуть их в одно поле
    # значило бы сделать выбор молчаливым.
    #
    # ⚠️ `status: "conflict"` у самой записи навыка замер НЕ сглаживает: спор
    # в источнике реален, наблюдение говорит, КАКАЯ сторона права, а не что
    # спора не было. Поле машинное — `mix wiki.parse` пишет файл целиком.
    test "у `perform` лейбл и категория спорят, и обе половины загружены", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala] do
        perform = Map.fetch!(ruleset.skills, :perform)

        refute perform.trained_only?
        assert perform.trained_only_category?

        # Положительный контроль: там, где стороны согласны, обе половины
        # одинаковы — иначе проверка выше зеленела бы и при поле-константе.
        tumble = Map.fetch!(ruleset.skills, :tumble)
        assert tumble.trained_only?
        assert tumble.trained_only_category?
      end

      assert Enum.find(file_skills(), &(&1["id"] == "perform"))["status"] == "conflict"
    end

    # 🔴 РЕШЕНИЕ ЗАДАЧИ 3.109: гэп после замера ОСТАЁТСЯ, и это выбор, а не
    # инерция. Он говорит про ИСТОЧНИК, а не про нашу неуверенность, и замер
    # не сделал ложным ни одного его слова: страница спорит сама с собой
    # по-прежнему, лейбл берём по-прежнему. Снимали 24–25.08.2026 (3.90, 3.93,
    # 3.95) другое — фразы «не считаем» и «это допущение», то есть ложную
    # неуверенность про НАШ ответ. Разбор — в `vanilla/feat_requirements.json`
    # → `skill_focus` → `note`.
    test "спор назван вслух гэпом на обоих ruleset'ах — и ПОСЛЕ замера тоже", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala] do
        assert {:conflict, {:skill_trained_only, :perform, :category_only}} in ruleset.gaps
      end
    end

    # ⚠️ Синтетический контроль: механизм читает ДАННЫЕ, а не имя `perform`,
    # и знает ОБЕ стороны спора. Контроль на живой записи проверяет только её
    # саму и молча перестаёт что-либо значить в день, когда запись починят
    # (урок 3.93/3.95, CLAUDE.md §9).
    test "второй такой спор дал бы второй гэп, и сторона считается по данным" do
      root = copy_rules()
      path = Path.join(root, "vanilla/skills.json")

      skills =
        path
        |> File.read!()
        |> Jason.decode!()
        |> Enum.map(fn skill ->
          case skill["id"] do
            # У обоих сегодня обе стороны говорят «тренировки не требует».
            # Разводим их в РАЗНЫЕ стороны — по одной на каждое значение формы.
            "listen" -> Map.put(skill, "trained_only_category", true)
            "spot" -> Map.put(skill, "trained_only", true)
            _ -> skill
          end
        end)

      File.write!(path, Jason.encode!(skills))

      assert %{"vanilla" => vanilla} = Loader.load!(root)

      assert {:conflict, {:skill_trained_only, :listen, :category_only}} in vanilla.gaps
      assert {:conflict, {:skill_trained_only, :spot, :label_only}} in vanilla.gaps
      assert {:conflict, {:skill_trained_only, :perform, :category_only}} in vanilla.gaps
    end

    # Перепись по ВСЕМ навыкам обоих ruleset'ов: правило обязано кусать ровно
    # тех, кого называет источник, и молчать про остальных. Числом, а не
    # поимённо, тест бы не заметил подмену одного навыка другим.
    #
    # 🔴 С задачи 3.106 списки ruleset'ов РАЗЪЕХАЛИСЬ ровно на `ride`, и это
    # единственное отличие: на Сиале вариант измерен (`GAME_CHECKS.md` AB1),
    # в ванили строка Fandom верна. Перепись поимённо это и ловит — числом
    # «10 и 10» правка выглядела бы как подмена одного навыка другим.
    test "правило задевает ровно 10 навыков ванили и 9 Сиалы, остальные 18 и 20 — нет", %{
      vanilla: vanilla,
      siala: siala
    } do
      # Воин, чтобы ни один из трёх ограниченных навыков не проходил по классу.
      fighter =
        Build.new(
          race: :human,
          alignment: :true_neutral,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
          levels: List.duplicate(:fighter, 9)
        )

      nine = [
        :animal_empathy,
        :disable_trap,
        :open_lock,
        :perform,
        :pick_pocket,
        :set_trap,
        :spellcraft,
        :tumble,
        :use_magic_device
      ]

      for {ruleset, total, expected} <- [
            {vanilla, 28, Enum.sort([:ride | nine])},
            {siala, 29, nine}
          ] do
        {touched, untouched} =
          ruleset.skills
          |> Map.keys()
          |> Enum.split_with(&(Rules.validate_feat(fighter, focus(&1), ruleset) != :ok))

        assert length(touched) + length(untouched) == total
        assert Enum.sort(touched) == expected

        # ⚠️ `alchemy` — среди НЕзадетых, и это не случайность: её
        # `trained_only` не назвал никто, запись числит поле в `unknown_fields`,
        # и умолчание словаря пермиссивное. Разбор — в `note` записи
        # `skill_focus` в `feat_requirements.json`.
        assert length(untouched) == total - length(expected)
      end
    end

    # «The bonus from this feat does not help meet prerequisites» — та же
    # секция. У нас это соблюдается ПО ПОСТРОЕНИЮ: требование читает ранги,
    # а +3 фита падает в значение навыка (задача 3.92). Тест закрепляет
    # построение, потому что «по построению» ломается молча.
    test "прибавка самого фита требование не выполняет", %{siala: siala} do
      # `Skill focus (Tumble)` уже взят на 3-м уровне, рангов Кувырка нет.
      taken =
        Build.new(
          race: :human,
          alignment: :true_neutral,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
          levels: List.duplicate(:rogue, 9),
          feats: %{3 => %{general: {:skill_focus, :tumble}}}
        )

      assert Rules.validate_feat(taken, focus(:tumble), siala) ==
               {:error, [{:requires_chosen_skill_ranks, :tumble, 1}]}
    end
  end

  describe "`Skill focus`: класс уровня и состав билда — РАЗНЫЕ правила" do
    defp focus_at(class, before_levels, class_levels, skills) do
      Build.new(
        race: :human,
        alignment: :true_neutral,
        base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
        levels: List.duplicate(class, class_levels) ++ List.duplicate(:fighter, before_levels),
        skills: skills
      )
    end

    # 🔴 Первый из трёх отрицательных контролей задачи: у Оборотня Эмпатия
    # ЕСТЬ (навык классовый), а фит источник ему запрещает поимённо.
    test "Оборотень не берёт `(animal empathy)` на своём уровне, а друид и рейнджер — берут", %{
      siala: siala
    } do
      # Оборотень требует друида 5, поэтому 6 уровней друида под ним.
      shifter =
        Build.new(
          race: :human,
          alignment: :true_neutral,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
          levels: List.duplicate(:druid, 6) ++ List.duplicate(:shifter, 3),
          skills: %{1 => %{animal_empathy: 4}}
        )

      assert Build.class_at(shifter, 9) == :shifter
      assert :animal_empathy in Map.fetch!(siala.classes, :shifter).class_skills

      assert Rules.validate_feat(shifter, focus(:animal_empathy), siala) ==
               {:error, [{:requires_leveling_as, [:druid, :ranger]}]}

      # ...и оба разрешённых класса берут его на своём уровне.
      druid = focus_at(:druid, 0, 9, %{1 => %{animal_empathy: 4}})
      ranger = focus_at(:ranger, 0, 9, %{1 => %{animal_empathy: 4}})

      assert Rules.validate_feat(druid, focus(:animal_empathy), siala) == :ok
      assert Rules.validate_feat(ranger, focus(:animal_empathy), siala) == :ok
    end

    # Второй отрицательный контроль, и список у него ДРУГОЙ — значит одно
    # правило не применяется ко всем ограниченным навыкам скопом.
    test "Ассасин не берёт `(use magic device)` на своём уровне, а бард и вор — берут", %{
      siala: siala
    } do
      assassin =
        Build.new(
          race: :human,
          alignment: {:neutral, :evil},
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
          levels: List.duplicate(:rogue, 6) ++ List.duplicate(:assassin, 3),
          skills: %{1 => %{use_magic_device: 4}}
        )

      assert Build.class_at(assassin, 9) == :assassin
      assert :use_magic_device in Map.fetch!(siala.classes, :assassin).class_skills

      assert Rules.validate_feat(assassin, focus(:use_magic_device), siala) ==
               {:error, [{:requires_leveling_as, [:bard, :rogue]}]}

      bard = focus_at(:bard, 0, 9, %{1 => %{use_magic_device: 4}})
      rogue = focus_at(:rogue, 0, 9, %{1 => %{use_magic_device: 4}})

      assert Rules.validate_feat(bard, focus(:use_magic_device), siala) == :ok
      assert Rules.validate_feat(rogue, focus(:use_magic_device), siala) == :ok
    end

    # 🔴 ГЛАВНЫЙ КОНТРОЛЬ ЗАДАЧИ, и он про форму правила, а не про число:
    # у `perform` условие на СОСТАВ БИЛДА, а не на класс уровня. Написать его
    # соседним ключом `only_on_class_levels_for_skill` значило бы запретить
    # барду-воину взять фит на воинском уровне — чего источник прямо
    # не запрещает («can be taken when leveling in any class»).
    test "`(perform)`: без барда нельзя, бард-воин берёт НА ВОИНСКОМ уровне", %{
      vanilla: vanilla,
      siala: siala
    } do
      no_bard =
        Build.new(
          race: :human,
          alignment: :true_neutral,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
          levels: List.duplicate(:fighter, 9)
        )

      bard_fighter =
        Build.new(
          race: :human,
          alignment: :true_neutral,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
          levels: [:bard | List.duplicate(:fighter, 8)]
        )

      for ruleset <- [vanilla, siala] do
        assert Rules.validate_feat(no_bard, focus(:perform), ruleset) ==
                 {:error, [{:requires_class_level, :bard, 1}]}

        # Уровень, на котором тратится слот, — ВОИНСКИЙ, и это половина теста.
        assert Build.class_at(bard_fighter, 9) == :fighter
        assert Rules.validate_feat(bard_fighter, focus(:perform), ruleset) == :ok
      end
    end

    # ⚠️ Соседняя половина того же различения: у ЭПИЧЕСКОГО близнеца правило
    # обратное («only when gaining a bard level»), и списки двух страниц
    # расходятся ещё в двух местах. Перенести один на другой было бы ошибкой
    # в обе стороны сразу, и вот она под тестом.
    test "две страницы одной семьи говорят про `perform` РАЗНОЕ", %{siala: siala} do
      assert siala.feats[:skill_focus].prereqs["class_levels_for_skill"] == %{
               "perform" => %{"bard" => 1}
             }

      # ⚠️ Ключ у обычного фокуса ЕСТЬ (в нём два других навыка), а `perform`
      # в нём нет — именно это и надо различить: «ключа нет» и «навыка нет
      # в ключе» выглядят одинаково у пустого справочника.
      refute Map.has_key?(
               siala.feats[:skill_focus].prereqs["only_on_class_levels_for_skill"],
               "perform"
             )

      assert siala.feats[:epic_skill_focus].prereqs["only_on_class_levels_for_skill"]["perform"] ==
               ["bard"]

      refute Map.has_key?(siala.feats[:epic_skill_focus].prereqs, "class_levels_for_skill")

      # И списки двух других навыков тоже разошлись — Оборотень и Теневой
      # танцор есть у эпического и нет у обычного.
      assert siala.feats[:skill_focus].prereqs["only_on_class_levels_for_skill"] == %{
               "animal_empathy" => ["druid", "ranger"],
               "use_magic_device" => ["bard", "rogue"]
             }
    end

    # Игрок видит ограничение на втором шаге, где значения перечислены
    # поимённо: ограниченный навык обязан стоять В СПИСКЕ с причиной, а не
    # исчезать (CLAUDE.md §6).
    test "во втором шаге ограниченные значения стоят с причиной", %{
      vanilla: vanilla,
      siala: siala
    } do
      fighter =
        Build.new(
          race: :human,
          alignment: :true_neutral,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
          levels: List.duplicate(:fighter, 9)
        )

      options = Feats.choice_options(siala, fighter, 9, :skill_focus)
      blocked = Map.new(options.blocked, &{&1.value, &1.reasons})

      assert {:requires_class_level, :bard, 1} in blocked[:perform]
      assert {:requires_leveling_as, [:druid, :ranger]} in blocked[:animal_empathy]

      # ...а незадетые навыки остаются предложением, а не уезжают в отказы.
      assert Enum.any?(options.allowed, &(&1.value == :discipline))

      # 🔴 `ride` переехал из отказов в предложение — задача 3.106, замер AB1.
      # Пара строк рядом, потому что поодиночке каждая зеленела бы и при
      # сломанной правке: «нет в отказах» верно и у навыка, исчезнувшего
      # из справочника вовсе.
      refute Map.has_key?(blocked, :ride)
      assert Enum.any?(options.allowed, &(&1.value == :ride))

      # Ванильный контроль тем же вызовом: там он по-прежнему в отказах,
      # и причина та же, что была на Сиале до замера.
      vanilla_blocked =
        vanilla
        |> Feats.choice_options(fighter, 9, :skill_focus)
        |> Map.fetch!(:blocked)
        |> Map.new(&{&1.value, &1.reasons})

      assert {:invalid_choice, :skill_focus, :ride} in vanilla_blocked[:ride]
    end
  end

  describe "`Skill focus`: варианта в Верховой езде не существует — в ВАНИЛИ" do
    # Один и тот же персонаж на оба ruleset'а: 24 уровня (эпический близнец
    # требует 21-го), ранги в обоих навыках (иначе отказ пришёл бы за ранги
    # и прятал бы тот, который мы измеряем).
    defp rider(ranks \\ %{ride: 4, discipline: 20}) do
      Build.new(
        race: :human,
        alignment: :true_neutral,
        base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14},
        levels: List.duplicate(:fighter, 24),
        skills: %{1 => ranks}
      )
    end

    # «There is no skill focus in [[ride]]» / «There is no *epic skill focus*
    # in [[ride]]» — отдельными предложениями на двух страницах.
    #
    # ⚠️ Отказ формой словаря выбора, а не «чего-то не хватает»: пары просто
    # нет, как нет `Favored enemy (Ooze)`. Игроку нечего дотягивать.
    #
    # 🔴 Здесь стояло «оба фита отказывают на ОБОИХ ruleset'ах» — снято
    # задачей 3.106 замером Dan 25.08.2026 (`GAME_CHECKS.md` AB1): «замерил,
    # skill focus - ride присутствует». Ванильная строка верна про ваниль
    # и неприменима к шарду, который навык оживил.
    test "оба фита отказывают в `ride` и берут соседний навык", %{vanilla: vanilla} do
      ride = rider()

      assert Rules.validate_feat(ride, focus(:ride, 24), vanilla) ==
               {:error, [{:invalid_choice, :skill_focus, :ride}]}

      assert Rules.validate_feat(ride, focus(:discipline, 24), vanilla) == :ok

      # ⚠️ Про эпического близнеца ваниль спросить НЕЛЬЗЯ, и это не пробел
      # в тесте: у `epic_skill_focus` в ванильном слое нет `repeatable`
      # (страница не пишет «may be selected multiple times»), значит пик
      # не несёт выбранного навыка и связывать ограничение не с чем. Ключ
      # там лежит и выстрелить не может — ровно как у требования «20 рангов
      # в ВЫБРАННОМ навыке». Его сторона проверена на Сиале ниже.
      assert vanilla.feats[:epic_skill_focus].repeatable == nil
    end

    # 🔴 ДВА ЗАМЕРА, ДВЕ ЗАПИСИ, ОДИН ОТВЕТ (задачи 3.106 и 3.108). Обычный
    # вариант на Сиале есть — AB1, 25.08.2026; эпический — AB2, 26.08.2026.
    #
    # ⚠️ Здесь стояло «на Сиале снят ровно у обычного фокуса, у эпического
    # стоит», и это было ПРАВИЛЬНЫМ решением с неверным по итогу ответом: AB1
    # сделан на 1-м уровне, а эпический близнец требует 21-го и 20 рангов
    # навыка, то есть в списке показаться не мог вовсе. Растянуть измерение
    # одной страницы на её сестру — ход, которым дважды ломались потолки
    # (CLAUDE.md §9), и направление ошибки при нём худшее: ложная легальность.
    # Ответ совпал, но узнан он вторым замером, а не выводом из первого.
    #
    # ⚠️ Записей в сиальском слое всё равно ДВЕ, и это не дубль: у каждого фита
    # свой ванильный запрет со своей страницы, а списки этих страниц совпадают
    # только на `ride` — соседний тест ниже держит `perform` и `animal_empathy`
    # там, где они лежат.
    test "на Сиале снят у ОБОИХ фитов, и каждый — своей записью", %{
      vanilla: vanilla,
      siala: siala
    } do
      assert vanilla.feats[:skill_focus].prereqs["no_feat_variant_for_skills"] == ["ride"]
      assert vanilla.feats[:epic_skill_focus].prereqs["no_feat_variant_for_skills"] == ["ride"]

      assert siala.feats[:skill_focus].prereqs["no_feat_variant_for_skills"] == []
      assert siala.feats[:epic_skill_focus].prereqs["no_feat_variant_for_skills"] == []

      # Каждая половина снята СВОЕЙ записью ручного слоя, а не одной на семью:
      # снеси запись — вернётся запрет ровно у своего фита.
      for id <- [:skill_focus, :epic_skill_focus] do
        assert Enum.any?(
                 siala.feats[id].siala_changes,
                 &(&1["what"] == "feat_variant_exists" and &1["value"]["value"] == "ride")
               ),
               "у #{id} нет своей записи feat_variant_exists"
      end
    end

    # То же самое, но живьём — ответом ядра, а не полем словаря. ⚠️ Билд здесь
    # СВОЙ: у `rider/0` четыре ранга Верховой езды, а эпический фокус требует
    # двадцати, и на нём отказ пришёл бы от рангов — то есть тест зеленел бы
    # и при невынутом запрете.
    test "и это видно ответом ядра, а не только словарём", %{
      vanilla: vanilla,
      siala: siala
    } do
      ride = rider()
      ranked = rider(%{ride: 20, discipline: 20})
      epic = %{feat: :epic_skill_focus, choice: :ride, at: 24}

      assert Rules.validate_feat(ride, focus(:ride, 24), siala) == :ok
      assert Rules.validate_feat(ranked, epic, siala) == :ok
      assert Rules.validate_feat_pick(ranked, epic, siala) == :ok

      # Ваниль по-прежнему отбивает — но ДРУГИМ правилом, и это надо назвать
      # вслух: `no_feat_variant_for_skills` там выстрелить не может (у фита нет
      # `repeatable`, значит пик не несёт навыка), поэтому отказ приходит от
      # словаря выбора — «значение на фите, который значений не принимает».
      assert Rules.validate_feat_pick(ranked, epic, vanilla) ==
               {:error, [{:invalid_choice, :epic_skill_focus, :ride}]}

      # Положительный контроль ровно на ту разницу: соседний навык на Сиале
      # тоже берётся, то есть правка сняла ЗАПРЕТ, а не требование рангов.
      assert Rules.validate_feat(
               ranked,
               %{feat: :epic_skill_focus, choice: :discipline, at: 24},
               siala
             ) ==
               :ok

      # И отрицательный: навык без рангов отбивается по рангам, а не молчит.
      assert Rules.validate_feat(
               ranked,
               %{feat: :epic_skill_focus, choice: :tumble, at: 24},
               siala
             ) ==
               {:error, [{:requires_chosen_skill_ranks, :tumble, 20}]}
    end

    # ⚠️ Снят ОДИН ключ и ОДНО значение в нём. Остальные три предложения той же
    # страницы шард не трогал, и подтвердить это надо здесь же: дельта, которая
    # заодно унесла бы соседний ключ, выглядела бы точно так же на строке про
    # `ride`.
    test "остальные три ключа записи не сдвинулись", %{vanilla: vanilla, siala: siala} do
      for key <- ~w(chosen_skill_ranks_if_trained_only only_on_class_levels_for_skill
                    class_levels_for_skill) do
        assert siala.feats[:skill_focus].prereqs[key] ==
                 vanilla.feats[:skill_focus].prereqs[key],
               "ключ #{key} разъехался между ruleset'ами"
      end
    end

    # Девять остальных навыков, которых касается запись `skill_focus`, обязаны
    # отвечать на обоих ruleset'ах одинаково: правка называет одно значение.
    test "девять задетых навыков отвечают одинаково на обоих ruleset'ах", %{
      vanilla: vanilla,
      siala: siala
    } do
      ride = rider()

      for skill <- ~w(animal_empathy disable_trap open_lock perform pick_pocket
                      set_trap spellcraft tumble use_magic_device)a do
        assert Rules.validate_feat(ride, focus(skill, 24), vanilla) ==
                 Rules.validate_feat(ride, focus(skill, 24), siala),
               "навык #{skill} отвечает по-разному"
      end
    end

    # Три отрицательных контроля задачи 3.104 — правка 3.106 обязана оставить
    # их на месте: она про существование ПАРЫ, а не про то, чей уровень тратит
    # слот. Оборотень, Ассасин и персонаж без барда по-прежнему отбиваются.
    test "запреты по классу уровня целы", %{siala: siala} do
      shifter =
        Build.new(levels: List.duplicate(:druid, 5) ++ [:shifter], skills: %{1 => %{ride: 1}})

      assert {:error, reasons} = Rules.validate_feat(shifter, focus(:animal_empathy, 6), siala)
      assert {:requires_leveling_as, [:druid, :ranger]} in reasons

      assassin =
        Build.new(levels: List.duplicate(:rogue, 8) ++ [:assassin], skills: %{1 => %{ride: 1}})

      assert {:error, reasons} = Rules.validate_feat(assassin, focus(:use_magic_device, 9), siala)
      assert {:requires_leveling_as, [:bard, :rogue]} in reasons

      fighter = Build.new(levels: List.duplicate(:fighter, 9))

      assert {:error, reasons} = Rules.validate_feat(fighter, focus(:perform, 9), siala)
      assert {:requires_class_level, :bard, 1} in reasons
    end
  end

  describe "the guards against drifting apart from the machine layer" do
    # `replaces` is what stood in `vanilla/feats.json` when the entry was
    # written. A re-parse that changes the reading must not leave a human
    # reading attached to a prerequisite that no longer says what it said.
    test "a prereqs block that moved raises instead of applying" do
      root = copy_rules()

      edit_entry(root, "curse_song", fn entry ->
        Map.put(entry, "replaces", %{"unparsed" => ["something new"]})
      end)

      assert_raise RuntimeError, ~r/but it now reads/, fn -> Loader.load!(root) end
    end

    test "an entry naming a feat that does not exist raises" do
      root = copy_rules()

      edit_entry(root, "curse_song", fn entry -> %{entry | "id" => "curse_serenade"} end)

      assert_raise RuntimeError, ~r/not a feat/, fn -> Loader.load!(root) end
    end

    # The hand-written block goes through the same filter the machine one
    # does, so a key `Rules.Prereqs` cannot check cannot be smuggled in under
    # a verdict of `applied`.
    test "an entry using a key the interpreter does not know raises" do
      root = copy_rules()

      edit_entry(root, "curse_song", fn entry ->
        put_in(entry["requirements"]["not_a_real_key"], 1)
      end)

      assert_raise RuntimeError, ~r/unknown keys/, fn -> Loader.load!(root) end
    end

    # ⚠️ Сообщение называет ТРИ ключа с 11.08.2026: `applied` бывает и без
    # `requirements`, когда прочитано только ограничение — по уровню взятия
    # (`only_on_class_levels`) или по слоту (`not_in_class_bonus_slot_for_skill`).
    # Сторож остался тем же — «applied обязан сказать, что теперь проверяется», —
    # но пустыми должны быть все три.
    test "an applied entry stating neither requirements nor a restriction raises" do
      root = copy_rules()

      edit_entry(root, "curse_song", fn entry -> Map.put(entry, "requirements", %{}) end)

      assert_raise RuntimeError, ~r/states neither requirements nor a restriction/, fn ->
        Loader.load!(root)
      end
    end

    # The verdict is a claim about *why* nothing is checked, so an entry
    # cannot make it while also stating requirements — that would be an
    # `applied` entry wearing the wrong label, silently ignored.
    #
    # 🔴 Вердикт `not_binding` СИНТЕЗИРУЕТСЯ, и с 25.08.2026 иначе нельзя:
    # `skill_focus` был последней и единственной записью с ним, а задача 3.104
    # его прочитала. Носителей у вердикта ноль, сам вердикт жив — ровно тот же
    # случай, что у форм словаря без носителей (CLAUDE.md §9): контроль на живой
    # записи назавтра получает другой вердикт и молча перестаёт что-либо
    # проверять, а синтетический ловит день, когда сторож сломают.
    test "a not_binding entry may not state requirements" do
      root = copy_rules()

      edit_entry(root, "two_weapon_fighting", fn entry ->
        entry
        |> Map.put("verdict", "not_binding")
        |> Map.put("requirements", %{"character_level" => 21})
      end)

      assert_raise RuntimeError, ~r/is "not_binding" but states requirements/, fn ->
        Loader.load!(root)
      end
    end

    # ...and it is still held to the machine layer, exactly like an applied
    # entry: the day the parser reads the prose an entry was written for, that
    # entry has to be reread, not left describing a place that changed.
    test "a not_binding entry is guarded exactly like an applied one" do
      root = copy_rules()

      edit_entry(root, "two_weapon_fighting", fn entry ->
        entry
        |> Map.put("verdict", "not_binding")
        |> Map.put("replaces", %{"unparsed" => ["a different fragment"]})
      end)

      assert_raise RuntimeError, ~r/but it now reads/, fn -> Loader.load!(root) end
    end
  end

  # A full copy of `priv/rules`, so `load!/1` sees everything it normally does
  # and only the one file under test differs.
  # Записи файла как они лежат на диске. Нужны там, где проверяется САМА запись,
  # а не её следствие в ruleset'е: провенанс ключа и отсутствие ключа у
  # `dragon_shape` через загруженный ruleset не видны вовсе — у первого нет
  # получателя в модели, второе неотличимо от «ключ есть, но вердикт его
  # не читает».
  defp file_entries do
    "priv/rules" |> Path.join(@path) |> File.read!() |> Jason.decode!() |> Map.fetch!("feats")
  end

  # ⚠️ Файл машинный — `mix wiki.parse` пишет его целиком, — поэтому `status`
  # записи навыка читается ИЗ ФАЙЛА, а не из загруженного словаря: словарь
  # его не несёт вовсе, и «спор в источнике» проверяется там, где он написан.
  defp file_skills do
    "priv/rules/vanilla/skills.json" |> File.read!() |> Jason.decode!()
  end

  defp copy_rules do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp edit_entry(root, id, fun) do
    path = Path.join(root, @path)
    data = path |> File.read!() |> Jason.decode!()

    entries =
      Enum.map(data["feats"], fn entry ->
        if entry["id"] == id, do: fun.(entry), else: entry
      end)

    File.write!(path, Jason.encode!(%{data | "feats" => entries}))
  end

  # Убрать запись целиком, а не ключ. Нужно там, где запись стоит БЕЗ
  # `requirements` (прочитано только ограничение по уровню взятия): удаление
  # ключа у такой записи роняет сборку сторожем «applied обязан сказать, что
  # теперь проверяется», то есть проверило бы сторож вместо правила.
  # ⚠️ Записи сиальского слоя, которые ЧИТАЮТ этот файл, — их приходится снимать
  # вместе с ним, и это не ослабление контроля выше, а его честная форма.
  # `siala_41/feats.json` → `skill_focus` / `feat_variant_exists` снимает ОДНО
  # значение из ванильного `no_feat_variant_for_skills` (задача 3.106, замер
  # AB1), и загрузчик намеренно падает, если снимать оказалось нечего: запись,
  # которая ничего не сняла, выглядит применённой, ничего не сделав. Убрать
  # ванильный файл, оставив её, — состояние, которого в репозитории быть
  # не может; «убрать слой» значит убрать и его читателей.
  #
  # ⚠️ Проверять этим сторож НЕЛЬЗЯ — он проверяется синтетикой в
  # `siala_feat_layer_test.exs`: здесь запись просто убирается с дороги.
  defp drop_shard_readers_of_this_file(root) do
    path = Path.join(root, "siala_41/feats.json")
    data = path |> File.read!() |> Jason.decode!()

    entries =
      Enum.map(data["feats"], fn entry ->
        Map.put(
          entry,
          "changes",
          Enum.reject(entry["changes"] || [], &(&1["what"] == "feat_variant_exists"))
        )
      end)

    File.write!(path, Jason.encode!(%{data | "feats" => entries}))
  end

  defp drop_entry(root, id) do
    path = Path.join(root, @path)
    data = path |> File.read!() |> Jason.decode!()
    entries = Enum.reject(data["feats"], &(&1["id"] == id))

    File.write!(path, Jason.encode!(%{data | "feats" => entries}))
  end
end
