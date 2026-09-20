defmodule BuildCalculator.Wiki.SialaFeatPage do
  @moduledoc """
  Reads one feat page of the Siala wiki.

  The Siala wiki is a **diff against vanilla**, not a reference: a feat page says
  what the shard changed and stays silent about everything else. Two thirds of
  the 66 pages in `Категория:Фиты` open with the same four bold labels —

      '''Тип навыка:''' Классовый.
      '''Требования:''' Теневой танцор (Shadowdancer) 4 уровня.
      '''Особенности:''' …
      '''Использование:''' Автоматическое.

  — and the rest are free prose. This module lifts the labels, reads the handful
  of shapes that repeat often enough to be read the same way twice, and leaves
  everything else verbatim. Interpreting a value is the caller's job; inventing
  one is nobody's (CLAUDE.md §3).

  ## What gets structured, and what that costs

  Four readings are attempted, all against closed vocabularies or literal numbers
  printed on the page:

    * `type` — the seven spellings `Тип навыка` actually uses, folded onto the
      vanilla `type` vocabulary (`class`, `general`, `defensive`, …).
    * `use` — `Использование`, likewise. A value whose first sentence is one of
      the four known words but which carries a qualifier after it keeps the word
      and is flagged, rather than having the qualifier dropped.
    * `requirements` — split on commas into atoms (`class_level`,
      `character_level`, `max_character_level`, `ability`, `bab`, `skill`,
      `feat`, `race`, `any_of`). This is where the shard's changes actually live:
      `Divine grace` is *Paladin 4* here and Paladin 2 in vanilla.
      A fragment that does not parse becomes `{kind: "unparsed"}` and keeps its
      text — it is never silently dropped, and it downgrades the whole reading.

      Two of those kinds exist because the shard writes a shape vanilla does not.
      `max_character_level` is «умение можно взять только на 1-ом уровне»
      (`Artist`), the one ceiling among floors. `any_of` is «Тёмный эльф (Elf)
      **или** Убийца (Assassin) 20 уровня» (`Keen sense`), where the shard
      *widened* a vanilla requirement: keeping vanilla's `race: [elf]` would
      refuse an assassin who qualifies, and reading the two halves as separate
      requirements would demand both. It is produced only when every branch
      reads whole — a choice resting on a fragment nobody understood would pass
      on that fragment.

      What is **not** decided here is whether two atoms are joined by «и» or by
      «или». `Lay on hands` states «Паладин (Paladin) 1 уровня, Чемпион Торма
      (Champion of Torm) 1 уровня» with a comma, and only game knowledge —
      a feat's list of granting classes is never a conjunction — makes that a
      choice. That rule belongs to the layer that already owns it
      (`BuildCalculator.Data.Loader.Feats.shard_prereqs/1`), not to a second copy here.
    * `unlocks` / `taking` — the five custom weapon-proficiency feats, which have
      no vanilla counterpart at all (see below).

  Which entity a requirement names is decided by looking the **English name in
  parentheses** up in the vanilla snapshot, not by guessing from the Russian:
  `Артистизм (Perform)` is a skill because `perform` is a skill id, and
  `Уклонение (Evasion)` is a feat because `evasion` is a feat id. Russian class
  names are resolved through a lookup the caller supplies.

  ## The five weapon-proficiency feats

  `Владение клинковым/древковым/…оружием` are a Siala invention that prestige
  class requirements refer to as «Владение оружием». One feat opens successive
  **weapon groups by character level** — daggers at 1, longswords at 10, greatswords
  at 20, rapiers at 30 — each group listing its own damage range, threat range and
  grip. `unlocks/1` reads that numbered list; `taking` reads the
  «Возможность взятия фита» section, which states which class may spend which
  **feat slot** on it (Fighter's bonus feats, Ranger's favored-enemy levels …) and
  therefore feeds the slot model of CLAUDE.md §6 directly.

  Weapon names stay Russian (`name_ru`). The shard publishes no English name for
  them, and transliterating one would be a guess.
  """

  alias BuildCalculator.Wiki.Wikitable
  alias BuildCalculator.Wiki.Wikitext

  @type fact :: %{
          what: binary,
          value: term,
          quote: binary,
          note: binary | nil,
          status: binary
        }

  @type t :: %{
          type: binary | nil,
          type_raw: binary | nil,
          requirements: [map] | nil,
          requirements_raw: binary | nil,
          use: binary | nil,
          use_raw: binary | nil,
          special_raw: binary | nil,
          extra_labels: [{binary, binary}],
          lead_raw: binary | nil,
          sections: [%{title: binary, body: binary}],
          tables: [map],
          unlocks: [map] | nil,
          taking: map | nil,
          moved: [map],
          disabled: binary | nil,
          granted_automatically_to: [binary] | nil,
          fandom_links: [binary],
          problems: [binary]
        }

  @doc """
  An empty lookup — every name resolves to `nil`, every requirement to `unparsed`.

  `parse/2` takes a lookup built from the vanilla snapshot plus the Russian class
  names; this is what it degrades to when the caller has none, and it is what the
  tests that only care about labels use.
  """
  @spec empty_lookup() :: map
  def empty_lookup do
    %{
      classes: %{},
      class_ids: MapSet.new(),
      skill_ids: MapSet.new(),
      feat_ids: MapSet.new(),
      race_ids: MapSet.new()
    }
  end

  # ── vocabularies ────────────────────────────────────────────────────────────

  # `Требования` and `Предварительные условия` are the same label under two names
  # (only `Dirty fighting` uses the second).
  @label_fields %{
    type: ["тип навыка"],
    requirements: ["требования", "предварительные условия"],
    use: ["использование"],
    special: ["особенности"]
  }

  # Every spelling `Тип навыка` uses, folded onto the vanilla `type` vocabulary.
  # The `(Общий)` / `(Классовый)` split Siala adds to item creation has no vanilla
  # counterpart and stays readable in `type_raw`.
  @types %{
    "классовый" => "class",
    "основной" => "general",
    "оборонительный" => "defensive",
    "особый" => "special",
    "расовый, классовый" => "classrace",
    "создание предметов (общий)" => "item creation",
    "создание предметов (классовый)" => "item creation"
  }

  # `personal` is Siala's own — the vanilla vocabulary is automatic/selected/combat
  # mode/cast — and is kept as its own word rather than bent onto one of those.
  @uses %{
    "по выбору" => "selected",
    "автоматическое" => "automatic",
    "персональное" => "personal",
    "боевой режим" => "combat mode"
  }

  @abilities %{
    "сила" => "STR",
    "ловкость" => "DEX",
    "телосложение" => "CON",
    "интеллект" => "INT",
    "мудрость" => "WIS",
    "харизма" => "CHA"
  }

  @damage_types %{
    "колющий" => "piercing",
    "режущий" => "slashing",
    "дробящий" => "bludgeoning"
  }

  @grips %{
    "одноручное" => "one_handed",
    "двуручное" => "two_handed",
    "двустороннее" => "double_sided"
  }

  @ranged_kinds %{"метательное" => "thrown", "стрелковое" => "projectile"}

  # Sections that hold pointers rather than rules; their bodies are still kept, but
  # they never become a fact of their own.
  @reference_sections ["ссылки", "история изменений", "источники"]

  @category ~r/^\s*\[\[\s*(?:категория|category)\s*:/iu
  @label_line ~r/^\s*'''/u

  @doc """
  Parses one feat page.

  `lookup` resolves names to ids and is built by the caller from the vanilla
  snapshot (`skill_ids`, `feat_ids`, `race_ids`, `class_ids`) plus a
  `classes` map of normalised Russian *and* English class names to class ids.
  Defaults to `empty_lookup/0`.

  `problems` collects everything the page did not yield in a readable form; the
  caller is expected to print it rather than swallow it.
  """
  @spec parse(binary, map | nil) :: t
  def parse(wikitext, lookup \\ nil) do
    lookup = lookup || empty_lookup()
    sections = sections(wikitext)
    [lead | rest] = sections
    labels = labels(sections)
    {requirements, requirement_problems} = requirements(labels[:requirements], lookup)
    unlocks = unlocks(sections)

    %{
      type: Map.get(@types, fold(labels[:type])),
      type_raw: labels[:type],
      requirements: requirements,
      requirements_raw: labels[:requirements],
      use: use_of(labels[:use]),
      use_raw: labels[:use],
      special_raw: labels[:special],
      extra_labels: labels[:__extra__],
      lead_raw: lead_prose(lead.body),
      sections: Enum.map(rest, &%{title: &1.title, body: String.trim(&1.body)}),
      tables: tables(wikitext),
      unlocks: unlocks,
      taking: taking(sections, lookup),
      moved: moved(wikitext, lookup),
      disabled: disabled(wikitext),
      granted_automatically_to: granted_automatically_to(wikitext, lookup),
      fandom_links: fandom_links(wikitext),
      problems: requirement_problems ++ label_problems(labels) ++ unlock_problems(unlocks)
    }
  end

  # ── sections and labels ─────────────────────────────────────────────────────

  # `[[Категория:Фиты]]` sits at the top of some pages and at the bottom of others,
  # where `labels/1` would otherwise read it as the continuation of the last label.
  defp sections(wikitext) do
    wikitext
    |> String.split("\n")
    |> Enum.reject(&Regex.match?(@category, &1))
    |> Enum.join("\n")
    |> Wikitext.sections()
  end

  # Labels are collected from every section, not just the lead: `Болезнь (Черный
  # страж)` keeps its whole label block under `== Изменения ==`.
  #
  # A bold line only counts as a label when the page really wrote a colon after
  # the name. Three lines on `Summon shadow` are bold *formulas*
  # (`'''Усиление Тени = Уровни в классе * 3'''`), and reading those as labels
  # named after a formula would be nonsense.
  defp labels(sections) do
    pairs =
      for section <- sections,
          {label, value} <- Wikitext.labels(section.body),
          colon_after?(section.body, label),
          value = String.trim(value),
          value != "",
          do: {Wikitext.normalize_label(label), value}

    known =
      for {field, names} <- @label_fields,
          {name, value} <- pairs,
          name in names,
          reduce: %{} do
        acc -> Map.put_new(acc, field, value)
      end

    taken = @label_fields |> Map.values() |> List.flatten() |> MapSet.new()

    extra =
      pairs
      |> Enum.reject(fn {name, _value} -> MapSet.member?(taken, name) end)
      |> Enum.reduce(%{}, fn {name, value}, acc -> Map.put_new(acc, name, value) end)
      |> Enum.sort()

    Map.put(known, :__extra__, extra)
  end

  # Both ways the wiki writes the colon — inside the bold and after it.
  defp colon_after?(body, label) do
    Regex.match?(~r/#{Regex.escape(label)}\s*(?:''')?\s*:/u, body)
  end

  # The prose above the first label — on a page with no labels at all, that is the
  # whole diff (`Живучесть`, `Уклонение`, `Разрушительный критический удар`).
  defp lead_prose(body) do
    body
    |> String.split("\n")
    |> Enum.take_while(&(not Regex.match?(@label_line, &1)))
    |> Enum.join("\n")
    |> String.trim()
    |> blank_to_nil()
  end

  defp tables(wikitext) do
    for source <- Wikitable.find_all(wikitext) do
      grid = source |> Wikitable.parse() |> Map.fetch!(:rows) |> Wikitable.expand()

      case grid do
        [head | rows] ->
          %{
            columns: Enum.map(head, & &1.text),
            rows: Enum.map(rows, fn row -> Enum.map(row, & &1.text) end),
            source: String.trim(source)
          }

        [] ->
          %{columns: [], rows: [], source: String.trim(source)}
      end
    end
  end

  # ── scalar readings ─────────────────────────────────────────────────────────

  defp fold(nil), do: nil

  # `ё` folds to `е`: the wiki spells the blackguard `Чёрный страж` on its own page
  # and `Черный страж` in the feat pages that link to it, and the two must key alike
  # (the same trap the race names carry, CLAUDE.md §3).
  defp fold(value) do
    value
    |> Wikitext.strip_links()
    |> String.downcase()
    |> String.replace("ё", "е")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.trim_trailing(".")
    |> String.trim()
  end

  # Only the leading sentence is read. Five pages qualify the word afterwards
  # ("Автоматическое. Эффект срабатывает один раз в день.") — the word is kept and
  # the qualifier stays visible in `use_raw`; `qualified_use?/1` makes the caller
  # mark such a reading as incomplete rather than clean.
  defp use_of(nil), do: nil
  defp use_of(value), do: Map.get(@uses, value |> first_sentence() |> fold())

  @doc "True when `Использование` says more than the one word that was read."
  @spec qualified_use?(binary | nil) :: boolean
  def qualified_use?(nil), do: false

  def qualified_use?(value) do
    rest = String.replace_prefix(value, first_sentence(value), "")
    String.trim(rest) not in ["", "."]
  end

  defp first_sentence(value) do
    case String.split(value, ".", parts: 2) do
      [head, _tail] -> head
      [head] -> head
    end
  end

  # ── requirements ────────────────────────────────────────────────────────────

  @doc """
  Splits a `Требования` value into atoms.

  Returns `{atoms, problems}`. Every comma-separated fragment produces exactly one
  atom, so `requirements_raw` can always be reconstructed from the parts and a
  fragment can never go missing. A fragment that does not match any known shape
  comes back as `%{kind: "unparsed", raw: …}`.
  """
  @spec requirements(binary | nil, map) :: {[map] | nil, [binary]}
  def requirements(nil, _lookup), do: {nil, []}

  def requirements(raw, lookup) do
    atoms =
      raw
      |> Wikitext.strip_links()
      |> String.trim_trailing(".")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&requirement(&1, lookup))
      |> merge_trailing_levels()

    problems =
      for %{kind: "unparsed", raw: text} <- atoms,
          do: "requirement fragment not understood: #{text}"

    {atoms, problems}
  end

  @level ~r/(\d+)\s*[-–]?\s*(?:го|ого)?\s*уровня\s*$/u
  @ordinal_level ~r/^(\d+)\s*[-–]?\s*(?:й|ый|ом|го|ого)?\s*уровень$/u
  @bare_level ~r/^уровень\s+(\d+)$/u
  @bab ~r/^базовый\s+бонус\s+(?:к\s+)?атак[еи]\s*\+?(\d+)/u
  @parenthesised ~r/^(.*?)\s*\(([^()]*)\)\s*(.*)$/u

  # «умение можно взять только на 1-ом уровне» (`Artist`) — a **ceiling**, and
  # the shard's wording for the sentence Fandom writes as "can only take this
  # feat at 1st-level". Every other number on these pages is a floor.
  @only_at ~r/^(?:умение|фит)?\s*можно\s+взять\s+только\s+на\s+(\d+)\s*[-–]?\s*(?:ом|м|ый|ой|й|го|ого)?\s*уровне$/u

  defp requirement(fragment, lookup) do
    cond do
      # `Темный эльф (Elf) или Убийца (Assassin) 20 уровня` — an alternative, not a
      # conjunction, and the page says so in the word «или». It is read only when
      # **every** branch reads whole; a branch left over would make the choice
      # pass on a fragment nobody understood.
      String.contains?(fragment, " или ") and not Regex.match?(@bab, String.downcase(fragment)) ->
        alternative(fragment, lookup)

      match = Regex.run(@only_at, fragment) ->
        [_, level] = match
        %{kind: "max_character_level", level: String.to_integer(level), raw: fragment}

      match = Regex.run(@parenthesised, fragment) ->
        [_, russian, english, tail] = match
        named(fragment, russian, english, tail, lookup)

      match = Regex.run(@ordinal_level, fragment) ->
        [_, level] = match
        %{kind: "character_level", level: String.to_integer(level), raw: fragment}

      match = Regex.run(@bab, String.downcase(fragment)) ->
        [_, bonus] = match
        %{kind: "bab", value: String.to_integer(bonus), raw: fragment}

      atom = ability(fragment, fragment) ->
        atom

      atom = russian_class(fragment, lookup) ->
        atom

      Regex.match?(@bare_level, fragment) ->
        [_, level] = Regex.run(@bare_level, fragment)
        %{kind: "level", level: String.to_integer(level), raw: fragment}

      true ->
        unparsed(fragment)
    end
  end

  # `Keen sense` is the one page that widens a vanilla requirement into a choice:
  # vanilla asks for an elf, the shard for «Тёмный эльф **или** Убийца 20
  # уровня». Keeping vanilla's race list would refuse an assassin who qualifies,
  # and reading the two halves as separate requirements would demand both.
  defp alternative(fragment, lookup) do
    branches =
      fragment
      |> String.split(" или ")
      |> Enum.map(&(&1 |> String.trim() |> requirement(lookup)))

    if Enum.any?(branches, &(&1.kind in ["unparsed", "level"])),
      do: unparsed(fragment),
      else: %{kind: "any_of", branches: branches, raw: fragment}
  end

  # `Бледный мастер (Pale master) 2 уровня` — the English name in the parentheses is
  # the reliable half, because it is an id in the vanilla snapshot. Which *kind* of
  # thing the fragment names follows from which snapshot the id is in.
  defp named(fragment, russian, english, tail, lookup) do
    id = id(english)

    cond do
      class = Map.get(lookup.classes, fold(english)) ->
        %{
          kind: "class_level",
          class: class,
          level: number(tail) || number(russian),
          raw: fragment
        }

      MapSet.member?(lookup.skill_ids, id) ->
        %{kind: "skill", skill: id, rank: number(tail), raw: fragment}

      MapSet.member?(lookup.feat_ids, id) ->
        %{kind: "feat", feat: id, raw: fragment}

      MapSet.member?(lookup.race_ids, id) ->
        %{kind: "race", race: id, raw: fragment}

      true ->
        unparsed(fragment)
    end
  end

  defp ability(fragment, raw) do
    case Regex.run(~r/^(\p{L}+)\s+(\d+)\s*\+?$/u, String.trim(fragment)) do
      [_, name, value] ->
        case Map.get(@abilities, String.downcase(name)) do
          nil ->
            nil

          ability ->
            %{kind: "ability", ability: ability, value: String.to_integer(value), raw: raw}
        end

      nil ->
        nil
    end
  end

  # `Рыцарь Пурпурного дракона 6 уровня` — the only class shape the pages write
  # without an English name beside it.
  defp russian_class(fragment, lookup) do
    name = Regex.replace(@level, fragment, "") |> String.trim()

    case Map.get(lookup.classes, fold(name)) do
      nil -> nil
      class -> %{kind: "class_level", class: class, level: number(fragment), raw: fragment}
    end
  end

  # `Тайный Лучник (Arcane Archer), уровень 10` puts the class level in the next
  # comma-separated fragment. Attaching it to the class before it is what the
  # sentence says; leaving it as a bare `level` would be a character level, which
  # it is not.
  defp merge_trailing_levels(atoms) do
    atoms
    |> Enum.reduce([], fn
      %{kind: "level", level: level}, [%{kind: "class_level", level: nil} = class | rest] ->
        [%{class | level: level, raw: class.raw <> ", " <> "уровень #{level}"} | rest]

      %{kind: "level", raw: raw}, acc ->
        [unparsed(raw) | acc]

      atom, acc ->
        [atom | acc]
    end)
    |> Enum.reverse()
  end

  # The first number in a fragment, or `nil` when it states none.
  #
  # Every caller hands it a capture group, so the argument is always a string and
  # there is deliberately no `number(nil)` head: "the text names no level" is the
  # **result** `nil`, produced by the clause below, and `merge_trailing_levels/1`
  # is what reads it — `Тайный Лучник (Arcane Archer), уровень 10` puts the level
  # in the next fragment and leaves this one with `level: nil`.
  defp number(text) do
    case Regex.run(~r/(\d+)/u, text) do
      [_, digits] -> String.to_integer(digits)
      nil -> nil
    end
  end

  defp unparsed(raw), do: %{kind: "unparsed", raw: raw}

  # ── the five custom weapon proficiency feats ────────────────────────────────

  @unlock_level ~r/с\s+(\d+)\s*[-–]\s*го\s+уровня/u
  @weapon_stats ~r/\(([^()]*урон\s*-[^()]*)\)/u

  @doc """
  Reads the numbered weapon list of a `Владение …` page.

  Each `#` item is one unlock step: the character level it opens at, and the
  weapons it opens, each with the damage range, threat range and grip printed
  next to it. Returns `nil` on a page that has no such list.
  """
  @spec unlocks([map]) :: [map] | nil
  def unlocks(sections) do
    lines =
      for section <- sections,
          line <- String.split(section.body, "\n"),
          String.starts_with?(String.trim(line), "#"),
          Regex.match?(@weapon_stats, line),
          do: String.trim(line)

    case lines do
      [] -> nil
      lines -> Enum.map(lines, &unlock/1)
    end
  end

  defp unlock(line) do
    %{level: unlock_level(line), weapons: weapons(line), raw: line}
  end

  defp unlock_level(line) do
    case Regex.run(@unlock_level, line) do
      [_, level] -> String.to_integer(level)
      nil -> nil
    end
  end

  # The stat group `('''2-4''' ''20/х2'' одноручное, урон - колющий)` is the anchor:
  # a weapon's name is whatever precedes it since the previous group ended. Matching
  # that way survives `Моргенштерны (палицы) ('''3-36''' …)`, where the name itself
  # carries a parenthesis.
  defp weapons(line) do
    {weapons, _cursor} =
      Regex.scan(@weapon_stats, line, return: :index)
      |> Enum.map_reduce(0, fn [{start, length}, {inner_start, inner_length}], cursor ->
        name = binary_part(line, cursor, start - cursor)
        stats = binary_part(line, inner_start, inner_length)
        {weapon(name, stats), start + length}
      end)

    weapons
  end

  @stats ~r/^((?:'''[^']+'''\/?)+)\s+''([^']+)''\s+([^,]+),\s*урон\s*-\s*(.+)$/u

  defp weapon(name, stats) do
    base = %{
      name_ru: clean_weapon_name(name),
      damage_raw: nil,
      damage: nil,
      crit_raw: nil,
      crit: nil,
      grip_raw: nil,
      grip: nil,
      ranged: nil,
      damage_type_raw: nil,
      damage_type: nil,
      raw: String.trim(stats)
    }

    case Regex.run(@stats, String.trim(stats)) do
      [_, damage, crit, grip, damage_type] ->
        %{
          base
          | damage_raw: String.trim(damage) |> String.replace("'''", ""),
            damage: damage_ranges(damage),
            crit_raw: String.trim(crit),
            crit: crit(crit),
            grip_raw: String.trim(grip),
            grip: Map.get(@grips, grip |> String.split("/") |> hd() |> String.trim()),
            ranged: ranged_kind(grip),
            damage_type_raw: String.trim(damage_type),
            damage_type: Map.get(@damage_types, damage_type |> String.trim() |> String.downcase())
        }

      nil ->
        base
    end
  end

  defp clean_weapon_name(name) do
    name
    |> String.replace(~r/^\s*#+\s*/u, "")
    |> String.replace(~r/^\s*(?:и|,)\s+/u, "")
    |> String.replace(~r/\[\d+\]/u, "")
    |> String.trim()
    |> String.trim(",")
    |> String.trim()
  end

  # A double weapon prints one range per end (`'''1-8'''/'''1-8'''`); both are kept.
  defp damage_ranges(damage) do
    for [_, min, max] <- Regex.scan(~r/'''(\d+)\s*-\s*(\d+)'''/u, damage) do
      %{min: String.to_integer(min), max: String.to_integer(max)}
    end
  end

  # `19-20/х2` — note the multiplier's `х` is Cyrillic on every one of these pages.
  defp crit(crit) do
    case Regex.run(~r/^(\d+)(?:\s*-\s*(\d+))?\s*\/\s*[xх]\s*(\d+)$/iu, String.trim(crit)) do
      [_, low, "", multiplier] ->
        %{
          threat_low: String.to_integer(low),
          threat_high: 20,
          multiplier: String.to_integer(multiplier)
        }

      [_, low, high, multiplier] ->
        %{
          threat_low: String.to_integer(low),
          threat_high: String.to_integer(high),
          multiplier: String.to_integer(multiplier)
        }

      _other ->
        nil
    end
  end

  defp ranged_kind(grip) do
    grip
    |> String.split("/")
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.find_value(&Map.get(@ranged_kinds, &1))
  end

  @doc """
  Reads the «Возможность взятия фита» section into feat *slots*.

  The section says who may spend which slot on the feat — "Воин на своих доп
  фитах (на 1 уровне и каждые 2 уровня); на эпических фитах" — which is exactly
  the distinction CLAUDE.md §6 is built on and which a plain "who can take it"
  list would flatten away. Returns `nil` when the page has no such section.
  """
  @spec taking([map], map) :: map | nil
  def taking(sections, lookup) do
    case Enum.find(
           sections,
           &(&1.title && Wikitext.normalize_label(&1.title) =~ ~r/возможность взятия/u)
         ) do
      nil ->
        nil

      section ->
        lines = String.split(section.body, "\n")
        intro = Enum.reject(lines, &String.starts_with?(String.trim(&1), "*"))

        %{
          general: Enum.any?(intro, &String.contains?(&1, "любому персонажу")),
          intro_raw: intro |> Enum.join("\n") |> String.trim(),
          by_class:
            for line <- lines, String.starts_with?(String.trim(line), "*") do
              taking_line(String.trim(line), lookup)
            end
        }
    end
  end

  defp taking_line(line, lookup) do
    class =
      line
      |> Wikitext.link_targets()
      |> Enum.find_value(&Map.get(lookup.classes, fold(&1)))

    slots =
      [
        {"доп фитах", "class_bonus"},
        {"эпических фитах", "epic_class_bonus"},
        {"любимого врага", "favored_enemy"}
      ]
      |> Enum.filter(fn {phrase, _slot} -> String.contains?(line, phrase) end)
      |> Enum.map(fn {_phrase, slot} -> slot end)

    %{class: class, slots: slots, raw: String.replace_prefix(line, "*", "") |> String.trim()}
  end

  # ── one-sentence facts the pages state outright ─────────────────────────────

  @moved ~r/с(?:о)?\s+(\d+)\s*[-–]\s*(?:го|ого)\s+уровня\s+(\[\[[^\]]+\]\])\s+на\s+(\d+)\s*[-–]\s*(?:ый|ой|ий)/u

  @doc """
  Every "moved from level N of X to level M" sentence on the page.

  `Уклонение` and `Улучшенное уклонение` state the shard's most build-breaking
  change this way, and both write it in the same shape.
  """
  @spec moved(binary, map) :: [map]
  def moved(wikitext, lookup) do
    for [raw, from, link, to] <- Regex.scan(@moved, wikitext) do
      class =
        link
        |> Wikitext.link_targets()
        |> Enum.find_value(&Map.get(lookup.classes, fold(&1)))

      %{
        class: class,
        vanilla_level: String.to_integer(from),
        siala_level: String.to_integer(to),
        raw: raw
      }
    end
  end

  @disabled ~r/[^\n.]*отключ[^\n.]*\./u

  @doc "The sentence saying the shard turned the feat off, if there is one."
  @spec disabled(binary) :: binary | nil
  def disabled(wikitext) do
    case Regex.run(@disabled, wikitext) do
      [sentence] -> String.trim(sentence)
      nil -> nil
    end
  end

  @doc """
  The classes that are handed the feat for free, off the bullet list that follows
  the sentence saying so.

  Only the contiguous bullet list counts: `Живучесть` names `[[Гномий защитник]]`
  in the sentence *after* the list for an unrelated reason, and sweeping up every
  class link on the page would pick it up.
  """
  @spec granted_automatically_to(binary, map) :: [binary] | nil
  def granted_automatically_to(wikitext, lookup) do
    lines = String.split(wikitext, "\n")

    case Enum.find_index(lines, &String.contains?(&1, "автоматически получа")) do
      nil ->
        nil

      index ->
        lines
        |> Enum.drop(index + 1)
        |> Enum.take_while(&String.starts_with?(String.trim(&1), "*"))
        |> Enum.flat_map(&Wikitext.link_targets/1)
        |> Enum.map(&Map.get(lookup.classes, fold(&1)))
        |> Enum.reject(&is_nil/1)
    end
  end

  @doc """
  Fandom page titles the page links to as "the English wiki".

  This is the mapping of last resort onto a vanilla feat id, and it is restricted
  to links that say so in their text: the weapon proficiency pages also link
  `Favored_enemy` from a sentence about *when* a ranger may take the feat, and
  reading that as "this page is about favored enemy" would be wrong.
  """
  @spec fandom_links(binary) :: [binary]
  def fandom_links(wikitext) do
    for [_, target, text] <-
          Regex.scan(
            ~r/\[https?:\/\/nwn\.(?:fandom\.com|wikia\.com)\/wiki\/([^\s\]]+)\s+([^\]]*)\]/u,
            wikitext
          ),
        String.contains?(text, "англояз"),
        do: target |> String.replace("_", " ") |> URI.decode()
  end

  @doc "Section titles a page uses for pointers rather than rules."
  @spec reference_section?(binary | nil) :: boolean
  def reference_section?(nil), do: false
  def reference_section?(title), do: Wikitext.normalize_label(title) in @reference_sections

  # ── problems ────────────────────────────────────────────────────────────────

  defp label_problems(labels) do
    unreadable_type =
      case labels[:type] do
        nil -> []
        raw -> if Map.has_key?(@types, fold(raw)), do: [], else: ["unknown 'Тип навыка': #{raw}"]
      end

    unreadable_use =
      case labels[:use] do
        nil -> []
        raw -> if use_of(raw), do: [], else: ["unknown 'Использование': #{raw}"]
      end

    unreadable_type ++ unreadable_use
  end

  defp unlock_problems(nil), do: []

  defp unlock_problems(unlocks) do
    missing_level =
      for %{level: nil, raw: raw} <- unlocks, do: "unlock step states no level: #{raw}"

    unreadable =
      for step <- unlocks,
          weapon <- step.weapons,
          is_nil(weapon.damage_type),
          do: "weapon stats not understood: #{weapon.raw}"

    missing_level ++ unreadable
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp id(name) do
    name
    |> String.replace(~r/['’]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "_")
    |> String.trim("_")
  end
end
