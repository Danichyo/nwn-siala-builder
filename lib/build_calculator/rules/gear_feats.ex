defmodule BuildCalculator.Rules.GearFeats do
  @moduledoc """
  Feats that come from an **item** — a satisfied requirement, not a number.

  The build the shard assembles and this calculator used to refuse (решение Dan,
  02.08.2026): the feat is nowhere in the ladder, it sits on a worn item, and in
  game it works. `Alertness` and `Stealthy` arrive that way often, and so does
  the Weapon Master's `Weapon focus` chain — which is why the refusal was not
  academic. `Harper scout` wants `Alertness` and `Iron will`, `Shifter` wants
  `Alertness`, `Weapon master` and `Champion of Torm` want `Weapon focus`,
  `Weapon specialization` wants it too: with the feat on an amulet instead of in
  a slot, every one of those came back `{:requires_feat, …}`.

  So the declaration is its own thing, kept beside the numbers the player types
  (`Rules.Gear`, `gear.feats`) because it belongs to the same layer — what is
  worn — and travels in the shared link with the rest of the build. It is **not**
  the armoury (task 3.5): there are no items here, only a list of feats the
  player says an item lends.

  ## Four decisions, and the argument for each

  ### It occupies no slot

  Dan's word, and the model follows it literally: the list lives in `Gear`, never
  in `build.feats`, so `Rules.FeatSlots` cannot see it. A declared feat adds no
  row to the progression column, spends no `general` / `class_bonus` slot, and
  changes no slot count anywhere.

  ### It satisfies a **class's** requirement, and its **effect counts**

  Both through one mechanism: the declaration joins `Build.feats_owned/3`, which
  is what `Rules.Prereqs` checks a class's `requires_feat` against *and* what the
  six markup readers price a bonus off. Dan's word again, and in his own example
  (09.08.2026): «да, пускай эффект фита с вещи учитывается в числах. Ведь если
  фит есть, допустим тафнес, то и HP будут увеличены».

  ### It does **not** satisfy another FEAT's requirement

  Measured 14.08.2026 (`GAME_CHECKS.md` H7), and it is a narrowing of the line
  above rather than an argument with it:

  > «фит с вещи не позволит взять другой фит, требующий тот фит, который мы
  > взяли с вещи. Пример, мы взяли expertise с вещи, improve expertise
  > не появится в выборке доступных фитов. А вот сам expertise там будет
  > (т.е. полный игнор фитов с вещи). Но вот КЛАСС можно взять…»

  Three sentences, three different answers, and the model owes all three: the
  class opens, the dependent feat does not, and the feat itself stays pickable.
  `Rules.Prereqs` splits the first two off `requirement_of`; the third was
  already right and is `Build.feats_permanent/3`'s doing.

  ⚠ The **effect** is untouched by this. A worn `Toughness` is still hit points,
  a worn `Iron will` is still a save — only the borrowed feat's standing as a
  stepping stone to another feat is gone.

  So nothing here counts anything: `Toughness` off an amulet reaches hit points
  because `Rules.FeatBonuses` already counts the feats the character owns, and
  `Alertness` reaches Spot because `Rules.Skills.feat_bonuses/3` does. The same
  goes for the honesty machinery in the other direction — a worn feat whose bonus
  the model refuses to work out arrives in `stats.gaps` through the existing
  `unmodelled/3` twins, with no new form of gap.

  ⚠ **The double counting to worry about is narrow, and it is named rather than
  prevented.** The player types three things under «Вещи»: abilities, AC by type,
  a bonus to all three saves. There is no box for hit points, skills or the
  attack roll, so `Toughness`, `Alertness` and `Epic prowess` cannot collide with
  anything. Where a box does exist the protection is that **every term is a named
  row of its own** (tasks 3.1/3.6/3.16, 1.12a, 1.12b): a declared `Iron will`
  shows as `Iron will +2` beside `вещи +2`, so a player who typed the same bonus
  twice sees it twice instead of being quietly overcharged — and nothing is
  hidden or understated to achieve that. Armour class goes one better, and since
  task 3.39 it does not merely name the collision but **resolves** it: a worn
  `Armor skin` and a typed `natural` do not add up, the larger of the two counts
  (`Rules.ArmorClass.geared/3`), and the interface is told which side did not
  land. ⚠ Here stood «`collisions/2` reports `{:not_modelled,
  :ac_same_type_stacking}`» — that caveat is gone with the rule that replaced it.

  ⚠ **A feat that changes a formula rather than adding to it is covered too**,
  since 14.08.2026 — `Weapon finesse` moves the attack roll onto dexterity
  (CLAUDE.md §6, «фиты бывают трёх видов»). This paragraph used to say the
  opposite and called the question "a separate one, not this task's to answer";
  it was answered on its own and the answer is the same as everywhere else in
  this module: `Rules.Attack.ability/5` now reads `Build.feats_owned/3`, so a
  Finesse off an item switches the roll like a picked one. Measured before the
  fix: fighter 10, STR 10, DEX 18, Finesse on an item — AB 10 instead of 14.

  ⚠ `Zen archery` is **not** covered, and this is not about where the feat came
  from: `ruleset.attack_ability.rules` carries one rule and it is Finesse's. The
  feat does nothing in the model by any route (`vanilla/feat_attack_bonuses.json`
  → `_open_questions.zen_archery_rule_missing`).

  ### It carries a parameter — and this section used to say the opposite

  A slot may hold `{feat_id, choice}`, and since task 3.97 so may a declaration.
  Решение Dan, 25.08.2026: «Подобный фит не может существовать без привязки
  к конкретному выбору. skill_focus всегда привязывается к одному из навыков
  и дает 3 к данному конкретному навыку, а weapon focus привязывается
  к конкретному оружию и дает с ним +1 АБ».

  ⚠ The old rule was right for its own time, and its argument is kept here
  because it is what shows the ground moving rather than the rule wobbling. It
  rested on two claims, and both have since stopped being true:

    * *«`Weapon focus`'s domain is `weapon`, which has no dictionary and will
      not have one before the armoury, so there is nothing to record even in
      principle»* — task 3.5 gave `weapon` a dictionary of 47 (part A) and put a
      weapon in the character's hands (part B);
    * *«nothing is lost»* — task 3.92 taught the core to count `Skill focus`'s
      +3 and `Epic skill focus`'s +10, so a declaration that cannot name the
      skill silently loses thirteen points off the row a player reads first.

  ⚠ **A declaration that names nothing stays legal**, and that is compatibility
  rather than leniency: every link shared before task 3.97 carries bare ids and
  has to open as the build it described. The missing value is therefore a
  **gap**, never a refusal — `{:not_modelled, {:gear_feat_choice, id}}`, owed
  exactly until a value is recorded and not one build longer.

  ⚠ **The value buys the borrowed feat no standing it did not have.** A worn
  `Spell focus (evocation)` still fails `Greater spell focus`'s
  `feats: [spell_focus]`, because that is the H7 line above and this task did not
  move it; the refusal is the ordinary `{:requires_feat, :spell_focus}` and no
  school list is reached at all. ⚠ Here stood «a worn `Spell focus` satisfies
  `Greater spell focus`'s `feats: [spell_focus]` but not its `same_choice_as`, so
  the school list stays empty with `{:choice_requires, …}`». That described the
  model as it stood **before** H7 (14.08.2026) and was left behind when the
  measurement narrowed it — checked by calling, 25.08.2026.

  ⚠ It **is** a take for the purpose of the **effect**, and it is **not** one for
  the purpose of the ceiling on takes. Dan settled the arithmetic on 09.08.2026 —
  a slot and an amulet are two takes of `Epic toughness`, «Это будет +2» — so
  `Build.feat_takes_owned/4` counts it and twenty hit points land. The ceiling
  went the other way when it was measured (14.08.2026, `GAME_CHECKS.md` H8):
  «брать эти фиты в билде также можно вплоть до 10 раз (если фит уже взят с вещи
  его можно взять при левел апе этот же фит)», so `Rules.FeatChoices` counts
  slots (`Build.feat_takes/3`) and nine picks plus an amulet still allow a tenth
  pick.

  ⚠ This paragraph has now been wrong in **both** directions, which is the point
  of keeping its history. It first said a declaration must never read as a take
  at all («a stated `max_takes` would refuse a pick the player has every right to
  make») — right about the ceiling, wrong about the effect. It then said the
  ceiling had to count it «or it can be walked around by wearing the feat instead
  of picking it» — right about the effect, wrong about the ceiling, and that
  half was our own inference rather than anybody's word. What actually stops the
  walk-around is the ceiling on the effect, which Dan named in the same breath:
  «как максимум для УЧЁТА там всё равно будет только 10 раз». Two ceilings, two
  answers; one number cannot serve both.

  Both readings stay apart from `Build.feat_choices/3`, which is slots-only for a
  third reason: a take can be counted without being attributed to a value. The
  values themselves do have a reader that counts an item — `Build.
  feat_choices_owned/4`, the choice-level twin of `feats_owned/3` — and it is
  read by the two rules that price an **effect** off a value (the skill a bonus
  lands on, the weapon the attack roll is rolled with), never by the ones that
  judge whether a pick is legal.

  ## The term keeps the source the **data** gives it, and that is on purpose

  A markup record says `source: {:feat, :iron_will}`, and it says that whether the
  feat was picked, granted or worn: the record is about the feat. So a worn feat's
  contribution is a `:feat` term, no new kind of source beside it — and that
  matters beyond tidiness, because the source kind is what decides which side of a
  ceiling the bonus falls on (`Caps.covers_source?/3`,
  `stat_caps.*.applies_to_sources`, since 09.08.2026).

  Naming a fourth kind would have to be earned by a number that differs, and
  there is none to point at: it is the same feat, giving the same bonus, and the
  engine cannot tell where the character got it. Where the boundary genuinely
  runs is between a **feat** and a **class or racial ability written in the shape
  of a feat** — `Divine grace`, `Sacred defense`, `Lucky` — and the data already
  draws it with `{:class, …}` / `{:race_feat, …}`.

  ⚠ Nothing in this module or its tests may assume which side of a ceiling a
  `:feat` term lands on. That answer moved once already (feats came out from under
  the attack ceiling on 09.08.2026) and is about to move again for the saves; it
  is read from the ruleset, never known here.

  ## What is deliberately **not** refused

    * **Declaring a feat the build already owns**, and — since 09.08.2026 — the
      other way round too: **picking a feat an item already lends.**
      `feats_owned/3` is a set, so a feat held both ways counts once and no number
      doubles.

      ⚠ This paragraph used to say the opposite about the second half: the picker
      called such a feat `{:already_taken, …}` and would not sell a slot for it,
      "which agrees with the arithmetic". It does not. An item comes off and a
      slot does not, so a player who wants the feat *permanently* was told he
      could not have it — a false illegality, and the worse of the two failure
      modes (`HANDOFF.md`, «контракт из двух половин»). The working precedent was
      already in the project: a feat a **class** grants for free is warned about,
      not refused (CLAUDE.md §6), and the argument is stronger here, because a
      class grant cannot be lost.

      So the pick is allowed and the player is told what it buys:
      `Rules.feat_pick_caveats/3` answers `{:owned_from_gear, id}` where a slot
      would add nothing at all, and answers nothing where it would — another take
      of a repeatable feat is a real twenty hit points (`pick_caveats/3` below).
      What decides "may it be picked" is `Build.feats_permanent/3`; `feats_owned/3`
      keeps answering the two questions it was widened for, requirements and
      bonuses.
    * **Declaring a feat no item is known to grant.** No source lists which feats
      items grant, and the player's own statement about their own character is the
      same kind of input as `+12 CON` — which nothing verifies either, and carries
      no caveat for it.
    * **A declared feat's own prerequisites.** An item grants what it grants: a
      level 1 character wearing something that lends `Epic prowess` has it, and
      asking him for 21 character levels first would be checking the wearer
      against a requirement the wiki states about *picking* the feat. This is also
      the one place where the two `Riding Sprint`-style shard feats become
      reachable at all — their own pages say the feat cannot be chosen at
      level-up and comes with a named item.

  What *is* refused is a feat this ruleset does not have (`{:unknown_feat, id}`)
  and one the shard switched off (`{:feat_disabled, id}`, `Devastating critical`):
  no item lends a feat that does not exist on the shard, and a declaration that
  satisfied a requirement out of one would be a false legality of our own making.
  Both are the same tuples `Rules.validate_feat/3` already answers with.
  """

  alias BuildCalculator.Rules.{Build, FeatChoices, GapReceivers, Gear}

  @typedoc """
  Why a declaration may not stand as written.

  ⚠ `{:invalid_choice, …}` is about the **value**, not the feat, and it arrives
  only from a link somebody edited by hand: the interface asks
  `Rules.FeatChoices.gear_reasons/4` before recording anything, and the URL codec
  drops a value its own dictionary cannot resolve (`Encoding.resolve_feat/2`).
  What slips past both is a value gated **per feat** rather than per domain —
  `ooze` is in `creature_types.json` and `Favored enemy` still may not take it.
  """
  @type reason ::
          {:unknown_feat, atom()} | {:feat_disabled, atom()} | {:invalid_choice, atom(), atom()}

  @typedoc """
  What a pick that **is** allowed still owes the player.

  Not a refusal: the slot may be spent, the sentence says what it buys.
  """
  @type caveat :: {:owned_from_gear, atom()}

  @doc """
  Whether this declaration may stand as written, and if not, why.

  Takes a whole entry — a bare `feat_id` or a `{feat_id, choice}` pair — and no
  build: the answer is a property of the feat, its value and the ruleset. Nothing
  about the character can make an item's feat illegal — that is the point of the
  feature — and nothing about the character is looked at.

  Two questions, and the second arrived with task 3.97:

    * **the feat** — this ruleset has it and the shard has not switched it off;
    * **the value** — the feat takes a parameter and this is one the domain
      accepts. Judged by `Rules.FeatChoices.choice_reasons/3`, the one place a
      value meets a domain, so the picker and this cannot disagree about what
      `Favored enemy` will name.

  ⚠ A declaration that names **nothing** passes: it is what every link written
  before task 3.97 says, and refusing it would shut those links (решение Dan,
  25.08.2026). The silence is owed as a gap instead — see `gaps/2`.
  """
  @spec validate(Gear.feat_entry(), map()) :: :ok | {:error, [reason()]}
  def validate(entry, ruleset) do
    feat_id = Build.feat_id(entry)

    case Map.fetch(ruleset.feats, feat_id) do
      :error -> {:error, [{:unknown_feat, feat_id}]}
      {:ok, %{disabled?: true}} -> {:error, [{:feat_disabled, feat_id}]}
      {:ok, _definition} -> value_verdict(feat_id, Build.feat_choice(entry), ruleset)
    end
  end

  defp value_verdict(feat_id, choice, ruleset) do
    case FeatChoices.choice_reasons(feat_id, choice, ruleset) do
      [] -> :ok
      reasons -> {:error, reasons}
    end
  end

  @doc """
  The declared feats that actually count, as a set — `Build.feats_owned/3`'s
  third source.

  A declaration `validate/2` would refuse is left out rather than honoured: a
  build made before the shard switched a feat off, or a hand-edited link, must
  not have a requirement satisfied out of a feat that does not exist here. The
  declaration itself is kept in the struct — dropping it would lose the player's
  statement — and `illegal/2` is what makes the discrepancy visible.
  """
  @spec held(Gear.t(), map()) :: MapSet.t(atom())
  def held(%Gear{} = gear, ruleset) do
    for entry <- gear.feats,
        validate(entry, ruleset) == :ok,
        into: MapSet.new(),
        do: Build.feat_id(entry)
  end

  @doc """
  The values `feat_id` is declared with off items — the gear half of
  `Build.feat_choices_owned/4`.

  One entry per accepted declaration, in the gear's own (sorted) order, and
  `nil` where the declaration names no value. `nil` is kept for the same reason
  a slot pick's is: "declared, saying nothing" is a different fact from "not
  declared", and the two readers that price a value off this both drop `nil`
  themselves.

  ⚠ **Not a count of takes.** An item lends the feat once however many values it
  names (`Build.feat_takes_owned/4` is the count, and it answers `1`); two
  entries here are two skills getting +3, never two takes of `Epic toughness`.
  """
  @spec choices(Gear.t(), map(), atom()) :: [atom() | nil]
  def choices(%Gear{} = gear, ruleset, feat_id) when is_atom(feat_id) do
    for entry <- gear.feats,
        Build.feat_id(entry) == feat_id,
        validate(entry, ruleset) == :ok,
        do: Build.feat_choice(entry)
  end

  @doc """
  Every declaration this ruleset refuses, as `{feat_id, reason}`.

  The same contract `Rules.illegal_feats/2` keeps for picks, and for the same
  reason: `compute/2` has no opinion on whether a declaration was ever valid, so
  without this a link carrying a feat the shard has since removed would read as
  legal. Ordered by feat id.
  """
  @spec illegal(Gear.t(), map()) :: [{atom(), reason()}]
  def illegal(%Gear{} = gear, ruleset) do
    for entry <- Enum.sort(gear.feats),
        {:error, reasons} <- [validate(entry, ruleset)],
        reason <- reasons do
      {Build.feat_id(entry), reason}
    end
  end

  @doc """
  What spending a slot on `feat_id` here would buy nothing for — `[]` when it buys
  something.

  Exactly one caveat today, and it is the other half of allowing the pick at all:
  an item lends the feat, the feat cannot be taken twice, so the slot changes no
  number. The slot may still be spent — an item comes off and a slot does not —
  and a player who does it for that reason is doing something sensible; what he
  must not be is uninformed, because a slot spent for nothing is «реальная и
  дорогая ошибка, которую никто не ловит» (CLAUDE.md §6).

  ⚠ **Repeatability is the whole of the test**, and it is read from the data
  (`FeatChoices.repeatable?/2`), never from a list of feat ids. Another take of
  `Epic toughness` is a real twenty hit points even with one on an amulet, so
  saying "the slot buys nothing" there would be plainly false — the same shape of
  mistake as `Rules.FeatChoices`'s `effect_gap/2`, which had to stop caveating a
  bonus the player can see in the breakdown.

  Structured, never Russian: the wording is the web layer's
  (`BuildCalculatorWeb.Builder.Feats`), and the twin caveat about a class that
  hands the feat over later still lives there too, built out of
  `Build.granted_feats_at/3` — this is the same advice about a different source,
  not a second mechanism.
  """
  @spec pick_caveats(Gear.t(), map(), atom()) :: [caveat()]
  def pick_caveats(%Gear{} = gear, ruleset, feat_id) when is_atom(feat_id) do
    if MapSet.member?(held(gear, ruleset), feat_id) and
         not FeatChoices.repeatable?(feat_id, ruleset),
       do: [{:owned_from_gear, feat_id}],
       else: []
  end

  @doc """
  What a build owes the reader about the feats it declared, as gaps — the half
  only a **declaration** can owe.

  Exactly one thing today, and only where three things are true at once: the
  feat takes a parameter, **this** declaration did not name one, and the value
  would have moved a number the calculator prints.

  ⚠ The third condition is task 3.98's, and without it the caveat was **ten
  false confessions out of fifteen** on `siala_41`. A worn `Spell focus` names
  no school, and a school moves the DC of somebody else's saving throw — which
  is not on any screen, so nothing was lost by the silence and saying so
  frightened the player about a number he was never going to see. The same feat
  picked into a **slot** had stopped saying it earlier the same day (task 3.93),
  so the two routes gave one feat and one piece of ignorance two different
  answers on one screen. Asked through the one mechanism that answers "is this
  receiver ours", `GapReceivers.feat_effect_ours?/2`, so they cannot disagree
  again.

  ⚠ **What survives is what costs a number**, and every one of the five is
  countable: `Skill focus` and `Epic skill focus` (+3 and +10 on the skill row),
  `Weapon focus` and `Epic weapon focus` (+1 and +2 to the attack roll), and
  `Weapon of choice` — whose own page says it has «no direct effect on game
  play» and which is nevertheless the biggest of them, because it designates the
  weapon the Weapon Master's whole `AB bonus` column is counted with (+7 at
  class level 28).

  ⚠ The second half of that sentence is task 3.97's whole visible effect here.
  It used to read «a declaration *cannot* name it», which was a statement about
  the model rather than about the build, so the caveat was owed by every worn
  `Skill focus` for ever. Now it is owed by the ones that say nothing, and a
  player who names the skill sees it go — which is the only kind of confession
  worth printing (CLAUDE.md §9: снимать признание можно только тем, что вернёт
  его само). Clear the value and the caveat comes back by itself.

  ⚠ There is deliberately **no** caveat about the effect *here*, and that has
  never meant a declaration is owed none. Restating one would either argue with a
  term the player can see in the breakdown — the mistake `Rules.FeatChoices`'s
  `effect_gap/2` had to be taught to avoid after task 1.9 — or duplicate a
  statement the existing machinery already makes. Where the caveats about a worn
  feat actually come from, all three of them by the same walk a picked feat gets:

    * **the five markup readers** (`Rules.FeatBonuses` and its four siblings) —
      they decide who holds a record's source with `Build.feats_owned/3`, gear
      included, so `{:not_modelled, {:feat_hp_bonus, …}}` and its kin have always
      reached a declaration;
    * **`Rules.FeatChoices.gaps/3`** — «прибавку от фита в статы не считаем»
      for a repeatable feat, since 14.08.2026. It walked slots only until then,
      which left `Self concealment` off an item silent about the one thing it
      should have said;
    * **`Rules.shard_feat_gaps/3`** — what the shard's own page rewrote and the
      core did not apply, since 14.08.2026, minus the facts that are about
      *acquiring* the feat (`GapReceivers.about_acquiring_a_feat/0`): an item's
      feat is never checked against its own prerequisites, so a caveat about who
      may pick it describes nothing that happened to this character.
  """
  @spec gaps(Gear.t(), map()) :: [tuple()]
  def gaps(%Gear{} = gear, ruleset) do
    for entry <- Enum.sort(gear.feats),
        validate(entry, ruleset) == :ok,
        gap <- choice_gap(entry, ruleset),
        uniq: true do
      gap
    end
  end

  # Whether the feat takes a parameter is read through `FeatChoices.domain/2`,
  # never off a list of feat names here: the day the shard makes a sixth feat
  # repeatable the answer has to come from `priv/rules/` (CLAUDE.md §3), and one
  # reading of `repeatable.choice` is what keeps the picker and this from
  # disagreeing about which feats have a value at all.
  #
  # ⚠ Three cases, not two, since task 3.97 — and the third is the point: a
  # declaration that **did** name a value owes nothing, because the value is in
  # the build and the bonus is in the numbers. `uniq: true` above is what keeps
  # one feat declared twice, once bare and once with a value, from saying its
  # piece twice.
  defp choice_gap(entry, ruleset) do
    feat_id = Build.feat_id(entry)

    case {FeatChoices.domain(feat_id, ruleset), Build.feat_choice(entry)} do
      {nil, _no_parameter} -> []
      {_domain, nil} -> unnamed_value_gap(feat_id, ruleset)
      {_domain, _named} -> []
    end
  end

  # Стоит ли неназванное значение хоть одного числа, которое мы печатаем.
  #
  # 🔴 Задача 3.98. До неё оговорку получал ЛЮБОЙ фит с доменом, и десять из
  # пятнадцати на `siala_41` были ложными признаниями: у `Spell focus` школа
  # двигает ДЦ чужого спасброска, у `Weapon specialization` — урон,
  # у `Improved critical` — крит-диапазон. Ни одной из этих механик калькулятор
  # не отвечает вовсе, то есть не назвав значение, игрок не теряет ничего
  # (CLAUDE.md §9, решение Dan 10.08.2026: гэп — дырка в нашем ОТВЕТЕ, а не
  # в наших знаниях).
  #
  # ⚠ И расхождение было ВИДНО НА ОДНОМ ЭКРАНЕ: тот же фит, взятый слотом,
  # молчал с задачи 3.93 — `FeatChoices.gaps/3` спрашивала получателя, а эта
  # функция нет. Один фит, одно незнание, две позиции проекта. Референсный билд
  # Dan (Бард 4 / Бледный мастер 19 / РДД 10 / Мастер оружия 7) нёс обе строки
  # про объявленный `Improved critical`, и 3.93 сняла ровно одну из них.
  #
  # ⚠ Спрашивается ТОТ ЖЕ механизм и ТОТ ЖЕ словарь, а не свой:
  # `GapReceivers.feat_effect_ours?/2` — единственное место, читающее
  # `ruleset.feat_effect_receivers`. Одного вызова хватает и на решение
  # владельца `not_a_gap` (задача 3.95): у `Arcane defense` и `Favored enemy`
  # оно уже принято, и своей ветки им не нужно.
  #
  # ⚠ Направление ошибки — в сторону показа: метки нет — оговорка остаётся,
  # хватает одного нашего получателя, ruleset без словаря (`vanilla`)
  # не фильтрует ничего.
  #
  # 🔴 `whole_effect_counted?/2` здесь НЕ спрашивается, хотя соседний
  # `FeatChoices.effect_gap/2` спрашивает, и это осознанно: у него посчитанный
  # эффект гасит фразу «прибавку не считаем», а здесь он — единственная
  # причина, по которой значение вообще чего-то стоит. Скопировать его сюда
  # значило бы погасить ровно те пять оговорок, которые честны: `Skill focus`
  # и `Epic skill focus` теряют +3 и +10 в строке навыка, `Weapon focus`
  # и `Epic weapon focus` — +1 и +2 к атаке, а `Weapon of choice` — всю колонку
  # «AB bonus» Мастера оружия (+7 у ВМ 28), потому что именно он назначает
  # оружие, которым она считается.
  defp unnamed_value_gap(feat_id, ruleset) do
    if GapReceivers.feat_effect_ours?(feat_id, ruleset),
      do: [{:not_modelled, {:gear_feat_choice, feat_id}}],
      else: []
  end
end
