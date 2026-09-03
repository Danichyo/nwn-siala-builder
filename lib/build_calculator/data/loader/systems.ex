defmodule BuildCalculator.Data.Loader.Systems do
  @moduledoc """
  Кастомные системы шарда и группы классов («Воины Сагры», «Воины Адры»).

  Оба читателя берут `siala_41/systems.json`: первый — вердикт «идёт ли система
  в калькулятор вообще», второй — сам состав группы, который заявлен трижды
  и тремя файлами, поэтому и сверяется здесь (`verify_class_groups!/2`,
  `verify_stat_caps!/2`).
  """

  import BuildCalculator.Data.Loader.Reading

  alias BuildCalculator.Data.Loader.{FactReceivers, NotAGap}

  # ---------------------------------------------------------- shard systems --

  # `priv/rules/siala_41/systems.json` is not a rules file and is not read as
  # one: it records what each custom system is and, per its own README, **what
  # goes into the calculator and what does not**. Most of the ten do not reach
  # the calculator at all, and that is a closed decision (CLAUDE.md §3), so this
  # lifts the verdicts and the stats each system touches *in the game* — the
  # price of the decision, visible rather than implied.
  #
  # ⚠ This comment used to count them ("nine verdicts out of ten are not `yes`")
  # and went stale the day Dan's 08.08.2026 decision made a second system reach
  # the numbers — `sagra_warriors` picks which racial bonus variant is counted,
  # so its verdict became `partial` (10.08.2026, §7 debt). The count now lives in
  # exactly one place that is checked, `siala_skill_layer_test.exs`; repeating it
  # here is what made it wrong.
  def build_systems(:missing), do: []

  def build_systems(%{"systems" => list}) when is_list(list) do
    for system <- list do
      %{
        id: atom(system["id"]),
        ru: system["ru"],
        # The page the system is *about*, which for a group of classes is the
        # group's own name («Воины Сагры») and the key three files join on. Note
        # that `source.kind` may be `missing` — Adra's page is not in the cache
        # and may not exist — while the title is still the right name for it.
        page: dig(system, ["source", "page"]),
        summary: system["summary"],
        verdict: system["goes_into_calculator"],
        verdict_reason: system["goes_into_calculator_reason"],
        derived_stats_touched: system["derived_stats_touched"] || [],
        facts: system["facts"] || []
      }
    end
  end

  def build_systems(_other), do: []

  # ------------------------------------------------------ shard class groups --

  # «Воины Сагры» and «Воины Адры» — groups a *build* belongs to when its class
  # list lines up (`BuildCalculator.Rules.ClassGroups`). Assembled here because
  # the relation is stated **three times** in `priv/rules/siala_41/`, from three
  # directions, and no single one of them carries everything:
  #
  #   1. `classes.json` — each class page names the groups it is in, by their
  #      page titles. Seven classes; the direction that scales, and therefore the
  #      authority for *who is in a group*.
  #   2. `systems.json` — the group's own record: what it is called, whether
  #      purity is required, what it gives, plus its own copy of the class list.
  #   3. `races.json` — a third copy of Sagra's class list, because the racial
  #      bonus has a number «для персонажа-сагровика» and had to state what that
  #      means.
  #
  # ⚠ A group known only from (1) is still a group. It gets a name (the page
  # title the classes link) and nothing else, which makes both of its caveats
  # fire by themselves — «правило чистоты не описано» and «что даёт группа,
  # никто не написал». Raising instead would break the build over data that is
  # merely incomplete, and degrade in the dishonest direction is exactly what
  # this arrangement avoids.
  #
  # ⚠ What *is* fatal is disagreement, and `verify_class_groups!/2` is what makes
  # keeping three copies safe — same device and same reason as
  # `verify_stat_caps!/2` next door.
  def class_groups(systems, classes, race_layer, known_receivers) do
    by_page = Map.new(systems, fn system -> {system.page, system} end)

    classes
    |> membership_by_group()
    |> Enum.sort_by(fn {page, _ids} -> page end)
    |> Enum.map(fn {page, ids} ->
      class_group(page, ids, Map.get(by_page, page), known_receivers)
    end)
    |> merge_class_group_copies!(race_layer)
  end

  # Inverted from the class side: `%{"Воины Сагры" => MapSet<:fighter, …>}`.
  defp membership_by_group(classes) do
    Enum.reduce(classes, %{}, fn {id, class}, acc ->
      Enum.reduce(Map.get(class, :class_groups, []), acc, fn page, inner ->
        Map.update(inner, page, MapSet.new([id]), &MapSet.put(&1, id))
      end)
    end)
  end

  defp class_group(page, ids, nil, _known) do
    %{
      id: class_group_id(page),
      name: page,
      classes: ids,
      # Nothing is known beyond the membership, and the two `nil`s below are what
      # make the core say so instead of assuming Sagra's rules everywhere.
      purity_required: nil,
      benefits: nil,
      benefits_counted: [],
      # ⚠ И два пустых поля разметки — по той же причине и в ту же сторону:
      # выгода без получателя остаётся гэпом, допущение без решения владельца
      # остаётся оговоркой. Группа, про которую известно одно членство,
      # обязана говорить оба раза.
      benefit_receivers: %{},
      purity_not_a_gap: nil,
      known_from: :class_pages
    }
  end

  defp class_group(page, ids, system, known) do
    stated = system_fact(system, "classes")

    if is_list(stated) and MapSet.new(stated, &atom/1) != ids do
      raise """
      the class group #{page} is stated twice and the two disagree: \
      systems.json lists #{inspect(Enum.sort(stated))}, the class pages of \
      #{inspect(Enum.sort(MapSet.to_list(ids)))} say they belong to it
      """
    end

    %{
      id: system.id,
      name: page,
      classes: ids,
      purity_required: system_fact(system, "purity_required"),
      benefits: system_fact(system, "benefits"),
      # Which of the listed benefits the calculator does account for. Empty until
      # task 3.35, and the reason it exists is that the gap beside it says «none
      # of it» — a sentence that stopped being true the day the shard's
      # weapon-type bonus started counting (`Rules.WeaponTypeBonus`). Read off the
      # same fact as `benefits`, so the two cannot name different things.
      benefits_counted: system_fact_field(system, "benefits", "counted_by_calculator") || [],
      # And what each of them **changes** — the receiver, out of the same closed
      # vocabulary `siala_41/classes.json` declares for the facts of a class
      # (`_receivers`, task 3.28). A benefit whose every receiver is something
      # the calculator never prints is not a hole in our answer, so the caveat
      # about it goes quiet — `Rules.ClassGroups`, and the rule itself is
      # `Rules.GapReceivers`, the one place it lives.
      benefit_receivers: benefit_receivers!(page, system, known),
      # The owner's decision that the missing purity rule is not a gap
      # (`not_a_gap`, task 3.74's device). ⚠ Read off the `purity_required`
      # fact and **not** turned into a `purity_required: true`: the assumption
      # stays an assumption, and only the confession moves.
      purity_not_a_gap: purity_not_a_gap!(page, system),
      known_from: :group_page
    }
  end

  # `affects_by_benefit` — a receiver per line of `benefits`, keyed by the line
  # itself. Two things raise rather than degrade quietly, both of them failing
  # towards **showing** the caveat:
  #
  #   * a key that names no benefit. A renamed line would otherwise keep a label
  #     that labels nothing, and the renamed benefit would silently go
  #     unlabelled — i.e. would silently start being a gap again (harmless) while
  #     the stale key claims otherwise (not harmless: it reads as done work).
  #   * a receiver outside the vocabulary, checked by the same
  #     `verify_bonus_affects!/4` the six markup files use. A typo would
  #     otherwise quietly mean "not ours", i.e. "do not show".
  #
  # ⚠ A benefit with no key here is **not** an error: no label means "still a
  # gap", exactly as it does for a class fact.
  defp benefit_receivers!(page, system, known) do
    labels = system_fact_field(system, "benefits", "affects_by_benefit")
    benefits = system_fact(system, "benefits") || []

    case labels do
      nil ->
        %{}

      %{} = labels ->
        stray = Map.keys(labels) -- benefits

        if stray != [] do
          raise """
          siala_41/systems.json: #{page} labels #{inspect(stray)} in affects_by_benefit, \
          and its benefits are #{inspect(benefits)} — a label that names no benefit labels \
          nothing, and the benefit it used to name is silently unlabelled
          """
        end

        for {benefit, receivers} <- labels, into: %{} do
          FactReceivers.verify_bonus_affects!(
            "siala_41/systems.json: #{page}",
            benefit,
            receivers,
            known
          )

          {benefit, receivers}
        end

      other ->
        raise """
        siala_41/systems.json: #{page} carries affects_by_benefit: #{inspect(other)}. \
        Expected an object keyed by the benefit it labels.
        """
    end
  end

  # ⚠ Сторож общий (`Loader.NotAGap`, задача 3.95) — пятое семейство данных,
  # несущее это поле. Словаря доводов (`bases:`) здесь не объявлено по той же
  # причине, что у фактов класса и у оружия: проверяемый довод
  # `feat_description` стоит на описании ФИТА, а у группы классов фита нет.
  defp purity_not_a_gap!(page, system) do
    decision = system_fact_field(system, "purity_required", "not_a_gap")

    NotAGap.verify!("siala_41/systems.json: #{page} · purity_required", decision)

    if is_map(decision), do: decision
  end

  # A group with no record of its own still needs an id, and the only thing it
  # has is a Russian page title — so the id is derived from the title and marked
  # as such. `slug/1` strips everything non-ASCII, which for a Cyrillic title
  # leaves nothing, so the title is kept verbatim inside a `:group_` atom rather
  # than silently collapsing to one id for every such group.
  defp class_group_id(page), do: atom("group_" <> page)

  # One fact of one system, by name. Shared by every reader of
  # `siala_41/systems.json` — the class groups, the weapon system — because the
  # file has one shape and two readings of it would drift.
  def system_fact(system, what) do
    Enum.find_value(system.facts, fn fact -> fact["what"] == what && fact["value"] end)
  end

  @doc """
  `status` того же факта — «цитата это или чтение».

  Публично, потому что читатель у него не один: ядро печатает оговорку у
  прочитанного и молчит у процитированного, и решать это должен статус самого
  факта, а не второй флаг рядом с ним.
  """
  @spec system_fact_status(map(), String.t()) :: String.t() | nil
  def system_fact_status(system, what), do: system_fact_field(system, what, "status")

  @doc """
  Поле факта РЯДОМ с его `value` — для тех немногих утверждений, которые факт
  несёт **о** своём значении, а не внутри него.

  Публично с 28.08.2026 (задача 3.132): отметка о подтверждении
  (`same_kind_confirmed`) — ровно такое утверждение, и читает её `Loader.Races`,
  а не этот модуль.
  """
  @spec system_fact_field(map(), String.t(), String.t()) :: term()
  def system_fact_field(system, what, field) do
    Enum.find_value(system.facts, fn fact -> fact["what"] == what && fact[field] end)
  end

  # The third copy: `races.json` states Sagra's class list and its purity rule
  # again, because the racial bonus has a variant «для персонажа-сагровика» and
  # the file had to say what that means. Joined to the group **by the wiki page
  # both cite**, which is the only key the two files share — the keys differ
  # (`sagra_warrior` against `sagra_warriors`) and matching by the class list
  # itself would be circular.
  #
  # Two things happen here, and they are the same thing seen from two sides:
  # a copy that says something the group does not is **adopted**, and a copy that
  # contradicts it **fails the build**. Keeping three copies of one fact is only
  # safe with the second half.
  defp merge_class_group_copies!(groups, race_layer) do
    copies = class_group_conditions(race_layer)

    for {key, entry} <- copies,
        do: verify_class_group_copy!(key, entry, find_group!(groups, key, entry))

    Enum.map(groups, fn group ->
      case Enum.find_value(copies, fn {_key, entry} ->
             dig(entry, ["source", "page"]) == group.name && entry
           end) do
        nil -> group
        entry -> adopt_class_group_copy(group, entry)
      end
    end)
  end

  defp find_group!(groups, key, entry) do
    page = dig(entry, ["source", "page"])

    Enum.find(groups, &(&1.name == page)) ||
      raise """
      races.json's #{key} cites the page #{inspect(page)} as a group of classes, \
      and no class page says it belongs to it — the condition would silently \
      never hold
      """
  end

  defp verify_class_group_copy!(key, entry, group) do
    stated = MapSet.new(entry["classes"] || [], &atom/1)
    purity = entry["purity_required"]

    cond do
      stated != group.classes ->
        raise """
        the class list of #{group.name} disagrees between two files: races.json's \
        #{key} says #{inspect(Enum.sort(MapSet.to_list(stated)))}, the group itself \
        says #{inspect(Enum.sort(MapSet.to_list(group.classes)))}
        """

      is_boolean(group.purity_required) and is_boolean(purity) and
          purity != group.purity_required ->
        raise """
        the purity rule of #{group.name} disagrees between two files: races.json's \
        #{key} says #{inspect(purity)}, the group itself says \
        #{inspect(group.purity_required)}
        """

      true ->
        :ok
    end
  end

  # A fact stated by the copy and not by the group's own record is still a fact
  # about the group — so it is taken, not dropped. Only ever fills a `nil`,
  # because the contradiction case has already raised above.
  defp adopt_class_group_copy(%{purity_required: nil} = group, entry) do
    case entry["purity_required"] do
      stated when is_boolean(stated) -> %{group | purity_required: stated}
      _unstated -> group
    end
  end

  defp adopt_class_group_copy(group, _entry), do: group

  # Top-level entries of `races.json` that state a class list: a condition one of
  # the racial bonus's four numbers is stated for. Found by shape rather than by
  # name — there is one today (`sagra_warrior`) and its key is spelled exactly
  # like the variant it belongs to, which is what links the two (see
  # `racial_bonus_variant_conditions/2`).
  def class_group_conditions(:missing), do: %{}

  def class_group_conditions(%{} = layer) do
    for {key, entry} <- layer,
        is_map(entry),
        is_list(entry["classes"]),
        into: %{},
        do: {key, entry}
  end

  def class_group_conditions(_other), do: %{}

  # The ceilings are stated twice — as prose for a human in `systems.json` and as
  # numbers for the core in `overrides.json` — and the second is explicitly a
  # transcription of the first. Two copies drift; this fails the build the day
  # they do, which is the only reason keeping both is safe.
  def verify_stat_caps!(systems, ov) do
    # `systems.json` names a fact after the ceiling ("attack_bonus_cap"),
    # `overrides.json` after the stat ("attack_bonus"). One suffix apart.
    stated =
      case Enum.find(systems, &(&1.id == :stat_caps)) do
        nil ->
          %{}

        system ->
          Map.new(system.facts, fn fact ->
            {String.replace_suffix(fact["what"], "_cap", ""), fact["value"]}
          end)
      end

    for {key, value} <- stated, is_integer(value) do
      case dig(ov, ["stat_caps", key, "value"]) do
        nil ->
          raise """
          systems.json states the ceiling #{key} = #{value}, and overrides.json has \
          no machine-readable entry for it — the core would silently not apply it
          """

        ^value ->
          :ok

        other ->
          raise """
          the two statements of the ceiling #{key} disagree: systems.json says \
          #{value}, overrides.json says #{other}
          """
      end
    end

    :ok
  end
end
