defmodule BuildCalculatorWeb.Builder.Import.Issues do
  @moduledoc """
  The wording of every issue the reader can produce, the group each is shown
  in, and every issue shape (`issue_forms/0`) — the list the tests hold the
  wording to. A part of `BuildCalculatorWeb.Builder.Import`, which documents
  the three functions its callers use.
  """

  use Gettext, backend: BuildCalculatorWeb.Gettext

  alias BuildCalculatorWeb.Builder.{Feats, Labels}
  alias BuildCalculatorWeb.Builder.Import.Scan

  @max_bytes Scan.max_bytes()

  def issue_text({:unknown_class, level, text}, _ruleset),
    do: gettext("level %{level}: class “%{text}” not recognized", level: level, text: text)

  def issue_text({:ambiguous_class, level, text, ids}, ruleset),
    do:
      gettext(
        "level %{level}: “%{text}” matches several classes (%{classes}) — we won't pick one for you",
        level: level,
        text: text,
        classes: Enum.map_join(ids, ", ", &Labels.class_name(ruleset, &1))
      )

  def issue_text({:class_guessed, level, text, class}, ruleset),
    do:
      gettext(
        "level %{level}: “%{text}” read as %{class} from an abbreviation — check it",
        level: level,
        text: text,
        class: Labels.class_name(ruleset, class)
      )

  # ⚠️ Задача 4.53: все три русские формы — прежний литерал «на N уровнях»
  # (при N = 1 он неграмотен, починка — правкой `msgstr`, HANDOFF.md 4.11).
  def issue_text({:ladder_stopped, kept}, _ruleset),
    do:
      ngettext(
        "the leveling guide stops after %{count} level: we can't guess the order of classes after a line we couldn't read — BAB and saves past level 20 depend on it",
        "the leveling guide stops after %{count} levels: we can't guess the order of classes after a line we couldn't read — BAB and saves past level 20 depend on it",
        kept
      )

  def issue_text({:level_gap, expected, found}, _ruleset),
    do:
      gettext(
        "the leveling guide has no level %{expected} (the next line is %{found}) — we stop reading there",
        expected: expected,
        found: found
      )

  def issue_text({:level_over_cap, level, cap}, _ruleset),
    do: gettext("level %{level} is above the cap of %{cap} — cut off", level: level, cap: cap)

  def issue_text({:unknown_class_in_header, text}, _ruleset),
    do: gettext("class “%{text}” in the header not recognized", text: text)

  def issue_text({:no_leveling_guide}, _ruleset),
    do:
      gettext(
        "the text has no leveling guide (LEVELING GUIDE), and the header can't give the order of classes: it names only the total for each class"
      )

  def issue_text({:split_mismatch, text, declared, actual}, _ruleset),
    do:
      gettext("the header promises %{text}(%{declared}), the leveling guide adds up to %{actual}",
        text: text,
        declared: declared,
        actual: actual
      )

  # ⚠️ Задача 4.4: импорт текста виден на ванили, и замечание говорит от
  # имени правил, чей лимит назван (`limit` — `ruleset.max_classes` того
  # ruleset'а, по которому читают): английский msgid без Сиалы, число классов
  # — через `ngettext` (у ванили лимит 3, и «4 классов» было бы ошибкой).
  # Русский перевод — прежний текст, с «на Сиале» (русский каталог — язык
  # сиальской редакции, шапка раздела 4.4 в `ru/default.po`).
  def issue_text({:too_many_classes, used, limit}, _ruleset),
    do:
      ngettext(
        "the build has %{count} class, the limit is %{limit} — the rules do not allow such a build",
        "the build has %{count} classes, the limit is %{limit} — the rules do not allow such a build",
        used,
        limit: limit
      )

  def issue_text({:unknown_race, text}, _ruleset),
    do: gettext("race “%{text}” not recognized", text: text)

  def issue_text({:ambiguous_race, text, _ids}, _ruleset),
    do: gettext("race “%{text}” matches several at once — we don't pick one", text: text)

  # Задача 4.31: раса — выбор автора из нескольких, догадка по опечатке,
  # подпись листа характеристик. Английский msgid, русский `msgstr`.
  def issue_text({:race_guessed, text, race}, ruleset),
    do:
      gettext("race “%{text}” read as %{race} — one letter off, check it",
        text: text,
        race: Labels.race_label(ruleset, race)
      )

  def issue_text({:race_chosen, text, race, races}, ruleset),
    do:
      gettext(
        "the text offers a choice of races (%{races}) — read as %{race}, the author's pick: “%{text}”",
        races: Enum.map_join(races, ", ", &Labels.race_label(ruleset, &1)),
        race: Labels.race_label(ruleset, race),
        text: text
      )

  def issue_text({:race_alternatives, text, races}, ruleset),
    do:
      gettext(
        "the text offers a choice of races (%{races}) and does not say which one the numbers are for — pick one yourself: “%{text}”",
        races: Enum.map_join(races, ", ", &Labels.race_label(ruleset, &1)),
        text: text
      )

  def issue_text({:race_by_sheet, text, race, caption}, ruleset),
    do:
      gettext(
        "the text offers a choice of races (“%{text}”); the score sheet is captioned “%{caption}” — read as %{race}",
        text: text,
        caption: caption,
        race: Labels.race_label(ruleset, race)
      )

  def issue_text({:unknown_alignment, text}, _ruleset),
    do: gettext("alignment “%{text}” not recognized", text: text)

  # Задача 4.8: `Any non-lawful` — не мировоззрение, а ограничение на него,
  # и выбирать одно из подходящих за игрока нельзя (это та же догадка, что
  # и выбор между двумя классами). Английский msgid, русский `msgstr`.
  def issue_text({:alignment_restriction, text}, _ruleset),
    do:
      gettext(
        "the text states an alignment restriction (%{text}), not an alignment — pick one yourself",
        text: text
      )

  def issue_text({:unknown_feat, level, text}, _ruleset),
    do: gettext("level %{level}: no feat “%{text}” in our list", level: level, text: text)

  # Задача 4.31: имена, прочитанные по догадке (опечатка, сокращение,
  # сокращение, которому отвечают два фита, а выбрать можно один), — одной
  # оговоркой на билд. Английский msgid, русский `msgstr`.
  def issue_text({:feats_guessed, guesses}, ruleset),
    do:
      gettext("read by a guess — check it: %{list}",
        list: Enum.map_join(guesses, "; ", &guess_text(&1, ruleset))
      )

  def issue_text({:ambiguous_feat, level, text, ids}, ruleset),
    do:
      gettext("level %{level}: “%{text}” matches several feats (%{feats})",
        level: level,
        text: text,
        feats: Enum.map_join(ids, ", ", &Labels.feat_name(ruleset, &1))
      )

  # ⚠️ Формулировка изменилась вместе с механикой: школы магии, расы-враги, типы
  # урона и навыки теперь ХРАНЯТСЯ, и обещать обратное было бы неправдой.
  # Осталось ровно оружие — справочника нет и не будет до армори.
  def issue_text({:feat_qualifier_dropped, level, feat, qualifier}, ruleset),
    do:
      gettext(
        "level %{level}: %{feat} is taken, but we don't keep the detail “%{qualifier}” — we have no list for it",
        level: level,
        feat: Labels.feat_name(ruleset, feat),
        qualifier: qualifier
      )

  # Формулировку самого отказа даёт `Labels.reason/2` — тот же текст, который
  # игрок видит в конструкторе. Своя копия разошлась бы с ней.
  def issue_text({:illegal_level, level, class, reason}, ruleset),
    do:
      gettext("level %{level}: %{class} can't be taken here — %{reason}",
        level: level,
        class: Labels.class_name(ruleset, class),
        reason: Labels.reason(reason, ruleset)
      )

  def issue_text({:feat_choice_unknown, level, feat, qualifier}, ruleset),
    do:
      gettext(
        "level %{level}: %{feat} is taken without its choice — “%{qualifier}” is not in our list",
        level: level,
        feat: Labels.feat_name(ruleset, feat),
        qualifier: qualifier
      )

  # Задача 4.59: причину называет ядро (с 4.40 — `Feats.unplaced_reason/5`). «Нет
  # свободного слота» — прежняя фраза байт в байт; остальные причины — словами
  # выбора фитов (`Feats.reason/2`, та же короткая форма, что у окна лога: имя
  # фита уже стоит в предложении).
  def issue_text({:feat_no_slot, level, feat, {:no_free_slot, _feat}}, ruleset),
    do:
      gettext("level %{level}: nowhere to put %{feat} — no suitable free slot at this level",
        level: level,
        feat: Labels.feat_name(ruleset, feat)
      )

  def issue_text({:feat_no_slot, level, feat, reason}, ruleset),
    do:
      gettext("level %{level}: nowhere to put %{feat} — %{reason}",
        level: level,
        feat: Labels.feat_name(ruleset, feat),
        reason: Feats.reason(reason, ruleset)
      )

  def issue_text({:feat_granted_here, level, feat}, ruleset),
    do:
      gettext("level %{level}: %{feat} is granted by class — the slot is left free",
        level: level,
        feat: Labels.feat_name(ruleset, feat)
      )

  def issue_text({:feat_already_owned, level, feat}, ruleset),
    do:
      gettext("level %{level}: the character already has %{feat} — skipped",
        level: level,
        feat: Labels.feat_name(ruleset, feat)
      )

  def issue_text({:unknown_skill, level, text}, _ruleset),
    do: gettext("level %{level}: skill “%{text}” not recognized", level: level, text: text)

  def issue_text({:ambiguous_skill, level, text, _ids}, _ruleset),
    do:
      gettext("level %{level}: skill “%{text}” matches several — we don't pick one",
        level: level,
        text: text
      )

  # Число в скобках — форма слова от него не зависит ни в одном языке.
  def issue_text({:skills_not_placed, count}, _ruleset),
    do:
      gettext(
        "skills (%{count}) are not carried over to the build: the SKILLS block gives only the totals, and a rank's cost and max ranks depend on the level it was bought at",
        count: count
      )

  # ⚠️ Задача 4.53: все три русские формы — прежний литерал «на N уровнях».
  def issue_text({:skill_ranks_past_ladder, count}, _ruleset),
    do:
      ngettext(
        "skill ranks at %{count} level past the leveling guide we read are dropped",
        "skill ranks at %{count} levels past the leveling guide we read are dropped",
        count
      )

  def issue_text({:feats_without_levels, count}, _ruleset),
    do:
      gettext(
        "feats (%{count}) are listed without levels — we can't tell which slots they go into",
        count: count
      )

  def issue_text({:abilities_missing}, _ruleset),
    do: gettext("the text has no ability scores — the point-buy minimum is set")

  # Задача 4.31: лист характеристик, в котором есть не все шесть.
  def issue_text({:abilities_partial, missing}, _ruleset),
    do:
      ngettext(
        "the score sheet does not give %{abilities} — the point-buy minimum is set for it",
        "the score sheet does not give %{abilities} — the point-buy minimum is set for them",
        length(missing),
        abilities: Enum.map_join(missing, ", ", &Labels.ability/1)
      )

  def issue_text({:abilities_without_race}, _ruleset),
    do:
      gettext(
        "race not recognized, so the racial modifiers are not taken off the ability scores — check the starting numbers"
      )

  def issue_text({:ability_off_point_buy, ability, score}, _ruleset),
    do:
      gettext(
        "%{ability} %{score} without the racial modifier is outside the point-buy range — carried over as is",
        ability: Labels.ability(ability),
        score: score
      )

  # ⚠️ Задача 4.53: все три русские формы — прежний литерал «на N байтах».
  def issue_text({:text_clipped, bytes}, _ruleset),
    do:
      ngettext(
        "the text is cut at %{count} byte — the rest was not read",
        "the text is cut at %{count} bytes — the rest was not read",
        bytes
      )

  # Задача 4.34: байты, которые не складываются в UTF-8, — заменены, а не
  # роняют разбор (`Scan.paste/1`).
  def issue_text({:invalid_utf8, count}, _ruleset),
    do:
      ngettext(
        "%{count} place in the text is not UTF-8 text — replaced with “�”; the rest is read",
        "%{count} places in the text are not UTF-8 text — replaced with “�”; the rest is read",
        count
      )

  def issue_text({:ignored_line, number, text}, _ruleset),
    do:
      gettext("line %{number}: “%{text}” — we couldn't tell what this is",
        number: number,
        text: ellipsis(text)
      )

  # Задача 4.31: прибавки отдельным списком («Bump Str at levels 4, 8, …»).
  def issue_text({:increase_list_disagrees, level, ladder, listed}, _ruleset),
    do:
      gettext(
        "level %{level}: the leveling guide raises %{ladder}, the list of increases says %{listed} — the leveling guide's is kept",
        level: level,
        ladder: Labels.ability(ladder),
        listed: Labels.ability(listed)
      )

  # Задача 4.36: прибавка, выписанная на уровне, который её не даёт, — в билд
  # не идёт (ядро сложило бы её молча, `Abilities.scores_at/3`).
  def issue_text({:increase_off_level, level, ability}, _ruleset),
    do:
      gettext(
        "level %{level}: the text raises %{ability} here, but this level grants no ability increase — not carried over",
        level: level,
        ability: Labels.ability(ability)
      )

  def issue_text({:increase_list_unread, levels}, _ruleset),
    do:
      gettext(
        "the list of increases names levels %{levels}, and not all of them grant one — not carried over",
        levels: Enum.join(levels, ", ")
      )

  # Задача 4.31: строка выбора класса (`Domains: …`), прочитанная не целиком.
  def issue_text({:class_choice_unread, line}, _ruleset),
    do:
      gettext("“%{line}” names a class's choice we could not read whole — pick it yourself",
        line: ellipsis(line)
      )

  # Задача 4.31: прибавки за уровни, которых лестница не называет.
  def issue_text({:increases_restored, ability, levels, final}, _ruleset),
    do:
      ngettext(
        "the leveling guide does not name the ability increase at level %{levels}; the text gives %{ability} %{final} at the end, exactly one more than without it — put into %{ability}",
        "the leveling guide does not name the ability increases at levels %{levels}; the text gives %{ability} %{final} at the end, exactly %{count} more than without them — all put into %{ability}",
        length(levels),
        levels: Enum.join(levels, ", "),
        ability: Labels.ability(ability),
        final: final
      )

  def issue_text({:increases_unplaced, levels, short}, _ruleset),
    do:
      ngettext(
        "the leveling guide does not name the ability increase at level %{levels}, and the scores the text gives at the end do not say which one it went into (%{short}) — not carried over",
        "the leveling guide does not name the ability increases at levels %{levels}, and the scores the text gives at the end do not say which level took which (%{short}) — not carried over",
        length(levels),
        levels: Enum.join(levels, ", "),
        short: short_text(short)
      )

  def issue_text({:increases_unnamed, levels}, _ruleset),
    do:
      ngettext(
        "the leveling guide does not name the ability increase at level %{levels} — it is not in the build",
        "the leveling guide does not name the ability increases at levels %{levels} — they are not in the build",
        length(levels),
        levels: Enum.join(levels, ", ")
      )

  def issue_text(other, _ruleset), do: inspect(other)

  defp short_text(short) when map_size(short) == 0,
    do: gettext("they match ours without the increases")

  defp short_text(short) do
    short
    |> Enum.sort_by(fn {ability, _} ->
      Enum.find_index(Labels.ability_order(), &(&1 == ability))
    end)
    |> Enum.map_join(", ", fn {ability, count} ->
      "#{Labels.ability(ability)} #{signed(count)}"
    end)
  end

  defp guess_text({text, reading, level}, ruleset),
    do:
      gettext("“%{text}” as %{name} (level %{level})",
        text: text,
        name: guess_name(reading, ruleset),
        level: level
      )

  defp guess_name({feat, value}, ruleset),
    do: Labels.feat_name(ruleset, feat) <> ": " <> Labels.choice_name(ruleset, feat, value)

  defp guess_name(feat, ruleset), do: Labels.feat_name(ruleset, feat)

  def ellipsis(text) do
    if String.length(text) > 60, do: String.slice(text, 0, 57) <> "…", else: text
  end

  def issue_kind(issue), do: issue |> issue_family() |> family_title()

  defp issue_family({:unknown_class, _level, _text}), do: :not_recognised
  defp issue_family({:ambiguous_class, _level, _text, _ids}), do: :not_recognised
  defp issue_family({:unknown_class_in_header, _text}), do: :not_recognised
  defp issue_family({:unknown_race, _text}), do: :not_recognised
  defp issue_family({:ambiguous_race, _text, _ids}), do: :not_recognised
  defp issue_family({:unknown_alignment, _text}), do: :not_recognised
  defp issue_family({:unknown_feat, _level, _text}), do: :not_recognised
  defp issue_family({:ambiguous_feat, _level, _text, _ids}), do: :not_recognised
  defp issue_family({:unknown_skill, _level, _text}), do: :not_recognised

  # Опечатка в школе — это «не распознано», а не «не перенесено»: строку писал
  # человек, и разница между «мы такого не знаем» и «мы такое не храним»
  # для него — разница между «поправь» и «ничего не поделать».
  defp issue_family({:feat_choice_unknown, _level, _feat, _text}), do: :not_recognised
  defp issue_family({:ambiguous_skill, _level, _text, _ids}), do: :not_recognised

  # Its own group, and not out of tidiness: «не нашли такой фит» is a question
  # about our dictionary, «не поняли, что это за строка» is a question about the
  # paste. Mixed together, the prose lines bury the misses that matter.
  defp issue_family({:ignored_line, _number, _text}), do: :skipped_lines

  # A guess is neither a miss nor a loss: it is a reading the player has to
  # confirm, and it belongs in the group they are most likely to actually read.
  defp issue_family({:class_guessed, _level, _text, _class}), do: :assumed
  defp issue_family({:feats_guessed, _guesses}), do: :assumed
  defp issue_family({:increases_restored, _ability, _levels, _final}), do: :assumed
  defp issue_family({:race_guessed, _text, _race}), do: :assumed
  defp issue_family({:race_chosen, _text, _race, _races}), do: :assumed
  defp issue_family({:race_by_sheet, _text, _race, _caption}), do: :assumed

  # Своя группа: остальные «спорит с собой» — про то, что в тексте одно место
  # противоречит другому. Здесь текст внутренне непротиворечив, а спорит он
  # с правилами шарда, и починить это можно только правкой билда.
  defp issue_family({:illegal_level, _level, _class, _reason}), do: :breaks_rules

  defp issue_family({:split_mismatch, _text, _declared, _actual}), do: :contradicts_itself
  defp issue_family({:increase_list_disagrees, _level, _ladder, _listed}), do: :contradicts_itself
  defp issue_family({:too_many_classes, _used, _limit}), do: :contradicts_itself
  defp issue_family({:ability_off_point_buy, _ability, _score}), do: :contradicts_itself

  defp issue_family(_other), do: :not_carried_over

  defp family_title(:not_recognised), do: gettext("Not recognized")
  defp family_title(:skipped_lines), do: gettext("Skipped lines")
  defp family_title(:assumed), do: gettext("Read with an assumption")
  defp family_title(:breaks_rules), do: gettext("Breaks the rules")
  defp family_title(:contradicts_itself), do: gettext("The source contradicts itself")
  defp family_title(:not_carried_over), do: gettext("Not carried over")

  # The contract of `BuildCalculatorWeb.Builder.Import.issue_forms/0`: an issue
  # the reader is taught to produce is worded in `issue_text/2` above and listed
  # here, or the tests fail.
  #
  # The quoted samples stand for what a player pasted and we did not know — the
  # format's text is English, so they are English too (task 4.53): an echo of
  # someone else's input is not our wording, and the en-guard zone over these
  # forms (`import_issues`) is meant to count only what the site writes itself.
  def issue_forms do
    [
      {:unknown_class, 5, "Ftr"},
      {:ambiguous_class, 5, "Pal", [:paladin, :pale_master]},
      {:class_guessed, 2, "Ftr", :fighter},
      {:ladder_stopped, 4},
      {:level_gap, 5, 7},
      {:level_over_cap, 42, 41},
      {:unknown_class_in_header, "Ftr"},
      {:no_leveling_guide},
      {:split_mismatch, "Fighter", 10, 9},
      {:too_many_classes, 5, 4},
      {:unknown_race, "Hobbit"},
      {:ambiguous_race, "Elvish", [:elf, :half_elf]},
      {:race_guessed, "Hafling", :halfling},
      {:race_chosen, "Human or Elf (I choose human here)", :human, [:human, :elf]},
      {:race_alternatives, "Human or Elf", [:human, :elf]},
      {:race_by_sheet, "Human or Elf", :human, "Human Stats"},
      {:unknown_alignment, "Chaotic Kind"},
      {:alignment_restriction, "Any non-lawful"},
      {:unknown_feat, 3, "Mystic Strike"},
      {:feats_guessed,
       [{"Luck of Heros", :luck_of_heroes, 1}, {"Electricity", {:resist_energy, :electrical}, 2}]},
      {:increases_restored, :dex, [4, 8, 12], 19},
      {:increases_unplaced, [4, 8], %{dex: 1, con: 1}},
      {:increases_unnamed, [4, 8]},
      {:class_choice_unread, "Domains: Air, Your Choice"},
      {:increase_list_disagrees, 8, :str, :dex},
      {:increase_off_level, 30, :dex},
      {:increase_list_unread, [4, 9]},
      {:ambiguous_feat, 3, "WF", [:weapon_focus, :weapon_finesse]},
      {:feat_qualifier_dropped, 3, :weapon_focus, "longsword"},
      {:feat_choice_unknown, 3, :spell_focus, "Evokation"},
      {:illegal_level, 32, :weapon_master, {:class_level_cap, :weapon_master, 31}},
      {:feat_no_slot, 3, :toughness, {:no_free_slot, :toughness}},
      {:feat_no_slot, 2, :dodge, {:no_feat_slot_at_level, :dodge}},
      {:feat_no_slot, 2, :evasion, {:not_slottable, "class"}},
      {:feat_granted_here, 1, :toughness},
      {:feat_already_owned, 6, :toughness},
      {:unknown_skill, 1, "Basket Weaving"},
      {:ambiguous_skill, 1, "Craft", [:craft_armor, :craft_trap, :craft_weapon]},
      {:skills_not_placed, 12},
      {:skill_ranks_past_ladder, 3},
      {:feats_without_levels, 14},
      {:abilities_missing},
      {:abilities_without_race},
      {:abilities_partial, [:str, :con]},
      {:ability_off_point_buy, :str, 20},
      {:text_clipped, @max_bytes},
      {:invalid_utf8, 3},
      {:ignored_line, 12, "some prose around the build"}
    ]
  end

  # A number with its sign, `?` for none — how a total prints; `Comparison`
  # writes ours beside the source's the same way.
  def signed(nil), do: "?"
  def signed(value) when value >= 0, do: "+#{value}"
  def signed(value), do: Integer.to_string(value)
end
