defmodule BuildCalculator.Rules.AttackBonuses do
  @moduledoc """
  What the **build itself** adds to the attack roll, as opposed to what gear
  added to the governing ability (`gear_attack_bonus`) or what the shard's race
  gives (`Rules.RacialBonus`).

  Before task 1.12b `Rules.compute/2` summed exactly three things into
  `attack_bonus`: the base attack from the class tables and the epic ladder, the
  governing ability's modifier, and those two bonus sources. `Epic prowess` — a
  flat "+1 bonus to all attacks", the example CLAUDE.md §9 itself gives of "a
  feat of the first kind: a flat bonus, trivial" — was not in the numbers at
  all, and not in a gap either. Neither was the +1 a small race gets, whose
  armour class twin was counted from task 3.11 **until task 3.143** (30.08.2026)
  found the same truncated quote on both sides: the size modifier is
  conditional on the target being larger than the character
  (`fandom:Small stature` — "when dealing with larger creatures"), and this
  file had counted it as flat because its own `note` quoted the sentence up to
  "hide checks" and stopped. Both twins are `not_modelled` now.

  ## Nothing here knows a feat, class, skill or race by name

  Which of them raises the attack roll, by how much and what it depends on is
  data — `priv/rules/vanilla/feat_attack_bonuses.json`, read by
  `BuildCalculator.Data.Loader`. There is no `epic_prowess` and no `gnome` in
  this file, and there must never be one.

  ## Almost every bonus here is conditional, and that is the finding

  Of the 81 candidates the sweep classified, **two** were read as unconditional
  bonuses to the attack roll at the time — `Epic prowess` and a small race's
  size modifier — against fourteen for the saves. ⚠ **Task 3.143 (30.08.2026)
  found the second was never unconditional**, only mis-read that way; `Epic
  prowess` is the one true unconditional bonus left in this file. The rest
  depend on the weapon in hand, the enemy's type or relative size, the terrain,
  the range, a mount, a combat mode, an attack of opportunity, a special
  attack, a fighting style, or a once-a-day activation, and an attack bonus is
  the one derived stat where that is the *normal* case.

  Two shapes are computed: `flat`, and `attack_at_class_level` — a table of class
  level to total, which the Weapon Master's own «AB bonus» column needed once task
  3.5 made it countable. ⚠ `ability_modifier` is still guarded rather than
  implemented: its only two records are `Smite evil` and `Smite good`, both
  once-a-day activations, so the loader raises on an `applied` record of that kind
  rather than letting it count as zero.

  ## The weapon, and why it is now a **question about the build**

  `Weapon focus` (+1), `Epic weapon focus` (+2) and the Weapon Master's column
  (+1…+7) apply "with the chosen weapon". Until 10.08.2026 that made them
  `not_modelled`: nothing in the build could say what was in the character's
  hands, so a counted bonus would have been an assumption — and one with a
  neutral alternative, which is the kind this project refuses to make (the whole
  argument is still in the data file's `_weapon_decision`, kept rather than
  rewritten).

  Task 3.5 removed the premise, in two halves: part A gave the `weapon` choice
  domain a dictionary, and part B gave the gear block a weapon in hand
  (`Rules.GearWeapon`). So the three are `applied` now, and the condition became
  a **comparison** instead of an excuse: the bonus counts when the weapon held is
  the weapon the feat names, and does not when it is not — which is exactly what
  the source says.

  ⚠ **The refusal did not disappear, it became conditional.** A build that names
  no weapon, or one whose feats cannot be pinned to a single weapon, still gets
  `{:not_modelled, {:attack_bonus_weapon, id}}` — see `weapon_bonus/4`. Printing
  nothing there would be the overstatement `_weapon_decision`'s fourth argument
  is about: a too-high AB is discovered in game, a too-low one is named on screen.

  Which feats name the weapon is data (`applies_to_weapon.choice_of`), never a
  list here.

  ## A source may name a CLASS of weapons instead, and that is a second form

  Task 3.101 (25.08.2026) finished the same turn for the last two records. Their
  weapon is not "the one you chose for this feat" but a class the page names
  outright — `Good aim` is «+1 with throwing weapons», `Enchant arrow` «only
  operates for bows» — and until that day both were `not_modelled` on the honest
  ground that the class was ours to invent (`ranged` covers crossbows, slings and
  darts too). It was not: both classes are stated, and stated **on the pages of
  the weapons**, which is why neither the original sweep nor the exhaustive read
  of all 299 feat `Notes` had found them — both went by the feat.

  So `applies_to_weapon` now has three keys and a record carries exactly one:

    * `choice_of` — feats whose recorded choice names the weapon;
    * `weapon_must_be` — a **property** the dictionary states, read through
      `Rules.Attack.weapon_property_field/1` (one closed dictionary for the whole
      core, shared with the ability hook);
    * `weapon_one_of` — an **enumeration**, because the source enumerates.

  ⚠ The caveat stayed conditional here too: a build that named no weapon gets
  `{:not_modelled, {:attack_bonus_weapon, id}}` exactly as the focus family does,
  and a build holding the *wrong* weapon gets nothing at all — the game gives
  nothing there either.

  ⚠ **And one enumeration differs between the two rulesets**, which is the shard
  speaking, not this module: «Все классовые умения Тайного лучника теперь
  распространяются на малый и большие арбалеты». That rule belongs to the class
  and has exactly one record (`siala_41/classes.json` → `class_ability_weapons`);
  the loader widens the markup off it rather than letting a second copy live in
  the bonus file, because two records of one rule drift silently (task 3.85).

  ⚠ **And the first of them has to be OWNED, or the bonus does not exist at all**
  (14.08.2026). The list is ordered — the feat that *designates* the weapon
  first, then whatever it may be *inferred* from — and a designator the character
  never took designates nothing. Until M2b that distinction was invisible: the
  Weapon Master was handed `Weapon of choice` by his class, so only its parameter
  could be missing. Once the grant became an optional slot pick, inferring the
  column's weapon from a plain `Weapon focus` started paying **+7 AB** to
  characters who had skipped the feat.

  ## Where the ceiling lives, and it is not here

  `stat_caps.attack_bonus` (+20) is clipped **once**, over every source it
  covers, never once per source (CLAUDE.md §9: clipping by source is how the
  saves came to carry +40 while each source said +20, and task 3.12 already had
  to merge two of these into one clip). `terms/2` and `total/2` return the
  **raw**, uncapped contribution; `Rules.compute/2` is where the one clip
  happens.

  ⚠ **Which sources it covers is not "all of them" any more** (09.08.2026, Dan:
  «Фиты не входят в кап атаки +20»). Task 1.12b put these terms under the ceiling
  by analogy with the saves, where a class ability under the +20 is quoted word
  for word; for attack no such quote exists, and the player says the analogy is
  wrong. So a term carries `under_cap?`, and `Rules.compute/2` clips only the
  terms that answer `true`, adding the rest on top of the clip. Reading which side
  of a ceiling a source falls on is a lookup; applying the ceiling is still one
  clip, and still there.

  ⚠ **And that lookup is per record, not per kind** — the second correction of the
  same rule on the same day. Dan named `Divine grace` (outside) against `Sacred
  defense` (inside) on the save side: two class abilities, both written in the data
  in the shape of a feat. So the side is a field of the record
  (`bonuses[].cap`, `Rules.Caps.covers_record?/3`) and never a property of
  `{:feat, _}`. Both records here are outside the +20; the day one of them is not,
  nothing in this module has to change.

  ## Что здесь своё, а что общее

  Чтение файла, «держит ли персонаж эту запись», сбор гэпов из отвергнутых и
  `effect_coverage` — общие для пяти статов и живут в
  `BuildCalculator.Rules.Bonuses` (задача 3.21). Здесь остаётся специфика
  атаки: **две** формы отказа вместо одной (оружие против всего остального),
  порог таблицы по уровням класса у отвергнутой записи и сторона капа на
  терме.

  ⚠ Чего здесь нет и не должно появиться — **смены формулы**. От какой
  характеристики считается атака (`Weapon Finesse`, `Zen Archery`) решает
  `Rules.Attack`, и это не прибавка, а другое слагаемое в самом выражении
  (CLAUDE.md §6, «фиты бывают трёх видов»). Втянуть третий вид в механизм
  прибавок значило бы потерять именно то различие, ради которого у
  `DerivedStats` есть поле `attack_ability`.
  """

  alias BuildCalculator.Rules.{Attack, Bonuses, Build, Caps, GearWeapon}

  @markup :attack_bonuses

  @typedoc """
  One source's contribution to the attack roll.

    * `id` — the feat, class, skill, racial trait or race, for the breakdown
      and the gaps
    * `source` — `{:feat, id}` / `{:class, id}` / `{:skill, id}` /
      `{:race_feat, id}` / `{:race, id}`
    * `bonus` — the contribution, already worked out for this build
    * `under_cap?` — whether `stat_caps.attack_bonus` covers this source at all.
      A breakdown needs it to place the row: a term the ceiling never touched
      printed above the "сверх капа" line would blame it for a loss it did not
      take
  """
  @type term_entry :: %{
          id: atom(),
          source: {atom(), atom()},
          bonus: integer(),
          under_cap?: boolean()
        }

  @doc """
  Every attack-roll term this build earns by itself, in the data's own order.

  A source that works out to zero is left out rather than listed as `+0`, the
  same rule `Rules.SaveBonuses.terms/3` follows — a breakdown row worth nothing
  costs a line and answers nothing.

  ⚠ Takes no ability modifiers, unlike its three siblings: no `applied` record
  is of the `ability_modifier` kind (`Smite evil`'s charisma is `not_modelled`,
  it is a once-a-day attack), so there is nothing here to compute against a
  modifier map. Adding the argument "for symmetry" would invite a caller to
  pass the geared modifiers where the naked ones belong — the choice
  `attack_bonus` itself has to make, and makes explicitly in `rules.ex`.
  """
  @spec terms(Build.t(), map(), [atom()] | nil) :: [term_entry()]
  def terms(%Build{} = build, ruleset, held \\ nil) do
    level = Build.character_level(build)
    held = held || main_hand(build, ruleset)

    # ⚠️ Пропускаются ДВА вердикта, а не один: `:counts` — прибавка на оружие,
    # оружие совпало; `:not_weapon_conditional` — прибавка верна при любом оружии
    # (`Epic prowess`, размерный модификатор). Фильтр «только :counts» отобрал бы
    # у воина 41 его +1 — и это ровно то, что поймали тесты 1.12b, когда он тут
    # стоял.
    for record <- Bonuses.held(build, ruleset, @markup, level),
        weapon_bonus(record, build, ruleset, level, held) in [:counts, :not_weapon_conditional],
        bonus = amount(record, build),
        bonus != 0 do
      %{
        id: record.id,
        source: record.source,
        bonus: bonus,
        under_cap?: Caps.covers_record?(ruleset, :attack_bonus, record)
      }
    end
  end

  @doc """
  The same, summed — every term, both sides of the ceiling.

  ⚠ Not "what is offered to the ceiling": since 09.08.2026 only the terms whose
  `under_cap?` is `true` are, and the split is `Rules.compute/2`'s to make. This
  is the build's own contribution before anything is clipped, which is what
  `stats.own_attack_bonus` carries.
  """
  @spec total(Build.t(), map(), [atom()] | nil) :: integer()
  def total(%Build{} = build, ruleset, held \\ nil) do
    build |> terms(ruleset, held) |> Bonuses.sum(:bonus)
  end

  # Что считается «в руках», если вызывающий не сказал. Главная рука — то же,
  # что было до задачи 3.132, и потому же остаётся умолчанием: у всех прежних
  # читателей рука была одна.
  #
  # ⚠ Список, а не одно значение, и не имя руки: у ДВУСТОРОННЕГО оружия обе
  # руки держат ОДИН предмет, то есть «оружие второй руки» и «рука :off»
  # перестают совпадать. Вызывающий знает, какой ответ ему нужен; этот модуль
  # не должен угадывать.
  defp main_hand(build, ruleset) do
    case GearWeapon.held(build, ruleset, :main) do
      nil -> []
      weapon -> [weapon]
    end
  end

  @doc """
  Sources this build has whose attack bonus the model does **not** count, and
  whose condition is something other than the weapon in hand.

  Returns ids, sorted and deduplicated. The build turns them into
  `{:not_modelled, {:attack_bonus, id}}` — a combat mode, a rage, a bonus
  narrowed to one kind of enemy, to wilderness, to a mount, to an attack of
  opportunity, to one special attack. Every one of them is either switched
  **off** by default (the same line `Rules.ArmorClass` and `Rules.SaveBonuses`
  draw for the very same abilities) or narrower than "every attack roll", which
  showing as a flat number would overstate exactly where the source is precise
  about *not* applying.
  """
  @spec unmodelled(Build.t(), map(), non_neg_integer()) :: [atom()]
  def unmodelled(build, ruleset, level), do: rejected(build, ruleset, level, &(&1 != :weapon))

  @doc """
  The same, but only the ones whose condition **is** the weapon in hand — plus
  the counted ones whose weapon this build cannot pin down.

  Kept apart from `unmodelled/3` because the two need different sentences and
  they are true in different ways. "Не всегда и не против всего" is permanent;
  "только выбранным оружием" is a statement about *this build*, which naming a
  weapon in the gear block lifts — and the interface saying so is the difference
  between a rule and a to-do. The build reports these as
  `{:not_modelled, {:attack_bonus_weapon, id}}`.

  Two halves since 10.08.2026, and the second is the point of task 3.5 part B:

    * records still `not_modelled` — `Enchant arrow` (bows) and `Good aim`
      (throwing weapons). Their weapon is named as a **class** of weapon, and the
      dictionary has no field for either class, so counting them would mean
      inventing a taxonomy (`ranged: true` covers crossbows and slings too);
    * records `applied` whose weapon came back `:unknown` — no weapon in hand, or
      nothing recorded, or two focuses and nothing to choose between them
      (`weapon_bonus/4`). ⚠ A record whose weapon is simply **the wrong one** is
      *not* here: the game gives nothing there either, so there is nothing to
      confess. ⚠ Neither is one whose **designating feat the character does not
      have** (`:no_designator`, 14.08.2026): a Weapon Master who skipped
      `Weapon of choice` is not owed a caveat about a column he was never
      entitled to, any more than about any other feat he did not take.
  """
  @spec weapon_conditional(Build.t(), map(), non_neg_integer()) :: [atom()]
  def weapon_conditional(build, ruleset, level) do
    rejected(build, ruleset, level, &(&1 == :weapon)) ++ unknown_weapon(build, ruleset, level)
  end

  # ⚠️ `reached?/2` здесь по той же причине, что и у отвергнутой половины: у
  # Мастера оружия 3 колонка «AB bonus» печатает «-», и оговорка «не считаем
  # твою прибавку» предупреждала бы о том, чего ещё не происходит. Без этого
  # фильтра гэп появлялся бы с первого уровня класса — ровно то, что поймал
  # тест 1.12b, когда фильтр стоял только у одной половины.
  defp unknown_weapon(build, ruleset, level) do
    # ⚠ ПО ВСЕМ рукам сразу, а не по главной (задача 3.132): «оружия не назвали»
    # перестало быть вопросом об одном предмете. Билд, у которого фокус совпал
    # со вторым оружием, ничего не должен читателю — а спросив только главную
    # руку, мы напечатали бы ему оговорку про уже посчитанное.
    held = for {_hand, weapon} <- GearWeapon.held_all(build, ruleset), do: weapon

    for record <- Bonuses.held(build, ruleset, @markup, level),
        reached?(record, build),
        weapon_bonus(record, build, ruleset, level, held) == :unknown,
        uniq: true,
        do: record.id
  end

  @doc """
  Whether the whole of what this feat does is already in the numbers.

  Same contract as `Rules.FeatBonuses.whole_effect_counted?/1` and its two
  siblings: the claim is the data's (`effect_coverage: "whole_feat"`), never
  inferred from the bonus being applied. `Enchant arrow` is `applied` here and
  `false` — its damage and damage-reduction remainder (see its own `note`) is
  counted nowhere, so the general "прибавку от фита не считаем" caveat has to
  keep costing something for it.

  ⚠ `Small stature` used to be the example here — `applied` with `false` for
  its +4 to the four stealth and detection skills. Task 3.143 (30.08.2026)
  moved the record to `not_modelled` (its attack half was never unconditional;
  the truncated quote made it look so), where `effect_coverage` is forbidden
  outright — and this asker filters on `{:feat, feat_id}` sources besides,
  which `Small stature`'s `{:race_feat, _}` never matched at all, at any
  verdict.

  ⚠ **That day came on 10.08.2026** (task 3.5 part B). This used to say that no
  `applied` record here was repeatable, so `Rules.FeatChoices.gaps/3` — the only
  caller — never reached one. `Weapon focus` is now both `applied` and repeatable
  by weapon, and without this asker the build would have printed «прибавку от фита
  в статы не считаем» beside the `Weapon focus +1` row of its own AB breakdown.
  """
  @spec whole_effect_counted?(atom(), map()) :: boolean()
  def whole_effect_counted?(feat_id, ruleset) do
    Bonuses.whole_effect_counted?(ruleset, @markup, feat_id)
  end

  @doc """
  Оба вида отказа, уже в виде гэпов билда — **две** формы, а не одна.

  `{:not_modelled, {:attack_bonus, …}}` — привычная половина: боевой режим,
  ярость, прибавка против одного вида врагов или на одном виде местности. Они
  не станут считаемыми ничем, кроме моделирования боя.

  `{:not_modelled, {:attack_bonus_weapon, …}}` — половина, которая является
  утверждением про **этот калькулятор**, а не про игру: `Weapon focus` и
  колонка Мастера оружия — плоские безусловные числа, **если знать, что у
  персонажа в руках**, и армори (задача 3.5) это узнает. Сформулировать их
  одинаково значило бы либо обещать симулятор боя, либо спрятать долг; см.
  `vanilla/feat_attack_bonuses.json` → `_weapon_decision`.
  """
  @spec gaps(Build.t(), map(), non_neg_integer()) :: [tuple()]
  def gaps(%Build{} = build, ruleset, level) do
    for(id <- unmodelled(build, ruleset, level), do: {:not_modelled, {:attack_bonus, id}}) ++
      for(
        id <- weapon_conditional(build, ruleset, level),
        do: {:not_modelled, {:attack_bonus_weapon, id}}
      )
  end

  @doc """
  Whether a record whose bonus needs a particular weapon reaches the attack roll
  on this build — `:counts`, `:wrong_weapon`, `:unknown` or `:no_designator`.

  `:not_weapon_conditional` for a record that has no such condition at all
  (`Epic prowess`), so the four answers below are only ever about the three that
  do.

  ## The answers, and why the last two exist

    * `:counts` — the weapon in hand is the weapon the record names;
    * `:wrong_weapon` — it is not, and that is a **fact, not a gap**: the game
      gives nothing there either, so nothing is owed to the player;
    * `:unknown` — nobody can say which weapon the record means. No weapon in
      hand, or nothing recorded, or — the case worth the code —
      **several candidates and no way to choose**;
    * `:no_designator` — the character does not **have** the feat that names the
      weapon, so there is no named weapon to compare anything with. Silent, like
      `:wrong_weapon` and for the same reason: the game gives nothing here
      either.

  ## Why the last one is a separate answer and not a shade of `:unknown`

  «Оружия не назвали» and «фита нет» look alike from inside `weapon_choices/4` —
  both arrive as an empty list of recorded values — and they are opposite facts.
  The first is a hole in *our* record of the build and is owed a caveat; the
  second is the build, and a caveat there would warn about a bonus the character
  was never entitled to.

  ⚠ **That confusion was a live bug, 14.08.2026.** The Weapon Master's column
  takes its weapon from `weapon_of_choice` and, failing that, infers it from
  `Weapon focus`. While the class *handed the feat over* the inference was
  sound — every Weapon Master had it, only its parameter was unrecorded. Once
  M2b turned the grant into an optional slot pick («Получается я могу и не брать
  weapon of choice!»), the same inference started handing **+7 AB** to a
  character who had not taken the feat at all: the column was being derived from
  a feat that designates nothing for it.

  So ownership of the designator is checked **before** the weapon is looked up,
  and it is checked with `Build.feats_owned/3` — a slot pick, a class grant or an
  item alike, because this is the feat's *effect* and an item's feats count
  towards effects (CLAUDE.md §3).

  The last one is `Epic weapon focus`, and it is the reason this is not a one-line
  membership test. The epic feat records no weapon of its own (`repeatable: nil`
  on vanilla): its weapon is the one its ordinary `Weapon focus` names, which is
  what its own prerequisite says. With one focus in the build that is determined.
  With **two** — legal, `distinct: true` — the epic one was taken for one of
  them and the build does not record which, so counting +2 because the weapon in
  hand happens to be *a* focus would overstate AB on half of those builds.

  ## Whose choice it is, and the data says so by ordering

  `applies_to_weapon.choice_of` lists the feat the record **designates** its
  weapon with first, and whatever the weapon is only *inferred* from after that.
  That ordering is the whole rule:

    * values from the **designator** are usable as they stand, all of them, because
      each of its takes names its own weapon. `Weapon focus` designates for
      itself; `weapon_of_choice` designates for the Weapon Master's column, and
      with two of them **both** weapons benefit — which is the source's own
      explanation of why a second one is worth taking: «it designates which weapon
      **types** benefit from the other weapon master feats», «it is possible for
      an epic weapon master to take additional weapons of choice»
      (`fandom:Weapon of choice`, revid 65834);
    * values from a **later** entry are an inference, and an inference is usable
      only while it is unambiguous. `Epic weapon focus` records no weapon of its
      own, so with two ordinary focuses in the build it stays `:unknown`; so does
      the Weapon Master's column on a build that has recorded no weapon of choice
      at all, which is exactly how it behaved before task 3.26 and how every
      already-shared link still behaves.

  ⚠ The distinction is the **position in the data**, never the kind of source. A
  class record and a feat record get the same answer for the same reason, the way
  `Rules.Caps` reads a ceiling's side per record rather than per kind (CLAUDE.md
  §9: `Divine grace` against `Sacred defense`).

  ⚠ And the designator's **ownership** comes off the same position, so the file
  states one fact once. For `Weapon focus` and `Epic weapon focus` the designator
  *is* the record's own source, so the check is what `Bonuses.held/4` already
  did; it bites on exactly one record — the Weapon Master's column, whose
  designator is a feat and whose source is a class.
  """
  @spec weapon_bonus(map(), Build.t(), map(), non_neg_integer(), [atom()]) ::
          :not_weapon_conditional | :counts | :wrong_weapon | :unknown | :no_designator
  def weapon_bonus(record, %Build{} = build, ruleset, level, held) do
    case {Map.get(record, :weapon), Map.get(record, :weapon_kind)} do
      {nil, nil} -> :not_weapon_conditional
      {nil, kind} -> weapon_kind_verdict(kind, held, ruleset)
      {feats, _kind} -> weapon_verdict(feats, build, ruleset, level, held)
    end
  end

  # Вторая форма условия (задача 3.101): оружие названо КЛАССОМ, а не выбором
  # фита. Ответов здесь три из тех же четырёх, и `:no_designator` среди них нет
  # по построению — назначающего фита у такой записи не бывает вовсе, оружие
  # называет собственный источник записи, а держит ли персонаж сам источник,
  # уже спросил `Bonuses.held/4`.
  #
  # ⚠ `:unknown` остаётся ровно там, где было: билд оружия не назвал, сравнивать
  # не с чем, и об этом надо сказать вслух. Это та половина отказа, которую
  # задача 3.5 (часть B) сделала условной у семейства фокуса, и здесь она
  # условная по той же причине и с той же формой гэпа.
  defp weapon_kind_verdict(_kind, [], _ruleset), do: :unknown

  defp weapon_kind_verdict(kind, held, ruleset) do
    if Enum.any?(held, &weapon_of_kind?(kind, &1, ruleset)), do: :counts, else: :wrong_weapon
  end

  # ⚠ Ни имени оружия, ни имени свойства здесь нет: свойство приходит записью,
  # а какое поле справочника на него отвечает, знает ОДИН закрытый словарь ядра
  # (`Rules.Attack.weapon_property_field/1`) — тот же, которым пользуется хук
  # характеристики атаки. Второй словарь про «что ядро умеет прочитать
  # с оружия» разъехался бы с первым молча.
  defp weapon_of_kind?({:one_of, ids}, id, _ruleset), do: MapSet.member?(ids, id)

  defp weapon_of_kind?({:property, property}, id, ruleset) do
    field = Attack.weapon_property_field(property)

    case Map.get(ruleset.weapons || %{}, id) do
      %{} = weapon -> not is_nil(field) and Map.get(weapon, field) == true
      _unknown_weapon -> false
    end
  end

  # ⚠ `level` — у выбора фита, но НЕ у оружия в руках: `Build.truncate/2` вещи не
  # трогает сознательно (`Rules.Build`), поэтому дельта уровня видит то же оружие,
  # а вот фит, взятый на 27-м, не имеет права менять посчитанное на 26-м.
  defp weapon_verdict(feats, build, ruleset, level, held) do
    if designator_held?(feats, build, ruleset, level) do
      case weapon_choices(feats, build, ruleset, level) do
        {_feat, []} -> :unknown
        {_feat, _choices} when held == [] -> :unknown
        {feat, choices} -> weapon_match(feats, feat, choices, held)
      end
    else
      :no_designator
    end
  end

  # Владение — `feats_owned/3`, то есть слот, выдача класса или вещь: речь про
  # ЭФФЕКТ фита, а эффекты фитов с вещи считаются (CLAUDE.md §3, задача 3.3).
  #
  # ⚠ Ни одного имени фита здесь нет и быть не может: кто назначает оружие,
  # сказано данными — первым элементом `applies_to_weapon.choice_of`.
  defp designator_held?([designator | _rest], build, ruleset, level),
    do: MapSet.member?(Build.feats_owned(build, ruleset, level), designator)

  # Первый фит списка, у которого выбор записан хоть раз, вместе с самим списком
  # записанных значений. Порядок — из данных (`applies_to_weapon.choice_of`):
  # собственное взятие точнее наследования, поэтому оно и стоит первым.
  #
  # ⚠ `feat_choices_owned/4`, а не `feat_choices/3`, и это две задачи подряд.
  # 3.26: `weapon_of_choice` Мастеру оружия **выдаёт класс**, слота у выдачи нет,
  # и до неё её значение не лежало нигде — оружие приходилось выводить от
  # `Weapon focus`, а вывод однозначен только пока фокус один. У билда с двумя
  # фокусами колонка теряла свои +7 (Воин 13 / ВМ 28: 39 → 32). Записанная
  # выдача читается ПЕРВОЙ по тому же порядку `choice_of`, поэтому вывод остался
  # запасным путём: старая ссылка, где выбор не записан, считается как раньше.
  #
  # ⚠ 3.97 добавила третий источник — ПРЕДМЕТ. Речь по-прежнему про ЭФФЕКТ фита,
  # а эффект фита с вещи считается (H7), поэтому здесь `_owned`, ровно как
  # `designator_held?/4` рядом уже читает `feats_owned/3`. До правки это была
  # половина ответа: фит с амулета в список владения попадал, а названное им
  # оружие — нет, то есть `Weapon focus` с вещи не мог совпасть ни с чем.
  defp weapon_choices(feats, build, ruleset, level) do
    Enum.reduce_while(feats, {nil, []}, fn feat, acc ->
      case recorded_choices(build, ruleset, feat, level) do
        [] -> {:cont, acc}
        choices -> {:halt, {feat, choices}}
      end
    end)
  end

  defp recorded_choices(build, ruleset, feat, level) do
    build
    |> Build.feat_choices_owned(ruleset, feat, level)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # ⚠ `held` — СПИСОК с задачи 3.132: рук две, и прибавка достаётся той, чьё
  # оружие названо фитом. Совпадение хотя бы с одной рукой — это `:counts`,
  # потому что список приходит с той стороны, которая знает, про какую руку
  # спрашивает: `terms/3` передаёт одну руку, `gaps/3` — обе.
  defp weapon_match(feats, feat, choices, held) do
    matched = Enum.filter(held, &(&1 in choices))

    cond do
      matched != [] and (own_designator?(feats, feat) or match?([_one], choices)) -> :counts
      matched != [] -> :unknown
      true -> :wrong_weapon
    end
  end

  # Пришли ли значения от того фита, которым запись НАЗНАЧАЕТ себе оружие, — или
  # от следующего в списке, то есть по выводу.
  #
  # Порядок `applies_to_weapon.choice_of` и есть этот ответ: первым стоит
  # собственный назначающий фит записи, дальше — то, от чего оружие только
  # выводится («собственное взятие точнее наследования» — комментарий записи в
  # `vanilla/feat_attack_bonuses.json`). Каждое взятие назначающего фита называет
  # своё оружие, поэтому его значения годятся все; выведенное годится, только пока
  # оно одно.
  defp own_designator?([designator | _rest], feat), do: designator == feat
  defp own_designator?(_feats, _feat), do: false

  defp rejected(%Build{} = build, ruleset, level, keep?) do
    Bonuses.rejected_ids(build, ruleset, @markup, level,
      filter: &(keep?.(&1.condition) and reached?(&1, build))
    )
  end

  # A rejected bonus stated as a table of class levels is only worth a caveat
  # once the build has reached the table's first step. The Weapon Master's own
  # «AB bonus» column prints "-" for class levels 1–4, and a build at Weapon
  # Master 3 told "we do not count your attack bonus" would be warned about
  # something that is not happening yet — the shape of noise
  # `Rules.ArmorClass`'s `gear_base/1` avoids for the same reason.
  #
  # Every other shape is relevant the moment it is held: a flat number and an
  # ability modifier have no step to reach.
  defp reached?(%{amount: %{kind: :attack_at_class_level} = amount}, build) do
    case Map.keys(amount.attack_at_class_level) do
      [] -> false
      steps -> Bonuses.class_level(build, amount.class) >= Enum.min(steps)
    end
  end

  defp reached?(_record, _build), do: true

  # ⚠ Two clauses of `amount/2` and no catch-all, deliberately. Which kinds may
  # reach an applied record is enforced where the data is read (`Loader`'s
  # `@applied_attack_bonus_kinds`, which raises at **compile** time on anything
  # else), so an unmatched shape here is a broken build and not a live request.
  # A fallback returning zero would turn that into the one failure this module
  # exists to prevent: a bonus that quietly counts for nothing.
  defp amount(%{amount: %{kind: :flat, bonus: bonus}}, _build), do: bonus

  # Таблица «уровень класса → ИТОГ на ступени» — колонка «AB bonus» Мастера
  # оружия. Чтение общее и не своё: `Bonuses.total_at_step/2`, тот же читатель,
  # что у `ac_at_class_level` и `save_at_class_level`. ⚠ Противоположное чтение
  # (ступени суммируются) живёт у характеристик, и путать их нельзя — колонка
  # печатает накопленный итог, поэтому у Мастера оружия 28 это +7, а не +28.
  defp amount(%{amount: %{kind: :attack_at_class_level} = amount}, build) do
    Bonuses.total_at_step(
      amount.attack_at_class_level,
      Bonuses.class_level(build, amount.class)
    )
  end
end
