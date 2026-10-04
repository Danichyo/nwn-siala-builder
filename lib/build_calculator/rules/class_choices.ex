defmodule BuildCalculator.Rules.ClassChoices do
  @moduledoc """
  A class's own one-time choice, held for the rest of the build.

  Separate from `BuildCalculator.Rules.FeatChoices` on purpose, even though the
  two end up sharing almost everything: a feat's parameter is picked **with**
  a specific pick, in a specific slot, and may in some families be taken again
  elsewhere in the build (`Favored enemy`, ten times over). A class's choice
  belongs to the class itself — a Cleric picks two domains once, when the
  class's own first level is taken, and every later Cleric level in the build
  simply inherits it. There is no slot, no repetition, and (unlike a feat)
  nothing to distinguish "not yet chosen" from "chose nothing on purpose",
  because `required?` already answers that per class.

  ## One mechanism, not two

  A Cleric's two domains (this module's only populated entry today) and a
  future Wizard's one school (AGENT_QUEUE.md §3.10) are the same shape: `count`
  distinct values drawn from one named domain in `ruleset.choice_domains` —
  the exact table `FeatChoices` already reads a feat's parameter from. Reusing
  it rather than building a second "values dictionary with names" is why a
  Wizard's `spell_school` domain will already exist the day 3.10 is written:
  `Spell focus` already names it.

  Which classes have a choice, out of what domain, how many values and
  whether it is required is `ruleset.class_choices`, built by
  `BuildCalculator.Data.Loader` from `priv/rules/vanilla/class_choices.json` —
  never a class id written out in this file.

  ## What is not here

  What a domain value *does* — a Cleric domain's special ability, the spells
  it adds to the list — is not modelled at all (решение Дана, AGENT_QUEUE.md
  §3.14): the choice is recorded and shown in the progression column, and
  nothing about it reaches `Rules.compute/2`'s numbers. So there is no `gaps/3`
  in this module the way `FeatChoices` has one.

  ⚠ Nor is there a ruleset-wide note any more. `{:not_modelled,
  :cleric_domains}` used to say this out loud in `ruleset.gaps`; it was
  **removed 22.08.2026 by Dan's decision** (task 3.79), because none of the
  three things it covered can reach an answer this calculator gives: a domain's
  *active* powers are timed and switchable, i.e. buffs (Dan, 10.08.2026); its
  *passive* ones are turning, healing and summons, which nothing here counts;
  and its *spells* are handed out automatically, so there is no choice to
  model. Dan: «домены клерика дают ему новые заклинания, но выбирать их
  не надо, они выдаются автоматически. Получается для конструктора здесь
  делать нечего».

  🔴 **The choice itself is untouched by that** — it is exactly what Dan called
  ready, and it is what this module is: two distinct domains, required, asked
  for on the class's own first level, and the level stays unsettled until both
  are named. What did *not* go away is the per-build gap for a domain whose
  dictionary is missing (`{:missing_data, {:choice_domain, …}}` in `reason()`
  below) — that one is about *our* data being absent, not about the game.
  """

  alias BuildCalculator.Rules.{Build, FeatChoices}

  @type reason ::
          {:no_choice, atom()}
          | {:invalid_class_choice, atom(), atom()}
          | {:class_choice_full, atom(), pos_integer()}
          | {:missing_data, {:choice_domain, atom()}}

  @doc """
  The choice `class_id` asks for, or `nil` when it has none.

  A Cleric's is `%{domain: :domain, count: 2, distinct?: true, required?: true,
  no_selection_name: nil}` — the last key is `no_selection_name/2`'s own
  field, carried here rather than duplicated by a second lookup.
  """
  @spec spec(atom(), map()) :: map() | nil
  def spec(class_id, ruleset), do: Map.get(Map.get(ruleset, :class_choices, %{}), class_id)

  @doc "The domain `class_id`'s choice is drawn from, or `nil` when it has none."
  @spec domain(atom(), map()) :: atom() | nil
  def domain(class_id, ruleset) do
    case spec(class_id, ruleset) do
      %{domain: domain} -> domain
      nil -> nil
    end
  end

  @doc "Whether `class_id`'s choice must be made before the build is complete."
  @spec required?(atom(), map()) :: boolean()
  def required?(class_id, ruleset) do
    case spec(class_id, ruleset) do
      %{required?: required?} -> required?
      nil -> false
    end
  end

  @doc """
  The word the game CLIENT prints for "`class_id`'s choice, left unmade" — a
  Wizard's `General` — or `nil` when the ruleset has none (a Cleric, or any
  ruleset older than task 3.170).

  Reads `Map.get/2`, not `spec.no_selection_name`, on purpose: a synthetic
  ruleset built by hand for a test (`ClassChoicesTest`'s own `ruleset/1`,
  `builder_live_test.exs`'s fixtures) is not guaranteed to carry the key —
  `BuildCalculator.Data.Loader.Classes.build_class_choices/2` always sets it,
  but nothing here should raise on a `ruleset.class_choices` map some other
  test built by literal.
  """
  @spec no_selection_name(atom(), map()) :: String.t() | nil
  def no_selection_name(class_id, ruleset) do
    case spec(class_id, ruleset) do
      %{} = spec -> Map.get(spec, :no_selection_name)
      nil -> nil
    end
  end

  @doc """
  Every value `class_id`'s choice may draw from, unfiltered by what is already
  picked — the picker's full list, chosen values included.

    * `:no_choice` — this class has no choice mechanic at all.
    * `{:ok, values}` — the domain's dictionary, sorted.
    * `:none` — the class has a choice, but its domain has no dictionary
      (`{:missing_data, {:choice_domain, domain}}` is the build-facing form of
      this; nothing in this module produces it as a build gap because it is
      not a fact about any one build, see the module doc).
  """
  @spec values(atom(), map()) :: :no_choice | {:ok, [atom(), ...]} | :none
  def values(class_id, ruleset) do
    case spec(class_id, ruleset) do
      nil ->
        :no_choice

      %{domain: domain} ->
        case domain_values(domain, ruleset) do
          {:ok, values} -> {:ok, Enum.sort(values)}
          :none -> :none
        end
    end
  end

  @doc """
  Whether `class_id` has all the values its choice requires.

  A class with no choice, or one whose choice is not `required?`, is trivially
  complete — an unmade optional choice (a Wizard staying "general", task
  3.10) is a legitimate final state, not an open question.

  Unlike everything else `level_settled?/3` asks in the web layer, there is no
  `level` parameter to scope this by: the choice is not stored per level (see
  `Build.class_choices`), so it is judged against the build exactly as given —
  callers that want the answer "as it stood earlier" pass a `Build.truncate/2`
  build in, the same way any other caller would.
  """
  @spec complete?(Build.t(), atom(), map()) :: boolean()
  def complete?(%Build{} = build, class_id, ruleset) do
    case spec(class_id, ruleset) do
      nil -> true
      %{required?: false} -> true
      %{count: count} -> build |> Build.class_choice(class_id) |> length() >= count
    end
  end

  @doc """
  Whether adding `value` to `class_id`'s choice is legal here, and if not,
  every reason why — the same "reasons, never text" contract every other
  refusal in the core keeps (CLAUDE.md §8).

  Removing a value (the other half of a chip's toggle, `Build.
  toggle_class_choice/3`) is never asked about: taking back a pick is always
  legal, the same way clearing a feat slot is.
  """
  @spec reasons(Build.t(), atom(), atom(), map()) :: [reason()]
  def reasons(%Build{} = build, class_id, value, ruleset) do
    case spec(class_id, ruleset) do
      nil ->
        [{:no_choice, class_id}]

      %{domain: domain, count: count} ->
        case domain_values(domain, ruleset) do
          :none ->
            [{:missing_data, {:choice_domain, domain}}]

          {:ok, allowed} ->
            held = Build.class_choice(build, class_id)

            # A value already held is never refused here: a second click on it
            # is `Build.toggle_class_choice/3` taking it back, not a duplicate
            # pick, and `reasons/4` is asked before that decision is made, not
            # instead of it. So only two things can be wrong with a fresh
            # value — it does not belong to the domain, or there is no room
            # left for it.
            List.flatten([
              if(MapSet.member?(allowed, value),
                do: [],
                else: [{:invalid_class_choice, class_id, value}]
              ),
              if(value not in held and length(held) >= count,
                do: [{:class_choice_full, class_id, count}],
                else: []
              )
            ])
        end
    end
  end

  @doc "`:ok`, or every reason `reasons/4` finds."
  @spec validate(Build.t(), atom(), atom(), map()) :: :ok | {:error, [reason()]}
  def validate(%Build{} = build, class_id, value, ruleset) do
    case reasons(build, class_id, value, ruleset) do
      [] -> :ok
      reasons -> {:error, reasons}
    end
  end

  @doc """
  What a click on `value` (`class_id`'s choice) should do to the build — the
  whole meaning of the click, not just whether it is legal (задача 3.171).

    * `:toggle` — take `Build.toggle_class_choice/3` at its word: `value` is
      either already held (taking it back is always legal) or there is
      outright room for it. Either way the plain add-or-remove primitive is
      exactly right.
    * `:replace` — `value` is not held and the choice is full, but the choice
      only ever holds ONE value at a time (`count == 1` — a Wizard's school).
      A fresh click here reads as "pick this one instead", the way a radio
      button behaves, not as an over-capacity add. Dan, 02.09.2026: «в других
      местах сайта у нас можно свободно переключаться между различными
      выборами чего-либо… не блокировать другие школы, просто выделить ту что
      выбрали, с возможностью выбрать другую».
    * `{:error, reasons}` — `reasons/4`'s own answer, verbatim. Covers both
      an outright illegal value (wrong domain, no dictionary) and a full
      choice that holds MORE than one value (`count > 1`, a Cleric's two
      domains): which of several held values a fresh click should evict has
      no rule anywhere, game or ours, so a full multi-value choice stays
      refused exactly as it always has.

  This is the one place "a single-value choice behaves like a radio button"
  is written down. It costs nothing extra to know which `count` triggered
  `:replace` — `reasons/4` already carries it in the very reason tuple this
  reads (`{:class_choice_full, class_id, count}`), so there is no second
  lookup of `spec.count` to keep in step with this one.

  `Build.toggle_class_choice/3` itself is untouched and stays the plain,
  ruleset-blind primitive it always was — same reason `Build.put_feat/5`
  never learns a slot's rules. `Build.replace_class_choice/3` is its sibling
  for the one case toggling cannot express: swapping the held value outright
  rather than appending past capacity.
  """
  @spec click(Build.t(), atom(), atom(), map()) ::
          :toggle | :replace | {:error, [reason()]}
  def click(%Build{} = build, class_id, value, ruleset) do
    if value in Build.class_choice(build, class_id) do
      :toggle
    else
      case reasons(build, class_id, value, ruleset) do
        [] -> :toggle
        [{:class_choice_full, ^class_id, 1}] -> :replace
        reasons -> {:error, reasons}
      end
    end
  end

  # ⚠ Found while wiring the Wizard's `spell_school` domain in (task 3.10):
  # `universal` sat in this domain's raw dictionary all along
  # (`values: MapSet.new([..., :universal])`, `flags: %{selectable: <the
  # other eight>}`), and until now nothing here read `flags` at all — every
  # caller of `values/2` got `universal` back as an offerable pick. Harmless
  # for a Cleric's `domain` (its dictionary carries no `selectable` gate, so
  # `Map.get(flags, gate)` was always `nil` there and fell through to the
  # unfiltered set unchanged), which is exactly why `class_choices_test.exs`
  # never caught it: `spell_school` is the first domain `ClassChoices` reads
  # that actually gates a value. `FeatChoices` already carries this exact
  # rule for a feat's own parameter (`Spell focus` and kin) — reusing its
  # `domain_gate/0` rather than repeating the atom `:selectable` here is what
  # keeps the two from drifting apart the way `Rules.Prereqs.keys()` vs a
  # hand-duplicated list did in loader.ex (AGENT_QUEUE.md bug 1.2). A domain
  # with no gate (Cleric's `domain`) is unaffected: `flags` is
  # `%{}`, `Map.get(flags, gate)` is `nil`, and the raw set passes through.
  defp domain_values(domain, ruleset) do
    case Map.get(Map.get(ruleset, :choice_domains, %{}), domain) do
      %{values: %MapSet{} = values, flags: flags} ->
        gated(Map.get(flags, FeatChoices.domain_gate()) || values)

      _no_dictionary ->
        :none
    end
  end

  # An empty gate is not a set of values, the same reading `FeatChoices.
  # gated/1` gives it and for the same reason: a gate that lets nothing
  # through is a hole in the data, not a fact about the character.
  defp gated(values) do
    if Enum.empty?(values), do: :none, else: {:ok, values}
  end
end
