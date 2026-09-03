defmodule BuildCalculator.Rules.LevelUp do
  @moduledoc """
  Validates taking one more class level.

  Two contracts hold here (CLAUDE.md §8):

    * **Reasons are data, never text.** `{:requires_bab, 7}`, `{:max_classes, 4}`,
      `{:requires_race, [:dwarf]}`. Russian wording ("нужен BAB +7") is the web
      layer's job; the core stays language-free and testable.
    * **Every reason at once**, not the first one hit. The UI shows a locked class
      with the full list of what is missing — that is how the tool teaches the
      rules instead of merely refusing.

  ## What is checked, and what is not

  Caps and limits come from the ruleset and are checked in full: character level
  cap, class limit, per-class level caps, the pre-epic prestige ceiling.

  Prerequisites are checked whenever the class record carries a structured
  `requirements` map, and **all twelve prestige classes carry one** — on both
  rulesets, checked by call 10.08.2026, not by memory. Nothing hits the
  `{:missing_data, {:class_requirements, id}}` branch below today: every one of
  the twelve answers a level-1 build with structural reasons instead
  (`weapon_master` with nine on `vanilla`, `champion_of_torm` with two on
  `siala_41`).

  ⚠️ Here stood «the shard layer already provides them for Purple Dragon Knight
  and Harper Scout. Where only prose exists (`requirements_raw`, most vanilla
  prestige classes)…» — stale in both halves, and the same sentence was already
  corrected in `BuildCalculatorWeb.Builder.Import` («тоже устарела, чинить не
  в этой зоне»). It is not two classes and it is not the shard layer: the
  structured block comes off the wiki labels for all twelve, with the prose ones
  read by a human into `priv/rules/vanilla/class_requirements.json`.

  The gap branch stays, and it is not dead weight: `requirements_raw` is present
  on all twelve as well, so a data change that drops the structured block puts
  the gap back rather than declaring the class legal in silence. Guessing "BAB
  +7, dwarf, dodge, toughness" out of a sentence is what it exists to prevent.
  The shape the interpreter reads is

      "requirements": {
        "base_attack_bonus": 7,
        "race": ["dwarf"],
        "feats": ["dodge", "toughness"],
        "skills": {"hide": 8},
        "class_levels": {"bard": 1},
        "abilities": {"str": 13},
        "alignment": "any lawful",
        "any_of": [{"class_levels": {"bard": 3}}, {"class_levels": {"sorcerer": 3}}]
      }

  `any_of` is how a requirement written as a choice arrives — «class: bard **or**
  sorcerer», «arcane spellcasting: level 3 or higher», which the Pale Master page
  glosses as three levels of any one arcane class. Those two do not come off the
  bold labels: their meaning is in the page's prose, so a human reads them into
  `priv/rules/vanilla/class_requirements.json` and the data layer merges them in.
  ⚠️ Until that key reached this far, Pale Master's whole block was a gap and the
  class could be taken at character level 1.

  Alignment phrases are normalised by the data layer into
  `%{require: [...], forbid: [...], exact: [...]}`; a phrase outside that closed
  vocabulary becomes `{:missing_data, :alignment_requirement}`.

  Reading the block itself is `BuildCalculator.Rules.Prereqs`, shared with feats:
  a feat's prerequisites come off the same wiki prose through the same parser and
  must not be checked by a second implementation.
  """

  alias BuildCalculator.Rules.{Build, Prereqs}

  @type reason ::
          {:unknown_class, atom()}
          | {:level_cap, pos_integer()}
          | {:max_classes, pos_integer()}
          | {:class_level_cap, atom(), pos_integer()}
          | Prereqs.reason()

  @doc """
  `:ok`, or every reason the level cannot be taken.

  `choice` is `%{class: class_id}` and `build` is everything taken *before* the
  level being decided; `stats` are that build's derived stats, which is where the
  base attack the prerequisites compare against comes from.

  ## Editing a level in the middle

  `%{class: class_id, at: character_level}` says "set this level's class", and
  then `build` is the **whole** build. The distinction is not cosmetic: limits
  that are properties of the finished build — the class limit, per-class ceilings
  — have to see the levels that come *after* the one being edited, while
  prerequisites (base attack, feats held, ranks bought) are properties of the
  moment and must not. A 40-level build that already uses four classes looks like
  it uses one when level 5 is open, and checking the limit against the levels
  before that point lets a fifth class in and makes the build illegal.

  ⚠️ The split is per rule, and a rule may not straddle it. "The 11th level of a
  prestige class needs 20 character levels" is a rule of the **moment** on both
  of its halves: the count of prestige levels held and the character level are
  read at the level being decided. Mixing the two — a whole-build count against a
  character level of the moment — is what once made the core refuse a legal
  build, and it is invisible while levels are only appended.
  """
  @spec validate(Build.t(), map(), map(), map()) :: :ok | {:error, [reason()]}
  def validate(%Build{} = build, choice, ruleset, stats) do
    class = Map.get(choice, :class)

    case Map.fetch(ruleset.classes, class) do
      :error ->
        {:error, [{:unknown_class, class}]}

      {:ok, definition} ->
        {before, whole} = scope(build, choice, class)

        reasons =
          List.flatten([
            level_cap(whole, ruleset),
            class_limit(whole, ruleset),
            class_level_cap(whole, ruleset, definition),
            prestige_pre_epic(before, whole, ruleset, definition),
            requirements(before, ruleset, definition, stats)
          ])

        if reasons == [], do: :ok, else: {:error, reasons}
    end
  end

  # `before` is what the character had when the decision was made; `whole` is the
  # build that would result. For a level appended at the end the two differ by
  # exactly this one level, which is why the plain form needs no `:at`.
  defp scope(build, %{at: level}, class) when is_integer(level) and level >= 1 do
    {Build.truncate(build, level - 1), Build.replace_level(build, level, class)}
  end

  defp scope(build, _choice, class), do: {build, Build.add_level(build, class)}

  # ------------------------------------------------------------ caps/limits --

  defp level_cap(whole, ruleset) do
    if Build.character_level(whole) > ruleset.level_cap,
      do: [{:level_cap, ruleset.level_cap}],
      else: []
  end

  defp class_limit(_whole, %{max_classes: nil}), do: [{:missing_data, :max_classes}]

  defp class_limit(whole, ruleset) do
    if MapSet.size(Build.classes_used(whole)) > ruleset.max_classes,
      do: [{:max_classes, ruleset.max_classes}],
      else: []
  end

  defp class_level_cap(whole, ruleset, definition) do
    taken = Map.get(Build.class_levels(whole), definition.id, 0)
    cap = effective_class_level_cap(ruleset, definition)

    if is_integer(cap) and taken > cap, do: [{:class_level_cap, definition.id, cap}], else: []
  end

  @doc """
  Highest level this class may reach under this ruleset.

  Base classes run to the character level cap. Prestige classes take the shard's
  prestige cap (Siala: 31), except the ones the shard exempts, which keep their
  vanilla `max_level` — as do all prestige classes when no override is present.
  """
  @spec effective_class_level_cap(map(), map()) :: pos_integer() | nil
  def effective_class_level_cap(ruleset, %{prestige?: false}), do: ruleset.level_cap

  def effective_class_level_cap(ruleset, %{prestige?: true} = definition) do
    prestige = ruleset.prestige

    cond do
      Map.has_key?(prestige.level_cap_exceptions, definition.id) ->
        prestige.level_cap_exceptions[definition.id] || definition.max_level

      MapSet.member?(prestige.never_epic, definition.id) ->
        definition.max_level

      is_integer(prestige.level_cap) ->
        prestige.level_cap

      is_integer(prestige.epic_class_level_cap) ->
        prestige.epic_class_level_cap

      true ->
        # Vanilla records "no cap past character level 20 beyond the character
        # level cap itself" as a null (epic.json, epic_thresholds). The pre-epic
        # ceiling of ten levels is a separate check, below.
        ruleset.level_cap
    end
  end

  # A prestige class stops at 10 levels through character level 20; the 11th
  # needs 20 character levels already (`epic.json`, epic_thresholds).
  #
  # ⚠️ Both halves are properties of **the same moment**, and getting that wrong
  # is what made the check accuse a legal build. It used to count the class
  # levels over the *whole* build while reading the character level off `before`:
  # on a finished "Fighter 10 / Weapon master 31" — the shape the wiki's «Мастер
  # оружия Сагровик» has — editing level 11 showed 31 prestige levels against a
  # character of 10, and the core refused. The build is legal: its 11th Weapon
  # master level falls on character level 21. Appending one level at a time hid
  # it, because there the whole build *is* the moment; it only surfaced on a
  # finished ladder, i.e. on import and on the wiki regression.
  #
  # So the count is taken over the build as it stands **at the level being
  # decided**: everything held before, plus this one level.
  defp prestige_pre_epic(before, whole, ruleset, %{prestige?: true} = definition) do
    cap = ruleset.prestige.pre_epic_class_level_cap
    at = Build.character_level(before) + 1
    taken = Map.get(Build.class_levels(whole, at), definition.id, 0)

    if is_integer(cap) and taken > cap and
         Build.character_level(before) < ruleset.epic.starts_at - 1,
       do: [{:requires_character_level, ruleset.epic.starts_at - 1}],
       else: []
  end

  defp prestige_pre_epic(_before, _whole, _ruleset, _definition), do: []

  # ----------------------------------------------------------- requirements --

  defp requirements(build, ruleset, definition, stats) do
    context = context(build, ruleset, stats)

    alignment_restriction(definition, context) ++
      case definition.requirements do
        nil -> unparsed(definition)
        requirements -> Prereqs.check(requirements, context)
      end
  end

  # `level` is the level being decided, one past what the character already has —
  # the class is taken *on* it. Nothing in a class's requirements asks for a
  # character level today (the schema key is a feat's), but getting the number
  # right here is what keeps the two blocks readable by one interpreter.
  #
  # ⚠ `requirement_of: :class` is not bookkeeping: it is what keeps a feat lent
  # by a worn item counting towards a **class's** `feats` after it stopped
  # counting towards a **feat's** (замер Dan, 14.08.2026 — «но вот КЛАСС можно
  # взять: ВМ требует ряд фитов, и если expertise у нас есть на вещи, то брать
  # его фитом при лвл апе не обязательно»). The rule itself is in
  # `Rules.Prereqs`; this states only whose block is being read.
  defp context(build, ruleset, stats) do
    %{
      build: build,
      ruleset: ruleset,
      stats: stats,
      level: Build.character_level(build) + 1,
      requirement_of: :class
    }
  end

  # A class's own alignment restriction, separate from its prerequisites: Monk is
  # lawful, Barbarian is not (CLAUDE.md §9). A build with no alignment chosen
  # fails it, because the requirement is genuinely unmet.
  defp alignment_restriction(definition, context) do
    cond do
      not is_nil(definition.alignment_restriction) ->
        Prereqs.check(%{alignment: definition.alignment_restriction}, context)

      definition.alignment_restriction_raw not in [nil, "None", "none"] ->
        [{:missing_data, {:alignment_restriction, definition.id}}]

      true ->
        []
    end
  end

  defp unparsed(definition) do
    if definition.prestige? and definition.requirements_raw,
      do: [{:missing_data, {:class_requirements, definition.id}}],
      else: []
  end
end
