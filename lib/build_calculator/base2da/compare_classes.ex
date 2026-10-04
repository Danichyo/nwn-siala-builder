defmodule BuildCalculator.Base2da.CompareClasses do
  @moduledoc """
  Сверка классов с `classes.2da` и таблицами, на которые он ссылается
  (задача 4.5): прогрессии BAB и спасов, хит-дайс, скилл-поинты, классовые
  навыки, выдачи и пулы фитов, бонусные уровни, требования престижа,
  мировоззрение, заклинания.

  Сравнивается **загруженный** ванильный ruleset (`Data.ruleset!/1`),
  а не сырой JSON: ручные слои (`class_requirements.json`, `feat_requirements.json`,
  `grant_substitutions.json`) уже наложены, и расхождение — это то, что
  калькулятор напечатает, а не то, что лежит в одном из файлов.
  """

  import Bitwise

  alias BuildCalculator.Base2da.{Source, Tally}
  alias BuildCalculator.GameFiles.TwoDA
  alias BuildCalculator.Rules.{Build, FeatSlots, Prereqs}

  @alignments ~w(lawful_good neutral_good chaotic_good lawful_neutral true_neutral
                 chaotic_neutral lawful_evil neutral_evil chaotic_evil)a

  @doc "Все области по классам — список `Tally`."
  @spec run(map()) :: [Tally.t()]
  def run(ctx) do
    [progression(ctx), class_feats(ctx), bonus_values(ctx), requirements(ctx), spellcasting(ctx)]
  end

  # ------------------------------------------------------------ progression --

  defp progression(ctx) do
    tally =
      Tally.new(
        :classes,
        "Классы: хит-дайс, скилл-поинты, BAB и спасы по уровням, навыки, длина таблицы"
      )

    Enum.reduce(sorted(ctx.class_rows), tally, fn {id, row}, tally ->
      class = ctx.ruleset.classes[id]
      at = &"classes.2da:#{row} #{TwoDA.get(ctx.classes, row, "Label")}.#{&1}"

      tally
      |> hit_die(ctx, id, class, row, at)
      |> Tally.check(int(ctx.classes, row, "SkillPointBase"), class.skill_points,
        subject: id,
        field: "skill_points",
        base_at: at.("SkillPointBase"),
        ours_at: "classes.#{id}.skill_points"
      )
      |> bab_and_saves(ctx, id, class, row)
      |> class_skills(ctx, id, class, row, at)
      |> table_length(ctx, id, class, row, at)
    end)
  end

  defp hit_die(tally, ctx, id, class, row, at) do
    base = int(ctx.classes, row, "HitDie")

    case class.hit_die_by_class_level do
      nil ->
        Tally.check(tally, base, class.hit_die,
          subject: id,
          field: "hit_die",
          base_at: at.("HitDie"),
          ours_at: "classes.#{id}.hit_die"
        )

      steps ->
        # Растущая кость (РДД). В EE она выдаётся фитами «Hit Die Increase (dN)»
        # из cls_feat_*, а размер кости — константа FEAT_DRAGON_HDn в ruleset.2da.
        dice = dragon_dice(ctx, id)
        ours = Map.new(steps, &{&1.from, &1.die})

        tally
        |> Tally.add(base, class.hit_die,
          subject: id,
          field: "hit_die",
          base_at: at.("HitDie"),
          ours_at: "classes.#{id}.hit_die (рядом hit_die_by_class_level)"
        )
        |> Tally.check(dice, ours,
          subject: id,
          field: "hit_die_by_class_level",
          base_at: "cls_feat: выдачи «Hit Die Increase (dN)» + ruleset.2da FEAT_DRAGON_HDn",
          ours_at: "classes.#{id}.hit_die_by_class_level"
        )
    end
  end

  defp dragon_dice(ctx, id) do
    constants = ctx.constants

    for {row, grants} <- ctx.grants,
        {^id, level} <- grants,
        ctx.feat_rows[row] == :hit_die_increase,
        label = TwoDA.get(ctx.feat, row, "LABEL"),
        [_, n] <- [Regex.run(~r/HDINCREASE_D(\d+)$/, label || "")],
        into: %{},
        do: {level, constants["FEAT_DRAGON_HD" <> n]}
  end

  defp bab_and_saves(tally, ctx, id, class, row) do
    atk_name = TwoDA.get(ctx.classes, row, "AttackBonusTable")
    sav_name = TwoDA.get(ctx.classes, row, "SavingThrowTable")
    atk = Source.table(ctx.source, atk_name)
    sav = Source.table(ctx.source, sav_name)

    Enum.reduce(class.progression, tally, fn {level, ours}, tally ->
      tally
      |> Tally.check(int(atk, level - 1, "BAB"), ours.bab,
        subject: id,
        field: "bab[#{level}]",
        base_at: "#{String.downcase(atk_name)}.2da:#{level - 1}.BAB",
        ours_at: "classes.#{id}.progression[#{level}].bab"
      )
      |> Tally.check(
        {int(sav, level - 1, "FortSave"), int(sav, level - 1, "RefSave"),
         int(sav, level - 1, "WillSave")},
        {ours.fort, ours.ref, ours.will},
        subject: id,
        field: "saves[#{level}]",
        base_at: "#{String.downcase(sav_name)}.2da:#{level - 1}.FortSave/RefSave/WillSave",
        ours_at: "classes.#{id}.progression[#{level}].fort/ref/will"
      )
    end)
  end

  defp class_skills(tally, ctx, id, class, row, at) do
    table_name = TwoDA.get(ctx.classes, row, "SkillsTable")
    table = Source.table(ctx.source, table_name)

    base =
      for {_i, r} <- TwoDA.rows(table),
          r["ClassSkill"] == "1",
          skill = ctx.skill_rows[TwoDA.to_int(r["SkillIndex"])],
          into: MapSet.new(),
          do: skill

    Tally.check(tally, base, MapSet.new(class.class_skills),
      subject: id,
      field: "class_skills",
      base_at: "#{String.downcase(table_name)}.2da (ClassSkill = 1); #{at.("SkillsTable")}",
      ours_at: "classes.#{id}.class_skills"
    )
  end

  # `max_level` у нас — длина НЕэпической таблицы класса (CLAUDE.md §3), в
  # classes.2da это EpicLevel (−1 — у базовых, значит 20). Потолок класса —
  # MaxLevel (0 — нет своего потолка).
  #
  # Свой потолок у класса — только когда MaxLevel режет НИЖЕ потолка, который
  # класс получил бы без него (у престижа — общий потолок престижа ruleset'а,
  # у Сиалы 31; у базового — кап персонажа): MaxLevel 40 престижа Сиалы
  # не достижим и потолком не является. Наш ответ — тот, что спрашивает ядро
  # (`LevelUp.effective_class_level_cap/2`), у класса с исключением или «никогда
  # не эпического» (задача 4.49: у Сиалы PDK — исключение 10, а не общие 5).
  defp table_length(tally, ctx, id, class, row, at) do
    epic_level = int(ctx.classes, row, "EpicLevel")
    base_length = if epic_level in [nil, -1], do: 20, else: epic_level
    cap = int(ctx.classes, row, "MaxLevel")
    prestige = ctx.ruleset.prestige

    ours_cap =
      if Map.has_key?(prestige.level_cap_exceptions, id) or
           MapSet.member?(prestige.never_epic, id),
         do: BuildCalculator.Rules.LevelUp.effective_class_level_cap(ctx.ruleset, class)

    ceiling =
      if class.prestige?,
        do: prestige.level_cap || prestige.epic_class_level_cap || ctx.ruleset.level_cap,
        else: ctx.ruleset.level_cap

    base_cap = if cap in [nil, 0] or cap >= ceiling, do: nil, else: cap

    tally
    |> Tally.check(min(base_length, base_cap || base_length), class.max_level,
      subject: id,
      field: "max_level",
      base_at: "#{at.("EpicLevel")} = #{epic_level}; MaxLevel = #{cap}",
      ours_at: "classes.#{id}.max_level"
    )
    |> Tally.check(base_cap, ours_cap,
      subject: id,
      field: "class_level_cap",
      base_at: at.("MaxLevel") <> " (0 и не ниже общего потолка #{ceiling} — своего потолка нет)",
      ours_at: "LevelUp.effective_class_level_cap — prestige.level_cap_exceptions / never_epic"
    )
  end

  # -------------------------------------------------------------- feats --

  defp class_feats(ctx) do
    tally =
      Tally.new(:class_feats, "Классы: выданные фиты, бонусные уровни и пулы бонусных фитов")

    {tally, differences, markers} =
      Enum.reduce(sorted(ctx.class_rows), {tally, [], []}, fn {id, row},
                                                              {tally, differences, markers} ->
        {tally, d, m} = granted(tally, ctx, id, row)

        tally =
          tally
          |> bonus_levels(ctx, id, row)
          |> thresholds(ctx, id, row)

        {tally, differences ++ d, markers ++ m}
      end)

    tally
    |> grouped_first_grants(differences)
    |> epic_markers(markers)
    |> bonus_pools(ctx)
  end

  # Выдачи сравниваются по ПЕРВОМУ уровню семейства: ступени одной семьи одна
  # сторона пишет строкой на каждом уровне, другая — одной строкой. Одинаковое
  # расхождение у нескольких классов сводится в одну находку.
  defp granted(tally, ctx, id, row) do
    table_name = TwoDA.get(ctx.classes, row, "FeatsTable") |> String.downcase()
    class = ctx.ruleset.classes[id]

    # Выдача за капом персонажа (у Сиалы хак выносит так Mount actions на 60-й
    # уровень, задача 4.27) — не выдача: её не получит ни один персонаж.
    base =
      for {feat, entries} <- ctx.class_lists[id],
          levels =
            for({3, level} <- entries, level > 0, level <= ctx.ruleset.level_cap, do: level),
          levels != [],
          into: %{},
          do: {feat, Enum.sort(Enum.uniq(levels))}

    ours =
      Enum.reduce(class.granted_feats, %{}, fn {level, feats}, acc ->
        Enum.reduce(feats, acc, fn feat, acc -> Map.update(acc, feat, [level], &[level | &1]) end)
      end)
      |> Map.new(fn {feat, levels} -> {feat, Enum.sort(Enum.uniq(levels))} end)

    markers =
      for {level, label, name, row} <- Map.get(ctx.unmapped_grants, id, []),
          do: {Map.get(ctx.unmapped_groups, row, "epic_class_markers"), id, level, label, name}

    feats = (Map.keys(base) ++ Map.keys(ours)) |> Enum.uniq() |> Enum.sort()

    Enum.reduce(feats, {Tally.count(tally, length(feats)), [], markers}, fn feat,
                                                                            {tally, differences,
                                                                             markers} ->
      b = Map.get(base, feat, [])
      o = Map.get(ours, feat, [])

      cond do
        List.first(b) != List.first(o) ->
          {tally, differences ++ [{feat, List.first(b), List.first(o), id}], markers}

        b != o ->
          tally =
            Tally.add(tally, b, o,
              subject: id,
              field: "granted_ranks/#{feat}",
              base_at: "#{table_name}.2da: List 3, GrantedOnLevel",
              ours_at: "classes.#{id}.granted_feats",
              kind: :b,
              note:
                "Первая выдача совпала; ступени одной семьи одна сторона пишет строкой " <>
                  "на каждом уровне, другая — одной строкой, а рост считает движок или правило."
            )

          {tally, differences, markers}

        true ->
          {tally, differences, markers}
      end
    end)
  end

  defp grouped_first_grants(tally, differences) do
    differences
    |> Enum.group_by(fn {feat, b, o, _class} -> {feat, b, o} end, fn {_, _, _, class} -> class end)
    |> Enum.sort()
    |> Enum.reduce(tally, fn {{feat, b, o}, classes}, tally ->
      Tally.add(tally, b && "уровень #{b}", o && "уровень #{o}",
        subject: feat,
        field: "granted_first",
        base_at: "cls_feat_*.2da, List 3 — у классов: #{Enum.join(Enum.sort(classes), ", ")}",
        ours_at: "classes.*.granted_feats"
      )
    end)
  end

  defp epic_markers(tally, []), do: tally

  # Выдачи строк feat.2da без нашего id — по группе строки: служебные «Epic
  # <Class>» (группа по умолчанию) и строки, которым явная таблица сверки дала
  # свою группу (у Сиалы — «Дух Сиалы», строка 754, задача 4.49).
  defp epic_markers(tally, markers) do
    markers
    |> Enum.group_by(&elem(&1, 0), &Tuple.delete_at(&1, 0))
    |> Enum.sort()
    |> Enum.reduce(tally, fn {group, entries}, tally ->
      listed =
        entries
        |> Enum.sort()
        |> Enum.map_join("; ", fn {class, level, label, name} ->
          "#{class}: #{name} (#{label}) на #{level}"
        end)

      Tally.add(tally, listed, nil,
        subject: group,
        field: "granted_unmapped",
        base_at: "cls_feat_*.2da, List 3 — строки feat.2da без нашего id",
        ours_at: "classes.*.granted_feats"
      )
    end)
  end

  defp bonus_levels(tally, ctx, id, row) do
    table_name = TwoDA.get(ctx.classes, row, "BonusFeatsTable") |> String.downcase()
    table = Source.table(ctx.source, table_name)
    class = ctx.ruleset.classes[id]
    cap = class_cap(ctx, id)

    base =
      for {i, r} <- TwoDA.rows(table),
          n = TwoDA.to_int(r["Bonus"]),
          is_integer(n) and n > 0,
          i + 1 <= cap,
          into: %{},
          do: {i + 1, n}

    ours_levels = MapSet.union(class.bonus_feat_levels, class.epic_bonus_feat_levels)

    ours =
      Map.new(ours_levels, fn level -> {level, Map.get(class.bonus_feat_counts, level, 1)} end)

    Tally.check(tally, base, ours,
      subject: id,
      field: "bonus_feat_levels",
      base_at:
        "#{table_name}.2da: Bonus по строкам (строка = уровень − 1), до потолка класса #{cap}",
      ours_at: "classes.#{id}.bonus_feat_levels ∪ epic_bonus_feat_levels (+ bonus_feat_counts)"
    )
  end

  # List 0/1/2 с GrantedOnLevel > 0 — «с какого уровня класса фит можно взять».
  defp thresholds(tally, ctx, id, row) do
    table_name = TwoDA.get(ctx.classes, row, "FeatsTable") |> String.downcase()

    for(
      {feat, entries} <- ctx.class_lists[id],
      {list, level} <- entries,
      list in [0, 1, 2],
      level > 1 and level <= ctx.ruleset.level_cap,
      do: {feat, level}
    )
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce(tally, fn {feat, level}, tally ->
      Tally.check(tally, level, our_class_threshold(ctx.ruleset.feats[feat], id),
        subject: id,
        field: "threshold/#{feat}",
        base_at: "#{table_name}.2da: GrantedOnLevel у List 0/1/2 — выбор с уровня класса",
        ours_at: "feats.#{feat}.prereqs (class_levels / qualifying_class_levels / any_of)"
      )
    end)
  end

  defp our_class_threshold(nil, _class), do: nil

  defp our_class_threshold(feat, class) do
    prereqs = feat.prereqs || %{}
    key = Atom.to_string(class)

    get_in(prereqs, ["class_levels", key]) || get_in(prereqs, ["qualifying_class_levels", key]) ||
      Enum.find_value(prereqs["any_of"] || [], &get_in(&1, ["class_levels", key]))
  end

  defp bonus_pools(tally, ctx) do
    base =
      for {class, feats} <- ctx.class_lists,
          {feat, entries} <- feats,
          Enum.any?(entries, fn {list, level} ->
            list in [1, 2] and level <= ctx.ruleset.level_cap
          end),
          reduce: %{} do
        acc -> Map.update(acc, feat, MapSet.new([class]), &MapSet.put(&1, class))
      end

    # Выключенный фит (`disabled?`, у Сиалы — семь владений и Devastating
    # critical) и фит, который не выбирается при левелапе вовсе
    # (`level_up_selectable?: false`), не принимает ни один слот
    # (`Rules.FeatSlots`): их `bonus_for` до ответа не доезжает, и сверяется то,
    # что слот примет на деле.
    ours =
      for {feat, record} <- ctx.ruleset.feats,
          not record.disabled?,
          record.level_up_selectable?,
          MapSet.size(record.bonus_for) > 0,
          into: %{},
          do: {feat, record.bonus_for}

    (Map.keys(base) ++ Map.keys(ours))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce(tally, fn feat, tally ->
      Tally.check(tally, Map.get(base, feat, MapSet.new()), Map.get(ours, feat, MapSet.new()),
        subject: feat,
        field: "bonus_for",
        base_at:
          "cls_feat_*.2da: List 1 или 2 (бонусный слот), GrantedOnLevel ≤ #{ctx.ruleset.level_cap}",
        ours_at: "feats.#{feat}.bonus_for"
      )
    end)
  end

  # -------------------------------------------------- bonus slot values --

  # Бонусный слот класса по ЗНАЧЕНИЮ выбора (задача 4.49). Семейная сверка
  # (`bonus_pools/2`) видит, что класс берёт «Weapon focus» бонусным слотом,
  # но не видит, что из сорока строк семейства его таблица перечисляет
  # тридцать девять: у Чемпиона Торма хака нет Weapon focus (trident), у
  # паладина вместо Overwhelming critical (club) стоит (creature). Здесь
  # сравниваются значения, когда обе стороны пускают класс в слот вообще —
  # иначе это уже находка семейной сверки, и второй раз её не печатаем.
  #
  #   * таблица — значения строк семейства с List 1/2 (уровень ≤ капа) в
  #     `cls_feat_*` класса, из них — только те, что ruleset вообще даёт
  #     выбрать этому фиту (строка Weapon focus (creature) у Сиалы выбора
  #     не имеет и не считается);
  #   * мы — значения, которые бонусный слот класса примет на уровне ЭТОГО
  #     класса (`slot_takes?/4`): всё, что фит даёт выбрать, кроме того, что
  #     отбивает сам слот (`Rules.FeatSlots.choice_refusals/4` — пары
  #     `bonus_for_except` и списки `bonus_for_only`, задача 4.50), и того, что
  #     отбивают требования фита ПО ЗНАЧЕНИЮ, а не по персонажу (`@value_keys`).
  #
  # ⚠ С задачи 4.50 — у обеих сверок (у ванили до неё была выключена).
  # 🔴 «Мы» спрашивается у ядра, а не читается из полей записи: сверка до 4.50
  # сама читала `bonus_for_except`, и новая форма данных была бы ей не видна —
  # тот же дефект, что у теста, собирающего ответ из кусков ядра (HANDOFF,
  # «Тесты»). Регрессия ядра от этого не прячется, а всплывает находкой: слот,
  # переставший отбивать значение, расширяет «мы».
  # ⚠ Домены энергии и типов существ не сверяются: имена строк («Energy
  # Resistance, Cold I», «Favored Enemy: Dwarves») значением не разбираются
  # без своей таблицы соответствий — пробел назван, а не спрятан.
  @value_domains [:weapon, :spell_school, :skill]

  # Ключи требований фита, которые решают по ЗНАЧЕНИЮ и классу уровня, а не по
  # персонажу, — то есть одинаково для любого бонусного слота класса:
  #
  #   * `only_on_class_levels_for_skill` — «Epic skill focus in perform can be
  #     taken only when gaining a bard level» (`fandom:Epic skill focus`):
  #     бонусный слот класса стоит на уровне этого класса, и значение, которое
  #     этот класс не берёт уровнем, бонусным слотом он не берёт тоже. Таблица
  #     говорит то же самое своей формой — строку такого навыка (ALLCLASSESCANUSE 0)
  #     перечисляет только таблица класса, который её берёт;
  #   * `no_feat_variant_for_skills` — «There is no epic skill focus in ride»:
  #     варианта нет вовсе, и в бонусном списке его нет тоже.
  #
  # Без них сверка печатала находку на каждом классе, у которого Epic skill
  # focus в бонусном списке: таблица не перечисляет Animal empathy барду, а мы —
  # «перечисляли», хотя ядро ту же пару на уровне барда отбивает
  # (`{:requires_leveling_as, …}`). Требования к персонажу (ранги, BAB, уровень)
  # сюда не идут: слот их не решает.
  @value_keys ~w(only_on_class_levels_for_skill no_feat_variant_for_skills)

  defp bonus_values(ctx) do
    tally =
      Tally.new(
        :class_bonus_values,
        "Классы: бонусный слот по значению выбора (оружие, школа, навык)"
      )

    feats =
      for {id, feat} <- ctx.ruleset.feats,
          match?(%{repeatable: %{choice: d}} when d in @value_domains, feat),
          Map.has_key?(ctx.families, id),
          do: id

    for {class, _row} <- sorted(ctx.class_rows), feat <- Enum.sort(feats), reduce: tally do
      tally ->
        record = ctx.ruleset.feats[feat]
        allowed = allowed_values(ctx.ruleset, record)
        base = MapSet.intersection(listed_values(ctx, class, feat, record), allowed)

        ours =
          if record.disabled? or not record.level_up_selectable? or
               not MapSet.member?(record.bonus_for, class),
             do: MapSet.new(),
             else: MapSet.filter(allowed, &slot_takes?(ctx.ruleset, record, class, &1))

        if MapSet.size(base) == 0 or MapSet.size(ours) == 0 do
          tally
        else
          Tally.check(tally, base, ours,
            subject: class,
            field: Atom.to_string(feat),
            base_at:
              "#{String.downcase(TwoDA.get(ctx.classes, ctx.class_rows[class], "FeatsTable"))}.2da: " <>
                "строки семейства с List 1/2 — значения, которые ruleset даёт выбрать",
            ours_at:
              "feats.#{feat}: бонусный слот класса на уровне класса " <>
                "(Rules.FeatSlots.choice_refusals/4 и требования по значению)"
          )
        end
    end
  end

  # Примет ли бонусный слот `class` фит `record` со значением `value` — вопрос
  # слоту (ядро) и двум ключам требований по значению (`@value_keys`), заданный
  # персонажу из одного уровня этого класса: эти ключи смотрят только на класс
  # уровня и на само значение, а остальное в блоке сюда не берётся.
  defp slot_takes?(ruleset, record, class, value) do
    FeatSlots.choice_refusals(ruleset, {:class_bonus, class}, record.id, value) == [] and
      value_requirements(ruleset, record, class, value) == []
  end

  defp value_requirements(ruleset, record, class, value) do
    case Map.take(record.prereqs || %{}, @value_keys) do
      block when block == %{} ->
        []

      block ->
        Prereqs.check(block, %{
          build: %Build{levels: [class]},
          ruleset: ruleset,
          stats: nil,
          level: 1,
          requirement_of: :feat,
          feat: record.id,
          # Оба ключа — про навык; значение фита — навык, когда домен фита
          # разрешается в словарь навыков ruleset'а (так его узнаёт и ядро).
          chosen_skill: if(skill_domain?(ruleset, record), do: value),
          chosen_value: value
        })
    end
  end

  defp skill_domain?(ruleset, record),
    do: match?(%{source: {:ruleset, :skills}}, ruleset.choice_domains[record.repeatable.choice])

  # Значения, которые фит даёт выбрать на этом ruleset'е: ворота домена
  # (по id фита, иначе общие `selectable`), как `Rules.FeatChoices` их читает.
  defp allowed_values(ruleset, record) do
    domain = ruleset.choice_domains[record.repeatable.choice]
    flags = domain.flags || %{}

    MapSet.new(Map.get(flags, record.id) || Map.get(flags, :selectable) || domain.values)
  end

  defp listed_values(ctx, class, feat, record) do
    domain = ctx.ruleset.choice_domains[record.repeatable.choice]
    rows = MapSet.new(ctx.families[feat])
    table = Source.table(ctx.source, TwoDA.get(ctx.classes, ctx.class_rows[class], "FeatsTable"))

    for {_i, r} <- TwoDA.rows(table),
        row = TwoDA.to_int(r["FeatIndex"]),
        MapSet.member?(rows, row),
        TwoDA.to_int(r["List"]) in [1, 2],
        (TwoDA.to_int(r["GrantedOnLevel"]) || -1) <= ctx.ruleset.level_cap,
        value = row_value(ctx, row, domain.values),
        value != nil,
        into: MapSet.new(),
        do: value
  end

  # Значение строки по скобке в имени: «Weapon Focus (Short Sword)» → shortsword,
  # «Skill Focus (Heal)» → heal_skill. Сравнение без подчёркиваний и с хвостом
  # `_skill`/`_weapon` — так же, как `Base2da.Ids` сопоставляет имена с id.
  defp row_value(ctx, row, values) do
    name = ctx.feat_name.(row) || ""

    with [_, raw] <- Regex.run(~r/\(([^)]+)\)\s*$/, name) do
      squeeze = &String.replace(&1, "_", "")
      n = squeeze.(BuildCalculator.Base2da.Ids.norm(raw))

      Enum.find(values, fn v ->
        squeeze.(Atom.to_string(v)) in [n, n <> "skill", n <> "weapon"]
      end)
    else
      _ -> nil
    end
  end

  # ------------------------------------------------------- requirements --

  defp requirements(ctx) do
    tally = Tally.new(:class_requirements, "Классы: мировоззрение и требования престиж-классов")

    Enum.reduce(sorted(ctx.class_rows), tally, fn {id, row}, tally ->
      tally
      |> alignment(ctx, id, row)
      |> prestige(ctx, id, row)
    end)
  end

  defp alignment(tally, ctx, id, row) do
    mask = int(ctx.classes, row, "AlignRestrict") || 0
    axes = int(ctx.classes, row, "AlignRstrctType") || 0
    invert = int(ctx.classes, row, "InvertRestrict") || 0
    class = ctx.ruleset.classes[id]

    specs =
      [class.alignment_restriction, class.requirements && class.requirements[:alignment]]
      |> Enum.filter(&is_map/1)

    ours =
      for alignment <- @alignments,
          Enum.all?(
            specs,
            &(Prereqs.check(%{alignment: &1}, %{build: %Build{alignment: alignment}}) == [])
          ),
          into: MapSet.new(),
          do: alignment

    Tally.check(tally, allowed_by_mask(mask, axes, invert), ours,
      subject: id,
      field: "alignment",
      base_at:
        "classes.2da:#{row} AlignRestrict=0x#{Integer.to_string(mask, 16)} " <>
          "AlignRstrctType=#{axes} InvertRestrict=#{invert}",
      ours_at: "classes.#{id}.alignment_restriction + requirements.alignment"
    )
  end

  @doc """
  Разрешённые мировоззрения по трём колонкам `classes.2da`.

  Биты (nwn.wiki, classes.2da; расшифровка проверена на семи известных
  ванильных фактах ещё в docs/hak_diff_classes.md): 0x01 нейтральность,
  0x02 закон, 0x04 хаос, 0x08 добро, 0x10 зло. `AlignRstrctType` выбирает оси
  (0x1 закон–хаос, 0x2 добро–зло), `InvertRestrict = 1` — маска называет
  РАЗРЕШЁННОЕ, иначе — запрещённое.
  """
  @spec allowed_by_mask(non_neg_integer(), non_neg_integer(), 0 | 1) :: MapSet.t(atom())
  def allowed_by_mask(mask, axes, invert) do
    for alignment <- @alignments, into: MapSet.new() do
      [law, good] = alignment |> Atom.to_string() |> String.split("_") |> axis_words()

      hit =
        ((axes &&& 0x1) != 0 and (mask &&& law_bit(law)) != 0) or
          ((axes &&& 0x2) != 0 and (mask &&& good_bit(good)) != 0)

      {alignment, if(invert == 1, do: hit, else: not hit)}
    end
    |> Enum.filter(&elem(&1, 1))
    |> MapSet.new(&elem(&1, 0))
  end

  defp axis_words(["true", "neutral"]), do: ["neutral", "neutral"]
  defp axis_words([law, good]), do: [law, good]

  defp law_bit("lawful"), do: 0x02
  defp law_bit("chaotic"), do: 0x04
  defp law_bit("neutral"), do: 0x01
  defp good_bit("good"), do: 0x08
  defp good_bit("evil"), do: 0x10
  defp good_bit("neutral"), do: 0x01

  defp prestige(tally, ctx, id, row) do
    case TwoDA.get(ctx.classes, row, "PreReqTable") do
      nil -> tally
      name -> prestige_rows(tally, ctx, id, String.downcase(name))
    end
  end

  defp prestige_rows(tally, ctx, id, table_name) do
    table = Source.table(ctx.source, table_name)
    requirements = ctx.ruleset.classes[id].requirements || %{}
    rows = for {_i, r} <- TwoDA.rows(table), do: r
    by_type = Enum.group_by(rows, & &1["ReqType"])
    at = "#{table_name}.2da"
    ours_at = "classes.#{id}.requirements"

    tally
    |> Tally.check(first_int(by_type["BAB"]), req(requirements, :base_attack_bonus),
      subject: id,
      field: "requirement/bab",
      base_at: "#{at}: BAB",
      ours_at: ours_at
    )
    |> Tally.check(
      feats_of(ctx, by_type["FEAT"]),
      MapSet.new(req(requirements, :feats) || [], &String.to_existing_atom/1),
      subject: id,
      field: "requirement/feats",
      base_at: "#{at}: FEAT (все обязательны)",
      ours_at: ours_at <> ".feats",
      same: &feats_implied?(ctx, &1, MapSet.difference(&2, feats_of(ctx, by_type["FEATOR"])))
    )
    |> feats_or(ctx, id, by_type["FEATOR"], requirements, at, ours_at)
    |> Tally.check(
      MapSet.new(by_type["RACE"] || [], &ctx.race_by_row[TwoDA.to_int(&1["ReqParam1"])]),
      MapSet.new(req(requirements, :race) || [], &String.to_existing_atom/1),
      subject: id,
      field: "requirement/race",
      base_at: "#{at}: RACE (любая одна)",
      ours_at: ours_at <> ".race"
    )
    |> Tally.check(
      Map.new(by_type["SKILL"] || [], fn r ->
        {ctx.skill_rows[TwoDA.to_int(r["ReqParam1"])], TwoDA.to_int(r["ReqParam2"])}
      end),
      Map.new(req(requirements, :skills) || %{}, fn {k, v} -> {String.to_existing_atom(k), v} end),
      subject: id,
      field: "requirement/skills",
      base_at: "#{at}: SKILL (ранги)",
      ours_at: ours_at <> ".skills"
    )
    |> caster_requirement(ctx, id, by_type, requirements, at, ours_at)
  end

  # ARCSPELL N — «N уровней аркан-класса» (nwn.wiki cls_pres_xxx.2da: «required
  # combined class levels which are arcane spellcasters», с примером, где два
  # класса по 5 НЕ проходят требование 10). CLASSOR — любой из названных
  # классов. SPELL N — «уровень класса-заклинателя N».
  defp caster_requirement(tally, ctx, id, by_type, requirements, at, ours_at) do
    arcane = first_int(by_type["ARCSPELL"])
    spell = first_int(by_type["SPELL"])

    class_or =
      Enum.map(by_type["CLASSOR"] || [], &ctx.class_by_row[TwoDA.to_int(&1["ReqParam1"])])

    arcane_classes =
      for {cid, row} <- ctx.class_rows, TwoDA.get(ctx.classes, row, "Arcane") == "1", do: cid

    base =
      cond do
        arcane && class_or != [] -> Map.new(class_or, &{&1, arcane})
        arcane -> Map.new(arcane_classes, &{&1, arcane})
        true -> %{}
      end

    ours =
      requirements
      |> req(:any_of)
      |> List.wrap()
      |> Enum.flat_map(fn alt ->
        Map.to_list(alt["class_levels"] || alt[:class_levels] || %{})
      end)
      |> Map.new(fn {k, v} -> {to_atom(k), v} end)

    tally =
      if base == %{} and ours == %{} do
        tally
      else
        Tally.check(tally, base, ours,
          subject: id,
          field: "requirement/caster",
          base_at: "#{at}: ARCSPELL / CLASSOR",
          ours_at: ours_at <> ".any_of[].class_levels"
        )
      end

    if spell do
      Tally.add(
        tally,
        "SPELL #{spell} — уровень класса-заклинателя #{spell}",
        ours_spellcasting(requirements),
        subject: id,
        field: "requirement/spell_level",
        base_at: "#{at}: SPELL",
        ours_at: ours_at
      )
    else
      tally
    end
  end

  defp ours_spellcasting(requirements) do
    req(requirements, :spellcasting) ||
      "нет ключа (фиты: #{Enum.join(req(requirements, :feats) || [], ", ")})"
  end

  defp feats_of(ctx, rows) do
    MapSet.new(rows || [], &ctx.feat_rows[TwoDA.to_int(&1["ReqParam1"])])
  end

  # FEAT в cls_pres — прямые требования; у нас список бывает транзитивным
  # (WM: Spring attack — это требование Whirlwind attack). Сходится, если каждое
  # наше следует из их замыкания, а каждое их есть у нас.
  defp feats_implied?(ctx, base, ours) do
    closure = Enum.reduce(base, base, &MapSet.union(&2, ctx.feat_closure.(&1)))
    MapSet.subset?(base, ours) and MapSet.subset?(ours, closure)
  end

  # FEATOR — «любой из»: у нас это фит семейства в `feats` плюс ограничение
  # выбора (`feat_choice_properties` / `feat_choice_excludes`) или его проза
  # (`qualifiers`). Сверяются и семейство, и набор допустимых значений.
  defp feats_or(tally, _ctx, _id, nil, _requirements, _at, _ours_at), do: tally

  defp feats_or(tally, ctx, id, rows, requirements, at, ours_at) do
    families = feats_of(ctx, rows)
    ours = MapSet.new(req(requirements, :feats) || [], &String.to_existing_atom/1)

    tally =
      Tally.check(tally, families, ours,
        subject: id,
        field: "requirement/feats_or",
        base_at: "#{at}: FEATOR (любой один)",
        ours_at: ours_at <> ".feats",
        same: &MapSet.subset?/2
      )

    if families == MapSet.new([:weapon_focus]) do
      base = MapSet.new(rows, &ctx.choice_of_row.(TwoDA.to_int(&1["ReqParam1"])))

      case our_weapon_choices(ctx, requirements) do
        {:computed, allowed} ->
          Tally.check(tally, base, allowed,
            subject: id,
            field: "requirement/weapon_focus_choice",
            base_at: "#{at}: FEATOR — строки Weapon Focus (оружие)",
            ours_at: ours_at <> ".feat_choices / feat_choice_properties / feat_choice_excludes"
          )

        {:prose, text} ->
          Tally.add(tally, base, text,
            subject: id,
            field: "requirement/weapon_focus_choice",
            base_at: "#{at}: FEATOR — строки Weapon Focus (оружие)",
            ours_at: ours_at <> ".qualifiers"
          )
      end
    else
      tally
    end
  end

  defp our_weapon_choices(ctx, requirements) do
    properties = get_in(req(requirements, :feat_choice_properties) || %{}, ["weapon_focus"])
    excludes = get_in(req(requirements, :feat_choice_excludes) || %{}, ["weapon_focus"]) || []

    # Список значений целиком (`feat_choices`, `Rules.Prereqs`) — у Тайного
    # лучника Сиалы: «короткий лук, длинный лук, малый или большой арбалет».
    listed = get_in(req(requirements, :feat_choices) || %{}, ["weapon_focus"])
    domain = ctx.ruleset.choice_domains[:weapon]

    cond do
      is_list(listed) ->
        {:computed, MapSet.new(listed, &String.to_existing_atom/1)}

      properties || excludes != [] ->
        allowed =
          domain.flags.selectable
          |> MapSet.difference(MapSet.new(excludes, &String.to_existing_atom/1))
          |> then(fn set ->
            case properties do
              %{"ranged" => false} -> MapSet.difference(set, domain.flags.ranged)
              _ -> set
            end
          end)

        {:computed, allowed}

      true ->
        {:prose, Enum.join(req(requirements, :qualifiers) || [], "; ")}
    end
  end

  # -------------------------------------------------------- spellcasting --

  defp spellcasting(ctx) do
    tally =
      Tally.new(
        :spellcasting,
        "Классы: заклинания по дням, известные, ключевая характеристика, спонтанность, выбор домена и школы"
      )

    casters =
      for {id, row} <- sorted(ctx.class_rows),
          TwoDA.get(ctx.classes, row, "SpellCaster") == "1",
          do: {id, row}

    spontaneous_base =
      for {id, row} <- casters,
          TwoDA.get(ctx.classes, row, "MemorizesSpells") == "0",
          into: MapSet.new(),
          do: id

    tally =
      Tally.check(tally, spontaneous_base, ctx.ruleset.casting.spontaneous,
        subject: "casting",
        field: "spontaneous",
        base_at:
          "classes.2da: MemorizesSpells = 0 (НЕ CanCastSpontaneously — та колонка про обмен на лечение у клирика)",
        ours_at: "casting.spontaneous"
      )

    tally =
      Tally.check(
        tally,
        MapSet.new(casters, &elem(&1, 0)),
        ctx.ruleset.classes
        |> Enum.filter(fn {_id, c} -> c.spells_per_day != %{} end)
        |> MapSet.new(&elem(&1, 0)),
        subject: "casting",
        field: "casters",
        base_at: "classes.2da: SpellCaster = 1",
        ours_at: "classes.*.spells_per_day не пуст"
      )

    tally = choices(tally, ctx, casters)

    Enum.reduce(casters, tally, fn {id, row}, tally ->
      class = ctx.ruleset.classes[id]

      tally
      |> Tally.check(
        ability(TwoDA.get(ctx.classes, row, "SpellcastingAbil")),
        class.casting_ability,
        subject: id,
        field: "casting_ability",
        base_at: "classes.2da:#{row}.SpellcastingAbil",
        ours_at: "classes.#{id}.casting_ability"
      )
      |> spell_table(ctx, id, row, "SpellGainTable", :spells_per_day)
      |> spell_table(ctx, id, row, "SpellKnownTable", :spells_known)
    end)
    |> pale_master(ctx)
  end

  defp choices(tally, ctx, casters) do
    Enum.reduce(casters, tally, fn {id, row}, tally ->
      choice = ctx.ruleset.class_choices[id]

      tally
      |> Tally.check(
        TwoDA.get(ctx.classes, row, "PickDomains") == "1",
        match?(%{domain: :domain}, choice),
        subject: id,
        field: "picks_domains",
        base_at: "classes.2da:#{row}.PickDomains",
        ours_at: "class_choices.#{id}"
      )
      |> Tally.check(
        TwoDA.get(ctx.classes, row, "PickSchool") == "1",
        match?(%{domain: :spell_school}, choice),
        subject: id,
        field: "picks_school",
        base_at: "classes.2da:#{row}.PickSchool",
        ours_at: "class_choices.#{id}"
      )
    end)
  end

  defp spell_table(tally, ctx, id, row, column, field) do
    class = ctx.ruleset.classes[id]
    ours_table = Map.get(class, field) || %{}

    case TwoDA.get(ctx.classes, row, column) do
      nil ->
        Tally.check(tally, %{}, ours_table,
          subject: id,
          field: Atom.to_string(field),
          base_at: "classes.2da:#{row}.#{column} = ****",
          ours_at: "classes.#{id}.#{field}"
        )

      name ->
        table = Source.table(ctx.source, name)
        at = String.downcase(name) <> ".2da"
        top = class.spell_table_max_class_level || 20

        tally =
          Enum.reduce(1..top, tally, fn level, tally ->
            base = slots(table, level)
            ours = Map.get(ours_table, level, %{})

            if base == ours do
              Tally.count(tally, 1)
            else
              circles = Enum.uniq(Map.keys(base) ++ Map.keys(ours)) |> Enum.sort()

              Enum.reduce(circles, tally, fn circle, tally ->
                Tally.check(tally, Map.get(base, circle), Map.get(ours, circle),
                  subject: id,
                  field: "#{field}[#{level}][#{circle}]",
                  base_at: "#{at}:#{level - 1}.SpellLevel#{circle}",
                  ours_at: "classes.#{id}.#{field}[#{level}][#{circle}]"
                )
              end)
            end
          end)

        # Эпических строк у нас нет (CLAUDE.md §6: таблицы кончаются на 20-м);
        # в .2da они есть и повторяют 20-ю — проверяется, что именно повторяют.
        epic_changes =
          for level <- (top + 1)..ctx.ruleset.level_cap//1,
              slots(table, level) != slots(table, top),
              do: level

        Tally.check(tally, epic_changes, [],
          subject: id,
          field: "#{field}_epic",
          base_at: "#{at}: строки #{top + 1}..#{ctx.ruleset.level_cap} против строки #{top}",
          ours_at: "classes.#{id}.#{field} кончается на #{top}"
        )
    end
  end

  defp slots(table, level) do
    for circle <- 0..9,
        n = TwoDA.int(table, level - 1, "SpellLevel#{circle}"),
        is_integer(n),
        into: %{},
        do: {circle, n}
  end

  # Бледный мастер двигает каст хозяина: ArcSpellLvlMod = 2 в classes.2da.
  defp pale_master(tally, ctx) do
    case ctx.class_rows[:pale_master] do
      nil ->
        tally

      row ->
        advancement = ctx.ruleset.casting.advancement[:pale_master]

        Tally.check(
          tally,
          int(ctx.classes, row, "ArcSpellLvlMod"),
          advancement && {advancement.at_class_levels, advancement.levels_per_grant},
          subject: "pale_master",
          field: "spell_advancement",
          base_at: "classes.2da:#{row}.ArcSpellLvlMod",
          ours_at: "casting.advancement.pale_master (at_class_levels, levels_per_grant)",
          same: fn base, ours -> base == 2 and ours == {:odd, 1} end,
          kind: :b,
          note:
            "«+1 уровень каста каждые 2 уровня» и «на нечётных уровнях по одному» — одно и то же правило; какой из двух уровней пары считает движок, таблица не говорит."
        )
    end
  end

  # ------------------------------------------------------------- helpers --

  @doc false
  def class_cap(ctx, id) do
    row = ctx.class_rows[id]
    cap = int(ctx.classes, row, "MaxLevel")
    if cap in [nil, 0] or cap > ctx.ruleset.level_cap, do: ctx.ruleset.level_cap, else: cap
  end

  defp sorted(map), do: Enum.sort_by(map, &elem(&1, 0))
  defp int(table, row, column), do: TwoDA.int(table, row, column)
  defp first_int(nil), do: nil
  defp first_int([r | _]), do: TwoDA.to_int(r["ReqParam1"])

  defp req(nil, _key), do: nil
  defp req(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp ability(nil), do: nil
  defp ability(value), do: value |> String.downcase() |> String.to_existing_atom()

  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_existing_atom(value)
end
