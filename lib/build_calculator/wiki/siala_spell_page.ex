defmodule BuildCalculator.Wiki.SialaSpellPage do
  @moduledoc """
  Reads one spell page of the Siala wiki.

  Spells are the most regular part of that wiki: 128 of the 129 pages in
  `Категория:Заклинания` open with the same block of bold Russian labels —

      '''Уровень Заклинателя:''' Колдун / Волшебник 3
      '''Начальный Уровень:''' 3
      '''Школа:''' Разрушение (Evocation)
      '''Дескриптор(ы):''' Огонь
      '''Компонент(ы):''' Вербальные, Жестовые
      '''Расстояние до Цели:''' Большое
      '''Область Охвата / Цель:''' Огромная
      '''Продолжительность:''' Мгновенное
      '''Спасбросок:''' Рефлекс 1/2
      '''Сопротивление Заклинанию:''' Да

  — followed by the description in prose. Every label is carried over **verbatim**
  into a `*_raw` field; nothing here is folded onto a vocabulary, because unlike
  feats these values are free text the shard writes in its own words.

  ## Where the shard's changes actually are

  Some are in the labels — school, saving throw, spell resistance and the class
  circles are structured on both wikis, and `school/1`, `save/1`,
  `spell_resistance/1`, `circles/1` and `level/1` read either wiki's spelling of
  them into a value that can be compared. The rest are not: `Fireball` on Siala
  carries exactly the vanilla label block and hides the whole balance change in
  the middle of a sentence — «до максимума **20d6**», against vanilla's 10d6.
  Structuring that with a regular expression would be inventing game numbers out
  of prose, which CLAUDE.md §3 forbids.

  So for prose the module does the mechanical half only: it keeps the description
  whole (`description_raw`) and lists the **numbers printed in it** (`numbers/1`).
  The caller compares that list against the same list taken from the vanilla
  description. Two descriptions in two languages cannot be diffed as text, but the
  numbers in them can, and a disagreement is a reliable *pointer*: it says "a
  human must read this one", never "here is the new value".

  ## Struck-through patch history

  Fandom editors record a patch by striking the old value out rather than
  deleting it: `|save=<s>will 1/2</s>`, `<del>3d6</del> ''6d6''`,
  `|innatelevel=<s>2</s> 3`. That text is vanilla's *past*, and comparing it
  against Siala's present invents differences that are not there — six vanilla
  saving throws and one spell resistance alone. `strip_struck/1` cuts it, and
  every reader here runs it first.

  ## Labels, prose and where one ends

  A label's value runs to the end of its paragraph — the next label line or a
  blank line — which is what keeps the creature stat blocks of
  `Summon creature I…IX` attached to the `'''Существо начального уровня:'''` label
  they belong to instead of leaking into the description. Everything in the
  label-bearing section that is not part of a label is the description.

  Three pages are irregular and are read as they are rather than repaired:
  `Mind fog` closes two of its bold labels with `</c>` instead of `'''`,
  `Summon creature IX` writes `'''>Начальный Уровень:'''`, and `Aura of Glory`
  puts its whole label block under a heading. `One With The Land` is the single
  page written as `{{Шаблон:Заклинание}}`, whose named parameters carry the same
  fields under Russian names.
  """

  alias BuildCalculator.Wiki.Template
  alias BuildCalculator.Wiki.Wikitext

  @type t :: %{
          caster_level_raw: binary | nil,
          initial_level_raw: binary | nil,
          school_raw: binary | nil,
          descriptors_raw: binary | nil,
          components_raw: binary | nil,
          range_raw: binary | nil,
          area_raw: binary | nil,
          duration_raw: binary | nil,
          save_raw: binary | nil,
          spell_resistance_raw: binary | nil,
          shamanism_raw: binary | nil,
          extra_labels: [{binary, binary}],
          description_raw: binary | nil,
          numbers: [binary],
          sections: [%{title: binary | nil, body: binary}],
          changes_raw: [%{title: binary, body: binary}],
          fandom_links: [binary],
          template?: boolean,
          problems: [binary]
        }

  # The ten labels the recon found on essentially every page, plus `Шаманство`,
  # which 54 of them carry. Keys are `Wikitext.normalize_label/1` output, so
  # `Дескриптор(ы)` keys on `дескриптор` and `Область Охвата / Цель` on
  # `область охвата цель`. Anything else lands in `extra_labels` verbatim.
  @label_fields [
    {:caster_level, "уровень заклинателя", "Уровень Заклинателя"},
    {:initial_level, "начальный уровень", "Начальный Уровень"},
    {:school, "школа", "Школа"},
    {:descriptors, "дескриптор", "Дескриптор(ы)"},
    {:components, "компонент", "Компонент(ы)"},
    {:range, "расстояние до цели", "Расстояние до Цели"},
    {:area, "область охвата цель", "Область Охвата / Цель"},
    {:duration, "продолжительность", "Продолжительность"},
    {:save, "спасбросок", "Спасбросок"},
    {:spell_resistance, "сопротивление заклинанию", "Сопротивление Заклинанию"},
    {:shamanism, "шаманство", "Шаманство"}
  ]

  # `Дескриптор(ы)` is absent from half the pages by design (a spell without a
  # descriptor), and `Шаманство` from the spells the shard's shamanism does not
  # touch, so neither counts as missing.
  @required_labels [
    :caster_level,
    :initial_level,
    :school,
    :components,
    :range,
    :area,
    :duration,
    :save,
    :spell_resistance
  ]

  @template_name "Шаблон:Заклинание"

  # `{{Шаблон:Заклинание}}` names the same fields in Russian. `круг` holds the
  # class/level pairs the label block writes under `Уровень Заклинателя`.
  @template_fields [
    {:caster_level, "круг"},
    {:school, "школа"},
    {:components, "компонент"},
    {:range, "диапазон"},
    {:area, "зона действия"},
    {:duration, "продолжительность"},
    {:save, "спасбросок"},
    {:spell_resistance, "СР"},
    {:shamanism, "шаманство"}
  ]

  # `<s>…</s>`, `<del>…</del>` and `<strike>…</strike>` — the three ways Fandom
  # writes "this used to say". Unclosed tags are left alone: half a span is not a
  # statement about what it once said.
  @struck ~r/<\s*(s|del|strike)\s*>.*?<\s*\/\s*\1\s*>/isu

  @category ~r/^\s*\[\[\s*(?:категория|category)\s*:/iu
  # An image and a table-of-contents switch are markup, not prose, and the pages
  # that carry them put them on a line of their own.
  @skipped_line ~r/^\s*(?:__[A-Z]+__|\[\[\s*(?:file|файл|image|изображение)\s*:)/iu
  @changes_heading ~r/^изменени.* в заклинани/u

  @doc """
  Parses one spell page.

  `problems` collects everything the page did not yield in a readable form; the
  caller is expected to print it rather than swallow it.
  """
  @spec parse(binary) :: t
  def parse(wikitext) do
    case Template.find_one(wikitext, @template_name) do
      {:ok, template} -> from_template(template, wikitext)
      {:error, :none} -> from_labels(wikitext)
      {:error, reason} -> add_problem(from_labels(wikitext), "#{@template_name}: #{reason}")
    end
  end

  # ── the 128 pages written as a label block ──────────────────────────────────

  defp from_labels(wikitext) do
    [_lead | rest] = sections = sections(wikitext)
    split = Enum.map(sections, &split_body(&1.body))
    pairs = for {labels, _prose} <- split, pair <- labels, do: pair
    {known, extra} = fields(pairs)

    page =
      %{
        blank()
        | extra_labels: extra,
          description_raw: description(split),
          sections: Enum.map(rest, &%{title: &1.title, body: String.trim(&1.body)}),
          changes_raw: changes_raw(rest),
          fandom_links: fandom_links(wikitext)
      }
      |> Map.merge(known)

    %{
      page
      | numbers: numbers(page.description_raw || ""),
        problems: problems(page, pairs)
    }
  end

  # `[[Категория:Заклинания]]` sits at the bottom of most pages, where it would
  # otherwise read as the continuation of the last label's value.
  defp sections(wikitext) do
    wikitext
    |> String.split("\n")
    |> Enum.reject(&Regex.match?(@category, &1))
    |> Enum.join("\n")
    |> Wikitext.sections()
  end

  # The description is the prose of whichever section carries the label block —
  # the lead on 127 pages, and the first heading on `Aura of Glory`, which opens
  # with `== Изменения фита на Сиале ==` before saying anything else.
  defp description(split) do
    labelled =
      Enum.find(split, fn {labels, _prose} ->
        Enum.any?(labels, fn {name, _value} -> name == "уровень заклинателя" end)
      end)

    {_labels, prose} = labelled || hd(split)
    blank_to_nil(prose)
  end

  @doc """
  Cuts one section body into its labels and the prose around them.

  Returns `{[{normalised_label, value}], prose}`. A label's value runs to the end
  of its paragraph — the next label line or a blank line — because that is how
  the pages that continue a value onto further lines actually write it:

      '''Существо начального уровня:''' Древний гигант
      *Тип: Атакующее существо
      *Класс брони: 36

  Reading the bullets as prose instead would drop a whole creature's stat block
  into the description and take its numbers with it.
  """
  @spec split_body(binary) :: {[{binary, binary}], binary}
  def split_body(body) do
    state =
      body
      |> String.split("\n")
      |> Enum.reduce(%{labels: [], prose: [], current: nil}, &body_line/2)
      |> close_label()

    prose = state.prose |> Enum.reverse() |> Enum.join("\n") |> String.trim()
    {Enum.reverse(state.labels), prose}
  end

  defp body_line(line, state) do
    case label_start(line) do
      {:ok, label, value} ->
        %{close_label(state) | current: {label, [value]}}

      :no ->
        cond do
          state.current && String.trim(line) == "" -> close_label(state)
          state.current -> %{state | current: append_line(state.current, line)}
          Regex.match?(@skipped_line, line) -> state
          true -> %{state | prose: [line | state.prose]}
        end
    end
  end

  defp append_line({label, lines}, line), do: {label, [line | lines]}

  defp close_label(%{current: nil} = state), do: state

  defp close_label(%{current: {label, lines}} = state) do
    value = lines |> Enum.reverse() |> Enum.join("\n") |> String.trim()

    labels =
      if value == "",
        do: state.labels,
        else: [{Wikitext.normalize_label(label), value} | state.labels]

    %{state | labels: labels, current: nil}
  end

  # A bold line is a label only when the page really wrote a colon after the name.
  # `Evard's black tentacles` sets three of its paragraphs in bold without one
  # (`'''Монстров''' тентакли бьют каждый раунд…`), and reading those as labels
  # named after their first word would be nonsense.
  defp label_start(line) do
    with true <- String.starts_with?(String.trim_leading(line), "'''"),
         [{label, value}] <- Wikitext.labels(line),
         true <- colon_after?(line, label) do
      {:ok, label, value}
    else
      _other -> :no
    end
  end

  # Both ways the wiki writes the colon — inside the bold and after it — plus the
  # two labels of `Mind fog` that close with `</c>` instead of `'''`.
  defp colon_after?(line, label) do
    Regex.match?(~r/#{Regex.escape(label)}\s*(?:'''|<\/c>)?\s*:/u, line)
  end

  defp fields(pairs) do
    known =
      for {field, name, _title} <- @label_fields,
          {label, value} <- pairs,
          label == name,
          reduce: %{} do
        acc -> Map.put_new(acc, raw_key(field), value)
      end

    taken = MapSet.new(@label_fields, fn {_field, name, _title} -> name end)

    extra =
      pairs
      |> Enum.reject(fn {label, _value} -> MapSet.member?(taken, label) end)
      |> Enum.reduce(%{}, fn {label, value}, acc -> Map.put_new(acc, label, value) end)
      |> Enum.sort()

    {known, extra}
  end

  defp raw_key(field), do: :"#{field}_raw"

  @list_item ~r/^\s*[*#](?![*#])/u

  @doc """
  Cuts a `== Изменение в заклинаниях ==` body into one item per statement.

  The sections are bullet lists whose items routinely continue underneath —
  a `<blockquote>` with the formula, a `**` sub-list — and all of that belongs to
  the bullet above it. Anything before the first bullet is an item of its own, so
  a section written as plain prose (`Mordenkainen's disjunction`) still yields
  exactly one item and nothing is lost.

  Items come back verbatim; the caller quotes them as they are.
  """
  @spec change_items(binary) :: [binary]
  def change_items(body) do
    body
    |> String.split("\n")
    |> Enum.reduce([], fn line, items ->
      cond do
        Regex.match?(@list_item, line) -> [[line] | items]
        items == [] and String.trim(line) == "" -> items
        items == [] -> [[line]]
        true -> [[line | hd(items)] | tl(items)]
      end
    end)
    |> Enum.map(fn lines -> lines |> Enum.reverse() |> Enum.join("\n") |> String.trim() end)
    |> Enum.reverse()
    |> Enum.reject(&(&1 == ""))
  end

  defp changes_raw(sections) do
    for section <- sections,
        section.title,
        Regex.match?(@changes_heading, Wikitext.normalize_label(section.title)),
        body = String.trim(section.body),
        body != "",
        do: %{title: String.trim(section.title), body: body}
  end

  # ── the one page written as a template ──────────────────────────────────────

  defp from_template(template, wikitext) do
    known =
      for {field, param} <- @template_fields,
          value = trimmed_param(template, param),
          into: %{},
          do: {raw_key(field), value}

    taken = Enum.map(@template_fields, fn {_field, param} -> param end)
    description = trimmed_param(template, "описание")

    extra =
      template.params
      |> Map.drop(["описание", "изменения", "ссылка" | taken])
      |> Enum.map(fn {key, value} -> {key, String.trim(value)} end)
      |> Enum.reject(fn {_key, value} -> value == "" end)
      |> Enum.sort()

    changes =
      case trimmed_param(template, "изменения") do
        nil -> []
        body -> [%{title: "изменения", body: body}]
      end

    page =
      %{
        blank()
        | extra_labels: extra,
          description_raw: description,
          changes_raw: changes,
          fandom_links: fandom_links(wikitext),
          template?: true
      }
      |> Map.merge(known)

    duplicates =
      for param <- template.duplicate_params,
          do: "#{@template_name}: parameter written twice: #{param}"

    %{
      page
      | numbers: numbers(description || ""),
        problems: duplicates ++ missing_labels(page)
    }
  end

  defp trimmed_param(template, param) do
    template.params |> Map.get(param, "") |> String.trim() |> blank_to_nil()
  end

  # ── numbers ─────────────────────────────────────────────────────────────────

  # A dice roll may be written with the count in front (`20d6`) or without it
  # (`d10 за каждые 10 уровней`), and on the Russian pages the `d` is routinely
  # the Cyrillic `д` — `Fireball` uses both spellings on the same page. The
  # lookbehind stops `4d6` from also yielding a bare `d6`.
  @dice ~r/(?<![\p{L}\p{N}])(\d*)[dд](\d+)/iu
  # A percentage may be written with a fraction — `3,4%`, `12,5%` — and cutting it
  # at the comma would leave the misleading `4%`.
  @percent ~r/(\d+(?:[.,]\d+)?)\s*%/u
  # `1-3` is a damage range, not a `-3` bonus, so a sign only counts when nothing
  # alphanumeric precedes it.
  @signed ~r/(?<![\p{L}\p{N}])([+\-−])(\d+)/u
  # `0,5 секунды`, `6.6 feet`. Both wikis write the separator both ways, and the
  # English thousands separator (`1,000 points`) is indistinguishable from a
  # fraction here — it occurs once in the whole corpus, on a page Siala does not
  # describe, and reading it as `1.000` costs nothing a pointer cares about.
  @decimal ~r/(?<![\p{L}\p{N}])(\d+)[.,](\d+)/u
  @integer ~r/(?<![\p{L}\p{N}])(\d+)(?!\d)/u

  @labelled_link ~r/\[https?:\/\/\S+\s+([^\]]*)\]/u
  @bare_link ~r/\[https?:\/\/\S+\]/u
  @markup_attribute ~r/[\p{L}-]+\s*=\s*"[^"]*"/u
  # `[[Image:Evards_tentacles.jpg|right|thumb|160px|…]]` — an embed's parameters
  # are markup, and `160px` is the one place a page number reaches the text.
  @image_embed ~r/\[\[\s*(?:file|файл|image|изображение)\s*:[^\]]*\]\]/iu

  @doc """
  Cuts struck-through patch history out of a value.

  Fandom records a change by striking the old value rather than removing it —
  `<s>will 1/2</s>`, `<del>3d6</del> ''6d6''` — so `<s>`, `<del>` and `<strike>`
  spans are the wiki's history, not its current answer. Everything outside them
  is left exactly as it was, tags and all.
  """
  @spec strip_struck(binary) :: binary
  @spec strip_struck(nil) :: nil
  def strip_struck(nil), do: nil
  def strip_struck(text), do: String.replace(text, @struck, " ")

  @doc """
  Every game number printed in `text`, deduplicated and ordered.

  Five shapes, each of them a literal on the page: `20d6`, `d10`, `+5`, `15%`
  and a bare quantity (`3`, `0.5`). Struck-through history is cut first, so
  vanilla's superseded `<del>3d6</del>` is not compared against Siala's present.

  Bare quantities used to be left out, on the argument that a round count, a
  caster level and a spell circle all look alike once the words around them are
  gone. Measured against the hand review of all 129 pages that cost more than it
  saved: the numbers the shard actually changed are routinely bare — `Divine
  power` 1 → 3 temporary hit points per level, `Time stop` 9 → 6 seconds, `Cure
  minor wounds` 4 → «4 + 1 за уровень». Collecting them points at 22 further
  pages, every one of which the review had already found changed by hand, and
  leaves all three pages it found unchanged — `Hold monster`, `Silence`, `Slow` —
  still unflagged. The reading cost is one number: the median disagreement grew
  from two numbers to three.

  This is the whole basis of `numeric_diff`: the Siala description is Russian and
  the vanilla one English, so the texts cannot be compared, but "vanilla says
  10d6 here and Siala says 20d6" survives translation intact.
  """
  @spec numbers(binary | nil) :: [binary]
  def numbers(nil), do: []

  def numbers(text) do
    text = normalize(text)

    dice = for [_, count, faces] <- Regex.scan(@dice, text), do: "#{count}d#{faces}"
    without_dice = Regex.replace(@dice, text, " ")

    percents = for [_, value] <- Regex.scan(@percent, without_dice), do: "#{decimal(value)}%"
    without_percents = Regex.replace(@percent, without_dice, " ")

    signs =
      for [_, sign, value] <- Regex.scan(@signed, without_percents),
          do: if(sign == "+", do: "+#{value}", else: "-#{value}")

    without_signs = Regex.replace(@signed, without_percents, " ")

    decimals =
      for [_, whole, fraction] <- Regex.scan(@decimal, without_signs), do: "#{whole}.#{fraction}"

    without_decimals = Regex.replace(@decimal, without_signs, " ")

    integers = for [_, value] <- Regex.scan(@integer, without_decimals), do: value

    (dice ++ percents ++ signs ++ decimals ++ integers)
    |> Enum.uniq()
    |> Enum.sort_by(&sort_key/1)
  end

  # Wiki markup carries digits of its own — an external link's URL, a table cell's
  # `style="width:120px"`, an image embed's `160px` — and none of them are game
  # numbers. The link's *text* survives, because that is the part a reader sees.
  defp normalize(text) do
    text
    |> strip_struck()
    |> String.replace(@image_embed, " ")
    |> String.replace(@labelled_link, " \\1 ")
    |> String.replace(@bare_link, " ")
    |> String.replace(@markup_attribute, " ")
    |> Wikitext.strip_links()
  end

  defp decimal(value), do: String.replace(value, ",", ".")

  # Dice first, then percents, then bonuses, then bare quantities; within a group
  # by the numbers themselves, so `4d6` sorts before `10d6` rather than after it.
  defp sort_key(number) do
    cond do
      match = Regex.run(~r/^(\d*)d(\d+)$/u, number) ->
        [_, count, faces] = match
        {0, String.to_integer(faces), int_or_zero(count), number}

      match = Regex.run(~r/^([\d.]+)%$/u, number) ->
        [_, value] = match
        {1, float(value), 0, number}

      Regex.match?(~r/^[+\-−]/u, number) ->
        {2, int_or_zero(String.slice(number, 1..-1//1)) * 1.0, 0, number}

      true ->
        {3, float(number), 0, number}
    end
  end

  defp int_or_zero(""), do: 0
  defp int_or_zero(digits), do: String.to_integer(digits)

  defp float(value) do
    {number, ""} = Float.parse(value)
    number
  end

  # ── the fields both wikis carry in a closed vocabulary ──────────────────────

  # Both wikis name the same eight schools, and the Siala pages print the English
  # name next to the Russian one on 128 of 129 pages — «Разрушение (Evocation)».
  # The English name is therefore read first and the Russian table is the fallback
  # for the one page that writes «трансмутация» alone; every Russian spelling in
  # it is corroborated by the pages that write both.
  @schools ~w(abjuration conjuration divination enchantment evocation illusion necromancy
              transmutation)

  @russian_schools %{
    "преграждение" => "abjuration",
    "вызывание" => "conjuration",
    "прорицание" => "divination",
    "зачарование" => "enchantment",
    "разрушение" => "evocation",
    "иллюзия" => "illusion",
    "иллюзии" => "illusion",
    "некромантия" => "necromancy",
    "трансмутация" => "transmutation"
  }

  @type reading(value) :: {:ok, value} | {:error, :absent | :struck_out | {:unknown, binary}}

  @doc """
  Reads a school of magic out of a `Школа` / `school` value of either wiki.

  Fails rather than guesses: a value that names two schools (`Balagarn's iron
  horn` before its struck history is cut) or none is `{:error, {:unknown, …}}`,
  and the caller prints it.
  """
  @spec school(binary | nil) :: reading(binary)
  def school(value) do
    with {:ok, text} <- plain(value) do
      case Enum.filter(@schools, &String.contains?(text, &1)) do
        [one] ->
          {:ok, one}

        _none_or_many ->
          case @russian_schools
               |> Enum.filter(&String.contains?(text, elem(&1, 0)))
               |> values() do
            [one] -> {:ok, one}
            _other -> {:error, {:unknown, text}}
          end
      end
    end
  end

  # `Стойкость (Fotritude)` misspells the English and `Cтойкость (Fortitude)`
  # opens with a Latin `C`, so neither spelling alone is enough — a value is read
  # if *either* half of it names a save.
  @save_words %{
    "fortitude" => :fortitude,
    "reflex" => :reflex,
    "will" => :will,
    "тойкост" => :fortitude,
    "рефлекс" => :reflex,
    "вол" => :will
  }

  # `harmless` is Fandom's way of saying the spell has no save to make; Siala
  # writes «Нет» for the same spells. `special`, `Особый` and `see below` name no
  # save and are not "no save" either — they are unread, and say so.
  @no_save ~w(none harmless нет)

  @doc """
  Reads a `Спасбросок` / `save` value into the set of saving throws it names.

  Only the throws, never the effect: Fandom writes `[[will]] negates` where Siala
  writes «Воля (Will)», and calling that a difference would be reading a
  convention, not a rule. An empty set is a spell that names no save.
  """
  @spec save(binary | nil) :: reading([:fortitude | :reflex | :will])
  def save(value) do
    with {:ok, text} <- plain(value) do
      named =
        @save_words
        |> Enum.filter(fn {word, _save} -> String.contains?(text, word) end)
        |> values()
        |> Enum.uniq()
        |> Enum.sort()

      cond do
        named != [] -> {:ok, named}
        text == "no" or Enum.any?(@no_save, &String.contains?(text, &1)) -> {:ok, []}
        true -> {:error, {:unknown, text}}
      end
    end
  end

  @doc """
  Reads a `Сопротивление Заклинанию` / `spellresistance` value as yes or no.

  `yes*` is a footnote on a yes. `special` is neither, and comes back unread.
  """
  @spec spell_resistance(binary | nil) :: reading(boolean)
  def spell_resistance(value) do
    with {:ok, text} <- plain(value) do
      case String.trim_trailing(text, "*") |> String.trim() do
        yes when yes in ~w(yes да) -> {:ok, true}
        no when no in ~w(no none нет) -> {:ok, false}
        other -> {:error, {:unknown, other}}
      end
    end
  end

  @doc """
  Reads a spell circle written as a plain number.

  Both wikis keep these as strings and both write worse than numbers into them —
  `epic`, `6 (''special'')`, `<s>2</s> 3`. Struck history is cut first (that one
  *is* a number, the current one); anything else that is not digits comes back
  unread, because turning `epic` into a circle would be inventing one.
  """
  @spec level(binary | nil) :: reading(non_neg_integer)
  def level(value) do
    with {:ok, text} <- plain(value) do
      if Regex.match?(~r/^\d+$/, text),
        do: {:ok, String.to_integer(text)},
        else: {:error, {:unknown, text}}
    end
  end

  # The six casting classes as the Siala pages name them, longest first so that
  # «Колдун / Волшебник» is read before «Колдун». Fandom keeps sorcerer and wizard
  # in one `magelevel` and one `sorcerer/wizard spell list` category, and Siala
  # writes them as one label for the same reason — hence the shared `mage`. The
  # Russian spellings are the ones `priv/rules/siala_41/classes.json` carries.
  @caster_classes [
    {"колдун / волшебник", :mage},
    {"священник", :cleric},
    {"рейнджер", :ranger},
    {"волшебник", :mage},
    {"паладин", :paladin},
    {"колдун", :mage},
    {"друид", :druid},
    {"бард", :bard}
  ]

  @doc """
  Reads an `Уровень Заклинателя` value into `{class, circle}` pairs.

  The label is written as a comma- or semicolon-separated list of a class and its
  circle — `Бард 2, Священник 2, Колдун / Волшебник 2`. A part that does not read
  that way fails the whole value: a half-read caster list is a spell that looks
  unavailable to a class it is available to.
  """
  @spec circles(binary | nil) :: reading([{atom, non_neg_integer}])
  def circles(value) do
    with {:ok, text} <- plain(value) do
      text
      |> String.split([",", ";"])
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce_while({:ok, []}, fn part, {:ok, pairs} ->
        case circle(part) do
          {:ok, pair} -> {:cont, {:ok, [pair | pairs]}}
          :no -> {:halt, {:error, {:unknown, part}}}
        end
      end)
      |> merge_circles(text)
    end
  end

  defp circle(part) do
    with [_, name, circle] <- Regex.run(~r/^(.*?)\s+(\d+)$/u, part),
         {_spelling, class} <- Enum.find(@caster_classes, &(elem(&1, 0) == name)) do
      {:ok, {class, String.to_integer(circle)}}
    else
      _other -> :no
    end
  end

  # `Колдун / Волшебник` and a second, differently numbered mention of either
  # would be two answers to one question; that has never happened, and if it does
  # the value is unread rather than silently halved.
  defp merge_circles({:ok, pairs}, text) do
    unique = pairs |> Enum.uniq() |> Enum.sort()

    if length(Enum.uniq_by(unique, &elem(&1, 0))) == length(unique),
      do: {:ok, unique},
      else: {:error, {:unknown, text}}
  end

  defp merge_circles({:error, reason}, _text), do: {:error, reason}

  # Everything the readers share: history cut, markup rendered away, folded to
  # lower case so that `Нет` and `нет` are one answer. A value that is nothing but
  # struck history says nothing at all, which is not the same as being absent.
  defp plain(nil), do: {:error, :absent}

  defp plain(value) do
    case value
         |> strip_struck()
         |> Wikitext.strip_links()
         |> String.trim()
         |> String.downcase() do
      "" -> if String.trim(value) == "", do: {:error, :absent}, else: {:error, :struck_out}
      text -> {:ok, text}
    end
  end

  defp values(pairs), do: Enum.map(pairs, &elem(&1, 1))

  # ── links and problems ──────────────────────────────────────────────────────

  @fandom_link ~r/\[https?:\/\/nwn\.(?:fandom\.com|wikia\.com)\/wiki\/([^\s\]?]+)[^\s\]]*\s+([^\]]*)\]/u

  @doc """
  Fandom page titles the page links to as "the English wiki".

  Restricted to links whose text says so: `Energy drain` also links five other
  Fandom spells from a sentence about what protects against it, and reading those
  as "this page is about them" would be wrong. A `?so=search` query string is
  dropped — `Отражение` links its counterpart both with and without one.
  """
  @spec fandom_links(binary) :: [binary]
  def fandom_links(wikitext) do
    for [_, target, text] <- Regex.scan(@fandom_link, wikitext),
        String.contains?(text, "англояз"),
        uniq: true,
        do: target |> String.replace("_", " ") |> URI.decode()
  end

  defp problems(page, pairs) do
    missing_labels(page) ++ broken_bold(pairs)
  end

  defp missing_labels(page) do
    for {field, _name, title} <- @label_fields,
        field in @required_labels,
        is_nil(Map.fetch!(page, raw_key(field))),
        do: "label missing: #{title}"
  end

  # `Mind fog` closes two labels with `</c>`, which leaves the stray tag at the
  # head of the value. It is kept there rather than trimmed away: a snapshot that
  # quietly repairs its source stops being diffable against it.
  defp broken_bold(pairs) do
    for {label, value} <- pairs,
        String.contains?(value, "</c>"),
        do: "label closed with </c> instead of ''': #{label}"
  end

  defp add_problem(page, problem), do: %{page | problems: page.problems ++ [problem]}

  defp blank do
    %{
      caster_level_raw: nil,
      initial_level_raw: nil,
      school_raw: nil,
      descriptors_raw: nil,
      components_raw: nil,
      range_raw: nil,
      area_raw: nil,
      duration_raw: nil,
      save_raw: nil,
      spell_resistance_raw: nil,
      shamanism_raw: nil,
      extra_labels: [],
      description_raw: nil,
      numbers: [],
      sections: [],
      changes_raw: [],
      fandom_links: [],
      template?: false,
      problems: []
    }
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
