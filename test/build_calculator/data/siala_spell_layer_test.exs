defmodule BuildCalculator.Data.SialaSpellLayerTest do
  @moduledoc """
  `priv/rules/siala_41/spells.json` laid over the vanilla dictionary.

  The layer exists since 13.08.2026 and it is the last of the shard's five
  corpora to reach a number the calculator prints. Until that day
  `ruleset.spells` was the vanilla 303 in **both** rulesets: the machine layer
  (`generated/spells.json`) is a comparison report and was never applied, so a
  circle the shard had moved simply did not exist for us.

  ⚠ Why the layer is deliberately tiny while the report is huge. The report
  finds 115 of 128 matched pages different from vanilla — but the differences
  are damage, saving throw, duration, school: effects the calculator does not
  compute. The **circle** is the one field that reaches an answer we print, and
  only through the known-spell catalogue, which a Bard and a Sorcerer have and
  nobody else (`Rules.Spells.list_for/2`). So the layer carries circles, one
  measured record at a time, and the report stays a report.

  Both records here come from one measurement (`GAME_CHECKS.md`, K2): a Sorcerer
  8 has no `Wall of fire` on his fourth circle and does have `Stream of Flame`,
  a spell the shard added. They are two halves of one shard edit — the arcane
  half of `Wall of fire` was replaced, not deleted — which is why the test that
  the first is gone and the test that the second is there sit side by side.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules.Spells

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp circle(ruleset, class, circle) do
    for entry <- Spells.list_for(ruleset, class), entry.circle == circle, do: entry.id
  end

  describe "the arcane half the shard took away" do
    # ⚠ Both halves of the record under one assertion on purpose. "Vanilla has
    # it" and "Siala does not" each pass under a broken layer on their own — the
    # first if the layer never loaded, the second if it wiped the entry — and
    # the pair is what says an override happened.
    test "wall_of_fire keeps druid 5 and loses mage 4", %{siala: s, vanilla: v} do
      assert v.spells[:wall_of_fire].levels == %{druid: 5, mage: 4}
      assert s.spells[:wall_of_fire].levels == %{druid: 5}
    end

    test "so a Sorcerer's fourth circle no longer offers it", %{siala: s, vanilla: v} do
      assert :wall_of_fire in circle(v, :sorcerer, 4)
      refute :wall_of_fire in circle(s, :sorcerer, 4)
    end

    # The druid column is untouched, and that is a decision rather than an
    # oversight: the constructor shows no druid spell list at all (K1/K3 closed
    # on exactly that), but a correct number is not thrown away because nobody
    # is looking at it today.
    test "the druid half is not collateral damage", %{siala: s} do
      assert s.spells[:wall_of_fire].levels[:druid] == 5
    end
  end

  describe "the shard's own spell" do
    test "stream_of_flame exists only in the shard ruleset", %{siala: s, vanilla: v} do
      refute Map.has_key?(v.spells, :stream_of_flame)
      assert %{name: "Stream of Flame", levels: %{mage: 4}} = s.spells[:stream_of_flame]
    end

    test "a Sorcerer sees it on the fourth circle and a Bard not at all", %{siala: s} do
      assert :stream_of_flame in circle(s, :sorcerer, 4)
      assert Enum.all?(0..9, &(:stream_of_flame not in circle(s, :bard, &1)))
    end

    # It came in as an addition, not as a rewrite of something: the vanilla
    # corpus is exactly one entry shorter, and every other spell is shared.
    test "the corpus grew by one and nothing else moved", %{siala: s, vanilla: v} do
      assert map_size(s.spells) == map_size(v.spells) + 1

      assert MapSet.difference(
               MapSet.new(Map.keys(s.spells)),
               MapSet.new(Map.keys(v.spells))
             ) == MapSet.new([:stream_of_flame])
    end
  end

  # Задача 4.58: строка 50 `spells.2da` у шарда — «Отражение (Reflection)», а не
  # Endure elements (хак, `.tlk` шарда, страница Сиалы «Отражение»). Круги и
  # школа те же; меняется то, что печатает интерфейс, — имя и иконка. id тот же:
  # ссылки хранят id.
  describe "the shard's spell on a vanilla row (Reflection on Endure elements)" do
    # Обе половины под одним утверждением — как у `wall_of_fire` выше: «у ванили
    # так» и «у Сиалы иначе» по отдельности зеленеют и при сломанном слое.
    test "Siala calls it Reflection with the wiki's «Отражение»; vanilla is untouched",
         %{siala: s, vanilla: v} do
      assert %{name: "Reflection", ru: "Отражение", icon: nil} = s.spells[:endure_elements]

      assert %{name: "Endure elements", icon: "is_endelem.gif"} = v.spells[:endure_elements]
      refute Map.has_key?(v.spells[:endure_elements], :ru)
    end

    # Ровно имя и иконка: круги, школа и сырьё уровней — ванильные, иначе запись
    # переписала бы больше, чем говорит источник.
    test "circles and school are vanilla's on both rulesets", %{siala: s, vanilla: v} do
      drop = &Map.drop(&1, [:name, :ru, :icon])
      assert drop.(s.spells[:endure_elements]) == drop.(v.spells[:endure_elements])
      assert s.spells[:endure_elements].levels == %{cleric: 1, druid: 1, paladin: 1, mage: 1}
      assert s.spells[:endure_elements].school == :abjuration
    end

    test "a Sorcerer's first circle offers it under the shard's name", %{siala: s, vanilla: v} do
      names = fn ruleset ->
        for entry <- Spells.list_for(ruleset, :sorcerer), entry.circle == 1, do: entry.spell.name
      end

      assert "Reflection" in names.(s)
      refute "Endure elements" in names.(s)
      assert "Endure elements" in names.(v)
      refute "Reflection" in names.(v)
    end

    # Ни одна другая ванильная запись имени не сменила и `ru` не получила: правка
    # точечная, а не новая форма всего корпуса.
    test "no other spell is renamed or gets an alias", %{siala: s, vanilla: v} do
      renamed =
        for {id, spell} <- v.spells,
            other = s.spells[id],
            other.name != spell.name or Map.has_key?(other, :ru),
            do: id

      assert renamed == [:endure_elements]
    end
  end

  describe "the loader refuses what it cannot apply" do
    # The file is small and hand written, so a typo in it is a typo in the
    # rules. Both guards below would otherwise fail silently — an unknown key
    # doing nothing looks exactly like a key that was applied.
    # ⚠️ Раньше «незнакомым» ключом здесь стоял `"school"` — 24.08.2026
    # (задача 3.86) он стал знакомым, и пример пришлось заменить. Тест
    # при этом продолжал бы зеленеть на старом ключе (у записи не было
    # `"value"`, и она падала в тот же catch-all), то есть проверял бы
    # уже не то, что говорит его имя.
    test "an unknown change raises" do
      assert_raise RuntimeError, ~r/does not know how to apply/, fn ->
        apply_layer(%{"id" => "wall_of_fire", "changes" => [%{"what" => "duration"}]})
      end
    end

    # Школа читается тем же словарём, что и ванильное поле, но в отличие
    # от него нечитаемое значение здесь РОНЯЕТ сборку: ванильный файл
    # перегенерируется из кэша вики и обязан пережить новое написание
    # наверху, а этот написан руками, и опечатка в нём — опечатка в правилах.
    test "an unreadable school raises" do
      assert_raise RuntimeError, ~r/is not one of the eight schools/, fn ->
        apply_layer(%{
          "id" => "wall_of_fire",
          "changes" => [%{"what" => "school", "value" => "энчантмент"}]
        })
      end
    end

    # Школа заклинания шарда объявляется полем записи, а не правкой: править
    # нечего, пока заклинания нет. Иначе запись выглядела бы применённой,
    # а школа молча оставалась бы `nil`.
    test "a school change for a spell that does not exist raises" do
      assert_raise RuntimeError, ~r/overrides the school of a spell that does not exist/, fn ->
        apply_layer(%{
          "id" => "made_up_spell",
          "changes" => [%{"what" => "school", "value" => "evocation"}]
        })
      end
    end

    # Положительный контроль к обоим guard'ам: то же самое значение,
    # написанное как на странице Сиалы — по-русски и с английским
    # в скобках, — читается и применяется. Один словарь на оба слоя.
    test "the shard's own spelling of a school is read, not refused" do
      rulesets =
        apply_layer(%{
          "id" => "wall_of_fire",
          "changes" => [%{"what" => "school", "value" => "Зачарование (Enchantment)"}]
        })

      assert rulesets["siala_41"].spells[:wall_of_fire].school == :enchantment
      assert rulesets["vanilla"].spells[:wall_of_fire].school == :evocation
    end

    test "a class column outside `spell_lists` raises" do
      assert_raise RuntimeError, ~r/names spell list/, fn ->
        apply_layer(%{
          "id" => "wall_of_fire",
          "changes" => [%{"what" => "levels", "value" => %{"warlock" => 4}}]
        })
      end
    end

    test "a shard-only spell without a name raises" do
      assert_raise RuntimeError, ~r/has no name/, fn ->
        apply_layer(%{
          "id" => "made_up_spell",
          "changes" => [%{"what" => "levels", "value" => %{"mage" => 4}}]
        })
      end
    end

    # Задача 4.58. Переименовать можно только то, что есть: заклинание шарда
    # называет себя полем `name` записи, а правка имени у несуществующего
    # выглядела бы применённой и не делала бы ничего.
    test "a name change for a spell that does not exist raises" do
      assert_raise RuntimeError, ~r/renames a spell that does not exist/, fn ->
        apply_layer(%{
          "id" => "made_up_spell",
          "changes" => [%{"what" => "name", "value" => %{"name" => "Made up"}}]
        })
      end
    end

    test "a name change without a shown name raises" do
      for value <- [%{"ru" => "Отражение"}, "Reflection", %{"name" => ""}] do
        assert_raise RuntimeError, ~r/expected `\{"name"/, fn ->
          apply_layer(%{
            "id" => "endure_elements",
            "changes" => [%{"what" => "name", "value" => value}]
          })
        end
      end
    end

    test "an icon change without a value, or for a spell that does not exist, raises" do
      assert_raise RuntimeError, ~r/without a `value`/, fn ->
        apply_layer(%{"id" => "endure_elements", "changes" => [%{"what" => "icon"}]})
      end

      assert_raise RuntimeError, ~r/icon of a spell that does not exist/, fn ->
        apply_layer(%{
          "id" => "made_up_spell",
          "changes" => [%{"what" => "icon", "value" => nil}]
        })
      end
    end

    # Положительный контроль к трём сторожам выше: правильная правка ложится —
    # и только на Сиалу, а `ru` без имени шарда необязателен.
    test "a well-formed name and icon change is applied to Siala only" do
      rulesets =
        apply_layer(%{
          "id" => "fireball",
          "changes" => [
            %{"what" => "name", "value" => %{"name" => "Fire Ball"}},
            %{"what" => "icon", "value" => nil}
          ]
        })

      assert %{name: "Fire Ball", icon: nil} = rulesets["siala_41"].spells[:fireball]
      refute Map.has_key?(rulesets["siala_41"].spells[:fireball], :ru)
      assert %{name: "Fireball"} = rulesets["vanilla"].spells[:fireball]
      assert is_binary(rulesets["vanilla"].spells[:fireball].icon)
    end
  end

  # The guards run against a copy of `priv/rules` with one file replaced — the
  # same shape `ClassChangeReceiversTest` uses for its own watchdog, and for the
  # same reason: the question is how the loader reads a file, not what today's
  # file happens to contain.
  defp apply_layer(entry) do
    root = BuildCalculator.TmpDir.unique_path!("spell-layer-")
    File.mkdir_p!(root)
    on_exit_rm(root)
    File.cp_r!("priv/rules", root)

    File.write!(
      Path.join(root, "siala_41/spells.json"),
      Jason.encode!(%{"spells" => [entry]})
    )

    BuildCalculator.Data.Loader.load!(root)
  end

  defp on_exit_rm(path) do
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(path) end)
  end
end
