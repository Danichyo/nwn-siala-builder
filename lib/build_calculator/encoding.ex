defmodule BuildCalculator.Encoding do
  @moduledoc """
  The whole build, in a link.

  v1 has no database (CLAUDE.md §9): a build is shared by URL, so this codec is
  load-bearing rather than a convenience. Three properties matter more than
  compactness:

    * **Versioned.** The code starts with the schema version and a dot —
      `1.eJx…`. `decode/1` dispatches on it, so adding a v2 never breaks a link
      somebody already pasted into Discord. The payload also carries the
      `ruleset_version`, and the build is recomputed with *that* ruleset, not
      with whatever is newest.
    * **Whitelisted.** Every id in the payload is a string, and it becomes an
      atom only by being found in `BuildCalculator.Data` (see
      `BuildCalculator.Ids`). Ids the data no longer knows are
      dropped and reported, never `String.to_atom/1`-ed.
    * **Total.** Any malformed input returns `{:error, reason}`. Nothing here
      raises, so a mangled link opens an empty builder with a message instead of
      a 500.

  ## Layout

  A binary, deflated, then URL-safe base64 without padding. Strings are
  `<<size::8, bytes>>`; ids that repeat (classes, feats, skills, spells) are
  listed once in a table and referenced by index; consecutive levels of the same
  class are run-length encoded, because that is what a real build looks like.

      <<v>>                                  schema version again — catches truncation
      str    ruleset_version
      str    race        ("" for none)
      str    alignment   ("" for none)
      <<n>>  n x (str ability, <<score>>)
      <<n>>  n x str                         class table
      <<n>>  n x <<class_index, count>>      levels, run-length encoded
      <<n>>  n x <<level, ability_index>>    the +1 on every fourth level
      <<n::16>>  n x str                     feat table
      <<n::16>>  n x (<<level>>, str slot, <<feat_index::16>>)
      <<n>>  n x str                         skill table
      <<n::16>>  n x <<level, skill_index, ranks>>
                                             ⚠️ level 0 = прибавка с вещей,
                                             а не ранги (см. ниже)

  **v2 appends** the gear the player typed and the spells they chose — both are
  part of the build (CLAUDE.md §6), so both travel in the link:

      <<n>>  n x (str ability, <<bonus>>)    gear ability bonuses
      <<n>>  n x (str ac_type, <<bonus>>)    gear AC, one number per type
      <<saves>>                              gear bonus to all saves
      <<n::16>>  n x str                     spell table
      <<n::16>>  n x <<level, circle, index, spell_index::16>>

  A v1 code carries neither, which decodes to an empty gear set and no spells —
  the state a build had before the feature existed. **v1 keeps decoding**: the
  frozen fixture in the test suite is somebody's Discord message.

  ## Фит с выбором — и почему версия не выросла

  Слот может держать не голый фит, а пару: `Spell focus` берётся В школе,
  `Favored enemy` — против расы (`Rules.Build`). Записать это можно было двумя
  способами, и они не равноценны.

  Новая секция в хвосте потребовала бы **v3**, а версия входит в код первым
  байтом и в префикс строки — то есть **у каждого билда сменился бы код**,
  включая те, где никакого выбора нет. Ссылка, лежащая в чужом Discord,
  продолжала бы открываться (клауза `"2."` никуда не девается), но «тот же
  билд» стал бы иметь два разных кода, и сравнить их было бы нечем.

  Поэтому выбор едет **внутри строки таблицы фитов**: `"spell_focus|evocation"`
  вместо `"spell_focus"`. Раскладка байт не менялась ни на бит, и билд без
  выборов кодируется побайтово так же, как до этой правки, — что и проверяет
  замороженная фикстура. Разделитель `|` в id не встречается (там только
  `[a-z0-9_]`), а до base64 он не доживает: payload length-prefixed, экранировать
  нечего.

  ⚠️ Плата за это честная и названа: код с выбором, открытый **старой** сборкой
  приложения, потеряет такой фит — строка не найдётся в словаре и уедет
  в `dropped` как `{:unknown_feat, "spell_focus|evocation"}`. То есть игрок
  увидит сообщение «из ссылки выпало», а не молчание. Обратной дороги нет ни
  у одного из двух вариантов: v3 та же ссылка встретила бы
  `{:error, :unknown_version}` и не открылась бы вовсе.

  ## Фит с вещи — тем же приёмом, третий раз, и снова без новой версии

  Фит может прийти **с предмета**: слота он не занимает, но требования
  выполняет (`Rules.GearFeats`, задача 3.3). Живёт он в `gear`, а не в
  `build.feats`, — то есть по раскладке §Layout ему место в хвосте v2, рядом
  с остальными вещами. Так делать нельзя: **новая секция в хвосте меняет байты
  у КАЖДОГО билда**, включая те, где никаких фитов с вещи нет, — счётчик `0`
  всё равно занимает байт. Замороженная фикстура тут не придирка: она
  и означает «у того же билда тот же код».

  Поэтому объявленные фиты едут строками **той же таблицы фитов**, с ключом
  слота `"gear"` и уровнем `0`:

      <<0>>  "gear"  <<feat_index::16>>

  Билд без таких фитов не получает ни одной лишней строки и кодируется
  побайтово как раньше. Уровень `0` выбран не для красоты: у персонажа уровня
  `0` не бывает, значит строка не может быть спутана с настоящим слотом
  настоящего уровня даже при ручной правке кода.

  ⚠️ **Индекс указывает на пик целиком, а не на голый id** — с задачи 3.97,
  и формат от этого не изменился ни на байт: имя пишет тот же `feat_key/1`,
  который у слота уже умеет `"skill_focus|discipline"`, а декодер уже умел
  такую строку прочитать. Здесь стояло срезание — пара разбиралась, значение
  выбрасывалось и честно называлось в `dropped` («объявление с вещи параметра
  не несёт»). Объявление его несёт (решение Dan, 25.08.2026), срезание снято,
  и `dropped_choice/1` вместе с ним. Голый id по-прежнему пишется голым,
  поэтому уже расшаренная ссылка кодируется байт в байт как раньше и
  открывается тем же билдом.

  ⚠️ Плата та же, что у выбора фита, и так же названа: код с фитом с вещи,
  открытый **старой** сборкой, потеряет эту строку — `Ids.fetch_slot/2` не
  знает ключа `"gear"` и отдаст `:error`, то есть игрок увидит
  «из ссылки выпало: unknown_slot gear», а не молчание. Билд при этом
  откроется целиком, только без объявления.

  ⚠️ И ключ `"gear"` намеренно **не** добавлен в `Ids.fetch_slot/2`: там он стал
  бы валидным слотом и для кликов из браузера, то есть `pick_feat` смог бы
  положить фит в слот, которого ни один уровень не выдаёт. Строки с этим ключом
  разбирает `nest_feats/3` здесь, до всякого резолва слота.

  ## Прибавка к навыку с вещей — тем же приёмом, четвёртый раз

  Игрок вписывает «дисциплина +50» (`Rules.Gear`, задача 3.20), и это снова часть
  вещей, которой по раскладке §Layout место в хвосте v2. И снова нельзя: лишний
  счётчик в хвосте — это лишний байт **у каждого** билда, включая те, где никаких
  прибавок к навыкам нет.

  Поэтому прибавки едут строками **той же таблицы навыков**, с уровнем `0`:

      <<0>>  <<skill_index>>  <<bonus>>

  Уровень `0` работает ровно как псевдо-слот `"gear"` у фитов: уровня `0` у
  персонажа не бывает, значит строку не спутать с настоящей покупкой рангов даже
  при ручной правке кода. Билд без таких прибавок не получает ни одной лишней
  строки и кодируется побайтово как раньше — что и проверяет замороженная
  фикстура.

  ⚠️ Плата названа, и она та же: код с прибавкой к навыку, открытый **старой**
  сборкой, положит её в **ранги нулевого уровня** — то есть `Build.skill_ranks/3`
  их не увидит (он считает уровни от 1), а вот бюджет очков посчитает потраченным.
  Это единственный из четырёх приёмов, где старая сборка не скажет «выпало», а
  тихо покажет билд с меньшим числом свободных очков. Хуже альтернативы всё равно
  нет: v3 та же ссылка встретила бы `{:error, :unknown_version}`.

  ⚠️ И общая для всех чисел вещей плата, которую эта задача не меняет: `byte/1`
  режет отрицательное в `0`, а больше 255 — в 255. То есть штраф с предмета
  (`−2 STR`, «hide −5») через ссылку не проезжает; так ведут себя все четыре
  числа вещей с самого начала, и починка сменила бы байты у билдов, где вещи
  есть. Названо здесь, а не молчит.

  ## Оружие в руках — тем же приёмом, пятый раз, и снова без новой версии

  В вещах выбирается оружие и вписывается его число (`Rules.Gear` → `weapon`,
  `weapon_attack`; задача 3.5, часть B). По раскладке §Layout ему место в хвосте
  v2, и снова нельзя — по той же причине, что у фитов с вещи и прибавок
  к навыкам: **новая секция в хвосте меняет байты у КАЖДОГО билда**, включая те,
  где оружия нет, и версия входит в код первым байтом и в префикс строки. Тогда
  у одного и того же билда стало бы два разных кода, и сравнить их было бы нечем;
  а ссылка v3, открытая старой сборкой, встретила бы `{:error, :unknown_version}`
  и не открылась бы вовсе.

  Поэтому оружие едет **одной строкой таблицы фитов**, уровень `0`, а вся запись
  лежит в ключе слота:

      <<0>>  "weapon|<id>|<бонус атаки>"  <<0::16>>

  Ключ слота — свободный текст, который разбирает `nest_feats/3` **до**
  `Ids.fetch_slot/2` (точно как псевдо-слот `"gear"`), поэтому индекс фита в такой
  строке не читается вовсе и стоит нулём. Билд без оружия не получает ни одной
  лишней строки и кодируется побайтово как раньше — что и проверяет замороженная
  фикстура.

  ### ⚠️ Чисел было ДВА, стало одно, и версия из-за этого не выросла

  До задачи 3.52 у предмета было второе число — усиление
  (`"weapon|<id>|<атака>|<усиление>"`), и оно писалось **позиционно**, то есть
  его несут все уже расшаренные ссылки с оружием, даже там, где усиление равно
  нулю. Совместимости от нас не требовали (Dan, 19.08.2026: «я не создавал билды,
  использующие enchantment bonus и никто больше не пользовался билдером»), но
  ломать оказалось нечего: `weapon_numbers/1` терпел переменное число чисел
  и до правки.

  **Второе число при чтении СКЛАДЫВАЕТСЯ с первым, а не выбрасывается.** Стоит
  это ровно столько же, сколько игнорирование, и не имеет сценария, в котором
  врёт: сторона капа у обоих чисел общая всегда (Dan, 19.08.2026: «по механике
  nwn attack bonus и enchantment bonus должны быть равны в плане капа»), значит
  сумма даёт то же AB, что давали два терма. Игнорирование же тихо занизило бы
  билд, окажись «никто не пользовался» неточным хоть на одну ссылку.

  ⚠️ Клауза на два числа поэтому **не удалена**: она стоит ноль строк и остаётся
  единственной защитой от правленой руками ссылки. Новый кодер пишет одно число,
  и ссылка стала короче ровно на `|<усиление>`.

  ⚠️ Числа записаны **десятичным текстом**, а не байтами, и это не украшение: у
  четырёх остальных чисел вещей `byte/1` режет отрицательное в `0`, о чём ниже
  сказано отдельно, — а здесь минус проезжает целиком. Проклятое оружие с −2
  к атаке через ссылку не теряется.

  ⚠️ Плата названа, как у всех четырёх приёмов до этого: код с оружием, открытый
  **старой** сборкой, потеряет строку видимо — `Ids.fetch_slot/2` ключа не знает
  и отдаст `:error`, то есть игрок увидит «из ссылки выпало: unknown_slot
  weapon|scimitar|5». Билд при этом откроется целиком, только без оружия.

  ## Выбор у ВЫДАННОГО фита — тем же приёмом, шестой раз

  Фит может прийти от класса и всё равно требовать выбора: `Weapon of choice`
  выдаётся Мастеру оружия на 1-м классовом уровне и называет оружие
  (`Rules.Build` → `granted_choices`, задача 3.26). Слота у выдачи нет, значит
  в секции фитов §Layout ей места нет, а новая секция в хвосте — это лишний байт
  **у каждого** билда и смена версии в первом байте кода.

  Поэтому выбор выдачи едет строкой **той же таблицы фитов**, с ключом слота
  `"granted"` и настоящим уровнем выдачи:

      <<14>>  "granted"  <<feat_index::16>>

  Сам выбор лежит там же, где у пика в слоте, — в строке таблицы имён
  (`"weapon_of_choice|scimitar"`), то есть механизм ровно тот, что у выбора фита
  выше, и ничего нового не разбирается. ⚠️ Уровень здесь **настоящий**, а не `0`,
  как у фитов с вещи: выдача случается на уровне, и уровень — часть записи.
  Спутать с настоящим слотом нельзя всё равно, потому что `Ids.fetch_slot/2`
  ключа `"granted"` не знает и знать не должен (иначе клик из браузера смог бы
  положить фит в слот, которого ни один уровень не выдаёт).

  Билд без записанного выбора выдачи — то есть любая уже расшаренная ссылка —
  не получает ни одной лишней строки и кодируется побайтово как раньше, что
  и проверяет замороженная фикстура.

  ⚠️ Плата названа, как у всех приёмов до этого: код с выбором выдачи, открытый
  **старой** сборкой, потеряет строку видимо — `{:unknown_slot, "granted"}`, —
  билд откроется целиком, только Мастер оружия останется без записанного оружия
  и посчитается как считался до задачи 3.26.

  ## Надетое — тем же приёмом, седьмой раз (задача 3.41)

  В вещах выбирается **тип доспеха и размер щита** (`Rules.Gear` → `worn`,
  `Rules.Worn`). Из выбора берутся база AC и предел бонуса ловкости, то есть это
  часть билда и ехать в ссылке обязано. Новая секция в хвосте снова нельзя —
  довод тот же, что у шести приёмов выше: лишний байт **у каждого** билда и
  смена версии в первом байте кода.

  Поэтому надетое едет строками **таблицы фитов**, по одной на категорию,
  уровень `0`, а вся запись лежит в ключе слота:

      <<0>>  "worn|<категория>|<предмет>"  <<0::16>>

  🔴 **Старая ссылка открывается и даёт ТО ЖЕ ЧИСЛО, и это решение, а не
  везение.** В уже расшаренных кодах таких строк нет вовсе, значит `worn` пуст,
  значит предмета нет, базы нет и потолка ловкости нет — а вписанное под типом
  число остаётся ровно тем, чем было до задачи: бонусом. Иначе пришлось бы
  угадывать, что лежит внутри одного числа, а угадывать игровые числа запрещено
  (CLAUDE.md §3). Ссылка не «чинится молча» — она открывается как записана, и
  игрок сам называет предмет, если он есть.

  ⚠️ Обе половины пары проходят белый список: категория ищется среди объявленных
  ruleset'ом, предмет — среди предметов этой категории. Неизвестное теряется
  ПОИМЁННО (`{:unknown_worn, "worn|armor|mithral"}`), а не молча, — иначе ссылка
  на снятый из данных доспех открылась бы как «доспеха и не было», то есть
  с завышенным AC и без предела ловкости.

  ## Оружие ВТОРОЙ РУКИ — тем же приёмом, восьмой раз (задача 3.132)

  Вторая рука — оружие вместо щита или второй половины двуручного —
  добавилась своими двумя полями (`Rules.Gear` → `off_hand_weapon`,
  `off_hand_weapon_attack`; Dan, 28.08.2026: «многие билды берут 2 оружия
  вместо щита или двуручки … Можем ввести вторую руку? с возможностью
  выбрать оружие вместо щита и его attack bonus»). По раскладке §Layout ей
  снова место в хвосте v2, и снова нельзя — тот же довод в седьмой раз:
  новая секция в хвосте — это лишний байт **у КАЖДОГО** билда, а версия
  входит в код первым байтом и в префикс строки.

  Поэтому вторая рука едет **второй** строкой той же таблицы фитов, уровень
  `0`, СВОИМ псевдо-слотом:

      <<0>>  "offweapon|<id>|<бонус атаки>"  <<0::16>>

  ⚠️ **Не тем же ключом `"weapon"` с дописанной рукой.** Это нарочно —
  главная рука кодируется СТРОКОЙ `"weapon|<id>|<атака>"` без упоминания
  руки вовсе (см. выше), и любая ссылка, выпущенная до этой задачи, несёт
  ровно такую строку. Допиши к формату главной руки третье поле «рука» —
  и парсер, разбирающий `String.split(rest, "|")` позиционно
  (`weapon_slot/3`), либо потребовал бы менять уже написанный формат, либо
  завёл вторую ветку разбора внутри одного ключа. Отдельный ключ проще и не
  трогает byte-for-byte совместимость главной руки ни на один байт: билд без
  второй руки (то есть КАЖДАЯ уже расшаренная ссылка) не получает ни одной
  лишней строки и кодируется побайтово как раньше — это же проверяет
  замороженная фикстура `@frozen_v2`.

  Числа второй руки читаются ТЕМ ЖЕ разборщиком, что и главной
  (`weapon_numbers/1` и соседи), только под своим тегом — значит все его
  правила действуют и здесь без повторной записи: минус проезжает целиком
  (текст, не байт), потолок `@weapon_bonus_limit` тот же, а старая ссылка
  ДВУМЯ числами (эпоха до задачи 3.52) читалась бы суммой и для второй
  руки тоже, хотя писать их такими наш кодер уже давно не умеет ни для
  одной руки.

  ⚠️ Плата названа, как у всех приёмов до этого: код со второй рукой,
  открытый **старой** сборкой, потеряет строку видимо —
  `Ids.fetch_slot/2` ключа `"offweapon"` не знает и отдаст `:error`, то есть
  игрок увидит «из ссылки выпало: unknown_slot offweapon|mace|2». Билд при
  этом откроется целиком, только без второй руки.

  ## Выбор класса (домены клирика) — тем же приёмом, другая таблица

  У класса тоже бывает выбор, сделанный один раз навсегда (`Build.
  class_choices`, задача 3.14) — но не в СЛОТЕ, как у фита, а сам по себе,
  привязанный к id класса. Своей таблицы под это заводить не пришлось: класс
  уже перечислен один раз в таблице классов (`classes`, та же секция, что
  строит индекс для run-length-кодированных уровней), и ровно туда же,
  ровно тем же разделителем `|`, дописывается выбор — `"cleric|air,war"`
  вместо голого `"cleric"`. Несколько значений внутри одной ячейки разделены
  запятой: id значений домена, как и id всего остального, состоят только
  из `[a-z0-9_]`, так что запятая в них не встречается и не нуждается
  в экранировании.

  Билд без выбора класса (сегодня — любой билд без клирика, и клирик
  БЕЗ дописанных доменов тоже) кодируется побайтово так же, как до этой
  правки — версия не выросла по той же причине, что и у выбора фитов.
  Раздельный дроп: если сам класс не резолвится, лестница теряет ЦЕЛЫЕ
  уровни (как и раньше — это не новое поведение), а если не резолвится
  только значение выбора, класс и его уровни остаются, теряется только
  та часть выбора, которая не читается (`{:unknown_choice, "cleric|xyz"}`
  на каждое такое значение) — сохранённые уровни игрока терять из-за
  одного протухшего домена было бы куда дороже потерянного домена.
  """

  alias BuildCalculator.Data
  alias BuildCalculator.Rules.{Build, Gear}
  alias BuildCalculator.Ids

  @current_version 2

  # A real build encodes to a few hundred characters. The ceiling is here so a
  # hand-written code cannot ask us to inflate something enormous.
  @max_code_bytes 4096

  # В id встречаются только `[a-z0-9_]`, так что разделитель однозначен, а
  # экранировать его не нужно: payload length-prefixed, а до base64 он не
  # доживает.
  @choice_separator "|"

  # Псевдо-слот, под которым в таблице фитов едут фиты с вещи (см. moduledoc).
  # Настоящим слотом он не является нигде: `Ids.fetch_slot/2` его не знает, и
  # знать не должен.
  @gear_slot_key "gear"

  # Второй псевдо-слот той же таблицы — оружие в руках и его число
  # (см. moduledoc). Разбирается там же, где первый, и по той же причине.
  @weapon_slot_key "weapon"

  # Третий псевдо-слот той же таблицы — выбор, сделанный для ВЫДАННОГО классом
  # фита (см. moduledoc). Настоящим слотом не является: у выдачи слота нет вовсе.
  @granted_slot_key "granted"

  # Четвёртый псевдо-слот той же таблицы — надетое: доспех и щит как предметы
  # (задача 3.41, см. moduledoc). По строке на категорию.
  @worn_slot_key "worn"

  # Пятый псевдо-слот той же таблицы — оружие ВТОРОЙ РУКИ (задача 3.132,
  # см. moduledoc). ⚠️ Своей строкой, не дописанной рукой к `@weapon_slot_key`
  # — так главная рука кодируется тем же байтом, что и до этой задачи.
  @off_weapon_slot_key "offweapon"

  # Границы числа оружия при ЧТЕНИИ кода. Не игровое правило: кап +20 применяет
  # ядро, и правленая руками ссылка с «+99» обязана открыться, как открываются
  # остальные числа вещей. Это защита от кода, просящего сложить что-то
  # огромное, — и та же граница, что принимает форма конструктора.
  @weapon_bonus_limit 255

  @type dropped ::
          {:unknown_class
           | :unknown_feat
           | :unknown_skill
           | :unknown_spell
           | :unknown_slot
           | :unknown_weapon
           | :unknown_worn
           | :unknown_choice, String.t()}

  @doc "Schema version this module writes."
  @spec current_version() :: pos_integer()
  def current_version, do: @current_version

  @doc "Encodes a build into the string that goes in the `b` query parameter."
  @spec encode(Build.t()) :: String.t()
  def encode(%Build{} = build) do
    "#{@current_version}." <> Base.url_encode64(:zlib.zip(payload_v2(build)), padding: false)
  end

  @doc """
  Decodes a code back into the ruleset it was built with, and the build.

  `dropped` lists ids the data no longer knows — the build still opens, minus
  those entries, and the caller is expected to say so.
  """
  @spec decode(term()) ::
          {:ok, %{ruleset: map(), build: Build.t(), dropped: [dropped()]}} | {:error, atom()}
  def decode(code) when not is_binary(code), do: {:error, :malformed}
  def decode(code) when byte_size(code) > @max_code_bytes, do: {:error, :too_long}
  def decode("1." <> body), do: with({:ok, payload} <- inflate(body), do: parse(1, payload))
  def decode("2." <> body), do: with({:ok, payload} <- inflate(body), do: parse(2, payload))
  def decode(_code), do: {:error, :unknown_version}

  # ------------------------------------------------------------------ encode --

  defp payload_v2(%Build{} = build) do
    gear_abilities = Enum.sort(non_zero(build.gear.abilities))
    gear_ac = Enum.sort(non_zero(build.gear.ac))
    spell_entries = spell_entries(build.spells)
    spells = spell_entries |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> Enum.sort()
    spell_ix = index(spells)

    IO.iodata_to_binary([
      common_payload(build),
      <<length(gear_abilities)::8>>,
      for({ability, bonus} <- gear_abilities, do: [str(ability), <<byte(bonus)::8>>]),
      <<length(gear_ac)::8>>,
      for({type, bonus} <- gear_ac, do: [str(type), <<byte(bonus)::8>>]),
      <<byte(build.gear.saves)::8>>,
      <<length(spells)::16>>,
      Enum.map(spells, &str/1),
      <<length(spell_entries)::16>>,
      for {level, {:circle, circle, index}, spell} <- spell_entries do
        <<byte(level)::8, byte(circle)::8, byte(index)::8, Map.fetch!(spell_ix, spell)::16>>
      end
    ])
  end

  defp non_zero(map), do: for({key, value} <- map, value != 0, into: %{}, do: {key, value})

  defp spell_entries(spells) do
    for {level, at_level} <- Enum.sort(spells),
        {slot, spell} <- Enum.sort(at_level),
        match?({:circle, _, _}, slot),
        do: {level, slot, spell}
  end

  defp common_payload(%Build{} = build) do
    abilities = Enum.sort(build.base_abilities)
    ability_ids = Enum.map(abilities, &elem(&1, 0))

    classes = build.levels |> Enum.uniq() |> Enum.sort()

    feat_entries =
      feat_entries(build.feats) ++
        gear_feat_entries(build.gear) ++
        weapon_entries(build.gear) ++
        off_weapon_entries(build.gear) ++
        worn_entries(build.gear) ++
        granted_choice_entries(build)

    skill_entries = skill_entries(build.skills) ++ gear_skill_entries(build.gear)

    # ⚠️ `nil` — строка оружия: у неё вся запись в ключе слота, а фита нет вовсе,
    # поэтому в таблицу имён она не попадает и индекс у неё нулевой.
    feats =
      for {_level, _slot, pick} <- feat_entries, not is_nil(pick), uniq: true, do: pick

    feats = Enum.sort_by(feats, &feat_key/1)
    skills = skill_entries |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

    class_ix = index(classes)
    feat_ix = index(feats)
    skill_ix = index(skills)

    IO.iodata_to_binary([
      <<@current_version::8>>,
      str(build.ruleset_version || Data.default_version()),
      str(build.race),
      str(build.alignment),
      <<length(abilities)::8>>,
      for({ability, score} <- abilities, do: [str(ability), <<byte(score)::8>>]),
      <<length(classes)::8>>,
      Enum.map(classes, &str(class_key(&1, build.class_choices))),
      runs(build.levels, class_ix),
      <<map_size(build.ability_increases)::8>>,
      for {level, ability} <- Enum.sort(build.ability_increases) do
        <<byte(level)::8, byte(Enum.find_index(ability_ids, &(&1 == ability)) || 255)::8>>
      end,
      <<length(feats)::16>>,
      Enum.map(feats, &str(feat_key(&1))),
      <<length(feat_entries)::16>>,
      for {level, slot, feat} <- feat_entries do
        [<<byte(level)::8>>, str(slot_key(slot)), <<feat_index(feat_ix, feat)::16>>]
      end,
      <<length(skills)::8>>,
      Enum.map(skills, &str/1),
      <<length(skill_entries)::16>>,
      for {level, skill, ranks} <- skill_entries do
        <<byte(level)::8, Map.fetch!(skill_ix, skill)::8, byte(ranks)::8>>
      end
    ])
  end

  defp feat_entries(feats) do
    for {level, slots} <- Enum.sort(feats),
        {slot, pick} <- Enum.sort_by(slots, &Ids.slot_key(elem(&1, 0))),
        do: {level, slot, pick}
  end

  # Фиты с вещи — строки той же таблицы, уровень `0`, псевдо-слот `"gear"`
  # (см. moduledoc). `gear.feats` уже отсортирован (`Gear.toggle_feat/3`), но
  # сортировка повторена здесь: код обязан быть одинаковым у одинакового билда,
  # а этот список мог прийти и из декодера, и из чужого кода.
  #
  # ⚠️ Запись — целиком, вместе с выбором (задача 3.97): в таблицу имён она
  # уходит через тот же `feat_key/1`, что и слотовый пик, то есть
  # `"skill_focus|discipline"`. Голый id пишется голым, поэтому уже расшаренная
  # ссылка кодируется байт в байт как раньше, а совпавшая пара делит одну
  # строку таблицы со слотовым пиком (`uniq: true` в `common_payload/1`).
  defp gear_feat_entries(%Gear{feats: feats}) do
    for entry <- Enum.sort(feats), do: {0, :gear, entry}
  end

  # Оружие в руках — одна строка той же таблицы, уровень `0`, псевдо-слот
  # `"weapon|<id>|<атака>"` (см. moduledoc). Ни одной строки у билда без оружия:
  # нулевое число пишется, а вот отсутствие оружия — нет, иначе «выбрал и снял»
  # и «не выбирал» получили бы разные коды при одинаковом билде.
  #
  # ⚠️ Одно число с задачи 3.52, два до неё. Читатель по-прежнему принимает оба
  # (`weapon_numbers/1`), а пишем мы одно — то есть ссылка короче, а старая
  # открывается тем же билдом.
  defp weapon_entries(%Gear{weapon: nil}), do: []

  defp weapon_entries(%Gear{} = gear) do
    [{0, {:weapon, gear.weapon, gear.weapon_attack}, nil}]
  end

  # Оружие ВТОРОЙ РУКИ — тем же приёмом, восьмой раз (задача 3.132,
  # см. moduledoc). Своя строка, свой псевдо-слот `"offweapon|<id>|<атака>"`
  # — не дописанная рука к `@weapon_slot_key`, чтобы главная рука
  # кодировалась тем же байтом, что и до этой задачи. Ни одной строки у
  # билда без второй руки — та же причина, что у главной: «выбрал и снял» и
  # «не выбирал» обязаны быть одним и тем же кодом.
  defp off_weapon_entries(%Gear{off_hand_weapon: nil}), do: []

  defp off_weapon_entries(%Gear{} = gear) do
    [{0, {:off_weapon, gear.off_hand_weapon, gear.off_hand_weapon_attack}, nil}]
  end

  # Надетое — по строке на категорию, уровень `0`, псевдо-слот
  # `"worn|<категория>|<предмет>"` (задача 3.41, см. moduledoc). Отсортировано по
  # категории: билд не хранит порядок кликов, а код обязан быть одинаковым
  # у одинакового билда. Ни одной строки у билда, где ничего не надето, —
  # ровно поэтому уже расшаренная ссылка кодируется байт в байт как раньше.
  defp worn_entries(%Gear{worn: worn}) do
    for {category, item} <- Enum.sort(worn), do: {0, {:worn, category, item}, nil}
  end

  # Выбор для выданного фита — строки той же таблицы, псевдо-слот `"granted"`,
  # уровень настоящий (см. moduledoc). Пик записывается парой, поэтому в таблицу
  # имён попадает `"weapon_of_choice|scimitar"` тем же механизмом, что у пика
  # в слоте. Порядок — уровень, затем фит, ровно как у `Build.
  # granted_choice_picks/2`: у одинакового билда обязан быть одинаковый код.
  #
  # ⚠️ Уровнем НЕ обрезается, хотя читатель `granted_choice_picks/2` умеет: та
  # же линия, что у `feat_entries/1`, который тоже пишет всё, что лежит в билде.
  # Строка выше лестницы бывает только в правленом руками коде, и «сохранить как
  # есть» там честнее, чем молча подчистить, — иначе `decode(encode(b)) == b`
  # держалось бы не всегда, а почти всегда.
  defp granted_choice_entries(%Build{granted_choices: by_level}) do
    for {level, at_level} <- Enum.sort_by(by_level, &elem(&1, 0)),
        {feat, choice} <- Enum.sort(at_level),
        do: {level, :granted, {feat, choice}}
  end

  # У строки оружия фита нет вовсе, и индекс у неё нулевой: читается такая строка
  # по ключу слота, а до таблицы имён дело не доходит. ⚠️ `Map.fetch!` у остальных
  # оставлен намеренно — он ловит пик, не попавший в таблицу, и подменять его
  # на `Map.get(..., 0)` значило бы молча писать «первый фит таблицы».
  defp feat_index(_feat_ix, nil), do: 0
  defp feat_index(feat_ix, feat), do: Map.fetch!(feat_ix, feat)

  # ⚠️ Псевдо-слот пишется НЕ через `Ids.slot_key/1`: тот отвечает за настоящие
  # слоты, которые умеет и разобрать обратно, а `"gear"` разбирается здесь.
  # Совпадение строк (`Atom.to_string(:gear) == "gear"`) сделало бы делегирование
  # рабочим и потому опасным — правило держалось бы на совпадении имён.
  defp slot_key(:gear), do: @gear_slot_key
  defp slot_key(:granted), do: @granted_slot_key

  # ⚠️ Числа десятичным текстом, а не байтами: минус тогда проезжает целиком
  # (см. moduledoc). Разделитель тот же `|` — в id встречаются только
  # `[a-z0-9_]`, а знак минуса и цифры с ним не спутать.
  defp slot_key({:weapon, id, attack}) do
    Enum.join([@weapon_slot_key, Atom.to_string(id), attack], @choice_separator)
  end

  defp slot_key({:off_weapon, id, attack}) do
    Enum.join([@off_weapon_slot_key, Atom.to_string(id), attack], @choice_separator)
  end

  defp slot_key({:worn, category, item}) do
    Enum.join([@worn_slot_key, Atom.to_string(category), Atom.to_string(item)], @choice_separator)
  end

  defp slot_key(slot), do: Ids.slot_key(slot)

  # Как класс выглядит строкой в таблице классов — `"cleric"` без выбора,
  # `"cleric|air,war"` с ним. Значения внутри выбора отсортированы: билд не
  # хранит порядок кликов, а строка обязана быть детерминированной, иначе
  # один и тот же билд кодировался бы по-разному от захода к заходу.
  #
  # ⚠️ `class_ix` в `common_payload/1` строится ДО этой функции, по голым
  # атомам `classes` — она трогает только то, что пишется в саму таблицу
  # строк, а `runs/2` продолжает искать индекс по атому, не по декорированной
  # строке. Разойдись они — план по обратной совместимости (класс без выбора
  # кодируется как раньше) остался бы только на словах.
  defp class_key(id, class_choices) do
    case Map.get(class_choices, id, []) do
      [] ->
        Atom.to_string(id)

      values ->
        Atom.to_string(id) <>
          @choice_separator <> Enum.map_join(Enum.sort(values), ",", &Atom.to_string/1)
    end
  end

  # Как пик выглядит строкой в таблице фитов.
  #
  # ⚠️ `Build.put_feat/5` при `choice == nil` кладёт ГОЛЫЙ атом, а не пару
  # с `nil`, — ровно ради того, чтобы эта функция вернула ту же строку, что
  # и до появления выбора. На этом держится байтовая совместимость.
  #
  # Сортировка таблицы тоже переехала на этот ключ (`sort_by(&feat_key/1)`):
  # порядок атомов в Erlang и так лексикографический по имени, поэтому у билда
  # без выборов таблица не переставляется, а у билда с выборами пары встают
  # рядом со своим фитом, а не в хвост списка, как дал бы порядок термов.
  defp feat_key(pick) do
    case Build.feat_choice(pick) do
      nil -> Atom.to_string(Build.feat_id(pick))
      choice -> Atom.to_string(Build.feat_id(pick)) <> @choice_separator <> Atom.to_string(choice)
    end
  end

  defp skill_entries(skills) do
    for {level, bought} <- Enum.sort(skills),
        {skill, ranks} <- Enum.sort(bought),
        ranks > 0,
        do: {level, skill, ranks}
  end

  # Прибавки к навыкам с вещей — строки той же таблицы, уровень `0`
  # (см. moduledoc). Нулевые не пишутся: «вписал и стёр» и «не вписывал» — один
  # и тот же билд, а лишняя строка сделала бы у них разные коды.
  defp gear_skill_entries(%Gear{skills: skills}) do
    for {skill, bonus} <- Enum.sort(skills), bonus != 0, do: {0, skill, bonus}
  end

  # `[:fighter, :fighter, :dwarven_defender]` becomes one entry per uninterrupted
  # run. The order is never sorted away: past character level 20 it decides base
  # attack and saves outright.
  defp runs(levels, index) do
    chunks = Enum.chunk_by(levels, & &1)

    [
      <<length(chunks)::8>>,
      Enum.map(chunks, fn chunk ->
        <<Map.fetch!(index, hd(chunk))::8, byte(length(chunk))::8>>
      end)
    ]
  end

  defp index(ids), do: ids |> Enum.with_index() |> Map.new()

  defp str(nil), do: <<0::8>>
  defp str(value) when is_atom(value), do: value |> Atom.to_string() |> str()
  defp str(value) when is_binary(value), do: <<byte_size(value)::8, value::binary>>

  defp byte(n) when is_integer(n) and n >= 0 and n <= 255, do: n
  defp byte(n) when is_integer(n) and n > 255, do: 255
  defp byte(_), do: 0

  # ------------------------------------------------------------------ decode --

  defp inflate(body) do
    case Base.url_decode64(body, padding: false) do
      {:ok, zipped} -> unzip(zipped)
      :error -> {:error, :malformed}
    end
  end

  defp unzip(zipped) do
    {:ok, :zlib.unzip(zipped)}
  rescue
    _ -> {:error, :malformed}
  end

  # One parser for every schema version: the layout only ever grows at the end,
  # so an older code is the newer one with the tail missing. That is what keeps
  # a link somebody pasted into Discord a year ago opening.
  defp parse(schema, payload) do
    with <<^schema::8, rest::binary>> <- payload,
         {:ok, version, rest} <- take_str(rest),
         {:ok, ruleset} <- Data.ruleset(version),
         {:ok, race, rest} <- take_str(rest),
         {:ok, alignment, rest} <- take_str(rest),
         {:ok, abilities, rest} <- take_pairs(rest),
         {:ok, class_names, rest} <- take_table8(rest),
         {:ok, level_ixs, rest} <- take_runs(rest),
         {:ok, increases, rest} <- take_increases(rest),
         {:ok, feat_names, rest} <- take_table16(rest),
         {:ok, raw_feats, rest} <- take_feats(rest),
         {:ok, skill_names, rest} <- take_table8(rest),
         {:ok, raw_skills, rest} <- take_skills(rest),
         {:ok, tail, <<>>} <- take_tail(schema, rest) do
      {classes, class_choices, class_dropped} = resolve_classes(ruleset, class_names)
      {feats, feat_dropped} = resolve_feats(ruleset, feat_names)
      {skills, skill_dropped} = resolve(ruleset, :skills, skill_names)
      {spells, spell_dropped} = resolve(ruleset, :spells, tail.spell_names)
      ability_names = Enum.map(abilities, &elem(&1, 0))

      nested = nest_feats(ruleset, raw_feats, feats)
      {skill_map, gear_skills} = nest_skills(raw_skills, skills)

      build =
        Build.new(
          ruleset_version: version,
          race: Ids.get(ruleset, :races, race),
          alignment: Ids.get(ruleset, :alignments, alignment),
          base_abilities: to_abilities(ruleset, abilities),
          levels: for(ix <- level_ixs, id = Map.get(classes, ix), do: id),
          ability_increases: to_increases(ruleset, increases, ability_names),
          feats: nested.feats,
          skills: skill_map,
          spells: nest_spells(tail.spells, spells),
          gear: to_gear(ruleset, tail, nested, gear_skills),
          class_choices: class_choices,
          granted_choices: nested.granted
        )

      {:ok,
       %{
         ruleset: ruleset,
         build: build,
         dropped:
           class_dropped ++ feat_dropped ++ skill_dropped ++ nested.dropped ++ spell_dropped
       }}
    else
      {:error, {:unknown_ruleset, _}} -> {:error, :unknown_ruleset}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :malformed}
    end
  end

  @empty_tail %{gear_abilities: [], gear_ac: [], gear_saves: 0, spell_names: [], spells: []}

  # v1 predates gear and spells, so it simply has no tail — and the build it
  # decodes to is the one it described when it was written.
  defp take_tail(1, rest), do: {:ok, @empty_tail, rest}

  defp take_tail(2, rest) do
    with {:ok, gear_abilities, rest} <- take_pairs(rest),
         {:ok, gear_ac, rest} <- take_pairs(rest),
         <<saves::8, rest::binary>> <- rest,
         {:ok, spell_names, rest} <- take_table16(rest),
         {:ok, spells, rest} <- take_spells(rest) do
      {:ok,
       %{
         gear_abilities: gear_abilities,
         gear_ac: gear_ac,
         gear_saves: saves,
         spell_names: spell_names,
         spells: spells
       }, rest}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :malformed}
    end
  end

  defp to_gear(ruleset, tail, nested, gear_skills) do
    weapon = nested.weapon
    off_weapon = nested.off_weapon

    Gear.new(
      abilities: whitelisted(ruleset, :abilities, tail.gear_abilities),
      ac: whitelisted(ruleset, :ac_types, tail.gear_ac),
      # Надетое (задача 3.41). Обе половины пары уже пропущены через белый
      # список (`worn_slot/2`), поэтому здесь только перекладывание.
      #
      # 🔴 Пусто у КАЖДОЙ ссылки, записанной до этой задачи, — и это ответ на
      # вопрос «как читается старая ссылка»: предмета в ней нет, значит базы нет
      # и потолка ловкости нет, а вписанное под типом число остаётся тем, чем
      # было, — бонусом. Число, которое старая ссылка давала, она даёт и сейчас.
      worn: nested.worn,
      saves: tail.gear_saves,
      # ⚠️ Оружие пропущено через белый список справочника (`nest_feats/3`), но НЕ
      # проверено на владение — это правило ядра (`Rules.GearWeapon`), и здесь оно
      # не повторяется: код декодируется как записан, а что с ним не так, говорит
      # `Rules.illegal_gear_weapon/2`. Ровно так же декодер поступает с фитом
      # с вещи и со всеми числами вещей.
      weapon: weapon.id,
      weapon_attack: weapon.attack,
      # Вторая рука (задача 3.132) — тем же путём и с тем же ограничением: код
      # декодируется как записан, а держать ли это оружие — снова спрашивает
      # `Rules.illegal_gear_weapon/2` (он уже обходит обе руки, см. `rules.ex`).
      off_hand_weapon: off_weapon.id,
      off_hand_weapon_attack: off_weapon.attack,
      # Уже отфильтрованы белым списком словаря навыков (`resolve/3`) и уже
      # отделены от рангов по уровню `0` (`nest_skills/2`). Потолок +50 — дело
      # ядра, как и у остальных чисел вещей: правленая руками ссылка с «+99»
      # открывается, а `Rules.Skills` говорит, во что она упёрлась.
      skills: gear_skills,
      # Уже отфильтрованы белым списком словаря фитов (`resolve_feats/2`);
      # ⚠️ но НЕ проверены на `disabled?` — это правило ядра
      # (`Rules.GearFeats`), и здесь оно повторено не будет: код декодируется
      # как записан, а что с ним не так, говорит `Rules.illegal_gear_feats/2`.
      # Ровно так же декодер поступает с числами вещей — потолки не его дело.
      feats: nested.gear
    )
  end

  # Gear numbers are clamped by the rules core, not here: a hand-edited link
  # asking for +99 CON opens, and the core reports the ceiling it hit.
  defp whitelisted(ruleset, kind, pairs) do
    for {name, value} <- pairs, id = Ids.get(ruleset, kind, name), into: %{}, do: {id, value}
  end

  defp nest_spells(raw, spells) do
    for {level, circle, index, ix} <- raw, id = Map.get(spells, ix), reduce: %{} do
      acc ->
        slot = {:circle, circle, index}
        Map.update(acc, level, %{slot => id}, &Map.put(&1, slot, id))
    end
  end

  defp to_abilities(ruleset, abilities) do
    for {name, score} <- abilities,
        id = Ids.get(ruleset, :abilities, name),
        into: %{},
        do: {id, score}
  end

  defp to_increases(ruleset, increases, ability_names) do
    for {level, ix} <- increases,
        name = Enum.at(ability_names, ix),
        id = Ids.get(ruleset, :abilities, name),
        into: %{},
        do: {level, id}
  end

  @no_weapon %{id: nil, attack: 0}
  @nothing_nested %{
    feats: %{},
    gear: [],
    weapon: @no_weapon,
    off_weapon: @no_weapon,
    worn: %{},
    granted: %{},
    dropped: []
  }

  # Возвращает мапу: фиты по уровням и слотам, фиты с вещи, оружие ОБЕИХ рук,
  # надетое, выбор выдачи, выпавшее.
  #
  # ⚠️ Мапой, а не кортежем, с задачи 3.41: псевдо-слотов стало пять
  # (задача 3.132 добавила пятый), и кортеж читается позиционно — то есть
  # новый вид записи добавляется правкой каждой ветки `case`, а перепутанные
  # местами два поля одного типа компилятор не ловит.
  #
  # ⚠️ Все пять псевдо-слотов — `"gear"`, `"weapon|…"`, `"offweapon|…"`,
  # `"worn|…"` и `"granted"` — разбираются ЗДЕСЬ, до `Ids.fetch_slot/2`, и это
  # не оптимизация: попади они в белый список слотов, «gear» стал бы валидным
  # слотом и для клика из браузера (см. moduledoc).
  defp nest_feats(ruleset, raw, feats) do
    nested =
      Enum.reduce(raw, @nothing_nested, fn {level, slot_key, ix}, acc ->
        case {slot_or_gear(ruleset, slot_key), Map.get(feats, ix)} do
          {:gear, pick} when not is_nil(pick) ->
            Map.update!(acc, :gear, &[pick | &1])

          {{:weapon, parsed}, _pick} ->
            %{acc | weapon: parsed}

          {{:off_weapon, parsed}, _pick} ->
            %{acc | off_weapon: parsed}

          {{:worn, category, item}, _pick} ->
            Map.update!(acc, :worn, &Map.put(&1, category, item))

          {{:unknown, entry}, _pick} ->
            drop(acc, [entry])

          {:granted, pick} when not is_nil(pick) ->
            acc
            |> Map.update!(:granted, &put_granted(&1, level, pick))
            |> drop(granted_bare(pick))

          {{:ok, slot}, feat} when not is_nil(feat) ->
            Map.update!(acc, :feats, fn by_level ->
              Map.update(by_level, level, %{slot => feat}, &Map.put(&1, slot, feat))
            end)

          {:error, _} ->
            drop(acc, [{:unknown_slot, slot_key}])

          _ ->
            # The feat itself was already reported by `resolve/3`.
            acc
        end
      end)

    %{nested | gear: nested.gear |> Enum.uniq() |> Enum.sort()}
  end

  defp drop(nested, []), do: nested
  defp drop(nested, entries), do: Map.update!(nested, :dropped, &(&1 ++ entries))

  # ⚠️ Уровень `0` в строке выдачи не бывает у нашего кодера и не имеет смысла:
  # уровня `0` у персонажа нет, а `Build.put_granted_choice/4` требует `level >= 1`.
  # Правленая руками ссылка с нулём теряет строку ПОИМЁННО, а не роняет билд.
  defp put_granted(granted, level, pick) when level >= 1 do
    case Build.feat_choice(pick) do
      nil ->
        granted

      choice ->
        Map.update(
          granted,
          level,
          %{Build.feat_id(pick) => choice},
          &Map.put(&1, Build.feat_id(pick), choice)
        )
    end
  end

  defp put_granted(granted, _level, _pick), do: granted

  # Строка выдачи БЕЗ выбора не несёт ничего: сам факт выдачи читается из
  # справочника классов, а не из кода. Такую строку наш кодер не пишет вовсе,
  # поэтому встретить её можно только в правленой руками ссылке — и тогда она
  # называется вслух, а не исчезает молча.
  defp granted_bare(pick) do
    case Build.feat_choice(pick) do
      nil -> [{:unknown_choice, Atom.to_string(Build.feat_id(pick))}]
      _choice -> []
    end
  end

  defp slot_or_gear(_ruleset, @gear_slot_key), do: :gear
  defp slot_or_gear(_ruleset, @granted_slot_key), do: :granted

  defp slot_or_gear(ruleset, @weapon_slot_key <> @choice_separator <> rest),
    do: weapon_slot(ruleset, rest, :weapon)

  # Вторая рука (задача 3.132) — своя строка, СВОЙ тег `:off_weapon`, чтобы
  # `nest_feats/3` не спутал её с главной: обе бегут через один и тот же
  # разборщик чисел (`weapon_slot/3`), различается только то, куда положить
  # результат.
  defp slot_or_gear(ruleset, @off_weapon_slot_key <> @choice_separator <> rest),
    do: weapon_slot(ruleset, rest, :off_weapon)

  defp slot_or_gear(ruleset, @worn_slot_key <> @choice_separator <> rest),
    do: worn_slot(ruleset, rest)

  defp slot_or_gear(ruleset, slot_key), do: Ids.fetch_slot(ruleset, slot_key)

  # `"<id>|<атака>"`, и `"<id>|<атака>|<усиление>"` у ссылки старше задачи 3.52.
  # Оружие, которого справочник не знает, теряется ПОИМЁННО — не молча: ссылка
  # на оружие, снятое с вики, иначе открылась бы как «оружия и не было». Битые
  # числа читаются как ноль, а не роняют строку: id тут важнее чисел, и потерять
  # из-за одной цифры выбор игрока было бы дороже.
  #
  # ⚠️ `tag` — `:weapon` или `:off_weapon` (задача 3.132): какой руке достанется
  # разобранная пара, решает вызывающая сторона, а не имя оружия.
  defp weapon_slot(ruleset, rest, tag) do
    case String.split(rest, @choice_separator) do
      [name | numbers] ->
        case Ids.get(ruleset, :weapons, name) do
          nil ->
            {:unknown, {:unknown_weapon, name}}

          id ->
            {tag, %{id: id, attack: weapon_numbers(numbers)}}
        end

      _other ->
        {:unknown, {:unknown_weapon, rest}}
    end
  end

  # `"<категория>|<предмет>"` — надетое (задача 3.41). Обе половины проходят
  # белый список, и обе обязаны: категория ищется среди объявленных ruleset'ом,
  # предмет — среди предметов ЭТОЙ категории, а не любых. Иначе `"worn|shield|
  # full_plate"` из правленой руками ссылки положил бы латы в щит.
  #
  # ⚠️ Неизвестное теряется ПОИМЁННО, как и оружие, и по той же причине: ссылка
  # на доспех, которого в справочнике больше нет, иначе открылась бы как «доспеха
  # и не было» — с завышенным AC и без предела ловкости.
  defp worn_slot(ruleset, rest) do
    with [category, item] <- String.split(rest, @choice_separator),
         {:ok, category_id, item_id} <- Ids.fetch_worn(ruleset, category, item) do
      {:worn, category_id, item_id}
    else
      _no -> {:unknown, {:unknown_worn, @worn_slot_key <> @choice_separator <> rest}}
    end
  end

  # ⚠️ Клауза на ДВА числа оставлена намеренно (задача 3.52). Кодер пишет одно,
  # но позиционное второе несут все ссылки, выпущенные до правки, — и оно
  # СКЛАДЫВАЕТСЯ с первым, а не выбрасывается. Сторона капа у бывших двух чисел
  # общая всегда (слово Dan), значит сумма даёт то же AB, что давали два терма,
  # а выбрасывание тихо занизило бы такой билд. Стоит это ноль строк и остаётся
  # заодно защитой от правленой руками ссылки.
  defp weapon_numbers([attack, enhancement | _extra]),
    do: clamp_weapon_number(weapon_number(attack) + weapon_number(enhancement))

  defp weapon_numbers([attack]), do: weapon_number(attack)
  defp weapon_numbers([]), do: 0

  defp weapon_number(text) do
    case Integer.parse(text) do
      {number, _rest} -> clamp_weapon_number(number)
      :error -> 0
    end
  end

  # ⚠️ Сумма клипается ЕЩЁ РАЗ: два числа по потолку каждое дают вдвое больше
  # потолка, и без второго клипа сложение старой ссылки протаскивало бы в билд
  # число, которого одно поле принять не может.
  defp clamp_weapon_number(number),
    do: number |> max(-@weapon_bonus_limit) |> min(@weapon_bonus_limit)

  # Возвращает `{ранги по уровням, прибавки с вещей}`.
  #
  # ⚠️ Уровень `0` — это прибавка с вещей, а не ранги (см. moduledoc), и
  # разбирается он здесь, до всякой сборки уровней: попади он в общую ветку,
  # ранги легли бы на несуществующий уровень `0` — `Build.skill_ranks/3` их бы
  # не увидел, а бюджет очков посчитал бы потраченными. Правдоподобная чушь,
  # а не заметная поломка.
  #
  # Повторы складываются в обеих половинах — ровно как складывались ранги до
  # этой правки: две строки про один навык бывают только в правленом руками
  # коде, и сумма там честнее, чем «победила последняя».
  defp nest_skills(raw, skills) do
    Enum.reduce(raw, {%{}, %{}}, fn {level, ix, value}, {ranks, gear} ->
      case {level, Map.get(skills, ix)} do
        {_level, nil} -> {ranks, gear}
        {0, id} -> {ranks, Map.update(gear, id, value, &(&1 + value))}
        {level, id} -> {add_ranks(ranks, level, id, value), gear}
      end
    end)
  end

  defp add_ranks(acc, level, id, ranks) do
    Map.update(acc, level, %{id => ranks}, &Map.update(&1, id, ranks, fn n -> n + ranks end))
  end

  defp resolve(ruleset, kind, names) do
    {resolved, dropped} =
      names
      |> Enum.with_index()
      |> Enum.reduce({%{}, []}, fn {name, ix}, {ok, bad} ->
        case Ids.fetch(ruleset, kind, name) do
          {:ok, id} -> {Map.put(ok, ix, id), bad}
          :error -> {ok, [{unknown(kind), name} | bad]}
        end
      end)

    {resolved, Enum.reverse(dropped)}
  end

  # Таблица фитов — единственная, где строка может быть НЕ голым id: у фита
  # с выбором это `"spell_focus|evocation"`.
  #
  # ⚠️ Не разобравшийся выбор роняет пик ЦЕЛИКОМ, а не срезается до фита.
  # Оставить `Spell focus` без школы значило бы записать в билд пик, которого
  # в коде не было: снаружи он неотличим от честно выбранного, а школа при этом
  # потеряна молча. Выпавшее видно игроку — `warn_dropped/2` печатает список.
  defp resolve_feats(ruleset, names) do
    {resolved, dropped} =
      names
      |> Enum.with_index()
      |> Enum.reduce({%{}, []}, fn {name, ix}, {ok, bad} ->
        case resolve_feat(ruleset, name) do
          {:ok, pick} -> {Map.put(ok, ix, pick), bad}
          {:error, reason} -> {ok, [{reason, name} | bad]}
        end
      end)

    {resolved, Enum.reverse(dropped)}
  end

  defp resolve_feat(ruleset, name) do
    case String.split(name, @choice_separator, parts: 2) do
      [id] ->
        with {:ok, feat} <- Ids.fetch(ruleset, :feats, id), do: {:ok, feat}

      [id, choice] ->
        with {:ok, feat} <- Ids.fetch(ruleset, :feats, id) do
          case Ids.fetch_choice(ruleset, feat, choice) do
            {:ok, value} -> {:ok, {feat, value}}
            :error -> {:error, :unknown_choice}
          end
        end
    end
    |> case do
      :error -> {:error, :unknown_feat}
      other -> other
    end
  end

  # Таблица классов — вторая (после фитов) таблица, где строка может нести
  # больше, чем голый id: `"cleric|air,war"`, если у клирика записан выбор.
  #
  # ⚠️ Класс и его выбор резолвятся НЕЗАВИСИМО, и это правило другое, чем
  # у фита с выбором. Там нечитаемое значение роняет пик целиком (см.
  # `resolve_feat/2`) — здесь так нельзя: индекс, под которым лежит класс,
  # питает `runs/2`, который по нему восстанавливает уровни ПЕРСОНАЖА, и
  # уронить класс из-за одного протухшего домена значило бы стереть игроку
  # сколько угодно уровней ради потери двух слов. Поэтому класс резолвится
  # сам по себе, а нечитаемые значения выбора теряются поодиночке.
  defp resolve_classes(ruleset, names) do
    {classes, choices, dropped} =
      names
      |> Enum.with_index()
      |> Enum.reduce({%{}, %{}, []}, fn {name, ix}, {classes, choices, dropped} ->
        {id_str, choice_str} =
          case String.split(name, @choice_separator, parts: 2) do
            [id_str] -> {id_str, nil}
            [id_str, choice_str] -> {id_str, choice_str}
          end

        case Ids.fetch(ruleset, :classes, id_str) do
          {:ok, id} ->
            {values, bad} = resolve_class_choice(ruleset, id_str, id, choice_str)
            choices = if values == [], do: choices, else: Map.put(choices, id, values)
            {Map.put(classes, ix, id), choices, bad ++ dropped}

          :error ->
            {classes, choices, [{:unknown_class, id_str} | dropped]}
        end
      end)

    {classes, choices, Enum.reverse(dropped)}
  end

  defp resolve_class_choice(_ruleset, _id_str, _class_id, nil), do: {[], []}

  defp resolve_class_choice(ruleset, id_str, class_id, choice_str) do
    {values, bad} =
      choice_str
      |> String.split(",")
      |> Enum.reduce({[], []}, fn value_str, {ok, bad} ->
        case Ids.fetch_class_choice(ruleset, class_id, value_str) do
          {:ok, value} ->
            {[value | ok], bad}

          :error ->
            {ok, [{:unknown_choice, id_str <> @choice_separator <> value_str} | bad]}
        end
      end)

    {Enum.reverse(values), Enum.reverse(bad)}
  end

  defp unknown(:skills), do: :unknown_skill
  defp unknown(:feats), do: :unknown_feat
  defp unknown(:spells), do: :unknown_spell

  # ------------------------------------------------------------ binary bites --

  defp take_str(<<size::8, value::binary-size(size), rest::binary>>), do: {:ok, value, rest}
  defp take_str(_), do: {:error, :malformed}

  defp take_pairs(<<count::8, rest::binary>>) do
    take_times(count, rest, fn bin ->
      with {:ok, name, bin} <- take_str(bin),
           <<score::8, rest::binary>> <- bin do
        {:ok, {name, score}, rest}
      else
        _ -> {:error, :malformed}
      end
    end)
  end

  defp take_pairs(_), do: {:error, :malformed}

  defp take_table8(<<count::8, rest::binary>>), do: take_times(count, rest, &take_str/1)
  defp take_table8(_), do: {:error, :malformed}

  defp take_table16(<<count::16, rest::binary>>), do: take_times(count, rest, &take_str/1)
  defp take_table16(_), do: {:error, :malformed}

  defp take_runs(<<count::8, rest::binary>>) do
    case take_times(count, rest, fn
           <<ix::8, n::8, rest::binary>> -> {:ok, List.duplicate(ix, n), rest}
           _ -> {:error, :malformed}
         end) do
      {:ok, runs, rest} -> {:ok, List.flatten(runs), rest}
      other -> other
    end
  end

  defp take_runs(_), do: {:error, :malformed}

  defp take_increases(<<count::8, rest::binary>>) do
    take_times(count, rest, fn
      <<level::8, ix::8, rest::binary>> -> {:ok, {level, ix}, rest}
      _ -> {:error, :malformed}
    end)
  end

  defp take_increases(_), do: {:error, :malformed}

  defp take_feats(<<count::16, rest::binary>>) do
    take_times(count, rest, fn bin ->
      with <<level::8, bin::binary>> <- bin,
           {:ok, slot, bin} <- take_str(bin),
           <<ix::16, rest::binary>> <- bin do
        {:ok, {level, slot, ix}, rest}
      else
        _ -> {:error, :malformed}
      end
    end)
  end

  defp take_feats(_), do: {:error, :malformed}

  defp take_skills(<<count::16, rest::binary>>) do
    take_times(count, rest, fn
      <<level::8, ix::8, ranks::8, rest::binary>> -> {:ok, {level, ix, ranks}, rest}
      _ -> {:error, :malformed}
    end)
  end

  defp take_skills(_), do: {:error, :malformed}

  defp take_spells(<<count::16, rest::binary>>) do
    take_times(count, rest, fn
      <<level::8, circle::8, index::8, ix::16, rest::binary>> ->
        {:ok, {level, circle, index, ix}, rest}

      _ ->
        {:error, :malformed}
    end)
  end

  defp take_spells(_), do: {:error, :malformed}

  # `fun` — всегда один из `take_*` этого же модуля, и каждый заканчивается
  # веткой `_ -> {:error, :malformed}`, то есть возвращает ровно две формы.
  # Третьей ветки здесь раньше стояла ещё одна, `_ -> {:error, :malformed}` —
  # мёртвая (dialyzer), и хуже того: она заглушила бы будущий парсер, который
  # вернул бы что-то новое, вместо того чтобы уронить его на месте. Декодер
  # обязан не пускать битую ссылку дальше, а не молча превращать её в пустой билд.
  defp take_times(count, bin, fun), do: take_times(count, bin, [], fun)

  defp take_times(0, rest, acc, _fun), do: {:ok, Enum.reverse(acc), rest}

  defp take_times(count, bin, acc, fun) do
    case fun.(bin) do
      {:ok, value, rest} -> take_times(count - 1, rest, [value | acc], fun)
      {:error, reason} -> {:error, reason}
    end
  end
end
