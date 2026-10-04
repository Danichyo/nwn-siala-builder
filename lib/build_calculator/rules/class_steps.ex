defmodule BuildCalculator.Rules.ClassSteps do
  @moduledoc """
  Which feat a class **raises a step of** on a level — the tables «by class level»
  of the bonus markup, asked the question the class's grant list cannot answer
  (task 4.40, item 6).

  A class hands a feat over in two ways, and the data keeps them apart. The grant
  list (`classes.*.granted_feats`, Fandom's «Feats» column) names a feat on the
  levels the page prints it; the markup files carry the feat's **effect** as a
  table of class level → value (`Bonuses.total_at_step/2`), and a table may step
  up on a level the grant list says nothing about:

    * `Enchant arrow` — granted once, at Arcane archer 1; its attack bonus grows
      on every odd class level (`vanilla/feat_attack_bonuses.json`, read off
      `cls_feat_archer.2da` since task 4.26). In the game each step is a feat of
      its own (`FEAT_PRESTIGE_ENCHANT_ARROW_2` … `_20`), and the builder's «the
      class gives by itself» line named none of them past the first;
    * `Draconic armor` — granted at Red dragon disciple 1, the natural armour
      grows at 5, 8, 10 and every five levels after;
    * `Dragon abilities` — granted at 2, the ability gains of 4, 7, 9 and 10.

  `at/3` answers with the core's own reading of the same tables the numbers are
  computed from, so the line and the number cannot disagree.

  ## A column of the class, not of a feat

  The Weapon master's «AB bonus» column is a record named by the **class**
  (`source: {:class, :weapon_master}`): the column is the sum of `Superior weapon
  focus` and every step of `Epic superior weapon focus`, and the record says so
  only in prose. The grant list names the feat on each step through class level
  28 (Fandom's table ends at 30). Siala's step at 31 (decision `BC1`, task 4.46)
  has no grant beside it, and so the line named nothing at Weapon master 31.

  Such a step is named after the feat the grant list names on the **two steps of
  the same table right before it**, with the rank the list gives it there — and
  only when the class grants nothing at all on the level itself (a grant there
  may be what the step is about, and which one would be a guess). Weapon master 31:
  steps 25 and 28 both grant `Epic superior weapon focus` «(+1 AB)», level 31
  grants nothing — the line reads `Epic superior weapon focus (+1 AB)`, as on 13
  through 28. The other class column, the Monk's armour class, never qualifies:
  no feat is granted on two of its steps in a row, so it is named by nothing,
  which is what it was before.

  ## What is not here

  The value of a step is not invented: a table past its last step adds nothing
  (`Bonuses.total_at_step/2`), and no step is answered for a class level the table
  does not list. Only records the numbers count (`applied`) are read.
  """

  alias BuildCalculator.Rules.{Bonuses, Build}

  # The markup files whose records may carry a table by class level, and the
  # shape each table has (`Data.Loader.Bonuses`). Attack, armour class and saves
  # state TOTALS; ability tables state GAINS, summed (`Rules.AbilityBonuses`).
  @tables [
    {:attack_bonuses, :attack_at_class_level, :total},
    {:ac_bonuses, :ac_at_class_level, :total},
    {:save_bonuses, :save_at_class_level, :total},
    {:ability_bonuses, :ability_at_class_level, :gains}
  ]

  @typedoc """
  One step a class reaches on a level:

    * `{:total, n}` — the feat's table now stands at `n` (attack, AC, a save);
    * `{:gains, %{ability => n}}` — the abilities this step adds;
    * `{:rank, text}` — a class column continuing a feat the grant list named on
      the steps before, with the rank text the list gives it (see the moduledoc).
  """
  @type step :: %{feat: atom(), step: {:total, integer()} | {:gains, map()} | {:rank, String.t()}}

  @doc """
  The steps the class of `level` reaches on it, one per feat, in the order of the
  markup files. `[]` on a level with no class (past the end of the ladder) and on
  a level no table steps on.

  A feat the class also grants on that very level is still listed — whether to
  say it twice is the caller's question (the grant list already names it, with
  the page's own rank).
  """
  @spec at(Build.t(), map(), pos_integer()) :: [step()]
  def at(%Build{} = build, ruleset, level) do
    with class when not is_nil(class) <- Build.class_at(build, level),
         class_level when is_integer(class_level) <- Build.class_level_at(build, level) do
      for {markup, kind, shape} <- @tables,
          record <- Bonuses.applied(ruleset, markup),
          %{kind: ^kind, class: ^class} = amount <- [record.amount],
          step = step(record, amount, shape, ruleset, class, class_level),
          step != nil,
          uniq: true,
          do: step
    else
      _ -> []
    end
  end

  defp step(%{source: {:feat, feat}}, amount, :total, _ruleset, _class, class_level) do
    case Map.fetch(table(amount), class_level) do
      {:ok, total} -> %{feat: feat, step: {:total, total}}
      :error -> nil
    end
  end

  defp step(%{source: {:feat, feat}}, amount, :gains, _ruleset, _class, class_level) do
    case Map.fetch(amount.gains_at_class_level, class_level) do
      {:ok, gains} when map_size(gains) > 0 -> %{feat: feat, step: {:gains, gains}}
      _ -> nil
    end
  end

  defp step(%{source: {:class, class}}, amount, :total, ruleset, class, class_level) do
    steps = amount |> table() |> Map.keys() |> Enum.sort()

    if class_level in steps, do: continued(ruleset, class, steps, class_level)
  end

  defp step(_record, _amount, _shape, _ruleset, _class, _class_level), do: nil

  defp table(%{kind: :attack_at_class_level} = amount), do: amount.attack_at_class_level
  defp table(%{kind: :ac_at_class_level} = amount), do: amount.ac_at_class_level
  defp table(%{kind: :save_at_class_level} = amount), do: amount.save_at_class_level

  # The feat a class column continues on `class_level` — see the moduledoc.
  defp continued(ruleset, class, steps, class_level) do
    %{granted_feats: grants} = definition = Map.fetch!(ruleset.classes, class)
    ranks = Map.get(definition, :granted_feat_ranks, %{})

    with [] <- Map.get(grants, class_level, []),
         [_, _] = before <- steps |> Enum.filter(&(&1 < class_level)) |> Enum.take(-2),
         [feat] <- before |> Enum.map(&MapSet.new(Map.get(grants, &1, []))) |> common(),
         rank when is_binary(rank) <- get_in(ranks, [List.last(before), feat]) do
      %{feat: feat, step: {:rank, rank}}
    else
      _ -> nil
    end
  end

  defp common([a, b]), do: a |> MapSet.intersection(b) |> MapSet.to_list()
end
