defmodule BuildCalculator.Rules.Worn do
  @moduledoc """
  What the character **wears**, as an item with a size rather than as one typed
  number (task 3.41).

  Until this task the gear block asked for a number per armour class type and
  nothing else, so two facts every real character carries had nowhere to live:
  the **base** armour class of the thing worn, which always stacks, and the
  **ceiling it puts on the dexterity bonus**. A player in full plate with DEX 30
  was shown +10 of dexterity where the game gives +1.

  ## Three columns out of two different pages, and they must not be merged

    * **base AC** — `fandom:Armor check penalty`, whose table is headed «Type of
      armor **or shield**», so shields are in it: 1 / 2 / 3;
    * **armour check penalty** — the third column of that same table, and the
      one that lands nowhere near armour class: it comes off six named skills
      (task 3.42, `armor_check_penalty/2`);
    * **maximum dexterity bonus** — `fandom:Maximum dexterity bonus` (revid
      59855), whose table is headed «Type of **armor**» and contains no shield at
      all.

  So a shield never caps dexterity, and that is not an omission of ours but the
  shape of the source. It is stated in the data (`caps_dexterity`) and the
  loader refuses a shield that names a `max_dex`, because a shield quietly
  starting to cut dexterity would be an invented game rule.

  ⚠ The two columns of the **one** page do not agree about which item is the
  heavier, and that is the point of keeping them apart: by base armour class a
  tower shield is the smallest thing here (3 against full plate's 8), and by
  penalty it is the largest by a wide margin (−10 against −8).

  ## The cap applies to armour class and to nothing else

  Quoted in full because three numbers hang on it: «This cap applies only to AC;
  it does not affect the attack bonus for ranged weapons, the attack bonus from
  weapon finesse, reflex saves, nor dexterity-based skills». `dexterity_cap/2`
  is therefore read by exactly one caller — `Rules.ArmorClass.geared/3`, for the
  dexterity term of «AC в шмоте» — and never by the reflex save, the attack roll
  or a skill. Capping the modifier itself would have been one line shorter and
  wrong in three places at once.

  ## Nothing here knows a piece of armour by name

  Which categories exist, which armour class type each lands in, which items
  they hold and what their two numbers are is all data
  (`ruleset.gear.worn`, out of `siala_41/overrides.json`'s shared vanilla
  section). There is no plate and no tower shield in this module, the same way
  `Rules.WeaponTypeBonus` holds no weapon and `Rules.RacialBonus` no race.

  ## An item nobody knows is nothing, and it is named elsewhere

  `Rules.Gear`'s `worn` map may carry an id the ruleset has no item for — a
  hand-edited link, or a build recomputed with an older ruleset. Everything here
  ignores it (no base, no cap), and the decoder is what says so out loud:
  `BuildCalculator.Encoding` whitelists both halves of the pair and
  reports `{:unknown_worn, …}`. That is the same division of labour the typed AC
  numbers have had since v2 — an unknown *type* is dropped at decode and never
  reaches the core.

  ## An item may also be one this character cannot use (task 3.43)

  Two refusals, both about the same slot and both quoted:

    * **the race cannot use this item.** `fandom:Shield proficiency`: «Tower
      shields additionally require that the wielder be medium-sized or larger.
      (In particular, gnomes and halflings may not use tower shields, even with
      this feat.)» — and the two races say the same on their own pages, which is
      the field the item points at by name (`race_restriction`);
    * **both hands are taken.** Same page: «Creatures may not simultaneously use
      a shield and a two-handed weapon.» Which weapon takes both hands is not
      here and cannot be — it is a function of two sizes, `Rules.Wield`'s to
      answer;
    * **the off hand holds a weapon** (task 3.132, Dan: щит и второе оружие
      одновременно взять нельзя). A separate reason from the one above and
      deliberately worded differently: «занята двуручным оружием» and «занята
      вторым оружием» are different facts about the same hand, and a player
      reading the wrong one goes and changes the wrong thing.

  ⚠ The mutual exclusion is decided **in the weapon's favour**, exactly as it
  already was for a two-handed weapon: the shield is what gets refused. Asking
  it the other way round as well would close a literal loop — `worn/2` already
  asks `GearWeapon.held/3`, and `held/3` would have to ask `worn/2` back.

  ⚠ **A refused item stays in the build and is named** (`illegal/2`), exactly as
  a weapon whose proficiency feat was taken away (`Rules.GearWeapon`) and a feat
  the shard has since switched off (`Rules.GearFeats`). Silently confiscated
  reads as a bug in the calculator; named reads as a rule.

  ⚠ **And it is worth nothing while refused** — no base armour class, no armour
  check penalty, and it does not switch a Monk's bonuses off either. Before this
  task a Карлик was offered a tower shield along with +3 AC and −10 to stealth the
  game does not give him. Everything numeric here reads `worn/2`, which is the
  legal half; `recorded/2` is the whole of it and is read only by `illegal/2`.
  """

  alias BuildCalculator.Rules.{Build, Gear, GearWeapon, Wield}

  @typedoc """
  One thing that can be worn: a row of the source's table.

  `name` is the row as the page spells it — «Studded leather armor, Hide armor»
  — because the row names two armours with identical numbers and both of them
  *are* that row. `id` is a handle for it, not the name of one of the two.
  """
  @type item :: %{
          id: atom(),
          category: atom(),
          name: String.t() | nil,
          base_ac: integer(),
          max_dex: integer() | nil,
          weight_class: weight_class(),
          armor_check_penalty: integer()
        }

  @typedoc """
  How heavy this item is — **light, medium, heavy, none of the three, or nobody
  said** (task 3.141).

  Five values and not four, because `:none` and `:unknown` are different
  statements about the same silence and a rule reads them differently. The
  "нулёвка" row is *typeless* — the game prints no armour type for it at all —
  and the Ranger keeps his benefits in it; `:unknown` is a ruleset whose layer
  never named a class, and there the Ranger's benefits are counted with a caveat
  beside them. Merging the two would make a `vanilla` build silently claim an
  answer measured on Siala.

  ⚠ **Which words exist is the data's to say**, which is why the type is a plain
  atom and not a list of four: today they are the shard's measured «none»,
  «light», «medium» and «heavy» (`siala_weight_classes` beside the items), and
  a shard that adds a fifth must not have to come here for it. The loader
  refuses a class outside the list the category declares, so a typo cannot read
  as «not medium» and hand the benefits back.

  ⚠ `:unknown` is the one value this core owns, and it means only «this layer
  did not say» — the data may not declare a class by that name, and the loader
  refuses one that does.
  """
  @type weight_class :: atom()

  @typedoc "A slot the player chooses one item for — armour, shield."
  @type category :: %{
          id: atom(),
          ru: String.t() | nil,
          ac_type: atom(),
          caps_dexterity?: boolean(),
          occupies_off_hand?: boolean(),
          items: [item()]
        }

  @typedoc "Why this character may not use a worn item he recorded."
  @type reason ::
          {:not_usable_by_race, atom()}
          | {:two_handed_weapon, atom()}
          | {:off_hand_weapon, atom()}

  @doc "Every category the ruleset declares, in its own order. `[]` when none."
  @spec categories(map()) :: [category()]
  def categories(ruleset), do: Map.get(ruleset.gear, :worn) || []

  @doc "One category by id, or `nil`."
  @spec category(map(), atom()) :: category() | nil
  def category(ruleset, id), do: Enum.find(categories(ruleset), &(&1.id == id))

  @doc """
  The item chosen in `category_id` **and legal here** — `nil` otherwise.

  Same contract as `Rules.GearWeapon.held/2`: an item the character may not use
  is not what he is wearing, however plainly the build records it. What he
  recorded is `recorded/2`, and `illegal/2` is what names the difference.
  """
  @spec chosen(Build.t(), map(), atom()) :: item() | nil
  def chosen(%Build{} = build, ruleset, category_id) do
    case Enum.find(worn(build, ruleset), fn {category, _item} -> category.id == category_id end) do
      {_category, item} -> item
      nil -> nil
    end
  end

  @doc """
  Everything the player recorded, as `[{category, item}]` in the ruleset's own
  order — **legal or not**.

  Only what resolves: a category with nothing chosen, and an id the ruleset has
  no item for, are both absent rather than present with `nil`.

  ⚠ Read by `illegal/2` and by the caveats, never by a number. Everything that
  adds up reads `worn/2`.
  """
  @spec recorded(Build.t(), map()) :: [{category(), item()}]
  def recorded(%Build{gear: %Gear{worn: worn}}, ruleset) do
    for category <- categories(ruleset),
        item_id = Map.get(worn, category.id),
        item = Enum.find(category.items, &(&1.id == item_id)),
        do: {category, item}
  end

  @doc """
  Everything worn **that counts**, as `[{category, item}]` in the ruleset's own
  order.

  The legal half of `recorded/2`, and the one every number here reads: a refused
  item gives no base armour class and no armour check penalty (task 3.43).
  """
  @spec worn(Build.t(), map()) :: [{category(), item()}]
  def worn(%Build{} = build, ruleset) do
    for {category, item} <- recorded(build, ruleset),
        refusals(build, ruleset, category, item) == [],
        do: {category, item}
  end

  @doc """
  Why this character may not use `item` of `category` — `[]` when he may.

  **All the reasons at once**, not the first: a Карлик holding a longsword and
  wearing a tower shield fails on two independent statements, and the interface
  shows what is missing in full (CLAUDE.md §6).
  """
  @spec refusals(Build.t(), map(), category(), item()) :: [reason()]
  def refusals(%Build{} = build, ruleset, category, item) do
    race_refusals(build, ruleset, item) ++ off_hand_refusals(build, ruleset, category)
  end

  @doc """
  What the build records and may not use, as `[{category_id, item_id, reason}]`.

  One entry per reason, so a single item may appear twice; the shape is
  `Rules.illegal_gear_weapon/2`'s with the slot named, because a build wears one
  item per category and the interface prints the refusal beside its own row.
  """
  @spec illegal(Build.t(), map()) :: [{atom(), atom(), reason()}]
  def illegal(%Build{} = build, ruleset) do
    for {category, item} <- recorded(build, ruleset),
        reason <- refusals(build, ruleset, category, item),
        do: {category.id, item.id, reason}
  end

  @doc """
  What this build owes the reader about what it wears.

  Exactly one thing, and it is scoped as tightly as it can be: an item that
  **takes the off hand** is counted while the weapon in the other hand states no
  grip and has no size to derive one from (the unarmed strike is the only such
  entry in the dictionary). Whether that shield should be there at all is then
  unknown, and its base armour class is in the number either way.

  ⚠ Nothing is said when there is no such item, when no weapon is held, or when
  the item is refused already — a caveat about a question that does not arise is
  noise, the same rule `Rules.GearWeapon`'s stacking caveat follows.
  """
  @spec gaps(Build.t(), map()) :: [tuple()]
  def gaps(%Build{} = build, ruleset) do
    with true <-
           Enum.any?(worn(build, ruleset), fn {category, _} -> category.occupies_off_hand? end),
         weapon when not is_nil(weapon) <- GearWeapon.held(build, ruleset),
         nil <- Wield.grip(build, weapon, ruleset) do
      [{:missing_data, {:weapon_grip, weapon}}]
    else
      _decided_or_moot -> []
    end
  end

  @doc """
  The base armour class of what is worn, per AC type — `%{}` for a bare
  character.

  **This always stacks**, and that is the one half of the shard's rule about
  armour class that never competes: «а вот с АЦ щитовым с вещей это не
  складывается, **только с базой щита**» (Dan, 16.08.2026). What competes is the
  *bonus* the player types under the same type, and that is
  `Rules.ArmorClass`'s business.

  Summed per type rather than per category, because two categories are allowed
  to land in one type; none do today.
  """
  @spec base_ac(Build.t(), map()) :: %{atom() => integer()}
  def base_ac(%Build{} = build, ruleset) do
    for {category, item} <- worn(build, ruleset), reduce: %{} do
      acc -> Map.update(acc, category.ac_type, item.base_ac, &(&1 + item.base_ac))
    end
  end

  @doc """
  What everything worn takes off a skill the penalty applies to — `0` for a bare
  character, negative otherwise.

  **The armour and the shield add up**, and that is quoted rather than assumed:
  «If a character is wearing armor and using a shield, **both** armor check
  penalties apply» (`fandom:Armor check penalty`). Full plate and a tower shield
  are −18 together.

  ## What this is not

  ⚠ **Not a bonus with a minus sign.** Nothing here goes near `Rules.Caps` or
  `Rules.Bonuses`: the ceilings of this project are one-sided by construction
  («лимит атаки +20», «кап +50» — `Caps.clamp/3` clips above and never below),
  and feeding a penalty through a mechanism built for bonuses would either do
  nothing or do something nobody wrote down.

  ⚠ **Not per skill.** Which skills take it is a fact about the *skill* and lives
  on the skill record (`ruleset.skills[id].armor_check_penalty`); this answers
  only «how much does what is worn take off». `Rules.Skills` is what puts the two
  together, and it is the only caller.

  ⚠ **Not floored.** Whether a skill's value may go negative is stated on no
  page, so nothing here decides it — see `Rules.Skills.value/4`.
  """
  @spec armor_check_penalty(Build.t(), map()) :: integer()
  def armor_check_penalty(%Build{} = build, ruleset) do
    for {_category, item} <- worn(build, ruleset), reduce: 0 do
      total -> total + item.armor_check_penalty
    end
  end

  @doc """
  The ceiling the worn armour puts on the dexterity bonus **to armour class** —
  `nil` when there is none.

  `nil` means "no ceiling" in all three of the ways it can arise, and they are
  deliberately one answer: nothing is worn, the item states «unlimited» (the
  clothing row), or the ruleset declares no category that caps dexterity at all.
  A character with no cap is a character whose dexterity counts whole, and the
  three readings differ in nothing an answer could be built on.

  The smallest wins when more than one category caps — no ruleset ships two, and
  a maximum that grew when a second cap was added would be the wrong direction
  of wrong.

  ⚠ Read by `Rules.ArmorClass` and by nothing else. See the module doc.
  """
  @spec dexterity_cap(Build.t(), map()) :: integer() | nil
  def dexterity_cap(%Build{} = build, ruleset) do
    caps =
      for {category, item} <- worn(build, ruleset),
          category.caps_dexterity?,
          not is_nil(item.max_dex),
          do: item.max_dex

    case caps do
      [] -> nil
      caps -> Enum.min(caps)
    end
  end

  # Which field of a worn item a condition's `kind` is read off — the same
  # arrangement `Rules.Attack.weapon_property_field/1` has with a weapon, and
  # for the same reason: the loader asks first, so a ruleset naming a property
  # nobody can answer fails the build instead of shipping a rule that silently
  # never fires.
  #
  # ⚠ One entry today, and it is a *property*, not a value: the four weight
  # classes themselves are the data's words (`siala_weight_classes`), never
  # this core's. Compare `@weapon_properties`, which names `ranged` and
  # `thrown` for exactly the same reason and no weapon at all.
  @item_properties %{armor_weight_class: :weight_class}

  @doc """
  Which field of an item a `kind` of condition is read off, or `nil` for a
  property this core cannot answer.

  Asked by the loader (`Data.Loader.DualWield`), so a condition naming something
  unreadable is a build failure rather than a rule that quietly never fires.
  """
  @spec item_property_field(atom()) :: atom() | nil
  def item_property_field(property), do: Map.get(@item_properties, property)

  @doc """
  Whether an AC type is one the player picks an **item** for.

  What the caveat about an item's base hangs on (`Rules.ArmorClass.gaps/4`):
  before this task no type had an item, so a typed number could hide a base
  nobody could tell apart from it. On a type with a category the question is
  answered — the player either picked an item or wears none — and printing "we
  cannot tell" about it would be the false uncertainty CLAUDE.md §6 forbids.
  """
  @spec item_type?(map(), atom()) :: boolean()
  def item_type?(ruleset, ac_type),
    do: Enum.any?(categories(ruleset), &(&1.ac_type == ac_type))

  # ------------------------------------------------------------------ private --

  # Запрет по расе — соединение ДВУХ независимых утверждений по имени поля:
  # предмет говорит, каким полем он запрещён, раса говорит, стоит ли это поле
  # у неё. Ни имени щита, ни имени расы здесь нет, и обе стороны сверены
  # загрузчиком: ключ, которого не объявляет ни одна раса, роняет сборку.
  defp race_refusals(_build, _ruleset, %{race_restriction: nil}), do: []

  defp race_refusals(%Build{race: race} = _build, ruleset, %{race_restriction: key}) do
    case Map.get(Map.get(ruleset, :races) || %{}, race) do
      %{restrictions: restrictions} ->
        if MapSet.member?(restrictions, key), do: [{:not_usable_by_race, race}], else: []

      _no_race_yet ->
        []
    end
  end

  # А это ВТОРАЯ РУКА, и она про оружие: «Creatures may not simultaneously use a
  # shield and a two-handed weapon» (`fandom:Shield proficiency`).
  #
  # ⚠ Спрашивается ДЕРЖИМОЕ оружие (`GearWeapon.held/2`), а не записанное:
  # оружие, которое персонаж держать не может, ни атаки не даёт, ни рук не
  # занимает — иначе снятый фит владения отбирал бы заодно и щит.
  defp off_hand_refusals(_build, _ruleset, %{occupies_off_hand?: false}), do: []

  defp off_hand_refusals(build, ruleset, %{occupies_off_hand?: true}) do
    main_hand_refusals(build, ruleset) ++ off_hand_weapon_refusals(build, ruleset)
  end

  defp main_hand_refusals(build, ruleset) do
    case GearWeapon.held(build, ruleset, :main) do
      nil ->
        []

      weapon ->
        if Wield.both_hands?(build, weapon, ruleset), do: [{:two_handed_weapon, weapon}], else: []
    end
  end

  # 🔴 И ВТОРАЯ рука — но занятая не хватом, а вторым оружием (задача 3.132,
  # решение Dan 28.08.2026: щит и второе оружие одновременно взять нельзя).
  #
  # ⚠ Форма отказа СВОЯ, а не общая с двуручным оружием выше, и это требование,
  # а не вкус: «занята двуручным оружием» и «занята вторым оружием» — разные
  # факты об одной руке, и игрок по ним идёт менять разные вещи. Одна фраза
  # на два факта отправила бы половину из них не туда.
  defp off_hand_weapon_refusals(build, ruleset) do
    case GearWeapon.held(build, ruleset, :off) do
      nil -> []
      weapon -> [{:off_hand_weapon, weapon}]
    end
  end
end
