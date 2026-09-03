defmodule BuildCalculator.Rules.DualWieldTest do
  @moduledoc """
  Бой двумя оружиями — задача 3.132.

  Источники, по которым посчитано всё ниже:

    * **таблица штрафов** — `fandom:Two-weapon fighting` (revid 41783), описание
      фита целиком: «The normal penalty of -6 to the primary hand and -10 to the
      off-hand becomes -4 for the primary hand and -8 for the off-hand. The
      ambidexterity feat further reduces the attack penalty for the second weapon
      by 4 (to -4/-4). Best results are achieved if the off-hand weapon is light,
      further reducing the penalty for both the primary and off-hand by 2
      (to -2/-2)»;
    * **прирост Ambidexterity сам по себе** — `fandom:Ambidexterity` (revid
      68733): «When fighting with two weapons, this feat reduces the penalty of
      the off-hand weapon by 4» — БЕЗ оговорки про Two-weapon fighting, отсюда
      −6/−6 у билда, взявшего только его;
    * **лёгкое оружие** — `fandom:Weapon size` (revid 59292): «A melee weapon at
      least one size smaller than the wielder is considered a light weapon»;
    * **двустороннее оружие** — `fandom:Double-sided weapon` (revid 68931):
      «Wielding a double-sided weapon automatically causes one to be
      dual-wielding, allowing an extra attack (or two) per combat round and
      incurring the standard dual-wielding penalties. These penalties are not as
      severe as possible, as a double-sided weapon's off-hand end counts as a
      light weapon»;
    * **вторая атака** — `fandom:Improved two-weapon fighting` (revid 70454):
      «The character with this feat is able to get a second off-hand attack (at a
      penalty of -5 to his attack roll)»;
    * **выдача Рейнджера** — `fandom:Dual-wield (feat)` (revid 44233): «Rangers,
      when wearing light armor, get all the benefits of having the ambidexterity
      and two-weapon fighting feats. While wearing medium or heavy armor they
      lose these benefits»;
    * **два оружия — два бонуса** — `Система оружия` Сиалы (revid 20527):
      «Используя два разных оружия персонаж получает два разных бонуса».

  🔴 **Главная проверка транскрипции — первый describe:** источник печатает
  ЧЕТЫРЕ итога (−6/−10, −4/−8, −4/−4, −2/−2), а данные хранят базу и приросты.
  Если приросты записаны неверно, хотя бы один из четырёх итогов разойдётся.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, DualWield, Gear, Wield}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @abilities %{str: 18, dex: 14, con: 14, int: 10, wis: 10, cha: 10}

  # Пять сиальских фитов владения разом: задача не про владение, и без них
  # оружие просто не оказалось бы в руках. ⚠️ У ванильного ruleset'а этих фитов
  # нет вовсе, и владение там не проверяется (`:unread`) — то есть один и тот же
  # билд годится обоим.
  @proficiencies [
    :siala_blade_proficiency,
    :siala_axe_proficiency,
    :siala_hammer_proficiency,
    :siala_polearm_proficiency,
    :siala_ranged_proficiency
  ]

  defp build(opts) do
    Build.new(
      race: Keyword.get(opts, :race, :human),
      levels: List.duplicate(:fighter, Keyword.get(opts, :levels, 20)),
      base_abilities: @abilities,
      gear:
        Gear.new(
          weapon: Keyword.get(opts, :weapon, :katana),
          off_hand_weapon: Keyword.get(opts, :off_hand),
          worn: Keyword.get(opts, :worn, %{}),
          feats: @proficiencies ++ Keyword.get(opts, :feats, [])
        )
    )
  end

  defp penalty(opts, ruleset) do
    opts |> build() |> DualWield.of(ruleset) |> DualWield.penalty()
  end

  describe "таблица штрафов" do
    # 🔴 ЧЕТЫРЕ ИТОГА ИСТОЧНИКА, дословно. Оружие второй руки здесь неЛЁГКОЕ
    # (warhammer, medium — тот же размер, что у человека), поэтому первые три
    # строки читаются напрямую из описания фита; четвёртая берёт лёгкое.
    test "четыре напечатанных источником итога воспроизводятся", %{ruleset: ruleset} do
      table = [
        # {фиты, оружие второй руки, {главная, вторая}, что печатает источник}
        {[], :warhammer, {-6, -10}, "The normal penalty of -6 … and -10"},
        {[:two_weapon_fighting], :warhammer, {-4, -8}, "becomes -4 … and -8 for the off-hand"},
        {[:two_weapon_fighting, :ambidexterity], :warhammer, {-4, -4}, "(to -4/-4)"},
        {[:two_weapon_fighting, :ambidexterity], :mace, {-2, -2}, "(to -2/-2)"}
      ]

      for {feats, off_hand, {main, off}, quote_} <- table do
        assert penalty([feats: feats, off_hand: off_hand], ruleset) == %{main: main, off: off},
               "#{quote_}"
      end
    end

    # ⚠️ Комбинация, которой источник НЕ печатает, и потому она проверяется
    # отдельно и с собственной цитатой: страница `Ambidexterity` формулирует
    # свой прирост безусловно, значит билд без Two-weapon fighting получает
    # −6/−6, а не −6/−10 и не −4/−4.
    test "Ambidexterity без Two-weapon fighting снимает 4 только второй руке", %{
      ruleset: ruleset
    } do
      assert penalty([feats: [:ambidexterity], off_hand: :warhammer], ruleset) ==
               %{main: -6, off: -6}
    end

    # И вторая невыведенная комбинация: лёгкое оружие без единого фита.
    # «further reducing the penalty for both» — прирост свой, а не часть пакета.
    test "лёгкое оружие без фитов снимает по 2 обеим рукам", %{ruleset: ruleset} do
      assert penalty([off_hand: :mace], ruleset) == %{main: -4, off: -8}
    end

    test "то же самое на ванильном ruleset'е", %{vanilla: vanilla} do
      assert penalty([off_hand: :warhammer], vanilla) == %{main: -6, off: -10}

      assert penalty([feats: [:two_weapon_fighting, :ambidexterity], off_hand: :mace], vanilla) ==
               %{main: -2, off: -2}
    end
  end

  describe "лёгкость второй руки" do
    # 🔴 Правило — функция ДВУХ размеров, ровно как хват: короткий меч (small)
    # лёгкий для человека и не лёгкий для Карлика (small). Проверяется парой,
    # потому что порознь каждая строка зеленеет и у неверной модели.
    test "короткий меч: у человека лёгкий, у Карлика нет", %{ruleset: ruleset} do
      assert penalty([off_hand: :shortsword], ruleset) == %{main: -4, off: -8}

      # ⚠️ У Карлика (Gnome) катана в главной руке двуручная — размер medium
      # против small, — поэтому главная рука берёт кинжал: задача здесь про
      # лёгкость второй руки, а не про хват первой.
      assert penalty([race: :gnome, weapon: :dagger, off_hand: :shortsword], ruleset) ==
               %{main: -6, off: -10}
    end

    # ⚠️ Источник говорит «A **melee** weapon …», то есть про дальнобойное
    # не утверждает ничего. Праща размера small — по одному только размеру она
    # была бы лёгкой; расширять предложение за его собственные слова нельзя.
    #
    # 🔴 ЗДЕСЬ СТОЯЛО `penalty([off_hand: :sling]) == %{main: -6, off: -10}`,
    # и с задачи 3.142 такого билда не существует: дальнобойное во вторую руку
    # не идёт вовсе (`fandom:Ranged weapon`, замер `GAME_CHECKS.md` AI2).
    # Проверяемое правило от этого не исчезло — исчез путь, которым оно
    # проверялось, — поэтому оно спрашивается там, где живёт, и рядом
    # спрашивается запрет: иначе следующий читатель решит, что правило лёгкости
    # для дальнобойного отменили.
    test "праща размером как лёгкое оружие лёгкой не считается", %{ruleset: ruleset} do
      armed = build(weapon: :katana)

      assert Wield.light?(armed, :sling, ruleset) == false
      assert Wield.light?(armed, :shortsword, ruleset) == true

      assert Rules.validate_gear_weapon(armed, :sling, ruleset, :off) ==
               {:error, [{:ranged_in_off_hand, :sling}]}
    end

    # Сказать нечем — значит −2 не сняты, и билд говорит об этом вслух.
    test "у рукопашного удара нет размера — оговорка вместо −2", %{ruleset: ruleset} do
      build = build(off_hand: :unarmed_strike)

      assert DualWield.of(build, ruleset).light_off_hand? == nil
      assert DualWield.penalty(DualWield.of(build, ruleset)) == %{main: -6, off: -10}
      assert {:missing_data, {:light_weapon, :unarmed_strike}} in DualWield.gaps(build, ruleset)
    end
  end

  describe "двустороннее оружие" do
    # 🔴 ВТОРОЙ способ оказаться в бою двумя оружиями, и вторая рука при нём
    # пуста. Без этого правила билд с двулезвийным мечом показывал бы AB
    # главной руки на 2 больше настоящего — завышение, которое игрок изнутри
    # инструмента не обнаружит.
    test "двулезвийный меч сам ставит персонажа в бой двумя оружиями", %{ruleset: ruleset} do
      style = DualWield.of(build(weapon: :two_bladed_sword, off_hand: nil), ruleset)

      assert style.source == :double_sided
      assert style.off_hand_weapon == nil
      assert style.penalty == %{main: -4, off: -8}
      assert style.off_hand_attacks == 1
    end

    # ⚠️ «Лёгкость» здесь названа СЛОВОМ источника, а не посчитана по размеру:
    # двулезвийный меч `large`, и по размерному правилу лёгким он не был бы
    # никогда. Проверяется тем, что −2 всё-таки сняты.
    test "второй конец считается лёгким, хотя оружие large", %{ruleset: ruleset} do
      style = DualWield.of(build(weapon: :dire_mace, off_hand: nil), ruleset)

      assert style.light_off_hand? == true
      assert style.penalty == %{main: -4, off: -8}
    end

    test "и на ванильном ruleset'е тоже", %{vanilla: vanilla} do
      style = DualWield.of(build(weapon: :double_axe, off_hand: nil), vanilla)

      assert style.source == :double_sided
      assert style.penalty == %{main: -4, off: -8}
    end

    # Отрицательный контроль: обычное двуручное оружие в бой двумя оружиями
    # НЕ ставит — «двуручное» и «двустороннее» разные слова справочника.
    test "обычное двуручное оружие боем двумя оружиями не является", %{ruleset: ruleset} do
      assert DualWield.of(build(weapon: :greatsword, off_hand: nil), ruleset) == nil
    end
  end

  describe "число атак второй руки" do
    # ⚠️ Своё число, а не копия главной: у главной руки при БАБ 20 их четыре.
    test "одна атака, две с Improved two-weapon fighting", %{ruleset: ruleset} do
      one = build(off_hand: :mace)
      two = build(off_hand: :mace, feats: [:improved_two_weapon_fighting])

      assert DualWield.of(one, ruleset).off_hand_attacks == 1
      assert DualWield.of(two, ruleset).off_hand_attacks == 2

      assert Rules.compute(one, ruleset).attacks_per_round == 4
      assert Rules.compute(two, ruleset).off_hand.attacks_per_round == 2
    end

    test "одним оружием второй руки нет вовсе", %{ruleset: ruleset} do
      stats = Rules.compute(build(off_hand: nil), ruleset)

      assert stats.dual_wield == nil
      assert stats.off_hand == nil
      assert DualWield.off_hand_attacks(nil) == 0
    end
  end

  describe "выдача Рейнджера" do
    defp ranger(opts) do
      Build.new(
        race: :human,
        alignment: :true_neutral,
        levels: List.duplicate(:ranger, Keyword.get(opts, :levels, 1)),
        base_abilities: @abilities,
        gear:
          Gear.new(
            weapon: :katana,
            off_hand_weapon: :warhammer,
            worn: Keyword.get(opts, :worn, %{}),
            feats: @proficiencies ++ Keyword.get(opts, :feats, [])
          )
      )
    end

    # Класс выдаёт `Dual-wield` на 1-м уровне, и он даёт эффекты ОБОИХ фитов.
    test "рейнджер 1 бьётся как с Ambidexterity и Two-weapon fighting", %{ruleset: ruleset} do
      assert ranger([]) |> DualWield.of(ruleset) |> DualWield.penalty() == %{main: -4, off: -4}
    end

    # 🔴 Тот же эффект, а не второй: рейнджер, взявший фит слотом, прироста
    # дважды не получает («get all the benefits of having the … feats»).
    test "взятый слотом Two-weapon fighting второй раз не считается", %{ruleset: ruleset} do
      with_feat = ranger(feats: [:two_weapon_fighting, :ambidexterity])

      assert with_feat |> DualWield.of(ruleset) |> DualWield.penalty() == %{main: -4, off: -4}
    end

    @weight_gap {:missing_data, {:armor_weight_class, :dual_wield_feat}}

    # 🔴 ТАБЛИЧНЫЙ КЕЙС ЗАМЕРА AH1 (Dan, 30.08.2026) — девять баз доспеха и обе
    # руки, задача 3.141. Источник правила — `fandom:Dual-wield (feat)` (revid
    # 44233): «Rangers, when wearing light armor, get all the benefits … While
    # wearing medium or heavy armor they lose these benefits»; источник ГРАНИЦЫ
    # — сам замер: лист печатает тип брони словом, и он оказался сиальским,
    # а не ванильным (кольчужная рубаха, база 4, — СРЕДНЯЯ).
    #
    # Персонаж замера: Рейнджер 15, STR 10 / DEX 10, длинный меч +5 в главной.
    # ⚠️ Штраф брони на бросок атаки не влияет ничем (он идёт в шесть навыков),
    # поэтому ЛЮБОЕ изменение AB при смене одного лишь доспеха — это и есть
    # потеря бонусов, и посторонних причин у неё нет.
    defp measured_ranger(off_hand, armor) do
      Build.new(
        race: :human,
        alignment: :true_neutral,
        levels: List.duplicate(:ranger, 15),
        base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
        feats: %{1 => %{general: :siala_blade_proficiency}},
        gear:
          Gear.new(
            weapon: :longsword,
            weapon_attack: 5,
            off_hand_weapon: off_hand,
            off_hand_weapon_attack: 5,
            worn: %{armor: armor}
          )
      )
    end

    defp measured_ab(off_hand, armor, ruleset) do
      stats = Rules.compute(measured_ranger(off_hand, armor), ruleset)

      {stats.attack_bonus, stats.off_hand.attack_bonus}
    end

    # Лёгкая вторая рука: −2/−2 с бонусами, −4/−8 без них.
    test "кинжал во второй руке: 18/18 в лёгкой броне, 16/12 в средней и тяжёлой", %{
      ruleset: ruleset
    } do
      table = [
        {:none, {18, 18}, "типа нет вовсе"},
        {:padded, {18, 18}, "лёгкая"},
        {:leather, {18, 18}, "лёгкая"},
        {:studded_leather, {18, 18}, "лёгкая"},
        {:chain_shirt, {16, 12}, "средняя — и это САМАЯ дорогая строка замера"},
        {:chainmail, {16, 12}, "средняя"},
        {:splint_mail, {16, 12}, "тяжёлая"},
        {:half_plate, {16, 12}, "тяжёлая"},
        {:full_plate, {16, 12}, "тяжёлая"}
      ]

      for {armor, expected, note} <- table do
        assert measured_ab(:dagger, armor, ruleset) == expected, "#{armor} (#{note})"
      end
    end

    # Нелёгкая вторая рука: те же две ступени, сдвинутые на −2 обеим рукам.
    test "длинный меч во второй руке: 16/16 в лёгкой броне, 14/10 в средней и тяжёлой", %{
      ruleset: ruleset
    } do
      table = [
        {:none, {16, 16}},
        {:padded, {16, 16}},
        {:leather, {16, 16}},
        {:studded_leather, {16, 16}},
        {:chain_shirt, {14, 10}},
        {:chainmail, {14, 10}},
        {:splint_mail, {14, 10}},
        {:half_plate, {14, 10}},
        {:full_plate, {14, 10}}
      ]

      for {armor, expected} <- table do
        assert measured_ab(:longsword, armor, ruleset) == expected, "#{armor}"
      end
    end

    # 🔴 Падение РАЗНОЕ у рук — 2 главной и 6 второй, а не «6 обеим»: рейнджер
    # теряет `two_weapon_fighting` (2/2) и `ambidexterity` (0/4) разом.
    test "потеря стоит 2 главной руке и 6 второй", %{ruleset: ruleset} do
      {light_main, light_off} = measured_ab(:dagger, :studded_leather, ruleset)
      {heavy_main, heavy_off} = measured_ab(:dagger, :chain_shirt, ruleset)

      assert light_main - heavy_main == 2
      assert light_off - heavy_off == 6
    end

    # 🔴 И ЦЕНА БЕЗДЕЙСТВИЯ, замеренная до правки: у ванили класса брони не
    # знает никто, поэтому там по-прежнему 18/18 во всех девяти базах — ровно
    # то, что показывала Сиала до задачи 3.141. Это не забытая строка, а запрет
    # выдумывать: границу измерили на Сиале, а где та же линия у ванильных
    # правил, не выяснял никто (CLAUDE.md §3, железное правило 1).
    test "у ванили бонусы не теряются ни в одном доспехе — класс ей неизвестен", %{
      vanilla: vanilla
    } do
      for armor <- [:none, :studded_leather, :chain_shirt, :chainmail, :full_plate] do
        assert measured_ab(:dagger, armor, vanilla) == {18, 18}, "#{armor}"
        assert measured_ab(:longsword, armor, vanilla) == {16, 16}, "#{armor}"
      end
    end

    # 🔴 Оговорка живёт ровно там, где нет ответа, — и только там. Три
    # состояния, и различать их обязательно: «класса нет вовсе» (нулёвка),
    # «класс известен» и «слой про класс не сказал».
    test "оговорка: у Сиалы её нет нигде, у ванили — в каждом доспехе", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      for armor <- [:none, :leather, :chain_shirt, :full_plate] do
        refute @weight_gap in DualWield.gaps(ranger(worn: %{armor: armor}), ruleset), "#{armor}"
        assert @weight_gap in DualWield.gaps(ranger(worn: %{armor: armor}), vanilla), "#{armor}"
      end
    end

    # ⚠️ Доспеха нет вовсе — молчат ОБА: исключение «wearing medium or heavy
    # armor» не выполняется по факту, а не по незнанию.
    test "доспеха нет — молчат оба ruleset'а", %{ruleset: ruleset, vanilla: vanilla} do
      for rs <- [ruleset, vanilla] do
        refute @weight_gap in DualWield.gaps(ranger([]), rs)
      end

      assert ranger([]) |> DualWield.of(ruleset) |> DualWield.penalty() == %{main: -4, off: -4}
    end

    # ⚠️ Щит условие не задевает ни в одном ruleset'е — источник называет доспех
    # («medium or heavy armor»), и категория названа в данных именем.
    test "щит оговорки про броню не вызывает", %{ruleset: ruleset, vanilla: vanilla} do
      # Щит при втором оружии всё равно отказан, и это его собственный отказ;
      # проверяется здесь только то, что оговорку про броню он не поднимает.
      for rs <- [ruleset, vanilla] do
        refute @weight_gap in DualWield.gaps(ranger(worn: %{shield: :large}), rs)
      end
    end

    # ⚠️ Потеря относится к ВЫДАЧЕ, а не к фиту в слоте: рейнджер, взявший оба
    # фита сам, в латах их не теряет — «While wearing medium or heavy armor
    # they lose these benefits» сказано про `Dual-wield`, а не про них.
    test "взятые слотом фиты доспех не отбирает", %{ruleset: ruleset} do
      taken =
        ranger(worn: %{armor: :full_plate}, feats: [:two_weapon_fighting, :ambidexterity])

      assert taken |> DualWield.of(ruleset) |> DualWield.penalty() == %{main: -4, off: -4}

      # Положительный контроль: без взятых фитов та же броня их отбирает.
      assert ranger(worn: %{armor: :full_plate})
             |> DualWield.of(ruleset)
             |> DualWield.penalty() == %{main: -6, off: -10}
    end
  end

  describe "числа билда целиком" do
    # 🔴 Живой пример из запроса Dan: «К примеру катану и булаву во вторую
    # руку». Воин 20, сила 18 — БАБ 20 + 4 = 24 одной рукой.
    test "воин 20 с катаной и булавой: AB обеих рук", %{ruleset: ruleset} do
      alone = Rules.compute(build(off_hand: nil), ruleset)
      bare = Rules.compute(build(off_hand: :mace), ruleset)

      full =
        Rules.compute(
          build(off_hand: :mace, feats: [:two_weapon_fighting, :ambidexterity]),
          ruleset
        )

      assert alone.attack_bonus == 24
      assert alone.off_hand == nil

      # Булава — лёгкая для человека, поэтому без фитов −4/−8.
      assert bare.attack_bonus == 20
      assert bare.off_hand.attack_bonus == 16

      # С обоими фитами −2/−2.
      assert full.attack_bonus == 22
      assert full.off_hand.attack_bonus == 22
    end

    # ⚠️ Число ПРЕДМЕТА у каждой руки своё, и складывать их нельзя: игрок
    # вводит два усиления, и каждое действует только своей рукой.
    test "усиление каждой руки считается только своей руке", %{ruleset: ruleset} do
      build =
        Build.new(
          race: :human,
          levels: List.duplicate(:fighter, 20),
          base_abilities: @abilities,
          gear:
            Gear.new(
              weapon: :katana,
              weapon_attack: 5,
              off_hand_weapon: :mace,
              off_hand_weapon_attack: 2,
              feats: @proficiencies
            )
        )

      stats = Rules.compute(build, ruleset)

      assert stats.weapon_attack_bonus == 5
      assert stats.off_hand.weapon_attack_bonus == 2
      assert stats.attack_bonus == 25
      assert stats.off_hand.attack_bonus == 18
    end

    # 🔴 Кап атаки +20 у рук ОБЩИЙ по составу и РАЗНЫЙ по числу: расовый бонус
    # и бонус за тип оружия у них одни и те же, а усиление предмета — своё.
    # Значит одна рука может упереться там, где другая нет, и значок при этом
    # один: кап принадлежит СТАТУ, а не руке.
    test "вторая рука упирается в кап +20 отдельно от главной", %{ruleset: ruleset} do
      build =
        Build.new(
          race: :human,
          levels: List.duplicate(:fighter, 20),
          base_abilities: @abilities,
          gear:
            Gear.new(
              weapon: :katana,
              weapon_attack: 5,
              off_hand_weapon: :mace,
              off_hand_weapon_attack: 25,
              feats: @proficiencies
            )
        )

      stats = Rules.compute(build, ruleset)

      assert stats.attack_cap_clipped == 0
      assert stats.off_hand.attack_cap_clipped == -5
      assert stats.off_hand.attack_capped? == true
      assert :attack_bonus in stats.capped
    end

    # Разбор обязан сходиться со своим итогом: сумма слагаемых равна штрафу.
    test "разбор штрафа сходится со штрафом", %{ruleset: ruleset} do
      style =
        DualWield.of(
          build(off_hand: :mace, feats: [:two_weapon_fighting, :ambidexterity]),
          ruleset
        )

      assert Enum.reduce(style.terms, 0, &(&1.main + &2)) == style.penalty.main
      assert Enum.reduce(style.terms, 0, &(&1.off + &2)) == style.penalty.off

      assert Enum.map(style.terms, & &1.source) == [
               :base,
               {:feat, :two_weapon_fighting},
               {:feat, :ambidexterity},
               :light_off_hand
             ]
    end
  end

  describe "бонус за тип оружия по обеим рукам" do
    # 🔴 «Используя два разных оружия персонаж получает два разных бонуса»
    # (`Система оружия`, revid 20527). Обе руки считаются, и виды у них разные.
    #
    # ⚠️ ЗДЕСЬ СТОЯЛА ПАРА «катана + праща» с двумя ПОСЧИТАННЫМИ числами
    # (щитовой AC 9 и бонус атаки 9). С задачи 3.142 такого билда нет:
    # дальнобойное во вторую руку не идёт. Заодно выяснилось, что пара
    # с двумя посчитанными числами была достижима ТОЛЬКО через эту дыру —
    # у древкового оружия все восемь записей `large`, то есть двуручные,
    # и во вторую руку не попадали никогда. Живая пара поэтому такая:
    # клинок даёт щитовой AC, а молот — звуковой урон, получателя которому
    # мы не считаем (CLAUDE.md §9). Механика «две руки — два вида» на ней
    # видна целиком; положительный контроль на ДВА ПОСЧИТАННЫХ числа стоит
    # на синтетике ниже.
    test "два разных вида приходят от двух рук", %{ruleset: ruleset} do
      stats = Rules.compute(build(weapon: :katana, off_hand: :mace, levels: 41), ruleset)

      kinds =
        for entry <- stats.weapon_type_bonuses,
            do: {entry.weapon, entry.kind, entry.counted, entry.modelled?}

      assert kinds == [{:katana, :shield_ac, 9, true}, {:mace, :sonic_damage, nil, false}]
    end

    # 🔴 ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ НА СИНТЕТИКЕ, и он обязателен: на поставляемых
    # данных вторую руку могут занять только клинки, топоры и молоты, а
    # получатель есть лишь у клинков, — то есть два ПОСЧИТАННЫХ числа от двух
    # рук живыми данными больше не достигаются. Держать контроль на живой паре
    # значило бы не иметь его вовсе (урок 3.85: так за неделю сгорели пять
    # проверок подряд).
    #
    # ⚠️ Синтетика меняет ОДНУ вещь — вешает на короткий меч запись с другим
    # видом бонуса, — и ничего больше: правило складывания, потолки и уровень
    # остаются теми же.
    test "два посчитанных числа от двух рук — на синтетике", %{ruleset: ruleset} do
      blade = ruleset.weapon_type_bonuses.by_group[:blade]
      ranged = ruleset.weapon_type_bonuses.by_group[:ranged]

      synthetic =
        update_in(
          ruleset.weapon_type_bonuses.by_weapon,
          &Map.put(&1, :shortsword, ranged)
        )

      stats = Rules.compute(build(weapon: :katana, off_hand: :shortsword, levels: 41), synthetic)

      assert for(e <- stats.weapon_type_bonuses, do: {e.weapon, e.kind, e.counted}) == [
               {:katana, :shield_ac, 9},
               {:shortsword, :attack_bonus, 9}
             ]

      # Контроль самой синтетики: на нетронутых данных короткий меч даёт
      # то же, что и катана, и виды схлопываются в один.
      assert blade != ranged

      assert length(
               Rules.compute(build(weapon: :katana, off_hand: :shortsword, levels: 41), ruleset).weapon_type_bonuses
             ) == 1
    end

    # 🔴 Один и тот же вид из двух рук считается ОДИН раз — и это ПОДТВЕРЖДЕНО
    # владельцем 28.08.2026 (`GAME_CHECKS.md` AH2), дословно: «два клинка дают
    # +6 щитового ац, короче говоря, если в руках два оружия одного типа -
    # бонус не удваивается».
    #
    # ⚠️ Здесь стояло `assert {:assumed, {:weapon_type_bonus_both_hands, …}}`
    # с доводом «это ЧТЕНИЕ, источник молчит». Довод был верен ровно до ответа;
    # число при этом не сдвинулось ни на единицу — подтвердилось то, что
    # считалось, — и печатать «мы это предполагаем» про подтверждённое
    # запрещено так же прямо, как молчать про непосчитанное (CLAUDE.md §6).
    #
    # ⚠️ Положительный контроль на саму механику переехал на СИНТЕТИЧЕСКУЮ
    # запись (describe ниже). Держать его на живой нельзя: живая уже получила
    # отметку, и тест молча перестал бы что-либо проверять (урок задачи 3.85).
    test "один и тот же вид считается один раз и без оговорки", %{ruleset: ruleset} do
      stats = Rules.compute(build(weapon: :katana, off_hand: :shortsword, levels: 41), ruleset)

      assert [%{kind: :shield_ac, counted: 9}] = stats.weapon_type_bonuses
      refute {:assumed, {:weapon_type_bonus_both_hands, :shield_ac}} in stats.gaps

      # Положительный контроль другого рода, без которого «оговорки нет»
      # сошлось бы и на билде, у которого бонуса нет вовсе.
      assert Rules.compute(build(weapon: :katana, off_hand: nil, levels: 41), ruleset).ac_geared ==
               stats.ac_geared
    end
  end

  # ---------------------------------------------------------------------------
  # 🔴 ОТМЕТКА О ПОДТВЕРЖДЕНИИ — НА ЗАПИСИ, А НЕ ФЛАГОМ НА МЕХАНИЗМЕ.
  #
  # Правило CLAUDE.md §9: снимать признание можно только тем, что вернёт его
  # само. Отметка живёт в данных (`siala_41/systems.json` →
  # `bonuses_from_both_hands.same_kind_confirmed`), и снапшот, принёсший это
  # правило БЕЗ отметки, снова получает оговорку.
  #
  # ⚠️ Проверяется на СИНТЕТИЧЕСКОМ ruleset'е — копии живого со снятой
  # отметкой, — потому что живая запись отметку уже несёт: контроль на ней
  # проверял бы ровно ничего (задача 3.85, пять сгоревших контролей подряд).
  describe "подтверждение складывания — на записи, а не на механизме" do
    defp without_mark(ruleset) do
      put_in(ruleset.weapon_type_bonuses.both_hands.same_kind_confirmed, nil)
    end

    test "без отметки тот же билд снова получает оговорку", %{ruleset: ruleset} do
      build = build(weapon: :katana, off_hand: :shortsword, levels: 41)
      stats = Rules.compute(build, without_mark(ruleset))

      assert {:assumed, {:weapon_type_bonus_both_hands, :shield_ac}} in stats.gaps

      # ...и ЧИСЛО при этом то же самое: отметка снимает признание, а не меняет
      # расчёт. Если бы двинулось — правка была бы не про статус.
      # ⚠️ Сравниваются посчитанные величины, а не записи целиком: у записей
      # различается ровно один флаг — `both_hands_assumed?`, — и он и есть
      # предмет проверки, а не расхождение.
      counted = fn s -> for e <- s.weapon_type_bonuses, do: {e.weapon, e.kind, e.counted} end

      assert counted.(stats) == counted.(Rules.compute(build, ruleset))
      assert counted.(stats) == [{:katana, :shield_ac, 9}]
    end

    # ⚠️ И оговорка привязана к СТОЛКНОВЕНИЮ, а не к существованию записи:
    # у билда с двумя РАЗНЫМИ видами сталкиваться нечему, и без отметки тоже.
    test "разные виды оговорки не приносят даже без отметки", %{ruleset: ruleset} do
      stats =
        Rules.compute(build(weapon: :katana, off_hand: :sling, levels: 41), without_mark(ruleset))

      refute Enum.any?(stats.gaps, &match?({:assumed, {:weapon_type_bonus_both_hands, _}}, &1))
    end
  end
end
