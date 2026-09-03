defmodule BuildCalculator.Data.Loader.Classes do
  @moduledoc """
  Классы: ванильные записи, разовый выбор при первом уровне класса, сиальский слой
  поверх них и разбор того, **что именно меняет факт шарда**.

  Два соседних модуля отпочковались отсюда задачей 3.46 (заход 3), и оба названы
  тем, что в них лежит: `Loader.FactReceivers` — получатели факта (`changes[].affects`),
  `Loader.ClassFeatFacts` — то, что говорят о классах страницы фитов.
  """

  alias BuildCalculator.Data.Loader.NotAGap
  alias BuildCalculator.Data.Loader.Reading
  alias BuildCalculator.Data.Loader.Skills
  alias BuildCalculator.Data.Loader.Spells
  alias BuildCalculator.Rules.AttackModifiers

  import BuildCalculator.Data.Loader.Reading

  @requirement_keys Reading.requirement_keys()

  # The three saving throws, as our own JSON spells them. One list rather than
  # two `~w(fort ref will)` literals: the save labels are now read into the
  # ruleset as well as verified against the progression tables, and a save that
  # one of the two forgot would be a save whose word is never checked.
  @save_keys ~w(fort ref will)

  # Alignment restrictions and requirements arrive as short English phrases. The
  # vocabulary is closed, so it is transcribed here rather than pattern-matched
  # in the rules core; anything outside this table normalises to nil and is
  # reported as a gap instead of being guessed at.
  @alignment_phrases %{
    "none" => :any,
    "any" => :any,
    "any lawful" => %{require: ["lawful"]},
    "any chaotic" => %{require: ["chaotic"]},
    "any non-lawful" => %{forbid: ["lawful"]},
    "any non-chaotic" => %{forbid: ["chaotic"]},
    "any good" => %{require: ["good"]},
    "any evil" => %{require: ["evil"]},
    "any neutral" => %{require: ["neutral"]},
    "any non-good" => %{forbid: ["good"]},
    "any non-evil" => %{forbid: ["evil"]},
    "any non-evil and non-chaotic" => %{forbid: ["evil", "chaotic"]},
    "lawful good only" => %{exact: ["lawful_good"]}
  }

  # ---------------------------------------------------------------- classes --

  def build_classes(:missing, _skills), do: raise("vanilla/classes.json is required and missing")

  def build_classes(list, skills) do
    Map.new(list, fn c ->
      id = atom(c["id"])
      {class_skills, skill_conflicts} = class_skills(c, skills)

      {id,
       %{
         id: id,
         name: c["name"],
         # The shard's own page title, filled in by the Siala layer below. It is
         # a **search and matching** key, never a label: a class is shown in
         # English (CLAUDE.md §4), unlike a race, whose Siala name leads. Without
         # it importing somebody's build off the forum cannot resolve
         # «Мастер оружия», and there is no other place to learn it from —
         # `name_map.json` carries skills, feats and spells, no classes at all.
         ru: nil,
         prestige?: c["prestige"] == true,
         hit_die: c["hit_die"],
         hit_die_raw: c["hit_die_raw"],
         # Хит-дайс как функция уровня КЛАССА — `nil` у 22 классов из 23, и
         # у них ответ целиком в `hit_die` рядом. Ступени есть там, где страница
         # печатает дайс построчно (`red dragon disciple`: d6 → d8 → d10 → d12,
         # `Wiki.ClassPage.hit_die_by_class_level/3`), и читает их один
         # `Rules.Progression.hit_die/3` — оба поля вместе, чтобы разъехаться
         # было нечему.
         hit_die_by_class_level: hit_die_steps!(c),
         skill_points: c["skill_points"],
         # Vanilla's "max level" column: 20 for base classes, 10 (5) for prestige.
         # The effective cap also depends on the ruleset, see `Rules.LevelUp`.
         max_level: c["max_level"],
         bab_progression: c["bab_progression"],
         # The same kind of label for each of the three saves — `"good"` /
         # `"poor"`, off the class page's own «Primary saving throw(s)» line
         # (task «разбор сейвов по классам»). Two values in the whole corpus,
         # not three: a save is either primary for the class or it is not.
         #
         # ⚠ A **label**, exactly like `bab_progression` beside it: what one is
         # worth per class level lives in `save_from_label/2` alone, and
         # `verify_saves!/3` checks it against all 990 vanilla save cells at
         # compile time. That check is what makes the label safe to print next
         # to a number taken from the table — the two cannot disagree, because
         # a snapshot where they did would not compile.
         save_progressions: save_progressions(c),
         progression: progression(c),
         # Both spell tables are keyed by *class* level and both stop at 20 —
         # there is no epic spell progression for anybody (CLAUDE.md §6). The
         # rules core needs the wall, not just the rows, so it is stored.
         spells_per_day: Spells.spell_table(c, "spells_per_day"),
         spells_known: Spells.spell_table(c, "spells_known"),
         spell_table_max_class_level: Spells.spell_table_max(c),
         # Which ability the class casts off, as the wiki's "primary ability"
         # label states it (`"[[wisdom]]"`). Half of "able to cast Nth level
         # spells" is the table above; the other half is a score of 10 + N in
         # *this* ability, and without the field that half was unchecked.
         # `nil` for the sixteen non-casters, and `nil` is not "assume it is
         # fine": see `Rules.Prereqs`.
         casting_ability: Skills.ability_word(c["primary_ability_raw"]),
         bonus_feat_levels: MapSet.new(c["bonus_feat_levels"] || []),
         epic_bonus_feat_levels: MapSet.new(c["epic_bonus_feat_levels"] || []),
         # ⚠ Сколько слотов даёт класс на своём уровне, и **только там, где их
         # больше одного** — сегодня это одна запись во всём корпусе
         # (`ranger` → `%{35 => 2}`). Уровня здесь нет — значит слот один; ключ
         # у 22 классов из 23 отсутствует, и его отсутствие и есть это «один».
         #
         # Отдельным полем, а не заменой двух множеств выше: множества отвечают
         # на «выдаёт ли класс слот на этом уровне» и читаются полудюжиной мест,
         # а кратность — новый факт поверх того же ответа. Разъехаться им не
         # даёт `class_page.ex`: оба поля выводятся из одного прохода по строкам
         # таблицы (`bonus_feat_slots/1`), а `ClassBonusSlotsTest` проверяет
         # обходом всех классов обоих ruleset'ов, что уровень с кратностью
         # всегда лежит и в множестве.
         bonus_feat_counts:
           bonus_feat_counts(c["bonus_feat_counts"], c["epic_bonus_feat_counts"]),
         # Семейства фитов, которыми шард РАСШИРИЛ состав бонусного пула этого
         # класса — имена категорий из `siala_41/classes.json` →
         # `_bonus_feat_pools`, заполняется фактом `bonus_feat_pool` ниже.
         # Пусто у ванили всегда и у 21 класса Сиалы из 23.
         #
         # ⚠ Здесь лежит имя семейства со своим селектором (`%{"epic_spell_feats"
         # => %{feat_type: "epic spell"}}`), а не список фитов: сами фиты
         # разрешаются позже, когда справочник фитов построен, и ложатся
         # в `bonus_for` каждого из них — туда же, где живёт ванильный ответ
         # на тот же вопрос (`Loader.Feats.widen_bonus_pools/2`). Второго
         # места, где хранится «что примет бонусный слот», не заведено
         # намеренно: `Rules.FeatSlots` читает `bonus_for` и только его.
         bonus_feat_pool_adds: %{},
         class_skills: class_skills,
         class_skill_conflicts: skill_conflicts,
         # ⚠️ Here stood "structured prerequisites are not parsed yet — only
         # `requirements_raw` prose exists": stale. All twelve prestige classes
         # carry a structured `requirements` block on both rulesets (checked by
         # call 10.08.2026), so `Rules.LevelUp` reaches no class with
         # {:missing_data, {:class_requirements, …}} today. `requirements_raw`
         # stays alongside it — it is what the block is checked against, and it
         # is what puts the gap back if the block ever goes missing. See
         # `Loader.Gaps.gaps/…` and the moduledoc of `Rules.LevelUp`.
         requirements: requirements(c["requirements"]),
         requirements_unsupported: requirements_unsupported(c["requirements"]),
         requirements_raw: c["requirements_raw"],
         alignment_restriction:
           alignment_phrase(c["alignment_restriction"] || c["alignment_restriction_raw"]),
         alignment_restriction_raw: c["alignment_restriction_raw"],
         # Feats the class hands out for free, keyed by class level: read off the
         # feats column of the wiki progression table, plus the Toughness the
         # shard grants at level 1 to every martial class. Without it a Fighter
         # would be asked to *take* a feat he already has (it gates Dwarven
         # Defender).
         granted_feats: granted_feats(c["granted_feats"]),
         # The rank of a granted feat, where the wiki fragment carried one:
         # `%{5 => %{defensive_awareness: "II"}}`. One wiki page covers a whole
         # family of ranked abilities, so `granted_feats` alone collapses
         # "Rage 1/day" and "Greater Rage 4/day" onto the same id; this is what
         # tells them apart, and its absence is what `repeated_grants/1`
         # reports. Levels with no rank in the source are simply absent — an
         # empty string would read as "the rank is blank".
         granted_feat_ranks: granted_feat_ranks(c["granted_feat_ranks"]),
         # The mirror image of `granted_feats`: general feats a level of this
         # class may **not** be spent on. Off the class page's own
         # `Unavailable feats` label — «These general feats cannot be selected
         # when taking a level of bard» — resolved to ids by `mix wiki.parse`.
         #
         # Not a prerequisite and not a property of the feat: the very same feat
         # is fine on the next level if that level belongs to another class. It
         # is read by `Rules.FeatSlots` as a property of the *level* being taken.
         # Without it the picker offered `Quicken spell` on a Fighter level.
         unavailable_feats: MapSet.new(Enum.map(c["unavailable_feats"] || [], &atom/1)),
         # The shard's own groupings this class belongs to, by their page titles
         # («Воины Сагры»). Empty for vanilla and for the sixteen Siala classes
         # that belong to none; filled by the shard layer's `class_group` change.
         # Read only to assemble `ruleset.class_groups` and to cross-check it —
         # see `class_groups/2` and `BuildCalculator.Rules.ClassGroups`.
         class_groups: [],
         # Оружие, на которое шард РАСПРОСТРАНИЛ умения этого класса сверх того,
         # что называет собственный источник каждого умения (задача 3.101).
         # Пусто у ванили всегда и у 22 классов Сиалы из 23: единственная такая
         # строка сегодня — «Все классовые умения Тайного лучника теперь
         # распространяются на малый и большие арбалеты».
         #
         # ⚠ Здесь лежит ОРУЖИЕ, а не список умений: какие умения у класса есть,
         # уже сказано `granted_feats`, и вторая копия этого списка разошлась бы
         # с первой — ровно та поломка, которую задача 3.85 чинила у бонусных
         # пулов («две записи об одном правиле, и вторая не знает, что первая
         # сработала»).
         ability_weapons: MapSet.new(),
         # Shard changes, kept whole so the UI can show them and nothing
         # disappears silently. `siala_unapplied` is the subset that did **not**
         # reach a mechanical home — see `apply_class_changes/2`.
         siala_changes: [],
         siala_unapplied: [],
         source: c["source"]
       }}
    end)
  end

  # JSON object keys are strings; the class level they stand for is a number.
  defp granted_feats(map) when is_map(map) do
    Map.new(map, fn {level, ids} ->
      {String.to_integer(level), Enum.map(ids, &atom/1)}
    end)
  end

  defp granted_feats(_absent), do: %{}

  # `%{"5" => %{"defensive_awareness" => "II"}}` as the parser writes it.
  defp granted_feat_ranks(map) when is_map(map) do
    for {level, ranks} <- map, is_map(ranks), into: %{} do
      {String.to_integer(level), Map.new(ranks, fn {feat, rank} -> {atom(feat), rank} end)}
    end
  end

  defp granted_feat_ranks(_absent), do: %{}

  # `%{"35" => 2}` как их пишет парсер, из двух таблиц в одну карту: обе
  # ключуются **классовым** уровнем и не пересекаются (эпическая начинается
  # там, где кончается основная), поэтому у них одно пространство ключей —
  # ровно как у `granted_feats` рядом.
  defp bonus_feat_counts(pre_epic, epic) do
    for map <- [pre_epic, epic], is_map(map), {level, count} <- map, into: %{} do
      {String.to_integer(level), count}
    end
  end

  # Normalises a requirements object to atom keys the rules core understands.
  # Unrecognised keys are dropped from the checkable set but remain visible in
  # `gaps` through `requirements_unsupported/1`.
  defp requirements(nil), do: nil

  defp requirements(map) when is_map(map) do
    for {key, value} <- map, key in @requirement_keys, into: %{} do
      case key do
        "alignment" -> {:alignment, alignment_phrase(value)}
        _ -> {String.to_atom(key), value}
      end
    end
  end

  defp requirements_unsupported(nil), do: []

  defp requirements_unsupported(map) when is_map(map) do
    for {key, _} <- map, key not in @requirement_keys, do: key
  end

  # The hand-written layer over a prestige class's requirements
  # (`vanilla/class_requirements.json`).
  #
  # Some requirements are stated on the page and *meant* somewhere else on it:
  # Pale Master asks for «arcane spellcasting: level 3 or higher», and the Notes
  # section of the same page says that this is a caster level and that three
  # levels of bard, sorcerer or wizard satisfy it. No parser reaches a sentence
  # like that, so the machine layer writes the label out verbatim and the loader
  # turns it into `{:missing_data, {:requirement, class, key}}` — a gap that
  # names the hole and, deliberately, leaves the class takeable on the half that
  # *was* read. For Pale Master the unread half was the whole of it, so the class
  # could be taken at character level 1 with no spellcasting at all.
  #
  # An entry here is one human reading of one such place, in the same schema the
  # machine layer writes and `Rules.Prereqs` checks.
  #
  # ⚠ `replaces` is what stood in the machine layer when the entry was written,
  # and it is compared byte for byte. Two ways for these files to drift are
  # closed by that: the page changing under a re-parse, and `mix wiki.parse`
  # learning to read the place by itself. Both raise at compile time and are
  # settled by a human deleting or rewriting the entry — never by the loader
  # picking a winner.
  def apply_class_requirements(classes, :missing, _raw_classes), do: classes

  def apply_class_requirements(classes, %{"classes" => entries}, raw_classes)
      when is_list(entries) do
    raw = Map.new(raw_classes, fn c -> {atom(c["id"]), c["requirements"] || %{}} end)

    Enum.reduce(entries, classes, fn entry, acc ->
      id = atom(entry["id"])

      class =
        Map.get(acc, id) ||
          raise "class_requirements.json names #{entry["id"]}, which is not a class"

      verify_replaced!(entry, class, Map.get(raw, id, %{}))

      case entry["verdict"] do
        "applied" ->
          Map.put(acc, id, merge_requirements(class, entry))

        # `not_binding`: the requirement was read and the answer is known — there
        # is nothing left to check, because another requirement of the same class
        # already guarantees it. The key leaves the unread list (an empty gap
        # here is knowledge, not silence) and **no** check is added. Shifter is
        # the case: whatever «Spellcasting: level 3 or higher» means there, a
        # character who owns `wild shape` owns five druid levels, and Dan
        # observed a druid 5 with WIS 12 — two circles of spells, not three —
        # being offered the class on the test server.
        #
        # ⚠ Kept apart from `applied` on purpose. Both end up calling the same
        # merge, but they are different claims: `applied` says "here is the
        # check", this says "no check is needed, and here is why". Collapsing
        # them would let an entry that states no requirements read as an applied
        # one that forgot to.
        "not_binding" ->
          if entry["requirements"] not in [nil, %{}] do
            raise """
            class_requirements.json: #{entry["id"]} is "not_binding" but states requirements. \
            A requirement that binds nothing has nothing to check — use "applied" if it does.
            """
          end

          Map.put(acc, id, merge_requirements(class, entry))

        # `not_modelled`: the entry is documentation. The key stays unread, the
        # gap stays, the class stays takeable.
        _not_modelled ->
          acc
      end
    end)
  end

  def apply_class_requirements(classes, _other, _raw_classes), do: classes

  defp verify_replaced!(entry, class, raw_requirements) do
    for {key, expected} <- entry["replaces"] || %{} do
      actual = Map.get(raw_requirements, key, :absent)

      if actual != expected do
        raise """
        class_requirements.json: #{entry["id"]} says its "#{key}" requirement reads \
        #{inspect(expected)}, but vanilla/classes.json now has #{inspect(actual)}. \
        The page moved under the entry — reread it and rewrite the entry.
        """
      end

      if key not in class.requirements_unsupported do
        raise """
        class_requirements.json: #{entry["id"]} claims to replace "#{key}", which the \
        parser now reads by itself. The entry is stale — delete it.
        """
      end
    end
  end

  defp merge_requirements(class, entry) do
    block = entry["requirements"] || %{}
    added = requirements(block)

    case requirements_unsupported(block) do
      [] -> :ok
      keys -> raise "class_requirements.json: #{entry["id"]} uses unknown keys #{inspect(keys)}"
    end

    # Приписка, которую запись сделала проверяемой, снимается ДО проверки
    # на перезапись: иначе запись, оставляющая рядом честный остаток
    # («ranged проверили, unarmed strike — нет»), считалась бы перезаписью
    # ключа `qualifiers` и роняла бы сборку.
    existing = drop_qualifiers!(class.requirements || %{}, entry)

    case Enum.filter(Map.keys(added), &Map.has_key?(existing, &1)) do
      [] -> :ok
      keys -> raise "class_requirements.json: #{entry["id"]} overwrites #{inspect(keys)}"
    end

    %{
      class
      | requirements: Map.merge(existing, added),
        requirements_unsupported:
          class.requirements_unsupported -- Map.keys(entry["replaces"] || %{})
    }
  end

  # Приписка, которую запись СДЕЛАЛА проверяемой, — `supersedes_qualifiers`
  # (задача 3.99).
  #
  # У класса `requirements` только ДОПОЛНЯЕТ блок (перезапись ключа роняет
  # сборку выше), поэтому убрать оговорку нечем: «weapon focus **in a melee
  # weapon**» — одно предложение, прочитанное дважды, и запись выражает его
  # ключом `feat_choice_properties`, а фраза остаётся рядом и продолжает
  # говорить «мы это не проверяем». Это ровно та ложная неопределённость
  # наоборот, которую запрещает CLAUDE.md §6.
  #
  # ⚠ Список ФРАЗ, а не «убрать все»: у класса может стоять приписка про что-то
  # ещё, и снимать её не за что. Названная фраза обязана быть на месте — иначе
  # это опечатка или страница уехала, и молчаливое «нечего убирать» неотличимо
  # от применённой записи. Тот же сторож и тот же довод, что у `replaces` выше.
  defp drop_qualifiers!(requirements, entry) do
    case entry["supersedes_qualifiers"] || [] do
      [] ->
        requirements

      phrases ->
        stated = Map.get(requirements, :qualifiers) || []

        case phrases -- stated do
          [] ->
            :ok

          missing ->
            raise """
            class_requirements.json: #{entry["id"]} says it supersedes \
            #{inspect(missing)}, which vanilla/classes.json does not state. \
            Reread the page and rewrite the entry — a phrase that is not there \
            cannot be the one the new key replaces.
            """
        end

        case stated -- phrases do
          [] -> Map.delete(requirements, :qualifiers)
          rest -> Map.put(requirements, :qualifiers, rest)
        end
    end
  end

  # -------------------------------------------------------- class choices --

  # `priv/rules/vanilla/class_choices.json` — a class that asks for a one-time
  # pick out of a named domain when its OWN first class level is taken (a
  # Cleric's two domains; a future Wizard's school, task 3.10). Same schema
  # `Rules.ClassChoices` reads, and the same "one human reading, cited" shape
  # as `apply_class_requirements/3` above — see that function's doc for why
  # the fact lives here rather than in `classes.json` itself.
  #
  # ⚠ Only `"applied"` is understood today, and anything else raises rather
  # than being skipped: unlike `class_requirements.json`'s `not_binding` /
  # `not_modelled`, there is no reading of "a class has a choice, but we are
  # not going to say what it is" that keeps the fact honest — a choice either
  # is checked or it does not exist yet in the model, and a silently skipped
  # verdict would be a class quietly missing its domain picker.
  def build_class_choices(:missing, _classes), do: %{}

  def build_class_choices(%{"classes" => entries}, classes) when is_list(entries) do
    Map.new(entries, fn entry ->
      id = atom(entry["id"])

      unless Map.has_key?(classes, id) do
        raise "class_choices.json names #{entry["id"]}, which is not a class"
      end

      unless entry["verdict"] == "applied" do
        raise "class_choices.json: #{entry["id"]} has verdict #{inspect(entry["verdict"])}, " <>
                "and only \"applied\" is understood — see this function's doc"
      end

      domain =
        atom(entry["domain"] || raise("class_choices.json: #{entry["id"]} names no domain"))

      count = entry["count"] || raise("class_choices.json: #{entry["id"]} names no count")

      {id,
       %{
         domain: domain,
         count: count,
         # Both default true: every entry today states them explicitly, and a
         # future one that omits them gets the reading that matches "choose
         # N of these" — distinct picks, and the choice is not optional
         # unless the source says a class may skip it (a Wizard's
         # specialization will, task 3.10).
         distinct?: Map.get(entry, "distinct", true),
         required?: Map.get(entry, "required", true),
         # Filled in below by `build_class_choice_no_selection/2`, never
         # omitted: a caller that reads `spec.no_selection_name` (the way it
         # already reads `spec.domain`) gets `nil` for a Cleric rather than a
         # `KeyError`.
         no_selection_name: nil
       }}
    end)
  end

  def build_class_choices(_other, _classes), do: %{}

  # ---------------------------------------- class choice "no selection" --

  @doc """
  Layers the word the game CLIENT prints for "this choice, left unmade" onto
  an already-built `class_choices` map — a Wizard's `General` (task 3.170,
  AGENT_QUEUE.md).

  Deliberately a second pass over `build_class_choices/2`'s own output rather
  than a field read inside that function: the mechanic there (`required?:
  false`, `count: 1`) was already correct on its own — a build with nothing
  picked is already legal and already complete (`Rules.ClassChoices.
  complete?/3`) — and this only names the state that mechanic already
  produces, out of `priv/rules/vanilla/class_choice_no_selection.json`, a
  file of its own for the two reasons its `_note` gives: it does not touch
  the "no specialization is an absent value, not a pseudo-school" decision
  `class_choices.json` already recorded, and it is not
  `vanilla/spell_schools.json` (`universal`'s own `name`), because that file
  is rewritten wholesale by `mix wiki.parse` and a hand edit there would not
  survive the next run.

  Every class not named in the file keeps `no_selection_name: nil` — a
  Cleric, whose "nothing chosen" is not a legal state to have a word for at
  all. Naming a class here whose choice is `required?: true` raises rather
  than being accepted silently: a button captioned by this fact offers
  "nothing chosen" as a legitimate action, and offering it where the class
  choice is mandatory would be a false legality reachable by editing data
  alone, the exact failure mode `illegal_feats/2`'s rewrite (task 3.84)
  exists to catch elsewhere.
  """
  @spec build_class_choice_no_selection(term(), %{atom() => map()}) :: %{atom() => map()}
  def build_class_choice_no_selection(:missing, class_choices), do: class_choices

  def build_class_choice_no_selection(%{"classes" => entries}, class_choices)
      when is_list(entries) do
    Enum.reduce(entries, class_choices, fn entry, acc ->
      id = atom(entry["id"])

      spec =
        Map.get(acc, id) ||
          raise "class_choice_no_selection.json names #{entry["id"]}, " <>
                  "which has no class_choices.json entry"

      if spec.required? do
        raise "class_choice_no_selection.json names #{entry["id"]}, whose choice is " <>
                "required? true — \"nothing chosen\" is not a legal state for it, " <>
                "see class_choices.json"
      end

      # ⚠ The button this word captions clears the choice by toggling ONE
      # value off (`builder_live.html.heex`, `#class-choice-none`, which
      # passes `List.first(chosen)` back through `toggle_class_choice`), so
      # it only empties a `count: 1` choice. A class allowed to skip a
      # two-value choice would get a button that clears half of it and then
      # reports itself as chosen — worse than no button, because the screen
      # would state something untrue. Today no such class exists; the day one
      # arrives the build stops rather than shipping the half-clear, and
      # whoever adds it decides between a multi-clear event and a different
      # control.
      if spec.count > 1 do
        raise "class_choice_no_selection.json names #{entry["id"]}, whose choice takes " <>
                "#{spec.count} values — the \"no selection\" button clears one value at a " <>
                "time and would leave the rest standing, see builder_live.html.heex"
      end

      name =
        entry["name"] || raise "class_choice_no_selection.json: #{entry["id"]} names no name"

      Map.put(acc, id, %{spec | no_selection_name: name})
    end)
  end

  def build_class_choice_no_selection(_other, class_choices), do: class_choices

  defp alignment_phrase(nil), do: nil
  defp alignment_phrase(spec) when is_map(spec), do: spec

  defp alignment_phrase(phrase) when is_binary(phrase) do
    normalised =
      phrase
      |> String.replace(~r/\[\[(?:[^\]|]*\|)?([^\]]+)\]\]/, "\\1")
      |> String.downcase()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
      |> String.trim(".")

    Map.get(@alignment_phrases, normalised)
  end

  # `[%{from: 1, die: 6}, %{from: 4, die: 8}, …]`, or `nil` where the snapshot
  # carries no scale at all. **The last step covers every class level above it**
  # — that is what makes the shape usable past the class's own table (Siala
  # takes a prestige class to 31, `red dragon disciple`'s table stops at 10) and
  # also what makes a malformed scale dangerous: a step out of order, or a first
  # step above class level 1, would silently hand some level the wrong die. So
  # anything this cannot read **raises at compile time**, exactly as a broken
  # markup file does — the snapshot is machine-written and reviewed by a human,
  # and a scale nobody can trust is worse than the `nil` it replaced.
  defp hit_die_steps!(class) do
    case class["hit_die_by_class_level"] do
      nil ->
        nil

      steps when is_list(steps) and steps != [] ->
        steps |> Enum.map(&hit_die_step!(class, &1)) |> verify_hit_die_steps!(class)

      other ->
        raise "#{class["id"]}: hit_die_by_class_level is #{inspect(other)}, expected a " <>
                "non-empty list of steps"
    end
  end

  defp hit_die_step!(_class, %{"from" => from, "die" => die})
       when is_integer(from) and from >= 1 and is_integer(die) and die >= 1 do
    %{from: from, die: die}
  end

  defp hit_die_step!(class, step) do
    raise "#{class["id"]}: hit_die_by_class_level step #{inspect(step)} is not " <>
            "{from: positive class level, die: positive number of sides}"
  end

  defp verify_hit_die_steps!(steps, class) do
    froms = Enum.map(steps, & &1.from)

    cond do
      hd(froms) != 1 ->
        raise "#{class["id"]}: hit_die_by_class_level starts at class level #{hd(froms)}, so " <>
                "levels below it have no die at all"

      froms != Enum.sort(froms) or froms != Enum.uniq(froms) ->
        raise "#{class["id"]}: hit_die_by_class_level steps are #{inspect(froms)} — a scale is " <>
                "read by its last applicable step, so the order is the meaning"

      true ->
        steps
    end
  end

  # Per class level: the BAB and save numbers straight off the wiki progression
  # table. Nothing is re-derived — the table is the fact.
  #
  # The label formula is checked against every row of every class here, at
  # compile time (330 BAB cells and 990 save cells at the time of writing, all
  # agreeing). That check is what makes `bab_from_label/2` usable further down:
  # when the shard restates a class's BAB progression as a label and gives no
  # table of its own, the table is regenerated from a formula that has been
  # validated against the whole vanilla corpus rather than assumed.
  defp progression(class) do
    rows = class["progression"] || []

    for %{"level" => level} = row <- rows, is_integer(row["bab"]), into: %{} do
      verify_bab!(class, level, row["bab"])
      verify_saves!(class, level, row)

      {level, %{bab: row["bab"], fort: row["fort"], ref: row["ref"], will: row["will"]}}
    end
  end

  # `%{fort: "good", ref: "poor", will: "poor"}` — one label per save, whatever
  # the snapshot carries, `nil` where it carries nothing. Keys are always all
  # three so a reader never has to tell "no label" from "no such save".
  defp save_progressions(class) do
    labels = class["saves"] || %{}

    Map.new(@save_keys, fn save -> {atom(save), labels[save]} end)
  end

  defp verify_bab!(class, level, actual) do
    case bab_from_label(class["bab_progression"], level) do
      ^actual ->
        :ok

      expected ->
        raise """
        #{class["id"]} level #{level}: base attack table says #{actual}, but the \
        "#{class["bab_progression"]}" label works out to #{expected}
        """
    end
  end

  defp verify_saves!(class, level, row) do
    for save <- @save_keys do
      actual = row[save]
      expected = save_from_label(get_in(class, ["saves", save]), level)

      if actual != expected do
        raise """
        #{class["id"]} level #{level}: #{save} table says #{actual}, but the \
        "#{get_in(class, ["saves", save])}" label works out to #{expected}
        """
      end
    end
  end

  # source: fandom "Base attack bonus" — high +1/level, medium +3/4, low +1/2.
  # Verified against every vanilla progression row by `verify_bab!/3`.
  defp bab_from_label("high", level), do: level
  defp bab_from_label("medium", level), do: div(level * 3, 4)
  defp bab_from_label("low", level), do: div(level, 2)
  defp bab_from_label(_other, _level), do: nil

  # source: fandom "Base save" — good 2 + level/2, poor level/3.
  # Verified against every vanilla progression row by `verify_saves!/3`.
  defp save_from_label("good", level), do: 2 + div(level, 2)
  defp save_from_label("poor", level), do: div(level, 3)
  defp save_from_label(_other, _level), do: nil

  # Class-skill membership has two independent sources on Fandom: the class page
  # (`class_skills_raw`) and each skill page (`classes_raw` in skills.json). They
  # agree almost everywhere; where they do not, `mix wiki.parse` settles it and
  # writes both the resolved list (`class_skills`) and the disagreement
  # (`class_skills_conflict`) into the snapshot. **The decision is data, not
  # code** — this reads it and turns every disagreement into a `{:conflict, ...}`
  # gap, so the reconciliation stays visible and can be revised in one place.
  defp class_skills(class, skills) do
    case class["class_skills"] do
      list when is_list(list) -> {MapSet.new(list, &slug/1), stated_conflicts(class)}
      _unresolved -> derive_class_skills(class, skills)
    end
  end

  @conflict_sources %{"class_page" => :class_page_only, "skill_page" => :skill_page_only}

  defp stated_conflicts(class) do
    for entry <- class["class_skills_conflict"] || [],
        only_in = Map.get(@conflict_sources, entry["stated_by"]),
        do: {slug(entry["skill"]), only_in}
  end

  # A snapshot from before the parser resolved this — or a hand-written class
  # that only lists its skills as prose — still yields the same union.
  defp derive_class_skills(class, skills) do
    id = atom(class["id"])
    index = skill_alias_index(skills)

    from_class =
      class["class_skills_raw"]
      |> wiki_links()
      |> Enum.map(&Map.get(index, &1, &1))
      |> MapSet.new()

    if map_size(skills) == 0 do
      {from_class, []}
    else
      from_skills =
        for {sid, skill} <- skills,
            skill.classes_all? or id in skill.class_for,
            into: MapSet.new(),
            do: sid

      conflicts =
        Enum.sort(
          Enum.map(MapSet.difference(from_class, from_skills), &{&1, :class_page_only}) ++
            Enum.map(MapSet.difference(from_skills, from_class), &{&1, :skill_page_only})
        )

      {MapSet.union(from_skills, from_class), conflicts}
    end
  end

  # skills.json keys a skill by its page title, so "Heal (skill)" becomes
  # :heal_skill while a class page links it as [[heal (skill)|heal]] -> :heal.
  # The display name reconciles the two.
  defp skill_alias_index(skills) do
    for {id, skill} <- skills, skill.name, into: %{}, do: {slug(skill.name), id}
  end

  def wiki_links(nil), do: []

  def wiki_links(raw) do
    ~r/\[\[([^\]]+)\]\]/
    |> Regex.scan(raw, capture: :all_but_first)
    |> Enum.map(fn [inner] ->
      inner
      |> String.split("|")
      |> List.last()
      |> slug()
    end)
  end

  # ----------------------------------------------------- shard class layer --

  # `priv/rules/siala_41/classes.json` is a hand-written diff: per class, a list
  # of `%{"what" => field, "value" => ...}` changes lifted off the shard's wiki.
  # Only the ones with a mechanical home are applied; the rest travel along in
  # `class.siala_changes` so nothing vanishes without a trace.
  def apply_class_layer(classes, shard, pools \\ %{})

  def apply_class_layer(classes, :missing, _pools), do: {classes, []}

  def apply_class_layer(classes, %{"classes" => entries}, pools) do
    Enum.reduce(entries, {classes, []}, fn entry, {acc, modifiers} ->
      id = atom(entry["vanilla_id"] || entry["id"])

      case Map.fetch(acc, id) do
        :error ->
          {acc, modifiers}

        {:ok, class} ->
          changes = entry["changes"] || []

          Enum.each(changes, fn change ->
            verify_not_a_gap!(id, change)
            verify_status!(id, change)
          end)

          {updated, unapplied} =
            apply_class_changes(%{class | siala_changes: changes}, changes, pools)

          # `ru` rides along with the layer that owns it: every entry in
          # `siala_41/classes.json` cites its own Siala page and revid, so the
          # vanilla ruleset legitimately has none and matching by Russian name
          # simply finds nothing there.
          {Map.put(acc, id, %{updated | siala_unapplied: unapplied, ru: entry["ru"] || class.ru}),
           modifiers ++ attack_modifiers(id, changes, acc)}
      end
    end)
  end

  def apply_class_layer(classes, _other, _pools), do: {classes, []}

  @doc """
  Словарь `_bonus_feat_pools` сиальского файла классов — прочитанный и выверенный.

  Отдельной функцией, а не внутри слоя, ровно по той же причине, что
  `Loader.FactReceivers.gap_receivers!/1`: словарь закрыт, и расхождение с ним
  обязано ронять сборку **до** того, как кто-нибудь применит половину фактов.

  Читается один раз и передаётся вниз, потому что имя категории проверяется
  на стадии класса (справочника фитов там ещё нет), а разрешается в фиты
  позже — `Loader.Feats.widen_bonus_pools/3`.

  ⚠ Роняет сборку только на **форме** словаря: селектор, который загрузчик
  не умеет прочитать, — это данные, разошедшиеся с кодом. Категория, которую
  словарь не объявляет, сборку не роняет и ничего не делает: это шард сказал
  то, чего мы не формализовали, и такое обязано доехать до игрока гэпом,
  а не упасть (CLAUDE.md §3).

  ## Селекторов два, и второй — не по полю фита

  `feat_type` сравнивает `feats[].type` как есть, и им объявлено семейство
  эпических заклинаний. `weapon_proficiency: true` разрешается в пять фитов
  владения кастомной «Системы оружия», и берутся они **не отсюда**, а из
  `vanilla/weapons.json` (`_siala_proficiency.groups[].siala_feat`) — тем же
  реестром, которым справочник оружия отвечает на вопрос «какой фит владения
  требует эта группа». Поэтому и параметр: список id сюда не переписан ни разу.

  ⚠ По полю фита эту пятёрку не выбрать вовсе: `type` у неё обычный `general`
  (владения берут и общим слотом), то есть селектор по типу забрал бы в пул
  весь общий справочник.

  ⚠ Второй аргумент обязателен, без умолчания: пустое множество означало бы
  «фитов владения нет», и категория, которую словарь объявил, упала бы уже
  на этом основании — то есть забытая проводка выглядела бы как порча данных.
  """
  @spec bonus_feat_pools!(map() | :missing, MapSet.t(atom())) :: %{String.t() => map()}
  def bonus_feat_pools!(:missing, _weapon_proficiency_feats), do: %{}

  def bonus_feat_pools!(%{"_bonus_feat_pools" => %{} = declared}, weapon_proficiency_feats) do
    for {name, selector} <- declared, not String.starts_with?(name, "_"), into: %{} do
      keys = for {key, _} <- selector, not String.starts_with?(key, "_"), do: key

      case {keys, selector} do
        {["feat_type"], %{"feat_type" => type}} when is_binary(type) and type != "" ->
          {name, %{feat_type: type}}

        {["weapon_proficiency"], %{"weapon_proficiency" => true}} ->
          {name, %{feat_ids: weapon_proficiency_feats!(name, weapon_proficiency_feats)}}

        _other ->
          raise """
          siala_41/classes.json: категория бонусного пула #{inspect(name)} объявлена
          селектором #{inspect(selector)}. Загрузчик умеет два — `feat_type`
          со строкой (`feats[].type` как есть) и `weapon_proficiency: true`
          (пять фитов владения из `weapons.json`). Форма, которую он прочитать
          не может, значила бы «пул расширен неизвестно чем», а молча расширить
          его ничем — тот же самый молчаливый разумный дефолт, ради запрета
          которого словарь и закрыт.
          """
      end
    end
  end

  def bonus_feat_pools!(_no_dictionary, _weapon_proficiency_feats), do: %{}

  # Реестр пуст — значит `weapons.json` перестал называть фиты владения, а не
  # «шард отменил систему»: категорию-то словарь объявил. Молчаливое пустое
  # расширение здесь неотличимо от применённого факта, ровно как в
  # `Loader.Feats.widen_one_pool/4`, поэтому это падение, а не тишина.
  defp weapon_proficiency_feats!(name, feats) do
    if MapSet.size(feats) == 0 do
      raise """
      siala_41/classes.json: категория бонусного пула #{inspect(name)} объявлена
      селектором `weapon_proficiency`, а `vanilla/weapons.json` не называет
      (`_siala_proficiency.groups[].siala_feat`) ни одного фита владения.
      Расширять нечем — либо реестр переехал, либо категорию назвали не тем именем.
      """
    end

    feats
  end

  # -------------------------------------------------- applying a shard fact --

  # Which changes reached a mechanical home, decided by **what actually
  # happened**, not by a list of field names. The difference is not academic: a
  # change whose `what` is one this loader knows but whose value it cannot use —
  # Arcane Archer's `requirements`, `unclear` with a null value — used to be
  # counted as applied and vanished without a trace. Now it is refused here and
  # named in `gaps`, which is the whole point of the status.
  defp apply_class_changes(class, changes, pools) do
    Enum.reduce(changes, {class, []}, fn change, {acc, unapplied} ->
      case apply_change(change, acc, pools) do
        {:ok, updated} -> {updated, unapplied}
        :skip -> {acc, unapplied ++ [change]}
        # ⚠ `:refuted` — третий исход, и он НЕ уходит в `unapplied`, в отличие
        # от `:skip`. Разница смысловая: `unapplied` означает «шард что-то
        # изменил, а мы не смогли это выразить» и честно доезжает до игрока
        # оговоркой. Опровергнутый факт — обратное: мы **знаем** ответ, он
        # ванильный, и оговорка тут была бы ложной тревогой того самого вида,
        # который §9 CLAUDE.md запрещает («пугать тем, что уже посчитано»).
        :refuted -> {acc, unapplied}
      end
    end)
  end

  # Статусы, которые файл вообще вправе назвать. Сторож стоит здесь, потому что
  # разбор `apply_change/3` идёт по ключу `what`, а не по статусу: опечатка
  # в `"refuted"` не отбросила бы факт, а **применила** бы его молча — то есть
  # ошибка была бы направлена в сторону ложного знания.
  @known_statuses ~w(verified custom unclear refuted)

  defp verify_status!(class_id, %{"status" => status} = change) when is_binary(status) do
    unless status in @known_statuses do
      raise """
      неизвестный status у факта класса #{class_id}: #{inspect(status)}
      what: #{inspect(change["what"])}

      Разрешены: #{Enum.join(@known_statuses, ", ")}.
      Статус решает, применить факт или отбросить, и опечатка здесь применяет
      его молча — поэтому сборка падает, а не догадывается.
      """
    end

    :ok
  end

  defp verify_status!(_class_id, _change), do: :ok

  @doc false
  # Точка входа для теста: сторож живёт в приватной функции, а проверять его
  # надо — иначе «сборка падает на опечатке» останется утверждением без проверки.
  def verify_status_for_test!(class_id, change), do: verify_status!(class_id, change)

  # A class that grants a feat id it already granted at a lower level. **87 such
  # places exist, across 13 classes**, counted by walking `ruleset.classes` on both
  # rulesets (10.08.2026). Same count on both, and — carefully — **not the same
  # places**: the shard stretched Purple Dragon Knight's schedule, so its second
  # `inspire_courage` sits at class level 8 instead of 4. One place moved, none
  # appeared or vanished.
  #
  # ⚠ Here stood «ten such places, across six classes». That was the count before
  # `ClassPage.feat_grants/1` learnt to read a family the page names in plain text
  # once its link has been used (`bone skin (+2AC)` two rows under the linked
  # one), i.e. since 08.08.2026 the comment claimed a scale **eight times too
  # small** — enough for the next reader to decide the ranked-grant machinery is
  # not worth a general answer. Both counts are pinned by tests now: the JSON
  # snapshot's by `Wiki.ClassGrantRanksTest`, the loaded ruleset's (this one) by
  # `Data.RepeatedGrantsTest`. Two claims, not one copy — the shard layer moves
  # grants, and the Purple Dragon Knight above is the proof that the two lists
  # are not the same list.
  #
  # **Not one of them is a duplicate**, and they come in two shapes:
  #
  #   * **49** whose rank differs from every earlier one — the wiki keeps one page
  #     per ability family, so distinct steps collapse onto one id;
  #   * **38** whose rank repeats an earlier one word for word — the same
  #     increment handed out again, which is a gain just as much (`sacred defense
  #     (+1)` comes fourteen more times after the first, `bone skin (+2AC)` seven).
  #
  # `progression[].feats_raw` tells them apart either way:
  #
  #     barbarian    1  [[barbarian rage]] (1x/day)   15  [[greater rage]] (4x/day)
  #     pale master  5  [[deathless vigor]] (+3HP)    15  [[deathless vigor]] (+5HP)
  #     shifter     13  [[infinite humanoid shape]]   16  [[infinite greater wildshape]] IV
  #
  # So the grant is **kept**: dropping it would hide a real gain, and showing the
  # id twice is merely imprecise where dropping is false. The rank is what makes
  # it precise, and it now has a home: `granted_feat_ranks` carries whatever tail
  # the parser found on the fragment. **A repeat is reported if and only if its
  # rank is unnamed** — where the parser managed to name it there is nothing
  # imprecise left to report, and a gap that is not true trains the reader to
  # skim the list.
  #
  # ⚠ Which today means this function returns **nothing at all**: all 87 ranks are
  # named, so neither ruleset carries a single `{:unnamed_grant_rank, …}`. That is
  # why the rule is exercised on fixtures as well — on the snapshot alone half of
  # the "if and only if" would never fire.
  #
  # Runs after the shard layer, so a level shift cannot fake a repeat.
  def repeated_grants(classes) do
    for {id, class} <- classes,
        {level, feat} <- repeats(class.granted_feats),
        is_nil(rank_at(class, level, feat)),
        do: {id, level, feat}
  end

  defp rank_at(class, level, feat) do
    class.granted_feat_ranks |> Map.get(level, %{}) |> Map.get(feat)
  end

  defp repeats(granted) do
    granted
    |> Enum.sort_by(fn {level, _ids} -> level end)
    |> Enum.reduce({MapSet.new(), []}, fn {level, ids}, {seen, again} ->
      {fresh, repeated} = Enum.split_with(ids, &(not MapSet.member?(seen, &1)))
      {MapSet.union(seen, MapSet.new(fresh)), again ++ for(f <- repeated, do: {level, f})}
    end)
    |> elem(1)
  end

  # ⚠ `unclear` is refused before anything else looks at it. It means a human
  # read the shard's page and could **not** pin the value down; turning it into
  # a rule anyway would assert a number the source never gave, which is the one
  # thing CLAUDE.md §3 forbids outright. Refusing it silently would be no better
  # — that is why the refusal lands in `siala_unapplied` and then in `gaps`.
  defp apply_change(%{"status" => "unclear"}, _class, _pools), do: :skip

  # ⚠ `refuted` — факт прочитан со страницы шарда верно, но **игра говорит иначе**,
  # и это проверено замером. Ранг источников §3 ставит наблюдение выше страницы
  # правил, поэтому факт не применяется — но и не считается «неразобранным»
  # (см. `:refuted` в `apply_class_changes/3`).
  #
  # Первый и пока единственный носитель — `wholeness_of_body` у монаха: страница
  # Сиалы даёт «Требования: Монах 2 уровня», а замер Dan 28.08.2026 показал
  # выдачу на 7-м, как в ванили. Туда же смотрит `cls_feat_monk.2da` из хаков.
  defp apply_change(%{"status" => "refuted"}, _class, _pools), do: :refuted

  # The shard restates the progression as a label and gives no table, so the BAB
  # column is regenerated with the formula validated against all of vanilla.
  # Saves are untouched — the shard changes none.
  defp apply_change(%{"what" => "bab_progression", "value" => label}, class, _pools)
       when is_binary(label) do
    progression =
      Map.new(class.progression, fn {level, row} ->
        {level, %{row | bab: bab_from_label(label, level) || row.bab}}
      end)

    {:ok, %{class | bab_progression: label, progression: progression}}
  end

  defp apply_change(%{"what" => "max_level", "value" => level}, class, _pools)
       when is_integer(level) do
    {:ok, %{class | max_level: level}}
  end

  # The shard restates the class's OWN progression as a table that reaches
  # further than the vanilla one it inherited, instead of as a label change —
  # Purple Dragon Knight's page prints all ten of its levels once the shard
  # doubled its schedule (`max_level` above), where the vanilla table this
  # class inherited stops at five (task 3.96, 25.08.2026). Before this clause
  # existed the five missing rows were not "a bit short": `progression_row/3`
  # (`Rules.Progression`) looks a class's whole contribution up by ONE
  # cumulative level, so the moment a build's Purple Dragon Knight levels
  # reached six the class's *entire* share of base attack and all three saves
  # read `nil` and summed to zero — ten levels of the class contributing less
  # than its own first five did alone.
  #
  # Every row is checked against the label already sitting on the class — the
  # very same `bab_from_label/2` / `save_from_label/2` pair vanilla's own 330
  # BAB and 990 save cells are checked against at compile time (`progression/1`
  # above) — so a table that ever disagreed with the class's own stated
  # progression fails the build rather than silently winning. Purple Dragon
  # Knight's label is untouched by any other fact on this class ("high" BAB,
  # saves as Fighter's — this class's own `unchanged_from_vanilla` note already
  # says the shard left both alone), so this is not a guess dressed up as a
  # check: **the quoted table's 40 cells — 10 levels × BAB plus three saves —
  # agree with the formula in all 40**, and that agreement is what makes
  # growing the table past vanilla's honest rather than assumed.
  #
  # ⚠ Merged into `class.progression` rather than only appended: a fact that
  # states a level the class already had is compared against what is already
  # there (`verify_progression_table_agrees!/2`) and must match it exactly.
  # A shard quote that silently disagreed with the table it claims to restate
  # would be exactly the kind of source drift CLAUDE.md §3 exists to catch,
  # and a plain `Map.merge/2` that let the newer value win without checking
  # would paper over it instead.
  #
  # ⚠ Deliberately narrower than "grow any class to `max_level`": nothing here
  # reads `class.max_level` at all. A class earns more progression rows only
  # by a human transcribing them off the shard's own page into a fact like
  # this one — never by the loader assuming a label keeps applying past
  # wherever a table last spoke for it. Whether the *finished* ruleset's
  # tables reach every class's own cap is a separate question, checked once,
  # on the loaded ruleset, by `Data.ProgressionTableTest` rather than guessed
  # at here.
  defp apply_change(%{"what" => "progression_table", "value" => rows}, class, _pools)
       when is_list(rows) and rows != [] do
    parsed = for row <- rows, do: progression_table_row!(class.id, row)
    verify_progression_table_levels!(class.id, parsed)

    for {level, row} <- parsed do
      verify_progression_table_bab!(class, level, row.bab)
      verify_progression_table_saves!(class, level, row)
    end

    table = Map.new(parsed)
    verify_progression_table_agrees!(class, table)

    {:ok, %{class | progression: Map.merge(class.progression, table)}}
  end

  defp apply_change(%{"what" => "class_skills", "value" => %{} = value}, class, _pools) do
    added = value |> Map.get("added", []) |> Enum.map(&slug/1)
    removed = value |> Map.get("removed", []) |> Enum.map(&slug/1)

    skills =
      class.class_skills
      |> MapSet.union(MapSet.new(added))
      |> MapSet.difference(MapSet.new(removed))

    {:ok, %{class | class_skills: skills}}
  end

  defp apply_change(%{"what" => "requirements", "value" => %{} = value}, class, _pools) do
    {:ok,
     %{
       class
       | requirements: requirements(value),
         requirements_unsupported: requirements_unsupported(value)
     }}
  end

  defp apply_change(%{"what" => "alignment_restriction", "value" => value}, class, _pools)
       when is_binary(value) do
    {:ok,
     %{
       class
       | alignment_restriction: alignment_phrase(value),
         alignment_restriction_raw: value
     }}
  end

  # ⚠ Одно число поверх ШКАЛЫ не применяется, а уезжает в гэп. У класса
  # с растущим дайсом (`red dragon disciple`) непонятно, что значит «хит-дайс
  # d10»: заменить всю шкалу одним числом или подвинуть одну её ступень —
  # и выбрать за источник загрузчик не имеет права (CLAUDE.md §3). Сегодня
  # такой записи нет ни в одном слое; появится — станет видимым
  # `{:not_modelled, {:class_change, id, "hit_die"}}`, а не тихой заменой.
  defp apply_change(%{"what" => "hit_die"}, %{hit_die_by_class_level: steps}, _pools)
       when is_list(steps),
       do: :skip

  defp apply_change(%{"what" => "hit_die", "value" => die}, class, _pools)
       when is_integer(die) do
    {:ok, %{class | hit_die: die}}
  end

  defp apply_change(%{"what" => "skill_points", "value" => points}, class, _pools)
       when is_integer(points) do
    {:ok, %{class | skill_points: points}}
  end

  defp apply_change(%{"what" => "auto_feat_at_level_1", "value" => feats}, class, _pools)
       when is_list(feats) do
    {:ok, Enum.reduce(feats, class, &grant_feat(&2, 1, slug(&1)))}
  end

  # The shard moves feats a class hands out to other class levels — Rogue's
  # Evasion from 2 to 30, Paladin's Divine Grace from 1 to 4, Shadowdancer's Hide
  # in Plain Sight from 1 to 4 (CLAUDE.md §3). Now that the vanilla levels are in
  # the data, *not* applying this would have the shard ruleset hand out feats at
  # levels the shard explicitly took them away from. `from: null` is the shard
  # adding a feat vanilla never gave at all.
  defp apply_change(%{"what" => "feat_level_shift", "value" => shifts}, class, _pools)
       when is_list(shifts) do
    applied =
      Enum.reduce(shifts, class, fn shift, acc ->
        case {shift["feat"], shift["from"], shift["to"]} do
          {feat, from, to} when is_binary(feat) and is_integer(to) ->
            move_grant(acc, from, to, slug(feat))

          _incomplete ->
            acc
        end
      end)

    {:ok, applied}
  end

  # Which of the shard's class groups this class belongs to, **by the group's own
  # page title**: `["Воины Сагры"]`, `["Воины Адры"]`, or both for the Fighter
  # («Воин не изменился в своей основе, но входит в группу классов воинов Сагры и
  # воинов Адры»). Seven classes state it, and this is the statement of the
  # membership relation that scales — a class page says which groups it is in,
  # so adding a class is one edit on one page.
  #
  # ⚠ Applied since 08.08.2026, and until then it was not: the fact sat in
  # `siala_unapplied` and every build made of these classes carried
  # `{:not_modelled, {:class_change, :fighter, "class_group"}}`. The note in the
  # data still reads «формализовать не берусь» — that was true of what the group
  # *gives*, and it is still reported (`Rules.ClassGroups.gaps/2`); membership
  # itself is a function of the class list and is now computed, so leaving the
  # caveat would say "not applied" about something applied — the exact stale
  # справка this project keeps burning on (HANDOFF).
  # `extra_attacks` has its mechanical home in `ruleset.attack_modifiers`, not in
  # the class map — the rule is about the character's attacks, not about a column
  # of the class table — so the class travels back unchanged and the modifier is
  # assembled by `attack_modifiers/3` off this same change.
  #
  # ⚠ Both ask `attack_modifier/1`, which is why "applied" and "carried" are one
  # decision. Until task 3.72 they were two: the modifier was built regardless
  # while the fact stayed unapplied, so the shard's rule was simultaneously
  # reported as an unmodelled gap and carried in a list nothing could use.
  defp apply_change(%{"what" => "extra_attacks"} = change, class, _pools) do
    case attack_modifier(change) do
      {:ok, _modifier} -> {:ok, class}
      :skip -> :skip
    end
  end

  defp apply_change(%{"what" => "class_group", "value" => names}, class, _pools)
       when is_list(names) do
    {:ok, %{class | class_groups: Enum.map(names, &to_string/1)}}
  end

  # Шард распространил УМЕНИЯ класса на оружие, которого их собственный источник
  # не называет (задача 3.101): «Все классовые умения Тайного лучника теперь
  # распространяются на малый и большие арбалеты».
  #
  # ⚠ Имя факта общее (`class_ability_weapons`), а не «про арбалеты», и это
  # не косметика: имя читает `apply_change`, а слово «арбалет» в коде загрузчика
  # стало бы игровым именем, которое соврёт в день, когда шард распространит
  # умения ещё на что-нибудь. Оружие живёт в `value`.
  #
  # ⚠ Само оружие здесь только СОБИРАЕТСЯ. Кому оно достаётся, решает
  # `Loader.Bonuses.widen_class_ability_weapons/2` — тот единственный читатель
  # `granted_feats`, который знает, у каких умений вообще есть записанное
  # условие по оружию. Пустой список роняет сборку: факт, который ничего
  # не расширяет, применённым считаться не может, иначе он молча перестал бы
  # быть и гэпом.
  defp apply_change(%{"what" => "class_ability_weapons", "value" => %{} = value}, class, _pools) do
    case value["weapons"] do
      [_ | _] = weapons ->
        {:ok, %{class | ability_weapons: MapSet.new(weapons, &atom/1)}}

      other ->
        raise "siala_41/classes.json: class_ability_weapons states weapons = " <>
                "#{inspect(other)}, and a non-empty list of weapon ids is required — " <>
                "a fact that widens nothing is not applied, it is unread"
    end
  end

  # Шард переписал СОСТАВ пула бонусных фитов класса, а не уровни, на которых
  # пул выдаётся (задача 3.73):
  #
  #   «На уровнях с бонусными умениями Священник может выбирать умения
  #    с Эпическими заклинаниями (23, 26, 29, 32, 35 и 38 уровни в классе).»
  #
  # Перечисление в скобках — это ванильные `epic_bonus_feat_levels` Священника,
  # слово в слово, и то же самое у Друида. Поэтому запись применяется только
  # тогда, когда названные уровни РАВНЫ бонусным уровням класса: тогда
  # предложение говорит «на всех своих бонусных уровнях», и расширять нужно
  # пул, а не заводить уровень. Список, который бонусным уровням класса
  # не равен, значил бы пул, зависящий от уровня, — такой формы у нас нет,
  # и выдумывать её по записи, которую никто не измерял, нельзя: факт уезжает
  # в `siala_unapplied` и доходит до игрока гэпом.
  #
  # ## Уровни называются двумя способами, и второй завела задача 3.85
  #
  # ⚠ Здесь стояло: «Ключи значения проверяются на равенство, а не на вхождение:
  # у записи Рейнджера есть третий ключ `also_on` („а также на эпических
  # фитах“), то есть она говорит БОЛЬШЕ, чем мы бы применили. Половина правила
  # хуже отсутствующего — применив её, мы бы объявили посчитанным то, чего
  # не считаем, и сняли бы гэп, на котором стоит замер (GAME_CHECKS.md U2)».
  #
  # Довод был верен ровно до своего замера, и замер пришёл: Dan 24.08.2026
  # (кейсы U1 и U2) видел все пять владений в бонусном слоте Рейнджера
  # на уровнях 1 и 5 и в обоих слотах Чемпиона Торма — обычном (ЧТ 2)
  # и эпическом (ЧТ 14). То есть «половины» больше нет: посылка снята,
  # и держать на ней гэп значит утверждать необходимость, которой нет.
  #
  # 🔴 И гэп этот был ЛОЖНЫМ ещё до замера. Правило приезжает со страниц самих
  # фитов (раздел «Возможность взятия фита» → `bonus_for`), поэтому пул у обоих
  # классов был верен всё это время, а запись на стороне класса продолжала
  # печатать `{:not_modelled, {:class_change, …, "bonus_feat_pool"}}`. Мы
  # применяли правило и одновременно говорили игроку, что не применяем, —
  # ложная неопределённость, которую §6 запрещает так же, как ложную
  # уверенность. Две записи об одном правиле теперь сходятся на одной карте:
  # применение здесь ничего к `bonus_for` не добавляет (проверено вызовом,
  # список кандидатов не сдвинулся ни на один id) и служит сверкой.
  #
  # Поэтому уровни складываются из двух слагаемых, и оба необязательны:
  #
  #   * `class_levels` — числа, названные источником. `null` значит «страница
  #     не называет ни одного», а не «ноль уровней» (Чемпион Торма);
  #   * `also_on` — имя собственного набора уровней класса из закрытого словаря
  #     (`epic_bonus_feat_levels` у Рейнджера — дословный хвост его цитаты;
  #     `all_bonus_feat_levels` у Чемпиона Торма — прочтение фразы
  #     «На дополнительных фитах», подтверждённое замером обеих пачек).
  #
  # ⚠ Имя вне словаря НЕ роняет сборку, а оставляет факт гэпом: это значение
  # факта, а не расхождение данных с кодом (роняет только форма селектора
  # в `_bonus_feat_pools`). И пустое утверждение — ни чисел, ни имени — тоже
  # гэп: у класса без бонусных уровней оно иначе сравнялось бы с пустым
  # множеством и «применилось» бы, ничего не сказав.
  defp apply_change(%{"what" => "bonus_feat_pool", "value" => %{} = value}, class, pools) do
    with true <- known_pool_keys?(value),
         {:ok, levels} <- stated_pool_levels(value, class),
         {:ok, selector} <- Map.fetch(pools, value["adds"]),
         true <- levels == bonus_feat_levels(class) do
      {:ok,
       %{
         class
         | bonus_feat_pool_adds: Map.put(class.bonus_feat_pool_adds, value["adds"], selector)
       }}
    else
      _not_ours -> :skip
    end
  end

  defp apply_change(_change, _class, _pools), do: :skip

  # -------------------------------------------- shard progression tables --

  # One row of a `progression_table` fact — strict where vanilla's own
  # `progression/1` above is lenient, and deliberately so: a vanilla row comes
  # off a parser that has already decided what counts as a progression row
  # (`is_integer(row["bab"])` there quietly skips a row the wiki table did not
  # give a BAB cell), while this fact is a human transcription with nothing
  # upstream to have already filtered it — a malformed row here is a typo
  # worth failing the build over, not a row worth skipping.
  defp progression_table_row!(_id, %{
         "level" => level,
         "bab" => bab,
         "fort" => fort,
         "ref" => ref,
         "will" => will
       })
       when is_integer(level) and level >= 1 and is_integer(bab) and bab >= 0 and
              is_integer(fort) and fort >= 0 and is_integer(ref) and ref >= 0 and
              is_integer(will) and will >= 0 do
    {level, %{bab: bab, fort: fort, ref: ref, will: will}}
  end

  defp progression_table_row!(id, row) do
    raise "#{id}: progression_table row #{inspect(row)} is not {level:, bab:, fort:, ref:, " <>
            "will:} of a positive level and three non-negative integers"
  end

  # A table read one cumulative level at a time has to cover every level it
  # claims to, in order, with neither a gap nor a repeat — a level missing in
  # the middle would silently fall back to nothing the moment a build reached
  # it, exactly the failure this whole fact exists to close.
  defp verify_progression_table_levels!(id, parsed) do
    levels = parsed |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    unless levels == Enum.to_list(1..length(levels)//1) do
      raise "#{id}: progression_table levels are #{inspect(levels)}, expected a contiguous " <>
              "1..N run with neither a gap nor a repeat — a table read by cumulative level " <>
              "must cover every level it claims to"
    end
  end

  defp verify_progression_table_bab!(class, level, actual) do
    case bab_from_label(class.bab_progression, level) do
      ^actual ->
        :ok

      expected ->
        raise """
        #{class.id} level #{level}: progression_table states base attack #{actual}, but the \
        "#{class.bab_progression}" label already on the class works out to #{expected}
        """
    end
  end

  defp verify_progression_table_saves!(class, level, row) do
    for save <- [:fort, :ref, :will] do
      actual = Map.fetch!(row, save)
      label = Map.get(class.save_progressions, save)
      expected = save_from_label(label, level)

      if actual != expected do
        raise """
        #{class.id} level #{level}: progression_table states #{save} #{actual}, but the \
        "#{label}" label already on the class works out to #{expected}
        """
      end
    end
  end

  # Where the shard's table and the one it grew out of both name a level, the
  # two numbers must be the SAME number. Checked before the merge rather than
  # left for the merge to overwrite silently — see the moduledoc note on the
  # `apply_change` clause above for why this is not optional.
  defp verify_progression_table_agrees!(class, table) do
    for {level, row} <- class.progression, existing = Map.get(table, level), existing != nil do
      if existing != row do
        raise """
        #{class.id}: progression_table's level #{level} reads #{inspect(existing)}, but this \
        class's own table already has #{inspect(row)} there — the shard fact disagrees with \
        the table it claims to restate, and neither side has the authority to overwrite the \
        other silently
        """
      end
    end
  end

  # ⚠ Сторож поля `not_a_gap` — задача 3.74 (21.08.2026). Поле снимает факт
  # со счёта пробелов, то есть это единственный способ уменьшить число, которое
  # калькулятор показывает игроку, НЕ посчитав ничего нового. Поэтому оно
  # обязано нести автора, дату и довод — иначе им можно было бы гасить
  # неудобные факты одной строкой, и баннер перестал бы что-либо значить.
  #
  # Та же граница, что у `"modelled": false` в условиях `attack_modifiers`
  # (задача 3.72), и заведена она по той же причине: решение владельца — это
  # запись с провенансом, а не отсутствие записи.
  #
  # ⚠ Сама проверка с задачи 3.95 живёт в `Loader.NotAGap` — одна на четыре
  # семейства данных, которые это поле несут. Здесь остаётся только имя записи
  # для сообщения: факт класса зовётся парой «класс · что», и ни одно другое
  # семейство так не зовётся.
  #
  # ⚠ Словаря доводов (`bases:`) здесь НЕ объявлено, и это не пропуск: довод
  # `feat_description` проверяется описанием ФИТА, а у факта класса своего фита
  # нет. Поле `basis` у такого факта роняет сборку — поле, которого никто
  # не читает, выглядело бы решением, не будучи им.
  defp verify_not_a_gap!(class_id, %{"not_a_gap" => decision} = change)
       when is_map(decision) do
    NotAGap.verify!("siala_41/classes.json: #{class_id} · #{change["what"]}", decision)
  end

  defp verify_not_a_gap!(_class_id, _change), do: :ok

  @pool_keys ~w(adds class_levels also_on)

  defp known_pool_keys?(value), do: Map.keys(value) -- @pool_keys == []

  # Уровни, на которых запись объявляет расширенный пул: названные числами
  # плюс названные именем набора. Пустое объединение — не ответ (см. выше).
  defp stated_pool_levels(value, class) do
    with {:ok, named} <- named_levels(value["class_levels"]),
         {:ok, also} <- also_on_levels(value["also_on"], class),
         levels = MapSet.union(named, also),
         false <- Enum.empty?(levels) do
      {:ok, levels}
    else
      _unreadable -> :skip
    end
  end

  defp named_levels(nil), do: {:ok, MapSet.new()}

  defp named_levels(levels) when is_list(levels) do
    if Enum.all?(levels, &is_integer/1), do: {:ok, MapSet.new(levels)}, else: :error
  end

  defp named_levels(_other), do: :error

  # Закрытый словарь имён: набор уровней класса, названный вместо чисел.
  # `bonus_feat_levels` в одиночку сюда не заведён — его сегодня не называет
  # ни одна запись, а термин, которым никто не пользуется, проверить нечем.
  defp also_on_levels(nil, _class), do: {:ok, MapSet.new()}
  defp also_on_levels("epic_bonus_feat_levels", class), do: {:ok, class.epic_bonus_feat_levels}
  defp also_on_levels("all_bonus_feat_levels", class), do: {:ok, bonus_feat_levels(class)}
  defp also_on_levels(_unknown, _class), do: :error

  # Оба множества, потому что предложение источника говорит «на уровнях
  # с бонусными умениями» и не различает эпические от доэпических — у Священника
  # и Друида доэпических нет вовсе, а у класса, у которого они есть, разделять
  # их было бы нашим домыслом.
  defp bonus_feat_levels(class),
    do: MapSet.union(class.bonus_feat_levels, class.epic_bonus_feat_levels)

  defp grant(granted, level, ids),
    do: Map.update(granted, level, ids, &Enum.uniq(&1 ++ ids))

  # One feat handed over at one class level, rank and all. The rank travels with
  # the grant because it belongs to it: `deathless_vigor (+5HP)` at level 15 is
  # a different thing from `deathless_vigor (+3HP)` at level 5, and a shift that
  # left the rank behind would relabel the wrong one.
  def grant_feat(class, level, id, rank \\ nil) do
    %{
      class
      | granted_feats: grant(class.granted_feats, level, [id]),
        granted_feat_ranks: put_rank(class.granted_feat_ranks, level, id, rank)
    }
  end

  def move_grant(class, from, to, id) do
    {ranks, rank} = pop_rank(class.granted_feat_ranks, from, id)

    %{
      class
      | granted_feats: class.granted_feats |> revoke(from, id) |> grant(to, [id]),
        granted_feat_ranks: put_rank(ranks, to, id, rank)
    }
  end

  defp put_rank(ranks, _level, _id, nil), do: ranks

  defp put_rank(ranks, level, id, rank),
    do: Map.update(ranks, level, %{id => rank}, &Map.put_new(&1, id, rank))

  defp pop_rank(ranks, level, id) when is_integer(level) do
    case Map.get(ranks, level) do
      nil ->
        {ranks, nil}

      at_level ->
        {rank, rest} = Map.pop(at_level, id)
        {if(rest == %{}, do: Map.delete(ranks, level), else: Map.put(ranks, level, rest)), rank}
    end
  end

  defp pop_rank(ranks, _no_vanilla_level, _id), do: {ranks, nil}

  # A level whose last feat was moved away grants nothing, so it leaves the map
  # rather than staying as `9 => []`. An empty list would read as "this level is
  # known to grant nothing", which is the same shape as a level that was never in
  # the table at all, and it is not what the map is for: `granted_feats` answers
  # "which levels hand something over".
  defp revoke(granted, level, id) when is_integer(level) do
    case Map.get(granted, level) do
      nil -> granted
      ids -> put_granted(granted, level, List.delete(ids, id))
    end
  end

  defp revoke(granted, _no_vanilla_level, _id), do: granted

  defp put_granted(granted, level, []), do: Map.delete(granted, level)
  defp put_granted(granted, level, ids), do: Map.put(granted, level, ids)

  # ------------------------------------------- attacks a shard class adds --

  # Shard rules that add attacks on top of the vanilla table (`ruleset
  # .attack_modifiers`, read by `Rules.AttackModifiers`). Today exactly one:
  # Arcane Archer, +1 attack per 10 class levels, up to 3.
  #
  # ⚠ The **only** decision here is `attack_modifier/1`, and `apply_change/2`
  # asks the very same function — so "this fact reached a mechanical home" and
  # "this modifier exists" cannot drift apart into a fact that is applied and
  # missing, or carried and reported as a gap. That drift is precisely what the
  # comment above `apply_class_changes/2` was written about.
  #
  # ⚠ The class ids a condition names are checked **here** rather than in
  # `attack_modifier/1`, because only this function has the class map. An id
  # nobody carries would make the condition silently never fire, and every
  # condition in this list disables the rule — so a misspelt one grants attacks
  # the character will not have.
  defp attack_modifiers(class_id, changes, classes) do
    for change <- changes, {:ok, modifier} <- [attack_modifier(change)] do
      Enum.each(modifier.disabled_if, &check_condition_class!(&1, classes, class_id))

      Map.put(modifier, :source, {:class, class_id})
    end
  end

  # ⚠ `unclear` is refused first here as well, and for the reason
  # `apply_change/2` states: a value a human read the page and could **not** pin
  # down must not become a number on somebody's screen.
  defp attack_modifier(%{"what" => "extra_attacks", "status" => "unclear"}), do: :skip

  defp attack_modifier(%{"what" => "extra_attacks", "value" => %{} = value} = change) do
    {:ok,
     %{
       kind: :extra_attacks,
       per_class_levels: attack_step!(value, "per_class_levels"),
       attacks_per_step: attack_step!(value, "attacks_per_step"),
       max: attack_max!(value),
       disabled_if: Enum.map(value["disabled_if"] || [], &attack_condition!/1),
       status: change["status"]
     }}
  end

  defp attack_modifier(_change), do: :skip

  # Both numbers are **required**, and neither gets a default. `nil` would crash
  # `div/2` on somebody's build rather than here, and — worse — a default would
  # be a game number this layer invented: «one attack per class level» is not
  # what any source says, it is just what `|| 1` happens to mean.
  defp attack_step!(value, key) do
    case Map.get(value, key) do
      step when is_integer(step) and step > 0 ->
        step

      other ->
        raise "siala_41/classes.json: extra_attacks states #{key} = #{inspect(other)}, " <>
                "and a positive integer is required — a default here would be a game number " <>
                "nobody read off a page"
    end
  end

  defp attack_max!(%{"max" => nil}), do: nil
  defp attack_max!(value) when not is_map_key(value, "max"), do: nil
  defp attack_max!(%{"max" => max}) when is_integer(max) and max > 0, do: max

  defp attack_max!(%{"max" => other}) do
    raise "siala_41/classes.json: extra_attacks states max = #{inspect(other)} — a positive " <>
            "integer, or no key at all when the source names no ceiling"
  end

  # A condition the data declares unmodelled. `modelled: false` is the one way
  # past the check below, so it is not a bare flag: it has to say who decided and
  # why, because the consequence is a number quietly too high (`mounted` — the
  # calculator answers for a character on foot, Dan 21.08.2026).
  defp attack_condition!(%{"modelled" => false} = condition) do
    decision = condition["decision"]

    unless is_map(decision) and present?(decision["who"]) and present?(decision["why"]) do
      raise "siala_41/classes.json: extra_attacks declares the condition " <>
              "#{inspect(condition["when"])} unmodelled without a `decision` naming `who` " <>
              "and `why` — skipping a disabling condition shows attacks the character " <>
              "does not have, and that is not a thing to do silently"
    end

    %{kind: atom(condition["when"] || "unnamed"), modelled?: false}
  end

  # ⚠ Asked of the rules core, never listed here a second time — the same move as
  # `weapon_must_be` (`Rules.Attack.weapon_property_field/1`). A `when` the core
  # cannot read fails the build: a disabling condition that never fires is the
  # dangerous half of "the rule silently does nothing".
  defp attack_condition!(%{"when" => name} = condition) when is_binary(name) do
    kind = atom(name)

    case AttackModifiers.condition_fields(kind) do
      nil ->
        raise "siala_41/classes.json: extra_attacks names the condition #{name}, and " <>
                "BuildCalculator.Rules.AttackModifiers cannot evaluate it. Either the core " <>
                "learns it, or the record says `\"modelled\": false` with a decision"

      fields ->
        fields
        |> Map.new(&{&1, attack_condition_field!(condition, kind, &1)})
        |> Map.merge(%{kind: kind, modelled?: true})
    end
  end

  defp attack_condition!(other) do
    raise "siala_41/classes.json: extra_attacks states #{inspect(other)} as a condition, and " <>
            "a record with a `when` is required since task 3.72 — the prose the field used to " <>
            "carry was never read by anything"
  end

  defp attack_condition_field!(condition, kind, :levels) do
    case condition["levels"] do
      levels when is_integer(levels) and levels > 0 ->
        levels

      other ->
        raise "siala_41/classes.json: condition #{kind} states levels = #{inspect(other)}"
    end
  end

  defp attack_condition_field!(condition, kind, :read_modifiers) do
    source = atom(condition["read_modifiers"] || "")

    if source in AttackModifiers.ability_modifier_sources() do
      source
    else
      raise "siala_41/classes.json: condition #{kind} states read_modifiers = " <>
              "#{inspect(condition["read_modifiers"])}, and one of " <>
              "#{inspect(AttackModifiers.ability_modifier_sources())} is required — whether " <>
              "gear counts is a game question and this layer may not pick the default"
    end
  end

  defp attack_condition_field!(condition, kind, field) when field in [:ability, :exceeds] do
    name = atom(condition[Atom.to_string(field)] || "")

    if AttackModifiers.ability?(name) do
      name
    else
      raise "siala_41/classes.json: condition #{kind} names the ability " <>
              "#{inspect(condition[Atom.to_string(field)])} — a typo compares against a " <>
              "modifier of zero, so the rule would switch off almost always"
    end
  end

  defp attack_condition_field!(condition, _kind, :class), do: atom(condition["class"] || "")

  defp check_condition_class!(%{class: class}, classes, owner) when is_atom(class) do
    unless Map.has_key?(classes, class) do
      raise "siala_41/classes.json: #{owner}'s extra_attacks is disabled by levels of " <>
              "#{class}, and no such class is loaded — the condition would never fire"
    end
  end

  defp check_condition_class!(_condition, _classes, _owner), do: :ok

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
