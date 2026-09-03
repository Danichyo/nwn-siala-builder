defmodule BuildCalculator.Rules.Vocabulary do
  @moduledoc """
  Every shape the core speaks in — one example of each.

  The core answers in tuples and never in Russian (CLAUDE.md §8), so a tuple the
  web layer has no wording for renders through `inspect/1`. That is visible, and
  it is also exactly the failure nobody notices: six constructors lived like that
  until somebody happened to look at the screen.

  `ruleset.gaps` could always be walked, so the gaps *in the data* were covered by
  a test. The ones that only appear on **a particular build** — a caveat about a
  class this character took, a requirement that could not be checked — had no such
  list to walk, because there is no build to walk them off. This is that list.

      for gap <- Vocabulary.gaps(), do: refute Labels.gap(gap, ruleset) =~ ~r/^\\{/

  ## What the entries are

  Real, well-formed tuples with plausible ids in them — not patterns, not
  templates. A caller can pass one straight to a formatter, which is the whole
  point: a wording test wants something to word. Ids are chosen so the sentence
  they produce is worth reading (`:weapon_master`, `:spellcraft`), because they
  end up in test failure messages.

  Several entries may share a `form/1`; that is fine and sometimes wanted —
  `{:derived, :class_skills, …}` has two different sentences behind one form.

  ## What keeps it honest

  A registry that quietly falls behind the code is worse than no registry. Two
  checks in `test/build_calculator/rules/vocabulary_test.exs` keep it level:

    * every tuple **literal** in the rules core and the data loader whose head is
      one of `heads/0` or a `requires_*` reason must have its form registered;
    * every gap and every reason a **corpus of builds** actually produces —
      every class validated, every feat validated, both rulesets loaded — must
      have its form registered.

  The first catches a form that exists but nothing reaches yet; the second
  catches one built out of a variable, which the first cannot see.
  """

  @typedoc "One example of a machine-readable answer the core gives."
  @type entry :: tuple()

  # Heads whose **second element names the subject**: `{:missing_data, {:hit_die,
  # …}}` is about hit dice, `{:assumed, :base_ac, …}` about armour class, and each
  # subject needs its own sentence. Everything else — a refusal, and
  # `{:skill_over_cap, skill, …}`, whose second element is an id and not a
  # subject — is one form per head.
  @families ~w(missing_data not_modelled assumed derived conflict missing_file)a

  # Gap heads never used as a refusal, plus the ones that are. `:missing_data`
  # is deliberately in both lists further down: "we could not read this
  # requirement" is a reason to refuse *and* a gap in the model, and the web
  # layer words the two through different functions.
  @gaps [
    # -------------------------------------------------- the data, as loaded --
    {:missing_file, "vanilla/skills.json"},
    # ⚠ Пример остался с прежним классом СОЗНАТЕЛЬНО, но с 16.08.2026 он
    # больше не описывает состояние корпуса: задача 3.37 прочитала растущий
    # хит-дайс Ученика красного дракона, и ни один класс обоих ruleset'ов эту
    # форму не производит. Форма живёт, потому что живёт механизм — снапшот,
    # потерявший и `hit_die`, и `hit_die_by_class_level`, обязан сказать об
    # этом, а не считать HP по числу, которого никто не писал
    # (`Data.Loader.Gaps.gaps/14`, `Rules.Progression.hit_die/3`). Класс в примере
    # настоящий, чтобы `Labels.gap/2` было чем его назвать.
    {:missing_data, {:hit_die, :red_dragon_disciple}},
    {:missing_data, {:class_requirements, :weapon_master}},
    {:missing_data, {:requirement, :harper_scout, "spellcasting"}},
    {:missing_data, {:alignment_restriction, :monk}},
    {:missing_data, {:skill, :alchemy}},
    {:missing_data, :spell_lists},
    {:missing_data, {:stat_cap, :attack_bonus}},
    {:missing_data, {:stat_cap, :max_skill_value}},
    {:missing_data, {:stat_cap, :ac}},
    {:missing_data, :attack_ability_rules},
    {:missing_data, :point_buy_costs},
    {:missing_data, :caster_minimum_ability},
    # The hand-written casting file (`vanilla/spellcasting.json`) and the three
    # things it answers: the score a circle needs, which ability a class casts
    # off, and which prestige class lends its host slot-table levels.
    {:missing_data, :casting_ability_minimum},
    # Which casters are spontaneous, and therefore get the weaker reading of
    # «ability to cast Nth level spells» one sentence of `fandom:Spell focus`
    # grants them (task 3.124). Without the record nobody gets it, so a Bard 4
    # with charisma 11 is refused a feat the game hands him.
    {:missing_data, :spontaneous_casters},
    {:missing_data, {:casting_ability, :sorcerer}},
    {:missing_data, {:caster_advancement, :pale_master}},
    # ⚠ The **shape** of "the casting file records a rule it does not apply", and
    # today it stands for nothing: the one record it was written for — Fandom
    # stating a different prerequisite for the six epic spells than the one
    # printed in their own requirement line — was applied on 15.08.2026 (task
    # 3.31, `qualifying_class_levels`), and `spellcasting.json`'s `not_modelled`
    # list is empty. The form stays because the mechanism does: a record added
    # there tomorrow produces it again, and a shape with no wording is what this
    # module exists to prevent.
    #
    # ⚠ The example keeps the old id on purpose, and it costs one thing worth
    # naming: `Labels.gap/2` has a clause written for `:epic_spell_access`
    # specifically, and that clause is now unreachable — no build can produce it.
    # Changing the example here would only move the problem (the general clause
    # beside it words any other id), so this is left as a debt for the web layer
    # rather than half-fixed from the core.
    {:not_modelled, {:caster_advancement, :epic_spell_access}},
    {:missing_data, :max_classes},
    # «Дух Сиалы» (task, волна 12, 09.08.2026): a safety net for
    # `innate_hp_bonus/1` degrading silently to `nil`. ⚠ Unlike `max_classes`
    # above, never produced for vanilla — nil there is a confirmed fact (no
    # such mechanic in NWN1), not an open question — only for a broken
    # siala_41. See `Data.Loader`'s `gaps/14` and `Progression.hit_points/3`.
    {:missing_data, :innate_hp_bonus},
    # The shard's own racial bonus (task 3.12). **Two** forms today, and both are
    # about a build rather than about the corpus:
    #   * the shape is carried but the character is below the level the numbers
    #     are stated for, so nothing was counted;
    #   * it **was** counted, and by which of the four numbers the page states —
    #     the two that rest on a weapon in hand (the armoury) are never counted,
    #     and the two that do not are told apart by the variant inside the tuple.
    # ⚠ A race with no such bonus at all (Гоблин, Тёмный эльф) gets none of them:
    # a caveat about something that is not happening is noise.
    #
    # ⚠ **`{:missing_data, :racial_bonus_progression}` СНЯТА 22.08.2026**
    # (задача 3.81, решение Dan: «прогрессию делать не будем, данный пробел
    # можно закрыть»). Она была единственным здесь утверждением про КОРПУС —
    # «бонус растёт с уровнем, числа на вики только для 40-го, функции роста
    # не называет никто», — и закрылась продолжением решения Q2 от 15.08.2026:
    # ответ даётся на 40–41 уровне, значит прогрессия ниже перестала быть
    # дыркой в нашем ответе.
    # 🔴 **`{:missing_data, {:racial_bonus_level, race}}` НЕ снята и снята быть
    # не может:** билд ниже 40-го получает её по-прежнему, потому что бонус
    # в игре есть, а величины его не знает никто. Решение закрыло вопрос
    # «добудем ли мы таблицу», а не вопрос «посчитано ли это число».
    #
    # ⚠ **A fourth form stood here until 16.08.2026** — `{:not_modelled,
    # {:racial_bonus, race, kind}}`, for a bonus of a shape no number here carries
    # (Гном's damage resistance, Могучий человек's damage). Removed with task 3.38
    # by Dan's decision («мы это не показываем, оговорку игнорируем, не показываем
    # лишней информации»), which is CLAUDE.md §9's rule: a gap is a hole in our
    # ANSWER, not in our knowledge. `Rules.RacialBonus.gaps/2` no longer produces
    # it, nobody else ever did, and the two races now behave exactly like Гоблин
    # and Тёмный эльф above — silently. ⚠ The guard would not have caught a
    # leftover: it fails on a form without a Russian caption, not on a caption
    # without a producer.
    {:missing_data, {:racial_bonus_level, :half_elf}},
    {:assumed, {:racial_bonus_variant, :gnome, :base}},
    # The same system seen from the weapon's side (task 3.35,
    # `Rules.WeaponTypeBonus`): the shard gives a bonus for the **type of weapon
    # in hand**, and the two are added rather than merged (Dan's measurement,
    # `GAME_CHECKS.md` Q1). Four forms, one about the corpus and three about a
    # build, and each is a different sentence:
    #   * a weapon the page gives a bonus to and `weapons.json` does not carry at
    #     all («Вилы»): not a hole in a number, a hole in what can be expressed;
    #   * the page names the **type** of bonus and no number — a halberd's and a
    #     greataxe's shield armour class. Substituting the blade's 6/9 would be an
    #     invention: the one weapon of that section whose number is stated turned
    #     out to be an exception;
    #   * the number is known and the character is below the level it is stated
    #     for;
    #   * it **was** counted and the number of that variant is our reading of «он
    #     одинаковый для всех билдов» rather than the sentence itself.
    # ⚠ A shape with no receiver — damage, damage resistance, physical immunity —
    # produces **no** form at all, and deliberately: the calculator gives no
    # answer about damage, so it has no hole there (CLAUDE.md §9; Dan,
    # 16.08.2026). That is where this half differs from the racial one above.
    # ⚠ **`{:missing_data, :weapon_type_bonus_progression}` СНЯТА 22.08.2026**
    # тем же решением Dan (задача 3.81) и вместе с расовой половиной выше —
    # не по симметрии, а потому что это одно правило: `races.json` объявляет
    # каждый расовый бонус тождественным бонусу за тип оружия, и уровень
    # у обеих половин читается одинаково. Сказать про одно правило две разные
    # вещи было бы хуже, чем оставить обе.
    # 🔴 `{:missing_data, {:weapon_type_bonus_level, weapon}}` ниже НЕ снята:
    # билд ниже 40-го с оружием в руках получает её по-прежнему.
    {:missing_data, {:weapon_type_bonus_weapon, "Вилы"}},
    {:missing_data, {:weapon_type_bonus_amount, :halberd, :shield_ac}},
    {:missing_data, {:weapon_type_bonus_level, :longbow}},
    {:assumed, {:weapon_type_bonus_variant, :two_bladed_sword, :in_group}},
    # 🔴 И ОДИН И ТОТ ЖЕ вид бонуса от ОБЕИХ рук (задача 3.132). Первая половина
    # правила — цитата («Используя два разных оружия персонаж получает два
    # разных бонуса»), вторая — про два оружия ОДНОЙ группы, и про неё источник
    # молчит: вид посчитан один раз, а не дважды.
    #
    # 🔴 **НОСИТЕЛЕЙ У ФОРМЫ СЕГОДНЯ НОЛЬ, и это законно** — ровно как
    # у `{:assumed, :ac_bonus_types_unstated}` после задачи 3.90. Вторая
    # половина правила ПОДТВЕРЖДЕНА владельцем в тот же день, 28.08.2026
    # (`GAME_CHECKS.md` AH2: «если в руках два оружия одного типа - бонус
    # не удваивается»), и запись данных несёт отметку `same_kind_confirmed`.
    # Ни одно число при этом не сдвинулось: подтвердилось то, что считалось.
    #
    # ⚠ Форма живёт, потому что живёт МЕХАНИЗМ: отметка стоит на записи, а не
    # выключателем на коде, и снапшот, принёсший это правило без отметки, снова
    # получает оговорку. Живой её держит СИНТЕТИЧЕСКИЙ ruleset
    # (`DualWieldTest`, describe «подтверждение складывания»), а не живая
    # запись — контроль на живой назавтра получает отметку и молча перестаёт
    # что-либо проверять (урок задачи 3.85, пять контролей подряд).
    {:assumed, {:weapon_type_bonus_both_hands, :shield_ac}},
    # ---------------------------------------- бой двумя оружиями (задача 3.132) --
    # Таблицы штрафов в снапшоте нет вовсе — значит бой двумя оружиями посчитан
    # бесплатным. Умолчание направлено в сторону разговора: молча не вычесть
    # −6/−10 значило бы завысить AB обеим рукам.
    {:missing_data, :dual_wield_rules},
    # Лёгкое ли оружие во второй руке, сказать нечем (у оружия нет размера,
    # у персонажа нет расы, у снапшота нет лестницы) — и −2 обеим рукам поэтому
    # не сняты.
    {:missing_data, {:light_weapon, :unarmed_strike}},
    # 🔴 Выдача Рейнджера посчитана, а её условие по броне прочитать НЕЧЕМ:
    # класса брони (лёгкая / средняя / тяжёлая) нет ни в наших данных, ни в кэше
    # вики, а выводить его из `base_ac` запрещено (`GAME_CHECKS.md` AH1).
    # Печатается только там, где вопрос живой, — когда доспех записан.
    {:missing_data, {:armor_weight_class, :dual_wield_feat}},
    # The shard's groupings of classes a *build* can belong to (08.08.2026,
    # Dan: «сагровик получит больше бонусов, чем несагровик»). Membership itself
    # is computed and needs no caveat; these are the two things about a group
    # that are not known, and the two groups differ in exactly this:
    #   * whether purity is required — quoted and `verified` for Sagra, and for
    #     Adra nobody wrote it down at all, so Sagra's rule is applied and the
    #     assumption is declared rather than passed off as read;
    #   * what membership gives — listed for Sagra (potions, a whetstone, the
    #     weapon multiplier) and, for Adra, named by the owner rather than by any
    #     page (potions of Adra, Dan 25.08.2026).
    #
    # 🔴 **НИ ОДНА ИЗ ТРЁХ НЕ ИМЕЕТ СЕГОДНЯ НОСИТЕЛЯ** — задача 3.100
    # (25.08.2026), решение Dan: «для нашего конструктора и итоговых значений
    # принадлежность билда к Адре или нет ничего не меняет. Эта принадлежность
    # позволяет пить зелья адры, которые мы не моделируем, считай баффы».
    # Выгоды обеих групп — расходники и предметы, то есть механики, про которые
    # калькулятор не отвечает ничего; допущение про чистоту Адры двигает флажок,
    # а не число.
    #
    # ⚠ И ровно поэтому формы ОСТАЮТСЯ: снято признание, а не механизм. Каждое
    # из трёх молчаний стоит на записи в данных — на метке получателя у выгоды
    # и на решении владельца у чистоты, — и группа без такой записи вернёт свою
    # оговорку сама (`Rules.ClassGroups.gaps/2`, синтетический контроль
    # в `class_groups_test.exs`). Форма без носителя — не фикция; фикция — форма
    # без механизма.
    {:assumed, {:class_group_purity, :adra_warriors}},
    {:missing_data, {:class_group_benefits, :adra_warriors}},
    {:not_modelled, {:class_group_benefits, :sagra_warriors}},
    # ⚠ `{:not_modelled, :cleric_domains}` СНЯТА 22.08.2026 (задача 3.79,
    # решение Dan): «в конструкторе заклинания нас интересуют только те, что
    # надо выбирать при повышении уровня… домены клерика дают ему новые
    # заклинания, но выбирать их не надо, они выдаются автоматически». Все три
    # части пробела мимо нашего ответа — активные умения доменов это баффы,
    # пассивные считает не калькулятор, а заклинания домена выдаются сами.
    # ⚠ САМ выбор двух доменов при этом жив и остаётся моделью, и словарь это
    # показывает с двух сторон: `{:missing_data, {:choice_domain, …}}` ниже
    # в ЭТОМ списке (домен без словаря значений) и пара
    # `{:invalid_class_choice, …}` / `{:class_choice_full, …}` в `@reasons` —
    # отказы, которые выбор доменов отдаёт до сих пор. Снято признание,
    # а не механика.
    # ⚠ Специализация волшебника (задача 3.10) больше не значится здесь ни
    # одной формой, и обе ушли ЗАМЕРОМ или ОТВЕТОМ, а не вычёркиванием.
    # `{:assumed, :wizard_specialization_excludes_cantrips}` снята 09.08.2026
    # (Dan измерил: волшебник 1, INT 11, Conjuration → круг 0 показывает 3,
    # круг 1 показывает 2 — решение стало фактом).
    # `{:not_modelled, :wizard_opposed_school}` снята 24.08.2026 (задача 3.86):
    # она говорила, что выгода специализации посчитана, а цена — потеря
    # противоположной школы — нет. Цена теперь названа в самом месте выбора
    # («Illusion закрывает Enchantment — 20 заклинаний из 179»,
    # `Rules.Spells.specialization_costs/2`). Сам запрет каста по-прежнему
    # не проверяется, и это не долг: списка заклинаний волшебника в модели
    # нет вовсе, ни одного нашего числа он не двигает — гэп это дырка
    # в ОТВЕТЕ, а не в знаниях (CLAUDE.md §9).
    # Обе удалены, а не оставлены мёртвыми: сторож `vocabulary_test.exs`
    # («fiction») ловит именно зарегистрированную форму, которую никто
    # не производит.
    # ⚠ `{:not_modelled, :bonus_spell_slots_from_ability}` СНЯТА 21.08.2026
    # (задача 3.70): таблица со страницы `fandom:Ability modifier#Spellcasting`
    # перенесена в данные, слоты считаются. Форма удалена, а не оставлена
    # мёртвой — сторож «dead forms» ловит именно это. На её место встала
    # `{:missing_data, :bonus_spell_slots}` — то же утверждение, но проверяемое:
    # оно верно ровно тогда, когда таблицы в данных и правда нет.
    {:missing_data, :bonus_spell_slots},
    # ⚠ Since task 3.1 those bonuses **are** counted, and this form says only
    # what is left of the statement: the markup file
    # (`vanilla/feat_ability_bonuses.json`) states nothing applicable, so the
    # scores are short and nobody would otherwise know. It is emitted from the
    # finished dictionary rather than from the file's presence — a file that
    # arrived and applies to nothing is the same silence as no file.
    {:not_modelled, :ability_bonus_feats_and_class},
    # And the build-scoped half of the same subject: an ability the character
    # has that raises an ability score and cannot go into a permanent number —
    # a rage, a defensive stance, a feat that only grants the right to cast a
    # spell. Every one of them is switched **off** by default, which is the
    # same line `{:not_modelled, {:ac_bonus, …}}` draws for the very same
    # abilities; a raging barbarian and a standing one are not one character.
    {:not_modelled, {:ability_bonus, :barbarian_rage}},
    # ⚠ Одна форма `:item_attack_and_skill_bonuses` разделена на две 09.08.2026
    # (задача 3.20). Прибавки к навыкам с предметов стали полем ввода, то есть
    # половина прежнего утверждения перестала быть правдой, а печатать
    # «не считаем» про посчитанное запрещено так же прямо, как обратное
    # (CLAUDE.md §6). Осталось ровно то, что по-прежнему верно, и порознь: прямой
    # бонус к атаке с предмета (поля под него нет вовсе — атака получает вещи
    # только через характеристику) и штраф брони, чья величина зависит от
    # надетого доспеха.
    # ⚠ Renamed twice as it narrowed, never reworded in place: it was
    # `:item_attack_and_skill_bonuses` until task 3.20 gave skills their own item
    # field, and `:item_attack_bonus` until task 3.5 part B gave the weapon in hand
    # its two. What is left is what no field takes and none is planned to — an
    # attack bonus off anything other than the weapon, and the two cap fillers that
    # are not properties of a build at all (buffs, the bard song).
    # ⚠ Здесь стояла `{:not_modelled, :armor_check_penalty}` — «штраф брони не
    # считаем, он зависит от надетого доспеха». СНЯТА 16.08.2026 задачей 3.42:
    # надетое стало предметом (3.41), штраф считается термом значения навыка, а
    # форма без производителя — это фикция, которую сторож `vocabulary_test.exs`
    # («no registered form is fiction») и ловит. Оставить её мёртвой значило бы
    # учить читателя пролистывать этот список.
    {:not_modelled, {:unnamed_grant_rank, :barbarian, 15, :barbarian_rage}},
    {:conflict, {:class_skill, :purple_dragon_knight, :discipline, :class_page_only}},
    # Вторая форма того же рода и про тот же корпус: Fandom спорит сам с собой
    # о том, требует ли навык тренировки — лейбл страницы говорит одно, категория
    # другое. Своя голова, а не `class_skill`: там спор о том, ЧЕЙ навык
    # классовый, здесь — о свойстве самого навыка, и подпись у них разная.
    #
    # Форма завелась задачей 3.104 вместе с первым читателем признака
    # (`Rules.Prereqs`, `chosen_skill_ranks_if_trained_only`): до неё
    # `trained_only?` грузился и не решал ничего, а спор был безобиден.
    {:conflict, {:skill_trained_only, :perform, :category_only}},
    # Two sentences behind one form, and both are wanted: which one a ruleset
    # carries says whether the skill pages were read at all.
    {:derived, :class_skills, :union_of_class_and_skill_pages},
    {:derived, :class_skills, :from_class_skills_raw},
    {:assumed, :attacks_per_round_table, "fandom:Attacks per round"},
    # ⚠ Four elements, not three, since task 3.49 (18.08.2026): the citation is
    # the ruleset's own `constant_source/2` reading, not a second copy typed
    # here — see `Loader.Gaps`. `form/1` does not care about arity, so this did
    # not need to change for either registered form to keep matching what the
    # loader actually emits; it changed so the registry stops being a stale
    # example of a shape nothing produces any more.
    {:assumed, :base_ac, 10, "fandom:Armor class"},
    {:assumed, :ability_modifier_formula, "floor((score - 10) / 2)", "fandom:Ability modifier"},
    {:assumed, :hp_uses_maximum_hit_die_rolls},
    {:assumed, :skill_rank_caps_past_vanilla_cap},
    # The general feats a class takes off the list for its own levels
    # («These general feats cannot be selected when taking a level of bard»).
    # Two statements about it, and both are about the corpus: the shard's pages
    # say nothing on the subject at all, so the vanilla lists are carried over;
    # and a snapshot that carries no list makes the rule permit everything.
    {:assumed, :class_unavailable_feats_vanilla},
    {:missing_data, :class_unavailable_feats},
    # A feat the shard switched off where the shard's own record says the switch
    # was **inferred, not seen** (`"status": "assumed"`). Four of the eight
    # vanilla weapon proficiencies are like that: each is handed over by exactly
    # one class, and a granted feat is never printed in the pick list, so no
    # observation in game can tell "off" from "given" (`GAME_CHECKS.md` H5).
    # ⚠ The measured four produce nothing — see `Loader.Gaps.assumed_disabled_gaps/1`.
    {:assumed, {:feat_disabled, :weapon_proficiency_monk}},
    # A feat that may be taken more than once, each time with a different value.
    # `distinct` defaults to true because that is what this family's pages say;
    # `Epic energy resistance` is the counter-example and needs the data to say
    # so. See `BuildCalculator.Data.Loader.repeatable/1`.
    {:assumed, :repeatable_choices_must_differ},
    {:missing_data, {:feat_repeatable, :favored_enemy}},
    {:missing_data, {:choice_domain, :weapon}},
    # How many times a feat that repeats **the same thing** may be taken. Every
    # page in that family names a ceiling and almost none names it in takes
    # («up to a maximum of 200 hit points»), the feat's own effect is not
    # modelled, and dividing one by the other would invent a number. So the
    # count goes unchecked and says so. See `BuildCalculator.Rules.FeatChoices`.
    {:missing_data, {:feat_max_takes, :epic_toughness}},
    # A feat that adds to a **named skill** and whose bonus cannot go into the
    # number honestly — conditional on where the character stands, or with no
    # number on the page at all (`vanilla/feat_skill_bonuses.json`, verdict
    # `not_modelled`). Distinct from `{:not_modelled, {:feat_bonus, …}}`, which is
    # about a *build* and about a repeatable feat's own effect; this one is about
    # the corpus, and it is only emitted where the other cannot reach.
    {:not_modelled, {:feat_skill_bonus, :trackless_step}},
    # The same for hit points (`vanilla/feat_hp_bonuses.json`, verdict
    # `not_modelled`) — and unlike the skill one this is build-scoped, because
    # what it qualifies is a single number the build shows.
    #
    # ⚠ Here stood two examples, `Deathless vigor` and `Hit die increase`, and
    # both have since been counted (D1 on 13.08.2026, task 3.37 on
    # 16.08.2026 — the growing die belongs to the **class**, not the feat), so
    # the file's `not_modelled` bucket is empty and no build produces this
    # today. The form stays for the same reason the one above it does: the
    # mechanism is live, and a record added there tomorrow brings it back.
    {:not_modelled, {:feat_hp_bonus, :deathless_vigor}},
    # Armour class from the build itself (`vanilla/ac_bonuses.json`, task
    # 3.11). Four forms and four different statements, which is why they are
    # not one:
    #   * an ability that raises AC and cannot go into a permanent number — a
    #     combat mode, an ability used so many times a day, a bonus against one
    #     kind of enemy. Build-scoped: only the abilities this character has.
    #   * a bonus that **is** counted and that the game takes away under a
    #     condition we cannot see (a Monk in armour) — the Spellcraft
    #     precedent, and the same shape as `{:not_modelled, {:save_bonus_scope,
    #     …}}` beside it.
    #   * at least one counted bonus whose source names no type, so nothing
    #     stops it stacking and nothing clips it.
    #   * a type on which a bonus of the build's met a number the player typed:
    #     the rule is applied (the larger wins, task 3.39), but the **base**
    #     armour class of the item, which always stacks, cannot be told apart
    #     from the bonus inside one typed number, so the number may be low by
    #     it. ⚠ Here stood `{:not_modelled, :ac_same_type_stacking}` —
    #     «одинаковые типы мы складываем, а игра не складывает» — and it is
    #     gone rather than renamed: own against own **does** add up (measured,
    #     `GAME_CHECKS.md` E5) and own against typed is a rule now. What is left
    #     is smaller and says so in its own words.
    #
    #     ⚠ **The example is `natural` and used to be `shield`** (task 3.41).
    #     Armour and shields are items with a size now, so their base is known
    #     and they carry no caveat at all — an example naming a type that can no
    #     longer produce it would be a form nobody can reach, and the vocabulary
    #     is read as a list of what the core actually says.
    {:not_modelled, {:ac_bonus, :defensive_stance}},
    {:not_modelled, {:ac_bonus_scope, :monk_ac_bonus}},
    #
    #     ⚠ `:ac_bonus_types_unstated` has **no carriers today** (task 3.90,
    #     25.08.2026) and stays for the same reason `:ac_bonus_scope` does:
    #     the four untyped records each carry a `stacking_confirmed` mark now,
    #     and the next untyped bonus off the wiki will arrive without one. Zero
    #     carriers is a state, not a dead form — a synthetic record in
    #     `armor_class_test.exs` keeps it reachable, deliberately not a live one.
    {:assumed, :ac_bonus_types_unstated},
    {:not_modelled, {:ac_gear_base, :natural}},
    # Saving throws from the build itself (`vanilla/feat_save_bonuses.json`,
    # task 1.12a) — one form, the same shape `{:not_modelled, {:ac_bonus, …}}`
    # already has: an ability that raises Fort/Ref/Will and cannot go into a
    # permanent number, because it is switched off by default (`barbarian_rage`
    # already carries this id under `:class_change` and `:ac_bonus` too — a
    # third, narrower statement about the same ability is not a duplicate of
    # either, see `rules.ex`'s `own_save_bonus_gaps/3`) or because the source
    # is precise about a threat it does *not* cover (poison, fear, a chosen
    # school) and a flat number would overstate the save against everything
    # else.
    {:not_modelled, {:save_bonus, :barbarian_rage}},
    # The attack roll from the build itself (`vanilla/feat_attack_bonuses.json`,
    # task 1.12b) — **two** forms where the three stats above need one, and the
    # split is not cosmetic:
    #   * the familiar half — an ability that raises the attack roll and cannot
    #     go into a permanent number: a combat mode (`Expertise` trades −5
    #     attack for +5 AC), a once-a-day activation, a bonus narrow to one kind
    #     of enemy or one patch of terrain. Nothing short of modelling a fight
    #     would make these countable.
    #   * the weapon half — `Weapon focus`, `Epic weapon focus` and the Weapon
    #     Master's own «AB bonus» column are plain unconditional numbers *once
    #     you know what is in the character's hands*, and the armoury (task 3.5)
    #     is what will know. This one is a statement about the calculator, not
    #     about the game, and wording it like the other would either promise a
    #     fight simulator or bury a to-do. Full argument in the data file's
    #     `_weapon_decision`.
    {:not_modelled, {:attack_bonus, :expertise}},
    {:not_modelled, {:attack_bonus_weapon, :weapon_focus}},
    # Сопротивление заклинаниям (`vanilla/feat_spell_resistance.json`, задача
    # 3.45) — две формы, и они про разное.
    #
    # Первая — та же, что у пяти статов выше: источник SR, который персонаж
    # держит, а модель считать отказывается. ⚠ Сегодня её не производит ни один
    # билд, потому что в данных нет ни одной записи с вердиктом `not_modelled`:
    # сплошная разведка нашла ровно два источника SR, и оба посчитаны. Форма
    # стоит здесь ровно на тех же правах, что `{:not_modelled, {:feat_hp_bonus,
    # …}}` рядом, — механизм жив, и запись, добавленная в файл завтра, придёт
    # к игроку подписанной, а не сырым таплом.
    {:not_modelled, {:spell_resistance, :diamond_soul}},
    #
    # 🔴 Вторая — про предметы, и она обязана быть, потому что стоит дороже, чем
    # у прочих статов: у всех остальных вещь ПРИБАВЛЯЕТ, и непосчитанная вещь
    # делает наше число нижней границей. SR из разных источников
    # **не складывается** — засчитывается наибольший, — а крафт Сиалы доходит
    # до «28 СР» при нашем 22 у монаха 12. То есть до монаха 17 включительно
    # предмет наше число ПЕРЕБИВАЕТ, и правило это игрок из остальной панели
    # не выведет. Считать мы всё равно не можем (поля под ввод Dan заводить
    # не велел, каталога предметов у нас нет), поэтому оговорка называет
    # правило, а не величину — та же роль, что у
    # `{:not_modelled, :attack_bonus_outside_weapon}`.
    #
    # ⚠ Появляется только у билда, у которого SR есть: оговорка про вопрос,
    # который не возникает, — шум.
    {:not_modelled, :spell_resistance_from_gear},
    # Which side of a +20 ceiling an addend falls on, where nobody wrote it down
    # (09.08.2026). **Two forms, because the data answers at two levels**: a
    # mechanism of `compute/2` (gear, the shard's racial bonus, a skill rule) is
    # classified per kind, and everything with a record in the bonus markup states
    # its own side — `Divine grace` and `Sacred defense` are both class abilities
    # in the shape of a feat and Dan put them on opposite sides, which is what
    # makes the record and not the kind the unit of the answer.
    #
    # ⚠ Neither form is produced by any build today, and both are registered on
    # purpose. Three records were `assumed` for a few hours on 09.08.2026 —
    # `Small stature`, `Lucky`, `Dark blessing` — and the owner's list settled all
    # three; the shapes stay so that the next unstated side is a printed caveat
    # rather than a silent choice.
    {:assumed, {:cap_covers_source, :attack_bonus, :gear}},
    {:assumed, {:cap_covers_entry, :saving_throw_bonus, :lucky}},
    # The repetition rule itself is a guess somebody marked as one: Дан answered
    # «не знаю, предполагаю» about two of the eight feats in
    # `siala_41/feats.json` and the data keeps `status: "unclear"`. The rule is
    # applied — no page says the feat is single-take either — and this is what
    # stops an applied guess from reading as an observation.
    {:assumed, {:feat_repeatable, :resist_energy}},
    # ----------------------------------------------------- this build alone --
    # ⚠ The example moved twice, and both moves are the same failure being
    # avoided — an example that can no longer be produced.
    #
    #   * 09.08.2026, `"instinctive_throw"` → `"instinctive_throw_usable_from"`:
    #     Dan measured that the Monk **is** handed the ability on class level 5,
    #     so the hand-out is applied and naming it would say "not applied" about
    #     something applied.
    #   * 10.08.2026, `"instinctive_throw_usable_from"` → `"weapon_bab_exceptions"`
    #     (task 3.28): that key is labelled `affects: ["special_ability"]`, i.e. a
    #     receiver the calculator never prints, so `Rules.GapReceivers` filters it
    #     out and no build can produce it. `weapon_bab_exceptions` is the Monk's
    #     surviving one.
    #
    #   * 13.08.2026, `{:monk, "weapon_bab_exceptions"}` → `{:rogue,
    #     "stealth_perception_penalty"}`: two measurements on the same day took
    #     the Monk out of this form entirely. First his shown attack bonus turned
    #     out identical unarmed, with a quarterstaff and with a longsword
    #     (GAME_CHECKS.md, L2), striking `bab` and `attack_bonus`; then the page's
    #     riddle of a sentence turned out to be about *Flurry of blows* (works
    #     unarmed and with a staff, not with a sword — L2b), which is an activated
    #     mode, so Dan called it a buff. **The Monk now carries no fact with an
    #     `our` receiver at all** — the first class to run out.
    #
    # The rule this history is here to enforce: an example must be a form some
    # build can still produce, and every move above was one measurement making the
    # previous example unproducible.
    #
    #   * 17.08.2026, `{:rogue, "stealth_perception_penalty"}` →
    #     `{:weapon_master, "attack_bonus_progression"}`: ровно то, что абзац
    #     выше предсказывал вслух. Три записи двух файлов несли ОДНО
    #     предложение источника про штраф вора в режиме скрытности; две
    #     (`listen`/`spot`) стали `buff` утром, третья — тем же днём, когда
    #     решение Dan показали на ней самой («если штрафы вору идут только
    #     в режиме хайда, то мы их не показываем»). Форма осталась живой —
    #     девять классовых фактов дают её сегодня.
    #
    # ⚠ Новый пример выбран не «любой из девяти», а самый устойчивый к тому же
    # виду устаревания: прибавка к атаке Мастера оружия — ПОСТОЯННАЯ прогрессия
    # класса, то есть уехать под баффы по построению не может, в отличие от
    # активируемых умений, которые унесли отсюда два прежних примера подряд.
    {:not_modelled, {:class_change, :weapon_master, "attack_bonus_progression"}},
    # ⚠ `:divine_might` → `:improved_evasion`, 14.08.2026 (task "фиты: получатели
    # у фактов"), the `:feat_change` form's own turn at the same failure. All
    # eighteen feats that carried `siala_unapplied` now carry `affects`
    # (`Mix.Tasks.Wiki.Parse`'s `@feat_fact_affects`), and seventeen of them —
    # `Divine might` included — turned out entirely `not_our`: a build that
    # takes Divine might no longer produces this tuple at all. `Improved
    # evasion` is the one survivor.
    #
    # ⚠ It survived a second time on 14.08.2026, when the reason it survived the
    # first time was fixed. The Rogue's «может взять с 35-го уровня» became a
    # requirement rather than a hand-out (`siala_41/feats.json`,
    # `requirement_class_level`); what stayed unread was the *consequence* of
    # the Monk and Shadowdancer hand-outs moving to 30 and 25 while the
    # requirement branches that mirrored their vanilla levels stayed at 9 and 10
    # — inert in vanilla, live on the shard, and nobody had written down whether
    # they moved.
    #
    # ⚠ **On 17.08.2026 it stopped being producible, and the entry stays anyway
    # — the third time this list keeps a form whose example a build can no
    # longer make.** H9 measured the branches (Dan, 16.08.2026), all three moved,
    # and Dan closed the gap itself: «правила железные и измеряны». **No feat
    # fact in either ruleset now names a receiver we print**, so the *form* is
    # reachable only from `Data.Loader`'s literal — which is exactly what the
    # "no registered form is fiction" test accepts and why it accepts it. The
    # mechanism is untouched: tag one feat fact `hp` tomorrow and the form comes
    # back on its own, and it must have wording waiting when it does.
    #
    # ⚠ The rule stated at `:class_change` above — «an example must be a form
    # some build can still produce» — is therefore **not** a rule about this
    # list; it is a rule about how hard one should try before giving up on a
    # live example. Here there is nothing to move to: the alternative is a made
    # up feat id, which would be worse than a real id nobody reaches.
    {:not_modelled, {:feat_change, :improved_evasion, "siala_note"}},
    {:not_modelled, {:skill_change, :spellcraft, "save_bonus"}},
    {:not_modelled, {:save_bonus_scope, :spellcraft}},
    {:not_modelled, {:feat_qualifier, :spell_focus, "in the chosen spell school"}},
    # ⚠️ Пример сменил класс 25.08.2026 (задача 3.99): у Мастера оружия
    # оговорки больше нет — «in a melee weapon» стало проверяемым требованием
    # (`feat_choice_properties`). Форма жива и обязана быть жива: её несут
    # ванильные Тайный лучник и Пурпурный рыцарь, и её вернёт первая же
    # страница класса, чью приписку схема не выразит.
    {:not_modelled, {:class_qualifier, :purple_dragon_knight, "(requires ride 1)"}},
    # ⚠ Здесь стояла форма `{:not_modelled, {:extra_attacks, :arcane_archer}}` —
    # «доп. атаки Тайного лучника не посчитаны: условия лежат прозой». Снята
    # задачей 3.72 вместе с самой прозой: условия стали записями данных, ядро их
    # читает (`Rules.AttackModifiers`), а условие, которое ядро прочитать не
    # умеет, теперь роняет сборку вместо того, чтобы становиться оговоркой.
    # Оговорки нет, потому что нет и дырки в ответе.
    # A feat declared as coming from an **item** (task 3.3, `Rules.GearFeats`).
    # One form, and the narrow one: the feat's effect *is* counted (Dan,
    # 09.08.2026 — «если фит есть, допустим тафнес, то и HP будут увеличены»), so
    # there is nothing to confess about it. What a declaration may fail to say is
    # which value the feat was granted with.
    #
    # ⚠ Здесь стояло, что голое объявление «clears `Greater spell focus`'s
    # `feats:` requirement and not its `same_choice_as`» — это описывало модель
    # ДО замера H7 (14.08.2026) и снято в `Rules.GearFeats` ещё тогда: фит
    # с вещи не открывает пререквизит другого фита вовсе, ни с названным
    # значением, ни без. Оговорка не про требования — она про число.
    #
    # ⚠ Носителей у формы **пять**, а не пятнадцать (задача 3.98): значение
    # называется только там, где оно стоит нашего числа — `Skill focus`,
    # `Epic skill focus`, `Weapon focus`, `Epic weapon focus`, `Weapon of
    # choice`. Форма при этом остаётся здесь при любом их числе: её вернёт
    # первый же фит с доменом, у которого нет метки получателя.
    {:not_modelled, {:gear_feat_choice, :weapon_focus}},
    # The weapon in the character's hands (task 3.5 part B, `Rules.GearWeapon`).
    # Three forms, and each is about a statement somebody did not make — none of
    # them about the numbers, which the player types and the model simply adds:
    #   * the proficiency category is **ours**: Siala replaced the vanilla weapon
    #     proficiency system with five of its own and names the members only in
    #     Russian prose, so 31 of the 47 assignments are `assumed` (Dan, 10.08.2026:
    #     «пока допущение с гэпом, точный маппинг в вопросы ко мне сохрани»);
    #   * nobody wrote the requirement down at all — the club is in none of the five
    #     categories, and that is **not** the same statement as the staff's "needs
    #     none". Such a weapon is offered and says this.
    #
    # ⚠ A third form stood here until task 3.52: `{:assumed, :weapon_bonuses_stack}`,
    # «the item's two numbers are added and no page says they stack». The item has
    # one number now, so the question is gone rather than unanswered — the one kind
    # of caveat that may be dropped without losing anything.
    {:assumed, {:weapon_proficiency_group, :scimitar, :blade}},
    {:missing_data, {:weapon_proficiency, :club}},
    # How a weapon is held, when nobody said and nothing can be derived (task
    # 3.43, `Rules.Wield`). Build-scoped and scoped tighter still: the caveat is
    # about a **shield** that is being counted while it is unknown whether the
    # weapon in the other hand leaves a hand free. Exactly one entry in the
    # dictionary reaches it — the unarmed strike, which states no grip on Siala's
    # table and no size on Fandom's — and only beside something worn in the off
    # hand. See `Rules.Worn.gaps/2`.
    {:missing_data, {:weapon_grip, :unarmed_strike}},
    # And the corpus-scoped half: a snapshot whose `weapons.json` states no size
    # ladder cannot answer any of it — not the grip, not «too large to wield»,
    # not the shield. `nil` everywhere rather than «allowed», and this is what
    # says so. Produced by no shipped ruleset; the loader refuses a **half**
    # stated block outright, so this is the whole-block case alone.
    {:missing_data, :weapon_size_rules},
    # The effect of a feat taken with a parameter — Favored Enemy's +1 rising to
    # +9 with the class level. Recorded, never counted.
    {:not_modelled, {:feat_bonus, :favored_enemy}},
    {:missing_data, {:class_progression, :red_dragon_disciple, 31}},
    # ⚠ Обе формы ниже с 17.08.2026 не производит ни один ruleset: Dan ответил
    # на кейс P1 сразу про оба поля Алхимии («ее атрибут - мудрость» и «Штрафа
    # нет»), а другого навыка без ключевой характеристики или с непрочитанным
    # штрафом в корпусе нет — ни у Сиалы, ни у ванили. Это тот же случай, что
    # у `{:missing_data, {:hit_die, …}}` выше: форма живёт, потому что живёт
    # механизм — навык шарда без ванильной основы приходит без обоих полей, —
    # и `Rules.Skills` обязан сказать об этом, а не подставить ноль. Проверяется
    # копией `priv/rules`, из которой поле вынуто (`skills_test.exs`).
    # ⚠ Навык в примере настоящий, чтобы `Labels.gap/2` было чем его назвать:
    # синтетический id напечатался бы сырым атомом посреди русской фразы.
    {:missing_data, {:skill_key_ability, :alchemy}},
    # Второе слагаемое того же навыка (задача 3.42): отнимает ли у него доспех.
    # ⚠ Отдельная форма, а не «значение не собралось»: у неё своё предложение
    # («не сказано, отнимает ли») и своя область — она появляется, только пока
    # надето что-то штрафующее, тогда как характеристика неизвестна всегда.
    {:missing_data, {:skill_armor_check_penalty, :alchemy}},
    {:missing_data, {:feat_prerequisites, :epic_dodge}},
    {:missing_data, {:caster_level, 3}},
    {:missing_data, {:prerequisite, :save_bonus}},
    {:missing_data, :alignment_requirement},
    # ⚠ **Сузилось 17.08.2026** (замер S10): оружие, которым `Weapon Finesse`
    # работает, обе вики перечисляют поимённо, и билд, назвавший оружие,
    # получает проверенный ответ без единой оговорки. Форма осталась ровно для
    # того случая, где проверять нечего, — оружие не названо вовсе. Раньше она
    # стояла на КАЖДОМ билде, где правило сработало, включая тот, что держал
    # в руках двуручный меч.
    {:assumed, :finessable_weapon},
    # The other feat that changes the attack **formula** (`Rules.Attack`), and the
    # one thing its answer can lack: `Zen archery` computes the attack off wisdom
    # only «when firing ranged weapons», and a build that named no weapon has not
    # said whether it does. ⚠ Deliberately **not** the shape Finesse's caveat has,
    # and the difference is what each rule does with the same silence: Finesse
    # covers the unarmed strike, so it fires anyway and pays with the assumption
    # above, while this one needs a bow nobody mentioned and stays quiet. The
    # ruleset-wide `{:not_modelled, :zen_archery}` this replaces said the feat was
    # not modelled at all, which stopped being true on 14.08.2026.
    {:not_modelled, {:attack_ability_weapon, :zen_archery}},
    # And the same missing statement one level below the feats (task 3.34,
    # 15.08.2026): which ability the attack comes off **before** any feat is a
    # property of the weapon in hand too — ranged attacks come off dexterity —
    # so a build that named no weapon was answered with the melee fallback.
    # ⚠ A form of its own rather than the one above, because the sentence is
    # different: that one says a feat you own did not fire, this one says the
    # baseline itself is a guess. The subject is the weapon **property** whose
    # default went unapplied, read out of the ruleset, so no ability is named
    # here or in the web layer.
    {:not_modelled, {:attack_ability_default, :ranged}},
    {:assumed, :skill_points_ignore_gear_intelligence},
    {:skill_over_cap, :discipline, 5, 9, 8},
    {:unknown_class, :not_a_class}
  ]

  # Why a level, a class or a feat may not be taken — and, at the end of the list,
  # what a pick the core **does** allow still owes the player. Same tuples
  # `validate_level_up/3`, `validate_feat/3`, `Prereqs.check/2` and
  # `feat_pick_caveats/3` return.
  #
  # The `:missing_data` entries are here on purpose: a requirement the parser
  # could not read refuses the thing *and* is a hole in the model, and the web
  # layer words a refusal through a different function than a gap. A form worded
  # as one and not the other is exactly the case this list exists to catch.
  @reasons [
    {:unknown_class, :not_a_class},
    {:unknown_feat, :not_a_feat},
    # Not a prerequisite and not a property of the feat: the class whose level is
    # being taken keeps this feat off the general feat list, and the very same
    # feat is fine on a level of another class. See `Rules.FeatSlots`.
    {:forbidden_by_class, :fighter},
    # The third refusal of that family, and neither of the other two says it: the
    # shard's «Умение нельзя выбрать при росте персонажа» (`Riding Sprint`, `Smile
    # of Death`). The feat is not switched off — it works, and a declaration under
    # «Вещи» is legal for it — and no class is at fault either: no level-up of any
    # class offers it. Until 09.08.2026 the refusal existed only as a side effect
    # of the feat's `type`, and `validate_feat/3` answered `:ok` about a feat every
    # slot refused.
    {:not_selectable_at_level_up, :riding_sprint},
    {:level_cap, 41},
    {:max_classes, 4},
    {:class_level_cap, :weapon_master, 10},
    {:feat_disabled, :devastating_critical},
    # Why a weapon may not be the one in the character's hands (task 3.5 part B).
    # `{:requires_feat, …}` is the third and it is reused from above deliberately:
    # «нужен фит владения клинковым» is the same sentence as any other missing feat,
    # and a second form for it would only differ in where it was produced.
    {:unknown_weapon, :not_a_weapon},
    {:not_wieldable, :creature_weapon},
    # Предмет обычный, но на шарде его нет вовсе (наблюдение Dan 16.08.2026:
    # лэнс). ⚠ Своя форма, а не `:not_wieldable`: та говорит «это вообще
    # не предмет», и подменить одну другой значит напечатать неверную причину.
    {:not_on_shard, :lance},
    # Оружие крупнее владельца больше чем на категорию — «cannot be wielded at
    # all», а НЕ «двуручно» (задача 3.43, `Rules.Wield`). Своя форма именно
    # поэтому: `{:not_wieldable, …}` рядом говорит «это вообще не предмет», и
    # склеить их значило бы сказать Карлику про великий меч, что меча не бывает.
    {:weapon_too_large, :gnome},
    # Нижняя половина того же предложения источника («down to two sizes
    # smaller»). На поставляемых данных её не производит никто: ступеней четыре,
    # играбельных размеров два, и ничего мельче двух категорий от владельца
    # в справочнике нет. Заведена всё равно — отказ, который нечем назвать, хуже
    # отказа, который не срабатывает, а лестница лежит в данных и может вырасти.
    {:weapon_too_small, :half_orc},
    # И два отказа НАДЕТОМУ (`Rules.Worn`), оба про щит и оба цитатой с
    # `fandom:Shield proficiency`. Раздельно, потому что это два независимых
    # утверждения: одно про расу («gnomes and halflings may not use tower
    # shields»), другое про то, что в руках («Creatures may not simultaneously
    # use a shield and a two-handed weapon»), и билд может нарушить оба разом.
    {:not_usable_by_race, :gnome},
    {:two_handed_weapon, :longsword},
    # 🔴 И ТРЕТИЙ отказ надетому — вторая рука занята ВТОРЫМ ОРУЖИЕМ, а не
    # хватом (задача 3.132, решение Dan 28.08.2026: щит и второе оружие
    # одновременно взять нельзя). Своя форма именно потому, что фраза обязана
    # быть другой: «занята двуручным оружием» и «занята вторым оружием» —
    # разные факты об одной руке, и по каждому игрок идёт менять своё.
    {:off_hand_weapon, :shortsword},
    # И зеркальный отказ САМОМУ второму оружию: двуручным оружием вторую руку
    # не занять. ⚠ Не `{:two_handed_weapon, …}` рядом: та говорит «рука занята
    # ЧУЖИМ предметом», а эта — «этот предмет туда не кладут», и обвиняемый
    # предмет у них разный.
    {:two_handed_in_off_hand, :greatsword},
    # 🔴 И ЕЩЁ ДВА про ту же руку — но не про хват, а про СВОЙСТВО оружия
    # (задача 3.142, `fandom:Ranged weapon`: «No ranged weapon may be wielded in
    # the off-hand slot, nor can any weapon be wielded in the off-hand when a
    # ranged weapon is in the main hand»). Формы раздельные по той же причине,
    # что и пара выше: одна говорит «этот предмет туда не кладут», другая —
    # «рука занята тем, что в главной», и обвиняемый предмет у них разный.
    #
    # ⚠ И ни одна из них не равна паре про хват: та отбирает ВЕСЬ слот, вместе
    # со щитом, а эта — только оружие. Щит лучника с пращой остаётся (замер Dan
    # 30.08.2026, `GAME_CHECKS.md` AI2), и фраза обязана это различать.
    {:ranged_in_off_hand, :sling},
    {:ranged_in_main_hand, :sling},
    {:requires_character_level, 21},
    {:max_character_level, 1},
    {:requires_bab, 7},
    {:requires_race, [:dwarf]},
    {:requires_feat, :dodge},
    # Фит есть, а взят не с тем значением: Тайному лучнику нужен `Weapon focus`
    # ровно в одном из четырёх дальнобойных (`Rules.Prereqs`, ключ
    # `feat_choices`). Своя голова, а не `{:requires_feat, …}`: тот говорит
    # «возьми фит» тому, у кого фит уже есть, и игрок ищет несуществующую
    # строчку в списке. Разные подсказки — разные формы.
    {:requires_feat_choice, :weapon_focus, [:longbow, :shortbow]},
    {:requires_skill_ranks, :hide, 8},
    {:requires_class_level, :bard, 1},
    {:requires_ability, :str, 13},
    {:requires_alignment, %{require: ["lawful"]}},
    {:requires_spell_level, 4},
    {:requires_save_bonus, :fort, 8},
    {:requires_any_skill_ranks, 20},
    {:requires_any_of,
     [[{:requires_race, [:dwarf]}], [{:requires_class_level, :pale_master, 3}]]},
    # A feat and the value it is taken with (`BuildCalculator.Rules.FeatChoices`).
    # `already_taken` reaches the core for the first time here: whether a feat may
    # be taken twice used to be a constant and is now a property of the data, so
    # the answer had to move where the data is read. The feat picker has its own
    # wording for it and keeps it.
    {:already_taken, :power_attack},
    # A value offered for a feat this level does **not** hand over
    # (`FeatChoices.granted_reasons/5`, task 3.26). Its own head rather than
    # `already_taken`'s: the two are opposites — "the character has it" against
    # "the class does not give it here" — and a hand-edited link is the only way
    # to reach it, which is precisely when a wordless tuple would show.
    {:not_granted, :weapon_of_choice},
    {:choice_already_taken, :favored_enemy, :goblinoid},
    # A feat that repeats the same thing, taken as many times as the data says it
    # may be. Only ever produced against a ceiling `priv/rules/` states outright —
    # where none is stated the pick is allowed and the gap above is recorded.
    {:max_takes, :epic_damage_reduction, 3},
    # "20 ranks in **the chosen skill**": the requirement is about the value the
    # feat was taken with, so it can only be checked once a pick names one. The
    # unbound form beside it (`requires_any_skill_ranks`) is what a pick that
    # names nothing still gets.
    {:requires_chosen_skill_ranks, :tumble, 20},
    # «[[weapon focus]] in a [[melee weapon]]» — требование к значению, названное
    # его СВОЙСТВОМ. Своя форма рядом с `requires_feat_choice`, а не список
    # из 39 имён оружия в нём: подсказка «возьми фокус в ближнем оружии» —
    # действие, а перечисление словаря — шум, и оно устаревает молча.
    {:requires_feat_choice_property, :weapon_focus, :ranged, false},
    # Третья и последняя форма про то же значение, с обратной полярностью:
    # «этот фокус требованию не годится». Источник называет значение ПОИМЁННО
    # («this focus does not satisfy the "weapon focus in a melee ''weapon''"
    # requirement», `fandom:Unarmed strike`), и подсказка обязана назвать его
    # тоже: у игрока фит взят, и без имени он не поймёт, чем именно не тем.
    # Своя голова, а не `requires_feat_choice_property`: у той в отказе стоит
    # свойство, а свойства, которым отличить рукопашный удар, справочник
    # не несёт — ровно поэтому правило и записано перечислением.
    {:requires_feat_choice_other_than, :weapon_focus, [:unarmed_strike]},
    # The fourth shape of «only when leveling as …», and the only one that hangs
    # off the **value** rather than off the feat: `Epic skill focus (perform)` is
    # a bard's to take and `Epic skill focus (discipline)` is anybody's, one feat
    # id either way. `{:forbidden_by_class, class}` would say something false here
    # — the class refuses the feat in that form, and it does not.
    {:requires_leveling_as, [:druid, :ranger, :shifter]},
    # The same page's *other* sentence, and it is about the **slot** rather than
    # the level: `Epic skill focus` in `use magic device` is off the rogue bonus
    # list only, while the general slot of the same rogue level takes it and the
    # rogue bonus slot takes every other skill. Neither `forbidden_by_class` nor
    # `requires_leveling_as` can say that — the first blames a class that is not
    # at fault, the second names the very class whose level this is
    # (`Rules.FeatSlots.choice_refusals/4`).
    {:not_in_class_bonus_slot, :rogue},
    {:requires_choice, :favored_enemy, :creature_type},
    {:requires_same_choice, :spell_focus, :evocation},
    {:invalid_choice, :favored_enemy, :ooze},
    # Nothing left to choose, and the two ways that happens are two forms
    # (`FeatChoices.candidates/3`). `choice_exhausted` used to be invented by the
    # feat picker and covered both, which is how a wizard with no `Spell focus`
    # was told he had taken all eight schools already.
    {:choice_exhausted, :spell_focus, :spell_school},
    {:choice_requires, :greater_spell_focus, [:spell_focus], :spell_school},
    # A class's own one-time choice (`BuildCalculator.Rules.ClassChoices`) —
    # a Cleric's two domains. Deliberately its own heads rather than reusing
    # `invalid_choice`/`choice_exhausted`: those two read a *feat* id through
    # `Labels.choice_name/3`, which would print the wrong thing (or nothing
    # useful) for a class id, since a class and a feat are looked up in
    # different dictionaries.
    {:invalid_class_choice, :cleric, :not_a_domain},
    {:class_choice_full, :cleric, 2},
    # Defensive: the picker only ever asks about a class that has a choice at
    # all, so this should never reach a player, but a refusal that cannot be
    # worded is worse than one that is unreachable in practice.
    {:no_choice, :fighter},
    {:missing_data, {:choice_domain, :weapon}},
    {:missing_data, {:class_requirements, :weapon_master}},
    {:missing_data, {:alignment_restriction, :monk}},
    {:missing_data, {:feat_prerequisites, :epic_dodge}},
    {:missing_data, {:caster_level, 3}},
    {:missing_data, {:prerequisite, :save_bonus}},
    # Both halves of «able to cast Nth level spells» can be undecidable rather
    # than unmet: a class nobody says casts off anything, and a prestige class
    # whose host cannot be picked because two of them are tied for highest.
    {:missing_data, {:casting_ability, :sorcerer}},
    {:missing_data, {:caster_advancement, :pale_master}},
    {:missing_data, :alignment_requirement},
    {:missing_data, :max_classes},
    # ---------------------------------------- allowed, and still worth a sentence --
    # Not a refusal: `Rules.feat_pick_caveats/3`. An item lends this feat and the
    # feat cannot be taken twice, so the slot changes no number — but the pick is
    # **allowed**, because an item comes off and a slot does not (09.08.2026;
    # refusing it was a false illegality). Registered here rather than among the
    # gaps because a gap is something the model could not compute, and this is
    # advice about a choice; what it shares with a refusal is that the web layer
    # words it through `Labels.reason/2`, and a tuple nobody worded prints itself.
    {:owned_from_gear, :toughness}
  ]

  @doc """
  One example of every gap the core can put in `ruleset.gaps` or `stats.gaps`.

  Walk it to check that each has been given wording.
  """
  @spec gaps() :: [entry()]
  def gaps, do: @gaps

  @doc "One example of every reason the core refuses a level, a class or a feat with."
  @spec reasons() :: [entry()]
  def reasons, do: @reasons

  @doc """
  Every head the registry knows, gap and refusal alike.

  Derived from the entries rather than listed, so a head cannot be registered and
  left out of this. It is what a source scan matches on — see
  `test/build_calculator/rules/vocabulary_test.exs`.
  """
  @spec heads() :: [atom()]
  def heads do
    for tuple <- @gaps ++ @reasons, uniq: true, do: elem(tuple, 0)
  end

  @doc """
  The *form* of a tuple: the head, and for a gap the thing it is about.

  `{:missing_data, {:hit_die, :monk}}` and `{:missing_data, {:hit_die, :rogue}}`
  are one form; `{:missing_data, {:hit_die, …}}` and
  `{:missing_data, {:stat_cap, …}}` are two, because they need two sentences.

  A refusal is its head alone: `{:requires_class_level, :bard, 1}` is one form,
  not one per class.

  `:_` stands for a slot whose value is not an atom — a variable in source, a
  number or a string in a value. Two forms differing only in a `:_` are the same
  form to a formatter, which is what this is for.
  """
  @spec form(tuple()) :: [atom()]
  def form(tuple) when is_tuple(tuple) and tuple_size(tuple) >= 1 do
    head = elem(tuple, 0)

    cond do
      not is_atom(head) -> []
      head in @families and tuple_size(tuple) >= 2 -> [head, subject(elem(tuple, 1))]
      true -> [head]
    end
  end

  @doc "Forms of a list of entries, deduplicated."
  @spec forms([entry()]) :: MapSet.t([atom()])
  def forms(entries), do: MapSet.new(entries, &form/1)

  # What a gap is *about*: the atom beside the head, or the head of the tuple
  # beside it. Anything else is a value, not a subject.
  defp subject(atom) when is_atom(atom), do: atom

  defp subject(tuple) when is_tuple(tuple) and tuple_size(tuple) >= 1 do
    head = elem(tuple, 0)
    if is_atom(head), do: head, else: :_
  end

  defp subject(_value), do: :_
end
