defmodule BuildCalculator.Wiki.SkillPage do
  @moduledoc """
  Reads one Fandom skill page into the fields a build calculator needs.

  Skill pages carry no template either, but unlike class pages they are almost
  regular: 28 of the 41 members of `Category:Skills` open with the same bullet
  labels, written in the two punctuation styles the wiki mixes everywhere —

      *'''Ability''': [[dexterity]]
      * '''Classes''': [[bard]], [[rogue]]
      *'''[[Cross-class skill|Cross-class]]''': yes
      *'''[[untrained skill check|Requires training]]''': no
      *'''Check''': …
      *'''Use''': …

  The other 13 members are rules pages filed under the same category (`skill
  point`, `class skill`, `armor check penalty`) plus the two combat modes
  (`stealth`, `detect`). They have no `Ability` label, and that — not a hand
  written list of titles — is what tells them apart: `key_ability_raw` comes back
  `nil` and the caller skips the page and says so.

  ## What the page does not say

  **Nothing on a skill page mentions the armor check penalty.** The list of
  affected skills lives once, on the `Armor check penalty` page, in a sentence
  that also states it is exhaustive ("The only dexterity-based skills not on this
  list are open lock and ride"). `armor_check_skills/1` reads that sentence, and
  the caller joins it onto the skills; if the sentence ever stops matching, every
  skill gets `nil` rather than a fabricated `false`.

  Everything else is kept verbatim, wiki markup included, in a `*_raw` field, so
  a value can still be diffed against the page it came from (CLAUDE.md §3).
  """

  alias BuildCalculator.Wiki.Wikitext

  @type t :: %{
          key_ability: binary | nil,
          key_ability_raw: binary | nil,
          trained_only: boolean | nil,
          trained_only_raw: binary | nil,
          cross_class_raw: binary | nil,
          classes_raw: binary | nil,
          classes: [binary],
          classes_all?: boolean,
          check_raw: binary | nil,
          use_raw: binary | nil,
          special_raw: binary | nil,
          description: binary | nil,
          extra_labels: [{binary, binary}],
          problems: [binary]
        }

  @label_fields %{
    ability: ["ability"],
    classes: ["classes"],
    cross_class: ["cross class", "cross class skill"],
    trained: ["requires training", "untrained"],
    check: ["check"],
    use: ["use"],
    special: ["special"]
  }

  # Both spellings the wikis use for an ability score, abbreviated and spelled out.
  @ability_names %{
    "str" => "STR",
    "strength" => "STR",
    "dex" => "DEX",
    "dexterity" => "DEX",
    "con" => "CON",
    "constitution" => "CON",
    "int" => "INT",
    "intelligence" => "INT",
    "wis" => "WIS",
    "wisdom" => "WIS",
    "cha" => "CHA",
    "charisma" => "CHA"
  }

  # Image, category and interwiki lines are page furniture, not prose: they sit
  # both above the first label (where the description is read) and below the last
  # one (where they would otherwise be swallowed as its continuation).
  @furniture ~r/^\s*\[\[\s*(?:image|file|category)\s*:/iu
  @label_line ~r/^\s*\*+\s*'''/u

  @doc """
  Parses a skill page.

  Returns the parsed fields plus `problems` — human-readable strings for
  everything the page did not yield, which the caller is expected to report
  rather than swallow. A page with no `Ability` label is not a skill: it comes
  back with `key_ability_raw: nil` and no problems, since there is nothing wrong
  with a rules page for it to be.
  """
  @spec parse(binary) :: t
  def parse(wikitext) do
    {description, body} = split_lead(wikitext)
    labels = labels(body)
    classes_raw = labels[:classes]

    %{
      key_ability: ability(labels[:ability]),
      key_ability_raw: labels[:ability],
      trained_only: yes_no(labels[:trained]),
      trained_only_raw: labels[:trained],
      cross_class_raw: labels[:cross_class],
      classes_raw: classes_raw,
      classes: Wikitext.link_targets(classes_raw || ""),
      classes_all?: classes_raw != nil and Wikitext.strip_links(classes_raw) == "all",
      check_raw: labels[:check],
      use_raw: labels[:use],
      special_raw: labels[:special],
      description: description,
      extra_labels: labels[:__extra__],
      problems: problems(labels)
    }
  end

  @doc """
  Reads the skills an armor check penalty applies to off the `Armor check
  penalty` page.

  The whole fact is one sentence — "it applies to `[[hide]]`, `[[move
  silently]]`, … and `[[tumble]]`" — which the page immediately declares
  exhaustive, so a skill missing from the returned list genuinely takes no
  penalty. Returns `nil`, not `[]`, when the sentence does not match: "the page
  no longer says" must not read as "no skill is affected".
  """
  @spec armor_check_skills(binary) :: [binary] | nil
  def armor_check_skills(wikitext) do
    case Regex.run(~r/\bit applies to\s+((?:\[\[[^\[\]]+\]\][,\s]*(?:and\s+)?)+)\./u, wikitext) do
      [_, list] -> Wikitext.link_targets(list)
      nil -> nil
    end
  end

  # ── the lead ──────────────────────────────────────────────────────────────

  # The lead splits at the first bullet label: prose above it, labels below.
  # Splitting matters — half the pages open with `'''Lore''' allows a character
  # to…`, which `Wikitext.labels/1` would otherwise read as a label named "lore".
  # The prose is kept verbatim, markup included.
  defp split_lead(wikitext) do
    [lead | _] = Wikitext.sections(wikitext)

    {above, below} =
      lead.body
      |> String.split("\n")
      |> Enum.reject(&Regex.match?(@furniture, &1))
      |> Enum.split_while(&(not Regex.match?(@label_line, &1)))

    {above |> Enum.join("\n") |> String.trim() |> blank_to_nil(), Enum.join(below, "\n")}
  end

  defp labels(body) do
    pairs =
      for {label, value} <- Wikitext.bullet_labels(body),
          do: {Wikitext.normalize_label(label), String.trim(value)}

    known =
      for {field, names} <- @label_fields,
          {name, value} <- pairs,
          name in names,
          value != "",
          reduce: %{} do
        acc -> Map.put_new(acc, field, value)
      end

    taken = @label_fields |> Map.values() |> List.flatten() |> MapSet.new()

    extra =
      pairs
      |> Enum.reject(fn {name, value} -> MapSet.member?(taken, name) or value == "" end)
      |> Enum.reduce(%{}, fn {name, value}, acc -> Map.put_new(acc, name, value) end)
      |> Enum.sort()

    Map.put(known, :__extra__, extra)
  end

  # ── scalar readings of a label ────────────────────────────────────────────

  defp ability(nil), do: nil

  defp ability(value) do
    Map.get(@ability_names, value |> Wikitext.strip_links() |> String.downcase())
  end

  # Only the two words the pages actually use. Anything else stays unread rather
  # than being coerced into a boolean nobody checked.
  defp yes_no(nil), do: nil

  defp yes_no(value) do
    case value |> Wikitext.strip_links() |> String.downcase() |> String.trim_trailing(".") do
      "yes" -> true
      "no" -> false
      _other -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # A page with no `Ability` label is a rules page filed under `Category:Skills`
  # rather than a skill — `class skill`, `difficulty class`, the `stealth` mode.
  # It carries none of these labels, so the record comes back empty by itself,
  # and it earns no problems either: there is nothing wrong with it.
  defp problems(%{ability: raw} = labels) do
    # `cross_class` and `special` are genuinely optional — a third of the pages
    # carry neither — so their absence is a `nil` the caller counts, not a fault.
    missing =
      for {field, [name | _]} <- Enum.sort(@label_fields),
          field not in [:cross_class, :special],
          is_nil(labels[field]),
          do: "no '#{name}' label"

    unreadable = if ability(raw), do: [], else: ["unknown ability name: #{raw}"]

    missing ++ unreadable ++ unreadable_training(labels[:trained])
  end

  defp problems(_no_ability), do: []

  defp unreadable_training(nil), do: []

  defp unreadable_training(value) do
    if is_nil(yes_no(value)),
      do: ["'requires training' is neither yes nor no: #{value}"],
      else: []
  end
end
