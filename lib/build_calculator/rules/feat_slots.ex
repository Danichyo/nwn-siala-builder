defmodule BuildCalculator.Rules.FeatSlots do
  @moduledoc """
  Feat slots per level — and what each one will accept.

  **Slots are not interchangeable** (CLAUDE.md §6). A level does not grant "two
  feats"; it grants, say, one general slot and one Fighter bonus slot, and the
  Fighter bonus only takes a feat that lists Fighter in its `bonus_for`. Counting
  them as one number is the classic calculator bug that produces illegal builds,
  so a slot is a value with a kind:

    * `:general` — the every-third-level slot, general feats only
    * `:epic_general` — the same slot once the character is epic; also takes epic feats
    * `:racial` — the human bonus feat at level 1
    * `:class_bonus` — a class's own bonus slot, restricted to that class's list

  Slot ids are stable, so `build.feats[level][slot_id]` addresses one exact slot.
  Which levels grant which slots comes from the ruleset: general and epic-general
  levels from `epic.general_feat_levels`, class bonus levels from the class's
  `bonus_feat_levels` / `epic_bonus_feat_levels` (which are **class** levels, not
  character levels), the racial slot from the race's `extra_feats`.

  ⚠ `epic_bonus_feat_levels` says **when** a class grants a bonus slot, never
  what that slot will take: a class has one bonus list and the epic entries on it
  are gated by the *character* being epic, nothing else (`fandom:Bonus feat`).
  Reading the two as the same thing is what made a Fighter level taken at
  character level 22 refuse the epic feats its own page offers.

  ⚠ …and it does not say **how many**, because it is a set. A class level may
  grant two bonus slots — ranger 35 does, on three independent readings of the
  wiki — and until 14.08.2026 the second one had nowhere to go: the player lost a
  whole feat and nothing anywhere said so. The count comes from
  `bonus_feat_counts` (`%{class_level => n}`, filled only where n > 1), and the
  two slots get **different ids**, because `build.feats[level]` is a map keyed by
  slot id and one id would mean the second pick overwrote the first. See
  `bonus_slot_id/2` for why only the second one is indexed.

  ## The class of the level narrows the general pool

  A general slot does not accept every general feat — it accepts the ones on the
  **general feat list of the class whose level is being taken**. Each class page
  names what it takes off that list: «These general feats cannot be selected when
  taking a level of bard». So `Quicken spell` is a legal pick on a Wizard level
  and not on a Fighter level, and the deciding fact is the class sitting on
  *this* character level — which is why every slot carries `taken_with`.

  Three things this rule is **not**, and each of them would be a lie in the other
  direction (HANDOFF, «контракт из двух половин»):

    * it is not a prerequisite. Nothing the character does at this level satisfies
      it; the same feat is available at the next level if that level belongs to
      another class.
    * it does not **take away** a feat already owned. A feat picked on a Wizard
      level stays picked when a Fighter level is added later; only a level whose
      own class forbids the feat refuses it (`Rules.illegal_feats/2` re-asks
      exactly that question, per level, after an edit).
    * it does not touch the class bonus slot. The ban is stated about general
      feats, and a bonus slot draws on a different list — one «set forth in each
      class' description» and read here out of `bonus_for` (`fandom:Bonus feat`).
      The one page that compares the two says bonus availability *matches*
      general availability **except** where it is narrower (`Epic skill focus` in
      `use magic device` is off the rogue bonus list only — see
      `choice_refusals/4`), so a class's ban list and its own bonus list are
      independent statements. In today's data they never overlap — no class
      forbids a feat its own bonus pool would take — so nothing observable turns
      on this; `feat_slots_test.exs` fails if that ever stops being true, and then
      a human decides rather than a default.

  ## One refusal belongs to the slot **and** to the value it is taken with

  > «*Epic skill focus* in *use magic device* cannot be selected as a rogue
  > [[bonus feat]], but otherwise bonus feat availability matches [[general
  > feat]] availability» — `fandom:Epic skill focus`, Notes.

  That is narrow along two axes at once, and every wider reading of it is wrong
  in a way a player would notice:

    * **by slot** — the *general* slot on a rogue level takes the very same pair
      («otherwise … matches general feat availability»), so this may not go into
      `unavailable_feats`, which is about the general pool;
    * **by value** — `Epic skill focus (discipline)` goes into the rogue bonus
      slot legally, so it may not come off `bonus_for` either. The feat *is* on
      the rogue bonus list (`bonus4=rogue` on that page); one pair is not.

  So the answer needs the slot and the choice in the same hand, which is exactly
  what neither existing reader has: `accepts?/3` knows the slot and takes no
  choice, `Rules.Prereqs` knows the choice and never sees a slot. Hence
  `choice_refusals/4` here rather than a fourth argument on either — and hence
  its own reason, `{:not_in_class_bonus_slot, class}`, because
  `{:forbidden_by_class, :rogue}` would state two falsehoods at once (the class
  does not refuse the feat, and a rogue level is where the pair is meant to be
  taken).

  ## Two things no slot ever takes, for reasons that have nothing to do with slots

  A feat the shard **switched off** (`disabled?`, `Devastating critical`) and a
  feat the shard says **cannot be chosen at level-up at all**
  (`level_up_selectable?`, `Riding Sprint` and `Smile of Death`: «Умение нельзя
  выбрать при росте персонажа» — they come on an item). Both are refused before
  any question about the slot is asked, because no class, level or freed slot
  changes the answer.

  The two are separate facts and must stay separate: a switched-off feat cannot
  be had at all, while these two work — a declaration under «Вещи»
  (`Rules.GearFeats`) is legal for them and is the only way they reach a build.

  ⚠ The second one used to be true **by accident**: a shard-only feat's slot
  answer is read off its own «Возможность взятия фита» block (see `general?/1`
  below), these two pages carry none, and "the page did not say" happened to
  coincide with "may not be chosen". The coincidence rested on the shard never
  editing their `Тип навыка`, and the refusal the player was shown said
  "выдаётся классом или расой", which is not what the page says at all.

  ⚠ The **racial** slot is treated as a general one here, and that is a
  deduction, not a quoted sentence: the human bonus feat's pool is «exactly all
  general feats» (`fandom:General feat`), and the general pool at a level of class
  X is X's list. Both halves are sourced, their conjunction is not, and it is
  cheap to measure in game (a human Fighter 1 either sees `Spell focus` in the
  list or does not) — see `GAME_CHECKS.md`. Leaving the racial slot out would let
  a human Wizard 1 pick `Weapon specialization` in one of two slots that draw on
  the same pool, which is the plainly worse of the two guesses.
  """

  alias BuildCalculator.Rules.{Build, Epic, FeatChoices}

  @typedoc """
  One slot at one character level.

  `class` is what the slot *belongs* to (the class whose bonus it is, the race
  whose bonus it is); `taken_with` is the class whose level the slot arrived on,
  and it is what narrows the general pool. The two are **not** the same field: a
  general slot has no `class` at all, and a class bonus slot has both, equal by
  construction.

  `taken_with` is `nil` in exactly one case — the build has no level there, i.e.
  a hypothetical slot asked about past the end of the ladder — and then no class
  narrows anything.
  """
  @type slot :: %{
          id: Build.slot_id(),
          kind: :general | :epic_general | :racial | :class_bonus,
          class: atom() | nil,
          taken_with: atom() | nil,
          epic?: boolean()
        }

  @typedoc "Why the class whose level is being taken refuses a feat outright."
  @type class_reason :: {:forbidden_by_class, atom()}

  @typedoc """
  Why **this slot** refuses the feat **with this value**, though it takes both apart.

  Names the class whose bonus slot refuses the pair, because that is the part the
  player can act on: the same pair goes into the general slot of the same level.
  """
  @type choice_reason :: {:not_in_class_bonus_slot, atom()}

  @typedoc """
  Why **no** level-up may pick this feat, whatever the class and whatever the slot.

  The third refusal of its family, and each of the three is a different sentence:
  `{:feat_disabled, id}` is "the shard removed it", `{:forbidden_by_class, class}`
  is "not on a level of *this* class", and this one is "not on anybody's level —
  it comes from an item".
  """
  @type level_up_reason :: {:not_selectable_at_level_up, atom()}

  @doc "Slots granted at character `level` for this build, in a stable order."
  @spec at(Build.t(), map(), pos_integer()) :: [slot()]
  def at(%Build{} = build, ruleset, level) when level >= 1 do
    epic? = Epic.epic_level?(ruleset, level)
    taken_with = Build.class_at(build, level)

    general_slot(ruleset, level, epic?, taken_with) ++
      racial_slot(build, ruleset, level, epic?, taken_with) ++
      class_bonus_slot(build, ruleset, level, epic?)
  end

  @doc """
  Every slot in the build, as `%{character_level => [slot]}`.

  Levels that grant no slot are absent rather than mapped to `[]`.
  """
  @spec all(Build.t(), map()) :: %{pos_integer() => [slot()]}
  def all(%Build{} = build, ruleset) do
    for level <- 1..max(Build.character_level(build), 0)//1,
        slots = at(build, ruleset, level),
        slots != [],
        into: %{},
        do: {level, slots}
  end

  @doc """
  Whether `slot` will take `feat_id`.

  General slots take general feats; epic-general slots additionally take epic
  ones; a class bonus slot takes whatever lists its class in `bonus_for`, and a
  pre-epic one refuses epic feats. On top of that, a slot drawing on the general
  pool refuses what the class of this level takes off it (see the module doc).
  """
  @spec accepts?(map(), slot(), atom()) :: boolean()
  def accepts?(ruleset, slot, feat_id) do
    case Map.fetch(ruleset.feats, feat_id) do
      {:ok, feat} -> accepts_feat?(slot, feat, unavailable(ruleset, slot))
      :error -> false
    end
  end

  @doc "Feat ids `slot` will take, sorted."
  @spec candidates(map(), slot()) :: [atom()]
  def candidates(ruleset, slot) do
    unavailable = unavailable(ruleset, slot)

    for {id, feat} <- ruleset.feats, accepts_feat?(slot, feat, unavailable), do: id
  end

  @doc """
  Why a level of `class` refuses `feat_id` outright — `[]` when it does not.

  The same reading `accepts?/3` applies to a general slot, exposed so the one
  caller that has no slot in hand can ask it too: `Rules.validate_feat/3` answers
  about a feat and a level, and the level's class is the whole of this rule. Two
  implementations of it would eventually disagree, and the player would be offered
  a feat the build then refuses to hold.

  `nil` for the class is not an error: a build asked about past the end of its own
  ladder has no class on that level, and no class means nothing is forbidden.
  """
  @spec class_refusals(map(), atom() | nil, atom()) :: [class_reason()]
  def class_refusals(_ruleset, nil, _feat_id), do: []

  def class_refusals(ruleset, class, feat_id) do
    if MapSet.member?(unavailable_feats(ruleset, class), feat_id),
      do: [{:forbidden_by_class, class}],
      else: []
  end

  @doc """
  Why `slot` refuses `feat_id` **taken with `choice`** — `[]` when it does not.

  The one question about a slot that cannot be asked without the value; see the
  module doc for the sentence it stands for and for why both halves of that
  sentence keep it out of `unavailable_feats` *and* out of `bonus_for`.

  `slot` is a slot or its id, so the caller that has a pick
  (`Rules.validate_feat_pick/3`, `Rules.illegal_feats/2`) and the caller that has
  a slot list (the picker) can both ask without reshaping anything. Neither the
  build nor the level is needed: a bonus slot's id names its class, and the pair
  is refused wherever that slot occurs.

  `nil` for the choice — every caller that deals in no values — is `[]`, and so is
  every general and racial slot: the restriction is stated about a bonus slot, and
  stretching it to the general one would contradict the same sentence.

  ⚠ Which pairs are refused is **data** (`bonus_for_except` on the feat, filled
  from `vanilla/feat_requirements.json`). No feat, class or skill is named here,
  so the day the shard states another one it takes a record and no code
  (CLAUDE.md §3).

  ⚠ Silent on a ruleset where the feat takes no value at all, and that is the
  same silence its sibling `only_on_class_levels_for_skill` keeps for the same
  reason: `vanilla` never declared `Epic skill focus` repeatable (that is the
  shard's record — `siala_41/feats.json`, `source.kind: user`), so a pick there
  carries no skill and the pair does not exist to be refused. Answering anyway
  would print a refusal about a value the ruleset says cannot be recorded, beside
  the `{:invalid_choice, …}` that says exactly that.
  """
  @spec choice_refusals(map(), slot() | Build.slot_id() | nil, atom(), term()) ::
          [choice_reason()]
  def choice_refusals(_ruleset, _slot, _feat_id, nil), do: []

  def choice_refusals(ruleset, slot, feat_id, choice) do
    with class when not is_nil(class) <- bonus_slot_class(slot),
         # Asked of `FeatChoices`, not of the record: "does this feat take a
         # value" already has one reader, and a second would be free to drift.
         true <- FeatChoices.domain(feat_id, ruleset) != nil,
         {:ok, feat} <- Map.fetch(ruleset.feats, feat_id),
         true <- MapSet.member?(bonus_for_except(feat), {class, choice}) do
      [{:not_in_class_bonus_slot, class}]
    else
      _no_refusal -> []
    end
  end

  # A class bonus slot names its class in its own id, which is why this answers
  # off either shape. Anything else — the general slot, the racial one, a slot id
  # from an older link — is not what the restriction talks about.
  #
  # ⚠ Both id shapes, because a level may grant two slots of the same class and
  # the restriction is about the *pool*, which the two share: forgetting the
  # indexed one would let `Epic skill focus (use magic device)` into the second
  # rogue bonus slot and refuse it in the first.
  defp bonus_slot_class(%{kind: :class_bonus, class: class}), do: class
  defp bonus_slot_class({:class_bonus, class}), do: class
  defp bonus_slot_class({:class_bonus, class, _index}), do: class
  defp bonus_slot_class(_other), do: nil

  # Same defensive read as `disabled?`: a record assembled by hand in a test
  # predates the key, and absent is "no exception", which is the rule as it stood.
  defp bonus_for_except(feat), do: Map.get(feat, :bonus_for_except) || MapSet.new()

  @doc """
  Why no level-up may pick `feat_id` at all — `[]` when one may.

  «Умение нельзя выбрать при росте персонажа» (`siala:Riding Sprint`,
  `siala:Smile of Death`): the feat exists, works, and arrives on an item, so no
  slot of any class ever offers it. Exposed for the same reason
  `class_refusals/3` is — one reading of the rule, shared by `accepts?/3`, by
  `Rules.validate_feat/3` and by the picker, instead of three that can drift.

  ⚠ It says nothing about a **declaration** under «Вещи»
  (`Rules.GearFeats.validate/2`), which stays legal: that is the only route such
  a feat has into a build at all.
  """
  @spec level_up_refusals(map(), atom()) :: [level_up_reason()]
  def level_up_refusals(ruleset, feat_id) do
    case Map.fetch(ruleset.feats, feat_id) do
      {:ok, feat} -> if selectable?(feat), do: [], else: [{:not_selectable_at_level_up, feat_id}]
      :error -> []
    end
  end

  # A feat the shard switched off is refused by every slot, whatever its type
  # and whoever lists it as a bonus. Siala's `Devastating critical` is on eight
  # classes' bonus lists in the vanilla data, so leaving the kind checks to do
  # the work would keep offering it (CLAUDE.md §3).
  #
  # ⚠ `selectable?` is the same shape and a different fact — see the module doc.
  # Both are read before anything about the slot, because neither has anything to
  # do with the slot: no class, level or freed slot changes the answer.
  defp accepts_feat?(slot, feat, unavailable) do
    not disabled?(feat) and selectable?(feat) and
      not off_the_class_list?(slot, feat, unavailable) and accepts_kind?(slot, feat)
  end

  defp disabled?(feat), do: Map.get(feat, :disabled?, false)

  # Same defensive read as `disabled?`: the key arrives with the data layer, and
  # a record assembled by hand (a test fixture, an older snapshot) has not got
  # it. Absent is "may be chosen", which is the rule as it stood.
  defp selectable?(feat), do: Map.get(feat, :level_up_selectable?, true)

  # Only the slots whose pool **is** the general feat list. The class bonus slot
  # draws on its own list and is left alone — see the module doc for why, and for
  # why the racial slot is not.
  defp off_the_class_list?(%{kind: kind}, feat, unavailable)
       when kind in [:general, :epic_general, :racial],
       do: MapSet.member?(unavailable, feat.id)

  defp off_the_class_list?(_slot, _feat, _unavailable), do: false

  # Hoisted out of the per-feat test so `candidates/2` reads one class record
  # instead of three hundred.
  defp unavailable(ruleset, slot), do: unavailable_feats(ruleset, Map.get(slot, :taken_with))

  defp unavailable_feats(_ruleset, nil), do: MapSet.new()

  defp unavailable_feats(ruleset, class) do
    case Map.fetch(ruleset.classes, class) do
      # ⚠ `Map.get`, because a ruleset built by hand in a test may predate the
      # key. A class that *is* in the data always carries it — the loader fills
      # it from `unavailable_feats` and the ruleset reports
      # `{:missing_data, :class_unavailable_feats}` when the whole snapshot has
      # none, so an empty answer here cannot pass for a checked one.
      {:ok, definition} -> Map.get(definition, :unavailable_feats) || MapSet.new()
      :error -> MapSet.new()
    end
  end

  defp accepts_kind?(%{kind: :general}, feat), do: general?(feat) and not feat.epic?
  defp accepts_kind?(%{kind: :epic_general}, feat), do: general?(feat)
  defp accepts_kind?(%{kind: :racial}, feat), do: general?(feat) and not feat.epic?

  defp accepts_kind?(%{kind: :class_bonus, class: class, epic?: epic?}, feat) do
    MapSet.member?(feat.bonus_for, class) and (epic? or not feat.epic?)
  end

  # The human racial bonus feat draws on exactly the general feat list
  # («the choices for a human's racial bonus feat are exactly all general
  # feats», fandom `General feat`), so it shares the general rule.
  #
  # ⚠ `type` is Fandom's own **taxonomy of feats**, not a flag saying which slot
  # takes one. Reading it as a flag — `type == "general"` — refused `Epic weapon
  # focus` (`combat`), `Epic energy resistance` (`defensive`), `Epic spell
  # focus` (`spell`) and `Hellball` (`epic spell`) from every slot in the game.
  # Exactly one value of that field is a statement about slots, and the wiki
  # makes it in as many words:
  #
  #   «Some feats are given a **type** of "class"; this means the feat is not a
  #   general feat, so it is only available to the indicated classes, and only
  #   at the designated level(s).» — fandom `Class feat`
  #
  # So the rule is written as what a general slot does **not** take. The five
  # values below are the ones whose own pages say the feat is handed out rather
  # than chosen:
  #
  #   "class"           fandom `Class feat`, quoted above
  #   "race"            fandom `Racial feat` — «given to a player character at
  #                     character creation on the basis of that character's race»
  #   "classrace"       both at once; `Darkvision` lists races *and* class levels
  #                     as its prerequisite and is `use=automatic`
  #   "monster"         «This feat is only available for NPCs by default»
  #                     (`Blindsight, 60 foot radius`, `Monster uncanny reflex`)
  #   "instant custom"  the module-builder hooks: «All DM characters start with
  #                     this instant feat» (`DM tool`, `Player tool`)
  #
  # Everything else Fandom types — `combat`, `defensive`, `spell`, `epic spell`,
  # `item creation`, `metamagic`, `special`, `general` — is a choice, and is
  # gated by its own prerequisites plus, for an epic feat, by the slot being an
  # epic one. The vocabulary itself is pinned in
  # `test/build_calculator/wiki/parsed_snapshot_test.exs`, and every value in it
  # is classified by `the whole feat type vocabulary is classified` in this
  # module's test, so a new one cannot arrive unclassified.
  @granted_not_chosen ["class", "classrace", "instant custom", "monster", "race"]

  @doc """
  The `type` values a general slot refuses, from Fandom's own feat vocabulary.

  Exposed so the test can check the classification against the whole vocabulary
  rather than against the handful of feats that happen to appear in a fixture.
  """
  @spec granted_not_chosen() :: [String.t()]
  def granted_not_chosen, do: @granted_not_chosen

  # ⚠ …and `@granted_not_chosen` is a reading of **Fandom's** vocabulary, so it
  # may only be applied to a value that came from Fandom. A shard-only feat has
  # no Fandom record at all; its `type` is the Siala page's «Тип навыка» label,
  # a different field on a different wiki that merely spells to the same
  # strings. Trusting it here would repeat the original bug one wiki over, and
  # expensively: `Riding Sprint` and `Smile of Death` are both «Тип навыка:
  # Особый» with no requirements block, and both say in their own text «Умение
  # **нельзя выбрать при росте персонажа**» — they come from items («Обломок
  # трезубца», «Шапка Железного Шута»). A rule reading their type as Fandom's
  # `special` would put two unpickable item abilities in every character's
  # general slot, free of charge.
  #
  # For a shard-only feat the slot answer is on the page's own «Возможность
  # взятия фита» block, which the loader turns into `general: true` (hence
  # `type` "general") or into `bonus_for`. No block, no offer — "the page did
  # not say" is not "it is a general feat" (CLAUDE.md §3). The five custom
  # weapon proficiencies do carry the block and are taken normally.
  #
  # ⚠ Those two are **no longer refused here**, and this comment is kept because
  # it is the argument for the rule and not for the coincidence: since the data
  # states «нельзя выбрать при росте персонажа» outright
  # (`level_up_selectable?`), `selectable?/1` refuses them and would keep
  # refusing them if the shard ever gave those pages a slot block or renamed
  # their type. What this clause still does is the general case: a shard page
  # that says nothing about slots offers nothing.
  defp general?(%{siala_only?: true} = feat), do: feat.type == "general"
  defp general?(%{type: nil}), do: false
  defp general?(%{type: type}), do: type not in @granted_not_chosen

  defp general_slot(ruleset, level, epic?, taken_with) do
    if MapSet.member?(ruleset.epic.general_feat_levels, level) do
      kind = if epic?, do: :epic_general, else: :general
      [%{id: :general, kind: kind, class: nil, taken_with: taken_with, epic?: epic?}]
    else
      []
    end
  end

  defp racial_slot(%Build{race: race}, ruleset, level, epic?, taken_with) do
    case ruleset.races do
      %{^race => %{extra_feats: %{level: ^level, count: count}}} when count > 0 ->
        [%{id: :racial, kind: :racial, class: race, taken_with: taken_with, epic?: epic?}]

      _ ->
        []
    end
  end

  defp class_bonus_slot(%Build{} = build, ruleset, level, epic?) do
    with class when not is_nil(class) <- Build.class_at(build, level),
         {:ok, definition} <- Map.fetch(ruleset.classes, class),
         class_level = Build.class_level_at(build, level),
         count when count > 0 <- bonus_feat_count(definition, class_level, ruleset, class) do
      for index <- 1..count do
        %{
          id: bonus_slot_id(class, index),
          kind: :class_bonus,
          class: class,
          # The same class by construction: the slot exists because *this* level
          # is a bonus-feat level of the class taken on it.
          taken_with: class,
          # ⚠ The **character** being epic is what opens the epic half of the
          # list, not the class level being one of the class's epic bonus
          # levels. A class has one bonus list, and epic entries on it are
          # gated by their own "21st level" prerequisite, nothing else:
          #
          #   «each class has a single list of bonus feat choices that is used
          #   regardless of whether or not the bonus can be called "epic".
          #   Some choices might only appear as epic bonus feats, but this is a
          #   consequence of those feats' particular prerequisites being
          #   impossible to meet otherwise» — fandom `Bonus feat`
          #
          # The same page spells out the case this used to get wrong: «an epic
          # character taking a fifth ranger level could potentially substitute
          # ''epic prowess'' (a ranger epic bonus feat) for the favored enemy
          # normally obtained at that level.»
          #
          # Checked across all 23 vanilla class pages, not two (CLAUDE.md §3):
          # of the seven classes with pre-epic bonus feats every one says it
          # (Fighter «If the character is an epic character, then the epic
          # fighter bonus feats are also available»; Wizard «(not necessarily
          # an epic wizard)»; Ranger «not just epic ranger levels»; Rogue «When
          # reaching rogue level 10, 13, 16 or 19 at epic character levels»;
          # Champion of Torm «before becoming an epic champion of Torm»; Harper
          # Scout «when Harper scout levels are taken after level 20»; Weapon
          # Master, via `weapon of choice`). The other fifteen grant bonus
          # feats only on epic class levels, where the question cannot arise,
          # and no page states the opposite.
          epic?: epic?
        }
      end
    else
      _ -> []
    end
  end

  # ⚠ The **first** slot of a class on a level keeps the id it has always had,
  # and only the second one carries an index. That asymmetry is deliberate and
  # it is the whole compatibility story: `build.feats[level]` is keyed by slot
  # id, so a shared link, a saved row and an exported build all name the slot by
  # this string. Numbering from scratch (`{:class_bonus, :ranger, 1}`) would have
  # renamed the one slot every existing build already uses, and the pick would
  # not crash — it would quietly stop matching any slot the level offers, which
  # is the failure mode this fix exists to remove, reintroduced at a hundred
  # times the scale.
  #
  # The index counts slots, so it starts at 2 for the second one and generalises
  # if a class ever grants three.
  defp bonus_slot_id(class, 1), do: {:class_bonus, class}
  defp bonus_slot_id(class, index), do: {:class_bonus, class, index}

  # ⚠ **How many**, not "whether" — a class level may grant more than one bonus
  # slot. Ranger 35 grants two («at levels 23, 25, 26, 29, 30, 32, 35(two bonus
  # feats), 38, and 40» — `fandom:Ranger`), and while this answered a boolean the
  # second one had nowhere to go: the player lost a whole feat, silently, and the
  # data could not say otherwise because `epic_bonus_feat_levels` is a *set*.
  # The count now comes from the class table's own cell (`2 bonus feats`) through
  # `bonus_feat_counts`, which carries only the levels where it is not one.
  #
  # ⚠ A level absent from `bonus_feat_counts` grants **one** slot, not none: the
  # question of *whether* a level grants anything is still the three readings
  # below, and the count only says how many. Reading the map alone would take the
  # slot away from every level in the game bar one.
  #
  # ⚠ And the `1` is not a game number smuggled in (CLAUDE.md §3): the three
  # readings answer yes/no, and the cardinality of "yes" is one by definition —
  # exactly what a *set* of bonus feat levels has always meant. The only number
  # that comes from the wiki is the one in `bonus_feat_counts`, and the day a
  # class grants three the data says three and nothing here changes. Writing a
  # count for every level instead would be the same fact recorded twice, in two
  # files, free to drift.
  #
  # ⚠ The third reading is not a bonus-feat level according to the class table at
  # all: the table says the level **grants** a feat, and the game offers the
  # class's bonus list instead (`vanilla/grant_substitutions.json`, measured on
  # `Weapon of choice` — GAME_CHECKS.md M2 and M2b).
  #
  # ⚠ It was gated on the character being epic for about an hour on 14.08.2026,
  # because the source sentence reads «If an **epic character** takes weapon
  # master level 1, alternatives to weapon of choice are available» and the first
  # measurement was taken at 21. The second one (a level-7 Weapon Master, six
  # feats in the slot) removed the gate: «epic» in that sentence describes the
  # consequence, not the condition — only an epic character passes the
  # alternatives' own prerequisites.
  #
  # ⚠ And the grant has to disappear with it — `Build`, same map. A slot here
  # without the withdrawal there would hand the feat over *and* let a slot be
  # spent on it.
  defp bonus_feat_count(definition, class_level, ruleset, class) do
    if bonus_feat_level?(definition, class_level, ruleset, class) do
      # `Map.get` with a default of one: a ruleset assembled by hand in a test
      # predates the key, and "one slot" is the rule as it stood everywhere.
      definition |> Map.get(:bonus_feat_counts, %{}) |> Map.get(class_level, 1)
    else
      0
    end
  end

  defp bonus_feat_level?(definition, class_level, ruleset, class) do
    MapSet.member?(definition.bonus_feat_levels, class_level) or
      MapSet.member?(definition.epic_bonus_feat_levels, class_level) or
      substituted_grant?(ruleset, class, class_level)
  end

  defp substituted_grant?(ruleset, class, class_level) do
    ruleset |> Map.get(:grant_substitutions, %{}) |> Map.has_key?({class, class_level})
  end
end
