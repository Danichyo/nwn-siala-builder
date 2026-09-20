defmodule BuildCalculator.Rules.AbilityBonuses do
  @moduledoc """
  What the **build itself** adds to the six ability scores, as opposed to what
  the player bought, the race gave or the equipment adds.

  Until task 3.1 there was nothing here at all, and the two halves of that
  failed differently. `Great strength` at least said something — the feat
  repeats, so `{:not_modelled, {:feat_bonus, :great_strength}}` was on the
  build — while a Red Dragon Disciple's own table said **nothing**: ten class
  levels, `+8` strength on the wiki's own progression table, strength 16 on our
  screen and an empty `gaps`.

  ## Nothing here knows a feat or a class by name

  Which feat or class raises which ability, by how much and in what shape is
  data — `priv/rules/vanilla/feat_ability_bonuses.json`, read by
  `BuildCalculator.Data.Loader`. There is no `great_strength` and no
  `red_dragon_disciple` in this file, and there must never be one.

  ## Two shapes, and why they are not one number

    * **per take** — a `Great …`. `+1` for every take the character has
      (`Build.feat_takes_owned/4`: every slot spent on it, plus one for an item
      that lends it), with the ceiling the page states («to a maximum
      of +10») applied to the sum. ⚠ That ceiling is the ceiling on the
      **effect** and is a different fact from the ceiling on the number of
      takes (`repeatable.max_takes`, ten, from Dan): one is the page's, the
      other is the player's, and the vanilla ruleset carries only the first.
    * **at class level** — `Dragon abilities`. A table of `class level =>
      %{ability => bonus}` whose steps are **summed**: `+2` strength stands at
      class level 2 and again at 4, and that is `+4`. ⚠ Deliberately the
      opposite reading from `ac_at_class_level` in `Rules.ArmorClass`, where
      the table states totals — the two columns come off the same wiki page and
      are printed differently, so each file states its own.

  ## What is owned, and by what

  A feat counts when the character **owns** it — picked in a slot or handed
  over by a class — because a feat is a feat however it arrived, and
  `Dragon abilities` arrives by grant at the second class level. The amount is
  then worked out from the class's own levels, which is not a tautology: the
  source keeps the two apart itself («While this feat can be given to another
  class, the ability increases depend upon levels in red dragon disciple»).

  ## Where these land in the cascade

  In the **naked** score, after the every-fourth-level increases and before the
  gear. The source splits it that way itself — one paragraph lists what a base
  score is made of and puts these feats beside point buy, race and the level
  increases; the next gives items and spells a ceiling of their own — so a feat
  bonus is never clipped by the +12 ability cap, and it does count towards a
  feat's own ability prerequisite. See `_order_decision` in the data file.

  Everything derived follows from the score, which is the whole point and the
  whole danger: `+2` constitution is `+1` to the modifier, which is `+1` hit
  point on **every** level of the build (`fandom:Red dragon disciple`: «the
  constitution increase at level 7 can also provide a significant increase to
  hit points, +1 per total character level»).

  ## Что здесь своё, а что общее

  Чтение файла, «держит ли персонаж эту запись», сбор гэпов из отвергнутых и
  `effect_coverage` — общие для пяти статов и живут в
  `BuildCalculator.Rules.Bonuses` (задача 3.21). Здесь остаётся ровно
  специфика характеристик, и её видно по тому, что осталось: две формы
  прибавки, потолок **эффекта** отдельно от потолка числа взятий, и одна
  запись, дающая несколько термов сразу (`Dragon abilities` поднимает четыре
  абилки).
  """

  alias BuildCalculator.Rules.{Bonuses, Build}

  @markup :ability_bonuses

  @typedoc """
  One source's contribution to one ability.

    * `id` — the feat or the class, for the breakdown and the gaps
    * `source` — `{:feat, id}` or `{:class, id}`
    * `ability` — which of the six
    * `bonus` — the contribution, already worked out for this build
    * `takes` — how many slots went on it (`1` for a feat that does not repeat)
    * `capped?` — the stated ceiling on the effect was reached
  """
  @type term_entry :: %{
          id: atom(),
          source: {atom(), atom()},
          ability: Build.ability(),
          bonus: integer(),
          takes: pos_integer(),
          capped?: boolean()
        }

  @doc """
  Every ability term this build earns by itself, as of character `level`.

  In the data's own order, and one term per (source, ability) pair: `Dragon
  abilities` raises four different abilities and shows up as four terms,
  because the breakdown is read one ability at a time.

  ⚠ `level` is not decoration. A feat taken at 27 has no business changing what
  was computed at 26 — most visibly in skill points, which are granted per
  level off the intelligence modifier **of that level**
  (`Rules.Skills.points_at/3`). A source that works out to zero is left out
  rather than listed as `+0`.
  """
  @spec terms(Build.t(), map(), non_neg_integer()) :: [term_entry()]
  def terms(%Build{} = build, ruleset, level) do
    for record <- Bonuses.held(build, ruleset, @markup, level),
        entry <- amount(record, build, ruleset, level),
        entry.bonus != 0 do
      entry
    end
  end

  @doc """
  The same, summed per ability — what `Rules.Abilities.scores_at/3` adds.

  Abilities nobody raised are absent rather than zero, so a caller can tell
  «nothing here» from «nothing at all» without comparing to zero.
  """
  @spec by_ability(Build.t(), map(), non_neg_integer()) :: %{Build.ability() => integer()}
  def by_ability(%Build{} = build, ruleset, level) do
    build |> terms(ruleset, level) |> Bonuses.group_sum(:ability, :bonus)
  end

  @doc """
  Sources this build has whose ability bonus the model does **not** count.

  Returns ids, sorted and deduplicated. The build turns them into
  `{:not_modelled, {:ability_bonus, id}}` — a rage, a defensive stance, a feat
  that merely lets a spell be cast. All of them are switched **off** by
  default, which is the line `Rules.ArmorClass` already draws for the same
  abilities (`_conditional_decision` in `vanilla/ac_bonuses.json`): showing a
  raging barbarian's strength on a barbarian who is standing still would
  overstate his attack and his damage in every fight and out of them.
  """
  @spec unmodelled(Build.t(), map(), non_neg_integer()) :: [atom()]
  def unmodelled(%Build{} = build, ruleset, level) do
    Bonuses.rejected_ids(build, ruleset, @markup, level)
  end

  @doc """
  То же, уже в виде гэпов билда.

  Форма живёт здесь, а не в `Rules.compute/2`: словарь стата принадлежит
  стату, и `Rules.Vocabulary` регистрирует именно эту форму.

  ⚠ У билда с варваром уже есть `{:not_modelled, {:class_change, :barbarian,
  "rage"}}` (шард переписал ярость и чисел не назвал) и `{:not_modelled,
  {:ac_bonus, :barbarian_rage}}`. Это третье утверждение про одну способность
  и не дубль ни одного из двух: одно говорит, что версия шарда не прочитана,
  второе — что её AC не посчитан, это — что не посчитаны сила и телосложение.
  """
  @spec gaps(Build.t(), map(), non_neg_integer()) :: [tuple()]
  def gaps(%Build{} = build, ruleset, level) do
    Bonuses.gaps(build, ruleset, @markup, level, &{:not_modelled, {:ability_bonus, &1}})
  end

  @doc """
  Whether the whole of what this feat does is already in the numbers.

  Asked by `Rules.FeatChoices.gaps/3` before it says «прибавку от фита в статы
  не считаем» about a repeatable feat. Once `Great strength`'s ten points are
  counted **and named** in the breakdown, that caveat argues with a term the
  player can see, and a caveat that argues with the screen is worse than none.

  The claim is the data's (`effect_coverage: "whole_feat"`), never inferred
  from the bonus being applied — same contract as
  `Rules.FeatBonuses.whole_effect_counted?/1`, which answers the same question
  for hit points.
  """
  @spec whole_effect_counted?(atom(), map()) :: boolean()
  def whole_effect_counted?(feat_id, ruleset) do
    Bonuses.whole_effect_counted?(ruleset, @markup, feat_id)
  end

  # ⚠ Two clauses of `amount/3` and no catch-all, deliberately. Which kinds may
  # reach an applied record is enforced where the data is read (`Loader`'s
  # `@applied_ability_bonus_kinds`, which raises at **compile** time on
  # anything else), so an unmatched shape here is a broken build and not a live
  # request. A fallback returning `[]` would turn that into the one failure
  # this module exists to prevent: a bonus that quietly counts for nothing.

  # Another slot spent is another take, **and so is an item that lends the feat**
  # (`Build.feat_takes_owned/4`, Dan 09.08.2026): a slot plus an amulet is two
  # takes. The ceiling is on the effect, so it is applied to the sum: a build
  # holding eleven takes gets the +10 the page names, not +11.
  #
  # ⚠ `max(…, 1)` because this walks the feats the character **owns**, and one may
  # be owned with no take behind it: a class handed it over. No class hands out a
  # `Great …` today, so the floor is a guard rather than a live rule — but without
  # it such a feat would be owned and worth nothing at all, which is the silent
  # zero this file exists to prevent. The same floor `Rules.FeatBonuses` keeps,
  # and for the same reason.
  defp amount(%{amount: %{kind: :per_take} = amount} = record, build, ruleset, level) do
    takes = max(Build.feat_takes_owned(build, ruleset, record.id, level), 1)
    total = takes * amount.bonus

    [
      %{
        id: record.id,
        source: record.source,
        ability: amount.ability,
        bonus: min(total, amount.max_total),
        takes: takes,
        capped?: total > amount.max_total
      }
    ]
  end

  # ⚠ Steps are **summed** here, the opposite reading from
  # `Bonuses.total_at_step/2` which armour class and the saves use for their own
  # class tables: `+2` strength at class level 2 and again at 4 is `+4`. Both
  # columns come off the same wiki page and are printed differently, so each
  # data file states its own reading — see `Bonuses.total_at_step/2`'s doc for
  # the pair. Past the last step nothing more is added: the table simply ends,
  # and a Red Dragon Disciple's epic levels have no such column at all.
  defp amount(
         %{amount: %{kind: :ability_at_class_level} = amount} = record,
         build,
         _ruleset,
         level
       ) do
    reached = Bonuses.class_level(build, amount.class, level)

    amount.gains_at_class_level
    |> Enum.filter(fn {step, _gains} -> step <= reached end)
    |> Enum.reduce(%{}, fn {_step, gains}, acc ->
      Map.merge(acc, gains, fn _ability, a, b -> a + b end)
    end)
    |> Enum.sort()
    |> Enum.map(fn {ability, bonus} ->
      %{
        id: record.id,
        source: record.source,
        ability: ability,
        bonus: bonus,
        takes: 1,
        capped?: false
      }
    end)
  end
end
