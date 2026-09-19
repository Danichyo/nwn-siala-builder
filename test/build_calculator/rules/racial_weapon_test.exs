defmodule BuildCalculator.Rules.RacialWeaponTest do
  @moduledoc """
  Удвоение за расовое оружие и то, что его снимает (задача 3.198).

  🔴 **Главный источник — замер Dan 12.09.2026** (`GAME_CHECKS.md`, кейс `AN1`),
  дословно: «карлик 15 уровня, по дефолту AC = 12, потому что я голый и мод
  ловкости 2. С клинковым в руке AC вырастает до 18, если взять дубину в левую
  руку, то AC падает до 15, но я получаю урон соником от дубины. Получается
  второе оружие другого вида убирает удвоенный бонус AC».

  Второй источник — разбор серверных скриптов шарда
  (`docs/research/2026-09-11-miniset-scaling-system.md`, §5,
  `sl_s_wp_inc.nss:516-539`): «The matching multiplier requires the other hand
  not to contain a different weapon category; torches, wands, rods, and shields
  do not count as a conflict».

  ## Таблица кейсов: Карлик-варвар, DEX 14 (мод +2), голым AC 12

  | в руках                     | 15 уровень | 40 уровень | почему |
  |-----------------------------|-----------:|-----------:|--------|
  | пусто                       |         12 |         12 | бонус включает оружие в руках (`Q1`) |
  | кинжал                      |     **18** |     **30** | расовый + клинковый, то есть удвоение |
  | кинжал + кинжал             |     **18** |     **30** | та же категория не мешает (`AH2`) |
  | кинжал + лёгкий молот       |     **15** |     **21** | 🔴 другая категория — удвоение снято |
  | лёгкий молот + кинжал       |     **15** |     **21** | правило симметрично: важны РУКИ, а не главная |

  Арифметика скрипта на 15-м: тир 2 × 3/2 (чистый класс Сагры) = 3, ×2 = 6.
  На 40-м: тир 6 × 3/2 = 9, ×2 = 18.

  ⚠️ **Числа 40-го уровня здесь 30/30/21, а не 29/29/20**, и расхождение
  не в правиле, а в ловкости: у этого билда мод +2 (голое AC 12, как у Dan),
  а прежние заходы считали на моде +1. Разность между строками — ровно 9,
  то есть величина удвоения, и она от ловкости не зависит.

  🔴 **ЧЕМ МЫ ОТЛИЧАЕМСЯ ОТ ЗАМЕРА БУКВАЛЬНО: у Dan во второй руке ДУБИНА,
  а у нас лёгкий молот.** Дубина (`club`) — оружие среднего размера, Карлик —
  малая раса, и по ванильному правилу хвата (`vanilla/weapons.json` → `_grip`,
  «на одну категорию крупнее — двумя руками») малая раса держит её ДВУМЯ
  руками; наша модель второй руки ему поэтому не даёт вовсе
  (`{:two_handed_in_off_hand, :club}`). Правило, которое проверяет замер, —
  про КАТЕГОРИЮ оружия, и лёгкий молот воспроизводит его точка в точку: та же
  категория «молоты», тот же звуковой урон, те же числа 18 → 15. ⚠️ Само
  расхождение при этом настоящее и записано в отчёте задачи: либо Dan держал
  другой дробящий предмет, либо хват дубины на шарде не ванильный. Дорисовывать
  ответ сюда нельзя — размер оружия правило этой задачи не трогает.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear, GearWeapon, RacialWeapon}

  # Ловкость 14 — мод +2, то есть «по дефолту AC = 12» замера слово в слово.
  @flat %{str: 10, dex: 14, con: 10, int: 10, wis: 10, cha: 10}

  # Все пять фитов владения сразу: кейсы этого файла про удвоение, а не про
  # допуск к оружию (это `gear_weapon_test.exs`), и отказ по владению
  # превратил бы половину из них в ложно-зелёные нули.
  @proficiencies [
    :siala_blade_proficiency,
    :siala_polearm_proficiency,
    :siala_ranged_proficiency,
    :siala_axe_proficiency,
    :siala_hammer_proficiency
  ]

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  describe "замер AN1 (Dan, 12.09.2026): Карлик 15 уровня" do
    # 🔴 ГЛАВНЫЙ КЕЙС ЗАДАЧИ, и три его строки стоят вместе намеренно: первая
    # и вторая — положительный контроль к третьей. Правка, снимающая удвоение
    # всегда, сломала бы первую; правка, снимающая его от ЛЮБОГО второго
    # оружия, — вторую.
    test "12 голым, 18 с клинком, 15 с молотом во второй руке", %{ruleset: ruleset} do
      assert ac(ruleset, 15, nil, nil) == 12
      assert ac(ruleset, 15, :dagger, nil) == 18
      assert ac(ruleset, 15, :dagger, :dagger) == 18
      assert ac(ruleset, 15, :dagger, :light_hammer) == 15
    end

    # Разложение того же числа по слагаемым, а не «сошлось же»: расовый терм
    # обязан остаться на месте (его включает ЛЮБОЕ оружие в руках — замер
    # `AI1`), а погаснуть обязан оружейный, и именно тот, что лёг бы в тот же
    # эффект движка.
    test "гаснет оружейный терм, расовый остаётся", %{ruleset: ruleset} do
      broken = stats(ruleset, 15, :dagger, :light_hammer)

      assert broken.racial_bonus.counted == 3
      assert broken.racial_bonus.variant == :sagra_warrior
      assert broken.racial_bonus.weapon_match == {:broken, :light_hammer}

      assert Enum.map(broken.weapon_type_bonuses, &{&1.weapon, &1.kind, &1.counted}) == [
               {:dagger, :shield_ac, nil},
               {:light_hammer, :sonic_damage, nil}
             ]

      assert Enum.find(broken.weapon_type_bonuses, &(&1.weapon == :dagger)).folded_into_racial?
    end

    # ⚠️ Правило про РУКИ, а не про главную руку: скрипт спрашивает «другая
    # рука», и обе перестановки обязаны дать одно число. Без этого кейса
    # реализация, смотрящая только во вторую руку, зеленела бы.
    test "перестановка рук ничего не меняет", %{ruleset: ruleset} do
      assert ac(ruleset, 15, :light_hammer, :dagger) == 15

      assert stats(ruleset, 15, :light_hammer, :dagger).racial_bonus.weapon_match ==
               {:broken, :light_hammer}
    end

    # Топор — тоже «другая категория», и это не тот же кейс, что молот:
    # у топоров свой исполнитель (поглощение урона), а снимается удвоение
    # одинаково. Ровно этот сценарий и предлагал кейс `AN1` («кинжал + ручной
    # топор»), пока Dan не снял его дубиной.
    test "ручной топор во второй руке снимает удвоение так же", %{ruleset: ruleset} do
      assert ac(ruleset, 15, :dagger, :handaxe) == 15
    end
  end

  describe "40-й уровень — та же тройка, цена ошибки девять очков" do
    test "30 / 30 / 21", %{ruleset: ruleset} do
      assert ac(ruleset, 40, :dagger, nil) == 30
      assert ac(ruleset, 40, :dagger, :dagger) == 30
      assert ac(ruleset, 40, :dagger, :light_hammer) == 21
    end

    # ⚠️ Несагровик — обязательная пара к каждому числу этого файла: без неё
    # тест зеленел бы и у кода, который всегда берёт вариант сагровика.
    # По скрипту у него `B = T` без множителя 3/2: тир 6 → 6, удвоение → 12.
    test "у несагровика те же две строки, но числа свои", %{ruleset: ruleset} do
      assert ac(ruleset, 40, :dagger, nil, impure?: true) == 24
      assert ac(ruleset, 40, :dagger, :light_hammer, impure?: true) == 18

      assert stats(ruleset, 40, :dagger, nil, impure?: true).racial_bonus.variant == :base
    end

    # 41-й — кап Сиалы, и тир там тот же, что на 40-м. Граница проверяется
    # потому, что «максимум на 40» и «41-й ведёт себя как ванильный эпический»
    # — два разных факта, и правило удвоения не должно зависеть ни от одного.
    test "на капе 41 правило то же", %{ruleset: ruleset} do
      assert ac(ruleset, 41, :dagger, nil) == 30
      assert ac(ruleset, 41, :dagger, :light_hammer) == 21
    end

    # Нижняя граница лестницы: на 1-м уровне тир 1, у сагровика
    # floor(1 · 3 / 2) = 1, то есть удвоение стоит ровно одно очко — и оно
    # тоже обязано сниматься.
    test "на 1-м уровне удвоение стоит одно очко и снимается", %{ruleset: ruleset} do
      assert ac(ruleset, 1, :dagger, nil) == 14
      assert ac(ruleset, 1, :dagger, :light_hammer) == 13
    end
  end

  describe "что правило НЕ трогает" do
    # 🔴 «Два разных оружия — два разных бонуса» (`Система оружия`, revid
    # 20527) остаётся в силе: гасится ровно запись ТОГО ЖЕ эффекта движка.
    # Звуковой урон молота получателя у нас не имеет, поэтому проверяется
    # не число, а то, что запись жива и не свёрнута.
    test "бонус второй руки за ЕЁ тип остаётся", %{ruleset: ruleset} do
      hammer =
        ruleset
        |> stats(15, :dagger, :light_hammer)
        |> Map.fetch!(:weapon_type_bonuses)
        |> Enum.find(&(&1.weapon == :light_hammer))

      assert hammer.kind == :sonic_damage
      refute hammer.folded_into_racial?
    end

    # Раса без расового бонуса вовсе: спрашивать нечего ни в одном состоянии
    # рук, и билд об этом молчит.
    test "у Гоблина и Тёмного эльфа правила нет", %{ruleset: ruleset} do
      for race <- [:halfling, :elf] do
        build = build(race, 40, :dagger, :light_hammer)
        assert RacialWeapon.match(build, ruleset) == :none
      end
    end

    # Оружие не той категории в ОБЕИХ руках: совпадения нет, снимать нечего.
    test "без расового оружия в руках — :none", %{ruleset: ruleset} do
      build = build(:gnome, 40, :light_hammer, :handaxe)
      assert RacialWeapon.match(build, ruleset) == :none
    end

    # 🔴 Ванильный ruleset не знает ни расового бонуса, ни системы оружия —
    # значит и правила нет. Проверяется тем же билдом, который на Сиале даёт
    # `{:broken, …}`.
    test "ваниль правила не знает вовсе", %{vanilla: vanilla} do
      build = build(:gnome, 40, :dagger, :light_hammer)

      assert RacialWeapon.match(build, vanilla) == :none
      assert Rules.compute(build, vanilla).ac_geared == 12
    end

    # ⚠️ Правило спрашивает оружие, которое билд ДЕРЖИТ. Кинжал без фита
    # владения на Сиале в руки не идёт (задача 3.99), значит и удвоения нет —
    # но и снимать его нечем: `:none`, а не `{:broken, …}`.
    test "отвергнутое оружие ни совпадения не даёт, ни его не ломает", %{ruleset: ruleset} do
      build = %Build{
        build(:gnome, 40, :dagger, :light_hammer)
        | gear: Gear.new(weapon: :dagger, off_hand_weapon: :light_hammer, feats: [])
      }

      assert GearWeapon.held_all(build, ruleset) == []
      assert RacialWeapon.match(build, ruleset) == :none
    end
  end

  describe "недостижимое сегодня — и почему это ответ, а не пропуск" do
    # 🔴 У Человека и Светлого эльфа правило НЕ СРАБАТЫВАЕТ НИКОГДА, и это
    # свойство данных, а не поблажка кода:
    #
    #   * всё древковое оружие справочника — `large`, то есть двуручное для
    #     любой расы: вторая рука у Человека с копьём занята по построению;
    #   * дальнобойное во вторую руку не идёт вовсе, и с ним в главной руке
    #     второго оружия не дают (замер `AI2`, 30.08.2026).
    #
    # Кейс стоит именно затем, чтобы день, когда шард заведёт одноручное
    # древковое или разрешит второе оружие лучнику, был виден падением теста,
    # а не тишиной.
    test "Человек с древковым: вторая рука занята хватом", %{ruleset: ruleset} do
      build = build(:human, 40, :spear, :dagger)

      assert GearWeapon.held_all(build, ruleset) == [main: :spear]
      assert RacialWeapon.match(build, ruleset) == :matched
    end

    test "Светлый эльф с луком: второго оружия не бывает", %{ruleset: ruleset} do
      build = build(:half_elf, 40, :longbow, :dagger)

      assert GearWeapon.held_all(build, ruleset) == [main: :longbow]
      assert RacialWeapon.match(build, ruleset) == :matched
    end

    # 🔴 Категория, которой не знает никто. «Система оружия» описывает бонус
    # перчаток и ни одного оружия к этому типу не приписывает, поэтому
    # у рукопашного удара категории нет. Считаем как раньше (удвоение
    # остаётся) и говорим об этом гэпом: молча снять — занизить, молча
    # оставить — завысить.
    test "рукопашный удар во второй руке: считаем по-старому и признаёмся",
         %{ruleset: ruleset} do
      build = build(:gnome, 40, :dagger, :unarmed_strike)
      computed = Rules.compute(build, ruleset)

      assert RacialWeapon.category(ruleset, :unarmed_strike) == nil
      assert RacialWeapon.match(build, ruleset) == {:unknown, :unarmed_strike}
      assert computed.ac_geared == 30
      assert {:missing_data, {:weapon_category, :unarmed_strike}} in computed.gaps
    end
  end

  describe "категория — это ТИП ДВИЖКА, а не группа владения" do
    # Пять групп владения — первые пять типов движка, и у сорока двух оружий
    # категория совпадает с группой. Остальные три типа так просто не
    # прочитать, и ровно на них правило и спотыкалось бы.
    test "дубинка несёт категорию молотов, не имея группы владения",
         %{ruleset: ruleset} do
      assert ruleset.weapons[:club].proficiency_group == :no_proficiency_required
      assert RacialWeapon.category(ruleset, :club) == :hammer
    end

    # Магический посох — восьмой тип движка: своя категория, ничья больше.
    # Значит для Карлика он «другая категория», хотя ни в одну из пяти групп
    # не входит.
    test "магический посох — свой тип, а не ничей", %{ruleset: ruleset} do
      assert RacialWeapon.category(ruleset, :magic_staff) == {:own_type, :magic_staff}
      assert RacialWeapon.category(ruleset, :dagger) == :blade
    end

    # ⚠️ Комбинированное оружие берёт категорию СВОЕЙ группы, а не той, чей
    # бонус несёт вторым: алебарда даёт щитовой AC клинков, но категория у неё
    # древковая.
    test "алебарда древковая, хотя несёт клинковый бонус", %{ruleset: ruleset} do
      assert RacialWeapon.category(ruleset, :halberd) == :polearm
    end
  end

  describe "мини-сеты усиливают то, что осталось" do
    # 🔴 Усиление и внутренний кап исполнителя считаются от СУММЫ наших термов
    # (`Rules.MiniSets`), поэтому снятое удвоение обязано менять и их:
    #
    #   удвоение цело:  база 18, +floor(18·4/10) = 7 → 25, кап 18 → **18**
    #   удвоение снято: база  9, +floor(9·4/10)  = 3 → 12, кап не кусает → **12**
    #
    # Четыре куска выбраны намеренно: на десяти оба состояния упираются
    # в кап 18 и разница исчезает — тот случай, когда тест зеленел бы
    # на сломанном коде.
    test "четыре куска: 18 против 12", %{ruleset: ruleset} do
      whole = stats(ruleset, 40, :dagger, nil, mini_sets: [4])
      broken = stats(ruleset, 40, :dagger, :light_hammer, mini_sets: [4])

      assert receiver(whole) == %{base: 18, added: 7, clipped: -7, total: 18}
      assert receiver(broken) == %{base: 9, added: 3, clipped: 0, total: 12}

      assert whole.ac_geared == 30
      assert broken.ac_geared == 24
    end

    # ⚠️ А на десяти кусках разницы НЕТ, и это не баг: кап исполнителя 18
    # и без удвоения достижим. Записано кейсом, чтобы никто не «починил»
    # равенство, увидев его на живом билде.
    test "десять кусков: кап прячет разницу", %{ruleset: ruleset} do
      whole = stats(ruleset, 40, :dagger, nil, mini_sets: [10])
      broken = stats(ruleset, 40, :dagger, :light_hammer, mini_sets: [10])

      assert whole.ac_geared == broken.ac_geared
      assert receiver(whole).total == receiver(broken).total
    end
  end

  describe "ничего не сдвинулось там, где второго оружия нет" do
    # Положительный контроль ко всей задаче: билд с одним оружием обязан
    # считаться ровно как до 12.09.2026. Числа взяты из `racial_bonus_test`
    # и `weapon_type_bonus_test` — те же, что стояли там до правки.
    test "Светлый эльф-сагровик 40 с луком: AB не изменился", %{ruleset: ruleset} do
      build = %Build{
        build(:half_elf, 40, :longbow, nil)
        | base_abilities: %{@flat | str: 8, dex: 28},
          gear: Gear.new(weapon: :longbow, weapon_attack: 5, feats: @proficiencies)
      }

      stats = Rules.compute(build, ruleset)

      assert stats.attack_bonus == 59
      assert {stats.race_attack_bonus, stats.weapon_type_attack_bonus} == {9, 9}
    end

    test "Человек-сагровик 40 с копьём: Дисциплина не изменилась", %{ruleset: ruleset} do
      build = %Build{build(:human, 40, :spear, nil) | skills: %{1 => %{discipline: 4}}}
      value = Rules.compute(build, ruleset).skill_values[:discipline]

      assert value.shard_race_bonus == 18
      assert value.weapon_type_bonus == 18
    end
  end

  # ---------------------------------------------------------------------------
  # 🔴 СТОРОЖА ЗАГРУЗЧИКА И ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ НА САМО ПРАВИЛО.
  #
  # Правило целиком лежит в данных, и проверяется это не чтением, а прогоном
  # на КОПИИ `priv/rules`: снапшот без записи считает как до 12.09.2026,
  # а снапшот, у которого две записи об одной категории разошлись, роняет
  # сборку вместо того, чтобы молча выбрать одну.
  describe "правило живёт в данных: сторожа загрузчика" do
    @describetag :tmp_dir

    setup do
      root = BuildCalculator.TmpDir.unique_path!()
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    # Снапшот без правила — законное состояние (так выглядели все данные
    # до этой задачи), и он обязан считать по-старому: сумма двух термов при
    # любом составе рук. Это же и контроль, что правило не зашито в коде.
    test "без записи `racial_weapon_match` удвоение не снимается ничем", %{root: root} do
      ruleset = patched(root, &Map.delete(&1, "racial_weapon_match"))
      build = build(:gnome, 15, :dagger, :light_hammer)

      assert ruleset.racial_bonuses.weapon_match == nil
      assert RacialWeapon.match(build, ruleset) == :none
      assert Rules.compute(build, ruleset).ac_geared == 18
    end

    # ⚠️ Второй ключ записи читается тоже: «та же категория не мешает» — это
    # замер `AH2`, а не умолчание кода. Снапшот, объявивший обратное, обязан
    # получить обратное поведение.
    test "`same_category_breaks` читается из данных", %{root: root} do
      ruleset = patched(root, &put_in(&1["racial_weapon_match"]["same_category_breaks"], true))
      build = build(:gnome, 15, :dagger, :dagger)

      assert RacialWeapon.match(build, ruleset) == {:broken, :dagger}
      assert Rules.compute(build, ruleset).ac_geared == 15
    end

    # Категория расы названа дважды — русскими словами (`mirrors_weapon_type`)
    # и id (`mirrors_proficiency_group`), — и второе сверяется со справочником
    # оружия: опечатка выглядела бы как данные и молча выключила бы правило.
    test "неизвестная группа у расы роняет сборку", %{root: root} do
      path = Path.join(root, "siala_41/races.json")
      raw = path |> File.read!() |> Jason.decode!()

      patched =
        update_in(raw["races"], fn races ->
          for race <- races do
            if race["vanilla_id"] == "gnome",
              do: put_in(race["racial_bonus"]["mirrors_proficiency_group"], "blades"),
              else: race
          end
        end)

      File.write!(path, Jason.encode!(patched))

      assert_raise RuntimeError, ~r/mirrors proficiency group blades/, fn ->
        Loader.load!(root)
      end
    end

    # 🔴 Категория оружия тоже написана дважды — группой владения
    # в `weapons.json` и `own_group` в таблице по оружию. Разойтись молча
    # им нельзя: от того, какую из двух прочитали, зависит, переживёт ли
    # удвоение вторую руку.
    test "разошедшиеся записи о категории оружия роняют сборку", %{root: root} do
      path = Path.join(root, "siala_41/systems.json")
      raw = path |> File.read!() |> Jason.decode!()

      patched =
        update_in(raw["systems"], fn systems ->
          for system <- systems do
            if system["id"] == "weapon_system" do
              update_in(system["facts"], fn facts ->
                for fact <- facts do
                  if fact["what"] == "weapon_specific_bonus_overrides" do
                    update_in(fact["value"], fn rows ->
                      for row <- rows do
                        if row["weapon_id"] == "halberd",
                          do: Map.put(row, "own_group", "blade"),
                          else: row
                      end
                    end)
                  else
                    fact
                  end
                end
              end)
            else
              system
            end
          end
        end)

      File.write!(path, Jason.encode!(patched))

      assert_raise RuntimeError, ~r/own group is blade/, fn -> Loader.load!(root) end
    end

    defp patched(root, fun) do
      path = Path.join(root, "siala_41/races.json")
      raw = path |> File.read!() |> Jason.decode!()
      File.write!(path, Jason.encode!(update_in(raw["activation"], fun)))

      Loader.load!(root)["siala_41"]
    end
  end

  # ------------------------------------------------------------------ helpers --

  defp ac(ruleset, levels, main, off, opts \\ []),
    do: stats(ruleset, levels, main, off, opts).ac_geared

  defp stats(ruleset, levels, main, off, opts \\ []),
    do: Rules.compute(build(:gnome, levels, main, off, opts), ruleset)

  # ⚠️ По умолчанию — ВАРВАР, то есть чистый класс Сагры: замер `AN1` снят
  # на нём, и множитель 3/2 виден в каждом числе. `impure?: true` подменяет
  # последний уровень бардом и тем самым отменяет группу.
  defp build(race, levels, main, off, opts \\ []) do
    classes =
      if opts[:impure?],
        do: List.duplicate(:barbarian, levels - 1) ++ [:bard],
        else: List.duplicate(:barbarian, levels)

    %Build{} =
      Build.new(
        race: race,
        levels: classes,
        base_abilities: @flat,
        gear:
          Gear.new(
            [weapon: main, off_hand_weapon: off, feats: @proficiencies] ++
              mini_sets(opts)
          )
      )
  end

  defp mini_sets(opts), do: if(opts[:mini_sets], do: [mini_sets: opts[:mini_sets]], else: [])

  defp receiver(stats) do
    stats.mini_sets
    |> Enum.find(&(&1.kind == :shield_ac))
    |> Map.take([:base, :added, :clipped, :total])
  end
end
