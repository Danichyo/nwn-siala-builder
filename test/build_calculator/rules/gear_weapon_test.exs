defmodule BuildCalculator.Rules.GearWeaponTest do
  @moduledoc """
  Оружие в руках — задача 3.5, часть B.

  Dan, 09.08.2026: «в вещах можно будет выбрать оружие, допустим „скимитар“
  с усилением атаки +5. И будем показывать в деталях об АБ значение с конкретным
  оружием». И 10.08.2026 про список: «можно в вещах не предлагать выбрать оружие,
  если нет фитов „владение …“. Если в билде есть владение клинковым, то мы все
  мечи и кинжалы из стандартного нвн оружия туда добавляем».

  Источники ожиданий — все в данных, ни одного числа из головы:

    * `priv/rules/vanilla/weapons.json` — 47 записей, `siala_proficiency_group`
      с собственным статусом у каждой; группа → фит владения в
      `_siala_proficiency.groups`;
    * `priv/rules/siala_41/overrides.json` → `gear.weapon.not_wieldable` — пять
      записей оружия существ (`proficiency=creature` у Fandom), которые предметом
      не являются;
    * `stat_caps.attack_bonus.applies_to_sources.gear_weapon` — число оружия
      ВНУТРИ капа +20 (Dan, `GAME_CHECKS.md` J1: «Получается attack bonus или
      enchantment bonus оружия, баффы …, песня барда, бонус светлого эльфа»).
      ⚠️ Чисел было два, с задачи 3.52 одно: усиление у предмета в игре есть,
      но от бонуса атаки его отличал только урон, которого модель не считает.

  ⚠️ Ни одного имени оружия и ни одного имени фита владения в самом ядре нет —
  здесь они есть, и это правильно: тест обязан называть предмет разговора, иначе
  проверять нечего.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Caps, Gear, GearWeapon, Vocabulary}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @flat %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

  defp build(fields \\ []) do
    Build.new(
      [levels: List.duplicate(:fighter, 10), base_abilities: @flat, race: :human] ++ fields
    )
  end

  # Билд, взявший названный сиальский фит владения слотом.
  defp with_proficiency(feat, fields \\ []) do
    build([feats: %{1 => %{{:class_bonus, :fighter} => feat}}] ++ fields)
  end

  defp offered(build, ruleset) do
    for c <- Rules.gear_weapon_candidates(build, ruleset), is_nil(c.reason), do: c.id
  end

  # ---------------------------------------------------------------------------
  # ВТОРАЯ РУКА — задача 3.132 (запрос Dan 28.08.2026: «Можем ввести вторую
  # руку? с возможностью выбрать оружие вместо щита и его attack bonus»).
  #
  # 🔴 Четыре отказа, и КАЖДЫЙ обязан быть своей фразой: «занята двуручным
  # оружием» и «занята вторым оружием» — разные факты об одной руке, и по ним
  # игрок идёт менять разное. Проверяются попарно с положительным контролем,
  # иначе «всё отказано» зеленело бы наравне с верной моделью.
  #
  # Источники: `fandom:Shield proficiency` (revid 54502) — «Creatures may not
  # simultaneously use a shield and a two-handed weapon»; `fandom:Two-handed
  # weapon` (revid 64752) — двуручное занимает обе руки; решение Dan 28.08.2026 —
  # щит и второе оружие одновременно взять нельзя.
  describe "вторая рука" do
    defp two_handed_build(main, off, worn \\ %{}) do
      build(
        gear:
          Gear.new(
            weapon: main,
            off_hand_weapon: off,
            worn: worn,
            feats: [:siala_blade_proficiency, :siala_hammer_proficiency]
          )
      )
    end

    test "двуручное оружие во вторую руку не берётся, одноручное берётся", %{ruleset: ruleset} do
      armed = two_handed_build(nil, nil)

      assert Rules.validate_gear_weapon(armed, :katana, ruleset, :off) == :ok

      assert Rules.validate_gear_weapon(armed, :greatsword, ruleset, :off) ==
               {:error, [{:two_handed_in_off_hand, :greatsword}]}

      # 🔴 Положительный контроль, без которого тест зеленел бы и у модели
      # «во вторую руку нельзя ничего»: та же самая запись в ГЛАВНОЙ руке
      # законна, и отказывает ей ровно хват, а не владение.
      assert Rules.validate_gear_weapon(armed, :greatsword, ruleset, :main) == :ok
    end

    test "двуручное в главной руке отбирает вторую", %{ruleset: ruleset} do
      taken = two_handed_build(:greatsword, :mace)
      free = two_handed_build(:katana, :mace)

      assert Rules.illegal_gear_weapon(taken, ruleset) == [
               {:mace, {:two_handed_weapon, :greatsword}}
             ]

      assert Rules.illegal_gear_weapon(free, ruleset) == []
    end

    # 🔴 Взаимное исключение решено В ПОЛЬЗУ ОРУЖИЯ — ровно так же, как оно
    # решено у двуручного оружия с задачи 3.43: отказ получает щит. Обе фразы
    # проверяются вместе, потому что смысл правки именно в том, что они разные.
    test "щит и второе оружие исключают друг друга, и фразы разные", %{ruleset: ruleset} do
      with_weapon = two_handed_build(:katana, :mace, %{shield: :large})
      with_two_handed = two_handed_build(:greatsword, nil, %{shield: :large})

      assert Rules.illegal_worn(with_weapon, ruleset) == [
               {:shield, :large, {:off_hand_weapon, :mace}}
             ]

      assert Rules.illegal_worn(with_two_handed, ruleset) == [
               {:shield, :large, {:two_handed_weapon, :greatsword}}
             ]

      # Положительный контроль: одной рукой щит остаётся.
      assert Rules.illegal_worn(two_handed_build(:katana, nil, %{shield: :large}), ruleset) == []
    end

    # ⚠️ Отказанное оружие второй руки не считается НИГДЕ — ни в атаке, ни как
    # занятая рука: у щита с ним отказа нет, потому что руки он не занял.
    test "нелегальное второе оружие не отбирает щит", %{ruleset: ruleset} do
      # Без фита владения молотами булава в руки не попадает.
      build =
        build(
          gear:
            Gear.new(
              weapon: :katana,
              off_hand_weapon: :mace,
              worn: %{shield: :large},
              feats: [:siala_blade_proficiency]
            )
        )

      assert Rules.illegal_gear_weapon(build, ruleset) == [
               {:mace, {:requires_feat, :siala_hammer_proficiency}}
             ]

      assert Rules.illegal_worn(build, ruleset) == []
      assert GearWeapon.held(build, ruleset, :off) == nil
    end

    # Число предмета у каждой руки своё — иначе игрок вводил бы два усиления,
    # а видел одно.
    test "усиление второй руки читается своим полем", %{ruleset: ruleset} do
      build =
        build(
          gear:
            Gear.new(
              weapon: :katana,
              weapon_attack: 5,
              off_hand_weapon: :mace,
              off_hand_weapon_attack: 2,
              feats: [:siala_blade_proficiency, :siala_hammer_proficiency]
            )
        )

      assert GearWeapon.attack_bonus(build, ruleset, :main) == 5
      assert GearWeapon.attack_bonus(build, ruleset, :off) == 2
      assert GearWeapon.held_all(build, ruleset) == [main: :katana, off: :mace]
    end
  end

  # ---------------------------------------------------------------------------
  # ДАЛЬНОБОЙНОЕ ВО ВТОРУЮ РУКУ — задача 3.142, замер `GAME_CHECKS.md` AI2.
  #
  # Источник: `fandom:Ranged weapon` (revid 70660) — «No ranged weapon may be
  # wielded in the off-hand slot, nor can any weapon be wielded in the off-hand
  # when a ranged weapon is in the main hand. That is, dual-wielding is not an
  # option with ranged weapons».
  #
  # 🔴 Это ДВА запрета, и второй из первого не следует: праща одноручная, и по
  # хвату вторая рука у неё свободна. Плюс ТРЕТЬЕ утверждение, которое запретом
  # не является и обязано таковым не стать: щит остаётся. Dan 30.08.2026
  # дословно: «игра дает его надеть только в правую руку. Не смотря на то, что
  # праща — одноручная, взять с ней кинжал либо меч в левую руку нельзя.
  # Но можно взять щит».
  describe "дальнобойное во вторую руку" do
    defp ranged_build(main, off, worn \\ %{}) do
      build(
        gear:
          Gear.new(
            weapon: main,
            off_hand_weapon: off,
            worn: worn,
            feats: [:siala_blade_proficiency, :siala_ranged_proficiency]
          )
      )
    end

    # 🔴 ВСЕ ВОСЕМЬ дальнобойных, с причиной у каждого, и причины РАЗНЫЕ.
    # Четыре двуручны, и их отбивает хват — утверждение более старое и более
    # широкое (оно про весь слот). До этой задачи проходили ровно оставшиеся
    # четыре, а совпадение исхода у первых четырёх читалось как правило.
    test "все восемь отбиты, и четыре из них не хватом", %{ruleset: ruleset} do
      armed = ranged_build(nil, nil)

      refusals =
        for {id, weapon} <- Enum.sort(ruleset.weapons),
            weapon.ranged?,
            do: {id, Rules.validate_gear_weapon(armed, id, ruleset, :off)}

      assert refusals == [
               dart: {:error, [{:ranged_in_off_hand, :dart}]},
               heavy_crossbow: {:error, [{:two_handed_in_off_hand, :heavy_crossbow}]},
               light_crossbow: {:error, [{:two_handed_in_off_hand, :light_crossbow}]},
               longbow: {:error, [{:two_handed_in_off_hand, :longbow}]},
               shortbow: {:error, [{:two_handed_in_off_hand, :shortbow}]},
               shuriken: {:error, [{:ranged_in_off_hand, :shuriken}]},
               sling: {:error, [{:ranged_in_off_hand, :sling}]},
               throwing_axe: {:error, [{:ranged_in_off_hand, :throwing_axe}]}
             ]

      # 🔴 Положительный контроль, без которого тест зеленел бы и у модели
      # «дальнобойное нельзя вовсе»: та же праща в ГЛАВНОЙ руке законна.
      assert Rules.validate_gear_weapon(armed, :sling, ruleset, :main) == :ok
      assert Rules.validate_gear_weapon(armed, :longbow, ruleset, :main) == :ok
    end

    # Вторая половина того же предложения, и она про ГЛАВНУЮ руку: пока в ней
    # дальнобойное, второго оружия нет — при том что рук праща занимает одну.
    test "дальнобойное в главной отбирает вторую руку у оружия", %{ruleset: ruleset} do
      assert Rules.illegal_gear_weapon(ranged_build(:sling, :dagger), ruleset) == [
               {:dagger, {:ranged_in_main_hand, :sling}}
             ]

      # Контроль: обычная пара не тронута.
      assert Rules.illegal_gear_weapon(ranged_build(:longsword, :dagger), ruleset) == []
    end

    # 🔴 ТРЕТЬЕ правило замера, и оно про то, чего мы НЕ запрещаем. Источник
    # формулирует два соседних запрета РАЗНОЙ ширины — «any **weapon**»
    # у дальнобойного и «**anything** in the off-hand slot» у двуручного, —
    # и вся разница видна ровно здесь.
    #
    # ⚠️ Проверяется не только отсутствие отказа, но и то, что щит СЧИТАЕТСЯ:
    # тест «отказа нет» зеленел бы и у щита, выпавшего из расчёта.
    test "а щит с дальнобойным остаётся, и считается", %{ruleset: ruleset} do
      with_sling = ranged_build(:sling, nil, %{shield: :large})

      assert Rules.illegal_worn(with_sling, ruleset) == []
      assert Rules.compute(with_sling, ruleset).ac_by_type[:shield] == 2

      # Отрицательный контроль той же руки: двуручное дальнобойное щит отбирает,
      # и отбирает ХВАТОМ. Одно правило шире другого — это и проверяется.
      assert Rules.illegal_worn(ranged_build(:longbow, nil, %{shield: :large}), ruleset) == [
               {:shield, :large, {:two_handed_weapon, :longbow}}
             ]
    end

    # ⚠️ Правило ванильное по источнику, и на ванили действует так же. Отдельным
    # тестом, потому что `_off_hand` лежит в общем файле, а вопрос «доезжает ли
    # он до ОБОИХ ruleset'ов» решается сборкой, а не чтением.
    test "на ванили ровно то же самое", %{vanilla: vanilla} do
      armed = ranged_build(:sling, :dagger)

      assert Rules.illegal_gear_weapon(armed, vanilla) == [
               {:dagger, {:ranged_in_main_hand, :sling}}
             ]

      assert Rules.validate_gear_weapon(armed, :sling, vanilla, :off) ==
               {:error, [{:ranged_in_off_hand, :sling}]}

      assert Rules.illegal_worn(ranged_build(:sling, nil, %{shield: :large}), vanilla) == []
    end

    # Отказанное второе оружие не считается нигде — ни в бою двумя оружиями,
    # ни в бонусе за тип оружия. Иначе штраф стиля, лишняя атака и чужой бонус
    # печатались бы персонажу, которого в игре не собрать.
    #
    # 🔴 Цена, ради которой задача и заведена: `меч + праща` давал ДВА бонуса
    # за тип оружия — клинковый щитовой AC и дальнобойный бонус атаки, — то есть
    # до +9 AB ни за что. Пара с законным вторым оружием стоит рядом
    # положительным контролем: без неё тест зеленел бы и у модели, где второй
    # руки нет вовсе.
    test "отбитая вторая рука не даёт ни штрафа стиля, ни своего бонуса", %{ruleset: ruleset} do
      pair = fn off ->
        build(
          levels: List.duplicate(:fighter, 41),
          gear:
            Gear.new(
              weapon: :katana,
              off_hand_weapon: off,
              feats: [:siala_blade_proficiency, :siala_ranged_proficiency]
            )
        )
      end

      with_sling = Rules.compute(pair.(:sling), ruleset)
      with_dagger = Rules.compute(pair.(:dagger), ruleset)

      assert GearWeapon.held_all(pair.(:sling), ruleset) == [main: :katana]
      assert with_sling.dual_wield == nil
      assert with_sling.off_hand == nil

      assert for(e <- with_sling.weapon_type_bonuses, do: {e.weapon, e.kind, e.counted}) ==
               [{:katana, :shield_ac, 9}]

      # Положительный контроль: законная вторая рука делает все три вещи.
      # ⚠️ −4/−8, а не база −6/−10: кинжал `tiny`, для человека это лёгкое
      # оружие, и оно снимает по 2 с обеих рук («Best results are achieved if
      # the off-hand weapon is light»).
      assert with_dagger.dual_wield.penalty == %{main: -4, off: -8}
      assert with_dagger.off_hand.attacks_per_round == 1
      assert GearWeapon.held_all(pair.(:dagger), ruleset) == [main: :katana, off: :dagger]
    end
  end

  describe "фильтр по фитам владения" do
    # 🔴 ОБЕ половины парного правила ОДНИМ тестом: фильтр прячет неподходящее
    # И пропускает подходящее. Порознь каждая зеленела бы и при неверной модели —
    # «скимитар не предлагается» верно и у кода, который не предлагает ничего.
    test "владение клинковым открывает клинковое и не открывает топоры", %{ruleset: ruleset} do
      blade = with_proficiency(:siala_blade_proficiency)
      none = build()

      blade_offered = offered(blade, ruleset)

      # Прячет: без фита скимитара в списке нет.
      refute :scimitar in offered(none, ruleset)

      # Пропускает: с фитом есть, и не только он — вся группа.
      assert :scimitar in blade_offered
      assert :longsword in blade_offered
      assert :dagger in blade_offered

      # И не открывает лишнего: топор клинковым владением не открывается.
      refute :battleaxe in blade_offered
      assert {:requires_feat, :siala_axe_proficiency} = refusal(blade, :battleaxe, ruleset)
    end

    test "владение топорами открывает топоры и не открывает клинковое", %{ruleset: ruleset} do
      axe = with_proficiency(:siala_axe_proficiency)
      axe_offered = offered(axe, ruleset)

      assert :battleaxe in axe_offered
      assert :greataxe in axe_offered
      refute :scimitar in axe_offered
    end

    # ⚠️ Владение может прийти С ВЕЩИ (`Rules.GearFeats`) — фит есть фит, как бы
    # он ни пришёл, и это то же чтение, по которому объявленный `Toughness` даёт
    # HP. Отрицательный контроль рядом: без объявления оружие не предлагается.
    test "владение с вещи открывает оружие так же, как взятое слотом", %{ruleset: ruleset} do
      declared = build(gear: Gear.new(feats: [:siala_blade_proficiency]))

      assert :scimitar in offered(declared, ruleset)
      refute :scimitar in offered(build(), ruleset)
    end
  end

  describe "три ответа про владение, а не два" do
    # 🔴 Посох обязан проходить фильтр ВСЕГДА: он владения не требует (замер Dan),
    # и без этого у волшебника без единого фита владения список оказался бы пуст,
    # а он в игре бегает с посохом.
    test "посох предлагается персонажу без единого фита владения", %{ruleset: ruleset} do
      wizard = Build.new(levels: List.duplicate(:wizard, 10), base_abilities: @flat, race: :human)

      assert :magic_staff in offered(wizard, ruleset)
      assert GearWeapon.validate(wizard, :magic_staff, ruleset) == :ok

      # Отрицательный контроль: список НЕ «пропускает всё» — скимитар волшебнику
      # без владения клинковым не предлагается.
      refute :scimitar in offered(wizard, ruleset)
    end

    # ✅ **ИЗМЕРЕНО Dan 16.08.2026** (смотрел список оружия в игре): «club, magic
    # staff и unarmed не требуют фитов, они доступны всем классам на Сиале
    # базово». ⚠️ Здесь у дубины стояла оговорка
    # `{:missing_data, {:weapon_proficiency, :club}}` — «требование не прочитано», —
    # и она была честной ровно до этого дня: Сиала не называет дубину ни в одной
    # из пяти категорий, и молчание источника читалось как незнание.
    #
    # ⚠️ Третье состояние («не прочитано») из модели НЕ ушло — просто на нём
    # больше нет ни одного оружия. Проверяется, что все три молчат по ОДНОЙ
    # причине: ответ известен, а не потому, что оговорку выкинули.
    test "посох, дубина и рукопашный удар молчат — владения не требует ни один", %{
      ruleset: ruleset
    } do
      by_id = Map.new(Rules.gear_weapon_candidates(build(), ruleset), &{&1.id, &1})

      for weapon <- [:magic_staff, :club, :unarmed_strike] do
        assert by_id[weapon].caveats == [],
               "#{weapon}: владение известно, оговорки быть не должно"

        assert is_nil(by_id[weapon].reason), "#{weapon}: запрета никто не называл"
      end
    end

    # ✅ **ПОДТВЕРЖДЕНО Dan 16.08.2026** — оговорки «группу назначили сами» нет
    # больше ни у одного оружия. ⚠️ Здесь стояло обратное: скимитар нёс
    # `{:assumed, {:weapon_proficiency_group, :scimitar, :blade}}`, и это было
    # верно ровно до дня, когда Dan сверил список.
    #
    # ⚠️ И снялась оговорка НЕ потому, что русского имени нет в интерфейсе (его
    # там правда нет). Группу Сиала называет сама, и дважды — пятью страницами
    # фитов и колонкой «Тип оружия» сводной таблицы; нашим был только ПЕРЕВОД
    # ИМЕНИ, и проверял Dan именно его. Маппинг решает, какой фит потребуется
    # и какой бонус за тип оружия начислится, то есть виден в числах.
    test "оговорки «группу назначили сами» не осталось ни у одного оружия", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      for rs <- [ruleset, vanilla] do
        assumed =
          for candidate <- Rules.gear_weapon_candidates(build(), rs),
              {:assumed, {:weapon_proficiency_group, _, _}} <- candidate.caveats,
              do: candidate.id

        assert assumed == [], "осталось допущение группы: #{inspect(assumed)}"
      end

      # Положительный контроль: список не пуст и оговорок у него нет вовсе —
      # иначе «ни одного» выполнялось бы и у пустого списка.
      by_id = Map.new(Rules.gear_weapon_candidates(build(), ruleset), &{&1.id, &1})
      assert by_id[:scimitar].caveats == []
      assert by_id[:longbow].caveats == []
    end

    # ⚠️ Форма и механизм ЖИВЫ, просто в данных на них больше нет ни одной
    # записи: шард добавит оружие, которого нет в сводной таблице, — и оговорка
    # обязана вернуться сама. Проверяется единственным способом, каким это
    # можно проверить без выдуманного игрового факта: копией `priv/rules`,
    # где одной записи возвращён статус `assumed`. Утверждения про игру здесь
    # нет — испорчена копия, а не снапшот.
    #
    # ⚠️ Оговорка доезжает до ГЭПОВ БИЛДА, а не только до списка: игрок,
    # открывший чужую ссылку, список не листает.
    test "механизм оговорки жив: возвращённый `assumed` доезжает до гэпов билда" do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      path = Path.join([root, "vanilla", "weapons.json"])

      weapons = path |> File.read!() |> Jason.decode!()

      patched =
        update_in(weapons["weapons"], fn list ->
          for weapon <- list do
            if weapon["id"] == "scimitar",
              do: Map.put(weapon, "siala_proficiency_group_status", "assumed"),
              else: weapon
          end
        end)

      File.write!(path, Jason.encode!(patched))

      ruleset = BuildCalculator.Data.Loader.load!(root)["siala_41"]

      with_scimitar =
        with_proficiency(:siala_blade_proficiency, gear: %Gear{weapon: :scimitar})

      stats = Rules.compute(with_scimitar, ruleset)

      assert {:assumed, {:weapon_proficiency_group, :scimitar, :blade}} in stats.gaps

      # Отрицательный контроль: у билда без оружия оговорки нет и в этой копии —
      # она про выбранное оружие, а не про ruleset целиком.
      refute Enum.any?(
               Rules.compute(build(), ruleset).gaps,
               &match?({_, {:weapon_proficiency_group, _, _}}, &1)
             )
    end
  end

  describe "не предмет — не предлагается" do
    # Пять записей справочника это форма атаки существа, а не предмет: усиление
    # атаки вводится С ПРЕДМЕТА, а предмета там нет.
    test "оружие существ отсутствует в списке целиком", %{ruleset: ruleset} do
      ids = for c <- Rules.gear_weapon_candidates(build(), ruleset), do: c.id

      for creature <- [:bite_item, :claw_item, :creature_weapon, :gore_item, :slam_item] do
        refute creature in ids, "#{creature} — не предмет игрока"
      end

      # Положительный контроль: 41 из 47 — пять форм атаки существа и лэнс.
      # ⚠️ Было 42: лэнс убран 16.08.2026 по наблюдению Dan («нет такого
      # на Сиале»), и причина отказа у него СВОЯ, а не «не предмет игрока».
      assert length(ids) == 41
      refute :lance in ids

      # 🔴 И вторая половина, без которой правка молча соврала бы про ВАНИЛЬ:
      # лэнса нет **на Сиале**, а в NWN он есть. Первая редакция положила запись
      # в секцию `gear`, которую видят оба ruleset'а, и у ванили список тоже
      # стал 41 — поймано прогоном, а не рассуждением.
      vanilla = BuildCalculator.Data.ruleset!("vanilla")
      vanilla_ids = for c <- Rules.gear_weapon_candidates(build(), vanilla), do: c.id

      assert :lance in vanilla_ids
      assert length(vanilla_ids) == 42

      # ⚠️ И рукопашный удар в этот список НЕ входит: монах им бьёт, и фокус
      # на него берут.
      assert :unarmed_strike in ids
    end

    # Правленая руками ссылка называет форму атаки существа — отказ с причиной,
    # а не молчаливое «ничего не считаем».
    test "оружие существ отбивается причиной", %{ruleset: ruleset} do
      assert GearWeapon.validate(build(), :bite_item, ruleset) ==
               {:error, [{:not_wieldable, :bite_item}]}

      assert GearWeapon.validate(build(), :not_a_weapon, ruleset) ==
               {:error, [{:unknown_weapon, :not_a_weapon}]}
    end

    # В СПРАВОЧНИКЕ они остаются как были — это другой вопрос («во что можно
    # взять фокус»), и часть A его не трогала.
    #
    # ⚠️ Здесь стояло «в домене выбора фитов оружие существ осталось», и с
    # 26.08.2026 это верно только про справочник, а не про предложение: замер
    # AC6 закрыл `Weapon focus (Creature weapon)` на Сиале ВОРОТАМИ домена
    # (`overrides.json` → `weapons.no_feat_variant`, разбор в `weapons_test.exs`).
    # Запись при этом никуда не делась — убрано предложение, а не факт, — и обе
    # половины стоят рядом именно поэтому.
    test "в справочнике оружие существ осталось, но фитом Сиалы не предлагается", %{
      ruleset: ruleset
    } do
      values = ruleset.choice_domains[:weapon].values
      gate = ruleset.choice_domains[:weapon].flags[Rules.FeatChoices.domain_gate()]

      assert MapSet.member?(values, :creature_weapon)
      assert MapSet.member?(values, :unarmed_strike)

      refute MapSet.member?(gate, :creature_weapon)

      # Положительный контроль: рукопашный удар в воротах есть — проверка
      # про закрытое значение, а не про пустые ворота.
      assert MapSet.member?(gate, :unarmed_strike)
    end
  end

  describe "оружие, потерявшее основание" do
    # 🔴 Требование задания: помечать, а не молча выбрасывать. Форма та же, что
    # у сброса поинт-бая (1.7) и у фита с вещи, который шард выключил.
    test "снял фит владения — оружие названо в illegal и перестало считаться", %{
      ruleset: ruleset
    } do
      gear = %Gear{weapon: :scimitar, weapon_attack: 5}
      legal = with_proficiency(:siala_blade_proficiency, gear: gear)
      illegal = build(gear: gear)

      # Положительный контроль: с фитом всё считается и претензий нет.
      assert Rules.illegal_gear_weapon(legal, ruleset) == []
      assert Rules.compute(legal, ruleset).weapon_attack_bonus == 5

      # Без фита: оружие ОСТАЛОСЬ в билде (запись игрока не теряется), названо
      # с причиной, и в числа не идёт.
      assert illegal.gear.weapon == :scimitar

      assert Rules.illegal_gear_weapon(illegal, ruleset) ==
               [{:scimitar, {:requires_feat, :siala_blade_proficiency}}]

      assert Rules.compute(illegal, ruleset).weapon_attack_bonus == 0
      assert Rules.compute(illegal, ruleset).weapon == nil
    end
  end

  describe "число предмета" do
    # ⚠️ ОДНО поле с задачи 3.52, два до неё. Решение Dan 19.08.2026: «У оружия мы
    # можем вбить или attack bonus, или enchantment bonus. Второй отличается
    # от первого тем, что еще дает урон. Но, урон мы нигде не выводим и не
    # считаем, так что надо нам от enchantment bonus просто отказаться».
    #
    # 🔴 **Число ПОД капом — решение Dan 18.08.2026, идущее ПРОТИВ замера Q5.**
    # Дословно: «они оба по идее работают идентично и внутри капа… нам на 100%
    # надо attack bonus засунуть внутрь капа 20».
    #
    # ⚠️ История правила в одном месте, чтобы следующий не «чинил» его в шестой
    # раз вслепую: J1 (10.08, слово) — внутри; Q5 (15.08, ЗАМЕР) — снаружи,
    # потому что светлый эльф-сагровик 40 с луком +5 показал AB 62 там, где
    # 5 + 9 + 9 = 23 обязаны были срезаться до 20 и дать 59; 18.08 (решение
    # владельца) — снова внутри, с открытым вопросом.
    #
    # 🔴 **Спор НЕ разрешён, и это единственное место, где мы сознательно
    # расходимся с наблюдением.** Гипотеза Dan: лист персонажа показывает
    # завышенное AB, а в боевом логе было бы 59. Проверяется переоткрытым Q5.
    # Тест на 62 не удалён, а помечен отложенным (`weapon_type_bonus_test.exs`).
    test "число идёт в атаку и стоит ПОД капом", %{ruleset: ruleset} do
      gear = %Gear{weapon: :scimitar, weapon_attack: 5}
      b = with_proficiency(:siala_blade_proficiency, gear: gear)
      stats = Rules.compute(b, ruleset)

      assert stats.weapon_attack_bonus == 5
      assert stats.weapon_attack_terms == [%{kind: :attack, bonus: 5, under_cap?: true}]

      assert Caps.covers_source?(ruleset, :attack_bonus, GearWeapon.cap_source())
    end

    # ⚠️ Задача 3.52 убрала ВТОРОЕ ЧИСЛО, а не механизм: сколько их у предмета,
    # объявляют данные, и ядро читает объявленное, а не «одно». Проверяется
    # тем, что вид числа берётся из ruleset'а, а поле под него — у самой
    # структуры вещей; загрузчик роняет сборку у вида без поля, поэтому пара
    # обязана сходиться.
    test "видов числа ровно столько, сколько объявляют данные", %{ruleset: ruleset} do
      assert ruleset.gear.weapon_bonus_kinds == [:attack]

      for kind <- ruleset.gear.weapon_bonus_kinds do
        assert Gear.weapon_bonus_field(kind) != nil
      end

      # И обратная половина: усиление полем БОЛЬШЕ НЕ ЯВЛЯЕТСЯ, то есть ruleset,
      # объявивший его, сборку уронит — а не посчитает объявленное число нулём.
      assert Gear.weapon_bonus_field(:enhancement) == nil
    end

    # 🔴 Сторож загрузчика обязан ПЕРЕЖИТЬ задачу 3.52, а не уйти вместе с полем:
    # именно он делает список видов из данных настоящим механизмом, а не
    # украшением. Проверяется единственным способом, каким это можно проверить
    # без выдуманного факта: копией `priv/rules`, где усиление возвращено
    # в `gear.weapon.bonus_fields` — поля под него в `Rules.Gear` больше нет,
    # значит объявленное число молча считалось бы нулём.
    test "объявленный вид без поля роняет сборку, а не считается нулём" do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      path = Path.join([root, "siala_41", "overrides.json"])
      overrides = path |> File.read!() |> Jason.decode!()

      patched =
        put_in(overrides["gear"]["weapon"]["bonus_fields"]["value"], ["attack", "enhancement"])

      File.write!(path, Jason.encode!(patched))

      assert_raise RuntimeError, ~r/bonus_fields names \[enhancement: :main/, fn ->
        BuildCalculator.Data.Loader.load!(root)
      end
    end

    # ⚠️ Оговорка `{:assumed, :weapon_bonuses_stack}` («складываются ли два числа,
    # не написано ни на одной вики») ушла вместе со вторым числом: складывать
    # стало нечего, то есть вопрос ИСЧЕЗ, а не остался без ответа. Форма снята
    # и из `Rules.Vocabulary` — тест держит это с двух сторон, чтобы оговорка
    # не вернулась молча вместе с полем.
    test "оговорки про сложение нет ни у одного билда с оружием", %{ruleset: ruleset} do
      gear = %Gear{weapon: :scimitar, weapon_attack: 5}
      stats = Rules.compute(with_proficiency(:siala_blade_proficiency, gear: gear), ruleset)

      refute Enum.any?(stats.gaps, &match?({:assumed, :weapon_bonuses_stack}, &1))

      refute Enum.any?(
               Vocabulary.gaps(),
               &match?({:assumed, :weapon_bonuses_stack}, &1)
             )
    end

    # Нулевой терм не печатается — то же правило, что у всех остальных списков
    # термов: строка, стоящая ноль, занимает место и ни на что не отвечает.
    test "нулевое число терма не даёт", %{ruleset: ruleset} do
      b = with_proficiency(:siala_blade_proficiency, gear: %Gear{weapon: :scimitar})
      stats = Rules.compute(b, ruleset)

      assert stats.weapon_attack_terms == []
      assert stats.weapon_attack_bonus == 0

      # ⚠️ Но САМО оружие в руках есть — и это не то же самое: от него зависят
      # три фита, а не только его собственные числа.
      assert stats.weapon == :scimitar
    end

    # Штраф проезжает: проклятое оружие бывает, а потолок объявлен только сверху
    # («лимит атаки +20»), и зеркалить его в пол значило бы выдумать число.
    test "минус проходит через модель без клипа", %{ruleset: ruleset} do
      gear = %Gear{weapon: :scimitar, weapon_attack: -2}
      stats = Rules.compute(with_proficiency(:siala_blade_proficiency, gear: gear), ruleset)

      assert stats.weapon_attack_bonus == -2
      assert stats.attack_cap_clipped == 0
    end
  end

  describe "потолок атаки +20 достижим — подтверждено боевым логом 24.08.2026" do
    # 🔴 ЧЕТВЁРТАЯ и последняя редакция этого describe, и все четыре записаны,
    # потому что правило переписывали на ОДНИХ И ТЕХ ЖЕ числах:
    #
    #   10.08 (слово, J1)   — числа оружия ПОД капом, кап впервые кусает
    #   15.08 (ЗАМЕР, Q5)   — снаружи: AB 62 там, где срез дал бы 59
    #   18.08 (решение Dan) — снова ПОД капом, «инфа 100%», тест на 62 отложен
    #   24.08 (ЗАМЕР, Q5b)  — ✅ ПОД капом, и спор закрыт
    #
    # ✅ Спор разрешён, и разрешил его ИСТОЧНИК ЧИСЛА, а не новое число.
    # Dan 24.08.2026: «в логе на 3 меньше, 62 лист → 59 лог. Лог всегда вернее
    # чарлиста». То есть замер Q5 от 15.08 был снят с ЛИСТА, лист завышает,
    # и вывод «оружие вне капа» стоял на дефекте клиента игры.
    #
    # ⚠️ Разница ровно 3 подтверждает не только число, но и СОСТАВ капа: игра
    # режет 5 + 9 + 9 = 23 до 20 тем же одним клипом, что и мы. Решение Dan
    # от 18.08, принятое вопреки собственному же замеру, оказалось верным.
    #
    # 🔴 Урок: «игрок наблюдал в игре» — это ДВА источника разного качества,
    # лист и боевой лог, и при расхождении верен лог.
    #
    # Тест закрепляет срез на тех же числах, на которых прежняя редакция
    # закрепляла его ОТСУТСТВИЕ: `+15` оружия и `+9` расовых — это 24, срез до 20.
    test "оружие +15 и расовый бонус +9 вместе режутся до 20", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 40)

      gear = %Gear{weapon: :scimitar, weapon_attack: 15}

      b =
        Build.new(
          levels: levels,
          base_abilities: @flat,
          race: :half_elf,
          feats: %{1 => %{{:class_bonus, :fighter} => :siala_blade_proficiency}},
          gear: gear
        )

      stats = Rules.compute(b, ruleset)
      race = stats.race_attack_bonus

      assert race == 9, "светлый эльф-сагровик 40 с оружием в руках"

      # 15 + 9 = 24 внутрикапного, потолок 20 → срез на 4.
      assert race == 9
      assert stats.attack_extra_bonus == 20
      assert stats.attack_cap_clipped == -4
      assert :attack_bonus in stats.capped
    end

    # Отрицательный контроль к предыдущему: ниже потолка ничего не режется, и
    # оба источника доезжают целиком.
    test "оружие +5 и расовый бонус вместе проходят без среза", %{ruleset: ruleset} do
      b =
        Build.new(
          levels: List.duplicate(:fighter, 40),
          base_abilities: @flat,
          race: :half_elf,
          feats: %{1 => %{{:class_bonus, :fighter} => :siala_blade_proficiency}},
          gear: %Gear{weapon: :scimitar, weapon_attack: 5}
        )

      stats = Rules.compute(b, ruleset)

      assert stats.attack_extra_bonus == 5 + stats.race_attack_bonus
      assert stats.attack_cap_clipped == 0
      refute :attack_bonus in stats.capped
    end
  end

  describe "ванильный ruleset" do
    # ⚠️ Пяти сиальских фитов владения на ванили нет вовсе — они приходят слоем
    # шарда. Значит требование там ПРОЧИТАТЬ НЕЧЕМ, и ответ тот же, что у дубины:
    # оружие предлагается и говорит, что проверки нет. Запретить всё значило бы
    # сделать ванильный ruleset неработоспособным.
    test "без сиальских фитов владения всё предлагается с оговоркой", %{vanilla: vanilla} do
      b = Build.new(levels: [:fighter], base_abilities: @flat, race: :human)
      candidates = Rules.gear_weapon_candidates(b, vanilla)
      by_id = Map.new(candidates, &{&1.id, &1})

      assert is_nil(by_id[:scimitar].reason)
      assert by_id[:scimitar].caveats == [{:missing_data, {:weapon_proficiency, :scimitar}}]

      # Оружие существ и здесь не предлагается — факт ванильный, и секцию
      # `gear` видят оба ruleset'а.
      refute Map.has_key?(by_id, :bite_item)
    end
  end

  defp refusal(build, weapon, ruleset) do
    case GearWeapon.validate(build, weapon, ruleset) do
      :ok -> nil
      {:error, [reason]} -> reason
    end
  end
end
