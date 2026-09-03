defmodule BuildCalculator.Data.SialaFeatLayerTest do
  @moduledoc """
  `priv/rules/siala_41/generated/feats.json` laid over the vanilla dictionary.

  Every expectation below is read off that file, and every one of them is a
  place where the shard and Fandom disagree — which is the point: until this
  layer was wired in, a calculator calling itself Siala's answered with vanilla's
  feat rules.

  Layering is `vanilla -> siala generated -> siala manual` (README beside the
  files).

  ⚠ Here also live two facts that come off the **manual** layer instead, because
  no page of either wiki states them at all and their only source is a player's
  own observation (`GAME_CHECKS.md` H1 and H5, Dan 09.08.2026): the class ban on
  `Brew Potion` being lifted, and the eight vanilla weapon proficiencies being
  switched off. They are tested here rather than beside the repeatability records
  because the mechanism is this file's: `Devastating critical`'s `disabled` is
  the same `what`, only arrived at by the parser.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatSlots, GearWeapon}
  alias BuildCalculatorWeb.Builder.Feats

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  describe "requirements are restated, not merged" do
    # source: siala «Brew Potion» revid 20388 — «Знание (Lore) 4.» replaces the
    # vanilla «spellcaster level 3+», so a non-caster may brew.
    #
    # ⚠️ Задача 3.120, заход 1 (data-miner, 27.08.2026): vanilla's own
    # `caster_level: 3` is no longer a bare, uninterpreted key here —
    # `vanilla/feat_requirements.json` now translates it into `any_of` over the
    # eight classes Fandom names on this feat's own Notes ("a character must be
    # taking level three or higher in a class with a spellbook or in shifter").
    # The shard's page still replaces the whole block with a Lore check, so the
    # two sides remain two different requirements — neither one is the raw
    # `caster_level` key any more, and the assertion below is what the vanilla
    # side actually reads once translated.
    test "Brew Potion asks for Lore 4 instead of a caster level", %{siala: s, vanilla: v} do
      assert v.feats[:brew_potion].prereqs == %{
               "any_of" => [
                 %{"class_levels" => %{"bard" => 3}},
                 %{"class_levels" => %{"cleric" => 3}},
                 %{"class_levels" => %{"druid" => 3}},
                 %{"class_levels" => %{"paladin" => 3}},
                 %{"class_levels" => %{"ranger" => 3}},
                 %{"class_levels" => %{"shifter" => 3}},
                 %{"class_levels" => %{"sorcerer" => 3}},
                 %{"class_levels" => %{"wizard" => 3}}
               ]
             }

      assert s.feats[:brew_potion].prereqs == %{"skills" => %{"lore" => 4}}
    end

    # ⚠️ Здесь стояло «`caster_level` is the one key the core refuses outright
    # … this is the difference between a feat that can never be cleared and one
    # that can» — устарело задачей 3.120 (27.08.2026). `caster_level` больше не
    # безусловный отказ у ЭТОГО фита: `vanilla/feat_requirements.json` переводит
    # его в `any_of`, так что vanilla's side is checkable too now, just against
    # real class levels instead of Lore. The contrast this test exists for is
    # unchanged — the shard's rule clears a non-caster that vanilla's own
    # translation still refuses — it is only the vanilla *reason* that changed
    # shape, from an unconditional `missing_data` to a real, failed `any_of`.
    test "and the shard's rule clears a build vanilla's own translation still refuses",
         %{siala: s, vanilla: v} do
      # ⚠️ Класс здесь больше не произволен (было `:rogue`). Требования фита —
      # не единственное, что решает: класс уровня держит собственный список
      # запрещённых, и `brew_potion` вор на своём уровне не выбирает вовсе
      # (`unavailable_feats`, задача 1.10 шаг 2) — то есть на воре видно было бы
      # два отказа, и исчезновение одного пряталось бы за вторым.
      #
      # `shifter` выбран не «чтобы прошло»: он единственный НЕ-заклинатель, чей
      # список фит не запрещает, — то есть ровно тот случай, ради которого шард
      # правило и переписал («варить зелья теперь может не-кастер», CLAUDE.md §3).
      # ⚠️ И ровно поэтому он теперь ещё и минимальный контр-пример на vanilla:
      # `shifter` — одна из восьми веток `any_of` (задача 3.120 включила его по
      # цитате «or in shifter»), но у этого билда ОДИН его уровень, а нужно ТРИ,
      # так что отказ по vanilla не исчез — просто сменил форму.
      build = Build.new(levels: [:shifter], skills: %{1 => %{lore: 4}})

      assert Rules.validate_feat(build, :brew_potion, v) ==
               {:error,
                [
                  requires_any_of: [
                    [{:requires_class_level, :bard, 3}],
                    [{:requires_class_level, :cleric, 3}],
                    [{:requires_class_level, :druid, 3}],
                    [{:requires_class_level, :paladin, 3}],
                    [{:requires_class_level, :ranger, 3}],
                    [{:requires_class_level, :shifter, 3}],
                    [{:requires_class_level, :sorcerer, 3}],
                    [{:requires_class_level, :wizard, 3}]
                  ]
                ]}

      assert Rules.validate_feat(build, :brew_potion, s) == :ok
    end

    # source: siala «Epic Dodge» revid 17399 — «Ловкость 25+, Защитный бросок,
    # Уклонение». The 21st level, Tumble 30 and Improved Evasion are gone, and
    # merging the block instead of replacing it would silently keep all three.
    test "Epic Dodge loses three requirements and gains Evasion", %{siala: s, vanilla: v} do
      assert v.feats[:epic_dodge].prereqs == %{
               "character_level" => 21,
               "abilities" => %{"dex" => 25},
               "feats" => ["improved_evasion", "defensive_roll"],
               "skills" => %{"tumble" => 30}
             }

      assert s.feats[:epic_dodge].prereqs == %{
               "abilities" => %{"dex" => 25},
               "feats" => ["defensive_roll", "evasion"]
             }
    end

    # source: siala class pages — the shard moved these onto class levels the
    # vanilla data does not know about.
    test "class-ability feats move to the shard's levels", %{siala: s} do
      assert s.feats[:hide_in_plain_sight].prereqs == %{"class_levels" => %{"shadowdancer" => 4}}
      assert s.feats[:divine_grace].prereqs == %{"class_levels" => %{"paladin" => 4}}
      assert s.feats[:monk_ac_bonus].prereqs == %{"class_levels" => %{"monk" => 4}}
      assert s.feats[:wholeness_of_body].prereqs == %{"class_levels" => %{"monk" => 2}}
      assert s.feats[:craft_harper_item].prereqs == %{"class_levels" => %{"harper_scout" => 1}}
    end

    # source: siala «Keen Sense» — «Тёмный эльф (Elf) или Убийца (Assassin) 20
    # уровня». The shard *widened* the requirement, so keeping vanilla's
    # `race: [elf]` would refuse an assassin who qualifies. The "или" is printed
    # on the page, so the disjunction is read as one rather than guessed at.
    test "a widened requirement becomes a disjunction, not a narrower rule", %{
      siala: s,
      vanilla: v
    } do
      assert v.feats[:keen_sense].prereqs == %{"race" => ["elf"]}

      assert s.feats[:keen_sense].prereqs == %{
               "any_of" => [
                 %{"race" => ["elf"]},
                 %{"class_levels" => %{"assassin" => 20}}
               ]
             }

      assert s.feats[:keen_sense].prereqs["unparsed"] == nil
    end

    # ⚠ The parser states the atoms and deliberately does not say whether they
    # are joined by "и" or "или" — the page writes a comma. Two **different**
    # classes can only be "или" («Паладин 1 уровня, Чемпион Торма 1 уровня»):
    # the ability is handed over by either, and folding them into a conjunction
    # would demand a build nobody has. That inference is about the game and not
    # about the punctuation, which is why it lives in the loader and the parser
    # does not carry a second copy of it.
    test "two class levels in one block are alternatives, not a conjunction", %{siala: s} do
      prereqs = s.feats[:lay_on_hands].prereqs

      assert prereqs["class_levels"] == nil
      assert prereqs["unparsed"] == nil

      assert prereqs["any_of"] == [
               %{"class_levels" => %{"paladin" => 1}},
               %{"class_levels" => %{"champion_of_torm" => 1}}
             ]
    end

    # 🔴 ЗДЕСЬ СТОЯЛО «a fragment with no number does not acquire one» с проверкой
    # «Артистизм (Perform)» in prereqs["unparsed"] — задача 3.103 (25.08.2026)
    # фрагмент ПРОЧИТАЛА, и главная половина утверждения не тронута: ранга
    # у требования по-прежнему нет, потому что его не называет ни одна вики.
    # Переведён не РАНГ, а ДОСТУП: Исполнение — исключительный навык барда,
    # и это говорит сама Сиала («Навык нужный Бардам и только им, как
    # и в оригинальном NWN», `siala_41/skills.json` → perform → vanilla_baseline,
    # verified), Fandom со стороны навыка («Classes: bard», «Cross-class: no»)
    # и Fandom со стороны фита («only characters starting as bards may take
    # this feat»).
    #
    # ⚠ Тест держит обе половины сразу, иначе следующий читатель починит
    # не то: ранг НЕ придуман (`skills` пуст), а доступ прочитан
    # (`class_levels`), и сырого остатка не осталось.
    test "«Артистизм (Perform)» переведён в уровень барда, а ранг не выдуман", %{siala: s} do
      prereqs = s.feats[:artist].prereqs

      assert prereqs["skills"] == nil
      assert prereqs["unparsed"] == nil
      assert prereqs["class_levels"] == %{"bard" => 1}
      assert prereqs["max_character_level"] == 1
    end

    # 🔴 БЕЗ ЭТОЙ ЗАПИСИ ВАНИЛЬНАЯ ПРАВКА ДО ШАРДА НЕ ДОЕЗЖАЛА, и это не деталь
    # реализации, а форма всего слоя: блок «Требования» шардовой страницы
    # ЗАМЕЩАЕТ `prereqs` целиком (тот же механизм, что у `Epic dodge` двумя
    # тестами выше). До задачи 3.103 `vanilla/feat_requirements.json` уже мог
    # бы нести перевод — и `siala_41` всё равно отказывал бы барду, потому что
    # поверх ложился машинный шардовый блок с непрочитанным фрагментом.
    #
    # Отрицательный контроль здесь — САМ ФАКТ РАЗНЫХ ИСТОЧНИКОВ: на `vanilla`
    # работает ванильная запись, на `siala_41` — шардовая, и обе обязаны давать
    # один ответ. Разъедутся — тест красный.
    test "перевод есть на ОБОИХ ruleset'ах, и приходит он из разных файлов", %{
      siala: s,
      vanilla: v
    } do
      bard = Build.new(levels: [:bard], alignment: :neutral, race: :human)
      wizard = Build.new(levels: [:wizard], alignment: :neutral, race: :human)

      # ✅ Задача 3.109 (26.08.2026): это ровно тот билд, который Dan замерил
      # на экране СОЗДАНИЯ персонажа — бард 1, в Исполнение не вложено ни одного
      # очка, «artist доступен» (`GAME_CHECKS.md` AC8). Запись 3.103 назвала
      # риск («если сверх доступа есть порог в один ранг, мы мягче ровно здесь»)
      # — риск НЕ сбылся, порога нет. ⚠️ Ни одно число от замера не сдвинулось:
      # `class_levels: {bard: 1}` как стояло, так и стоит; изменилась ОПОРА.
      # ⚠️ Нуль рангов назван ЯВНО, а не подразумевается пустым билдом: «рангов
      # нет» — половина измеренного условия, и молчаливой она быть не должна.
      assert Build.skill_ranks(bard, :perform, 1) == 0

      for ruleset <- [v, s] do
        assert Rules.validate_feat(bard, :artist, ruleset) == :ok

        assert Rules.validate_feat(wizard, :artist, ruleset) ==
                 {:error, [{:requires_class_level, :bard, 1}]}
      end

      # Ванильный блок — из `vanilla/feat_requirements.json`, шардовый — из
      # `siala_41/feats.json`, и сырые строки у них РАЗНЫЕ. Это и есть доказательство,
      # что до шарда доехала шардовая запись, а не ванильная.
      assert v.feats[:artist].prereq_raw =~ "[[perform]] skill"
      assert s.feats[:artist].prereq_raw =~ "Артистизм (Perform)"
    end

    # Сторож на месте ванильного `replaces`: у шардового слоя своего механизма
    # сверки нет, поэтому форму МАШИННОГО блока пинит тест. День, когда
    # `mix wiki.parse` научится читать «Артистизм (Perform)» сам, будет красным —
    # и тогда ручную запись надо будет переписать или снять, а не оставить
    # молча перекрывать разобранное.
    test "машинный блок `artist` всё ещё несёт непрочитанный навык" do
      entry =
        "priv/rules/siala_41/generated/feats.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.fetch!("feats")
        |> Enum.find(&(&1["id"] == "artist"))

      change = Enum.find(entry["changes"], &(&1["what"] == "requirements"))

      assert Enum.map(change["value"], & &1["kind"]) == ["skill", "max_character_level"]
      assert Enum.find(change["value"], &(&1["kind"] == "skill"))["rank"] == nil
    end
  end

  describe "a feat the shard switched off" do
    # source: siala «Разрушительный критический удар» revid 12690 — «Этот фит на
    # Сиале отключен, взять его нельзя.»
    test "Devastating critical is marked disabled but keeps its record", %{siala: s} do
      assert s.feats[:devastating_critical].disabled?
      assert s.feats[:devastating_critical].name == "Devastating critical"
      refute s.feats[:devastating_critical].siala_only?
    end

    test "vanilla is untouched", %{vanilla: v} do
      refute v.feats[:devastating_critical].disabled?
    end

    # It is on eight classes' bonus lists in the vanilla data, so the type
    # checks alone would keep offering it in an epic Weapon Master bonus slot.
    test "no slot accepts it, on Siala only", %{siala: s, vanilla: v} do
      slot = %{
        id: {:class_bonus, :weapon_master},
        kind: :class_bonus,
        class: :weapon_master,
        epic?: true
      }

      assert FeatSlots.accepts?(v, slot, :devastating_critical)
      refute FeatSlots.accepts?(s, slot, :devastating_critical)
      refute :devastating_critical in FeatSlots.candidates(s, slot)
    end

    test "asking about it directly is refused with its own reason", %{siala: s} do
      build = Build.new(levels: List.duplicate(:fighter, 25))

      assert Rules.validate_feat(build, :devastating_critical, s) ==
               {:error, [{:feat_disabled, :devastating_critical}]}
    end

    # The "→ N" badge counts what a feat opens; a feat nobody may take opens
    # nothing, so Power Attack is a gate to six on Siala and seven in vanilla.
    test "it stops counting as something other feats unlock", %{siala: s, vanilla: v} do
      assert :devastating_critical in v.feats[:power_attack].unlocks
      refute :devastating_critical in s.feats[:power_attack].unlocks
      assert length(v.feats[:power_attack].unlocks) - length(s.feats[:power_attack].unlocks) == 1
    end
  end

  # ✅ Замер: Dan, тестовый сервер, 09.08.2026 — `GAME_CHECKS.md` кейс **H5**.
  # Сиала заменила ванильную систему владения ОРУЖИЕМ пятью своими фитами, а
  # ванильные `Weapon Proficiency (*)` выключила. Броня и щиты не тронуты.
  #
  # 🔴 СЕМЬ ФИТОВ, А НЕ ВОСЕМЬ — правка 26.08.2026 (задача 3.112). Здесь стояло
  # «Восемь фитов», и `simple` стоял в `@measured`: наблюдение H5 («вор 1-го
  # уровня фит не видит») было верным, а прочтение — нет. Три игровых лога
  # `.билд` показали `Weapon Proficiency (simple)` на LEVEL 1 у ВСЕХ трёх
  # персонажей, включая волшебника и монаха, — то есть шард его не выключил,
  # а наоборот выдаёт всем даром, а выданное в списке выбора не печатается.
  # Разбор — в describe «simple шард не выключил, а выдаёт всем» ниже.
  #
  # ⚠️ Семь фитов, и они выключены с РАЗНОЙ уверенностью — тесты этого раздела
  # держат именно разницу, потому что один флажок на семь её бы стёр:
  #   * `martial`, `exotic`, `elf` — измерены, `verified`, гэпа нет;
  #   * `monk`, `druid`, `rogue`, `wizard` — вывод, `assumed`, гэп есть. Каждый
  #     выдаётся ровно одним классом, а выданное в СПИСКЕ ВЫБОРА не печатается,
  #     значит там их не проверить в принципе.
  #     ⚠️ «В принципе» относится к списку выбора, и только к нему: игровой лог
  #     `.билд` печатает выданное, и в трёх логах `monk`, `wizard` и `rogue`
  #     отсутствуют — то есть у трёх из четырёх вывод теперь подтверждён
  #     движком. Статусы 26.08.2026 сознательно не тронуты (это отдельное
  #     решение с отдельной ценой — три гэпа уйдут с экрана), и тест ниже
  #     по-прежнему требует у них гэп.
  describe "ванильные владения оружием шард выключил" do
    @measured [
      :weapon_proficiency_martial,
      :weapon_proficiency_exotic,
      :weapon_proficiency_elf
    ]
    @inferred [
      :weapon_proficiency_monk,
      :weapon_proficiency_druid,
      :weapon_proficiency_rogue,
      :weapon_proficiency_wizard
    ]

    # ⚠️ Решает наблюдение ВОРА, а не воина: воин фит `martial` получает даром, а
    # выданное в списке выбора и так не печатается, то есть его наблюдение не
    # отличает «выключен» от «выдан». Вор фит не запрещён, даром не получает, и
    # требований у `martial`/`simple` нет вовсе — модель обязана была их показать.
    test "вор 1-го уровня не видит ни одного из семи", %{siala: s} do
      rogue = Build.new(race: :human, levels: [:rogue])

      for id <- @measured ++ @inferred do
        assert Rules.validate_feat(rogue, id, s) == {:error, [{:feat_disabled, id}]},
               "#{id}: обязан отказывать именно как выключенный, а не по другой причине"
      end
    end

    # ⚠️ ПОЛОЖИТЕЛЬНЫЕ КОНТРОЛИ, без которых тест выше доказывает только
    # «мы что-то спрятали». Все три строки — из того же захода H5, все три
    # измерены на том же экране вора 1-го уровня.
    test "но броню, щит и сиальское владение — видит", %{siala: s} do
      rogue = Build.new(race: :human, levels: [:rogue])

      for id <- [
            :armor_proficiency_light,
            :armor_proficiency_medium,
            :shield_proficiency,
            :siala_blade_proficiency
          ] do
        assert Rules.validate_feat(rogue, id, s) == :ok, to_string(id)
      end

      # И контрольная строка самого замера: сиальское владение никто не выдаёт
      # даром — «0 выдач в данных» сошлось с игрой.
      granting =
        for {cid, class} <- s.classes,
            {_level, ids} <- class.granted_feats,
            :siala_blade_proficiency in ids,
            do: cid

      assert granting == []
    end

    test "ваниль не тронута", %{vanilla: v} do
      for id <- @measured ++ @inferred do
        refute v.feats[id].disabled?, to_string(id)
      end

      # И берётся там же, где на Сиале отказывает.
      assert Rules.validate_feat(
               Build.new(race: :human, levels: [:rogue]),
               :weapon_proficiency_martial,
               v
             ) ==
               :ok
    end

    # Выдачу гасит ЯДРО, а не правка ванильных файлов: там 26 пар класс×фит
    # верны, файлами владеет `mix wiki.parse`. Значит проверять надо обе
    # стороны — что на Сиале выдачи нет и что в ванили она на месте.
    test "выдача выключенного фита не печатается — 12 пар против нуля", %{siala: s, vanilla: v} do
      pairs = fn ruleset ->
        for {cid, class} <- ruleset.classes,
            {level, ids} <- class.granted_feats,
            id <- ids,
            id in (@measured ++ @inferred),
            do: {cid, level, id}
      end

      assert pairs.(v) |> length() == 12
      assert pairs.(s) == []

      # Именно то, что видит игрок: у воина в «Класс даёт сам» больше нет
      # владений оружием, а броня и щит на месте.
      fighter = Build.new(race: :human, levels: [:fighter])
      granted = Build.granted_feats_at(fighter, s, 1)

      assert :armor_proficiency_medium in granted
      assert :shield_proficiency in granted
      refute :weapon_proficiency_martial in granted

      # ⚠️ `simple` здесь ЕСТЬ, и это не исключение из правила, а другой факт:
      # шард его не выключал (задача 3.112, describe ниже).
      assert :weapon_proficiency_simple in granted

      # И у четвёрки-вывода — то же, каждый у своего единственного класса.
      for {class, id} <- [
            {:monk, :weapon_proficiency_monk},
            {:druid, :weapon_proficiency_druid},
            {:rogue, :weapon_proficiency_rogue},
            {:wizard, :weapon_proficiency_wizard}
          ] do
        build = Build.new(race: :human, levels: [class])
        refute id in Build.granted_feats_at(build, s, 1), to_string(id)
        assert id in Build.granted_feats_at(build, v, 1), "в ванили выдача обязана остаться"
      end
    end

    # Расовая склонность — второй путь выдачи, и он гасится тем же местом.
    # ⚠️ На числа сегодня не влияет: ни одна запись разметки прибавок не
    # ключуется этим фитом. Гасится ради того, чтобы «эльф владеет выключенным
    # фитом» не осталось латентной неправдой.
    test "и расовая склонность эльфа тоже", %{siala: s, vanilla: v} do
      assert :weapon_proficiency_elf in v.races[:elf].bonus_feats
      refute :weapon_proficiency_elf in s.races[:elf].bonus_feats

      # Положительный контроль: остальные шесть склонностей эльфа на месте.
      assert length(s.races[:elf].bonus_feats) == length(v.races[:elf].bonus_feats) - 1
      assert :keen_sense in s.races[:elf].bonus_feats
    end

    # Бонусный список — третий путь, которым выключенный фит мог бы просочиться:
    # `exotic` стоит в `bonus_for` воина и Чемпиона Торма, и без проверки
    # `disabled?` бонусный слот предлагал бы его дальше.
    test "бонусный слот воина больше не предлагает exotic", %{siala: s, vanilla: v} do
      slot = %{
        id: {:class_bonus, :fighter},
        kind: :class_bonus,
        class: :fighter,
        taken_with: :fighter,
        epic?: false
      }

      assert MapSet.member?(s.feats[:weapon_proficiency_exotic].bonus_for, :fighter),
             "запись в бонусном списке обязана остаться — гасит её проверка disabled?, а не удаление"

      assert FeatSlots.accepts?(v, slot, :weapon_proficiency_exotic)
      refute FeatSlots.accepts?(s, slot, :weapon_proficiency_exotic)
      refute :weapon_proficiency_exotic in FeatSlots.candidates(s, slot)
    end

    # ⚠️ Главное различие раздела: у измеренных гэпа НЕТ, у выведенных ЕСТЬ.
    # Печатать «предполагаем» про измеренное — та же ложная неопределённость
    # наоборот, которую запрещает §6 CLAUDE.md.
    test "гэп стоит только у четырёх выведенных", %{siala: s, vanilla: v} do
      for id <- @inferred do
        assert {:assumed, {:feat_disabled, id}} in s.gaps, to_string(id)
      end

      for id <- @measured do
        refute {:assumed, {:feat_disabled, id}} in s.gaps,
               "#{id}: измерено — оговорка о выводе была бы ложной неопределённостью"
      end

      # Ваниль про это молчит вовсе: там ничего не выключено.
      refute Enum.any?(v.gaps, &match?({:assumed, {:feat_disabled, _}}, &1))
    end

    # Ни один фит не требует выключенного, поэтому ни одна ветка графа
    # пререквизитов не умерла — проверено по всему словарю, а не на глаз.
    # Если такой фит когда-нибудь появится, тест назовёт его по имени, и решать
    # будет человек, а не умолчание.
    test "от выключенных владений не зависит ни один пререквизит", %{siala: s} do
      disabled = MapSet.new(@measured ++ @inferred)

      depending =
        for {id, feat} <- s.feats,
            required <- (feat.prereqs || %{})["feats"] || [],
            MapSet.member?(disabled, String.to_atom(to_string(required))),
            do: {id, required}

      assert depending == []

      # И то же с другой стороны: сами они ничего не открывают, значит счётчик
      # «→ N» ни у кого не завышен.
      for id <- @measured ++ @inferred do
        assert s.feats[id].unlocks == [], to_string(id)
      end
    end
  end

  # 🔴 `Weapon proficiency (simple)` — восьмой член семьи, и он ЕДИНСТВЕННЫЙ,
  # кто шардом не выключен. Задача 3.112 (26.08.2026), запрос Dan: «данный фит
  # на Сиале есть и он выдается абсолютно всем классам на 1 уровне».
  #
  # Опровергнут был не замер, а его ПРОЧТЕНИЕ. H5 наблюдал «вор 1-го уровня фит
  # не видит», и у этого два объяснения: фит выключен ИЛИ фит уже выдан (а
  # выданное в списке выбора не печатается вовсе). Мы выбрали первое, потому что
  # по ванили вор `simple` даром не получает. На Сиале получает — как и все.
  #
  # ✅ Чем опровергнуто: тремя логами команды `.билд`, то есть печатью самого
  # движка. `test/fixtures/game_logs/` — brunna (WIZARD), moxie (MONK),
  # hnyupius (FIGHTER), у всех троих фит стоит на LEVEL 1. Волшебник и монах —
  # ровно те классы, которых ванильная страница называет исключением.
  describe "simple шард не выключил, а выдаёт всем" do
    test "фит жив: не выключен и берётся, если бы был не выдан", %{siala: s} do
      refute s.feats[:weapon_proficiency_simple].disabled?

      refute {:assumed, {:feat_disabled, :weapon_proficiency_simple}} in s.gaps

      refute Enum.any?(
               s.feats[:weapon_proficiency_simple].siala_changes,
               &match?(%{"what" => "disabled"}, &1)
             )
    end

    # 🔴 Главный инвариант правки, и он про ВСЕ классы, а не про три из лога:
    # факт называет 23 имени руками, а `Loader.ClassFeatFacts.update_class/3`
    # молча пропускает неизвестный класс. Промах означал бы, что персонаж,
    # начавший с этого класса, тихо остался без фита, — поэтому 24-й класс
    # обязан уронить тест, а не найтись живым билдом.
    test "выдают ВСЕ 23 класса, на классовом уровне 1", %{siala: s} do
      missing =
        for {id, class} <- s.classes,
            :weapon_proficiency_simple not in Map.get(class.granted_feats, 1, []),
            do: id

      assert missing == []
      assert map_size(s.classes) == 23

      # И ровно на первом классовом уровне: ни один класс не выдаёт его дважды.
      elsewhere =
        for {id, class} <- s.classes,
            {level, ids} <- class.granted_feats,
            level != 1,
            :weapon_proficiency_simple in ids,
            do: {id, level}

      assert elsewhere == []
    end

    # Ваниль не тронута ни в чём: там же 14 классов, и те же четыре исключения.
    test "ваниль осталась при своих 14 — druid/monk/rogue/wizard без фита", %{vanilla: v} do
      granters =
        for {id, class} <- v.classes,
            :weapon_proficiency_simple in Map.get(class.granted_feats, 1, []),
            do: id

      assert length(granters) == 14

      for id <- [:druid, :monk, :rogue, :wizard], do: refute(id in granters, to_string(id))
      refute v.feats[:weapon_proficiency_simple].disabled?
    end

    # 🔴 Игрок обязан увидеть фит РОВНО ОДИН РАЗ. Отдельного механизма «выдать
    # персонажу однажды» для этого нет и не заводили: сырой список выдач класса
    # несёт дубли, а показ их вычитает (`Builder.Feats.granted/3`, баг 1.14).
    # Отрицательный контроль здесь обязателен — без него четыре выдачи выглядят
    # ровно как одна.
    test "мультикласс видит фит один раз, а сырой список несёт его четырежды", %{siala: s} do
      # Ладдер `moxie.log`: monk 1 / cleric 2 / rogue 4 / ranger 5.
      build = Build.new(race: :elf, levels: [:monk, :cleric, :cleric, :rogue, :ranger])

      raw =
        for level <- 1..5,
            :weapon_proficiency_simple in Build.granted_feats_at(build, s, level),
            do: level

      shown =
        for level <- 1..5,
            :weapon_proficiency_simple in Feats.granted(s, build, level),
            do: level

      assert raw == [1, 2, 4, 5]
      assert shown == [1]

      # Положительный контроль на том же билде: дубли гасятся не «всему подряд»,
      # а по владению — своё рейнджер приносит и на 5-м.
      assert :trackless_step in Feats.granted(s, build, 5)
      assert :armor_proficiency_light in Build.granted_feats_at(build, s, 5)
      refute :armor_proficiency_light in Feats.granted(s, build, 5)
    end

    # Взять слотом нельзя — но отказ теперь ОБЫЧНЫЙ «уже есть», а не «шард
    # выключил». Разница видна игроку: вторая фраза была бы неправдой.
    test "слотом не взять, и причина названа как «уже есть»", %{siala: s} do
      build = Build.new(race: :human, levels: [:fighter, :wizard, :wizard])

      for level <- 1..3 do
        assert Rules.validate_feat_pick(
                 build,
                 %{feat: :weapon_proficiency_simple, choice: nil, at: level},
                 s
               ) == {:error, [already_taken: :weapon_proficiency_simple]}
      end

      # Требований у фита нет, значит сам по себе он законен — отказ приходит
      # от владения, а не от пререквизитов.
      assert Rules.validate_feat(build, :weapon_proficiency_simple, s) == :ok
    end

    # ⚠️ Ванильный запрет БРАТЬ фит слотом (`unavailable_feats` у druid,
    # pale_master, shifter) правкой НЕ снят и сниматься не должен: Dan сказал
    # «выдаётся всем», а не «druid может купить его слотом», и выдумывать второе
    # из первого запрещено. Запрет и выдача не спорят — это ровно та же форма,
    # что у монаха с `knockdown` («получает даром и потому не выбирает»),
    # только половины пришли с разных вики.
    test "ванильный запрет по классу остаётся, и он не спорит с выдачей", %{siala: s} do
      for id <- [:druid, :pale_master, :shifter] do
        assert MapSet.member?(s.classes[id].unavailable_feats, :weapon_proficiency_simple),
               to_string(id)

        assert :weapon_proficiency_simple in Map.get(s.classes[id].granted_feats, 1, []),
               to_string(id)
      end

      druid = Build.new(race: :human, levels: List.duplicate(:druid, 3))

      assert MapSet.member?(
               Build.feats_owned(druid, s, 3),
               :weapon_proficiency_simple
             )

      assert {:error, reasons} =
               Rules.validate_feat_pick(
                 druid,
                 %{feat: :weapon_proficiency_simple, choice: nil, at: 3},
                 s
               )

      assert {:forbidden_by_class, :druid} in reasons
      assert {:already_taken, :weapon_proficiency_simple} in reasons
    end

    # ⚠️ Состав ОРУЖИЯ этой правкой не тронут. Dan называет дубину и «возможно
    # ещё посох», но club/magic_staff/unarmed_strike стоят `:none_needed` с
    # 16.08.2026 по его же наблюдению, и «simple открывает дубину» — вывод.
    # Переписывать наблюдение под вывод запрещено (CLAUDE.md §3).
    test "право на оружие из фита не выводится — числа не сдвинулись", %{siala: s} do
      for id <- [:club, :magic_staff, :unarmed_strike] do
        assert GearWeapon.proficiency(s, id) == :none_needed, to_string(id)
      end

      # Боевой посох по-прежнему просит сиальское древковое владение: сомнение
      # в словах Dan («возможно ещё посохом») не имеет права стать правилом.
      assert GearWeapon.proficiency(s, :quarterstaff) == {:feat, :siala_polearm_proficiency}

      # И ни одна из семи разметок прибавок этим фитом не ключуется — вот
      # ПОЧЕМУ выдача не двигает ни одного числа. Проверять это сравнением
      # `compute` с самим собой было бы тавтологией: правку надо ловить там,
      # где она могла бы появиться, — в источниках прибавок.
      keyed =
        for key <- [
              :hp_bonuses,
              :ac_bonuses,
              :skill_bonuses,
              :save_bonuses,
              :ability_bonuses,
              :attack_bonuses,
              :spell_resistance
            ],
            {_verdict, records} <- Map.fetch!(s, key),
            record <- records,
            record.source == {:feat, :weapon_proficiency_simple},
            do: {key, record.id}

      assert keyed == []

      # Положительный контроль на том же обходе: `toughness` — выдача той же
      # формы (`auto_feat_at_level_1` у девяти классов), и он в разметке ЕСТЬ.
      # Без него «пусто» одинаково выглядело бы при сломанном обходе.
      assert Enum.any?(
               s.hp_bonuses.applied,
               &(&1.source == {:feat, :toughness})
             )
    end
  end

  describe "feats the shard added" do
    test "eleven of them, and none in vanilla", %{siala: s, vanilla: v} do
      only = for {id, feat} <- s.feats, feat.siala_only?, do: id

      assert length(only) == 11
      assert Enum.all?(only, &(not Map.has_key?(v.feats, &1)))
    end

    # The five custom weapon proficiencies have no English name anywhere — the
    # wiki title is the shard's own name, not a fan translation of an engine
    # one, exactly as with the races (CLAUDE.md §4).
    test "the nameless ones are shown under the shard's name", %{siala: s} do
      assert s.feats[:siala_blade_proficiency].name == "Владение клинковым оружием"
      assert s.feats[:siala_ranged_proficiency].name == "Владение оружием дальнего боя"
    end

    # source: «Возможность взятия фита» — "любому персонажу на любом уровне, на
    # котором даётся фит" is what a general feat is, and the list under it names
    # the bonus slots.
    test "the weapon proficiencies reach the general slot and three bonus slots", %{siala: s} do
      feat = s.feats[:siala_blade_proficiency]

      assert feat.type == "general"
      assert MapSet.member?(feat.bonus_for, :fighter)
      assert MapSet.member?(feat.bonus_for, :weapon_master)
      assert MapSet.member?(feat.bonus_for, :champion_of_torm)

      slot = %{id: :general, kind: :general, class: nil, epic?: false}
      assert FeatSlots.accepts?(s, slot, :siala_blade_proficiency)
    end

    # AGENT_QUEUE.md §1.8: Dan observed on the test server (03.08.2026) that the
    # five feats sit on the Ranger's own bonus slot — the one it opens "when it
    # picks a favoured enemy" (`bonus_feat_levels [1, 5, 10, 15, 20]`) — not on a
    # slot kind the core lacks. `overrides.json` → `feats.bonus_slot_aliases`
    # states the equivalence; without it (see the manual-layer test below) the
    # Ranger drops out exactly as it used to.
    test "the ranger's favoured-enemy slot reads as its ordinary bonus slot", %{siala: s} do
      for id <- [
            :siala_blade_proficiency,
            :siala_axe_proficiency,
            :siala_hammer_proficiency,
            :siala_polearm_proficiency,
            :siala_ranged_proficiency
          ] do
        feat = s.feats[id]

        assert MapSet.member?(feat.bonus_for, :ranger), "#{id}: рейнджер не в bonus_for"
        # the three classes the fix must not disturb
        assert MapSet.member?(feat.bonus_for, :fighter)
        assert MapSet.member?(feat.bonus_for, :champion_of_torm)
        assert MapSet.member?(feat.bonus_for, :weapon_master)

        # once the alias resolves the slot name, the fact is fully modelled —
        # "feat_slots" must not linger as a gap on a build that took the feat
        refute "feat_slots" in Enum.map(feat.siala_unapplied, & &1["what"])
      end
    end

    # Positive control: a class the pages never mention must stay refused, or a
    # bug that handed the feat to *every* class would pass the test above too.
    test "a class the pages never name is still refused", %{siala: s} do
      for id <- [
            :siala_blade_proficiency,
            :siala_axe_proficiency,
            :siala_hammer_proficiency,
            :siala_polearm_proficiency,
            :siala_ranged_proficiency
          ] do
        refute MapSet.member?(s.feats[id].bonus_for, :wizard), "#{id}: визард не должен получить"
      end
    end

    # End-to-end through `FeatSlots`, not just `bonus_for`: at a real Ranger's
    # bonus level, the slot the core opens takes all five weapon-proficiency
    # feats — and `Favored enemy` is still among the candidates, because Dan
    # confirmed (04.08.2026) they compete for the same one slot rather than
    # each getting their own.
    test "a ranger's bonus slot offers the five feats alongside Favored enemy", %{siala: s} do
      build = Build.new(race: :human, levels: List.duplicate(:ranger, 5))

      assert [%{kind: :class_bonus, class: :ranger} = slot] = FeatSlots.at(build, s, 5)

      candidates = FeatSlots.candidates(s, slot)

      assert :favored_enemy in candidates

      for id <- [
            :siala_blade_proficiency,
            :siala_axe_proficiency,
            :siala_hammer_proficiency,
            :siala_polearm_proficiency,
            :siala_ranged_proficiency
          ] do
        assert id in candidates, "#{id} не предложен в бонусном слоте рейнджера"
        assert FeatSlots.accepts?(s, slot, id)
      end
    end

    # source: siala «Shades (feat)» revid 18248. HANDOFF listed this as an open
    # hole: the assassin's level-15 ability is a shard feat with no vanilla
    # record, so nothing could be shifted onto it.
    test "the assassin's Shades exists now, with its requirement", %{siala: s} do
      assert s.feats[:shades_feat].prereqs == %{"class_levels" => %{"assassin" => 15}}
    end
  end

  describe "the layer does not double what the class layer already applied" do
    # source: siala «Evasion» / «Improved Evasion» restate the level shifts the
    # class pages state. Both land on the same map; the move is idempotent.
    test "the moved evasion levels are exactly the shard's", %{siala: s} do
      assert :evasion in s.classes[:rogue].granted_feats[30]
      assert :evasion in s.classes[:monk].granted_feats[25]
      assert :evasion in s.classes[:shadowdancer].granted_feats[15]
      assert :improved_evasion in s.classes[:monk].granted_feats[30]
      assert :improved_evasion in s.classes[:shadowdancer].granted_feats[25]
    end

    test "and the vanilla levels they came from grant nothing any more", %{siala: s} do
      refute :evasion in Map.get(s.classes[:rogue].granted_feats, 2, [])
      refute :evasion in Map.get(s.classes[:monk].granted_feats, 1, [])
      refute :improved_evasion in Map.get(s.classes[:monk].granted_feats, 9, [])
    end

    # source: siala «Улучшенное уклонение» revid 14699 — «Улучшенное уклонение
    # может взять [[Вор|вор]], начиная с 35-го уровня (а не с 10-го)», restated
    # by the class page «Вор» revid 20408 — «улучшенное уклонение можно взять,
    # начиная с 35-го уровня вора».
    #
    # 🔴 **Both halves in one test on purpose.** Split apart, each half passes
    # against the *wrong* model too: "Rogue 35 may take it" is true of a model
    # that hands it over for free, and "Rogue 34 may not" is true of one that
    # hands it over at 35. Only together do they say what the page says — the
    # feat costs a slot, and the slot may not be spent before class level 35.
    # The model failed both ways at once until 14.08.2026: the sentence was
    # recorded in `siala_41/classes.json` as a `feat_level_shift`, which can
    # only move a hand-out, so a Rogue 35 was given it free while the untouched
    # vanilla `rogue: 10` branch let a Rogue 10 buy it.
    test "Improved evasion is BOUGHT by a Rogue from class level 35, not handed over", %{
      siala: s
    } do
      before = Build.new(race: :human, levels: List.duplicate(:rogue, 34))
      at = Build.new(race: :human, levels: List.duplicate(:rogue, 35))

      assert {:error, reasons} = Rules.validate_feat(before, :improved_evasion, s)

      assert [{:requires_any_of, branches}] = reasons
      assert [{:requires_class_level, :rogue, 35}] in branches

      assert Rules.validate_feat(at, :improved_evasion, s) == :ok

      # ...and nobody was given it: `35 => [:improved_evasion]` in the Rogue's
      # `granted_feats` is exactly the bug this test exists to keep out.
      refute :improved_evasion in Map.get(s.classes[:rogue].granted_feats, 35, [])
      assert Build.granted_feats_at(at, s, 35) == []
      refute MapSet.member?(Build.feats_owned(at, s, 35), :improved_evasion)

      # The first slot that can actually spend it is the epic class bonus at 36
      # — the shard left the Rogue's bonus levels alone (10/13/16/19, 24/28/32/
      # 36/40), so the gap between 35 and 36 is the page's, not ours.
      spender =
        Build.new(
          race: :human,
          levels: List.duplicate(:rogue, 36),
          feats: %{36 => %{{:class_bonus, :rogue} => :improved_evasion}}
        )

      assert Rules.validate_feat_pick(
               spender,
               %{feat: :improved_evasion, at: 36, slot: {:class_bonus, :rogue}},
               s
             ) == :ok
    end

    # The control for the test above: the two sentences that really are hand-outs
    # keep behaving like hand-outs. A "fix" that turned all three into
    # requirements would pass every assertion up there and break these.
    test "while the Monk's and Shadowdancer's stay hand-outs", %{siala: s} do
      monk = Build.new(race: :human, levels: List.duplicate(:monk, 30))

      dancer =
        Build.new(
          race: :human,
          levels: List.duplicate(:fighter, 6) ++ List.duplicate(:shadowdancer, 25)
        )

      assert :improved_evasion in Build.granted_feats_at(monk, s, 30)
      assert MapSet.member?(Build.feats_owned(monk, s, 30), :improved_evasion)
      assert :improved_evasion in Build.granted_feats_at(dancer, s, 31)
    end

    # The shard moved one branch of one feat's requirement; vanilla keeps every
    # number Fandom states. Without this the manual layer could quietly leak
    # into the ruleset a build was assembled under (CLAUDE.md §5).
    test "and vanilla still lets a Rogue 10 take it", %{vanilla: v} do
      build = Build.new(race: :human, levels: List.duplicate(:rogue, 10))

      assert Rules.validate_feat(build, :improved_evasion, v) == :ok

      assert v.feats[:improved_evasion].prereqs == %{
               "any_of" => [
                 %{"class_levels" => %{"monk" => 9}},
                 %{"class_levels" => %{"rogue" => 10}},
                 %{"class_levels" => %{"shadowdancer" => 10}}
               ]
             }
    end

    # ⚠ The other two branches are **left where vanilla put them**, and that is a
    # decision, not an oversight: the page moved the Rogue's number and said
    # nothing about the other two, so they stayed vanilla — and on the shard that
    # stopped being harmless. In vanilla those branches were inert (a Monk 9
    # already owned the feat, and what you own you cannot buy); the shard moved
    # the hand-out to Monk 30, and the branch started clearing a purchase for
    # somebody who owns nothing.
    #
    # ✅ `GAME_CHECKS.md` H9 asked the game, and the game answered on 16.08.2026:
    # a Monk 9 / Rogue 10 does **not** see the feat. Both branches now sit at the
    # levels the same trip measured the hand-outs at.
    # 🔴 **ЗАМЕР Dan 16.08.2026 (кейс H9) — дырку закрыл, и ответ оказался обратным
    # тому, что модель разрешала.** Здесь стояло `assert … == :ok` с комментарием
    # выше про «цену, измеренную здесь, чтобы никто не открыл её сюрпризом»:
    # монах 9 / вор 10 брал слотом фит, которого в игре у него нет. Дословно:
    # «монах 9, вор 10 -> improved evasion не доступен».
    #
    # ⚠️ Ветки монаха и ШД двинуты на уровни ВЫДАЧИ (30 и 25) — те, что Dan
    # измерил тем же заходом. ⚠️ Что ветка стоит именно там, а не отсутствует
    # вовсе, проверить нельзя ничем: на 30-м монах фитом уже владеет, а владеемое
    # не покупают. Две модели наблюдательно неразличимы, выбрана та, что сохраняет
    # форму источника (в ванили ветка стояла ровно на уровне выдачи).
    test "a Monk 9 dip no longer clears the requirement — measured, not read", %{
      siala: s
    } do
      build =
        Build.new(race: :human, levels: List.duplicate(:monk, 9) ++ List.duplicate(:rogue, 10))

      refute MapSet.member?(Build.feats_owned(build, s, 19), :improved_evasion)

      assert {:error, [requires_any_of: branches]} =
               Rules.validate_feat(build, :improved_evasion, s)

      assert Enum.sort(branches) == [
               [{:requires_class_level, :monk, 30}],
               [{:requires_class_level, :rogue, 35}],
               [{:requires_class_level, :shadowdancer, 25}]
             ]
    end

    # Остальные три чтения того же захода — они и делают первое осмысленным.
    # ⚠️ Без «вор 35 берёт» первый кейс зеленел бы у модели, которая просто
    # запретила фит всем; без «монах 30 владеет» — у модели, где ветка ушла
    # в недостижимое число.
    test "the other three readings of the same trip", %{siala: s} do
      rogue_10 = Build.new(race: :human, levels: List.duplicate(:rogue, 10))
      rogue_35 = Build.new(race: :human, levels: List.duplicate(:rogue, 35))
      monk_30 = Build.new(race: :human, levels: List.duplicate(:monk, 30))

      # вор 10 — фита нет ни как покупки, ни как владения
      assert {:error, _} = Rules.validate_feat(rogue_10, :improved_evasion, s)
      refute MapSet.member?(Build.feats_owned(rogue_10, s, 10), :improved_evasion)

      # вор 35 — можно ВЗЯТЬ, но не выдаётся
      assert Rules.validate_feat(rogue_35, :improved_evasion, s) == :ok
      refute MapSet.member?(Build.feats_owned(rogue_35, s, 35), :improved_evasion)

      # монах 30 — наоборот: выдан даром, и слотом его уже не взять
      assert MapSet.member?(Build.feats_owned(monk_30, s, 30), :improved_evasion)

      assert Rules.validate_feat_pick(monk_30, :improved_evasion, s) ==
               {:error, [already_taken: :improved_evasion]}

      # ШД 25 — выдача стоит там же, где её измерил Dan
      assert :improved_evasion in s.classes[:shadowdancer].granted_feats[25]
    end

    # Toughness is stated twice as well — once by the eight class pages and once
    # by the feat page's `granted_automatically_to`.
    test "Toughness arrives once per class, not twice", %{siala: s} do
      for class <- [:fighter, :barbarian, :weapon_master, :paladin, :ranger, :druid] do
        assert Enum.count(s.classes[class].granted_feats[1], &(&1 == :toughness)) == 1,
               "#{class} получил Toughness дважды"
      end
    end
  end

  describe "what the layer could not apply is named — and only when it names something we print" do
    # 🔴 Здесь стоял ПОЛОЖИТЕЛЬНЫЙ пример этого describe — `Improved evasion`,
    # единственный факт слоя фитов, переживавший фильтр получателей. Стояло:
    # «the note is *still* a gap, because applying the first two left
    # a consequence unread» — ванильный `any_of` списан с ванильных уровней
    # ВЫДАЧИ, шард выдачу отодвинул, и две инертные ветки ожили.
    #
    # **Остаток закрыт замером H9 (Dan, 16.08.2026)**: три записи
    # `requirement_class_level` ручного слоя двинули все три ветки (вор 10→35,
    # монах 9→30, ШД 10→25), а 17.08.2026 Dan снял и сам гэп — «правила
    # железные и измеряны». На реальных данных положительного примера у слоя
    # фитов не осталось ни одного: все 21 неприменённых факта про урон,
    # длительность, иммунитеты и умения без выделимого числа.
    #
    # ⚠️ Поэтому тестов ДВА, и порознь ни один правила не доказывает: первый —
    # что факт молчит; второй — что молчит он ИЗ-ЗА ПОЛУЧАТЕЛЯ, а не потому,
    # что механизм сломался и молчит про всё. Билд у обоих один и тот же,
    # различается ровно одна строка данных.
    test "Improved evasion гэпа больше не даёт — все три предложения применены",
         %{siala: s} do
      gaps = Rules.compute(rogue_36_with_improved_evasion(), s).gaps

      refute {:not_modelled, {:feat_change, :improved_evasion, "siala_note"}} in gaps

      # Положительный контроль к самому фикстуру: факт на месте и по-прежнему
      # НЕ применён — иначе тест зеленел бы у модели, которая его просто
      # потеряла, а это совсем другое событие.
      assert Enum.any?(s.feats[:improved_evasion].siala_unapplied, &(&1["what"] == "siala_note"))
    end

    # ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ на живость механизма. Тот же билд, тот же фит, та же
    # форма факта — меняется одно поле `affects`, и гэп возвращается. Синтетика
    # здесь не от лени: на слое фитов настоящего факта с нашим получателем
    # больше нет, а проверять надо именно этот слой (у классов и навыков свои
    # тесты, и они бы прошли при сломанном слое фитов).
    test "и механизм жив: тот же факт с нашим получателем гэп даёт", %{siala: s} do
      ours =
        put_in(s, [:feats, :improved_evasion, :siala_unapplied], [
          %{"what" => "siala_note", "affects" => ["hp"]}
        ])

      assert {:not_modelled, {:feat_change, :improved_evasion, "siala_note"}} in Rules.compute(
               rogue_36_with_improved_evasion(),
               ours
             ).gaps
    end

    # source: siala «Divine Might» — the shard's rewrite is entirely about how
    # long an already-uncounted buff lasts (`affects: ["duration"]`), which is
    # not a hole in an answer this calculator gives at all (CLAUDE.md §9, task
    # 3.28's own reasoning carried over to the feat layer 14.08.2026). The
    # mirror image of the test above: naming a receiver we never print takes
    # the fact out of `gaps` even though it stayed in `siala_unapplied`.
    test "a taken feat whose unread change names nothing we print stays silent", %{siala: s} do
      build =
        Build.new(
          levels: List.duplicate(:paladin, 6),
          feats: %{1 => %{general: :divine_might}}
        )

      refute {:not_modelled, {:feat_change, :divine_might, "siala_note"}} in Rules.compute(
               build,
               s
             ).gaps

      assert Map.get(s.feats[:divine_might] || %{}, :siala_unapplied) != [],
             "the fixture only proves the filter's direction if the fact is still unapplied"
    end

    test "a build that took none of them collects none", %{siala: s} do
      build =
        Build.new(levels: List.duplicate(:fighter, 6), feats: %{1 => %{general: :toughness}})

      refute Enum.any?(
               Rules.compute(build, s).gaps,
               &match?({:not_modelled, {:feat_change, _, _}}, &1)
             )
    end

    test "the prose itself is kept, not just counted, even once filtered out of the gaps",
         %{siala: s} do
      note = Enum.find(s.feats[:divine_might].siala_changes, &(&1["what"] == "siala_note"))

      assert note["quote"] =~ "уровня"
      assert s.feats[:divine_might].siala_source["revid"]
    end
  end

  describe "the manual layer" do
    @describetag :tmp_dir

    # It does not exist yet, so the contract is checked on a fixture: a
    # hand-written record beside the generated one overrides it, fact by fact,
    # because it is applied second (README: vanilla -> generated -> manual).
    test "a hand-written record overrides the machine's", %{tmp_dir: dir} do
      generated = %{
        "feats" => [
          %{
            "id" => "ward",
            "vanilla_id" => "ward",
            "changes" => [
              %{
                "what" => "requirements",
                "value" => [%{"kind" => "bab", "value" => 4, "raw" => "БАБ +4"}],
                "status" => "verified"
              }
            ]
          }
        ]
      }

      manual = %{
        "feats" => [
          %{
            "id" => "ward",
            "vanilla_id" => "ward",
            "changes" => [
              %{
                "what" => "requirements",
                "value" => [%{"kind" => "bab", "value" => 9, "raw" => "БАБ +9, замер в игре"}],
                "status" => "verified"
              }
            ]
          }
        ]
      }

      ruleset = load(dir, generated, manual)

      assert ruleset.feats[:ward].prereqs == %{"base_attack_bonus" => 9}
    end

    # `requirement_class_level` moves **one** branch and leaves the rest of the
    # block alone — the shape the shard's own sentence has («может взять вор,
    # начиная с 35-го уровня (а не с 10-го)» names one class and nothing else).
    # `requirements` above cannot express that: it replaces the block, so the
    # other branches would have to be copied out of the vanilla file, where the
    # next `mix wiki.parse` could no longer keep them honest.
    test "a class-level requirement moves one branch of a disjunction", %{tmp_dir: dir} do
      ruleset = load(dir, %{"feats" => []}, manual_branch_move(35))

      assert ruleset.feats[:gate_keeper].prereqs == %{
               "any_of" => [
                 %{"class_levels" => %{"fighter" => 9}},
                 %{"class_levels" => %{"rogue" => 35}}
               ]
             }
    end

    # `from` is the record's claim about what vanilla says, and it is checked. A
    # mismatch means the page moved under the record — or that the record was
    # applied once already — and the number about to be overwritten is not the
    # one a human read. Silently rewriting it is exactly the failure this whole
    # family of records exists to avoid, so the load stops instead.
    test "a stale `from` fails the load instead of overwriting an unknown number", %{
      tmp_dir: dir
    } do
      manual =
        put_in(
          manual_branch_move(35),
          ["feats", Access.at(0), "changes", Access.at(0), "value", "from"],
          4
        )

      assert_raise RuntimeError,
                   ~r/requirement_class_level says rogue's requirement reads 4/,
                   fn ->
                     load(dir, %{"feats" => []}, manual)
                   end
    end

    test "and so does a class no requirement of the feat names", %{tmp_dir: dir} do
      manual =
        put_in(
          manual_branch_move(35),
          ["feats", Access.at(0), "changes", Access.at(0), "value", "class"],
          "monk"
        )

      assert_raise RuntimeError, ~r/no requirement of this feat names monk/, fn ->
        load(dir, %{"feats" => []}, manual)
      end
    end

    test "the generated layer alone still applies", %{tmp_dir: dir} do
      generated = %{
        "feats" => [
          %{
            "id" => "ward",
            "vanilla_id" => "ward",
            "changes" => [%{"what" => "disabled", "value" => true, "status" => "verified"}]
          }
        ]
      }

      assert load(dir, generated, nil).feats[:ward].disabled?
    end

    # Isolates the mechanism behind §1.8 from the 66 real pages: a feat whose
    # only fact is a `feat_slots` change naming a slot this loader has never
    # heard of ("favored_enemy") behaves exactly as `siala_blade_proficiency`
    # used to — refused, and reported — until `overrides.json` states the
    # equivalence. Nothing else in this test changes between the two loads, so
    # the alias fact is what does the work, not something else.
    test "a bonus_slot_aliases fact — and only it — admits the aliased class", %{tmp_dir: dir} do
      generated = %{
        "feats" => [
          %{
            "id" => "proficiency_test",
            "changes" => [
              %{
                "what" => "feat_slots",
                "value" => %{
                  "general" => false,
                  "by_class" => [
                    %{
                      "class" => "ranger",
                      "slots" => ["favored_enemy"],
                      "raw" => "любимого врага"
                    }
                  ]
                },
                "status" => "custom"
              }
            ]
          }
        ]
      }

      without_alias = load(dir, generated, nil, nil)
      refute MapSet.member?(without_alias.feats[:proficiency_test].bonus_for, :ranger)

      assert "feat_slots" in Enum.map(
               without_alias.feats[:proficiency_test].siala_unapplied,
               & &1["what"]
             )

      overrides = %{
        "feats" => %{
          "bonus_slot_aliases" => %{"value" => %{"favored_enemy" => "class_bonus"}}
        }
      }

      with_alias = load(dir, generated, nil, overrides)
      assert MapSet.member?(with_alias.feats[:proficiency_test].bonus_for, :ranger)

      refute "feat_slots" in Enum.map(
               with_alias.feats[:proficiency_test].siala_unapplied,
               & &1["what"]
             )
    end

    # An alias that points somewhere `apply_feat_change/4` would never match is
    # exactly the typo the check exists to catch — refusing to load beats
    # silently modelling nothing.
    test "an alias to an unknown slot kind fails the load loudly", %{tmp_dir: dir} do
      generated = %{"feats" => []}

      overrides = %{
        "feats" => %{"bonus_slot_aliases" => %{"value" => %{"favored_enemy" => "typo"}}}
      }

      assert_raise RuntimeError, ~r/bonus_slot_aliases/, fn ->
        load(dir, generated, nil, overrides)
      end
    end
  end

  describe "вариант фита, которого в ванили нет" do
    @describetag :tmp_dir

    # `feat_variant_exists` — седьмая тема ручного слоя (задача 3.106, замер
    # Dan 25.08.2026, `GAME_CHECKS.md` AB1: «замерил, skill focus - ride
    # присутствует»). Ванильная страница пишет «There is no skill focus in
    # ride», шард навык ОЖИВИЛ и завёл вариант вместе с ним.
    #
    # ⚠️ Синтетика намеренно: живая запись проверена против живого справочника
    # в `feat_requirements_test.exs`, а здесь проверяется МЕХАНИЗМ — то, что
    # ложной записью не спровоцируешь. Урок 3.93/3.95: контроль на живой записи
    # назавтра получает другое значение и молча перестаёт что-либо проверять.
    test "снимает названное значение и не трогает ни соседнее, ни соседний ключ", %{
      tmp_dir: dir
    } do
      ruleset = load(dir, %{"feats" => []}, manual_variant_exists("skill", "ride"))

      assert ruleset.feats[:focus].prereqs == %{
               "no_feat_variant_for_skills" => ["taunt"],
               "any_skill_ranks" => 20
             }
    end

    # 🔴 ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ НА САМО ПРАВИЛО: умолчание ванильное, и оно
    # возвращается САМО. Убрать сиальскую запись — запрет снова на месте,
    # потому что снимать его будет некому. Ничего не выключено флагом, и
    # «шард молчит» продолжает читаться как ваниль (CLAUDE.md §3).
    test "без сиальской записи ванильный запрет стоит на месте", %{tmp_dir: dir} do
      ruleset = load(dir, %{"feats" => []}, nil)

      assert ruleset.feats[:focus].prereqs["no_feat_variant_for_skills"] == ["ride", "taunt"]
    end

    # Запись, которой нечего снять, роняет сборку — тот же обмен, что делает
    # сосед `requirement_class_level` со своим `from`: ванильная страница могла
    # переехать под записью, либо запись уже применена, и в обоих случаях
    # снятие запрета оказалось бы тихим no-op. А тихий no-op здесь — это
    # ложная НЕЛЕГАЛЬНОСТЬ, которую игрок изнутри инструмента не обойдёт.
    test "значение, которого ваниль не запрещает, роняет сборку", %{tmp_dir: dir} do
      assert_raise RuntimeError,
                   ~r/vanilla's no_feat_variant_for_skills does not forbid it/,
                   fn ->
                     load(dir, %{"feats" => []}, manual_variant_exists("skill", "hide"))
                   end
    end

    # Тот же сторож с другой стороны: фит, у которого такого ключа нет вовсе.
    # Сюда же попадает опечатка в `vanilla_id` — она заводит фит-призрак
    # с пустыми требованиями, и без падения запись выглядела бы применённой.
    test "фит без такого ключа роняет сборку", %{tmp_dir: dir} do
      manual =
        put_in(
          manual_variant_exists("skill", "ride"),
          ["feats", Access.at(0), "vanilla_id"],
          "ward"
        )

      assert_raise RuntimeError, ~r/states no no_feat_variant_for_skills at all/, fn ->
        load(dir, %{"feats" => []}, manual)
      end
    end

    # ⚠️ Та же ветка, но с другого входа, и он-то и есть реалистичный дрейф:
    # у фита требования ЕСТЬ, а этого ключа среди них нет. Так выглядит день,
    # когда ванильную строку с Fandom снимут (или запись применят дважды).
    # Без падения снятие стало бы no-op, а `siala_41/feats.json` продолжал бы
    # уверять, что запрет снят.
    test "фит с требованиями, но без этого ключа, роняет сборку тоже", %{tmp_dir: dir} do
      manual =
        put_in(
          manual_variant_exists("skill", "ride"),
          ["feats", Access.at(0), "vanilla_id"],
          "gate_keeper"
        )

      assert_raise RuntimeError, ~r/states no no_feat_variant_for_skills at all/, fn ->
        load(dir, %{"feats" => []}, manual)
      end
    end

    # Словарь доменов ЗАКРЫТЫЙ. Опечатка в домене иначе прочиталась бы как
    # «ничего не сняли», то есть тихо, — а снятие запрета уменьшает число
    # отказов, и в эту сторону молчать нельзя.
    test "домен вне закрытого словаря роняет сборку", %{tmp_dir: dir} do
      assert_raise RuntimeError, ~r/names domain "weapon"/, fn ->
        load(dir, %{"feats" => []}, manual_variant_exists("weapon", "longsword"))
      end
    end
  end

  # The shard's `Improved evasion` sentence in miniature: a feat whose vanilla
  # requirement is a disjunction, one branch of which the shard moves. Synthetic
  # on purpose — the real record is asserted against the real ruleset above, and
  # this one is about the mechanism (what happens when `from` disagrees), which
  # cannot be provoked with data that is correct.
  # Ручная запись «на шарде вариант фита ЕСТЬ», в той же форме, в какой она
  # лежит в `siala_41/feats.json` у `skill_focus`.
  defp manual_variant_exists(domain, value) do
    %{
      "feats" => [
        %{
          "id" => "focus",
          "vanilla_id" => "focus",
          "changes" => [
            %{
              "what" => "feat_variant_exists",
              "value" => %{"domain" => domain, "value" => value},
              "quote" => "замерил, skill focus - ride присутствует",
              "status" => "verified"
            }
          ]
        }
      ]
    }
  end

  defp manual_branch_move(to) do
    %{
      "feats" => [
        %{
          "id" => "gate_keeper",
          "vanilla_id" => "gate_keeper",
          "changes" => [
            %{
              "what" => "requirement_class_level",
              "value" => %{"class" => "rogue", "from" => 10, "to" => to},
              "quote" => "может взять вор, начиная с 35-го уровня (а не с 10-го)",
              "status" => "verified"
            }
          ]
        }
      ]
    }
  end

  # Билд **легальный**, и это не деталь: вор 36 берёт фит эпическим бонусным
  # слотом, как разрешает страница («может взять, начиная с 35-го уровня»).
  # Оговорка, показанная на нелегальном билде, не доказывает ничего про
  # легальные — на этом уже обжигались, когда фикстурой был вор 10.
  defp rogue_36_with_improved_evasion do
    Build.new(
      levels: List.duplicate(:rogue, 36),
      feats: %{36 => %{{:class_bonus, :rogue} => :improved_evasion}}
    )
  end

  defp load(dir, generated, manual, overrides \\ nil) do
    File.mkdir_p!(Path.join([dir, "siala_41", "generated"]))
    File.mkdir_p!(Path.join(dir, "vanilla"))

    File.cp!(
      Path.join(File.cwd!(), "priv/rules/vanilla/epic.json"),
      Path.join([dir, "vanilla", "epic.json"])
    )

    File.write!(
      Path.join([dir, "vanilla", "classes.json"]),
      Jason.encode!([%{"id" => "fighter", "name" => "Fighter"}])
    )

    File.write!(
      Path.join([dir, "vanilla", "feats.json"]),
      Jason.encode!([
        %{"id" => "ward", "name" => "Ward", "type" => "general"},
        %{
          "id" => "gate_keeper",
          "name" => "Gate keeper",
          "type" => "class",
          "prereqs" => %{
            "any_of" => [
              %{"class_levels" => %{"fighter" => 9}},
              %{"class_levels" => %{"rogue" => 10}}
            ]
          }
        },
        # `Skill focus` в миниатюре: ванильная запись объявляет, что двух пар
        # «фит + значение» не существует, плюс соседний ключ, который дельта
        # обязана не трогать.
        %{
          "id" => "focus",
          "name" => "Focus",
          "type" => "general",
          "prereqs" => %{
            "no_feat_variant_for_skills" => ["ride", "taunt"],
            "any_skill_ranks" => 20
          }
        }
      ])
    )

    File.write!(
      Path.join([dir, "siala_41", "generated", "feats.json"]),
      Jason.encode!(generated)
    )

    if manual do
      File.write!(Path.join([dir, "siala_41", "feats.json"]), Jason.encode!(manual))
    end

    if overrides do
      File.write!(Path.join([dir, "siala_41", "overrides.json"]), Jason.encode!(overrides))
    end

    Loader.load!(dir)["siala_41"]
  end
end
