defmodule BuildCalculator.Data.Loader do
  @moduledoc """
  Builds rulesets out of the JSON snapshots in `priv/rules/`.

  Runs **at compile time** (see `BuildCalculator.Data`), so malformed JSON breaks
  the build instead of production, and reading costs nothing at runtime.

  This module is the only place allowed to touch the filesystem; the rules core
  never does. It also owns every honest-but-unsourced assumption: each one is
  recorded in `ruleset.gaps` so the web layer (and a human reviewer) can see it.

  Layering is `vanilla` first, then the shard overrides from `siala_41` on top,
  per CLAUDE.md §3 ("Сиала переопределяет ваниль").

  ## Где что лежит (задача 3.46, заход 1)

  Модуль был один на 9662 строки с 39 разделами, размеченными комментариями;
  разделы стали модулями `BuildCalculator.Data.Loader.*`, а этот остался
  фасадом: наружу по-прежнему смотрят `source_files/0`, `load!/1`,
  `choice_domains/2,3` и `repeatable/1,3,4`, и больше ничего.

    * `Reading` — чтение JSON, общие словари, справочники значений выбора;
    * `Classes`, `Races`, `Feats`, `Skills`, `Spells`, `Gear` — по сущности,
      вместе с сиальским слоем каждой;
    * `Systems` — кастомные системы шарда и группы классов;
    * `Bonuses` — семь читателей разметки «что прибавляет к …»;
    * `Character` — потолки, формулы, эпик, престиж, поинт-бай;
    * `Gaps` — оговорки, которые ruleset несёт игроку.

  Сборка ruleset'а осталась здесь: она и есть то место, где перечисленное
  складывается в одну карту.
  """

  alias BuildCalculator.Data.Loader.Bonuses
  alias BuildCalculator.Data.Loader.Character
  alias BuildCalculator.Data.Loader.ClassFeatFacts
  alias BuildCalculator.Data.Loader.DualWield
  alias BuildCalculator.Data.Loader.Classes
  alias BuildCalculator.Data.Loader.FactReceivers
  alias BuildCalculator.Data.Loader.Feats
  alias BuildCalculator.Data.Loader.Gaps
  alias BuildCalculator.Data.Loader.Gear
  alias BuildCalculator.Data.Loader.Races
  alias BuildCalculator.Data.Loader.Reading
  alias BuildCalculator.Data.Loader.Skills
  alias BuildCalculator.Data.Loader.Spells
  alias BuildCalculator.Data.Loader.Systems

  # `read_json/2`, `dig/2` и `domain_files/1` зовутся здесь так же, как звались
  # внутри одного модуля: разрезание не должно было переписать ни одной строки
  # тела. Всё остальное общее ушло в `Reading` вместе со своими комментариями.
  import BuildCalculator.Data.Loader.Reading, only: [read_json: 2, dig: 2, domain_files: 1]

  @abilities Reading.abilities()
  @base_ac Reading.base_ac()

  @doc """
  Справочники значений выбора — см. `BuildCalculator.Data.Loader.Reading.choice_domains/3`.

  Делегат, а не копия: функция публична потому, что её зовёт `load!/1` и на неё
  ссылается ядро правил, а живёт она рядом с разрешением доменов.
  """
  @spec choice_domains(map(), map(), [atom()] | MapSet.t(atom())) :: %{atom() => map()}
  defdelegate choice_domains(domain_files, dictionaries, extra \\ []), to: Reading

  @doc """
  Блок повторяемости фита — см. `BuildCalculator.Data.Loader.Feats.repeatable/4`.

  Делегат по той же причине: на имя `Data.Loader.repeatable/1` ссылается
  `Rules.Vocabulary`, и разрезание не должно было эту ссылку сдвинуть.
  """
  @spec repeatable(term()) :: map() | nil
  defdelegate repeatable(block), to: Feats

  @spec repeatable(term(), term(), term()) :: map() | nil
  defdelegate repeatable(block, fallback_source, status), to: Feats

  @spec repeatable(term(), term(), term(), String.t() | nil) :: map() | nil
  defdelegate repeatable(block, fallback_source, status, where), to: Feats

  @doc "Relative paths, under `priv/rules/`, that a ruleset is built from."
  @spec source_files() :: [Path.t()]
  def source_files do
    [
      "name_map.json",
      "vanilla/classes.json",
      "vanilla/feats.json",
      "vanilla/races.json",
      "vanilla/skills.json",
      "vanilla/spells.json",
      "vanilla/epic.json",
      # Hand written, and registered by name for that reason: the directory entry
      # below only moves when a file is *added*, so editing this one would leave
      # the compiled ruleset stale.
      "vanilla/feat_skill_bonuses.json",
      # The same file for hit points, and named here for the same reason — see
      # `build_hp_bonuses/2`. ⚠ It is also listed in `@rules_files`: a
      # `vanilla/*.json` nobody claims is treated as a dictionary of choice
      # values (`domain_files/1`), and this one would have become a domain
      # called `feat_hp_bonuses` whose "values" are markup records.
      "vanilla/feat_hp_bonuses.json",
      # And the same file for armour class — see `build_ac_bonuses/4`. It is
      # named here and in `@rules_files` for exactly the two reasons above; the
      # second matters more here than for its siblings, because this file's
      # entries are keyed by four different things (feat, class, skill, race
      # feat) and a domain built out of them would have been a plausible-looking
      # dictionary of nothing.
      "vanilla/ac_bonuses.json",
      # И то же для самих характеристик — см. `build_ability_bonuses/2`. Здесь
      # оба списка нужны по тем же двум причинам, что у соседей; вторая опять
      # весомее: записи этого файла ключуются фитом ИЛИ классом, и словарь
      # «значений выбора» из них собрался бы правдоподобный на вид и пустой
      # по смыслу.
      "vanilla/feat_ability_bonuses.json",
      # Пятый файл этой формы, и по тем же двум причинам — см.
      # `build_save_bonuses/2`. Записи ключуются фитом, классом, навыком или
      # расовой склонностью (та же четвёрка, что у ac_bonuses.json), а не
      # только фитом — Sacred defense подтверждён ещё и колонкой таблицы
      # класса, Lucky и вся семья Hardiness vs. * приходят от расы.
      "vanilla/feat_save_bonuses.json",
      # Шестой и последний файл этой формы (задача 1.12b) — прибавки к БРОСКУ
      # АТАКИ. Тот же набор источников плюс пятый вид, `race`: расовый бонус
      # Сиалы принадлежит расе, а не её склонности, и уже считается своим
      # модулем — запись про него нужна ровно затем, чтобы следующая разведка
      # не завела ему второй. См. `build_attack_bonuses/2`.
      "vanilla/feat_attack_bonuses.json",
      # Седьмой файл этой формы (задача 3.45) — СОПРОТИВЛЕНИЕ ЗАКЛИНАНИЯМ. Здесь
      # он по тем же двум причинам, что шесть соседей, и обе нужны: правка файла
      # обязана пересобирать ruleset, а `vanilla/*.json`, которого никто не
      # назвал, читается как словарь значений для выбора (`domain_files/1`) —
      # то есть без второй записи появился бы домен `feat_spell_resistance`,
      # чьи «значения» на самом деле записи разметки.
      "vanilla/feat_spell_resistance.json",
      "vanilla/spellcasting.json",
      "vanilla/class_requirements.json",
      "vanilla/feat_requirements.json",
      "vanilla/grant_substitutions.json",
      # Which mechanic a repeatable feat's effect lands on, so a caveat about an
      # uncounted bonus is not printed for damage or a spell's save DC (task
      # 3.93). Hand written and registered by name for the same two reasons as
      # every file above it: the directory entry only moves when a file is
      # *added*, and a `vanilla/*.json` nobody claims is read as a dictionary of
      # choice values — this one would have become a domain called
      # `feat_effect_receivers` whose "values" are receiver labels.
      "vanilla/feat_effect_receivers.json",
      # Hand written for the same reason and registered the same way — see the
      # loader's `class_choices` read below and `@rules_files`.
      "vanilla/class_choices.json",
      # The word the game CLIENT prints for "this class's choice, left
      # unmade" (task 3.170) — a Wizard's `General`. Hand written and
      # registered the same way as the file above and for the same two
      # reasons: a directory's mtime does not move on an edit, and its
      # entries are keyed by CLASS id, so an unclaimed `vanilla/*.json`
      # would offer `wizard` as a pickable domain *value*. See
      # `Classes.build_class_choice_no_selection/2` and the file's own
      # `_note` for why it is not a field on `class_choices.json` itself.
      "vanilla/class_choice_no_selection.json",
      # The values dictionary `class_choices.json` draws its `domain` from.
      # Discovered generically through `domain_files/1` too (it is *not* in
      # `@rules_files`, on purpose — see `choice_domains/3`), but a hand
      # edit needs a named entry here the same way `class_requirements.json`
      # does, because the catch-all `"vanilla"` entry below only moves when a
      # file is *added* to the directory, not when an existing one is edited.
      "vanilla/domains.json",
      # ⚠️ The weapon dictionary (task 3.5), named for the same reason and found
      # the same way — and this one is not hypothetical: a corruption run during
      # 3.5 rewrote `weapons.json` and the compiled ruleset went on serving the
      # old 41-value gate, because only the `"vanilla"` directory entry covered
      # it and a directory's mtime does not move when a file is *edited*. That is
      # the wave-5 lesson `spellcasting_test.exs` records, reproduced.
      "vanilla/weapons.json",
      "siala_41/overrides.json",
      "siala_41/classes.json",
      "siala_41/races.json",
      "siala_41/skills.json",
      "siala_41/systems.json",
      "siala_41/generated/feats.json",
      # The hand-written feat layer does not exist yet. It is listed anyway:
      # `Mix.Utils.last_modified/1` reports 0 for a missing path, so creating it
      # later marks `BuildCalculator.Data` stale and the ruleset recompiles by
      # itself instead of silently keeping the machine layer alone.
      "siala_41/feats.json",
      # The hand-written spell layer (13.08.2026). There is no machine layer
      # under it: `generated/spells.json` is a comparison report and stays one —
      # see `apply_spell_layer/3` for why only the circle is lifted out of it.
      "siala_41/spells.json",
      # The **directory**, not a file. Choice-domain dictionaries
      # (`creature_types.json` and whatever the schools end up in) are discovered
      # by name at load time — see `domain_files/1` — so there is no path to
      # register in advance. A directory's mtime moves when a file is added to
      # it, which is exactly the staleness signal a named file would have given.
      "vanilla"
    ]
  end

  @doc """
  Reads `root` (a `priv/rules` directory) and returns `%{version => ruleset}`.

  Missing optional files (`skills.json` while data-miner is still on it) degrade
  into an empty dictionary plus an entry in `gaps`; they never raise.
  """
  @spec load!(Path.t()) :: %{optional(String.t()) => map()}
  def load!(root) do
    raw = %{
      classes: read_json(root, "vanilla/classes.json"),
      feats: read_json(root, "vanilla/feats.json"),
      races: read_json(root, "vanilla/races.json"),
      skills: read_json(root, "vanilla/skills.json"),
      spells: read_json(root, "vanilla/spells.json"),
      epic: read_json(root, "vanilla/epic.json"),
      # Which feats add a stated number to named skills. Hand written, because
      # the connection exists only as English prose in a feat's `description`
      # and no field of `feats.json` carries it — see `build_skill_bonuses/2`.
      feat_skill_bonuses: read_json(root, "vanilla/feat_skill_bonuses.json"),
      # And which feats add to hit points, read the same way and for the same
      # reason: `Toughness` says "one bonus hit point per character level" in
      # prose and in no field — see `build_hp_bonuses/2`.
      feat_hp_bonuses: read_json(root, "vanilla/feat_hp_bonuses.json"),
      # And what adds to armour class outside the equipment the player types:
      # a class ability, a feat, a skill, a racial trait. Hand written for the
      # third time and for the third time because the corpus has no field —
      # see `build_ac_bonuses/4`.
      ac_bonuses: read_json(root, "vanilla/ac_bonuses.json"),
      # И что прибавляет к самим характеристикам: `Great strength` с пятью
      # сёстрами и таблица роста статов РДД. Четвёртый ручной файл подряд и
      # по четвёртому разу потому, что поля в корпусе нет — см.
      # `build_ability_bonuses/2`.
      ability_bonuses: read_json(root, "vanilla/feat_ability_bonuses.json"),
      # И что прибавляет к спасброскам: Iron will и семья, Divine grace,
      # Sacred defense — пятый ручной файл подряд, и снова потому, что поля в
      # корпусе нет (задача 1.12a) — см. `build_save_bonuses/2`.
      feat_save_bonuses: read_json(root, "vanilla/feat_save_bonuses.json"),
      # И что прибавляет к БРОСКУ АТАКИ: `Epic prowess` и размерный модификатор
      # мелких рас — шестой ручной файл подряд, и по шестому разу потому, что
      # поля в корпусе нет (задача 1.12b). ⚠ Применяемых записей всего две:
      # прибавки к атаке в источниках почти все условные, и это вывод
      # разведки, а не недоделка — см. `build_attack_bonuses/2`.
      feat_attack_bonuses: read_json(root, "vanilla/feat_attack_bonuses.json"),
      # И что даёт СОПРОТИВЛЕНИЕ ЗАКЛИНАНИЯМ: `Diamond soul` Монаха и `Improved
      # spell resistance` — седьмой ручной файл подряд, и по седьмому разу
      # потому, что поля в корпусе нет (задача 3.45). ⚠ Применяемых записей две,
      # и это результат сплошной разведки, а не недоделка: SR во всём корпусе
      # дают ровно два фита, ни один класс, навык или раса — ни одного. См.
      # `build_spell_resistance/2`.
      feat_spell_resistance: read_json(root, "vanilla/feat_spell_resistance.json"),
      # Facts about casting that no template on either wiki carries: the minimum
      # ability score a circle needs, and the prestige classes that push another
      # class's slot table. Both live as prose on Fandom — see
      # `casting_ability_minimum/1` and `prestige_advancement/2`.
      spellcasting: read_json(root, "vanilla/spellcasting.json"),
      # Prestige class requirements whose meaning is in the page's prose rather
      # than in its requirements block — «the spellcasting requirement refers to
      # the caster level required, not the level of spell that can be cast». Hand
      # written for the same reason as the file above, and checked against the
      # machine layer it replaces — see `apply_class_requirements/3`.
      class_requirements: read_json(root, "vanilla/class_requirements.json"),
      # A feat's own prerequisite, read the same way and for the same reason:
      # `Curse song` carries `prereq=-` and the class it is actually usable by
      # sits in a "Notes" sentence instead — see `apply_feat_requirements/4`.
      feat_requirements: read_json(root, "vanilla/feat_requirements.json"),
      # A class level whose table says "grants a feat" but which actually offers
      # the class's bonus list — see `grant_substitutions/2` and `GAME_CHECKS.md`
      # M2 / M2b.
      grant_substitutions: read_json(root, "vanilla/grant_substitutions.json"),
      # Which mechanic a feat's effect lands on — damage, a spell's save DC,
      # metamagic — so that «прибавку от этого фита в статы не считаем» is only
      # said about a number we actually print (task 3.93). Hand written for the
      # same reason as the three files above: the fact lives in a feat page's
      # own description, and `vanilla/feats.json` is rewritten wholesale by
      # `mix wiki.parse`. See `feat_effect_receivers/3`.
      feat_effect_receivers: read_json(root, "vanilla/feat_effect_receivers.json"),
      # Which classes ask for a one-time, held-forever pick out of a named
      # domain when their OWN first class level is taken — a Cleric's two
      # domains, later a Wizard's school (task 3.10). Hand written for the
      # same reason as the two files above: the fact lives in a class page's
      # prose, not in a machine-readable field of `classes.json`. See
      # `build_class_choices/2`.
      class_choices: read_json(root, "vanilla/class_choices.json"),
      # The word the client prints for that same choice left unmade — a
      # Wizard's `General` (task 3.170). Separate file on purpose; see
      # `class_choice_no_selection.json`'s own `_note` and
      # `Classes.build_class_choice_no_selection/2`.
      class_choice_no_selection: read_json(root, "vanilla/class_choice_no_selection.json"),
      name_map: read_json(root, "name_map.json"),
      # Dictionaries a feat's choice is drawn from, keyed by file basename. Not
      # listed by name: which domains exist is stated by the feats themselves
      # (`repeatable.choice`), so naming the files here would be one more place
      # to keep in step. See `choice_domains/2`.
      domain_files: domain_files(root)
    }

    shard = %{
      overrides: read_json(root, "siala_41/overrides.json"),
      classes: read_json(root, "siala_41/classes.json"),
      races: read_json(root, "siala_41/races.json"),
      skills: read_json(root, "siala_41/skills.json"),
      # Not a rules file: the shard's ten custom systems, each with a verdict on
      # whether it belongs in the calculator at all. Only one does (`stat_caps`),
      # and that one is transcribed machine-readably in `overrides.json` — this is
      # read so the verdicts are visible and so the two statements of the caps can
      # be checked against each other (`verify_stat_caps!/2`).
      systems: read_json(root, "siala_41/systems.json"),
      # `vanilla -> siala generated -> siala manual` (priv/rules/siala_41/README).
      # The machine layer is rewritten wholesale by `mix wiki.parse`; a hand
      # written record beside it overrides the machine's, fact by fact, which is
      # why both are read and applied in this order.
      feats_generated: read_json(root, "siala_41/generated/feats.json"),
      feats_manual: read_json(root, "siala_41/feats.json"),
      # Spells are the one place where the machine layer is deliberately NOT
      # applied: `generated/spells.json` compares 128 pages against vanilla and
      # 115 of them differ, but the differences are effects the calculator does
      # not compute (damage, save, duration, school). Only the circle reaches an
      # answer we print, and only for the two classes that pick known spells —
      # so the circle is lifted by hand, one measured record at a time.
      spells_manual: read_json(root, "siala_41/spells.json")
    }

    %{
      "vanilla" =>
        ruleset("vanilla", raw, %{
          overrides: vanilla_sections(shard.overrides),
          classes: :missing,
          races: :missing,
          skills: :missing,
          systems: :missing,
          feats_generated: :missing,
          feats_manual: :missing,
          spells_manual: :missing
        }),
      "siala_41" => ruleset("siala_41", raw, shard)
    }
  end

  # Sections of the shard file that are not the shard's: vanilla NWN rules that
  # have nowhere else to live because `vanilla/` is machine-generated and a hand
  # written fact there would be wiped by the next `mix wiki.parse`. Both rulesets
  # see these; everything else in `overrides.json` is Siala's alone.
  @vanilla_sections ~w(stat_caps gear formulas _vanilla_constants_confirmed)

  defp vanilla_sections(:missing), do: :missing
  defp vanilla_sections(overrides), do: Map.take(overrides, @vanilla_sections)

  # ---------------------------------------------------------------- ruleset --

  defp ruleset(version, raw, shard) do
    epic = require_map!(raw.epic, "vanilla/epic.json")
    ov = if shard.overrides == :missing, do: %{}, else: shard.overrides

    skill_rules = Skills.skill_rules(shard.skills, ov)

    {skills, skill_class_facts} =
      raw.skills |> Skills.build_skills() |> Skills.apply_skill_layer(shard.skills, skill_rules)

    systems = Systems.build_systems(shard.systems)
    Systems.verify_stat_caps!(systems, ov)

    vanilla_classes =
      raw.classes
      |> Classes.build_classes(skills)
      |> Classes.apply_class_requirements(
        Map.get(raw, :class_requirements, :missing),
        raw.classes
      )

    # Read (and checked) before the layer is applied: a receiver outside the
    # vocabulary must fail the build, not half-load a filtered gap list.
    gap_receivers = FactReceivers.gap_receivers!(shard.classes)

    # The same vocabulary, checked again against the feat layer — task "фиты:
    # получатели у фактов" (data-miner, 14.08.2026). There is one `_receivers`
    # dictionary, declared once on `siala_41/classes.json`; the feat files
    # never declare a second one, they only ever *use* this one, so the check
    # runs against `gap_receivers` rather than re-reading `_receivers` here.
    known_receivers = MapSet.union(gap_receivers.our, gap_receivers.not_our)
    FactReceivers.verify_feat_affects!(shard.feats_generated, known_receivers)
    FactReceivers.verify_feat_affects!(shard.feats_manual, known_receivers)

    # The same vocabulary, checked a third time against the skill layer —
    # data-miner, 14.08.2026. `siala_41/skills.json` declares no `_receivers`
    # of its own either, same as the feat files above, and for the same
    # reason (one dictionary, `classes.json`'s).
    FactReceivers.verify_skill_affects!(shard.skills, known_receivers)

    # Словарь семейств фитов, которыми шард расширяет бонусные пулы классов
    # (`_bonus_feat_pools`). Прочитан и выверен ДО слоя, по той же причине,
    # что `gap_receivers!/1` выше: селектор вне словаря обязан уронить сборку,
    # а не применить половину фактов.
    # Вторым аргументом — реестр пяти фитов владения из `weapons.json`: одна
    # из двух категорий словаря названа семейством «Системы оружия», а по полю
    # записи фита его не выбрать (у пятёрки обычный `type: "general"`).
    # Справочник оружия здесь ещё не собран и не нужен — читается сам реестр.
    bonus_feat_pools =
      Classes.bonus_feat_pools!(shard.classes, Gear.proficiency_feat_ids(raw))

    {shard_classes, attack_modifiers} =
      Classes.apply_class_layer(vanilla_classes, shard.classes, bonus_feat_pools)

    {vanilla_feats, vanilla_feat_class_facts} =
      raw.feats
      |> Feats.build_feats()
      |> Feats.apply_feat_requirements(
        Map.get(raw, :feat_requirements, :missing),
        raw.feats,
        raw.classes
      )

    {feats, feat_class_facts} = Feats.apply_feat_layer(vanilla_feats, shard)

    # И сразу же — расширение бонусных пулов, снятое со страниц КЛАССОВ
    # и уложенное в `bonus_for` самих фитов (задача 3.73). Здесь, а не ниже:
    # `bonus_for` читает всё, что строится дальше, и «финальный» справочник
    # фитов должен быть финальным до первого читателя. Требования фитов
    # (`qualifying_class_levels`) к этому моменту уже применены —
    # расширение их спрашивает.
    feats = Feats.widen_bonus_pools(feats, shard_classes)

    # ⚠️ Здесь стояли два вызова, вливавших `feat_skill_bonuses.json` и
    # `feat_hp_bonuses.json` в ПОЛЯ ФИТА (`hp_bonus`, `unmodelled_hp_bonus`,
    # `skill_bonuses`, `unmodelled_skill_bonus`). Задача 3.25 перевела оба файла
    # на общую форму, и теперь они собираются списками записей ниже, рядом с
    # четырьмя остальными — `build_skill_bonuses/2` и `build_hp_bonuses/2`. Порядок
    # в конвейере от этого сдвинулся вниз, и это не косметика: записям нужны
    # ФИНАЛЬНЫЕ словари (классы после слоя Сиалы, расы после `apply_race_layer/2`),
    # потому что у записи появился вид источника `race_feat`, а расы строятся
    # позже фитов.

    # After the class layer on purpose: a feat page that restates a level shift
    # the class page already stated must land on the same map, not shift it
    # twice. `move_grant/4` is idempotent, so restating it is a no-op.
    #
    # The skill pages restate class-skill membership from the other side
    # («Навыки Скрытность и Тихое передвижение сделаны классовыми» on Чёрный
    # страж), and that lands here for the same reason: a union is idempotent, so
    # a fact stated twice is applied once.
    # ⚠ Vanilla facts first, shard facts second, and the order is the whole
    # override rule: `:forbid_for` **replaces** the set of classes that refuse a
    # feat, so a shard page stating the restriction in full wins over what
    # Fandom's prose said (CLAUDE.md §3). `:forbid_for_all_but` — the vanilla
    # side's shape — is a union, so the two never fight over a feat neither
    # names.
    classes =
      shard_classes
      |> ClassFeatFacts.apply_feat_class_facts(vanilla_feat_class_facts)
      |> ClassFeatFacts.apply_feat_class_facts(feat_class_facts)
      |> Skills.apply_skill_class_facts(skill_class_facts)
      |> ClassFeatFacts.drop_disabled_grants(feats)

    # Runs here rather than beside `apply_feat_requirements/4`, because it needs
    # both finished dictionaries: the requirement it checks names skills on one
    # side and classes on the other.
    ClassFeatFacts.verify_choice_class_restrictions!(feats, skills, classes)

    repeat_grants = Classes.repeated_grants(classes)
    spellcasting = Map.get(raw, :spellcasting, :missing)

    Spells.verify_spellcasting_applied!(
      spellcasting,
      feats,
      Map.get(raw, :feat_requirements, :missing)
    )

    level_cap = level_cap(epic, ov)
    spell_lists = Spells.spell_lists(ov)

    races =
      raw.races
      |> Races.build_races()
      |> Races.apply_race_layer(shard.races)
      |> ClassFeatFacts.drop_disabled_race_feats(feats)

    spells =
      raw.spells
      |> Spells.build_spells(spell_lists)
      |> Spells.apply_spell_layer(Map.get(shard, :spells_manual, :missing), spell_lists)

    # ⚠ `version` — не для того, чтобы загрузчик знал шард по имени. Секция
    # `gear` общая (`@vanilla_sections`) и раздаётся обоим ruleset'ам байт в
    # байт, а внутри неё у части чисел есть сиальский двойник; какой версии
    # он принадлежит, называет сама секция, и здесь передаётся только то,
    # с чем ей сравнивать (задача 3.141).
    gear = Gear.gear(ov, version)
    caps = Character.stat_caps(ov)
    Gear.verify_ac_type_ceilings!(gear, caps)
    # Which sources each ceiling covers, per source kind — read beside the
    # numbers and cross-checked below, once the things it talks about exist.
    cap_sources = Character.stat_cap_sources(ov)

    # The shard's own groupings of classes — «Воины Сагры», «Воины Адры». Built
    # after the class layer, because the membership relation is read off the
    # finished classes, and before the racial bonuses, because one of their four
    # numbers is stated for a member of one of these groups.
    # ⚠ И `known_receivers` четвёртым аргументом — с задачи 3.100: у выгод группы
    # есть та же метка получателя, что у фактов класса, и она проверяется тем же
    # закрытым словарём. Второго словаря в проекте нет и быть не должно.
    class_groups = Systems.class_groups(systems, classes, shard.races, known_receivers)

    # ⚠ Hoisted above the racial bonuses on 15.08.2026, and not for tidiness:
    # since Dan's measurement the racial bonus is switched on by a weapon in the
    # character's hands, so its own activation record names weapon ids and they
    # have to be checked against this dictionary like every other name in the
    # shard layer. Everything it needs (`feats`) is built well above.
    weapons = Gear.weapons(raw, ov, feats)

    # Правило хвата (задача 3.43): лестница размеров и два порога. Читается
    # рядом со справочником, а сверяется с расами ниже — тот же приём, что
    # у `not_wieldable_weapons!/2`: один и тот же факт записан дважды, и
    # расхождение обязано ронять сборку, а не всплывать у игрока.
    wield = Gear.wield(raw)
    Gear.verify_large_weapon_bans!(wield, races, weapons)
    Gear.verify_worn_restrictions!(gear.worn, races)

    # The shard's own racial bonus — read since task 3.12, whereas before it was
    # carried whole under `race.siala` and modelled by nothing. Needs five
    # dictionaries and both ceilings, so it is built here rather than beside the
    # races: every name it states is checked, and the ceiling it claims is
    # cross-checked against the one the core actually clips at.
    racial_bonuses =
      Races.racial_bonuses(shard.races, %{
        races: races,
        classes: classes,
        skills: skills,
        weapons: weapons,
        ac_types: gear.ac_types,
        stat_caps: caps,
        class_groups: class_groups
      })

    # And the same system seen from the other side (task 3.35): the bonus the
    # shard gives for the **type of weapon in hand**. Built beside the racial
    # bonus and out of the same five dictionaries, because the two are the same
    # bonus on the shard's own pages and are added together in the game (Dan's
    # measurement, `GAME_CHECKS.md` Q1) — keeping them apart in the loader while
    # they share a level rule, a class group and an AC type would be two
    # transcriptions of one page.
    weapon_type_bonuses =
      Races.weapon_type_bonuses(systems, %{
        weapons: weapons,
        skills: skills,
        ac_types: gear.ac_types,
        class_groups: class_groups
      })

    Races.verify_weapon_type_bonus_caps!(weapon_type_bonuses, caps)

    # Armour class from the build itself, as opposed to from the equipment the
    # player types. Built last of the dictionaries because it names all four of
    # them and every name is checked against the real thing.
    ac_bonuses =
      Bonuses.build_ac_bonuses(Map.get(raw, :ac_bonuses, :missing), %{
        classes: classes,
        feats: feats,
        skills: skills,
        races: races,
        # ⚠ A fifth dictionary the other five files of this shape do not need: a
        # `scope` names the AC **types** whose worn item takes the bonus away.
        # Checked against the very list the input block offers, so the two
        # cannot drift.
        ac_types: gear.ac_types,
        # ...and against the types something can actually be **worn** in, which
        # is the half that decides whether the condition can ever fire at all.
        # Since 19.08.2026 `Rules.ArmorClass.in_scope?/3` reads `Worn.base_ac/2`
        # and nothing else («числа в "AC по типам" не влияют» — Dan), so a scope
        # naming `deflection` would be a rule that quietly never applies. Before
        # that day the typed number was read too and any enterable type could
        # fire it; the guard moved with the rule rather than staying behind it.
        worn_ac_types: Enum.map(gear.worn, & &1.ac_type),
        # `changes[].affects`'s closed vocabulary — same one `known_receivers`
        # already checked the shard's own class/feat/skill facts against. See
        # `verify_bonus_affects!/4` for why this file (vanilla, shared by both
        # rulesets) is checked more gently than a siala-only layer.
        known_receivers: known_receivers
      })

    # And the same for the ability scores themselves. Two dictionaries instead
    # of four: this file's sources are a feat or a class table and nothing
    # else, because no race and no skill raises an ability — checked, and
    # written down in the file's `_double_counting_check` rather than left as
    # an absence somebody would have to rediscover.
    ability_bonuses =
      Bonuses.build_ability_bonuses(Map.get(raw, :ability_bonuses, :missing), %{
        classes: classes,
        feats: feats,
        known_receivers: known_receivers
      })

    # And the same for saving throws (task 1.12a): Iron will and its siblings,
    # Divine grace's charisma, Sacred defense's class table. Four dictionaries
    # again, the same reason `ac_bonuses` needs four: a bonus arrives off a
    # feat, a class table, a skill (Bard song) or a racial trait (Lucky,
    # Hardiness vs. *) — see `build_save_bonuses/2`.
    save_bonuses =
      Bonuses.build_save_bonuses(Map.get(raw, :feat_save_bonuses, :missing), %{
        classes: classes,
        feats: feats,
        skills: skills,
        races: races,
        # ⚠ Словарь тот же, что у четырёх соседей, хотя размечать этому файлу
        # сегодня нечего: `affects` в нём не стоит ни на одной записи. Стоит он
        # здесь, чтобы разметка, когда её проставят, заработала сама, — см.
        # `affects:` в `save_bonus_record/2`.
        known_receivers: known_receivers
      })

    # And the same for the attack bonus (task 1.12b) — the sixth and last file
    # of this shape. FIVE dictionaries here, one more than the saves need: a
    # record may be keyed by the **race itself** rather than by one of its
    # traits, because the shard's own racial bonus belongs to the race and is
    # already counted by `Rules.RacialBonus` — see `build_attack_bonuses/2`.
    attack_bonuses =
      Bonuses.build_attack_bonuses(Map.get(raw, :feat_attack_bonuses, :missing), %{
        classes: classes,
        feats: feats,
        skills: skills,
        races: races,
        # ⚠ Шестой словарь, которого не просит ни один сосед (задача 3.101):
        # запись может назвать оружие ПЕРЕЧИСЛЕНИЕМ, а не выбором фита
        # (`Enchant arrow` — «only for bows», и состав «луков» источник даёт
        # списком). Имя, которого в справочнике нет, обязано ронять сборку:
        # прибавка, которую не получит никто, — то же тихое занижение, от
        # которого стоит остальная стража этого файла.
        weapons: weapons,
        known_receivers: known_receivers
      })
      # ⚠ И сразу же — расширение оружия тем, что шард дописал КЛАССУ (задача
      # 3.101): «Все классовые умения Тайного лучника теперь распространяются
      # на малый и большие арбалеты». Здесь, а не в самой разметке, потому что
      # правило принадлежит классу, и второй его записи в файле прибавок
      # заводиться не должно (урок задачи 3.85). У ванильного ruleset'а
      # не меняется ничего: цитата принадлежит Сиале.
      |> Bonuses.widen_class_ability_weapons(classes)

    # И то же для HP — тот самый файл задачи 1.9, переведённый на общую форму
    # задачей 3.25. Четыре словаря, как у соседей: величина `per_class_level`
    # называет класс, а вид источника может быть расовой склонностью.
    hp_bonuses =
      Bonuses.build_hp_bonuses(Map.get(raw, :feat_hp_bonuses, :missing), %{
        classes: classes,
        feats: feats,
        skills: skills,
        races: races,
        known_receivers: known_receivers
      })

    # И для навыков — второй из двух файлов, переведённых задачей 3.25.
    #
    # ⚠ Пятый словарь, которого не просит ни один сосед: `skill_rules` идёт сюда не
    # для удобства, а потому что поле `counted_for_classes` («чью версию умения ядро
    # уже считает») верно только для того ruleset'а, чей слой навыков это правило
    # строит — см. `build_skill_bonuses/2`.
    skill_bonuses =
      Bonuses.build_skill_bonuses(Map.get(raw, :feat_skill_bonuses, :missing), %{
        classes: classes,
        feats: feats,
        skills: skills,
        races: races,
        class_level_bonuses: skill_rules.class_level_bonuses,
        known_receivers: known_receivers
      })

    # И то же для СОПРОТИВЛЕНИЯ ЗАКЛИНАНИЯМ (задача 3.45) — седьмой файл этой
    # формы. Четыре словаря, как у соседей, хотя заполнен сегодня только `feat`:
    # величина `class_level_plus` называет класс, а вид источника схемой
    # разрешён тот же четырёхчастный — сужать его здесь значило бы завести
    # седьмую разновидность общего механизма ради файла, у которого таких
    # записей просто нет.
    spell_resistance =
      Bonuses.build_spell_resistance(Map.get(raw, :feat_spell_resistance, :missing), %{
        classes: classes,
        feats: feats,
        skills: skills,
        races: races,
        known_receivers: known_receivers
      })

    # ⚠ Два механизма кладут прибавку в ОДИН терм значения навыка (`class_bonus`),
    # и разъехаться они обязаны громко: правило слоя навыков и запись разметки с
    # `amount.kind: class_level_sum`. Здесь, а не в `skill_rules/2`, ровно потому,
    # что раньше разметки ещё нет. См. `verify_skill_class_bonuses!/3`.
    Skills.verify_skill_class_bonuses!(
      skill_rules.class_level_bonuses,
      skill_bonuses,
      shard.skills
    )

    # ⚠ Every mechanism the core offers to a ceiling must be classified as inside
    # it or on top of it, and the two facts stated twice must agree — see
    # `verify_cap_sources!/4`. Runs here rather than beside `stat_cap_sources/1`
    # because it needs the races' and the skill rules' own claims about a ceiling.
    Character.verify_cap_sources!(caps, cap_sources, racial_bonuses, skill_rules.save_bonus)

    # A one-time, held-forever choice a class asks for when its OWN first
    # class level is taken — a Cleric's two domains. Built before
    # `choice_domains/3` so its `domain` names can widen that table's set: see
    # the note there and on `class_choices.json`.
    class_choices = Classes.build_class_choices(Map.get(raw, :class_choices, :missing), classes)

    # The word the client prints for that same choice left unmade (task
    # 3.170) — layered on top rather than read inside `build_class_choices/2`
    # itself, the same "verify, then apply" shape `apply_class_requirements/3`
    # uses: the mechanic above is unconditionally correct already and this
    # cannot change it, only add a display fact `:no_selection_name` never
    # omits (`nil` for every class the file does not name, a Cleric
    # included).
    class_choices =
      Classes.build_class_choice_no_selection(
        Map.get(raw, :class_choice_no_selection, :missing),
        class_choices
      )

    class_choice_domains = for {_id, spec} <- class_choices, do: spec.domain

    # After every dictionary is built: a domain may resolve *to* one of them
    # (`skill` → `skills`), so this cannot run earlier.
    domains =
      choice_domains(
        Map.get(raw, :domain_files, %{}),
        %{
          feats: feats,
          skills: skills,
          races: races,
          classes: classes,
          spells: spells
        },
        class_choice_domains
      )
      # И сразу же — значения, которых у фитов ЭТОГО ruleset'а нет вовсе
      # (задача 3.108, замер `GAME_CHECKS.md` AC6). Здесь, а не в справочнике:
      # `vanilla/weapons.json` переписывается `mix wiki.parse` целиком, а факт
      # принадлежит шарду — у ванили `Weapon focus (Creature weapon)` законен.
      # Тот же приём и та же секция, что у `weapons.absent_on_shard`, и по той же
      # причине: `gear` виден обоим ruleset'ам, `weapons` — только шарду.
      |> Reading.close_feat_variants!(feats, ov)

    # После словарей, а не рядом с `verify_choice_class_restrictions!/3`: имена
    # значений проверяются по домену выбора, а домены строятся здесь и позже
    # классов.
    ClassFeatFacts.verify_class_feat_choices!(classes, feats, domains)
    ClassFeatFacts.verify_class_feat_choice_properties!(classes, feats)
    ClassFeatFacts.verify_class_feat_choice_excludes!(classes, feats, domains)

    # Куда падает эффект фита (задача 3.93). После финального справочника фитов,
    # потому что каждое имя в файле сверяется с ним, и рядом с ним же — словарь
    # получателей, тот самый единственный, что уже проверил факты классов,
    # фитов и навыков выше.
    feat_effect_receivers =
      Feats.feat_effect_receivers(
        Map.get(raw, :feat_effect_receivers, :missing),
        feats,
        known_receivers
      )

    %{
      version: version,
      layers: layers(version),
      level_cap: level_cap,
      max_classes: dig(ov, ["character", "max_classes", "value"]),
      # «Дух Сиалы» — a flat, once-per-character hit point bonus the shard
      # hands every character, regardless of level or class. `nil` for the
      # vanilla ruleset unconditionally, the same way `max_classes` above is:
      # `"character"` never survives `vanilla_sections/1`, so `ov` has
      # nothing under that key to read. See `innate_hp_bonus/1`.
      innate_hp_bonus: Character.innate_hp_bonus(ov),
      epic_starts_at: Map.fetch!(epic, "epic_starts_at_character_level"),
      base_ac: @base_ac,
      abilities: @abilities,
      classes: classes,
      races: races,
      feats: feats,
      # Выдачи, которые на самом деле выбор (`vanilla/grant_substitutions.json`).
      # Сегодня одна — `Weapon of choice` Мастера оружия; читают
      # `Rules.FeatSlots` (слот появляется) и `Rules.Build` (выдача исчезает),
      # и обе половины обязаны читать одно и то же место, иначе фит окажется
      # и выданным, и выбираемым.
      grant_substitutions:
        Spells.grant_substitutions(Map.get(raw, :grant_substitutions, :missing), classes),
      # What a feat that takes a parameter may be taken *with*, keyed by the
      # domain the feat names. `values: nil` means "no dictionary" — an answer,
      # not an omission; see `choice_domains/2`.
      choice_domains: domains,
      # The weapons themselves, as the rules read them: whether each is an item a
      # character can hold, and which proficiency feat it asks for (task 3.5
      # part B). The same file also feeds `choice_domains[:weapon]` above, and the
      # ids are deliberately one set — a weapon a focus was taken with and a
      # weapon in the character's hands have to match by name. See `weapons/3`.
      weapons: weapons,
      # Как из двух размеров — оружия и владельца — получается хват, и когда
      # оружие не взять вовсе (задача 3.43). Читает `Rules.Wield`; `size_order:
      # []` означает «снапшот про размеры не сказал», и ядро говорит об этом
      # гэпом вместо того, чтобы разрешить всё.
      wield: wield,
      # Таблица штрафов боя двумя оружиями (задача 3.132), из того же файла, что
      # и прибавки к атаке: получатель у неё тот же — бросок атаки. ⚠ `nil`
      # значит «блока нет», и ядро говорит об этом гэпом вместо того, чтобы
      # считать бой двумя оружиями бесплатным. Читает `Rules.DualWield`.
      dual_wield:
        DualWield.build(
          Map.get(raw, :feat_attack_bonuses, :missing),
          feats,
          gear.worn
        ),
      # Classes with a one-time choice at their own first class level — see
      # `build_class_choices/2` and `BuildCalculator.Rules.ClassChoices`. The
      # values themselves are not carried here a second time: read them
      # through `choice_domains[spec.domain]`, same as a feat's choice would.
      class_choices: class_choices,
      skills: skills,
      # Skill rules that are not properties of one skill: the Spellcraft
      # contribution to every saving throw and the stealth penalty a build of
      # four classes takes. See `skill_rules/2`.
      skill_rules: skill_rules,
      # The shard's custom systems with their verdicts, carried so the interface
      # can show what the calculator knowingly leaves out. ⚠ Eight of the ten do
      # not reach a build's numbers: the ceilings always did, and since
      # 08.08.2026 (Dan: «сагровик получит больше бонусов, чем несагровик») the
      # class groups do too — through the racial bonus's own variant, see
      # `class_groups` below and CLAUDE.md §3.
      systems: systems,
      # Groups a *build* belongs to when its class list lines up, assembled out
      # of three independent statements and cross-checked. `[]` for vanilla,
      # which has no such thing. See `class_groups/2` and
      # `BuildCalculator.Rules.ClassGroups`.
      class_groups: class_groups,
      # The closed vocabulary of `changes[].affects` — which receivers the
      # calculator prints and which it does not (`gap_receivers!/1`). Two empty
      # sets for vanilla, which has no shard facts to label; read by
      # `BuildCalculator.Rules.GapReceivers`, which then answers whether a fact
      # is a gap in our answer at all.
      gap_receivers: gap_receivers,
      # И на какую механику падает эффект ПОВТОРЯЕМОГО фита — задача 3.93.
      # Читает `Rules.FeatChoices`: оговорка «прибавку от этого фита в статы
      # не считаем» полагается только про число, которое мы печатаем, а урон,
      # ДЦ чужого спасброска и метамагия к таким не относятся. Запись лежит
      # сырой, потому что её судит `GapReceivers.ours?/2` — та же функция,
      # что судит факты шарда, и по тому же полю `affects`.
      feat_effect_receivers: feat_effect_receivers,
      spells: spells,
      spell_lists: spell_lists,
      # Casting rules that are not a property of one class table: the minimum
      # ability score a circle asks for, the bonus slots a high casting ability
      # grants, the prestige classes that advance
      # somebody else's slots, and the classes whose own one-time choice
      # (`Rules.ClassChoices`) bends their own table — a Wizard's school
      # (AGENT_QUEUE.md §3.10). Hand written (`vanilla/spellcasting.json`)
      # because all three are prose on Fandom, and read here so no class id is
      # ever named in `Rules.Spells` (CLAUDE.md §5).
      casting: %{
        ability_minimum: Spells.casting_ability_minimum(spellcasting),
        # The table of bonus slots a high casting ability grants (task 3.70),
        # keyed by ability modifier, plus the source's own formula for it — the
        # loader has already checked the two agree on all 234 cells.
        bonus_slots: Spells.bonus_spell_slots(spellcasting),
        # Which casters are **spontaneous**, as a `MapSet` — the two classes one
        # sentence of `fandom:Spell focus` grants a weaker reading of «ability to
        # cast Nth level spells» to (task 3.124). `nil` when the file has no such
        # record, and then nobody gets the exception and a gap says so.
        spontaneous: Spells.spontaneous_casters(spellcasting, classes),
        advancement: Spells.prestige_advancement(spellcasting, classes),
        school_specialization: Spells.school_specialization(spellcasting, classes)
      },
      # What the build itself adds to armour class — a class ability, a feat, a
      # skill, a racial trait — as opposed to the equipment the player types.
      # `%{applied: […], unmodelled: […]}`; see `build_ac_bonuses/2` and
      # `Rules.ArmorClass`.
      ac_bonuses: ac_bonuses,
      # What the build itself adds to the **ability scores** — `Great strength`
      # and its five siblings, a Red Dragon Disciple's own table. Same shape
      # and same contract as `ac_bonuses` above; see `build_ability_bonuses/2`
      # and `Rules.AbilityBonuses`. ⚠ These land in the *naked* score, before
      # gear: the source itself splits «base scores» (point buy, race, level
      # increases, these feats) from «magical means» (items and spells, capped
      # at +12) — see `_order_decision` in the file.
      ability_bonuses: ability_bonuses,
      # What the build itself adds to Fort/Ref/Will — `Iron will` and its
      # siblings, `Divine grace`'s charisma, `Sacred defense`'s class table
      # (task 1.12a). Same shape as `ac_bonuses`/`ability_bonuses`; see
      # `build_save_bonuses/2` and `Rules.SaveBonuses`. ⚠ Unlike those two
      # ceilings, this one is not the whole story: `Rules.compute/2` combines
      # it with `build.gear.saves` and Spellcraft's rule under **one** ceiling
      # per save, per `_cap_decision` in the file — a source here is never
      # clipped on its own.
      save_bonuses: save_bonuses,
      # And what the build itself adds to the **attack roll** — `Epic prowess`
      # (task 1.12b). Same shape as the three above; see `build_attack_bonuses/2`
      # and `Rules.AttackBonuses`. The same ceiling caveat holds and is tighter
      # here: `Rules.compute/2` puts these terms under the **one** `attack_bonus`
      # clip it already shares with the gear bonus and the shard's racial bonus
      # (task 3.12), never a clip of their own.
      #
      # ⚠ A small race's size modifier sat here too until task 3.143
      # (30.08.2026): its condition ("when dealing with larger creatures") had
      # been read off a quote truncated one clause short, and the fix moved it
      # to `not_modelled`.
      attack_bonuses: attack_bonuses,
      # And what the build itself adds to **hit points** — `Toughness` at one per
      # character level, `Epic toughness` at twenty per take (task 1.9). Same shape
      # as the four above since task 3.25; before it these records were poured into
      # `feats[id].hp_bonus` instead, which is why `Rules.FeatBonuses` could share
      # only half of the common plumbing. ⚠ No ceiling clips them: no ruleset states
      # one for hit points at all, and `cap` on a record of this file raises — see
      # `_cap_decision` in it.
      hp_bonuses: hp_bonuses,
      # And to a **named skill** — `Alertness`'s +2 Spot/Listen and seven siblings,
      # plus what cannot be counted honestly (a size modifier the character sheet
      # does not even show). Same shape and the same task; the one field its five
      # siblings lack is `counted_for_classes`, because only here does one id cover
      # two implementations with different fates — see `build_skill_bonuses/2`.
      skill_bonuses: skill_bonuses,
      # И что даёт **сопротивление заклинаниям** — `Diamond soul` (уровень монаха
      # + 10) и `Improved spell resistance` (+2 за взятие, потолок эффекта +20),
      # задача 3.45. Та же форма, что у шести выше; см. `build_spell_resistance/2`
      # и `Rules.SpellResistance`. ⚠ Потолка на SR не объявляет ни один ruleset,
      # поэтому `cap` у записи этого файла роняет сборку — как у `hp_bonuses`, и
      # по той же причине. ⚠ И складывать источники SR можно **не всегда**:
      # два наших складываются потому, что страница говорит это дословно, а
      # предмет с SR не прибавляется, а конкурирует — см. `_stacking_decision`.
      spell_resistance: spell_resistance,
      # And the shard's own racial bonus, which is neither: it lands on the
      # attack bonus, on armour class or on one skill depending on the race, and
      # its value is known only at the level the wiki states it for. `nil` for
      # vanilla, which has no such thing at all. See `racial_bonuses/2` and
      # `Rules.RacialBonus`.
      racial_bonuses: racial_bonuses,
      # And the same bonus seen from the weapon's side (task 3.35): what the
      # shard gives for the **type of weapon in hand** — shield armour class for
      # a blade, Discipline for a polearm, attack for a ranged weapon. `nil` for
      # vanilla, which has no such system. Two independent terms with the racial
      # bonus above, measured rather than assumed; see `weapon_type_bonuses/2`
      # and `Rules.WeaponTypeBonus`.
      weapon_type_bonuses: weapon_type_bonuses,
      # Ceilings on *bonuses*, not on the base — see `stat_caps/1`.
      stat_caps: caps,
      # And **which** bonuses each ceiling covers, per source kind: since
      # 09.08.2026 a feat's attack bonus sits on top of the +20 rather than under
      # it (Dan). Read by `Rules.Caps.covers_source?/3`; see `stat_cap_sources/1`.
      stat_cap_sources: cap_sources,
      # The manual-entry equipment layer: what the player may type and how far.
      gear: gear,
      # Feats that change a formula rather than adding to it (Weapon Finesse).
      # ⚠ Takes the weapon dictionary since 17.08.2026: a rule may now name the
      # weapons it works with **by name** (task S10), and a name nobody can find
      # has to fail the build rather than quietly narrow the rule to nothing.
      attack_ability: Character.attack_ability(ov, weapons),
      point_buy: Character.point_buy(ov),
      # Считается ли интеллект С ВЕЩЕЙ, когда уровень выдаёт скилл-поинты
      # (задача 3.105). `:ignored` — «нет» со слов Dan (25.08.2026), `:counted` —
      # «да», `nil` — не сказал никто, и тогда ядро считает по-прежнему без вещей
      # **и оговаривается**. Читает `Rules.Skills.gear_intelligence/1`; лежит
      # в `_vanilla_constants_confirmed`, поэтому запись видят оба ruleset'а —
      # вопрос про движок, а не про баланс шарда.
      skill_points_gear_intelligence: Character.skill_points_gear_intelligence(ov),
      name_map: if(raw.name_map == :missing, do: %{}, else: raw.name_map),
      epic: Character.build_epic(epic, ov, level_cap),
      skill_rank_caps: Character.skill_rank_caps(epic, level_cap),
      attacks_per_round: Character.attacks_per_round(epic),
      # Extension point for shard rules that add attacks on top of the vanilla
      # "frozen at level 20" number — empty for vanilla. See `attack_modifiers/1`.
      attack_modifiers: attack_modifiers,
      prestige: Character.build_prestige(epic, ov),
      gaps:
        Gaps.gaps(
          version,
          raw,
          shard,
          ov,
          classes,
          skills,
          epic,
          repeat_grants,
          feats,
          domains,
          ability_bonuses,
          # ⚠ `racial_bonuses` уехал отсюда 22.08.2026 (задача 3.81): его
          # единственный гэп ruleset'а — «прогрессии роста нет» — снят решением
          # Dan, и передавать запись, чтобы про неё нечего было сказать, незачем.
          # Сама запись жива и идёт в ruleset выше — считает по ней
          # `Rules.RacialBonus`.
          weapon_type_bonuses,
          skill_bonuses,
          gap_receivers
        )
    }
  end

  defp layers("vanilla"), do: ["vanilla"]
  defp layers(version), do: ["vanilla", version]

  defp level_cap(epic, ov) do
    dig(ov, ["character", "level_cap", "value"]) || Map.fetch!(epic, "character_level_cap")
  end

  defp require_map!(:missing, rel), do: raise("#{rel} is required and missing")
  defp require_map!(data, _rel), do: data
end
