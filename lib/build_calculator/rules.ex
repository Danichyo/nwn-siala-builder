defmodule BuildCalculator.Rules do
  @moduledoc """
  The pure rules core: the one place that decides what a build is worth.

  Two entry points, exactly as CLAUDE.md §5 specifies:

      Rules.compute(build, ruleset)                  :: DerivedStats.t()
      Rules.validate_level_up(build, choice, ruleset) :: :ok | {:error, [reason]}

  `ruleset` is data from `BuildCalculator.Data`; the core never loads it itself.
  Everything in `lib/build_calculator/rules/` is a pure function — no Ecto, no
  Phoenix, no IO, no clock, no randomness. Same input, same output, always, which
  is what makes the rules testable by tables of cases and reusable later by an
  importer, a Discord bot or an API.

  ## Deltas

  There is no incremental algorithm and there must not be one. The change a level
  makes is the difference between two full computations:

      before = Rules.compute(Build.truncate(build, level - 1), ruleset)
      after  = Rules.compute(Build.truncate(build, level), ruleset)

  Two implementations would eventually disagree, and the player would be shown
  one number and given another.

  ## Gear

  Equipment is not a separate pass bolted on afterwards: the ability bonuses the
  player types are applied to the scores **before** anything is derived, because
  that is the whole point of the feature. `+12 CON` is +6 to the modifier, which
  is +6 hit points on every level (CLAUDE.md §6). `ac_naked`,
  `abilities_naked` and `saves_naked` are computed with no gear at all so the
  interface can show `было → стало`.

  ⚠ И у `abilities_naked` есть второй читатель, не про показ: **требование фита
  по характеристике сравнивается именно с ним** (16.08.2026, кейс S1). Числа при
  этом считаются от **одетого** значения, все до одного: вещь даёт свой эффект и
  не даёт права взять фит — это разные вопросы, и вещь отвечает на них
  по-разному (`GAME_CHECKS.md` H7).

  ⚠ У сейвов таких чисел **два, и это не дубль**. `saves_naked` — «сколько было
  бы без предметов» (кейс S2: «вещи на спасы также не откроют фит»);
  `saves_for_prereqs` — то, с чем сравнивается требование, и правил в нём на
  одно больше: оттуда вычтено ещё и то, что источник исключил поимённо
  (кейс S3, `Luck of heroes`). Одно поле на оба вопроса означало бы, что «голое»
  число зависит от того, кто спрашивает.

  ⚠ И читается это поле **не у того персонажа, что на экране**: требование по
  сейву сравнивается со снимком на входе в уровень — билдом, обрезанным до
  `level - 1`, **плюс прибавка характеристики, записанная на самом этом уровне**
  (кейсы S6 и S7b). Поэтому у воина 12 с телосложением 10 в панели стоит Fort 8,
  а `Resist energy` он взять не может — восьмёрка приехала вместе с этим самым
  уровнем; а его сосед с телосложением 11, поднявший его на 12-м, фит получает,
  хотя в панели у обоих одно и то же. Ни одно **число** от этого не меняется,
  меняется только право.

  ## Not implemented

  ⚠ **This paragraph was wrong in three ways at once by 22.08.2026, and each
  half aged for a different reason** — worth keeping as written history rather
  than quietly replacing. It said: «What a Cleric domain *does* … is not
  modelled, and neither is metamagic or the bonus spell slots a high ability
  grants: none of those tables exist in the data».

    * **bonus spell slots are computed** since 21.08.2026 (задача 3.70): the
      table came off `fandom:Ability modifier#Spellcasting` and is checked
      against the source's own formula on every load. A Sorcerer 41 with CHA 30
      gains 17 slots a day by it;
    * **a Cleric's domains** stopped being a confession 22.08.2026 (задача 3.79)
      — not because a table arrived but because the answer never wanted one:
      domain spells are handed out automatically, so there is nothing to choose;
    * **metamagic** went the same day (задача 3.80) for the same reason, and
      Dan stated the criterion behind both: the constructor cares about spells
      exactly where the player *must choose at level-up*.

  What holds today: spell slots per day and spells known are computed
  (`BuildCalculator.Rules.Spells`), and a Cleric's *choice* of two domains is
  modelled in `BuildCalculator.Rules.ClassChoices` — which values were picked,
  not what they do.
  """

  alias BuildCalculator.Rules.{
    Abilities,
    AbilityBonuses,
    ArmorClass,
    Attack,
    AttackBonuses,
    Bonuses,
    Build,
    Caps,
    ClassChoices,
    ClassGroups,
    DerivedStats,
    Epic,
    FeatBonuses,
    FeatChoices,
    FeatSlots,
    GapReceivers,
    Gear,
    GearFeats,
    DualWield,
    GearWeapon,
    LevelUp,
    Prereqs,
    Progression,
    RacialBonus,
    SaveBonuses,
    Skills,
    Spells,
    SpellResistance,
    Vocabulary,
    WeaponTypeBonus,
    Wield,
    Worn
  }

  @doc """
  One example of every gap this core can produce — data-wide and build-specific.

  The honesty mechanism only works if the interface shows the gap, and a gap
  nobody worded renders through `inspect/1`. `ruleset.gaps` can be walked; the
  gaps that appear only on a particular build cannot, so they are registered.
  See `BuildCalculator.Rules.Vocabulary`.
  """
  @spec gap_forms() :: [tuple()]
  defdelegate gap_forms(), to: Vocabulary, as: :gaps

  @doc "One example of every reason this core refuses a level, a class or a feat with."
  @spec reason_forms() :: [tuple()]
  defdelegate reason_forms(), to: Vocabulary, as: :reasons

  @doc """
  Derived statistics for the build, gear included.

  Fields that cannot be computed honestly come back `nil`, with the reason in
  `stats.gaps` — see `BuildCalculator.Rules.DerivedStats`.
  """
  @spec compute(Build.t(), map()) :: DerivedStats.t()
  def compute(%Build{} = build, ruleset) do
    character_level = Build.character_level(build)

    # Тот же самый персонаж, у которого блок «Вещи» пуст: по нему считается всё
    # «голое» — и AC, и сейвы. ⚠ Пустой `%Gear{}`, а не `%Gear{gear | saves: 0}`
    # и не вычитание задним числом: «голым» здесь значит ровно то же, что
    # у `ac_naked` и `abilities_naked`, — без предметов вообще. Третье значение
    # одного слова в одном модуле было бы ловушкой, а не экономией.
    naked_build = %Build{build | gear: %Gear{}}

    naked = Abilities.scores(build, ruleset)
    naked_modifiers = Abilities.modifiers(naked)

    {abilities, gear_abilities, abilities_capped?} = Abilities.with_gear(naked, build, ruleset)
    modifiers = Abilities.modifiers(abilities)

    base = Progression.base(build, ruleset)
    epic_attack = Epic.attack_bonus(ruleset, character_level)
    epic_save = Epic.save_bonus(ruleset, character_level)

    {hp, hp_breakdown, hp_gaps} =
      case Progression.hit_points(build, ruleset, modifiers.con) do
        {:ok, hp, breakdown} -> {hp, breakdown, []}
        {:error, reason} -> {nil, nil, [reason]}
      end

    base_attack = base.bab + epic_attack

    # ⚠ Оба набора модификаторов, а не один: у Тайного лучника Сиалы условие
    # «мудрость выше ловкости» само говорит, по каким считаться (задача 3.72,
    # `Rules.AttackModifiers`), и решать это здесь значило бы прятать игровое
    # решение в вызове.
    {attacks, attacks_terms} =
      Progression.attacks_per_round(build, ruleset, base.bab, naked_modifiers, modifiers)

    # Оружие в руках и его число (задача 3.5, часть B; чисел было два до 3.52) —
    # **третий** механизм атаки, и первый предметный источник ПОД капом: до него
    # внутри +20 стоял только расовый бонус Сиалы, максимум +9. Свести его
    # с `gear` в один источник нельзя — у того сторона противоположная
    # (`Rules.Caps`).
    #
    # ⚠ Считается ЗДЕСЬ, до формулы атаки, а не рядом со своими числами ниже:
    # с 14.08.2026 оружие решает не только слагаемое, но и саму характеристику
    # (`Zen archery` — атака от мудрости, но только с дальнобойным).
    weapon = GearWeapon.held(build, ruleset, :main)
    weapon_attack_terms = GearWeapon.attack_terms(build, ruleset, :main)
    weapon_attack = Enum.reduce(weapon_attack_terms, 0, &(&1.bonus + &2))

    # 🔴 И ВТОРАЯ РУКА (задача 3.132, запрос Dan 28.08.2026): «наличие оружия
    # во второй руке влияет на АБ в главной … обновить АБ основной руки и левой
    # руки тоже». Стиль считается ОДИН раз на билд (`Rules.DualWield`) и отдаёт
    # штраф каждой руке свой; числа рук после этого считаются одинаковым
    # конвейером, просто с разным оружием в нём.
    #
    # ⚠ Штраф применяется ПОСЛЕ капа и мимо него: потолки этого проекта
    # односторонние (`Caps.clamp/3` режет сверху), и отрицательное число через
    # них не проходит по построению.
    dual_wield = DualWield.of(build, ruleset)
    dual_wield_penalty = DualWield.penalty(dual_wield)

    # Which ability the attack comes off is a rule, not a constant: Weapon
    # Finesse switches it to dexterity when dexterity is higher, and Zen archery
    # to wisdom when a ranged weapon is in hand.
    #
    # ⚠ **Owned, not picked** (fixed 14.08.2026). This read `feats_taken/2`, so a
    # `Weapon Finesse` off an item changed nothing — STR 10 / DEX 18 fighter 10
    # showed AB 10 where the game gives 14 — while every other reader of the same
    # feat counted it. Which ability the roll comes off is an **effect**, and an
    # item's feat has its effect (Dan, 09.08.2026); the half the H7 measurement
    # narrowed on 14.08.2026 is a *feat's prerequisite*, and nothing here asks one.
    #
    # ⚠ **The weapon goes in, and it is the one that counts** (14.08.2026, the
    # same day, second fix): `Zen archery` had no rule at all until then, so the
    # feat moved nothing whatsoever. Its condition is about the weapon in hand,
    # which this model has had since task 3.5 part B — so it is checked, not
    # assumed. `held/2` rather than the declaration: a weapon the character may
    # not wield adds no attack bonus either.
    #
    # ⚠ **И ХВАТ тоже идёт внутрь** (17.08.2026, замер S10): «двуручным
    # не финессится» — правило про пару «оружие и владелец», а не про оружие,
    # поэтому считает его здесь `Rules.Wield`, а `Rules.Attack` получает готовый
    # ответ и остаётся без единого имени расы и предмета. У Карлика (Gnome)
    # рапира двуручная, у человека — нет, и `Weapon Finesse` работает ровно
    # у второго.
    {attack_ability, formula_gaps} =
      Attack.ability(
        ruleset,
        modifiers,
        Build.feats_owned(build, ruleset, character_level),
        weapon,
        not is_nil(weapon) and Wield.both_hands?(build, weapon, ruleset)
      )

    # The ceilings cap *bonuses*, never the base — so what is offered to the cap
    # is the part gear added, not the modifier the character earned.
    #
    # ⚠ **One clip, and it does not cover every source.** Which sources the +20
    # covers is read from the data and never decided here, at the two levels the
    # data states it at: gear and the shard's racial bonus are named as
    # **mechanisms** (`stat_caps.attack_bonus.applies_to_sources`), and of those
    # two only the racial one is under the ceiling — it says «Этот бонус входит
    # в кап атаки +20» on its own page (task 3.12) — while every bonus with a
    # **record** of its own carries its side in that record (`bonuses[].cap`).
    # `Epic prowess` sits on top of the ceiling since 09.08.2026 (Dan,
    # `source: user`). Task 1.12b had put it under the ceiling *by analogy*
    # with the saves; the analogy was wrong, and so was its replacement,
    # "the side belongs to the source kind" — see `Rules.Caps`.
    #
    # ⚠ **`Small stature` stood beside `Epic prowess` here until task 3.143**
    # (30.08.2026): a race's size modifier to the attack roll, also outside the
    # ceiling by the same word from Dan. It never earned that side — the
    # record's own quote was truncated before the condition that makes it
    # conditional (`fandom:Small stature` — "when dealing with larger
    # creatures"), and the fix moved it to `not_modelled`, where `cap` is
    # forbidden outright. `Epic prowess` is the only record here with a side
    # to speak of today.
    #
    # ⚠ **`gear` left the ceiling on 10.08.2026** (task 3.22, `GAME_CHECKS.md` J1).
    # Dan listed what the +20 covers — a weapon's attack and enchantment bonus,
    # buffs, the bard song, the shard's racial bonus — and an ability modifier is
    # in none of it, whatever raised it: «Бонус силы в кап 20 не входит». Which
    # means the saves were right all along, since there an ability's contribution
    # rides inside the modifier and is never clipped.
    #
    # ⚠ And on the same day the **first item bonus genuinely under it** arrived,
    # as that same note predicted it would: the weapon in hand carries the number
    # Dan named first in that list (task 3.5 part B, `gear_weapon` below —
    # two numbers until task 3.52 dropped the enhancement bonus as an input,
    # the two having differed only in damage, which is computed nowhere).
    # So the ceiling now covers two sources, and it is reachable for the first
    # time — until this task the most anything under it could offer was +9.
    #
    # What is **not** negotiable is that everything the ceiling does cover is
    # clipped **together, once**: clipping by source is how the saves came to
    # carry +40 while each source said +20 (CLAUDE.md §9), and task 3.12 already
    # had to merge two of these into one clip.
    #
    # ⚠ **И четвёртый механизм с 16.08.2026 (задача 3.35) — бонус за ТИП оружия
    # в руках**, и он же первый, при котором кап атаки становится достижимым:
    # расовый бонус и он дают по +9, то есть 18 из 20, и любая третья
    # внутрикапная прибавка кап кусает. ⚠ Не путать с `gear_weapon` рядом: там
    # числа, вписанные игроком с предмета, и замер Q5 вынес их НАРУЖУ капа, а эта
    # прибавка называет свой кап дословно («Бонус входит в лимита атаки +20»).
    # Два механизма оружия по разные стороны одного потолка — ровно поэтому они
    # два, а не один.
    gear_attack = modifier(modifiers, attack_ability) - modifier(naked_modifiers, attack_ability)
    race_attack = RacialBonus.attack_bonus(build, ruleset)

    # ⚠ ОБЕ руки сразу, и это цитата, а не удобство: «Используя два разных
    # оружия персонаж получает два разных бонуса» (`Система оружия`, revid
    # 20527). Число одно на персонажа и достаётся ОБЕИМ рукам — бонус висит
    # на персонаже, а не на предмете («накладываются на персонажа как эффект
    # в момент взятия оружия в руку»).
    weapon_type_attack = WeaponTypeBonus.attack_bonus(build, ruleset)
    own_attack_terms = AttackBonuses.terms(build, ruleset, [weapon] -- [nil])
    own_attack = Enum.reduce(own_attack_terms, 0, &(&1.bonus + &2))

    # `[{under_cap?, value}]`: у механизмов сторону спрашиваем у вида источника,
    # у собственных термов она уже посчитана по записи (`Rules.Caps`).
    attack_mechanisms =
      for {source, value} <- [
            {:gear, gear_attack},
            {:racial_bonus, race_attack},
            {:weapon_bonus, weapon_type_attack}
          ],
          do: {Caps.covers_source?(ruleset, :attack_bonus, source), value}

    attack_sides =
      attack_mechanisms ++
        for(term <- weapon_attack_terms, do: {term.under_cap?, term.bonus}) ++
        for(term <- own_attack_terms, do: {term.under_cap?, term.bonus})

    %{total: attack_extra, clipped: attack_clipped, capped?: attack_capped?} =
      Bonuses.clip(ruleset, :attack_bonus, attack_sides)

    # Вторая рука тем же конвейером и с тем же капом — но со своим оружием,
    # своим числом с предмета и своей характеристикой атаки. `nil`, если билд
    # бьётся одним оружием: «нет второй руки» и «второй рукой ноль» — разные
    # ответы, и второй читался бы как посчитанный.
    off_hand =
      off_hand_attack(build, ruleset, dual_wield, %{
        base_attack: base_attack,
        naked_modifiers: naked_modifiers,
        modifiers: modifiers,
        race_attack: race_attack,
        weapon_type_attack: weapon_type_attack,
        penalty: dual_wield_penalty.off
      })

    # Three sources of a bonus to Fort/Ref/Will — what the player typed under
    # "Вещи", +1 per 5 ranks of Spellcraft, and (task 1.12a) the build's own
    # feats/class abilities/racial traits — and **one ceiling per save**, not
    # one per source. The first two are save-agnostic (they land on all three
    # identically); the third is not (`Iron will` only ever touches Will), so
    # the three saves' totals can now genuinely differ before the clip — see
    # `Rules.SaveBonuses`'s moduledoc and CLAUDE.md §9 for why clipping by
    # source, or pooling all three saves into one shared +20, would both
    # reproduce the "+40 instead of +20" bug this ceiling exists to prevent.
    #
    # ⚠ **And the ceiling covers gear and Spellcraft but almost none of the
    # third** (09.08.2026, Dan: «У сейвов тоже фиты не входят в кап +20 … и потом
    # ещё с вещей набрать +20»). Which side each term falls on is read off the
    # record, not off its kind — `Divine grace` and `Sacred defense` are both
    # class abilities in the shape of a feat and land on opposite sides
    # (`Rules.Caps.covers_record?/3`). One clip per save, over what it covers.
    {skill_save, save_skills} = Skills.save_bonus(build, ruleset, character_level)
    skill_values = Skills.values(build, ruleset, character_level)
    gear_save = build.gear.saves
    own_save_terms = SaveBonuses.terms(build, ruleset, modifiers)
    own_save_bonus = save_totals(own_save_terms)

    %{total: save_bonus, clipped: save_clipped, capped: saves_capped} =
      clip_saves(ruleset, gear_save, skill_save, own_save_terms)

    # Тот же конвейер во второй раз, по билду без вещей, — «сколько было бы
    # у персонажа, не введи игрок ни одного предмета» (задача S2). Второй проход,
    # а не вычитание: `clip_saves/4` стоит внутри, и снаружи его не отменить.
    #
    # ⚠ Всё, что от вещей, уходит разом и в трёх местах сразу, потому что вещь
    # добирается до сейва тремя дорогами: числом в поле «сейвы», модификатором
    # характеристики (`+12 CON` — это +6 к Стойкости) и фитом с предмета
    # (`Great fortitude` на амулете). Оставить первую и забыть вторую значило бы
    # отменить решение S1 задней дверью — там `+12 CON` требования уже не
    # выполняет, а здесь выполнял бы через Стойкость.
    #
    # ⚠ `Skills.save_bonus/3` зовётся тоже по голому билду, хотя сегодня ранги
    # от вещей не зависят и ответ тот же. Это не суеверие: задача 3.20 кладёт
    # в вещи прибавки к НАВЫКАМ, и в тот день «прибавка к Spellcraft с предмета»
    # обязана выпасть отсюда сама, а не ждать, пока кто-нибудь вспомнит про это
    # место.
    own_save_terms_naked = SaveBonuses.terms(naked_build, ruleset, naked_modifiers)
    {skill_save_naked, _} = Skills.save_bonus(naked_build, ruleset, character_level)

    %{total: save_bonus_naked} = clip_saves(ruleset, 0, skill_save_naked, own_save_terms_naked)

    # …и то же самое ещё раз, без слагаемых, которые источник исключил из
    # ТРЕБОВАНИЯ по сейву (задача S3, 17.08.2026): `Luck of heroes` даёт +1 в
    # лист и ноль в требование — «The fortitude bonus from luck of heroes does
    # not count towards the fortitude required» (`fandom:Resist energy`),
    # замерено Dan на Сиале.
    #
    # ⚠ Третье число, а не правка второго. «Голым» (`saves_naked`) значит «без
    # вещей» и отвечает на вопрос про предметы; это отвечает на вопрос «что видит
    # требование», и правил в нём на одно больше. Сложить их в одно поле —
    # значит сделать «голое» число зависящим от того, кто спрашивает, а такое
    # расходится молча: первый же читатель, которому нужно именно «без вещей»,
    # получил бы число, из которого молча вычли Удачу.
    #
    # ⚠ Считается тем же `clip_saves/4` и той же `saves/4`, а не вычитанием
    # исключённого из готового числа: потолок стоит ВНУТРИ формулы. Сегодня
    # единственная исключённая запись лежит поверх капа и обе дороги дали бы
    # одно и то же — но признак принадлежит записи, и первая же внутрикапная
    # запись с ним развела бы их без единого падающего теста.
    %{total: save_bonus_for_prereqs} =
      clip_saves(
        ruleset,
        0,
        skill_save_naked,
        SaveBonuses.for_prerequisites(own_save_terms_naked)
      )

    # Одна формула сейва на оба прохода. Списывать её вторым экземпляром было
    # нельзя: у двух копий разъезжается не результат, а смысл — «голое» число
    # обязано быть тем же самым сейвом, посчитанным по другому персонажу, иначе
    # отказ «нужна Стойкость 8» перестал бы сходиться с числом на экране.
    saves = saves(base, epic_save, modifiers, save_bonus)
    saves_naked = saves(base, epic_save, naked_modifiers, save_bonus_naked)
    saves_for_prereqs = saves(base, epic_save, naked_modifiers, save_bonus_for_prereqs)

    # What the build adds to armour class by itself — a class ability, a feat,
    # a skill, a racial trait (task 3.11). Twice, against two sets of ability
    # modifiers, for the same reason hit points take the geared constitution:
    # `Monk AC bonus` is worth whatever wisdom is worth, and "голым" has to
    # mean naked down to the modifier.
    #
    # ⚠ And the naked pass is computed off a build with **no gear at all**, which
    # since task 3.3 is not the same build: a feat an item lends
    # (`Rules.GearFeats`) is owned like any other and its armour class counts —
    # but take the item off and it goes with it, so `Armor skin` off an amulet
    # belongs in `ac_geared` only. A slot-picked `Armor skin` is unaffected and
    # stays in both, which is exactly what the two numbers are for.
    own_ac_naked = ArmorClass.terms(naked_build, ruleset, naked_modifiers)

    # ⚠ The geared pass is **not** the same list plus what the player typed: since
    # task 3.39 the two meet type by type, and one shape of bonus — the shard's
    # shield armour class — supersedes the typed number instead of adding to it
    # (`Rules.ArmorClass.geared/3`). So a term can be missing from
    # `ac_own_terms_geared` while standing in `ac_own_terms`, exactly as it
    # already could when a Monk put armour on. ⚠ Everything else **adds**: until
    # task 3.91 the whole of the build's own side competed, and a feat's +2 was
    # thrown away by an amulet worth +5. The naked list is untouched by any of
    # it, and not by a special case: it is computed off a build with empty gear,
    # where there is nothing to compete with.
    ac = ArmorClass.geared(build, ruleset, modifiers)
    own_ac_geared = ac.terms

    # Сопротивление заклинаниям (задача 3.45) — самый простой стат в этом файле
    # и единственный, у которого нет ни потолка из `stat_caps`, ни вещей, ни
    # пары «голым / в шмоте»: сумма двух монашеских фитов, и всё. ⚠ Сумма, а не
    # максимум, потому что вторая страница объявляет сложение дословно; общее
    # правило игры — «spell resistance does not stack», и оно кусает ровно там,
    # где появится SR с предмета. См. `Rules.SpellResistance`.
    spell_resistance_terms = SpellResistance.terms(build, ruleset, character_level)

    %DerivedStats{
      character_level: character_level,
      class_levels: Build.class_levels(build),
      abilities: abilities,
      ability_modifiers: modifiers,
      abilities_naked: naked,
      ability_modifiers_naked: naked_modifiers,
      gear_ability_bonuses: gear_abilities,
      hp: hp,
      hp_breakdown: hp_breakdown,
      base_attack: base_attack,
      base_attack_at_20: base.bab,
      epic_attack_bonus: epic_attack,
      # The same `base_attack`, told per class instead of as one number (task
      # 3.16). Assembled here rather than in `Progression` because the epic term
      # and the window are the character's facts, not a class's; the terms
      # themselves come off the one traversal that decided which levels count,
      # so the list and the total cannot disagree. See
      # `BuildCalculator.Rules.Progression.bab_breakdown/0`.
      bab_breakdown: %{
        by_class: base.bab_by_class,
        epic_term: epic_attack,
        counted_levels: Epic.counted_levels(ruleset)
      },
      # ⚠ Штраф стиля прибавляется ПОСЛЕДНИМ и мимо потолка: он отрицательный,
      # а `Rules.Caps` режет только сверху (`Rules.DualWield`). У персонажа
      # с одним оружием он равен нулю, то есть число ровно то же, что было
      # до задачи 3.132.
      attack_bonus:
        base_attack + modifier(naked_modifiers, attack_ability) + attack_extra +
          dual_wield_penalty.main,
      attack_ability: attack_ability,
      # ⚠ Both of these are **before** the ceiling and `attack_extra_bonus` is
      # after it, the same three-field shape the saves carry. A breakdown that
      # printed the clipped total as one of its terms could not say which source
      # lost what; printing the raw terms plus the residual can.
      gear_attack_bonus: gear_attack,
      race_attack_bonus: race_attack,
      # Что даёт ТИП оружия в руках (задача 3.35) — второй терм той же системы,
      # что и расовый бонус строкой выше, и он к нему прибавляется, а не заменяет
      # (замер Dan, `GAME_CHECKS.md` Q1). Тоже ДО потолка.
      weapon_type_attack_bonus: weapon_type_attack,
      # What the build itself adds, before the ceiling — `Epic prowess`, a small
      # race's size modifier (task 1.12b, `Rules.AttackBonuses`). Summed and by
      # term, the same two-shape pair `ac_own_bonus`/`ac_own_terms` and
      # `own_save_bonus`/`own_save_terms` already give AC and the saves.
      own_attack_bonus: own_attack,
      own_attack_terms: own_attack_terms,
      # ⚠ `attack_bonus` остаётся ОДНИМ числом и означает «AB с тем, что в руках»
      # (задача 3.5, часть B). Оружия в руках нет — число ровно то же, что было
      # до этой задачи, и ни один потребитель не задет. Матрица «AB по каждому
      # виду оружия» противоречила бы и запросу Dan («выбрать оружие и глянуть AB
      # итоговый»), и всей панели итогов, где у каждого стата одна строка.
      weapon: weapon,
      weapon_attack_bonus: weapon_attack,
      weapon_attack_terms: weapon_attack_terms,
      # Бой двумя оружиями и числа второй руки (задача 3.132). `nil` у обоих
      # означает «одна рука», а не «ноль»: штраф стиля главной руки уже внутри
      # `attack_bonus` выше, и поле нужно разбору, а не второму вычитанию.
      dual_wield: dual_wield,
      off_hand: off_hand,
      attack_extra_bonus: attack_extra,
      # How much the ceiling took off, `0` or negative. ⚠ Carried rather than
      # left for a caller to subtract: since the ceiling covers some sources and
      # not others, the difference between `attack_extra_bonus` and the sum of the
      # raw terms is **not** the clip any more — a breakdown working it out that
      # way would blame the feat that was never clipped.
      attack_cap_clipped: attack_clipped,
      # The shard's racial bonus in full — which race, which shape, all four
      # numbers the page states and which of them was counted. The interface
      # needs the three uncounted ones: the counted one is the smallest, and a
      # floor shown without saying it is a floor reads as the whole truth
      # (`BuildCalculator.Rules.RacialBonus`).
      racial_bonus: RacialBonus.of(build, ruleset),
      # И то же самое со стороны оружия: что даёт ТИП того, что в руках. Список,
      # а не одна запись, потому что одно оружие несёт до трёх бонусов сразу
      # (алебарда — Дисциплину и щитовой AC), и печатать их надо порознь.
      weapon_type_bonuses: WeaponTypeBonus.of(build, ruleset),
      # Which of the shard's groupings of classes this build belongs to — «Воины
      # Сагры», «Воины Адры». A property of the whole class list («любой другой
      # класс в билде нивелирует преимущества»), so it is computed here and not
      # per level, and it is what decides which variant of the racial bonus above
      # was counted (`BuildCalculator.Rules.ClassGroups`).
      class_groups: ClassGroups.of(build, ruleset),
      # Base is frozen by the attack bonus from the levels that count — the epic
      # bonus raises the numbers but never adds an attack. Shard rules may add on
      # top of that, and since task 3.72 one of them does: Siala's Arcane Archer,
      # +1 attack per 10 class levels up to 3 (`Rules.AttackModifiers`).
      #
      # ⚠ Терм печатается рядом с числом, потому что подпись «от BAB N» перестала
      # быть полным объяснением: у билда с Тайным лучником число больше того, что
      # даёт таблица, и молчаливая разница читалась бы как ошибка калькулятора.
      attacks_per_round: attacks,
      attacks_per_round_terms: attacks_terms,
      base_fort: base.fort + epic_save,
      base_ref: base.ref + epic_save,
      base_will: base.will + epic_save,
      # The same three base saves, told per class instead of as one «база» number.
      # Assembled here rather than in `Progression` for the same reason
      # `bab_breakdown` is: the window and the epic term are facts about the
      # character, not about a class.
      #
      # ⚠ `epic_save`, and copying `epic_attack` here would be wrong by one at the
      # cap: epic saves go up on **even** character levels and epic attack on odd
      # ones, so level 41 carries +10 saves against +11 attack (`Rules.Epic`).
      save_breakdown: %{
        by_class: base.save_by_class,
        epic_term: epic_save,
        counted_levels: Epic.counted_levels(ruleset)
      },
      epic_save_bonus: epic_save,
      gear_save_bonus: gear_save,
      skill_save_bonus: skill_save,
      save_bonus: save_bonus,
      # What the build itself adds, before the ceiling — a Paladin's charisma,
      # a Champion of Torm's class table (task 1.12a, `Rules.SaveBonuses`).
      # Summed and by term, the same two-shape pair `ac_own_bonus`/`ac_own_terms`
      # already give AC.
      own_save_bonus: own_save_bonus,
      own_save_terms: own_save_terms,
      # How much the ceiling took off each save, `0` or negative — the same field
      # `attack_cap_clipped` is, and carried for the same reason: since the ceiling
      # covers gear and Spellcraft but almost none of the build's own terms, the
      # difference between `save_bonus` and the sum of the raw addends is **not**
      # the clip any more, and a breakdown working it out that way would charge the
      # loss to `Luck of heroes`, which was never clipped.
      save_cap_clipped: save_clipped,
      fort: saves.fort,
      ref: saves.ref,
      will: saves.will,
      # Те же три сейва у персонажа без вещей. ⚠ Отдельным полем, а не
      # разностью: клип стоит внутри формулы, и «итог минус вещи» разошёлся бы
      # с правдой ровно там, где потолок кусает.
      #
      # ⚠ Поле отвечает ровно на один вопрос — «сколько было бы без предметов»,
      # тот же, на который отвечают `ac_naked` и `abilities_naked`. С 17.08.2026
      # (S3) требование по сейву читает НЕ его, а `saves_for_prereqs` ниже:
      # правил там на одно больше, и смешивать их в одном числе нельзя.
      saves_naked: saves_naked,
      # 🔴 А ЭТО поле держит правило: требование фита по сейву сравнивается
      # именно с ним. Два вычета, и оба из данных, а не из кода: вещи целиком
      # (S2, «вещи на спасы также не откроют фит») и записи разметки, которые
      # источник исключил поимённо (S3, `Luck of heroes`). Убрать его как «дубль
      # голого числа» нельзя: без него требование отвечает
      # `{:missing_data, {:prerequisite, :save_bonus}}`.
      saves_for_prereqs: saves_for_prereqs,
      # Naked means naked: no gear at all, so dexterity without its bonus too.
      # ⚠ The build's own bonuses are in **both** numbers on purpose — a Monk's
      # wisdom and a Pale Master's `Bone skin` are not equipment, so leaving
      # them out of the naked one would make "голым" mean "with nothing at all",
      # which is a different and wrong statement.
      ac_naked: ruleset.base_ac + naked_modifiers.dex + own_total(own_ac_naked),
      # ⚠ Четыре слагаемых, и последнее — не украшение: `clip` это то, что
      # потолок ТИПА снял с собственной стороны, когда её одной хватило, чтобы
      # его пробить. Сегодня он всегда 0 (прибавок с капнутым типом в данных
      # нет), но без него разбор и число разошлись бы молча в тот день, когда
      # такая запись появится, — та же форма, что `attack_cap_clipped`.
      # ⚠ `ac.dexterity.counted`, а не `modifiers.dex` — с задачи 3.41 надетый
      # доспех ставит потолок бонусу ловкости, и **только** ему: ни рефлекс, ни
      # дальняя атака, ни `Weapon Finesse`, ни навыки его не видят (страница
      # `fandom:Maximum dexterity bonus` перечисляет все четыре поимённо). Ровно
      # поэтому потолок применён здесь, к одному слагаемому, а не к самому
      # модификатору строкой выше.
      ac_geared:
        ruleset.base_ac + ac.dexterity.counted + gear_ac_total(ac) + own_total(own_ac_geared) +
          ac.clip,
      # Ловкость в AC целиком: сколько её было и сколько дошло. Отдельным полем,
      # а не разностью — разбор печатает терм «DEX» и обязан печатать дошедшее,
      # иначе он не сойдётся со своим итогом.
      ac_dexterity: ac.dexterity,
      # ⚠ Что игрок ВПИСАЛ (после потолка своего типа), а не что из этого
      # дошло: на этот вопрос отвечает `ac_by_type` по типам. Поле читает
      # интерфейс, чтобы понять, есть ли вообще шмот, — и «0» здесь означало бы
      # «AC с вещей игрок не вводил», а не «его перебило собственным».
      ac_gear_bonus: ac.typed_total,
      ac_own_bonus: own_total(own_ac_naked),
      ac_own_bonus_geared: own_total(own_ac_geared),
      ac_own_terms: own_ac_naked,
      ac_own_terms_geared: own_ac_geared,
      ac_by_type: ac.by_type,
      ac_types_resolved: ac.types,
      ac_superseded_types: ac.superseded,
      ac_cap_clipped: ac.clip,
      # `saves_capped` is already a list (`:fort_save`/`:ref_save`/
      # `:will_save`, task 1.12a) rather than one shared boolean — the three
      # saves can now be capped independently, see `clip_saves/2`.
      # ⚠️ Предела ловкости от надетого доспеха (задача 3.41) в этом списке
      # НЕТ, и это не пропуск: `capped` — «упёрлось в потолок из
      # `ruleset.stat_caps`», а этот предел принадлежит ПРЕДМЕТУ и в `stat_caps`
      # его нет вовсе. Флаг здесь заставил бы читателя спросить у `Caps.cap/2`
      # число, которого нет, и напечатать «упёрлось в кап» без величины. Факт
      # лежит там, где у него есть и величина, и причина, — в `ac_dexterity`.
      capped:
        ([
           abilities_capped? && :gear_abilities,
           # ⚠ Кап атаки — свойство СТАТА, а не руки: упёрлась любая из двух —
           # значок один, потому что и стат один. Отдельной строки «вторая рука
           # упёрлась» в этом списке нет и быть не должно; сколько именно
           # потеряла каждая, лежит у неё в `attack_cap_clipped`.
           (attack_capped? or (off_hand && off_hand.attack_capped?)) && :attack_bonus,
           ac.capped != [] && :gear_ac
         ]
         |> Enum.filter(& &1)) ++ saves_capped,
      ac_capped_types: ac.capped,
      # Одно число и его слагаемые — та же пара, что у AC, сейвов и атаки.
      # ⚠ Ноль у билда без монашеских фитов — это ответ, а не `nil`: разведка
      # по корпусу сплошная, других источников SR нет.
      spell_resistance: SpellResistance.total(spell_resistance_terms),
      spell_resistance_terms: spell_resistance_terms,
      skill_points: Skills.budget(build, ruleset, character_level),
      skill_modifiers: Skills.modifiers(build, ruleset, character_level),
      skill_values: skill_values,
      feat_slots: FeatSlots.all(build, ruleset),
      spell_slots: Spells.slots(build, ruleset),
      spells_per_day: Spells.per_day(build, ruleset),
      gaps:
        hp_gaps ++
          base.gaps ++
          formula_gaps ++
          gear_gaps(gear_abilities, ruleset) ++
          RacialBonus.gaps(build, ruleset) ++
          WeaponTypeBonus.gaps(build, ruleset) ++
          DualWield.gaps(build, ruleset) ++
          ClassGroups.gaps(build, ruleset) ++
          save_bonus_gaps(ruleset, save_skills) ++
          shard_class_gaps(build, ruleset) ++
          shard_feat_gaps(build, ruleset, character_level) ++
          GearFeats.gaps(build.gear, ruleset) ++
          GearWeapon.gaps(build, ruleset) ++
          Worn.gaps(build, ruleset) ++
          FeatBonuses.gaps(build, ruleset, character_level) ++
          AbilityBonuses.gaps(build, ruleset, character_level) ++
          SaveBonuses.gaps(build, ruleset, character_level) ++
          AttackBonuses.gaps(build, ruleset, character_level) ++
          SpellResistance.gaps(build, ruleset, character_level, spell_resistance_terms) ++
          Bonuses.cap_side_gaps(
            ruleset,
            :attack_bonus,
            :attack_bonuses,
            [
              gear: gear_attack,
              gear_weapon: weapon_attack,
              racial_bonus: race_attack,
              weapon_bonus: weapon_type_attack
            ],
            own_attack_terms
          ) ++
          Bonuses.cap_side_gaps(
            ruleset,
            :saving_throw_bonus,
            :save_bonuses,
            [gear: gear_save, skill_rule: skill_save],
            own_save_terms
          ) ++
          ArmorClass.gaps(build, ruleset, modifiers, ac) ++
          FeatChoices.gaps(build, ruleset, character_level) ++
          shard_skill_gaps(build, ruleset) ++
          skill_value_gaps(skill_values) ++
          Skills.over_cap(build, ruleset, character_level)
    }
  end

  # Числа второй руки: тот же конвейер, что у главной, с другим оружием внутри.
  # `nil`, если бой одной рукой.
  #
  # ⚠ У ДВУСТОРОННЕГО оружия «оружие второй руки» — это тот же предмет, что
  # в главной («Wielding a double-sided weapon automatically causes one to be
  # dual-wielding»), поэтому оружие берётся у стиля, а не у поля второй руки:
  # иначе `Weapon focus` на двулезвийный меч считался бы только одной руке.
  #
  # ⚠ Гэпы хука характеристики здесь НЕ собираются: главная рука уже сказала
  # всё, что можно сказать про неназванное оружие, и второй такой же строкой
  # это читалось бы как две разные недостачи.
  defp off_hand_attack(_build, _ruleset, nil, _shared), do: nil

  defp off_hand_attack(build, ruleset, dual_wield, shared) do
    weapon = dual_wield.off_hand_weapon || dual_wield.weapon
    hand = if dual_wield.off_hand_weapon, do: :off, else: :main

    weapon_terms = GearWeapon.attack_terms(build, ruleset, hand)
    weapon_attack = Enum.reduce(weapon_terms, 0, &(&1.bonus + &2))

    {ability, _gaps} =
      Attack.ability(
        ruleset,
        shared.modifiers,
        Build.feats_owned(build, ruleset, Build.character_level(build)),
        weapon,
        false
      )

    gear_attack =
      modifier(shared.modifiers, ability) - modifier(shared.naked_modifiers, ability)

    own_terms = AttackBonuses.terms(build, ruleset, [weapon] -- [nil])
    own_attack = Enum.reduce(own_terms, 0, &(&1.bonus + &2))

    mechanisms =
      for {source, value} <- [
            {:gear, gear_attack},
            {:racial_bonus, shared.race_attack},
            {:weapon_bonus, shared.weapon_type_attack}
          ],
          do: {Caps.covers_source?(ruleset, :attack_bonus, source), value}

    sides =
      mechanisms ++
        for(term <- weapon_terms, do: {term.under_cap?, term.bonus}) ++
        for(term <- own_terms, do: {term.under_cap?, term.bonus})

    %{total: extra, clipped: clipped, capped?: capped?} =
      Bonuses.clip(ruleset, :attack_bonus, sides)

    %{
      weapon: weapon,
      attack_bonus:
        shared.base_attack + modifier(shared.naked_modifiers, ability) + extra + shared.penalty,
      attack_ability: ability,
      gear_attack_bonus: gear_attack,
      race_attack_bonus: shared.race_attack,
      weapon_type_attack_bonus: shared.weapon_type_attack,
      own_attack_bonus: own_attack,
      own_attack_terms: own_terms,
      weapon_attack_bonus: weapon_attack,
      weapon_attack_terms: weapon_terms,
      attack_extra_bonus: extra,
      attack_cap_clipped: clipped,
      # ⚠ Упёрлась ли В КАП именно эта рука. Флаг свой, потому что число
      # с предмета у рук разное: остальные внутрикапные слагаемые (расовый
      # бонус и бонус за тип оружия) у них общие, а усиление второго оружия —
      # нет, и одна рука может упереться там, где другая нет.
      attack_capped?: capped?,
      style_penalty: shared.penalty,
      attacks_per_round: DualWield.off_hand_attacks(dual_wield)
    }
  end

  # What the shard's own class pages say about the classes **this build took**
  # and the core could not turn into a rule.
  #
  # Build-scoped for the same reason as the feat version below, and overdue: a
  # build with 28 levels of Weapon Master used to report `gaps: []` while
  # `extra_attack_bonus_past_class_level_10` sat in the data marked `unclear` —
  # a rule that changes the number of attacks. An empty list on a build made of
  # classes the shard rewrote is not "clean", it is silence (CLAUDE.md §9).
  #
  # Keyed by the class rather than by the level it bites at: no fact in the file
  # carries a level, and inventing one to filter by would be worse than showing
  # the caveat a level early.
  #
  # ⚠ And only the facts about something this core actually answers — the same
  # filter `ruleset.gaps` runs, off the same rule and the same vocabulary
  # (`GapReceivers`, task 3.28). A build that took a Paladin used to be told
  # «изменение Сиалы „holy_sword“ не применено»; nothing on any screen is wrong
  # because of `holy_sword`, because nothing on any screen is about it. Two
  # different answers here and in the data list would be worse than either.
  defp shard_class_gaps(build, ruleset) do
    our = GapReceivers.our(ruleset)

    for class_id <- Enum.sort(Build.classes_used(build)),
        class = Map.get(ruleset.classes, class_id),
        gap <- class_changes(class_id, class, our) ++ class_requirements(class_id, class),
        uniq: true do
      gap
    end
  end

  defp class_changes(class_id, class, our) do
    for change <- GapReceivers.filter(Map.get(class || %{}, :siala_unapplied, []), our),
        do: {:not_modelled, {:class_change, class_id, change["what"]}}
  end

  # A prestige class whose block is prose is refused outright
  # (`{:missing_data, {:class_requirements, id}}`); a class whose block is
  # **partly** readable is not, and used to say nothing about the half that was
  # skipped. Same window the feats had, closed the same way: the class stays
  # takeable and names what went unchecked.
  defp class_requirements(class_id, class) do
    keys =
      for key <- Map.get(class || %{}, :requirements_unsupported, []),
          do: {:missing_data, {:requirement, class_id, key}}

    keys ++ Prereqs.qualifiers(class)
  end

  # What the shard's own feat pages say about the feats **this build holds** and
  # the core could not turn into a rule: Divine Might scaling with class level,
  # Shadow Evade's table, the weapon lists the custom proficiencies unlock.
  #
  # Build-scoped rather than ruleset-scoped on purpose. `ruleset.gaps` answers
  # "how complete are the rules"; this answers "what is unknown about *these*
  # numbers", and a caveat about a feat nobody took is neither.
  #
  # ⚠ **A slot and an item, and NOT a class grant, checked 14.08.2026.** This is
  # not an effect and not a right to pick: it is a caveat about what the *shard
  # rewrote* on a page, scoped to the feats this character has by his own
  # statement. Widening it to `feats_owned/3` would fold in every class grant —
  # a monk would collect `evasion` and `improved_evasion` notes about a level
  # shift the core does apply, reported twice over, since a class's own facts
  # already reach him through `shard_class_gaps/2`.
  #
  # The item route arrived later than the slot one and by a separate argument:
  # a declared feat's **effect is counted** (Dan, 09.08.2026 — «если фит есть,
  # допустим тафнес, то и HP будут увеличены»), so a fact saying the shard
  # rewrote that effect and we did not apply it is exactly as owed to the man
  # wearing the feat as to the man who picked it. What is *not* owed to him is
  # the half about getting the feat in the first place — that is what the second
  # branch's `filter_held/2` drops (`GapReceivers.about_acquiring_a_feat/0`), and
  # it is why `qualifiers/1` is absent from that branch altogether: an item's
  # feat is never checked against its own prerequisites, so "we could not check
  # all of them" describes nothing that happened to this character.
  #
  # ⚠ **Filtered through the same receiver vocabulary as `class_changes/3`,
  # task "фиты: получатели у фактов" (data-miner, 14.08.2026).** Eighteen feats
  # carried `siala_unapplied`, and until this task every one of them reached
  # the player regardless of what it was about — a build with `Divine might`
  # in a slot was told «правило шарда прозой на вики есть, учтено не
  # полностью» about a fact whose entire content is how long an
  # already-uncounted buff lasts. `priv/rules/siala_41/generated/feats.json`
  # now carries `affects` on those facts (a handful of quotes tagged from
  # `Mix.Tasks.Wiki.Parse`'s `@feat_fact_affects`, since the machine layer is
  # rewritten whole and a hand-written override in `siala_41/feats.json` would
  # only ever sit *beside* the unlabelled generated fact, never replace it —
  # see that module's own note), read through the one `_receivers` dictionary
  # `siala_41/classes.json` declares. Seventeen of the eighteen ended up
  # entirely `not_our` and dropped out; `Improved evasion` was the one
  # exception, and not for the reason a quick read suggests — see
  # `@feat_fact_affects`'s own note on it. The short version («the level shift
  # is already applied by the class layer», true of every other feat here) is
  # exactly the trap that task's brief warned about.
  #
  # ⚠ **Since 17.08.2026 the exception is gone too — eighteen of eighteen —
  # and the history is kept rather than deleted, because the shape of the hole
  # is the lesson.** What kept the caveat alive was never the level shift
  # itself: it was a **consequence** of two applied sentences. Vanilla's
  # `any_of` mirrors vanilla's hand-out levels, and vanilla's Monk-9 and
  # Shadowdancer-10 branches were inert only because whoever cleared them
  # already owned the feat; the shard moved the hand-outs to 30 and 25 and
  # nobody wrote down whether the branches moved with them, so a Monk 9 cleared
  # a requirement owning nothing and could buy the feat in a Rogue bonus slot
  # at Rogue 10 — in defiance of the page's «а не с 10-го». Moving the branches
  # by inference would have been inventing numbers; `GAME_CHECKS.md` H9 asked
  # the game instead, Dan measured it on 16.08.2026 (Monk 9 / Rogue 10 does not
  # see the feat; the hand-outs are at 30 and 25), three `requirement_class_level`
  # records moved all three branches, and on 17.08.2026 Dan closed the gap:
  # «правила железные и измеряны».
  #
  # ⚠ **What the item branch is worth today: still nothing, and now for a
  # second reason.** In 14.08.2026's numbers exactly one of the twenty-one
  # facts survived `our`, and it was tagged `feat_availability` — the one
  # receiver a declaration is not about, so a declared feat gained zero lines.
  # Today none survives `our` at all, so it gains zero again, by the outer
  # filter rather than the inner one. ⚠ That makes `filter_held/2` **unexercised
  # by real data on both halves**, which is precisely when a branch rots
  # unnoticed — it is under synthetic test on purpose (`gear_feats_test.exs`,
  # два контроля), and the branch exists because the *rule* is not zero: the day
  # data-miner tags a feat fact `hp` or `ac`, the man wearing that feat is told,
  # without anyone re-reading a file. That is the same device `affects` itself
  # is built on — the label names the receiver, never the visibility
  # (CLAUDE.md §9) — and the alternative is a silent asymmetry between two
  # builds carrying the same feat.
  #
  # The old note here said `Divine might` declared from gear «stays as silent as
  # before this task». True, and it turned out to be a poor example: a `Divine
  # might` **picked in a slot** is silent too, its only fact being about
  # duration. There is no build in which that feat's caveats differ by route.
  #
  # A **qualifier** is the other half of the same idea and arrives here too: the
  # prerequisite was checked as far as the schema can express it and the rest —
  # "in the chosen spell school", "with the chosen weapon" — is declared
  # unchecked. The feat stays available; refusing it outright would be a lie in
  # the other direction (CLAUDE.md §9).
  defp shard_feat_gaps(build, ruleset, level) do
    our = GapReceivers.our(ruleset)
    picked = Build.feats_taken(build, level)

    # A feat held both ways is a picked feat: the wider filter wins, and the
    # gap is stated once rather than twice.
    worn =
      build.gear
      |> GearFeats.held(ruleset)
      |> MapSet.difference(picked)

    picked_gaps =
      for feat_id <- Enum.sort(picked),
          feat = Map.get(ruleset.feats, feat_id),
          gap <-
            feat_changes(feat_id, feat, our, &GapReceivers.filter/2) ++ Prereqs.qualifiers(feat) do
        gap
      end

    worn_gaps =
      for feat_id <- Enum.sort(worn),
          feat = Map.get(ruleset.feats, feat_id),
          gap <- feat_changes(feat_id, feat, our, &GapReceivers.filter_held/2) do
        gap
      end

    picked_gaps ++ worn_gaps
  end

  # The filter arrives as a function rather than as a narrower set of receivers:
  # an empty set means "no vocabulary, no filtering" to `GapReceivers`, so
  # subtracting until it empties would report *more* instead of less. Both
  # callers pass the ruleset's own `our`; which question is being asked is the
  # function they pass with it.
  defp feat_changes(feat_id, feat, our, filter) do
    for change <- filter.(Map.get(feat || %{}, :siala_unapplied, []), our),
        do: {:not_modelled, {:feat_change, feat_id, change["what"]}}
  end

  # ⚠ Пять сборщиков гэпов из разметки прибавок жили здесь пятью почти
  # одинаковыми обёртками — по одной за задачу (HP 1.9, характеристики 3.1,
  # сейвы 1.12a, атака 1.12b, AC 3.11 уже своей). Задача 3.21 переселила их к
  # своим статам (`FeatBonuses.gaps/3`, `AbilityBonuses.gaps/3`,
  # `SaveBonuses.gaps/3`, `AttackBonuses.gaps/3`, `ArmorClass.gaps/4`), потому
  # что форма гэпа — словарь стата, а не оглавление `compute/2`. Здесь остался
  # только вызов, и это ровно то, чем `compute/2` и должна быть.

  # The shard rewrote 22 of 29 skill pages, and almost none of it reaches a
  # number. So this is scoped tighter still — only the skills the build actually
  # bought ranks in — and only says what it can honestly say: "the shard changed
  # this and we did not apply it".
  #
  # ⚠ **Filtered through the same receiver vocabulary as `class_changes/3` and
  # `feat_changes/4`, task "навыки: получатели у фактов" (data-miner,
  # 14.08.2026).** Before the markup this loop showed every unapplied fact of
  # a skill a build had ranks in, `crafting` and `traps` and `mounted_combat`
  # included — a build with ranks in `craft_armor` was told about a change to
  # a crafting formula the calculator has no notion of at all, the exact noise
  # task 3.28 removed from the class layer. Now it says only what is a hole in
  # an answer this calculator gives — a page that states which classes hold a
  # skill and cannot be turned into a rule (`set_trap`'s
  # `class_skills_unchanged`, the one such fact left today), and Harper Scout's
  # Bardic Knowledge bonus to Lore if it is ever demoted off `verified` (today
  # it is applied and carries no gap at all).
  #
  # ⚠ **The Rogue's stealth-mode penalty to Spot/Listen left this list on
  # 17.08.2026, and it left by the front door.** `listen`/`spot`'s
  # `rogue_stealth_penalty` used to be the example here; Dan classified it as a
  # buff («Режим скрытности = считай бафф»), i.e. the same временность gate that
  # closed Bard song, Rage and Shadow Evade on 10.08.2026 — a mode that is
  # switched on and ends is a state of combat, not a property of the build
  # (CLAUDE.md §9). Both records carry `affects: ["buff"]` now.
  #
  # ✅ **И третья копия того же предложения — классовая (`{:class_change,
  # :rogue, "stealth_perception_penalty"}`) — переведена на `buff` тем же днём**,
  # когда решение Dan показали на ней самой. Здесь стояло, что она «всё ещё
  # несёт `skill_values` и всё ещё отчитывается»; это было верно ровно до
  # вечера. Урок, ради которого абзац оставлен: одно предложение источника
  # лежало ТРЕМЯ записями в ДВУХ файлах, и решение владельца применили к ним
  # в два захода — правя факт, ищи его копии.
  #
  # ✅ **`craft_trap` тоже ушёл отсюда 17.08.2026, и по другой причине —
  # он ПРИМЕНЁН.** Его «сделан классовым для Теневого танцора» считалось
  # расхождением с `classes.json` (там тем же предложением добавлен `set_trap`),
  # а замер Dan показал, что классовыми стали оба навыка: спор был не двух
  # прочтений, а неполнотой страницы. Билд с уровнями ШД теперь покупает оба
  # навыка по классовой цене и под классовым потолком.
  defp shard_skill_gaps(build, ruleset) do
    our = GapReceivers.our(ruleset)

    invested =
      for {_level, bought} <- build.skills,
          {skill, ranks} <- bought,
          ranks > 0,
          uniq: true,
          do: skill

    for skill_id <- Enum.sort(invested),
        skill = Map.get(ruleset.skills, skill_id),
        not is_nil(skill),
        gap <- skill_gaps(skill_id, skill, our),
        uniq: true do
      gap
    end
  end

  defp skill_gaps(skill_id, skill, our) do
    for change <- GapReceivers.filter(Map.get(skill, :siala_unapplied, []), our),
        do: {:not_modelled, {:skill_change, skill_id, change["what"]}}
  end

  # What could not be assembled into a skill's final value — two shapes, "nobody
  # ever wrote down this skill's key ability" and "nobody said whether armour
  # takes anything off it". Produced by `Skills.value/4` rather than restated
  # here, so the decision about what an unknown term means lives in exactly one
  # place.
  #
  # ⚠ Both were about one skill (`alchemy`) and both were answered by one
  # measurement (Dan, 17.08.2026, `GAME_CHECKS.md` P1), so no shipped ruleset
  # produces either today. The route stays under test on a copy of `priv/rules`
  # with the field taken out — the shard's next own skill arrives the same way.
  defp skill_value_gaps(values) do
    for {_skill, value} <- Enum.sort(values), gap <- value.gaps, do: gap
  end

  # The Spellcraft bonus is applied flat, and it is not flat: vanilla gives it
  # against spells only, and Siala takes it away from area spells on top
  # (Implosion excepted). Showing it flat is Дан's decision — the interface does
  # not carry conditions — but a decision the player has to be told about, or
  # the saves are simply overstated against exactly what they are held up for.
  defp save_bonus_gaps(ruleset, skills) do
    for rule <- Map.get(ruleset, :skill_rules, %{})[:save_bonus] || [],
        not is_nil(rule.scope),
        rule.skill in skills,
        do: {:not_modelled, {:save_bonus_scope, rule.skill}}
  end

  defp modifier(_modifiers, nil), do: 0
  defp modifier(modifiers, ability), do: Map.get(modifiers, ability, 0)

  defp own_total(terms), do: Bonuses.sum(terms, :ac)

  # Сколько из вписанного игроком реально дошло до «AC в шмоте» — сумма по
  # типам ПОСЛЕ правила столкновения (задача 3.39), а не сумма введённого.
  # Второе лежит рядом в `ac_gear_bonus` и отвечает на другой вопрос.
  defp gear_ac_total(%{by_type: by_type}),
    do: Enum.reduce(by_type, 0, fn {_type, value}, sum -> sum + value end)

  # `Rules.SaveBonuses.terms/3`, summed per save rather than into one number —
  # a save has no single total the way armour class does, so `own_total/1`
  # does not fit here.
  #
  # ⚠ Не `Bonuses.group_sum/3`, и это единственное место, где различие важно:
  # там цель, которую никто не поднял, **отсутствует** («здесь ничего» ≠
  # «вообще ничего»), а здесь каждый ключ обязан быть на месте даже нулём —
  # это то, к чему прибавляет `clip_saves/4`, и пропущенный ключ читался бы
  # как «нечего клипать», а не «ничего не заработано». `Map.update!/3`
  # заодно сторож: сейв не из трёх названных здесь падает, а не тихо
  # добавляет четвёртый ключ.
  defp save_totals(terms) do
    Enum.reduce(terms, %{fort: 0, ref: 0, will: 0}, fn term, acc ->
      Map.update!(acc, term.save, &(&1 + term.bonus))
    end)
  end

  # Три сейва из уже посчитанных слагаемых: классовая база, эпический терм,
  # модификатор характеристики и всё, что прибавилось, после потолка.
  #
  # ⚠ Функция заведена задачей S2 не ради краткости, а ради **одной** формулы
  # на два прохода: «в шмоте» и «голым». Пока формула стояла строчками в
  # структуре, второй проход неизбежно был бы её копией, а две копии одного
  # правила расходятся молча — ровно тем способом, каким однажды разошёлся клип
  # капа (CLAUDE.md §9).
  #
  # ⚠ Какой характеристикой считается какой сейв — единственное игровое знание
  # здесь, и оно не переехало из этого файла, а только перестало быть в нём
  # написанным трижды.
  defp saves(base, epic_save, modifiers, save_bonus) do
    %{
      fort: base.fort + epic_save + modifiers.con + save_bonus.fort,
      ref: base.ref + epic_save + modifiers.dex + save_bonus.ref,
      will: base.will + epic_save + modifiers.wis + save_bonus.will
    }
  end

  # **One ceiling per save**, over exactly the sources the ruleset says it covers
  # — never one ceiling per source (that bug already happened once, CLAUDE.md §9)
  # and never one shared ceiling split three ways (a `Divine grace` Paladin and an
  # `Iron will` Fighter would then compete for the same +20 with saves that have
  # nothing to do with each other).
  #
  # ⚠ Two levels answer "which side", and the rule between them is one sentence:
  # **a record's own statement wins, and the source kind is the default only for
  # the addends that have no record** — gear and the skill rule (Spellcraft), both
  # inside, both cited. Everything from `feat_save_bonuses.json` carries its own
  # `under_cap?`, and thirteen of the fourteen are on top of the ceiling since
  # 09.08.2026 (Dan). Reading the side is a lookup; the clip is still single.
  #
  # Returns `%{total:, clipped:, capped:}` — the per-save total after the ceiling
  # (the clipped part plus what sits on top of it), how much the ceiling took off
  # per save (`0` or negative), and which of
  # `:fort_save`/`:ref_save`/`:will_save` actually hit it, for `stats.capped`
  # (task 1.12a: three atoms, not one shared `:saving_throws`, because the three
  # saves cap independently once a source can raise one without the other two).
  #
  # ⚠ **Арифметики здесь больше нет** — она вся в `Bonuses.clip/3`, одна на
  # атаку и сейвы (задача 3.21). Осталось только «три цели вместо одной»,
  # которая и есть специфика сейвов: раньше две формы одного клипа стояли рядом
  # и разошлись дважды (клип по половинке у сейвов, клип по источнику у атаки).
  defp clip_saves(ruleset, gear_save, skill_save, own_terms) do
    mechanisms =
      for {source, value} <- [{:gear, gear_save}, {:skill_rule, skill_save}],
          do: {Caps.covers_source?(ruleset, :saving_throw_bonus, source), value}

    Enum.reduce([:fort, :ref, :will], %{total: %{}, clipped: %{}, capped: []}, fn save, acc ->
      own = for term <- own_terms, term.save == save, do: {term.under_cap?, term.bonus}
      clip = Bonuses.clip(ruleset, :saving_throw_bonus, mechanisms ++ own)

      %{
        total: Map.put(acc.total, save, clip.total),
        clipped: Map.put(acc.clipped, save, clip.clipped),
        capped: if(clip.capped?, do: [save_cap_flag(save) | acc.capped], else: acc.capped)
      }
    end)
  end

  defp save_cap_flag(:fort), do: :fort_save
  defp save_cap_flag(:ref), do: :ref_save
  defp save_cap_flag(:will), do: :will_save

  # Skill points are granted per level from the intelligence of that level, and
  # gear is a single final set with no history — so the budget is computed from
  # the intelligence the *character* has.
  #
  # ⚠ **Whether that is the game's rule or our choice is now the ruleset's to
  # say** (задача 3.105, 25.08.2026): «INT с вещей скилл поинты при повышении
  # уровня не увеличивает» (Dan). Here that turns into one question — has anyone
  # stated the rule — and `Rules.Skills.gear_intelligence/1` is the same reader
  # the arithmetic uses, so the number and this caveat cannot disagree.
  #
  # ⚠ Before that day this comment said the rule «is not stated anywhere we can
  # cite» while CLAUDE.md §6 claimed it stood on Dan's word about
  # **constitution** («CON в отличие от интеллекта работает сразу за все
  # уровни»). One of the two had to be wrong about which question had been
  # answered, and it was the справка: that measurement was about retroactivity,
  # not about the level-up grant.
  #
  # ⚠ Silence still speaks: a ruleset carrying no such record keeps the very
  # same arithmetic **and** gets the caveat back, and only on builds where worn
  # intelligence could have moved the number at all.
  defp gear_gaps(%{int: bonus}, ruleset) when bonus != 0 do
    case Skills.gear_intelligence(ruleset) do
      nil -> [{:assumed, :skill_points_ignore_gear_intelligence}]
      _stated -> []
    end
  end

  defp gear_gaps(_bonuses, _ruleset), do: []

  @doc """
  Whether one more class level may be taken, and if not, every reason why.

  Reasons are structured data (`{:requires_bab, 7}`), never Russian text.
  """
  @spec validate_level_up(Build.t(), map() | atom(), map()) :: :ok | {:error, [LevelUp.reason()]}
  def validate_level_up(%Build{} = build, class, ruleset) when is_atom(class) do
    validate_level_up(build, %{class: class}, ruleset)
  end

  def validate_level_up(%Build{} = build, choice, ruleset) when is_map(choice) do
    LevelUp.validate(build, choice, ruleset, compute(build, ruleset))
  end

  @doc """
  Every level in `build`'s own ladder whose class no longer qualifies, checked
  against the build **as it stands right now**.

  The scenario this exists for (Дан, 03.08.2026): a build stacks ten levels of
  Weapon Master on feats it legitimately held at the time, the player scrolls
  back and clears one of those feats, and nothing rechecks the ten levels that
  used to need it. `compute/2` still returns numbers for all forty-one levels
  — it has no opinion on whether a level was ever earned, only on what it is
  worth — so without this the build reads as legal right up until it is
  pasted somewhere that replays it (`BuildCalculatorWeb.Builder.Import`) and
  the same ten levels come back refused. Shown once it is pasted and not a
  moment before is exactly the false legality AGENT_QUEUE.md/HANDOFF.md's
  «контракт из двух половин» calls the worse of the two failure modes.

  One entry per `{level, class, reason}`, and **every** offending level, not
  only the first one: a caller building a short report may want to fold that
  down to one line per class (`Builder.Import` does, through its own — and
  deliberately narrower, see the comment there — reading of which reasons are
  worth a paste's report), but a progression column has to mark every level
  the problem actually touches, or the mark sits on the wrong row.

  ⚠ `stats` is computed **per level, off the build truncated to that level**
  (`Build.truncate(build, level - 1)`) — never off the whole build passed in.
  `{:requires_bab, n}` compared against the *final* build's base attack would
  read as satisfied almost always, because base attack only grows as levels
  are appended; using it here would quietly trade the false legality this
  function exists to catch for another false legality of its own.
  """
  @spec illegal_class_levels(Build.t(), map()) :: [{pos_integer(), atom(), LevelUp.reason()}]
  def illegal_class_levels(%Build{} = build, ruleset) do
    for {class, level} <- Enum.with_index(build.levels, 1),
        stats = compute(Build.truncate(build, level - 1), ruleset),
        {:error, reasons} <- [LevelUp.validate(build, %{class: class, at: level}, ruleset, stats)],
        reason <- reasons do
      {level, class, reason}
    end
  end

  @doc """
  Every already-placed feat pick in `build` whose prerequisites no longer
  hold, replayed the same way as `illegal_class_levels/2`.

  Catches the half a class-only replay cannot: a feat taken on an ability
  threshold that a later edit removed (`{:requires_ability, …}`), a feat
  requiring another feat that was since cleared out of its slot
  (`{:requires_feat, …}`), and so on — AGENT_QUEUE.md §1.3's "снятие
  прибавки к характеристике, от которой зависел порог фита". No class
  requirement block in the data uses `abilities` at all today, only feats
  do, so this half is not optional if that scenario is to be caught.

  ## Slot bookkeeping: not re-asked, then re-asked, and by which criterion

  ⚠ Until 24.08.2026 this asked `validate_feat/3` — the requirement block alone —
  and said so: "is the pick a duplicate, does a `same_choice_as` partner still
  hold … is deliberately **not** re-asked here", mirroring
  `illegal_class_levels/2`, which reads a class's `requirements` block and has
  nothing to say about how the class was slotted in either. One exception was
  already carved out, and its wording is what decided this: `FeatSlots.choice_refusals/4`
  was re-asked because "its absence would be a false legality **reachable without
  hand-editing anything**".

  🔴 Task 3.84 found the same criterion met by the duplicate, so this now asks
  `validate_feat_pick/3` — requirements **plus** slot refusals **plus**
  `Rules.FeatChoices.reasons/3`. What Dan did (24.08.2026) needed no hand-editing
  at all: take levels while leaving the feat rows empty, pick `Blind fight` on a
  late level, then scroll back to an earlier empty row and pick `Blind fight`
  again. `FeatChoices.reasons/3` knew — `[already_taken: :blind_fight]` — and
  nothing asked it, so the ladder marked no level and the row read `Blind fight ×2`
  for a feat that may be held once.

  ⚠ **The later level is accused, and that is the game's own answer, not a
  tie-break.** A pick's history is the build truncated to its own level
  (`FeatChoices`'s `history/3`), so level 3 cannot see level 6 and level 6 sees
  level 3. Levels are taken in order: on level 3 the feat was genuinely offered,
  on level 6 it would not have been. Accusing the *earlier* level was considered
  and refused by Dan — it contradicts the game, makes the answer depend on the
  order the rows were edited, and forbids the legal "move this feat earlier".

  ⚠ The pick never accuses itself: `illegal_feats/2` passes `:slot`, and that is
  precisely what makes `history/3` empty the slot being asked about before
  counting. Passing the pick without `:slot` would make **every** placed feat a
  duplicate of itself.

  ⚠ One consequence was accepted in advance rather than discovered: `Toughness`
  put in the general slot of level 1 by a class that hands it over for free
  (Fighter, Barbarian, …) is now `{:already_taken, :toughness}` — a slot spent for
  nothing, and CLAUDE.md §9's open question «Ловить ли это». Dan, 24.08.2026:
  catch it.

  ⚠ One head of `validate_feat_pick/3` is **exempted** here, and the criterion is
  the same one read the other way: `{:requires_choice, …}` is not a fact about the
  character but about our record — see `placed_pick_exemptions/1`.

  ⚠ What a row is **marked** for remains the web layer's policy, not this
  function's: `BuildCalculatorWeb.Builder.Labels` keeps its own whitelist and
  decides which of these heads reach the ladder.
  """
  @spec illegal_feats(Build.t(), map()) ::
          [
            {pos_integer(), Build.slot_id(), atom(),
             Prereqs.reason()
             | FeatSlots.class_reason()
             | FeatSlots.choice_reason()
             | FeatChoices.reason()}
          ]
  def illegal_feats(%Build{} = build, ruleset) do
    for {level, slot_id, feat_id, choice} <- Build.feat_picks(build, Build.character_level(build)),
        pick = %{feat: feat_id, at: level, choice: choice, slot: slot_id},
        reasons = feat_pick_reasons(build, pick, ruleset),
        reason <- reasons do
      {level, slot_id, feat_id, reason}
    end
  end

  defp feat_pick_reasons(build, pick, ruleset) do
    case validate_feat_pick(build, pick, ruleset) do
      :ok -> []
      {:error, reasons} -> reasons -- placed_pick_exemptions(reasons)
    end
  end

  # The one head of `validate_feat_pick/3` a **placed** pick must not be accused
  # of. `{:requires_choice, …}` says the pick records no value, which is the right
  # answer on the write path — a choiceless pick of a repeatable feat is
  # indistinguishable from another one, so the slot model refuses it — and the
  # wrong answer on a replay: every pick already in a build got there somehow, and
  # the missing field is **our record**, not the character. Same line the ladder's
  # own whitelist draws around `:missing_data`: «не смогли решить» is not «билд
  # нарушает правило», and marking a level for it trades the false legality this
  # function exists to catch for a false illegality of its own.
  #
  # ⚠ Reachable without hand-editing, which is why it is exempted rather than
  # left to the web layer to filter: `BuildCalculatorWeb.Builder.Import` places
  # feats through `Builder.Feats.best_slot/4` and records a qualifier only when
  # the pasted text spells one out, so `Weapon Focus` pasted bare is a legal build
  # carrying a choiceless pick. It already reports that as its own issue
  # (`:feat_qualifier_dropped`), in the register the fact belongs to.
  defp placed_pick_exemptions(reasons) do
    for {:requires_choice, _feat, _domain} = reason <- reasons, do: reason
  end

  @doc """
  Whether a feat may be taken on this level at all, and if not, every reason why.

  `build` is the character **as it stands on the level the feat is picked on**:
  that level's class, hit points and ranks all count, because NWN checks a feat
  against the character the level-up has already produced. Pass
  `%{feat: id, at: level}` to ask about a level in the middle of a finished
  build; the plain form asks about the build's own last level.

  `%{feat: id, choice: value}` answers about a feat taken **with** something, and
  one requirement in the schema needs it: `Epic skill focus` wants "20 ranks in
  **the chosen skill**", which is a requirement about the pick rather than about
  the character. Without a choice the check stays exactly what it was.

  Three questions, not one, and only the first is a prerequisite:

    * the feat's own requirement block (`BuildCalculator.Rules.Prereqs`, the same
      reader `validate_level_up/3` uses);
    * whether the class of **this level** takes the feat off the general feat list
      at all — `{:forbidden_by_class, class}`. That answer belongs to the level and
      not to the character: the very same feat is legal on the next level if that
      level belongs to another class, and a feat already picked on a legal level
      stays picked. `Rules.FeatSlots` decides it, here as well as in the picker's
      slot lists, so there is exactly one reading of it;
    * whether **any** level-up may pick it — `{:not_selectable_at_level_up, id}`,
      the shard's «Умение нельзя выбрать при росте персонажа». Neither a
      prerequisite nor a fact about the level: the feat works, it just arrives on
      an item. Until 09.08.2026 this answered `:ok` while every slot refused the
      feat, so the two halves of the same question disagreed — see
      `feat_level_up_refusals/2`.

  Slot bookkeeping — is there a free slot, does *that* slot accept this feat, is
  the feat already taken — is still **not** here: that is
  `BuildCalculator.Rules.FeatSlots` and the picker.
  """
  @spec validate_feat(Build.t(), atom() | map(), map()) ::
          :ok | {:error, [Prereqs.reason() | FeatSlots.class_reason()]}
  def validate_feat(%Build{} = build, feat_id, ruleset) when is_atom(feat_id) do
    validate_feat(build, %{feat: feat_id}, ruleset)
  end

  def validate_feat(%Build{} = build, choice, ruleset) when is_map(choice) do
    scoped =
      case Map.get(choice, :at) do
        level when is_integer(level) and level >= 0 -> Build.truncate(build, level)
        _whole -> build
      end

    feat_id = Map.fetch!(choice, :feat)

    prereqs =
      case Prereqs.feat(
             scoped,
             feat_id,
             ruleset,
             compute(scoped, ruleset),
             Map.get(choice, :choice),
             stats_entering_level(scoped, feat_id, ruleset)
           ) do
        :ok -> []
        {:error, reasons} -> reasons
      end

    # The level a scoped build is being asked about is its own last one — the same
    # convention `Prereqs` reads it by.
    refused =
      feat_level_up_refusals(feat_id, ruleset) ++
        class_feat_refusals(scoped, Build.character_level(scoped), feat_id, ruleset)

    case refused ++ prereqs do
      [] -> :ok
      reasons -> {:error, reasons}
    end
  end

  # Тот же персонаж, каким он ВОШЁЛ в уровень, на котором тратится слот
  # (задача S6, 17.08.2026). Требование по сейву сравнивается с ним, и только
  # оно: `character_level` замерен и читает состояние ПОСЛЕ взятия уровня —
  # эпический фит доступен на 21-м сразу.
  #
  # ⚠️ «До уровня» здесь — ровно тот же `Build.truncate(build, level - 1)`,
  # которым считается дельта левелапа (см. «Deltas» в моддоке). Второго
  # определения «состояния до уровня» в ядре быть не должно: две реализации
  # разойдутся, и игрок увидит одно, а получит другое.
  #
  # ⚠️ Считается ПО ТРЕБОВАНИЮ, а не всегда, и это не преждевременная
  # оптимизация: `compute/2` на билде в 41 уровень стоит 0,32 мс, а список фитов
  # прогоняет требования через все 310 записей справочника на каждую
  # перерисовку. Ключ сегодня несёт **один** фит из 310 (`Resist energy`),
  # то есть безусловный второй проход удваивал бы самый горячий путь ядра ради
  # одной строки. Кто спрашивает — `Prereqs.reads_entering_level?/1`, там же
  # сказано, почему промах этого предиката безопасен.
  #
  # ⚠️ Из взятого уровня в снимок ВОЗВРАЩАЕТСЯ ровно одно — прибавка
  # характеристики, записанная на нём (задача S7b, 17.08.2026). Замер Dan:
  # «на 12 уровне взял CON +1 → с 11 до 12. Resist energy был доступен», при
  # том что базовая Стойкость на входе была 7. То есть игра считала 7 + 1 = 8:
  # прогрессию сейва этого уровня не взяла, а прибавку характеристики — взяла.
  # Контроль снят отдельным билдом (S6, воин 12 с телосложением 10): тот же
  # снимок 7, тот же модификатор 0, и фита в игре нет. Разница между двумя
  # билдами ровно одна — прибавка.
  #
  # ⚠️ И **больше ничего**, хотя обобщение напрашивалось и было сформулировано:
  # «считается всё, что в мастере левелапа выбирается раньше фитов». Его убил
  # замер S7c — ранги навыка, купленные на том же уровне, не считаются
  # («взял 5 раз навык spellcraft, но не повышал CON до 12. Как итог resist
  # energy не доступен»). Правило оказалось не про порядок экранов мастера,
  # а про конкретное слагаемое, и расширять его снова можно только замером.
  defp stats_entering_level(scoped, feat_id, ruleset) do
    definition = Map.get(ruleset.feats, feat_id)

    if definition && Prereqs.reads_entering_level?(Map.get(definition, :prereqs)) do
      scoped |> build_entering_level(Build.character_level(scoped)) |> compute(ruleset)
    end
  end

  # Персонаж, каким его видит мастер левелапа на `level`: уровень ещё не
  # засчитан, но прибавка характеристики, выбранная на нём, уже применена.
  #
  # ⚠️ `max(…, 0)` не косметика: `Build.truncate/2` зовёт `Enum.take/2`,
  # а `Enum.take(list, -1)` берёт ПОСЛЕДНИЙ элемент, а не пустой список. Без
  # клампа билд нулевой длины дал бы «состояние до» из одного уровня.
  defp build_entering_level(%Build{} = build, level) do
    entering = max(level - 1, 0)
    snapshot = Build.truncate(build, entering)

    case Map.get(build.ability_increases, level) do
      nil ->
        snapshot

      ability ->
        increases = snapshot.ability_increases

        %Build{
          snapshot
          | ability_increases: Map.put(increases, free_increase_key(increases, entering), ability)
        }
    end
  end

  # Куда положить прибавку взятого уровня, чтобы снимок её увидел.
  #
  # Ключ в `ability_increases` — это МЕСТО В КАРТЕ, а не факт о персонаже:
  # `Abilities.scores_at/3` складывает все прибавки, у которых ключ не больше
  # уровня, и номера ей безразличны. Снимок обрезан до `entering`, значит ключ
  # взятого уровня в него не попадает вовсе, и прибавку надо переложить внутрь.
  #
  # ⚠️ Свободный ключ ищется вниз от `entering`, а не берётся наугад: сегодня
  # прибавки идут раз в четыре уровня и столкнуться не могут, но это правило
  # ДАННЫХ (`epic.json` → `ability_increases`), а ядро на игровые числа
  # не опирается (CLAUDE.md §3). Затёртая чужая прибавка была бы тихой ложной
  # нелегальностью — то есть ровно тем, что эта правка убирает.
  #
  # ⚠️ Отвергнуто: прибавить единицу к `base_abilities` снимка. Число вышло бы
  # то же, а разбор характеристики соврал бы — прибавка уровня приехала бы
  # термом поинт-бая. Снимок наружу не выходит, но лгать внутри структуры,
  # которую кто-нибудь однажды напечатает, дороже трёх строк здесь.
  #
  # ⚠️ Названо честно: у билда, где прибавка стоит на КАЖДОМ уровне, свободного
  # ключа среди уровней не остаётся и поиск уходит в ноль и ниже, то есть
  # за пределы `Build.t()` (`%{pos_integer() => ability()}`). Такой билд сегодня
  # не собирается ни одним ruleset'ом, снимок живёт внутри этой функции и наружу
  # не выходит, а альтернатива — молча потерять прибавку — хуже: она врёт
  # в ответе, а не в аннотации типа.
  defp free_increase_key(increases, entering) do
    Enum.find(Stream.iterate(entering, &(&1 - 1)), &(not Map.has_key?(increases, &1)))
  end

  @doc """
  Why no level-up may pick `feat_id` at all — `[]` when one may.

  The shard's «Умение нельзя выбрать при росте персонажа» (`Riding Sprint`,
  `Smile of Death`): the third refusal beside `{:feat_disabled, id}` ("the shard
  removed it") and `{:forbidden_by_class, class}` ("not on a level of this
  class"). Nothing about the build changes the answer, so it takes none.

  Folded into `validate_feat/3` and exposed here for the caller that has no slot
  in hand — the same arrangement `class_feat_refusals/4` has, and for the same
  reason: one reading of the rule instead of the picker's own.

  ⚠ Says nothing about declaring the feat off an **item**
  (`validate_gear_feat/2`), which stays legal and is the only route such a feat
  has into a build.
  """
  @spec feat_level_up_refusals(atom(), map()) :: [FeatSlots.level_up_reason()]
  def feat_level_up_refusals(feat_id, ruleset),
    do: FeatSlots.level_up_refusals(ruleset, feat_id)

  @doc """
  Why the class taken on `level` refuses `feat_id` outright — `[]` when it does not.

  «These general feats cannot be selected when taking a level of bard» is a rule
  of the level, not of the character, so it needs the level: pass the character
  level the pick sits on. Reasons are `{:forbidden_by_class, class}`, the same
  ones `validate_feat/3` folds in; the interface asks this one directly when it
  has a row to explain and no slot to point at.

  `0` and a level past the end of the ladder are legal questions with the same
  answer: no class is taken there, so nothing is forbidden.
  """
  @spec class_feat_refusals(Build.t(), non_neg_integer(), atom(), map()) ::
          [FeatSlots.class_reason()]
  def class_feat_refusals(%Build{} = build, level, feat_id, ruleset) do
    FeatSlots.class_refusals(ruleset, Build.class_at(build, level), feat_id)
  end

  @doc """
  Whether `feat_id` may be declared as coming from an **item**, and if not, why.

  The feat then satisfies a **class's** requirement without occupying a slot, and
  its effect counts — see `BuildCalculator.Rules.GearFeats` for the whole rule
  and the argument behind each half of it. `Rules.Gear.toggle_feat/3` is what
  records the declaration once this has cleared it.

  ⚠ Takes a whole declaration since task 3.97 — a bare `feat_id` or a
  `{feat_id, choice}` pair — because a value that the feat's domain does not
  accept is a refusal of the same kind as a feat the shard switched off. Whether
  a *particular* value is free is `validate_gear_feat_choice/4`'s question, which
  is the one the interface asks while offering the list.
  """
  @spec validate_gear_feat(Gear.feat_entry(), map()) :: :ok | {:error, [GearFeats.reason()]}
  defdelegate validate_gear_feat(feat_id, ruleset), to: GearFeats, as: :validate

  @doc """
  Every feat declared as coming from an item that this ruleset refuses.

  `[{feat_id, reason}]`; the same "replay what is already in the build" contract
  `illegal_feats/2` keeps for picks — a link carrying a feat the shard has since
  switched off must not read as legal (`BuildCalculator.Rules.GearFeats`).
  """
  @spec illegal_gear_feats(Build.t(), map()) :: [{atom(), GearFeats.reason()}]
  def illegal_gear_feats(%Build{gear: gear}, ruleset), do: GearFeats.illegal(gear, ruleset)

  @doc """
  Whether `weapon_id` may be the weapon in this build's hands, and if not, why.

  Takes the build, unlike `validate_gear_feat/2`: the list of weapons a character
  may hold is filtered by the proficiency feats he owns (Dan, 10.08.2026), so the
  answer is about this character and not only about the weapon. The whole rule —
  including the staff that needs no proficiency and the club whose requirement
  nobody wrote down — is `BuildCalculator.Rules.GearWeapon`.

  ⚠ `hand` is `:main` or `:off` (task 3.132), and the answer genuinely differs:
  the off hand refuses a weapon that takes both hands, and refuses everything
  while the main hand holds one. Both phrases are the off hand's own — see
  `Rules.Vocabulary`.
  """
  @spec validate_gear_weapon(Build.t(), atom(), map(), atom()) ::
          :ok | {:error, [GearWeapon.reason()]}
  defdelegate validate_gear_weapon(build, weapon_id, ruleset, hand \\ :main),
    to: GearWeapon,
    as: :validate

  @doc """
  Every weapon the gear block may offer, with the reason a refused one is refused.

  ⚠ Refused weapons are **in** the list (CLAUDE.md §6, «недоступное показываем
  с причиной»); what is left out entirely is what cannot be an item at all — a
  creature's attack form has no bonus to type. The order is the dictionary's own,
  by name.

  ⚠ `hand` decides which refusals apply (task 3.132): the off hand's list refuses
  every two-handed weapon and, while the main hand holds one, everything.
  """
  @spec gear_weapon_candidates(Build.t(), map(), atom()) :: [GearWeapon.candidate()]
  defdelegate gear_weapon_candidates(build, ruleset, hand \\ :main),
    to: GearWeapon,
    as: :candidates

  @doc """
  The weapon recorded in this build that it may not hold — `[{weapon_id, reason}]`,
  at most one entry.

  Same contract and same reason as `illegal_gear_feats/2`: take the proficiency
  feat away and the weapon stops counting, but it stays in the build and is named
  here. Silently confiscated reads as a bug, named reads as a rule (task 1.7).
  """
  @spec illegal_gear_weapon(Build.t(), map()) :: [{atom(), GearWeapon.reason()}]
  defdelegate illegal_gear_weapon(build, ruleset), to: GearWeapon, as: :illegal

  @doc """
  Бой двумя оружиями этого билда — `nil`, если персонаж бьётся одним
  (задача 3.132).

  То же, что лежит в `stats.dual_wield`, и отдельной функцией ровно по той же
  причине, по какой `illegal_gear_weapon/2` живёт рядом с `compute/2`: интерфейс
  спрашивает это, когда игрок ЕЩЁ выбирает оружие, а не когда читает итоги.
  """
  @spec dual_wield(Build.t(), map()) :: DualWield.t() | nil
  defdelegate dual_wield(build, ruleset), to: DualWield, as: :of

  @doc """
  Every worn item this build records and may not use, as
  `[{category_id, item_id, reason}]` (task 3.43).

  The third member of the same family as `illegal_gear_feats/2` and
  `illegal_gear_weapon/2`, and it keeps the same contract: what the player
  recorded stays recorded, and what he may not use is **named** rather than
  quietly dropped from the numbers. Two things make it refuse — the race («gnomes
  and halflings may not use tower shields») and what is in the other hand
  («Creatures may not simultaneously use a shield and a two-handed weapon») —
  and both may fire at once, so one item may appear twice.

  ⚠ A refused item is worth nothing while refused: no base armour class, no
  armour check penalty, and it does not switch a Monk's bonuses off either.
  Before this task a Карлик was offered a tower shield along with +3 AC and −10 to
  stealth the game does not give him.

  ⚠ Whether a shield is refused depends on the **weapon that counts**, not on the
  one recorded: take the proficiency feat away and the weapon stops occupying a
  hand, exactly as it stops adding an attack bonus.
  """
  @spec illegal_worn(Build.t(), map()) :: [{atom(), atom(), Worn.reason()}]
  defdelegate illegal_worn(build, ruleset), to: Worn, as: :illegal

  @doc """
  Every worn item the gear block may offer for `category_id`, with the reason a
  refused one is refused.

  ⚠ Refused items are **in** the list (CLAUDE.md §6, «недоступное показываем
  с причиной») — a Карлик has to learn that a tower shield is not his to wear, and
  a shortsword-and-shield build has to learn what a longsword would cost him.
  The order is the ruleset's own.
  """
  @spec worn_candidates(Build.t(), map(), atom()) ::
          [%{id: atom(), name: String.t() | nil, reasons: [Worn.reason()]}]
  def worn_candidates(%Build{} = build, ruleset, category_id) do
    case Worn.category(ruleset, category_id) do
      nil ->
        []

      category ->
        for item <- category.items do
          %{
            id: item.id,
            name: item.name,
            reasons: Worn.refusals(build, ruleset, category, item)
          }
        end
    end
  end

  @doc """
  Whether a feat may be **put in a slot** here: prerequisites, and the parameter.

  `validate_feat/3` answers "does the character qualify"; this adds the two
  questions a slot asks on top, and both of them are now data-driven:

    * has the character got it already? A feat is taken once — unless the data
      marks it repeatable, in which case it may be taken again **with a different
      value** (`Favored enemy` naming another creature type) or, where it names
      nothing at all, simply again (`Epic toughness`, ten times on an ordinary
      epic build). How many times it has been taken is `Build.feat_takes/3`.
    * is the value legal? It has to be in the domain's dictionary, unused by
      *this* feat, and — where the requirement block says so — matched by the
      feat it builds on (`Greater spell focus` in a school that already has
      `Spell focus`).

  `%{feat: id, choice: value, at: level, slot: slot_id}`; everything but `:feat`
  is optional. Pass `:slot` when the build already contains the pick being asked
  about, so it is not compared against itself.

  ⚠ The interface does not write choices yet, and until it does a choiceless pick
  of a repeatable feat is refused with `{:requires_choice, …}` rather than
  quietly allowed. That is the safe half of the contract to land first: a refusal
  is visible, an unrecorded duplicate is not (HANDOFF, «контракт из двух половин»).

  ## The one slot question asked here, and why only that one

  General slot bookkeeping is still **not** here: whether the slot exists on this
  level, whether it is free, whether its pool takes the feat at all
  (`FeatSlots.accepts?/3`, the picker). One exception —
  `FeatSlots.choice_refusals/4`, "this slot refuses the feat **with this value**",
  which is the rogue bonus slot's exclusion of `Epic skill focus` in `use magic
  device`. It is here because this is the only function that holds a slot and a
  choice at once, and it is the whole of the rule: `accepts?/3` cannot ask it
  (no choice) and `validate_feat/3` must not (no slot, and the same pair is legal
  in the general slot of the same level).
  """
  @spec validate_feat_pick(Build.t(), atom() | map(), map()) :: :ok | {:error, [term()]}
  def validate_feat_pick(%Build{} = build, feat_id, ruleset) when is_atom(feat_id) do
    validate_feat_pick(build, %{feat: feat_id}, ruleset)
  end

  def validate_feat_pick(%Build{} = build, pick, ruleset) when is_map(pick) do
    prereqs =
      case validate_feat(build, Map.take(pick, [:feat, :at, :choice]), ruleset) do
        :ok -> []
        {:error, reasons} -> reasons
      end

    slot = feat_pick_slot_refusals(pick, ruleset)

    # `uniq` because both halves answer `{:unknown_feat, id}` about a feat that is
    # not in the dictionary, and saying it twice reads as two faults.
    case Enum.uniq(slot ++ prereqs ++ FeatChoices.reasons(build, pick, ruleset)) do
      [] -> :ok
      reasons -> {:error, reasons}
    end
  end

  defp feat_pick_slot_refusals(pick, ruleset) do
    FeatSlots.choice_refusals(
      ruleset,
      Map.get(pick, :slot),
      Map.fetch!(pick, :feat),
      Map.get(pick, :choice)
    )
  end

  @doc """
  What a pick this core **allows** still owes the player — `[]` when nothing.

  `validate_feat_pick/3` answers whether the slot may be spent; this answers what
  spending it buys, for the one case where the honest answer is "nothing":
  `{:owned_from_gear, id}` — an item already lends this feat and the feat cannot be
  taken twice, so the slot changes no number. A slot spent for nothing is «реальная
  и дорогая ошибка, которую никто не ловит» (CLAUDE.md §6), and the whole reason
  the pick is allowed at all is that an item comes off while a slot does not — so
  refusing would be worse and silence would be worse.

  ⚠ **A caveat, not a refusal**, and a caller that folds it into a refusal list
  undoes the fix: the row stays available, with the sentence beside it. Wording is
  the web layer's; the twin advice about a class that hands the feat over later
  lives there too (`Builder.Feats.free_later/3`), because it needs a scan of levels
  the core has no reason to do.
  """
  @spec feat_pick_caveats(Build.t(), atom() | map(), map()) :: [GearFeats.caveat()]
  def feat_pick_caveats(%Build{} = build, feat_id, ruleset) when is_atom(feat_id),
    do: GearFeats.pick_caveats(build.gear, ruleset, feat_id)

  def feat_pick_caveats(%Build{} = build, pick, ruleset) when is_map(pick),
    do: feat_pick_caveats(build, Map.fetch!(pick, :feat), ruleset)

  @doc """
  What a feat will accept as its parameter here — the list the picker offers.

  `:no_choice`, `{:ok, values}`, `{:empty, reasons}` or `{:error, reasons}`; see
  `BuildCalculator.Rules.FeatChoices.candidates/3`. The narrowing is a game rule
  and belongs here rather than in the interface.

  ⚠ `{:ok, values}` is never an empty list. Nothing left to offer is
  `{:empty, reasons}`, and the reasons distinguish "everything this feat could
  take, it has taken" from "nothing qualifies yet" — one empty list for both is
  the bug this constructor exists to prevent.
  """
  @spec feat_choice_candidates(Build.t(), atom() | map(), map()) ::
          :no_choice | {:ok, [atom(), ...]} | {:empty, [term()]} | {:error, [term()]}
  def feat_choice_candidates(%Build{} = build, feat_id, ruleset) when is_atom(feat_id) do
    feat_choice_candidates(build, %{feat: feat_id}, ruleset)
  end

  def feat_choice_candidates(%Build{} = build, pick, ruleset) when is_map(pick) do
    FeatChoices.candidates(build, pick, ruleset)
  end

  @doc """
  The domain a feat's parameter is drawn from, or `nil` when it takes none.

  `:creature_type`, `:school`, `:weapon` — whatever the data names.
  """
  @spec feat_choice_domain(atom(), map()) :: atom() | nil
  defdelegate feat_choice_domain(feat_id, ruleset), to: FeatChoices, as: :domain

  @doc """
  Feats the class **hands over** on `level` that still owe a value, with what has
  been recorded for each.

  `Weapon of choice` is the one such grant in either ruleset: a Weapon Master is
  given it at his first class level and still names a weapon (Dan, 10.08.2026;
  task 3.26). A granted feat sits in no slot, so the value lives beside the picks
  — `Build.granted_choices` — and this is what the interface asks to know it owes
  a second step at all.

  See `BuildCalculator.Rules.FeatChoices.granted_choices_owed/3`; the offer list
  is `granted_feat_choice_candidates/4` and the check is
  `validate_granted_feat_choice/5`.
  """
  @spec granted_feat_choices_owed(Build.t(), map(), pos_integer()) ::
          [%{feat: atom(), domain: atom(), choice: term() | nil}]
  def granted_feat_choices_owed(%Build{} = build, ruleset, level),
    do: FeatChoices.granted_choices_owed(build, ruleset, level)

  @doc """
  What the feat granted on `level` will accept — the same four answers
  `feat_choice_candidates/3` gives, plus `{:error, [{:not_granted, feat}]}` for a
  feat this level does not hand over.

  See `BuildCalculator.Rules.FeatChoices.granted_candidates/4`.
  """
  @spec granted_feat_choice_candidates(Build.t(), map(), atom(), pos_integer()) ::
          :no_choice | {:ok, [atom(), ...]} | {:empty, [term()]} | {:error, [term()]}
  def granted_feat_choice_candidates(%Build{} = build, ruleset, feat_id, level),
    do: FeatChoices.granted_candidates(build, ruleset, feat_id, level)

  @doc """
  Whether recording `choice` for the feat granted on `level` is legal, and if not,
  why.

  ⚠ A grant checks its value as strictly as a slot pick does, and `Weapon of
  choice` is exactly why: its requirement is «[[weapon focus]] (chosen weapon)»,
  so the weapon the class hands the feat over with has to be a weapon the
  character has `Weapon focus` in. See
  `BuildCalculator.Rules.FeatChoices.validate_granted/5`.
  """
  @spec validate_granted_feat_choice(Build.t(), map(), atom(), atom(), pos_integer()) ::
          :ok | {:error, [FeatChoices.reason()]}
  def validate_granted_feat_choice(%Build{} = build, ruleset, feat_id, choice, level),
    do: FeatChoices.validate_granted(build, ruleset, feat_id, choice, level)

  @doc """
  What a feat declared off an **item** will accept — the same four answers
  `feat_choice_candidates/3` gives.

  The fourth route a value arrives by, after a slot, a class grant and an
  imported line (task 3.97, решение Dan 25.08.2026: «Подобный фит не может
  существовать без привязки к конкретному выбору»). Takes no level and asks
  nothing about the character: an item is worn whichever level is being looked
  at, and it is never checked against its own prerequisites. See
  `BuildCalculator.Rules.FeatChoices.gear_candidates/3`.
  """
  @spec gear_feat_choice_candidates(Build.t(), map(), atom()) ::
          :no_choice | {:ok, [atom(), ...]} | {:empty, [term()]} | {:error, [term()]}
  def gear_feat_choice_candidates(%Build{} = build, ruleset, feat_id),
    do: FeatChoices.gear_candidates(build, ruleset, feat_id)

  @doc """
  Whether declaring `feat_id` off an item **with** `choice` is legal, and if not,
  why.

  ⚠ A declaration that names **nothing** is legal — every link shared before
  task 3.97 says exactly that, and what it owes the reader is a gap rather than
  a refusal. See `BuildCalculator.Rules.FeatChoices.validate_gear/4`, and
  `validate_gear_feat/2` for whether the feat may be declared at all.
  """
  @spec validate_gear_feat_choice(Build.t(), map(), atom(), atom()) ::
          :ok | {:error, [FeatChoices.reason()]}
  def validate_gear_feat_choice(%Build{} = build, ruleset, feat_id, choice),
    do: FeatChoices.validate_gear(build, ruleset, feat_id, choice)

  @doc """
  Caveats on a feat that is otherwise legal — what was **not** checked.

  A requirement block may carry a refinement the schema cannot express: `[[spell
  focus]] **in the chosen spell school**`, "proficiency **with the chosen
  weapon**". The part that fits the schema is checked and `validate_feat/3`
  returns `:ok`; this returns what went unchecked, as the same machine-readable
  gaps `compute/2` puts in `stats.gaps`.

  ⚠ **A picker that offers the feat without showing these is worse than one that
  refused it.** Before the `qualifiers` key existed the whole phrase went to
  `unparsed` and the feat was honestly refused with "требования не разобраны";
  offering it silently would trade a visible refusal for an invisible guess,
  which is the one trade CLAUDE.md §9 forbids. So `validate_feat/3` and this
  belong together at every call site.

  Classes work the same way — `class_caveats/2`.
  """
  @spec feat_caveats(atom(), map()) :: [tuple()]
  def feat_caveats(feat_id, ruleset), do: Prereqs.qualifiers(Map.get(ruleset.feats, feat_id))

  @doc """
  The same for a class: what its requirement block says and the core did not check.

  Two of them today — Champion of Torm's "in a melee weapon" and Weapon Master's
  "(requires ride 1)".
  """
  @spec class_caveats(atom(), map()) :: [tuple()]
  def class_caveats(class_id, ruleset), do: Prereqs.qualifiers(Map.get(ruleset.classes, class_id))

  @doc """
  What taking `class` as the next level would change.

  `%{before: stats, after: stats}` — the caller diffs whichever fields it shows.
  Built out of `compute/2` twice on purpose (see the module doc).
  """
  @spec preview_level_up(Build.t(), atom(), map()) :: %{
          before: DerivedStats.t(),
          after: DerivedStats.t()
        }
  def preview_level_up(%Build{} = build, class, ruleset) do
    %{
      before: compute(build, ruleset),
      after: compute(Build.add_level(build, class), ruleset)
    }
  end

  @doc """
  Whether adding `value` to `class`'s choice is legal, and if not, why.

  Reasons are the same "structured, never text" tuples every other refusal in
  the core returns — see `BuildCalculator.Rules.ClassChoices`.
  """
  @spec validate_class_choice(Build.t(), atom(), atom(), map()) ::
          :ok | {:error, [ClassChoices.reason()]}
  defdelegate validate_class_choice(build, class_id, value, ruleset),
    to: ClassChoices,
    as: :validate
end
