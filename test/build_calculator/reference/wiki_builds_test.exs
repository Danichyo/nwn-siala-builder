defmodule BuildCalculator.Reference.WikiBuildsTest do
  @moduledoc """
  Regression run against the finished builds published on the Siala wiki.

  Eight pages there carry a full level ladder — one class per character level from
  1 to 40 — plus the author's own totals. They are the only place where the model
  meets a whole character somebody actually played, so they are worth running on
  every `mix test`, not once by hand.

  ## Wiki pages are fixtures, not truth

  CLAUDE.md §3 ranks the sources: `игрок в игре > страница правил > страница билда
  > Fandom`. A build page sits second from the bottom, and we have been burnt
  already — two pages disagreed with the model by exactly +13 skill points and it
  turned out to be **their authors' arithmetic**, proved by three other builds
  landing exactly. So a disagreement here is not automatically a failure.

  What this run must do instead:

    * **fail when something that used to agree stops agreeing** — that is a
      regression in the calculator and the whole point of the file;
    * **not fail on known disagreements** — each one is listed in `divergences`
      with the two numbers, the verdict on whose mistake it is and why.

  Hence a snapshot rather than a live comparison with the wiki. Every model number
  below is either (a) equal to what the page says, or (b) declared in
  `divergences`, or (c) derived by hand from the class progression tables in
  `priv/rules/` with the arithmetic written out — never copied from a test run.
  `every page↔model difference is declared` enforces (a)-or-(b) structurally: a
  number cannot be quietly bent to match the code.

  ## What is compared, and what is not

  The numbers printed on these pages are **geared** numbers: mini-sets alone are
  worth +15…+91 % HP (CLAUDE.md §3), which is where 700–1000 HP and +71 attack
  come from. We model no equipment, so comparing those is guaranteed to disagree
  and would teach us nothing. `@not_comparable` names each one and why; the test
  `every number lifted off a page is classified` makes sure nothing new slips
  through unclassified.

  Compared:

    * **class composition and character level** — mostly a check that we read the
      ladder correctly, and independently cross-checked: the hub page «Билды для
      новичков» states each build's class split in one line, and all eight agree
      with the per-level ladder.
    * **feats, level by level** — the ladder names them, and the slot model,
      the prerequisite checker and the class grant tables all have something to
      say about each one. See below.
    * **skill points earned** — the best indicator available. Gear cannot touch
      it, the formula is `(class value + INT modifier)` a level, ×4 on the first,
      and it is the number the pages state most often.
    * **skill points spent** — the page's own rank list, priced by our
      `Rules.Skills`. This exercises the rule most calculators get wrong: a rank
      costs 1 or 2 by the class taken *on the level it is bought*.
    * **rank ceilings** — every rank a page asks for must fit under our cap.
    * **caps and limits** — no build may break the class limit, the level cap or a
      per-class ceiling.

  Derived from `priv/rules/` and pinned here, not comparable with the pages
  because no page gives a breakdown to subtract equipment from: `base_attack`,
  the three base saves, attacks per round and naked HP. Each carries its
  arithmetic in a comment so the expectation is checkable without running the code.

  ⚠️ **`hp` alone is computed off a build with `feats: true`, everything else
  off one without** (AGENT_QUEUE.md §7 «Стенд регрессии считает числа без
  фитов», closed 08.08.2026). `Toughness` is granted by nine classes and is
  counted either way — `Build.granted_feats/3` never reads `build.feats` — but
  `Epic toughness` and the ability-score feats (`Great constitution`, feeding
  the CON modifier the hit-point formula uses) are *picked*, so they only
  register once the page's feats are laid into slots. `base_attack`, the base
  saves and attacks per round never read a feat or an ability score at all
  (`Progression.base/2`, `attacks_per_round/3` walk `build.levels` only), so
  they are read off the feats-free build — and each fixture that could be
  fed a feat says so with a guard assertion next to the pinned number, rather
  than trusting that reading once. `attack_ability` is the one number a naive
  `feats: true` swap would corrupt (Weapon Finesse switches which ability it
  reads off), which is why it stays local to «the feats add exactly the
  caveats we know about» below and is never asked of the numbers here.

  «Дух Сиалы» (task, волна 12, 09.08.2026, `GAME_CHECKS.md` A1) sits beside
  `Toughness` in that first sentence rather than beside `Epic toughness`: a
  flat +20 the shard hands every character, read straight off
  `ruleset.innate_hp_bonus` and never gated by a feat slot at all, so — like
  `Toughness` — it is in every `hp:` fixture below whether or not the page's
  feats are laid into slots. Every one of the eight pages' `hp:` fixtures
  moved by exactly +20 the day this landed; none of the other pinned numbers
  did, because none of them reads it.

  ## Gaps are pinned by name, not asserted empty

  These fixtures used to pin `stats.gaps == []`, and that was wrong in a way
  worth spelling out: every one of these builds is made of classes the shard
  rewrote, and the core has things to say about all of them. «Гном Защитник»
  carries 25 levels of Weapon Master, and until 17.08.2026 the shard's
  unclear-magnitude attack-bonus rule (then two records,
  `attack_bonus_progression` and `extra_attack_bonus_past_class_level_10`)
  sat in the data as a caveat this file pinned — an empty list there was not
  "clean", it was silence (CLAUDE.md §9). A measurement closed it: the rule is
  the vanilla `feat_attack_bonuses.json` column, already counted by the core,
  so both records merged into one carrying `counted_elsewhere` and the caveat
  is gone from every fixture below that carries the class — the caveat lists
  in this file moved accordingly, named, not silently.

  So `model.class_caveats` names them, class by class, and the run compares the
  whole set. A caveat that appears is then an event somebody sees, and one that
  disappears — because the rule got modelled or the fact got dropped from
  `siala_41/classes.json` — fails just as loudly.

  ⚠ **And on 15.08.2026 every one of the eight grew by the same single line**
  (task 3.34): `{:not_modelled, {:attack_ability_default, :ranged}}`. The measured
  rule behind it is that a ranged attack comes off dexterity (`GAME_CHECKS.md`
  N1), so which ability the attack bonus is computed from now depends on the
  weapon in hand — and **no wiki build page names a weapon**. Handing these
  fixtures one would be inventing a page's data, so each carries the caveat
  instead: the model says out loud that it answered as if the character were in
  melee. It appears on all eight because on all eight the two modifiers differ,
  which is exactly the condition the core emits it under.

  ⚠ **These lists shrank a lot on 10.08.2026 (task 3.28) and it is not the rules
  getting quieter.** A gap is a hole in the *answer*, and a fact whose every
  receiver is something the calculator never prints — damage, effect duration,
  summons, poisons, a buff — is not one (Dan's decision; `changes[].affects` in
  the data, `Rules.GapReceivers` in the core). «Бледный Призыватель» carried 21
  caveats, of which exactly one, `blackguard / bulls_strength`, is about a number
  on the screen; the Paladin's nine `holy_sword` … `otrazhenie` were about spells
  and mounts. Nothing was deleted from the data and nothing stopped being read —
  the facts are still in `class.siala_changes` with their receiver named, and the
  day damage gets modelled they come back by themselves.

  ## Feats

  Every ladder line names the feats taken on that level, and the fixture reads
  them (`BuildCalculator.WikiBuildPage.feat_plan/2`). Four questions get asked of
  each one, and each has its own answer in `model.feats`:

    * **does a slot take it?** Slots are not interchangeable (CLAUDE.md §6) — a
      Fighter bonus only takes a feat that lists Fighter — so this is the one
      check that catches an illegal build. `unplaced` names the feats no slot
      would take, and `@feat_refusals` explains **every one of them by root
      cause**, both directions exhaustive.
    * **is a slot spent at all?** A feat the class hands over for free costs
      nothing, and counting it as a spend would accuse a legal page of
      overspending. `granted` names those; they are also the §6 case worth
      showing a player — «получишь бесплатно, не трать слот».
    * **are its prerequisites met at that level?** `prerequisites_unmet` pins
      what `Rules.validate_feat/3` says, verbatim. Not all of it is the page's
      fault and not all of it is ours — `@prerequisite_causes` sorts that out.
    * **what does the core admit it did not model?** The feats add gaps of their
      own (`{:assumed, :finessable_weapon}` for the two builds that take Weapon
      Finesse), and `caveats` pins the set the way `class_caveats` does.
      ⚠ Задача 3.99 сняла отсюда `{:feat_qualifier, …}` про «with the chosen
      weapon» и «proficiency with the chosen weapon» — у ВСЕХ восьми страниц
      разом. Это не потеря: обе фразы стали проверяемыми требованиями
      (`proficiency_with_chosen_weapon` и работающий `same_choice_as`),
      и на ванильном ruleset'е вторая из них по-прежнему печатается —
      см. `vanilla_gaps`.

  ⚠ Three shapes of caveat arrived with repeatable feats and every one of them is
  a **caveat these builds always deserved and could not be given**, not a new
  hole. All eight pages take feats of that family — `great strength`,
  `epic toughness`, `epic weapon focus` — and until the core knew they repeat it
  had nothing to say about them:

    * `{:not_modelled, {:feat_bonus, id}}` — the feat's own effect is not in the
      numbers. It never was; the gap is only reachable once the feat is known to
      be repeatable, which is why it appears on `great strength` now and not
      before.
    * `{:missing_data, {:feat_max_takes, id}}` — how many times the same thing
      may be taken. Every one of those pages names a ceiling in an effect
      («maximum of 200 hit points», «to a maximum of +10») and none in takes, and
      the effect is not modelled, so the count genuinely goes unchecked. «Паладин
      Адры» takes `epic toughness` three times and nothing in the model would
      have stopped a thirtieth.
    * ~~`{:assumed, {:feat_repeatable, :epic_weapon_specialization}}`, on
      «Мастер оружия Сагровик» alone~~ — **снята 25.08.2026**, кейс `AA2`.
      Стояла на Дановом «не знаю, предполагаю» (`status: "unclear"`); замер
      подтвердил догадку дословно — «её можно брать для разных оружий», —
      статус поднялся до `verified`, и оговорка ушла сама.
      ⚠️ Тем же днём и тем же способом ушла её сестра у `resist_energy`
      (кейс `AA1`): **последние два `unclear` в семействе повторяемости**.
      Ни одно число ни у одного билда не сдвинулось — менялась опора,
      а не расчёт.

  🔴 **И семнадцать строк этой формы сняты 25.08.2026 задачей 3.93 — по причине,
  которой в этом файле ещё не было.** Прежние снятия (`epic_toughness` 1.9,
  `great_*` 3.1, `weapon_focus` 3.5B, `improved_spell_resistance` 3.45,
  `skill_focus` 3.92) все означали одно: **прибавку научились считать**, и
  оговорка начала спорить с числом на экране. Эти семнадцать сняты при том, что
  ни одно число не сдвинулось: `improved_critical`, `epic_energy_resistance`,
  `spell_focus`, `weapon_specialization` и `epic_weapon_specialization` меняют
  крит-диапазон, сопротивление, ДЦ ЧУЖОГО спасброска и урон — механики, про
  которые калькулятор не даёт ответа вовсе, а гэп есть дырка **в ответе**
  (решение Dan 10.08.2026, CLAUDE.md §9). Метка получателя лежит в
  `vanilla/feat_effect_receivers.json` с цитатой страницы у каждой записи;
  словарь получателей — тот же единственный, что судит факты шарда.

  ⚠️ Порядок правки тот же, что у разметки 17.08.2026: **сперва метка в данных,
  потом строка отсюда**. Снять её «потому что тест красный» значило бы спрятать
  регрессию.

  ⚠️ **`favored_enemy` сознательно ОСТАЛСЯ** («Мастер Ловушек»), и он же —
  положительный контроль на то, что механизм жив: его +1 к трём навыкам падает
  в НАШЕ число и не посчитан. Разница между ним и снятыми — «не посчитали то,
  что печатаем» против «не печатаем вовсе».

  ⚠ **`{:feat_bonus, :weapon_focus}` и `{:feat_bonus, :epic_weapon_focus}` сняты
  со ВСЕХ семи фикстур, где они стояли** (задача 3.5, часть B, 10.08.2026). Их
  прибавку к атаке ядро теперь считает — когда в руках названное оружие, — и
  общая оговорка «прибавку от фита не считаем» спорила бы с термом `Weapon focus
  +1` в разборе AB. Ровно та же замена, что волнами раньше произошла у
  `epic_toughness` (1.9) и `great_strength` (3.1).

  ⚠️ И оговорка не исчезла, а стала **точнее**: у этих восьми страниц оружие
  в блоке «Вещи» не выбрано, поэтому на её месте стоит
  `{:not_modelled, {:attack_bonus_weapon, id}}` — «прибавку не считаем, потому
  что какое оружие в руках, не сказано». Проверено диффом обоих множеств по всем
  восьми страницам: ушли ровно две формы, ни одна не появилась.

  ⚠ **Expect disagreement and do not bend the model to it.** These pages are
  written by players, and one of them takes Power Attack on a character with
  strength 12. A finding here is a finding about *something* — read it before
  deciding which side it is about.

  ## The 41st level

  All eight pages stop at 40, so the shard's own cap was covered by unit tests
  and by nothing that looks like a character. `describe "the 41st level"` extends
  each build by one more level of the class it ends on. That level is **derived
  from the rules and observed on no wiki page** — it is labelled as such
  everywhere it appears, because the whole point of this file is that derived and
  observed never get mixed up.

  What it must do (CLAUDE.md §3, `overrides.json` `epic.level_41_behaviour`,
  `source: user`): 41 is odd, so it gives **+1 base attack and nothing to the
  saves**, no general feat, no ability increase, and rank ceilings of 44 / 22.

  ## The vanilla ruleset

  The regression used to run under `siala_41` alone, so a change that broke
  vanilla would not have shown up. `vanilla:` on each fixture is a **diff** — the
  fields whose value changes when the same ladder is computed under the vanilla
  rules — and an empty diff is an assertion that nothing changes. Two builds have
  an entry, both for the same reason: Siala gives the Monk full base attack.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Epic, Skills, Spells}
  alias BuildCalculator.WikiBuildPage

  # source (all eight): https://wiki.siala.kiev.ua/index.php/<title>, снято
  # 2026-08-01, revids as recorded in priv/wiki_cache/siala/_index.json and
  # repeated per entry below.
  #
  # source (class splits, second and independent statement of the same fact):
  # https://wiki.siala.kiev.ua/index.php/Билды_для_новичков revid 18457 — the hub
  # summarises every build in one line («2 Варвар - 10 Воин - 28 Мастер оружия»).
  # All eight agree with the per-level ladder, which is what makes the ladder
  # parse trustworthy rather than merely self-consistent.
  #
  # source (progression rows used in the derivations): priv/rules/vanilla/classes.json,
  # transcribed off Fandom with a revid per class; epic bonuses from
  # priv/rules/vanilla/epic.json — odd levels 21…39 give +1 base attack (10 by
  # level 40), even levels 22…40 give +1 to all three saves (10 by level 40).
  @builds [
    %{
      title: "Бледный Призыватель",
      revid: 18_469,
      page: %{
        race: :gnome,
        alignment: :chaotic_evil,
        # printed as the character sheet shows them, i.e. after the racial
        # modifiers; Gnome is +2 CON / −2 STR
        abilities: %{str: 12, dex: 8, con: 17, int: 14, wis: 8, cha: 16},
        ability_increases: %{con: 1, cha: 9},
        character_level: 40,
        class_levels: %{bard: 4, pale_master: 30, red_dragon_disciple: 2, blackguard: 4},
        # the page discusses skills in prose and states no total
        skill_points: nil,
        free_skill_points: nil,
        committed_ranks: %{},
        attack_bonus: nil,
        saves: %{fort: 72, ref: 60, will: 67},
        spell_resistance: nil
      },
      model: %{
        # first 20 levels only (CLAUDE.md §3: class levels taken after 20 give no
        # base attack and no saves at all): bard 4 → 3/1/4/4, pale master 10 →
        # 5/7/3/7, red dragon disciple 2 → 1/3/0/3, blackguard 4 → 4/4/1/1.
        # Sum 13/15/8/15, then +10 attack and +10 saves from the epic levels.
        base_attack: 23,
        base_saves: %{fort: 25, ref: 18, will: 25},
        # ⚠ The same derivation, written out per class instead of only summed:
        # `fort/ref/will` off the comment above, `levels` = the ones that landed
        # inside the window. This is what makes the sum non-tautological — the
        # numbers here come from the wiki tables, not from the model.
        base_saves_by_class: %{
          bard: %{levels: 4, fort: 1, ref: 4, will: 4},
          pale_master: %{levels: 10, fort: 7, ref: 3, will: 7},
          red_dragon_disciple: %{levels: 2, fort: 3, ref: 0, will: 3},
          blackguard: %{levels: 4, fort: 4, ref: 1, will: 1}
        },
        # base attack 13 at level 20 → 3 attacks, and the epic +10 never adds one
        attacks_per_round: 3,
        # ⚠️ Здесь стояло `hp: nil` — «у Ученика красного дракона нет хит-дайса
        # в данных». Задача 3.37 прочитала растущую шкалу со страницы класса
        # (замер Dan, `GAME_CHECKS.md` G2), и число появилось:
        #   бард            4 × d6                 =  24
        #   Бледный мастер 30 × d6                 = 180
        #   РДД             2 × d6 (первая ступень
        #                   шкалы — до 4-го уровня
        #                   класса это всё ещё d6) =  12
        #   Чёрный страж    4 × d10                =  40
        #   CON 18 (мод +4) × 40 уровней           = 160
        #   Toughness (Чёрный страж выдаёт даром)  =  40
        #   Deathless vigor (ступени ПМ, 30 ур.)   =  38
        #   «Дух Сиалы»                            =  20
        #                                   итого  = 514
        # ⚠️ Именно эта лестница показывает, что шкала читается по уровню
        # КЛАССА, а не персонажа: два уровня РДД взяты глубоко в эпике, и оба
        # всё равно d6 — первые два уровня класса.
        hp: 514,
        # Both prestige classes here used to add a gap apiece — the halves of
        # their requirement blocks the parser could not read («arcane
        # spellcasting: level 3 or higher», «class: bard or sorcerer»). Both are
        # read now, off the pages' own prose (`vanilla/class_requirements.json`),
        # so the gaps are gone because the holes are gone. ⚠️ And this ladder is
        # what corroborates the reading: it takes Bard 1–3 and Pale Master from
        # character level 4, which is exactly «three levels of bard, sorcerer or
        # wizard» and nothing to spare. Under the other reading of that line —
        # «able to cast 3rd circle spells» — a bard needs seven levels and this
        # page would be illegal by four.
        gaps: [
          # ⚠️ Задача 3.34 (15.08.2026): страница оружия не называет, а с 15.08
          # от него зависит сама характеристика броска (дальний бой — ловкость,
          # замер N1). Модель ответила ближним боем и говорит об этом — разбор
          # в шапке файла.
          {:not_modelled, {:attack_ability_default, :ranged}},
          # ⚠️ Здесь стояла `{:missing_data, {:hit_die, :red_dragon_disciple}}`
          # — снята задачей 3.37 (16.08.2026): шкала растущего дайса прочитана,
          # и HP этого билда стало числом (514, разложено у `model.hp` выше).
          # ⚠️ Здесь стояла оговорка `{:not_modelled, {:feat_hp_bonus,
          # :deathless_vigor}}` — тридцать уровней Бледного мастера приносят
          # этот фит, а его хиты растут ступенями по уровню КЛАССА, и форму
          # ядро не считало. Замер D1 (13.08.2026: волшебник 5 / Бледный мастер
          # 5 показывает 73 HP, а не 70) заставил её посчитать, и оговорка ушла.
          # ⚠️ На ЭТОМ билде она и до того была про число, которого нет вовсе:
          # HP тут `nil`, потому что у РДД нет хит-дайса. Строка снята здесь,
          # но недостача до 38 хитов у билда с ПМ без РДД была настоящей.
          # ⚠️ Здесь стояло `{:assumed, :ac_bonus_types_unstated}` — СНЯТО
          # задачей 3.90 (25.08.2026). AC этого билда по-прежнему собирается из
          # трёх собственных источников — `Bone skin` +16 (30 уровней Бледного
          # мастера), `Draconic armor` +1 (2 уровня РДД) и +1 за размер
          # Карлика, — и тип у `Bone skin` («innate») по-прежнему не назван
          # никем. Изменилось не знание, а ОТВЕТ: складывание `Bone skin`
          # с прибавками типа natural подтверждено владельцем, отметка стоит
          # на самой записи (`stacking_confirmed`), и оговорка про то, чего
          # не происходит, стала шумом. ⚠️ Числа AC не сдвинулись ни на
          # единицу — у этого билда 28 голым и до, и после.
          # ⚠️ И здесь же стояло «именно этот билд показывает, что AC и HP
          # развязаны: хиты у него `nil`, а AC считается полностью» —
          # устарело 16.08.2026: считается и то, и другое.
          # Задача 3.12: четвёртый источник AC — щитовой бонус расы Карлика,
          # +6 базовым вариантом. Он есть у этого билда ровно потому, что
          # уровень 40-й: на 39-м величина неизвестна и терма не было бы вовсе.
          # ⚠️ И это ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ к решению Dan от 08.08.2026: билд
          # набран бардом, Бледным мастером, РДД и Чёрным стражем — ни одного
          # класса Сагры, поэтому вариант остаётся базовым (+6, а не +9). У
          # «Сагровика» ниже на том же поле стоит `:sagra_warrior`, и две
          # фикстуры вместе не дают перепутать «всегда base» с «всегда сагровик».
          # 🔴 **Вариант стал `nil` 15.08.2026 — замер Dan** (`GAME_CHECKS.md`
          # Q1/Q4): расовый бонус включается ОРУЖИЕМ В РУКАХ, а фикстуры этого
          # файла собираются со страницы билда и оружия не объявляют вовсе.
          # Значит у них бонус честно не посчитан, и оговорка называет причину,
          # а не вариант.
          #
          # ⚠️ Контраст «base против sagra_warrior», ради которого две фикстуры
          # и держали рядом, этой правкой НЕ потерян — он переехал в
          # `racial_bonus_test.exs`, где билд можно вооружить. Здесь остался
          # контроль поважнее: число, которого игра не даёт, не приезжает
          # и к нам.
          #
          # ⚠️ И это расхождение со страницей РАСТЁТ, а не сокращается: живой
          # персонаж с вики оружие держит, и его AB на странице расовый бонус
          # включает. Наш ответ ниже на эту величину — но он верен ДЛЯ ТОГО
          # БИЛДА, КОТОРЫЙ ОПИСАН, а дорисовывать фикстуре оружие значило бы
          # выдумать данные страницы.
          {:assumed, {:racial_bonus_variant, :gnome, nil}}
          # ⚠️ Здесь стояла `{:not_modelled, {:ability_bonus,
          # :bulls_strength_feat}}` — четыре уровня Чёрного стража приносят
          # право сотворить заклинание, поднимающее силу, — со словами «это
          # бафф, а не постоянная прибавка, поэтому в число он не идёт **и
          # называется**». Вторая половина снята 17.08.2026: бафф — не наш
          # ответ вовсе (решение Dan 10.08.2026), и разметка записи говорит это
          # прямо (`affects: ["buff"]`). Ровно тем же решением днём раньше ушёл
          # `class_caveats` этого билда — см. комментарий под списком; строка
          # осталась в классовом слое и не доехала до слоя разметки.
          # ⚠️ Прибавки самого билда при этом ПОСЧИТАНЫ: два уровня РДД дают
          # +2 к силе, и именно поэтому тремя блоками ниже исчезли три отказа
          # по требованию «сила 13».
          # Задача 1.12a: раса Карлик (Gnome, CLAUDE.md §4) несёт расовую
          # склонность `Hardiness vs. illusions` — узкая по цели прибавка
          # (+2 против mind-affecting заклинаний, а не против всех сейвов),
          # поэтому ядро её не считает и называет.
          # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
          # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
          #   hardiness_vs_illusions(save_bonus)
          # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
          # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
          # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
          # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
          # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
          # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
          # Задача 1.12b: та же раса несёт ДВЕ склонности к атаке, обе узкие по
          # виду врага (+1 против гоблиноидов, +1 против рептилоидов). ⚠️ Третья
          # склонность Карлика, `Small stature`, ЗДЕСЬ НЕ ЛЕЖИТ и это правильно:
          # её +1 к броску атаки безусловен и ПОСЧИТАН (`own_attack_bonus == 1`
          # у этого билда, единственного из восьми, у кого он ненулевой без
          # фитов). Три склонности одной расы, два вердикта — ровно то
          # различие, ради которого разметка сплошная.
          # 🔴 И это ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ к правке 17.08.2026: обе склонности
          # пассивны, помечены `affects: ["attack_bonus"]`, то есть про наше
          # число, и остались на месте, пока баффы вокруг них уходили. Фильтр
          # выкосил бы список целиком — эти две строки говорят, что не выкосил.
          # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
          # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
          #   battle_training_vs_goblins(attack_bonus), battle_training_vs_reptilians(attack_bonus)
          # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
          # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
          # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
          # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
          # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
          # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
          # ⚠️ Правка 09.08.2026, ВТОРАЯ за день: здесь стояла оговорка
          # `{:assumed, {:attack_cap_covers, :race_feat}}` — «входит ли `Small
          # stature` в кап атаки +20, не сказано ни на одной странице». Утром
          # источника не было ни в ту, ни в другую сторону; вечером Dan назвал
          # склонность в списке прямо («из всех тобой перечисленных только Sacred
          # defense входит в кап»), и допущение исчезло вместе с гэпом. Строка
          # оставлена комментарием, а не удалена молча: гэп, который был и пропал,
          # иначе читается как потерянная оговорка.
          # ⚠️ Здесь же стояла `{:not_modelled, {:attack_bonus, :smite_good}}` —
          # четыре уровня Чёрного стража дают модификатор харизмы к броску, но
          # одной атакой раз в день. Снята 17.08.2026 по той же причине, что и
          # `bulls_strength_feat` выше, и ровно тем же признаком в данных:
          # «раз в день, на несколько раундов» — это `buff`.
        ],
        # ⚠️ Из 21 факта четырёх классов до чисел этого билда доезжает ОДИН:
        # ⚠️ Класс-оговорок у этого билда НЕ ОСТАЛОСЬ ни одной (3.28). Песня
        # барда, дыхание дракона, призывы и иммунитеты Бледного мастера — про
        # то, чего калькулятор не считает вовсе. Последним ушёл `bulls_strength`
        # Чёрного стража: 10.08.2026 решением Dan он стал баффом (активируемое
        # умение, поднимающее STR на время), хотя до этого числился нашим —
        # имя как у заклинания, а заметка говорит «было аналогом… переработана».
        class_caveats: %{},
        # bard 4 + pale master 2 + red dragon disciple 2 + blackguard 2, INT 14 →
        # +2 a level: 24 on level 1, then the class value +2 on each of 2…40
        skill_points_earned: 186,
        plan_cost: 0,
        feats: %{
          taken: %{
            1 => [:siala_blade_proficiency],
            3 => [:spell_focus],
            6 => [:expertise],
            9 => [:power_attack],
            12 => [:cleave],
            15 => [:improved_expertise],
            18 => [:divine_shield],
            21 => [:great_charisma],
            23 => [:epic_energy_resistance],
            24 => [:great_charisma],
            26 => [:epic_spell_dragon_knight],
            27 => [:great_charisma],
            29 => [:epic_spell_epic_mage_armor],
            30 => [:great_charisma],
            32 => [:epic_spell_mummy_dust],
            33 => [:great_charisma],
            35 => [:epic_spell_greater_ruin],
            36 => [:great_charisma],
            38 => [:epic_spell_hellball],
            39 => [:great_charisma]
          },
          granted: [],
          unplaced: [],
          unreadable: [],
          # The one page whose every feat lands in a slot.
          #
          # ⚠️ ЗДЕСЬ БЫЛИ ТРИ ОТКАЗА, И ОНИ БЫЛИ НАШИ — сняты задачей 3.1.
          # Страница печатает силу 12, Power Attack (9-й уровень), Cleave (12-й)
          # и Divine Shield (18-й) требуют 13, и модель три раза обвиняла
          # страницу («page_build_does_not_qualify»). На самом деле у билда два
          # уровня Ученика красного дракона — на 6-м и 7-м уровнях персонажа, —
          # а второй уровень класса даёт **+2 к силе** (`Dragon abilities`).
          # То есть к девятому уровню сила 14, и все три фита законны.
          #
          # ⚠️ Это ложная НЕлегальность, а её «не ловит никто» (HANDOFF): фит
          # просто не подошёл, игрок решил бы, что так и надо. Поймалась она
          # не проверкой, а тем, что задача 3.1 научила ядро считать прибавку,
          # — и снятие устойчиво к усечению лестницы: `scores_at(build, rs, 9)`
          # даёт 14, а не только финальные 14.
          #
          # ⚠️ У ПЯТИ СТРОК НИЖЕ ПРОПАЛА ПЕРВАЯ ПРИЧИНА — задача 3.31
          # (15.08.2026). Стояло `{:requires_spell_level, 9}` рядом со
          # Spellcraft, и первая была наша: страницы всех шести эпических
          # заклинаний сами пишут, что «the ability to cast 9th level spells»
          # не настоящее требование, а настоящее — «эпический клирик/друид/
          # соркерер/волшебник, либо 15 уровней Бледного мастера, и только
          # на уровне этого класса». Замер Dan подтвердил (см.
          # `@prerequisite_causes` выше). Все пять взяты на уровнях Бледного
          # мастера при ПМ 16/19/22/25/28, то есть право у них есть.
          #
          # ⚠️ Вторая причина осталась у всех пяти, и это ГЛАВНАЯ проверка
          # ширины правки: Spellcraft — настоящее требование, оно прозой
          # не оспорено, и билд Dan (`user_builds_test.exs`), где Spellcraft
          # сходится, стал легальным, а этот — нет.
          prerequisites_unmet: [
            {26, :epic_spell_dragon_knight, [{:requires_skill_ranks, :spellcraft, 22}]},
            {29, :epic_spell_epic_mage_armor, [{:requires_skill_ranks, :spellcraft, 26}]},
            {32, :epic_spell_mummy_dust, [{:requires_skill_ranks, :spellcraft, 15}]},
            {35, :epic_spell_greater_ruin, [{:requires_skill_ranks, :spellcraft, 25}]},
            {38, :epic_spell_hellball, [{:requires_skill_ranks, :spellcraft, 32}]}
          ],
          caveats: [
            # 🔴 СЕМЬ СТРОК СНЯТО 17.08.2026, и все семь — один и тот же случай.
            # Здесь стояли четыре AC-оговорки («ни один из четырёх фитов не
            # идёт в постоянное число: `Expertise` и `Improved expertise` —
            # боевые режимы, `Divine shield` тратит попытку изгнания нежити,
            # `Epic mage armor` — заклинание») и три атакующих («вторая
            # половина одной сделки: `Expertise` торгует −5 атаки за +5 AC»).
            #
            # Про ЧИСЛО обе фразы верны и сегодня — ни одна прибавка никуда не
            # приехала. Изменилось, называем ли мы это дыркой в своём ответе:
            # боевой режим, попытка изгнания и заклинание — «включается и
            # кончается» (решение Dan 10.08.2026), и разметка всех семи записей
            # называет получателем `buff`. Оговорка про механику, которой
            # калькулятор не отвечает вовсе, — это не честность, а шум.
            #
            # ⚠️ Обратный порядок правки был бы ошибкой: сперва разметка в
            # данных (17.08.2026, пять файлов), и только потом строки отсюда.
            # Снять их «потому что тест красный» значило бы спрятать регрессию.
            # 🔴 Снято задачей 3.93 (25.08.2026): `epic_energy_resistance` — получатель
            # эффекта не наш. Разбор целиком в moduledoc; это НЕ «прибавку научились
            # считать».
            # ⚠️ `great_charisma` снят с задачи 3.1 — по той же причине, по
            # которой волной раньше сняли `epic_toughness`: его +1 к харизме
            # за взятие ядро теперь считает и называет в разборе
            # характеристик, и оговорка «прибавку не считаем» спорила бы
            # с числом на экране.
            # 🔴 Снято задачей 3.93 (25.08.2026): `spell_focus` — получатель эффекта не наш.
            # Разбор целиком в moduledoc; это НЕ «прибавку научились считать».
          ],
          attack_ability: :str,
          declared: 20,
          slots: 20,
          filled: 20
        }
      },
      # ⚠️ Здесь стояло `hp_gain: nil` со словами «pale master d8 + CON 17
      # (+3) — but the build's hit points are nil». Обе половины были неверны
      # уже тогда: у Бледного мастера d6, а не d8, и CON у листа 18, а не 17.
      # Задача 3.37 сделала прирост считаемым, и он равен 11:
      #   d6 (Бледный мастер) + 4 (мод CON 18) + 1 (Toughness за новый
      #   уровень персонажа) = 11.
      # Skill points: pale master 2 + INT 14 (+2).
      level_41: %{class: :pale_master, hp_gain: 11, skill_point_gain: 4},
      # ⚠️ Ваниль расходится с Сиалой на 60 хитов, и НИ ОДИН из них не про
      # хит-дайс: бесплатный `Toughness` Чёрного стража (40) и «Дух Сиалы»
      # (20) — обе выдачи сиальские. Кости и телосложение совпадают до
      # единицы, потому что шкалу РДД задача 3.37 положила в ВАНИЛЬНЫЙ слой:
      # она прочитана со страницы Fandom, а замер Dan только подтвердил, что
      # шард её не трогал. Разойдись здесь ещё и кости — это значило бы, что
      # шкала уехала в сиальский слой.
      vanilla: %{hp: 454},
      # The hand-written requirement layer is vanilla, not a shard override, so
      # both prestige classes read the same under either ruleset.
      vanilla_gaps: [
        # ⚠️ Задача 3.34: то же и на ванили — правило про дальнюю атаку общее,
        # а оружия страница не называет ни там, ни там.
        not_modelled: {:attack_ability_default, :ranged},
        # ⚠️ И здесь стоял `missing_data: {:hit_die, :red_dragon_disciple}` —
        # снят задачей 3.37 (16.08.2026). Ушёл у ОБОИХ ruleset'ов сразу, и это
        # главное, что доказывает список: шкала лежит в ванильном слое.
        # ⚠️ И здесь стоял `deathless_vigor` — снят тем же замером 13.08.2026.
        # Ванильная страница Бледного мастера и есть источник прибавки, шард про
        # неё молчит, поэтому она посчитана одинаково на обоих ruleset'ах —
        # как раньше одинаково не считалась.
        # ⚠️ И здесь стояло `assumed: :ac_bonus_types_unstated` — снято
        # задачей 3.90 у ОБОИХ ruleset'ов сразу, и это ровно то, что список
        # доказывает: `Bone skin`, `Draconic armor` и размер Карлика —
        # ванильные факты, шард их не трогал, разметка одна на два ruleset'а.
        # И `Bull's strength` Чёрного стража — тоже ванильный факт.
        not_modelled: {:ability_bonus, :bulls_strength_feat},
        # Задача 1.12a: `Hardiness vs. illusions` — расовая склонность, шард
        # рас не меняет механически (CLAUDE.md §3, решение Dan), значит на
        # обоих ruleset'ах одна и та же оговорка.
        # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
        # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
        #   hardiness_vs_illusions(save_bonus)
        # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
        # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
        # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
        # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
        # Задача 1.12b: и по той же причине совпадают две склонности Карлика к
        # атаке и `Smite good` Чёрного стража — все три ванильные, шард их не
        # трогал.
        # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
        # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
        #   battle_training_vs_goblins(attack_bonus), battle_training_vs_reptilians(attack_bonus)
        # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
        # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
        # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
        # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
        not_modelled: {:attack_bonus, :smite_good}
        # ⚠️ Здесь стояло `assumed: {:attack_cap_covers, :race_feat}` — сторона
        # капа у `Small stature` как допущение. Снято 09.08.2026 вечером, когда
        # Dan назвал склонность в списке: сторона стала правилом, а не догадкой,
        # и на обоих ruleset'ах одинаково — потолок +20 ванильный и лежит
        # в секции, которую видят оба слоя (`@vanilla_sections` загрузчика).
      ],
      divergences: []
    },
    %{
      title: "Гном Защитник",
      revid: 19_525,
      page: %{
        race: :dwarf,
        alignment: :lawful_good,
        # CHA 6 is impossible as a point-buy score (the scale starts at 8) and is
        # exactly 8 − 2 for a Dwarf: proof that these are sheet values
        abilities: %{str: 16, dex: 13, con: 18, int: 13, wis: 8, cha: 6},
        ability_increases: %{str: 10},
        character_level: 40,
        class_levels: %{fighter: 8, weapon_master: 7, dwarven_defender: 25},
        skill_points: 142,
        free_skill_points: 8,
        committed_ranks: %{intimidate: 4, tumble: 20, discipline: 43, heal_skill: 43},
        attack_bonus: 55,
        saves: %{fort: 61, ref: 46, will: 45},
        spell_resistance: nil
      },
      model: %{
        # first 20: dwarven defender 10 → 10/7/3/7, fighter 8 → 8/6/2/2, weapon
        # master 2 → 2/0/3/0. Sum 20/13/8/9, +10 attack / +10 saves from epic.
        base_attack: 30,
        base_saves: %{fort: 23, ref: 18, will: 19},
        base_saves_by_class: %{
          dwarven_defender: %{levels: 10, fort: 7, ref: 3, will: 7},
          fighter: %{levels: 8, fort: 6, ref: 2, will: 2},
          weapon_master: %{levels: 2, fort: 0, ref: 3, will: 0}
        },
        attacks_per_round: 4,
        # CON 18 → +4 без фитов, maximum hit die always on Siala (CLAUDE.md §3,
        # source: user). 25 × (d12 + 4) + 8 × (d10 + 4) + 7 × (d10 + 4) = 610,
        # плюс 40 от `Toughness`, который все три класса выдают даром на своём
        # 1-м уровне (задача 1.9, siala:Живучесть revid 16727) — по 1 хиту за
        # каждый из 40 уровней ПЕРСОНАЖА. ⚠️ И плюс ещё 40 от двух взятий
        # `Great constitution` (24, 27 уровни): +1 CON каждое
        # (vanilla/feat_ability_bonuses.json, fandom:Great_constitution revid
        # 51384) поднимают CON 18 → 20, модификатор +4 → +5, а этот
        # модификатор входит в КАЖДЫЙ из 40 уровней — 610 + 40 (Toughness) +
        # 40 (Great constitution ×2) = 690, плюс 20 от «Духа Сиалы» (задача,
        # волна 12, 09.08.2026 — флэт, безусловный, посчитан бы даже без
        # feats: true) = 710. AGENT_QUEUE.md §7 «Стенд регрессии считает числа
        # без фитов»: прибавки Great constitution не было видно, пока стенд
        # звал `to_build/3` без `feats: true` — найдено при починке 08.08.2026,
        # а не было в исходном долге (там назывались только Сагровик и
        # Паладин Адры).
        hp: 710,
        # «in a melee weapon» is Weapon Master's own requirement, refining
        # «Weapon focus»: the schema cannot say "the feat, taken in a melee
        # weapon", so the class is offered on the rest and the refinement is
        # declared.
        gaps: [
          # ⚠️ Задача 3.34 (15.08.2026): страница оружия не называет, а с 15.08
          # от него зависит сама характеристика броска (дальний бой — ловкость,
          # замер N1). Модель ответила ближним боем и говорит об этом — разбор
          # в шапке файла.
          {:not_modelled, {:attack_ability_default, :ranged}}
          # 🔴 ЗАДАЧА 3.107 СНЯЛА ЭТУ СТРОКУ, И СНЯЛА ЕЁ ПРАВИЛОМ, А НЕ
          # ВЫЧЁРКИВАНИЕМ. Здесь стояло `{:not_modelled, {:class_qualifier,
          # :weapon_master, "unarmed strike is excluded from the
          # prerequisites"}}` с пояснением, что второе исключение страницы
          # названо ИМЕНЕМ ОДНОГО ПРЕДМЕТА, а не свойством, и потому
          # не проверяется. Проверяется с 26.08.2026: имя и записано именем
          # (`feat_choice_excludes`, перечисление — потому что перечисляет
          # источник), а замер Dan (кейс AC1) показал, что оговорка прикрывала
          # ложную ЛЕГАЛЬНОСТЬ — `Weapon Focus (Unarmed strike)` открывал класс,
          # которого в игре нет в списке.
          #
          # ⚠️ Легальность ЭТОГО билда не изменилась: его фокус оружия —
          # не рукопашный удар. Ушла ровно оговорка.
          # 🔴 ДВЕ СТРОКИ ПРО БОЕВУЮ СТОЙКУ СНЯТЫ 17.08.2026. Стояли
          # `{:not_modelled, {:ac_bonus, :defensive_stance}}` (+4 уклонения,
          # задача 3.11) и `{:not_modelled, {:ability_bonus, :defensive_stance}}`
          # (+2 силы и +4 телосложения, задача 3.1), и обе объяснялись одинаково:
          # «в постоянное „Итого“ не идёт — режим по умолчанию выключен, — но
          # называется». Первая половина не изменилась ни на единицу; вторая
          # снята — «столько раз в день, сколько позволяет уровень класса»
          # и есть определение баффа, и разметка обеих записей это называет.
          #
          # ⚠️ Довод «две оговорки про одно умение — не дубль, у них разные
          # получатели» был верен и остался верен: получателей действительно
          # два, просто ни один из них не наш. Уходят они поэтому вместе — и
          # это то же самое, что уже случилось с САМИМ фактом стойки в классовом
          # слое, оговорка про который висит строкой ниже как
          # `group_stance_requirements`.
          #
          # ⚠️ `Defensive awareness` здесь не появлялся и не появился: он
          # возвращает бонус ловкости застигнутому врасплох, а к AC не
          # прибавляет ничего. Его собственная оговорка живёт по сейвам.
          # ⚠️ ЗДЕСЬ СТОЯЛА ОГОВОРКА ПРО БОНУС РАСЫ ГНОМА (Dwarf) — поглощение
          # элементального урона, `{:not_modelled, {:racial_bonus, :dwarf,
          # :damage_resistance}}`. Снята задачей 3.38 (16.08.2026) по решению
          # Dan: показать поглощение по-прежнему негде (в билде нет ни строки
          # урона, ни строки сопротивления), но именно поэтому и оговорки нет —
          # калькулятор такого вопроса не задаёт, значит и дырки в ответе не
          # имеет (CLAUDE.md §9, то же решение, что убрало с экрана бо́льшую
          # часть из 89 классовых фактов).
          # ⚠️ И ничего не появилось ВМЕСТО: `{:missing_data, {:racial_bonus_level,
          # :dwarf}}` тут быть не должно — бонус не «неизвестной величины»,
          # его вида у нас нет вовсе. Под тестом в `racial_bonus_test.exs`.
          #
          # 08.08.2026: воин 8 / мастер оружия 7 / гномий защитник 25 — все три
          # класса из списка Сагры, других уровней нет, значит билд **воин
          # Сагры**. Числа это не двигает: у Гнома (Dwarf) бонус расы — то самое
          # поглощение урона, которому негде лечь, поэтому вариант сагровика
          # некуда применить. Остаётся оговорка про остальное, что даёт группа:
          # зелья, точило и множитель от оружия — армори.
          # ⚠️ ЗДЕСЬ СТОЯЛА `{:not_modelled, {:class_group_benefits,
          # :sagra_warriors}}` — снята задачей 3.100 (25.08.2026). Непосчитанного
          # у группы столько же, сколько было: зелья Сагры, зелья Азарака, точило.
          # Изменилось не число, а признание: у всех трёх строк теперь назван
          # ПОЛУЧАТЕЛЬ (`custom_items`, `buff` — `systems.json`, affects_by_benefit),
          # и ни один из них калькулятор не печатает. Гэп — дырка в НАШЕМ ответе
          # (CLAUDE.md §9), а вопроса про расходники мы не задаём вовсе.
          # ⚠️ «Усиленный бонус от оружия» этой правки не касается: он посчитан
          # с задачи 3.35 и вычитается раньше, чем читается получатель.
          # 🔴 ТРЕТЬЯ СТРОКА ПРО БОЕВУЮ СТОЙКУ СНЯТА 18.08.2026 (шестой файл
          # семейства прибавок, `feat_save_bonuses.json`). Стояла
          # `{:not_modelled, {:save_bonus, :defensive_stance}}` — та же +2
          # к сейвам («resistance bonus on all saves»), тот же довод, что
          # у AC/STR/CON выше (режим по умолчанию выключен), просто третий
          # получатель дошёл до разметки на день позже двух других. Теперь
          # все три оговорки про это умение сняты, и осталась только
          # `group_stance_requirements` в `class_caveats` ниже — она про
          # занятую щитом руку, то есть AC, который мы печатаем.
          # `Defensive awareness`, ступень 3 из 3: +1 к Reflex, но только
          # против ловушек — узкая цель, не общий сейв.
          # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
          # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
          #   defensive_awareness(save_bonus)
          # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
          # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
          # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
          # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
          # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
          # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
          # Раса Гном (Dwarf, CLAUDE.md §4) несёт ДВЕ расовые склонности к
          # сейвам сразу — обе узкие (яд/заклинания), обе не входят в число.
          # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
          # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
          #   hardiness_vs_poisons(save_bonus), hardiness_vs_spells(save_bonus)
          # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
          # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
          # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
          # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
          # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
          # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
          # Задача 1.12b: та же раса несёт ещё две склонности к АТАКЕ, и они
          # тоже узкие — по виду врага (+1 против орков, +1 против гоблиноидов).
          # ⚠️ Третья, `Battle training vs. giants`, в этом списке отсутствует
          # не по недосмотру: она даёт +4 УКЛОНЕНИЯ к AC, а не атаку, и лежит
          # в ac_bonuses.json. Семью нельзя размечать по имени.
          # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
          # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
          #   battle_training_vs_goblins(attack_bonus), battle_training_vs_orcs(attack_bonus)
          # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
          # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
          # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
          # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
          # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
          # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
          # ⚠️ Здесь стоял `{:not_modelled, {:attack_bonus_weapon,
          # :weapon_master}}` — «колонка AB bonus не посчитана, оружие
          # не названо». Он не исчез, а ПЕРЕЕХАЛ в `feats.caveats` ниже
          # (14.08.2026): этот список считается по билду БЕЗ фитов, а колонка
          # с того дня требует владения `Weapon of choice`, и без фитов её
          # у персонажа нет вовсе. Оговорка про непосчитанную колонку у того,
          # кто на колонку не имеет права, предупреждала бы о том, чего
          # не происходит.
          # ⚠️ Соседний гэп про тот же класс, `extra_attack_bonus_past_class_
          # level_10` (в `class_caveats` ниже), НЕ про то же самое: там шард
          # называет каденцию и не называет величину, здесь величина известна
          # и не считается по другой причине. Два разных незнания.
        ],
        # ⚠ `extra_attack_bonus_past_class_level_10` (and its sibling
        # `attack_bonus_progression`) was the reason this file stopped pinning
        # an empty list: this build has 25 Weapon Master levels, the shard
        # said something about attacks past the tenth, and the fact was
        # `unclear` in the data. `attacks_per_round: 4` above used to be
        # pinned *with* that caveat outstanding.
        #
        # ⚠️ 17.08.2026 (задача про Мастера оружия): `weapon_master` УШЁЛ
        # из этого списка целиком — замер Dan показал, что каденция «+AB
        # каждые 3 уровня после 10-го» это ванильная колонка
        # `feat_attack_bonuses.json` (Superior/Epic superior weapon focus),
        # уже посчитанная ядром, а не сиальское изменение. Обе записи слиты
        # в одну с получателем `counted_elsewhere` — у класса не осталось
        # ни одного факта с нашим получателем.
        #
        # ⚠️ `class_group` ушёл из этого списка 08.08.2026 у всех семи классов,
        # которые его несли: факт «класс входит в группу воинов Сагры/Адры»
        # теперь ПРИМЕНЯЕТСЯ (`Rules.ClassGroups`), а не лежит непрочитанным.
        # Что группа даёт — по-прежнему не в числах, но это сказано одной
        # оговоркой на группу, а не тремя одинаковыми на каждый класс.
        # ⚠️ `group_stance` (сама стойка) ушёл с 3.28: её числа — штрафы ЧУЖИМ
        # персонажам в радиусе и количество применений за отдых, то есть
        # `special_ability` + `ability_uses`, ни одного нашего числа.
        # ⚠️ `group_stance_requirements` ушёл 21.08.2026 (задача 3.75), и здесь
        # стояло «остался — он про занятую щитом руку, а это AC, который мы
        # печатаем». Посылка оказалась неверной: предмет стойки **юзабельный**,
        # слот щита не занимает и надеть его нельзя (решение Dan). Руку он
        # не занимает, щитового AC не даёт, двуручное оружие не запрещает —
        # то есть до нашего ответа не доезжает ничем.
        #
        # 🔴 Тем самым две половины ОДНОЙ механики наконец помечены согласованно:
        # сама стойка ушла ещё с 3.28 как `special_ability` + `ability_uses`,
        # а её требование числилось нашим через `affects: ["ac"]` — требование
        # для способности, выведенной из области ответа.
        #
        # Список пуст, и это состояние, а не забытая строка: у билда из воина,
        # Гнома Защитника и Мастера оружия не осталось ни одного факта класса,
        # который мы читаем и не считаем.
        class_caveats: %{},
        # all three classes give 2, INT 13 → +1: 12 on level 1, 3 × 39 after
        skill_points_earned: 129,
        # Intimidate 4 bought on level 8, a Fighter level with no Intimidate →
        # 2 each = 8; Tumble is a class skill of none of the three → 20 × 2 = 40;
        # Discipline and Heal are class skills of all three → 43 + 43.
        plan_cost: 134,
        feats: %{
          taken: %{
            1 => [:luck_of_heroes, :dodge],
            2 => [:mobility],
            3 => [:expertise],
            4 => [:spring_attack],
            6 => [:whirlwind_attack, :siala_blade_proficiency],
            8 => [:weapon_focus],
            9 => [:blind_fight, :weapon_of_choice],
            12 => [:great_fortitude],
            15 => [:improved_critical],
            18 => [:siala_hammer_proficiency],
            21 => [:epic_fortitude],
            24 => [:great_strength],
            27 => [:great_strength],
            28 => [:armor_skin],
            30 => [:great_constitution],
            33 => [:great_constitution, :epic_weapon_focus],
            36 => [:epic_energy_resistance],
            37 => [:epic_prowess],
            39 => [:epic_energy_resistance]
          },
          # ⚠️ Здесь стояло `granted: [{9, :weapon_of_choice}]` с доводом «Weapon
          # Master hands Weapon of Choice over at its first class level, so the
          # page's line is a restatement and not a second feat». Замеры M2/M2b
          # (14.08.2026) показали, что класс его не выдаёт вовсе: первый уровень
          # даёт СЛОТ. Значит строка страницы — не повтор выдачи, а настоящий
          # пик, и он занимает классовый слот Мастера оружия.
          granted: [],
          unplaced: [{28, :armor_skin}],
          unreadable: [],
          prerequisites_unmet: [],
          caveats: [
            # ⚠️ `Armor skin` этого билда в списке НЕ появляется, и это верно:
            # он лежит в `unplaced` выше (слота на 28-м уровне для него нет),
            # то есть персонаж им не владеет. Прибавка к AC следует за
            # владением, а не за строкой на странице.
            #
            # 🔴 `Expertise` (и по AC, и по атаке) снят 17.08.2026 — боевой
            # режим, получатель `buff`. А `Dodge` и `Mobility` рядом ОСТАЛИСЬ
            # и держат правку честной: они тоже не посчитаны, но пассивны
            # и помечены `ac`, то есть дырка в нашем ответе настоящая. Три
            # соседние строки из одного файла, два разных ответа — ровно то
            # различие, ради которого разметка и заведена.
            # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
            # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
            #   dodge(ac_bonus), mobility(ac_bonus)
            # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
            # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
            # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
            # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
            # 🔴 Снято задачей 3.93 (25.08.2026): `epic_energy_resistance` — получатель
            # эффекта не наш. Разбор целиком в moduledoc; это НЕ «прибавку научились
            # считать».
            # ⚠️ `great_constitution` и `great_strength` сняты с задачи 3.1:
            # их прибавки посчитаны и названы поимённо в разборе
            # характеристик.
            # 🔴 Снято задачей 3.93 (25.08.2026): `improved_critical` — получатель эффекта не
            # наш. Разбор целиком в moduledoc; это НЕ «прибавку научились считать».
            # ⚠️ Здесь стояла `not_modelled: {:feat_bonus, :weapon_of_choice}` —
            # появилась 14.08.2026 вместе с M2/M2b (фит перестал выдаваться
            # классом и стал пиком, а оговорки идут по ВЗЯТЫМ фитам) и снята
            # в тот же день, решением Dan. Она была неверна дважды: фит числа
            # не даёт вовсе (он НАЗНАЧАЕТ оружие колонке Мастера оружия), а
            # второе взятие покупает второе избранное оружие, то есть смысл
            # «повторное взятие ничего не купит» здесь не работает. Теперь
            # запись `weapon_of_choice` в разметке атаки помечена
            # `counted_elsewhere` → `weapon_master`, и ядро это читает.
            # Задача 1.12b. ⚠️ `Epic prowess` этого билда (37-й уровень) в
            # списке НЕ появляется — его +1 ПОСЧИТАН (`own_attack_bonus`
            # 0 → 1 с фитами, AB 38 → 40 вместе с `Great strength`), и оговорка
            # спорила бы с числом на экране.
            # ⚠️ И с 17.08.2026 не появляется `{:attack_bonus, :expertise}` —
            # по другой причине, которую с первой путать нельзя: этот −5
            # НЕ посчитан, просто боевой режим не то, о чём калькулятор даёт
            # ответ. «Посчитано, поэтому молчим» и «не наше, поэтому молчим» —
            # два разных умолчания, и оба обязаны быть названы, иначе список
            # читается как «здесь всё сходится».
            # ⚠️ ЗДЕСЬ СТОЯЛО «у фокуса ДВЕ оговорки, и они разные»: старая
            # (`feat_qualifier … "with the chosen weapon"`) — «мы не проверили
            # ТРЕБОВАНИЕ фита», новая — «мы не посчитали его ПРИБАВКУ».
            # Первой больше нет: задача 3.99 сделала требование проверяемым,
            # ровно как эта строка и предсказывала («исчезнет, когда схема
            # научится выражать оговорку требования»). Осталась вторая,
            # и она ждёт армори.
            not_modelled: {:attack_bonus_weapon, :epic_weapon_focus},
            not_modelled: {:attack_bonus_weapon, :weapon_focus},
            # ⚠️ А ЭТА оговорка сюда ПЕРЕЕХАЛА из `gaps` билда (14.08.2026), и
            # переезд содержателен: колонка «AB bonus» Мастера оружия теперь
            # требует владения `Weapon of choice`, значит её непосчитанность —
            # следствие взятого фита, а не свойство лестницы. Раньше она стояла
            # в обоих списках сразу и потому не числилась «добавленной фитами».
            not_modelled: {:attack_bonus_weapon, :weapon_master}
          ],
          attack_ability: :str,
          declared: 23,
          # ⚠️ 22 → 23 и 21 → 22 правкой 14.08.2026 (замеры M2/M2b): первый
          # уровень Мастера оружия перестал ВЫДАВАТЬ `Weapon of choice`
          # и стал давать слот, значит слотов на один больше и занят он тем же
          # фитом, который раньше числился выдачей.
          slots: 23,
          # 19 → 21: both `epic energy resistance` levels now land in the
          # general epic slot they always belonged in (`type=defensive` is
          # Fandom's taxonomy, not a slot flag — see @feat_refusals).
          filled: 22
        }
      },
      # dwarven defender d12 + CON 18→20 (+5 с учётом двух `Great
      # constitution`) + 1 from Toughness = 18. ⚠️ Дельта тоже чувствует фит:
      # `Great constitution` прибавляет модификатор на КАЖДОМ уровне,
      # включая только что добавленный 41-й, поэтому она не сокращается при
      # вычитании (в отличие от плоской `Epic toughness` у других билдов).
      # skill points 2 + INT 13 (+1) = 3
      level_41: %{class: :dwarven_defender, hp_gain: 18, skill_point_gain: 3},
      # Vanilla hands `Toughness` to nobody — the free feat is the shard's.
      # `Great constitution` is ordinary vanilla, though, and Siala did not
      # touch it — so под ванилью тот же +40 от него остаётся: 610 (dice +
      # CON 18) + 40 (Great constitution ×2) = 650, без Toughness.
      vanilla: %{hp: 650},
      vanilla_gaps: [
        # ⚠️ Задача 3.34: то же и на ванили — правило про дальнюю атаку общее,
        # а оружия страница не называет ни там, ни там.
        not_modelled: {:attack_ability_default, :ranged},
        # 🔴 ЗАДАЧА 3.107 СНЯЛА ЭТУ СТРОКУ ПРАВИЛОМ, А НЕ ВЫЧЁРКИВАНИЕМ —
        # разбор в сиальской половине этой же фикстуры. Правило ванильное
        # (`fandom:Unarmed strike` называет оба класса поимённо), поэтому
        # оговорка ушла на ОБОИХ ruleset'ах, а не только у Сиалы.
        not_modelled: {:ac_bonus, :defensive_stance},
        not_modelled: {:ability_bonus, :defensive_stance},
        # Задача 1.12a: все четыре — ванильные факты (стойка Гномьего
        # защитника, расовые склонности Гнома/Dwarf), шард их не переписывал.
        not_modelled: {:save_bonus, :defensive_stance}
        # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
        # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
        #   defensive_awareness(save_bonus), hardiness_vs_poisons(save_bonus), hardiness_vs_spells(save_bonus)
        # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
        # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
        # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
        # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
        # Задача 1.12b: то же и здесь — две расовые склонности к атаке
        # ванильные целиком, шард их не переписывал.
        # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
        # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
        #   battle_training_vs_goblins(attack_bonus), battle_training_vs_orcs(attack_bonus)
        # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
        # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
        # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
        # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
        # ⚠️ Здесь стояла и колонка «AB bonus» Мастера оружия — ушла
        # 14.08.2026 по той же причине, что из `model.gaps` выше: список
        # считается по билду БЕЗ фитов, а колонка теперь требует владения
        # `Weapon of choice`. Таблица Fandom при этом та же на обоих
        # ruleset'ах, и с фитами оговорка на месте на обоих.
      ],
      divergences: [
        %{
          field: :skill_points_earned,
          page: 142,
          model: 129,
          verdict: :page_arithmetic,
          # The page's own spending arithmetic agrees with ours to the point:
          # 142 − 8 free = 134, and pricing its rank list with our 1/2 rule gives
          # exactly 134. Only the earned total differs, by the same +13 as
          # «Мастер оружия Сагровик» — the other build in the same hub — while
          # «Мастер Вор» is −5 and «Мастер Монах» is exact. Divergences that do
          # not point the same way are not a missing rule (CLAUDE.md §3).
          note: "same +13 as Сагровик; spending arithmetic matches exactly"
        },
        %{
          field: :plan_cost_fits,
          page: true,
          model: false,
          verdict: :follows_from_skill_points,
          # A consequence of the +13, not a separate finding: at 129 earned the
          # build cannot afford its own 134-point rank list. If the page is right
          # about 142 it can; if we are right it is five points short.
          note: "134 > 129 earned — the build overspends unless the page's 142 is right"
        }
      ]
    },
    %{
      title: "Мастер Вор",
      revid: 17_941,
      page: %{
        race: :elf,
        alignment: :lawful_evil,
        abilities: %{str: 10, dex: 16, con: 14, int: 14, wis: 14, cha: 8},
        ability_increases: %{dex: 10},
        character_level: 40,
        class_levels: %{ranger: 5, rogue: 31, shadowdancer: 4},
        skill_points: 385,
        free_skill_points: 8,
        committed_ranks: %{
          hide: 43,
          move_silently: 43,
          spot: 43,
          discipline: 43,
          heal_skill: 43,
          set_trap: 43,
          craft_trap: 43,
          search: 43,
          use_magic_device: 33,
          tumble: 5
        },
        attack_bonus: 48,
        saves: %{fort: 53, ref: 57, will: 44},
        spell_resistance: nil
      },
      model: %{
        # first 20: ranger 4 → 4/4/1/1, rogue 12 → 9/4/8/4, shadowdancer 4 →
        # 3/1/4/1. Sum 16/9/13/6, +10/+10 epic. The nineteen rogue levels taken
        # after 20 add nothing here — this is the rule that makes class order
        # irreversible.
        base_attack: 26,
        base_saves: %{fort: 19, ref: 23, will: 16},
        base_saves_by_class: %{
          ranger: %{levels: 4, fort: 4, ref: 1, will: 1},
          rogue: %{levels: 12, fort: 4, ref: 8, will: 4},
          shadowdancer: %{levels: 4, fort: 1, ref: 4, will: 1}
        },
        # base attack 16 at level 20 → 4 attacks
        attacks_per_round: 4,
        # CON 14 → +2. 5 × (d10 + 2) + 31 × (d6 + 2) + 4 × (d8 + 2) = 348, плюс
        # 40 от `Toughness`: пять уровней рейнджера приносят фит даром, а платит
        # он за каждый уровень ПЕРСОНАЖА, включая 31 воровской (задача 1.9),
        # плюс 20 от «Духа Сиалы» — флэт, безусловный (задача, волна 12,
        # 09.08.2026) — 348 + 40 + 20 = 408.
        hp: 408,
        gaps: [
          # ⚠️ Задача 3.34 (15.08.2026): страница оружия не называет, а с 15.08
          # от него зависит сама характеристика броска (дальний бой — ловкость,
          # замер N1). Модель ответила ближним боем и говорит об этом — разбор
          # в шапке файла.
          {:not_modelled, {:attack_ability_default, :ranged}}
          # ⚠️ Здесь стояла `{:not_modelled, {:ac_bonus, :shadow_evade}}`
          # (задача 3.11): четыре уровня Теневого танцора приносят умение,
          # дающее AC. Снята 17.08.2026 — своё же объяснение и снимало её:
          # «активируется, три раза в день на несколько раундов». Тот же
          # `Shadow evade` Dan объявил баффом ещё 10.08.2026, разбирая
          # классовые факты; до слоя разметки прибавок решение доехало теперь.
          # Число не изменилось: в «Итого» оно не шло и не идёт.
          # Задача 1.12a: `Uncanny dodge` (ступени выше первой, вор его несёт
          # сам) даёт узкую reflex-vs-traps прибавку, а раса приносит
          # `Hardiness vs. enchantments` — тоже узко (mind-affecting). Оба не
          # входят в постоянные сейвы.
          #
          # 🔴 И обе строки — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ к правке выше: они из
          # `feat_save_bonuses.json`, ЕДИНСТВЕННОГО файла семейства, который
          # разметки `affects` не получил вовсе. Правило «нет метки — значит
          # гэп» держит их на месте, и по ним видно, что фильтр не выкосил
          # оговорки скопом.
          # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
          # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
          #   uncanny_dodge(save_bonus), hardiness_vs_enchantments(save_bonus)
          # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
          # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
          # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
          # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
          # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
          # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
        ],
        # ⚠️ Из 18 фактов трёх классов остались 4 (3.28): у вора — три прибавки
        # к навыкам (условные, кейс замера L1) и у рейнджера — пул бонусных
        # фитов. Птица-шпион, стрелы, яды, иммунитет к тьме и плащ — не наши
        # числа. Переработанное умение Тени (`Shadow Evade`) числилось нашим
        # за названный AC, но 10.08.2026 решением Dan ушло в баффы: оно
        # активируется и кончается.
        # ⚠️ 17.08.2026 у ВОРА не осталось ни одной оговорки: последняя
        # (`stealth_perception_penalty`) ушла тем же гейтом по временности —
        # штраф действует только в режиме скрытности, а режим включается
        # и кончается («если штрафы вору идут только в режиме хайда, то мы их
        # не показываем», Dan). Пустой список оставлен НАРОЧНО вместо удаления
        # ключа: «у вора оговорок нет» — утверждение, которое ловит их возврат,
        # а отсутствующий ключ молчит про это так же, как про всё остальное.
        # ⚠️ 24.08.2026 (задача 3.85): у Рейнджера не осталось ни одной оговорки —
        # `bonus_feat_pool` применён по замерам U1 и U2, и гэп был ЛОЖНЫМ
        # (пять сиальских владений лежали в бонусном слоте всё это время,
        # их кладут туда сами страницы фитов). Пустой список оставлен
        # НАРОЧНО вместо удаления ключа: он ловит возврат оговорки, а
        # отсутствующий ключ молчал бы про это так же, как про всё остальное.
        class_caveats: %{
          ranger: [],
          rogue: []
        },
        # INT 14 → +2. ranger 4, rogue 8, shadowdancer 6: 24 on level 1, then
        # 6/10/8 by the class of each level
        skill_points_earned: 390,
        # every skill on the list is a class skill of ranger, rogue or
        # shadowdancer, so 8 × 43 + 33; Tumble 5 is pinned to level 7, a Rogue
        # level that has it → 5 × 1
        plan_cost: 382,
        feats: %{
          taken: %{
            1 => [:blooded, :siala_blade_proficiency],
            3 => [:dodge],
            6 => [:mobility],
            9 => [:skill_focus],
            12 => [:skill_focus],
            15 => [:great_fortitude],
            17 => [:crippling_strike],
            18 => [:alertness],
            21 => [:epic_fortitude, :epic_skill_focus],
            24 => [:weapon_focus, :epic_skill_focus],
            27 => [:improved_critical, :epic_skill_focus],
            30 => [:weapon_finesse],
            32 => [:epic_skill_focus],
            33 => [:blind_fight],
            36 => [:stealthy, :defensive_roll],
            39 => [:epic_dodge],
            40 => [:epic_weapon_focus]
          },
          granted: [],
          # AGENT_QUEUE.md §1.8: this build's level 1 is Ranger, whose bonus
          # slot the shard names by the level it picks a favoured enemy rather
          # than by "доп фитах" — the wiki's own words parsed to a slot kind
          # the loader did not yet recognise. `siala_blade_proficiency` used
          # to sit here unplaced; `overrides.json` → `feats.bonus_slot_aliases`
          # reads that name as the ordinary Ranger bonus slot it is.
          unplaced: [],
          unreadable: [],
          # The three `epic skill focus` entries only appear here now that the
          # rogue's bonus slot accepts them at all: an unplaced feat is never
          # checked against its prerequisites, so placing one is what makes its
          # requirement visible. They join the fourth for the same reason as
          # every other rank requirement in this file — the fixtures encode no
          # per-level rank schedule (@prerequisite_causes).
          prerequisites_unmet: [
            {21, :epic_skill_focus, [requires_any_skill_ranks: 20]},
            {24, :epic_skill_focus, [requires_any_skill_ranks: 20]},
            {27, :epic_skill_focus, [requires_any_skill_ranks: 20]},
            {32, :epic_skill_focus, [requires_any_skill_ranks: 20]}
            # ⚠️ Здесь стоял `{36, :defensive_roll, [missing_data: …]}` — отказ
            # ядра читать непрочитанную прозу. Волна 4 её дочитала
            # (`vanilla/feats.json`: Вор 10 ИЛИ Теневой танцор 5), у этого билда
            # 31 уровень вора, и требование просто выполнено. Отказ не обойдён,
            # а перестал существовать.
          ],
          # Weapon Finesse at level 30 is the §6 third kind of feat — it changes
          # the formula rather than adding to it — so this is the fixture that
          # holds the `abStat` switch in place: attack comes off dexterity here.
          caveats: [
            assumed: :finessable_weapon,
            # Оба фита — требования Теневого танцора, поэтому стоят в каждом
            # скрытном билде. AC они дают условный (`Dodge` — против текущей
            # цели, `Mobility` — против атак по возможности), в число не идут.
            # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
            # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
            #   dodge(ac_bonus), mobility(ac_bonus)
            # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
            # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
            # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
            # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
            # 🔴 Здесь стояли `{:feat_bonus, :skill_focus}` и
            # `{:feat_bonus, :epic_skill_focus}` — «прибавку от этого фита в статы
            # не считаем». Сняты задачей 3.92 по решению Dan: +3 и +10 идут
            # в значение ВЫБРАННОГО навыка и названы там термом с именем фита.
            # Оговорка, спорящая с напечатанным числом, хуже отсутствующей
            # (CLAUDE.md §6) — тот же ход, что у `improved_spell_resistance`
            # (3.45) и `epic_toughness` (1.9).
            # 🔴 Снято задачей 3.93 (25.08.2026): `improved_critical` — получатель эффекта не
            # наш. Разбор целиком в moduledoc; это НЕ «прибавку научились считать».
            # Задача 1.12b. ⚠️ Этот билд — положительный контроль на то, что
            # ПОСЧИТАННОЕ не отменяется непосчитанным: `attack_ability: :dex`
            # выше (Weapon Finesse, «третий вид фита» из §6) остался как был,
            # и число атаки по-прежнему считается от ловкости. Оговорок про
            # оружие ровно две, обе про ПРИБАВКИ фокуса, и ни одна не про
            # формулу — то есть Finesse не удвоился и не превратился в гэп.
            not_modelled: {:attack_bonus_weapon, :epic_weapon_focus},
            not_modelled: {:attack_bonus_weapon, :weapon_focus}
          ],
          attack_ability: :dex,
          declared: 22,
          slots: 22,
          # 17 → 21 → 22: three `epic skill focus` in the rogue's bonus slots at
          # class levels 13/16/19, `epic weapon focus` in the ranger's at class
          # level 5, and (§1.8) `siala_blade_proficiency` in the ranger's level-1
          # bonus slot, alongside Favored enemy rather than instead of it.
          filled: 22
        }
      },
      # ranger d10 + CON 14 (+2) + 1 от Toughness = 13; skill points 4 + INT 14 (+2) = 6
      level_41: %{class: :ranger, hp_gain: 13, skill_point_gain: 6},
      # Бесплатного Toughness в ванили нет — вся разница в его 40 хитах.
      vanilla: %{hp: 348},
      # Задача 1.12a: `Uncanny dodge` и раса Эльфа — ванильные факты, шард их
      # не переписывал.
      vanilla_gaps: [
        # ⚠️ Задача 3.34: то же и на ванили — правило про дальнюю атаку общее,
        # а оружия страница не называет ни там, ни там.
        not_modelled: {:attack_ability_default, :ranged},
        not_modelled: {:ac_bonus, :shadow_evade}
        # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
        # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
        #   uncanny_dodge(save_bonus), hardiness_vs_enchantments(save_bonus)
        # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
        # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
        # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
        # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
      ],
      divergences: [
        %{
          field: :skill_points_earned,
          page: 385,
          model: 390,
          verdict: :page_arithmetic,
          # −5 where the two «Билды для новичков» pages are +13: opposite signs
          # rule out a rule we are missing.
          note: "−5, opposite in sign to the +13 pages"
        },
        %{
          field: :plan_cost,
          page: 377,
          model: 382,
          verdict: :page_omission,
          # 385 − 8 free = 377, which is exactly our 382 minus the Tumble 5 the
          # page lists under «Обязательные навыки» and then leaves out of its own
          # subtraction. The prices themselves agree.
          note: "the page forgot the Tumble 5 it demands for Shadowdancer"
        }
      ]
    },
    %{
      title: "Мастер Ловушек",
      revid: 17_928,
      page: %{
        race: :elf,
        alignment: :lawful_evil,
        abilities: %{str: 10, dex: 16, con: 14, int: 14, wis: 14, cha: 8},
        ability_increases: %{dex: 10},
        character_level: 40,
        class_levels: %{ranger: 35, shadowdancer: 4, rogue: 1},
        skill_points: 314,
        free_skill_points: 175,
        # the five further skills the page lists are a menu, not a plan — it says
        # «Очков хватит на 4 из них» — so they are not counted as committed
        committed_ranks: %{hide: 43, move_silently: 43, spot: 43, tumble: 5},
        attack_bonus: 55,
        saves: %{fort: 56, ref: 50, will: 44},
        spell_resistance: nil
      },
      model: %{
        # first 20 levels are twenty ranger levels: 20/12/6/6, +10/+10 epic
        base_attack: 30,
        base_saves: %{fort: 22, ref: 16, will: 16},
        # ⚠ Теневой танцор и вор стоят в разборе С НУЛЯМИ, а не отсутствуют:
        # обе их лестницы целиком за окном, и именно это правило разбор обязан
        # проговорить числом на настоящей странице, а не только в юнит-тесте.
        base_saves_by_class: %{
          ranger: %{levels: 20, fort: 12, ref: 6, will: 6},
          shadowdancer: %{levels: 0, fort: 0, ref: 0, will: 0},
          rogue: %{levels: 0, fort: 0, ref: 0, will: 0}
        },
        attacks_per_round: 4,
        # CON 14 → +2. 35 × (d10 + 2) + 1 × (d6 + 2) + 4 × (d8 + 2) = 468,
        # плюс 40 от бесплатного `Toughness` рейнджера (задача 1.9), плюс 20
        # от «Духа Сиалы» (задача, волна 12, 09.08.2026) = 528.
        hp: 528,
        gaps: [
          # ⚠️ Задача 3.34 (15.08.2026): страница оружия не называет, а с 15.08
          # от него зависит сама характеристика броска (дальний бой — ловкость,
          # замер N1). Модель ответила ближним боем и говорит об этом — разбор
          # в шапке файла.
          {:not_modelled, {:attack_ability_default, :ranged}}
          # ⚠️ `{:not_modelled, {:ac_bonus, :shadow_evade}}` снята 17.08.2026 —
          # ровно так же, как у «Мастер Вор» выше, и это ВТОРАЯ половина того
          # же решения: классовый факт про Тень ушёл в баффы 10.08.2026 (см.
          # комментарий у `class_caveats` ниже, он это и говорит), а запись
          # разметки прибавок висела ещё неделю, потому что `affects` в этих
          # файлах никто не читал.
          # Задача 1.12a: как и у «Мастер Вор» — тот же `Uncanny dodge`
          # (владение от вора и теневого танцора) и та же расовая склонность
          # Эльфа. Обе из файла сейвов, у которого разметки нет, — то есть
          # положительный контроль к правке выше.
          # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
          # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
          #   uncanny_dodge(save_bonus), hardiness_vs_enchantments(save_bonus)
          # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
          # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
          # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
          # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
          # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
          # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
          # Задача 1.12b: рейнджер выдаёт `Improved two-weapon fighting` на 9-м
          # уровне класса даром — вторая атака левой рукой со штрафом −5. Штраф
          # существует только при бое двумя оружиями, стиля мы не моделируем.
          # ⚠️ Единственный из восьми билдов, у кого гэп про атаку приходит от
          # ВЫДАННОГО классом фита, а не от взятого в слот и не от расы.
          # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
          # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
          #   improved_two_weapon_fighting(attack_bonus)
          # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
          # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
          # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
          # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
          # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
          # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
        ],
        # The same three classes as «Мастер Вор», in different proportions — and
        # therefore the same caveats. They are keyed by class, not by level,
        # because no fact in `siala_41/classes.json` carries a level.
        # ⚠️ Из 18 фактов трёх классов остались 4 (3.28): у вора — три прибавки
        # к навыкам (условные, кейс замера L1) и у рейнджера — пул бонусных
        # фитов. Птица-шпион, стрелы, яды, иммунитет к тьме и плащ — не наши
        # числа. Переработанное умение Тени (`Shadow Evade`) числилось нашим
        # за названный AC, но 10.08.2026 решением Dan ушло в баффы: оно
        # активируется и кончается.
        # ⚠️ 17.08.2026 у ВОРА не осталось ни одной оговорки: последняя
        # (`stealth_perception_penalty`) ушла тем же гейтом по временности —
        # штраф действует только в режиме скрытности, а режим включается
        # и кончается («если штрафы вору идут только в режиме хайда, то мы их
        # не показываем», Dan). Пустой список оставлен НАРОЧНО вместо удаления
        # ключа: «у вора оговорок нет» — утверждение, которое ловит их возврат,
        # а отсутствующий ключ молчит про это так же, как про всё остальное.
        # ⚠️ 24.08.2026 (задача 3.85): у Рейнджера не осталось ни одной оговорки —
        # `bonus_feat_pool` применён по замерам U1 и U2, и гэп был ЛОЖНЫМ
        # (пять сиальских владений лежали в бонусном слоте всё это время,
        # их кладут туда сами страницы фитов). Пустой список оставлен
        # НАРОЧНО вместо удаления ключа: он ловит возврат оговорки, а
        # отсутствующий ключ молчал бы про это так же, как про всё остальное.
        class_caveats: %{
          ranger: [],
          rogue: []
        },
        # INT 14 → +2. 24 on level 1, then ranger 6 / shadowdancer 8 / rogue 10
        skill_points_earned: 270,
        # Hide, Move Silently and Spot are ranger class skills → 3 × 43; Tumble 5
        # is pinned to level 7, a Ranger level without it → 5 × 2
        plan_cost: 139,
        feats: %{
          taken: %{
            1 => [:blooded, :siala_blade_proficiency],
            3 => [:dodge],
            5 => [:siala_ranged_proficiency],
            6 => [:mobility],
            9 => [:skill_focus],
            10 => [:favored_enemy],
            12 => [:skill_focus],
            15 => [:great_fortitude, :favored_enemy],
            18 => [:alertness],
            20 => [:favored_enemy],
            21 => [:epic_skill_focus],
            24 => [:epic_skill_focus],
            27 => [:epic_fortitude, :bane_of_enemies],
            29 => [:epic_prowess],
            30 => [:weapon_focus, :epic_weapon_focus],
            33 => [:epic_skill_focus],
            34 => [:favored_enemy],
            35 => [:favored_enemy],
            36 => [:improved_critical],
            37 => [:blinding_speed],
            39 => [:blind_fight],
            40 => [:favored_enemy, :favored_enemy]
          },
          granted: [],
          # AGENT_QUEUE.md §1.8: this build's level 1 AND level 5 are both
          # Ranger, and both `siala_blade_proficiency` (1) and
          # `siala_ranged_proficiency` (5) used to sit here unplaced — the
          # ranger's own bonus slot at those levels (`overrides.json` →
          # `feats.bonus_slot_aliases`) now takes them, competing with
          # `favored_enemy` for the same slot rather than being refused by it.
          # ⚠ `{40, :favored_enemy}` stood here too until 14.08.2026, and it was
          # **the page corroborating the wiki against us**: character level 40 is
          # this build's 35th ranger level, the class page names *two* bonus
          # feats due there, this ladder line takes literally
          # `[:favored_enemy, :favored_enemy]` — and the slot model could only
          # express one, so the second was dropped. Both fit now
          # (`bonus_feat_counts` → two slots with distinct ids), and this list is
          # empty for the first time.
          unplaced: [],
          unreadable: [],
          # ⚠️ Шесть строк `favored_enemy` (уровни 10, 15, 20, 34, 35, 40) ушли
          # отсюда в волну 4: их требование дочитано (`vanilla/feats.json`:
          # Рейнджер 1 ИЛИ Арфист-скаут 1), а у этого билда 35 уровней
          # рейнджера. `skill_focus` остался — его «able to use the skill»
          # схемой не выражается, и честный отказ читать прозу сохранён.
          prerequisites_unmet: [
            {21, :epic_skill_focus, [requires_any_skill_ranks: 20]},
            {24, :epic_skill_focus, [requires_any_skill_ranks: 20]},
            {33, :epic_skill_focus, [requires_any_skill_ranks: 20]}
          ],
          caveats: [
            # Требования Теневого танцора — см. «Мастер Вор» выше.
            # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
            # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
            #   dodge(ac_bonus), mobility(ac_bonus)
            # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
            # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
            # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
            # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
            # 🔴 Здесь стояли `{:feat_bonus, :skill_focus}` и
            # `{:feat_bonus, :epic_skill_focus}` — «прибавку от этого фита в статы
            # не считаем». Сняты задачей 3.92 по решению Dan: +3 и +10 идут
            # в значение ВЫБРАННОГО навыка и названы там термом с именем фита.
            # Оговорка, спорящая с напечатанным числом, хуже отсутствующей
            # (CLAUDE.md §6) — тот же ход, что у `improved_spell_resistance`
            # (3.45) и `epic_toughness` (1.9).
            # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
            # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
            #   favored_enemy(feat_bonus)
            # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
            # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
            # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
            # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
            # 🔴 Снято задачей 3.93 (25.08.2026): `improved_critical` — получатель эффекта не
            # наш. Разбор целиком в moduledoc; это НЕ «прибавку научились считать».
            # Задача 1.12b: две прибавки фокуса плюс `Bane of enemies` — +2
            # к попаданию, но только по избранному врагу, то есть узость поверх
            # узости (вид существа, да ещё и выбранный другим фитом).
            # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
            # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
            #   bane_of_enemies(attack_bonus)
            # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
            # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
            # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
            # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
            not_modelled: {:attack_bonus_weapon, :epic_weapon_focus},
            not_modelled: {:attack_bonus_weapon, :weapon_focus}
          ],
          attack_ability: :str,
          declared: 27,
          # 26 → 27 on 14.08.2026: ranger class level 35 (character level 40 for
          # this build) grants **two** bonus slots, not one, and the ladder line
          # that names two favoured enemies there now has somewhere to put both.
          # Every declared feat on this page is placed — `declared == slots ==
          # filled` for the first time.
          slots: 27,
          # 24 → 26: both weapon-proficiency feats now fill the ranger's bonus
          # slot at levels 1 and 5 instead of falling out unplaced (§1.8);
          # 26 → 27 with the second slot above.
          filled: 27
        }
      },
      # ranger d10 + CON 14 (+2) + 1 от Toughness = 13; skill points 4 + INT 14 (+2) = 6
      level_41: %{class: :ranger, hp_gain: 13, skill_point_gain: 6},
      # Бесплатного Toughness в ванили нет — вся разница в его 40 хитах.
      vanilla: %{hp: 468},
      vanilla_gaps: [
        # ⚠️ Задача 3.34: то же и на ванили — правило про дальнюю атаку общее,
        # а оружия страница не называет ни там, ни там.
        not_modelled: {:attack_ability_default, :ranged},
        not_modelled: {:ac_bonus, :shadow_evade}
        # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
        # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
        #   uncanny_dodge(save_bonus), hardiness_vs_enchantments(save_bonus)
        # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
        # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
        # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
        # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
        # Задача 1.12b: `Improved two-weapon fighting` рейнджер выдаёт и в
        # ванили — шард этой выдачи не касался.
        # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
        # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
        #   improved_two_weapon_fighting(attack_bonus)
        # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
        # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
        # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
        # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
      ],
      divergences: [
        %{
          field: :skill_points_earned,
          page: 314,
          model: 270,
          verdict: :page_stale,
          # The page's spending arithmetic is exact — 314 − 175 free = 139, our
          # price for its rank list to the point — so only the earned total is
          # off, and by a very specific amount. 314 is what this build earns with
          # 24 ranger / 4 shadowdancer / **12** rogue levels instead of one:
          # rogue pays 4 more a level than ranger, and 11 × 4 = 44 = 314 − 270.
          # The stated total looks like it survived an edit that cut the rogue
          # levels. Not provable from the cache — the page has one revision here —
          # so the verdict is on the page either way, but the arithmetic is exact.
          note: "314 = the same build with 12 rogue levels; 11 × (8 − 4) = 44"
        }
      ]
    },
    %{
      title: "Мастер Монах",
      revid: 17_944,
      page: %{
        race: :elf,
        alignment: :lawful_evil,
        abilities: %{str: 10, dex: 16, con: 14, int: 14, wis: 14, cha: 8},
        ability_increases: %{dex: 10},
        character_level: 40,
        class_levels: %{ranger: 1, monk: 35, assassin: 2, fighter: 2},
        skill_points: 254,
        # the page never subtracts, so it never notices the overspend below
        free_skill_points: nil,
        committed_ranks: %{
          hide: 8,
          move_silently: 8,
          spot: 43,
          discipline: 43,
          heal_skill: 43,
          tumble: 40,
          search: 37,
          use_magic_device: 33
        },
        attack_bonus: 52,
        saves: %{fort: 51, ref: 55, will: 49},
        spell_resistance: 63
      },
      model: %{
        # first 20: monk 19 → 19/11/11/11 (Siala raises monk's base attack from
        # medium to high — «Боевой прирост БАБ (+1 за уровень)» — so 19, not 14),
        # ranger 1 → 1/2/0/0. Sum 20/13/11/11, +10/+10 epic.
        base_attack: 30,
        base_saves: %{fort: 23, ref: 21, will: 21},
        # ⚠ Монах — единственный класс, у которого все три сейва основные, и
        # именно поэтому у этого билда сейвы ровные. Убийца и воин — нулевые
        # строки: их уровни взяты после 20-го.
        base_saves_by_class: %{
          monk: %{levels: 19, fort: 11, ref: 11, will: 11},
          ranger: %{levels: 1, fort: 2, ref: 0, will: 0},
          assassin: %{levels: 0, fort: 0, ref: 0, will: 0},
          fighter: %{levels: 0, fort: 0, ref: 0, will: 0}
        },
        attacks_per_round: 4,
        # CON 14 → +2. 35 × (d8 + 2) + 1 × (d10 + 2) + 2 × (d10 + 2) + 2 × (d6 + 2)
        # = 402, плюс 40 от `Toughness`. ⚠️ Монах его НЕ выдаёт — фит приносят
        # два уровня воина и один рейнджера, и платит он за все 40 уровней
        # персонажа, 35 монашеских включительно (задача 1.9). Плюс 20 от
        # «Духа Сиалы» — флэт, монах его тоже не выдаёт, а бонус есть и без
        # выдачи (задача, волна 12, 09.08.2026) — 402 + 40 + 20 = 462.
        hp: 462,
        gaps: [
          # ⚠️ Задача 3.34 (15.08.2026): страница оружия не называет, а с 15.08
          # от него зависит сама характеристика броска (дальний бой — ловкость,
          # замер N1). Модель ответила ближним боем и говорит об этом — разбор
          # в шапке файла.
          {:not_modelled, {:attack_ability_default, :ranged}},
          # Задача 3.11: у монаха ДВЕ собственные прибавки к AC, и они разные —
          # фит `Monk AC bonus` (вся мудрость) и колонка таблицы класса (+1 за
          # каждые 5 уровней). Обе пропадают в доспехах и со щитом.
          #
          # ⚠️ Здесь стояли ДВЕ оговорки `{:ac_bonus_scope, …}`, и они ушли
          # 09.08.2026: замер Dan назвал условие по числу («любой доспех, который
          # даёт AC»), а не по виду надетого, — и это ровно то, что игрок вводит,
          # так что условие стало ПРАВИЛОМ. У этого билда вещей нет вовсе, значит
          # обе прибавки на месте, а говорить «условие не проверяем» про
          # проверенное запрещено (CLAUDE.md §6).
          #
          # ⚠️ Здесь стояло `{:assumed, :ac_bonus_types_unstated}` с доводом
          # «замер подтвердил величину и условие, но не тип» — оговорка СНЯТА
          # задачей 3.90 (25.08.2026), а довод остался верным: тип по-прежнему
          # не назван ни одной из двух вики. Закрылся не он, а его следствие —
          # обе прибавки монаха складываются, и это ВИДНО РАЗНОСТЬЮ: на живом
          # билде владельца доспех отбирает двенадцать очков сразу, а общий тип
          # оставил бы в числе бо́льшую и стоил бы шесть.
          # Задача 1.12a: четыре узких источника — `Still mind` монаха (vs
          # mind-affecting), `Poison save` двух уровней ассасина (vs яд,
          # растёт по уровню класса — таблица известна, но узость решает
          # вердикт раньше величины), `Uncanny dodge` (владение от тех же
          # двух уровней ассасина) и раса Эльфа.
          # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
          # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
          #   still_mind(save_bonus), poison_save(save_bonus), uncanny_dodge(save_bonus), hardiness_vs_enchantments(save_bonus)
          # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
          # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
          # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
          # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
          # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
          # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
          # 🔴 Задача 3.45: единственный билд набора, у которого SR вообще есть,
          # — и единственный, который получает эту оговорку. Она не про
          # непосчитанный источник (таких у SR нет ни одного), а про ПРАВИЛО:
          # SR из разных источников не складывается, засчитывается наибольший,
          # а крафт Сиалы доходит до 28 СР. У монаха 35 наше число 63 и предмет
          # его не перебивает — но правило игрок из панели не выведет, и молчать
          # про него дороже, чем сказать. Разбор — в `_gear_decision` файла
          # разметки.
          #
          # ⚠️ Стоит ЗДЕСЬ, а не в `feats.caveats` ниже: `Diamond soul` приходит
          # выдачей класса, то есть SR есть у этого билда и без прочитанных
          # фитов. Появись оговорка в списке «что добавили фиты» — это значило бы,
          # что ворота перепутаны.
          {:not_modelled, :spell_resistance_from_gear}
          # 🔴 ТРИ СТРОКИ ПРО АТАКУ МОНАХА СНЯТЫ 17.08.2026. Стояли
          # `{:attack_bonus, :flurry_of_blows}`, `{:attack_bonus, :knockdown}` и
          # `{:attack_bonus, :stunning_fist}` (задача 1.12b) — три умения со
          # знаком МИНУС: −2 ко всем атакам раунда за лишнюю атаку, −4 на
          # попытку сбить с ног, −4 на оглушающий удар.
          #
          # ⚠️ Довод «даже ЗНАК числа зависит от класса» («monks suffer no
          # attack or damage penalties when using this feat») никуда не делся
          # и остаётся доводом НЕ ТАЩИТЬ эти числа в постоянное AB. Но каждое
          # из трёх — модификатор одного конкретного броска в одном конкретном
          # раунде, то есть состояние боя, а не свойство билда; про такое
          # калькулятор ответа не даёт вовсе, значит и дырки не имеет.
          #
          # ⚠️ Ровно это уже сказано строкой ниже про `weapon_bab_exceptions`:
          # «фраза страницы — про Flurry of blows, то есть про активируемый
          # режим. Решением Dan это бафф, а баффы мы не считаем и не называем».
          # Тот же `flurry_of_blows`, тот же довод — и до 17.08.2026 он снимал
          # оговорку в классовом слое и не снимал в слое разметки прибавок.
        ],
        # ⚠️ `weapon_bab_exceptions` стояло здесь и ушло 13.08.2026 (GAME_CHECKS.md,
        # L2 и L2b). Оговорка держалась на чтении «шард выводит часть оружия из-под
        # полного BAB монаха, а какого — проза»; два замера показали, что показанный
        # AB от оружия не зависит вовсе, а фраза страницы — про Flurry of blows,
        # то есть про активируемый режим. Решением Dan это бафф, а баффы мы
        # не считаем и не называем. Базовая атака ниже по-прежнему стоит на полном
        # BAB монаха — эта часть замером не задета.
        # ⚠️ Ни одной оговорки про группы классов у этого билда нет, и это
        # содержательная проверка, а не пропуск: рейнджер 1 / монах 35 / ассасин 2
        # / воин 2 — монах и воин из Адры, а рейнджер с ассасином нет, значит
        # чистота нарушена и билд НЕ адровец. Появись здесь гэп про Адру, это
        # означало бы, что правило чистоты перестало работать.
        # ⚠️ Из 15 фактов остался 1 (3.28 плюс замеры 13.08.2026): пул бонусных
        # фитов рейнджера. Яды, ловушки, скорость бега, лечение и порог применения
        # Instinctive throw — про то, чего калькулятор не считает, а исключения
        # BAB монаха оказались про Шквал ударов, то есть про бафф.
        # ⚠️ 24.08.2026 (задача 3.85): у Рейнджера не осталось ни одной оговорки —
        # `bonus_feat_pool` применён по замерам U1 и U2, и гэп был ЛОЖНЫМ
        # (пять сиальских владений лежали в бонусном слоте всё это время,
        # их кладут туда сами страницы фитов). Пустой список оставлен
        # НАРОЧНО вместо удаления ключа: он ловит возврат оговорки, а
        # отсутствующий ключ молчал бы про это так же, как про всё остальное.
        class_caveats: %{
          ranger: []
        },
        # INT 14 → +2. ranger/monk/assassin 4, fighter 2: 24 on level 1, then 6
        # on the monk and assassin levels and 4 on the two fighter ones
        skill_points_earned: 254,
        # every skill is a class skill of monk, ranger or assassin, so the plan
        # costs one point a rank: 8 + 8 + 43 + 43 + 43 + 40 + 37 + 33
        plan_cost: 255,
        feats: %{
          taken: %{
            1 => [:blooded, :siala_blade_proficiency],
            3 => [:skill_focus],
            6 => [:weapon_focus],
            9 => [:blind_fight],
            12 => [:improved_critical],
            15 => [:weapon_finesse],
            18 => [:alertness],
            21 => [:epic_skill_focus],
            22 => [:epic_weapon_focus],
            23 => [:armor_skin],
            24 => [:improved_spell_resistance],
            27 => [:improved_spell_resistance],
            29 => [:improved_spell_resistance],
            30 => [:improved_spell_resistance],
            33 => [:improved_spell_resistance],
            34 => [:improved_spell_resistance],
            36 => [:improved_spell_resistance],
            # two ranks of the same feat on one level, into two different slots —
            # the case a list-of-feats model gets wrong and a slot model does not
            39 => [:improved_spell_resistance, :improved_spell_resistance]
          },
          granted: [],
          # AGENT_QUEUE.md §1.8: this build's level 1 is Ranger (one lone level
          # among 35 of Monk), whose bonus slot the shard names by the level it
          # picks a favoured enemy — `siala_blade_proficiency` used to sit here
          # unplaced; `overrides.json` → `feats.bonus_slot_aliases` reads that
          # name as the ordinary Ranger bonus slot it is.
          unplaced: [],
          unreadable: [],
          prerequisites_unmet: [
            {21, :epic_skill_focus, [requires_any_skill_ranks: 20]}
          ],
          caveats: [
            assumed: :finessable_weapon,
            # ⚠️ Ни одной оговорки про AC от фитов, и это положительный
            # контроль к соседним билдам: Ассасин не требует ни `Dodge`, ни
            # `Mobility`, поэтому монах их не берёт. Весь AC этого билда —
            # классовый (см. `gaps` выше), а не фитовый.
            # 🔴 Здесь стояли `{:feat_bonus, :skill_focus}` и
            # `{:feat_bonus, :epic_skill_focus}` — «прибавку от этого фита в статы
            # не считаем». Сняты задачей 3.92 по решению Dan: +3 и +10 идут
            # в значение ВЫБРАННОГО навыка и названы там термом с именем фита.
            # Оговорка, спорящая с напечатанным числом, хуже отсутствующей
            # (CLAUDE.md §6) — тот же ход, что у `improved_spell_resistance`
            # (3.45) и `epic_toughness` (1.9).
            # 🔴 Снято задачей 3.93 (25.08.2026): `improved_critical` — получатель эффекта не
            # наш. Разбор целиком в moduledoc; это НЕ «прибавку научились считать».
            # 🔴 Здесь стояло `not_modelled: {:feat_bonus,
            # :improved_spell_resistance}` — «прибавку от этого фита в статы
            # не считаем». Снято задачей 3.45: девять взятий дают +18, и число
            # видно на экране рядом. Оговорка, спорящая с напечатанным числом,
            # хуже отсутствующей (CLAUDE.md §6), и её исчезновение отсюда —
            # видимое событие, ради которого фикстуры и перечисляют оговорки
            # поимённо.
            # Задача 1.12b: только две прибавки фокуса. `attack_ability: :dex`
            # ниже — Weapon Finesse, и он остался формулой, а не термом.
            not_modelled: {:attack_bonus_weapon, :epic_weapon_focus},
            not_modelled: {:attack_bonus_weapon, :weapon_focus}
          ],
          attack_ability: :dex,
          declared: 20,
          slots: 20,
          # 17 → 19 → 20: this build's Fighter levels 1 and 2 are taken at
          # character levels 22 and 23, and an epic character may pick from the
          # whole fighter bonus list there (`epic weapon focus`, `armor skin`);
          # the 20th is `siala_blade_proficiency` in the ranger's level-1 bonus
          # slot (§1.8).
          filled: 20
        }
      },
      # assassin d6 + CON 14 (+2) + 1 от Toughness = 9; skill points 4 + INT 14 (+2) = 6
      level_41: %{class: :assassin, hp_gain: 9, skill_point_gain: 6},
      # Siala gives the Monk full base attack («Боевой прирост БАБ (+1 за
      # уровень)»); vanilla's is medium. Of the first 20 levels 19 are monk, so
      # vanilla gets div(19 × 3, 4) = 14 there instead of 19, plus 1 from the
      # single ranger level = 15, and +10 from the epic levels = 25. Attacks are
      # frozen by the level-20 number, and 15 buys three where 20 buys four.
      # …и, как у всех остальных, 40 хитов бесплатного Toughness, которого
      # в ванили нет.
      vanilla: %{base_attack: 25, attacks_per_round: 3, hp: 402},
      # ⚠️ Условие AC монаха ПРИМЕНЯЕТСЯ на обоих ruleset'ах (разметка ванильная,
      # `vanilla/ac_bonuses.json`), поэтому оговорок про него нет ни здесь, ни
      # выше. А вот САМО число ruleset'ами расходится: сдвиг выдачи фита с 1-го
      # уровня на 4-й — отличие Сиалы, и на билде с одним уровнем монаха оно
      # решает всё. Здесь уровней монаха много, поэтому фит есть в обоих.
      # Задача 1.12a: все четыре — ванильные факты (Still mind, Poison save,
      # Uncanny dodge, раса Эльфа), шард их не переписывал.
      vanilla_gaps: [
        # ⚠️ Задача 3.34: то же и на ванили — правило про дальнюю атаку общее,
        # а оружия страница не называет ни там, ни там.
        not_modelled: {:attack_ability_default, :ranged},
        # ⚠️ И `assumed: :ac_bonus_types_unstated` стоял здесь — снят задачей
        # 3.90 у обоих ruleset'ов: разметка AC ванильная, значит и отметка
        # о подтверждённом складывании действует на обоих.
        # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
        # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
        #   still_mind(save_bonus), poison_save(save_bonus), uncanny_dodge(save_bonus), hardiness_vs_enchantments(save_bonus)
        # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
        # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
        # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
        # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
        # Задача 1.12b: и три отрицательных умения монаха тоже ванильные —
        # шард `Flurry of blows`, `Knockdown` и `Stunning fist` не переписывал.
        not_modelled: {:attack_bonus, :flurry_of_blows},
        not_modelled: {:attack_bonus, :knockdown},
        not_modelled: {:attack_bonus, :stunning_fist},
        # Задача 3.45: оговорка про предметы приходит и на ванили — разметка SR
        # ванильная, а не сиальская, и Diamond soul выдаётся на 12-м уровне
        # монаха в обоих ruleset'ах (шард выдачу не сдвигал). ⚠️ Довод у неё при
        # этом сиальский — крафтовые 28 СР, — и это не противоречие: правило
        # «SR не складывается» ванильное, числа шарда лишь показывают, что оно
        # кусает.
        not_modelled: :spell_resistance_from_gear
      ],
      divergences: [
        %{
          field: :plan_cost_fits,
          page: true,
          model: false,
          verdict: :page_arithmetic,
          # The one build whose earned total we match exactly, and its own skill
          # list needs 255 points against the 254 both sides agree it earns. One
          # point over, on a page that never does the subtraction. Nothing to fix
          # on our side: the two numbers it states are our two numbers.
          note: "255 needed against the 254 both sides agree on — off by one on the page"
        }
      ]
    },
    %{
      title: "Мастер оружия Сагровик",
      revid: 17_916,
      page: %{
        race: :half_elf,
        alignment: :chaotic_good,
        abilities: %{str: 16, dex: 13, con: 16, int: 13, wis: 8, cha: 8},
        ability_increases: %{str: 10},
        character_level: 40,
        class_levels: %{barbarian: 2, fighter: 10, weapon_master: 28},
        skill_points: 152,
        free_skill_points: 22,
        committed_ranks: %{intimidate: 4, tumble: 20, discipline: 43, heal_skill: 43},
        attack_bonus: 71,
        saves: %{fort: 58, ref: 47, will: 41},
        spell_resistance: nil
      },
      model: %{
        # first 20: barbarian 2 → 2/3/0/0, fighter 8 → 8/6/2/2, weapon master 10
        # → 10/3/7/3. Sum 20/12/9/5, +10/+10 epic. The eighteen weapon master
        # levels past 20 add nothing.
        base_attack: 30,
        base_saves: %{fort: 22, ref: 19, will: 15},
        base_saves_by_class: %{
          barbarian: %{levels: 2, fort: 3, ref: 0, will: 0},
          fighter: %{levels: 8, fort: 6, ref: 2, will: 2},
          weapon_master: %{levels: 10, fort: 3, ref: 7, will: 3}
        },
        attacks_per_round: 4,
        # CON 16 → +3. 2 × (d12 + 3) + 10 × (d10 + 3) + 28 × (d10 + 3) = 524,
        # плюс 40 от бесплатного `Toughness` (все три класса выдают его сами),
        # плюс 20 от `Epic toughness`, взятого на 35-м уровне: 524 + 40 + 20 =
        # 584, плюс 20 от «Духа Сиалы» — флэт, безусловный, не феат (задача,
        # волна 12, 09.08.2026) — 584 + 20 = 604. ✅ Задача из AGENT_QUEUE.md §7
        # «Стенд регрессии считает числа без фитов» (волна 10, 08.08.2026):
        # `to_build/3` раскладывает фиты по слотам только с `feats: true`,
        # тест ниже теперь его передаёт (только для HP — остальные поля фитов
        # не читают, см. комментарий у теста).
        hp: 604,
        gaps: [
          # ⚠️ Задача 3.34 (15.08.2026): страница оружия не называет, а с 15.08
          # от него зависит сама характеристика броска (дальний бой — ловкость,
          # замер N1). Модель ответила ближним боем и говорит об этом — разбор
          # в шапке файла.
          {:not_modelled, {:attack_ability_default, :ranged}},
          # 🔴 ЗАДАЧА 3.107 СНЯЛА ЭТУ СТРОКУ, И СНЯЛА ЕЁ ПРАВИЛОМ, А НЕ
          # ВЫЧЁРКИВАНИЕМ. Здесь стояло `{:not_modelled, {:class_qualifier,
          # :weapon_master, "unarmed strike is excluded from the
          # prerequisites"}}` с пояснением, что второе исключение страницы
          # названо ИМЕНЕМ ОДНОГО ПРЕДМЕТА, а не свойством, и потому
          # не проверяется. Проверяется с 26.08.2026: имя и записано именем
          # (`feat_choice_excludes`, перечисление — потому что перечисляет
          # источник), а замер Dan (кейс AC1) показал, что оговорка прикрывала
          # ложную ЛЕГАЛЬНОСТЬ — `Weapon Focus (Unarmed strike)` открывал класс,
          # которого в игре нет в списке.
          #
          # ⚠️ Легальность ЭТОГО билда не изменилась: его фокус оружия —
          # не рукопашный удар. Ушла ровно оговорка.
          # 🔴 ДВЕ СТРОКИ ПРО ЯРОСТЬ СНЯТЫ 17.08.2026, и это тот самый кейс,
          # ради которого задача заводилась. Стояли `{:ac_bonus,
          # :barbarian_rage}` (штраф −2 к AC на время ярости, задача 3.11) и
          # `{:ability_bonus, :barbarian_rage}` (+4 к силе и телосложению, с
          # 15-го уровня +6, задача 3.1).
          #
          # Ярость Dan закрыл как бафф ещё 10.08.2026 — «то, что включается и
          # кончается, не наше», — и в классовом слое она в тот же день
          # замолчала. Здесь она говорила ещё неделю: разметка `affects` у пяти
          # файлов прибавок появилась 17.08.2026, а читал её ровно один файл
          # из пяти. Игрок всё это время читал оговорки про механику, которую
          # владелец явным решением объявил не нашей.
          #
          # ⚠️ Оба довода из снятых комментариев остаются верными и оба
          # относятся к ЧИСЛУ, а не к оговорке: −2 к AC не приезжает («варвар,
          # который не в ярости, получил бы −2 из ниоткуда»), и +4 к силе тоже
          # («недосчёт в ПОЛЬЗУ игрока»). Ни одно число этой правкой не
          # сдвинулось — сдвинулся список того, о чём мы молчим сознательно.
          # Задача 3.12: бонус расы Светлого эльфа к атаке, и он входит в кап
          # атаки +20 (страница говорит это прямо).
          # ⚠️ **Самый показательный кейс во всём файле, и он же закрыл открытый
          # вопрос волны 10.** Билд называется «Сагровик», и он им и является по
          # составу: варвар + воин + мастер оружия — три класса из четырёх,
          # которые страница «Воины Сагры» перечисляет, других уровней нет.
          # В игре ему полагается +9, а мы показывали +6, потому что «сагровик ли
          # персонаж» считалось неизвестным. 08.08.2026 Dan ответил: «сагровик
          # получит больше бонусов, чем несагровик», — и теперь оговорка называет
          # ПОСЧИТАННЫЙ вариант (+9), а не признаётся в недосчёте. Число этого
          # билда сдвинулось: AB 39 → 42 при плоских характеристиках.
          # 🔴 **Вариант стал `nil` 15.08.2026 — замер Dan** (`GAME_CHECKS.md`
          # Q1/Q4): расовый бонус включается ОРУЖИЕМ В РУКАХ, а фикстуры этого
          # файла собираются со страницы билда и оружия не объявляют вовсе.
          # Значит у них бонус честно не посчитан, и оговорка называет причину,
          # а не вариант.
          #
          # ⚠️ Контраст «base против sagra_warrior», ради которого две фикстуры
          # и держали рядом, этой правкой НЕ потерян — он переехал в
          # `racial_bonus_test.exs`, где билд можно вооружить. Здесь остался
          # контроль поважнее: число, которого игра не даёт, не приезжает
          # и к нам.
          #
          # ⚠️ И это расхождение со страницей РАСТЁТ, а не сокращается: живой
          # персонаж с вики оружие держит, и его AB на странице расовый бонус
          # включает. Наш ответ ниже на эту величину — но он верен ДЛЯ ТОГО
          # БИЛДА, КОТОРЫЙ ОПИСАН, а дорисовывать фикстуре оружие значило бы
          # выдумать данные страницы.
          {:assumed, {:racial_bonus_variant, :half_elf, nil}}
          # И то, что группа даёт помимо расового бонуса: зелья Сагры и Азарака,
          # точило, множитель от оружия. Всё это расходники и армори, в числах
          # его нет — но теперь это сказано вслух, одной оговоркой на группу.
          # ⚠️ ЗДЕСЬ СТОЯЛА `{:not_modelled, {:class_group_benefits,
          # :sagra_warriors}}` — снята задачей 3.100 (25.08.2026). Непосчитанного
          # у группы столько же, сколько было: зелья Сагры, зелья Азарака, точило.
          # Изменилось не число, а признание: у всех трёх строк теперь назван
          # ПОЛУЧАТЕЛЬ (`custom_items`, `buff` — `systems.json`, affects_by_benefit),
          # и ни один из них калькулятор не печатает. Гэп — дырка в НАШЕМ ответе
          # (CLAUDE.md §9), а вопроса про расходники мы не задаём вовсе.
          # ⚠️ «Усиленный бонус от оружия» этой правки не касается: он посчитан
          # с задачи 3.35 и вычитается раньше, чем читается получатель.
          # 🔴 ТРЕТЬЯ СТРОКА ПРО ЯРОСТЬ СНЯТА 18.08.2026 (шестой файл семейства
          # прибавок, `feat_save_bonuses.json`). Стояла `{:not_modelled,
          # {:save_bonus, :barbarian_rage}}` — те же +2 к Will (условно), тем
          # же доводом, что и у снятых 17.08.2026 AC/характеристик. `Uncanny
          # dodge` — владение от двух уровней варвара, остаётся: узко против
          # ловушек, а не временно. Раса Светлого эльфа несёт `Hardiness vs.
          # enchantments`, тоже остаётся тем же доводом.
          # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
          # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
          #   uncanny_dodge(save_bonus), hardiness_vs_enchantments(save_bonus)
          # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
          # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
          # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
          # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
          # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
          # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
          # ⚠️ Здесь стоял `{:not_modelled, {:attack_bonus_weapon,
          # :weapon_master}}` — самое крупное непосчитанное число задачи 1.12b
          # (+7 за 28 уровней класса). Он не исчез, а ПЕРЕЕХАЛ в `feats.caveats`
          # ниже (14.08.2026): этот список считается по билду БЕЗ фитов, а
          # колонка с того дня требует владения `Weapon of choice`.
          # ⚠️ Ярость варвара к атаке при этом НЕ прибавляет ничего, и это
          # положительный контроль на то, что одно умение не размножилось по
          # шести файлам разметки: она трогает четыре системы разом (AC,
          # характеристики, сейв, магнитуда классового слоя) и ни разу —
          # пятую, атаку. 18.08.2026 (шестой файл, `feat_save_bonuses.json`)
          # сняло третью строку из четырёх, и на ЭТОМ билде (двухуровневый
          # дип варвара) у Ярости не осталось ни одной живой оговорки вовсе:
          # класс-слоевая (`rage`, `class_caveats` ниже) ушла ещё 10.08.2026,
          # AC и характеристики — 17.08.2026. Про атаку не появилось ничего
          # ни на одном из четырёх шагов.
        ],
        # 28 Weapon Master levels, so until 17.08.2026 the same outstanding
        # attack rule as «Гном Защитник» — and this is the build whose page
        # claims «Бонус атаки: +71».
        # ⚠️ `rage` варвара стояла здесь и ушла 10.08.2026 решением Dan: Ярость
        # включается и кончается, то есть бафф, — хотя названные ею STR/CON/
        # Will/AC мы печатаем.
        # ⚠️ 17.08.2026 (задача про Мастера оружия): прибавка к атаке Мастера
        # оружия УШЛА тоже — замер Dan показал, что это ванильная колонка
        # `feat_attack_bonuses.json`, уже посчитанная (прогоном: воин 10 /
        # ВМ 28 с длинным мечом даёт AB 39 против 32 без меча). Ровно она
        # и была источником «Бонус атаки: +71» на странице — теперь этот вклад
        # учтён ядром, а не висит оговоркой, поэтому `class_caveats` пуст.
        class_caveats: %{},
        # INT 13 → +1. barbarian 4, fighter and weapon master 2: 20 on level 1,
        # 5 on level 2, then 3 on each of 3…40
        skill_points_earned: 139,
        # Intimidate 4 pinned to level 1, a Barbarian level that has it → 4 × 1;
        # Tumble is a class skill of none of the three → 20 × 2; Discipline and
        # Heal are class skills of all three → 43 + 43. Total 130, which is
        # exactly the page's own 152 − 22.
        plan_cost: 130,
        feats: %{
          taken: %{
            1 => [:luck_of_heroes],
            3 => [:dodge, :mobility],
            4 => [:expertise],
            6 => [:spring_attack, :whirlwind_attack],
            8 => [:siala_blade_proficiency],
            9 => [:weapon_focus],
            10 => [:weapon_specialization],
            11 => [:weapon_of_choice],
            12 => [:blind_fight],
            15 => [:improved_critical],
            18 => [:great_fortitude],
            21 => [:epic_fortitude],
            23 => [:epic_weapon_focus],
            24 => [:great_strength],
            26 => [:armor_skin],
            27 => [:great_strength],
            29 => [:epic_prowess],
            30 => [:great_strength],
            32 => [:siala_hammer_proficiency],
            33 => [:great_strength],
            35 => [:epic_toughness],
            36 => [:epic_energy_resistance],
            39 => [:epic_energy_resistance, :epic_weapon_specialization]
          },
          # ⚠️ Было `[{11, :weapon_of_choice}]` — см. тот же довод у «Гнома
          # Защитника»: с 14.08.2026 класс фит не выдаёт, строка страницы
          # занимает слот.
          granted: [],
          # Nothing left over: this is the build that needed *both* slot fixes at
          # once. Level 39 asks for two feats and the level grants two slots —
          # the general epic one takes `epic energy resistance` and the Fighter
          # bonus takes `epic weapon specialization`, which is only possible now
          # that neither slot is refusing on the wrong grounds.
          unplaced: [],
          unreadable: [],
          prerequisites_unmet: [],
          caveats: [
            # ⚠️ ЗДЕСЬ СТОЯЛА `{:assumed, {:feat_repeatable,
            # :epic_weapon_specialization}}` — снята 25.08.2026 замером Dan
            # (`GAME_CHECKS.md`, кейс `AA2`): «её можно брать для разных оружий,
            # аналогично как просто weapon specialization». Догадка 02.08.2026
            # оказалась верной, статус поднялся `unclear` → `verified`,
            # и оговорку снял механизм, который производит её ровно
            # по `status == "unclear"`. Ни одно число билда не сдвинулось.
            # Требования Мастера оружия: `Dodge`, `Mobility` и `Expertise`
            # стоят в его блоке требований, значит появляются в каждом билде
            # с ВМ. Все три дают условный AC и ни один не идёт в число.
            #
            # 🔴 А ВОТ ГОВОРИМ МЫ С 17.08.2026 ТОЛЬКО ПРО ДВА, и разница внутри
            # одной тройки — лучший имеющийся контроль качества разметки:
            # `Dodge` и `Mobility` пассивны (условие — текущая цель, атака по
            # возможности), у них получатель `ac`; `Expertise` включается
            # игроком и выключается, у него `buff`. Разделение прошло не по
            # файлу и не по фиту, а по механике.
            # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
            # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
            #   dodge(ac_bonus), mobility(ac_bonus)
            # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
            # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
            # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
            # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
            # 🔴 Снято задачей 3.93 (25.08.2026): `epic_energy_resistance` — получатель
            # эффекта не наш. Разбор целиком в moduledoc; это НЕ «прибавку научились
            # считать».
            # ⚠️ `epic_toughness` больше не в списке — с задачи 1.9 его двадцать
            # хитов за взятие ядро считает и называет в разборе HP, а оговорка
            # «прибавку не считаем» спорила бы с числом на экране.
            # 🔴 Снято задачей 3.93 (25.08.2026): `epic_weapon_specialization` — получатель
            # эффекта не наш. Разбор целиком в moduledoc; это НЕ «прибавку научились
            # считать».
            # ⚠️ `great_strength` снят с задачи 3.1 — прибавка посчитана.
            # 🔴 Снято задачей 3.93 (25.08.2026): `improved_critical` — получатель эффекта не
            # наш. Разбор целиком в moduledoc; это НЕ «прибавку научились считать».
            # ⚠️ Здесь стояла `not_modelled: {:feat_bonus, :weapon_of_choice}` —
            # появилась 14.08.2026 вместе с M2/M2b и снята в тот же день
            # решением Dan; довод целиком — у «Гнома Защитника» выше.
            # 🔴 Снято задачей 3.93 (25.08.2026): `weapon_specialization` — получатель
            # эффекта не наш. Разбор целиком в moduledoc; это НЕ «прибавку научились
            # считать».
            # ⚠️ Задача 3.5 сняла отсюда `{:feat_qualifier, :weapon_specialization,
            # "(chosen weapon)"}` — единственную оговорку, которая ПЕРЕЕХАЛА
            # в проверяемое правило, а не просто исчезла: с появлением словаря
            # оружия `same_choice_as: [weapon_focus]` у этого фита начал
            # срабатывать, и печатать «схема этого выразить не может» рядом
            # с работающей проверкой было бы ложной неопределённостью наоборот
            # (§6). ⚠️ ЗДЕСЬ СТОЯЛО: «У `epic_weapon_focus`
            # и `epic_weapon_specialization` выше оговорка ОСТАЛАСЬ, и это
            # не забывчивость: на ванильном ruleset'е они не объявлены
            # повторяемыми, а `qualifiers` один на оба ruleset'а». Диагноз был
            # верен, вывод — нет: файл один, а решать должен был RULESET.
            # Задача 3.99 перенесла решение в ядро (`Prereqs.qualifiers/1`
            # спрашивает `FeatChoices.same_choice_enforced?/1`), и на Сиале обе
            # оговорки ушли, а в ванили остались — это видно в `vanilla_gaps`
            # соседних билдов.
            # Задача 1.12b. ⚠️ `Weapon specialization` и `Epic weapon
            # specialization` в этом списке НЕ появляются, хотя оба «в выбранном
            # оружии»: они дают УРОН, а не атаку (`not_an_attack_bonus`
            # в разметке). Ровно та ловушка, из-за которой разведка шла по
            # содержанию, а не по имени фита.
            # ⚠️ И с 17.08.2026 не появляется `{:attack_bonus, :expertise}` —
            # третья причина молчать в одном списке: не «дало другое число»
            # и не «посчитано», а «получатель не наш». Три разные причины, все
            # три названы, иначе список читается как «здесь всё сходится».
            not_modelled: {:attack_bonus_weapon, :epic_weapon_focus},
            not_modelled: {:attack_bonus_weapon, :weapon_focus},
            # ⚠️ ПЕРЕЕХАЛА из `gaps` билда (14.08.2026): колонка «AB bonus»
            # Мастера оружия требует владения `Weapon of choice`, значит её
            # непосчитанность — следствие взятого фита, а не свойство лестницы.
            not_modelled: {:attack_bonus_weapon, :weapon_master}
          ],
          attack_ability: :str,
          declared: 26,
          # ⚠️ 26 → 27 и 25 → 26 правкой 14.08.2026 (замеры M2/M2b), причина
          # та же, что у «Гнома Защитника»: выдача Мастера оружия оказалась
          # слотом. Заодно ушла и арифметика «26 = 1 granted + 25 filled» —
          # выданного у этого билда больше нет вовсе, все 26 объявленных фитов
          # лежат в слотах.
          slots: 27,
          # 22 → 25: the page spends every slot it is given and nothing is
          # left over.
          filled: 26
        }
      },
      # weapon master d10 + CON 16 (+3) + 1 от Toughness = 14; skill points
      # 2 + INT 13 (+1) = 3
      # Epic toughness landed on level 35 — flat, already earned by level 40 —
      # so it cancels out of the level 40→41 delta and `hp_gain` is unaffected.
      level_41: %{class: :weapon_master, hp_gain: 14, skill_point_gain: 3},
      # Бесплатного Toughness в ванили нет, а `Epic toughness` — ванильный
      # фит без правок Сиалы, так что его 20 хитов остаются: 524 + 20 = 544.
      vanilla: %{hp: 544},
      vanilla_gaps: [
        # ⚠️ Задача 3.34: то же и на ванили — правило про дальнюю атаку общее,
        # а оружия страница не называет ни там, ни там.
        not_modelled: {:attack_ability_default, :ranged},
        # 🔴 ЗАДАЧА 3.107 СНЯЛА ЭТУ СТРОКУ ПРАВИЛОМ, А НЕ ВЫЧЁРКИВАНИЕМ —
        # разбор в сиальской половине этой же фикстуры. Правило ванильное
        # (`fandom:Unarmed strike` называет оба класса поимённо), поэтому
        # оговорка ушла на ОБОИХ ruleset'ах, а не только у Сиалы.
        not_modelled: {:ac_bonus, :barbarian_rage},
        not_modelled: {:ability_bonus, :barbarian_rage},
        # Задача 1.12a: все три — ванильные факты (Ярость, Uncanny dodge,
        # раса Светлого эльфа), шард их не переписывал.
        not_modelled: {:save_bonus, :barbarian_rage}
        # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
        # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
        #   uncanny_dodge(save_bonus), hardiness_vs_enchantments(save_bonus)
        # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
        # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
        # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
        # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
        # ⚠️ Здесь стоял `{:not_modelled, {:attack_bonus_weapon,
        # :weapon_master}}` с доводом «колонка ванильная целиком, таблица Fandom
        # одна на оба ruleset'а». Таблица та же и сегодня — ушла не она, а сам
        # вопрос: `vanilla_gaps` считается по билду БЕЗ фитов, а колонка
        # с 14.08.2026 требует владения `Weapon of choice`. С фитами оговорка
        # на месте на обоих ruleset'ах (`feats.caveats` выше).
      ],
      divergences: [
        %{
          field: :skill_points_earned,
          page: 152,
          model: 139,
          verdict: :page_arithmetic,
          note: "same +13 as Гном Защитник; spending arithmetic matches exactly"
        }
      ]
    },
    %{
      title: "Паладин Адры",
      revid: 19_670,
      page: %{
        race: :elf,
        alignment: :lawful_good,
        abilities: %{str: 14, dex: 10, con: 12, int: 14, wis: 14, cha: 14},
        ability_increases: %{str: 10},
        character_level: 40,
        class_levels: %{paladin: 38, monk: 1, champion_of_torm: 1},
        # the page's skills section is an empty heading
        skill_points: nil,
        free_skill_points: nil,
        committed_ranks: %{},
        attack_bonus: nil,
        saves: nil,
        spell_resistance: nil
      },
      model: %{
        # first 20 levels are twenty paladin levels: 20/12/6/6, +10/+10 epic
        base_attack: 30,
        base_saves: %{fort: 22, ref: 16, will: 16},
        # ⚠ Монах со всеми тремя основными сейвами стоит здесь с НУЛЯМИ: его
        # единственный уровень взят в эпике. Ровно тот случай, на котором
        # «+2 за первый уровень класса» не срабатывает, и разбор это показывает.
        base_saves_by_class: %{
          paladin: %{levels: 20, fort: 12, ref: 6, will: 6},
          monk: %{levels: 0, fort: 0, ref: 0, will: 0},
          champion_of_torm: %{levels: 0, fort: 0, ref: 0, will: 0}
        },
        attacks_per_round: 4,
        # CON 12 → +1. 38 × (d10 + 1) + 1 × (d8 + 1) + 1 × (d10 + 1) = 438, плюс
        # 40 от бесплатного `Toughness` паладина, плюс 40 от ДВУХ из трёх
        # взятий `Epic toughness` (32, 35 уровни) — 438 + 40 + 40 = 518, плюс
        # 20 от «Духа Сиалы» — флэт, безусловный, не феат (задача, волна 12,
        # 09.08.2026) — 518 + 20 = 538.
        # ⚠️ Не 558 (518 + 3 × 20 вместо 518 + 20), хотя страница называет три
        # взятия Epic toughness (32, 35, 39): на 39-м уровне заявлено сразу
        # два фита — `epic_skill_focus` и `epic_toughness` — а общий эпический
        # слот там ровно один. Слот достаётся `epic_skill_focus` (см.
        # `feats.unplaced` этого билда: `epic_toughness` на 39-м не размещён),
        # так что в `build.feats` попадают только два взятия — третье никогда
        # не становится picked и не может учитываться в HP, каким бы способом
        # мы фиты ни передавали. AGENT_QUEUE.md §7 называл эту прибавку «−60»,
        # это неточность самого долга: 60 — арифметика страницы (3 × 20), а не
        # то, что вправе посчитать наш слотовый механизм при честном разборе
        # той же страницы. Проверено прогоном 08.08.2026.
        hp: 538,
        # Champion of Torm's own requirement refines «Weapon focus» to a melee
        # weapon, and weapons are not modelled. The class is offered on the rest.
        #
        # ⚠️ Задача 3.11, и это самая наглядная пара во всём файле: про AC
        # монаха здесь НЕ сказано ничего, а в `vanilla_gaps` ниже — сказано.
        # У билда ровно ОДИН уровень монаха, а Сиала сдвинула выдачу
        # `Monk AC bonus` с 1-го уровня класса на 4-й. То есть в ванили этот
        # персонаж получает мудрость к AC (+2 при WIS 14), а на Сиале — нет.
        # Ровно поэтому в билдах шарда берут четыре уровня монаха, а не один.
        gaps: [
          # ⚠️ Задача 3.34 (15.08.2026): страница оружия не называет, а с 15.08
          # от него зависит сама характеристика броска (дальний бой — ловкость,
          # замер N1). Модель ответила ближним боем и говорит об этом — разбор
          # в шапке файла.
          {:not_modelled, {:attack_ability_default, :ranged}}
          # ⚠️ ЗДЕСЬ СТОЯЛА `{:not_modelled, {:class_qualifier, :champion_of_torm,
          # "in a melee weapon"}}` — снята задачей 3.99: требование стало
          # проверяемым (`feat_choice_properties`, свойство `ranged`).
          # Страница Чемпиона Торма раздела Notes не несёт вовсе, то есть
          # второго исключения (рукопашный удар) у неё нет — в отличие
          # от Мастера оружия, у которого остаток честный и остался.
          # ⚠️ 08.08.2026: **страница называется «Паладин Адры», и билд им
          # оказался по составу** — паладин 38 / монах 1 / чемпион Торма 1, все
          # три класса из списка Адры. Это независимое подтверждение группы,
          # ровно как «Сагровик» подтверждает Сагру, — и единственное, что у нас
          # вообще есть про Адру помимо четырёх строк на страницах классов.
          #
          # Оба гэпа — про то, чего про эту группу не знает никто:
          # правило чистоты нигде не сформулировано (мы применили правило Сагры),
          # и что членство даёт — тоже. ⚠️ Числа билда не двигаются вовсе: у
          # Тёмного эльфа расового бонуса нет, а собственного числа у группы Адры
          # не существует ни в одном файле. Флажок отвечает только на «состав
          # подходит».
          # ⚠️ ЗДЕСЬ СТОЯЛИ ОБЕ ОГОВОРКИ ПРО АДРУ — сняты задачей 3.100
          # (25.08.2026), решением владельца, а не находкой на вики:
          #   {:assumed, {:class_group_purity, :adra_warriors}}
          #   {:missing_data, {:class_group_benefits, :adra_warriors}}
          # Dan: «для нашего конструктора и итоговых значений принадлежность билда
          # к Адре или нет ничего не меняет. Эта принадлежность позволяет пить зелья
          # адры, которые мы не моделируем, считай баффы».
          # Первая перестала печататься по решению (`not_a_gap` у факта
          # purity_required), вторая — потому что «что даёт группа» больше
          # не неизвестно: названы зелья, и получатели у них не наши.
          # ⚠️ Само ДОПУЩЕНИЕ про чистоту никуда не делось: purity_required
          # по-прежнему null, флажок группы по-прежнему помечен допущением
          # в своём title. Снято признание, а не допущение.
          # Задача 1.12a: раса Эльфа несёт `Hardiness vs. enchantments` — узко
          # против mind-affecting заклинаний. ⚠️ `Divine wrath` и `Still mind`
          # НЕ появляются здесь: у этого билда только 1 уровень Чемпиона Торма
          # (Divine wrath выдаётся с 5-го) и 1 монаха — оба ниже порога
          # владения, так что билд честно НЕ несёт этих гэпов.
          # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
          # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
          #   hardiness_vs_enchantments(save_bonus)
          # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
          # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
          # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
          # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
          # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
          # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
          # ⚠️ ТРИ СТРОКИ ПРО АТАКУ СНЯТЫ 17.08.2026 (`flurry_of_blows`,
          # `stunning_fist` — единственный уровень монаха, `smite_evil` —
          # второй уровень паладина). Все три помечены `buff`: режим, разовая
          # спецатака и умение «раз в день».
          #
          # ⚠️ Наблюдение, ради которого они здесь стояли, правку ПЕРЕЖИЛО и
          # осталось под тестом строкой выше: «один уровень монаха оказался
          # НИЖЕ порога у сейвов и ВЫШЕ у атаки, и оба ответа читаются из
          # `granted_feats`». Порог владения — гейт `held?/5`, его эта задача
          # не трогала вовсе; изменился второй гейт, который спрашивает про
          # получателя. Что первый работает, видно по `Divine wrath`: он
          # выдаётся с 5-го уровня Чемпиона Торма, здесь его уровень один,
          # и в списке ниже (у «Паладина метателя», где ЧТ десять) он
          # был — а теперь не появляется уже по второй причине.
        ],
        # ⚠️ Из 17 фактов остался 1 (3.28 плюс замеры 13.08.2026). Все девять
        # фактов паладина — про заклинания-баффы (`Holy sword`, `Prayer`,
        # `Divine favor`, `Bless weapon`, `Aura of glory`, `Отражение`), лечение
        # руками и бой верхом; у Чемпиона Торма осталась не длительность Divine
        # wrath, а пул бонусных фитов; исключения BAB монаха ушли замером L2b —
        # фраза оказалась про Шквал ударов, то есть про бафф.
        # ⚠️ 24.08.2026 (задача 3.85): у Чемпиона Торма не осталось ни одной оговорки —
        # `bonus_feat_pool` применён по замерам U1 и U2, и гэп был ЛОЖНЫМ
        # (пять сиальских владений лежали в бонусном слоте всё это время,
        # их кладут туда сами страницы фитов). Пустой список оставлен
        # НАРОЧНО вместо удаления ключа: он ловит возврат оговорки, а
        # отсутствующий ключ молчал бы про это так же, как про всё остальное.
        class_caveats: %{
          champion_of_torm: []
        },
        # INT 14 → +2. paladin and champion of torm 2, monk 4: 16 on level 1,
        # then 4 a level with 6 on the single monk level
        skill_points_earned: 174,
        plan_cost: 0,
        feats: %{
          taken: %{
            1 => [:blooded],
            3 => [:siala_blade_proficiency],
            6 => [:weapon_focus],
            9 => [:power_attack],
            12 => [:divine_shield],
            15 => [:divine_might],
            18 => [:improved_critical],
            21 => [:epic_skill_focus],
            23 => [:epic_weapon_focus],
            24 => [:blind_fight],
            26 => [:armor_skin],
            27 => [:great_strength],
            29 => [:epic_prowess],
            30 => [:great_strength],
            32 => [:epic_toughness],
            # «Al?» — the author's own note to self, not a feat name
            33 => [nil],
            35 => [:epic_toughness],
            36 => [:skill_focus],
            39 => [:epic_skill_focus, :epic_toughness]
          },
          granted: [],
          unplaced: [{39, :epic_toughness}],
          unreadable: [{33, "al?"}],
          prerequisites_unmet: [
            {21, :epic_skill_focus, [requires_any_skill_ranks: 20]},
            {39, :epic_skill_focus, [requires_any_skill_ranks: 20]}
          ],
          caveats: [
            # ⚠️ `{:ac_bonus, :divine_shield}` снят 17.08.2026, и снял его тот
            # же текст, которым он объяснялся: «тратит попытку изгнания нежити
            # и держится столько раундов, каков модификатор харизмы» — это
            # определение баффа, а не условной прибавки. Разметка записи
            # называет получателем `buff`.
            # ⚠️ А `Armor skin` этого билда оговорки не приносил и не приносит,
            # и это по-прежнему положительный контроль другого рода: его +2
            # природного AC ПОСЧИТАНЫ. Две разные причины молчать, и обе
            # названы — иначе список читался бы как «здесь всё сходится».
            # 🔴 Здесь стояли `{:feat_bonus, :skill_focus}` и
            # `{:feat_bonus, :epic_skill_focus}` — «прибавку от этого фита в статы
            # не считаем». Сняты задачей 3.92 по решению Dan: +3 и +10 идут
            # в значение ВЫБРАННОГО навыка и названы там термом с именем фита.
            # Оговорка, спорящая с напечатанным числом, хуже отсутствующей
            # (CLAUDE.md §6) — тот же ход, что у `improved_spell_resistance`
            # (3.45) и `epic_toughness` (1.9).
            # ⚠️ `epic_toughness` снят с задачи 1.9: его эффект посчитан, и
            # оговорка «прибавку не считаем» стала бы неправдой.
            # ⚠️ `great_strength` снят с задачи 3.1 — прибавка посчитана.
            # 🔴 Снято задачей 3.93 (25.08.2026): `improved_critical` — получатель эффекта не
            # наш. Разбор целиком в moduledoc; это НЕ «прибавку научились считать».
            # Задача 1.12b. ⚠️ `Epic prowess` (29-й уровень) в списке НЕ
            # появляется — его +1 посчитан.
            # ⚠️ И `Power attack` больше не появляется тоже — с 17.08.2026 и по
            # ДРУГОЙ причине. Здесь стояло «его −5 к атаке никем не посчитаны
            # и посчитаны быть не могут: это боевой режим», и обе половины
            # верны; изменилось следствие: раз это боевой режим, то он
            # включается и кончается, а значит это не наш ответ вовсе.
            not_modelled: {:attack_bonus_weapon, :epic_weapon_focus},
            not_modelled: {:attack_bonus_weapon, :weapon_focus}
          ],
          attack_ability: :str,
          declared: 20,
          slots: 20,
          filled: 18
        }
      },
      # paladin d10 + CON 12 (+1) + 1 от Toughness = 12; skill points 2 + INT 14 (+2) = 4.
      # `Epic toughness` не задевает дельту — оба реально размещённых взятия
      # (32, 35) уже отыграны к 40-му уровню, и в сумме 40→41 сокращаются.
      level_41: %{class: :paladin, hp_gain: 12, skill_point_gain: 4},
      # Бесплатного Toughness в ванили нет, а два реально размещённых взятия
      # `Epic toughness` (32, 35 — см. комментарий у `hp` выше про 39-й
      # уровень) остаются и под ванилью: 438 + 40 = 478.
      vanilla: %{hp: 478},
      # 🔴 ЗДЕСЬ ФИКСТУРА ПОТЕРЯЛА СВОЙ СМЫСЛ, и это надо было сказать вслух,
      # а не молча вычеркнуть строку. Стояло: «Оговорка, которой НЕТ
      # в сиальском списке выше, и в ней весь смысл кейса: один уровень монаха
      # даёт мудрость к AC в ванили и не даёт на Сиале (сдвиг выдачи с 1-го
      # уровня класса на 4-й)… видно оно теперь по ОДНОЙ строке,
      # `{:assumed, :ac_bonus_types_unstated}`». Задача 3.90 сняла эту оговорку
      # у обоих ruleset'ов, и списки гэпов сравнялись — сдвиг выдачи фита
      # отсюда больше НЕ ВИДЕН вовсе. ⚠️ Сам сдвиг никуда не делся и под
      # тестом остаётся: `armor_class_test.exs`, «мудрость доезжает до AC,
      # и это видно на 4-м уровне монаха» — там он проверяется ЧИСЛОМ, а не
      # наличием оговорки, то есть надёжнее, чем здесь.
      # Пара `{:ac_bonus_scope, …}` ушла 09.08.2026 у обоих ruleset'ов —
      # условие стало правилом (замер Dan), а разметка условия ванильная.
      vanilla_gaps: [
        # ⚠️ Задача 3.34: то же и на ванили — правило про дальнюю атаку общее,
        # а оружия страница не называет ни там, ни там.
        not_modelled: {:attack_ability_default, :ranged},
        # ⚠️ ЗДЕСЬ СТОЯЛА `{:not_modelled, {:class_qualifier, :champion_of_torm,
        # "in a melee weapon"}}` — снята задачей 3.99: требование стало
        # проверяемым (`feat_choice_properties`, свойство `ranged`).
        # Страница Чемпиона Торма раздела Notes не несёт вовсе, то есть
        # второго исключения (рукопашный удар) у неё нет — в отличие
        # от Мастера оружия, у которого остаток честный и остался.
        # Задача 1.12a: раса Эльфа — ванильный факт. `Divine wrath`/`Still
        # mind` по-прежнему отсутствуют — 1 уровень CoT/монаха ниже порога
        # владения (см. тот же довод в сиальском списке выше).
        # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
        # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
        #   hardiness_vs_enchantments(save_bonus)
        # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
        # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
        # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
        # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
        # Задача 1.12b: и три умения со штрафом/разовой прибавкой к атоке — тоже
        # ванильные. ⚠️ В отличие от `Monk AC bonus` двумя строками выше, сдвиг
        # выдачи Сиалой их НЕ касается: `Flurry of blows` и `Stunning fist`
        # выдаются на 1-м уровне монаха на обоих ruleset'ах, поэтому здесь
        # список совпадает с сиальским, а не расходится с ним.
        not_modelled: {:attack_bonus, :flurry_of_blows},
        not_modelled: {:attack_bonus, :smite_evil},
        not_modelled: {:attack_bonus, :stunning_fist}
      ],
      divergences: []
    },
    %{
      title: "Паладин метатель",
      revid: 17_981,
      page: %{
        race: :elf,
        alignment: :lawful_good,
        abilities: %{str: 14, dex: 10, con: 12, int: 14, wis: 14, cha: 14},
        ability_increases: %{wis: 10},
        character_level: 40,
        class_levels: %{paladin: 30, monk: 4, champion_of_torm: 6},
        skill_points: nil,
        free_skill_points: nil,
        committed_ranks: %{},
        attack_bonus: 70,
        saves: nil,
        spell_resistance: nil
      },
      model: %{
        # first 20: paladin 16 → 16/10/5/5, monk 2 → 2/3/3/3, champion of torm 2
        # → 2/3/3/0. Sum 20/16/11/8, +10/+10 epic.
        base_attack: 30,
        base_saves: %{fort: 26, ref: 21, will: 18},
        # ⚠ Пара к «Паладину Адры» и по этому числу тоже: там у монаха и Чемпиона
        # нули, здесь по два ЗАСЧИТАННЫХ уровня каждого — и +2 за первый уровень
        # класса срабатывает трижды, отчего Fort у этого билда на 4 выше при том
        # же капе. Именно это одно число «база» и скрывало.
        base_saves_by_class: %{
          paladin: %{levels: 16, fort: 10, ref: 5, will: 5},
          monk: %{levels: 2, fort: 3, ref: 3, will: 3},
          champion_of_torm: %{levels: 2, fort: 3, ref: 3, will: 0}
        },
        attacks_per_round: 4,
        # CON 12 → +1. 30 × (d10 + 1) + 4 × (d8 + 1) + 6 × (d10 + 1) = 432,
        # плюс 40 от бесплатного `Toughness` паладина (задача 1.9), плюс 20
        # от «Духа Сиалы» (задача, волна 12, 09.08.2026) — 432 + 40 + 20 = 492.
        hp: 492,
        # ⚠️ Задача 3.11, и это вторая половина пары с «Паладином Адры»: там
        # уровень монаха ОДИН и на Сиале мудрость к AC не даётся, здесь их
        # ЧЕТЫРЕ — ровно порог сдвига, — и даётся. WIS 14 плюс десять прибавок
        # = 24, то есть +7 к «голому» AC, которых до этой задачи не было.
        #
        # ⚠️ Оговорки про доспехи и щит рядом с числом больше нет: с 09.08.2026
        # условие проверяется (замер Dan — ломает не вид надетого, а то, даёт ли
        # оно AC), а вещей у этого билда нет вовсе. ⚠️ Здесь же стояло
        # «Осталось допущение про ТИП — его замер не закрыл»: допущение снято
        # задачей 3.90, и снял его не замер про тип, а замер про СКЛАДЫВАНИЕ —
        # тип в игре не печатается вовсе и наблюдаем быть не может.
        gaps: [
          # ⚠️ Задача 3.34 (15.08.2026): страница оружия не называет, а с 15.08
          # от него зависит сама характеристика броска (дальний бой — ловкость,
          # замер N1). Модель ответила ближним боем и говорит об этом — разбор
          # в шапке файла.
          {:not_modelled, {:attack_ability_default, :ranged}}
          # ⚠️ ЗДЕСЬ СТОЯЛА `{:not_modelled, {:class_qualifier, :champion_of_torm,
          # "in a melee weapon"}}` — снята задачей 3.99: требование стало
          # проверяемым (`feat_choice_properties`, свойство `ranged`).
          # Страница Чемпиона Торма раздела Notes не несёт вовсе, то есть
          # второго исключения (рукопашный удар) у неё нет — в отличие
          # от Мастера оружия, у которого остаток честный и остался.
          # 08.08.2026: паладин 30 / монах 4 / чемпион Торма 6 — тоже чистая
          # Адра, хотя страница про группу не говорит ни слова. ⚠️ Второй такой
          # билд из восьми, и это довод сам по себе: связка «паладин + монах +
          # чемпион Торма» — обычная форма билда на шарде, а не одна страница.
          # ⚠️ ЗДЕСЬ СТОЯЛИ ОБЕ ОГОВОРКИ ПРО АДРУ — сняты задачей 3.100
          # (25.08.2026), решением владельца, а не находкой на вики:
          #   {:assumed, {:class_group_purity, :adra_warriors}}
          #   {:missing_data, {:class_group_benefits, :adra_warriors}}
          # Dan: «для нашего конструктора и итоговых значений принадлежность билда
          # к Адре или нет ничего не меняет. Эта принадлежность позволяет пить зелья
          # адры, которые мы не моделируем, считай баффы».
          # Первая перестала печататься по решению (`not_a_gap` у факта
          # purity_required), вторая — потому что «что даёт группа» больше
          # не неизвестно: названы зелья, и получатели у них не наши.
          # ⚠️ Само ДОПУЩЕНИЕ про чистоту никуда не делось: purity_required
          # по-прежнему null, флажок группы по-прежнему помечен допущением
          # в своём title. Снято признание, а не допущение.
          # Задача 1.12a: два узких источника, оба остаются — `Still mind`
          # (4 уровня монаха), раса Эльфа `Hardiness vs. enchantments`.
          # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
          # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
          #   still_mind(save_bonus), hardiness_vs_enchantments(save_bonus)
          # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
          # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
          # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
          # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
          # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
          # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
          # 🔴 ЧЕТЫРЕ АТАКУЮЩИЕ ОГОВОРКИ СНЯТЫ 17.08.2026, и это был самый
          # длинный такой список из восьми билдов: `Divine wrath` Чемпиона
          # Торма (+3 к атаке раз в день, до +5 на 10-м уровне класса — у билда
          # шесть), `Smite evil` паладина (харизма, раз в день), `Flurry of
          # blows` и `Stunning fist` монаха (штрафы −2 и −4). Все четыре
          # помечены `buff`: раз в день, на несколько раундов, в режиме.
          #
          # 🔴 ЕДИНСТВЕННАЯ АСИММЕТРИЯ ПРАВКИ 17.08.2026 ЗАКРЫТА 18.08.2026 —
          # и это была строка `{:save_bonus, :divine_wrath}`, стоявшая здесь
          # до сегодня. `Divine wrath` несла ДВЕ оговорки — про атаку и про
          # сейв, — и 17.08.2026 ушла только одна: умение одно, механика одна,
          # вердикт обеих записей один, а разошлись они только тем, что
          # разметку 17.08.2026 получили ПЯТЬ файлов прибавок из шести, и
          # `feat_save_bonuses.json` не входил в их число. Строка
          # `{:save_bonus, :divine_wrath}` оставалась не потому, что про сейвы
          # мы знали больше, а потому, что правило «нет метки — значит гэп»
          # работало как задумано. 18.08.2026 (шестой файл) снял и её — обе
          # половины одного умения теперь оговариваются одинаково: никак.
          #
          # ⚠️ Довод «две оговорки про одно умение — не дубль» остаётся верным
          # и тогда, когда их стало ноль: страница называет трёх получателей
          # одним предложением («attack rolls, damage, and saving throws»), и
          # каждый отвергался своим файлом со своим доводом, пока не сошлись
          # оба посчитанных «не наших». Урон — третий получатель, и его
          # в модели нет вовсе, поэтому про него не было и не будет ни строки.
        ],
        # ⚠️ Из 17 фактов остался 1 (3.28 плюс замеры 13.08.2026). Все девять
        # фактов паладина — про заклинания-баффы (`Holy sword`, `Prayer`,
        # `Divine favor`, `Bless weapon`, `Aura of glory`, `Отражение`), лечение
        # руками и бой верхом; у Чемпиона Торма осталась не длительность Divine
        # wrath, а пул бонусных фитов; исключения BAB монаха ушли замером L2b —
        # фраза оказалась про Шквал ударов, то есть про бафф.
        # ⚠️ 24.08.2026 (задача 3.85): у Чемпиона Торма не осталось ни одной оговорки —
        # `bonus_feat_pool` применён по замерам U1 и U2, и гэп был ЛОЖНЫМ
        # (пять сиальских владений лежали в бонусном слоте всё это время,
        # их кладут туда сами страницы фитов). Пустой список оставлен
        # НАРОЧНО вместо удаления ключа: он ловит возврат оговорки, а
        # отсутствующий ключ молчал бы про это так же, как про всё остальное.
        class_caveats: %{
          champion_of_torm: []
        },
        # INT 14 → +2. paladin and champion of torm 2, monk 4: 16 on level 1
        skill_points_earned: 180,
        plan_cost: 0,
        feats: %{
          taken: %{
            1 => [:blooded],
            3 => [:siala_ranged_proficiency],
            6 => [:weapon_focus],
            9 => [:weapon_focus],
            12 => [:zen_archery],
            15 => [:power_attack],
            18 => [:divine_might],
            20 => [:improved_critical],
            21 => [:divine_shield],
            24 => [:great_wisdom],
            27 => [:great_wisdom],
            28 => [:epic_prowess],
            30 => [:great_wisdom],
            31 => [:armor_skin],
            33 => [:great_wisdom],
            34 => [:epic_weapon_focus],
            36 => [:epic_skill_focus, :great_wisdom],
            39 => [:blind_fight],
            40 => [:great_wisdom]
          },
          granted: [],
          unplaced: [],
          unreadable: [],
          prerequisites_unmet: [{36, :epic_skill_focus, [requires_any_skill_ranks: 20]}],
          caveats: [
            # ⚠️ `{:ac_bonus, :divine_shield}` снят 17.08.2026 — бафф, довод
            # целиком у «Паладина Адры» выше.
            # 🔴 Здесь стояли `{:feat_bonus, :skill_focus}` и
            # `{:feat_bonus, :epic_skill_focus}` — «прибавку от этого фита в статы
            # не считаем». Сняты задачей 3.92 по решению Dan: +3 и +10 идут
            # в значение ВЫБРАННОГО навыка и названы там термом с именем фита.
            # Оговорка, спорящая с напечатанным числом, хуже отсутствующей
            # (CLAUDE.md §6) — тот же ход, что у `improved_spell_resistance`
            # (3.45) и `epic_toughness` (1.9).
            # ⚠️ `great_wisdom` снят с задачи 3.1 — прибавка посчитана.
            # 🔴 Снято задачей 3.93 (25.08.2026): `improved_critical` — получатель эффекта не
            # наш. Разбор целиком в moduledoc; это НЕ «прибавку научились считать».
            # 🔴 Единственный билд вики с `Zen archery` (12-й уровень) — и,
            # судя по имени страницы, метатель именно поэтому. Прибавкой фит
            # не становится: он меняет ХАРАКТЕРИСТИКУ атаки, и живёт в
            # `Rules.Attack` (`counted_elsewhere` в разметке).
            #
            # ⚠️ Здесь стояло «оговорки НЕ приносит … сила выше мудрости при
            # плоских характеристиках теста». Неверны были обе половины.
            # У билда WIS 24 (14 + десять прибавок) против STR 14, то есть
            # мудрость выше на пять; `:str` получался не поэтому, а потому,
            # что правила для фита в хуке не было ВООБЩЕ, — и молчание было
            # не «хук честно не сработал», а фит не делал ничего.
            #
            # С 14.08.2026 правило есть, и билд говорит вслух ровно то, чего
            # ему не хватает: оружия в «Вещах». `attack_ability` при этом
            # по-прежнему `:str` — страница билда оружие не называет, а
            # догадаться по имени «метатель» модель не имеет права. В игре
            # с дротиком в руках атака шла бы от мудрости, то есть наше число
            # на 5 меньше; теперь это сказано, а не скрыто.
            # 🔴 И ЭТА СТРОКА — ГЛАВНЫЙ ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ко всей правке
            # 17.08.2026: `Zen archery` лежит в том же файле разметки атаки,
            # что снятый рядом `Power attack`, и остаётся на месте. Он не
            # прибавка вовсе — он меняет ХАРАКТЕРИСТИКУ броска, то есть
            # постоянное свойство билда, и молчать про непосчитанное здесь
            # было бы ровно тем, чего оговорки и не должны позволять.
            not_modelled: {:attack_ability_weapon, :zen_archery},
            # ⚠️ `{:attack_bonus, :power_attack}` снят 17.08.2026 — боевой
            # режим, довод целиком у «Паладина Адры» выше.
            not_modelled: {:attack_bonus_weapon, :epic_weapon_focus},
            not_modelled: {:attack_bonus_weapon, :weapon_focus}
          ],
          attack_ability: :str,
          declared: 20,
          slots: 20,
          # 18 → 20: both `great wisdom` go into the Champion of Torm bonus
          # slots at class levels 4 and 6, which an epic character may spend on
          # the epic half of that class's list.
          filled: 20
        }
      },
      # champion of torm d10 + CON 12 (+1) = 11; skill points 2 + INT 14 (+2) = 4
      level_41: %{class: :champion_of_torm, hp_gain: 12, skill_point_gain: 4},
      # Same one change as «Мастер Монах», smaller: of the first 20 levels two
      # are monk, worth 2 under Siala and div(2 × 3, 4) = 1 under vanilla, so
      # 16 (paladin) + 1 + 2 (champion of torm) = 19, +10 epic = 29. Attacks are
      # unchanged: 19 at level 20 still buys four. Плюс те же 40 хитов
      # бесплатного Toughness, которого в ванили нет.
      vanilla: %{base_attack: 29, hp: 432},
      # Одинаково на обоих ruleset'ах: четырёх уровней монаха хватает и до
      # сдвига, и после. Сдвиг виден на «Паладине Адры», где уровень один.
      vanilla_gaps: [
        # ⚠️ Задача 3.34: то же и на ванили — правило про дальнюю атаку общее,
        # а оружия страница не называет ни там, ни там.
        not_modelled: {:attack_ability_default, :ranged},
        # ⚠️ ЗДЕСЬ СТОЯЛА `{:not_modelled, {:class_qualifier, :champion_of_torm,
        # "in a melee weapon"}}` — снята задачей 3.99: требование стало
        # проверяемым (`feat_choice_properties`, свойство `ranged`).
        # Страница Чемпиона Торма раздела Notes не несёт вовсе, то есть
        # второго исключения (рукопашный удар) у неё нет — в отличие
        # от Мастера оружия, у которого остаток честный и остался.
        # ⚠️ И `assumed: :ac_bonus_types_unstated` стоял здесь — снят задачей
        # 3.90 у обоих ruleset'ов, разметка AC ванильная.
        # Задача 1.12a: все три — ванильные факты (Divine wrath, Still mind,
        # раса Эльфа), шард их не переписывал.
        not_modelled: {:save_bonus, :divine_wrath},
        # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
        # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
        #   still_mind(save_bonus), hardiness_vs_enchantments(save_bonus)
        # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
        # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
        # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
        # и точнее нас; видно оно в конструкторе (3.87) и на экране просмотра (3.94).
        # Задача 1.12b: и все четыре атакующие оговорки — ванильные тоже.
        not_modelled: {:attack_bonus, :divine_wrath},
        not_modelled: {:attack_bonus, :flurry_of_blows},
        not_modelled: {:attack_bonus, :smite_evil},
        not_modelled: {:attack_bonus, :stunning_fist}
      ],
      divergences: []
    }
  ]

  # ── why a feat the page takes finds no slot ───────────────────────────────
  #
  # Grouped by root cause rather than by build, because findings are not
  # problems: the three "two feats on level 1" entries are one author's habit
  # written out three times. `where` is compared **both ways** — an instance that
  # disappears fails as loudly as one that appears, because a silently-resolved
  # refusal would hide the next real one.
  #
  # ⚠ Verdicts say **whose mistake it is**, and this file's first run put twenty
  # feats here. Eighteen of them turned out to be ours, in four slot rules,
  # and are gone; the two below are what is left. What the five retired
  # groups were, since the lesson outlived them:
  #
  #   `feat_type_is_not_general` (4) — the general slot took `type == "general"`
  #     and nothing else, and Fandom's `type` is a taxonomy of feats rather than
  #     a slot flag: `Epic energy resistance` is `defensive`, `Epic weapon
  #     focus` is `combat`. Fixed in `Rules.FeatSlots`, which now says which
  #     types a general slot refuses instead of which one it takes.
  #
  #   `fighter_bonus_slot_refuses_an_epic_feat` (3) — a class bonus slot was
  #     marked epic only on the class's own epic bonus levels, so a Fighter
  #     level taken at character level 22 refused the epic list.
  #
  #   ⚠ `epic_feat_in_a_pre_epic_class_bonus_slot` (6) — **this one was filed
  #     against the pages, and the pages were right.** The reasoning was that
  #     only the Fighter's page grants its epic list early, so a rogue asking
  #     for `epic skill focus` at rogue 13 was overspending. It was drawn from
  #     two class pages. The whole sample says otherwise: all seven classes with
  #     pre-epic bonus feats state the rule, and `fandom:Bonus feat` states it
  #     once for everybody — «each class has a single list of bonus feat choices
  #     that is used regardless of whether or not the bonus can be called
  #     "epic"», with an epic character taking a fifth ranger level as its
  #     worked example. Six pages were accused of a mistake they had not made,
  #     and the same fix as the group above cleared all six. CLAUDE.md §3's
  #     "check the whole sample" applies to reading *prose*, not just numbers.
  #
  #   ⚠ `not_on_that_class_bonus_list` and three of `more_feats_than_the_level_
  #     grants` (4, one slot rule — AGENT_QUEUE.md §1.8) — **filed against the
  #     pages, and the pages were right again.** The Siala wiki names the
  #     Ranger's bonus slot by the level it picks a favoured enemy («на
  #     уровнях, когда выбирает любимого врага») rather than by "доп фитах" —
  #     a wording the loader did not yet read as the ordinary bonus slot it is,
  #     so `siala_blade_proficiency`/`siala_ranged_proficiency` looked like
  #     they had nowhere to go on a Ranger's own bonus levels. Dan observed
  #     otherwise on the test server (`overrides.json` →
  #     `feats.bonus_slot_aliases`, `source.kind: "user"`), and these three
  #     pages independently corroborate it: all three take a weapon-proficiency
  #     feat on the Ranger's level-1 bonus slot alongside a second level-1
  #     token that only fits if that slot is open, and «Мастер Ловушек» does
  #     the same again at level 5. Four pages were accused of overspending a
  #     level they had not overspent.
  #
  #   ⚠ `only_one_class_bonus_slot_per_level` (1, fixed 14.08.2026) — the one
  #     entry here that was **filed against us and was ours**, and it sat
  #     admitted for ten days because the fix was a data shape rather than a
  #     line: ranger class level 35 grants **two** bonus feats
  #     («at levels 23, 25, 26, 29, 30, 32, 35(two bonus feats), 38, and 40» —
  #     `fandom:Ranger`; the table cell says `2 bonus feats`, and `fandom:Bonus
  #     feat` has `12<br />13` in that cell, the only two-valued cell in either
  #     of its tables), while `epic_bonus_feat_levels` is a MapSet and cannot
  #     carry a count at all. «Мастер Ловушек» takes its 40th character level
  #     there and lost the second feat. Now `bonus_feat_counts` carries the
  #     number and the second slot gets its own id — see `Rules.FeatSlots`.
  @feat_refusals [
    %{
      cause: :more_feats_than_the_level_grants,
      verdict: :page_overspends,
      # Champion of Torm's first class level grants no bonus feat (they come at
      # champion levels 2, 4, 6, 8, 10), so «Паладин Адры» taking one at
      # character level 39 is a feat with nowhere to go and no bonus slot to
      # blame the loader for. ⚠️ Three siblings of this entry — the same
      # complaint about a *Ranger's* level 1 on three other pages — used to
      # stand here too; they were the loader's mistake, not the pages', and are
      # retired above (`not_on_that_class_bonus_list`, AGENT_QUEUE.md §1.8).
      note: "every slot on the level is filled and a feat is still left over",
      where: [{"Паладин Адры", 39, :epic_toughness}]
    },
    %{
      cause: :the_level_grants_no_slot_of_any_kind,
      verdict: :page_off_by_one,
      # Dwarven Defender's epic bonus feats land on class levels 14, 18, 22, 26,
      # 30 — character level 29 for this build, not 28. The page is one level
      # early, and its own level 29 line is empty.
      note: "no feat slot on this level at all; the class's bonus level is the next one",
      where: [{"Гном Защитник", 28, :armor_skin}]
    }
  ]

  # Tokens on a ladder line that resolve to no feat. One, and it is not a feat:
  # «:33. Паладин - Al?» is the author wondering what to take. Declared rather
  # than dropped, so a page that grows a real unreadable feat name is noticed.
  @unreadable_feat_tokens [
    {"Паладин Адры", 33, "al?", "the author's own question mark, not a feat name"}
  ]

  # Every shape of unmet prerequisite this run produces, and whose problem it is.
  # Keyed by the reason's own tag, and checked exhaustively both ways: a reason
  # shape that stops occurring is as much of an event as a new one.
  @prerequisite_causes %{
    # The fixture encodes **no per-level rank schedule** — no page states one,
    # and inventing one would put ranks on levels nobody named
    # (`WikiBuildPage.to_build/3`). So every rank requirement fails here
    # regardless of the truth. What can honestly be checked instead is that the
    # page's own final rank targets are at least large enough; see
    # `rank prerequisites are within reach of the page's own targets`.
    requires_skill_ranks: :not_encoded_in_these_fixtures,
    requires_any_skill_ranks: :not_encoded_in_these_fixtures
    # 🔴 КЛЮЧ `missing_data` УБРАН 25.08.2026 (задача 3.104), и это событие,
    # а не уборка — третье такое в этом списке после `requires_ability` и
    # `requires_spell_level`. Он стоял с пояснением «после волны 4 остался ровно
    # ОДИН фит: `skill_focus`, чьё "able to use the skill" — не порог вовсе
    # и формы в схеме не имеет». Форму нашли: это ЧЕТЫРЕ предложения `Notes`
    # той же страницы, и все четыре выражаются (`vanilla/feat_requirements.json`,
    # запись `skill_focus`).
    #
    # ⚠️ Ушедшие шесть строк были ложной НЕЛЕГАЛЬНОСТЬЮ, а не спором со
    # страницами: ядро отказывало `Skill focus` ВСЕМ и на любой навык, то есть
    # обвиняло четыре страницы билдов в том, чего они не делали. Строки сняты
    # тем, что правило прочитано, а не тем, что их объяснили.
    #
    # ⚠️ Фикстуры не пишут ВЫБОР фита (`Rules.validate_feat/3` зовётся без
    # `choice`), а все четыре ключа `skill_focus` спрашивают про выбранный
    # навык — значит здесь они молчат по построению. Это НЕ значит, что правило
    # не работает: контроли на паре «фит + навык» стоят в
    # `Data.FeatRequirementsTest` и `Rules.PrereqsTest`.
    # ⚠️ Ключ `requires_ability` УБРАН 04.08.2026 (задача 3.1), и это событие,
    # а не уборка. Он стоял с пояснением «страница не дотягивает: сила 12, а
    # Power Attack требует 13» — то есть мы трижды обвиняли «Бледного
    # Призывателя» в нелегальном билде. Обвинение было нашим: у него два
    # уровня РДД, а второй даёт +2 к силе, и к моменту взятия фитов её 14.
    # Оставить ключ «на всякий случай» нельзя — тест ниже требует, чтобы
    # причины совпадали с наблюдаемыми обе стороны, и мёртвая причина
    # с готовым оправданием ровно так и живёт годами.
    # ⚠️ Ключ `requires_spell_level` УБРАН 15.08.2026 (задача 3.31), и это тоже
    # событие, а не уборка. Он стоял здесь с разбором «страница билда права,
    # а пять отказов наши, но правило применить нечем»: у всех шести эпических
    # заклинаний Fandom в примечаниях пишет, что напечатанное требование
    # не настоящее — «the actual prerequisite is not the ability to cast level 9
    # spells, but being an epic cleric, druid, sorcerer, or wizard, or having at
    # least 15 pale master levels. Furthermore, this feat can only be chosen when
    # gaining a level in the qualifying class».
    #
    # Замер Dan 15.08.2026 (Бард 10 / ПМ 15 — игра предлагает `Epic spell: mummy
    # dust` и в бонусном слоте ПМ, и в общем эпическом) подтвердил прозу, и оба
    # предложения записаны одним ключом `qualifying_class_levels`
    # (`vanilla/feat_requirements.json`, читает `Rules.Prereqs`). У «Бледного
    # Призывателя» все пять заклинаний взяты на уровнях Бледного мастера при
    # ПМ 16/19/22/25/28 — то есть по настоящему правилу законны.
    #
    # ⚠️ Пять отказов при этом НЕ исчезли: у каждого остался `requires_skill_ranks`
    # по Spellcraft, и он настоящий. Ровно так проверялась ширина правки: если бы
    # легальными стали все пять, правило применили бы слишком широко.
    #
    # ⚠️ И половина старого разбора остаётся верной, поэтому записана здесь:
    # `ruleset.casting.advancement` двигает таблицу слотов хозяина на число
    # нечётных уровней ПМа, но у этого билда хозяин — Бард 4, и 4 + 15 = 19
    # уровней барда дают максимум **6-й круг**. Девятого круга он не достигает
    # и не достигнет — просто эпические заклинания его и не требуют.
  }

  # Everything the parser lifts off a page, split into what this run compares and
  # what it refuses to. `every number lifted off a page is classified` keeps the
  # two lists exhaustive, so a new parser field cannot arrive unclassified — the
  # point being that "not comparable" is visible rather than merely absent.
  @compared [
    :race,
    :alignment_en,
    :abilities,
    :ability_increases,
    :levels,
    :declared_feats,
    :declared_skill_points,
    :declared_free_skill_points,
    :declared_skills,
    # 🔴 Единственное ИТОГОВОЕ число страницы в этом списке, и оно здесь потому,
    # что единственное сравнимое (задача 3.45). Соседи по разделу «Общее» — AB,
    # AC, сейвы — лежат в `@not_comparable`: это одетый, забаффанный персонаж
    # с мини-сетами. Сопротивление заклинаниям на Сиале не даёт ни один предмет
    # и ни один бафф из тех, что носят эти билды: источников во всём корпусе два,
    # оба фиты, оба постоянные, — и «63» на «Мастер Монах» сходится с моделью
    # в точку.
    :declared_spell_resistance
  ]

  # Fields the parser lifts but this run refuses to compare, with the reason.
  #
  # Hit points are absent from the list because they are absent from the pages: not
  # one of the eight states its own, and the hub gives «Среднее количество ХП:
  # 700-1000» for every character on the shard at once, explicitly crediting crafts
  # and mini-sets. There is nothing to parse, let alone compare. Our naked number
  # is pinned in `model.hp` instead, derived from hit dice and constitution.
  @not_comparable [
    # «Бонус атаки: +71 (Максимум +77)» is a finished character under buffs, with
    # weapon enchantment, potions, the shard's weapon system and the +20 attack
    # ceiling all inside it. Our base attack is pinned separately, derived from
    # the class progression tables.
    declared_attack_bonus: "geared and buffed total; no page breaks it down",

    # Same: «Спасброски: 58 Стойкости / 47 Рефлексов / 41 Воли» is base + ability
    # modifier + up to +20 from items + Spellcraft ranks. Base saves are pinned
    # separately.
    declared_saves: "geared total; base saves are pinned from the progression tables",

    # The raw tail of each ladder line, which the feat reader then tokenises. The
    # *feats* it yields are compared (`declared_feats`); the leftover prose —
    # «// Заливаем Тамбл в 20, дисцу, хил» — is a note to the reader and is no
    # more comparable than the description above it.
    level_notes: "raw line tails; the feats read out of them are compared instead",

    # Parse health, not a game number — asserted directly instead.
    problems: "parse diagnostics, asserted directly"
  ]

  # Struct fields that identify the page rather than describe the character.
  @bookkeeping [:__struct__, :title, :revid, :race_ru, :race_en, :alignment_ru]

  # The other twelve pages the wiki files under «Билды для новичков». They are
  # listed rather than skipped: "we cover 8 of 20" has to be visible, and a
  # thirteenth prose build appearing must force somebody to look at it.
  #
  # One fact settles all twelve regardless of their format: **not one of them
  # states a skill-point total**. That is the number this run compares, so even a
  # perfectly parsed ladder would have nothing to check against — reading them
  # would buy a class split and nothing else. The format notes say what a future
  # importer would be up against.
  #
  # source: each page named, priv/wiki_cache/siala/, снято 2026-08-01.
  @prose_builds [
    {"Варвар Сагры", "two builds on one page; class runs in prose, numbered lines are feats"},
    {"Крадущийся в Тени", "class runs as ranges («1-9 рейндж», «10-15 ШД»)"},
    {"Мастер Бард", "ladder in lower-case slang («:15 бг»), class names abbreviated"},
    {"Мастер Лучник", "ladder in its own format («:11 Тайный лучник(Arcane archer)»)"},
    {"Мастер рукопашного боя", "class runs as ranges, numbered lines are feats"},
    {"Мастер Тайной магии", "numbered lines are feats only; classes only in prose"},
    {"Мастер форм", "class order in prose, numbered lines are feats"},
    {"Мастер ядов", "numbered lines are feats; ranks listed in slang («х 43», «мс 43»)"},
    {"Ученик Красного дракона", "class runs in prose, numbered lines are feats"},
    {"Черный страж Азарака", "class runs as ranges («2-10 ренж», «11-40 БГ»)"},
    {"Шаман Друид", "ladder in slang («:1 друид»), feats transliterated"},
    {"Шаман Священник", "ladder in slang («:1 лвл клерик»), feats transliterated"}
  ]

  setup_all do
    ruleset = Data.ruleset!("siala_41")
    pages = Map.new(WikiBuildPage.load_all(), &{&1.title, &1})

    %{ruleset: ruleset, vanilla: Data.ruleset!("vanilla"), pages: pages}
  end

  describe "coverage" do
    test "every cached page with a level ladder has a fixture", %{pages: pages} do
      found = WikiBuildPage.discover()
      snapshotted = Enum.map(@builds, & &1.title)

      assert Enum.sort(found) == Enum.sort(snapshotted),
             """
             found #{length(found)} build pages in the cache, #{length(snapshotted)} fixtures.
             unsnapshotted: #{inspect(found -- snapshotted)}
             missing from the cache: #{inspect(snapshotted -- found)}
             """

      assert map_size(pages) == length(@builds)
    end

    test "every page the wiki calls a build is either read or declared unreadable" do
      candidates = WikiBuildPage.discover_candidates()
      read = Enum.map(@builds, & &1.title)
      declared = Enum.map(@prose_builds, &elem(&1, 0))

      assert Enum.sort(candidates) == Enum.sort(read ++ declared),
             """
             #{length(candidates)} build pages in the cache: #{length(read)} read as fixtures,
             #{length(declared)} declared unreadable. Unaccounted for:
               new: #{inspect(candidates -- (read ++ declared))}
               gone: #{inspect((read ++ declared) -- candidates)}
             A new build page must be read or listed in @prose_builds with a reason.
             """
    end

    # The reason the twelve are left alone, held as an invariant rather than a
    # comment: reading one would buy a class split and nothing to check it with.
    # The day a prose page grows «в сумме N очков навыков» this fails and somebody
    # has to go and read it.
    test "no page declared unreadable states a total to compare against" do
      with_totals =
        for {title, _format} <- @prose_builds,
            page = WikiBuildPage.load!(title),
            page.declared_skill_points,
            do: {title, page.declared_skill_points}

      assert with_totals == [],
             "these now state a skill total and are worth parsing: #{inspect(with_totals)}"
    end

    test "every page parses whole, with no unread lines", %{pages: pages} do
      unreadable =
        for {title, page} <- pages, page.problems != [], do: {title, page.problems}

      assert unreadable == [],
             "#{length(unreadable)} of #{map_size(pages)} pages did not parse: #{inspect(unreadable)}"
    end

    test "every number lifted off a page is classified" do
      described = @compared ++ Keyword.keys(@not_comparable) ++ @bookkeeping
      actual = Map.keys(%WikiBuildPage{})

      assert actual -- described == [],
             "unclassified fixture fields: #{inspect(actual -- described)} — " <>
               "add each to @compared or to @not_comparable with a reason"

      # And nothing classified that the parser does not produce, so a stale entry
      # cannot stand in for a field that quietly disappeared.
      assert described -- actual == [],
             "classified but not parsed: #{inspect(described -- actual)}"
    end

    # source: CLAUDE.md §3 (fandom "Point buy" revid 57460) — six scores starting
    # at 8, a 30-point budget, and the cumulative prices below.
    #
    # This is what settles how the ability block on these pages must be read. Taken
    # as printed, «Гном Защитник» has CHA 6, which the scale cannot produce at all,
    # and «Бледный Призыватель» costs 33 of 30. Take the racial modifiers off first
    # and all eight come to exactly 30. So the pages print the character sheet, and
    # the fixture subtracts the race to recover the point buy.
    test "printed ability scores are the character sheet, not the point buy", %{
      pages: pages,
      ruleset: ruleset
    } do
      cost = %{8 => 0, 9 => 1, 10 => 2, 11 => 3, 12 => 4, 13 => 5, 14 => 6, 15 => 8, 16 => 10}

      budgets =
        for {title, page} <- pages do
          spent =
            page
            |> WikiBuildPage.base_abilities(ruleset)
            |> Enum.reduce(0, fn {_ability, score}, acc -> acc + Map.fetch!(cost, score) end)

          {title, spent}
        end

      assert Enum.all?(budgets, fn {_title, spent} -> spent == 30 end),
             "off the 30-point budget: #{inspect(Enum.reject(budgets, &(elem(&1, 1) == 30)))}"
    end
  end

  # ── ranks a page states that its own ladder cannot reach ──────────────────
  #
  # Since 03.08.2026 the rank ceiling is read off the class taken on **each
  # level** rather than off the build as a whole (Дан, observed in game:
  # a Sorcerer 1–39 who takes Fighter at 40 cannot raise Spellcraft there).
  # The pages know this rule and write it down — «Discipline - 43 (Доступен
  # только на уровнях рейнджера)» on «Мастер Вор», «Spot - 43 (Доступен только
  # на уровнях ассасина)» on «Мастер Монах». Both notes are about skills that
  # are perfectly buyable cross-class, so they can only be about the ceiling,
  # and under the old reading both would have been false: three Ranger levels
  # would have made Discipline a class skill of the build for good.
  #
  # One number does not fit, and the page contradicts itself on it: «Мастер
  # Монах» lists Discipline 43, while its own level guide says «:39. Монах //
  # Заливаем 42 Discipline» and never returns to the skill. Level 40 is an
  # Assassin, for whom Discipline is cross-class (ceiling 21), so 42 is where
  # the ladder stops — the summary carries the level-40 class maximum the
  # author wrote against every other skill in the list.
  @rank_over_ceiling [{"Мастер Монах", :discipline, 43, 42}]

  describe "rules the whole set must obey" do
    test "no build breaks a cap or a limit", %{pages: pages, ruleset: ruleset} do
      # Only caps and limits: prerequisites are checked against feats and ranks
      # these fixtures deliberately do not encode, so `requires_feat` here would
      # be an artefact of the fixture and not a finding.
      caps = [:level_cap, :max_classes, :class_level_cap]

      broken =
        for {title, page} <- pages,
            build = WikiBuildPage.to_build(page, ruleset),
            {class, level} <- Enum.with_index(build.levels, 1),
            {:error, reasons} <-
              [Rules.validate_level_up(Build.truncate(build, level - 1), class, ruleset)],
            hard = Enum.filter(reasons, &(elem(&1, 0) in caps)),
            hard != [],
            do: {title, level, class, hard}

      assert broken == []
    end

    # ⚠️ Тот же вопрос, заданный вторым входом в ядро — и именно он ловил баг,
    # которого не видел тест выше. Там лестница выращивается (`truncate` + класс),
    # здесь проигрывается как ГОТОВАЯ (`%{class:, at:}`) — так её видят импорт
    # и шаренная ссылка. Пока `prestige_pre_epic/4` считал уровни престижа по
    # билду целиком, а уровень персонажа по моменту, три из восьми страниц
    # получали по десять ложных обвинений: «Мастер оружия Сагровик» (11–20),
    # «Гном Защитник» (11–20) и «Бледный Призыватель» (4–16 через уровень).
    # Все три легальны: их 11-й уровень престижа приходится на 21-й, 26-й
    # и 21-й уровень персонажа соответственно.
    test "no build is accused of entering a prestige class too early", %{
      pages: pages,
      ruleset: ruleset
    } do
      accused =
        for {title, page} <- pages,
            build = WikiBuildPage.to_build(page, ruleset),
            {class, level} <- Enum.with_index(build.levels, 1),
            {:error, reasons} <-
              [Rules.validate_level_up(build, %{class: class, at: level}, ruleset)],
            {:requires_character_level, needed} <- reasons,
            do: {title, level, class, needed}

      assert accused == []
    end

    # Положительный контроль к предыдущему: `refute` зеленеет и там, где
    # проверяемое не попало в поле зрения. Правило существует и на этой же
    # форме вызова срабатывает — стоит сдвинуть лестницу «Сагровика» на один
    # уровень раньше, и 11-й уровень Мастера оружия падает на 20-й уровень
    # персонажа, чего шард не разрешает.
    test "the same sweep does refuse a ladder that enters one level too early", %{
      pages: pages,
      ruleset: ruleset
    } do
      page = Map.fetch!(pages, "Мастер оружия Сагровик")
      build = WikiBuildPage.to_build(page, ruleset)
      early = %{build | levels: tl(build.levels)}

      accused =
        for {class, level} <- Enum.with_index(early.levels, 1),
            {:error, reasons} <- [
              Rules.validate_level_up(early, %{class: class, at: level}, ruleset)
            ],
            {:requires_character_level, needed} <- reasons,
            do: {level, needed}

      assert accused == [{20, 20}]
    end

    # ⚠️ Требование престиж-класса, записанное дизъюнкцией классов, до этой волны
    # до ядра не доезжало вовсе: загрузчик срезал ключ `any_of`, и Бледного
    # мастера можно было взять первым уровнем без единого уровня заклинателя.
    # Теперь оно проверяется — и обязано не задеть готовые лестницы.
    #
    # ⚠️ Проверка идёт по ГОТОВОЙ лестнице (`%{class:, at:}`), потому что вопрос
    # про момент: требование смотрит на уровни, взятые ДО этого, а не на итог.
    #
    # source: fandom "Pale master" revid 71581 — «Three levels of bard, sorcerer,
    # or wizard fulfills this requirement»; "Red dragon disciple" revid 71919 —
    # «Class: bard or sorcerer».
    test "no build is refused by a class requirement written as a choice", %{
      pages: pages,
      ruleset: ruleset
    } do
      accused =
        for {title, page} <- pages,
            build = WikiBuildPage.to_build(page, ruleset),
            {class, level} <- Enum.with_index(build.levels, 1),
            {:error, reasons} <-
              [Rules.validate_level_up(build, %{class: class, at: level}, ruleset)],
            {:requires_any_of, _} = reason <- reasons,
            do: {title, level, class, reason}

      assert accused == []
    end

    # Положительный контроль: `refute` зеленеет и там, где проверяемое не попало
    # в поле зрения. «Бледный Призыватель» ставит Бледного мастера на 4-й уровень,
    # и перед ним ровно три уровня Барда — без запаса. На третьем их два.
    test "and the same requirement refuses a pale master one bard level early", %{
      pages: pages,
      ruleset: ruleset
    } do
      build = WikiBuildPage.to_build(Map.fetch!(pages, "Бледный Призыватель"), ruleset)

      assert Enum.take(build.levels, 4) == [:bard, :bard, :bard, :pale_master]
      assert Rules.validate_level_up(build, %{class: :pale_master, at: 4}, ruleset) == :ok

      assert {:error, reasons} =
               Rules.validate_level_up(build, %{class: :pale_master, at: 3}, ruleset)

      assert {:requires_any_of,
              [
                [{:requires_class_level, :bard, 3}],
                [{:requires_class_level, :sorcerer, 3}],
                [{:requires_class_level, :wizard, 3}]
              ]} in reasons
    end

    # ⚠ Against `max_ranks/4` — the tallest ceiling the **ladder** ever offered —
    # and not against the ceiling of the last level, which answers a different
    # question entirely. «Мастер Вор» finishes on a Ranger level, where his 33
    # ranks of Use Magic Device could not be raised by one; they were bought as a
    # Rogue and no later level takes them back. Comparing a finished total
    # against the last level's ceiling accused him of exactly that.
    test "no declared rank exceeds our ceiling", %{pages: pages, ruleset: ruleset} do
      over =
        for {title, page} <- pages,
            build = WikiBuildPage.to_build(page, ruleset),
            level = length(build.levels),
            {skill, ranks} <- WikiBuildPage.committed_ranks(page),
            cap = Skills.max_ranks(build, ruleset, skill, level),
            ranks > cap,
            do: {title, skill, ranks, cap}

      assert Enum.sort(over) == Enum.sort(@rank_over_ceiling),
             """
             new:  #{inspect(Enum.sort(over) -- @rank_over_ceiling, pretty: true)}
             gone: #{inspect(@rank_over_ceiling -- Enum.sort(over), pretty: true)}
             A rank the ladder cannot reach is either a page's arithmetic or our
             ceiling rule; decide which and say so in `@rank_over_ceiling`.
             """
    end

    # The ceiling formula, checked from the other side: these pages stop their
    # class skills at 43 and their cross-class Tumble at 20, which is exactly
    # `character level + 3` and its half at level 40. Both numbers appear on
    # several pages written by different authors.
    #
    # ⚠ It is level 40's own class that is asked, and this build is built so the
    # question is real: level 40 is a Weapon Master, who has Discipline and has
    # not got Tumble. A ladder ending on a class without Discipline would answer
    # 21 to the first line, which is the whole point of the rule.
    test "the 43 the pages aim for is the class ceiling at level 40", %{
      pages: pages,
      ruleset: ruleset
    } do
      page = Map.fetch!(pages, "Мастер оружия Сагровик")
      build = WikiBuildPage.to_build(page, ruleset)

      assert Build.class_at(build, 40) == :weapon_master
      assert Skills.rank_cap(build, ruleset, :discipline, 40) == 43
      # Tumble is a class skill of none of barbarian, fighter or weapon master,
      # so the ceiling halves — and 20 is the most the page asks for
      assert Skills.rank_cap(build, ruleset, :tumble, 40) == 21
    end

    # source: «Мастер Вор» revid as recorded above — «*Discipline - 43 (Доступен
    # только на уровнях рейнджера)». Discipline is not exclusive and may be bought
    # cross-class by anybody, so «доступен только на уровнях рейнджера» is a
    # statement about the **ceiling** and about nothing else. The build takes
    # Ranger at 1–3, 20 and 40; every other level is a Rogue or a Shadowdancer,
    # for whom Discipline is cross-class.
    #
    # This is the wiki's own, independent statement of the rule Дан observed in
    # game, and it is why the page ends on a Ranger level at all: level 40 is the
    # only level that offers a ceiling of 43.
    test "a page states the per-level ceiling itself, and the ladder obeys it", %{
      pages: pages,
      ruleset: ruleset
    } do
      build = "Мастер Вор" |> then(&Map.fetch!(pages, &1)) |> WikiBuildPage.to_build(ruleset)

      ranger_levels = for {:ranger, level} <- Enum.with_index(build.levels, 1), do: level
      assert ranger_levels == [1, 2, 3, 20, 40]

      # Only those levels offer the class ceiling; the rest offer its half.
      assert Skills.rank_cap(build, ruleset, :discipline, 40) == 43
      assert Skills.rank_cap(build, ruleset, :discipline, 39) == 21
      assert Skills.max_ranks(build, ruleset, :discipline, 40) == 43

      # ⚠ Positive control for the sentence above: under the old reading — «a
      # class skill of *any* class taken so far» — level 39 would have answered
      # 42 and the page's note would have been meaningless.
      assert Skills.class_skill_by?(build, ruleset, :discipline, 39)
    end
  end

  describe "feats across the whole set" do
    # `@feat_refusals` explains; this makes sure it explains **all of it**, and
    # only what is really there. A refusal that quietly resolved would otherwise
    # leave a stale entry sitting where the next real one should appear.
    test "every feat that fits no slot has a declared cause", %{pages: pages, ruleset: ruleset} do
      actual =
        for {title, page} <- pages,
            finding <- WikiBuildPage.feat_plan(page, ruleset).unplaced,
            do: {title, finding.level, finding.feat}

      declared = Enum.flat_map(@feat_refusals, & &1.where)

      assert Enum.sort(actual) == Enum.sort(declared),
             """
             unexplained: #{inspect(Enum.sort(actual -- declared), pretty: true)}
             stale:       #{inspect(Enum.sort(declared -- actual), pretty: true)}
             Each one belongs in @feat_refusals under a cause, with a verdict on
             whose mistake it is — ours or the page's (CLAUDE.md §3).
             """
    end

    # ⚠️ Самое сильное подтверждение запрета «этот фит нельзя выбрать на уровне
    # такого-то класса» (задача 1.10, шаг 2), какое есть: восемь страниц билдов,
    # написанных разными людьми, играющими в эту игру, — и ни одного фита,
    # поставленного на уровень класса, который его запрещает. Проверяется НЕ через
    # раскладку по слотам (там такой пик просто не лёг бы и уехал в `unplaced`),
    # а по объявленному странице хвосту строки — то есть по тому, что автор
    # действительно написал.
    #
    # Положительный контроль обязателен и он ниже, в паре: те же 18 фитов
    # на страницах ЕСТЬ, семь раз, — и каждый раз на уровне класса, которому они
    # разрешены. Без второй половины первая зеленела бы и от того, что ни один
    # из 18 фитов в билдах не встречается вовсе.
    test "ни один билд вики не берёт фит на уровне класса, который его запрещает", %{
      pages: pages,
      ruleset: ruleset
    } do
      taken =
        for {title, page} <- pages,
            build = WikiBuildPage.to_build(page, ruleset),
            {level, entries} <- page.declared_feats,
            %{feat: feat} when not is_nil(feat) <- entries,
            class = Build.class_at(build, level),
            not is_nil(class),
            do: {title, level, class, feat}

      forbidden =
        for {_title, _level, class, feat} = pick <- taken,
            MapSet.member?(ruleset.classes[class].unavailable_feats, feat),
            do: pick

      assert forbidden == [],
             """
             Страница билда ставит фит на уровень класса, чей список его не
             содержит. Расхождение с фикстурой — повод перепроверить ОБЕ стороны
             (CLAUDE.md §3): либо у нас список неверен, либо автор страницы
             ошибся, и решать это человеку.
             #{inspect(forbidden, pretty: true)}
             """

      # Положительный контроль: эти 22 фита на страницах действительно берут.
      watched =
        for {_id, class} <- ruleset.classes,
            feat <- class.unavailable_feats,
            into: MapSet.new(),
            do: feat

      seen = for {_t, _l, _c, feat} <- taken, MapSet.member?(watched, feat), do: feat

      # ⚠️ Здесь стояло 8, и стало 14 — 10.08.2026, когда прочитали третье
      # семейство `vanilla/feat_requirements.json` («этот фит можно взять ТОЛЬКО
      # на уровне такого-то класса», девять фитов). Шесть новых взятий — и все
      # шесть ЛЕГАЛЬНЫЕ, то есть это не «нашли нарушения», а самое сильное
      # подтверждение нового запрета, какое здесь можно получить:
      #
      #   «Бледный Призыватель» берёт все пять эпических заклинаний на уровнях
      #   **Бледного мастера** (26, 29, 32, 35, 38), а не на уровнях волшебника,
      #   — и `pale_master` в разрешённом списке ровно потому, что источник
      #   называет второй способ получить право («or having at least 15 pale
      #   master levels»). Забудь я эту половину предложения — этот билд стал бы
      #   нелегальным пять раз подряд.
      #
      #   «Мастер оружия Сагровик» берёт `Epic Weapon Specialization` на 39-м, и
      #   класс этого уровня — **воин**, один из двух названных страницей.
      assert length(seen) == 14,
             "ожидались 14 взятий фитов из этого списка, а нашлось #{length(seen)}: #{inspect(seen)}"

      # И это не один и тот же фит восемь раз: разные фиты на разных классах.
      #
      # ⚠️ Восьмое взятие — источник 4 (AGENT_QUEUE.md §1.10), и оно ЛЕГАЛЬНОЕ,
      # не второй пример «нашли билд с запрещённым фитом». «Мастер Ловушек»
      # берёт `Blinding speed` на уровне 37, и класс ЭТОГО уровня — Рейнджер,
      # а не Арфист-скаут. `blinding_speed` попал в `watched`, потому что
      # ГДЕ-ТО в ruleset'е его запрещает Харпист (`watched` — объединение
      # запретов ВСЕХ классов, не только класса конкретного пика); Ranger сам
      # его не запрещает (`blinding_speed.bonus_for` прямо включает `ranger`,
      # и `forbidden == []` выше об этой строке заслуженно молчит). Это тот
      # же случай, что divine_might/divine_shield ниже: фит из «наблюдаемого»
      # списка взят на классе, которому он разрешён, а не запрещён.
      assert Enum.sort(Enum.uniq(seen)) == [
               :blinding_speed,
               :divine_might,
               :divine_shield,
               :epic_spell_dragon_knight,
               :epic_spell_epic_mage_armor,
               :epic_spell_greater_ruin,
               :epic_spell_hellball,
               :epic_spell_mummy_dust,
               :epic_weapon_specialization,
               :spell_focus,
               :weapon_specialization
             ]
    end

    test "every unreadable feat token is declared with a reason", %{
      pages: pages,
      ruleset: ruleset
    } do
      actual =
        for {title, page} <- pages,
            {level, raw} <- WikiBuildPage.feat_plan(page, ruleset).unreadable,
            do: {title, level, raw}

      declared = for {title, level, raw, _why} <- @unreadable_feat_tokens, do: {title, level, raw}

      assert Enum.sort(actual) == Enum.sort(declared),
             """
             new: #{inspect(actual -- declared)}
             gone: #{inspect(declared -- actual)}
             A token the feat dictionary does not know is either a name to add to
             `@feat_aliases` or a note the author wrote to themselves. Decide which.
             """
    end

    test "every unmet prerequisite has a declared cause" do
      tags =
        for entry <- @builds,
            {_level, _feat, reasons} <- entry.model.feats.prerequisites_unmet,
            reason <- reasons,
            uniq: true,
            do: elem(reason, 0)

      assert Enum.sort(tags) == Enum.sort(Map.keys(@prerequisite_causes)),
             """
             unclassified: #{inspect(tags -- Map.keys(@prerequisite_causes))}
             stale:        #{inspect(Map.keys(@prerequisite_causes) -- tags)}
             """
    end

    # The honest half of a rank requirement this run *can* check. Timing is out
    # of reach — no page states when a rank was bought — but a page that never
    # buys twenty ranks of anything cannot take Epic Skill Focus at any time, so
    # the final targets it does state are a necessary condition and are checked.
    # Silence is not evidence: the three pages that state no ranks are skipped.
    test "rank prerequisites are within reach of the page's own targets", %{pages: pages} do
      short =
        for entry <- @builds,
            page = Map.fetch!(pages, entry.title),
            ranks = WikiBuildPage.committed_ranks(page),
            ranks != %{},
            best = Enum.max(Map.values(ranks)),
            {level, feat, reasons} <- entry.model.feats.prerequisites_unmet,
            reason <- reasons,
            unreachable?(reason, ranks, best),
            do: {entry.title, level, feat, reason}

      assert short == [],
             """
             these feats need ranks the page's own final targets never reach, so no
             purchase schedule could make them legal: #{inspect(short, pretty: true)}
             """
    end
  end

  # source: priv/rules/siala_41/overrides.json — `epic.spell_selection_at_41`
  # («На 41-м уровне нельзя выбирать заклинания», revid 20387, `verified`) and
  # `skills.rank_cap_at_41`.
  #
  # ⚠ Synthetic: **no wiki build page reaches level 41**, and none of the eight
  # ends on a caster whose class table is still running. So this ladder is made
  # up — a Fighter who then takes twenty Bard levels — purely to put level 41 in
  # front of the parts of the core the eight fixtures cannot reach.
  describe "the 41st level (derived from the rules, on no wiki page)" do
    setup %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :true_neutral,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 8, cha: 16},
          levels: List.duplicate(:fighter, 21) ++ List.duplicate(:bard, 20)
        )

      %{build: build}
    end

    test "is the cap, and 42 is not", %{build: build, ruleset: ruleset} do
      assert ruleset.level_cap == 41
      assert Rules.validate_level_up(Build.truncate(build, 40), :bard, ruleset) == :ok
      assert Rules.validate_level_up(build, :bard, ruleset) == {:error, [{:level_cap, 41}]}
    end

    test "gives +1 base attack and nothing to the saves", %{build: build, ruleset: ruleset} do
      stats = Rules.compute(build, ruleset)

      # The first twenty levels are all Fighter: base attack 20, saves 12/6/6.
      # The epic levels add +1 attack on each odd level 21…41 (eleven of them)
      # and +1 to every save on each even level 22…40 (ten).
      assert Epic.attack_bonus(ruleset, 41) == 11
      assert Epic.save_bonus(ruleset, 41) == 10
      assert stats.base_attack == 31
      assert {stats.base_fort, stats.base_ref, stats.base_will} == {22, 16, 16}
      # frozen by the base attack of 20 at level 20
      assert stats.attacks_per_round == 4
    end

    # source: overrides.json `skills.rank_cap_at_41` — «43 → 44, ванильная
    # формула «уровень + 3» просто продолжается», `source: user`.
    test "raises the rank ceilings to 44 and 22", %{ruleset: ruleset, pages: pages} do
      # A build with a genuinely cross-class skill, so both halves are real:
      # Tumble belongs to none of barbarian, fighter or weapon master.
      page = Map.fetch!(pages, "Мастер оружия Сагровик")
      build = Build.add_level(WikiBuildPage.to_build(page, ruleset), :weapon_master)

      assert Skills.rank_cap(build, ruleset, :discipline, 41) == 44
      assert Skills.rank_cap(build, ruleset, :tumble, 41) == 22
    end

    # source: `overrides.json` `epic.spell_selection_at_41: false` («На 41-м
    # уровне нельзя выбирать заклинания», revid 20387, `verified`) — now read by
    # `Rules.Spells`. The check is only worth anything because the bard table is
    # *still running* on this level: the ladder is built so that character level
    # 41 is bard class level 20, which grants a circle-5 spell in vanilla and
    # would grant one here too if the shard rule were not applied. So this
    # distinguishes "the shard forbids the choice" from "the table ran out",
    # which is the other, unrelated reason a caster sees nothing.
    test "offers no known-spell choice on 41, as the shard forbids", %{
      build: build,
      ruleset: ruleset
    } do
      assert Build.class_level_at(build, 41) == 20, "the bard table is still running here"
      assert Spells.slots_at(build, ruleset, 41) == []

      # …and the level below it, an ordinary epic level, is untouched: bard 19
      # is where the table adds a fourth circle-6 spell and a fifth circle-4 one
      # (`spells_known` rows 18 and 19 in vanilla/classes.json).
      assert [%{circle: 4}, %{circle: 6}] =
               Spells.slots_at(Build.truncate(build, 40), ruleset, 40)
    end

    # The prohibition is the shard's own, not a fact about a top level in
    # general. Vanilla says nothing about it, so its flag stays true and its own
    # cap level still offers the choice — the same ladder, the same class level,
    # a different ruleset.
    test "vanilla states no such rule, so its own top level still chooses", %{
      build: build,
      ruleset: ruleset,
      vanilla: vanilla
    } do
      assert vanilla.epic.spell_selection_at_level_cap?
      refute ruleset.epic.spell_selection_at_level_cap?

      at_cap = Build.truncate(build, vanilla.level_cap)
      assert Build.class_level_at(at_cap, 40) == 19
      assert [%{circle: 4}, %{circle: 6}] = Spells.slots_at(at_cap, vanilla, 40)
    end

    test "grants no general feat and no ability increase", %{build: build, ruleset: ruleset} do
      stats = Rules.compute(build, ruleset)

      assert Map.get(stats.feat_slots, 41, []) == []
      refute MapSet.member?(ruleset.epic.general_feat_levels, 41)
      refute MapSet.member?(ruleset.epic.ability_increase_levels, 41)
    end

    test "does not exist under the vanilla ruleset", %{build: build, vanilla: vanilla} do
      assert vanilla.level_cap == 40

      assert {:error, reasons} =
               Rules.validate_level_up(Build.truncate(build, 40), :bard, vanilla)

      assert {:level_cap, 40} in reasons
    end
  end

  for entry <- @builds do
    @entry entry

    describe "#{entry.title} (revid #{entry.revid})" do
      test "reads off the page as the snapshot records", %{pages: pages} do
        entry = @entry
        page = Map.fetch!(pages, entry.title)

        assert page.revid == entry.revid, "the cached page moved — re-read the fixture"
        assert page.race == entry.page.race
        assert page.alignment_en == entry.page.alignment
        assert page.abilities == entry.page.abilities
        assert page.ability_increases == entry.page.ability_increases
        assert length(page.levels) == entry.page.character_level
        assert Enum.frequencies(page.levels) == entry.page.class_levels
        assert page.declared_skill_points == entry.page.skill_points
        assert page.declared_free_skill_points == entry.page.free_skill_points
        assert WikiBuildPage.committed_ranks(page) == entry.page.committed_ranks
        assert page.declared_attack_bonus == entry.page.attack_bonus
        assert page.declared_saves == entry.page.saves
        assert page.declared_spell_resistance == entry.page.spell_resistance
      end

      # ⚠️ AGENT_QUEUE.md §7 «Стенд регрессии считает числа без фитов» (волна 10,
      # 08.08.2026). До задачи 1.9 `feats: true` было безразлично этому тесту —
      # фиты нигде не входили в числа. Теперь `Toughness` (класс раздаёт даром,
      # `Build.granted_feats/3` не читает `build.feats` вообще — считается и
      # без фитов) сосуществует с `Epic toughness` и прибавками характеристик
      # от фитов (`Great constitution`, задача 3.1 — `Abilities.scores_at/3`
      # читает `AbilityBonuses`, которая смотрит именно `build.feats`), и вторая
      # половина не считалась. HP — единственное поле здесь, которое это
      # затрагивает; проверено прогоном по всем восьми страницам 08.08.2026
      # (не только по двум, названным в долге, — «Гном Защитник» тоже сорвался,
      # хоть в долге и не упомянут):
      #
      #   * `base_attack`, `base_saves`, `attacks_per_round` — вообще не читают
      #     ни фиты, ни характеристики (`Progression.base/2`,
      #     `attacks_per_round/3` идут только по `build.levels` и классовым
      #     таблицам); `attack_ability`, `attack_bonus`, `ac_*`, полные `fort`/
      #     `ref`/`will` (не «base») — читают, но эти поля этот тест не
      #     сравнивает вовсе (там, где сравнивает — `feats: true` уже стоит,
      #     ниже, в «the feats add exactly the caveats we know about»).
      #   * `skill_points.earned` тоже читает характеристику (INT, тем же
      #     путём через `Abilities.scores_at/3`) и оттого не застрахован
      #     структурно — среди этих восьми билдов просто нет фита на INT.
      #     Гвардия ниже — не украшение: она ловит день, когда девятая
      #     страница его заведёт, а не тихо продолжает считать по старому.
      #
      # Чинить фитозависимость `attack_ability` здесь и подмешивать `feats:
      # true` в НЕЁ нельзя — расходится с Weapon Finesse у «Мастер Вор» и
      # «Мастер Монах» (AGENT_QUEUE.md §7 предупреждение), но этот тест её
      # и не трогает.
      test "the model still produces the snapshot's numbers", %{pages: pages, ruleset: ruleset} do
        entry = @entry
        page = Map.fetch!(pages, entry.title)
        build = WikiBuildPage.to_build(page, ruleset)
        stats = Rules.compute(build, ruleset)
        with_feats = Rules.compute(WikiBuildPage.to_build(page, ruleset, feats: true), ruleset)

        assert stats.character_level == entry.page.character_level
        assert stats.class_levels == entry.page.class_levels
        assert stats.base_attack == entry.model.base_attack

        assert %{fort: stats.base_fort, ref: stats.base_ref, will: stats.base_will} ==
                 entry.model.base_saves

        # ⚠ Та же сумма, разложенная по классам, и сверяется она с числами
        # ИЗ ФИКСТУРЫ, а не с самой суммой: сумма считается из этих же строк, то
        # есть «Σ == итог» здесь тавтологична (HANDOFF, «инвариант бывает
        # тавтологичным»). Числа фикстуры сняты с таблиц прогрессии Fandom
        # человеком — они и есть независимая сторона. Плюс половина строк
        # у настоящих страниц законно нулевая, а нулевой терм суммы не двигает
        # вовсе, так что сверху него сумма молчала бы в принципе.
        assert save_terms_by_class(stats) == entry.model.base_saves_by_class

        assert stats.attacks_per_round == entry.model.attacks_per_round
        assert with_feats.hp == entry.model.hp
        assert stats.skill_points.earned == entry.model.skill_points_earned
        assert WikiBuildPage.plan_cost(page, build, ruleset) == entry.model.plan_cost

        # Положительный контроль на само допущение «фиты не трогают эти поля»
        # — а не только вывод из чтения кода. Разойдись оно на девятой
        # странице, тест должен упасть здесь, а не молча продолжить читать
        # `stats` (без фитов) как раньше.
        assert stats.base_attack == with_feats.base_attack

        assert {stats.base_fort, stats.base_ref, stats.base_will} ==
                 {with_feats.base_fort, with_feats.base_ref, with_feats.base_will}

        # И разбор по классам тоже: он идёт по `build.levels` и классовым
        # таблицам, фитов не читает вовсе — но утверждение это структурное,
        # а не проверенное, пока рядом не стоит вот эта строка.
        assert save_terms_by_class(stats) == save_terms_by_class(with_feats)

        assert stats.attacks_per_round == with_feats.attacks_per_round
        assert stats.skill_points.earned == with_feats.skill_points.earned
      end

      # 🔴 Единственное «итоговое» число страницы, которое сверяется с моделью
      # НАПРЯМУЮ (задача 3.45). Все остальные — AB, AC, сейвы, HP — числа
      # со шмотом, баффами и мини-сетами, и сверять их можно только «голыми»
      # (CLAUDE.md §3, «мини-сеты дают +15…+91 % к HP»). Спелл-резист на Сиале
      # не даёт ни один предмет и ни один бафф из тех, что носят эти билды:
      # его источников во всём корпусе ровно два, оба фиты, оба постоянные.
      #
      # ⚠ Считается по билду С ФИТАМИ, и это содержательная часть проверки:
      # `Diamond soul` приходит выдачей класса и стоит в обоих числах, а девять
      # взятий `Improved spell resistance` — только там, где фиты прочитаны.
      # 45 против 63 — ровно эта разница.
      #
      # ⚠ Страница, которая числа не называет, проверяется тоже: у неё
      # `spell_resistance: nil`, и тогда утверждение здесь — «модель не выдумала
      # SR там, где источника нет». Семь из восьми билдов дают ноль, восьмой —
      # 63; ни одного промежуточного случая в наборе нет.
      test "the page's spell resistance is the model's, number for number", %{
        pages: pages,
        ruleset: ruleset
      } do
        entry = @entry
        page = Map.fetch!(pages, entry.title)
        with_feats = Rules.compute(WikiBuildPage.to_build(page, ruleset, feats: true), ruleset)

        # ⚠️ Сравнивается со СТРАНИЦЕЙ, а не с числом фикстуры, и это не обход
        # предупреждения компилятора (хотя и он: литеральный `nil` у семи
        # фикстур из восьми делает любую ветку под него заведомо мёртвой).
        # Так проверка честнее в цепочке: страница ↔ фикстура пиннится тестом
        # выше, а здесь модель ↔ страница. Перестань парсер читать число —
        # упадёт первый тест, а не этот молча сойдётся на нулях.
        assert with_feats.spell_resistance == (page.declared_spell_resistance || 0)
      end

      # Sorted set comparison rather than list equality: the order gaps are
      # concatenated in is an implementation detail of `Rules.compute/2` and
      # nothing here should be pinned to it. What is pinned is *which* caveats
      # this build carries, and both directions fail — an unexpected one is a
      # new unmodelled rule to look at, a missing one is a fact that quietly
      # left `siala_41/classes.json`.
      test "the build carries exactly the caveats we know about", %{
        pages: pages,
        ruleset: ruleset
      } do
        entry = @entry
        page = Map.fetch!(pages, entry.title)
        build = WikiBuildPage.to_build(page, ruleset)
        stats = Rules.compute(build, ruleset)

        expected = Enum.sort(expected_gaps(entry))
        actual = Enum.sort(stats.gaps)

        assert actual == expected,
               """
               #{entry.title}: the gap list moved.
                 appeared: #{inspect(actual -- expected, pretty: true)}
                 gone:     #{inspect(expected -- actual, pretty: true)}
               A gap that appeared is a shard rule we do not model — read it before
               adding it here. A gap that is gone either got modelled or fell out
               of the data (CLAUDE.md §9).
               """
      end

      test "reads the feats off the page as the snapshot records", %{pages: pages} do
        entry = @entry
        page = Map.fetch!(pages, entry.title)

        # `feats_at/2` drops the unreadable tokens, so the ladder is compared
        # against the raw entries instead — a token that stopped resolving has to
        # show up here as a `nil` rather than as a shorter list.
        ladder =
          Map.new(page.declared_feats, fn {level, entries} ->
            {level, Enum.map(entries, & &1.feat)}
          end)

        assert ladder == entry.model.feats.taken

        assert WikiBuildPage.feats_at(page, 1) ==
                 Enum.reject(Map.fetch!(entry.model.feats.taken, 1), &is_nil/1)
      end

      # Where each of those feats goes, and what happens to the ones that fit
      # nowhere. The counts are pinned alongside the lists because a tokeniser
      # that silently stopped reading second feats would shrink the lists without
      # producing a single new finding.
      test "the page's feats go into the slots the core grants", %{
        pages: pages,
        ruleset: ruleset
      } do
        entry = @entry
        page = Map.fetch!(pages, entry.title)
        plan = WikiBuildPage.feat_plan(page, ruleset)
        expected = entry.model.feats

        assert Enum.map(plan.unplaced, &{&1.level, &1.feat}) == expected.unplaced,
               """
               #{entry.title}: which feats fit no slot has changed.
               #{inspect(plan.unplaced, pretty: true)}
               Every one has to be in @feat_refusals with a cause and a verdict.
               """

        assert plan.granted == expected.granted
        assert plan.unreadable == expected.unreadable

        assert %{declared: plan.declared, slots: plan.slots, filled: plan.filled} ==
                 %{
                   declared: expected.declared,
                   slots: expected.slots,
                   filled: expected.filled
                 }

        # Nothing may be lost between the two: every feat read is either handed
        # over by a class, placed in a slot, left unplaced, or unreadable.
        assert plan.declared ==
                 length(plan.granted) + plan.filled + length(plan.unplaced) +
                   length(plan.unreadable)
      end

      test "the prerequisites of the page's feats are as recorded", %{
        pages: pages,
        ruleset: ruleset
      } do
        entry = @entry
        page = Map.fetch!(pages, entry.title)
        build = WikiBuildPage.to_build(page, ruleset, feats: true)

        unmet =
          for {level, slots} <- Enum.sort(build.feats),
              {_slot, feat} <- Enum.sort(slots),
              {:error, reasons} <-
                [Rules.validate_feat(build, %{feat: feat, at: level}, ruleset)],
              do: {level, feat, reasons}

        assert unmet == entry.model.feats.prerequisites_unmet,
               """
               #{entry.title}: the unmet prerequisites moved.
                 appeared: #{inspect(unmet -- entry.model.feats.prerequisites_unmet, pretty: true)}
                 gone:     #{inspect(entry.model.feats.prerequisites_unmet -- unmet, pretty: true)}
               Whose problem each one is is recorded in @prerequisite_causes.
               """
      end

      # The feats bring gaps of their own, and the same argument applies as to
      # `class_caveats`: a build that takes Weapon Focus without saying what it
      # cannot check about the weapon is quietly overstating what it knows.
      #
      # ⚠️ TASK 3.5 REMOVED ONE CAVEAT FROM ALL SEVEN FIXTURES THAT HAD IT:
      # `{:missing_data, {:choice_domain, :weapon}}`. It was true — weapons had
      # no dictionary at all — and `priv/rules/vanilla/weapons.json` is exactly
      # what made it stop being true, so every one of those lines is a deliberate
      # deletion rather than a fixture bent to match a run. What did NOT go is
      # `{:not_modelled, {:feat_qualifier, :weapon_focus, "proficiency with the
      # chosen weapon"}}`: the choice is checked against the dictionary now,
      # whether the character is *proficient* with what he chose still is not.
      test "the feats add exactly the caveats we know about", %{pages: pages, ruleset: ruleset} do
        entry = @entry
        page = Map.fetch!(pages, entry.title)
        without = Rules.compute(WikiBuildPage.to_build(page, ruleset), ruleset)
        with_feats = Rules.compute(WikiBuildPage.to_build(page, ruleset, feats: true), ruleset)

        added =
          with_feats.gaps
          |> MapSet.new()
          |> MapSet.difference(MapSet.new(without.gaps))
          |> Enum.sort()

        assert added == Enum.sort(entry.model.feats.caveats)

        # Weapon Finesse moves the attack off strength — the §6 "third kind of
        # feat", the one that is a change of formula and not an addend. Two of
        # the eight builds take it, and their attack ability is pinned.
        assert with_feats.attack_ability == entry.model.feats.attack_ability
      end

      # source: priv/rules/siala_41/overrides.json — `character.level_cap` 41,
      # `epic.level_41_behaviour` (`source: user`, «41-й нечётный, значит даёт
      # +1 к base attack и НЕ даёт прибавки к сейвам»), `skills.rank_cap_at_41`.
      #
      # ⚠ **This level is on no wiki page.** All eight builds stop at 40; the
      # 41st here is the same class one more time, and everything asserted about
      # it is derived from the rules above. Nothing observed is being claimed.
      test "one more level behaves the way the shard's 41st is documented to", %{
        pages: pages,
        ruleset: ruleset
      } do
        entry = @entry
        page = Map.fetch!(pages, entry.title)
        at_40 = WikiBuildPage.to_build(page, ruleset)
        at_41 = Build.add_level(at_40, entry.level_41.class)

        assert entry.level_41.class == List.last(at_40.levels),
               "the 41st level is the build's own last class taken once more"

        before = Rules.compute(at_40, ruleset)
        after_41 = Rules.compute(at_41, ruleset)

        assert after_41.character_level == 41
        assert after_41.base_attack == before.base_attack + 1
        assert after_41.base_fort == before.base_fort
        assert after_41.base_ref == before.base_ref
        assert after_41.base_will == before.base_will
        # Attacks per round were frozen by the base attack at level 20; no epic
        # level has ever added one and 41 is an epic level like any other.
        assert after_41.attacks_per_round == before.attacks_per_round

        # ⚠️ Тот же манёвр и по той же причине, что чуть выше в «the model
        # still produces the snapshot's numbers» (AGENT_QUEUE.md §7): `hp_gain`
        # — разница, а не абсолютное число, но фит всё равно её задевает,
        # когда поднимает CONSTITUTION (`Great constitution`) — прибавка идёт
        # в КАЖДЫЙ уровень персонажа, включая только что добавленный 41-й, так
        # что она не сокращается при вычитании, в отличие от плоской
        # `Epic toughness`. У «Гном Защитник» `hp_gain` без фитов — 17, с
        # фитами (два взятия `Great constitution`) — 18. Проверено прогоном по
        # всем восьми страницам 08.08.2026 — у остальных семи дельта не
        # шевелится, но полагаться на «сегодня так у семи из восьми» без
        # гвардии ниже — то самое допущение по недостаточной выборке
        # (HANDOFF.md).
        at_40_with_feats = WikiBuildPage.to_build(page, ruleset, feats: true)
        at_41_with_feats = Build.add_level(at_40_with_feats, entry.level_41.class)
        before_with_feats = Rules.compute(at_40_with_feats, ruleset)
        after_41_with_feats = Rules.compute(at_41_with_feats, ruleset)

        assert hp_gain(before_with_feats, after_41_with_feats) == entry.level_41.hp_gain

        assert after_41.skill_points.earned - before.skill_points.earned ==
                 entry.level_41.skill_point_gain

        # Гвардия: все остальные числа этого теста совпадают что без фитов,
        # что с ними, на всех восьми страницах сегодня. Разойдись это — тест
        # обязан упасть здесь, а не молча продолжить читать `after_41`/`before`
        # (без фитов) как источник истины для чисел, которые фит тоже трогает.
        assert after_41.base_attack == after_41_with_feats.base_attack

        assert {after_41.base_fort, after_41.base_ref, after_41.base_will} ==
                 {after_41_with_feats.base_fort, after_41_with_feats.base_ref,
                  after_41_with_feats.base_will}

        assert after_41.attacks_per_round == after_41_with_feats.attacks_per_round

        assert after_41.skill_points.earned - before.skill_points.earned ==
                 after_41_with_feats.skill_points.earned - before_with_feats.skill_points.earned

        # 41 is neither a general feat level (they run 1, 3 … 39) nor an ability
        # increase level (4, 8 … 40). A *class* bonus slot may still land there —
        # Dwarven Defender's epic bonus levels reach class level 26, which is
        # this build's 41st — so only the general slot is asserted away.
        refute MapSet.member?(ruleset.epic.general_feat_levels, 41)
        refute MapSet.member?(ruleset.epic.ability_increase_levels, 41)
        refute Enum.any?(Map.get(after_41.feat_slots, 41, []), &(&1.class == nil))

        # 42 is over the cap. Other reasons come with it — the prestige
        # requirements of a class taken again are re-checked against a fixture
        # that encodes no ranks — so the cap is asserted, not the whole list.
        assert {:error, reasons} =
                 Rules.validate_level_up(at_41, entry.level_41.class, ruleset)

        assert {:level_cap, 41} in reasons
      end

      # ⚠️ Тот же манёвр, что в двух тестах выше, и по той же причине
      # (AGENT_QUEUE.md §7): под ванилью `Epic toughness` и `Great
      # constitution` — те же ванильные фиты, ничего сиальского в них нет
      # (`vanilla/feat_hp_bonuses.json`, `vanilla/feat_ability_bonuses.json`),
      # так что дыра повторяется здесь буквально с теми же тремя страницами
      # и теми же причинами. `Toughness` ваниль не выдаёт вовсе (страницы это
      # и объясняют — «Бесплатного Toughness в ванили нет»), поэтому под
      # feats:true считается только Epic toughness / Great constitution.
      test "the same ladder under the vanilla ruleset", %{pages: pages, vanilla: vanilla} do
        entry = @entry
        page = Map.fetch!(pages, entry.title)
        build = WikiBuildPage.to_build(page, vanilla)
        stats = Rules.compute(build, vanilla)
        with_feats = Rules.compute(WikiBuildPage.to_build(page, vanilla, feats: true), vanilla)

        # `vanilla:` is a diff over `model:`, and the empty diff is the
        # assertion: a change that moved a vanilla number without moving a Siala
        # one would show up here as an undeclared difference.
        expected = Map.merge(Map.take(entry.model, comparable_fields()), entry.vanilla)

        actual = %{
          base_attack: stats.base_attack,
          base_saves: %{fort: stats.base_fort, ref: stats.base_ref, will: stats.base_will},
          # ⚠ Здесь это ещё и проверка того, что шард сейвы НЕ переписывал: ни
          # один из 23 классов не несёт правки `saves`, поэтому разбор обязан
          # совпасть с ванильным на всех восьми страницах. Появится правка —
          # диффу `vanilla:` придётся её объявить, и это станет видимым событием,
          # а не тихим расхождением (у BAB так уже случилось с монахом).
          base_saves_by_class: save_terms_by_class(stats),
          attacks_per_round: stats.attacks_per_round,
          hp: with_feats.hp,
          skill_points_earned: stats.skill_points.earned,
          plan_cost: WikiBuildPage.plan_cost(page, build, vanilla)
        }

        assert actual == expected,
               """
               #{entry.title} computes differently under the vanilla ruleset than declared.
               Add the field to `vanilla:` with the arithmetic, or find out what broke.
               #{inspect(Map.reject(actual, fn {k, v} -> expected[k] == v end), pretty: true)}
               """

        # Гвардия: как и в «the model still produces the snapshot's numbers»
        # — все поля здесь, кроме HP, обязаны совпадать что без фитов, что
        # с ними, на всех восьми страницах сегодня.
        assert stats.base_attack == with_feats.base_attack

        assert {stats.base_fort, stats.base_ref, stats.base_will} ==
                 {with_feats.base_fort, with_feats.base_ref, with_feats.base_will}

        # И разбор по классам тоже: он идёт по `build.levels` и классовым
        # таблицам, фитов не читает вовсе — но утверждение это структурное,
        # а не проверенное, пока рядом не стоит вот эта строка.
        assert save_terms_by_class(stats) == save_terms_by_class(with_feats)

        assert stats.attacks_per_round == with_feats.attacks_per_round
        assert stats.skill_points.earned == with_feats.skill_points.earned

        assert Enum.sort(stats.gaps) == Enum.sort(entry.vanilla_gaps)

        # Vanilla caps at 40, so the 41st level this file exercises above is
        # exactly the level vanilla refuses.
        assert {:error, reasons} =
                 Rules.validate_level_up(build, entry.level_41.class, vanilla)

        assert {:level_cap, 40} in reasons
      end

      test "every page↔model difference is declared", %{pages: pages, ruleset: ruleset} do
        entry = @entry
        page = Map.fetch!(pages, entry.title)
        build = WikiBuildPage.to_build(page, ruleset)
        stats = Rules.compute(build, ruleset)
        cost = WikiBuildPage.plan_cost(page, build, ruleset)

        declared = Map.new(entry.divergences, &{&1.field, &1})

        # Only fields the page actually states can disagree; a page that is silent
        # is not evidence either way. Driven off the parsed page rather than the
        # snapshot, so a page that stops stating a number stops being compared.
        comparisons =
          [
            page.declared_skill_points &&
              {:skill_points_earned, page.declared_skill_points, stats.skill_points.earned},
            page.declared_skill_points && page.declared_free_skill_points &&
              {:plan_cost, page.declared_skill_points - page.declared_free_skill_points, cost},
            WikiBuildPage.committed_ranks(page) != %{} &&
              {:plan_cost_fits, true, cost <= stats.skill_points.earned}
          ]
          |> Enum.filter(& &1)

        undeclared =
          for {field, wiki, ours} <- comparisons,
              wiki != ours,
              not Map.has_key?(declared, field),
              do: {field, wiki: wiki, ours: ours}

        assert undeclared == [],
               """
               #{entry.title} disagrees with the wiki on something not listed in `divergences`.
               Work out who is wrong before touching this file — an expectation bent to
               match the code turns this run into a snapshot of a bug (CLAUDE.md §3).
               #{inspect(undeclared, pretty: true)}
               """

        # And the other way round: a divergence that stopped diverging is stale
        # bookkeeping, and leaving it in would hide the next real one.
        stale =
          for %{field: field} = divergence <- entry.divergences,
              {^field, wiki, ours} <- comparisons,
              wiki == ours,
              do: divergence

        assert stale == [],
               "#{entry.title}: these divergences have resolved — delete them: #{inspect(stale)}"
      end
    end
  end

  # `model.gaps` holds whatever is specific to the build (a missing hit die);
  # `model.class_caveats` holds what the shard says about the classes it uses,
  # grouped by class because that is how the source file is organised and how a
  # reviewer checks it against `siala_41/classes.json`.
  defp expected_gaps(entry) do
    entry.model.gaps ++
      for {class, whats} <- Map.get(entry.model, :class_caveats, %{}), what <- whats do
        {:not_modelled, {:class_change, class, what}}
      end
  end

  # Hit points are `nil` for one build (red dragon disciple has no hit die), and
  # `nil - nil` is not a gain of zero.
  defp hp_gain(%{hp: nil}, %{hp: nil}), do: nil
  defp hp_gain(%{hp: before}, %{hp: now}), do: now - before

  # What `vanilla:` is a diff over. Everything under `model:` that both rulesets
  # compute the same way is here; the feats, the gaps and the class caveats are
  # not, because they have their own comparisons and their own shard layers.
  defp comparable_fields do
    [
      :base_attack,
      :base_saves,
      :base_saves_by_class,
      :attacks_per_round,
      :hp,
      :skill_points_earned,
      :plan_cost
    ]
  end

  # `stats.save_breakdown.by_class` в форме фикстуры: картой по классу, а не
  # списком. Порядок термов проверяется юнит-тестами ядра (и совпадает с
  # порядком разбора BAB), а здесь важно другое — что у КАЖДОГО класса страницы
  # свои три числа и свой счётчик засчитанных уровней.
  defp save_terms_by_class(stats) do
    Map.new(stats.save_breakdown.by_class, fn term ->
      {term.class, Map.put(term.subtotals, :levels, term.levels_counted)}
    end)
  end

  # A rank requirement the page's own final targets cannot satisfy at any point
  # in the build — the necessary half of a check whose sufficient half needs a
  # purchase schedule no page states.
  defp unreachable?({:requires_skill_ranks, skill, needed}, ranks, _best),
    do: Map.get(ranks, skill, 0) < needed

  defp unreachable?({:requires_any_skill_ranks, needed}, _ranks, best), do: best < needed
  defp unreachable?(_reason, _ranks, _best), do: false
end
