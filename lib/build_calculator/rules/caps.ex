defmodule BuildCalculator.Rules.Caps do
  @moduledoc """
  The ceilings a shard's numbers stop at.

  Siala declares no ceilings of its own — it *references* the vanilla NWN ones
  ("Бонус входит в лимита атаки +20", "входит в кап +50"). The core knowing
  nothing about them is not a cosmetic hole: **it overstates attack and skills
  for exactly the builds the calculator gets opened for**, the ones pushed to the
  cap (CLAUDE.md §6).

  Three ceilings are applied, all of them from `ruleset.stat_caps`, none of them
  a literal here:

    * `:attack_bonus` — +20
    * `:saving_throw_bonus` — +20
    * `:skill_bonus` — +50

  A fourth, `:max_skill_value` — the 127 ceiling on a skill's *total* — is
  `verified` in the data since 03.08.2026 and therefore carried here too. It was
  `unclear` while the wiki only stated it for Hide and Move Silently; the player
  confirmed it as the general rule (`source: user`, the top of the ranking in
  CLAUDE.md §3), so the gap it used to raise is gone.

  ⚠ Applied since task 3.20 (`Rules.Skills.value/4`), and still unable to bite on
  a legal build: a skill's total is bounded at ≈119, because the item bonuses
  that could push it further are inside the same +50 the racial bonus is in. The
  arithmetic is spelled out in `Rules.Skills` — and it is worth reading before
  "fixing" the clamp, since the tempting sum (74 + 50 = 124) double-counts the
  Human's +12.

  ## What the ceilings bite on

  All three cap **bonuses**, not the base: base attack, skill ranks and an
  ability modifier are outside them. The +50 is the one that now has a real item
  term under it — the skill bonuses the player types under «Вещи» (task 3.20),
  which the shard's own page puts inside the ceiling («+12 к спеллкрафту … входит
  в кап +50», about a magic staff). ⚠ Nothing is missing on the item side any
  more: `{:not_modelled, :attack_bonus_outside_weapon}` used to be named right
  here — «an attack bonus off anything other than the weapon in hand, which no
  field takes at all» — and it was **removed 21.08.2026 by Dan's decision**
  (task 3.71): «бонуса к атаке с прочих вещей я не припоминаю, мы уже учитываем
  всё что надо». The other two thirds of that gap (buffs and the bard song) had
  already been ruled out of the answer entirely on 10.08.2026, and §9 forbids
  such a thing being a gap at all.

  ⚠ **The armour check penalty is not one of them, and never was one of these**
  (task 3.42, 16.08.2026). It used to be named right here beside the item attack
  bonus, and that was a filing error as much as a stale sentence: a ceiling
  stated on bonuses has nothing to say about a penalty, and `clamp/3` — one-sided
  by construction — would have done nothing to it whichever way it was routed.
  It is counted now, off the item worn, as a term of a skill's value and outside
  every pool here (`Rules.Skills`).

  ## ⚠ "Bonuses" is not the same as "every bonus", and the answer is per **record**

  A ceiling covers some sources of a bonus and not others, and which is which is
  **data**, never a reading made here. The rule between the two levels the data
  states it at, word for word:

  > **Сторона капа читается у записи. Вид источника — дефолт только для тех
  > слагаемых, у которых записи в файлах разметки нет вовсе.**

  So `covers_record?/3` answers for anything with a record of its own —
  `feat_save_bonuses.json`, `feat_attack_bonuses.json` → `bonuses[].cap` — and
  `covers_source?/3` answers for the three mechanisms of `Rules.compute/2` that
  have no record: gear, the shard's racial bonus, a skill rule (Spellcraft).

  ## How that rule was arrived at, three times wrong first

  09.08.2026, Dan, `source: user` both times:

    1. «Фиты не входят в кап атаки +20» — before that, task 1.12b had put a
       feat's attack bonus under the ceiling **by analogy** with the saves, where
       a class ability under the +20 is quoted verbatim (`fandom:Uncanny dodge`).
       That produced `applies_to_sources`: a side per source **kind**.
    2. «Divine grace не входит в кап +20, а Sacred Defence входит. Похоже нам для
       каждого фита надо ещё объявить, входит в кап или нет» — and those two are
       both **class abilities written in the shape of a feat**. A kind cannot
       give them opposite answers. So the side moved onto the record, and
       `applies_to_sources` kept exactly the sources that have no record.

  And a third time, 10.08.2026 (task 3.22, `GAME_CHECKS.md` J1), `source: user`
  again: «Бонус силы в кап 20 не входит… Получается attack bonus или enchantment
  bonus оружия, баффы (магия клерика и прочих), песня барда, бонус светлого эльфа
  (сиальская тема)». `gear` under `:attack_bonus` means exactly one thing today —
  what an item did to the governing **ability** — and an ability modifier is in
  none of the four. So it moved outside, and the attack ceiling is left covering a
  single source, the shard's racial bonus. The first genuine item bonus under it
  arrives with the armoury (task 3.5), as a field of its own.

  The lesson each correction leaves is the same shape and worth keeping all three
  times: «применяется к бонусам» ≠ «применяется ко всем бонусам», «применяется
  к фитам» ≠ «применяется ко всем фитам», and — the third — the side is decided by
  **what** is added, not by **who** added it: a bonus off an item is still an
  ability modifier, and an ability modifier is base. A cited scope about one source
  is not a rule about every source that resembles it.

  ⚠ **The saves and attack are not symmetric, and the asymmetry is the statement.**
  Both have almost every record outside them — thirteen of fourteen for the saves,
  two of two for attack — but `gear` is inside for the saves and outside for
  attack, because under that one name two different things ride: a number the
  player typed as a save bonus, and an ability modifier an item raised. That very
  divergence between two screens of one application is what found the bug: AB put
  the ability's gear share under the ceiling, the saves never did. What did *not*
  change any of the three times is that everything a ceiling does cover is clipped
  **together, once** — clipping per source is how the saves once carried +40 while
  every source said +20 (CLAUDE.md §9).
  """

  @type stat :: :attack_bonus | :saving_throw_bonus | :skill_bonus

  @typedoc """
  Which mechanism of `Rules.compute/2` a bonus came from, as the rulesets name
  them: `:gear`, `:racial_bonus`, `:skill_rule`.

  ⚠ **Not** the source *fields* of the markup files (`:feat`, `:class`, `:skill`,
  `:race_feat`, `:race`) — those have records, and a record states its own side
  (`covers_record?/3`). The loader refuses to compile a ceiling whose
  `applies_to_sources` names one of them, so the two levels cannot drift into
  answering the same question twice.
  """
  @type source :: atom()

  @typedoc """
  One record of the bonus markup, as far as this module is concerned: it carries
  a `cap` side, or it does not and its kind answers for it.
  """
  @type bonus_record :: %{
          optional(:cap) => %{inside?: boolean(), assumed?: boolean()} | nil,
          source: {atom(), atom()}
        }

  @doc "The ceiling for `stat`, or `nil` when the ruleset does not state one."
  @spec cap(map(), stat()) :: integer() | nil
  def cap(ruleset, stat), do: Map.get(ruleset.stat_caps, stat)

  @doc """
  Clips `value` to the ruleset's ceiling for `stat`.

  Returns `{value, capped?}`. A ruleset with no ceiling for `stat` returns the
  value untouched — absence of a number is never treated as a number.

  **The clip has one side.** Every ceiling here is stated as a ceiling on a
  bonus ("лимит атаки +20", "кап +50"); none of them names a floor. So a
  negative total — the attack a strength penalty from gear takes away, a save
  penalty typed under "Вещи" — passes through untouched. Mirroring the ceiling
  into a floor would be a game number nobody wrote down, which is the one thing
  this module exists not to do.
  """
  @spec clamp(map(), stat(), integer()) :: {integer(), boolean()}
  def clamp(ruleset, stat, value) do
    case cap(ruleset, stat) do
      cap when is_integer(cap) and value > cap -> {cap, true}
      _ -> {value, false}
    end
  end

  @doc """
  Whether the ceiling for `stat` covers a bonus that came from the **mechanism**
  `source` — gear, the shard's racial bonus, a skill rule.

  `true` when the ruleset says nothing about that source — a ceiling stated as
  one on *bonuses* covers a bonus unless its own scope says otherwise, which is
  how every one of them was read before the scopes existed. That default is never
  load-bearing on a shipped ruleset: the loader refuses to compile a ceiling
  whose scope leaves out a mechanism the core actually adds
  (`verify_cap_sources!/4`), so the only rulesets reaching it are the ones
  with no such ceiling at all, where nothing is clipped either way.

  ⚠ **Do not call this with a markup record's kind.** `Divine grace` and `Sacred
  defense` are both `{:feat, _}` and fall on opposite sides of the +20; the kind
  is not the answer for anything that has a record. That is `covers_record?/3`.
  """
  @spec covers_source?(map(), stat(), source()) :: boolean()
  def covers_source?(ruleset, stat, source) do
    case scope(ruleset, stat, source) do
      %{inside?: inside?} -> inside?
      nil -> true
    end
  end

  @doc """
  The same question for one **record** of the bonus markup — a feat, a class
  ability, a skill, a racial trait as `feat_save_bonuses.json` and
  `feat_attack_bonuses.json` state them.

  The record's own `cap` is the answer whenever it has one, and on a shipped
  ruleset every `applied` record does: the loader refuses to compile one that
  does not (`cap_side!/4`). A record without it falls back to its kind, which is
  the pre-09.08.2026 reading and survives only for a ruleset whose markup file is
  absent — where nothing is counted, so nothing is clipped either.

  ⚠ There is no clause here that decides anything by *shape* — not by the kind,
  not by whether the amount is flat, not by which class hands the ability over.
  Every attempt to infer this from the shape of a record has been wrong twice
  (see the moduledoc), and the second time the two records that broke it were
  indistinguishable in every field but this one.
  """
  @spec covers_record?(map(), stat(), bonus_record()) :: boolean()
  def covers_record?(ruleset, stat, record) do
    case record do
      %{cap: %{inside?: inside?}} -> inside?
      %{source: {kind, _id}} -> covers_source?(ruleset, stat, kind)
    end
  end

  @doc """
  Whether a mechanism's side is an **assumption** rather than something anybody
  stated.

  No mechanism is one today: gear, the racial bonus and the skill rule each have
  their own citation. Kept because the answer «никто этого не писал» has to have
  somewhere to live other than a comment — the build turns it into
  `{:assumed, {:cap_covers_source, stat, source}}`, which is what stops a choice
  the core had to make from looking like a fact.
  """
  @spec assumed_source?(map(), stat(), source()) :: boolean()
  def assumed_source?(ruleset, stat, source) do
    match?(%{assumed?: true}, scope(ruleset, stat, source))
  end

  @doc """
  The same for one record: is its side stated, or did somebody have to choose?

  Nothing is `assumed` today either — `Small stature` and `Lucky` were, until
  09.08.2026, and Dan naming them in his list is what closed it. A record marked
  so is reported as `{:assumed, {:cap_covers_entry, stat, id}}` on every build
  that carries the bonus, whether or not the ceiling actually bites: a ceiling
  that is out of reach would otherwise hide the question exactly where it lives.
  """
  @spec assumed_record?(map(), stat(), bonus_record()) :: boolean()
  def assumed_record?(ruleset, stat, record) do
    case record do
      %{cap: %{assumed?: assumed?}} -> assumed?
      %{source: {kind, _id}} -> assumed_source?(ruleset, stat, kind)
    end
  end

  defp scope(ruleset, stat, source) do
    ruleset
    |> Map.get(:stat_cap_sources, %{})
    |> Map.get(stat, %{})
    |> Map.get(source)
  end
end
