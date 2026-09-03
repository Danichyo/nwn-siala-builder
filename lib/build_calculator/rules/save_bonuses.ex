defmodule BuildCalculator.Rules.SaveBonuses do
  @moduledoc """
  What the **build itself** adds to Fort/Ref/Will, as opposed to what the
  player types under "Вещи" or Spellcraft's ranks (`Rules.Skills.save_bonus/3`).

  Before task 1.12a `Rules.compute/2` summed exactly those two sources into
  every save — both save-agnostic, both landing on Fort, Ref and Will
  identically — and `Iron will`, `Divine grace`, `Sacred defense` and their
  siblings were not in the numbers at all, and not in a gap either: the
  honesty mechanism had a form for the one source that already counted
  (`{:not_modelled, {:save_bonus_scope, :spellcraft}}`) and nothing for the
  ones that did not, on a Paladin — one of the shard's popular classes.

  ## Nothing here knows a feat, class, skill or race by name

  Which of them raises a saving throw, by how much and which of the three it
  lands on is data — `priv/rules/vanilla/feat_save_bonuses.json`, read by
  `BuildCalculator.Data.Loader`. There is no `iron_will`, no `paladin` and no
  `halfling` in this file, and there must never be one.

  ## Three shapes, and why they are not one number

    * **flat** — `Iron will` (+2 Will), `Luck of heroes` (+1, all three). A
      number, while the character has the thing.
    * **ability modifier** — `Divine grace`, `Dark blessing`. The whole of
      charisma's modifier, landing on all three saves at once. ⚠ Computed
      off the modifiers the caller passes in (the geared ones — unlike
      armour class, a save has no "голым"/"в шмоте" pair in this engine, so
      there is only one to pass). One of the two carries a `floor`: `Divine
      grace`'s own page says "(if positive)" and its Notes section spells
      out the alternative by contrast — a negative charisma modifier adds
      nothing there, and *does* subtract under `Dark blessing`, which the
      wiki states as the point of difference between two otherwise
      identical feats. Read the data file's `_amount_kinds` before assuming
      the two are interchangeable.
    * **at class level** — `Sacred defense`, the only record of this shape.
      A table of `class level => total at that level`, read the same way
      `Rules.ArmorClass`'s `ac_at_class_level` is (the wiki's own column
      prints a running sum, not a per-step increment — the opposite reading
      from `Rules.AbilityBonuses`'s `ability_at_class_level` next door, and
      each file states its own).

  ## What is owned, and by what

  A feat counts when the character **owns** it — picked in a slot or handed
  over by a class, because a feat is a feat however it arrived (`Divine
  grace` and `Dark blessing` both arrive by grant, and Siala moves the grant
  from level 1/2 to level 4 without touching the amount — ownership already
  reads through the shift). A class table counts from the class's own level.
  A skill counts once the build has ranks in it, the same scoping
  `Rules.compute/2` already uses for the shard's other skill caveats. A
  racial trait counts off the race, never off `Build.feats_owned/3` — the
  same reason `Rules.ArmorClass` keeps them apart: `Lucky` is a `type: race`
  feat in the data, not a general one, and widening what counts as "owned"
  would change every prerequisite check in the application.

  ## No `type` field, unlike `Rules.ArmorClass`

  Armour class genuinely has bonus types in this engine — natural, dodge,
  deflection — with real stacking and ceiling consequences. No source this
  file's sweep found ever names a save bonus a type word the way tabletop
  D&D would ("resistance bonus", "luck bonus"); the engine appears to just
  sum every source into one number. So there is nothing here to type and no
  stacking rule to guard.

  ## Where the ceiling lives, and it is not here

  `stat_caps.saving_throw_bonus` (+20) applies to the combined total of every
  source landing on one save **that it covers** — clipped **once per save**, not
  once per source (CLAUDE.md §9: clipping gear and Spellcraft separately used to
  let a build carry +40 while every source said +20; the same bug, in the same
  shape, is what a per-source clip here would reproduce with three sources
  instead of two). `terms/3` returns the **raw**, uncapped contribution;
  `Rules.compute/2` is where the one clip per save happens, and where the terms
  are summed per save (`save_totals/1` — with all three keys present even at
  zero, which is why there is no `by_save/3` here any more).

  ⚠ **It does not cover most of what this module returns** (09.08.2026, Dan,
  `source: user`): «У сейвов тоже фиты не входят в кап +20. Можешь взять и luck of
  heroes, и форту +2, и форту +4, и потом ещё с вещей набрать +20». Of the
  fourteen `applied` records exactly **one** is inside the ceiling — `Sacred
  defense` — and the other thirteen sit on top of it. Gear and Spellcraft stay
  inside, each with its own citation.

  ⚠ **And that side is a property of the record, not of its kind.** `Divine grace`
  and `Sacred defense` are both class abilities, both written in the data in the
  shape of a feat, and Dan put one outside the +20 and the other inside — which is
  what killed the model this file carried for a few hours, "the side belongs to the
  source kind". Each term therefore carries `under_cap?`, read off the record
  (`Rules.Caps.covers_record?/3`) and never decided here.

  ⚠ **What was wrong before, and why it looked right.** The save ceiling has a
  verbatim quote — `fandom:Uncanny dodge`, «subject to the +20 saving throw cap» —
  and on 08.08.2026 that quote was written into the project's own notes as proof
  that the asymmetry with attack was deliberate and must not be "harmonised". The
  quote is real; it is about **one** class ability (a narrow reflex-vs-traps bonus
  this file rejects as `not_modelled`), and it was stretched to cover every feat.
  A cited scope about one source is not a rule about every source of that kind —
  the same mistake the attack markup had made a day earlier, in the same words.

  ⚠ Live numbers this moved, not hypotheticals: a Fighter 41 with `Luck of
  heroes` + `Great fortitude` + `Epic fortitude` and +20 worth of gear had Fort
  **42** and has **49**; a goblin's racial `+1` no longer vanishes into a ceiling
  the moment gear reaches +20 (that was `GAME_CHECKS.md` I1, closed by the
  owner's word rather than a measurement).

  ## Прибавка в ЧИСЛЕ и прибавка в ТРЕБОВАНИИ — разные вопросы

  С 17.08.2026 (задача S3) у записи есть второй признак рядом со стороной капа:
  идёт ли её прибавка в число, с которым сравнивается **требование** фита по
  сейву. Тринадцать записей идут, `Luck of heroes` — нет: его исключает
  поимённо страница фита-получателя («The fortitude bonus from ''luck of
  heroes'' does not count towards the fortitude required», `fandom:Resist
  energy`), и **замер Dan подтвердил это на Сиале** — воин 9 с телосложением 12
  и взятой Удачей имеет Стойкость 8 при требовании 8, а фита в игре нет; на
  12-м, где базовой Стойкости хватает и без Удачи, фит есть.

  ⚠ **Эффект при этом не меняется ни на единицу.** Удача по-прежнему даёт +1 ко
  всем трём сейвам, стоит своей строкой в разборе и участвует в клипе. Требование
  и эффект — разные вопросы, и один источник отвечает на них по-разному; ровно
  та же граница, что у вещей (S1/S2) и у фита с предмета (H7).

  ⚠ И это **второй** признак подряд, который принадлежит записи, а не виду
  источника. Обобщить строку до «прибавки фитов в требование не идут» значило бы
  повторить ошибку, на которой дважды сломался потолок: цитата про один источник
  не есть правило про все источники того же вида. Умолчание — «идёт» — объявлено
  один раз в самих данных (`_prerequisite_decision`), а не выбирается здесь.

  ## Что здесь своё, а что общее

  Чтение файла, «держит ли персонаж эту запись», сбор гэпов из отвергнутых и
  `effect_coverage` — общие для пяти статов и живут в
  `BuildCalculator.Rules.Bonuses` (задача 3.21). Здесь остаётся специфика
  сейвов, и её ровно три пункта: **три** цели у одной записи, `floor` у
  модификатора характеристики и сторона капа на каждом терме. Клип по-прежнему
  не здесь — он один на сейв и живёт в `Rules.compute/2`.
  """

  alias BuildCalculator.Rules.{Bonuses, Build, Caps}

  @markup :save_bonuses

  @typedoc """
  One source's contribution to one saving throw.

    * `id` — the feat, class, skill or racial trait, for the breakdown and
      the gaps
    * `source` — `{:feat, id}` / `{:class, id}` / `{:skill, id}` /
      `{:race_feat, id}`
    * `save` — which of `:fort` / `:ref` / `:will`
    * `bonus` — the contribution, already worked out for this build
    * `under_cap?` — whether `stat_caps.saving_throw_bonus` covers this record at
      all. Thirteen of the fourteen do not (09.08.2026); a breakdown needs it to
      place the row, because a term the ceiling never touched printed above the
      «сверх капа» line would blame it for a loss it did not take
    * `counts_for_prereqs?` — идёт ли эта прибавка в число, с которым
      сравнивается **требование** фита по сейву. Тринадцать из четырнадцати
      идут; `Luck of heroes` не идёт (задача S3, 17.08.2026). ⚠ Второй признак
      подряд, который принадлежит **записи**, а не виду источника, и по той же
      причине: и здесь источник называет один фит поимённо
  """
  @type term_entry :: %{
          id: atom(),
          source: {atom(), atom()},
          save: :fort | :ref | :will,
          bonus: integer(),
          under_cap?: boolean(),
          counts_for_prereqs?: boolean()
        }

  @doc """
  Every saving-throw term this build earns by itself, in the data's own order.

  `modifiers` is the ability modifier map `ability_modifier` amounts are
  computed against — the build's final, geared modifiers, because a save has
  no naked/geared pair to choose between the way armour class does.

  One term per `(source, save)` pair: `Divine grace` raises all three and
  shows up as three terms, because the breakdown reads one save at a time
  (`Summary.save_summary_terms/5`). A source that works out to zero — a
  negative charisma modifier under `Divine grace`'s `floor` — is left out
  rather than listed as `+0`.
  """
  @spec terms(Build.t(), map(), %{atom() => integer()}) :: [term_entry()]
  def terms(%Build{} = build, ruleset, modifiers) do
    level = Build.character_level(build)

    for record <- Bonuses.held(build, ruleset, @markup, level),
        save <- record.saves,
        bonus = amount(record, build, modifiers),
        bonus != 0 do
      %{
        id: record.id,
        source: record.source,
        save: save,
        bonus: bonus,
        under_cap?: Caps.covers_record?(ruleset, :saving_throw_bonus, record),
        counts_for_prereqs?: counts_for_prereqs?(record)
      }
    end
  end

  @doc """
  Те же слагаемые, из которых убраны не идущие в **требование** по сейву.

  Требование фита сравнивается не с тем, что напечатано в листе: вещи из него
  выпадают целиком (задача S2, `Rules.compute/2` считает голым проходом), а
  внутри голого числа выпадает ещё и то, что исключил источник, — сегодня
  `Luck of heroes` (задача S3).

  ⚠ **Фильтр, а не вычитание готового числа.** Разность соблазнительно короче
  («итог минус исключённое»), и она неверна ровно там же, где было неверно
  «итог минус вещи»: потолок `stat_caps.saving_throw_bonus` стоит **внутри**
  формулы, и запись, попавшая под него, могла быть срезана целиком или наполовину
  — вычесть её сырое число значило бы отнять то, чего в итоге и не было.
  Сегодня единственная исключённая запись стоит **поверх** капа, то есть обе
  дороги дали бы одно и то же; но признак — свойство записи, и первая же
  внутрикапная запись с этим признаком развела бы их молча.

  Порядок и остальные поля не трогаются: это тот же список, только короче.
  """
  @spec for_prerequisites([term_entry()]) :: [term_entry()]
  def for_prerequisites(terms), do: Enum.filter(terms, & &1.counts_for_prereqs?)

  @doc """
  Кого из `applied`-записей источник исключил из требований по сейву — id, по
  порядку данных.

  Нужно **интерфейсу**, а не расчёту: отказ `{:requires_save_bonus, save, n}`
  печатается игроку, у которого в панели стоит ровно требуемое число, и без
  имени исключённого он читается как ошибка калькулятора. Ядро отдаёт список,
  русскую фразу вокруг него собирает веб-слой (`Builder.Labels`) — та же
  граница, что у всех прочих причин отказа.

  ⚠ Ответ **из данных**, а не из кода: имени фита здесь нет и быть не должно,
  и в тот день, когда шард (или замер) снимет признак, фраза исчезнет сама.
  """
  @spec not_counted_for_prerequisites(map()) :: [atom()]
  def not_counted_for_prerequisites(ruleset) do
    for record <- Bonuses.applied(ruleset, @markup),
        not counts_for_prereqs?(record),
        uniq: true,
        do: record.id
  end

  # Умолчание — «идёт», и оно объявлено в данных
  # (`feat_save_bonuses.json` → `_prerequisite_decision`), а не выбрано здесь:
  # запись, которая про требование молчит, требование выполняет. Загрузчик
  # пропускает ключ только у `applied` и только со `status: verified`, так что
  # `nil` здесь означает ровно «источник об этой записи ничего не сказал».
  defp counts_for_prereqs?(record) do
    case record do
      %{prereq: %{counts?: counts?}} -> counts?
      _ -> true
    end
  end

  # ⚠️ Здесь стояла `by_save/3` — «то же, но суммой по сейву», через
  # `Bonuses.group_sum/3`. Удалена 09.08.2026 (долг из AGENT_QUEUE §7), и не за
  # то, что её никто не звал, а за то, что **звать её было ловушкой**: у неё
  # сейв, которого никто не поднял, ОТСУТСТВУЕТ, а единственному потребителю
  # нужны все три ключа нулями — `Rules.compute/2` прибавляет к ней вещи и
  # Spellcraft, и пропущенный ключ читался бы как «нечего клипать», а не как
  # «ничего не заработано». Две записи одного факта с разной семантикой нуля
  # расходятся молча; поэтому осталась одна, и она у потребителя
  # (`Rules.save_totals/1`, там же и довод).
  #
  # ⚠️ Асимметрия с `Rules.AbilityBonuses.by_ability/3` намеренная и на месте:
  # ту зовёт `Rules.Abilities`, и ей «здесь ничего» ≠ «вообще ничего» как раз
  # нужно.

  @doc """
  Sources this build has whose save bonus the model does **not** count.

  Returns ids, sorted and deduplicated. The build turns them into
  `{:not_modelled, {:save_bonus, id}}` — a rage, a stance, a bonus narrowed to
  one kind of threat (poison, fear, a chosen school). Every one of them is
  either switched **off** by default (the same line `Rules.ArmorClass` draws
  for the very same abilities) or narrower than "every saving throw", which
  showing as a flat number would overstate exactly where the source is
  precise about *not* applying.
  """
  @spec unmodelled(Build.t(), map(), non_neg_integer()) :: [atom()]
  def unmodelled(%Build{} = build, ruleset, level) do
    Bonuses.rejected_ids(build, ruleset, @markup, level)
  end

  @doc """
  То же, уже в виде гэпов билда.

  Форма живёт здесь, а не в `Rules.compute/2`: словарь стата принадлежит
  стату. Каждая из этих способностей либо выключена по умолчанию — ту же
  линию `Rules.ArmorClass` и `Rules.AbilityBonuses` проводят для тех же самых
  способностей, — либо слишком узка, чтобы показываться плоским числом на
  всех трёх сейвах; это разные виды отказа, и второй завысил бы сейв ровно
  против того, про что источник точен, что он **не** покрывает.
  """
  @spec gaps(Build.t(), map(), non_neg_integer()) :: [tuple()]
  def gaps(%Build{} = build, ruleset, level) do
    Bonuses.gaps(build, ruleset, @markup, level, &{:not_modelled, {:save_bonus, &1}})
  end

  @doc """
  Whether the whole of what this feat does is already in the numbers.

  Same contract as `Rules.FeatBonuses.whole_effect_counted?/1` and
  `Rules.AbilityBonuses.whole_effect_counted?/2`: the claim is the data's
  (`effect_coverage: "whole_feat"`), never inferred from the bonus being
  applied. `Snake blood` and `Strong soul` are `applied` here and still say
  `false` — each has a second, narrower effect (an extra bonus against
  poison, against death magic) this module does not count, so the general
  "прибавку от фита не считаем" caveat has to keep costing something for
  them specifically.

  ⚠ No `applied` record in this file is `repeatable` today, so
  `Rules.FeatChoices.gaps/3`'s `effect_gap/3` — the only caller that asks
  this question — never reaches a save-bonus feat yet. Kept for the day one
  does, on the same terms its two siblings already are.
  """
  @spec whole_effect_counted?(atom(), map()) :: boolean()
  def whole_effect_counted?(feat_id, ruleset) do
    Bonuses.whole_effect_counted?(ruleset, @markup, feat_id)
  end

  # ⚠ Three clauses of `amount/3` and no catch-all, deliberately. Which kinds
  # may reach an applied record is enforced where the data is read (`Loader`'s
  # `@applied_save_bonus_kinds`, which raises at **compile** time on anything
  # else), so an unmatched shape here is a broken build and not a live
  # request. A fallback returning zero would turn that into the one failure
  # this module exists to prevent: a bonus that quietly counts for nothing.
  defp amount(%{amount: %{kind: :flat, bonus: bonus}}, _build, _modifiers), do: bonus

  defp amount(%{amount: %{kind: :ability_modifier} = amount}, _build, modifiers) do
    raw = Map.get(modifiers, amount.ability, 0)

    case Map.get(amount, :floor) do
      nil -> raw
      floor -> max(floor, raw)
    end
  end

  # The table states TOTALS — the same reading `Rules.ArmorClass` gives its
  # `ac_at_class_level`, and since task 3.21 literally the same code
  # (`Bonuses.total_at_step/2`), where the ⚠ about the opposite reading at
  # `Rules.AbilityBonuses` is stated once instead of three times.
  defp amount(%{amount: %{kind: :save_at_class_level} = amount}, build, _modifiers) do
    Bonuses.total_at_step(amount.save_at_class_level, Bonuses.class_level(build, amount.class))
  end
end
