defmodule BuildCalculator.Rules.Progression do
  @moduledoc """
  Aggregates per-class progression tables into base attack, base saves, hit
  points and attacks per round.

  Every number comes out of `ruleset.classes[id].progression`, which is the wiki
  table transcribed level by level. No `high`/`medium`/`low` formula is re-derived
  here: the label is a label, the table is the fact.
  """

  alias BuildCalculator.Rules.{AttackModifiers, Build, Epic, FeatBonuses}

  # Which saves exist, and nothing about what any of them is worth. The three
  # keys are the shape `Rules.compute/2` and `Rules.SaveBonuses` already speak.
  @saves [:fort, :ref, :will]

  @typedoc """
  One class's share of base attack (task 3.16), and how many of its levels earned it.

  **Three different level counts, because they are three different numbers**, and
  collapsing them is the lie this term exists to prevent: `levels_taken` is what
  the build bought, `levels_counted` is what fed base attack, and
  `levels_ignored` is the difference — the levels epic rule 2 throws away
  (`Epic`). On `Fighter 10 / Cleric 15 / Rogue 16` the rogue's row reads
  `levels_taken: 16, levels_counted: 0, subtotal: 0`, and a breakdown that
  printed "Rogue × 16" instead would contradict the total standing beside it.
  `levels_counted + levels_ignored == levels_taken`, always.

  `progression` is the ruleset's own label for the class — `"high"` / `"medium"`
  / `"low"` in both rulesets today, with Siala's monk override already applied
  (`bab_progression`, `Data.Loader`). It travels **untouched and as a label**:
  what one is worth per level is the loader's business, checked there against
  every vanilla progression row, and the table is the fact. Turning the label
  back into a coefficient here would be a second copy of a game number — and
  `0.75 × 15` is `11.25` while the cleric's real share is `11`, so it would also
  print a sum that does not equal its parts. `nil` for a class the ruleset does
  not carry a label for.

  `subtotal` is `nil` — never `0` — when the class's progression table has no row
  for `levels_counted` (an over-levelled prestige class off a hand-edited link,
  an unknown class): the total is then short by an unknown amount, and a
  confident zero would hide that. Such a term always comes with a gap
  (`{:missing_data, {:class_progression, …}}` or `{:unknown_class, …}`).
  """
  @type bab_class_term :: %{
          class: atom(),
          levels_counted: non_neg_integer(),
          levels_taken: pos_integer(),
          levels_ignored: non_neg_integer(),
          progression: String.t() | nil,
          subtotal: non_neg_integer() | nil
        }

  @typedoc """
  Base attack, regrouped by class instead of folded away (task 3.16).

  `by_class` carries **one term per class the build ever took**, in the order it
  was first taken — the same order `hp_breakdown`'s and `Summary.title/3`'s lists
  use, so a build's three breakdowns list its classes the same way. A class that
  contributed nothing is present with `subtotal: 0` rather than absent: "the
  rogue gave zero" is the single most expensive thing to know about a multiclass
  build and the one the old one-line caption never said.

  `epic_term` is the flat epic attack bonus (`Epic.attack_bonus/2`) and
  `counted_levels` the size of the window (`Epic.counted_levels/1`) — both here
  rather than left to the caller so the breakdown explains itself without
  reaching back into the ruleset, exactly as `hp_breakdown` carries `con_term`.

      Enum.sum(for %{subtotal: n} <- by_class, is_integer(n), do: n) + epic_term
        == stats.base_attack

  holds **exactly**, and on any build where every subtotal is an integer that is
  every term in the list. ⚠ The sum is not a check of anything by itself: the
  totals are computed *from* these rows, one traversal and one truth, so it can
  never disagree. What has to be checked term by term — including the terms worth
  `0`, which no sum can see — is the list itself, compared literally
  (`test/build_calculator/rules/compute_test.exs`, describe `bab_breakdown`).
  """
  @type bab_breakdown :: %{
          by_class: [bab_class_term()],
          epic_term: non_neg_integer(),
          counted_levels: non_neg_integer()
        }

  @typedoc """
  One class's share of **all three** base saves, and how many of its levels earned it.

  The same three level counts as `t:bab_class_term/0`, for the same reason and
  off the same rows — epic rule 2 throws class levels past the window away from
  the saves exactly as it does from base attack, so `Fighter 10 / Cleric 15 /
  Rogue 16` has a rogue worth nothing here too.

  ⚠ **Where this term differs from its base-attack twin, and why it is not
  three of them.** A save is not one number but three, and `levels_counted` is
  a fact about the **class**, not about a save: the row of the progression table
  that was read carries fort, ref and will together. So there is one term per
  class carrying a map per save (`subtotals`, `progressions`) rather than three
  parallel breakdowns with the level counts copied into each — three copies
  could disagree, and two of the three disagreeing is invisible to any check
  that looks at one save at a time.

  `progressions` is the ruleset's own label per save — `"good"` / `"poor"` in
  both rulesets today, and only those two: a save is either primary for the
  class or it is not (`save_progressions`, `Data.Loader`). It travels
  **untouched and as a label**, for the same reason `progression` does above:
  what `"good"` is worth per class level is `Data.Loader.Classes.save_from_label/2`'s
  business, and it is checked there against every vanilla save cell, so the
  label and the number beside it cannot contradict each other. `nil` for a save
  the ruleset carries no label for.

  `subtotals` is `%{fort: nil, ref: nil, will: nil}` — all three at once, never
  one of them — when the class's progression table has no row for
  `levels_counted`: fort, ref and will live in the same row, so a row that
  cannot be read is three unknowns and not one. Such a term always comes with
  the same gap its base-attack twin carries.
  """
  @type save_class_term :: %{
          class: atom(),
          levels_counted: non_neg_integer(),
          levels_taken: pos_integer(),
          levels_ignored: non_neg_integer(),
          progressions: %{(:fort | :ref | :will) => String.t() | nil},
          subtotals: %{(:fort | :ref | :will) => non_neg_integer() | nil}
        }

  @typedoc """
  Base saves, regrouped by class instead of folded away into one «база» term.

  `by_class` carries one term per class the build ever took, in the order it was
  first taken — the same list, in the same order, that `bab_breakdown` and
  `hp_breakdown` use, because all three are built from one traversal. A class
  that contributed nothing is present with zeroes rather than absent, for the
  same reason it is there in base attack: `Wizard 20 → Fighter 20` has the saves
  of a **wizard**, and twenty fighter levels worth nothing at all is the single
  most expensive thing to know about that build.

  `epic_term` is `Epic.save_bonus/2` — ⚠ **not** `attack_bonus/2`, and not the
  same number: epic saves go up on **even** character levels (22, 24 … 40) while
  epic attack goes up on odd ones, so at Siala's level 41 cap the saves carry
  `+10` and the attack `+11`. One term for all three saves, because an epic
  level raises all three at once.

      Enum.sum(for %{subtotals: %{^save => n}} <- by_class, is_integer(n), do: n)
        + epic_term == stats.base_fort   # / base_ref / base_will

  holds **exactly**, per save. ⚠ As with `bab_breakdown`, that sum checks
  nothing by itself — the totals are computed from these very rows — and a term
  worth `0` moves no sum at all. What has to be compared is the list of terms,
  literally, against numbers taken from the progression tables
  (`test/build_calculator/rules/compute_test.exs`, describe `save_breakdown`).
  """
  @type save_breakdown :: %{
          by_class: [save_class_term()],
          epic_term: non_neg_integer(),
          counted_levels: non_neg_integer()
        }

  @doc """
  Base attack and base saves from the class levels that count, per class and totalled.

  Only the first `Epic.counted_levels/1` character levels feed either — that is
  the whole of epic rule 2, and it is applied in exactly one place: the per-class
  rows below. The four totals are summed **from those rows**, so the number the
  panel shows and the breakdown that explains it cannot drift apart; there is no
  second traversal to disagree with the first.

  Returns the totals, the same totals per class — `bab_by_class` (see
  `t:bab_class_term/0`) and `save_by_class` (see `t:save_class_term/0`) — and any
  `gaps` met on the way: a class whose progression table does not reach the level
  asked for, or one the ruleset does not know at all.

  ⚠ Both breakdowns come off **one** list of rows, and that is the point rather
  than an implementation detail: base attack and the three saves are read out of
  the same table row, decided by the same window, so a build cannot be told that
  its rogue gave nothing to attack while giving something to Fortitude.
  """
  @spec base(Build.t(), map()) ::
          %{
            bab: non_neg_integer(),
            fort: integer(),
            ref: integer(),
            will: integer(),
            bab_by_class: [bab_class_term()],
            save_by_class: [save_class_term()],
            gaps: [tuple()]
          }
  def base(%Build{} = build, ruleset) do
    rows = counted_rows(build, ruleset)

    %{
      bab: total(rows, :bab),
      fort: total(rows, :fort),
      ref: total(rows, :ref),
      will: total(rows, :will),
      bab_by_class: Enum.map(rows, &class_term/1),
      save_by_class: Enum.map(rows, &save_class_term/1),
      gaps: Enum.flat_map(rows, & &1.gaps)
    }
  end

  # One row per class the build took, in the order it was first taken. The window
  # is read once, here, and every number downstream — the four totals, the
  # breakdown, the gaps — comes off these rows.
  defp counted_rows(%Build{levels: levels} = build, ruleset) do
    taken = Build.class_levels(build)
    within = Build.class_levels(build, Epic.counted_levels(ruleset))

    for class <- Enum.uniq(levels) do
      counted = Map.get(within, class, 0)
      {row, gaps} = counted_row(ruleset, class, counted)

      %{
        class: class,
        levels_counted: counted,
        levels_taken: Map.fetch!(taken, class),
        levels_ignored: Map.fetch!(taken, class) - counted,
        progression: progression_label(ruleset, class),
        save_progressions: save_progression_labels(ruleset, class),
        row: row,
        gaps: gaps
      }
    end
  end

  # No counted levels, no contribution — and that is epic rule 2 rather than a
  # table read, so nothing is looked up and no gap is reported. A class taken
  # entirely past the window has nothing to say about its own progression table
  # and must not be blamed for it.
  defp counted_row(_ruleset, _class, 0), do: {%{bab: 0, fort: 0, ref: 0, will: 0}, []}

  defp counted_row(ruleset, class, counted) do
    case progression_row(ruleset, class, counted) do
      {:ok, row} -> {row, []}
      {:error, reason} -> {nil, [reason]}
    end
  end

  # A row that could not be read contributes nothing to the total — which is what
  # the old fold did too — and says so through `subtotal: nil` plus its gap.
  defp total(rows, key) do
    Enum.reduce(rows, 0, fn
      %{row: %{} = row}, acc -> acc + Map.fetch!(row, key)
      %{row: nil}, acc -> acc
    end)
  end

  defp class_term(row) do
    %{
      class: row.class,
      levels_counted: row.levels_counted,
      levels_taken: row.levels_taken,
      levels_ignored: row.levels_ignored,
      progression: row.progression,
      subtotal: row.row && row.row.bab
    }
  end

  # The same row, told as three numbers instead of one. `row.row` being `nil`
  # makes all three `nil` together and never one of them: fort, ref and will are
  # read out of a single table row, so an unreadable row is three unknowns.
  defp save_class_term(row) do
    %{
      class: row.class,
      levels_counted: row.levels_counted,
      levels_taken: row.levels_taken,
      levels_ignored: row.levels_ignored,
      progressions: row.save_progressions,
      subtotals: Map.new(@saves, fn save -> {save, row.row && Map.fetch!(row.row, save)} end)
    }
  end

  # The ruleset's label, passed through as a label. `Data.Loader` is the one place
  # that knows what `"medium"` is worth per level, and it checks that formula
  # against all 330 vanilla progression cells before regenerating anything with
  # it; restating it here would be the same game number written twice.
  defp progression_label(ruleset, class) do
    case ruleset.classes do
      %{^class => %{bab_progression: label}} -> label
      _ -> nil
    end
  end

  # The same, three at a time. A class the ruleset does not carry labels for gets
  # `nil` per save rather than a missing key: the breakdown reads one save at a
  # time, and an absent key there would have to be told apart from an absent
  # label by every caller.
  defp save_progression_labels(ruleset, class) do
    labels =
      case ruleset.classes do
        %{^class => %{save_progressions: %{} = labels}} -> labels
        _ -> %{}
      end

    Map.new(@saves, fn save -> {save, Map.get(labels, save)} end)
  end

  @typedoc """
  `hit_points/3`'s total, regrouped by class instead of folded away (task 3.6).

  `by_class` sums the exact per-level `max(1, hit_die + con_modifier)` term
  `hit_points/3` already adds internally, grouped by class rather than into
  one running number. `con_term` is `con_modifier × character_level` —
  constitution is one number for the **whole character** (the final score,
  applied retroactively — see the moduledoc below), not a per-class fact, so
  it stands apart from `by_class` rather than being folded into each row.

  ⚠ **`hit_dice` is a list, and that is not decoration** (task 3.37): a class's
  die is a function of its own level, not a constant, and `red dragon disciple`
  is the one class in the corpus that uses the freedom — d6 on its class levels
  1–3, d8 on 4–5, d10 on 6–10, d12 from 11. Its row therefore reads
  `[%{die: 6, levels: 3}, %{die: 8, levels: 2}, %{die: 10, levels: 5}]`, and a
  single `hit_die: 10` in its place would print a number that does not multiply
  out to the `subtotal` standing beside it — a breakdown that disagrees with its
  own total is worse than none (CLAUDE.md §6). The other 22 classes have a
  one-element list, which is the same statement they always made.
  `Enum.sum(for d <- hit_dice, do: d.levels) == levels` and
  `Enum.sum(for d <- hit_dice, do: d.die * d.levels) == subtotal` both hold
  always.

  `by_feat` is the same idea for the feats that add hit points — `Toughness`
  at one per character level, `Epic toughness` at twenty per take
  (`BuildCalculator.Rules.FeatBonuses`, task 1.9). Named per feat rather than
  summed, for the same reason the classes are: «+41» beside `Toughness` is a
  number the player can check, «+41» on its own is one he has to trust.

  `innate` is a fourth bucket, deliberately kept apart from `by_feat`: «Дух
  Сиалы», a flat +20 the shard hands **every** character regardless of level
  or class (волна 12, 09.08.2026, `GAME_CHECKS.md` заход A кейс A1 — a plain
  Fighter 1 read 31 HP where the model predicted 11, and a Wizard 1 who never
  gets `Toughness` still read 24). `source: kind: user` — no page on either
  wiki names the mechanic at all, see `Data.Loader.Character.innate_hp_bonus/1` and
  `overrides.json` → `character.spirit_of_siala`. It is **not** a feat: nobody
  picks it, no class grants it, and this function does not gate it through
  `FeatBonuses.hit_points/3`'s feat ownership the way `by_feat`'s terms are —
  the only question asked of it is whether there is a character at all
  (`nil` on the level-less build the empty-build tests exercise, `nil`
  unconditionally under the vanilla ruleset, which never reads the fact).
  Giving it a feat id instead would have let a build "already own" or
  prerequisite against a mechanic nobody chooses — `%{id:, ru:, amount:}` or
  `nil` is honest about what it is instead. Added to the total **after** the
  per-level floor, the same place `Epic toughness`'s flat term lands, because
  the source's own words are "выдаётся ... единоразово" and not "per level".

  `floor_adjustment` absorbs whatever those clean terms could not: the
  per-level floor means "hit dice alone" plus "CON alone" do not, in general,
  sum back to the total once CON is negative enough that a level's own
  `max(1, …)` bit (three levels of a d4 class at a −4 CON modifier land on
  the floor every time, not on `die + con_modifier`). It is `0` on every
  build that is not deliberately pushed there, and it is computed as a
  residual against the total this same function already produced — the same
  trick `Summary.save_terms/1`'s "сверх капа" uses for a ceiling — so
  `Enum.sum(Enum.map(by_class, & &1.subtotal)) + con_term +
  Enum.sum(Enum.map(by_feat, & &1.subtotal)) + (innate[:amount] || 0) +
  floor_adjustment` equals the total **exactly**, always, never approximately,
  and never a second implementation of the floor rule to drift from the first.
  `innate`'s amount is subtracted out of the residual explicitly rather than
  left for `floor_adjustment` to swallow — the same reason `by_feat`'s terms
  are not left for it either: a residual that absorbed a real term would make
  a corrupted term invisible (HANDOFF.md, «сумма частей равна итогу — не
  проверка»; the floor is the only thing this residual is allowed to be
  about).
  """
  @type hp_breakdown :: %{
          by_class: [
            %{
              class: atom(),
              levels: pos_integer(),
              hit_dice: [%{die: pos_integer(), levels: pos_integer()}],
              subtotal: non_neg_integer()
            }
          ],
          con_term: integer(),
          by_feat: [
            %{feat: atom(), takes: pos_integer(), subtotal: integer(), capped?: boolean()}
          ],
          innate: %{id: atom(), ru: String.t(), amount: pos_integer()} | nil,
          floor_adjustment: non_neg_integer()
        }

  @doc """
  Hit points for the whole build, plus the same total broken down by class.

  Assumes the **maximum** hit die roll on every level, which is what the
  community build format and CBC report; the wiki only guarantees the maximum on
  character levels 1-3. Constitution is applied per level and taken from the
  final score, because NWN recalculates it retroactively whenever CON changes
  (`fandom:Hit point`). The floor of one hit point per level is the same source.

  Feats are in the number too, and where they stand relative to that floor is a
  rule and not a detail: a per-level bonus (`Toughness`) goes **inside** it —
  «a minimum of 1 hit point for each level … after combining the base and bonus
  hit points associated with that level» — while a flat one (`Epic toughness`,
  twenty per take) is added to the total afterwards, exactly as its page words
  it. See `BuildCalculator.Rules.FeatBonuses` and the data file's
  `_floor_decision`; the two readings differ only where the floor bites, which
  is why the choice is written down instead of assumed.

  So is «Дух Сиалы» (task, волна 12, 09.08.2026) — a flat +20 the shard hands
  every character, unconditionally and once, on top of dice, CON and feats
  alike (`ruleset.innate_hp_bonus`, `hp_breakdown().innate`). It lands after
  the floor exactly like `Epic toughness`'s flat term does, for the source's
  own reason: Дан's words are "единоразово", never "per level". `nil` under
  the vanilla ruleset — the fact lives under `overrides.json` →
  `character.spirit_of_siala`, which only the Siala layer reads.

  ⚠ **A level's die is read off the level of its own class, not off the
  character's** (task 3.37). For 22 classes the distinction is invisible — one
  number, every level — but `red dragon disciple`'s die grows with the class
  (d6 → d8 → d10 → d12), and «not retroactive» is the source's own word
  (`fandom:Hit die increase`): the third class level keeps the d6 it was taken
  with. So the levels are walked in the order the build took them, counting each
  class's own levels as they come. ⚠ And epic rule 2 — the one that throws class
  levels past character level 20 out of base attack and the saves — does **not**
  apply here: every level pays hit points whenever it was taken, which is why
  this function walks `build.levels` itself rather than reusing
  `counted_rows/2`'s window.

  Returns `{:ok, hp, breakdown}` or `{:error, reason}` — a class whose data
  states neither one hit die nor a scale over its levels cannot be computed
  honestly, and a plausible number would be worse than none. ⚠ That refuses the
  **whole** build's hit points, feat bonuses included: one level of such a class
  shows no hit points at all, and therefore no `Toughness` term either. Naming
  the missing die is the honest half of that; giving the feat bonuses their own
  number beside a total that does not exist would not be. ⚠ Today no class in
  either ruleset produces it — `red dragon disciple` was the one, and it has its
  scale since task 3.37 — so the refusal is exercised on a ruleset with the fact
  taken out rather than on the corpus.
  """
  @spec hit_points(Build.t(), map(), integer()) ::
          {:ok, non_neg_integer(), hp_breakdown()} | {:error, tuple()}
  def hit_points(%Build{levels: levels} = build, ruleset, con_modifier) do
    feat_terms = FeatBonuses.hit_points(build, ruleset, length(levels))
    per_level = Enum.reduce(feat_terms, 0, &(&1.per_level + &2))
    flat = Enum.reduce(feat_terms, 0, &(&1.flat + &2))
    innate = innate_bonus(ruleset, levels)

    levels
    |> with_class_levels()
    |> Enum.reduce_while({:ok, 0}, fn {class, class_level}, {:ok, total} ->
      case hit_die(ruleset, class, class_level) do
        {:ok, die} -> {:cont, {:ok, total + max(1, die + con_modifier + per_level)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, total} ->
        total = total + flat + innate_amount(innate)
        {:ok, total, hp_breakdown(levels, ruleset, con_modifier, feat_terms, innate, total)}

      error ->
        error
    end
  end

  @doc """
  The die one **class level** of a class rolls: `{:ok, sides}` or `{:error, gap}`.

  The single place either shape of the fact is read, so the two cannot drift:
  `hit_die` (one number, 22 classes of 23) and `hit_die_by_class_level` (steps
  over the class's own levels, `red dragon disciple`). A scale wins where both
  are present — a class that states its die per level has already said what the
  single number could only approximate — and its **last step covers everything
  above it**, which is what carries the answer past the class's own table:
  Siala takes a prestige class to 31 while the vanilla table stops at 10, and
  the page's own epic section is where the `11 → d12` step came from.

  ⚠ `class_level` is the ordinal of that level **within its class** — the
  build's third Red Dragon Disciple level is `3` however high the character
  is. Passing a character level here would give a starting Red Dragon Disciple
  a d12 for reaching character level 11.
  """
  @spec hit_die(map(), atom(), pos_integer()) :: {:ok, pos_integer()} | {:error, tuple()}
  def hit_die(ruleset, class, class_level) do
    case ruleset.classes do
      %{^class => %{hit_die_by_class_level: [_ | _] = steps}} ->
        {:ok, step_die(steps, class_level)}

      %{^class => %{hit_die: die}} when is_integer(die) ->
        {:ok, die}

      %{^class => _} ->
        {:error, {:missing_data, {:hit_die, class}}}

      _ ->
        {:error, {:unknown_class, class}}
    end
  end

  # The last step that has started. The scale is validated on load — it begins
  # at class level 1 and rises — so there is always one.
  defp step_die(steps, class_level) do
    steps
    |> Enum.take_while(&(&1.from <= class_level))
    |> List.last()
    |> Map.fetch!(:die)
  end

  # `[:bard, :bard, :rogue, :bard]` → `[{:bard, 1}, {:bard, 2}, {:rogue, 1},
  # {:bard, 3}]`. Which level of its own class each character level is, in the
  # order the build took them — the order is the fact for a growing die, and
  # `Build.class_levels/1`'s totals cannot answer it.
  defp with_class_levels(levels) do
    levels
    |> Enum.map_reduce(%{}, fn class, seen ->
      taken = Map.get(seen, class, 0) + 1

      {{class, taken}, Map.put(seen, class, taken)}
    end)
    |> elem(0)
  end

  # «Дух Сиалы» itself — read straight off the ruleset (`Data.Loader`), never
  # named by id here the way a feat would be, per the moduledoc above. The
  # only gate this function owns is `levels != []`: the empty-build tests
  # (`ComputeTest`, «an empty build is all zeroes») exercise a build that is
  # not a character yet, and a flat +20 there would contradict `hp == 0`
  # without a single class ever having been taken. A real build always has at
  # least one level, so this never fires for one the game could produce.
  defp innate_bonus(%{innate_hp_bonus: bonus}, levels) when levels != [], do: bonus
  defp innate_bonus(_ruleset, _levels), do: nil

  defp innate_amount(%{amount: amount}), do: amount
  defp innate_amount(nil), do: 0

  # «По классам», in the order the interface already lists a build's classes
  # elsewhere — first taken, first shown (`Summary.title/3` uses the same
  # `Enum.uniq/1` on the level-by-level list, so a build's HP breakdown lists
  # its classes in the same order as its own title does).
  defp hp_breakdown(levels, ruleset, con_modifier, feat_terms, innate, total) do
    counts = Enum.frequencies(levels)
    character_level = length(levels)
    dice_taken = dice_taken(levels, ruleset)

    by_class =
      for class <- Enum.uniq(levels) do
        dice = Map.fetch!(dice_taken, class)
        count = Map.fetch!(counts, class)

        %{
          class: class,
          levels: count,
          hit_dice: dice,
          subtotal: Enum.reduce(dice, 0, &(&1.die * &1.levels + &2))
        }
      end

    # A per-level feat is worth its bonus on every level, a flat one is worth
    # itself — the same arithmetic `hit_points/3` above just did, restated per
    # feat instead of summed. The floor is *not* applied here: whatever it took
    # away lands in `floor_adjustment` as a residual, so one implementation of
    # the floor stays one.
    by_feat =
      for term <- feat_terms do
        %{
          feat: term.feat,
          takes: term.takes,
          subtotal: term.per_level * character_level + term.flat,
          capped?: term.capped?
        }
      end

    dice_total = Enum.reduce(by_class, 0, &(&1.subtotal + &2))
    feat_total = Enum.reduce(by_feat, 0, &(&1.subtotal + &2))
    con_term = con_modifier * character_level
    innate_total = innate_amount(innate)

    %{
      by_class: by_class,
      con_term: con_term,
      by_feat: by_feat,
      innate: innate,
      floor_adjustment: total - dice_total - con_term - feat_total - innate_total
    }
  end

  # `%{class => [%{die:, levels:}]}` — how many of a class's levels were taken on
  # each of its dice, in the order the dice come. One list per class, and one
  # entry in it for 22 classes of 23; `red dragon disciple` gets as many entries
  # as its scale has steps the build reached.
  #
  # ⚠ Read through `hit_die/3`, the same function the total above uses, and off
  # the same walk of the same levels — the breakdown is a regrouping of the sum,
  # never a second computation of it. A class whose die could not be read never
  # gets here at all: `hit_points/3` has already refused the whole build.
  defp dice_taken(levels, ruleset) do
    levels
    |> with_class_levels()
    |> Enum.reduce(%{}, fn {class, class_level}, acc ->
      {:ok, die} = hit_die(ruleset, class, class_level)

      Map.update(acc, class, [%{die: die, levels: 1}], &add_die(&1, die))
    end)
    |> Map.new(fn {class, dice} -> {class, Enum.reverse(dice)} end)
  end

  # Newest first while accumulating: a level either extends the die the class is
  # on or starts the next one, and the scale only ever rises, so the head is the
  # only entry that can grow.
  defp add_die([%{die: die} = current | rest], die),
    do: [%{current | levels: current.levels + 1} | rest]

  defp add_die(dice, die), do: [%{die: die, levels: 1} | dice]

  @doc """
  Attacks per round: the base from the level-20 BAB, plus whatever the ruleset
  adds on top.

  The vanilla number is a table lookup and is frozen at the base attack the
  character had at level 20 — callers pass the pre-epic base attack, not the epic
  total. That is not the whole story on every shard: Siala's Arcane Archer grants
  an extra attack per ten class levels, up to three. So the base is only a base,
  and `ruleset.attack_modifiers` is layered over it (`Rules.AttackModifiers`,
  task 3.72). The list is empty for vanilla.

  ⚠ Both modifier maps go in, naked and geared, because a modifier's conditions
  say which of the two they read — `Rules.AttackModifiers` explains why that is
  not a thing this function may decide.

  Returns `{attacks, terms}`, and `attacks` is `base + total(terms)` by
  construction: the breakdown is a regrouping of the number, never a second
  computation of it.
  """
  @spec attacks_per_round(Build.t(), map(), non_neg_integer(), %{atom() => integer()}, %{
          atom() => integer()
        }) :: {pos_integer(), [AttackModifiers.term_entry()]}
  def attacks_per_round(%Build{} = build, ruleset, base_attack, naked_modifiers, geared_modifiers) do
    table = ruleset.attacks_per_round
    highest = table |> Map.keys() |> Enum.max(fn -> 0 end)
    base = Map.get(table, min(base_attack, highest), 1)

    context = AttackModifiers.context(build, naked_modifiers, geared_modifiers)
    terms = AttackModifiers.terms(ruleset, context)

    {base + AttackModifiers.total(terms), terms}
  end

  @doc "The progression row for a given class level, or a machine-readable reason."
  @spec progression_row(map(), atom(), pos_integer()) :: {:ok, map()} | {:error, tuple()}
  def progression_row(ruleset, class, level) do
    case ruleset.classes do
      %{^class => %{progression: progression}} ->
        case Map.fetch(progression, level) do
          {:ok, row} -> {:ok, row}
          :error -> {:error, {:missing_data, {:class_progression, class, level}}}
        end

      _ ->
        {:error, {:unknown_class, class}}
    end
  end
end
