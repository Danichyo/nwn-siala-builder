defmodule BuildCalculator.Data.IconsTest do
  @moduledoc """
  Guards `priv/rules/vanilla/icons.json` and the files it describes — task
  3.50, part A (data-miner).

  Deliberately offline, same as every other data test: it re-verifies the
  **committed** bytes under `priv/static/icons/` against the **committed**
  manifest, never the wiki. `mix wiki.fetch.icons` is the only thing here that
  talks to Fandom; this file is the guarantee that what it wrote once stays
  honest as the repository changes underneath it — a feat's `icon` field
  edited without re-running the fetch, or a file trimmed from disk by hand,
  both fail a test here instead of shipping silently.

  Three things are checked, and they answer different questions:

    * completeness — every `icon` string `feats.json`/`spells.json` actually
      carry has a manifest entry that resolves to a file on disk, and nothing
      in the manifest names a file that is not there;
    * the manifest is not lying about what is on disk *right now* — declared
      `downloaded_size`/`downloaded_sha1` match the committed bytes exactly,
      whether or not those bytes match Fandom's own metadata (`verified`);
    * the two collision pairs (task moduledoc, `Mix.Tasks.Wiki.Fetch.Icons`)
      are still exactly two, still exactly those two files — a regression
      here would mean either the wiki's own title normalisation changed
      (unlikely) or a re-run silently produced fewer files than names.

  ⚠️ Every `for domain <- @domains do test … end` loop below closes over the
  domain's records via `unquote(Macro.escape(records))`, not by indexing
  `@icons`/`@feats`/`@spells` again inside the generated test body. Elixir's
  type checker treats a module attribute holding a fully-known literal (which
  all three are — plain `Jason.decode!` output) as a closed union of every
  value in it; a runtime `Map.fetch!(@icons, label)` inside the compiled
  function therefore infers as "some feats record OR some spells record OR a
  bare binary" instead of "a list", and `for record <- that` fails
  `--warnings-as-errors` with an Enumerable-protocol type error. Embedding the
  already-selected list as a literal sidesteps the lookup entirely.
  """

  use ExUnit.Case, async: true

  @root File.cwd!()

  @icons "priv/rules/vanilla/icons.json" |> File.read!() |> Jason.decode!()
  @feats "priv/rules/vanilla/feats.json" |> File.read!() |> Jason.decode!()
  @spells "priv/rules/vanilla/spells.json" |> File.read!() |> Jason.decode!()

  @icon_feats @icons["feats"]
  @icon_spells @icons["spells"]

  @domains [
    {"feats", @feats, @icon_feats},
    {"spells", @spells, @icon_spells}
  ]

  defp static_path(relative), do: Path.join([@root, "priv/static", relative])

  describe "shape" do
    test "top level carries provenance and exactly the two domains" do
      assert @icons["_layer"] == "vanilla"
      assert @icons["_generated_by"] == "mix wiki.fetch.icons"
      assert is_binary(@icons["_note"]) and @icons["_note"] != ""

      assert Map.keys(@icons) |> Enum.sort() ==
               Enum.sort(["_layer", "_generated_by", "_note", "feats", "spells"])
    end

    test "every record carries the full field set" do
      fields =
        ~w(names file resolved_title pageid size width height mime sha1
           downloaded_size downloaded_sha1 verified source_url wiki fetched)

      for {label, _source, records} <- @domains,
          record <- records do
        for field <- fields do
          assert Map.has_key?(record, field),
                 "[#{label}] #{inspect(record["file"])} misses #{field}"
        end

        assert record["names"] != [], "[#{label}] #{record["file"]} has no names at all"
        assert record["wiki"] == "fandom"
      end
    end
  end

  describe "completeness — no icon name silently lost" do
    for {label, source, records} <- @domains do
      test "every #{label} `icon` string resolves to a manifest entry on disk" do
        source = unquote(Macro.escape(source))
        manifest = unquote(Macro.escape(records))
        label = unquote(label)

        wanted =
          source
          |> Enum.map(& &1["icon"])
          |> Enum.reject(&is_nil/1)
          |> MapSet.new()

        covered = manifest |> Enum.flat_map(& &1["names"]) |> MapSet.new()

        missing = MapSet.difference(wanted, covered)

        assert missing == MapSet.new(),
               "[#{label}] icon names with no manifest entry: #{inspect(missing)}"

        # The reverse direction matters too: a manifest entry naming something
        # no longer in feats.json/spells.json would be silently stale data
        # nobody notices, exactly the failure mode `mix wiki.parse`'s
        # idempotency check exists to catch on the wikitext side.
        extra = MapSet.difference(covered, wanted)

        assert extra == MapSet.new(),
               "[#{label}] manifest names nothing asks for: #{inspect(extra)}"
      end
    end
  end

  describe "files on disk match what the manifest says about them" do
    for {label, _source, records} <- @domains do
      test "#{label}: every file exists, and downloaded_size/downloaded_sha1 are not stale" do
        label = unquote(label)

        for record <- unquote(Macro.escape(records)) do
          path = static_path(record["file"])

          assert File.exists?(path),
                 "[#{label}] #{record["file"]} is in the manifest but not on disk"

          bytes = File.read!(path)

          assert byte_size(bytes) == record["downloaded_size"],
                 "[#{label}] #{record["file"]}: on-disk size drifted from the manifest"

          sha1 = :sha |> :crypto.hash(bytes) |> Base.encode16(case: :lower)

          assert sha1 == record["downloaded_sha1"],
                 "[#{label}] #{record["file"]}: on-disk sha1 drifted from the manifest"
        end
      end
    end
  end

  describe "`verified` means what it says" do
    for {label, _source, records} <- @domains do
      test "#{label}: verified is true exactly when downloaded matches wiki metadata" do
        label = unquote(label)

        for record <- unquote(Macro.escape(records)) do
          expected =
            record["downloaded_size"] == record["size"] and
              record["downloaded_sha1"] == record["sha1"]

          assert record["verified"] == expected,
                 "[#{label}] #{record["file"]}: verified flag disagrees with its own size/sha1 fields"
        end
      end
    end
  end

  describe "magic bytes still match the declared MIME (re-checked from committed bytes)" do
    @signatures %{
      "image/gif" => ["GIF87a", "GIF89a"],
      "image/png" => [<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>],
      "image/jpeg" => [<<0xFF, 0xD8, 0xFF>>]
    }

    for {label, _source, records} <- @domains do
      test "#{label}: every committed file starts with its declared format's signature" do
        label = unquote(label)

        for record <- unquote(Macro.escape(records)) do
          bytes = static_path(record["file"]) |> File.read!()
          signatures = Map.fetch!(@signatures, record["mime"])

          assert Enum.any?(signatures, &String.starts_with?(bytes, &1)),
                 "[#{label}] #{record["file"]}: does not start with a #{record["mime"]} signature"
        end
      end
    end
  end

  describe "the two known name collisions (task moduledoc)" do
    test "exactly two feat records carry more than one name, and they are the known pair" do
      multi = Enum.filter(@icon_feats, &(length(&1["names"]) > 1))

      assert length(multi) == 2

      assert multi |> Enum.map(& &1["names"]) |> Enum.map(&Enum.sort/1) |> Enum.sort() ==
               [
                 ["Ife_ambidex.gif", "ife ambidex.gif"],
                 ["ife x2ddarmor.gif", "ife_x2ddarmor.gif"]
               ]
    end

    test "no spell record carries more than one name" do
      assert Enum.all?(@icon_spells, &(length(&1["names"]) == 1))
    end
  end

  describe "the static asset is actually servable" do
    test "\"icons\" is on BuildCalculatorWeb.static_paths/0, or every file 404s" do
      assert "icons" in BuildCalculatorWeb.static_paths()
    end
  end
end
