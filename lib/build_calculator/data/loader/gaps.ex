defmodule BuildCalculator.Data.Loader.Gaps do
  @moduledoc """
  Оговорки ruleset'а: всё, чего загрузчик не смог превратить в правило, названо
  здесь машинной формой и доезжает до игрока (`Rules.Vocabulary.gaps/0`).

  Гэп — дырка в **нашем ответе**, а не в наших знаниях (решение Dan 10.08.2026),
  поэтому список собирается из того, что мы считаем, а не из всего, что известно
  про игру.
  """

  alias BuildCalculator.Data.Loader.Character
  alias BuildCalculator.Data.Loader.Feats
  alias BuildCalculator.Data.Loader.Gear
  alias BuildCalculator.Data.Loader.Races
  alias BuildCalculator.Data.Loader.Reading
  alias BuildCalculator.Data.Loader.Spells

  import BuildCalculator.Data.Loader.Reading

  @base_ac Reading.base_ac()
  @stat_cap_keys Character.stat_cap_keys()

  # ------------------------------------------------------------------- gaps --

  def gaps(
        version,
        raw,
        shard,
        ov,
        classes,
        skills,
        epic,
        repeat_grants,
        feats,
        domains,
        ability_bonuses,
        weapon_type_bonuses,
        skill_bonuses,
        gap_receivers
      ) do
    lists = Spells.spell_lists(ov)
    caps = Character.stat_caps(ov)

    missing_files =
      for {key, rel} <- [
            skills: "vanilla/skills.json",
            races: "vanilla/races.json",
            spellcasting: "vanilla/spellcasting.json",
            # Added 15.08.2026 (task 3.31). Its absence changes what fourteen
            # feats require — six of them by putting back the very prerequisite
            # their own pages call wrong — and until now it changed all of that
            # silently, because only three hand-written files were watched here.
            feat_requirements: "vanilla/feat_requirements.json"
          ],
          Map.get(raw, key, :missing) == :missing,
          do: {:missing_file, rel}

    # ⚠ **Both fields, and «neither» is the condition** (task 3.37). A class
    # states its hit die either as one number (`hit_die`, 22 of 23) or as a
    # scale over its own levels (`hit_die_by_class_level`, `red dragon
    # disciple`); asking only about the first named the shard's one growing die
    # missing while the data held it in full. Today no class produces this at
    # all — the form stays because a snapshot that loses either field must say
    # so rather than compute hit points off a number nobody wrote down.
    missing_hit_die =
      for {id, class} <- classes,
          is_nil(class.hit_die) and is_nil(class.hit_die_by_class_level),
          do: {:missing_data, {:hit_die, id}}

    missing_requirements =
      for {id, class} <- classes,
          class.prestige? and is_nil(class.requirements) and not is_nil(class.requirements_raw),
          do: {:missing_data, {:class_requirements, id}}

    unsupported_requirements =
      for {id, class} <- classes,
          key <- class.requirements_unsupported,
          do: {:missing_data, {:requirement, id, key}}

    missing_alignment =
      for {id, class} <- classes,
          is_nil(class.alignment_restriction) and
            class.alignment_restriction_raw not in [nil, "None", "none"],
          do: {:missing_data, {:alignment_restriction, id}}

    # ⚠ Filtered fact by fact and deduplicated afterwards, which together are the
    # existential the rule asks for: the pair `(class, what)` is **not** unique
    # (Monk carries three `feat_level_shift` records), so a gap survives when
    # *any* fact behind it names a receiver we print. Picking "the fact with this
    # pair" would tie the answer to the order of lines in a JSON file — see
    # `BuildCalculator.Rules.GapReceivers`.
    unapplied_changes =
      for {id, class} <- classes,
          change <-
            BuildCalculator.Rules.GapReceivers.filter(
              class.siala_unapplied,
              gap_receivers.our
            ),
          uniq: true,
          do: {:not_modelled, {:class_change, id, change["what"]}}

    # The same statement about the shard's **feat** pages, added 14.08.2026 —
    # the day the feat layer's unapplied facts got `affects`
    # (`Mix.Tasks.Wiki.Parse`'s `@feat_fact_affects`), which is what made it
    # safe. Read fact by fact through the same filter and deduplicated
    # afterwards, exactly as above.
    #
    # ⚠ **Why it was not here before, and why waiting was right.** Until that
    # markup existed this loop would have added 21 gaps, 20 of them about
    # damage, effect duration and immunities — precisely the rows task 3.28 had
    # just taken out of the same list, and the header figure would have gone
    # back up for no gain in what the player can act on. With the markup it
    # added **one**: `improved_evasion / siala_note`.
    #
    # ⚠ **And since 17.08.2026 it adds none, which is a state and not a bug.**
    # That one gap rested on a consequence nobody had read — vanilla's `any_of`
    # branches mirror vanilla's hand-out levels, and the shard moved the
    # hand-outs without anybody writing down whether the branches moved. H9
    # measured it (Dan, 16.08.2026), three `requirement_class_level` records
    # moved all three branches, and Dan closed the gap itself the next day
    # («правила железные и измеряны»). The loop stays, obviously: the day a feat
    # fact is tagged with a receiver we print, it reports it without anyone
    # touching this file — which is the whole point of `affects` naming the
    # receiver rather than the visibility.
    #
    # ⚠ **Why it belongs here at all**, given that `Rules.shard_feat_gaps/3`
    # already reports these on a build. The two lists answer different
    # questions and are shown under different headings — «данные» is «how
    # complete are the rules», «этот билд» is «what is missing from *these*
    # numbers» — and the class layer has been in both since 3.28. Leaving the
    # feat layer out of the first one made the header's figure depend on which
    # *file* a fact happens to live in, which is not a property a player can
    # see. It is the same doubling the class facts already have, not a new one.
    unapplied_feat_changes =
      for {id, feat} <- feats,
          change <-
            BuildCalculator.Rules.GapReceivers.filter(
              Map.get(feat, :siala_unapplied, []),
              gap_receivers.our
            ),
          uniq: true,
          do: {:not_modelled, {:feat_change, id, change["what"]}}

    # The shard's **skill** pages, added 14.08.2026 — the day the skill layer's
    # 53 facts got `affects` (data-miner). Same filter, same dedup, same two
    # lists (this one and `Rules.shard_skill_gaps/2`) answering the two
    # different questions «data» / «this build» that the class and feat
    # layers already answer twice over. Unlike the feat layer's markup wave,
    # this one was labelled *whole* — see `GapReceivers`'s own note on why
    # `skills.ours` is a real classification and not a safety net — so there
    # is no "before the markup existed" number to compare against here.
    unapplied_skill_changes =
      for {id, skill} <- skills,
          change <-
            BuildCalculator.Rules.GapReceivers.filter(
              Map.get(skill, :siala_unapplied, []),
              gap_receivers.our
            ),
          uniq: true,
          do: {:not_modelled, {:skill_change, id, change["what"]}}

    repeated_grants =
      for {id, level, feat} <- repeat_grants,
          do: {:not_modelled, {:unnamed_grant_rank, id, level, feat}}

    skill_conflicts =
      for {id, class} <- classes,
          {skill, only_in} <- class.class_skill_conflicts,
          do: {:conflict, {:class_skill, id, skill, only_in}}

    # Второе место, где Fandom спорит сам с собой про навык, и с задачи 3.104
    # оно двигает ответ: лейбл страницы говорит «Requires training: no», а
    # `Category:Skills that require training` числит её своей. Сегодня такая
    # запись ровно одна (`perform`), и разница видна ровно на одном билде —
    # бард с НУЛЁМ рангов Исполнения: по лейблу `Skill focus (Perform)` ему
    # доступен, по категории нет.
    #
    # Читаем лейбл (`Loader.Skills.build_skills/1`, довод и цитата там), и вот
    # запись о том, что выбор был. Молчаливое умолчание тут и было бы тем самым
    # «разумным дефолтом», который CLAUDE.md §3 запрещает: признак загрузился бы
    # как факт, а он — прочтение.
    #
    # ✅ 26.08.2026 выбор ПОДТВЕРЖДЁН НАБЛЮДЕНИЕМ (`GAME_CHECKS.md` AC8): бард 1
    # с нулём рангов Исполнения на экране создания персонажа видит
    # `Skill focus (Perform)`, то есть лейбл прав. 🔴 ГЭП ПРИ ЭТОМ ОСТАЁТСЯ —
    # решение задачи 3.109, и оно сознательное, а не инерция. Он говорит про
    # ИСТОЧНИК, а не про нашу неуверенность, и замер не сделал ложным ни одного
    # его слова: страница по-прежнему спорит сама с собой (`status: "conflict"`
    # пишет парсер, и `mix wiki.parse` воспроизведёт его побайтово), а мы
    # по-прежнему берём лейбл. Снимать надо признания вида «не считаем» и «это
    # допущение» (3.90, 3.93, 3.95) — ложную неуверенность про НАШ ответ;
    # подпись этого гэпа читается «источники спорят … — взят лейбл страницы»,
    # то есть утверждение. Разряд у формы `:resolved`, баннера о неполноте она
    # не зажигает (гейт на `data_real_count`, задача 3.88), и видна она ровно
    # на `/sources`, где вступление прямым текстом говорит: «Список ниже — не
    # пробелы, а список ТАКИХ решений». Полный разбор — в
    # `vanilla/feat_requirements.json` → `skill_focus` → `note`.
    trained_only_conflicts =
      for {id, skill} <- skills,
          Map.get(skill, :trained_only?) != Map.get(skill, :trained_only_category?),
          do:
            {:conflict,
             {:skill_trained_only, id,
              if(Map.get(skill, :trained_only?), do: :label_only, else: :category_only)}}

    # A `repeatable` block that names no `choice` cannot be acted on, so the feat
    # stays single-take — the safe direction — and says so rather than looking
    # like a feat nobody marked.
    unreadable_repeatable =
      for entry <- repeatable_blocks(raw, shard),
          is_nil(Feats.repeatable(entry["repeatable"])),
          id = atom_or_nil(entry["vanilla_id"] || entry["id"]),
          not is_nil(id),
          uniq: true,
          do: {:missing_data, {:feat_repeatable, id}}

    # A domain the data names and nothing resolves. Weapons are the standing
    # example and will stay one until the armoury exists: the choice is real,
    # unchecked, and must not read as checked.
    unresolved_domains =
      for {domain, dictionary} <- Enum.sort(domains),
          is_nil(dictionary.values),
          do: {:missing_data, {:choice_domain, domain}}

    # ⚠ True of this family's pages, not of every repeatable feat — see
    # `repeatable/1`. Recorded once for the ruleset rather than per feat: it is a
    # statement about how the loader read the data, and the data can turn it off
    # feat by feat with `"distinct": false`.
    #
    # Only where there **is** a domain. A feat that repeats without naming
    # anything has nothing for two picks to differ in, so no assumption is made
    # about it and claiming one would pad the list with a caveat that is not true.
    assumed_distinct =
      if Enum.any?(feats, fn {_id, feat} ->
           is_map(feat.repeatable) and feat.repeatable.distinct? == true and
             not feat.repeatable.distinct_stated?
         end),
         do: [{:assumed, :repeatable_choices_must_differ}],
         else: []

    unknown_skills =
      if map_size(skills) == 0 do
        []
      else
        for {_id, class} <- classes,
            skill <- class.class_skills,
            not Map.has_key?(skills, skill),
            uniq: true,
            do: {:missing_data, {:skill, skill}}
      end

    List.flatten([
      missing_files,
      Enum.sort(missing_hit_die),
      Enum.sort(missing_requirements),
      Enum.sort(unsupported_requirements),
      Enum.sort(missing_alignment),
      Enum.sort(unapplied_changes),
      Enum.sort(unapplied_feat_changes),
      Enum.sort(unapplied_skill_changes),
      Enum.sort(repeated_grants),
      # ⚠ Здесь стояли ДВЕ строки — `Races.racial_bonus_gaps(racial_bonuses)`
      # и первая половина `weapon_type_bonus_gaps/1`, — заводившие
      # `{:missing_data, :racial_bonus_progression}` и
      # `{:missing_data, :weapon_type_bonus_progression}`: «бонус растёт
      # с уровнем персонажа, числа на вики есть только для 40-го, функции роста
      # не называет ни одна страница». **Обе сняты 22.08.2026 решением Dan**
      # (задача 3.81): «прогрессию делать не будем, данный пробел можно закрыть».
      #
      # Продолжение решения Q2 от 15.08.2026, закрывшего добывание прогрессии:
      # «Полноценный билд всегда идет для 40 или 41 уровня, поэтому промежуточные
      # цифры не важны, главное итог в конце». Гэп — дырка в НАШЕМ ОТВЕТЕ
      # (moduledoc выше), а ответ по решению владельца даётся на 40–41 уровне.
      #
      # 🔴 **Гэпы БИЛДА этим не сняты и сниматься не должны.** Они живут
      # не здесь, а в ядре (`Rules.RacialBonus.gaps/2`,
      # `Rules.WeaponTypeBonus.gaps/3`), и приезжают каждому билду ниже 40-го:
      # `{:missing_data, {:racial_bonus_level, race}}` и
      # `{:missing_data, {:weapon_type_bonus_level, weapon}}`. Ровно то
      # различение, которое прежний комментарий здесь и объявлял главным:
      # ruleset-гэп отвечал «насколько полны правила у нас в данных», гэп билда
      # отвечает «чего не хватает В ЭТОМ числе», и закрыто решением только
      # первое. Светлый эльф-воин 25-го уровня с луком без них молча терял бы
      # 18 из своего AB.
      #
      # ⚠ Вторая половина `weapon_type_bonus_gaps/1` осталась и вызывается ниже:
      # она про оружие, которого нет в справочнике («Вилы»), а это дыра
      # не в числе, а в том, что билд с таким оружием у нас не выражается вовсе.
      Races.weapon_type_bonus_gaps(weapon_type_bonuses),
      Enum.sort(skill_conflicts),
      Enum.sort(trained_only_conflicts),
      Enum.sort(unknown_skills),
      Enum.sort(unreadable_repeatable),
      unresolved_domains,
      assumed_distinct,
      # Feats that add to a skill and whose bonus the model refuses to work out
      # (`vanilla/feat_skill_bonuses.json`, verdict `not_modelled`). A statement
      # about the corpus, so it belongs here and not on a build.
      #
      # Skipped for a feat that **repeats**: every repeatable feat a build takes
      # already carries `{:not_modelled, {:feat_bonus, id}}`
      # (`Rules.FeatChoices.gaps/3`), and saying one thing twice under two names
      # is how a list of caveats turns into a list people skim. Which feats those
      # are differs by ruleset — `Epic skill focus` only repeats once the shard
      # layer says so — so it is decided from the finished dictionary rather than
      # written down.
      #
      # ⚠ Read off the rejected half of the markup since task 3.25, and off
      # `feats[id].unmodelled_skill_bonus` before it. Same list, and the same
      # ruleset-wide statement — what changed is that a build now gets the *same*
      # caveat named per skill as well (`Rules.Skills.feats_by_skill/3`), which is
      # what `Small stature` never managed while the records were poured into
      # feat fields.
      #
      # ⚠ Filtered through `GapReceivers` since 17.08.2026 (task «пять файлов
      # прибавок») — the same filter `unapplied_changes` and its two siblings
      # already run below. Before it this loop reported every `not_modelled`
      # record unconditionally, `oath_of_wrath` included, whose own `affects`
      # now names `buff`: a once-a-day, single-target, limited-duration bonus is
      # a hole in an answer we never give, not in the one we do.
      #
      # ⚠ `bonus_ours?/2` and not an inline wrapper around `ours?/2`: a markup
      # record spells `affects` under an atom key, and that difference is now
      # written down in exactly one place. It used to be written here — while
      # four of the six markup files had no reader at all, so their labels were
      # material rather than a filter (fixed the same day in
      # `Rules.Bonuses.held_rejected/4`).
      Enum.sort(
        for record <- skill_bonuses.unmodelled,
            match?(%{repeatable: nil}, Map.get(feats, record.id)),
            BuildCalculator.Rules.GapReceivers.bonus_ours?(record, gap_receivers.our),
            do: {:not_modelled, {:feat_skill_bonus, record.id}}
      ),
      if(map_size(skills) == 0,
        do: [{:derived, :class_skills, :from_class_skills_raw}],
        else: [{:derived, :class_skills, :union_of_class_and_skill_pages}]
      ),
      if(dig(epic, ["attacks_per_round", "table"]),
        do: [],
        else: [{:assumed, :attacks_per_round_table, "fandom:Attacks per round"}]
      ),
      # ⚠ **Both used to claim "no page states this", and that stopped being true
      # 18.08.2026** (task 3.49, Dan's own pointer to `fandom:Armor class`).
      # `Armor class` and `Ability modifier` carry the numbers verbatim; neither
      # is fetched by `mix wiki.fetch` because it walks *categories* (feats,
      # spells, classes, skills, races) and a page of general rules sits in
      # none of them — the same reason `Point buy` and `Ability cap` were also
      # missing from the cache and are also cited with `in_cache: false`.
      #
      # The citation is read off `_vanilla_constants_confirmed`, not hand-typed
      # a second time here — the same section `Character.point_buy/1` and
      # `caster_minimum/1` already read, and both rulesets see it
      # (`@vanilla_sections` in `loader.ex`). `constant_source/2` degrades to
      # `nil` rather than raising if the record is ever missing a citation, so
      # a snapshot mid-edit still gets *a* caveat instead of a crash — see its
      # own doc for why that fallback still tells the truth.
      [{:assumed, :base_ac, @base_ac, constant_source(ov, "base_ac")}],
      [
        {:assumed, :ability_modifier_formula, "floor((score - 10) / 2)",
         constant_source(ov, "ability_modifier_formula")}
      ],
      # ⚠ Task 3.49 (18.08.2026): unconditional until today, on every ruleset —
      # including Siala, where `character.hit_points_roll` (`source: user`, Dan)
      # has said since 01.08.2026 that "always max" is the shard's own rule, not
      # our simplification, and nothing here ever read it. `hp_always_max?/1`
      # is `false` for vanilla unconditionally (`character` is not shared across
      # rulesets), so the caveat stays there exactly as before.
      if(Character.hp_always_max?(ov),
        do: [],
        else: [{:assumed, :hp_uses_maximum_hit_die_rolls}]
      ),
      # Spellcasting is modelled from the class progression tables now, but one
      # piece of it is not in the data at all (CLAUDE.md §6). ⚠ Three until
      # 21.08.2026 and two until 22.08.2026 — see the two struck-out entries
      # below, and note they left for opposite reasons: the bonus slots because
      # the model learned to count them, the domains because the answer never
      # wanted them.
      # ⚠ Здесь третьей строкой стояла `{:not_modelled,
      # :bonus_spell_slots_from_ability}` — «бонусные слоты за высокую
      # характеристику не считаем, таблицы в данных нет». Снята задачей 3.70:
      # таблица есть (`vanilla/spellcasting.json` → `bonus_spell_slots`), слоты
      # считаются, и печатать «не считаем» про посчитанное запрещено так же
      # прямо, как обратное. Утверждение «таблицы нет» не исчезло, а переехало
      # туда, где его можно проверить, — `Spells.spellcasting_gaps/2` заводит
      # `{:missing_data, :bonus_spell_slots}`, только если файла и правда нет.
      # ⚠ Здесь стояло `{:not_modelled, :cleric_domains}` — «выбор двух
      # доменов записывается и виден в прогрессии, но их особые способности
      # и добавленные заклинания в расчёт не идут». **Снято 22.08.2026
      # решением Dan** (задача 3.79), и не отмахиванием: пробел
      # раскладывается на ТРИ части, и ни одна до нашего ответа не доезжает:
      #
      #   * **активные умения** пяти доменов — включаемые, с длительностью
      #     (сиальский War domain: «Длительность: 1 ход за каждый модификатор
      #     силы и ловкости»), то есть **баффы** по решению Dan 10.08.2026 —
      #     та же категория, что песня барда, Ярость и Shadow Evade;
      #   * **пассивные** — изгнание нежити, автоусиление лечения, призывы
      #     на ступень выше: эффекты, которых калькулятор не считает **вовсе**
      #     (CLAUDE.md §9 — гэп это дырка в НАШЕМ ОТВЕТЕ, а не в знаниях);
      #   * **заклинания домена** — выдаются АВТОМАТИЧЕСКИ, выбора нет.
      #
      # Dan 22.08.2026: «в конструкторе заклинания нас интересуют только те,
      # что надо выбирать при повышении уровня. Поэтому у барда и колдуна они
      # есть, а у клерика есть выбор двух доменов. И это уже готово. Домены
      # клерика дают ему новые заклинания, но выбирать их не надо, они выдаются
      # автоматически. Получается для конструктора здесь делать нечего».
      #
      # 🔴 **Сам выбор двух доменов этой правкой НЕ тронут ни строкой** —
      # он модель, и именно его Dan назвал готовым: `ruleset.class_choices`
      # просит у клирика два различных домена, `Rules.ClassChoices` держит
      # уровень незакрытым, пока они не названы, и оба утверждения под
      # тестом на НАСТОЯЩЕМ ruleset'е (`ClassChoicesTest`, «гэп снят…»).
      #
      # ⚠ Сиала переработала семь доменов (Animal, Healing, Magic, Plant, Sun,
      # Trickery, War), их страницы лежат в кэше. Решение этого не отменяет,
      # но если однажды понадобятся числа доменных умений — брать надо
      # сиальские, а не ванильные.
      # ⚠ Здесь стояло `{:not_modelled, :metamagic}` — «метамагия не считается».
      # **Снято 22.08.2026 решением Dan** (задача 3.80): «метамагию можно
      # закрыть, конструктора не касается».
      #
      # Разбор, по которому решение принято: девять фитов метамагии смоделированы
      # ЦЕЛИКОМ — они в справочнике, с требованиями, которые мы проверяем
      # (`Empower` требует каста 2-го круга, `Automatic quicken` — 21-й уровень,
      # каст 9-го, сам `Quicken spell` и 30 рангов Spellcraft). Не считается
      # только ЭФФЕКТ, а он по источнику применяется при подготовке или
      # в момент каста: «Wizards and divine spellcasters … during preparation,
      # the character chooses which spells to prepare with metamagic feats;
      # Sorcerers and bards … can choose when they cast» (`fandom:Metamagic`).
      # То есть при левелапе выбирается только сам фит — и это мы моделируем,
      # — а всё остальное происходит в игре, и его результат (урон, длительность,
      # скорость каста) калькулятор не считает вовсе.
      #
      # ⚠ Единственное возражение названо и снято: «uses a spell slot higher
      # than normal» — про слоты, а слоты мы печатаем. Но задевается РАСХОД,
      # а не таблица: сколько слотов в день у колдуна 15-го уровня, метамагия
      # не меняет ни на единицу.
      # Ability score bonuses from feats (`Great strength` and its five
      # siblings) and from class abilities (a Red Dragon Disciple's own table)
      # — counted since task 3.1, so this now says only what it is for: **the
      # markup file is not here**. Judged by the finished dictionary rather
      # than by the file existing, for the same reason the ceilings are judged
      # by status: a file that arrived and turned out to state nothing
      # applicable is the same silence as no file, and only one of the two
      # would be visible otherwise.
      #
      # The totals panel's ability breakdown (task 3.2) reads this exact tuple
      # to caption itself, and stops captioning as soon as the numbers are
      # real — the gap is what makes the caption disappear, not a second edit
      # in the web layer.
      if(ability_bonuses.applied == [],
        do: [{:not_modelled, :ability_bonus_feats_and_class}],
        else: []
      ),
      Spells.spellcasting_gaps(Map.get(raw, :spellcasting, :missing), classes),
      # ⚠ Здесь стояло `{:missing_data, {:spell_circles, N}}` — «у N заклинаний
      # круг записан правкой патча, а не числом, их нет в выборе». **Снято
      # 21.08.2026 решением Dan** (задача 3.71), и подпись врала дважды.
      #
      # Во-первых, «правка патча»: у всех шести таких заклинаний стоит ровно
      # слово `epic`, ни одного зачёркнутого числа. Источник не грязный — он
      # говорит правду, что у эпического заклинания круга не бывает вовсе.
      #
      # Во-вторых, «их нет в выборе»: все шесть (`dragon_knight`,
      # `epic_mage_armor`, `epic_warding`, `greater_ruin`, `hellball`,
      # `mummy_dust`) берутся **фитами**, и все шесть фитов в справочнике есть
      # со своими требованиями по Spellcraft. Dan 21.08.2026: «все эпические
      # заклинания в игре — одноразовые раз в сон, слоты обычных кругов
      # не тратят». То есть механика смоделирована целиком, а пункт был
      # переучётом в баннере — тем же, чем была `:armor_check_penalty` ниже.
      #
      # ⚠ Сам факт «круг не читается числом» никуда не делся и по-прежнему
      # держит эти заклинания вне каталога кругов — просто это больше
      # не признание в недостаче.
      if(map_size(lists) == 0, do: [{:missing_data, :spell_lists}], else: []),
      # Лестница размеров, без которой правило хвата не считается вовсе
      # (задача 3.43): ни «двуручное», ни «нельзя взять вовсе», ни запрет щита
      # рядом с двуручным. Ruleset-wide, потому что это утверждение о снапшоте,
      # а не о билде. ⚠ Полу-объявленный блок сюда не доходит — `wield/1`
      # роняет сборку: «правило есть, а лестницы нет» молча означало бы «щит
      # можно всегда».
      if(Gear.wield(raw).size_order == [], do: [{:missing_data, :weapon_size_rules}], else: []),
      # Stat ceilings. Only what the shard layer states as `verified` becomes a
      # rule; the rest is named here rather than quietly assumed either way.
      # Derived from `@stat_cap_keys`, the same list `stat_caps/1` reads — a
      # ceiling cannot be carried without its absence being reportable, and
      # cannot be reported as missing once it is carried.
      for(
        key <- Enum.map(@stat_cap_keys, &atom/1),
        not Map.has_key?(caps, key),
        do: {:missing_data, {:stat_cap, key}}
      ),
      # ⚠ The *general* armour-class ceiling is judged by status, not by having a
      # number: `value: null` with `status: "verified"` is a decision — «there is
      # no general ceiling, the types simply stack» (Dan, 03.08.2026) — and a
      # decision must not keep printing "we do not know" (CLAUDE.md §6). Only one
      # AC type has a ceiling, and it lives with the other ceilings as
      # `stat_caps.dodge_ac`.
      if(dig(ov, ["gear", "ac_cap", "status"]) == "verified",
        do: [],
        else: [{:missing_data, {:stat_cap, :ac}}]
      ),
      # The ceilings above cap bonuses, and what is left of the item side of them.
      #
      # ⚠ This statement has now been narrowed **twice**, both times because a
      # half of it stopped being true, and both times renamed rather than reworded:
      # a form whose name outlives its meaning is how справка goes stale silently.
      #
      #   * until 09.08.2026 it was `:item_attack_and_skill_bonuses`. Task 3.20
      #     made the skill half false — the skill bonuses items give are a number
      #     the player types now, and they are clipped by the +50 the sentence
      #     about magic staves states them under;
      #   * until 10.08.2026 it was `:item_attack_bonus`, «прямой бонус к атаке
      #     с предмета не вводится». Task 3.5 part B made *that* false: a weapon
      #     in hand carries an attack bonus the player types, and it is inside
      #     the +20. ⚠ It carried an enhancement bonus beside it until task 3.52,
      #     which dropped that input — the two differed only in damage.
      #
      # What is left is the part no field takes and none is planned to: an attack
      # bonus off anything **other** than the weapon in hand, and the two cap
      # fillers that are not properties of a build at all — buffs and the bard
      # song (`GAME_CHECKS.md` J1, point 5: they must be *named* where a player
      # compares our AB with the game's, because his +20 may be full and ours not).
      #
      # ⚠ **`{:not_modelled, :armor_check_penalty}` стояла здесь второй строкой
      # и снята 16.08.2026 задачей 3.42.** Она говорила «величина зависит от
      # надетого доспеха, а доспеха у нас нет»; доспех появился задачей 3.41, и
      # с 3.42 штраф считается — отдельным термом значения навыка у тех шести,
      # которые страница называет поимённо (`Rules.Skills`, `Rules.Worn.
      # armor_check_penalty/2`). Форма удалена вместе с русской подписью, а не
      # оставлена мёртвой: печатать «не считаем» про посчитанное запрещено так
      # же прямо, как обратное (CLAUDE.md §6), и сторож словаря ловит именно
      # зарегистрированную форму, которую больше никто не производит.
      # ⚠ Здесь стояло `{:not_modelled, :attack_bonus_outside_weapon}` — «бонус
      # с других предметов, баффы и песню барда не считаем». **Снято 21.08.2026
      # решением Dan** (задача 3.71): в одном пункте лежали ТРИ разные вещи,
      # и две из них он вывел из области ответа ещё 10.08.2026 («песня и все
      # заклинания у нас баффы и мы их не учитываем»), а §9 прямо запрещает
      # такому быть гэпом — «если калькулятор ответа не даёт вовсе, то и дырки
      # нет». Третью, настоящую, снял он же: «бонуса к атаке с прочих вещей
      # я не припоминаю, мы уже учитываем всё что надо».
      #
      # ⚠ Кап +20 этим НЕ затронут: замер Q5b (единственное место, где модель
      # сознательно расходится с наблюдением Dan) остаётся открытым отдельно.
      # ⚠ Здесь стояло `{:not_modelled, :ability_cap_penalty_interaction}` —
      # «кап +12 считаем плоским, а источник говорит, что штрафы понижают
      # эффективный потолок (при силе −2 предметы дадут не больше +10)».
      # **Снято 22.08.2026 решением Dan** (задача 3.77), и не отмахиванием,
      # а по разбору: взаимодействие НЕВЫРАЗИМО в нашей форме ввода.
      #
      # Источник описывает штраф и прибавку на ОДНУ характеристику из разных
      # источников, а в «Вещах» на характеристику приходится ровно одно число,
      # и означает оно НЕТТО. Игрок с кольцом +12 и проклятием −2 впишет +10
      # и получит верный ответ. Прочие источники штрафа проверены и оба мимо:
      # истинные расовые модификаторы в кап не входят по самому источнику,
      # а заклинания — баффы, выведенные из области ответа 10.08.2026.
      #
      # Dan: «в реальности у одетых персонажей надето по +12 статов нужных
      # в билде, что они и вобьют у нас в вещах».
      #
      # ⚠ Сам кап при этом считается и остаётся под тестом: +20 срезается
      # до +12 и говорит об этом (`stats.capped` несёт `:gear_abilities`),
      # а штраф проходит насквозь — потолок односторонний, и зеркалить его
      # в −12 значило бы выдумать игровое число.
      # ⚠ Вторая ветка была `[{:not_modelled, :zen_archery}]` и снята 14.08.2026:
      # правило для `Zen archery` заведено, то есть строка стала ложью про
      # посчитанное — а печатать «не применяем» о применённом запрещено так же
      # прямо, как обратное (CLAUDE.md §6). Того, что осталось непосчитанным у
      # этого фита, ruleset не знает: оно зависит от билда (какое оружие в руках)
      # и говорится оттуда — `{:not_modelled, {:attack_ability_weapon, feat}}`
      # в `Rules.Attack`.
      # ⚠ Спрашивается СЫРОЙ список, а не разобранный хук: вопрос здесь один —
      # «правила вообще объявлены», — и тащить ради него в `gaps/14`
      # справочник оружия значило бы отвечать на него разбором, который умеет
      # ронять сборку.
      if(Character.attack_ability_rules_stated?(ov),
        do: [],
        else: [{:missing_data, :attack_ability_rules}]
      ),
      if(Character.point_buy(ov), do: [], else: [{:missing_data, :point_buy_costs}]),
      # ⚠ Measured in game on 03.08.2026 and applied since, so the gap is now
      # conditional like every other. It comes back for a ruleset that carries no
      # table (vanilla has no overrides file at all) or one whose record a human
      # demoted — and it must, because the floor is what makes a caster's budget
      # 27 instead of 30: without it the calculator hands the player three points
      # the game never gave.
      if(Character.caster_minimum(ov), do: [], else: [{:missing_data, :caster_minimum_ability}]),
      if(version != "vanilla" and dig(ov, ["character", "max_classes", "value"]),
        do: [],
        else: [{:missing_data, :max_classes}]
      ),
      # «Дух Сиалы» (task, волна 12, 09.08.2026): a safety net, not a copy of
      # `max_classes`'s — deliberately **not** the same shape of exception.
      # `max_classes` shows its gap on vanilla too because vanilla's own class
      # limit is a genuinely open question (CLAUDE.md §9 — 1.69 says 3, the EE
      # patch says 8, nobody picked one). This fact has no such ambiguity:
      # vanilla NWN simply has no such mechanic, confirmed rather than
      # unknown, so `nil` there is the *answer*, not a hole, and must stay
      # gap-free — printing "не задан в данных" on every vanilla build would
      # be the exact "не знаем про решённое" CLAUDE.md §6 forbids. The gap
      # exists only to catch `innate_hp_bonus/1` silently returning `nil`
      # under **siala_41**, where the fact is supposed to be `verified` — a
      # broken JSON path or a status a human demoted, the same failure mode
      # `stat_caps/1` and `verified_flag/3` degrade the same silent way.
      if(version == "vanilla" or Character.innate_hp_bonus(ov),
        do: [],
        else: [{:missing_data, :innate_hp_bonus}]
      ),
      # ⚠ Task 3.49 (18.08.2026): used to fire for every non-vanilla ruleset
      # unconditionally. Siala's own `skills.rank_cap_at_41` (`source: user`,
      # Dan) has confirmed the one level past vanilla's own table (41 = 40 + 1)
      # since 01.08.2026 — «ванильная формула… просто продолжается… подтверждение
      # только от игрока» — and nothing here ever read it either. A *future*
      # non-vanilla ruleset without such a record still gets the caveat, which
      # is what reading the record rather than the bare version string buys.
      if(version == "vanilla" or Character.skill_rank_cap_extension_confirmed?(ov),
        do: [],
        else: [{:assumed, :skill_rank_caps_past_vanilla_cap}]
      ),
      unavailable_feat_gaps(version, classes),
      assumed_disabled_gaps(feats)
    ])
  end

  # Renders a `_vanilla_constants_confirmed.<key>.source` record the way
  # `attacks_per_round_table`'s own hand-written citation already reads —
  # `"fandom:Page name"` — so all three universal-constant caveats cite their
  # page in one voice rather than two.
  #
  # `nil` for anything short of a proper `{"wiki" => _, "page" => _}` map: a
  # record a human has not finished (or one some future ruleset simply does not
  # carry) must fall back to the honest "no page" wording rather than crash the
  # whole ruleset load over one citation. `base_ac` and `ability_modifier_formula`
  # do not exercise this branch today — both records are `verified` — but the
  # branch is what keeps the caveat from lying **again** if that record is ever
  # edited back out, which is exactly the failure task 3.49 was opened over.
  defp constant_source(ov, key) do
    case dig(ov, ["_vanilla_constants_confirmed", key, "source"]) do
      %{"wiki" => wiki, "page" => page} when is_binary(wiki) and is_binary(page) ->
        "#{wiki}:#{page}"

      _ ->
        nil
    end
  end

  # A feat switched off **without a measurement of its own** — the shard record
  # says `"status": "assumed"` instead of `"verified"`.
  #
  # One gap per feat, deliberately: the whole reason the form exists is that
  # "switched off" is known to different degrees inside one family, and a single
  # flag over the family would erase the difference. Siala replaced the vanilla
  # weapon-proficiency system with five of its own, and of the eight vanilla
  # variants **three were seen missing in game** (`martial`, `exotic`, `elf` —
  # `GAME_CHECKS.md` H5) while four cannot be observed in the pick list at all:
  # each is handed over by exactly one class, and a granted feat never appears
  # there, so `monk` looks identical whether it is off or merely given. Those
  # four are `assumed` and say so; the measured ones print nothing, because a
  # caveat about something measured is the false uncertainty CLAUDE.md §6
  # forbids just as plainly as the opposite.
  #
  # 🔴 The eighth, `simple`, is not switched off at all — task 3.112
  # (26.08.2026). It used to sit among the measured four on the strength of the
  # same H5 sighting, and the sighting was right while the *reading* was not:
  # "the rogue does not see it" also fits "he already has it". Three `.билд`
  # dumps print it at LEVEL 1 for a wizard, a monk and a fighter alike, so the
  # shard hands it to everyone. It therefore carries no `disabled` record and
  # cannot reach this function.
  #
  # ⚠️ And the same dumps make "cannot be observed at all" too strong a claim
  # for the remaining four: the game log prints what was *granted*, and `monk`,
  # `wizard` and `rogue` are absent from it. Their status was deliberately left
  # `assumed` by that task — upgrading three neighbours is its own decision with
  # its own price (three caveats leave the screen) — but the sentence above is
  # about the **pick list**, not about every channel there is.
  #
  # Read off `siala_changes` rather than off a flag on the feat: the status
  # belongs to the *record*, and one feat may carry facts of several statuses.
  defp assumed_disabled_gaps(feats) do
    for {id, feat} <- Enum.sort_by(feats, &elem(&1, 0)),
        %{"what" => "disabled", "value" => true, "status" => "assumed"} <-
          List.wrap(Map.get(feat, :siala_changes)),
        do: {:assumed, {:feat_disabled, id}}
  end

  # What the ban on picking a general feat at a level of some class rests on, and
  # the two ways it can be wrong. Both are statements about the corpus, so they
  # live here rather than on a build.
  #
  #   * **nothing to apply.** No class carries a list at all, which is what a
  #     snapshot parsed before `unavailable_feats` existed looks like. The rule
  #     then silently permits everything — exactly the false legality it was
  #     written to remove — and silence is not "clean" (CLAUDE.md §9).
  #   * **applied off Fandom on a Siala ruleset.** The shard's own class pages say
  #     nothing about forbidden feats anywhere (checked across
  #     `siala_41/classes.json`: no page restricts a pick), so the vanilla list is
  #     carried over. That is the documented default — «если по механике на вики
  #     Сиалы ничего нет, считаем её ванильной, но помечаем источник» (CLAUDE.md
  #     §3) — and this is the mark. It matters more than most: the shard rewrote
  #     Monk's BAB and moved half of Shadowdancer's abilities, so "it never
  #     touched the feat lists" is a claim, not an observation.
  defp unavailable_feat_gaps(version, classes) do
    cond do
      Enum.all?(classes, fn {_id, class} -> MapSet.size(class.unavailable_feats) == 0 end) ->
        [{:missing_data, :class_unavailable_feats}]

      version != "vanilla" ->
        [{:assumed, :class_unavailable_feats_vanilla}]

      true ->
        []
    end
  end

  # Every record, from any layer, that states something about repeatability.
  # Both layers are searched because either may carry the key and the shard's
  # wins; a record that carries none is not a record with a problem.
  defp repeatable_blocks(raw, shard) do
    vanilla = if is_list(raw.feats), do: raw.feats, else: []

    shard_entries =
      Feats.feat_entries(Map.get(shard, :feats_generated, :missing)) ++
        Feats.feat_entries(Map.get(shard, :feats_manual, :missing))

    for entry <- vanilla ++ shard_entries,
        is_map(entry),
        Map.has_key?(entry, "repeatable"),
        do: entry
  end
end
