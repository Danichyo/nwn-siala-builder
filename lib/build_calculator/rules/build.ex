defmodule BuildCalculator.Rules.Build do
  @moduledoc """
  A character build: plain data, nothing computed.

  `levels` is the spine — one class id per character level, in the order the
  levels were taken. Order is not cosmetic: past character level 20 it decides
  base attack and saves outright (CLAUDE.md §3), so the list is never sorted or
  deduplicated.

  Everything else is keyed by character level:

    * `ability_increases` — `%{4 => :str}`, the +1 on every fourth level
    * `feats` — `%{level => %{slot_id => pick}}`. A map per level, not a list:
      feat slots are not interchangeable (CLAUDE.md §6), so which slot a feat
      went into is part of the build. A `pick` is either a bare `feat_id` or
      `{feat_id, choice}` — see below.
    * `skills` — `%{level => %{skill_id => ranks_bought_at_this_level}}`. Ranks
      are stored per level, not as a total, because both their price and their
      cap depend on the level they were bought at.
    * `spells` — `%{level => %{spell_slot_id => spell_id}}`. Known spells are the
      same slot model as feats (CLAUDE.md §6): a Sorcerer's seventh level grants
      one spell of circle 1, one of circle 2 and one of circle 3, and which slot
      a spell went into is part of the build.

  `base_abilities` are point-buy scores *before* racial modifiers. `gear` is the
  manual equipment layer: it is part of the build, so it travels in the shared
  link like everything else.

  ## A feat pick may carry a parameter

  Some feats are taken **with** something: `Favored enemy` names a creature type
  and may be taken again for another one, `Spell focus` names a school,
  `Skill focus` a skill, `Weapon focus` a weapon. Storing the bare id cannot say
  *which*, and two picks of one id are then indistinguishable — the calculator
  cannot tell a legal second Favored Enemy from a wasted duplicate.

  So a slot holds either form:

      %{general: :toughness}                     # no parameter
      %{general: {:favored_enemy, :goblinoid}}   # taken with a choice

  Both are read through the same helpers — `feat_id/1`, `feat_choice/1`,
  `feats_at/2`, `feats_taken/2` — which always answer in bare ids, so nothing
  that already reads a build has to know the second form exists. That is
  deliberate: the interface, the URL codec and the export learn to *write*
  choices in a later wave, and until they do, every build in the wild is still
  the first form and must keep working unchanged.

  Which feats accept a choice, and out of what, is data
  (`BuildCalculator.Rules.FeatChoices`) — never a list of feat names here.

  ## A class may ask for a choice of its own, once, forever

  Separately from a feat pick, a class may ask for a fixed number of values
  out of a named domain when its **own** first class level is taken — a
  Cleric picks two domains, later a Wizard will pick a school (task 3.10).
  `class_choices` carries these: `%{cleric: [:air, :war]}`. Keyed by class,
  not by character level, because the choice belongs to the class and outlives
  wherever in the ladder that class's levels sit — editing an early level's
  class does not touch it as long as the class stays somewhere in `levels`
  (`prune_class_choices/1`, called from `truncate/2` and `replace_level/3`
  drops an entry only once its class is gone from the build entirely).

  Which classes ask for a choice, out of what domain, how many and whether it
  is required is data (`BuildCalculator.Rules.ClassChoices`) — the same rule
  as feat choices above, and deliberately the same mechanism: both are "N
  distinct values out of one named `choice_domains` dictionary", so a Cleric's
  `domain` and a Wizard's future `spell_school` read through one module rather
  than two similar ones that would drift apart (AGENT_QUEUE.md §3.14).

  ## A feat a CLASS hands over may still owe a choice — `granted_choices`

  `Weapon of choice` is handed to a Weapon Master at his first class level
  (`granted_feats`) and it names a weapon: «the weapon chosen to be a weapon of
  choice by a weapon master becomes the focus for all of their special
  abilities» (`fandom:Weapon of choice`). A grant is not a pick and sits in no
  slot, so the pair `{feat, choice}` of `feats` has nowhere to go — and until
  task 3.26 the value was recorded **nowhere**, which is Dan's own observation
  of 10.08.2026 («ВМ получает weapon of choice автоматически, но для него ещё
  надо выбрать оружие»).

  So a second map carries it, keyed by character level and then by feat:

      granted_choices: %{14 => %{weapon_of_choice: :scimitar}}

  ⚠ **Deliberately not a pseudo-slot inside `feats`.** That would have been
  free (`feat_choices/3`, `truncate/2` and the URL codec all read `feats`
  already), and it would have made the grant indistinguishable from a pick for
  every one of the readers that count slots — `feats_at/2`, `feat_picks/3`,
  `feat_takes/3`, the canonical export, the levelling guide. A granted feat
  costs no slot (CLAUDE.md §6), and one shape answering two questions is how
  slot accounting goes wrong.

  ⚠ **Keyed by level, not by feat**, unlike `class_choices` above — and for the
  opposite reason. A class's choice outlives the level it was made on because it
  belongs to the class; this one belongs to *the grant*, which happens on a
  level, so `truncate/2` scopes it the way it scopes `feats` and a delta at
  level 13 cannot see a weapon chosen at 14. It also needs no invented count:
  each grant records one value, and a ruleset that ever hands the same feat over
  twice records two, one per level, with nothing to derive.

  ⚠ A recorded value is **not** proof the feat is granted there: editing the
  class of a level leaves it behind, exactly as it leaves the level's feat picks
  behind. Readers gate on the grant itself
  (`granted_feat_choices/4`), so a stale entry counts for nothing.
  """

  alias BuildCalculator.Rules.{Build, Gear, GearFeats}

  @type ability :: :str | :dex | :con | :int | :wis | :cha
  @type class_id :: atom()
  @typedoc """
  One feat slot on one level, as `build.feats[level]` keys it.

  ⚠ The class bonus has **two** shapes, and that is a compatibility decision
  rather than an oversight: a class level may grant more than one bonus slot
  (ranger 35 grants two), the slots need different keys or the second pick would
  overwrite the first, and the first slot had to keep the name every shared link
  and saved build already spells. So the first is `{:class_bonus, class}` as it
  always was, and the second is `{:class_bonus, class, 2}`.
  """
  @type slot_id ::
          :general
          | :racial
          | {:class_bonus, class_id()}
          | {:class_bonus, class_id(), pos_integer()}
  @type spell_slot_id :: {:circle, non_neg_integer(), non_neg_integer()}

  @typedoc "What a feat was taken *with* — a creature type, a school, a skill."
  @type feat_choice :: atom()

  @typedoc "What sits in a feat slot: a feat, or a feat and the choice made with it."
  @type feat_pick :: atom() | {atom(), feat_choice()}

  @type t :: %__MODULE__{
          ruleset_version: String.t() | nil,
          race: atom() | nil,
          alignment: atom() | nil,
          base_abilities: %{ability() => integer()},
          levels: [class_id()],
          ability_increases: %{pos_integer() => ability()},
          feats: %{pos_integer() => %{slot_id() => feat_pick()}},
          skills: %{pos_integer() => %{atom() => non_neg_integer()}},
          spells: %{pos_integer() => %{spell_slot_id() => atom()}},
          gear: Gear.t(),
          class_choices: %{class_id() => [atom()]},
          granted_choices: %{pos_integer() => %{atom() => feat_choice()}}
        }

  # The default scores are the neutral placeholder the wiki uses to describe the
  # scale ("a 'typical' human having a score of 10 in each ability"), not a
  # point-buy starting point — the web layer always sets real ones.
  defstruct ruleset_version: nil,
            race: nil,
            alignment: nil,
            base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
            levels: [],
            ability_increases: %{},
            feats: %{},
            skills: %{},
            spells: %{},
            gear: %Gear{},
            class_choices: %{},
            granted_choices: %{}

  @doc "Builds a struct from a keyword list or map, filling in the defaults."
  @spec new(Enumerable.t()) :: t()
  def new(fields \\ []) do
    struct!(__MODULE__, Map.new(fields))
  end

  @doc "Number of character levels taken."
  @spec character_level(t()) :: non_neg_integer()
  def character_level(%Build{levels: levels}), do: length(levels)

  @doc "Class taken at `level` (1-based), or `nil` past the end of the build."
  @spec class_at(t(), pos_integer()) :: class_id() | nil
  def class_at(%Build{levels: levels}, level) when level >= 1, do: Enum.at(levels, level - 1)
  def class_at(%Build{}, _level), do: nil

  @doc "Class levels per class, counting the whole build."
  @spec class_levels(t()) :: %{class_id() => pos_integer()}
  def class_levels(%Build{levels: levels}), do: tally(levels)

  @doc """
  Class levels per class, counting only the first `up_to` character levels.

  This is the shape the epic rules need: base attack and base saves look at the
  class split as it stood at character level 20 and ignore everything after.
  """
  @spec class_levels(t(), non_neg_integer()) :: %{class_id() => pos_integer()}
  def class_levels(%Build{levels: levels}, up_to), do: levels |> Enum.take(up_to) |> tally()

  @doc """
  Which level of its own class the pick at character `level` is.

  `[:fighter, :wizard, :fighter]` -> `class_level_at(build, 3) == 2`.
  """
  @spec class_level_at(t(), pos_integer()) :: pos_integer() | nil
  def class_level_at(%Build{} = build, level) do
    case class_at(build, level) do
      nil -> nil
      class -> build |> class_levels(level) |> Map.fetch!(class)
    end
  end

  @doc "Distinct classes used in the whole build."
  @spec classes_used(t()) :: MapSet.t(class_id())
  def classes_used(%Build{levels: levels}), do: MapSet.new(levels)

  @doc """
  The same build cut back to its first `level` character levels.

  Deltas are computed as `compute(truncate(b, n)) -> compute(b)`; there is no
  separate incremental algorithm, precisely so the two cannot drift apart
  (CLAUDE.md §5).
  """
  @spec truncate(t(), non_neg_integer()) :: t()
  def truncate(%Build{} = build, level) do
    %Build{
      build
      | levels: Enum.take(build.levels, level),
        ability_increases: drop_above(build.ability_increases, level),
        feats: drop_above(build.feats, level),
        skills: drop_above(build.skills, level),
        spells: drop_above(build.spells, level),
        granted_choices: drop_above(build.granted_choices, level)
    }
    |> prune_class_choices()
  end

  @doc "Appends one class level to the build."
  @spec add_level(t(), class_id()) :: t()
  def add_level(%Build{} = build, class), do: %Build{build | levels: build.levels ++ [class]}

  @doc """
  The same build with character `level` set to `class`, appending if it is the
  next level.

  Editing the class of a level in the *middle* of a finished build is a real
  operation and the reason whole-build limits cannot be checked against the
  levels before the one being edited: a 40-level build may already use four
  classes and still look like it uses one when level 5 is open.
  """
  @spec replace_level(t(), pos_integer(), class_id()) :: t()
  def replace_level(%Build{} = build, level, class) when level >= 1 do
    levels =
      if level > length(build.levels),
        do: build.levels ++ [class],
        else: List.replace_at(build.levels, level - 1, class)

    %Build{build | levels: levels} |> prune_class_choices()
  end

  # A class's own choice (`class_choices`) is keyed by class, not by level, so
  # replacing or truncating the level it happened to be taken on does not by
  # itself invalidate it — the same class taken *anywhere else* in the build
  # still owns the pick. Only a class that has left `levels` entirely loses
  # it: keeping a choice on record for a class the build no longer contains
  # would be dead weight nothing reads (no ladder row exists to show it on),
  # but leaving it in is not a correctness bug so much as clutter, and pruning
  # it here — right where `levels` changes — is cheaper than teaching every
  # reader to check membership itself.
  defp prune_class_choices(%Build{} = build) do
    used = classes_used(build)
    %Build{build | class_choices: Map.take(build.class_choices, MapSet.to_list(used))}
  end

  @doc "Feat ids taken in slots at `level` (does not include class-granted feats)."
  @spec feats_at(t(), pos_integer()) :: [atom()]
  def feats_at(%Build{feats: feats}, level) do
    feats |> Map.get(level, %{}) |> Map.values() |> Enum.map(&feat_id/1)
  end

  @doc "Feat ids taken in slots up to and including `level`."
  @spec feats_taken(t(), non_neg_integer()) :: MapSet.t(atom())
  def feats_taken(%Build{feats: feats}, level) do
    for {lv, slots} <- feats,
        lv <= level,
        {_slot, pick} <- slots,
        into: MapSet.new(),
        do: feat_id(pick)
  end

  # ------------------------------------------------------- picks and choices --

  @doc """
  The feat id out of a slot's contents, whichever form it is stored in.

  `:toughness` and `{:favored_enemy, :goblinoid}` both answer with a bare atom,
  which is what every existing reader of a build expects.
  """
  @spec feat_id(feat_pick()) :: atom()
  def feat_id({feat, _choice}) when is_atom(feat), do: feat
  def feat_id(feat) when is_atom(feat), do: feat

  @doc """
  What the feat in a slot was taken **with**, or `nil` when nothing was recorded.

  `nil` is not "no choice was needed" — it is "this pick does not say". Whether a
  choice was owed is a question about the feat, not about the slot, and it is
  answered from the data by `BuildCalculator.Rules.FeatChoices`.
  """
  @spec feat_choice(feat_pick()) :: feat_choice() | nil
  def feat_choice({feat, choice}) when is_atom(feat), do: choice
  def feat_choice(feat) when is_atom(feat), do: nil

  @doc """
  Puts `feat` in `slot_id` at `level`, with `choice` when one was made.

  A `nil` choice stores the bare id, so a build that makes no choices is byte for
  byte the build it was before this existed — which is what keeps every shared
  link, export and saved row readable.
  """
  @spec put_feat(t(), pos_integer(), slot_id(), atom(), feat_choice() | nil) :: t()
  def put_feat(%Build{} = build, level, slot_id, feat, choice \\ nil)
      when level >= 1 and is_atom(feat) do
    pick = if is_nil(choice), do: feat, else: {feat, choice}
    at_level = build.feats |> Map.get(level, %{}) |> Map.put(slot_id, pick)

    %Build{build | feats: Map.put(build.feats, level, at_level)}
  end

  @doc "What sits in one slot, in stored form (`nil` when the slot is empty)."
  @spec feat_pick(t(), pos_integer(), slot_id()) :: feat_pick() | nil
  def feat_pick(%Build{feats: feats}, level, slot_id) do
    feats |> Map.get(level, %{}) |> Map.get(slot_id)
  end

  @doc """
  Sort key for a feat slot — the one order every list of picks comes out in.

  A level holds a map of slots, and a map has no order, so anything that prints
  or replays the picks of one level has to choose one. Three places did, each
  with its own `Enum.sort_by(…, &inspect/1)`: this function, the canonical text
  export and the view screen's guide. The order they produced is the order kept
  here — general and racial before a class bonus, alphabetical inside each —
  because it is what the player already reads.

  ⚠ What changed is only that it is **stated** rather than inherited from the
  `Inspect` protocol. Ordering by `inspect/1` means the order a player sees is
  keyed on a debugging representation: nothing promises `{:class_bonus, :fighter}`
  will render with that space in it forever, and three copies of the same
  accident cannot be kept in step by anything.

  ⚠ Deliberately **not** the order the URL codec writes slots in
  (`BuildCalculator.Ids.slot_key/1`, which sorts `"class_bonus:…"`
  ahead of `"general"`). Those two answer different questions: the codec needs one
  stable byte order and a decoded build is a map either way — measured, the
  round-trip does not depend on it — while this one is read by people. Making
  them agree would move the class bonus to the front of every exported level for
  no reason a source gives.

  ⚠ Two class-bonus slots of the same class on the same level sort by their
  index, and the un-indexed shape is the first of them — hence the pair in the
  key rather than the bare class. All keys stay two-element tuples on purpose:
  Erlang compares tuples by **size** first, so a three-element key would have
  sorted the class bonus ahead of `{0, :general}` and behind nothing at all.

  ⚠ **Total on purpose**, and the last clause is not defensive padding: this is
  reached from `Rules.compute/2` (attack bonuses ask which weapon a feat was
  taken with), so a shape it refuses would not misorder a line — it would take
  the whole page down. `t:slot_id/0` names three shapes and the codec accepts
  exactly those. Unknown shapes sort last, among themselves by Erlang's own
  term order, so nothing crashes and nothing is silently reordered — which is
  exactly what let roughly twenty test fixtures carry invented shapes
  (`{:epic_general, 21}`, `{:general, 0}`) for a long time under the old
  `inspect/1` sorting: nothing here ever refused them, so nothing ever said so.
  Fixed at the fixtures, not here (AGENT_QUEUE.md §7, closed 11.08.2026) — the
  clause stays total regardless, because a shape *this* function has never
  seen (a hand-edited link, a future bug) must still not take the page down,
  and `BuildCalculator.Ids.slot_key/1` is where such a shape is
  refused loudly instead.
  """
  @spec slot_order(slot_id() | term()) :: {0 | 1 | 2, term()}
  def slot_order({:class_bonus, class}), do: {1, {class, 1}}
  def slot_order({:class_bonus, class, index}), do: {1, {class, index}}
  def slot_order(id) when is_atom(id), do: {0, id}
  def slot_order(other), do: {2, other}

  @doc """
  Every slot filled up to and including `level`, as
  `{character_level, slot_id, feat_id, choice}`.

  Ordered by level and then by `slot_order/1`, so two builds with the same picks
  produce the same list.
  """
  @spec feat_picks(t(), non_neg_integer()) :: [{pos_integer(), slot_id(), atom(), term()}]
  def feat_picks(%Build{feats: feats}, level) do
    for {lv, slots} <- Enum.sort_by(feats, &elem(&1, 0)),
        lv <= level,
        {slot_id, pick} <- Enum.sort_by(slots, &slot_order(elem(&1, 0))) do
      {lv, slot_id, feat_id(pick), feat_choice(pick)}
    end
  end

  @doc """
  The choices recorded for `feat` up to and including `level`, in pick order.

  One entry per pick, `nil` where that pick recorded nothing — the count matters
  as much as the values, because "taken twice, neither saying which" is a
  different fact from "taken once".

  Scoped to **one feat id** on purpose. Taking `Spell focus (evocation)` uses up
  evocation for `Spell focus` and for nothing else: `Greater spell focus` in the
  same school is not merely legal but the point of the feat, so the key that has
  to be unique is the pair, never the choice alone.
  """
  @spec feat_choices(t(), atom(), non_neg_integer()) :: [feat_choice() | nil]
  def feat_choices(%Build{} = build, feat, level) do
    for {_lv, _slot, id, choice} <- feat_picks(build, level), id == feat, do: choice
  end

  # -------------------------------------------- choices made for a class grant --

  @doc """
  What the feat a class handed over on `level` was chosen **with**, or `nil`.

  `nil` is "nothing recorded", never "nothing was owed": whether this grant owes
  a value at all is a question about the feat and the class table, and
  `BuildCalculator.Rules.FeatChoices.granted_candidates/4` answers it from the
  data.
  """
  @spec granted_choice(t(), pos_integer(), atom()) :: feat_choice() | nil
  def granted_choice(%Build{granted_choices: by_level}, level, feat) do
    by_level |> Map.get(level, %{}) |> Map.get(feat)
  end

  @doc """
  Records what `feat`, handed over on `level`, was chosen with — `nil` clears it.

  Plain data in, plain data out, exactly like `put_feat/5` and
  `toggle_class_choice/3`: whether the value is legal here is
  `BuildCalculator.Rules.FeatChoices.validate_granted/4`'s question and has to be
  asked *before* this is called. Clearing is never refused, the same as emptying a
  slot.

  An empty level is dropped rather than left as `%{}`, so "chose and took it
  back" is byte for byte the build that never chose — which is what keeps the URL
  codec's frozen fixtures frozen.
  """
  @spec put_granted_choice(t(), pos_integer(), atom(), feat_choice() | nil) :: t()
  def put_granted_choice(%Build{} = build, level, feat, choice)
      when level >= 1 and is_atom(feat) do
    at_level =
      case choice do
        nil -> build.granted_choices |> Map.get(level, %{}) |> Map.delete(feat)
        value -> build.granted_choices |> Map.get(level, %{}) |> Map.put(feat, value)
      end

    granted_choices =
      if at_level == %{},
        do: Map.delete(build.granted_choices, level),
        else: Map.put(build.granted_choices, level, at_level)

    %Build{build | granted_choices: granted_choices}
  end

  @doc """
  Every choice recorded for a class grant up to `level`, as `{level, feat, choice}`.

  Ordered by level and then by feat id, so two builds with the same choices
  produce the same list — the same promise `feat_picks/2` makes, and for the same
  reader: the URL codec writes these rows and needs one stable byte order.

  ⚠ Raw, ungated: a row survives its class being edited away, exactly as a
  level's feat picks do. Whoever asks "what counts" wants
  `granted_feat_choices/4`.
  """
  @spec granted_choice_picks(t(), non_neg_integer()) :: [{pos_integer(), atom(), feat_choice()}]
  def granted_choice_picks(%Build{granted_choices: by_level}, level) do
    for {lv, at_level} <- Enum.sort_by(by_level, &elem(&1, 0)),
        lv <= level,
        {feat, choice} <- Enum.sort(at_level),
        do: {lv, feat, choice}
  end

  @doc """
  Values recorded for `feat` on the levels that really do hand it over, up to
  `level`.

  The gate is the whole point, and it is why this takes a ruleset while
  `feat_choices/3` does not: a value stays on record when the level's class
  changes, and counting it would let a build keep a Weapon Master's weapon after
  the Weapon Master level became a Fighter level. `nil`s cannot appear here —
  nothing is recorded until a value is chosen.
  """
  @spec granted_feat_choices(t(), map(), atom(), non_neg_integer()) :: [feat_choice()]
  def granted_feat_choices(%Build{} = build, ruleset, feat, level) do
    for {lv, id, choice} <- granted_choice_picks(build, level),
        id == feat,
        feat in granted_feats_at(build, ruleset, lv),
        do: choice
  end

  @doc """
  Every value `feat` is held with **for keeps** — its slot picks and its class
  grants, in that order.

  The choice-level twin of `feats_permanent/3`, and the same three-way split of
  the question:

    * **what values does the character hold** — this one. A `Weapon focus` in a
      slot and a `Weapon of choice` from the class both name a weapon, and a rule
      that reads «with the chosen weapon» has to see both;
    * **how many slots went on it** — `feat_choices/3`, slots only. A grant is
      not a take and must never inflate `feat_takes/3`;
    * **what an item lends** — not this one, `feat_choices_owned/4` right below.

  ⚠ The third bullet used to read «neither. A declaration under «Вещи» cannot
  say *which* value it was granted with», and that was true of the model until
  task 3.97 rather than true of the question. A declaration says which value now
  (решение Dan, 25.08.2026), and the split between this and `feat_choices_owned/4`
  is the very line `feats_permanent/3` and `feats_owned/3` keep — measured, H7:
  a borrowed value prices an **effect** and opens no other feat's requirement.
  So this function stays exactly as it was and every caller that judges a *pick*
  keeps calling it.

  ⚠ Slot picks keep their `nil`s (a pick made before choices were recorded says
  nothing, and dropping it would have it satisfy a requirement about a value
  nobody wrote down); grants have none to keep.
  """
  @spec feat_choices_permanent(t(), map(), atom(), non_neg_integer()) :: [feat_choice() | nil]
  def feat_choices_permanent(%Build{} = build, ruleset, feat, level) do
    feat_choices(build, feat, level) ++ granted_feat_choices(build, ruleset, feat, level)
  end

  @doc """
  Every value `feat` is held with by **any** route — slots, class grants and the
  items declared under «Вещи», in that order.

  The choice-level twin of `feats_owned/3`, and it draws the line in exactly the
  same place, because it is the same measured line (H7, 14.08.2026):

    * **is a bonus counted with this value** — this one. `Skill focus` off an
      amulet names a skill and that skill gets its +3, the same way a worn
      `Toughness` is hit points;
    * **is another FEAT's requirement satisfied with it** — `feat_choices_permanent/4`.
      An item opens no feat, so it cannot open one "in the chosen school"
      either, and `same_choice_as` never reads this;
    * **how many takes went on it** — neither: `feat_takes/3` counts slots and
      `feat_takes_owned/4` adds the item's single take. Two values off two items
      are two bonuses and still one take.

  ⚠ Two readers today, and both price an effect off a value:
  `Rules.Skills.receiving_skills/4` (which skill a bonus lands on) and
  `Rules.AttackBonuses` (which weapon the roll is rolled with). A third that
  judged a *pick* by this would quietly undo H7.

  ⚠ The gear half is **not** level-scoped, exactly as `feats_owned/3`'s is not:
  `truncate/2` leaves gear alone, so a delta computed at level 4 sees the same
  items the finished build does.
  """
  @spec feat_choices_owned(t(), map(), atom(), non_neg_integer()) :: [feat_choice() | nil]
  def feat_choices_owned(%Build{} = build, ruleset, feat, level) do
    feat_choices_permanent(build, ruleset, feat, level) ++
      GearFeats.choices(build.gear, ruleset, feat)
  end

  @doc """
  How many times `feat` was picked up to and including `level`.

  A feat the data marks repeatable with **no** parameter — `Epic toughness`, the
  six `Great …` — is taken again simply by spending another slot on it, so the
  count of picks is the count of takes. There is deliberately no counter in this
  struct: a number beside the picks would be the same fact written twice, and two
  writings of one fact drift apart.

  Feats a class hands over are not picks and are not counted; `feats_owned/3`
  answers "has it", this answers "how many slots went on it".
  """
  @spec feat_takes(t(), atom(), non_neg_integer()) :: non_neg_integer()
  def feat_takes(%Build{} = build, feat, level), do: length(feat_choices(build, feat, level))

  @doc """
  How many times `feat` was taken, counting an **item** that lends it as one.

  `feat_takes/3` counts slots; this counts what the character has. A declaration
  under «Вещи» (`Rules.GearFeats`) is worth one take, so `Epic toughness` picked
  once and lent by an amulet is **two** takes and twenty hit points twice over
  (Dan, 09.08.2026: «Это будет +2»).

  ⚠ **This is the count of the effect, and only of the effect.** A second
  sentence used to stand here — that the stated ceiling on *takes*
  (`repeatable.max_takes`) counts the item's take too, «or the ceiling could be
  walked around by wearing the feat instead of picking it». That was our own
  inference from Dan's arithmetic, nobody had said it, and the measurement said
  otherwise (14.08.2026, `GAME_CHECKS.md` H8): «брать эти фиты в билде также
  можно вплоть до 10 раз (если фит уже взят с вещи его можно взять при левел апе
  этот же фит)». The take ceiling counts slots — `feat_takes/3` — and
  `Rules.FeatChoices` reads that one.

  The loophole closes on the other ceiling, the one on the **effect**, which Dan
  named in the same breath: «как максимум для УЧЁТА там всё равно будет только
  10 раз». Ten picks plus an amulet are eleven takes here and still two hundred
  hit points, because `Rules.FeatBonuses` clamps the sum (`max_total`).

  ⚠ Known and **deliberately not modelled** — Dan's own decision, 14.08.2026,
  after the survey (AGENT_QUEUE.md 3.29). The shard's copies are **numbered**
  («какой-то epic toughness 6») and the same number worn and picked does not
  stack in game, but here takes are counted as a number and summed: «при подсчёте
  статов или ХП в Итогах мы можем их просто складывать… и ставим кап на 10 штук…
  учитывая СУММУ того, что взяли в билде, и того, что набрали с вещей». His
  reason is that nobody is expected to declare these off gear at all — the gear
  block exists to open Weapon Master and to pick up `Epic prowess`.

  The survey found the question narrower than it looked: **seven** feats can be
  hit by it (`epic_toughness` and the six `great_*` — the only ones whose bonus
  depends on the *count* of takes), and every repeatable feat *with a choice* is
  immune by construction, because a pick is identified by its value and a
  declaration carries a bare id.

  ⚠ **One take, never more**, and never attributed to a value. An item lends the
  feat, not a number of copies of it, and a declaration cannot say *which* school
  or enemy it was granted with — the build says so through
  `{:not_modelled, {:gear_feat_choice, id}}`. So for a feat whose takes must
  differ (`Favored enemy`) the item's take collides with nothing and blocks
  nothing; `feat_choices/3` stays slots-only on purpose.
  """
  @spec feat_takes_owned(t(), map(), atom(), non_neg_integer()) :: non_neg_integer()
  def feat_takes_owned(%Build{} = build, ruleset, feat, level) do
    feat_takes(build, feat, level) + gear_takes(build, ruleset, feat)
  end

  defp gear_takes(%Build{gear: gear}, ruleset, feat) do
    if MapSet.member?(GearFeats.held(gear, ruleset), feat), do: 1, else: 0
  end

  @doc """
  How many times `feat` was picked with each value — `%{fire: 2, electricity: 1}`.

  The pair is the unit that repeats, not the feat: `Epic energy resistance` may
  be taken twice for fire and once for electricity (Дан, 02.08.2026), which is
  two takes of one thing and one of another. `nil` is a key like any other and
  counts the picks that recorded nothing.
  """
  @spec feat_takes_by_choice(t(), atom(), non_neg_integer()) ::
          %{(feat_choice() | nil) => pos_integer()}
  def feat_takes_by_choice(%Build{} = build, feat, level) do
    build |> feat_choices(feat, level) |> Enum.frequencies()
  end

  @doc """
  Feats the character *has* up to `level`, whatever the route: picked in a slot,
  handed over by a class, or granted by an **item** declared under «Вещи».

  A **class's** prerequisites must use this and not `feats_taken/2`. On Siala
  every martial class grants Toughness at its first level, and Dwarven Defender
  requires Toughness — counting only picked feats would refuse a Fighter the
  prestige class over a feat he already owns. The item route is the same story
  and is the shard's own practice: Dan's Weapon Master opens on character level
  14 with `Expertise` off armour and `Whirlwind attack` off a quarterstaff.

  The third route is task 3.3 (`Rules.GearFeats`) and lands here rather than
  beside here on Dan's own reading (09.08.2026): «если фит есть, допустим
  тафнес, то и HP будут увеличены».

  ⚠ **A FEAT's prerequisites do not use this** — that is `feats_permanent/3`,
  and the split is a measured game fact rather than bookkeeping (Dan,
  14.08.2026, `GAME_CHECKS.md` H7): «фит с вещи не позволит взять другой фит,
  требующий тот фит, который мы взяли с вещи… но вот КЛАСС можно взять». This
  doc used to say the opposite in as many words — «one set of owned feats
  therefore answers both questions at once… there is deliberately no second,
  narrower set» — and the argument for it (two sets would drift) was sound but
  lost to the engine, which draws the line exactly there. The two sets do not
  drift because there is one reader of each: `Rules.Prereqs` picks between them
  off `requirement_of`, in one clause, with the quote beside it.

  So what this answers now is: **which of a class's requirements are satisfied,
  and which bonuses are counted.**

  Two consequences worth naming, both of them wanted:

    * a **set**, so a feat both picked in a slot and lent by an item counts
      exactly once *as a feat the character has*. Where the same feat's **effect**
      is counted the number is a different question and has its own reader —
      `feat_takes_owned/4`, which adds the item's take to the slots'. The number
      of takes a *ceiling* governs is a third question again, and slots-only:
      `feat_takes/3`;
    * the six markup readers (`Rules.FeatBonuses`, `AbilityBonuses`,
      `SaveBonuses`, `ArmorClass`, `AttackBonuses`, `Skills.feat_bonuses/3`)
      count an item's feat, and their `unmodelled/3` twins report it when they
      cannot — no extra wiring was needed for either.

  ⚠ **What this is not for: deciding that a slot may not be spent.** A third
  bullet used to stand here saying the picker calls an item's feat a duplicate
  and refuses to sell a slot for it. That was a false illegality and is gone
  (09.08.2026): an item comes off, so refusing the permanent version of a feat
  the character is only borrowing costs the player a legal build. What answers
  "may this be picked" is `feats_permanent/3`, right below; the warning that the
  slot buys nothing is `Rules.feat_pick_caveats/3`.

  ⚠ The gear half is **not** level-scoped, and must not be: `level` cuts the
  ladder, while an item is worn whichever level is being asked about.
  `truncate/2` leaves `gear` alone for the same reason, so a delta computed at
  level 4 sees the same items the finished build does.
  """
  @spec feats_owned(t(), map(), non_neg_integer()) :: MapSet.t(atom())
  def feats_owned(%Build{} = build, ruleset, level) do
    feats_permanent(build, ruleset, level)
    |> MapSet.union(GearFeats.held(build.gear, ruleset))
  end

  @doc """
  Feats the character has **for keeps** — picked in a slot or handed over by a
  class, and nothing an item lends.

  The narrower half of `feats_owned/3`, and the difference is a game fact rather
  than bookkeeping: a slot and a class grant cannot be lost, an item can be taken
  off. So this is what "already taken" means when a *pick* is being judged
  (`Rules.FeatChoices`) — a feat on loan does not spend the player's slot for
  him — and, since 14.08.2026, what "already held" means to **another feat's**
  prerequisites.

  Which way each question goes:

    * **is a CLASS's requirement satisfied / is a bonus counted** —
      `feats_owned/3`. The feat is on the character while the item is worn, and
      that is Dan's own reading (09.08.2026), confirmed for the class half by
      measurement on 14.08.2026;
    * **is a FEAT's requirement satisfied** — this one. «Мы взяли expertise
      с вещи, improve expertise не появится в выборке доступных фитов» (Dan,
      14.08.2026, `GAME_CHECKS.md` H7). The engine ignores worn feats when it
      builds the pick list, and the refusal is the ordinary
      `{:requires_feat, id}`;
    * **may a slot be spent on it** — this one too, and note that the two are
      not the same sentence: `Expertise` itself stays pickable with `Expertise`
      on armour («а вот сам expertise там будет»), while `Improved expertise`
      does not. Refusing the first would be the false illegality named in
      `feats_owned/3`'s doc.
  """
  @spec feats_permanent(t(), map(), non_neg_integer()) :: MapSet.t(atom())
  def feats_permanent(%Build{} = build, ruleset, level) do
    MapSet.union(feats_taken(build, level), granted_feats(build, ruleset, level))
  end

  @doc """
  Feats the class taken at character `level` hands over **on that level alone**.

  `granted_feats/3` accumulates ("what does the character own by now"); this
  answers a different question — "what does the class hand over here", the raw
  list off the class's own table.

  ⚠ **Not what the `○` glyph of CLAUDE.md §6 prints.** It used to be, and that
  was баг 1.14 (Dan, 10.08.2026): a class hands over what the character may well
  own already, so the first level of a second class printed six names and brought
  one. The interface therefore asks `BuildCalculatorWeb.Builder.Feats.granted/3`,
  which subtracts what is already owned while keeping a repeat *inside the same
  class* (`Defensive awareness` I/II/III share one id). This function stays the
  raw reading, and it has its own callers: the text importer needs to recognise
  a name the page lists whether or not it is new, and `Feats.free_later/3` scans
  the ladder ahead, where nothing is owned yet.

  The class level is worked out from the build, so a hypothetical build can be
  passed in: a class card has to answer "what would *this* class give me here".
  An empty list is the honest answer for a level that grants nothing.
  """
  @spec granted_feats_at(t(), map(), pos_integer()) :: [atom()]
  def granted_feats_at(%Build{} = build, ruleset, level) when level >= 1 do
    with class when not is_nil(class) <- class_at(build, level),
         %{granted_feats: by_level} <- Map.get(ruleset.classes, class) do
      class_level = class_level_at(build, level)

      by_level
      |> Map.get(class_level, [])
      |> withhold_substituted(ruleset, class, class_level, level)
    else
      _ -> []
    end
  end

  def granted_feats_at(%Build{}, _ruleset, _level), do: []

  @doc "Feats granted for free by the classes taken up to `level`."
  @spec granted_feats(t(), map(), non_neg_integer()) :: MapSet.t(atom())
  def granted_feats(%Build{levels: levels}, ruleset, level) do
    levels
    |> Enum.take(level)
    |> Enum.with_index(1)
    |> Enum.reduce({%{}, MapSet.new()}, fn {class_id, character_level}, {seen, acc} ->
      class_level = Map.get(seen, class_id, 0) + 1

      granted =
        case ruleset.classes do
          %{^class_id => %{granted_feats: by_level}} ->
            by_level
            |> Map.get(class_level, [])
            |> withhold_substituted(ruleset, class_id, class_level, character_level)

          _ ->
            []
        end

      {Map.put(seen, class_id, class_level), Enum.into(granted, acc)}
    end)
    |> elem(1)
  end

  # A "grant" the character is really offered a choice instead of
  # (`vanilla/grant_substitutions.json`; `Weapon of choice` at Weapon Master 1,
  # measured twice — GAME_CHECKS.md M2 and M2b). Withheld here and opened as a
  # slot in `Rules.FeatSlots`, both off the same map: were the two to disagree,
  # the feat would be granted *and* choosable.
  #
  # ⚠ `character_level` is no longer read — the parameter stays because the
  # signature is the one every caller already computes, and because the day this
  # file learns a second substitution with a real condition, it will be needed
  # again. For an hour on 14.08.2026 there was one: the rule was gated on the
  # character being epic, until the second measurement said otherwise.
  defp withhold_substituted(granted, ruleset, class, class_level, _character_level) do
    case ruleset |> Map.get(:grant_substitutions, %{}) |> Map.fetch({class, class_level}) do
      {:ok, feats} -> granted -- feats
      :error -> granted
    end
  end

  @doc "Total ranks bought in `skill` up to and including `level`."
  @spec skill_ranks(t(), atom(), non_neg_integer()) :: non_neg_integer()
  def skill_ranks(%Build{skills: skills}, skill, level) do
    Enum.reduce(skills, 0, fn {lv, bought}, acc ->
      if lv <= level, do: acc + Map.get(bought, skill, 0), else: acc
    end)
  end

  # -------------------------------------------------------- class choices --

  @doc """
  What `class` was chosen with — a Cleric's domains, in pick order.

  `[]` when nothing has been recorded yet, which is the honest reading for a
  class with no choice mechanic at all as much as for one whose choice is
  simply unmade (`Rules.ClassChoices` is where the two are told apart, since
  telling them apart needs the ruleset and this does not).
  """
  @spec class_choice(t(), class_id()) :: [atom()]
  def class_choice(%Build{class_choices: choices}, class_id), do: Map.get(choices, class_id, [])

  @doc """
  Adds or removes one value from `class`'s choice — a click on a domain chip.

  Plain data in, plain data out, exactly like `put_feat/5`: whether `value` is
  legal here (a member of the right domain, room left under the class's
  count) is `Rules.ClassChoices.validate/4`'s question and must be asked
  *before* this is called, not by this function guessing at it. Toggling is
  add-or-remove, nothing more — a fresh value is always appended, never made
  to displace one already held. `replace_class_choice/3` below is the other
  primitive a chip's click can mean (задача 3.171); `Rules.ClassChoices.
  click/4` is what decides which one a given click is.
  """
  @spec toggle_class_choice(t(), class_id(), atom()) :: t()
  def toggle_class_choice(%Build{} = build, class_id, value)
      when is_atom(class_id) and is_atom(value) do
    current = class_choice(build, class_id)
    updated = if value in current, do: List.delete(current, value), else: current ++ [value]

    choices =
      if updated == [],
        do: Map.delete(build.class_choices, class_id),
        else: Map.put(build.class_choices, class_id, updated)

    %Build{build | class_choices: choices}
  end

  @doc """
  Replaces `class`'s choice outright with `[value]` — whatever was held
  before is gone, unconditionally (задача 3.171).

  Plain data in, plain data out, same as `toggle_class_choice/3` and for the
  same reason: legality is asked *before* this is called, not guessed at
  here. The only caller today is `Rules.ClassChoices.click/4`, and only for
  a `count == 1` choice full to capacity — a Wizard clicking a fresh school
  while one is already held. Calling this for a `count > 1` choice (a
  Cleric's two domains) would silently discard a value nothing asked to
  drop; nothing here stops that, the same way `toggle_class_choice/3` trusts
  its caller to have asked `ClassChoices.validate/4` first.
  """
  @spec replace_class_choice(t(), class_id(), atom()) :: t()
  def replace_class_choice(%Build{} = build, class_id, value)
      when is_atom(class_id) and is_atom(value) do
    %Build{build | class_choices: Map.put(build.class_choices, class_id, [value])}
  end

  defp tally(levels), do: Enum.frequencies(levels)

  defp drop_above(map, level), do: Map.filter(map, fn {lv, _} -> lv <= level end)
end
