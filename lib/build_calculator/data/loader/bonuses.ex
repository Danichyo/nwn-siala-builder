defmodule BuildCalculator.Data.Loader.Bonuses do
  @moduledoc """
  Семь читателей разметки «что прибавляет к …»: к навыку, к HP, к AC,
  к характеристикам, к спасброскам, к броску атаки и к сопротивлению заклинаниям.

  У них один скелет и семь префиксов, и это **не** случайное дублирование: у каждого
  свои ключи, и каждый ключ кодирует настоящее решение — тип AC, сторона капа,
  условие по оружию, запрет потолка у HP. Задача 3.46 (заход 2) развела эти две
  половины: одинаковый скелет уехал в `Loader.BonusMarkup` (идентичность записи,
  провенанс, вердикт, имя, форма величины), а здесь остались **доменные читатели** —
  ровно то, на что семь файлов отвечают по-разному.

  Каждый раздел устроен одинаково и читается сверху вниз: длинное объяснение файла
  → `@applied_*_kinds` (какие формы величины ядро умеет считать) → поля-источники →
  словарь вердиктов → паспорт читателя `@*_reader` → `build_*/2` в одну строку →
  запись → доменные читатели её полей.

  ⚠ Имя файла живёт в разделе ДВАЖДЫ: атрибутом `@*_file` (его читает хребет) и
  строковым литералом в собственных сообщениях раздела. Второе оставлено нарочно —
  сообщение сторожа ищут `grep`'ом по тексту, который увидели в падении, — но
  переименование файла разметки обязано тронуть оба, и одно без другого разъедется
  молча.
  """

  alias BuildCalculator.Data.Loader.BonusMarkup
  alias BuildCalculator.Data.Loader.Character
  alias BuildCalculator.Rules.Attack

  import BuildCalculator.Data.Loader.Reading

  # ------------------------------------------------ what adds to a skill --

  # `priv/rules/vanilla/feat_skill_bonuses.json` — hand written, and hand written
  # for a reason that is worth stating once: **the corpus has no field for this.**
  # All 299 records of `feats.json` carry the connection "this feat adds N to
  # skill X" only inside English prose (`description`), and the single
  # machine-readable hook near it — `repeatable.choice == "skill"` — names the
  # *parameter* a feat is taken with, never the size of its bonus.
  #
  # The cost of that was not a wrong number, it was silence. A feat's own effect
  # is reported as `{:not_modelled, {:feat_bonus, id}}` only for feats that
  # **repeat** (`Rules.FeatChoices.gaps/3`), and not one of the seventeen feats
  # that hand out a flat skill bonus repeats. So `Alertness` used to reach a
  # character sheet as nothing whatsoever: two points missing from Spot, and no
  # gap anywhere saying so.
  #
  # Four verdicts, and telling them apart is the whole reason this is a file and
  # not a regular expression over `description`:
  #
  #   * `applied` — number and skills both named, no condition. Counted.
  #   * `counted_elsewhere` — the nine racial affinities (`Skill affinity
  #     (spot)` and friends). ⚠ Their +2 is **already** on the character through
  #     `races.json` → `skill_bonuses`, so counting the feat as well would double
  #     every elf's Spot. They are listed rather than omitted so the next sweep
  #     does not rediscover them and "fix" the omission.
  #   * `not_modelled` — a bonus that cannot go into a number honestly: it
  #     depends on where the character is standing (`Trackless step`), on which
  #     creature is in front of him (`Favored enemy`), or the number
  #     lands on the *roll* rather than on the skill level (`Improved parry`,
  #     `Small stature`). ⚠ That last reading is the source's own:
  #     `fandom:Skill level` says the size modifier «is considered part of those
  #     specific checks, not part of the skill level». `Small stature` used to sit
  #     here as «no number on the page», which was simply wrong — both race pages
  #     name +4 for four skills — and AGENT_QUEUE §7 duly asked for that +4 to be
  #     added. Counting it would print a number the game does not even show on the
  #     character sheet. Not counted, and said out loud.
  #   * `not_a_skill_bonus` — prose that mentions a skill and grants it nothing
  #     (`Skill mastery` takes 20; `Epic prowess` merely uses the word "skill").
  #
  # ## Four kinds of source, and the one that was missing cost a caveat
  #
  # An entry names exactly one of `feat` / `class` / `skill` / `race_feat`, the
  # same four `ac_bonuses.json` and `feat_save_bonuses.json` use. ⚠ Until task
  # 3.25 this file had **only** `feat`, and that was not a simplification: the key
  # chooses the *ownership gate*, and a racial trait is deliberately absent from
  # `Build.feats_owned/3` (`Rules.Bonuses.held?/5`). So `Small stature`'s caveat
  # reached no build at all — measured before the fix on a goblin rogue with ranks
  # in all four skills: `unmodelled_feats: []` on every one of them, while
  # `ruleset.gaps` carried the caveat for *every* build including a human's. A
  # caveat that stands on everything stands on nothing.
  #
  # ## What raises at compile time
  #
  # An entry naming a feat, class, skill or racial trait that does not exist; an
  # `applied` record with no skills, no amount, an amount whose `kind` the core
  # does not compute, or no stated `cap` side; a `cap` on any other verdict; and
  # an `applied` record claiming to be **inside** the +50 ceiling, which the core
  # cannot clip (see below). This file is hand written and its whole job is to
  # stop a bonus from disappearing quietly; a typo in it doing exactly that would
  # be the joke writing itself.
  #
  # ## `counted_for_classes` is resolved per **ruleset**, not taken on trust
  #
  # ⚠ The file is one layer and there are two rulesets, and this one field talks
  # about what the *core* counts, so a named class is kept only where a rule
  # actually counts it — tested against the rules the ruleset ended up with rather
  # than against the file's own word. The direction is deliberate: an unmatched
  # name **drops** out and the caveat travels, so the failure mode is "said too
  # much" and never "went quiet".
  #
  # ⚠ **No record carries the field since 16.08.2026** and the mechanism stays all
  # the same. Its only bearer was `Bardic knowledge`, whose two implementations
  # were thought to have different fates — the Harper Scout's counted, the Bard's
  # not — and Dan's F7 measurement showed there is one implementation: the bonus is
  # the **sum** of both classes' levels, so the record became `applied` whole and
  # has nothing left to qualify. What the field answers («this record is a caveat,
  # except for builds whose only route to the feat is a class the core already
  # counts») is a real question that will be asked again.
  #
  # ## The ceiling, and why a guard stands where an implementation would
  #
  # `stat_caps.skill_bonus` (+50) does **not** cover these records, and that is
  # the source's word rather than ours: `fandom:Skill level` puts the ceiling on
  # «modifiers from items and effects» and, a paragraph later, counts a skill's
  # maximum «without bonuses from items and effects» with the focus feats' +13
  # *inside* that figure. Each `applied` record states the side itself all the
  # same (`cap`), for the reason the saves learned twice over: a kind cannot tell
  # `Divine grace` from `Sacred defense`.
  #
  # ⚠ And `inside_cap: true` **raises**. `Rules.Skills` clips a pool of exactly two
  # addends — what the player typed and the shard's racial bonus — and adds a feat's
  # bonus on top of the clip; a record promoted to the inside would sail past the
  # ceiling in silence. Same device `@applied_ac_bonus_kinds`'s `dodge` clause uses
  # next door, and for the same reason: there is nothing to implement today, and a
  # guard is honest where untested arithmetic would not be.
  #
  # ## The skill a record does not name — `skills_from` (task 3.92)
  #
  # `Skill focus` and `Epic skill focus` add +3 and +10 to a skill the page
  # cannot name, because the player names it: the pick carries the pair
  # (`{:skill_focus, :discipline}`) and the feat's `repeatable.choice` says that
  # parameter is a skill id. Both used to sit under `not_modelled` for exactly
  # that reason, and the cost was silence — thirteen points missing from the row
  # a player reads first. Dan's decision on 25.08.2026 was to count them: «данные
  # фиты, как и любые другие фиты, увеличивающие скиллы, нужно плюсовать
  # в скиллах».
  #
  # So the record states `skills_from: "feat_choice"` and leaves `skills` empty,
  # and the receiver is worked out per build rather than per page
  # (`Rules.Skills.feat_bonuses/3`). Four things raise around it — see
  # `skills_from!/3` — and all four are the same failure: two answers to «кому
  # прибавили».
  #
  # ⚠ **And it is resolved per ruleset, not taken on trust**, exactly like
  # `counted_for_classes` above. «The pick names the skill» is only true where
  # the ruleset says the feat *takes* one, and `Epic skill focus` is repeatable
  # on Siala (a manual layer, Dan's word) and not on vanilla, where Fandom
  # carries no `repeatable` block at all. Where it cannot be resolved the record
  # drops back into the rejected half — the caveat stays alive instead of
  # vanishing beside a number that was never added.
  #
  # ## Which shapes of `amount` may be `applied`, and who reads each
  #
  # Two, and they land in **different terms** of a skill's value — the shape of the
  # amount decides which, not the kind of source:
  #
  #   * `flat` → `feat_bonus`, named by the feat («Alertness +2»);
  #   * `class_level_sum` → `class_bonus`, named by the classes («Bard +7 · Harper
  #     scout +1»). The size is explained by the classes and by nothing else, so
  #     printing it under the feat's name would hide the only thing that explains
  #     it (`Rules.Skills.class_bonuses/3`).
  #
  # ⚠ `class_level_sum` joined the list on 16.08.2026 with Dan's F7 measurement,
  # and until then this guard was doing its job: the shape was carried as material
  # nothing computed, and promoting it to `applied` failed the build rather than
  # adding a silent zero. The guard stays for the next shape that arrives before
  # its reader does — today it refuses nothing, which is what a guard looks like
  # when the implementation caught up with the data.
  @applied_skill_bonus_kinds ~w(flat class_level_sum)

  @skill_file "feat_skill_bonuses.json"
  @skill_bonus_sources ~w(feat class skill race_feat)

  @skill_bonus_verdicts %{
    "applied" => :applied,
    "counted_elsewhere" => :counted_elsewhere,
    "not_modelled" => :not_modelled,
    "not_a_skill_bonus" => :not_a_skill_bonus
  }

  @skill_reader %{
    file: @skill_file,
    keys: @skill_bonus_sources,
    verdicts: @skill_bonus_verdicts
  }

  def build_skill_bonuses(shape, dictionaries) do
    shape
    |> BonusMarkup.build(dictionaries, &skill_bonus_record/2)
    |> resolve_choice_driven(dictionaries)
  end

  defp skill_bonus_record(entry, dictionaries) do
    BonusMarkup.record(@skill_reader, entry, dictionaries, fn entry, verdict, name ->
      %{
        skills: skill_bonus_skills!(entry, verdict, name, dictionaries),
        # Where the receiving skill comes from when the page names none. `nil` is
        # "the record names its skills itself"; `:feat_choice` is "the pick does".
        skills_from: skills_from!(entry, verdict, name),
        amount: skill_bonus_amount(entry, verdict, name, dictionaries),
        # Same contract as its four siblings: the claim is the data's
        # (`effect_coverage: "whole_feat"`), never inferred from the bonus being
        # applied. `Blooded` and `Thug` are `applied` here and `false` — each also
        # raises initiative, which is nobody's number — and `Artist` is `false`
        # because Fandom's Notes name a third skill Siala's page does not (the
        # record says so in full).
        covers_feat?: entry["effect_coverage"] == "whole_feat",
        # Which side of `stat_caps.skill_bonus` this record falls on — required on
        # `applied`, forbidden elsewhere. See `Character.cap_side!/4` and the guard
        # beside it — since task 3.46 it is one module over, not further down.
        cap: skill_bonus_cap!(entry, verdict, name),
        # Classes whose version of this ability the core already counts, resolved
        # against the rules **this** ruleset ended up with rather than trusted.
        counted_for_classes: counted_for_classes(entry, verdict, name, dictionaries)
      }
    end)
  end

  # Required and non-empty on `applied` — a bonus nobody says which skill it lands
  # on is not honestly a bonus. Elsewhere it is whatever the source named, `[]`
  # included: an empty list is the statement «the page names no skill»
  # (`Oath of wrath`'s is "skills" wholesale), and the caveat machinery reads it
  # as such.
  #
  # ⚠ One exception, and it is stated by the record rather than assumed here:
  # `skills_from: "feat_choice"` says the receiver comes from the **pick**
  # (`Skill focus (discipline)`), so an empty list is the honest shape and the
  # two answers must not both be given — see `skills_from!/3`.
  defp skill_bonus_skills!(entry, :applied, name, dictionaries) do
    case {skill_bonus_skill_list!(entry, name, dictionaries), entry["skills_from"]} do
      {[], nil} ->
        raise "feat_skill_bonuses.json: #{name} is `applied` but names no skill"

      {skills, _from} ->
        skills
    end
  end

  defp skill_bonus_skills!(entry, _verdict, name, dictionaries),
    do: skill_bonus_skill_list!(entry, name, dictionaries)

  defp skill_bonus_skill_list!(entry, name, dictionaries) do
    for target <- entry["skills"] || [] do
      BonusMarkup.id!(@skill_file, name, target, dictionaries, :skill)
    end
  end

  # Откуда берётся навык-получатель, когда страница его не называет. Значение
  # ровно одно, и оно не «поле про запас»: `feat_choice` — навык приходит из
  # ВЫБОРА, сделанного при взятии фита, и знает его только пик билда
  # (`Skill focus (discipline)`). Читает его `Rules.Skills.feat_bonuses/3`.
  #
  # ⚠ Четыре сторожа, и каждый закрывает одно и то же: **два ответа на один
  # вопрос «кому прибавили»**.
  #
  #   * не `applied` — у неприменяемой записи получателя не спрашивают вовсе,
  #     а адресную оговорку собирает `Rules.Skills.feats_by_skill/3` по пикам
  #     напрямую;
  #   * `skills` непуст — страница НАЗВАЛА навыки, и брать их ещё и из пика
  #     значило бы прибавить дважды;
  #   * источник не `feat` — у класса, навыка и расовой склонности пиков нет,
  #     и спрашивать выбор было бы не у кого;
  #   * `amount.kind` не `flat` — плоское число ложится термом `feat_bonus`,
  #     подписанным именем фита (`Rules.Skills.term_of/1`), а `class_level_sum`
  #     ложится термом классов; выбор навыка со второй формой сегодня не
  #     сочетается ничем, и молчаливое «сойдёт» здесь было бы догадкой.
  defp skills_from!(entry, verdict, name) do
    case entry["skills_from"] do
      nil ->
        nil

      "feat_choice" ->
        skill_require!(verdict == :applied, name, "states skills_from on a `#{verdict}` record")

        skill_require!(
          entry["skills"] in [nil, []],
          name,
          "states skills_from and names skills too"
        )

        skill_require!(is_binary(entry["feat"]), name, "states skills_from without naming a feat")

        skill_require!(
          get_in(entry, ["amount", "kind"]) == "flat",
          name,
          "states skills_from with amount kind " <>
            "#{inspect(get_in(entry, ["amount", "kind"]))}, and only a flat bonus lands in the " <>
            "term a feat's name signs"
        )

        :feat_choice

      other ->
        raise "feat_skill_bonuses.json: #{name} states skills_from #{inspect(other)}, " <>
                "which this loader does not know"
    end
  end

  defp skill_require!(true, _name, _what), do: :ok

  defp skill_require!(false, name, what),
    do: raise("feat_skill_bonuses.json: #{name} #{what}")

  # ⚠ РЕЗОЛВИТСЯ ПО RULESET-У, ровно как `counted_for_classes/4` рядом, и по той
  # же причине: файл разметки один, а ruleset-а два, и «навык приходит из
  # выбора» верно только там, где у фита этот выбор ЕСТЬ
  # (`repeatable.choice == :skill`). Где его нет, получателя назвать нечем,
  # и запись опускается обратно в отвергнутую половину — то есть оговорка
  # остаётся жить, а не пропадает вместе с числом.
  #
  # Сегодня это случается ровно раз: `epic_skill_focus` на `vanilla`. Блок
  # `repeatable` у него приходит ручным слоем Сиалы (Dan, 02.08.2026), а на
  # Fandom его нет вовсе, так что на ванили выбор не записывается и +10 повесить
  # не на что. `skill_focus` повторяем на обоих.
  #
  # ⚠ Направление ошибки выбрано то же, что у соседа: несошедшийся факт
  # ОПУСКАЕТ запись, то есть провал выглядит как «сказали лишнее», и никогда
  # как «замолчали». Обратное направление — оставить запись применяемой —
  # молча прибавляло бы ноль и снимало бы оговорку заодно.
  defp resolve_choice_driven(%{applied: applied, unmodelled: unmodelled} = buckets, dictionaries) do
    {kept, unresolved} = Enum.split_with(applied, &choice_resolvable?(&1, dictionaries))

    %{
      buckets
      | applied: kept,
        unmodelled: unmodelled ++ Enum.map(unresolved, &%{&1 | verdict: :not_modelled})
    }
  end

  defp choice_resolvable?(%{skills_from: :feat_choice, source: {:feat, id}}, dictionaries),
    do: match?(%{repeatable: %{choice: :skill}}, Map.get(dictionaries.feats, id))

  defp choice_resolvable?(_record, _dictionaries), do: true

  defp skill_bonus_amount(entry, verdict, name, dictionaries) do
    BonusMarkup.amount!(
      @skill_file,
      name,
      verdict,
      @applied_skill_bonus_kinds,
      skill_amount(entry, name, dictionaries)
    )
  end

  # ⚠ Здесь стояло «`class_level_sum` is carried as material and computed by
  # nobody» — устарело 16.08.2026 (замер F7): форма считается, её читает
  # `Rules.Skills.class_bonuses/3`, а `classes` — это ровно те классы, чьи уровни
  # складываются («Harper scout and bard levels stack for the bonus granted by
  # this feat»). Формой, которую не читает никто, остался `per_class_level`
  # в файле HP, и сторож `@applied_skill_bonus_kinds` выше по-прежнему про это.
  defp skill_amount(%{"amount" => %{"kind" => "flat"} = amount}, name, _dictionaries) do
    %{kind: :flat, bonus: skill_bonus_number!(name, amount["bonus"])}
  end

  defp skill_amount(%{"amount" => %{"kind" => "class_level_sum"} = amount}, name, dictionaries) do
    %{
      kind: :class_level_sum,
      classes: skill_bonus_classes!(name, amount["classes"], dictionaries)
    }
  end

  defp skill_amount(%{"amount" => %{} = amount}, name, _dictionaries) do
    raise "feat_skill_bonuses.json: #{name} states amount kind " <>
            "#{inspect(amount["kind"])}, which this loader does not know"
  end

  defp skill_amount(_entry, _name, _dictionaries), do: nil

  defp skill_bonus_number!(name, value),
    do: BonusMarkup.number!(@skill_file, name, value, "a whole number")

  # ⚠ Сверяется со словарём классов с 16.08.2026, и это не аккуратность ради
  # аккуратности. Здесь стояло «Not checked against the class dictionary here on
  # purpose: the amount is material nothing computes» — довод верен ровно до того
  # дня, когда форму начали считать: с F7 опечатка в имени класса не роняет
  # сборку, а МОЛЧА ВЫЧИТАЕТ его уровни из суммы, то есть даёт правдоподобное
  # число вместо верного. Ровно та поломка, ради которой весь этот файл и заведён.
  defp skill_bonus_classes!(name, classes, dictionaries)
       when is_list(classes) and classes != [] do
    for class <- classes, do: BonusMarkup.id!(@skill_file, name, class, dictionaries, :class)
  end

  defp skill_bonus_classes!(name, other, _dictionaries) do
    raise "feat_skill_bonuses.json: #{name} states classes #{inspect(other)} " <>
            "where a non-empty list was expected"
  end

  # ⚠ One value allowed and the other raises, which is unusual for a `cap` and
  # deliberate: the side is data, the *clip* is code, and `Rules.Skills` has none
  # for a record of this file. See the section note above.
  defp skill_bonus_cap!(entry, verdict, name) do
    case Character.cap_side!(@skill_file, name, entry, verdict) do
      %{inside?: true} ->
        raise "feat_skill_bonuses.json: #{name} claims to be inside " <>
                "stat_caps.skill_bonus, and Rules.Skills clips only the pool of gear and the " <>
                "shard's racial bonus — the bonus would pass the ceiling in silence. Implement " <>
                "the clip before stating this side; see _cap_decision in the file"

      side ->
        side
    end
  end

  # The classes whose version of this ability the core really does count, out of
  # the ones the entry names. See the note above for why the file's own word is not
  # enough.
  #
  # A class must be counted for **every** skill the entry lists, because the
  # caveat is all-or-nothing across them (`Rules.Skills.feats_by_skill/3` gates
  # once per record, not once per skill). No entry names two skills today; the day
  # one does, "counted for one of them" must not silence the other.
  defp counted_for_classes(entry, verdict, name, dictionaries) do
    named = Enum.map(entry["counted_for_classes"] || [], &atom/1)

    if named != [] and verdict != :not_modelled do
      raise "feat_skill_bonuses.json: #{name} is `#{verdict}` and names " <>
              "counted_for_classes, which only qualifies a caveat this record does not carry"
    end

    counted =
      for class <- named do
        unless Map.has_key?(dictionaries.classes, class) do
          raise "feat_skill_bonuses.json: #{name} says #{class} counts it, " <>
                  "which is not a class"
        end

        class
      end

    targets = skill_bonus_skill_list!(entry, name, dictionaries)

    for class <- counted,
        Enum.all?(targets, fn skill ->
          Enum.any?(dictionaries.class_level_bonuses, &(&1.class == class and &1.skill == skill))
        end),
        do: class
  end

  # ------------------------------------------- what adds to hit points --

  # `priv/rules/vanilla/feat_hp_bonuses.json` — hand written for exactly the
  # reason the skill file above is: **the corpus has no field for it.** All 299
  # records of `feats.json` carry "this feat adds N hit points" only inside
  # English prose, and the one machine-readable hook nearby (`repeatable`) says
  # how many times `Epic toughness` may be taken, never what a take is worth.
  #
  # The cost of that was a wrong number *and* silence, which is the worse pair.
  # On Siala nine classes hand `Toughness` out at their own first level, so
  # almost every martial build was 41 hit points short at the cap — and the
  # honesty mechanism said nothing, because `{:not_modelled, {:feat_bonus, …}}`
  # is only ever produced for feats the data marks **repeatable**
  # (`Rules.FeatChoices.gaps/3`) and plain `Toughness` is not one.
  #
  # Three shapes of amount, because the corpus states three (see the file's
  # `_amount_kinds`): per character level, per take with a ceiling on the
  # effect, and — described but deliberately not applied — steps at named
  # levels of a named class.
  #
  # ## No ceiling, and therefore no `cap`
  #
  # ⚠ `cap` on a record of this file **raises**, and that is the opposite of the
  # save and attack files rather than an omission: no ruleset states a ceiling on
  # hit points at all (`stat_caps` names five, and none of them is this), so a
  # stated side would be a claim about a ceiling nobody wrote down. Not to be
  # confused with `Epic toughness`'s `max_total: 200`, which is a ceiling on **one
  # effect**, named by its own page and living inside `amount`.
  #
  # ⚠ Anything the file states and this cannot express **raises at compile
  # time**: an unknown feat, class, skill or racial trait, an `applied` record
  # with no amount, an amount whose `kind` the core does not compute. A markup
  # file whose whole job is to stop a bonus disappearing quietly must not be able
  # to drop one itself.
  #
  # ## Разметка `affects`
  #
  # See `BonusMarkup.record/4` for the field's shape and why it is not
  # atomised. Always `nil` here today: no `not_modelled` record survives
  # in this file as of 16.08.2026 (task 3.37), so there is nothing to
  # label yet — see `_schema.affects` in the file itself.
  @applied_hp_bonus_kinds ~w(per_character_level per_take per_class_level)

  @hp_file "feat_hp_bonuses.json"
  @hp_bonus_sources ~w(feat class skill race_feat)

  @hp_bonus_verdicts %{
    "applied" => :applied,
    "counted_elsewhere" => :counted_elsewhere,
    "not_modelled" => :not_modelled,
    "not_a_hp_bonus" => :not_a_hp_bonus
  }

  @hp_reader %{
    file: @hp_file,
    keys: @hp_bonus_sources,
    verdicts: @hp_bonus_verdicts,
    guard: &__MODULE__.hp_bonus_cap_forbidden!/2
  }

  def build_hp_bonuses(shape, dictionaries),
    do: BonusMarkup.build(shape, dictionaries, &hp_bonus_record/2)

  defp hp_bonus_record(entry, dictionaries) do
    BonusMarkup.record(@hp_reader, entry, dictionaries, fn entry, verdict, name ->
      %{
        amount: hp_bonus_amount(entry, verdict, name, dictionaries),
        # `Toughness` and `Epic toughness` are both `whole_feat`: their pages name
        # nothing else either does. Read from the data like its five siblings, never
        # inferred from the bonus being applied.
        covers_feat?: entry["effect_coverage"] == "whole_feat"
      }
    end)
  end

  # ⚠ `per_class_level` joined the applied kinds on 13.08.2026, and the comment
  # that stood here said the opposite — that the shape was described but not
  # computed, so listing it as applied would contribute a silent zero. That was
  # true until the measurement: a Wizard 5 / Pale Master 5 with CON 10 shows 73
  # in game and 70 here (`GAME_CHECKS.md`, D1), and the missing 3 is the first
  # step of `Deathless vigor`. Nothing had to be invented — the steps were
  # transcribed in full and verified against two Fandom pages long before;
  # `FeatBonuses.hp_term/4` now sums the ones a build has reached.
  defp hp_bonus_amount(entry, verdict, name, dictionaries) do
    BonusMarkup.amount!(
      @hp_file,
      name,
      verdict,
      @applied_hp_bonus_kinds,
      hp_amount(entry, name, dictionaries)
    )
  end

  # No ruleset states a ceiling on hit points, so a side of one is a statement
  # about nothing — see the section note and the file's `_cap_decision`.
  #
  # ⚠ Публичная только потому, что стоит в `@hp_reader` захватом `&__MODULE__.…/2`,
  # и это единственный способ положить функцию своего же модуля в атрибут. Зовёт
  # её `BonusMarkup.record/4` и никто больше.
  @doc false
  def hp_bonus_cap_forbidden!(entry, name),
    do: BonusMarkup.cap_forbidden!(@hp_file, name, entry, "hit points")

  defp hp_amount(%{"amount" => %{} = amount}, name, dictionaries) do
    case amount["kind"] do
      "per_character_level" ->
        %{kind: :per_character_level, hp: hp_number!(name, amount["hp"])}

      "per_take" ->
        %{
          kind: :per_take,
          hp: hp_number!(name, amount["hp"]),
          max_total: hp_number!(name, amount["max_total"])
        }

      "per_class_level" ->
        %{
          kind: :per_class_level,
          class: BonusMarkup.id!(@hp_file, name, amount["class"], dictionaries, :class),
          hp_at_class_level: hp_steps!(name, amount["hp_at_class_level"])
        }

      other ->
        raise "feat_hp_bonuses.json: #{name} states amount kind " <>
                "#{inspect(other)}, which this loader does not know"
    end
  end

  defp hp_amount(_entry, _name, _dictionaries), do: nil

  defp hp_number!(name, value),
    do: BonusMarkup.number!(@hp_file, name, value, "a whole number of hit points")

  defp hp_steps!(name, steps),
    do: BonusMarkup.steps!(@hp_file, name, steps, "hit points", &hp_number!(name, &1))

  # ----------------------------------------------- what adds to armour class --

  # `priv/rules/vanilla/ac_bonuses.json` — hand written for the third time and
  # for the third time because **the corpus has no field for it**. A sweep of
  # 507 records across nine files found the connection "this adds N to armour
  # class" only ever in prose: a feat's `description`, a column of a class's
  # progression table, a skill's `description`, a race's `skill_bonuses_prose`.
  #
  # The cost was the familiar pair — a wrong number *and* silence. Every build
  # in the calculator carried `AC = 10 + dexterity`, and the honesty mechanism
  # said nothing at all: `Vocabulary` had `{:assumed, :base_ac, 10}` and
  # `{:missing_data, {:stat_cap, :ac}}` and not one form about a class ability.
  # A Cleric 35 / Monk 4 — a build the shard's players take *for its AC*, four
  # monk levels precisely because Siala moved the bonus from the first — showed
  # 10 and an empty `gaps`.
  #
  # ## Four sources, not one, and that is the point
  #
  # An entry names exactly one of `feat` / `class` / `skill` / `race_feat`, and
  # the four cannot be folded into one. A Monk has **two** independent armour
  # class bonuses — the feat (wisdom) and a column of the class table (+1 every
  # five levels) — and Siala moved only the feat, from class level 1 to 4. Key
  # them both off the feat and the shard's own change becomes unrepresentable.
  #
  # ## What raises at compile time
  #
  # An unknown feat, class, skill or race trait; an `applied` record with no
  # amount, with an amount whose `kind` is unknown, or missing the mandatory
  # `type` key; an amount naming an ability or a skill that does not exist.
  #
  # ⚠ Here stood one rule more: an `applied` record of the **capped** type
  # (`dodge`) used to raise, because the core applied that ceiling to the number
  # the player typed alone and a bonus added afterwards would have sailed past it
  # in silence. It was a guard standing in for an implementation, and task 3.39
  # wrote the implementation: a capped type is summed across the build's own
  # bonuses and the typed number and clipped **once**
  # (`Rules.ArmorClass.geared/3`). Keeping the guard would now refuse correct
  # data with a reason that is no longer true. Still no record is of that type
  # today — every source saying the word is conditional — so the rule is under a
  # test with a doctored ruleset instead of under a compile-time refusal.
  @applied_ac_bonus_kinds ~w(flat ability_modifier ac_at_class_level per_skill_ranks)

  @ac_file "ac_bonuses.json"
  @ac_bonus_sources ~w(feat class skill race_feat)

  @ac_bonus_verdicts %{
    "applied" => :applied,
    "counted_elsewhere" => :counted_elsewhere,
    "not_modelled" => :not_modelled,
    "not_an_ac_bonus" => :not_an_ac_bonus
  }

  @ac_reader %{
    file: @ac_file,
    keys: @ac_bonus_sources,
    verdicts: @ac_bonus_verdicts
  }

  def build_ac_bonuses(shape, dictionaries),
    do: BonusMarkup.build(shape, dictionaries, &ac_bonus_record/2)

  # ⚠ Единственный из семи, у кого НЕТ `covers_feat?`, и это не забывчивость:
  # у AC вопрос «называет ли страница что-то ещё, чего мы не считаем» никто
  # не задавал, а дорисовать ключ значило бы положить в ruleset поле, которого
  # там никогда не было. Хребет поэтому его и не ставит — см. `BonusMarkup.record/4`.
  defp ac_bonus_record(entry, dictionaries) do
    BonusMarkup.record(@ac_reader, entry, dictionaries, fn entry, verdict, name ->
      type = ac_bonus_type!(entry, verdict, name)

      %{
        type: type,
        amount: ac_bonus_amount(entry, verdict, name, dictionaries),
        # The condition under which the game takes the bonus away. `nil` for
        # everything unconditional; otherwise a shape the rules core either applies
        # or declares unchecked — see `ac_bonus_scope!/3`.
        scope: ac_bonus_scope!(entry, name, dictionaries),
        # Whether this bonus's behaviour beside its neighbours has been
        # confirmed — see `ac_stacking_confirmed!/4`. `nil` on everything that
        # has not.
        stacking_confirmed: ac_stacking_confirmed!(entry, verdict, type, name)
      }
    end)
  end

  # `bonuses[].stacking_confirmed` — «как эта прибавка ведёт себя рядом
  # с соседями, подтверждено». Задача 3.90, 25.08.2026.
  #
  # Тип решает ровно две вещи: столкнётся ли прибавка с другой и попадёт ли под
  # потолок. У четырёх записей без типа столкновений ровно четыре, и все четыре
  # отвечены поимённо (`_stacking_confirmed_decision`), поэтому отметка снимает
  # с записи `{:assumed, :ac_bonus_types_unstated}`.
  #
  # 🔴 **Отметка НЕ называет тип и не может его назвать.** Поле `type` остаётся
  # `nil`, правило записи типа (`_type_decision.rule`) не тронуто: тип пишется,
  # только когда источник назвал его словом. Имя поля выбрано так, чтобы
  # перепутать было нельзя — подтверждено СКЛАДЫВАНИЕ, а не тип.
  #
  # 🔴 **Признак на ЗАПИСИ, а не выключатель на механизме**, и в этом вся
  # задача: парсер принесёт новую прибавку без названного типа — у неё отметки
  # не будет, и оговорка вернётся сама. «Мы это выяснили» не имеет права стать
  # вечным «мы это знаем».
  #
  # Что роняет сборку, и по тому же доводу, что у `not_a_gap`
  # (`BonusMarkup.verify_not_a_gap!/3`): отметка снимает признание
  # в неуверенности, то есть это единственный способ уменьшить число, которое
  # калькулятор показывает игроку, НЕ посчитав ничего нового.
  #
  #   * отметка на записи с вердиктом кроме `applied` — у прибавки, которой
  #     никто не считает, соседей нет и подтверждать нечего;
  #   * отметка на записи с **названным** типом — там на вопрос отвечает тип,
  #     а отметка не делала бы ничего. Молчаливый холостой ход — ровно то, ради
  #     чего сторожи этого файла и стоят;
  #   * пустой `what` — без него через полгода не прочитать, ЧТО именно
  #     подтверждено, и отметка становится «нам сказали, что всё хорошо»;
  #   * пустой `why`;
  #   * `status` не `verified`;
  #   * `source` без `kind`, `who` или `date` — факт, снимающий оговорку
  #     с экрана, обязан быть прослеживаемым (CLAUDE.md §3).
  #
  # ⚠ **Дословная цитата обязательна не всегда, и это названо в данных**
  # (`_stacking_confirmed_decision.quote_is_not_required`). Отметка, стоящая на
  # СООБЩЕНИИ, цитату несёт (монашеская пара); отметка, стоящая на РЕШЕНИИ,
  # переданном координатором, — нет, и выдумывать её было бы хуже, чем её
  # отсутствие. Присутствующая проверяется на непустоту.
  @stacking_confirmed_source ~w(kind who date)

  defp ac_stacking_confirmed!(entry, verdict, type, name) do
    case {entry["stacking_confirmed"], verdict, type} do
      {nil, _verdict, _type} ->
        nil

      {%{} = mark, :applied, nil} ->
        stacking_mark!(mark, name)

      {%{}, :applied, type} ->
        raise "ac_bonuses.json: #{name} states `stacking_confirmed` and names " <>
                "the type #{inspect(type)}; on a typed record the type already " <>
                "answers what the mark would answer, so the mark would do nothing " <>
                "at all — and it would do it silently"

      {_present, other_verdict, _type} ->
        raise "ac_bonuses.json: #{name} is `#{other_verdict}` and states " <>
                "`stacking_confirmed`; a bonus nobody counts has no neighbours " <>
                "to stack with"
    end
  end

  defp stacking_mark!(mark, name) do
    cond do
      not mark_words?(mark["what"]) ->
        raise "ac_bonuses.json: #{name} states `stacking_confirmed` without a " <>
                "non-empty `what` — a mark that does not name WHICH collision it " <>
                "answers is «нам сказали, что всё хорошо»"

      not mark_word?(mark["why"]) ->
        raise "ac_bonuses.json: #{name} states `stacking_confirmed` without a " <>
                "non-empty `why`"

      mark["status"] != "verified" ->
        raise "ac_bonuses.json: #{name} states stacking_confirmed.status " <>
                "#{inspect(mark["status"])}; only \"verified\" takes a caveat off " <>
                "the player's screen"

      not is_map(mark["source"]) ->
        raise "ac_bonuses.json: #{name} states `stacking_confirmed` without a `source`"

      true ->
        for field <- @stacking_confirmed_source do
          unless mark_word?(mark["source"][field]) do
            raise "ac_bonuses.json: #{name} states `stacking_confirmed` whose " <>
                    "source has no non-empty `#{field}` — a fact that removes a " <>
                    "caveat can only do so with its kind, its author and its date named"
          end
        end

        unless is_nil(mark["quote"]) or mark_word?(mark["quote"]) do
          raise "ac_bonuses.json: #{name} states an empty stacking_confirmed.quote; " <>
                  "leave the key out rather than leave it blank"
        end

        mark
    end
  end

  # Непустая строка и непустой список непустых строк — только для отметки.
  # Имена узкие намеренно: в модуле семь читателей разметки, и общий `filled?`
  # рано или поздно приняли бы за общий контракт, которым он не является.
  defp mark_word?(value), do: is_binary(value) and String.trim(value) != ""

  defp mark_words?(value),
    do: is_list(value) and value != [] and Enum.all?(value, &mark_word?/1)

  # `scope` was a bare string until 09.08.2026 and the core only printed a caveat
  # about it. Dan measured what the Monk's condition actually is — «Бонус на AC
  # монаха от мудрости „ломается“, если надеть любой щит, или если надеть любой
  # доспех, который даёт AC» — and that is a rule this model can check, because
  # AC by type is exactly what the player enters. So the field became a shape.
  #
  # ⚠ A **string raises**. It has to: the core matches on `kind`, so an old-style
  # string would fall through to "a kind I cannot apply" and the condition would
  # go back to being a caveat — silently, with the number wrong in the direction
  # that flatters the build. The one shape this file must never allow is a rule
  # that quietly stops applying.
  #
  # An unknown `kind` raises for the same reason a typo in `amount.kind` does. A
  # kind that is *declared here* but which the core cannot check is a different
  # thing and is allowed: the bonus stays in the number and the build says
  # `{:not_modelled, {:ac_bonus_scope, id}}`. Today the two sets coincide.
  @ac_scope_kinds ~w(no_ac_from_worn)

  defp ac_bonus_scope!(%{"scope" => nil}, _name, _dictionaries), do: nil

  defp ac_bonus_scope!(%{"scope" => %{"kind" => kind} = scope}, name, dictionaries)
       when kind in @ac_scope_kinds do
    %{kind: atom(kind), ac_types: ac_scope_types!(name, scope["ac_types"], dictionaries)}
  end

  defp ac_bonus_scope!(%{"scope" => other}, name, _dictionaries) do
    raise "ac_bonuses.json: #{name} states scope #{inspect(other)}; expected " <>
            "an object with a kind out of #{inspect(@ac_scope_kinds)} — see _scope_kinds"
  end

  defp ac_bonus_scope!(_entry, _name, _dictionaries), do: nil

  # The AC types a condition names are checked twice, against two different
  # lists, because they answer two different questions.
  #
  #   * a type the player cannot **enter** is a typo or a renamed type;
  #   * a type nothing can be **worn** in is a condition that never fires, so
  #     the bonus would quietly become unconditional. That is the check that
  #     moved on 19.08.2026: `Rules.ArmorClass.in_scope?/3` used to read the
  #     typed number as well, and back then every enterable type could fire the
  #     condition. Now it reads `Worn.base_ac/2` alone, and only a type some
  #     worn category lands in can ever take a bonus away.
  #
  # ⚠ Both lists are tolerated empty, the way `known != []` already was: a
  # ruleset assembled without a gear block at all must not start raising about
  # a file it has nothing to check against.
  defp ac_scope_types!(name, types, dictionaries) when is_list(types) and types != [] do
    known = Map.get(dictionaries, :ac_types, [])
    wearable = Map.get(dictionaries, :worn_ac_types, [])

    for type_name <- types do
      type = atom(type_name)

      if known != [] and type not in known do
        raise "ac_bonuses.json: #{name} scopes on AC type #{type_name}, which is " <>
                "not one the player can enter (#{inspect(known)})"
      end

      if wearable != [] and type not in wearable do
        raise "ac_bonuses.json: #{name} scopes on AC type #{type_name}, which " <>
                "nothing can be worn in (#{inspect(wearable)}) — the condition " <>
                "would never fire and the bonus would be unconditional in practice"
      end

      type
    end
  end

  defp ac_scope_types!(name, other, _dictionaries) do
    raise "ac_bonuses.json: #{name} states ac_types #{inspect(other)} where a " <>
            "non-empty list of AC types was expected"
  end

  # `type` is mandatory on an applied record and may be `null` there — the two
  # are different statements, and only `Map.has_key?/2` tells them apart. A
  # record that simply forgot the key would otherwise read as "the source names
  # no type", which is a claim about the wiki page nobody made.
  defp ac_bonus_type!(entry, :applied, name) do
    unless Map.has_key?(entry, "type") do
      raise "ac_bonuses.json: #{name} is " <>
              "`applied` and states no `type` key (null is allowed, absent is not)"
    end

    ac_bonus_type!(entry, :any, name)
  end

  defp ac_bonus_type!(entry, _verdict, _name) do
    case entry["type"] do
      nil -> nil
      other when is_binary(other) -> atom(other)
    end
  end

  defp ac_bonus_amount(entry, verdict, name, dictionaries) do
    BonusMarkup.amount!(
      @ac_file,
      name,
      verdict,
      @applied_ac_bonus_kinds,
      ac_amount(entry, name, dictionaries)
    )
  end

  defp ac_amount(%{"amount" => %{} = amount}, name, dictionaries) do
    case amount["kind"] do
      "flat" ->
        %{kind: :flat, ac: ac_number!(name, amount["ac"])}

      "ability_modifier" ->
        %{
          kind: :ability_modifier,
          ability: BonusMarkup.ability!(@ac_file, name, amount["ability"])
        }

      "ac_at_class_level" ->
        %{
          kind: :ac_at_class_level,
          class: BonusMarkup.id!(@ac_file, name, amount["class"], dictionaries, :class),
          ac_at_class_level: ac_steps!(name, amount["ac_at_class_level"])
        }

      "per_skill_ranks" ->
        %{
          kind: :per_skill_ranks,
          ac: ac_number!(name, amount["ac"]),
          per_ranks: ac_positive!(name, amount["per_ranks"])
        }

      other ->
        raise "ac_bonuses.json: amount kind #{inspect(other)} is unknown to this loader"
    end
  end

  defp ac_amount(_entry, _name, _dictionaries), do: nil

  defp ac_number!(name, value),
    do: BonusMarkup.number!(@ac_file, name, value, "a whole number of armour class")

  defp ac_positive!(_name, value) when is_integer(value) and value > 0, do: value

  defp ac_positive!(name, value) do
    raise "ac_bonuses.json: #{name} states #{inspect(value)} where a " <>
            "positive number of ranks was expected"
  end

  defp ac_steps!(name, steps),
    do: BonusMarkup.steps!(@ac_file, name, steps, "AC", &ac_number!(name, &1))

  # ------------------------------------------ what adds to the ability scores --

  # `priv/rules/vanilla/feat_ability_bonuses.json` — hand written for the
  # fourth time and for the fourth time because **the corpus has no field for
  # it**. A sweep of the same 507 records found "this raises an ability score"
  # only in prose: a feat's `description` (and inside it, for a Red Dragon
  # Disciple, a table left as raw wikitext) or a column of a class's
  # progression table.
  #
  # The cost was the pair this project keeps meeting — a wrong number and
  # silence, in unequal halves. `Great strength` at least said something
  # (`{:not_modelled, {:feat_bonus, …}}`, because the feat repeats); the Red
  # Dragon Disciple's table said **nothing at all**, so a build with ten class
  # levels showed strength 16 and an empty `gaps` while the character had 24.
  #
  # ## Where the numbers land, and why not beside the gear ones
  #
  # In the **naked** score, after the level increases and before the gear. That
  # is the source's own split rather than ours: one paragraph lists what a
  # *base score* is made of and puts these feats in it beside point buy, race
  # and the every-fourth-level increase; the next starts on items and spells
  # and gives them a ceiling of their own (+12). So a feat bonus is never
  # clipped by that ceiling, and it does count towards a feat's own ability
  # prerequisite — «It is this unmodified score (the base score) that matters
  # when meeting the prerequisite of a feat».
  #
  # ## Two shapes, and what raises at compile time
  #
  # `per_take` (a `Great …`, +1 a take up to a stated ceiling on the effect)
  # and `ability_at_class_level` (steps by class level, **summed** — the
  # opposite reading from `ac_at_class_level` next door, and each file states
  # its own). An unknown feat or class, an `applied` record with no amount or
  # with an amount whose `kind` the core does not compute, an amount naming an
  # ability that does not exist — all raise. A markup file whose whole job is
  # to stop a bonus disappearing quietly must not be able to drop one itself.
  @applied_ability_bonus_kinds ~w(per_take ability_at_class_level)

  @ability_file "feat_ability_bonuses.json"
  @ability_bonus_sources ~w(feat class)

  @ability_bonus_verdicts %{
    "applied" => :applied,
    "counted_elsewhere" => :counted_elsewhere,
    "not_modelled" => :not_modelled,
    "not_an_ability_bonus" => :not_an_ability_bonus
  }

  @ability_reader %{
    file: @ability_file,
    keys: @ability_bonus_sources,
    verdicts: @ability_bonus_verdicts
  }

  def build_ability_bonuses(shape, dictionaries),
    do: BonusMarkup.build(shape, dictionaries, &ability_bonus_record/2)

  defp ability_bonus_record(entry, dictionaries) do
    BonusMarkup.record(@ability_reader, entry, dictionaries, fn entry, verdict, name ->
      %{
        amount: ability_bonus_amount(entry, verdict, name, dictionaries),
        # Whether the page names nothing else this feat does, which is what lets
        # a build stop saying «прибавку от фита не считаем» about a feat whose
        # whole effect is now a term on screen. Never inferred from the bonus
        # being applied — see the file's `_schema`.
        covers_feat?: entry["effect_coverage"] == "whole_feat"
      }
    end)
  end

  defp ability_bonus_amount(entry, verdict, name, dictionaries) do
    BonusMarkup.amount!(
      @ability_file,
      name,
      verdict,
      @applied_ability_bonus_kinds,
      ability_amount(entry, name, dictionaries)
    )
  end

  defp ability_amount(%{"amount" => %{} = amount}, name, dictionaries) do
    case amount["kind"] do
      "per_take" ->
        %{
          kind: :per_take,
          ability: ability_bonus_ability!(name, amount["ability"]),
          bonus: ability_bonus_number!(name, amount["bonus"]),
          max_total: ability_bonus_number!(name, amount["max_total"])
        }

      "ability_at_class_level" ->
        %{
          kind: :ability_at_class_level,
          class: BonusMarkup.id!(@ability_file, name, amount["class"], dictionaries, :class),
          gains_at_class_level: ability_steps!(name, amount["gains_at_class_level"])
        }

      other ->
        raise "feat_ability_bonuses.json: amount kind #{inspect(other)} is unknown to this loader"
    end
  end

  defp ability_amount(_entry, _name, _dictionaries), do: nil

  defp ability_bonus_number!(name, value),
    do: BonusMarkup.number!(@ability_file, name, value, "a whole number")

  defp ability_bonus_ability!(name, value),
    do: BonusMarkup.ability!(@ability_file, name, value)

  # `{class level => %{ability => bonus}}`. The steps are summed by the core,
  # so a level naming an ability twice cannot happen (a JSON object cannot
  # repeat a key) and a level naming none is simply a level with no step.
  defp ability_steps!(name, steps) do
    BonusMarkup.steps!(@ability_file, name, steps, "abilities", &ability_step_gains!(name, &1))
  end

  defp ability_step_gains!(name, %{} = gains) do
    Map.new(gains, fn {ability, bonus} ->
      {ability_bonus_ability!(name, ability), ability_bonus_number!(name, bonus)}
    end)
  end

  defp ability_step_gains!(name, other) do
    raise "feat_ability_bonuses.json: #{name} states #{inspect(other)} " <>
            "where a step of ability => bonus was expected"
  end

  # ------------------------------------------ what adds to saving throws --

  # `priv/rules/vanilla/feat_save_bonuses.json` — hand written for the fifth
  # time and for the fifth time because **the corpus has no field for it**
  # (task 1.12a). Until this task `Rules.compute/2` summed exactly two
  # sources into every save: what the player typed under "Вещи" and
  # Spellcraft's ranks — both save-agnostic, both landing on Fort, Ref and
  # Will identically. `Iron will`, `Divine grace`, `Sacred defense` and their
  # siblings were not in the numbers at all, and not in a gap either:
  # `Vocabulary` had `{:not_modelled, {:save_bonus_scope, :spellcraft}}` about
  # the ONE source that already counted and nothing about the ones that did
  # not.
  #
  # ## Four sources, same as `ac_bonuses.json`, and for the same reason
  #
  # An entry names exactly one of `feat` / `class` / `skill` / `race_feat`.
  # `Sacred defense`'s own page and Champion of Torm's class table state the
  # same number two independent ways (`counted_elsewhere` records the second);
  # `Lucky` and the whole `Hardiness vs. *` family arrive off a race, never a
  # slot; Bard song is a skill's table, not a feat's.
  #
  # ## No `type` field, unlike `ac_bonuses.json`
  #
  # Armour class genuinely has bonus *types* in this engine — natural, dodge,
  # deflection — and same-typed sources do not stack while a `dodge` one has
  # its own ceiling. No source in this file's sweep ever names a save bonus a
  # "resistance bonus" or a "luck bonus" the way tabletop D&D would; the
  # engine appears to just sum every source into one number. So there is
  # nothing here to type and nothing to guard against stacking.
  #
  # ## `saves` where AC has nothing analogous
  #
  # A bonus here lands on one, two or three of Fort/Ref/Will, and unlike AC's
  # single number or an ability score's single target, which save(s) a
  # record touches has to be stated. Required on `applied`; on `not_modelled`
  # it is present only when the source names the save by word ("reflex
  # saves", "will saves") — when it says "against poison" or "against the
  # chosen school" without naming a save type, the key is left out rather
  # than guessed (CLAUDE.md §3: poison is Fortitude in every edition of the
  # rules this reads from, but no page here says so in words, and the field
  # would be inventing a fact none of the nine files states).
  #
  # ## What raises at compile time
  #
  # An unknown feat, class, skill or race trait; an `applied` record with no
  # amount, with an amount whose `kind` is unknown, missing `saves`, or
  # naming a save that is not `fort`/`ref`/`will`; an amount naming an ability
  # or a class that does not exist; a `prerequisite` on a record nobody counts,
  # or one stated without a boolean, a `verified` status, a quote and a source
  # (`save_bonus_prerequisite!/3`).
  #
  # ⚠ The **amount** of the ceiling is not this file's business — `Rules.compute/2`
  # combines a build's terms from here with `gear.saves` and Spellcraft under
  # one clip **per save**, exactly the shape `_cap_decision` in the file
  # describes and the shape that closed the "clipped by halves, actually +40"
  # bug for the two sources that predate this one (CLAUDE.md §9). Records here
  # carry the raw, uncapped contribution.
  #
  # ⚠ **Which side of that ceiling a record falls on, though, is stated per
  # record** (`cap`, since 09.08.2026), and that was the second correction of the
  # same rule in one day. First the ceiling covered everything (analogy with two
  # vanilla quotes); then it was made a property of the source **kind**
  # (`applies_to_sources`); then Dan named `Divine grace` and `Sacred defense` —
  # two class abilities, both written here in the shape of a feat, one outside the
  # +20 and one inside. A kind cannot answer that, only a record can. See
  # `Character.cap_side!/4` and `Rules.Caps.covers_record?/3`.
  #
  # ## Разметка `affects`
  #
  # ⚠ **Между 17.08.2026 и 18.08.2026 этот файл не нёс поле `affects` ни на одной
  # записи** — разметку 17.08.2026 получили пять файлов из шести, — и все
  # 21 отвергнутая запись оставались гэпами: у Ярости пропали оговорки про
  # характеристику и AC, а оговорка про сейвы держалась ещё день. Маршрут
  # был заведён всё равно и пустым: без него разметка этого файла в день,
  # когда её проставят, молча не сделала бы ничего — ровно та поломка,
  # которую задача 17.08.2026 чинила у четырёх остальных. 18.08.2026 файл
  # получил разметку (6 `buff`, 15 `saving_throws` из 21 not_modelled), и
  # маршрут наконец не пустует: три пары «одно умение, две записи» (Ярость
  # в ac/ability, Стойка Гномьего защитника в ac/ability, Divine wrath
  # в атаке) сошлись — обе половины каждой пары теперь молчат одинаково.
  @applied_save_bonus_kinds ~w(flat ability_modifier save_at_class_level)
  @saves ~w(fort ref will)a

  @save_file "feat_save_bonuses.json"
  @save_bonus_sources ~w(feat class skill race_feat)

  # ⚠ Отдаётся наружу потому, что этот же список читает потолок статов
  # (`Character`, `@cap_record_kinds`): поле-источник разметки не может быть
  # именем источника капа, и решает это ОДИН список, а не два одинаковых.
  # До задачи 3.46 оба читателя жили в одном модуле и делили атрибут; атрибут
  # виден только своему модулю, поэтому здесь функция, а не вторая копия.
  @doc "Поля разметки, которыми запись прибавки к спасброску называет свой источник."
  def save_bonus_sources, do: @save_bonus_sources

  @save_bonus_verdicts %{
    "applied" => :applied,
    "counted_elsewhere" => :counted_elsewhere,
    "not_modelled" => :not_modelled,
    "not_a_save_bonus" => :not_a_save_bonus
  }

  @save_reader %{
    file: @save_file,
    keys: @save_bonus_sources,
    verdicts: @save_bonus_verdicts
  }

  def build_save_bonuses(shape, dictionaries),
    do: BonusMarkup.build(shape, dictionaries, &save_bonus_record/2)

  defp save_bonus_record(entry, dictionaries) do
    BonusMarkup.record(@save_reader, entry, dictionaries, fn entry, verdict, name ->
      %{
        saves: save_bonus_saves(entry, verdict, name),
        amount: save_bonus_amount(entry, verdict, name, dictionaries),
        # Whether the page names nothing else this feat does — the same
        # question `ability_bonus_record/2` asks, answered the same way: from
        # the data's own `effect_coverage`, never inferred from the bonus being
        # applied. `Snake blood` and `Strong soul` are `applied` here and
        # `false` here on purpose — each has a second, narrower effect this
        # file does not count (see `_partial_coverage_note`), so the general
        # "прибавку от фита не считаем" caveat has to keep costing something.
        covers_feat?: entry["effect_coverage"] == "whole_feat",
        # Which side of `stat_caps.saving_throw_bonus` this record falls on —
        # required on `applied`, forbidden elsewhere. See `cap_side!/4`.
        cap: Character.cap_side!(@save_file, name, entry, verdict),
        # Идёт ли эта прибавка в число, с которым сравнивается ТРЕБОВАНИЕ фита по
        # сейву — `nil`, пока запись про это молчит. See `save_bonus_prerequisite!/3`.
        prereq: save_bonus_prerequisite!(entry, verdict, name)
      }
    end)
  end

  # `bonuses[].prerequisite` — идёт ли прибавка ЭТОЙ записи в число, с которым
  # сравнивается требование фита по сейву (`prereqs.save_bonus`; сегодня таким
  # требованием владеет один `Resist energy`). Задача S3, 17.08.2026.
  #
  # **Ключ необязателен, и это не поблажка, а само правило:** молчание записи
  # означает «идёт», умолчание объявлено ОДИН раз в `_prerequisite_decision`
  # файла и опирается на слово Dan из S2 («собственные прибавки требование
  # выполнять обязаны»). Ключ появляется только там, где от умолчания
  # **отклоняются**, — сегодня ровно у `luck_of_heroes`, которого страница
  # `fandom:Resist energy` исключает поимённо, а замер Dan подтвердил на Сиале.
  #
  # ⚠ Признак — свойство ЗАПИСИ, а не вида источника, и это тот же урок, что у
  # `cap`: строка источника называет один фит из четырнадцати, дающих прибавку к
  # сейвам, и правило «прибавки фитов в требование не идут» было бы обобщением
  # цитаты про один источник на все источники того же вида (`_cap_decision.
  # _superseded`, `Divine grace` против `Sacred defense`).
  #
  # Что роняет сборку:
  #
  #   * ключ на записи с любым вердиктом кроме `applied` — у прибавки, которую
  #     никто не считает, в требовании нечему участвовать;
  #   * `counts` не булево — у вопроса нет нейтрального ответа;
  #   * `status` не `verified`. ⚠ **Здесь строже, чем у `cap`, и намеренно:**
  #     исключение двигает ответ в сторону ОТКАЗА, а догадка в эту сторону — это
  #     ложная нелегальность, которую игрок изнутри инструмента не обойдёт и не
  #     распознает. Умолчание («идёт») ошибается в другую сторону и хотя бы
  #     совпадает с тем, что делают остальные тринадцать записей;
  #   * нет дословной цитаты или источника — факт, снимающий прибавку с чужого
  #     требования, обязан быть прослеживаемым (CLAUDE.md §3).
  #
  # ⚠ Читает это ОДИН файл разметки — сейвы. У атаки такого ключа нет и быть не
  # может молча: требование `base_attack_bonus` сравнивается с BAB, куда записи
  # `feat_attack_bonuses.json` не входят вовсе. Понадобится второму файлу —
  # функция переезжает к `cap_side!/4`, где уже стоит общая пара «файл, имя».
  defp save_bonus_prerequisite!(entry, verdict, name) do
    case {entry["prerequisite"], verdict} do
      {nil, _verdict} ->
        nil

      {%{} = prereq, :applied} ->
        cond do
          not is_boolean(prereq["counts"]) ->
            raise "feat_save_bonuses.json: #{name} states no boolean prerequisite.counts"

          prereq["status"] != "verified" ->
            raise "feat_save_bonuses.json: #{name} states " <>
                    "prerequisite.status #{inspect(prereq["status"])}; only \"verified\" takes " <>
                    "a bonus out of somebody's requirement — a guess in that direction is a " <>
                    "refusal the player cannot work around"

          not (is_binary(prereq["quote"]) and prereq["quote"] != "") or
              not is_map(prereq["source"]) ->
            raise "feat_save_bonuses.json: #{name} states a `prerequisite` " <>
                    "without a verbatim quote and a source"

          true ->
            %{counts?: prereq["counts"]}
        end

      {_present, other_verdict} ->
        raise "feat_save_bonuses.json: #{name} is `#{other_verdict}` and " <>
                "states a `prerequisite`; a bonus nobody counts is in nobody's requirement either"
    end
  end

  # Required on `applied` — a bonus nobody says which save it lands on is not
  # honestly a bonus. Optional everywhere else, and left `nil` rather than
  # guessed when the source itself does not name a save type (see the file's
  # `_schema`).
  defp save_bonus_saves(entry, :applied, name) do
    case entry["saves"] do
      list when is_list(list) and list != [] ->
        save_bonus_save_list!(name, list)

      _ ->
        raise "feat_save_bonuses.json: #{name} is `applied` but names no saves"
    end
  end

  defp save_bonus_saves(entry, _verdict, name) do
    case entry["saves"] do
      list when is_list(list) and list != [] -> save_bonus_save_list!(name, list)
      _ -> nil
    end
  end

  defp save_bonus_save_list!(name, list) do
    saves = for save <- list, do: save_bonus_save!(name, save)

    if Enum.uniq(saves) == saves,
      do: Enum.sort(saves),
      else: raise("feat_save_bonuses.json: #{name} names a save twice")
  end

  defp save_bonus_save!(_name, save) when is_binary(save) do
    id = atom(save)
    if id in @saves, do: id, else: raise("feat_save_bonuses.json names save #{save}")
  end

  defp save_bonus_save!(name, other) do
    raise "feat_save_bonuses.json: #{name} states #{inspect(other)} " <>
            "where fort/ref/will was expected"
  end

  defp save_bonus_amount(entry, verdict, name, dictionaries) do
    BonusMarkup.amount!(
      @save_file,
      name,
      verdict,
      @applied_save_bonus_kinds,
      save_amount(entry, name, dictionaries)
    )
  end

  defp save_amount(%{"amount" => %{} = amount}, name, dictionaries) do
    case amount["kind"] do
      "flat" ->
        %{kind: :flat, bonus: save_bonus_number!(name, amount["bonus"])}

      "ability_modifier" ->
        %{
          kind: :ability_modifier,
          ability: save_bonus_ability!(name, amount["ability"]),
          # `Divine grace`'s own page: "(if positive)", and its Notes section
          # names the alternative by contrast — "unlike divine grace, if the
          # character has a negative charisma modifier, his saving throws are
          # reduced instead of increased" (that alternative is `Dark
          # blessing`, which carries no `floor` at all). Absent key, not
          # `null`: the two feats read identically otherwise, and a key that
          # is merely absent keeps that visible in the JSON's own shape.
          floor: save_bonus_floor(name, amount["floor"])
        }

      "save_at_class_level" ->
        %{
          kind: :save_at_class_level,
          class: BonusMarkup.id!(@save_file, name, amount["class"], dictionaries, :class),
          save_at_class_level: save_bonus_steps!(name, amount["save_at_class_level"])
        }

      other ->
        raise "feat_save_bonuses.json: amount kind #{inspect(other)} is unknown to this loader"
    end
  end

  defp save_amount(_entry, _name, _dictionaries), do: nil

  defp save_bonus_number!(name, value),
    do: BonusMarkup.number!(@save_file, name, value, "a whole number")

  defp save_bonus_ability!(name, value),
    do: BonusMarkup.ability!(@save_file, name, value)

  defp save_bonus_floor(_name, nil), do: nil
  defp save_bonus_floor(_name, value) when is_integer(value), do: value

  defp save_bonus_floor(name, other) do
    raise "feat_save_bonuses.json: #{name} states floor #{inspect(other)} " <>
            "where a whole number or nothing was expected"
  end

  # The table states TOTALS at each step, the same reading `ac_steps!/2` gives
  # `ac_at_class_level` — `Sacred defense`'s own class table prints a running
  # sum ("+1" at level 2, "+2" at level 4, … "+15" at level 30), not a
  # per-step increment, and `Rules.SaveBonuses` takes the highest step
  # reached rather than summing them.
  defp save_bonus_steps!(name, steps),
    do: BonusMarkup.steps!(@save_file, name, steps, "bonus", &save_bonus_number!(name, &1))

  # ------------------------------------------- what adds to the attack roll --

  # `priv/rules/vanilla/feat_attack_bonuses.json` — the sixth and last file of
  # this shape, hand written for the sixth time and for the sixth time because
  # **the corpus has no field for it** (task 1.12b). Until this task
  # `Rules.compute/2` summed exactly two things into `attack_bonus` beyond the
  # base: the part gear added to the governing ability modifier, and the
  # shard's own racial bonus (task 3.12). `Epic prowess` — a flat +1 to every
  # attack roll, and CLAUDE.md §9's own example of "a feat of the first kind,
  # a flat bonus, trivial" — was not in the numbers at all, and not in a gap
  # either.
  #
  # ## Five sources, one more than the saves
  #
  # An entry names exactly one of `feat` / `class` / `skill` / `race_feat` /
  # `race`. The fifth exists for a single record and earns its place: the
  # shard's racial attack bonus belongs to the **race**, not to any trait of
  # it, and it is already counted by `Rules.RacialBonus`. Recording it here as
  # `counted_elsewhere` is what stops the next sweep from giving it a second,
  # double-counting home.
  #
  # ## No `saves` field, and no `type` field
  #
  # Armour class has bonus types that stack differently; a saving throw has
  # three recipients. An attack roll has one number and one recipient, so
  # neither field has anything to say here.
  #
  # ## `condition` instead, and it is required on `not_modelled`
  #
  # ⚠ The finding of this sweep is that attack bonuses in the sources are
  # **almost all conditional**: of 81 candidates exactly two were unconditional
  # at the time of the sweep (`Epic prowess` and a small race's size modifier),
  # against fourteen for the saves. ⚠ **One of the two turned out not to be**
  # (task 3.143, 30.08.2026): the small race's size modifier is not a flat
  # bonus at all, but conditional on the target being larger than the
  # character (`condition: relative_size`) — the sweep had quoted that very
  # sentence in the record's own `quote_feat_page` and still counted it flat.
  # `Epic prowess` is the one true unconditional bonus left in this file. So a
  # rejected record has to say *what* it depends on — the weapon in hand, the
  # enemy's type or relative size, the terrain, a combat mode, a once-a-day
  # activation — and the core reads exactly one distinction out of that field:
  # `weapon` against everything else, because the weapon case is the one the
  # armoury will lift (task 3.5) and the others are not. Two gap forms, two
  # sentences, `_weapon_decision` in the file for the whole argument.
  #
  # ## What raises at compile time
  #
  # An unknown feat, class, skill, race trait or race; an `applied` record
  # with no amount, or with an amount whose kind the core cannot compute; a
  # `not_modelled` record with no `condition` or an unknown one; an amount
  # naming an ability or a class that does not exist.
  #
  # ⚠ `@applied_attack_bonus_kinds` is deliberately **narrower** than
  # `@attack_bonus_kinds`: the file carries `ability_modifier` (`Smite evil`'s
  # charisma) and `attack_at_class_level` (the Weapon Master's «AB bonus»
  # column) as *material*, on records that are all `not_modelled`. The core
  # implements `flat` only, and the guard raises rather than silently counting
  # zero if somebody promotes one of those to `applied` without implementing
  # it — the same "a guard instead of an implementation" the `dodge_ac` ceiling
  # already stands on, and for the same reason: there is nothing to implement
  # today and untested arithmetic does not belong in this module.
  @attack_bonus_kinds ~w(flat ability_modifier attack_at_class_level)
  # ⚠ `attack_at_class_level` joined on 10.08.2026 (task 3.5 part B): the Weapon
  # Master's own «AB bonus» column became `applied`, so the form had to be
  # implemented rather than guarded against. The guard stays where there is still
  # nothing to implement — `ability_modifier` belongs to `Smite evil`/`Smite good`
  # alone, both once-a-day activations.
  @applied_attack_bonus_kinds ~w(flat attack_at_class_level)
  @attack_bonus_conditions ~w(weapon activated combat_mode enemy_type relative_size area range
                              mounted attack_of_opportunity special_attack dual_wield
                              unknown_amount)

  @attack_file "feat_attack_bonuses.json"
  @attack_bonus_sources ~w(feat class skill race_feat race)

  # Наружу — по той же причине, что и у соседа выше: список читает ещё и потолок
  # статов в `Character`.
  @doc "Поля разметки, которыми запись прибавки к атаке называет свой источник."
  def attack_bonus_sources, do: @attack_bonus_sources

  @attack_bonus_verdicts %{
    "applied" => :applied,
    "counted_elsewhere" => :counted_elsewhere,
    "not_modelled" => :not_modelled,
    "not_an_attack_bonus" => :not_an_attack_bonus
  }

  @attack_reader %{
    file: @attack_file,
    keys: @attack_bonus_sources,
    verdicts: @attack_bonus_verdicts
  }

  def build_attack_bonuses(shape, dictionaries),
    do: BonusMarkup.build(shape, dictionaries, &attack_bonus_record/2)

  @doc """
  Расширяет оружие применяемых прибавок тем, что шард дописал КЛАССУ.

  Одна строка шарда на сегодня, и она не про прибавку, а про класс целиком:
  «Все классовые умения Тайного лучника теперь распространяются на малый
  и большие арбалеты». Умение, которое от этого меняет наше число, ровно одно —
  `Enchant arrow`, растущий бонус атаки, — но выражать это записью В ФАЙЛЕ
  ПРИБАВОК было бы второй записью того же правила, а две записи об одном
  правиле расходятся молча (урок задачи 3.85). Поэтому правило остаётся одно,
  на стороне класса (`ability_weapons`), а связь «класс → его умения» берётся
  оттуда, где она уже есть, — из `granted_feats`.

  ⚠ Расширяет, а не заменяет: ванильный состав («лук») остаётся, арбалеты
  добавляются. У ванильного ruleset'а `ability_weapons` пуст у всех классов,
  поэтому там не меняется ничего — и это не совпадение, а требование: цитата
  принадлежит Сиале и говорить от имени ванили не может.

  ⚠ Роняет сборку на записи, чьё оружие названо НЕ перечислением: свойство
  справочника (`weapon_must_be`) списком не расширить, а выбор фита
  (`choice_of`) расширять нечем — оружие там называет игрок. Молча пропустить
  такую запись значило бы применить правило шарда наполовину, то есть завести
  ровно тот молчаливый разъезд, ради устранения которого правило и живёт
  в одном месте.
  """
  @spec widen_class_ability_weapons(map(), map()) :: map()
  def widen_class_ability_weapons(attack_bonuses, classes) do
    case class_ability_weapons(classes) do
      extra when map_size(extra) == 0 ->
        attack_bonuses

      extra ->
        Map.update!(attack_bonuses, :applied, fn records ->
          for record <- records, do: widen_record(record, extra)
        end)
    end
  end

  # `%{feat_id => MapSet}` — какое оружие шард дописал умениям, которые выдаёт
  # класс. Объединение, а не последний победивший: один и тот же фит могут
  # выдавать два класса, и правило одного не отменяет правила другого.
  defp class_ability_weapons(classes) do
    for {_id, class} <- classes,
        weapons = Map.get(class, :ability_weapons) || MapSet.new(),
        MapSet.size(weapons) > 0,
        {_level, feats} <- Map.get(class, :granted_feats) || %{},
        feat <- feats,
        reduce: %{} do
      acc -> Map.update(acc, feat, weapons, &MapSet.union(&1, weapons))
    end
  end

  defp widen_record(%{source: {:feat, id}} = record, extra) do
    case {Map.get(extra, id), Map.get(record, :weapon_kind), Map.get(record, :weapon)} do
      {nil, _kind, _choice} ->
        record

      {_weapons, nil, nil} ->
        # Прибавка безусловна — расширять нечего, и в игре она с арбалетом
        # работает ровно так же, как со всем прочим.
        record

      {weapons, {:one_of, ids}, nil} ->
        %{record | weapon_kind: {:one_of, MapSet.union(ids, weapons)}}

      {_weapons, kind, choice} ->
        raise "siala_41/classes.json: a class widens the weapons of its abilities to " <>
                "#{inspect(id)}, whose record in #{@attack_file} names its weapon as " <>
                "#{inspect(kind || {:choice_of, choice})} — only an enumeration can be " <>
                "widened by one, and widening nothing would apply the shard's rule by half"
    end
  end

  defp widen_record(record, _extra), do: record

  defp attack_bonus_record(entry, dictionaries) do
    BonusMarkup.record(@attack_reader, entry, dictionaries, fn entry, verdict, name ->
      %{
        amount: attack_bonus_amount(entry, verdict, name, dictionaries),
        # What the bonus depends on — `nil` on anything but `not_modelled`, where
        # it is required. `Rules.AttackBonuses` reads it to tell the two gap
        # forms apart and for nothing else.
        condition: attack_bonus_condition!(entry, verdict, name),
        # Which weapon in the character's hands the bonus needs, as an ordered list
        # of the feats whose recorded choice names it (task 3.5 part B). `nil` on a
        # bonus that is true whatever is held — `Epic prowess`, the only `applied`
        # record left with no weapon condition. ⚠ Until 30.08.2026 (task 3.143)
        # a small race's size modifier sat here too; it needed no weapon, but it
        # needed an opponent larger than the character, and that is a `condition`
        # (`relative_size`), not a reason for `weapon` to stay `nil` on an
        # `applied` record — the record moved to `not_modelled` instead.
        #
        # ⚠ Only on `applied`: on a rejected record it would be a statement that
        # looks live and moves nothing, which is exactly what `applies_to_sources`
        # had to have the feat kinds removed from.
        weapon: attack_bonus_weapon!(entry, verdict, name, dictionaries),
        # The **other** way a source names the weapon (task 3.101, 25.08.2026):
        # not «the one you chose for this feat» but a class of weapons the page
        # names outright. `{:property, atom}` or `{:one_of, MapSet}`, `nil` when
        # the record says nothing about the weapon or names it by choice.
        weapon_kind: attack_bonus_weapon_kind!(entry, verdict, name, dictionaries),
        # Same contract as its three siblings: the claim is the data's
        # (`effect_coverage: "whole_feat"`), never inferred from the bonus being
        # applied. `Enchant arrow` is `applied` here and `false` — its damage and
        # damage-reduction remainder is nobody's number yet (see its own note).
        # ⚠ `Small stature` used to be the example here; task 3.143 (30.08.2026)
        # moved it to `not_modelled`, where `effect_coverage` is forbidden.
        covers_feat?: entry["effect_coverage"] == "whole_feat",
        # Same as its save sibling: the side of `stat_caps.attack_bonus` belongs to
        # the record, not to its kind (09.08.2026). See `cap_side!/4`.
        cap: Character.cap_side!(@attack_file, name, entry, verdict)
      }
    end)
  end

  defp attack_bonus_condition!(entry, :not_modelled, name) do
    case entry["condition"] do
      condition when is_binary(condition) and condition != "" ->
        if condition in @attack_bonus_conditions,
          do: atom(condition),
          else: raise("feat_attack_bonuses.json: unknown condition #{inspect(condition)}")

      _ ->
        raise "feat_attack_bonuses.json: #{name} is `not_modelled` but names no condition"
    end
  end

  defp attack_bonus_condition!(_entry, _verdict, _name), do: nil

  # `applies_to_weapon.choice_of` — упорядоченный список фитов, чей записанный
  # выбор называет оружие этой прибавки. Возвращает `[feat_id]` или `nil`.
  #
  # Что проверяется на компиляции и почему каждое:
  #
  #   * ключ есть только у `applied` — у отвергнутой записи он не решал бы ничего;
  #   * фит существует — опечатка иначе означала бы «оружие никогда не известно»,
  #     то есть прибавку, которая молча не считается;
  #   * фит берёт выбор ИЗ ДОМЕНА `weapon` — фит без выбора не может назвать
  #     оружие вовсе, а фит с выбором из другого домена назвал бы не оружие.
  #     ⚠ Кроме одного случая, названного явно: `epic_weapon_focus` на ванили
  #     `repeatable: null`, то есть своего выбора у него нет, и он стоит в списке
  #     первым ровно затем, чтобы шард мог сделать его повторяемым, не правя
  #     данные. Поэтому проверка требует, чтобы домен `weapon` был хотя бы
  #     у ОДНОГО фита списка, а не у каждого.
  defp attack_bonus_weapon!(entry, verdict, name, dictionaries) do
    case {applies_to_weapon!(entry, verdict, name), verdict} do
      {%{"choice_of" => feats}, :applied} when is_list(feats) and feats != [] ->
        ids =
          for feat <- feats, do: BonusMarkup.id!(@attack_file, name, feat, dictionaries, :feat)

        verify_weapon_choice_feats!(name, ids, dictionaries.feats)
        ids

      {%{"choice_of" => _empty_or_wrong}, :applied} ->
        raise "feat_attack_bonuses.json: #{name} states applies_to_weapon " <>
                "without a non-empty `choice_of` list of the feats whose choice names the weapon"

      _no_choice_of ->
        nil
    end
  end

  # ⚠ **ДВА способа назвать оружие, и вывести один из другого нельзя** — та же
  # граница, что `formulas.attack_ability.rules` провела 17.08.2026 между
  # `weapon_must_be` и `weapon_one_of`, и здесь она проходит по тому же месту:
  #
  #   * `weapon_must_be` — СВОЙСТВО, которое справочник утверждает полем.
  #     `Good aim` даёт +1 «with throwing weapons», а `thrown` — категория вики
  #     ровно из четырёх страниц, и `fandom:Throwing weapon` перечисляет тех же
  #     четверых прозой. Своей таксономии здесь нет ни на грош;
  #   * `weapon_one_of` — ПЕРЕЧИСЛЕНИЕ, потому что источник перечисляет.
  #     `Enchant arrow` работает «only for bows», а «лук» — не поле справочника
  #     и не категория вики: состав класса называет отдельная страница
  #     (`fandom:Bow`: «two types of bows: longbows and shortbows»). Завести
  #     ради этого колонку `bow` значило бы назвать своей таксономией то, что
  #     источник дал списком.
  #
  # Что роняет сборку и почему каждое:
  #
  #   * ключ есть только у `applied` — у отвергнутой записи он не решал бы ничего;
  #   * ровно ОДИН из трёх ключей (`choice_of`, `weapon_must_be`, `weapon_one_of`).
  #     Два сразу — это два разных утверждения об одном оружии, и порядок чтения
  #     молча решал бы, какое из них правда;
  #   * свойство обязано быть читаемым (`Rules.Attack.weapon_property_field/1` —
  #     тот же закрытый словарь, что у хука характеристики атаки, второго
  #     в проекте нет). Нечитаемое свойство — правило, которое не сработает
  #     никогда, то есть тихое занижение;
  #   * список непуст и каждое имя есть в справочнике оружия — по той же причине.
  defp attack_bonus_weapon_kind!(entry, verdict, name, dictionaries) do
    case applies_to_weapon!(entry, verdict, name) do
      nil -> nil
      %{"weapon_must_be" => property} -> {:property, attack_weapon_property!(name, property)}
      %{"weapon_one_of" => ids} -> {:one_of, attack_weapon_list!(name, ids, dictionaries)}
      %{} -> nil
    end
  end

  @attack_weapon_keys ~w(choice_of weapon_must_be weapon_one_of)

  defp applies_to_weapon!(entry, verdict, name) do
    case {entry["applies_to_weapon"], verdict} do
      {nil, _verdict} ->
        nil

      {%{} = spec, :applied} ->
        case Enum.filter(@attack_weapon_keys, &Map.has_key?(spec, &1)) do
          [_one] ->
            spec

          other ->
            raise "feat_attack_bonuses.json: #{name} states applies_to_weapon with " <>
                    "#{inspect(other)} — exactly one of #{inspect(@attack_weapon_keys)} is " <>
                    "required, because they are three different statements about the same " <>
                    "weapon and reading order would decide between them"
        end

      {%{}, _verdict} ->
        raise "feat_attack_bonuses.json: #{name} states applies_to_weapon " <>
                "on a `#{verdict}` record, where it decides nothing"
    end
  end

  defp attack_weapon_property!(name, property) when is_binary(property) do
    kind = atom(property)

    if Attack.weapon_property_field(kind) do
      kind
    else
      raise "feat_attack_bonuses.json: #{name} needs a weapon that is #{inspect(property)}, " <>
              "and the core cannot read that property off a weapon — a condition that never " <>
              "holds is a bonus that silently counts for nothing"
    end
  end

  defp attack_weapon_property!(name, other) do
    raise "feat_attack_bonuses.json: #{name} states weapon_must_be #{inspect(other)}, " <>
            "and a property name is required"
  end

  defp attack_weapon_list!(name, ids, dictionaries) when is_list(ids) and ids != [] do
    known = Map.get(dictionaries, :weapons) || %{}

    for id <- ids, into: MapSet.new() do
      weapon = atom(id)

      unless map_size(known) == 0 or Map.has_key?(known, weapon) do
        raise "feat_attack_bonuses.json: #{name} names the weapon #{inspect(id)}, which the " <>
                "dictionary does not carry — a name nothing matches is a bonus nobody gets"
      end

      weapon
    end
  end

  defp attack_weapon_list!(name, other, _dictionaries) do
    raise "feat_attack_bonuses.json: #{name} states weapon_one_of #{inspect(other)}, " <>
            "and a non-empty list of weapon ids is required"
  end

  @weapon_choice_domain :weapon

  defp verify_weapon_choice_feats!(name, ids, feats) do
    domains = for id <- ids, domain = feat_choice_domain(feats, id), do: domain

    unless map_size(feats) == 0 or @weapon_choice_domain in domains do
      raise "feat_attack_bonuses.json: #{name} takes its weapon from " <>
              "#{inspect(ids)}, and not one of them is taken with a choice out of " <>
              "#{inspect(@weapon_choice_domain)} — the weapon could never be known"
    end

    :ok
  end

  defp feat_choice_domain(feats, id) do
    case Map.get(feats, id) do
      %{repeatable: %{choice: domain}} -> domain
      _absent_or_single_take -> nil
    end
  end

  defp attack_bonus_amount(entry, verdict, name, dictionaries) do
    BonusMarkup.amount!(
      @attack_file,
      name,
      verdict,
      @applied_attack_bonus_kinds,
      attack_amount(entry, name, dictionaries)
    )
  end

  defp attack_amount(%{"amount" => %{} = amount}, name, dictionaries) do
    unless to_string(amount["kind"]) in @attack_bonus_kinds do
      raise "feat_attack_bonuses.json: amount kind #{inspect(amount["kind"])} is unknown to " <>
              "this loader"
    end

    case amount["kind"] do
      "flat" ->
        # ⚠ May legitimately be NEGATIVE, unlike every sibling file: the combat
        # modes and special attacks trade attack for something else (Expertise
        # −5, Disarm −6). All of them are `not_modelled`; the sign is recorded
        # so the day modes are modelled does not start by guessing it.
        %{kind: :flat, bonus: attack_bonus_number!(name, amount["bonus"])}

      "ability_modifier" ->
        %{
          kind: :ability_modifier,
          ability: BonusMarkup.ability!(@attack_file, name, amount["ability"])
        }

      "attack_at_class_level" ->
        %{
          kind: :attack_at_class_level,
          class: BonusMarkup.id!(@attack_file, name, amount["class"], dictionaries, :class),
          attack_at_class_level: attack_bonus_steps!(name, amount["attack_at_class_level"])
        }
    end
  end

  defp attack_amount(_entry, _name, _dictionaries), do: nil

  defp attack_bonus_number!(name, value),
    do: BonusMarkup.number!(@attack_file, name, value, "a whole number")

  # TOTALS at each step, the same reading `save_bonus_steps!/2` and `ac_steps!/2`
  # give — the Weapon Master's own «AB bonus» column prints a running sum ("+1"
  # at class level 5, "+2" at 13, … "+7" at 28), not a per-step increment.
  defp attack_bonus_steps!(name, steps),
    do: BonusMarkup.steps!(@attack_file, name, steps, "bonus", &attack_bonus_number!(name, &1))

  # ------------------------------------ what gives spell resistance (SR) --

  # `priv/rules/vanilla/feat_spell_resistance.json` — the seventh file of this
  # shape, hand written for the seventh time and for the seventh time because
  # **the corpus has no field for it** (task 3.45). Both formulas — «equal to
  # their class level + 10» and «a +2 to spell resistance» — sat in the feats'
  # `description` prose from the first parse, and until this task the core did
  # not compute spell resistance at all: a build with 35 monk levels carried
  # `{:not_modelled, {:feat_bonus, :improved_spell_resistance}}` where the wiki's
  # own page prints 63. Prose in a data file is not a rule until somebody reads
  # it — the fourth time in this repository (`Zen archery`, the racial bonus's
  # activation, the base score a feat prerequisite reads).
  #
  # ## Four sources in the schema, one of them used
  #
  # An entry names exactly one of `feat` / `class` / `skill` / `race_feat`, the
  # same four `ac_bonuses.json` and `feat_save_bonuses.json` take. Only `feat`
  # occurs, and that is the **finding** of the file's own sweep rather than a
  # limitation here: no class table, no skill and none of the seven races grants
  # spell resistance anywhere in the corpus.
  #
  # ## No `type`, no `saves`, no `condition`, and no `cap`
  #
  # Spell resistance is one number with one recipient, so the first three have
  # nothing to say. The fourth is a decision: no ruleset states a ceiling on
  # spell resistance at all (`stat_caps` lists five, and this is not among
  # them), so `cap` on a record raises — the same guard `feat_hp_bonuses.json`
  # carries, for the same reason. ⚠ Not to be confused with `amount.max_total`,
  # which belongs to **one** bonus and is quoted from its own page («to a
  # maximum of +20»).
  #
  # ## Two kinds, and the first one is a formula on purpose
  #
  # `class_level_plus` is `Diamond soul`: monk level + 10. Its two siblings in
  # neighbouring files (`ac_at_class_level`, `save_at_class_level`) are **tables**
  # because that is how the wiki prints them — a progression column, transcribed
  # row by row. There is no such column here: `fandom:Monk`'s progression table
  # carries no spell-resistance column at all, and the feat's page states the
  # formula in one sentence. Expanding it into thirty rows would add a step
  # between source and data, and would quietly decide what happens past the last
  # row (a table holds its last step; the formula does not need to).
  #
  # `per_take` is `Improved spell resistance`, the same shape and the same name
  # `epic_toughness` carries in `feat_hp_bonuses.json`, read the same way.
  #
  # ## What raises at compile time
  #
  # An unknown feat, class, skill or race trait; an `applied` record with no
  # amount, or one whose `kind` the core does not compute; an amount naming a
  # class that does not exist; a `cap` on any record; `affects` that is present
  # but not a non-empty list of known receivers.
  #
  # ## Разметка `affects`
  #
  # See `BonusMarkup.record/4` for the field's shape and why it is not
  # atomised. Always `nil` here today: the file has no `not_modelled` record
  # at all, so there is nothing to label — exactly the state
  # `feat_hp_bonuses.json` is in. The route is wired anyway, and that is the
  # point: a file whose records reach the core **without** the key can be
  # labelled in the data and do nothing, which is the breakage five of the
  # six older files carried until 17.08.2026.
  @applied_spell_resistance_kinds ~w(class_level_plus per_take)

  @spell_resistance_file "feat_spell_resistance.json"
  @spell_resistance_sources ~w(feat class skill race_feat)

  @spell_resistance_verdicts %{
    "applied" => :applied,
    "counted_elsewhere" => :counted_elsewhere,
    "not_modelled" => :not_modelled,
    "not_a_spell_resistance" => :not_a_spell_resistance
  }

  @spell_resistance_reader %{
    file: @spell_resistance_file,
    keys: @spell_resistance_sources,
    verdicts: @spell_resistance_verdicts,
    guard: &__MODULE__.spell_resistance_cap_forbidden!/2
  }

  def build_spell_resistance(shape, dictionaries),
    do: BonusMarkup.build(shape, dictionaries, &spell_resistance_record/2)

  defp spell_resistance_record(entry, dictionaries) do
    BonusMarkup.record(@spell_resistance_reader, entry, dictionaries, fn entry, verdict, name ->
      %{
        amount: spell_resistance_amount(entry, verdict, name, dictionaries),
        # Same contract as its six siblings: the claim is the data's
        # (`effect_coverage: "whole_feat"`), never inferred from the bonus being
        # applied. Both records here are `whole_feat` — `Diamond soul`'s second
        # Notes line («cannot be lowered by breaches») is a property of the number
        # this file already counts, not a second bonus going uncounted.
        covers_feat?: entry["effect_coverage"] == "whole_feat"
      }
    end)
  end

  # No ruleset states a ceiling on spell resistance, so a side of one is a
  # statement about nothing — see the section note and the file's `_cap_decision`.
  #
  # ⚠ Публичная по той же причине, что и её близнец у HP: захват `&__MODULE__.…/2`
  # в атрибуте иначе не выразить. Разные ответы у этих двух функций дать нельзя —
  # но и одной на всех они не становятся: пять остальных файлов сторону капа
  # ТРЕБУЮТ, и разница между «требуется» и «запрещено» живёт в том, у кого из семи
  # паспортов есть ключ `guard`.
  @doc false
  def spell_resistance_cap_forbidden!(entry, name),
    do: BonusMarkup.cap_forbidden!(@spell_resistance_file, name, entry, "spell resistance")

  defp spell_resistance_amount(entry, verdict, name, dictionaries) do
    BonusMarkup.amount!(
      @spell_resistance_file,
      name,
      verdict,
      @applied_spell_resistance_kinds,
      spell_resistance_amount_shape(entry, name, dictionaries)
    )
  end

  defp spell_resistance_amount_shape(%{"amount" => %{} = amount}, name, dictionaries) do
    case amount["kind"] do
      "class_level_plus" ->
        %{
          kind: :class_level_plus,
          class:
            BonusMarkup.id!(
              @spell_resistance_file,
              name,
              amount["class"],
              dictionaries,
              :class
            ),
          plus: spell_resistance_number!(name, amount["plus"])
        }

      "per_take" ->
        %{
          kind: :per_take,
          sr: spell_resistance_number!(name, amount["sr"]),
          max_total: spell_resistance_number!(name, amount["max_total"])
        }

      other ->
        raise "feat_spell_resistance.json: #{name} states amount kind " <>
                "#{inspect(other)}, which this loader does not know"
    end
  end

  defp spell_resistance_amount_shape(_entry, _name, _dictionaries), do: nil

  defp spell_resistance_number!(name, value),
    do: BonusMarkup.number!(@spell_resistance_file, name, value, "a whole number")
end
