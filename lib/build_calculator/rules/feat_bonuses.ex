defmodule BuildCalculator.Rules.FeatBonuses do
  @moduledoc """
  What a build adds to its **hit points** beyond dice and constitution.

  Today that is `Toughness` and `Epic toughness`, out of the hand-written
  `priv/rules/vanilla/feat_hp_bonuses.json` (task 1.9). Both arrive off a feat,
  and three other kinds of source are possible in the schema (a class table, a
  skill, a racial trait) — none of them occurs in the corpus, and that is a
  finding of the file's own sweep rather than a limitation here.

  ## Nothing here knows a feat by name

  Which feats add hit points, how much, and in what shape is data. There is no
  list of feat ids in this file and there must never be one: the day the shard
  rewrites `Toughness`, the answer has to come from `priv/rules/`, not from a
  clause somebody remembered to add.

  ## Three shapes, and why they are not one number

    * **per character level** — `Toughness`. Counted off feats the character
      **owns**: picked in a slot *or* handed over by a class, because a feat is
      a feat however it arrived, and on Siala nine classes hand this one out at
      their own first level. Retroactive by the source's own words, so the
      character level is the whole of the argument — not the level it was taken
      on.
    * **per take** — `Epic toughness`. Counted off the takes the character has
      (`Build.feat_takes_owned/4`): every slot spent on it, plus one for an item
      that lends it, because that is what another take *is* and Dan reads an
      item's copy as one («Это будет +2», 09.08.2026). The effect ceiling the
      page states («up to a maximum of 200 hit points») is applied to the sum.
      ⚠ That ceiling is a different fact from the ceiling on the number of
      takes (`repeatable.max_takes`, ten, from Dan): one is the page's, the
      other is the player's, and a build may carry one without the other — the
      vanilla ruleset has no take ceiling at all.
    * **per class level** — `Deathless vigor`. Described in the data,
      deliberately **not** applied here: it is a class ability that grows with
      a class level (task 3.11), and the loader refuses to let such a record be
      marked `applied` precisely so it cannot contribute a silent zero. A build
      that owns such a feat says so instead — `unmodelled/3`.

  ## Что здесь своё, а что общее

  Общее — всё, кроме `hp_term/3`: чтение файла по вердикту, гейт владения, сбор
  гэпов из отвергнутых и `effect_coverage` живут в
  `BuildCalculator.Rules.Bonuses` (задачи 3.21 и 3.25). Своего осталось ровно
  два пункта, и оба про хиты, а не про плумбинг:

    * **три формы величины** и, главное, деление вклада на `per_level` и `flat`
      — вопрос про пол в один хит за уровень (ниже), которого нет ни у одного
      другого стата;
    * **счёт взятий** (`Build.feat_takes_owned/4`) с потолком эффекта — тоже
      только здесь: у пяти остальных статов повторяемых применяемых записей нет.

  Стороны капа здесь нет, и это не пропуск: потолка на HP не объявляет ни один
  ruleset, а `cap` у записи этого файла роняет сборку — см. `_cap_decision` в
  самом файле.

  ⚠️ **Здесь стояла оговорка «`applied/2`, `held?/5` и сторона капа — не общие, и
  это разница в данных, не в коде»** (задача 3.21 правки данных делать права не
  имела). Закрыто задачей 3.25: загрузчик больше не вливает файл в поля фита
  (`ruleset.feats[id].hp_bonus` и два соседа удалены), записи лежат списком под
  `ruleset.hp_bonuses`, и обход шестого стата — тот же, что у пяти остальных.

  ## Where the per-level term goes relative to the floor

  Inside it. A level is worth `max(1, hit die + CON modifier + per-level feat
  bonuses)`, not `max(1, hit die + CON modifier)` plus the feats, and the
  source says so outright: «There is a minimum of 1 hit point for each level,
  though, after combining the base and bonus hit points associated with that
  level» (`fandom:Hit point`, revid 62785), in the same paragraph that lists
  `Toughness` among the sources of bonus hit points. The two readings differ
  exactly where the floor bites — a d4 caster at a −4 constitution modifier
  gains one hit point per level with `Toughness` and without it — so the choice
  is stated in the data file (`_floor_decision`) rather than made quietly here.
  `Progression.hit_points/3` is what applies it; this module only says which
  part of the total is per level and which is flat.
  """

  alias BuildCalculator.Rules.{Bonuses, Build}

  @markup :hp_bonuses

  @typedoc """
  One source's contribution to hit points.

    * `feat` — the record's own id, for the breakdown
    * `per_level` — added to **every** character level, inside the floor
    * `flat` — added to the total once, after the floor
    * `takes` — how many slots went on it (`1` for a feat that does not repeat)
    * `capped?` — the stated ceiling on the effect was reached
  """
  @type hp_term :: %{
          feat: atom(),
          per_level: integer(),
          flat: integer(),
          takes: pos_integer(),
          capped?: boolean()
        }

  @doc """
  Every hit-point term this build's feats contribute, in the data's own order.

  Only records the ruleset marks as `applied` in `vanilla/feat_hp_bonuses.json`
  produce a term; a feat whose bonus the model refuses to work out is
  `unmodelled/3`'s business, and a feat with no entry at all contributes
  nothing and is not a hole (most feats do not touch hit points).

  ⚠ In the data's order, not sorted by id — that is `Bonuses.applied/2`'s
  contract and it changed here with task 3.25: the breakdown now prints
  `Toughness` before `Epic toughness`, the order a human wrote them in, rather
  than the alphabet's.
  """
  @spec hit_points(Build.t(), map(), non_neg_integer()) :: [hp_term()]
  def hit_points(%Build{} = build, ruleset, level) do
    for record <- Bonuses.held(build, ruleset, @markup, level),
        term = hp_term(record, build, ruleset, level),
        term.per_level != 0 or term.flat != 0 do
      term
    end
  end

  # ⚠ Three clauses and no catch-all, deliberately. Which kinds may reach an
  # `applied` record is enforced where the data is read (`Loader`'s
  # `@applied_hp_bonus_kinds`, which raises at **compile** time on anything
  # else), so an unmatched shape here is a broken build, not a live request. A
  # fallback clause returning zero would turn that into the one failure this
  # module exists to prevent: a bonus that quietly counts for nothing.

  # One bonus hit point per character level, for as long as the character has
  # the feat — and the level here is the character level the whole computation
  # is scoped to, so a truncated build (which is how every delta is computed)
  # answers for the ladder it actually has.
  defp hp_term(%{id: id, amount: %{kind: :per_character_level, hp: hp}}, _build, _ruleset, _level) do
    %{feat: id, per_level: hp, flat: 0, takes: 1, capped?: false}
  end

  # Another slot spent is another take, **and so is an item that lends the feat**
  # (`Build.feat_takes_owned/4`): a slot plus an amulet is two takes of `Epic
  # toughness` and forty hit points, which is Dan's own reading of it («Это будет
  # +2», 09.08.2026). The ceiling is on the **effect**, so it is applied to the sum
  # rather than to the count: a build that somehow holds eleven takes gets the 200
  # the page names, not 220.
  #
  # ⚠ Matched on `source: {:feat, id}` and not on the id alone, and that is the
  # guard rather than pedantry: takes are a property of a **feat**, and a record of
  # this shape keyed by a class table or a racial trait would have no takes to
  # count — `feat_takes_owned/4` would answer zero and `max(…, 1)` would turn it
  # into a plausible single take. No such record exists; an unmatched clause is how
  # it stays that way.
  #
  # ⚠ `max(…, 1)` still, and now only for the one case it was always about: a feat
  # the character **owns** with no take behind it, i.e. one a class handed over. No
  # class hands out a per-take hit point feat today, so the floor is a guard rather
  # than a live rule — but without it such a feat would be owned and worth nothing
  # at all, which is the silent zero this whole file exists to prevent. The gear
  # half no longer relies on it: an item's take is counted, not floored.
  defp hp_term(
         %{source: {:feat, id}, amount: %{kind: :per_take, hp: hp, max_total: max_total}},
         build,
         ruleset,
         level
       ) do
    takes = max(Build.feat_takes_owned(build, ruleset, id, level), 1)
    total = takes * hp

    %{
      feat: id,
      per_level: 0,
      flat: min(total, max_total),
      takes: takes,
      capped?: total > max_total
    }
  end

  # Steps by the named class's own level: `Deathless vigor` hands the Pale Master
  # +3 at each of his class levels 5..10 and +5 at 15, 20, 25, 30. Every step the
  # build has **reached** is summed, which is what makes the shape different from
  # the two above — the argument is neither the character level nor the number of
  # takes, and folding it into either would be wrong at both ends (3 at Pale
  # Master 5, 38 at 30).
  #
  # ⚠ Not retroactive and not per level, and the table is what says so: the feat's
  # own description reads «+3 hit points per level», which taken literally gives
  # 90 at class level 30 instead of 38. The steps come from the class progression
  # table and the feat's Notes, which agree with each other and not with that one
  # sentence (`vanilla/feat_hp_bonuses.json` → `deathless_vigor`).
  #
  # ⚠ `class_levels/2` is scoped to `level`, so a truncated build — which is how
  # every delta is computed — counts the steps it had at that point and no more.
  defp hp_term(
         %{id: id, amount: %{kind: :per_class_level, class: class, hp_at_class_level: steps}},
         build,
         _ruleset,
         level
       ) do
    reached = build |> Build.class_levels(level) |> Map.get(class, 0)
    flat = for {at, hp} <- steps, at <= reached, reduce: 0, do: (sum -> sum + hp)

    %{feat: id, per_level: 0, flat: flat, takes: 1, capped?: false}
  end

  @doc """
  Sources this build has whose hit-point bonus the model does **not** count.

  Returns ids, sorted. The build turns them into
  `{:not_modelled, {:feat_hp_bonus, id}}`, which is the same contract the skill
  side keeps: what is short has a name, instead of the total looking like a
  miscalculation.
  """
  @spec unmodelled(Build.t(), map(), non_neg_integer()) :: [atom()]
  def unmodelled(%Build{} = build, ruleset, level) do
    build |> Bonuses.rejected_ids(ruleset, @markup, level) |> Enum.sort()
  end

  @doc """
  То же, уже в виде гэпов билда.

  Форма живёт здесь, а не в `Rules.compute/2`: словарь стата принадлежит стату,
  и `Rules.Vocabulary` регистрирует именно эту форму.

  ⚠ **Владеет, а не взял слотом.** Такие фиты выдаёт класс, а не слот, так что
  подсчёт по взятиям не сообщил бы ни об одном — ровно та ловушка, в которую на
  применённой стороне попал `Toughness` (девять классов выдают его сами, и
  слотом его не берёт никто).

  ⚠ **Сегодня эта функция не возвращает ничего ни на одном билде**, и это
  проверенный факт, а не догадка: в `vanilla/feat_hp_bonuses.json` не осталось
  ни одной записи с вердиктом `not_modelled`. Здесь стояло «`Deathless vigor`
  (ступени по уровню Бледного Мастера) и `Hit die increase` (растущий хит-дайс,
  из-за которого у билда с Учеником красного дракона нет HP вовсе)» — первый
  посчитан замером D1 (13.08.2026), второй перестал быть прибавкой ФИТА вовсе
  (задача 3.37, 16.08.2026): растущий дайс лежит у КЛАССА
  (`Progression.hit_die/3`), а запись фита стала `counted_elsewhere`. Механизм
  при этом жив и нужен: новая запись с этим вердиктом включит его обратно,
  и `FeatHpBonusesTest` проверяет обе стороны на подменённой разметке.
  """
  @spec gaps(Build.t(), map(), non_neg_integer()) :: [tuple()]
  def gaps(%Build{} = build, ruleset, level) do
    for feat_id <- unmodelled(build, ruleset, level),
        do: {:not_modelled, {:feat_hp_bonus, feat_id}}
  end

  @doc """
  Whether the whole of what this feat does is already in the numbers.

  Asked by `Rules.FeatChoices.gaps/3` before it says «прибавку от фита в статы
  не считаем» about a repeatable feat: once `Epic toughness`'s twenty hit
  points are counted **and named** in the breakdown, that caveat contradicts a
  term the player can see, and a caveat that argues with the screen is worse
  than none.

  The claim is the data's (`effect_coverage: "whole_feat"`), never inferred
  from the bonus being applied: a feat may add hit points *and* do something
  else, and silence about the something else has to keep costing a caveat.

  ⚠ `/2` since task 3.25, and the argument changed shape as well as arity: it
  used to take the feat **map** and read a field the loader poured into it
  (`hp_bonus_covers_feat?`). Now it takes the id and asks the markup, exactly
  like its three siblings (`Rules.AbilityBonuses`, `Rules.SaveBonuses`,
  `Rules.AttackBonuses`).
  """
  @spec whole_effect_counted?(atom(), map()) :: boolean()
  def whole_effect_counted?(feat_id, ruleset) do
    Bonuses.whole_effect_counted?(ruleset, @markup, feat_id)
  end
end
