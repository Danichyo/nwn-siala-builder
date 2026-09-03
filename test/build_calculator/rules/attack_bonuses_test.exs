defmodule BuildCalculator.Rules.AttackBonusesTest do
  @moduledoc """
  Прибавки к БРОСКУ АТАКИ от фитов, классов, навыков и рас — задача 1.12b.

  До неё `Rules.compute/2` складывал AB из базы, модификатора характеристики,
  прибавки от вещей и расового бонуса Сиалы — и молчал про фиты и классовые
  умения совсем: ни числа, ни гэпа. Воин 41-го уровня с `Epic prowess`
  показывал AB на единицу меньше, чем даёт игра, и не говорил, что чего-то не
  хватает. `Epic prowess` при этом назван в CLAUDE.md §9 примером «фита первого
  вида: плоская прибавка, тривиально».

  ## Главный вывод разведки — прибавки к атаке почти все УСЛОВНЫЕ

  Применяемых записей во всём корпусе было **две**: `Epic prowess` и размерный
  модификатор мелких рас. Против четырнадцати у сейвов. Поэтому здесь тестов
  про НЕпосчитанное больше, чем про посчитанное, — и это не перекос, а форма
  предмета: у атаки нормальный случай это «+1 выбранным оружием», «+1 против
  орков», «−5 в режиме мощной атаки», «+3 раз в день».

  ⚠️ **С задачи 3.5 (часть B) применяемых пять**: три записи «выбранным оружием»
  (`Weapon focus`, `Epic weapon focus`, колонка Мастера оружия) стали считаться,
  потому что оружие в руках теперь часть билда (`Rules.GearWeapon`). Условность
  при этом не исчезла, а стала проверяемой: прибавка есть с тем оружием, что
  названо, и нет с другим.

  ⚠️ **И это тоже устарело, не будучи переоткрытым.** Задача 3.101 (25.08.2026)
  добавила `Enchant arrow` и `good_aim` (стало 7), задача 3.132 (28.08.2026)
  перевела три записи боя двумя оружиями из `unmodelled` в `counted_elsewhere`
  (на счёт `applied` не повлияло). 🔴 **Задача 3.143 (30.08.2026) сняла именно
  тот размерный модификатор, с которого этот раздел начинается** («Epic prowess
  и размерный модификатор мелких рас»): его цитата была обрезана перед условием
  «когда противник крупнее персонажа» (`fandom:Small stature`), и он стал
  `not_modelled`. Сегодня `applied` — **шесть**: `Epic prowess`, `Weapon focus`,
  `Epic weapon focus`, колонка Мастера оружия, `Enchant arrow`, `good_aim`.
  `Epic prowess` — единственная запись без всякого условия.

  Источники, по которым здесь считаются ожидания — все дословно в
  `priv/rules/vanilla/feat_attack_bonuses.json`:

    * `fandom:Epic prowess` (revid 68036) — «gains a +1 bonus to all attacks»,
      без единой оговорки;
    * `fandom:Gnome` (revid 65710) и `fandom:Halfling` (revid 71190) — «+1 size
      modifier to attack rolls» у обеих рас дословно одинаково. ⚠️ Страница
      самого фита `Small stature` (revid 65303) числа НЕ называет и добавляет
      условие «when dealing with larger creatures» — расхождение разобрано
      в `_sweep.conflict_found` разметки;
    * `fandom:Weapon master` (revid 71587) — колонка «AB bonus» таблицы класса:
      +1 с 5-го уровня класса, дальше +1 на 13/16/19/22/25/28, итого +7;
    * `fandom:Weapon focus` (revid 70066) «+1 attack bonus with it» и
      `fandom:Epic weapon focus` (revid 42299) «+2 bonus to all attack rolls
      with the chosen weapon» — ⚠️ с задачи 3.5 (часть B) оба СЧИТАЮТСЯ, когда
      в руках то самое оружие. До неё не считались вовсе, довод — в
      `_weapon_decision`, и он оставлен в данных целиком: предпосылка («что
      в руках, записать нечем») перестала быть верной, а не довод — неверным;
    * `fandom:Expertise` (revid 50170) — «-5 penalty to attack rolls», боевой
      режим и первое отрицательное число в этом семействе файлов.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{AttackBonuses, Build, FeatSlots, Gear}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @flat %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

  defp build(levels, fields \\ []) do
    Build.new([levels: levels, base_abilities: @flat, race: :human] ++ fields)
  end

  # Потолок опускается в копии ruleset'а: настоящий +20 недостижим (максимум
  # +16), и без этого механизм клипа не проверить вовсе.
  defp with_attack_cap(ruleset, cap),
    do: %{ruleset | stat_caps: Map.put(ruleset.stat_caps, :attack_bonus, cap)}

  # Порча стороны капа У ЗАПИСИ — там, где она с 09.08.2026 и живёт.
  defp with_record_cap(ruleset, id, inside?),
    do: update_record(ruleset, id, &put_in(&1, [:cap, :inside?], inside?))

  defp with_record_assumed(ruleset, id),
    do: update_record(ruleset, id, &put_in(&1, [:cap, :assumed?], true))

  defp update_record(ruleset, id, fun) do
    update_in(ruleset, [Access.key!(:attack_bonuses), :applied], fn records ->
      for record <- records, do: if(record.id == id, do: fun.(record), else: record)
    end)
  end

  # Билд, у которого ненулевые все три источника: вещи +6, расовый бонус
  # сагровика +9, `Epic prowess` +1.
  # ⚠️ Меч в руках — не декорация: с 15.08.2026 расовый бонус Сиалы включается
  # оружием в руках (замер Dan, `GAME_CHECKS.md` Q1/Q4), и без него `race_attack_bonus`
  # был бы нулём, то есть все кейсы про кап проверяли бы клип одного источника
  # вместо трёх. Меч без своих чисел — он здесь ровно выключатель.
  defp capped_build do
    build(List.duplicate(:fighter, 40),
      race: :half_elf,
      gear:
        Gear.new(
          abilities: %{str: 12},
          weapon: :longsword,
          feats: [:siala_blade_proficiency]
        ),
      feats: %{21 => %{general: :epic_prowess}}
    )
  end

  defp attack_gaps(stats) do
    stats.gaps
    |> Enum.filter(fn
      {_, {:attack_bonus, _}} -> true
      {_, {:attack_bonus_weapon, _}} -> true
      _ -> false
    end)
    |> Enum.sort()
  end

  describe "Epic prowess — единственная безусловная прибавка от фита" do
    # 🔴 Обязательная проверка задания: AB вырос ровно на 1, терм назван, и
    # контроль без фита рядом. Уровень 41 — кап Сиалы, то есть граничный.
    test "воин 41 с Epic prowess получает +1 к AB, и терм называет себя", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 41)
      without = Rules.compute(build(levels), ruleset)

      with_feat =
        Rules.compute(
          build(levels, feats: %{21 => %{general: :epic_prowess}}),
          ruleset
        )

      # База не сдвинулась — вырос только собственный терм.
      assert without.base_attack == 31
      assert with_feat.base_attack == 31

      assert without.own_attack_bonus == 0
      assert without.own_attack_terms == []
      assert without.attack_bonus == 31

      assert with_feat.own_attack_bonus == 1
      assert with_feat.attack_bonus == 32

      # ⚠️ `under_cap?: false` — прибавка от фита лежит ПОВЕРХ капа атаки +20
      # (09.08.2026, Dan: «Фиты не входят в кап атаки +20»). Сторона капа стоит
      # на самом терме, потому что разбор AB обязан поставить его после строки
      # среза, а не перед ней.
      assert with_feat.own_attack_terms == [
               %{
                 id: :epic_prowess,
                 source: {:feat, :epic_prowess},
                 bonus: 1,
                 under_cap?: false
               }
             ]
    end

    # ⚠️ Два пути к одному числу обязаны сходиться: `compute/2` складывает
    # термы у себя, `AttackBonuses.total/2` — у себя. Разойдись они, игрок
    # увидел бы одно, а получил другое — та же причина, по которой дельта
    # считается разностью двух полных `compute`, а не инкрементально.
    test "total/2 сходится с own_attack_bonus из compute/2", %{ruleset: ruleset} do
      for b <- [
            build([:fighter]),
            build([:fighter], race: :gnome),
            build(List.duplicate(:fighter, 41),
              feats: %{21 => %{general: :epic_prowess}}
            ),
            build(List.duplicate(:fighter, 41),
              race: :halfling,
              feats: %{21 => %{general: :epic_prowess}}
            )
          ] do
        assert AttackBonuses.total(b, ruleset) == Rules.compute(b, ruleset).own_attack_bonus
      end
    end

    # ⚠️ Порча, которую «сумма частей равна итогу» не поймала бы: терм со
    # значением 0 сумму не двигает. Поэтому сравнивается СПИСОК термов, а не
    # только число — то же требование, что уже стоит у `ab_terms/2`.
    test "у билда без фита список термов ПУСТ, а не содержит нулевой терм", %{ruleset: ruleset} do
      stats = Rules.compute(build(List.duplicate(:fighter, 41)), ruleset)

      assert stats.own_attack_terms == []
      refute Enum.any?(stats.own_attack_terms, &(&1.bonus == 0))
    end

    # Фит эпический (требование — 21-й уровень персонажа), но само владение
    # ядро читает по слотам, а не по уровню: на 21-м он уже есть, и +1 идёт
    # в число сразу, а не с 41-го.
    test "прибавка идёт с уровня взятия, а не с капа", %{ruleset: ruleset} do
      feats = %{21 => %{general: :epic_prowess}}
      at_21 = Rules.compute(build(List.duplicate(:fighter, 21), feats: feats), ruleset)

      assert at_21.own_attack_bonus == 1
    end

    # `whole_effect_counted?/2` — тот же контракт, что у трёх соседей: суждение
    # данных (`effect_coverage`), а не вывод из того, что прибавка применена.
    test "Epic prowess покрыт целиком, Small stature — нет", %{ruleset: ruleset} do
      assert AttackBonuses.whole_effect_counted?(:epic_prowess, ruleset)

      # ⚠️ До задачи 3.143 (30.08.2026) здесь стояло «есть непосчитанный
      # остаток: +4 к четырём навыкам скрытности и обнаружения» — верно, пока
      # запись была applied. Small stature стал not_modelled (условие «когда
      # противник крупнее персонажа» посчитать нечем): атака у него теперь
      # не считается ВООБЩЕ, а не «неполностью». `whole_effect_counted?/2`
      # к тому же ищет только записи с источником `{:feat, id}`, а у Small
      # stature он `{:race_feat, id}` — эта функция не нашла бы запись ни при
      # каком вердикте, так что refute верен теперь по двум причинам сразу.
      refute AttackBonuses.whole_effect_counted?(:small_stature, ruleset)

      # ⚠️ `Weapon focus` стоял здесь как пример НЕпосчитанного до задачи 3.5
      # (часть B). Теперь он посчитан целиком, и это важно не само по себе:
      # `FeatChoices.gaps/3` спрашивает ровно эту функцию, чтобы не печатать
      # «прибавку от фита не считаем» рядом с термом `Weapon focus +1`, который
      # игрок видит в разборе AB.
      assert AttackBonuses.whole_effect_counted?(:weapon_focus, ruleset)
    end
  end

  # 🔴 ПЕРЕВОРОТ ВЕРДИКТА, ПРОТИВОПОЛОЖНЫЙ ОБЫЧНОМУ (задача 3.143, 30.08.2026).
  # Здесь стояло «Small stature — размерный модификатор, и он от РАСЫ, а не от
  # слота», и все три теста ниже проверяли `own_attack_bonus == 1` у Карлика
  # и Гоблина. Цитата в разметке была обрезана РОВНО перед условием: фит
  # называет его прямо — «gain bonuses to their attack rolls, armor class,
  # and hide checks WHEN DEALING WITH LARGER CREATURES» — а число (+1) стояло
  # только на странице расы, без условия. Обрезка сделала запись похожей на
  # безусловную. ✅ Подтверждено движком, независимо от чтения: Dan, тестовый
  # сервер, 30.08.2026 — «АБ и АЦ не попадают в чар лист», ровно потому что
  # бонус зависит от противника, а лист печатает свойства персонажа.
  describe "Small stature — условный размерный модификатор, и AB его не считает" do
    # Обе мелкие расы Сиалы: Карлик = Gnome, Гоблин = Halfling (CLAUDE.md §4,
    # коллизия имён — Гном это Dwarf). ⚠️ Было `{race, 1, [:small_stature]}`
    # у обеих до задачи 3.143 — своего терма нет ни у кого теперь.
    test "ни у одной расы нет ни терма, ни бонуса", %{ruleset: ruleset} do
      small =
        for race <- [:gnome, :halfling] do
          stats = Rules.compute(build([:fighter], race: race), ruleset)
          {race, stats.own_attack_bonus, Enum.map(stats.own_attack_terms, & &1.id)}
        end

      assert small == [{:gnome, 0, []}, {:halfling, 0, []}]

      for race <- [:human, :dwarf, :elf, :half_elf, :half_orc] do
        assert Rules.compute(build([:fighter], race: race), ruleset).own_attack_bonus == 0,
               "#{race}: размерного модификатора не бывает ни у кого"
      end
    end

    # ⚠️ Гейт — раса, а не владение фитом: расовые склонности не попадают
    # в `Build.feats_owned/3` вовсе. Проверяется тем, что фит, вписанный
    # в слот человеку, прибавки НЕ даёт (в игре его туда и не взять). Сегодня
    # это ноль по ДВУМ причинам сразу — гейт по-прежнему не пропускает
    # человека, а запись и не считается вовсе ни у кого; тест остаётся,
    # потому что гейт — отдельный от условности механизм, и порча одного
    # не должна маскироваться исправностью другого.
    test "человек со Small stature в слоте прибавки не получает", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build([:fighter], race: :human, feats: %{1 => %{general: :small_stature}}),
          ruleset
        )

      assert stats.own_attack_bonus == 0
    end

    # Отсутствие терма не зависит от уровня — ни на 1-м, ни на 41-м.
    test "нет терма ни на 1-м уровне, ни на 41-м", %{ruleset: ruleset} do
      at_1 = Rules.compute(build([:fighter], race: :gnome), ruleset)
      at_41 = Rules.compute(build(List.duplicate(:fighter, 41), race: :gnome), ruleset)

      assert at_1.own_attack_bonus == 0
      assert at_41.own_attack_bonus == 0
    end

    # ⚠️ И оговорки тоже нет: `not_a_gap` (basis `feat_description`) гасит её —
    # описание фита само называет условие точнее нашей фразы, и оно доступно
    # игроку (конструктор, задача 3.87; экран просмотра, 3.94).
    test "и оговорки не печатает", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter], race: :gnome), ruleset)

      assert attack_gaps(stats) == []
    end
  end

  describe "Мастер оружия — колонка «AB bonus» ступенями, и с 3.5 она СЧИТАЕТСЯ" do
    # 🔴 Переворот вердикта задачей 3.5 (часть B): колонка обусловлена оружием
    # в руках, а оружие в руках теперь есть. Наблюдаемое ступенчатое поведение
    # осталось тем же — колонка печатает «-» на 1–4 и «+1» с 5-го, — но теперь
    # это число в AB, а не уровень появления оговорки.
    #
    # ⚠️ Фит `weapon_of_choice` в билде обязателен с 14.08.2026: без него колонки
    # нет вовсе, значит и оговорки про её оружие быть не может (вторая половина
    # ниже). Собственных требований фита этот билд не выполняет (фокуса в нём
    # нет), и это сознательно: модуль про прибавки легальность пика не проверяет
    # ВООБЩЕ — за неё отвечает `Rules.validate_feat_pick/3`, — а фикстуре нужен
    # ровно случай «оружие не названо ничем».
    test "оговорка появляется с 5-го уровня класса, а не с первого", %{ruleset: ruleset} do
      for {wm_levels, expected} <- [
            {1, []},
            {4, []},
            {5, [:weapon_master]},
            {28, [:weapon_master]}
          ] do
        levels = List.duplicate(:fighter, 6) ++ List.duplicate(:weapon_master, wm_levels)

        # 7-й уровень персонажа = 1-й уровень Мастера оружия, там его слот.
        picked =
          build(levels, feats: %{7 => %{{:class_bonus, :weapon_master} => :weapon_of_choice}})

        level = 6 + wm_levels

        assert AttackBonuses.weapon_conditional(picked, ruleset, level) == expected,
               "ВМ #{wm_levels}: ожидалось #{inspect(expected)}"

        # ⚠️ Вторая половина, без которой первая зеленела бы и у кода, который
        # владение не смотрит: фит не взят — колонки нет, и оговорки нет тоже.
        # Молча, как у любого невзятого фита (решение Dan 14.08.2026).
        assert AttackBonuses.weapon_conditional(build(levels), ruleset, level) == [],
               "ВМ #{wm_levels} без Weapon of choice: оговорка про чужую колонку"
      end
    end

    # 🔴 Главное число этой задачи и самое крупное в файле разметки. Колонка
    # действует «with their weapon of choice»; сам выбор здесь НЕ записан — так
    # выглядит расшаренная до 3.26 ссылка, — поэтому оружие выводится от
    # `Weapon focus`, чьим оружием weapon of choice обязан быть по своему же
    # требованию.
    test "с оружием в руках колонка идёт в AB ступенями, без него — нет", %{ruleset: ruleset} do
      # ⚠️ Владение клинковым обязательно: без него скимитар в руки не берётся
      # вовсе (`Rules.GearWeapon`), и тест мерил бы не то, что называет.
      feats = %{
        1 => %{{:class_bonus, :fighter} => :siala_blade_proficiency},
        3 => %{general: {:weapon_focus, :scimitar}}
      }

      for {wm_levels, expected} <- [{4, 0}, {5, 1}, {13, 2}, {28, 7}] do
        levels =
          List.duplicate(:fighter, 41 - wm_levels) ++ List.duplicate(:weapon_master, wm_levels)

        # Слот Мастера оружия стоит на его 1-м КЛАССОВОМ уровне, а он у каждой
        # строки таблицы свой.
        wm_first = 42 - wm_levels

        with_feat =
          Map.put(feats, wm_first, %{{:class_bonus, :weapon_master} => :weapon_of_choice})

        b = build(levels, feats: with_feat)
        without = Rules.compute(b, ruleset)
        with_weapon = Rules.compute(%Build{b | gear: %Gear{weapon: :scimitar}}, ruleset)

        # Фокус даёт +1 сам, поэтому колонка — это разность.
        assert with_weapon.own_attack_bonus - 1 == expected,
               "ВМ #{wm_levels} со скимитаром: ожидалось +#{expected} от колонки"

        # ⚠️ Отрицательный контроль в том же тесте: без оружия в руках ни одна
        # ступень не считается. Порознь обе половины зеленели бы и у кода,
        # который колонку не читает вовсе.
        assert without.own_attack_bonus == 0

        # ⚠️ А оговорка есть только там, где считать УЖЕ есть что: на 4-м уровне
        # класса колонка печатает «-», и предупреждение о непосчитанном висело бы
        # над тем, чего не происходит.
        gap = {:not_modelled, {:attack_bonus_weapon, :weapon_master}}

        if expected > 0,
          do: assert(gap in without.gaps),
          else: refute(gap in without.gaps)
      end
    end

    # 🔴 Регрессия 14.08.2026 и её приёмка. Колонка бралась из вывода «оружие =
    # то, на которое есть Weapon focus» — и вывод продолжал работать после того,
    # как замер M2b сделал `Weapon of choice` необязательным слотовым пиком
    # («Получается я могу и не брать weapon of choice!»). Персонаж, фит не
    # бравший, получал +7 AB ни за что.
    #
    # ⚠️ Обе половины ОДНИМ тестом: порознь каждая зеленеет и при неверной
    # модели — «без фита нет колонки» верно и у кода, который колонку не считает
    # никогда, а «с фитом есть» верно и у сегодняшнего бага.
    test "колонка требует ВЛАДЕНИЯ Weapon of choice, а не только оружия в руках", %{
      ruleset: ruleset
    } do
      levels = List.duplicate(:fighter, 13) ++ List.duplicate(:weapon_master, 28)

      feats = %{
        1 => %{{:class_bonus, :fighter} => :siala_blade_proficiency},
        3 => %{general: {:weapon_focus, :scimitar}}
      }

      fields = [feats: feats, gear: %Gear{weapon: :scimitar}]
      without = Rules.compute(build(levels, fields), ruleset)

      with_feat =
        Rules.compute(
          build(
            levels,
            Keyword.put(
              fields,
              :feats,
              Map.put(feats, 14, %{{:class_bonus, :weapon_master} => :weapon_of_choice})
            )
          ),
          ruleset
        )

      terms = fn stats -> Enum.map(stats.own_attack_terms, & &1.id) end

      # Фита нет — колонки нет вовсе, сколько бы уровней класса ни было взято.
      refute :weapon_master in terms.(without)

      # ⚠️ А `Weapon focus` при этом ОСТАЁТСЯ: он про своё оружие и к Мастеру
      # оружия отношения не имеет. Без этой строки тест прошёл бы и у правки,
      # которая срезала бы оба терма разом.
      assert terms.(without) == [:weapon_focus]
      assert without.own_attack_bonus == 1

      # Фит взят — колонка на месте, +7 на 28 уровнях класса.
      assert terms.(with_feat) == [:weapon_focus, :weapon_master]
      assert with_feat.own_attack_bonus == 8

      # ⚠️ И молча: невзятый фит оговорки не стоит (решение Dan 14.08.2026 —
      # «давать информацию, что АБ меньше, чем могло бы быть… нам не надо»).
      assert attack_gaps(without) == []
      assert attack_gaps(with_feat) == []
    end

    # Обратный контроль к предыдущему: оружие в руках НЕ то, на которое взят
    # фокус, — колонка не считается, и оговорки при этом нет. Игра там тоже
    # ничего не даёт, значит признаваться не в чем.
    #
    # ⚠️ `Weapon of choice` здесь взят намеренно, и без него тест перестал бы
    # проверять то, что называет: с 14.08.2026 невзятый фит сам по себе убирает
    # колонку (`:no_designator`), и «не то оружие» (`:wrong_weapon`) осталось бы
    # непройденной веткой при зелёном тесте.
    test "фит взят, но в руках не то оружие — ни числа, ни оговорки", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 13) ++ List.duplicate(:weapon_master, 28)

      b =
        build(levels,
          feats: %{
            1 => %{{:class_bonus, :fighter} => :siala_blade_proficiency},
            3 => %{general: {:weapon_focus, :scimitar}},
            14 => %{{:class_bonus, :weapon_master} => :weapon_of_choice}
          },
          gear: %Gear{weapon: :longsword}
        )

      stats = Rules.compute(b, ruleset)

      assert stats.own_attack_bonus == 0
      assert attack_gaps(stats) == []
    end

    # ⚠️ Порча «таблица → формула», и она НЕ ловится на низких уровнях. 1.12a
    # наступила на это у `Sacred defense`: линейное правило совпадает
    # с формулой на первых ступенях и расходится только на капе. Здесь
    # ловушка та же и острее: до 12-го уровня класса «+1» совпадает
    # с `div(level, 5)`, а на 28-м таблица держит +7, а формула дала бы 5;
    # каденция «+1 каждые 3 уровня после 10-го» дала бы на 31-м +8, а таблица
    # обязана держать +7 (её последняя ступень — 28-я, продолжать её нельзя).
    #
    # Проверяется по САМИМ ДАННЫМ, потому что величина сегодня не применяется:
    # ядро её не считает, а данные обязаны остаться верными к тому дню, когда
    # начнёт (см. `_weapon_decision.how_to_flip_it`).
    test "таблица держит ступени источника, а не формулу", %{ruleset: ruleset} do
      %{attack_at_class_level: steps} =
        ruleset.attack_bonuses.applied
        |> Enum.find(&(&1.id == :weapon_master))
        |> Map.fetch!(:amount)

      # Дословно колонка «AB bonus» страницы `Weapon master` (revid 71587):
      # «-» на 1–4, «+1» на 5–12, «+2» на 13, …, «+7» на 28–30.
      assert steps == %{5 => 1, 13 => 2, 16 => 3, 19 => 4, 22 => 5, 25 => 6, 28 => 7}

      at = fn level ->
        steps
        |> Enum.filter(fn {s, _} -> s <= level end)
        |> Enum.max_by(&elem(&1, 0), fn -> {0, 0} end)
        |> elem(1)
      end

      # Три точки, где формула и таблица расходятся, и первая — та, на которой
      # порча была бы незаметна.
      assert at.(12) == 1
      assert at.(28) == 7

      # ⚠️ 31-й уровень класса: Сиала поднимает потолок престижа до 31, а
      # таблица Fandom кончается на 30-м. Держится последнее значение.
      assert at.(31) == 7
      assert at.(4) == 0
    end
  end

  # ⚠️ Заголовок был «Weapon of choice ВЫДАЁТСЯ классом, и его выбор теперь
  # записан (3.26)» — 14.08.2026 замер M2b показал, что фит не выдаётся вовсе:
  # первый уровень Мастера оружия даёт СЛОТ, в котором `Weapon of choice` лежит
  # рядом с пятью сиальскими владениями («он не является автоматическим или
  # обязательным»). Существо задачи 3.26 от этого не изменилось ни на число —
  # колонка Мастера оружия считается только тем оружием, которое назвал выбор, —
  # изменилось лишь то, ГДЕ этот выбор записан: был `granted_choices`, стал
  # обычный пик в слот.
  describe "Weapon of choice берётся слотом, и колонка следует за его выбором (3.26)" do
    # 🔴 Билд из брифа задачи и вся её приёмка: Воин 13 / ВМ 28 со скимитаром
    # в руках. Один фокус — колонка считается по выводу («weapon of choice обязан
    # быть тем же оружием, что фокус»); два фокуса — вывод неоднозначен, и до 3.26
    # колонка теряла свои +7 у совершенно обычного билда.
    #
    # Владение клинковым обязательно: без него скимитар в руки не берётся вовсе
    # (`Rules.GearWeapon`), и тест мерил бы отсутствие оружия.
    defp wm_build(fields \\ []) do
      feats =
        Map.merge(
          %{
            1 => %{
              {:class_bonus, :fighter} => :siala_blade_proficiency,
              :general => {:weapon_focus, :scimitar}
            },
            # 14-й уровень персонажа = 1-й уровень Мастера оружия, и там слот.
            # ⚠️ Пик БЕЗ выбора — это не выдумка ради теста, а форма, в которой
            # приезжает старая расшаренная ссылка: до 14.08.2026 фит выдавался
            # классом, и никакого выбора в билде не лежало.
            14 => %{{:class_bonus, :weapon_master} => :weapon_of_choice}
          },
          Keyword.get(fields, :extra_feats, %{})
        )

      build(
        List.duplicate(:fighter, 13) ++ List.duplicate(:weapon_master, 28),
        [feats: feats, gear: %Gear{weapon: :scimitar}] ++ Keyword.delete(fields, :extra_feats)
      )
    end

    # Второй фокус — законный обычный билд, а не крайний случай.
    defp two_focus_build,
      do: wm_build(extra_feats: %{3 => %{general: {:weapon_focus, :longsword}}})

    # Тот же билд, но слот Мастера оружия потрачен на `Weapon of choice`
    # С НАЗВАННЫМ оружием — то, как выглядит билд, собранный после 14.08.2026.
    defp wm_with_choice(weapon, opts \\ []) do
      extra = %{14 => %{{:class_bonus, :weapon_master} => {:weapon_of_choice, weapon}}}

      extra =
        if opts[:two],
          do: Map.put(extra, 3, %{general: {:weapon_focus, :longsword}}),
          else: extra

      wm_build(extra_feats: extra)
    end

    test "два фокуса без записанного выбора — по-прежнему гэп, с записанным — +7", %{
      ruleset: ruleset
    } do
      # ⚠️ Первая половина — то, как ведёт себя УЖЕ РАСШАРЕННАЯ ссылка: выбора
      # выдачи в ней нет, вывод неоднозначен, колонка не считается и говорит
      # об этом. Ровно поведение до задачи 3.26, и оно обязано сохраниться.
      without = Rules.compute(two_focus_build(), ruleset)

      assert without.own_attack_bonus == 1
      assert attack_gaps(without) == [{:not_modelled, {:attack_bonus_weapon, :weapon_master}}]

      # Вторая половина — то же самое, но выбор записан вместе с пиком.
      with_choice = Rules.compute(wm_with_choice(:scimitar), ruleset)

      assert with_choice.own_attack_bonus == 8
      assert attack_gaps(with_choice) == []

      # Дословно числа брифа: −7 к AB было ценой дыры.
      assert with_choice.attack_bonus - without.attack_bonus == 7
      assert {without.attack_bonus, with_choice.attack_bonus} == {32, 39}
    end

    # Один фокус — вывод однозначен и без записи, поэтому запись ничего не меняет.
    # Это и есть обещание «старые ссылки считаются как считались».
    test "один фокус: с записью и без неё одно и то же число", %{ruleset: ruleset} do
      without = Rules.compute(wm_build(), ruleset)

      assert without.own_attack_bonus == 8
      assert Rules.compute(wm_with_choice(:scimitar), ruleset).own_attack_bonus == 8
      assert attack_gaps(without) == []
    end

    # ⚠️ Записанный выбор — это и запрет тоже, а не только разрешение: колонка
    # действует ТЕМ оружием, которое назвал weapon of choice, а не любым, на
    # которое есть фокус. Обе половины одним тестом.
    test "выбор назвал не то оружие, что в руках — колонка не считается", %{ruleset: ruleset} do
      stats = Rules.compute(wm_with_choice(:longsword, two: true), ruleset)

      # `Weapon focus (scimitar)` свои +1 даёт — он про своё оружие;
      # колонка Мастера оружия про чужое, и её нет.
      assert stats.own_attack_bonus == 1

      # ⚠️ И гэпа тоже нет: игра с этим оружием колонки не даёт, признаваться
      # не в чем (тот же довод, что у `:wrong_weapon` вообще).
      assert attack_gaps(stats) == []
    end

    # 🔴 Второй weapon of choice — законное эпическое взятие («additional weapons
    # of choice as class epic bonus feats»), и тогда колонка действует ОБОИМИ
    # оружиями: фит «designates which weapon types benefit». ⚠️ Отдельным
    # assert'ом рядом — что `Epic weapon focus` при двух фокусах остаётся
    # неоднозначным: там оружие УНАСЛЕДОВАНО, а не названо своим взятием, и
    # путать эти два случая нельзя.
    test "два weapon of choice — колонка действует обоими, а эпический фокус нет", %{
      ruleset: ruleset
    } do
      # ВМ 13 = 26-й уровень персонажа, эпический бонусный слот класса.
      # ⚠️ Оба взятия теперь пики в слот — первое на 14-м (ВМ 1) и второе
      # на 26-м; до 14.08.2026 первое было выдачей с записанным выбором.
      two_choices =
        Build.put_feat(
          wm_with_choice(:scimitar, two: true),
          26,
          {:class_bonus, :weapon_master},
          :weapon_of_choice,
          :longsword
        )

      with_scimitar = Rules.compute(two_choices, ruleset)

      with_longsword =
        Rules.compute(%Build{two_choices | gear: %Gear{weapon: :longsword}}, ruleset)

      assert with_scimitar.own_attack_bonus == 8
      assert with_longsword.own_attack_bonus == 8
      assert attack_gaps(with_longsword) == []

      # Тот же билд плюс `Epic weapon focus`: своего оружия он не называет,
      # наследует от двух фокусов — значит остаётся `:unknown` и говорит об этом.
      epic = Build.put_feat(two_choices, 21, :general, :epic_weapon_focus)
      epic_stats = Rules.compute(epic, ruleset)

      assert {:not_modelled, {:attack_bonus_weapon, :epic_weapon_focus}} in epic_stats.gaps
      assert epic_stats.own_attack_bonus == 8
    end

    # Оружие обязано быть тем, на которое взят `Weapon focus` («prereq=[[weapon
    # focus]] (chosen weapon)», fandom revid 65834). Ослабить это значило бы
    # разрешить собрать нелегальный билд.
    #
    # ⚠️ Проверялось через `granted_feat_choice_candidates/4` и
    # `validate_granted_feat_choice/5` — ветку для ВЫДАННОГО фита. С 14.08.2026
    # фит берётся слотом, и та же строгость обязана прийти из обычного пути
    # пика: он и проверяется здесь, иначе правка тихо ослабила бы требование.
    test "выбор ограничен оружием, на которое есть Weapon focus", %{ruleset: ruleset} do
      b = two_focus_build()

      slot = %{
        id: {:class_bonus, :weapon_master},
        kind: :class_bonus,
        class: :weapon_master,
        taken_with: :weapon_master,
        epic?: false
      }

      pick = fn weapon ->
        Rules.validate_feat_pick(
          b,
          %{feat: :weapon_of_choice, at: 14, slot: slot, choice: weapon},
          ruleset
        )
      end

      assert pick.(:scimitar) == :ok
      assert pick.(:longsword) == :ok

      # Рапира — настоящее оружие домена, фокуса на неё нет.
      assert {:error, reasons} = pick.(:rapier)
      assert {:requires_same_choice, :weapon_focus, :rapier} in reasons

      # Лук вообще вне домена weapon of choice («only available for melee»).
      assert {:error, reasons} = pick.(:longbow)
      assert {:invalid_choice, :weapon_of_choice, :longbow} in reasons
    end

    # Слот стоит на 1-м КЛАССОВОМ уровне ВМ, а не на 1-м персонажном.
    #
    # ⚠️ Тест проверял `granted_feat_choices_owed/3` — «на каком уровне класс
    # должен выдачу». Выдачи не стало, и вопрос стал прямее: на каком уровне
    # стоит слот. Само число (14) — то же самое и по той же причине.
    test "слот стоит ровно на том уровне, где класс брал выдачу", %{ruleset: ruleset} do
      b = wm_build()

      kinds = fn level -> b |> FeatSlots.at(ruleset, level) |> Enum.map(& &1.kind) end

      assert :class_bonus in kinds.(14)
      refute :class_bonus in kinds.(13)
      refute :class_bonus in kinds.(15)

      # ⚠️ И механизм выдачи с выбором остался без пользователей: сегодня
      # `granted_feat_choices_owed/3` не должен предлагать ничего никому.
      assert Rules.granted_feat_choices_owed(b, ruleset, 14) == []
    end
  end

  describe "Семейство фокуса — считается с тем оружием, что в руках (задача 3.5)" do
    # ⚠️ Владение клинковым — в билде, а не «подразумевается»: без него скимитар
    # в руки не берётся, и все тесты ниже мерили бы отсутствие оружия.
    defp focus_build(fields \\ []) do
      feats = %{
        1 => %{
          {:class_bonus, :fighter} => :siala_blade_proficiency,
          :general => {:weapon_focus, :scimitar}
        },
        21 => %{general: :epic_weapon_focus}
      }

      build(List.duplicate(:fighter, 41), [feats: feats] ++ fields)
    end

    # 🔴 Главная пара этой задачи, и ОДНИМ тестом: со совпавшим оружием оба
    # фокуса в числе, без оружия — ни одного и обе оговорки на месте. Порознь
    # каждая половина зеленела бы и при неверной модели (первая — у кода, который
    # считает фокус всегда; вторая — у того, который не считает никогда).
    test "оружие совпало — +3 в AB; оружия нет — 0 и обе оговорки", %{ruleset: ruleset} do
      with_weapon = Rules.compute(focus_build(gear: %Gear{weapon: :scimitar}), ruleset)
      without = Rules.compute(focus_build(), ruleset)

      assert with_weapon.own_attack_bonus == 3

      assert Enum.map(with_weapon.own_attack_terms, & &1.id) == [
               :weapon_focus,
               :epic_weapon_focus
             ]

      assert attack_gaps(with_weapon) == []

      assert without.own_attack_bonus == 0

      assert attack_gaps(without) == [
               {:not_modelled, {:attack_bonus_weapon, :epic_weapon_focus}},
               {:not_modelled, {:attack_bonus_weapon, :weapon_focus}}
             ]
    end

    # Не то оружие — прибавки нет, и оговорки тоже нет: в игре с длинным мечом
    # фокус на скимитар не работает, признаваться не в чем. ⚠️ Это третье
    # состояние, а не половина предыдущего теста: «не знаем» и «знаем, что ноль» —
    # разные ответы, и путать их значило бы либо пугать игрока зря, либо
    # промолчать там, где надо сказать.
    test "не то оружие — ни прибавки, ни оговорки", %{ruleset: ruleset} do
      stats = Rules.compute(focus_build(gear: %Gear{weapon: :longsword}), ruleset)

      assert stats.own_attack_bonus == 0
      assert attack_gaps(stats) == []
    end

    # ⚠️ Два обычных фокуса — законный билд (`distinct: true`), и он ломает
    # наследование: эпический фокус взят в ОДИН из двух, а в какой — не записано
    # нигде. Считать +2 потому, что в руках «какой-то из фокусов», значило бы
    # завысить AB половине таких билдов.
    test "два фокуса: обычный считается, эпический — нет, и он говорит почему", %{
      ruleset: ruleset
    } do
      feats = %{
        1 => %{
          {:class_bonus, :fighter} => :siala_blade_proficiency,
          :general => {:weapon_focus, :scimitar}
        },
        3 => %{general: {:weapon_focus, :rapier}},
        21 => %{general: :epic_weapon_focus}
      }

      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 41), feats: feats, gear: %Gear{weapon: :scimitar}),
          ruleset
        )

      assert stats.own_attack_bonus == 1
      assert Enum.map(stats.own_attack_terms, & &1.id) == [:weapon_focus]

      assert attack_gaps(stats) == [
               {:not_modelled, {:attack_bonus_weapon, :epic_weapon_focus}}
             ]
    end

    # Фит с ВЕЩИ параметра не несёт (`Rules.GearFeats`), значит оружие им
    # не назвать — и прибавка не считается, хотя фит у персонажа есть.
    test "фокус с вещи оружия не называет — прибавки нет, оговорка есть", %{ruleset: ruleset} do
      gear = %Gear{weapon: :scimitar, feats: [:weapon_focus, :siala_blade_proficiency]}
      stats = Rules.compute(build(List.duplicate(:fighter, 41), gear: gear), ruleset)

      assert stats.own_attack_bonus == 0
      assert {:not_modelled, {:attack_bonus_weapon, :weapon_focus}} in stats.gaps
    end

    # Величина лежит в данных и после переворота — веб-слой печатает её в гэпе
    # («не считаем +2») у билда, который оружие не назвал.
    test "величины и сторона капа лежат в данных", %{ruleset: ruleset} do
      by_id = Map.new(ruleset.attack_bonuses.applied, &{&1.id, &1})

      assert by_id[:weapon_focus].amount == %{kind: :flat, bonus: 1}
      assert by_id[:epic_weapon_focus].amount == %{kind: :flat, bonus: 2}
      assert by_id[:weapon_focus].weapon == [:weapon_focus]
      assert by_id[:epic_weapon_focus].weapon == [:epic_weapon_focus, :weapon_focus]

      # ⚠️ Фиты на оружие — ПОВЕРХ капа, в отличие от чисел самого оружия.
      refute by_id[:weapon_focus].cap.inside?
      refute by_id[:epic_weapon_focus].cap.inside?
    end

    # Обратный контроль: билд, который фокус не брал, оговорок про оружие не
    # несёт. Иначе тест выше зеленел бы и у кода, который вешает гэп всем.
    test "билд без фокуса оговорок про оружие не несёт", %{ruleset: ruleset} do
      stats = Rules.compute(build(List.duplicate(:fighter, 41)), ruleset)

      assert AttackBonuses.weapon_conditional(build(List.duplicate(:fighter, 41)), ruleset, 41) ==
               []

      assert attack_gaps(stats) == []
    end
  end

  # 🔴 Задача 3.101. Два последних носителя условия «оружием», у которых оружие
  # названо не выбором фита, а КЛАССОМ оружия. Оба класса называет источник,
  # и оба раза — не на странице фита, а на странице самого оружия:
  #
  #   * `fandom:Throwing weapon` (revid 60731) перечисляет весь класс —
  #     «these weapons consist of darts, shurikens, slings, and throwing
  #     axes» — и прямо называет, ради чего он существует: «This classification
  #     is mostly notable in connection with a halfling's good aim feat»;
  #   * `fandom:Sling` (revid 71191) снимает единственный спорный член:
  #     «A sling is considered a throwing weapon for the good aim feat»;
  #   * `fandom:Bow` (revid 49109) даёт состав «луков»: «In Neverwinter Nights
  #     there are two types of bows: longbows and shortbows»;
  #   * `fandom:Enchant arrow` (revid 59129) закрывает всё остальное
  #     дальнобойное: «The enchant arrow attack bonus is reported on the
  #     character sheet for all ranged weapons, but that is a display error;
  #     in combat, this feat only operates for bows».
  describe "Good aim — прибавка «метательным», и «метательное» лежит полем справочника" do
    defp halfling(weapon) do
      gear =
        if weapon,
          do:
            Gear.new(weapon: weapon, feats: [:siala_ranged_proficiency, :siala_blade_proficiency]),
          else: Gear.new()

      Build.new(levels: [:fighter], base_abilities: @flat, race: :halfling, gear: gear)
    end

    # 🔴 Главная пара одним тестом: с метательным прибавка есть, без оружия —
    # нет и оговорка на месте. Порознь каждая половина зеленела бы и при
    # неверной модели.
    test "праща и дротик дают +1; без оружия — 0 и оговорка", %{ruleset: ruleset} do
      for weapon <- [:sling, :dart, :shuriken, :throwing_axe] do
        stats = Rules.compute(halfling(weapon), ruleset)

        assert {:good_aim, 1} in Enum.map(stats.own_attack_terms, &{&1.id, &1.bonus}),
               "#{weapon}: прибавка Гоблина не посчитана"

        assert attack_gaps(stats) == [], "#{weapon}: оговорка про посчитанное"
      end

      without = Rules.compute(halfling(nil), ruleset)

      refute Enum.any?(without.own_attack_terms, &(&1.id == :good_aim))

      assert attack_gaps(without) == [
               {:not_modelled, {:attack_bonus_weapon, :good_aim}}
             ]
    end

    # ⚠️ Праща ПРОТИВ ИНТУИЦИИ («метает, а не бросается»), и это ровно то место,
    # которое следующий читатель захочет «починить». Отдельным тестом с цитатой
    # именно поэтому.
    test "праща — метательное оружие, и источник называет фит по имени", %{ruleset: ruleset} do
      assert ruleset.weapons[:sling].thrown?

      assert Rules.compute(halfling(:sling), ruleset).own_attack_bonus ==
               Rules.compute(halfling(:dart), ruleset).own_attack_bonus
    end

    # Не то оружие — ни прибавки, ни оговорки: в игре с мечом её тоже нет,
    # признаваться не в чем. Третье состояние, а не половина первого теста.
    # ⚠️ Короткий лук, а не длинный: длинный — оружие размера large, а Гоблин
    # мелкий, и в руки он его не берёт вовсе (`Rules.Wield`). Тогда мерилось бы
    # «оружия нет», а не «оружие не то».
    test "меч и короткий лук — ни прибавки, ни оговорки", %{ruleset: ruleset} do
      for weapon <- [:longsword, :shortbow] do
        stats = Rules.compute(halfling(weapon), ruleset)

        refute Enum.any?(stats.own_attack_terms, &(&1.id == :good_aim)), "#{weapon}"
        assert attack_gaps(stats) == [], "#{weapon}"
      end
    end

    # 🔴 Гейт — РАСА, а не владение фитом (`{:race_feat, _}`), и это не деталь:
    # `Notes` страницы фита говорят, что бонус праще «hardcoded to the halfling
    # race», то есть механизм у неё свой. Для нас оба совпадают без остатка
    # ровно потому, что запись гейтится расой.
    test "у Карлика той же мелкой расы прибавки нет — гейт по расе", %{ruleset: ruleset} do
      gnome =
        Build.new(
          levels: [:fighter],
          base_abilities: @flat,
          race: :gnome,
          gear: Gear.new(weapon: :sling, feats: [:siala_ranged_proficiency])
        )

      stats = Rules.compute(gnome, ruleset)

      refute Enum.any?(stats.own_attack_terms, &(&1.id == :good_aim))
      assert stats.own_attack_bonus == 0

      # ...а тот же билд Гоблином (та же мелкая раса семьи, то же оружие)
      # прибавку получает — контроль к тому, что тест выше про склонность
      # конкретной расы, а не про сломанный расчёт целиком.
      # ⚠️ До задачи 3.143 (30.08.2026) тем же контролем служил размерный
      # модификатор той же расы (`{:small_stature, 1}` в own_attack_terms) —
      # он стал not_modelled и своего терма больше не даёт ни у кого.
      halfling = %Build{gnome | race: :halfling}
      assert Rules.compute(halfling, ruleset).own_attack_bonus == 1
    end

    test "величина, свойство и сторона капа лежат в данных", %{ruleset: ruleset} do
      record = Enum.find(ruleset.attack_bonuses.applied, &(&1.id == :good_aim))

      assert record.amount == %{kind: :flat, bonus: 1}
      assert record.weapon_kind == {:property, :thrown}
      assert record.source == {:race_feat, :good_aim}
      # «The bonus does not count against the +20 attack bonus cap» — цитата
      # со страницы самого фита, а не вывод из слова Dan про фиты.
      refute record.cap.inside?
      refute record.cap.assumed?
    end
  end

  describe "Enchant arrow — растущая прибавка луком, и «лук» перечислен источником" do
    # Легальная лестница: волшебник даёт аркановый уровень, воин — БАБ +6,
    # и одиннадцатый уровень ПМ приходится на уровень персонажа 22 (кап 20
    # уже пройден). Собрано лестницей, а не «списком классов ради числа».
    defp archer(class_levels, fields \\ []) do
      levels =
        [:wizard] ++ List.duplicate(:fighter, 10) ++ List.duplicate(:arcane_archer, class_levels)

      feats = %{
        1 => %{general: {:weapon_focus, :longbow}},
        3 => %{general: :point_blank_shot}
      }

      Build.new([levels: levels, base_abilities: @flat, race: :elf, feats: feats] ++ fields)
    end

    defp bow_gear(weapon), do: Gear.new(weapon: weapon, feats: [:siala_ranged_proficiency])

    defp enchant(stats) do
      Enum.find_value(stats.own_attack_terms, 0, &if(&1.id == :enchant_arrow, do: &1.bonus))
    end

    # 🔴 Ступени таблицы поимённо, включая обе границы: +1 на первом уровне
    # класса, +15 на 29-м, и на 30-м держится последнее значение (источник
    # кончается на 29-м, дальше не продолжаем — CLAUDE.md §3).
    test "таблица по уровням класса: 1 → +1, 29 → +15, 30 → +15", %{ruleset: ruleset} do
      for {class_levels, expected} <- [{1, 1}, {2, 1}, {3, 2}, {10, 5}, {29, 15}, {30, 15}] do
        stats = Rules.compute(archer(class_levels, gear: bow_gear(:longbow)), ruleset)
        assert enchant(stats) == expected, "Тайный лучник #{class_levels}"
      end
    end

    # ✅ ВСЯ таблица против НАБЛЮДЕНИЯ, а не против себя самой (Dan, 26.08.2026,
    # `GAME_CHECKS.md` AC5): «фит даётся через каждые 2 уровня, начиная с 1.
    # К примеру, на 25 уровне arcane archer у меня 13 уровень данного фита».
    #
    # 🔴 Зачем сверх соседнего теста: сиальская страница расписывает колонку
    # только до 10-го классового уровня, дальше мы продолжаем ванильной. Числа
    # 1–10 совпадают строка в строку, поэтому продолжение не было выдумкой —
    # но было ВЫВОДОМ. Наблюдение попало ровно в спорную половину: 25-й уровень
    # лежит глубоко за концом таблицы шарда.
    #
    # ⚠️ Замер AC2 (арбалет) эту половину закрыть не мог — он сделан там, где
    # обе таблицы дают одно и то же.
    test "все 15 ступеней сходятся с формулой замера (уровень + 1) / 2", %{ruleset: ruleset} do
      for class_levels <- 1..29 do
        stats = Rules.compute(archer(class_levels, gear: bow_gear(:longbow)), ruleset)
        assert enchant(stats) == div(class_levels + 1, 2), "Тайный лучник #{class_levels}"
      end

      # Названная замером точка отдельной строкой — она и есть наблюдение,
      # остальные 14 ступеней сошлись счётом по правилу, а не с листа.
      assert enchant(Rules.compute(archer(25, gear: bow_gear(:longbow)), ruleset)) == 13
    end

    # 🔴 Главная пара одним тестом.
    test "с луком +15; без оружия — 0 и оговорка", %{ruleset: ruleset} do
      with_bow = Rules.compute(archer(29, gear: bow_gear(:longbow)), ruleset)
      without = Rules.compute(archer(29), ruleset)

      assert enchant(with_bow) == 15
      refute {:not_modelled, {:attack_bonus_weapon, :enchant_arrow}} in with_bow.gaps

      assert enchant(without) == 0
      assert {:not_modelled, {:attack_bonus_weapon, :enchant_arrow}} in without.gaps
    end

    test "короткий лук считается так же, как длинный", %{ruleset: ruleset} do
      assert enchant(Rules.compute(archer(29, gear: bow_gear(:shortbow)), ruleset)) == 15
    end

    # ⚠️ Праща и дротик дальнобойные (`ranged?`), и ровно поэтому «лук» нельзя
    # было вывести из этого поля: вывод дал бы пращнику +15.
    test "праща дальнобойна и прибавки НЕ даёт", %{ruleset: ruleset} do
      assert ruleset.weapons[:sling].ranged?
      assert enchant(Rules.compute(archer(29, gear: bow_gear(:sling)), ruleset)) == 0
    end

    # 🔴 РАСХОЖДЕНИЕ RULESET'ОВ, и оно единственное: на ванили арбалет прибавки
    # не даёт («only operates for bows»), на Сиале даёт — «Все классовые умения
    # Тайного лучника теперь распространяются на малый и большие арбалеты»
    # (`siala_41/classes.json`, `class_ability_weapons`, `status: verified`).
    #
    # ⚠️ Игрок с арбалетом на ВАНИЛИ увидит прибавку у себя на листе в игре
    # и не увидит её у нас — так и должно быть: лист врёт, и источник говорит
    # это дословно.
    test "арбалет: у Сиалы +15, у ванили 0", %{ruleset: siala, vanilla: vanilla} do
      for weapon <- [:light_crossbow, :heavy_crossbow] do
        assert enchant(Rules.compute(archer(29, gear: bow_gear(weapon)), siala)) == 15,
               "#{weapon} на Сиале"

        # ⚠️ Владение на ванили не спрашивается вовсе (сиальских фитов там нет),
        # поэтому то же снаряжение годится обоим.
        assert enchant(Rules.compute(archer(29, gear: bow_gear(weapon)), vanilla)) == 0,
               "#{weapon} на ванили"
      end

      # Положительный контроль к нулю: лук на ванили считается, то есть ноль
      # выше — про арбалет, а не про сломанную запись.
      assert enchant(Rules.compute(archer(29, gear: bow_gear(:longbow)), vanilla)) == 15
    end

    # 🔴 Сторона капа названа ПРЯМОЙ цитатой источника: «The enchant arrow bonus
    # does not count towards the +20 attack bonus cap». Проверяется не полем,
    # а числом: клип на 12 съедает внутрикапное и не трогает эти +15.
    test "+15 не режется капом +20, даже когда клип кусает", %{ruleset: ruleset} do
      loose = Rules.compute(archer(29, gear: bow_gear(:longbow)), ruleset)

      tight =
        Rules.compute(
          archer(29,
            gear:
              Gear.new(weapon: :longbow, weapon_attack: 20, feats: [:siala_ranged_proficiency])
          ),
          ruleset
        )

      # Внутри капа здесь бонус за тип оружия (+6) и число самого предмета:
      # у `loose` это 6 + 0, у `tight` — 6 + 20 = 26, срезанные до 20.
      # ⚠️ Расового бонуса нет: Тёмный эльф (`:elf`) прибавки к атаке
      # не получает, её получает Светлый (`:half_elf`).
      assert loose.attack_cap_clipped == 0
      assert tight.attack_cap_clipped == -6

      # Прибавка та же по обе стороны клипа, и AB отличается ровно на то,
      # что клип оставил от внутрикапного (20 − 6), — то есть +15 в срез
      # не попали ни разу.
      assert enchant(loose) == 15
      assert enchant(tight) == 15
      assert tight.attack_bonus - loose.attack_bonus == 14
    end

    test "величина, состав и сторона капа лежат в данных", %{ruleset: siala, vanilla: vanilla} do
      record = Enum.find(siala.attack_bonuses.applied, &(&1.id == :enchant_arrow))

      assert record.amount.kind == :attack_at_class_level
      assert record.amount.class == :arcane_archer
      assert record.amount.attack_at_class_level[29] == 15

      assert record.weapon_kind ==
               {:one_of, MapSet.new([:longbow, :shortbow, :light_crossbow, :heavy_crossbow])}

      assert Enum.find(vanilla.attack_bonuses.applied, &(&1.id == :enchant_arrow)).weapon_kind ==
               {:one_of, MapSet.new([:longbow, :shortbow])}

      refute record.cap.inside?
      refute record.cap.assumed?
    end

    # Обратный контроль: без уровней Тайного лучника ни прибавки, ни оговорки —
    # фит выдаёт класс, и у того, кто класс не брал, спрашивать нечего.
    test "билд без Тайного лучника оговорки не несёт", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 41), gear: bow_gear(:longbow)),
          ruleset
        )

      assert enchant(stats) == 0
      refute {:not_modelled, {:attack_bonus_weapon, :enchant_arrow}} in stats.gaps
    end
  end

  describe "Weapon Finesse — формула, а не прибавка" do
    # 🔴 Обязательная проверка задания: атака по-прежнему считается от DEX
    # и НИЧЕГО не удвоилось. Finesse учтён `Rules.Attack` (хук на смену
    # характеристики), и в разметке у него вердикт `counted_elsewhere` — то
    # есть ни терма, ни гэпа он приносить не должен.
    test "атака остаётся от DEX, и терма от Finesse нет", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: [:fighter],
          base_abilities: %{@flat | dex: 16},
          race: :human,
          feats: %{1 => %{general: :weapon_finesse}}
        )

      stats = Rules.compute(build, ruleset)

      assert stats.attack_ability == :dex
      # BAB 1 + DEX +3, и ни единицы сверх.
      assert stats.attack_bonus == 4
      assert stats.own_attack_bonus == 0
      assert stats.own_attack_terms == []
      assert attack_gaps(stats) == []

      # Допущение про подходящее оружие — на месте, и оно ОДНО: вторая копия
      # с нашей стороны была бы вторым сообщением об одном и том же.
      assert Enum.count(stats.gaps, &(&1 == {:assumed, :finessable_weapon})) == 1
    end

    # 🔴 Обязательная проверка правки 14.08.2026: смена характеристики — это
    # ЭФФЕКТ, значит правило смотрит на ВЛАДЕНИЕ фитом, а не на потраченный слот.
    #
    # До правки `Rules.Attack.ability/5` (тогда /3) читала `Build.feats_taken/2`, и
    # `Weapon Finesse` с надетой вещи не делал ничего: воин 10 с STR 10 и DEX 18
    # показывал AB 10 вместо 14. Молча — фит при этом считали все остальные
    # читатели ядра (HP, сейвы, AC ходят в `Build.feats_owned/3`), расходился
    # только хук на формулу.
    #
    # Источники: эффект фита с вещи считается — Dan 09.08.2026 («если фит есть,
    # допустим тафнес, то и HP будут увеличены»); замер H7 от 14.08.2026 сузил
    # ДРУГУЮ половину — требование другого ФИТА, — а здесь ничьих требований
    # не спрашивают. Само правило: `fandom:Weapon finesse` через
    # `siala_41/overrides.json` → `formulas.attack_ability`.
    #
    # Таблица одним тестом, чтобы три строки нельзя было развести по разным
    # ожиданиям, плюс отрицательный контроль: при STR ≥ DEX не переключается
    # ничего — иначе тест зеленел бы и на модели «всегда DEX».
    test "Finesse переключает атаку на DEX и слотом, и с вещи — но не когда STR выше",
         %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 10)
      nimble = %{@flat | dex: 18}

      table = [
        # {откуда фит, характеристики, ожидаемая характеристика атаки, AB}
        {:slot, nimble, :dex, 14},
        {:gear, nimble, :dex, 14},
        {:none, nimble, :str, 10},
        # Отрицательный контроль: сила не ниже ловкости — правило не срабатывает
        # ни по одному источнику, и допущения про оружие тоже нет.
        {:slot, %{@flat | str: 18, dex: 18}, :str, 14},
        {:gear, %{@flat | str: 18, dex: 18}, :str, 14}
      ]

      for {source, abilities, expected_ability, expected_ab} <- table do
        fields =
          case source do
            :slot -> [feats: %{1 => %{general: :weapon_finesse}}]
            :gear -> [gear: Gear.new(feats: [:weapon_finesse])]
            :none -> []
          end

        stats =
          Rules.compute(
            Build.new([levels: levels, base_abilities: abilities, race: :human] ++ fields),
            ruleset
          )

        assert stats.attack_ability == expected_ability,
               "#{source}, DEX #{abilities.dex} против STR #{abilities.str}"

        assert stats.attack_bonus == expected_ab, "#{source}: AB"

        # Допущение про подходящее оружие — ровно там, где правило сработало,
        # и по обоим источникам одинаково.
        assumed = Enum.count(stats.gaps, &(&1 == {:assumed, :finessable_weapon}))
        assert assumed == if(expected_ability == :dex, do: 1, else: 0)
      end
    end

    # ⚠️ Классовой выдачи `Weapon Finesse` в данных НЕТ ни на одном ruleset'е —
    # обход `granted_feats` всех 23 классов (и расовых `bonus_feats`) не нашёл
    # ни одного из фитов хука. То есть третий маршрут владения сегодня мёртв,
    # и проверять его на настоящих данных нечем: тест на них зеленел бы и
    # у сломанного кода. Поэтому выдача заводится синтетически — проверяется
    # МАРШРУТ, а не игровой факт, и выдуманного числа в ожидании нет.
    #
    # Тест перестанет быть синтетическим в тот день, когда шард выдаст Finesse
    # классом; до тех пор он держит `feats_owned/3` от сужения обратно к слотам.
    test "фит, ВЫДАННЫЙ классом, переключает атаку так же (маршрут, синтетика)",
         %{ruleset: ruleset} do
      refute Enum.any?(ruleset.classes, fn {_id, class} ->
               Enum.any?(class.granted_feats, fn {_lv, ids} -> :weapon_finesse in ids end)
             end),
             "класс стал выдавать Weapon Finesse — синтетику пора заменить настоящим билдом"

      granting =
        update_in(ruleset, [Access.key!(:classes), :fighter, :granted_feats], fn by_level ->
          Map.update(by_level, 1, [:weapon_finesse], &[:weapon_finesse | &1])
        end)

      build = build(List.duplicate(:fighter, 10), base_abilities: %{@flat | dex: 18})

      assert Rules.compute(build, ruleset).attack_ability == :str
      assert Rules.compute(build, granting).attack_ability == :dex
      assert Rules.compute(build, granting).attack_bonus == 14
    end

    # 🔴 `Zen archery` — второй фит того же вида, и до 14.08.2026 он В МОДЕЛИ НЕ
    # ДЕЛАЛ НИЧЕГО: в `overrides.json` → `attack_ability.rules` лежало одно
    # правило, `Weapon Finesse`. Монах 10 с WIS 18, STR 10 и длинным луком
    # получал атаку от силы — на 4 меньше, чем даёт игра, и без единой оговорки.
    #
    # Источник (`fandom:Zen archery`, revid 66323), дословно: «Wisdom guides the
    # character's ranged attacks, letting them use their wisdom modifier, if it
    # is higher, instead of their dexterity when firing ranged weapons». Три
    # утверждения, и таблица ниже проверяет все три:
    #
    #   * заменяется ЛОВКОСТЬ, а не сила («instead of their dexterity»);
    #   * только если мудрость выше («if it is higher»);
    #   * только с дальнобойным оружием в руках («when firing ranged weapons»).
    #
    # ⚠️ Третье — ПРОВЕРЯЕМОЕ условие, а не допущение: оружие в билде есть
    # с задачи 3.5 (часть B), а дальнобойность лежит полем справочника. Поэтому
    # «с луком» и «с мечом» стоят ОДНОЙ таблицей: порознь каждая половина
    # зеленела бы и у неверной модели («всегда WIS» проходит первую, «никогда
    # WIS» — вторую).
    #
    # ⚠️ Метательное оружие — дальнобойное ПО ИСТОЧНИКУ, а не по нашему
    # толкованию: «Ranged weapons either can be missile weapons … or can be
    # throwing weapons» (`fandom:Ranged weapon`), плюс заметка самой страницы
    # фита («the description is correct in stating „ranged weapons“»). Поэтому
    # дротик в таблице — не лишняя строка, а единственная проверка того, что
    # условие читает поле справочника, а не слово «лук».
    test "Zen archery переключает атаку на WIS — но только с дальнобойным в руках",
         %{ruleset: ruleset} do
      # Владение обязательно, иначе оружие в руках не засчитывается вовсе
      # (`Rules.GearWeapon`) — и тест зеленел бы по неверной причине.
      table = [
        # {что в руках, владение, характеристики, ожидаемая характеристика, AB}
        {:longbow, :siala_ranged_proficiency, %{@flat | wis: 18}, :wis, 14},
        {:dart, :siala_ranged_proficiency, %{@flat | wis: 18}, :wis, 14},
        {:longsword, :siala_blade_proficiency, %{@flat | wis: 18}, :str, 10},
        {nil, nil, %{@flat | wis: 18}, :str, 10},
        # «Если мудрость выше» — контроль в обе стороны: ловкость выше мудрости,
        # и правило молчит. ⚠️ Ухудшать оно при этом не имеет права.
        #
        # ⚠️ Ожидание правлено задачей 3.34 (15.08.2026): здесь стояло
        # `{:str, 10}`, потому что дефолт был один на всё и назывался силой.
        # Замер N1 сделал дальний бросок ловкостью, и молчание правила теперь
        # значит «остаёмся на том, что дал лук», а не «падаем в силу».
        {:longbow, :siala_ranged_proficiency, %{@flat | dex: 18}, :dex, 14}
      ]

      for {weapon, proficiency, abilities, expected_ability, expected_ab} <- table do
        gear =
          if weapon,
            do: Gear.new(weapon: weapon, feats: [proficiency]),
            else: %Gear{}

        stats =
          Rules.compute(
            Build.new(
              levels: List.duplicate(:monk, 10),
              base_abilities: abilities,
              race: :human,
              alignment: :lawful_good,
              feats: %{1 => %{general: :zen_archery}},
              gear: gear
            ),
            ruleset
          )

        assert stats.attack_ability == expected_ability, "#{inspect(weapon)}: характеристика"
        assert stats.attack_bonus == expected_ab, "#{inspect(weapon)}: AB"

        # Прибавкой фит не стал и стать не должен — это смена характеристики,
        # и разметка помечает его `counted_elsewhere` ровно поэтому.
        assert stats.own_attack_bonus == 0
      end
    end

    # Отрицательный контроль к первой строке таблицы выше: без фита тот же лучник
    # с той же мудростью мудрости НЕ получает. Без него «WIS с луком» зеленело бы
    # и у модели, которая просто всегда берёт наибольший модификатор.
    #
    # ⚠️ Ожидание правлено задачей 3.34 (15.08.2026): здесь стояло `:str`, и
    # с приходом дальнего дефолта это стало `:dex` — характеристика сменилась,
    # а СМЫСЛ контроля нет, и именно поэтому он остался. Число при этом не
    # двинулось (у плоских характеристик и сила, и ловкость дают 0), так что
    # проверяет он ровно одно: мудрость 18 без фита не приезжает никуда.
    test "без фита лук ничего не переключает", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          Build.new(
            levels: List.duplicate(:monk, 10),
            base_abilities: %{@flat | wis: 18},
            race: :human,
            alignment: :lawful_good,
            gear: Gear.new(weapon: :longbow, feats: [:siala_ranged_proficiency])
          ),
          ruleset
        )

      assert stats.attack_ability == :dex
      assert stats.attack_bonus == 10
    end

    # 🔴 Третий ответ про оружие — «не сказано», и он не то же самое, что «нет».
    # Билд без оружия в «Вещах» правило не применяет (занижение обнаружимо,
    # завышение — нет: `_weapon_decision` в разметке), но говорит об этом вслух.
    #
    # ⚠️ И только там, где ответ от этого сдвинулся бы: у монаха с мудростью
    # не выше силы оговорка была бы шумом про вопрос, который не возникает.
    test "оружие не названо — правило молчит, но билд об этом говорит", %{ruleset: ruleset} do
      caveat = {:not_modelled, {:attack_ability_weapon, :zen_archery}}

      archer =
        Build.new(
          levels: List.duplicate(:monk, 10),
          base_abilities: %{@flat | wis: 18},
          race: :human,
          alignment: :lawful_good,
          feats: %{1 => %{general: :zen_archery}}
        )

      assert caveat in Rules.compute(archer, ruleset).gaps

      # Мудрость не выше силы — сказать нечего: с луком в руках ответ был бы
      # тот же самый.
      dull = %Build{archer | base_abilities: %{@flat | str: 18, wis: 18}}
      refute caveat in Rules.compute(dull, ruleset).gaps

      # Оружие названо — вопрос закрыт, и оговорки нет ни с луком, ни с мечом.
      for {weapon, proficiency} <- [
            {:longbow, :siala_ranged_proficiency},
            {:longsword, :siala_blade_proficiency}
          ] do
        armed = %Build{archer | gear: Gear.new(weapon: weapon, feats: [proficiency])}
        refute caveat in Rules.compute(armed, ruleset).gaps, "#{weapon}"
      end
    end

    # 🔴 ЭТОТ ТЕСТ УПАЛ 15.08.2026 ЗАДАЧЕЙ 3.34, И ЭТО ПРАВИЛЬНОЕ ПАДЕНИЕ.
    #
    # Он закреплял следствие, которое выглядело багом и багом не являлось: у
    # билда с луком в руках взятие `Zen archery` ПОНИЖАЛО показанное AB (14 → 13
    # у воина ниже). Причина была не в правиле, а в том, чего модель не знала:
    # дальняя атака считается от ЛОВКОСТИ, а `default` был один на всё и он про
    # ближний бой. Собственный комментарий теста называл и день, и число: «тест
    # упадёт в тот день, когда у хука появится дальняя характеристика по
    # умолчанию (замер N1) — тогда 14 обязано стать 10, а не остаться».
    #
    # Замер пришёл (Dan, 15.08.2026), дальний дефолт заведён — и оба числа стали
    # ровно теми, что тот комментарий называл игровыми: **10 без фита и 13
    # с фитом**. То есть понижать больше нечему: правило сравнивает мудрость
    # с ловкостью, как и написано в источнике, а не с силой, которой у лучника
    # в броске нет вовсе.
    #
    # ⚠️ Тест оставлен, а не удалён вместе с багом: он единственный держит
    # утверждение «взятие фита не может ухудшить число», и сегодня оно проверяемо
    # на билде, где сила выше обеих участвующих характеристик.
    test "с луком фит больше не ПОНИЖАЕТ наше AB — дырка default'а закрыта замером",
         %{ruleset: ruleset} do
      abilities = %{@flat | str: 18, wis: 16}

      archer = fn feats ->
        Build.new(
          levels: List.duplicate(:fighter, 10),
          base_abilities: abilities,
          race: :human,
          feats: feats,
          gear: Gear.new(weapon: :longbow, feats: [:siala_ranged_proficiency])
        )
      end

      without = Rules.compute(archer.(%{}), ruleset)
      with_zen = Rules.compute(archer.(%{1 => %{general: :zen_archery}}), ruleset)

      # Сила 18 в руках с луком не участвует вовсе — ни до фита, ни после.
      assert {without.attack_ability, without.attack_bonus} == {:dex, 10}
      assert {with_zen.attack_ability, with_zen.attack_bonus} == {:wis, 13}
      assert with_zen.attack_bonus > without.attack_bonus
    end

    # 🔴 Замер N1 (Dan, 15.08.2026), обе половины одним предложением: «по
    # умолчанию для дальнобойного оружие AB считается от мода ловкости, а не
    # силы. Как только берешь zen archery — начинается считаться от мудрости».
    #
    # Билд заказанного кейса: воин-человек 3 с `STR 8 / DEX 14 / WIS 18`. Три
    # числа, и порознь ни одно из них ничего не доказывает — меч отделяет
    # ближний бой от дальнего, лук без фита проверяет сам дефолт, лук с фитом —
    # что правило меряется от НОВОГО дефолта, а не от старого.
    #
    # ⚠️ Билд собирается ПО ОДНОМУ ЛЕВЕЛАПУ через `validate_level_up/3`
    # (CLAUDE.md §3): список классов, засунутый в `Build.new/1`, валидацию
    # не проходит вовсе, и на этом уже обжигались.
    test "замер N1: воин 3 STR 8 / DEX 14 / WIS 18 — меч 2, лук 5, лук с Zen archery 7",
         %{ruleset: ruleset} do
      abilities = %{str: 8, dex: 14, con: 8, int: 8, wis: 18, cha: 8}

      empty =
        Build.new(
          levels: [],
          base_abilities: abilities,
          race: :human,
          alignment: :true_neutral
        )

      # По одному уровню, и каждый — через валидацию.
      level_up = fn build, class ->
        assert Rules.validate_level_up(build, %{class: class}, ruleset) == :ok
        Build.add_level(build, class)
      end

      %Build{} =
        fighter_3 = Enum.reduce(1..3, empty, fn _level, build -> level_up.(build, :fighter) end)

      # Оба владения помещаются бесплатно: у человека на 1-м уровне три слота
      # (общий, расовый, бонус воина), и общий остаётся под `Zen archery`.
      proficiencies = %{
        1 => %{
          {:class_bonus, :fighter} => :siala_ranged_proficiency,
          racial: :siala_blade_proficiency
        }
      }

      # Требования фита проверяются там же, где их проверит игрок: BAB +3 и
      # WIS 13 выполняются ровно на третьем уровне.
      armed = %Build{fighter_3 | feats: proficiencies}
      assert Rules.validate_feat(armed, %{feat: :zen_archery, at: 3}, ruleset) == :ok

      zen = %Build{armed | feats: Map.put(proficiencies, 3, %{general: :zen_archery})}

      ab = fn %Build{} = build, weapon ->
        stats = Rules.compute(%Build{build | gear: Gear.new(weapon: weapon)}, ruleset)
        {stats.attack_ability, stats.attack_bonus}
      end

      # BAB воина на Сиале — полный, то есть 3 на третьем уровне.
      assert Rules.compute(armed, ruleset).base_attack == 3

      assert ab.(armed, :longsword) == {:str, 2}
      assert ab.(armed, :longbow) == {:dex, 5}
      assert ab.(zen, :longbow) == {:wis, 7}

      # И меч у владельца фита ничего не меняет: условие правила — оружие
      # в руках, а не наличие фита.
      assert ab.(zen, :longsword) == {:str, 2}
    end

    # ⚠️ Ruleset больше НЕ говорит «Zen archery не применяем»: правило заведено,
    # а печатать «не считаем» про посчитанное запрещено так же прямо, как
    # обратное (CLAUDE.md §6). Форма снята из `Rules.Vocabulary` целиком.
    test "гэпа «Zen archery не применяем» у ruleset'а больше нет", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      refute {:not_modelled, :zen_archery} in ruleset.gaps
      refute {:not_modelled, :zen_archery} in vanilla.gaps

      assert Enum.map(ruleset.attack_ability.rules, & &1.feat) == [
               :weapon_finesse,
               :zen_archery
             ]
    end

    # ⚠️ И то же самое про сам дефолт (задача 3.34): в `overrides.json` лежала
    # запись `not_modelled.ranged_attack_ability` — «в игре дальняя атака
    # считается от ЛОВКОСТИ, а у нас `default` один на всё». Замер сделан,
    # дефолт заведён, запись снята. Ruleset обязан нести дальний дефолт
    # на ОБОИХ ruleset'ах: правило ванильное, а `formulas` — общая секция.
    test "дальний дефолт есть у обоих ruleset'ов, и он один", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      for hook <- [ruleset.attack_ability, vanilla.attack_ability] do
        assert hook.default == :str
        assert hook.weapon_defaults == [%{weapon_must_be: :ranged, ability: :dex}]
      end
    end
  end

  # 🔴 Задача 3.34: от какой характеристики считается бросок ДО фитов — свойство
  # того, что в руках, а не константа. Замер N1 (Dan, 15.08.2026).
  #
  # Эти проверки намеренно НЕ про `Zen archery`: до 15.08.2026 весь дальний бой
  # в модели существовал только через него, и легко решить, что дефолт — деталь
  # его правила. Ни один билд ниже фитов хука не имеет вовсе.
  describe "характеристика броска до фитов зависит от оружия в руках" do
    setup do
      %{ruleset: Data.ruleset!("siala_41")}
    end

    @unstated {:not_modelled, {:attack_ability_default, :ranged}}

    # Лучник без единого фита: сила 8, ловкость 18. До правки он получал силу,
    # то есть AB на 5 меньше игрового.
    test "лук считает атаку от ловкости, меч — от силы, и фитов для этого не нужно",
         %{ruleset: ruleset} do
      abilities = %{@flat | str: 8, dex: 18}

      answer = fn weapon, proficiency ->
        stats =
          Rules.compute(
            Build.new(
              levels: List.duplicate(:fighter, 10),
              base_abilities: abilities,
              race: :human,
              gear: Gear.new(weapon: weapon, feats: [proficiency])
            ),
            ruleset
          )

        {stats.attack_ability, stats.attack_bonus, @unstated in stats.gaps}
      end

      # BAB воина 10, модификаторы −1 и +4.
      assert answer.(:longbow, :siala_ranged_proficiency) == {:dex, 14, false}
      assert answer.(:dart, :siala_ranged_proficiency) == {:dex, 14, false}
      assert answer.(:longsword, :siala_blade_proficiency) == {:str, 9, false}
    end

    # 🔴 Оговорка — про НЕСКАЗАННОЕ, и она обязана появляться в ОБЕ стороны.
    # Занижение игрок увидит сам («почему у меня в игре больше?»), а завышение
    # изнутри инструмента невидимо — ровно тот довод, которым в этом проекте
    # решён и `_weapon_decision` в разметке прибавок.
    test "оружие не названо — считаем ближний бой и говорим об этом", %{ruleset: ruleset} do
      stats = fn abilities ->
        Rules.compute(
          Build.new(
            levels: List.duplicate(:fighter, 10),
            base_abilities: abilities,
            race: :human
          ),
          ruleset
        )
      end

      # Занижаем: настоящий лучник получил бы +4, а мы дали −1.
      understated = stats.(%{@flat | str: 8, dex: 18})
      assert {understated.attack_ability, understated.attack_bonus} == {:str, 9}
      assert @unstated in understated.gaps

      # Завышаем: с луком в руках было бы 10, а мы показываем 14.
      overstated = stats.(%{@flat | str: 18, dex: 10})
      assert {overstated.attack_ability, overstated.attack_bonus} == {:str, 14}
      assert @unstated in overstated.gaps

      # А когда число от ответа не зависит — молчим: оговорка про вопрос,
      # который не возникает, это шум.
      same = stats.(%{@flat | str: 18, dex: 18})
      assert {same.attack_ability, same.attack_bonus} == {:str, 14}
      refute @unstated in same.gaps
    end

    # ⚠️ Побочное следствие правки 3.34, и его надо держать: билд с луком
    # не получает оговорки «оружие лёгкое». ⚠️ ПРИЧИНА У НЕГО СМЕНИЛАСЬ
    # 17.08.2026, и это важнее самого утверждения: тогда правило срабатывало
    # и попадало на ту же ловкость, которую лук и так дал (то есть не двигало
    # числа), а теперь лука просто нет в списке финессируемого — правило
    # не срабатывает вовсе. Число одно, механизм другой.
    #
    # 🔴 ВТОРАЯ ПОЛОВИНА ТЕСТА ПЕРЕПИСАНА ТЕМ ЖЕ ДНЁМ (замер S10), и это
    # правильное падение. Здесь стояло «с мечом правило ДЕЙСТВИТЕЛЬНО меняет
    # ответ… и допущение на месте»: длинный меч не финессится ни на одной вики,
    # а мы считали его атаку от ловкости — то есть тест закреплял ровно тот баг,
    # ради которого допущение и снимали.
    test "Finesse с луком не добавляет допущения — под ответом лежит не он", %{
      ruleset: ruleset
    } do
      archer = fn gear ->
        Rules.compute(
          Build.new(
            levels: List.duplicate(:fighter, 10),
            base_abilities: %{@flat | str: 8, dex: 18},
            race: :human,
            feats: %{1 => %{general: :weapon_finesse}},
            gear: gear
          ),
          ruleset
        )
      end

      with_bow = archer.(Gear.new(weapon: :longbow, feats: [:siala_ranged_proficiency]))
      with_sword = archer.(Gear.new(weapon: :longsword, feats: [:siala_blade_proficiency]))
      with_dagger = archer.(Gear.new(weapon: :dagger, feats: [:siala_blade_proficiency]))

      assert with_bow.attack_ability == :dex
      refute {:assumed, :finessable_weapon} in with_bow.gaps

      # Длинного меча в списке нет — правило молчит, и атака остаётся силовой
      # (−1 против ловкости +4, то есть разница видна в числе, а не только
      # в имени характеристики).
      assert {with_sword.attack_ability, with_sword.attack_bonus} == {:str, 9}
      refute {:assumed, :finessable_weapon} in with_sword.gaps

      # Положительный контроль тем же билдом: кинжал в списке есть, и там
      # правило срабатывает — тоже без оговорки, потому что проверено.
      assert {with_dagger.attack_ability, with_dagger.attack_bonus} == {:dex, 14}
      refute {:assumed, :finessable_weapon} in with_dagger.gaps
    end
  end

  # 🔴 Замер S10 (Dan, 17.08.2026). Страница Сиалы перечисляет финессируемое
  # оружие ПОИМЁННО — 13 предметов против 11 у Fandom, — и два добавленных
  # (боевой посох и копьё) двуручные. Значит либо шард снял ванильный запрет
  # «двуручным не финессится», либо это исключения; числа расходятся на билде
  # малой расы с рапирой, и Dan его собрал:
  #
  #   «провел тест: Weapon Finesse на рапиру на карлике не работает! Похоже
  #    нужно ограничение на двуручное оружие, но с исключением в виде посоха
  #    и копья».
  #
  # ⚠️ До правки правило работало ЛЮБЫМ оружием с допущением
  # {:assumed, :finessable_weapon} — то есть билд с двуручным мечом считал атаку
  # от ловкости. Допущение стояло с тех пор, когда оружия в модели не было вовсе.
  describe "Weapon Finesse — список оружия и запрет на двуручное" do
    setup do
      %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
    end

    # Сила 8 против ловкости 18: правило сдвигает AB на 5, поэтому «сработало»
    # и «не сработало» различаются ЧИСЛОМ, а не только именем характеристики.
    defp finessing(race, weapon, proficiency, ruleset) do
      gear =
        if weapon,
          do: Gear.new(weapon: weapon, feats: List.wrap(proficiency)),
          else: %Gear{}

      stats =
        Rules.compute(
          Build.new(
            levels: List.duplicate(:fighter, 10),
            base_abilities: %{@flat | str: 8, dex: 18},
            race: race,
            feats: %{1 => %{general: :weapon_finesse}},
            gear: gear
          ),
          ruleset
        )

      {stats.attack_ability, stats.attack_bonus, {:assumed, :finessable_weapon} in stats.gaps}
    end

    # 🔴 Дословная половина замера, и обе строки обязаны стоять вместе: порознь
    # каждая зеленеет и у неверной модели («рапира не финессится никогда»
    # проходит первую, «финессится всегда» — вторую).
    #
    # ⚠️ «Карлик» = Gnome (CLAUDE.md §4), малая раса. Рапира среднего размера,
    # у малого владельца она двуручная (`Rules.Wield`, задача 3.43) — то есть
    # число здесь считает правило размеров, а не список исключений.
    #
    # ⚠️ До задачи 3.143 (30.08.2026) здесь стояло «Девятка у обоих —
    # СОВПАДЕНИЕ»: у человека с рапирой BAB 10 и сила 8 (−1) = 9, у Карлика —
    # BAB 10, сила 6 после расового −2 (то есть −2) и +1 размерного
    # модификатора = тоже 9, разными путями. `Small stature` стал
    # `not_modelled` (цитата была обрезана перед условием «когда противник
    # крупнее персонажа»), совпадение распалось: у Карлика теперь 8, а не 9.
    test "рапира: у человека финессится, у Карлика нет", %{ruleset: ruleset} do
      assert finessing(:human, :rapier, :siala_blade_proficiency, ruleset) == {:dex, 14, false}
      assert finessing(:gnome, :rapier, :siala_blade_proficiency, ruleset) == {:str, 8, false}

      # ⚠️ Контроль: до задачи 3.143 тот же Карлик с кинжалом получал 15 —
      # число человека (14) плюс размерный модификатор. Small stature больше
      # не считается, и число совпадает с человеческим — контроль на
      # различие расой заменён контролем на совпадение оружием.
      assert finessing(:gnome, :dagger, :siala_blade_proficiency, ruleset) == {:dex, 14, false}
    end

    # Таблица по всему списку: что в нём — работает, чего нет — нет, и запрет
    # на двуручное кусает только там, где источник не вывел оружие поимённо.
    test "список из 13 работает, всё остальное — нет", %{ruleset: ruleset} do
      table = [
        # {оружие, владение, ожидание}
        # Из списка, одноручное всем: правило срабатывает.
        {:dagger, :siala_blade_proficiency, {:dex, 14, false}},
        {:kukri, :siala_blade_proficiency, {:dex, 14, false}},
        {:handaxe, :siala_axe_proficiency, {:dex, 14, false}},
        {:whip, :siala_hammer_proficiency, {:dex, 14, false}},
        # Удар без оружия — тоже строка списка, и владения не требует.
        {:unarmed_strike, nil, {:dex, 14, false}},
        # 🔴 Два сиальских исключения: оба ДВУРУЧНЫЕ (размер large — то есть
        # у любого персонажа), и оба финессятся, потому что страница называет
        # их сама.
        {:quarterstaff, :siala_polearm_proficiency, {:dex, 14, false}},
        {:spear, :siala_polearm_proficiency, {:dex, 14, false}},
        # Не из списка, одноручное: отказ по СПИСКУ, а не по хвату.
        {:longsword, :siala_blade_proficiency, {:str, 9, false}},
        # Не из списка и двуручное — то, ради чего правку и заказывали.
        {:greatsword, :siala_blade_proficiency, {:str, 9, false}},
        # Из семейства «почти финессируемое»: двусторонняя булава — не булава.
        # ⚠️ Владение у неё древковое, а не молотовое: у Сиалы комбинированное
        # оружие лежит в древковых, и с чужим фитом она бы просто не считалась
        # в руках — тест зеленел бы по неверной причине.
        # ⚠️ Число 5, а не 9, с 28.08.2026 (задача 3.132), и характеристика
        # та же: двустороннее оружие само по себе ставит персонажа в бой двумя
        # оружиями («Wielding a double-sided weapon automatically causes one
        # to be dual-wielding … and incurring the standard dual-wielding
        # penalties»), а его второй конец считается лёгким — то есть −4
        # главной руке. Проверяемое здесь правило (какая характеристика) этим
        # не задето вовсе.
        {:dire_mace, :siala_polearm_proficiency, {:str, 5, false}},
        # А обычная булава — в списке.
        {:mace, :siala_hammer_proficiency, {:dex, 14, false}}
      ]

      for {weapon, proficiency, expected} <- table do
        assert finessing(:human, weapon, proficiency, ruleset) == expected, "#{weapon}"
      end
    end

    # ⚠️ Допущение снято не целиком, и остаток честный: у билда, который оружия
    # не назвал, проверять нечего. Правило при этом СРАБАТЫВАЕТ — в отличие от
    # `Zen archery`, которому нужен лук: удар без оружия в списке есть, то есть
    # персонаж с пустыми руками финессит в любом случае.
    test "оружие не названо — правило работает и говорит, чем за это заплачено", %{
      ruleset: ruleset
    } do
      assert finessing(:human, nil, nil, ruleset) == {:dex, 14, true}

      # И у малой расы то же самое: без названного оружия хват спрашивать не
      # у чего. ⚠️ Именно поэтому оговорка и остаётся — ответ может быть
      # и рапирой, которой этому персонажу нельзя. (14, как у человека — до
      # задачи 3.143, 30.08.2026, было 15: +1 размерного модификатора Карлика
      # к броску атаки. Small stature стал not_modelled, своей прибавки нет.)
      assert finessing(:gnome, nil, nil, ruleset) == {:dex, 14, true}

      # ⚠️ И то же самое у билда, который оружие НАЗВАЛ, но держать его не может:
      # `GearWeapon.held/2` такое оружие не отдаёт вовсе, значит и хука оно
      # не касается. Отказ игрок при этом видит — своей строкой, а не через
      # молчание атаки.
      too_large = finessing(:gnome, :greatsword, :siala_blade_proficiency, ruleset)
      assert too_large == {:dex, 14, true}
    end

    # 🔴 Ваниль НЕ ТРОГАЕМ: у неё свой список (11) и своё поведение — посох
    # и копьё там не финессятся вовсе, потому что их нет в перечне Fandom.
    # Проверка на обоих ruleset'ах нужна ровно потому, что `formulas` — общая
    # секция: сиальские две строки, положенные туда, оказались бы и здесь.
    test "у ванили список из 11, и посох с копьём в него не входят", %{vanilla: vanilla} do
      assert finessing(:human, :dagger, nil, vanilla) == {:dex, 14, false}
      assert finessing(:human, :quarterstaff, nil, vanilla) == {:str, 9, false}
      assert finessing(:human, :spear, nil, vanilla) == {:str, 9, false}

      # Запрет на двуручное у ванили тот же, и рапира Карлика — его дословный
      # пример со страницы источника.
      # ⚠️ 8, а не 9 (до задачи 3.143, 30.08.2026): правило про Small stature
      # ванильное, и живёт в файле разметки, общем для обоих ruleset'ов.
      assert finessing(:gnome, :rapier, nil, vanilla) == {:str, 8, false}
      assert finessing(:human, :rapier, nil, vanilla) == {:dex, 14, false}
    end

    # Данные, а не поведение: у двух ruleset'ов разные списки и разные
    # исключения, и накладка шарда легла ПОЛЕМ, не заменив правило целиком.
    test "правило одно, а список у каждого ruleset'а свой", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      finesse = fn rs -> Enum.find(rs.attack_ability.rules, &(&1.feat == :weapon_finesse)) end

      assert MapSet.size(finesse.(vanilla).weapon_one_of) == 11
      assert MapSet.size(finesse.(ruleset).weapon_one_of) == 13

      assert MapSet.to_list(finesse.(vanilla).weapon_not_two_handed.except) == []

      assert finesse.(ruleset).weapon_not_two_handed.except ==
               MapSet.new([:quarterstaff, :spear])

      # Накладка меняет ДВА поля и не трогает остальные: характеристика,
      # заменяемая характеристика и условие пришли из ванильной записи.
      for rs <- [vanilla, ruleset] do
        rule = finesse.(rs)
        assert {rule.ability, rule.instead_of, rule.condition} == {:dex, :str, :higher_modifier}
        assert rule.assumes == :finessable_weapon
      end

      # ⚠️ И ни одного имени оружия в самом ядре: правило целиком приходит
      # из данных, поэтому «список» — это множество атомов, а не ветка кода.
      assert MapSet.member?(finesse.(ruleset).weapon_one_of, :quarterstaff)
      refute MapSet.member?(finesse.(vanilla).weapon_one_of, :quarterstaff)
    end

    # ⚠️ Сосед по механизму не задет: у `Zen archery` списка оружия нет вовсе,
    # он спрашивает СВОЙСТВО. Если бы правка свела оба условия в одно, это
    # покраснело бы.
    test "Zen archery остался на свойстве, а не на списке", %{ruleset: ruleset} do
      zen = Enum.find(ruleset.attack_ability.rules, &(&1.feat == :zen_archery))

      assert zen.weapon_must_be == :ranged
      assert zen.weapon_one_of == nil
      assert zen.weapon_not_two_handed == nil

      # И поведение: лук двуручный (`stated_grip` Сиалы), но правило про хват
      # не спрашивает — иначе монах-лучник потерял бы мудрость.
      stats =
        Rules.compute(
          Build.new(
            levels: List.duplicate(:monk, 10),
            base_abilities: %{@flat | wis: 18},
            race: :human,
            alignment: :lawful_good,
            feats: %{1 => %{general: :zen_archery}},
            gear: Gear.new(weapon: :longbow, feats: [:siala_ranged_proficiency])
          ),
          ruleset
        )

      assert stats.attack_ability == :wis
    end
  end

  # 🔴 Сторож на самую дорогую поломку этого хука: правило, которое загрузилось
  # и не срабатывает НИКОГДА. Ровно так `Zen archery` прожил полмесяца — только
  # там его не было вовсе, а опечатка выглядит ещё безобиднее: правило в списке
  # есть, тест «в хуке два правила» зелёный, а фит ничего не делает.
  #
  # Оба падения — про молчание, и направление ошибки у них разное:
  # неизвестное свойство оружия занижает (правило не сработает), а опечатка
  # в имени характеристики ЗАВЫШАЕТ (сравнение с нулём почти всегда истинно).
  describe "загрузчик роняет сборку на битом правиле смены характеристики" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      root = Path.join(dir, "rules")
      File.cp_r!("priv/rules", root)

      %{root: root, path: Path.join([root, "siala_41", "overrides.json"])}
    end

    defp rule!(path, feat, fun) do
      file = path |> File.read!() |> Jason.decode!()

      file
      |> update_in(["formulas", "attack_ability", "rules"], fn rules ->
        for rule <- rules, do: if(rule["feat"] == feat, do: fun.(rule), else: rule)
      end)
      |> Jason.encode!()
      |> then(&File.write!(path, &1))
    end

    # ⚠️ Положительный контроль: нетронутая копия обязана грузиться, иначе
    # `assert_raise` ниже зеленел бы на копии, которая не грузится вовсе.
    test "нетронутая копия грузится и правил в ней два", %{root: root} do
      ruleset = Loader.load!(root)["siala_41"]

      assert Enum.map(ruleset.attack_ability.rules, & &1.feat) == [:weapon_finesse, :zen_archery]
    end

    test "свойство оружия, которого ядро не знает", %{root: root, path: path} do
      rule!(path, "zen_archery", &Map.put(&1, "weapon_must_be", "two_handed"))

      assert_raise RuntimeError, ~r/would never fire/, fn -> Loader.load!(root) end
    end

    test "характеристика написана не тем именем", %{root: root, path: path} do
      rule!(path, "zen_archery", &Map.put(&1, "instead_of", "dexterity"))

      assert_raise RuntimeError, ~r/names ability dexterity/, fn -> Loader.load!(root) end
    end

    # 🔴 И четыре сторожа на условие про ОРУЖИЕ (замер S10). Направление ошибки
    # у них разное, и это главное: незнакомое имя и пустой список ЗАНИЖАЮТ
    # (правило не сработает никогда), а понижение статуса ЗАВЫШАЕТ — условие
    # исчезает, и Finesse снова работает двуручным мечом. Второе изнутри
    # инструмента невидимо, поэтому «отключить понижением» запрещено так же
    # прямо, как у дефолта.
    test "список называет оружие, которого нет в справочнике", %{root: root, path: path} do
      rule!(path, "weapon_finesse", fn rule ->
        put_in(rule, ["weapon_one_of", "weapons"], ["dagger", "sabre"])
      end)

      assert_raise RuntimeError, ~r/could never be satisfied/, fn -> Loader.load!(root) end
    end

    test "список пуст — правило не сработает ни разу", %{root: root, path: path} do
      rule!(path, "weapon_finesse", &put_in(&1, ["weapon_one_of", "weapons"], []))

      assert_raise RuntimeError, ~r/would never fire/, fn -> Loader.load!(root) end
    end

    test "условие про оружие понижено до unclear", %{root: root, path: path} do
      rule!(path, "weapon_finesse", &put_in(&1, ["weapon_one_of", "status"], "unclear"))

      assert_raise RuntimeError, ~r/cannot be half-applied/, fn -> Loader.load!(root) end
    end

    # Исключение из запрета для оружия, которого правило и так не берёт, —
    # мёртвая строка: молча ничего не изменит.
    test "исключение названо мимо списка", %{root: root, path: path} do
      rule!(path, "weapon_finesse", fn rule ->
        put_in(rule, ["weapon_not_two_handed", "except"], ["greatsword"])
      end)

      assert_raise RuntimeError, ~r/exemption would never fire/, fn -> Loader.load!(root) end
    end

    # 🔴 Сиальская накладка (`formulas_shard`) может только ПЕРЕОПРЕДЕЛЯТЬ
    # существующее правило. Опечатка в имени фита иначе дала бы ровно ту
    # поломку, ради которой заведены все сторожа выше: запись в файле есть,
    # а не делает ничего.
    test "накладка шарда называет фит, которого нет в ванильных правилах", %{
      root: root,
      path: path
    } do
      file = path |> File.read!() |> Jason.decode!()

      file
      |> update_in(["formulas_shard", "attack_ability", "rules"], fn rules ->
        for rule <- rules, do: Map.put(rule, "feat", "weapon_finess")
      end)
      |> Jason.encode!()
      |> then(&File.write!(path, &1))

      assert_raise RuntimeError, ~r/lands on nothing/, fn -> Loader.load!(root) end
    end

    # ⚠️ И положительный контроль к самой накладке: снимаем её целиком — оба
    # ruleset'а обязаны остаться с ванильными одиннадцатью. Иначе тест выше
    # зеленел бы и у кода, который сиальский список читает откуда-то ещё.
    test "без накладки у Сиалы остаются ванильные 11", %{root: root, path: path} do
      file = path |> File.read!() |> Jason.decode!()

      file
      |> Map.delete("formulas_shard")
      |> Jason.encode!()
      |> then(&File.write!(path, &1))

      rulesets = Loader.load!(root)

      for name <- ["vanilla", "siala_41"] do
        finesse =
          Enum.find(rulesets[name].attack_ability.rules, &(&1.feat == :weapon_finesse))

        assert MapSet.size(finesse.weapon_one_of) == 11, name
        assert MapSet.to_list(finesse.weapon_not_two_handed.except) == [], name
      end
    end

    # `instead_of` — единственное поле, которому МОЖНО не быть: правило без него
    # сравнивает с `default`, как сравнивали все правила до 14.08.2026.
    test "без instead_of правило сравнивает с default", %{root: root, path: path} do
      rule!(path, "weapon_finesse", &Map.delete(&1, "instead_of"))

      ruleset = Loader.load!(root)["siala_41"]
      finesse = Enum.find(ruleset.attack_ability.rules, &(&1.feat == :weapon_finesse))

      assert finesse.instead_of == nil

      # И поведение то же: у Finesse заменяемая характеристика и `default` — обе
      # сила, поэтому снятие поля не двигает ни одного числа.
      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 10),
            base_abilities: %{@flat | dex: 18},
            feats: %{1 => %{general: :weapon_finesse}}
          ),
          ruleset
        )

      assert stats.attack_ability == :dex
      assert stats.attack_bonus == 14
    end

    # 🔴 И три сторожа на сам ДЕФОЛТ (задача 3.34). У него, в отличие от правил,
    # нет безопасного «не сработало»: не применённая запись не убирает прибавку,
    # а меняет характеристику, от которой считается ВСЁ AB, — и молча.
    defp default!(path, fun) do
      file = path |> File.read!() |> Jason.decode!()

      file
      |> update_in(["formulas", "attack_ability", "default"], fun)
      |> Jason.encode!()
      |> then(&File.write!(path, &1))
    end

    test "дефолта для пустых рук нет вовсе", %{root: root, path: path} do
      default!(path, fn records -> for r <- records, r["weapon_must_be"], do: r end)

      assert_raise RuntimeError, ~r/exactly one is required/, fn -> Loader.load!(root) end
    end

    test "дефолтов для пустых рук два — порядок строк решал бы за правило", %{
      root: root,
      path: path
    } do
      default!(path, fn records ->
        [%{"weapon_must_be" => nil, "ability" => "cha", "status" => "verified"} | records]
      end)

      assert_raise RuntimeError, ~r/exactly one is required/, fn -> Loader.load!(root) end
    end

    # Понижение статуса — не способ отключить дефолт: молча сменилась бы
    # характеристика, а не пропала прибавка.
    test "запись дефолта понижена до unclear", %{root: root, path: path} do
      default!(path, fn records ->
        for r <- records, do: Map.put(r, "status", "unclear")
      end)

      assert_raise RuntimeError, ~r/cannot be half-applied/, fn -> Loader.load!(root) end
    end

    # То же падение, что у правил, и по той же причине: запись, которая
    # не сработает никогда, хуже её отсутствия.
    test "свойство оружия у дефолта, которого ядро не знает", %{root: root, path: path} do
      default!(path, fn records ->
        for r <- records do
          if r["weapon_must_be"], do: Map.put(r, "weapon_must_be", "two_handed"), else: r
        end
      end)

      assert_raise RuntimeError, ~r/would never fire/, fn -> Loader.load!(root) end
    end

    # ⚠️ И форма целиком: одна голая строка вместо списка — это файл до 3.34,
    # и грузиться он не должен, а не «понят как дефолт для всего».
    test "дефолт записан строкой, как до задачи 3.34", %{root: root, path: path} do
      default!(path, fn _records -> "str" end)

      assert_raise RuntimeError, ~r/list of records is required/, fn -> Loader.load!(root) end
    end
  end

  describe "потолок +20 — ОДИН клип, и он покрывает НЕ ВСЕ источники" do
    # 🔴 Обязательная проверка задания (правка 09.08.2026). Dan: «Фиты не входят
    # в кап атаки +20» (`source: user`, на вики этого нет). До этого дня задача
    # 1.12b положила прибавку от фита под кап ПО АНАЛОГИИ с сейвами, где кап на
    # классовое умение подтверждён дословно (`fandom:Uncanny dodge`); для атаки
    # такой цитаты нет, и аналогия оказалась неверной.
    #
    # ⚠️ Потолок опускается искусственно, и это находка, а не удобство теста:
    # **при настоящем ruleset'е кап атаки по-прежнему недостижим.** Максимум,
    # что ядро умеет предложить, — +6 от вещей (кап прибавки характеристики +12
    # даёт +6 к модификатору), +9 расового бонуса сагровика и +1 `Epic prowess`,
    # то есть +16 против 20.
    #
    # ⚠️ Здесь стояло «достижимым кап станет с приходом оружия (задача 3.5)» —
    # снято 15.08.2026 замером Dan (`GAME_CHECKS.md` Q5): числа оружия в кап
    # атаки НЕ входят. Пять дней между 3.5 и замером кап действительно кусал,
    # и это был единственный отрезок, когда он вообще был достижим.
    #
    # 🔴 **С 10.08.2026 (задача 3.22) внутри капа остался РОВНО ОДИН источник —
    # расовый бонус Сиалы.** Dan перечислил состав капа целиком, и модификатора
    # силы там нет ни из какого источника, включая надетые вещи (`GAME_CHECKS.md`
    # кейс J1): «Бонус силы в кап 20 не входит… Получается attack bonus или
    # enchantment bonus оружия, баффы, песня барда, бонус светлого эльфа».
    # Поэтому `gear` вынесен наружу — правы оказались сейвы, где вклад
    # характеристики никогда под кап не попадал.
    test "режется только раса, а вещи и фит ложатся ПОВЕРХ среза", %{ruleset: ruleset} do
      tight = with_attack_cap(ruleset, 8)

      stats = Rules.compute(capped_build(), tight)

      # Предпосылка: все три источника ненулевые и КАЖДЫЙ сам по себе ниже
      # потолка, поэтому раздельные клипы прошли бы незаметно.
      assert stats.gear_attack_bonus == 6
      assert stats.race_attack_bonus == 9
      assert stats.own_attack_bonus == 1

      # Под капом одна раса: 9 → 8 (срезано 1), вещи +6 и фит +1 сверху — 15,
      # а не 9 (вещи внутри капа, как было до 10.08.2026), не 8 (внутри капа
      # ещё и фит, как было до 09.08.2026) и не 16 (клипа нет вовсе).
      assert stats.attack_extra_bonus == 15
      assert stats.attack_cap_clipped == -1
      assert stats.attack_bonus == stats.base_attack + 15
      assert :attack_bonus in stats.capped
    end

    # 🔴 ПОРЧА №1 из задания, и она не комментарий, а тест: правило приходит из
    # данных, поэтому его можно вернуть как было — и число обязано вернуться
    # к прежнему. Тест ловит и обратное: код, который зашил «фит снаружи» мимо
    # данных, здесь покажет 9 вместо 8.
    #
    # ⚠️ Правится ЗАПИСЬ, а не вид источника (правка 09.08.2026, второй заход):
    # сторона капа лежит у `Epic prowess`, потому что вид `{:feat, _}` не
    # различает `Divine grace` и `Sacred defense`.
    test "вернули запись под кап в ruleset'е — вернулось прежнее число", %{ruleset: ruleset} do
      as_before =
        ruleset
        |> with_attack_cap(8)
        |> with_record_cap(:epic_prowess, true)

      stats = Rules.compute(capped_build(), as_before)

      # Под капом раса 9 и фит 1 = 10 → 8 (срезано 2), вещи +6 сверху.
      assert stats.attack_extra_bonus == 14
      assert stats.attack_cap_clipped == -2
    end

    # 🔴 ПОРЧА, обратная предыдущей и заведённая задачей 3.22: вернули под кап
    # ВЕЩИ — число обязано поехать. Она же и единственный способ проверить, что
    # клип по-прежнему ОДИН на несколько внутрикапных источников: на настоящих
    # данных внутри капа источник ровно один, и «клип по половинке» (баг, из-за
    # которого сейвы носили +40, CLAUDE.md §9) сегодня физически не проявляется.
    #
    # ⚠️ Ветка не мёртвая: настоящий внутрикапный источник вещей придёт с задачей
    # 3.5 (attack и enchantment bonus оружия — Dan назвал их отдельными числами,
    # и оба под капом).
    test "вернули вещи под кап — один клип на два источника, а не два клипа", %{
      ruleset: ruleset
    } do
      as_before =
        ruleset
        |> with_attack_cap(8)
        |> put_in([Access.key!(:stat_cap_sources), :attack_bonus, :gear, :inside?], true)

      stats = Rules.compute(capped_build(), as_before)

      # 6 + 9 = 15 предложено потолку 8 → 8 (срезано 7), и +1 от фита сверху:
      # 9, а не 8 (фит внутри капа) и не 8 + 8 + 1 (клип по источнику).
      assert stats.attack_extra_bonus == 9
      assert stats.attack_cap_clipped == -7
    end

    # 🔴 ПОРЧА №4 из задания: признак записи игнорируется, и сторона берётся
    # у ВИДА источника. Здесь она подложена прямо в копию ruleset'а (загрузчик
    # такую копию не собрал бы — вид, у которого есть записи, роняет сборку), и
    # запись обязана победить. Без этого теста код, читающий `covers_source?/3`
    # вместо `covers_record?/3`, зеленел бы: у настоящих данных вид `feat` не
    # назван вовсе, а неназванный по умолчанию считается ВНУТРИ капа — то есть
    # ошибка вернула бы ровно прежнее, неверное поведение.
    test "запись перекрывает вид источника", %{ruleset: ruleset} do
      lying_kind =
        ruleset
        |> with_attack_cap(8)
        |> put_in([Access.key!(:stat_cap_sources), :attack_bonus, :feat], %{
          inside?: true,
          assumed?: false
        })

      stats = Rules.compute(capped_build(), lying_kind)

      # Запись говорит «поверх» — значит поверх, вид ни при чём: под капом одна
      # раса (9 → 8), вещи и фит сверху. Если бы победил вид, фит уехал бы под
      # кап и вышло бы 14 при срезе −2.
      assert Enum.map(stats.own_attack_terms, &{&1.id, &1.under_cap?}) == [{:epic_prowess, false}]
      assert stats.attack_extra_bonus == 15
      assert stats.attack_cap_clipped == -1
    end

    # Обратный контроль: потолок, до которого не дотянулись, не режет ничего и
    # не заявляет, что срезал. Без этой половины тесты выше зеленели бы
    # и у кода, который клипает всегда.
    test "настоящий потолок 20 недостижим — 16 проходит целиком", %{ruleset: ruleset} do
      stats = Rules.compute(capped_build(), ruleset)

      assert ruleset.stat_caps.attack_bonus == 20
      assert stats.gear_attack_bonus + stats.race_attack_bonus + stats.own_attack_bonus == 16
      assert stats.attack_extra_bonus == 16
      assert stats.attack_cap_clipped == 0
      assert stats.attack_bonus == stats.base_attack + 16
      refute :attack_bonus in stats.capped
    end

    # Холостой контроль: ничего не введено, ничего не взято — клипа нет вовсе.
    test "без источников клипа нет", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter]), ruleset)

      assert stats.attack_extra_bonus == 0
      assert stats.attack_cap_clipped == 0
      refute :attack_bonus in stats.capped
    end

    # Собственный терм на одном билде: у Карлика фит (`Epic prowess`), и по
    # слову Dan он лежит ПОВЕРХ капа.
    #
    # ⚠️ **Двумя половинами в ОДНОМ тесте, и это не удобство.** С 10.08.2026
    # у Карлика под капом атаки нет вообще ничего: расового бонуса к атаке
    # у него не бывает, а вещи вынесены наружу (задача 3.22). Значит на настоящих
    # данных среза нет, и «терм лежит ПОСЛЕ среза» проверить нечем — вторая
    # половина возвращает вещи под кап, чтобы срез появился. По отдельности
    # каждая половина зеленела бы и при неверной модели: первая не отличает
    # «поверх капа» от «капа не было», вторая не доказывает, что настоящие данные
    # держат сторону.
    #
    # ⚠️ До задачи 3.143 (30.08.2026) термов здесь было ДВА — `epic_prowess`
    # и `small_stature` (расовая склонность Карлика), и это заодно проверяло,
    # что сторона капа читается у КАЖДОЙ записи, а не выводится из того, что
    # терм «свой» (та же мысль, что у Divine grace / Sacred defense для
    # сейвов). `small_stature` стал `not_modelled` — цитата в разметке была
    # обрезана перед условием «когда противник крупнее персонажа». Единственная
    # оставшаяся применяемая запись без условия — `epic_prowess`; двухзаписную
    # версию этой проверки для атаки заново не собирали, потому что тот же
    # принцип уже держит `CapSidesTest` («Divine grace и Sacred defense — один
    # вид, разные стороны») для сейвов, а здесь сегодня взять вторую запись
    # можно только ценой оружия в руках (`weapon_focus` и родня).
    test "собственный терм ложится поверх среза", %{ruleset: ruleset} do
      build =
        build(List.duplicate(:fighter, 41),
          race: :gnome,
          gear: Gear.new(abilities: %{str: 12}),
          feats: %{21 => %{general: :epic_prowess}}
        )

      # На настоящих сторонах: под капом ноль слагаемых, режется нечему,
      # и терм +1 доезжает целиком вместе с вещами +6.
      as_shipped = Rules.compute(build, with_attack_cap(ruleset, 4))

      assert Enum.map(as_shipped.own_attack_terms, &{&1.id, &1.under_cap?}) == [
               {:epic_prowess, false}
             ]

      assert as_shipped.attack_extra_bonus == 7
      assert as_shipped.attack_cap_clipped == 0
      refute :attack_bonus in as_shipped.capped

      # Вернули вещи под кап: +6 → 4 (срезано 2), терм +1 сверху.
      with_clip =
        Rules.compute(
          build,
          ruleset
          |> with_attack_cap(4)
          |> put_in([Access.key!(:stat_cap_sources), :attack_bonus, :gear, :inside?], true)
        )

      assert Enum.map(with_clip.own_attack_terms, &{&1.id, &1.under_cap?}) ==
               Enum.map(as_shipped.own_attack_terms, &{&1.id, &1.under_cap?})

      assert with_clip.attack_extra_bonus == 5
      assert with_clip.attack_cap_clipped == -2
    end

    # 🔴 ПОРЧА №3 из задания: запись внутрь капа — число обязано поехать.
    # Без этой половины тест выше зеленел бы и у кода, который выносит поверх
    # капа что попало.
    #
    # ⚠️ Потолок здесь **0**, а не 4, и это следствие задачи 3.22: под капом
    # у Карлика не осталось ни одного другого слагаемого, поэтому при потолке 4
    # прибавка +1 не срезалась бы и порча была бы невидимой. Нулевой потолок —
    # единственная величина, при которой единичная прибавка что-то теряет.
    #
    # ⚠️ До задачи 3.143 (30.08.2026) портилась сторона `small_stature`
    # (расовой склонности). Она стала `not_modelled`, у `not_modelled` поле
    # `cap` запрещено вовсе, и `with_record_cap/3` для такой записи — молчаливый
    # no-op (в `.applied` её больше нет). Портить теперь `epic_prowess` —
    # единственную оставшуюся применяемую запись атаки.
    test "epic_prowess внутрь капа — число поехало", %{ruleset: ruleset} do
      build =
        build(List.duplicate(:fighter, 41),
          race: :gnome,
          gear: Gear.new(abilities: %{str: 12}),
          feats: %{21 => %{general: :epic_prowess}}
        )

      broken =
        ruleset
        |> with_attack_cap(0)
        |> with_record_cap(:epic_prowess, true)

      stats = Rules.compute(build, broken)

      # Epic prowess +1 → 0 (срезано 1), поверх остались вещи +6.
      assert stats.attack_extra_bonus == 6
      assert stats.attack_cap_clipped == -1

      # Положительный контроль: нетронутая сторона при том же потолке не режет
      # ничего — иначе тест зеленел бы просто от нулевого потолка.
      as_shipped = Rules.compute(build, with_attack_cap(ruleset, 0))

      assert as_shipped.attack_extra_bonus == 7
      assert as_shipped.attack_cap_clipped == 0
    end
  end

  describe "допущений про сторону капа больше нет" do
    # 🔴 Правка 09.08.2026, вторая за день. До неё `small_stature` считался ВНУТРИ
    # капа как объявленное допущение: слово Dan про фиты склонность не покрывало
    # («взять их на других расах да и на этой нельзя»), а вики говорит про кап
    # только применительно к расовому БОНУСУ Сиалы, и это другой бонус. Теперь
    # склонность названа Dan'ом в списке прямо, и гэп-допущение обязано ИСЧЕЗНУТЬ:
    # печатать «не знаем» про решённое — та же ложная неопределённость, что
    # запрещена CLAUDE.md §6, только наоборот.
    test "у Карлика и Гоблина гэпа про кап атаки нет", %{ruleset: ruleset} do
      for race <- [:gnome, :halfling, :human, :dwarf, :elf, :half_elf, :half_orc] do
        stats = Rules.compute(build([:fighter], race: race), ruleset)

        refute Enum.any?(
                 stats.gaps,
                 &match?({:assumed, {:cap_covers_entry, :attack_bonus, _}}, &1)
               ),
               "#{race}: висит допущение про сторону капа, которую Dan назвал"
      end
    end

    # Положительный контроль к `refute` выше: механизм-то работает. Пометь
    # запись допущением — и билд, который её несёт, скажет об этом вслух,
    # причём независимо от того, режет ли потолок (сегодня он недостижим, и
    # «говорить только когда режет» означало бы не говорить никогда).
    #
    # ⚠️ До задачи 3.143 (30.08.2026) портилась `small_stature` (расовая
    # склонность, гейт — раса). Она стала `not_modelled`, у `not_modelled`
    # поле `cap` запрещено вовсе, и `with_record_assumed/2` для такой записи —
    # молчаливый no-op. Портим теперь `epic_prowess` (гейт — владение фитом,
    # не раса), и «только там, где запись вообще есть» проверяется владением
    # фитом, а не расой.
    test "помеченная допущением запись называет себя гэпом", %{ruleset: ruleset} do
      assumed = with_record_assumed(ruleset, :epic_prowess)
      gap = {:assumed, {:cap_covers_entry, :attack_bonus, :epic_prowess}}

      with_feat = build(List.duplicate(:fighter, 21), feats: %{21 => %{general: :epic_prowess}})

      for rules <- [assumed, with_attack_cap(assumed, 0)] do
        assert gap in Rules.compute(with_feat, rules).gaps
      end

      # …и только там, где фит вообще взят.
      without_feat = build(List.duplicate(:fighter, 21))
      refute gap in Rules.compute(without_feat, assumed).gaps
    end
  end

  describe "атаки в раунд не двигаются" do
    # 🔴 Обязательная проверка задания: число атак фиксирует BAB на 20-м
    # уровне, а не AB (CLAUDE.md §3, подтверждено тремя страницами Fandom).
    # Прибавка к атаке НЕ обязана менять число атак — и не меняет.
    test "Epic prowess число атак не меняет", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 41)
      without = Rules.compute(build(levels), ruleset)

      with_feat =
        Rules.compute(
          build(levels, feats: %{21 => %{general: :epic_prowess}}),
          ruleset
        )

      assert without.attacks_per_round == 4
      assert with_feat.attacks_per_round == 4
      assert with_feat.attack_bonus == without.attack_bonus + 1
      assert with_feat.base_attack_at_20 == without.base_attack_at_20
    end

    # ⚠️ УБРАН задачей 3.143 (30.08.2026). Здесь стоял тест «то же и у мелкой
    # расы: +1 к атаке с 1-го уровня, а атак по-прежнему одна» — Карлик
    # действительно получал +1 к AB, пока `small_stature` был `applied`.
    # Цитата в разметке была обрезана перед условием («когда противник крупнее
    # персонажа»), запись стала `not_modelled`, и своей прибавки Карлик больше
    # не получает вовсе — демонстрировать «атаки не двигаются от размерного
    # модификатора» больше нечем: у него нет модификатора, который мог бы их
    # сдвинуть. Тот же принцип («флэт-прибавка к AB не меняет число атак»)
    # остаётся под тестом выше, на `Epic prowess`.
  end

  # ⚠️ Блок назывался «условное не считается и называет себя». Вторая половина
  # у ДВУХ его кейсов пересмотрена 17.08.2026: боевой режим и разовое умение —
  # это «включается и кончается», то есть бафф (решение Dan 10.08.2026), и
  # разметка обоих записей называет получателем `buff`. Гэпа в нашем ответе они
  # не образуют. Третий кейс — прибавка против вида врага — пассивен, помечен
  # `attack_bonus` и называется как раньше; он же и есть положительный контроль
  # к правке.
  describe "условное не считается и называет себя — где получатель наш" do
    # Боевые режимы — первые записи с ОТРИЦАТЕЛЬНЫМ числом за все шесть файлов
    # разметки. `Expertise` торгует −5 атаки за +5 AC; AC-половина отвергнута
    # в ac_bonuses.json, атакующая здесь, и обе теперь молчат по одной причине.
    test "боевой режим не в числе и на Сиале не назван", %{ruleset: ruleset, vanilla: vanilla} do
      b = build([:fighter], feats: %{1 => %{general: :expertise}})
      stats = Rules.compute(b, ruleset)

      assert stats.own_attack_bonus == 0
      refute {:not_modelled, {:attack_bonus, :expertise}} in stats.gaps

      # 🔴 Отрицательный контроль: у ванили словаря получателей нет, и та же
      # запись на том же билде называется. Значит фильтр — единственное, что
      # её сняло, а не пропавшая запись и не пропавший гейт владения.
      assert {:not_modelled, {:attack_bonus, :expertise}} in Rules.compute(b, vanilla).gaps

      by_id = Map.new(ruleset.attack_bonuses.unmodelled, &{&1.id, &1})
      assert by_id[:expertise].amount == %{kind: :flat, bonus: -5}
      assert by_id[:expertise].condition == :combat_mode
      assert by_id[:expertise].affects == ["buff"]
    end

    # Разовое умение класса: `Smite evil` даёт харизму к броску атаки, но
    # одной атакой раз в день. Форма `ability_modifier` в файле есть и НЕ
    # применяется — сторож в загрузчике роняет сборку, если её попытаются
    # применить, не реализовав.
    test "разовое умение класса не в числе и на Сиале не названо", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      b = build(List.duplicate(:paladin, 4), base_abilities: %{@flat | cha: 18})
      stats = Rules.compute(b, ruleset)

      assert stats.own_attack_bonus == 0
      refute {:not_modelled, {:attack_bonus, :smite_evil}} in stats.gaps
      assert {:not_modelled, {:attack_bonus, :smite_evil}} in Rules.compute(b, vanilla).gaps

      by_id = Map.new(ruleset.attack_bonuses.unmodelled, &{&1.id, &1})
      assert by_id[:smite_evil].amount == %{kind: :ability_modifier, ability: :cha}
      assert by_id[:smite_evil].affects == ["buff"]
    end

    # Расовые склонности «против вида врага»: в число не идут.
    #
    # ⚠️ Здесь стоял `assert attack_gaps(stats) == [battle_training_vs_goblins,
    # battle_training_vs_orcs]` — обе оговорки сняты задачей 3.95 (25.08.2026)
    # решением владельца: описание каждой называет и число, и условие
    # («+1 racial bonus on attack rolls made against orcs»), точнее нашего
    # «не всегда и не против всего». Число, как и прежде, ноль — правка про
    # признание, а не про расчёт.
    test "прибавка против вида врага не в числе и не в оговорках", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter], race: :dwarf), ruleset)

      assert stats.own_attack_bonus == 0
      assert attack_gaps(stats) == []

      # ⚠️ Прежняя формулировка проверяла заодно, что «AC-близнец сюда
      # не попадает»: у Гнома (Dwarf) три склонности `Battle training vs. *`,
      # и одна из них про AC. С пустым списком оговорок эта половина стала бы
      # верной сама собой, поэтому она переехала на уровень ДАННЫХ — семью
      # по-прежнему нельзя размечать по имени.
      attack_ids = for r <- ruleset.attack_bonuses.unmodelled, do: r.id
      ac_ids = for r <- ruleset.ac_bonuses.unmodelled, do: r.id

      assert :battle_training_vs_giants in ac_ids
      refute :battle_training_vs_giants in attack_ids
      assert :battle_training_vs_orcs in attack_ids
    end

    # ⚠️ И самое ценное различие файла на одной расе: Гоблин (Halfling) несёт
    # ТРИ склонности, задевающие атаку. До задачи 3.143 (30.08.2026) вердикты
    # были разными — размерный модификатор посчитан, метательный бонус
    # отвергнут по оружию, страх не про атаку вовсе.
    #
    # 🔴 `small_stature` стал `not_modelled` тем же коммитом: цитата в разметке
    # была обрезана перед условием «когда противник крупнее персонажа», а
    # посчитать его нечем (противник неизвестен заранее). Демонстрация теперь
    # другая, и не менее ценная: ОБА условных источника отвергнуты, но видны
    # по-разному — `good_aim` называет себя гэпом (оружие неизвестно),
    # `small_stature` молчит (`not_a_gap`: описание фита само называет условие
    # точнее нашей фразы, задача 3.95).
    test "у одной расы два условных источника видны по-разному", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter], race: :halfling), ruleset)

      assert stats.own_attack_bonus == 0
      assert Enum.map(stats.own_attack_terms, & &1.id) == []
      assert attack_gaps(stats) == [{:not_modelled, {:attack_bonus_weapon, :good_aim}}]
    end
  end

  describe "оба ruleset'а и старые источники" do
    # Файл разметки один на оба ruleset'а (лежит в `vanilla/`), и шард своих
    # прибавок к атаке не добавил ни одной — значит числа совпадают.
    test "числа одинаковы на vanilla и siala_41", %{ruleset: ruleset, vanilla: vanilla} do
      b = build([:fighter], feats: %{1 => %{general: :epic_prowess}}, race: :gnome)

      assert Rules.compute(b, ruleset).own_attack_bonus ==
               Rules.compute(b, vanilla).own_attack_bonus
    end

    # Задача 1.12b добавляет ТРЕТИЙ источник, а не переписывает два прежних:
    # вещи и расовый бонус остаются своими полями и своими числами.
    test "вещи и расовый бонус остались на месте", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 40),
            race: :half_elf,
            gear:
              Gear.new(
                abilities: %{str: 12},
                weapon: :longsword,
                feats: [:siala_blade_proficiency]
              )
          ),
          ruleset
        )

      assert stats.gear_attack_bonus == 6
      assert stats.race_attack_bonus == 9
      assert stats.own_attack_bonus == 0
      assert stats.attack_extra_bonus == 15
    end
  end
end
