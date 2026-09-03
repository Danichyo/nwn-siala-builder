defmodule BuildCalculator.Data.Loader.Skills do
  @moduledoc """
  Навыки: ванильные записи, сиальский слой поверх них и правила навыков —
  прибавки, которые навык даёт сам (Spellcraft к спасброскам) и штрафы формы билда.
  """

  alias BuildCalculator.Data.Loader.ClassFeatFacts
  alias BuildCalculator.Data.Loader.Classes
  alias BuildCalculator.Data.Loader.Reading
  alias BuildCalculator.Data.Loader.Spells

  import BuildCalculator.Data.Loader.Reading

  @ability_keys Reading.ability_keys()

  # The same six, written out. A separate table and not an extension of the one
  # above, because the two answer different questions: `@ability_keys` reads the
  # three-letter key our own JSON is written in, this one reads the English word
  # a **wiki page** uses (`primary ability: [[wisdom]]`). Merging them would let a
  # file written in one vocabulary be silently read as the other.
  @ability_words %{
    "strength" => :str,
    "dexterity" => :dex,
    "constitution" => :con,
    "intelligence" => :int,
    "wisdom" => :wis,
    "charisma" => :cha
  }

  # ----------------------------------------------------------------- skills --

  # An absent `vanilla/skills.json` yields an empty dictionary plus a `gaps`
  # entry, never a crash — the file arrived late and may again.
  def build_skills(:missing), do: %{}

  def build_skills(list) when is_list(list) do
    Map.new(list, fn s ->
      id = atom(s["id"])

      {id,
       %{
         id: id,
         name: s["name"],
         key_ability: ability_or_nil(s["key_ability"] || s["ability"]),
         # Classes for which this is a class skill, off the skill's own page.
         # `classes_all?` means every class, which is how Heal and Lore are given.
         class_for:
           s["classes_raw"] |> Classes.wiki_links() |> Enum.concat(atoms(s["class_for"])),
         classes_all?: s["classes_all"] == true,
         # "Exclusive" skills cannot be bought cross-class at all — a build with
         # no class granting them may take no ranks (fandom skill pages,
         # `cross_class_raw: "no"`).
         exclusive?: s["exclusive"] == true,
         # Лейбл страницы («Requires training: yes»), а не членство в категории.
         # У одной записи из 28 они СПОРЯТ (`perform`), и выбор здесь не молчит:
         # `trained_only_category?` рядом несёт вторую половину, а `Loader.Gaps`
         # превращает расхождение в `{:conflict, {:skill_trained_only, …}}`.
         #
         # ⚠ Почему лейбл: `fandom:Untrained skill check` называет, чем эта вики
         # метит такие навыки — «those that do not are marked as either "Requires
         # Training: Yes" or "Untrained: No". (NWNWiki uses the former.)». То есть
         # лейбл и есть метка, а категория — индекс поверх неё. Довод источниковый,
         # и потому это выбор между двумя прочтениями, а не выдуманное число.
         #
         # ✅ И с 26.08.2026 выбор стоит НЕ ТОЛЬКО на доводе: Dan замерил ровно тот
         # билд, на котором две стороны расходятся, — бард 1 с НУЛЁМ рангов
         # Исполнения на экране создания персонажа, — и `Skill focus (Perform)`
         # там доступен (`GAME_CHECKS.md` AC8). Лейбл прав, категория ошибочна.
         # ⚠ Ни одно число от этого не сдвинулось: `perform` как читался
         # `trained_only?: false`, так и читается. Изменилась опора, а не ответ,
         # и гэп остался на месте — разбор решения в `vanilla/feat_requirements.json`
         # → `skill_focus` → `note` и в `Loader.Gaps.gaps/*` рядом с самим гэпом.
         #
         # ⚠ Читатель у признака ровно один — `Rules.Prereqs`, ключ
         # `chosen_skill_ranks_if_trained_only` («Skill focus in a skill that
         # requires training can only be taken if the character is trained in it»,
         # задача 3.104). До неё поле грузилось и не читалось никем.
         trained_only?: s["trained_only"] == true,
         trained_only_category?: s["trained_only_category"] == true,
         # ⚠ Три ответа, а не два, и третий не декоративный. Парсер ставит
         # `null`, когда предложение страницы перестало разбираться вовсе
         # (`Mix.Tasks.Wiki.Parse`, «the armor check penalty sentence no longer
         # parses»), а слой Сиалы ставит «неизвестно» через `unknown_fields`
         # (`alchemy` — навык шарда, про который не высказался никто). Свернуть
         # `null` в `false` значило бы сказать «штрафа нет» там, где никто ничего
         # не говорил, — а это ровно то число, которое задача 3.42 подставляет
         # шести навыкам.
         armor_check_penalty: armor_check_penalty(s["armor_check_penalty"]),
         source: s["source"],
         # The shard layer, same contract as a class's and a feat's: the page's
         # own name, everything it says, and the subset that reached no
         # mechanical home. `vanilla_baseline` is the skill layer's own field and
         # answers a question the other two never ask — see `merge_skill_entry/3`.
         ru: nil,
         siala_only?: false,
         vanilla_baseline: nil,
         siala_changes: [],
         siala_unapplied: [],
         # Fields of the vanilla shape that the wiki does not state **anywhere**
         # for this skill. Named rather than invented: `alchemy` has no key
         # ability on any page, and picking one would be a guess dressed as data.
         unknown_fields: [],
         siala_source: nil
       }}
    end)
  end

  # `true` / `false` — страница ответила; всё остальное (в том числе `null`
  # парсера) — не ответил никто.
  defp armor_check_penalty(true), do: :applies
  defp armor_check_penalty(false), do: :none
  defp armor_check_penalty(_unstated), do: :unknown

  defp atoms(nil), do: []
  defp atoms(list) when is_list(list), do: Enum.map(list, &atom/1)

  defp ability_or_nil(nil), do: nil
  defp ability_or_nil(v) when is_binary(v), do: Map.get(@ability_keys, String.upcase(v))

  # An ability named the way a wiki page names it: `"[[wisdom]]"`. The links are
  # cut here rather than by the parser, so the machine layer keeps carrying the
  # source's own text and a diff against the page stays readable (CLAUDE.md §3).
  #
  # A word outside the six is `nil` — the same answer as an absent field, and on
  # purpose: both mean "this class's casting ability is not known", and the one
  # place that must not treat that as harmless is `Rules.Prereqs`, not this.
  def ability_word(nil), do: nil

  def ability_word(value) when is_binary(value) do
    Map.get(@ability_words, value |> Spells.strip_links() |> String.downcase())
  end

  def ability_word(_other), do: nil

  # ------------------------------------------------------- shard skill layer --

  # `priv/rules/siala_41/skills.json`: all 29 pages of the shard's «Навыки»
  # category, read by hand. 28 map onto vanilla skills one for one; the 29th
  # (`alchemy`) is the shard's own and has no vanilla counterpart.
  #
  # Almost nothing here changes a number on a character sheet — the two rules
  # that do are not properties of a single skill and live in `skill_rules/2`.
  # What this pass is for is that the other 20-odd changes stop being invisible:
  # each travels on the skill record, and the ones that reached no mechanical
  # home are named, exactly as a class's do.
  #
  # Returns the dictionary and the facts the skill pages state about **classes**
  # («Навыки Скрытность и Тихое передвижение сделаны классовыми» — a fact about
  # Blackguard, written on the skill's page), which the caller lays onto the
  # class map afterwards.
  def apply_skill_layer(skills, :missing, _rules), do: {skills, []}

  def apply_skill_layer(skills, %{"skills" => entries} = shard_skills, rules)
      when is_list(entries) do
    with_save_bonus = MapSet.new(rules.save_bonus, & &1.skill)
    # Which `{skill, what}` pairs became a rule — see `apply_skill_change/3`'s
    # last clause. Built from the rules and not from the file a second time, so
    # "applied" cannot drift away from "actually applied".
    #
    # ⚠ Плюс те, что считает **другой файл** (`counted_elsewhere`): «посчитано вон
    # там» и «не посчитано» — противоположные утверждения, и оставить такое
    # изменение в `siala_unapplied` значило бы напечатать игроку оговорку про
    # число, которое у него на экране посчитано. Это единственное, что читается
    # здесь из файла, и указатель не берётся на веру —
    # `verify_skill_class_bonuses!/3` разрешает его против самой разметки.
    applied =
      rules.class_level_bonuses
      |> MapSet.new(&{&1.skill, &1.what})
      |> MapSet.union(
        MapSet.new(skill_changes_counted_elsewhere(shard_skills), &{&1.skill, &1.what})
      )

    Enum.reduce(entries, {skills, []}, fn entry, {acc, facts} ->
      id = atom(entry["vanilla_id"] || entry["id"])
      base = Map.get(acc, id) || new_shard_skill(id, entry)

      {skill, unapplied, entry_facts} =
        apply_skill_changes(base, {id, with_save_bonus, applied}, entry["changes"] || [])

      {Map.put(acc, id, merge_skill_entry(skill, entry, unapplied)), facts ++ entry_facts}
    end)
  end

  def apply_skill_layer(skills, _other, _rules), do: {skills, []}

  # `alchemy`: a skill the shard added, with no vanilla record to sit on. Every
  # flag defaults to the permissive value because the wiki states none of them —
  # which is precisely what `unknown_fields` records, so the absence is visible
  # rather than looking like a decision.
  defp new_shard_skill(id, entry) do
    %{
      id: id,
      name: entry["name"] || entry["ru"],
      key_ability: nil,
      class_for: [],
      classes_all?: false,
      exclusive?: false,
      trained_only?: false,
      trained_only_category?: false,
      # ⚠ И этот флаг — единственный из четырёх, у которого «пермиссивное
      # значение» и «неизвестно» это РАЗНЫЕ числа, а не разные слова: остальные
      # три решают, что навык можно качать, а этот решает, отнимает ли доспех.
      # Поэтому по умолчанию `:unknown`, а не `:none`: у навыка шарда, про
      # который никто не высказался, «штрафа нет» — такое же выдуманное игровое
      # число, как любое другое.
      #
      # ⚠ Довод верен и после 17.08.2026, изменился только адресат: у Алхимии
      # ответ теперь ЕСТЬ («Штрафа нет» — Dan, кейс P1), и приходит он записью
      # `armor_check_penalty` в `changes[]`, которую читает
      # `apply_skill_change/3`. Умолчание осталось `:unknown` именно затем,
      # чтобы следующий навык шарда, про который никто не высказался, получил
      # третий ответ, а не тот же ноль по наследству.
      armor_check_penalty: :unknown,
      source: nil,
      ru: entry["ru"],
      siala_only?: true,
      vanilla_baseline: nil,
      siala_changes: [],
      siala_unapplied: [],
      unknown_fields: [],
      siala_source: nil
    }
  end

  defp merge_skill_entry(skill, entry, unapplied) do
    verify_unknown_fields!(skill.id, entry)

    %{
      skill
      | ru: entry["ru"] || skill.ru,
        name: skill.name || entry["name"] || entry["ru"],
        siala_only?: skill.siala_only? or entry["siala_only"] == true,
        # `true` — the page says outright "работает как в оригинальной игре";
        # `false` — it says outright that it does not; a record with no baseline
        # at all means the page never addressed it. Kept whole, because the
        # difference between "stated unchanged" and "silent" is the point of the
        # field and collapsing it to a boolean would destroy it.
        vanilla_baseline: entry["vanilla_baseline"],
        siala_changes: entry["changes"] || [],
        siala_unapplied: unapplied,
        unknown_fields: entry["unknown_fields"] || [],
        # ⚠ Файл сильнее умолчания кода. `unknown_fields` означает «факта
        # с цитатой для этого поля не существует» (README слоя), то есть ровно
        # `:unknown`, и прочитать его здесь дешевле, чем однажды обнаружить, что
        # запись это говорит, а ruleset — нет.
        #
        # ⚠ Сегодня эта ветка не срабатывает ни на одной записи корпуса:
        # единственным её адресатом была `alchemy`, а с 17.08.2026 штраф у неё
        # назван (Dan, кейс P1) и поле ушло из `unknown_fields`. Ветка остаётся,
        # потому что остаётся сам случай — навык шарда, про чей штраф никто не
        # высказался, — и `verify_unknown_fields!/2` рядом следит, чтобы две
        # половины файла не сказали про одно поле разное.
        armor_check_penalty:
          if("armor_check_penalty" in (entry["unknown_fields"] || []),
            do: :unknown,
            else: skill.armor_check_penalty
          ),
        siala_source: entry["source"]
    }
  end

  # ⚠ Одно поле — одно утверждение. `unknown_fields` говорит «факта с цитатой
  # для этого поля не существует», запись в `changes[]` — «вот факт, вот цитата,
  # вот источник»; вместе это про одно поле два взаимоисключающих утверждения,
  # и выбрать из них молча загрузчик права не имеет.
  #
  # Ловится ПОЛУПРАВКА, и она дешёвая ровно настолько, чтобы случиться:
  # у `armor_check_penalty` список сильнее записи (см. `merge_skill_entry/3`),
  # поэтому редактор, который заведёт факт и забудет вычеркнуть имя поля,
  # получил бы `:unknown` при прочитанном ответе — то есть «?» на экране вместо
  # числа, и ни одного сообщения об этом.
  #
  # ⚠ Статус записи не смотрим сознательно: даже `unclear` — это «страница
  # что-то сказала, а прочитать однозначно не вышло», и с «не высказался никто»
  # оно тоже не сочетается.
  defp verify_unknown_fields!(id, entry) do
    stated = MapSet.new(entry["changes"] || [], & &1["what"])

    case Enum.filter(entry["unknown_fields"] || [], &MapSet.member?(stated, &1)) do
      [] ->
        :ok

      both ->
        raise "siala_41/skills.json: skill #{id} lists #{Enum.join(both, ", ")} in " <>
                "unknown_fields and states the same field in changes[] — «никто не " <>
                "высказался» and a fact with a quote cannot both be true"
    end
  end

  # The other guard of the same kind, and it fires on the same thing: our own
  # data saying two incompatible things about one field. `class_skills_unchanged`
  # asserts that the class list on the shard's page is the vanilla one — an
  # assertion we can check, which is rare enough in this repository to be worth
  # checking. See `apply_skill_change/3`'s clause for why a mismatch stops the
  # build instead of becoming a gap: неизвестно here is not "the game does
  # something we cannot model" but "our two files disagree", and the honest
  # numbers are the ones nobody has written down yet.
  defp verify_class_list_unchanged!(id, %{classes_all?: true}, stated) do
    raise "siala_41/skills.json: skill #{id} states class_skills_unchanged " <>
            "(#{names(stated)}) while the vanilla layer gives this skill to every " <>
            "class — a named list and «all classes» cannot both be the same list"
  end

  defp verify_class_list_unchanged!(id, skill, stated) do
    vanilla = MapSet.new(skill.class_for)
    added = MapSet.difference(stated, vanilla)
    dropped = MapSet.difference(vanilla, stated)

    if MapSet.size(added) > 0 or MapSet.size(dropped) > 0 do
      raise "siala_41/skills.json: skill #{id} states class_skills_unchanged " <>
              "(#{names(stated)}) but the vanilla layer holds #{names(vanilla)}" <>
              added_note(added) <>
              dropped_note(dropped) <>
              " — «список не менялся» is checked against vanilla/skills.json and " <>
              "no longer holds"
    end

    :ok
  end

  defp added_note(set) do
    if MapSet.size(set) == 0,
      do: "",
      else:
        "; #{names(set)} is on the shard's page and not in vanilla, which is the " <>
          "shard ADDING a class — write it as `class_skills`, or the build pays " <>
          "cross-class price under half the rank cap"
  end

  defp dropped_note(set) do
    if MapSet.size(set) == 0,
      do: "",
      else:
        "; #{names(set)} is in vanilla and unnamed on the shard's page, which is " <>
          "either a removal or a partial page (CLAUDE.md §3) — a human has to say which"
  end

  defp names(set), do: set |> Enum.sort() |> Enum.map_join(", ", &inspect/1)

  defp apply_skill_changes(skill, scope, changes) do
    Enum.reduce(changes, {skill, [], []}, fn change, {acc, unapplied, facts} ->
      case apply_skill_change(change, acc, scope) do
        {:ok, updated} -> {updated, unapplied, facts}
        {:ok, updated, more} -> {updated, unapplied, facts ++ more}
        :skip -> {acc, unapplied ++ [change], facts}
      end
    end)
  end

  # Same refusal as the class layer, for the same reason: `unclear` means a human
  # read the page and could not pin the value down. Today that is Heal's «добавлена
  # зависимость от навыка» to Wholeness of Body and Intimidate's effect on the
  # Barbarian's rage — both sentences state that a number exists and none of them
  # states the number.
  #
  # ⚠ Здесь примером стоял Craft Trap («сделан классовым для Теневого танцора») —
  # снят 17.08.2026 замером Dan: навык классовый, запись применяется. Пример
  # заменён, а не выброшен, и разница важна: у Craft Trap отказ был про
  # РАСХОЖДЕНИЕ двух прочтений (какой из двух навыков ловушек шард добавил),
  # а замер показал, что верны оба, — то есть отказ снят не потому, что мы стали
  # смелее, а потому, что источник оказался неполным, а не противоречивым.
  defp apply_skill_change(%{"status" => "unclear"}, _skill, _scope), do: :skip

  defp apply_skill_change(%{"what" => "key_ability", "value" => value}, skill, _scope)
       when is_binary(value) do
    case ability_or_nil(value) do
      nil -> :skip
      ability -> {:ok, %{skill | key_ability: ability}}
    end
  end

  # ⚠ Тот же контракт, что у ключевой характеристики выше, и заведён по той же
  # причине: у флага ТРИ ответа, а запись слоя умеет сказать только два из них.
  # `false` здесь — утверждение «доспех у этого навыка не отнимает», и оно
  # приходит записью **с источником**, а не молчаливым умолчанием кода: третий
  # ответ (`:unknown`, «не высказался никто») остаётся тем, что получает навык
  # шарда БЕЗ такой записи — см. `new_shard_skill/2`.
  #
  # ⚠ Без этой клаузы общая клауза ниже положила бы факт в `siala_unapplied`,
  # то есть данные утверждали бы одно, а ruleset — другое, и молча.
  defp apply_skill_change(%{"what" => "armor_check_penalty", "value" => value}, skill, _scope)
       when is_boolean(value) do
    {:ok, %{skill | armor_check_penalty: armor_check_penalty(value)}}
  end

  # Stated from the skill's side; applied to the classes named. Both shapes the
  # file uses — a vanilla skill gaining a class and the shard's own skill naming
  # the class that gets it.
  defp apply_skill_change(%{"what" => "class_skills", "value" => %{} = value}, skill, {id, _, _}) do
    case value["added_for"] do
      [_ | _] = classes -> {:ok, skill, for(class <- classes, do: {atom(class), id})}
      _ -> :skip
    end
  end

  defp apply_skill_change(%{"what" => "class_skill_for", "value" => classes}, skill, {id, _, _})
       when is_list(classes) do
    {:ok, skill, for(class <- classes, do: {atom(class), id})}
  end

  # The mirror image of the two above, and the only fact in the corpus that
  # states a **coincidence** instead of a change: «Классы, которые используют
  # данный навык: воры, рейнджеры, убийцы» — the shard's page restating the
  # class list vanilla already has. There is nothing to change, so until task
  # 3.78 the record fell through to `siala_unapplied` and travelled to the
  # player as «не смоделировано» — a caveat about a rule that is in force,
  # merely written down in the other file.
  #
  # ⚠ It is applied by being **checked, not by being trusted**. The record's own
  # note says a human compared the three names against `vanilla/skills.json` and
  # found them equal; this re-runs that comparison every build, so the day the
  # shard edits the list the claim stops being true out loud rather than
  # quietly. Silencing the line with a `not_a_gap` decision (задача 3.74) would
  # have cost the same and bought nothing — «мы отказались сверять» is a weaker
  # sentence than «сверено», and it would not survive the edit this guard is for.
  #
  # ⚠ Set equality, both directions, because the two directions are wrong in
  # different ways and neither has an honest number:
  #
  #   * a name vanilla does not carry means the shard **added** a class, and
  #     that has to be written as `class_skills` — applied as "unchanged" it
  #     would leave the build paying cross-class price under half the rank cap;
  #   * a name the page omits means either the shard removed one or the page is
  #     partial (CLAUDE.md §3, урок фита `Artist`: молчание источника — молчание,
  #     а не отрицание), and picking between those two is a human's job.
  #
  # ⚠ And the check runs against the **vanilla** list on purpose, not against
  # who ends up holding the skill. Siala's own page is not the shard's whole
  # answer: Теневой танцор gets `set_trap` from `siala_41/classes.json`, this
  # page never mentions him, and the two statements do not contradict — one is
  # about vanilla's list, the other adds to it.
  defp apply_skill_change(
         %{"what" => "class_skills_unchanged", "value" => classes},
         skill,
         {id, _, _}
       )
       when is_list(classes) do
    verify_class_list_unchanged!(id, skill, MapSet.new(classes, &atom/1))
    {:ok, skill}
  end

  # The scope of a saving-throw bonus, for a skill that has one. The bonus is a
  # rule (`skill_rules/2`) and the scope is deliberately not modelled — but that
  # caveat is reported once, precisely, as `{:not_modelled, {:save_bonus_scope,
  # skill}}`. Letting it also sit in `siala_unapplied` would state the same
  # caveat twice under two names, and a list with duplicates in it is a list
  # people learn to skim.
  defp apply_skill_change(%{"what" => "save_bonus_scope"}, skill, {id, with_save_bonus, _}) do
    if MapSet.member?(with_save_bonus, id), do: {:ok, skill}, else: :skip
  end

  # The other half of `class_level_bonus_rules/1`, and the same contract
  # `save_bonus_scope` has above: a change counts as applied **exactly when a
  # rule was built out of it**. Deciding it from the rules rather than from the
  # file a second time is what keeps "applied" from drifting away from applied —
  # a record the rule builder refused (`unclear`, or a shape it cannot read)
  # stays in `siala_unapplied` and goes on travelling as a gap.
  defp apply_skill_change(%{"what" => what}, skill, {id, _save, applied}) when is_binary(what) do
    if MapSet.member?(applied, {id, what}), do: {:ok, skill}, else: :skip
  end

  defp apply_skill_change(_change, _skill, _scope), do: :skip

  def apply_skill_class_facts(classes, facts) do
    Enum.reduce(facts, classes, fn {class_id, skill_id}, acc ->
      ClassFeatFacts.update_class(acc, class_id, fn class ->
        %{class | class_skills: MapSet.put(class.class_skills, skill_id)}
      end)
    end)
  end

  # ------------------------------------------------------------- skill rules --

  # The two skill rules that reach a character sheet, plus nothing else.
  #
  #   * **Spellcraft adds to every saving throw** — +1 per 5 ranks. Vanilla
  #     (`fandom:Spellcraft`), stated in `vanilla/skills.json` only as prose
  #     inside `check_raw`, so the machine-readable form lives in the hand
  #     written layer. Players do not count it, which is why CLAUDE.md §3
  #     requires showing it.
  #   * **Hide and Move Silently lose 1 per level of a non-stealth class** in a
  #     build of four classes. The only rule about skills that depends on the
  #     shape of the whole build.
  #   * **A class ability that adds its own class level to one skill** — the
  #     Harper Scout's Bardic Knowledge, and so far only it.
  #
  # All are read only when `verified`; an `unclear` record stays a gap instead
  # of quietly becoming a rule.
  def skill_rules(shard_skills, ov) do
    %{
      save_bonus: save_bonus_rules(ov),
      stealth_multiclass_penalty: stealth_penalty_rule(shard_skills),
      class_level_bonuses: class_level_bonus_rules(shard_skills)
    }
  end

  # «Способность … предоставляет персонажу бонус, равный его уровню класса ко
  # всем проверкам навыка Знание (Lore)» — Bardic Knowledge of the Harper Scout
  # (`siala_41/skills.json`, `verified`, `revid 19414`). The fact was in the data
  # from the day the shard layer landed and nothing read it: a Harper Scout 5
  # with 12 ranks of Lore was shown 14 where the game rolls 19.
  #
  # Matched by the **shape of the value** — a class id plus `bonus:
  # "class_level"` — and not by the fact's own name, so a second such ability on
  # another page arrives as a rule with no code change here. The ability is
  # handed over at a class level, and below it there is no bonus at all, which is
  # why `granted_at_class_level` is carried rather than assumed to be 1.
  #
  # ⚠ **A change that declares itself counted elsewhere builds no rule**, and the
  # only one that does today is the very fact quoted above. Dan's F7 measurement
  # (16.08.2026) showed the shard page states half of the ability: the bonus is the
  # **sum** of the Bard's and the Harper Scout's levels, which now arrives from
  # `vanilla/feat_skill_bonuses.json`, and the shard's own contribution — the grant
  # moving to class level 2 — is already in `siala_41/classes.json` as a
  # `feat_level_shift`. Both halves counted, so a rule here would be the Harper's
  # levels counted twice. ⚠ The record is **kept** rather than deleted: its quote
  # and revid are the only evidence the shard has the ability at all, and the
  # pointer is verified against the markup by `verify_skill_class_bonuses!/3` —
  # «counted elsewhere» pointing at nothing would be the quietest possible way to
  # lose a bonus.
  defp class_level_bonus_rules(%{"skills" => entries}) when is_list(entries) do
    for entry <- entries,
        skill = atom(entry["vanilla_id"] || entry["id"]),
        change <- entry["changes"] || [],
        change["status"] == "verified",
        is_nil(change["counted_elsewhere"]),
        value = change["value"],
        is_map(value),
        value["bonus"] == "class_level",
        class = value["class"],
        is_binary(class) do
      %{
        skill: skill,
        class: atom(class),
        from_class_level: max(value["granted_at_class_level"] || 1, 1),
        # The change this rule was read off, so `apply_skill_layer/3` can mark it
        # applied instead of reporting it as a caveat that never got a home.
        what: change["what"]
      }
    end
  end

  defp class_level_bonus_rules(_absent), do: []

  # Изменения слоя навыков, которые считает **не этот слой**, а запись разметки
  # прибавок — `changes[].counted_elsewhere` с именем записи.
  #
  # Читается из файла, а не выводится из правил, и это не то же самое, чем
  # занимается `applied` в `apply_skill_layer/3`: там речь про «стало ли
  # правилом» (и вывод из самих правил защищает от расхождения), а здесь — про
  # «считает другой файл», чего правила этого слоя знать не могут по построению.
  # Утверждение при этом проверяемо и проверяется — `verify_skill_class_bonuses!/3`
  # разрешает указатель против готовой разметки.
  defp skill_changes_counted_elsewhere(%{"skills" => entries}) when is_list(entries) do
    for entry <- entries,
        skill = atom(entry["vanilla_id"] || entry["id"]),
        change <- entry["changes"] || [],
        %{"record" => record} when is_binary(record) <- [change["counted_elsewhere"]] do
      %{
        skill: skill,
        what: change["what"],
        record: atom(record),
        class: atom_or_nil(dig(change, ["value", "class"]))
      }
    end
  end

  defp skill_changes_counted_elsewhere(_absent), do: []

  # Два утверждения, каждое из которых иначе разошлось бы молча.
  #
  #   * **указатель ведёт куда-то.** «Учтено вон там» — единственная пометка,
  #     которая ОДНОВРЕМЕННО убирает правило и убирает оговорку: ошибись в имени
  #     записи, и факт исчезнет целиком, не оставив ни числа, ни следа. Поэтому
  #     запись обязана существовать, быть `applied` и покрывать ровно тот навык
  #     и тот класс, о которых говорит изменение;
  #   * **одна пара «класс + навык» не считается дважды.** Ровно та поломка, ради
  #     которой правка F7 и делалась: правило слоя навыков и запись разметки
  #     считают одно и то же умение, и оживи оба разом — уровни Арфиста легли бы
  #     в Lore вторым разом. Число выросло бы правдоподобно, и заметить это было
  #     бы нечем.
  def verify_skill_class_bonuses!(rules, skill_bonuses, shard_skills) do
    sums =
      for record <- skill_bonuses.applied,
          match?(%{amount: %{kind: :class_level_sum}}, record),
          do: record

    for rule <- rules,
        record <- sums,
        rule.skill in record.skills,
        rule.class in record.amount.classes do
      raise "siala_41/skills.json: #{rule.skill}/#{rule.what} counts #{rule.class} levels, and " <>
              "so does #{record.id} in feat_skill_bonuses.json — the skill would carry them " <>
              "twice. One of the two has to declare itself `counted_elsewhere`"
    end

    for pointer <- skill_changes_counted_elsewhere(shard_skills) do
      record = Enum.find(sums, &(&1.id == pointer.record))

      cond do
        is_nil(record) ->
          raise "siala_41/skills.json: #{pointer.skill}/#{pointer.what} says #{pointer.record} " <>
                  "counts it instead, and no `applied` record of feat_skill_bonuses.json by " <>
                  "that name adds up class levels"

        pointer.skill not in record.skills ->
          raise "siala_41/skills.json: #{pointer.skill}/#{pointer.what} points at " <>
                  "#{pointer.record}, which does not add to #{pointer.skill} at all"

        not is_nil(pointer.class) and pointer.class not in record.amount.classes ->
          raise "siala_41/skills.json: #{pointer.skill}/#{pointer.what} points at " <>
                  "#{pointer.record}, which does not count #{pointer.class} levels"

        true ->
          :ok
      end
    end
  end

  defp save_bonus_rules(ov) do
    for rule <- dig(ov, ["_vanilla_constants_confirmed", "skill_save_bonus", "rules"]) || [],
        rule["status"] == "verified",
        is_integer(rule["bonus"]),
        is_integer(rule["per_ranks"]),
        rule["per_ranks"] > 0 do
      %{
        skill: atom(rule["skill"]),
        bonus: rule["bonus"],
        per_ranks: rule["per_ranks"],
        applies_to: Enum.map(rule["applies_to"] || [], &atom/1),
        # Whether the bonus is clipped together with the ones from equipment.
        # `source: user` — no wiki page says it, and it changes the number for
        # exactly the builds pushed to the ceiling.
        counts_toward_cap: atom_or_nil(dig(rule, ["counts_toward_cap", "value"])),
        # The bonus is conditional in both rulesets — vanilla gives it against
        # spells only, and the shard narrows it further (nothing against area
        # spells, Implosion excepted). The condition is deliberately **not**
        # modelled: a decision, not an oversight, so it is carried and reported
        # rather than dropped. `nil` would mean "applies to everything", which is
        # a different statement. See `Rules.compute/2`.
        scope: dig(rule, ["scope", "value"]),
        scope_excludes: dig(rule, ["scope", "siala_excludes"])
      }
    end
  end

  defp stealth_penalty_rule(%{"global" => entries}) when is_list(entries) do
    entry =
      Enum.find(entries, fn e ->
        e["what"] == "multiclass_stealth_penalty" and e["status"] == "verified"
      end)

    case entry && entry["value"] do
      %{} = value ->
        %{
          skills: Enum.map(value["applies_to"] || [], &atom/1),
          # The wiki says "при наличии 4 классов"; `max_classes` makes five
          # impossible, so the comparison never actually differs from equality.
          classes_in_build: value["applies_when_classes_in_build"],
          penalty_per_level: value["penalty_per_level"],
          profile_classes: MapSet.new(value["profile_classes"] || [], &atom/1)
        }

      _absent ->
        nil
    end
  end

  defp stealth_penalty_rule(_absent), do: nil
end
