defmodule BuildCalculator.Rules.ArmorClass do
  @moduledoc """
  What the **build itself** adds to armour class, as opposed to the equipment
  the player types.

  Until task 3.11 armour class was `base_ac + dexterity + <what was typed under
  "Вещи">` and nothing else, so a Cleric 35 / Monk 4 — a build the shard's
  players take *for its AC*, four monk levels precisely because Siala moved the
  bonus off the first — came out at 10. Worse than the number was the silence:
  not one gap said a class ability had gone missing.

  ## Nothing here knows an ability by name

  Which class, feat, skill or racial trait raises armour class, by how much and
  in what shape is data — `priv/rules/vanilla/ac_bonuses.json`, read by
  `BuildCalculator.Data.Loader`. There is no monk, no pale master and no tumble
  in this file, and there must never be one.

  ## Four shapes, and why they are not one number

    * **flat** — `Armor skin` (+2), the file's only `applied` example of the
      shape. ⚠ `Small stature` (+1) used to be the second until task 3.143
      (30.08.2026): its condition ("when dealing with larger creatures") had
      been read off a quote truncated one clause short, and the fix moved it
      to `not_modelled` — the amount is still `flat`, it simply is not counted.
      A number, while the character has the thing.
    * **ability modifier** — `Monk AC bonus`, the whole of wisdom. ⚠ Computed
      off the modifiers handed in, which is why the caller passes them: the
      naked number uses the naked score and the geared one the geared score,
      the same cascade constitution runs in hit points.
    * **at class level** — `Bone skin`, `Draconic armor`, the Monk's own table
      column. A table of `class level => armour class`, and the values are the
      **total at that level**, not an increment — that is how the wiki's class
      progression tables print them, and both of the doubled sources (feat page
      and class table) agree number for number. ⚠ Deliberately the opposite
      reading from `hp_at_class_level` next door, where the steps are summed;
      each file states its own.
    * **per skill ranks** — `Tumble`, +1 per 5 **base** ranks, which is exactly
      the number a build stores.

  ## What is owned, and by what

  A feat counts when the character **owns** it — picked in a slot or handed
  over by a class — because a feat is a feat however it arrived, and every one
  of these arrives by grant. A class table counts from the class's own level. A
  racial trait counts off the race, never off `Build.feats_owned/3`: racial
  bonus feats are not in there, and widening that function would silently
  change every prerequisite check in the application (a Gnome carries
  `spell_focus` as a racial trait).

  ## And two terms that are not in that file at all

  The shard's own racial bonus (task 3.12) is armour class for exactly one race,
  and its numbers live with the race rather than here —
  `BuildCalculator.Rules.RacialBonus`, off `priv/rules/siala_41/races.json`. It
  arrives as a term like any other, typed `shield`, so the collision rules below
  see it; what it does **not** do is arrive at every level, because its size is
  only known at the level the wiki states it for.

  The second is the same bonus from the other side (task 3.35): the shard gives
  shield armour class for holding a **blade**, and by name for three weapons that
  are not blades (`BuildCalculator.Rules.WeaponTypeBonus`). Same type, same level
  rule, and a Gnome with a longsword genuinely carries both — which is why the
  collision below is not a corner case any more.

  ## One condition is checked, and it is checked against the item worn

  A record may name a `scope` — the condition under which the game takes the
  bonus away. The Monk's is `no_ac_from_worn` over `armor` and `shield`, and
  since 09.08.2026 it is a **rule** rather than a caveat. Dan has stated it
  twice, and the second statement is the narrower one — the readings stack in
  the order they arrived, none of them wrong for what it could see:

    * **both wikis** name the *kind* of thing worn («если носит доспехи или
      использует щит»), and by kind the question was unanswerable: a robe and
      bracers are things a monk is supposed to wear, and the model of the day
      knew only one number per type.
    * **09.08.2026** names the AC it gives («любой доспех, который **даёт AC**»),
      which a model without items could check, because AC by type is what the
      player enters. That is what made the condition a rule at all.
    * **19.08.2026** names the item: «бонусы монаха опираются **исключительно**
      на надетый щит и доспех, числа в "AC по типам" не влияют». Dan's own robe
      *gives* 6 AC and keeps the bonuses; plate takes them away. What counts is
      the **base** of the thing picked, and the base is what task 3.41 made
      knowable.

  Three things worth spelling out, because each is a way of getting it wrong:

    * it reads `Worn.base_ac/2` — **the item the player picked** — and neither
      the number typed under the same type nor the summed total for it. Two
      different traps, and they are not one. The **total** would take a Gnome
      monk's bonuses away for being a Gnome: the shard's racial bonus is armour
      class typed `shield` (task 3.12), and so is a blade in hand (task 3.35),
      and neither is a shield anybody put on. The **typed number** is a bonus —
      the robe's own enchantment, a spell, a property of an item — and not a
      piece of equipment at all.
    * `ac_naked` is unaffected by construction, and not by a special case:
      `Rules.compute/2` computes the naked pass off a build with **no gear at
      all**, so the condition holds there whatever is worn. Naked means naked.
    * a `scope` whose `kind` the core cannot check is not silently dropped. The
      bonus stays in the number and the build says
      `{:not_modelled, {:ac_bonus_scope, id}}` — the Spellcraft precedent, show
      the number and print the caveat. No record needs that today; the branch is
      what stops the next unformalisable condition from becoming silence.

  ## Two bonuses of one type — four rules, and they are not one rule (tasks 3.39, 3.91)

  ⚠ Here stood «same-typed bonuses do not stack in the game, and this sums them
  anyway», with `{:not_modelled, :ac_same_type_stacking}` as the caveat. Both
  halves of that are gone: the rule is applied now, and it turned out to be four
  rules of different provenance. All four are **data**
  (`gear.ac_types.same_type`), none of them is decided here:

    * **own against own — they add up.** Measured, twice over: Dan on 16.08.2026
      (`GAME_CHECKS.md` E5 — `Draconic armor` beside `Armor skin`, both
      `natural`, worth exactly +2 more together) and the shard's own «Расы»
      page, where a Gnome holding a blade gets **+12** (6 racial + 6 for the
      weapon type) and a Sagra warrior **+18**. Nothing changed here.
    * **own against what the player typed — they add up too.** «АЦ с фитов
      всегда стакаются все», «вот амулет + 5 и armor skin стакаются, должна быть
      сумма» (Dan, 25.08.2026, `GAME_CHECKS.md` X1).
    * **except a shape declared an exception** — `own_vs_gear_by_kind`, and
      today it holds exactly one: the shard's `shield_ac`, which is the Gnome's
      racial bonus and a blade in hand seen from two sides. That one
      **supersedes** the typed shield bonus rather than adding to it: «раса
      карлика… перекрывает бонус щита (не базу щита(1/2/3), а именно бонус)»
      (Dan), and off the «Расы» page since 01.08.2026: «Этот класс брони не
      складывается с бонусом класса брони щита, но складывается с базовым
      классом брони щита».
    * **and except a type declared cumulative** — `dodge` today — which adds up
      with the typed number whatever the shapes in it say, and is then clipped
      **once**, over the sum. Clipping the two halves separately is how the
      saves once carried +40 while every source said +20 (CLAUDE.md §9).

  🔴 **The second rule was `max` until 25.08.2026, and that was a silent
  understatement** (task 3.91). It rested on the «Расы» sentence quoted in the
  third bullet — a sentence about **one** bonus — plus a wider one of Dan's
  («никакое АЦ не складывается, когда дело касается вещей») that his own
  narrowing later placed where it belongs: gear and buffs meeting **each other**,
  of which this model holds neither. A Fighter 21 with `Armor skin` and +5 of
  natural armour typed in showed 16 instead of 18; a Red Dragon Disciple lost up
  to 8. The player could not have found it from inside the tool — the number
  looked plausible. It is the same shape of error CLAUDE.md §3 records three
  times over: a quote about one source becomes a rule about every source of its
  kind.

  ## The item's base is a third thing, and it always stacks (task 3.41)

  Since armour and shields became items with a size
  (`BuildCalculator.Rules.Worn`) a type has **three** addends, and they behave
  differently on purpose:

      counted = stacking + max(competing, typed) + base

  «а вот с АЦ щитовым с вещей это не складывается, **только с базой щита**»
  (Dan, 16.08.2026) — the base is the half of that sentence task 3.39 could not
  reach, because one typed number cannot be split into a base and a bonus. Now
  it is not split: the player names the item, and its base comes off the source's
  own table.

  ⚠ The base is **not** part of the competition and never loses one: it is added
  after the larger of the two is chosen, whichever side that was. Neither is the
  `stacking` part of the build's own side, which is why the formula has three
  addends and not two.

  ## What that rule honestly cannot do, and says so

  On a type nobody picks an item for — deflection, natural armour — the old
  problem stands: one typed number, no way to tell a base from a bonus. So
  `{:not_modelled, {:ac_gear_base, type}}` stays, and stays exactly there —
  `Worn.item_type?/2` is what decides, so the caveat disappears from the two
  types the player can now answer for and from no others. Printing it beside an
  answered question would be the false uncertainty CLAUDE.md §6 forbids.

  ⚠ **No build produces it today** (task 3.91), and the branch stays for the same
  reason the unformalisable `scope` one does. The caveat only ever fires where a
  contest actually happened, and the one shape that competes is typed `shield` —
  a type the player picks an item for, so its base is known. The day a competing
  shape lands on `deflection` or `natural`, the caveat comes back by itself
  rather than having to be remembered.

  ## And the dexterity bonus meets a ceiling of its own

  `fandom:Maximum dexterity bonus` (revid 59855): armour caps the dexterity
  bonus **to armour class** and to nothing else — «it does not affect the attack
  bonus for ranged weapons, the attack bonus from weapon finesse, reflex saves,
  nor dexterity-based skills». Hence `geared/3` returns the dexterity term
  already resolved (`dexterity`), and `Rules.compute/2` uses that one number in
  «AC в шмоте» while the reflex save, the attack roll and every skill go on
  reading the modifier itself. Capping the modifier would have been shorter and
  wrong in three places at once.

  ⚠ «AC голым» is untouched by construction and not by a special case: the naked
  pass runs over a build with no gear at all, so nothing is worn and there is no
  ceiling to meet.

  ⚠ A **penalty** does not compete. When either side is zero or below, the two
  are added instead: every source states this as a rule about bonuses, none
  states a floor, and letting `max/2` swallow a typed −3 would delete a number
  the player entered (the same one-sidedness `Rules.Caps.clamp/3` has).

  ## What it still does not decide

  A type nobody wrote down. Four of the seven applied records have no type at
  all, because their pages name none, and a type assigned by resemblance would
  change the number silently — a type is what decides whether something competes
  and what ceiling it meets. Untyped bonuses are simply added.

  ⚠ **The type is unknown; the answer is not** (task 3.90, 25.08.2026). Here
  stood «`{:assumed, :ac_bonus_types_unstated}` says that this is an
  assumption», and it stood for as long as the CONSEQUENCES of the missing word
  were open. Those consequences are four collisions, all four are answered now —
  the two monk bonuses add up (measured: armour takes away twelve points, a
  shared type would have cost six), `Bone skin` adds to natural armour, and
  `Tumble` neither meets the dodge ceiling nor competes with the monk. The
  caveat is a hole in our **answer**, so on a record whose answer is confirmed
  it is not printed.

  ⚠ Confirmation lives **on the record** (`stacking_confirmed`, with its own
  source), never on this function: a new untyped bonus off the wiki carries no
  mark and brings the caveat straight back. And it never names the type — the
  data still says `type: nil`, and `untyped/2` still asks the same question it
  always did.

  ## Что здесь своё, а что общее

  Чтение файла, «держит ли персонаж эту запись» и сбор гэпов из отвергнутых —
  общие для пяти статов и живут в `BuildCalculator.Rules.Bonuses` (задача
  3.21). Здесь остаётся специфика AC, и её больше, чем у любого соседа:
  **типы** прибавок и правило столкновения однотипных (`geared/3`), оговорка
  про условие (`scope`), отсутствующий тип (`untyped/1`), четыре формы прибавки
  и терм расового бонуса шарда, приходящий не из файла разметки вовсе. Плюс —
  единственный из пяти — считается **дважды**, против голых и одетых
  модификаторов.
  """

  alias BuildCalculator.Rules.{
    Bonuses,
    Build,
    Caps,
    Gear,
    GearWeapon,
    RacialBonus,
    WeaponTypeBonus,
    Worn
  }

  @markup :ac_bonuses

  # The build's own side of one AC type, empty. Two buckets rather than one
  # number since task 3.91: `stacking` adds to whatever the player typed under
  # the same type, `competing` meets it as a contest and the larger wins. Which
  # of the two a term lands in is the ruleset's answer — see `vs_typed/2`.
  @no_own %{stacking: 0, competing: 0}

  @typedoc """
  One source's contribution to armour class.

    * `id` — the feat, class, skill or racial trait, for the breakdown and the gaps
    * `source` — `{:feat, id}` / `{:class, id}` / `{:skill, id}` / `{:race_feat, id}`
      / `{:race, id}` / `{:weapon, id}`
    * `type` — the AC type the source names, or `nil` when it names none
    * `ac` — the contribution, already worked out for this build
    * `vs_typed` — how this term meets the number the player typed under its own
      type: `:sum` (it adds to it) or `:max` (the two compete and the larger
      wins). The ruleset's answer, never this module's — see `vs_typed/2`.
      Meaningless on an untyped term, which meets nothing, and carried there
      anyway so that every term has the same shape
  """
  @type term_entry :: %{
          id: atom(),
          source: {atom(), atom()},
          type: atom() | nil,
          ac: integer(),
          vs_typed: :sum | :max
        }

  @doc """
  Every armour class term this build earns by itself, in the data's own order.

  `modifiers` is the ability modifier map the terms are computed against — pass
  the naked ones for «AC голым» and the geared ones for «AC в шмоте», because
  `Monk AC bonus` is worth whatever wisdom is worth at the time.

  A source that works out to zero — a Monk 4, whose class table starts at 5 — is
  left out rather than listed as `+0`: a term with no value in it is not a term,
  and the breakdown is read as a list of what the character *has*.

  A source whose condition the worn gear breaks — a Monk in armour — is left out
  the same way, which is why the naked and the geared list can differ by more
  than one number. See `in_scope?/2` and the module doc.
  """
  @spec terms(Build.t(), map(), %{atom() => integer()}) :: [term_entry()]
  def terms(%Build{} = build, ruleset, modifiers) do
    level = Build.character_level(build)

    # ⚠ A record of the markup file names no shard bonus shape, so it takes the
    # ruleset's default — and since 25.08.2026 that default is «складывается»
    # (task 3.91). A feat's armour class adds to what the player typed under the
    # same type: «АЦ с фитов всегда стакаются все» (Dan). Should a record ever
    # need the other answer, it will be a field on the record beside its quote,
    # never a rule about feats as a kind.
    from_data =
      for record <- Bonuses.held(build, ruleset, @markup, level),
          in_scope?(record, build, ruleset),
          ac = amount(record, build, modifiers),
          ac != 0 do
        %{
          id: record.id,
          source: record.source,
          type: record.type,
          ac: ac,
          vs_typed: vs_typed(ruleset, nil)
        }
      end

    from_data ++ racial_terms(build, ruleset) ++ weapon_type_terms(build, ruleset)
  end

  # Whether the record's own condition holds for what this build **wears**.
  #
  # ⚠ **The item picked, and only the item.** Not the summed total for the type —
  # the shard's racial bonus is armour class typed `shield` for one race and a
  # blade in hand carries the same type, so off the total a Gnome monk would lose
  # his monk bonuses for being a Gnome. And not the number typed under the type
  # either: «Получаются бонусы монаха опираются **исключительно** на надетый щит
  # и доспех, числа в "AC по типам" не влияют» (Dan, 19.08.2026).
  #
  # 🔴 The typed number **was** read here until 19.08.2026, and it cost Dan's own
  # build twelve points of armour class: a Monk 33 in a robe — `armor: :none`,
  # base 0, exactly what a monk is supposed to be standing in — typed the robe's
  # own +6 under «Броня» and lost both monk bonuses to his own robe.
  #
  # ⚠ It was not a mistake when it was written. Until task 3.41 there were no
  # worn items at all, and the typed number was the **only** thing in the model
  # that could say «I am wearing armour» — so reading it was the whole of the
  # 09.08.2026 rule. Once the player names the item, the number stopped being
  # that statement and became the other one: a bonus on top of the thing worn.
  #
  # ⚠ This **narrows** the 09.08.2026 measurement rather than undoing it. Dan's
  # robe gives 6 AC in the game too, so «даёт AC» was the closest a model without
  # items could get to «база не ноль»; the module doc has all three readings in
  # the order they arrived.
  #
  # ⚠ `> 0` on the base, which is the half 09.08.2026 got right and this does not
  # touch: the clothing row of the source's table is `base_ac: 0`, and every
  # other row of both categories is 1 or more. So «любой щит» and «доспех — не
  # роба» are now stated exactly rather than approximated — see `_scope_decision`.
  #
  # ⚠ `Worn.base_ac/2` считает только ЛЕГАЛЬНОЕ надетое (задача 3.43), и это
  # ровно то, что здесь нужно: башенный щит, которого Карлику носить нельзя,
  # бонусы монаха не отключает — в игре его на персонаже нет вовсе.
  #
  # The last clause is the honest half: a condition the core cannot check leaves
  # the bonus in the number and reports itself in `gaps/4`.
  @spec in_scope?(map(), Build.t(), map()) :: boolean()
  defp in_scope?(%{scope: nil}, _build, _ruleset), do: true

  defp in_scope?(
         %{scope: %{kind: :no_ac_from_worn, ac_types: types}},
         %Build{} = build,
         ruleset
       ) do
    base = Worn.base_ac(build, ruleset)

    Enum.all?(types, &(Map.get(base, &1, 0) <= 0))
  end

  defp in_scope?(%{scope: _unmodelled}, _build, _ruleset), do: true

  # The shard's own racial bonus, for the one race whose bonus is armour class
  # (task 3.12). It belongs here rather than beside the equipment for the same
  # reason a Monk's wisdom does: a race is not a worn item, so "голым" has to
  # include it.
  #
  # ⚠ Typed `shield`, which is the whole reason it goes through this module and
  # not straight into the sum. «Этот класс брони не складывается с бонусом класса
  # брони щита, но складывается с базовым классом брони щита» — so a Gnome who
  # also typed a shield number under "Вещи" has a same-type collision, and
  # `collisions/2` already exists to say so. Which type it is comes from the
  # data; nothing here knows the word.
  defp racial_terms(build, ruleset) do
    case RacialBonus.armor_class(build, ruleset) do
      {kind, type, ac} ->
        [
          %{
            id: build.race,
            source: {:race, build.race},
            type: type,
            ac: ac,
            vs_typed: vs_typed(ruleset, kind)
          }
        ]

      nil ->
        []
    end
  end

  # And the same bonus from the other side (task 3.35): a blade in hand carries
  # shield armour class on Siala, and so — by an explicit line of the page — do a
  # halberd, a greataxe and a two-bladed sword, none of which is a blade.
  #
  # ⚠ Typed `shield`, the same type the racial term above carries, and that is
  # the point of routing it through this module too: a Gnome with a longsword has
  # **two** shield-typed sources plus whatever he typed under «Вещи», and
  # `collisions/2` is what says the game would not stack them.
  #
  # ⚠ Never in `ac_naked`, and not by a special case: a weapon is equipment, so
  # the naked pass (`Rules.compute/2` runs it over a build with `%Gear{}`) holds
  # nothing and this returns `[]`. Exactly what the racial bonus does since Dan's
  # measurement of 15.08.2026 — «голым» means naked down to the hands.
  defp weapon_type_terms(build, ruleset) do
    case WeaponTypeBonus.armor_class(build, ruleset) do
      [] ->
        []

      bonuses ->
        weapon = GearWeapon.held(build, ruleset)

        for {kind, type, ac} <- bonuses do
          %{
            id: weapon,
            source: {:weapon, weapon},
            type: type,
            ac: ac,
            vs_typed: vs_typed(ruleset, kind)
          }
        end
    end
  end

  # How a bonus of this shape meets the number the player typed under its type.
  #
  # 🔴 The default changed on 25.08.2026 (task 3.91) and the exception did not.
  # It used to be `:max` for everything the build earns, which came off one
  # sentence of the «Расы» page about **one** bonus — the Gnome's racial shield
  # armour class — spread over feats, class tables and skills alike. Dan's own
  # words narrowed it in both directions at once: «АЦ с фитов всегда стакаются
  # все» and «раса карлика работает немного по-другому и перекрывает бонус
  # щита». Up to 8 points of armour class were being dropped in silence on a Red
  # Dragon Disciple wearing an amulet of natural armour.
  #
  # ⚠ `kind` is the **shard bonus shape** (`nil` for a record of the markup
  # file, which names none), and the mapping shape → mode is the ruleset's. There
  # is no `shield_ac` in this module and there must never be one: keying the
  # exception by AC type would make a shield-typed feat compete too, and keying
  # it by kind of source would put two class abilities written as feats on one
  # side of a rule that treats them differently — the mistake CLAUDE.md §9
  # records about the save ceiling.
  @spec vs_typed(map(), atom() | nil) :: :sum | :max
  defp vs_typed(ruleset, kind) do
    rule = same_type_rule(ruleset)

    rule |> Map.get(:gear_by_kind, %{}) |> Map.get(kind, rule.gear)
  end

  @typedoc """
  What one AC type comes to once the build's own bonuses of that type have met
  the number the player typed under «Вещи».

    * `own` — what the build's own sources of this type add up to (they stack)
    * `own_competing` — how much of `own` was **at stake** against the typed
      number: the part whose shape the ruleset declares an exception (task 3.91).
      `0` on every type but the shard's `shield` today, and that is why the
      typed number now lands beside a feat's bonus instead of replacing it
    * `typed` — what the player typed for this type
    * `base` — the base armour class of the item worn in this type's category
      (task 3.41), `0` where nothing is worn and on every type nobody picks an
      item for. **Never competes**: it is added to whichever side won
    * `typed_alone` — the same after this type's own ceiling, ignoring the build
    * `counted` — what the type contributes to «AC в шмоте» in total
    * `gear` — how much of `counted` came from the **equipment** — the item's
      base plus whatever of the typed number landed. `0` on a type where the
      player typed nothing and wears nothing
    * `contested?` — `own_competing` and the typed number were both real bonuses
      and the larger won. This and not `superseded?` is what the caveat about the
      item's base hangs on: the base is lost whoever won
    * `own_lost?` — the item won, so the build's **competing** bonuses of this
      type are worth nothing while it is worn and are **not** in `terms`. Its
      stacking bonuses of the same type were never at stake and stay
    * `superseded?` — the mirror image: the typed number did not land at all, so
      the interface can say why a number the player entered shows as nothing
    * `capped?` — the type's own ceiling clipped it
    * `clip` — how much the ceiling took off the **build's own** side, `0` or
      negative, and `0` on every ruleset that ships today. Carried rather than
      folded into `own` for the reason `attack_cap_clipped` is carried next
      door: a breakdown printing raw terms needs somewhere to show the loss
  """
  @type type_entry :: %{
          type: atom(),
          own: integer(),
          own_competing: integer(),
          typed: integer(),
          base: integer(),
          typed_alone: integer(),
          counted: integer(),
          gear: integer(),
          contested?: boolean(),
          own_lost?: boolean(),
          superseded?: boolean(),
          capped?: boolean(),
          clip: integer()
        }

  @typedoc """
  The dexterity term of «AC в шмоте», after the ceiling the worn armour puts on
  it (task 3.41).

    * `modifier` — the geared dexterity modifier, whole. What the reflex save,
      the attack roll and every dexterity skill go on using
    * `counted` — what armour class actually gets
    * `cap` — the ceiling, `nil` when the armour states none or nothing is worn
    * `capped?` — the ceiling actually took something off
  """
  @type dexterity :: %{
          modifier: integer(),
          counted: integer(),
          cap: integer() | nil,
          capped?: boolean()
        }

  @typedoc """
  Armour class in the geared pass, assembled: the build's own terms **that
  count**, and what the typed numbers came to beside them.
  """
  @type geared :: %{
          terms: [term_entry()],
          types: [type_entry()],
          by_type: [{atom(), integer()}],
          typed_total: integer(),
          dexterity: dexterity(),
          capped: [atom()],
          superseded: [atom()],
          contested: [atom()],
          clip: integer()
        }

  @doc """
  «AC в шмоте», resolved: what the build earns by itself **and** what the player
  typed, after the rule about two bonuses of one type (task 3.39).

  What `Rules.compute/2` adds up is

      base_ac + dexterity.counted + Σ terms + Σ by_type + clip

  and every one of those four is in the returned map, so the panel's breakdown
  and the number cannot disagree. ⚠ `dexterity.counted` and not the modifier
  itself since task 3.41: armour caps the dexterity bonus **to armour class**,
  and to nothing else.

  ⚠ A term that lost to the typed number is **not in `terms`**. It is not a
  special case but the module's existing rule — a source worth nothing on this
  build is not a term (a Monk 4, a Monk in armour) — and a bonus the game
  overrides is worth nothing while that item is worn. The type is named in
  `superseded`, so the interface can say so rather than lose it silently.

  ⚠ Only a **competing** term can lose that way (task 3.91), and today only the
  shard's shield bonus is one. A feat's armour class adds to what the player
  typed and is in `terms` beside it.

  ⚠ `typed_total` is what the player **typed** (after each type's own ceiling)
  and deliberately not what landed: it answers «есть ли вообще AC с вещей», which
  is a question about the gear block. What landed is `by_type`, type by type.
  """
  @spec geared(Build.t(), map(), %{atom() => integer()}) :: geared()
  def geared(%Build{} = build, ruleset, modifiers) do
    own = terms(build, ruleset, modifiers)
    own_by_type = own_by_type(own)

    # Что даёт САМ ПРЕДМЕТ (задача 3.41) — база, которая складывается всегда и
    # ни с чем не конкурирует. Читается по типам, а не по категориям: полю ввода
    # и правилу столкновения известен тип, а не то, что его надело.
    base_by_type = Worn.base_ac(build, ruleset)

    # ⚠ The typed side is read through `Rules.Gear` rather than off the struct
    # here: which types the player may enter at all is that module's statement
    # (and the ruleset's), and reading the map directly would quietly count a
    # type no input box offers.
    types =
      for {type, typed} <- Gear.ac_typed(build.gear, ruleset) do
        resolve(
          type,
          Map.get(own_by_type, type, @no_own),
          typed,
          Map.get(base_by_type, type, 0),
          ruleset
        )
      end

    # ⚠ Two different losses, and they are not each other's mirror image in the
    # code even though they are in the rule: `own_lost?` is what removes terms
    # from the list, `superseded?` is what the interface says about a typed
    # number that came to nothing. Reading one off the other is the bug this
    # pair was born with — it dropped the build's own bonuses on the very builds
    # where they had won.
    #
    # 🔴 And what is removed is the **competing** terms of a lost type, not every
    # term of it (task 3.91). Since the two kinds live side by side in one type —
    # a Gnome's racial shield bonus competes, a hypothetical shield-typed feat
    # would add — dropping the whole type would take away a bonus that never
    # entered the contest.
    own_lost = for entry <- types, entry.own_lost?, do: entry.type

    %{
      terms: for(term <- own, not lost_to_typed?(term, own_lost), do: term),
      types: types,
      by_type: for(entry <- types, do: {entry.type, entry.gear}),
      typed_total: Enum.reduce(types, 0, &(&2 + &1.typed_alone)),
      dexterity: dexterity(build, ruleset, modifiers),
      capped: for(entry <- types, entry.capped?, do: entry.type),
      superseded: for(entry <- types, entry.superseded?, do: entry.type),
      contested: for(entry <- types, entry.contested?, do: entry.type),
      clip: Enum.reduce(types, 0, &(&2 + &1.clip))
    }
  end

  # Ловкость под потолком надетого доспеха (задача 3.41).
  #
  # 🔴 Режется ТОЛЬКО этот терм. Дословно со страницы источника: «This cap
  # applies only to AC; it does not affect the attack bonus for ranged weapons,
  # the attack bonus from weapon finesse, reflex saves, nor dexterity-based
  # skills». Поэтому здесь возвращается отдельное число, а не правленый
  # модификатор: срезать сам модификатор было бы на строку короче и неверно
  # сразу в трёх местах.
  #
  # ⚠ Потолок односторонний, как и все остальные в проекте: он про БОНУС
  # («a cap on the **bonus** to armor class»), поэтому сравнение, а не `min/2`, —
  # отрицательный модификатор ловкости проезжает целиком, пола не называет
  # ни один источник.
  #
  # ⚠ `:dex` здесь — та же характеристика, которую `Rules.compute/2` кладёт в оба
  # числа AC соседней строкой (`naked_modifiers.dex`), а не второе независимое
  # утверждение: это ОДИН терм, и здесь считается его потолок. Разойдись они —
  # потолок применялся бы не к тому слагаемому, поэтому обе строки читаются
  # рядом и правятся вместе.
  @spec dexterity(Build.t(), map(), %{atom() => integer()}) :: dexterity()
  defp dexterity(%Build{} = build, ruleset, modifiers) do
    modifier = Map.get(modifiers, :dex, 0)
    cap = Worn.dexterity_cap(build, ruleset)
    counted = if is_nil(cap) or modifier <= cap, do: modifier, else: cap

    %{modifier: modifier, counted: counted, cap: cap, capped?: counted != modifier}
  end

  # One type, both sides, one answer. Every rule read here comes out of the
  # ruleset — which shapes of bonus compete instead of adding up, which types add
  # up regardless, and which ceiling belongs to which type — because a type's
  # name is a game word and there is not one in this module.
  #
  # `own` arrives split in two (task 3.91): `stacking`, which simply adds to the
  # typed number, and `competing`, which meets it as a contest. Before that day
  # the whole of the build's own side competed, and a feat's +2 of natural armour
  # was thrown away by an amulet worth +5.
  defp resolve(type, own, typed, base, ruleset) do
    contested? = contested?(ruleset, type, own.competing, typed)
    own_lost? = contested? and typed > own.competing

    # The winner takes the **competing** part when the two competed; the stacking
    # part is never at stake and neither is the typed number's own presence when
    # nothing competes with it.
    {own_share, typed_share} =
      cond do
        not contested? -> {own.stacking + own.competing, typed}
        own_lost? -> {own.stacking, typed}
        true -> {own.stacking + own.competing, 0}
      end

    # 🔴 База предмета в состязании не участвует и не проигрывает его: она
    # прибавляется к победителю, кем бы он ни был («не складывается с бонусом
    # класса брони щита, но складывается с базовым классом брони щита»).
    gear_share = typed_share + base
    raw = own_share + gear_share
    {counted, capped?} = clamp_type(ruleset, type, raw)

    # ⚠ The ceiling is applied to the **whole** of the type and then charged to
    # the item's share first — «своё есть своё, потолок съедает надетое». Only
    # when the build's own side alone is over the ceiling does anything come off
    # it, and that residual is `clip` rather than a quietly smaller term: a
    # breakdown printing terms as earned needs a row for the loss.
    {own_counted, from_gear} =
      if counted == raw,
        do: {own_share, gear_share},
        else: {min(own_share, counted), counted - min(own_share, counted)}

    %{
      type: type,
      own: own.stacking + own.competing,
      # How much of `own` was at stake — what `contested?` is actually about.
      # `0` on every type whose bonuses all stack, which is every type but the
      # shard's `shield` today.
      own_competing: own.competing,
      typed: typed,
      base: base,
      # What the typed number is worth on its own, after this type's own
      # ceiling — the pre-3.39 meaning of `ac_gear_bonus`, kept unchanged
      # because the interface asks it «ввёл ли игрок хоть что-то».
      typed_alone: type |> clamp_type_value(ruleset, typed),
      counted: counted,
      gear: from_gear,
      contested?: contested?,
      own_lost?: own_lost?,
      # ⚠ Считается по ДОЛЕ ВПИСАННОГО, а не по `from_gear`: с задачи 3.41 в
      # `from_gear` едет ещё и база предмета, и билд с малым щитом без усиления
      # перестал бы говорить игроку, что его число не доехало, — просто потому
      # что рядом лежит единица базы.
      superseded?: contested? and typed_share == 0,
      capped?: capped?,
      # ⚠ Only the **ceiling's** doing, never the maximum's: a side that lost
      # the maximum lost it to a rule, and charging that here would print a −18
      # «срез» on a build nothing was clipped on. It comes out at zero for that
      # case by construction — a losing side's share is zero to begin with.
      clip: own_counted - own_share
    }
  end

  # Whether anything is actually at stake on this type. Three readings are
  # decided here and none of them is a game number:
  #
  #   * a type nobody declared cumulative still adds up while one of the sides is
  #     empty — there is nothing to compete with;
  #   * a **penalty** never competes: every source states the rule about bonuses
  #     and none states a floor, so a maximum must not be allowed to swallow a
  #     number the player typed below zero;
  #   * a type declared cumulative adds up whatever the shapes in it say, which
  #     is what «dodge АЦ еще стакается до капа в 20» means — the exception is
  #     the type's, and it is stronger than the shape's.
  defp contested?(ruleset, type, competing, typed) do
    competing > 0 and typed > 0 and type not in same_type_rule(ruleset).cumulative
  end

  @default_same_type %{own: :sum, gear: :sum, gear_by_kind: %{}, cumulative: []}

  defp same_type_rule(ruleset), do: Map.get(ruleset.gear, :ac_same_type, @default_same_type)

  # A term that lost the contest on its type — and only a term that was **in**
  # the contest. A stacking term of the same type brought its own number and
  # keeps it.
  defp lost_to_typed?(%{type: type, vs_typed: :max}, lost_types), do: type in lost_types
  defp lost_to_typed?(_term, _lost_types), do: false

  # The build's own sources per type, split by how each of them meets the number
  # the player typed. The **sum within each side** is the `own_vs_own` half of
  # the rule, and the one half that has not changed since 16.08.2026: two bonuses
  # of the build's own add up whichever side they are on. ⚠ Summed here rather
  # than read off `ac_same_type.own`, and the loader is what keeps that honest:
  # it refuses a ruleset declaring any other mode there, so the declaration
  # cannot come to mean nothing.
  #
  # ⚠ Untyped terms are not in here at all: they meet nothing and are simply
  # added.
  defp own_by_type(terms) do
    for %{type: type, ac: ac, vs_typed: vs_typed} <- terms, not is_nil(type), reduce: %{} do
      acc -> Map.update(acc, type, add_side(@no_own, vs_typed, ac), &add_side(&1, vs_typed, ac))
    end
  end

  defp add_side(sides, :sum, ac), do: %{sides | stacking: sides.stacking + ac}
  defp add_side(sides, :max, ac), do: %{sides | competing: sides.competing + ac}

  # A type's own ceiling, applied to the **whole** of that type. Which type has
  # one, and which `stat_caps` key holds it, is declared beside the types
  # themselves (`gear.ac_types.ceilings`); nothing here knows the word.
  defp clamp_type(ruleset, type, value) do
    case ruleset.gear |> Map.get(:ac_type_ceilings, %{}) |> Map.get(type) do
      nil -> {value, false}
      stat -> Caps.clamp(ruleset, stat, value)
    end
  end

  defp clamp_type_value(type, ruleset, value) do
    {clamped, _capped?} = clamp_type(ruleset, type, value)
    clamped
  end

  @doc """
  Gaps this build's armour class carries — everything the number does not say
  for itself.

  Four kinds, and they answer four different questions:

    * `{:not_modelled, {:ac_bonus, id}}` — the character has an ability that
      raises armour class and the model refuses to put it in a permanent
      number: a combat mode, an ability used so many times a day, a bonus
      against one kind of enemy. Not silence — the ability is named.
    * `{:not_modelled, {:ac_bonus_scope, id}}` — a bonus that **is** counted and
      that the game takes away under a condition the core cannot check. The
      Spellcraft precedent: show the number, say the caveat. ⚠ **No record
      produces this today.** The Monk's condition used to and is now applied
      instead (09.08.2026), so a caveat about it would be a lie in the other
      direction — printing "not checked" about something checked is exactly what
      CLAUDE.md §6 forbids. The branch stays so that the next condition nobody
      can formalise arrives as a printed caveat rather than as silence.
    * `{:assumed, :ac_bonus_types_unstated}` — at least one counted bonus has
      no type in its source, so it is added to everything and clipped by
      nothing, **and nobody has confirmed that this is what the game does**.
      ⚠ The second half is the live one (task 3.90): all four untyped records
      carry `stacking_confirmed` today, so no build prints this. The form stays
      because the next untyped bonus off the wiki arrives without a mark — see
      `untyped/2`.
    * `{:not_modelled, {:ac_gear_base, type}}` — on this type a bonus of the
      build's met a number the player typed, the larger of the two won (the rule
      is applied, task 3.39), and the **base** armour class of the item — which
      always stacks — cannot be told apart from the bonus inside one typed
      number. So the number here may be low by that base. Emitted per type and
      only where the collision actually happened.

      ⚠ **And only on a type the player picks no item for** (task 3.41). Armour
      and shields are items with a size now, so their base is known and this
      caveat would be a lie in the other direction there — «не можем посчитать»
      about something counted (CLAUDE.md §6). What is left is deflection and
      natural armour: one typed number apiece and no item behind it.

      ⚠ Here stood `{:not_modelled, :ac_same_type_stacking}` — «мы складываем
      однотипное, а игра не складывает». Both halves are gone: own against own
      **does** add up (measured, `GAME_CHECKS.md` E5) and own against typed is a
      rule now. What is left unmodelled is a different, smaller thing, and it
      says so in its own words rather than inheriting the old sentence.
  """
  @spec gaps(Build.t(), map(), %{atom() => integer()}, geared() | nil) :: [tuple()]
  def gaps(%Build{} = build, ruleset, modifiers, geared \\ nil) do
    level = Build.character_level(build)
    geared = geared || geared(build, ruleset, modifiers)
    counted = geared.terms

    # ⚠ `uniq?: false` — сохранённая асимметрия, а не улучшение: у трёх
    # остальных статов свёртка повторов по id стояла с самого начала, у AC
    # никогда. Сегодня повторяющихся id в файле нет, поэтому оба чтения
    # выдают одно и то же; выравнивать наугад в рефакторинге нечего.
    unmodelled =
      Bonuses.gaps(build, ruleset, @markup, level, &{:not_modelled, {:ac_bonus, &1}},
        uniq?: false
      )

    # Only a condition the core cannot check. One that it can is applied in
    # `terms/3` instead, and a caveat beside an applied rule would say "not
    # checked" about something checked.
    scoped =
      for record <- Bonuses.applied(ruleset, @markup),
          unchecked_scope?(record),
          Enum.any?(counted, &(&1.id == record.id)),
          do: {:not_modelled, {:ac_bonus_scope, record.id}}

    unmodelled ++ scoped ++ untyped(counted, ruleset) ++ gear_base(geared, ruleset)
  end

  # A record carries a condition, and it is not one of the shapes `in_scope?/2`
  # decides. Written as "everything but the known shapes" rather than as a list of
  # unknown ones, so a new shape has to be taught to `in_scope?/2` before it stops
  # being a caveat — never the other way round.
  defp unchecked_scope?(%{scope: nil}), do: false
  defp unchecked_scope?(%{scope: %{kind: :no_ac_from_worn}}), do: false
  defp unchecked_scope?(%{scope: _other}), do: true
  defp unchecked_scope?(_record), do: false

  # A counted bonus whose source names no type, and whose behaviour beside its
  # neighbours nobody has confirmed either.
  #
  # 🔴 The second half arrived with task 3.90 and is the whole of it. A type
  # decides exactly two things — whether the bonus collides with another and
  # whether it meets a ceiling — so what the caveat is really about is the
  # ANSWER, not the word. Every collision the four untyped records have is
  # answered now, each on its own record and each with its own provenance
  # (`ac_bonuses.json` → `_stacking_confirmed_decision`), and a gap is a hole in
  # our answer rather than in our knowledge (CLAUDE.md §9).
  #
  # ⚠ The type is still unknown, and this does not claim otherwise: the records
  # keep `type: nil` and the file keeps the rule that a type is written only when
  # a source says the word.
  #
  # ⚠ Asked of the RECORD and never of the mechanism. A new armour class bonus
  # arriving off the wiki with no type carries no mark, and the caveat comes
  # back by itself — «мы это выяснили» must not become «мы это знаем».
  #
  # ⚠ Matched on `source` rather than on `id`: `{:feat, :monk_ac_bonus}` and
  # `{:class, :monk}` are two independent records about one class, and the four
  # source kinds are exactly what keeps them apart everywhere else in this file.
  defp untyped(terms, ruleset) do
    confirmed =
      for record <- Bonuses.applied(ruleset, @markup),
          is_map(record.stacking_confirmed),
          into: MapSet.new(),
          do: record.source

    unconfirmed? =
      Enum.any?(terms, &(is_nil(&1.type) and not MapSet.member?(confirmed, &1.source)))

    if unconfirmed?, do: [{:assumed, :ac_bonus_types_unstated}], else: []
  end

  # Where the maximum actually resolved a collision, and only there. ⚠ It hangs
  # on `contested?` and not on who won: the item's base is lost either way, and a
  # caveat that only appeared when the player's number lost would go quiet on
  # exactly the builds where the understatement is largest.
  #
  # ⚠ И только там, где базу по-прежнему взять неоткуда (задача 3.41): у типа,
  # под который игрок выбирает ПРЕДМЕТ, база известна и прибавлена, а печатать
  # «посчитать не можем» про посчитанное запрещено ровно так же прямо, как
  # обратное (CLAUDE.md §6). Вопрос задаётся справочнику
  # (`Worn.item_type?/2`), а не списку имён здесь.
  defp gear_base(%{contested: types}, ruleset),
    do:
      for(
        type <- types,
        not Worn.item_type?(ruleset, type),
        do: {:not_modelled, {:ac_gear_base, type}}
      )

  # ⚠ Four clauses of `amount/3` and no catch-all, deliberately. Which kinds may
  # reach an applied record is enforced where the data is read (`Loader`'s
  # `@applied_ac_bonus_kinds`, which raises at **compile** time on anything
  # else), so an unmatched shape here is a broken build and not a live request.
  # A fallback returning zero would turn that into the one failure this module
  # exists to prevent: a bonus that quietly counts for nothing.
  defp amount(%{amount: %{kind: :flat, ac: ac}}, _build, _modifiers), do: ac

  defp amount(%{amount: %{kind: :ability_modifier, ability: ability}}, _build, modifiers),
    do: Map.get(modifiers, ability, 0)

  # The table states TOTALS — `Bonuses.total_at_step/2` is where that reading
  # lives, and its doc is where the ⚠ about the opposite reading next door
  # (`Rules.AbilityBonuses` sums its steps) is stated once instead of three
  # times. Below the first step there is no bonus at all: a Monk 4 on Siala has
  # wisdom to armour class and not one point from this table, and that is the
  # whole reason the two are separate records.
  defp amount(%{amount: %{kind: :ac_at_class_level} = amount}, build, _modifiers) do
    Bonuses.total_at_step(amount.ac_at_class_level, Bonuses.class_level(build, amount.class))
  end

  # The skill is the record's `source` and is not restated in the amount: two
  # writings of one fact drift apart.
  defp amount(
         %{amount: %{kind: :per_skill_ranks} = amount, source: {:skill, skill}},
         build,
         _mods
       ) do
    ranks = Build.skill_ranks(build, skill, Build.character_level(build))
    div(ranks, amount.per_ranks) * amount.ac
  end
end
