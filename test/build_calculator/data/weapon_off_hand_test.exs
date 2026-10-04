defmodule BuildCalculator.Data.WeaponOffHandTest do
  @moduledoc """
  «Какой рукой можно» — `vanilla/weapon_off_hand.json` и сиальская половина
  `siala_41/weapon_off_hand.json` (задача 4.29).

  Файл переписывает колонку `EquipableSlots` таблицы игры `baseitems.2da` для
  41 оружия справочника (бит `0x00020` — вторая рука, Fandom «Baseitems.2da»)
  и запрет движка на цепы и моргенштерн. Слой Сиалы ложится поверх по `id`:
  хак шарда даёт кнуту бит второй руки, которого у базовой игры нет.

  Здесь — то, что сторожит загрузчик: регистрация, полнота покрытия, маска
  из данных, id, слоение. Ответы ядра по всем видам — `wield_matrix_test.exs`;
  ячейки таблицы — `provenance_test.exs` («цитаты-строки базовых таблиц»);
  строки хака — `weapon_off_hand_hak_test.exs`.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Data.Loader.Layers

  @vanilla_file "priv/rules/vanilla/weapon_off_hand.json"
  @siala_file "priv/rules/siala_41/weapon_off_hand.json"
  @vanilla_raw @vanilla_file |> File.read!() |> Jason.decode!()
  @siala_raw @siala_file |> File.read!() |> Jason.decode!()

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  # Копия `priv/rules` с правкой одного JSON — только через `TmpDir` (CLAUDE.md §7).
  defp copy_with(relative, fun) do
    root = BuildCalculator.TmpDir.unique_path!("weapon_off_hand_")
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

  defp set_slots(json, id, value) do
    update_in(json["weapons"], fn list ->
      for w <- list, do: if(w["id"] == id, do: Map.put(w, "equipable_slots", value), else: w)
    end)
  end

  describe "файлы подключены" do
    test "оба зарегистрированы по имени" do
      assert "vanilla/weapon_off_hand.json" in Loader.source_files()
      assert "siala_41/weapon_off_hand.json" in Loader.source_files()
    end

    # Список `weapons` на верхнем уровне сделал бы файл доменом выбора, если
    # бы загрузчик не знал его по имени (`Reading`, `@rules_files`).
    test "не стал доменом выбора", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        refute Map.has_key?(ruleset.choice_domains, :weapon_off_hand)
      end
    end

    test "покрывает справочник целиком: 41 строка таблицы и 6 без строки", %{vanilla: vanilla} do
      rows = for w <- @vanilla_raw["weapons"], do: String.to_existing_atom(w["id"])
      absent = for id <- @vanilla_raw["not_in_baseitems"]["ids"], do: String.to_existing_atom(id)

      assert length(rows) == 41
      assert Enum.sort(absent) == ~w(bite_item claw_item creature_weapon gore_item slam_item
                                     unarmed_strike)a

      assert Enum.sort(rows ++ absent) == vanilla.weapons |> Map.keys() |> Enum.sort()
    end

    # Ячейки — те же строки, что у хвата: одно оружие — одна строка таблицы.
    test "строки те же, что в vanilla/weapon_wield.json" do
      wield = "priv/rules/vanilla/weapon_wield.json" |> File.read!() |> Jason.decode!()
      rows = fn file -> Map.new(file["weapons"], &{&1["id"], &1["source"]["row"]}) end

      assert rows.(@vanilla_raw) == rows.(wield)
      assert @vanilla_raw["not_in_baseitems"]["ids"] == wield["not_in_baseitems"]["ids"]
    end
  end

  describe "что загружено" do
    test "ваниль: четырнадцать без бита второй руки, три под запретом движка", %{
      vanilla: vanilla
    } do
      assert Enum.sort(vanilla.wield.main_hand_only.slot) ==
               ~w(dart dire_mace double_axe greataxe greatsword halberd heavy_flail magic_staff
                  quarterstaff scythe shuriken throwing_axe two_bladed_sword whip)a

      assert Enum.sort(vanilla.wield.main_hand_only.engine) ==
               ~w(heavy_flail light_flail morningstar)a
    end

    # 🔴 Разница двух ruleset'ов — ровно кнут, и ровно в `slot`: хак Сиалы
    # добавил ему бит второй руки (строка 111 `0x1C030`).
    test "Сиала: то же без кнута", %{vanilla: vanilla, siala: siala} do
      assert MapSet.difference(vanilla.wield.main_hand_only.slot, siala.wield.main_hand_only.slot) ==
               MapSet.new([:whip])

      assert MapSet.subset?(siala.wield.main_hand_only.slot, vanilla.wield.main_hand_only.slot)
      assert siala.wield.main_hand_only.engine == vanilla.wield.main_hand_only.engine
    end

    # Слой Сиалы несёт СВОЙ источник, и ванильный с записи уходит
    # (`Layers.merge/3`: «провенанс не сливается»). Иначе у сиальского кнута
    # осталась бы ванильная ячейка `0x1C010` рядом с хаковой `0x1C030`.
    test "слой Сиалы — одна запись, кнут, с источником хака вместо ванильного" do
      assert [%{"id" => "whip"} = whip] = @siala_raw["weapons"]
      assert whip["source"]["kind"] == "hak"
      assert whip["source"]["row"] == 111
      assert whip["source"]["value"] == whip["equipable_slots"]

      merged = Layers.merge(@vanilla_raw, @siala_raw, {"vanilla", "siala"})
      merged_whip = Enum.find(merged["weapons"], &(&1["id"] == "whip"))

      assert merged_whip["equipable_slots"] == "0x1C030"
      assert merged_whip["source"]["kind"] == "hak"
      assert length(merged["weapons"]) == 41
    end
  end

  describe "загрузчик читает данные, а не список в коде" do
    # Положительный контроль: ячейка из данных двигает ответ. Бит второй руки
    # у посоха — и посох уходит из `slot` на обоих ruleset'ах.
    test "бит второй руки у посоха — посох идёт во вторую руку" do
      loaded =
        load(copy_with("vanilla/weapon_off_hand.json", &set_slots(&1, "magic_staff", "0x1C030")))

      for {_version, ruleset} <- loaded do
        refute MapSet.member?(ruleset.wield.main_hand_only.slot, :magic_staff)
        assert MapSet.member?(ruleset.wield.main_hand_only.slot, :greatsword)
      end
    end

    # Маска — тоже из данных: объяви битом главную руку (`0x00010`), и без
    # бита окажутся только предметы, которых в главную руку не положить, —
    # таких среди оружия нет ни одного.
    test "маска бита — из rule.off_hand_bit" do
      loaded =
        load(
          copy_with("vanilla/weapon_off_hand.json", fn json ->
            put_in(json["rule"]["off_hand_bit"], "0x00010")
          end)
        )

      assert loaded["vanilla"].wield.main_hand_only.slot == MapSet.new()
    end
  end

  describe "загрузчик роняет сборку, а не молчит" do
    test "оружие без строки и без записи «строки нет»" do
      root =
        copy_with("vanilla/weapon_off_hand.json", fn json ->
          update_in(json["weapons"], &Enum.reject(&1, fn w -> w["id"] == "whip" end))
        end)

      assert_raise RuntimeError, ~r/uncovered \[\"whip\"\]/, fn -> Loader.load!(root) end
    end

    test "ячейка, которая не читается шестнадцатеричным числом" do
      root = copy_with("vanilla/weapon_off_hand.json", &set_slots(&1, "whip", "113680"))

      assert_raise RuntimeError, ~r/equipable_slots is "113680"/, fn -> Loader.load!(root) end
    end

    test "запрет движка на оружие, которого нет в справочнике" do
      root =
        copy_with("vanilla/weapon_off_hand.json", fn json ->
          update_in(json["engine_barred"]["weapons"], &(&1 ++ ["nunchaku"]))
        end)

      assert_raise RuntimeError, ~r/engine_barred` names \[\"nunchaku\"\]/, fn ->
        Loader.load!(root)
      end
    end

    test "лестница размеров объявлена, а файла нет" do
      root = BuildCalculator.TmpDir.unique_path!("weapon_off_hand_")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      File.rm!(Path.join(root, "vanilla/weapon_off_hand.json"))
      File.rm!(Path.join(root, "siala_41/weapon_off_hand.json"))

      assert_raise RuntimeError, ~r/weapon_off_hand.json is missing/, fn -> Loader.load!(root) end
    end

    # Запись шарда, которая ни на что не легла, — `Layers.merge/3`.
    test "запись Сиалы про оружие, которого у ванили нет" do
      root =
        copy_with("siala_41/weapon_off_hand.json", fn json ->
          update_in(json["weapons"], fn [whip] -> [whip, Map.put(whip, "id", "nunchaku")] end)
        end)

      assert_raise RuntimeError, ~r/id=\"nunchaku\"/, fn -> Loader.load!(root) end
    end
  end
end
