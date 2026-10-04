defmodule BuildCalculator.Base2da.SialaClassification do
  @moduledoc """
  Виды находок сверки Сиалы `mix hak2da.diff` (задача 4.49).

  ## Ранг источников Сиалы

      замер в игре (kind: user)  >  страница правил вики Сиалы  >  хак  >  Fandom

  🔴 **Хак — сильный источник гипотез, не арбитр:** шард выдаёт и выключает
  скриптами мимо таблиц (`priv/hak/README.md`, «таблица умеет молчать»).
  И хак говорит **за Сиалу** только там, где он отличается от базовой игры:
  строка, которую шард не трогал, — таблица движка, и спор с ней тот же, что
  у ванили (`docs/base2da_diff.md`).

  ## Виды

    * `:a` — **наши данные неверны**: против нас хак, вики Сиалы с ним
      согласна или молчит, замера нет. Это правка; находка, которая осталась
      в отчёте с этим видом, — неисправленная, и довод называет, почему
      (отдельная задача, нужен механизм ядра);
    * `:d` — **нужен замер**: хак спорит с вики Сиалы или с решением Dan
      без замера. Довод несёт сценарий кейса;
    * `:e` — **объяснено**: отличие объясняет вики Сиалы, замер (`kind: user`)
      или решение Dan — со ссылкой. Не ошибка;
    * `:c` — **таблица не решает**: правило в движке или на сервере шарда;
    * `:b` — **разница представления** или разница, которая **не доезжает**
      ни до одного печатаемого числа (довод называет, чем это проверено).

  ## Как ставится вид

  1. Правило Сиалы ниже — по ключу находки (`Finding.key/1`: точное совпадение
     или регулярное выражение) и, если правило их называет, по **значениям**
     находки (`base` — что говорит таблица, `ours` — что у нас). Значения
     прибиты нарочно: правило про «Mount actions MINSTR 99» не должно молча
     классифицировать то же поле, когда шард поменяет число.
  2. Вид, который поставило само сравнение по форме расхождения (ступени фита,
     фит только выдаётся) — остаётся.
  3. Находка, совпавшая с ванильной до буквы (ключ, `base`, `ours`), получает
     вид и довод ванильной сверки с пометкой «как у ванили»: хак строку
     не трогал, слой Сиалы число не переписал — спор тот же.
  4. Иначе — `nil`, и `mix hak2da.diff --check` падает: новую находку никто
     ещё не видел.
  """

  alias BuildCalculator.Base2da.Finding

  @inherited "Как у ванили (`docs/base2da_diff.md`): хак строку не трогал, слой Сиалы число не переписал. "

  # Правила по областям. `base` / `ours` — значения находки, к которым правило
  # прибито; `check` — имя предиката ниже, когда значение не одно (37 оружий
  # с одной и той же формой владения).
  @rules [
    # --------------------------------------------------------- classes
    %{
      key: "constants/MIN_LEVEL_FOR_MAX_HP/value",
      base: "3",
      ours: "every_level",
      kind: :e,
      note:
        "Хак строку не трогал (3, как у базы), а на Сиале HP за уровень — максимум кости ВСЕГДА: слово Dan 01.08.2026 (`siala_41/overrides.json` → character.hit_points_roll = always_max, `source.kind: user`). Замер выше таблицы; ванильное «решение показа» (4.20) Сиалу не касается."
    },

    # ------------------------------------------------------ class feats
    # ⚠ Задача 4.51 сняла здесь правило (a) — шесть находок
    # `class_feats/{bard,cleric,paladin,ranger,sorcerer,wizard}/bonus_feat_levels`:
    # строка 40 базовых `cls_bfeat_*` (уровень класса 41, Bonus 1) теперь лежит
    # в слое Сиалы — `siala_41/class_bonus_feat_levels.json`, статус `assumed`,
    # решение Dan `BC1`. Правило снято вместе с находками; что сверка
    # расхождение видит, держит порча `class_feats/bard/bonus_feat_levels`
    # в `hak2da_positive_control_test.exs`.
    %{
      key: "class_feats/weapon_proficiency_simple/granted_first",
      base: "—",
      ours: "уровень 1",
      kind: :e,
      note:
        "Хак выдачу Weapon proficiency (simple) из таблиц классов убрал (у Тайного лучника строка WeapProfSim снята, у остальных её нет), а игра её даёт: логи `.билд` (CLAUDE.md §3 «Фиты Сиалы», `siala_41/feats.json` → weapon_proficiency_simple, granted_automatically_to) — источник из движка, выше таблицы. Выдаёт сервер мимо cls_feat — ровно случай «таблица умеет молчать» (`priv/hak/README.md`). Друид логом не покрыт (открыто в CLAUDE.md)."
    },
    %{
      key: "class_feats/spirit_of_siala/granted_unmapped",
      check: :spirit_of_siala_grants,
      kind: :e,
      note:
        "Строка 754, подписанная FEAT_EPIC_TOUGHNESS_1, — «Дух Сиалы», отдельный фит, выданный всем на 1-м уровне (решение Dan 02.10.2026, задача 4.52). В модели он не фит, а `character.spirit_of_siala` (+20 HP, `siala_41/overrides.json`); Epic toughness — 10 взятий сверх него. Не переоткрывать."
    },
    %{
      key: ~r{^class_feats/siala_(axe|blade|hammer|polearm)_proficiency/bonus_for$},
      base:
        "barbarian, blackguard, champion_of_torm, dwarven_defender, fighter, paladin, ranger, weapon_master",
      ours: "champion_of_torm, fighter, paladin, ranger, weapon_master",
      kind: :d,
      note:
        "Хак против РЕШЕНИЯ Dan `AK2` (03.09.2026, «игроки зарепортят сами»): владения Сиалы в бонусном слоте берут только пять классов, шестнадцать — нет, под тестом `bonus_feat_pool_test.exs`. Решение принято без замера и без свидетельств, а хак свидетельство даёт: таблицы Варвара, Чёрного стража и Гномьего защитника перечисляют все пять владений (строки 2001–2005) с List 1 — ровно как у Паладина, которого Dan мерил (`AK1`: «игра позволяет»), и Тайного лучника — «Bows». Данные не тронуты: решение под тестом, переоткрывать его — Dan. Сценарий — в «Нужен замер» этого файла."
    },
    %{
      key: "class_feats/siala_ranged_proficiency/bonus_for",
      base: "9 шт.; нет у нас: arcane_archer, barbarian, blackguard, dwarven_defender",
      ours: "5 шт.; нет в .2da: ∅",
      kind: :d,
      note:
        "То же, что у четырёх других владений (решение `AK2` против хака), плюс Тайный лучник: его таблица перечисляет из пяти владений одно — «Bows» (cls_feat_archer.2da, строка 99, List 1). Сценарий — в «Нужен замер»."
    },

    # ------------------------------------------- bonus slot by value
    # ⚠ Задача 4.50 сняла здесь три правила — семь находок (a) области
    # `class_bonus_values`. Три закрыты данными: Тайный лучник (Epic weapon
    # focus, Overwhelming critical) и Убийца (Epic skill focus) — ванильный
    # слой `vanilla/feat_bonus_slot_values.json` («бонусный слот берёт только
    # эти значения», `bonus_for_only`), хак несёт те же строки и запись доезжает
    # до Сиалы сама. Четыре — бард, Арфист, вор, Теневой танцор (правило было
    # одно на четыре класса) — оказались слепотой сверки, а не дырой данных: ядро
    # отбивает эти пары правилом уровня (`only_on_class_levels_for_skill`,
    # `{:requires_leveling_as, …}`), а сверка этот ключ не читала; теперь
    # читает (`CompareClasses`, `@value_keys`). Правила сняты вместе
    # с находками; что сверка расхождение видит, держат порчи
    # `class_bonus_values/arcane_archer/epic_weapon_focus`,
    # `class_bonus_values/assassin/epic_skill_focus` и
    # `class_bonus_values/harper_scout/epic_skill_focus`
    # в `hak2da_positive_control_test.exs`.

    # ------------------------------------------------------ requirements
    %{
      key: "feats/devastating_critical/abilities",
      base: "str: 99",
      ours: "str: 25",
      kind: :e,
      note:
        "Фит на Сиале выключен (страница Сиалы revid 12690; `siala_41/feats.json` → devastating_critical, disabled): ни слотом, ни с вещи. MINSTR 99 у 40 строк из 41 — приём выключения, унаследованный от базовой игры; наше STR 25 — требование со страницы Сиалы, до числа не доезжает."
    },
    %{
      key: "feats/epic_dodge/skills",
      base: "tumble: —",
      ours: "∅",
      kind: :d,
      note:
        "Хак спорит со страницей Сиалы: та сняла «Акробатика 30» (вместе с 21-м уровнем и Improved evasion), а строка feat.2da оставила REQSKILL Tumble без порога рангов. Что значит такое требование, известно по Perform: Artist у барда с 0 рангов доступен (замер `AC8`), но Perform применяется без обучения, а Tumble — нет (Untrained 0). Сценарий — в «Нужен замер»; ответ меняет только билд без единого ранга Tumble."
    },
    %{
      key: "feats/epic_toughness/feats",
      base: "«Дух Сиалы» [feat.2da:754]",
      ours: "∅",
      kind: :e,
      note:
        "Epic toughness II (строка 755) требует строку 754, а это «Дух Сиалы», выданный каждому персонажу на 1-м уровне (решение Dan 4.52): требование выполнено всегда, до ответа не доезжает."
    },
    %{
      key: ~r{^feats/(weapon_focus|improved_critical)/feats$},
      base: "Swords [feat.2da:2005]",
      ours: "∅",
      kind: :b,
      note:
        "Разница представления. Каноническая строка семейства у хака требует владение СВОЕГО оружия (PREREQFEAT1 — одна из строк 2001–2005, у меча — Swords); у нас то же правило одним ключом — `proficiency_with_chosen_weapon`, группа по оружию. Что хак называет те же группы у всех 38 оружий, держит `feat_requirements_hak_test.exs`."
    },
    %{
      key: ~r{^feats/mounted_(combat|archery)/abilities$},
      base: "str: 99",
      ours: "∅",
      kind: :b,
      note:
        "Разница представления: MINSTR 99 хака (у базы порога нет — правка шарда) у нас — `level_up_selectable: false` (`siala_41/feats.json`, задача 4.49): на левелапе фит не выбрать ни одним слотом."
    },
    %{
      key: ~r{^feat_classes/mounted_(combat|archery)/general_slot_for$},
      check: :all_classes_vs_none,
      kind: :b,
      note:
        "Разница представления: ALLCLASSESCANUSE 1 у строки есть, но MINSTR 99 не даёт её взять никому; у нас — `level_up_selectable: false` (`siala_41/feats.json`, задача 4.49), общий слот фит не берёт."
    },
    %{
      key: "feat_classes/devastating_critical/general_slot_for",
      check: :all_classes_vs_none,
      kind: :e,
      note:
        "Фит на Сиале выключен (страница Сиалы, `siala_41/feats.json` → devastating_critical, disabled); таблица выключает его порогом MINSTR 99, а не колонкой ALLCLASSESCANUSE."
    },
    %{
      key: "feat_classes/weapon_proficiency_simple/general_slot_for",
      base: "0 шт.; нет у нас: ∅",
      ours:
        "10 шт.; нет в .2da: arcane_archer, assassin, blackguard, champion_of_torm, dwarven_defender, harper_scout, purple_dragon_knight, red_dragon_disciple, shadowdancer, weapon_master",
      kind: :e,
      note:
        "Weapon proficiency (simple) на Сиале у каждого персонажа с 1-го уровня — выдача сервера мимо таблиц (логи `.билд`, `siala_41/feats.json` → granted_automatically_to), поэтому слотом его не взять: `already_taken` (проверено вызовом, вор 6). Таблица хака выдач не несёт и выбор закрывает — у нас тот же ответ другой дорогой."
    },
    %{
      key: "feats/mount_actions/abilities",
      base: "str: 99",
      ours: "∅",
      kind: :b,
      note:
        "Разница представления: хак закрывает строку трижды — MinLevel 99, ALLCLASSESCANUSE 0 и MINSTR 99 (у базы — первые два), выдачу выносит за кап. У нас — `level_up_selectable: false` (`vanilla/feat_level_up_selectable.json`, задача 4.49; до Сиалы доезжает сам) и `classes: []` в `siala_41/class_granted_feats.json`."
    },
    %{
      key: "feats/summon_mount/abilities",
      base: "str: 99",
      ours: "∅",
      kind: :b,
      note:
        "Разница представления: MINSTR 99 хака (у базы порога нет) закрывает строку от выбора, а у нас фит и так не берёт ни один слот — `type: class`, в бонусных списках его нет. Выдачу паладину 5 хак снял, и у нас она снята (`siala_41/classes.json` → paladin, granted_feat_removed, задача 4.49)."
    },
    %{
      key: "feats/spirit_of_siala/unmapped_rows",
      base: "«Дух Сиалы» [754]",
      ours: "—",
      kind: :e,
      note:
        "«Дух Сиалы» — не фит модели, а `character.spirit_of_siala` (+20 HP, `siala_41/overrides.json`); решение Dan 4.52."
    },
    %{
      key: "feats/siala_retired_rows/unmapped_rows",
      base: "Brew Potion (строка базы, снятая хаком) [944]",
      ours: "—",
      kind: :d,
      note:
        "Прежняя строка Brew Potion: хак вывел её из оборота (GrantedOnLevel 99 во всех своих cls_feat_*) и завёл строку 2018. Но таблицу Оборотня хак не присылает, а базовая `cls_feat_shiftr.2da` (строка 43) перечисляет строку 944 с List 0 и уровнем 3 — у неё нет ни одного требования. Значит, клиент может предложить Оборотню 3+ «старый» Brew Potion без Знания 4, а мы требуем Знание 4 у всех. Сценарий — в «Нужен замер»; ответ меняет только Оборотня без 4 рангов Знания."
    },
    %{
      key: "feats/siala_riding/unmapped_rows",
      base: "Charge (FEAT_CHARGE) [2008]",
      ours: "—",
      kind: :b,
      note:
        "FEAT_CHARGE — таран верхом (страница Сиалы «Верховая езда»). В справочнике его нет, и он ни к чему не доезжает: строка закрыта (ALLCLASSESCANUSE 0; все 11 таблиц базовых классов хака перечисляют её с уровнем 99)."
    },
    %{
      key: "feats/siala_spell_school_focus/unmapped_id",
      base: "—",
      ours: "Фокусировки на школы магии",
      kind: :b,
      note:
        "Не фит: страница Сиалы про семейство Spell focus (запись `describes_feat: false`, type nil, слотом не берётся — `feat_slots_test.exs`). Строки в feat.2da у неё нет и быть не должно."
    },
    %{
      key: "repeatable/epic_toughness/max_takes",
      base: "9",
      ours: "10",
      kind: :e,
      note:
        "Решение Dan 02.10.2026 (задача 4.52): строка 754 — «Дух Сиалы», Epic toughness на Сиале — 10 взятий СВЕРХ него; цепочка 755–763 в хаке — 9 строк. Не переоткрывать и до 9 не «чинить»."
    },

    # ------------------------------------------------------------ weapons
    %{
      key: ~r{^weapons/[a-z_]+/proficiency$},
      check: :martial_plus_group,
      kind: :b,
      note:
        "Разница представления. Хак держит в ReqFeat0 ванильное Weapon proficiency (martial), а владение Сиалы — группой (строки 2001–2005); у нас — только группа. Martial на Сиале выключен (`siala_41/feats.json`, замер H5) и хаком не выдаётся ни одному классу, так что «любой из двух» на Сиале и есть «группа»."
    },
    %{
      key: "weapons/club/proficiency",
      base: "weapon_proficiency_martial, weapon_proficiency_simple",
      ours: "∅",
      kind: :e,
      note:
        "Дубина владения не требует (CLAUDE.md §6): simple на Сиале выдаётся всем 23 классам на 1-м уровне (логи `.билд`), martial выключен — «любой из двух» есть у каждого."
    },
    %{
      key: ~r{^weapons/[a-z_]+/(damage|threat_range|critical_multiplier|damage_types)$},
      kind: :b,
      note:
        "До печатаемого не доезжает: урон, угроза крита, множитель и тип урона в ruleset не загружаются вовсе (сверка читает их из сырого `vanilla/weapons.json`), калькулятор урона не считает (CLAUDE.md §9). Шард переписал урон почти всему оружию — это его система оружия; если урон когда-нибудь станут считать, источник Сиалы — эта таблица."
    },
    %{
      key: ~r{^weapons/(dart|shuriken)/grip_(medium|small)$},
      base: "one_handed",
      ours: "two_handed",
      kind: :e,
      note:
        "Колонка Сиалы «двуручное/метательное», хак — WeaponWield 11 (метательное, одной рукой). Объяснено замером `R5` (Dan 16.08.2026): «двуручное» там про бросок — щит с дротиком в игре остаётся, и модель это знает (`Rules.Wield`: у метательного вторая рука свободна). Проверено вызовом: человек-воин 5 с дротиками и большим щитом — щит в AC (+2), отказа нет."
    },
    %{
      key: ~r{^weapons/lance/grip_(medium|small)$},
      kind: :e,
      note:
        "Лэнса на Сиале нет (слово Dan; `{:not_on_shard, id}`, значение закрыто у всех оружейных фитов) — хват не печатается. Ванильный спор о колонке WeaponWield 4 (вид (d) в `docs/base2da_diff.md`) Сиалы не касается."
    },

    # ------------------------------------------------------------- spells
    # ⚠ Задача 4.58 сняла здесь правило (a) — находку
    # `spells/endure_elements/unmapped_id`: строка 50 хака («Отражение
    # (Reflection)») названа в `SialaRows`, имя и иконку переписывает слой
    # `siala_41/spells.json`. Имя у названных строк сверяется с меткой
    # (`CompareOther`, поле `name`); что расхождение видно, держит порча
    # `spells/endure_elements/name` в `hak2da_positive_control_test.exs`.
    %{
      key: ~r{^spells/(energy_drain|tide_of_battle)/levels$},
      check: :cleric_column_only,
      kind: :b,
      note:
        "До печатаемого не доезжает: хак переставил круг Священника (Energy drain снят, Tide of battle — 9), а круг Священника не читает ни одно наше число — выбор заклинаний есть только у барда и колдуна (`Builder.LevelPicks`, `spells_known`), а цена специализации — только у волшебника. Колонка мага та же."
    },
    %{
      key: ~r{^spells/(stream_of_flame|wall_of_fire)/innate_level$},
      kind: :b,
      note:
        "До печатаемого не доезжает: врождённый уровень заклинания (Innate) не читает ни одно правило (`rules/` его не знает). Круги Сиалы у этих двух уже свои (`siala_41/spells.json`: Stream of Flame — маг 4, Wall of fire — друид 5) и с хаком сходятся."
    },

    # ---------------------------------------------------------- constants
    # ⚠ Задача 4.57 сняла здесь два правила (b) — находки
    # `constants/POINT_BLANK_SHOT_ATTACK_BONUS/value` (хак 5, у нас было 1)
    # и `constants/CALLED_SHOT_TO_HIT_MODIFIER/value` (хак 2, было −4). Числа
    # шарда лежат в слое `siala_41/feat_attack_bonuses.json` (источник —
    # страница Сиалы и строка хака), сверка сходится, находок нет. Что
    # расхождение снова видно, держат порчи обоих ключей
    # в `hak2da_positive_control_test.exs`.
    %{
      key: "constants/hak_changed_unprobed/value",
      base:
        "CALLED_SHOT_ARM_ATTACK_PENALTY 2 → 3 [9], CALLED_SHOT_EFFECT_DURATION 24.0f → 8.0f [8], CALLED_SHOT_LEG_ABILITY_PENALTY 2 → 3 [10], CRIPPLING_STRIKE_STRENGTH_MODIFIER 2 → 3 [26], DIRTY_FIGHTING_BONUS_DICE 4 → 50 [455], EPIC_ENERGY_RESISTANCE_AMOUNT_2 20 → 30 [229], EPIC_ENERGY_RESISTANCE_AMOUNT_3 30 → 45 [230], EPIC_ENERGY_RESISTANCE_AMOUNT_4 40 → 60 [231], EPIC_ENERGY_RESISTANCE_AMOUNT_5 50 → 75 [232], EPIC_ENERGY_RESISTANCE_AMOUNT_6 60 → 90 [233], EPIC_ENERGY_RESISTANCE_AMOUNT_7 70 → 105 [234], EPIC_ENERGY_RESISTANCE_AMOUNT_8 80 → 120 [235], EPIC_ENERGY_RESISTANCE_AMOUNT_9 90 → 135 [236], IMPROVED_WHIRLWIND_ATTACK_RANGE 4.0f → 8.0f [101], MOVEMENT_SPEED_BONUS_MONK_CAP 3.0f → 1.5f [320], POINT_BLANK_SHOT_DAMAGE_BONUS 1 → 5 [146], REST_ENEMY_CHECK_DISTANCE 30.0f → 0.0f [107], TAUNT_ARCANE_SPELL_FAILURE 30 → 100 [30], TAUNT_EFFECT_DURATION 30.0f → 12.0f [29], TAUNT_MAX_MODIFIER 6 → 10 [31], WHIRLWIND_ATTACK_RANGE 2.0f → 4.0f [100]",
      ours: "∅",
      kind: :b,
      note:
        "Пункт (1) постановки: из 26 констант, которые хак переписал, сверка сравнивает пять, и все пять сходятся со слоем Сиалы: POINT_BLANK_SHOT_ATTACK_BONUS 5 и CALLED_SHOT_TO_HIT_MODIFIER 2 (с задачи 4.57 — `siala_41/feat_attack_bonuses.json`), EPIC_ENERGY_RESISTANCE_AMOUNT_1 и _10 — 15 и 150, MULTICLASS_LIMIT 4. Остальные 21 — здесь, и ни одна не доезжает до печатаемого: эффект на цель (Called shot, Crippling strike, Taunt), урон (Point blank shot, Dirty fighting), дистанции и длительности, скорость монаха, отдых; промежуточные ступени Epic energy resistance 2–9 — то же «15 за взятие», что и у сверенных крайних. Список прибит: новая правка шарда в ruleset.2da уронит `--check`."
    }
  ]

  # --------------------------------------------------------- predicates --

  # Строка 754 у каждого из одиннадцати базовых классов на 1-м уровне — и ничего больше.
  defp check(:spirit_of_siala_grants, f) do
    entries = String.split(f.base, "; ")

    f.ours == "—" and length(entries) == 11 and
      Enum.all?(
        entries,
        &Regex.match?(~r/^[a-z_]+: «Дух Сиалы» \(FEAT_EPIC_TOUGHNESS_1\) на 1$/, &1)
      )
  end

  # Таблица открывает строку всем 23 классам, у нас — никому.
  defp check(:all_classes_vs_none, f),
    do: String.starts_with?(f.base, "23 шт.;") and f.ours == "0 шт.; нет в .2da: ∅"

  # «группа Сиалы, martial» у таблицы против «группа Сиалы» у нас.
  defp check(:martial_plus_group, f),
    do:
      String.starts_with?(f.ours, "siala_") and
        f.base == f.ours <> ", weapon_proficiency_martial"

  # Разница только в колонке Священника.
  defp check(:cleric_column_only, f) do
    strip = &String.replace(&1, ~r/(, )?cleric: \d+/, "")

    norm =
      &(&1
        |> strip.()
        |> String.trim_leading(", ")
        |> then(fn s -> if s == "", do: "∅", else: s end))

    norm.(f.base) == norm.(f.ours)
  end

  @doc "Ставит находке вид и довод (moduledoc, «Как ставится вид»)."
  @spec classify(Finding.t(), %{String.t() => Finding.t()}) :: Finding.t()
  def classify(%Finding{} = finding, vanilla_index) do
    key = Finding.key(finding)

    case Enum.find(@rules, &matches?(&1, key, finding)) do
      %{kind: kind, note: note} ->
        %{finding | kind: kind, note: note}

      nil ->
        cond do
          finding.kind != nil ->
            finding

          inherited = same_as_vanilla(vanilla_index[key], finding) ->
            %{finding | kind: inherited.kind, note: @inherited <> (inherited.note || "")}

          true ->
            finding
        end
    end
  end

  defp same_as_vanilla(nil, _finding), do: nil

  defp same_as_vanilla(%Finding{kind: kind} = vanilla, finding) when kind != nil do
    if vanilla.base == finding.base and vanilla.ours == finding.ours, do: vanilla
  end

  defp same_as_vanilla(_unclassified, _finding), do: nil

  @doc "Все правила — для теста: вид из закрытого списка, непустой довод."
  @spec rules() :: [map()]
  def rules, do: @rules

  defp matches?(rule, key, finding) do
    key_matches?(rule.key, key) and
      (not Map.has_key?(rule, :base) or rule.base == finding.base) and
      (not Map.has_key?(rule, :ours) or rule.ours == finding.ours) and
      (not Map.has_key?(rule, :check) or check(rule.check, finding))
  end

  defp key_matches?(%Regex{} = regex, key), do: Regex.match?(regex, key)
  defp key_matches?(exact, key), do: exact == key
end
