defmodule BuildCalculator.Rules.ClassGroups do
  @moduledoc """
  The shard's own groupings of classes — «Воины Сагры», «Воины Адры» — and
  whether **this build** belongs to one.

  A group is not a faction a character joins and not a property of a class
  level: it is a property of the **whole class list**.

  > «Чистые классы воинов Сагры (также комбинации эти классов) получают
  > покровительство бога; любой другой класс в билде нивелирует преимущества»
  > (`Воины Сагры`, revid 19232, `verified`)

  So `Fighter 40 / Bard 1` is not a warrior of Sagra, while `Barbarian 2 /
  Fighter 10 / Weapon Master 28` is — and that is decidable from `build.levels`
  alone, which is why it lives here rather than in `Rules.RacialBonus`, where the
  first version of it sat. A race has nothing to do with it; the racial bonus is
  merely the first number the answer moves.

  ## Why the core answers this at all

  Nine of the shard's ten custom systems do not reach a build's numbers
  (CLAUDE.md §3), and Sagra's benefits are mostly consumables and weapon
  multipliers — the armoury's business. Two things make membership worth
  computing anyway:

    * **it moves a number we already show.** Every racial bonus in
      `siala_41/races.json` states four values, and one of them is «для
      персонажа-сагровика»: a Half-elf's attack bonus is +6 for anybody and +9
      for a warrior of Sagra. Dan, 08.08.2026: «сагровик получит больше бонусов,
      чем несагровик» — so the bigger number is counted, and the class list is
      what decides it (`Rules.RacialBonus`).
    * **players think in these terms.** `siala_41/systems.json` says so in the
      file itself: «сама принадлежность к группе — чисто функция состава билда,
      и её калькулятор вычисляет тривиально; показать флажок „это сагровик“
      дёшево и полезно».

  ## No group is named here

  Which groups exist, which classes are in them, whether purity is required and
  what the group gives is all data (`ruleset.class_groups`, assembled by
  `BuildCalculator.Data.Loader` out of three independent statements in
  `priv/rules/siala_41/`). This module decides only *how* to read a group, and it
  has exactly two rules: membership needs every level (or any level, where the
  data says purity is not required), and an empty ladder is a member of nothing.

  ⚠ **The two groups do not have equally good data, and that difference must not
  be erased.** Sagra's purity rule is quoted above, `verified`. Adra has **no
  page of its own**: the group is known only because four class pages say «входит
  в группу воинов Адры», and nobody wrote down whether purity is required.
  Applying Sagra's rule to Adra is an assumption — narrowing, which is the safe
  direction for a claim — and the flag says so (`purity_stated?`, and the caption
  built on it).

  ⚠ **Что Адра даёт — сказал ВЛАДЕЛЕЦ, а не вики** (Dan, 25.08.2026, задача
  3.100): «Эта принадлежность позволяет пить зелья адры, которые мы не
  моделируем, считай баффы». Здесь стояло «`what_the_group_gives` is `null` /
  `unclear`… **Nothing here or in the interface may hint at what Adra gives**:
  no source says» — первая половина по-прежнему верна про ВИКИ (страницы у
  группы нет, факт `what_the_group_gives` не тронут), вторая пересмотрена в
  одном: источник появился, и это `kind: user`. Запрет на догадку остаётся в
  силе для всего, чего Dan не называл: зелья и только зелья.

  ⚠ **Оговорок у групп сегодня нет ни одной, и это снятое ПРИЗНАНИЕ, а не
  снятый механизм** — см. `gaps/2`, где расписаны все три молчания и то, что
  вернёт каждое из них.
  """

  alias BuildCalculator.Rules.{Build, GapReceivers}

  @typedoc """
  A group as the data states it.

    * `id` — `:sagra_warriors`
    * `name` — the group's own name, i.e. its wiki page title («Воины Сагры»)
    * `classes` — every class the group is made of
    * `purity_required` — `true`, `false`, or `nil` when no page says
    * `benefits` — what membership gives, as the source lists it, or `nil` when
      nobody wrote it down. Never interpreted here: it is prose either way
    * `benefits_counted` — which of those the calculator does account for, as the
      data marks them. ⚠ Not a reading made here: the gap beside it says «none of
      it», and that sentence stopped being true when the shard's weapon-type
      bonus started counting (task 3.35, `Rules.WeaponTypeBonus`), so what is
      counted has to be stated where the list itself is
    * `benefit_receivers` — and what each benefit **changes**, keyed by the
      benefit line: `%{"зелья Сагры" => ["custom_items", "buff"]}`, out of the
      one closed vocabulary the shard layer declares (`Rules.GapReceivers`).
      An unlabelled benefit is not an error and means "still a gap"
    * `purity_not_a_gap` — the owner's decision that an **unwritten** purity rule
      is not a hole in our answer, with author, quote and reason
      (`Loader.NotAGap`). ⚠ Not the same thing as `purity_required`: the
      assumption is unchanged, only the confession moves
    * `known_from` — `:group_page` when the group has a record of its own,
      `:class_pages` when all we have is the classes saying they belong to it
  """
  @type group :: %{
          id: atom(),
          name: String.t() | nil,
          classes: MapSet.t(atom()),
          purity_required: boolean() | nil,
          benefits: [String.t()] | nil,
          benefits_counted: [String.t()],
          benefit_receivers: %{String.t() => [String.t()]},
          purity_not_a_gap: map() | nil,
          known_from: :group_page | :class_pages
        }

  @typedoc """
  One group this build belongs to, with everything the caption needs.

  `classes` is a sorted list rather than the group's `MapSet`, because the only
  thing a caller does with it is name the classes — and it has to name them in a
  stable order.

  `purity_stated?` is the honest half of `purity_required?`: both are `true` for
  Sagra, and for Adra the first is `true` **because we assumed it**. A caller that
  shows the flag without that distinction is showing two different qualities of
  fact as one.

  ⚠ `benefit_receivers` and `purity_not_a_gap` ride along unchanged from the
  group, and no caption reads either: they are what `gaps/2` asks about, and
  `gaps/2` is handed memberships rather than groups (it answers **about this
  build**, and only a membership knows which groups those are). Handing over the
  whole decision rather than a boolean is deliberate — a boolean would be this
  module's own reading of somebody else's record, i.e. the second copy of a rule
  that `Loader.NotAGap` exists to prevent.
  """
  @type membership :: %{
          id: atom(),
          name: String.t() | nil,
          classes: [atom()],
          purity_required?: boolean(),
          purity_stated?: boolean(),
          purity_not_a_gap: map() | nil,
          benefits: [String.t()] | nil,
          benefits_counted: [String.t()],
          benefits_uncounted: [String.t()],
          benefit_receivers: %{String.t() => [String.t()]}
        }

  @doc """
  Every group the ruleset carries, in a stable order — `[]` for vanilla, which
  has no such thing at all.
  """
  @spec all(map()) :: [group()]
  def all(ruleset) do
    ruleset |> Map.get(:class_groups) |> List.wrap() |> Enum.sort_by(& &1.id)
  end

  @doc """
  Every group this build belongs to.

  `[]` for an empty ladder, for a build whose classes do not line up with any
  group, and for the vanilla ruleset. ⚠ A build can be in **two** groups at once
  and that is the ordinary case rather than a corner one: `Fighter` is the one
  class in both lists («Воин не изменился в своей основе, но входит в группу
  классов воинов Сагры и воинов Адры», `Воин`, revid 16725), so a pure Fighter
  build is a warrior of Sagra **and** of Adra.
  """
  @spec of(Build.t(), map()) :: [membership()]
  def of(%Build{} = build, ruleset) do
    for group <- all(ruleset), belongs?(build, group), do: membership(group)
  end

  @doc """
  Whether this build belongs to the group named by `id`.

  An unknown id is `false` rather than an error: asking about a group a ruleset
  does not carry is exactly what the vanilla ruleset does to every caller.
  """
  @spec member?(Build.t(), map(), atom()) :: boolean()
  def member?(%Build{} = build, ruleset, id) do
    case Enum.find(all(ruleset), &(&1.id == id)) do
      nil -> false
      group -> belongs?(build, group)
    end
  end

  @doc """
  What is unknown about the groups **this build is in** — never about the others.

  Two questions, so up to two gaps per group, and they are not two halves of one
  statement:

    * `{:assumed, {:class_group_purity, id}}` — no page says whether one level of
      an outside class cancels membership, and we assumed it does.
    * `{:missing_data, {:class_group_benefits, id}}` — nobody wrote down what
      membership gives.
    * `{:not_modelled, {:class_group_benefits, id}}` — the source lists what it
      gives and the calculator carries **some** of it: Sagra's potions and
      whetstone are consumables and stay out, while «усиленный бонус от оружия»
      has been counted since task 3.35 (`Rules.WeaponTypeBonus`). ⚠ Until then
      this form meant "none of it", and leaving it worded that way would be
      printing «не считаем» about something counted — exactly what CLAUDE.md §6
      forbids in the other direction too. Which lines are counted is data
      (`benefits_counted`), and a group with nothing left over gets no caveat.

  🔴 **Сегодня ни один билд не получает ни одной из трёх** — на обоих ruleset'ах,
  проверено прогоном (задача 3.100, 25.08.2026). Формы при этом живы и обязаны
  быть живы: снято ПРИЗНАНИЕ, а не механизм, и каждое из трёх молчаний вернётся
  само, потому что каждое стоит на записи в данных, а не на флаге в коде:

    * выгода **без** `affects` снова становится гэпом — это `ours?/2`, а не
      здешнее правило;
    * выгода, чей получатель окажется нашим (день армори: `custom_items`
      переезжает в `our`), возвращает `{:not_modelled, …}` одной строкой словаря;
    * группа без `not_a_gap` у `purity_required` возвращает `{:assumed, …}`.

  Форма без носителя — не фикция; фикция — форма без механизма (CLAUDE.md §9).
  Поэтому механизм проверяется **синтетическим** ruleset'ом в
  `class_groups_test.exs`, а не живой записью: живая запись назавтра получает
  правку данных и молча перестаёт что-либо проверять.

  ⚠ Scoped to membership on purpose. A build with one Monk level is not called a
  warrior of Adra by us, so a caveat about Adra's rules there would fire on
  almost every martial build and teach the reader to skim the list — the shape of
  noise `Rules.ArmorClass`'s `gear_base/1` and `Rules.RacialBonus.gaps/2` both
  avoid. ⚠ The cost is stated once here and not hidden: **if Adra turns out not
  to require purity, we withhold its flag from builds that should have it.** That
  is a missing flag rather than a wrong number, and it is the direction the whole
  core errs in (HANDOFF, «контракт из двух половин»).
  """
  @spec gaps(Build.t(), map()) :: [tuple()]
  def gaps(%Build{} = build, ruleset) do
    # Fetched once per list rather than per group: it is the same set for every
    # group of a ruleset, exactly as it is for every fact of one.
    our = GapReceivers.our(ruleset)

    for group <- of(build, ruleset),
        gap <- purity_gaps(group, our) ++ benefit_gaps(group, our),
        do: gap
  end

  # `nil` — no page says whether purity is required — is read as "yes", and the
  # gap above says it was read that way. Two reasons, both about the direction of
  # the error: the only group whose rule *is* written down requires it, and
  # requiring it makes the claim narrower, so a wrong reading withholds a flag
  # instead of inventing one.
  defp purity_required?(%{purity_required: false}), do: false
  defp purity_required?(_group), do: true

  defp belongs?(%Build{levels: []}, _group), do: false

  defp belongs?(%Build{levels: levels}, group) do
    if purity_required?(group) do
      Enum.all?(levels, &MapSet.member?(group.classes, &1))
    else
      Enum.any?(levels, &MapSet.member?(group.classes, &1))
    end
  end

  defp membership(group) do
    counted = Map.get(group, :benefits_counted) || []

    %{
      id: group.id,
      name: group.name,
      classes: group.classes |> MapSet.to_list() |> Enum.sort(),
      purity_required?: purity_required?(group),
      purity_stated?: is_boolean(group.purity_required),
      purity_not_a_gap: Map.get(group, :purity_not_a_gap),
      benefits: group.benefits,
      benefits_counted: counted,
      # ⚠ Handed on unfiltered, and that is not the same list `benefit_gaps/2`
      # asks about: «не посчитано» and «дырка в нашем ответе» are two different
      # statements, and the caption's job is the first one. A benefit stays in
      # here whether or not its receiver is something we print.
      benefit_receivers: Map.get(group, :benefit_receivers) || %{},
      # ⚠ Handed over already subtracted, rather than leaving the caller to do it.
      # The caption's whole job is to name what is **not** counted, and a caller
      # working that out itself would be a second place deciding which of a
      # group's benefits reach a number.
      benefits_uncounted: (group.benefits || []) -- counted
    }
  end

  defp purity_gaps(%{purity_stated?: true}, _our), do: []

  # ⚠ Second silence, and it is the owner's decision rather than a reading:
  # `not_a_gap` says the assumption distorts no number, only the flag itself
  # (task 3.100, Dan 25.08.2026). Asked through `GapReceivers` and not with an
  # `is_map/1` of our own, so that «обязаны ли мы признаться» keeps one answer
  # across the four families of data that carry this field — the same reason
  # `Loader.NotAGap` is one guard instead of four.
  #
  # ⚠ The record carries no `affects` and never will: there is no mechanic to
  # name here. What is unknown is a rule of the shard, and what we did about it
  # is assume — so the only thing that can silence it is somebody deciding it
  # is not a hole. No decision, and the caveat is back.
  defp purity_gaps(%{id: id} = group, our) do
    if GapReceivers.record_ours?(%{not_a_gap: Map.get(group, :purity_not_a_gap)}, our),
      do: [{:assumed, {:class_group_purity, id}}],
      else: []
  end

  # An empty list of benefits is treated as "nobody wrote them down", not as "the
  # group gives nothing": no page on either wiki says a group gives nothing, and
  # a group that gave nothing would not be worth a page.
  defp benefit_gaps(%{benefits: benefits, id: id}, _our) when benefits in [nil, []],
    do: [{:missing_data, {:class_group_benefits, id}}]

  # ⚠ Only about what is **left**, since task 3.35. The form means «перечислено,
  # и калькулятор не несёт из этого ничего», and one line of Sagra's list —
  # «усиленный бонус от оружия» — is carried now (`Rules.WeaponTypeBonus`). A
  # group all of whose benefits are counted owes no caveat at all, which is the
  # honest end of the same rule rather than a special case.
  defp benefit_gaps(%{benefits_uncounted: [], id: _id}, _our), do: []

  # 🔴 And the third silence (task 3.100): what is left over is real, and every
  # bit of it is about a mechanic the calculator answers **nothing** about —
  # potions and a whetstone, i.e. buffs and items. A gap is a hole in our answer
  # (CLAUDE.md §9, Dan 10.08.2026), so there is no hole here, and saying «не
  # считаем» about a question we never ask is the same false uncertainty the
  # data banner was gated for.
  #
  # ⚠ Exactly the rule the facts of a class are judged by, asked through the one
  # module that owns it. Three directions, all towards showing the caveat: a
  # benefit with **no** label keeps it, **one** benefit we would print is enough
  # to keep it, and a ruleset with no vocabulary at all keeps every one of them.
  defp benefit_gaps(%{benefits_uncounted: uncounted, id: id} = group, our) do
    receivers = Map.get(group, :benefit_receivers) || %{}

    if Enum.any?(uncounted, &GapReceivers.record_ours?(%{affects: receivers[&1]}, our)),
      do: [{:not_modelled, {:class_group_benefits, id}}],
      else: []
  end
end
