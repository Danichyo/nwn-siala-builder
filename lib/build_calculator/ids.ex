defmodule BuildCalculator.Ids do
  @moduledoc """
  Resolving ids that arrived from outside — a click payload or a shared link.

  Everything the browser sends is a string, and `String.to_atom/1` on it would
  leak the atom table (AGENTS.md). So a string only ever becomes an atom by
  being *found* in the ruleset: the dictionaries in `BuildCalculator.Data` are
  the whitelist, and anything not in them is simply `:error`.

  Alignments are the one list that is not in the data. They are not game numbers
  but the closed vocabulary the rules core already assumes: `Rules.LevelUp`
  matches a requirement against the words of the alignment atom, so the nine
  atoms below are exactly what it can read.
  """

  @alignments [
    {:lawful_good, "Lawful Good"},
    {:neutral_good, "Neutral Good"},
    {:chaotic_good, "Chaotic Good"},
    {:lawful_neutral, "Lawful Neutral"},
    {:true_neutral, "True Neutral"},
    {:chaotic_neutral, "Chaotic Neutral"},
    {:lawful_evil, "Lawful Evil"},
    {:neutral_evil, "Neutral Evil"},
    {:chaotic_evil, "Chaotic Evil"}
  ]

  @doc "The nine alignments as `{id, english_name}`, in the canonical 3x3 order."
  @spec alignments() :: [{atom(), String.t()}]
  def alignments, do: @alignments

  @doc "English name of an alignment, or `nil`."
  @spec alignment_name(atom() | nil) :: String.t() | nil
  def alignment_name(nil), do: nil

  def alignment_name(id) do
    case List.keyfind(@alignments, id, 0) do
      {^id, name} -> name
      nil -> nil
    end
  end

  @doc """
  Resolves a string id against one of the ruleset's dictionaries.

  `kind` is `:classes`, `:races`, `:feats`, `:skills`, `:spells`, `:weapons`,
  `:abilities`, `:ac_types` or `:alignments`. Returns `{:ok, atom}` or `:error` —
  never raises, never invents an atom.
  """
  @spec fetch(map(), atom(), term()) :: {:ok, atom()} | :error
  def fetch(_ruleset, _kind, value) when not is_binary(value), do: :error

  def fetch(_ruleset, :alignments, value) do
    find(Enum.map(@alignments, &elem(&1, 0)), value)
  end

  def fetch(ruleset, :abilities, value), do: find(ruleset.abilities, value)
  def fetch(ruleset, :ac_types, value), do: find(ruleset.gear.ac_types, value)

  def fetch(ruleset, kind, value)
      when kind in [:classes, :races, :feats, :skills, :spells, :weapons] do
    ruleset |> Map.fetch!(kind) |> Map.keys() |> find(value)
  end

  @doc "Like `fetch/3` but returns `nil` when the id is unknown."
  @spec get(map(), atom(), term()) :: atom() | nil
  def get(ruleset, kind, value) do
    case fetch(ruleset, kind, value) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  @doc """
  Resolves a worn item — the pair `{category, item}` — against the ruleset.

  Two halves and **both** are whitelisted, against different lists: the category
  among those the ruleset declares (`ruleset.gear.worn`), the item among the
  items of *that* category rather than of any. A pair that names a real category
  and a real item of another one is `:error`, or a hand-edited link could put
  full plate in the shield slot and collect its base twice.

  Returns `{:ok, category_id, item_id}` or `:error` — the same "found, never
  invented" rule `fetch/3` follows, for the same reason (AGENTS.md: no
  `String.to_atom/1` on anything from outside).
  """
  @spec fetch_worn(map(), term(), term()) :: {:ok, atom(), atom()} | :error
  def fetch_worn(_ruleset, category, item)
      when not is_binary(category) or not is_binary(item),
      do: :error

  def fetch_worn(ruleset, category, item) do
    with {:ok, id} <- find(Enum.map(worn(ruleset), & &1.id), category),
         %{items: items} <- Enum.find(worn(ruleset), &(&1.id == id)),
         {:ok, item_id} <- find(Enum.map(items, & &1.id), item) do
      {:ok, id, item_id}
    else
      _no -> :error
    end
  end

  defp worn(ruleset), do: Map.get(ruleset.gear, :worn) || []

  @doc """
  Resolves the value a feat is taken **with** — a school, a creature type, a skill.

  Same whitelist rule as `fetch/3` and for the same reason: the string arrives
  from a click, and `String.to_atom/1` on it would leak the atom table
  (AGENTS.md). The list it is checked against is the domain's own dictionary,
  looked up through the feat — so a value legal for one feat cannot be smuggled
  into another whose domain is different.

  ⚠️ This says the value **exists**, never that the pick is legal. Whether this
  feat may take this value here is `Rules.validate_feat_pick/3`, and the two are
  different questions: `evocation` is a real school even for a character who has
  no `Spell focus` in it.
  """
  @spec fetch_choice(map(), atom(), term()) :: {:ok, atom()} | :error
  def fetch_choice(_ruleset, _feat_id, value) when not is_binary(value), do: :error

  def fetch_choice(ruleset, feat_id, value) do
    with domain when not is_nil(domain) <-
           BuildCalculator.Rules.feat_choice_domain(feat_id, ruleset),
         %{values: %MapSet{} = values} <- Map.get(ruleset.choice_domains || %{}, domain) do
      find(values, value)
    else
      _no_dictionary -> :error
    end
  end

  @doc """
  Resolves the value a CLASS's own choice is taken with — a Cleric domain.

  Same whitelist rule as `fetch_choice/3` and for the same reason (a click
  payload is a string, and `String.to_atom/1` on it would leak the atom
  table). The domain comes from `BuildCalculator.Rules.ClassChoices.domain/2`
  rather than a feat's `repeatable.choice`, but both read the value out of the
  same `ruleset.choice_domains` table, so a Cleric's domain and a feat's
  parameter are resolved by one mechanism (AGENT_QUEUE.md §3.14).
  """
  @spec fetch_class_choice(map(), atom(), term()) :: {:ok, atom()} | :error
  def fetch_class_choice(_ruleset, _class_id, value) when not is_binary(value), do: :error

  def fetch_class_choice(ruleset, class_id, value) do
    with domain when not is_nil(domain) <-
           BuildCalculator.Rules.ClassChoices.domain(class_id, ruleset),
         %{values: %MapSet{} = values} <- Map.get(ruleset.choice_domains || %{}, domain) do
      find(values, value)
    else
      _no_dictionary -> :error
    end
  end

  @doc """
  Parses a feat slot id back out of its DOM-safe string form.

  Slot ids are `:general`, `:racial`, `{:class_bonus, class}` or
  `{:class_bonus, class, index}` — the tuple has to survive a round trip through
  an HTML attribute, so it travels as `"class_bonus:fighter"` (or
  `"class_bonus:ranger:2"`) and the class half is whitelisted like everything
  else.

  ⚠ The index half is **not** whitelisted against anything, and cannot be: it is
  a position within one level, not a game id. It is read as a positive integer
  and nothing else — a string that is not one is `:error` rather than an atom
  built out of whatever the client sent, the same rule
  `fetch_spell_slot/1` follows for the same reason. Whether the level actually
  grants a second slot is a rules question and stays with `Rules.FeatSlots`: this
  says the string names a slot shape, never that the slot exists.
  """
  @spec fetch_slot(map(), term()) ::
          {:ok, atom() | {:class_bonus, atom()} | {:class_bonus, atom(), pos_integer()}} | :error
  def fetch_slot(_ruleset, value) when not is_binary(value), do: :error
  def fetch_slot(_ruleset, "general"), do: {:ok, :general}
  def fetch_slot(_ruleset, "racial"), do: {:ok, :racial}

  def fetch_slot(ruleset, "class_bonus:" <> rest) do
    # Class ids are `[a-z0-9_]`, so the colon can only be the index separator.
    case String.split(rest, ":") do
      [class] -> class_bonus(ruleset, class)
      [class, index] -> class_bonus(ruleset, class, index)
      _more -> :error
    end
  end

  def fetch_slot(_ruleset, _value), do: :error

  defp class_bonus(ruleset, class) do
    case fetch(ruleset, :classes, class) do
      {:ok, id} -> {:ok, {:class_bonus, id}}
      :error -> :error
    end
  end

  # ⚠ `"1"` is refused rather than folded onto the un-indexed shape. One slot has
  # exactly one name — the shape `slot_key/1` writes — and accepting a second
  # spelling of it would mean two strings addressing one entry of
  # `build.feats[level]`, which is how a pick gets written twice and read once.
  defp class_bonus(ruleset, class, index) do
    with {index, ""} when index > 1 <- Integer.parse(index),
         {:ok, id} <- fetch(ruleset, :classes, class) do
      {:ok, {:class_bonus, id, index}}
    else
      _no -> :error
    end
  end

  @doc """
  The DOM-safe string form of a slot id — the inverse of `fetch_slot/2`.

  ⚠ Refuses anything `t:BuildCalculator.Rules.Build.slot_id/0` does not name.
  Until 11.08.2026 the second clause matched on bare `is_atom(id)`, which let
  through *any* atom, not only `:general` and `:racial` — so an invented shape
  such as a bare `:epic_general` (a real form found living in a test fixture,
  AGENT_QUEUE.md §7) produced a string here without error, one `fetch_slot/2`
  then could not parse back, and the pick it named vanished on the next decode
  as an unremarkable `{:unknown_slot, "epic_general"}` — a silent round-trip
  failure, not a crash. A 2-tuple that was not `{:class_bonus, _}` already
  raised (no clause matched it at all); this only widens the same refusal to
  the bare-atom half of the type and gives it a message naming what arrived,
  in place of an opaque `FunctionClauseError`.

  ⚠ A second class bonus slot on the same level writes its index
  (`"class_bonus:ranger:2"`), and the **first** one deliberately does not: that
  string is what every already-shared link spells, and renaming it would drop the
  pick it names on the next decode. Hence `index > 1` in the guard — the
  un-indexed shape is slot one, and there is no second way to write it.
  """
  @spec slot_key(atom() | {:class_bonus, atom()} | {:class_bonus, atom(), pos_integer()}) ::
          String.t()
  def slot_key({:class_bonus, class}) when is_atom(class),
    do: "class_bonus:" <> Atom.to_string(class)

  def slot_key({:class_bonus, class, index})
      when is_atom(class) and is_integer(index) and index > 1,
      do: "class_bonus:" <> Atom.to_string(class) <> ":" <> Integer.to_string(index)

  def slot_key(id) when id in [:general, :racial], do: Atom.to_string(id)

  def slot_key(other) do
    raise ArgumentError,
          "not a slot id: #{inspect(other)} — Build.slot_id/0 names only " <>
            ":general, :racial, {:class_bonus, class} or {:class_bonus, class, index > 1}"
  end

  @doc "A DOM id fragment: the slot key with the colon swapped for a dash."
  @spec slot_dom_id(atom() | {:class_bonus, atom()} | {:class_bonus, atom(), pos_integer()}) ::
          String.t()
  def slot_dom_id(id), do: id |> slot_key() |> String.replace(":", "-")

  @doc """
  Parses a spell slot id out of a form parameter.

  A spell slot is `{:circle, circle, index}` — pure integers, so unlike class ids
  there is nothing to whitelist against the ruleset. The bounds are still checked:
  the circle is 0..9 in every caster table we have, and the index is the position
  within that circle at one level, which never runs high. Anything else is `:error`
  rather than a tuple built out of whatever the client sent.
  """
  @spec fetch_spell_slot(term()) ::
          {:ok, {:circle, non_neg_integer(), non_neg_integer()}} | :error
  def fetch_spell_slot(value) when not is_binary(value), do: :error

  def fetch_spell_slot("circle:" <> rest) do
    with [circle, index] <- String.split(rest, ":"),
         {c, ""} when c in 0..9 <- Integer.parse(circle),
         {i, ""} when i in 0..15 <- Integer.parse(index) do
      {:ok, {:circle, c, i}}
    else
      _ -> :error
    end
  end

  def fetch_spell_slot(_value), do: :error

  @doc "The string form of a spell slot id — the inverse of `fetch_spell_slot/1`."
  @spec spell_slot_key({:circle, non_neg_integer(), non_neg_integer()}) :: String.t()
  def spell_slot_key({:circle, circle, index}), do: "circle:#{circle}:#{index}"

  @doc "A DOM id fragment for a spell slot: colons swapped for dashes."
  @spec spell_slot_dom_id({:circle, non_neg_integer(), non_neg_integer()}) :: String.t()
  def spell_slot_dom_id(id), do: id |> spell_slot_key() |> String.replace(":", "-")

  defp find(ids, value) do
    Enum.find_value(ids, :error, fn id ->
      if Atom.to_string(id) == value, do: {:ok, id}
    end)
  end
end
