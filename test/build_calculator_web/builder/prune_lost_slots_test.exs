defmodule BuildCalculatorWeb.Builder.PruneLostSlotsTest do
  @moduledoc """
  Задача 4.62: пик в слоте, которого его уровень не даёт, снимается; пик
  в слоте, который уровень даёт (тот же id на том же уровне), остаётся, что бы
  ни случилось вокруг.

  С задачи 4.63 чистка одна на фиты и известные заклинания — `LostPicks.prune/2`
  (прежде `Feats.prune_lost_slots/2`, только фиты), а какие пики потеряли слот,
  отвечает ядро (`Rules.lost_slot_picks/2`). Здесь — её половина про фиты,
  утверждения 4.62 без изменений; у этих билдов заклинаний нет, и половина про
  заклинания обязана остаться пустой (`prune/2` ниже). Заклинания —
  `lost_spell_picks_test.exs`.

  Слоты уровня — ответ ядра (`FeatSlots.at/3`), и снятое обязано совпасть
  с тем, что ядро называет `{:slot_not_granted, slot_id}`
  (`Rules.illegal_feats/2`): чистка — не второе определение, а то же самое
  правило, применённое к билду. Каждый билд до правки проверен как законный —
  тем вопросом, что задаёт конструктор (`validate_level_up/3`,
  `validate_feat_pick/3`), — иначе «снято» могло бы значить «было нелегально
  с самого начала».

  Оба ruleset'а: правило слотов (общий, расовый, бонусный) у них общее.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatSlots}
  alias BuildCalculatorWeb.Builder.LostPicks

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @fighter_abilities %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8}
  @wizard_abilities %{str: 8, dex: 14, con: 14, int: 18, wis: 10, cha: 8}

  defp start(ruleset, race, abilities),
    do:
      Build.new(
        ruleset_version: ruleset.version,
        race: race,
        alignment: :true_neutral,
        base_abilities: abilities
      )

  # Один левелап так, как его делает конструктор: класс — `validate_level_up/3`,
  # каждый пик — `validate_feat_pick/3` со слотом.
  defp level_up(build, class, ruleset, picks) do
    level = Build.character_level(build) + 1
    assert Rules.validate_level_up(build, class, ruleset) == :ok
    build = Build.add_level(build, class)

    Enum.reduce(picks, build, fn {slot, feat}, acc ->
      assert Rules.validate_feat_pick(acc, %{feat: feat, at: level, slot: slot}, ruleset) == :ok,
             "#{feat} в #{inspect(slot)} на #{level}-м"

      Build.put_feat(acc, level, slot, feat)
    end)
  end

  # Человек-воин 4: бонусные фиты Воина на 1, 2 и 4-м его уровнях
  # (`fandom:Fighter`), общий на 1 и 3-м, расовый на 1-м.
  defp fighter_ladder(ruleset) do
    b = start(ruleset, :human, @fighter_abilities)

    b =
      level_up(b, :fighter, ruleset, [
        {:general, :alertness},
        {:racial, :iron_will},
        {{:class_bonus, :fighter}, :blind_fight}
      ])

    b = level_up(b, :fighter, ruleset, [{{:class_bonus, :fighter}, :dodge}])
    b = level_up(b, :fighter, ruleset, [{:general, :lightning_reflexes}])
    b = level_up(b, :fighter, ruleset, [{{:class_bonus, :fighter}, :mobility}])

    assert Rules.illegal_feats(b, ruleset) == []
    b
  end

  # То, что ядро называет «слота нет», — эталон чистки.
  defp not_granted(build, ruleset) do
    for {level, slot, _feat, {:slot_not_granted, _}} <- Rules.illegal_feats(build, ruleset),
        do: {level, slot}
  end

  defp ids(lost), do: for({level, slot, _pick} <- lost, do: {level, slot})

  # Половина чистки про фиты — в прежней форме `{build, lost}`, чтобы утверждения
  # 4.62 остались дословными.
  defp prune(ruleset, build) do
    {pruned, %{feats: feats, spells: []}} = LostPicks.prune(ruleset, build)
    {pruned, feats}
  end

  for version <- ["siala_41", "vanilla"] do
    @version version

    describe "#{version}" do
      setup context do
        %{ruleset: if(@version == "vanilla", do: context.vanilla, else: context.siala)}
      end

      test "нечего снимать — билд возвращается тем же, без пересборки", %{ruleset: ruleset} do
        build = fighter_ladder(ruleset)
        assert prune(ruleset, build) == {build, []}

        empty = start(ruleset, :elf, @wizard_abilities)
        assert prune(ruleset, empty) == {empty, []}
      end

      test "человек → эльф: расовый пик снят, общий остался", %{ruleset: ruleset} do
        human =
          ruleset
          |> start(:human, @wizard_abilities)
          |> level_up(:wizard, ruleset, [{:general, :alertness}, {:racial, :dodge}])

        assert Rules.illegal_feats(human, ruleset) == []

        elf = %Build{human | race: :elf}
        assert not_granted(elf, ruleset) == [{1, :racial}]

        {pruned, lost} = prune(ruleset, elf)

        assert lost == [{1, :racial, :dodge}]
        assert pruned.feats == %{1 => %{general: :alertness}}
        assert not_granted(pruned, ruleset) == []
        assert Rules.illegal_feats(pruned, ruleset) == []
        refute :dodge in Build.feats_taken(pruned, 1)
      end

      test "воин 4, 1-й уровень → волшебник: 1-й и 4-й сняты, 2-й и общие остались",
           %{ruleset: ruleset} do
        fighter = fighter_ladder(ruleset)
        edited = Build.replace_level(fighter, 1, :wizard)

        # 2-й уровень персонажа стал 1-м уровнем Воина — бонусный слот с тем же
        # id на том же уровне; 3-й стал 2-м — НОВЫЙ бонусный слот (пустой);
        # 4-й стал 3-м — бонусного слота нет.
        assert Enum.map(FeatSlots.at(edited, ruleset, 2), & &1.id) == [{:class_bonus, :fighter}]
        assert {:class_bonus, :fighter} in Enum.map(FeatSlots.at(edited, ruleset, 3), & &1.id)
        assert FeatSlots.at(edited, ruleset, 4) == []

        {pruned, lost} = prune(ruleset, edited)

        assert lost == [
                 {1, {:class_bonus, :fighter}, :blind_fight},
                 {4, {:class_bonus, :fighter}, :mobility}
               ]

        assert ids(lost) == Enum.sort(not_granted(edited, ruleset))

        assert pruned.feats == %{
                 1 => %{general: :alertness, racial: :iron_will},
                 2 => %{{:class_bonus, :fighter} => :dodge},
                 3 => %{general: :lightning_reflexes}
               }

        assert not_granted(pruned, ruleset) == []
      end

      test "пик с выбором снимается вместе с выбором", %{ruleset: ruleset} do
        fighter = fighter_ladder(ruleset)

        # Weapon focus (Club) в бонусном слоте 4-го (дубина владения не требует
        # и на Сиале, `CLAUDE.md` §6) — тем же путём, что пик.
        fighter =
          Build.put_feat(fighter, 4, {:class_bonus, :fighter}, :weapon_focus, :club)

        assert Rules.illegal_feats(fighter, ruleset) == []

        {_pruned, lost} =
          prune(ruleset, Build.replace_level(fighter, 1, :wizard))

        assert {4, {:class_bonus, :fighter}, {:weapon_focus, :club}} in lost
      end

      # Уровень ЗА длиной билда: конструктор позволяет выбрать фит раньше класса
      # уровня. Общий слот уровня от класса не зависит — пик законен и остаётся;
      # расовый 1-го уровня пустого билда пропадает со сменой расы так же, как
      # у взятого, — ядро назвало бы его, как только класс встанет.
      test "уровни за длиной билда спрашиваются так же", %{ruleset: ruleset} do
        two = fighter_ladder(ruleset) |> Build.truncate(2)
        ahead = Build.put_feat(two, 3, :general, :lightning_reflexes)
        assert prune(ruleset, ahead) == {ahead, []}

        empty_human =
          Build.put_feat(start(ruleset, :human, @wizard_abilities), 1, :racial, :dodge)

        assert prune(ruleset, empty_human) == {empty_human, []}

        {pruned, lost} = prune(ruleset, %Build{empty_human | race: :elf})
        assert lost == [{1, :racial, :dodge}]
        assert pruned.feats == %{}
      end

      # Уровень 0 бывает только в ссылке, собранной руками; слотов у него нет —
      # тот же ответ, что у ядра (`granted_slot/4`: уровень < 1 → слота нет).
      test "уровень 0 слотов не даёт", %{ruleset: ruleset} do
        build = %Build{fighter_ladder(ruleset) | feats: %{0 => %{general: :toughness}}}
        assert not_granted(build, ruleset) == [{0, :general}]

        assert prune(ruleset, build) ==
                 {%Build{build | feats: %{}}, [{0, :general, :toughness}]}
      end
    end
  end

  # Положительный контроль сравнения с ядром: чистка, которая ничего не снимает,
  # обязана разойтись с ядром на билде с пропавшим слотом — иначе равенство
  # `ids(lost) == not_granted(...)` выше проверяло бы пустое против пустого.
  test "контроль: на билде с пропавшим слотом ядро называет непустой список", %{siala: siala} do
    edited = siala |> fighter_ladder() |> Build.replace_level(1, :wizard)
    assert not_granted(edited, siala) != []
    refute match?({_, []}, prune(siala, edited))
  end
end
