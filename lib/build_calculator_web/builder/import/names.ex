defmodule BuildCalculatorWeb.Builder.Import.Names do
  @moduledoc """
  Every dictionary a name in the paste is resolved through, built from the
  ruleset itself (`indexes/1`): classes, feats, skills, races, alignments, the
  six ability scores, and the values a choice takes. Here too are the guesses
  — a typo, a shorthand, a name read off a unique prefix — each of which is a
  reading the player is told about, never a silent one. A part of
  `BuildCalculatorWeb.Builder.Import`.
  """

  import BuildCalculatorWeb.Builder.Import.Rx, only: [sigil_RX: 2]

  alias BuildCalculator.FeatListTokenizer
  alias BuildCalculator.Ids
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.FeatSlots
  alias BuildCalculatorWeb.Builder.{ChoiceIndex, Fuzzy, Labels, PointBuy}
  alias BuildCalculatorWeb.Builder.Import.Rx

  @ability_words ~w(str dex con int wis cha)

  # The six scores by their full English names — the game's own words, not a
  # synonym table. `Strength 9`, `Charisma +1 (17)` and `Char: 12` name one of
  # them by a prefix of three letters or more; `Chaotic` and `Intimidate` do not.
  @ability_names %{
    "str" => "strength",
    "dex" => "dexterity",
    "con" => "constitution",
    "int" => "intelligence",
    "wis" => "wisdom",
    "cha" => "charisma"
  }

  # The six keys, read by `Sheets` (a whole sheet names all six) and
  # `Assembly` (a key of a list of increases, as the ability it names).
  def ability_words, do: @ability_words

  # The three saves by the words posts write them with, shorthand included —
  # one table for the block of saves `Sheets` reads (`Fortitude: 23` /
  # `Refl: 22` / `Wil: 33`) and for `Comparison`, which sets the source's saves
  # against ours in the order the source names them (task 4.34: its own table
  # had no `for`, `refl`, `wil`, and `Saves: Wil 16, For 21, Refl 33` was set
  # against ours as Fort/Ref/Will).
  @save_names %{
    "f" => :fort,
    "for" => :fort,
    "fort" => :fort,
    "fortitude" => :fort,
    "r" => :ref,
    "ref" => :ref,
    "refl" => :ref,
    "reflex" => :ref,
    "w" => :will,
    "wil" => :will,
    "will" => :will
  }

  def save_name(word), do: Map.get(@save_names, String.downcase(word))

  # ------------------------------------------------------------- name lookup --

  # One index per dictionary, built from the ruleset itself. A key two entries
  # answer to refuses instead of picking one: guessing which of two feats the
  # player meant is the same sin as guessing a number.
  def indexes(ruleset) do
    feat_words = feat_words(ruleset)
    classes = name_index(ruleset, ruleset.classes)
    class_short = short_index(ruleset)
    feats = ruleset |> name_index(ruleset.feats, &feat_variants/1) |> put_shorthands(ruleset)

    %{
      classes: classes,
      races: race_index(ruleset),
      feats: feats,
      feat_letters: feat_letters(feats, feat_words),
      feat_dictionary: feat_dictionary(ruleset),
      feat_words: feat_words,
      feat_words_by_count: Enum.group_by(feat_words, &length(&1.words)),
      choosable: choosable_feats(ruleset),
      # The class of the level being read, set per level by `assemble/4`: the
      # one thing about the ladder a feat's reading asks (`narrow/5`).
      level_class: nil,
      level_first?: false,
      skills: name_index(ruleset, ruleset.skills, &skill_variants/1),
      skill_names:
        for {id, skill} <- ruleset.skills do
          %{id: id, key: norm(without_parenthetical(skill.name || ""))}
        end,
      abilities: Map.new(ruleset.abilities, &{Atom.to_string(&1), [&1]}),
      point_buy_min: PointBuy.min_score(ruleset),
      # `Sheets.point_buy_sheet?/3`'s question, compiled once: it names the
      # ruleset's minimum, and was compiled anew for every line (task 4.34).
      point_buy_sum:
        Rx.ascii_digits("(?:^|[^\\d])#{PointBuy.min_score(ruleset)}\\s*\\+\\s*\\d[^=]*=")
        |> Regex.compile!("u"),
      point_buy_sheet?: false,
      choices: choice_index(ruleset),
      class_short: class_short,
      class_names:
        for {id, class} <- ruleset.classes do
          %{id: id, key: norm(class.name || ""), name: class.name || Atom.to_string(id)}
        end,
      class_letters: class_letters(classes, class_short),
      alignments: alignment_index(),
      # The ruleset itself, for a line read the way a level's contents are
      # before the ladder is known (`Lines`, task 4.36), and its level cap for
      # a sheet captioned by the level it shows (`Sheets`).
      ruleset: ruleset
    }
  end

  # The most letters a text can have and still name a class through
  # `resolve_class/3` or `named_class/2` (task 4.34): a key a text is looked up
  # by — its `norm/1`, or a start of a class's (`prefix_class/2`) — keeps every
  # letter of the text, so a text of more letters than the longest key has
  # bytes names none; `singular_class/2` drops at most one `s` in four letters,
  # hence a third more; the guess (`fuzzy_class/2`) reads `fuzzy_class_chars/0`
  # characters at most.
  # `Ladder` does not try longer runs of words at all: a line of sixteen
  # thousand words tried every one of their starts.
  # The same bound for a feat's name (`feat_by_name/2`): its `norm/1` keeps
  # every letter and digit, and so do its words, each a start of the feat's
  # own word in the same place (`word_prefix_feat/2`).
  defp feat_letters(feats, feat_words) do
    keys = Enum.map(Map.keys(feats), &byte_size/1)

    words =
      Enum.map(feat_words, fn %{words: words} -> words |> Enum.map(&byte_size/1) |> Enum.sum() end)

    Enum.max(keys ++ words, fn -> 0 end)
  end

  defp class_letters(classes, class_short) do
    longest =
      Enum.max(Enum.map(Map.keys(classes) ++ Map.keys(class_short), &byte_size/1), fn -> 0 end)

    max(div(longest * 4, 3) + 1, fuzzy_class_chars())
  end

  # Значения, с которыми берутся фиты: школы магии, расы-враги, типы урона,
  # навыки. Домен без справочника (`weapon`, до задачи 3.5) даёт пустой индекс:
  # сопоставлять не с чем, и это честный ответ, а не пропуск.
  #
  # ⚠️ Сама индексация переехала в `BuildCalculatorWeb.Builder.ChoiceIndex`
  # (26.08.2026, задача 3.111) — вторым читателем стал `GameLogImport`, а
  # второй implementation одной и той же выборки был бы ровно той ошибкой,
  # от которой уже спасает `FeatListTokenizer`. Поведение не изменилось —
  # это чистое извлечение, регрессия — тесты этого модуля.
  defp choice_index(ruleset), do: ChoiceIndex.build(ruleset)

  defp name_index(ruleset, dictionary, variants \\ fn _name -> [] end) do
    Enum.reduce(dictionary, %{}, fn {id, entry}, acc ->
      name = Map.get(entry, :name)

      [name, Map.get(entry, :ru), name && Map.get(ruleset.name_map, name)]
      |> Enum.concat(if(name, do: variants.(name), else: []))
      |> Enum.reduce(acc, &put_key(&2, &1, id))
    end)
  end

  # `Weapon Proficiency Exotic` for `Weapon proficiency (exotic)` — the bracket
  # is how the wiki writes the name, not how anybody types it; `Epic Warding`
  # for `Epic spell: epic warding` — the part after the colon is the spell's
  # own name, and the one ladders write.
  defp feat_variants(name) do
    after_colon =
      case String.split(name, ":", parts: 2) do
        [_kind, own] -> String.trim(own)
        [_whole] -> nil
      end

    [acronym(name), inline_parenthetical(name), after_colon]
  end

  # Names the community writes a feat by that no rule above derives (task
  # 4.40, third pass), each counted on the ECB corpus (2027 first posts) before
  # it went in. `Whirlwind` alone stood for Whirlwind attack on a ladder —
  # after Spring attack and Expertise, often beside «Intimidate 4» (Weapon
  # Master's own requirement; 186693: «12 Paladin Whirlwind (Intimidate = 4)»,
  # Weapon Master on 13) — and was an unknown name in 17 posts and a line
  # passed over in one more (117355, «--- Whirlwind» under its level);
  # `Improved whirlwind` stands for Improved whirlwind attack (117411), kept
  # beside it so that the shorter name never reads the longer one. Rejected
  # as a rule: «a name ending in `attack` without it» would read `Power`,
  # `Sneak` and `Death` as feats — the corpus writes none of them alone, and
  # of the eight such names only `Spring` once (197098).
  #
  # ⚠️ Into this index only — the whole name of an unknown run — and never
  # into the tokenizer's dictionary: there `whirlwind` would stand at the
  # start of `Whirlwind Atk` and leave `Atk` an unknown name, where the run
  # is read whole today (a guess the player is told of). A shorthand another
  # feat already answers to is refused as ambiguous by `put_key/3`, never
  # handed to one of them.
  @feat_shorthands %{
    whirlwind_attack: ["Whirlwind"],
    improved_whirlwind_attack: ["Improved whirlwind"]
  }

  defp put_shorthands(index, ruleset) do
    for {id, names} <- @feat_shorthands,
        Map.has_key?(ruleset.feats, id),
        name <- names,
        reduce: index,
        do: (acc -> put_key(acc, name, id))
  end

  # `Heal` for `Heal (skill)` — the bracket is the wiki's disambiguation, and
  # nobody writes it; `UMD` for `Use magic device`.
  defp skill_variants(name) do
    bare = without_parenthetical(name)
    [bare, acronym(bare)]
  end

  defp inline_parenthetical(name),
    do: name |> String.replace(~RX/[()]/u, " ") |> String.replace(~RX/\s+/u, " ") |> String.trim()

  defp without_parenthetical(name),
    do: name |> String.replace(~RX/\s*\([^)]*\)/u, "") |> String.trim()

  # The feat names as `FeatListTokenizer` wants them: lower case, words kept
  # apart by single spaces, a hyphen read as a space (`Two-Weapon`, `Blind-Fight`,
  # `Self-Concealment`). A key two feats answer to maps to both, and is then
  # reported as ambiguous — the same refusal as the name index's.
  defp feat_dictionary(ruleset) do
    table =
      for {id, feat} <- ruleset.feats,
          name <- feat_names(ruleset, feat),
          key <- Enum.uniq([tok_key(name), tok_key(inline_parenthetical(name))]),
          key != "",
          reduce: %{} do
        acc -> Map.update(acc, key, {:feat, id}, &join_feat(&1, id))
      end

    FeatListTokenizer.dictionary(table)
  end

  defp feat_words(ruleset) do
    for {id, feat} <- ruleset.feats,
        name <- feat_names(ruleset, feat),
        words = name_words(name),
        do: %{id: id, words: words, joined: Enum.join(words)}
  end

  # The feats some slot of some class would take — asked of the core
  # (`FeatSlots.candidates/2`) with one epic general slot and one epic bonus
  # slot per class, the widest of each kind. What is left out is handed over,
  # never picked: Lay on Hands, a race's own feats (`narrow/4`).
  defp choosable_feats(ruleset) do
    general = %{id: :general, kind: :epic_general, class: nil, taken_with: nil, epic?: true}

    bonus =
      for class <- Map.keys(ruleset.classes),
          do: %{
            id: :class_bonus,
            kind: :class_bonus,
            class: class,
            taken_with: class,
            epic?: true
          }

    for slot <- [general | bonus],
        id <- FeatSlots.candidates(ruleset, slot),
        into: MapSet.new(),
        do: id
  end

  defp feat_names(ruleset, feat) do
    name = Map.get(feat, :name)

    Enum.filter(
      [name, Map.get(feat, :ru), name && Map.get(ruleset.name_map, name)],
      &is_binary/1
    )
  end

  defp tok_key(name), do: name |> tok_text() |> collapse()

  defp join_feat({:feat, id}, id), do: {:feat, id}
  defp join_feat({:feat, other}, id), do: {:ambiguous, [other, id]}
  defp join_feat({:ambiguous, ids}, id), do: {:ambiguous, Enum.uniq(ids ++ [id])}

  defp race_index(ruleset) do
    Enum.reduce(ruleset.races, %{}, fn {id, race}, acc ->
      shard = Map.get(race, :siala) || %{}

      [Map.get(race, :name), Map.get(race, :ru), Map.get(shard, "en")]
      |> Enum.concat(Map.get(shard, "ru_spellings") || [])
      |> Enum.reduce(acc, &put_key(&2, &1, id))
    end)
  end

  defp short_index(ruleset) do
    Enum.reduce(ruleset.classes, %{}, fn {id, _class}, acc ->
      put_key(acc, Labels.class_short(ruleset, id), id)
    end)
  end

  defp put_key(index, nil, _id), do: index

  defp put_key(index, name, id) do
    case norm(name) do
      "" -> index
      key -> Map.update(index, key, [id], &Enum.uniq([id | &1]))
    end
  end

  # `Improved two-weapon fighting` → `itwf`, the way the community writes it.
  # Derived, never a table: a feat added to the data gets its shorthand for free,
  # and a shorthand two feats share is refused as ambiguous instead of guessed.
  defp acronym(nil), do: nil

  defp acronym(name) do
    case String.split(name, ~RX/[\s\-]+/u, trim: true) do
      [_single] -> nil
      words -> words |> Enum.map_join(&String.first/1) |> String.downcase()
    end
  end

  def resolve(index, text) do
    case Map.get(index, norm(text), []) do
      [id] -> {:ok, id}
      [] -> :error
      many -> {:ambiguous, many}
    end
  end

  # Classes get three chances more than everything else, because the ladder is
  # where shorthand actually gets written. In order of how much they claim:
  # `WM`, `DD`, `CoT` off `Labels.class_short/2`; `Sorc` or `Dwarven def` off a
  # unique prefix; and finally `Ftr`, `Bbn`, `Rgr` — the community's consonant
  # shorthand, which no rule derives — through the same subsequence matcher the
  # feat search uses. Only the last tier returns `{:guess, id}`, and only it is
  # reported to the player, because only it could plausibly be wrong.
  #
  # Before the guess, one mechanical spelling: a plural `s` dropped off each
  # word — `Weapons Master`, `Bards` — read as surely as the name itself.
  def resolve_class(index, text, fuzzy? \\ true) do
    key = norm(text)

    with :error <- resolve(index.classes, text),
         :error <- resolve(index.class_short, key),
         :error <- prefix_class(index, key),
         :error <- singular_class(index, text) do
      if fuzzy?, do: fuzzy_class(index, text), else: :error
    end
  end

  defp singular_class(index, text) do
    singular = String.replace(text, ~RX/(?<=\p{L}{3})s\b/u, "")

    if singular == text,
      do: :error,
      else: only_ok(resolve(index.classes, singular))
  end

  def prefix_class(_index, key) when byte_size(key) < 3, do: :error

  def prefix_class(index, key) do
    case Enum.filter(index.class_names, &String.starts_with?(&1.key, key)) do
      [class] -> {:ok, class.id}
      [] -> :error
      many -> {:ambiguous, Enum.map(many, & &1.id)}
    end
  end

  # Only for something short enough to be an abbreviation, and only when one
  # class scores strictly better than every other: `Pal` matches Paladin and
  # Pale master equally well, and picking either would be a coin toss dressed
  # up as a reading.
  #
  # The most characters a guess reads is asked by `class_letters/2` and by
  # `Ladder`'s heads too (task 4.34): one number, or the bounds drift apart.
  @fuzzy_class_chars 24

  def fuzzy_class_chars, do: @fuzzy_class_chars

  def fuzzy_class(index, text) do
    trimmed = String.trim(text)

    if String.length(trimmed) in 2..@fuzzy_class_chars do
      index.class_names
      |> Enum.flat_map(fn class ->
        case Fuzzy.match(trimmed, class.name) do
          nil -> []
          match -> [{match.score, class.id}]
        end
      end)
      |> Enum.sort_by(fn {score, id} -> {-score, Atom.to_string(id)} end)
      |> best_class()
    else
      :error
    end
  end

  defp best_class([]), do: :error
  defp best_class([{_score, id}]), do: {:guess, id}

  defp best_class([{score, id}, {runner_up, other} | _]) do
    if score > runner_up, do: {:guess, id}, else: {:ambiguous, [id, other]}
  end

  # Skills get the class's second chance and not its third: a unique prefix
  # (`Tum`, `Conc`, `Disc`, `Move Silent`) is how a skill chart abbreviates, and
  # it cannot be mistaken; a subsequence (`Spcr`) could, and is reported as an
  # unknown skill instead.
  def resolve_skill(index, text) do
    with :error <- resolve(index.skills, text),
         :error <- prefix_skill(index, norm(text)) do
      singular = String.replace(text, ~RX/(?<=\p{L}{3})s\b/u, "")
      if singular == text, do: :error, else: only_ok(resolve(index.skills, singular))
    end
  end

  defp prefix_skill(_index, key) when byte_size(key) < 3, do: :error

  defp prefix_skill(index, key) do
    case Enum.filter(index.skill_names, &String.starts_with?(&1.key, key)) do
      [skill] -> {:ok, skill.id}
      [] -> :error
      many -> {:ambiguous, Enum.map(many, & &1.id)}
    end
  end

  def norm(nil), do: ""

  def norm(text) do
    text
    |> String.downcase()
    |> String.replace("ё", "е")
    |> String.replace(~RX/[\s_\-–—.'’"`]+/u, "")
  end

  def named_class(index, text) do
    with :error <- only_ok(resolve(index.classes, text)),
         :error <- only_ok(resolve(index.class_short, norm(text))) do
      singular_class(index, text)
    end
  end

  def collapse(text), do: text |> String.replace(~RX/\s+/u, " ") |> String.trim()

  def tok_text(text), do: text |> String.downcase() |> String.replace(["-", "_"], " ")

  # `str` for `Str`, `STR`, `Stre`, `Strength` — a prefix of the full name, at
  # least three letters long; or, five letters and more, the full name one
  # typo away (`Strenght`, task 4.31).
  def ability_key(word) do
    lowered = String.downcase(word)
    key = String.slice(lowered, 0, 3)

    case Map.fetch(@ability_names, key) do
      {:ok, full} -> if String.starts_with?(full, lowered), do: key
      :error -> nil
    end || misspelt_ability(lowered)
  end

  # Whether a word names one of the six scores — the one question every reader
  # of a score asks (task 4.34): the note after a bump (`(STR=16)`), a score
  # written into a feat's item (`Extend Spell Str 15`), the tail of a feat's
  # name (`Great Str I Str 18`), a list of increases (`Str at levels 4, 8`).
  # Those readers used to know six prefixes of their own
  # (`str|dex|con|int|wis|cha` and any letters after them), so `(Chr=16)` was
  # read as a bump where `(Cha=16)` was a note, and `(Intimidate = 4)` as a
  # score of Intelligence.
  def ability_word?(word), do: ability_key(word) != nil

  # `Chr`, `Cns` — three consonants of the name in order, the first kept.
  defp misspelt_ability(lowered) when byte_size(lowered) == 3 do
    if Regex.match?(~RX/^[a-z][^aeiouy]{2}$/u, lowered) do
      case for({key, full} <- @ability_names, shorthand?(lowered, full), do: key) do
        [key] -> key
        _ -> nil
      end
    end
  end

  defp misspelt_ability(lowered) when byte_size(lowered) >= 5 do
    case for({key, full} <- @ability_names, within_one?(lowered, full), do: key) do
      [key] -> key
      _ -> nil
    end
  end

  defp misspelt_ability(_lowered), do: nil

  # ------------------------------------------------------ race and alignment --

  # `Гном (Dwarf)` gives two chances to resolve. Both are tried because both are
  # real names: the shard rebuilt the races rather than translating them, so
  # `Гном` is the name a Siala player uses and `Dwarf` the one the engine does
  # (CLAUDE.md §4) — and mind the collision, `Карлик` is Gnome.
  #
  # A bracket the comma cut off before it closed — `Human (YA I know, but it
  # gets the job done)` — is dropped to the end as well (`drop_brackets/1`, the
  # one reading of a bracket the alignment's readers take too).
  def resolve_race(index, text) do
    outer = text |> drop_brackets() |> collapse()
    inner = with [_, inside] <- Regex.run(~RX/\(([^)]*)\)/u, text), do: String.trim(inside)

    Enum.find_value([text, outer, inner], :error, fn candidate ->
      case candidate && resolve(index.races, candidate) do
        {:ok, id} -> {:ok, id}
        {:ambiguous, ids} -> {:ambiguous, ids}
        _ -> nil
      end
    end)
  end

  # A race's name, and nothing but: `Human*` — a footnote's mark — too.
  def exact_race(index, text) do
    text = String.trim_trailing(text, "*") |> String.trim()
    resolve_race(index, text)
  end

  # What stands after `Race:` (task 4.31):
  #
  #   * the race — its text cut at the first full stop (`Elf. Subrace - Drow.`)
  #     and at a trailing separator (`Human /`);
  #   * races to pick from — `Human (for the extra skills) or Elf (for higher
  #     Dex)` — the one the author says they picked (`I choose human here`)
  #     read as `{:chosen, …}`, and without one none (`{:alternatives, …}`);
  #   * a name one typo away from exactly one race — `Hafling`, `Halfing` — as a
  #     guess the player is told about. Only here, where the line says it is a
  #     race: out of prose, `Gnomes` and a `genome` are not the same thing.
  def race_value(index, text) do
    text =
      text
      |> String.split(~RX/\.(?:\s|$)/u, parts: 2)
      |> hd()
      |> String.replace(~RX"(?<![\s/|,;*\-–—])[\s/|,;*\-–—]+$"u, "")
      |> String.trim()

    with :error <- resolve_race(index, text),
         :error <- race_pick(index, text) do
      race_typo(index, text)
    end
  end

  defp pick_verbs,
    do:
      ~RX/\bI(?:'ll|\s+will|'m|\s+am)?\s+(?:choose|chose|pick|picked|use|used|went\s+with|go\s+with|going\s+with|prefer|take|took|play|played)\s+(?:an?\s+|the\s+)?(\p{L}+(?:[\s\-]\p{L}+)?)/iu

  defp race_pick(index, text) do
    outer = text |> drop_brackets() |> collapse()
    options = outer |> String.split(~RX"\s+or\s+|\s*/\s*"iu, trim: true)

    ids =
      Enum.map(options, fn option ->
        case resolve_race(index, option) do
          {:ok, id} -> id
          _ -> nil
        end
      end)

    cond do
      length(ids) < 2 or Enum.member?(ids, nil) ->
        :error

      picked = picked_race(index, text, ids) ->
        {:chosen, picked, Enum.uniq(ids)}

      true ->
        {:alternatives, Enum.uniq(ids)}
    end
  end

  defp picked_race(index, text, ids) do
    Enum.find_value(Regex.scan(pick_verbs(), text), fn [_, words] ->
      Enum.find_value([words, hd(String.split(words, ~RX/[\s\-]/u))], fn name ->
        case resolve_race(index, name) do
          {:ok, id} -> if id in ids, do: id
          _ -> nil
        end
      end)
    end)
  end

  defp race_typo(index, text) do
    key = text |> drop_brackets() |> norm()

    matches =
      if String.length(key) >= 5,
        do:
          for(
            {name, ids} <- index.races,
            String.length(name) >= 5,
            within_one?(key, name),
            id <- ids,
            uniq: true,
            do: id
          ),
        else: []

    case matches do
      [id] -> {:guess, id}
      _ -> :error
    end
  end

  # Words an alignment *restriction* is written in — `Any`, `Any non-lawful`,
  # `LN or LE`, `Lawful <any>`, `neutral good preferred, but any non-lawful`.
  # A text made of nothing else that does not name one alignment is a
  # restriction; anything with a word outside it stays unrecognised.
  @restriction_words ~w(any non not no none or and but except either nor all only of
                        alignment alignments
                        preferably preferred prefered ideally recommended
                        lawful chaotic neutral good evil true law chaos
                        lg ln le ng tn nn ne cg cn ce n x xn nx)

  # ⚠️ A trailing run of `.!;:` is found from its first character only (task
  # 4.34): a match that starts inside the run has one a character earlier, and
  # trying every character of a long run in turn read the rest of the run from
  # each of them.
  def read_alignment(index, text) do
    cleaned =
      text
      |> drop_brackets()
      |> String.replace(
        ~RX/\b(?:only|preferably|preferred|prefered|ideally|recommended)\b/iu,
        " "
      )
      |> String.replace(~RX/(?<![.!;:])[.!;:]+\s*$/u, "")
      |> collapse()

    with :error <- resolve_alignment(index, cleaned),
         :error <- resolve_alignment(index, String.replace(cleaned, "/", " ")) do
      if restriction?(text), do: {:restriction, text}, else: :error
    end
  end

  defp restriction?(text) do
    words =
      text
      |> drop_brackets()
      |> String.downcase()
      |> String.split(~RX/[^a-z]+/, trim: true)

    words != [] and Enum.all?(words, &(&1 in @restriction_words))
  end

  defp resolve_alignment(index, text) do
    case Map.fetch(index.alignments, norm(text)) do
      {:ok, id} -> {:ok, id}
      :error -> :error
    end
  end

  # Built off `Ids.alignments/0` rather than typed out: the full name, the id,
  # and the two-letter shorthand the community writes. `N` is added by hand
  # because "Neutral" on its own is how True Neutral is written everywhere.
  #
  # Built once per paste, by `indexes/1` (task 4.34: once per question, it was
  # four times per line). A key two alignments share keeps the first — what
  # the list this was read from gave.
  defp alignment_index do
    base =
      for {id, name} <- Ids.alignments(),
          key <- [norm(name), norm(Atom.to_string(id)), initials(name)],
          do: {key, id}

    Enum.reduce(base ++ [{"n", :true_neutral}, {"neutral", :true_neutral}], %{}, fn {key, id},
                                                                                    acc ->
      Map.put_new(acc, key, id)
    end)
  end

  # A race's or an alignment's text without what it says in brackets — the one
  # reading of a bracket both of them take (task 4.34): `Human (for the
  # skills)`, `Any [non-lawful]`. A bracket and what it holds become a space;
  # read from the left, a bracket runs to the first closing one of its kind,
  # and a bracket inside it is part of it.
  #
  # 🔴 A bracket that never closes runs to the end of the text: `Human (YA I
  # know, but it gets the job done)` cut at its comma is `Human (YA I know`,
  # and `Lawful Good (the paladin` is Lawful Good. Until task 4.34 the race's
  # readers read it so and the alignment's kept the bracket, and neither read
  # `[…]` the way the other did.
  #
  # ⚠️ By hand, not by a regex: on a line of brackets that do not close, a
  # regex read to the end of the line from every one of them, and a line of
  # 64 KB of `(` took seconds (task 4.34). Here each closing bracket is looked
  # for once. Bytes are safe to count in: the four brackets are ASCII, and in
  # UTF-8 no byte of a longer character is ASCII.
  def drop_brackets(text) do
    opens = :binary.matches(text, ["(", "["])
    rounds = for {at, _} <- :binary.matches(text, ")"), do: at
    squares = for {at, _} <- :binary.matches(text, "]"), do: at
    drop_brackets(text, opens, rounds, squares, 0, [])
  end

  defp drop_brackets(text, [], _rounds, _squares, cursor, done),
    do: IO.iodata_to_binary([done | binary_part(text, cursor, byte_size(text) - cursor)])

  defp drop_brackets(text, [{at, _} | opens], rounds, squares, cursor, done) when at < cursor,
    do: drop_brackets(text, opens, rounds, squares, cursor, done)

  defp drop_brackets(text, [{at, _} | opens], rounds, squares, cursor, done) do
    rounds = Enum.drop_while(rounds, &(&1 <= at))
    squares = Enum.drop_while(squares, &(&1 <= at))
    closing = if :binary.at(text, at) == ?(, do: rounds, else: squares

    case closing do
      [close | _] ->
        done = [done, binary_part(text, cursor, at - cursor), " "]
        drop_brackets(text, opens, rounds, squares, close + 1, done)

      [] ->
        IO.iodata_to_binary([done, binary_part(text, cursor, at - cursor), " "])
    end
  end

  defp initials(name) do
    name
    |> String.split(~RX/[\s\-]+/u, trim: true)
    |> Enum.map_join(&String.first/1)
    |> String.downcase()
  end

  # -------------------------------------------------------------- feat names --

  # The name as written, then with what a source writes after a name taken off
  # one layer at a time — the score it left (`Str 18`, `(WIS 21)`, `(23)`), the
  # rank (`II`, `3`, `+1`): `Great Str I Str 18` is `Great Str I` is `Great
  # Str`, and `Great Dex +1 (23)` is `Great Dex`.
  #
  # A form with more letters and digits than any feat's key or name has
  # (`index.feat_letters`) names none, and is passed over unasked (task 4.34).
  def feat_by_name(index, name), do: feat_by_forms(index, name_forms(name))

  # The same, for a name's forms worked out already (`FeatList` asks one name
  # several questions, task 4.34).
  def feat_by_forms(index, forms) do
    Enum.find_value(forms, :error, fn {form, letters} ->
      with true <- letters <= index.feat_letters,
           found when found != :error <- exact_or_prefix(index, form) do
        found
      else
        _ -> nil
      end
    end)
  end

  defp exact_or_prefix(index, form) do
    with :error <- resolve(index.feats, form), do: word_prefix_feat(index, form)
  end

  # A score is two digits: `Great Int 1` is the first take of Great
  # Intelligence, not a score of one.
  #
  # A tail that names a score captures its word, and is a tail only when the
  # word names one (`ability_word?/1`).
  defp name_tails do
    [
      ~RX/\s*[\(\[]\s*(\p{L}+)\.?\s*[:=]?\s*\d{2}\s*[\)\]]$/u,
      ~RX/\s*[\(\[]\s*[+\-]?\d{1,2}\s*[\)\]]$/u,
      ~RX/\s+(\p{L}+)\.?\s*[:=]?\s*\d{2}$/u,
      ~RX/\s*\+\s*1$/u,
      ~RX/\s+\d{1,2}$/u,
      ~RX/\s+[ivx]+\+?$/iu
    ]
  end

  # Every form reachable by taking tails off, the longest first: `Great Wisdom
  # 27` is `Great Wisdom` by its number, not `Great` by `Wisdom 27`. Each with
  # how many letters and digits it has, for `feat_by_name/2`.
  #
  # ⚠️ Worked out on the name's own bytes (task 4.34). A tail taken off leaves
  # a start of the name, so a form is a length of it; and the forms used to be
  # strings, each searched for its tails from its first character and measured
  # in graphemes whole — `Xyz 1 1 1 …` made one form per number, all of them
  # read to the end, and four kilobytes took ten seconds. Now:
  #
  #   * a tail is looked for among the last six words of the form only: no
  #     tail spans more than five (a bracket, a score's name, `=`, the score, a
  #     bracket), so no match can start before them;
  #   * a form reached again is not taken apart again — whatever it gives was
  #     already given, earlier in the same order;
  #   * a form's length in graphemes is the number of graphemes of the name
  #     that start inside it: a start of a text breaks into graphemes where the
  #     whole text does, the last one maybe cut short.
  def name_forms(name) do
    trimmed = String.trim(name)
    {starts, stops} = word_spans(trimmed)
    graphemes = grapheme_starts(trimmed)
    letters = letter_positions(trimmed)

    trimmed
    |> reachable_forms({starts, stops})
    |> Enum.sort_by(&(-count_below(graphemes, &1)))
    |> Enum.map(&{binary_part(trimmed, 0, &1), count_below(letters, &1)})
  end

  # The forms as lengths, in the order the tails were first taken off in: a
  # level of forms, then every tail off every form of it.
  defp reachable_forms(trimmed, words) do
    whole = byte_size(trimmed)

    {[whole], MapSet.new([whole])}
    |> Stream.unfold(fn
      {[], _seen} ->
        nil

      {level, seen} ->
        {next, seen} =
          for length <- level, tail <- name_tails(), reduce: {[], seen} do
            {next, seen} ->
              case strip_tail(trimmed, length, tail, words) do
                nil ->
                  {next, seen}

                shorter ->
                  if shorter in seen,
                    do: {next, seen},
                    else: {[shorter | next], MapSet.put(seen, shorter)}
              end
          end

        {level, {Enum.reverse(next), seen}}
    end)
    |> Enum.concat()
  end

  defp strip_tail(trimmed, length, tail, words) do
    form = binary_part(trimmed, 0, length)

    case Regex.run(tail, form, offset: tail_window(words, length), return: :index) do
      nil ->
        nil

      [{0, _} | _] ->
        nil

      [{at, _}, {word_at, word_size}] ->
        if ability_word?(binary_part(form, word_at, word_size)),
          do: byte_size(String.trim_trailing(binary_part(form, 0, at)))

      [{at, _}] ->
        byte_size(String.trim_trailing(binary_part(form, 0, at)))
    end
  end

  # Where the last six words of the first `length` bytes begin: the end of the
  # word before them.
  defp tail_window({starts, stops}, length) do
    last = count_below(starts, length) - 1
    if last >= 6, do: elem(stops, last - 6), else: 0
  end

  defp word_spans(text) do
    spans = for [{at, size}] <- Regex.scan(~RX/\S+/u, text, return: :index), do: {at, at + size}

    {spans |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
     spans |> Enum.map(&elem(&1, 1)) |> List.to_tuple()}
  end

  # Where every grapheme of the text starts, in bytes. The graphemes of a
  # start of the text are the ones starting inside it (`Ladder` reads the
  # heads of a line with it too).
  def grapheme_starts(text), do: grapheme_starts(text, 0, [])

  defp grapheme_starts(rest, at, starts) do
    case String.next_grapheme_size(rest) do
      {size, rest} -> grapheme_starts(rest, at + size, [at | starts])
      nil -> starts |> Enum.reverse() |> List.to_tuple()
    end
  end

  defp letter_positions(text),
    do:
      List.to_tuple(for [{at, _}] <- Regex.scan(~RX/[\p{L}\p{N}]/u, text, return: :index), do: at)

  # How many of the ascending positions are below `limit`.
  def count_below(positions, limit), do: count_below(positions, limit, 0, tuple_size(positions))

  defp count_below(_positions, _limit, low, high) when low >= high, do: low

  defp count_below(positions, limit, low, high) do
    middle = div(low + high, 2)

    if elem(positions, middle) < limit,
      do: count_below(positions, limit, middle + 1, high),
      else: count_below(positions, limit, low, middle)
  end

  # ------------------------------------------------------------ near misses --

  # A feat's name nobody wrote into the dictionary — `Luck of Heros`, `GRT
  # DEX`, `Armour Skin`, `ironwll` — read as the ONE feat it is a typo or a
  # shorthand of (task 4.31). Always a guess (`{:guess, id}`), reported to the
  # player once per build (`{:feats_guessed, …}`): a guess the player can see
  # and reject is tolerance, a silent one is invention.
  #
  # Word by word, each word written has to fit the name's word in the same
  # place:
  #
  #   * the start of it (`Dex`, `Imp`) — what `word_prefix_feat/2` reads for
  #     sure, so at least one other word has to be a looser fit;
  #   * one typo away, for words of four letters and more — a letter missing,
  #     added, changed, or two swapped (`Heros`, `Armour`, `Lighting`, `Willl`);
  #   * the name's word and a short ending (`Greater` for `Great`, `Fighting`
  #     for `Fight`);
  #   * its shorthand, three letters and more, the first one kept: its
  #     consonants in order (`Grt`, `Chr`, `Wpn`), or so after one swapped pair
  #     (`GTR`); its letters in order, half the word or more (`Wep`,
  #     `Dextery`); or the first letter and the word's own ending (`Kdown`).
  #     Short and with vowels, letters in order make a different word: `Stun`
  #     and `Song` are letters of Stonecunning too, `DRII` of Darkvision.
  #
  # Or, the words run together, the whole name one typo away (`ironwll`) —
  # only when fewer words are written than the name has: `I.Evasion` is
  # Improved Evasion, not Evasion with a stray letter. A word glued from two
  # (`GrDEX`, `GrWis`) is parted where a small letter meets a capital. Two
  # feats that fit are refused, not tossed for.
  def near_feat(index, name), do: near_feat_by_forms(index, name_forms(name))

  # The same, for a name's forms worked out already: the shortest is read.
  #
  # `glued?` — whether a name run together (`ironwll`) is looked for too: it
  # walks every feat's name, where the words written walk only the names of as
  # many words. A question asked of every item (`LevelTail`, task 4.36) asks
  # the words alone.
  def near_feat_by_forms(index, forms, glued? \\ true) do
    {bare, _letters} = List.last(forms)

    # `Grt Dex Dex I` — a word written twice running is one word.
    typed =
      bare
      |> String.replace(~RX/(?<=\p{Ll})(?=\p{Lu})/u, " ")
      |> name_words()
      |> Enum.dedup()

    matches =
      if typed == [] or Enum.all?(typed, &(String.length(&1) < 3)) do
        []
      else
        joined = Enum.join(typed)

        # Each typed word measured once, not once per word of the dictionary
        # (task 4.34: a word of sixty thousand letters was walked through for
        # every one of them).
        measured = Enum.map(typed, &{&1, String.length(&1)})

        by_words =
          for %{id: id, words: words} <- Map.get(index.feat_words_by_count, length(typed), []),
              Enum.zip(measured, words) |> Enum.all?(fn {t, w} -> word_fits?(t, w) end),
              do: id

        glued =
          if glued? and String.length(joined) >= 6,
            do:
              for(
                %{id: id, words: words, joined: name} <- index.feat_words,
                length(words) > length(typed),
                within_one?(joined, name),
                do: id
              ),
            else: []

        Enum.uniq(by_words ++ glued)
      end

    case matches do
      [id] -> {:guess, id}
      _ -> :error
    end
  end

  defp word_fits?({typed, typed_length}, word) do
    word_length = String.length(word)

    typed == word or
      (typed_length >= 2 and String.starts_with?(word, typed)) or
      (min(typed_length, word_length) >= 4 and within_one?(typed, word)) or
      (word_length >= 4 and String.starts_with?(typed, word) and
         typed_length - word_length <= if(word_length >= 5, do: 3, else: 2)) or
      shorthand?(typed, typed_length, word, word_length)
  end

  defp shorthand?(typed, word),
    do: shorthand?(typed, String.length(typed), word, String.length(word))

  defp shorthand?(typed, typed_length, word, word_length) do
    first = String.first(typed)
    rest = String.slice(typed, 1..-1//1)

    typed_length >= 3 and typed_length < word_length and
      first == String.first(word) and
      ((not Regex.match?(~RX/[aeiouy]/u, rest) and
          (subsequence?(typed, word) or Enum.any?(swaps(typed), &subsequence?(&1, word)))) or
         (String.length(typed) * 2 >= String.length(word) and subsequence?(typed, word)) or
         (String.length(rest) >= 3 and String.ends_with?(word, rest)))
  end

  defp subsequence?(small, big),
    do: subsequence_of?(String.graphemes(small), String.graphemes(big))

  defp subsequence_of?([], _big), do: true
  defp subsequence_of?(_small, []), do: false
  defp subsequence_of?([a | small], [a | big]), do: subsequence_of?(small, big)
  defp subsequence_of?(small, [_ | big]), do: subsequence_of?(small, big)

  # Every spelling with one adjacent pair swapped, the first letter kept.
  defp swaps(text) do
    letters = String.graphemes(text)

    for at <- 1..(length(letters) - 2)//1 do
      {left, [a, b | right]} = Enum.split(letters, at)
      Enum.join(left ++ [b, a] ++ right)
    end
  end

  # One edit apart: a letter missing, added or changed, or two neighbours
  # swapped (the optimal string alignment distance 1), and never equal.
  #
  # `a` is counted no further than it can matter (task 4.34): two graphemes
  # longer than `b`, it is more than one edit away however long it is — and a
  # word of sixty thousand letters was taken apart for every name it was
  # held against.
  defp within_one?(a, b) do
    y = String.graphemes(b)

    case graphemes_upto(a, length(y) + 2, 0) - length(y) do
      0 -> one_change?(String.graphemes(a), y)
      1 -> one_dropped?(String.graphemes(a), y)
      -1 -> one_dropped?(y, String.graphemes(a))
      _ -> false
    end
  end

  # How many graphemes `text` has, or `cap` if it has as many or more.
  defp graphemes_upto(_text, cap, count) when count >= cap, do: count

  defp graphemes_upto(text, cap, count) do
    case String.next_grapheme_size(text) do
      {_size, rest} -> graphemes_upto(rest, cap, count + 1)
      nil -> count
    end
  end

  defp one_change?(x, y) do
    diffs = for {{a, b}, at} <- Enum.with_index(Enum.zip(x, y)), a != b, do: at

    case diffs do
      [_] ->
        true

      [at, next] when next == at + 1 ->
        Enum.at(x, at) == Enum.at(y, next) and Enum.at(x, next) == Enum.at(y, at)

      _ ->
        false
    end
  end

  defp one_dropped?(longer, shorter) do
    Enum.any?(0..(length(longer) - 1)//1, &(List.delete_at(longer, &1) == shorter))
  end

  defp word_prefix_feat(index, text) do
    words = name_words(text)

    matches =
      if words == [] or Enum.any?(words, &(String.length(&1) < 2)) or
           Enum.all?(words, &(String.length(&1) < 3)) do
        []
      else
        for %{id: id, words: name} <- index.feat_words,
            length(name) == length(words),
            Enum.zip(words, name)
            |> Enum.all?(fn {typed, full} -> String.starts_with?(full, typed) end),
            uniq: true,
            do: id
      end

    case matches do
      [id] -> {:ok, id}
      [] -> :error
      many -> {:ambiguous, many}
    end
  end

  def name_words(text) do
    text
    |> String.downcase()
    |> String.replace("ё", "е")
    |> String.split(~RX/[^\p{L}\p{N}]+/u, trim: true)
  end

  # ----------------------------------------------------------- choice values --

  # `Electricity` for the value the game calls `Electrical`, `Daggers` for
  # `Dagger`, `Constructs` for `Construct` (task 4.31): the one value of the
  # domain the written words are, all but the last as they stand and the last
  # sharing its stem — four letters and more in common, six with the words
  # before it, what differs an ending of four letters at most. A guess,
  # reported like a feat's. A typo inside the stem (`Evokation`) stays the
  # error it was, and so does a value with something written after it
  # (`Rapier Dex` — a bump, not a longer rapier).
  def near_value(ruleset, index, id, text) do
    domain = Rules.feat_choice_domain(id, ruleset)
    typed = text |> strip_rank() |> name_words()

    with values when is_map(values) <- domain && Map.get(index.choices, domain),
         [value] <-
           Enum.uniq(
             for {_key, ids} <- values,
                 value <- ids,
                 name <- value_names(ruleset, id, value),
                 same_stem?(typed, name_words(name)),
                 do: value
           ) do
      value
    else
      _ -> nil
    end
  end

  defp value_names(ruleset, feat, value),
    do: Enum.uniq([Atom.to_string(value), Labels.choice_name(ruleset, feat, value)])

  defp same_stem?(typed, words) when length(typed) != length(words) or typed == [], do: false

  defp same_stem?(typed, words) do
    {head, [last]} = Enum.split(typed, -1)
    {name_head, [name_last]} = Enum.split(words, -1)
    common = common_prefix(last, name_last)
    ending = &(String.length(&1) - common)

    head == name_head and last != name_last and common >= 4 and
      common + String.length(Enum.join(head)) >= 6 and ending.(last) <= 4 and
      ending.(name_last) <= 4
  end

  # How many graphemes `a` and `b` open with alike — walked side by side up to
  # the first that differ, not taken apart whole first (task 4.34: a word of
  # sixty thousand letters was, for every name it was held against).
  def common_prefix(a, b), do: common_prefix(a, b, 0)

  defp common_prefix(a, b, count) do
    case {String.next_grapheme(a), String.next_grapheme(b)} do
      {{same, a}, {same, b}} -> common_prefix(a, b, count + 1)
      _ -> count
    end
  end

  # The value as written; then without a roman rank (`Fire I` — the rank of
  # `Epic Energy Resistance`, not part of the element); then by a unique prefix
  # (`Unarmed` for `Unarmed strike`, `Scim`), the class's and the skill's own
  # second chance; then, for a skill, the way a skill is read anywhere else
  # (`Epic Skill Focus: UMD`). A prefix two values share (`Long`) reads as
  # nothing.
  def choice_value(ruleset, index, id, text) do
    domain = Rules.feat_choice_domain(id, ruleset)

    case domain && Map.get(index.choices, domain) do
      nil ->
        :no_domain

      values ->
        with :error <- only_ok(resolve(values, text)),
             :error <- only_ok(resolve(values, strip_rank(text))),
             :error <- prefix_value(values, strip_rank(text)) do
          skill_choice(domain, values, index, text)
        end
    end
  end

  def only_ok({:ok, value}), do: {:ok, value}
  def only_ok(_other), do: :error

  def prefix_value(values, text) do
    key = norm(text)

    matches =
      if byte_size(key) < 3,
        do: [],
        else:
          for(
            {name, ids} <- values,
            String.starts_with?(name, key),
            id <- ids,
            uniq: true,
            do: id
          )

    case matches do
      [value] -> {:ok, value}
      _ -> :error
    end
  end

  defp strip_rank(text), do: String.replace(text, ~RX/\s+[IVXivx]+\+?\s*$/u, "")

  defp skill_choice(:skill, values, index, text) do
    with {:ok, id} <- resolve_skill(index, text),
         true <- values |> Map.values() |> Enum.any?(&(id in &1)) do
      {:ok, id}
    else
      _ -> :error
    end
  end

  defp skill_choice(_domain, _values, _index, _text), do: :error
end
