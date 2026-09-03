defmodule BuildCalculator.Reference.UserBuildsTest do
  @moduledoc """
  Regression run against builds a player sent us directly — not a wiki page.

  ## Why this is a separate file from `wiki_builds_test.exs`

  That file is built entirely around `WikiBuildPage`: it discovers pages in
  `priv/wiki_cache/siala/`, parses their wikitext ladder, and its own
  `describe "coverage"` block asserts the fixture titles match exactly what
  `WikiBuildPage.discover/0` finds in the cache. A hand-built `Build.t()` has
  no cached page and no revid, so it does not fit that contract — bending
  `WikiBuildPage` to accept a struct that was never parsed off a page would be
  the dishonest move, and the coverage tests would have to special-case it
  either way. A build sent by Dan directly is a different *kind* of source
  (`source.kind: "user"`, same vocabulary `siala_41/*.json` already uses for
  facts nobody wrote on a wiki page), so it gets its own file rather than a
  faked-up entry in the wiki one.

  ## The first entry, and what it proves

  Dan sent this ladder 14.08.2026 as the illustration behind
  `GAME_CHECKS.md` H7 and the rule it closed in `Rules.Prereqs`: a feat lent by
  a worn **item** satisfies a **class's** requirement block but not a
  **feat's**. `Expertise` (off armour) and `Whirlwind attack` (off a
  quarterstaff) open Weapon Master on character level 14 without occupying a
  slot; both are then picked in slots anyway, on Weapon Master's own 2nd and
  5th class levels, specifically so the items can come off without losing the
  feats (CLAUDE.md §3, «Вещи» — «фит с вещи открывает класс, но не другой
  фит»). `Rules.Prereqs`'s own moduledoc now cites this exact build by name
  («Dan's opens Weapon Master on character level 14 with `Expertise` off
  armour and `Whirlwind attack` off a quarterstaff…»), so this fixture is what
  keeps that sentence honest across future edits — a regression here is a
  regression in the rule the sentence describes, not just in one number.

  # source: Dan, 14.08.2026, screenshot of an in-game level-up planner,
  # transcribed into a markdown ladder and handed to qa. `source.kind: user`
  # per CLAUDE.md's source ranking — no wiki page exists for a player's own
  # character, and «игрок наблюдал в игре» outranks every wiki page anyway.
  # Cross-referenced: `GAME_CHECKS.md` §H7, `Rules.Prereqs` moduledoc.

  ## What is reconstructed, and what is observed

  The screenshot gives the class ladder, four ability-score checkpoints
  (STR/CON/INT/CHA, at the levels they change), the skill totals at the
  levels they were raised, and every feat pick. It does **not** give race,
  alignment, DEX, WIS, or a starting point-buy split — a character sheet at
  level 40 does not print those separately from the levelled-up totals. So
  three things below are *our* reconstruction, not Dan's, and are marked as
  such rather than presented as observed:

    * **race half_elf, alignment chaotic_neutral** — chosen, not given.
      Half-elf carries no `ability_modifiers` and no bonus feat at level 1
      (`vanilla/races.json`), which is what lets `base_abilities` below equal
      the "after race" scores Dan's checkpoints imply without also guessing a
      race's modifiers on top of them — any other zero-modifier race would
      read identically to the model. Chaotic neutral is the cheapest
      alignment that clears both alignment-gated classes in this ladder
      (Bard forbids lawful, Pale Master forbids good); nothing in the
      screenshot narrows it further.
    * **DEX 13, WIS 8** — DEX 13 is the floor every combat feat in the ladder
      needs (Weapon Master's own requirements text: "Getting these feats
      requires dexterity and intelligence scores of at least 13"), and
      neither dexterity nor wisdom is ever shown changing, so 13 is the
      minimal honest floor rather than a guess at a higher number. WIS 8 is
      an unconstrained dump stat.

  What is **not** a guess: `base_abilities: %{str: 14, con: 16, int: 14}`
  (cha 11) is pinned down by the checkpoints themselves, not chosen for
  convenience — see `reconstructed ability checkpoints match the screenshot`
  below, which replays all sixteen of Dan's own numbers against
  `Abilities.scores_at/3` and Red Dragon Disciple's "Dragon abilities" table
  (`vanilla/feat_ability_bonuses.json`) and finds only one four-number
  starting point that produces every one of them. Fifteen of the sixteen
  carry a non-zero `dragon_abilities` term (every one but level 4, before any
  RDD level is taken), and six of those fifteen are the exact level a new row
  of the table first takes effect — one for each of its five rows, with row
  10 landing on both STR and CHA at level 39 (checked directly against
  `AbilityBonuses.terms/3`, not inferred). More independent confirmation of
  that table than any single wiki fixture has exercised it with before
  (`wiki_builds_test.exs`'s «Бледный Призыватель» only reaches RDD's 2nd
  class level, i.e. row 2 alone).

  ## What this run does and does not claim

  Per the assignment: there is no character sheet to compare *totals*
  against, only the ladder — so, like `wiki_builds_test.exs`, every pinned
  number here is either arithmetic written out in a comment or the direct
  output of `Rules.compute/2`, never a value copied from a run and left
  unexplained. Where a number has no independent source to check it against
  (skill points earned, the attack/save breakdowns), that is said plainly
  rather than dressed up as confirmed.

  ⚠ Here stood «HP is `nil` — Red Dragon Disciple carries no formalised hit
  die … pinned as `nil`, not patched over with a plausible number». True until
  16.08.2026, when task 3.37 read the growing die off the class page and Dan's
  own measurement (`GAME_CHECKS.md` G2) confirmed the shard did not touch the
  scale. HP is a number now, written out term by term beside it like every
  other, and it is **575** on Siala against **515** on vanilla — the sixty
  between them are the shard's free `Toughness` and «Дух Сиалы», neither of
  which is about the hit die at all.

  ## Slot placement is QA's own reading, not a parser's

  There is no `WikiBuildPage.feat_plan/2` for a hand-built ladder, so which
  slot each feat went into (`general`, or `{:class_bonus, class}`) is worked
  out by hand from `FeatSlots`/`bonus_for` and asserted directly — see
  `every feat lands in the slot Dan's screenshot implies` below, which checks
  the *whole* accounting (every slot the ladder offers is filled, every fill
  has a slot) rather than trusting the placement silently.

  ## Two things this fixture finds and does not paper over

  * **Level 39's screenshot carries two feats marked with Dan's own `?`**
    ("//Blind-fight?, //Epic spell warding") beside the one he committed to
    (`Called shot`). Only the committed one is in `@builds`; the two question
    marks are left out rather than guessed at, per the assignment.
  * ✅ **Two picks used to fail their own prerequisites, and the model was
    wrong, not the build** (closed 15.08.2026, task 3.31). `Epic spell:
    hellball` (Pale Master 16) and `Epic spell: epic mage armor` (Pale
    Master 19) were refused by "the ability to cast 9th level spells" —
    this build's only caster is a Bard, whose table tops out at circle 6
    however far Pale Master's advancement pushes it. Handing the finding
    back rather than bending the build is exactly what closed it: the
    question reached Dan, Dan measured it (Бард 10 / ПМ 15 — the game
    offers `Epic spell: mummy dust`), and the six pages turned out to say
    in as many words that the field the parser read is not the real
    prerequisite. Both picks are legal now, on the rule the pages state:
    the level is a Pale Master one and Pale Master is past 15.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Abilities, Build, FeatSlots, Gear, Skills}

  # ── the build itself ────────────────────────────────────────────────────
  #
  # A list of one today, shaped like `wiki_builds_test.exs`'s `@builds` on
  # purpose: the day Dan sends a second screenshot, it is a second entry here
  # and not a new file.
  @builds [
    %{
      title:
        "Dan: Бард 4 / Бледный мастер 19 / Ученик красного дракона 10 / " <>
          "Мастер оружия 7 — Expertise и Whirlwind attack с вещей открывают ВМ",
      race: :half_elf,
      alignment: :chaotic_neutral,
      base_abilities: %{str: 14, dex: 13, con: 16, int: 14, wis: 8, cha: 11},
      levels:
        List.duplicate(:bard, 3) ++
          List.duplicate(:pale_master, 2) ++
          List.duplicate(:red_dragon_disciple, 8) ++
          List.duplicate(:weapon_master, 7) ++
          [:red_dragon_disciple] ++
          List.duplicate(:pale_master, 17) ++
          [:red_dragon_disciple] ++
          [:bard],
      # The +1 every fourth level. Dan's screenshot names STR at every one of
      # these except 36 and 40, where the stated total only reconciles if the
      # increase went to CON instead (see the ability-checkpoint table below).
      ability_increases: %{
        4 => :str,
        8 => :str,
        12 => :str,
        16 => :str,
        20 => :str,
        24 => :str,
        28 => :str,
        32 => :str,
        36 => :con,
        40 => :con
      },
      # Every slot Dan's ladder fills, keyed by character level. `general`
      # covers both the ordinary and the epic-general slot — which one a
      # level offers is `FeatSlots.at/3`'s question, not this map's; see
      # `every feat lands in the slot Dan's screenshot implies`.
      #
      # "Владение древковым" = `siala_polearm_proficiency` (спасибо
      # `weapons.json`: `spear.proficiency == {:feat, :siala_polearm_proficiency}`
      # — this is literally the spear-proficiency feat, which is why it is
      # taken first, before anything else touches a spear).
      # "Greater fortitude" on the screenshot is `great_fortitude` — NWN has
      # no feat named "Greater Fortitude"; read as the in-client label for
      # the ordinary "Great Fortitude".
      # "Epic energy resistance (electric)" — the ruleset's `energy_type`
      # dictionary spells it `:electrical` (fire/acid/cold/electrical/sonic).
      feats: %{
        1 => %{general: :siala_polearm_proficiency},
        3 => %{general: {:weapon_focus, :spear}},
        6 => %{general: :dodge},
        9 => %{general: :mobility},
        12 => %{general: :spring_attack},
        14 => %{{:class_bonus, :weapon_master} => {:weapon_of_choice, :spear}},
        15 => %{general: :expertise},
        18 => %{general: :whirlwind_attack},
        21 => %{general: :epic_fortitude},
        24 => %{general: {:epic_weapon_focus, :spear}},
        27 => %{general: :armor_proficiency_heavy},
        30 => %{general: :great_fortitude},
        32 => %{{:class_bonus, :pale_master} => {:epic_energy_resistance, :electrical}},
        33 => %{general: :armor_skin},
        35 => %{{:class_bonus, :pale_master} => :epic_spell_hellball},
        36 => %{general: :epic_prowess},
        38 => %{{:class_bonus, :pale_master} => :epic_spell_epic_mage_armor},
        39 => %{general: :called_shot}
      },
      # Dan's screenshot gives running totals ("Discipline - 15", later
      # "Discipline - 40"), not per-level purchases; each entry here is the
      # total minus whatever was already bought — e.g. heal_skill 5 at level
      # 33 is +4 on top of the 1 bought at level 18.
      skills: %{
        3 => %{use_magic_device: 1},
        5 => %{lore: 8},
        12 => %{intimidate: 4},
        14 => %{discipline: 15},
        18 => %{heal_skill: 1},
        26 => %{spellcraft: 27},
        33 => %{heal_skill: 4},
        35 => %{spellcraft: 5},
        38 => %{spellcraft: 2},
        40 => %{discipline: 25}
      },
      # The three items the screenshot marks with `//`: armour lending
      # Expertise, a quarterstaff lending Whirlwind attack, an amulet
      # lending Improved Critical (spear) — the last is never picked in a
      # slot anywhere in the ladder, only worn.
      gear_feats: [:expertise, :whirlwind_attack, :improved_critical],
      # Every ability-score checkpoint the screenshot names, in the order it
      # names them — some from the "стат" column (the four-level increases),
      # some from the "примечание" column (Red Dragon Disciple's own
      # "Dragon abilities" table, `vanilla/feat_ability_bonuses.json`:
      # class level 2 → STR+2, 4 → STR+2, 7 → CON+2, 9 → INT+2,
      # 10 → STR+4/CHA+2). Both kinds are checked the same way: what
      # `Abilities.scores_at/3` says at that character level.
      ability_checkpoints: [
        {4, :str, 15},
        {7, :str, 17},
        {8, :str, 18},
        {9, :str, 20},
        {12, :str, 21},
        {12, :con, 18},
        {16, :str, 22},
        {20, :str, 23},
        {21, :int, 16},
        {24, :str, 24},
        {28, :str, 25},
        {32, :str, 26},
        {36, :con, 19},
        {39, :str, 30},
        {39, :cha, 13},
        {40, :con, 20}
      ],
      expect: %{
        # first 20 character levels only (CLAUDE.md §3): bard counts 3 of
        # its 4 levels (the 4th is char 40, past the window), pale master 2
        # of 19, red dragon disciple 8 of 10, weapon master all 7 of 7.
        #   bard:    medium, 3 levels  → floor(3*3/4)  = 2
        #   pale m.: low,    2 levels  → floor(2*1/2)  = 1
        #   RDD:     medium, 8 levels  → floor(8*3/4)  = 6
        #   WM:      high,   7 levels  → floor(7*1/1)  = 7
        # sum 16 (== base_attack_at_20), +10 from the epic term (odd levels
        # 21..39, ten of them) = 26.
        base_attack: 26,
        base_attack_at_20: 16,
        epic_attack: 10,
        # good save = 2 + floor(levels/2); poor = floor(levels/3), off the
        # same counted-level windows as base_attack above.
        #   bard    (fort poor, ref good, will good), 3: fort 1, ref 3, will 3
        #   pale m. (fort good, ref poor, will good), 2: fort 3, ref 0, will 3
        #   RDD     (fort good, ref poor, will good), 8: fort 6, ref 2, will 6
        #   WM      (fort poor, ref good, will poor), 7: fort 2, ref 5, will 2
        # sum fort 12 / ref 10 / will 14, +10 epic (even levels 22..40) each
        # = fort 22 / ref 20 / will 24.
        base_saves: %{fort: 22, ref: 20, will: 24},
        base_saves_by_class: %{
          bard: %{levels: 3, fort: 1, ref: 3, will: 3},
          pale_master: %{levels: 2, fort: 3, ref: 0, will: 3},
          red_dragon_disciple: %{levels: 8, fort: 6, ref: 2, will: 6},
          weapon_master: %{levels: 7, fort: 2, ref: 5, will: 2}
        },
        # base_attack_at_20 == 16, which the vanilla attack table buys
        # exactly 4 attacks (thresholds 1/6/11/16); never revisited by the
        # epic bonus (CLAUDE.md §3).
        attacks_per_round: 4,
        # ⚠️ Здесь стояло `hp: nil` — у Ученика красного дракона не было
        # хит-дайса, и HP всего билда ядро не считало вовсе. Задача 3.37
        # (замер Dan, `GAME_CHECKS.md` G2) прочитала шкалу, и число появилось:
        #   бард          4 × d6                        =  24
        #   Бледный мастер 19 × d6                      = 114
        #   РДД           10: 6+6+6 8+8 10+10+10+10+10  =  84
        #   Мастер оружия  7 × d10                      =  70
        #   CON 20 (мод +5) × 40 уровней                = 200
        #   Toughness (Мастер оружия выдаёт даром) × 40 =  40
        #   Deathless vigor (ступени Бледного мастера)  =  23
        #   «Дух Сиалы»                                 =  20
        #                                        итого  = 575
        hp: 575,
        # ⚠️ Под ванилью то же самое МИНУС ДВЕ строки, и обе — сиальские
        # выдачи, а не хит-дайс: бесплатный `Toughness` Мастера оружия (−40)
        # и «Дух Сиалы» (−20). Кости и телосложение совпадают до единицы, что
        # и утверждает комментарий у ванильного прогона ниже: шкала хит-дайса
        # прочитана в ВАНИЛЬНОМ слое, и шард её не трогал.
        vanilla_hp: 515,
        # earned = 4×(class + INT mod) on level 1, then (class + INT mod) a
        # level. INT mod is +2 (score 14) through level 20, and +3 (score
        # 16, RDD's own 9th class level lands the +2 to INT exactly on
        # character level 21) from level 21 on:
        #   level 1:            (4 + 2) × 4                     = 24
        #   levels 2–3   (bard, 4+2):    2 × 6                  = 12
        #   levels 4–5   (PM,   2+2):    2 × 4                  =  8
        #   levels 6–13  (RDD,  2+2):    8 × 4                  = 32
        #   levels 14–20 (WM,   2+2):    7 × 4                  = 28
        #   level 21     (RDD,  2+3):                           =  5
        #   levels 22–38 (PM,   2+3):   17 × 5                  = 85
        #   level 39     (RDD,  2+3):                           =  5
        #   level 40     (bard, 4+3):                           =  7
        #                                            total      = 206
        skill_points_earned: 206,
        # 1 point a rank on a class skill of the level's own class, 2 on a
        # cross-class one (CLAUDE.md §6). Every purchase here lands on a
        # level whose class carries the skill as its own — discipline
        # (bard/RDD/WM), lore/spellcraft/heal_skill (pale master and/or
        # whichever class the level belongs to), use_magic_device (bard) —
        # except intimidate at level 12 (a Red Dragon Disciple level;
        # intimidate is not in RDD's class-skill list):
        #   umd 1 (classed)        →  1
        #   lore 8 (classed)       →  8
        #   intimidate 4 (X-class) →  8
        #   discipline 15 (classed)→ 15
        #   heal 1 (classed)       →  1
        #   spellcraft 27 (classed)→ 27
        #   heal +4 (classed)      →  4
        #   spellcraft +5 (classed)→  5
        #   spellcraft +2 (classed)→  2
        #   discipline +25(classed)→ 25
        #                   total  → 96
        plan_cost: 96,
        skill_points: %{earned: 206, spent: 96, free: 110},
        # Weapon Finesse never taken; attack stays on strength.
        attack_ability: :str,
        # base_attack(26) + naked STR mod(+10, score 30) + attack_extra(7).
        # 🔴 43 → 37 (15.08.2026, замер Dan `GAME_CHECKS.md` Q1/Q4): расовый
        # бонус включается ОРУЖИЕМ В РУКАХ, а этот билд оружия не объявляет —
        # значит и бонуса у него нет. Ровно то, что показывает игра: голый
        # светлый эльф-сагровик 40 имеет AB 29, а не 38.
        attack_bonus: 37,
        own_attack_bonus: 1,
        own_attack_terms: [
          %{id: :epic_prowess, source: {:feat, :epic_prowess}, bonus: 1, under_cap?: false}
        ],
        # 🔴 half-elf's racial attack bonus: `base` variant would be +6 (not a
        # Sagra warrior — see `class_groups` below) and the level is right, but
        # since 15.08.2026 the bonus also needs **a weapon in hand** (Dan's
        # measurement, `GAME_CHECKS.md` Q1/Q4) and this build declares none.
        # ⚠ Put the weapon in and the whole caveat changes shape, not just the
        # number: `variant` comes back and the sentence stops being «возьми
        # оружие». That is why it is `0` here rather than absent.
        race_attack_bonus: 0,
        gear_attack_bonus: 0,
        weapon_attack_bonus: 0,
        # fort/ref/will = base + governing modifier + save_bonus.
        #   fort: 22 + CON mod(+5, score 20) + 12 = 39
        #   ref:  20 + DEX mod(+1, score 13) +  6 = 27
        #   will: 24 + WIS mod(-1, score  8) +  6 = 29
        fort: 39,
        ref: 27,
        will: 29,
        # save_bonus is Spellcraft's +1-per-5-ranks (34 ranks → +6, applies
        # to all three) plus the build's own terms (Great/Epic Fortitude,
        # fort only): fort 6+6=12, ref 6+0=6, will 6+0=6.
        save_bonus: %{fort: 12, ref: 6, will: 6},
        skill_save_bonus: 6,
        # ⚠ `counts_for_prereqs?` — второй признак записи рядом со стороной капа
        # (задача S3, 17.08.2026): идёт ли прибавка в число, с которым
        # сравнивается требование фита по сейву. Здесь у обеих `true`, и это
        # содержательный контроль, а не шум: исключён источником ровно один
        # `Luck of heroes`, и если признак однажды поедет на соседние записи,
        # первым это увидит референсный билд.
        own_save_terms: [
          %{
            id: :great_fortitude,
            source: {:feat, :great_fortitude},
            save: :fort,
            bonus: 2,
            under_cap?: false,
            counts_for_prereqs?: true
          },
          %{
            id: :epic_fortitude,
            source: {:feat, :epic_fortitude},
            save: :fort,
            bonus: 4,
            under_cap?: false,
            counts_for_prereqs?: true
          }
        ],
        # No gear AC typed in (only gear *feats* were declared), and none of
        # the build's own AC terms read a modifier that differs between the
        # naked and the geared pass — so, unusually among these fixtures,
        # naked and geared coincide: base_ac(10, CLAUDE.md §3) + DEX mod(+1)
        # + own(16) = 27.
        ac_naked: 27,
        ac_geared: 27,
        # ⚠️ `vs_typed: :sum` у всех трёх — задача 3.91: собственная прибавка
        # складывается с числом, которое игрок вписал под тем же типом. Этот
        # билд вписанного AC не несёт вовсе, поэтому поле здесь ничего не
        # двигает; фикстура называет его, чтобы правка правила была видна
        # диффом и на референсном билде тоже.
        ac_own_terms: [
          %{ac: 10, id: :bone_skin, type: nil, source: {:feat, :bone_skin}, vs_typed: :sum},
          %{
            ac: 4,
            id: :draconic_armor,
            type: :natural,
            source: {:feat, :draconic_armor},
            vs_typed: :sum
          },
          %{ac: 2, id: :armor_skin, type: :natural, source: {:feat, :armor_skin}, vs_typed: :sum}
        ],
        # Not a Sagra or an Adra warrior: the ladder mixes Bard/Pale
        # Master/Red Dragon Disciple in with Weapon Master, and both groups
        # require every class in the build to be one of theirs.
        class_groups: [],
        racial_bonus: %{
          kind: :attack_bonus,
          race: :half_elf,
          skill: nil,
          cap: :attack_bonus,
          ac_type: nil,
          variants: %{
            base: 6,
            racial_weapon: 12,
            racial_weapon_and_sagra_warrior: 18,
            sagra_warrior: 9
          },
          stated_for_level: 40,
          counted: nil,
          modelled?: true,
          variant: nil,
          inactive?: true
        },
        # ⚠️ ЗДЕСЬ БЫЛИ ДВА ОТКАЗА, И ОНИ БЫЛИ НАШИ — сняты задачей 3.31
        # (15.08.2026). `Epic spell: hellball` (ПМ 16) и `Epic spell: epic
        # mage armor` (ПМ 19) отбивались требованием «the ability to cast
        # 9th level spells»: единственный кастер билда — Бард, чья таблица
        # кончается 6-м кругом, сколько бы Бледный мастер её ни продвигал.
        # Spellcraft при этом сходился оба раза (32/32 и 34/26), то есть
        # спотыкалось ровно одно требование — этим билд и был ценен,
        # он изолировал `casts_spell_level`.
        #
        # Оказалось, что требования такого нет: страница каждого из шести
        # эпических заклинаний сама говорит, что поле `prereq=` неверно
        # («The actual prerequisite is NOT the ability to cast level 9
        # spells, but … having at least 15 pale master levels»), а замер
        # Dan 15.08.2026 (Бард 10 / ПМ 15 — заклинание предлагается)
        # подтвердил прозу. Оба уровня здесь — уровни Бледного мастера,
        # и на них ПМ уже 16 и 19, то есть выбор законный.
        #
        # ⚠️ Пустой список тут — не «проверять стало нечего»: тот же прогон
        # держит остальные 17 пиков лестницы, и он же ловит обратную
        # ошибку. Разошлись фикстуры по-разному: у «Бледного Призывателя»
        # (`wiki_builds_test.exs`) те же пять заклинаний остались
        # отбитыми — по Spellcraft, и это настоящая причина.
        prerequisites_unmet: [],
        # `Enum.sort/1`, the same convention `wiki_builds_test.exs` uses:
        # `compute/2`'s own gap order is an implementation detail, what is
        # pinned is *which* gaps this build carries.
        gaps:
          Enum.sort([
            # ⚠️ ЗДЕСЬ БЫЛИ ДВЕ ОГОВОРКИ ПРО ХИТ-ДАЙС, И ОБЕ БЫЛИ ПРАВДОЙ:
            # `{:missing_data, {:hit_die, :red_dragon_disciple}}` (базы нет
            # вовсе) и `{:not_modelled, {:feat_hp_bonus, :hit_die_increase}}`
            # (фит, который её растит, не посчитан). Сняты задачей 3.37 —
            # шкала прочитана со страницы класса, а запись фита в разметке
            # стала `counted_elsewhere`: считает класс, а не фит. Обе оговорки
            # обязаны были уйти ВМЕСТЕ, поэтому и записаны здесь одной
            # заметкой: оставить вторую значило бы сказать «HP посчитано,
            # но растущий дайс мы не учли» — про то, из чего оно и посчитано.
            # `nil`, а не `:base`: вариант известен, а бонуса нет — оружия
            # в руках у фикстуры не объявлено (замер Dan 15.08.2026).
            {:assumed, {:racial_bonus_variant, :half_elf, nil}},
            # Spellcraft's Siala rewrite (+1/5 ranks to saves) is applied
            # flat; the AOE exception the shard's page states is not.
            {:not_modelled, {:save_bonus_scope, :spellcraft}},
            # ⚠️ ЗДЕСЬ БЫЛИ ДВЕ ОГОВОРКИ ПРО НЕЯСНУЮ ВЕЛИЧИНУ Мастера оружия
            # ("+AB every 3 class levels past the 10th") — ушли 17.08.2026
            # (задача про Мастера оружия), не потому что этот билд перестал
            # брать класс, а потому что величина ПЕРЕСТАЛА быть неясной: замер
            # Dan показал, что это ванильная колонка `feat_attack_bonuses.json`
            # (Superior/Epic superior weapon focus), уже посчитанная ядром —
            # ровно тот же терм, что и на «Гном Защитник»/«Мастер оружия
            # Сагровик» ниже. Обе записи слиты в одну с получателем
            # `counted_elsewhere`, поэтому обе строки исчезли вместе.
            # ⚠️ ЗАДАЧА 3.99 ЗАМЕНИЛА ЗДЕСЬ ОДНУ СТРОКУ И УБРАЛА ДВЕ, и все три
            # правки — одного вида: оговорка стала ПРОВЕРКОЙ.
            #
            # Было: `{:class_qualifier, :weapon_master, "in a melee weapon"}` —
            # стало требованием `feat_choice_properties` (свойство `ranged`
            # записи справочника). Оставалось второе исключение той же страницы,
            # названное ИМЕНЕМ ОДНОГО ПРЕДМЕТА, а не свойством: «unarmed strike
            # is excluded from the prerequisites».
            #
            # 🔴 ЗАДАЧА 3.107 УБРАЛА И ЕГО, ТЕМ ЖЕ ХОДОМ: имя записано именем
            # (`feat_choice_excludes`, перечисление — потому что перечисляет
            # источник), и оговорка ушла вместе с правилом. Замер Dan 26.08.2026
            # (кейс AC1) показал, что она прикрывала ложную ЛЕГАЛЬНОСТЬ:
            # `Weapon Focus (Unarmed strike)` открывал Мастера оружия, которого
            # в игре в списке нет.
            #
            # ⚠️ 🔴 И РОВНО ЭТОТ БИЛД — ЖИВОЙ ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ К ОБЕИМ
            # ПРАВКАМ: `Weapon Focus` у него объявлен С ВЕЩИ, класс это
            # требование выполняет (замер H7), а с задачи 3.97 объявление несёт
            # ЗНАЧЕНИЕ. Значит и свойство, и исключение проверяются по гировому
            # маршруту — и билд остаётся легальным (`illegal_class_levels/2`
            # → `[]` ниже), потому что объявлен у него не рукопашный удар.
            #
            # Ушли ещё в 3.99: `{:feat_qualifier, :epic_weapon_focus, "with the
            # chosen weapon"}` — на Сиале фит повторяем, то есть `same_choice_as`
            # его выбор СРАВНИВАЕТ, и печатать «не проверяем» рядом с работающей
            # проверкой было ложной неопределённостью наоборот; и
            # `{:feat_qualifier, :weapon_focus, "proficiency with the chosen
            # weapon"}` — владение выбранным оружием теперь требование
            # (`proficiency_with_chosen_weapon`).
            # ⚠️ ЗДЕСЬ СТОЯЛА оговорка `{:not_modelled, {:gear_feat_choice,
            # :improved_critical}}` — «фит объявлен с вещи, а какое оружие он
            # называет, объявление не говорит». 🔴 Снята задачей 3.98
            # (25.08.2026), и снята ТЕМ ЖЕ решением, что и её близнец абзацем
            # ниже: домен у фита — оружие, а оружие двигает у него КРИТ-ДИАПАЗОН,
            # механику, которой калькулятор не отвечает вовсе. Значит не назвав
            # оружие, игрок не потерял ни одного нашего числа, и признаваться
            # было не в чем.
            #
            # 🔴 ИМЕННО ЭТОТ БИЛД И БЫЛ ЖИВЫМ ДОКАЗАТЕЛЬСТВОМ РАСХОЖДЕНИЯ:
            # он нёс ОДНУ из двух строк про один и тот же объявленный фит:
            # 3.93 научила спрашивать получателя слотовый маршрут
            # (`FeatChoices.gaps/3`) и не тронула вещевой (`GearFeats.gaps/2`).
            # Между двумя правками — один день, то есть приватной копии чтения
            # хватило одного захода, чтобы разойтись.
            # Один фит, одно незнание, две позиции проекта на одном экране.
            # Число не сдвинулось ни на единицу — сдвинулось признание.
            # ⚠️ И вторая, отдельная оговорка про тот же объявленный фит,
            # появилась 14.08.2026: крит-диапазон не считает ни один файл
            # разметки, то есть «прибавку в статы не считаем» — ровно то, что
            # сказал бы `Improved critical`, взятый слотом. До той правки
            # `FeatChoices.gaps/3` ходила по одним слотам, и объявление молчало
            # про эффект, который у него как раз СЧИТАЕТСЯ, если посчитан
            # (Dan, 09.08.2026) — то есть молчание читалось как «посчитали».
            # Это первая живая строка, которую та правка добавила на реальном
            # билде.
            # 🔴 Снято задачей 3.93 (25.08.2026): `improved_critical` — крит-диапазон,
            # механика, которой калькулятор не отвечает вовсе. НЕ «прибавку научились
            # считать»: число не сдвинулось ни на единицу. Разбор — в moduledoc
            # `WikiBuildsTest`, где той же правкой снято семнадцать строк.
            # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
            # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
            #   hardiness_vs_enchantments(save_bonus)
            # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
            # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
            # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
            # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
            # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
            # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
            # 🔴 ЧЕТЫРЕ СТРОКИ СНЯТЫ 17.08.2026 — здесь и ниже, в блоке AC:
            # `{:attack_bonus, :expertise}`, `{:attack_bonus, :called_shot}`,
            # `{:ac_bonus, :expertise}` и `{:ac_bonus,
            # :epic_spell_epic_mage_armor}`. Боевой режим, спецатака и
            # заклинание — «включается и кончается», получатель `buff`.
            #
            # ⚠️ Этот билд Dan — единственная фикстура, где фит приходит
            # С ВЕЩИ (`Expertise` объявлен под «Вещами» и открывает Мастера
            # оружия), и правка эту половину НЕ трогает: фит по-прежнему
            # считается владением, требования класса им по-прежнему
            # выполняются, `declared`/`slots` не сдвинулись. Ушла ровно
            # оговорка про прибавку, которой мы всё равно не отвечаем.
            # ⚠️ И третье следствие того же пустого поля, добавлено задачей
            # 3.34 (15.08.2026): с этого дня оружие решает не только прибавки
            # ниже, но и саму ХАРАКТЕРИСТИКУ броска (дальняя атака идёт от
            # ловкости, замер N1). Билд оружия не назвал, поэтому посчитан
            # ближний бой, и это сказано вслух. Здесь разрыв крупный и
            # в сторону ЗАВЫШЕНИЯ: STR 22 (+6) против DEX 13 (+1), то есть
            # с луком в руках наше AB было бы на 5 меньше показанного.
            {:not_modelled, {:attack_ability_default, :ranged}},
            # No weapon is set under «Вещи» (`gear.weapon`), only the three
            # declared feats — so neither Weapon Focus's own bonus nor
            # Weapon Master's "AB bonus" column can be told which weapon
            # they would apply to.
            {:not_modelled, {:attack_bonus_weapon, :weapon_focus}},
            {:not_modelled, {:attack_bonus_weapon, :epic_weapon_focus}},
            {:not_modelled, {:attack_bonus_weapon, :weapon_master}}
            # 🔴 `Dodge` и `Mobility` ОСТАЛИСЬ рядом со снятым `Expertise` —
            # те же требования Мастера оружия, тот же файл, тот же вердикт
            # `not_modelled`, и разошлись они только механикой: эти двое
            # пассивны (`affects: ["ac"]`), а Expertise включается.
            # ⚠️ ЗДЕСЬ СТОЯЛИ оговорки об УСЛОВНЫХ прибавках — сняты задачей 3.95
            # (25.08.2026) решением владельца (`not_a_gap`, довод `feat_description`):
            #   dodge(ac_bonus), mobility(ac_bonus)
            # Прибавка реальная и в число по-прежнему НЕ идёт (вердикт `not_modelled`
            # на месте, числа не сдвинулись ни на единицу) — изменилось только то,
            # признаёмся ли мы в этом второй раз. Первый раз это говорит ОПИСАНИЕ фита,
            # и точнее нас: «+2 racial bonus on saving throws vs. poison» против нашего
            # «не всегда и не против всего». Описание видно в конструкторе (3.87) и на
            # экране просмотра билда (3.94), то есть в одном движении мыши от имени фита.
            # ⚠️ Здесь стояла `{:not_modelled, {:ac_bonus,
            # :epic_spell_epic_mage_armor}}` с доводом «оговорки пика
            # печатаются независимо от того, выполнены ли его собственные
            # требования (CLAUDE.md §9 — отказать молча было бы ложью
            # в другую сторону)». Довод не отменён и продолжает работать —
            # просто у этого пика больше нет оговорки, которую стоило бы
            # печатать: заклинание есть заклинание, то есть бафф.
            #
            # ⚠️ И следом стояло `{:assumed, :ac_bonus_types_unstated}` — снято
            # задачей 3.90 (25.08.2026). У этого билда прибавка без типа ровно
            # одна, `Bone skin` (+12 за 19 уровней Бледного мастера), и её
            # складывание с прибавками типа natural — а их у билда две,
            # `Draconic armor` и `Armor skin` — подтверждено владельцем.
            # ⚠️ Тип `Bone skin` («innate») по-прежнему не назван, поле `type`
            # осталось `null`: подтверждено складывание, а не тип. Числа AC
            # не сдвинулись ни на единицу.
            # ⚠️ Здесь стояла `{:not_modelled, :ac_same_type_stacking}`:
            # `Draconic armor` и `Armor skin` оба `type: natural` — единственное
            # столкновение СОБСТВЕННЫХ прибавок во всём корпусе, и мы их
            # складывали, честно говоря, что игра, возможно, не складывает.
            # E5 замерен Dan 16.08.2026: **складываются**, +2 ровно. Значит
            # оговорка ушла не переименованием, а потому что вопроса больше нет
            # (задача 3.39). Числа билда при этом не сдвинулись ни на единицу —
            # он не вводит AC с вещей вовсе, а вписанное с вещей и есть
            # единственное, что теперь конкурирует.
            # 🔴 Снято задачей 3.93 (25.08.2026): `epic_energy_resistance` — сопротивление
            # урону, механика, которой калькулятор не отвечает вовсе. Разбор — в moduledoc
            # `WikiBuildsTest`.
            # ⚠️ Здесь стояла `{:not_modelled, {:feat_bonus, :weapon_of_choice}}`
            # — появилась 14.08.2026 (M2b сделал фит слотовым пиком, а оговорки
            # идут по взятым фитам) и снята в тот же день решением Dan: фит
            # числа не даёт вовсе, он НАЗНАЧАЕТ оружие колонке Мастера оружия,
            # и весь его эффект посчитан ею. В разметке атаки запись фита теперь
            # `counted_elsewhere` → `weapon_master`, и ядро это читает.
            # ⚠️ `{:not_modelled, {:attack_bonus_weapon, :weapon_master}}` выше
            # при этом ОСТАЁТСЯ и остаётся верной: фит взят, выбор записан
            # (`:spear`), а оружия в руках нет — считать колонку не по чему.
            #
            # ⚠️ Восемь строк `skill_change` (`heal_skill`, `intimidate`,
            # `lore` ×3, `use_magic_device` ×2) стояли здесь до задачи "навыки:
            # получатели у фактов" (data-miner, 14.08.2026) — этот билд качает
            # все четыре навыка (Bard/Pale Master/RDD/Weapon Master), и до
            # разметки `shard_skill_gaps/2` печатал про них ВСЁ неприменённое
            # без разбора. Все восемь оказались про крафт зелий и предметов,
            # про баф Ярости и про порог чтения свитков — механики, которых
            # калькулятор не считает вовсе, — и ушли той же арифметикой, что
            # 3.28 когда-то убрала их класс-версии. `appeared: []` в диффе
            # теста и есть подтверждение: разметка НИЧЕГО не добавила этому
            # билду, только вычистила шум.
          ])
      }
    }
  ]

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp to_build(entry, ruleset_version \\ "siala_41") do
    %Build{} =
      Build.new(
        ruleset_version: ruleset_version,
        race: entry.race,
        alignment: entry.alignment,
        base_abilities: entry.base_abilities,
        levels: entry.levels,
        ability_increases: entry.ability_increases,
        feats: entry.feats,
        skills: entry.skills,
        gear: Gear.new(feats: entry.gear_feats)
      )
  end

  defp save_terms_by_class(stats) do
    Map.new(stats.save_breakdown.by_class, fn term ->
      {term.class, Map.put(term.subtotals, :levels, term.levels_counted)}
    end)
  end

  for entry <- @builds do
    @entry entry

    describe entry.title do
      # ── reconstruction check ────────────────────────────────────────────

      test "reconstructed ability checkpoints match the screenshot exactly", %{
        ruleset: ruleset
      } do
        entry = @entry
        build = to_build(entry)

        mismatches =
          for {level, ability, expected} <- entry.ability_checkpoints,
              actual = Abilities.scores_at(build, ruleset, level)[ability],
              actual != expected,
              do: {level, ability, expected: expected, actual: actual}

        assert mismatches == [],
               """
               #{entry.title}: the reconstructed base_abilities/ability_increases do not
               reproduce Dan's own numbers. Every one of these sixteen checkpoints was
               chosen to be independently checkable, so a mismatch here means the
               starting scores (or the RDD "Dragon abilities" table) moved, not that a
               new number needs picking.
               #{inspect(mismatches, pretty: true)}
               """
      end

      # ── legality, end to end ────────────────────────────────────────────

      test "every level passes validate_level_up, appended one at a time", %{
        ruleset: ruleset
      } do
        entry = @entry
        build = to_build(entry)

        refused =
          for {class, level} <- Enum.with_index(build.levels, 1),
              before = Build.truncate(build, level - 1),
              {:error, reasons} <- [Rules.validate_level_up(before, class, ruleset)],
              do: {level, class, reasons}

        assert refused == []
      end

      # ⚠️ The second, independent entry into the same check
      # (`wiki_builds_test.exs`'s own lesson): appending one level at a time
      # cannot see a rule that reads the *whole* build, such as the
      # prestige pre-epic ceiling counting all of a class's levels against
      # a character level in the past. Replaying the finished ladder with
      # `%{class:, at:}` is what would have caught that bug here too.
      test "every level also passes validate_level_up replayed as a finished ladder", %{
        ruleset: ruleset
      } do
        entry = @entry
        build = to_build(entry)

        refused =
          for {class, level} <- Enum.with_index(build.levels, 1),
              {:error, reasons} <-
                [Rules.validate_level_up(build, %{class: class, at: level}, ruleset)],
              do: {level, class, reasons}

        assert refused == []
      end

      test "nothing about the finished build is illegal", %{ruleset: ruleset} do
        entry = @entry
        build = to_build(entry)

        assert Rules.illegal_class_levels(build, ruleset) == []
        assert Rules.illegal_gear_weapon(build, ruleset) == []
        assert Rules.illegal_gear_feats(build, ruleset) == []
      end

      # The one check `validate_level_up/3` does not do: whether a rank
      # bought at a level fits under that level's own ceiling
      # (`Skills.rank_cap/4` — CLAUDE.md §6, «потолок ограничивает покупку
      # НА УРОВНЕ»). Every entry here is the *cumulative* total after the
      # purchase, which is what the screenshot states and what the cap
      # bounds.
      test "no rank purchase exceeds the ceiling at the level it was bought", %{
        ruleset: ruleset
      } do
        entry = @entry
        build = to_build(entry)

        over =
          for {level, bought} <- entry.skills,
              {skill, _delta} <- bought,
              total = Build.skill_ranks(build, skill, level),
              cap = Skills.rank_cap(build, ruleset, skill, level),
              total > cap,
              do: {level, skill, total, cap}

        assert over == []
      end

      # ── the headline claim (GAME_CHECKS.md H7) ──────────────────────────

      test "Weapon Master needs the gear feats to open, not slot picks", %{ruleset: ruleset} do
        entry = @entry
        build = to_build(entry)
        # Every other requirement of Weapon Master (BAB 5, Intimidate 4,
        # Dodge/Mobility/Spring attack/Weapon focus, all slot-picked by
        # level 13) is already satisfied here — only Expertise and
        # Whirlwind attack come from gear, so this isolates exactly the
        # claim Dan's build illustrates.
        before_wm = Build.truncate(build, 13)
        without_gear = %Build{before_wm | gear: %Gear{}}

        assert Rules.validate_level_up(without_gear, :weapon_master, ruleset) ==
                 {:error, [requires_feat: :expertise, requires_feat: :whirlwind_attack]}

        assert Rules.validate_level_up(before_wm, :weapon_master, ruleset) == :ok
      end

      # ⚠ The other half Dan's own ladder illustrates: re-picking a feat the
      # build already owns from an item is legal (the item can be removed
      # without losing the feat) and buys nothing numerically, and the core
      # says so rather than staying silent (`Rules.feat_pick_caveats/3`,
      # CLAUDE.md §6 «фит с вещи не запрещает взять его же слотом»).
      # `Dodge` at level 6 is the negative control: an ordinary pick with no
      # gear-owned twin gets no such caveat.
      # ⚠ `slot:` is passed on purpose (`Rules.validate_feat_pick/3`'s own
      # doc): the build already holds this exact pick at that slot, and
      # without naming the slot the check would compare the pick against
      # itself and answer `{:error, [already_taken: …]}` — measured while
      # writing this fixture, not a hypothetical footgun.
      test "the re-picks at Weapon Master 2 and 5 are legal and buy nothing extra", %{
        ruleset: ruleset
      } do
        entry = @entry
        build = to_build(entry)

        assert Rules.validate_feat_pick(
                 build,
                 %{feat: :expertise, at: 15, slot: :general},
                 ruleset
               ) == :ok

        assert Rules.feat_pick_caveats(build, %{feat: :expertise, at: 15}, ruleset) ==
                 [{:owned_from_gear, :expertise}]

        assert Rules.validate_feat_pick(
                 build,
                 %{feat: :whirlwind_attack, at: 18, slot: :general},
                 ruleset
               ) == :ok

        assert Rules.feat_pick_caveats(build, %{feat: :whirlwind_attack, at: 18}, ruleset) ==
                 [{:owned_from_gear, :whirlwind_attack}]

        assert Rules.feat_pick_caveats(build, %{feat: :dodge, at: 6}, ruleset) == []
      end

      # ⚠ `dev-rules` is editing the neighbouring rule in parallel — a
      # feat's OWN `feats` prerequisite stops reading gear (H7's second
      # finding, "Improved expertise не появится в выборке доступных
      # фитов"). `Whirlwind attack` itself names `expertise` among its own
      # prerequisites (`feats: [dodge, mobility, expertise, spring_attack]`)
      # — the exact shape that edit touches. It has nothing to bite on here
      # only because, by the level `whirlwind_attack` is picked (18),
      # `expertise` is already a genuine SLOT pick (level 15) and not only a
      # gear declaration; this is what would notice if that stopped holding.
      test "whirlwind_attack's own dependency on expertise is a slot pick, not only gear", %{
        ruleset: ruleset
      } do
        entry = @entry
        build = to_build(entry)

        assert "expertise" in Map.get(ruleset.feats[:whirlwind_attack].prereqs, "feats", [])

        # Slots and class grants only, no gear — the same set `Prereqs`
        # reads for a FEAT's own `feats:` block since H7
        # (`Build.feats_permanent/3`, `requirement_of: :feat`).
        assert MapSet.member?(Build.feats_permanent(build, ruleset, 18), :expertise)
      end

      # ── feat slots, fully accounted ─────────────────────────────────────

      test "every feat lands in the slot Dan's screenshot implies", %{ruleset: ruleset} do
        entry = @entry
        build = to_build(entry)

        wrong =
          for {level, slots} <- entry.feats,
              {slot_id, pick} <- slots,
              feat_id = Build.feat_id(pick),
              offered = FeatSlots.at(build, ruleset, level),
              do: {level, slot_id, feat_id, offered}

        for {level, slot_id, feat_id, offered} <- wrong do
          matching = Enum.find(offered, &(&1.id == slot_id))

          assert matching, "level #{level}: no #{inspect(slot_id)} slot is offered at all"

          assert FeatSlots.accepts?(ruleset, matching, feat_id),
                 "level #{level}: #{inspect(slot_id)} refuses #{feat_id}"
        end

        # And the other way: no level offers a slot this build leaves
        # empty. `weapon_of_choice` at level 14 is a positive control on its
        # own — until task 3.26/M2b it was a class *grant* with no slot at
        # all, and would have vanished from this side of the check.
        offering =
          for level <- 1..40,
              slots = FeatSlots.at(build, ruleset, level),
              slots != [],
              do: level

        assert Enum.sort(offering) == Enum.sort(Map.keys(entry.feats))
      end

      # ⚠ Built with `Enum.flat_map/2` over `case`, not a `for` with
      # `choice = Build.feat_choice(pick)` as a filter clause — `for` treats
      # any non-generator clause as a boolean filter, and `feat_choice/1`
      # legitimately returns `nil` for every bare (no-parameter) pick, which
      # `for` reads as "skip this iteration" and not as "the choice is
      # `nil`". That silently dropped every bare feat from the sweep,
      # including both epic spells, and made this test pass by producing an
      # empty list on either side of a `== []` typo rather than by checking
      # anything — caught while writing this fixture, not a hypothetical.
      test "every pick of the ladder clears its own prerequisites", %{ruleset: ruleset} do
        entry = @entry
        build = to_build(entry)

        unmet =
          Enum.flat_map(Enum.sort(build.feats), fn {level, slots} ->
            Enum.flat_map(Enum.sort(slots), fn {slot_id, pick} ->
              feat_id = Build.feat_id(pick)
              choice = Build.feat_choice(pick)
              pick_ctx = %{feat: feat_id, at: level, choice: choice}

              case Rules.validate_feat(build, pick_ctx, ruleset) do
                :ok -> []
                {:error, reasons} -> [{level, slot_id, feat_id, reasons}]
              end
            end)
          end)

        assert unmet == entry.expect.prerequisites_unmet
      end

      # ── what the model computes ─────────────────────────────────────────

      test "attack, saves, attacks per round and HP", %{ruleset: ruleset} do
        entry = @entry
        stats = Rules.compute(to_build(entry), ruleset)

        assert stats.base_attack == entry.expect.base_attack
        assert stats.base_attack_at_20 == entry.expect.base_attack_at_20
        assert stats.epic_attack_bonus == entry.expect.epic_attack

        assert %{fort: stats.base_fort, ref: stats.base_ref, will: stats.base_will} ==
                 entry.expect.base_saves

        assert save_terms_by_class(stats) == entry.expect.base_saves_by_class
        assert stats.attacks_per_round == entry.expect.attacks_per_round
        assert stats.hp == entry.expect.hp

        # ⚠️ Здесь стояло `hp_breakdown == nil` — у РДД не было хит-дайса,
        # и разбор отказывал вместе с числом. Задача 3.37: и число, и разбор
        # на месте, а у РДД в разборе три дайса вместо одного — ровно те
        # ступени, которые эта лестница прошла.
        assert Enum.find(stats.hp_breakdown.by_class, &(&1.class == :red_dragon_disciple)) == %{
                 class: :red_dragon_disciple,
                 levels: 10,
                 hit_dice: [
                   %{die: 6, levels: 3},
                   %{die: 8, levels: 2},
                   %{die: 10, levels: 5}
                 ],
                 subtotal: 84
               }

        assert stats.attack_ability == entry.expect.attack_ability
        assert stats.attack_bonus == entry.expect.attack_bonus
        assert stats.own_attack_bonus == entry.expect.own_attack_bonus
        assert stats.own_attack_terms == entry.expect.own_attack_terms
        assert stats.race_attack_bonus == entry.expect.race_attack_bonus
        assert stats.gear_attack_bonus == entry.expect.gear_attack_bonus
        assert stats.weapon_attack_bonus == entry.expect.weapon_attack_bonus

        assert stats.fort == entry.expect.fort
        assert stats.ref == entry.expect.ref
        assert stats.will == entry.expect.will
        assert stats.save_bonus == entry.expect.save_bonus
        assert stats.skill_save_bonus == entry.expect.skill_save_bonus
        assert stats.own_save_terms == entry.expect.own_save_terms
      end

      test "AC, naked and geared", %{ruleset: ruleset} do
        entry = @entry
        stats = Rules.compute(to_build(entry), ruleset)

        assert stats.ac_naked == entry.expect.ac_naked
        assert stats.ac_geared == entry.expect.ac_geared
        assert stats.ac_own_terms == entry.expect.ac_own_terms
        assert stats.ac_own_terms_geared == entry.expect.ac_own_terms
        assert stats.ac_gear_bonus == 0
      end

      test "skill points earned, spent and free", %{ruleset: ruleset} do
        entry = @entry
        stats = Rules.compute(to_build(entry), ruleset)

        assert stats.skill_points == entry.expect.skill_points
      end

      test "not a Sagra or an Adra warrior, and the racial bonus stays at its base variant", %{
        ruleset: ruleset
      } do
        entry = @entry
        stats = Rules.compute(to_build(entry), ruleset)

        assert stats.class_groups == entry.expect.class_groups
        assert stats.racial_bonus == entry.expect.racial_bonus
      end

      # Sorted-set comparison, same convention as `wiki_builds_test.exs`:
      # `compute/2`'s own concatenation order is not part of the contract,
      # which caveats this build carries is.
      test "the build carries exactly the caveats we know about", %{ruleset: ruleset} do
        entry = @entry
        stats = Rules.compute(to_build(entry), ruleset)
        actual = Enum.sort(stats.gaps)

        assert actual == entry.expect.gaps,
               """
               #{entry.title}: the gap list moved.
                 appeared: #{inspect(actual -- entry.expect.gaps, pretty: true)}
                 gone:     #{inspect(entry.expect.gaps -- actual, pretty: true)}
               """
      end

      # ── vanilla, lightly ─────────────────────────────────────────────────
      #
      # ⚠ Deliberately not the full page-vs-vanilla machinery
      # `wiki_builds_test.exs` runs: none of this ladder's four classes carry
      # a Siala change to `bab_progression`, `saves`, `hit_die` or
      # `skill_points` (checked against `siala_41/classes.json`'s own
      # `changes` lists for all four, unlike Monk's full-BAB rewrite, which
      # is why that file needs the heavier machinery and this one does not).
      # Legality under vanilla is **not** compared: vanilla carries no
      # 4-class limit at all (`{:missing_data, :max_classes}` on every
      # level, since `ruleset.max_classes` is simply absent there) and does
      # not know `siala_polearm_proficiency`, so a level-by-level legality
      # diff would be reporting well-understood noise, not a finding.
      test "the numbers derived from class progression tables agree under vanilla", %{
        vanilla: vanilla
      } do
        entry = @entry
        build = to_build(entry, "vanilla")
        stats = Rules.compute(build, vanilla)

        assert stats.base_attack == entry.expect.base_attack
        assert save_terms_by_class(stats) == entry.expect.base_saves_by_class
        assert stats.attacks_per_round == entry.expect.attacks_per_round
        assert stats.skill_points.earned == entry.expect.skill_points.earned

        # ⚠️ У HP своё ванильное число, и разница ровно 60 — бесплатный
        # `Toughness` Мастера оружия (40) плюс «Дух Сиалы» (20). Обе выдачи
        # сиальские, ни одна не про хит-дайс, поэтому остальные три числа
        # выше по-прежнему сравниваются с общим ожиданием.
        assert stats.hp == entry.expect.vanilla_hp
        assert entry.expect.hp - entry.expect.vanilla_hp == 40 + 20
      end
    end
  end
end
