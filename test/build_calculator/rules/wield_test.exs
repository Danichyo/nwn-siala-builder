defmodule BuildCalculator.Rules.WieldTest do
  @moduledoc """
  Три запрета по размеру — задача 3.43.

  🔴 **Хват — функция ДВУХ размеров**, и это единственное, что здесь надо
  держать в голове. `fandom:Two-handed weapon` (revid 64752): «a two-handed
  weapon is a weapon whose weapon size is one category larger than **its
  wielder**. (That is, a large weapon for most player characters, and a medium
  weapon for gnomes and halflings.)» Поэтому длинный меч у человека одноручный,
  а у Карлика двуручный, и одна колонка справочника ответить на это не может.

  Источники, по которым посчитаны все ожидания ниже:

    * **лестница размеров** — `fandom:Weapon size` (revid 59292), заголовки строк
      таблицы «Weapons by size and proficiency»: Tiny → Small → Medium → Large.
      Оттуда же окно: «A creature can wield any weapon up to one size larger than
      their own size and down to two sizes smaller than their own size. Other
      weapons cannot be wielded»;
    * **«нельзя вовсе» ≠ «двуручно»** — `fandom:Two-handed weapon`: «Weapons more
      than one size category larger than the wielder are **not considered
      two-handed weapons because they cannot be wielded at all**»;
    * **щит рядом с двуручным** — `fandom:Shield proficiency` (revid 54502):
      «Creatures may not simultaneously use a shield and a two-handed weapon»;
    * **башенный щит** — та же страница: «Tower shields additionally require that
      the wielder be medium-sized or larger. (In particular, gnomes and halflings
      may not use tower shields, even with this feat.)», и то же самое буллетом
      `Small stature` на собственных страницах `fandom:Gnome` и `fandom:Halfling`;
    * **размеры рас** — `vanilla/races.json` → `size` (задача 3.44): `small`
      у Карлика (`gnome`) и Гоблина (`halfling`), `medium` у остальных пяти;
    * **хват для обычного размера** — `Система оружия` Сиалы (revid 20527),
      колонка «Одно или двуручное», 38 записей из 47.

  🔴 **И всё это подтверждено замером Dan 16.08.2026** (`GAME_CHECKS.md`, R2b):
  у Карлика кинжал и короткий меч берутся со щитом, длинный меч — нет; башенный
  щит недоступен. Ниже это ровно первый describe.

  ⚠️ Ванильный ruleset получает те же правила: они ванильные, а не сиальские, —
  и это проверено отдельно, а не предположено.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear, GearWeapon, Wield, Worn}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @flat %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

  # Пять сиальских фитов владения разом: задача не про владение, а про размер,
  # и без них отказ пришёл бы не тот. ⚠️ На ванильном ruleset'е этих фитов нет
  # вовсе, и владение там не проверяется (`:unread`) — то есть тот же билд
  # годится обоим.
  @proficiencies [
    :siala_blade_proficiency,
    :siala_axe_proficiency,
    :siala_hammer_proficiency,
    :siala_polearm_proficiency,
    :siala_ranged_proficiency
  ]

  defp armed(race, weapon, worn \\ %{}) do
    Build.new(
      race: race,
      levels: [:fighter],
      base_abilities: @flat,
      gear: Gear.new(weapon: weapon, worn: worn, feats: @proficiencies)
    )
  end

  defp weapon_reasons(build, weapon, ruleset) do
    case Rules.validate_gear_weapon(build, weapon, ruleset) do
      :ok -> []
      {:error, reasons} -> reasons
    end
  end

  defp shield_reasons(build, ruleset) do
    for {_category, _item, reason} <- Rules.illegal_worn(build, ruleset), do: reason
  end

  # ---------------------------------------------------------------------------

  describe "замер R2b: Карлик, щит и три меча" do
    # 🔴 Табличный кейс замера, дословно. Кинжал `tiny`, короткий меч `small`,
    # длинный меч `medium`; Карлик `small`. Смещение по лестнице: −1, 0, +1 —
    # и только третье равно порогу двуручности.
    test "кинжал и короткий меч со щитом можно, длинный меч — нет", %{ruleset: ruleset} do
      table = [
        {:dagger, :one_handed, []},
        {:shortsword, :one_handed, []},
        {:longsword, :two_handed, [{:two_handed_weapon, :longsword}]}
      ]

      for {weapon, grip, expected} <- table do
        build = armed(:gnome, weapon, %{shield: :large})

        assert Wield.grip(build, weapon, ruleset) == grip,
               "#{weapon}: хват у Карлика посчитан не тот"

        assert shield_reasons(build, ruleset) == expected,
               "#{weapon}: щит у Карлика решён неверно"
      end
    end

    # 🔴 Отрицательный контроль и главная ловушка задачи: тот же длинный меч
    # у человека одноручный, и щит с ним берётся. Реализация, прочитавшая хват
    # из одной колонки `siala_grip`, зеленела бы на человеке и падала бы на
    # Карлике; реализация, считающая только по размерам, — наоборот.
    test "тот же длинный меч у человека одноручный, и щит с ним можно", %{ruleset: ruleset} do
      build = armed(:human, :longsword, %{shield: :large})

      assert Wield.grip(build, :longsword, ruleset) == :one_handed
      assert shield_reasons(build, ruleset) == []
    end

    # И вторая половина замера: башенный щит Карлику недоступен.
    test "башенный щит Карлику недоступен", %{ruleset: ruleset} do
      build = armed(:gnome, nil, %{shield: :tower})

      assert shield_reasons(build, ruleset) == [{:not_usable_by_race, :gnome}]
    end
  end

  describe "малая раса и башенный щит" do
    # ⚠️ Обе малые расы, а не одна: запрет стоит полем у каждой, и проверка
    # по одной не отличила бы правило от совпадения.
    test "обе малые расы башенный щит не носят, остальные пять носят", %{ruleset: ruleset} do
      for race <- [:gnome, :halfling] do
        assert shield_reasons(armed(race, nil, %{shield: :tower}), ruleset) ==
                 [{:not_usable_by_race, race}]
      end

      for race <- [:human, :dwarf, :elf, :half_elf, :half_orc] do
        assert shield_reasons(armed(race, nil, %{shield: :tower}), ruleset) == [],
               "#{race} среднего размера и башенный щит носить может"
      end
    end

    # 🔴 Живая ошибка, которую задача чинит: до неё башенный щит Карлику
    # ПРЕДЛАГАЛСЯ вместе с +3 AC и −10 к навыкам, которых игра не даёт.
    # Проверяются ОБЕ половины — числа обязаны перестать приезжать.
    test "нелегальный башенный щит не даёт ни базы AC, ни штрафа к навыкам", %{
      ruleset: ruleset
    } do
      refused = armed(:gnome, nil, %{shield: :tower})
      allowed = armed(:human, nil, %{shield: :tower})

      assert Worn.base_ac(refused, ruleset) == %{}
      assert Worn.armor_check_penalty(refused, ruleset) == 0

      # Положительный контроль той же парой: у среднего персонажа обе величины
      # на месте, значит выше поймана именно легальность, а не сломанное чтение.
      assert Worn.base_ac(allowed, ruleset) == %{shield: 3}
      assert Worn.armor_check_penalty(allowed, ruleset) == -10
    end

    # И то же самое числами билда, а не вызовами модуля: щитовой AC не вырос,
    # значение навыка со штрафом не упало. ⚠️ Ранги Hide куплены — у навыка без
    # рангов значения нет вовсе, и сравнивать было бы нечего.
    test "у билда Карлика с башенным щитом AC и Hide не двигаются", %{ruleset: ruleset} do
      hidden = fn worn ->
        %Build{} = base = armed(:gnome, nil, worn)
        %Build{base | skills: %{1 => %{hide: 4}}}
      end

      bare = Rules.compute(hidden.(%{}), ruleset)
      towered = Rules.compute(hidden.(%{shield: :tower}), ruleset)

      hide = fn stats -> stats.skill_values[:hide].total end

      assert towered.ac_geared == bare.ac_geared
      assert hide.(towered) == hide.(bare)

      # Положительный контроль: малый щит Карлику доступен, и он-то приезжает —
      # +1 к AC и −1 к скрытности.
      small = Rules.compute(hidden.(%{shield: :small}), ruleset)

      assert small.ac_geared == bare.ac_geared + 1
      assert hide.(small) == hide.(bare) - 1
    end

    test "малый и средний щит Карлику доступны", %{ruleset: ruleset} do
      for size <- [:small, :large] do
        assert shield_reasons(armed(:gnome, nil, %{shield: size}), ruleset) == []
      end
    end
  end

  describe "малая раса и большое оружие — отказ, а не «двуручно»" do
    # 🔴 «Weapons more than one size category larger than the wielder are **not
    # considered two-handed weapons** because they cannot be wielded at all».
    # Разница видна ровно в двух местах: у оружия появляется причина отказа,
    # а у щита рядом — НЕ появляется, потому что оружия в руках нет.
    test "великий меч и алебарда Карлику недоступны вовсе", %{ruleset: ruleset} do
      for weapon <- [:greatsword, :halberd] do
        build = armed(:gnome, weapon, %{shield: :large})

        assert weapon_reasons(build, weapon, ruleset) == [{:weapon_too_large, :gnome}],
               "#{weapon}: отказ по размеру не пришёл"

        # ⚠️ И это НЕ «двуручно»: хват не считается вовсе, а щит рядом остаётся
        # легальным — оружия, которое занимало бы вторую руку, у персонажа нет.
        assert Wield.grip(build, weapon, ruleset) == nil
        assert shield_reasons(build, ruleset) == []
      end
    end

    # Отрицательный контроль: у человека то же оружие законно и ДВУРУЧНО, то
    # есть щит рядом с ним отбит — второй формой отказа, не первой.
    test "у человека то же оружие законно и двуручно", %{ruleset: ruleset} do
      for weapon <- [:greatsword, :halberd] do
        build = armed(:human, weapon, %{shield: :large})

        assert weapon_reasons(build, weapon, ruleset) == []
        assert Wield.grip(build, weapon, ruleset) == :two_handed
        assert shield_reasons(build, ruleset) == [{:two_handed_weapon, weapon}]
      end
    end

    # ⚠️ Недоступное не прячется, а показывается с причиной (CLAUDE.md §6):
    # в списке блока «Вещи» слишком большое оружие обязано быть, с отказом.
    test "слишком большое оружие остаётся в списке выбора, с причиной", %{ruleset: ruleset} do
      candidates = Rules.gear_weapon_candidates(armed(:gnome, nil), ruleset)
      greatsword = Enum.find(candidates, &(&1.id == :greatsword))

      assert greatsword.reason == {:weapon_too_large, :gnome}
    end

    # 🔴 Размер решается ПЕРЕД владением, и это не косметика: фитом он не
    # лечится, а «нужен фит владения клинковым» было бы обещанием, которого мы
    # сдержать не можем.
    test "у Карлика без фитов владения великий меч отказан размером, а не фитом", %{
      ruleset: ruleset
    } do
      bare =
        Build.new(
          race: :gnome,
          levels: [:fighter],
          base_abilities: @flat,
          gear: Gear.new(weapon: :greatsword)
        )

      assert weapon_reasons(bare, :greatsword, ruleset) == [{:weapon_too_large, :gnome}]

      # Положительный контроль: оружие ПО РУКЕ у того же билда отказано именно
      # владением — значит проверка владения на месте и просто стоит второй.
      assert weapon_reasons(bare, :shortsword, ruleset) ==
               [{:requires_feat, :siala_blade_proficiency}]
    end
  end

  describe "двуручное и щит: составление двух утверждений" do
    # 🔴 Правило может сделать хват ТЯЖЕЛЕЕ и никогда легче. Лёгкий арбалет —
    # `small`, то есть для Карлика он тот же размер, что и владелец, и вывод
    # по размерам дал бы одноручный. Колонка Сиалы говорит «двуручное», и она
    # выигрывает: правило размера объясняет, что ДЕЛАЕТ оружие двуручным,
    # а не что всё остальное одноручно.
    test "объявленное двуручным не становится одноручным у малой расы", %{ruleset: ruleset} do
      for race <- [:gnome, :human] do
        build = armed(race, :light_crossbow, %{shield: :large})

        assert Wield.grip(build, :light_crossbow, ruleset) == :two_handed
        assert shield_reasons(build, ruleset) == [{:two_handed_weapon, :light_crossbow}]
      end
    end

    # Двустороннее оружие — третье значение хвата, и оно тоже занимает обе руки:
    # «Even though these are large weapons and require two hands to wield…»
    # (`fandom:Double-sided weapon`, revid 68931).
    test "двустороннее оружие щит тоже отбивает", %{ruleset: ruleset} do
      build = armed(:human, :two_bladed_sword, %{shield: :small})

      assert Wield.grip(build, :two_bladed_sword, ruleset) == :double_sided
      assert shield_reasons(build, ruleset) == [{:two_handed_weapon, :two_bladed_sword}]
    end

    # ⚠️ Отбивается ДЕРЖИМОЕ оружие, а не записанное: снятый фит владения
    # отбирает оружие, и вместе с ним отпадает его претензия на вторую руку.
    # Иначе один отказ порождал бы второй на пустом месте.
    test "оружие, которое держать нельзя, вторую руку не занимает", %{ruleset: ruleset} do
      unarmed =
        Build.new(
          race: :human,
          levels: [:fighter],
          base_abilities: @flat,
          gear: Gear.new(weapon: :greatsword, worn: %{shield: :large})
        )

      assert Rules.illegal_gear_weapon(unarmed, ruleset) ==
               [{:greatsword, {:requires_feat, :siala_blade_proficiency}}]

      assert shield_reasons(unarmed, ruleset) == []
    end

    # Доспех вторую руку не занимает — свойство КАТЕГОРИИ, и оно объявлено
    # в данных, а не выведено из имени.
    test "доспех рядом с двуручным остаётся на месте", %{ruleset: ruleset} do
      build = armed(:human, :greatsword, %{armor: :full_plate, shield: :large})

      assert shield_reasons(build, ruleset) == [{:two_handed_weapon, :greatsword}]
      assert Worn.base_ac(build, ruleset) == %{armor: 8}
      assert Worn.armor_check_penalty(build, ruleset) == -8
    end

    # 🔴 Все причины сразу, а не первая: Карлик с длинным мечом и башенным
    # щитом нарушает два независимых правила, и оба обязаны быть названы.
    test "два независимых отказа одному щиту приходят оба", %{ruleset: ruleset} do
      build = armed(:gnome, :longsword, %{shield: :tower})

      assert Enum.sort(shield_reasons(build, ruleset)) ==
               Enum.sort([{:not_usable_by_race, :gnome}, {:two_handed_weapon, :longsword}])
    end
  end

  describe "ловушки задачи 3.41, которые ломать нельзя" do
    @monk5 %{@flat | wis: 14}

    defp monk(race, gear_fields) do
      Build.new(
        race: race,
        levels: List.duplicate(:monk, 5),
        base_abilities: @monk5,
        gear: Gear.new(gear_fields)
      )
    end

    defp own(stats), do: for(term <- stats.ac_own_terms_geared, do: {term.id, term.ac})

    # 🔴 Щит, который носить нельзя, бонусы монаха НЕ отключает: в игре его
    # на персонаже нет вовсе. Тот же башенный щит на человеке — отключает.
    #
    # ⚠️ До задачи 3.143 (30.08.2026) у Карлика в `refused` был ещё расовый
    # терм `small_stature` (+1 за размер, никак не связан с монашеским
    # AC-условием) — applied по обрезанной цитате, теперь not_modelled, своего
    # терма не даёт вовсе.
    test "нелегальный щит бонусов монаха не отключает, легальный отключает", %{
      ruleset: ruleset
    } do
      refused = Rules.compute(monk(:gnome, worn: %{shield: :tower}), ruleset)
      allowed = Rules.compute(monk(:human, worn: %{shield: :tower}), ruleset)

      assert own(refused) == [monk_ac_bonus: 2, monk: 1]
      assert own(allowed) == []
    end

    # И отрицательный контроль той же пары: щит, который Карлику МОЖНО,
    # бонусы отключает — то есть выше сработала легальность, а не раса.
    #
    # ⚠️ До задачи 3.143 (30.08.2026) сравнивалось с `[small_stature: 1]` —
    # расовый терм пережил бы отключение монашеского AC, потому что он не
    # монашеский вовсе. `small_stature` стал not_modelled и своего терма
    # больше не даёт, поэтому демонстрация теперь идёт явным контрастом
    # с безщитовым состоянием, а не остаточным термом.
    test "малый щит Карлику бонусы монаха всё-таки ломает", %{ruleset: ruleset} do
      bare = Rules.compute(monk(:gnome, worn: %{}), ruleset)
      stats = Rules.compute(monk(:gnome, worn: %{shield: :small}), ruleset)

      assert own(bare) == [monk_ac_bonus: 2, monk: 1]
      assert own(stats) == []
    end
  end

  describe "ванильный ruleset получает те же правила" do
    # ⚠️ Правила ванильные (`fandom:Gnome`, `Halfling`, `Two-handed weapon`),
    # а не сиальские, поэтому проверяются на обоих ruleset'ах, а не на одном.
    test "три запрета работают и на vanilla", %{vanilla: vanilla} do
      gnome = armed(:gnome, :longsword, %{shield: :large})

      assert Wield.grip(gnome, :longsword, vanilla) == :two_handed
      assert shield_reasons(gnome, vanilla) == [{:two_handed_weapon, :longsword}]

      assert shield_reasons(armed(:gnome, nil, %{shield: :tower}), vanilla) ==
               [{:not_usable_by_race, :gnome}]

      assert weapon_reasons(armed(:gnome, :greatsword), :greatsword, vanilla) ==
               [{:weapon_too_large, :gnome}]

      assert shield_reasons(armed(:human, :longsword, %{shield: :large}), vanilla) == []
    end

    test "лестница размеров одна и та же у обоих", %{ruleset: ruleset, vanilla: vanilla} do
      assert Wield.rules(ruleset) == Wield.rules(vanilla)
      assert Wield.known?(ruleset) and Wield.known?(vanilla)
    end
  end

  # ---------------------------------------------------------------------------
  # ЛЁГКОЕ ОРУЖИЕ — второе предложение того же абзаца источника (задача 3.132).
  #
  # 🔴 До 28.08.2026 правило лежало в `weapons.json` ПРОЗОЙ (`light_when`)
  # и не читалось никем — пятый случай формы «проза в файле данных правилом
  # не является, пока её кто-нибудь не читает» (CLAUDE.md §9). Читателя ему дал
  # штраф боя двумя оружиями: лёгкая вторая рука снимает по 2 с обеих.
  #
  # Источник — `fandom:Weapon size` (revid 59292), тот же абзац, что и у хвата:
  # «A melee weapon at least one size smaller than the wielder is considered
  # a light weapon».
  describe "лёгкое оружие" do
    test "лёгкость — функция ДВУХ размеров, как и хват", %{ruleset: ruleset} do
      human = armed(:human, :dagger)
      gnome = armed(:gnome, :dagger)

      # {оружие, размер, человек (medium), Карлик (small)}
      table = [
        {:dagger, "tiny", true, true},
        {:kukri, "tiny", true, true},
        {:shortsword, "small", true, false},
        {:mace, "small", true, false},
        {:kama, "small", true, false},
        {:longsword, "medium", false, false},
        {:katana, "medium", false, false},
        {:warhammer, "medium", false, false},
        {:greatsword, "large", false, false}
      ]

      for {weapon, size, for_human, for_gnome} <- table do
        assert Wield.light?(human, weapon, ruleset) == for_human, "#{weapon} (#{size}), человек"
        assert Wield.light?(gnome, weapon, ruleset) == for_gnome, "#{weapon} (#{size}), Карлик"
      end
    end

    # ⚠️ «A **MELEE** weapon …» — источник про дальнобойное не утверждает
    # ничего, и расширять предложение за его собственные слова нельзя: ровно
    # так задача 3.122 применила исключение `spell_focus` шире, чем сказано.
    # Все четыре — размера, при котором по одному только размеру они были бы
    # лёгкими у человека.
    test "дальнобойное лёгким не считается, каким бы мелким ни было", %{ruleset: ruleset} do
      human = armed(:human, :dagger)

      for weapon <- [:sling, :throwing_axe, :dart, :shuriken] do
        assert Wield.light?(human, weapon, ruleset) == false, "#{weapon}"
      end
    end

    # `nil` — «сказать нечем», и это три разных состояния с одним ответом,
    # ровно как у `grip/3`.
    test "нечем сказать: нет размера, нет расы, нет лестницы", %{ruleset: ruleset} do
      assert Wield.light?(armed(:human, :dagger), :unarmed_strike, ruleset) == nil

      raceless = Build.new(levels: [:fighter], base_abilities: @flat)
      assert Wield.light?(raceless, :dagger, ruleset) == nil

      assert Wield.light?(armed(:human, :dagger), :dagger, %{}) == nil
    end

    test "правило одно и то же на обоих ruleset'ах", %{ruleset: ruleset, vanilla: vanilla} do
      for weapon <- [:dagger, :shortsword, :longsword, :sling] do
        assert Wield.light?(armed(:human, weapon), weapon, ruleset) ==
                 Wield.light?(armed(:human, weapon), weapon, vanilla),
               "#{weapon}"
      end
    end
  end

  describe "чего мы не знаем — и говорим об этом" do
    # ⚠️ Рукопашный удар — единственная запись справочника, у которой нет ни
    # хвата (Сиала его в таблицу не внесла), ни размера (Fandom не называет).
    # Значит двуручность из неё не выводится ничем, и щит рядом считается
    # как есть — с оговоркой, а не молча.
    test "оружие без хвата и без размера даёт оговорку рядом со щитом", %{ruleset: ruleset} do
      build = armed(:human, :unarmed_strike, %{shield: :large})

      assert Wield.grip(build, :unarmed_strike, ruleset) == nil
      assert shield_reasons(build, ruleset) == []

      assert {:missing_data, {:weapon_grip, :unarmed_strike}} in Rules.compute(build, ruleset).gaps

      # ⚠️ Область оговорки узкая: без щита вопрос не возникает вовсе, и
      # печатать её было бы шумом.
      refute {:missing_data, {:weapon_grip, :unarmed_strike}} in Rules.compute(
               armed(:human, :unarmed_strike),
               ruleset
             ).gaps
    end

    # Билд без расы: размер владельца неизвестен, поэтому правило размера
    # молчит — но объявленный хват работает, и щит рядом с двуручным отбит.
    test "без расы работает объявленный хват и не работает вывод по размерам", %{
      ruleset: ruleset
    } do
      raceless =
        Build.new(
          levels: [:fighter],
          base_abilities: @flat,
          gear: Gear.new(weapon: :longsword, worn: %{shield: :tower}, feats: @proficiencies)
        )

      assert Wield.wielder_size(raceless, ruleset) == nil
      assert Wield.grip(raceless, :longsword, ruleset) == :one_handed
      assert shield_reasons(raceless, ruleset) == []
    end

    # Снапшот без лестницы: ни один вопрос не отвечается «можно» молча —
    # ruleset говорит об этом гэпом. ⚠️ Синтетический ruleset, потому что оба
    # поставляемых лестницу несут: форма живая, а данных под неё сегодня нет.
    test "ruleset без лестницы отвечает nil и называет пробел", %{ruleset: ruleset} do
      blind = %{ruleset | wield: %{ruleset.wield | size_order: []}}
      build = armed(:gnome, :greatsword, %{shield: :tower})

      refute Wield.known?(blind)

      # Великий меч Карлику становится «можно»: запрет по размеру посчитать
      # нечем, и правило молчит вместо того, чтобы угадывать.
      assert Wield.refusal(build, :greatsword, blind) == nil

      # ⚠️ А объявленная колонка работает по-прежнему — она значение, а не
      # вывод: щит рядом с великим мечом отбит и здесь. Пропадает ровно то,
      # что считалось по лестнице, и ровно у той расы, ради которой она нужна:
      # у длинного меча (колонка говорит «одноручное») Карлик щит сохраняет.
      assert Wield.grip(build, :greatsword, blind) == :two_handed
      assert {:two_handed_weapon, :greatsword} in shield_reasons(build, blind)
      assert shield_reasons(armed(:gnome, :longsword, %{shield: :large}), blind) == []

      # ⚠️ Расовый запрет при этом остаётся: он полем, а не выводом по размерам.
      assert {:not_usable_by_race, :gnome} in shield_reasons(build, blind)
    end
  end

  describe "метательное оружие вторую руку не занимает (замер R5)" do
    # 🔴 **ЗАМЕР Dan 16.08.2026**, кейс R5: «дротик — щит остался». До него
    # колонка Сиалы («двуручное/метательное») читалась первым словом буквально,
    # и мы отбирали щит у КАЖДОГО метателя — на обоих ruleset'ах, у любой расы.
    #
    # ⚠️ Граница проходит по `thrown`, а не по `ranged`: у метательного
    # «двуручное» описывает БРОСОК, у стрелкового — настоящие две руки.
    # Без колонки короткий лук и лёгкий арбалет стали бы одноручными по размеру
    # (`medium` и `small` против `medium` владельца), поэтому её нельзя просто
    # перестать читать для всего дальнобойного.
    test "все четыре метательных держат щит, все четыре стрелковых — нет", %{
      ruleset: ruleset
    } do
      for weapon <- [:dart, :shuriken, :sling, :throwing_axe] do
        refute Wield.both_hands?(armed(:human, weapon), weapon, ruleset),
               "#{weapon}: метательное, вторую руку занимать не должно"
      end

      for weapon <- [:longbow, :shortbow, :light_crossbow, :heavy_crossbow] do
        assert Wield.both_hands?(armed(:human, weapon), weapon, ruleset),
               "#{weapon}: стрелковое, обе руки"
      end
    end

    # ⚠️ Ошибка была НЕ про малую расу — она была общая. Половина кейса,
    # без которой правку легко «уточнить» до расовой.
    #
    # ⚠️ Стрелковое здесь КОРОТКИЙ лук, а не длинный, и это не придирка:
    # длинный `large`, Карлик `small` — оружие на ДВЕ категории крупнее,
    # то есть его не взять вовсе, и `both_hands?` вернул бы `false`
    # по совершенно другой причине. Кейс проверял бы не то.
    test "у Карлика ровно то же самое", %{ruleset: ruleset} do
      refute Wield.both_hands?(armed(:gnome, :dart), :dart, ruleset)
      assert Wield.both_hands?(armed(:gnome, :shortbow), :shortbow, ruleset)
    end

    # ⚠️ Свойство приходит ИЗ ДАННЫХ. Снапшот, который его не объявляет,
    # обязан вернуться к прежнему чтению — хват решает один, — а не молча
    # освободить руку всем.
    test "снапшот без правила читает хват по-старому", %{ruleset: ruleset} do
      without = update_in(ruleset.wield, &Map.put(&1, :off_hand_free_when, nil))

      assert Wield.both_hands?(armed(:human, :dart), :dart, without)
    end
  end

  # ---------------------------------------------------------------------------
  # КАКАЯ РУКА, а не сколько рук — задача 3.142, замер `GAME_CHECKS.md` AI2.
  #
  # `fandom:Ranged weapon` (revid 70660): «No ranged weapon may be wielded in
  # the off-hand slot, nor can any weapon be wielded in the off-hand when
  # a ranged weapon is in the main hand».
  #
  # 🔴 Правило ключуется СВОЙСТВОМ оружия, а не размером, и потому не зависит
  # от владельца: у Карлика и у человека ответ один. Это и отличает его от всего
  # остального в этом модуле.
  describe "запрет второй руки по свойству оружия" do
    test "все восемь дальнобойных заперты, ближнее — нет", %{ruleset: ruleset} do
      barred =
        for {id, weapon} <- Enum.sort(ruleset.weapons),
            Wield.barred_from_off_hand?(id, ruleset),
            do: {id, weapon.ranged?}

      assert barred == [
               dart: true,
               heavy_crossbow: true,
               light_crossbow: true,
               longbow: true,
               shortbow: true,
               shuriken: true,
               sling: true,
               throwing_axe: true
             ]

      # Контроль: ближнее оружие правило не трогает — ни лёгкое, ни двуручное.
      for weapon <- [:dagger, :katana, :greatsword, :unarmed_strike] do
        refute Wield.barred_from_off_hand?(weapon, ruleset), "#{weapon}"
      end
    end

    # ⚠️ Ответ НЕ зависит от владельца, в отличие от хвата и лёгкости. Проверено
    # обеими играбельными величинами размера: у Карлика праща по хвату
    # одноручная ровно как у человека, а запрет всё равно стоит.
    test "раса на ответ не влияет — это свойство оружия, а не пары", %{ruleset: ruleset} do
      assert Wield.barred_from_off_hand?(:sling, ruleset)
      assert Wield.grip(armed(:human, :sling), :sling, ruleset) == :one_handed
      assert Wield.grip(armed(:gnome, :sling), :sling, ruleset) == :one_handed
    end

    # 🔴 Вторая половина того же предложения, и она про ГЛАВНУЮ руку. Отдельная
    # функция, потому что отдельный вопрос: праща и сама во вторую руку не идёт,
    # и второго оружия рядом не оставляет — при том что рук занимает одну.
    test "дальнобойное в главной держит из второй руки оружие", %{ruleset: ruleset} do
      assert Wield.bars_from_off_hand?(:sling, ruleset, :weapon)
      assert Wield.bars_from_off_hand?(:longbow, ruleset, :weapon)
      refute Wield.bars_from_off_hand?(:katana, ruleset, :weapon)
    end

    # 🔴 А ЩИТ — НЕТ, и это не пропуск проверки, а слово источника: у соседнего
    # правила про двуручное оружие та же вики пишет «anything in the off-hand
    # slot», у этого — «any **weapon**». Замер Dan подтвердил разницу дословно:
    # «Но можно взять щит».
    #
    # ⚠️ Проверяется ДВУМЯ утверждениями сразу: занятия `:worn` нет в списке
    # ядра (значит объявить его в снапшоте нельзя — сборка упадёт), и сама
    # функция отвечает на него `false`.
    test "щит правило не трогает, и объявить его нельзя", %{ruleset: ruleset} do
      assert Wield.off_hand_occupants() == [:weapon]
      refute :worn in Wield.off_hand_occupants()
      refute Wield.bars_from_off_hand?(:sling, ruleset, :worn)
    end

    # ⚠️ Правило приходит ИЗ ДАННЫХ. Снапшот, который его не объявляет, обязан
    # вернуться к прежнему чтению — вторую руку решает один хват, — а не нести
    # запрет, зашитый в коде.
    test "снапшот без правила не запрещает ничего", %{ruleset: ruleset} do
      without = update_in(ruleset.wield, &Map.put(&1, :off_hand, nil))

      refute Wield.barred_from_off_hand?(:sling, without)
      refute Wield.bars_from_off_hand?(:sling, without, :weapon)

      # И тем же чтением — до самого отказа: без правила праща во вторую руку
      # возвращается, как это и было до 30.08.2026.
      armed =
        Build.new(
          race: :human,
          levels: [:fighter],
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          gear: Gear.new(feats: [:siala_ranged_proficiency])
        )

      assert GearWeapon.validate(armed, :sling, without, :off) == :ok

      assert GearWeapon.validate(armed, :sling, ruleset, :off) ==
               {:error, [{:ranged_in_off_hand, :sling}]}
    end

    # ⚠️ Половины ДВЕ, и снапшот вправе объявить одну без другой: они читаются
    # разными полями и разными функциями. Синтетика — единственный способ это
    # проверить, живые данные объявляют обе.
    test "половины правила независимы", %{ruleset: ruleset} do
      only_off_hand = update_in(ruleset.wield.off_hand, &Map.put(&1, :bars, MapSet.new()))
      only_main_hand = update_in(ruleset.wield.off_hand, &Map.put(&1, :barred?, false))

      assert Wield.barred_from_off_hand?(:sling, only_off_hand)
      refute Wield.bars_from_off_hand?(:sling, only_off_hand, :weapon)

      refute Wield.barred_from_off_hand?(:sling, only_main_hand)
      assert Wield.bars_from_off_hand?(:sling, only_main_hand, :weapon)
    end
  end

  describe "данные: лестница и пороги прочитаны, а не назначены" do
    # ⚠️ Проверяется у ЯДРА через ruleset, а не чтением JSON: смысл в том, что
    # значение доезжает до расчёта.
    test "четыре ступени в порядке страницы, оба порога и оба имени хвата", %{
      ruleset: ruleset
    } do
      rules = Wield.rules(ruleset)

      assert rules.size_order == [:tiny, :small, :medium, :large]
      assert rules.grip_by_step == %{1 => :two_handed}
      assert rules.grip_otherwise == :one_handed
      assert rules.wieldable_to == 1
      assert rules.wieldable_from == -2
      assert rules.stated_grip_size == :medium

      assert rules.both_hands_grips |> MapSet.to_list() |> Enum.sort() ==
               [:double_sided, :two_handed]
    end

    # Размер знает каждая раса, и ровно две из семи малые — тот же счёт, что
    # у `Small stature` на своей странице.
    test "две малые расы из семи", %{ruleset: ruleset} do
      by_size = Enum.group_by(Map.values(ruleset.races), & &1.size, & &1.id)

      assert Enum.sort(by_size[:small]) == [:gnome, :halfling]
      assert length(by_size[:medium]) == 5
      assert map_size(ruleset.races) == 7
    end

    # ⚠️ Расовое поле и правило размеров — ДВА независимых чтения одного факта,
    # и загрузчик роняет сборку на расхождении. Здесь то же сравнение как тест:
    # запрет большого оружия стоит ровно у тех рас, которым правило что-то
    # запрещает.
    test "флаг расы и правило размеров говорят одно и то же", %{ruleset: ruleset} do
      for {id, race} <- ruleset.races do
        build = Build.new(race: id, levels: [:fighter], base_abilities: @flat)

        refused? =
          Enum.any?(ruleset.weapons, fn {weapon_id, _weapon} ->
            Wield.refusal(build, weapon_id, ruleset) != nil
          end)

        assert refused? == MapSet.member?(race.restrictions, :cannot_use_large_weapons),
               "#{id}: поле расы и правило размеров разошлись"
      end
    end
  end
end
