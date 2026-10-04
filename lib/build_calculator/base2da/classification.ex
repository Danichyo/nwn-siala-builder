defmodule BuildCalculator.Base2da.Classification do
  @moduledoc """
  Классификация находок сверки базовых `.2da` с ванильным слоем (задача 4.5).

    * `:a` — **наши данные неверны или неполны**: `.2da` говорит, Fandom с ним
      согласен или молчит, а у нас другое или ничего. Это правка данных;
    * `:b` — **разница представления**: один и тот же факт записан по-разному
      (ступени фита, растущая кость РДД отдельным полем, выбор оружия прозой)
      или разница не доезжает ни до одного числа;
    * `:c` — **`.2da` этого не решает**: правило в движке, таблица даёт в лучшем
      случае число без условия; остаются Fandom и замер;
    * `:d` — **Fandom и `.2da` спорят** — нужен замер в одиночной игре
      (`VANILLA.md` §6, идея 6).

  🔴 **Ранга «таблица важнее Fandom» проект не объявлял** (`priv/hak/README.md`,
  разбор `Extra turning`), поэтому спор источников — это `:d`, а не `:a`
  в пользу таблицы. `:a` — только там, где Fandom с таблицей согласен (часто —
  в разделе Notes той же страницы, которую наш парсер прочитал до половины)
  или молчит.

  Правило подбирается по ключу находки (`Finding.key/1`): точное совпадение или
  регулярное выражение, первое совпавшее выигрывает. Правило из четырёх
  элементов несёт ещё и **предикат по значениям** находки (задача 4.50, как
  у `SialaClassification`): ключ совпал, а значения другие — правило не
  подходит, и находка остаётся без вида. Так правило на широкий ключ не глотает
  чужое расхождение под тем же ключом. Сравнение само ставит вид
  только там, где он следует из формы расхождения (ступени фита, строка
  с зачёркнутой историей правок), — правило здесь его перекрывает. Находка без
  правила остаётся `nil` и печатается в отчёте отдельным списком: новая
  выгрузка или новая правка данных, которой ещё никто не смотрел в глаза.
  """

  alias BuildCalculator.Base2da.Finding

  @rules [
    # ------------------------------------------------------------- classes
    {"classes/purple_dragon_knight/class_skills", :d,
     "Fandom спорит сам с собой: страница класса Heal не называет, страница навыка Heal называет PDK; наш слой берёт объединение ({:derived, :class_skills, :union_of_class_and_skill_pages}). cls_skill_pdk.2da — без Heal, как страница класса. Замер: PDK 1 — Heal стоит 1 очко или 2."},
    {"classes/red_dragon_disciple/hit_die", :b,
     "В EE растущая кость РДД — фиты «Hit Die Increase (d6/d8/d10)» из cls_feat_dradis + константы FEAT_DRAGON_HDn в ruleset.2da; колонка HitDie (8, в 1.69 было 6) её не описывает. У нас hit_die = nil и шкала отдельным полем hit_die_by_class_level."},
    {"classes/red_dragon_disciple/hit_die_by_class_level", :c,
     "d6 с 1-го, d8 с 4-го, d10 с 6-го — совпали с выдачами и константами. d12 с 11-го таблицы не называют: константа FEAT_DRAGON_HD12 = 12 есть, фита, который её выдаёт, нет — ступень считает движок. Замер в одиночной игре: РДД 11 — прибавка HP за уровень (с учётом CON). Там же видно, работает ли где-то HitDie = 8."},

    # ---------------------------------------------------------- class feats
    {~r{^class_feats/[a-z_]+/granted_ranks/}, :b,
     "Первая выдача совпала; ступени одной семьи одна сторона пишет строкой на каждом уровне, другая — одной строкой, а рост считает движок или правило."},
    # ⚠ Задача 4.27 закрыла здесь находку (a) `class_feats/mount_actions/granted_first`:
    # Mount actions (FEAT_HORSE_MENU) выдаётся на 1-м уровне всем 11 базовым
    # классам записью `vanilla/class_granted_feats.json` (источник — Notes
    # страницы фита и строки cls_feat_*.2da, List 3). У Сиалы хак выносит ту же
    # выдачу на 60-й уровень, за кап, — её половина `siala_41/class_granted_feats.json`
    # говорит `classes: []`. Правило снято вместе с находкой, как в 4.7: выдача,
    # разошедшаяся с таблицей снова, придёт находкой без вида, и `--check`
    # упадёт; что сверка это видит, держит порча
    # `class_feats/mount_actions/granted_first` в `positive_control_test.exs`.
    {"class_feats/hit_die_increase/granted_first", :b,
     "Кость РДД у нас считается полем hit_die_by_class_level (совпало с .2da: 1/4/6), а в выдачах фит стоит на 4-м, как в таблице Fandom. Число HP не задето; список «Класс даёт сам» у РДД на 1-м и 6-м короче таблицы."},
    {"class_feats/weapon_of_choice/granted_first", :b,
     "Мастер оружия: в .2da — бонусный слот на 1-м уровне (cls_bfeat_wm) и 31 строка Weapon of Choice в List 2; у нас — выдача на 1-м с выбором (grant_substitutions.json). Один факт, две формы."},
    {"class_feats/epic_class_markers/granted_unmapped", :b,
     "Служебные фиты «Epic <Class>» движок выдаёт на 21-м уровне базового класса и 11-м престижного; у нас эпичность считается уровнями (epic.json), своего фита нет. Чисел не двигает."},
    {"class_feats/improved_critical/bonus_for", :d,
     "cls_feat_pal.2da перечисляет из 41 строки Improved Critical ровно одну — Whip (List 1); у бойца — 40 (все, кроме «(creature)»). Похоже на след добавления кнута в EE. У нас паладин в bonus_for не входит, как на Fandom. Замер: паладин 21+ — предлагается ли Improved Critical (Whip) эпическим бонусным фитом."},
    {"class_feats/sap/bonus_for", :b,
     "Sap выключен в самом feat.2da порогом MINSPELLLVL 100 (у нас caster_level 100) — строка в пулах бойца и CoT есть, взять фит нельзя никем."},
    # ⚠ Задача 4.26 закрыла здесь 7 находок (a) — эпическая шкала бонусных
    # фитов Убийцы, Чёрного стража, Бледного мастера, РДД, Теневого танцора,
    # Оборотня и (за 30-м) Мастера оружия, — и 3 находки (b) «за потолком»
    # (Тайный лучник, Чемпион Торма, Гномий защитник: 34 и 38): все десять
    # классов получили уровни таблицы cls_bfeat_* до 40-го записью
    # `vanilla/class_bonus_feat_levels.json` (источник `kind: "2da"`, `extends`
    # сверяется с машинным слоем). Правила сняты вместе с находками, как в 4.7:
    # шкала, разошедшаяся с таблицей снова, придёт находкой без вида, и
    # `--check` упадёт. Что сверка это расхождение видит, держит порча
    # `class_feats/pale_master/bonus_feat_levels` в `positive_control_test.exs`.
    # 🔴 Вид (a) у этих находок стоял на оценке достижимости, которая не учла
    # предел «10 уровней престиж-класса до 20-го уровня персонажа»: у ванили
    # престиж кончается на 30-м, и ни один продлённый уровень ей не достижим;
    # число сдвигается только у Сиалы, на 31-м (потолок 10 + 21).
    {"class_feats/weapon_master/bonus_feat_levels", :b,
     "Уровень 1 — выбор Weapon of Choice (см. weapon_of_choice/granted_first, разница формы): в .2da это бонусный слот (cls_bfeat_wm, строка 0), у нас — выдача с выбором, которую ядро превращает в тот же слот (grant_substitutions.json). Эпическая шкала совпала целиком, включая 31–40 (задача 4.26)."},

    # ---------------------------------------------------- bonus slot values
    # Задача 4.50 включила у ванили сверку бонусного слота по значению. Четыре
    # её находки (a) закрыты данными (`vanilla/feat_bonus_slot_values.json`:
    # Тайный лучник — Epic weapon focus, Overwhelming critical, Devastating
    # critical только с луками, Убийца — Epic skill focus в Hide и Move
    # silently); ещё четыре (бард, Арфист, вор, Теневой танцор) были слепотой
    # самой сверки — правило уровня и «нет варианта» она теперь читает. Порчи
    # `class_bonus_values/*` в `positive_control_test.exs` держат, что сверка
    # видит расхождение. Осталась одна форма — ниже.
    {~r{^class_bonus_values/[a-z_]+/[a-z_]+$}, :b,
     "Оружие существ — у нас бонусный слот класса это значение не отбивает, у таблицы его строки нет ни в одном списке играбельного класса (строки feat.2da 289–292, 532, 656, 694, 746 — ALLCLASSESCANUSE 0 или пусто; из таблиц классов их знают только таблицы существ — 289 и 291, List 3). До печатаемого не доезжает — проверено вызовом: Weapon focus и Improved critical (creature) у ванили требуют владения выбранным оружием, то есть Weapon proficiency (creature) (задача 4.7), а это фит типа monster — ни один слот его не берёт, ни один класс не выдаёт, фит с вещи требование другого фита не выполняет (H7); остальные пять семейств (Weapon specialization, Epic weapon focus и specialization, Overwhelming и Devastating critical) стоят на Weapon focus или Improved critical того же оружия. Воин 4 — в бонусном и в общем слоте одно и то же: {:requires_feat, :weapon_proficiency_creature} (`feat_bonus_slot_values_test.exs`). Значение показывается недоступным с причиной, а таблица его не показывает — разница только в этом.",
     :creature_weapon_only},

    # --------------------------------------------------- class requirements
    {"class_requirements/arcane_archer/requirement/weapon_focus_choice", :b,
     "Совпадает по смыслу: .2da — FEATOR на две строки Weapon Focus (longbow/shortbow); у нас — qualifiers прозой «(longbow or shortbow)», выбор оружия ядро не проверяет."},
    # ⚠ Задача 4.27 закрыла здесь 2 находки (a) — вход Чемпиона Торма и Мастера
    # оружия засчитывал Weapon Focus (creature), а FEATOR таблиц
    # `cls_pres_divcha.2da` и `cls_pres_wm.2da` его не перечисляет.
    # `vanilla/class_requirements.json` исключает `creature_weapon` рядом
    # с рукопашным ударом (источник поля — строка cls_pres, `kind: "2da"`),
    # и множества сошлись: 31 = 31. Правило снято вместе с находками; порча
    # `class_requirements/weapon_master/requirement/weapon_focus_choice`
    # в `positive_control_test.exs` держит, что сверка расхождение видит.
    {"class_requirements/shifter/requirement/spell_level", :b,
     "SPELL 3 — «уровень класса-заклинателя 3» (nwn.wiki, cls_pres_xxx). Следует из Wild Shape, который у нас в требованиях: его выдаёт только друид 5-го уровня."},

    # --------------------------------------------------------- spellcasting
    # ⚠ Задача 4.44 закрыла здесь находку (d) `spellcasting/druid/spells_per_day[15][3]`
    # — единственное расхождение таблиц слотов и известных: Fandom (Druid, строка
    # 15th) — 6/5/5/5/4/4/3/2/1, cls_spgn_dru.2da — 6/5/5/4/4/4/3/2/1. Спор решил
    # замер AW1 (Dan, сервер Сиалы, 27.09.2026: «друид 15, WIS 14, 3-го круга
    # доступно 4 слота») в пользу таблицы; ячейка правится ручным слоем
    # `vanilla/class_spell_tables.json` (источник `kind: "2da"`, замер, цитата
    # Fandom с прежним числом) и доезжает до Сиалы — её хак этой таблицы не
    # присылает. Правило снято вместе с находкой, как в 4.7: ячейка, разошедшаяся
    # с таблицей снова, придёт находкой без вида, и `--check` упадёт. Что сверка
    # это расхождение видит, держит порча `spellcasting/druid/spells_per_day[15][3]`
    # в `positive_control_test.exs`.

    # ---------------------------------------------------------------- feats
    {~r{^feats/(artist|extra_music|lingering_song)/skills$}, :b,
     "REQSKILL Perform без минимума рангов — «навык Perform», а он есть только у барда (AllClassesCanUse 0). У нас то же выражено уровнем барда / Bard Song (feat_requirements.json → artist)."},
    {~r{^feats/(extra_music|lingering_song)/class_level/bard$}, :b,
     "MinLevelClass Bard, MinLevel 1; у нас — требование Bard Song, который выдаёт только бард 1-го уровня. То же условие."},
    {"feats/weapon_of_choice/class_level/weapon_master", :b,
     "Weapon of Choice выбирается Мастером оружия на 1-м (у нас — выдача с выбором, grant_substitutions.json)."},
    # ⚠ Задача 4.25 закрыла здесь 2 находки (a): Weapon specialization — воин 4
    # (было 1), Lasting inspiration — Bard Song 20-го уровня, то есть бард 20
    # (было «любая песня», бард 1); обе — записями `vanilla/feat_requirements.json`.
    # Правила сняты вместе с находками, как в 4.7: требование, разошедшееся
    # с таблицей снова, придёт находкой без вида, и `--check` упадёт. Что сверка
    # эти два расхождения по-прежнему видит, держит порча в
    # `positive_control_test.exs`.
    {"feats/epic_shadowlord/class_level/shadowdancer", :c,
     "MinLevelClass Shadowdancer без MinLevel — уровня таблица не называет; что движок делает с классом без уровня, .2da не говорит. У нас SD 11 (Fandom: «epic shadowdancer»). Остальное совпало: эпический, Summon Shadow."},
    {"feats/domain_powers/unmapped_rows", :b,
     "Способности доменов — выдачи домена, не выбор. Что домен делает, калькулятор не считает сознательно (решение Dan, задача 3.79; moduledoc Rules.ClassChoices, «What is not here»)."},
    {"feats/epic_class_markers/unmapped_rows", :b,
     "Служебные фиты «Epic <Class>» и «Epic Character»: движок помечает ими эпического персонажа; у нас эпичность — уровни (epic.json)."},
    {"feats/horse_menu/unmapped_rows", :b,
     "Подменю верховой езды (Individual/Party Mount…) — действия интерфейса, MinLevel 99, не выбираются."},
    {"feats/skilled/unmapped_id", :b,
     "Skilled в EE — не фит, а колонки racialtypes.2da (ExtraSkillPointsPerLevel 1, FirstLevelSkillPointsMultiplier 4); число сошлось: races.human.bonus_skill_points."},

    # ----------------------------------------------------------- repeatable
    {"repeatable/extra_turning/repeatable", :d,
     "Уже открытый кейс AG1 (GAME_CHECKS.md, из сверки хаков). Добавка из базовых таблиц: строка та же (GAINMULTIPLE 1, EFFECTSSTACK 1), а nwn.wiki о самих колонках: «Nonfunctional. Was meant to allow Extra Turning (and similar feats) to be allowed to be taken multiple times.» — довод в пользу нашего «нет», но это не замер."},
    # ⚠ Задача 4.7 закрыла здесь 17 находок (a) — потолок взятий семнадцати
    # фитов со ступенями: `vanilla/feat_repeatable.json` несёт его длиной
    # цепочки feat.2da, и сверка сходится. Правило снято вместе с находками:
    # потолок, разошедшийся с таблицей снова, придёт находкой без вида,
    # и `--check` упадёт. Попутно поправлено само сравнение — оно сверяло
    # длину цепочки с КАРТОЙ `max_takes`, а не с её числом, и расходилось бы
    # и при верном потолке.
    # ⚠ Задача 4.30 закрыла здесь 2 находки (a) — Overwhelming critical
    # и Devastating critical получили блок повторяемости с выбором оружия
    # (`vanilla/feat_repeatable.json`: 40 строк feat.2da под MASTERFEAT 12 и 13,
    # по фиту на оружие, плюс строка оружия существ без MASTERFEAT). Запись
    # доезжает до Сиалы по решению постановки («оба ruleset'а, меняет Сиалу»)
    # и с доказательством хаком (`weapon_feat_tables_hak_test.exs`). Правило
    # снято вместе с находками; порча `repeatable/overwhelming_critical/choice`
    # в `positive_control_test.exs` держит, что сверка видит расхождение.

    # ---------------------------------------------------------- feat classes
    # ⚠ Задача 4.24 закрыла здесь все 8 находок (a) области — Bane of enemies,
    # Great smiting, Improved ki strike 4 и 5, Improved sneak attack, Improved
    # spell resistance, Lasting inspiration, Planar turning получили
    # `only_on_class_levels` по `ALLCLASSESCANUSE 0` и спискам `cls_feat_*`
    # (`vanilla/feat_requirements.json`, у каждого поля источник `kind: "2da"`).
    # Правило снято вместе с находками: фит, у которого список классов снова
    # разойдётся с таблицей, придёт находкой без вида, и `--check` упадёт.
    # Что сверка это расхождение видит, держит порча в `positive_control_test.exs`.

    # ---------------------------------------------------------------- races
    {"races/human/bonus_feats", :b,
     "Skilled у нас — фит в bonus_feats плюс bonus_skill_points; в EE — только колонки racialtypes. Числа совпали (extra_skill_points)."},

    # ----------------------------------------------------------- stat gains
    # ⚠ Задача 4.26 закрыла здесь все 3 находки (a) области: естественный AC
    # Бледного мастера (32, 36, 40) и РДД (35, 40) — `vanilla/ac_bonuses.json`,
    # источник поля `amount.ac_at_class_level_source` (cls_stat_*.2da); Enchant
    # Arrow Тайного лучника (+16 … +20 на 31 … 39) — `vanilla/feat_attack_bonuses.json`,
    # `amount.attack_at_class_level_source` (cls_feat_archer.2da) и `_source_2`
    # (ruleset.2da). Правила сняты вместе с находками; область теперь без
    # находок, и что сверка её не ослепла, держат порчи
    # `stat_gains/pale_master/natural_ac`, `stat_gains/red_dragon_disciple/natural_ac`
    # и `stat_gains/arcane_archer/enchant_arrow_attack` в `positive_control_test.exs`.
    # 🔴 Достижима из всех новых ступеней одна — Enchant Arrow +16 на 31-м,
    # и только у Сиалы: престиж-класс кончается на 30-м у ванили и на 31-м
    # у Сиалы (10 уровней до 20-го уровня персонажа + эпические).

    # -------------------------------------------------------------- weapons
    {~r{^weapons/(bite_item|claw_item|gore_item|slam_item|creature_weapon)/unmapped_id$}, :b,
     "Оружие существ в baseitems — четыре обезличенных типа (cslashweapon, cpiercweapon, cbludgweapon, cslshprcweap), по имени не сопоставить; PC им не пользуется."},
    {"weapons/unarmed_strike/unmapped_id", :b,
     "Безоружный удар — не предмет; в baseitems его держат перчатки и наручи (WeaponFocusFeat 100 = Weapon Focus (unarmed strike))."},
    {"weapons/dart/size", :d,
     "Fandom — tiny (Category:Tiny weapons), baseitems.2da — WeaponSize 2 (small). Сегодня не двигает ничего: дротик метательный, одноручный у обоих размеров владельца и не фехтовальный."},
    # ⚠ Задача 4.28 закрыла здесь 14 находок: дротик и сюрикен (4, (a)) — хват
    # ванили больше не с колонки Сиалы; семь `*_without_siala_grip` — проверка
    # снята вместе с вопросом («что будет, если колонку Сиалы у ванили убрать»);
    # три такие же у посоха и лэнса. Три оставшиеся у посоха и лэнса — ниже,
    # и они больше не (a).
    {~r{^weapons/(lance|magic_staff)/grip_(medium|small)$}, :d,
     "Сторона .2da читает WeaponWield 4 подписью значения — «two-handed weapon (polearm)», двумя руками при любом размере (чтение задачи 4.5). Ванильный слой (задача 4.28, vanilla/weapon_wield.json, статус assumed) читает 4 как набор анимаций древкового и хват оставляет размеру: Fandom «Baseitems.2da» — «Indicates which animation set is used when this item is wielded»; nwn.wiki — «If a two handed weapon being of a certain size may affect if it is single or two handed»; Fandom «Magic staff» — во вторую руку нельзя «without using a modified baseitems.2da» (у двуручного такая заметка была бы пустой); у лэнса в EquipableSlots бит второй руки стоит (0x1C030); игроки 2005 года (Epic Character Builder's Guild) — «a 'staff' is treated as single handed weapon, allowing you to equip a weapon or shield in your offhand». Разница — у двух видов из шести древковых (посох medium, лэнс small; остальные large). Замер: одиночная NWN:EE, человек, магический посох в правой руке, малый щит в левой — надевается ли щит. Ответ касается и Сиалы: строка 45 в её хаке та же."},
    {"weapons/sling/thrown", :d,
     "Fandom кладёт пращу в Category:Throwing weapons (отсюда thrown? = true); baseitems.2da различает пращу (WeaponWield 10) и метательное (11). Сегодня не двигает ничего: на ванили thrown? хват не читает вовсе (задача 4.28: её таблица метательное двуручным не зовёт), на Сиале читается только у двуручного по её колонке — праща там одноручная."},
    {~r{^weapons/(dire_mace|double_axe|two_bladed_sword)/damage$}, :b,
     "Урон двустороннего оружия Fandom пишет парой «1d8/1d8», парсер её не разбирает; урон калькулятор не считает (CLAUDE.md §9)."},

    # --------------------------------------------------------------- spells
    {~r{^spells/(restoration_others|summon_shadow_shadow_conjuration)/unmapped_id$}, :b,
     "Страница-вариант на Fandom без своей строки в spells.2da (вариант — подзаклинание основной строки)."},
    {~r{^spells/[a-z_]+/innate_level$}, :b,
     "Число совпадает; у нас сырой викитекст с зачёркнутой историей правок Fandom (так заведено: уровни хранятся строками)."},
    {~r{^spells/(magic_fang|greater_magic_fang|tide_of_battle)/school$}, :d,
     "Fandom — Transmutation, spells.2da — Conjuration (Magic Fang, Greater Magic Fang) и Evocation (Tide of Battle). На печать не влияет: школа у нас работает только в цене специализации волшебника, а это не заклинания волшебника."},

    # ------------------------------------------------------------ constants
    {"constants/MIN_LEVEL_FOR_MAX_HP/value", :b,
     "Та же игра: максимум кости на уровнях персонажа 1–3, дальше бросок (Fandom «Hit point» говорит то же; правило лежит в rules.json → character.hit_points_roll). Калькулятор печатает максимум на каждом уровне, как CBC, — решение показа Dan 02.10.2026 (задача 4.20, rules.json → character.hit_points_shown), а не допущение."}
  ]

  @doc "Ставит находке вид и довод по первому совпавшему правилу."
  @spec classify(Finding.t()) :: Finding.t()
  def classify(%Finding{} = finding) do
    key = Finding.key(finding)

    case Enum.find(@rules, &applies?(&1, key, finding)) do
      nil -> finding
      rule -> %{finding | kind: elem(rule, 1), note: elem(rule, 2)}
    end
  end

  defp applies?({matcher, _kind, _note}, key, _finding), do: matches?(matcher, key)

  defp applies?({matcher, _kind, _note, check}, key, finding),
    do: matches?(matcher, key) and check(check, finding)

  # Таблица и мы расходимся ровно в одном значении — оружии существ, и только
  # с нашей стороны: всё, что перечисляет таблица, есть и у нас.
  defp check(:creature_weapon_only, finding),
    do:
      String.ends_with?(finding.base, "; нет у нас: ∅") and
        String.ends_with?(finding.ours, "; нет в .2da: creature_weapon")

  @doc """
  Все правила — для теста: у каждого вид из закрытого списка и непустой довод.
  Третий элемент — довод, четвёртый (если есть) — имя предиката по значениям.
  """
  @spec rules() :: [
          {String.t() | Regex.t(), Finding.kind(), String.t()}
          | {String.t() | Regex.t(), Finding.kind(), String.t(), atom()}
        ]
  def rules, do: @rules

  defp matches?(%Regex{} = regex, key), do: Regex.match?(regex, key)
  defp matches?(exact, key), do: exact == key
end
