defmodule BuildCalculator.Base2da.CompareOther do
  @moduledoc """
  Сверка всего, что не класс и не требование фита (задача 4.5): навыки, расы,
  оружие и щиты, доспехи, заклинания, домены, школы, константы движка
  (`ruleset.2da`), таблица опыта.
  """

  alias BuildCalculator.Base2da.{Ids, Source, Tally}
  alias BuildCalculator.GameFiles.TwoDA
  alias BuildCalculator.Rules.{Build, Wield}

  @spec run(map()) :: [Tally.t()]
  def run(ctx) do
    [
      skills(ctx),
      races(ctx),
      stat_gains(ctx),
      weapons(ctx),
      armor(ctx),
      spells(ctx),
      domains(ctx),
      schools(ctx),
      constants(ctx),
      xp(ctx)
    ]
  end

  # --------------------------------------------------------------- skills --

  defp skills(ctx) do
    tally = Tally.new(:skills, "Навыки (skills.2da)")
    table = Source.table(ctx.source, "skills")

    tally =
      Enum.reduce(Enum.sort_by(ctx.skill_rows, &elem(&1, 0)), tally, fn {row, id}, tally ->
        skill = ctx.ruleset.skills[id]
        at = &"skills.2da:#{row} #{TwoDA.get(table, row, "Label")}.#{&1}"

        tally
        |> Tally.check(lower_atom(TwoDA.get(table, row, "KeyAbility")), skill.key_ability,
          subject: id,
          field: "key_ability",
          base_at: at.("KeyAbility"),
          ours_at: "skills.#{id}.key_ability"
        )
        |> Tally.check(TwoDA.int(table, row, "Untrained") == 0, skill.trained_only?,
          subject: id,
          field: "trained_only",
          base_at: at.("Untrained") <> " (0 — только обученным)",
          ours_at: "skills.#{id}.trained_only?"
        )
        |> Tally.check(
          TwoDA.int(table, row, "ArmorCheckPenalty") == 1,
          skill.armor_check_penalty == :applies,
          subject: id,
          field: "armor_check_penalty",
          base_at: at.("ArmorCheckPenalty"),
          ours_at: "skills.#{id}.armor_check_penalty"
        )
        |> Tally.check(TwoDA.int(table, row, "AllClassesCanUse") == 0, skill.exclusive?,
          subject: id,
          field: "exclusive",
          base_at: at.("AllClassesCanUse") <> " (0 — только классам, у которых он классовый)",
          ours_at: "skills.#{id}.exclusive?"
        )
      end)

    ctx.ruleset.skills
    |> Map.keys()
    |> Enum.reject(&(&1 in Map.values(ctx.skill_rows)))
    |> Enum.sort()
    |> Enum.reduce(tally, fn id, tally ->
      Tally.add(tally, nil, id,
        subject: id,
        field: "unmapped_id",
        base_at: "skills.2da",
        ours_at: "skills.#{id}"
      )
    end)
  end

  # ---------------------------------------------------------------- races --

  defp races(ctx) do
    tally = Tally.new(:races, "Расы (racialtypes.2da, race_feat_*, appearance.2da)")
    table = Source.table(ctx.source, "racialtypes")

    tally =
      Enum.reduce(ctx.unmapped_races, tally, fn label, tally ->
        Tally.add(tally, label, nil,
          subject: label,
          field: "unmapped_row",
          base_at: "racialtypes.2da",
          ours_at: "races"
        )
      end)

    Enum.reduce(Enum.sort_by(ctx.race_rows, &elem(&1, 0)), tally, fn {id, row}, tally ->
      race = ctx.ruleset.races[id]
      at = &"racialtypes.2da:#{row} #{TwoDA.get(table, row, "Label")}.#{&1}"

      adjust =
        for {column, ability} <- [
              {"StrAdjust", :str},
              {"DexAdjust", :dex},
              {"ConAdjust", :con},
              {"IntAdjust", :int},
              {"WisAdjust", :wis},
              {"ChaAdjust", :cha}
            ],
            n = TwoDA.int(table, row, column),
            is_integer(n) and n != 0,
            into: %{},
            do: {ability, n}

      favored = TwoDA.int(table, row, "Favored")

      base_favored =
        if is_integer(favored) and favored >= 0, do: ctx.class_by_row[favored], else: :any

      ours_favored = if race.favored_class_any?, do: :any, else: race.favored_class

      tally
      |> Tally.check(adjust, race.ability_modifiers,
        subject: id,
        field: "ability_modifiers",
        base_at: at.("StrAdjust…ChaAdjust"),
        ours_at: "races.#{id}.ability_modifiers"
      )
      |> Tally.check(base_favored, ours_favored,
        subject: id,
        field: "favored_class",
        base_at: at.("Favored"),
        ours_at: "races.#{id}.favored_class"
      )
      |> race_feats(ctx, id, race, row, table)
      |> Tally.check(
        TwoDA.int(table, row, "ExtraFeatsAtFirstLevel"),
        race.extra_feats && race.extra_feats[:count],
        subject: id,
        field: "extra_feats",
        base_at: at.("ExtraFeatsAtFirstLevel"),
        ours_at: "races.#{id}.extra_feats.count"
      )
      |> Tally.check(
        TwoDA.int(table, row, "ExtraSkillPointsPerLevel"),
        race.bonus_skill_points && race.bonus_skill_points[:per_level],
        subject: id,
        field: "extra_skill_points",
        base_at: at.("ExtraSkillPointsPerLevel"),
        ours_at: "races.#{id}.bonus_skill_points.per_level"
      )
      |> Tally.check(
        TwoDA.int(table, row, "AbilitiesPointBuyNumber"),
        ctx.ruleset.point_buy.budget,
        subject: id,
        field: "point_buy_budget",
        base_at: at.("AbilitiesPointBuyNumber"),
        ours_at: "point_buy.budget (rules.json → _vanilla_constants_confirmed.point_buy)"
      )
      # Против числа ruleset'а, а не литерала (задача 4.65): до неё здесь стояла
      # та же четвёрка, что в ядре `* 4`, и сверка сравнивала таблицу с копией,
      # а не с тем, что ядро умножает. Колонка — по расе, число у нас одно на
      # ruleset: раса с другим множителем — находка, и запись переезжает в расы.
      |> Tally.check(
        TwoDA.int(table, row, "FirstLevelSkillPointsMultiplier"),
        ctx.ruleset.skill_points_first_level_multiplier,
        subject: id,
        field: "first_level_skill_multiplier",
        base_at: at.("FirstLevelSkillPointsMultiplier"),
        ours_at:
          "skill_points_first_level_multiplier (rules.json → character.skill_points_first_level_multiplier)"
      )
      |> Tally.check(
        {TwoDA.int(table, row, "NormalFeatEveryNthLevel"),
         TwoDA.int(table, row, "NumberNormalFeatsEveryNthLevel")},
        general_feat_cadence(ctx.ruleset),
        subject: id,
        field: "general_feat_cadence",
        base_at: at.("NormalFeatEveryNthLevel / NumberNormalFeatsEveryNthLevel"),
        ours_at: "epic.general_feat_levels"
      )
      |> Tally.check(lower_atom(TwoDA.get(table, row, "SkillPointModifierAbility")), :int,
        subject: id,
        field: "skill_point_ability",
        base_at: at.("SkillPointModifierAbility"),
        ours_at: "ядро: скилл-поинты от модификатора INT"
      )
      |> size(ctx, id, race, row, table)
    end)
  end

  defp race_feats(tally, ctx, id, race, row, table) do
    name = TwoDA.get(table, row, "FeatsTable") |> String.downcase()

    base =
      for {_i, r} <- TwoDA.rows(Source.table(ctx.source, name)),
          feat = ctx.feat_rows[TwoDA.to_int(r["FeatIndex"])],
          into: MapSet.new(),
          do: feat

    Tally.check(tally, base, MapSet.new(race.bonus_feats),
      subject: id,
      field: "bonus_feats",
      base_at: "#{name}.2da",
      ours_at: "races.#{id}.bonus_feats"
    )
  end

  defp size(tally, ctx, id, race, row, table) do
    appearance = Source.table(ctx.source, "appearance")
    sizes = Source.table(ctx.source, "creaturesize")
    app = TwoDA.int(table, row, "Appearance")
    category = appearance && TwoDA.int(appearance, app, "SIZECATEGORY")
    label = sizes && category && TwoDA.get(sizes, category, "LABEL")

    Tally.check(tally, label && lower_atom(label), race.size,
      subject: id,
      field: "size",
      base_at:
        "racialtypes.2da:#{row}.Appearance = #{app} → appearance.2da:#{app}.SIZECATEGORY = #{category} → creaturesize.2da",
      ours_at: "races.#{id}.size"
    )
  end

  defp general_feat_cadence(ruleset) do
    levels = ruleset.epic.general_feat_levels |> Enum.filter(&(&1 <= 20)) |> Enum.sort()
    # 1, 3, 6, 9 … — первый при создании, дальше каждые N.
    step =
      levels
      |> Enum.drop(1)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)
      |> Enum.uniq()

    {List.first(step), 1}
  end

  # RDD: способности и естественный AC; Бледный мастер: естественный AC.
  # cls_stat_* даёт ПРИРОСТ на уровне класса, у нас — накопленное значение.
  defp stat_gains(ctx) do
    tally =
      Tally.new(
        :stat_gains,
        "Классы: прибавки по уровню класса (cls_stat_*, ступени Enchant Arrow)"
      )
      |> enchant_arrow(ctx)

    Enum.reduce(Enum.sort_by(ctx.class_rows, &elem(&1, 0)), tally, fn {id, row}, tally ->
      case TwoDA.get(ctx.classes, row, "StatGainTable") do
        nil ->
          tally

        name ->
          table = Source.table(ctx.source, String.downcase(name))
          cap = BuildCalculator.Base2da.CompareClasses.class_cap(ctx, id)
          rows = for {i, r} <- TwoDA.rows(table), i + 1 <= cap, do: {i + 1, r}

          abilities =
            for {level, r} <- rows,
                gains =
                  for(
                    {col, key} <- [
                      {"Str", :str},
                      {"Dex", :dex},
                      {"Con", :con},
                      {"Wis", :wis},
                      {"Int", :int},
                      {"Cha", :cha}
                    ],
                    n = TwoDA.to_int(r[col]),
                    is_integer(n),
                    into: %{},
                    do: {key, n}
                  ),
                gains != %{},
                into: %{},
                do: {level, gains}

          natural =
            rows
            |> Enum.reduce({0, %{}}, fn {level, r}, {total, acc} ->
              case TwoDA.to_int(r["NaturalAC"]) do
                n when is_integer(n) and n != 0 -> {total + n, Map.put(acc, level, total + n)}
                _ -> {total, acc}
              end
            end)
            |> elem(1)

          at = "#{String.downcase(name)}.2da (строки до потолка класса #{cap})"

          tally
          |> then(fn tally ->
            if abilities == %{} and our_bonus(ctx, :ability_bonuses, id) == nil do
              tally
            else
              Tally.check(
                tally,
                abilities,
                gains_of(ctx, :ability_bonuses, id, :gains_at_class_level),
                subject: id,
                field: "ability_gains",
                base_at: at <> ": Str…Cha",
                ours_at: "ability_bonuses (запись класса или её фита)"
              )
            end
          end)
          |> Tally.check(natural, gains_of(ctx, :ac_bonuses, id, :ac_at_class_level),
            subject: id,
            field: "natural_ac",
            base_at: at <> ": NaturalAC, накопленно",
            ours_at: "ac_bonuses (запись класса или её фита): ac_at_class_level"
          )
      end
    end)
  end

  # Бонус атаки Arcane Archer: ступени «Enchant Arrow N» выдаёт cls_feat_archer
  # (уровень), размер — PRESTIGE_ENCHANT_ARROW_N_BONUS в ruleset.2da.
  defp enchant_arrow(tally, ctx) do
    case ctx.class_rows[:arcane_archer] do
      nil ->
        tally

      _row ->
        cap = BuildCalculator.Base2da.CompareClasses.class_cap(ctx, :arcane_archer)

        base =
          for {row, grants} <- ctx.grants,
              {:arcane_archer, level} <- grants,
              level <= cap,
              [_, n] <- [
                Regex.run(
                  ~r/^FEAT_PRESTIGE_ENCHANT_ARROW_(\d+)$/,
                  TwoDA.get(ctx.feat, row, "LABEL") || ""
                )
              ],
              into: %{},
              do: {level, ctx.constants["PRESTIGE_ENCHANT_ARROW_#{n}_BONUS"]}

        Tally.check(
          tally,
          base,
          gains_of(ctx, :attack_bonuses, :arcane_archer, :attack_at_class_level),
          subject: :arcane_archer,
          field: "enchant_arrow_attack",
          base_at:
            "cls_feat_archer.2da: выдачи FEAT_PRESTIGE_ENCHANT_ARROW_N (уровень) + ruleset.2da PRESTIGE_ENCHANT_ARROW_N_BONUS",
          ours_at: "attack_bonuses.enchant_arrow.attack_at_class_level"
        )
    end
  end

  # У класса запись «counted_elsewhere» указывает на фит, который её считает.
  defp gains_of(ctx, section, class, key) do
    record =
      Enum.find_value([:applied, :counted_elsewhere, :unmodelled], fn bucket ->
        Enum.find(Map.get(Map.get(ctx.ruleset, section), bucket, []), fn r ->
          match?(%{amount: %{class: ^class}}, r) and Map.has_key?(r.amount, key)
        end)
      end)

    record && Map.get(record.amount, key)
  end

  defp our_bonus(ctx, section, id) do
    Enum.find_value([:applied, :counted_elsewhere, :unmodelled], fn bucket ->
      Enum.find(Map.get(Map.get(ctx.ruleset, section), bucket, []), &(&1.id == id))
    end)
  end

  # -------------------------------------------------------------- weapons --

  defp weapons(ctx) do
    tally = Tally.new(:weapons, "Оружие (baseitems.2da)")
    items = Source.table(ctx.source, "baseitems")
    raw = Map.new(ctx.raw_weapons, &{String.to_existing_atom(&1["id"]), &1})
    domain = ctx.ruleset.choice_domains[:weapon]
    human = Build.new(race: :human)
    halfling = Build.new(race: :halfling)

    tally =
      ctx.ruleset.weapons
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(ctx.weapon_rows, &1))
      |> Enum.sort()
      |> Enum.reduce(tally, fn id, tally ->
        Tally.add(tally, nil, id,
          subject: id,
          field: "unmapped_id",
          base_at: "baseitems.2da — строки с таким именем нет",
          ours_at: "weapons.#{id}"
        )
      end)

    Enum.reduce(Enum.sort_by(ctx.weapon_rows, &elem(&1, 0)), tally, fn {id, row}, tally ->
      weapon = ctx.ruleset.weapons[id]
      r = raw[id]
      at = &"baseitems.2da:#{row} #{TwoDA.get(items, row, "label")}.#{&1}"
      wield = TwoDA.int(items, row, "WeaponWield")
      base_size = weapon_size(TwoDA.int(items, row, "WeaponSize"))

      tally
      |> Tally.check(base_size, weapon.size,
        subject: id,
        field: "size",
        base_at: at.("WeaponSize"),
        ours_at: "weapons.#{id}.size"
      )
      |> Tally.check(TwoDA.int(items, row, "RangedWeapon") != nil, weapon.ranged?,
        subject: id,
        field: "ranged",
        base_at: at.("RangedWeapon"),
        ours_at: "weapons.#{id}.ranged?"
      )
      |> Tally.check(wield == 11, weapon.thrown?,
        subject: id,
        field: "thrown",
        base_at: at.("WeaponWield") <> " = #{inspect(wield)} (11 — метательное, 10 — праща)",
        ours_at: "weapons.#{id}.thrown?"
      )
      |> Tally.check(wield == 8, weapon.double_sided?,
        subject: id,
        field: "double_sided",
        base_at: at.("WeaponWield") <> " (8 — двустороннее)",
        ours_at: "weapons.#{id}.double_sided?"
      )
      |> Tally.check(proficiencies(ctx, items, row), loaded_proficiencies(weapon.proficiency),
        subject: id,
        field: "proficiency",
        base_at: at.("ReqFeat0…4") <> " → фиты владения, хватает любого",
        ours_at:
          "weapons.#{id}.proficiency = #{inspect(weapon.proficiency)} (vanilla/weapons.json → proficiency, правило rules.json → gear.weapon.proficiency)"
      )
      |> Tally.check(
        dice(items, row),
        r["damage"] && {r["damage"]["count"], r["damage"]["faces"]},
        subject: id,
        field: "damage",
        base_at: at.("NumDice/DieToRoll"),
        ours_at: "vanilla/weapons.json → #{id}.damage"
      )
      |> Tally.check(threat_low(items, row), r["threat_range_low"] || 20,
        subject: id,
        field: "threat_range",
        base_at: at.("CritThreat") <> " (N из 20: 2 → 19–20)",
        ours_at: "vanilla/weapons.json → #{id}.threat_range_low (нет — 20)"
      )
      |> Tally.check(TwoDA.int(items, row, "CritHitMult"), r["critical_multiplier"],
        subject: id,
        field: "critical_multiplier",
        base_at: at.("CritHitMult"),
        ours_at: "vanilla/weapons.json → #{id}.critical_multiplier"
      )
      |> Tally.check(
        damage_types(TwoDA.int(items, row, "WeaponType")),
        damage_types_ours(r["damage_types"]),
        subject: id,
        field: "damage_types",
        base_at: at.("WeaponType"),
        ours_at: "vanilla/weapons.json → #{id}.damage_types"
      )
      |> Tally.check(
        TwoDA.get(items, row, "WeaponFocusFeat") != nil,
        MapSet.member?(domain.flags.selectable, id),
        subject: id,
        field: "has_weapon_focus",
        base_at: at.("WeaponFocusFeat"),
        ours_at: "choice_domains.weapon.flags.selectable"
      )
      |> Tally.check(
        TwoDA.get(items, row, "WeaponOfChoiceFeat") != nil,
        MapSet.member?(domain.flags.weapon_of_choice, id),
        subject: id,
        field: "weapon_of_choice",
        base_at: at.("WeaponOfChoiceFeat"),
        ours_at: "choice_domains.weapon.flags.weapon_of_choice"
      )
      |> finesse(ctx, id, items, row, at)
      |> finesse_small(ctx, id, items, row, at, halfling)
      |> grip(ctx, id, items, row, at, human, "grip_medium")
      |> grip(ctx, id, items, row, at, halfling, "grip_small")
      |> off_hand_slot(ctx, id, items, row, at)
    end)
  end

  # Можно ли положить предмет во вторую руку по таблице: бит 0x00020 («Off-hand»,
  # `fandom:Baseitems.2da`, column notes) в `EquipableSlots` (задача 4.29).
  #
  # ⚠ Сверяется ТОЛЬКО бит таблицы — множество `slot`, а не весь ответ «только
  # в главную руку»: запрет движка на цепы и моргенштерн (`engine`) в таблице
  # не лежит, и у лёгкого цепа и моргенштерна бит СТОИТ. Сравнить с таблицей
  # весь ответ значило бы получить две находки про правило, которого таблица
  # не несёт по построению.
  # ⚠ Маска здесь — чтение документации этой стороной сверки, независимо от
  # данных (`rule.off_hand_bit` ванильного файла): так же, как `base_grip/3`
  # читает коды `WeaponWield` сам.
  @off_hand_bit 0x20

  defp off_hand_slot(tally, ctx, id, items, row, at) do
    slots = TwoDA.int(items, row, "EquipableSlots")
    slot_set = get_in(ctx.ruleset, [:wield, :main_hand_only, :slot]) || MapSet.new()

    Tally.check(
      tally,
      is_integer(slots) and Bitwise.band(slots, @off_hand_bit) != 0,
      not MapSet.member?(slot_set, id),
      subject: id,
      field: "off_hand_slot",
      base_at:
        at.("EquipableSlots") <>
          " = #{TwoDA.get(items, row, "EquipableSlots")} (0x00020 — вторая рука)",
      ours_at: "wield.main_hand_only.slot (vanilla/weapon_off_hand.json)"
    )
  end

  # Хват по .2da для владельца размера `wielder`: WeaponWield **** — по размеру
  # (на ступень больше владельца — двуручное, на две — не взять), 4 — двуручное
  # всегда (древковое), 5/6 — лук/арбалет (двумя руками), 8 — двустороннее,
  # 10/11 — праща/метательное (одной рукой).
  #
  # ⚠ Это ЧТЕНИЕ ПОДПИСИ колонки задачей 4.5, и оно оставлено нарочно как вторая,
  # независимая сторона сверки. Ванильный слой с задачи 4.28 читает колонку
  # по документации (`vanilla/weapon_wield.json`) и в одном месте иначе:
  # древковое (4) там решает размер, потому что обе вики описывают колонку как
  # набор анимаций, а игроки видели магический посох одной рукой со щитом.
  # Расхождение остаётся находкой вида (d) у посоха и лэнса — до замера, а не
  # подгоняется здесь под наш ответ.
  defp base_grip(items, row, wielder_size) do
    wield = TwoDA.int(items, row, "WeaponWield")
    size = TwoDA.int(items, row, "WeaponSize")
    step = if is_integer(size), do: size - wielder_size

    cond do
      is_integer(step) and step > 1 -> :cannot_wield
      wield == 8 -> :double_sided
      wield in [4, 5, 6] -> :two_handed
      wield in [10, 11] -> :one_handed
      step == 1 -> :two_handed
      true -> :one_handed
    end
  end

  # ⚠ До задачи 4.28 здесь была вторая проверка, `*_without_siala_grip`: хват
  # на ruleset'е со снятым `stated_grip`, то есть «что будет, если колонку
  # Сиалы у ванили просто убрать» (7 находок). У ванили колонки Сиалы больше
  # нет, `stated_grip` у неё свой, из таблицы игры, — и вопрос проверки исчез
  # вместе с ней.
  defp grip(tally, ctx, id, items, row, at, build, field) do
    wielder = if build.race == :human, do: 3, else: 2
    base = base_grip(items, row, wielder)
    base_at = at.("WeaponWield / WeaponSize") <> " (владелец: #{build.race})"

    Tally.check(tally, base, our_grip(ctx.ruleset, build, id),
      subject: id,
      field: field,
      base_at: base_at,
      ours_at: "Rules.Wield.grip — хват ванили (vanilla/weapon_wield.json + _grip)"
    )
  end

  defp our_grip(ruleset, build, id) do
    case Wield.refusal(build, id, ruleset) do
      nil -> Wield.grip(build, id, ruleset)
      _refusal -> :cannot_wield
    end
  end

  defp finesse(tally, ctx, id, items, row, at) do
    min_size = TwoDA.int(items, row, "WeaponFinesseMinimumCreatureSize")
    rule = Enum.find(ctx.ruleset.attack_ability.rules, &(&1.feat == :weapon_finesse))
    ours = rule && rule.weapon_one_of && MapSet.member?(rule.weapon_one_of, id)

    Tally.check(tally, is_integer(min_size) and min_size <= 3, ours,
      subject: id,
      field: "finesse_medium",
      base_at:
        at.("WeaponFinesseMinimumCreatureSize") <>
          " = #{inspect(min_size)} (фехтовальное, если размер владельца ≥ этого)",
      ours_at: "attack_ability.rules[weapon_finesse].weapon_one_of"
    )
  end

  # Фехтовальное ли оружие у владельца МАЛОГО размера (задача 4.49, п. 6). По
  # таблице — `WeaponFinesseMinimumCreatureSize` ≤ 2. У нас колонку никто не
  # читает: правило — список оружия плюс «не двуручное в руках» с исключениями
  # (`attack_ability.rules[weapon_finesse]`, у Сиалы — посох и копьё, замер
  # S10), и для малой расы ответ складывается из хвата (`Rules.Wield`). Сверяется
  # то, что получится у этой пары, против колонки — так видно, где «двуручное»
  # подменяет размер неточно.
  defp finesse_small(tally, ctx, id, items, row, at, build) do
    min_size = TwoDA.int(items, row, "WeaponFinesseMinimumCreatureSize")
    rule = Enum.find(ctx.ruleset.attack_ability.rules, &(&1.feat == :weapon_finesse))

    ours =
      if rule && rule.weapon_one_of && MapSet.member?(rule.weapon_one_of, id) do
        except = (rule.weapon_not_two_handed || %{}) |> Map.get(:except, MapSet.new())

        case our_grip(ctx.ruleset, build, id) do
          :cannot_wield -> false
          :one_handed -> true
          _two -> is_nil(rule.weapon_not_two_handed) or MapSet.member?(except, id)
        end
      else
        false
      end

    Tally.check(tally, is_integer(min_size) and min_size <= 2, ours,
      subject: id,
      field: "finesse_small",
      base_at:
        at.("WeaponFinesseMinimumCreatureSize") <>
          " = #{inspect(min_size)} (фехтовальное для малого владельца, если ≤ 2)",
      ours_at:
        "attack_ability.rules[weapon_finesse]: weapon_one_of + weapon_not_two_handed.except × Rules.Wield (владелец halfling)"
    )
  end

  # Фиты, любой из которых делает владельцем: ReqFeat1…4 — «an alternate to
  # those in the preceding columns» (`fandom:Baseitems.2da`), пустая строка —
  # «all characters are automatically proficient».
  defp proficiencies(ctx, items, row) do
    for i <- 0..5,
        f = TwoDA.int(items, row, "ReqFeat#{i}"),
        is_integer(f),
        feat = ctx.feat_rows[f],
        feat != nil,
        into: MapSet.new(),
        do: feat
  end

  # ⚠ Сверяется ЗАГРУЖЕННОЕ требование, а не сырой список справочника (задача
  # 4.7): до неё загрузчик ванильный список не читал вовсе, и сверка сырого JSON
  # сходилась у всех 41, пока у каждого оружия в ruleset стояло `:unread`.
  # `:unread` — не множество фитов и не сойдётся ни с одной строкой таблицы.
  defp loaded_proficiencies({:feat, feat}), do: MapSet.new([feat])
  defp loaded_proficiencies({:any_of, feats}), do: MapSet.new(feats)
  defp loaded_proficiencies(:none_needed), do: MapSet.new()
  defp loaded_proficiencies(other), do: other

  defp dice(items, row) do
    case {TwoDA.int(items, row, "NumDice"), TwoDA.int(items, row, "DieToRoll")} do
      {nil, _} -> nil
      pair -> pair
    end
  end

  defp threat_low(items, row) do
    case TwoDA.int(items, row, "CritThreat") do
      nil -> nil
      n -> 21 - n
    end
  end

  defp damage_types(1), do: MapSet.new([:piercing])
  defp damage_types(2), do: MapSet.new([:bludgeoning])
  defp damage_types(3), do: MapSet.new([:slashing])
  defp damage_types(4), do: MapSet.new([:piercing, :slashing])
  defp damage_types(5), do: MapSet.new([:bludgeoning, :piercing])
  defp damage_types(_), do: MapSet.new()

  defp damage_types_ours(nil), do: MapSet.new()

  defp damage_types_ours(types) do
    types
    |> Enum.flat_map(&String.split(&1, "-"))
    |> MapSet.new(&String.to_existing_atom/1)
  end

  defp weapon_size(n) do
    case n do
      1 -> :tiny
      2 -> :small
      3 -> :medium
      4 -> :large
      5 -> :huge
      _ -> nil
    end
  end

  # ---------------------------------------------------------------- armor --

  defp armor(ctx) do
    tally = Tally.new(:armor, "Доспехи и щиты (armor.2da, baseitems.2da)")
    table = Source.table(ctx.source, "armor")
    items = Source.table(ctx.source, "baseitems")
    worn = Map.new(ctx.ruleset.gear.worn, &{&1.id, &1.items})

    tally =
      worn[:armor]
      |> Enum.reduce(tally, fn item, tally ->
        row = item.base_ac
        at = &"armor.2da:#{row}.#{&1}"
        dex = TwoDA.int(table, row, "DEXBONUS")

        tally
        |> Tally.check(TwoDA.int(table, row, "ACBONUS"), item.base_ac,
          subject: item.id,
          field: "base_ac",
          base_at: at.("ACBONUS"),
          ours_at: "gear.worn.armor.#{item.id}.base_ac"
        )
        |> Tally.check(if(dex == 100, do: nil, else: dex), item.max_dex,
          subject: item.id,
          field: "max_dex",
          base_at: at.("DEXBONUS") <> " (100 — предела нет)",
          ours_at: "gear.worn.armor.#{item.id}.max_dex"
        )
        |> Tally.check(TwoDA.int(table, row, "ACCHECK"), item.armor_check_penalty,
          subject: item.id,
          field: "armor_check_penalty",
          base_at: at.("ACCHECK"),
          ours_at: "gear.worn.armor.#{item.id}.armor_check_penalty"
        )
      end)

    shields = %{small: "smallshield", large: "largeshield", tower: "towershield"}

    Enum.reduce(worn[:shield], tally, fn item, tally ->
      row =
        Enum.find_value(TwoDA.rows(items), fn {i, r} ->
          if r["label"] == shields[item.id], do: i
        end)

      at = &"baseitems.2da:#{row} #{shields[item.id]}.#{&1}"

      tally
      |> Tally.check(TwoDA.int(items, row, "BaseAC"), item.base_ac,
        subject: item.id,
        field: "base_ac",
        base_at: at.("BaseAC"),
        ours_at: "gear.worn.shield.#{item.id}.base_ac"
      )
      |> Tally.check(TwoDA.int(items, row, "ArmorCheckPen"), item.armor_check_penalty,
        subject: item.id,
        field: "armor_check_penalty",
        base_at: at.("ArmorCheckPen"),
        ours_at: "gear.worn.shield.#{item.id}.armor_check_penalty"
      )
    end)
  end

  # --------------------------------------------------------------- spells --

  @spell_columns [
    {"Bard", :bard},
    {"Cleric", :cleric},
    {"Druid", :druid},
    {"Paladin", :paladin},
    {"Ranger", :ranger},
    {"Wiz_Sorc", :mage}
  ]

  defp spells(ctx) do
    tally = Tally.new(:spells, "Заклинания (spells.2da)")
    table = Source.table(ctx.source, "spells")

    schools =
      Map.new(TwoDA.rows(Source.table(ctx.source, "spellschools")), fn {_i, r} ->
        {r["Letter"], Ids.norm(r["Label"])}
      end)

    tally =
      ctx.ruleset.spells
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(ctx.spell_rows, &1))
      |> Enum.sort()
      |> Enum.reduce(tally, fn id, tally ->
        Tally.add(tally, nil, ctx.ruleset.spells[id].name,
          subject: id,
          field: "unmapped_id",
          base_at: "spells.2da — строки с таким именем нет",
          ours_at: "spells.#{id}"
        )
      end)

    Enum.reduce(Enum.sort_by(ctx.spell_rows, &elem(&1, 0)), tally, fn {id, row}, tally ->
      spell = ctx.ruleset.spells[id]
      at = &"spells.2da:#{row} #{TwoDA.get(table, row, "Label")}.#{&1}"

      levels =
        for {col, key} <- @spell_columns,
            n = TwoDA.int(table, row, col),
            is_integer(n),
            into: %{},
            do: {key, n}

      innate = TwoDA.int(table, row, "Innate")
      raw = spell.innate_level_raw
      clean = clean_level(raw)

      tally
      |> spell_name_check(ctx, id, row, spell, at)
      |> Tally.check(levels, spell.levels,
        subject: id,
        field: "levels",
        base_at: at.("Bard/Cleric/Druid/Paladin/Ranger/Wiz_Sorc"),
        ours_at: "spells.#{id}.levels"
      )
      |> Tally.check(
        schools[TwoDA.get(table, row, "School")],
        spell.school && Atom.to_string(spell.school),
        subject: id,
        field: "school",
        base_at: at.("School"),
        ours_at: "spells.#{id}.school"
      )
      |> Tally.check(innate, raw,
        subject: id,
        field: "innate_level",
        base_at: at.("Innate"),
        ours_at: "spells.#{id}.innate_level_raw",
        same: fn b, o -> o == to_string(b) end,
        kind: if(clean == innate, do: :b),
        note:
          if(clean == innate,
            do:
              "Число совпадает; у нас сырой викитекст с зачёркнутой историей правок Fandom (так заведено: уровни хранятся строками)."
          )
      )
    end)
  end

  # Имя у строк, названных явной таблицей (`SialaRows`, у ванили таких нет):
  # их имени нет в выгрузке — оно в `.tlk` шарда, — зато метка строки есть,
  # и наша запись обязана ей соответствовать (`Ids.norm/1`: «Stream_of_flame» —
  # «Stream of Flame»). Задача 4.58: на строке 50 хака — `Reflection`, и пока
  # слой Сиалы не переименовал ванильный `endure_elements`, это была находка
  # без имени; без проверки сопоставленная строка спрятала бы её совсем.
  # Расхождение остаётся без вида — `--check` упадёт, а не примет довод.
  defp spell_name_check(tally, ctx, id, row, spell, at) do
    case Map.get(ctx, :spell_overrides, %{}) do
      %{^row => %{id: ^id, label: label}} ->
        Tally.check(tally, label, spell.name,
          subject: id,
          field: "name",
          base_at: at.("Label"),
          ours_at: "spells.#{id}.name",
          same: &(Ids.norm(&1) == Ids.norm(&2))
        )

      _ ->
        tally
    end
  end

  defp clean_level(nil), do: nil

  defp clean_level(raw) do
    raw
    |> String.replace(~r/<(s|del|strike)>.*?<\/\1>/s, "")
    |> String.replace("''", "")
    |> then(&Regex.run(~r/\d+/, &1))
    |> case do
      [n] -> String.to_integer(n)
      _ -> nil
    end
  end

  # -------------------------------------------------------------- domains --

  defp domains(ctx) do
    tally = Tally.new(:domains, "Домены клирика (domains.2da)")
    table = Source.table(ctx.source, "domains")
    spells_table = Source.table(ctx.source, "spells")
    spell_by_row = Map.new(ctx.spell_rows, fn {id, row} -> {row, id} end)

    ours_domains = ctx.ruleset.choice_domains[:domain].values |> MapSet.new(&Atom.to_string/1)

    tally =
      Tally.check(tally, MapSet.new(Map.keys(ctx.domain_rows)), ours_domains,
        subject: "domains",
        field: "set",
        base_at: "domains.2da (строки с именем)",
        ours_at: "choice_domains.domain.values"
      )

    ours_spells = domain_spells(ctx.raw_spells)

    Enum.reduce(Enum.sort(ctx.domain_rows), tally, fn {domain, row}, tally ->
      base =
        for level <- 1..9,
            r = TwoDA.int(table, row, "Level_#{level}"),
            is_integer(r),
            into: %{},
            do:
              {spell_by_row[r] || "spells.2da:#{r} #{TwoDA.get(spells_table, r, "Label")}", level}

      Tally.check(tally, base, Map.get(ours_spells, domain, %{}),
        subject: domain,
        field: "spells",
        base_at: "domains.2da:#{row}.Level_1…Level_9",
        ours_at: "vanilla/spells.json → template domain/domainlevel, domainN/domainNlevel"
      )
    end)
  end

  # Шаблон заклинания на Fandom: domain/domainlevel, domain2/domain2level, …
  defp domain_spells(raw_spells) do
    for spell <- raw_spells,
        template = spell["template"] || %{},
        {key, domain} <- template,
        Regex.match?(~r/^domain\d*$/, key),
        reduce: %{} do
      acc ->
        id = String.to_existing_atom(spell["id"])
        level = to_int(template[key <> "level"])
        Map.update(acc, domain, %{id => level}, &Map.put(&1, id, level))
    end
  end

  defp to_int(nil), do: nil
  defp to_int(s) when is_binary(s), do: TwoDA.to_int(s)
  defp to_int(n), do: n

  # -------------------------------------------------------------- schools --

  defp schools(ctx) do
    tally = Tally.new(:schools, "Школы магии (spellschools.2da)")
    table = Source.table(ctx.source, "spellschools")
    names = ctx.school_rows

    base_set =
      names
      |> Map.values()
      |> Enum.map(&if(&1 == "general", do: "universal", else: &1))
      |> MapSet.new()

    ours_set = ctx.ruleset.choice_domains[:spell_school].values |> MapSet.new(&Atom.to_string/1)

    tally =
      Tally.check(tally, base_set, ours_set,
        subject: "schools",
        field: "set",
        base_at:
          "spellschools.2da (General = Universal: «без специализации», у нас class_choice_no_selection)",
        ours_at: "choice_domains.spell_school.values"
      )

    opposed = ctx.ruleset.casting.school_specialization[:wizard].opposed_schools

    names
    |> Enum.sort()
    |> Enum.reduce(tally, fn {row, school}, tally ->
      opposition = TwoDA.int(table, row, "Opposition")

      if is_nil(opposition) do
        tally
      else
        Tally.check(
          tally,
          names[opposition],
          opposed[String.to_existing_atom(school)] &&
            Atom.to_string(opposed[String.to_existing_atom(school)]),
          subject: school,
          field: "opposition",
          base_at: "spellschools.2da:#{row}.Opposition",
          ours_at: "casting.school_specialization.wizard.opposed_schools"
        )
      end
    end)
  end

  # ------------------------------------------------------------ constants --

  defp constants(ctx) do
    tally = Tally.new(:constants, "Константы движка (ruleset.2da) против чисел ванильного слоя")
    c = ctx.constants
    r = ctx.ruleset

    probes = [
      {"MULTICLASS_LIMIT", r.max_classes, "max_classes (rules.json → character.max_classes)"},
      {"CHARGEN_BASE_ABILITY_MIN", r.point_buy.min_score, "point_buy.min_score"},
      {"CHARGEN_BASE_ABILITY_MAX", r.point_buy.max_score, "point_buy.max_score"},
      {"CHARGEN_BASE_ABILITY_MIN_PRIMARY", r.point_buy.caster_minimum.value,
       "point_buy.caster_minimum.value"},
      {"CHARGEN_SKILL_MAX_LEVEL_1_BONUS", r.skill_rank_caps[1].class - 1,
       "skill_rank_caps[1].class − 1"},
      {"TUMBLE_NUM_RANKS_PER_AC_BONUS", amount(r, :ac_bonuses, :tumble, :per_ranks),
       "ac_bonuses.tumble.per_ranks"},
      {"SPELLCRAFT_NUM_RANKS_PER_SAVE_BONUS",
       r.skill_rules.save_bonus |> hd() |> Map.get(:per_ranks),
       "skill_rules.save_bonus[spellcraft].per_ranks"},
      {"MAX_AC_DODGE_MOD", r.stat_caps[:dodge_ac], "stat_caps.dodge_ac"},
      {"FEAT_TOUGHNESS_HP_BONUS", amount(r, :hp_bonuses, :toughness, :hp),
       "hp_bonuses.toughness"},
      {"FEAT_EPIC_TOUGHNESS_HP_BONUS_1", amount(r, :hp_bonuses, :epic_toughness, :hp),
       "hp_bonuses.epic_toughness (за взятие)"},
      {"FEAT_EPIC_TOUGHNESS_HP_BONUS_10", amount(r, :hp_bonuses, :epic_toughness, :max_total),
       "hp_bonuses.epic_toughness.max_total"},
      {"FEAT_DEATHLESS_VIGOR_HP_BONUS", pm_vigor(r, 10),
       "hp_bonuses.deathless_vigor (Бледный мастер 5–10)"},
      {"FEAT_EPIC_DEATHLESS_VIGOR_HP_BONUS", pm_vigor(r, 15),
       "hp_bonuses.deathless_vigor (Бледный мастер 15+)"},
      {"EPIC_GREAT_STAT_BONUS", amount(r, :ability_bonuses, :great_strength, :bonus),
       "ability_bonuses.great_*"},
      {"DIAMOND_SOUL_SPELL_RESISTANCE_BASE", amount(r, :spell_resistance, :diamond_soul, :plus),
       "spell_resistance.diamond_soul.plus"},
      {"EPIC_SPELL_RESISTANCE_1", amount(r, :spell_resistance, :improved_spell_resistance, :sr),
       "spell_resistance.improved_spell_resistance.sr"},
      {"EPIC_SPELL_RESISTANCE_10",
       amount(r, :spell_resistance, :improved_spell_resistance, :max_total), "…max_total"},
      {"RESISTANCE_TO_ENERGY", amount(r, :resistance_bonuses, :resist_energy, :bonus),
       "resistance_bonuses.resist_energy"},
      {"EPIC_ENERGY_RESISTANCE_AMOUNT_1",
       amount(r, :resistance_bonuses, :epic_energy_resistance, :bonus),
       "resistance_bonuses.epic_energy_resistance"},
      {"EPIC_ENERGY_RESISTANCE_AMOUNT_10",
       amount(r, :resistance_bonuses, :epic_energy_resistance, :max_total), "…max_total"},
      {"WEAPON_FOCUS_BONUS", amount(r, :attack_bonuses, :weapon_focus, :bonus),
       "attack_bonuses.weapon_focus"},
      {"EPIC_WEAPON_FOCUS_BONUS", amount(r, :attack_bonuses, :epic_weapon_focus, :bonus),
       "attack_bonuses.epic_weapon_focus"},
      {"EPIC_PROWESS_ATTACK_BONUS", amount(r, :attack_bonuses, :epic_prowess, :bonus),
       "attack_bonuses.epic_prowess"},
      {"GOOD_AIM_MODIFIER", amount(r, :attack_bonuses, :good_aim, :bonus),
       "attack_bonuses.good_aim"},
      {"POINT_BLANK_SHOT_ATTACK_BONUS", amount(r, :attack_bonuses, :point_blank_shot, :bonus),
       "attack_bonuses.point_blank_shot"},
      {"OFFENSIVE_TRAINING_MODIFIER",
       amount(r, :attack_bonuses, :battle_training_vs_orcs, :bonus),
       "attack_bonuses.battle_training_vs_*"},
      {"NATURE_SENSE_TO_HIT_MODIFIER", amount(r, :attack_bonuses, :nature_sense, :bonus),
       "attack_bonuses.nature_sense"},
      {"OPPORTUNIST_TO_HIT_MODIFIER", amount(r, :attack_bonuses, :opportunist, :bonus),
       "attack_bonuses.opportunist"},
      {"EPIC_BANE_OF_ENEMIES_ATTACK_BONUS", amount(r, :attack_bonuses, :bane_of_enemies, :bonus),
       "attack_bonuses.bane_of_enemies"},
      {"CREATURE_SIZE_SMALL_ATTACK_BONUS", amount(r, :attack_bonuses, :small_stature, :bonus),
       "attack_bonuses.small_stature"},
      {"POWER_ATTACK_TO_HIT_MODIFIER", amount(r, :attack_bonuses, :power_attack, :bonus),
       "attack_bonuses.power_attack"},
      {"IMPROVED_POWER_ATTACK_TO_HIT_MODIFIER",
       amount(r, :attack_bonuses, :improved_power_attack, :bonus),
       "attack_bonuses.improved_power_attack"},
      {"EXPERTISE_TO_HIT_MODIFIER", amount(r, :attack_bonuses, :expertise, :bonus),
       "attack_bonuses.expertise"},
      {"IMPROVED_EXPERTISE_TO_HIT_MODIFIER",
       amount(r, :attack_bonuses, :improved_expertise, :bonus),
       "attack_bonuses.improved_expertise"},
      {"RAPID_SHOT_TO_HIT_MODIFIER", amount(r, :attack_bonuses, :rapid_shot, :bonus),
       "attack_bonuses.rapid_shot"},
      {"FLURRY_OF_BLOWS_TO_HIT_MODIFIER", amount(r, :attack_bonuses, :flurry_of_blows, :bonus),
       "attack_bonuses.flurry_of_blows"},
      {"CALLED_SHOT_TO_HIT_MODIFIER", amount(r, :attack_bonuses, :called_shot, :bonus),
       "attack_bonuses.called_shot"},
      {"DISARM_TO_HIT_MODIFIER", amount(r, :attack_bonuses, :disarm, :bonus),
       "attack_bonuses.disarm"},
      {"IMPROVED_DISARM_TO_HIT_MODIFIER", amount(r, :attack_bonuses, :improved_disarm, :bonus),
       "attack_bonuses.improved_disarm"},
      {"KNOCKDOWN_TO_HIT_MODIFIER", amount(r, :attack_bonuses, :knockdown, :bonus),
       "attack_bonuses.knockdown"},
      {"SAP_TO_HIT_MODIFIER", amount(r, :attack_bonuses, :sap, :bonus), "attack_bonuses.sap"},
      {"STUNNING_FIST_TO_HIT_MODIFIER", amount(r, :attack_bonuses, :stunning_fist, :bonus),
       "attack_bonuses.stunning_fist"},
      {"LUCKY_SAVE_BONUS", amount(r, :save_bonuses, :lucky, :bonus), "save_bonuses.lucky"},
      {"GREAT_FORTITUDE_SAVE_BONUS", amount(r, :save_bonuses, :great_fortitude, :bonus),
       "save_bonuses.great_fortitude"},
      {"IRON_WILL_SAVE_BONUS", amount(r, :save_bonuses, :iron_will, :bonus),
       "save_bonuses.iron_will"},
      {"LIGHTNING_REFLEXES_SAVE_BONUS", amount(r, :save_bonuses, :lightning_reflexes, :bonus),
       "save_bonuses.lightning_reflexes"},
      {"EPIC_FORTITUDE_SAVE_BONUS", amount(r, :save_bonuses, :epic_fortitude, :bonus),
       "save_bonuses.epic_fortitude"},
      {"EPIC_REFLEXES_REFLEX_BONUS", amount(r, :save_bonuses, :epic_reflexes, :bonus),
       "save_bonuses.epic_reflexes"},
      {"EPIC_WILL_SAVE_BONUS", amount(r, :save_bonuses, :epic_will, :bonus),
       "save_bonuses.epic_will"},
      {"LUCKOFHEROES_SAVE_BONUS", amount(r, :save_bonuses, :luck_of_heroes, :bonus),
       "save_bonuses.luck_of_heroes"},
      {"STRONG_SOUL_SAVE_BONUS", amount(r, :save_bonuses, :strong_soul, :bonus),
       "save_bonuses.strong_soul"},
      {"BULLHEADED_WILL_SAVE_BONUS", amount(r, :save_bonuses, :bullheaded, :bonus),
       "save_bonuses.bullheaded"},
      {"SNAKE_BLOOD_REFLEX_BONUS", amount(r, :save_bonuses, :snake_blood, :bonus),
       "save_bonuses.snake_blood"},
      {"HARDINESS_SAVE_BONUS", amount(r, :save_bonuses, :hardiness_vs_poisons, :bonus),
       "save_bonuses.hardiness_vs_*"},
      {"FEARLESS_MORALE_BONUS", amount(r, :save_bonuses, :fearless, :bonus),
       "save_bonuses.fearless"},
      {"RESIST_POISON_BONUS", amount(r, :save_bonuses, :resist_poison, :bonus),
       "save_bonuses.resist_poison"},
      {"RESIST_DISEASE_BONUS", amount(r, :save_bonuses, :resist_disease, :bonus),
       "save_bonuses.resist_disease"},
      {"RESIST_NATURES_LURE_SAVE_BONUS", amount(r, :save_bonuses, :resist_natures_lure, :bonus),
       "save_bonuses.resist_natures_lure"},
      {"STILL_MIND_COMPETANCE_BONUS", amount(r, :save_bonuses, :still_mind, :bonus),
       "save_bonuses.still_mind"},
      {"DENEIRS_EYE_SAVE_BONUS", amount(r, :save_bonuses, :deneirs_eye, :bonus),
       "save_bonuses.deneirs_eye"},
      {"LLIIRAS_HEART_SAVE_BONUS", amount(r, :save_bonuses, :lliiras_heart, :bonus),
       "save_bonuses.lliiras_heart"},
      {"ARCANE_DEFENSE_SAVE_BONUS", amount(r, :save_bonuses, :arcane_defense, :bonus),
       "save_bonuses.arcane_defense"},
      {"DEFENSIVE_AWARENESS_SAVE_BONUS", amount(r, :save_bonuses, :defensive_awareness, :bonus),
       "save_bonuses.defensive_awareness"},
      {"FEAT_DEFENSIVES_STANCE_SAVE_BONUS", amount(r, :save_bonuses, :defensive_stance, :bonus),
       "save_bonuses.defensive_stance"},
      {"FEAT_DEFENSIVES_STANCE_CON_BONUS", amount(r, :ability_bonuses, :defensive_stance, :bonus),
       "ability_bonuses.defensive_stance (CON)"},
      {"FEAT_DEFENSIVES_STANCE_DODGE_BONUS", amount(r, :ac_bonuses, :defensive_stance, :ac),
       "ac_bonuses.defensive_stance"},
      {"ALERTNESS_SKILL_BONUS", amount(r, :skill_bonuses, :alertness, :bonus),
       "skill_bonuses.alertness"},
      {"SKILL_FOCUS_SKILL_BONUS", amount(r, :skill_bonuses, :skill_focus, :bonus),
       "skill_bonuses.skill_focus"},
      {"EPIC_SKILL_FOCUS_SKILL_BONUS", amount(r, :skill_bonuses, :epic_skill_focus, :bonus),
       "skill_bonuses.epic_skill_focus"},
      {"SKILL_AFFINITY_SKILL_BONUS", amount(r, :skill_bonuses, :skill_affinity_listen, :bonus),
       "skill_bonuses.skill_affinity_*"},
      {"PARTIAL_SKILL_FOCUS_SKILL_BONUS",
       amount(r, :skill_bonuses, :partial_skill_affinity_listen, :bonus),
       "skill_bonuses.partial_skill_affinity_*"},
      {"STONECUNNING_SEARCH_SKILL_BONUS", amount(r, :skill_bonuses, :stonecunning, :bonus),
       "skill_bonuses.stonecunning"},
      {"TRACKLESS_STEP_SKILL_BONUS", amount(r, :skill_bonuses, :trackless_step, :bonus),
       "skill_bonuses.trackless_step"},
      {"ARTIST_PERFORM_BONUS", amount(r, :skill_bonuses, :artist, :bonus),
       "skill_bonuses.artist"},
      {"BLOODED_SPOT_BONUS", amount(r, :skill_bonuses, :blooded, :bonus),
       "skill_bonuses.blooded"},
      {"COURTEOUS_MAGOCRACY_LORE_BONUS", amount(r, :skill_bonuses, :courteous_magocracy, :bonus),
       "skill_bonuses.courteous_magocracy"},
      {"SILVER_PALM_PERSUADE_BONUS", amount(r, :skill_bonuses, :silver_palm, :bonus),
       "skill_bonuses.silver_palm"},
      {"STEALTHY_HIDE_BONUS", amount(r, :skill_bonuses, :stealthy, :bonus),
       "skill_bonuses.stealthy"},
      {"THUG_PERSUADE_BONUS", amount(r, :skill_bonuses, :thug, :bonus), "skill_bonuses.thug"},
      {"EPIC_REPUTATION_SKILL_BONUS", amount(r, :skill_bonuses, :epic_reputation, :bonus),
       "skill_bonuses.epic_reputation"},
      {"DODGE_AC_BONUS", amount(r, :ac_bonuses, :dodge, :ac), "ac_bonuses.dodge"},
      {"MOBILITY_DODGE_BONUS", amount(r, :ac_bonuses, :mobility, :ac), "ac_bonuses.mobility"},
      {"DEFENSIVE_TRAINING_MODIFIER", amount(r, :ac_bonuses, :battle_training_vs_giants, :ac),
       "ac_bonuses.battle_training_vs_giants"},
      {"EXPERTISE_AC_BONUS", amount(r, :ac_bonuses, :expertise, :ac), "ac_bonuses.expertise"},
      {"IMPROVED_EXPERTISE_AC_BONUS", amount(r, :ac_bonuses, :improved_expertise, :ac),
       "ac_bonuses.improved_expertise"},
      {"EPIC_ARMOR_SKIN_NATURAL_AC_BONUS", amount(r, :ac_bonuses, :armor_skin, :ac),
       "ac_bonuses.armor_skin"},
      {"CREATURE_SIZE_SMALL_AC_BONUS", amount(r, :ac_bonuses, :small_stature, :ac),
       "ac_bonuses.small_stature"},
      {"ONHAND_NORMAL_OFFHAND_ATTACK_PENALTY", r.dual_wield.base_penalty.main,
       "dual_wield.base_penalty.main"},
      {"OFFHAND_NORMAL_OFFHAND_ATTACK_PENALTY", r.dual_wield.base_penalty.off,
       "dual_wield.base_penalty.off"},
      {"LIGHT_OFFHAND_WEAPON_BONUS", r.dual_wield.light_off_hand.main,
       "dual_wield.light_off_hand"},
      {"TWO_WEAPON_FIGHTING_BONUS", step(r, :two_weapon_fighting, :main),
       "dual_wield.steps[two_weapon_fighting]"},
      {"AMBIDEXTERITY_BONUS", step(r, :ambidexterity, :off),
       "dual_wield.steps[ambidexterity].off"}
    ]

    tally =
      Enum.reduce(probes, tally, fn {label, ours, where}, tally ->
        Tally.check(tally, c[label], ours,
          subject: label,
          field: "value",
          base_at: "ruleset.2da #{label}",
          ours_at: where
        )
      end)

    tally
    |> point_buy_costs(ctx)
    |> shard_constants(ctx, MapSet.new(probes, &elem(&1, 0)))
    |> Tally.check(c["MIN_LEVEL_FOR_MAX_HP"], :every_level,
      subject: "MIN_LEVEL_FOR_MAX_HP",
      field: "value",
      base_at:
        "ruleset.2da MIN_LEVEL_FOR_MAX_HP (максимум кости на уровнях персонажа 1..N, дальше бросок)",
      ours_at:
        "Rules.Progression: максимум кости на каждом уровне (решение показа: rules.json → character.hit_points_shown)"
    )
    |> Tally.check(c["MULTIPLE_ATTACKS_BAB_PENALTY_MULTIPLIER"], attack_step(r),
      subject: "MULTIPLE_ATTACKS_BAB_PENALTY_MULTIPLIER",
      field: "value",
      base_at: "ruleset.2da MULTIPLE_ATTACKS_BAB_PENALTY_MULTIPLIER (шаг BAB между атаками)",
      ours_at: "attacks_per_round (шаг BAB, на котором прибавляется атака)"
    )
    |> Tally.check(
      {c["CREATURE_SIZE_SMALL_AC_BONUS"], c["CREATURE_SIZE_SMALL_ATTACK_BONUS"]},
      size_modifier(ctx, 2),
      subject: "creaturesize",
      field: "small",
      base_at: "creaturesize.2da:2 SMALL.ACATTACKMOD",
      ours_at: "ruleset.2da CREATURE_SIZE_SMALL_* (сверка двух таблиц между собой)"
    )
  end

  # Константы, которые шард переписал (хак против базы), а сверка выше их не
  # сравнивает: у нас таких чисел нет (урон, длительности, дистанции, скорость).
  # Одна находка со списком — так новая правка шарда в `ruleset.2da` не пройдёт
  # мимо: прибитое правило вида у Сиалы перестанет совпадать, и `--check` упадёт
  # (задача 4.49, п. 1). У ванили источника-слоя нет — проверки нет.
  @named_constants ~w(MIN_LEVEL_FOR_MAX_HP MULTIPLE_ATTACKS_BAB_PENALTY_MULTIPLIER
                      CREATURE_SIZE_SMALL_AC_BONUS CREATURE_SIZE_SMALL_ATTACK_BONUS
                      CHARGEN_ABILITY_COST_INCREMENT2 CHARGEN_ABILITY_COST_INCREMENT3
                      CHARGEN_ABILITY_COST_INCREMENT4)

  defp shard_constants(tally, ctx, probed) do
    if Source.layered?(ctx.source) do
      base = Source.table(ctx.source.base, "ruleset")
      top = Source.table(ctx.source, "ruleset")
      base_values = Map.new(TwoDA.rows(base), fn {_i, r} -> {r["Label"], r["Value"]} end)

      changed =
        for {i, r} <- TwoDA.rows(top),
            label = r["Label"],
            label != nil,
            base_values[label] != r["Value"],
            not MapSet.member?(probed, label),
            label not in @named_constants,
            do: "#{label} #{base_values[label] || "—"} → #{r["Value"]} [#{i}]"

      Tally.check(tally, changed, [],
        subject: "hak_changed_unprobed",
        field: "value",
        base_at: "ruleset.2da: константы, которые хак переписал против базы",
        ours_at: "у нас таких чисел нет — сверка их не сравнивает"
      )
    else
      tally
    end
  end

  defp point_buy_costs(tally, ctx) do
    c = ctx.constants

    derived =
      cumulative_costs(c["CHARGEN_BASE_ABILITY_MIN"], c["CHARGEN_BASE_ABILITY_MAX"], [
        c["CHARGEN_ABILITY_COST_INCREMENT2"],
        c["CHARGEN_ABILITY_COST_INCREMENT3"],
        c["CHARGEN_ABILITY_COST_INCREMENT4"]
      ])

    Tally.check(tally, derived, ctx.ruleset.point_buy.cost,
      subject: "CHARGEN_ABILITY_COST_INCREMENT2/3/4",
      field: "cost_table",
      base_at:
        "ruleset.2da: шаг стоит 1 до INCREMENT2, 2 до INCREMENT3, 3 до INCREMENT4 (накопительно от BASE_ABILITY_MIN)",
      ours_at: "point_buy.cost"
    )
  end

  # Стоимость поднять на следующую единицу: 1, пока текущее значение < INC2,
  # 2 — пока < INC3, 3 — пока < INC4. Проверено на известной таблице Fandom
  # (18 стоит 16): совпадение — это и есть результат сверки.
  defp cumulative_costs(min, max, [inc2, inc3, inc4]) when is_integer(min) and is_integer(max) do
    Enum.reduce(min..max, %{}, fn score, acc ->
      if score == min do
        Map.put(acc, score, 0)
      else
        from = score - 1

        step =
          cond do
            from < inc2 -> 1
            from < inc3 -> 2
            from < inc4 -> 3
            true -> 4
          end

        Map.put(acc, score, acc[from] + step)
      end
    end)
  end

  defp cumulative_costs(_min, _max, _incs), do: nil

  defp amount(ruleset, section, id, key) do
    Enum.find_value([:applied, :counted_elsewhere, :unmodelled], fn bucket ->
      case Enum.find(Map.get(Map.get(ruleset, section), bucket, []), &(&1.id == id)) do
        %{amount: amount} when is_map(amount) -> Map.get(amount, key)
        _ -> nil
      end
    end)
  end

  defp pm_vigor(ruleset, level) do
    case amount(ruleset, :hp_bonuses, :deathless_vigor, :hp_at_class_level) do
      %{} = table -> table[level]
      _ -> nil
    end
  end

  defp step(ruleset, feat, hand) do
    Enum.find_value(ruleset.dual_wield.steps, fn s -> if s.feat == feat, do: Map.get(s, hand) end)
  end

  # Атака прибавляется на BAB 6, 11, 16 — шаг 5.
  defp attack_step(ruleset) do
    ruleset.attacks_per_round
    |> Enum.sort()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [{_, a}, {_, b}] -> b > a end)
    |> Enum.map(fn [_, {bab, _}] -> bab end)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> b - a end)
    |> Enum.uniq()
    |> case do
      [n] -> n
      other -> other
    end
  end

  defp size_modifier(ctx, category) do
    sizes = Source.table(ctx.source, "creaturesize")
    n = sizes && TwoDA.int(sizes, category, "ACATTACKMOD")
    {n, n}
  end

  # ------------------------------------------------------------------- xp --

  defp xp(ctx) do
    tally = Tally.new(:xp, "Опыт и кап уровня (exptable.2da)")
    table = Source.table(ctx.source, "exptable")

    reachable =
      for {_i, r} <- TwoDA.rows(table),
          xp = TwoDA.to_int(r["XP"]),
          is_integer(xp) and xp < 0xFFFFFFFF,
          do: {TwoDA.to_int(r["Level"]), xp}

    ours =
      for row <- ctx.raw_epic["level_table"]["rows"],
          into: %{},
          do: {row["character_level"], row["required_xp"]}

    tally =
      Tally.check(tally, length(reachable), ctx.ruleset.level_cap,
        subject: "level_cap",
        field: "value",
        base_at: "exptable.2da: строк с достижимым опытом (строка 41 — 0xFFFFFFFF)",
        ours_at: "level_cap (epic.json → character_level_cap)"
      )

    Enum.reduce(Enum.sort(ours), tally, fn {level, xp}, tally ->
      Tally.check(tally, Map.new(reachable)[level], xp,
        subject: "level_#{level}",
        field: "required_xp",
        base_at: "exptable.2da:#{level - 1}.XP",
        ours_at: "epic.json → level_table[#{level}].required_xp"
      )
    end)
  end

  defp lower_atom(nil), do: nil
  defp lower_atom(value), do: value |> String.downcase() |> String.to_existing_atom()
end
