defmodule BuildCalculator.Wiki.WeaponPage do
  @moduledoc """
  Reads one Fandom `{{Weapon}}` page into the fields a weapon dictionary needs.

  Weapons are the domain eight feats choose from — `Weapon focus` and its family,
  `Improved critical` and its — and until this module existed the domain resolved
  to nothing, so a build carried `{:missing_data, {:choice_domain, :weapon}}` and
  no choice was ever checked.

  ## What counts as a weapon is the template, not a list

  A page belongs here iff it carries exactly one `{{Weapon}}` call.
  `Category:Weapons` also holds thirteen overview pages (`Melee weapon`,
  `Weapon size`, `Sword`, `Axe`, …), and hand-listing them would be a list to
  keep in step with the wiki. Checked over the whole snapshot: the template and
  the category agree in both directions — every page carrying it is in the
  category and vice versa apart from those thirteen.

  ## Grip is **not** a field, and that is the finding

  The task asked for "one-handed / two-handed", the way the item palette shows
  it. The wiki does not state it per weapon and cannot: `fandom:Two-handed
  weapon` says a two-handed weapon is "a weapon whose weapon size is one
  category larger than its wielder", and `fandom:Weapon size` spells out the
  consequence — a halfling "may only wield a longsword two-handed" while a human
  wields the same longsword in one hand. So grip is a function of **two** sizes,
  and a per-weapon `hands: "two_handed"` column would be false for gnomes and
  halflings — the quiet kind of wrong. What is stated is the weapon's `size`,
  and that is what this module reads; the rule that turns two sizes into a grip
  is quoted once beside the dictionary rather than applied 47 times inside it.

  ## Three fields, three readings, and a cross-check

    * **proficiency** is stated twice by two different hands — the
      `proficiency=` parameter and the page's own categories (`Category:Simple
      weapons`) — so they are read separately and compared. Two weapons
      disagree, and both are interesting rather than noise: see `conflicts/1`.
    * **size** is stated twice as well: the parameter, and the
      `Weapon size` page's table. That page is read by the caller and handed in.
    * **critical** and **damage** are single-sourced, verbatim in `*_raw`, and
      parsed only where the value is nothing but the number. `1d0` (Lance),
      `varies` (Creature weapon), `0` (creature items) and
      `1[[d2]] (small creature) or…` (Unarmed strike) are the shapes that stop a
      parse, and they are left `nil` rather than rounded into something plausible.

  ⚠ Struck-through history is cut before anything is read, exactly as
  `BuildCalculator.Wiki.SialaSpellPage` does it and for the same reason: the
  Lance's critical is written `<del>x1</del> ''x3''`, and reading the strike as
  the current answer would make it a ×1 weapon.

  ⚠ A threat range is recorded **only where the field states one**. The wiki
  writes `19-20/x2` when the range is wider than a natural 20 and usually just
  `x3` when it is not — but not always (`Creature weapon` writes `20/x2`, the
  creature items `20-20/x2`), so the omission is an inconsistency rather than a
  convention, and reading it as "20" would be inventing a number in 21 places.
  """

  alias BuildCalculator.Wiki.{SialaSpellPage, Wikitext}

  @typedoc ~S(A parsed weapon; every key is present, `nil` meaning "the page does not say".)
  @type weapon :: map()

  # `[[Weapon proficiency (simple)|Simple]]` — the parenthesised key is the
  # stable half. Case varies between pages, hence /i.
  @proficiency_link ~r/\[\[\s*weapon proficiency \(([a-z]+)\)/iu

  # The literal values the parameter takes instead of a link. Two spellings of
  # "no proficiency needed" and one of "the question does not apply"; a closed
  # vocabulary read as literals, not a guess about mechanics.
  @proficiency_literals %{
    "none needed" => :not_required,
    "none" => :not_required,
    "n/a" => :not_applicable
  }

  # The three that are a *category* of proficiency rather than a class's own
  # list. Exactly one of them per weapon, or none.
  @proficiency_categories ~w(simple martial exotic)

  @sizes ~w(tiny small medium large)

  # `[[piercing-slashing damage|Piercing & slashing]]` — again the target, not
  # the label, and the label's case and ampersands are not read at all.
  @damage_type_link ~r/\[\[\s*([a-z-]+) damage/iu

  @dice ~r/^(\d+)d(\d+)$/u

  # `19-20/x2`, `20/x2`, `x3`. The range is optional; the multiplier is not.
  @critical ~r/^(?:(\d+)(?:-(\d+))?\/)?x(\d+)$/u

  @doc """
  The categories this module reads meaning out of, keyed by what they mean.

  Named here rather than inline so the caller can check them against the
  category snapshot: a category renamed on the wiki must fail loudly, not
  quietly stop marking anything.
  """
  @spec category_meanings() :: %{atom() => String.t()}
  def category_meanings do
    %{
      weapons: "Category:Weapons",
      simple: "Category:Simple weapons",
      martial: "Category:Martial weapons",
      exotic: "Category:Exotic weapons",
      ranged: "Category:Ranged weapons",
      thrown: "Category:Throwing weapons",
      double_sided: "Category:Double-sided weapons"
    }
  end

  @doc """
  Whether a page is a weapon: exactly one `{{Weapon}}` call on it.

  `{:error, :ambiguous}` is a genuine possibility (a page describing a family
  could carry two) and is passed through rather than resolved here.
  """
  @spec template(binary) ::
          {:ok, map()} | {:error, :none | :ambiguous | :unbalanced}
  def template(wikitext), do: BuildCalculator.Wiki.Template.find_one(wikitext, "weapon")

  @doc """
  Parses one weapon.

    * `params` — the `{{Weapon}}` parameters, verbatim
    * `categories` — the page's own categories, as the API reports them (**not**
      the template's `category=` parameter: `Sling` and `Creature weapon` leave
      that empty and put their category links at the foot of the page instead)
    * `ranged_categories` — the categories that mean "ranged", the ranged one
      and every subcategory of it. `Category:Throwing weapons` is filed under
      `Category:Ranged weapons`, and a page lists only its *direct* categories,
      so a dart says "throwing" and never says "ranged".
  """
  @spec parse(map(), [binary], [binary]) :: weapon()
  def parse(params, categories, ranged_categories) do
    proficiency_raw = param(params, "proficiency")
    critical_raw = param(params, "critical")
    damage_raw = param(params, "damage")
    size_raw = param(params, "size")
    type_raw = param(params, "damagetype")

    {threat_low, threat_high, multiplier} = critical(critical_raw)
    proficiency = proficiency(proficiency_raw)
    in_category = MapSet.new(categories)

    %{
      proficiency: proficiency,
      proficiency_raw: proficiency_raw,
      proficiency_category: Enum.find(proficiency, &(&1 in @proficiency_categories)),
      proficiency_required: proficiency_required(proficiency_raw, proficiency),
      proficiency_from_categories: from_categories(in_category),
      size: size(size_raw),
      size_raw: size_raw,
      ranged: Enum.any?(ranged_categories, &MapSet.member?(in_category, &1)),
      thrown: MapSet.member?(in_category, category_meanings().thrown),
      double_sided: MapSet.member?(in_category, category_meanings().double_sided),
      damage: dice(damage_raw),
      damage_raw: damage_raw,
      threat_range_low: threat_low,
      threat_range_high: threat_high,
      critical_multiplier: multiplier,
      critical_raw: critical_raw,
      damage_types: damage_types(type_raw),
      damage_type_raw: type_raw,
      categories: Enum.sort(categories)
    }
  end

  @doc """
  Where a weapon's two statements of its proficiency disagree, as a list.

  Empty for 45 of the 47. The two that are not are `Lance` (`proficiency=none`,
  filed under simple weapons) and `Magic staff` (`proficiency=none needed`, also
  filed under simple weapons) — and they are the two weapons no weapon feat has
  a variant for, which is why the disagreement is recorded rather than resolved.
  Picking a side here would be exactly the "«чиним» противоречие выбором того
  варианта, что нам нравится" CLAUDE.md §3 forbids.
  """
  @spec conflicts(weapon()) :: [map()]
  def conflicts(weapon) do
    case {weapon.proficiency_category, weapon.proficiency_from_categories} do
      {same, same} ->
        []

      {from_param, from_category} ->
        [
          %{
            field: "proficiency_category",
            from_parameter: from_param,
            from_categories: from_category,
            parameter_raw: weapon.proficiency_raw
          }
        ]
    end
  end

  @size_header ~r/^\s*!\s*(Tiny|Small|Medium|Large)\s*$/u
  @size_row ~r/^\s*\|\s*\[\[([^\[\]|]+)(?:\|[^\[\]]*)?\]\](.*)$/u

  @doc """
  The `Weapon size` page's table, as `%{weapon title => %{size:, notes:}}`.

  The second statement of every weapon's size, by a different hand and in a
  different shape — a table of size × proficiency with an italic aside per row
  (`[[dart]] || ''(piercing, ranged)''`). Read line by line rather than as a
  wikitable because the page nests a table per cell, and column attribution is
  not needed: the row header alone answers "what size", and `notes` carries the
  aside verbatim so "ranged" and "2-sided" can be compared too.

  Titles come back exactly as the page links them, lowercase and all; the caller
  owns the id scheme (see `mix wiki.parse`).
  """
  @spec size_table(binary) :: %{binary => %{size: binary, notes: binary}}
  def size_table(wikitext) do
    wikitext
    |> String.split("\n")
    |> Enum.reduce({nil, %{}}, fn line, {size, found} ->
      cond do
        match = Regex.run(@size_header, line) ->
          {match |> List.last() |> String.downcase(), found}

        is_nil(size) ->
          {size, found}

        match = Regex.run(@size_row, line) ->
          [_all, target, tail] = match
          {size, Map.put_new(found, target, %{size: size, notes: Wikitext.strip_links(tail)})}

        true ->
          {size, found}
      end
    end)
    |> elem(1)
  end

  @doc """
  The same table's row headers, **in the order the page prints them**.

  `["tiny", "small", "medium", "large"]` — the ladder every size rule on that
  page is stated against ("up to one size larger than their own size and down to
  two sizes smaller"), and without it none of them can be computed: "one
  category larger" is a step along an order, and an order is exactly what a set
  of four words is not.

  ⚠ **The order is read, not assigned.** The page lays its table out as size ×
  proficiency and prints the four row headers top to bottom; this returns them in
  that document order. The *set* is still pinned by `@size_header`, which is what
  makes a fifth size stop the build rather than vanish — the caller checks every
  weapon's stated size against this list.

  ⚠ Deliberately a separate function from `size_table/1` even though both walk
  the same headers: that one answers "what size is this weapon", this one answers
  "which sizes are there and in what order", and a table listing no weapon of
  some size would still have to keep its place in the ladder.
  """
  @spec size_order(binary) :: [binary]
  def size_order(wikitext) do
    wikitext
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(@size_header, line) do
        nil -> []
        match -> [match |> List.last() |> String.downcase()]
      end
    end)
    |> Enum.uniq()
  end

  @melee_list ~r/the list is(.*?)Additional melee weapons/su

  @doc """
  The weapons `fandom:Melee weapon` names, as linked titles.

  Not the definition of "melee" — the page is explicit that this is the list
  BioWare's scripts use for spells that target a melee weapon, and that `lance`
  is missing from it by oversight. It is used only as a second route to the same
  set `Weapon of choice` describes in prose, and the two are compared: agreement
  is evidence, not proof, and disagreement stops the build.
  """
  @spec melee_list(binary) :: [binary]
  def melee_list(wikitext) do
    case Regex.run(@melee_list, wikitext) do
      [_all, body] -> body |> Wikitext.link_targets() |> Enum.uniq()
      nil -> []
    end
  end

  # ------------------------------------------------------------------ fields --

  defp param(params, name) do
    case Map.get(params, name) do
      value when is_binary(value) -> value |> String.trim() |> nilify()
      _absent -> nil
    end
  end

  defp nilify(""), do: nil
  defp nilify(value), do: value

  defp plain(nil), do: nil
  defp plain(value), do: value |> SialaSpellPage.strip_struck() |> Wikitext.strip_links()

  defp proficiency(nil), do: []

  defp proficiency(raw) do
    case @proficiency_link
         |> Regex.scan(raw)
         |> Enum.map(&(&1 |> List.last() |> String.downcase())) do
      [] -> []
      keys -> Enum.sort(Enum.uniq(keys))
    end
  end

  # Three answers, and the third is not the second. `n/a` on `Unarmed strike`
  # says the question does not apply (there is no item to be proficient with);
  # `none`/`none needed` say the weapon needs no proficiency, which is the fact
  # Dan measured in game for the staff and the reason this field exists at all.
  # A page that says neither and links no proficiency leaves it unknown.
  defp proficiency_required(raw, keys) do
    case Map.get(@proficiency_literals, String.downcase(plain(raw) || "")) do
      :not_required -> false
      :not_applicable -> nil
      nil -> if keys == [], do: nil, else: true
    end
  end

  defp from_categories(in_category) do
    meanings = category_meanings()

    Enum.find(@proficiency_categories, fn key ->
      MapSet.member?(in_category, Map.fetch!(meanings, String.to_existing_atom(key)))
    end)
  end

  defp size(raw) do
    case String.downcase(plain(raw) || "") do
      size when size in @sizes -> size
      _not_a_size -> nil
    end
  end

  defp dice(raw) do
    case Regex.run(@dice, plain(raw) || "") do
      [_all, count, faces] -> %{count: String.to_integer(count), faces: String.to_integer(faces)}
      nil -> nil
    end
  end

  # ⚠ Only the *whole* value. `1d8/1d8` is a double-sided weapon's two ends and
  # `%{count: 1, faces: 8}` would silently halve it, so it stays unparsed with
  # `double_sided` beside it saying why.
  defp critical(raw) do
    case Regex.run(@critical, plain(raw) || "") do
      [_all, "", "", multiplier] -> {nil, nil, String.to_integer(multiplier)}
      [_all, low, "", multiplier] -> {int(low), int(low), String.to_integer(multiplier)}
      [_all, low, high, multiplier] -> {int(low), int(high), String.to_integer(multiplier)}
      nil -> {nil, nil, nil}
    end
  end

  defp int(text), do: String.to_integer(text)

  defp damage_types(nil), do: []

  defp damage_types(raw) do
    @damage_type_link
    |> Regex.scan(raw)
    |> Enum.map(&(&1 |> List.last() |> String.downcase()))
    |> Enum.uniq()
  end
end
