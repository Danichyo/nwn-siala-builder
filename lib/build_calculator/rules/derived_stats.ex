defmodule BuildCalculator.Rules.DerivedStats do
  @moduledoc """
  Everything `BuildCalculator.Rules.compute/2` works out about a build.

  A field is `nil` when it could not be computed honestly; `gaps` then holds the
  machine-readable reason. A plausible-looking number would be the worse answer,
  because it never shows up as a failure.

  ## Base, then levels, then gear

  The build is `point buy + race` -> `the +1 every fourth level` -> `gear`, in
  that order, and **everything derived is computed from the final ability score**
  (CLAUDE.md §6). That is not a detail: `+12 CON` is +6 to the modifier, which is
  +6 hit points on every level and +246 on a level 41 build. `abilities_naked`
  keeps the pre-gear scores so the interface can show `было → стало`.

  ⚠ И у `abilities_naked` с 16.08.2026 есть второй читатель, не про показ:
  **требование по характеристике сравнивается именно с ним** — «статы с вещей
  не работают при выборе фитов. Только поинт бай + левел апы» (Dan,
  `GAME_CHECKS.md` S1), то же самое и в источнике («It is this unmodified score
  (the base score) that matters when meeting the prerequisite of a feat»,
  `fandom:Ability score`). То есть поле держит правило, а не только подпись,
  и убрать его как «дубль для интерфейса» нельзя: `Rules.Prereqs` без него
  отвечает `{:missing_data, {:prerequisite, :abilities}}`. Числа при этом
  считаются по-прежнему от **одетого** значения, все до одного.

  ⚠ В тот же день ту же работу получили сейвы — `saves_naked` (кейс S2, «вещи
  на спасы также не откроют фит, должен быть закрыт»), — а 17.08.2026 работа
  у них **отделилась в своё поле**: требование по сейву читает
  `saves_for_prereqs`, потому что из него вычтено ещё и то, что источник
  исключил поимённо (кейс S3, `Luck of heroes`). У характеристик такого
  расщепления пока нет: ни одну прибавку к статам из требований никто не
  исключал, и заводить второе поле «на всякий случай» здесь нечем.

  Fields worth spelling out:

    * `base_attack` — total base attack, epic bonus included
    * `base_attack_at_20` — base attack from the class levels that count, before
      the epic bonus; this is what fixes `attacks_per_round`
    * `bab_breakdown` — the same `base_attack`, told per class rather than as one
      number (task 3.16): what each class contributed, how many of its levels
      counted **and how many were thrown away** by epic rule 2, plus the epic
      term. `Fighter 10 / Cleric 15 / Rogue 16` is BAB 28 with the rogue's
      sixteen levels worth exactly nothing, and the panel used to print the 28
      and say nothing about it. Never `nil`; see
      `BuildCalculator.Rules.Progression.bab_breakdown/0`
    * `attack_bonus` — `base_attack` + the attack ability's modifier +
      `attack_extra_bonus`. ⚠ Still **one number**, and since task 3.5 part B it
      means "AB with what is in hand". A map per weapon kind was the alternative
      and it was rejected twice over: Dan asked for «выбрать оружие и глянуть AB
      итоговый», one weapon and one number, and every consumer of this field —
      the totals panel, the view screen, the export, the breakdown — is built
      around a scalar. With no weapon chosen the number is exactly what it was
      before the weapon existed, so nothing had to change to keep working
    * `weapon` — which weapon that was, or `nil`. Refused weapons are not here:
      take the proficiency feat away and the weapon stops counting, which
      `Rules.illegal_gear_weapon/2` reports rather than this hiding
    * `weapon_attack_bonus` / `weapon_attack_terms` — what the weapon adds to the
      attack roll, summed and one term per number the player typed. One number
      since task 3.52 and two before it: an item carries an enhancement bonus
      too, but it differed from the attack bonus only in also giving damage, and
      damage is computed nowhere. **Before** the ceiling, like the three below —
      and the first item bonus ever to be *inside* it, which is what makes the
      +20 reachable at all
    * `attack_ability` — **which** ability that was. Weapon Finesse changes the
      formula, not the value, and an attack bonus that quietly starts coming off
      dexterity looks like a bug unless the interface says so
    * `gear_attack_bonus` / `race_attack_bonus` — two of the three things that
      add to attack beside the base and the ability, **before** the ceiling:
      what gear did to the governing ability, and the shard's racial attack
      bonus (task 3.12). Kept raw so a breakdown can name what each source
      offered. ⚠ Since 10.08.2026 the first of the two is **outside** the ceiling
      (task 3.22), and the interface merges it into the ability's own term rather
      than printing it beside it — `Summary.ab_terms/2`
    * `own_attack_bonus` — the third, and it is the build's own: what its feats
      and class abilities add (`Rules.AttackBonuses`, task 1.12b — `Epic
      prowess`, the file's one unconditional record). Before the ceiling, like
      the two above. ⚠ Small on purpose, and that is a fact about the sources
      rather than about the model: attack bonuses in NWN are almost all
      conditional — on the weapon in hand, the enemy or its relative size, the
      terrain, a combat mode — and the conditional ones stay out of the number
      and name themselves in `gaps`. ⚠ A small race's size modifier used to sit
      beside `Epic prowess` here too, until task 3.143 (30.08.2026) found its
      condition ("when dealing with larger creatures") had been read off a
      quote truncated one clause short — it is one of the conditional ones now
    * `own_attack_terms` — the same, one entry per source rather than summed, so
      the breakdown can print `Epic prowess +1` instead of an anonymous number.
      Each term carries `under_cap?`, because the ceiling below does not cover
      all of them
    * `attack_extra_bonus` — those three **after** the ruleset's ceiling: the
      sources the ceiling covers, clipped together exactly once, plus the sources
      it does not cover, added on top of the clip. ⚠ Since 09.08.2026 a feat's
      bonus is one of the latter — Dan: «Фиты не входят в кап атаки +20» — and
      since 10.08.2026 so is gear: an ability modifier is outside the +20 whatever
      raised it («Бонус силы в кап 20 не входит», task 3.22, `GAME_CHECKS.md` J1),
      which is how the saves had always treated it. **Under the ceiling there are
      exactly two sources** — the shard's racial bonus, word for word on its own
      page, and the weapon in hand, which Dan named first when he listed what
      fills the +20 (task 3.5 part B). Which sources fall where is read from
      `stat_caps.attack_bonus.applies_to_sources` and never decided in code
      (`Rules.Caps.covers_source?/3`)
    * `dual_wield` — бой двумя оружиями целиком: чем он вызван, лёгкая ли вторая
      рука, штраф по каждой руке и из чего он собрался
      (`BuildCalculator.Rules.DualWield`, задача 3.132). `nil` у персонажа
      с одним оружием — и это ответ, а не пропуск: штрафа у него нет вовсе.
      ⚠ Штраф главной руки УЖЕ ВНУТРИ `attack_bonus` выше; поле нужно разбору,
      чтобы напечатать, откуда взялись эти −2, а не для второго вычитания
    * `off_hand` — те же числа для ВТОРОЙ руки: своё оружие, своя
      характеристика атаки, своё число с предмета, свой клип потолка и своё
      число атак. `nil`, когда второй руки нет. Решение Dan 28.08.2026: «Для
      второй руки отдельную строку, мешать не надо».
      ⚠ Отдельная карта, а не десяток полей рядом с главными: у второй руки
      те же вопросы и те же имена, и разложить их плоско значило бы завести
      десять полей с приставкой, которые невозможно перепутать только по
      внимательности.
      ⚠ `attacks_per_round` внутри — **своё** число, а не копия главной руки:
      сама вторая рука даёт одну атаку, `Improved two-weapon fighting` —
      вторую, а у главной руки их в это время четыре.
      ⚠ `attack_capped?` внутри — тоже своё: усиление у рук разное, и одна
      может упереться в +20 там, где другая нет. В `capped` ниже при этом
      попадает один и тот же `:attack_bonus` — кап принадлежит СТАТУ, а не руке
    * `attack_cap_clipped` — how much that ceiling took off: `0`, or negative.
      ⚠ Carried rather than left to a caller's subtraction: with the ceiling
      covering only some sources, `attack_extra_bonus` minus the raw terms is no
      longer the clip, and a breakdown deriving it that way would charge the loss
      to a feat that was never clipped
    * `fort` / `ref` / `will` — base save + governing modifier +
      `save_bonus`'s entry for that save
    * `saves_naked` — `%{fort:, ref:, will:}`, те же три числа у персонажа
      **без вещей вообще**: без числа в поле «сейвы», без модификатора, который
      подняли предметы, и без фита, одолженного вещью. Слово «голым» тут значит
      ровно то же, что у `ac_naked` и `abilities_naked`, и ровно это, а не
      «сколько засчитает требование» — на второй вопрос отвечает поле ниже
      (правил в нём на одно больше, `GAME_CHECKS.md` S3).

      ⚠ Это **не** `fort` минус `gear_save_bonus`: клип потолка стоит внутри
      формулы, а не снаружи, и разность врала бы всюду, где он кусает —
      Spellcraft +8 при вещах +20 даёт после капа те же +20, то есть разность
      напечатала бы 0 вместо честных 8. Считается вторым проходом того же
      конвейера по билду с пустым `Gear`

      🔴 **Названо вслух: с 17.08.2026 в `lib/` это поле не читает никто** —
      оба его читателя (проверка требования и сортировка «почти дотянулся»)
      переехали на `saves_for_prereqs`. Оставлено не по инерции, и причин две.
      Первая: это «голое» число того же рода, что `ac_naked`, и интерфейс
      вправе его напечатать — сейчас он этого не делает, но правило «голым
      значит без вещей» от числа читателей не зависит. Вторая, важнее:
      **это единственное место, где правило S2 (вещи) наблюдаемо отдельно от
      правила S3 (исключённая запись)** — сложи их в одно поле, и разъехаться
      они смогут молча, а тест, проверяющий «три дороги вещи», начнёт заодно
      проверять и вычет Удачи, не отличая одно от другого.

      ⚠ Появится читатель-интерфейс — он читает **это** поле, а не соседнее:
      «сколько было бы без предметов» и «что засчитает требование» — разные
      вопросы, и второе меньше первого ровно на исключённые прибавки
    * `saves_for_prereqs` — `%{fort:, ref:, will:}`, то, с чем сравнивается
      **требование** фита по сейву (`Rules.Prereqs`, ключ `save_bonus`).

      🔴 Поле держит правило, а не подпись, и вычетов у него **два**, оба
      названные источником, а не выведенные: вещи целиком — «вещи на спасы
      также не откроют фит, должен быть закрыт» (Dan, 16.08.2026,
      `GAME_CHECKS.md` S2), — и записи разметки, которые источник исключил
      поимённо: сегодня `Luck of heroes`, «The fortitude bonus from ''luck of
      heroes'' does not count towards the fortitude required»
      (`fandom:Resist energy`), подтверждено замером Dan 17.08.2026 на Сиале
      (кейс S3). Убрать поле как «дубль голого числа» нельзя: `Rules.Prereqs`
      без него отвечает `{:missing_data, {:prerequisite, :save_bonus}}`.

      ⚠ Совпадает с `saves_naked` у всякого билда, который не держит ни одной
      исключённой записи, — то есть почти у каждого. Отдельным полем оно всё
      равно нужно: числа расходятся ровно там, где правило и кусает, а поле,
      меняющее смысл в зависимости от читателя, расходится молча
    * `save_breakdown` — the class part of those three, told per class rather
      than as the single «база» term the interface used to print: what each
      class contributed to fort, ref **and** will, how many of its levels
      counted and how many epic rule 2 threw away, plus the epic term.
      `Wizard 20 → Fighter 20` has the saves of a wizard and twenty fighter
      levels worth nothing, and the caption used to say «база 6» and leave the
      player to guess whose. ⚠ Not three breakdowns but one, with a map per
      save inside each term: the level counts are facts about the class, and
      three copies of them could disagree. Never `nil`; see
      `BuildCalculator.Rules.Progression.save_breakdown/0`
    * `save_bonus` — `%{fort:, ref:, will:}`, everything that adds to that
      **one** save, after the ruleset's ceiling — what the player typed under
      "Вещи", the Spellcraft ranks, and the build's own feats/class
      abilities/racial traits (task 1.12a: `Iron will`, `Divine grace`,
      `Sacred defense`…). ⚠ A single scalar until task 1.12a, because the two
      sources that predated it (gear, Spellcraft) both land on all three
      saves identically — the map only became honest once a source
      (`Iron will`) could raise one save and not the others. **One ceiling
      per save**, covering every source that lands on it, not one ceiling per
      source and not one shared pool across all three (CLAUDE.md §9: clipping
      gear and Spellcraft separately once let a build carry +40 while every
      source said +20 — the same failure a per-source or a pooled clip here
      would reproduce with three sources instead of two)
    * `gear_save_bonus` / `skill_save_bonus` — those two terms as they stand
      before the ceiling, still scalars because both remain save-agnostic:
      what the player typed applies to all three, and so does Spellcraft's
      rule. The Spellcraft one exists because players do not count it
      (CLAUDE.md §3)
    * `own_save_bonus` — `%{fort:, ref:, will:}`, the build's **own**
      contribution before the ceiling — a Paladin's charisma, a Champion of
      Torm's class table (`Rules.SaveBonuses`, task 1.12a). Part of what
      `save_bonus` sums, kept separate so the interface can caption it by
      name rather than folding it into "вещи"
    * `own_save_terms` — the same, one entry per `(source, save)` pair rather
      than summed — a Paladin's `Divine grace` names itself in the Fort, Ref
      **and** Will breakdowns rather than showing up as an anonymous number.
      Each term carries `under_cap?`, because since 09.08.2026 the ceiling covers
      exactly one of the fourteen sources here (`Sacred defense`) and a breakdown
      has to put the rest **after** the clip row rather than before it
    * `save_cap_clipped` — `%{fort:, ref:, will:}`, how much the ceiling took off
      each save: `0`, or negative. ⚠ Carried rather than left to a caller's
      subtraction, the same as `attack_cap_clipped`: with most of the build's own
      terms sitting on top of the ceiling, `save_bonus` minus the raw addends is no
      longer the clip
    * `spell_resistance` — сопротивление заклинаниям, одним числом (задача 3.45).
      Сегодня его дают ровно два фита, оба монашеские: `Diamond soul` (уровень
      монаха + 10) и `Improved spell resistance` (+2 за взятие, потолок эффекта
      +20). ⚠ **`0`, а не `nil`, у билда без обоих**, и это ответ, а не молчание:
      разведка по девяти файлам корпуса сплошная, SR не даёт ни один класс,
      навык или раса, — то есть ноль здесь полон. `nil` в этой структуре значит
      «честно посчитать нельзя», и говорить так про известную нам пустоту
      означало бы завести дырку на месте ответа.

      ⚠ Ограничителя на итог нет: 71 на капе Сиалы — арифметика (монах 41 плюс
      десять взятий), а не потолок. Fandom пишет «maximum possible spell
      resistance of 70» про ванильный кап 40, и это не правило
    * `spell_resistance_terms` — то же по слагаемым, чтобы разбор печатал
      `Diamond soul · Монах 35 → 45`, а не безымянное число
      (`BuildCalculator.Rules.SpellResistance.term_entry/0`). ⚠ Пустой список —
      это и есть «строки нет»: показывать ли её, решает интерфейс, и Dan назвал
      воротами 12 уровней монаха
    * `skill_modifiers` — what a skill's final value gets that is not a rank:
      today only the four-class stealth penalty. Skills with no modifier are
      absent from the map rather than zero
    * `skill_values` — `%{skill_id => value}` for every skill the build bought
      ranks in: ranks, the geared ability modifier, the racial affinity and the
      shard modifier, assembled (`BuildCalculator.Rules.Skills.value/4`). A skill
      whose key ability nobody wrote down carries `total: nil` and says why
    * `hp_breakdown` — the same total as `hp`, regrouped by class rather than
      folded away (task 3.6): `by_class`'s hit-die subtotals, plus `con_term`
      and `floor_adjustment`, sum to `hp` exactly — see
      `BuildCalculator.Rules.Progression.hp_breakdown/0`. `nil` exactly when
      `hp` is, never independently
    * `ac_naked` — with no gear at all, dexterity included: otherwise "голым"
      stops meaning naked
    * `ac_geared` / `ac_by_type` — the same with equipment. Different AC types
      stack and are summed, and **inside** one type what the player typed adds to
      what the build earns itself (task 3.91) — except against a shape the
      ruleset declares an exception, where the two compete and the larger wins.
      One shape is one today: the shard's shield armour class. So `ac_by_type` is
      what the typed number **contributed** — `0` on a type it lost — while
      `ac_gear_bonus` stays what was typed
    * `ac_types_resolved` — the same story type by type, both sides named
      (`BuildCalculator.Rules.ArmorClass.type_entry/0`): what the build has, what
      was typed, what counted, who won. The interface needs it to explain a
      typed number showing as nothing
    * `ac_superseded_types` — the short version of the above: types where the
      typed number did not land at all
    * `ac_cap_clipped` — how much a type's own ceiling took off the **build's
      own** side, `0` or negative and `0` on every shipped ruleset. Carried for
      the same reason `attack_cap_clipped` is: a breakdown that prints raw terms
      needs a term for the loss, or it stops adding up to its own total
    * `ac_dexterity` — the dexterity term of «AC в шмоте» after the ceiling the
      worn armour puts on it (task 3.41): `modifier` whole, `counted` after the
      cap, the `cap` itself and whether it bit. 🔴 The cap is **armour class's
      alone** — `ref`, `attack_bonus` and every skill go on using the whole
      modifier, which is what `fandom:Maximum dexterity bonus` states in as many
      words. A reader wanting "dexterity" wants `ability_modifiers.dex`; only a
      reader printing the terms of `ac_geared` wants this.

      ⚠ Its `capped?` deliberately does **not** also appear in `capped` below:
      that list means "hit a ceiling out of `ruleset.stat_caps`", and this
      ceiling belongs to the item worn — there is no `stat_caps` entry to look
      its value up in, so a flag there would print "упёрлось в кап" with no
      number beside it
    * `ac_own_terms` / `ac_own_bonus` — what the **build itself** adds to
      armour class: a Monk's wisdom and class table, a Pale Master's `Bone
      skin`, `Armor skin`, Tumble's ranks (`BuildCalculator.Rules.ArmorClass`,
      task 3.11). Part of the naked number, because a class ability is not
      equipment. ⚠ A small race's size modifier sat here too until task 3.143
      (30.08.2026): its condition ("when dealing with larger creatures") had
      been read off a quote truncated one clause short, and the fix moved it
      to `not_modelled` — it earns no term at all now
    * `ac_own_terms_geared` / `ac_own_bonus_geared` — the same terms recomputed
      against the geared ability scores. ⚠ Two things make the geared list
      differ, not one: `Monk AC bonus` is worth whatever wisdom is worth, so
      `+12 WIS` off items is `+6` here — and a term whose type lost to a typed
      number is **absent**, the same way a Monk's terms are absent in armour
    * `capped` — stats that hit a ceiling from `ruleset.stat_caps`. A number that
      stopped growing must say why, or the player reads it as an error. ⚠
      Carries `:fort_save` / `:ref_save` / `:will_save` **separately** since
      task 1.12a, not one shared `:saving_throws` — the three saves' own
      bonuses can now differ (`Iron will` only ever touches Will), so a build
      may sit at the ceiling on one and not the other two, and a badge on all
      three when only one is capped would be exactly the "reads as an error"
      case this field exists to prevent
    * `ac_capped_types` — which AC types were clipped, for the same reason:
      `:gear_ac` in `capped` says *that* something was, this says which. Only
      `dodge` has a ceiling today, and armour class as a whole has none
    * `skill_points` — `%{earned:, spent:, free:}`, a running total over all levels
    * `feat_slots` / `spell_slots` — `%{character_level => [slot]}`
    * `spells_per_day` — one entry per casting class, with the level-20 wall
    * `racial_bonus` — the shard's own racial bonus in full: which shape, where it
      landed, all four numbers the page states and which one was counted
      (`BuildCalculator.Rules.RacialBonus`). `nil` for a race that has none and
      for the vanilla ruleset. ⚠ The counted number is **not** the largest of the
      four — the two that need a weapon in hand are never counted — so the rest
      are not decoration: the interface has to print them, or a floor reads as
      the whole truth
    * `weapon_type_bonuses` — what the shard gives for the **type of weapon in
      hand** (`BuildCalculator.Rules.WeaponTypeBonus`, task 3.35): a list, because
      one weapon can carry three at once, and `[]` for vanilla, for empty hands
      and for a weapon the page excludes by name. ⚠ A **second** term beside
      `racial_bonus` above and not a replacement for it — Dan measured the two
      being added (`GAME_CHECKS.md` Q1), and that is also where the racial record's
      two uncounted variants come from
    * `class_groups` — the shard's groupings of classes this build belongs to,
      «Воины Сагры» / «Воины Адры» (`BuildCalculator.Rules.ClassGroups`). A
      property of the whole class list, so one level of an outside class empties
      it; `[]` for an empty ladder and for vanilla. ⚠ Two entries is the ordinary
      case, not a corner one: `Fighter` is in both groups
  """

  alias BuildCalculator.Rules.{
    ArmorClass,
    AttackBonuses,
    AttackModifiers,
    Build,
    DualWield,
    GearWeapon,
    ClassGroups,
    Progression,
    RacialBonus,
    SaveBonuses,
    Skills,
    Spells,
    SpellResistance,
    WeaponTypeBonus
  }

  @typedoc "Which saving throw — `Rules.SaveBonuses`'s own key."
  @type save :: :fort | :ref | :will

  @type t :: %__MODULE__{
          character_level: non_neg_integer(),
          class_levels: %{atom() => pos_integer()},
          abilities: %{Build.ability() => integer()},
          ability_modifiers: %{Build.ability() => integer()},
          abilities_naked: %{Build.ability() => integer()},
          ability_modifiers_naked: %{Build.ability() => integer()},
          gear_ability_bonuses: %{Build.ability() => integer()},
          hp: non_neg_integer() | nil,
          hp_breakdown: Progression.hp_breakdown() | nil,
          base_attack: non_neg_integer(),
          base_attack_at_20: non_neg_integer(),
          bab_breakdown: Progression.bab_breakdown(),
          epic_attack_bonus: non_neg_integer(),
          attack_bonus: integer(),
          attack_ability: Build.ability() | nil,
          gear_attack_bonus: integer(),
          race_attack_bonus: integer(),
          weapon_type_attack_bonus: integer(),
          own_attack_bonus: integer(),
          own_attack_terms: [AttackBonuses.term_entry()],
          weapon: atom() | nil,
          weapon_attack_bonus: integer(),
          weapon_attack_terms: [GearWeapon.term_entry()],
          attack_extra_bonus: integer(),
          attack_cap_clipped: integer(),
          dual_wield: DualWield.t() | nil,
          off_hand: map() | nil,
          racial_bonus: RacialBonus.t() | nil,
          weapon_type_bonuses: [WeaponTypeBonus.entry()],
          class_groups: [ClassGroups.membership()],
          attacks_per_round: pos_integer(),
          attacks_per_round_terms: [AttackModifiers.term_entry()],
          base_fort: integer(),
          base_ref: integer(),
          base_will: integer(),
          save_breakdown: Progression.save_breakdown(),
          epic_save_bonus: non_neg_integer(),
          gear_save_bonus: integer(),
          skill_save_bonus: non_neg_integer(),
          save_bonus: %{save() => integer()},
          own_save_bonus: %{save() => integer()},
          own_save_terms: [SaveBonuses.term_entry()],
          save_cap_clipped: %{save() => integer()},
          fort: integer(),
          ref: integer(),
          will: integer(),
          saves_naked: %{save() => integer()},
          saves_for_prereqs: %{save() => integer()},
          ac_naked: integer(),
          ac_geared: integer(),
          ac_gear_bonus: integer(),
          ac_own_bonus: integer(),
          ac_own_bonus_geared: integer(),
          ac_own_terms: [ArmorClass.term_entry()],
          ac_own_terms_geared: [ArmorClass.term_entry()],
          ac_by_type: [{atom(), integer()}],
          ac_types_resolved: [ArmorClass.type_entry()],
          ac_superseded_types: [atom()],
          ac_cap_clipped: integer(),
          ac_dexterity: ArmorClass.dexterity(),
          capped: [atom()],
          ac_capped_types: [atom()],
          skill_points: %{earned: non_neg_integer(), spent: non_neg_integer(), free: integer()},
          spell_resistance: integer(),
          spell_resistance_terms: [SpellResistance.term_entry()],
          skill_modifiers: %{atom() => integer()},
          skill_values: %{atom() => Skills.value()},
          feat_slots: %{pos_integer() => [map()]},
          spell_slots: %{pos_integer() => [Spells.slot()]},
          spells_per_day: [map()],
          gaps: [tuple()]
        }

  defstruct character_level: 0,
            class_levels: %{},
            abilities: %{},
            ability_modifiers: %{},
            abilities_naked: %{},
            ability_modifiers_naked: %{},
            gear_ability_bonuses: %{},
            hp: nil,
            hp_breakdown: nil,
            base_attack: 0,
            base_attack_at_20: 0,
            # A well-formed empty breakdown, not `nil`: `compute/2` always fills
            # it in, and an empty build honestly has no class terms and no epic.
            bab_breakdown: %{by_class: [], epic_term: 0, counted_levels: 0},
            epic_attack_bonus: 0,
            attack_bonus: 0,
            attack_ability: nil,
            gear_attack_bonus: 0,
            race_attack_bonus: 0,
            weapon_type_attack_bonus: 0,
            own_attack_bonus: 0,
            own_attack_terms: [],
            # Ничего в руках — честный дефолт: `nil` и нули, то есть ровно то же
            # число `attack_bonus`, что было до задачи 3.5.
            weapon: nil,
            weapon_attack_bonus: 0,
            weapon_attack_terms: [],
            attack_extra_bonus: 0,
            attack_cap_clipped: 0,
            # Одна рука — честный `nil` у обоих: штрафа стиля нет, второй руки
            # нет, и ноль вместо этого читался бы как посчитанный ответ.
            dual_wield: nil,
            off_hand: nil,
            racial_bonus: nil,
            weapon_type_bonuses: [],
            class_groups: [],
            attacks_per_round: 1,
            # Пусто у ванили всегда и у Сиалы почти всегда: терм появляется
            # только там, где класс шарда действительно добавил атаку
            # (`Rules.AttackModifiers`).
            attacks_per_round_terms: [],
            base_fort: 0,
            base_ref: 0,
            base_will: 0,
            # Same contract as `bab_breakdown` above: a well-formed empty
            # breakdown rather than `nil`, because an empty build honestly has no
            # class terms and no epic bonus.
            save_breakdown: %{by_class: [], epic_term: 0, counted_levels: 0},
            epic_save_bonus: 0,
            gear_save_bonus: 0,
            skill_save_bonus: 0,
            # Well-formed empty maps, not `0`: `compute/2` always fills every
            # key in, and an empty build honestly earns nothing on any save.
            save_bonus: %{fort: 0, ref: 0, will: 0},
            own_save_bonus: %{fort: 0, ref: 0, will: 0},
            own_save_terms: [],
            save_cap_clipped: %{fort: 0, ref: 0, will: 0},
            fort: 0,
            ref: 0,
            will: 0,
            # Все три ключа нулями, как у `save_bonus` выше и по той же причине:
            # у читателей этих двух полей отсутствующий ключ означал бы «сейва
            # нет вовсе», а не «сейв нулевой».
            saves_naked: %{fort: 0, ref: 0, will: 0},
            saves_for_prereqs: %{fort: 0, ref: 0, will: 0},
            ac_naked: 0,
            ac_geared: 0,
            ac_gear_bonus: 0,
            ac_own_bonus: 0,
            ac_own_bonus_geared: 0,
            ac_own_terms: [],
            ac_own_terms_geared: [],
            ac_by_type: [],
            ac_types_resolved: [],
            ac_superseded_types: [],
            ac_cap_clipped: 0,
            # Пустой билд ловкости не имеет и доспехов не носит — ноль без
            # потолка, а не `nil`: у поля всегда есть все четыре ключа, иначе
            # читателю пришлось бы гадать, «нет потолка» это или «нет поля».
            ac_dexterity: %{modifier: 0, counted: 0, cap: nil, capped?: false},
            capped: [],
            ac_capped_types: [],
            # Честный ноль и пустой список: персонаж без обоих фитов имеет
            # сопротивление заклинаниям 0, а не «неизвестно сколько».
            spell_resistance: 0,
            spell_resistance_terms: [],
            skill_points: %{earned: 0, spent: 0, free: 0},
            skill_modifiers: %{},
            skill_values: %{},
            feat_slots: %{},
            spell_slots: %{},
            spells_per_day: [],
            gaps: []
end
