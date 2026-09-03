defmodule BuildCalculator.Rules.BuildTest do
  @moduledoc """
  The build struct's readers — the ones that answer a question about one level.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules.Build

  setup_all do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  describe "granted_feats_at/3" do
    # The accumulating `granted_feats/3` answers "what does the character own by
    # now"; the progression column asks the other question on every row — "what
    # arrives here" — and marks exactly this list with `○` (CLAUDE.md §6).
    test "is this level's hand-out, not everything so far", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:monk, 5))

      assert Build.granted_feats_at(build, ruleset, 1) ==
               ruleset.classes[:monk].granted_feats[1]

      # ⚠️ 28.08.2026: было `[:deflect_arrows, :wholeness_of_body]` — см. соседний
      # тест ниже и кейс AF1. Смысл этого теста («выдача ИМЕННО этого уровня,
      # а не всё накопленное») от правки данных не зависит.
      assert Build.granted_feats_at(build, ruleset, 2) == [:deflect_arrows]
      assert Build.granted_feats_at(build, ruleset, 4) == [:monk_ac_bonus]

      # ... while the accumulation has all of them at once
      owned = Build.granted_feats(build, ruleset, 4)
      assert MapSet.member?(owned, :deflect_arrows)
      assert MapSet.member?(owned, :monk_ac_bonus)
    end

    # The class level is worked out from the build, so a level in the middle of a
    # multiclass build is asked about correctly rather than by character level.
    test "counts the class's own levels, not the character's", %{ruleset: ruleset} do
      build = Build.new(levels: [:fighter, :fighter, :monk, :monk])

      assert Build.granted_feats_at(build, ruleset, 3) ==
               ruleset.classes[:monk].granted_feats[1]

      # ⚠️ 28.08.2026: было `[:deflect_arrows, :wholeness_of_body]`. Второе ушло
      # не из этой функции, а из данных: сдвиг `Wholeness of body` 7 → 2 оказался
      # нашей ошибкой (кейс AF1, замер Dan — фит выдаётся на 7-м классовом уровне).
      # Сам инвариант теста — «спрашиваем уровень КЛАССА, а не персонажа» —
      # держится прежним: воин 2 + монах 2 спрашивают монашеский уровень 2.
      assert Build.granted_feats_at(build, ruleset, 4) == [:deflect_arrows]
    end

    test "a level that grants nothing is an empty list", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:fighter, 3))

      # AGENT_QUEUE.md §1.10 шаг 3: level 1 больше не `[:toughness]` одним —
      # владения (свои Источники 2/3, `wiki.parse.ex`) плюс сиальский Toughness.
      # Здесь важна не эта строка, а level 2 ниже: он и есть заявленный
      # в названии теста «уровень, который не даёт ничего».
      #
      # ⚠️ Из владений оружием тут остался ОДИН, `simple`. Здесь стояло «больше
      # НЕТ… ванильные Weapon Proficiency (*) на Сиале выключены»: верно про
      # `martial`, неверно про `simple` — 26.08.2026 (задача 3.112) три игровых
      # лога `.билд` показали, что шард его не выключил, а выдаёт на классовом
      # уровне 1 всем 23 классам. Обе стороны под тестом
      # в `siala_feat_layer_test.exs`.
      #
      # ⚠️ Порядок здесь не алфавитный и не случайный: ванильная строка класса
      # (броня, щит, martial, simple) идёт первой, сиальский `toughness`
      # дописывается слоем классов, а `martial` вычёркивается последним шагом
      # (`drop_disabled_grants/2`).
      assert Build.granted_feats_at(build, ruleset, 1) == [
               :armor_proficiency_heavy,
               :armor_proficiency_light,
               :armor_proficiency_medium,
               :shield_proficiency,
               :weapon_proficiency_simple,
               :toughness
             ]

      assert Build.granted_feats_at(build, ruleset, 2) == []
    end

    test "past the end of the build, and off it, there is nothing", %{ruleset: ruleset} do
      build = Build.new(levels: [:fighter])

      assert Build.granted_feats_at(build, ruleset, 2) == []
      assert Build.granted_feats_at(Build.new(), ruleset, 1) == []
      assert Build.granted_feats_at(build, ruleset, 0) == []
    end

    # A hypothetical build is a legitimate argument: the class card has to answer
    # "what would *this* class give me here", not "what does the class already
    # sitting on this level give me".
    test "answers for a hypothetical class on the next level", %{ruleset: ruleset} do
      base = Build.new(levels: List.duplicate(:fighter, 4))

      assert base |> Build.add_level(:monk) |> Build.granted_feats_at(ruleset, 5) ==
               ruleset.classes[:monk].granted_feats[1]

      assert base |> Build.add_level(:paladin) |> Build.granted_feats_at(ruleset, 5) != []
    end

    test "an unknown class grants nothing rather than raising", %{ruleset: ruleset} do
      build = Build.new(levels: [:sorcerer_king])

      assert Build.granted_feats_at(build, ruleset, 1) == []
    end
  end

  describe "granted_choices — выбор, сделанный для ВЫДАННОГО фита (задача 3.26)" do
    # Мастер оружия получает `weapon_of_choice` на своём 1-м классовом уровне и
    # всё равно называет оружие. Билд: Воин 13 / ВМ 28, то есть выдача на 14-м.
    defp wm_build do
      Build.new(levels: List.duplicate(:fighter, 13) ++ List.duplicate(:weapon_master, 28))
    end

    # Ruleset без подстановки выдач: в нём Мастер оружия `Weapon of choice`
    # по-прежнему выдаёт, а не предлагает слотом. Нужен ровно там, где
    # проверяется сам механизм выдачи-с-выбором, а не поведение сегодняшних
    # данных.
    defp granting_ruleset(ruleset), do: %{ruleset | grant_substitutions: %{}}

    test "значение лежит на своём уровне и читается по нему", %{ruleset: _ruleset} do
      b = Build.put_granted_choice(wm_build(), 14, :weapon_of_choice, :scimitar)

      assert b.granted_choices == %{14 => %{weapon_of_choice: :scimitar}}
      assert Build.granted_choice(b, 14, :weapon_of_choice) == :scimitar
      refute Build.granted_choice(b, 15, :weapon_of_choice)
      refute Build.granted_choice(wm_build(), 14, :weapon_of_choice)
    end

    # 🔴 Ровно то, ради чего выбор НЕ уехал псевдо-слотом в `feats`: выдача слота
    # не занимает и взятием не считается, а значение при этом у персонажа есть.
    # Обе половины одним тестом — порознь каждая зеленела бы и на слотовой модели.
    # ⚠️ С 14.08.2026 (замеры M2/M2b) `Weapon of choice` классом НЕ выдаётся —
    # он берётся слотом, — и живого носителя у этого механизма в данных
    # не осталось ни одного. Механизм при этом жив и обязан оставаться под
    # тестом: ruleset здесь СИНТЕТИЧЕСКИЙ, без подстановки, то есть ровно тот,
    # в котором выдача была бы. Тот же приём и та же причина, что у формы
    # `{:missing_data, {:choice_domain, …}}` (CLAUDE.md §6).
    test "слот не занят и взятие не посчитано, а значение есть", %{ruleset: ruleset} do
      ruleset = granting_ruleset(ruleset)
      b = Build.put_granted_choice(wm_build(), 14, :weapon_of_choice, :scimitar)

      assert Build.feats_at(b, 14) == []
      assert Build.feat_picks(b, 41) == []
      assert Build.feat_takes(b, :weapon_of_choice, 41) == 0
      assert Build.feat_choices(b, :weapon_of_choice, 41) == []

      assert Build.granted_feat_choices(b, ruleset, :weapon_of_choice, 41) == [:scimitar]
      assert Build.feat_choices_permanent(b, ruleset, :weapon_of_choice, 41) == [:scimitar]
    end

    test "усечение отрезает выбор вместе с уровнем", %{ruleset: ruleset} do
      b = Build.put_granted_choice(wm_build(), 14, :weapon_of_choice, :scimitar)

      assert Build.truncate(b, 14).granted_choices == %{14 => %{weapon_of_choice: :scimitar}}
      assert Build.truncate(b, 13).granted_choices == %{}

      # Дельта считается разностью двух полных `compute` (CLAUDE.md §5), поэтому
      # выбор, сделанный на 14-м, не имеет права влиять на посчитанное для 13-го.
      assert Build.feat_choices_permanent(Build.truncate(b, 13), ruleset, :weapon_of_choice, 13) ==
               []
    end

    # ⚠️ Уровень с записанным значением можно переписать другим классом — строка
    # останется, ровно как остаются пики уровня. Считаться она при этом перестаёт:
    # доказательством выдачи является справочник классов, а не сама строка.
    test "строка живёт дольше выдачи, но без выдачи не считается", %{ruleset: ruleset} do
      ruleset = granting_ruleset(ruleset)
      b = Build.put_granted_choice(wm_build(), 14, :weapon_of_choice, :scimitar)
      moved = Build.replace_level(b, 14, :fighter)

      assert Build.granted_choice(moved, 14, :weapon_of_choice) == :scimitar
      assert Build.granted_feat_choices(moved, ruleset, :weapon_of_choice, 41) == []

      # Положительный контроль: у нетронутого билда та же строка считается.
      assert Build.granted_feat_choices(b, ruleset, :weapon_of_choice, 41) == [:scimitar]
    end

    test "снятое значение стирает уровень целиком, а не оставляет пустую карту" do
      b =
        wm_build()
        |> Build.put_granted_choice(14, :weapon_of_choice, :scimitar)
        |> Build.put_granted_choice(14, :weapon_of_choice, nil)

      # «Выбрал и снял» обязан быть тем же билдом, что «не выбирал», иначе
      # у одного и того же билда два разных кода в ссылке.
      assert b.granted_choices == %{}
      assert b == wm_build()
    end

    test "выборы перечисляются в одном и том же порядке" do
      b =
        wm_build()
        |> Build.put_granted_choice(20, :weapon_of_choice, :longsword)
        |> Build.put_granted_choice(14, :weapon_of_choice, :scimitar)

      assert Build.granted_choice_picks(b, 41) == [
               {14, :weapon_of_choice, :scimitar},
               {20, :weapon_of_choice, :longsword}
             ]

      assert Build.granted_choice_picks(b, 14) == [{14, :weapon_of_choice, :scimitar}]
    end
  end
end
