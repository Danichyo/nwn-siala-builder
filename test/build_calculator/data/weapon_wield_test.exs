defmodule BuildCalculator.Data.WeaponWieldTest do
  @moduledoc """
  Хват оружия ванили из таблицы игры — `vanilla/weapon_wield.json` (задача 4.28).

  Файл переписывает колонку `WeaponWield` из `baseitems.2da` для 41 оружия
  справочника и правило, какой код называет хват сам (лук, арбалет —
  двумя руками при любом размере; двустороннее — обе руки), а какой оставляет
  его правилу размеров. Колонка «Одно или двуручное» Сиалы с той же задачи —
  в слое шарда (`siala_41/generated/weapons.json`) и ложится поверх по id.

  Здесь — то, что сторожит загрузчик: полнота покрытия, закрытые словари кодов
  и слов хвата, слоение. Ответы ядра по всем видам — `wield_matrix_test.exs`;
  строки таблицы — `provenance_test.exs` («цитаты-строки базовых таблиц»).
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader

  @file_path "priv/rules/vanilla/weapon_wield.json"
  @raw @file_path |> File.read!() |> Jason.decode!()

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  # Копия `priv/rules` с правкой одного JSON — только через `TmpDir` (CLAUDE.md §7).
  defp copy_with(relative, fun) do
    root = BuildCalculator.TmpDir.unique_path!("weapon_wield_")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)

    path = Path.join(root, relative)
    File.write!(path, path |> File.read!() |> Jason.decode!() |> fun.() |> Jason.encode!())
    root
  end

  defp load(root) do
    log = capture_log(fn -> send(self(), {:loaded, Loader.load!(root)}) end)
    assert is_binary(log)
    assert_received {:loaded, loaded}
    loaded
  end

  defp set_code(json, id, code) do
    update_in(json["weapons"], fn list ->
      for w <- list, do: if(w["id"] == id, do: Map.put(w, "weapon_wield", code), else: w)
    end)
  end

  describe "файл подключён" do
    test "зарегистрирован по имени, как и слой Сиалы" do
      assert "vanilla/weapon_wield.json" in Loader.source_files()
      assert "siala_41/generated/weapons.json" in Loader.source_files()
    end

    # Список `weapons` на верхнем уровне сделал бы файл доменом выбора, если
    # бы загрузчик не знал его по имени (`Reading`, `@rules_files`).
    test "не стал доменом выбора", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        refute Map.has_key?(ruleset.choice_domains, :weapon_wield)
      end
    end

    test "покрывает справочник целиком: 41 строка таблицы и 6 без строки", %{vanilla: vanilla} do
      rows = for w <- @raw["weapons"], do: String.to_existing_atom(w["id"])
      absent = for id <- @raw["not_in_baseitems"]["ids"], do: String.to_existing_atom(id)

      assert length(rows) == 41
      assert Enum.sort(absent) == ~w(bite_item claw_item creature_weapon gore_item slam_item
                                     unarmed_strike)a

      assert Enum.sort(rows ++ absent) == vanilla.weapons |> Map.keys() |> Enum.sort()
    end

    # Каждый встретившийся код правило называет ровно одним из двух способов.
    test "коды правила: три называют хват, четыре оставляют размеру" do
      stated = for e <- @raw["rule"]["stated_grip"], do: {e["weapon_wield"], e["grip"]}
      by_size = for e <- @raw["rule"]["size_decides"], do: e["weapon_wield"]

      assert stated == [{5, "two_handed"}, {6, "two_handed"}, {8, "double_sided"}]
      assert by_size == [nil, 4, 10, 11]

      used = @raw["weapons"] |> Enum.map(& &1["weapon_wield"]) |> Enum.uniq() |> Enum.sort()
      assert used -- (Enum.map(stated, &elem(&1, 0)) ++ by_size) == []
    end

    # ⚠️ Древковое (4) — наше чтение, и файл обязан говорить это сам: статус,
    # оба чтения и замер, который их различит.
    test "древковое — assumed, с обоими чтениями и замером" do
      polearm = Enum.find(@raw["rule"]["size_decides"], &(&1["weapon_wield"] == 4))

      assert polearm["status"] == "assumed"
      assert Map.keys(polearm["readings"]) |> Enum.sort() == ["always_two_handed", "size_rule"]
      assert polearm["measurement"] =~ "малый щит"
    end
  end

  # Два независимых чтения одного факта — код таблицы игры и флаги Fandom
  # в справочнике — обязаны сходиться: двустороннее — это код 8, дальнобойное —
  # коды лука, арбалета, пращи и метательного.
  test "коды сходятся с флагами Fandom: double_sided — 8, ranged — 5, 6, 10, 11", %{
    vanilla: vanilla
  } do
    for %{"id" => id, "weapon_wield" => code} <- @raw["weapons"] do
      weapon = vanilla.weapons[String.to_existing_atom(id)]

      assert weapon.double_sided? == (code == 8), id
      assert weapon.ranged? == code in [5, 6, 10, 11], id
    end
  end

  describe "загрузчик роняет сборку, а не молчит" do
    test "оружие без строки и без записи «строки нет»" do
      root =
        copy_with("vanilla/weapon_wield.json", fn json ->
          update_in(json["weapons"], &Enum.reject(&1, fn w -> w["id"] == "shortbow" end))
        end)

      assert_raise RuntimeError, ~r/uncovered \[\"shortbow\"\]/, fn -> Loader.load!(root) end
    end

    test "код, которого правило не называет" do
      root = copy_with("vanilla/weapon_wield.json", &set_code(&1, "shortbow", 9))

      assert_raise RuntimeError, ~r/shortbow carries WeaponWield 9/, fn -> Loader.load!(root) end
    end

    test "слово хвата, которого нет в правиле" do
      root =
        copy_with("vanilla/weapon_wield.json", fn json ->
          update_in(json["rule"]["stated_grip"], fn list ->
            for e <- list, do: Map.put(e, "grip", "two_hands")
          end)
        end)

      assert_raise RuntimeError, ~r/not words of the grip rule/, fn -> Loader.load!(root) end
    end

    test "лестница размеров объявлена, а файла нет" do
      root = BuildCalculator.TmpDir.unique_path!("weapon_wield_")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      File.rm!(Path.join(root, "vanilla/weapon_wield.json"))

      assert_raise RuntimeError, ~r/weapon_wield.json is missing/, fn -> Loader.load!(root) end
    end

    test "слой Сиалы не про те же 47" do
      root =
        copy_with("siala_41/generated/weapons.json", fn json ->
          update_in(json["weapons"], &Enum.reject(&1, fn w -> w["id"] == "dart" end))
        end)

      assert_raise RuntimeError, ~r/misses \[\"dart\"\]/, fn -> Loader.load!(root) end
    end
  end

  # 🔴 Слоение по id: названное колонкой Сиалы — её, молчание — ванильное.
  # На живых данных у всех девяти, которых таблица Сиалы не называет, ванильное
  # тоже `nil`, и наследование не видно — поэтому синтетика: древковое (4)
  # переносится в «называет хват» (то, что сделал бы замер «щит снимается»).
  test "молчит Сиала — ваниль: посох наследует хват таблицы игры, дротик — нет" do
    root =
      copy_with("vanilla/weapon_wield.json", fn json ->
        update_in(json["rule"], fn rule ->
          rule
          |> Map.update!("size_decides", &Enum.reject(&1, fn e -> e["weapon_wield"] == 4 end))
          |> Map.update!("stated_grip", &(&1 ++ [%{"weapon_wield" => 4, "grip" => "two_handed"}]))
        end)
      end)

    loaded = load(root)

    # Посох: Сиала его не называет — наследует ванильное.
    assert loaded["vanilla"].weapons[:magic_staff].stated_grip == :two_handed
    assert loaded["siala_41"].weapons[:magic_staff].stated_grip == :two_handed

    # Трезубец: Сиала называет сама — её значение (с задачи 4.42 одноручное,
    # замер AY1), а у ванили код **** (размер).
    assert loaded["vanilla"].weapons[:trident].stated_grip == nil
    assert loaded["siala_41"].weapons[:trident].stated_grip == :one_handed

    # Контроль: на живых данных посох у обоих — `nil`, то есть сдвинула его
    # правка правила, а не что-то ещё.
    assert Data.ruleset!("vanilla").weapons[:magic_staff].stated_grip == nil
    assert Data.ruleset!("siala_41").weapons[:magic_staff].stated_grip == nil
  end
end
