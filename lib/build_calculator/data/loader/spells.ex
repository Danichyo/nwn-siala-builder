defmodule BuildCalculator.Data.Loader.Spells do
  @moduledoc """
  Заклинания: ванильные записи, ручной сиальский слой (в него доезжает только круг
  по классам), подмены классовой выдачи и правила заклинательства — минимум
  характеристики, продвижение чужого каста престиж-классом, специализация школы.
  """

  import BuildCalculator.Data.Loader.Reading

  # ----------------------------------------------------------------- spells --

  # Slots per day and spells known come off the class progression tables (see
  # `spell_table/2`); what a spell *is* comes from here.
  #
  # A spell's circle is stored per list (`mage_level`, `bard_level`, …) and
  # **as a string**: Fandom editors wrote patch history straight into the field,
  # so the column holds `"epic"`, `"4 (''special'')"` and `"<s>2</s> 3"` beside
  # honest numbers (CLAUDE.md §3). Only an unambiguous integer is lifted; every
  # other spelling stays in `levels_raw` and the spell is left out of the picker
  # with a gap, because turning `"<s>2</s> 3"` into a number is inventing one.
  def build_spells(:missing, _lists), do: %{}

  def build_spells(list, lists) do
    fields = lists |> Map.values() |> Enum.uniq()

    Map.new(list, fn s ->
      id = atom(s["id"])
      {levels, raw} = spell_levels(s, fields)

      {id,
       %{
         id: id,
         name: s["name"],
         school: school_id(s["school"]),
         school_raw: strip_links(s["school"]),
         innate_level_raw: s["innate_level"],
         levels: levels,
         levels_raw: raw,
         # Raw Fandom filename off the `{{spell}}` template's `icon=` parameter
         # ("is_acidfog.gif"), `nil` for the 9 vanilla spells whose page carries
         # none. Presentational only — resolved against
         # `priv/rules/vanilla/icons.json` by `BuildCalculatorWeb.Builder.Icons`,
         # never read inside `rules/` (AGENT_QUEUE.md 3.50).
         icon: s["icon"]
       }}
    end)
  end

  # ⚠ **The school field is raw wikitext, and it has to be read, not printed.**
  # Three of the 304 vanilla entries carry struck-through patch history
  # (`"<del>abjuration</del> <i>necromancy</i>"`) and one is capitalised
  # (`"Evocation"`), so `school` is lifted into an atom here exactly the way
  # `spell_levels/2` lifts a circle: the reading when it is unambiguous, the
  # source string beside it in `school_raw` when it is not.
  #
  # The reading itself is `Wiki.SialaSpellPage.school/1` — the same closed
  # dictionary of eight English and nine Russian names that `mix wiki.parse`
  # compares the two wikis with, and it already cuts struck history through
  # `strip_struck/1`. Writing a second normalisation here is exactly what
  # CLAUDE.md forbids: two readings of one field drift, and the day they drift
  # the comparison report and the ruleset would disagree about what a spell's
  # school is.
  #
  # ⚠ `nil` rather than a raise for an unreadable value, the same direction
  # `levels_raw` takes: `vanilla/spells.json` is regenerated from the wiki cache,
  # so a new spelling upstream must not stop the whole application from
  # compiling. What guards against a silent undercount is a test —
  # `SpellSchoolTest` asserts that every spell of a wizard's list has a readable
  # school and that the per-school counts add up to the size of the list. The
  # hand-written shard layer below is the opposite case and does raise: a typo
  # there is a typo in the rules.
  #
  # ⚠ `String.to_atom/1` and not `to_existing_atom/1`: the reader answers out of
  # a closed eight-word dictionary compiled into `SialaSpellPage`, so there is no
  # unbounded input here — and `to_existing_atom/1` would depend on whether some
  # *other* module mentioning `:evocation` happened to be compiled first, which
  # is not something a data loader may rely on.
  defp school_id(value) do
    case BuildCalculator.Wiki.SialaSpellPage.school(value) do
      {:ok, school} -> String.to_atom(school)
      {:error, _unreadable} -> nil
    end
  end

  # ------------------------------------------------------- the shard's spells --

  # `priv/rules/siala_41/spells.json` — hand written, and the only part of the
  # shard's spell corpus that reaches a number we print.
  #
  # ⚠ Why by hand when a machine layer already exists. `generated/spells.json`
  # holds all 129 Siala pages and finds 115 of the 128 matched ones different
  # from vanilla — but the differences are damage, saving throw, duration,
  # school: effects the calculator does not compute at all. The one field that
  # does reach the player is the **circle**, and only through the known-spell
  # catalogue, which only a Bard and a Sorcerer have (`Rules.Spells.list_for/2`).
  # Applying the machine layer wholesale would import 115 differences to change
  # nothing and would put the parser's reading of prose into the ruleset; lifting
  # the circle by hand keeps the file to the records somebody actually verified.
  #
  # Two shapes, told apart by whether the id is already there:
  #
  #   * an id that exists — its `levels` map is **replaced**, not merged. That is
  #     the shape the measurement had: `Wall of fire` lost its arcane half and
  #     kept the druid one, and a merge could not have expressed a removal.
  #   * an id that does not — a spell the shard added (`Stream of Flame`), which
  #     must then state its own `name` and circles.
  #
  # An unknown `what`, an unknown class column, or a shard-only record without a
  # name raises: this file is small and hand written, so a typo here is a typo in
  # the rules, not an edge case to route around.
  def apply_spell_layer(spells, :missing, _lists), do: spells

  def apply_spell_layer(spells, %{"spells" => entries}, lists) do
    columns = lists |> Map.values() |> Enum.map(&to_string/1) |> MapSet.new()

    Enum.reduce(entries, spells, fn entry, acc ->
      id = atom(entry["id"])

      Enum.reduce(entry["changes"] || [], acc, fn change, inner ->
        apply_spell_change(inner, id, entry, change, columns)
      end)
    end)
  end

  def apply_spell_layer(spells, _other, _lists), do: spells

  defp apply_spell_change(spells, id, entry, %{"what" => "levels", "value" => value}, columns)
       when is_map(value) do
    for {column, _circle} <- value, column not in columns do
      raise """
      siala_41/spells.json: #{entry["id"]} names spell list #{inspect(column)}, \
      which is not one of #{inspect(MapSet.to_list(columns))}.\
      """
    end

    levels = Map.new(value, fn {column, circle} -> {String.to_existing_atom(column), circle} end)

    case Map.fetch(spells, id) do
      {:ok, spell} ->
        Map.put(spells, id, %{spell | levels: levels})

      :error ->
        Map.put(spells, id, shard_spell(id, entry, levels))
    end
  end

  # 🔴 The second field of the shard layer, added 24.08.2026 (task 3.86) — and it
  # is here for the same reason the circle is: it reaches a number we print.
  # Siala moves the school of eight spells, five of them into `enchantment` out
  # of `evocation`, and naming a wizard's specialization now costs a **count**
  # of spells («closes Illusion — 20 of 179»). Counted off the vanilla school
  # that number would be 16, i.e. wrong by a quarter on the shard's own ruleset.
  #
  # ⚠ The value goes through the very same reader the vanilla field does
  # (`school_id/1`), so `"enchantment"` and «Зачарование (Enchantment)» are one
  # answer — but unlike the vanilla side an unreadable value **raises**: this
  # file is hand written and small, and a school nobody can read here is a typo
  # in the rules rather than an upstream page we have to survive.
  defp apply_spell_change(spells, id, entry, %{"what" => "school", "value" => value}, _columns)
       when is_binary(value) do
    school =
      school_id(value) ||
        raise """
        siala_41/spells.json: #{entry["id"]} names school #{inspect(value)}, \
        which is not one of the eight schools of magic.\
        """

    case Map.fetch(spells, id) do
      {:ok, spell} ->
        Map.put(spells, id, %{spell | school: school, school_raw: value})

      :error ->
        raise """
        siala_41/spells.json: #{entry["id"]} overrides the school of a spell that \
        does not exist. A shard-only spell states its school in the record itself \
        (`"school"`), not as a change.\
        """
    end
  end

  defp apply_spell_change(_spells, _id, entry, change, _columns) do
    raise """
    siala_41/spells.json: #{entry["id"]} carries change #{inspect(change["what"])}, \
    which the loader does not know how to apply.\
    """
  end

  # A spell the shard added. `levels_raw` is empty on purpose rather than absent:
  # the shape has to match a vanilla entry exactly, or every reader would need to
  # know which spells came from where.
  defp shard_spell(id, entry, levels) do
    name = entry["name"] || raise "siala_41/spells.json: #{entry["id"]} has no name"

    %{
      id: id,
      name: name,
      # Read through the same dictionary as every other school (`school_id/1`):
      # `Stream of Flame`'s page writes «Evocation» capitalised, and a capital
      # letter is not a ninth school.
      school: school_id(entry["school"]),
      school_raw: entry["school"],
      innate_level_raw: entry["innate_level"],
      levels: levels,
      levels_raw: %{},
      # Same reasoning as a shard-only feat's `icon: nil` above: `Stream of
      # Flame` has no Fandom page, so there is no art to point at.
      icon: nil
    }
  end

  # ----------------------------------------------- substitutes for a grant --

  # `vanilla/grant_substitutions.json` — a class level whose "granted" feat is
  # really a bonus-feat *choice*.
  #
  # ⚠ Two readers and one source. `FeatSlots.at/3` opens the slot and
  # `Build.granted_feats/3` withholds the grant; if either read its own list the
  # feat would end up both handed over and choosable, which is the one state the
  # rules can never be in. Hence a map keyed `{class, class_level}`, built once.
  #
  # ⚠ This was `epic_grant_substitutions` with a `when: epic_character` gate for
  # about an hour on 14.08.2026: the first measurement was taken at character
  # level 21 and the Fandom sentence reads «If an **epic character** takes weapon
  # master level 1…». Dan asked for the other half («а нам не стоит weapon of
  # choice проверить до 20 уровня?») and it came back the same — a slot with six
  # feats on a level-7 character. The condition went, the name with it.
  #
  # Every id is checked against the class's own `granted_feats` for that level:
  # withdrawing a grant that was never there would be a silent no-op wearing the
  # look of a rule.
  def grant_substitutions(:missing, _classes), do: %{}

  def grant_substitutions(%{"substitutions" => entries}, classes) when is_list(entries) do
    Map.new(entries, fn entry ->
      class = atom(entry["class"])
      class_level = entry["class_level"]
      feats = Enum.map(entry["feats"] || [], &atom/1)

      definition =
        Map.get(classes, class) ||
          raise "grant_substitutions.json: no such class #{inspect(entry["class"])}"

      granted = Map.get(definition.granted_feats, class_level, [])

      for feat <- feats, feat not in granted do
        raise """
        epic_grant_substitutions.json: #{entry["class"]} level #{class_level} does not grant \
        #{inspect(feat)}, so there is nothing to substitute — the class grants \
        #{inspect(granted)}.\
        """
      end

      case entry["when"] do
        "always" -> :ok
        other -> raise "grant_substitutions.json: unknown condition #{inspect(other)}"
      end

      {{class, class_level}, feats}
    end)
  end

  def grant_substitutions(_other, _classes), do: %{}

  def spell_levels(spell, fields) do
    Enum.reduce(fields, {%{}, %{}}, fn field, {clean, raw} ->
      case spell["#{field}_level"] do
        nil -> {clean, raw}
        value -> place_spell_level(field, to_string(value), clean, raw)
      end
    end)
  end

  defp place_spell_level(field, value, clean, raw) do
    case Integer.parse(value) do
      {circle, ""} -> {Map.put(clean, field, circle), raw}
      _ -> {clean, Map.put(raw, field, value)}
    end
  end

  # Which column of a spell entry names the circle for a class. Plumbing of the
  # Fandom `{{spell}}` template rather than a game number — the fields are
  # literally called `mage_level`, `bard_level`, `cleric_level`.
  def spell_lists(ov) do
    case dig(ov, ["_vanilla_constants_confirmed", "spell_lists", "value"]) do
      map when is_map(map) ->
        Map.new(map, fn {class, field} -> {atom(class), list_key(field)} end)

      _ ->
        %{}
    end
  end

  defp list_key(field), do: field |> String.replace_suffix("_level", "") |> atom()

  # Per class level, the circle -> count row off the wiki progression table.
  # Levels with no table (`{}` for a Ranger before level 4) are left out, so a
  # missing key means "this class level grants nothing", not "unknown".
  def spell_table(class, key) do
    for %{"level" => level} = row <- class["progression"] || [],
        table = row[key],
        is_map(table) and map_size(table) > 0,
        into: %{} do
      {level, Map.new(table, fn {circle, count} -> {String.to_integer(circle), count} end)}
    end
  end

  # Where both spell tables stop. Vanilla ends every caster at class level 20 and
  # no epic progression exists, which is the single most expensive thing a player
  # can fail to know (CLAUDE.md §6) — so it is a number the core can state.
  def spell_table_max(class) do
    levels =
      for %{"level" => level} = row <- class["progression"] || [],
          is_map(row["spells_per_day"]) or is_map(row["spells_known"]),
          do: level

    case levels do
      [] -> nil
      levels -> Enum.max(levels)
    end
  end

  # ------------------------------------------------------- spellcasting rules --

  # Facts about casting that have no machine-readable home. Both of these live as
  # English prose on Fandom — inside the parentheses of a class's `Spellcasting:`
  # line and under a `Bonus spells` heading — so they are transcribed by hand into
  # `vanilla/spellcasting.json` rather than parsed. See that file's `_note`.

  # "a base charisma score of 10 + the spell's level is required to cast a spell",
  # as `%{base: 10, per_circle: 1}`. `nil` when the file is missing or the record
  # is not `verified`, and `nil` means the ability half of `casts_spell_level`
  # simply is not checked — never that it passed.
  def casting_ability_minimum(:missing), do: nil

  def casting_ability_minimum(file) when is_map(file) do
    entry = Map.get(file, "casting_ability_minimum")

    if is_map(entry) and entry["status"] == "verified" and entry["verdict"] == "applied" and
         is_integer(entry["base"]) and is_integer(entry["per_circle"]) do
      # ⚠ `applies_to` — не украшение записи: обе её читательницы сравнивают
      # требование с МЕНЬШИМ из базового и одетого значения («both a base … and
      # a modified … score»), и обе (`Rules.Prereqs`'s `casts_with_ability/3`,
      # `Rules.Spells`'s casting floor) реализуют ровно эту одну ветку. Файл,
      # объявивший другую, останавливает сборку, а не применяется наполовину:
      # правило, разобранное в данных и не доехавшее до кода, — самая частая
      # форма дефекта в этом проекте (CLAUDE.md §9).
      record_flag!("casting_ability_minimum", entry, "applies_to", "base_and_modified")

      %{base: entry["base"], per_circle: entry["per_circle"]}
    end
  end

  # Which casting classes are **spontaneous** — a `MapSet` of class ids, or `nil`
  # when the file carries no such record (and then `{:missing_data,
  # :spontaneous_casters}` is announced and nobody gets the exception).
  #
  # 🔴 The record exists because one sentence of `fandom:Spell focus` grants
  # spontaneous casters, and only them, a weaker reading of «ability to cast Nth
  # level spells»: «Spontaneous casters ([[bard]]s and [[sorcerer]]s) can take
  # this feat without being able to cast first level spells as long as their
  # class level qualifies for at least 0 level one spell slots». Task 3.122 read
  # that sentence without its first two words and applied it to all seven
  # casters; task 3.124 put the two words back — Dan's own measurement of a
  # Wizard 8 with intelligence 11 is what caught it.
  #
  # ⚠ The list is hand written and cannot be derived by reading the class pages
  # for the word: the Cleric's own `Spellcasting:` label contains «which can be
  # [[spontaneous cast]]» while saying «requires preparation» in the same
  # sentence. See the record's `note` for the four observations behind it.
  #
  # ⚠ Both readings the core implements are named in the file and checked here,
  # the same contract `bonus_spell_slots` has: a record stating a third one stops
  # the build rather than being applied halfway.
  def spontaneous_casters(:missing, _classes), do: nil

  def spontaneous_casters(file, classes) when is_map(file) do
    entry = Map.get(file, "spontaneous_casters")

    if is_map(entry) and entry["status"] == "verified" and entry["verdict"] == "applied" do
      record_flag!(
        "spontaneous_casters",
        entry,
        "feat_prerequisite",
        "class_row_names_the_circle"
      )

      record_flag!("spontaneous_casters", entry, "others_require", "castable_circle")

      case List.wrap(entry["classes"]) do
        [] ->
          raise "spellcasting.json: spontaneous_casters names no classes"

        names ->
          MapSet.new(names, &advancement_class!(&1, classes))
      end
    end
  end

  # Bonus spell slots for a high casting ability (task 3.70). The table off
  # `fandom:Ability modifier#Spellcasting` (revid 71035 — `Bonus spells` is a
  # redirect onto it, and the page is not in `priv/wiki_cache/`, same as
  # `Point buy`), keyed by ability **modifier**:
  #
  #     %{by_modifier: %{5 => %{1 => 2, 2 => 1, …}}, formula: …, min_circle: 1}
  #
  # `nil` when the file is missing or the record is not `verified`, and `nil`
  # means no bonus is added at all *and* `{:missing_data, :bonus_spell_slots}`
  # is announced — a caster silently short by seventeen slots a day is exactly
  # the quiet plausible answer this project refuses (CLAUDE.md §3).
  #
  # ⚠ Every one of the four conditions the rule carries is checked here rather
  # than defaulted, and three of them raise instead of degrading: the core
  # implements one reading of each, so a file that states another would make the
  # data and the code disagree in silence. `min_circle` has no default for the
  # same reason its twin in `school_specialization` has none.
  def bonus_spell_slots(:missing), do: nil

  def bonus_spell_slots(file) when is_map(file) do
    entry = Map.get(file, "bonus_spell_slots")

    if is_map(entry) and entry["status"] == "verified" and entry["verdict"] == "applied" do
      rule = bonus_spell_slot_rule!(entry)
      verify_bonus_slots_against_formula!(rule)
      rule
    end
  end

  defp bonus_spell_slot_rule!(entry) do
    %{
      min_circle:
        entry["min_circle"] ||
          raise("spellcasting.json: bonus_spell_slots names no min_circle"),
      by_modifier: bonus_slot_table!(entry),
      formula: bonus_slot_formula!(entry["formula"]),
      # The modifier the bonus reads off. «bonus spells are based on modified
      # intelligence» — the same sentence that puts the *casting* minimum on the
      # base score, so the two are opposed in one line of the source and the
      # core follows both. Only that reading exists in the core, so a file
      # stating another one stops the build rather than being half-applied.
      modifier_source: bonus_slot_flag!(entry, "modifier_source", "modified"),
      # «the caster must have spell slots of that level by virtue of class
      # level. For this purpose, having "0" spell slots counts (but having "-"
      # spell slots does not)» — a printed zero is a key of the class row, an
      # empty cell is an absent key, and the parser already keeps them apart.
      #
      # ⚠ NOT named `requires_…`, and that is not taste: `VocabularyTest`'s
      # source scan reads every two-tuple whose head starts with `requires_` as
      # a refusal form, so a map key spelled that way makes the core look like
      # it produces `{:requires_class_level_slot, …}` and the guard fails on a
      # field that is not a tuple at all. Caught by that test on the first run.
      circle_must_be_in_class_row: bonus_slot_flag!(entry, "circle_must_be_in_class_row", true),
      zero_slots_count: bonus_slot_flag!(entry, "zero_slots_count", true)
    }
  end

  defp bonus_slot_flag!(entry, key, expected),
    do: record_flag!("bonus_spell_slots", entry, key, expected)

  # ⚠ Один читатель на все записи файла, а не копия на каждую: смысл у него
  # ровно один — «ядро реализует одно прочтение, и файл, называющий другое,
  # обязан уронить сборку, а не примениться наполовину». Имя записи приходит
  # аргументом только затем, чтобы сообщение называло виновную запись.
  defp record_flag!(record, entry, key, expected) do
    case Map.fetch(entry, key) do
      {:ok, ^expected} ->
        expected

      other ->
        raise "spellcasting.json: #{record}.#{key} is #{inspect(other)}, " <>
                "and the core only implements #{inspect(expected)}"
    end
  end

  # `circles` is the table's header row and `by_modifier` its body, so the two
  # are zipped rather than the columns being assumed to be 1..9 by position.
  defp bonus_slot_table!(entry) do
    circles = List.wrap(entry["circles"])

    if circles == [] or not Enum.all?(circles, &is_integer/1) do
      raise "spellcasting.json: bonus_spell_slots names no circles header"
    end

    for {modifier, row} <- Map.get(entry, "by_modifier", %{}), into: %{} do
      {integer!(modifier), zip_bonus_row!(circles, row, modifier)}
    end
    |> case do
      table when map_size(table) > 0 -> table
      _ -> raise "spellcasting.json: bonus_spell_slots names no by_modifier rows"
    end
  end

  defp zip_bonus_row!(circles, row, modifier) when is_list(row) do
    if length(row) != length(circles) do
      raise "spellcasting.json: bonus_spell_slots row #{modifier} has #{length(row)} cells " <>
              "for #{length(circles)} circles"
    end

    circles |> Enum.zip(row) |> Map.new()
  end

  defp zip_bonus_row!(_circles, row, modifier) do
    raise "spellcasting.json: bonus_spell_slots row #{modifier} is #{inspect(row)}, not a list"
  end

  defp integer!(value) when is_integer(value), do: value

  defp integer!(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} ->
        number

      _ ->
        raise "spellcasting.json: bonus_spell_slots row key #{inspect(value)} is not an integer"
    end
  end

  # ⚠ No default for any of the three, `minimum` included: `formula["minimum"]
  # || 0` would have read a missing key as «zero», which is a number of the game
  # written in the loader rather than in the file — and one that changes every
  # answer for a caster with a negative modifier.
  defp bonus_slot_formula!(%{} = formula) do
    %{
      divisor: bonus_slot_number!(formula, "divisor"),
      plus: bonus_slot_number!(formula, "plus"),
      minimum: bonus_slot_number!(formula, "minimum")
    }
  end

  defp bonus_slot_formula!(other) do
    raise "spellcasting.json: bonus_spell_slots.formula is #{inspect(other)}, not an object"
  end

  defp bonus_slot_number!(formula, key) do
    case Map.fetch(formula, key) do
      {:ok, number} when is_integer(number) ->
        number

      other ->
        raise "spellcasting.json: bonus_spell_slots.formula.#{key} is #{inspect(other)}, " <>
                "not an integer"
    end
  end

  # The source states the table **and** a general formula for it. They are not
  # two facts: the formula is the rule and the table is its tabulation, so a
  # disagreement between them is a transcription error and the build stops.
  # 234 cells on 21.08.2026, no disagreement — which is also what lets the core
  # continue past the table's last row with the formula instead of clamping.
  defp verify_bonus_slots_against_formula!(rule) do
    mismatches =
      for {modifier, row} <- rule.by_modifier,
          {circle, count} <- row,
          expected =
            BuildCalculator.Rules.Spells.bonus_slots_by_formula(rule.formula, modifier, circle),
          count != expected,
          do: {modifier, circle, count, expected}

    if mismatches != [] do
      raise "spellcasting.json: bonus_spell_slots table disagrees with its own formula at " <>
              inspect(Enum.sort(mismatches))
    end
  end

  # Prestige classes that push **another** class's slot table. Keyed by the
  # prestige class, because that is what a build carries levels of.
  #
  # Only a record the schema can express in full becomes a rule: an unknown
  # `advances`, `host_choice` or `at_class_levels` leaves the class out and is
  # reported as a gap by `advancement_gaps/2`. Half a rule applied silently is
  # exactly the failure this whole file is arranged against — the record itself
  # says why the epic-spell one is left out entirely.
  @advancement_targets %{"spells_per_day" => :spells_per_day}
  @advancement_host_choice %{"highest_class_level" => :highest_class_level}
  @advancement_levels %{"odd" => :odd, "every" => :every}

  def prestige_advancement(:missing, _classes), do: %{}

  def prestige_advancement(file, classes) when is_map(file) do
    for record <- List.wrap(Map.get(file, "prestige_advancement")),
        is_map(record),
        record["verdict"] == "applied",
        record["status"] == "verified",
        rule = advancement_rule(record, classes),
        rule != nil,
        into: %{},
        do: {rule.class, rule}
  end

  defp advancement_rule(record, classes) do
    class = advancement_class!(record["class"], classes)
    hosts = for host <- List.wrap(record["host_classes"]), do: advancement_class!(host, classes)

    target = Map.get(@advancement_targets, record["advances"])
    choice = Map.get(@advancement_host_choice, record["host_choice"])
    levels = Map.get(@advancement_levels, record["at_class_levels"])
    per_grant = record["levels_per_grant"]

    if target && choice && levels && hosts != [] && is_integer(per_grant) do
      %{
        class: class,
        advances: target,
        hosts: hosts,
        host_choice: choice,
        at_class_levels: levels,
        levels_per_grant: per_grant
      }
    end
  end

  # A hand-written file naming a class that does not exist is a typo, and a typo
  # here would silently switch the rule off. Same contract as
  # `feat_skill_bonuses.json`: it breaks the build instead.
  defp advancement_class!(name, classes) when is_binary(name) do
    id = atom(name)

    if Map.has_key?(classes, id),
      do: id,
      else: raise("spellcasting.json names class #{name}, which is not a class")
  end

  defp advancement_class!(other, _classes) do
    raise "spellcasting.json: #{inspect(other)} is not a class name"
  end

  # A class's own one-time choice (`class_choices.json`, `Rules.ClassChoices`)
  # may bend the class's OWN `spells_per_day` row rather than merely being
  # recorded — a Wizard naming a school gains a flat bonus at every circle it
  # already has slots for (AGENT_QUEUE.md §3.10). Same "one human reading,
  # cited" shape as `prestige_advancement/2` above, and deliberately its own
  # top-level key rather than folded into `advancement`: that table lends
  # ANOTHER class's table (Pale Master into its host), this one changes the
  # class's own, and `SpellcastingTest` pins `Map.keys(advancement) ==
  # [:pale_master]` — widening what `advancement` means would break a fact
  # that test protects on purpose.
  #
  # ⚠ Only `"applied"` is understood, same contract as `class_choices.json`:
  # a choice's numeric effect either is checked or does not exist in the model
  # yet, there is no "partially" that stays honest without a schema for it.
  # Unlike `advancement_rule/2`, every field below is required rather than
  # defaulted (`specialization_rule/2` raises if one is missing), so there is
  # no reading of a record that comes back `nil` — nothing here to filter.
  def school_specialization(:missing, _classes), do: %{}

  def school_specialization(file, classes) when is_map(file) do
    for record <- List.wrap(Map.get(file, "school_specialization")),
        is_map(record),
        record["verdict"] == "applied",
        record["status"] == "verified",
        rule = specialization_rule(record, classes),
        into: %{},
        do: {rule.class, rule}
  end

  defp specialization_rule(record, classes) do
    class = advancement_class!(record["class"], classes)

    bonus =
      record["bonus_per_circle"] ||
        raise("spellcasting.json: #{record["class"]} names no bonus_per_circle")

    # ⚠ No default: whether circle 0 (cantrips) is included is exactly what
    # neither source quote settles (see `min_circle_note` beside this record),
    # so the file states the decision rather than the loader assuming one.
    min_circle =
      record["min_circle"] || raise("spellcasting.json: #{record["class"]} names no min_circle")

    opposed =
      for {school, forbidden} <- Map.get(record, "opposed_schools", %{}), into: %{} do
        {atom(school), atom(forbidden)}
      end

    %{
      class: class,
      bonus_per_circle: bonus,
      min_circle: min_circle,
      # The restriction the specialization also imposes — losing the opposed
      # school, scrolls included — is deliberately not a field that toggles
      # behaviour: nothing in the core checks a Wizard's prepared or castable
      # spells against a school at all (no `spells_known` table for wizards),
      # so there is no rule for this to switch on. What it does drive is the
      # **size** of the loss, which is a plain fact about the spell corpus and
      # is counted: `Rules.Spells.specialization_costs/2` pairs each school with
      # how many spells of the wizard's own list the opposed one takes away, and
      # the choice names both halves at the point it is made (task 3.86).
      opposed_schools: opposed
    }
  end

  # What the hand-written casting file leaves unanswered, and what it answers
  # with "we know and are not counting it".
  #
  # ⚠ The second kind used to hold exactly one record, and it is gone: Fandom
  # states a *different* prerequisite for the six epic spells than the one
  # printed in their own `prereq` line («the actual prerequisite is not the
  # ability to cast level 9 spells, but … at least 15 pale master levels»), and
  # since 15.08.2026 that rule **is** applied — in `feat_requirements.json`,
  # where a feat's prerequisites live. The record stayed, under
  # `applied_elsewhere`, and stopped producing a gap: a rule that is counted and
  # still announced as unknown is the false uncertainty CLAUDE.md §6 forbids.
  # `verify_spellcasting_applied!/2` is what keeps it from becoming dead text.
  def spellcasting_gaps(file, classes) do
    minimum =
      if casting_ability_minimum(file), do: [], else: [{:missing_data, :casting_ability_minimum}]

    # ⚠ The one that replaced `{:not_modelled, :bonus_spell_slots_from_ability}`
    # (task 3.70). The old form said «мы это не считаем»; this one fires only
    # when the table is genuinely absent — a rule that is counted and still
    # announced as missing is the false uncertainty CLAUDE.md §6 forbids, and a
    # caster short by seventeen slots a day with nothing said is the opposite
    # failure. Both are the same file's business, so both are decided here.
    bonus_slots =
      if bonus_spell_slots(file), do: [], else: [{:missing_data, :bonus_spell_slots}]

    # Which casters are spontaneous (task 3.124). Without the record the weaker
    # reading of `casts_spell_level` is applied to nobody, so a Bard 4 with
    # charisma 11 is refused a feat the game hands him — the error is a false
    # **illegality**, which the player can at least see and argue with, but it is
    # still a wrong answer and so it is announced.
    spontaneous =
      if spontaneous_casters(file, classes), do: [], else: [{:missing_data, :spontaneous_casters}]

    # A class whose table hands out slots and whose casting ability nobody wrote
    # down. None today — all seven casters carry `primary ability` — and it is
    # here for the day a shard adds one, because the alternative is that class
    # quietly skipping the ability half of every spell requirement.
    unknown_ability =
      for {id, class} <- Enum.sort(classes),
          map_size(class.spells_per_day) > 0,
          is_nil(class.casting_ability),
          do: {:missing_data, {:casting_ability, id}}

    unreadable =
      case file do
        %{"prestige_advancement" => records} when is_list(records) ->
          applied = prestige_advancement(file, classes)

          for record <- records,
              is_map(record),
              record["verdict"] == "applied",
              id = atom(record["class"]),
              not Map.has_key?(applied, id),
              do: {:missing_data, {:caster_advancement, id}}

        _no_records ->
          []
      end

    declared =
      case file do
        %{"not_modelled" => records} when is_list(records) ->
          for record <- records,
              is_map(record),
              id = atom(record["id"]),
              id != nil,
              do: {:not_modelled, {:caster_advancement, id}}

        _no_records ->
          []
      end

    minimum ++ bonus_slots ++ spontaneous ++ unknown_ability ++ unreadable ++ declared
  end

  # A rule read in the casting file and applied in another one — today just the
  # six epic spells, whose real prerequisite is a fact about which class's level
  # is being taken (`vanilla/feat_requirements.json`, `qualifying_class_levels`).
  #
  # The record carries the quotes, the revids and the measurement; the rule
  # itself lives where the schema can check it. This is the seam between the two,
  # and without it the record would be prose nobody reads: the day the other file
  # is rewritten and the key disappears, the six feats would quietly go back to
  # the requirement their own pages call wrong, and this file would still claim
  # the rule is applied. So the claim is checked, and a broken one fails the build
  # rather than the player.
  # ⚠ Silent when the file that applies the rule is not there **at all** — and
  # that is a seam, not a hole. A snapshot without `feat_requirements.json` has
  # rolled back all fourteen of its records at once, which is a far larger event
  # than this record's claim going stale, and it is reported where such things
  # belong: `{:missing_file, "vanilla/feat_requirements.json"}` among the gaps.
  # Raising here as well would only mean the whole ruleset stops loading instead
  # of saying what is missing — and it would break the one honest way to show
  # what a hand-written file does, which is to take it away and look
  # (`Data.FeatRequirementsTest`).
  def verify_spellcasting_applied!(_file, _feats, :missing), do: :ok
  def verify_spellcasting_applied!(:missing, _feats, _applier), do: :ok

  def verify_spellcasting_applied!(%{"applied_elsewhere" => records}, feats, _applier)
      when is_list(records) do
    for record <- records,
        is_map(record),
        key = record["requirement_key"],
        is_binary(key),
        feat_id <- List.wrap(record["feats"]) do
      feat =
        Map.get(feats, atom(feat_id)) ||
          raise "spellcasting.json: #{record["id"]} names #{feat_id}, which is not a feat"

      unless is_map(feat.prereqs) and Map.has_key?(feat.prereqs, key) do
        raise """
        spellcasting.json: #{record["id"]} says the rule is applied in \
        #{record["applied_in"]} through "#{key}", but #{feat_id} carries no such key \
        (its prerequisites are #{inspect(feat.prereqs)}). Either the rule was rolled \
        back — and then this record has to say so instead of claiming otherwise — or \
        the key was renamed and this record was not.
        """
      end
    end

    :ok
  end

  def verify_spellcasting_applied!(_file, _feats, _applier), do: :ok

  # ⚠️ Здесь стояла `specialization_gaps/1` — единственная её запись
  # `{:not_modelled, :wizard_opposed_school}` СНЯТА 24.08.2026 (задача 3.86,
  # решение Dan). Она говорила: прибавку за специализацию (+1 слот на круг)
  # мы считаем, а её цену — потерю противоположной школы — нет, и игрок видит
  # у выбора одну выгоду. Цена теперь названа там, где выбор и делается:
  # ядро отдаёт `Rules.Spells.specialization_costs/2` («Evocation закрывает
  # Conjuration — 27 заклинаний из 179»), веб печатает это на самом чипе школы.
  #
  # 🔴 Запрет каста противоположной школы по-прежнему НЕ проверяется, и это
  # не умолчание: проверять его нечем и не на чем — списка подготовленных
  # заклинаний волшебника в модели нет вовсе, ни одного числа этот запрет
  # у нас не двигает. Гэп — дырка в нашем ОТВЕТЕ, а не в наших знаниях
  # (CLAUDE.md §9), и с того момента, как ответ называет цену выбора,
  # дырки в нём не осталось.

  def strip_links(nil), do: nil

  def strip_links(value) when is_binary(value) do
    value |> String.replace(~r/\[\[(?:[^\]|]*\|)?([^\]]+)\]\]/, "\\1") |> String.trim()
  end
end
