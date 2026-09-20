defmodule BuildCalculator.Rules.Attack do
  @moduledoc """
  Which ability the attack bonus is computed from — the hook for feats that
  change a **formula** rather than a value.

  Feats come in three kinds (CLAUDE.md §6) and the third one breaks the model
  "feat = bonus":

    1. a flat bonus — Toughness, Epic Prowess;
    2. a prerequisite for other feats — Power Attack -> Cleave, already a graph;
    3. **a different term in the expression.** `Weapon Finesse` makes attack come
       off dexterity when dexterity is higher than strength. That is not "+N to
       attack", and no list of modifiers can express it.

  So the core carries a hook, and `compute/2` reports which ability it landed on
  (`ab_stat` in the prototype, `attack_ability` here). The interface is obliged
  to show it: an attack bonus that is suddenly computed differently and says
  nothing looks like an error in the calculator.

  The hook is **general on purpose**, not a special case wired for Finesse:
  vanilla also has Zen Archery (attack from wisdom) and the monk's unarmed base
  attack, and the shard may add more. The rules live in
  `ruleset.attack_ability`, never here.

  ## The baseline is a property of what is in the hands, not a constant

  Before any feat touches it, which ability the roll comes off is decided by the
  weapon (task 3.34, measured by Dan on 15.08.2026, `GAME_CHECKS.md` N1): «по
  умолчанию для дальнобойного оружие AB считается от мода ловкости, а не силы.
  Как только берешь zen archery — начинается считаться от мудрости». So
  `ruleset.attack_ability` carries a **list** of defaults keyed by the same
  `weapon_must_be` property the rules use, plus one fallback for melee and empty
  hands. Nothing is named here — neither ability, nor property, nor weapon.

  ⚠ Until that day there was **one** default and it was the melee one, so an
  archer with dexterity 18 and strength 8 was shown strength. The hole was known
  and stated (`{:not_modelled, :ranged_attack_ability}`) rather than guessed at,
  because the rule is written on no page of either wiki — it could only be read
  out of `Zen archery`'s own description — and changing the number of every
  armed build off a sentence in a feat's description is not something done
  without a measurement.

  ⚠ That fix removed an artefact worth remembering: while the baseline was
  strength, taking `Zen archery` could **lower** the attack bonus shown to an
  archer, because the feat's own rule replaces dexterity and dexterity was not
  what the model had computed. Nothing was wrong with the rule; the baseline it
  was measured against was. A rule and the thing it replaces have to be the same
  thing.

  ## A rule replaces a **named** ability, and may ask what is in the hands

  Two feats of this kind exist in vanilla and they are not the same shape, which
  is why a rule carries four fields rather than two (14.08.2026):

    * `Weapon finesse` — «melee attack rolls with his dexterity modifier instead
      of **strength** (if his dexterity is higher than his strength)»;
    * `Zen archery` — «their wisdom modifier, if it is higher, instead of their
      **dexterity** when firing **ranged weapons**».

  So `instead_of` says which ability the rule is measured against (`nil` falls
  back to the hook's default), and `weapon_must_be` names a property the weapon
  in hand has to have. Until this was written, `Zen archery` had no rule at all
  and the feat moved nothing whatsoever: a monk with wisdom 18, strength 10 and a
  longbow was shown an attack bonus off strength — four short, silently.

  ## Three questions about the weapon, and none of them derives the others

  A rule may ask about what is in the hands in three ways, because its source
  states the condition in three ways and no two of them can be computed from
  each other (`weapon_one_of` and `weapon_not_two_handed`, task S10, 17.08.2026):

    * a **property** the dictionary carries — `weapon_must_be: :ranged`;
    * a **list of weapons by name** — «Automatic when using any of the following
      weapons: dagger, handaxe, …». Neither wiki states what "light" means as a
      property, both simply enumerate, and Fandom says so outright: «The
      finessable weapons are exactly the ones listed above, regardless of the
      size of the weapon and the size of the wielder»;
    * **not two-handed for this character**, with named exemptions. That one is
      not a column and cannot be: a grip is a function of two sizes, so a rapier
      is one-handed for a human and two-handed for a Карлик. The caller answers
      it (`Rules.Wield.both_hands?/3`), this module only reads the exemptions.

  ⚠ Which weapons, and which of them are exempt, live entirely in the ruleset:
  Siala's page lists thirteen where Fandom lists eleven, and the two it adds —
  the quarterstaff and the spear — are two-handed for everybody, so they are
  exempt by name. Not one weapon id appears in this file, the same way no race
  appears in `Rules.RacialBonus`.

  ## The unknown answer, and who is allowed to give it

  A build that named no weapon has stated nothing, and the two rules of this kind
  answer that differently **out of their own record**, not out of a branch here:
  a rule that states an assumption (`assumes`) may fire on an unknown weapon and
  says what it cost; a rule that states none may not.

  That is one field doing two jobs on purpose. Splitting it would allow two
  combinations that mean nothing — firing on an unknown without saying what was
  assumed, and declaring an assumption nobody ever uses — and the pairing is
  exactly what the two feats need: `Weapon finesse` covers the unarmed strike, so
  a character with empty hands is finessing something either way, while
  `Zen archery` needs a bow that the build has not mentioned.

  ⚠ `weapon_must_be` rather than the `requires_…` it wants to be called: in this
  project `requires_*` is the naming convention for a **refusal**
  (`{:requires_bab, 4}`), and `Rules.Vocabulary`'s guard treats any such head as
  one that owes the player Russian wording. A field of a rule is not a refusal,
  and the guard was right to say so.

  ⚠ **The weapon condition is checked, never assumed.** The weapon in hand is
  part of the build since task 3.5 part B, and the dictionary states which
  weapons are ranged, so writing this down as an assumption the way Finesse's
  light-weapon caveat is written would be a lie in the direction of
  convenience. A build that named **no** weapon is a third answer, not a `false`:
  the rule does not fire (understating is the discoverable error — see the
  markup file's `_weapon_decision`) and the build says so out loud with
  `{:not_modelled, {:attack_ability_weapon, feat}}`.

  ## Rules are candidates, not a chain

  Every rule is judged against the abilities alone and the best of the survivors
  wins, rather than each rule rewriting what the previous one produced. Each is
  measured against **what it says it replaces** (`instead_of`, falling back to
  the baseline the weapon decided), so two rules never have to agree on an order.

  ⚠ Until 15.08.2026 the paragraph here explained that this arrangement was what
  kept `Zen archery` working while the model had no ranged baseline. It has one
  now, and the reason for candidates over a chain is the plainer one above.

  ## Which feats count — **owned**, not picked in a slot

  A rule fires off a feat the character *has*, whatever route it came by:
  a slot, a class grant, or an item declared under «Вещи»
  (`Build.feats_owned/3`). Changing the ability the roll comes off is an
  **effect**, and the effect of a worn feat counts — Dan, 09.08.2026: «если фит
  есть, допустим тафнес, то и HP будут увеличены», left standing when the H7
  measurement of 14.08.2026 split the *requirement* half in two
  (`Rules.GearFeats`, `Build.feats_permanent/3`). What a worn feat does **not**
  buy is another feat's prerequisite, and no prerequisite is asked about here.

  ⚠ Until 14.08.2026 this read `Build.feats_taken/2` — slots only — and a
  `Weapon Finesse` off an item moved nothing at all: a fighter with STR 10 and
  DEX 18 kept attacking from strength and was shown AB 10 where the game gives
  14. Silent, because the feat was owned by every other reader in the core
  (hit points, saves, armour class all walk `feats_owned/3`) and only the
  formula hook disagreed. The same reading also missed a **class grant**, which
  is latent rather than live: no class in either ruleset hands out a feat this
  hook names — checked by walking `granted_feats` of all 23 classes — so the
  bug could only ever be seen through gear.

  ## The assumption

  ⚠ **Narrowed to one case on 17.08.2026** (Dan's measurement, `GAME_CHECKS.md`
  S10). It used to read: weapon size is not modelled, so the calculator assumes
  the weapon qualifies and says so — `{:assumed, :finessable_weapon}` whenever
  Finesse changed the ability. That held while the model had no weapons at all;
  by the time it was removed it meant a build with a **two-handed sword** in hand
  was attacking off dexterity.

  What is left is the honest half: a build that named no weapon. There the
  condition cannot be checked at all, the rule fires, and the assumption is
  printed. A build that named one gets the condition checked and **no caveat** —
  printing "we assumed" about something computed is the false uncertainty
  CLAUDE.md §6 forbids, in the same breath as its opposite.
  """

  # Which field of a weapon record answers a rule's `weapon_must_be`. A closed
  # dictionary and a tiny one on purpose: the property has to be something the
  # weapon dictionary **states**, or the rule would rest on a taxonomy of ours
  # (the same line `Rules.GearWeapon` draws around Siala's proficiency groups).
  #
  # ⚠ `thrown` joined on 25.08.2026 (task 3.101) for a reader outside this
  # module — `Rules.AttackBonuses`, where `Good aim` adds +1 «with throwing
  # weapons». It is stated by the dictionary exactly the way `ranged` is (a
  # Fandom category with four members, and `fandom:Throwing weapon` enumerates
  # the same four in prose), so it belongs to the same closed list rather than
  # to a second one. Two dictionaries of "properties the core can read off a
  # weapon" would be two places to drift.
  #
  # ⚠ `double_sided` joined on 28.08.2026 (task 3.132), and again for a reader
  # outside this module — `Rules.DualWield`, where a double-sided weapon is the
  # second way of being in a two-weapon fight at all. Stated by the dictionary
  # exactly the way the other two are (the `{{Weapon}}` template's own field,
  # and `fandom:Double-sided weapon` names the same three weapons in prose), so
  # it belongs to the same closed list rather than to a third one.
  @weapon_properties %{ranged: :ranged?, thrown: :thrown?, double_sided: :double_sided?}

  @doc """
  Which field of a weapon record a `weapon_must_be` property is read off, or
  `nil` for a property this core cannot answer.

  Asked by the loader, so a ruleset naming a property nobody can check fails the
  build instead of producing a rule that silently never fires — the same
  arrangement `Rules.Gear.weapon_bonus_field/1` has with the item's own numbers,
  and for the same reason: this whole module exists because a feat quietly did
  nothing for months.

  ⚠ Two callers since 25.08.2026, and the second is not about the ability the
  roll comes off at all: `Rules.AttackBonuses` asks the same question of a
  **bonus** whose source names a class of weapons rather than a chosen one. The
  dictionary is shared on purpose — a property the core can read off a weapon is
  one fact, whichever rule needs it.
  """
  @spec weapon_property_field(atom()) :: atom() | nil
  def weapon_property_field(property), do: Map.get(@weapon_properties, property)

  @doc """
  The ability the attack bonus comes off, and what that answer owes the player.

  Returns `{ability, gaps}`. `ability` is `nil` only when the ruleset states no
  default at all, in which case the caller cannot compute an attack bonus
  honestly and should say so rather than pick one.

  The baseline comes first and comes off the weapon (a ranged weapon attacks off
  dexterity, everything else and empty hands off the fallback). Candidate rules
  are then those whose feat the build **owns**, whose ability condition holds
  against what that rule replaces, and whose weapon conditions are satisfied; the
  one with the highest modifier wins, so a Finesse build whose strength is still
  higher keeps attacking from strength — and collects no assumption, because none
  was needed.

  ⚠ A build that named **no** weapon gets the fallback and says so
  (`{:not_modelled, {:attack_ability_default, property}}`) wherever a
  weapon-conditional default would have produced a different number. Both
  directions are reported, unlike a rule's caveat which only reports the
  understating one: here the model is not failing to add a bonus, it is choosing
  a term, and choosing the melee one for an archer with high strength overstates
  — the error a player can only discover in game.

  ⚠ `feats_owned` is the set of feats the character *has*
  (`Build.feats_owned/3`), never the set of feats picked in slots — see the
  moduledoc. `weapon_in_hand` is the id of the weapon that **counts**
  (`Rules.GearWeapon.held/2`), or `nil` when the build named none. `both_hands?`
  is whether that weapon takes both of this character's hands
  (`Rules.Wield.both_hands?/3`) — a grip is a function of the weapon's size *and*
  the wielder's, so it cannot be read off the weapon here. All three stay plain
  values so this module knows nothing about builds, but the caller owes it
  ownership, legality and grip.
  """
  @spec ability(map(), %{atom() => integer()}, Enumerable.t(), atom() | nil, boolean()) ::
          {atom() | nil, [tuple()]}
  def ability(ruleset, modifiers, feats_owned, weapon_in_hand, both_hands?) do
    hook = ruleset.attack_ability
    owned = MapSet.new(feats_owned)
    weapon = weapon(ruleset, weapon_in_hand)
    baseline = baseline(hook, weapon)

    judged =
      for rule <- hook.rules,
          MapSet.member?(owned, rule.feat),
          condition?(rule.condition, modifiers, rule, baseline),
          do: {rule, weapon_verdict(rule, weapon, both_hands?)}

    chosen =
      judged
      |> Enum.filter(fn {rule, verdict} -> applies?(rule, verdict) end)
      |> Enum.max_by(fn {rule, _verdict} -> modifier(modifiers, rule.ability) end, fn -> nil end)

    ability = if chosen, do: elem(chosen, 0).ability, else: baseline

    {ability,
     assumption(chosen, baseline) ++
       unknown_weapon_gaps(judged, modifiers, ability) ++
       unstated_weapon_gaps(hook, modifiers, weapon, baseline)}
  end

  # Which ability the roll comes off before any feat is consulted. The weapon
  # decides, and which property decides what is data — the same
  # `weapon_must_be`/`ability` pair the rules carry.
  #
  # ⚠ A build with nothing in hand takes the fallback, which is also the honest
  # answer for a character who really is unarmed. It is not silent about it, see
  # `unstated_weapon_gaps/4`.
  defp baseline(hook, nil), do: hook.default

  defp baseline(hook, weapon) do
    Enum.find_value(hook.weapon_defaults, hook.default, fn record ->
      if holds?(weapon, weapon_property_field(record.weapon_must_be)) == :ok,
        do: record.ability
    end)
  end

  # `higher_modifier`: the rule's ability has to beat the one it replaces —
  # strength for Finesse, dexterity for Zen archery — which is what «if it is
  # higher» means on both pages.
  #
  # ⚠ Every field added since the hook was written is read through `rule[…]`,
  # never matched — `instead_of` and `weapon_must_be` (14.08.2026), then
  # `weapon_one_of` and `weapon_not_two_handed` (17.08.2026) — so a rule that
  # states none of them behaves exactly as rules did before any of them existed.
  # The two fields the hook has always had stay strict, so a rule missing one of
  # *those* still fails loudly.
  #
  # ⚠ The fallback is the baseline **the weapon decided**, not the hook's melee
  # default (task 3.34). A rule replaces the term the model actually computed;
  # measuring it against a term the model did not compute is exactly what made
  # `Zen archery` able to lower an archer's attack bonus.
  #
  # An unknown condition never fires: the core does not guess at a rule it cannot
  # read.
  defp condition?(:higher_modifier, modifiers, rule, baseline) do
    modifier(modifiers, rule.ability) > modifier(modifiers, rule[:instead_of] || baseline)
  end

  defp condition?(:always, _modifiers, _rule, _baseline), do: true
  defp condition?(_other, _modifiers, _rule, _baseline), do: false

  # Three answers, not two. `:no` is knowledge — the sword in hand is not a
  # ranged weapon and the feat does nothing — while `:unknown` is the build never
  # having said, and only the second is worth telling the player about.
  #
  # ⚠ Три условия, и `:no` у любого перевешивает: правило обязано пройти их все.
  # `:unknown` побеждает только над `:ok` — «не сказано» слабее знания, но
  # сильнее согласия.
  defp weapon_verdict(rule, weapon, both_hands?) do
    [
      property_verdict(rule[:weapon_must_be], weapon),
      list_verdict(rule[:weapon_one_of], weapon),
      grip_verdict(rule[:weapon_not_two_handed], weapon, both_hands?)
    ]
    |> Enum.reduce(:ok, &weakest/2)
  end

  defp weakest(:no, _other), do: :no
  defp weakest(_verdict, :no), do: :no
  defp weakest(:unknown, _other), do: :unknown
  defp weakest(_verdict, :unknown), do: :unknown
  defp weakest(:ok, :ok), do: :ok

  defp property_verdict(nil, _weapon), do: :ok
  defp property_verdict(_property, nil), do: :unknown
  defp property_verdict(property, weapon), do: holds?(weapon, weapon_property_field(property))

  # Оружие названо поимённо (замер S10). ⚠ Здесь ни одного имени нет и быть
  # не может: список приходит правилом, потому что у Сиалы он свой.
  defp list_verdict(nil, _weapon), do: :ok
  defp list_verdict(_list, nil), do: :unknown

  defp list_verdict(list, weapon),
    do: if(MapSet.member?(list, weapon.id), do: :ok, else: :no)

  # «Двуручным не финессится» — и вопрос про ХВАТ задаёт не этот модуль, а
  # вызывающий: хват считается от размера оружия ПРОТИВ размера владельца
  # (`Rules.Wield`), то есть один и тот же предмет отвечает по-разному у человека
  # и у Карлика. Здесь остаётся только поимённое исключение.
  defp grip_verdict(nil, _weapon, _both_hands?), do: :ok
  defp grip_verdict(_ban, nil, _both_hands?), do: :unknown
  defp grip_verdict(_ban, _weapon, false), do: :ok

  defp grip_verdict(%{except: except}, weapon, true),
    do: if(MapSet.member?(except, weapon.id), do: :ok, else: :no)

  defp holds?(_weapon, nil), do: :no
  defp holds?(weapon, field), do: if(Map.get(weapon, field) == true, do: :ok, else: :no)

  # ⚠ На неизвестном оружии правило срабатывает, ТОЛЬКО если само объявило
  # допущение. Это не ветка про два фита, а чтение их записей: `Weapon finesse`
  # покрывает удар без оружия, поэтому пустые руки финессят в любом случае, —
  # а `Zen archery` нужен лук, которого билд не назвал. Разбор — в moduledoc.
  defp applies?(_rule, :ok), do: true
  defp applies?(%{assumes: assumes}, :unknown), do: not is_nil(assumes)
  defp applies?(_rule, _verdict), do: false

  # ⚠ Only where the answer would actually move. A rule whose ability is worth no
  # more than the one already chosen changes no number even with the right weapon
  # in hand, and a caveat about a question that does not arise is noise — the
  # same line `Rules.GearWeapon` draws around its stacking caveat.
  #
  # ⚠ И только у правил, которые на неизвестном оружии НЕ сработали: сработавшее
  # уже сказало своё слово допущением, а два сообщения об одном и том же оружии
  # читались бы как две разные недостачи.
  defp unknown_weapon_gaps(judged, modifiers, chosen_ability) do
    chosen = modifier(modifiers, chosen_ability)

    for {rule, :unknown} <- judged,
        not applies?(rule, :unknown),
        modifier(modifiers, rule.ability) > chosen,
        do: {:not_modelled, {:attack_ability_weapon, rule.feat}}
  end

  # The same admission one level below: the **baseline** depends on the weapon
  # too, and a build that named none was answered with the fallback.
  #
  # ⚠ `!=`, not `>`. A rule's caveat only fires where the model understates,
  # because a rule that would not have raised the number was not owed anything;
  # a baseline is not a bonus, it is the term itself, and picking the melee one
  # for an archer with strength 18 and dexterity 10 **overstates** — the error
  # a player can only discover in game, which is exactly the one this project
  # refuses to make silently (`feat_attack_bonuses.json` →
  # `_weapon_decision.why_4_the_error_must_be_discoverable`).
  defp unstated_weapon_gaps(hook, modifiers, nil, baseline) do
    for record <- hook.weapon_defaults,
        modifier(modifiers, record.ability) != modifier(modifiers, baseline),
        do: {:not_modelled, {:attack_ability_default, record.weapon_must_be}}
  end

  defp unstated_weapon_gaps(_hook, _modifiers, _weapon, _baseline), do: []

  defp weapon(_ruleset, nil), do: nil
  defp weapon(ruleset, id), do: (Map.get(ruleset, :weapons) || %{}) |> Map.get(id)

  defp modifier(_modifiers, nil), do: 0
  defp modifier(modifiers, ability), do: Map.get(modifiers, ability, 0)

  defp assumption(nil, _baseline), do: []

  # ⚠ A rule that landed on the ability the weapon had already chosen moved no
  # number, so its assumption is not one the answer rests on. Before the baseline
  # knew about weapons this could not happen; with a bow in hand it does —
  # `Weapon finesse` fires on dexterity for an archer whose dexterity is already
  # the baseline, and printing «считаем оружие подходящим» about a bow would be
  # a caveat we did not have to make (and a wrong one: the feat is melee-only).
  defp assumption({%{ability: same}, _verdict}, same), do: []

  # ⚠ Проверенное условие оговорки не оставляет (17.08.2026). Оружие названо —
  # список и хват сверены, ответ посчитан, и «мы допустили, что оружие
  # подходящее» было бы ложной неопределённостью ровно того вида, который
  # CLAUDE.md §6 запрещает наравне с молчанием про непосчитанное.
  defp assumption({_rule, :ok}, _baseline), do: []
  defp assumption({%{assumes: nil}, _verdict}, _baseline), do: []
  defp assumption({%{assumes: what}, _verdict}, _baseline), do: [{:assumed, what}]
end
