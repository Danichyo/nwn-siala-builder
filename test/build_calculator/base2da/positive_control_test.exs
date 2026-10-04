defmodule BuildCalculator.Base2da.PositiveControlTest do
  @moduledoc """
  Положительный контроль сверки `mix base2da.diff` (задача 4.5): в загруженный
  ванильный ruleset вносится одна порча на область, и сверка обязана её увидеть.
  Сравнение, которое ни разу не расходилось, иначе нельзя отличить от слепого
  (HANDOFF.md: «Инвариант „сумма сходится“ слеп там, где слагаемого нет вовсе»).

  Нужна выгрузка `priv/base_2da/` — таблицы Beamdog/WotC, которых нет
  в публичном репозитории и в CI. Без неё модуль пропускается, а не падает.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.{Diff, Finding, Source}

  @dir Path.expand("../../../priv/base_2da", __DIR__)

  unless File.regular?(Path.join(@dir, "manifest.json")) do
    @moduletag skip:
                 "нет priv/base_2da (публичный репозиторий, CI) — выгрузка: mix base2da.extract"
  end

  setup_all do
    {:ok, source} = Source.load(@dir)
    ruleset = BuildCalculator.Data.ruleset!("vanilla")
    %{source: source, ruleset: ruleset, baseline: keys(source, ruleset)}
  end

  @mutated ~w(
    classes/wizard/hit_die
    classes/fighter/bab[5]
    class_requirements/monk/alignment
    class_feats/fighter/bonus_feat_levels
    spellcasting/cleric/spells_per_day[5][3]
    spellcasting/druid/spells_per_day[15][3]
    feats/power_attack/abilities
    skills/hide/key_ability
    races/gnome/size
    weapons/longsword/size
    spells/fireball/levels
    constants/CHARGEN_ABILITY_COST_INCREMENT2/3/4/cost_table
    repeatable/epic_toughness/max_takes
    repeatable/epic_skill_focus/choice
    weapons/club/proficiency
    feat_classes/great_smiting/general_slot_for
    feats/weapon_specialization/class_level/fighter
    feats/lasting_inspiration/feats
    class_feats/pale_master/bonus_feat_levels
    stat_gains/pale_master/natural_ac
    stat_gains/red_dragon_disciple/natural_ac
    stat_gains/arcane_archer/enchant_arrow_attack
    class_feats/mount_actions/granted_first
    class_requirements/weapon_master/requirement/weapon_focus_choice
    repeatable/overwhelming_critical/choice
    weapons/whip/off_hand_slot
    feat_classes/mount_actions/general_slot_for
    weapons/rapier/finesse_small
    class_bonus_values/arcane_archer/epic_weapon_focus
    class_bonus_values/assassin/epic_skill_focus
    class_bonus_values/rogue/epic_skill_focus
    class_bonus_values/harper_scout/epic_skill_focus
    class_bonus_values/bard/epic_skill_focus
  )

  for key <- @mutated do
    @key key
    test "порча ловится: #{key}", %{source: source, ruleset: ruleset, baseline: baseline} do
      found = keys(source, mutate(@key, ruleset))

      refute MapSet.member?(baseline, @key),
             "#{@key} расходится и без порчи — контроль не контролирует"

      assert MapSet.member?(found, @key)
    end
  end

  test "на неиспорченных данных у каждой находки есть вид", %{source: source, ruleset: ruleset} do
    unclassified =
      Diff.run(source, ruleset, "priv/rules").areas
      |> Enum.flat_map(& &1.findings)
      |> Enum.filter(&is_nil(&1.kind))
      |> Enum.map(&Finding.key/1)

    assert unclassified == []
  end

  defp mutate("classes/wizard/hit_die", r), do: put_in(r.classes[:wizard].hit_die, 6)

  defp mutate("classes/fighter/bab[5]", r),
    do: update_in(r.classes[:fighter].progression[5].bab, &(&1 + 1))

  defp mutate("class_requirements/monk/alignment", r),
    do: put_in(r.classes[:monk].alignment_restriction, :any)

  defp mutate("class_feats/fighter/bonus_feat_levels", r),
    do: update_in(r.classes[:fighter].bonus_feat_levels, &MapSet.delete(&1, 4))

  defp mutate("spellcasting/cleric/spells_per_day[5][3]", r),
    do: update_in(r.classes[:cleric].spells_per_day[5], &Map.put(&1, 3, 9))

  # Задача 4.44: порча возвращает ячейку туда, где она была до правки, — к числу
  # таблицы Fandom (5), которое машинный слой несёт и сегодня
  # (`vanilla/class_spell_tables.json` → `replaces`). Без ручного слоя сверка
  # обязана снова увидеть спор с cls_spgn_dru.2da.
  defp mutate("spellcasting/druid/spells_per_day[15][3]", r),
    do: update_in(r.classes[:druid].spells_per_day[15], &Map.put(&1, 3, 5))

  defp mutate("feats/power_attack/abilities", r),
    do: put_in(r.feats[:power_attack].prereqs, %{"abilities" => %{"str" => 15}})

  defp mutate("skills/hide/key_ability", r), do: put_in(r.skills[:hide].key_ability, :str)
  defp mutate("races/gnome/size", r), do: put_in(r.races[:gnome].size, :medium)
  defp mutate("weapons/longsword/size", r), do: put_in(r.weapons[:longsword].size, :large)
  defp mutate("spells/fireball/levels", r), do: put_in(r.spells[:fireball].levels, %{mage: 4})
  defp mutate("constants/" <> _, r), do: put_in(r.point_buy.cost[18], 14)

  # Задача 4.7: потолок взятий, выбор семейства и владение «любым из» —
  # три сверки, которые до неё ни разу не сходились (потолка и выбора у ванили
  # не было, владение было `:unread`), и теперь им нужна порча, чтобы отличить
  # сходимость от слепоты. Владение портится сведением к ОДНОЙ категории —
  # ровно той ошибкой, которую «любой из» и закрывает.
  defp mutate("repeatable/epic_toughness/max_takes", r),
    do: put_in(r.feats[:epic_toughness].repeatable.max_takes.value, 9)

  defp mutate("repeatable/epic_skill_focus/choice", r),
    do: put_in(r.feats[:epic_skill_focus].repeatable, nil)

  defp mutate("weapons/club/proficiency", r),
    do: put_in(r.weapons[:club].proficiency, {:feat, :weapon_proficiency_simple})

  # Задачи 4.24 и 4.25: три сверки, которые впервые сошлись у этих фитов, —
  # порча возвращает каждую ровно к тому, что было до правки. Ограничение
  # по классу уровня портится снятием запрета у ОДНОГО класса (у воина Great
  # smiting снова берётся общим слотом), требование — прежним прочтением
  # парсера: воин 1 и «любая песня барда».
  defp mutate("feat_classes/great_smiting/general_slot_for", r),
    do: update_in(r.classes[:fighter].unavailable_feats, &MapSet.delete(&1, :great_smiting))

  defp mutate("feats/weapon_specialization/class_level/fighter", r),
    do: put_in(r.feats[:weapon_specialization].prereqs["class_levels"], %{"fighter" => 1})

  defp mutate("feats/lasting_inspiration/feats", r),
    do: update_in(r.feats[:lasting_inspiration].prereqs, &Map.delete(&1, "class_levels"))

  # Задача 4.26: эпические шкалы престиж-классов за 30-м уровнем класса. Область
  # «прибавки по уровню класса» с этой задачи сходится ЦЕЛИКОМ, и без порчи её
  # сходимость неотличима от слепоты. Каждая порча снимает ровно одну ступень,
  # которую задача добавила, — то есть возвращает данные к тому, что было до неё.
  defp mutate("class_feats/pale_master/bonus_feat_levels", r),
    do: update_in(r.classes[:pale_master].epic_bonus_feat_levels, &MapSet.delete(&1, 31))

  defp mutate("stat_gains/pale_master/natural_ac", r),
    do: drop_step(r, :ac_bonuses, :pale_master, :ac_at_class_level, 32)

  defp mutate("stat_gains/red_dragon_disciple/natural_ac", r),
    do: drop_step(r, :ac_bonuses, :red_dragon_disciple, :ac_at_class_level, 35)

  defp mutate("stat_gains/arcane_archer/enchant_arrow_attack", r),
    do: drop_step(r, :attack_bonuses, :arcane_archer, :attack_at_class_level, 33)

  # Задачи 4.27 и 4.30: три сверки, которые впервые сошлись, — порча
  # возвращает каждую ровно к тому, что было до правки. Выдача Mount actions
  # снимается у ОДНОГО класса (воин), исключение оружия существ — у одного
  # класса (Мастер оружия), повторяемость — у одного фита из двух.
  defp mutate("class_feats/mount_actions/granted_first", r),
    do: update_in(r.classes[:fighter].granted_feats[1], &List.delete(&1, :mount_actions))

  defp mutate("class_requirements/weapon_master/requirement/weapon_focus_choice", r),
    do:
      put_in(
        r.classes[:weapon_master].requirements[:feat_choice_excludes],
        %{"weapon_focus" => ["unarmed_strike"]}
      )

  defp mutate("repeatable/overwhelming_critical/choice", r),
    do: put_in(r.feats[:overwhelming_critical].repeatable, nil)

  # Задача 4.29: бит второй руки в `EquipableSlots` — сверка впервые сравнивает
  # его с загруженным ruleset'ом. Порча возвращает кнут туда, где он был до
  # правки: без запрета, то есть «во вторую руку можно» при `0x1C010`.
  defp mutate("weapons/whip/off_hand_slot", r),
    do: update_in(r.wield.main_hand_only.slot, &MapSet.delete(&1, :whip))

  # Задача 4.49: два новых сравнения, которые у ванили сходятся целиком.
  # Mount actions — порча возвращает фиту выбор при левелапе, как было до
  # `vanilla/feat_level_up_selectable.json`: таблица его не даёт выбрать никому,
  # а общий слот двенадцати престиж-классов (им фит не выдаётся) снова бы брал.
  # Рапира — фехтовальна у малого владельца, если снять ей «не двуручное»:
  # колонка WeaponFinesseMinimumCreatureSize (3) говорит нет.
  defp mutate("feat_classes/mount_actions/general_slot_for", r),
    do: put_in(r.feats[:mount_actions].level_up_selectable?, true)

  defp mutate("weapons/rapier/finesse_small", r) do
    update_in(r.attack_ability.rules, fn rules ->
      Enum.map(rules, fn
        %{feat: :weapon_finesse} = rule ->
          %{rule | weapon_not_two_handed: %{except: MapSet.new([:rapier])}}

        rule ->
          rule
      end)
    end)
  end

  # Задача 4.50: бонусный слот по значению у ванили сверяется впервые, и область
  # сходится — кроме оружия существ (вид (b)). Порчи держат каждую из трёх
  # дорог, которыми «мы» получается у ядра: список «только эти значения»
  # (`bonus_for_only`, две записи 4.50), пара-исключение (`bonus_for_except`,
  # вор — Use magic device, Fandom) и два ключа требований по значению —
  # правило уровня (Perform только на уровне барда — снимается, и Арфист
  # «берёт» его бонусным слотом) и «нет варианта» (Верховая езда — снимается,
  # и бард «берёт» её).
  defp mutate("class_bonus_values/arcane_archer/epic_weapon_focus", r),
    do: update_in(r.feats[:epic_weapon_focus].bonus_for_only, &Map.delete(&1, :arcane_archer))

  defp mutate("class_bonus_values/assassin/epic_skill_focus", r),
    do: update_in(r.feats[:epic_skill_focus].bonus_for_only, &Map.delete(&1, :assassin))

  defp mutate("class_bonus_values/rogue/epic_skill_focus", r),
    do:
      update_in(
        r.feats[:epic_skill_focus].bonus_for_except,
        &MapSet.delete(&1, {:rogue, :use_magic_device})
      )

  defp mutate("class_bonus_values/harper_scout/epic_skill_focus", r),
    do:
      update_in(
        r.feats[:epic_skill_focus].prereqs["only_on_class_levels_for_skill"],
        &Map.delete(&1, "perform")
      )

  defp mutate("class_bonus_values/bard/epic_skill_focus", r),
    do: put_in(r.feats[:epic_skill_focus].prereqs["no_feat_variant_for_skills"], [])

  # Ступень `level` снимается у записи раздела, чья таблица ключуется уровнем
  # класса `class` (так её находит и сверка — `CompareOther.gains_of/4`).
  defp drop_step(r, section, class, key, level) do
    update_in(r, [section, :applied], fn records ->
      Enum.map(records, fn
        %{amount: %{class: ^class} = amount} = record when is_map_key(amount, key) ->
          %{record | amount: Map.update!(amount, key, &Map.delete(&1, level))}

        record ->
          record
      end)
    end)
  end

  defp keys(source, ruleset) do
    Diff.run(source, ruleset, "priv/rules").areas
    |> Enum.flat_map(& &1.findings)
    |> MapSet.new(&Finding.key/1)
  end
end
