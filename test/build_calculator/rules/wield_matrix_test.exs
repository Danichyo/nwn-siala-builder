defmodule BuildCalculator.Rules.WieldMatrixTest do
  @moduledoc """
  Хват оружия и вторая рука на обоих ruleset'ах — сплошной матрицей (задачи
  4.28 и 4.29).

  Все 47 видов справочника × два размера владельца: человек (medium) и Гоблин
  (`halfling`, small); Карлик (`gnome`, тоже small) обязан отвечать как Гоблин.
  На каждую пару — четыре ответа ядра:

    * **хват** — `Rules.Wield.grip/3`, или `:too_large`, если оружие не взять вовсе
      (`Rules.Wield.refusal/3`);
    * **щит можно** — оружие не занимает вторую руку (`both_hands?/3`);
    * **вторая рука можно** — оружие можно положить во вторую руку. С задачи
      4.29 ответ берётся из НАСТОЯЩЕЙ цепочки отказов второй руки
      (`Rules.GearWeapon.validate/4`, рука `:off`): не занимает обе, не
      дальнобойное и сам предмет игра туда кладёт (`EquipableSlots`, запрет
      движка — `Wield.main_hand_only?/2`). ⚠️ До 4.29 столбец собирался здесь
      же из двух предикатов `Wield` и потому был слеп к третьему отказу —
      ровно тому, которого не хватало;
    * **лёгкое** — `light?/3` (штраф боя двумя оружиями).

  Пять атак существ — не предметы игрока (`wieldable?: false`) и в матрицу
  не входят; это проверено отдельно.

  🔴 **Откуда ожидания.**

    * **Ваниль** — таблица игры, а не наша память: `baseitems.2da` (`WeaponWield`,
      `WeaponSize`, `EquipableSlots`, `RangedWeapon`) в чтении документации
      (`vanilla/weapon_wield.json`, `vanilla/weapon_off_hand.json`) и запрет
      движка на цепы и моргенштерн (nwn.wiki, «Hardcoded Limitations»; Fandom
      «Light flail», «Morningstar»). Литеральная таблица ниже сверена с выгрузкой
      `priv/base_2da/` отдельным тестом (без выгрузки он пропускается — в
      публичном репозитории её нет).
    * **Сиала** — ответы ДО задачи 4.28, снятые прогоном на коммите 922d5f3, со
      сдвигом задачи 4.29 во второй руке у трёх видов человека (посох, лёгкий
      цеп, моргенштерн) — по строкам хака, сверка ниже — и со сдвигом задачи
      4.42 у трезубца: замер `AY1` («Трезубец одноручный, причём его можно
      взять в левую руку тоже») и размер по хаку (`WeaponSize 3`, medium;
      `siala_41/weapons.json`).

  ⚠️ Две таблицы расходятся ровно в трёх местах: в слове хвата дротика
  и сюрикена (у Сиалы её колонка зовёт их «двуручное/метательное», а щит рядом
  остаётся — замер R5; у ванили таблица игры их двуручными не зовёт), во второй
  руке кнута (хак Сиалы даёт ему бит второй руки, базовая игра — нет) и в размере
  трезубца (хак Сиалы делает его средним, базовая игра — большим).
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.{Ids, Source}
  alias BuildCalculator.Data
  alias BuildCalculator.GameFiles.TwoDA
  alias BuildCalculator.Rules.{Build, GearWeapon, Wield}

  @not_items [:bite_item, :claw_item, :creature_weapon, :gore_item, :slam_item]

  # оружие => {человек, Гоблин}; ответ — {хват, щит можно, вторая рука можно, лёгкое}
  # или `:too_large` («не взять вовсе»).
  #
  # Вторая рука у четырёх видов — ПО ИСТОЧНИКУ (задача 4.29):
  #   * кнут, магический посох — нет бита второй руки в `EquipableSlots`
  #     (baseitems.2da:111 и :45, `0x1C010`); Fandom «Whip», «Magic staff»:
  #     «cannot be wielded in the off-hand without using a modified baseitems.2da»;
  #   * лёгкий цеп, моргенштерн — бит есть (`0x1C030`), не пускает движок:
  #     Fandom «Light flail», «Morningstar»; nwn.wiki, «Hardcoded Limitations».
  #   У Гоблина посох, цеп и моргенштерн medium — двуручны и без этого.
  @vanilla %{
    bastard_sword: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    battleaxe: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    club: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    dagger: {{:one_handed, true, true, true}, {:one_handed, true, true, true}},
    dart: {{:one_handed, true, false, false}, {:one_handed, true, false, false}},
    dire_mace: {{:double_sided, false, false, false}, :too_large},
    double_axe: {{:double_sided, false, false, false}, :too_large},
    dwarven_waraxe: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    greataxe: {{:two_handed, false, false, false}, :too_large},
    greatsword: {{:two_handed, false, false, false}, :too_large},
    halberd: {{:two_handed, false, false, false}, :too_large},
    handaxe: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    heavy_crossbow: {{:two_handed, false, false, false}, {:two_handed, false, false, false}},
    heavy_flail: {{:two_handed, false, false, false}, :too_large},
    kama: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    katana: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    kukri: {{:one_handed, true, true, true}, {:one_handed, true, true, true}},
    lance: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    light_crossbow: {{:two_handed, false, false, false}, {:two_handed, false, false, false}},
    light_flail: {{:one_handed, true, false, false}, {:two_handed, false, false, false}},
    light_hammer: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    longbow: {{:two_handed, false, false, false}, :too_large},
    longsword: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    mace: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    magic_staff: {{:one_handed, true, false, false}, {:two_handed, false, false, false}},
    morningstar: {{:one_handed, true, false, false}, {:two_handed, false, false, false}},
    quarterstaff: {{:two_handed, false, false, false}, :too_large},
    rapier: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    scimitar: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    scythe: {{:two_handed, false, false, false}, :too_large},
    shortbow: {{:two_handed, false, false, false}, {:two_handed, false, false, false}},
    shortsword: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    shuriken: {{:one_handed, true, false, false}, {:one_handed, true, false, false}},
    sickle: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    sling: {{:one_handed, true, false, false}, {:one_handed, true, false, false}},
    spear: {{:two_handed, false, false, false}, :too_large},
    throwing_axe: {{:one_handed, true, false, false}, {:one_handed, true, false, false}},
    trident: {{:two_handed, false, false, false}, :too_large},
    two_bladed_sword: {{:double_sided, false, false, false}, :too_large},
    unarmed_strike: {{nil, true, true, nil}, {nil, true, true, nil}},
    warhammer: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    whip: {{:one_handed, true, false, true}, {:one_handed, true, false, false}}
  }

  # Вторая рука у Сиалы (задача 4.29) — по её хаку, `priv/hak/2da/baseitems.2da`:
  #   * посох — строка 45 та же, `0x1C010`: во вторую руку нельзя, как у ванили;
  #   * лёгкий цеп и моргенштерн — строки 4 и 47 на тех же позициях, запрет
  #     движка тот же;
  #   * кнут — строка 111 `0x1C030`: бит второй руки хак ДОБАВИЛ, и ответ
  #     Сиалы по кнуту остаётся прежним.
  #
  # Трезубец у Сиалы (задача 4.42) — замер `AY1` и строка 95 хака
  # (`WeaponSize 3`, medium; у базы 4): у человека одноручный, щит и вторая
  # рука можно, лёгким не считается; у Гоблина — двуручный по правилу размеров
  # (средний на категорию крупнее малого), а не «нельзя вовсе», как до задачи.
  @siala %{
    bastard_sword: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    battleaxe: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    club: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    dagger: {{:one_handed, true, true, true}, {:one_handed, true, true, true}},
    dart: {{:two_handed, true, false, false}, {:two_handed, true, false, false}},
    dire_mace: {{:double_sided, false, false, false}, :too_large},
    double_axe: {{:double_sided, false, false, false}, :too_large},
    dwarven_waraxe: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    greataxe: {{:two_handed, false, false, false}, :too_large},
    greatsword: {{:two_handed, false, false, false}, :too_large},
    halberd: {{:two_handed, false, false, false}, :too_large},
    handaxe: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    heavy_crossbow: {{:two_handed, false, false, false}, {:two_handed, false, false, false}},
    heavy_flail: {{:two_handed, false, false, false}, :too_large},
    kama: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    katana: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    kukri: {{:one_handed, true, true, true}, {:one_handed, true, true, true}},
    lance: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    light_crossbow: {{:two_handed, false, false, false}, {:two_handed, false, false, false}},
    light_flail: {{:one_handed, true, false, false}, {:two_handed, false, false, false}},
    light_hammer: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    longbow: {{:two_handed, false, false, false}, :too_large},
    longsword: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    mace: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    magic_staff: {{:one_handed, true, false, false}, {:two_handed, false, false, false}},
    morningstar: {{:one_handed, true, false, false}, {:two_handed, false, false, false}},
    quarterstaff: {{:two_handed, false, false, false}, :too_large},
    rapier: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    scimitar: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    scythe: {{:two_handed, false, false, false}, :too_large},
    shortbow: {{:two_handed, false, false, false}, {:two_handed, false, false, false}},
    shortsword: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    shuriken: {{:two_handed, true, false, false}, {:two_handed, true, false, false}},
    sickle: {{:one_handed, true, true, true}, {:one_handed, true, true, false}},
    sling: {{:one_handed, true, false, false}, {:one_handed, true, false, false}},
    spear: {{:two_handed, false, false, false}, :too_large},
    throwing_axe: {{:one_handed, true, false, false}, {:one_handed, true, false, false}},
    trident: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    two_bladed_sword: {{:double_sided, false, false, false}, :too_large},
    unarmed_strike: {{nil, true, true, nil}, {nil, true, true, nil}},
    warhammer: {{:one_handed, true, true, false}, {:two_handed, false, false, false}},
    whip: {{:one_handed, true, true, true}, {:one_handed, true, true, false}}
  }

  # Где вторую руку отбивает именно «только в главную» (задача 4.29), а не
  # более старая причина — поимённо. Это и есть сдвиг задачи: пять пар ванили,
  # три пары Сиалы (кнут у неё во вторую руку идёт).
  @main_hand_only %{
    "vanilla" => [
      {:light_flail, :human},
      {:magic_staff, :human},
      {:morningstar, :human},
      {:whip, :halfling},
      {:whip, :human}
    ],
    "siala_41" => [
      {:light_flail, :human},
      {:magic_staff, :human},
      {:morningstar, :human}
    ]
  }

  # Отказы, которые говорят про саму ВТОРУЮ РУКУ, а не про владение или
  # «на шарде нет». Всё прочее, что вернёт `GearWeapon.validate/4`, вторую руку
  # не запрещает: у этой цепочки отказ руки стоит раньше отказа владения.
  @hand_refusals [:two_handed_in_off_hand, :ranged_in_off_hand, :main_hand_only]

  # Слои таблицы игры, которые читает сверка с выгрузкой.
  @base2da Path.expand("../../../priv/base_2da", __DIR__)
  @hak Path.expand("../../../priv/hak/2da", __DIR__)
  @weapon_wield "priv/rules/vanilla/weapon_wield.json"

  # nwn.wiki, baseitems.2da, «Hardcoded Limitations» → «Flails and
  # Morningstars»: «Fails [sic] (light and heavy) and morningstars cannot be
  # equipped in the off hand due to engine coding»; то же Fandom «Light flail»,
  # «Morningstar». Метки строк — НЕЗАВИСИМОЕ чтение источника: данные
  # (`vanilla/weapon_off_hand.json` → `engine_barred`) здесь не спрашиваются.
  @engine_barred ~w(lightflail heavyflail morningstar)

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp answer(race, id, ruleset) do
    build = Build.new(race: race)

    case Wield.refusal(build, id, ruleset) do
      nil ->
        both? = Wield.both_hands?(build, id, ruleset)

        {Wield.grip(build, id, ruleset), not both?, off_hand_reason(build, id, ruleset) == nil,
         Wield.light?(build, id, ruleset)}

      {:weapon_too_large, ^race} ->
        :too_large
    end
  end

  # Отказ ВТОРОЙ РУКЕ, как его печатает ядро, — `nil`, если рука его берёт.
  # Сборка без оружия в главной руке: отказы «рука занята тем, что в главной»
  # здесь не спрашиваются, только сам предмет.
  defp off_hand_reason(build, id, ruleset) do
    case GearWeapon.validate(build, id, ruleset, :off) do
      :ok -> nil
      {:error, [reason]} -> if elem(reason, 0) in @hand_refusals, do: reason
    end
  end

  defp matrix(ruleset) do
    for {id, weapon} <- ruleset.weapons, weapon.wieldable?, into: %{} do
      {id, {answer(:human, id, ruleset), answer(:halfling, id, ruleset)}}
    end
  end

  # Расхождения поимённо: `[{оружие, ожидали, получили}]` — пустой список
  # печатается пустым, а не «матрица не совпала».
  defp mismatches(expected, actual) do
    for id <- Enum.sort(Enum.uniq(Map.keys(expected) ++ Map.keys(actual))),
        Map.get(expected, id) != Map.get(actual, id),
        do: {id, Map.get(expected, id), Map.get(actual, id)}
  end

  # Ruleset без правила «только в главную руку» — положительный контроль:
  # проверки ниже обязаны его заметить, а не сойтись по построению.
  defp without_main_hand_only(ruleset) do
    put_in(ruleset.wield.main_hand_only, %{slot: MapSet.new(), engine: MapSet.new()})
  end

  describe "справочник" do
    test "в матрице 42 предмета, пять атак существ — не предметы", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala] do
        not_items = for {id, w} <- ruleset.weapons, not w.wieldable?, do: id
        assert Enum.sort(not_items) == @not_items
        assert map_size(matrix(ruleset)) == 42
      end

      assert map_size(@vanilla) == 42 and map_size(@siala) == 42
    end
  end

  describe "ваниль — хват и вторая рука по таблице игры" do
    test "все виды × человек и Гоблин", %{vanilla: vanilla} do
      assert mismatches(@vanilla, matrix(vanilla)) == []
    end

    test "Карлик отвечает как Гоблин — размер один", %{vanilla: vanilla} do
      for {id, w} <- vanilla.weapons, w.wieldable? do
        assert answer(:gnome, id, vanilla) == answer(:halfling, id, vanilla), "#{id}"
      end
    end

    # Семь видов, у которых хват называет сама таблица (луки, арбалеты,
    # двустороннее), и ни одного больше: у остальных его решает размер.
    test "stated_grip есть ровно у семи, и все — из таблицы игры", %{vanilla: vanilla} do
      stated = for {id, w} <- Enum.sort(vanilla.weapons), w.stated_grip, do: {id, w.stated_grip}

      assert stated == [
               dire_mace: :double_sided,
               double_axe: :double_sided,
               heavy_crossbow: :two_handed,
               light_crossbow: :two_handed,
               longbow: :two_handed,
               shortbow: :two_handed,
               two_bladed_sword: :double_sided
             ]

      refute vanilla.wield.stated_grip_size
      refute vanilla.wield.off_hand_free_when
    end
  end

  describe "Сиала — ответы прежние, кроме второй руки трёх видов и трезубца" do
    test "все виды × человек и Гоблин", %{siala: siala} do
      assert mismatches(@siala, matrix(siala)) == []
    end

    test "Карлик отвечает как Гоблин — размер один", %{siala: siala} do
      for {id, w} <- siala.weapons, w.wieldable? do
        assert answer(:gnome, id, siala) == answer(:halfling, id, siala), "#{id}"
      end
    end

    test "описание колонки Сиалы прежнее", %{siala: siala} do
      assert siala.wield.stated_grip_size == :medium
      assert siala.wield.off_hand_free_when == :thrown
    end
  end

  # 🔴 Задача 4.29 поимённо: «только в главную руку» печатается ровно там, где
  # его не перекрывает более старая причина, — и нигде больше. У остальных
  # видов без права на вторую руку (двуручные, двусторонние, метательные)
  # причина осталась прежней: этот отказ спрашивается последним.
  describe "вторая рука: какая причина печатается" do
    for {version, _pairs} <- @main_hand_only do
      test "#{version}: «только в главную» — ровно у названных пар", context do
        ruleset = if unquote(version) == "vanilla", do: context.vanilla, else: context.siala

        found =
          for {id, w} <- Enum.sort(ruleset.weapons),
              w.wieldable?,
              race <- [:halfling, :human],
              off_hand_reason(Build.new(race: race), id, ruleset) == {:main_hand_only, id},
              do: {id, race}

        assert Enum.sort(found) == @main_hand_only[unquote(version)]
      end
    end

    # Положительный контроль: без правила эти же пары вторую руку БЕРУТ —
    # то есть отказ выше даёт именно правило 4.29, а не совпадение с чужим.
    test "без правила названные пары вторую руку берут", %{vanilla: vanilla, siala: siala} do
      for {ruleset, version} <- [{vanilla, "vanilla"}, {siala, "siala_41"}],
          {id, race} <- @main_hand_only[version] do
        assert off_hand_reason(Build.new(race: race), id, without_main_hand_only(ruleset)) ==
                 nil,
               "#{version} #{id} #{race}"
      end
    end

    # Отказ — свойство ПРЕДМЕТА, а не пары: у Гоблина посох, цеп и моргенштерн
    # отбиты двуручностью (причина прежняя), но и без неё рука бы их не взяла.
    test "у малой расы причина прежняя — двуручность", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala], id <- [:magic_staff, :light_flail, :morningstar] do
        assert off_hand_reason(Build.new(race: :halfling), id, ruleset) ==
                 {:two_handed_in_off_hand, id}

        assert Wield.main_hand_only?(id, ruleset)
      end
    end
  end

  # 🔴 Разница двух ruleset'ов — поимённо, а не «таблицы разные»: если она
  # вырастет, значит одна из сторон сдвинулась, и это надо увидеть.
  test "ваниль и Сиала расходятся ровно в хвате дротика и сюрикена, во второй руке кнута и в трезубце" do
    assert Map.keys(@vanilla) |> Enum.sort() == Map.keys(@siala) |> Enum.sort()

    differ =
      for {id, van} <- Enum.sort(@vanilla), van != Map.fetch!(@siala, id), do: id

    assert differ == [:dart, :shuriken, :trident, :whip]

    # Трезубец (задача 4.42) — у обоих размеров владельца, и причина одна:
    # размер. У ванили он большой — у человека двуручный, Гоблину не по руке;
    # у Сиалы средний по хаку — у человека одноручный (замер AY1), у Гоблина
    # двуручный. Лёгким он не бывает ни у кого.
    assert @vanilla[:trident] == {{:two_handed, false, false, false}, :too_large}

    assert @siala[:trident] ==
             {{:one_handed, true, true, false}, {:two_handed, false, false, false}}

    # Дротик и сюрикен — только слово хвата, у обоих размеров: щит, вторая
    # рука и лёгкость те же.
    for id <- [:dart, :shuriken], size <- [0, 1] do
      {van_grip, van_shield, van_off, van_light} = elem(@vanilla[id], size)
      {sia_grip, sia_shield, sia_off, sia_light} = elem(@siala[id], size)

      assert {van_grip, sia_grip} == {:one_handed, :two_handed}, "#{id}"
      assert {van_shield, van_off, van_light} == {sia_shield, sia_off, sia_light}, "#{id}"
    end

    # Кнут — только вторая рука, у обоих размеров: хват, щит и лёгкость те же.
    for size <- [0, 1] do
      {van_grip, van_shield, van_off, van_light} = elem(@vanilla[:whip], size)
      {sia_grip, sia_shield, sia_off, sia_light} = elem(@siala[:whip], size)

      assert {van_off, sia_off} == {false, true}
      assert {van_grip, van_shield, van_light} == {sia_grip, sia_shield, sia_light}
    end
  end

  # Ожидание, собранное ИЗ ТАБЛИЦЫ, а не из справочника: код и размер оружия —
  # строка baseitems.2da; какой код называет хват — правило файла.
  # Размер человека 3, Гоблина 2 (creaturesize.2da; сверено задачей 4.5).
  defp from_table(items, row, stated, wielder) do
    wield = TwoDA.int(items, row, "WeaponWield")
    step = TwoDA.int(items, row, "WeaponSize") - wielder
    melee? = TwoDA.int(items, row, "RangedWeapon") == nil

    if step > 1 do
      :too_large
    else
      grip = Map.get(stated, wield) || if(step == 1, do: :two_handed, else: :one_handed)
      free? = grip not in [:two_handed, :double_sided]
      {grip, free?, free? and melee?, melee? and step <= -1}
    end
  end

  # Вторая рука по документации таблицы: свободна по хвату, ближнего боя, бит
  # второй руки в `EquipableSlots` (0x00020 — Fandom «Baseitems.2da», column
  # notes) и не под запретом движка.
  defp documented_off_hand?(items, row, free_melee?) do
    slot? = Bitwise.band(TwoDA.int(items, row, "EquipableSlots"), 0x20) != 0
    barred? = TwoDA.get(items, row, "label") in @engine_barred

    free_melee? and slot? and not barred?
  end

  describe "ваниль сверена с выгрузкой baseitems.2da" do
    unless File.regular?(Path.join(@base2da, "manifest.json")) do
      @describetag skip:
                     "нет priv/base_2da (публичный репозиторий, CI) — выгрузка: mix base2da.extract"
    end

    setup %{vanilla: vanilla} do
      {:ok, source} = Source.load(@base2da)
      items = Source.table(source, "baseitems")
      rule = @weapon_wield |> File.read!() |> Jason.decode!() |> Map.fetch!("rule")

      stated =
        Map.new(rule["stated_grip"], &{&1["weapon_wield"], String.to_existing_atom(&1["grip"])})

      %{items: items, rows: Ids.weapons(source, vanilla), stated: stated}
    end

    # Хват, щит и лёгкость — из таблицы как есть; вторая рука — с битом слота
    # и запретом движка (задача 4.29).
    defp documented(items, row, stated, wielder) do
      case from_table(items, row, stated, wielder) do
        :too_large ->
          :too_large

        {grip, free?, free_melee?, light?} ->
          {grip, free?, documented_off_hand?(items, row, free_melee?), light?}
      end
    end

    test "у всех 41 вида со строкой таблицы литеральная таблица — это таблица игры", %{
      items: items,
      rows: rows,
      stated: stated
    } do
      assert map_size(rows) == 41

      from_2da =
        Map.new(rows, fn {id, row} ->
          {id, {documented(items, row, stated, 3), documented(items, row, stated, 2)}}
        end)

      # Безоружный удар строки не имеет (не предмет) — единственная запись
      # литеральной таблицы вне сверки.
      assert mismatches(Map.delete(@vanilla, :unarmed_strike), from_2da) == []
    end

    # Положительный контроль: без правила кодов (одно правило размеров) таблица
    # игры разошлась бы с литеральной ровно у шести видов — трёх двусторонних,
    # двух арбалетов и короткого лука. Это те же «семь находок» задачи 4.5
    # (`*_without_siala_grip`; лёгкий арбалет — у обоих размеров), то есть
    # сверка выше видит правило, а не совпадает по построению.
    test "контроль: без правила кодов расходятся ровно луки, арбалеты и двустороннее", %{
      items: items,
      rows: rows
    } do
      size_only =
        Map.new(rows, fn {id, row} ->
          {id, {documented(items, row, %{}, 3), documented(items, row, %{}, 2)}}
        end)

      differ =
        for {id, _expected, _got} <- mismatches(Map.delete(@vanilla, :unarmed_strike), size_only),
            do: id

      assert differ == [
               :dire_mace,
               :double_axe,
               :heavy_crossbow,
               :light_crossbow,
               :shortbow,
               :two_bladed_sword
             ]
    end

    # 🔴 Вторая рука — не только хват. `EquipableSlots` (бит 0x20) и движок
    # запрещают вторую руку ещё четырём видам; до задачи 4.29 это не было
    # смоделировано ни на одном ruleset'е, и здесь стоял поимённый список пяти
    # расхождений (docs/base2da_diff.md, п. 8). Теперь расхождений нет.
    defp off_hand_mismatches(items, rows, stated, ruleset) do
      # ⚠ Не `x = выражение` в компрехеншене: там это фильтр, и `false`
      # выкинул бы элемент молча — ровно то, что ищется.
      for {id, row} <- Enum.sort(rows),
          {race, size} <- [human: 3, halfling: 2],
          table = from_table(items, row, stated, size),
          table != :too_large,
          {_grip, _shield, ours, _light} = answer(race, id, ruleset),
          ours != documented_off_hand?(items, row, elem(table, 2)),
          do: {id, race}
    end

    test "вторая рука по EquipableSlots и правилам движка — у всех видов как у игры", %{
      items: items,
      rows: rows,
      stated: stated,
      vanilla: vanilla
    } do
      assert off_hand_mismatches(items, rows, stated, vanilla) == []
    end

    # Положительный контроль: без правила 4.29 сверка находит ровно те пять пар,
    # что стояли здесь списком до задачи, — то есть она видит бит и движок,
    # а не сходится по построению.
    test "контроль: без правила расходятся ровно кнут, посох, лёгкий цеп и моргенштерн", %{
      items: items,
      rows: rows,
      stated: stated,
      vanilla: vanilla
    } do
      assert Enum.sort(off_hand_mismatches(items, rows, stated, without_main_hand_only(vanilla))) ==
               [
                 {:light_flail, :human},
                 {:magic_staff, :human},
                 {:morningstar, :human},
                 {:whip, :halfling},
                 {:whip, :human}
               ]
    end
  end

  # 🔴 Сиала — тем же приёмом, но по её ХАКУ (задача 4.29): бит второй руки
  # читается из `priv/hak/2da/baseitems.2da`, хват и дальнобойность — ответом
  # ядра Сиалы (у неё своя колонка хвата, таблица игры его не решает), запрет
  # движка — по меткам строк хака. Нужны обе выгрузки: строки оружия
  # сопоставляются по базовой таблице, и на тех же позициях у хака те же метки.
  describe "Сиала сверена с хаком baseitems.2da" do
    unless File.regular?(Path.join(@base2da, "manifest.json")) and
             File.regular?(Path.join(@hak, "manifest.json")) do
      @describetag skip:
                     "нет priv/base_2da или priv/hak (публичный репозиторий, CI) — " <>
                       "выгрузки: mix base2da.extract, mix hak.extract"
    end

    setup %{vanilla: vanilla} do
      {:ok, source} = Source.load(@base2da)
      base = Source.table(source, "baseitems")
      hak = @hak |> Path.join("baseitems.2da") |> File.read!() |> TwoDA.parse!()

      %{base: base, hak: hak, rows: Ids.weapons(source, vanilla)}
    end

    # ⚠ Привязки — в теле, а не в заголовке `for`: `free_melee? = …` там был бы
    # ФИЛЬТРОМ, и `false` (двуручное, дальнобойное) молча выкинул бы строку —
    # ловушка задачи 4.28 (HANDOFF.md).
    defp siala_mismatches(hak, rows, siala) do
      for {id, row} <- Enum.sort(rows),
          race <- [:human, :halfling],
          Wield.refusal(Build.new(race: race), id, siala) == nil do
        build = Build.new(race: race)

        free_melee? =
          not Wield.both_hands?(build, id, siala) and TwoDA.int(hak, row, "RangedWeapon") == nil

        {_grip, _shield, ours, _light} = answer(race, id, siala)
        {id, race, ours != documented_off_hand?(hak, row, free_melee?)}
      end
      |> Enum.filter(fn {_id, _race, differs?} -> differs? end)
      |> Enum.map(fn {id, race, _differs?} -> {id, race} end)
    end

    test "вторая рука Сиалы — по строкам её хака у всех видов", %{
      base: base,
      hak: hak,
      rows: rows,
      siala: siala
    } do
      assert map_size(rows) == 41

      # Строка та же: позиция и метка у хака совпадают с базовой у всех 41.
      for {id, row} <- rows do
        assert TwoDA.get(hak, row, "label") == TwoDA.get(base, row, "label"), "#{id}"
      end

      assert siala_mismatches(hak, rows, siala) == []
    end

    # Положительный контроль: сиальский ruleset со ВАНИЛЬНЫМ правилом (кнут без
    # бита) разошёлся бы с хаком ровно кнутом — сверка видит строку 111.
    test "контроль: с ванильным правилом расходится ровно кнут", %{
      hak: hak,
      rows: rows,
      siala: siala,
      vanilla: vanilla
    } do
      with_vanilla_rule = put_in(siala.wield.main_hand_only, vanilla.wield.main_hand_only)

      assert Enum.sort(siala_mismatches(hak, rows, with_vanilla_rule)) ==
               [{:whip, :halfling}, {:whip, :human}]
    end
  end
end
