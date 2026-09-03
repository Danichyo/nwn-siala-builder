defmodule BuildCalculator.Rules.GapReceivers do
  @moduledoc """
  Which shard facts count as a gap — «дырка в нашем ОТВЕТЕ, а не в знаниях».

  A fact off the shard's own class pages that the loader could not turn into a
  rule becomes `{:not_modelled, {:class_change, class, what}}` and travels into
  `ruleset.gaps` and into a build's own gap list; a fact off a feat page becomes
  `{:not_modelled, {:feat_change, feat, what}}` and travels the same two roads.
  That is the honesty mechanism of the project (CLAUDE.md §9) — an unshown gap
  is indistinguishable from a confident wrong answer — and it had one flaw: most
  of those facts were about mechanics the calculator **gives no answer about at
  all**. Damage, effect duration, immunities, summons, poisons, traps, movement
  speed, the familiar, class items, buffs. Nothing on any screen is wrong
  because of them, because nothing on any screen is about them.

  Dan, 10.08.2026: a gap is a hole in the **answer**, so a fact whose every
  receiver is something we never print is not one. Hence this module, and the
  `affects` field it reads.

  ## `affects` names the receiver, not the visibility

  In the data (`priv/rules/siala_41/classes.json`) each fact carries
  `"affects": ["damage"]` — **what the fact changes** — and never
  `"shown": false`, which would be an interface decision hammered into the data.
  The difference is not cosmetic: the day the core starts computing damage, those
  facts come back on their own, with nobody re-reading 89 records.

  The vocabulary is closed and lives in the data too (`_receivers.our` /
  `_receivers.not_our`, read into `ruleset.gap_receivers`). A receiver outside it
  fails the build — see `BuildCalculator.Data.Loader`; a typo like `"damge"` has
  no right to mean "do not show".

  ## Three rules, all pointing the same way — towards showing

    * **a fact with no `affects` is a gap.** A missing label may not go quiet:
      the forgotten record has to make noise, not disappear.
    * **one `our` receiver is enough.** `rogue / rogue_light` adds to Search
      *and* depends on an item; the Search half is ours, so the fact stays.
    * **a ruleset with no vocabulary filters nothing.** `vanilla` has no shard
      layer at all, and a `siala_41` whose `_receivers` went missing must
      over-report rather than fall silent.

  ## Why `ours?/2` is asked per fact and never per `(class, what)` pair

  The pair is **not** unique: 123 pairs cover 126 facts (Monk carries three
  `feat_level_shift` records, Assassin two), and Monk's three do not agree on
  `affects` — one names `ac`, two do not. "Take the fact with this pair" would
  make the answer depend on the order of lines in a JSON file, and one day a data
  edit would put out a gap silently.

  So the filter runs **fact by fact** and the gap tuples are deduplicated
  afterwards, exactly as they were before this module existed. That composition
  is the existential the rule asks for — the gap survives if *any* fact behind it
  names a receiver we print — and it cannot be knocked off by reordering.
  """

  @typedoc "A receiver id as the data spells it: `\"damage\"`, `\"hp\"`."
  @type receiver :: String.t()

  @typedoc """
  The closed vocabulary, as `ruleset.gap_receivers` carries it.

  `our` — what the constructor and the build page print; `not_our` — mechanics
  the calculator does not compute at all. Disjoint, and the loader raises if they
  ever overlap.
  """
  @type vocabulary :: %{our: MapSet.t(receiver()), not_our: MapSet.t(receiver())}

  @typedoc """
  How **one** shard layer's facts divide up, counted rather than remembered.

    * `total` — facts read off that layer of the shard
    * `labelled` — how many of them carry `affects` at all. ⚠ Not decoration:
      it is what says whether `ours` may be read as a classification (see below)
    * `applied` / `unapplied` — did the loader turn the fact into a rule
    * `ours` / `not_ours` — does the fact name at least one receiver we print
    * `gaps` — `unapplied` **and** `ours`: what the gap list reports for this
      layer, or would if it fed it — see `reported?`
    * `dropped` — `unapplied` **and** `not_ours`: what this filter takes out
    * `not_our_receivers` — `{receiver, facts}` over the `not_ours` facts, most
      frequent first, so a screen can name the categories instead of promising
      «прочее». Counted over `not_ours` and not over `dropped` on purpose: it is
      printed next to the `not_ours` number, and a list that adds up to a
      different total than the figure beside it is worse than no list
    * `reported?` — do this layer's gaps reach `ruleset.gaps`, i.e. the
      «перенесено не полностью — N пробелов» figure in the header. All three
      layers do, since 14.08.2026 (`@layers` below)

  ⚠ `not_ours` and `dropped` are two numbers and not one on purpose. They are
  equal only while every **applied** fact names a receiver we print, which is
  what one would expect (a fact that moved a number we show is about something
  we show) — and if they ever diverge, a label is wrong and the difference is the
  only thing that says so.

  ⚠ **`ours` is only a classification where `labelled == total`.** The rule
  «a fact with no label is a gap» (`ours?/2`) is a *safety* rule about gap-hood,
  and it counts an unlabelled fact as ours. On the class layer every fact is
  labelled, so `ours` there is read off the markup and means what it says. The
  skill layer joined it on 14.08.2026 — a skill record, like a class record and
  unlike a feat's, carries no machine-read `type` / `use` field of its own, so
  every one of its 53 facts was read by a human and every one carries `affects`
  — `skills.ours` is a real classification too, not the feat layer's safety net.
  On the feat layer only the facts that failed to apply are labelled — the other
  175 are the page's own `type` / `use` / `requirements` labels, which applied
  and therefore need no classification — so `feats.ours` is «one labelled ours
  plus everything unlabelled» and must not be printed as «столько фактов про
  наши числа». Print `applied` and `gaps` there instead: they say the same thing
  without claiming a reading nobody made.
  """
  @type layer :: %{
          total: non_neg_integer(),
          labelled: non_neg_integer(),
          applied: non_neg_integer(),
          unapplied: non_neg_integer(),
          ours: non_neg_integer(),
          not_ours: non_neg_integer(),
          gaps: non_neg_integer(),
          dropped: non_neg_integer(),
          not_our_receivers: [{receiver(), pos_integer()}],
          reported?: boolean()
        }

  @typedoc """
  Every shard layer that carries facts, counted the same way — see `t:layer/0`.

  Three keys and not one number: `total` means a different kind of thing per
  layer (126 class facts are prose a human transcribed, 196 feat facts are
  mostly the four bold labels a parser read off a page), so a sum of them would
  answer no question. A screen quoting these numbers has to name the layer.
  """
  @type census :: %{classes: layer(), feats: layer(), skills: layer()}

  @empty %{our: MapSet.new(), not_our: MapSet.new()}

  @doc """
  The closed vocabulary of a ruleset, or two empty sets when it carries none.

  Empty is not an error: `vanilla` has no shard layer, and with an empty `our`
  set `ours?/2` keeps every fact, which is the direction a missing vocabulary
  must fail in.
  """
  @spec vocabulary(map()) :: vocabulary()
  def vocabulary(ruleset) do
    case Map.get(ruleset, :gap_receivers) do
      %{our: our, not_our: not_our} -> %{our: our, not_our: not_our}
      _absent -> @empty
    end
  end

  @doc """
  Receivers the calculator prints — the set `ours?/2` expects.

  Fetched once per gap list rather than per fact: it is the same set for every
  fact of a ruleset.
  """
  @spec our(map()) :: MapSet.t(receiver())
  def our(ruleset), do: vocabulary(ruleset).our

  # Receivers that are about **getting** a feat rather than **having** one. The
  # data spells this one out — «доступность фита: слот, требование, уровень
  # автоматической выдачи» — and all three halves of that sentence are things
  # that happen on the ladder.
  #
  # ⚠ `class_availability` is deliberately **not** here, and the difference is a
  # measured game fact rather than symmetry: a feat lent by an item does open a
  # class («но вот КЛАСС можно взять», Dan 14.08.2026, `GAME_CHECKS.md` H7), so a
  # fact about a class's entry requirements is as true for a worn feat as for a
  # picked one. Only the feat's own availability is not.
  @acquisition MapSet.new(["feat_availability"])

  @doc """
  Receivers that answer «may this feat be acquired» and nothing else.

  Read by `held_ours?/2` on behalf of a feat the character **has without
  acquiring it** — today one caller, a feat declared under «Вещи»
  (`Rules.GearFeats`). An item lends what it lends: its prerequisites are not
  checked, no slot is spent and no class hands it over, so a shard fact whose
  only receiver we print is «предложит ли конструктор этот фит» has nothing to
  say to the player wearing it. A caveat about something that does not happen is
  the one failure mode this module exists to avoid, taken from the other side.

  ⚠ Everything else in `our/1` stays: what the feat *does* — hit points, AC,
  saves, skills, the attack roll — is counted for a worn feat exactly as for a
  picked one (Dan, 09.08.2026), so silence about an unapplied shard rewrite of it
  would be the ordinary hole in our answer.

  ⚠ A name from the data's closed vocabulary, and the only one this core spells
  out. `gap_receivers_test.exs` fails if the data stops carrying it, because a
  rename would silently widen the filter back rather than break anything.
  """
  @spec about_acquiring_a_feat() :: MapSet.t(receiver())
  def about_acquiring_a_feat, do: @acquisition

  @doc """
  `ours?/2` for a feat the character **holds without having acquired it**.

  Everything `ours?/2` decides, minus the facts that are ours *only* because
  they touch getting the feat — see `about_acquiring_a_feat/0` for why that one
  receiver drops out and no other does.

  Written as a composition rather than as `ours?/2` against a smaller set on
  purpose: an **empty** `our` means "no vocabulary, no filtering", so subtracting
  from a set until it empties would turn the filter off and report *everything*
  — the exact opposite of what the subtraction asks for. Composing keeps every
  unclear case answering `true`, as the table in `ours?/2` promises:

  | `affects` on the fact | `ours?/2` | here | why |
  |---|---|---|---|
  | `["feat_availability"]` | `true` | `false` | ours only by acquisition |
  | `["feat_availability", "hp"]` | `true` | `true` | one other receiver is enough |
  | `["feat_availability", "damage"]` | `true` | `false` | the rest is not ours either |
  | `["hp"]` | `true` | `true` | untouched |
  | field absent | `true` | `true` | a missing label may not go quiet |
  | any, with `our` empty | `true` | `true` | no vocabulary, no filtering |
  """
  @spec held_ours?(map(), MapSet.t(receiver())) :: boolean()
  def held_ours?(fact, our) when is_map(fact) do
    ours?(fact, our) and not only_about_acquiring?(fact, our)
  end

  # Ours by acquisition alone: at least one receiver we print, and every one of
  # those about getting the feat. Receivers we do not print are ignored here —
  # they cannot make the fact ours in the first place, so they cannot save it.
  defp only_about_acquiring?(fact, our) do
    case fact["affects"] do
      receivers when is_list(receivers) and receivers != [] ->
        printed = Enum.filter(receivers, &MapSet.member?(our, &1))

        printed != [] and Enum.all?(printed, &MapSet.member?(@acquisition, &1))

      _unlabelled ->
        false
    end
  end

  @doc """
  Does this shard fact touch something the calculator answers about?

  `fact` is the raw change record (`%{"what" => …, "affects" => […]}`), `our` the
  set from `our/1`. `true` means "keep it as a gap", and every unclear case
  answers `true`. With `our = MapSet.new(["hp"])`:

  | `affects` on the fact | answer | why |
  |---|---|---|
  | `["hp"]` | `true` | ours |
  | `["hp", "damage"]` | `true` | one ours is enough |
  | `["damage"]` | `false` | nothing we print |
  | field absent | `true` | a missing label may not go quiet |
  | `[]` | `true` | same, and the loader refuses to load it anyway |
  | any, with `our` empty | `true` | no vocabulary, no filtering |

  The table is `test/build_calculator/rules/gap_receivers_test.exs`, case for
  case.
  """
  @spec ours?(map(), MapSet.t(receiver())) :: boolean()
  def ours?(fact, our) when is_map(fact) do
    receivers = fact["affects"]

    cond do
      # ⚠ РЕШЕНИЕ ВЛАДЕЛЬЦА, а не метка получателя — задача 3.74 (21.08.2026).
      # Механика в игре есть и получателя своего не меняет (`affects` у такого
      # факта остаётся честным), но до НАШЕГО ответа она не доезжает, и Dan
      # сказал это словами. Первый случай — требование клирика держать символ
      # веры в левой руке: на Сиале символ вешается на само оружие, значит
      # запрета щита нет вовсе, и применить тут было бы нечего — а «применить»
      # означало бы ОТНЯТЬ у игрока щитовой AC по выдуманному правилу.
      #
      # 🔴 Почему отдельным полем, а не правкой `affects`: `affects` называет
      # ПОЛУЧАТЕЛЯ, а не видимость (CLAUDE.md §9), и подкрутить его значило бы
      # соврать о природе факта ради числа в баннере. Ровно та же граница, что
      # у `"modelled": false` в условиях `attack_modifiers` (задача 3.72):
      # решение не спрятать, а назвать — с автором, датой и доводом, которых
      # требует сторож загрузчика.
      is_map(fact["not_a_gap"]) -> false
      # Словаря нет — фильтра нет вовсе (vanilla, синтетический ruleset).
      MapSet.size(our) == 0 -> true
      # Метки нет или она пуста — факт остаётся гэпом.
      not is_list(receivers) or receivers == [] -> true
      # И хватает одного нашего получателя из сколь угодно многих.
      true -> Enum.any?(receivers, &(&1 in our))
    end
  end

  @doc """
  Keeps the facts that are a gap in our answer, in order.

  The one place the rule is applied, so the ruleset-wide list and a build's own
  list cannot drift apart.
  """
  @spec filter([map()], MapSet.t(receiver())) :: [map()]
  def filter(facts, our), do: Enum.filter(facts, &ours?(&1, our))

  @doc """
  `ours?/2` for a record of the six **bonus markup** files
  (`priv/rules/vanilla/*_bonuses.json`), which spell the field the same way and
  carry it under a different key.

  A shard fact arrives as raw JSON (`%{"affects" => […]}`); a markup record
  passes through `Data.Loader`, which atomises the keys around it but leaves the
  receivers themselves as the source spells them. So the shapes differ by one
  key and by nothing else, and the answer must not differ at all — hence an
  adapter over `ours?/2` and not a second copy of the rule.

  ⚠ Ровно **одно** место в проекте, читающее `affects` с записи разметки: до
  17.08.2026 обёртка `%{"affects" => record.affects}` стояла в загрузчике,
  а четыре стата из шести не читали поле вовсе — то есть разметка у них
  была материалом, а не фильтром. Две формы одного чтения — это две
  возможности разойтись, и расходятся они молча.

  ⚠ `Map.get/2`, а не `record.affects`, и обе неудачи ведут в одну сторону:
  поле пустое (до 18.08.2026 — у всех 21 отвергнутой записи
  `feat_save_bonuses.json`, единственного из шести файлов, который разметку
  получил последним) или ключа нет вовсе (синтетическая запись в тестах
  статов, и живая запись любого файла, у которого not_modelled-записей нет
  вовсе — `feat_hp_bonuses.json`). Ответ и там, и там — «метки нет», то есть
  гэп остаётся; падать на живых данных или молча гасить оговорку эта функция
  не имеет права.
  """
  @spec bonus_ours?(map(), MapSet.t(receiver())) :: boolean()
  def bonus_ours?(record, our) when is_map(record), do: record_ours?(record, our)

  @doc """
  `ours?/2` for any record whose label and owner decision are **atom-keyed
  fields beside it**, rather than the raw JSON of a shard fact.

  Two families arrive in that shape, and they are the same shape rather than two
  similar ones:

    * a record of the six bonus-markup files (`bonus_ours?/2`, task 3.76);
    * a statement about a class group — what one of its benefits changes, and
      whether the owner has decided its unwritten purity rule is no gap
      (`Rules.ClassGroups`, task 3.100).

  ⚠ **Решение владельца едет тем же адаптером.** Иначе у одного и того же
  вопроса («обязаны ли мы признаться») оказалось бы два разных ответа: у факта
  класса `not_a_gap` читается, у записи разметки нет. Ровно тот же довод, по
  которому четыре копии сторожа этого поля свелись в `Loader.NotAGap`.

  ⚠ Оба поля необязательны, и обе неудачи ведут в сторону **показа**: нет метки
  — запись остаётся гэпом, нет решения — тоже. `Map.get/2`, а не точечный
  доступ: запись, у которой ключа нет вовсе, законна (см. `bonus_ours?/2`).
  """
  @spec record_ours?(map(), MapSet.t(receiver())) :: boolean()
  def record_ours?(record, our) when is_map(record),
    do:
      ours?(
        %{
          "affects" => Map.get(record, :affects),
          "not_a_gap" => Map.get(record, :not_a_gap)
        },
        our
      )

  @doc """
  `ours?/2` for **what a feat's own effect changes**, looked up by feat id
  (`priv/rules/vanilla/feat_effect_receivers.json` → `ruleset.feat_effect_receivers`).

  The third adapter over one rule, beside `bonus_ours?/2`, and the reason it
  takes the whole ruleset instead of a record is that the **lookup** is the part
  that must not be written twice. Two callers ask this question about the same
  feat from two directions and have to agree:

    * `Rules.FeatChoices.gaps/3` — «прибавку от этого фита в статы не считаем»
      (task 3.93);
    * `Rules.GearFeats.gaps/2` — «вещь не сказала, с каким значением фит взят»
      (task 3.98).

  ⚠ They disagreed, and that is what this function is for. A worn `Spell focus`
  said nothing about its bonus (the school moves a save DC, which the calculator
  does not print) and in the same breath confessed it did not know the school —
  one feat, one piece of ignorance, two positions on one screen. ⚠ The gap opened
  the moment task 3.93 taught the first caller to ask and left the second one
  alone: **the same day**, one commit apart. A private copy of a lookup does not
  need years to drift.

  ⚠ **`ours?/2` and not `held_ours?/2`**, deliberately. `held_ours?/2` drops
  `feat_availability`, which is a receiver about *acquiring* a feat; this
  dictionary labels what a feat's **effect** touches, so that receiver cannot
  appear on it truthfully, and using the narrower question here would be the
  second way for the two callers to drift.

  ⚠ Missing entry, missing dictionary and an empty vocabulary all answer `true`
  — the direction `ours?/2` promises, and here it means "keep the caveat".
  """
  @spec feat_effect_ours?(atom(), map()) :: boolean()
  def feat_effect_ours?(feat_id, ruleset) when is_atom(feat_id) do
    ruleset
    |> Map.get(:feat_effect_receivers, %{})
    |> Map.get(feat_id, %{})
    |> ours?(our(ruleset))
  end

  @doc """
  `filter/2` for a feat held without being acquired — see `held_ours?/2`.

  A sibling with the same shape rather than an option, so a caller picks the
  question by name: `Rules.shard_feat_gaps/3` hands the picked feats to
  `filter/2` and the declared ones here, in two lines that read as two
  different questions.
  """
  @spec filter_held([map()], MapSet.t(receiver())) :: [map()]
  def filter_held(facts, our), do: Enum.filter(facts, &held_ours?(&1, our))

  # Whether a layer's own gaps travel into `ruleset.gaps` — the figure the
  # constructor's header calls «пробелов в данных». ⚠ Typed here and checked
  # against `Data.Loader` by the test, rather than derived: the loader decides
  # it, and the two drifting apart is exactly what the canary is for.
  #
  #   * `classes` — since task 3.28;
  #   * `feats` — since 14.08.2026, the day the feat layer's unapplied facts
  #     got `affects`. Before that, adding them would have added 21 gaps of
  #     which 20 are about damage, duration and immunities — precisely what
  #     3.28 had just taken out;
  #   * `skills` — **since 14.08.2026 too**, the day the skill layer's 53 facts
  #     (all of them, not only the 48 unapplied — a skill record carries no
  #     `type`/`use` field of its own the way an applied feat fact does, so
  #     there is nothing here that would need no classification) got `affects`.
  #     Read `priv/rules/siala_41/skills.json`'s own `_field_note` for what the
  #     five `global[]` facts are and why they carry no label at all: they never
  #     reach a skill's `siala_changes`, so this module cannot see them and
  #     `census/1`'s `skills.total` is 53, not 58.
  @layers [classes: true, feats: true, skills: true]

  @doc """
  Counts each shard layer's facts by receiver — see `t:census/0` and `t:layer/0`.

  ⚠ Per layer and never summed. The layers' `total`s are not the same kind of
  number: the class layer is 126 facts a human transcribed off prose, the feat
  layer is 196 facts a parser read mostly off four bold labels, and only the
  latter's *unapplied* half carries `affects` at all. Adding them would produce
  a figure that answers no question, and a screen quoting any of them has to
  name the layer it came from.
  """
  @spec census(map()) :: census()
  def census(ruleset) do
    our = our(ruleset)

    for {layer, reported?} <- @layers, into: %{} do
      {layer, layer_census(ruleset |> Map.get(layer, %{}) |> Map.values(), our, reported?)}
    end
  end

  # ⚠ `applied` is `total - unapplied` rather than a list of its own, and that
  # holds because `siala_unapplied` is by construction a subset of
  # `siala_changes` — the same fact map goes into both lists in `Data.Loader`.
  # Under test, because if it ever stopped holding this number would go wrong
  # quietly instead of loudly.
  defp layer_census(records, our, reported?) do
    all = Enum.flat_map(records, &Map.get(&1, :siala_changes, []))
    unapplied = Enum.flat_map(records, &Map.get(&1, :siala_unapplied, []))
    dropped = Enum.reject(unapplied, &ours?(&1, our))
    not_ours = Enum.reject(all, &ours?(&1, our))

    %{
      total: length(all),
      # Non-empty, the same shape `ours?/2` treats as a label: `[]` states
      # nothing, and the loader refuses to load it anyway.
      labelled: Enum.count(all, &match?([_ | _], &1["affects"])),
      applied: length(all) - length(unapplied),
      unapplied: length(unapplied),
      ours: length(all) - length(not_ours),
      not_ours: length(not_ours),
      gaps: length(unapplied) - length(dropped),
      dropped: length(dropped),
      # ⚠ Гистограмма строится по фактам, отвергнутым ПО ПОЛУЧАТЕЛЮ, и факты
      # с решением владельца (`not_a_gap`, задача 3.74) из неё исключены.
      # Причина не бухгалтерская: такой факт называет получателя, который
      # у нас ЕСТЬ (у клирика это `ac`), и попади он сюда — список «получатели,
      # которых мы не печатаем» стал бы утверждать про `ac`, что мы его
      # не печатаем. Это неправда, и на странице «Источники» она была бы
      # видна читателю. Два разных повода не считаться пробелом — «получатель
      # не наш» и «владелец решил» — обязаны и считаться раздельно.
      not_our_receivers: not_ours |> Enum.reject(&is_map(&1["not_a_gap"])) |> receiver_counts(),
      reported?: reported?
    }
  end

  # Most frequent first, then alphabetically: a list of categories is read as
  # "what is left out most", and ties have to land somewhere stable.
  defp receiver_counts(facts) do
    facts
    |> Enum.flat_map(&(&1["affects"] || []))
    |> Enum.frequencies()
    |> Enum.sort_by(fn {receiver, count} -> {-count, receiver} end)
  end
end
