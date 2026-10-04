defmodule BuildCalculator.GameFiles.BaseExtractTest do
  @moduledoc """
  `mix base2da.extract` на синтетической установке NWN:EE, собранной в тесте
  (задача 4.5): старшинство ключей, манифест, имена из TLK, замыкание ссылок,
  идемпотентность и отказы. Настоящей игры здесь нет — её нет в CI.
  """
  use ExUnit.Case, async: true

  import BuildCalculator.GameFilesFixtures

  alias BuildCalculator.GameFiles.BaseExtract
  alias BuildCalculator.TmpDir

  @tables ~w(classes feat racialtypes ruleset)
  @families ~w(cls_atk_ race_feat_)

  setup do
    root = TmpDir.unique_path!("nwn-install-")
    out = TmpDir.unique_path!("base-2da-")

    on_exit(fn ->
      File.rm_rf(root)
      File.rm_rf(out)
    end)

    %{root: root, out: out}
  end

  defp classes(extra_rows \\ []) do
    two_da(
      ~w(Label Name HitDie AttackBonusTable PlayerClass),
      [["Fighter", 1, 10, "CLS_ATK_1", 1], ["Commoner", 2, 8, "CLS_ATK_9", 0] | extra_rows]
    )
  end

  defp base_tables(overrides \\ %{}) do
    Map.merge(
      %{
        "classes" => classes(),
        "feat" => two_da(~w(LABEL FEAT), [["Alertness", 3]]),
        "racialtypes" =>
          two_da(~w(Label Name FeatsTable PlayerRace), [["Dwarf", 4, "RACE_FEAT_DWARF", 1]]),
        "ruleset" => two_da(~w(Label Value), [["CHARGEN_BASE_ABILITY_MIN", 8]]),
        "cls_atk_1" => two_da(~w(BAB), [[1], [2]]),
        "race_feat_dwarf" => two_da(~w(FeatLabel FeatIndex), [["darkvision", 0]]),
        # не входит ни в список, ни в семейства — выгружаться не должна
        "appearance" => two_da(~w(LABEL), [["Dwarf"]])
      },
      overrides
    )
  end

  defp run(ctx), do: BaseExtract.run(ctx.root, ctx.out, tables: @tables, families: @families)

  test "writes the wanted tables byte for byte and a manifest that says where each came from",
       ctx do
    newer_ruleset =
      two_da(~w(Label Value), [["CHARGEN_BASE_ABILITY_MIN", 8], ["MULTICLASS_LIMIT", 3]])

    install!(ctx.root,
      base: base_tables(),
      retail: %{"ruleset" => newer_ruleset},
      strings: ["Bad Strref", "Fighter", "Commoner", "Alertness", "Dwarf"]
    )

    assert {:ok, summary} = run(ctx)
    assert summary.tables == 6
    assert summary.overridden == 1

    assert File.ls!(ctx.out) |> Enum.sort() ==
             ~w(classes.2da cls_atk_1.2da dialog_names.json feat.2da manifest.json
                race_feat_dwarf.2da racialtypes.2da ruleset.2da)

    # Слой nwn_retail.key старше nwn_base.key: игра читает его копию.
    assert File.read!(Path.join(ctx.out, "ruleset.2da")) == newer_ruleset
    assert File.read!(Path.join(ctx.out, "classes.2da")) == classes()

    manifest = Jason.decode!(File.read!(Path.join(ctx.out, "manifest.json")))
    ruleset = manifest["tables"]["ruleset"]
    assert ruleset["key"] == "data/nwn_retail.key"
    assert ruleset["bif"] == "data/ovr.bif"
    assert ruleset["sha1"] == sha1(newer_ruleset)

    assert [%{"key" => "data/nwn_base.key", "bif" => "data/base_2da.bif"} = shadowed] =
             ruleset["overrides"]

    assert shadowed["sha1"] == sha1(base_tables()["ruleset"])
    refute Map.has_key?(manifest["tables"]["classes"], "overrides")

    assert manifest["game"]["version"] == "89.8193.37-2"
    assert manifest["game"]["released"] == "2025-02-02"
    assert manifest["game"]["databuild"] == "r42 Mon Jan  1 00:00:00 UTC 2024"

    assert Enum.map(manifest["game"]["keys"], &{&1["file"], &1["precedence"], &1["built_on"]}) ==
             [
               {"data/nwn_retail.key", 1, "2025-10-06"},
               {"data/nwn_base.key", 2, "2024-02-26"}
             ]

    # Имена — только те строки, на которые ссылаются колонки имён выгруженных таблиц.
    names = Jason.decode!(File.read!(Path.join(ctx.out, "dialog_names.json")))
    assert names == %{"1" => "Fighter", "2" => "Commoner", "3" => "Alertness", "4" => "Dwarf"}
  end

  test "a second run changes no byte; a table gone from the set is removed", ctx do
    install!(ctx.root,
      base: base_tables(),
      strings: ["x", "Fighter", "Commoner", "Alertness", "Dwarf"]
    )

    assert {:ok, _} = run(ctx)
    before = snapshot(ctx.out)
    assert {:ok, %{removed: 0}} = run(ctx)
    assert snapshot(ctx.out) == before

    File.write!(Path.join(ctx.out, "leftover.2da"), "2DA V2.0\n")
    assert {:ok, %{removed: 1}} = run(ctx)
    assert snapshot(ctx.out) == before
  end

  test "a table a playable class points at must be in the set", ctx do
    install!(ctx.root,
      base: base_tables(%{"classes" => classes([["Wizard", 1, 4, "CLS_ATK_3", 1]])}),
      strings: ["x", "Fighter"]
    )

    assert {:error, message} = run(ctx)
    assert message =~ "cls_atk_3"

    # Commoner (PlayerClass 0) ссылается на CLS_ATK_9, которой тоже нет, — но он не играбельный.
    refute message =~ "cls_atk_9"
  end

  test "no install, a missing table, a missing TLK and loose files in ovr/ are errors", ctx do
    assert {:error, message} = run(ctx)
    assert message =~ "NWN_ROOT"

    install!(ctx.root, base: Map.delete(base_tables(), "ruleset"), strings: ["x"])
    assert {:error, "в установке нет таблиц: ruleset"} = run(ctx)

    File.rm_rf!(ctx.root)
    install!(ctx.root, base: base_tables(), tlk: false)
    assert {:error, message} = run(ctx)
    assert message =~ "dialog.tlk"

    File.rm_rf!(ctx.root)
    install!(ctx.root, base: base_tables(), strings: ["x"])
    File.mkdir_p!(Path.join(ctx.root, "ovr"))
    File.write!(Path.join(ctx.root, "ovr/classes.2da"), classes())
    assert {:error, message} = run(ctx)
    assert message =~ "ovr"
    refute File.exists?(ctx.out)
  end

  defp snapshot(dir) do
    dir |> File.ls!() |> Enum.sort() |> Enum.map(&{&1, File.read!(Path.join(dir, &1))})
  end

  defp sha1(bytes), do: :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower)
end
