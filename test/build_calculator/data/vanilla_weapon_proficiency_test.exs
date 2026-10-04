defmodule BuildCalculator.Data.VanillaWeaponProficiencyTest do
  @moduledoc """
  Владение оружием у ВАНИЛИ — правило `vanilla/rules.json` →
  `gear.weapon.proficiency` над собственным списком справочника
  `vanilla/weapons.json` (задача 4.7).

  До задачи `proficiency` у ванили было `:unread` у всех 47 записей: списки
  владений лежали в справочнике (параметр `proficiency` шаблона {{Weapon}}),
  задача 4.5 сверила их с колонками ReqFeat0…4 baseitems.2da — совпали у всех
  41 сопоставленного оружия, — а загрузчик читал только группы Сиалы. Отсюда
  `{:missing_data, {:weapon_proficiency, w}}` у любого ванильного билда
  с оружием, к тому же дублем у того, кто и держит оружие, и взял на него
  `Weapon focus`.

  🔴 Правило — «любой из списка», а не «категория»: у дубины пять владений,
  и волшебник берёт её своим, без Simple. Ядро держит это формой
  `{:any_of, ids}` (`Rules.GearWeapon`), здесь — что загрузчик её собирает
  и что всё, чего он прочитать не может, роняет сборку.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, GearWeapon}

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp copy_with(relative, fun) do
    root = BuildCalculator.TmpDir.unique_path!("vanilla_proficiency_")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)

    path = Path.join(root, relative)
    File.write!(path, path |> File.read!() |> Jason.decode!() |> fun.() |> Jason.encode!())
    root
  end

  defp edit_rule(fun) do
    copy_with("vanilla/rules.json", &update_in(&1, ["gear", "weapon", "proficiency"], fun))
  end

  defp shape({:feat, _}), do: :feat
  defp shape({:any_of, _}), do: :any_of
  defp shape(other), do: other

  describe "ваниль называет владение у всех 47" do
    test "непрочитанного не осталось ни одного", %{vanilla: v} do
      census = v.weapons |> Map.values() |> Enum.frequencies_by(&shape(&1.proficiency))

      assert census == %{feat: 24, any_of: 20, none_needed: 3}
      refute Map.has_key?(census, :unread)
    end

    # Список — ровно тот, что стоит в справочнике, и тем же порядком чтения:
    # один фит — `{:feat, id}` (форма Сиалы), больше — `{:any_of, …}` по имени.
    test "формы по списку справочника", %{vanilla: v} do
      assert v.weapons[:club].proficiency ==
               {:any_of,
                [
                  :weapon_proficiency_druid,
                  :weapon_proficiency_monk,
                  :weapon_proficiency_rogue,
                  :weapon_proficiency_simple,
                  :weapon_proficiency_wizard
                ]}

      assert v.weapons[:longsword].proficiency ==
               {:any_of, [:weapon_proficiency_elf, :weapon_proficiency_martial]}

      assert v.weapons[:greatsword].proficiency == {:feat, :weapon_proficiency_martial}
      assert v.weapons[:katana].proficiency == {:feat, :weapon_proficiency_exotic}
      assert v.weapons[:creature_weapon].proficiency == {:feat, :weapon_proficiency_creature}
    end

    # Пустой список решён поимённо и своим источником: посох и лэнс — пустой
    # ReqFeat таблицы («all characters are automatically proficient»), удар —
    # не предмет. Для ядра все трое — «не требует».
    test "три пустых списка — «не требует», каждый названный", %{vanilla: v} do
      for id <- [:magic_staff, :lance, :unarmed_strike] do
        assert v.weapons[id].proficiency == :none_needed, "#{id}"
      end
    end

    # 🔴 Сиала свою систему не отдаёт: её группы заменяют ванильные списки
    # целиком, и оружие без группы (формы атаки существ) остаётся `:unread`,
    # а не подхватывает ванильное Weapon proficiency (creature).
    test "у Сиалы — её группы, ванильный список не подмешан", %{siala: s} do
      assert s.weapons[:longsword].proficiency == {:feat, :siala_blade_proficiency}
      assert s.weapons[:club].proficiency == :none_needed
      assert s.weapons[:creature_weapon].proficiency == :unread

      refute Enum.any?(s.weapons, fn {_id, w} -> match?({:any_of, _}, w.proficiency) end)
    end
  end

  describe "ядро: хватает любого, расовый фит считается" do
    test "unmet_proficiency/2 — четыре ответа" do
      held = MapSet.new([:weapon_proficiency_wizard])

      assert GearWeapon.unmet_proficiency({:feat, :weapon_proficiency_wizard}, held) == []

      assert GearWeapon.unmet_proficiency({:feat, :weapon_proficiency_simple}, held) ==
               [{:requires_feat, :weapon_proficiency_simple}]

      assert GearWeapon.unmet_proficiency(
               {:any_of, [:weapon_proficiency_simple, :weapon_proficiency_wizard]},
               held
             ) == []

      assert GearWeapon.unmet_proficiency(
               {:any_of, [:weapon_proficiency_elf, :weapon_proficiency_martial]},
               held
             ) == [
               {:requires_any_of,
                [
                  [{:requires_feat, :weapon_proficiency_elf}],
                  [{:requires_feat, :weapon_proficiency_martial}]
                ]}
             ]

      assert GearWeapon.unmet_proficiency(:none_needed, MapSet.new()) == []
      assert GearWeapon.unmet_proficiency(:unread, MapSet.new()) == []
    end

    test "racial_feats/2 — бонусные фиты расы, пусто без расы", %{vanilla: v} do
      assert :weapon_proficiency_elf in GearWeapon.racial_feats(Build.new(race: :elf), v)
      refute :weapon_proficiency_elf in GearWeapon.racial_feats(Build.new(race: :human), v)
      assert GearWeapon.racial_feats(Build.new(), v) == MapSet.new()
    end

    # Близнецы по расе: волшебник-человек и волшебник-эльф, одно оружие.
    test "эльфу-волшебнику длинный меч по руке и в фокус, человеку — нет", %{vanilla: v} do
      wizard = fn race -> Build.new(race: race, levels: List.duplicate(:wizard, 8)) end
      focus = %{feat: :weapon_focus, choice: :longsword, at: 9}

      assert GearWeapon.validate(wizard.(:elf), :longsword, v) == :ok
      assert Rules.validate_feat(wizard.(:elf), focus, v) == :ok

      refusal =
        {:requires_any_of,
         [
           [{:requires_feat, :weapon_proficiency_elf}],
           [{:requires_feat, :weapon_proficiency_martial}]
         ]}

      assert GearWeapon.validate(wizard.(:human), :longsword, v) == {:error, [refusal]}
      assert Rules.validate_feat(wizard.(:human), focus, v) == {:error, [refusal]}
    end
  end

  describe "загрузчик роняет сборку, а не молчит" do
    test "ключ справочника без фита в правиле" do
      root = edit_rule(&update_in(&1, ["feats"], fn feats -> Map.delete(feats, "wizard") end))

      assert_raise RuntimeError, ~r/club asks for proficiency "wizard"/, fn ->
        Loader.load!(root)
      end
    end

    test "фит, которого нет в справочнике фитов" do
      root = edit_rule(&put_in(&1, ["feats", "wizard"], "weapon_proficiency_wizzard"))

      assert_raise RuntimeError, ~r/names weapon_proficiency_wizzard, which is not a feat/, fn ->
        Loader.load!(root)
      end
    end

    test "один фит под двумя ключами" do
      root = edit_rule(&put_in(&1, ["feats", "wizard"], "weapon_proficiency_simple"))

      assert_raise RuntimeError, ~r/one feat under two keys/, fn -> Loader.load!(root) end
    end

    test "«не требует» у оружия с непустым списком" do
      root =
        edit_rule(
          &update_in(&1, ["automatically_proficient", "weapons"], fn ws -> ws ++ ["club"] end)
        )

      assert_raise RuntimeError, ~r/names club as needing no proficiency/, fn ->
        Loader.load!(root)
      end
    end

    test "оружие, которого нет в справочнике" do
      root =
        edit_rule(&update_in(&1, ["not_applicable", "weapons"], fn ws -> ws ++ ["pitchfork"] end))

      assert_raise RuntimeError, ~r/names pitchfork/, fn -> Loader.load!(root) end
    end

    test "незнакомое правило" do
      root = edit_rule(&Map.put(&1, "rule", "category"))

      assert_raise RuntimeError, ~r/proficiency.rule is "category"/, fn -> Loader.load!(root) end
    end

    # То же поблочно: «не требует» без подтверждения не читается, и его
    # оружие говорит «владение не прочитано», а не молча проходит фильтр.
    test "блок «не требует» без статуса verified — его оружие :unread, соседний читается" do
      loaded =
        Loader.load!(edit_rule(&put_in(&1, ["automatically_proficient", "status"], "unclear")))

      for id <- [:lance, :magic_staff] do
        assert loaded["vanilla"].weapons[id].proficiency == :unread, "#{id}"
      end

      assert loaded["vanilla"].weapons[:unarmed_strike].proficiency == :none_needed
    end

    test "блок «не требует» не той формы" do
      root = edit_rule(&put_in(&1, ["not_applicable"], ["unarmed_strike"]))

      assert_raise RuntimeError, ~r/not_applicable is \["unarmed_strike"\]/, fn ->
        Loader.load!(root)
      end
    end

    # Правило, которого никто не подтвердил, не читается — и тогда ваниль
    # говорит ровно то, что говорила до задачи: владение не прочитано.
    test "правило без статуса verified — все 47 снова :unread" do
      loaded = Loader.load!(edit_rule(&Map.put(&1, "status", "unclear")))

      assert loaded["vanilla"].weapons |> Map.values() |> Enum.all?(&(&1.proficiency == :unread))
      assert loaded["siala_41"] == Data.ruleset!("siala_41")
    end
  end
end
