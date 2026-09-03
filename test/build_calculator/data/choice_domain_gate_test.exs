defmodule BuildCalculator.Data.ChoiceDomainGateTest do
  @moduledoc """
  Ворота словаря выбора — на собранном ruleset'е, а не на сыром JSON.

  Ворот два рода, и разница между ними — это разница между утверждением
  о **значении** и утверждением об **одном фите**:

    * `selectable` — домен-широкие. «universal — не школа магии» верно для
      всех, кто выбирает школу, поэтому одна пометка закрывает всё семейство;
    * `favored_enemy` — именные, по id фита. «ooze нельзя выбрать любимым
      врагом» — факт про список одного фита, и он перекрывает домен-широкие.

  Файл существует потому, что до 02.08.2026 у школ были только именные ворота.
  `spell_focus` отсекал `universal`, а `greater_spell_focus`, `epic_spell_focus`
  и `arcane_defense` получали все девять школ — и не выдавали `universal` лишь
  потому, что `same_choice_as` оставляет им только школы, уже взятые базовым
  фитом. Дыру закрывал **побочный эффект чужого правила**, неотличимый от
  работающего решения ровно до дня, когда правило исчезло бы.

  Поэтому здесь мало проверить, что `universal` не предлагается: это зеленело
  и ДО правки. Проверяется, что он не предлагается **по заслуге ворот** — на
  ruleset'е, у которого `same_choice_as` снят.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Rules.Build
  alias BuildCalculator.Rules.FeatChoices

  @gate FeatChoices.domain_gate()

  setup_all do
    {:ok, vanilla} = BuildCalculator.Data.ruleset("vanilla")
    {:ok, siala} = BuildCalculator.Data.ruleset("siala_41")

    %{vanilla: vanilla, siala: siala}
  end

  # Все фиты ruleset'а, выбирающие из названного домена.
  defp feats_choosing(ruleset, domain) do
    for {id, feat} <- ruleset.feats,
        is_map(feat.repeatable),
        feat.repeatable.choice == domain,
        do: id
  end

  # Тот же ruleset, но у КАЖДОГО фита выброшен `same_choice_as`. Единственное,
  # что после этого держит `universal` снаружи, — ворота домена.
  defp without_same_choice(ruleset) do
    feats =
      Map.new(ruleset.feats, fn {id, feat} ->
        prereqs =
          case feat.prereqs do
            %{} = p -> p |> Map.delete("same_choice_as") |> Map.delete(:same_choice_as)
            other -> other
          end

        {id, %{feat | prereqs: prereqs}}
      end)

    %{ruleset | feats: feats}
  end

  defp candidates(ruleset, feat_id) do
    FeatChoices.candidates(%Build{}, %{feat: feat_id, at: 41}, ruleset)
  end

  describe "домен-широкие ворота" do
    test "школу выбирают четыре фита, не один", %{siala: siala} do
      # Положительный контроль ко всем `refute` ниже: если это упадёт, значит
      # проверяемые фиты вообще не попали в поле зрения.
      assert Enum.sort(feats_choosing(siala, :spell_school)) ==
               [:arcane_defense, :epic_spell_focus, :greater_spell_focus, :spell_focus]
    end

    test "словарь школ несёт домен-широкие ворота, а именных не несёт", %{siala: siala} do
      flags = siala.choice_domains[:spell_school].flags

      assert Map.has_key?(flags, @gate)
      assert MapSet.size(Map.fetch!(flags, @gate)) == 8

      for feat_id <- feats_choosing(siala, :spell_school) do
        refute Map.has_key?(flags, feat_id),
               "#{feat_id}: именные ворота перекрыли бы общие и разошлись бы с ними"
      end
    end

    # ⚠️ ГЛАВНЫЙ ТЕСТ ФАЙЛА. `same_choice_as` снят у всех — если бы дыру
    # закрывал он, здесь бы `universal` и вылез.
    test "ни один фит не получает universal, даже когда same_choice_as снят", %{siala: siala} do
      stripped = without_same_choice(siala)

      for feat_id <- feats_choosing(stripped, :spell_school) do
        assert {:ok, values} = candidates(stripped, feat_id)

        # Положительный контроль рядом с refute: список не пуст, значит
        # проверка вообще что-то видела.
        assert length(values) == 8, "#{feat_id}: #{inspect(values)}"
        refute :universal in values, "#{feat_id} получил universal"
      end
    end

    # Тот же прогон на ванильном ruleset'е: слой Сиалы добавляет
    # `arcane_defense` и `epic_spell_focus`, и ворота обязаны работать до него.
    test "то же на ванили", %{vanilla: vanilla} do
      stripped = without_same_choice(vanilla)
      ids = feats_choosing(stripped, :spell_school)

      assert :greater_spell_focus in ids
      refute ids == []

      for feat_id <- ids do
        assert {:ok, values} = candidates(stripped, feat_id)
        assert length(values) == 8, "#{feat_id}: #{inspect(values)}"
        refute :universal in values, "#{feat_id} получил universal"
      end
    end

    # ⚠️ Положительный контроль ко всему файлу: доказывает, что зелень выше —
    # заслуга ворот, а не совпадение. Ворота переименовываются обратно в id
    # базового фита — ровно та форма, что была в данных до 02.08.2026, — и
    # `universal` немедленно возвращается к трём производным фитам.
    #
    # Без этого теста «universal не предлагается» зеленело бы и на старых
    # данных, где его отсекал побочный эффект `same_choice_as`.
    test "верни именные ворота — и universal возвращается", %{siala: siala} do
      domain = siala.choice_domains[:spell_school]
      eight = Map.fetch!(domain.flags, @gate)

      old_shape = %{
        siala
        | choice_domains:
            Map.put(siala.choice_domains, :spell_school, %{
              domain
              | flags: %{spell_focus: eight}
            })
      }

      stripped = without_same_choice(old_shape)

      assert {:ok, [_ | _] = base} = candidates(stripped, :spell_focus)
      refute :universal in base, "именные ворота обязаны продолжать работать для своего фита"

      for feat_id <- [:arcane_defense, :epic_spell_focus, :greater_spell_focus] do
        assert {:ok, values} = candidates(stripped, feat_id)

        assert :universal in values,
               "#{feat_id}: старая форма ворот обязана была протекать, иначе тест выше ничего не доказывает"
      end
    end

    # Сравнение по вхождению, а не по равенству: у пустого билда не выполнены
    # и другие требования (`greater_spell_focus` требует базовый фит), поэтому
    # список отказов длиннее одного. Проверяется именно отказ по значению.
    test "выбор universal отбивается у каждого фита семейства", %{siala: siala} do
      for feat_id <- feats_choosing(siala, :spell_school) do
        assert {:error, reasons} =
                 BuildCalculator.Rules.validate_feat_pick(
                   %Build{},
                   %{feat: feat_id, choice: :universal, at: 41},
                   siala
                 )

        assert {:invalid_choice, feat_id, :universal} in reasons,
               "#{feat_id}: #{inspect(reasons)}"

        # Положительный контроль: та же школа, но настоящая, по значению
        # не отбивается — значит отказ выше про `universal`, а не про то,
        # что фит недоступен вообще.
        assert {:error, ok_reasons} =
                 BuildCalculator.Rules.validate_feat_pick(
                   %Build{},
                   %{feat: feat_id, choice: :evocation, at: 41},
                   siala
                 )

        refute {:invalid_choice, feat_id, :evocation} in ok_reasons,
               "#{feat_id}: #{inspect(ok_reasons)}"
      end
    end
  end

  describe "именные ворота остаются исключением поверх" do
    test "любимый враг не получает ooze, и получает остальные 24", %{siala: siala} do
      assert {:ok, values} = candidates(siala, :favored_enemy)

      assert length(values) == 24
      refute :ooze in values

      # Положительный контроль: ooze вообще есть в словаре, то есть refute
      # выше проверяет отсечение, а не отсутствие значения.
      assert MapSet.member?(siala.choice_domains[:creature_type].values, :ooze)
    end

    test "тип существа выбирает ровно один фит — потому именные ворота и хватает",
         %{siala: siala} do
      assert feats_choosing(siala, :creature_type) == [:favored_enemy]
    end
  end

  describe "словарь без ворот отдаётся целиком" do
    test "типы урона: пять значений, ни одно не отсечено", %{siala: siala} do
      assert siala.choice_domains[:energy_type].flags == %{}

      for feat_id <- feats_choosing(siala, :energy_type) do
        assert {:ok, values} = candidates(siala, feat_id)
        assert Enum.sort(values) == [:acid, :cold, :electrical, :fire, :sonic]
      end
    end
  end
end
