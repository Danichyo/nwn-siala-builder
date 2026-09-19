defmodule BuildCalculator.Wiki.Requirements do
  @moduledoc """
  Turns the prose prerequisites of Fandom into the shape the rules core reads.

  Two texts, one grammar. A prestige class writes its criteria as bold labels —

      '''Alignment''': any lawful
      '''[[Base attack bonus]]''': +7
      '''Feats''': [[dodge]], [[toughness]]
      '''[[Race]]''': [[dwarf]]
      '''Skills''': [[hide]] 8 [[rank]]s

  — and a feat writes them as one comma-separated line, `"[[strength]] 13+"` or
  `"21st level, [[quicken spell]], [[spellcraft]] 30, ability to cast 9th level
  spells"`. Both reduce to the same **fragments**, and a fragment names at most
  one thing: an ability score, a skill rank, a feat, a race, a class level, a
  base attack bonus or a character level. The output is the map documented in
  `BuildCalculator.Rules.LevelUp` — `base_attack_bonus`, `race`, `feats`,
  `skills`, `class_levels`, `abilities`, `alignment` — plus `character_level`,
  which only feats ask for.

  ## Which entity a fragment names is looked up, never guessed

  `[[hide]] 8 ranks` is a skill because `hide` is a skill id in the snapshot, and
  `[[monk]] 3` is a class level because `monk` is a class id; the four id spaces
  (classes, skills, feats, races) are disjoint across the whole vanilla
  snapshot, so the lookup is unambiguous. A name in none of them —
  `[[spellcaster]] level 1`, `[[fortitude]] save bonus +8` — is not resolved by
  shape or by hunch: the fragment stays in `unparsed`, with its text.

  ## Four scalars a feat can ask for that a class never does

  `character_level` has three siblings, all of them off feat pages only:

    * `max_character_level` — "Can only take this feat at 1st-level" is the one
      shape on either wiki that states a **ceiling** rather than a floor;
    * `casts_spell_level` — "ability to cast 9th level spells", i.e. the highest
      spell circle the character can cast, not a level of anything;
    * `caster_level` — "spellcaster level 3+", which is the *caster* level and
      parts company with character level the moment a build multiclasses.

  Each number is the one printed on the page. `sap` genuinely says "spellcaster
  level 100", which is how the wiki records that the feat was taken away from
  player characters, and 100 is what is written down.

  Two more scalars name a derived stat rather than a level, and are read for the
  same reason: the core computes both, so both are checkable.

    * `save_bonus` — `%{"fortitude" => 8}` off `resist energy`'s
      "[[fortitude]] save bonus +8". The three saves are the only names accepted;
    * `any_skill_ranks` — "20 ranks in the chosen skill" (`epic skill focus`),
      i.e. *some* skill at that many ranks. It is deliberately not folded into
      `skills`, which names one.

  ## `qualifiers`: what is read, plus what could not be

  A fragment often states a condition the schema has no room for **beside** one
  it does: `[[spell focus]] in the chosen [[spell school]]` really does require
  Spell Focus, and the school it was taken in has nowhere to go. Dropping the
  whole fragment into `unparsed` used to cost the readable half as well, because
  `unparsed` makes the core refuse to check **anything** about the feat.

  So the readable half is kept and the leftover is listed under `qualifiers`, a
  list of the phrases as printed. Three families occur, and each is recognised by
  the word that makes it unreadable rather than by the sentence around it:

    * **a weapon** — `(chosen weapon)`, `with the chosen weapon`, `in a melee
      weapon`, `proficiency with the chosen weapon`. No weapon is modelled
      anywhere in this project (CLAUDE.md §6), so none of these can ever become a
      check;
    * **a school of magic** — `in the chosen spell school`, `(selected spell
      school)`. One page covers Spell Focus in all eight schools;
    * **an aside about the required feat's own prerequisites** — `(requires
      [[ride]] 1)`, the inline form of the `''Note:''` paragraph `cut_note/1`
      already lifts off a label.

  A rank inside a feat *family* joins them when it trails a feat:
  `[[ki strike]] +3` names the third step of a page that covers all three, the
  same thing `granted_feat_ranks` carries verbatim for a class's grants.

  `qualifiers` is **never** the only thing a block says. A phrase that yielded
  nothing at all stays in `unparsed` — "not checked" is a smaller claim than
  "checked, with a footnote" — and a block that ended up with qualifiers and no
  requirement beside them hands them back to `unparsed` in `finish/1`. Inside an
  `any_of` branch they are refused outright: there a footnote could make the
  branch, and so the whole disjunction, pass.

  ## What it refuses to read matters more than what it reads

  The schema is otherwise a **conjunction**, and two shapes on the wiki are
  not:

    * an alternative spread over several fragments —
      `[[elf]], [[half-elf]], or [[red dragon disciple]] 10`. One such `or`
      anywhere in a feat's prerequisites suppresses **every** entity group in
      it, because the alternative may bridge two of them (darkvision is "dwarf,
      half-orc, shadowdancer 2, pale master 3, red dragon disciple 10" — a race
      list and a class list that are one disjunction). Only the scalars survive.

      A disjunction that fits in **one** fragment bridges nothing, so
      `[[smite evil]] or [[smite good]]` is read into `any_of`, a list of
      requirement maps of which any one suffices. It is kept only when every
      branch reads whole: `either [[wild shape]] 6x/day or [[greater wildshape
      IV]]` has a qualifier the schema cannot hold, so the fragment stays prose
      rather than half a rule. Two such fragments in one feat would be two
      independent choices and `any_of` is one list, so a second one puts both
      back into `unparsed`;
    * `<del>…</del>` and `<s>…</s>`, which is how editors record a prerequisite a
      patch **removed** — `epic dodge` still prints `<del>[[dodge]]</del>`.
      Rendering the page shows it struck through; reading it as a requirement
      would resurrect it.

  A qualifier the schema has no room for — `[[weapon focus]] in a [[melee
  weapon]]` — keeps the requirement it qualifies (the feat really is required)
  and states the leftover under `qualifiers`, so nothing reads as fully
  understood when it is not. `[[greater rage]] (6x per day)` gets no such
  treatment: `greater rage` is a redirect and names no page here, so the
  fragment yields nothing to qualify and stays prose entire. Resolving it
  through the redirect would reach `barbarian rage`, which every barbarian has
  from level 1 — the requirement would not weaken, it would vanish.

  That fragment is nevertheless **checked**, and not here: three feat pages
  translate the tier into a class level in their own `Notes` («This feat's
  prerequisites require barbarian level 20»), and a human read the translation
  into `priv/rules/vanilla/feat_requirements.json`, which
  `BuildCalculator.Data.Loader.Feats.apply_feat_requirements/4` lays over this
  reading. `replaces` there holds what this module produced byte for byte, so
  the day this module learns to read the prose itself, the hand-written entry
  raises instead of quietly disagreeing with it.

  ## A feat's list of class levels is the third disjunction, and it is inferred

  `evasion` prints `[[monk]] 1, [[rogue]] 2, [[shadowdancer]] 2`, and read as
  the conjunction the punctuation suggests it would demand a build that is all
  three classes at once. It is the list of the classes that **grant** the feat,
  each with the level it arrives at, so it is an `any_of` — the same reading
  `BuildCalculator.Data.Loader` already applies to the shard's layer, where the
  page writes «Паладин 1 уровня, Чемпион Торма 1 уровня» with the same comma.

  Unlike the `or` above, nothing on the page says so: the conclusion is about
  the game, not about the punctuation. What carries it is that the template
  states the same list twice, and the second time in machine-readable fields —
  `class1..classN` (granted automatically) and `bonus1..bonusN` (may be taken as
  a bonus feat). Across all 275 Fandom pages that carry a `prereq` line, every
  one whose line names two or more classes has those classes and exactly those
  in `classN ∪ bonusN`; `parsed_snapshot_test.exs` pins the equality so that a
  page that stops agreeing with itself is a failing test rather than a silent
  re-reading. No counter-example exists in the corpus.

  ⚠️ The inference is deliberately narrow, because a comma is otherwise an
  "and": `weapon specialization` needs `[[fighter]]` **and** base attack +4
  **and** weapon focus. Only a run of two or more class levels, each read whole,
  turns into a choice, and only on a **feat** page. A prestige class's criteria
  can genuinely ask for two classes at once, so `class/2` keeps dropping such a
  list into `unparsed` (`drop_multi_class/1`) rather than inferring anything.

  Three shapes stay prose for the reasons that already applied to them:
  `uncanny_dodge` writes each class with a parenthesised list of later levels
  (`[[barbarian]] 2 (5, 10, 13, 16, 19)`) and so no fragment reads whole;
  `darkvision` mixes races into the list, which `suppress_race_or_class/1`
  refuses as one disjunction across two groups; and `extra_turning` says
  "exclusive to [[cleric]]s and [[paladin]]s", which is prose about who may
  choose the feat and carries no level at all.

  ## "epic <class>" is a class level, and the number comes off the wiki

  `[[epic class|epic]] [[shifter]]` is not prose to be shrugged at: the page it
  links to states the rule outright — 21 levels for a base class, 11 for a
  prestige class — and `[[epic character]]` links to a page that states 21
  character levels. Both numbers are passed in by the caller (they are the same
  ones written into `epic.json`), never assumed here: without them the phrase
  stays in `unparsed`. The wiki agrees with itself on this, having replaced
  `<del>epic barbarian</del>` with `21st level` on the terrifying rage page.

  Alignment stays the English phrase the page prints (`"any lawful"`, `"any
  non-evil and non-chaotic"`): `BuildCalculator.Data.Loader` owns the closed
  vocabulary it normalises into, and a phrase outside that vocabulary becomes
  `{:missing_data, :alignment_requirement}` there rather than a guess here.
  """

  alias BuildCalculator.Wiki.Wikitable
  alias BuildCalculator.Wiki.Wikitext

  @type result :: %{
          requirements: [{binary, term}],
          unparsed: [binary],
          notes: [binary],
          problems: [binary]
        }

  @type lookup :: %{
          classes: %{binary => binary},
          skills: %{binary => binary},
          feats: %{binary => binary},
          races: %{binary => binary},
          prestige: MapSet.t(binary),
          epic: %{
            optional(:character_level) => pos_integer | nil,
            optional(:base_class_level) => pos_integer | nil,
            optional(:prestige_class_level) => pos_integer | nil
          }
        }

  @abilities %{
    "strength" => "str",
    "dexterity" => "dex",
    "constitution" => "con",
    "intelligence" => "int",
    "wisdom" => "wis",
    "charisma" => "cha"
  }

  # The order keys are written out in, so the committed file is byte-stable and
  # reads the way `Rules.LevelUp` documents it.
  @key_order [
    :alignment,
    :character_level,
    :max_character_level,
    :caster_level,
    :casts_spell_level,
    :base_attack_bonus,
    :save_bonus,
    :abilities,
    :race,
    :feats,
    :skills,
    :any_skill_ranks,
    :class_levels,
    :any_of,
    :qualifiers
  ]

  # Groups an alternative left unread can be about. Ability scores are
  # deliberately not among them: every "or" on these pages is between named
  # things (feats, races, classes), never between two scores, so "charisma 25+"
  # survives an unreadable choice standing next to it. `any_of` is among them
  # because an `or` nobody could read may well reach into the fragment that one
  # came from, and `qualifiers` because a footnote to a requirement that was
  # just withdrawn is a footnote to nothing.
  @entity_groups [:race, :feats, :skills, :class_levels, :any_of, :qualifiers]

  # Bold labels a requirements block uses, folded onto the schema. `base attack`
  # is deliberately **not** an alias of `base attack bonus`: the red dragon
  # disciple's criteria carry its stats table along with them, and that table's
  # "Base attack: middle (+3/4 levels)" row would otherwise be read as +3.
  @labels %{
    "alignment" => :alignment,
    "base attack bonus" => :base_attack_bonus,
    "feat" => :feats,
    "feats" => :feats,
    "race" => :race,
    "skill" => :skills,
    "skills" => :skills,
    "class" => :class,
    "spellcasting" => :spellcasting,
    "arcane spellcasting" => :arcane_spellcasting,
    "divine spellcasting" => :divine_spellcasting
  }

  # The rows of that same stats table. Named one by one so that a genuinely new
  # requirement label still gets reported instead of being swallowed here.
  @not_requirements [
    "hit die",
    "hit dice",
    "skill point",
    "skill points",
    "high saves",
    "base attack",
    "primary saving throw",
    "proficiencies",
    "description"
  ]

  @doc """
  Builds the name -> id index that fragments are resolved against.

  Each record is indexed under both its id and its page title stripped of a
  disambiguating suffix, so that `[[Heal (skill)|heal]]` and `[[heal]]` reach the
  same `heal_skill` record.

  Two extras ride along, both needed only to read the phrase "epic <class>":
  which class ids are prestige (a `prestige?` key on the class records), and the
  `epic` level thresholds the caller read off the `Epic class` page. Leave either
  out and the phrase simply stays unparsed.
  """
  @spec lookup(%{
          required(:classes) => [map],
          required(:skills) => [map],
          required(:feats) => [map],
          required(:races) => [map],
          optional(:epic) => map
        }) :: lookup
  def lookup(snapshot) do
    [:classes, :skills, :feats, :races]
    |> Map.new(fn kind -> {kind, index(Map.fetch!(snapshot, kind))} end)
    |> Map.merge(%{
      prestige: MapSet.new(for c <- snapshot.classes, Map.get(c, :prestige?), do: c.id),
      epic: Map.get(snapshot, :epic) || %{}
    })
  end

  defp index(records) do
    for record <- records, name <- [record.id, base_name(record.title)], into: %{} do
      {name, record.id}
    end
  end

  defp base_name(title), do: title |> String.replace(~r/\s*\([^()]*\)\s*$/u, "") |> id()

  @doc """
  Reads a prestige class's requirements block.

  `requirements` comes back as an ordered list of `{key, value}` pairs ready to
  be written as a JSON object, `unparsed` holds every fragment the pairs do not
  fully carry, `notes` the italic asides the wiki appends to a label (they are
  about the prerequisites of the *feats* being asked for, not about the class),
  and `problems` the labels this module does not know at all.

  A `nil` block returns the same empty result as one that asks for nothing; only
  the caller can tell "the page says no requirements" from "the page is silent".
  """
  @spec class(binary | nil, lookup) :: result
  def class(nil, _lookup), do: finish(empty())

  def class(raw, lookup) do
    {text, deleted} = strip_deleted(raw)
    {labels, notes, problems} = labels(text)

    labels
    |> Enum.reduce(empty(), fn {label, value}, acc -> label(acc, label, value, lookup) end)
    |> add(:notes, notes ++ deleted)
    |> add(:problems, problems)
    |> finish()
  end

  @doc """
  Reads a feat's `prereq` line.

  `"none"` and `"-"` are the wiki saying "no prerequisites at all", and come back
  as an empty requirement list — a different answer from a page that carries no
  `prereq` parameter, which the caller keeps as `null`.
  """
  @spec feat(binary | nil, lookup) :: result
  def feat(nil, _lookup), do: finish(empty())

  def feat(raw, lookup) do
    {text, deleted} = strip_deleted(raw)

    parsed =
      if none?(text) do
        empty()
      else
        text |> fragments() |> Enum.reduce(empty(), &fragment(&2, &1, nil, lookup))
      end

    parsed
    |> suppress_alternatives()
    |> suppress_race_or_class()
    |> class_disjunction()
    |> add(:notes, deleted)
    |> finish()
  end

  defp none?(text) do
    plain = text |> Wikitext.strip_links() |> String.trim() |> String.downcase()
    plain in ["", "none", "-", "n/a"]
  end

  @doc """
  The reverse of `prereqs.feats`: `%{feat id => [feats it is required for]}`.

  The forward index answers "what does this feat need"; the UI needs the other
  direction to answer "what does taking it open up" — the `→ N` badge of
  CLAUDE.md §6. Takes the `{id, requirements}` pairs `feat/2` produced.

  Feats named inside an `any_of` branch count too. The badge is static — it says
  "this feat is a gateway to N others", not "N would open for *you* right now" —
  and Smite Evil is a gateway to Extra Smiting whether or not Smite Good would
  serve just as well. Counting only hard `feats` left both smiting feats claiming
  they open nothing, which is not a smaller truth but a false one.
  """
  @spec unlocks([{binary, [{binary, term}]}]) :: %{binary => [binary]}
  def unlocks(parsed) do
    for {id, requirements} <- parsed,
        prerequisite <- required_feats(requirements),
        reduce: %{} do
      acc -> Map.update(acc, prerequisite, [id], &[id | &1])
    end
    |> Map.new(fn {id, unlocked} -> {id, unlocked |> Enum.uniq() |> Enum.sort()} end)
  end

  # Feat ids this requirement list names, whether required outright or as one of
  # several alternatives. A branch is a requirement list in its own right, wrapped
  # in the `{:obj, …}` the JSON writer uses, so it recurses through the same path.
  defp required_feats(requirements) do
    Enum.flat_map(requirements, fn
      {"feats", feats} -> feats
      {"any_of", branches} -> Enum.flat_map(branches, &branch_feats/1)
      _ -> []
    end)
  end

  defp branch_feats({:obj, pairs}), do: required_feats(pairs)
  defp branch_feats(_other), do: []

  # ── struck-out requirements ─────────────────────────────────────────────────

  @deleted ~r/<(del|s)>(.*?)<\/\1>/su

  defp strip_deleted(text) do
    removed =
      for [_, _tag, inner] <- Regex.scan(@deleted, text),
          trimmed = String.trim(inner),
          trimmed != "",
          do: "removed by a patch (struck out on the page): " <> trimmed

    {String.replace(text, @deleted, " "), removed}
  end

  # ── the requirements block of a class page ──────────────────────────────────

  # Bold labels plus the `! Label: | value` table rows the red dragon disciple
  # uses instead of them. A label's value runs to the next label, which sweeps up
  # the italic `''Note:''` paragraph the wiki appends to some of them — that note
  # is about the required *feat's* own prerequisites, so it is cut off here and
  # reported rather than read as one more requirement.
  defp labels(raw) do
    pairs = Wikitext.labels(raw) ++ Enum.flat_map(Wikitable.find_all(raw), &definition_rows/1)

    {known, notes, problems} =
      Enum.reduce(pairs, {[], [], []}, fn {label, value}, {known, notes, problems} ->
        name = Wikitext.normalize_label(label)
        {value, note} = cut_note(value)

        cond do
          value == "" -> {known, notes ++ note, problems}
          field = Map.get(@labels, name) -> {known ++ [{field, value}], notes ++ note, problems}
          name in @not_requirements -> {known, notes ++ note, problems}
          true -> {known, notes ++ note, problems ++ ["requirement label not read: #{name}"]}
        end
      end)

    {Enum.uniq_by(known, &elem(&1, 0)), notes, problems}
  end

  defp definition_rows(source) do
    source
    |> Wikitable.parse()
    |> Map.fetch!(:rows)
    |> Enum.flat_map(fn
      %{cells: [%{header?: true, text: label}, %{header?: false, text: value}]} ->
        if String.ends_with?(label, ":"), do: [{label, value}], else: []

      _row ->
        []
    end)
  end

  # An italic run opening a line is a note; a bold one is the next label.
  @note_line ~r/^\s*''(?!')/u

  defp cut_note(value) do
    {kept, note} =
      value |> String.split("\n") |> Enum.split_while(&(not Regex.match?(@note_line, &1)))

    case note |> Enum.join("\n") |> String.trim() do
      "" -> {kept |> Enum.join("\n") |> String.trim(), []}
      note -> {kept |> Enum.join("\n") |> String.trim(), [note]}
    end
  end

  defp label(acc, :alignment, value, _lookup) do
    put(acc, :alignment, phrase(value))
  end

  defp label(acc, :base_attack_bonus, value, _lookup) do
    case Regex.run(~r/^\+?(\d+)$/, value |> Wikitext.strip_links() |> String.trim()) do
      [_, bonus] -> put(acc, :base_attack_bonus, String.to_integer(bonus))
      nil -> unparsed(acc, value)
    end
  end

  # A class page's `Race` label is the one alternative that is safe to read:
  # every branch of it is a race, and `race` is a list, i.e. an "any of".
  defp label(acc, :race, value, lookup) do
    ids =
      value
      |> String.split(~r/\bor\b/u)
      |> Enum.flat_map(&fragments/1)
      |> Enum.map(&race_id(&1, lookup))

    if ids != [] and Enum.all?(ids, & &1),
      do: put(acc, :race, ids),
      else: unparsed(acc, value)
  end

  defp label(acc, kind, value, lookup) when kind in [:feats, :skills, :class] do
    value
    |> fragments()
    |> Enum.reduce(acc, &fragment(&2, &1, expected(kind), lookup))
    |> close_class_label(kind, value)
  end

  # `Spellcasting: able to cast first level arcane spells` is a real requirement
  # with no home in the schema. It is written out under its own name so that the
  # loader turns it into `{:missing_data, {:requirement, class, "spellcasting"}}`
  # instead of letting it fall between the prose and the structure.
  defp label(acc, kind, value, _lookup) do
    put(acc, kind, Wikitext.strip_links(value))
  end

  defp expected(:feats), do: :feats
  defp expected(:skills), do: :skills
  defp expected(:class), do: :class_levels

  # `Class: [[bard]] or [[sorcerer]]` is a disjunction and `class_levels` is a
  # conjunction, so more than one branch of it cannot be kept.
  defp close_class_label(acc, :class, _value) do
    if map_size(Map.get(acc.groups, :class_levels, %{})) > 1,
      do: drop(acc, :class_levels),
      else: acc
  end

  defp close_class_label(acc, _kind, _value), do: acc

  defp phrase(value) do
    value
    |> Wikitext.strip_links()
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.trim_trailing(".")
    |> String.trim()
  end

  defp race_id(fragment, lookup) do
    with {:ok, target, ""} <- head(fragment) do
      Map.get(lookup.races, id(target))
    else
      _no -> nil
    end
  end

  # ── fragments ───────────────────────────────────────────────────────────────

  @doc """
  Splits a requirement value on the separators that mean "and".

  Commas, semicolons, newlines and the word `and` — but never inside `[[…]]` (the
  feat `[[sneak attack, blackguard]]` carries a comma in its page title) and
  never inside parentheses (`(5, 10, 13, 16, 19)` is one qualifier, not five
  requirements).
  """
  @spec fragments(binary) :: [binary]
  def fragments(text) do
    text
    |> split("", [], 0, 0)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 in ["", "."]))
  end

  defp split(<<"[[", rest::binary>>, acc, out, link, paren),
    do: split(rest, acc <> "[[", out, link + 1, paren)

  defp split(<<"]]", rest::binary>>, acc, out, link, paren) when link > 0,
    do: split(rest, acc <> "]]", out, link - 1, paren)

  defp split(<<"(", rest::binary>>, acc, out, link, paren),
    do: split(rest, acc <> "(", out, link, paren + 1)

  defp split(<<")", rest::binary>>, acc, out, link, paren) when paren > 0,
    do: split(rest, acc <> ")", out, link, paren - 1)

  defp split(<<" and ", rest::binary>>, acc, out, 0, 0),
    do: split(rest, "", [acc | out], 0, 0)

  defp split(<<char, rest::binary>>, acc, out, 0, 0) when char in [?,, ?;, ?\n],
    do: split(rest, "", [acc | out], 0, 0)

  defp split(<<char::utf8, rest::binary>>, acc, out, link, paren),
    do: split(rest, acc <> <<char::utf8>>, out, link, paren)

  defp split(<<>>, acc, out, _link, _paren), do: Enum.reverse([acc | out])

  @ordinal ~r/^(\d+)(?:st|nd|rd|th)\s+level$/u
  @bab ~r/^base attack bonus(?:\s+of)?\s*\+?(\d+)(?:\s+or higher)?$/u

  # "Can only take this feat at 1st-level" / "…at first level" — a ceiling, and
  # the only one on either wiki. Written as a whole sentence, full stop and all,
  # which is why these three tolerate one.
  @only_at ~r/^can only take this(?:\s+feat)?\s+at\s+(\d+(?:st|nd|rd|th)|first)[-\s]+level\.?$/ui

  # "ability to cast 9th level spells", "ability to cast first-level spells".
  # A leading "the" is already gone: `strip_conjunction/1` takes it off.
  @casts ~r/^ability to cast\s+(\d+(?:st|nd|rd|th)|first)[-\s]+level\s+spells?\.?$/ui

  # "spellcaster level 3+", "[[spellcaster]] level 1".
  @caster ~r/^spellcaster\s+level\s+(\d+)\s*\+?\.?$/ui

  # "[[fortitude]] save bonus +8". The three saves are the whole vocabulary the
  # game has, and the core computes each of them, so this is a real check rather
  # than a name to be shrugged at.
  @save_bonus ~r/^(fortitude|reflex|will)\s+save\s+bonus\s*\+?(\d+)\.?$/ui

  # "20 [[skill rank|rank]]s in the chosen skill" — *some* skill at 20 ranks,
  # which `skills` cannot say because it names one.
  @any_skill_ranks ~r/^(\d+)\s+ranks?\s+in\s+the\s+chosen\s+skill\.?$/ui

  defp fragment(acc, text, expected, lookup) do
    {plain, alternative?} = text |> Wikitext.strip_links() |> String.trim() |> strip_conjunction()

    cond do
      plain == "" ->
        acc

      match = Regex.run(@ordinal, plain) ->
        scalar(acc, :character_level, match, expected, text)

      # Before the alternative below, because "+1 or higher" is one bonus and not
      # a choice between two.
      match = Regex.run(@bab, String.downcase(plain)) ->
        scalar(acc, :base_attack_bonus, match, expected, text)

      level = ordinal(@only_at, plain) ->
        scalar(acc, :max_character_level, level, expected, text)

      level = ordinal(@casts, plain) ->
        scalar(acc, :casts_spell_level, level, expected, text)

      match = Regex.run(@caster, plain) ->
        scalar(acc, :caster_level, match, expected, text)

      match = Regex.run(@save_bonus, plain) ->
        save_bonus(acc, match, text, expected)

      match = Regex.run(@any_skill_ranks, plain) ->
        scalar(acc, :any_skill_ranks, match, expected, text)

      branches = self_contained_alternative(text) ->
        any_of(acc, text, branches, expected, lookup)

      alternative? ->
        acc |> unparsed(text) |> Map.put(:alternatives?, true)

      true ->
        entity(acc, text, plain, expected, lookup)
    end
  end

  # `save_bonus` is a **keyed** group, the same shape as `abilities` and
  # `skills`: a name and a number, one entry per name. Writing it out by hand
  # duplicated `keyed/6`, and the duplicate froze the group into a literal — so
  # its `expected in [nil, :save_bonus]` could never take the second branch,
  # because no bold label routes to `:save_bonus` and none ever will. Going
  # through `keyed/6` keeps the guard meaningful (there `group` is a variable and
  # `:skills` really does reach it) and keeps `source/3` in one place.
  defp save_bonus(acc, [_, save, bonus], text, expected) do
    keyed(acc, :save_bonus, String.downcase(save), {String.to_integer(bonus), ""}, text, expected)
  end

  # "9th" and "first" are the two ways these pages spell an ordinal, and neither
  # is extended to a word this corpus does not use: an unknown spelling stays
  # prose and gets reported rather than being decoded on a hunch.
  defp ordinal(pattern, plain) do
    case Regex.run(pattern, plain) do
      nil -> nil
      [_, word] -> word |> String.downcase() |> ordinal_value()
    end
  end

  defp ordinal_value("first"), do: 1

  defp ordinal_value(digits) do
    case Integer.parse(digits) do
      {number, _suffix} -> number
      :error -> nil
    end
  end

  defp scalar(acc, key, [_, number], expected, text),
    do: scalar(acc, key, String.to_integer(number), expected, text)

  defp scalar(acc, key, number, expected, text) when is_integer(number) do
    if expected in [nil, key],
      do: put(acc, key, number),
      else: unparsed(acc, text)
  end

  # "and whirlwind attack" is the tail of a list; "either A or B" and "or B" are
  # branches of an alternative, and saying so is what stops half of one being
  # read as a requirement of its own.
  defp strip_conjunction(plain) do
    case Regex.run(~r/^(and|the|either|or)\s+(.*)$/ui, plain) do
      [_, word, rest] -> {rest, String.downcase(word) in ["either", "or"]}
      nil -> {plain, false}
    end
  end

  # ── a disjunction that fits in one fragment ─────────────────────────────────

  @either ~r/^\s*either\s+/ui
  @opens_with_or ~r/^\s*or\b/ui

  # Splits `"A or B"` into its branches, or returns `nil` when it is not one.
  #
  # A fragment that *opens* with `or` — the last of `"[[elf]], [[half-elf]], or
  # [[red dragon disciple]] 10"` — is the tail of a disjunction whose other
  # branches are in earlier fragments, so it is not self-contained and reading it
  # alone would turn one third of a choice into a requirement.
  #
  # The split respects `[[…]]` and parentheses for the same reasons `fragments/1`
  # does: `[[weapon focus]] ([[longbow]] or [[shortbow]])` is one requirement
  # with a qualifier, not two.
  defp self_contained_alternative(text) do
    stripped = String.replace(text, @either, "")

    if Regex.match?(@opens_with_or, stripped) do
      nil
    else
      case or_split(stripped, "", [], 0, 0) do
        [_one] -> nil
        branches -> Enum.map(branches, &String.trim/1)
      end
    end
  end

  defp or_split(<<"[[", rest::binary>>, acc, out, link, paren),
    do: or_split(rest, acc <> "[[", out, link + 1, paren)

  defp or_split(<<"]]", rest::binary>>, acc, out, link, paren) when link > 0,
    do: or_split(rest, acc <> "]]", out, link - 1, paren)

  defp or_split(<<"(", rest::binary>>, acc, out, link, paren),
    do: or_split(rest, acc <> "(", out, link, paren + 1)

  defp or_split(<<")", rest::binary>>, acc, out, link, paren) when paren > 0,
    do: or_split(rest, acc <> ")", out, link, paren - 1)

  defp or_split(<<" or ", rest::binary>>, acc, out, 0, 0),
    do: or_split(rest, "", [acc | out], 0, 0)

  defp or_split(<<char::utf8, rest::binary>>, acc, out, link, paren),
    do: or_split(rest, acc <> <<char::utf8>>, out, link, paren)

  defp or_split(<<>>, acc, out, _link, _paren), do: Enum.reverse([acc | out])

  # Kept only when *every* branch reads whole and the fragment stands on its own
  # (`expected` is set only under a class page's bold label, where the schema
  # asks for one named group and has no room for a choice). Anything less falls
  # back to the old answer: prose, plus the flag that poisons the entity groups.
  defp any_of(acc, text, branches, expected, lookup) do
    parsed = Enum.map(branches, &branch(&1, lookup))

    if expected == nil and Enum.all?(parsed, & &1) do
      acc
      |> Map.update!(:groups, fn groups ->
        Map.update(groups, :any_of, [parsed], &(&1 ++ [parsed]))
      end)
      |> source(:any_of, text)
    else
      acc |> unparsed(text) |> Map.put(:alternatives?, true)
    end
  end

  # One branch is one fragment, so it yields one group and nothing left over —
  # `[[wild shape]] 6x/day` keeps its qualifier in `unparsed` and so fails here.
  #
  # A branch is also refused when it read a **qualifier**, which at the top level
  # is welcome. `any_of` passes as soon as one branch does, so a branch resting
  # on a footnote would carry the whole disjunction on it; prose is the smaller
  # claim.
  defp branch(text, lookup) do
    parsed = fragment(empty(), text, nil, lookup)

    if parsed.unparsed == [] and not parsed.alternatives? and parsed.groups != %{} and
         not Map.has_key?(parsed.groups, :qualifiers),
       do: parsed.groups,
       else: nil
  end

  # Resolution is attempted first and always wins: a fragment that names a feat,
  # a skill, a class or a race is that requirement, whatever words trail it. Only
  # a fragment that named nothing at all is offered to the qualifier vocabulary,
  # and only `proficiency with the chosen weapon` is in it today.
  defp entity(acc, text, plain, expected, lookup) do
    case head(text) do
      {:ok, target, tail} -> resolve(acc, text, id(target), tail, expected, lookup)
      :no -> qualifier_or_unparsed(acc, nil, plain, text, expected)
    end
  end

  @first_link ~r/\[\[(?:[^\[\]|]*\|)?([^\[\]|]*)\]\]/u

  # The name comes from the **link target** — `[[Heal (skill)|heal]]` is the
  # `heal_skill` page whatever it is displayed as — and the fragment has to start
  # with what the link *displays*, so that "exclusive to [[cleric]]s and
  # [[paladin]]s" can never be read as a cleric level.
  defp head(text) do
    plain = text |> Wikitext.strip_links() |> String.trim()
    {plain, _alternative?} = strip_conjunction(plain)

    with [_, display] <- Regex.run(@first_link, text),
         [target | _] <- Wikitext.link_targets(text),
         name = Wikitext.strip_links(display),
         true <- prefix?(plain, name) do
      {:ok, target, plain |> String.slice(String.length(name)..-1//1) |> String.trim()}
    else
      _no -> :no
    end
  end

  defp prefix?(plain, name) do
    name != "" and String.starts_with?(String.downcase(plain), String.downcase(name))
  end

  defp resolve(acc, text, id, tail, expected, lookup) do
    cond do
      # "or greater spell focus" — the fragment is one branch of an alternative,
      # never a requirement of its own.
      Regex.match?(~r/^or\b/ui, tail) ->
        acc |> unparsed(text) |> Map.put(:alternatives?, true)

      id == "epic_character" and tail == "" ->
        epic_character(acc, text, expected, lookup)

      id == "epic_class" ->
        epic_class(acc, text, tail, expected, lookup)

      ability = Map.get(@abilities, id) ->
        keyed(acc, :abilities, ability, number(tail), text, expected)

      class = Map.get(lookup.classes, id) ->
        keyed(acc, :class_levels, class, class_level(tail), text, expected)

      skill = Map.get(lookup.skills, id) ->
        keyed(acc, :skills, skill, number(tail), text, expected)

      feat = Map.get(lookup.feats, id) ->
        listed(acc, :feats, feat, tail, text, expected)

      race = Map.get(lookup.races, id) ->
        listed(acc, :race, race, tail, text, expected)

      true ->
        unparsed(acc, text)
    end
  end

  # ── "epic" is a level, and the wiki says which one ──────────────────────────

  # `[[epic character]]` — "characters become epic characters once they have
  # gained 21 levels", which is a character level and nothing else.
  defp epic_character(acc, text, expected, lookup) do
    case get_in(lookup, [:epic, :character_level]) do
      level when is_integer(level) and expected in [nil, :character_level] ->
        put(acc, :character_level, level)

      _no ->
        unparsed(acc, text)
    end
  end

  # `[[epic class|epic]] [[shifter]]` — "to become epic with a specific class the
  # character must have 21 levels for a base class, or 11 levels for a prestige
  # class" (`Epic class`, quoted verbatim in `epic.json`). So the phrase names a
  # class level, and which number it is depends on the class it names.
  #
  # `[[epic class|epic level caster]]` names no class and stays unparsed: there
  # is no such thing as a level of "caster" to count.
  defp epic_class(acc, text, tail, expected, lookup) do
    with class when not is_nil(class) <- Map.get(lookup.classes, id(tail)),
         level when is_integer(level) <- epic_class_level(class, lookup) do
      keyed(acc, :class_levels, class, {level, ""}, text, expected)
    else
      _no -> unparsed(acc, text)
    end
  end

  defp epic_class_level(class, lookup) do
    key =
      if MapSet.member?(Map.get(lookup, :prestige, MapSet.new()), class),
        do: :prestige_class_level,
        else: :base_class_level

    get_in(lookup, [:epic, key])
  end

  defp keyed(acc, _group, _key, nil, text, _expected), do: unparsed(acc, text)

  defp keyed(acc, group, key, {value, rest}, text, expected) do
    if expected in [nil, group] do
      acc
      |> Map.update!(:groups, fn groups ->
        Map.update(groups, group, %{key => value}, &Map.put(&1, key, value))
      end)
      |> source(group, text)
      |> qualified(group, rest, text)
    else
      unparsed(acc, text)
    end
  end

  defp listed(acc, group, value, rest, text, expected) do
    if expected in [nil, group] do
      acc
      |> Map.update!(:groups, fn groups ->
        Map.update(groups, group, [value], &(&1 ++ [value]))
      end)
      |> source(group, text)
      |> qualified(group, rest, text)
    else
      unparsed(acc, text)
    end
  end

  # ── qualifiers ──────────────────────────────────────────────────────────────

  # The closed vocabulary of leftovers that are read as a qualifier rather than
  # as prose. Each is anchored on the noun that puts it outside the schema, not
  # on the sentence around it, so a phrase this corpus does not contain still
  # falls through to `unparsed` instead of being decoded on a hunch.
  @qualifier_patterns [
    # "(chosen weapon)", "with the chosen weapon", "all in the chosen weapon",
    # "in a melee weapon", "proficiency with the chosen weapon" — which weapon
    # the feat was taken in, and no weapon is modelled anywhere (CLAUDE.md §6).
    ~r/^\(?[\p{L} ]*\bweapons?\)?$/u,
    # The same thing with the words the other way round.
    ~r/^\(weapon to be chosen\)$/u,
    # "in the chosen spell school", "(selected spell school)" — which school.
    ~r/^\(?[\p{L} ]*\bschools?\)?$/u,
    # "(requires [[ride]] 1)" — an aside about the required *feat's* own
    # prerequisites, the inline form of the `''Note:''` paragraph `cut_note/1`
    # takes off a label. Kept rather than dropped: the day one of these names a
    # condition the block does not repeat, it has to stay visible.
    ~r/^\(requires\b[^()]*\)$/u
  ]

  # A bare `+3` is a rank inside a feat family — one page covers Ki Strike I, II
  # and III — and means nothing after a class level or an ability score, so it is
  # offered only where a feat was just read.
  @rank_qualifier ~r/^\+\d+$/u

  # `[[weapon focus]] in a [[melee weapon]]` really does require weapon focus, so
  # the feat is kept; the weapon it must be taken in has no home in the schema,
  # so the leftover is stated as a qualifier. Anything the vocabulary above does
  # not cover leaves the whole fragment unread, exactly as before.
  defp qualified(acc, _group, "", _text), do: acc

  defp qualified(acc, group, rest, text), do: qualifier_or_unparsed(acc, group, rest, text, nil)

  defp qualifier_or_unparsed(acc, group, phrase, text, expected) do
    if expected == nil and qualifier?(group, phrase) do
      acc
      |> Map.update!(:groups, fn groups ->
        Map.update(groups, :qualifiers, [phrase], &(&1 ++ [phrase]))
      end)
      |> source(:qualifiers, text)
    else
      unparsed(acc, text)
    end
  end

  defp qualifier?(group, phrase) do
    Enum.any?(@qualifier_patterns, &Regex.match?(&1, phrase)) or
      (group == :feats and Regex.match?(@rank_qualifier, phrase))
  end

  # "13+", "25", "8 [[rank]]s", "(8 ranks)" — the score or rank, plus whatever
  # else was written after it. The word "rank" carries no information here and is
  # dropped first, so that "8 ranks" reads as fully understood and
  # "11 (14, 17, 20)" does not.
  defp number(tail) do
    cleaned =
      tail
      |> String.replace(~r/\bskill\s+ranks?\b/ui, " ")
      |> String.replace(~r/\branks?\b/ui, " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    case Regex.run(~r/^\(?\s*(\d+)\s*\+?\s*(.*?)\)?$/u, cleaned) do
      [_, digits, rest] -> {String.to_integer(digits), String.trim(rest)}
      nil -> nil
    end
  end

  # A class named with no level at all is one level of it ("[[fighter]], [[base
  # attack bonus]] +4, [[weapon focus]]"); a class named with only a
  # parenthesised list of levels ("[[monk]] (10, 13, 16)") states no first level,
  # and one is not invented for it.
  defp class_level(""), do: {1, ""}
  defp class_level(tail), do: number(tail)

  # ── an alternative anywhere poisons every entity in the same list ────────────

  defp suppress_alternatives(%{alternatives?: true} = acc) do
    Enum.reduce(@entity_groups, acc, &drop(&2, &1))
  end

  defp suppress_alternatives(acc), do: acc

  # Два и более классовых уровня в требованиях ФИТА — это список классов, которые
  # его выдают, каждый со своим уровнем выдачи, а не билд, который все они разом.
  # `class_levels` — конъюнкция, поэтому такой список целиком уходил в `unparsed`,
  # а `unparsed` заставляет ядро отказаться проверять фит вообще: у рейнджера
  # 1-го уровня `favored_enemy` — единственный доступный ему бонусный фит —
  # становился недоступен. `any_of` эту дизъюнкцию выражает.
  #
  # ⚠️ Вывод — про игру, а не про запятую (запятая по умолчанию значит «и»:
  # `weapon specialization` требует и воина, и BAB +4, и Weapon Focus). Держится
  # он на том, что шаблон печатает тот же список второй раз машиночитаемыми
  # полями `classN`/`bonusN`; равенство двух списков запинено тестом снапшота.
  #
  # Применяется только к фитам: у престиж-класса «Fighter 4 и Rogue 2» вполне
  # может быть конъюнкцией, поэтому `class/2` по-прежнему просто роняет такой
  # список в `unparsed` (`drop_multi_class/1`).
  defp class_disjunction(acc) do
    classes = Map.get(acc.groups, :class_levels)
    read = Map.get(acc.sources, :class_levels, [])

    if is_map(classes) and map_size(classes) > 1 and Enum.all?(read, &whole?(acc, &1)) do
      branches = for {class, level} <- Enum.sort(classes), do: %{class_levels: %{class => level}}
      {texts, sources} = Map.pop(acc.sources, :class_levels, [])

      %{
        acc
        | groups:
            acc.groups
            |> Map.delete(:class_levels)
            |> Map.update(:any_of, [branches], &(&1 ++ [branches])),
          sources: Map.update(sources, :any_of, texts, &(&1 ++ texts))
      }
    else
      acc
    end
  end

  # Фрагмент прочитан целиком, если после класса ничего не осталось: ни хвоста
  # в `unparsed` (`[[barbarian]] 2 (5, 10, 13, 16, 19)` — уровни улучшений),
  # ни сноски в `qualifiers`. Ветка дизъюнкции проходит одна за всю дизъюнкцию,
  # поэтому ветка, стоящая на недочитанном хвосте, роняет весь вывод.
  defp whole?(acc, text) do
    clean(text) not in acc.unparsed and text not in Map.get(acc.sources, :qualifiers, [])
  end

  # A race list and a class list in the same feat are one disjunction, not a
  # conjunction: darkvision is what dwarves, half-orcs, shadowdancers, pale
  # masters and red dragon disciples each get, and no build is a dwarf *and* a
  # shadowdancer. Neither list can be kept.
  defp suppress_race_or_class(acc) do
    if Map.has_key?(acc.groups, :race) and Map.has_key?(acc.groups, :class_levels),
      do: acc |> drop(:race) |> drop(:class_levels),
      else: acc
  end

  # ── assembling the result ───────────────────────────────────────────────────

  defp empty do
    %{groups: %{}, sources: %{}, unparsed: [], notes: [], problems: [], alternatives?: false}
  end

  defp put(acc, key, value), do: %{acc | groups: Map.put(acc.groups, key, value)}

  # The fragment each entry was read from, so that dropping a group can hand its
  # text back to `unparsed` instead of losing the requirement altogether.
  defp source(acc, group, text),
    do: %{acc | sources: Map.update(acc.sources, group, [text], &(&1 ++ [text]))}

  # Dropping a group is never quiet: whatever fed it goes back to `unparsed`.
  defp drop(acc, group) do
    {raw, sources} = Map.pop(acc.sources, group, [])

    Enum.reduce(
      raw,
      %{acc | groups: Map.delete(acc.groups, group), sources: sources},
      &unparsed(&2, &1)
    )
  end

  defp add(acc, key, values), do: Map.update!(acc, key, &(&1 ++ values))

  defp unparsed(acc, text) do
    case clean(text) do
      "" -> acc
      text -> %{acc | unparsed: acc.unparsed ++ [text]}
    end
  end

  # `unparsed` хранит фрагмент подчищенным, поэтому сравнивать с ним сырой текст
  # фрагмента нельзя — только через ту же нормализацию (см. `whole?/2`).
  defp clean(text) do
    text |> String.trim() |> String.trim_trailing(".") |> String.trim("'") |> String.trim()
  end

  defp finish(acc) do
    acc = acc |> drop_multi_class() |> drop_multi_alternative() |> drop_lone_qualifiers()

    # A fragment reaches `unparsed` twice when it was read with a qualifier and
    # its group was dropped afterwards; it is one fragment either way.
    unparsed = Enum.uniq(acc.unparsed)

    %{
      requirements: render(acc.groups) ++ render_unparsed(unparsed),
      unparsed: unparsed,
      notes: Enum.uniq(acc.notes),
      problems: acc.problems
    }
  end

  # Что осталось после `class_disjunction/1`: список классов престиж-класса
  # (там дизъюнкция не выводится) и список фита, ни один фрагмент которого
  # не прочитан целиком. `class_levels` — конъюнкция, держать в ней несколько
  # классов значило бы требовать билд, который все они разом.
  defp drop_multi_class(acc) do
    case Map.get(acc.groups, :class_levels) do
      classes when is_map(classes) and map_size(classes) > 1 -> drop(acc, :class_levels)
      _one_or_none -> acc
    end
  end

  # `any_of` is one list of alternatives, so it can hold one choice. Two of them
  # in the same prerequisites would be two independent choices — a shape the
  # schema has no room for, and half of it is worse than none.
  defp drop_multi_alternative(acc) do
    case Map.get(acc.groups, :any_of) do
      [_first, _second | _rest] -> drop(acc, :any_of)
      _one_or_none -> acc
    end
  end

  # A qualifier is a footnote to a requirement, so a block that is nothing but
  # footnotes has not been read at all — and left alone it would read as fully
  # understood, because `unparsed` is what makes the core refuse. `skill focus`
  # says only "able to use the skill"; that is prose, not a rule with an aside.
  defp drop_lone_qualifiers(acc) do
    if Map.has_key?(acc.groups, :qualifiers) and map_size(acc.groups) == 1,
      do: drop(acc, :qualifiers),
      else: acc
  end

  defp render(groups) do
    ordered =
      for key <- @key_order,
          value = Map.get(groups, key),
          do: {Atom.to_string(key), json(key, value)}

    extra =
      groups
      |> Enum.reject(fn {key, _value} -> key in @key_order end)
      |> Enum.sort()
      |> Enum.map(fn {key, value} -> {Atom.to_string(key), json(key, value)} end)

    ordered ++ extra
  end

  # A branch is a requirement map in its own right, written out by the same
  # ordering as the whole, so `any_of` reads as a list of little requirements.
  defp json(:any_of, [branches]), do: Enum.map(branches, &{:obj, render(&1)})
  # `devastating critical` says "(weapon to be chosen)" about two feats at once;
  # it is one caveat either way.
  defp json(:qualifiers, phrases), do: Enum.uniq(phrases)
  defp json(_key, value) when is_map(value), do: {:obj, Enum.sort(value)}
  defp json(_key, value), do: value

  defp render_unparsed([]), do: []
  defp render_unparsed(list), do: [{"unparsed", list}]

  defp id(name) do
    name
    |> String.replace(~r/['’]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "_")
    |> String.trim("_")
  end
end
