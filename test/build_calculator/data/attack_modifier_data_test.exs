defmodule BuildCalculator.Data.AttackModifierDataTest do
  @moduledoc """
  Сторож записи `extra_attacks` — той самой, что ломает ванильное «атаки
  фиксируются BAB'ом на 20-м уровне» (задача 3.72).

  Все проверки идут через `Loader.load!/1` на полной копии `priv/rules`,
  у которой испорчено одно поле, — тот же приём, что у сторожа получателей
  (`ClassChangeReceiversTest`) и у `feat_skill_bonuses.json`.

  ⚠️ **Направление ошибки здесь одностороннее, и от него зависит вся строгость
  файла.** Каждое условие в `disabled_if` ОТКЛЮЧАЕТ прибавку. Значит условие,
  которое молча не сработало, — это до трёх лишних атак у персонажа, который
  их не получит: ложная легальность на самом дорогом стате ближника. Поэтому
  «не смогли прочитать» роняет сборку, а не превращается в оговорку; единственный
  законный выход — сказать в данных `"modelled": false` и назвать, кто и почему
  так решил.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data.Loader

  describe "контроль" do
    test "чистая копия грузится — иначе `assert_raise` ниже зеленел бы впустую" do
      root = copy_rules()

      assert %{"siala_41" => siala} = Loader.load!(root)
      assert [%{source: {:class, :arcane_archer}, kind: :extra_attacks}] = siala.attack_modifiers
    end
  end

  describe "условие, которое ядро прочитать не умеет" do
    test "незнакомое `when` роняет сборку" do
      root = copy_rules()

      edit_conditions(root, fn [first | rest] ->
        [Map.put(first, "when", "phase_of_the_moon") | rest]
      end)

      assert_raise RuntimeError, ~r/phase_of_the_moon.*cannot evaluate/s, fn ->
        Loader.load!(root)
      end
    end

    test "прозой, как условия лежали до задачи 3.72, тоже не грузится" do
      root = copy_rules()
      edit_conditions(root, fn _ -> ["wis_modifier > dex_modifier"] end)

      assert_raise RuntimeError, ~r/a record with a `when` is required/s, fn ->
        Loader.load!(root)
      end
    end
  end

  describe "объявление «не моделируем»" do
    # `"modelled": false` — единственный способ обойти проверку выше, поэтому
    # он не голый флажок: без «кто» и «почему» сборка падает. Иначе следующий
    # читатель погасил бы неудобное условие одной строкой и никто бы не узнал.
    test "без `decision` не проходит" do
      root = copy_rules()

      edit_conditions(root, fn conditions -> Enum.map(conditions, &Map.delete(&1, "decision")) end)

      assert_raise RuntimeError, ~r/unmodelled without a `decision`/s, fn ->
        Loader.load!(root)
      end
    end

    test "с `decision`, но без «почему» — тоже не проходит" do
      root = copy_rules()

      edit_conditions(root, fn conditions ->
        Enum.map(conditions, fn
          %{"decision" => decision} = condition ->
            Map.put(condition, "decision", Map.delete(decision, "why"))

          condition ->
            condition
        end)
      end)

      assert_raise RuntimeError, ~r/unmodelled without a `decision`/s, fn ->
        Loader.load!(root)
      end
    end

    # ⚠️ И само объявление живо: сегодня им пользуется ровно одно условие —
    # «персонаж на коне» (решение Dan 21.08.2026, конь = бафф). Оно доезжает
    # до ruleset'а помеченным, а не выброшенным: выброшенное невозможно
    # отличить от забытого.
    test "объявленное условие доезжает до ruleset'а с пометкой" do
      root = copy_rules()
      %{"siala_41" => siala} = Loader.load!(root)
      [modifier] = siala.attack_modifiers

      assert %{kind: :mounted, modelled?: false} in modifier.disabled_if
      assert Enum.count(modifier.disabled_if, & &1.modelled?) == 2
    end
  end

  describe "поля условия" do
    test "имя характеристики с опечаткой роняет сборку" do
      root = copy_rules()
      edit_conditions(root, &put_field(&1, "ability_modifier_exceeds", "ability", "dexterity"))

      assert_raise RuntimeError, ~r/names the ability/s, fn -> Loader.load!(root) end
    end

    # ⚠️ «Голыми или в шмоте» — игровой вопрос, и загрузчик не имеет права
    # выбрать умолчание: запись без этого поля просто не грузится.
    test "read_modifiers обязателен и закрыт словарём" do
      root = copy_rules()
      edit_conditions(root, &put_field(&1, "ability_modifier_exceeds", "read_modifiers", "half"))

      assert_raise RuntimeError, ~r/read_modifiers/s, fn -> Loader.load!(root) end

      root = copy_rules()

      edit_conditions(root, fn conditions ->
        Enum.map(conditions, fn
          %{"when" => "ability_modifier_exceeds"} = c -> Map.delete(c, "read_modifiers")
          c -> c
        end)
      end)

      assert_raise RuntimeError, ~r/read_modifiers/s, fn -> Loader.load!(root) end
    end

    test "класс, которого нет в ruleset'е, роняет сборку" do
      root = copy_rules()
      edit_conditions(root, &put_field(&1, "class_levels_at_least", "class", "shadow_dancer"))

      assert_raise RuntimeError, ~r/shadow_dancer.*never fire/s, fn -> Loader.load!(root) end
    end
  end

  describe "числа самого правила" do
    test "шаг обязан быть положительным целым" do
      for bad <- [0, -1, "10"] do
        root = copy_rules()
        edit_value(root, &Map.put(&1, "per_class_levels", bad))

        assert_raise RuntimeError, ~r/per_class_levels/s, fn -> Loader.load!(root) end
      end
    end

    # ⚠️ И умолчания у них нет. `|| 1` читалось бы как «одна атака за уровень
    # класса» — число, которого не называет ни один источник; такое умолчание
    # и есть выдуманное игровое число, просто написанное оператором.
    test "оба числа обязательны, умолчания нет" do
      for key <- ["per_class_levels", "attacks_per_step"] do
        root = copy_rules()
        edit_value(root, &Map.delete(&1, key))

        assert_raise RuntimeError, ~r/#{key}/s, fn -> Loader.load!(root) end
      end
    end

    test "потолок обязан быть положительным целым, если он есть" do
      root = copy_rules()
      edit_value(root, &Map.put(&1, "max", "три"))

      assert_raise RuntimeError, ~r/extra_attacks states max/s, fn -> Loader.load!(root) end
    end

    # Потолка может не быть вовсе — источник другого класса его просто
    # не назовёт, и это не ошибка данных.
    test "без потолка грузится" do
      root = copy_rules()
      edit_value(root, &Map.delete(&1, "max"))

      assert %{"siala_41" => siala} = Loader.load!(root)
      assert [%{max: nil}] = siala.attack_modifiers
    end
  end

  describe "`unclear` отказывается ОДИН раз, а не по-разному в двух местах" do
    # До задачи 3.72 «факт применён» и «модификатор построен» были двумя
    # решениями: `apply_change/2` отказывал факту со `status: unclear`,
    # а модификатор строился всё равно. Теперь оба спрашивают одну функцию,
    # и оба ответа проверяются здесь вместе — врозь каждый выглядит верным
    # и при разъехавшейся модели.
    test "модификатора нет, и факт назван гэпом" do
      root = copy_rules()
      edit_change(root, &Map.put(&1, "status", "unclear"))

      assert %{"siala_41" => siala} = Loader.load!(root)
      assert siala.attack_modifiers == []
      assert {:not_modelled, {:class_change, :arcane_archer, "extra_attacks"}} in siala.gaps
    end
  end

  # ------------------------------------------------------------- помощники --

  defp copy_rules do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp put_field(conditions, when_name, key, value) do
    Enum.map(conditions, fn
      %{"when" => ^when_name} = condition -> Map.put(condition, key, value)
      condition -> condition
    end)
  end

  defp edit_conditions(root, fun),
    do: edit_value(root, &Map.update!(&1, "disabled_if", fun))

  defp edit_value(root, fun), do: edit_change(root, &Map.update!(&1, "value", fun))

  defp edit_change(root, fun) do
    path = Path.join(root, "siala_41/classes.json")
    data = path |> File.read!() |> Jason.decode!()

    classes =
      Enum.map(data["classes"], fn class ->
        if class["id"] == "arcane_archer" do
          changes =
            Enum.map(class["changes"], fn change ->
              if change["what"] == "extra_attacks", do: fun.(change), else: change
            end)

          Map.put(class, "changes", changes)
        else
          class
        end
      end)

    File.write!(path, Jason.encode!(Map.put(data, "classes", classes)))
  end
end
