defmodule BuildCalculator.Data.ResistanceLayerTest do
  @moduledoc """
  Сторожа слоя данных «Резистов», заведённые задачей 3.210 поверх разметки 3.209.

  Три новых утверждения приезжают в ruleset, и каждое может быть испорчено
  правкой JSON молча — то есть ровно тот случай, ради которого загрузчик роняет
  сборку, а этот файл проверяет, что он её роняет:

    * **правило сведения нефитовых источников** (`resistance_stacking`) —
      «эффект расы и топоров против вещи» и «вещь против вещи», у каждого свой
      статус, потому что провенанс у половин РАЗНЫЙ (первое — слово Dan плюс
      замер `AV1`, второе — только Fandom);
    * **виды урона, которых секция не показывает** (`resistance_excluded_types`)
      с именами, которыми их печатает игровой лог, и словом «почему»;
    * **каким фитам достаётся режим «каждая запись — взятие»**
      (`gear.feats.takes.applies_to`).

  ⚠️ Проверяется через `Loader.load!/1` на КОПИИ `priv/rules` — тем же приёмом,
  что у `worn_test.exs`: испорченный снапшот обязан уронить сборку, а не
  посчитать по-своему, и увидеть это можно только настоящей загрузкой.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader

  @resistance_file "vanilla/feat_resistance_bonuses.json"

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp copy_rules do
    root = BuildCalculator.TmpDir.unique_path!()
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp edit_json(root, relative, fun) do
    path = Path.join(root, relative)
    data = path |> File.read!() |> Jason.decode!()
    File.write!(path, Jason.encode!(fun.(data)))
    root
  end

  # Факт `resistance_stacking` лежит в массиве `facts` системы оружия, и найти
  # его надо по `what`, а не по индексу: он добавлен ПОСЛЕДНИМ именно затем,
  # чтобы индексы соседей не поехали (урок 3.209).
  defp edit_stacking(root, fun) do
    edit_json(root, "siala_41/systems.json", fn data ->
      systems =
        for system <- data["systems"] do
          if system["id"] == "weapon_system" do
            facts =
              for fact <- system["facts"],
                  do: if(fact["what"] == "resistance_stacking", do: fun.(fact), else: fact)

            Map.put(system, "facts", facts)
          else
            system
          end
        end

      Map.put(data, "systems", systems)
    end)
  end

  # ⚠️ Само правило лежит в `fact["value"]`, а его статусы — РЯДОМ с `value`,
  # на самом факте (`Systems.system_fact/2` против `system_fact_field/3`).
  # Два помощника, а не один с флагом: перепутать эти два места — ровно тот
  # способ написать зелёный тест, который ничего не проверяет.
  defp edit_stacking_value(root, fun),
    do: edit_stacking(root, &update_in(&1, ["value"], fun))

  defp edit_excluded(root, fun) do
    edit_json(root, @resistance_file, fn data ->
      update_in(data, ["totals_energy_types", "excluded"], &Enum.map(&1, fun))
    end)
  end

  # ⚠️ `load!/1` пишет в лог (он же читает 30+ файлов), и `capture_log/1` здесь
  # только ради тишины в выводе теста — сам ассерт про исключение.
  defp load_raising(root, pattern) do
    capture_log(fn -> assert_raise RuntimeError, pattern, fn -> Loader.load!(root) end end)
  end

  describe "правило сведения нефитовых источников" do
    test "у Сиалы оба правила — максимум, и статусы разведены", %{ruleset: rs} do
      assert rs.resistance_stacking == %{
               effect_vs_gear: :max,
               gear_vs_gear: :max,
               # слово Dan 13.09.2026 плюс замер `AV1` 18.09.2026
               effect_vs_gear_assumed?: false,
               # только Fandom, Сиала молчит
               gear_vs_gear_assumed?: true
             }
    end

    # 🔴 У ванили правила нет ВОВСЕ, и это не пропуск: расового бонуса шарда
    # и бонуса за тип оружия в NWN нет, значит сводить эффект с вещью там
    # нечего. Ядро в таком снапшоте берёт максимум (нижнюю границу обоих
    # чтений) и молчит, пока сравнивать не с чем.
    test "у ванили правила нет вовсе", %{vanilla: v} do
      assert v.resistance_stacking == nil
    end

    test "незнакомое слово в правиле роняет сборку" do
      root = edit_stacking_value(copy_rules(), &Map.put(&1, "effect_vs_gear", "average"))

      load_raising(root, ~r/resistance_stacking\.effect_vs_gear is "average"/)
    end

    test "незнакомое слово во ВТОРОЙ половине роняет сборку тоже" do
      root = edit_stacking_value(copy_rules(), &Map.put(&1, "gear_vs_gear", "first"))

      load_raising(root, ~r/resistance_stacking\.gear_vs_gear is "first"/)
    end

    # ⚠️ Снятая отметка `verified` не роняет сборку, а **включает оговорку** —
    # и это разные вещи: незнакомое слово значит «считаем непонятно как»,
    # а непроверенный статус значит «считаем известным способом, но провенанс
    # слабее». Второе — повод сказать, а не упасть.
    test "статус не verified включает оговорку, а не падение" do
      root = edit_stacking(copy_rules(), &Map.put(&1, "status_effect_vs_gear", "assumed"))

      rulesets = capture_log(fn -> send(self(), {:loaded, Loader.load!(root)}) end)
      assert is_binary(rulesets)
      assert_received {:loaded, %{"siala_41" => reloaded}}

      assert reloaded.resistance_stacking.effect_vs_gear_assumed?
      assert reloaded.resistance_stacking.effect_vs_gear == :max
    end
  end

  describe "виды урона, которых секция не показывает" do
    test "три записи, и у каждой своё слово «почему»", %{ruleset: rs} do
      assert rs.resistance_excluded_types == [
               # урон не поглощается вовсе, значит строки на предмете не бывает
               %{id: :magical, verdict: :not_absorbed, log_names: []},
               %{id: :divine, verdict: :not_absorbed, log_names: ["divine"]},
               # получатель НАШ, а решение владельца — не считать
               %{
                 id: :physical,
                 verdict: :decided,
                 log_names: ["bludgeoning", "piercing", "slashing"]
               }
             ]
    end

    # Один и тот же список у обоих ruleset'ов: вопрос про то, ЧТО ПОКАЗЫВАЕТ
    # секция, а не про баланс шарда.
    test "у ванили тот же список", %{ruleset: rs, vanilla: v} do
      assert v.resistance_excluded_types == rs.resistance_excluded_types
    end

    # 🔴 Исключённые и считаемые обязаны быть НЕПЕРЕСЕКАЮЩИМИСЯ: одно и то же
    # имя в двух списках означало бы, что свод импорта отвечает про строку
    # двумя разными фразами в зависимости от порядка веток.
    test "имена исключённых не пересекаются с семью считаемыми", %{ruleset: rs} do
      counted = for %{en: en} <- rs.resistance_energy_types, do: String.downcase(en)
      excluded = for %{log_names: names} <- rs.resistance_excluded_types, name <- names, do: name

      assert excluded -- counted == excluded
    end

    test "незнакомое слово вердикта роняет сборку" do
      root = edit_excluded(copy_rules(), &Map.put(&1, "verdict", "maybe"))

      load_raising(root, ~r/states verdict "maybe"/)
    end

    test "отсутствующий вердикт роняет сборку" do
      root = edit_excluded(copy_rules(), &Map.delete(&1, "verdict"))

      load_raising(root, ~r/states verdict nil/)
    end

    test "log_names не списком строк роняет сборку" do
      root = edit_excluded(copy_rules(), &Map.put(&1, "log_names", "Bludgeoning"))

      load_raising(root, ~r/states log_names/)
    end
  end

  describe "замещение: статус по ruleset'ам" do
    # У ванили правило процитировано дословно ОБЕИМИ страницами, у Сиалы —
    # перенесено (её пять страниц про `Resist energy` молчат). Разрешает это
    # загрузчик, читая, какому ruleset'у принадлежит двойник, — и потому
    # в ядре нет ни одного имени ruleset'а.
    test "у Сиалы assumed, у ванили нет", %{ruleset: rs, vanilla: v} do
      assert record(rs, :resist_energy).superseded_by.assumed?
      refute record(v, :resist_energy).superseded_by.assumed?
    end

    test "двойник без названного ruleset'а роняет сборку" do
      root =
        edit_json(copy_rules(), @resistance_file, fn data ->
          update_in(data, ["bonuses"], fn bonuses ->
            for bonus <- bonuses do
              if bonus["feat"] == "resist_energy",
                do:
                  update_in(
                    bonus,
                    ["superseded_by"],
                    &Map.delete(&1, "status_siala_applies_to_ruleset")
                  ),
                else: bonus
            end
          end)
        end)

      load_raising(root, ~r/no ruleset will ever read/)
    end
  end

  describe "каким фитам достаётся «каждая запись — взятие»" do
    test "снапшот называет широкое чтение", %{ruleset: rs, vanilla: v} do
      assert rs.gear.feat_takes_applies_to == :same_value

      # ⚠️ Секция `gear` общая обоим ruleset'ам — это вопрос про движок,
      # а не про баланс шарда.
      assert v.gear.feat_takes_applies_to == :same_value
    end

    test "незнакомое слово роняет сборку" do
      root =
        edit_json(copy_rules(), "siala_41/overrides.json", fn data ->
          put_in(data, ["gear", "feats", "takes", "applies_to", "value"], "every_feat")
        end)

      load_raising(root, ~r/gear\.feats\.takes\.applies_to is "every_feat"/)
    end

    # 🔴 Ключа нет вовсе — действует УЗКОЕ, прежнее чтение, а не широкое:
    # снапшот, который про расширение молчит, обязан считать так, как считал
    # до 18.09.2026. Направление умолчания — занижение, а не выдумывание.
    test "ключа нет — узкое чтение, и повтор пары перестаёт считаться" do
      root =
        edit_json(copy_rules(), "siala_41/overrides.json", fn data ->
          update_in(data, ["gear", "feats", "takes"], &Map.delete(&1, "applies_to"))
        end)

      rulesets = capture_log(fn -> send(self(), {:loaded, Loader.load!(root)}) end)
      assert is_binary(rulesets)
      assert_received {:loaded, %{"siala_41" => narrow}}

      assert narrow.gear.feat_takes_applies_to == nil

      gear =
        BuildCalculator.Rules.Gear.new(
          feats: [{:epic_energy_resistance, :fire}, {:epic_energy_resistance, :fire}]
        )

      # ...и два объявления пары считаются ОДНИМ взятием, как до задачи
      assert BuildCalculator.Rules.GearFeats.takes(
               gear,
               narrow,
               :epic_energy_resistance,
               :fire
             ) == 1

      # на поставляемых данных — двумя
      assert BuildCalculator.Rules.GearFeats.takes(
               gear,
               Data.ruleset!("siala_41"),
               :epic_energy_resistance,
               :fire
             ) == 2
    end
  end

  defp record(ruleset, id), do: Enum.find(ruleset.resistance_bonuses.applied, &(&1.id == id))
end
