defmodule Mix.Tasks.Wiki.Parse do
  @shortdoc "Parses the cached wikitext into priv/rules/vanilla/ and siala_41/generated/"

  @moduledoc """
  Turns the raw cache written by `mix wiki.fetch` into the rules snapshot.

      mix wiki.parse

  Reads `priv/wiki_cache/fandom/`, writes `priv/rules/vanilla/feats.json`,
  `priv/rules/vanilla/spells.json`, `priv/rules/vanilla/classes.json`,
  `priv/rules/vanilla/skills.json`, `priv/rules/vanilla/races.json`,
  `priv/rules/vanilla/epic.json` and the four choice dictionaries
  (`creature_types.json`, `spell_schools.json`, `energy_types.json`,
  `weapons.json`); then reads `priv/wiki_cache/siala/` and writes
  `priv/rules/siala_41/generated/feats.json` and
  `priv/rules/siala_41/generated/spells.json`.
  **Makes no network requests** — regenerating the snapshot must never depend on
  the wikis being up, and re-running it on an unchanged cache must produce an
  empty `git diff` (records sorted by `id`, object keys emitted in a fixed order).

  ## Scope

  Feats, spells, classes, skills, races and the epic rules, all from Fandom.
  Feats and spells are the genuinely machine-readable part of either wiki:
  `{{feat|...}}` and `{{spell|...}}` with named parameters. Classes have no
  template at all and are read by `BuildCalculator.Wiki.ClassPage` out of bold
  labels and the level progression table — including the seven casters' spell
  slots, which the table carries as one column per circle. Skills have no
  template either but do have a regular bullet-label block, read by
  `BuildCalculator.Wiki.SkillPage`. The seven playable races have neither
  template nor labels and are read by `BuildCalculator.Wiki.RacePage`, which
  structures only the handful of sentence shapes that repeat across all seven and
  leaves the rest verbatim. The epic (level 21+) attack and save progressions are
  on no class page at all — they depend on character level, not class — and come
  from `BuildCalculator.Wiki.EpicRules`. Weapons (task 3.5) have a template again
  — `{{Weapon|...}}` — and its presence is what makes a page a weapon at all;
  `BuildCalculator.Wiki.WeaponPage` reads it, and `collect_weapons/5` here adds
  everything the template does *not* state: which weapons a weapon feat has a
  variant for, and which of Siala's five proficiency groups each falls into.

  Two facts are cross-checked between files rather than trusted once: the class
  skill lists on the class pages against the class lists on the skill pages, and
  the skill ids of both against each other. Every disagreement is printed; none
  is reconciled.

  A class's `granted_feats` — the feats it hands out for free, keyed by class
  level — comes from the same progression table, whose feats column mixes those
  with the bonus feat *slots* the player fills himself.
  `BuildCalculator.Wiki.ClassPage.feat_grants/1` splits the two and this task
  resolves what it read to feat ids; every fragment read as a slot or as prose is
  printed as well, so the split can be checked without opening 23 pages.

  A link resolves through the redirect titles the cache records for each page:
  the barbarian's `[[Damage Reduction (feat)]]` and `[[greater rage]]` and the
  shifter's `[[infinite humanoid shape]]` are all redirects, and all three named
  no page here until `mix wiki.fetch --aliases-only` collected them. A real page
  name always beats an alias, and an alias two pages claim is dropped. What still
  names no page is **not** invented into an id: it is printed *and* written into
  the class record as `granted_feats_unread`, because a class that quietly stops
  handing out a feat is a wrong calculation, not a cosmetic gap.

  Redirects have a second consequence, and `granted_feat_ranks` is the answer to
  it. A wiki keeps **one page per ability family**, so three distinct ranks —
  `Defensive Awareness` I, II and III at dwarven defender 2, 5 and 10 — resolve
  onto one feat id and `granted_feats` cannot tell them apart. The rank is on the
  page all the same, either trailing the link (`[[deathless vigor]] (+5HP)`) or as
  the redirect title the author linked (`[[greater rage]]`, which is a redirect to
  `Barbarian rage`), and `granted_feat_ranks` carries it through **verbatim**:

      "granted_feat_ranks": { "5": { "defensive_awareness": "II" },
                              "15": { "deathless_vigor": "(+5HP)" } }

  Only levels and feats whose rank the page actually wrote down appear; a class
  with none has no such key. Nothing here is normalised — `II` does not become
  `2` — because these are captions written by hand, not numbers anything adds up.

  `unavailable_feats` is the mirror image of `granted_feats`: the general feats a
  level of this class may **not** be spent on. It is read off TWO independent
  wiki statements, folded onto one list because they are one fact seen from two
  pages, not two facts:

    * the class's own `Unavailable feats` label, off the `ClassPage` reading
      above — 240 pairs, 18 distinct feats;
    * four more pairs a handful of FEATS state about themselves, in the `Notes`
      section of their own page, that no class page repeats —
      `BuildCalculator.Wiki.FeatNotes.forbidden_by_class/1`, resolved the same
      way by `feat_class_bans/2`. Three of the four (`knockdown`,
      `improved_knockdown` on `monk`; `improved_two_weapon_fighting` on
      `ranger`) name a class that also **grants** the very same feat — "since
      monks receive this feat automatically, it cannot be selected when
      gaining a monk level" states the grant and the ban in one sentence, so a
      class here is allowed to both own a feat in `granted_feats` and refuse
      it in `unavailable_feats`, which is otherwise never true of a class
      restricting its own list (AGENT_QUEUE.md §1.10, «Источник 4»). The
      fourth, `blinding_speed` on `harper_scout`, grants nothing at all — the
      ban is the whole fact.

  Resolving either side is the same job through the same redirect lookup, and
  the one difference from every other reading in this file is what happens
  when a name does not resolve — this raises. Every other unresolved reading
  has an empty answer that means "the page said nothing"; here the empty
  answer means "the player may take it", which is a permission the game does
  not give.

  A class's starting armour, shield and weapon proficiencies belong in
  `granted_feats` too — a Fighter owns three armour tiers and a shield the
  moment he takes his first level, same as a Dwarven Defender owns
  `defensive_stance` — but they live off the `Proficiencies` label
  (`ClassPage.proficiency_targets/1`), which `feat_grants/1` never reads, so
  `proficiency_grants/3` resolves them and the caller folds the result onto
  class level 1 before `granted_feats/2` ever groups anything. Two classes name
  a tier without a link at all (`dwarven defender`'s and `blackguard`'s "all
  `[[armor]]`", `blackguard`'s bare "shields"), so the same feats' own pages —
  `promote_feat/2`'s `granted_by` — are read too, scoped to exactly the ids
  *some* class's own label resolves. See `proficiency_grants/3`.

  ## The two Siala layers

  `priv/rules/siala_41/` is split in two, and the split is what makes it safe for
  a parser to write there at all:

      priv/rules/siala_41/            hand-written — classes.json, races.json, overrides.json
      priv/rules/siala_41/generated/  machine-read, overwritten by this task

  This task writes **only** `generated/`. The hand-written files next to it are
  read (the Russian class names come from `classes.json`) and never touched, and
  the merge order is `vanilla → siala generated → siala manual`: the hand layer
  wins, because a human looked at it. See the README in that directory.

  Feats and spells are the part of the Siala wiki that machine-reads at all.
  Two thirds of the pages in `Категория:Фиты` carry the same four bold labels,
  and 128 of the 129 in `Категория:Заклинания` carry the same eleven;
  `BuildCalculator.Wiki.SialaFeatPage` and `BuildCalculator.Wiki.SialaSpellPage`
  read them. Classes, skills and races there are free prose and stay in the hand
  layer.

  Spells need one thing the other categories do not. The shard keeps its balance
  changes **inside the description**, not in the fields: `Fireball` carries the
  vanilla label block unchanged and says «до максимума 20d6» in the middle of a
  sentence where vanilla says 10d6. Lifting that with a regular expression would
  be inventing a game number out of prose, so instead the description is kept
  whole and only the numbers *printed* in it are compared against the numbers
  printed in the vanilla description — a comparison that survives the two texts
  being in different languages. A disagreement sets `differs_from_vanilla` and
  fills `numeric_diff` with both lists; it says "a human must read this page",
  never "here is the new value", and the record is marked `unclear` accordingly.

  ## What it deliberately does not do

  Template values are copied **verbatim, wiki markup included**, and are never
  normalised into structure. `prereq_raw` stays the string `"[[strength]] 13+"`
  rather than becoming `%{str: 13}`, because turning wiki prose into numbers is
  guessing, and the project forbids inventing game numbers (CLAUDE.md §3). Spell
  levels stay strings too — the wiki really does contain values like `"epic"` and
  `"<s>2</s> 3"` where an editor recorded a patch change inline. Structuring these
  is a later, human-reviewed step.

  Every record carries `"status": "parsed"`, meaning "machine-extracted, not yet
  checked by a human". Nothing here is `verified`. The one exception is a class
  whose progression table and bold label disagree about its BAB type or saves:
  that gets `"status": "conflict"` and keeps **both** readings, because resolving
  a contradiction in the source is a human's call, not a parser's.
  """

  use Mix.Task

  alias BuildCalculator.Wiki.Cache
  alias BuildCalculator.Wiki.CategoryMembers
  alias BuildCalculator.Wiki.ClassPage
  alias BuildCalculator.Wiki.EpicRules
  alias BuildCalculator.Wiki.FeatChoice
  alias BuildCalculator.Wiki.FeatNotes
  alias BuildCalculator.Wiki.Json
  alias BuildCalculator.Wiki.RacePage
  alias BuildCalculator.Wiki.Requirements
  alias BuildCalculator.Wiki.SialaFeatPage
  alias BuildCalculator.Wiki.SialaSpellPage
  alias BuildCalculator.Wiki.SkillPage
  alias BuildCalculator.Wiki.Template
  alias BuildCalculator.Wiki.WeaponPage
  alias BuildCalculator.Wiki.Wikitable
  alias BuildCalculator.Wiki.Wikitext

  @wiki "fandom"
  # Paired with `@wiki` and hoisted here (out of the "── Siala" section below,
  # where it used to live) because `collect_weapons/5` needs to read one Siala
  # page — `Система оружия`, задача 3.40 — and a module attribute must already
  # be assigned by the time earlier code in the file reads it, not just by the
  # time its "own" section starts.
  @siala_wiki "siala"
  @output_dir "priv/rules/vanilla"

  # Ворота, действующие на ВЕСЬ домен выбора, а не на один фит. Имя берётся
  # у ядра, а не пишется здесь строкой: разъехавшись, две копии дали бы словарь
  # с воротами, которых никто не читает, — то есть полный список значений,
  # включая те, что источник называет невыбираемыми.
  @domain_gate Atom.to_string(BuildCalculator.Rules.FeatChoices.domain_gate())

  @creature_types_note "The 25 racial types a Favored enemy is chosen from. Built from the members of Category:Races minus the articles filed under it, and checked against the count the `Favored enemy` page states in words. The gate is named after the feat (`favored_enemy`), not `selectable`, because the sentence it comes from is about that feat's list and not about the value: `Favored enemy` says only ooze cannot be *selected as a favored enemy*, and no page says ooze stops being a race. A second feat choosing from this dictionary would therefore arrive ungated on purpose — `feat_choices_test.exs` fails until somebody reads a source and decides, which is the honest outcome and the reason this one is not widened."

  @spell_schools_note "The schools a Spell focus is chosen from. Built from the members of Category:Spell schools minus the articles filed under it; `universal` is in the category and is excluded because its own page says it is not truly a school, which the `Epic spell focus` icon strip corroborates by naming eight variants. The gate is `selectable`, the domain-wide one, because that sentence is about the **value**: universal is not a school for anybody, so every feat that chooses a school is gated by it at once. A gate named after `spell_focus` said the same thing about one feat only, and left `greater_spell_focus`, `epic_spell_focus` and `arcane_defense` holding all nine — covered until now solely by the side effect of `same_choice_as`."

  @energy_types_note "The damage types an Epic energy resistance is chosen from. There is no category and no page per type: the set is a sentence, and it is taken from the two feat pages that give it, which must agree. No gate of either kind: both pages name the same five and neither excludes any, so writing `selectable: true` five times would state a rule nobody wrote."

  @weapons_note "The 47 weapons a Weapon focus is chosen from — every page in Category:Weapons that carries a {{Weapon}} template. The thirteen that do not (Melee weapon, Weapon size, Sword, Axe, …) are overview articles, and the template is the discriminator instead of a hand-kept list of them. The gate is `selectable`, the domain-wide one: seven feat pages carry an icon strip and all seven name the same 41 variants, so the six weapons outside the strip are outside it for every weapon feat at once, and `Weapon focus` says why in prose («There is no version of this feat for the magic staff or lance»). `weapon_of_choice` carries a NAMED gate on top, because its exclusion is about that one feat: its Notes limit it to melee weapons and exclude four by name. GRIP AS A VANILLA RULE IS DELIBERATELY NOT A FIELD: `Two-handed weapon` defines it as «one category larger than its wielder», so it is a function of two sizes and a per-weapon column would be wrong for gnomes and halflings — the weapon's own `size` is what the wiki states, and the rule sits in `_grip` with its quote. `siala_grip`/`siala_grip_raw` (задача 3.40) are a DIFFERENT fact and ARE fields: Siala's `Система оружия` states a grip outright, for a character of the usual size, for 38 of the 47 — a value the shard's own page prints, not a rule this file derives; see `_siala_grip._note` for the difference and for why it is not the same claim as `_grip`. Damage and critical are recorded because they came off the same template for free (Dan 10.08.2026: «урон … для конструктора не важно, мы это не показываем»); a `threat_range` is filled in only where the field states one, and `damage` only where the value is nothing but NdM."

  # Template parameters promoted to named fields, in the order they are written out.
  # Anything not listed here is kept verbatim under "template" so no wiki data is
  # silently dropped when the template gains a parameter. A third element is a
  # reader for the value; without one the parameter is copied verbatim, which is
  # the rule for every field but `type` (see `feat_type/1`).
  @feat_fields [
    {"type", "type", :feat_type},
    {"prereq_raw", "prereq"},
    {"required_for_raw", "reqfor"},
    {"use", "use"},
    {"description", "desc"},
    {"icon", "icon"}
  ]

  # `Category:Feats restricted by class` and its disjoint epic-only twin
  # `Category:Feats restricted by class, epic` (48 pages between them, no page
  # in both — the epic one is not a subcategory mechanism, just a second tag a
  # handful of editors used instead of the first). Both carry the same
  # boilerplate in "Custom content notes" — «A custom class must have this feat
  # in their feat list, or that class will not be able to select it as a
  # general feat» — which is the wiki's way of saying that despite `type=general`
  # (normally "any class"), the game's own class feat lists leave this one out
  # for somebody, and `prereq=` is not where that shows up: `Curse song` carries
  # `prereq=-` and the restriction lives only in a "Notes" sentence.
  #
  # This module does not turn that sentence into a rule — it is prose, feat by
  # feat, and reading it is `vanilla/feat_requirements.json`'s job
  # (`BuildCalculator.Data.Loader.Feats.apply_feat_requirements/4`), done by a human.
  # What belongs here is only that the category was seen at all, so a feat
  # whose `prereqs` reads `null` can be told apart from one that is `null`
  # *and* flagged by the wiki as restricted anyway.
  @restricted_by_class_categories MapSet.new([
                                    "Category:Feats restricted by class",
                                    "Category:Feats restricted by class, epic"
                                  ])

  @spell_fields [
    {"school", "school"},
    {"innate_level", "innatelevel"},
    {"mage_level", "magelevel"},
    {"cleric_level", "clericlevel"},
    {"druid_level", "druidlevel"},
    {"bard_level", "bardlevel"},
    {"paladin_level", "paladinlevel"},
    {"ranger_level", "rangerlevel"},
    {"components", "components"},
    {"range", "range"},
    {"area", "area"},
    {"save", "save"},
    {"spell_resistance", "spellresistance"},
    {"immunity", "immunity"},
    {"duration", "duration"},
    {"description", "desc"},
    {"icon", "icon"}
  ]

  # The header every `generated/` file carries, so that a reader who opens one
  # without having read the README still learns it is machine-written, gets
  # overwritten, and loses to the hand layer next to it.
  @siala_overwrite_note "Файл перезаписывается целиком — правки руками делать НЕЛЬЗЯ, " <>
                          "они потеряются. Ручной слой лежит на уровень выше " <>
                          "(priv/rules/siala_41/*.json) и при склейке выигрывает: " <>
                          "vanilla -> siala generated -> siala manual."

  @siala_status_note "changes[].status: verified — значение прочитано в структуру из слов " <>
                       "самой страницы; unclear — страница про это говорит, но значения не дала; " <>
                       "custom — механика шарда без ванильного аналога, форма записи наша. " <>
                       "value: null значит «числа в источнике нет», а не ноль. " <>
                       "quote обязательна у каждого факта. " <>
                       "ru — заголовок страницы вики (поисковый алиас, не название)."

  @siala_feat_field_note "describes_feat: false — страница лежит в категории «Фиты», " <>
                           "но самого фита не описывает: нет ни одного из четырёх лейблов, " <>
                           "нет списка разблокировок, нет раздела «Возможность взятия фита» " <>
                           "и нет ванильного соответствия. Такая страница про семейство умений " <>
                           "целиком («Фокусировки на школы магии» — это Spell Focus всех восьми " <>
                           "школ сразу): взять с неё нечего, в списке выбора ей не место, " <>
                           "но её siala_note — правила шарда, и запись остаётся. " <>
                           "requirements[].kind: max_character_level — потолок («можно взять " <>
                           "только на 1-ом уровне»), any_of — записанная на странице " <>
                           "дизъюнкция («... или ...»), её ветки лежат в branches. " <>
                           "numbers_differ: наборы чисел из лейбла «Особенности» и из " <>
                           "ванильного desc не совпали; оба набора лежат в numeric_diff. " <>
                           "Величину эффекта шард переписывает часто, а стоит она прозой, " <>
                           "а не полем: у Epic energy resistance ванильные 10 и 100 стоят " <>
                           "как 15 и 150 в середине фразы. Вытаскивать её регуляркой нельзя — " <>
                           "это выдумывание чисел (CLAUDE.md §3), поэтому сравниваются наборы, " <>
                           "и это УКАЗАТЕЛЬ человеку, а не вывод: «Сиала чисел не называет» " <>
                           "и «шард поменял число» отсюда выглядят одинаково. " <>
                           "null значит «сравнивать не с чем» (нет ванильного соответствия, " <>
                           "нет описания у ванильного фита или нет лейбла «Особенности» " <>
                           "на странице Сиалы) — это НЕ «разницы нет». " <>
                           "В changes эти числа сознательно не кладутся: факт не нашёл бы " <>
                           "себе механического дома, уехал бы в siala_unapplied и повесил " <>
                           "на билд второй гэп поверх уже висящего «прибавку фита " <>
                           "в статы не считаем»."

  @siala_feat_notes %{
    note: "Машинный разбор категории «Фиты» вики Сиалы. " <> @siala_overwrite_note,
    field_note: @siala_status_note <> " " <> @siala_feat_field_note
  }

  @siala_spell_notes %{
    note: "Машинный разбор категории «Заклинания» вики Сиалы. " <> @siala_overwrite_note,
    field_note:
      @siala_status_note <>
        " Числа шард держит внутри описания, а не в полях: у Fireball ванильные 10d6 стоят " <>
        "как 20d6 в середине фразы. Вытаскивать их регуляркой нельзя — это выдумывание чисел " <>
        "(CLAUDE.md §3), поэтому описание лежит целиком в description_raw, а numbers — это " <>
        "список чисел, буквально напечатанных в нём (20d6, d10, +5, 15% и голое число). " <>
        "Сравнений два, и они разного рода. " <>
        "numbers_differ: наборы чисел из описания Сиалы и из ванильного description не " <>
        "совпали; оба набора лежат в numeric_diff. " <>
        "fields_differ: разошлись поля, которые обе вики держат структурой; что именно — " <>
        "в field_diff. Сравниваются шесть: school, save, spell_resistance, circles " <>
        "(круги по классам), initial_level и duration. Первые пять — по замкнутому словарю, " <>
        "который печатают обе вики; duration — по числам внутри значения, потому что это " <>
        "проза с обеих сторон («24 hours» против «15 Раундов»), и изменение, записанное " <>
        "словами («Мгновенное» → «Особая»), таким сравнением не ловится. " <>
        "В field_diff попадает только то, что НЕ сошлось: verdict differs — обе стороны " <>
        "прочитаны и не совпали; unreadable — сравнить не удалось, причина в reason. " <>
        "Имени поля в field_diff нет — значит сравнили и расхождения не нашли. " <>
        "Зачёркнутая история патчей (<s>, <del>, <strike>) срезается перед любым сравнением: " <>
        "это прошлое Fandom, а не его сегодняшний ответ. " <>
        "differs_from_vanilla — оба сравнения вместе (null: проверить целиком не удалось). " <>
        "Всё это значит «сюда должен посмотреть человек», а не «вот новое значение»."
  }

  @impl Mix.Task
  def run(_args) do
    index = Cache.read_index!(@wiki)
    pages = Enum.map(index, &{&1, Cache.read_page!(@wiki, &1)})
    Mix.shell().info("[#{@wiki}] scanning #{length(pages)} cached pages…")

    classes = collect_classes(pages)
    skills = collect_skills(pages)
    feats = collect(pages, "feat", @feat_fields, &promote_feat/2)
    spells = collect(pages, "spell", @spell_fields)
    races = collect_races(pages)
    epic = EpicRules.parse(pages)

    # Prerequisites name skills, feats, races and classes, so they can only be
    # read once every one of those has an id — hence a second pass over records
    # that are otherwise complete.
    lookup =
      Requirements.lookup(%{
        classes: classes.records,
        skills: skills.records,
        feats: feats.records,
        races: races.records,
        # "epic shifter" is a class level, and how many levels that is comes off
        # the `Epic class` page rather than out of this file. See `epic_levels/1`.
        epic: epic_levels(epic.json)
      })

    feats = feats |> with_prereqs(lookup) |> with_choices(pages) |> with_forbidden_for(pages)
    grants = grant_lookup(index, feats, lookup)
    proficiencies = proficiency_grants(classes.records, feats.records, grants)
    # Источник 4 (AGENT_QUEUE.md §1.10): the same fact `unavailable_feats`
    # reads off the CLASS side, stated on four FEATS' own pages instead.
    # Resolved here, alongside `grants`/`proficiencies`, because it needs the
    # very same class index and the very same "empty means allowed" raise.
    feat_bans = feat_class_bans(feats.records, lookup)
    classes = with_requirements(classes, lookup, skills, grants, proficiencies, feat_bans)

    # Ahead of the dictionaries on purpose: `weapons.json` records how many
    # weapons each of Siala's five proficiency feats lists, as a live count off
    # this very layer, so the two taxonomies cannot drift apart unnoticed. See
    # `collect_weapons/5`.
    siala = collect_siala_feats(%{feats: feats, classes: classes, skills: skills, races: races})

    memberships = Cache.read_categories!(@wiki)
    creature_types = collect_creature_types(pages, memberships)
    spell_schools = collect_spell_schools(pages, memberships)
    energy_types = collect_energy_types(pages, memberships)
    weapons = collect_weapons(pages, memberships, siala, feats.records, races.records)

    write("classes.json", classes)
    write("skills.json", skills)
    write("feats.json", feats)
    write("spells.json", spells)
    write("races.json", races)
    write_json("epic.json", epic.json)
    write_dictionary("creature_types.json", "types", creature_types, @creature_types_note)
    write_dictionary("spell_schools.json", "schools", spell_schools, @spell_schools_note)
    write_dictionary("energy_types.json", "types", energy_types, @energy_types_note)
    write_dictionary("weapons.json", "weapons", weapons, @weapons_note, weapons.blocks)

    report("classes", classes, length(pages))
    report("skills", skills, length(pages))
    report("feats", feats, length(pages))
    report("spells", spells, length(pages))
    report("races", races, length(pages))
    report_classes(classes)
    report_requirements(classes)
    report_granted_feats(classes)
    report_unavailable_feats(classes)
    report_feat_class_bans(feats.records, pages)
    report_proficiency_grants(proficiencies, grants)
    report_feat_types(feats)
    report_feat_restrictions(feats)
    report_class_feats(feats, classes)
    report_prereqs(feats)
    report_spell_slots(classes)
    report_skills(skills)
    report_skill_classes(skills, classes)
    report_feat_links(feats, MapSet.new(classes.records, & &1.id))
    report_races(races, pages, feats, classes)
    report_epic(epic)
    report_choices(feats)
    report_dictionary("creature types", creature_types)
    report_dictionary("spell schools", spell_schools)
    report_dictionary("energy types", energy_types)
    report_weapons(weapons)

    write_siala("feats.json", "feats", siala, @siala_feat_notes)
    report_siala(siala, feats)

    siala_spells = collect_siala_spells(spells)
    write_siala("spells.json", "spells", siala_spells, @siala_spell_notes)
    report_siala_spells(siala_spells, spells)
  end

  defp collect(pages, template_name, fields, promote \\ &no_promote/2) do
    {records, problems} =
      Enum.reduce(pages, {[], []}, fn {entry, wikitext}, {records, problems} ->
        case Template.find_one(wikitext, template_name) do
          {:ok, template} ->
            {[record(entry, template, fields, promote) | records], problems}

          {:error, :none} ->
            {records, problems}

          {:error, reason} ->
            {records, [{entry.title, reason} | problems]}
        end
      end)

    %{
      records: Enum.sort_by(records, & &1.id),
      problems: Enum.sort(problems)
    }
  end

  defp record(entry, template, fields, promote) do
    extra = promote.(template, entry)
    consumed = Enum.map(fields, &elem(&1, 1)) ++ extra.consumed
    leftovers = template.params |> Map.drop(consumed) |> Enum.sort()

    named = Enum.map(fields, &field(&1, template.params))

    pairs =
      [{"id", id(entry.title)}, {"name", entry.title}] ++
        named ++
        extra.pairs ++
        [
          {"template", {:obj, leftovers}},
          {"source", source(entry)},
          {"status", "parsed"}
        ]

    %{
      id: id(entry.title),
      title: entry.title,
      pairs: pairs,
      json: {:obj, pairs},
      classes: extra.classes,
      params: template.params
    }
  end

  defp field({out, param}, params), do: {out, Map.get(params, param)}
  defp field({out, param, :feat_type}, params), do: {out, feat_type(Map.get(params, param))}

  defp source(entry) do
    {:obj,
     [
       {"wiki", @wiki},
       {"page", entry.title},
       {"revid", entry.revid},
       {"fetched", entry.fetched}
     ]}
  end

  defp no_promote(_template, _entry), do: %{pairs: [], consumed: [], classes: []}

  # `{{feat|bonus1=fighter|bonus2=champion of Torm|class1=monk|epic=yes}}` says
  # which classes may spend a *bonus* feat slot on this feat (`bonusN`) and which
  # classes **hand it out themselves** (`classN`) — the distinction the slot model
  # in CLAUDE.md §6 is built on, and until now it sat unread inside `template`.
  #
  # ⚠ `classN` used to be written out as `available_to`, which read as "who may
  # take it" and is the opposite of what Fandom means by it. `Cleave` carries
  # `class1=monk` **and** `special=Monks receive this feat at first level`; a rule
  # built on the old name would have refused Cleave to everyone but monks. Checked
  # across the whole snapshot rather than on those two pages: of the 212
  # (feat, class) pairs `classN` yields, **143 also appear in the class's own
  # `granted_feats` and not one class-side pair is missing from `classN`** — a
  # containment that a "may take" reading could not produce. The wording agrees
  # too: `Armor proficiency (heavy)` lists exactly its five `classN` under
  # «receive this feat for free», and `Armor proficiency (light)`'s «all classes
  # except …» leaves exactly the 15 that `class1..15` names.
  #
  # The remaining 69 pairs are why the field is renamed and not deleted: 67 are
  # armour/shield/weapon proficiencies, whose class-side statement lives only in
  # the unparsed prose of `proficiencies_raw` («all types of armor and shields»),
  # so `granted_by` is today the only machine-readable form of "this class starts
  # with this proficiency". The duplicate is partial, and deleting a partial
  # duplicate loses the difference silently.
  defp promote_feat(template, entry) do
    bonus_for = class_ids(template, "bonus")
    granted_by = class_ids(template, "class")
    epic = template.params["epic"]

    # Only the literal "yes" is a flag; anything else stays in `template` rather
    # than being coerced into a boolean nobody checked.
    {epic?, epic_consumed} =
      case epic do
        nil -> {false, ["epic"]}
        "yes" -> {true, ["epic"]}
        _other -> {nil, []}
      end

    %{
      pairs: [
        {"epic", epic?},
        {"granted_by", granted_by},
        {"bonus_for", bonus_for},
        {"restricted_by_class_category", restricted_by_class_category?(entry)}
      ],
      consumed: epic_consumed ++ params(template, "bonus") ++ params(template, "class"),
      classes: Enum.uniq(bonus_for ++ granted_by)
    }
  end

  # `true` only for the category tag itself — never derived from `bonusN` or
  # `classN`, which answer different questions ("whose bonus pool", "who grants
  # it for free") and cannot stand in for "who may pick it": `two_weapon_fighting`
  # names three classes under `bonusN` and is still filed here, so the category
  # cannot be that list read backwards, and `report_feat_restrictions/1` prints
  # the count so a page gained or lost by a future re-fetch is seen rather than
  # silently folded into the next parse.
  defp restricted_by_class_category?(entry) do
    not MapSet.disjoint?(MapSet.new(entry.categories), @restricted_by_class_categories)
  end

  # `|type=[[epic spell]]` on the six epic spell feats is the only place this
  # parameter carries markup, and the value under it is a word every other page
  # writes plainly. Nothing else is folded: `classrace`, `defensive`,
  # `item creation` and `instant custom` are the vocabulary Fandom actually uses,
  # and the first three are the one `SialaFeatPage` already maps its Russian
  # labels onto. Bending `instant custom` onto one of the others would be
  # inventing a classification the wiki does not make — the whole list is printed
  # by `report_feat_types/1` instead, so a new value is seen rather than guessed.
  defp feat_type(nil), do: nil
  defp feat_type(raw), do: raw |> Wikitext.strip_links() |> String.trim()

  # `bonus`, `bonus1`, … `bonus15` in the order the page lists them.
  defp params(template, prefix) do
    Enum.filter(Map.keys(template.params), &Regex.match?(~r/^#{prefix}\d*$/, &1))
  end

  defp class_ids(template, prefix) do
    template
    |> params(prefix)
    |> Enum.sort_by(fn key ->
      case String.replace_prefix(key, prefix, "") do
        "" -> 0
        digits -> String.to_integer(digits)
      end
    end)
    |> Enum.map(&id(template.params[&1]))
  end

  # A class page is one that has a level progression table; the four overview
  # pages that share Category:Classes ("Base class", "Prestige class", …) do not.
  # Which pages that test threw out is reported, so a class page whose table stops
  # parsing one day cannot vanish quietly among them.
  defp collect_classes(pages) do
    {records, problems, skipped} =
      pages
      |> Enum.filter(fn {entry, _wikitext} -> class_page?(entry) end)
      |> Enum.reduce({[], [], []}, fn {entry, wikitext}, {records, problems, skipped} ->
        parsed = ClassPage.parse(wikitext)

        if parsed.progression do
          {[class_record(entry, parsed) | records],
           problems ++ Enum.map(parsed.problems, &{entry.title, &1}), skipped}
        else
          {records, problems, [entry.title | skipped]}
        end
      end)

    %{
      records: Enum.sort_by(records, & &1.id),
      problems: Enum.sort(problems),
      skipped: Enum.sort(skipped)
    }
  end

  defp class_page?(entry), do: "Category:Classes" in entry.categories

  # The json is assembled later, in `with_requirements/3`: a class's
  # prerequisites and its class skill list are both cross-file readings, and
  # neither can be settled while its own page is being read.
  defp class_record(entry, parsed) do
    %{
      id: id(entry.title),
      title: entry.title,
      entry: entry,
      parsed: parsed,
      # Read here rather than in `class_json/1` because `Requirements` needs it
      # too: "epic <class>" is eleven class levels for a prestige class and
      # twenty-one for a base one.
      prestige?: "Category:Prestige classes" in entry.categories,
      requirements: nil,
      class_skills: [],
      granted_feats: [],
      granted_feat_ranks: [],
      granted_unmatched: [],
      unavailable_feats: [],
      conflicts: []
    }
  end

  defp class_json(record) do
    entry = record.entry
    parsed = record.parsed
    prestige? = record.prestige?

    pairs =
      [
        {"id", id(entry.title)},
        {"name", entry.title},
        {"prestige", prestige?},
        {"max_level", parsed.max_level},
        {"hit_die", parsed.hit_die},
        {"hit_die_raw", parsed.hit_die_raw},
        {"skill_points", parsed.skill_points},
        {"skill_points_raw", parsed.skill_points_raw},
        {"bab_progression", parsed.bab_progression},
        {"bab_progression_label", parsed.bab_progression_label},
        {"bab_progression_raw", parsed.bab_progression_raw},
        {"saves", saves(parsed.saves)},
        {"saves_label", saves(parsed.saves_label)},
        {"saves_raw", parsed.saves_raw},
        {"alignment_restriction_raw", parsed.alignment_restriction_raw},
        {"requirements", record.requirements},
        {"requirements_raw", parsed.requirements_raw},
        {"proficiencies_raw", parsed.proficiencies_raw},
        {"class_skills", record.class_skills},
        {"class_skills_raw", parsed.class_skills_raw},
        {"class_skills_conflict", Enum.map(record.conflicts, &conflict_json/1)},
        {"unavailable_feats", record.unavailable_feats},
        {"unavailable_feats_raw", parsed.unavailable_feats_raw},
        {"spellcasting_raw", parsed.spellcasting_raw},
        {"primary_ability_raw", parsed.primary_ability_raw},
        {"bonus_feat_levels", parsed.bonus_feat_levels},
        {"epic_bonus_feat_levels", parsed.epic_bonus_feat_levels},
        {"granted_feats", {:obj, record.granted_feats}},
        {"granted_feats_unread", Enum.map(record.granted_unmatched, &unmatched_grant_json/1)},
        {"progression", progression(parsed.progression)},
        {"epic_progression", progression(parsed.epic_progression)},
        {"extra_labels", {:obj, parsed.extra_labels}},
        {"source", source(entry)},
        {"status", if(parsed.conflicts == [], do: "parsed", else: "conflict")},
        {"conflict_note", conflict_note(parsed.conflicts)}
      ]
      |> insert_after("granted_feats", granted_feat_ranks_json(record.granted_feat_ranks))
      |> insert_after(
        "bonus_feat_levels",
        bonus_feat_counts_json("bonus_feat_counts", parsed.bonus_feat_counts)
      )
      |> insert_after(
        "epic_bonus_feat_levels",
        bonus_feat_counts_json("epic_bonus_feat_counts", parsed.epic_bonus_feat_counts)
      )
      |> insert_after("hit_die_raw", hit_die_scale_json(parsed.hit_die_by_class_level))

    Map.put(record, :json, {:obj, pairs})
  end

  # Ключ появляется только там, где страница печатает хит-дайс построчно —
  # сегодня у одного класса из 23 (`red dragon disciple`). Тот же довод, что
  # у `granted_feat_ranks_json/1` ниже: «шкалы нет» и «шкала из одной ступени
  # длиной в весь класс» — одно и то же утверждение, и у 22 классов оно уже
  # сказано полем `hit_die`, которое рядом.
  defp hit_die_scale_json(nil), do: []

  defp hit_die_scale_json(steps) do
    rendered = for {from, die} <- steps, do: {:obj, [{"from", from}, {"die", die}]}

    [{"hit_die_by_class_level", rendered}]
  end

  # Present only where a rank was read. A class whose every grant is a plain link
  # has no key at all rather than an empty object: "this page never labelled a
  # grant" and "this level labelled none" are the same statement, and neither is
  # worth a line in the file.
  defp granted_feat_ranks_json([]), do: []
  defp granted_feat_ranks_json(ranks), do: [{"granted_feat_ranks", {:obj, ranks}}]

  # Тот же довод, что у `granted_feat_ranks_json/1` выше: ключ появляется только
  # там, где таблица назвала число больше единицы. Сегодня это один класс из 23
  # (`ranger`, `{"35": 2}`), у остальных ключа нет вовсе — «страница не назвала
  # числа» и «слот один» это одно утверждение, и второе из них уже сказано тем,
  # что уровень стоит в `bonus_feat_levels`.
  defp bonus_feat_counts_json(_key, counts) when counts in [nil, %{}], do: []

  defp bonus_feat_counts_json(key, counts) do
    pairs = for {level, count} <- Enum.sort(counts), do: {Integer.to_string(level), count}

    [{key, {:obj, pairs}}]
  end

  # ── the second pass: prerequisites and class skills ─────────────────────────

  # `prereqs` sits next to the prose it was read from so the two can be diffed
  # side by side, and `unlocks` is the reverse of every `prereqs.feats` in the
  # file — the "→ N" badge of CLAUDE.md §6 has no other source.
  defp with_prereqs(feats, lookup) do
    read =
      for record <- feats.records do
        Map.put(record, :prereqs, Requirements.feat(record.params["prereq"], lookup))
      end

    unlocks =
      Requirements.unlocks(
        for record <- read, record.params["prereq"], do: {record.id, record.prereqs.requirements}
      )

    records =
      for record <- read do
        unlocked = Map.get(unlocks, record.id, [])

        pairs =
          insert_after(record.pairs, "required_for_raw", [
            {"prereqs", requirements_json(record.params["prereq"], record.prereqs)},
            {"unlocks", unlocked}
          ])

        record |> Map.put(:unlocks, unlocked) |> Map.merge(%{pairs: pairs, json: {:obj, pairs}})
      end

    %{feats | records: records}
  end

  # ── the titles a link may use for a feat page ───────────────────────────────

  # A progression table links whatever title its author typed, and a wiki lets
  # any number of titles reach one page: the barbarian's `[[Damage Reduction
  # (feat)]]`, `[[greater rage]]` and the shifter's `[[infinite humanoid shape]]`
  # are all redirects, and all three named no page here until the cache started
  # recording them.
  #
  # A real page name always wins over an alias, and an alias two feats both claim
  # is dropped rather than assigned to whichever sorted first — either way the
  # grant goes back to being reported as unread, which is the honest answer.
  #
  # `titles` comes back alongside, because resolving is only half the job: an
  # alias resolves `[[greater rage]]` onto the `Barbarian rage` page, and telling
  # that apart from a link that named the page itself needs the page's own title.
  defp grant_lookup(index, feats, lookup) do
    by_title = Map.new(feats.records, &{&1.title, &1.id})

    # `Greater Rage` and `Greater rage` are two redirects and one id, so the
    # claims are folded before they are counted: an alias spelled twice is one
    # alias, not a page two feats disagree about.
    claims =
      for entry <- index,
          feat = Map.get(by_title, entry.title),
          name <- entry.aliases,
          reduce: %{} do
        acc -> Map.update(acc, id(name), [feat], &[feat | &1])
      end
      |> Map.new(fn {name, feats} -> {name, feats |> Enum.uniq() |> Enum.sort()} end)

    aliases =
      for {name, [feat]} <- claims,
          not Map.has_key?(lookup.feats, name),
          into: %{},
          do: {name, feat}

    for {name, [_ | _] = feats} <- claims, length(feats) > 1 do
      Mix.shell().error(
        "[feats] redirect title claimed by more than one page, ignored: " <>
          "#{name} -> #{Enum.join(feats, ", ")}"
      )
    end

    Mix.shell().info("[feats] #{map_size(aliases)} redirect titles resolve to a feat page")

    %{ids: Map.merge(aliases, lookup.feats), titles: Map.new(feats.records, &{&1.id, &1.title})}
  end

  defp with_requirements(classes, lookup, skills, grants, proficiencies, feat_bans) do
    records =
      for record <- classes.records do
        parsed = Requirements.class(record.parsed.requirements_raw, lookup)
        {class_skills, conflicts} = class_skills(record, skills, lookup.skills)

        # Same list `feat_grants/1` would have produced had the wiki put
        # proficiencies in the progression table — folded on before
        # `granted_feats/2` groups, sorts and reports, so one call does both
        # jobs and a target that resolves nowhere is reported exactly once.
        # `record.parsed` itself is left untouched: it is only ever a reading
        # of *this* page, and half of what `proficiencies` carries (the
        # `granted_by` side) is read off somebody else's.
        own_and_proficiencies = %{
          record.parsed.feat_grants
          | granted: record.parsed.feat_grants.granted ++ Map.get(proficiencies, record.id, [])
        }

        {granted, ranks, unmatched} = granted_feats(own_and_proficiencies, grants)

        record
        |> Map.merge(%{
          requirements: requirements_json(record.parsed.requirements_raw, parsed),
          requirements_parsed: parsed,
          class_skills: class_skills,
          granted_feats: granted,
          granted_feat_ranks: ranks,
          granted_unmatched: unmatched,
          # Own label (Источник 1) union'd with what the FEATS themselves say
          # about this class (Источник 4, `feat_class_bans/2`) — one fact, two
          # pages, folded onto the one field `Rules.FeatSlots` reads. See the
          # moduledoc's `unavailable_feats` paragraph.
          unavailable_feats:
            merge_forbidden(unavailable_feats(record, grants), feat_bans, record.id),
          conflicts: conflicts
        })
        |> class_json()
      end

    %{classes | records: records}
  end

  # `%{"class level" => [feat id]}` for the feats the class hands out for free,
  # its rank labels, and the link targets that named no page in `feats.json`.
  #
  # The level is a **class** level, both tables being keyed by one, and it is a
  # string because a JSON object key is. A feat named twice at different levels
  # (champion of Torm's sacred defense at 2 and again at 12, one rank each) is
  # kept at both: the record says "this level hands it out", and owning it twice
  # over is the reader's problem, not this file's.
  defp granted_feats(grants, feats) do
    {resolved, unmatched} =
      Enum.split_with(grants.granted, fn {_level, target, _shown, _tail} ->
        Map.has_key?(feats.ids, id(target))
      end)

    resolved =
      Enum.map(resolved, fn {level, target, shown, tail} ->
        {level, Map.fetch!(feats.ids, id(target)), shown, tail}
      end)

    by_level =
      resolved
      |> Enum.group_by(fn {level, _, _, _} -> level end, fn {_, feat, _, _} -> feat end)
      |> Enum.sort_by(fn {level, _} -> level end)
      |> Enum.map(fn {level, ids} ->
        {Integer.to_string(level), ids |> Enum.uniq() |> Enum.sort()}
      end)

    {by_level, granted_feat_ranks(resolved, feats.titles),
     Enum.map(unmatched, fn {level, target, _shown, _tail} -> {level, target} end)}
  end

  # `%{class_id => [{1, target, target, ""}]}` — a class's starting armour,
  # shield and weapon proficiencies, read as more of the grant `granted_feats/2`
  # already knows how to resolve, group and report, so the caller appends the
  # result onto `feat_grants.granted` and calls that function once rather than
  # building a second copy of what it does.
  #
  # Two independent statements about the same fact, and both are needed:
  #
  #   * the class's own `Proficiencies:` label, link by link
  #     (`ClassPage.proficiency_targets/1`, off `proficiencies_raw`). This alone
  #     is where `fighter` gets all three armour tiers, a shield and two weapon
  #     groups — none of it reached `granted_feats` before this, because none of
  #     it is in the progression table.
  #   * the SAME feats' own `classN` — `granted_by`, already resolved by
  #     `promote_feat/2` — needed because a class's own prose sometimes names a
  #     proficiency without a single link: `dwarven defender` and `blackguard`
  #     both write "all `[[armor]]`", which links the general article and not
  #     any one tier, and `blackguard` writes "shields" as a bare word that was
  #     never a link. The feat's own page still lists both classes plainly under
  #     `classN`.
  #
  # Reading only the label would leave those two classes owning no armour tier
  # and no shield at all. Reading only `granted_by` unscoped would invent
  # nothing by itself, but it would pull in anything *any* feat's page happens
  # to name a class under `classN` for — `favored enemy` lists `ranger` and
  # `harper scout` there too, and it is a slotted choice the player makes
  # (`bonus_for`, `Rules.FeatSlots`), not something the class simply hands over.
  # What keeps it out is `known`: the second reading is scoped to exactly the
  # feat ids the FIRST reading resolves for *some* class, never to the whole of
  # `granted_by`.
  #
  # A class named nowhere on either side still gets a map entry, empty list — a
  # caller asking `Map.get(result, id, [])` cannot tell the difference, but the
  # report below can, and does.
  #
  # ⚠ Resolved by feat id, not by the raw string, and that is not a cosmetic
  # choice: the same feat is spelled three different ways across these pages
  # (`armor proficiency (light)` on `fighter`, `Armor Proficiency (Light)` on
  # `bard`, and the feat's own title `Armor proficiency (light)` from
  # `granted_by`). Deduplicating the strings would still leave two or three
  # grants of one feat sitting side by side; `granted_feats/2` groups by id
  # after resolving, so nothing downstream would break, but every caller that
  # counts pairs before that point — this function's own report included —
  # would count the same fact two or three times over.
  defp proficiency_grants(class_records, feat_records, grants) do
    own = Map.new(class_records, &{&1.id, &1.parsed.proficiency_targets})
    resolve = &Map.get(grants.ids, id(&1))

    known =
      for {_id, targets} <- own,
          target <- targets,
          id = resolve.(target),
          id,
          into: MapSet.new() do
        id
      end

    by_class =
      for feat <- feat_records,
          MapSet.member?(known, feat.id),
          class_id <- record_value(feat, "granted_by"),
          reduce: %{} do
        acc -> Map.update(acc, class_id, MapSet.new([feat.id]), &MapSet.put(&1, feat.id))
      end

    for {class_id, targets} <- own, into: %{} do
      resolved =
        for target <- targets, id = resolve.(target), id, into: MapSet.new(), do: id

      unresolved = for target <- targets, is_nil(resolve.(target)), do: target
      ids = MapSet.union(resolved, Map.get(by_class, class_id, MapSet.new()))

      grants_by_id =
        for id <- Enum.sort(ids) do
          title = Map.fetch!(grants.titles, id)
          {1, title, title, ""}
        end

      {class_id, grants_by_id ++ for(target <- unresolved, do: {1, target, target, ""})}
    end
  end

  # The feats a class takes **off the general feat list** for the level being
  # taken («These general feats cannot be selected when taking a level of bard»),
  # as feat ids. The prose the list is written in stays in
  # `unavailable_feats_raw`, so the reading can be diffed against the page.
  #
  # ⚠ Raises rather than reporting. Everything else read off a class page has a
  # sane empty answer — a missing grant is a feat the class does not hand out,
  # and `granted_feats_unread` carries the target so it can be seen. Here the
  # empty answer is a **permission**: a name that stops resolving silently
  # re-allows a feat the game forbids, which is the false legality this whole
  # reading exists to remove, and nothing downstream could tell it apart from a
  # class the page never restricted. All 240 pairs across all 23 pages resolve
  # today (18 distinct feats), so a failure here means the wiki gained a name and
  # a human has to look at it.
  defp unavailable_feats(record, feats) do
    targets = record.parsed.unavailable_feat_targets

    ids =
      for target <- targets do
        case Map.fetch(feats.ids, id(target)) do
          {:ok, feat} ->
            feat

          :error ->
            raise """
            #{record.id}: `Unavailable feats` names `#{target}`, which is no page in \
            feats.json and no redirect to one.

            The list says which general feats a level of this class may not pick. An \
            unresolved name would quietly *allow* one, so this is not reported and \
            skipped — read the page, and if the name is a feat, teach the cache its \
            redirect (`mix wiki.fetch --aliases-only`).
            """
        end
      end

    ids |> Enum.uniq() |> Enum.sort()
  end

  # Folds Источник 4's `feat_class_bans/2` onto Источник 1's own list —
  # `Enum.uniq` rather than an assumed disjoint union, because three of the
  # four Источник 4 pairs (`knockdown`, `improved_knockdown` on `monk`;
  # `improved_two_weapon_fighting` on `ranger`) name a class the class's own
  # `Unavailable feats` label never mentions, but nothing GUARANTEES the two
  # readings never overlap on some future re-fetch, and a duplicate in the
  # written list would be a cosmetic bug worth silently absorbing here rather
  # than reporting as a second "conflict".
  defp merge_forbidden(class_side, feat_bans, class_id) do
    (class_side ++ (feat_bans |> Map.get(class_id, MapSet.new()) |> MapSet.to_list()))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # `%{"class level" => %{feat id => rank}}`, and only where the page wrote a
  # rank down. It exists because a wiki keeps **one page per ability family**, so
  # `granted_feats` alone says the dwarven defender is handed `defensive_awareness`
  # at 2, 5 and 10 without a word about which of the three ranks each is.
  #
  # The rank is copied **exactly as printed** — `II`, `(+5HP)`, `(4x/day)`, `+1`.
  # Normalising `II` into `2` or `(+5HP)` into `+5 HP` would be rewriting a label
  # written by a human into a number nobody computed with, and none of these is
  # ever added up: it is a caption, not a term.
  #
  # A page tells its ranks apart in two ways, and both are read:
  #
  #   * a **tail** after the link — the usual case, 24 of the 26;
  #   * the **display text of the link itself**, where an author linked the rank's
  #     own redirect title: `[[greater rage]]` (→ `Barbarian rage`),
  #     `[[infinite humanoid shape]]` (→ `Infinite greater wildshape`),
  #     `[[elemental shape | improved elemental shape]]`. Here the display text
  #     *is* the rank, so it is kept along with whatever trails it, and the reader
  #     gets `greater rage (4x/day)` rather than a `(4x/day)` that would read
  #     exactly like the rage the barbarian has had since level 1.
  #
  # The twenty other places where display and title differ carry no rank at all —
  # they are the wiki hiding a disambiguating suffix (`[[fear (feat)|fear]]`,
  # `[[animate dead (feat)|animate dead]]`) — so the comparison drops one trailing
  # parenthesised qualifier from both sides first. Without that the file would
  # fill up with `fear fear`.
  defp granted_feat_ranks(resolved, titles) do
    resolved
    |> Enum.map(fn {level, feat, shown, tail} ->
      {level, feat, rank_label(shown, Map.get(titles, feat), tail)}
    end)
    |> Enum.reject(fn {_level, _feat, rank} -> rank == "" end)
    |> Enum.group_by(fn {level, _, _} -> level end, fn {_, feat, rank} -> {feat, rank} end)
    |> Enum.sort_by(fn {level, _} -> level end)
    |> Enum.map(fn {level, pairs} ->
      {Integer.to_string(level), {:obj, pairs |> Enum.uniq_by(&elem(&1, 0)) |> Enum.sort()}}
    end)
  end

  defp rank_label(shown, title, tail) do
    if title && undisambiguated(shown) == undisambiguated(title) do
      tail
    else
      String.trim(shown <> " " <> tail)
    end
  end

  defp undisambiguated(name) do
    name |> String.replace(~r/\s*\([^()]*\)\s*$/u, "") |> String.trim() |> String.downcase()
  end

  # The two numbers behind "epic <class>", straight out of the epic rules block
  # this task has just read. A missing one leaves the phrase unparsed rather than
  # standing in for it (CLAUDE.md §3).
  defp epic_levels({:obj, pairs}) do
    thresholds =
      case List.keyfind(pairs, "epic_thresholds", 0) do
        {_key, {:obj, values}} -> Map.new(values)
        _absent -> %{}
      end

    %{
      character_level: thresholds["epic_character_from_character_level"],
      base_class_level: thresholds["epic_base_class_from_class_level"],
      prestige_class_level: thresholds["epic_prestige_class_from_class_level"]
    }
  end

  # `null` means "nothing was read", and a page that states no criteria at all
  # reads the same way — `Rules.LevelUp` keeps refusing to call such a class
  # legal. An empty object would say "this class asks for nothing", which is a
  # claim no page here makes.
  defp requirements_json(nil, _parsed), do: nil
  defp requirements_json(_raw, %{requirements: []}), do: nil
  defp requirements_json(_raw, %{requirements: pairs}), do: {:obj, pairs}

  defp insert_after(pairs, key, extra) do
    Enum.flat_map(pairs, fn
      {^key, value} -> [{key, value} | extra]
      pair -> [pair]
    end)
  end

  # Class-skill membership is written down twice on Fandom — as a list of skills
  # on the class page and as a list of classes on every skill page — and the two
  # disagree seven times, all on the two youngest prestige classes.
  #
  # **The class page wins, and a skill page's blanket "Classes: all" wins too.**
  # That is the union, and it is a decision rather than a default:
  #
  #   * six of the seven are a skill the *class* page lists and the skill page's
  #     class list omits, and five of those six are one class (purple dragon
  #     knight) missing from five different lists at once. A class page is one
  #     hand-kept list about one class; a skill page's class list is a
  #     denormalised cross-index over 23 classes that has to be edited every time
  #     a class is added. A one-directional omission repeated across five pages
  #     is that index rotting, not five mistakes on the one page that agrees with
  #     itself — and three of the eight skills the purple dragon knight page
  #     lists *do* name it back, i.e. the cross-index was updated part of the way;
  #   * the seventh runs the other way (`heal` is listed by no class page and
  #     claimed by every class) and is not a stale list at all: `Heal (skill)`
  #     states `Classes: all`, a blanket claim that cannot go out of date as
  #     classes are added.
  #
  # Both readings stay in the file under `class_skills_conflict`, so the decision
  # can be reversed without re-reading the wiki.
  defp class_skills(record, skills, index) do
    from_class =
      (record.parsed.class_skills_raw || "")
      |> Wikitext.link_targets()
      |> Enum.map(&Map.get(index, id(&1), id(&1)))
      |> MapSet.new()

    from_skills =
      for skill <- skills.records,
          skill.parsed.classes_all? or record.id in Enum.map(skill.parsed.classes, &id/1),
          into: MapSet.new(),
          do: skill.id

    conflicts =
      Enum.sort(
        Enum.map(MapSet.difference(from_class, from_skills), &{&1, "class_page"}) ++
          Enum.map(MapSet.difference(from_skills, from_class), &{&1, "skill_page"})
      )

    {from_class |> MapSet.union(from_skills) |> Enum.sort(), conflicts}
  end

  # A feat the progression table hands out whose page this snapshot has not got.
  # It belongs in the file and not only in the run log: a class that silently
  # stops granting a feat is a wrong calculation, and `granted_feats` alone
  # cannot tell "grants nothing here" from "the grant went missing".
  defp unmatched_grant_json({level, target}) do
    {:obj, [{"level", level}, {"page", target}]}
  end

  defp conflict_json({skill, stated_by}) do
    {:obj, [{"skill", skill}, {"stated_by", stated_by}, {"resolution", "class_skill"}]}
  end

  defp saves(nil), do: nil

  defp saves(saves),
    do: {:obj, [{"fort", saves.fort}, {"ref", saves.ref}, {"will", saves.will}]}

  defp progression(nil), do: nil

  defp progression(rows) do
    Enum.map(rows, fn row ->
      {:obj,
       [
         {"level", row.level},
         {"bab", row.bab},
         {"fort", row.fort},
         {"ref", row.ref},
         {"will", row.will},
         {"feats_raw", row.feats_raw},
         {"bonus_feat_rank_raw", row.bonus_feat_rank_raw},
         {"hp", row.hp},
         {"hp_raw", row.hp_raw},
         {"spells_per_day", circles(row.spells_per_day)},
         {"spells_known", circles(row.spells_known)},
         {"extra", {:obj, row.extra}}
       ]}
    end)
  end

  # `null` = the class has no such table columns; `{}` = it has them and this
  # level grants nothing yet (paladin 1–3). A circle the table dashes out has no
  # key at all, which is what keeps "no slot" distinct from "a slot of zero".
  defp circles(nil), do: nil
  defp circles(pairs), do: {:obj, pairs}

  defp conflict_note([]), do: nil
  defp conflict_note(conflicts), do: Enum.join(conflicts, "; ")

  # Thirteen of the 41 members of `Category:Skills` are rules pages (`skill
  # point`, `class skill`, `difficulty class`) or combat modes (`stealth`,
  # `detect`) rather than skills. A skill is a page carrying an `Ability` label;
  # the rest are reported by title so that a real skill page whose labels stop
  # parsing one day cannot vanish quietly among them.
  defp collect_skills(pages) do
    penalised = armor_check_skills(pages)

    {records, skipped} =
      pages
      |> Enum.filter(fn {entry, _wikitext} -> "Category:Skills" in entry.categories end)
      |> Enum.reduce({[], []}, fn {entry, wikitext}, {records, skipped} ->
        parsed = SkillPage.parse(wikitext)

        if parsed.key_ability_raw do
          {[skill_record(entry, parsed, penalised) | records], skipped}
        else
          {records, [entry.title | skipped]}
        end
      end)

    %{
      records: Enum.sort_by(records, & &1.id),
      problems:
        records
        |> Enum.flat_map(fn record -> Enum.map(record.parsed.problems, &{record.title, &1}) end)
        |> Enum.sort(),
      skipped: Enum.sort(skipped),
      penalised: penalised
    }
  end

  # The one page that says which skills armor hinders. `nil` (not `[]`) when the
  # sentence stops matching, so "we no longer know" cannot read as "no skill is
  # affected".
  defp armor_check_skills(pages) do
    with {_entry, wikitext} <-
           Enum.find(pages, fn {entry, _} -> entry.title == "Armor check penalty" end),
         [_ | _] = titles <- SkillPage.armor_check_skills(wikitext) do
      MapSet.new(titles, &id/1)
    else
      _none -> nil
    end
  end

  defp skill_record(entry, parsed, penalised) do
    id = id(entry.title)
    trained_category? = "Category:Skills that require training" in entry.categories
    conflicts = trained_conflicts(parsed.trained_only, trained_category?)

    json =
      {:obj,
       [
         {"id", id},
         {"name", entry.title},
         {"key_ability", parsed.key_ability},
         {"key_ability_raw", parsed.key_ability_raw},
         {"armor_check_penalty", penalised && MapSet.member?(penalised, id)},
         {"trained_only", parsed.trained_only},
         {"trained_only_raw", parsed.trained_only_raw},
         {"trained_only_category", trained_category?},
         {"exclusive", "Category:Exclusive skills" in entry.categories},
         {"cross_class_raw", parsed.cross_class_raw},
         {"classes_all", parsed.classes_all?},
         {"classes_raw", parsed.classes_raw},
         {"check_raw", parsed.check_raw},
         {"use_raw", parsed.use_raw},
         {"special_raw", parsed.special_raw},
         {"description", parsed.description},
         {"extra_labels", {:obj, parsed.extra_labels}},
         {"source", source(entry)},
         {"status", if(conflicts == [], do: "parsed", else: "conflict")},
         {"conflict_note", conflict_note(conflicts)}
       ]}

    %{
      id: id,
      title: entry.title,
      json: json,
      parsed: parsed,
      exclusive?: "Category:Exclusive skills" in entry.categories,
      conflicts: conflicts
    }
  end

  # A skill page states "requires training" twice — as a label and as a category
  # membership — and on `perform` the two disagree. Both readings are kept and
  # the record is marked `conflict`; choosing between them is a human's call.
  defp trained_conflicts(nil, _category?), do: []
  defp trained_conflicts(same, same), do: []

  defp trained_conflicts(label, category?) do
    [
      "requires training: label says #{label}, " <>
        "Category:Skills that require training says #{category?}"
    ]
  end

  # `Category:Races` is mostly creature types (dragon, undead, vermin …) and
  # `Category:Custom content races` is community content the shard does not use;
  # only `Category:Playable races` is a choice a player makes, and it has exactly
  # seven members.
  defp collect_races(pages) do
    medium = medium_size_citation!(pages)

    records =
      pages
      |> Enum.filter(fn {entry, _wikitext} -> "Category:Playable races" in entry.categories end)
      |> Enum.map(fn {entry, wikitext} ->
        race_record(entry, RacePage.parse(wikitext), medium)
      end)

    verify_small_stature_races!(pages, records)

    %{
      records: Enum.sort_by(records, & &1.id),
      problems:
        records
        |> Enum.flat_map(fn record -> Enum.map(record.parsed.problems, &{record.title, &1}) end)
        |> Enum.sort()
    }
  end

  defp race_record(entry, parsed, medium) do
    feats = parsed.abilities |> Enum.map(& &1.link) |> Enum.reject(&is_nil/1) |> Enum.map(&id/1)
    size = size_fields(entry, parsed, medium)

    json =
      {:obj,
       [
         {"id", id(entry.title)},
         {"name", entry.title},
         {"ability_modifiers", ability_modifiers(parsed.ability_modifiers)},
         {"ability_modifiers_raw", parsed.ability_modifiers_raw},
         {"favored_class", parsed.favored_class_name && id(parsed.favored_class_name)},
         {"favored_class_any", parsed.favored_class_any?},
         {"favored_class_raw", parsed.favored_class_raw},
         {"favored_enemy", nil},
         {"bonus_feats", feats},
         {"extra_feats", extra_feats(parsed.extra_feats)},
         {"bonus_skill_points", bonus_skill_points(parsed.bonus_skill_points)},
         {"skill_bonuses", skill_bonuses(parsed.skill_bonuses)},
         {"skill_bonuses_prose", parsed.skill_bonuses_prose},
         {"special_abilities_raw", Enum.map(parsed.abilities, & &1.raw)}
       ] ++
         size.pairs ++
         [
           {"source", source(entry)},
           {"status", "parsed"}
         ]}

    %{
      id: id(entry.title),
      title: entry.title,
      json: json,
      parsed: parsed,
      feats: feats,
      size: size.value
    }
  end

  # AGENT_QUEUE.md §3.44. `parsed.size` is only ever "small" or `nil` (see
  # `RacePage`'s moduledoc) — `nil` means gnome/halfling's own two-race fact
  # ("<Race>s are small creatures", plus the tower-shield and large-weapon
  # bans) is not on THIS page, not that the race has no size. The other five
  # playable races are Medium by elimination over a closed set of seven: no
  # page calls any of them "medium" by name except `Weapon size`'s own worked
  # example (which names a human outright, and a halfling — corroborating the
  # gnome/halfling reading from a second, independent page), and `Small
  # stature`'s own `{{feat|prereq=…}}` names exactly gnome and halfling as the
  # only two races the ability applies to — cross-checked at build time by
  # `verify_small_stature_races!/2` against each race page's own bullet, so
  # the two readings can never quietly disagree.
  @medium_size_note "Ни Dwarf, ни Elf, ни Half-elf, ни Half-orc не называют себя \"medium\" " <>
                      "на СВОЕЙ странице; из пяти это делает только Human, в цитате слева. " <>
                      "\"medium\" для всех пяти — вывод по остатку: Category:Playable races " <>
                      "содержит ровно 7 записей, и prereq фита `Small stature` называет " <>
                      "ровно `gnome, halfling` (сверено при сборке, " <>
                      "verify_small_stature_races!/2 в mix wiki.parse) — третьего размера " <>
                      "у играбельного персонажа ни одна из двух вики не называет. " <>
                      "AGENT_QUEUE.md §3.44."

  defp size_fields(entry, %{size: "small"} = parsed, _medium) do
    %{
      value: "small",
      pairs: [
        {"size", "small"},
        {"size_status", "verified"},
        {"size_raw", parsed.small_stature_raw},
        {"size_note", nil},
        {"size_source", source(entry)},
        {"cannot_use_tower_shields", parsed.cannot_use_tower_shields},
        {"cannot_use_large_weapons", parsed.cannot_use_large_weapons}
      ]
    }
  end

  defp size_fields(_entry, %{size: nil}, medium) do
    %{
      value: "medium",
      pairs: [
        {"size", "medium"},
        {"size_status", "derived"},
        {"size_raw", medium.raw},
        {"size_note", @medium_size_note},
        {"size_source", source(medium.entry)},
        {"cannot_use_tower_shields", false},
        {"cannot_use_large_weapons", false}
      ]
    }
  end

  # The one sentence on `Weapon size` that names a playable race "medium-sized"
  # (a human) or "small-sized" (a halfling) outright, rather than leaving size
  # to be worked out from the two-handed-weapon rule. Picked over the more
  # tempting `(For playable races, this only excludes large weapons from
  # gnomes and halflings.)` aside precisely because that one sits inside a
  # parenthesis closed by ").", which this file's own `sentence_with/2` cannot
  # tell apart from a mid-sentence break — quoting it verbatim would run on
  # into the next, unrelated sentence about light weapons.
  @medium_size_anchor "may wield a medium-sized [[longsword]] in one hand or a large-sized " <>
                        "[[greatsword]] two-handed. However, a small-sized [[halfling]] may " <>
                        "not wield a greatsword and may only wield a longsword two-handed"

  defp medium_size_citation!(pages) do
    {entry, text} = page!(pages, "Weapon size")
    %{raw: sentence!(text, @medium_size_anchor), entry: entry}
  end

  # Independent of `size_fields/3` above: that one reads each race's OWN page,
  # this one reads `Small stature`'s `{{feat|prereq=…}}` fresh off ITS page.
  # Two different pages, two different readings, one fact — CLAUDE.md §3 wants
  # them cross-checked rather than one trusted alone, the same discipline
  # `_grip`'s `verify_grip_race_sizes!/1` (below, задача 3.44) applies again
  # from `weapons.json`'s side.
  defp verify_small_stature_races!(pages, records) do
    from_race_pages =
      records |> Enum.filter(&(&1.size == "small")) |> Enum.map(& &1.id) |> Enum.sort()

    from_prereq = small_stature_prereq_races!(pages)

    unless from_race_pages == from_prereq do
      raise """
      races: two independent readings of which playable races are Small disagree — each \
      race's own "Small stature" bullet says #{inspect(from_race_pages)}, but `Small \
      stature`'s own {{feat|prereq=…}} says #{inspect(from_prereq)}. CLAUDE.md §3: a \
      contradiction between two pages is a finding to record, not a tie for this task to \
      break by hand.
      """
    end
  end

  defp small_stature_prereq_races!(pages) do
    {entry, text} = page!(pages, "Small stature")

    case Template.find_one(text, "feat") do
      {:ok, %{params: %{"prereq" => prereq}}} ->
        prereq |> Wikitext.link_targets() |> Enum.map(&id/1) |> Enum.sort()

      _ ->
        raise "races: `#{entry.title}` no longer carries a {{feat|prereq=…}} to check race " <>
                "sizes against"
    end
  end

  # An empty object means "this race adjusts nothing" (human, half-elf, whose
  # pages carry no adjustments line at all); `null` would mean "not read".
  defp ability_modifiers(nil), do: nil
  defp ability_modifiers(modifiers), do: {:obj, modifiers}

  defp skill_bonuses(bonuses),
    do: {:obj, Enum.map(bonuses, fn {skill, bonus} -> {id(skill), bonus} end)}

  defp extra_feats(nil), do: nil

  defp extra_feats(extra),
    do: {:obj, [{"level", extra.level}, {"count", extra.count}]}

  defp bonus_skill_points(nil), do: nil

  defp bonus_skill_points(points),
    do:
      {:obj, [{"level", points.level}, {"extra", points.extra}, {"per_level", points.per_level}]}

  # Race pages hold no numbers of their own beyond the ability adjustments: what
  # a race actually grants is a set of *feats*, named by the link each ability
  # bullet opens with. So the check that matters is that those links resolve, in
  # both directions — an unresolvable one means the bullet was misread, and a
  # member of Category:Racial feats that no race grants means a race page stopped
  # listing an ability it used to list.
  defp report_races(%{records: records}, pages, feats, classes) do
    feat_ids = MapSet.new(feats.records, & &1.id)
    class_ids = MapSet.new(classes.records, & &1.id)
    skill_ids = MapSet.new(category_ids(pages, "Category:Skills"))
    racial_feat_ids = MapSet.new(category_ids(pages, "Category:Racial feats"))
    granted = records |> Enum.flat_map(& &1.feats) |> MapSet.new()

    for id <- sorted_difference(granted, feat_ids) do
      Mix.shell().error("[races] racial ability is not a feat in feats.json: #{id}")
    end

    for id <- sorted_difference(racial_feat_ids, granted) do
      Mix.shell().error("[races] Category:Racial feats member no race grants: #{id}")
    end

    records
    |> Enum.filter(& &1.parsed.favored_class_name)
    |> Enum.reject(&MapSet.member?(class_ids, id(&1.parsed.favored_class_name)))
    |> Enum.each(fn record ->
      Mix.shell().error(
        "[races] favored class not in classes.json: #{record.title} -> " <>
          record.parsed.favored_class_name
      )
    end)

    for record <- records,
        {skill, _bonus} <- record.parsed.skill_bonuses,
        not MapSet.member?(skill_ids, id(skill)) do
      Mix.shell().error("[races] skill bonus names an unknown skill: #{record.title} -> #{skill}")
    end

    prose = Enum.filter(records, &(&1.parsed.skill_bonuses_prose != []))

    Mix.shell().info(
      "[races] #{MapSet.size(granted)} distinct racial feats granted, " <>
        "#{MapSet.size(racial_feat_ids)} in Category:Racial feats"
    )

    Mix.shell().info(
      "[races] skill bonus left as prose (conditional or multi-skill) on: " <>
        Enum.map_join(prose, ", ", & &1.title)
    )

    small = records |> Enum.filter(&(&1.size == "small")) |> Enum.map(& &1.id) |> Enum.sort()
    medium = records |> Enum.filter(&(&1.size == "medium")) |> Enum.map(& &1.id) |> Enum.sort()

    Mix.shell().info(
      "[races] size (AGENT_QUEUE.md §3.44): #{length(small)} small, verified from their own " <>
        "page (#{Enum.join(small, ", ")}); #{length(medium)} medium, derived by elimination " <>
        "(#{Enum.join(medium, ", ")})"
    )
  end

  defp sorted_difference(left, right),
    do: left |> MapSet.difference(right) |> MapSet.to_list() |> Enum.sort()

  defp category_ids(pages, category) do
    for {entry, _wikitext} <- pages, category in entry.categories, do: id(entry.title)
  end

  # snake_case of the English page title. Disambiguating suffixes stay part of the
  # id ("Shield (spell)" -> "shield_spell") so that two different pages can never
  # collapse onto one identifier.
  defp id(title) do
    title
    |> String.replace(~r/['’]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "_")
    |> String.trim("_")
  end

  # ── repeatability and what a repeat chooses ─────────────────────────────────

  # The decisions themselves live in `BuildCalculator.Wiki.FeatChoice`, which
  # documents why they are curated rather than matched. This is only the wiring:
  # every quote is lifted from the cache, and both guards below raise rather than
  # print, because a feat that is silently not repeatable is a feat the core
  # refuses to let a ranger take twice.
  defp with_choices(feats, pages) do
    by_title = Map.new(pages, fn {entry, text} -> {entry.title, {entry, text}} end)

    context =
      Map.new(feats.records, fn record ->
        {entry, text} = Map.fetch!(by_title, record.title)

        {record.id,
         %{
           entry: entry,
           texts: %{use: record.params["use"], description: record.params["desc"], page: text}
         }}
      end)

    texts = Map.new(context, fn {id, %{texts: texts}} -> {id, texts} end)

    FeatChoice.check!(texts)

    case FeatChoice.unclassified(texts) do
      [] ->
        :ok

      ids ->
        raise """
        these feats discuss being taken more than once and no table in \
        BuildCalculator.Wiki.FeatChoice accounts for them:

          #{Enum.join(ids, "\n  ")}

        Read each page and add it to `@repeatable`, `@repeatable_raw` or \
        `@not_repeatable` — the last one exists precisely so that "the page says \
        it cannot be repeated" is recorded rather than left looking unexamined.
        """
    end

    records =
      for record <- feats.records do
        %{entry: entry, texts: texts} = Map.fetch!(context, record.id)

        pairs =
          record.pairs
          |> put_repeatable(record.id, texts, entry)
          |> put_same_choice(record)

        %{record | pairs: pairs, json: {:obj, pairs}}
      end

    %{feats | records: records}
  end

  # Источник 4 (AGENT_QUEUE.md §1.10): a feat's own ban on itself, read off the
  # full wikitext of ITS page — threaded through the same way `with_choices/2`
  # threads `repeatable`, because `promote_feat/2` only ever sees the
  # `{{feat}}` template, never the prose that follows it.
  #
  # `forbidden_for_raw` sits next to `restricted_by_class_category`: both are
  # "who this feat's own page says something about", and both are evidence
  # for a human to read, not something `Rules.FeatSlots` reads directly — the
  # resolved fact lives on the CLASS side, in `unavailable_feats`
  # (`feat_class_bans/2`, `with_requirements/6`), the same as `granted_by`
  # documents a grant that `class_json/1`'s `granted_feats` is the resolved
  # copy of.
  defp with_forbidden_for(feats, pages) do
    by_title = Map.new(pages, fn {entry, text} -> {entry.title, text} end)

    records =
      for record <- feats.records do
        forbidden = FeatNotes.forbidden_by_class(Map.fetch!(by_title, record.title))

        pairs =
          insert_after(
            record.pairs,
            "restricted_by_class_category",
            forbidden_for_json(forbidden)
          )

        record
        |> Map.put(:forbidden_for, forbidden)
        |> Map.merge(%{pairs: pairs, json: {:obj, pairs}})
      end

    %{feats | records: records}
  end

  defp forbidden_for_json(forbidden),
    do: [{"forbidden_for_raw", Enum.map(forbidden, &ban_json/1)}]

  defp ban_json({class, quote}), do: {:obj, [{"class", class}, {"quote", quote}]}

  # The other half of Источник 4: resolving `forbidden_for` (read above) needs
  # the class index one feat page cannot have, exactly the reason
  # `unavailable_feats/2` resolves its own class-page targets here and not
  # inside `ClassPage`. Raises the same way, and for the same reason: an
  # unresolved name here would quietly *allow* the feat, which the source does
  # not say.
  defp feat_class_bans(records, lookup) do
    for record <- records,
        {name, quote} <- record.forbidden_for,
        reduce: %{} do
      acc ->
        case Map.fetch(lookup.classes, id(name)) do
          {:ok, class} ->
            Map.update(acc, class, MapSet.new([record.id]), &MapSet.put(&1, record.id))

          :error ->
            raise """
            #{record.id}: its own `Notes` section forbids taking it on a level of \
            `#{name}`, which resolves to no class id — quoted as:

              #{quote}

            An unresolved name would quietly *allow* the feat there, which the \
            game does not: read the page, and if `#{name}` names a class, check \
            its spelling or teach the cache the redirect \
            (`mix wiki.fetch --aliases-only`).
            """
        end
    end
  end

  # The broader net `FeatNotes.mentions_cannot_be_selected?/1` casts, printed so
  # a wording change a future re-fetch introduces is seen here rather than
  # silently missed — the same purpose `report_feat_restrictions/1` serves for
  # `Category:Feats restricted by class`.
  defp report_feat_class_bans(records, pages) do
    by_title = Map.new(pages, fn {entry, text} -> {entry.title, text} end)
    pairs = for record <- records, ban <- record.forbidden_for, do: {record.id, ban}
    classes = pairs |> Enum.map(fn {_feat, {class, _quote}} -> class end) |> Enum.uniq()

    Mix.shell().info(
      "[feats] #{length(pairs)} class ban(s) read off a feat's own `Notes` section, " <>
        "naming #{length(classes)} class(es): #{Enum.join(Enum.sort(classes), ", ")}"
    )

    for {feat_id, {class, quote}} <- Enum.sort(pairs) do
      Mix.shell().info("[feats]   #{feat_id} forbidden for #{class} — #{quote}")
    end

    unmatched =
      for record <- records,
          record.forbidden_for == [],
          wikitext = Map.fetch!(by_title, record.title),
          FeatNotes.mentions_cannot_be_selected?(wikitext),
          do: record.id

    for id <- Enum.sort(unmatched) do
      Mix.shell().info(
        "[feats]   #{id}: `Notes` says \"cannot be selected\" but names no class ban — " <>
          "checked by hand, see FeatNotes moduledoc"
      )
    end
  end

  defp report_choices(%{records: records}) do
    decided = Enum.filter(records, &has_key?(&1, "repeatable"))
    raw = Enum.filter(records, &has_key?(&1, "repeatable_raw"))
    same = Enum.filter(records, &prereq_value(&1.pairs, "same_choice_as"))

    Mix.shell().info(
      "[choices] #{length(decided)} feats repeatable, #{length(raw)} left for a human, " <>
        "#{length(same)} tied to another feat's choice"
    )

    by_domain =
      decided
      |> Enum.group_by(fn record ->
        {:obj, inner} = record_value(record, "repeatable")
        List.keyfind(inner, "choice", 0) |> elem(1)
      end)
      |> Enum.sort_by(fn {domain, _records} -> to_string(domain) end)

    for {domain, group} <- by_domain do
      Mix.shell().info(
        "[choices]   #{domain || "(no choice named)"}: #{Enum.map_join(group, ", ", & &1.id)}"
      )
    end

    # Silence here is the finding: the pages that name a choice and never say the
    # feat repeats are the open question, not an oversight of this task.
    for record <- raw do
      Mix.shell().info("[choices]   undecided: #{record.id}")
    end

    for id <- FeatChoice.not_repeatable_ids() do
      Mix.shell().info("[choices]   not repeatable: #{id} — #{FeatChoice.denial_reason(id)}")
    end
  end

  defp report_dictionary(label, %{records: records, rule: {:obj, rule}}) do
    excluded = List.keyfind(rule, "excluded", 0) |> elem(1)
    available = List.keyfind(rule, "available", 0) |> elem(1)

    Mix.shell().info(
      "[#{label}] #{length(records)} entries, #{available} selectable" <>
        if(excluded == [], do: "", else: ", excluded: #{Enum.join(excluded, ", ")}")
    )
  end

  defp has_key?(record, key), do: List.keyfind(record.pairs, key, 0) != nil
  defp record_value(record, key), do: List.keyfind(record.pairs, key, 0) |> elem(1)

  defp put_repeatable(pairs, id, texts, entry) do
    case FeatChoice.decide(id, texts) do
      :none ->
        pairs

      {:raw, quote} ->
        insert_after(pairs, "unlocks", [
          {"repeatable_raw", {:obj, [{"quote", quote}, {"source", source(entry)}]}}
        ])

      {:repeatable, decided} ->
        distinct =
          case Map.fetch(decided, :distinct) do
            {:ok, value} -> [{"distinct", value}]
            :error -> []
          end

        inner =
          [{"choice", decided.choice}] ++
            distinct ++ [{"quote", decided.quote}, {"source", source(entry)}]

        insert_after(pairs, "unlocks", [{"repeatable", {:obj, inner}}])
    end
  end

  # `same_choice_as` goes *inside* `prereqs`, next to the `feats` list it refines:
  # it does not add a requirement, it says which of them has to have been taken
  # with this feat's own choice.
  defp put_same_choice(pairs, record) do
    required = prereq_value(pairs, "feats") || []

    case FeatChoice.same_choice_as(record.id, record.params["prereq"], required) do
      nil ->
        pairs

      decided ->
        Enum.map(pairs, fn
          {"prereqs", {:obj, inner}} -> {"prereqs", {:obj, refine(inner, decided)}}
          pair -> pair
        end)
    end
  end

  # Dropping the phrase from `qualifiers` is the point of `supersedes`: the
  # qualifier means "the schema cannot express this", and once the key expresses
  # it the caveat is not merely redundant, it is false. The phrase survives as
  # `same_choice_quote`, so no provenance is traded for the tidier output
  # (CLAUDE.md §3: every fact keeps its source).
  defp refine(inner, decided) do
    kept =
      Enum.flat_map(inner, fn
        {"qualifiers", phrases} ->
          case phrases -- List.wrap(decided.supersedes) do
            [] -> []
            remaining -> [{"qualifiers", remaining}]
          end

        pair ->
          [pair]
      end)

    kept ++ [{"same_choice_as", decided.feats}, {"same_choice_quote", decided.quote}]
  end

  defp prereq_value(pairs, key) do
    with {_key, {:obj, inner}} <- List.keyfind(pairs, "prereqs", 0),
         {_key, value} <- List.keyfind(inner, key, 0) do
      value
    else
      _otherwise -> nil
    end
  end

  # ── the dictionaries a repeatable feat chooses from ─────────────────────────
  #
  # A ranger's `Favored enemy` picks a racial type, `Spell focus` picks a school,
  # `Epic energy resistance` picks a damage type. None of those sets was anywhere
  # in the snapshot, so the choice half of a repeatable feat had nothing to point
  # at (see `BuildCalculator.Wiki.FeatChoice`).
  #
  # Each of the three is built the same way and checked the same way: take the
  # category's instances, then reconcile the size against a number the wiki
  # states **in prose on a different page**. Two independent statements agreeing
  # is the whole reason to believe the list; a category counted on its own would
  # just be a number with nothing to disagree with.

  @creature_type_category "Category:Races"
  @spell_school_category "Category:Spell schools"

  @favored_enemy_rule ~r/There are (\d+) favored enemy races available; of the (\d+) standard races, only \[\[([a-z]+)\]\] cannot be selected/u
  @spell_focus_variant ~r/Epic spell focus \(([a-z]+)\)/u
  @energy_choice ~r/\[\[([a-z]+) damage\|/u

  defp collect_creature_types(pages, memberships) do
    types = category_instances(pages, memberships, @creature_type_category)
    {entry, text} = page!(pages, "Favored enemy")

    {available, total, excluded} =
      case Regex.run(@favored_enemy_rule, flat(text)) do
        [_all, available, total, excluded] ->
          {String.to_integer(available), String.to_integer(total), excluded}

        nil ->
          raise """
          `Favored enemy` no longer states how many races it can choose from. That \
          sentence is the only source for the count, and creature_types.json is \
          checked against it — re-read the page before regenerating.
          """
      end

    ids = Enum.map(types, fn {entry, _text} -> id(entry.title) end)

    verify_count!("creature types", @creature_type_category, length(types), total, entry.title)
    verify_excluded!("creature types", [excluded], ids, available, total)

    records =
      for {type_entry, type_text} <- types do
        selectable = id(type_entry.title) != excluded

        {:obj,
         [{"id", id(type_entry.title)}, {"name", type_entry.title}, {"favored_enemy", selectable}] ++
           note_pair(selectable, type_text, "favored enemy") ++
           [{"source", source(type_entry)}]}
      end

    %{
      records: records,
      rule:
        {:obj,
         [
           {"feat", "favored_enemy"},
           {"gate", "favored_enemy"},
           {"available", available},
           {"total", total},
           {"excluded", [excluded]},
           {"quote", sentence!(text, "There are #{available} favored enemy races available")},
           {"source", source(entry)}
         ]}
    }
  end

  defp collect_spell_schools(pages, memberships) do
    schools = category_instances(pages, memberships, @spell_school_category)
    ids = Enum.map(schools, fn {entry, _text} -> id(entry.title) end)

    # The base `Spell focus` page carries one icon and no list of schools; the
    # epic variant carries one icon per school and is the only page that
    # enumerates them. Both feats choose from the same set, so the strip is the
    # enumeration for the family.
    {epic_entry, epic_text} = page!(pages, "Epic spell focus")

    variants =
      @spell_focus_variant |> Regex.scan(epic_text) |> Enum.map(&List.last/1) |> Enum.sort()

    excluded = ids -- variants

    verify_count!(
      "spell schools",
      @spell_school_category,
      length(schools),
      length(variants) + length(excluded),
      epic_entry.title
    )

    verify_excluded!("spell schools", excluded, ids, length(variants), length(schools))

    records =
      for {entry, text} <- schools do
        selectable = id(entry.title) not in excluded

        {:obj,
         [{"id", id(entry.title)}, {"name", entry.title}, {@domain_gate, selectable}] ++
           note_pair(selectable, text, "not truly a") ++
           [{"source", source(entry)}]}
      end

    # The reason universal is out is on universal's own page, not on the feat's:
    # the strip is *how* the exclusion was detected, the sentence is *why* it is
    # right. Quoting the feat's effect text here would evidence neither.
    {reason_entry, reason_text} =
      case excluded do
        [only] -> page!(pages, name_of(schools, only))
        _otherwise -> {epic_entry, epic_text}
      end

    %{
      records: records,
      rule:
        {:obj,
         [
           {"feat", "spell_focus"},
           {"gate", @domain_gate},
           {"available", length(variants)},
           {"total", length(schools)},
           {"excluded", excluded},
           {"quote", sentence!(reason_text, "not truly a")},
           {"source", source(reason_entry)},
           {"corroborated_by", {:obj, [{"variants", variants}, {"source", source(epic_entry)}]}}
         ]}
    }
  end

  defp name_of(pages, id) do
    {entry, _text} = Enum.find(pages, fn {entry, _text} -> id(entry.title) == id end)
    entry.title
  end

  # ── weapons (задача 3.5, часть A) ───────────────────────────────────────────

  @weapon_category "Category:Weapons"

  # The seven feat pages that carry an icon strip, one icon per weapon the feat
  # has a variant for. This is the same evidence `spell_schools` takes off `Epic
  # spell focus`, and there are seven independent copies of it rather than one.
  @weapon_icon_pages [
    "Weapon focus",
    "Weapon specialization",
    "Epic weapon focus",
    "Epic weapon specialization",
    "Improved critical",
    "Overwhelming critical",
    "Devastating critical"
  ]

  # `[[Image:Ife wepfoc bsw.gif|right|Weapon focus (bastard sword)]]` — the alt
  # text's parenthesis is the weapon. Read out of the strip above `{{feat`, so a
  # parenthesis inside the feat's own prose cannot join the set.
  @weapon_icon ~r/\[\[\s*Image:[^\]]*\(([^)]+)\)\s*\]\]/u

  # ⚠️ THE ONLY HAND-ASSIGNED NAME IN THIS DICTIONARY, and it is an alias rather
  # than an id: the epic pages label the creature icon `creature weapon` (the
  # page title) and the non-epic ones just `creature`. Everything else in all
  # seven strips is the page title verbatim, and `weapon_selectable!/2` raises on
  # any name it cannot resolve — so a strip that grows a new spelling stops the
  # build instead of quietly dropping a weapon out of the domain.
  @weapon_icon_aliases %{"creature" => "creature weapon"}

  # `Weapon of choice` states its own, narrower set in prose. Quoted in full
  # because every clause of it is load-bearing.
  @weapon_of_choice_anchor "This feat is only available for [[melee]] weapons"
  @weapon_of_choice_excluded ["unarmed strike", "lance", "magic staff", "creature weapon"]

  @weapon_exclusion_anchor "There is no version of this feat for the [[magic staff]] or [[lance]]"

  # ── Siala's own taxonomy of weapons ────────────────────────────────────────
  #
  # ⚠️ FANDOM DOES NOT ANSWER THIS QUESTION AND CANNOT. Siala replaced the whole
  # vanilla weapon-proficiency system with five feats of its own — клинковое,
  # древковое, молоты, топоры, дальний бой — and Fandom groups the same weapons
  # differently (`Category:Bladed weapons` holds the halberd and the scythe,
  # which Siala files under древковое; `Category:Axes` holds the double axe and
  # the throwing axe, which Siala does not). So the divergences below are the
  # interesting part rather than noise.
  #
  # ✅ ПОДТВЕРЖДЕНО Dan 16.08.2026 — `assumed` в этой таблице больше нет.
  # ⚠️ Здесь стояло «**every** assignment below is ours» плюс Dan, 10.08.2026:
  # «пока допущение с гэпом, точный маппинг в вопросы ко мне сохрани, я потом
  # уточню». Уточнил, и уточнение сняло не то, что ждали: **группу Сиала называет
  # сама, и дважды** — пятью страницами фитов («Владение клинковым» перечисляет
  # кинжалы, кукри, короткие/длинные/полуторные/великие мечи, рапиры, скимитары,
  # катаны) и колонкой «Тип оружия» сводной таблицы на `Система оружия`. Нашим
  # был только ПЕРЕВОД ИМЕНИ («Полуторные мечи» = Bastard sword), и проверял Dan
  # именно его: «Я глянул, вроде перевод подходит».
  #
  # Сверка обеих сиальских страниц против нашего назначения — 38 строк из 38,
  # расхождений ноль; тип урона сходится тоже 38 из 38 (у моргенштерна, алебарды
  # и косы Fandom даёт два типа, Сиала называет один из этих двух — сужение,
  # а не спор). Живьём её держит `verify_grip_groups!/2`.
  #
  # ⚠️ Снято НЕ потому, что русского имени нет в интерфейсе (его там правда нет —
  # у записи оружия поля `ru` не существует вовсе, `Labels.weapon_name/2` отдаёт
  # английское). Маппинг не декоративный: он решает, какой фит владения оружие
  # потребует и какой бонус за тип оружия начислится, — то есть виден в числах.
  # Довод «мы это не показываем» здесь НЕ применим и к другим допущениям
  # переносу не подлежит.
  #
  # Теперь `verified` приходит двумя маршрутами, и это разное качество довода:
  #   * `ranged` (8) — страница-категория Fandom **перечисляет** тех же восьмерых,
  #     то есть таксономии совпали сами;
  #   * blade / axe / hammer / polearm (30) + `lance` — сверка Dan (`source: user`,
  #     верхняя строка ранга §3, перепроверить по ссылке нельзя).
  # `nil` по-прежнему значит, что Сиала не называет оружие ни в одной категории;
  # сегодня это ровно пять атак существ, и это находка, а не слот под заполнение.
  #
  # ⚠️ The counts here are guarded live against the Siala layer: `weapon_groups!/2`
  # sums the weapons each of the five feats unlocks and raises if a group's total
  # no longer matches what we assigned. A category quietly growing a member on
  # either side stops the build.
  @siala_weapon_groups %{
    # клинковое — 9, and this is the group Fandom agrees with least: its
    # `Category:Bladed weapons` holds fourteen of the standard weapons.
    "bastard_sword" => {"blade", "verified", nil},
    "dagger" => {"blade", "verified", nil},
    "greatsword" => {"blade", "verified", nil},
    "katana" => {"blade", "verified", nil},
    "kukri" => {"blade", "verified", nil},
    "longsword" => {"blade", "verified", nil},
    "rapier" => {"blade", "verified", nil},
    "scimitar" => {"blade", "verified", nil},
    "shortsword" => {"blade", "verified", nil},

    # топоры — 6. Fandom's `Category:Axes` also holds six, and the equal count is
    # a false comfort: two members differ each way.
    "battleaxe" => {"axe", "verified", nil},
    "dwarven_waraxe" => {"axe", "verified", nil},
    "greataxe" => {"axe", "verified", nil},
    "handaxe" => {"axe", "verified", nil},
    "kama" =>
      {"axe", "verified",
       "Fandom files the kama under bladed and exotic weapons; Siala's «Владение топорами» names камы."},
    "sickle" =>
      {"axe", "verified",
       "Fandom files the sickle under bladed weapons; Siala's «Владение топорами» names серпы."},

    # молоты — 7, and the whip is the surprise: it deals slashing damage and
    # Fandom files it under exotic weapons alone.
    "heavy_flail" => {"hammer", "verified", nil},
    "light_flail" => {"hammer", "verified", nil},
    "light_hammer" => {"hammer", "verified", nil},
    "mace" => {"hammer", "verified", nil},
    "morningstar" => {"hammer", "verified", nil},
    "warhammer" => {"hammer", "verified", nil},
    "whip" =>
      {"hammer", "verified",
       "Fandom files the whip under exotic weapons and its damage is slashing; Siala's «Владение молотами» names кнуты first."},

    # древковое — 8. Fandom has no equivalent: its `Category:Polearms` holds five
    # (including the lance, which needs no proficiency), while Siala's group also
    # takes in the quarterstaff and all three double-sided weapons.
    "dire_mace" =>
      {"polearm", "verified",
       "Fandom files it under blunt and double-sided weapons; Siala's «Владение древковым» names двусторонние булавы."},
    "double_axe" =>
      {"polearm", "verified",
       "Fandom files it under axes; Siala's «Владение древковым» names двусторонние топоры."},
    "halberd" =>
      {"polearm", "verified",
       "Fandom files it under bladed weapons as well as polearms; Siala keeps древковое separate from клинковое."},
    "quarterstaff" =>
      {"polearm", "verified",
       "Fandom files it under blunt and simple weapons. ⚠️ NOT the weapon Dan meant by «бегать с посохом»: that is `magic_staff`, which needs no proficiency on both wikis, while Siala's «Владение древковым» names Посохи at its first step."},
    "scythe" =>
      {"polearm", "verified",
       "Fandom files it under bladed and exotic weapons as well as polearms; Siala keeps древковое separate."},
    "spear" => {"polearm", "verified", nil},
    "trident" => {"polearm", "verified", nil},
    "two_bladed_sword" =>
      {"polearm", "verified",
       "Fandom files it under bladed and double-sided weapons; Siala's «Владение древковым» names двулезвийные мечи."},

    # дальний бой — 8, and the only group where the two taxonomies coincide: the
    # `Category:Ranged weapons` subtree holds exactly these eight.
    "dart" => {"ranged", "verified", nil},
    "heavy_crossbow" => {"ranged", "verified", nil},
    "light_crossbow" => {"ranged", "verified", nil},
    "longbow" => {"ranged", "verified", nil},
    "shortbow" => {"ranged", "verified", nil},
    "shuriken" => {"ranged", "verified", nil},
    "sling" => {"ranged", "verified", nil},
    "throwing_axe" =>
      {"ranged", "verified",
       "Fandom files it under axes too; both wikis also call it ranged, and Siala's «Владение оружием дальнего боя» names метательные топоры."},

    # ⚠️ The sixth state, and it is a value rather than a footnote: a wizard who
    # took no proficiency feat at all still fights, so a gear list filtered by
    # proficiency feats must always let this through.
    "magic_staff" =>
      {"no_proficiency_required", "verified",
       "Fandom states `proficiency=none needed` and that no weapon feat has a magic staff variant; Dan measured the same in game — «некоторые маги могут ничего не брать, бегать с посохом, он не требует владения»."},
    # ⚠️ Лэнса на Сиале НЕТ вовсе (Dan, 16.08.2026), поэтому сиальской группы
    # у него не существует — и «мы её угадали» было бы утверждением о том,
    # чего нет. Ответ здесь целиком ванильный и прочитанный.
    "lance" =>
      {"no_proficiency_required", "verified",
       "Fandom states `proficiency=none` and «This item is not supported by feats». No Siala page mentions the lance at all — and Dan confirmed on 16.08.2026 that the shard has no such weapon («нет такого на Сиале»), so there is no Siala group to be unread about. `overrides.json` → `weapons.absent_on_shard` keeps it out of the Siala list; the vanilla ruleset still offers it, and there its proficiency answer comes off the Fandom page directly."},

    # `nil` — Siala names these in none of its five feats, and that is what the
    # data says. Filling them in by resemblance would put a weapon in a list the
    # source demonstrably leaves out.
    # ✅ ИЗМЕРЕНО Dan 16.08.2026 (посмотрел список оружия в игре):
    # «club, magic staff и unarmed не требуют фитов, они доступны всем классам на Сиале базово, можно их указывать как доступные без оговорок».
    #
    # ⚠️ Здесь у обоих стояло `unknown` — «шард про это не высказался», — и клуб
    # из-за этого нёс гэп `{:missing_data, {:weapon_proficiency, :club}}`.
    # Оговорка была честной ровно до этого дня: Сиала действительно не называет
    # дубину ни в одном из пяти фитов владения, и «не назвали» читалось как
    # «неизвестно». Теперь известно — и это не чтение страницы, а наблюдение,
    # то есть верхняя строка ранга источников (CLAUDE.md §3).
    "club" =>
      {"no_proficiency_required", "verified",
       "⚠️ Siala names the club in NONE of its five proficiency feats — «Владение молотами» lists кнуты, булавы, цепы and молоты and no дубины, and Fandom files it under blunt and simple weapons. That silence read as «unread» until Dan checked the game on 16.08.2026: «club, magic staff и unarmed не требуют фитов, они доступны всем классам на Сиале базово, можно их указывать как доступные без оговорок». The shard's own «Оружие, не требующее фитов» section says the same in prose («это оружие не требует умений»), so the measurement confirms a page nobody had connected to this field."},
    "unarmed_strike" =>
      {"no_proficiency_required", "verified",
       "Not an item: Fandom states `proficiency=n/a`, and Siala's five feats are about equipment. Selectable for Weapon focus all the same. ⚠️ Was `unknown` until Dan checked the game on 16.08.2026: «club, magic staff и unarmed не требуют фитов, они доступны всем классам на Сиале базово, можно их указывать как доступные без оговорок» — an unarmed character needs no feat to punch, and the field now says so instead of leaving it unread."},
    "creature_weapon" => {nil, "unknown", "Creature weapon, not a player's item."},
    "bite_item" => {nil, "unknown", "Creature weapon, not a player's item."},
    "claw_item" => {nil, "unknown", "Creature weapon, not a player's item."},
    "gore_item" => {nil, "unknown", "Creature weapon, not a player's item."},
    "slam_item" => {nil, "unknown", "Creature weapon, not a player's item."}
  }

  # The Fandom category that groups weapons by the same *kind* of thing, per
  # Siala group — so the two counts sit side by side in the data and our
  # assignment cannot read as if it came off the category. Counted live, because
  # a number typed into a note is a number nobody rechecks.
  #
  # `no_proficiency_required` has no counterpart: Fandom states it per weapon in
  # the `proficiency=` parameter, not by filing the weapon anywhere.
  @fandom_grouping_categories %{
    "blade" => "Category:Bladed weapons",
    "axe" => "Category:Axes",
    "hammer" => "Category:Blunt weapons",
    "polearm" => "Category:Polearms",
    "ranged" => "Category:Ranged weapons",
    "no_proficiency_required" => nil
  }

  # group id => the Siala feat that defines it. `no_proficiency_required` has no
  # feat by construction — it is the state of needing none.
  @siala_weapon_group_feats %{
    "blade" => "siala_blade_proficiency",
    "polearm" => "siala_polearm_proficiency",
    "hammer" => "siala_hammer_proficiency",
    "axe" => "siala_axe_proficiency",
    "ranged" => "siala_ranged_proficiency",
    "no_proficiency_required" => nil
  }

  # The one boolean field that is *meant* to be read as a per-feat gate.
  # `Loader.Reading.entry_flags/1` indexes **every** boolean field a dictionary entry
  # carries, and `FeatChoices.values/3` looks a gate up by feat id — so a
  # descriptive field that happened to share a name with a feat would silently
  # become that feat's list of allowed values. `verify_weapon_gates!/2` is the
  # guard, and it exists because the failure would be invisible: the feat would
  # simply offer the eight ranged weapons, or the three double-sided ones, and
  # look like it was working.
  @weapon_feat_gates ["weapon_of_choice"]

  # ── Siala's own grip column, задача 3.40 ────────────────────────────────────
  #
  # `Система оружия`'s sortable table states a grip — одноручное / двуручное /
  # двустороннее — for 38 of the 47 weapons, but only **for a character of the
  # usual (medium) size**. That is a different fact from `_grip` above (see
  # `weapon_grip_block/2`): that block is the general vanilla RULE, grip as a
  # function of the weapon's size against the wielder's, with no per-weapon
  # column on purpose because a fixed one would be wrong for a gnome or a
  # halfling. This is what Siala's own page states outright for the common
  # case — a value, not a rule — and it is recorded as one.
  @siala_weapon_table_page "Система оружия"

  @grip_table_header [
    "Требуемый уровень",
    "Название",
    "Урон",
    "Крит",
    "Множитель",
    "Тип урона",
    "Одно или двуручное",
    "Тип оружия"
  ]

  # The same closed vocabulary `SialaFeatPage` reads off the five «Владение …»
  # pages (`@grips` there) — kept as its own copy rather than exported and
  # shared, so `grip_from_proficiency_feats!/2` and `weapon_grip_lookup!/3`
  # below cross-check two genuinely independent readings instead of one
  # function calling the other twice.
  # Конфликты хвата, РАЗРЕШЁННЫЕ наблюдением Dan в игре. Ключ — id оружия.
  #
  # ⚠️ Это третий источник поверх двух спорящих, а не выбор одной из сторон:
  # «игрок наблюдал в игре» стоит верхней строкой ранга источников (CLAUDE.md §3),
  # выше страницы правил и выше сводной таблицы. Обе цитаты при этом остаются
  # в `conflicts` записи — вычеркнутый спор дороже отсутствующего.
  #
  # ⚠️ ИСТОРИЯ ЭТОЙ ЗАПИСИ — сама по себе урок, и стёрта она не будет.
  # 16.08.2026 Dan сперва ответил «одноручный, можно вносить как факт», и значение
  # было записано так. В тот же день он ответ ОТОЗВАЛ, перечитав таблицу: «отмена
  # моего предыдущего высказывания о размере, оставляем трезубец двуручным».
  #
  # ⚠️ Отзыв подтверждается данными ДВАЖДЫ, и оба довода структурные, а не по вкусу:
  #   1. трезубец `size: large`, а `large` во всём справочнике даёт двуручное или
  #      двустороннее — одноручным он был бы ЕДИНСТВЕННЫМ исключением из правила,
  #      которое держится у всех остальных 37 строк;
  #   2. вся древковая группа (8 из 8) — `large` и двуручная либо двусторонняя;
  #      одноручный трезубец был бы уникален и внутри своей группы тоже.
  # То есть ошибается страница фита, а не таблица.
  #
  # ⚠️ Запись всё равно ОСТАЁТСЯ явной, хотя теперь совпадает со значением таблицы:
  # она фиксирует, что конфликт РЕШЁН человеком, а не что его нет. Убрать её значит
  # вернуть спор в состояние «никто не выбирал».
  @siala_grip_resolved %{
    "trident" =>
      {"two_handed", "2026-08-16",
       "на Сиала вики «Система_оружия» странице есть таблица оружия, там есть трезубец " <>
         "и он указан как двуручный. Похоже что всё древковое оружие двуручное? Тогда " <>
         "отмена моего предыдущего высказывания о размере, оставляем трезубец двуручным"}
  }

  @siala_grips %{
    "одноручное" => "one_handed",
    "двуручное" => "two_handed",
    "двустороннее" => "double_sided"
  }

  # The table's own "Тип оружия" column, folded onto the five group ids
  # `@siala_weapon_groups` already assigns. Read only to cross-check that
  # assignment against a second Siala page — never to override it, and never
  # written out as a field of its own (see `verify_grip_groups!/2`).
  @siala_weapon_type_ru %{
    "клинковое" => "blade",
    "древковое" => "polearm",
    "дальнего боя" => "ranged",
    "топоры" => "axe",
    "молоты" => "hammer"
  }

  # The table's "Название" column: weapon id => the exact Russian text of its
  # row. ⚠️ EVERY key here is our own reading, exactly like `@siala_weapon_groups`
  # above — the table names a weapon, never one of our ids — so `assumed` is the
  # default `siala_grip_status`. Nine rows are `verified` instead, because THIS
  # SAME PAGE glosses the English name outright elsewhere on it: six in
  # `== Двуручное оружие ==` (Greataxe, Heavy flail, Halberd, Greatsword, Spear,
  # Scythe) and three more in `== Комбинированное оружие ==` (double axe, dire
  # mace, two-bladed sword). No other row gets this corroboration; the shard's
  # own prose happens to gloss exactly the weapons named in those two sections
  # and no others, not every двуручное weapon.
  @siala_weapon_grip_names %{
    "dagger" => {"Кинжалы", "assumed", nil},
    "kukri" => {"Кукри", "assumed", nil},
    "shortsword" => {"Короткие мечи", "assumed", nil},
    "longsword" => {"Длинные мечи", "assumed", nil},
    "bastard_sword" => {"Полуторные мечи", "assumed", nil},
    "greatsword" =>
      {"Великие мечи", "verified",
       "«Великий меч (Greatsword)» — раздел «Двуручное оружие» той же страницы."},
    "rapier" => {"Рапиры", "assumed", nil},
    "scimitar" => {"Скимитары", "assumed", nil},
    "katana" => {"Катаны", "assumed", nil},
    "quarterstaff" => {"Посохи", "assumed", nil},
    "dire_mace" =>
      {"Двусторонние булавы", "verified",
       "«Двусторонняя булава (dire mace)» — раздел «Комбинированное оружие» той же страницы."},
    "spear" =>
      {"Копья", "verified", "«Копье (Spear)» — раздел «Двуручное оружие» той же страницы."},
    "double_axe" =>
      {"Двусторонние топоры", "verified",
       "«Двусторонний топор (double axe)» — раздел «Комбинированное оружие» той же страницы."},
    "halberd" =>
      {"Алебарды", "verified",
       "«Алебарда (Halberd)» — раздел «Двуручное оружие» той же страницы."},
    "trident" => {"Трезубцы", "assumed", nil},
    "scythe" =>
      {"Косы", "verified", "«Коса (Scythe)» — раздел «Двуручное оружие» той же страницы."},
    "two_bladed_sword" =>
      {"Двулезвийные мечи", "verified",
       "«Двулезвийный меч (two-bladed sword)» — раздел «Комбинированное оружие» той же страницы."},
    "shuriken" => {"Сюрикены", "assumed", nil},
    "dart" => {"Дротики", "assumed", nil},
    "shortbow" => {"Короткие луки", "assumed", nil},
    "light_crossbow" => {"Легкие арбалеты", "assumed", nil},
    "longbow" => {"Длинные луки", "assumed", nil},
    "sling" => {"Пращи", "assumed", nil},
    "heavy_crossbow" => {"Тяжелые арбалеты", "assumed", nil},
    "throwing_axe" => {"Метательные топоры", "assumed", nil},
    "sickle" => {"Серпы", "assumed", nil},
    "handaxe" => {"Ручные топоры", "assumed", nil},
    "kama" => {"Камы", "assumed", nil},
    "battleaxe" => {"Боевые топоры", "assumed", nil},
    "greataxe" =>
      {"Великие топоры", "verified",
       "«Великий топор (Greataxe)» — раздел «Двуручное оружие» той же страницы."},
    "dwarven_waraxe" => {"Гномские боевые топоры", "assumed", nil},
    "whip" => {"Кнуты", "assumed", nil},
    "light_hammer" => {"Легкие молоты", "assumed", nil},
    "mace" => {"Булавы", "assumed", nil},
    "heavy_flail" =>
      {"Тяжелые цепы", "verified",
       "«Тяжелый цеп (Heavy flail)» — раздел «Двуручное оружие» той же страницы."},
    "light_flail" => {"Легкие цепы", "assumed", nil},
    "morningstar" => {"Моргенштерны (палицы)", "assumed", nil},
    "warhammer" => {"Боевые молоты", "assumed", nil}
  }

  # The nine weapons the table simply does not carry a row for — a finding
  # (CLAUDE.md §3: absence is not a gap to fill by resemblance), each with the
  # reason read off the page rather than assumed.
  @siala_weapon_grip_absent %{
    "bite_item" => "Creature weapon, not a player's item; absent from the table.",
    "claw_item" => "Creature weapon, not a player's item; absent from the table.",
    "gore_item" => "Creature weapon, not a player's item; absent from the table.",
    "slam_item" => "Creature weapon, not a player's item; absent from the table.",
    "creature_weapon" => "Creature weapon, not a player's item; absent from the table.",
    "club" =>
      "Absent from the table. «Оружие, не требующее фитов» calls it «среднее оружие» " <>
        "(a SIZE, not a grip) and says it needs no proficiency feat at all — the table " <>
        "states no grip word for it either way.",
    "lance" => "Absent from the table; no Siala page names the lance at all.",
    "magic_staff" =>
      "Absent from the table — its row «Посохи» is `quarterstaff`. The separate " <>
        "«Магические посохи» prose (§Оружие, не требующее фитов) states no grip word either.",
    "unarmed_strike" => "Not a weapon item; the table names none of the natural weapons."
  }

  defp collect_weapons(pages, memberships, siala, feats, races) do
    weapons = category_instances(pages, memberships, @weapon_category)
    ranged_categories = ranged_categories!(memberships)

    parsed =
      for {entry, text} <- weapons,
          {:ok, template} <- [WeaponPage.template(text)],
          do: {entry, WeaponPage.parse(template.params, entry.categories, ranged_categories)}

    verify_weapon_template!(weapons, parsed)

    by_title = Map.new(parsed, fn {entry, weapon} -> {String.downcase(entry.title), weapon} end)

    {selectable, icon_entry, icon_text} = weapon_selectable!(pages, by_title)
    of_choice = weapon_of_choice!(pages, by_title, selectable)
    sizes = weapon_sizes!(pages, by_title)

    excluded =
      by_title |> Map.keys() |> Enum.reject(&(&1 in selectable)) |> Enum.map(&id/1) |> Enum.sort()

    ids = for {entry, _weapon} <- parsed, do: id(entry.title)
    groups = weapon_groups!(ids, siala, memberships)

    verify_grip_coverage!(ids)
    {grip_page, grip_rows} = weapon_grip_rows!()
    verify_grip_groups!(grip_page, grip_rows)
    feat_grips = grip_from_proficiency_feats!(siala, length(grip_rows))
    grip_by_id = weapon_grip_lookup!(grip_page, grip_rows, feat_grips)
    verify_grip_delivery!(parsed, grip_by_id)
    size_order = weapon_size_order!(pages, parsed, sizes)
    verify_both_hands_grips!(grip_by_id)
    verify_stated_grip_size!(size_order)

    records =
      for {entry, weapon} <- Enum.sort_by(parsed, &id(elem(&1, 0).title)) do
        key = String.downcase(entry.title)

        weapon_record(
          entry,
          weapon,
          key in selectable,
          key in of_choice,
          sizes[key],
          Map.fetch!(@siala_weapon_groups, id(entry.title)),
          Map.fetch!(grip_by_id, id(entry.title))
        )
      end

    verify_weapon_gates!(records, feats)

    conflicts =
      for {entry, weapon} <- parsed,
          conflict <- WeaponPage.conflicts(weapon),
          do: Map.put(conflict, :id, id(entry.title))

    %{
      records: records,
      sizes: sizes,
      selectable: selectable,
      of_choice: of_choice,
      groups: groups,
      grip: %{entry: grip_page, rows: grip_rows, by_id: grip_by_id},
      blocks: [
        {"_grip", weapon_grip_block(pages, races, size_order)},
        {"_off_hand", weapon_off_hand_block(pages)},
        {"_siala_proficiency", groups.json},
        {"_siala_grip", siala_grip_block(grip_page, grip_by_id)}
      ],
      conflicts: conflicts,
      rule:
        {:obj,
         [
           {"feat", "weapon_focus"},
           {"gate", @domain_gate},
           {"available", length(selectable)},
           {"total", map_size(by_title)},
           {"excluded", excluded},
           {"quote", sentence!(icon_text, @weapon_exclusion_anchor)},
           {"source", source(icon_entry)},
           {"corroborated_by",
            {:obj,
             [
               {"icon_strips",
                Enum.map(@weapon_icon_pages, &{:obj, [{"page", &1}, {"variants", 41}]})},
               {"note",
                "All seven pages name the same 41 variants. `creature` on the four " <>
                  "non-epic strips and `creature weapon` on the three epic ones are the " <>
                  "same value spelled two ways — the one alias this dictionary carries."}
             ]}}
         ]}
    }
  end

  defp verify_weapon_gates!(records, feats) do
    feat_ids = MapSet.new(feats, &to_string(&1.id))

    booleans =
      for {:obj, pairs} <- records,
          {name, value} <- pairs,
          is_boolean(value),
          uniq: true,
          do: name

    accidental =
      for name <- booleans, name in @weapon_feat_gates == false, name in feat_ids, do: name

    unless accidental == [] do
      raise """
      weapons: #{inspect(accidental)} is both a descriptive boolean field and a feat id, so \
      `Loader.Reading.entry_flags/1` would hand that feat exactly the weapons carrying the field and \
      nothing else — a wrong list that looks like a working gate. Rename the field, or make \
      it a deliberate per-feat gate in @weapon_feat_gates.
      """
    end

    case @weapon_feat_gates -- MapSet.to_list(feat_ids) do
      [] -> :ok
      gone -> raise "weapons: gate #{inspect(gone)} names no feat any more"
    end
  end

  # `Category:Throwing weapons` is filed under `Category:Ranged weapons`, and a
  # page carries only its direct categories — so a dart is never labelled ranged
  # by its own page. The subcategory relation is read out of the snapshot rather
  # than hard-coded, because that is where the wiki states it.
  defp ranged_categories!(memberships) do
    ranged = WeaponPage.category_meanings().ranged

    subcategories =
      memberships
      |> Map.get(ranged, [])
      |> Enum.filter(&(&1["ns"] == 14))
      |> Enum.map(& &1["title"])

    if subcategories == [] do
      raise """
      #{ranged} no longer lists any subcategory. `Category:Throwing weapons` used to be \
      one, and it is the only reason a dart counts as ranged — check the category before \
      regenerating, or eight weapons silently become melee.
      """
    end

    [ranged | subcategories]
  end

  # Both directions, because either failing means the discriminator has stopped
  # being the template: a weapon page that lost its template would vanish from
  # the domain, and an overview page that gained one would join it.
  defp verify_weapon_template!(weapons, parsed) do
    without =
      for {entry, text} <- weapons,
          not match?({:ok, _}, WeaponPage.template(text)),
          do: {entry.title, WeaponPage.template(text)}

    broken = for {title, {:error, reason}} <- without, reason != :none, do: {title, reason}

    unless broken == [] do
      raise "weapons: #{inspect(broken)} carry an unreadable {{Weapon}} template"
    end

    if length(parsed) + length(without) != length(weapons) do
      raise "weapons: #{length(parsed)} parsed + #{length(without)} skipped != #{length(weapons)}"
    end
  end

  # The 41 the seven strips agree on. Raises on disagreement between pages and on
  # any name that is not a weapon we hold: both mean the strip is no longer the
  # enumeration this dictionary rests on.
  defp weapon_selectable!(pages, by_title) do
    {entry, text} = page!(pages, hd(@weapon_icon_pages))

    strips =
      for page <- @weapon_icon_pages, into: %{} do
        {_page_entry, page_text} = page!(pages, page)
        {page, weapon_icons(page_text, by_title)}
      end

    case strips |> Map.values() |> Enum.uniq() do
      [names] ->
        {names, entry, text}

      _disagree ->
        raise """
        weapons: the icon strips no longer agree on which weapons a weapon feat has a \
        variant for. #{inspect(Enum.map(strips, fn {page, names} -> {page, length(names)} end))}
        The set is the whole basis of the `selectable` gate — read the pages (CLAUDE.md §3).
        """
    end
  end

  defp weapon_icons(text, by_title) do
    head = text |> String.split("{{feat") |> List.first()

    names =
      @weapon_icon
      |> Regex.scan(head)
      |> Enum.map(fn [_all, name] ->
        key = String.downcase(name)
        Map.get(@weapon_icon_aliases, key, key)
      end)
      |> Enum.uniq()
      |> Enum.sort()

    case Enum.reject(names, &Map.has_key?(by_title, &1)) do
      [] ->
        names

      unknown ->
        raise """
        weapons: an icon strip names #{inspect(unknown)}, which is not a page carrying \
        {{Weapon}}. Either the weapon moved or the strip spells it a new way; assigning \
        it an id by hand would be inventing a name (CLAUDE.md §3).
        """
    end
  end

  # The narrower, per-feat set — and it is derived two ways so that neither has
  # to be trusted alone. From the feat's own Notes: the selectable weapons, less
  # melee (`ranged` off the categories), less the four it names. From `Melee
  # weapon`: the list BioWare's scripts use, less the magic staff, which is on
  # that list and excluded by the Notes.
  defp weapon_of_choice!(pages, by_title, selectable) do
    {notes_entry, notes_text} = page!(pages, "Weapon of choice")
    _quote = sentence!(notes_text, @weapon_of_choice_anchor)

    from_notes =
      selectable
      |> Enum.reject(&(&1 in @weapon_of_choice_excluded))
      |> Enum.reject(&Map.fetch!(by_title, &1).ranged)
      |> Enum.sort()

    {_melee_entry, melee_text} = page!(pages, "Melee weapon")

    from_melee =
      melee_text
      |> WeaponPage.melee_list()
      |> Enum.map(&String.downcase/1)
      |> Enum.reject(&(&1 in @weapon_of_choice_excluded))
      |> Enum.sort()

    unless from_notes == from_melee do
      raise """
      weapons: the two routes to `Weapon of choice`'s weapons disagree.
        from #{notes_entry.title} (selectable, melee, minus the four it names): #{inspect(from_notes -- from_melee)}
        from `Melee weapon` (BioWare's script list, minus the same four):       #{inspect(from_melee -- from_notes)}
      Neither list is the definition of melee on its own, which is why they are compared \
      rather than picked between (CLAUDE.md §3).
      """
    end

    from_notes
  end

  # The second statement of every size: the `Weapon size` table. The parameter is
  # the first. Sizes disagreeing is a conflict on the record, not something this
  # function resolves — but a weapon the table does not mention at all is normal
  # (it holds no creature items and no unarmed strike), so absence is not a fault.
  defp weapon_sizes!(pages, by_title) do
    {entry, text} = page!(pages, "Weapon size")
    table = WeaponPage.size_table(text)

    case Enum.reject(Map.keys(table), &Map.has_key?(by_title, String.downcase(&1))) do
      [] ->
        :ok

      unknown ->
        raise "weapons: `#{entry.title}` names #{inspect(unknown)}, which carries no {{Weapon}}"
    end

    Map.new(table, fn {title, row} -> {String.downcase(title), row} end)
  end

  @grip_anchor "A melee weapon one size larger than the wielder is a [[two-handed weapon]]"
  @light_anchor "A melee weapon at least one size smaller than the wielder is considered a [[light weapon]]"
  @two_handed_anchor "a [[weapon]] whose [[weapon size]] is one category larger than its wielder"
  @wieldable_anchor "up to one size larger than their own size and down to two sizes smaller"
  @unwieldable_anchor "are not considered two-handed weapons because they cannot be wielded at all"
  # ⚠ Оба якоря намеренно взяты у ПОСЛЕДСТВИЯ, а не у определения, и не из вкуса:
  # `sentence_with/2` рвёт предложение на `|`, а обе фразы про «require two hands»
  # стоят сразу после ссылки вида `[[weapon size|large weapons]]` — цитата вышла бы
  # обрубленной с середины. Эти два предложения говорят ровно то, ради чего список
  # заведён (щит рядом с таким оружием невозможен), и цитируются целиком.
  @both_hands_anchor "The most significant consequence of this may be the inability to use a " <>
                       "[[shield]] while wielding a two-handed weapon"
  @double_sided_anchor "They also necessitate a weapon switch if a [[shield]] becomes desired"

  # Which grip words mean "the off hand is taken". Two of the three, and both are
  # quoted below rather than reasoned out: `two_handed` off `Two-handed weapon`
  # («These weapons require two hands to wield … they also block equipping
  # anything in the off-hand slot»), `double_sided` off `Double-sided weapon`
  # («Even though these are large weapons and require two hands to wield …»).
  # `one_handed` is the third and is deliberately absent.
  #
  # ⚠ A literal here for the same reason `two_handed_when` beside it is one: the
  # parser restates a sentence it also quotes verbatim. What keeps it from
  # drifting is `verify_both_hands_grips!/1` — every word in this list has to be
  # a grip some weapon in the dictionary actually carries.
  @both_hands_grips ~w(two_handed double_sided)

  # Для какого размера владельца верна колонка «Одно или двуручное» Сиалы. Она
  # называет хват значением, а не правилом, и значение это — для персонажа
  # обычного размера; для Карлика тот же длинный меч двуручный. Записано полем
  # `_siala_grip.stated_for_size`, а сверяется с лестницей `_grip.size_order`.
  # Свойство оружия, при котором «двуручное» из колонки НЕ занимает вторую руку.
  # Замер Dan 16.08.2026 (кейс R5): дротик — «двуручное/метательное», а щит
  # с ним остаётся. Читается ядром (`Rules.Wield.both_hands?/3`).
  @siala_grip_off_hand_free_when "thrown"

  @siala_grip_stated_for_size "medium"

  # 🔴 ВТОРАЯ РУКА И ДАЛЬНОБОЙНОЕ ОРУЖИЕ (задача 3.142). Оба якоря — с одной
  # строки `Ranged weapon`, и оба цитируются целиком: первый несёт правило,
  # второй — глоссу источника к нему же.
  @ranged_off_hand_anchor "No ranged weapon may be wielded in the [[off-hand slot]]"
  @ranged_dual_wield_anchor "That is, [[dual-wield]]ing is not an option with ranged weapons"

  # Что именно правило держит вне второй руки — СЛОВО ИСТОЧНИКА, а не наше
  # обобщение: «nor can any **weapon** be wielded in the off-hand». Соседнее
  # правило про двуручное оружие сформулировано на той же вики шире («they also
  # block equipping **anything** in the off-hand slot»), и разница между
  # «weapon» и «anything» — ровно то, чем щит лучника отличается от щита
  # мечника: с пращой он остаётся (замер Dan 30.08.2026, `GAME_CHECKS.md` AI2).
  #
  # ⚠ Список закрытый со стороны ядра: загрузчик роняет сборку на занятии,
  # которое ядро вне второй руки удержать не умеет (`Rules.Wield.
  # off_hand_occupants/0`). Иначе шард объявил бы запрет, который молча
  # никогда не сработает.
  @ranged_bars_from_off_hand ~w(weapon)

  # Grip stated once, with its quotes, instead of a wrong column 47 times over.
  # The wielder-size half of the rule is the whole reason it cannot be a column:
  # a longsword is one-handed for a human and two-handed for a halfling, and both
  # wikis say so in as many words.
  defp weapon_grip_block(pages, races, size_order) do
    {size_entry, size_text} = page!(pages, "Weapon size")
    {two_entry, two_text} = page!(pages, "Two-handed weapon")
    {double_entry, double_text} = page!(pages, "Double-sided weapon")

    verify_grip_race_sizes!(races)

    {:obj,
     [
       {"_note",
        "Хват НЕ является свойством оружия и полем записи не сделан сознательно: " <>
          "он функция ДВУХ размеров — оружия и владельца. Длинный меч одноручный " <>
          "у человека и двуручный у карлика, и обе вики говорят это прямо. В записи " <>
          "лежит size (то, что источник утверждает), а правило — здесь, один раз. " <>
          "Считать хват из size и размера расы — дело ядра, как HP считается из " <>
          "хит-дайса и CON, а не лежит числом в данных. ⚠️ Это НЕ единственный факт " <>
          "о хвате в файле: `_siala_grip` ниже — ДРУГОЙ факт, значение (не правило), " <>
          "которое Сиала называет прямо для персонажа обычного размера (задача 3.40). " <>
          "Одно не отменяет другое — см. `_siala_grip._note`. ⚠️ `player_character_sizes` " <>
          "ниже — проза для человека, а НЕ машинный источник: с задачи 3.44 размер " <>
          "расы читается полем `size` в `vanilla/races.json` (small у Карлика и Гоблина, " <>
          "medium у остальных пяти), и эта проза сверяется с ним при каждой сборке " <>
          "(`verify_grip_race_sizes!/1`) — расхождение роняет `mix wiki.parse`, а не " <>
          "расходится молча.\n\n" <>
          "⚠️ `size_order`, `wieldable_steps`, `grip_by_step`, `grip_otherwise` " <>
          "и `grips_using_both_hands` заведены задачей 3.43 — " <>
          "это те же три предложения в машинной форме, ради которой правило и " <>
          "существует: «на одну категорию крупнее» — это ШАГ ПО ПОРЯДКУ, а порядка " <>
          "у четырёх слов нет. Порядок ПРОЧИТАН, а не назначен: это заголовки строк " <>
          "таблицы «Weapons by size and proficiency» сверху вниз " <>
          "(`WeaponPage.size_order/1`), и каждый `size` справочника обязан в нём " <>
          "быть, иначе сборка падает. Ключ `grip_by_step` — смещение по этому " <>
          "порядку (размер оружия минус размер владельца) и хват на нём; " <>
          "`wieldable_steps` — окно, вне которого оружие не взять вовсе.\n\n" <>
          "⚠️ `grip_by_step` отвечает на «сколько рук», а НЕ на «лёгкое ли оно»: " <>
          "лёгкое оружие остаётся одноручным, и это ДВА разных предложения " <>
          "источника, у каждого свой ключ (`grip_by_step` и `light_at_most_step`).\n\n" <>
          "⚠️ Здесь стояло, что `light_when` «осталось прозой — машинной формы " <>
          "у него нет, потому что ядру она не нужна ни для одного числа». " <>
          "Снято задачей 3.132 (28.08.2026): ядру она понадобилась — штраф боя " <>
          "двумя оружиями уменьшается на 2 обеим рукам, если во второй руке " <>
          "лёгкое оружие («Best results are achieved if the off-hand weapon is " <>
          "light», `fandom:Two-weapon fighting`). Это был ПЯТЫЙ случай формы " <>
          "«проза в файле данных правилом не является, пока её кто-нибудь " <>
          "не читает» (CLAUDE.md §9).\n\n" <>
          "⚠️ `light_excludes_property` — вторая половина ТОГО ЖЕ предложения, " <>
          "а не наша оговорка: источник говорит «A **melee** weapon at least one " <>
          "size smaller…», то есть про дальнобойное оружие не утверждает ничего. " <>
          "Свойство названо именем, которое ядро умеет прочитать со справочника " <>
          "(`Rules.Attack.weapon_property_field/1`), и загрузчик роняет сборку " <>
          "на имени, которого оно прочитать не умеет.\n\n" <>
          "⚠️ Оговорка Weapon Finesse `{:assumed, :finessable_weapon}` этим " <>
          "по-прежнему НЕ закрывается, и это не изменилось: справочник не знает " <>
          "«лёгкости для владельца данного размера» в смысле игры — у Finesse " <>
          "оружие перечислено поимённо (`weapon_one_of`), а не выведено из размера."},
       {"two_handed_when", "weapon size is one category larger than the wielder"},
       {"light_when", "weapon size is at least one category smaller than the wielder"},
       {"light_at_most_step", -1},
       {"light_excludes_property", "ranged"},
       {"unwieldable_when",
        "more than one category larger, or more than two categories smaller, than the wielder"},
       {"size_order", size_order},
       {"wieldable_steps", {:obj, [{"from", -2}, {"to", 1}]}},
       {"grip_by_step", {:obj, [{"1", "two_handed"}]}},
       {"grip_otherwise", "one_handed"},
       {"grips_using_both_hands", @both_hands_grips},
       {"player_character_sizes",
        {:obj,
         [
           {"medium", "all playable races except gnome and halfling"},
           {"small", "gnome and halfling"}
         ]}},
       {"quotes",
        {:obj,
         [
           {"two_handed", sentence!(two_text, @two_handed_anchor)},
           {"two_handed_source", source(two_entry)},
           {"grip", sentence!(size_text, @grip_anchor)},
           {"light", sentence!(size_text, @light_anchor)},
           {"wieldable", sentence!(size_text, @wieldable_anchor)},
           # ⚠ Со страницы `Two-handed weapon`, а не `Weapon size`: верхняя
           # половина окна названа на обеих, а «cannot be wielded at all» —
           # только там, и именно она отличает «двуручно» от «нельзя вовсе».
           {"unwieldable", sentence!(two_text, @unwieldable_anchor)},
           {"size_source", source(size_entry)},
           {"both_hands", sentence!(two_text, @both_hands_anchor)},
           {"double_sided", sentence!(double_text, @double_sided_anchor)},
           {"double_sided_source", source(double_entry)}
         ]}}
     ]}
  end

  # 🔴 КАКАЯ РУКА, а не сколько рук — и это ТРЕТИЙ факт файла о руках, отдельный
  # от `_grip` и от `_siala_grip` (задача 3.142). Те два отвечают «сколькими
  # руками держат» и «что об этом говорит колонка Сиалы»; здесь — «в какой руке
  # это вообще может оказаться», и размер к ответу не имеет отношения вовсе:
  # правило ключуется СВОЙСТВОМ оружия (`ranged`), а не его размером.
  #
  # Одно предложение источника, и в нём ДВА независимых запрета:
  #
  #   * дальнобойное оружие не кладут во вторую руку (`barred_from_off_hand`);
  #   * пока дальнобойное в главной, второй руки нет для ОРУЖИЯ
  #     (`bars_from_off_hand`).
  #
  # ⚠ Второй из первого не следует: праща одноручная, и по хвату вторая рука
  # у неё свободна. Ровно на этом мы и ошибались до 30.08.2026 — четыре
  # дальнобойных (`dart`, `shuriken`, `sling`, `throwing_axe`) проходили
  # во вторую руку, а остальные четыре отбивались ЧУЖОЙ причиной (двуручностью),
  # то есть совпадением исхода, а не правилом.
  #
  # ⚠ Свойство названо ИМЕНЕМ (`ranged`), которое ядро умеет прочитать
  # со справочника, — тот же приём и тот же сторож, что у
  # `_grip.light_excludes_property`. Правило, чьё свойство ядру неизвестно,
  # роняет сборку вместо того, чтобы молча не срабатывать.
  defp weapon_off_hand_block(pages) do
    {entry, text} = page!(pages, "Ranged weapon")

    {:obj,
     [
       {"_note",
        "В КАКОЙ РУКЕ может оказаться оружие — третий факт этого файла о руках, " <>
          "и он не про размер (задача 3.142). `_grip` отвечает «сколькими руками " <>
          "держат» (функция двух размеров), `_siala_grip` — «что об этом говорит " <>
          "колонка Сиалы»; здесь правило ключуется СВОЙСТВОМ оружия: дальнобойное " <>
          "во вторую руку не кладут, и пока оно в главной — вторая рука для оружия " <>
          "закрыта.\n\n" <>
          "⚠️ Это ДВА независимых запрета в одном предложении, и второй из первого " <>
          "не следует: праща одноручная, вторая рука у неё по хвату свободна. " <>
          "До 30.08.2026 модель разрешала во вторую руку четыре дальнобойных " <>
          "(дротик, сюрикен, пращу, метательный топор), а остальные четыре " <>
          "отбивала двуручностью — то есть совпадением исхода, а не этим правилом. " <>
          "Цена — до +6 бонуса атаки ни за что (+9 у сагровика на 40-м): вторая рука " <>
          "включает свой бонус за тип оружия, и меч с пращой давали щитовой AC " <>
          "и дальнобойный бонус атаки разом.\n\n" <>
          "🔴 `bars_from_off_hand` НЕСЁТ СЛОВО ИСТОЧНИКА, А НЕ НАШЕ ОБОБЩЕНИЕ: " <>
          "«nor can any **weapon** be wielded in the off-hand». Соседнее правило про " <>
          "двуручное оружие та же вики формулирует шире — «they also block equipping " <>
          "**anything** in the off-hand slot» (`fandom:Two-handed weapon`), — и " <>
          "разница между «weapon» и «anything» и есть щит лучника: с пращой он " <>
          "остаётся. Замер Dan 30.08.2026 (`GAME_CHECKS.md` AI2) подтвердил все три " <>
          "половины дословно: «игра дает его надеть только в правую руку. Не смотря " <>
          "на то, что праща — одноручная, взять с ней кинжал либо меч в левую руку " <>
          "нельзя. Но можно взять щит».\n\n" <>
          "⚠️ Занятия второй руки — закрытый список СО СТОРОНЫ ЯДРА " <>
          "(`Rules.Wield.off_hand_occupants/0`): снапшот, назвавший занятие, " <>
          "которое ядро вне второй руки удержать не умеет, роняет сборку. Иначе " <>
          "запрет молча никогда бы не сработал — та самая форма дефекта, ради " <>
          "которой заведена вся эта стража (CLAUDE.md §9).\n\n" <>
          "⚠️ Правило ванильное по источнику и потому действует на ОБА ruleset'а, " <>
          "как и `_grip`. Вики Сиалы о второй руке не говорит ничего; замер " <>
          "показывает, что шард ванильное поведение не трогал."},
       {"property", "ranged"},
       {"barred_from_off_hand", true},
       {"bars_from_off_hand", @ranged_bars_from_off_hand},
       {"status", "verified"},
       {"quotes",
        {:obj,
         [
           {"rule", sentence!(text, @ranged_off_hand_anchor)},
           {"gloss", sentence!(text, @ranged_dual_wield_anchor)},
           {"source", source(entry)}
         ]}},
       {"confirmed_in_game",
        {:obj,
         [
           {"kind", "user"},
           {"who", "Dan"},
           {"date", "2026-08-30"},
           {"case", "AI2"},
           {"quote",
            "игра дает его надеть только в правую руку. Не смотря на то, что праща — " <>
              "одноручная, взять с ней кинжал либо меч в левую руку нельзя. " <>
              "Но можно взять щит"}
         ]}}
     ]}
  end

  # Лестница размеров: заголовки строк таблицы `Weapon size` в порядке страницы.
  #
  # ⚠ Порядок ЧИТАЕТСЯ, а множество — пришпилено регуляркой `@size_header`
  # (`WeaponPage`), и это не небрежность, а страховка: пятый размер регуляркой не
  # опознается, а значит оружие с ним не найдёт себя в лестнице и сборка упадёт
  # здесь, вместо того чтобы молча выпасть из правила хвата.
  #
  # Сверяются ОБА утверждения о размере, которые справочник и так носит рядом:
  # параметр шаблона (`weapon.size`) и та же таблица (`size_from_table`). `nil`
  # законен — рукопашный удар и оружие существа размера не называют вовсе.
  defp weapon_size_order!(pages, parsed, sizes) do
    {entry, text} = page!(pages, "Weapon size")
    order = WeaponPage.size_order(text)

    if length(order) < 2 do
      raise "weapons: `#{entry.title}` no longer lays its table out by size " <>
              "(#{inspect(order)}) — the size ladder every grip rule is stated against " <>
              "cannot be read"
    end

    stated =
      for {_entry, weapon} <- parsed, not is_nil(weapon.size), uniq: true, do: weapon.size

    tabled = for {_title, row} <- sizes, not is_nil(row.size), uniq: true, do: row.size

    case Enum.sort(Enum.uniq(stated ++ tabled) -- order) do
      [] ->
        order

      unknown ->
        raise """
        weapons: #{inspect(unknown)} is a weapon size the `#{entry.title}` table has no row \
        for, so it has no place on the ladder #{inspect(order)}. Every size rule («one \
        category larger than the wielder») is a step along that order, and a size outside \
        it would silently stop being a two-handed weapon for anybody.
        """
    end
  end

  # Размер, для которого верна сиальская колонка хвата, обязан быть ступенью той
  # же лестницы: иначе «пересчитать для всех остальных» не от чего отсчитывать.
  defp verify_stated_grip_size!(size_order) do
    unless @siala_grip_stated_for_size in size_order do
      raise "weapons: `_siala_grip.stated_for_size` is #{inspect(@siala_grip_stated_for_size)}, " <>
              "which is not a rung of the size ladder #{inspect(size_order)}"
    end
  end

  # Каждое слово из `@both_hands_grips` обязано быть хватом, который в справочнике
  # действительно встречается. Опечатка иначе означала бы «щит можно всегда» —
  # молча и ровно у того оружия, ради которого правило заведено.
  defp verify_both_hands_grips!(grip_by_id) do
    known = for {_id, grip} <- grip_by_id, not is_nil(grip.grip), uniq: true, do: grip.grip

    case Enum.sort(@both_hands_grips -- known) do
      [] ->
        :ok

      missing ->
        raise """
        weapons: `_grip.grips_using_both_hands` names #{inspect(missing)}, and no weapon in \
        the dictionary carries that grip (it knows #{inspect(Enum.sort(known))}). A grip word \
        nothing has is a rule that never fires — the shield would stay legal beside the very \
        weapon this list exists to refuse it beside.
        """
    end
  end

  # AGENT_QUEUE.md §3.44: `player_character_sizes` above is prose written for a
  # human reader, kept for its quotes; the machine answer is `races.records`'
  # own `size` field, computed independently off each race's page (and,
  # cross-checked again there, off `Small stature`'s own `{{feat|prereq=…}}`).
  # This is the guard that stops the two from drifting apart unnoticed — a
  # third playable race gaining "small" (or one of the two losing it) fails
  # the build here rather than leaving this file's prose quietly wrong.
  defp verify_grip_race_sizes!(races) do
    small = races |> Enum.filter(&(&1.size == "small")) |> Enum.map(& &1.id) |> Enum.sort()

    unless small == ["gnome", "halfling"] do
      raise """
      weapons: `_grip.player_character_sizes` states the small playable races are gnome \
      and halfling, but `vanilla/races.json` now says #{inspect(small)} are. That file's \
      `size` field is the machine answer (задача 3.44) and this prose must never read \
      differently from it without this raising first.
      """
    end
  end

  # ── Siala's grip table, задача 3.40 ─────────────────────────────────────────

  # A page in the plain `siala` cache rather than the Fandom `pages` this file
  # otherwise reads throughout `collect_weapons/5` — `page!/2` only ever looks
  # inside the list it is handed, and every other caller hands it Fandom's.
  defp siala_page!(title) do
    case Enum.find(Cache.read_index!(@siala_wiki), &(&1.title == title)) do
      nil -> raise "`#{title}` is not in the #{@siala_wiki} cache"
      entry -> {entry, Cache.read_page!(@siala_wiki, entry)}
    end
  end

  # The «Сводная таблица оружия» section's one table, as `{entry, [row]}` —
  # `row` carries only the three columns this task reads (name, grip, the
  # table's own group word); damage/crit/multiplier/damage type are Siala's
  # own rebalanced numbers and stay out of scope (CLAUDE.md §3, Dan 10.08.2026:
  # «урон … для конструктора не важно, мы это не показываем»).
  defp weapon_grip_rows!() do
    {entry, wikitext} = siala_page!(@siala_weapon_table_page)

    case Wikitable.find_all(wikitext) do
      [source] ->
        grid = source |> Wikitable.parse() |> Map.fetch!(:rows) |> Wikitable.expand()
        [header | body] = grid
        verify_grip_table_header!(entry, header)
        {entry, Enum.map(body, &grip_table_row/1)}

      other ->
        raise "weapons: `#{entry.title}` no longer carries exactly one table (#{length(other)} found)"
    end
  end

  defp verify_grip_table_header!(entry, header) do
    labels = Enum.map(header, &(&1.text |> Wikitext.strip_links() |> String.trim()))

    unless labels == @grip_table_header do
      raise """
      weapons: `#{entry.title}`'s table header changed.
        expected: #{inspect(@grip_table_header)}
        found:    #{inspect(labels)}
      Read the page rather than reordering the columns to match (CLAUDE.md §3).
      """
    end
  end

  defp grip_table_row(cells) do
    [_level, name, _damage, _crit, _multiplier, _damage_type, grip, group] =
      Enum.map(cells, &(&1.text |> Wikitext.strip_links() |> String.trim()))

    %{name_ru: name, grip_raw: grip, group_ru: group}
  end

  # Cross-checks the table's OWN "Тип оружия" column against `@siala_weapon_groups`
  # (задача 3.5, read off the five «Владение …» pages) — a second Siala page
  # agreeing with the first, not a second opinion this task is allowed to prefer.
  # Never written out as a field: 3.40 is about grip, not about re-deciding 3.5.
  defp verify_grip_groups!(entry, rows) do
    names = Map.new(@siala_weapon_grip_names, fn {id, {ru, _status, _note}} -> {ru, id} end)

    mismatched =
      for row <- rows do
        id = Map.fetch!(names, row.name_ru)
        {group, _status, _note} = Map.fetch!(@siala_weapon_groups, id)

        table_group =
          Map.get(@siala_weapon_type_ru, row.group_ru) ||
            raise "weapons: `#{entry.title}` row `#{row.name_ru}` names an unrecognised " <>
                    "weapon type `#{inspect(row.group_ru)}`"

        {id, group, table_group}
      end
      |> Enum.reject(fn {_id, group, table_group} -> group == table_group end)

    unless mismatched == [] do
      raise """
      weapons: `#{entry.title}`'s own "Тип оружия" column disagrees with `@siala_weapon_groups` \
      (task 3.5) for #{inspect(mismatched)} — {id, our group, table's group}. The two are reading \
      the shard differently; read both before trusting either (CLAUDE.md §3).
      """
    end
  end

  # A second, independent reading of the same 38 grip values, keyed by the
  # LOWER-CASED Russian name: the five «Владение …» feat pages
  # `collect_siala_feats/1` already parses state the identical
  # `('''X-Y''' ''crit'' grip, урон - type)` blocks for every weapon they
  # unlock (`SialaFeatPage.unlocks/1`). Lower-cased because a name that leads
  # its own bullet keeps its capital ("Трезубцы") while one joined onto a
  # previous item with "и" does not ("Алебарды … и трезубцы") —
  # `SialaFeatPage.clean_weapon_name/1` strips the "и " but not the case, and
  # that is the wiki's OWN inconsistency to read around, not a typo to fix.
  #
  # ⚠️ This function only raises on a STRUCTURAL surprise (a page gone, or the
  # two sources naming a different NUMBER of weapons). It does NOT raise when
  # a value disagrees — `weapon_grip_lookup!/3` turns that into a `conflict` on
  # the one weapon it names, exactly like `Lance`/`Magic staff`'s proficiency
  # conflict, because CLAUDE.md §3 is explicit that a contradiction between two
  # pages is a finding to record, not a tie for the parser to break. It found
  # exactly one: `трезубцы` — the table says `двуручное`, «Владение древковым
  # оружием» says `одноручное` for the very same bullet. See `trident` in the
  # generated file.
  defp grip_from_proficiency_feats!(siala, expected_count) do
    by_name =
      for {_group, feat} <- @siala_weapon_group_feats, not is_nil(feat), reduce: %{} do
        acc ->
          record =
            Enum.find(siala.records, &(&1.id == feat)) ||
              raise "weapons: `#{feat}` is not in the Siala feat layer any more"

          for step <- record.page.unlocks || [], weapon <- step.weapons, reduce: acc do
            acc2 -> Map.put(acc2, String.downcase(weapon.name_ru), weapon.grip_raw)
          end
      end

    unless map_size(by_name) == expected_count do
      raise """
      weapons: the five «Владение …» pages name #{map_size(by_name)} weapons between them, but \
      `#{@siala_weapon_table_page}` names #{expected_count} — the two Siala sources of grip fell \
      out of step in COUNT, not just in a value; read both before trusting either (CLAUDE.md §3).
      """
    end

    by_name
  end

  # `ids` is every current weapon id (from `collect_weapons/5`, the same list
  # `weapon_groups!/3` already checks `@siala_weapon_groups` against) — checked
  # bidirectionally against the union of `@siala_weapon_grip_names` and
  # `@siala_weapon_grip_absent`, so a weapon added or removed upstream cannot
  # silently fall through either map.
  defp verify_grip_coverage!(ids) do
    mapped = MapSet.new(@siala_weapon_grip_names, fn {id, _} -> id end)
    absent = MapSet.new(@siala_weapon_grip_absent, fn {id, _} -> id end)

    overlap = MapSet.intersection(mapped, absent)

    unless MapSet.size(overlap) == 0 do
      raise "weapons: #{inspect(MapSet.to_list(overlap))} is both mapped and marked absent for grip"
    end

    covered = MapSet.union(mapped, absent)

    case Enum.sort(ids) -- Enum.sort(MapSet.to_list(covered)) do
      [] -> :ok
      new -> raise "weapons: #{inspect(new)} has no grip mapping and no absence reason"
    end

    case Enum.sort(MapSet.to_list(covered)) -- Enum.sort(ids) do
      [] ->
        :ok

      gone ->
        raise "weapons: #{inspect(gone)} has a grip mapping or absence reason but is no longer a weapon"
    end
  end

  # `%{id => %{grip:, raw:, status:, note:, conflict:}}` for all 47 —
  # `grip`/`raw`/`status` are `nil` for the nine `@siala_weapon_grip_absent`
  # entries, `note` names why. `conflict` is `nil` for 37 of the 38 present
  # entries and a weapon-record-`conflicts`-shaped map for `trident` — see
  # `grip_from_proficiency_feats!/2`.
  defp weapon_grip_lookup!(entry, rows, feat_grips) do
    names = Map.new(@siala_weapon_grip_names, fn {id, {ru, _status, _note}} -> {ru, id} end)

    unknown = for row <- rows, not Map.has_key?(names, row.name_ru), do: row.name_ru

    unless unknown == [] do
      raise """
      weapons: `#{entry.title}` names #{inspect(unknown)}, which `@siala_weapon_grip_names` does \
      not map to a weapon id — either the table gained a row or the id map fell out of step with \
      it; read the page rather than guessing an id (CLAUDE.md §3).
      """
    end

    by_ru = Map.new(rows, &{&1.name_ru, &1})

    present =
      for {id, {ru, status, note}} <- @siala_weapon_grip_names, into: %{} do
        row =
          Map.get(by_ru, ru) ||
            raise "weapons: `#{id}` names `#{ru}`, which is no longer on `#{entry.title}`"

        primary = row.grip_raw |> String.split("/") |> List.first() |> String.trim()

        grip =
          Map.get(@siala_grips, primary) ||
            raise "weapons: `#{entry.title}` row `#{ru}` has an unrecognised grip #{inspect(primary)}"

        feat_raw =
          Map.get(feat_grips, String.downcase(ru)) ||
            raise "weapons: `#{id}` (`#{ru}`) is on `#{entry.title}` but not on any of the five " <>
                    "«Владение …» pages — the two Siala sources of grip fell out of step (CLAUDE.md §3)."

        {id, grip_entry(entry, id, ru, row.grip_raw, grip, status, note, feat_raw)}
      end

    absent =
      for {id, note} <- @siala_weapon_grip_absent, into: %{} do
        {id, %{grip: nil, raw: nil, status: nil, note: note, conflict: nil}}
      end

    Map.merge(present, absent)
  end

  # `table_raw`/`feat_raw` are the same weapon's grip cell, read off two
  # independent Siala pages. Agreeing (37 of 38) is the ordinary case; the one
  # disagreement (`трезубцы`, task-3.40 discovery, cross-checked live against
  # `action=parse` — the table's rendering genuinely says «двуручное») becomes
  # a `conflicts`-shaped entry rather than a build failure, exactly like the
  # existing `Lance`/`Magic staff` proficiency conflict a few functions below.
  # The table's own value is kept in `grip`/`raw` — not because it outranks the
  # feat page, but because it is the source THIS task was asked to read; the
  # feat page's value is not discarded, it is named in `note` and in
  # `conflicts` (CLAUDE.md §3: record both, do not pick a side).
  defp grip_entry(_entry, _id, _ru, table_raw, grip, status, note, table_raw) do
    %{grip: grip, raw: table_raw, status: status, note: note, conflict: nil}
  end

  defp grip_entry(entry, id, ru, table_raw, grip, status, _note, feat_raw) do
    resolved = Map.get(@siala_grip_resolved, id)

    conflict = %{
      field: "siala_grip",
      from_parameter: table_raw,
      from_categories: feat_raw,
      parameter_raw: table_raw,
      note:
        "`#{entry.title}` states `#{table_raw}` for «#{ru}» (`#{id}`); the matching " <>
          "«Владение …» feat page states `#{feat_raw}` for the same bullet — a genuine " <>
          "disagreement between two Siala pages (checked live against the rendered page), " <>
          "not a parsing gap."
    }

    conflict_note =
      "⚠️ Конфликт источников Сиалы: «#{@siala_weapon_table_page}» называет «#{table_raw}», " <>
        "а соответствующая страница «Владение …» — «#{feat_raw}» (обе цитаты дословны, обе " <>
        "видны в `conflicts`). Значение таблицы (`#{table_raw}`) оставлено здесь как факт " <>
        "задачи 3.40 — не потому, что оно вернее, а потому, что таблица и есть источник, " <>
        "который просила задача; сторона намеренно не выбрана."

    case resolved do
      nil ->
        %{grip: grip, raw: table_raw, status: status, note: conflict_note, conflict: conflict}

      {resolved_grip, date, quote} ->
        %{
          grip: resolved_grip,
          raw: table_raw,
          status: "verified",
          note:
            conflict_note <>
              "\n\n✅ РАЗРЕШЁН НАБЛЮДЕНИЕМ Dan #{date}: «#{quote}». Значение здесь — " <>
              "ответ игрока, а не одной из двух страниц: «игрок наблюдал в игре» стоит " <>
              "верхней строкой ранга источников (CLAUDE.md §3), выше обеих. ⚠️ Обе " <>
              "спорящие цитаты ОСТАЛИСЬ в `conflicts` — разрешение это третий источник " <>
              "поверх двух, а не удаление проигравшего: без них следующий читатель " <>
              "решит, что страницы согласны, и «починит» значение обратно. " <>
              "⚠️ `siala_grip_raw` тоже остался прежним — он цитата таблицы, а не вывод.",
          conflict: conflict
        }
    end
  end

  # The reason `siala_grip_raw`'s delivery half (`.../метательное`,
  # `.../стрелковое`) never becomes a field of its own: it is exactly the
  # `ranged`/`thrown` pair `WeaponPage` already reads off Fandom's categories,
  # checked here over all 38 rows rather than assumed from the handful quoted
  # in `_siala_grip._note`. A weapon whose grip carries no slash at all is
  # checked too — "плоское значение" and "ranged: false" are the same claim.
  defp verify_grip_delivery!(parsed, grip_by_id) do
    checked =
      for {entry, weapon} <- parsed do
        id = id(entry.title)
        grip = Map.fetch!(grip_by_id, id)

        matched? =
          case grip.raw && String.split(grip.raw, "/", parts: 2) do
            nil -> true
            [_primary] -> not weapon.ranged
            [_primary, "метательное"] -> weapon.ranged and weapon.thrown
            [_primary, "стрелковое"] -> weapon.ranged and not weapon.thrown
          end

        {id, grip.raw, weapon.ranged, weapon.thrown, matched?}
      end

    mismatched = for row <- checked, not elem(row, 4), do: row

    unless mismatched == [] do
      raise """
      weapons: a grip cell's delivery half no longer matches `ranged`/`thrown` for \
      #{inspect(mismatched)} — {id, siala_grip_raw, ranged, thrown, matched?}. This is the whole \
      reason `siala_grip` carries no separate delivery field; read `_siala_grip._note` before \
      adding one back.
      """
    end
  end

  defp siala_grip_block(entry, grip_by_id) do
    statuses =
      grip_by_id |> Map.values() |> Enum.frequencies_by(& &1.status) |> Enum.sort()

    conflicts = Enum.sort(for {id, %{conflict: conflict}} <- grip_by_id, conflict, do: id)

    {:obj,
     [
       {"_note",
        "«#{@siala_weapon_table_page}»'s sortable table states a grip — одноручное / " <>
          "двуручное / двустороннее, sometimes with a second word after a slash for how " <>
          "it is delivered (метательное \"thrown\", стрелковое \"fired\") — for 38 of the " <>
          "47 weapons, but ONLY for a character of the usual (medium) size. This is a " <>
          "DIFFERENT fact from `_grip` above: that block is the general vanilla RULE (grip " <>
          "as a function of weapon size against wielder size, with no per-weapon column " <>
          "because a fixed one would be wrong for a gnome or a halfling); this block is " <>
          "what Siala's own page states outright for the common case, as a value rather " <>
          "than a rule. The delivery half of a compound cell (`двуручное/метательное` and " <>
          "the like) is kept verbatim in `siala_grip_raw` but NOT split into a field of its " <>
          "own: it is exactly the `ranged`/`thrown` pair every weapon already carries — " <>
          "checked over all 38 rows by `verify_grip_delivery!/2` (метательное ⇔ ranged and " <>
          "thrown both true, стрелковое ⇔ ranged true and thrown false, no slash at all ⇔ " <>
          "ranged false) — so a second field would only repeat it, and the build fails if it " <>
          "ever stops agreeing. `siala_grip_status` is `assumed` where the Russian row name " <>
          "→ our id correspondence is ours, the same convention as `siala_proficiency_group_status`; " <>
          "nine rows are `verified` instead because the same page glosses the English name " <>
          "outright elsewhere on it (§Двуручное оружие, §Комбинированное оружие) — see each " <>
          "weapon's `siala_grip_note`. `null` means the weapon is not on the table at all: a " <>
          "finding (creature items, the club, the lance, the magic staff, the unarmed " <>
          "strike — see `siala_grip_note`), not a gap to fill by resemblance. " <>
          "#{length(conflicts)} row#{if length(conflicts) == 1, do: "", else: "s"} — " <>
          "#{inspect(conflicts)} — disagree with the matching «Владение …» feat page; each " <>
          "carries `status: \"conflict\"` and both readings in `conflicts`, per CLAUDE.md §3 " <>
          "(a contradiction between two Siala pages is a finding, not a tie to break)."},
       # ⚠ «Обычный размер» вынесен ПОЛЕМ (задача 3.43), а не оставлен прозой
       # в `_note`: ядро обязано знать, для какого владельца эта колонка верна,
       # чтобы всем остальным пересчитать хват по размерам, — и `medium`
       # в коде ядра было бы именем размера, то есть игровым словом.
       {"stated_for_size", @siala_grip_stated_for_size},
       # 🔴 ЗАМЕР Dan 16.08.2026 (`GAME_CHECKS.md`, кейс R5). Колонка называет
       # дротики и сюрикены «двуручное/метательное», и до замера ядро читало
       # первое слово как «занимает вторую руку» — то есть отбирало щит
       # у каждого метателя, на ОБОИХ ruleset'ах. В игре щит остаётся.
       #
       # ⚠️ Значит «двуручное» у метательного описывает БРОСОК, а не занятую
       # руку. Правило записано свойством оружия (`thrown`), а не списком
       # из двух id: у Сиалы метательных четыре, и два из них колонка и так
       # зовёт одноручными — то есть после правки все четыре ведут себя
       # одинаково, а исключением остаётся ровно то, что измерено.
       #
       # ⚠️ Стрелковое (`стрелковое` — луки и арбалеты) под это НЕ подпадает
       # и остаётся двуручным: там «двуручное» и означает две руки, и без
       # колонки короткий лук с арбалетом стали бы одноручными по размеру.
       {"both_hands_excludes_when", @siala_grip_off_hand_free_when},
       {"source", siala_source(entry)},
       {"status_counts",
        {:obj, for({status, count} <- statuses, do: {status || "absent", count})}},
       {"conflicts_with_proficiency_pages", conflicts},
       {"cross_checked_against",
        {:obj,
         [
           {"pages",
            @siala_weapon_group_feats |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.sort()},
           {"note",
            "The same 38 grip values, read a second time off the five «Владение …» feat " <>
              "pages `collect_siala_feats/1` already parses, matched weapon-by-weapon and " <>
              "compared by `weapon_grip_lookup!/3` (via `grip_from_proficiency_feats!/2`'s " <>
              "lookup). The build still fails on a STRUCTURAL surprise (a page gone, or the " <>
              "two sources naming a different total count of weapons); a per-weapon VALUE " <>
              "disagreement becomes a `conflict` instead — see `conflicts_with_proficiency_pages`."}
         ]}}
     ]}
  end

  # Both halves of the count check, and the second is the point: Siala's own
  # pages say how many weapons each group holds, so an assignment table that has
  # drifted from them stops the build instead of quietly regrouping a weapon.
  defp weapon_groups!(ids, siala, memberships) do
    case Enum.sort(ids) -- Enum.sort(Map.keys(@siala_weapon_groups)) do
      [] -> :ok
      new -> raise "weapons: #{inspect(new)} has no Siala proficiency group assigned"
    end

    case Enum.sort(Map.keys(@siala_weapon_groups)) -- Enum.sort(ids) do
      [] -> :ok
      gone -> raise "weapons: #{inspect(gone)} is assigned a group but is no longer a weapon"
    end

    assigned =
      @siala_weapon_groups
      |> Map.values()
      |> Enum.frequencies_by(fn {group, _status, _why} -> group end)

    listed = siala_group_sizes(siala)

    for {group, feat} <- @siala_weapon_group_feats, not is_nil(feat) do
      ours = Map.get(assigned, group, 0)
      theirs = Map.fetch!(listed, feat)

      unless ours == theirs do
        raise """
        weapons: Siala's `#{feat}` unlocks #{theirs} weapons, but #{ours} are assigned to \
        `#{group}`. The two taxonomies have drifted — read both sides rather than nudging \
        one to fit (CLAUDE.md §3).
        """
      end
    end

    weapon_ids = MapSet.new(ids)

    group_blocks =
      for {group, feat} <- Enum.sort(@siala_weapon_group_feats) do
        category = Map.fetch!(@fandom_grouping_categories, group)

        {group,
         {:obj,
          [
            {"siala_feat", feat},
            {"weapons_assigned", Map.get(assigned, group, 0)},
            {"weapons_siala_lists", feat && Map.fetch!(listed, feat)},
            {"fandom_category", category},
            {"weapons_in_fandom_category",
             category && fandom_group_size(category, memberships, weapon_ids)}
          ]}}
      end

    unassigned = for {id, {nil, _status, _why}} <- Enum.sort(@siala_weapon_groups), do: id

    %{
      assigned: assigned,
      listed: listed,
      json:
        {:obj,
         [
           {"_note",
            "Таксономия ПЯТИ КАТЕГОРИЙ — сиальская, и Fandom на неё не отвечает " <>
              "по построению: Сиала заменила ванильную систему владения оружием целиком. " <>
              "Статус стоит у каждой записи (поле siala_proficiency_group_status). " <>
              "⚠️ Группу Сиала называет САМА, и дважды: пятью страницами фитов владения " <>
              "и колонкой «Тип оружия» сводной таблицы страницы «Система оружия» — " <>
              "38 строк, расхождений с нашим назначением ноль. Нашим был только ПЕРЕВОД " <>
              "ИМЕНИ («Полуторные мечи» = Bastard sword), и 16.08.2026 его сверил Dan " <>
              "(«Я глянул, вроде перевод подходит»), после чего 30 записей перешли " <>
              "из assumed в verified. verified приходит двумя маршрутами разного " <>
              "качества: ranged (8) — категория Fandom перечисляет тех же восьмерых, " <>
              "то есть таксономии совпали сами; blade/axe/hammer/polearm (30) и lance — " <>
              "сверка Dan, source kind user, перепроверить по ссылке нельзя. " <>
              "null — Сиала не называет оружие ни в одной из пяти категорий; сегодня " <>
              "это ровно пять атак существ, и это находка, а не пустое место."},
           # ⚠️ Остаётся `true` и после сверки Dan: поле отвечает на «кто это соответствие
           # СОСТАВИЛ», а не «проверено ли оно». Составили мы; подтвердил игрок.
           # Поставить сюда false значило бы стереть происхождение — статус записи
           # и так говорит, что факт подтверждён.
           {"taxonomy_correspondence_is_ours", true},
           {"groups", {:obj, group_blocks}},
           {"unassigned", unassigned}
         ]}
    }
  end

  # How many weapons Fandom files under a category, subcategories included and
  # overview articles excluded — the same "is it a weapon" test the dictionary
  # itself uses, so the two counts are counting the same kind of thing.
  defp fandom_group_size(category, memberships, weapon_ids) do
    members = Map.fetch!(memberships, category)

    direct = for m <- members, m["ns"] == 0, id(m["title"]) in weapon_ids, do: id(m["title"])

    nested =
      for m <- members,
          m["ns"] == 14,
          Map.has_key?(memberships, m["title"]),
          nested_id <- fandom_group_ids(m["title"], memberships, weapon_ids),
          do: nested_id

    (direct ++ nested) |> Enum.uniq() |> length()
  end

  defp fandom_group_ids(category, memberships, weapon_ids) do
    for m <- Map.fetch!(memberships, category),
        m["ns"] == 0,
        id(m["title"]) in weapon_ids,
        do: id(m["title"])
  end

  defp siala_group_sizes(siala) do
    for feat <- Map.values(@siala_weapon_group_feats), not is_nil(feat), into: %{} do
      record =
        Enum.find(siala.records, fn record -> record.id == feat end) ||
          raise "weapons: `#{feat}` is not in the Siala feat layer any more"

      steps = record.page.unlocks || []

      if steps == [] do
        raise "weapons: Siala's `#{feat}` no longer unlocks any weapon"
      end

      {feat, Enum.sum(for step <- steps, do: length(step.weapons))}
    end
  end

  defp weapon_record(entry, weapon, selectable?, of_choice?, size_row, siala_group, siala_grip) do
    {group, group_status, group_note} = siala_group

    size_conflict =
      case size_row do
        %{size: table_size} when table_size != weapon.size -> table_size
        _agrees_or_absent -> nil
      end

    conflicts =
      WeaponPage.conflicts(weapon) ++
        if(size_conflict,
          do: [
            %{
              field: "size",
              from_parameter: weapon.size,
              from_categories: size_conflict,
              parameter_raw: weapon.size_raw
            }
          ],
          else: []
        ) ++
        if(siala_grip.conflict, do: [siala_grip.conflict], else: [])

    {:obj,
     [
       {"id", id(entry.title)},
       {"name", entry.title},
       {@domain_gate, selectable?},
       {"weapon_of_choice", of_choice?},
       {"siala_proficiency_group", group},
       {"siala_proficiency_group_status", group_status},
       {"siala_proficiency_group_note", group_note},
       {"siala_grip", siala_grip.grip},
       {"siala_grip_raw", siala_grip.raw},
       {"siala_grip_status", siala_grip.status},
       {"siala_grip_note", siala_grip.note},
       {"proficiency_category", weapon.proficiency_category},
       {"proficiency_required", weapon.proficiency_required},
       {"proficiency", weapon.proficiency},
       {"proficiency_raw", weapon.proficiency_raw},
       {"size", weapon.size},
       {"size_raw", weapon.size_raw},
       {"size_from_table", size_row && size_row.size},
       {"ranged", weapon.ranged},
       {"thrown", weapon.thrown},
       {"double_sided", weapon.double_sided},
       {"damage",
        weapon.damage && {:obj, [{"count", weapon.damage.count}, {"faces", weapon.damage.faces}]}},
       {"damage_raw", weapon.damage_raw},
       {"threat_range_low", weapon.threat_range_low},
       {"threat_range_high", weapon.threat_range_high},
       {"critical_multiplier", weapon.critical_multiplier},
       {"critical_raw", weapon.critical_raw},
       {"damage_types", weapon.damage_types},
       {"damage_type_raw", weapon.damage_type_raw},
       {"categories", weapon.categories},
       {"conflicts", Enum.map(conflicts, &weapon_conflict_json/1)},
       {"status", if(conflicts == [], do: "parsed", else: "conflict")},
       {"source", source(entry)}
     ]}
  end

  defp report_weapons(weapons) do
    Mix.shell().info(
      "[weapons] #{length(weapons.records)} entries, #{length(weapons.selectable)} selectable, " <>
        "#{length(weapons.of_choice)} allowed to Weapon of choice -> #{@output_dir}/weapons.json"
    )

    statuses =
      @siala_weapon_groups
      |> Map.values()
      |> Enum.frequencies_by(fn {_group, status, _why} -> status end)
      |> Enum.sort()

    Mix.shell().info(
      "[weapons] Siala proficiency groups: " <>
        Enum.map_join(statuses, ", ", fn {status, count} -> "#{count} #{status}" end)
    )

    for {group, feat} <- Enum.sort(@siala_weapon_group_feats), not is_nil(feat) do
      Mix.shell().info(
        "[weapons]   #{String.pad_trailing(group, 24)} #{Map.get(weapons.groups.assigned, group, 0)} assigned, " <>
          "#{Map.fetch!(weapons.groups.listed, feat)} listed by #{feat}"
      )
    end

    for conflict <- weapons.conflicts do
      Mix.shell().info(
        "[weapons]   conflict on #{conflict.id}: #{conflict.field} — parameter says " <>
          "#{inspect(conflict.from_parameter)}, categories say #{inspect(conflict.from_categories)}"
      )
    end

    grip_statuses =
      weapons.grip.by_id |> Map.values() |> Enum.frequencies_by(& &1.status) |> Enum.sort()

    grip_conflicts =
      for {id, %{conflict: conflict}} <- weapons.grip.by_id, conflict, do: {id, conflict}

    Mix.shell().info(
      "[weapons] Siala grip (`#{@siala_weapon_table_page}`, revid #{weapons.grip.entry.revid}, " <>
        "38/47 named): " <>
        Enum.map_join(grip_statuses, ", ", fn {status, count} ->
          "#{count} #{status || "absent"}"
        end) <>
        " — checked against `ranged`/`thrown` with no disagreement (verify_grip_delivery!/2)"
    )

    for {id, conflict} <- Enum.sort_by(grip_conflicts, &elem(&1, 0)) do
      Mix.shell().info(
        "[weapons]   grip conflict on #{id}: `#{@siala_weapon_table_page}` says " <>
          "#{inspect(conflict.from_parameter)}, the matching «Владение …» page says " <>
          "#{inspect(conflict.from_categories)} — both kept, neither chosen"
      )
    end
  end

  defp weapon_conflict_json(conflict) do
    {:obj,
     [
       {"field", conflict.field},
       {"from_parameter", conflict.from_parameter},
       {"from_categories", conflict.from_categories},
       {"parameter_raw", conflict.parameter_raw},
       {"note", Map.get(conflict, :note)}
     ]}
  end

  defp collect_energy_types(pages, _memberships) do
    # No category and no page per type: the set exists only as a sentence, on two
    # pages, and both list the same five. Neither is dressed up as a list, which
    # is exactly why they are read as links rather than as prose.
    {resist_entry, resist_text} = page!(pages, "Resist energy")
    {epic_entry, epic_text} = page!(pages, "Epic energy resistance")

    resist_note = sentence!(resist_text, "The choices for types of energy are")
    epic_desc = sentence!(epic_text, "The character gains [[damage resistance|resistance]] 10")

    from_resist = energy_ids(resist_note)
    from_epic = energy_ids(epic_desc)

    unless from_resist == from_epic and from_resist != [] do
      raise """
      the two pages naming the types of energy no longer agree:
        Resist energy          #{inspect(from_resist)}
        Epic energy resistance #{inspect(from_epic)}
      Both feats choose from one set; picking a favourite is not this task's call.
      """
    end

    records =
      for type <- from_resist do
        {:obj,
         [
           {"id", type},
           {"name", String.capitalize(type)},
           {"source", source(resist_entry)}
         ]}
      end

    %{
      records: records,
      rule:
        {:obj,
         [
           {"feat", "epic_energy_resistance"},
           {"gate", nil},
           {"available", length(from_resist)},
           {"total", length(from_resist)},
           {"excluded", []},
           {"quote", resist_note},
           {"source", source(resist_entry)},
           {"corroborated_by", {:obj, [{"quote", epic_desc}, {"source", source(epic_entry)}]}}
         ]}
    }
  end

  defp energy_ids(text),
    do: @energy_choice |> Regex.scan(text) |> Enum.map(&List.last/1) |> Enum.sort()

  # The category's own membership, cross-checked against the pages we hold. The
  # index says which categories a *downloaded* page belongs to; the snapshot says
  # what the category itself reports. A member we never downloaded is invisible to
  # the first and obvious to the second.
  defp category_instances(pages, memberships, category) do
    %{instances: instances, filed: filed} = CategoryMembers.split(pages, category)

    declared =
      memberships
      |> Map.get(category, [])
      |> Enum.filter(&(&1["ns"] == 0))
      |> Enum.map(& &1["title"])
      |> Enum.sort()

    held = Enum.map(instances ++ filed, fn {entry, _text} -> entry.title end) |> Enum.sort()

    unless declared == held do
      raise """
      #{category}: the category snapshot and the page cache disagree about who belongs.
        only in #{Cache.dir(@wiki)}/_categories.json: #{inspect(declared -- held)}
        only in the downloaded pages:                 #{inspect(held -- declared)}
      Run `mix wiki.fetch --categories-only` if the snapshot is merely older than the pages.
      """
    end

    for {entry, _text} <- instances, not Regex.match?(~r/^[a-z0-9_]+$/, id(entry.title)) do
      raise "#{category}: #{entry.title} does not reduce to an ASCII id (#{id(entry.title)})"
    end

    instances
  end

  defp verify_count!(label, category, counted, stated, stated_by) do
    unless counted == stated do
      raise """
      #{label}: #{category} has #{counted} instances, but `#{stated_by}` says #{stated}.
      One of the two changed. Padding the list to fit the number, or trusting the \
      number over the list, both invent data — read both pages (CLAUDE.md §3).
      """
    end
  end

  defp verify_excluded!(label, excluded, ids, available, total) do
    case excluded -- ids do
      [] -> :ok
      unknown -> raise "#{label}: excluded #{inspect(unknown)} is not in the list #{inspect(ids)}"
    end

    unless available == total - length(excluded) do
      raise """
      #{label}: #{available} selectable + #{length(excluded)} excluded does not make #{total}
      """
    end
  end

  # A page that is excluded says why on its own page, and that sentence is worth
  # more than the flag: it is the difference between "false" and "false, because
  # Hordes of the Underdark added this type after the feat's list was fixed".
  defp note_pair(true, _text, _anchor), do: []

  defp note_pair(false, text, anchor) do
    case Wikitext.sentence_with(text, anchor) do
      {:ok, sentence} -> [{"note", sentence}]
      :error -> []
    end
  end

  defp sentence!(text, anchor) do
    case Wikitext.sentence_with(text, anchor) do
      {:ok, sentence} ->
        sentence

      :error ->
        raise ~s(the phrase "#{anchor}" is no longer on the page it was quoted from)
    end
  end

  defp page!(pages, title) do
    case Enum.find(pages, fn {entry, _text} -> entry.title == title end) do
      nil -> raise "`#{title}` is not in the cache, and a dictionary is checked against it"
      found -> found
    end
  end

  defp flat(text), do: String.replace(text, ~r/\s+/u, " ")

  # ⚠️ `extra` blocks must never be JSON **lists**. `Loader.domain_entries/1`
  # finds a dictionary's values by looking for the one list-valued key at the top
  # level, so a second one would make the file ambiguous and the domain resolve
  # to nothing at all.
  defp write_dictionary(file, key, %{records: records, rule: rule}, note, extra \\ []) do
    for {name, value} <- extra, is_list(value) do
      raise "#{file}: top-level block #{name} is a list, which would hide #{key} from the loader"
    end

    write_json(
      file,
      {:obj,
       [
         {"_layer", "vanilla"},
         {"_generated_by", "mix wiki.parse"},
         {"_note", note},
         {"_chosen_by", rule}
       ] ++ extra ++ [{key, records}]}
    )
  end

  defp write(file, %{records: records}) do
    write_json(file, Enum.map(records, & &1.json))
  end

  defp write_json(file, json) do
    path = Path.join([File.cwd!(), @output_dir, file])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Json.encode!(json))
  end

  defp report(label, %{records: records, problems: problems}, scanned) do
    duplicates =
      records
      |> Enum.group_by(& &1.id, & &1.title)
      |> Enum.filter(fn {_id, titles} -> length(titles) > 1 end)

    Mix.shell().info(
      "[#{label}] #{length(records)} records from #{scanned} pages " <>
        "-> #{@output_dir}/#{label}.json"
    )

    for {title, reason} <- problems do
      Mix.shell().error("[#{label}] unread on #{title}: #{reason}")
    end

    for {id, titles} <- duplicates do
      Mix.shell().error("[#{label}] duplicate id #{id}: #{Enum.join(titles, ", ")}")
    end
  end

  defp report_classes(%{records: records, skipped: skipped}) do
    prestige = Enum.count(records, &(&1.parsed.requirements_raw != nil))
    primary_ability = Enum.count(records, &(&1.parsed.primary_ability_raw != nil))

    Mix.shell().info("[classes] #{prestige} of #{length(records)} have requirements")

    Mix.shell().info(
      "[classes] #{primary_ability} of #{length(records)} name a primary ability " <>
        "(read out of Spellcasting: — the seven that cast spells at all)"
    )

    Mix.shell().info("[classes] no progression table, not a class: #{Enum.join(skipped, ", ")}")

    for record <- records, record.parsed.conflicts != [] do
      Mix.shell().error(
        "[classes] conflict: #{record.title} — #{Enum.join(record.parsed.conflicts, "; ")}"
      )
    end
  end

  # What the schema could not carry is the part of this that matters: a class
  # with partly-read requirements is checked on what was read and stays silent
  # about the rest, so the rest has to be visible here and in `requirements`
  # itself (where the loader turns it into a `{:missing_data, {:requirement, …}}`
  # gap).
  defp report_requirements(%{records: records}) do
    prestige = Enum.filter(records, &(&1.parsed.requirements_raw != nil))
    structured = Enum.filter(prestige, &(&1.requirements != nil))

    Mix.shell().info(
      "[classes] #{length(structured)} of #{length(prestige)} requirement blocks read into " <>
        "structure; #{Enum.count(structured, &(&1.requirements_parsed.unparsed == []))} of those " <>
        "with nothing left over"
    )

    for record <- prestige, record.requirements == nil do
      Mix.shell().error("[classes] requirements not read at all: #{record.title}")
    end

    for record <- prestige, fragment <- record.requirements_parsed.unparsed do
      Mix.shell().info("[classes] #{record.id}: not carried by the schema: #{fragment}")
    end

    for record <- prestige,
        {"qualifiers", phrases} <- record.requirements_parsed.requirements,
        phrase <- phrases do
      Mix.shell().info("[classes] #{record.id}: read with a qualifier: #{phrase}")
    end

    for record <- prestige, note <- record.requirements_parsed.notes do
      Mix.shell().info("[classes] #{record.id}: ignored aside: #{one_line(note)}")
    end

    for record <- records, problem <- record.requirements_parsed.problems do
      Mix.shell().error("[classes] #{record.id}: #{problem}")
    end
  end

  # The feats column of the progression table, and above all what was *not* read
  # out of it: a slot mistaken for a grant hands out a feat that does not exist,
  # and a grant mistaken for a slot makes the calculator demand a feat the
  # character already owns. Both halves are printed so a human can check the
  # split without opening 23 pages.
  defp report_granted_feats(%{records: records}) do
    granting = Enum.filter(records, &(&1.granted_feats != []))
    total = Enum.sum(for r <- granting, {_level, ids} <- r.granted_feats, do: length(ids))
    levels = Enum.sum(for r <- granting, do: length(r.granted_feats))

    Mix.shell().info(
      "[classes] #{length(granting)} of #{length(records)} hand feats out for free: " <>
        "#{total} grants over #{levels} class levels"
    )

    report_granted_feat_ranks(records)

    for record <- records, {level, target} <- record.granted_unmatched do
      Mix.shell().error(
        "[classes] #{record.id} level #{level}: granted feat has no page in feats.json: #{target}"
      )
    end

    for {text, where} <- fragment_index(records, & &1.parsed.feat_grants.slots) do
      Mix.shell().info("[classes] read as a bonus feat slot, not a grant: #{text} (#{where})")
    end

    for {text, where} <- fragment_index(records, & &1.parsed.feat_grants.prose) do
      Mix.shell().info("[classes] not read as a grant, no feat linked: #{text} (#{where})")
    end
  end

  # The other side of the same coin: what a class's level will **not** let the
  # player pick. Printed per class as well as in total, because the count is the
  # only cheap check that a page's list was read whole — a comma swallowed by a
  # line break shortens the list without breaking anything.
  defp report_unavailable_feats(%{records: records}) do
    restricting = Enum.filter(records, &(&1.unavailable_feats != []))
    pairs = Enum.sum(for r <- restricting, do: length(r.unavailable_feats))
    distinct = for r <- restricting, feat <- r.unavailable_feats, uniq: true, do: feat

    Mix.shell().info(
      "[classes] #{length(restricting)} of #{length(records)} take feats off the general list: " <>
        "#{pairs} pairs, #{length(distinct)} distinct feats"
    )

    for record <- restricting do
      Mix.shell().info(
        "[classes] #{record.id} cannot pick — #{Enum.join(record.unavailable_feats, ", ")}"
      )
    end
  end

  # What `proficiency_grants/3` resolved for each class, off its own label and
  # the same feats' `granted_by` — printed the same shape as
  # `report_unavailable_feats/1`, its mirror image on the general list.
  #
  # `pairs`/`distinct` count only what resolved to a feat id — `grants.ids`
  # decides, the same lookup `granted_feats/2` is about to apply to this exact
  # list. A target that resolves nowhere (`armor`, twice) is real data and
  # stays in the per-class line below, but it is not a proficiency *feat*, and
  # counting it as one would overstate the id total by one. It is not lost
  # either way: it goes through the very same `granted_feats/2` call as
  # everything else here and lands in the very same `granted_feats_unread`,
  # which `report_granted_feats/1` already prints.
  defp report_proficiency_grants(proficiencies, grants) do
    granting = for {id, list} <- proficiencies, list != [], into: %{}, do: {id, list}
    targets = for {_id, list} <- granting, {_level, target, _shown, _tail} <- list, do: target
    resolved = Enum.filter(targets, &Map.has_key?(grants.ids, id(&1)))
    distinct = resolved |> Enum.map(&Map.fetch!(grants.ids, id(&1))) |> Enum.uniq()
    unresolved = length(targets) - length(resolved)

    Mix.shell().info(
      "[classes] #{map_size(granting)} of #{map_size(proficiencies)} start with a proficiency " <>
        "off their own label or the feat's `classN`: #{length(resolved)} pairs, " <>
        "#{length(distinct)} distinct feats" <>
        if(unresolved > 0, do: ", #{unresolved} left unmatched (see below)", else: "")
    )

    for {class_id, list} <- Enum.sort_by(granting, fn {id, _} -> id end) do
      names = list |> Enum.map(fn {_level, target, _shown, _tail} -> target end) |> Enum.sort()
      Mix.shell().info("[classes] #{class_id} proficiencies — #{Enum.join(names, ", ")}")
    end
  end

  # Every rank read, in full: there are only a couple of dozen, they are the one
  # place a caption is copied out of prose rather than out of a field, and the
  # grants they belong to are exactly the ones a reader cannot check by the feat
  # id alone.
  defp report_granted_feat_ranks(records) do
    labelled = Enum.filter(records, &(&1.granted_feat_ranks != []))

    total =
      Enum.sum(
        for r <- labelled, {_level, {:obj, pairs}} <- r.granted_feat_ranks, do: length(pairs)
      )

    Mix.shell().info(
      "[classes] #{total} grants over #{length(labelled)} classes carry a rank the page wrote down"
    )

    for record <- labelled do
      ranks =
        for {level, {:obj, pairs}} <- record.granted_feat_ranks,
            {feat, rank} <- pairs,
            do: "#{level}: #{feat} #{rank}"

      Mix.shell().info("[classes] #{record.id} ranks — #{Enum.join(ranks, ", ")}")
    end
  end

  # `bonus feat` alone stands at 136 class levels, so a long list is cut short:
  # what the reader is checking is the wording, and the first few places it
  # appears are enough to go and look.
  @report_places 8

  defp fragment_index(records, get) do
    for record <- records, {level, text} <- get.(record) do
      {one_line(text), "#{record.id} #{level}"}
    end
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort()
    |> Enum.map(fn {text, where} -> {text, places(where)} end)
  end

  defp places(where) when length(where) <= @report_places, do: Enum.join(where, ", ")

  defp places(where) do
    {shown, rest} = Enum.split(where, @report_places)
    Enum.join(shown, ", ") <> " and #{length(rest)} more"
  end

  # The whole `type` vocabulary with its counts. The list of choosable feats is
  # filtered on this field, so a value nobody has seen is a filter nobody wrote:
  # printing all of them makes a new one arrive as news rather than as a feat
  # that quietly stopped appearing.
  defp report_feat_types(%{records: records}) do
    counts =
      records
      |> Enum.frequencies_by(fn record -> feat_type(record.params["type"]) end)
      |> Enum.sort_by(fn {type, count} -> {-count, to_string(type)} end)
      |> Enum.map_join(", ", fn {type, count} -> "#{inspect(type)} ×#{count}" end)

    Mix.shell().info("[feats] type vocabulary: #{counts}")
  end

  # The three-way split `AGENT_QUEUE.md` §1.6 asked for by hand, printed so the
  # next re-fetch shows it without anyone re-running that count: a page in
  # `named` already has its class restriction expressed some other way and
  # needs nobody's attention; `unparsed_only` refuses every class already, on a
  # fragment that has nothing to do with this category; `bare` is the list
  # `vanilla/feat_requirements.json` is checked against a human reading of.
  defp report_feat_restrictions(%{records: records}) do
    flagged = Enum.filter(records, &(record_value(&1, "restricted_by_class_category") == true))

    {bare, rest} = Enum.split_with(flagged, &(&1.prereqs.requirements == []))

    {unparsed_only, named} =
      Enum.split_with(
        rest,
        &(Enum.map(&1.prereqs.requirements, fn {key, _} -> key end) == ["unparsed"])
      )

    Mix.shell().info(
      "[feats] #{length(flagged)} pages carry Category:Feats restricted by class " <>
        "(either name); #{length(named)} already read a class restriction some other way, " <>
        "#{length(unparsed_only)} refuse everyone on an unrelated unread fragment, " <>
        "#{length(bare)} state no prerequisite at all: " <>
        Enum.map_join(Enum.sort_by(bare, & &1.id), ", ", & &1.id)
    )
  end

  # ⚠ This count is of what THIS PARSER read out of `prereq=`, not of what the
  # calculator refuses. Three of the fragments printed below
  # (`[[greater rage]] (4x/6x per day)` on the barbarian's three epic feats) are
  # answered by hand in `vanilla/feat_requirements.json`, where the same pages
  # translate the tier into a class level in their own `Notes` — so the ruleset
  # carries 12 feats with a raw remainder where this report says 15. Both numbers
  # are right about different things; conflating them is what made the three
  # feats look permanently unreachable.
  #
  # ⚠ Which is why the line itself now says "this parser" and names the hand
  # layer, instead of leaving that only here. The comment is read by whoever
  # opens line 2923 of a mix task; the NUMBER is read by whoever runs the task,
  # and then travels into a report or a backlog entry without it. This file has
  # already burned twice on a count printed without its unit (AGENT_QUEUE.md §7,
  # «43 → 29»), and the lesson written down there is exactly this one: a number
  # needs to say not just how it was counted but WHAT was counted.
  defp report_prereqs(%{records: records}) do
    stated = Enum.filter(records, &(&1.params["prereq"] != nil))
    {clean, leftover} = Enum.split_with(stated, &(&1.prereqs.unparsed == []))
    unlocking = Enum.count(records, &(&1.unlocks != []))

    Mix.shell().info(
      "[feats] #{length(stated)} of #{length(records)} state prerequisites; " <>
        "#{length(clean)} read whole, #{length(leftover)} with fragments THIS PARSER " <>
        "cannot read — not the count of what the calculator refuses: some are answered " <>
        "by hand in vanilla/feat_requirements.json, and the ruleset's own count is the " <>
        "one that decides a build; #{unlocking} feats are a prerequisite of another"
    )

    fragments =
      leftover
      |> Enum.flat_map(fn record -> Enum.map(record.prereqs.unparsed, &{&1, record.id}) end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.sort()

    for {fragment, feats} <- fragments do
      Mix.shell().info("[feats] not read by this parser: #{fragment} (#{Enum.join(feats, ", ")})")
    end

    report_qualifiers(records)

    for record <- records, note <- record.prereqs.notes do
      Mix.shell().info("[feats] #{record.id}: #{one_line(note)}")
    end
  end

  # The other half of the same picture: a requirement that *was* read together
  # with the part of it that could not be. Printed phrase by phrase because the
  # list is the closed vocabulary `Requirements` recognises — a phrase that
  # stops appearing here has quietly gone back to being prose.
  defp report_qualifiers(records) do
    phrases =
      records
      |> Enum.flat_map(fn record ->
        for {"qualifiers", list} <- record.prereqs.requirements,
            phrase <- list,
            do: {phrase, record.id}
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.sort()

    Mix.shell().info(
      "[feats] read with a qualifier the schema cannot hold: " <>
        "#{phrases |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq() |> length()} feats"
    )

    for {phrase, feats} <- phrases do
      Mix.shell().info("[feats] qualifier: #{phrase} (#{Enum.join(feats, ", ")})")
    end
  end

  defp one_line(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  # Which fields came back empty is as much a result as the fields that did not:
  # a `null` nobody listed is a hole nobody knows about (CLAUDE.md §3).
  @skill_fields [
    {"key_ability", :key_ability},
    {"trained_only", :trained_only},
    {"cross_class_raw", :cross_class_raw},
    {"classes_raw", :classes_raw},
    {"check_raw", :check_raw},
    {"use_raw", :use_raw},
    {"special_raw", :special_raw},
    {"description", :description}
  ]

  defp report_skills(%{records: records, skipped: skipped, penalised: penalised}) do
    Mix.shell().info("[skills] not a skill (no 'Ability' label): #{Enum.join(skipped, ", ")}")

    case penalised do
      nil ->
        Mix.shell().error(
          "[skills] the armor check penalty sentence no longer parses — " <>
            "every armor_check_penalty is null"
        )

      set ->
        Mix.shell().info("[skills] #{MapSet.size(set)} take an armor check penalty")

        for id <- sorted_difference(set, MapSet.new(records, & &1.id)) do
          Mix.shell().error("[skills] armor check penalty names an unknown skill: #{id}")
        end
    end

    for {name, field} <- @skill_fields,
        missing = Enum.filter(records, &is_nil(Map.fetch!(&1.parsed, field))),
        missing != [] do
      Mix.shell().info(
        "[skills] #{name} is null on #{length(missing)}: " <>
          Enum.map_join(missing, ", ", & &1.title)
      )
    end

    for record <- records, record.conflicts != [] do
      Mix.shell().error(
        "[skills] conflict: #{record.title} — #{Enum.join(record.conflicts, "; ")}"
      )
    end

    # "Cross-class: no" is the wiki's way of writing "exclusive", and on three
    # skills `Category:Exclusive skills` says so too. Where only one of the two
    # says it, the label stays raw and unread rather than being turned into a
    # rule about who may buy the skill.
    for record <- records,
        record.parsed.cross_class_raw == "no",
        not record.exclusive? do
      Mix.shell().error(
        "[skills] says 'cross-class: no' but is not in Category:Exclusive skills: #{record.title}"
      )
    end
  end

  # Two independent lists of the same fact: each class page names its skills and
  # each skill page names its classes. Every disagreement is printed *and*
  # written into `class_skills_conflict`; which side wins is argued once, at
  # `class_skills/3`.
  defp report_skill_classes(skills, classes) do
    skill_ids = MapSet.new(skills.records, & &1.id)
    class_ids = MapSet.new(classes.records, & &1.id)

    listed_by =
      for record <- classes.records,
          target <- Wikitext.link_targets(record.parsed.class_skills_raw || ""),
          reduce: %{} do
        acc -> Map.update(acc, id(target), [record.id], &[record.id | &1])
      end

    mentioned = MapSet.new(Map.keys(listed_by))

    for id <- sorted_difference(mentioned, skill_ids) do
      Mix.shell().error("[skills] a class lists a skill that has no page of its own: #{id}")
    end

    for id <- sorted_difference(skill_ids, mentioned) do
      Mix.shell().error("[skills] no class lists this skill among its class skills: #{id}")
    end

    for record <- skills.records,
        id <- sorted_difference(MapSet.new(record.parsed.classes, &id/1), class_ids) do
      Mix.shell().error("[skills] #{record.title} names an unknown class: #{id}")
    end

    conflicts =
      for record <- classes.records, {skill, stated_by} <- record.conflicts do
        "#{record.id}/#{skill} (only the #{String.replace(stated_by, "_", " ")} says so)"
      end

    Mix.shell().info(
      "[skills] #{length(conflicts)} class-skill disagreements, all resolved as class skills " <>
        "and kept in class_skills_conflict: #{Enum.join(conflicts, ", ")}"
    )
  end

  defp report_spell_slots(%{records: records}) do
    for group <- [:spells_per_day, :spells_known] do
      classes =
        Enum.filter(records, fn record ->
          Enum.any?(record.parsed.progression, &Map.fetch!(&1, group))
        end)

      Mix.shell().info(
        "[classes] #{group}: #{length(classes)} — " <> Enum.map_join(classes, ", ", & &1.id)
      )
    end

    leftovers =
      for record <- records,
          row <- record.parsed.progression,
          {name, value} <- row.extra,
          String.contains?(String.downcase(name), "spell"),
          do: "#{record.id} #{row.level} #{name}=#{inspect(value)}"

    for leftover <- Enum.sort(leftovers) do
      Mix.shell().error("[classes] spell column left in extra: #{leftover}")
    end
  end

  defp report_epic(%{problems: problems}) do
    Mix.shell().info("[epic] rules from #{length(EpicRules.pages())} character-level pages")

    for problem <- problems do
      Mix.shell().error("[epic] #{problem}")
    end
  end

  # ── Siala: priv/rules/siala_41/generated/ ───────────────────────────────────

  @siala_output_dir "priv/rules/siala_41/generated"
  @siala_manual_dir "priv/rules/siala_41"
  @siala_feat_category "Категория:Фиты"
  @siala_class_category "Категория:Классы"

  # Russian class names the feat pages use in prose but that are not the title of
  # any class page and not in the hand layer's `ru` field, so nothing else can
  # resolve them. Six pages depend on the first one.
  @siala_class_aliases %{
    "рыцарь пурпурного дракона" => "purple_dragon_knight",
    "плут" => "rogue"
  }

  # Ids that cannot be derived from the page title, for two different reasons.
  #
  # The six Russian-titled pages are Siala-only: the shard publishes no English
  # name for them anywhere, so these ids are **ours**, chosen once and kept stable.
  # `name` stays `null` on those records rather than carrying a translation nobody
  # can check (CLAUDE.md §4: do not transliterate on a hunch).
  #
  # The last one is a typo in the source: `Сold` on the wiki starts with a Cyrillic
  # `С`. Letting that into an identifier would produce an id no code could ever
  # type; the element is spelled out in full in the page's own text.
  @siala_ids %{
    "Владение клинковым оружием" => "siala_blade_proficiency",
    "Владение древковым оружием" => "siala_polearm_proficiency",
    "Владение молотами" => "siala_hammer_proficiency",
    "Владение топорами" => "siala_axe_proficiency",
    "Владение оружием дальнего боя" => "siala_ranged_proficiency",
    "Фокусировки на школы магии" => "siala_spell_school_focus",
    "Epic energy resistance (Сold)" => "epic_energy_resistance_cold"
  }

  defp collect_siala_feats(vanilla) do
    index = Cache.read_index!(@siala_wiki)

    pages =
      for entry <- index,
          @siala_feat_category in entry.categories,
          do: {entry, Cache.read_page!(@siala_wiki, entry)}

    lookup = siala_lookup(index, vanilla)
    aliases = name_map_by_russian()
    names = Map.new(vanilla.feats.records, &{&1.id, &1.title})
    descriptions = Map.new(vanilla.feats.records, &{&1.id, &1.params["desc"]})

    parsed =
      for {entry, wikitext} <- pages do
        page = SialaFeatPage.parse(wikitext, lookup)

        {vanilla_ids, matched_by} =
          match_vanilla(entry, page, aliases, MapSet.new(Map.keys(names)), "_feat")

        %{entry: entry, page: page, vanilla_ids: vanilla_ids, matched_by: matched_by}
      end

    # A vanilla feat that several Siala pages describe (one `Epic energy
    # resistance` page per element) cannot lend its id to all of them, so in that
    # case every one of them keeps an id of its own and only `vanilla_id` is shared.
    shared =
      parsed
      |> Enum.flat_map(& &1.vanilla_ids)
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> MapSet.new(fn {id, _count} -> id end)

    records =
      for record <- parsed do
        siala_record(record, shared, names, descriptions)
      end

    verify_feat_fact_affects!(records)

    %{records: Enum.sort_by(records, & &1.id), scanned: length(pages)}
  end

  # Class names, normalised the way `SialaFeatPage` normalises them: the English
  # names from the vanilla snapshot, the Russian names from the hand-written
  # `siala_41/classes.json` (the reviewed source of that mapping), plus the two
  # aliases above. Reading the hand layer here is the only direction that is safe —
  # this task never writes to it.
  defp siala_lookup(index, vanilla) do
    english =
      for record <- vanilla.classes.records, into: %{}, do: {siala_fold(record.title), record.id}

    russian = siala_manual_class_names()

    titles =
      for entry <- index,
          @siala_class_category in entry.categories,
          id = Map.get(russian, siala_fold(entry.title)),
          into: %{},
          do: {siala_fold(entry.title), id}

    %{
      classes:
        english |> Map.merge(russian) |> Map.merge(titles) |> Map.merge(@siala_class_aliases),
      class_ids: MapSet.new(vanilla.classes.records, & &1.id),
      skill_ids: MapSet.new(vanilla.skills.records, & &1.id),
      feat_ids: MapSet.new(vanilla.feats.records, & &1.id),
      race_ids: MapSet.new(vanilla.races.records, & &1.id)
    }
  end

  defp siala_manual_class_names do
    path = Path.join([File.cwd!(), @siala_manual_dir, "classes.json"])

    if File.exists?(path) do
      %{"classes" => classes} = path |> File.read!() |> Jason.decode!()

      for class <- classes,
          id = class["vanilla_id"] || class["id"],
          into: %{},
          do: {siala_fold(class["ru"]), id}
    else
      Mix.shell().error(
        "[siala] #{@siala_manual_dir}/classes.json is missing — Russian class names will not resolve"
      )

      %{}
    end
  end

  # `priv/rules/name_map.json` is EN -> RU; here it is needed the other way, and a
  # Russian page can stand for more than one English feat (`Разоружение` is both
  # `Disarm` and `Improved disarm`). Sorted so the primary id never depends on map
  # iteration order.
  defp name_map_by_russian do
    path = Path.join([File.cwd!(), "priv/rules/name_map.json"])

    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> Enum.group_by(fn {_en, ru} -> ru end, fn {en, _ru} -> en end)
      |> Map.new(fn {ru, names} -> {ru, Enum.sort(names)} end)
    else
      %{}
    end
  end

  # Three routes onto a vanilla feat, in order of how much they can be trusted:
  # the page title itself (most Siala feat pages are titled in English), the
  # reviewed EN<->RU redirect map, and finally the page's own "in the English wiki"
  # link. Nothing else is tried: guessing from the Russian name is exactly the
  # translation-by-hunch CLAUDE.md §4 forbids.
  defp match_vanilla(entry, page, aliases, vanilla_ids, suffix) do
    routes = [
      {"title", [entry.title]},
      {"name_map", Map.get(aliases, entry.title, [])},
      {"fandom_link", page.fandom_links}
    ]

    Enum.find_value(routes, {[], nil}, fn {route, names} ->
      case names
           |> Enum.flat_map(&vanilla_candidates(&1, suffix))
           |> Enum.filter(&MapSet.member?(vanilla_ids, &1))
           |> Enum.uniq() do
        [] -> nil
        ids -> {ids, route}
      end
    end)
  end

  # `Epic energy resistance (Acid)` is one Fandom page without the element in its
  # title, and `Contagion (Blackguard)` is `Contagion (feat)` there — both are the
  # same disambiguation habit read from the two ends. Fandom disambiguates with
  # the kind of thing the page is about, so the suffix differs per category
  # (`Heal (spell)` there, `Heal (skill)` next to it).
  defp vanilla_candidates(name, suffix) do
    base = String.replace(name, ~r/\s*\([^()]*\)\s*$/u, "")
    Enum.uniq([id(name), id(name) <> suffix, id(base), id(base) <> suffix])
  end

  defp siala_record(
         %{entry: entry, page: page, vanilla_ids: vanilla_ids, matched_by: matched_by},
         shared,
         names,
         descriptions
       ) do
    vanilla_id = List.first(vanilla_ids)
    siala_only? = vanilla_id == nil
    id = siala_id(entry.title, vanilla_id, shared)
    changes = page |> siala_changes(siala_only?) |> tag_feat_fact_affects(id)
    diff = feat_numeric_diff(page, vanilla_id, descriptions)

    json =
      {:obj,
       [
         {"id", id},
         {"ru", entry.title},
         {"name", siala_name(entry.title, vanilla_id, names)},
         {"vanilla_id", vanilla_id},
         {"vanilla_ids", vanilla_ids},
         {"matched_by", matched_by},
         {"siala_only", siala_only?},
         {"describes_feat", describes_feat?(page, vanilla_id)},
         {"type_raw", page.type_raw},
         {"requirements_raw", page.requirements_raw},
         {"use_raw", page.use_raw},
         {"special_raw", page.special_raw},
         {"numbers_differ", diff.differs},
         {"numeric_diff", numeric_diff_json(diff)},
         {"extra_labels", {:obj, page.extra_labels}},
         {"lead_raw", page.lead_raw},
         {"sections", Enum.map(page.sections, &{:obj, [{"title", &1.title}, {"body", &1.body}]})},
         {"changes", Enum.map(changes, &fact_json/1)},
         {"source", siala_source(entry)},
         {"status", "parsed"}
       ]}

    %{
      id: id,
      title: entry.title,
      json: json,
      page: page,
      changes: changes,
      diff: diff,
      vanilla_ids: vanilla_ids,
      siala_only?: siala_only?
    }
  end

  # Шард переписывает не только требования, но и САМУ ВЕЛИЧИНУ эффекта, и число
  # это стоит в прозе «Особенности», а не в поле. Ровно та же беда, что у
  # заклинаний, и лечится тем же способом: сравниваются не тексты (русский
  # против английского — несравнимы), а НАБОРЫ чисел, напечатанных в них.
  # «vanilla: 10, 100 → siala: 15, 150» переживает перевод целиком.
  #
  # Сравнивается ровно лейбл «Особенности» против ванильного `desc` — это
  # прямые аналоги друг друга. Разделы страницы в набор НЕ идут: у пяти
  # `Epic energy resistance` в разделе «Общие» стоит пример сложения с предметом
  # (−15, −30), и он утопил бы саму величину в шуме.
  #
  # ⚠ Это УКАЗАТЕЛЬ, а не вывод (CLAUDE.md §3, урок `numeric_diff` у заклинаний).
  # Машина говорит «числа разошлись, посмотри», решает человек: «Сиала чисел не
  # называет» и «шард поменял число» выглядят отсюда одинаково. Поэтому
  # результат лежит полем записи, а не фактом в `changes`: факт применялся бы
  # загрузчиком, не нашёл бы себе механического дома, уехал бы в
  # `siala_unapplied` и повесил бы на билд второй гэп поверх уже висящего
  # «прибавку фита в статы не считаем».
  defp feat_numeric_diff(page, vanilla_id, descriptions) do
    description = vanilla_id && Map.get(descriptions, vanilla_id)

    # `null`, а не `false`: «сравнивать не с чем» и «сравнили, разницы нет» —
    # разные ответы, и схлопывать их значило бы выдать справку о здоровье,
    # которую никто не подписывал.
    if is_binary(description) and is_binary(page.special_raw) do
      vanilla = SialaSpellPage.numbers(description)
      siala = SialaSpellPage.numbers(page.special_raw)

      %{differs: vanilla != siala, vanilla: vanilla, siala: siala, note: nil}
    else
      %{differs: nil, vanilla: nil, siala: nil, note: nil}
    end
  end

  # Whether the page describes a feat at all — a question `Категория:Фиты` does
  # not answer, because the category also holds pages about a *family*.
  # «Фокусировки на школы магии» is about Spell Focus in all eight schools at
  # once: there is no feat by that name, nothing on the page can be taken, and a
  # list of choices that offers it offers an empty pair of brackets.
  #
  # It is decided by the five things a page here states about a feat, none of
  # which that page states: any of the four bold labels, the numbered unlock list
  # of a weapon proficiency, the «Возможность взятия фита» section, and a match
  # onto a vanilla feat. The five Siala-only weapon proficiencies carry no labels
  # either and are real feats — the unlock list and the taking section are what
  # tell them apart.
  #
  # The record itself stays whatever the answer: its `siala_note` carries the
  # shard's rules on schools of magic, which are wanted whether or not anything
  # can be selected.
  defp describes_feat?(page, vanilla_id) do
    not is_nil(vanilla_id) or
      Enum.any?(
        [page.type_raw, page.requirements_raw, page.use_raw, page.special_raw, page.unlocks],
        &(not is_nil(&1))
      ) or
      not is_nil(page.taking)
  end

  defp siala_id(title, vanilla_id, shared) do
    cond do
      override = Map.get(@siala_ids, title) -> override
      vanilla_id == nil -> id(title)
      MapSet.member?(shared, vanilla_id) -> id(title)
      true -> vanilla_id
    end
  end

  # The English name comes from the vanilla record when there is one, and from the
  # page title when Siala titled the page in English itself. A Russian-titled
  # Siala-only feat has no English name anywhere and gets `null`.
  defp siala_name(_title, vanilla_id, names) when is_binary(vanilla_id),
    do: Map.fetch!(names, vanilla_id)

  defp siala_name(title, nil, _names) do
    if Regex.match?(~r/^[\p{Latin}\p{N}\s()'’.,-]+$/u, title), do: title, else: nil
  end

  defp siala_source(entry) do
    {:obj,
     [
       {"wiki", @siala_wiki},
       {"kind", "wiki"},
       {"page", entry.title},
       {"revid", entry.revid},
       {"fetched", entry.fetched}
     ]}
  end

  # ── facts ───────────────────────────────────────────────────────────────────

  # `status` is about the *reading*, not about how Siala compares to vanilla:
  #
  #   verified — a value was read into structure out of the page's own words
  #   unclear  — the page says something here, but no value came out of it
  #   custom   — a shard mechanic with no vanilla counterpart, whose shape is ours
  #
  # `value: null` always means "the source names no value", never zero.
  defp siala_changes(page, siala_only?) do
    structured =
      type_fact(page) ++
        use_fact(page) ++
        requirements_fact(page) ++
        moved_facts(page) ++
        disabled_fact(page) ++
        granted_automatically_fact(page) ++
        table_facts(page) ++
        unlocks_fact(page) ++
        slots_fact(page)

    structured ++ prose_facts(page, structured, siala_only?)
  end

  defp type_fact(%{type_raw: nil}), do: []

  defp type_fact(page) do
    [fact("type", page.type, page.type_raw, nil, status(page.type))]
  end

  defp use_fact(%{use_raw: nil}), do: []

  defp use_fact(page) do
    qualified? = SialaFeatPage.qualified_use?(page.use_raw)

    note =
      cond do
        page.use == nil ->
          nil

        qualified? ->
          "На странице после этого слова стоит уточнение, оно не разобрано — см. use_raw."

        true ->
          nil
      end

    status = if page.use == nil or qualified?, do: "unclear", else: "verified"
    [fact("use", page.use, page.use_raw, note, status)]
  end

  defp requirements_fact(%{requirements: nil}), do: []

  defp requirements_fact(page) do
    unparsed? = Enum.any?(page.requirements, &(&1.kind == "unparsed"))
    valueless? = Enum.any?(page.requirements, &valueless_requirement?/1)

    note =
      cond do
        unparsed? -> "Часть требования не разобрана и лежит в атоме kind: \"unparsed\" дословно."
        valueless? -> "Фрагмент назван, но числа при нём страница не пишет — оно осталось null."
        true -> nil
      end

    [
      fact(
        "requirements",
        Enum.map(page.requirements, &requirement_json/1),
        page.requirements_raw,
        note,
        if(unparsed? or valueless?, do: "unclear", else: "verified")
      )
    ]
  end

  # A `skill` with no rank and a `class_level` with no level name a requirement
  # without stating its size — «Артистизм (Perform)» is a real condition and one
  # rank would be a guess. The atom carries a kind, so it is not `unparsed`; it
  # is not a finished reading either, and `verified` would claim it is.
  defp valueless_requirement?(%{kind: "skill", rank: nil}), do: true
  defp valueless_requirement?(%{kind: "class_level", level: nil}), do: true

  defp valueless_requirement?(%{kind: "any_of", branches: branches}),
    do: Enum.any?(branches, &valueless_requirement?/1)

  defp valueless_requirement?(_atom), do: false

  defp moved_facts(page) do
    for move <- page.moved do
      fact(
        "granted_at_level",
        {:obj,
         [
           {"class", move.class},
           {"vanilla_level", move.vanilla_level},
           {"siala_level", move.siala_level}
         ]},
        move.raw,
        nil,
        status(move.class)
      )
    end
  end

  defp disabled_fact(%{disabled: nil}), do: []

  defp disabled_fact(page) do
    [fact("disabled", true, page.disabled, nil, "verified")]
  end

  defp granted_automatically_fact(%{granted_automatically_to: nil}), do: []
  defp granted_automatically_fact(%{granted_automatically_to: []}), do: []

  defp granted_automatically_fact(page) do
    [
      fact(
        "granted_automatically_to",
        page.granted_automatically_to,
        page.lead_raw,
        "Классы, которым фит выдаётся сам на 1-м уровне; список взят из маркированного списка под фразой.",
        "verified"
      )
    ]
  end

  defp table_facts(page) do
    for table <- page.tables do
      fact(
        "level_table",
        {:obj, [{"columns", table.columns}, {"rows", table.rows}]},
        table.source,
        "Таблица со страницы, перенесена дословно; какая колонка что значит, решает человек.",
        "verified"
      )
    end
  end

  defp unlocks_fact(%{unlocks: nil}), do: []

  defp unlocks_fact(page) do
    [
      fact(
        "unlocks",
        Enum.map(page.unlocks, &unlock_json/1),
        Enum.map_join(page.unlocks, "\n", & &1.raw),
        "Кастомная механика Сиалы: фит открывает виды оружия по уровню персонажа. " <>
          "Имена оружия остались русскими (name_ru) — английских на вики нет.",
        "custom"
      )
    ]
  end

  defp slots_fact(%{taking: nil}), do: []

  defp slots_fact(page) do
    [
      fact(
        "feat_slots",
        {:obj,
         [
           {"general", page.taking.general},
           {"by_class",
            Enum.map(page.taking.by_class, fn entry ->
              {:obj, [{"class", entry.class}, {"slots", entry.slots}, {"raw", entry.raw}]}
            end)}
         ]},
        [page.taking.intro_raw | Enum.map(page.taking.by_class, &("* " <> &1.raw))]
        |> Enum.join("\n"),
        "Раздел «Возможность взятия фита» — питает слотовую модель (CLAUDE.md §6).",
        "custom"
      )
    ]
  end

  # A page that yielded nothing structured must still carry what it says, or the
  # record would read as "Siala changes nothing here" — which is the one thing it
  # does not say.
  defp prose_facts(page, structured, siala_only?) do
    status = if siala_only?, do: "custom", else: "unclear"
    already_quoted = MapSet.new(structured, & &1.quote)

    lead =
      if page.lead_raw && not MapSet.member?(already_quoted, page.lead_raw) do
        [fact("siala_note", nil, page.lead_raw, "Лид страницы, число не названо.", status)]
      else
        []
      end

    sections =
      if structured == [] do
        for section <- page.sections,
            not SialaFeatPage.reference_section?(section.title),
            section.body != "",
            do:
              fact(
                "siala_note",
                nil,
                section.body,
                "Раздел «#{section.title}», число не названо.",
                status
              )
      else
        []
      end

    lead ++ sections
  end

  defp fact(what, value, quote, note, status) do
    %{what: what, value: value, quote: quote, note: note, status: status}
  end

  defp status(nil), do: "unclear"
  defp status(_value), do: "verified"

  defp fact_json(fact) do
    affects = Map.get(fact, :affects)

    pairs =
      [{"what", fact.what}] ++
        List.wrap(affects && {"affects", affects}) ++
        [
          {"value", fact.value},
          {"quote", fact.quote},
          {"note", fact.note},
          {"status", fact.status}
        ]

    {:obj, pairs}
  end

  # ── receivers of the facts that never resolve into a rule ──────────────────

  # `changes[].affects` on the twenty-two feats whose page states something
  # the loader either has no field for at all (`siala_note` prose, `Shadow
  # evade`'s level table, the five weapon proficiencies' `unlocks` — eighteen
  # of the twenty-two, task "фиты: получатели", data-miner 14.08.2026, the
  # feat-side half of what task 3.28 did for `siala_41/classes.json`) or DOES
  # have a field, and the field is either read by no rule at all or read only
  # in part.
  #
  # ⚠ **The other four (17.08.2026, "фиты: use/requirements без получателя")
  # are a DIFFERENT kind of entry, not a second wave of the same one.**
  # `lay_on_hands`/`smile_of_death`/`teleportation` key on `"use"`, whose
  # `apply_feat_change/4` clause is unconditional (`{:ok, %{feat | use: value
  # || feat.use}}` — "Carried, never derived from") because no rule reads
  # `feat.use` at all; the qualifier past the first sentence is genuinely
  # unread, but the fact never sits in `siala_unapplied` for that reason, only
  # for the receiver tagged below to say so honestly. `artist` keys on
  # `"requirements"`, whose clause is ALSO unconditional (`shard_prereqs/1`
  # accepts any atom list), but there the unread half survives inside the
  # applied value itself, as `prereqs["unparsed"]` — `Rules.Prereqs.unread/1`
  # refuses the feat over it regardless of this module's tag, which is a
  # wholly separate mechanism this tag cannot silence and does not try to.
  # `Rules.GapReceivers` is the same module either side; the vocabulary is the
  # same dictionary too — `_receivers` lives once, on `siala_41/classes.json`,
  # and `Data.Loader` checks every string below against it before the ruleset
  # compiles, the same way it already checks the classes file. There is
  # deliberately no second `_receivers` block here.
  #
  # ⚠ Keyed by `{id, what}` **and** a prefix of the quote, not by list position:
  # `contagion_feat` and `disarm` each carry two `siala_note` facts, so `what`
  # alone will not pick one, and leaning on the page's own section order would
  # make the tag depend on something this file does not control. Matched with
  # `String.starts_with?/2` in `feat_fact_affects/2` below: a wikitext edit that
  # changes the quote makes the match fail rather than paint new prose with an
  # old decision — a fact `mix wiki.parse` cannot match keeps no `affects` at
  # all, which is the same "still a gap" direction `Data.Loader`'s own
  # `verify_affects!/4` enforces (CLAUDE.md §3). `verify_feat_fact_affects!/1`,
  # called from `collect_siala_feats/1`, is the other half of that guarantee:
  # it fails the parse run out loud if an entry below stops matching anything,
  # so a stale decision is visible rather than quietly inert.
  #
  # Every entry's own `note` carries the reasoning a reader would otherwise
  # have to reconstruct — which OTHER fact on the same page already covers
  # part of what this one says, and why what is left is (or, once, is not)
  # something the calculator prints.
  #
  # ⚠ Здесь стояло: «Two of the eighteen — `evasion` and `improved_evasion` —
  # read alike at a glance … and resolve differently; see their own notes for
  # why». **С 17.08.2026 они решаются ОДИНАКОВО** (оба `not_our`), и это не
  # значит, что различать их перестали: пришли они к одному ответу разными
  # дорогами и с разницей в полтора года данных — у `evasion` перенос был
  # безобиден с самого начала (никто из троих фит слотом не покупает), у
  # `improved_evasion` он оживил две ветки требования, и закрыл это ЗАМЕР
  # (`GAME_CHECKS.md` H9, Dan 16.08.2026), а не чтение. Заметки обеих записей
  # оставлены целиком именно поэтому: одинаковый ответ, полученный по-разному,
  # — самое лёгкое место, где следующая правка склеит два разных случая в один.

  # The five weapon proficiencies share one note verbatim: `unlocks` is always
  # the same shape (damage die, threat range, grip, damage type per weapon
  # unlocked at character level 1/10/20/30) and the same verdict (`damage`,
  # CLAUDE.md §3 — none of the four is a number this calculator ever computes).
  # A module attribute rather than five copies of the same paragraph — reused
  # by `@feat_fact_affects` below, which can only reference an attribute
  # already defined above it, never a function or a closure of its own (those
  # do not exist yet while the module body is still compiling).
  @weapon_unlock_note "Кастомная сиальская механика: фит поэтапно открывает виды " <>
                        "оружия по уровню персонажа (1/10/20/30), у каждого — урон, " <>
                        "крит-диапазон, хват и тип урона (см. value). «Возможность " <>
                        "взятия фита» — отдельный факт feat_slots этой же страницы, он " <>
                        "применяется и сюда не входит; здесь только боевые " <>
                        "характеристики оружия, которых калькулятор не считает вовсе — " <>
                        "damage."

  @feat_fact_affects %{
    {"artist", "requirements"} => [
      %{
        prefix: "Артистизм (Perform), умение можно взять только на 1-ом уровне",
        affects: ["feat_availability"],
        note:
          "НЕ дыра чтения — предел ИСТОЧНИКА, той же формы, что у skill_focus " <>
            "(vanilla/feats.json → prereqs.unparsed: [\"able to use the skill\"]): требование " <>
            "к навыку названо, а величина (ранг) не названа ни на одной вики — ни здесь, ни " <>
            "на Fandom («''[[perform]] skill''» без числа). Выдумать «хотя бы 1 ранг» значило " <>
            "бы дописать число за источник (CLAUDE.md §3), поэтому фрагмент остаётся " <>
            "в prereqs.unparsed и Rules.Prereqs.unread/1 честно отказывает фиту целиком — так " <>
            "же, как отказывает Skill focus.\n\nЭто ОДНА цитата, а не одна судьба: вторая её " <>
            "половина («умение можно взять только на 1-ом уровне») ПРИМЕНЕНА — " <>
            "prereqs.max_character_level = 1, число совпадает с ванильным «Can only take this " <>
            "feat at 1st-level» (Fandom «Artist», revid 66623) — Сиала просто повторяет " <>
            "ванильное правило. Получатель — feat_availability: содержание ЦЕЛИКОМ про " <>
            "доступность фита, просто источник называет одно из двух требований не до конца."
      }
    ],
    {"weapon_finesse", "use"} => [
      %{
        prefix: "Автоматическое при применении любого из следующих видов оружия",
        affects: ["counted_elsewhere"],
        note:
          "🔴 ЭТО НЕ ПРОЗА, А ДАННЫЕ, И ОНИ ПРИМЕНЕНЫ. Цитата несёт СПИСОК ИЗ 13 " <>
            "ПРЕДМЕТОВ поимённо — ровно то, чего у модели не было: до 17.08.2026 " <>
            "`Weapon Finesse` работал при любом оружии с допущением " <>
            "{:assumed, :finessable_weapon}, и билд с двуручным мечом считал атаку " <>
            "от ловкости. Список разобран в id и лежит в " <>
            "priv/rules/siala_41/overrides.json → formulas_shard → attack_ability " <>
            "(ванильные 11 — в vanilla-секции formulas), читает Rules.Attack.\n\n" <>
            "Поэтому получатель `counted_elsewhere`, а не `attack_ability`: тема " <>
            "СЧИТАЕТСЯ, просто не этой записью — тот же случай и то же имя, что " <>
            "у пары Мастера оружия в siala_41/classes.json. Пометить `attack_ability` " <>
            "значило бы сказать, что факт ждёт применения, хотя он применён.\n\n" <>
            "⚠️ ВТОРАЯ ПОЛОВИНА ФАКТА ПРИШЛА НЕ ОТСЮДА, и это надо знать: страница " <>
            "перечисляет 13 предметов, из которых боевой посох и копьё ДВУРУЧНЫ, " <>
            "а Fandom говорит «two-handed weapons cannot be finessed». Развёл это " <>
            "замер Dan 17.08.2026 (GAME_CHECKS.md, кейс S10): «Weapon Finesse " <>
            "на рапиру на карлике не работает» — то есть правило про двуручное " <>
            "держится, а посох с копьём исключения. Двуручность ВЫЧИСЛЯЕТСЯ " <>
            "(Rules.Wield.both_hands?/3), исключения лежат в данных.\n\n" <>
            "⚠️ Почему запись год стояла unclear: `first_sentence/1` не разбивает " <>
            "перечисление без внутренних точек, и весь список читался одним " <>
            "предложением. Диагноз «нет числа» был неверен — числа тут и не нужно, " <>
            "нужен был справочник оружия, а он появился только задачей 3.5."
      }
    ],
    {"contagion_feat", "siala_note"} => [
      %{
        prefix: "Болезнь, которую накладывал",
        affects: ["special_ability"],
        note:
          "Лид страницы: общее «действие усилено, чтобы придать классу большую " <>
            "актуальность» без единого числа — special_ability (умение без выделимого " <>
            "числа, не покрытое другим получателем; сама цитата и есть номинал, читать " <>
            "больше нечего). Формулы — во втором факте этой же страницы (раздел «Изменения»)."
      },
      %{
        prefix: "'''Радиус:''' Около 10 метров",
        affects: ["damage", "duration"],
        note:
          "Раздел «Изменения»: ДЦ болезни (20 + уровень БГ + мод. CON), радиус, время до " <>
            "заражения (40 − уровень БГ раундов), инкубационный период и эффект на цели " <>
            "(бессилие на ДЦ/4 раундов либо вытягивание уровней 1д4(2)) — урон/дебафф " <>
            "умения на ЦЕЛИ плюс тайминг этого умения. Ни урон, ни ДЦ, ни тайминг " <>
            "активируемого умения калькулятор не считает — damage и duration достаточно."
      }
    ],
    {"deathless_master_touch", "siala_note"} => [
      %{
        prefix: "Фит изменен для большей актуальности.",
        affects: ["damage", "healing"],
        note:
          "Раздел «Описание»: канальное умение Бледного Мастера — «урон и лечение " <>
            "зависит от уровней в классе d6» прямым текстом, плюс радиус от INT/CHA, " <>
            "число целей и срабатываний от фокусов на Некромантии, иммунитет цели через " <>
            "«защиту от смерти», обездвиженность мастера на время действия. Урон и " <>
            "лечение — два числа калькулятор не считает вовсе; damage/healing хватает, " <>
            "радиус/иммунитет/обездвиженность — та же механика, отдельного получателя " <>
            "не заводим ради одного факта."
      }
    ],
    {"devastating_critical", "siala_note"} => [
      %{
        prefix: "Этот фит на Сиале отключен, взять его нельзя.",
        affects: ["special_ability"],
        note:
          "Лид страницы: то же самое предложение, что уже применено фактом «disabled» " <>
            "(фит выключен целиком, feat_availability уже честно закрыт), плюс фраза " <>
            "«игроки называют его „девастат“» — кличка без единого числа и без " <>
            "механики. Ничего сверх уже применённого «disabled» здесь нет; " <>
            "special_ability — по той же причине, что и у contagion_feat выше."
      }
    ],
    {"disarm", "siala_note"} => [
      %{
        prefix: "Дизарм - это фит, который позволяет",
        affects: ["special_ability"],
        note:
          "Лид страницы: как дизарм работает вообще (нельзя выбить из пустых рук/лап, " <>
            "на монстров действует как обычно) — поведенческое пояснение без числа. " <>
            "Экономика выбитого оружия — во втором факте этой же страницы."
      },
      %{
        prefix: "Расчет вероятности никак не изменен",
        affects: ["custom_system"],
        note:
          "Раздел «Магазин выбитого оружия»: сам шанс разоружения не тронут («расчёт " <>
            "вероятности никак не изменён»), правки — отдельная экономика лута: шанс " <>
            "уронить оружие на пол (30%/10% по территории), иначе оно уходит вендору " <>
            "Абрахиду, откуда владелец выкупает его, агрессор получает долю (70%), " <>
            "потолок 200 000 золотых, вещь висит у вендора 1 реальный месяц. Целиком " <>
            "PvP-экономика золота и лута между игроками — ни одно из чисел не касается " <>
            "характеристик персонажа, который выбивает или которого разоружили; " <>
            "custom_system — «целиком отдельная система шарда без аналога в ванили»."
      }
    ],
    {"divine_might", "siala_note"} => [
      %{
        prefix: "Бонусы, полученные от использования умения, нельзя рассеять.",
        affects: ["duration"],
        note:
          "Раздел «Изменения на Сиале»: длительность умения растёт по трём порогам " <>
            "уровня класса (Паладин/Черный страж/Чемпион Торма), плюс «нельзя рассеять» " <>
            "и «перекастовываемо». Сам фит и его прибавка — уже общий, не наш, гэп " <>
            "{:not_modelled, {:feat_bonus, …}}; этот факт целиком про длительность и " <>
            "поведение активации того же временного эффекта, поэтому duration и без " <>
            "добавления buff — эффект без числа, который надо было бы считать «нашим», " <>
            "здесь не появляется вовсе."
      }
    ],
    {"divine_shield", "siala_note"} => [
      %{
        prefix: "Бонусы, полученные от использования умения, нельзя рассеять.",
        affects: ["duration"],
        note: "Та же правка и тем же текстом, что у Divine might — см. его заметку."
      }
    ],
    {"divine_wrath", "siala_note"} => [
      %{
        prefix: "Это умение сохранило все бонусы оригинального фита",
        affects: ["duration"],
        note:
          "Раздел «Описание» говорит это прямым текстом: «сохранило ВСЕ бонусы " <>
            "оригинального фита… изменению подверглась ТОЛЬКО его длительность: " <>
            "игровой час на модификатор харизмы». Сама страница подтверждает, что " <>
            "кроме длительности здесь нечего считать — duration."
      }
    ],
    {"evasion", "siala_note"} => [
      %{
        prefix: "Уклонение перенесено:",
        affects: ["immunities"],
        note:
          "⚠️ ЛОВУШКА, разобрана отдельно от improved_evasion ниже — читаются одинаково, " <>
            "решаются по-разному. Лид страницы дословно повторяет три уровня переноса " <>
            "(вор 2→30, монах 1→25, ШД 2→15), но эти три числа УЖЕ применены — каждое " <>
            "своим отдельным фактом granted_at_level этой же страницы, и Rogue/Monk/" <>
            "Shadowdancer здесь и так auto-grant-only (bonus_for пуст у всех трёх, " <>
            "прежде и после Сиалы — Evasion никогда не выбирается слотом), так что " <>
            "переносу нечему мешать. Проверено вызовом (14.08.2026): " <>
            "ruleset.classes.{rogue,monk,shadowdancer}.granted_feats содержит :evasion " <>
            "ровно на 30/25/15. Тегать этот факт feat_availability значило бы печатать " <>
            "«не применяем» про применённое — ровно та ошибка, от которой " <>
            "предостерегает задача. Единственное НЕ покрытое содержимое факта — " <>
            "фиксированный шанс уклониться от восьми конкретных заклинаний " <>
            "(«Quillfire 5%, Ice storm 5%, …»), который только у вора и нигде не " <>
            "применён; immunities — «шанс проигнорировать» дословно из словаря."
      }
    ],
    {"improved_evasion", "siala_note"} => [
      %{
        prefix: "Улучшенное уклонение перенесено:",
        affects: ["special_ability"],
        note:
          "⚠️ ЛОВУШКА — читается как двойник evasion выше, но пришёл к тому же ответу " <>
            "другой дорогой; заметки обеих записей поэтому и оставлены целиком. Первые " <>
            "два предложения (монах 9→30, ШД 10→25) — auto-grant сдвиги, применённые " <>
            "своими granted_at_level фактами. Третье («может взять вор, начиная с " <>
            "35-го уровня, а не с 10-го») — про ПРАВО КУПИТЬ слотом (bonus_for включает " <>
            "rogue), а не про выдачу, и применено с 14.08.2026 фактом " <>
            "requirement_class_level ручного слоя (priv/rules/siala_41/feats.json). " <>
            "До того дня строка стояла в класс-слое как feat_level_shift, то есть как " <>
            "выдача, и модель врала в обе стороны: вор 10–34 брал слотом отобранное, " <>
            "вор 35 получал даром покупное.\n\n" <>
            "🔴 ГЭП СНЯТ 17.08.2026 — РЕШЕНИЕМ Dan ПОВЕРХ ЗАМЕРА, а не «тег убрали». " <>
            "Dan дословно: «думаю с Improved Evasion у нас все однозначно, можно " <>
            "убирать ее из гэпов. Правила железные и измеряны». Измерены они кейсом H9 " <>
            "(GAME_CHECKS.md, Dan 16.08.2026), и вот что тот замер закрыл.\n\n" <>
            "ЧТО ЗДЕСЬ СТОЯЛО И ПОЧЕМУ ЭТО БОЛЬШЕ НЕ ВЕРНО. Стояло: «Применены три " <>
            "предложения из трёх, но у первых двух есть НЕДОЧИТАННОЕ СЛЕДСТВИЕ, и " <>
            "именно оно теперь и есть остаток». Следствие было такое: ванильный any_of " <>
            "— [монах 9, вор 10, ШД 10] — списан с ванильных уровней ВЫДАЧИ, в ванили " <>
            "ветки монаха и ШД инертны (кто их проходит, фитом уже владеет), а шард " <>
            "отодвинул выдачу на 30 и 25 — и обе ветки ожили: монах 9 фитом не " <>
            "владеет, требование проходило, и в бонусном слоте вора фит был доступен " <>
            "уже на воре 10, в обход «а не с 10-го». Тогда двигать эти две ветки было " <>
            "запрещено: страница про них молчит, и число пришлось бы выдумать. **H9 " <>
            "принёс числа замером** — монах 9 / вор 10 фита НЕ видит, выдача монаху " <>
            "стоит на 30, ШД на 25 — и все три ветки any_of двинуты тремя записями " <>
            "requirement_class_level того же ручного слоя (вор 10→35, монах 9→30, " <>
            "ШД 10→25, все три status: verified). Остатка не осталось.\n\n" <>
            "ПРОВЕРЕНО ВЫЗОВОМ (17.08.2026), а не выведено из записей: билд монах 9 / " <>
            "вор 10 получает от Rules.validate_feat/3 и Rules.validate_feat_pick/3 " <>
            "{:error, [requires_any_of: [[monk 30], [rogue 35], [shadowdancer 25]]]}, " <>
            "фитом не владеет, и ни один слот его не принимает по требованиям; вор 36 " <>
            "берёт фит эпическим бонусным слотом, :ok. Тот самый дип, ради которого " <>
            "оговорка держалась, закрыт.\n\n" <>
            "⚠️ ПОЧЕМУ ТЕГ ПЕРЕСТАВЛЕН, А НЕ УДАЛЁН. Факт без affects — это гэп по " <>
            "построению (Rules.GapReceivers.ours?/2: «метки нет — факт остаётся " <>
            "гэпом»), то есть удаление тега вернуло бы ровно то, что снимается. " <>
            "И feat_availability здесь стало ЛОЖЬЮ ПРО ПОСЧИТАННОЕ: все три " <>
            "предложения применены, а печатать «учтено не полностью» про применённое " <>
            "— та самая ложная неопределённость, которую запрещает CLAUDE.md §6. " <>
            "special_ability — по тому же образцу, что у devastating_critical выше: " <>
            "проза, чьё механическое содержимое целиком применено другим фактом той же " <>
            "страницы, и получателя из списка ей больше не найти. Что фит ДЕЛАЕТ " <>
            "(половина урона при проваленном сейве по реакции) на странице не сказано " <>
            "ни словом — тегать immunities, как у evasion, значило бы приписать факту " <>
            "содержимое, которого в его цитате нет."
      }
    ],
    {"lay_on_hands", "use"} => [
      %{
        prefix:
          "По выбору. По выбору. При использовании против нежити рассматривается " <>
            "как умение с прикосновением",
        affects: ["special_ability"],
        note:
          "Уточнение после «По выбору» — про то, КАК умение применяется к нежити (как " <>
            "умение с прикосновением, урон вместо исцеления), а не про то, СКОЛЬКО оно " <>
            "даёт: формула самого исцеления (уровень в классе × мод. харизмы + Лечение) " <>
            "лежит в special_raw этой же страницы и калькулятором не считается вовсе " <>
            "(healing, CLAUDE.md §9) — эта запись про use, не про величину. Чисел " <>
            "в уточнении нет ни одного; special_ability — «боевая механика умения без " <>
            "выделимого числа», дословно из словаря, тот же образец, что у disarm/" <>
            "contagion_feat выше."
      }
    ],
    {"perfect_health", "siala_note"} => [
      %{
        prefix: "Помимо иммунитета к обычным ядам",
        affects: ["immunities", "poisons"],
        note:
          "Раздел «Описание»: сверх ванильного иммунитета к ядам и болезням фит " <>
            "добавляет иммунитет к ядам Убийцы и Черного стража — та же кастомная " <>
            "система ядов Сиалы, что и rogue/poisons и assassin/poisons в классах " <>
            "(там тоже not_our); immunities для самого факта иммунитета, poisons — " <>
            "потому что это именно сиальская система ядов, а не общий яд-эффект."
      }
    ],
    {"shadow_evade", "level_table"} => [
      %{
        prefix: "{| class=\"wikitable\"",
        affects: ["buff", "immunities"],
        note:
          "⚠️ ТА ЖЕ СПОСОБНОСТЬ, что shadowdancer/class_ability_changed в " <>
            "siala_41/classes.json (пункт 4 её цитаты — прямая ссылка [[Shadow evade|" <>
            "Теневой обход]]), и Dan 10.08.2026 уже классифицировал её как buff: " <>
            "«Shadow Evade активируется и кончается, то есть временный эффект, а не " <>
            "постоянное свойство персонажа». Таблица (снижение урона, маскировка, " <>
            "бонус АЦ, бонус Hide/Move Silently, длительность по уровню ШД) выглядит " <>
            "как AC/skill_values, но гейт — по временности активируемого режима, а не " <>
            "по номиналу колонки (дословно из словаря not_our.buff: «величина внутри " <>
            "буфа не переклассифицируется в our, даже если формально совпадает с одним " <>
            "из our-получателей»). immunities — колонка снижения урона (damage " <>
            "reduction) и процент маскировки; тот же набор, что у class_ability_changed."
      }
    ],
    {"shadow_evade", "siala_note"} => [
      %{
        prefix: "Этот довольно бесполезный фит оригинального NwN",
        affects: ["buff", "immunities"],
        note:
          "Лид страницы, дословно та же таблица и та же способность — см. заметку level_table этой же страницы."
      }
    ],
    {"siala_axe_proficiency", "unlocks"} => [
      %{prefix: "# Серпы (", affects: ["damage"], note: @weapon_unlock_note}
    ],
    {"siala_blade_proficiency", "unlocks"} => [
      %{prefix: "# Кинжалы (", affects: ["damage"], note: @weapon_unlock_note}
    ],
    {"siala_hammer_proficiency", "unlocks"} => [
      %{prefix: "# Кнуты (", affects: ["damage"], note: @weapon_unlock_note}
    ],
    {"siala_polearm_proficiency", "unlocks"} => [
      %{prefix: "# Посохи (", affects: ["damage"], note: @weapon_unlock_note}
    ],
    {"siala_ranged_proficiency", "unlocks"} => [
      %{prefix: "# Сюрикены (", affects: ["damage"], note: @weapon_unlock_note}
    ],
    {"siala_spell_school_focus", "siala_note"} => [
      %{
        prefix: "* школа Conjuration:",
        affects: ["spell_effects", "damage", "summons"],
        note:
          "Не отдельный фит (describes_feat: false — семейная страница восьми школ " <>
            "Spell Focus разом), а список того, что фокус на каждую школу меняет в " <>
            "ЗАКЛИНАНИЯХ: Conjuration — сила призванных и урон Evard's black tentacles; " <>
            "Evocation — урон ice storm у шифтера-ракшасы; Illusion — бонус Hide/Move " <>
            "Silently от displacement, зависящий от уровня барда; Necromancy — качество " <>
            "и количество поднятой нежити, работоспособность умений Бледного мастера, " <>
            "урон Harm у шаманов. Это ровно spell_effects («список изменённых Сиалой " <>
            "заклинаний — считается в слое spells, не здесь»), с damage и summons как " <>
            "двумя конкретными числовыми гранями того же списка."
      }
    ],
    {"slippery_mind", "siala_note"} => [
      %{
        prefix: "Фит Slippery mind дает",
        affects: ["immunities"],
        note:
          "Лид страницы: шанс игнорировать семь конкретных заклинаний по формуле " <>
            "((максимальный шанс) / 20) × (уровень вора / 2). Тот же кастомный шанс, " <>
            "что rogue/evasion_vs_spells в siala_41/classes.json называет для " <>
            "Evasion+Slippery mind вместе («ни шанс, ни список заклинаний не " <>
            "названы» — там формула была неизвестна, здесь она уже есть). immunities — " <>
            "«шанс проигнорировать» дословно из словаря, та же запись, что у evasion."
      }
    ],
    {"smile_of_death", "use"} => [
      %{
        prefix: "Автоматическое. Эффект срабатывает один раз в день",
        affects: ["ability_uses"],
        note:
          "Уточнение после «Автоматическое» называет ПОРОГ ПРИМЕНЕНИЯ — сколько раз " <>
            "в день может сработать умение, а не что оно даёт (шанс, срез урона, лечение " <>
            "— отдельные, тоже не наши поля special_raw этой же страницы). Тот же класс " <>
            "факта, что contagion_charges и deathless_master_touch/uses_per_rest " <>
            "в siala_41/classes.json: «сколько раз в день/за отдых можно применить " <>
            "умение» дословно из словаря — ability_uses, не special_ability (единица " <>
            "измерения здесь есть, просто это частота, а не боевая величина)."
      }
    ],
    {"teleportation", "use"} => [
      %{
        prefix: "Посох (Unique Power). По выбору",
        affects: ["special_ability"],
        note:
          "«Посох (Unique Power). По выбору» — описание СПОСОБА активации (через " <>
            "уникальную способность посоха, вручную выбором игрока), а не число. " <>
            "Величины в этой цитате нет ни одной: дистанция телепортации (5 метров × " <>
            "уровень Волшебника) лежит в extra_labels этой же страницы отдельным, " <>
            "непродвинутым в факт полем и в эту запись не входит — здесь только СПОСОБ " <>
            "применения. Special_ability — «боевая механика умения без выделимого " <>
            "числа», тот же образец, что у devastating_critical/disarm выше."
      }
    ]
  }

  @doc false
  # Which `affects`/`note` pair, if any, this fact should carry — matched by a
  # prefix of its own `quote` against `@feat_fact_affects`. `nil` leaves the
  # fact exactly as `siala_changes/2` built it: unlabelled, which
  # `Rules.GapReceivers` reads as "still a gap" (CLAUDE.md §3).
  defp tag_feat_fact_affects(changes, id) do
    Enum.map(changes, fn change ->
      case feat_fact_affects(id, change) do
        nil -> change
        tag -> Map.merge(change, %{affects: tag.affects, note: tag.note})
      end
    end)
  end

  defp feat_fact_affects(id, change) do
    case Map.get(@feat_fact_affects, {id, change.what}) do
      nil -> nil
      candidates -> Enum.find(candidates, &String.starts_with?(change.quote || "", &1.prefix))
    end
  end

  # The other half of the safety `feat_fact_affects/2`'s prefix match buys:
  # a prefix that stops matching anything fails the parse run instead of
  # sitting unused. Called once, after every page has been read, against the
  # `changes` this task is about to write — never against the wikitext
  # directly, so it only ever proves what actually landed in the file.
  defp verify_feat_fact_affects!(records) do
    by_key = Map.new(records, &{&1.id, &1})

    for {{id, what}, candidates} <- @feat_fact_affects,
        candidate <- candidates do
      record = Map.get(by_key, id)

      matched? =
        record != nil and
          Enum.any?(record.changes, fn change ->
            change.what == what and String.starts_with?(change.quote || "", candidate.prefix)
          end)

      unless matched? do
        Mix.shell().error(
          "[siala feats] @feat_fact_affects entry #{inspect({id, what})} " <>
            "(prefix #{inspect(candidate.prefix)}) matched no fact — the wikitext moved " <>
            "and this decision is stale"
        )
      end
    end
  end

  @requirement_keys [
    :kind,
    :class,
    :level,
    :ability,
    :value,
    :skill,
    :rank,
    :feat,
    :race,
    :branches,
    :raw
  ]

  # A branch of an `any_of` is a requirement atom in its own right, written out
  # by the same ordering.
  defp requirement_json(%{branches: branches} = atom) do
    atom
    |> Map.put(:branches, Enum.map(branches, &requirement_json/1))
    |> ordered(@requirement_keys)
  end

  defp requirement_json(atom), do: ordered(atom, @requirement_keys)

  @weapon_keys [
    :name_ru,
    :damage_raw,
    :damage,
    :crit_raw,
    :crit,
    :grip_raw,
    :grip,
    :ranged,
    :damage_type_raw,
    :damage_type,
    :raw
  ]

  defp unlock_json(step) do
    {:obj,
     [
       {"level", step.level},
       {"weapons", Enum.map(step.weapons, &weapon_json/1)},
       {"raw", step.raw}
     ]}
  end

  defp weapon_json(weapon) do
    weapon
    |> Map.update!(:damage, fn
      nil -> nil
      ranges -> Enum.map(ranges, &{:obj, [{"min", &1.min}, {"max", &1.max}]})
    end)
    |> Map.update!(:crit, fn
      nil ->
        nil

      crit ->
        {:obj,
         [
           {"threat_low", crit.threat_low},
           {"threat_high", crit.threat_high},
           {"multiplier", crit.multiplier}
         ]}
    end)
    |> ordered(@weapon_keys)
  end

  defp ordered(map, keys) do
    {:obj,
     for(key <- keys, Map.has_key?(map, key), do: {Atom.to_string(key), Map.fetch!(map, key)})}
  end

  # `ё` -> `е` and case-folded, matching `SialaFeatPage`: the wiki spells the
  # blackguard both ways and the two must key alike.
  defp siala_fold(name) do
    name
    |> String.downcase()
    |> String.replace("ё", "е")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp write_siala(file, key, %{records: records}, notes) do
    path = Path.join([File.cwd!(), @siala_output_dir, file])
    File.mkdir_p!(Path.dirname(path))

    json =
      {:obj,
       [
         {"_layer", "siala_41/generated"},
         {"_generated_by", "mix wiki.parse"},
         {"_note", notes.note},
         {"_field_note", notes.field_note},
         {key, Enum.map(records, & &1.json)}
       ]}

    File.write!(path, Json.encode!(json))
  end

  defp report_siala(siala, vanilla_feats) do
    records = siala.records
    matched = Enum.reject(records, & &1.siala_only?)
    facts = Enum.flat_map(records, & &1.changes)
    counts = facts |> Enum.frequencies_by(& &1.status) |> Enum.sort()

    Mix.shell().info(
      "[siala feats] #{length(records)} records from #{siala.scanned} pages " <>
        "-> #{@siala_output_dir}/feats.json"
    )

    Mix.shell().info(
      "[siala feats] #{length(matched)} matched a vanilla feat, " <>
        "#{length(records) - length(matched)} siala_only; #{length(facts)} facts " <>
        Enum.map_join(counts, ", ", fn {status, count} -> "#{status}: #{count}" end)
    )

    for record <- records, record.siala_only? do
      Mix.shell().info("[siala feats] no vanilla counterpart: #{record.title} -> #{record.id}")
    end

    # Указатель, а не вывод: печатается счётчик, чтобы было видно, растёт ли
    # объём ручной вычитки, — и «сравнить не с чем» отдельно от «сравнили».
    comparable = Enum.count(records, &(&1.diff.differs != nil))

    Mix.shell().info(
      "[siala feats] numbers differ on #{Enum.count(records, & &1.diff.differs)} " <>
        "of #{comparable} pages whose «Особенности» could be compared with vanilla; " <>
        "#{length(records) - comparable} had nothing to compare"
    )

    covered = records |> Enum.flat_map(& &1.vanilla_ids) |> MapSet.new()

    Mix.shell().info(
      "[siala feats] #{MapSet.size(covered)} of #{length(vanilla_feats.records)} vanilla feats " <>
        "are described on the Siala wiki; the other " <>
        "#{length(vanilla_feats.records) - MapSet.size(covered)} are assumed vanilla"
    )

    for record <- records, problem <- record.page.problems do
      Mix.shell().error("[siala feats] #{record.title}: #{problem}")
    end

    # A class name nobody could resolve turns into a `null` inside an otherwise
    # complete fact, which is exactly the kind of hole that reads as "no class".
    for record <- records, move <- record.page.moved, is_nil(move.class) do
      Mix.shell().error("[siala feats] #{record.title}: unknown class in: #{move.raw}")
    end

    for record <- records,
        taking = record.page.taking,
        taking != nil,
        entry <- taking.by_class,
        is_nil(entry.class) do
      Mix.shell().error(
        "[siala feats] #{record.title}: unknown class in feat slot line: #{entry.raw}"
      )
    end

    duplicates =
      records
      |> Enum.group_by(& &1.id, & &1.title)
      |> Enum.filter(fn {_id, titles} -> length(titles) > 1 end)

    for {id, titles} <- duplicates do
      Mix.shell().error("[siala feats] duplicate id #{id}: #{Enum.join(titles, ", ")}")
    end

    # Identifiers are English everywhere in this project (CLAUDE.md §4). A Russian
    # page title that reaches an id means it needs an entry in `@siala_ids`.
    for record <- records, not Regex.match?(~r/^[a-z0-9_]+$/, record.id) do
      Mix.shell().error(
        "[siala feats] id is not an ASCII identifier: #{record.id} (#{record.title})"
      )
    end
  end

  # ── Siala: spells ───────────────────────────────────────────────────────────

  @siala_spell_category "Категория:Заклинания"

  # 129 pages, 128 of them the same block of bold Russian labels. Reading those is
  # the easy half; the half that matters is that the shard keeps its balance
  # changes *inside the description* — `Fireball` carries the vanilla label block
  # and says «до максимума 20d6» in mid-sentence where vanilla says 10d6. So the
  # description is kept whole and only the numbers printed in it are compared
  # against the numbers printed in the vanilla description. That comparison
  # survives the language barrier and points at the pages a human must read; it
  # never decides what the new value is.
  defp collect_siala_spells(vanilla_spells) do
    index = Cache.read_index!(@siala_wiki)

    pages =
      for entry <- index,
          @siala_spell_category in entry.categories,
          do: {entry, Cache.read_page!(@siala_wiki, entry)}

    aliases = name_map_by_russian()
    vanilla = Map.new(vanilla_spells.records, &{&1.id, &1})
    ids = MapSet.new(Map.keys(vanilla))

    parsed =
      for {entry, wikitext} <- pages do
        page = SialaSpellPage.parse(wikitext)
        {vanilla_ids, matched_by} = match_vanilla(entry, page, aliases, ids, "_spell")
        %{entry: entry, page: page, vanilla_ids: vanilla_ids, matched_by: matched_by}
      end

    # `Energy drain` matches by title and `Essence Drain` links the same Fandom
    # page as its English counterpart. Neither may take the shared id, so both
    # keep an id of their own and only `vanilla_id` is shared.
    shared =
      parsed
      |> Enum.flat_map(& &1.vanilla_ids)
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> MapSet.new(fn {id, _count} -> id end)

    records = for record <- parsed, do: siala_spell_record(record, shared, vanilla)

    %{records: Enum.sort_by(records, & &1.id), scanned: length(pages)}
  end

  defp siala_spell_record(
         %{entry: entry, page: page, vanilla_ids: vanilla_ids, matched_by: matched_by},
         shared,
         vanilla
       ) do
    vanilla_id = List.first(vanilla_ids)
    counterpart = vanilla_id && Map.fetch!(vanilla, vanilla_id)
    id = siala_id(entry.title, vanilla_id, shared)
    diff = numeric_diff(page, counterpart)
    fields = field_diff(page, counterpart)
    differs = differs?(diff, fields)
    changes = siala_spell_changes(page)

    json =
      {:obj,
       [
         {"id", id},
         {"ru", entry.title},
         {"name", siala_spell_name(entry.title, counterpart)},
         {"vanilla_id", vanilla_id},
         {"vanilla_ids", vanilla_ids},
         {"matched_by", matched_by},
         {"siala_only", vanilla_id == nil},
         {"caster_level_raw", page.caster_level_raw},
         {"initial_level_raw", page.initial_level_raw},
         {"school_raw", page.school_raw},
         {"descriptors_raw", page.descriptors_raw},
         {"components_raw", page.components_raw},
         {"range_raw", page.range_raw},
         {"area_raw", page.area_raw},
         {"duration_raw", page.duration_raw},
         {"save_raw", page.save_raw},
         {"spell_resistance_raw", page.spell_resistance_raw},
         {"shamanism_raw", page.shamanism_raw},
         {"extra_labels", {:obj, page.extra_labels}},
         {"description_raw", page.description_raw},
         {"numbers", page.numbers},
         {"differs_from_vanilla", differs},
         {"numbers_differ", diff.differs},
         {"numeric_diff", numeric_diff_json(diff)},
         {"fields_differ", fields_differ(fields)},
         {"field_diff", field_diff_json(fields)},
         {"sections", Enum.map(page.sections, &{:obj, [{"title", &1.title}, {"body", &1.body}]})},
         {"changes", Enum.map(changes, &fact_json/1)},
         {"source", siala_source(entry)},
         {"status", if(differs, do: "unclear", else: "parsed")},
         {"note", note(diff, fields)}
       ]}

    %{
      id: id,
      title: entry.title,
      json: json,
      page: page,
      changes: changes,
      vanilla_ids: vanilla_ids,
      siala_only?: vanilla_id == nil,
      diff: diff,
      fields: fields,
      differs: differs
    }
  end

  # `differs` is `null`, not `false`, when there is nothing to compare against:
  # "we did not check" and "we checked and they agree" are different answers, and
  # collapsing them would read as a clean bill of health nobody issued.
  defp numeric_diff(page, nil), do: %{differs: nil, vanilla: nil, siala: page.numbers, note: nil}

  defp numeric_diff(page, counterpart) do
    description = counterpart.params["desc"]

    cond do
      description == nil ->
        %{
          differs: nil,
          vanilla: nil,
          siala: page.numbers,
          note: "У ванильного заклинания нет описания — сравнивать не с чем."
        }

      page.description_raw == nil ->
        %{
          differs: nil,
          vanilla: SialaSpellPage.numbers(description),
          siala: [],
          note: "На странице Сиалы нет описания — сравнивать не с чем."
        }

      true ->
        vanilla_numbers = SialaSpellPage.numbers(description)

        # `note` carries only what could *not* be compared; what the comparison
        # found is assembled by `note/2`, which also knows about the fields.
        %{
          differs: vanilla_numbers != page.numbers,
          vanilla: vanilla_numbers,
          siala: page.numbers,
          note: nil
        }
    end
  end

  defp numeric_diff_json(%{differs: true} = diff),
    do: {:obj, [{"vanilla", diff.vanilla}, {"siala", diff.siala}]}

  defp numeric_diff_json(_diff), do: nil

  # ── the fields both wikis keep in a structure ───────────────────────────────
  #
  # A disagreement in a field is a different kind of event from a disagreement
  # between the numbers in two paragraphs of prose, so the two are kept apart in
  # the record: `numeric_diff` stays the description's numbers, `field_diff`
  # carries the fields, and `differs_from_vanilla` is the two of them together.
  #
  # Five of the six are compared through a closed vocabulary both wikis write —
  # eight schools, three saving throws, yes/no, a circle as a plain number, the
  # six casting classes. The sixth, the duration, is prose on both sides
  # (`24 [[hour]]s` against «15 Раундов»), so it is compared the way descriptions
  # are: by the numbers printed in it.

  @vanilla_circles [
    {:bard, "bardlevel"},
    {:cleric, "clericlevel"},
    {:druid, "druidlevel"},
    {:mage, "magelevel"},
    {:paladin, "paladinlevel"},
    {:ranger, "rangerlevel"}
  ]

  defp field_diff(_page, nil), do: []

  defp field_diff(page, counterpart) do
    params = counterpart.params

    [
      compare("school", params["school"], page.school_raw, &SialaSpellPage.school/1),
      compare("save", params["save"], page.save_raw, &SialaSpellPage.save/1),
      compare(
        "spell_resistance",
        params["spellresistance"],
        page.spell_resistance_raw,
        &SialaSpellPage.spell_resistance/1
      ),
      compare_circles(params, page),
      compare(
        "initial_level",
        params["innatelevel"],
        page.initial_level_raw,
        &SialaSpellPage.level/1
      ),
      compare_duration(params, page)
    ]
  end

  defp compare(name, vanilla_raw, siala_raw, reader) do
    entry(name, vanilla_raw, siala_raw, reader.(vanilla_raw), reader.(siala_raw))
  end

  # Fandom spreads the circles over six parameters and Siala writes them on one
  # line, so the vanilla side is joined into one for the record. Only the layout
  # is ours; every value in it is the page's own.
  defp compare_circles(params, page) do
    written =
      for {class, param} <- @vanilla_circles, value = params[param], do: "#{class} #{value}"

    entry(
      "circles",
      if(written == [], do: nil, else: Enum.join(written, ", ")),
      page.caster_level_raw,
      vanilla_circles(params),
      SialaSpellPage.circles(page.caster_level_raw)
    )
  end

  # `epic` sits in these parameters as often as a number does. One unreadable
  # circle fails the whole list: a spell missing a class reads as unavailable to
  # it, which is a louder lie than "could not compare".
  defp vanilla_circles(params) do
    Enum.reduce_while(@vanilla_circles, {:ok, []}, fn {class, param}, {:ok, pairs} ->
      case params[param] do
        nil ->
          {:cont, {:ok, pairs}}

        value ->
          case SialaSpellPage.level(value) do
            {:ok, circle} -> {:cont, {:ok, [{class, circle} | pairs]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.sort(pairs)}
      error -> error
    end
  end

  # «Мгновенное» against `instant` prints no number on either side, so there the
  # two are not compared at all — an empty list matching an empty list is not
  # agreement, and calling it one would hide every change written in words.
  # One numberless side against a numbered one is a different matter: `permanent`
  # against «5 Минут» is a disagreement the page states outright.
  defp compare_duration(params, page) do
    {vanilla, siala} =
      case {duration_numbers(params["duration"]), duration_numbers(page.duration_raw)} do
        {{:ok, []}, {:ok, []}} -> {{:error, :no_numbers}, {:error, :no_numbers}}
        both -> both
      end

    entry("duration", params["duration"], page.duration_raw, vanilla, siala)
  end

  defp duration_numbers(nil), do: {:error, :absent}
  defp duration_numbers(value), do: {:ok, SialaSpellPage.numbers(value)}

  defp entry(name, vanilla_raw, siala_raw, {:ok, same}, {:ok, same}),
    do: %{name: name, vanilla: vanilla_raw, siala: siala_raw, verdict: :same, reason: nil}

  defp entry(name, vanilla_raw, siala_raw, {:ok, _vanilla}, {:ok, _siala}),
    do: %{name: name, vanilla: vanilla_raw, siala: siala_raw, verdict: :differs, reason: nil}

  defp entry(name, vanilla_raw, siala_raw, vanilla, siala) do
    %{
      name: name,
      vanilla: vanilla_raw,
      siala: siala_raw,
      verdict: :unreadable,
      reason: unread(vanilla, siala)
    }
  end

  defp unread({:error, same}, {:error, same}), do: "обе стороны: " <> unread_reason(same)

  defp unread(vanilla, siala) do
    [{"ваниль", vanilla}, {"Сиала", siala}]
    |> Enum.filter(&match?({_side, {:error, _reason}}, &1))
    |> Enum.map_join("; ", fn {side, {:error, reason}} -> "#{side}: #{unread_reason(reason)}" end)
  end

  defp unread_reason(:absent), do: "поля на странице нет"
  defp unread_reason(:struck_out), do: "в поле только зачёркнутая история патчей"
  defp unread_reason(:no_numbers), do: "чисел в значении нет, а сравнивается оно по числам"
  defp unread_reason({:unknown, text}), do: "значение не из известного словаря: «#{text}»"

  # Only what is not `same` is written out: a field the comparison passed is the
  # one case with nothing to read, and the note says an absent name means exactly
  # that. Everything else — including what could not be compared — is in the file.
  defp field_diff_json(fields) do
    written =
      for field <- fields,
          field.verdict != :same,
          do:
            {field.name,
             {:obj,
              [
                {"verdict", Atom.to_string(field.verdict)},
                {"vanilla", field.vanilla},
                {"siala", field.siala},
                {"reason", field.reason}
              ]}}

    if written == [], do: nil, else: {:obj, written}
  end

  defp fields_differ([]), do: nil
  defp fields_differ(fields), do: differing?(fields)

  defp differing?(fields), do: Enum.any?(fields, &(&1.verdict == :differs))

  # `null` is "we could not check all of it", not "no", so a page whose numbers
  # had nothing to compare against never reads as a clean bill of health.
  defp differs?(diff, fields) do
    cond do
      diff.differs == true or differing?(fields) -> true
      diff.differs == nil -> nil
      true -> false
    end
  end

  @machine_points "Машина только показывает, куда смотреть; значение из прозы она не выводит."

  @field_titles %{
    "school" => "школа",
    "save" => "спасбросок",
    "spell_resistance" => "сопротивление заклинанию",
    "circles" => "круги по классам",
    "initial_level" => "начальный уровень",
    "duration" => "длительность"
  }

  defp note(diff, fields) do
    found =
      Enum.reject([numbers_note(diff.differs), fields_note(fields)], &is_nil/1)

    case {diff.note, found} do
      {nil, []} -> nil
      {reason, []} -> reason
      {nil, found} -> Enum.join(found ++ [@machine_points], " ")
      {reason, found} -> Enum.join([reason | found] ++ [@machine_points], " ")
    end
  end

  defp numbers_note(true), do: "Числа в описании Сиалы и в ванильном описании разошлись."
  defp numbers_note(_other), do: nil

  defp fields_note(fields) do
    case for field <- fields, field.verdict == :differs, do: @field_titles[field.name] do
      [] -> nil
      names -> "Разошлись поля: " <> Enum.join(names, ", ") <> "."
    end
  end

  defp siala_spell_name(_title, %{title: title}), do: title

  defp siala_spell_name(title, nil) do
    if Regex.match?(~r/^[\p{Latin}\p{N}\s()'’.,\/-]+$/u, title), do: title, else: nil
  end

  # One fact per statement of the «Изменение в заклинаниях» section, quoted
  # verbatim. `value` stays null and `status` stays `unclear` throughout: these
  # sections are free prose about formulas («урон равен уровень кастера / 4»), and
  # turning that into a number is the guessing the project forbids.
  defp siala_spell_changes(page) do
    for section <- page.changes_raw, item <- SialaSpellPage.change_items(section.body) do
      fact(
        "siala_change",
        nil,
        item,
        "Пункт раздела «#{section.title}» дословно; значения из него не выведены.",
        "unclear"
      )
    end
  end

  defp report_siala_spells(siala, vanilla_spells) do
    records = siala.records
    matched = Enum.reject(records, & &1.siala_only?)
    differing = Enum.filter(records, &(&1.diff.differs == true))
    facts = Enum.flat_map(records, & &1.changes)

    Mix.shell().info(
      "[siala spells] #{length(records)} records from #{siala.scanned} pages " <>
        "-> #{@siala_output_dir}/spells.json"
    )

    Mix.shell().info(
      "[siala spells] #{length(matched)} matched a vanilla spell, " <>
        "#{length(records) - length(matched)} siala_only; " <>
        "#{length(facts)} facts from «Изменение в заклинаниях» on " <>
        "#{Enum.count(records, &(&1.changes != []))} pages"
    )

    Mix.shell().info(
      "[siala spells] numbers differ from vanilla on #{length(differing)} of " <>
        "#{Enum.count(records, &(&1.diff.differs != nil))} comparable; " <>
        "#{Enum.count(records, &(&1.diff.differs == nil))} could not be compared"
    )

    for record <- differing do
      Mix.shell().info(
        "[siala spells] differs: #{record.title}: " <>
          "ваниль #{inspect(record.diff.vanilla)} -> Сиала #{inspect(record.diff.siala)}"
      )
    end

    report_siala_spell_fields(records)

    for record <- records, record.siala_only? do
      Mix.shell().error("[siala spells] no vanilla counterpart: #{record.title} -> #{record.id}")
    end

    for record <- records, problem <- record.page.problems do
      Mix.shell().error("[siala spells] #{record.title}: #{problem}")
    end

    covered = records |> Enum.flat_map(& &1.vanilla_ids) |> MapSet.new()

    Mix.shell().info(
      "[siala spells] #{MapSet.size(covered)} of #{length(vanilla_spells.records)} vanilla " <>
        "spells are described on the Siala wiki; the other " <>
        "#{length(vanilla_spells.records) - MapSet.size(covered)} are assumed vanilla"
    )

    duplicates =
      records
      |> Enum.group_by(& &1.id, & &1.title)
      |> Enum.filter(fn {_id, titles} -> length(titles) > 1 end)

    for {id, titles} <- duplicates do
      Mix.shell().error("[siala spells] duplicate id #{id}: #{Enum.join(titles, ", ")}")
    end

    for record <- records, not Regex.match?(~r/^[a-z0-9_]+$/, record.id) do
      Mix.shell().error(
        "[siala spells] id is not an ASCII identifier: #{record.id} (#{record.title})"
      )
    end
  end

  # The field comparison is printed field by field rather than page by page: a
  # school that moved and a saving throw that changed are read by different
  # people, and "16 pages disagree somewhere" tells neither of them anything.
  # What could not be compared is printed just as loudly as what disagreed —
  # a silent gap here reads as agreement nobody checked.
  defp report_siala_spell_fields(records) do
    fields = for record <- records, field <- record.fields, do: {field.name, record, field}
    compared = Enum.uniq(for {name, _record, _field} <- fields, do: name)

    Mix.shell().info(
      "[siala spells] fields differ on #{Enum.count(records, &(&1.fields |> fields_differ()))} " <>
        "of #{Enum.count(records, &(&1.fields != []))} matched pages"
    )

    for name <- compared, verdict <- [:differs, :unreadable] do
      matching = for {^name, record, %{verdict: ^verdict} = field} <- fields, do: {record, field}

      Mix.shell().info(
        "[siala spells] #{name}: #{verdict} on #{length(matching)} of " <>
          "#{Enum.count(fields, &(elem(&1, 0) == name))}"
      )

      for {record, field} <- matching do
        Mix.shell().info(
          "[siala spells]   #{name} #{verdict}: #{record.title}: " <>
            "ваниль #{inspect(field.vanilla)} -> Сиала #{inspect(field.siala)}" <>
            if(field.reason, do: " (#{field.reason})", else: "")
        )
      end
    end

    Mix.shell().info(
      "[siala spells] differ from vanilla in numbers or in a field: " <>
        "#{Enum.count(records, &(&1.differs == true))}; " <>
        "#{Enum.count(records, &(&1.differs == false))} agree everywhere the machine looked; " <>
        "#{Enum.count(records, &(&1.differs == nil))} could not be checked at all"
    )
  end

  # A feat typed `class` that no class's progression table hands out. Two very
  # different things look alike here and the printout separates them: a feat
  # still reachable through a class's **bonus slot** or feat list (the rogue's
  # `crippling strike` at level 10, the ranger's `favored enemy`) is fine — the
  # player picks it, so no grant should exist — while one reachable by nothing is
  # a grant the table reader missed. Everything a class hands out for free is a
  # number on a character sheet, so a silent loss here is a wrong calculation.
  defp report_class_feats(%{records: feats}, %{records: classes}) do
    granted =
      for class <- classes, {_level, ids} <- class.granted_feats, id <- ids, into: MapSet.new() do
        id
      end

    orphans =
      for feat <- feats,
          feat.params["type"] == "class",
          not MapSet.member?(granted, feat.id),
          do: {feat.id, feat.classes}

    Mix.shell().info(
      "[feats] typed `class` but handed out by no class: #{length(orphans)} " <>
        "(a bonus slot or a class feat list is not a grant)"
    )

    for {id, classes} <- orphans do
      where = if classes == [], do: "no class names it at all", else: Enum.join(classes, ", ")
      Mix.shell().info("[feats] no grant: #{id} (#{where})")
    end
  end

  defp report_feat_links(%{records: records}, class_ids) do
    linked = Enum.count(records, &(&1.classes != []))

    unknown =
      records
      |> Enum.flat_map(& &1.classes)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(class_ids, &1))
      |> Enum.sort()

    Mix.shell().info("[feats] #{linked} feats reference a class")

    for id <- unknown do
      Mix.shell().error("[feats] class id not in classes.json: #{id}")
    end
  end
end
