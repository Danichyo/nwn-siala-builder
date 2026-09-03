defmodule BuildCalculatorWeb.Builder.GameLogImport do
  @moduledoc """
  Somebody's OWN character, out of the shard's `.билд` chat dump.

  Task 3.111, second pass. The first pass (`BuildCalculator.GameLog`) answers
  a narrow question — can the text be read at all — and hands back a
  structure that still mixes what the class handed over for free with what
  the player actually chose (its own moduledoc, "The three traps"). This
  module answers the second question: **which of that is a decision the
  constructor has to reproduce**, and turns it into a
  `BuildCalculator.Rules.Build`.

  ## The minimum, in Dan's own words (26.08.2026)

  «Хотя бы просто последовательность уровней + фиты было бы очень круто
  мочь мигрировать, поинт бай можно ввести руками, стат, поднимаемый на
  уровнях, вроде в логе есть». So this module carries, in order of how much
  it matters if it is wrong:

    1. **race → classes in the order taken.** A class level resolved to `nil`
       stops the ladder right there (`ladder/2`) rather than let the levels
       after it slide up one — CLAUDE.md §3 makes order load-bearing for base
       attack and saves past character level 20, so a build missing its tail
       is honest and a build with its tail shifted is a silent lie.
    2. **the `+1` on every fourth level.**
    3. **feats, level by level** — the hard part, see below.

  **Starting ability scores ARE restored — task 3.172, 03.09.2026, closing
  the puzzle CLAUDE.md §9 carried since 26.08.2026.** Dan named the formula
  the four failed readings `GameLog`'s own moduledoc measured were missing:
  «в (WHITE) попадают статы на 1 уровне + все статы типа эпик силы и
  прочих… вот их надо вычесть». `(WHITE) ABILITIES` bakes in the point-buy
  purchase, the race and the build's own bonuses (`Great …`, a Red Dragon
  Disciple's own table) — and does **not** carry the level-up `+1`s at all
  (CLAUDE.md §3, "Что на самом деле печатает `(WHITE) ABILITIES`"). Every
  earlier attempt, `GameLog`'s own four included, subtracted those increases
  too and undershot by exactly their count — the 19/22/24-of-30 the open
  question recorded.

  So the reconstruction is one subtraction, twice: `Rules.Abilities.
  racial_modifiers/2` and `Rules.AbilityBonuses.by_ability/3` — the SAME two
  numbers `Rules.Abilities.scores_at/3` itself adds on top of a base score
  — come back off `(WHITE)`, once every feat this pass places is already on
  the build (`with_point_buy/3` below runs after `level_feats/6` on
  purpose: a slotted `Great strength` has to be owned before
  `AbilityBonuses.by_ability/3` can see it). Neither call is a game formula
  invented here; both are the exact reads `Rules.compute/2` already makes
  for a hand-built character.

  ⚠️ **Spending exactly 30 is the game's own invariant, not this module's
  threshold — Dan said so twice.** First for the forced minimum purchase
  itself (CLAUDE.md §3: «очков 30 и их надо всегда принудительно
  потратить, иначе игра не даст продвинуться в создании персонажа»), then
  again for this exact check, task 3.172: «надо чтоб идеально ложилось, все
  30 очков обязаны быть потрачены, иначе игра в реальности не позволит,
  так что у абсолютно любого билда все 30 потрачены». So a real character
  spending anything other than 30 does not exist — which means a mismatch
  here is never a fact about the **player's** character. It can only be
  this project's own gap: a class ability bonus or a `Great …` feat this
  ruleset does not carry, or `(WHITE)` printed in a shape not seen on any
  of the fifteen fixtures. `verified?/2` below asks for that equality
  exactly, never "close enough" — 29 fails precisely as loudly as 18.

  Checked by running it against all fifteen fixtures before this shipped
  (all fifteen land on 30, every reconstructed score inside the table's own
  floor and ceiling), not asserted from the formula alone. Failing the
  check writes nothing: the build keeps today's floor
  (`BuildCalculatorWeb.Builder.PointBuy.starting_scores/1` plus the forced
  caster purchase, `PointBuy.enforce_floor/2`) and `issues` names this
  project's own gap rather than hinting the player's own sheet is somehow
  wrong — it is never that. A quietly wrong ability score would be worse
  than an honestly empty one regardless of whose fault it was: it moves HP,
  AB, saves and every ability-gated feat requirement without the player
  ever being told.

  **Alignment stays unrestored regardless** — the log carries none at all,
  which is a different fact from "we cannot read it".

  **A bonus, not the minimum: skill ranks.** `GameLog` already reads them
  level by level (a real per-level delta, not a lump total the way a forum
  paste's `SKILLS` block is — see `Builder.Import`'s own moduledoc on why
  *that* source cannot be placed), so there is nothing to reconstruct; they
  are carried straight into `Build.skills`.

  ## Trap 1 — what to do with a level that lists everything at once

  A class's own first level and a race both hand over feats for free, and the
  chat dump lists them in the very same `FEATS:` line as what the player
  picked (`GameLog`'s own moduledoc, trap 3). The engine does not print a
  fourth category — a class grant **with a choice attached** — as anything
  different either: Weapon Master's `Weapon of choice` sits in the list next
  to plain grants, `(bastard sword)` and all. So every `:feat` token is sorted
  into exactly one of four buckets before anything is written:

    * **class grant, no choice to carry** — `Build.granted_feats_at/3` already
      says so; nothing is written, the model derives it the same way it always
      has.
    * **racial trait** (`ruleset.races[race].bonus_feats`) — nothing written,
      same reasoning as the plain class grant.
    * **everything else** — a real pick, and it goes through the same
      narrowest-slot-first placement `Builder.Import` already uses for a
      forum paste, because a slot that is not interchangeable with another
      does not become interchangeable just because the source this time is a
      client log instead of a forum post (CLAUDE.md §6).

  ⚠️ **A class grant that still owes a choice — CLAUDE.md §6's «выданный фит
  С ВЫБОРОМ в лестницу ИДЁТ», Weapon Master's own `Weapon of choice` — turns
  out to need none of this module's own code.** `Rules.Build.granted_feats_at/3`
  already withholds it (`ruleset.grant_substitutions`, keyed
  `{weapon_master, 1}`) precisely so `Rules.FeatSlots` can open it as an
  ordinary bonus slot instead — measured by Dan twice before this task even
  existed (`GAME_CHECKS.md` M2/M2b). So `Weapon Of Choice (bastard sword)`
  never matches the first bucket at all; it falls straight into "everything
  else", gets its weapon resolved the same way `Weapon Focus (bastard sword)`
  does, and lands in `{:class_bonus, :weapon_master}` — confirmed against
  `hnyupius.log`'s own level 20. `Build.put_granted_choice/4` is still called
  from `grant/8` below, but only as a fallback for a *different* class grant
  the ruleset does not substitute this way — none exists in either ruleset
  today, so that branch is presently unexercised and deliberately kept: the
  model carries the capability, and removing the one caller that would use it
  the day a second such grant appears is a worse bet than a few lines of dead
  code today.

  A `{:special, tag}` token (`Дух Сиалы`, `Epic Character`, `Epic
  <ClassName>`, a domain grant) is never a feat at all — `GameLog` already
  says so, and this module's only remaining job for one is the domain grant,
  which becomes a `Build.class_choices` entry instead (Cleric's own two
  domains, printed as `War Domain Powers` / `Travel Domain Powers`).

  ## Trap 2 — a parenthesised argument is not always a choice

  `Weapon Focus (bastard sword)` and `Defensive Awareness (1)` both come back
  from `GameLog` with the parenthesised text in `argument` — the tokenizer
  cannot tell a chosen weapon from a numbered stage apart, on purpose (its own
  moduledoc: "what the parenthetical *means*… is the caller's dictionary's
  business"). This module is that caller: `Rules.feat_choice_domain/2` says
  whether the feat takes a value *at all*, and only then is `argument` looked
  up in that domain (`BuildCalculatorWeb.Builder.ChoiceIndex`, shared with
  `Builder.Import`). No domain, no lookup — the stage number is simply not a
  fact this model has anywhere to put, the same way a bare trailing roman
  numeral (`Great strength III`, `GameLog`'s `rank` field) never is.

  ⚠️ **One real loss, found and then closed at the source.** Until task 3.118
  (27.08.2026) five of `GameLog`'s own aliases folded `Energy Resistance,
  <element>` onto one feat id without keeping the element
  (`epic_energy_resistance` read with `argument: nil` even for «Fire I» — the
  element was baked into *which* alias matched, never captured separately),
  and a sixth family carried the identical loss the day Frah Hall's own log
  arrived: `Resist energy` spelled with the element *inside* the name
  («Resist Sonic Energy») rather than after a comma. Recovering either by
  re-reading `raw` HERE would have been the wrong move — exactly the "guess
  from context instead of the dictionary" `GameLog`'s own tokenizer refuses
  to make, for the identical reason. The fix instead sits where the loss
  actually happened: `GameLog`'s own dictionary now carries the element as
  part of the alias's OWN value (`feat_spelling_aliases/0`, a
  `{:feat, id, argument}` triple, read by `classify_feat_entry/1`), so this
  module sees it exactly the way it already sees a parenthesised one —
  `resolve_choice/6` and `grant/8` below were already written for "a feat
  with a domain and an argument" and needed no change at all.

  ⚠️ **The order discipline stays load-bearing regardless of that fix.**
  Domain is asked *before* argument, so a feat that owes a value and truly
  got none (a bare "Weapon Focus" with no weapon named at all, say) is told
  apart from one that never owed a value in the first place, and
  `{:feat_argument_missing, …}` remains this module's honest answer for that
  genuine case — never silently. Reversed, the first version of this
  function let `epic_energy_resistance` drop its element with zero issue
  raised — caught before it shipped, not after, but worth naming here so the
  next reader does not "simplify" the order back.

  ## Trap 3 — skill ranks are a delta, not a total

  Measured against Dan's own hand-built reference for `hnyupius.log`'s
  character: the log's `Discipline +5` on level 2 and `+1` on every level
  after is the **true** history, and a build that instead dumped every rank
  onto one late level (as a human assembling a build by hand is prone to do)
  would have a different price and a different cap per rank (CLAUDE.md §6,
  "Навыки — бюджет, а не каталог"). `GameLog` already reads the per-level
  deltas; this module only sums same-level duplicates and drops what never
  resolved to a skill id (already visible in `GameLog`'s own `problems`).

  ## Honesty

  Nothing that reads is thrown away silently. Every `GameLog.problem()` this
  module inherits is carried straight into `issues` — `issue_text/2` gives
  every one of its shapes Russian wording, the same discipline
  `Builder.Import.issue_text/2` holds itself to for a forum paste. A feat this
  module *recognised* but could not place gets the **same** reason the feat
  picker itself would show for the identical refusal
  (`BuildCalculatorWeb.Builder.Feats.reason/2`, which already falls back to
  `Builder.Labels.reason/2`) — one function translates a refusal into Russian
  everywhere in this project, and a second copy of that vocabulary here would
  be exactly the drift CLAUDE.md warns against.

  Never raises: an unreadable dump is a near-empty build with `issues` saying
  why, same as `GameLog.parse/2` and `Builder.Import.parse/2` before it.
  """

  alias BuildCalculator.GameLog
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Abilities, AbilityBonuses, Build, FeatChoices, FeatSlots}
  alias BuildCalculatorWeb.Builder.{ChoiceIndex, Feats, Labels, PointBuy}

  @typedoc "A machine-readable note about something that did not carry over."
  @type issue :: tuple()

  @type result :: %{
          build: Build.t(),
          title: String.t() | nil,
          log: GameLog.t(),
          read: map(),
          issues: [issue()]
        }

  # -------------------------------------------------------------- entry point --

  @doc """
  Reads one `.билд` chat dump straight into a build, plus everything that did
  not carry over.

  Never raises — `GameLog.parse/2`'s own promise, extended: a dump that reads
  badly turns into a build with as much of it as could be read and an
  `issues` list explaining the rest, never an exception and never a plausible
  wrong number.
  """
  @spec parse(term(), map()) :: result()
  def parse(text, ruleset), do: text |> GameLog.parse(ruleset) |> from_log(ruleset)

  @doc "The second pass alone, for a caller that already has a parsed `GameLog.t()`."
  @spec from_log(GameLog.t(), map()) :: result()
  def from_log(%GameLog{} = log, ruleset) do
    # Spliced flat, not wrapped: none of `GameLog.problem()`'s own tuple
    # heads collides with one of this module's own (checked by hand against
    # `GameLog`'s source), and `issue_text/2`/`issue_kind/1` below give the
    # inherited shapes their own clauses directly rather than through a
    # `{:log_problem, …}` layer that would need unwrapping everywhere else.
    log_issues = log.problems
    {classes, ladder_issues} = ladder(log, ruleset)
    kept = Enum.take(log.levels, length(classes))

    build =
      Build.new(
        ruleset_version: ruleset.version,
        race: log.race,
        alignment: log.alignment,
        base_abilities: PointBuy.starting_scores(ruleset),
        levels: classes
      )

    build = PointBuy.enforce_floor(ruleset, build)
    build = with_ability_increases(build, kept)

    choices = ChoiceIndex.build(ruleset)

    {build, feat_issues, tally} =
      Enum.reduce(kept, {build, [], %{}}, fn entry, {build, issues, tally} ->
        level_feats(build, ruleset, choices, entry, issues, tally)
      end)

    # After feats, not before: a slotted `Great strength` has to already be
    # on `build` for `AbilityBonuses.by_ability/3` (called inside) to see it.
    {build, point_buy_issues} = with_point_buy(build, ruleset, log.white_abilities)

    {build, skill_total} = with_skills(build, kept)

    issues =
      log_issues ++
        ladder_issues ++
        feat_issues ++ point_buy_issues ++ alignment_issue(build)

    %{
      build: build,
      title: log.name,
      log: log,
      read: read(build, classes, ruleset, tally, skill_total),
      issues: issues
    }
  end

  # Task 3.173: the shard started printing `ALIGNMENT:` (`GameLog`'s own
  # `put_alignment/2`), so "unavailable" is no longer unconditional — a log
  # that carries a recognised value has it on `build` and needs no issue at
  # all. A log with no line, or one with a value `GameLog` could not
  # resolve, still leaves `build.alignment` `nil`, and the player still
  # needs telling: an unresolved value's own raw text already surfaces
  # through `log_issues` above (`{:unresolved_alignment, raw}`, spliced in
  # from `log.problems` the same way `{:unresolved_race, raw}` always has),
  # so this only adds the "go fill it in" issue, never a second complaint
  # about the same line.
  defp alignment_issue(%Build{alignment: nil}), do: [{:alignment_unavailable}]
  defp alignment_issue(%Build{}), do: []

  # ----------------------------------------------------------------- ladder --

  # `log.levels` is already in encounter order (`GameLog`'s own moduledoc, "The
  # header count is a checksum, not a source") — this only guards the one shape
  # a `Build.levels` cannot hold at all, a `nil` class, and stops right there
  # rather than let a later level slide into the gap. `Enum.take/2` afterwards
  # (in `from_log/2`) reads off `length(classes)` alone, so a level's own
  # printed number is never trusted for positioning — same discipline `GameLog`
  # itself uses turning the ladder into a list.
  defp ladder(log, ruleset) do
    {classes, halted_at} =
      Enum.reduce_while(log.levels, {[], nil}, fn entry, {classes, _halted} ->
        cond do
          length(classes) >= ruleset.level_cap ->
            {:halt, {classes, {:cap, entry}}}

          is_nil(entry.class) ->
            {:halt, {classes, {:unresolved, entry}}}

          true ->
            {:cont, {classes ++ [entry.class], nil}}
        end
      end)

    issues =
      case halted_at do
        nil -> []
        {:cap, entry} -> [{:level_over_cap, entry.level, ruleset.level_cap}]
        {:unresolved, entry} -> [{:ladder_stopped, entry.level, length(classes)}]
      end

    {classes, issues}
  end

  # ------------------------------------------------------- ability increases --

  # `GameLog` already reports an ability label it could not resolve
  # (`{:unresolved_ability_increase, …}`, carried in via `log_issues`), so this
  # only ever writes what already resolved — never a second copy of that check.
  defp with_ability_increases(%Build{} = build, kept) do
    Enum.reduce(kept, build, &apply_ability_increase/2)
  end

  defp apply_ability_increase(entry, %Build{} = build) do
    case entry.ability_increase do
      %{ability: ability} when not is_nil(ability) ->
        %Build{build | ability_increases: Map.put(build.ability_increases, entry.level, ability)}

      _no_resolved_ability ->
        build
    end
  end

  # ------------------------------------------------------------------ skills --

  # A same-level duplicate name (not attested in any of the three fixtures,
  # guarded against on the same principle `GameLog.set_last/5` states for its
  # own duplicate fields) is summed rather than letting the second silently
  # overwrite the first.
  defp with_skills(%Build{} = build, kept) do
    Enum.reduce(kept, {build, 0}, &apply_skill_deltas/2)
  end

  defp apply_skill_deltas(entry, {%Build{} = build, total}) do
    ranks =
      for %{skill: skill, delta: delta} <- entry.skills,
          skill != nil,
          delta != nil,
          reduce: %{} do
        acc -> Map.update(acc, skill, delta, &(&1 + delta))
      end

    if ranks == %{} do
      {build, total}
    else
      at_level =
        build.skills
        |> Map.get(entry.level, %{})
        |> Map.merge(ranks, fn _skill, a, b -> a + b end)

      build = %Build{build | skills: Map.put(build.skills, entry.level, at_level)}
      {build, total + Enum.sum(Map.values(ranks))}
    end
  end

  # ------------------------------------------------------------------- feats --

  defp level_feats(build, ruleset, choices, entry, issues, tally) do
    {build, issues, tally, to_place} =
      Enum.reduce(entry.feats, {build, issues, tally, []}, fn item,
                                                              {build, issues, tally, to_place} ->
        classify_feat(build, ruleset, choices, entry.level, item, issues, tally, to_place)
      end)

    to_place
    |> Enum.sort_by(&openings(ruleset, build, entry.level, &1))
    |> Enum.reduce({build, issues, tally}, fn {feat_id, choice}, {build, issues, tally} ->
      place(build, ruleset, entry.level, feat_id, choice, issues, tally)
    end)
  end

  # Not a feat at all (`GameLog`'s own trap 2) — a domain grant is the one
  # `:special` shape this module still has work to do for; the rest (an epic
  # threshold crossed, «Дух Сиалы») carry no information the build has
  # anywhere to hold.
  defp classify_feat(
         build,
         _ruleset,
         _choices,
         _level,
         %{kind: :unknown},
         issues,
         tally,
         to_place
       ),
       do: {build, issues, bump(tally, :unresolved), to_place}

  defp classify_feat(
         build,
         _ruleset,
         choices,
         level,
         %{kind: :special, id: {:domain_powers, name}},
         issues,
         tally,
         to_place
       ) do
    domain_index = Map.get(choices, :domain, %{})
    class = Build.class_at(build, level)

    case class && ChoiceIndex.resolve(domain_index, name) do
      {:ok, value} ->
        if value in Build.class_choice(build, class) do
          {build, issues, bump(tally, :domain), to_place}
        else
          {Build.toggle_class_choice(build, class, value), issues, bump(tally, :domain), to_place}
        end

      _not_resolved ->
        {build, issues ++ [{:domain_unresolved, level, name}], tally, to_place}
    end
  end

  defp classify_feat(
         build,
         _ruleset,
         _choices,
         _level,
         %{kind: :special},
         issues,
         tally,
         to_place
       ),
       do: {build, issues, tally, to_place}

  defp classify_feat(
         build,
         ruleset,
         choices,
         level,
         %{kind: :feat, id: id} = item,
         issues,
         tally,
         to_place
       ) do
    cond do
      id in Build.granted_feats_at(build, ruleset, level) ->
        grant(build, ruleset, choices, level, id, item, issues, tally, to_place)

      racial_grant?(ruleset, build.race, id) ->
        {build, issues, bump(tally, :racial), to_place}

      true ->
        {choice, issues} = resolve_choice(ruleset, choices, level, id, item, issues)
        {build, issues, tally, to_place ++ [{id, choice}]}
    end
  end

  # `Weapon of choice` is the one feat CLAUDE.md §6 names by hand for this: a
  # class GRANT that still owes a value. Everything else here just tallies
  # "recognised, correctly not slotted".
  #
  # ⚠️ Domain is checked BEFORE argument, and that order is the whole point:
  # a feat with no domain never owed a value, so a missing argument there is
  # not a loss (`defensive_awareness`'s stage number, say). A feat WITH a
  # domain and no argument is a different fact — something this pass cannot
  # name — and it gets its own issue rather than folding into the silent
  # "nothing to record" branch a domain-less grant takes. Getting this
  # backwards is exactly how `epic_energy_resistance`'s element went missing
  # with zero issue raised the first time this was written.
  defp grant(build, ruleset, choices, level, id, item, issues, tally, to_place) do
    case Rules.feat_choice_domain(id, ruleset) do
      nil ->
        {build, issues, bump(tally, :granted), to_place}

      _domain when is_nil(item.argument) ->
        {build, issues ++ [{:feat_argument_missing, level, id}], bump(tally, :granted), to_place}

      domain ->
        case ChoiceIndex.resolve(Map.get(choices, domain, %{}), item.argument) do
          {:ok, value} ->
            build = Build.put_granted_choice(build, level, id, value)
            {build, issues, bump(tally, :granted_choice), to_place}

          _not_resolved ->
            {build, issues ++ [{:grant_choice_unresolved, level, id, item.argument}],
             bump(tally, :granted), to_place}
        end
    end
  end

  defp racial_grant?(_ruleset, nil, _id), do: false

  defp racial_grant?(ruleset, race, id) do
    case Map.get(ruleset.races, race) do
      %{bonus_feats: feats} when is_list(feats) -> id in feats
      _no_race_or_no_list -> false
    end
  end

  # `argument` may be a real choice or a bare stage number (`Defensive
  # Awareness (1)`) — `GameLog`'s tokenizer cannot tell them apart on purpose
  # (its own moduledoc), so the domain is what decides: no domain, no lookup,
  # the number is simply not a fact this model records anywhere.
  #
  # ⚠️ **`epic_energy_resistance` is the real, measured case this second
  # clause exists for.** `GameLog`'s own five-element alias table folds
  # `Energy Resistance, Fire I` onto the bare feat id without keeping "fire"
  # anywhere `argument` can see (moduledoc's Trap 2) — so on `hnyupius.log`
  # this feat arrives with a domain (`:energy_type`) and `argument: nil`, and
  # a version of this function that treated "no argument" as "nothing to
  # report" whatever the domain said dropped the element with **zero** issue
  # raised. Domain is checked first for exactly this reason.
  defp resolve_choice(ruleset, choices, level, id, %{argument: argument}, issues) do
    case Rules.feat_choice_domain(id, ruleset) do
      nil ->
        {nil, issues}

      _domain when is_nil(argument) ->
        {nil, issues ++ [{:feat_argument_missing, level, id}]}

      domain ->
        case ChoiceIndex.resolve(Map.get(choices, domain, %{}), argument) do
          {:ok, value} -> {value, issues}
          _not_resolved -> {nil, issues ++ [{:feat_argument_unresolved, level, id, argument}]}
        end
    end
  end

  # Same narrowest-slot-first order `Builder.Import` sorts a level's picks by:
  # a feat several slots would take goes last, so a feat only ONE slot accepts
  # claims it before something more flexible does (CLAUDE.md §6).
  defp openings(ruleset, build, level, {feat_id, _choice}) do
    ruleset
    |> Feats.open_slots(build, level)
    |> Enum.count(&FeatSlots.accepts?(ruleset, &1, feat_id))
  end

  defp place(build, ruleset, level, feat_id, choice, issues, tally) do
    cond do
      already_owned?(build, ruleset, level, feat_id, choice) ->
        if reprinted_grant?(build, ruleset, level, feat_id) do
          {build, issues, bump(tally, :granted)}
        else
          {build, issues ++ [{:feat_not_placed, level, feat_id, {:already_taken, feat_id}}],
           bump(tally, :not_placed)}
        end

      slot = Feats.best_slot(ruleset, build, level, feat_id) ->
        {Build.put_feat(build, level, slot.id, feat_id, choice), issues, bump(tally, :placed)}

      true ->
        reason = not_placed_reason(build, ruleset, level, feat_id)

        {build, issues ++ [{:feat_not_placed, level, feat_id, reason}], bump(tally, :not_placed)}
    end
  end

  # ⚠️ Один `feats_owned` мало с тех пор, как фиты стали повторяемыми — тот же
  # довод, что у `Builder.Import.already_owned?/5`, и та же пара вопросов ядру.
  defp already_owned?(build, ruleset, level, feat_id, choice) do
    MapSet.member?(Build.feats_owned(build, ruleset, level), feat_id) and
      FeatChoices.reasons(build, %{feat: feat_id, choice: choice, at: level}, ruleset) != []
  end

  # `Bard Song` (`frah_hall.log`, character level 41 — Bard's own 2nd class
  # level, task 3.118) is the shape this checks for. The class hands
  # `bard_song` over once, at its own level 1 (`ruleset.classes.bard.
  # granted_feats`), and `classify_feat/8`'s first clause already keeps that
  # single occurrence out of `to_place` entirely — but the engine reprints
  # the same name on the class's *next* level too (the song's own reach
  # growing, going by the shape; the ruleset does not model that and this
  # module has no business inventing it), which `Build.granted_feats_at/3`
  # cannot see, because it only ever answers for the one level it is asked
  # about.
  #
  # ⚠️ Silenced, not merely reworded, and the reasoning is not specific to
  # this one feat. `already_owned?/4` above only fires when there is nothing
  # NEW here — no choice, or the same choice a repeatable feat already holds
  # — and a real `.билд` dump is a legal character the game itself already
  # accepted; the engine never lets a player re-pick a feat he cannot have
  # twice. So a later repeat of a name the SAME class already granted can
  # only be the class re-announcing its own ability, never an illegal
  # double-take that slipped past the game — reporting it as "не перенесён —
  # уже есть" would be noise about correct behaviour, a false alarm about a
  # pick the player never tried to make, not a loss worth telling him about.
  #
  # `Build.granted_feats/3` (cumulative — "everything granted by now"), not
  # `granted_feats_at/3` (this level alone, already asked by
  # `classify_feat/8`'s first clause): the whole point here is to see a
  # grant from an EARLIER level of the ladder, which the per-level function
  # cannot do by design.
  defp reprinted_grant?(build, ruleset, level, feat_id) do
    feat_id in Build.granted_feats(build, ruleset, level)
  end

  # Checked in the order the feat picker itself would refuse a click, so the
  # wording matches what the constructor shows for the identical fact once the
  # build is open there: disabled first (no slot would ever help — the shard
  # switched it off entirely, `Rules.FeatSlots`'s own reasoning for the same
  # ordering), then the two other level-independent refusals, then a plain "no
  # room".
  defp not_placed_reason(build, ruleset, level, feat_id) do
    feat = Map.get(ruleset.feats, feat_id)

    cond do
      feat && Map.get(feat, :disabled?, false) ->
        {:feat_disabled, feat_id}

      (refused = Rules.feat_level_up_refusals(feat_id, ruleset)) != [] ->
        List.first(refused)

      (refused = Rules.class_feat_refusals(build, level, feat_id, ruleset)) != [] ->
        List.first(refused)

      true ->
        {:no_free_slot, feat_id}
    end
  end

  defp bump(tally, key), do: Map.update(tally, key, 1, &(&1 + 1))

  # --------------------------------------------------------------- point buy --

  # Task 3.172 — see this module's own moduledoc for the formula and why it
  # was safe to stop treating `(WHITE) ABILITIES` as unreadable. Runs after
  # every feat this pass placed, never before: `AbilityBonuses.by_ability/3`
  # only sees a `Great strength` slot pick once it is actually on `build`.
  #
  # ⚠️ Requires all six ability labels — `Map.fetch!/2` below would raise on
  # a hole otherwise, and a build reconstructed off five real numbers and
  # one silent zero is exactly the "plausibly wrong instead of honestly
  # empty" this whole pass promises never to hand back (moduledoc,
  # "Honesty"). `GameLog` already reports the missing label on its own
  # (`{:incomplete_ability_block, "(WHITE) ABILITIES", …}`, inherited via
  # `log_issues` in `from_log/2`) — this only has to decline gracefully, not
  # report it a second time.
  defp with_point_buy(%Build{} = build, ruleset, white) do
    keys = Abilities.keys()

    if Enum.all?(keys, &Map.has_key?(white, &1)) do
      level = Build.character_level(build)
      race_bonus = Abilities.racial_modifiers(build, ruleset)
      own_bonus = AbilityBonuses.by_ability(build, ruleset, level)

      start =
        Map.new(keys, fn ability ->
          {ability,
           Map.fetch!(white, ability) - Map.get(race_bonus, ability, 0) -
             Map.get(own_bonus, ability, 0)}
        end)

      if verified?(ruleset, start) do
        {%Build{build | base_abilities: start}, []}
      else
        # ⚠️ `spent` is reported for a bug report, never implied to the
        # player as "your own character's fault" — `verified?/2`'s own
        # comment names why that reading is impossible.
        spent = PointBuy.spent(ruleset, start)
        {build, [{:point_buy_not_restored, {:budget_mismatch, spent, PointBuy.budget(ruleset)}}]}
      end
    else
      {build, [{:point_buy_not_restored, :incomplete_white_abilities}]}
    end
  end

  # The reconstruction's own guard — and Dan named it an INVARIANT, not a
  # heuristic, twice over: «надо чтоб идеально ложилось, все 30 очков
  # обязаны быть потрачены, иначе игра в реальности не позволит, так что у
  # абсолютно любого билда все 30 потрачены» (task 3.172, echoing the same
  # forced purchase CLAUDE.md §3 already quotes him on: «иначе игра не даст
  # продвинуться в создании персонажа»). No real character spends anything
  # but exactly 30, so failing this check is never a fact about the
  # player's own sheet — it can only be this project's own gap, a class
  # bonus or a `Great …` feat the ruleset does not carry, or `(WHITE)` in a
  # shape none of the fifteen fixtures showed. That is why the equality is
  # exact rather than "close enough": 29 is exactly as wrong as 18, because
  # neither one is a score point buy could have produced.
  defp verified?(ruleset, start) do
    PointBuy.spent(ruleset, start) == PointBuy.budget(ruleset) and
      Enum.all?(start, fn {_ability, score} ->
        score >= PointBuy.min_score(ruleset) and score <= PointBuy.max_score(ruleset)
      end)
  end

  # ------------------------------------------------------------------- read --

  defp read(build, classes, ruleset, tally, skill_total) do
    %{
      levels: length(classes),
      level_cap: ruleset.level_cap,
      race: build.race,
      feats_placed: Map.get(tally, :placed, 0),
      feats_auto:
        Map.get(tally, :granted, 0) + Map.get(tally, :racial, 0) +
          Map.get(tally, :granted_choice, 0),
      feats_unresolved: Map.get(tally, :unresolved, 0),
      feats_not_placed: Map.get(tally, :not_placed, 0),
      domains: Map.get(tally, :domain, 0),
      ability_increases: map_size(build.ability_increases),
      skill_ranks: skill_total,
      anything?: build.levels != [] or build.race != nil
    }
  end

  # ------------------------------------------------------------- the wording --

  @doc """
  One issue, in Russian — every `GameLog.problem()` shape this module
  inherits, plus this module's own.

  Same register as `Builder.Import.issue_text/2`: what did not carry over is
  said plainly, quoting the source text where there is one to quote.
  """
  @spec issue_text(issue(), map()) :: String.t()

  # ---- inherited straight from `GameLog.parse/2` ----

  def issue_text({:not_a_string}, _ruleset),
    do: "текст не распознан — попробуй вставить лог заново"

  def issue_text({:unrecognized_line, line}, _ruleset),
    do: "строка «#{ellipsis(line)}» не похожа ни на одну известную строку лога — пропущена"

  def issue_text({:missing_field, field}, _ruleset),
    do: "в логе нет блока «#{missing_field_label(field)}»"

  def issue_text({:field_before_any_level, field}, _ruleset),
    do: "#{field_label(field)} встретилось раньше первого LEVEL — пропущено"

  def issue_text({:duplicate_field, level, field}, _ruleset),
    do: "уровень #{level}: #{field_label(field)} повторено — оставлено первое чтение"

  def issue_text({:unparsed_header_segment, text}, _ruleset),
    do: "в шапке «#{text}» не разобрано как «число КЛАСС»"

  def issue_text({:unresolved_header_class, abbrev}, _ruleset),
    do: "сокращение класса «#{abbrev}» в шапке не распознано"

  def issue_text({:unresolved_race, raw}, _ruleset), do: "раса «#{raw}» не распознана"

  def issue_text({:unresolved_alignment, raw}, _ruleset),
    do: "мировоззрение «#{raw}» не распознано — впиши вручную"

  def issue_text({:unresolved_ability_label, block, name}, _ruleset),
    do: "#{block}: подпись «#{name}» не распознана как характеристика"

  def issue_text({:incomplete_ability_block, block, missing}, _ruleset),
    do: "#{block}: не хватает #{Enum.map_join(missing, ", ", &Labels.ability/1)}"

  def issue_text({:unresolved_combat_stat_label, name}, _ruleset),
    do: "COMBAT STATS: подпись «#{name}» не распознана"

  def issue_text({:incomplete_combat_stats, missing}, _ruleset),
    do: "COMBAT STATS: не хватает #{Enum.map_join(missing, ", ", &to_string/1)}"

  def issue_text({:unresolved_skill_total, name}, _ruleset),
    do: "SKILLS WITH RANKS: навык «#{name}» не распознан"

  def issue_text({:unparsed_skill_total, segment}, _ruleset),
    do: "SKILLS WITH RANKS: «#{segment}» не разобрано как «навык число»"

  # Deliberately not the same wording as `{:missing_field, :skills_with_ranks}`
  # (which `GameLog` no longer produces at all, task 3.131) — the block being
  # absent outright is legal (a character who never spent a skill point) and
  # is not reported as an issue here. This is the one shape still worth
  # naming: the header line printed and nothing followed it, which no
  # fixture has shown yet and which this module has no story for beyond
  # "look at the source text".
  def issue_text({:empty_skill_totals}, _ruleset),
    do:
      "SKILLS WITH RANKS: заголовок в логе есть, но под ним нет ни одной строки — " <>
        "загляни в исходный текст, впиши ранги вручную"

  def issue_text({:unresolved_class, level, text}, _ruleset),
    do: "уровень #{level}: класс «#{text}» не распознан — дальше лестница не читается"

  def issue_text({:unresolved_ability_increase, level, label}, _ruleset),
    do: "уровень #{level}: характеристика «#{label}» в ABILITY: не распознана"

  def issue_text({:unexpected_ability_increase_amount, level, amount}, _ruleset),
    do:
      "уровень #{level}: прибавка к характеристике #{signed(amount)} вместо +1 — перенесена как есть"

  def issue_text({:unresolved_feat, level, text}, _ruleset),
    do: "уровень #{level}: фита «#{text}» нет в справочнике"

  def issue_text({:unresolved_skill_delta, level, name}, _ruleset),
    do: "уровень #{level}: навык «#{name}» не распознан"

  def issue_text({:header_body_mismatch, class, header, body}, ruleset),
    do:
      "шапка обещает #{Labels.class_name(ruleset, class)}(#{header}), " <>
        "в лестнице набралось #{body}"

  def issue_text({:class_missing_from_header, class, body}, ruleset),
    do: "#{Labels.class_name(ruleset, class)}(#{body}) есть в лестнице, но не в шапке"

  def issue_text({:level_out_of_sequence, expected, got}, _ruleset),
    do: "после уровня #{expected - 1} лог печатает LEVEL #{got} вместо #{expected}"

  def issue_text({:level_duplicate, level}, _ruleset),
    do: "уровень #{level} в логе встречается больше одного раза"

  # ---- this module's own ----

  def issue_text({:ladder_stopped, level, kept}, _ruleset),
    do:
      "класс на уровне #{level} не распознан — дальше лестница не читается " <>
        "(перенесено #{kept} #{Labels.level_word(kept)}); порядок классов после " <>
        "этого места решает BAB и спасы, додумывать его нельзя"

  def issue_text({:level_over_cap, level, cap}, _ruleset),
    do: "уровень #{level} выше капа #{cap} — обрезано"

  def issue_text({:feat_argument_missing, level, feat}, ruleset),
    do:
      "уровень #{level}: #{Labels.feat_name(ruleset, feat)} взят с выбором, но лог " <>
        "не показывает, каким (частый случай — стихия у Energy resistance теряется " <>
        "при разборе строки) — перенесено без него, впиши вручную"

  def issue_text({:feat_argument_unresolved, level, feat, argument}, ruleset),
    do:
      "уровень #{level}: #{Labels.feat_name(ruleset, feat)} взят, но «#{argument}» " <>
        "не распознано как выбор — перенесено без него"

  def issue_text({:grant_choice_unresolved, level, feat, argument}, ruleset),
    do:
      "уровень #{level}: класс выдаёт #{Labels.feat_name(ruleset, feat)}, " <>
        "но «#{argument}» не распознано — выбор не перенесён"

  def issue_text({:domain_unresolved, level, name}, _ruleset),
    do: "уровень #{level}: домен «#{name}» не распознан"

  def issue_text({:feat_not_placed, level, feat, reason}, ruleset),
    do:
      "уровень #{level}: #{Labels.feat_name(ruleset, feat)} не перенесён — " <>
        Feats.reason(reason, ruleset)

  def issue_text({:alignment_unavailable}, _ruleset),
    do: "лог не показывает мировоззрение персонажа — впиши вручную"

  def issue_text({:point_buy_not_restored, :incomplete_white_abilities}, _ruleset),
    do:
      "в (WHITE) ABILITIES не хватает характеристик — стартовые значения " <>
        "не восстановлены, впиши поинт-бай вручную"

  def issue_text({:point_buy_not_restored, {:budget_mismatch, spent, budget}}, _ruleset),
    do:
      "стартовые характеристики не восстановлены: получилось #{spent} " <>
        "очков вместо #{budget} — такого билда в игре не бывает (все 30 " <>
        "всегда потрачены), значит это пробел в наших данных о фитах или " <>
        "классах этого билда, а не что-то не так с персонажем — впиши " <>
        "поинт-бай вручную"

  def issue_text(other, _ruleset), do: inspect(other)

  # `:skills_with_ranks` had a clause here until task 3.131 — `GameLog` no
  # longer reports `{:missing_field, :skills_with_ranks}` at all (an absent
  # block is a legal zero-skill-points character, see `put_skill_totals/3`'s
  # own note), so keeping a label for a tuple this module can never receive
  # would describe a case that does not exist. `{:empty_skill_totals}` above
  # is that shape's replacement, worded on its own rather than through this
  # generic "missing block" phrasing — it is not a missing block.
  defp missing_field_label(:name), do: "имя персонажа (CHARACTER BUILD)"
  defp missing_field_label(:header_classes), do: "список классов в шапке (Current: …)"
  defp missing_field_label(:race), do: "раса (RACE)"
  defp missing_field_label(:combat_stats), do: "боевые показатели (COMBAT STATS)"
  defp missing_field_label(:levels), do: "лестница уровней (LEVEL …)"
  defp missing_field_label(text) when is_binary(text), do: text
  defp missing_field_label(other), do: inspect(other)

  defp field_label(:ability_raw), do: "ABILITY:"
  defp field_label(:feats_raw), do: "FEATS:"
  defp field_label(:skills_raw), do: "SKILLS:"
  defp field_label(other), do: to_string(other)

  defp signed(n) when n >= 0, do: "+#{n}"
  defp signed(n), do: Integer.to_string(n)

  defp ellipsis(text) do
    if String.length(text) > 60, do: String.slice(text, 0, 57) <> "…", else: text
  end

  @doc """
  Short Russian name of an issue family, for grouping the list — the same move
  `Builder.Import.issue_kind/1` makes and for the same reason: a flat list of
  thirty notes is read by nobody.
  """
  @spec issue_kind(issue()) :: String.t()
  def issue_kind({:unrecognized_line, _line}), do: "Пропущенные строки"

  def issue_kind({:missing_field, _field}), do: "Не хватает данных"
  def issue_kind({:incomplete_ability_block, _block, _missing}), do: "Не хватает данных"
  def issue_kind({:incomplete_combat_stats, _missing}), do: "Не хватает данных"
  def issue_kind({:alignment_unavailable}), do: "Не хватает данных"
  def issue_kind({:not_a_string}), do: "Не хватает данных"
  def issue_kind({:empty_skill_totals}), do: "Не хватает данных"

  def issue_kind({:header_body_mismatch, _class, _header, _body}), do: "Источник спорит с собой"
  def issue_kind({:class_missing_from_header, _class, _body}), do: "Источник спорит с собой"
  def issue_kind({:level_out_of_sequence, _expected, _got}), do: "Источник спорит с собой"
  def issue_kind({:level_duplicate, _level}), do: "Источник спорит с собой"
  def issue_kind({:duplicate_field, _level, _field}), do: "Источник спорит с собой"
  def issue_kind({:field_before_any_level, _field}), do: "Источник спорит с собой"

  def issue_kind({:unexpected_ability_increase_amount, _level, _amount}),
    do: "Источник спорит с собой"

  def issue_kind({:feat_not_placed, _level, _feat, _reason}), do: "Не перенесено"
  def issue_kind({:ladder_stopped, _level, _kept}), do: "Не перенесено"
  def issue_kind({:level_over_cap, _level, _cap}), do: "Не перенесено"
  def issue_kind({:point_buy_not_restored, _reason}), do: "Не перенесено"

  def issue_kind(_other), do: "Не распознано"

  @doc """
  Every issue shape this module can produce, filled with sample values.

  Guards the same way `Builder.Import.issue_forms/0` guards itself: an issue
  nobody worded renders through `inspect/1`, and this is what stops that from
  happening unnoticed.
  """
  @spec issue_forms() :: [issue()]
  def issue_forms do
    [
      {:not_a_string},
      {:unrecognized_line, "какая-то строка чата"},
      {:missing_field, :race},
      {:missing_field, "CURRENT ABILITIES"},
      {:field_before_any_level, :feats_raw},
      {:duplicate_field, 1, :feats_raw},
      {:unparsed_header_segment, "??? FTR"},
      {:unresolved_header_class, "XYZ"},
      {:unresolved_race, "Полурослик"},
      {:unresolved_alignment, "Neutral"},
      {:unresolved_ability_label, "CURRENT ABILITIES", "XYZ"},
      {:incomplete_ability_block, "CURRENT ABILITIES", [:str, :dex]},
      {:unresolved_combat_stat_label, "XYZ"},
      {:incomplete_combat_stats, [:ac]},
      {:unresolved_skill_total, "Ремесло"},
      {:unparsed_skill_total, "странная строка"},
      {:empty_skill_totals},
      {:unresolved_class, 5, "Ninja"},
      {:unresolved_ability_increase, 4, "XYZ"},
      {:unexpected_ability_increase_amount, 4, 2},
      {:unresolved_feat, 3, "Неведомый фит"},
      {:unresolved_skill_delta, 3, "Ремесло"},
      {:header_body_mismatch, :fighter, 10, 9},
      {:class_missing_from_header, :monk, 1},
      {:level_out_of_sequence, 2, 4},
      {:level_duplicate, 1},
      {:ladder_stopped, 5, 4},
      {:level_over_cap, 42, 41},
      {:feat_argument_missing, 39, :epic_energy_resistance},
      {:feat_argument_unresolved, 4, :weapon_focus, "нечто странное"},
      {:grant_choice_unresolved, 20, :weapon_of_choice, "нечто странное"},
      {:domain_unresolved, 2, "Nonsense"},
      {:feat_not_placed, 1, :toughness, {:already_taken, :toughness}},
      {:feat_not_placed, 1, :weapon_proficiency_simple,
       {:feat_disabled, :weapon_proficiency_simple}},
      {:point_buy_not_restored, :incomplete_white_abilities},
      {:point_buy_not_restored, {:budget_mismatch, 24, 30}},
      {:alignment_unavailable}
    ]
  end
end
