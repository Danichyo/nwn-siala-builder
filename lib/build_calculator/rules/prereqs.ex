defmodule BuildCalculator.Rules.Prereqs do
  @moduledoc """
  One interpreter for both requirement blocks: a prestige class's and a feat's.

  Both are read off the wiki by the same parser into the same shape
  (`BuildCalculator.Wiki.Requirements`), so they are checked by the same code.
  Two implementations of "does this build have base attack +7" would eventually
  disagree, and the player would be told one thing by the class card and another
  by the feat list.

      %{
        "alignment" => %{require: ["lawful"]},
        "character_level" => 21,
        "max_character_level" => 1,
        "base_attack_bonus" => 7,
        "abilities" => %{"str" => 13},
        "race" => ["dwarf"],
        "feats" => ["dodge", "toughness"],
        "feat_choices" => %{"weapon_focus" => ["longbow", "shortbow"]},
        "feat_choice_properties" => %{"weapon_focus" => %{"ranged" => false}},
        "feat_choice_excludes" => %{"weapon_focus" => ["unarmed_strike"]},
        "proficiency_with_chosen_weapon" => true,
        "skills" => %{"hide" => 8},
        "class_levels" => %{"bard" => 1},
        "caster_level" => 3,
        "casts_spell_level" => 9,
        "save_bonus" => %{"fortitude" => 8},
        "any_skill_ranks" => 20,
        "only_on_class_levels_for_skill" => %{"perform" => ["bard"]},
        "class_levels_for_skill" => %{"perform" => %{"bard" => 1}},
        "chosen_skill_ranks_if_trained_only" => 1,
        "no_feat_variant_for_skills" => ["ride"],
        "qualifying_class_levels" => %{"wizard" => 21, "pale_master" => 15},
        "qualifiers" => ["in the chosen spell school"],
        "any_of" => [%{"race" => ["dwarf"]}, %{"class_levels" => %{"pale_master" => 3}}]
      }

  Keys arrive as strings from a feat (raw JSON) and as atoms from a class (the
  data layer normalises those, but only at the top level — inside an `any_of`
  branch they stay strings either way), and ids inside them as either. Both are
  accepted; a key outside the table above is ignored here and reported as a gap
  by the data layer, which is the one place that knows the whole file.

  ## Reasons are data, and reasons are what is *needed*

  `{:requires_bab, 7}` reads "needs base attack +7", not "your base attack is
  wrong". That is what lets the same tuple caption a locked feat and explain a
  refusal. Russian wording belongs to the web layer (CLAUDE.md §8).

  ## `any_of` is the one disjunction

  Everything else here is a conjunction. `any_of` holds whole requirement maps
  and is satisfied when **any** of them is — that is how the wiki writes
  "dwarf, half-orc, shadowdancer 2, pale master 3", a race list and a class list
  that are one alternative rather than two demands.

  When no branch is satisfied the reason carries **one list per branch**:
  `{:requires_any_of, [[{:requires_race, [:dwarf]}], [{:requires_class_level,
  :pale_master, 3}]]}`. Nothing is flattened, because "dwarf" and "pale master
  3" are alternatives to each other and a flat list of five tuples reads as five
  demands. A branch that cannot be decided keeps its `{:missing_data, ...}`
  inside its own list, so an undecidable alternative is visibly undecidable
  instead of quietly passing.

  ## `qualifiers` narrow a requirement the schema cannot narrow

  Some of the wiki's prose is a *refinement* of a requirement rather than a
  requirement of its own: `[[spell focus]] **in the chosen spell school**`,
  `[[greater rage]] **(6x per day)**`, "proficiency **with the chosen weapon**".

  The wrong answer is the one that used to be given: the whole fragment went to
  `unparsed`, and the feat was refused with `{:missing_data, ...}` — nothing
  checked, and a player told the feat is unavailable when it may well be
  available. So a qualifier is **not a reason**. The part that fits the schema is
  checked, the feat stays takeable, and the refinement is declared unmodelled
  through `qualifiers/1`, which `Rules.compute/2` folds into `stats.gaps`.
  "Проверяем что можем и говорим, чего не можем" — the same contract as
  everywhere else in the core.

  ⚠ **Здесь стояло «there is no way to say „the feat, but taken in this school"
  here, and there will not be until schools and weapons are modelled».** Обе
  посылки сняты: школы смоделированы, оружие пришло задачей 3.5. Оговорка
  осталась **формой**, но с задачи 3.99 её носителей стало вдвое меньше —
  три ключа ниже (`feat_choices`, `feat_choice_properties`,
  `proficiency_with_chosen_weapon`) выражают ровно то, что раньше выражать
  было нечем. Правило, которым решается «оговорка это или требование», одно:
  **оговорка печатается ровно там, где ядро ответить не может** — см.
  `qualifiers/1`.

  ## `feat_choices` — тот же вопрос, но уже проверяемый

  ⚠ Оговорка выше писалась, когда оружия в модели не было вовсе. Задача 3.5
  дала домену `weapon` справочник и записала выбор в билд, и с тех пор
  «Weapon Focus **луком**» перестало быть непроверяемым: у взятия фита есть
  записанное значение, и его есть с чем сравнить. `feat_choices` — это и есть
  сравнение:

      "feats" => ["weapon_focus", "point_blank_shot"],
      "feat_choices" => %{"weapon_focus" => ["longbow", "shortbow"]}

  Два ключа, а не один, и это не дублирование. `feats` спрашивает «фит есть?»
  и отвечает `{:requires_feat, …}`; `feat_choices` спрашивает «а с тем ли
  значением?» и отвечает `{:requires_feat_choice, фит, [значения]}`. Слить их
  в один ключ значило бы напечатать игроку одну причину там, где ему нужны
  разные подсказки: «возьми фит» и «возьми его на другое оружие» — разные
  действия.

  ⚠ **Значений может быть несколько, и это дизъюнкция.** Список — «одно
  из», как его и пишет источник («Короткий лук, Длинный лук, Малый арбалет
  или Большой арбалет»). Конъюнкции здесь нет и быть не может: одно взятие
  фита несёт одно значение.

  ## Чего `feat_choices` НЕ делает: не отказывает, когда значение не записано

  Взятие фита может не нести значения вовсе, и это два разных случая, ни один
  из которых не является «взял не то оружие»:

    * фит пришёл **с вещи** — объявление под «Вещами» это переключатель
      «фит есть / нет», оружия оно не называет (`Rules.GearFeats`, и там же
      про это уже стоит своя оговорка `{:not_modelled, {:gear_feat_choice,
      …}}`). При этом фит с вещи **выполняет требование класса** (замер Dan
      14.08.2026, H7), и отказать ему здесь значило бы отменить измеренное
      правило через заднюю дверь;
    * ссылка расшарена до задачи 3.26 — тогда выбор в билде не записывался,
      и у старого билда его нет. `Rules.AttackBonuses` бережёт этот случай
      ровно так же и по той же причине.

  Поэтому: значение записано — сравниваем; не записано — молчим. Ошибка
  односторонняя и выбрана осознанно. Отказ был бы **ложной нелегальностью**
  («класс тебе недоступен» тому, кому он в игре доступен), а она в этом
  проекте дороже пропущенной проверки — тот же довод, которым фит с вещи не
  запрещает взять себя же слотом (CLAUDE.md §6, «Вещи»).

  ⚠ И обратная сторона, которую легко сделать по инерции: как только выбор
  проверен, соседний `qualifiers` про то же самое **обязан уйти**. Иначе
  билд, у которого оружие сошлось, продолжит печатать «выбор оружия мы не
  проверяем» — ложная неопределённость наоборот, прямо запрещённая
  CLAUDE.md §6.

  ⚠ **`requirement_of` этот ключ ЧИТАЕТ с задачи 3.99, и раньше не читал.**
  Довод против был записан здесь же — «у вещи значения нет ни в каком случае» —
  и он держался ровно до задачи 3.97, которая дала объявлению под «Вещами»
  записанное значение. С тех пор чтение одних слотов означало бы, что
  `Weapon Focus (Longbow)`, объявленный с вещи, открывает Мастера оружия
  без единой проверки. Линия та же, что у `feats`: класс читает
  `Build.feat_choices_owned/4`, фит — `Build.feat_choices_permanent/4`.

  ## `feat_choice_properties` — то же требование, названное СВОЙСТВОМ значения

  «[[weapon focus]] **in a [[melee weapon]]**» (Мастер оружия и Чемпион Торма)
  говорит про значение то же, что `feat_choices`, но не списком, а свойством.
  Список тут был бы вторым экземпляром справочника: 39 имён оружия, переписанных
  в требование класса руками, устаревают молча в день, когда шард добавит
  сороковое. Свойство читается с записи (`Rules.Attack.weapon_property_field/1` —
  закрытый словарь ядра), и ни одного имени оружия в этом модуле нет.

  ⚠ Свойств может быть несколько, и это **конъюнкция** — в отличие от списка
  значений у `feat_choices`, который дизъюнкция. «Одно из этих значений» и «со
  всеми этими свойствами» — разные утверждения источника, и один ключ на оба
  соврал бы про одно из них.

  ⚠ Дизъюнкция при этом есть по **взятиям**: фит повторяем, и хватает одного
  подходящего — «weapon focus in a melee weapon» выполняет тот, у кого есть
  ближний фокус, даже если рядом взят лук.

  ## `feat_choice_excludes` — значение, которое требование НЕ ЗАСЧИТЫВАЕТ

  Третий способ сказать про то же значение, и полярность у него обратная:
  не «годится вот это», а «вот это не годится». Источник пишет ровно так,
  и пишет ПОИМЁННО:

  > «Even though unarmed strikes are weaponless, it is possible to get [[weapon
  > focus]] in unarmed strikes. However, **this focus does not satisfy the
  > "weapon focus in a melee ''weapon''" requirement** for the [[champion of
  > Torm]] and [[weapon master]] prestige classes» — `fandom:Unarmed strike`,
  > Notes; и та же мысль на странице Мастера оружия: «ranged weapons **and
  > unarmed strike are excluded from the prerequisites**».

  Перечисление, а не свойство, **потому что перечисляет источник** (тот же
  довод, что у `weapon_one_of` в `Rules.AttackBonuses`): рукопашный удар назван
  именем, а свойства, которым его отличить, справочник не несёт — у записи те же
  `ranged: false` и `size: null`, что у соседей, а `proficiency: []` означает
  «про владение не сказано», а не «это рукопашный удар». Правило на отсутствии
  данных исчезло бы молча в день, когда парсер заполнит поле.

  ### 🔴 Это НЕ независимый конъюнкт, а сужение того, что считается взятием

  Источник говорит «**этот фокус не удовлетворяет требованию**» — то есть
  взятие с таким значением для этого блока не считается взятием вовсе. Ключ
  так и работает: исключённые значения выпадают из того, что видят **все**
  остальные ключи про значение (`feat_choices`, `feat_choice_properties`).

  Иначе получилась бы ложная легальность, и достижимая обычной игрой: у билда
  с `Weapon Focus (Longbow)` **и** `Weapon Focus (Unarmed strike)` два
  независимых ключа сошлись бы оба — «ближний фокус есть» (рукопашный не
  дальнобойный) и «неисключённый фокус есть» (лук), — хотя в игре не годится
  ни один из двух. Фит повторяем, и такой билд собирается без единой правки
  руками.

  Отсюда и отказ: он печатается, когда взятия **были**, а после сужения
  не осталось ни одного — `{:requires_feat_choice_other_than, фит, значения}`.
  Пустое множество до сужения — это «фита нет вовсе», и про это уже сказал
  ключ `feats`.

  ## `proficiency_with_chosen_weapon` — требование к СВОЕМУ выбору

  «proficiency with the chosen weapon» у `Weapon focus` и `Improved critical` —
  единственный ключ, который спрашивает не про чужой фит, а про значение этого
  же взятия. Какой фит владения просит выбранное оружие, знает справочник
  (`Rules.GearWeapon.proficiency/2`), и три его ответа — три разных случая:
  `{:feat, id}` (единственный, который отказывает), `:none_needed` (дубина,
  посох, рукопашный удар — это ответ, а не пропуск) и `:unread` (владения
  не назвал никто; отказать нечем, и билд говорит об этом сам через
  `Rules.FeatChoices.gaps/3`).

  ⚠ **Ответ зависит от ruleset'а, и это состав данных, а не разные правила.**
  У Сиалы владение названо у 42 записей из 47, у ванили ни у одной — её
  собственные категории (simple / martial / exotic) в ruleset не поднимаются.
  Значит на ванили требование сегодня не отказывает никому, и это честнее,
  чем отобрать `Weapon focus` у каждого воина по ненайденному фиту.

  ⚠ Читается `Build.feats_permanent/3` — фит владения с вещи требование фита
  не выполняет (H7). То же владение при этом позволяет взять это оружие
  **в руки** (`Rules.GearWeapon`), потому что там речь про эффект. Два вопроса,
  два ответа, и оба измерены.

  ## `casts_spell_level`: one question for a spontaneous caster, two for the rest

  🔴 **Rewritten twice on 27.08.2026, by two measurements pointing opposite
  ways** (tasks 3.122 and 3.124). «Ability to cast Nth level spells» is answered
  per class, and the answer is yes if **one** casting class in the build clears
  its own version:

    * a **spontaneous** caster — Bard and Sorcerer, and which classes those are
      comes from the ruleset (`Rules.Spells.spontaneous_casters_offered_circle/3`)
      — clears it when his class row **names** the circle at all: a printed `0`
      counts, an empty cell does not. His casting ability is not asked;
    * every **other** caster clears it only by being able to cast the circle:
      the row must give him a real slot (a printed `0` is not one) **and** his
      class's own casting ability must reach 10 + the circle — «in order to
      prepare or cast a known spell, the caster must have both a *base* casting
      ability score and a modified casting ability score of at least 10 + spell
      level» (Fandom «Ability score», revid 71148).

  The exception is one sentence of `fandom:Spell focus` (Notes, revid 69073), and
  **its first two words are the rule**:

  > «**Spontaneous casters ([[bard]]s and [[sorcerer]]s)** can take this feat
  > without being able to cast first level spells as long as their [[class
  > level]] qualifies for at least 0 level one spell slots (that is, even if
  > their casting ability is too low to actually cast a level one spell).»

  ### Four observations, and only one reading survives all four

    1. Bard 4, charisma 11, second-circle cell `0` — the feat **is** offered
       (Dan, `GAME_CHECKS.md` AE1);
    2. Bard 3, no second-circle cell — it is **not** (same measurement);
    3. Bard 9, charisma 11, second-circle cell **3** — the feat **is** held. This
       one is not a measurement but the engine's own `.билд` print
       (`test/fixtures/game_logs/aley.log`);
    4. Wizard 8, intelligence 11, second-circle cell **3** — the feat is **not**
       offered, and neither is the circle (Dan, case AE2).

  Task 3.122 read the sentence without its first two words and dropped the
  ability for all seven casters; observation 4 arrived an hour later and showed
  that as a false **legality** — the direction of error a player cannot discover
  from inside the tool. Task 3.124 put the two words back.

  ⚠ **The alternative reading is named and dead, rather than merely not chosen.**
  Case AE2 offered, for a negative answer, a rule with no spontaneity in it:
  «the row names the circle **and** (the cell is zero **or** the ability reaches
  10 + circle)». It explains 1, 2 and 4 — and is false on 3, where the cell is
  non-zero, the charisma is 11 and the feat is there. «At least 0» is not
  «exactly 0».

  ⚠ **Two halves per class, never crossed between classes.** A Wizard 20 /
  Sorcerer 1 with intelligence 10 and charisma 20 casts nothing above the first
  circle, and asking "some class has the slots" and "some ability is high enough"
  separately would say he casts ninth-circle spells.

  A refusal names whichever half failed: `{:requires_spell_level, n}` when no
  table offers the circle at all, `{:requires_ability, ability, 10 + n}` when a
  prepared caster's table does and his score falls short. One requirement, one
  reason — the second is the more useful of the two, because it is the one the
  player can act on.

  ⚠ A prepared class whose casting ability nothing names goes to `{:missing_data,
  {:casting_ability, class}}` — undecidable, never "fine".

  ## A restriction may belong to the **value**, not to the feat

  Nine feats say «can only be selected when leveling as a barbarian» about
  themselves, and those are handled where they belong — off the class's
  `unavailable_feats`, one ban per class (`Rules.FeatSlots`, the loader's
  `only_on_class_levels`). Two say it about the **value they are taken with**, and
  that cannot go on a class:

  > «*Epic skill focus* in [[animal empathy]] can be taken only when gaining a
  > [[druid]], [[ranger]], or [[shifter]] level. *Epic skill focus* in [[perform]]
  > can be taken only when gaining a [[bard]] level. *Epic skill focus* in [[use
  > magic device]] can be taken only when gaining a [[bard]] or [[rogue]], or
  > [[shadowdancer]] level» — `fandom:Epic skill focus`, Notes.

  Banning the feat on a fighter's levels would be wrong twice over: `Epic skill
  focus (discipline)` is perfectly legal there, and it is *only* the three
  class-restricted skills the sentence talks about. So `only_on_class_levels_for_skill`
  is checked here, where the pick's value is in hand, and the refusal is its own
  form — `{:requires_leveling_as, [classes]}`, not the `{:forbidden_by_class,
  class}` the nine get. The sentence that form stands for would be false: the
  class is not refusing the feat.

  ⚠ Read through `chosen_skill/3`, so it fires only for a feat whose parameter is
  a skill of the ruleset's own dictionary. A domain that is not skills (a weapon)
  needs its own key rather than this one — a key that silently never fires is a
  false legality nobody can see.

  ## Четыре предложения `Skill focus`, и ни одно не выражается соседним (3.104)

  «able to use the skill» — вся строка требований этого фита, и до 25.08.2026
  она лежала в `unparsed`, то есть фит отказывал **всем и на всё**: 28 навыков
  ванили и 29 Сиалы, на любом билде. Расшифровка лежит на той же странице,
  в `Notes`, четырьмя предложениями — и **все четыре разной формы**, поэтому
  ключей тоже четыре (три из них заведены этой задачей, четвёртый —
  `only_on_class_levels_for_skill` — уже стоял у эпического близнеца):

  > «Skill focus in a skill that [[untrained skill check|requires training]] can
  > only be taken if the character is trained in that skill (has at least one
  > [[rank]] in it).» — `chosen_skill_ranks_if_trained_only`

  Требование **к рангам выбранного навыка**, и включает его свойство самого
  навыка (`trained_only?` в словаре ruleset'а), а не список имён: источник
  называет признак, и список из восьми навыков, переписанный сюда руками,
  устарел бы молча в день, когда шард пометит девятый. Отказ —
  `{:requires_chosen_skill_ranks, skill, 1}`, та же форма, которой `Epic skill
  focus` просит свои двадцать.

  > «Skill focus in [[animal empathy]] can be taken only when gaining a [[druid]]
  > or [[ranger]] level, but not a [[shifter]] level. Skill focus in [[use magic
  > device]] can be taken only when gaining a [[bard]] or [[rogue]] level, but
  > not an [[assassin]] level.» — `only_on_class_levels_for_skill`, ключ выше

  > «Skill focus in [[perform]] can be taken when leveling in **any** class, as
  > long as the skill has been made accessible by taking at least one [[bard]]
  > level.» — `class_levels_for_skill`

  🔴 **Третье предложение — ДРУГАЯ ФОРМА, и спутать её со вторым значит соврать
  барду-воину.** Второе — про класс **уровня, который тратит слот**; третье —
  про **состав билда**, и уровень при нём ни при чём: бард 1 / воин 8 берёт
  `Skill focus (Perform)` на воинском уровне законно. `only_on_class_levels_for_skill`
  такого сказать не может (он смотрит на `Build.class_at/2`), а `class_levels`
  рядом не может привязаться к выбранному значению — отсюда третий ключ,
  ровно `class_levels`, но по навыку. Отказ — `{:requires_class_level, :bard, 1}`,
  и новой формы ему не нужно: «нужен бард 1» — ровно та фраза, которую игрок
  может исполнить.

  ⚠ Две страницы одной семьи говорят про `perform` **разное**, и это не опечатка:
  у обычного фокуса навык открывается уровнем барда навсегда, у эпического
  («can be taken only when gaining a bard level») — нет. Поэтому у
  `epic_skill_focus` стоит второй ключ, а у `skill_focus` — третий.

  > «There is no skill focus in [[ride]].» — `no_feat_variant_for_skills`

  Не требование вовсе: **пары просто не существует**, как не существует
  `Favored enemy (Ooze)`. Отказ поэтому `{:invalid_choice, feat, value}` —
  та же форма, которой словарь выбора отбивает значение вне своего домена.
  Ворота домена (`Rules.FeatChoices.domain_gate/0`) сказали бы это красивее,
  но у домена `skill` их нет: он резолвится в словарь самого ruleset'а
  (`{:ruleset, :skills}`), у которого `flags` пуст, а ванильный `skills.json`
  машинный — правка руками исчезла бы при следующем `mix wiki.parse`.

  ⚠ **Список — свойство RULESET'а, а не константа Fandom, и на двух ruleset'ах
  он РАЗНЫЙ** (задачи 3.106 и 3.108). Ваниль запрещает `ride` у обоих фитов
  семьи; на `siala_41` **пусты оба списка** — шард оживил Верховую езду и завёл
  вариант фита вместе с ней, что и измерено дважды (`GAME_CHECKS.md` AB1,
  25.08.2026: «замерил, skill focus - ride присутствует»; AB2, 26.08.2026:
  «замерил, epic skill focus - ride есть»). ⚠ Здесь стояло «у `epic_skill_focus`
  запрет там остаётся… замера на неё нет»: замер пришёл сутками позже и ответил
  то же, но **своим кейсом на своём билде** — на 1-м уровне AB1 эпического фита
  не видел и видеть не мог, а слить два предложения двух страниц в одно правило
  запрещает `perform`, про который они говорят разное. Ни одного имени навыка и
  ни одного ruleset-условия здесь при этом нет и быть не должно — проверка
  читает список, а собирает его слой данных.

  ## `qualifying_class_levels` — the one requirement about **this level's** class

  Six feats say the same two sentences about themselves, word for word:

  > «The actual prerequisite is **not** the ability to cast level 9 spells, but
  > being an [[epic class|epic]] [[cleric]], [[druid]], [[sorcerer]], or
  > [[wizard]], or having at least 15 [[pale master]] levels. Furthermore, this
  > feat **can only be chosen when gaining a level in the qualifying class**» —
  > `fandom:Epic spell: mummy dust` and the five other epic spell pages.

  Two sentences, and the second turns the first into a fact about **the class of
  the level spending the slot** rather than about the character: it is not «the
  build contains an epic wizard somewhere», it is «this level is that wizard's».
  A wizard 21 / cleric 5 may take it on a wizard level and may not on a cleric
  one, and `class_levels` cannot say that — it counts the build, not the level.

  So one key states the whole rule, as a table of «class → levels that qualify»,
  and what is checked is the class of `context.level`: it has to be in the table
  and to have at least the levels the table names for it. Splitting it into two
  keys would be two readers of one sentence, and a build could satisfy each half
  through a **different** class — exactly the false legality the sentence exists
  to forbid.

  A refusal names whichever half failed, the same arrangement `casts_spell_level`
  has: `{:requires_leveling_as, [classes]}` when the level's class is not in the
  table at all, and `{:requires_class_level, class, n}` when it is and falls
  short. The second is the one the player can act on, and neither needed a new
  form — the sentences they stand for are the ones these two forms already say.

  ⚠ The thresholds are **data**, and they are not one number: `fandom:Epic class`
  puts an epic base class at 21 levels and an epic prestige class at 11, while
  these six pages name **15** for Pale Master specifically. Nothing here knows
  either number (CLAUDE.md §3).

  ## `feats` is the one key whose answer depends on **whose** block it is

  One interpreter, two blocks — and exactly one requirement the engine answers
  differently depending on which block asked. A feat lent by a worn item
  satisfies a **class's** `feats`, and does **not** satisfy a **feat's**
  (замер Dan, 14.08.2026, `GAME_CHECKS.md` H7):

  > «фит с вещи не позволит взять другой фит, требующий тот фит, который мы
  > взяли с вещи. Пример, мы взяли expertise с вещи, improve expertise
  > не появится в выборке доступных фитов. А вот сам expertise там будет
  > (т.е. полный игнор фитов с вещи). Но вот КЛАСС можно взять: ВМ требует ряд
  > фитов, и если expertise у нас есть на вещи, то брать его фитом при лвл апе
  > не обязательно.»

  So `requirement_of` is a **required** part of the context, and the caller
  states a fact — whose block this is — rather than a policy. The policy lives
  here, in one place, with the quote beside it: a class reads
  `Build.feats_owned/3`, a feat reads `Build.feats_permanent/3`. A context
  without the key gets `{:missing_data, {:prerequisite, :feats}}` rather than
  either answer, because guessing would be a silent false legality in one
  direction and a silent false illegality in the other.

  ⚠ This is a **narrowing** of the 09.08.2026 rule, not its repeal. A worn
  feat's *effect* is still counted («если фит есть, допустим тафнес, то и HP
  будут увеличены»), it still satisfies a class's requirement, and it still
  fails to make the feat itself unpickable (`Rules.FeatChoices`). Only its role
  as another **feat's** prerequisite is gone.

  ## `abilities` сравнивается с БАЗОВЫМ значением, а не с тем, что в листе

  Второе требование, которое вещи не выполняют, и здесь у него нет двух ответов
  — правило одно на оба блока (Dan, 16.08.2026, `GAME_CHECKS.md` S1):

  > «Сразу могу сказать, что статы с вещей не работают при выборе фитов. Только
  > поинт бай + левел апы, это сразу как факт».

  То же самое, слово в слово, говорит источник — то есть факт стоит не на одном
  только замере: «Items, spells, etc. ("magical means") can further affect
  ability scores, subject to the +12 ability cap… **It is this unmodified score
  (the base score) that matters when meeting the prerequisite of a feat**»
  (`fandom:Ability score`, revid 71148). Там же и состав базового значения:
  поинт-бай, раса, прибавка каждого 4-го уровня и прибавки, которые билд
  зарабатывает сам — фиты семейства `Great …` и таблица Ученика красного
  дракона. Ровно это и есть `stats.abilities_naked`, и ровно это Dan называет
  «поинт бай + левел апы».

  ⚠ Граница проведена источником по «magical means», а не по тому, как фит
  пришёл: `Great strength`, объявленный с вещи, поднимает базовое значение
  и требование выполняет — как выполняет его тот же фит из слота. Провести
  здесь третью линию («фит с вещи не считается и статом») значило бы завести
  правило, которого не говорит никто; H7 выше сужает роль такого фита
  как **пререквизита**, а не его эффект. `# TODO: verify` — измеримо
  (объявить `Great strength` с вещи и посмотреть, открылся ли фит, которому
  недостаёт ровно +1 силы), и до замера мы следуем строке источника.

  ⚠ И ошибка, которую эта правка убрала, была в худшую сторону — в сторону
  **ложной легальности**: требование читало `stats.abilities`, то есть вместе
  с вещами, и полуорк воин 6 / варвар 15 с базовой силой 18 получал
  `Thundering rage` (сила 25) просто за надетый пояс. Такой билд собирается
  до конца и разваливается только в игре, на живом персонаже.

  ⚠ Ни один класс сегодня `abilities` не несёт (проверено обходом обоих
  ruleset'ов: у классов встречаются `alignment`, `any_of`, `base_attack_bonus`,
  `feats`, `qualifiers`, `race`, `skills`). Поэтому у ключа один ответ на оба
  блока, а не пара, как у `feats`: второй ответ был бы догадкой про требование,
  которого не существует. Появится такое требование — вопрос «а классу вещи
  считаются?» задаётся заново, и место для него здесь.

  ## `save_bonus` — то же самое, и по той же причине

  Третье требование, которое вещи не выполняют, и оно закрывает дверь, оставшуюся
  открытой после `abilities` (Dan, 16.08.2026, `GAME_CHECKS.md` S2):

  > «вещи на спасы также не откроют фит, должен быть закрыт».

  ⚠ **Цитаты источника здесь нет** — это `source: user`, слово владельца, и одно
  оно. У характеристик за правилом стоят и замер, и строка Fandom; тут только
  первое, и помечено это честно, а не подпёрто «ну по аналогии же».

  Сравнивается с `stats.saves_for_prereqs` — сейвом персонажа, у которого блок
  «Вещи» пуст. **Вещь добирается до сейва тремя дорогами, и уходят все три:** число,
  вписанное в поле «сейвы»; модификатор характеристики, который подняли предметы
  (`+12 CON` — это +6 к Стойкости); фит, одолженный вещью (`Great fortitude` на
  амулете). Считать первую и оставить вторую значило бы отменить решение S1
  задней дверью: там `+12 CON` требования уже не выполняет, а здесь выполнял бы
  через Стойкость.

  ⚠ Отвергнутое чтение — «вычесть из `fort` то, что вписано в поле „сейвы“».
  Оно короче и **неверно дважды**: мимо него проходят две дороги из трёх, и оно
  ломается о потолок +20 — Spellcraft +8 при вещах +20 даёт после капа те же
  +20, и разность напечатала бы 0 вместо честных 8.

  ⚠ Что требование выполнять **обязано** и выполняет: прибавку от рангов
  Spellcraft, от фитов (`Great fortitude`, эпические сейвы) и от классовых
  умений в форме фита (`Divine grace`, `Sacred defense`). Всё это билд заработал
  сам, снять это нельзя, и Dan назвал вещи, а не «всё, кроме базы».
  ⚠ **Это допущение**, а не прочитанное правило: у характеристик состав базового
  значения назван источником дословно, у сейвов не назван никем.

  ## Одна прибавка требование НЕ выполняет, и это тоже из данных

  ✅ `Luck of heroes` (задача S3, 17.08.2026). Источник исключает его поимённо:
  «The fortitude bonus from ''[[luck of heroes]]'' does not count towards the
  fortitude required» (`fandom:Resist energy`, revid 63837, Notes), и **замер
  Dan подтвердил строку на Сиале**: воин 9 с телосложением 12 и взятой Удачей
  имеет Стойкость 8 при требовании 8 — а фита в игре нет; на 12-м, где базовой
  Стойкости хватает без Удачи, фит есть. До правки мы его предлагали, то есть
  собирали билд, которого не существует.

  ⚠ **Имени фита здесь нет и не будет.** Признак стоит на записи прибавки
  (`feat_save_bonuses.json` → `bonuses[].prerequisite`), рядом со стороной капа
  и по той же причине: строка источника называет один фит из четырнадцати,
  и «прибавки фитов в требование не идут» было бы обобщением цитаты про один
  источник на все источники того же вида — ошибка, на которой уже дважды горели
  потолки сейвов и атаки. Ядро читает признак и не знает, о ком он.

  ⚠ **Чего замер не различает**, и это записано выбором, а не сглажено: «Удача
  не считается ни в каком требовании по сейву» против «требование `Resist
  energy` не считает именно Удачу». Сегодня разницы нет — фит с ключом
  `save_bonus` ровно один, — и выбрано первое, как сформулирован источник
  («The fortitude bonus **from** luck of heroes does not count»). Полный разбор
  — `_prerequisite_decision` в самом файле данных.

  ⚠ И **ещё одна половина той же строки была неверна** до правки S2: комментарий
  у `@save_keys` говорил «feat bonuses to saves are not modelled at all, so there
  is nothing here to exclude yet». С задачи 1.12a они моделируются, и «нечего
  вычитать» перестало быть правдой — а находка, которую этот комментарий
  проглядел, и есть S3 выше.

  ## `save_bonus` сравнивается с сейвом, с которым персонаж ВОШЁЛ в уровень

  Третья правка подряд по одному ключу и последняя из трёх (задача S6,
  17.08.2026). Источник — та же страница, третья строка тех же `Notes`:

  > «The prerequisite for **this feat** must be met **before leveling up**. For
  > example, a (single-class) fighter with constitution 10 cannot take this feat
  > at level 12 (when his fortitude save goes up to +8), but can at any level
  > after this on which he gains a feat» — `fandom:Resist energy`, revid 63837.

  🔴 **Различающий замер.** Первые три наблюдения Dan одинаково хорошо
  объясняла и вторая гипотеза — «требование на самом деле **9**, а состояние
  считается как есть». Развёл их четвёртый билд, воин 9 с телосложением 14
  и без фитов на сейвы: в лист он входит и выходит с восемью, и фит в игре
  **есть**. При требовании 9 его бы не было. Значит требование 8, а хватило
  его потому, что персонаж **входил** в уровень уже с восемью:

      воин  9, CON 12, Luck of heroes  вход 7 (Удача не в счёт)  лист  8  нет
      воин 12, CON 12, Luck of heroes  вход 8                    лист 10  есть
      воин 12, CON 10, без фитов       вход 7                    лист  8  нет
      воин  9, CON 14, без фитов       вход 8                    лист  8  есть

  До правки третья строка получала `:ok` — ложная легальность, и притом
  невидимая: в панели у того воина стоит ровно требуемое число.

  ## Почему правило живёт на КЛЮЧЕ, а не признаком на записи фита

  Источник называет это свойством **фита** («The prerequisite for *this feat*»),
  и `Resist energy` — единственный фит с ключом `save_bonus` во всём справочнике
  (проверено обходом обоих ruleset'ов), так что «правило про сейвы» и «квирк
  этого фита» замером не различаются вовсе. Выбран ключ, и вот почему:

    * **ось здесь — ключ, и это тоже замерено.** `character_level` ведёт себя
      ровно наоборот: «насчет эпик фита на 21 — он доступен сразу, проверил
      на 21 уровне рейнджера» (Dan, 17.08.2026), то есть уровень персонажа
      считается **включая** взятый. Два ключа, два ответа, оба измерены —
      значит «какой снимок персонажа читает требование» есть свойство ключа.
      Этот модуль уже держит такие политики поштучно, только про *какое число*
      (`abilities` → `abilities_naked`, `save_bonus` → `saves_for_prereqs`);
      здесь та же политика на шаг дальше — про *какой момент*;
    * **это не тот случай, что S3.** Там признак ушёл в данные, потому что
      цитата называла **одну запись из четырнадцати однотипных**, и растянуть её
      на весь вид значило бы повторить ошибку, на которой дважды горели потолки.
      Здесь однотипного множества нет вовсе: ключ один, фит один, обобщать
      не на что;
    * **направление ошибки у второго такого фита.** Правило на ключе применится
      к нему само; признак на записи потребовал бы правки данных, а забытая
      правка дала бы **ложную легальность** — худший вид ошибки. Промах правила
      на ключе (если второй фит вдруг проверяется после уровня) даёт ложную
      нелегальность: она видна игроку и он о ней скажет.

  ⚠ Область узкая и расширять её без своего замера **запрещено**:
  `base_attack_bonus`, `abilities`, `class_levels` и `character_level`
  по-прежнему читают состояние ПОСЛЕ взятия уровня. У трёх из четырёх за этим
  стоит замер — `character_level` (эпический фит на 21-м доступен сразу),
  `base_attack_bonus` (S7: `Improved critical` виден на воине 8, где БАБ +8
  приезжает этим самым уровнем) и `abilities` (S9: сила 12→13 на 12-м, и
  `Power attack` сразу же виден). Про `class_levels` не сказано ничего.

  ## Что «вошёл в уровень» значит буквально, и чего это стоит

  Снимок — это `Rules.compute/2` по билду, обрезанному до `уровень - 1`, то есть
  **тот же самый «до», которым считается дельта левелапа** (`Rules`, «Deltas»),
  **плюс прибавка характеристики, записанная на самом взятом уровне** (S7b).
  Двух определений «состояния до уровня» в ядре быть не должно: они разойдутся,
  и игрок увидит одно, а получит другое.

  ⚠ Первая редакция правки (S6) выбрасывала взятый уровень **целиком**, и это
  оказалось слишком грубо. Из четырёх замеров одного дня складывается карта:

      БАБ этого уровня            считается     S7  (Improved critical, воин 8)
      прибавка характеристики     СЧИТАЕТСЯ     S7b (телосложение 11 → 12 на 12-м)
      ранги навыка                нет           S7c (пятый ранг Знания магии на 12-м)
      базовая прогрессия сейва    НЕТ           S6  (воин 12 с телосложением 10)

  То есть из взятого уровня в требование по сейву не попадает **ровно одно** —
  базовая прогрессия сейва, — а прежний снимок выбрасывал заодно и прибавку
  характеристики, отказывая воину, которому игра фит даёт. Ложная нелегальность.

  🔴 **Отвергнутое обобщение, и оно отвергнуто не рассуждением, а замером.**
  S7b выглядел как порядок экранов мастера левелапа: прибавка характеристики
  выбирается **раньше** фитов и к моменту показа списка уже применена — значит,
  считаться должно всё, что раньше фитов, и ранги навыков в том числе. Кейс S7c
  заводился ровно этой гипотезой и её убил: «взял 5 раз навык spellcraft, но
  не повышал CON до 12. Как итог resist energy не доступен». Правило **не про
  порядок мастера, а про конкретное слагаемое**, и следующее слагаемое можно
  внести сюда только своим замером.

  ⚠ Что по-прежнему выпадает из снимка вместе с уровнем и **не измерено**:
  эпический сейв на чётных уровнях 22+, фит, взятый слотом-соседом того же
  уровня, и классовое умение в форме фита, выданное этим уровнем. Все три
  ошибаются в сторону **отказа** — то есть игрок их увидит и скажет.

  ⚠ Отвергнутая альтернатива — «вычесть из сейва этого уровня только его
  базовую прогрессию, остальное оставить как есть». Её прежний довод («вышло бы
  число, которого у персонажа не было ни в один момент») S7b **ослабил**: игра
  сама складывает вход в уровень с прибавкой этого уровня, то есть составные
  числа у неё бывают. Но альтернатива всё равно неверна, и теперь по двум
  доводам покрепче: она оставила бы внутри ранги, купленные на этом уровне,
  а S7c замерил, что их там нет; и собирать сейв арифметикой снаружи
  `Rules.compute/2` значит завести вторую формулу сейва — ровно то, чего это
  ядро не делает нигде. Снимок остаётся снимком: тот же `compute/2` по другому
  персонажу.

  ⚠ Отсюда видимая асимметрия, и она измерена, а не выбрана: ключ `skills`
  считает ранги, купленные **на этом** уровне, а `save_bonus` не видит прибавку
  к сейву от тех же рангов (S7c). Один и тот же ранг открывает фит по ключу
  `skills` и не открывает по ключу `save_bonus` — так в игре.

  ## One thing this refuses to work out

  * **`caster_level`** — nothing under `priv/rules/` states how caster level is
    derived. For a single-class caster it is the class level, but that identity
    is nowhere in the data, and neither is the answer for a multiclass build.
    Pale Master is the case that proves it cannot be guessed: it advances slots
    and *not* caster level, «a level 10 sorcerer / 19 pale master … has a caster
    level of only 10». So the check returns `{:missing_data, {:caster_level, n}}`
    and the feat is not declared legal.
  """

  alias BuildCalculator.Rules.{Attack, Build, FeatChoices, GearWeapon, Spells}

  @type reason ::
          {:feat_disabled, atom()}
          | {:requires_character_level, pos_integer()}
          | {:max_character_level, non_neg_integer()}
          | {:requires_bab, non_neg_integer()}
          | {:requires_race, [atom()]}
          | {:requires_feat, atom()}
          | {:requires_feat_choice, atom(), [atom()]}
          | {:requires_feat_choice_property, atom(), atom(), term()}
          | {:requires_feat_choice_other_than, atom(), [atom()]}
          | {:requires_skill_ranks, atom(), pos_integer()}
          | {:requires_class_level, atom(), pos_integer()}
          | {:requires_ability, atom(), pos_integer()}
          | {:requires_alignment, term()}
          | {:requires_spell_level, non_neg_integer()}
          | {:requires_save_bonus, :fort | :ref | :will, integer()}
          | {:requires_any_skill_ranks, pos_integer()}
          | {:requires_chosen_skill_ranks, atom(), pos_integer()}
          | {:requires_leveling_as, [atom()]}
          | {:requires_any_of, [[reason()]]}
          | {:unknown_feat, atom()}
          | {:missing_data, term()}

  @typedoc """
  Everything a check may look at.

  `level` is the character level the decision belongs to — the level being taken
  for a class, the level a feat is picked on — and `build` is the character as it
  stood at that moment. Keeping the two separate is what makes
  `max_character_level` mean "picked no later than level 1" rather than "the
  build never grew past 1".

  `requirement_of` is **whose block this is** and nothing more — a fact about the
  caller, never a policy. Exactly one key reads it (`feats`), and what it does
  with it is written where the rule is, not where the call is.

  `stats_entering_level` — снимок персонажа на **входе** в тот же уровень
  (`Rules.compute/2` по билду, обрезанному до `level - 1`, **плюс прибавка
  характеристики, записанная на самом уровне** — S7b). Его читает ровно
  один ключ, `save_bonus`, и раздел моддока говорит почему. Ключа нет или он
  `nil` — требование по сейву отвечает `{:missing_data, …}`, а не подставляет
  соседнее число: молчаливый запасной вариант здесь и есть ложная легальность,
  которую задача S6 убирает.
  """
  @type context :: %{
          required(:build) => Build.t(),
          required(:ruleset) => map(),
          required(:stats) => map() | nil,
          required(:level) => non_neg_integer(),
          required(:requirement_of) => :class | :feat,
          optional(:feat) => atom() | nil,
          optional(:chosen_skill) => atom() | nil,
          optional(:chosen_value) => term(),
          optional(:stats_entering_level) => map() | nil
        }

  # The ruleset's own key for the dictionary of skills — not the name of any
  # skill. It is how `chosen_skill/3` recognises that a feat's parameter *is* a
  # skill without this module knowing one by name (CLAUDE.md §3).
  @skill_dictionary :skills

  # Keys are checked in this order so the reason list is stable and reads the way
  # a requirements block is written: the gates on the character first, then what
  # it must own.
  @order [
    :alignment,
    :character_level,
    :max_character_level,
    :base_attack_bonus,
    :save_bonus,
    :caster_level,
    :casts_spell_level,
    :abilities,
    :race,
    :feats,
    # Сразу после `feats` намеренно: сперва «фита нет», потом «фит не тот».
    # Обратный порядок читался бы как «возьми лук» тому, у кого фита нет вовсе.
    :feat_choices,
    # Рядом с `feat_choices` и по той же причине: это тот же вопрос «а с тем ли
    # значением взят фит», только требование названо СВОЙСТВОМ значения,
    # а не списком («weapon focus in a melee weapon»).
    :feat_choice_properties,
    # Третий и последний из ключей про значение — тот же вопрос с обратной
    # полярностью: «вот это значение не засчитывается». Стоит ПОСЛЕ соседей,
    # потому что его отказ печатается только тогда, когда после сужения
    # не осталось ни одного взятия, — то есть когда сказать про свойство
    # уже нечего (моддок, раздел про `feat_choice_excludes`).
    :feat_choice_excludes,
    # Требование к САМОМУ выбору этого фита, а не к чужому: «proficiency with
    # the chosen weapon».
    :proficiency_with_chosen_weapon,
    :skills,
    :any_skill_ranks,
    # Рядом с `any_skill_ranks`, потому что спрашивает ровно то же — ранги
    # ВЫБРАННОГО навыка, — только порог включается свойством навыка, а не
    # стоит числом у всех.
    :chosen_skill_ranks_if_trained_only,
    :class_levels,
    # Сразу за `class_levels`: тот же вопрос к составу билда, но заданный
    # только для одного выбранного значения. Порядок читается как
    # «сперва общее требование к билду, потом то, которое включил выбор».
    :class_levels_for_skill,
    :qualifying_class_levels,
    :only_on_class_levels_for_skill,
    # Последним из ключей по значению: «такого варианта фита нет вовсе» —
    # не требование, а отсутствие пары, и печатать его после требований верно
    # (сперва «чего не хватает», потом «этого не бывает»).
    :no_feat_variant_for_skills,
    :any_of
  ]

  # Ключи, которые читают состояние на ВХОДЕ в уровень, а не после его взятия
  # (задача S6). Список, а не признак на записи фита, — довод в моддоке.
  #
  # 🔴 Ровно один, и дописывать сюда без своего замера запрещено: три соседних
  # ключа **измерены** и ведут себя наоборот — `character_level` (эпический фит
  # доступен на 21-м сразу), `base_attack_bonus` (S7) и `abilities` (S9). Общий
  # механизм «всё считать до уровня» сломал бы и эпические фиты на 21-м, и
  # `Improved critical` на воине 8, и `Power attack` на уровне, где силу подняли
  # до 13. Это главный риск правки, и он под тестом.
  @entering_level_keys [:save_bonus]

  # `qualifiers` is a key of the block and deliberately produces no reason: it is
  # listed here so it is *recognised* rather than silently dropped, and reported
  # by `qualifiers/1` instead.
  #
  # `same_choice_as` is recognised for the same reason and checked somewhere
  # else, of necessity: "spell focus **in the chosen school**" compares the pick
  # being made against a pick already in the build, and a requirement block on
  # its own carries neither. `BuildCalculator.Rules.FeatChoices` has both.
  @keys Map.new([:qualifiers, :same_choice_as | @order], fn key ->
          {Atom.to_string(key), key}
        end)

  @doc """
  Every key of a requirement block this interpreter recognises.

  A feat's block is handed over whole, so nothing filters it; a **class's** is
  normalised by the data layer, which has to know what to keep. That list used to
  be written out there as well, and the two drifted: `any_of` was added here and
  never there, so a class requirement written as a disjunction was dropped before
  it could be checked. One list, read from the module that does the checking.

  ⚠ Recognised is not the same as checked. `qualifiers` is a refinement reported
  through `qualifiers/1`, and `same_choice_as` is compared by
  `BuildCalculator.Rules.FeatChoices`, which only ever looks at feats — a class
  block carrying one would pass through unchecked and unreported. No class does
  today; the day one might, this comment is where the third list belongs.

  ⚠ `only_on_class_levels_for_skill` belongs to the same short list for the same
  reason, one step further: it is checked, but only against a **pick's** chosen
  skill, so on a class's block — which has no pick — it would answer nothing at
  all. No class carries it, and none can usefully: a class is not taken "with"
  a skill.

  ⚠ С задачи 3.104 таких ключей ЧЕТЫРЕ, а не один: рядом стоят
  `chosen_skill_ranks_if_trained_only`, `class_levels_for_skill` и
  `no_feat_variant_for_skills`. Довод у всех тот же и цена ошибки та же —
  ключ, который на блоке класса молча не срабатывает, читался бы как
  проверенный. Ни один класс их не несёт и нести не может.
  """
  @spec keys() :: [atom()]
  def keys, do: @keys |> Map.values() |> Enum.sort()

  @doc """
  Читает ли этот блок требований состояние на **входе** в уровень.

  Вопрос **вызывающего**, а не проверки, и заведён он ради цены: снимок «до
  уровня» — это второй полный `Rules.compute/2` (0,32 мс на билде в 41 уровень),
  а список фитов спрашивает требования у **всех** 310 записей справочника
  на каждую перерисовку. Считать снимок всегда значило бы удвоить самый горячий
  путь ядра ради одного фита из трёхсот десяти — единственного, кто сегодня
  несёт такой ключ.

  ⚠️ Ошибиться этот предикат может **только в сторону отказа**: не увидел ключ —
  проверка получит контекст без снимка и ответит `{:missing_data, {:prerequisite,
  :save_bonus}}`, то есть громко. Тихого «пройдено» у этой ошибки нет.

  Ветки `any_of` разбираются тоже: дизъюнкция несёт целые блоки требований,
  и ключ может лежать внутри ветки — сегодня ни у одного фита не лежит,
  но предикат, который об этом не знает, стал бы молчаливым исключением.
  """
  @spec reads_entering_level?(map() | nil) :: boolean()
  def reads_entering_level?(requirements) when is_map(requirements) do
    Enum.any?(requirements, fn {key, value} ->
      case normalise(key) do
        :any_of -> is_list(value) and Enum.any?(value, &reads_entering_level?/1)
        field -> field in @entering_level_keys
      end
    end)
  end

  def reads_entering_level?(_absent), do: false

  @doc """
  Every unmet requirement in `requirements`, in a stable order.

  `nil` is "the block states nothing" and yields no reasons; whether that means
  "no prerequisites" or "we could not read them" is the caller's to know — see
  `feat/4` and `BuildCalculator.Rules.LevelUp`.
  """
  @spec check(map() | nil, context()) :: [reason()]
  def check(nil, _context), do: []

  def check(requirements, context) when is_map(requirements) do
    pairs =
      for {key, value} <- requirements, field = normalise(key), do: {field, value}

    context = Map.put(context, :excluded_choices, excluded_choices(pairs, context))

    for field <- @order, {^field, value} <- pairs, reason <- one(field, value, context) do
      reason
    end
  end

  # Единственное место, где один ключ блока меняет то, что видит другой, —
  # и это не удобство, а буквальный смысл источника: «этот фокус **не
  # удовлетворяет требованию**», то есть взятие с исключённым значением
  # для этого блока взятием не считается (моддок, `feat_choice_excludes`).
  #
  # ⚠ Накопительно по ветвям `any_of`, а не заново: ветка — это тот же блок,
  # прочитанный дальше, и исключение, объявленное снаружи, действует и внутри.
  # Ни один блок сегодня так не устроен; ветка, которая перестала бы видеть
  # внешнее исключение, стала бы молчаливым исключением из правила.
  defp excluded_choices(pairs, context) do
    outer = Map.get(context, :excluded_choices) || %{}

    Enum.reduce(pairs, outer, fn
      {:feat_choice_excludes, by_feat}, acc when is_map(by_feat) ->
        Enum.reduce(by_feat, acc, fn
          {feat, values}, inner when is_list(values) ->
            ids = MapSet.new(values, &to_atom/1)
            Map.update(inner, to_atom(feat), ids, fn already -> MapSet.union(already, ids) end)

          {_feat, _malformed}, inner ->
            inner
        end)

      _other, acc ->
        acc
    end)
  end

  @doc """
  Whether `feat_id`'s prerequisites are met by `build` at its current level.

  `build` is the character **as it stands on the level the feat is picked on**:
  base attack, ranks and the classes taken all count, because NWN checks a feat
  against the character the level-up has already produced.

  ⚠ Ровно один ключ читает **другой** момент — `save_bonus`, и это измерено
  (задачи S6 и S7b, раздел моддока). Общего правила «всё считать до уровня»
  здесь нет и заводить его нельзя: `character_level`, `base_attack_bonus`
  и `abilities` измерены и читают момент после взятия. Такому вызывающему нужен
  `feat/6`.

  A feat whose prose the parser could not turn into structure at all is refused
  with `{:missing_data, {:feat_prerequisites, id}}` rather than passed. The same
  contract holds for prestige classes, and for the same reason: a feat is never
  silently declared legal. Where the parser read *part* of the block, the part
  it read is checked and the rest travels in `prereqs["unparsed"]`, which this
  reports the same way — the interface may soften it to "не проверено", but the
  core does not pretend.
  """
  @spec feat(Build.t(), atom(), map(), map()) :: :ok | {:error, [reason()]}
  def feat(%Build{} = build, feat_id, ruleset, stats),
    do: feat(build, feat_id, ruleset, stats, nil)

  @doc """
  The same, for a feat being taken **with** a value.

  One requirement in the schema is written about the choice rather than about the
  character: `Epic skill focus` reads «21st level, 20 ranks in **the chosen
  skill**», and the parser can only record it as `any_skill_ranks: 20` because a
  requirement block has no way to point at a pick. Given the pick, it can be
  pointed at one — see `one(:any_skill_ranks, …)`.

  ⚠ `nil`, which is every caller that does not deal in choices, leaves every
  check exactly as it was.

  ## Шестой аргумент — снимок персонажа на входе в уровень

  `stats_entering_level` нужен ровно одному ключу (`save_bonus`, задачи S6
  и S7b), и приходит он **готовым**, а не считается здесь: `Rules.compute/2`
  живёт этажом выше и звать его отсюда значило бы завести цикл между модулем
  расчёта и модулем проверки. Кто считает — тот и решает, надо ли считать вообще
  (`reads_entering_level?/1`), и что именно значит «на входе» — тоже он.

  ⚠ Умолчание `nil` оставляет прежние `feat/4` и `feat/5` рабочими и **не**
  делает требование по сейву «пройденным»: без снимка оно отвечает
  `{:missing_data, …}`. Это сознательно громко — вызывающий, забывший снимок,
  узнает об этом от первого же билда, а не через ложную легальность.
  """
  @spec feat(Build.t(), atom(), map(), map(), term(), map() | nil) ::
          :ok | {:error, [reason()]}
  def feat(build, feat_id, ruleset, stats, choice, stats_entering_level \\ nil)

  def feat(%Build{} = build, feat_id, ruleset, stats, choice, stats_entering_level) do
    case Map.fetch(ruleset.feats, feat_id) do
      :error ->
        {:error, [{:unknown_feat, feat_id}]}

      # Switched off by the shard: the record stays in the dictionary so old
      # shared builds still render its name, but no prerequisite can make it
      # legal. A separate reason from `unknown_feat` on purpose — "this ruleset
      # does not have it" and "this ruleset forbids it" are different sentences.
      {:ok, %{disabled?: true}} ->
        {:error, [{:feat_disabled, feat_id}]}

      {:ok, definition} ->
        context = %{
          build: build,
          ruleset: ruleset,
          stats: stats,
          level: Build.character_level(build),
          # A **feat's** block, which is what makes a worn feat stop counting
          # towards `feats` — see the moduledoc and `one(:feats, …)`.
          requirement_of: :feat,
          # Чей это блок по имени. Читает один ключ — `no_feat_variant_for_skills`,
          # чей отказ называет ПАРУ «фит + значение» («Skill focus в Верховой езде
          # не бывает»), а не одно значение: тот же навык у `Epic skill focus`
          # своя строка источника разрешает или запрещает отдельно.
          feat: feat_id,
          chosen_skill: chosen_skill(definition, choice, ruleset),
          chosen_value: choice,
          # Второй снимок того же персонажа — каким он вошёл в этот уровень
          # (задача S6). Читает его один ключ, `save_bonus`; остальные читают
          # `stats` рядом, и `character_level` среди них — замерено.
          stats_entering_level: stats_entering_level
        }

        case check(definition.prereqs, context) ++ unread(definition) do
          [] -> :ok
          reasons -> {:error, reasons}
        end
    end
  end

  # Which skill the pick names, when the feat's parameter is a skill at all.
  #
  # The link is drawn through the **dictionary the domain resolves to**, never
  # through a domain named in this file: a feat whose parameter is drawn from the
  # ruleset's own skill dictionary is a feat whose parameter is a skill, whatever
  # the shard ends up calling the domain and whichever skills are in it. Nothing
  # here knows a skill by name.
  #
  # ⚠ `nil` — no choice recorded, a feat that takes none, a parameter that is not
  # a skill — leaves `any_skill_ranks` exactly as it was. Until the interface
  # writes choices, no build may become illegal by a rule the data cannot yet
  # express: of the two halves of this contract, the one that removes a false
  # legality lands first and the one that adds refusals waits for its data
  # (HANDOFF, «контракт из двух половин»).
  defp chosen_skill(_definition, nil, _ruleset), do: nil

  defp chosen_skill(definition, choice, ruleset) do
    case choice_dictionary(definition, ruleset) do
      @skill_dictionary -> choice
      _not_a_skill -> nil
    end
  end

  # Из какого словаря ruleset'а фит выбирает значение, или `nil` — фит значения
  # не принимает вовсе.
  defp choice_dictionary(definition, ruleset) do
    domain =
      case Map.get(definition, :repeatable) do
        %{choice: domain} -> domain
        _takes_none -> nil
      end

    case Map.get(Map.get(ruleset, :choice_domains, %{}), domain) do
      %{source: {:ruleset, dictionary}} -> dictionary
      _not_a_ruleset_dictionary -> nil
    end
  end

  # `prereqs: nil` covers both "the page says «none»" and "the page carries no
  # prereq line", so the prose decides which: a real sentence with no structure
  # beside it was not read, and the feat cannot be cleared on it.
  defp unread(definition) do
    prereqs = Map.get(definition, :prereqs)
    raw = Map.get(definition, :prereq_raw)
    id = Map.get(definition, :id)

    stated? = is_map(prereqs) and map_size(prereqs) > 0
    leftover? = is_map(prereqs) and Map.get(prereqs, "unparsed", []) != []

    cond do
      leftover? -> [{:missing_data, {:feat_prerequisites, id}}]
      stated? -> []
      prose?(raw) -> [{:missing_data, {:feat_prerequisites, id}}]
      true -> []
    end
  end

  @doc """
  The refinements of a requirement block that the schema cannot express, as gaps.

  `[{:not_modelled, {:feat_qualifier, :spell_focus, "in the chosen spell school"}}]`
  for a feat; `{:class_qualifier, …}` for a class. Empty for a block with none,
  which is nearly all of them.

  🔴 **Правило одно, и оно двустороннее (задача 3.99): оговорка печатается ровно
  там, где ядро ответить НЕ МОЖЕТ.** Фраза, которую соседний `same_choice_as`
  действительно сравнивает, уходит; фраза, которую он не сравнивает, приходит —
  даже если парсер убрал её из `qualifiers`. Решить это в парсере нельзя:
  сравнивает он или нет, зависит от **ruleset'а** (`Epic weapon focus` повторяем
  на Сиале и не повторяем в ванили), а файл данных читают оба.

  Needed in two places and useless in only one: `Rules.compute/2` folds it into
  `stats.gaps` for what a build took, and **the picker has to caption a feat that
  is offered with a caveat**. Without the second, `qualifiers` is strictly worse
  than the `unparsed` it replaced — the feat used to be refused with "требования
  не разобраны" and would now pass silently. `Rules.feat_caveats/2` is the
  reachable form of this.

  A feat's block carries string keys (raw JSON) and a class's atom keys (the data
  layer normalises those); both are read.
  """
  @spec qualifiers(map() | nil) :: [{:not_modelled, {atom(), atom(), String.t()}}]
  def qualifiers(nil), do: []

  def qualifiers(definition) when is_map(definition) do
    prereqs = requirement_block(definition)
    id = Map.get(definition, :id)
    kind = if Map.has_key?(definition, :prestige?), do: :class_qualifier, else: :feat_qualifier

    texts =
      (is_map(prereqs) && (Map.get(prereqs, "qualifiers") || Map.get(prereqs, :qualifiers))) || []

    texts = same_choice_qualifiers(definition, prereqs, List.wrap(texts))

    for text <- texts, is_binary(text), do: {:not_modelled, {kind, id, text}}
  end

  # Оговорка про «тот же выбор» — ровно там, где выбор НЕ сравнивается, и нигде
  # больше (задача 3.99, разряд 1).
  #
  # `same_choice_as` и фраза `qualifiers` рядом с ним — это ОДНО предложение
  # источника, прочитанное дважды: «[[weapon focus]] **with the chosen weapon**».
  # Парсер оставляет обе половины и записывает связь между ними
  # (`same_choice_quote` — та самая фраза, на которой ключ стоит), потому что
  # решить, работает ключ или нет, он не может: ответ **зависит от ruleset'а**.
  # `Epic weapon focus` повторяем на Сиале и не повторяем в ванили — там
  # требование сравнивается, тут нет, а данные у обоих одни
  # (`vanilla/feats.json` читают оба).
  #
  # 🔴 Поэтому решение здесь, и оно двустороннее:
  #
  #   * ключ РАБОТАЕТ — фраза уходит. Печатать «выбор оружия мы не проверяем»
  #     билду, у которого он проверен, — ложная неопределённость наоборот,
  #     прямо запрещённая CLAUDE.md §6 в том же абзаце, что и её зеркало;
  #   * ключ НЕ работает — фраза печатается, даже если парсер её из `qualifiers`
  #     убрал. Так `Epic spell focus` в ванили молчал про «in the chosen school»
  #     и ничего при этом не проверял: `supersedes` в парсере снимал оговорку
  #     по одному ruleset'у, а файл читают оба.
  #
  # ⚠ Сравнивается **фраза**, а не сам факт наличия ключа: у фита может стоять
  # оговорка про что-то ещё, и её снимать не за что. Совпадение считается
  # по тексту со снятой разметкой `[[…]]` — `qualifiers` парсер уже очистил,
  # `same_choice_quote` хранит сырьё («in the chosen [[spell school]]»), и
  # строгое сравнение не нашло бы `arcane_defense`.
  defp same_choice_qualifiers(definition, prereqs, texts) do
    quote_text =
      is_map(prereqs) &&
        (Map.get(prereqs, "same_choice_quote") || Map.get(prereqs, :same_choice_quote))

    case plain_text(quote_text) do
      nil ->
        texts

      phrase ->
        cond do
          FeatChoices.same_choice_enforced?(definition) -> texts -- [phrase]
          phrase in texts -> texts
          true -> texts ++ [phrase]
        end
    end
  end

  # Викиссылка как её читает игрок: `[[spell school]]` → «spell school`,
  # `[[spell school|school]]` → «school». Ровно то преобразование, которым
  # парсер получил соседнюю строку `qualifiers`, — иначе две половины одного
  # предложения не сравнить.
  defp plain_text(text) when is_binary(text) do
    text
    |> String.replace(~r/\[\[(?:[^\]|]*\|)?([^\]]*)\]\]/u, "\\1")
    |> String.trim()
  end

  defp plain_text(_absent), do: nil

  # A feat keeps its block under `prereqs`, a class under `requirements`. One
  # interpreter reads both (see the module doc), so one accessor does too.
  defp requirement_block(definition) do
    Map.get(definition, :prereqs) || Map.get(definition, :requirements)
  end

  defp prose?(nil), do: false

  defp prose?(raw) when is_binary(raw) do
    String.downcase(String.trim(raw)) not in ["", "none", "-", "n/a"]
  end

  defp prose?(_other), do: false

  defp normalise(key) when is_atom(key), do: if(key in @order, do: key)
  defp normalise(key) when is_binary(key), do: Map.get(@keys, key)
  defp normalise(_other), do: nil

  # ------------------------------------------------------------------ checks --

  defp one(:alignment, nil, _context), do: [{:missing_data, :alignment_requirement}]
  defp one(:alignment, :any, _context), do: []

  # A feat's block is handed over exactly as the parser wrote it, and there the
  # alignment is still the wiki's English phrase — the closed vocabulary that
  # turns it into `%{require: [...]}` belongs to the data layer and is applied
  # to classes only. Reimplementing the table here would be the second
  # implementation this module exists to avoid, so an unnormalised phrase is
  # named rather than parsed.
  defp one(:alignment, phrase, _context) when is_binary(phrase) do
    [{:missing_data, :alignment_requirement}]
  end

  defp one(:alignment, spec, %{build: build}) when is_map(spec) do
    if alignment_matches?(build.alignment, spec), do: [], else: [{:requires_alignment, spec}]
  end

  defp one(:character_level, required, %{level: level}) when is_integer(required) do
    if level >= required, do: [], else: [{:requires_character_level, required}]
  end

  # The first ceiling in the schema: "can only take this feat at 1st level" is a
  # maximum, and every other key here is a minimum. It is checked against the
  # level the feat is picked on, never against how far the build eventually got.
  defp one(:max_character_level, ceiling, %{level: level}) when is_integer(ceiling) do
    if level <= ceiling, do: [], else: [{:max_character_level, ceiling}]
  end

  defp one(:base_attack_bonus, required, %{stats: %{base_attack: bab}})
       when is_integer(required) do
    if bab >= required, do: [], else: [{:requires_bab, required}]
  end

  # "fortitude save bonus +8" (`resist_energy`). Сравнивается с
  # `saves_for_prereqs` — сейвом персонажа без блока «Вещи», из которого вычтено
  # ещё и то, что источник исключил поимённо. См. раздел моддока: цитата Dan про
  # вещи, три дороги, которыми вещь до сейва добирается, отвергнутое «итог минус
  # вещи» и замер S3 про `Luck of heroes`.
  #
  # ⚠ Модификатор характеристики в число входит, и это не наш вывод: пример
  # источника («a (single-class) fighter with constitution 10 cannot take this at
  # level 12») работает только если телосложение считается. Входит именно
  # **голый** модификатор — тот, что был до вещей, ровно как у `abilities` рядом.
  @save_keys %{
    "fortitude" => :fort,
    "fort" => :fort,
    "reflex" => :ref,
    "ref" => :ref,
    "will" => :will
  }

  # 🔴 Снимок берётся `stats_entering_level`, а не `stats`: требование по сейву
  # сравнивается с тем, с чем персонаж ВОШЁЛ в уровень (задача S6, замер Dan
  # 17.08.2026), но прибавка характеристики этого уровня в снимок входит (S7b).
  # Это единственный ключ, читающий такой момент: `character_level`,
  # `base_attack_bonus` и `abilities` замерены и читают противоположный —
  # состояние СЧИТАЯ взятый уровень.
  #
  # ⚠ Матчится ещё и `saves_for_prereqs` внутри снимка, а не снимок целиком:
  # контекст без любой из двух половин падает в общий разбор и получает
  # `{:missing_data, {:prerequisite, :save_bonus}}`. Молча взять `stats`, или
  # `fort`/`ref`/`will`, или соседнее `saves_naked` запасным вариантом нельзя:
  # это ровно та ложная легальность, которую убирают правки S2, S3 и S6,
  # и она была бы не видна никому.
  defp one(:save_bonus, saves, %{stats_entering_level: %{saves_for_prereqs: counted}})
       when is_map(saves) do
    # `flat_map` and not a comprehension: an unknown save name yields a reason
    # rather than nothing, and a comprehension filter would swallow exactly that
    # case — the one this has to report.
    saves
    |> Enum.sort()
    |> Enum.flat_map(fn {save, required} -> save_reason(save_key(save), required, counted) end)
  end

  # "20 ranks in **the chosen skill**" (`epic_skill_focus`), and the emphasis is
  # the rule: the ranks that count are the chosen skill's, not any skill's. Дан
  # confirmed the feat is taken once per skill and the requirement is about that
  # skill (02.08.2026).
  #
  # Without this the hole is real and one-directional: a character with 20 ranks
  # of Hide could take the feat on a skill with no ranks at all, and the
  # requirement would read as checked. It is the same shape of link as
  # `same_choice_as` and a different one — that binds a pick to another *feat's*
  # pick, this binds it to a **rank**, so it is checked here, where the ranks are.
  defp one(:any_skill_ranks, required, %{chosen_skill: skill, build: build})
       when is_integer(required) and not is_nil(skill) do
    if Build.skill_ranks(build, skill, Build.character_level(build)) >= required,
      do: [],
      else: [{:requires_chosen_skill_ranks, skill, required}]
  end

  # No choice to bind it to: the requirement is on *some* skill and not on a
  # named one, and checking it exactly as written is all that can honestly be
  # done. Anything else would be inventing which.
  defp one(:any_skill_ranks, required, %{build: build}) when is_integer(required) do
    level = Build.character_level(build)

    bought =
      for {lv, ranks} <- build.skills, lv <= level, {skill, _} <- ranks, uniq: true, do: skill

    if Enum.any?(bought, &(Build.skill_ranks(build, &1, level) >= required)),
      do: [],
      else: [{:requires_any_skill_ranks, required}]
  end

  # Not "class level, probably". See the module doc.
  defp one(:caster_level, required, _context) when is_integer(required) do
    [{:missing_data, {:caster_level, required}}]
  end

  defp one(:casts_spell_level, circle, %{build: build, ruleset: ruleset} = context)
       when is_integer(circle) do
    # A prepared caster is asked the casting question in full, so the reading
    # here is the strict one: a cell of `0` is not a slot.
    prepared = Spells.casters_for_circle(build, ruleset, circle)

    cond do
      # The exception, and it belongs to two classes rather than to seven — see
      # the moduledoc. A spontaneous caster whose row names the circle passes
      # whatever the cell prints and whatever his ability is.
      Spells.spontaneous_casters_offered_circle(build, ruleset, circle) != [] ->
        []

      prepared != [] ->
        casts_with_ability(prepared, Spells.minimum_ability_score(ruleset, circle), context)

      # No table names the circle — but one might have, had the build not held
      # a prestige class whose host could not be picked. Saying "you cannot cast
      # it" there would be stating as fact the thing we could not work out.
      Spells.advancement(build, ruleset).undecided != [] ->
        [{:missing_data, {:caster_advancement, hd(Spells.advancement(build, ruleset).undecided)}}]

      true ->
        [{:requires_spell_level, circle}]
    end
  end

  # A context carrying no build or no ruleset cannot be answered at all. Kept as
  # the same kind of refusal the other keys give a context they cannot read: a
  # caller assembling a partial context must get "cannot answer", never the
  # table's silence read as a pass.
  #
  # ⚠ The abilities are read one level down (`casts_with_ability/3`) and not in
  # this head, because half of this key does not need them: a spontaneous caster
  # is decided by the build and the ruleset alone, and demanding a stats snapshot
  # for him would turn a measured legality into `{:missing_data, …}`.
  defp one(:casts_spell_level, circle, _context) when is_integer(circle) do
    [{:missing_data, {:prerequisite, :casts_spell_level}}]
  end

  # `abilities_naked`, а не `abilities`: требование сравнивается с базовым
  # значением, вещи в него не входят (см. раздел моддока — цитата Dan и цитата
  # источника). Читается именно то поле, которое интерфейс уже показывает
  # отдельным числом, — иначе отказ «нужен STR 25» не сходился бы ни с одной
  # строкой на экране.
  #
  # ⚠ Поля нет в контексте — падаем в общий разбор ниже и получаем
  # `{:missing_data, {:prerequisite, :abilities}}`. Молча взять `abilities`
  # запасным вариантом нельзя: это ровно та ложная легальность, которую правка
  # и убирает, и она была бы не видна никому.
  #
  # TODO: verify — `Great strength`, объявленный с ВЕЩИ, поднимает базовое
  # значение и требование выполняет. Это строка источника («magical means» —
  # предметы и заклинания, а фит в базовом значении), а не замер; кейс S1b
  # в `GAME_CHECKS.md`.
  defp one(:abilities, abilities, %{stats: %{abilities_naked: scores}})
       when is_map(abilities) do
    for {ability, required} <- Enum.sort(abilities),
        id = to_atom(ability),
        Map.get(scores, id, 0) < required do
      {:requires_ability, id, required}
    end
  end

  defp one(:race, races, %{build: build}) when is_list(races) do
    allowed = Enum.map(races, &to_atom/1)
    if build.race in allowed, do: [], else: [{:requires_race, allowed}]
  end

  # A **class's** `feats`: `feats_owned/3` — the feat counts however it arrived.
  # Siala grants Toughness to every martial class at level 1, and Dwarven
  # Defender requires Toughness, so asking a Fighter to take it again would lock
  # him out of a class he qualifies for. A worn **item** is a third such route
  # (`Rules.GearFeats`), and the shard's own builds rely on it: Dan's opens
  # Weapon Master on character level 14 with `Expertise` off armour and
  # `Whirlwind attack` off a quarterstaff, and picks both in slots only later, to
  # take those items off (замер 14.08.2026, `GAME_CHECKS.md` H7).
  defp one(:feats, feats, %{requirement_of: :class} = context) when is_list(feats) do
    %{build: build, ruleset: ruleset} = context
    unmet(feats, Build.feats_owned(build, ruleset, Build.character_level(build)))
  end

  # A **feat's** `feats`: `feats_permanent/3` — slots and class grants, and
  # nothing an item lends. «Improve expertise не появится в выборке доступных
  # фитов… полный игнор фитов с вещи» (Dan, 14.08.2026). The engine simply does
  # not look at worn feats when it builds the pick list, so `Improved expertise`
  # is refused with the plain `{:requires_feat, :expertise}` every other unmet
  # feat requirement gets — the reason is what is *needed*, and what is needed is
  # the feat, permanently.
  #
  # ⚠ The two halves of the measurement are opposite and both are load-bearing;
  # a single reading of `feats` would get one of them wrong whichever it chose.
  defp one(:feats, feats, %{requirement_of: :feat} = context) when is_list(feats) do
    %{build: build, ruleset: ruleset} = context
    unmet(feats, Build.feats_permanent(build, ruleset, Build.character_level(build)))
  end

  # No `requirement_of` in the context: the requirement is real and cannot be
  # answered, so it is named. Defaulting either way would be silent — to
  # `feats_owned` a false legality, to `feats_permanent` a false illegality — and
  # a check that quietly picks a side is what this module exists to avoid.
  defp one(:feats, feats, _context) when is_list(feats) do
    [{:missing_data, {:prerequisite, :feats}}]
  end

  # «Weapon Focus (Короткий лук, Длинный лук, Малый арбалет или Большой
  # арбалет)» — требование не к фиту, а к ЗНАЧЕНИЮ, с которым он взят. Раздел
  # моддока объясняет, почему это отдельный ключ рядом с `feats`, а не вместо
  # него, и почему незаписанное значение здесь молчит, а не отказывает.
  #
  # ⚠ `requirement_of` этот ключ не читает, и это не забывчивость: у `feats`
  # два ответа потому, что вещь фит ОДАЛЖИВАЕТ, а здесь спрашивается значение,
  # которого у вещи нет ни в каком случае (`Rules.GearFeats` — объявление это
  # переключатель, оружия оно не называет). Разные ответы взять было бы неоткуда.
  defp one(:feat_choices, by_feat, %{requirement_of: whose} = context) when is_map(by_feat) do
    seen = seen(context, whose)

    by_feat
    |> Enum.sort()
    |> Enum.flat_map(&feat_choice_reasons(&1, seen))
  end

  # Тот же довод, что у `feats` выше: чей это блок — факт вызывающего, и без
  # него ответа нет. ⚠ До 3.99 ключ `requirement_of` не читал вовсе, и довод
  # был записан прямо здесь: «у вещи значения нет ни в каком случае».
  # Задача 3.97 это сняла — объявленный с вещи фит теперь несёт записанное
  # значение, — и молчаливое чтение только слотов стало означать, что
  # `Weapon Focus (Longbow)` с вещи открывает Мастера оружия без единой проверки.
  defp one(:feat_choices, by_feat, _context) when is_map(by_feat) do
    [{:missing_data, {:prerequisite, :feat_choices}}]
  end

  # «[[weapon focus]] in a [[melee weapon]]» — требование к значению, названное
  # его СВОЙСТВОМ, а не списком. Список тут был бы вторым экземпляром словаря:
  # 39 имён оружия, переписанных руками, устаревают молча в тот день, когда шард
  # добавит сороковое. Свойство читается с записи справочника, и ни одного имени
  # оружия в этом модуле нет.
  #
  # ⚠ Молчание при незаписанном значении — та же политика, что у `feat_choices`
  # (раздел моддока), и по той же причине.
  defp one(:feat_choice_properties, by_feat, %{requirement_of: whose} = context)
       when is_map(by_feat) do
    seen = seen(context, whose)

    by_feat
    |> Enum.sort()
    |> Enum.flat_map(&feat_choice_property_reasons(&1, seen))
  end

  defp one(:feat_choice_properties, by_feat, _context) when is_map(by_feat) do
    [{:missing_data, {:prerequisite, :feat_choice_properties}}]
  end

  # «Этот фокус не удовлетворяет требованию» — значение, которое требование
  # НЕ ЗАСЧИТЫВАЕТ, названное источником поимённо. Раздел моддока объясняет,
  # почему перечисление, а не свойство, и почему исключение сужает то, что
  # видят соседние ключи, а не проверяется отдельно от них.
  #
  # ⚠ Здесь — и только здесь — берутся СЫРЫЕ взятия, до сужения: ключ и есть
  # тот, кто про сужение отвечает. Отказ печатается ровно тогда, когда взятия
  # были, а после сужения не осталось ни одного; пустое множество до сужения —
  # это «фита нет вовсе», и об этом уже сказал ключ `feats`.
  defp one(:feat_choice_excludes, by_feat, %{requirement_of: whose} = context)
       when is_map(by_feat) do
    seen = seen(context, whose)

    by_feat
    |> Enum.sort()
    |> Enum.flat_map(&feat_choice_exclude_reasons(&1, seen))
  end

  defp one(:feat_choice_excludes, by_feat, _context) when is_map(by_feat) do
    [{:missing_data, {:prerequisite, :feat_choice_excludes}}]
  end

  # «proficiency with the chosen weapon» — требование НЕ к чужому фиту, а к
  # выбору этого же взятия: `Weapon focus` и `Improved critical` просят владение
  # тем оружием, которое названо в них самих (`fandom:Weapon focus`, revid 70066;
  # `fandom:Improved critical`, revid 62341; и слово Dan 25.08.2026 — «без
  # владения клинковым improved critical на всякие мечи не взять»).
  #
  # 🔴 Какой фит просит это оружие — знает справочник, и спрашивается он одной
  # функцией на весь проект (`Rules.GearWeapon.proficiency/2`). Владеет ли им
  # персонаж — вопрос уже НЕ общий: там речь про оружие в руках, то есть
  # про эффект, и владение с вещи его открывает; здесь — пререквизит фита,
  # и фит с вещи его не выполняет (замер Dan 14.08.2026, H7). Поэтому читается
  # `feats_permanent/3`, а не `feats_owned/3`.
  #
  # ⚠ Три ответа справочника, и все три разные:
  #
  #   * `{:feat, id}` — единственный, который может отказать;
  #   * `:none_needed` — владения не требует вовсе (дубина, посох, рукопашный
  #     удар; замер Dan 16.08.2026). Это ответ, а не пропуск;
  #   * `:unread` — владения не назвал никто. Отказать нельзя: у ванильного
  #     ruleset'а так почти всё оружие, и отказ отобрал бы `Weapon focus`
  #     у каждого. Билд говорит об этом сам — `Rules.FeatChoices.gaps/3`.
  # ⚠ Значение берётся СЫРЫМ, без «а точно ли это оружие»: судья — сам
  # справочник. Ключ утверждает, что параметр фита оружие, и запись, у которой
  # это не так, получает `{:missing_data, …}` громко, а не молчит. Молчаливый
  # промах здесь был бы ложной легальностью, которую никто не увидит, — ровно
  # та ловушка, о которой предупреждает `chosen_skill/3` этажом ниже.
  defp one(:proficiency_with_chosen_weapon, true, %{chosen_value: weapon} = context)
       when is_atom(weapon) and not is_nil(weapon) do
    %{build: build, ruleset: ruleset, requirement_of: whose} = context

    case GearWeapon.proficiency(ruleset, weapon) do
      {:feat, feat_id} ->
        unmet([feat_id], held_feats(build, ruleset, whose))

      :unknown_weapon ->
        [{:missing_data, {:prerequisite, :proficiency_with_chosen_weapon}}]

      _none_needed_or_unread ->
        []
    end
  end

  # Значения нет — сравнивать не с чем; ключ со значением, которое не `true`, —
  # запись недописана, и это называется, а не пропускается.
  defp one(:proficiency_with_chosen_weapon, true, _context), do: []

  defp one(:proficiency_with_chosen_weapon, _malformed, _context) do
    [{:missing_data, {:prerequisite, :proficiency_with_chosen_weapon}}]
  end

  defp one(:skills, skills, %{build: build}) when is_map(skills) do
    level = Build.character_level(build)

    for {skill, required} <- Enum.sort(skills),
        id = to_atom(skill),
        Build.skill_ranks(build, id, level) < required do
      {:requires_skill_ranks, id, required}
    end
  end

  defp one(:class_levels, classes, %{build: build}) when is_map(classes) do
    taken = Build.class_levels(build)

    for {class, required} <- Enum.sort(classes),
        id = to_atom(class),
        Map.get(taken, id, 0) < required do
      {:requires_class_level, id, required}
    end
  end

  # «being an epic cleric, druid, sorcerer, or wizard, or having at least 15 pale
  # master levels … this feat can only be chosen when gaining a level in the
  # qualifying class» — the two sentences the six epic spell feats carry, read as
  # the one condition they amount to. See the module doc.
  #
  # The class asked about is the one **this level** belongs to, so the answer
  # moves with the level a feat is picked on and not with what the build holds
  # somewhere else. `class_levels` right above is the same shape and the opposite
  # fact — that one counts the whole build and does not care which level spends
  # the slot.
  defp one(:qualifying_class_levels, thresholds, %{build: build, level: level})
       when is_map(thresholds) and map_size(thresholds) > 0 do
    class = Build.class_at(build, level)

    case class && threshold(thresholds, class) do
      # Not a qualifying class — or no class at all, which a build asked about
      # past the end of its own ladder has. Both are "this level cannot spend a
      # slot on it", and the classes that could are what the player needs told.
      nil ->
        [{:requires_leveling_as, thresholds |> Map.keys() |> Enum.map(&to_atom/1) |> Enum.sort()}]

      required when is_integer(required) ->
        if Build.class_level_at(build, level) >= required,
          do: [],
          else: [{:requires_class_level, class, required}]

      # A threshold that is not a number: the requirement is real and cannot be
      # checked, the same as every other malformed value here.
      _malformed ->
        [{:missing_data, {:prerequisite, :qualifying_class_levels}}]
    end
  end

  # «*Epic skill focus* in [[perform]] can be taken only when gaining a [[bard]]
  # level» — a restriction on the level that spends the slot, keyed by the value
  # the feat is taken with. See the module doc for why it is neither a class ban
  # nor `{:forbidden_by_class, …}`.
  #
  # The skill decides whether there is a rule at all: the three class-restricted
  # skills have one, the other twenty-six do not, and a pick naming one of those
  # is as legal on a fighter's level as anywhere.
  defp one(:only_on_class_levels_for_skill, by_skill, %{chosen_skill: skill} = context)
       when is_map(by_skill) and not is_nil(skill) do
    case allowed_classes(by_skill, skill) do
      :none ->
        []

      {:ok, allowed} ->
        if Build.class_at(context.build, context.level) in allowed,
          do: [],
          else: [{:requires_leveling_as, allowed}]

      # A value stated and unreadable is a restriction that exists and is not
      # checked — named, never skipped, the same as every other malformed key here.
      :error ->
        [{:missing_data, {:prerequisite, :only_on_class_levels_for_skill}}]
    end
  end

  # No value in hand — either the caller deals in no choices at all, or the
  # interface is still on the first step of the two (`Builder.Feats`: the feat row
  # is offered, and each value is asked about separately once it is picked). The
  # restriction is about the value, so with no value there is nothing to refuse;
  # the pair is checked the moment one is named, which is before it can reach a
  # build.
  defp one(:only_on_class_levels_for_skill, by_skill, _context) when is_map(by_skill), do: []

  # «Skill focus in a skill that requires training can only be taken if the
  # character is trained in that skill (has at least one rank in it)»
  # — `fandom:Skill focus`, Notes.
  #
  # Порог включает СВОЙСТВО выбранного навыка, а не список его имён: источник
  # говорит «a skill that requires training», и восемь имён, переписанных
  # в требование, устарели бы молча в день, когда шард пометит девятое.
  # Признак читается из словаря ruleset'а (`skills[id].trained_only?`), то есть
  # ни одного имени навыка в этом модуле по-прежнему нет (CLAUDE.md §3).
  #
  # ⚠ Ранги, а не значение навыка, и это та же страница: «The bonus from this
  # feat does not help meet prerequisites». `Build.skill_ranks/3` — то, что
  # игрок купил; прибавка фита падает в значение и сюда не доходит по
  # построению, а не по отдельной оговорке.
  defp one(:chosen_skill_ranks_if_trained_only, required, %{chosen_skill: skill} = context)
       when is_integer(required) and not is_nil(skill) do
    if trained_only?(context.ruleset, skill) do
      one(:any_skill_ranks, required, context)
    else
      []
    end
  end

  # Значения нет — сравнивать не с чем, ровно как у соседнего ключа по значению.
  # Молчание здесь безопасно в одну сторону: пара проверяется в тот момент,
  # когда значение названо, а это раньше, чем она попадёт в билд.
  defp one(:chosen_skill_ranks_if_trained_only, required, _context)
       when is_integer(required),
       do: []

  # «Skill focus in [[perform]] can be taken when leveling in any class, as long
  # as the skill has been made accessible by taking at least one [[bard]] level»
  # — `fandom:Skill focus`, Notes.
  #
  # 🔴 Соседний `only_on_class_levels_for_skill` сказал бы это НЕВЕРНО: он
  # смотрит на класс уровня, который тратит слот, а источник говорит про состав
  # билда («by taking at least one bard level»). Бард 1 / воин 8 берёт
  # `Skill focus (Perform)` на воинском уровне, и запретить это значило бы
  # выдумать правило, которого источник не пишет.
  defp one(:class_levels_for_skill, by_skill, %{chosen_skill: skill} = context)
       when is_map(by_skill) and not is_nil(skill) do
    case Map.get(by_skill, skill) || Map.get(by_skill, Atom.to_string(skill)) do
      nil -> []
      classes when is_map(classes) -> one(:class_levels, classes, context)
      _malformed -> [{:missing_data, {:prerequisite, :class_levels_for_skill}}]
    end
  end

  defp one(:class_levels_for_skill, by_skill, _context) when is_map(by_skill), do: []

  # «There is no skill focus in [[ride]]» / «There is no *epic skill focus* in
  # [[ride]]» — `fandom:Skill focus` и `fandom:Epic skill focus`, Notes.
  #
  # Не требование: пара «фит + значение» не существует, как не существует
  # `Favored enemy (Ooze)`. Поэтому и форма отказа та же, что у словаря выбора,
  # — `{:invalid_choice, feat, value}`, — а не «чего-то не хватает».
  #
  # ⚠ Ключ по НАВЫКУ, а не по фиту: список у каждого фита свой, и в этой семье
  # он уже разошёлся бы, начнись он с одной строки — обе страницы называют
  # `ride`, но остальные ограничения у них разные.
  defp one(:no_feat_variant_for_skills, skills, %{chosen_skill: skill} = context)
       when is_list(skills) and not is_nil(skill) do
    excluded = for id <- skills, into: MapSet.new(), do: to_atom(id)

    if MapSet.member?(excluded, skill),
      do: [{:invalid_choice, Map.get(context, :feat), skill}],
      else: []
  end

  defp one(:no_feat_variant_for_skills, skills, _context) when is_list(skills), do: []

  defp one(:any_of, [_ | _] = branches, context) do
    per_branch = Enum.map(branches, &check(&1, context))

    if Enum.any?(per_branch, &(&1 == [])),
      do: [],
      else: [{:requires_any_of, per_branch}]
  end

  # A malformed value is not the same as an absent key: the requirement is
  # really there and really unchecked, so it is named rather than dropped.
  defp one(field, _value, _context), do: [{:missing_data, {:prerequisite, field}}]

  # The second half of "able to cast Nth level spells", asked of each PREPARED
  # class whose table reaches the circle.
  #
  # `nil` for the minimum is the hand-written file that states it («10 + spell
  # level») being absent. The ruleset already carries `{:missing_file, …}` for
  # that, and turning one missing file into a refusal on every caster in the game
  # would be the loudest possible way to report the quietest possible problem.
  #
  # ⚠ Restored on 27.08.2026 (task 3.124) after task 3.122 removed it the same
  # day. It was never wrong — it was applied to the wrong set: the source grants
  # the exception to spontaneous casters, and a Wizard 8 with intelligence 11 is
  # refused `Empower Spell` in the game exactly the way this half refuses him.
  defp casts_with_ability(_casters, nil, _context), do: []

  defp casts_with_ability(casters, minimum, %{stats: %{} = stats}) do
    case ability_scores(stats) do
      # A snapshot with no abilities in it at all is not a character with zeroes;
      # it is a caller who did not compute them, and refusing on it would be a
      # made-up number the player could not see.
      :none ->
        [{:missing_data, {:prerequisite, :casts_spell_level}}]

      scores ->
        known =
          for %{class: c, ability: a} <- casters, a != nil, do: {c, a, Map.get(scores, a, 0)}

        unknown = for %{class: c, ability: nil} <- casters, do: c

        cond do
          Enum.any?(known, fn {_class, _ability, score} -> score >= minimum end) ->
            []

          # A caster whose ability nothing names cannot be cleared and cannot be
          # refused either. Named, so the build says which class it is.
          unknown != [] ->
            [{:missing_data, {:casting_ability, unknown |> Enum.sort() |> hd()}}]

          true ->
            # The nearest miss, so the reason is the one the player can act on.
            # The class id breaks ties, which keeps the answer stable.
            {_class, ability, _score} =
              Enum.min_by(known, fn {class, _ability, score} -> {minimum - score, class} end)

            [{:requires_ability, ability, minimum}]
        end
    end
  end

  # No snapshot of the character in the context, so the half cannot be asked.
  # Answering "fine" here is the false legality this module exists to avoid, and
  # it is the very shape task 3.122 produced for a whole day.
  defp casts_with_ability(_casters, _minimum, _context),
    do: [{:missing_data, {:prerequisite, :casts_spell_level}}]

  # Both the base score and the modified one must clear the bar, so what is
  # compared is the smaller. Gear only adds today, which makes the base the
  # binding one — but reading both is what keeps a future penalty from passing
  # through unnoticed.
  #
  # ⚠ Правило СВОЁ, а не копия соседнего `abilities`, и написано оно по своей
  # цитате («both a base … and a modified … score»). Сегодня оба пути дают одно
  # и то же число — вещи только прибавляют, значит меньшее и есть базовое, — но
  # свести их в один читатель нельзя: там требование стоит на базовом значении,
  # здесь на обоих сразу, и день, когда с вещей придёт штраф, разведёт ответы.
  #
  # ⚠ Отсутствующая половина не читается как ноль: у снимка, в котором есть
  # только одна из двух карт, сравнивается та, что есть. Ноль вместо
  # неизвестного дал бы отказ там, где мы просто не посмотрели.
  defp ability_scores(stats) do
    naked = Map.get(stats, :abilities_naked)
    geared = Map.get(stats, :abilities)

    base = if is_map(naked) and map_size(naked) > 0, do: naked
    final = if is_map(geared) and map_size(geared) > 0, do: geared

    case {base, final} do
      {nil, nil} ->
        :none

      {base, final} ->
        both = base || final
        other = final || base

        Map.new(both, fn {ability, score} ->
          {ability, min(score, Map.get(other, ability, score))}
        end)
    end
  end

  # Keys arrive as strings from a feat's block and as atoms from a class's, the
  # same as everywhere else in this module.
  defp threshold(thresholds, class) do
    Map.get(thresholds, class) || Map.get(thresholds, Atom.to_string(class))
  end

  # Keys arrive as strings from a feat's block and as atoms from a class's, the
  # same as everywhere else here. `:none` is "this value carries no restriction",
  # which is not the same as an empty list of classes ("no level may take it") —
  # that one is a real, if absurd, restriction and refuses everybody.
  # Требует ли навык тренировки — по словарю ruleset'а, а не по списку имён.
  # Навык, которого в словаре нет вовсе, тренировки не требует: отказать
  # по ненайденной записи значило бы придумать правило про навык, о котором
  # у нас нет ничего.
  defp trained_only?(ruleset, skill) do
    case Map.get(Map.get(ruleset, :skills, %{}), skill) do
      %{trained_only?: trained?} -> trained? == true
      _unknown -> false
    end
  end

  defp allowed_classes(by_skill, skill) do
    case Map.get(by_skill, skill) || Map.get(by_skill, Atom.to_string(skill)) do
      nil -> :none
      classes when is_list(classes) -> {:ok, Enum.map(classes, &to_atom/1)}
      _malformed -> :error
    end
  end

  # Фиты, которые персонаж держит «для этого блока» — та же линия H7, что
  # у `one(:feats, …)`, и проведена она тем же ключом. Отдельной функцией
  # потому, что читателей стало двое: сам ключ `feats` и требование владения
  # выбранным оружием.
  defp held_feats(build, ruleset, :class),
    do: Build.feats_owned(build, ruleset, Build.character_level(build))

  defp held_feats(build, ruleset, _feat),
    do: Build.feats_permanent(build, ruleset, Build.character_level(build))

  # The half of `feats` that is the same for both blocks. Which set is handed in
  # is the whole of the difference, and it is decided one clause up, where the
  # measurement is quoted.
  defp unmet(feats, held) do
    for feat <- Enum.map(feats, &to_atom/1), not MapSet.member?(held, feat) do
      {:requires_feat, feat}
    end
  end

  # Одна пара «фит → допустимые значения». Пустой список значений запрещён
  # намеренно: он означал бы «этот фит нельзя взять ни с чем», а такого
  # требования не пишет ни один источник, — куда вероятнее, что запись
  # недописана, и молча пропустить её значит потерять требование целиком.
  defp feat_choice_reasons({feat, allowed}, seen) when is_list(allowed) and allowed != [] do
    id = to_atom(feat)
    values = Enum.map(allowed, &to_atom/1)
    recorded = qualifying_choices(seen, id)

    cond do
      recorded == [] -> []
      Enum.any?(recorded, &(&1 in values)) -> []
      true -> [{:requires_feat_choice, id, values}]
    end
  end

  # Значение, которое схема прочитать не может: требование настоящее и
  # непроверенное — называем, а не роняем, как и всякий кривой ключ здесь.
  defp feat_choice_reasons({_feat, _malformed}, _seen) do
    [{:missing_data, {:prerequisite, :feat_choices}}]
  end

  # Одна пара «фит → свойства, которые обязано иметь его значение». Свойств
  # может быть несколько, и это КОНЪЮНКЦИЯ — в отличие от списка значений
  # у `feat_choices`, который дизъюнкция: «одно из этих значений» и «со всеми
  # этими свойствами» — разные утверждения источника.
  defp feat_choice_property_reasons({feat, properties}, seen)
       when is_map(properties) and map_size(properties) > 0 do
    id = to_atom(feat)
    recorded = qualifying_choices(seen, id)

    if recorded == [] do
      []
    else
      for {property, required} <- Enum.sort(properties),
          key = to_atom(property),
          verdict = choice_property_verdict(recorded, key, required, seen.ruleset),
          verdict != :ok do
        case verdict do
          :unreadable -> {:missing_data, {:prerequisite, :feat_choice_properties}}
          :mismatch -> {:requires_feat_choice_property, id, key, required}
        end
      end
    end
  end

  defp feat_choice_property_reasons({_feat, _malformed}, _seen) do
    [{:missing_data, {:prerequisite, :feat_choice_properties}}]
  end

  # Одна пара «фит → значения, которые не засчитываются». Пустой список
  # запрещён по тому же доводу, что у `feat_choices`: «не исключено ничего» —
  # это отсутствие ключа, а не ключ, и недописанная запись здесь потеряла бы
  # правило целиком, ничего не сказав.
  defp feat_choice_exclude_reasons({feat, excluded}, seen)
       when is_list(excluded) and excluded != [] do
    id = to_atom(feat)
    values = Enum.map(excluded, &to_atom/1)
    recorded = recorded_choices(seen.build, seen.ruleset, id, seen.level, seen.whose)

    cond do
      recorded == [] -> []
      Enum.any?(recorded, &(&1 not in values)) -> []
      true -> [{:requires_feat_choice_other_than, id, values}]
    end
  end

  defp feat_choice_exclude_reasons({_feat, _malformed}, _seen) do
    [{:missing_data, {:prerequisite, :feat_choice_excludes}}]
  end

  # ⚠ **Дизъюнкция по взятиям**: фит повторяем, и достаточно ОДНОГО взятия
  # с подходящим значением — «weapon focus in a melee weapon» выполняет тот,
  # у кого есть хоть один ближний фокус, даже если рядом взят лук.
  defp choice_property_verdict(recorded, property, required, ruleset) do
    verdicts =
      for value <- recorded do
        case weapon_property(ruleset, value, property) do
          :unreadable -> :unreadable
          actual -> if actual == required, do: :ok, else: :mismatch
        end
      end

    cond do
      :ok in verdicts -> :ok
      :mismatch in verdicts -> :mismatch
      true -> :unreadable
    end
  end

  # Свойство записи справочника — закрытым словарём ядра, а не по имени поля
  # из данных: ruleset, назвавший свойство, которого ядро прочитать не умеет,
  # обязан отвечать `{:missing_data, …}`, а не молча совпадать с `nil`.
  defp weapon_property(ruleset, weapon_id, property) do
    field = Attack.weapon_property_field(property)
    weapon = Map.get(Map.get(ruleset, :weapons) || %{}, weapon_id)

    cond do
      is_nil(field) or not is_map(weapon) -> :unreadable
      not Map.has_key?(weapon, field) -> :unreadable
      is_nil(Map.get(weapon, field)) -> :unreadable
      true -> Map.get(weapon, field)
    end
  end

  # Значения, с которыми фит взят «для этого блока»: у КЛАССА считается и то,
  # что объявлено с вещи (замер H7 — «но вот КЛАСС можно взять»), у ФИТА — нет.
  # Ровно та же линия, что у `feats` двумя ключами выше, и проведена она тем же
  # `requirement_of`, а не вторым правилом.
  #
  # ⚠ `nil` отбрасывается до сравнения: «взял, но не записал какое» — это
  # отсутствие ответа, а не ответ «не то оружие» (раздел моддока).
  # Всё, что нужно ключу про ЗНАЧЕНИЕ, одной картой: три ключа спрашивают одно
  # и то же у одного и того же билда, и собирать это по-своему в каждом значило
  # бы завести три места, где можно забыть про сужение.
  defp seen(context, whose) do
    %{build: build, ruleset: ruleset} = context

    %{
      build: build,
      ruleset: ruleset,
      level: Build.character_level(build),
      whose: whose,
      excluded: Map.get(context, :excluded_choices) || %{}
    }
  end

  # То же самое, но уже СУЖЕННОЕ: исключённые значения выпадают, потому что
  # взятием для этого блока не считаются (моддок, `feat_choice_excludes`).
  # Единственный читатель у сырого списка — сам ключ исключений.
  defp qualifying_choices(seen, feat_id) do
    excluded = Map.get(seen.excluded, feat_id) || MapSet.new()

    seen.build
    |> recorded_choices(seen.ruleset, feat_id, seen.level, seen.whose)
    |> Enum.reject(&MapSet.member?(excluded, &1))
  end

  defp recorded_choices(build, ruleset, feat_id, level, :class) do
    build
    |> Build.feat_choices_owned(ruleset, feat_id, level)
    |> Enum.reject(&is_nil/1)
  end

  defp recorded_choices(build, ruleset, feat_id, level, _feat) do
    build
    |> Build.feat_choices_permanent(ruleset, feat_id, level)
    |> Enum.reject(&is_nil/1)
  end

  defp save_key(save) when is_atom(save), do: Map.get(@save_keys, Atom.to_string(save))
  defp save_key(save) when is_binary(save), do: Map.get(@save_keys, String.downcase(save))
  defp save_key(_other), do: nil

  # A save the vocabulary does not know, or a value that is not a number, is a
  # requirement that exists and cannot be checked — named, never skipped.
  defp save_reason(nil, _required, _counted), do: [{:missing_data, {:prerequisite, :save_bonus}}]

  defp save_reason(key, required, counted) when is_integer(required) do
    if Map.get(counted, key, 0) >= required, do: [], else: [{:requires_save_bonus, key, required}]
  end

  defp save_reason(_key, _required, _counted), do: [{:missing_data, {:prerequisite, :save_bonus}}]

  # Alignment is one atom (`:lawful_good`, `:true_neutral`). A requirement, once
  # the data layer has normalised its English phrase, is
  # `%{require: [...], forbid: [...], exact: [...]}` over the two words of that
  # atom — so `%{require: ["lawful"]}` admits :lawful_good and :lawful_evil alike.
  defp alignment_matches?(nil, _spec), do: false

  defp alignment_matches?(alignment, spec) when is_map(spec) do
    words = alignment |> Atom.to_string() |> String.split("_")

    Enum.all?([
      Enum.all?(Map.get(spec, :require, []), &(&1 in words)),
      Enum.all?(Map.get(spec, :forbid, []), &(&1 not in words)),
      case Map.get(spec, :exact) do
        nil -> true
        allowed -> Atom.to_string(alignment) in allowed
      end
    ])
  end

  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_atom(value)
end
