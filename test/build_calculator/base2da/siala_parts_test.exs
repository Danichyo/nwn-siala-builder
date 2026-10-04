defmodule BuildCalculator.Base2da.SialaPartsTest do
  @moduledoc """
  Части сверки хака Сиалы `mix hak2da.diff` (задача 4.49), которые проверяются
  без файлов игры: слоёный источник (имя строки из кастомного `.tlk` шарда),
  явная таблица строк, виды находок Сиалы и пометка слоя в отчёте. Сама сверка
  на выгрузках — `hak2da_positive_control_test.exs`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.{Finding, Ids, Report, SialaClassification, Source}
  alias BuildCalculator.GameFiles.TwoDA

  # Две таблицы `feat`: у базы три строки, у «хака» — те же три, где у второй
  # имя из кастомного .tlk (0x01000000+), у третьей — кастомное имя И другая
  # метка, плюс четвёртая строка, которой у базы нет.
  defp sources do
    base_feat = "2DA V2.0\n\nLABEL FEAT\n0 PowerAttack 100\n1 Cleave 101\n2 Dodge 102\n"

    hak_feat =
      "2DA V2.0\n\nLABEL FEAT\n0 PowerAttack 100\n1 Cleave 16777300\n2 Renamed 16777301\n" <>
        "3 Hammers 16777302\n"

    names = %{100 => "Power Attack", 101 => "Cleave", 102 => "Dodge"}

    base = %Source{
      tables: %{"feat" => TwoDA.parse!(base_feat)},
      names: names,
      origin: %{"feat" => :base}
    }

    layered = %Source{
      tables: %{"feat" => TwoDA.parse!(hak_feat)},
      names: names,
      origin: %{"feat" => :hak},
      base: base,
      top: %{dir: "hak", manifest: %{"tables" => %{}}, tables: ["feat"]}
    }

    {base, layered}
  end

  describe "Source.row_name/4 у слоёного источника" do
    test "кастомное имя шарда — имя той же строки базы, если метка та же" do
      {_base, layered} = sources()

      assert Source.row_name(layered, "feat", 0, "FEAT") == "Power Attack"
      assert Source.row_name(layered, "feat", 1, "FEAT") == "Cleave"
    end

    test "метка другая или строки у базы нет — имени нет, а не выдумка" do
      {_base, layered} = sources()

      assert Source.row_name(layered, "feat", 2, "FEAT") == nil
      assert Source.row_name(layered, "feat", 3, "FEAT") == nil
    end

    test "у одиночного источника отката нет" do
      {base, _layered} = sources()
      refute Source.layered?(base)
      assert Source.row_name(base, "feat", 2, "FEAT") == "Dodge"
    end
  end

  describe "Ids.feats/3 — явная таблица строк" do
    test "строка из таблицы получает id, метка сверяется" do
      {_base, layered} = sources()
      ruleset = BuildCalculator.Data.ruleset!("siala_41")

      overrides = %{3 => %{label: "Hammers", id: :siala_hammer_proficiency, name: "Hammers"}}
      {found, _missing} = Ids.feats(layered, ruleset, overrides)

      assert found[0] == :power_attack
      assert found[1] == :cleave
      assert found[3] == :siala_hammer_proficiency
      refute Map.has_key?(found, 2)
    end

    test "шард сдвинул строку — сверка падает, а не сопоставляет чужую" do
      {_base, layered} = sources()
      ruleset = BuildCalculator.Data.ruleset!("siala_41")
      overrides = %{3 => %{label: "Axes", id: :siala_axe_proficiency, name: "Axes"}}

      assert_raise RuntimeError, ~r/шард сдвинул строку/, fn ->
        Ids.feats(layered, ruleset, overrides)
      end
    end

    test "id: nil — строка без id, в списке несопоставленных под своим именем" do
      {_base, layered} = sources()
      ruleset = BuildCalculator.Data.ruleset!("siala_41")
      overrides = %{1 => %{label: "Cleave", id: nil, name: "Не Cleave"}}

      {found, missing} = Ids.feats(layered, ruleset, overrides)
      refute Map.has_key?(found, 1)
      assert {1, "Не Cleave"} in missing
    end
  end

  describe "SialaClassification" do
    test "у каждого правила вид из закрытого списка, ключ и довод" do
      for rule <- SialaClassification.rules() do
        assert rule.kind in [:a, :b, :c, :d, :e], inspect(rule.key)
        assert is_binary(rule.note) and String.length(rule.note) > 40, inspect(rule.key)
        assert is_binary(rule.key) or is_struct(rule.key, Regex)
      end
    end

    test "правило прибито к значениям: другое значение — без вида" do
      pinned = %Finding{
        area: :repeatable,
        subject: "epic_toughness",
        field: "max_takes",
        base: "9",
        ours: "10"
      }

      assert %{kind: :e} = SialaClassification.classify(pinned, %{})
      assert %{kind: nil} = SialaClassification.classify(%{pinned | base: "8"}, %{})
    end

    test "находка, совпавшая с ванильной до буквы, наследует вид; не совпавшая — нет" do
      finding = %Finding{area: :x, subject: "y", field: "z", base: "1", ours: "2"}

      vanilla = %{
        "x/y/z" => %{finding | kind: :c, note: "движок"}
      }

      assert %{kind: :c, note: "Как у ванили" <> _} =
               SialaClassification.classify(finding, vanilla)

      assert %{kind: nil} = SialaClassification.classify(%{finding | ours: "3"}, vanilla)
    end

    test "вид, поставленный самим сравнением, остаётся" do
      finding = %Finding{area: :x, subject: "y", field: "z", base: "1", ours: "2", kind: :b}
      assert %{kind: :b} = SialaClassification.classify(finding, %{})
    end
  end

  test "Report: у слоёного источника таблица в подробностях помечена слоем" do
    {_base, layered} = sources()

    finding = %Finding{
      area: :feats,
      subject: "s",
      field: "f",
      base: "1",
      base_at: "feat.2da:3 Hammers; cls_feat_*.2da; skills.2da",
      ours: "2",
      kind: :b,
      note: "довод"
    }

    text =
      Report.details(
        %{areas: [%{area: :feats, title: "Фиты", checks: 1, findings: [finding]}]},
        Report.profile(:siala),
        layered
      )

    assert text =~ "хак/feat.2da:3 Hammers; cls_feat_*.2da; skills.2da"
    assert text =~ "(b) разница представления"
  end
end
