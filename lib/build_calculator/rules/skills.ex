defmodule BuildCalculator.Rules.Skills do
  @moduledoc """
  Skill ranks: budget, price and ceiling.

  Three rules that a skill row lies without (CLAUDE.md §6):

    * **Ceiling** — `character level + 3` for a class skill, half that rounded
      down for a cross-class one. "Class skill" here means a class skill of the
      class taken on **exactly that level**, the same reading the price uses.
    * **Price** — one point for a class skill, two for a cross-class one, and
      here "class" means the class taken on **exactly that level**, not the build
      as a whole. The same skill can cost 1 on level 5 and 2 on level 6.
    * **Carry-over** — unspent points roll into the next level, so the budget is
      a running total and not a per-level "spend it or lose it".

  Both caps come from `ruleset.skill_rank_caps`, both prices from the class-skill
  lists in the ruleset.

  ## The ceiling bounds a purchase, not a total

  ⚠ This module used to read the ceiling off the **build**: a skill was a class
  skill for the ceiling if *any* class taken so far had it, and the previous
  version of this doc called that deliberate. It is wrong, and wrong in the
  direction that matters — it let a build buy ranks the game refuses.

  Дан, observed in game 03.08.2026 (`source: user`, described on no wiki page at
  all): a Sorcerer 1–39 who takes Fighter at level 40 **cannot raise Spellcraft
  there**, because Spellcraft is cross-class for a Fighter. The 35 ranks bought
  on the Sorcerer levels are not taken away — they stay, and the character simply
  buys nothing more on that level. The old reading offered him a ceiling of 43.

  So the ceiling governs **what a level may buy**, never what the skill may hold:

    * `rank_cap/4` — how high a purchase on this level may take the skill;
    * `rank_room/4` — how many ranks that leaves to buy, given what is already
      held: `max(0, cap - ranks held before this level)`;
    * `max_ranks/4` — the other question, and it needs the whole ladder: the
      tallest ceiling any single level offered, which is the most the skill can
      ever have reached.

  ⚠ `over_cap/3` follows from the same sentence and is the half that is easy to
  break. A build is accused only where it **bought** past the level's ceiling.
  Comparing the running total against the ceiling would accuse the Sorcerer's 35
  legal ranks on his Fighter level — trading a false legality for a false
  illegality, which is not a fix.

  ## Two skill rules that leave the skill sheet

  Ranks are not the end of it. Two of the shard's rules change numbers elsewhere,
  and both are read from `ruleset.skill_rules` rather than written here:

    * `save_bonus/3` — Spellcraft adds +1 to **every** saving throw per 5 ranks.
      Players do not count it, which is why CLAUDE.md §3 asks for it to be shown.
    * `modifiers/3` — a build of four classes loses 1 from Hide and Move Silently
      for each level of a class that is not a stealth class. The only rule about
      skills that depends on the shape of the whole build rather than on one
      class, which is why it cannot live on a class record.
    * `class_bonuses/3` — a bonus whose size is **class levels**. `Bardic
      knowledge` is the only one today, and it is the only skill rule whose size
      grows with the build: «Harper scout and bard levels stack for the bonus
      granted by this feat» (`fandom:Bardic knowledge`, revid 51806, measured by
      Dan 16.08.2026 — `GAME_CHECKS.md` F7). ⚠ Read off the markup rather than
      off `ruleset.skill_rules`, and the two are not interchangeable: the rule
      form asks for a class level, this one asks whether the character **owns the
      feat** and then counts every level of the classes the source names. The
      shard moving the grant to the Harper Scout's second level decides the
      first question and says nothing about the second — our model used to
      answer both with one number and was short by 8 on Dan's build.

  ## Ranks are not the skill

  What a character rolls is `ranks + key ability modifier + everything else`, and
  `value/4` is the only place that assembles it. The interface used to add the
  ability modifier itself, in two places, and neither of them knew about the
  racial affinities (an Elf's +2 Spot) or about the stealth penalty — so a number
  captioned "с модификаторами" was short by two for five of the seven races.

  Three things it deliberately refuses to work out, and each says so in its own
  way rather than rounding into the number:

    * **A skill with no key ability gets `total: nil`**, not `ranks + 0`. Adding
      zero would state that the ability contributes nothing — a number the source
      never gave. The gap `{:missing_data, {:skill_key_ability, id}}` travels
      instead, and `ranks` still comes back so the caller can show what *is*
      known.

      ⚠ **Ни один навык обоих ruleset'ов сегодня сюда не попадает.** Его
      единственным адресатом была `alchemy` — навык шарда, чью ключевую
      характеристику не называет ни одна вики, — и 17.08.2026 Dan ответил на
      кейс P1 замером: «ее атрибут - мудрость». Механизм от этого не умер, а
      остался без свидетеля: следующий навык шарда придёт ровно так же, поэтому
      форма жива и проверяется на копии `priv/rules`, у которой характеристика
      снята (`skills_test.exs`). ⚠ Отсутствие свидетеля — тоже утверждение, и
      оно под тестом на обоих ruleset'ах: «таких навыков не осталось» обязано
      падать в тот день, когда появится новый.
    * **A feat's bonus is in `total` only where a human wrote it down.** The
      connection "this feat adds N to skill X" exists on Fandom as English prose
      and nowhere else, so it was transcribed by hand into
      `vanilla/feat_skill_bonuses.json` with the sentence it came from beside it,
      and this reads that file through `ruleset.skill_bonuses` — `Alertness` +2 to
      Spot and Listen, `Stealthy` +2 to Hide and Move Silently, nine in all.
      Reading a number out of prose *here* would still be inventing one
      (CLAUDE.md §3); reading one a human transcribed and cited is the same
      contract every other fact in the project has.

      ⚠ Ten of the eleven are a flat number and reach `feat_bonus`; the eleventh
      (`Bardic knowledge`) is a **sum of class levels** and reaches `class_bonus`
      instead — the shape of the amount decides the term, see `class_bonuses/3`.

      ⚠ **Two of the ten do not name their skill, and the build does** —
      `Skill focus` +3 and `Epic skill focus` +10, task 3.92. The page cannot
      name it because the player picks it, so the record says `skills_from:
      "feat_choice"` and the receiver comes off the pick; the section on
      `feat_bonuses/3` has the whole of it. Here it matters only for the count:
      this used to be «nine records, eight flat», with those two sitting among
      the refusals below.

      The rest of that file is refusals, and they arrive the same way: a bonus
      that depends on where the character stands (`Trackless step`, in the
      wilderness), on which creature is in front of him (`Favored enemy`), or
      that the character sheet does not even show (`Small stature`'s size
      modifier). Those are named in `unmodelled_feats` for the skills they would
      have landed on, so the shortfall has a name instead of looking like
      arithmetic we got wrong — see `feats_by_skill/3`.

      ⚠ **A racial trait counts here too, and did not until task 3.25.** The
      records now carry a source kind (`{:feat, id}` / `{:race_feat, id}` / …)
      the way the other five markup files always did, so `Small stature` reaches
      a goblin's Hide row instead of being gated behind ownership of a feat
      nobody can own. The names of the two fields still say «feat» — that is the
      web layer's contract and the trait is a feat in `feats.json` — but the
      route is the ruleset's races.
    * **A skill's value is clipped at 127 and never by anything smaller.** The
      ceiling is `verified` in the data since 03.08.2026 (the wiki states it for
      Hide and Move Silently, the player confirmed it as the general rule —
      `source: user`, the top of the ranking in CLAUDE.md §3), and since task
      3.20 it is **applied**: the value carries item bonuses now, which is the
      layer it was written about. ⚠ It still cannot bite on a legal build, and
      that is worth stating with the arithmetic rather than left to be
      rediscovered — see «Второй потолок применён и всё ещё не достаёт» below.

  ## Два потолка на одном числе, и они про разное

  ⚠ Путать их нельзя, потому что они кусают разные вещи:

    * `:skill_bonus` — **+50 на бонусы**, то есть на пул слагаемых поверх базы.
      Ранги, модификатор характеристики и штрафы в него не входят;
    * `:max_skill_value` — **127 на итог**, то есть на всё вместе, включая ранги.

  ### Что лежит в пуле +50, а что нет

  Внутри — ровно те слагаемые, чей собственный источник говорит, что они туда
  входят, и ни одного больше. С 09.08.2026 их **два**:

    * расовый бонус шарда к названному навыку (+12 дисциплины у Человека,
      задача 3.12) — «Этот бонус входит в кап навыка +50» на странице расы;
    * **прибавка с вещей** (`Rules.Gear`, задача 3.20) — и это не аналогия:
      «Система оружия» (revid 20527) говорит про магический посох, дающий
      +12 к спеллкрафту, ровно то же самое — «Этот бонус складывается с
      остальными бонусами к навыкам, но входит в кап +50». То есть шард сам
      называет предмет источником, который в этот потолок входит.

  Прибавки фитов, классовые умения и ванильная расовая склонность **не**
  клипаются: ни один источник не говорит, что они в этот пул входят, а положить
  их туда, куда их никто не кладёт, значило бы выдумать правило. У focus-фитов
  сторону называет источник ПОИМЁННО, а не по аналогии: считая максимум навыка
  «without bonuses from items and effects», `fandom:Skill level` включает
  в это число «plus 13 from epic and regular skill focus».

  ⚠ Здесь стояло «всех их вместе максимум +7 (склонность +2, фит +2, Арфист +5
  на своём потолке), так что вопрос пока и не дорог» — **устарело дважды и
  в обе стороны крупно**. Прибавка Арфиста с замера F7 (16.08.2026) равна СУММЕ
  уровней барда и Арфиста, то есть до +41, а не +5; прибавка фитов с задачи 3.92
  выросла на +13 у любого навыка, куда взяты оба focus-фита. Померено на барде 41
  с Lore: `class_bonus` 41, `feat_bonus` 13. Вопрос перестал быть дешёвым — но
  ответ на него не изменился ни на единицу: сторона у каждого слагаемого
  по-прежнему читается из данных, и внутрь пула никто из них не переехал.

  ⚠ Клип **один на пул**, а не по слагаемому — иначе Человек с вписанными +50
  унёс бы 62 при потолке 50, ровно тем же способом, каким сейвы однажды несли
  +40 (CLAUDE.md §9). Сторона каждого слагаемого читается из данных
  (`Rules.Caps.covers_source?/3`), сам клип — `Bonuses.clip/3`, единственный в
  ядре.

  ### Второй потолок ДОСТАЁТ — с 25.08.2026, и это ровно то, что было предсказано

  ⚠ Здесь стояло «применён и всё ещё не достаёт — но разрыв уже 8», а рядом
  назывались оба числа, которых не хватало: `Skill focus` +3 и `Epic skill focus`
  +10, «в день, когда их перенесут в данные, Lore переваливает за 127». Задача
  3.92 их перенесла, и день настал — с числами, а не по расчёту на бумаге.

  Померено на барде 41 с Lore (44 ранга, INT 18 поинт-бай + 2 раса + 10 прибавок
  + 12 вещи → модификатор +15, вписанные «Lore +50», `Bardic knowledge` 41):

    * без focus-фитов — сырых **150**, срез **−23**, в листе **127**;
    * с обоими — сырых **163**, срез **−36**, в листе те же **127**.

  То есть у такого билда +13 уже не видны вовсе, и это не ошибка расчёта, а
  потолок: он был на месте заранее (задача 3.20), поэтому появление двух новых
  слагаемых не потребовало ни строчки. Данные это объявляли всё время
  (`stat_caps.max_skill_value._decision`: «Применяется ядром как потолок ИТОГА
  навыка»).

  ⚠ Ключевое, что не изменилось: расовый бонус шарда и прибавка с вещей стоят
  в **одном** пуле, поэтому «74 + 50 = 124» было бы двойным счётом — +12
  Человека уже внутри тех же 50.

  ⚠ И то, что потолок теперь кусает, не делает его проверяемым только на живом
  билде: он по-прежнему проверяется и на искусственно опущенном — тем же
  приёмом, каким проверялся +50.

  ## Штраф брони — терм значения, а не отрицательный бонус

  ⚠ Здесь стояло «не считается и объявлено гэпом `{:not_modelled,
  :armor_check_penalty}`, величина зависит от надетого, а надетого у нас нет».
  Надетое появилось задачей 3.41, штраф считается с 3.42, и форма снята вместе
  с русской подписью.

  Величину даёт `Rules.Worn.armor_check_penalty/2` (доспех и щит **складываются**
  — так сказано на странице), а кто её получает — поле навыка
  `armor_check_penalty`, поднятое из `vanilla/skills.json`: шесть навыков, ровно
  те, что страница называет поимённо. Ни одного имени навыка здесь нет, как и
  нигде в ядре.

  Четыре свойства этого терма, каждое из которых легко нарушить:

    * он **свой терм** (`armor_penalty` в `value/4`), а не поправка внутри
      чужого. Разбор навыка обязан сходиться со своим числом, а спрятанный
      внутри «вещей» штраф сделал бы вписанное игроком число неузнаваемым;
    * он **не в пуле +50** и вообще ни в каком потолке. Потолки этого проекта
      односторонние и стоят на бонусах; штраф — не бонус, и `Caps.clamp/3` для
      него не механизм, а совпадение формы;
    * он **не трогает ни цену ранга, ни потолок рангов, ни классовость** — те
      три правила про покупку, а этот про значение;
    * он **не имеет пола**. Может ли навык уйти в минус, не говорит ни одна
      страница, поэтому `max(0, …)` здесь нет: это было бы выдуманное игровое
      число, а не осторожность.

  ⚠ И третье состояние вместо двух: у навыка шарда про штраф может **не
  высказаться никто**. Ноль там был бы утверждением, поэтому пока надето что-то
  штрафующее, значение такого навыка `nil`, а
  `{:missing_data, {:skill_armor_check_penalty, id}}` говорит почему. Голым
  персонажем вопрос не встаёт вовсе — штраф `0` при любом ответе, — и оговорки
  тоже нет: неопределённость про решённое запрещена так же прямо, как молчание
  про нерешённое.

  ⚠ **Свидетеля у третьего состояния сегодня нет ни в одном ruleset'е** — тем
  же ответом Dan 17.08.2026 («Штрафа нет», кейс P1) `alchemy` перешла из него
  в `:none`. Пара с ключевой характеристикой тут не случайна: оба состояния
  держались на одном и том же навыке, поэтому и закрывались вместе, и
  проверяются вместе — копией `priv/rules` без поля плюс утверждением, что
  в живых данных таких навыков не осталось.

  ## What is still missing from the number, and where it is reported

  Nothing about armour any more. The circumstances of a fight — light, movement,
  stance — are not in the number either, and never were: they are not properties
  of a build at all, so there is no gap to report about them. ⚠️ The web layer
  used to say so in a caption; **removed 20.08.2026 by Dan's decision** («если бы
  мы это учитывали, это бы явно прописано»). Nothing about the number changed —
  only whether the panel spelled the omission out.
  """

  alias BuildCalculator.Rules.{
    Abilities,
    Bonuses,
    Build,
    Caps,
    Gear,
    GearFeats,
    RacialBonus,
    WeaponTypeBonus,
    Worn
  }

  # Ключ ruleset'а, под которым лежит разметка прибавок к навыкам. Передаётся в
  # `Rules.Bonuses` аргументом, как у пяти остальных статов.
  @markup :skill_bonuses

  @doc """
  Skill points granted by character `level`.

  Class value plus the intelligence modifier *as it stood on that level*, floored
  at one, plus the racial per-level bonus, and quadrupled on character level 1
  (`fandom:Skill point`).

  Whether *worn* intelligence is part of that modifier is the ruleset's answer,
  not this function's — see `gear_intelligence/1`.
  """
  @spec points_at(Build.t(), map(), pos_integer()) :: non_neg_integer()
  def points_at(%Build{} = build, ruleset, level) do
    with class when not is_nil(class) <- Build.class_at(build, level),
         {:ok, %{skill_points: base}} when is_integer(base) <- Map.fetch(ruleset.classes, class) do
      per_level =
        max(1, base + intelligence_modifier(build, ruleset, level)) +
          racial_per_level(build, ruleset)

      if level == 1, do: per_level * 4, else: per_level
    else
      _ -> 0
    end
  end

  @doc """
  Whether the ruleset counts intelligence **from equipment** when a level hands
  out skill points.

  `:ignored` — «INT с вещей скилл поинты при повышении уровня не увеличивает»
  (Dan, 25.08.2026; `_vanilla_constants_confirmed.skill_points_gear_intelligence`).
  `:counted` — the same record saying the opposite. `nil` — nobody has said, and
  that is a third answer rather than a synonym of the first: the points still
  have to be granted somehow, so the core keeps counting the **base** score and
  `Rules.compute/2` says so out loud (`{:assumed,
  :skill_points_ignore_gear_intelligence}`).

  ⚠ The two silent answers are silent for opposite reasons and only one of them
  is a decision of ours. Reading them off one key keeps the number and the
  caveat from drifting apart — before 25.08.2026 the choice lived in this module
  and the caveat in `Rules.compute/2`, which is exactly the arrangement where a
  rule gets applied and denied at the same time (CLAUDE.md §9, «ложный гэп»).
  """
  @spec gear_intelligence(map()) :: :counted | :ignored | nil
  def gear_intelligence(ruleset), do: Map.get(ruleset, :skill_points_gear_intelligence)

  # ⚠ `modifiers_at/3` is the geared reading and `scores_at/3` the bare one —
  # two functions rather than one with a flag, because gear has no history and
  # the geared one applies it at every level. Which of the two runs is decided
  # once, here, off the record above.
  defp intelligence_modifier(build, ruleset, level) do
    case gear_intelligence(ruleset) do
      :counted ->
        build |> Abilities.modifiers_at(ruleset, level) |> Map.fetch!(:int)

      _ ->
        build |> Abilities.scores_at(ruleset, level) |> Map.fetch!(:int) |> Abilities.modifier()
    end
  end

  @doc "Whether `skill` is a class skill for the class taken on `level` — this sets the price."
  @spec class_skill_at?(Build.t(), map(), atom(), pos_integer()) :: boolean()
  def class_skill_at?(%Build{} = build, ruleset, skill, level) do
    case Build.class_at(build, level) do
      nil -> false
      class -> class_skill?(ruleset, class, skill)
    end
  end

  @doc "Cost of one rank of `skill` bought on `level`."
  @spec rank_cost(Build.t(), map(), atom(), pos_integer()) :: 1 | 2
  def rank_cost(%Build{} = build, ruleset, skill, level) do
    if class_skill_at?(build, ruleset, skill, level), do: 1, else: 2
  end

  @doc """
  Whether *any* class taken up to and including `level` has `skill` as a class
  skill.

  ⚠ This is **not** the ceiling rule — `rank_cap/4` reads the class of the level
  in question, not the build. What this answers is "was this skill ever available
  at the class price and the class ceiling", which is what a finished build's
  summary needs in order to mark a skill as cross-class for the character as a
  whole.
  """
  @spec class_skill_by?(Build.t(), map(), atom(), pos_integer()) :: boolean()
  def class_skill_by?(%Build{} = build, ruleset, skill, level) do
    build
    |> Build.class_levels(level)
    |> Map.keys()
    |> Enum.any?(&class_skill?(ruleset, &1, skill))
  end

  @doc """
  Highest rank a purchase made on `level` may take `skill` to.

  Decided by the class taken on that very level (see the module doc): the ranks
  already held are untouched by it, and a level whose class does not favour the
  skill simply offers a lower ceiling — often lower than what is already held, in
  which case nothing may be bought there at all.

  Zero for an exclusive skill on a level whose class does not grant it: Animal
  Empathy, Perform and Use Magic Device cannot be bought cross-class at all
  (their skill pages say `cross_class: no`), so those levels buy none of it —
  the "forbidden skills" of the community calculators.
  """
  @spec rank_cap(Build.t(), map(), atom(), pos_integer()) :: non_neg_integer()
  def rank_cap(%Build{} = build, ruleset, skill, level) do
    caps = Map.get(ruleset.skill_rank_caps, level, %{class: 0, cross_class: 0})

    cond do
      class_skill_at?(build, ruleset, skill, level) -> caps.class
      exclusive?(ruleset, skill) -> 0
      true -> caps.cross_class
    end
  end

  @doc """
  How many ranks of `skill` may still be bought on `level`.

  `max(0, rank_cap - ranks held before this level)`. Zero once the ceiling of
  this level is already behind the character — the ranks stay, the purchases
  stop.

  Budget is a separate limit and is deliberately not applied here: this answers
  "what do the rules allow", `budget/3` answers "what can be afforded", and the
  caller shows the two for different reasons.
  """
  @spec rank_room(Build.t(), map(), atom(), pos_integer()) :: non_neg_integer()
  def rank_room(%Build{} = build, ruleset, skill, level) do
    held = Build.skill_ranks(build, skill, level - 1)

    max(rank_cap(build, ruleset, skill, level) - held, 0)
  end

  @doc """
  Most ranks `skill` could hold at `level` — the tallest ceiling any one level of
  the ladder offered.

  The ceiling of the *last* level answers nothing here: a Rogue who finishes on a
  Ranger level keeps every rank of Use Magic Device he bought as a Rogue, and a
  Sorcerer who finishes on a Fighter level keeps his Spellcraft. What bounds the
  total is the best single opportunity the ladder ever gave.

  ⚠ An upper bound, not a schedule. Whether the points were there to spend on
  that level is `budget/3`'s question, and a total under this number can still be
  unaffordable.
  """
  @spec max_ranks(Build.t(), map(), atom(), non_neg_integer()) :: non_neg_integer()
  def max_ranks(%Build{} = build, ruleset, skill, level) do
    for lv <- 1..max(level, 0)//1, reduce: 0 do
      best -> max(best, rank_cap(build, ruleset, skill, lv))
    end
  end

  @doc "Whether the ruleset forbids buying `skill` cross-class."
  @spec exclusive?(map(), atom()) :: boolean()
  def exclusive?(ruleset, skill) do
    case ruleset.skills do
      %{^skill => %{exclusive?: exclusive?}} -> exclusive?
      _ -> false
    end
  end

  @doc """
  Running budget up to and including `level`.

  `%{earned:, spent:, free:}`. `free` may not go negative in a legal build; a
  negative value means the build overspent and the web layer should say so.
  """
  @spec budget(Build.t(), map(), non_neg_integer()) :: %{
          earned: non_neg_integer(),
          spent: non_neg_integer(),
          free: integer()
        }
  def budget(%Build{} = build, ruleset, level) do
    {earned, spent} =
      Enum.reduce(1..max(level, 0)//1, {0, 0}, fn lv, {earned, spent} ->
        bought = Map.get(build.skills, lv, %{})

        cost =
          Enum.reduce(bought, 0, fn {skill, ranks}, acc ->
            acc + ranks * rank_cost(build, ruleset, skill, lv)
          end)

        {earned + points_at(build, ruleset, lv), spent + cost}
      end)

    %{earned: earned, spent: spent, free: earned - spent}
  end

  @doc """
  Levels on which the build **bought** past the ceiling, as machine-readable
  reasons.

  `[{:skill_over_cap, :discipline, level, ranks, cap}]`, where `ranks` is the
  running total once that level's purchase is counted and `cap` is the ceiling
  that level offered.

  ⚠ Only levels that bought something are examined, and that is the whole point
  (see the module doc). A total standing above a later level's ceiling is legal —
  it was bought where the ceiling was high enough, and nothing takes it back.
  What is illegal is spending a point where the rules give no room.
  """
  @spec over_cap(Build.t(), map(), non_neg_integer()) :: [tuple()]
  def over_cap(%Build{} = build, ruleset, level) do
    for lv <- 1..max(level, 0)//1,
        {skill, bought} <- Enum.sort(Map.get(build.skills, lv, %{})),
        bought > 0,
        ranks = Build.skill_ranks(build, skill, lv),
        cap = rank_cap(build, ruleset, skill, lv),
        ranks > cap,
        do: {:skill_over_cap, skill, lv, ranks, cap}
  end

  @doc """
  What the build's skill ranks add to every saving throw.

  `{bonus, [skill_id]}` — the total and which skills produced it, so the caller
  can caption the number and report what the model does *not* do with it.
  Vanilla's Spellcraft rule ("+1 per 5 ranks to all saving throws against
  spells") is the only entry today; the shard narrows it to non-area spells and
  that narrowing is deliberately not modelled (CLAUDE.md §3, Дан's decision), so
  the number is the flat one and the caveat travels beside it.

  A ruleset with no such rule returns `{0, []}` — absence of a rule is never
  treated as a rule.

  ⚠ **Считается от КУПЛЕННЫХ РАНГОВ, а не от значения навыка**, и это самое
  вероятное место незаметной поломки после задачи 3.20. Dan, 09.08.2026, своим
  примером: 30 рангов дают `+6`, значит с вещей до потолка сейвов добирается
  ровно `+14`. Прибавка, вписанная тому же Spellcraft в «Вещах», на сейвы не
  влияет **вообще** — иначе «+50 спеллкрафта с посоха» превратились бы в +10 ко
  всем трём сейвам, которых игра не даёт, и заметить это было бы нечем: число
  выглядело бы правдоподобно.
  """
  @spec save_bonus(Build.t(), map(), non_neg_integer()) :: {integer(), [atom()]}
  def save_bonus(%Build{} = build, ruleset, level) do
    for rule <- rules(ruleset).save_bonus, reduce: {0, []} do
      {total, from} ->
        bonus = div(Build.skill_ranks(build, rule.skill, level), rule.per_ranks) * rule.bonus

        if bonus > 0, do: {total + bonus, from ++ [rule.skill]}, else: {total, from}
    end
  end

  @doc """
  Shard modifiers on a skill's final value — everything that is not a rank.

  `%{hide: -12, move_silently: -12}`; skills with no modifier are absent rather
  than zero, because "no modifier" and "a modifier of zero" are the same number
  and not the same statement.

  The only rule here is the four-class stealth penalty. It counts the levels of
  every class outside the shard's list of stealth classes, so a Rogue/Shadowdancer
  who dipped two levels of Fighter and one of Wizard is penalised for three
  levels — not for having dipped, but for each level.
  """
  @spec modifiers(Build.t(), map(), non_neg_integer()) :: %{atom() => integer()}
  def modifiers(%Build{} = build, ruleset, level) do
    case rules(ruleset).stealth_multiclass_penalty do
      nil -> %{}
      rule -> stealth_penalty(build, rule, level)
    end
  end

  defp stealth_penalty(build, rule, level) do
    taken = Build.class_levels(build, level)

    penalised =
      for {class, levels} <- taken,
          not MapSet.member?(rule.profile_classes, class),
          reduce: 0,
          do: (acc -> acc + levels)

    if map_size(taken) >= rule.classes_in_build and penalised > 0 do
      Map.new(rule.skills, &{&1, rule.penalty_per_level * penalised})
    else
      %{}
    end
  end

  @doc """
  Skill bonuses **class levels** grant, as `%{skill_id => %{bonus:, from:}}`.

  Returned with the classes named rather than as a bare number, unlike
  `modifiers/3`. A term that appears in a skill's total without a name is a
  number nobody can check, and this one is large — eight points of Lore on a
  Bard 7 / Harper Scout 1 is the difference between the sheet and the game.

  ## Два источника, один терм — и почему подпись именно классовая

  * **правило слоя навыков** (`ruleset.skill_rules.class_level_bonuses`) —
    «класс X добавляет свой уровень к навыку Y, начиная с такого-то классового
    уровня». Читается из `siala_41/skills.json`; сегодня таких правил нет ни
    одного (см. ниже), механизм жив;
  * **запись разметки с `amount.kind: :class_level_sum`** — «пока фит у
    персонажа есть, прибавка равна СУММЕ уровней названных классов». Одна
    запись: `Bardic knowledge`, «Harper scout and bard levels stack for the
    bonus granted by this feat» (`vanilla/feat_skill_bonuses.json`, `revid
    51806`).

  Вторая приходит от фита, а печатается классами — и это не небрежность: её
  величину объясняют классы и больше ничто, а «Bardic Knowledge +8» под числом
  18 не отвечает, откуда взялась восьмёрка. Поэтому форма величины решает,
  в какой терм запись ложится (`term_of/1`), а вид источника — нет.

  ## Владение фитом, а не потраченный слот

  Гейт второй половины — `Bonuses.held/4`, то есть `Build.feats_owned/3`: слот,
  выдача класса **или** объявленный в «Вещах» фит. Это **эффект**, а эффекты
  фитов с вещей считаются («если фит есть, допустим тафнес, то и HP будут
  увеличены» — Dan, 09.08.2026); сужение 14.08.2026 касалось требований других
  фитов, а не эффектов. Персонаж, объявивший `Bardic knowledge` с вещи и не
  имеющий ни одного уровня барда или Арфиста, получает ноль — и это посчитанный
  ответ, а не молчание: «it is hardcoded to the bard and Harper scout class
  levels» говорит та же страница.

  ## ⚠ Уровень выдачи и состав суммы — РАЗНЫЕ вопросы

  Здесь стояло «One rule fills it: the Harper Scout's Bardic Knowledge… below
  the level the ability is handed over there is no bonus at all», и модель
  склеивала два вопроса в один. Замер Dan 16.08.2026 (`GAME_CHECKS.md`, F7,
  Знание 9 рангов, INT 12): бард 6 → 16, бард 7 → 17, бард 7 + Арфист 1 → **18**,
  плюс рейнджер 2 → 18. То есть первый уровень Арфиста дал +1, хотя шард выдаёт
  само умение только на втором, — сдвиг выдачи решает, ЕСТЬ ли фит, а в сумму
  идут все уровни обоих классов. Мы показывали 10 вместо 18 на всех четырёх
  точках.

  ⚠ Рейнджер в замере — отрицательный контроль: третий класс не добавляет
  ничего, потому что складываются только названные записью классы.

  ⚠ У чистого Арфиста числа при этом не изменились ни на единицу (бардовских
  уровней ноль, фит выдан на 2-м уровне класса, сумма равна уровню Арфиста) —
  поэтому дыру никто и не замечал: единственный случай, ради которого правило
  когда-то записывали, был верен.
  """
  @spec class_bonuses(Build.t(), map(), non_neg_integer()) ::
          %{atom() => %{bonus: integer(), from: [atom()]}}
  def class_bonuses(%Build{} = build, ruleset, level) do
    taken = Build.class_levels(build, level)

    from_rules =
      for rule <- rules(ruleset).class_level_bonuses,
          class_level = Map.get(taken, rule.class, 0),
          class_level >= rule.from_class_level,
          reduce: %{} do
        acc -> add_named(acc, rule.skill, class_level, rule.class)
      end

    # ⚠ Класс с нулём уровней пропускается, а не прибавляет ноль: `from` —
    # это подпись под числом, и «Bard +0» рядом с «Harper scout +3» назвал бы
    # источником класс, которого в билде нет.
    for record <- Bonuses.held(build, ruleset, @markup, level),
        term_of(record) == :class_bonus,
        class <- record.amount.classes,
        class_level = Map.get(taken, class, 0),
        class_level > 0,
        skill <- record.skills,
        reduce: from_rules do
      acc -> add_named(acc, skill, class_level, class)
    end
  end

  # Прибавка к навыку **с именем того, кто её дал**. Одна форма на два
  # источника — фиты и классовые умения, — и это не украшение: терм, попавший
  # в итог навыка без имени, — число, которое никому не проверить, а прибавка
  # Арфиста в пять очков это разница между листом персонажа и игрой.
  defp add_named(acc, key, bonus, source) do
    Map.update(
      acc,
      key,
      %{bonus: bonus, from: [source]},
      &%{bonus: &1.bonus + bonus, from: &1.from ++ [source]}
    )
  end

  @doc """
  Skill bonuses the build itself grants, as `%{skill_id => %{bonus:, from:}}`.

  Read off `ruleset.skill_bonuses` — the `applied` half of the hand-transcribed
  `vanilla/feat_skill_bonuses.json`; nothing is derived from a feat's name or its
  prose here.

  Counted over what the character **owns**, which for a feat means picked in a
  slot *or* handed over by a class, because a feat is a feat however it arrived
  (`Bonuses.held/4`). Owning it twice is impossible (`feats_owned/3` is a set),
  so nothing stacks with itself.

  ## Две записи не называют своего навыка, и его называет билд (задача 3.92)

  `Skill focus` даёт +3, `Epic skill focus` +10 — **тому навыку, который выбрал
  игрок**, и страница его назвать не может по построению. Раньше это делало обе
  записи `not_modelled`, и билд, взявший обе на один навык, недосчитывал 13 очков
  молча. Решение Dan 25.08.2026: «данные фиты, как и любые другие фиты,
  увеличивающие скиллы, нужно плюсовать в скиллах».

  Получателя даёт `Build.feat_choices_permanent/4` — выборы, записанные пиком
  или классовой выдачей, — а то, что запись читается именно так, объявляет она
  сама (`skills_from: "feat_choice"`), и загрузчик роняет сборку, если её
  объявили так же, но назвали навыки (`Loader.Bonuses.skills_from!/3`).

  ⚠ **Одна пара «фит + навык» — одна прибавка.** Источник говорит «the effects do
  not stack. It applies to a different skill in each case», поэтому выборы
  проходят через `Enum.uniq/1`: два пика одного фита в один навык (билд, собранный
  в обход валидации) не дадут +6.

  ⚠ **Складываются друг с другом, и это сказано с обеих сторон** — «This feat
  stacks with epic skill focus» на одной странице и «This feat stacks with skill
  focus» на другой. +13 не сложены нами.

  ⚠ **Вещь навык НАЗЫВАЕТ — с задачи 3.97.** Здесь стояло «вещь навыка не
  называет вовсе… объявленный с предмета `Skill focus` владением считается,
  а выбора не несёт, значит прибавки не даёт»; это было верно про модель, а не
  про механику (решение Dan 25.08.2026: «skill_focus всегда привязывается
  к одному из навыков и дает 3 к данному конкретному навыку»). Получателей
  читает `Build.feat_choices_owned/4`, то есть слот, выдача класса и предмет —
  ЭФФЕКТ, а не требование, и граница ровно та же, что у `feats_owned/3`.
  Объявление БЕЗ значения по-прежнему прибавки не даёт и по-прежнему говорит
  об этом: `{:not_modelled, {:gear_feat_choice, id}}` (`Rules.GearFeats`), — но
  теперь оговорка снимается тем, что игрок навык назвал.

  ⚠ **Взятый фит сам по себе навык в панель не приводит.** Строка появляется,
  только если билд в навык вложился (ранг или число в «Вещах») — то же правило,
  по которому туда не приводит расовый бонус шарда, см. `values/3`.

  ⚠ The nine racial affinities (`Skill affinity (spot)` and its kin) are *not*
  among them, on purpose: their +2 already reaches the sheet through
  `races.json` → `skill_bonuses` and `racial_bonus/3`, so counting the record as
  well would give every elf +4 Spot. The data file records them all the same,
  with the verdict `counted_elsewhere`, so the next reader does not "fix" the
  omission — and `Bonuses.applied/2` never sees them.

  ⚠ One number per record for every skill it lists, and the sum is **outside**
  the +50 pool: `fandom:Skill level` puts that ceiling on «modifiers from items
  and effects» and counts the focus feats' bonus outside it in the next
  paragraph. Each record states the side itself (`cap`), and the loader refuses
  to compile one that claims to be inside — see `bonus_pool/3`, which clips the
  pool this term is not part of.
  """
  @spec feat_bonuses(Build.t(), map(), non_neg_integer()) ::
          %{atom() => %{bonus: integer(), from: [atom()]}}
  def feat_bonuses(%Build{} = build, ruleset, level) do
    for record <- Bonuses.held(build, ruleset, @markup, level),
        term_of(record) == :feat_bonus,
        skill <- receiving_skills(record, build, ruleset, level),
        reduce: %{} do
      acc -> add_named(acc, skill, record.amount.bonus, record.id)
    end
  end

  @doc """
  Навыки, на которые ложится эта запись у **этого** билда.

  Два ответа, и какой из них — решает сама запись, а не вид источника:

    * запись назвала навыки — они и есть получатели (`Alertness` → Spot,
      Listen). Билд тут ни при чём;
    * запись объявила `skills_from: :feat_choice` — получателей называют пики
      (`Skill focus (discipline)`), и билд единственный, кто их знает.

  ⚠ **Без catch-all**, та же дисциплина, что у `term_of/1`: какие записи вообще
  доезжают до применяемой половины, решает загрузчик, и он же роняет сборку
  на записи, которая объявила выбор без фита или назвала и то и другое. Ветка-
  заглушка вернула бы пустой список — молчаливый ноль, ради которого вся эта
  разметка и заведена.
  """
  @spec receiving_skills(map(), Build.t(), map(), non_neg_integer()) :: [atom()]
  def receiving_skills(record, build, ruleset, level)

  def receiving_skills(%{skills_from: :feat_choice, source: {:feat, id}}, build, ruleset, level) do
    build
    |> Build.feat_choices_owned(ruleset, id, level)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def receiving_skills(%{skills_from: nil, skills: skills}, _build, _ruleset, _level), do: skills

  @doc """
  Считается ли прибавка этого фита к навыкам целиком — шестой ответчик
  `Rules.FeatChoices.effect_gap/2`.

  Тот же контракт и та же формулировка, что у пяти соседей (`Rules.FeatBonuses`,
  `AbilityBonuses`, `AttackBonuses`, `SaveBonuses`, `SpellResistance`):
  утверждение принадлежит данным (`effect_coverage: "whole_feat"`), а не
  выводится из того, что прибавка применена.

  ⚠ **Шестого не было до задачи 3.92, и до неё он ничего бы не менял**: ни одна
  применяемая запись этого файла не была повторяемой, а `effect_gap/2` спрашивают
  только про повторяемые. `Skill focus` и `Epic skill focus` — первые, кто и
  повторяем, и посчитан, и без этой строки у каждого билда с ними висела бы
  «прибавку от фита в статы не считаем» рядом с термом «Skill focus +3» в разборе
  того же навыка на том же экране. Ровно тот случай, которым `Weapon focus`
  завёл третьего ответчика (задача 3.5) и `Improved spell resistance` — пятого.
  """
  @spec whole_effect_counted?(atom(), map()) :: boolean()
  def whole_effect_counted?(feat_id, ruleset) do
    Bonuses.whole_effect_counted?(ruleset, @markup, feat_id)
  end

  # В какой терм значения ложится запись — решает **форма величины**, а не вид
  # источника: плоское число это прибавка фита («Alertness +2»), а сумма уровней
  # классов — прибавка классов («Bard +7 · Harper scout +1»). Подписать вторую
  # именем фита значило бы спрятать единственное, что объясняет её величину;
  # разбор навыка обязан сходиться не только числом, но и подписями.
  #
  # ⚠ **Без catch-all, сознательно** — та же дисциплина, что у пяти остальных
  # читателей разметки. Какие формы вообще доезжают до `applied`, решает
  # загрузчик (`@applied_skill_bonus_kinds`, падает на **компиляции**), поэтому
  # несовпавшая форма здесь — это сломанная сборка, а не живой запрос. Ветка-
  # заглушка (или тихий пропуск в генераторе, что то же самое) вернула бы ноль —
  # ровно ту молчаливую недостачу, ради которой вся эта разметка и заведена.
  defp term_of(%{amount: %{kind: :flat}}), do: :feat_bonus
  defp term_of(%{amount: %{kind: :class_level_sum}}), do: :class_bonus

  @typedoc """
  A skill's final value and every term it was assembled from.

  `total` is `nil` when a term could not be worked out honestly, and `gaps` then
  says which; every other field is filled in either way, so a caller can still
  show the ranks it does know.

  `unmodelled_feats` is the opposite kind of entry: not a term of the sum but a
  named hole in it — feats this build took **for this skill** whose bonus is
  prose on a wiki page and no number anywhere. `total` stays a number, because a
  build's numbers are its base without gear either (the view screen says so
  outright); what the field buys is that the shortfall has a name instead of
  looking like a miscalculation.

  ## Каждое слагаемое отдельным полем — это и есть защита от двойного счёта

  ⚠ У AC однотипные прибавки ловятся типом; **у навыка типов нет**, поэтому
  объявленный фитом с вещи `Stealthy` (+2 Hide) и вписанное «Hide +50»
  складываются, и запретить это нечем — оба утверждения игрока верны по
  отдельности. Защита не в отказе считать, а в том, что `feat_bonus` и
  `gear_bonus` — **разные поля**: игрок, вписавший одно и то же дважды, видит
  две строки, а не одно число, в котором не разобраться.

  ## Три поля про потолки, и они говорят разное

    * `gear_bonus`, `shard_race_bonus` и `weapon_type_bonus` — **до** потолка,
      как есть. ⚠ Третье — прибавка за ТИП оружия в руках (задача 3.35): своим
      полем, а не внутри `shard_race_bonus`, хотя число у них одно и то же и
      источник тоже шард. Это два независимых терма, они складываются (замер
      Dan, `GAME_CHECKS.md` Q1), и Человек-сагровик с древковым оружием получает
      к Дисциплине +18 и ещё +18;
    * `bonus_clipped` / `bonus_capped?` — сколько забрал потолок пула (+50) и
      укусил ли он. ⚠ Остаток несётся полем, а не выводится вызывающим из
      разницы: потолок покрывает не все слагаемые, поэтому «сумма термов минус
      total» обвинила бы фит, который никто не клипал — та же причина, по
      которой `attack_cap_clipped` и `save_cap_clipped` тоже поля;
    * `value_clipped` / `value_capped?` — то же про потолок **итога** (127).

  `armor_penalty` — ни в одной из этих трёх компаний: это **штраф**, а не бонус,
  которому не повезло со знаком (см. раздел про него в модульной документации).
  `0` — штрафа нет; отрицательное — вот столько отнимает надетое; `nil` —
  про этот навык не сказано, отнимает ли, и тогда `total` тоже `nil`, а в `gaps`
  лежит причина.
  """
  @type value :: %{
          skill: atom(),
          ranks: non_neg_integer(),
          ability: Build.ability() | nil,
          ability_modifier: integer() | nil,
          race_bonus: integer(),
          shard_race_bonus: integer(),
          weapon_type_bonus: integer(),
          gear_bonus: integer(),
          bonus_clipped: integer(),
          bonus_capped?: boolean(),
          armor_penalty: integer() | nil,
          shard_modifier: integer(),
          feat_bonus: integer(),
          feat_bonus_from: [atom()],
          class_bonus: integer(),
          class_bonus_from: [atom()],
          unmodelled_feats: [atom()],
          value_clipped: integer(),
          value_capped?: boolean(),
          total: integer() | nil,
          gaps: [tuple()]
        }

  @doc """
  What `skill` is worth at `level` — ranks plus everything that is not a rank.

  `ranks + key ability modifier + racial affinity + the shard's racial bonus +
  what the player typed under «Вещи» + feats + class abilities + shard modifiers
  − what the worn armour and shield take off it`, and then the two ceilings. The
  ability modifier is the geared one: `+12 INT` off a ring is +6 to every
  intelligence skill, and that cascade is the whole point of the equipment layer
  (CLAUDE.md §6).

  Every source of "everything else" is in the data rather than here: the racial
  skill affinities off `vanilla/races.json` (an Elf's +2 Spot, a Dwarf's +2
  Lore), the shard's own racial bonus off `siala_41/races.json` (the Human's +12
  Discipline — a different fact from the affinity, and only known at the level
  its numbers are stated for, see `BuildCalculator.Rules.RacialBonus`), the flat
  feat bonuses off `vanilla/feat_skill_bonuses.json` (`feat_bonuses/3`), the
  bonuses whose size is class levels off the same file plus
  `siala_41/skills.json` (`class_bonuses/3` — `Bardic knowledge` is the only one
  today), and the shard's four-class stealth penalty (`modifiers/3`). The one term that is not data but the player's own reading is
  `gear_bonus` — the total their items give, typed by hand (task 3.20), the same
  arrangement the ability, AC and save bonuses have had since the beginning:
  «Вещи — не армори, а ручной ввод прибавок» (CLAUDE.md §6).

  ⚠ И один терм, который не прибавка вовсе: **штраф брони** (задача 3.42). Он
  приходит от предмета, а не от числа, отнимает у шести названных навыков и ни
  в какой потолок не входит — разбор в модульной документации.

  See the module doc for the things this refuses to work out.
  """
  @spec value(Build.t(), map(), atom(), non_neg_integer()) :: value()
  def value(%Build{} = build, ruleset, skill, level) do
    assemble(build, ruleset, skill, level, shared_terms(build, ruleset, level))
  end

  @doc """
  `value/4` for every skill the build has something to say about, as
  `%{skill_id => value}`.

  The shared terms — the geared ability modifiers, the stealth penalty — are
  worked out once rather than per skill.

  ## Что считается «есть что сказать» — и почему это не только ранги

  Ранги, **или** число, которое игрок вписал этому навыку в «Вещах» (задача
  3.20). Второе условие новое, и оно не косметика: «дисциплина +50» без единого
  ранга — это то, ради чего поле и заводилось («чтобы в „Итого“ увидеть
  финальную картинку по скиллам», Dan), а панель печатает ровно то, что здесь
  посчитано.

  ⚠ **Расовый бонус шарда сам по себе навык в список НЕ приводит**, хотя
  соблазн симметрии сильный: у Человека +12 дисциплины есть на 40-м уровне
  всегда, и строка про неё появилась бы у каждого билда, где игрок про
  дисциплину ничего не говорил. Панель по дизайну печатает то, во что билд
  **вложился** (CLAUDE.md §6: «Все 28 на каждом из 41 уровня — шум»), а
  вложение — это либо купленный ранг, либо вписанное число. Показывать ли
  расовую прибавку без рангов — продуктовый вопрос, он открыт в бэклоге и решать
  его не ядру.

  A skill with ranks but no record in `ruleset.skills` is left out: that is a
  different failure (`{:missing_data, {:skill, id}}`, already in `ruleset.gaps`),
  and reporting it as "no key ability" would misname it.
  """
  @spec values(Build.t(), map(), non_neg_integer()) :: %{atom() => value()}
  def values(%Build{} = build, ruleset, level) do
    shared = shared_terms(build, ruleset, level)

    for skill <- invested(build, ruleset, level), into: %{} do
      {skill, assemble(build, ruleset, skill, level, shared)}
    end
  end

  # Everything that does not depend on *which* skill is being assembled. Gathered
  # once and passed down, so `values/3` costs one pass over the build's feats and
  # classes rather than one per skill.
  defp shared_terms(build, ruleset, level) do
    %{
      abilities: Abilities.modifiers_at(build, ruleset, level),
      shard: modifiers(build, ruleset, level),
      feat_bonuses: feat_bonuses(build, ruleset, level),
      class_bonuses: class_bonuses(build, ruleset, level),
      unmodelled_feats: feats_by_skill(build, ruleset, level),
      # Сколько отнимает надетое — одно число на весь лист персонажа, поэтому
      # здесь, а не в `assemble/5`: доспех и щит не знают, какой навык их
      # спрашивает. Кому оно достаётся, решает уже поле навыка.
      worn_penalty: Worn.armor_check_penalty(build, ruleset)
    }
  end

  @doc """
  Feats whose bonus to a skill this build has and the model does not count, as
  `%{skill_id => [feat_id]}`.

  Two ways a feat gets in, and neither reads a name or a sentence:

    * **It was taken *for* the skill.** The pick records what it was taken with
      (`{:skill_focus, :discipline}`) and the feat's `repeatable.choice` says that
      parameter is a skill id, so the pair comes off two machine-readable fields.
      `Spell focus (evocation)` names a school and is not here; `Favored enemy
      (goblinoid)` names a creature type and is not here.

      ⚠ **Unless the markup counts it** (task 3.92). Since `Skill focus` and
      `Epic skill focus` became `applied` their +3 and +10 are terms of the value
      with the feat's name beside them, and listing the same feat here as well
      would put «прибавку не считаем» next to a number the player can see — the
      contradiction `Epic toughness` was before task 1.9. Whether it is counted
      comes from the data (`skills_from: :feat_choice` on an applied record),
      never from this module knowing the two names: the day a ruleset stops
      saying the feat takes a skill, the loader drops the record back into the
      rejected half and this line starts printing again by itself.
    * **The data says the record adds to that skill and says why it cannot be
      counted** — the `not_modelled` half of `vanilla/feat_skill_bonuses.json`,
      transcribed with the sentence beside it. `Trackless step` is +4 to Hide and
      Move Silently *in the wilderness*; `Small stature` is +4 to four stealth
      and detection skills that `fandom:Skill level` itself puts outside the
      skill level («part of those specific checks, not part of the skill level»),
      so it never becomes our number.

      ✅ **`Small stature` reaches this list since task 3.25**, and what fixed it
      was the record's **source kind**, not the gate: racial traits are still
      deliberately absent from `Build.feats_owned/3` (`Rules.Bonuses.held?/5`,
      the `{:race_feat, id}` clause reads the race instead), and until this file's
      schema had that kind the caveat was owed to nobody. Measured before the fix
      on a goblin rogue with ranks in all four skills: `unmodelled_feats: []`
      everywhere, while `ruleset.gaps` carried the same caveat for *every* build
      including a human's. A caveat that stands on everything stands on nothing.

  What it is for is stated where it is used (see the module doc): the value is
  short by these, and this is what lets the caller say by *what*.

  ⚠ **`counted_for_classes` is the one place this gets subtle**, and since
  16.08.2026 no record carries it. It answers «this record is a caveat, *except*
  for a build whose only route to the feat is a class the model already counts» —
  a real question, because one feat id can be handed out by two classes whose
  versions have different fates, and telling a build «Harper Scout +5» and «без
  прибавки от Bardic Knowledge» about one number on one row is two opposite
  statements.

  ⚠ Its only bearer *was* `Bardic knowledge`, and Dan's F7 measurement showed the
  two fates were one: the bonus is the sum of both classes' levels, so the record
  became `applied` whole and owes nobody a caveat. The field, its per-ruleset
  resolution (`Loader.Bonuses.counted_for_classes/3` — the file is one layer over two
  rulesets, so a class counted in one may be counted in neither the other) and
  the clauses below stay: nothing about the question stopped being true, it just
  stopped being asked. The guard is under test through a corrupted copy rather
  than through a live record.
  """
  @spec feats_by_skill(Build.t(), map(), non_neg_integer()) :: %{atom() => [atom()]}
  def feats_by_skill(%Build{} = build, ruleset, level) do
    counted = choice_counted(ruleset)

    chosen =
      for {_level, _slot, feat, skill} <- Build.feat_picks(build, level),
          not is_nil(skill),
          skill_choice?(ruleset, feat),
          not MapSet.member?(counted, feat),
          reduce: %{} do
        acc -> Map.update(acc, skill, [feat], &Enum.uniq(&1 ++ [feat]))
      end

    for record <- Bonuses.held_rejected(build, ruleset, @markup, level),
        caveat_owed?(build, ruleset, level, record),
        skill <- record.skills,
        reduce: chosen do
      acc -> Map.update(acc, skill, [record.id], &Enum.uniq(&1 ++ [record.id]))
    end
  end

  # No class is named — the caveat always applies. Otherwise it applies unless
  # every route by which this build owns the feat is one the model already counts.
  #
  # ⚠ A record that arrives off the **race** short-circuits to "owed": the two
  # routes below are a slot and a class grant, and a racial trait is neither, so
  # asking about them would answer `false` and take the caveat away from exactly
  # the build that is owed it. `counted_for_classes` is named on no record today
  # (see the doc above), and the loader raises if it is named on anything but a
  # `not_modelled` one — but "a class counts it" and "a race grants it" are
  # different questions, and this clause is what keeps them from being answered by
  # one expression.
  defp caveat_owed?(_build, _ruleset, _level, %{counted_for_classes: []}), do: true

  defp caveat_owed?(_build, _ruleset, _level, %{source: {:race_feat, _id}}), do: true

  # ⚠ Three routes, not two, since 14.08.2026: a slot, an **item** and a class the
  # data does not list as counted. The item was missing, and it made this
  # disagree with its own caller — `held_rejected/4` decides the record is held by
  # walking `Build.feats_owned/3` (gear included), so a feat declared under
  # «Вещи» arrived here and then lost its caveat, leaving the row short with
  # nothing said. Same shape as the `Rules.Attack` bug fixed the same day: an
  # effect asked about slots.
  #
  # ⚠ **Not `feats_owned/3` itself**, and that is the whole subtlety of this
  # clause: it would fold in the class grant too, and then a build whose class
  # version *is* counted would be shown the class's own term and «прибавку от
  # этого фита не считаем» on one row. The routes have to stay named apart.
  defp caveat_owed?(build, ruleset, level, %{id: feat, counted_for_classes: counted}) do
    MapSet.member?(Build.feats_taken(build, level), feat) or
      MapSet.member?(GearFeats.held(build.gear, ruleset), feat) or
      Enum.any?(Build.class_levels(build, level), fn {class, class_level} ->
        class not in counted and grants_by?(ruleset, class, class_level, feat)
      end)
  end

  defp grants_by?(ruleset, class, class_level, feat) do
    case ruleset.classes do
      %{^class => %{granted_feats: by_level}} ->
        Enum.any?(by_level, fn {level, ids} -> level <= class_level and feat in ids end)

      _ ->
        false
    end
  end

  defp skill_choice?(ruleset, feat) do
    case ruleset.feats do
      %{^feat => %{repeatable: %{choice: :skill}}} -> true
      _ -> false
    end
  end

  # Фиты, чью прибавку «по выбранному навыку» разметка ЭТОГО ruleset'а считает.
  # Читается из применяемой половины, а не из списка имён здесь: ruleset, который
  # не знает про выбор, эти записи не применяет вовсе (загрузчик опускает их
  # обратно), и тогда оговорка обязана вернуться сама.
  defp choice_counted(ruleset) do
    for record <- Bonuses.applied(ruleset, @markup),
        record.skills_from == :feat_choice,
        into: MapSet.new(),
        do: record.id
  end

  defp invested(%Build{skills: skills, gear: gear}, ruleset, level) do
    ranked =
      for {lv, bought} <- skills,
          lv <= level,
          {skill, ranks} <- bought,
          ranks > 0,
          do: skill

    typed = for {skill, bonus} <- gear.skills, bonus != 0, do: skill

    for skill <- ranked ++ typed, Map.has_key?(ruleset.skills, skill), uniq: true, do: skill
  end

  @none %{bonus: 0, from: []}

  defp assemble(build, ruleset, skill, level, shared) do
    feats = Map.get(shared.feat_bonuses, skill, @none)
    classes = Map.get(shared.class_bonuses, skill, @none)
    pool = bonus_pool(build, ruleset, skill)
    ability = key_ability(ruleset, skill)
    armor = armor_penalty(ruleset, skill, shared.worn_penalty)

    known = %{
      skill: skill,
      ranks: Build.skill_ranks(build, skill, level),
      ability: ability,
      # Известен ровно тогда, когда известна характеристика: у него нет своего
      # способа не сойтись. ⚠ А `total` может быть `nil` и при известном
      # модификаторе — когда неизвестен штраф.
      ability_modifier: ability && Map.get(shared.abilities, ability, 0),
      race_bonus: racial_bonus(build, ruleset, skill),
      shard_race_bonus: pool.shard_race,
      weapon_type_bonus: pool.weapon_type,
      gear_bonus: pool.gear,
      bonus_clipped: pool.clipped,
      bonus_capped?: pool.capped?,
      armor_penalty: armor,
      shard_modifier: Map.get(shared.shard, skill, 0),
      feat_bonus: feats.bonus,
      feat_bonus_from: feats.from,
      class_bonus: classes.bonus,
      class_bonus_from: classes.from,
      unmodelled_feats: Map.get(shared.unmodelled_feats, skill, []),
      value_clipped: 0,
      value_capped?: false,
      total: nil,
      gaps: []
    }

    # Два слагаемых, которых может не быть, и каждое говорит своё. Оба гэпа
    # производятся здесь, а не пересказываются в `Rules.compute/2`: одно место
    # решает, что значит неизвестное слагаемое, и ровно поэтому их два, а не
    # один общий «значение не собралось» — у них разные причины и разные
    # предложения на экране.
    case unknown_terms(skill, known) do
      [] -> sum(known, ruleset)
      gaps -> %{known | gaps: gaps}
    end
  end

  # Not `ranks + 0` in either case: see the module doc. A skill can hit both at
  # once — `alchemy` under a tower shield did until 17.08.2026 — and both are
  # then owed: the key ability nobody wrote down and the penalty nobody wrote
  # down are different holes with different answers, and one sentence for the
  # two would name neither.
  defp unknown_terms(skill, known) do
    [
      {known.ability, {:missing_data, {:skill_key_ability, skill}}},
      {known.armor_penalty, {:missing_data, {:skill_armor_check_penalty, skill}}}
    ]
    |> Enum.filter(fn {term, _gap} -> is_nil(term) end)
    |> Enum.map(&elem(&1, 1))
  end

  defp sum(known, ruleset) do
    raw =
      known.ranks + known.ability_modifier + known.race_bonus + known.shard_race_bonus +
        known.weapon_type_bonus + known.gear_bonus +
        known.bonus_clipped + known.shard_modifier + known.feat_bonus + known.class_bonus +
        known.armor_penalty

    {total, capped?} = Caps.clamp(ruleset, :max_skill_value, raw)

    %{known | value_clipped: total - raw, value_capped?: capped?, total: total}
  end

  # Сколько надетое отнимает **у этого навыка**. Три ответа, и третий не
  # декоративный:
  #
  #   * `:applies` — страница называет навык поимённо, штраф его;
  #   * `:none` — страница называет его в списке исключений (Открытый замок,
  #     Верховая езда), он не про ловкость вовсе, или ответ дал игрок
  #     («Штрафа нет» про `alchemy` — Dan, 17.08.2026);
  #   * `:unknown` — не высказался никто, и тогда ответа нет, пока надето
  #     что-то штрафующее. ⚠ Свидетеля в данных сегодня нет ни одного — ветка
  #     ждёт следующего навыка шарда и держится тестом на копии `priv/rules`.
  #     ⚠ Голым персонажем вопрос не встаёт: штраф `0` при любом ответе,
  #     значит неопределённости нет и печатать её было бы ложной оговоркой
  #     про решённое (CLAUDE.md §6).
  defp armor_penalty(ruleset, skill, worn) do
    case ruleset.skills do
      %{^skill => %{armor_check_penalty: :applies}} -> worn
      %{^skill => %{armor_check_penalty: :unknown}} when worn != 0 -> nil
      _known_or_exempt -> 0
    end
  end

  # Слагаемые, стоящие **внутри** потолка на бонусы, и один клип на них.
  #
  # Их три, и у каждого своя цитата — сторона потолка читается из данных
  # (`Caps.covers_source?/3`), а не из вида слагаемого:
  #
  #   * расовый бонус шарда к названному навыку (+12 дисциплины у Человека,
  #     задача 3.12) — «Этот бонус входит в кап навыка +50» на странице расы;
  #   * прибавка с вещей (задача 3.20) — «Система оружия» про магический посох:
  #     «+12 к спеллкрафту … входит в кап +50»;
  #   * бонус за ТИП оружия в руках (+12 дисциплины за древковое, задача 3.35) —
  #     та же страница и то же общее правило про бонусы к навыкам.
  #
  # ⚠ **Один `Bonuses.clip/3` на все три, никогда по слагаемому.** До задачи 3.20
  # клип стоял на расовом бонусе персонально, и это было верно ровно пока
  # слагаемое было одно: Человек с вписанными +50 унёс бы 62 при потолке 50 —
  # та же поломка, которой сейвы однажды несли +40 при потолке +20
  # (CLAUDE.md §9). С третьим слагаемым цена ошибки выросла ещё: Человек-сагровик
  # с древковым оружием и вписанными +50 унёс бы +86. Остаток возвращается
  # отдельно, чтобы разбор мог назвать срез строкой, а не спрятать его внутрь
  # одного из трёх чисел.
  #
  # Прибавки фитов, классов и ванильной склонности здесь не появляются вовсе:
  # они не в пуле (см. модульную документацию), а не «в пуле со стороной
  # снаружи».
  defp bonus_pool(build, ruleset, skill) do
    shard_race = RacialBonus.skill_bonus(build, ruleset, skill)
    weapon_type = WeaponTypeBonus.skill_bonus(build, ruleset, skill)
    gear = Gear.skill_bonus(build.gear, skill)

    clip =
      Bonuses.clip(ruleset, :skill_bonus, [
        {Caps.covers_source?(ruleset, :skill_bonus, :racial_bonus), shard_race},
        {Caps.covers_source?(ruleset, :skill_bonus, :weapon_bonus), weapon_type},
        {Caps.covers_source?(ruleset, :skill_bonus, :gear), gear}
      ])

    %{
      shard_race: shard_race,
      weapon_type: weapon_type,
      gear: gear,
      clipped: clip.clipped,
      capped?: clip.capped?
    }
  end

  defp key_ability(ruleset, skill) do
    case ruleset.skills do
      %{^skill => %{key_ability: ability}} -> ability
      _ -> nil
    end
  end

  defp racial_bonus(%Build{race: nil}, _ruleset, _skill), do: 0

  defp racial_bonus(%Build{race: race}, ruleset, skill) do
    case ruleset.races do
      %{^race => %{skill_bonuses: bonuses}} -> Map.get(bonuses, skill, 0)
      _ -> 0
    end
  end

  @no_rules %{save_bonus: [], stealth_multiclass_penalty: nil, class_level_bonuses: []}

  # A ruleset built without the skill layer carries no rules at all; that is "no
  # rule", not "no skills", and must not raise.
  defp rules(ruleset), do: Map.merge(@no_rules, Map.get(ruleset, :skill_rules) || %{})

  defp class_skill?(ruleset, class, skill) do
    case ruleset.classes do
      %{^class => %{class_skills: skills}} -> MapSet.member?(skills, skill)
      _ -> false
    end
  end

  defp racial_per_level(%Build{race: nil}, _ruleset), do: 0

  defp racial_per_level(%Build{race: race}, ruleset) do
    case ruleset.races do
      %{^race => %{bonus_skill_points: %{per_level: n}}} when is_integer(n) -> n
      _ -> 0
    end
  end
end
