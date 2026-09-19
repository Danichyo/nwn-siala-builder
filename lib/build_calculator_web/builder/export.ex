defmodule BuildCalculatorWeb.Builder.Export do
  @moduledoc """
  The build as a plain-text block — two shapes, one per ruleset (task 3.145).

  `vanilla` prints the Epic Character Builders posting format (CLAUDE.md §3) —
  the de-facto exchange format on forums and in Discord — unchanged: block
  order as specified, English entity names, and the per-level skill spend as
  its own `SKILL GUIDE` list rather than crammed into the level lines. Other
  people's parsers depend on this shape staying byte for byte the same, which
  is why `leveling_guide/2` and `skill_guide/2` still write exactly it.

  `siala_41` merges everything a level gives into that level's own line
  instead. Dan, 30.08.2026: «на Сиале нету пользователей EPIC CHARACTER
  BUILDERS… когда качаешься и поднимаешь уровень сразу видеть все что надо
  взять при лвл апе». `merged_guide/3` reuses `Summary.guide_rows/2` — the
  same assembly the view screen's own levelling guide already calls
  (CLAUDE.md §6, task 3.24) — rather than collecting a level's contents a
  second time; two readings of "what does this level give" have drifted
  apart before (`bonus_feat_pool`, task 3.85).

  ⚠️ `Builder.Import` is not taught the merged shape, on purpose: Siala
  players move builds with the in-game `.билд` log, never by pasting our own
  export back in (CLAUDE.md §6, Dan: «у нас отдельный импорт от команды
  `.билд` в игре, т.е. импорт и экспорт полностью разные»). So only
  `vanilla`'s two-block shape has to keep reading as its own writing —
  `import_test.exs`'s own round trips pin that on `vanilla` explicitly.

  ### `opts[:show_granted_feats]` (task 3.146)

  A `siala_41` class hands several feats over for free on level 1 (up to five
  — Monk, for one), and `merged_guide/3` used to always print every one of
  them next to the level's actual decisions. A player relayed through Dan,
  30.08.2026, looking at exactly that: «скрыть фиты, получаемые автоматически…
  по дефолту можно их спрятать, чтоб UI почище был». `text/4` now reads
  `opts[:show_granted_feats]` (default `true`, so every existing caller —
  `BuildViewLive`, every test in this suite that does not pass the key —
  keeps printing what it always printed) and threads it down to
  `granted_item/2` and `guide_legend/1`. `vanilla` ignores the key outright:
  its two-block shape never carried granted feats at all (`leveling_guide/2`
  only ever reads `build.feats`, never `row.granted`), so there is nothing in
  it to hide.

  ⚠️ `BuilderLive`'s export dialog defaults the *caller's* choice to `false`
  — this module's own default stays `true`, so any caller that does not pass
  the key (every existing test above, any future one-off script) keeps
  printing what `text/4` always printed. Flipping the module's default would
  have silently changed every caller that has not opted in.

  ### `BuildViewLive` (task 3.147)

  Dan asked for the same toggle on the view screen, 30.08.2026: «Давай ещё
  добавим эту галочку в просмотр билда». That screen is CLAUDE.md §6's
  «выданное остаётся, но обязано быть подписано» — a decision this task does
  not reopen: `○` is still shown, labelled, on request. What changes is the
  *default* — Dan, on the follow-up: «Лучше выключить по дефолту, чтобы
  разгрузить UI», the same reasoning as the constructor's, on purpose applied
  to both screens even though their audiences differ (the builder's own
  work-in-progress build vs. a stranger's shared link). `BuildViewLive` keeps
  its own `:view_show_granted?` assign (default `false`, mirroring
  `BuilderLive`'s `:export_show_granted?`) rather than this module flipping
  its default, for the identical reason above — `BuildViewLive`'s guide
  itself (`guide_section/1`, not this module) also reads that same assign to
  gate `○` on-screen, so the two representations of one build move together
  off a single control, not two.

  ### Вещи в этот текст не идут вовсе — и мини-сеты тоже (задача 3.185)

  Решение, а не умолчание. Формат гильдии — это соглашение комьюнити, чужие
  парсеры читают его байт в байт, и поля под экипировку в нём нет ни одного:
  ни оружие в руках, ни надетый доспех, ни объявленные фиты с вещи, ни
  вписанные числа не печатались здесь **никогда**. Куски мини-сетов —
  такой же ввод про экипировку, и первой строкой про вещи в этом формате
  им становиться незачем.

  ⚠️ Довод не «так короче», а **дважды по существу**:

    * добавь их — и блок перестанет быть каноническим форматом, ради которого
      он и существует (CLAUDE.md §3: «иначе экспорт ломает совместимость
      с форумами и Discord»);
    * читателю они ничего не добавляют: числа, которые куски двигают, уже
      стоят в `AB`, `AC` и `SKILLS` этого же блока — то есть строка «мини-сеты
      2, 3, 2» повторяла бы не факт, а его причину, и повторяла бы её
      в формате, где причин не печатают вовсе.

  🔴 Переносит куски **ссылка**, и это не половина решения, а его вторая
  половина: `BuildCalculator.Encoding` кодирует их с задачи 3.185, а
  `Export.file_text/5` кладёт ссылку в самый низ скачанного `.txt`
  (задача 3.180). То есть игрок, отдавший файл, отдаёт вместе с ним и куски —
  просто не строкой формата, а кодом билда.

  Races are the documented exception to "names in English" (CLAUDE.md §4): the
  shard rebuilt them rather than translating, so both names are printed —
  `Гном (Dwarf)` — which keeps the block readable on a Russian forum and still
  parseable elsewhere.

  Numbers that the rules core could not work out honestly print as `?`, and the
  block ends with the gap count. A build sheet that quietly rounds an unknown
  into a plausible number is worse than one that admits it.
  """

  use Gettext, backend: BuildCalculatorWeb.Gettext

  alias BuildCalculator.Rules.{Abilities, Build, Skills}
  alias BuildCalculatorWeb.Builder.{Gaps, Labels, Summary}

  # Потолок на стем имени файла (без `.txt`), задача 3.179. Недостижимо живыми
  # данными сегодня — лимит 4 класса на ruleset и короткие id держат реальные
  # имена около 78 символов (см. `file_name/3`'s moduledoc) — но `download`
  # получает эту строку как есть, и молчаливо растущее до тысяч символов имя
  # файла — не то, на чём стоит экономить одну строку. Держится синтетикой
  # в `export_test.exs`, не живой записью.
  @max_file_stem_length 120

  @doc """
  Renders the whole block.

  `opts[:show_granted_feats]` (default `true`) controls whether `siala_41`'s
  merged guide prints the feats a class hands over on its own (glyph `○`) —
  see the moduledoc's "`opts[:show_granted_feats]`" section. `vanilla` never
  had these in its shape and ignores the key.
  """
  @spec text(Build.t(), map(), map(), keyword()) :: String.t()
  def text(%Build{} = build, ruleset, stats, opts \\ []) do
    title = Keyword.get(opts, :title, "Build")
    show_granted? = Keyword.get(opts, :show_granted_feats, true)
    start_scores = Abilities.scores_at(build, ruleset, 0)

    [
      header(build, ruleset, stats, title),
      "",
      abilities(start_scores, stats),
      "",
      totals(stats),
      skills_block(build, ruleset, stats),
      "",
      guide_blocks(build, ruleset, show_granted?),
      "",
      footer(build, ruleset, stats)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  @doc """
  `text/4`'s own block, plus one line at the very bottom naming the build's
  own share link (task 3.180). Dan, 10.09.2026, asking for it: «внутрь файла
  на самом деле добавить ссылку было бы неплохо, можно в самый низ куда-то.
  Выводить ссылку в попапе смысла нет, она на этот момент доступна и так» —
  the *downloaded file* is the one copy that leaves the page with no way
  back to the build that made it; the on-screen `<pre>` and the "copy text"
  button sit right next to a working link already and stay exactly what
  `text/4` always printed.

  `url` is not built here — this module never touches `Phoenix`, `URI`, or
  which host served a request (its own moduledoc: pure text formatting), and
  the two callers that DO know that (`BuilderLive`'s `#share-link`,
  `BuildViewLive`'s equivalent) already have their own single place that
  decides it. Handing over the finished string keeps that a one-rule fact
  instead of growing a second opinion about what a build's link looks like
  inside this module.

  `opts` reads exactly what `text/4` reads — passed straight through, not
  re-interpreted — so a caller that already computed `text/4`'s output for
  the popup does not have to duplicate which options it used to get the same
  block here; it just adds the one thing `text/4` never had reason to know:
  where the file came from.
  """
  @spec file_text(Build.t(), map(), map(), String.t(), keyword()) :: String.t()
  def file_text(%Build{} = build, ruleset, stats, url, opts \\ []) do
    text(build, ruleset, stats, opts) <> "\n\n" <> link_line(url)
  end

  # A translated whole sentence, not two fragments glued with `<>`
  # (CLAUDE.md §4's own lesson, cited a few functions down at
  # `guide_legend/1`): one `msgid` with the URL as an interpolation, so
  # a language gettext knows nothing about the grammar of still gets one
  # real sentence back — not "Собран в конструкторе:" welded, word order
  # unchecked, to whatever `url` happens to be.
  defp link_line(url), do: gettext("Built in the constructor: %{url}", url: url)

  @doc """
  The file name for the "download as .txt" button (task 3.179, Dan: «в
  название файла можно сложить общий уровень и сколько какого класса,
  условно `fighter_10_dwarven_defender_30.txt`»).

  Same three arguments `header/4` reads. `ruleset` is not read by this
  function today — kept for the same call shape as the rest of this module,
  and because Dan's own example names classes by their bare `id`
  (`fighter`, `dwarven_defender`), not `Labels.class_name/2`'s title-cased
  English (`"Fighter"`, `"Dwarven defender"`): ids are already `[a-z0-9_]`
  atoms straight out of `priv/rules/`, exactly the spelling his example
  used, and reading `class_name/2` would have to transliterate the result
  right back down to get there.

  Class order is the order classes were TAKEN (`Enum.uniq(build.levels)`,
  the same list `header/4` folds into the posting title), never
  alphabetical: CLAUDE.md §3's own warning applies here too — past
  character level 20, order changes the build itself (`Fighter 20 → Wizard
  20` computes a different BAB than the reverse) — so an alphabetised file
  name would fold two different builds onto one name.

  An empty build (no class taken yet) has nothing to name itself after, so
  it falls back to a bare `"build.txt"` rather than a `"lvl0_.txt"` nobody
  asked for.
  """
  @spec file_name(Build.t(), map(), map()) :: String.t()
  def file_name(%Build{} = build, _ruleset, stats) do
    case Enum.uniq(build.levels) do
      [] ->
        "build.txt"

      classes ->
        level = Build.character_level(build)

        class_part =
          Enum.map_join(classes, "_", fn class ->
            "#{sanitize_file_segment(class)}_#{Map.get(stats.class_levels, class, 0)}"
          end)

        stem = "lvl#{level}_#{class_part}"

        if String.length(stem) > @max_file_stem_length do
          "lvl#{level}_build.txt"
        else
          stem <> ".txt"
        end
    end
  end

  # A ruleset's class ids are already `[a-z0-9_]` — every entry in
  # `priv/rules/*/classes.json` — so this never fires on data we ship today.
  # It stays here anyway because a browser `download` attribute takes this
  # string verbatim, with no `Plug`/`URI.encode/1` pass in between, and the
  # one way this feature could ever do something unwelcome is a future
  # class id carrying a `/` or a `..` straight into a file name. One line,
  # against a defect nobody would find until a downloaded file landed
  # somewhere it should not have. Covered by a synthetic ruleset in
  # `export_test.exs`, not a live record — there is nothing today to exercise
  # it with.
  defp sanitize_file_segment(class) do
    class
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]+/, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end

  defp header(build, ruleset, stats, title) do
    split =
      build.levels
      |> Enum.uniq()
      |> Enum.map_join(", ", fn class ->
        "#{Labels.class_name(ruleset, class)}(#{Map.get(stats.class_levels, class, 0)})"
      end)

    [
      if(split == "", do: title, else: "#{title} - #{split}"),
      "#{Labels.race_ru(ruleset, build.race)} (#{Labels.race_en(ruleset, build.race)}), " <>
        (Labels.alignment_name(build.alignment) || "—")
    ]
  end

  defp abilities(start_scores, stats) do
    for ability <- Labels.ability_order() do
      start = Map.get(start_scores, ability, 0)
      final = Map.get(stats.abilities, ability, 0)
      label = Labels.ability(ability)

      if final == start, do: "#{label}: #{start}", else: "#{label}: #{start} (#{final})"
    end
  end

  defp totals(stats) do
    [
      "Hitpoints: #{number(hitpoints(stats))}",
      "Skillpoints: #{number(stats.skill_points.earned)}",
      "Saving Throws (Fort/Ref/Will): #{signed(stats.fort)}/#{signed(stats.ref)}/#{signed(stats.will)}",
      "BAB: #{number(stats.base_attack)}",
      "AB: #{signed(stats.attack_bonus)}",
      # The second number belongs to the armoury, which does not exist yet, so
      # it stays empty instead of being invented (CLAUDE.md §1).
      "AC (naked/mundane armor and shield): #{number(stats.ac_naked)}/?",
      "Attacks per round: #{number(stats.attacks_per_round)}"
    ]
  end

  # `Hitpoints` — БЕЗ процента за мини-сеты и крафтовые вещи (`Rules.GearHitPoints`,
  # 3.186), хотя `stats.hp` его несёт. Слово Dan 12.09.2026: «если в экспорте
  # видно, что были активированы какие-то минисеты, которые дают хп, то можно
  # ХП подсчитать с мини-сетами, а если мини-сетов в экспорте вообще нет,
  # то ХП без их воздействия». В формате гильдии полей под экипировку нет
  # ни одного (решение 3.185, moduledoc), куски и крафт здесь не печатаются
  # никогда — значит, по этому правилу процент в число не входит. Вещевой CON
  # при этом входит: финальные характеристики стоят строкой выше
  # (`STR: 16 (28)`), читатель видит, откуда HP. Вычитание терма, а не третий
  # прогон `compute/2`: `gear_bonus.amount` — ровно та прибавка, и разбор HP
  # обязан сходиться с этим числом (`Summary.hp_terms/2`).
  defp hitpoints(%{hp: nil}), do: nil

  defp hitpoints(%{hp: hp, hp_breakdown: %{gear_bonus: %{amount: amount}}}), do: hp - amount

  defp hitpoints(%{hp: hp}), do: hp

  # The second number is the skill's *value*, and it comes from
  # `stats.skill_values` rather than being added up here. Assembling it as
  # `ranks + ability modifier` dropped the racial affinities (an Elf's +2 Spot),
  # the flat feat bonuses (`Alertness` +2 to Spot and Listen), the Harper Scout's
  # Bardic Knowledge, the shard's four-class stealth penalty, and printed a
  # confident `ranks + 0` for a skill whose key ability nobody wrote down. A value
  # we cannot work out prints `?` like every other number the core refused.
  #
  # ⚠ Такого навыка в корпусе сегодня нет ни одного — последним был `alchemy`,
  # и 17.08.2026 Dan назвал его характеристику (кейс P1). Печать «?» от этого
  # не отменяется: она проверяется на ruleset'е с вынутым полем
  # (`export_test.exs`), потому что навык шарда без ванильной основы придёт
  # без него снова.
  #
  # The canonical posting format has one slot per skill and no room for a
  # breakdown, so what the number is made of is said on the view screen instead
  # (`Summary.skill_rows/3`), not here.
  defp skills_block(build, ruleset, stats) do
    level = Build.character_level(build)

    ranked =
      for {id, skill} <- Enum.sort_by(ruleset.skills, fn {_id, s} -> s.name end),
          ranks = Build.skill_ranks(build, id, level),
          ranks > 0 do
        "#{skill.name} #{ranks} (#{number(Summary.skill_value(stats, id))})"
      end

    if ranked == [], do: [], else: ["", "SKILLS"] ++ ranked
  end

  # Two shapes past this point (task 3.145). `vanilla` keeps the guild's own
  # two blocks — the `[leveling_guide, skill_guide]` nesting flattens exactly
  # the way it did when they were two separate elements of the pipeline list
  # above, so this changes nothing about what `vanilla` prints (and it never
  # reads `show_granted?` — its `leveling_guide/2` only ever prints
  # `build.feats`, a class's own grants were never in the shape to begin
  # with). `siala_41` replaces both with `merged_guide/3`'s single block; see
  # the moduledoc for why only `vanilla` keeps the split.
  defp guide_blocks(build, %{version: "siala_41"} = ruleset, show_granted?),
    do: merged_guide(build, ruleset, show_granted?)

  defp guide_blocks(build, ruleset, _show_granted?),
    do: [leveling_guide(build, ruleset), skill_guide(build, ruleset)]

  # `siala_41`'s own shape: one line per character level, everything that
  # level gives read off `Summary.guide_rows/2` — the same rows the view
  # screen's guide renders (CLAUDE.md §6), so a class's own choice, a known
  # spell, a skill's cross-class price and what the class handed over for
  # free all show up here exactly as they do on screen, not re-decided.
  defp merged_guide(build, ruleset, show_granted?) do
    lines =
      for row <- Summary.guide_rows(ruleset, build) do
        class = Labels.class_name(ruleset, row.class)
        nth = Build.class_level_at(build, row.level)
        items = guide_line_items(build, ruleset, row, show_granted?)

        "#{pad(row.level)}: #{class}(#{nth}):" <>
          if(items == [], do: "", else: " " <> Enum.join(items, ", "))
      end

    ["LEVELING GUIDE", guide_legend(show_granted?)] ++ lines
  end

  # Glyphs, not words — the one open decision task 3.145 leaves to this
  # module. The view screen already prints `✦`/`★`/`⚔`/`○`/`▲`/`▪`/`◆` for
  # exactly these seven things (CLAUDE.md §6's vocabulary), and every one is
  # a plain Unicode symbol from the oldest blocks (arrows and dingbats, not
  # emoji), which renders in Discord's font and any terminal without a
  # fallback box. Spelling each one out as a word would cost a whole extra
  # word on *every* item of a line whose entire point is fitting a level
  # onto one line — the thing task 3.145 exists to fix. What a screenshot
  # does not need and a bare paste does is a key, so one travels with the
  # block (`guide_legend/1`) instead of assuming the reader has
  # `#view-guide-legend` open next to it.
  #
  # ⚠️ Задача 3.177: `feat_pick_items/1` раньше звало `Labels.feat_glyph/2`
  # — глиф ПО ФИТУ (эпичен ли сам фит), а не то же правило, что у слота
  # (`Labels.slot_glyph/1`, которым уже красят и лестница конструктора, и
  # (с задачи 3.176) гид экрана просмотра). Обычный фит в ЭПИЧЕСКОМ общем
  # слоте получал бы здесь `✦`, хотя слот `★`, а фит в БОНУСНОМ слоте
  # класса эта функция вообще не умела отличить (`⚔` не входил в её
  # алфавит). Теперь у всех трёх поверхностей один читатель на одной и той
  # же карте `%{kind: …}` (`Summary.guide_feats/3`) — один и тот же фит на
  # одном уровне не может разойтись глифом между экраном просмотра,
  # лестницей конструктора и экспортом. `Labels.feat_glyph/2` — правило
  # «эпичен ли сам фит» — снято вместе с последним потребителем, а не
  # оставлено висеть без единого вызова.
  #
  # A spell's circle keeps the on-screen badge's number but drops its shape
  # — `[2]` rather than a coloured circle — because plain text has no colour
  # to carry it in; a bracketed number reads as "this many" without one.
  defp guide_line_items(build, ruleset, row, show_granted?) do
    Enum.concat([
      feat_pick_items(row.feats),
      ability_increase_item(row.increase),
      skill_pick_items(build, ruleset, row.level, row.skills),
      spell_pick_items(row.spells),
      domain_pick_item(row.domains),
      granted_item(row.granted, show_granted?)
    ])
  end

  # `ruleset` пропал из сигнатуры вместе с `feat_glyph/2`: у `row.feats`
  # (`Summary.guide_feats/3`) уже есть `:kind`, и глиф решает
  # `Labels.slot_glyph/1` без похода в справочник фитов.
  defp feat_pick_items(feats),
    do: for(feat <- feats, do: "#{Labels.slot_glyph(feat)} #{feat.name}")

  defp ability_increase_item(nil), do: []
  defp ability_increase_item(%{label: label}), do: ["▲ #{label}"]

  # Same price `skill_guide/2` already prints for `vanilla` — one core call,
  # `Skills.rank_cost/4`, read from two call sites rather than re-derived.
  defp skill_pick_items(build, ruleset, level, skills) do
    for skill <- skills do
      cost = Skills.rank_cost(build, ruleset, skill.id, level)
      suffix = if cost > 1, do: " x#{cost}", else: ""
      "▪ #{skill.name} +#{skill.ranks} (#{skill.total})#{suffix}"
    end
  end

  defp spell_pick_items(spells), do: for(spell <- spells, do: "[#{spell.circle}] #{spell.name}")

  defp domain_pick_item(nil), do: []

  defp domain_pick_item(%{label: label, names: names}),
    do: ["◆ #{label}: #{Enum.join(names, ", ")}"]

  # One `○` for the whole group, names comma-joined inside it — the same
  # shape the view screen's guide prints (`v-g-granted`), so a class that
  # hands over five feats on level 1 is one item on the line, not five.
  #
  # ⚠️ `show_granted? == false` (task 3.146) drops the item outright, on
  # *every* level, not just the noisy ones — a level whose only content was
  # what the class handed over (Monk 2, say) is left as a bare
  # `"02: Monk(2):"`, exactly the shape `vanilla` has always printed for a
  # level with nothing chosen on it. That is not a defect to paper over: the
  # line still carries the class level, and that is the player's own
  # decision, empty or not.
  defp granted_item(_granted, false), do: []
  defp granted_item([], true), do: []
  defp granted_item(granted, true), do: ["○ " <> Enum.map_join(granted, ", ", & &1.name)]

  # Two whole sentences, not one spliced with `<>` (CLAUDE.md §4's lesson from
  # `builder_live.ex`'s `ladder_class_choice/5`: a translated fragment cannot
  # be joined to another and still read as one sentence in a language gettext
  # does not know the grammar of). The legend has to drop the `○` entry the
  # moment the guide stops printing granted feats — "легенда, называющая
  # отсутствующее, хуже отсутствующей легенды" — so this is the branch that
  # keeps them in lockstep rather than a shared string with a fragment cut out
  # of it at render time.
  defp guide_legend(true) do
    gettext(
      "✦ feat picked · ★ epic feat · ⚔︎ class bonus feat · ○ feat the class hands over · ▲ +1 to an ability score · ▪ skill · [N] spell circle · ◆ a class's own choice"
    )
  end

  defp guide_legend(false) do
    gettext(
      "✦ feat picked · ★ epic feat · ⚔︎ class bonus feat · ▲ +1 to an ability score · ▪ skill · [N] spell circle · ◆ a class's own choice"
    )
  end

  defp leveling_guide(build, ruleset) do
    running = %{}

    {lines, _} =
      Enum.reduce(Enum.with_index(build.levels, 1), {[], running}, fn {class, level},
                                                                      {lines, running} ->
        running = Map.update(running, class, 1, &(&1 + 1))

        extras =
          feat_names(build, ruleset, level) ++ ability_increase(build, ruleset, level)

        line =
          "#{pad(level)}: #{Labels.class_name(ruleset, class)}(#{running[class]}):" <>
            if(extras == [], do: "", else: " " <> Enum.join(extras, ", "))

        {[line | lines], running}
      end)

    ["LEVELING GUIDE" | Enum.reverse(lines)]
  end

  defp feat_names(build, ruleset, level) do
    build.feats
    |> Map.get(level, %{})
    # ⚠️ Тот же ключ, что у гида экрана просмотра и у `Build.feat_picks/2`: три
    # места печатают фиты одного уровня, и раньше каждое сортировало своей копией
    # `inspect/1`. Порядок не изменился — изменилось то, что он один и назван.
    |> Enum.sort_by(fn {slot, _feat} -> Build.slot_order(slot) end)
    # ⚠️ `feat_pick_name/2`, а не `feat_name/2`: в слоте лежит либо голый атом,
    # либо пара `{фит, выбор}`, и второе `feat_name/2` уронило бы протоколом
    # `String.Chars` — то есть весь экспорт целиком. Выбор печатается так, как
    # его пишет сообщество: `Spell focus (Evocation)`, — а импорт с этой стороны
    # его читает обратно.
    |> Enum.map(fn {_slot, pick} -> Labels.feat_pick_name(ruleset, pick) end)
  end

  defp ability_increase(build, ruleset, level) do
    case Map.get(build.ability_increases, level) do
      nil ->
        []

      ability ->
        score = build |> Abilities.scores_at(ruleset, level) |> Map.get(ability, 0)
        ["+1 #{Labels.ability(ability)}, #{score}"]
    end
  end

  # The guild's rules ask for the per-level skill spend as its own list: mixing
  # it into the level lines breaks other people's parsers.
  defp skill_guide(build, ruleset) do
    lines =
      for level <- 1..max(Build.character_level(build), 0)//1,
          bought = Map.get(build.skills, level, %{}),
          bought != %{} do
        parts =
          bought
          |> Enum.sort_by(fn {id, ranks} -> {-ranks, Labels.skill_name(ruleset, id)} end)
          |> Enum.map_join(", ", fn {id, ranks} ->
            total = Build.skill_ranks(build, id, level)
            cost = Skills.rank_cost(build, ruleset, id, level)
            suffix = if cost > 1, do: " x#{cost}", else: ""
            "#{Labels.skill_name(ruleset, id)} +#{ranks} (#{total})#{suffix}"
          end)

        "#{pad(level)}: #{parts}"
      end

    if lines == [], do: [], else: ["", "SKILL GUIDE"] ++ lines
  end

  # Задача 1.3 (продолжение): билд, нарушающий правила, экспортировался и
  # открывался по ссылке молча — этой строки не было вовсе. ⚠️ Решение,
  # а не недосмотр, симметричное тому, что уже стоит у `SKILLS` (см. тест
  # «строка SKILLS остаётся канонической…»): канонические блоки выше
  # (шапка, характеристики, итоги, `SKILLS`, `LEVELING GUIDE`,
  # `SKILL GUIDE`) читают чужие парсеры форумов и Discord, и дописывать
  # в них своё поле значит ломать совместимость с форматом гильдии Epic
  # Character Builders (CLAUDE.md §3). Подвал — не их территория: он и так
  # начинается с "---" и подписан «Посчитано Siala Build Calculator», то
  # есть уже за пределами того, что определяет формат. Строка про пробелы
  # в данных живёт здесь по той же причине — это её прецедент, не новый.
  #
  # UI получает то же предупреждение отдельно (`view-illegal`,
  # `#spine-illegal`) — здесь оно нужно не вместо: билд, вставленный
  # в Discord как голый текст, читают и без нашего интерфейса, и ровно
  # это — основной сценарий использования канонического формата (обмен на
  # форуме, рецензия билда другим игроком). Без строки здесь читатель
  # чужого поста узнать о нарушении не может вовсе.
  defp footer(build, ruleset, stats) do
    gap_count = length(stats.gaps)
    illegal_count = ruleset |> Labels.ladder_issues(build) |> map_size()
    # `Gaps.data_tiers/1` needs only the ruleset — same gate `@gaps.data_real_count
    # > 0` drives in both LiveViews (задача 3.88), computed here rather than
    # threaded through as an opt so every existing caller of `text/4` keeps
    # working unchanged, and so there is exactly one place that decides what
    # a "real" data gap is.
    data_gaps? = Gaps.data_tiers(ruleset).real != []

    warning =
      if illegal_count > 0 do
        # ⚠️ Не «на N уровнях»: `Labels.level_word/1` — счётная форма («3
        # уровня», как в счётчике конструктора), а после предлога «на» тут
        # был бы нужен предложный («на 3 уровнях») — расхождение нашлось
        # только прогоном на реальном экспорте, не угадано заранее. Оборот
        # «у билда N X» ту же форму берёт без предлога и без ошибки.
        " ⚠ У билда #{illegal_count} #{Labels.level_word(illegal_count)} с нарушением правил" <>
          " — открой его в конструкторе, там названы причины."
      else
        ""
      end

    # ⚠️ Задача 3.49 (18.08.2026): было «перенесены не полностью» — та же
    # over-claiming формулировка, что чинилась в постоянном баннере
    # конструктора и экрана просмотра (`BuildCalculatorWeb.Builder.Gaps`,
    # moduledoc «`ruleset.gaps` is not one list, it is three»): часть того,
    # что калькулятор не переносит в число, — решённый спор источников или
    # процитированная константа, а не дыра.
    #
    # 🔴 Задача 3.88 (24.08.2026, решение Dan): та же самая фраза устарела
    # ещё раз, теперь целиком, а не только формулировкой. Dan, глядя на
    # список из 17 в основном РЕШЁННЫХ записей: «данную секцию с сайта уже
    # убрал бы… для пользователей я предлагаю дыры больше не показывать» —
    # и это относится и к экспорту («и с экрана просмотра и в экспорте
    # прячем тоже»). Предложение «Часть правил Сиалы ещё не в расчёте»
    # теперь идёт под ворота `data_real_count > 0`, ровно как баннер
    # в обеих LiveView — и сегодня (`data_real_count == 0`, задача 3.86)
    # печатать её было бы враньём: список, который остался, — решения,
    # а не дыры.
    #
    # ⚠️ Легенда `«?»` НЕ идёт под ворота: она печатается всегда, потому что
    # `AC (naked/mundane armor and shield)` несёт литеральный `/?` на месте
    # брони (армори ещё нет) на КАЖДОМ билде без исключения — то есть «?»
    # в блоке гарантированно есть, и билд, вставленный в Discord как голый
    # текст, читают без нашего интерфейса: без легенды рядом со знаком
    # читатель чужого поста не поймёт, что он значит.
    intro =
      if data_gaps? do
        "Посчитано Siala Build Calculator. Часть правил Сиалы ещё не в расчёте;" <>
          " «?» — то, что ядро считать отказалось."
      else
        "Посчитано Siala Build Calculator. «?» — то, что ядро считать отказалось."
      end

    [
      "---",
      intro <>
        if(gap_count > 0, do: " Пробелов в этом билде: #{gap_count}.", else: "") <>
        warning <>
        off_hand_line(ruleset, stats)
    ]
  end

  # Вторая рука (задача 3.132) — тем же приёмом, что предупреждение о
  # нелегальных уровнях строкой выше: канонический формат гильдии Epic
  # Character Builders не называет для неё слота («AB» — одно число, «Attacks
  # per round» — одно число), а дописывать его значило бы менять формат,
  # который читают чужие парсеры форумов (CLAUDE.md §3). Подвал уже стоит за
  # пределами формата — он и так начинается с «---» и подписан «Посчитано
  # Siala Build Calculator», — и это ровно то же место для второй руки: билд
  # без неё печатает то же самое, что печатал раньше (`nil` → ""), билд с ней
  # не молчит про число, которого «AB:» не несёт.
  defp off_hand_line(_ruleset, %{off_hand: nil}), do: ""

  defp off_hand_line(ruleset, %{off_hand: off_hand}) do
    " Вторая рука (#{Labels.weapon_name(ruleset, off_hand.weapon)}): AB #{signed(off_hand.attack_bonus)}," <>
      " атак #{number(off_hand.attacks_per_round)}."
  end

  defp pad(level), do: level |> Integer.to_string() |> String.pad_leading(2, "0")

  defp number(nil), do: "?"
  defp number(value), do: Integer.to_string(value)

  defp signed(nil), do: "?"
  defp signed(value) when value >= 0, do: "+#{value}"
  defp signed(value), do: Integer.to_string(value)
end
