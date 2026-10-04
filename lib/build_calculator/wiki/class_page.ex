defmodule BuildCalculator.Wiki.ClassPage do
  @moduledoc """
  Reads one Fandom class page into the fields a build calculator needs.

  Class pages carry no template, so there are two sources of truth on the page and
  they are read separately:

    * **bold labels** in the lead (`'''Hit die:''' d10`, `'''Base attack bonus:'''
      +3/4 levels`, `'''Primary saving throw(s):''' [[fortitude]]`), written in
      half a dozen punctuation styles across the 23 pages, plus — on the red
      dragon disciple, the one page that uses no labels at all — a two-column
      table saying the same thing;
    * the **level progression table**, from which the BAB type and the save
      progressions are recomputed (BAB equal to the level is high, ¾ of it middle,
      ½ low; a save reaching `2 + level/2` is good, `level/3` poor — the same
      arithmetic holds for 20-, 10- and 5-level classes).

  When the two disagree the record is **not** silently reconciled: both readings
  are kept, `status` becomes `"conflict"` and `conflict_note` says what differs.
  Picking a winner is a human's call (CLAUDE.md §3).

  Anything that does not reduce to a number stays verbatim in a `*_raw` field,
  wiki links included, so it can be diffed against the page it came from.

  ## `primary_ability_raw` is a third kind of reading

  Fandom has no `'''Primary ability:'''` label — the phrase does not occur on
  any of the 23 pages. The seven classes that cast spells name it inside
  `'''Spellcasting:'''` instead, right after the arcane/divine tag, as
  `[[wisdom]]-based` (followed by "a base wisdom score of 10 + the spell's
  level is required…"). Reading it is therefore neither a whole label (like
  `hit_die_raw`) nor a second source to reconcile against a table (like BAB
  and saves) — it is a narrow regex read *inside* one specific label's
  already-captured value, scoped there on purpose: "-based" also shows up
  describing someone else's class (a paladin page note on "charisma-based
  [[bard]]…builds", about multiclass dips) and describing a non-caster's own
  melee playstyle (the monk's notes weigh "Wisdom-based" against
  "dexterity-based" unarmed styles, on a page that states two sentences
  earlier that monks do not cast spells at all). A page-wide search would have
  read both as this class's primary ability; neither is. The other 16 classes
  carry no `Spellcasting:` label whatsoever, so `primary_ability_raw` stays
  `nil` for them — that is the page saying "not a caster", not a parsing gap.

  ## `Unavailable feats` is a list, and its own sentence is not part of it

  The label carries the feats a class **removes from the general feat list**
  («These `[[general feat]]`s cannot be selected when taking a level of bard»),
  and the sentence explaining that is inside the same label value, after a
  `<br />`. That sentence links `[[general feat]]` — a real page, and not a feat
  — so reading the whole value for links puts a twenty-fourth "feat" into every
  one of the 23 classes. `unavailable_feat_targets/1` therefore cuts at the first
  `<br` and reads links only out of the list itself. Resolving those targets to
  feat ids is the caller's job, exactly as it is for `feat_grants/1`: it needs
  the feat index, which one class page cannot have.

  ## `Proficiencies` names more grants, off a label `feat_grants/1` never reads

  A class's starting armour, shield and weapon proficiencies are not in the
  progression table at all — with one accidental exception (`wizard`'s table
  row happens to list `[[weapon proficiency (wizard)]]` next to `scribe scroll`
  and `summon familiar`) they live only in the `'''Proficiencies:'''` label,
  which `feat_grants/1` never looks at. `proficiency_targets/1` reads that
  label the same way `unavailable_feat_targets/1` reads its own — link targets,
  verbatim, resolving left to the caller — but needs no `<br` cut: none of the
  23 pages append a sentence after the list the way `Unavailable feats` does.

  What it cannot do alone is name a proficiency the label states without a
  link — `dwarven defender` and `blackguard` both write "all `[[armor]]`",
  linking the general article rather than any one tier, and `blackguard`
  writes "shields" as a bare word that was never a link to begin with. Those
  two classes still own every tier: the two feats' own pages list them under
  `classN` (`promote_feat/2`'s `granted_by`), so the caller reads both sides
  before deciding a class has no armor proficiency at all — see
  `Mix.Tasks.Wiki.Parse.proficiency_grants/3`.

  ## The "Feats" column holds two different things

  The progression table's feats column mixes a **slot** the player fills himself
  (`bonus feat`, `2 bonus feats`, `wizard bonus feat`) with the feats the class
  simply **hands out** (`[[rallying cry]], [[heroic shield]]`). Reading the two
  as one list is what `feat_grants/1` exists to prevent: a slot put into the
  granted list would have the class hand out a feat that does not exist, and a
  grant left out of it makes the calculator demand a feat the character already
  owns (CLAUDE.md §6 — the Dwarven Defender/Toughness bug).

  ⚠️ И у эпической таблицы red dragon disciple этой колонки нет вовсе — там она
  называется `Bonus feats`, а не `Feats`, и несёт числительное («first» …
  «fifth»), а не слово «bonus feat». Это отдельная роль `:bonus_feats`
  (`@column_roles`) и отдельное поле строки `bonus_feat_rank_raw`, читаемые
  и объясняемые у `bonus_feat_levels/1` — до этой правки `epic_bonus_feat_levels`
  красного дракона было `[]` вместо пяти уровней (AGENT_QUEUE.md §1.13).

  ⚠️ И слот бывает не один: ячейка называет **сколько** их
  (`|35th ||align=left|2 bonus feats` — рейнджер), поэтому рядом с
  `bonus_feat_levels` стоит `bonus_feat_counts` — `%{уровень => сколько}`
  и только для уровней, где их больше одного. Разбор — у `bonus_feat_slots/1`.

  ## Хит-дайс бывает не числом, а функцией уровня класса

  `hit_die` читается из bold-лейбла и потому умеет ровно одно число — у 22
  классов из 23 так и есть. Двадцать третий, `red dragon disciple`, пишет
  в том же лейбле диапазон (`d6 to d12 (see [[hit die increase]])`), который
  числом не является и остаётся `nil` плюс `hit_die_raw`; настоящее значение
  у него стоит **отдельной колонкой на каждой строке таблицы прогрессии**.
  Её и читает `hit_die_by_class_level/3` — см. там же, откуда берётся
  ступень `11 → d12`, которой в основной таблице нет вовсе, и почему
  недочитанная эпическая ступень обязана обнулить всю шкалу, а не молча
  растянуть последнюю прочитанную (AGENT_QUEUE.md 3.37).
  """

  alias BuildCalculator.Wiki.Requirements
  alias BuildCalculator.Wiki.Wikitable
  alias BuildCalculator.Wiki.Wikitext

  @type progression_row :: %{
          level: pos_integer,
          bab: integer | nil,
          fort: integer | nil,
          ref: integer | nil,
          will: integer | nil,
          feats_raw: binary | nil,
          bonus_feat_rank_raw: binary | nil,
          hit_die_raw: binary | nil,
          hp: integer | nil,
          hp_raw: binary | nil,
          spells_per_day: [{binary, non_neg_integer}] | nil,
          spells_known: [{binary, non_neg_integer}] | nil,
          extra: [{binary, binary}]
        }

  @label_fields %{
    hit_die: ["hit die", "hit dice"],
    skill_points: ["skill point", "skill points"],
    proficiencies: ["proficiencies"],
    class_skills: ["skills", "class skills"],
    unavailable_feats: ["unavailable feats"],
    primary_saves: ["primary saving throw", "high saves"],
    bab: ["base attack bonus", "base attack"],
    alignment: ["alignment restrictions", "alignment restriction", "alignment"],
    requirements: ["requirements"],
    description: ["description"],
    spellcasting: ["spellcasting"],
    # Защитный запасной путь: ни одна из 23 страниц классов на Fandom такой
    # bold-лейбл не пишет (проверено по всему кэшу — фраза "primary ability" не
    # встречается ни разу), поэтому этот путь сегодня всегда пуст. Настоящий
    # источник — `primary_ability/1`, вытаскивающий характеристику из прозы
    # лейбла `Spellcasting:`. Ключ оставлен на случай, если вики когда-нибудь
    # заведёт явный лейбл — тогда он выигрывает первым (см. `parse/1`).
    primary_ability: ["primary ability"]
  }

  @column_roles %{
    level: ["lvl", "level", "class level"],
    bab: ["bab", "ba", "base attack bonus", "base attack"],
    fort: ["fort", "fortitude"],
    ref: ["ref", "reflex"],
    will: ["will"],
    feats: ["feats", "feat"],
    # Эпическая таблица Red dragon disciple — единственная из 23 страниц, где
    # колонка слотов бонусных фитов называется не «Feats», а буквально «Bonus
    # feats» (см. `bonus_feat_levels/1` — там же почему её ячейки не «bonus
    # feat», а порядковое числительное). Роль отдельная от `:feats` и не
    # расширяет его алиасы: сверено по всем 23 страницам (baseline-прогон
    # ДО этой правки, AGENT_QUEUE.md §1.13) — ни одна колонка ни одного из
    # остальных 22 классов, ни в основной, ни в эпической таблице, «bonus
    # feats» не называется, так что добавление этой роли не меняет чтение
    # ни одного из них.
    bonus_feats: ["bonus feats"],
    # Та же пара имён, что у одноимённого bold-лейбла (`@label_fields`), и та же
    # причина держать роль отдельной: колонка есть ровно у одной страницы из 23
    # (`red dragon disciple`, проверено обходом всего кэша — `Hit die` как
    # заголовок колонки таблицы прогрессии больше не встречается нигде), и до
    # этой правки её ячейки оседали в `extra` строки. Читается
    # `hit_die_by_class_level/3`.
    hit_die: ["hit die", "hit dice"],
    hp: ["hp", "hp range", "hit points"]
  }

  # The seven casting classes put their slots in a `!colspan=10|Base spells per
  # day` header stacked over `!0 !1st … !9th`, which `columns/1` flattens into
  # "Base spells per day / 3rd". Both halves have to match for a column to count,
  # so a table that renames either one falls back into `extra` instead of being
  # misread.
  @spell_groups %{
    "base spells per day" => :spells_per_day,
    "spells per day" => :spells_per_day,
    "known spells" => :spells_known,
    "spells known" => :spells_known
  }

  @spell_circle ~r/^(\d)(?:st|nd|rd|th)?$/
  @spell_column ~r{^(.*?)\s*/\s*([^/]*)$}

  # Hyphen-minus and em dash are what the pages actually use; the other two are
  # tolerated so a copy-edit cannot silently turn "no slot" into a leftover.
  @dashes ["-", "–", "—", "−"]

  # Every spelling of a bonus-feat slot on the 23 pages: `bonus feat`,
  # `2 bonus feats`, `special bonus feat`, `wizard bonus feat` and the champion
  # of Torm's `[[:Category:Champion of Torm bonus feats|bonus feat]]`. All of
  # them are a slot, never a feat.
  #
  # The two captures are what `bonus_feat_mentions/1` reads and what
  # `Regex.match?/2` in `fragment/3` ignores: **how many** slots the cell names
  # (`2 bonus feats` — the only cell in the corpus that says a number) and
  # whether it said "feats" without one, which is a shape nothing can count.
  @bonus_feat ~r/(?:(\d+)\s+)?\bbonus feat(s?)\b/i

  # A link into another namespace is never a feat. The champion of Torm's slot is
  # written as a category link, which is caught by @bonus_feat as well — this is
  # the belt to that pair of braces.
  @not_a_page ~r/^\s*(:|(category|image|file|template|help|special)\s*:)/i

  # Где на самом деле напечатана первичная характеристика заклинателя: не своим
  # лейблом, а внутри прозы `'''Spellcasting:'''`, сразу за arcane/divine-тегом —
  # `[[wisdom]]-based (a base wisdom score of 10 + the spell's level is
  # required…)`. Список из шести характеристик — намеренно закрытый, а не «любое
  # слово перед -based»: на страницах встречается «class-based» (Wizard, про
  # генератор луты) и «ki-based» (Monk, про его собственную энергию) — ни то,
  # ни другое не характеристика, и открытый список подхватил бы оба.
  @primary_ability ~r/(\[\[(?:strength|dexterity|constitution|intelligence|wisdom|charisma)\]\])-based/iu

  @doc """
  Parses a class page.

  Returns a map of parsed fields plus `problems` — a list of human-readable
  strings for everything the page did not yield, which the caller is expected to
  report rather than swallow.
  """
  @spec parse(binary) :: map
  def parse(wikitext) do
    sections = Wikitext.sections(wikitext)
    [lead | _] = sections
    labels = labels(lead)

    progression = progression(sections)
    epic = epic_progression(sections, progression)

    table_bab = bab_from_table(progression)
    table_saves = saves_from_table(progression)
    label_bab = bab_from_label(labels[:bab])
    label_saves = saves_from_label(labels[:primary_saves])

    conflicts = conflicts(table_bab, label_bab, table_saves, label_saves)

    %{
      hit_die: hit_die(labels[:hit_die]),
      hit_die_raw: labels[:hit_die],
      hit_die_by_class_level: hit_die_by_class_level(sections, progression, epic),
      skill_points: skill_points(labels[:skill_points]),
      skill_points_raw: labels[:skill_points],
      bab_progression: table_bab || label_bab,
      bab_progression_label: label_bab,
      bab_progression_raw: labels[:bab],
      saves: table_saves || label_saves,
      saves_label: label_saves,
      saves_raw: labels[:primary_saves],
      alignment_restriction_raw: labels[:alignment],
      requirements_raw: requirements(sections, labels),
      proficiencies_raw: labels[:proficiencies],
      proficiency_targets: proficiency_targets(labels[:proficiencies]),
      class_skills_raw: labels[:class_skills],
      unavailable_feats_raw: labels[:unavailable_feats],
      unavailable_feat_targets: unavailable_feat_targets(labels[:unavailable_feats]),
      spellcasting_raw: labels[:spellcasting],
      primary_ability_raw: labels[:primary_ability] || primary_ability(labels[:spellcasting]),
      max_level: progression && progression |> List.last() |> Map.fetch!(:level),
      bonus_feat_levels: bonus_feat_levels(progression),
      epic_bonus_feat_levels: bonus_feat_levels(epic),
      bonus_feat_counts: bonus_feat_counts(progression),
      epic_bonus_feat_counts: bonus_feat_counts(epic),
      # Both tables are keyed by *class* level, so the two grant lists share one
      # key space and are read together.
      feat_grants: feat_grants((progression || []) ++ (epic || [])),
      progression: progression,
      epic_progression: epic,
      extra_labels: labels[:__extra__],
      conflicts: conflicts,
      problems: problems(labels, progression, epic, sections)
    }
  end

  # ── labels ────────────────────────────────────────────────────────────────

  # Bold labels win over the lead's two-column tables: on the red dragon disciple
  # page "Skills:" means class skills as a bold label and the lore requirement as
  # a table row, and only the former belongs in `class_skills_raw`.
  defp labels(lead) do
    bold = lead.body |> Wikitext.labels() |> Enum.map(fn {l, v} -> {normalize(l), v} end)
    from_tables = lead.body |> Wikitable.find_all() |> Enum.flat_map(&definition_rows/1)

    pairs = bold ++ from_tables

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

  # `! Hit die: | d10` — the shape the red dragon disciple page uses instead of
  # bold labels. Only header/value pairs qualify, so real data tables are ignored.
  defp definition_rows(source) do
    source
    |> Wikitable.parse()
    |> Map.fetch!(:rows)
    |> Enum.flat_map(fn
      %{cells: [%{header?: true, text: label}, %{header?: false, text: value}]} ->
        if String.ends_with?(label, ":"), do: [{normalize(label), value}], else: []

      _row ->
        []
    end)
  end

  # Every class names its bonus feat list after itself ("Fighter bonus feats"),
  # so those all collapse onto one key; the rest is the shared normalisation.
  defp normalize(label) do
    name = Wikitext.normalize_label(label)

    if Regex.match?(~r/bonus feats?$/, name), do: "bonus feats", else: name
  end

  defp requirements(sections, labels) do
    section =
      Enum.find(sections, fn s -> s.title && normalize(s.title) == "requirements" end)

    case section do
      nil -> labels[:requirements]
      %{body: body} -> blank_to_nil(String.trim(body))
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # ── scalar readings of a label ────────────────────────────────────────────

  # `d10` only. The red dragon disciple's "d6 to d12 (see hit die increase)" is a
  # range, and a range is not a number — it stays `nil` plus the raw string.
  defp hit_die(nil), do: nil

  defp hit_die(value) do
    case Regex.run(~r/^d(\d+)$/, Wikitext.strip_links(value)) do
      [_, digits] -> String.to_integer(digits)
      nil -> nil
    end
  end

  @doc """
  Хит-дайс как **функция уровня класса**: ступени `[{from, die}]` или `nil`.

  `nil` у 22 классов из 23, и это не пропуск: у них хит-дайс — одно число,
  оно стоит bold-лейблом (`hit_die`), а колонки в таблице прогрессии нет
  вовсе. Ступени появляются ровно там, где страница печатает хит-дайс
  **построчно**, то есть сегодня у одного `red dragon disciple`.

  Читается из двух мест одной и той же страницы, и оба — прямые значения,
  а не вывод:

    * **колонка `Hit die` основной таблицы** — `d6` на классовых уровнях 1–3,
      `d8` на 4–5, `d10` на 6–10 (`fandom:Red dragon disciple`, revid 71919);
    * **bold-лейбл `Hit die:` эпического раздела** (`d12`) на уровне, с которого
      начинается эпическая таблица класса (11). Уровень берётся из первой её
      строки, а не из `max_level + 1`: это тот же вопрос «с какого уровня»,
      и отвечать на него арифметикой, когда рядом стоит само число, значило бы
      завести второй источник.

  Обе половины независимо подтверждает третья страница — `fandom:Hit die
  increase`, где та же шкала лежит таблицей целиком (`1 → d6, 4 → d8, 6 → d10,
  11 → d12`) плюс фраза «This change is not retroactive», из которой следует,
  что ступень применяется к уровню, на котором взята, а не задним числом. Её мы
  **не читаем** (это страница фита, у неё свой парсер и таблица внутри
  параметра шаблона) — она сверка, а не второй механизм.

  ⚠️ **Растущий хит-дайс без эпической ступени даёт `nil` целиком, а не
  усечённую шкалу.** Последняя ступень по построению покрывает всё, что выше
  неё, поэтому шкала `[{1,6},{4,8},{6,10}]` тихо назначила бы `d10` и 11-му
  уровню класса, и 31-му — то есть выдумала бы число там, где страница молчит.
  Отказ целиком возвращает поведение к сегодняшнему (HP билда не считается,
  причина названа), а сам факт уезжает в `problems`, то есть в отчёт
  `mix wiki.parse`. Сегодня эта ветка не срабатывает ни разу.

  ⚠️ Требование эпической ступени стоит **только там, где дайс растёт**:
  колонка с одним и тем же числом во всех строках — это тот же самый один
  хит-дайс, что у лейбла, и спрашивать с неё продолжение незачем.
  """
  @spec hit_die_by_class_level([map], [progression_row] | nil, [progression_row] | nil) ::
          [{pos_integer, pos_integer}] | nil
  def hit_die_by_class_level(sections, progression, epic) do
    case hit_die_column(progression) do
      {:ok, [_single] = flat} ->
        flat

      {:ok, growing} ->
        case epic_hit_die_step(sections, epic) do
          nil -> nil
          step -> merge_steps(growing ++ [step])
        end

      _absent_or_unreadable ->
        nil
    end
  end

  # `:absent` — колонки нет вовсе (22 класса); `:unreadable` — колонка есть,
  # но хотя бы одна её ячейка не читается как `dN`. Второе обнуляет всё чтение,
  # а не одну строку: последняя ступень покрывает всё, что выше неё, поэтому
  # пропущенная строка не осталась бы без ответа — она молча получила бы чужой.
  defp hit_die_column(nil), do: :absent

  defp hit_die_column(rows) do
    read = for row <- rows, do: {row.level, hit_die(row.hit_die_raw)}

    cond do
      Enum.all?(read, fn {_level, die} -> is_nil(die) end) -> :absent
      Enum.any?(read, fn {_level, die} -> is_nil(die) end) -> :unreadable
      true -> {:ok, merge_steps(read)}
    end
  end

  # Эпическое продолжение шкалы: число — из bold-лейбла эпического раздела,
  # уровень — из первой строки эпической таблицы. Нужны оба; одно без другого
  # ступени не составляет.
  defp epic_hit_die_step(sections, epic) do
    dice =
      for section <- sections,
          epic?(section),
          {label, value} <- Wikitext.labels(section.body),
          normalize(label) in @label_fields.hit_die,
          die = hit_die(value),
          uniq: true,
          do: die

    case {dice, epic} do
      {[die], [%{level: level} | _]} -> {level, die}
      _no -> nil
    end
  end

  # Соседние равные значения — одна ступень. Читается по строкам таблицы,
  # то есть уже в порядке уровней.
  defp merge_steps(pairs) do
    pairs
    |> Enum.reduce([], fn
      {_level, die}, [{_from, die} | _] = acc -> acc
      {level, die}, acc -> [{level, die} | acc]
    end)
    |> Enum.reverse()
  end

  defp skill_points(nil), do: nil

  defp skill_points(value) do
    case Regex.run(~r/^(\d+)\s*\+/, Wikitext.strip_links(value)) do
      [_, digits] -> String.to_integer(digits)
      nil -> nil
    end
  end

  defp bab_from_label(nil), do: nil

  defp bab_from_label(value) do
    text = Wikitext.strip_links(value)

    cond do
      Regex.match?(~r{\+\s*1\s*/\s*level}i, text) -> "high"
      Regex.match?(~r{\+\s*3\s*/\s*4}, text) -> "medium"
      Regex.match?(~r{\+\s*1\s*/\s*2}, text) -> "low"
      true -> nil
    end
  end

  defp saves_from_label(nil), do: nil

  defp saves_from_label(value) do
    text = value |> Wikitext.strip_links() |> String.downcase()

    saves =
      Map.new([{:fort, "fortitude"}, {:ref, "reflex"}, {:will, "will"}], fn {key, word} ->
        {key, if(Regex.match?(~r/\b#{word}\b/, text), do: "good", else: "poor")}
      end)

    if Enum.any?(saves, fn {_key, value} -> value == "good" end), do: saves
  end

  # Единственный настоящий источник поля: не отдельный лейбл (его на Fandom нет
  # ни у одного из 23 классов), а подстрока внутри `Spellcasting:`. Вызывающая
  # сторона обязана передавать именно значение ЭТОГО лейбла, а не всю страницу —
  # поиск по всей странице подхватил бы чужие упоминания «-based»: заметка на
  # странице паладина про «charisma-based [[bard]]…builds» — это чужой класс
  # (бард/соркерер в мультиклассе), а заметки на странице монаха про
  # «Wisdom-based» и «dexterity-based» стили безоружного боя — это его СИЛА
  # атаки/КД трюков, а не заклинания (страница монаха прямо говорит двумя
  # предложениями раньше: «they don't cast spells»). Ни то, ни другое не
  # является первичной характеристикой каста этого класса, и то, что оба они —
  # реальный текст с реальной вики, а не выдумка, — ровно то, что делает эту
  # ошибку опасной, если не сузить поиск до лейбла.
  #
  # Внутри самого лейбла у всех семи кастеров ровно одно упоминание — если
  # страница когда-нибудь начнёт называть внутри одного лейбла две РАЗНЫЕ
  # характеристики, это настоящее расхождение источника, а не техническая
  # накладка (два прочтения одной и той же характеристики в разном регистре —
  # не расхождение). Выбирать между двумя разными парсер не имеет права
  # (CLAUDE.md §3), поэтому в этом случае поле остаётся `nil`, а не берёт первое
  # совпадение молча.
  defp primary_ability(nil), do: nil

  defp primary_ability(value) do
    case value |> abilities_named() |> Enum.uniq_by(&String.downcase/1) do
      [ability] -> ability
      _none_or_disagreeing -> nil
    end
  end

  defp abilities_named(value) do
    for [_match, ability] <- Regex.scan(@primary_ability, value), do: ability
  end

  @doc """
  The link targets in the `Unavailable feats` label — the list, not its sentence.

  The value is a comma-separated list of links followed by the wiki's own
  explanation of what the list means, and the explanation **also links**:

      [[divine might]], [[divine shield]], [[extra turning]], [[weapon specialization]]
      <br />These [[general feat]]s cannot be selected when taking a level of bard.

  So the value is cut at the first `<br` before any link is read. All 23 pages
  put the sentence there and spell the break `<br />`; `harper scout` adds a
  second one («''The inclusion of martial weapon proficiency in this list is
  likely a bug.''»), which the same cut removes. Reading the value whole would
  hand every class `general feat` as a feat it forbids — a page that exists, so
  nothing downstream would report it as unresolvable.

  Targets come back verbatim, in page order, duplicates and all: turning one
  into a feat id needs the feat index and belongs to the caller.
  """
  @spec unavailable_feat_targets(binary | nil) :: [binary]
  def unavailable_feat_targets(nil), do: []

  def unavailable_feat_targets(value) do
    value
    |> String.split("<br", parts: 2)
    |> hd()
    |> Wikitext.link_targets()
    |> Enum.map(&String.trim/1)
  end

  @doc """
  The link targets in the `Proficiencies` label — armour, shield and weapon
  feats a class starts with, whatever the label happens to link.

  Unlike `unavailable_feat_targets/1` there is nothing to cut first: none of
  the 23 pages append a sentence after the list. What the value *can* hold is a
  link that is not a proficiency feat at all — `all [[armor]]` (`dwarven
  defender`, `blackguard`) links the general article, not any one tier — and a
  bare word that was never a link (`blackguard`'s trailing "shields", every
  page's "robes"). Both are the caller's problem, exactly as an unresolved
  `feat_grants/1` target is: a class page alone has no feat index to check a
  target against, real or not.
  """
  @spec proficiency_targets(binary | nil) :: [binary]
  def proficiency_targets(nil), do: []

  def proficiency_targets(value) do
    value |> Wikitext.link_targets() |> Enum.map(&String.trim/1)
  end

  # ── readings taken from the progression table ─────────────────────────────

  # A class's BAB type is visible in the last row: equal to the level is high,
  # three quarters of it middle, half low. Holds for 20-, 10- and 5-level tables.
  defp bab_from_table(nil), do: nil

  defp bab_from_table(rows) do
    last = List.last(rows)

    cond do
      is_nil(last.bab) -> nil
      last.bab == last.level -> "high"
      last.bab == div(last.level * 3, 4) -> "medium"
      last.bab == div(last.level, 2) -> "low"
      true -> nil
    end
  end

  defp saves_from_table(nil), do: nil

  defp saves_from_table(rows) do
    last = List.last(rows)
    good = 2 + div(last.level, 2)
    poor = div(last.level, 3)

    saves =
      Map.new([:fort, :ref, :will], fn key ->
        {key,
         case Map.fetch!(last, key) do
           ^good -> "good"
           ^poor -> "poor"
           _other -> nil
         end}
      end)

    if Enum.all?(saves, fn {_key, value} -> value end), do: saves
  end

  defp bonus_feat_levels(nil), do: nil

  defp bonus_feat_levels(rows), do: for({level, _count} <- bonus_feat_slots(rows), do: level)

  # Только уровни, где слот НЕ один, — то есть сегодня ровно одна запись во всём
  # корпусе (`ranger` 35). Пустая карта не пишется в файл вовсе: «страница нигде
  # не назвала числа» и «на этом уровне слот один» — одно и то же утверждение,
  # и второй ключ у 22 классов из 23 был бы шумом (ровно тот же довод, что
  # у `granted_feat_ranks_json/1` в `mix wiki.parse`).
  defp bonus_feat_counts(nil), do: nil

  defp bonus_feat_counts(rows) do
    for {level, count} <- bonus_feat_slots(rows), count > 1, into: %{}, do: {level, count}
  end

  # Обычная страница называет слот словами («bonus feat» внутри `feats_raw`,
  # regex `@bonus_feat`), но red dragon disciple ту же самую вещь на эпической
  # таблице пишет через отдельную колонку `Bonus feats` (роль `:bonus_feats`,
  # `@column_roles`), а внутри неё — не слово, а порядковое числительное:
  # «first» на 14-м уровне класса, «second» на 18-м, … «fifth» на 30-м. Пустая
  # ячейка (`&nbsp;`) — уровень без слота, значит `bonus_feat_rank_raw` уже
  # `nil` (см. `row/2`), а непустая — сам факт наличия слота: значение
  # числительного не несёт отдельного смысла и нигде дальше не читается,
  # только то, что оно НЕ пусто. Источник (`fandom:Red dragon disciple`,
  # revid 71919): «The epic dragon disciple gains a bonus feat every four
  # levels. In other words, at levels 14, 18, 22, 26, and 30.» — ровно то, что
  # эта строка обязана вернуть (AGENT_QUEUE.md §1.13; до этой правки
  # `epic_bonus_feat_levels` красного дракона было `[]`, а игрок терял все
  # пять эпических бонусных слотов молча).
  #
  # ⚠️ ЧТО кладётся в открывшийся слот эта функция не решает и решать не
  # обязана: пул уже читается независимо, с каждой ОТДЕЛЬНОЙ страницы фита
  # через `bonus15=red dragon disciple` (`promote_feat/2` → `bonus_for`,
  # `Rules.FeatSlots.accepts_kind?/2` для `:class_bonus`) и у всех 12 фитов
  # красного дракона уже совпадает слово в слово со списком со страницы класса
  # («Epic bonus feats:» armor skin, automatic quicken/silent/still spell,
  # epic damage reduction, epic prowess, epic reputation, epic spell focus,
  # epic spell penetration, epic toughness, greater spell focus, improved
  # combat casting) — читать этот bold-лейбл отдельно значило бы завести
  # второй механизм для факта, который первый уже держит верно.
  # ⚠️ **Сколько**, а не «есть ли»: до 14.08.2026 эта функция отвечала «да/нет»,
  # а рейнджер на 35-м классовом уровне получает ДВА бонусных слота, и второй
  # терялся молча — целый фит на билд (CLAUDE.md §9, «Известные баги модели»).
  # Источник называет число трижды и независимо: строкой таблицы
  # (`|35th ||align=left|2 bonus feats`), прозой лейбла («at levels 23, 25, 26,
  # 29, 30, 32, 35(two bonus feats), 38, and 40» — `fandom:Ranger`, revid 68113)
  # и сводной таблицей на отдельной странице, где в ячейке 35-го уровня строки
  # «Epic ranger» стоит `12<br />13` — единственная двузначная ячейка обеих
  # таблиц (`fandom:Bonus feat`). Мы читаем **таблицу класса**, остальные два —
  # сверка, а не второй механизм.
  #
  # Число берётся **из строки без ссылок**: у чемпиона Торма слот записан
  # категорийной ссылкой `[[:Category:Champion of Torm bonus feats|bonus feat]]`,
  # где множественное число живёт в цели ссылки, а не в тексте. Сырой текст дал
  # бы «сказано „feats“, а числа нет» на ровном месте.
  defp bonus_feat_slots(rows) do
    for row <- rows, count = bonus_feat_count(row), count > 0, do: {row.level, count}
  end

  # Колонка `Feats` и колонка `Bonus feats` — это два РАЗНЫХ способа одной и той
  # же таблицы назвать слот, и ни одна из 23 страниц не пользуется обоими сразу
  # (у эпической таблицы red dragon disciple, единственной с колонкой `Bonus
  # feats`, `feats_raw` пуст во всех 20 строках). Поэтому здесь тот же выбор
  # «первое, что нашлось», что стоял тут и раньше, а не сумма: складывать два
  # прочтения одного слота значило бы выдумать слот на странице, которая ещё
  # не существует.
  defp bonus_feat_count(row) do
    case bonus_feat_mentions(row.feats_raw) do
      [] -> if row.bonus_feat_rank_raw, do: 1, else: 0
      mentions -> mentions |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    end
  end

  # `{сколько слотов, названо ли это число}` на каждое упоминание слота в ячейке.
  #
  # ⚠️ `:uncounted` — «ячейка говорит „bonus feats“ во множественном числе и не
  # говорит, сколько их». Сегодня такой формы в корпусе нет ни одной, и слот
  # считается за один, но молчать об этом нельзя: ровно так — множественным
  # числом без разбора — рейнджер и терял слот. Форма уезжает в `problems`,
  # то есть в отчёт `mix wiki.parse`, а не в тишину.
  defp bonus_feat_mentions(nil), do: []

  defp bonus_feat_mentions(raw) do
    for [_whole, digits, plural] <- Regex.scan(@bonus_feat, Wikitext.strip_links(raw)) do
      case {digits, plural} do
        {"", "s"} -> {1, :uncounted}
        {"", _singular} -> {1, :counted}
        {digits, _plural} -> {String.to_integer(digits), :counted}
      end
    end
  end

  # ── what the class hands out, and what it only opens a slot for ───────────

  @doc """
  Splits the progression's feats column into grants, slots and leftover prose.

  The column is a comma-separated list, and `BuildCalculator.Wiki.Requirements`
  already splits exactly this grammar — commas and `and`, but never inside
  `[[…]]` (the feat `[[sneak attack, blackguard]]` has a comma in its title) and
  never inside parentheses (`bonus feat ([[curse song]], [[favored enemy]])` is
  one slot with a restricted pool, **not** two granted feats — the trap this
  whole function exists for).

  A fragment is then one of three things:

    * a **slot** — it says "bonus feat" in any of its five spellings. Already
      counted by `bonus_feat_levels`, and it names no feat: the pool it may be
      spent on is what `bonus_for` in `feats.json` records, not a grant;
    * a **grant** — it *starts* with a `[[link]]`, whose **target** is the feat
      (`[[fear (feat)|fear]]` is the `fear (feat)` page however it is displayed),
      **or** it repeats — case-insensitively, with no link at all — the display
      name an EARLIER row of this same table already granted. A class page almost
      never links a rank family twice: `[[bone skin]] (+2AC)` at pale master 1 is
      followed by the bare `bone skin (+2AC)` at 4, 8, 12, 16, 20, 24 and 28, and
      the feat's own page confirms all eight (CLAUDE.md §3 — this is what closes
      the "2 instead of 8" bug the second reading exists to fix). Whatever trails
      the matched name (`I`, `(+2AC)`, `1/day`) is the rank or the uses per day of
      that same feat and comes back as `tail`, not as another feat. What was
      matched comes back too, as `shown`: where a page links a rank under its own
      title (`[[greater rage]]`, `[[infinite humanoid shape]]`,
      `[[elemental shape | improved elemental shape]]` — all three are redirects
      into a family page) the matched text is the only thing telling that grant
      apart from the earlier one, and `tail` is empty or says nothing new;
    * **prose** — everything else: a sentence naming no grant this table has
      made yet, linked or not (`gets wings`, `huge (1x/day)`, `druid wildshape
      (animal)` — the druid's own notes call the last of these "not a new feat,
      simply a change in what using this feat produces", so the wiki agrees it
      is not one). Nothing here is guessed into a feat id.

  Returns `%{granted: [{level, target, shown, tail}], slots: [{level, text}],
  prose: [{level, text}]}`, all three in page order. Resolving a target to a feat
  id is the caller's job — it needs the feat index, which one class page cannot
  have, and so is deciding whether `shown` says anything the feat's own name does
  not.
  """
  @spec feat_grants([progression_row]) :: %{
          granted: [{pos_integer, binary, binary, binary}],
          slots: [{pos_integer, binary}],
          prose: [{pos_integer, binary}]
        }
  def feat_grants(rows) do
    empty = %{granted: [], slots: [], prose: [], known: %{}}

    rows
    |> Enum.reduce(empty, fn row, acc ->
      case row.feats_raw do
        nil -> acc
        raw -> raw |> Requirements.fragments() |> Enum.reduce(acc, &fragment(&2, row.level, &1))
      end
    end)
    |> Map.take([:granted, :slots, :prose])
    |> Map.new(fn {key, list} -> {key, Enum.reverse(list)} end)
  end

  defp fragment(acc, level, text) do
    plain = Wikitext.strip_links(text)
    lead = lead_in(plain)

    cond do
      plain == "" ->
        acc

      Regex.match?(@bonus_feat, plain) ->
        push(acc, :slots, {level, text})

      grant = grant(text, lead) ->
        acc |> push(:granted, Tuple.insert_at(grant, 0, level)) |> remember(grant)

      repeat = repeat(acc.known, lead) ->
        push(acc, :granted, Tuple.insert_at(repeat, 0, level))

      true ->
        push(acc, :prose, {level, text})
    end
  end

  defp push(acc, key, value), do: Map.update!(acc, key, &[value | &1])

  # Teaches a link's display name to every later row of the same table, so a
  # rank written without a link (`repeat/2`) can still be told apart from a
  # sentence naming no grant at all. Keyed lower-case because the page is not
  # consistent about capitalising a rank's second and third appearance.
  defp remember(acc, {target, name, _tail}) do
    Map.update!(acc, :known, &Map.put(&1, String.downcase(name), target))
  end

  # The wiki almost never repeats a `[[link]]` once a rank family starts: after
  # `[[bone skin]] (+2AC)` at pale master 1, level 4 is the bare `bone skin
  # (+2AC)`, and so are 8, 12, 16, 20, 24 and 28, all the way to the feat's own
  # last documented step. Reading only the linked rows left six of those eight
  # invisible — the wiki was consulted correctly, `fragment/3` was just stopping
  # before the sentence's second half.
  #
  # Matched against every name a link on an EARLIER row put into `known`
  # (`remember/2`), longest name first: barbarian 26 is `epic barbarian damage
  # reduction II`, and cutting it at the five-levels-earlier `damage reduction`
  # would misfile a fresh family under the wrong one. A name is matched whole,
  # case-insensitively, against the START of the fragment — the same rule
  # `grant/2` uses for a linked name — so a fragment naming no known grant at
  # all (`gets wings`, `huge (1x/day)`, `druid wildshape (animal)`) still falls
  # through to `prose`, unread and unguessed, exactly as before this existed.
  #
  # A repeat never introduces a target `known` did not already hold, so it can
  # never grow the set of (class, feat) pairs a class hands out — only the set
  # of levels at which an already-granted one recurs. What it hands the reader
  # that a bare `grant/2` match could not is the same thing a linked repeat
  # already gets: `shown`, which `granted_feat_ranks/2` in `mix wiki.parse`
  # turns into the rank caption (`(+2AC)`, `II`, `(6x/day)`) — see
  # `RepeatedGrantsTest` and `ClassGrantRanksTest`.
  defp repeat(known, plain) do
    lower = String.downcase(plain)

    known
    |> Map.keys()
    |> Enum.sort_by(&{-String.length(&1), &1})
    |> Enum.find_value(fn name ->
      if String.starts_with?(lower, name) do
        target = Map.fetch!(known, name)
        shown = String.slice(plain, 0, String.length(name))
        tail = plain |> String.slice(String.length(name)..-1//1) |> String.trim()
        {target, shown, tail}
      end
    end)
  end

  # The red dragon disciple is the one page that introduces its grants with a
  # sentence — "becomes a half-dragon: [[darkvision]], [[immunity to fire]], …" —
  # and only its first fragment carries the lead-in. Cutting at the colon is what
  # keeps darkvision from being dropped while its three neighbours are kept; the
  # feat's own page agrees, listing `[[red dragon disciple]] 10` as one of the
  # things that grant it.
  defp lead_in(plain) do
    case String.split(plain, ":", parts: 2) do
      [_lead, rest] -> String.trim(rest)
      [whole] -> whole
    end
  end

  @first_link ~r/\[\[(?:[^\[\]|]*\|)?([^\[\]|]*)\]\]/u

  # The fragment has to *start* with what the link displays, so a feat named in
  # passing inside a sentence can never be read as one the class hands out. That
  # display text is kept as well as the target: the two differ on 24 of the 230
  # grants a linked fragment reads this way (`repeat/2` below adds more grants
  # from later, unlinked rows, but never a new *kind* of difference — it can
  # only ever repeat one this function already found), 23 of them only by the
  # disambiguating `(feat)` the page hides and one because the page deliberately
  # named a *later rank* of the same family under a different redirect title
  # (`[[elemental shape | improved elemental shape]]`).
  defp grant(text, plain) do
    with [_, display] <- Regex.run(@first_link, text),
         [target | _] <- Wikitext.link_targets(text),
         target = String.trim(target),
         false <- Regex.match?(@not_a_page, target),
         name = Wikitext.strip_links(display),
         true <- name != "" and String.starts_with?(String.downcase(plain), String.downcase(name)) do
      {target, name, plain |> String.slice(String.length(name)..-1//1) |> String.trim()}
    else
      _no -> nil
    end
  end

  # ── the two readings compared, and what the page never gave ───────────────

  defp conflicts(table_bab, label_bab, table_saves, label_saves) do
    bab =
      if table_bab && label_bab && table_bab != label_bab do
        ["BAB progression: table says #{table_bab}, label says #{label_bab}"]
      else
        []
      end

    saves =
      if table_saves && label_saves && table_saves != label_saves do
        ["saves: table says #{render(table_saves)}, label says #{render(label_saves)}"]
      else
        []
      end

    bab ++ saves
  end

  defp render(saves) do
    Enum.map_join([:fort, :ref, :will], ", ", fn key -> "#{key} #{saves[key]}" end)
  end

  defp problems(labels, progression, epic, sections) do
    missing =
      for field <- [:hit_die, :skill_points, :bab, :primary_saves, :class_skills],
          is_nil(labels[field]),
          do: "no '#{field}' label"

    missing ++
      if(progression, do: [], else: ["no level progression table"]) ++
      uncounted_bonus_feats((progression || []) ++ (epic || [])) ++
      unread_hit_die_scale(progression, epic, sections)
  end

  # Колонка есть, а шкалы не вышло — единственный способ узнать об этом, кроме
  # тишины. Обе ветки сегодня молчат (`red dragon disciple` читается целиком),
  # и обе стоят здесь ровно потому, что молчание в этом месте неотличимо
  # от исправного чтения.
  defp unread_hit_die_scale(progression, epic, sections) do
    case {hit_die_column(progression), hit_die_by_class_level(sections, progression, epic)} do
      {:unreadable, _} ->
        ["hit die column: a row states something other than 'dN' — no scale read at all"]

      {{:ok, [_ | _ = more]}, nil} when more != [] ->
        ["hit die grows and the epic section states no hit die — no scale read at all"]

      _read_or_absent ->
        []
    end
  end

  # Обе таблицы вместе: слот с числом сегодня стоит в эпической, а завтра может
  # появиться в основной — вопрос «сколько» у них общий.
  defp uncounted_bonus_feats(rows) do
    for row <- rows,
        {_count, :uncounted} <- bonus_feat_mentions(row.feats_raw),
        do: "level #{row.level}: 'bonus feats' without a number — counted as one"
  end

  # ── the progression tables ────────────────────────────────────────────────

  defp progression(sections) do
    sections
    |> Enum.reject(&epic?/1)
    |> Enum.flat_map(&tables/1)
    |> Enum.find_value(fn table ->
      rows = rows(table)

      if table.roles[:level] && table.roles[:bab] && match?([%{level: 1} | _], rows), do: rows
    end)
  end

  defp epic_progression(sections, progression) do
    floor = if progression, do: List.last(progression).level, else: 0

    sections
    |> Enum.filter(&epic?/1)
    |> Enum.flat_map(&tables/1)
    |> Enum.find_value(fn table ->
      rows = rows(table)

      if table.roles[:level] && match?([%{level: level} | _] when level > floor, rows), do: rows
    end)
  end

  defp epic?(%{title: nil}), do: false
  defp epic?(%{title: title}), do: Regex.match?(~r/\bepic\b/i, title)

  defp tables(section) do
    section.body
    |> Wikitable.find_all()
    |> Enum.map(fn source ->
      grid = source |> Wikitable.parse() |> Map.fetch!(:rows) |> Wikitable.expand()
      {header, body} = Enum.split_while(grid, &header_row?/1)
      columns = columns(header)
      spells = spell_columns(columns)

      %{
        columns: columns,
        roles: roles(columns),
        spells: spells,
        spell_groups: spells |> Map.values() |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
        body: body
      }
    end)
  end

  # A header row may carry a data cell: the champion of Torm's epic table declares
  # its blank spacer column with `|rowspan=21|&nbsp;` in the middle of the `!`
  # cells. Blank cells therefore count as header material.
  defp header_row?(cells) do
    cells != [] and Enum.all?(cells, fn cell -> cell.header? or cell.text == "" end)
  end

  # Column name = the distinct header texts stacked above it, e.g. "Saves / Fort"
  # for a `!colspan=3|Saves` sitting over `!Fort`.
  defp columns(header_rows) do
    header_rows
    |> Enum.map(&Enum.map(&1, fn cell -> Wikitext.strip_links(cell.text) end))
    |> zip_ragged()
    |> Enum.map(fn texts ->
      texts |> Enum.reject(&(&1 == "")) |> Enum.uniq() |> Enum.join(" / ")
    end)
  end

  defp zip_ragged([]), do: []

  defp zip_ragged(rows) do
    width = rows |> Enum.map(&length/1) |> Enum.max()

    for index <- 0..(width - 1)//1 do
      Enum.map(rows, &Enum.at(&1, index, ""))
    end
  end

  defp roles(columns) do
    for {name, index} <- Enum.with_index(columns),
        {role, aliases} <- @column_roles,
        name |> last_segment() |> Kernel.in(aliases),
        reduce: %{} do
      acc -> Map.put_new(acc, role, index)
    end
  end

  # `%{column index => {group, circle}}` for the spell-slot columns of one table.
  defp spell_columns(columns) do
    columns
    |> Enum.with_index()
    |> Enum.flat_map(fn {name, index} ->
      case spell_column(name) do
        nil -> []
        found -> [{index, found}]
      end
    end)
    |> Map.new()
  end

  # Circles are keyed by the string "0".."9" rather than by an integer so that
  # the zeroth circle survives a round-trip through JSON as a key of its own.
  defp spell_column(name) do
    with [_, group, circle] <- Regex.run(@spell_column, name),
         group when not is_nil(group) <- Map.get(@spell_groups, normalize(group)),
         [_, digit] <- Regex.run(@spell_circle, String.trim(circle)) do
      {group, digit}
    else
      _no -> nil
    end
  end

  defp last_segment(name) do
    name
    |> String.split(" / ")
    |> List.last()
    |> String.downcase()
    |> String.replace(~r/[^\p{Ll} ]/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp rows(table) do
    Enum.flat_map(table.body, fn cells ->
      case integer(cell(cells, table.roles[:level])) do
        nil -> []
        level -> [row(cells, table, level)]
      end
    end)
  end

  defp row(cells, table, level) do
    core = table.roles |> Map.values() |> MapSet.new()
    hp_raw = cell(cells, table.roles[:hp])

    {slots, extra} =
      for {name, index} <- Enum.with_index(table.columns),
          not MapSet.member?(core, index),
          name != "",
          reduce: {%{}, []} do
        {slots, extra} ->
          value = cell(cells, index) || ""

          case slot(table.spells[index], value) do
            :unread -> {slots, [{name, value} | extra]}
            :absent -> {slots, extra}
            {group, circle} -> {Map.update(slots, group, [circle], &[circle | &1]), extra}
          end
      end

    %{
      level: level,
      bab: integer(cell(cells, table.roles[:bab])),
      fort: integer(cell(cells, table.roles[:fort])),
      ref: integer(cell(cells, table.roles[:ref])),
      will: integer(cell(cells, table.roles[:will])),
      feats_raw: blank_to_nil(cell(cells, table.roles[:feats]) || ""),
      bonus_feat_rank_raw: blank_to_nil(cell(cells, table.roles[:bonus_feats]) || ""),
      # Сырой ячейкой, как всё остальное в строке: числом её делает
      # `hit_die_by_class_level/3`, и только для той страницы, где колонка есть.
      hit_die_raw: blank_to_nil(cell(cells, table.roles[:hit_die]) || ""),
      hp: integer_only(hp_raw),
      hp_raw: hp_raw,
      spells_per_day: circles(table, slots, :spells_per_day),
      spells_known: circles(table, slots, :spells_known),
      extra: Enum.sort(extra)
    }
  end

  # A dash is the wiki's "this class has no such circle yet", and that is not a
  # zero: a bard at level 2 has a literal `0` in the 1st-circle column — a slot
  # that only opens up with a charisma bonus — and a dash in the 2nd. Collapsing
  # the two would invent a slot. Absence is therefore a *missing key*, and a cell
  # that is neither a dash nor a plain number is left in `extra` untouched rather
  # than guessed at.
  defp slot(nil, _value), do: :unread

  defp slot({group, circle}, value) do
    case value |> Wikitext.strip_links() |> String.trim() do
      dash when dash in @dashes ->
        :absent

      text ->
        case Integer.parse(text) do
          {count, ""} -> {group, {circle, count}}
          _other -> :unread
        end
    end
  end

  # `nil` when the table has no columns of this kind at all — only a class whose
  # table *does* have them can meaningfully say "and none at this level" with an
  # empty list.
  defp circles(table, slots, group) do
    if group in table.spell_groups do
      slots
      |> Map.get(group, [])
      |> Enum.sort_by(fn {circle, _count} -> String.to_integer(circle) end)
    end
  end

  defp cell(_cells, nil), do: nil

  defp cell(cells, index) do
    case Enum.at(cells, index) do
      nil -> nil
      cell -> cell.text
    end
  end

  # "+6/+1" is a BAB of 6; "1st" is level 1; "d6" is not a number at all.
  defp integer(nil), do: nil

  defp integer(text) do
    case Regex.run(~r/^\s*([+-]?\d+)/, Wikitext.strip_links(text)) do
      [_, digits] -> String.to_integer(digits)
      nil -> nil
    end
  end

  # HP is written as a range ("5-10") everywhere on Fandom, so this practically
  # always returns nil — but a plain number, if one ever appears, is not lost.
  defp integer_only(nil), do: nil

  defp integer_only(text) do
    case Regex.run(~r/^\s*(\d+)\s*$/, Wikitext.strip_links(text)) do
      [_, digits] -> String.to_integer(digits)
      nil -> nil
    end
  end
end
