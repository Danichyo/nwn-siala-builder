defmodule BuildCalculator.Rules.Gear do
  @moduledoc """
  Equipment as numbers the player types, not as an armoury.

  Full items with stats come later (CLAUDE.md §1). Until then the build carries
  the totals a player reads off their character sheet:

    * `abilities` — `%{con: 12}`, capped per ability by `ruleset.gear.ability_bonus_cap`.
      A number here may be **negative**: penalties from equipment are real, and
      the same cascade runs downwards
    * `ac` — `%{armor: 8, deflection: 5}`, one number per AC type. **Different
      types stack** and are simply summed; what happens **inside** one type,
      where a number here meets a bonus the build earns itself, is the shard's
      own rule and lives in `BuildCalculator.Rules.ArmorClass` (task 3.39 — the
      larger of the two, except a type declared cumulative). ⚠ **Not capped
      here**, for the same reason `saves` below is not: the one type with a
      ceiling is clipped over that whole sum, once. ⚠ Since task 3.41 a number
      here is the **bonus** of the thing worn, not the whole of it: the item's
      base is `worn` below
    * `worn` — `%{armor: :full_plate, shield: :large}`, the thing worn in each
      category the ruleset declares (task 3.41). The one entry of this struct
      that is a **choice out of a dictionary** rather than a number, and two
      numbers come off it — the item's base armour class, which always stacks,
      and the ceiling it puts on the dexterity bonus **to armour class**. Both
      are `BuildCalculator.Rules.Worn`'s to read; no category and no item is
      named here
    * `saves` — one bonus to all three saves at once, which is what the shard's
      items call `Saving Throw Bonus (Universal)`. **Not capped here**: the
      `saving_throw_bonus` ceiling covers everything that adds to all three
      saves at once, and equipment is no longer the only such source — the
      Spellcraft ranks count towards the same +20. Two separate clamps would let
      a build carry +40, so `Rules.compute/2` clamps the sum
    * `saves_specific` — `%{fort: 12, will: 3}`, a bonus to **one** save
      (задача 3.187, слово Dan 11.09.2026: «мы показываем только +universal …
      а на экипировке еще есть спасброски отдельные, например +fortitude,
      +reflex, +will. Предлагаю в экипировку ввести помимо universal еще
      раздельные спас броски, но общее правило то же — +20 — это кап»). Items
      really carry both lines at once — Хнюпиус wears +16 universal and +12 to
      Fortitude on top (`test/fixtures/game_logs_plus/hnyupius.log`) — so this
      is a second field beside `saves`, never a replacement for it: one number
      could not say which of the three saves it meant.

      ⚠ **Not capped here either, and under the SAME ceiling as `saves`, not
      a second one of its own.** "Общее правило то же" reads «в кап +20 у сейва
      входит всё вещевое вместе»: `Rules.compute/2` offers universal and
      specific to one clip per save, the way it already does for gear and
      Spellcraft. Two clamps of +20 are exactly the bug that ceiling exists to
      prevent (CLAUDE.md §9).

      🔴 **И это ИЗМЕРЕНО печатью движка, а не прочитано.** У Хнюпиуса надето
      16 universal и 12 к Стойкости — 28 при потолке 20, — и игра печатает
      Стойкость **59**, ровно столько же, сколько даёт модель с одним клипом;
      конкурирующее чтение («у каждого поля свой +20») дало бы 67. Сверка —
      `BuildCalculatorWeb.Builder.GearImportEngineTest`, лог
      `test/fixtures/game_logs_plus/hnyupius.log`. Мерить это на сервере
      незачем: ответ уже напечатала сама игра.

      A number here may be negative for the same reason `saves` may, and the
      keys are the three the core already speaks (`:fort`, `:ref`, `:will`);
      an absent key and a zero are one answer, as everywhere else in this
      struct.
    * `skills` — `%{discipline: 50, hide: 50}`, one number per skill (task 3.20,
      Dan: «чтобы можно было указать „дисциплина +50“ … чтобы в „Итого“ увидеть
      финальную картинку по скиллам»). **Not capped here either**, and for the
      very same reason: the `skill_bonus` ceiling of +50 already covers the
      shard's racial bonus to a named skill, so a second clamp of its own would
      let a Human carry +62 to Discipline while every source says +50. One clip
      over the pool, in `BuildCalculator.Rules.Skills`
    * `feats` — feats an item **grants**: the one entry here that is not a number
      the player adds up but a fact the rules read. It costs no feat slot and
      counts as owned, so a class's requirements and every bonus reader see it
      like any other feat — see `BuildCalculator.Rules.GearFeats` for the whole
      rule, including the one requirement a borrowed feat does **not** satisfy
      (another feat's). Kept in this struct because it belongs to the same layer
      ("what is worn") and therefore travels in the shared link with everything
      else.

      ⚠ **A list, and repeats in it mean something** (task 3.204): a feat the
      data marks repeatable with no value to name may stand here more than once,
      and the number of entries is the number of takes — `Epic toughness` twice
      is forty hit points. Which feats those are is read from `repeatable.choice`
      and never listed here (`Rules.GearFeats.stackable?/2`); for every other
      feat a repeat counts once, exactly as before.

      ⚠ An entry is a bare id **or** a `{feat_id, choice}` pair, exactly like a
      slot's contents (task 3.97, решение Dan 25.08.2026: «Подобный фит не может
      существовать без привязки к конкретному выбору»). Without the value there
      is nothing for `Skill focus`'s +3 to land on and no weapon for
      `Weapon focus` to name. Both forms are legal and a bare one is not a
      defect: every link shared before that task carries bare ids, and the build
      says what is missing rather than refusing to open
    * `weapon` — the weapon in the character's hands, by id, and
      `weapon_attack` — the number the item carries (task 3.5 part B, Dan:
      «в вещах можно будет выбрать оружие, допустим „скимитар“ с усилением
      атаки +5. И будем показывать в деталях об АБ значение с конкретным
      оружием»). **One** weapon and one number, never a matrix of "AB per
      weapon kind". ⚠ One number since task 3.52 and two before it: an item
      also carries an *enhancement* bonus, and the shard's items really do
      (Dan named both while listing the +20 cap's contents). It is not an input
      here because the only thing that told the two apart was damage, and damage
      is not computed anywhere — see `ruleset.gear.weapon_bonus_kinds`, which is
      where the kinds are declared. Whether this weapon may be held at all, and
      what its number is worth, is `BuildCalculator.Rules.GearWeapon`
    * `off_hand_weapon` / `off_hand_weapon_attack` — the same pair for the
      **second hand** (task 3.132, Dan: «многие билды берут 2 оружия вместо щита
      или двуручки … Можем ввести вторую руку? с возможностью выбрать оружие
      вместо щита и его attack bonus»). Two fields rather than a list of hands,
      for the same reason there is one weapon and not a matrix: every consumer
      prints a row per hand, and a hand is not a repetition of the same thing —
      it has its own refusals (a two-handed weapon may not go there), its own
      attack bonus and its own number of attacks.

      ⚠ A weapon here and a shield in `worn` are mutually exclusive, and the two
      refusals are **worded differently** on purpose: «занята двуручным оружием»
      and «занята вторым оружием» are different facts about the same hand, and
      one wearing the other's sentence would send the player to change the wrong
      thing (`Rules.Worn`, `Rules.GearWeapon`)
    * `mini_sets` — **сколько кусков каждого набора надето**, списком чисел
      (задача 3.184, просьба Dan 11.09.2026: «я как раз хотел мини сеты
      добавить, потому что они очень распространены в реальной игре»). Мини-сет
      — комплект предметов шарда, и надетые куски одного комплекта усиливают
      оружейные и расовые бонусы: `B += floor(B · Nmini / 10)`.

      🔴 **Список ЧИСЕЛ, а не имён, и это не упрощение, а свойство правила.**
      В сумму `Nmini` входит только мультимножество счётчиков — какие именно
      наборы их дали, арифметика не спрашивает вовсе, — поэтому каталога из 80
      групп здесь нет и заводить его незачем (`Rules.MiniSets`). Имена
      понадобятся импорту игрового лога, а не расчёту.

      🔴 **Одинокий кусок не считается ВООБЩЕ.** `[2]` это `Nmini = 2`, а `[1]`
      — ноль; `[2, 1]` — те же два, потому что одиночка в счёт не идёт. Ровно
      та ошибка, которую легко сделать, прочитав «сколько сетовых вещей надето»
    * `named_items` — **сколько КРАФТОВЫХ (именных) и уникальных вещей
      надето**, одним числом (задача 3.186). Второй вход той же таблицы
      процентов к HP, что и куски выше: `Ctotal = Cgear + Nmini`, и проценты
      от него нелинейны — от +15 % за одну вещь до +105 % за десять, **а на
      одиннадцатой обрыв в ноль** (`Rules.GearHitPoints`).

      🔴 **«Сетовое» на Сиале значит три разные вещи, и к HP ведут две.**
      Мини-сет — это поле выше; **крафт и уникальные вещи** — это поле;
      а **артефактные сеты** (Перчатки Мокси и родня) не дают к HP ничего
      (Dan 11.09.2026: «Перчатки Мокси это сет, а не мини сет и он не даёт
      прибавку к здоровью, а вот крафт — даёт»). Поэтому подпись обязана
      называть крафт, а не «сетовые вещи»: одно слово на три системы — это
      как раз тот ввод, который игрок заполнит неверно.

      ⚠ **Число, а не список предметов**, и ровно по той же причине, что
      у кусков: скрипт шарда спрашивает у слота только «именная ли она»
      (`MatchingFigure == ID персонажа` либо ненулевой `UnqQualityLevel`),
      а какая именно — не спрашивает вовсе. Слотов десять, и клипает ввод
      этим числом **ядро**, читая его из данных, — здесь число не трогается,
      как и всякий другой ввод игрока.

      ⚠ **Куски и именные вещи считаются НЕЗАВИСИМО, и один предмет может
      войти в оба счётчика** («The code tests the two metadata families
      independently»). Поэтому это два поля и одна сумма, а не одно поле
      с попыткой не задвоить.
    * `resistances` — **поглощение стихийного урона с вещей**, по числу на
      стихию (`%{fire: 15, cold: 15}`, задача 3.210). Стихии называет ruleset
      (`resistance_energy_types`, семь), и ни одна из них не названа здесь.

      🔴 **Одно число на стихию, и это правило, а не форма ввода.** Между
      предметами поглощение одной и той же стихии **не складывается** — «only
      the highest resistance granted by a spell or (equipped) item is used»
      (`fandom:Damage resistance`, revid 68743), — поэтому игрок вписывает
      наибольшее, а свод импорта выбирает его сам
      (`Rules.GearImport`, правило из данных). Складывать здесь было бы вторым
      прочтением того же правила.

      ⚠ **А вот с прибавкой от ФИТА оно складывается**, и это названо трижды
      независимо (обе страницы фитов и `fandom:Damage resistance`); с эффектом
      расы и топоров — **конкурирует**, и побеждает наибольшее (слово Dan
      13.09.2026, замер `AV1` 18.09.2026). Всю арифметику держит
      `Rules.Resistances`, здесь лежит только ввод.

      ⚠ Пустая мапа — «поглощения с вещей нет», и это то состояние, в котором
      открывается ВСЯКАЯ уже расшаренная ссылка: ни одного числа у неё
      не записано, и ни одно число такого билда не меняется — под тестом.
      **Не капается здесь**, ровно как `saves` и `skills`: своего потолка
      поглощению не называет ни один источник, и выдумывать его нельзя.

  ## The point is the cascade, not the input box

  `+12 CON` is not "+12 CON". It is +6 to the modifier, which is +6 hit points
  on **every** level — +246 on a level 41 build. That is the arithmetic players
  get wrong by hand and the reason the calculator exists, so the order of
  application is fixed and not negotiable (CLAUDE.md §6):

      point buy + race  ->  the +1 every fourth level  ->  gear

  and everything derived is computed from the **final** score. `ac_naked` is the
  one number computed with no gear at all — including a dexterity modifier taken
  before the gear bonus — because otherwise "голым" stops meaning naked.
  """

  @typedoc """
  What the player says one item lends: a feat, or a feat and the value it names.

  The same duality a feat slot holds, and deliberately the same shape — one
  reader answers both (`BuildCalculator.Rules.Build.feat_id/1` and
  `feat_choice/1`), so a second way of writing "a feat with a parameter" never
  comes into existence.
  """
  @type feat_entry :: atom() | {atom(), atom()}

  @type t :: %__MODULE__{
          abilities: %{atom() => integer()},
          ac: %{atom() => integer()},
          worn: %{atom() => atom()},
          saves: integer(),
          saves_specific: %{atom() => integer()},
          skills: %{atom() => integer()},
          feats: [feat_entry()],
          weapon: atom() | nil,
          weapon_attack: integer(),
          off_hand_weapon: atom() | nil,
          off_hand_weapon_attack: integer(),
          mini_sets: [pos_integer()],
          named_items: non_neg_integer(),
          resistances: %{atom() => integer()}
        }

  defstruct abilities: %{},
            ac: %{},
            # Что надето, по категориям ruleset'а (задача 3.41). Ключи и значения
            # — из данных (`ruleset.gear.worn`), поэтому ни одного имени доспеха
            # или щита ни здесь, ни где-либо в `rules/` нет. Пустая мапа — «ничего
            # не надето», и это ровно то, во что открывается уже расшаренная
            # ссылка: предмета в ней не записано, значит и базы у неё нет.
            worn: %{},
            saves: 0,
            # Прибавка к ОДНОМУ сейву (задача 3.187). ⚠️ Пустая мапа — «таких
            # прибавок нет», и это то состояние, в котором открывается ВСЯКАЯ
            # уже расшаренная ссылка: раздельных сейвов в ней не записано, и
            # ни одно число такого билда не меняется — под тестом.
            saves_specific: %{},
            skills: %{},
            feats: [],
            # Оружие в руках и его число. ⚠️ ОДНО с задачи 3.52 и два до неё:
            # усиление у предмета в игре есть (кейс J1, Dan назвал attack bonus
            # и enchantment bonus отдельно), но отличалось оно от бонуса атаки
            # только уроном, а урон модель не считает вовсе — то есть игрок
            # вводил два числа и разницы не видел нигде (решение Dan
            # 19.08.2026). Какие именно поля бывают, объявлено в данных
            # (`ruleset.gear.weapon_bonus_kinds`), чтобы веб-слой не перечислял их
            # заново, — и объявленный вид без поля здесь роняет сборку.
            weapon: nil,
            weapon_attack: 0,
            # Вторая рука (задача 3.132). Пусто — «одна рука», ровно то
            # состояние, в котором открывается всякая уже расшаренная ссылка:
            # второго оружия в ней не записано, и число главной руки от этих
            # полей не зависит вовсе.
            off_hand_weapon: nil,
            off_hand_weapon_attack: 0,
            # Сколько кусков каждого надетого мини-сета на персонаже (задача
            # 3.184). ⚠️ Пустой список — «мини-сетов нет», и это то состояние,
            # в котором открывается ВСЯКАЯ уже расшаренная ссылка: ни одного
            # числа у неё не записано, значит и усиливать нечего. Ни одно число
            # билда без этого поля не меняется — под тестом.
            mini_sets: [],
            # Сколько крафтовых (именных) и уникальных вещей надето (задача
            # 3.186) — второй вход таблицы процентов к HP. ⚠️ Артефактные сеты
            # сюда НЕ входят: они считаются другим счётчиком движка и к HP
            # не ведут вовсе. ⚠️ Ноль — «ни одной», и это то
            # состояние, в котором открывается ВСЯКАЯ уже расшаренная ссылка.
            # Потолок (десять слотов) стоит в данных и применяется в
            # `Rules.GearHitPoints`, а не здесь: ввод игрока хранится как
            # введён, ровно как сумма кусков выше.
            named_items: 0,
            # Поглощение стихийного урона с вещей, по стихии (задача 3.210).
            # ⚠️ Пустая мапа — «такого поглощения нет», и это то состояние,
            # в котором открывается ВСЯКАЯ уже расшаренная ссылка: ни одного
            # числа у неё не записано, и ни одно число такого билда
            # не меняется — под тестом. Одно число на стихию потому, что
            # между предметами поглощение НЕ складывается (см. @typedoc),
            # а потолка у него не называет ни один источник.
            resistances: %{}

  @doc "Builds a gear struct from a keyword list or map, filling in the defaults."
  @spec new(Enumerable.t()) :: t()
  def new(fields \\ []), do: struct!(__MODULE__, Map.new(fields))

  @doc """
  Whether the player has entered anything at all.

  A declared feat counts — it is something the player entered, and it moves real
  numbers (`Rules.GearFeats`), so a set answering "nothing here" while carrying
  one would understate the whole block it belongs to.

  So does a chosen weapon, and for the same reason twice over: it is the player's
  own statement, and it is what makes `Weapon focus` count at all
  (`Rules.GearWeapon`). ⚠ The weapon counts even with both its numbers at zero —
  a plain scimitar in hand is still a scimitar, and it is what decides whether
  three feats reach the attack roll.

  And so does a worn item, on the same argument a third time: the clothing row
  is worth `0` armour class and still answers a question — it is what says the
  character wears no armour, which is what a Monk's bonuses hang on.

  ⚠ And so does a declared mini-set piece, for the first of those reasons: it is
  the player's own statement and it multiplies real numbers. A **singleton**
  counts here even though it adds nothing at all (`Rules.MiniSets` requires two
  of a kind) — this question is «ввёл ли игрок хоть что-то», not «двигает ли
  это число», and the two differ for the same reason a scimitar with both
  numbers at zero still counts.

  ⚠ And so does a named item (task 3.186), for the first reason once more — and
  here the price of answering "nothing" would be the largest of the lot: one
  named item is +15 % hit points and ten are +105 %, so a set calling itself
  empty while carrying them would make "HP голым" and "HP в экипировке" print
  the same number on a build where they differ by half.
  """
  @spec any?(t()) :: boolean()
  def any?(%__MODULE__{} = gear) do
    gear.saves != 0 or Enum.any?(gear.saves_specific, &(elem(&1, 1) != 0)) or
      Enum.any?(gear.abilities, &(elem(&1, 1) != 0)) or
      Enum.any?(gear.ac, &(elem(&1, 1) != 0)) or Enum.any?(gear.skills, &(elem(&1, 1) != 0)) or
      gear.feats != [] or not is_nil(gear.weapon) or not is_nil(gear.off_hand_weapon) or
      gear.worn != %{} or gear.mini_sets != [] or gear.named_items > 0 or
      Enum.any?(gear.resistances, &(elem(&1, 1) != 0))
  end

  @doc """
  What the player typed for one element's damage resistance — `0` for an element
  they said nothing about.

  **Raw, and one number by construction:** resistance from two worn items does
  not add up, the larger counts, so what is stored here is already that larger
  number (`Rules.GearImport` picks it at import, by a rule out of the data).
  What this number then meets — the feat's own bonus, which **adds**, and the
  shard's racial/weapon effect, which **competes** — is `Rules.Resistances`.

  ⚠ `0` and «нет записи» are one answer here, exactly as in `skill_bonus/2`:
  a number typed and cleared back to zero absorbs nothing and there is nothing
  to say about it either.
  """
  @spec resistance(t(), atom()) :: integer()
  def resistance(%__MODULE__{resistances: resistances}, energy_type),
    do: Map.get(resistances, energy_type, 0)

  @doc """
  What equipment adds to **one** save — the universal line plus that save's own.

  One number, because that is what every reader of this term needs: the ceiling
  is one clip per save over everything it covers (`Rules.compute/2`), and the
  breakdown prints one row per save. Adding the two here rather than at each
  caller is what keeps «вещи» from meaning two different things in the panel
  and in the clip — the split between `saves` and `saves_specific` is an input
  shape, not a second rule.

  ⚠ **Raw, before the ceiling**, exactly like `skill_bonus/2` above and for the
  same reason: the +20 covers Spellcraft and the build's own `Sacred defense`
  too, and clipping here as well would be the pair of half-clips that once let
  a build carry +40 (CLAUDE.md §9).
  """
  @spec save_bonus(t(), atom()) :: integer()
  def save_bonus(%__MODULE__{} = gear, save) when is_atom(save),
    do: gear.saves + Map.get(gear.saves_specific, save, 0)

  @doc """
  What is worn in one category — `nil` for a category the player said nothing
  about.

  The id as the player recorded it, **not** resolved against the ruleset: whether
  this ruleset still has such an item is `BuildCalculator.Rules.Worn`'s question,
  and answering it here would make an unknown id indistinguishable from an empty
  slot at the one place that could still name it.
  """
  @spec worn(t(), atom()) :: atom() | nil
  def worn(%__MODULE__{worn: worn}, category), do: Map.get(worn, category)

  @doc """
  Records what is worn in one category, or takes it off with `nil`.

  Plain data in, plain data out, exactly like `toggle_feat/2`: nothing here asks
  whether the item exists — the caller resolves the id first
  (`BuildCalculator.Ids`), and an empty category is stored as an
  **absent** key rather than as `nil`, so «снял» and «не выбирал» are one state
  and one URL code.
  """
  @spec put_worn(t(), atom(), atom() | nil) :: t()
  def put_worn(%__MODULE__{} = gear, category, nil) when is_atom(category),
    do: %__MODULE__{gear | worn: Map.delete(gear.worn, category)}

  def put_worn(%__MODULE__{} = gear, category, item)
      when is_atom(category) and is_atom(item),
      do: %__MODULE__{gear | worn: Map.put(gear.worn, category, item)}

  @doc """
  What the player typed for one skill — `0` for a skill they said nothing about.

  **Raw, before the ceiling.** The `+50` on skill bonuses is not this term's own:
  the shard's racial bonus to a named skill counts towards the very same ceiling
  («Этот бонус входит в кап навыка +50»), so clipping here and clipping there
  would be the two half-clips that once let a build carry +40 on its saves
  (CLAUDE.md §9). `BuildCalculator.Rules.Skills` offers both to one clip.

  ⚠ `0` and «нет записи» are one answer here on purpose, unlike in the terms of
  a skill's value: a number the player typed and then cleared to zero adds
  nothing, and there is nothing to say about it either.
  """
  @spec skill_bonus(t(), atom()) :: integer()
  def skill_bonus(%__MODULE__{skills: skills}, skill), do: Map.get(skills, skill, 0)

  # Which field of this struct holds which of the weapon's numbers. The kinds
  # themselves are declared in the data (`gear.weapon_bonus_kinds`); this is the
  # one place that says where each lands, so a kind the data grows without a field
  # here fails the **build** rather than counting as zero — the loader asks this
  # function and raises on `nil`.
  # ⚠ Keyed by the **hand** as well since task 3.132. Not one field per kind with
  # the hand looked up somewhere else: which hand a number belongs to is exactly
  # what a caller must not be able to get wrong, and the two hands are two
  # inputs the player fills in separately.
  @weapon_bonus_fields %{
    {:main, :attack} => :weapon_attack,
    {:off, :attack} => :off_hand_weapon_attack
  }

  # Which hands a build has, in the order everything prints them. A list rather
  # than two names scattered through the core: the pair travels together into
  # `Rules.GearWeapon`, `Rules.DualWield` and the breakdown, and a third hand
  # would be a data question rather than a rewrite.
  @hands [:main, :off]

  @doc """
  The hands a build holds weapons in, main first.

  Exposed so nothing outside this module writes `:main` and `:off` down as a
  pair of literals — the same reason `ruleset.gear.weapon_bonus_kinds` is data
  rather than a list in `Rules.GearWeapon`.
  """
  @spec hands() :: [atom()]
  def hands, do: @hands

  @doc """
  Which field of this struct carries the weapon bonus of `kind` for `hand` —
  `nil` when the struct has no field for it.

  Read by `BuildCalculator.Data.Loader`, which refuses to compile a ruleset
  declaring a kind that would land nowhere **in either hand**.
  `Rules.GearWeapon` is what reads the numbers themselves.
  """
  @spec weapon_bonus_field(atom(), atom()) :: atom() | nil
  def weapon_bonus_field(kind, hand \\ :main) when is_atom(kind) and is_atom(hand),
    do: Map.get(@weapon_bonus_fields, {hand, kind})

  @doc """
  Which weapon this hand holds — `nil` when it holds none.

  The id as the player recorded it, **not** resolved against the ruleset and not
  checked for legality: both are `Rules.GearWeapon`'s questions, and answering
  them here would make an unknown id indistinguishable from an empty hand at the
  one place that could still name it — exactly the division `worn/2` above keeps.
  """
  @spec weapon(t(), atom()) :: atom() | nil
  def weapon(%__MODULE__{weapon: weapon}, :main), do: weapon
  def weapon(%__MODULE__{off_hand_weapon: weapon}, :off), do: weapon

  @doc """
  What the player typed for one of the weapon's numbers — `0` for a kind this
  struct has no field for, which only a ruleset the loader refused could ask
  about.
  """
  @spec weapon_bonus(t(), atom(), atom()) :: integer()
  def weapon_bonus(%__MODULE__{} = gear, kind, hand \\ :main) do
    case weapon_bonus_field(kind, hand) do
      nil -> 0
      field -> Map.fetch!(gear, field)
    end
  end

  @doc """
  Adds or removes one declaration — a click on a chip.

  `choice` is the value the item's feat names; `nil` declares the bare feat,
  which is what every declaration was before task 3.97 and still is for a feat
  that takes no parameter at all.

  ## The entry is the unit, not the feat id

  Two items lending `Skill focus` for two different skills are two declarations
  and two bonuses — решение Dan, 25.08.2026: «разные значения — разные записи».
  So uniqueness is by the **pair**: toggling with a value only ever removes that
  pair, and toggling a bare id only ever removes the bare declaration. Neither
  can shadow the other, which is what makes a chip and its value one reversible
  click each.

  ⚠ **Two declarations of the same bare id are two takes since task 3.204**,
  and that is a reversal of what stood here — «an item lends a feat, not a
  number of copies of it, and «×N с вещей» stays out until the armoury gives
  the count a place to live». The armoury never came into it: the count has a
  place to live in this very list, which is a list. Слово Dan 13.09.2026: «на
  фитах с вещи нам необходимо добавить возможность настакивать те фиты, которые
  можно взять несколько раз… Там не только epic toughness». Which feats may
  repeat that way is the **data's** answer and nothing this module knows
  (`Rules.GearFeats.stackable?/2` → `repeatable.choice == nil`); this struct
  simply keeps what it is given, duplicates and all.

  ⚠ For a feat that names a **value** the pair is unique **unless the data lets
  the same value be taken again** (`Rules.FeatChoices.repeats_same_value?/2` —
  today `Epic energy resistance` alone): such a pair stands in the list once per
  take, exactly like a bare stackable feat (задачи 3.210 и 3.224). This paragraph
  used to say that two items lending `Epic energy resistance (fire)` «remain
  indistinguishable from one (3.29's remaining half)» — true until 3.210, stale
  after it, and flagged as such by two agents in a row. `toggle_feat/3` is what
  the interface clicks for a value that does **not** repeat; `add_feat/3` and
  `remove_feat/3` are for everything that counts — bare entries and repeating
  pairs alike (whether an entry repeats is `Rules.GearFeats.repeats?/2`).

  Kept sorted, for the same reason `Rules.Build`'s class choices are: the build
  does not record the order things were clicked in, and the URL code has to be
  the same for the same build every time. Plain `Enum.sort/1`, so the order is
  Erlang's term order — every bare id before every pair — and
  `BuildCalculator.Encoding` sorts the very same list the very same
  way. A build that names no values therefore encodes byte for byte as it did
  before values existed, and so does one that declares nothing twice.

  Plain data in, plain data out, exactly like `Build.put_feat/5`: whether this
  feat may be declared at all is `Rules.validate_gear_feat/2`'s question, and
  whether the value is one it accepts is
  `Rules.FeatChoices.gear_reasons/4`'s — both are asked *before* this, never
  guessed at by this.
  """
  @spec toggle_feat(t(), atom(), atom() | nil) :: t()
  def toggle_feat(%__MODULE__{} = gear, feat_id, choice \\ nil)
      when is_atom(feat_id) and is_atom(choice) do
    entry = entry(feat_id, choice)

    feats =
      if entry in gear.feats,
        do: List.delete(gear.feats, entry),
        else: Enum.sort([entry | gear.feats])

    %__MODULE__{gear | feats: feats}
  end

  @doc """
  Adds **one more** declaration of the same feat — a take, not a toggle.

  The other half of the pair `toggle_feat/3` cannot be: a chip answers "declared
  or not", a counter answers "how many". Task 3.204, слово Dan 13.09.2026 («на
  фитах с вещи нам необходимо добавить возможность настакивать те фиты, которые
  можно взять несколько раз»).

  ⚠ **Plain data in, plain data out**, exactly like `toggle_feat/3`: whether
  this feat may repeat at all (`Rules.GearFeats.stackable?/2`) and whether the
  stated ceiling has room for another one (`Rules.GearFeats.add_reasons/3`) are
  asked *before* this, never guessed at by this. A caller that adds a second
  `Toughness` gets a build with two of them written down and one counted — the
  same shape of answer a hand-edited link gets, and `Rules.GearFeats` is what
  names it.
  """
  @spec add_feat(t(), atom(), atom() | nil) :: t()
  def add_feat(%__MODULE__{} = gear, feat_id, choice \\ nil)
      when is_atom(feat_id) and is_atom(choice) do
    %__MODULE__{gear | feats: Enum.sort([entry(feat_id, choice) | gear.feats])}
  end

  @doc """
  Removes **one** declaration — the counter's other button.

  One, never all: `List.delete/2` drops the first match and leaves the rest, so
  a player who declared `Epic toughness` three times and clicks «−» once keeps
  two. Removing them all would make the minus button an undo of the whole
  column.
  """
  @spec remove_feat(t(), atom(), atom() | nil) :: t()
  def remove_feat(%__MODULE__{} = gear, feat_id, choice \\ nil)
      when is_atom(feat_id) and is_atom(choice) do
    %__MODULE__{gear | feats: List.delete(gear.feats, entry(feat_id, choice))}
  end

  @doc """
  How many times this exact entry is declared — what the player typed, not what
  counts.

  Raw and ruleset-free on purpose: this is the number beside the «×» in the
  interface, and the number that actually reaches a bonus is
  `Rules.GearFeats.takes/3`, which additionally drops declarations this ruleset
  refuses and answers `1` for a feat that may not repeat at all. Two questions,
  two readers — the same split `Build.feat_takes/3` and `feat_takes_owned/4`
  keep on the slot side.
  """
  @spec feat_takes(t(), atom(), atom() | nil) :: non_neg_integer()
  def feat_takes(%__MODULE__{} = gear, feat_id, choice \\ nil)
      when is_atom(feat_id) and is_atom(choice) do
    Enum.count(gear.feats, &(&1 == entry(feat_id, choice)))
  end

  # A `nil` choice stores the bare id rather than a pair with a `nil` in it —
  # the same rule `Build.put_feat/5` follows, and the thing byte compatibility
  # hangs on: the URL writes this entry through one key function, and a bare id
  # has to come out of it as the string it always was.
  defp entry(feat_id, nil), do: feat_id
  defp entry(feat_id, choice), do: {feat_id, choice}

  @doc """
  Ability bonuses after the per-ability ceiling.

  Returns `{%{ability => bonus}, capped?}`; `capped?` is true when a typed number
  was clipped, which the interface has to show — a silently reduced number reads
  as a bug in the calculator.

  ## The ceiling has one side only

  The source is a *bonus* ceiling — "This limit is a bonus of +12" (fandom
  "Ability cap", revid 68173) — so a penalty is clipped by nothing here. No page
  states a floor, and mirroring +12 into a −12 would be inventing a game number
  (CLAUDE.md §3, rule 1).

  What that same page *does* say is that penalties lower the effective ceiling —
  with strength down 2, items may add no more than +10 net.

  ⚠ That interaction used to be confessed as
  `{:not_modelled, :ability_cap_penalty_interaction}`, and the confession was
  **removed 22.08.2026 by Dan's decision** (task 3.77) — not by waving it away
  but because it is **inexpressible in this input's shape**. The page describes
  a penalty and a bonus on the *same* ability from *different* sources; here an
  ability carries exactly one number, and that number means the **net**. A
  player with a +12 ring and a −2 curse types +10 and gets the right answer.
  The other two sources of a penalty are both out by the source's own words:
  true racial modifiers never enter the ceiling, and a spell is a buff (Dan,
  10.08.2026). Dan: «в реальности у одетых персонажей надето по +12 статов
  нужных в билде, что они и вобьют у нас в вещах».
  """
  @spec ability_bonuses(t(), map()) :: {%{atom() => integer()}, boolean()}
  def ability_bonuses(%__MODULE__{abilities: abilities}, ruleset) do
    cap = ruleset.gear.ability_bonus_cap

    Enum.reduce(abilities, {%{}, false}, fn {ability, bonus}, {acc, capped?} ->
      {value, clipped?} = clamp(bonus, cap)
      {Map.put(acc, ability, value), capped? or clipped?}
    end)
  end

  @doc """
  What the player typed for armour class, per type the ruleset names — raw, in
  the ruleset's own order, and `0` for a type they said nothing about.

  ## Raw, because the ceiling is not this number's own

  ⚠ Here stood `armor_class/2`, which summed the typed numbers and clipped the
  one type that has a ceiling (`dodge`, +20). Task 3.39 moved both jobs to
  `BuildCalculator.Rules.ArmorClass`, and not for tidiness: since Dan's rule
  of 16.08.2026 the typed number does not simply add to what the build earns by
  itself — it **competes** with it, and a cumulative type is clipped over the
  **sum** of the two. Clipping here first and again there is the pair of
  half-clips that once let the saves carry +40 while every source said +20
  (CLAUDE.md §9).

  There is still **no general ceiling on armour class** — different types stack,
  and no source names one. That is a decision (Dan, 03.08.2026) rather than a
  hole, which is why nothing prints `{:missing_data, {:stat_cap, :ac}}`.
  """
  @spec ac_typed(t(), map()) :: [{atom(), integer()}]
  def ac_typed(%__MODULE__{ac: ac}, ruleset),
    do: for(type <- ruleset.gear.ac_types, do: {type, Map.get(ac, type, 0)})

  # Only `value > cap` is clipped: the ceiling is stated for a bonus, and a
  # penalty has no stated floor. Whatever is typed below zero passes through
  # whole — see the note above `ability_bonuses/2`.
  defp clamp(value, nil), do: {value, false}
  defp clamp(value, cap) when value > cap, do: {cap, true}
  defp clamp(value, _cap), do: {value, false}
end
