defmodule BuildCalculator.Rules.GearImport do
  @moduledoc """
  Надетые предметы → один блок «Вещи», и отчёт по КАЖДОЙ строке.

  Вход этой функции — то, что печатает шардовая команда `.билд+` разделом
  `=== Equipped: <имя> ===`: одиннадцать слотов, у каждого имя предмета и список
  свойств. Выход — `%Rules.Gear{}`, то есть ровно тот блок, который игрок
  заполняет руками, плюс отчёт.

  Слово Dan 11.09.2026, которым эта функция и заведена:

  > «По итогу после импорта хотел бы видеть заполненную экипировку в нашем
  > билдере, **не отдельные вещи, а итоговую „сумму“**, таким образом можно
  > будет видеть чего не хватает до капов и чего набрано сверх капов».

  То есть армори это не делает и не приближает: предметов у модели по-прежнему
  нет, есть суммы. Отсюда и форма — «свести список в сумму», а не «завести
  каталог».

  ## Что здесь НЕ происходит

  **Текста тут нет вовсе.** Разбор строки лога (`[5] AC Bonus (65535) 5`),
  имена свойств, имена характеристик, навыков и фитов — всё это работа
  вызывающего (`BuildCalculatorWeb.Builder.GameLogImport`), и словарь имён у него
  тот же самый, которым читается `FEATS:` обычного `.билд`
  (`BuildCalculator.FeatListTokenizer`). Сюда приходят уже разобранные значения:
  атом характеристики, атом навыка, пара `{feat_id, choice}`. Второго словаря
  имён в проекте быть не должно (CLAUDE.md §9).

  ⚠ Одно исключение, и оно про справочник, а не про словарь имён: **базовый
  тип предмета** (`Warhammer`, `Tower Shield`) сверяется здесь с именами
  `ruleset.weapons` и предметов `gear.worn` — потому что это и есть та таблица,
  в которую он должен лечь, и держать её копию у вызывающего значило бы два
  списка оружия.

  **Потолков тут тоже нет.** Ни +12 на характеристику, ни +50 на навык, ни +20
  на сейв: всё это стоит ниже по конвейеру и применяется к СУММЕ вещевого
  и собственного (`Rules.Gear`, `Rules.Skills`, `Rules.compute/2`). Клип здесь
  был бы вторым клипом того же потолка — ровно та ошибка «по половинке»,
  из-за которой билд однажды носил +40 на сейве (CLAUDE.md §9). Поэтому
  импорт кладёт в `%Gear{}` **сумму до потолка**: игрок для того и просил
  «итоговую сумму», чтобы видеть, «чего набрано сверх капов».

  ## Три ведра, и каждая строка ровно в одном

  Отчёт перечисляет **все** строки всех предметов:

    * `applied` — строка легла в число. `landed` называет куда
      (`{:ability, :con, 3}`, `{:ac, :armor, 6}`, `{:feat, :cleave}`),
      `counted?` — попала ли она в итог: у AC одного типа побеждает
      **наибольшая** (кроме складывающихся типов), и проигравшая строка
      остаётся здесь с `counted?: false` и названной причиной. Соврать «учтено»
      про выброшенное число нельзя;
    * `not_ours` — получателя у механики нет вовсе (`Cast Spell`,
      `Damage Bonus`, `Regeneration`, `Immunity`…), либо он есть, но решением
      владельца не вводится (сопротивление заклинаниям с вещей, решение Dan
      18.08.2026);
    * `unresolved` — **получатель наш, а сложить нельзя**: лог не печатает того,
      от чего зависит ответ, **либо мы не прочитали саму строку**. Это и есть
      машиночитаемый список доработок сервера, который просил Dan («делаем что
      получится и составляем список что не получается, отдам на доработку
      сервер»).

  🔴 **`not_ours` — утверждение, а не помойка** (урок 3.213, закреплён задачей
  3.221). Строка попадает туда, только когда мы прочли ИМЯ свойства и знаем про
  эту механику, что получателя у неё нет. Имя, которого разбиратель текста
  не узнал, идёт в `unresolved` с причиной `{:property_name_unknown, raw}`: это
  **наш** вопрос, а не решение, и ровно так выглядит правка чужой печати. Когда
  сервер снял параметр у `AC Bonus`, строка перестала совпадать с именем
  и молча уехала в «не наше» — AC на проде стал 38 вместо 58 без единой
  оговорки, хотя инвариант «ни одна строка не теряется» держался.

  🔴 **Инвариант: ни одна строка не теряется молча.** Сумма длин трёх списков
  равна числу свойств на входе — под тестом. Тот же принцип, что у токенизатора
  фитов: нераспознанное обязано быть НАЗВАНО, а не пропущено.

  ## Третье поколение печати — 18.09.2026, задача 3.213

  Администрация закрыла два последних пункта списка доработок, и свод читает оба:

    * **база доспеха** — `[CHEST] Нагрудник Призрака [BaseAC:8]`. Число ищется
      по `base_ac` строк той категории `gear.worn`, которую называет сам слот
      (`worn_category_by_base_ac`), и доспех ложится в `worn`. 🔴 **Имя предмета
      здесь не спрашивают вовсе** — «Нагрудник Призрака» с базой 8 это латы,
      а не `chainmail` («Chainmail, Breastplate», база 5), и подстановка
      по переводу имени дала бы минус три очка AC. Ровно на эту базу AC
      расходился с игрой у двух логов из четырёх: 58 против 63 и 34 против 41,
      теперь **63 = 63** и **41 = 41**;
    * **базовый тип в `ARMS`** — `(Bracer) [BaseItem:78]` и `(Gauntlet)
      [BaseItem:36]`. Напечатанное имя типа переводится в тип AC записями
      `ac_type_by_base_type` (наручи → броня, перчатки → отклонение, обе
      цитаты в данных). ⚠ Ни у одной вещи в `ARMS` на четырёх логах нет строки
      `AC Bonus`, так что живого носителя у правила пока нет — под тестом оно
      синтетикой.

  ⚠ И третья правка сервера, которая ничего не добавила, а могла всё сломать:
  `AC Bonus` больше **не печатает параметра** (`AC Bonus 5` вместо `AC Bonus
  (0) 5`). Читает обе формы разбор текста (`BuildCalculator.GameLog`), здесь
  про это знать нечего — сюда приходит вид `:ac_bonus` и число.

  ## Второе поколение печати — 13.09.2026, задача 3.206

  Администрация сделала три из четырёх доработок, которые просил
  `docs/bild_plus_for_admins.md`, и свод читает их все:

    * **базовый тип предмета в руках** — `Ург Шак (Warhammer) [BaseItem:5]`,
      `… (Tower Shield) [BaseItem:57]`. Имя типа сверяется со справочником
      (`ruleset.weapons[].name`, предметы `gear.worn`), и оружие ложится в руку
      (`weapon` / `off_hand_weapon` с числом по правилу `gear.weapon_import_rule`),
      а щит — в `worn`. Тип AC у второй руки тем же движением перестаёт быть
      неизвестным: щит → щитовой, всё остальное → отклонение
      (`item_slot_ac_types[left_hand].ac_type_by_worn_category` / `ac_type_otherwise`,
      обе цитаты — в данных). ⚠ Здесь стояло «`ARMS` базового типа не печатает
      по-прежнему, и его AC остаётся в `unresolved`» — закрыто третьим
      поколением, см. выше;
    * **номер набора у куска мини-сета** — `Use Item (Mini Set) [SetID:73]`.
      Куски группируются по номеру, одиночка не считается
      (`Rules.MiniSets.minimum_group/1`), и группы ложатся в `mini_sets`;
    * **две суммы в шапке раздела** — `MINI SET PIECES: 7` и `CRAFT ITEMS: 7`,
      посчитанные самим сервером; и **пометка `[CRAFT]`** у имени крафтовой вещи.

  🔴 **Что значат две суммы — прочитано по именам функций скрипта, а не по
  подписям в логе, и это чтение НАЗВАНО** (`docs/research/2026-09-11-miniset-
  scaling-system.md`, §1 и §3): `MINI SET PIECES` = `number_minisets` = `Nmini`,
  то есть куски **только из групп от двух**; `CRAFT ITEMS` = то, что возвращает
  `GetNumberOfEquipedIndividualCraftItems` — а она «first counts qualifying
  personalized/unique equipment … It then adds `Nmini`», то есть **`Ctotal`
  целиком**, а не одни крафтовые. Ровно поэтому у Хнюпиуса стоит `CRAFT ITEMS: 7`
  при семи кусках и **нуле** помеченных `[CRAFT]` вещей, а у Бора — `4` при
  четырёх кусках и нуле пометок; читать шапку как «крафтовых 7» значило бы
  `Ctotal` 14 и обрыв прибавки в ноль — а игра печатает Хнюпиусу 1503 HP,
  ровно ячейку 7. Отсюда:

      named_items = CRAFT ITEMS − MINI SET PIECES

  и пометки `[CRAFT]` — **сверка** этого числа по предметам, а не второй его
  источник: на всех четырёх логах 13.09.2026 они сходятся (0 / 6 / 3 / 0).
  Разошлись — верх берёт шапка (её считает тот же скрипт, что и HP), и разница
  названа в `report.counts.notes`, а не сглажена.

  ⚠ **Чего второе поколение не различает — записано, а не додумано:**

    * `MINI SET PIECES` при ОДНОМ надетом куске — `0` (если это `Nmini`) или `1`
      (если это сырой счёт). На четырёх логах одиночек нет; принято первое, по
      имени переменной скрипта, и ✅ ИЗМЕРЕНО Dan 13.09.2026: «надел 1 предмет
      из мини-сетов, в шапке `MINI SET PIECES: 0`» — шапка печатает `Nmini`
      (кейс `AT2`);
    * куски без `[SetID]` при ненулевой шапке (у Бора: четыре куска по шапке
      и **ни одной** строки `Use Item (Mini Set)`). Слово Dan 13.09.2026: «просто
      старый персонаж и на его вещах нет отметки о мини сетах, её добавили позже»
      — отметка стоит на новых экземплярах предметов, шапка считает по данным
      сервера. Групп по строкам не восстановить, и в `mini_sets` ложится **одна
      группа размером в шапку**: для `Nmini` это то же число (`[4]` = `[2, 2]` = 4),
      а для показа — оговорка в `notes`;
    * пометка `[CRAFT]` против замера `AS1`: 12.09.2026 движок считал Брунне
      **четыре** крафтовые вещи (813 HP при `Ctotal` 4), а 13.09.2026 сервер
      помечает **шесть** и печатает `CRAFT ITEMS: 6`. ✅ Не спор — Dan тем же днём:
      «при замерах я менял вещи, снимал что-то, надевал другое», состояния разные.
      Свод берёт число сервера как есть (кейс `AT1` закрыт).

  ## Откуда берутся правила, по которым это сводится

  Ни одного игрового числа и ни одного имени типа AC в этом модуле нет:

    * тип класса брони по слоту — `ruleset.gear.item_slot_ac_types`
      (`fandom:Armor class`, revid 71718). Слот, у которого источник называет
      два разных предмета с разными типами (`ARMS`: наручи или перчатки;
      `LEFTHAND`: щит или что угодно другое), типа не получает вовсе, и его
      число уходит в `unresolved` с названными альтернативами — **пока лог
      не назвал базовый тип предмета** (см. выше);
    * какая категория `gear.worn` стоит за базой доспеха — тот же слот,
      поле `worn_category_by_base_ac`, и цитата та же: «armor bonus - provided
      by armor (the only thing that can occupy the armor slot)»;
    * два предмета ОДНОГО типа — `ruleset.gear.ac_same_type.gear_vs_gear`
      (максимум) и `ruleset.gear.ac_same_type.cumulative` (типы-исключения,
      которые складываются). Слово Dan 16.08.2026: «Вообще никакое АЦ
      не складывается, когда дело касается вещей, всегда берется максимальное,
      за исключением dodge АЦ»;
    * повторяемость фита — `Rules.FeatChoices.repeatable?/2`, а то, считается ли
      вторая запись ВТОРЫМ ВЗЯТИЕМ, — `Rules.FeatChoices.repeats_same_value?/2`
      (задачи 3.204 и 3.210). Списка имён ни у того, ни у другого здесь нет:
      оба читают `repeatable` из данных;
    * наименьшая группа кусков и число слотов — `Rules.MiniSets.minimum_group/1`
      и `slots/1`, из того же снапшота, что считает усиление бонусов;
    * стихии поглощения и то, каких видов урона эта секция не показывает, —
      `ruleset.resistance_energy_types` и `resistance_excluded_types` (задача
      3.210); свод вещи с вещью по одной стихии — `resistance_stacking.
      gear_vs_gear` (максимум). Ни одного имени стихии и ни одного вида урона
      в этом модуле нет.
  """

  alias BuildCalculator.Rules.{Abilities, FeatChoices, Gear, MiniSets, Worn}

  # Какие сейвы существуют, и ничего о том, сколько какой стоит, — та же тройка
  # ключей, которой говорят `Rules.compute/2` и `Rules.SaveBonuses`.
  @saves [:fort, :ref, :will]

  # Какими свойствами предмет называет своё число атаки. Это словарь РАЗБОРА
  # ЛОГА (`kind()` этого модуля), а не игровые сущности: имена свойств живут
  # у вызывающего, сюда приходят виды. Их два, и ровно поэтому нужно правило
  # свода — модель держит одно число на руку (задача 3.52).
  @weapon_attack_kinds [:attack_bonus, :enhancement_bonus]

  @typedoc """
  Слот, в котором надет предмет — id из `ruleset.gear.item_slot_ac_types`
  (`:head`, `:chest`, `:left_hand`…). Токен лога (`"HEAD"`) в этот id переводит
  вызывающий, читая ту же таблицу: её поле `log` для того и лежит в данных.
  """
  @type slot :: atom()

  @typedoc """
  Вид свойства предмета. Всё, чего в этом списке нет, приходит как `:other`:
  решение «эта механика не наша» принимает разбиратель текста, знающий имя
  свойства, а не эта функция.

  ⚠️ `:other` уходит в ДВА ведра, и решает это `param` (задача 3.221): атом —
  имя узнано, значит `not_ours`; отсутствует или `{:unresolved, text}` — имя
  не узнано, значит `unresolved`.
  """
  @type kind ::
          :ability_bonus
          | :ac_bonus
          | :saving_throw_universal
          | :saving_throw_specific
          | :skill_bonus
          | :bonus_feat
          | :attack_bonus
          | :enhancement_bonus
          | :mini_set
          | :quality
          | :spell_resistance
          | :damage_resistance
          | :other

  @typedoc """
  Параметр свойства — уже разобранный вызывающим.

  Атом (характеристика, навык, сейв, имя свойства), пара `{feat_id, choice}`
  для фита с выбором, число (номер набора у `:mini_set`, задача 3.206), либо
  `{:unresolved, "текст"}`, когда вызывающий имя не опознал.
  ⚠ `{:unresolved, …}` — законное значение, а не ошибка вызова: «мы не узнали
  имя» обязано доехать до отчёта, а не превратиться в исключение.
  """
  @type param ::
          atom() | {atom(), atom() | nil} | non_neg_integer() | {:unresolved, String.t()} | nil

  @typedoc """
  Одна строка предмета, как её напечатал лог и разобрал вызывающий.

  ⚠ `rank` — римская ступень фита, если игра её напечатала (`Bonus Feat (Epic
  Toughness II)`), строкой и как есть. Задача 3.204: у повторяемого фита без
  выбора ступень и есть НОМЕР ВЗЯТИЯ — разные ступени дают разные взятия,
  одинаковая ступень с двух предметов остаётся одним. Ключа нет вовсе там, где
  ступени не напечатано, и это не то же самое, что пустая строка.
  """
  @type property :: %{
          required(:kind) => kind(),
          required(:raw) => String.t(),
          optional(:param) => param(),
          optional(:value) => integer() | nil,
          optional(:rank) => String.t()
        }

  @typedoc """
  Один надетый предмет.

  Четыре ключа НЕОБЯЗАТЕЛЬНЫ и есть только там, где их напечатал лог:
  `base_type` — базовый тип предмета текстом, как напечатан (`"Warhammer"`,
  `"Bracer"`); `base_item` — строка `baseitems.2da`, для провенанса;
  `base_ac` — база класса брони у доспеха (`[BaseAC:8]`, третье поколение
  печати, задача 3.213); `craft?: true` — пометка `[CRAFT]`. Отсутствие
  ключа — «лог не сказал», а не «нет».

  ⚠ `base_ac: 0` — законное значение и означает «роба, одежда» (строка
  `gear.worn` с нулевой базой), а не «сервер промолчал». Разница видна
  в числе на экране: нулевая база НЕ гасит AC-бонусы монаха, а неназванная
  база оставляет доспех невыбранным вовсе.
  """
  @type item :: %{
          required(:slot) => slot(),
          required(:name) => String.t(),
          required(:properties) => [property()],
          optional(:base_type) => String.t(),
          optional(:base_item) => non_neg_integer(),
          optional(:base_ac) => non_neg_integer(),
          optional(:craft?) => true
        }

  @typedoc """
  Две суммы из шапки раздела `=== Equipped` второго поколения, как их напечатал
  сервер. Что каждая значит — в moduledoc; пустая мапа у первого поколения.
  """
  @type counts :: %{
          optional(:mini_set_pieces) => non_neg_integer(),
          optional(:craft_items) => non_neg_integer()
        }

  @typedoc "Куда легла строка."
  @type landing ::
          {:ability, atom(), integer()}
          | {:skill, atom(), integer()}
          | {:save, :universal | :fort | :ref | :will, integer()}
          | {:ac, atom(), integer()}
          | {:feat, atom()}
          | {:feat, atom(), atom()}
          | {:weapon_attack, atom(), integer()}
          | {:mini_set, non_neg_integer()}
          | {:resistance, atom(), integer()}

  @typedoc """
  Почему строка не легла. Закрытый словарь — веб-слой пишет по нему фразы,
  и он же есть список доработок `.билд+` для администрации шарда.

  Три причины про базовый тип, и они про разное: `weapon_base_type_unknown` —
  лог его не напечатал (первое поколение); `base_type_unresolved` — напечатал,
  а справочник такого имени не знает; `base_type_not_a_weapon` — напечатал
  и опознан, но в ЭТУ руку это не надевается (щит в главной руке).

  🔴 **`property_not_modelled` и `property_name_unknown` — РАЗНЫЕ утверждения,
  и путать их дорого** (задача 3.221). Первое говорит «мы прочли ИМЯ свойства
  и у этой механики нет получателя» — поэтому у него всегда **атом** из нашей
  таблицы имён, никогда текст лога. Второе — «имени мы не узнали вовсе», то есть
  вопрос наш, и строка идёт в `unresolved`, список доработок. До правки обе
  приходили одной формой, и неузнанное имя печаталось как «не наша механика»
  — то самое молчание, которым 3.213 стоила прода: сервер сменил форму печати
  `AC Bonus`, строка перестала совпадать с именем и ушла в «не наше» без единой
  оговорки.
  """
  @type reason ::
          {:property_not_modelled, atom()}
          | {:property_name_unknown, String.t()}
          | {:decided_not_modelled, atom()}
          | {:slot_unknown, slot()}
          | {:ac_type_unknown, slot(), [atom()]}
          | {:ability_unknown, term()}
          | {:skill_unknown, term()}
          | {:save_unknown, term()}
          | {:feat_unknown, term()}
          | {:resistance_unknown, term()}
          | {:feat_repeat_not_expressible, atom()}
          | {:weapon_base_type_unknown, atom()}
          | {:base_type_unresolved, String.t()}
          | {:base_type_not_a_weapon, String.t()}
          | {:weapon_numbers_not_reconciled, [kind()]}
          | {:mini_set_group_unknown, nil}
          | {:named_item_flag_missing, atom()}
          | {:value_missing, kind()}

  @typedoc """
  Строка в отчёте — чем бы она ни кончилась.

  `landed` и `counted?` заполнены у `applied`, `reason` — у двух других вёдер.
  `note` объясняет `counted?: false` у строки, которая ПРОЧИТАНА, но в число
  не вошла: `:superseded_by_larger_same_type` (у AC того же типа — или у второго
  числа атаки того же предмета — нашлось большее), `:already_declared` (этот
  фит вещи уже одолжили) и `:lone_piece` (кусок набора, у которого пары нет,
  а одиночка не считается).
  """
  @type entry :: %{
          slot: slot(),
          item: String.t(),
          kind: kind(),
          raw: String.t(),
          landed: landing() | nil,
          counted?: boolean(),
          note: :superseded_by_larger_same_type | :already_declared | :lone_piece | nil,
          reason: reason() | nil
        }

  @typedoc """
  Оружие в одной руке: что надето и какое число атаки оно несёт.

  `attack` — уже **сведённое** число, то есть ответ на «что впишется
  в `Gear.weapon_attack`», а не строка лога: чисел у предмета бывает два
  (`Attack Bonus` и `Enhancement Bonus`), и сводит их правило из данных
  (`gear.weapon_import_rule`). `nil` означает «числа у нас нет» — либо его
  не назвала ни одна строка, либо назвали две, а правила свода в ruleset'е
  нет; различает эти два случая `from`, где во втором названы обе строки.

  `from` — виды свойств, назвавшие число, в порядке печати лога.

  `base_type` — базовый тип, как напечатал лог (`nil` у первого поколения);
  `wields` — что из этого ЛЕГЛО в билд: `{:weapon, id}`, `{:worn, category,
  item}` (щит) или `nil`, когда предмет в руку не надет — потому что тип
  не напечатан, не опознан или в эту руку не идёт.
  """
  @type weapon :: %{
          slot: slot(),
          name: String.t(),
          attack: integer() | nil,
          from: [kind()],
          base_type: String.t() | nil,
          wields: {:weapon, atom()} | {:worn, atom(), atom()} | nil
        }

  @typedoc """
  Надетое, которое лог называет БАЗОЙ, а не типом — сегодня это доспех
  (задача 3.213, `[BaseAC:8]` у `CHEST`).

  Стоит рядом с вёдрами и ничего у них не забирает, как и `weapons`: база
  печатается у ИМЕНИ предмета, а не отдельной строкой свойства, значит
  в инвариант «каждая строка ровно в одном ведре» ей входить нечем.

  `wears` — что легло в `Gear.worn` (`{:worn, category, item}` или `nil`);
  `reason` — почему не легло, и вариантов три:

    * `{:armor_base_not_printed, slot}` — предмет в слоте есть, а базы лог
      не напечатал (первое и второе поколение печати). ⚠️ Это НЕ «доспеха нет»:
      доспех надет, мы не знаем его базу, и молчать об этом нельзя — ровно
      на неё AC расходился с игрой у двух логов из четырёх;
    * `{:armor_base_unresolved, base_ac}` — база напечатана, а записи с такой
      базой в справочнике нет;
    * `{:armor_base_rule_missing, slot}` — база напечатана, а снапшот не говорит,
      какую категорию `gear.worn` она называет (`worn_category_by_base_ac`).
  """
  @type worn_item :: %{
          slot: slot(),
          name: String.t(),
          base_ac: non_neg_integer() | nil,
          wears: {:worn, atom(), atom()} | nil,
          reason: worn_reason() | nil
        }

  @typedoc "Почему база доспеха не превратилась в надетый предмет."
  @type worn_reason ::
          {:armor_base_not_printed, slot()}
          | {:armor_base_unresolved, non_neg_integer()}
          | {:armor_base_rule_missing, slot()}

  @typedoc """
  Что свод понял про счётчики второго поколения.

  `mini_set_pieces` и `craft_items` — суммы из шапки как напечатаны (`nil`
  у первого поколения); `groups` — группы кусков от двух по `[SetID]`;
  `craft_marked` — имена предметов с пометкой `[CRAFT]`; `named_items` — то,
  что легло в `Gear.named_items`; `notes` — где шапка и предметы разошлись
  и что взяло верх:

    * `{:mini_set_groups_unverified, header, groups}` — сумма групп по `[SetID]`
      не равна шапке, в `mini_sets` легла одна группа размером в шапку;
    * `{:craft_marks_disagree, named, marked}` — `CRAFT ITEMS − MINI SET PIECES`
      не совпало с числом пометок `[CRAFT]`, взято первое;
    * `{:craft_items_below_pieces, craft_items, pieces}` — шапка называет
      крафта меньше, чем кусков, разность отрицательна, взят ноль.
  """
  @type counts_report :: %{
          mini_set_pieces: non_neg_integer() | nil,
          craft_items: non_neg_integer() | nil,
          groups: [pos_integer()],
          craft_marked: [String.t()],
          named_items: non_neg_integer(),
          notes: [tuple()]
        }

  @typedoc """
  Отчёт: каждая строка ровно в одном ведре, и сумма длин равна числу строк.

  `weapons` стоит рядом с вёдрами и ничего у них не забирает: здесь названо
  то, что из строк оружия **следует**, — имя предмета в каждой руке, его число
  и что легло в билд. `worn` — то же для базы доспеха, `counts` — для двух
  сумм шапки.
  """
  @type report :: %{
          applied: [entry()],
          not_ours: [entry()],
          unresolved: [entry()],
          weapons: %{atom() => weapon() | nil},
          worn: %{slot() => worn_item() | nil},
          counts: counts_report()
        }

  @doc """
  One example of every `reason/0` and `worn_reason/0` this module's callers
  can be handed — by hand, the same way `Rules.Vocabulary.gaps/0` and
  `reasons/0` do it, because these two types predate that registry and speak
  a small closed union of their own rather than the gap/refusal families it
  audits (task 3.213, part of the same finding that turned up three forms —
  `:ability_unknown`, `:skill_unknown`, `:save_unknown` — the import dialog
  had been rendering through its `"Не распознано"`/`inspect/1` fallback with
  nobody noticing, because nothing had ever walked the full union to ask).

  Exists so the web layer can prove every one has real Russian wording
  instead of quietly falling through to that fallback
  (`BuildCalculatorWeb.Builder.GameLogImportPanelReasonLabelsTest` walks this
  list the same way `Rules.VocabularyTest` walks `Vocabulary`'s registry). A
  sibling test on this module, `GearImportReasonExamplesTest`, keeps the
  catalogue itself honest: every entry here is reproduced by a real call to
  `sum/2,3` on a minimal synthetic item — nothing here is a shape invented
  for the list and never actually produced.
  """
  @spec reason_examples() :: [reason() | worn_reason()]
  def reason_examples do
    [
      {:property_not_modelled, :cast_spell},
      # Задача 3.221. Здесь стояло `{:property_not_modelled, "Quality"}` —
      # СТРОКА, и сама она была следом дефекта: строковый субъект у этой формы
      # означал ровно «имя мы не прочитали», а фраза панели утверждала «не наша
      # механика». Теперь у `property_not_modelled` субъект только атом, а
      # неузнанное имя носит свою форму и едет в `unresolved`.
      {:property_name_unknown, "[3] Fancy New Property (65535) 4"},
      {:decided_not_modelled, :spell_resistance},
      # Поглощение ФИЗИЧЕСКОГО урона (задача 3.210): получатель у механики
      # наш — это те же `Damage Resistance (…)` строки, что у стихий, — а
      # решение владельца её не считать («поглощение стихийного урона, без
      # физического», Dan 13.09.2026). Поэтому «решением не считаем», а не
      # «не наша механика» и уж точно не список доработок сервера. ⚠️ Имя
      # вида урона приходит ИЗ ДАННЫХ (`resistance_excluded_types`), а не
      # литералом здесь.
      {:decided_not_modelled, :physical},
      {:resistance_unknown, {:unresolved, "Some Damage Type"}},
      {:slot_unknown, :unknown_slot},
      {:ac_type_unknown, :arms, [:armor, :deflection]},
      {:ability_unknown, {:unresolved, "Some Ability"}},
      {:skill_unknown, {:unresolved, "Some Skill"}},
      {:save_unknown, {:unresolved, "Some Save"}},
      {:feat_unknown, {:unresolved, "Sneak Attack"}},
      {:feat_repeat_not_expressible, :epic_energy_resistance},
      {:weapon_base_type_unknown, :main},
      {:base_type_unresolved, "Some Base Type"},
      {:base_type_not_a_weapon, "Tower Shield"},
      {:weapon_numbers_not_reconciled, [:attack_bonus, :enhancement_bonus]},
      {:mini_set_group_unknown, nil},
      {:named_item_flag_missing, :quality},
      {:value_missing, :ac_bonus},
      {:armor_base_not_printed, :chest},
      {:armor_base_unresolved, 99},
      {:armor_base_rule_missing, :chest}
    ]
  end

  @doc """
  Сводит список надетых предметов в один блок «Вещи».

  Возвращает `{gear, report}`: `gear` — суммы **до потолков**, `report` —
  все строки по трём вёдрам (см. moduledoc). `counts` — две суммы из шапки
  раздела второго поколения; пустая мапа у первого поколения, и тогда
  поведение ровно то, что было до задачи 3.206 (под тестом на старых логах).

  ⚠ Возвращается ПУСТОЙ `%Gear{}` с проставленными суммами, а не правка того,
  что игрок ввёл раньше: «заполненная экипировка» — это результат импорта
  целиком, а сливать его с прежним вводом (и решать, что победит) — вопрос
  интерфейса, а не правил.

  ⚠ Чего эта функция НЕ заполняет у ПЕРВОГО поколения печати, и каждый раз
  по названной причине (у второго и третьего — заполняет, см. moduledoc):

    * `worn` и `weapon` — ни базового типа предмета, ни базы доспеха лог
      не печатает; числа оружия при этом **названы** в `unresolved`
      и **сведены** по рукам в `report.weapons` (задача 3.199), а надетый
      доспех со своей причиной стоит в `report.worn` (задача 3.213);
    * `mini_sets` — кусок помечен, набор не назван, а без принадлежности
      `Nmini` не считается вовсе (`[A,A,B]` = 2, `[A,B]` = 0);
    * `named_items` — `Quality` это артефактный сет, а не крафт (Dan: «Перчатки
      Мокси это сет, а не мини сет, и он не даёт прибавку к здоровью, а вот
      крафт — даёт»), а крафтовую вещь лог первого поколения ничем не помечает.
  """
  @spec sum([item()], map(), counts()) :: {Gear.t(), report()}
  def sum(items, ruleset, counts \\ %{}) when is_list(items) and is_map(counts) do
    bases = Map.new(items, &{&1.slot, resolve_base(&1, ruleset)})
    texts = Map.new(items, &{&1.slot, Map.get(&1, :base_type)})
    hands = hand_slots(ruleset)
    context = %{bases: bases, texts: texts, hands: hands, counts: counts, ruleset: ruleset}

    state = Enum.reduce(items, empty_state(), &read_item(&1, &2, context))

    {ac, ac_entries} = resolve_ac(state.ac, ruleset)
    {resistances, resistance_entries} = resolve_resistances(state.resistances, ruleset)
    {weapons, hand_gear, attack_entries, attack_unresolved} = resolve_hands(items, state, context)
    {mini_sets, groups, piece_entries, piece_notes} = resolve_mini_sets(state.pieces, context)
    {named_items, craft_marked, craft_notes} = resolve_named_items(items, groups, context)
    {worn_gear, worn_report} = resolve_worn(items, context)

    gear = %Gear{
      abilities: drop_zeros(state.abilities),
      skills: drop_zeros(state.skills),
      saves: state.saves,
      saves_specific: drop_zeros(state.saves_specific),
      ac: ac,
      feats: Enum.sort(state.feats),
      # Две категории надетого приходят из РАЗНЫХ мест лога и не спорят между
      # собой: щит — из второй руки по базовому типу, доспех — из числа
      # `[BaseAC:n]` у своего слота.
      worn: Map.merge(worn_gear, hand_gear.worn),
      weapon: hand_gear.weapon,
      weapon_attack: hand_gear.weapon_attack,
      off_hand_weapon: hand_gear.off_hand_weapon,
      off_hand_weapon_attack: hand_gear.off_hand_weapon_attack,
      mini_sets: mini_sets,
      named_items: named_items,
      resistances: drop_zeros(resistances)
    }

    report = %{
      applied:
        Enum.reverse(state.applied) ++
          ac_entries ++ attack_entries ++ piece_entries ++ resistance_entries,
      not_ours: Enum.reverse(state.not_ours),
      unresolved: Enum.reverse(state.unresolved) ++ attack_unresolved,
      weapons: weapons,
      worn: worn_report,
      counts: %{
        mini_set_pieces: Map.get(counts, :mini_set_pieces),
        craft_items: Map.get(counts, :craft_items),
        groups: groups,
        craft_marked: craft_marked,
        named_items: named_items,
        notes: piece_notes ++ craft_notes
      }
    }

    {gear, report}
  end

  @doc """
  Сколько строк пришло на вход — то, с чем сверяется инвариант «ни одна строка
  не потеряна».

  Отдельной функцией, чтобы вызывающий считал вход тем же способом, каким его
  считает тест, а не своим.
  """
  @spec property_count([item()]) :: non_neg_integer()
  def property_count(items) when is_list(items),
    do: Enum.reduce(items, 0, &(length(&1.properties) + &2))

  # ------------------------------------------------------------------ чтение --

  defp empty_state do
    %{
      abilities: %{},
      skills: %{},
      saves: 0,
      saves_specific: %{},
      ac: [],
      feats: [],
      # Опознанные строки фитов вместе со СТУПЕНЬЮ (`{entry, rank}`) — по ним
      # различаются копии повторяемого фита (задача 3.204). Отдельно от `feats`,
      # потому что в блок «Вещи» уходит список записей, а этот ключ отвечает
      # на другой вопрос: «эта строка лога уже прочитана или другая такая же».
      feat_keys: [],
      # Числа атаки по рукам и куски мини-сетов — копятся, решаются после
      # прочтения всех предметов, тем же приёмом, что AC: у предмета чисел
      # бывает два, а считается ли кусок, знает только вся группа.
      attack: %{},
      pieces: [],
      # Поглощение стихий — копится и решается после прочтения всех предметов,
      # тем же приёмом и по той же причине, что AC: между предметами
      # поглощение одной стихии не складывается, побеждает наибольшее,
      # а кто победил, видно только когда прочитаны все.
      resistances: [],
      applied: [],
      not_ours: [],
      unresolved: []
    }
  end

  defp read_item(%{slot: slot, name: name, properties: properties}, state, context) do
    where = %{slot: slot, item: name}
    Enum.reduce(properties, state, &read_property(&1, where, &2, context))
  end

  # `:other` — «вызывающий узнал строку и знает, что механика не наша». Судить
  # об этом здесь нечем: имя свойства осталось в тексте, а сюда пришёл вид.
  #
  # 🔴 НО РОВНО ОДИН ВОПРОС ЗДЕСЬ РЕШАЕТСЯ, И ОН ПРО НАС, А НЕ ПРО МЕХАНИКУ
  # (задача 3.221): узнал ли вызывающий ИМЯ. `name_of/1` отдаёт атом из его
  # закрытой таблицы имён, когда узнал, и сырую строку лога, когда нет, —
  # и это два разных ответа игроку. «Не наша механика (Cast Spell)» —
  # утверждение, которое мы обязаны уметь сделать; «не наша механика
  # ([3] Fancy New Property (65535) 4)» — утверждение про строку, которую
  # мы просто не прочитали, и в ведре `not_ours` оно к тому же выпадает
  # из списка доработок сервера. Цена этого молчания измерена в 3.213.
  defp read_property(%{kind: :other} = property, where, state, _context) do
    case name_of(property) do
      name when is_atom(name) ->
        not_ours(state, where, property, {:property_not_modelled, name})

      text ->
        unresolved(state, where, property, {:property_name_unknown, text})
    end
  end

  # Единственный случай «получатель есть, а ввода не будет по решению»: поля
  # ввода SR с вещей не будет (Dan 18.08.2026), и SR к тому же не складывается,
  # а конкурирует — то есть суммировать его было бы вдвойне неверно.
  defp read_property(%{kind: :spell_resistance} = property, where, state, _context),
    do: not_ours(state, where, property, {:decided_not_modelled, :spell_resistance})

  defp read_property(%{kind: :ability_bonus} = property, where, state, _context) do
    with {:ok, ability} <- known(property, Abilities.keys(), :ability_unknown),
         {:ok, value} <- number(property) do
      state
      |> update_in([:abilities, Access.key(ability, 0)], &(&1 + value))
      |> applied(where, property, {:ability, ability, value})
    else
      {:error, reason} -> unresolved(state, where, property, reason)
    end
  end

  defp read_property(%{kind: :skill_bonus} = property, where, state, %{ruleset: ruleset}) do
    with {:ok, skill} <- known(property, Map.keys(ruleset.skills), :skill_unknown),
         {:ok, value} <- number(property) do
      state
      |> update_in([:skills, Access.key(skill, 0)], &(&1 + value))
      |> applied(where, property, {:skill, skill, value})
    else
      {:error, reason} -> unresolved(state, where, property, reason)
    end
  end

  defp read_property(%{kind: :saving_throw_universal} = property, where, state, _context) do
    case number(property) do
      {:ok, value} ->
        state
        |> Map.update!(:saves, &(&1 + value))
        |> applied(where, property, {:save, :universal, value})

      {:error, reason} ->
        unresolved(state, where, property, reason)
    end
  end

  defp read_property(%{kind: :saving_throw_specific} = property, where, state, _context) do
    with {:ok, save} <- known(property, @saves, :save_unknown),
         {:ok, value} <- number(property) do
      state
      |> update_in([:saves_specific, Access.key(save, 0)], &(&1 + value))
      |> applied(where, property, {:save, save, value})
    else
      {:error, reason} -> unresolved(state, where, property, reason)
    end
  end

  # AC не складывается на месте: тип у строки берётся от слота (и от базового
  # типа предмета, когда лог его назвал), а между собой строки одного типа
  # СПОРЯТ (максимум) — и кто победил, видно только когда прочитаны все
  # предметы. Поэтому копим, а решаем в `resolve_ac/2`.
  defp read_property(%{kind: :ac_bonus} = property, where, state, context) do
    with {:ok, value} <- number(property),
         {:ok, type} <- ac_type(where.slot, context) do
      Map.update!(state, :ac, &[{type, value, where, property} | &1])
    else
      {:error, reason} -> unresolved(state, where, property, reason)
    end
  end

  # Поглощение стихийного урона (задача 3.210). Три исхода, и это ТРИ РАЗНЫХ
  # ответа, а не один с оттенками:
  #
  #   * стихия из семи, которые печатает секция «Резисты» — строка ложится
  #     в `Gear.resistances`, а между предметами решает `resolve_resistances/2`;
  #   * вид урона, которого секция НЕ показывает, — `not_ours`, и фраза зависит
  #     от того, ПОЧЕМУ его нет: физическое поглощение мы могли бы считать
  #     и не считаем по решению владельца, а магический и божественный урон
  #     не поглощаются в самой игре. Оба списка имён — из данных
  #     (`ruleset.resistance_excluded_types`), ни одного вида урона здесь
  #     по имени нет;
  #   * имя, которого не знает ни один из двух словарей, — `unresolved`, то есть
  #     список доработок сервера. ⚠️ Разница дорогая: `not_ours` говорит «это
  #     не наш вопрос», `unresolved` — «наш, и мы не смогли», и физическое
  #     поглощение во второй список попасть не должно.
  defp read_property(%{kind: :damage_resistance} = property, where, state, context) do
    case excluded_damage_type(property, context) do
      {:ok, reason} ->
        not_ours(state, where, property, reason)

      :not_excluded ->
        with {:ok, type} <- known(property, energy_type_ids(context), :resistance_unknown),
             {:ok, value} <- number(property) do
          Map.update!(state, :resistances, &[{type, value, where, property} | &1])
        else
          {:error, reason} -> unresolved(state, where, property, reason)
        end
    end
  end

  defp read_property(%{kind: :bonus_feat} = property, where, state, %{ruleset: ruleset}) do
    case feat_entry(property, ruleset) do
      {:ok, entry} -> read_feat(entry, where, property, state, ruleset)
      {:error, reason} -> unresolved(state, where, property, reason)
    end
  end

  # Число оружия ложится в руку, только когда в этой руке ОПОЗНАННОЕ оружие;
  # иначе строка остаётся в `unresolved` с причиной, называющей, чего именно
  # не хватило (типа нет / тип не узнан / это не оружие для этой руки).
  #
  # ⚠ У первого поколения печати строка остаётся в `unresolved` И ПОСЛЕ 3.199,
  # хотя число сведено: сводка живёт в `report.weapons`, а ведро отвечает
  # на другой вопрос — «легло ли это в блок „Вещи“», и ответ там «нет».
  defp read_property(%{kind: kind} = property, where, state, context)
       when kind in @weapon_attack_kinds do
    hand = hand_of(where.slot, context)

    case {hand, wields(where.slot, hand, context)} do
      {nil, _} ->
        unresolved(state, where, property, {:weapon_base_type_unknown, kind})

      {_hand, {:weapon, _id}} ->
        Map.update!(state, :attack, fn attack ->
          Map.update(attack, hand, [{where, property}], &(&1 ++ [{where, property}]))
        end)

      {_hand, _not_a_weapon} ->
        unresolved(state, where, property, base_type_refusal(where.slot, kind, context))
    end
  end

  # Кусок набора: с номером — копится и решается группой (`resolve_mini_sets/2`),
  # без номера — как в первом поколении, «набор не назван». ⚠ У ruleset'а без
  # системы мини-сетов вовсе (ваниль) кусок с номером — не наша механика:
  # считать группы нечем, и «не сложить без сервера» было бы неправдой.
  defp read_property(%{kind: :mini_set, param: set_id} = property, where, state, context)
       when is_integer(set_id) do
    case MiniSets.minimum_group(context.ruleset) do
      nil -> not_ours(state, where, property, {:property_not_modelled, :mini_set})
      _smallest -> Map.update!(state, :pieces, &[{set_id, where, property} | &1])
    end
  end

  defp read_property(%{kind: :mini_set} = property, where, state, _context),
    do: unresolved(state, where, property, {:mini_set_group_unknown, nil})

  # `Quality` — артефактный сет, не крафт (слово Dan 11.09.2026). Пока лог
  # крафт ничем не помечал, эта строка была единственным местом, где можно
  # было сказать «крафтовые не посчитаны»; во втором поколении пометка есть
  # (`[CRAFT]` и `CRAFT ITEMS`), и `Quality` — просто не наша механика.
  defp read_property(%{kind: :quality} = property, where, state, %{counts: counts}) do
    if Map.has_key?(counts, :craft_items) do
      not_ours(state, where, property, {:property_not_modelled, :quality})
    else
      unresolved(state, where, property, {:named_item_flag_missing, :quality})
    end
  end

  # ------------------------------------------------------------------- фиты --

  # 🔴 СТУПЕНЬ — ЭТО НОМЕР ВЗЯТИЯ, и по ней здесь считаются копии (задача
  # 3.204). До неё второй раз тот же фит с вещей не давал ничего вовсе, и это
  # было устройством модели («An item lends the feat, not a number of copies of
  # it»); слово Dan 13.09.2026 его сняло, а цену назвал его собственный билд:
  # игра печатает 1503 HP, модель печатала 1437.
  #
  # Четыре случая, и каждый отвечает на свой вопрос:
  #
  #   * фит ещё не объявлен — обычное первое взятие;
  #   * та же строка со ТОЙ ЖЕ ступенью со второго предмета (`Epic Toughness II`
  #     на поясе при `II` на сапогах у Хнюпиуса) — ОДИН и тот же фит, а не
  #     второе взятие. Это измерено игрой, а не выведено: 1503 = 906 × 1.66,
  #     то есть ровно два взятия при трёх строках. Строка «легла», просто
  #     не прибавила;
  #   * ДРУГАЯ ступень повторяемого фита без выбора (`III` при `II`) — ещё одно
  #     взятие, и именно его теряла прежняя модель;
  #   * повторяемый фит С ВЫБОРОМ (`Epic energy resistance (Fire)` с двух
  #     предметов) — по-прежнему невыразим, и это открытая половина задачи 3.29:
  #     повторяется там ПАРА, а какую копию одалживает предмет, лог не говорит.
  #
  # ⚠ И повторяемый фит БЕЗ ступени, объявленный дважды, — туда же, а не
  # в «легла, но не прибавила»: игра свои копии нумерует (в движке это
  # `Epic Toughness I..X`, десять отдельных строк), значит строка без номера —
  # это лог, которого мы не понимаем, а не доказательство, что копия одна.
  # Ветка стоит ВЫШЕ проверки на совпадение ключа именно поэтому: иначе две
  # одинаковые безномерные строки молча схлопнулись бы в одно взятие.
  # ⚠ Спрашивается `FeatChoices.repeats_same_value?/2`, а НЕ
  # `GearFeats.stackable?/2` (задача 3.210), и разница ровно в одном фите:
  # `Epic energy resistance` повторяет ОДНО И ТО ЖЕ значение законно
  # (`distinct?: false`), то есть ступень у него — такой же номер взятия, как
  # у `Epic toughness`. `stackable?/2` для него `false` и обязана такой
  # остаться: на ней висит развилка интерфейса «счётчик или строка на значение»
  # (`BuildCalculatorWeb.Builder.GearPanel`), и widening отняло бы у фита выбор
  # стихии. Здесь вопрос другой — «считается ли вторая запись вторым взятием».
  defp read_feat(entry, where, property, state, ruleset) do
    rank = Map.get(property, :rank)
    key = {entry, rank}
    stackable? = FeatChoices.repeats_same_value?(feat_id(entry), ruleset)

    cond do
      entry not in state.feats ->
        declare(entry, key, where, property, state)

      stackable? and is_nil(rank) ->
        unresolved(state, where, property, {:feat_repeat_not_expressible, feat_id(entry)})

      key in state.feat_keys ->
        applied(state, where, property, landing_of(entry), false, :already_declared)

      stackable? ->
        declare(entry, key, where, property, state)

      FeatChoices.repeatable?(feat_id(entry), ruleset) ->
        unresolved(state, where, property, {:feat_repeat_not_expressible, feat_id(entry)})

      true ->
        applied(state, where, property, landing_of(entry), false, :already_declared)
    end
  end

  defp declare(entry, key, where, property, state) do
    state
    |> Map.update!(:feats, &[entry | &1])
    |> Map.update!(:feat_keys, &[key | &1])
    |> applied(where, property, landing_of(entry))
  end

  defp feat_entry(property, ruleset) do
    case Map.get(property, :param) do
      id when is_atom(id) and not is_nil(id) -> known_feat(id, id, ruleset)
      {id, nil} when is_atom(id) -> known_feat(id, id, ruleset)
      {id, choice} when is_atom(id) and is_atom(choice) -> known_feat(id, {id, choice}, ruleset)
      other -> {:error, {:feat_unknown, other}}
    end
  end

  # ⚠ Проверка против ruleset'а, а не против «вызывающий же разобрал»: билд
  # открывается тем ruleset'ом, в котором собран, и фит, которого в нём нет
  # (выключенное шардом владение, старый снапшот), обязан быть назван, а не
  # молча объявлен надетым.
  defp known_feat(id, entry, ruleset) do
    if Map.has_key?(ruleset.feats, id), do: {:ok, entry}, else: {:error, {:feat_unknown, id}}
  end

  defp feat_id({id, _choice}), do: id
  defp feat_id(id) when is_atom(id), do: id

  defp landing_of({id, choice}), do: {:feat, id, choice}
  defp landing_of(id) when is_atom(id), do: {:feat, id}

  # --------------------------------------------------------------------- AC --

  # Тип AC решает не эта функция: она спрашивает таблицу слотов ruleset'а.
  # Слота там нет вовсе — `{:slot_unknown, …}`; слот есть, а типа у него нет —
  # спрашивается БАЗОВЫЙ ТИП предмета: сначала по НАПЕЧАТАННОМУ ИМЕНИ типа
  # (`ac_type_by_base_type`, задача 3.213 — наручи → броня, перчатки →
  # отклонение), потом по опознанному предмету (щит → тип его категории, любой
  # другой опознанный → запасной тип слота, задача 3.206); ничего из этого —
  # `{:ac_type_unknown, …}` С НАЗВАННЫМИ АЛЬТЕРНАТИВАМИ, чтобы игрок знал,
  # в какое из полей вписать число руками.
  #
  # ⚠ Порядок веток сегодня ничего не решает — у `arms` пусто всё, кроме первой,
  # у `left_hand` пусто ровно она, — и это проверено тестом, а не обещано:
  # слот, у которого однажды окажутся обе записи, ответит по НАПЕЧАТАННОМУ
  # типу, потому что это самое точное из двух утверждений о предмете.
  defp ac_type(slot, %{ruleset: ruleset, bases: bases, texts: texts}) do
    case Enum.find(ruleset.gear.item_slot_ac_types, &(&1.id == slot)) do
      nil ->
        {:error, {:slot_unknown, slot}}

      %{ac_type: nil} = row ->
        base = Map.get(bases, slot, :unknown)
        by_base_type = Map.get(row, :ac_type_by_base_type) || %{}
        printed = with text when is_binary(text) <- Map.get(texts, slot), do: normalize_name(text)
        by_category = Map.get(row, :ac_type_by_worn_category) || %{}
        otherwise = Map.get(row, :ac_type_otherwise)

        cond do
          is_binary(printed) and Map.has_key?(by_base_type, printed) ->
            {:ok, Map.fetch!(by_base_type, printed)}

          match?({:worn, _, _}, base) and Map.has_key?(by_category, elem(base, 1)) ->
            {:ok, Map.fetch!(by_category, elem(base, 1))}

          match?({:worn, _, _}, base) and not is_nil(otherwise) ->
            {:ok, otherwise}

          match?({:weapon, _}, base) and not is_nil(otherwise) ->
            {:ok, otherwise}

          true ->
            {:error, {:ac_type_unknown, slot, row.ac_type_alternatives}}
        end

      %{ac_type: type} ->
        {:ok, type}
    end
  end

  # Собранные строки AC — в числа по типам. Складывающиеся типы (`dodge`)
  # суммируются, остальные спорят, и побеждает наибольшая; обе стороны правила
  # читаются из данных (`ac_same_type.cumulative`, `ac_same_type.gear_vs_gear`),
  # ни одного имени типа здесь нет.
  #
  # ⚠ Проигравшая строка остаётся в `applied` с `counted?: false`: она прочитана
  # и понята, просто её число в итог не вошло. Соврать «учтено» нельзя, потерять
  # — тем более.
  defp resolve_ac(rows, ruleset) do
    same = ruleset.gear.ac_same_type

    rows
    |> Enum.reverse()
    |> Enum.group_by(fn {type, _value, _where, _property} -> type end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce({%{}, []}, fn {type, group}, {ac, entries} ->
      cumulative? = type in same.cumulative or same.gear_vs_gear == :sum
      values = for {_type, value, _where, _property} <- group, do: value
      winner = unless cumulative?, do: Enum.find_index(values, &(&1 == Enum.max(values)))
      total = if cumulative?, do: Enum.sum(values), else: Enum.max(values)

      entries =
        entries ++
          for {{_type, value, where, property}, index} <- Enum.with_index(group) do
            counted? = cumulative? or index == winner
            note = unless counted?, do: :superseded_by_larger_same_type
            entry(where, property, {:ac, type, value}, counted?, note)
          end

      {Map.put(ac, type, total), entries}
    end)
  end

  # -------------------------------------------- поглощение стихий (3.210) --

  defp energy_type_ids(%{ruleset: ruleset}),
    do: for(%{id: id} <- Map.get(ruleset, :resistance_energy_types) || [], do: id)

  # Вид урона, который секция «Резисты» не показывает — и ПОЧЕМУ. Оба слова
  # приходят из данных; здесь только перевод слова в форму отказа.
  #
  # ⚠️ Спрашивается лишь у имени, которого словарь стихий не узнал
  # (`{:unresolved, text}`): узнанное имя — это уже стихия, и второй вопрос
  # ей задавать нечего. Загрузчик держит два списка непересекающимися.
  defp excluded_damage_type(%{param: {:unresolved, text}}, %{ruleset: ruleset}) do
    key = normalize_name(text)

    Enum.find_value(
      Map.get(ruleset, :resistance_excluded_types) || [],
      :not_excluded,
      fn %{id: id, verdict: verdict, log_names: names} ->
        if key in names, do: {:ok, excluded_reason(verdict, id)}
      end
    )
  end

  defp excluded_damage_type(_property, _context), do: :not_excluded

  # `decided` — получатель наш, а решение владельца эту механику не считает;
  # `not_absorbed` — такого поглощения не бывает в самой игре. Разные фразы
  # у разных причин, и слово выбирают данные.
  defp excluded_reason(:decided, id), do: {:decided_not_modelled, id}
  defp excluded_reason(:not_absorbed, id), do: {:property_not_modelled, id}

  # Собранные строки поглощения — в числа по стихиям. Правило свода из данных
  # (`resistance_stacking.gear_vs_gear`): вещь против вещи — **наибольшая**
  # («only the highest resistance granted by a spell or (equipped) item is
  # used», `fandom:Damage resistance`, revid 68743).
  #
  # ⚠️ Снапшот без правила сводится тем же максимумом, а не отказом, и это то же
  # умолчание, что у AC (`ac_same_type.gear_vs_gear`): максимум есть нижняя
  # граница обоих чтений, а правило ванильное по источнику и потому действует
  # на оба ruleset'а.
  #
  # ⚠️ Проигравшая строка остаётся в `applied` с `counted?: false` и тем же
  # словом, что у AC одного типа: она прочитана и понята, просто её число
  # в итог не вошло.
  defp resolve_resistances(rows, ruleset) do
    sum? = stacking_rule(ruleset) == :sum

    rows
    |> Enum.reverse()
    |> Enum.group_by(fn {type, _value, _where, _property} -> type end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce({%{}, []}, fn {type, group}, {resistances, entries} ->
      values = for {_type, value, _where, _property} <- group, do: value
      winner = unless sum?, do: Enum.find_index(values, &(&1 == Enum.max(values)))
      total = if sum?, do: Enum.sum(values), else: Enum.max(values)

      entries =
        entries ++
          for {{_type, value, where, property}, index} <- Enum.with_index(group) do
            counted? = sum? or index == winner
            note = unless counted?, do: :superseded_by_larger_same_type
            entry(where, property, {:resistance, type, value}, counted?, note)
          end

      {Map.put(resistances, type, total), entries}
    end)
  end

  defp stacking_rule(ruleset) do
    case Map.get(ruleset, :resistance_stacking) do
      %{gear_vs_gear: rule} -> rule
      _absent -> :max
    end
  end

  # ------------------------------------------------------------ базовый тип --

  # Что напечатанный базовый тип значит для справочника: оружие (`ruleset.
  # weapons[].name`), предмет категории надетого (`gear.worn`, по `name`
  # строки — у строки источника имён бывает два через запятую, «Studded
  # leather armor, Hide armor», и оба она), ничего из этого — `{:unresolved,
  # text}`; `:unknown`, когда лог типа не напечатал вовсе.
  #
  # ⚠ Сверяется ИМЯ, а не строка `baseitems.2da`: таблицы «строка → наш id»
  # в данных нет, а имя в логе — то же английское имя, которым оружие названо
  # в справочнике (`Warhammer` = `Warhammer`, `Bastard Sword` = `Bastard sword`).
  # Строка едет рядом (`base_item`) для провенанса и ручной сверки с хаком.
  defp resolve_base(%{base_type: text}, ruleset) when is_binary(text) do
    key = normalize_name(text)

    cond do
      id = weapon_by_name(key, ruleset) -> {:weapon, id}
      worn = worn_by_name(key, ruleset) -> worn
      true -> {:unresolved, text}
    end
  end

  defp resolve_base(_item, _ruleset), do: :unknown

  defp weapon_by_name(key, ruleset) do
    Enum.find_value(Map.get(ruleset, :weapons) || %{}, fn {id, record} ->
      name = Map.get(record, :name)
      if is_binary(name) and normalize_name(name) == key, do: id
    end)
  end

  defp worn_by_name(key, ruleset) do
    Enum.find_value(Worn.categories(ruleset), fn category ->
      Enum.find_value(category.items, fn item ->
        names = item.name |> to_string() |> String.split(",") |> Enum.map(&normalize_name/1)
        if key in names, do: {:worn, category.id, item.id}
      end)
    end)
  end

  defp normalize_name(text),
    do: text |> String.trim() |> String.downcase() |> String.replace(~r/\s+/u, " ")

  # ------------------------------------------------------------ база доспеха --

  # 🔴 Доспех лог называет не типом, а ЧИСЛОМ: `[CHEST] Нагрудник Призрака
  # [BaseAC:8]` (третье поколение печати, 18.09.2026). Значит и искать его надо
  # числом — по `base_ac` строк той категории `gear.worn`, которую называет сам
  # слот (`worn_category_by_base_ac`); загрузчик держит `base_ac` внутри
  # категории уникальным, иначе число указывало бы на две строки сразу.
  #
  # ⚠ ИМЕНИ ПРЕДМЕТА ЗДЕСЬ НЕ СПРАШИВАЮТ ВОВСЕ. «Нагрудник Призрака» с базой 8
  # — это латы, а не кольчуга с нагрудником (`chainmail`, база 5), и перевод
  # имени об этом не знает. Ровно эту подстановку по имени запрещает §3.
  #
  # ⚠ Ноль — законная база («роба, одежда»), и он ДОЛЖЕН лечь: AC-бонусы монаха
  # гасит надетый предмет с НЕНУЛЕВОЙ базой, а роба с `[BaseAC:0]` их не гасит
  # (слово Dan 19.08.2026). Роба Мокси — живой контроль этого: 72 = 72.
  #
  # ⚠ Слот, у которого правила нет, в отчёт не попадает; предмет, у которого
  # база не напечатана, попадает — с названной причиной. «Доспех надет, базы
  # не знаем» и «доспеха нет» — разные ответы, и раньше они выглядели одинаково.
  defp resolve_worn(items, %{ruleset: ruleset}) do
    rows = ruleset.gear.item_slot_ac_types
    slots = for row <- rows, not is_nil(row.worn_category_by_base_ac), do: row.id

    # Слот, в котором лог напечатал базу, а снапшот про него молчит: число
    # прочитано и обязано быть названо, а не выброшено.
    stray = for item <- items, Map.has_key?(item, :base_ac), item.slot not in slots, do: item.slot

    for slot <- slots ++ Enum.uniq(stray), reduce: {%{}, %{}} do
      {worn, report} ->
        row = Enum.find(rows, &(&1.id == slot))
        item = Enum.find(items, &(&1.slot == slot))
        {landed, entry} = worn_of(item, row, ruleset)

        {Map.merge(worn, landed), Map.put(report, slot, entry)}
    end
  end

  defp worn_of(nil, _row, _ruleset), do: {%{}, nil}

  defp worn_of(item, row, ruleset) do
    category = row && row.worn_category_by_base_ac
    base = Map.get(item, :base_ac)

    case {category, base} do
      {_category, nil} ->
        {%{}, worn_entry(item, nil, nil, {:armor_base_not_printed, item.slot})}

      {nil, _base} ->
        {%{}, worn_entry(item, base, nil, {:armor_base_rule_missing, item.slot})}

      {category, base} ->
        case worn_by_base_ac(ruleset, category, base) do
          nil -> {%{}, worn_entry(item, base, nil, {:armor_base_unresolved, base})}
          id -> {%{category => id}, worn_entry(item, base, {:worn, category, id}, nil)}
        end
    end
  end

  defp worn_entry(item, base, wears, reason),
    do: %{slot: item.slot, name: item.name, base_ac: base, wears: wears, reason: reason}

  defp worn_by_base_ac(ruleset, category, base) do
    with %{items: items} <- Worn.category(ruleset, category),
         %{id: id} <- Enum.find(items, &(&1.base_ac == base)) do
      id
    else
      _no_such_row -> nil
    end
  end

  # ----------------------------------------------------------------- руки --

  defp hand_slots(ruleset) do
    for row <- ruleset.gear.item_slot_ac_types,
        hand = Map.get(row, :hand),
        not is_nil(hand),
        into: %{},
        do: {hand, row.id}
  end

  defp hand_of(slot, %{hands: hands}),
    do: Enum.find_value(hands, fn {hand, hand_slot} -> if hand_slot == slot, do: hand end)

  # Что из опознанного базового типа НАДЕВАЕТСЯ в эту руку: оружие — в любую
  # (законность хвата и владения — вопрос `Rules.GearWeapon`, он назовёт отказ
  # в самом билде); предмет категории надетого — только во вторую и только
  # если категория её занимает (`occupies_off_hand?`, щит). Остальное — `nil`.
  defp wields(slot, hand, %{bases: bases, ruleset: ruleset}) do
    case {Map.get(bases, slot, :unknown), hand} do
      {{:weapon, id}, _hand} ->
        {:weapon, id}

      {{:worn, category, item}, :off} ->
        case Worn.category(ruleset, category) do
          %{occupies_off_hand?: true} -> {:worn, category, item}
          _elsewhere -> nil
        end

      _nothing ->
        nil
    end
  end

  defp base_type_refusal(slot, kind, %{bases: bases, texts: texts}) do
    case Map.get(bases, slot, :unknown) do
      :unknown ->
        {:weapon_base_type_unknown, kind}

      {:unresolved, text} ->
        {:base_type_unresolved, text}

      _resolved_elsewhere ->
        {:base_type_not_a_weapon, Map.get(texts, slot) || Atom.to_string(slot)}
    end
  end

  # Что надето в каждой руке, сколько это даёт к атаке и что легло в билд.
  #
  # 🔴 Правило свода — из данных (`gear.weapon_import_rule`, задача 3.199,
  # слово Dan 12.09.2026): у предмета чисел бывает ДВА, а модель держит одно
  # на руку. Здесь нет ни `max`, ни списка рук, ни имён слотов: руки называет
  # `Rules.Gear.hands/0`, слот руки — таблица слотов ruleset'а (поле `hand`).
  #
  # ⚠ Ключи есть у ОБЕИХ рук всегда, даже когда руки пусты: «в этой руке
  # ничего» — ответ, а отсутствие ключа было бы отсутствием ответа.
  defp resolve_hands(items, state, %{hands: hands, ruleset: ruleset} = context) do
    empty_gear = %{
      worn: %{},
      weapon: nil,
      weapon_attack: 0,
      off_hand_weapon: nil,
      off_hand_weapon_attack: 0
    }

    Enum.reduce(Gear.hands(), {%{}, empty_gear, [], []}, fn hand,
                                                            {weapons, gear, applied, unresolved} ->
      slot = Map.get(hands, hand)
      item = slot && Enum.find(items, &(&1.slot == slot))

      case item do
        nil ->
          {Map.put(weapons, hand, nil), gear, applied, unresolved}

        %{name: name} ->
          numbers = weapon_numbers(item)
          attack = attack_number(numbers, ruleset)
          wields = wields(slot, hand, context)
          rows = Map.get(state.attack, hand, [])
          {rows_applied, rows_unresolved} = attack_entries(rows, attack, numbers, hand)

          weapon = %{
            slot: slot,
            name: name,
            attack: attack,
            from: numbers |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
            base_type: Map.get(item, :base_type),
            wields: wields
          }

          {Map.put(weapons, hand, weapon), put_hand(gear, hand, wields, attack),
           applied ++ rows_applied, unresolved ++ rows_unresolved}
      end
    end)
  end

  defp weapon_numbers(%{properties: properties}) do
    for %{kind: kind} = property <- properties,
        kind in @weapon_attack_kinds,
        {:ok, value} <- [number(property)],
        do: {kind, value}
  end

  # Строки чисел атаки той руки, в которой лежит опознанное оружие: победившая
  # — `counted?`, вторая — прочитана и не вошла (`:superseded_by_larger_same_type`,
  # тем же словом, что у AC одного типа). Когда чисел два, а правила свода
  # в снапшоте нет, обе строки уходят в `unresolved` — выбирать наугад нельзя.
  defp attack_entries([], _attack, _numbers, _hand), do: {[], []}

  defp attack_entries(rows, nil, numbers, _hand) when numbers != [] do
    kinds = numbers |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    {[],
     for(
       {where, property} <- rows,
       do: refusal(where, property, {:weapon_numbers_not_reconciled, kinds})
     )}
  end

  defp attack_entries(rows, attack, _numbers, hand) do
    winner =
      Enum.find_index(rows, fn {_where, property} -> Map.get(property, :value) == attack end)

    entries =
      for {{where, property}, index} <- Enum.with_index(rows) do
        value = Map.get(property, :value)
        counted? = index == winner
        note = unless counted?, do: :superseded_by_larger_same_type
        entry(where, property, {:weapon_attack, hand, value}, counted?, note)
      end

    {entries, []}
  end

  defp put_hand(gear, :main, {:weapon, id}, attack),
    do: %{gear | weapon: id, weapon_attack: attack || 0}

  defp put_hand(gear, :off, {:weapon, id}, attack),
    do: %{gear | off_hand_weapon: id, off_hand_weapon_attack: attack || 0}

  defp put_hand(gear, :off, {:worn, category, item}, _attack),
    do: %{gear | worn: Map.put(gear.worn, category, item)}

  defp put_hand(gear, _hand, _nothing, _attack), do: gear

  # ⚠ Числа нет ни у одной строки — это `nil`, а не ноль: предмет в руке есть,
  # а прибавки к атаке лог у него не назвал, и «назвал ноль» было бы вторым
  # утверждением (та же граница, что у `number/1` ниже).
  defp attack_number([], _ruleset), do: nil

  # Одно число — сводить нечего, и правило здесь не спрашивается вовсе:
  # снапшот без правила обязан отдавать единственное число как есть.
  defp attack_number([{_kind, value}], _ruleset), do: value

  # Два числа и больше — отвечает правило из данных. Его нет — не сводим
  # и не выбираем наугад: `attack: nil` при непустом `from` и значит
  # «числа назвали двое, свести нечем».
  defp attack_number(numbers, ruleset) do
    case Map.get(ruleset.gear, :weapon_import_rule) do
      :max -> numbers |> Enum.map(&elem(&1, 1)) |> Enum.max()
      nil -> nil
    end
  end

  # ------------------------------------------------------------- мини-сеты --

  # Куски по номеру набора → группы от `minimum_group`, и сверка с шапкой.
  #
  # 🔴 Шапка (`MINI SET PIECES`) — это `number_minisets` скрипта, то есть уже
  # посчитанный `Nmini`, и она берёт верх: строка `Use Item (Mini Set)`
  # печатается не на каждом экземпляре предмета (у Бора — четыре куска
  # по шапке и ни одной строки), так что группы по `[SetID]` бывают неполны.
  # Сошлись — в `mini_sets` ложатся группы; нет — одна группа размером в шапку
  # (для `Nmini` то же число) и оговорка в `notes`.
  defp resolve_mini_sets(rows, %{counts: counts, ruleset: ruleset}) do
    smallest = MiniSets.minimum_group(ruleset)
    rows = Enum.reverse(rows)

    sizes = rows |> Enum.map(&elem(&1, 0)) |> Enum.frequencies()

    groups =
      if is_nil(smallest),
        do: [],
        else: sizes |> Map.values() |> Enum.filter(&(&1 >= smallest)) |> Enum.sort(:desc)

    entries =
      for {set_id, where, property} <- rows do
        counted? = not is_nil(smallest) and Map.fetch!(sizes, set_id) >= smallest
        note = unless counted?, do: :lone_piece
        entry(where, property, {:mini_set, set_id}, counted?, note)
      end

    derived = Enum.sum(groups)

    {mini_sets, notes} =
      case Map.get(counts, :mini_set_pieces) do
        nil -> {groups, []}
        _header when is_nil(smallest) -> {[], []}
        0 when derived == 0 -> {[], []}
        0 -> {[], [{:mini_set_groups_unverified, 0, groups}]}
        ^derived -> {groups, []}
        header -> {[header], [{:mini_set_groups_unverified, header, groups}]}
      end

    {mini_sets, groups, entries, notes}
  end

  # Крафтовые (именные) вещи: `CRAFT ITEMS − MINI SET PIECES` (moduledoc:
  # шапка печатает `Ctotal`, а не одни крафтовые), пометки `[CRAFT]` — сверка.
  # Без шапки — по пометкам; без того и другого — ноль, как в первом поколении.
  defp resolve_named_items(items, groups, %{counts: counts, ruleset: ruleset}) do
    marked = for %{craft?: true, name: name} <- items, do: name
    pieces = Map.get(counts, :mini_set_pieces) || Enum.sum(groups)

    case {Map.get(counts, :craft_items), MiniSets.minimum_group(ruleset)} do
      {nil, _} ->
        {length(marked), marked, []}

      {_craft, nil} ->
        {0, marked, []}

      {craft, _} when craft < pieces ->
        {0, marked, [{:craft_items_below_pieces, craft, pieces}]}

      {craft, _} ->
        named = craft - pieces

        notes =
          if named == length(marked),
            do: [],
            else: [{:craft_marks_disagree, named, length(marked)}]

        {named, marked, notes}
    end
  end

  # ------------------------------------------------------------------ отчёт --

  defp applied(state, where, property, landing, counted? \\ true, note \\ nil),
    do: Map.update!(state, :applied, &[entry(where, property, landing, counted?, note) | &1])

  defp not_ours(state, where, property, reason),
    do: Map.update!(state, :not_ours, &[refusal(where, property, reason) | &1])

  defp unresolved(state, where, property, reason),
    do: Map.update!(state, :unresolved, &[refusal(where, property, reason) | &1])

  defp entry(where, property, landing, counted?, note) do
    %{
      slot: where.slot,
      item: where.item,
      kind: property.kind,
      raw: property.raw,
      landed: landing,
      counted?: counted?,
      note: note,
      reason: nil
    }
  end

  defp refusal(where, property, reason) do
    %{
      slot: where.slot,
      item: where.item,
      kind: property.kind,
      raw: property.raw,
      landed: nil,
      counted?: false,
      note: nil,
      reason: reason
    }
  end

  # ----------------------------------------------------------------- мелочи --

  defp known(property, allowed, refusal) do
    case Map.get(property, :param) do
      value when is_atom(value) ->
        if value in allowed, do: {:ok, value}, else: {:error, {refusal, value}}

      other ->
        {:error, {refusal, other}}
    end
  end

  # ⚠ Ноль — законное число и проходит насквозь; `nil` — это «лог напечатал
  # строку без числа», и молчаливым нулём такое становиться не должно.
  defp number(property) do
    case Map.get(property, :value) do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, {:value_missing, property.kind}}
    end
  end

  # Имя свойства так, как его опознал вызывающий: **атом** — узнал (ключ его
  # закрытой таблицы имён), **строка** — не узнал. Разницу читает единственный
  # вызывающий, клауза `:other`, и она же переводит её в два разных ведра
  # (задача 3.221). ⚠️ Возвращать «строку по умолчанию» здесь нельзя: тогда
  # «не узнали» снова стало бы неотличимо от «узнали».
  defp name_of(property) do
    case Map.get(property, :param) do
      {:unresolved, text} -> text
      nil -> property.raw
      name -> name
    end
  end

  # Нули из сумм убираются: «вписал и стёр» и «не вписывал» — один ответ у всех
  # полей этой структуры, и пустая мапа кодируется в ссылку как пустая.
  defp drop_zeros(map), do: for({key, value} <- map, value != 0, into: %{}, do: {key, value})
end
