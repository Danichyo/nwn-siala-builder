defmodule BuildCalculator.Base2da.Hak2daPositiveControlTest do
  @moduledoc """
  Положительный контроль сверки хака Сиалы `mix hak2da.diff` (задача 4.49): в
  загруженный ruleset `siala_41` вносится одна порча на область, и сверка
  обязана её увидеть — новой находкой или находкой, которая перестала совпадать
  со своим прибитым правилом и осталась без вида. Сравнение, которое ни разу
  не расходилось, иначе нельзя отличить от слепого.

  Здесь же — сторожа самой классификации: у каждой находки на неиспорченных
  данных есть вид, и у каждого правила Сиалы есть находка, к которой оно
  прибито (правило, которое ни к чему не подходит, — устаревший довод).

  Нужны обе выгрузки — `priv/hak/2da/` и `priv/base_2da/`; в публичном
  репозитории и в CI их нет, и модуль пропускается, а не падает.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.{Finding, SialaClassification, SialaDiff, Source}

  @hak Path.expand("../../../priv/hak/2da", __DIR__)
  @base Path.expand("../../../priv/base_2da", __DIR__)

  unless File.regular?(Path.join(@hak, "manifest.json")) and
           File.regular?(Path.join(@base, "manifest.json")) do
    @moduletag skip:
                 "нет priv/hak или priv/base_2da (публичный репозиторий, CI) — " <>
                   "выгрузки: mix hak.extract, mix base2da.extract"
  end

  setup_all do
    {:ok, source} = Source.load_layered(@hak, @base)

    index =
      SialaDiff.vanilla_index(source.base, BuildCalculator.Data.ruleset!("vanilla"), "priv/rules")

    ruleset = BuildCalculator.Data.ruleset!("siala_41")
    baseline = findings(source, ruleset, index)

    %{source: source, index: index, ruleset: ruleset, baseline: baseline}
  end

  # Порча → ключ находки, которая обязана появиться (или потерять вид).
  @mutated ~w(
    classes/monk/bab[5]
    classes/fighter/hit_die
    classes/purple_dragon_knight/class_level_cap
    class_feats/fighter/bonus_feat_levels
    class_feats/bard/bonus_feat_levels
    class_feats/summon_mount/granted_first
    class_feats/brew_potion/bonus_for
    class_bonus_values/champion_of_torm/weapon_focus
    class_bonus_values/paladin/overwhelming_critical
    class_bonus_values/rogue/epic_skill_focus
    class_bonus_values/arcane_archer/epic_weapon_focus
    class_bonus_values/assassin/epic_skill_focus
    class_bonus_values/harper_scout/epic_skill_focus
    class_requirements/arcane_archer/requirement/weapon_focus_choice
    class_requirements/monk/alignment
    spellcasting/cleric/spells_per_day[5][3]
    feats/lasting_inspiration/feats
    feats/power_attack/abilities
    repeatable/epic_skill_focus/choice
    feat_classes/mount_actions/general_slot_for
    skills/hide/key_ability
    races/gnome/size
    stat_gains/arcane_archer/enchant_arrow_attack
    weapons/trident/size
    weapons/longsword/proficiency
    weapons/whip/off_hand_slot
    weapons/quarterstaff/finesse_medium
    armor/full_plate/max_dex
    spells/fireball/levels
    spells/endure_elements/name
    domains/domains/set
    schools/necromancy/opposition
    xp/level_cap/value
    constants/MULTICLASS_LIMIT/value
    constants/EPIC_ENERGY_RESISTANCE_AMOUNT_1/value
    constants/POINT_BLANK_SHOT_ATTACK_BONUS/value
    constants/CALLED_SHOT_TO_HIT_MODIFIER/value
    constants/CHARGEN_ABILITY_COST_INCREMENT2/3/4/cost_table
  )

  for key <- @mutated do
    @key key
    test "порча ловится: #{key}", ctx do
      before = ctx.baseline[@key]

      refute before && before.kind == nil,
             "#{@key} без вида и без порчи — контроль не контролирует"

      mutated = findings(ctx.source, mutate(@key, ctx.ruleset), ctx.index)
      found = mutated[@key]

      assert found, "#{@key}: порчу сверка не увидела"

      if before do
        # Находка была и раньше, прибитая правилом, — порча обязана выбить её
        # из правила: другое значение без вида, а не тихо тот же довод.
        assert found.kind == nil or {found.base, found.ours} != {before.base, before.ours}
      end
    end
  end

  test "на неиспорченных данных у каждой находки есть вид", %{baseline: baseline} do
    assert for({key, %{kind: nil}} <- baseline, do: key) == []
  end

  test "у каждого правила Сиалы есть находка, к которой оно прибито", %{baseline: baseline} do
    used =
      for {_key, finding} <- baseline,
          finding.note,
          rule <- SialaClassification.rules(),
          rule.note == finding.note,
          into: MapSet.new(),
          do: rule.note

    unused = for rule <- SialaClassification.rules(), rule.note not in used, do: inspect(rule.key)

    assert unused == [], "правила без находок (устаревший довод?): #{Enum.join(unused, ", ")}"
  end

  test "исправленные находки (a) задачи 4.49 в отчёте не встречаются", %{baseline: baseline} do
    fixed = ~w(
      feats/lasting_inspiration/feats
      class_feats/summon_mount/granted_first
      class_feats/brew_potion/bonus_for
      class_bonus_values/champion_of_torm/weapon_focus
      class_bonus_values/champion_of_torm/improved_critical
      class_bonus_values/paladin/overwhelming_critical
      feat_classes/mount_actions/general_slot_for
      class_feats/mounted_combat/bonus_for
      class_feats/mounted_archery/bonus_for
      class_feats/mount_actions/granted_first
    )

    assert Enum.filter(fixed, &Map.has_key?(baseline, &1)) == []
  end

  test "находки (a) области бонусного слота по значению задачи 4.50 в отчёте не встречаются",
       %{baseline: baseline} do
    fixed = ~w(
      class_bonus_values/arcane_archer/epic_weapon_focus
      class_bonus_values/arcane_archer/overwhelming_critical
      class_bonus_values/assassin/epic_skill_focus
      class_bonus_values/bard/epic_skill_focus
      class_bonus_values/harper_scout/epic_skill_focus
      class_bonus_values/rogue/epic_skill_focus
      class_bonus_values/shadowdancer/epic_skill_focus
    )

    assert Enum.filter(fixed, &Map.has_key?(baseline, &1)) == []
    assert for({"class_bonus_values/" <> _ = key, _} <- baseline, do: key) == []
  end

  test "находки (a) бонусного уровня 41 задачи 4.51 в отчёте не встречаются",
       %{baseline: baseline} do
    fixed =
      for class <- ~w(bard cleric paladin ranger sorcerer wizard),
          do: "class_feats/#{class}/bonus_feat_levels"

    assert Enum.filter(fixed, &Map.has_key?(baseline, &1)) == []
    assert for({"class_feats/" <> _ = key, %{kind: :a}} <- baseline, do: key) == []
  end

  # Задача 4.58: строка 50 хака названа (`SialaRows`), и находка про имя ушла
  # не потому, что сверка её больше не видит, — порча `spells/endure_elements/name`
  # выше возвращает её.
  test "находка (a) имени заклинания шарда задачи 4.58 в отчёте не встречается",
       %{baseline: baseline} do
    assert Enum.filter(
             ~w(spells/endure_elements/unmapped_id spells/endure_elements/name),
             &Map.has_key?(baseline, &1)
           ) == []

    assert for({"spells/" <> _ = key, %{kind: :a}} <- baseline, do: key) == []
  end

  # Задача 4.57: числа Point blank shot и Called shot шарда — в слое
  # `siala_41/feat_attack_bonuses.json`, и находки ушли не потому, что сверка
  # их больше не видит, — порчи обоих ключей выше возвращают их.
  test "находки (b) констант атаки задачи 4.57 в отчёте не встречаются", %{baseline: baseline} do
    assert Enum.filter(
             ~w(constants/POINT_BLANK_SHOT_ATTACK_BONUS/value
                constants/CALLED_SHOT_TO_HIT_MODIFIER/value),
             &Map.has_key?(baseline, &1)
           ) == []
  end

  defp findings(source, ruleset, index) do
    SialaDiff.run(source, ruleset, "priv/rules", vanilla_index: index).areas
    |> Enum.flat_map(& &1.findings)
    |> Map.new(&{Finding.key(&1), &1})
  end

  # --------------------------------------------------------------- порчи --

  defp mutate("classes/monk/bab[5]", r),
    do: update_in(r.classes[:monk].progression[5].bab, &(&1 - 1))

  defp mutate("classes/fighter/hit_die", r), do: put_in(r.classes[:fighter].hit_die, 8)

  # Исключение PDK у Сиалы — 10 (хак, MaxLevel 10); вернуть ванильные 5.
  defp mutate("classes/purple_dragon_knight/class_level_cap", r),
    do: put_in(r.prestige.level_cap_exceptions[:purple_dragon_knight], 5)

  defp mutate("class_feats/fighter/bonus_feat_levels", r),
    do: update_in(r.classes[:fighter].bonus_feat_levels, &MapSet.delete(&1, 4))

  # Задача 4.51: вернуть шкалу барда к таблице Fandom — без 41-го уровня класса.
  defp mutate("class_feats/bard/bonus_feat_levels", r),
    do: update_in(r.classes[:bard].epic_bonus_feat_levels, &MapSet.delete(&1, 41))

  # Порчи ниже возвращают правки задачи 4.49 к тому, что было до них.
  defp mutate("class_feats/summon_mount/granted_first", r),
    do: update_in(r.classes[:paladin].granted_feats, &Map.put(&1, 5, [:summon_mount]))

  defp mutate("class_feats/brew_potion/bonus_for", r),
    do: put_in(r.feats[:brew_potion].bonus_for, MapSet.new([:wizard]))

  defp mutate("class_bonus_values/champion_of_torm/weapon_focus", r),
    do:
      update_in(
        r.feats[:weapon_focus].bonus_for_except,
        &MapSet.delete(&1, {:champion_of_torm, :trident})
      )

  defp mutate("class_bonus_values/paladin/overwhelming_critical", r),
    do:
      update_in(
        r.feats[:overwhelming_critical].bonus_for_except,
        &MapSet.delete(&1, {:paladin, :club})
      )

  defp mutate("class_bonus_values/rogue/epic_skill_focus", r),
    do:
      update_in(r.feats[:epic_skill_focus].bonus_for_except, &MapSet.delete(&1, {:rogue, :ride}))

  # Задача 4.50: область у Сиалы сошлась целиком. Порчи снимают ванильную запись
  # «только эти значения» (доезжает до Сиалы сама — хак несёт те же строки) и
  # правило уровня (Perform только на уровне барда), которое сверка с этой
  # задачи читает: без него Арфист «берёт» Perform бонусным слотом.
  defp mutate("class_bonus_values/arcane_archer/epic_weapon_focus", r),
    do: update_in(r.feats[:epic_weapon_focus].bonus_for_only, &Map.delete(&1, :arcane_archer))

  defp mutate("class_bonus_values/assassin/epic_skill_focus", r),
    do: update_in(r.feats[:epic_skill_focus].bonus_for_only, &Map.delete(&1, :assassin))

  defp mutate("class_bonus_values/harper_scout/epic_skill_focus", r),
    do:
      update_in(
        r.feats[:epic_skill_focus].prereqs["only_on_class_levels_for_skill"],
        &Map.delete(&1, "perform")
      )

  defp mutate("class_requirements/arcane_archer/requirement/weapon_focus_choice", r),
    do:
      put_in(r.classes[:arcane_archer].requirements[:feat_choices], %{
        "weapon_focus" => ["shortbow", "longbow"]
      })

  defp mutate("class_requirements/monk/alignment", r),
    do: put_in(r.classes[:monk].alignment_restriction, :any)

  defp mutate("spellcasting/cleric/spells_per_day[5][3]", r),
    do: update_in(r.classes[:cleric].spells_per_day[5], &Map.put(&1, 3, 9))

  defp mutate("feats/lasting_inspiration/feats", r),
    do: update_in(r.feats[:lasting_inspiration].prereqs, &Map.delete(&1, "class_levels"))

  defp mutate("feats/power_attack/abilities", r),
    do: put_in(r.feats[:power_attack].prereqs, %{"abilities" => %{"str" => 15}})

  defp mutate("repeatable/epic_skill_focus/choice", r),
    do: put_in(r.feats[:epic_skill_focus].repeatable, nil)

  defp mutate("feat_classes/mount_actions/general_slot_for", r),
    do: put_in(r.feats[:mount_actions].level_up_selectable?, true)

  defp mutate("skills/hide/key_ability", r), do: put_in(r.skills[:hide].key_ability, :str)

  # Карлик = Gnome: имя расы у хака из .tlk шарда, сопоставлено откатом на базу.
  defp mutate("races/gnome/size", r), do: put_in(r.races[:gnome].size, :medium)

  defp mutate("stat_gains/arcane_archer/enchant_arrow_attack", r) do
    update_in(r, [:attack_bonuses, :applied], fn records ->
      Enum.map(records, fn
        %{amount: %{class: :arcane_archer} = amount} = record
        when is_map_key(amount, :attack_at_class_level) ->
          %{record | amount: Map.update!(amount, :attack_at_class_level, &Map.delete(&1, 33))}

        record ->
          record
      end)
    end)
  end

  # Размер Сиалы — хак (`siala_41/weapons.json`, задача 4.42).
  defp mutate("weapons/trident/size", r), do: put_in(r.weapons[:trident].size, :large)

  defp mutate("weapons/longsword/proficiency", r),
    do: put_in(r.weapons[:longsword].proficiency, {:feat, :siala_axe_proficiency})

  # Кнут у Сиалы во вторую руку идёт (хак, строка 111) — порча запрещает.
  defp mutate("weapons/whip/off_hand_slot", r),
    do: update_in(r.wield.main_hand_only.slot, &MapSet.put(&1, :whip))

  # Посох фехтовальный у Сиалы (страница Weapon finesse) — порча снимает.
  defp mutate("weapons/quarterstaff/finesse_medium", r) do
    update_in(r.attack_ability.rules, fn rules ->
      Enum.map(rules, fn
        %{feat: :weapon_finesse} = rule ->
          %{rule | weapon_one_of: MapSet.delete(rule.weapon_one_of, :quarterstaff)}

        rule ->
          rule
      end)
    end)
  end

  defp mutate("armor/full_plate/max_dex", r) do
    update_in(r.gear.worn, fn worn ->
      Enum.map(worn, fn
        %{id: :armor} = category ->
          %{
            category
            | items:
                Enum.map(category.items, fn
                  %{id: :full_plate} = item -> %{item | max_dex: 2}
                  item -> item
                end)
          }

        category ->
          category
      end)
    end)
  end

  defp mutate("spells/fireball/levels", r), do: put_in(r.spells[:fireball].levels, %{mage: 4})

  # Задача 4.58: вернуть ванильное имя строке 50 — так было до слоя Сиалы.
  defp mutate("spells/endure_elements/name", r),
    do: put_in(r.spells[:endure_elements].name, "Endure elements")

  defp mutate("domains/domains/set", r),
    do: update_in(r.choice_domains[:domain].values, &MapSet.delete(&1, :fire))

  defp mutate("schools/necromancy/opposition", r),
    do: put_in(r.casting.school_specialization[:wizard].opposed_schools[:necromancy], :illusion)

  defp mutate("xp/level_cap/value", r), do: put_in(r.level_cap, 40)
  defp mutate("constants/MULTICLASS_LIMIT/value", r), do: put_in(r.max_classes, 3)

  defp mutate("constants/EPIC_ENERGY_RESISTANCE_AMOUNT_1/value", r) do
    update_in(r, [:resistance_bonuses, :applied], fn records ->
      Enum.map(records, fn
        %{id: :epic_energy_resistance, amount: amount} = record ->
          %{record | amount: %{amount | bonus: 10}}

        record ->
          record
      end)
    end)
  end

  # Задача 4.57: вернуть ванильные числа, которые несла запись Сиалы до слоя.
  defp mutate("constants/POINT_BLANK_SHOT_ATTACK_BONUS/value", r),
    do: unmodelled_attack_bonus(r, :point_blank_shot, 1)

  defp mutate("constants/CALLED_SHOT_TO_HIT_MODIFIER/value", r),
    do: unmodelled_attack_bonus(r, :called_shot, -4)

  defp mutate("constants/" <> _, r), do: put_in(r.point_buy.cost[18], 14)

  defp unmodelled_attack_bonus(r, id, bonus) do
    update_in(r, [:attack_bonuses, :unmodelled], fn records ->
      Enum.map(records, fn
        %{id: ^id, amount: amount} = record -> %{record | amount: %{amount | bonus: bonus}}
        record -> record
      end)
    end)
  end
end
