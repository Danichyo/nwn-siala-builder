defmodule BuildCalculator.Rules.WeaponTypeBonus do
  @moduledoc """
  What the shard gives a character for the **type of weapon in his hands**.

  Siala replaced the vanilla weapon proficiency system with five categories of
  its own, and every one of them carries a bonus that lands on the character «как
  эффект в момент взятия оружия в руку»:

      клинковое      +6 щитового AC     (+9 у воина Сагры)
      древковое      +12 Дисциплины     (+18)
      дальнобойное   +6 к атаке         (+9)
      топоры         12/- поглощения    (18/-)
      молоты         +6 урона звуком    (+9)
      щиты           18 % иммунитета    (36 %)

  Three of the six land in numbers this calculator shows; the other three have no
  receiver in a build at all — there is no damage line and no resistance line —
  and by CLAUDE.md §9 that is **not a gap** but a question we do not ask (Dan,
  16.08.2026: «мы поглоты не отображаем, так что нам на этот бонус пока что всё
  равно, как и на бонус от расы дварфа»).

  ⚠ **Пять — это число групп ВЛАДЕНИЯ, а не число ответов.** Бонус даёт и то,
  что ни в одну из пяти не входит: у движка восемь типов оружия, и один из тех
  трёх, которых нет в списке выше, до наших чисел доезжает — **магический
  посох**, `+12 Spellcraft / +12 Concentration / +12 Animal empathy` на 40-м
  (+18 воину Сагры), «складывается с остальными бонусами к навыкам, но входит
  в кап +50». Он не мирроит чужую группу, как дубинка, — он свой восьмой тип
  со своим исполнителем, и в данных он поэтому лежит записью **по оружию**,
  как алебарда, а не строкой группы (задача 3.183).

  ⚠ И один вопрос он оставляет без ответа: у Человека посох даёт **ещё и**
  Дисциплину, страница не называет её величины, а расовый бонус Человека — та
  же Дисциплина. Прибавляется она к расовой или замещает её, не говорит ни один
  источник, поэтому здесь не считается ничего: модель отдаёт расовые 12, то
  есть меньшее из двух чтений. Разбор — в `magic_staff_skill_bonus` данных.

  ⚠ `Rules.RacialBonus` said the opposite about the same two shapes until
  16.08.2026 — it reported `{:not_modelled, {:racial_bonus, race, kind}}` — which
  meant one statement about one shard system gave two different answers depending
  on which half you asked. Task 3.38 brought that half here rather than the other
  way round; the form is gone from `Rules.Vocabulary` with it.

  ## This is the same bonus as the racial one, and they are added

  Every racial bonus in `siala_41/races.json` is described as identical to one of
  the rows above («Бонус идентичен бонусу от [[Владение клинковым оружием]]»),
  which is why the two share three shapes, three numbers and one level rule. What
  they do **not** share is a term: Dan measured on 15.08.2026 (`GAME_CHECKS.md`
  Q1) a Half-elf warrior of Sagra at 40 with a longbow +5 —

      30 БАБ + 9 ловкость + 5 лук + 9 светлый эльф + 9 оружие дальнего боя = 62

  — so the racial bonus and this one are two independent addends. That is also
  where `racial_weapon: 12` and `racial_weapon_and_sagra_warrior: 18` come from:
  they are `6+6` and `9+9`, arithmetic rather than a third rule, and a build
  holding a bow gets them **because both terms fire**, never because anything
  here or in `Rules.RacialBonus` reads those two variants.

  🔴 **И ровно поэтому у суммы есть условие (задача 3.198).** В движке это
  не два эффекта, а один, удвоенный при совпадении расы с категорией оружия,
  и удвоение снимается оружием ДРУГОЙ категории в другой руке (замер `AN1`,
  Dan 12.09.2026: Карлик 15-го уровня — AC 18 с кинжалом и **15** с дробящим
  во второй руке). Тогда наш оружейный терм того же эффекта гасится
  (`fold_racial_double/3`, `counted: nil`, `folded_into_racial?: true`), и сумма
  снова равна тому, что пишет движок: `B`, а не `2B`. ⚠ Гасится ровно запись
  ТОГО ЖЕ эффекта — бонус второй руки за её собственный тип остаётся, как
  и требует «два разных оружия — два разных бонуса».

  ## The level rule — a step table since 11.09.2026 (task 3.181)

  The numbers are stated for character level 40 and the bonus grows with level.
  For a year no page on either wiki named the growth function, so the bonus was
  counted exactly where it was true — at and above the stated level — and below
  that nothing was counted and the build said why.

  🔴 **The function arrived from the shard's own server scripts**, sent by the
  administration, and Dan's decision of 11.09.2026 is to count by it on every
  level. The reading is `Rules.RacialBonus.variants_at/3` itself rather than a
  copy of it, for exactly the reason `counted_at?/2` below gives: these are two
  halves of one shard system, and a second implementation could only ever be a
  way for them to disagree.

  ⚠ **Two things the table did not change.** A snapshot without it still counts
  the old way and still says why (the default is deliberately the silent one).
  And the numbers on levels 40 and 41 did not move by a single point — that was
  the acceptance criterion of the task and it is under test.

  ⚠ **One weapon does not follow the steps at all.** A two-bladed sword's
  armour class goes through the script's *override* branch, which is straight
  linear in the character's level and bypasses every multiplier — `9` at level
  40 like everything else, `3` at 17 where the step table would say 4. Which
  branch a record takes is data (`executor` on the row), not a special case
  here.

  ## The bonus is **not** a function of the weapon's group

  Six weapons of the page's «Комбинированное оружие» section carry a second
  bonus belonging to a group they are not in, and three more carry a bonus while
  belonging to no group at all:

    * a halberd is a polearm and carries a blade's shield armour class on top;
    * a greataxe is an axe and carries shield armour class — for us its **only**
      possible contribution, since damage resistance has no receiver;
    * a two-bladed sword's shield armour class is +9 at the stated level and
      explicitly not multiplied for a warrior of Sagra («Данный бонус
      не модифицируется. Он одинаковый для всех билдов») — which the server
      scripts explain as an *override*: linear in the character's level, past
      every multiplier;
    * a magic staff needs no proficiency feat at all and carries three skill
      bonuses at once — the only record in the table with more than one number
      that reaches a receiver.

  So the data carries a table **by weapon** which *replaces* the group's row for
  those nine, and this module reads it first. A `group → bonus` rule would lose
  the halberd's armour class, give the greataxe nothing at all and hand a warrior
  of Sagra +13 with a two-bladed sword where the page says +9.

  ## Nothing here names a weapon, a group, a skill or a class group

  Which type of weapon gives what, which weapons are excluded by name («трезубцы
  не дают никакого бонуса»), which skill a «+12 дисциплины» lands on and which
  class group the second number is stated for are all data
  (`ruleset.weapon_type_bonuses`, assembled by `BuildCalculator.Data.Loader` out
  of `siala_41/systems.json` and `vanilla/weapons.json`). What this module decides
  is only which *shapes* of bonus reach a number — the three below — and what to
  say about the ones that do not reach one for a reason.
  """

  alias BuildCalculator.Rules.{Build, ClassGroups, GearWeapon, RacialBonus, RacialWeapon}

  # The shapes the core turns into a number. Identical to `Rules.RacialBonus`'s
  # list and identical on purpose: the shard's own pages state the two bonuses as
  # the same thing, so a shape one of them carried and the other did not would be
  # a disagreement about one sentence.
  #
  # 🔴 **`:damage_resistance` joined on 18.09.2026 (задача 3.210)** — the axes'
  # `12/-` and the double axe's second bonus now reach a number, because the
  # «Резисты» section exists (`Rules.Resistances`). It joined **both** lists in
  # one commit for the reason above: one sentence, one answer.
  @modelled_kinds [:attack_bonus, :shield_ac, :skill_bonus, :damage_resistance]

  @typedoc """
  One bonus the weapon in hand carries, and everything a caption needs.

    * `weapon` — what is in the hands, for the caption and the caveats
    * `kind` — `:attack_bonus` / `:shield_ac` / `:skill_bonus`, or the page's own
      name for a shape this calculator has no number for
    * `skill` / `ac_type` — where a skill bonus and an armour class bonus land
    * `variants` — both numbers **at this build's level**, `nil` where the page
      states none at all. ⚠ Not «what the page says»: that is `stated?` below,
      and the two answer different questions since the growth table (3.181)
    * `variant` — which of them this build qualifies for, always one of the two
      **roles**: `:in_group` when the build belongs to the class group the bigger
      number is stated for, `:base` otherwise. ⚠ A role rather than the page's
      own word for it, so no group is named in the core
    * `variant_assumed?` — the number of that variant rests on a reading rather
      than on a sentence (a two-bladed sword's «одинаковый для всех билдов»)
    * `stated_for_level` — the character level the **file's** numbers are written
      for; the level the loader checks the growth formula against
    * `counted` — what the core actually adds, or `nil` when it adds nothing
    * `modelled?` — whether this shape reaches any number at all
    * `stated?` — whether the page states a number for the chosen variant. ⚠ A
      third state, distinct from both «посчитано» and «уровень мал»: the bonus
      exists, its type is named and its size is written down nowhere
    * `folded_into_racial?` — этот бонус и расовый оказались ОДНИМ эффектом
      движка, а удвоения нет (`Rules.RacialWeapon.match/2` вернул
      `{:broken, _}`): эффект уже посчитан расовым термом, и второй раз его
      считать нельзя. `counted` тогда `nil`, а запись остаётся на месте — чтобы
      «бонуса нет» и «бонус посчитан один раз» не выглядели одинаково
    * `both_hands_assumed?` — both hands carry this same shape and the core
      counted it **once** on a reading nobody has confirmed (task 3.132).
      `false` on every entry that came from one hand alone — and `false` on the
      shipped data since 28.08.2026, when the owner confirmed the reading
      («если в руках два оружия одного типа - бонус не удваивается»,
      `GAME_CHECKS.md` AH2). ⚠ The field is not dead: the confirmation is a
      **mark on the record** (`same_kind_confirmed`), so a snapshot stating the
      rule without one gets the caveat back by itself
  """
  @type entry :: %{
          weapon: atom(),
          kind: atom(),
          skill: atom() | nil,
          ac_type: atom() | nil,
          executor: atom() | nil,
          variants: %{atom() => integer() | nil},
          variant: atom() | nil,
          variant_assumed?: boolean(),
          stated_for_level: pos_integer() | nil,
          counted: integer() | nil,
          modelled?: boolean(),
          stated?: boolean(),
          folded_into_racial?: boolean(),
          both_hands_assumed?: boolean()
        }

  @doc """
  Every bonus the weapon in this build's hands carries — `[]` when there is none.

  `[]` covers four different situations on purpose, because none of them is worth
  a caveat: no such system in the ruleset (vanilla), nothing in the hands, a
  weapon the page excludes by name (a trident, a throwing axe — «не дают никакого
  бонуса» is knowledge, not a hole), and a weapon in no category at all.

  ⚠ The weapon is the one that **counts** (`Rules.GearWeapon.held/2`), not the one
  recorded: a weapon the character may not wield adds no attack bonus either, and
  a bonus for holding it would be the same false legality the proficiency filter
  exists to close.
  """
  @spec of(Build.t(), map()) :: [entry()]
  def of(%Build{} = build, ruleset) do
    case Map.get(ruleset, :weapon_type_bonuses) do
      %{} = layer ->
        layer
        |> combine(entries_by_hand(build, ruleset, layer))
        |> fold_racial_double(build, ruleset)

      _no_such_system ->
        []
    end
  end

  # Каждая рука отдельно, в порядке `Rules.Gear.hands/0`. ⚠ Одной рукой это
  # было до задачи 3.132, и расширение — не удобство, а цитата: «Используя два
  # разных оружия персонаж получает два разных бонуса» (`Система оружия`, revid
  # 20527). ⚠ Здесь стояло «Катана с копьём дают и щитовой AC, и Дисциплину» —
  # пример невозможный: копьё `large`, то есть двуручное, и второй рукой его
  # не взять никогда.
  #
  # ⚠ Здесь же стояло «пары с двумя ПОСЧИТАННЫМИ числами с задачи 3.142 нет
  # вовсе»: верно было ровно до задачи 3.183. Живая пара теперь есть и она
  # не экзотическая — **клинок и магический посох**: первый даёт щитовой AC,
  # второй три значения навыка, и посох во вторую руку идёт, потому что он
  # `medium`, то есть одноручный. Довод прежней строки («вторую руку могут
  # занять только клинки, топоры и молоты, а получатель есть лишь у клинков»)
  # перестал быть верным вместе с появлением восьмого типа.
  #
  # ⚠ Рука, у которой правило про две руки не объявлено вовсе, остаётся ОДНА:
  # снапшот без этой записи считается как считался.
  defp entries_by_hand(build, ruleset, layer) do
    hands =
      case Map.get(layer, :both_hands) do
        %{} ->
          GearWeapon.held_all(build, ruleset)

        _one_hand_only ->
          for weapon <- [GearWeapon.held(build, ruleset)], weapon, do: {:main, weapon}
      end

    variant = variant(build, ruleset, layer)
    level = Build.character_level(build)

    for {_hand, weapon} <- hands,
        not MapSet.member?(layer.excluded, weapon),
        record <- records(layer, ruleset, weapon),
        do: entry(weapon, record, variant, level, layer)
  end

  # 🔴 ДВА РАЗНЫХ вида складываются, ОДИН И ТОТ ЖЕ — нет. Провенанс у двух
  # половин правила РАЗНЫЙ, и в данных он разведён: первая — цитата вики
  # («Используя два разных оружия персонаж получает два разных бонуса»), вторая
  # — слово владельца («если в руках два оружия одного типа - бонус
  # не удваивается», Dan 28.08.2026, `GAME_CHECKS.md` AH2).
  #
  # ⚠ Пока вторая была НАШИМ ЧТЕНИЕМ, каждый такой билд нёс
  # `{:assumed, {:weapon_type_bonus_both_hands, kind}}`. Оговорка снята
  # ОТМЕТКОЙ НА ЗАПИСИ (`same_kind_confirmed`), а не выключателем здесь:
  # снапшот, принёсший это правило без отметки, получит её обратно сам.
  # Ни одно число при этом не сдвинулось — подтвердилось ровно то, что
  # считалось (`assumed_combination?/1` ниже).
  #
  # ⚠ Ключ сравнения — вид бонуса вместе с его получателем (`kind`, `skill`,
  # `ac_type`), а не одно `kind`: два бонуса к РАЗНЫМ навыкам одного вида
  # складываться обязаны, и сегодня такой пары нет только потому, что навык
  # у этой системы один.
  defp combine(_layer, []), do: []

  defp combine(layer, entries) do
    entries
    |> Enum.group_by(&{&1.kind, &1.skill, &1.ac_type})
    |> Enum.sort_by(fn {_key, [entry | _]} -> Enum.find_index(entries, &(&1 == entry)) end)
    |> Enum.map(fn {_key, group} -> best(layer, group) end)
  end

  defp best(_layer, [entry]), do: entry

  defp best(layer, group) do
    chosen =
      Enum.max_by(group, fn entry -> entry.counted || entry.variants[entry.variant] || 0 end)

    if assumed_combination?(layer), do: Map.put(chosen, :both_hands_assumed?, true), else: chosen
  end

  # Отметка есть — молчим; отметки нет — говорим. Умолчание направлено
  # в сторону разговора: правило про две руки без подтверждения двигает
  # щитовой AC на 6…9 очков, и молчать об этом было бы занижением втихую.
  # 🔴 УДВОЕНИЕ ЗА РАСОВОЕ ОРУЖИЕ, СНЯТОЕ ВТОРОЙ РУКОЙ (задача 3.198).
  #
  # В движке расовый бонус и бонус за тип оружия — ОДИН эффект: диспетчер
  # вешает сперва расовый (его включает любое оружие в руках), потом оружейный
  # того же типа, и второй перезаписывает первый — удвоив величину, если раса
  # совпала с категорией оружия (`if R, B = 2B`). У нас это два независимых
  # слагаемых, и наше «×2» и есть их сумма: `6 + 6` при `B = 6`. Значит, когда
  # совпадение сломано оружием другой категории во второй руке, эффект обязан
  # быть посчитан ОДИН раз.
  #
  # ⚠ ГАСИТСЯ ОРУЖЕЙНЫЙ ТЕРМ, А НЕ РАСОВЫЙ, и выбор не произволен, хотя числа
  # у них равны по построению (один исполнитель, один тир, один набор шагов —
  # и сама страница говорит «Бонус идентичен бонусу от ношения клинков»):
  #
  #   1. расовый включается ЛЮБЫМ оружием в руках — это измерено (`AI1`,
  #      Карлик с дубиной получает свои +4 без единого клинка), поэтому он
  #      присутствует во всех трёх состояниях замера `AN1`, а меняется между
  #      ними ровно удвоение. Гасить его значило бы, что расовая строка то
  #      исчезает, то появляется от предмета в ЛЕВОЙ руке;
  #   2. величина расового известна у каждой расы с бонусом, а у оружия
  #      бывает не названа вовсе (щитовой AC алебарды — `stated?: false`).
  #      Гашение расового терма в такой паре потеряло бы число, которое
  #      игра даёт.
  #
  # ⚠ Гасится ровно запись ТОГО ЖЕ эффекта (`executor`, `kind`, `skill`,
  # `ac_type`), а не все бонусы оружия: дубина во второй руке свой звуковой
  # урон получает по-прежнему («два разных оружия — два разных бонуса»), и
  # у алебарды гасится Дисциплина, но не щитовой AC.
  #
  # ⚠ И только когда расовый терм ПОСЧИТАН: если его нет (ниже известного
  # уровня, раса без бонуса), гасить нечего — иначе у билда пропали бы оба
  # слагаемых сразу.
  defp fold_racial_double(entries, build, ruleset) do
    with {:broken, _weapon} <- RacialWeapon.match(build, ruleset),
         %{counted: counted} = racial when is_integer(counted) <- RacialBonus.of(build, ruleset) do
      key = effect_key(racial)

      Enum.map(entries, fn entry ->
        if effect_key(entry) == key,
          do: %{entry | counted: nil, folded_into_racial?: true},
          else: entry
      end)
    else
      _no_doubling_to_undo -> entries
    end
  end

  defp effect_key(%{} = record),
    do: {Map.get(record, :executor), record.kind, record.skill, record.ac_type}

  defp assumed_combination?(layer) do
    case Map.get(layer, :both_hands) do
      %{same_kind_confirmed: mark} -> not is_map(mark)
      _absent -> false
    end
  end

  @doc """
  What the weapon in hand adds to the attack roll — `0` unless it is a ranged
  weapon and the level is one the numbers are known at.

  ⚠ **Before the ceiling, not after.** The page says «Бонус входит в лимита атаки
  +20» in the very row that states the number, so this is one of the things the
  +20 is over. The caller offers it to `Rules.Caps` together with the racial
  bonus, one clip over both — and those two together are what makes that ceiling
  reachable for the first time (9 + 9 of 20).
  """
  @spec attack_bonus(Build.t(), map()) :: integer()
  def attack_bonus(%Build{} = build, ruleset), do: amount(build, ruleset, :attack_bonus)

  @doc """
  What it adds to armour class, as `[{kind, type, ac}]` — `[]` when it adds
  nothing.

  The type matters as much as the number: it is a **shield** bonus, so it meets
  the Gnome's racial shield bonus and any shield the player typed under «Вещи»
  as the same type rather than sailing past them (`Rules.ArmorClass.geared/3`).
  ⚠ The two meetings end differently, and that is the shard's rule rather than
  ours: with the racial bonus it **adds up** (the «Расы» page prints +12 for a
  Gnome with a blade and +18 for a Sagra warrior — 6 + 6 and 9 + 9), with a
  typed number it **competes** and the larger wins (tasks 3.39 and 3.91).

  ⚠ The `kind` rides along for that second meeting alone (task 3.91): since
  25.08.2026 a bonus of the build's own **adds** to a typed number of its type
  unless its shape is named as an exception in the ruleset
  (`gear.ac_types.same_type.own_vs_gear_by_kind`), and this shape is the one
  exception there is. Handing over the word rather than the answer keeps the
  rule in the data — and keeps both halves of one shard system answering it the
  same way, which is the whole reason the loader reads the racial and the
  weapon-type shape off one table.

  ⚠ A **list**, where `Rules.RacialBonus.armor_class/2` is a single tuple, and
  the difference is in the data rather than in taste: a race has exactly one
  bonus, a weapon carries up to three. Today no weapon carries two of armour
  class, so the list is never longer than one — but returning the first of
  several would be a bonus dropped in silence, which is the failure this whole
  module is arranged against.
  """
  @spec armor_class(Build.t(), map()) :: [{atom(), atom() | nil, integer()}]
  def armor_class(%Build{} = build, ruleset) do
    for %{kind: :shield_ac = kind, ac_type: type, counted: ac} <- of(build, ruleset),
        is_integer(ac),
        ac != 0,
        do: {kind, type, ac}
  end

  @doc """
  What it adds to `skill` — `0` for every skill but the one the page names.

  Like the attack bonus, this is offered **before** the ceiling: a bonus to a
  skill is inside the shard's +50 pool together with the racial bonus and whatever
  the player typed, and one clip covers all three.
  """
  @spec skill_bonus(Build.t(), map(), atom()) :: integer()
  def skill_bonus(%Build{} = build, ruleset, skill) do
    for(
      %{kind: :skill_bonus, skill: ^skill, counted: bonus} <- of(build, ruleset),
      is_integer(bonus),
      do: bonus
    )
    |> Enum.sum()
  end

  @doc """
  Whether the numbers stated in the data are true at `level`.

  **`Rules.RacialBonus.counted_at?/2` itself, not a copy.** The two bonuses are
  one statement on the shard's pages — each racial bonus is defined as identical
  to one of these rows — so a second implementation could only ever be a way for
  them to disagree about the same level, and a ruleset that stopped one from
  counting while the other kept going would be worse than either answer.
  """
  @spec counted_at?(non_neg_integer(), map()) :: boolean()
  defdelegate counted_at?(level, layer), to: RacialBonus

  @doc """
  What this build's weapon bonus does not say for itself.

  Three shapes, and each answers a different question:

    * `{:missing_data, {:weapon_type_bonus_amount, weapon, kind}}` — the page
      names the **type** of bonus and no number. A halberd and a greataxe carry
      «Бонус к классу брони (Shield bonus)» with no figure anywhere, and the
      blade's 6/9 is deliberately not substituted: the one weapon of that section
      whose number *is* stated turned out to be an exception, so the family is not
      uniform. ⚠ For a greataxe this is everything the calculator could have got
      out of it — its own bonus is damage resistance, which has no receiver.
    * `{:missing_data, {:weapon_type_bonus_level, weapon}}` — the number is known
      and the character is below the level it is stated for, so nothing was
      counted. The honest half of the missing growth function: the bonus is there
      in the game and its size at this level is unknown.
    * `{:assumed, {:weapon_type_bonus_variant, weapon, variant}}` — it **was**
      counted, and the number of that variant is our reading of a sentence rather
      than the sentence itself. One record produces it: «Данный бонус не
      модифицируется. Он одинаковый для всех билдов» is quoted, and reading «для
      всех билдов» as covering a warrior of Sagra is ours.

  ⚠ A shape with no receiver — damage, damage resistance, physical immunity —
  produces **nothing**, and that is the rule of CLAUDE.md §9 rather than an
  omission: the calculator gives no answer about damage, so it has no hole there.
  A build holding a warhammer is told nothing about its sonic damage, exactly as
  it is told nothing about the damage its strength adds.
  """
  @spec gaps(Build.t(), map()) :: [tuple()]
  def gaps(%Build{} = build, ruleset) do
    build |> of(ruleset) |> Enum.flat_map(&entry_gaps/1) |> Enum.uniq()
  end

  # ------------------------------------------------------------------ private --

  # The weapon's own table wins over its type's, whole: the page states those
  # eight weapons individually and restates their own group's bonus inside that
  # statement, so merging the two would count a halberd's Discipline twice.
  defp records(layer, ruleset, weapon) do
    case Map.get(layer.by_weapon, weapon) do
      [_ | _] = records -> records
      _none -> Map.get(layer.by_group, group(ruleset, weapon)) || []
    end
  end

  defp group(ruleset, weapon) do
    case Map.get(Map.get(ruleset, :weapons) || %{}, weapon) do
      %{proficiency_group: group} -> group
      _ -> nil
    end
  end

  # Which of the two numbers this build gets. Two, not four — the page states one
  # condition and it is a property of the class list, so a build always qualifies
  # for exactly one of them.
  #
  # ⚠ `:in_group` / `:base` are **roles**, not the page's own words: the group
  # whose members get the bigger number is «Воины Сагры», and naming it here
  # would be a game entity in the core (CLAUDE.md §5). Which group it is comes
  # from the data as an id resolved from the page title; a ruleset naming none
  # leaves every build on the smaller number, which is the floor and the safe
  # direction.
  defp variant(build, ruleset, %{class_group: group}) when not is_nil(group) do
    if ClassGroups.member?(build, ruleset, group), do: :in_group, else: :base
  end

  defp variant(_build, _ruleset, _layer), do: :base

  defp entry(weapon, record, variant, level, layer) do
    modelled? = record.kind in @modelled_kinds

    # ⚠ Два разных вопроса, и путать их нельзя: `stated?` — «называет ли
    # страница число вообще» (свойство ДАННЫХ, отсюда `record.variants`), а
    # `amount` — «сколько это на ЭТОМ уровне». Первое отвечает за оговорку
    # «тип назван, числа нет», второе — за оговорку про уровень.
    stated? = is_integer(Map.get(record.variants, variant))
    variants = RacialBonus.variants_at(layer, record, level)
    amount = Map.get(variants, variant)

    %{
      weapon: weapon,
      kind: record.kind,
      skill: record.skill,
      ac_type: record.ac_type,
      # Тот же исполнитель, что у расового бонуса, и та же причина его
      # показывать (задача 3.184): у двулезвийного меча он ДРУГОЙ
      # (`ac_override`), и складывать его щитовой AC с расовым под общим капом
      # нельзя — линейная ветка проходит мимо всех множителей.
      executor: Map.get(record, :executor),
      variants: variants,
      variant: variant,
      variant_assumed?: MapSet.member?(record.assumed_variants, variant),
      stated_for_level: layer.stated_for_level,
      counted: if(modelled? and stated? and is_integer(amount), do: amount, else: nil),
      modelled?: modelled?,
      stated?: stated?,
      # Не оказался ли этот бонус тем же эффектом, что расовый, при снятом
      # удвоении (`fold_racial_double/3`). Здесь всегда `false`: вопрос решается
      # после того, как собраны обе руки, и знать о нём запись не обязана.
      folded_into_racial?: false,
      # Пришёл ли этот вид сразу из двух рук, и решён ли спор ЧТЕНИЕМ
      # (`combine/2`). `false` у всякой записи, пришедшей из одной руки, —
      # то есть у всех, пока в руках одно оружие.
      both_hands_assumed?: false
    }
  end

  # Exactly one sentence per entry, never two: «величины не знает никто» and
  # «уровень мал» are two answers to one question, and a build that got both
  # would read as two separate faults about one bonus.
  defp entry_gaps(%{modelled?: false}), do: []

  # ⚠ Свёрнутый в расовый терм бонус гэпа НЕ даёт, и это правило CLAUDE.md §9
  # про ложное признание: мы не «не смогли посчитать», мы посчитали этот эффект
  # ОДИН раз — ровно так, как его пишет движок. Объяснение стоит там, где стоит
  # число, — строкой у расового бонуса (`Rules.RacialBonus`'s `weapon_match`),
  # а не в списке «ядро не смогло».
  defp entry_gaps(%{folded_into_racial?: true}), do: []

  defp entry_gaps(%{stated?: false, weapon: weapon, kind: kind}),
    do: [{:missing_data, {:weapon_type_bonus_amount, weapon, kind}}]

  defp entry_gaps(%{counted: nil, weapon: weapon}),
    do: [{:missing_data, {:weapon_type_bonus_level, weapon}}]

  defp entry_gaps(%{variant_assumed?: true, weapon: weapon, variant: variant}),
    do: [{:assumed, {:weapon_type_bonus_variant, weapon, variant}}]

  # ⚠ Своя оговорка, а не «ещё один вариант» соседней: та про то, КАКОЕ число
  # взято из двух написанных на странице, эта — про то, что вторая рука дала
  # тот же вид и мы посчитали его ОДИН раз. Разные вопросы и разные фразы.
  #
  # 🔴 **Носителей у неё сегодня ноль**, и это не мёртвый код: правило
  # подтверждено владельцем 28.08.2026 и несёт отметку в данных
  # (`systems.json` → `bonuses_from_both_hands.same_kind_confirmed`). Снимут
  # отметку или принесут это правило новой записью без неё — ветка заговорит
  # сама. Живой её держит СИНТЕТИЧЕСКИЙ ruleset в тесте, а не живая запись:
  # контроль на живой записи назавтра получает отметку и молча перестаёт
  # что-либо проверять (урок задачи 3.85, пять контролей подряд).
  defp entry_gaps(%{both_hands_assumed?: true, kind: kind}),
    do: [{:assumed, {:weapon_type_bonus_both_hands, kind}}]

  defp entry_gaps(_entry), do: []

  defp amount(build, ruleset, kind) do
    for(%{kind: ^kind, counted: bonus} <- of(build, ruleset), is_integer(bonus), do: bonus)
    |> Enum.sum()
  end
end
