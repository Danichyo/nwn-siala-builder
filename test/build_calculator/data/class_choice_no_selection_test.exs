defmodule BuildCalculator.Data.ClassChoiceNoSelectionTest do
  @moduledoc """
  `priv/rules/vanilla/class_choice_no_selection.json` — the word the game
  CLIENT prints for "this class's own one-time choice, left unmade" (task
  3.170, AGENT_QUEUE.md).

  Today this is exactly one fact: a Wizard who never picked a school is shown
  the choice named `General`, not left silent. `class_choices.json` right
  next to this file already got the *mechanic* correct (`required?: false`,
  so an unmade choice is legal and complete) — this file only supplies the
  word for that already-correct state, out of a screenshot rather than a
  wiki page, and deliberately apart from both `class_choices.json` (the
  mechanic decision it must not disturb) and `spell_schools.json`
  (`universal`'s own name, on the machine layer `mix wiki.parse` rewrites
  whole).

  Half of what is pinned here is the same lesson `class_requirements_test.exs`
  already paid for: a hand file only helps if it is actually read (registered
  by name, not merely by directory, and not mistaken for a choice-values
  dictionary) — and half is its guard against a false legality reachable by
  editing data alone: naming a class whose choice is `required?: true`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules.ClassChoices

  @path "vanilla/class_choice_no_selection.json"

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  describe "the file is wired in" do
    test "registered by name, not merely by its directory" do
      assert @path in Loader.source_files()
    end

    # Its entries are keyed by CLASS id, same pitfall `class_choices.json`'s
    # own note describes: an unclaimed `vanilla/*.json` would offer `wizard`
    # as a pickable *value* of a domain called `class_choice_no_selection`.
    test "is not mistaken for a choice domain", %{siala: siala} do
      refute Map.has_key?(siala.choice_domains, :class_choice_no_selection)

      # Positive control: the mechanism it is being kept out of is alive.
      assert Map.has_key?(siala.choice_domains, :creature_type)
    end

    # Wizard specialization is a vanilla mechanic Siala's own wiki never
    # mentions (`class_choices.json`'s own `siala.note`), so both rulesets
    # inherit the exact same word.
    test "both rulesets carry the reading — a Wizard's General", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala] do
        assert ClassChoices.no_selection_name(:wizard, ruleset) == "General"
      end
    end

    # Positive control on the guard, not just on the happy path: a Cleric's
    # choice is required?: true, and this file names nobody but the Wizard —
    # if it ever silently named the Cleric too, the button task 3.170 built
    # would offer "no domains" as a legitimate final state, which
    # `Rules.ClassChoices.complete?/3` would rightly refuse.
    test "a class outside this file has no word for it", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        assert ClassChoices.no_selection_name(:cleric, ruleset) == nil
        assert ClassChoices.no_selection_name(:fighter, ruleset) == nil
      end
    end
  end

  describe "the file missing degrades to no word at all, not a crash" do
    test "no word for the Wizard, and the rest of class_choices.json still loads" do
      ruleset = load_without_file()

      assert ClassChoices.no_selection_name(:wizard, ruleset) == nil
      # `class_choices.json` itself is untouched by this file's absence — the
      # mechanic this file only labels keeps working.
      assert ClassChoices.required?(:wizard, ruleset) == false
      assert {:ok, values} = ClassChoices.values(:wizard, ruleset)
      assert length(values) == 8
    end
  end

  describe "the guard against a false legality reachable by editing data alone" do
    # A class this file has never heard of before — `build_class_choices/2`
    # itself would have to name it first.
    test "a class with no class_choices.json entry at all raises" do
      root = copy_rules()

      edit_entry(root, "wizard", fn entry -> %{entry | "id" => "fighter"} end)

      assert_raise RuntimeError, ~r/has no class_choices\.json entry/, fn ->
        Loader.load!(root)
      end
    end

    # The guard this file exists to enforce: naming a REQUIRED choice would
    # let a button say "nothing chosen is fine" about a state
    # `ClassChoices.complete?/3` calls illegal.
    test "a class whose own choice is required raises" do
      root = copy_rules()

      edit_entry(root, "wizard", fn entry -> %{entry | "id" => "cleric"} end)

      assert_raise RuntimeError, ~r/required\? true/, fn -> Loader.load!(root) end
    end

    test "an entry with no name raises" do
      root = copy_rules()

      edit_entry(root, "wizard", fn entry -> Map.delete(entry, "name") end)

      assert_raise RuntimeError, ~r/names no name/, fn -> Loader.load!(root) end
    end

    # 🔴 Найдено координатором при приёмке 3.170, а не самой задачей: кнопка
    # `#class-choice-none` очищает выбор, отдавая ОДНО значение обратно
    # в `toggle_class_choice` (`List.first(chosen)`), то есть опустошает
    # только `count: 1`. Класс, которому позволено пропустить выбор ИЗ ДВУХ
    # значений, получил бы кнопку, снимающую половину и после этого
    # рисующую себя выбранной, — экран утверждал бы неправду. Сегодня такого
    # класса нет, и сборка обязана остановиться в день, когда он появится,
    # а не выпустить полу-очистку молча.
    test "класс, которому можно пропустить выбор ИЗ ДВУХ значений, роняет сборку" do
      root = copy_rules()
      path = Path.join(root, "vanilla/class_choices.json")
      data = path |> File.read!() |> Jason.decode!()

      classes =
        Enum.map(data["classes"], fn entry ->
          if entry["id"] == "wizard", do: Map.put(entry, "count", 2), else: entry
        end)

      File.write!(path, Jason.encode!(%{data | "classes" => classes}))

      assert_raise RuntimeError, ~r/clears one value at a time/, fn -> Loader.load!(root) end
    end
  end

  defp copy_rules do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp load_without_file do
    root = copy_rules()
    File.rm!(Path.join(root, @path))
    Loader.load!(root)["siala_41"]
  end

  defp edit_entry(root, id, fun) do
    path = Path.join(root, @path)
    data = path |> File.read!() |> Jason.decode!()

    entries =
      Enum.map(data["classes"], fn entry ->
        if entry["id"] == id, do: fun.(entry), else: entry
      end)

    File.write!(path, Jason.encode!(%{data | "classes" => entries}))
  end
end
