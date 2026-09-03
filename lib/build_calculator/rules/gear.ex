defmodule BuildCalculator.Rules.Gear do
  @moduledoc """
  Equipment as numbers the player types, not as an armoury.

  Full items with stats come later (CLAUDE.md §1). Until then the build carries
  the totals a player reads off their character sheet:

    * `abilities` — `%{con: 12}`, capped per ability by `ruleset.gear.ability_bonus_cap`.
      A number here may be **negative**: penalties from equipment are real, and
      the same cascade runs downwards
    * `ac` — `%{armor: 8, deflection: 5}`, one number per AC type. **Different
      types stack** and are simply summed; what happens **inside** one type,
      where a number here meets a bonus the build earns itself, is the shard's
      own rule and lives in `BuildCalculator.Rules.ArmorClass` (task 3.39 — the
      larger of the two, except a type declared cumulative). ⚠ **Not capped
      here**, for the same reason `saves` below is not: the one type with a
      ceiling is clipped over that whole sum, once. ⚠ Since task 3.41 a number
      here is the **bonus** of the thing worn, not the whole of it: the item's
      base is `worn` below
    * `worn` — `%{armor: :full_plate, shield: :large}`, the thing worn in each
      category the ruleset declares (task 3.41). The one entry of this struct
      that is a **choice out of a dictionary** rather than a number, and two
      numbers come off it — the item's base armour class, which always stacks,
      and the ceiling it puts on the dexterity bonus **to armour class**. Both
      are `BuildCalculator.Rules.Worn`'s to read; no category and no item is
      named here
    * `saves` — one bonus to all three saves. **Not capped here**: the
      `saving_throw_bonus` ceiling covers everything that adds to all three
      saves at once, and equipment is no longer the only such source — the
      Spellcraft ranks count towards the same +20. Two separate clamps would let
      a build carry +40, so `Rules.compute/2` clamps the sum
    * `skills` — `%{discipline: 50, hide: 50}`, one number per skill (task 3.20,
      Dan: «чтобы можно было указать „дисциплина +50“ … чтобы в „Итого“ увидеть
      финальную картинку по скиллам»). **Not capped here either**, and for the
      very same reason: the `skill_bonus` ceiling of +50 already covers the
      shard's racial bonus to a named skill, so a second clamp of its own would
      let a Human carry +62 to Discipline while every source says +50. One clip
      over the pool, in `BuildCalculator.Rules.Skills`
    * `feats` — feats an item **grants**: the one entry here that is not a number
      the player adds up but a fact the rules read. It costs no feat slot and
      counts as owned, so a class's requirements and every bonus reader see it
      like any other feat — see `BuildCalculator.Rules.GearFeats` for the whole
      rule, including the one requirement a borrowed feat does **not** satisfy
      (another feat's). Kept in this struct because it belongs to the same layer
      ("what is worn") and therefore travels in the shared link with everything
      else.

      ⚠ An entry is a bare id **or** a `{feat_id, choice}` pair, exactly like a
      slot's contents (task 3.97, решение Dan 25.08.2026: «Подобный фит не может
      существовать без привязки к конкретному выбору»). Without the value there
      is nothing for `Skill focus`'s +3 to land on and no weapon for
      `Weapon focus` to name. Both forms are legal and a bare one is not a
      defect: every link shared before that task carries bare ids, and the build
      says what is missing rather than refusing to open
    * `weapon` — the weapon in the character's hands, by id, and
      `weapon_attack` — the number the item carries (task 3.5 part B, Dan:
      «в вещах можно будет выбрать оружие, допустим „скимитар“ с усилением
      атаки +5. И будем показывать в деталях об АБ значение с конкретным
      оружием»). **One** weapon and one number, never a matrix of "AB per
      weapon kind". ⚠ One number since task 3.52 and two before it: an item
      also carries an *enhancement* bonus, and the shard's items really do
      (Dan named both while listing the +20 cap's contents). It is not an input
      here because the only thing that told the two apart was damage, and damage
      is not computed anywhere — see `ruleset.gear.weapon_bonus_kinds`, which is
      where the kinds are declared. Whether this weapon may be held at all, and
      what its number is worth, is `BuildCalculator.Rules.GearWeapon`
    * `off_hand_weapon` / `off_hand_weapon_attack` — the same pair for the
      **second hand** (task 3.132, Dan: «многие билды берут 2 оружия вместо щита
      или двуручки … Можем ввести вторую руку? с возможностью выбрать оружие
      вместо щита и его attack bonus»). Two fields rather than a list of hands,
      for the same reason there is one weapon and not a matrix: every consumer
      prints a row per hand, and a hand is not a repetition of the same thing —
      it has its own refusals (a two-handed weapon may not go there), its own
      attack bonus and its own number of attacks.

      ⚠ A weapon here and a shield in `worn` are mutually exclusive, and the two
      refusals are **worded differently** on purpose: «занята двуручным оружием»
      and «занята вторым оружием» are different facts about the same hand, and
      one wearing the other's sentence would send the player to change the wrong
      thing (`Rules.Worn`, `Rules.GearWeapon`)

  ## The point is the cascade, not the input box

  `+12 CON` is not "+12 CON". It is +6 to the modifier, which is +6 hit points
  on **every** level — +246 on a level 41 build. That is the arithmetic players
  get wrong by hand and the reason the calculator exists, so the order of
  application is fixed and not negotiable (CLAUDE.md §6):

      point buy + race  ->  the +1 every fourth level  ->  gear

  and everything derived is computed from the **final** score. `ac_naked` is the
  one number computed with no gear at all — including a dexterity modifier taken
  before the gear bonus — because otherwise "голым" stops meaning naked.
  """

  @typedoc """
  What the player says one item lends: a feat, or a feat and the value it names.

  The same duality a feat slot holds, and deliberately the same shape — one
  reader answers both (`BuildCalculator.Rules.Build.feat_id/1` and
  `feat_choice/1`), so a second way of writing "a feat with a parameter" never
  comes into existence.
  """
  @type feat_entry :: atom() | {atom(), atom()}

  @type t :: %__MODULE__{
          abilities: %{atom() => integer()},
          ac: %{atom() => integer()},
          worn: %{atom() => atom()},
          saves: integer(),
          skills: %{atom() => integer()},
          feats: [feat_entry()],
          weapon: atom() | nil,
          weapon_attack: integer(),
          off_hand_weapon: atom() | nil,
          off_hand_weapon_attack: integer()
        }

  defstruct abilities: %{},
            ac: %{},
            # Что надето, по категориям ruleset'а (задача 3.41). Ключи и значения
            # — из данных (`ruleset.gear.worn`), поэтому ни одного имени доспеха
            # или щита ни здесь, ни где-либо в `rules/` нет. Пустая мапа — «ничего
            # не надето», и это ровно то, во что открывается уже расшаренная
            # ссылка: предмета в ней не записано, значит и базы у неё нет.
            worn: %{},
            saves: 0,
            skills: %{},
            feats: [],
            # Оружие в руках и его число. ⚠️ ОДНО с задачи 3.52 и два до неё:
            # усиление у предмета в игре есть (кейс J1, Dan назвал attack bonus
            # и enchantment bonus отдельно), но отличалось оно от бонуса атаки
            # только уроном, а урон модель не считает вовсе — то есть игрок
            # вводил два числа и разницы не видел нигде (решение Dan
            # 19.08.2026). Какие именно поля бывают, объявлено в данных
            # (`ruleset.gear.weapon_bonus_kinds`), чтобы веб-слой не перечислял их
            # заново, — и объявленный вид без поля здесь роняет сборку.
            weapon: nil,
            weapon_attack: 0,
            # Вторая рука (задача 3.132). Пусто — «одна рука», ровно то
            # состояние, в котором открывается всякая уже расшаренная ссылка:
            # второго оружия в ней не записано, и число главной руки от этих
            # полей не зависит вовсе.
            off_hand_weapon: nil,
            off_hand_weapon_attack: 0

  @doc "Builds a gear struct from a keyword list or map, filling in the defaults."
  @spec new(Enumerable.t()) :: t()
  def new(fields \\ []), do: struct!(__MODULE__, Map.new(fields))

  @doc """
  Whether the player has entered anything at all.

  A declared feat counts — it is something the player entered, and it moves real
  numbers (`Rules.GearFeats`), so a set answering "nothing here" while carrying
  one would understate the whole block it belongs to.

  So does a chosen weapon, and for the same reason twice over: it is the player's
  own statement, and it is what makes `Weapon focus` count at all
  (`Rules.GearWeapon`). ⚠ The weapon counts even with both its numbers at zero —
  a plain scimitar in hand is still a scimitar, and it is what decides whether
  three feats reach the attack roll.

  And so does a worn item, on the same argument a third time: the clothing row
  is worth `0` armour class and still answers a question — it is what says the
  character wears no armour, which is what a Monk's bonuses hang on.
  """
  @spec any?(t()) :: boolean()
  def any?(%__MODULE__{} = gear) do
    gear.saves != 0 or Enum.any?(gear.abilities, &(elem(&1, 1) != 0)) or
      Enum.any?(gear.ac, &(elem(&1, 1) != 0)) or Enum.any?(gear.skills, &(elem(&1, 1) != 0)) or
      gear.feats != [] or not is_nil(gear.weapon) or not is_nil(gear.off_hand_weapon) or
      gear.worn != %{}
  end

  @doc """
  What is worn in one category — `nil` for a category the player said nothing
  about.

  The id as the player recorded it, **not** resolved against the ruleset: whether
  this ruleset still has such an item is `BuildCalculator.Rules.Worn`'s question,
  and answering it here would make an unknown id indistinguishable from an empty
  slot at the one place that could still name it.
  """
  @spec worn(t(), atom()) :: atom() | nil
  def worn(%__MODULE__{worn: worn}, category), do: Map.get(worn, category)

  @doc """
  Records what is worn in one category, or takes it off with `nil`.

  Plain data in, plain data out, exactly like `toggle_feat/2`: nothing here asks
  whether the item exists — the caller resolves the id first
  (`BuildCalculator.Ids`), and an empty category is stored as an
  **absent** key rather than as `nil`, so «снял» and «не выбирал» are one state
  and one URL code.
  """
  @spec put_worn(t(), atom(), atom() | nil) :: t()
  def put_worn(%__MODULE__{} = gear, category, nil) when is_atom(category),
    do: %__MODULE__{gear | worn: Map.delete(gear.worn, category)}

  def put_worn(%__MODULE__{} = gear, category, item)
      when is_atom(category) and is_atom(item),
      do: %__MODULE__{gear | worn: Map.put(gear.worn, category, item)}

  @doc """
  What the player typed for one skill — `0` for a skill they said nothing about.

  **Raw, before the ceiling.** The `+50` on skill bonuses is not this term's own:
  the shard's racial bonus to a named skill counts towards the very same ceiling
  («Этот бонус входит в кап навыка +50»), so clipping here and clipping there
  would be the two half-clips that once let a build carry +40 on its saves
  (CLAUDE.md §9). `BuildCalculator.Rules.Skills` offers both to one clip.

  ⚠ `0` and «нет записи» are one answer here on purpose, unlike in the terms of
  a skill's value: a number the player typed and then cleared to zero adds
  nothing, and there is nothing to say about it either.
  """
  @spec skill_bonus(t(), atom()) :: integer()
  def skill_bonus(%__MODULE__{skills: skills}, skill), do: Map.get(skills, skill, 0)

  # Which field of this struct holds which of the weapon's numbers. The kinds
  # themselves are declared in the data (`gear.weapon_bonus_kinds`); this is the
  # one place that says where each lands, so a kind the data grows without a field
  # here fails the **build** rather than counting as zero — the loader asks this
  # function and raises on `nil`.
  # ⚠ Keyed by the **hand** as well since task 3.132. Not one field per kind with
  # the hand looked up somewhere else: which hand a number belongs to is exactly
  # what a caller must not be able to get wrong, and the two hands are two
  # inputs the player fills in separately.
  @weapon_bonus_fields %{
    {:main, :attack} => :weapon_attack,
    {:off, :attack} => :off_hand_weapon_attack
  }

  # Which hands a build has, in the order everything prints them. A list rather
  # than two names scattered through the core: the pair travels together into
  # `Rules.GearWeapon`, `Rules.DualWield` and the breakdown, and a third hand
  # would be a data question rather than a rewrite.
  @hands [:main, :off]

  @doc """
  The hands a build holds weapons in, main first.

  Exposed so nothing outside this module writes `:main` and `:off` down as a
  pair of literals — the same reason `ruleset.gear.weapon_bonus_kinds` is data
  rather than a list in `Rules.GearWeapon`.
  """
  @spec hands() :: [atom()]
  def hands, do: @hands

  @doc """
  Which field of this struct carries the weapon bonus of `kind` for `hand` —
  `nil` when the struct has no field for it.

  Read by `BuildCalculator.Data.Loader`, which refuses to compile a ruleset
  declaring a kind that would land nowhere **in either hand**.
  `Rules.GearWeapon` is what reads the numbers themselves.
  """
  @spec weapon_bonus_field(atom(), atom()) :: atom() | nil
  def weapon_bonus_field(kind, hand \\ :main) when is_atom(kind) and is_atom(hand),
    do: Map.get(@weapon_bonus_fields, {hand, kind})

  @doc """
  Which weapon this hand holds — `nil` when it holds none.

  The id as the player recorded it, **not** resolved against the ruleset and not
  checked for legality: both are `Rules.GearWeapon`'s questions, and answering
  them here would make an unknown id indistinguishable from an empty hand at the
  one place that could still name it — exactly the division `worn/2` above keeps.
  """
  @spec weapon(t(), atom()) :: atom() | nil
  def weapon(%__MODULE__{weapon: weapon}, :main), do: weapon
  def weapon(%__MODULE__{off_hand_weapon: weapon}, :off), do: weapon

  @doc """
  What the player typed for one of the weapon's numbers — `0` for a kind this
  struct has no field for, which only a ruleset the loader refused could ask
  about.
  """
  @spec weapon_bonus(t(), atom(), atom()) :: integer()
  def weapon_bonus(%__MODULE__{} = gear, kind, hand \\ :main) do
    case weapon_bonus_field(kind, hand) do
      nil -> 0
      field -> Map.fetch!(gear, field)
    end
  end

  @doc """
  Adds or removes one declaration — a click on a chip.

  `choice` is the value the item's feat names; `nil` declares the bare feat,
  which is what every declaration was before task 3.97 and still is for a feat
  that takes no parameter at all.

  ## The entry is the unit, not the feat id

  Two items lending `Skill focus` for two different skills are two declarations
  and two bonuses — решение Dan, 25.08.2026: «разные значения — разные записи».
  So uniqueness is by the **pair**: toggling with a value only ever removes that
  pair, and toggling a bare id only ever removes the bare declaration. Neither
  can shadow the other, which is what makes a chip and its value one reversible
  click each.

  ⚠ Two declarations of the same pair are therefore one, and that is a known
  limit rather than an oversight: an item lends a feat, not a number of copies
  of it, and «×N с вещей» stays out until the armoury gives the count a place to
  live (`Build.feat_takes_owned/4`, task 3.29 — closed by decision, not by code).

  Kept sorted and unique, for the same reason `Rules.Build`'s class choices are:
  the build does not record the order things were clicked in, and the URL code
  has to be the same for the same build every time. Plain `Enum.sort/1`, so the
  order is Erlang's term order — every bare id before every pair — and
  `BuildCalculator.Encoding` sorts the very same list the very same
  way. A build that names no values therefore encodes byte for byte as it did
  before values existed.

  Plain data in, plain data out, exactly like `Build.put_feat/5`: whether this
  feat may be declared at all is `Rules.validate_gear_feat/2`'s question, and
  whether the value is one it accepts is
  `Rules.FeatChoices.gear_reasons/4`'s — both are asked *before* this, never
  guessed at by this.
  """
  @spec toggle_feat(t(), atom(), atom() | nil) :: t()
  def toggle_feat(%__MODULE__{} = gear, feat_id, choice \\ nil)
      when is_atom(feat_id) and is_atom(choice) do
    entry = entry(feat_id, choice)

    feats =
      if entry in gear.feats,
        do: List.delete(gear.feats, entry),
        else: Enum.sort([entry | gear.feats])

    %__MODULE__{gear | feats: feats}
  end

  # A `nil` choice stores the bare id rather than a pair with a `nil` in it —
  # the same rule `Build.put_feat/5` follows, and the thing byte compatibility
  # hangs on: the URL writes this entry through one key function, and a bare id
  # has to come out of it as the string it always was.
  defp entry(feat_id, nil), do: feat_id
  defp entry(feat_id, choice), do: {feat_id, choice}

  @doc """
  Ability bonuses after the per-ability ceiling.

  Returns `{%{ability => bonus}, capped?}`; `capped?` is true when a typed number
  was clipped, which the interface has to show — a silently reduced number reads
  as a bug in the calculator.

  ## The ceiling has one side only

  The source is a *bonus* ceiling — "This limit is a bonus of +12" (fandom
  "Ability cap", revid 68173) — so a penalty is clipped by nothing here. No page
  states a floor, and mirroring +12 into a −12 would be inventing a game number
  (CLAUDE.md §3, rule 1).

  What that same page *does* say is that penalties lower the effective ceiling —
  with strength down 2, items may add no more than +10 net.

  ⚠ That interaction used to be confessed as
  `{:not_modelled, :ability_cap_penalty_interaction}`, and the confession was
  **removed 22.08.2026 by Dan's decision** (task 3.77) — not by waving it away
  but because it is **inexpressible in this input's shape**. The page describes
  a penalty and a bonus on the *same* ability from *different* sources; here an
  ability carries exactly one number, and that number means the **net**. A
  player with a +12 ring and a −2 curse types +10 and gets the right answer.
  The other two sources of a penalty are both out by the source's own words:
  true racial modifiers never enter the ceiling, and a spell is a buff (Dan,
  10.08.2026). Dan: «в реальности у одетых персонажей надето по +12 статов
  нужных в билде, что они и вобьют у нас в вещах».
  """
  @spec ability_bonuses(t(), map()) :: {%{atom() => integer()}, boolean()}
  def ability_bonuses(%__MODULE__{abilities: abilities}, ruleset) do
    cap = ruleset.gear.ability_bonus_cap

    Enum.reduce(abilities, {%{}, false}, fn {ability, bonus}, {acc, capped?} ->
      {value, clipped?} = clamp(bonus, cap)
      {Map.put(acc, ability, value), capped? or clipped?}
    end)
  end

  @doc """
  What the player typed for armour class, per type the ruleset names — raw, in
  the ruleset's own order, and `0` for a type they said nothing about.

  ## Raw, because the ceiling is not this number's own

  ⚠ Here stood `armor_class/2`, which summed the typed numbers and clipped the
  one type that has a ceiling (`dodge`, +20). Task 3.39 moved both jobs to
  `BuildCalculator.Rules.ArmorClass`, and not for tidiness: since Dan's rule
  of 16.08.2026 the typed number does not simply add to what the build earns by
  itself — it **competes** with it, and a cumulative type is clipped over the
  **sum** of the two. Clipping here first and again there is the pair of
  half-clips that once let the saves carry +40 while every source said +20
  (CLAUDE.md §9).

  There is still **no general ceiling on armour class** — different types stack,
  and no source names one. That is a decision (Dan, 03.08.2026) rather than a
  hole, which is why nothing prints `{:missing_data, {:stat_cap, :ac}}`.
  """
  @spec ac_typed(t(), map()) :: [{atom(), integer()}]
  def ac_typed(%__MODULE__{ac: ac}, ruleset),
    do: for(type <- ruleset.gear.ac_types, do: {type, Map.get(ac, type, 0)})

  # Only `value > cap` is clipped: the ceiling is stated for a bonus, and a
  # penalty has no stated floor. Whatever is typed below zero passes through
  # whole — see the note above `ability_bonuses/2`.
  defp clamp(value, nil), do: {value, false}
  defp clamp(value, cap) when value > cap, do: {cap, true}
  defp clamp(value, _cap), do: {value, false}
end
