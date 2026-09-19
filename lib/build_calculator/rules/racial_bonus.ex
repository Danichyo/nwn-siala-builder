defmodule BuildCalculator.Rules.RacialBonus do
  @moduledoc """
  The shard's own racial bonus — the one thing about a Siala race that is not
  vanilla.

  Siala did not translate the races, it rebuilt them (CLAUDE.md §4), and the
  mechanical part of that is a single bonus per race, mirroring the custom weapon
  system: a Half-elf attacks better, a Gnome carries shield armour class, a Human
  is better at Discipline, a Dwarf absorbs elemental damage, a Half-orc hits
  harder. Two races have none at all.

  ## Why this was declared out of scope, and what changed

  ⚠ On 01.08.2026 the whole feature was declared `out_of_scope`
  (`priv/rules/siala_41/races.json` → `level_scaling._decision`, which records
  all three decisions — `history` there is an array, oldest first). The blocker
  was real and is still there:

  > «На первых уровнях персонажа бонус от расы невелик, но постепенно с набором
  > уровней он увеличивается. Бонус становится максимальным на 40 уровне.»
  > «Ниже все бонусы рас приведены для персонажей 40-го уровня.»

  The bonus **grows with character level** and every number on the page is stated
  for one level. There is no table and no formula on any page; the one word that
  describes the shape ("пропорционально") sits in a descriptive paragraph with
  not a single level→number pair to check it against. Interpolating linearly
  would be inventing a game number, which is the one thing forbidden outright
  (CLAUDE.md §3).

  Task 3.12 (Dan, 03.08.2026) resolves it without the formula: count the number
  exactly where it is true, and say so where it is not.

    * **At and above the level the numbers are stated for** — the wiki says the
      bonus is already maximal there, so the level cap's extra level carries the
      same number rather than a bigger one. Both facts are read from the data
      (`stated_for_level`, `max_at_level`); neither is a literal here, and
      `counted_at?/2` needs both to hold. A data change that breaks the premise
      stops the counting instead of guessing.
    * **Below it** — nothing is counted, and `gaps/2` says why by name. Silently
      leaving out a bonus the game gives is the same lie as inventing one; it
      just fails in the direction nobody complains about.

  ## 🔴 The growth function arrived, and it is counted (task 3.181, 11.09.2026)

  ⚠ **Everything above is still true — of a ruleset that carries no growth
  table.** Since 11.09.2026 `siala_41` carries one, and the bonus is counted at
  **every** level; `variants_at/3` is what answers, and `counted_at?/2` is the
  fallback for a snapshot that says nothing about growth.

  It came from neither wiki and from no measurement: the shard's administration
  sent a reading of their own **server scripts**, which carries the step table
  `GetWeaponBonus` (1–7 → 1, 8–16 → 2, 17–23 → 3, 24–31 → 4, 32–39 → 5, 40+ →
  6) and the arithmetic of every executor. Dan's decision of that day is to
  count by it.

  ⚠ **The decision that closed the search is not reversed — its premise was.**
  Dan refused the measurements (`GAME_CHECKS.md` Q2: «промежуточные цифры
  не важны… могу ошибиться или перепутать»), and the table needed none.

  ⚠ **And it is not our formula.** The table, the unit each shape starts from
  and every multiplier live in `systems.json` → `bonuses_level_tiers`; this
  module only interprets them. One point below the cap **was** measured — Dan,
  11.09.2026, `GAME_CHECKS.md` AM1: a Half-elf Barbarian 17 with a sling gets
  `+4` from his race and `+4` from the weapon group, and that number killed
  three competing readings of the arithmetic.

  ## Two of the four numbers, not one

  Every record states four: `base`, `sagra_warrior`, `racial_weapon` and both
  together. Which one is counted is decided by **what the build says about
  itself**, and the line runs where the model's knowledge does:

    * **`base`** — always available, the floor;
    * **`sagra_warrior`** — a build all of whose levels come from the shard's
      four warrior classes. That is decidable from `build.levels` alone
      (`BuildCalculator.Rules.ClassGroups`), so since 08.08.2026 it is **counted**
      — Dan: «сагровик получит больше бонусов, чем несагровик». Until then only
      `base` was, and a Half-elf warrior of Sagra was shown +6 where the game
      gives +9;
    * **`racial_weapon` and both together** — never **counted here**, and since
      15.08.2026 that is a statement about *this module*, not about the model.

  ⚠ **Dan measured what those two numbers are, and they are sums.** Half-elf
  warrior of Sagra at 40, three readings of one character: nothing in hand → 29,
  sword +5 → 43 (`30 + (−1) + 5 + `**`9`**), longbow +5 → 62
  (`30 + 9 + 5 + `**`9`**` + `**`9`**). The last `9` is the *weapon group* bonus
  of the shard's weapon system, a separate term with its own source — and
  `racial_weapon: 12` / `…_and_sagra_warrior: 18` are exactly this bonus plus
  that one.

  So these two variants need no rule of their own and must not get one: once the
  weapon-group term exists (AGENT_QUEUE 3.35) their numbers arrive as arithmetic.
  Adding a third reading here would double the bonus for every Half-elf with a bow.

  🔴 **И у удвоения есть ВТОРОЕ условие, измеренное 12.09.2026 (задача 3.198):
  в другой руке не должно быть оружия ДРУГОЙ категории.** Замер `AN1`: Карлик
  15-го уровня показывает AC 18 с кинжалом и **15** с дробящим во второй руке.
  Считает это `Rules.RacialWeapon`, а гасит лишний терм `Rules.WeaponTypeBonus`
  — здесь число не меняется вовсе, но состояние отдаётся полем `weapon_match`:
  справка обязана назвать, почему AC упал от предмета в левой руке.

  ⚠ **Записанный `conflict` про ОБЕ руки
  (`activation.both_weapons_must_be_racial`) этим и закрылся** — оба чтения вики
  опровергнуты в строгой форме: «Расы» ограничивали правило Могучими людьми
  (замер снят на Карлике), «Система оружия» требовала расовыми ОБА оружия
  (с одним клинком и пустой второй рукой удвоение работает).

  ## What switches the bonus on at all

  ⚠ **Not the level — a weapon in the character's hands.** The page has said so
  since 01.08.2026 («Эти бонусы накладываются на персонажа как эффект в момент
  взятия оружия в руку»), the sentence sat in `activation` as prose, nothing read
  it, and the core handed the bonus over to a character holding nothing. Dan's
  naked reading — 29 in game against our 38 — is what caught it. See
  `activated?/3`; the rule and its two exceptions are data.

  Which condition belongs to which number is read from the data, not decided
  here: `ruleset.racial_bonuses.variant_conditions` says what each number is
  stated for and `conditions` says which of those the core can decide. So a
  variant whose condition is undecidable stays out of the arithmetic by itself,
  and no variant is named in this module.

  All four numbers are handed over whole in `variants` regardless, so the
  interface can print the uncounted ones beside the counted one. A build that
  would really get +18 shown +9 with no explanation is a wrong number; shown +9
  with «а с подходящим оружием вместе +18» beside it is an honest floor.

  ⚠ **Since 11.09.2026 those four numbers are the ones of THIS BUILD'S LEVEL**,
  not the ones written in the file. Before the growth table the two coincided
  by construction — the bonus was counted only where the numbers were stated —
  and a caption could read either. It cannot any more: a level-17 build gets
  `+4`, and printing the file's `+9` beside its own number would promise twice
  what the game gives. The web layer reads them off this record for exactly
  that reason (`Labels.racial_bonus_note/2`).

  ## Nothing here names a race, a skill or an armour class type

  Which race has which bonus, where it lands, which ceiling it counts towards and
  what the four numbers are is data (`ruleset.racial_bonuses`, read by
  `BuildCalculator.Data.Loader`). What this module decides is only which *shapes*
  of bonus reach a number at all — the three below.

  ⚠ A shape outside that list produces **no caveat either** since 16.08.2026
  (Dan's decision, `gaps/2`): the calculator shows no damage and no resistance, so
  a bonus to them is not a hole in our answer. Until then it was named, and the
  weapon half of the same shard system was silent about the same two shapes.
  """

  alias BuildCalculator.Rules.{Build, ClassGroups, GearWeapon, RacialWeapon}

  # The shapes the core turns into a number, and where each lands.
  #
  # 🔴 **`:damage_resistance` joined on 18.09.2026 (задача 3.210), and that is a
  # receiver arriving rather than a rule changing.** Until then the list carried
  # three shapes and this comment said damage resistance was not on it «because
  # no number in the calculator shows it» — true of its own day and false the
  # moment the «Резисты» section got a number of its own
  # (`Rules.Resistances`, `DerivedStats.resistances`). Гном's 12/- is now
  # counted, amplified by mini-sets and clipped by the executor's own ceiling,
  # exactly like the Карлик's shield armour class.
  #
  # ⚠ **`:damage` is still out, and still for the original reason**: the build
  # has no damage line at all, so Могучий человек's bonus has nowhere to go and
  # `gaps/2` says nothing about it (Dan, 16.08.2026).
  #
  # ⚠ Membership is decided here and nowhere else. The loader's own list of
  # shapes is wider on purpose — it guards against a typo in the data, which
  # would otherwise arrive as an unknown shape and count for nothing.
  @modelled_kinds [:attack_bonus, :shield_ac, :skill_bonus, :damage_resistance]

  @typedoc """
  What a build's race contributes, and everything the interface needs to caption it.

    * `race` / `kind` — whose bonus and of what shape
    * `skill` — for a `skill_bonus`, which skill; `nil` otherwise
    * `ac_type` — for a `shield_ac`, the armour class type it lands on
    * `variants` — all four numbers **at this build's level**, for the reference
      beside the counted one. ⚠ Since 11.09.2026 that is not the same as «the
      numbers the page states»: with the growth table they coincide only at
      `stated_for_level`, and a caption reading the file instead of this field
      would promise a level-17 build twice what it gets
    * `stated_for_level` — the character level the **file's** numbers are
      written for. Still the provenance of the record, and still what the
      growth formula is checked against by the loader
    * `counted` — what the core actually adds, or `nil` when it adds nothing
    * `variant` — which of the four `counted` came from, `nil` when none. ⚠ Not
      decoration: this is what the note beside the number has to be worded from,
      since «посчитан базовый» and «посчитан вариант сагровика» say different
      things. ⚠ Since 25.08.2026 that note is **not** a gap — a counted bonus is
      an answer, not a hole, and `gaps/2` says why
    * `inactive?` — the number **is** known at this level and was still not
      counted, because nothing switches the bonus on (see `activated?/3`). A
      third state, distinct from both «посчитано» and «уровень мал», and it needs
      its own sentence: the player is one weapon away from the bonus, not one
      level away from knowing it
    * `modelled?` — whether the shape reaches any number at all. ⚠ Since
      16.08.2026 it no longer produces a caveat when false (`gaps/2`); it is
      still what keeps the number out of the arithmetic, and still the field a
      future damage line would switch on
    * `cap` — the ceiling key the page says it counts towards, or `nil`
    * `weapon_match` — совпало ли оружие в руках с расой и цело ли совпадение
      (`Rules.RacialWeapon.match/2`, задача 3.198). ⚠ Само ЧИСЛО этой записи
      от него не зависит: удвоение у нас — это сумма расового терма и терма
      за тип оружия, и гасится при `{:broken, _}` второй из них
      (`Rules.WeaponTypeBonus`). Здесь поле живёт потому, что справка обязана
      сказать игроку, почему AC упал на три очка от дубины в левой руке
  """
  @type t :: %{
          race: atom(),
          kind: atom(),
          skill: atom() | nil,
          ac_type: atom() | nil,
          executor: atom() | nil,
          variants: %{atom() => integer()},
          stated_for_level: pos_integer() | nil,
          counted: integer() | nil,
          variant: atom() | nil,
          inactive?: boolean(),
          modelled?: boolean(),
          cap: atom() | nil,
          weapon_match: RacialWeapon.match()
        }

  @doc """
  The build's racial bonus, or `nil` when its race has none at all.

  `nil` means exactly that — Гоблин and Тёмный эльф have no such bonus, their
  page says so in one sentence, and a build of theirs must carry no caveat about
  it either. Everything else comes back as a record whose `counted` says whether
  the number reached the sheet.
  """
  @spec of(Build.t(), map()) :: t() | nil
  def of(%Build{race: nil}, _ruleset), do: nil

  def of(%Build{race: race} = build, ruleset) do
    with %{} = layer <- Map.get(ruleset, :racial_bonuses),
         %{} = record <- Map.get(layer.by_race, race) do
      modelled? = record.kind in @modelled_kinds
      variants = variants_at(layer, record, Build.character_level(build))
      variant = counted_variant(build, ruleset, layer)
      amount = Map.get(variants, variant)
      known? = modelled? and is_integer(amount)
      active? = activated?(build, ruleset, layer)
      counted? = known? and active?

      %{
        race: record.race,
        kind: record.kind,
        skill: record.skill,
        ac_type: record.ac_type,
        # Какой скрипт шарда накладывает этот бонус (задача 3.181). Отдаётся
        # наружу с 3.184: усиление мини-сетами и внутренний кап принадлежат
        # ИСПОЛНИТЕЛЮ, а не виду бонуса, и сложить наш терм с оружейным можно
        # только там, где исполнитель у обоих один (`Rules.MiniSets`).
        executor: Map.get(record, :executor),
        variants: variants,
        stated_for_level: layer.stated_for_level,
        counted: if(counted?, do: amount, else: nil),
        variant: if(counted?, do: variant, else: nil),
        inactive?: known? and not active?,
        modelled?: modelled?,
        cap: record.counts_toward_cap,
        weapon_match: RacialWeapon.match(build, ruleset)
      }
    else
      _ -> nil
    end
  end

  @doc """
  What the racial bonus adds to the attack bonus — `0` unless the race's bonus is
  one and the level is one it is known at.

  ⚠ **Before the ceiling, not after.** The Half-elf's page says the bonus «входит
  в кап атаки +20», so it is one of the things the ceiling is over, not a bonus
  on top of it. The caller offers it to `Rules.Caps` together with the gear
  bonus, one clip over both — clipping each separately is how the saves came to
  carry +40 (CLAUDE.md §9).
  """
  @spec attack_bonus(Build.t(), map()) :: integer()
  def attack_bonus(%Build{} = build, ruleset), do: amount(build, ruleset, :attack_bonus)

  @doc """
  What it adds to armour class, of which type and under which shape — `nil` when
  it adds nothing.

  `{kind, type, ac}`. The type matters as much as the number: it is a **shield**
  bonus, which the page says stacks with a shield's base armour class and not
  with a shield's bonus, so it has to meet the number the player typed under
  "Вещи" as a same-type collision rather than sail past it (`Rules.ArmorClass`).

  ⚠ And the **kind** is handed over for exactly that collision (task 3.91). The
  shard's shield bonus is the one thing on a build that does not simply add to a
  typed number of its own type — «раса карлика… перекрывает бонус щита (не базу
  щита(1/2/3), а именно бонус)» — while a feat's bonus does add («АЦ с фитов
  всегда стакаются все», both Dan, 25.08.2026). Which shapes are the exception
  is stated in the ruleset (`gear.ac_types.same_type.own_vs_gear_by_kind`), so
  this module hands over the word the data keys that rule by and decides
  nothing; `Rules.ArmorClass` never learns the word `shield_ac`.
  """
  @spec armor_class(Build.t(), map()) :: {atom(), atom() | nil, integer()} | nil
  def armor_class(%Build{} = build, ruleset) do
    case of(build, ruleset) do
      %{kind: :shield_ac = kind, counted: ac, ac_type: type} when is_integer(ac) and ac != 0 ->
        {kind, type, ac}

      _ ->
        nil
    end
  end

  @doc """
  What it adds to `skill` — `0` for every skill but the one the race's page names.

  Like the attack bonus, this is offered **before** the ceiling: the Human's page
  says «Этот бонус входит в кап навыка +50», so it is inside that ceiling and not
  above it.
  """
  @spec skill_bonus(Build.t(), map(), atom()) :: integer()
  def skill_bonus(%Build{} = build, ruleset, skill) do
    case of(build, ruleset) do
      %{kind: :skill_bonus, skill: ^skill, counted: bonus} when is_integer(bonus) -> bonus
      _ -> 0
    end
  end

  @doc """
  Whether the ceiling `stat` is one this build's racial bonus counts towards.

  Answered off the data (`counts_toward_cap`) rather than off the shape, so a
  bonus is never clipped by a ceiling its own page does not claim.
  """
  @spec counts_toward_cap?(Build.t(), map(), atom()) :: boolean()
  def counts_toward_cap?(%Build{} = build, ruleset, stat) do
    match?(%{cap: ^stat}, of(build, ruleset))
  end

  @doc """
  Whether the numbers stated in the data are true at `level`.

  Two facts, and neither alone is enough: they are stated **for** one level, and
  the bonus stops growing **at** another. Counting is allowed only at or above
  the stated level and only because the bonus is already maximal there — which is
  what makes the shard's extra level past the vanilla cap carry the same number
  rather than a bigger one.

  A ruleset that states one fact and not the other counts nothing. That is the
  point: if somebody transcribes numbers for level 30 while the maximum is still
  at 40, this stops agreeing rather than quietly extending them upwards.

  ⚠ **Since 11.09.2026 (task 3.181) this is the FALLBACK, not the gate.** A
  ruleset carrying the shard's tier table answers «сколько это на этом уровне»
  by `variants_at/3` instead, at every level; this clause is what a ruleset
  **without** that table falls back to, and it is the same answer it gave
  before. The default is deliberately the silent-below-the-stated-level one: a
  snapshot that says nothing about growth may not start guessing it.
  """
  @spec counted_at?(non_neg_integer(), map()) :: boolean()
  def counted_at?(level, %{stated_for_level: stated, max_at_level: max})
      when is_integer(stated) and is_integer(max),
      do: level >= stated and stated >= max

  def counted_at?(_level, _layer), do: false

  @doc """
  What each of the record's numbers is worth **at `level`** — the shard's growth
  rule, and the one place it lives for both halves of the system.

  ## Why this exists at all, and why it is not a formula of ours

  Every number in `siala_41/races.json` and in the weapon system's rows is
  stated for one character level, and the bonus grows below it. For a year that
  growth function was declared undiscoverable: no page on either wiki names it,
  and Dan closed the search by decision (`GAME_CHECKS.md` Q2, 15.08.2026). The
  shard's administration then sent a reading of their own **server scripts**,
  and it carries the table. Dan's decision of 11.09.2026 is to count by it.

  ⚠ **Nothing here is a number.** The ladder of tiers, the multiplier each
  variant takes, the unit each shape starts from and the arithmetic of every
  executor come from `layer.scaling`, assembled by
  `BuildCalculator.Data.Loader.Races` out of `systems.json` →
  `bonuses_level_tiers`. This module knows only the *grammar*: multiply by a
  fraction, add, apply N times — in that order.

  ## The grammar, and why it is a grammar rather than one formula

  The second document («Mini-set Scaling System», 11.09.2026) traced all eight
  executors separately and says it outright: *«there is no single formula shared
  by all eight»*. Two of them differ in ways our own numbers depend on — the
  damage one doubles and adds 2 on the racial branch, the shield one applies its
  half-again unconditionally — so a single parameterised formula would have to
  invent the difference away. Hence a table of executors in the data and an
  interpreter here.

  ## Three answers, not two

    * an **integer** — the value at this level;
    * `nil` where the page states no number at all (a halberd's own sonic damage
      says which shape and not how much);
    * `nil` where the level is below the ladder, or the ruleset carries no table
      and the level is below the one the numbers are stated for. The caller
      turns that into the gap naming the level, exactly as before.

  ⚠ A variant naming a step its executor does not describe also comes back
  `nil` rather than silently skipping the step: a skipped multiplier is a
  number **smaller** than the game's, and the whole point of the ladder is that
  such a mistake is invisible in the answer.
  """
  @spec variants_at(map(), map(), non_neg_integer()) :: %{atom() => integer() | nil}
  def variants_at(layer, record, level) do
    Map.new(record.variants, fn {variant, stated} ->
      {variant, value_at(layer, record, variant, stated, level)}
    end)
  end

  # A page that states no number for this variant has none at any level either.
  defp value_at(_layer, _record, _variant, nil, _level), do: nil

  defp value_at(layer, record, variant, stated, level) do
    with %{} = scaling <- Map.get(layer, :scaling),
         executor when not is_nil(executor) <- Map.get(record, :executor),
         %{} = spec <- Map.get(scaling.executors, executor),
         steps when is_list(steps) <- Map.get(scaling.variant_multipliers, variant) do
      evaluate(spec, steps, stated, level, layer, scaling)
    else
      _no_table -> stated_at(layer, level, stated)
    end
  end

  # The value grows straight with the character level and is whole at the level
  # the number is written for. One executor works this way — the armour class
  # **override** of the two-bladed sword, whose page says the bonus «не
  # модифицируется… и не улучшается минисетами» and whose script bypasses every
  # multiplier. Above the stated level it stops, like everything else here.
  defp evaluate(%{shape: :linear}, _steps, stated, level, %{stated_for_level: full}, _scaling)
       when is_integer(full) and full > 0,
       do: div(min(level, full) * stated, full)

  defp evaluate(%{shape: :tiered} = spec, steps, stated, level, layer, scaling) do
    with tier when is_integer(tier) <- tier(scaling, level),
         described when is_list(described) <- described_steps(spec, steps) do
      Enum.reduce([spec.always | described], tier * spec.unit, &apply_step(&2, &1))
    else
      _ -> stated_at(layer, level, stated)
    end
  end

  defp evaluate(_spec, _steps, stated, level, layer, _scaling),
    do: stated_at(layer, level, stated)

  # All of them or none: a step the executor does not describe is not a step
  # worth zero, it is an arithmetic this data cannot express.
  defp described_steps(spec, steps) do
    Enum.reduce_while(steps, [], fn step, acc ->
      case Map.fetch(spec.steps, step) do
        {:ok, described} -> {:cont, acc ++ [described]}
        :error -> {:halt, nil}
      end
    end)
  end

  defp tier(%{tiers: tiers}, level) do
    Enum.find_value(tiers, fn {from, to, tier} ->
      level >= from and (is_nil(to) or level <= to) and tier
    end)
  end

  # ⚠ Multiply, then add, then repeat — the order the data is written in and the
  # order the scripts run: the racial branch of the damage executor is
  # `2B + 2`, applied as two damage types, and any other order gives a different
  # number. Integer division truncates downwards, which is what NWScript does
  # and what Dan measured (`GAME_CHECKS.md` AM1).
  defp apply_step(value, nil), do: value

  defp apply_step(value, step) do
    value
    |> multiply(step.multiply)
    |> plus(step.add)
    |> repeat(step.applications)
  end

  defp multiply(value, nil), do: value
  defp multiply(value, {numerator, denominator}), do: div(value * numerator, denominator)

  defp plus(value, nil), do: value
  defp plus(value, addend), do: value + addend

  defp repeat(value, nil), do: value
  defp repeat(value, times), do: value * times

  # The pre-3.181 answer, and still the right one for a ruleset that says
  # nothing about growth: the number where it is stated, nothing below it.
  defp stated_at(layer, level, stated), do: if(counted_at?(level, layer), do: stated)

  @doc """
  What this build's racial bonus does not say for itself.

  Exactly one of two, never both, because they are two answers to one question
  and stacking them would read as two separate faults:

    * `{:missing_data, {:racial_bonus_level, race}}` — the shape *is* modelled and
      the character is below the level the numbers are stated for, so nothing was
      counted. This is the honest half of the 01.08 blocker: the bonus is there in
      the game and its size is unknown.
    * `{:assumed, {:racial_bonus_variant, race, nil}}` — the number **is** known
      at this level and the bonus was still not counted, because nothing switched
      it on (`inactive?`). The one thing the caption must say is that a weapon in
      hand is what is missing — not a level and not a source: the player is one
      movement away from the bonus.

  ## 🔴 A counted variant is NOT a gap any more (task 3.102, 25.08.2026)

  ⚠ Until 25.08.2026 this function had a third clause: a bonus that **was**
  counted came back as `{:assumed, {:racial_bonus_variant, race, variant}}` with
  the variant named. Two of the three sentences that tuple carried described a
  **success** — «посчитан базовый +6», «посчитан вариант сагровика +9» — and
  the interface prints every gap of a build under «ядро не смогло посчитать N».
  The core **could**, and the sentence said so itself.

  Dan's decision that day splits the tuple by meaning rather than deletes it:
  «не посчитан — возьми оружие» stays here, «посчитан такой-то» moves next to
  the number it landed in. The web layer routes it by `kind`
  (`BuildCalculatorWeb.Builder.Summary.racial_bonus_note/2`) and words it with
  the very same sentence the gap used to carry
  (`BuildCalculatorWeb.Builder.Labels.racial_bonus_note/2` — the two share one
  private formatter, so there is no second wording to drift).

  ⚠ **The form stays registered and the variant stays in the record.** The
  `nil` case above produces the very same form (`Rules.Vocabulary.form/1` reads
  the head and the subject atom, not the third element), and `variant` is what
  the note beside the number is worded from — «посчитан базовый, сагровиком билд
  не является» admits something the sagra sentence does not. Nothing was
  deleted; one reader moved.

  ⚠ **This is not the same statement `Rules.WeaponTypeBonus` makes**, so the two
  halves of the shard's one system did not drift apart here — they were never
  saying the same thing. Its `{:assumed, {:weapon_type_bonus_variant, …}}` fires
  only on a record whose `assumed_variants` names the variant, i.e. where reading
  «одинаковый для всех билдов» as covering a warrior of Sagra would be **ours**.
  That is an assumption about a *reading*, not an announcement of arithmetic.
  ⚠ Carriers of it in today's data: **none** — every `assumed_variants` in
  `ruleset.weapon_type_bonuses` is empty (checked by walking the layer,
  25.08.2026). Unchanged by this task and untouched by it, named here only so
  the next reader does not "fix" the weapon half by symmetry with this one.

  ⚠ A race with no such bonus at all gets `[]`, not a caveat. Гоблин and Тёмный
  эльф have one sentence about shamanism on their pages and nothing else, so a
  caveat there would be a warning about something that is not happening —
  the shape of noise `Rules.ArmorClass`'s `gear_base/1` avoids for the same reason.

  ## A shape with no receiver gets `[]` too, and that is a decision

  ⚠ Гном's damage resistance and Могучий человек's damage used to come back as
  `{:not_modelled, {:racial_bonus, race, kind}}` — the number is known at 40 and
  there is nowhere in a build to put it. Since 16.08.2026 they come back as `[]`,
  by Dan's word: «если речь о поглотах, то мы просто ничего не пишем. Потом если
  захотим добавить поглоты — добавим все условия, а пока мы это не показываем,
  оговорку игнорируем, не показываем лишней информации».

  That is CLAUDE.md §9's rule, the one that took most of the 89 class facts off
  the screen (19 carry a receiver of ours): **a gap is a hole in our answer, not
  in our knowledge.** The calculator gives no answer about damage or resistance,
  so it has no hole there, exactly as it says nothing about the damage a build's
  strength adds.

  ⚠ It also ends a disagreement between two halves of one shard system.
  `Rules.WeaponTypeBonus` is silent about the very same shapes — an axe's
  resistance, a warhammer's sonic damage — and until this change the racial half
  spoke about them. One statement, two answers.

  ⚠ The `%{modelled?: false}` clause below returns `[]` **explicitly** rather
  than being deleted, and that is not style: such a record also carries
  `counted: nil`, so dropping the clause would hand these two races the level
  caveat instead of silence — and their bonus is not of unknown size, it is of a
  shape we do not carry. `modelled?` itself stays in the record: `of/2` reads it
  to keep the number out of the arithmetic, and it is what any future receiver
  would switch on.
  """
  @spec gaps(Build.t(), map()) :: [tuple()]
  def gaps(%Build{} = build, ruleset) do
    case of(build, ruleset) do
      nil -> []
      %{modelled?: false} -> []
      %{inactive?: true} = bonus -> [{:assumed, {:racial_bonus_variant, bonus.race, nil}}]
      %{counted: nil} = bonus -> [{:missing_data, {:racial_bonus_level, bonus.race}}]
      # Посчитано — и потому молчим. См. 🔴 выше. Единственное исключение:
      # удвоение зависит от категории оружия в другой руке, а у одного оружия
      # справочника категории не называет ни один источник (задача 3.198).
      # Тогда число посчитано ПО СТАРОМУ правилу, и об этом надо сказать:
      # молча оставить удвоение — завысить, молча снять — занизить.
      %{weapon_match: {:unknown, weapon}} -> [{:missing_data, {:weapon_category, weapon}}]
      _counted -> []
    end
  end

  @doc """
  Whether anything switched the bonus on.

  ⚠ **The rule was in the data from the first day and read by nobody.**
  `siala_41/races.json` → `activation` has said since 01.08.2026 that the bonus
  is «эффект в момент взятия оружия в руку», and the core handed it over
  regardless of what the build held; Dan measured the gap on 15.08.2026 — a naked
  Half-elf warrior of Sagra at 40 shows attack bonus 29 in game against our 38.
  The same shape of bug as `Zen archery`, which carried a rule that did nothing:
  prose in a data file is not a rule until something reads it.

  What counts as switching it on is data, not a list here: `switched_on_by_weapon?`
  says whether a weapon is needed at all, `non_activating` names the weapons that
  are held and still do not switch it on. A ruleset that states neither activates
  always, which is both the old behaviour and the right answer for a layer that
  never made the claim.

  ⚠ **«Any weapon», not «the race's own weapon»** — and that half is measured
  rather than assumed: the same character with a sword showed 43 = 30 + (−1) + 5
  + **9**, so the race's own number arrives with a weapon it does not mirror. What
  the matching weapon adds on top is the *weapon group* bonus, a separate term
  and a separate task (AGENT_QUEUE 3.35).
  """
  @spec activated?(Build.t(), map(), map()) :: boolean()
  def activated?(%Build{} = build, ruleset, layer) do
    case Map.get(layer, :activation) do
      %{switched_on_by_weapon?: true} = activation ->
        case GearWeapon.held(build, ruleset) do
          nil -> false
          weapon_id -> not MapSet.member?(activation.non_activating, weapon_id)
        end

      _no_rule ->
        true
    end
  end

  # Which of the four numbers this build gets, decided by which of the conditions
  # they are stated for actually hold. Both halves come from the data
  # (`variant_conditions` says what a number is for, `conditions` says which of
  # those the core can decide), so no variant and no group is named here.
  #
  # The most specific satisfiable one wins: `base` names no condition, so anybody
  # qualifies for it, and a member of the sagra group qualifies for both. ⚠ A tie
  # — two different satisfied conditions of equal length — cannot happen with
  # today's data, where exactly one condition resolves at all; the sort keeps the
  # answer deterministic if it ever can, but **which number the game gives then
  # is not something this rule may decide** (`# TODO: verify` — it would need a
  # source, not a convention).
  defp counted_variant(build, ruleset, layer) do
    layer
    |> Map.get(:variant_conditions, %{})
    |> Enum.filter(fn {_variant, conditions} ->
      Enum.all?(conditions, &satisfied?(build, ruleset, layer, &1))
    end)
    |> Enum.sort_by(fn {variant, conditions} -> {length(conditions), variant} end)
    |> List.last()
    |> case do
      {variant, _conditions} -> variant
      # A ruleset that states no variants at all: `Map.get(variants, nil)` is
      # `nil`, which is the same "nothing counted" every other absence produces.
      nil -> nil
    end
  end

  # A condition holds only if the data says what it *is*. An unresolved name —
  # `racial_weapon`, whose own definition is prose and whose «both hands» half is a
  # stated conflict (see the moduledoc) — is not false-because-unmet but
  # undecidable, and either way its number stays out of the arithmetic; that is the
  # whole reason the two maps are separate.
  defp satisfied?(build, ruleset, layer, condition) do
    case Map.get(Map.get(layer, :conditions, %{}), condition) do
      {:class_group, id} -> ClassGroups.member?(build, ruleset, id)
      _unknown -> false
    end
  end

  defp amount(build, ruleset, kind) do
    case of(build, ruleset) do
      %{kind: ^kind, counted: bonus} when is_integer(bonus) -> bonus
      _ -> 0
    end
  end
end
