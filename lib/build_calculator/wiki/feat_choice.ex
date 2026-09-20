defmodule BuildCalculator.Wiki.FeatChoice do
  @moduledoc """
  Which feats may be taken more than once, and what they choose when they are.

  A ranger takes `Favored enemy` once per five levels and picks a different
  racial type each time; `Spell focus` is taken once per school, `Skill focus`
  once per skill. Until now the snapshot said nothing about either half, so the
  rules core had to treat every feat as a one-off — which is the safe default,
  and also wrong for 25 of the 299 vanilla feats.

  ## Why this is a table and not a regex

  Repetition is stated in prose, and prose says the opposite just as fluently.
  Searching for "multiple times" over the corpus returns 29 feats, and **four of
  them are not repeatable at all**:

      armor_skin    "The pencil-and-paper version of this feat could be taken
                     multiple times, but the Neverwinter Nights version can be
                     taken only once."
      epic_prowess  the same sentence
      extra_turning "this feat was going to be obtainable multiple times" — a
                     plan that never shipped
      epic_shadowlord "stronger each time the shadowdancer gains a level" — that
                     is level growth, not a second helping of the feat

  A pattern that marked those four repeatable would err in the direction that
  produces illegal builds. So the decision is human (CLAUDE.md §3: the machine
  points, the human decides) and the *verification* is machine: every entry below
  names the phrase it rests on, `check/1` confirms that phrase is still on the
  page, and `mix wiki.parse` raises when it is not. An edit to the wiki cannot
  quietly change what this file claims.

  ## Three answers, not two

  * `@repeatable` — the page says so outright. Becomes the `repeatable` key.
  * `@repeatable_raw` — the page describes a per-instance choice ("the chosen
    weapon") but never says the feat may be taken again. Becomes `repeatable_raw`:
    a quote and no decision. Every epic variant lands here, because `use` on all
    of them is the bare word "automatic" while the base feat spells the repeat
    out — and inferring the epic case from the base one would be exactly the
    "reasoning by analogy" §3 forbids.
  * `@not_repeatable` — the page addresses repetition in order to deny it. No key
    is written; the entry exists so the guard can tell "classified as no" from
    "never looked at".

  Feats in none of the three simply have no key, which reads as not repeatable.

  ## Choice domains

  `choice` names the dictionary a value is drawn from, and is `nil` where the
  page states the repeat but names nothing to choose (`Epic toughness` just
  stacks). It is never guessed from the feat's name.

      creature_type  priv/rules/vanilla/creature_types.json
      spell_school   priv/rules/vanilla/spell_schools.json
      energy_type    priv/rules/vanilla/energy_types.json
      skill          priv/rules/vanilla/skills.json
      weapon         no dictionary — weapons are not modelled at all (CLAUDE.md
                     §3), so this is an honest gap until the armoury exists

  ⚠️ The names are not free: a domain is resolved by looking for
  `priv/rules/vanilla/<domain>s.json`, so `spell_school` finds its file and a
  domain called `school` would find nothing. `creature_types_test.exs` checks
  every named domain against the directory for exactly that reason.

  ## `distinct`

  Repeating a feat does not always mean picking something new. The focus family
  is explicit that it does — "the effects do not stack… it applies to a different
  school of magic in each case" — while `Epic energy resistance` is equally
  explicit that it does not: "to a maximum of 100 resistance to **each** damage
  type", which takes ten helpings of the same type to reach. Both readings are
  written down; neither is inferred, and where a page settles neither (the ranger
  is never told his favored enemies must differ) no key is written and the core
  keeps its gap.

  ## `same_choice_as`

  `Greater spell focus` requires `Spell focus` **in the same school**, and the
  requirements parser could only record that as a `qualifiers` note reading
  "(selected spell school)" — an admission that the schema could not say it. With
  a choice model it can: `same_choice_as` lists the feats that must have been
  taken with *this* feat's choice value. The raw `qualifiers` stays exactly where
  it was, as the provenance showing which phrase the key was read from.
  """

  alias BuildCalculator.Wiki.Wikitext

  @typedoc "Where in the page a phrase is expected: a template parameter or anywhere."
  @type field :: :use | :description | :page

  @typedoc "The text of one feat: its `use`, its `desc` and its whole page."
  @type texts :: %{use: binary | nil, description: binary | nil, page: binary}

  # id => %{choice:, field:, phrase:} and optionally distinct:.
  #
  # `phrase` is quoted into the snapshot, so where a page settles both questions
  # in adjacent sentences the phrase spans both and one quote carries both facts.
  @repeatable %{
    # The focus family says it in `use`, in one shared pair of sentences whose
    # second half is the whole reason `distinct` exists.
    "spell_focus" => %{
      choice: "spell_school",
      field: :use,
      distinct: true,
      phrase:
        "This feat may be selected multiple times, but the effects do not [[stack]]. It applies to a different school of magic in each case"
    },
    "greater_spell_focus" => %{
      choice: "spell_school",
      field: :use,
      distinct: true,
      phrase:
        "This feat may be selected multiple times, but the effects do not [[stack]]. It applies to a different school of magic in each case"
    },
    "skill_focus" => %{
      choice: "skill",
      field: :use,
      distinct: true,
      phrase:
        "This feat may be selected multiple times, but the effects do not [[stack]]. It applies to a different skill in each case"
    },
    "weapon_focus" => %{
      choice: "weapon",
      field: :use,
      distinct: true,
      phrase:
        "This feat may be selected multiple times, but the effects do not [[stack]]. It applies to a new weapon in each case"
    },
    "weapon_specialization" => %{
      choice: "weapon",
      field: :use,
      distinct: true,
      phrase:
        "This feat may be selected multiple times, but the effects do not [[stack]]. It applies to a new weapon in each case"
    },
    "improved_critical" => %{
      choice: "weapon",
      field: :use,
      distinct: true,
      phrase:
        "This feat can be selected multiple times, applying to a new weapon category each time"
    },

    # No `distinct`: the page says a ranger keeps choosing enemies and never says
    # the choices must differ. Assuming they must would be inventing a rule, and
    # the core's gap is the honest answer (CLAUDE.md §3).
    "favored_enemy" => %{
      choice: "creature_type",
      field: :use,
      phrase: "The ranger may choose additional favored enemies every 5 levels"
    },

    # ⚠️ The counterexample to the focus family: here the *same* damage type is
    # taken again, ten times over, and the cap is stated per type. A model that
    # assumed repeats must differ would refuse a legal build.
    "epic_energy_resistance" => %{
      choice: "energy_type",
      field: :description,
      distinct: false,
      phrase:
        "This feat may be taken multiple times, to a maximum of 100 resistance to each damage type"
    },

    # The epic and "great" families say it in `desc` and name nothing to choose:
    # taking Epic toughness twice is just 40 more hit points.
    "epic_toughness" => %{choice: nil, field: :description, phrase: "may be taken multiple times"},
    "epic_damage_reduction" => %{
      choice: nil,
      field: :description,
      phrase: "This feat may be taken up to three times"
    },
    "great_smiting" => %{choice: nil, field: :description, phrase: "may be taken multiple times"},
    "great_charisma" => %{choice: nil, field: :description, phrase: "may be taken multiple times"},
    "great_constitution" => %{
      choice: nil,
      field: :description,
      phrase: "may be taken multiple times"
    },
    "great_dexterity" => %{
      choice: nil,
      field: :description,
      phrase: "may be taken multiple times"
    },
    "great_intelligence" => %{
      choice: nil,
      field: :description,
      phrase: "may be taken multiple times"
    },
    "great_strength" => %{choice: nil, field: :description, phrase: "may be taken multiple times"},
    "great_wisdom" => %{choice: nil, field: :description, phrase: "may be taken multiple times"},
    "improved_sneak_attack" => %{
      choice: nil,
      field: :description,
      phrase: "may be taken multiple times"
    },
    "improved_spell_resistance" => %{
      choice: nil,
      field: :description,
      phrase: "may be taken multiple times"
    },
    "improved_stunning_fist" => %{
      choice: nil,
      field: :description,
      phrase: "may be taken multiple times"
    },
    # The source wraps this one mid-sentence, between "may" and "be".
    "self_concealment" => %{
      choice: nil,
      field: :description,
      phrase: "may be taken multiple times"
    },
    # These three repeat as a fixed ladder I/II/III rather than a free choice,
    # which is why `choice` is nil: the page numbers the variants, it does not
    # offer a set to pick from.
    "automatic_quicken_spell" => %{
      choice: nil,
      field: :description,
      phrase: "may be taken multiple times"
    },
    "automatic_silent_spell" => %{
      choice: nil,
      field: :description,
      phrase: "may be taken multiple times"
    },
    "automatic_still_spell" => %{
      choice: nil,
      field: :description,
      phrase: "may be taken multiple times"
    },

    # Only the Notes say it, and Notes are not part of the `{{feat}}` template —
    # so this one is invisible to anything reading feats.json alone.
    "weapon_of_choice" => %{
      choice: "weapon",
      field: :page,
      phrase: "take additional weapons of choice"
    }
  }

  # id => {field, phrase} — the page names a choice, never a repeat.
  @repeatable_raw %{
    "arcane_defense" => {:description, "the chosen school of magic"},
    "devastating_critical" => {:description, "with the chosen weapon"},
    "epic_skill_focus" => {:description, "with the chosen [[skill]]"},
    "epic_spell_focus" => {:description, "from the chosen school of magic"},
    "epic_weapon_focus" => {:description, "with the chosen weapon"},
    "epic_weapon_specialization" => {:description, "by the chosen weapon"},
    "overwhelming_critical" => {:description, "When using the weapon chosen"},
    "resist_energy" => {:description, "against the chosen type of energy"},
    # The weapon master's chain inherits its weapon from `weapon_of_choice`,
    # which *is* repeatable — so whether these follow it is a real question, and
    # not one any of their pages answers.
    "superior_weapon_focus" => {:description, "with their weapon of choice"},
    "epic_superior_weapon_focus" => {:description, "with his weapon of choice"},
    "increased_multiplier" => {:description, "With their weapon of choice"},
    "ki_critical" => {:description, "of their weapon of choice"}
  }

  # id => {field, phrase, why the phrase is not an endorsement}
  #
  # ⚠ `extra_turning` — 27.08.2026, task 3.130, a `.2da` sverka against this
  # exact classification found a live contradiction, not a confirmation:
  # `feat.2da` row 13 (`Constant FEAT_EXTRA_TURNING`, sha1
  # `470c84d59da7b158cd5b70de577ad3d8132d95c9` in `priv/hak/2da/manifest.json`)
  # carries `GAINMULTIPLE 1, EFFECTSSTACK 1` — the client's own flag for "may be
  # taken again, and stacks" — which is the opposite of what the cited Fandom
  # sentence claims about the shipped game. Left `:not_repeatable` on purpose:
  # a machine table outranks nothing that a human already read off the wiki and
  # cited (CLAUDE.md §3 — "не «чини» противоречия… зафиксируй оба значения"),
  # and this project has one proven case of a `.2da` row staying perfectly
  # ordinary for a feat the shard disables by a server script the client-side
  # table cannot see at all (the seven `weapon_proficiency_*` families,
  # `docs/hak_diff_feats.md`) — so a table saying "repeatable" is not
  # automatically the last word either. Cheap to settle in play (`GAME_CHECKS.md`
  # AG1): a level-1 Cleric already has `turn_undead`, and Extra Turning is a
  # character-level-1 general-slot pick. Do not flip this entry until it answers.
  @not_repeatable %{
    "armor_skin" =>
      {:page, "the ''Neverwinter Nights'' version can be taken only once",
       "names repetition to rule it out — the pen-and-paper version had it, NWN does not"},
    "epic_prowess" =>
      {:page, "the ''Neverwinter Nights'' version can be taken only once",
       "names repetition to rule it out — the pen-and-paper version had it, NWN does not"},
    "extra_turning" =>
      {:page, "this feat was going to be obtainable multiple times",
       "describes a plan from development that never reached a released version"},
    "epic_shadowlord" =>
      {:description, "making him stronger each time",
       "\"each time\" counts class levels, not takings of the feat"}
  }

  # id => %{feats: must carry the same choice value, phrase: as printed in
  # `prereq`, supersedes: the parsed `qualifiers` string this now replaces}
  #
  # `supersedes` is set only where the key genuinely closes the caveat. Removing
  # a `qualifiers` string removes a warning, so it is safe exactly when the core
  # can check the thing instead — which needs **two** things: a dictionary for
  # the domain, and a feat that can record a choice at all.
  #
  # ⚠️ The second condition is the one that used to be invisible.
  # `same_choice_reasons/4` is reached only from `repeat_reasons/6`, so a feat
  # the wiki never calls repeatable cannot carry a choice and its
  # `same_choice_as` never fires — the key sits in the data looking applied.
  # `arcane_defense` is exactly that case and is why its `supersedes` is `nil`
  # even though `spell_schools.json` has existed all along.
  #
  # Task 3.5 part A gave weapons a dictionary (`weapons.json`), which closes the
  # first condition for all six weapon entries. The second splits them:
  #
  #   * `weapon_specialization` and `weapon_of_choice` are repeatable on **both**
  #     rulesets, so the requirement is enforced and the caveat comes off;
  #   * `epic_weapon_focus` and `epic_weapon_specialization` are repeatable only
  #     on Siala (Dan, 02.08.2026 — see the shard feat layer), and this table
  #     feeds `vanilla/feats.json`, which both rulesets read. Superseding here
  #     would drop the caveat on vanilla too, where nothing checks it — false
  #     legality, the direction that costs more. They keep it;
  #   * `devastating_critical` and `overwhelming_critical` are repeatable on
  #     neither, so nothing checks them anywhere and the caveat is simply true.
  #
  # ⚠️ Still owed, and not a data fix: on siala_41 the two epic feats now *are*
  # checked and still print «оговорку, которую схема выразить не может». That is
  # the mirror-image lie CLAUDE.md §6 warns about, and closing it needs either a
  # per-ruleset `qualifiers` or a core rule ("a qualifier a checked
  # `same_choice_as` covers is not a gap") — dev-rules, not this table.
  @same_choice_as %{
    "arcane_defense" => %{
      feats: ["spell_focus"],
      phrase: "in the chosen [[spell school]]",
      supersedes: nil
    },
    "devastating_critical" => %{
      feats: ["improved_critical", "overwhelming_critical"],
      phrase: "(weapon to be chosen)",
      supersedes: nil
    },
    "epic_spell_focus" => %{
      feats: ["spell_focus", "greater_spell_focus"],
      phrase: "in the chosen [[spell school|school]]",
      supersedes: "in the chosen school"
    },
    "epic_weapon_focus" => %{
      feats: ["weapon_focus"],
      phrase: "with the chosen weapon",
      supersedes: nil
    },
    "epic_weapon_specialization" => %{
      feats: ["weapon_focus", "epic_weapon_focus", "weapon_specialization"],
      phrase: "all in the chosen weapon",
      supersedes: nil
    },
    "greater_spell_focus" => %{
      feats: ["spell_focus"],
      phrase: "(selected [[spell school]])",
      supersedes: "(selected spell school)"
    },
    "overwhelming_critical" => %{
      feats: ["improved_critical"],
      phrase: "(chosen weapon)",
      supersedes: nil
    },
    "weapon_of_choice" => %{
      feats: ["weapon_focus"],
      phrase: "(chosen weapon)",
      supersedes: "(chosen weapon)"
    },
    "weapon_specialization" => %{
      feats: ["weapon_focus"],
      phrase: "(chosen weapon)",
      supersedes: "(chosen weapon)"
    }
  }

  # Broad on purpose: it is the guard's job to over-report, and every hit must be
  # accounted for by one of the three tables above.
  @signal ~r/multiple times|more than once|additional favored|additional weapons|up to (?:two|three|four|five|seven|ten) times|only once|obtainable multiple|each time/iu

  @doc "Feat ids classified as repeatable, sorted."
  @spec repeatable_ids() :: [binary]
  def repeatable_ids, do: @repeatable |> Map.keys() |> Enum.sort()

  @doc "Feat ids left for a human to decide, sorted."
  @spec raw_ids() :: [binary]
  def raw_ids, do: @repeatable_raw |> Map.keys() |> Enum.sort()

  @doc "Feat ids whose pages discuss repetition in order to deny it, sorted."
  @spec not_repeatable_ids() :: [binary]
  def not_repeatable_ids, do: @not_repeatable |> Map.keys() |> Enum.sort()

  @doc "Feat ids carrying a `same_choice_as` entry, sorted."
  @spec same_choice_ids() :: [binary]
  def same_choice_ids, do: @same_choice_as |> Map.keys() |> Enum.sort()

  @doc "The reason a `@not_repeatable` entry is not an endorsement."
  @spec denial_reason(binary) :: binary | nil
  def denial_reason(id) do
    case Map.fetch(@not_repeatable, id) do
      {:ok, {_field, _phrase, reason}} -> reason
      :error -> nil
    end
  end

  @doc """
  What the snapshot should say about `id`, given the text of its page.

  Returns `{:repeatable, choice, quote}`, `{:raw, quote}` or `:none`. The quote is
  always lifted from `texts` — see `BuildCalculator.Wiki.Wikitext.sentence_with/2`.
  Raises when a curated phrase is no longer in the source, because at that point
  the table is making a claim the wiki does not support.
  """
  @spec decide(binary, texts) :: {:repeatable, map} | {:raw, binary} | :none
  def decide(id, texts) do
    cond do
      entry = Map.get(@repeatable, id) ->
        decided = %{choice: entry.choice, quote: quote!(id, texts, entry.field, entry.phrase)}

        case Map.fetch(entry, :distinct) do
          {:ok, distinct} -> {:repeatable, Map.put(decided, :distinct, distinct)}
          :error -> {:repeatable, decided}
        end

      entry = Map.get(@repeatable_raw, id) ->
        {field, phrase} = entry
        {:raw, quote!(id, texts, field, phrase)}

      true ->
        :none
    end
  end

  @doc """
  The feats that must share `id`'s choice, or `nil`.

  `prereq_raw` and the already-parsed `feats` list are both checked: the phrase
  has to still be in the prose, and every feat named has to still be a
  prerequisite. Either check failing means the requirement moved and the key
  would now assert something nobody wrote.
  """
  @spec same_choice_as(binary, binary | nil, [binary]) :: map | nil
  def same_choice_as(id, prereq_raw, prereq_feats) do
    case Map.fetch(@same_choice_as, id) do
      :error ->
        nil

      {:ok, entry} ->
        unless prereq_raw && String.contains?(flatten(prereq_raw), flatten(entry.phrase)) do
          raise """
          #{id}: same_choice_as rests on "#{entry.phrase}", which is no longer in its \
          prerequisites (#{inspect(prereq_raw)})
          """
        end

        case entry.feats -- prereq_feats do
          [] ->
            %{feats: entry.feats, quote: entry.phrase, supersedes: entry.supersedes}

          missing ->
            raise """
            #{id}: same_choice_as names #{inspect(missing)}, which #{id} no longer \
            requires (requires #{inspect(prereq_feats)})
            """
        end
    end
  end

  @doc """
  Feat ids whose text talks about repetition but which no table classifies.

  This is the completeness half of the contract. The tables were built by reading
  the 29 feats this pattern matches; anything the wiki adds later shows up here,
  and `mix wiki.parse` refuses to write a snapshot while it is non-empty. Without
  it a newly repeatable feat would simply be absent, and absence reads as "not
  repeatable" — a silent wrong answer rather than a loud one.
  """
  @spec unclassified(%{binary => texts}) :: [binary]
  def unclassified(by_id) do
    ids =
      for {id, texts} <- by_id,
          not Map.has_key?(@repeatable, id),
          not Map.has_key?(@repeatable_raw, id),
          not Map.has_key?(@not_repeatable, id),
          Regex.match?(@signal, flatten(text_of(texts, :page))),
          do: id

    Enum.sort(ids)
  end

  @doc """
  Confirms every curated phrase is still in the page it was read from.

  Covers `@not_repeatable` too, which `decide/2` never touches: a page that stops
  denying repetition is exactly the edit that should be noticed.
  """
  @spec check!(%{binary => texts}) :: :ok
  def check!(by_id) do
    for {id, entry} <- @repeatable,
        do: quote!(id, fetch!(by_id, id), entry.field, entry.phrase)

    for {id, {field, phrase}} <- @repeatable_raw,
        do: quote!(id, fetch!(by_id, id), field, phrase)

    for {id, {field, phrase, _reason}} <- @not_repeatable,
        do: quote!(id, fetch!(by_id, id), field, phrase)

    :ok
  end

  defp fetch!(by_id, id) do
    case Map.fetch(by_id, id) do
      {:ok, texts} ->
        texts

      :error ->
        raise "#{id}: named by BuildCalculator.Wiki.FeatChoice but absent from the feat snapshot"
    end
  end

  defp quote!(id, texts, field, phrase) do
    text = text_of(texts, field)

    case Wikitext.sentence_with(text || "", phrase) do
      {:ok, sentence} ->
        sentence

      :error ->
        raise """
        #{id}: the phrase "#{phrase}" is no longer in its #{field}. The decision \
        recorded in BuildCalculator.Wiki.FeatChoice rests on that phrase, so it \
        has to be re-read against the page rather than carried over.
        """
    end
  end

  defp text_of(texts, :use), do: texts.use
  defp text_of(texts, :description), do: texts.description
  defp text_of(texts, :page), do: texts.page

  defp flatten(text), do: String.replace(text, ~r/\s+/u, " ")
end
