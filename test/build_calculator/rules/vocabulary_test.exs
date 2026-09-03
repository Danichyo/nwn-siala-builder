defmodule BuildCalculator.Rules.VocabularyTest do
  @moduledoc """
  Keeps `BuildCalculator.Rules.Vocabulary` level with the core.

  The registry exists so the web layer can prove every tuple has Russian
  wording. A registry that silently falls behind is worse than none — it turns a
  green wording test into a promise nobody is keeping. So it is checked from both
  ends:

    * **from the source** — every tuple literal in the rules core and the data
      loader whose head is a gap family or a `requires_*` refusal;
    * **from a run** — every gap and every refusal a corpus of builds actually
      produces, with every class and every feat validated against it.

  Neither alone is enough. A form nothing reaches yet is invisible to the run; a
  form assembled out of a variable (`{:not_modelled, {modifier.kind, class}}`) is
  invisible to the scan. Together they leave very little room, and the third test
  closes the loop the other way: a registered form that neither the source nor a
  run produces is fiction, and fiction in this list is how it starts rotting.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear, Vocabulary}

  # The registry itself is left out on purpose: its entries are tuple literals
  # with vocabulary heads, so counting them would have the list vouch for itself
  # and the fiction test would pass on anything.
  # ⚠️ Загрузчик — это ЧЕТЫРНАДЦАТЬ файлов с задачи 3.46 (заход 1 разрезал один
  # модуль на 9662 строки, заход 3 отделил от классов ещё два), и подстановочник
  # здесь обязателен: формы гэпов лежат в `loader/gaps.ex`, `loader/spells.ex`
  # и соседях, а не в фасаде. Список путей был единственным местом во всём
  # репозитории, которое заметило перенос, — и заметило падением, а не молчанием.
  @sources ["lib/build_calculator/rules.ex", "lib/build_calculator/data/loader.ex"] ++
             Path.wildcard("lib/build_calculator/data/loader/*.ex") ++
             (Path.wildcard("lib/build_calculator/rules/*.ex") --
                ["lib/build_calculator/rules/vocabulary.ex"])

  setup_all do
    %{
      known: Vocabulary.forms(Vocabulary.gaps() ++ Vocabulary.reasons()),
      in_source: source_forms(),
      observed: observed_forms()
    }
  end

  test "every tuple form the core writes down is registered", context do
    # A head built out of a variable reads as `:_` and cannot be judged
    # statically; the run below is what covers those.
    missing =
      for {form, path} <- context.in_source,
          :_ not in form,
          not MapSet.member?(context.known, form),
          uniq: true,
          do: {form, path}

    assert missing == [],
           """
           These forms are produced by the core and not registered in
           `BuildCalculator.Rules.Vocabulary`. Add an example of each: the web layer
           walks that list to prove every tuple has Russian wording, and a form
           missing from it renders through `inspect/1` where nobody looks.

           #{Enum.map_join(missing, "\n", fn {form, path} -> "  #{inspect(form)}  (#{path})" end)}
           """
  end

  test "every form an actual run produces is registered", context do
    missing =
      for {form, example} <- context.observed,
          not MapSet.member?(context.known, form),
          uniq: true,
          do: {form, example}

    assert missing == [],
           """
           A run of the core produced these and the registry does not know them:

           #{Enum.map_join(missing, "\n", fn {form, example} -> "  #{inspect(form)}  e.g. #{inspect(example)}" end)}
           """
  end

  test "no registered form is fiction", context do
    real =
      MapSet.union(
        MapSet.new(context.in_source, &elem(&1, 0)),
        MapSet.new(context.observed, &elem(&1, 0))
      )

    dead = for form <- context.known, not MapSet.member?(real, form), do: form

    assert dead == [],
           """
           Registered, but neither written anywhere in the core nor produced by a
           run — either it was renamed and the entry was left behind, or the rule
           it belonged to is gone. A list that is partly fiction teaches people to
           skim it.

           #{inspect(dead, pretty: true)}
           """
  end

  describe "form/1" do
    test "a gap is its head and its subject, a refusal is its head alone" do
      assert Vocabulary.form({:missing_data, {:hit_die, :monk}}) == [:missing_data, :hit_die]
      assert Vocabulary.form({:missing_data, :max_classes}) == [:missing_data, :max_classes]
      assert Vocabulary.form({:assumed, :base_ac, 10}) == [:assumed, :base_ac]
      assert Vocabulary.form({:requires_class_level, :bard, 1}) == [:requires_class_level]
      assert Vocabulary.form({:missing_file, "vanilla/skills.json"}) == [:missing_file, :_]
    end

    test "ids inside a gap do not multiply its form" do
      assert Vocabulary.form({:missing_data, {:hit_die, :monk}}) ==
               Vocabulary.form({:missing_data, {:hit_die, :rogue}})

      refute Vocabulary.form({:missing_data, {:hit_die, :monk}}) ==
               Vocabulary.form({:missing_data, {:stat_cap, :ac}})
    end
  end

  # ------------------------------------------------------------------- a run --

  defp observed_forms do
    ruleset = Data.ruleset!()
    builds = corpus(ruleset)

    data_gaps = for version <- Data.versions(), gap <- Data.ruleset!(version).gaps, do: gap
    build_gaps = for build <- builds, gap <- Rules.compute(build, ruleset).gaps, do: gap

    # 🔴 Гэпы билда снимаются со ВСЕХ ruleset'ов с задачи 3.107, а не с одного
    # умолчательного, и это не педантизм. Гэпы ДАННЫХ строкой выше так и
    # снимались всегда; гэпы БИЛДА — нет, и форма могла жить только у ванили,
    # оставаясь для теста вымыслом. Ровно это и случилось: 3.107 выразила
    # последнюю оговорку Сиалы требованием, и `{:not_modelled,
    # {:class_qualifier, …}}` на `siala_41` потеряла всех носителей, хотя
    # у ванили их двое — `arcane_archer` и `purple_dragon_knight`.
    #
    # ⚠ Корпус строится ДЛЯ КАЖДОГО ruleset'а заново: он ссылается на
    # `ruleset.version` и на фит, найденный обходом того же справочника, —
    # общий корпус означал бы билд с версией одного ruleset'а, посчитанный
    # по другому.
    other_gaps =
      for version <- Data.versions(),
          version != ruleset.version,
          other = Data.ruleset!(version),
          build <- corpus(other),
          gap <- Rules.compute(build, other).gaps,
          do: gap

    # An empty build fails nearly every prestige class and most feats, which is
    # how one sweep reaches nearly every refusal there is; a finished one reaches
    # the rest (a class level cap, the class limit).
    refusals =
      for build <- [Build.new(ruleset_version: ruleset.version), Enum.at(builds, 1)],
          reason <- refusals_for(build, ruleset),
          do: reason

    for tuple <- data_gaps ++ build_gaps ++ other_gaps ++ refusals,
        uniq: true,
        do: {Vocabulary.form(tuple), tuple}
  end

  defp refusals_for(build, ruleset) do
    classes =
      Enum.flat_map(ruleset.classes, fn {id, _} ->
        case Rules.validate_level_up(build, id, ruleset) do
          :ok -> []
          {:error, reasons} -> List.flatten(reasons)
        end
      end)

    feats =
      Enum.flat_map(ruleset.feats, fn {id, _} ->
        case Rules.validate_feat(build, id, ruleset) do
          :ok -> []
          {:error, reasons} -> List.flatten(reasons)
        end
      end)

    classes ++ feats
  end

  # Builds picked to trip as many build-scoped gaps as one pass can: classes the
  # shard rewrote, a fourth class for the stealth penalty, ranks in a skill with
  # no key ability, a feat that changes the attack formula, a feat whose
  # requirement carries a qualifier, and gear so the cascade engages.
  defp corpus(ruleset) do
    [
      Build.new(ruleset_version: ruleset.version),
      Build.new(
        ruleset_version: ruleset.version,
        race: :half_elf,
        alignment: :true_neutral,
        levels:
          List.duplicate(:rogue, 10) ++
            List.duplicate(:shadowdancer, 4) ++
            List.duplicate(:fighter, 3) ++ List.duplicate(:harper_scout, 3),
        base_abilities: %{str: 14, dex: 16, con: 14, int: 14, wis: 10, cha: 10},
        # Alchemy is bought one rank over the cross-class ceiling, on purpose:
        # the `{:skill_over_cap, …}` refusal off a skill that is not the usual
        # suspect. ⚠ It used to earn a second entry here — no key ability on any
        # wiki — and that half is gone since Dan's 17.08.2026 measurement (P1)
        # named one; the form itself stays registered and is exercised on a
        # ruleset with the field taken out (`Rules.SkillsTest`).
        skills: %{1 => %{alchemy: 3, hide: 4}, 20 => %{spellcraft: 10}},
        feats: %{1 => %{general: :weapon_finesse}, 3 => %{general: :toughness}},
        gear: Gear.new(abilities: %{con: 12, int: 12}, ac: %{armor: 8}, saves: 15)
      ),
      Build.new(
        ruleset_version: ruleset.version,
        race: :dwarf,
        alignment: :lawful_good,
        levels: List.duplicate(:fighter, 10) ++ List.duplicate(:weapon_master, 20),
        base_abilities: %{str: 16, dex: 14, con: 16, int: 10, wis: 10, cha: 8},
        # ⚠️ Уровень 21, а не 1: с задачи 3.99 все оставшиеся фиты с оговоркой
        # эпические, а `feats_taken/2` читает слоты по уровням билда.
        feats: %{21 => %{general: qualified_feat(ruleset)}}
      ),
      Build.new(
        ruleset_version: ruleset.version,
        race: :half_elf,
        levels: List.duplicate(:red_dragon_disciple, 5) ++ List.duplicate(:arcane_archer, 10)
      ),
      # 🔴 Пятый — ради формы, которую не видит СТАТИЧЕСКИЙ обход (задача
      # 3.132): голова гэпа выдачи Рейнджера собирается из данных
      # (`condition.gap`), то есть в исходнике её литералом нет.
      #
      # Три вещи в одном билде, и каждая нужна: рейнджер (класс сам выдаёт
      # `Dual-wield` на 1-м уровне), ДВА оружия в руках (без второй руки штрафа
      # стиля нет вовсе) и ЗАПИСАННЫЙ доспех (без него условие «wearing medium
      # or heavy armor» не выполняется по факту, и оговорка не печатается —
      # см. `Rules.DualWield`).
      #
      # 🔴 И с задачи 3.141 форму даёт ровно ОДИН из двух ruleset'ов — ванильный,
      # через обход `other_gaps` выше. На `siala_41` класс брони измерен
      # (`GAME_CHECKS.md` AH1), ответ есть, и оговорки там не осталось ни на
      # одном билде; у ванили границу не выяснял никто, и она печатается на
      # каждом доспехе. То есть носитель у формы живой, но чужой — ровно тот
      # случай, ради которого 3.107 расширила обход на все версии.
      #
      # ⚠️ Оружие выбрано так, чтобы не зависеть от ruleset'а: дубина и
      # рукопашный удар не требуют владения ни у ванили (там его не читал никто),
      # ни у Сиалы (замер Dan 16.08.2026). Рукопашный удар заодно даёт
      # `{:missing_data, {:light_weapon, …}}`: размера у него нет, и сказать
      # про лёгкость нечем.
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: [:ranger],
        base_abilities: %{str: 14, dex: 16, con: 14, int: 10, wis: 12, cha: 10},
        gear:
          Gear.new(
            weapon: :club,
            off_hand_weapon: :unarmed_strike,
            worn: %{armor: :chainmail}
          )
      )
    ]
  end

  # Some feat whose requirement block carries a refinement the schema cannot
  # express — the `{:not_modelled, {:feat_qualifier, …}}` case. Looked up rather
  # than named, because which feats have one is the parser's business and it
  # changes; if none does any more, the form stops being produced and the
  # fiction test says so, which is the correct outcome.
  # ⚠️ Здесь стояло `not feat.epic?`, и после задачи 3.99 такого фита не осталось
  # ни одного: `Weapon focus` и `Improved critical` получили проверяемое
  # требование владения, `Improved ki strike 4` — уровень класса вместо ступени,
  # а три оружейно-школьных молчат там, где `same_choice_as` их сравнивает.
  # Отбор эпических остался бы пустым и уронил бы «fiction» — что и произошло.
  # Обход отсортирован, чтобы выбор не зависел от порядка обхода карты.
  defp qualified_feat(ruleset) do
    ruleset.feats
    |> Map.keys()
    |> Enum.sort()
    |> Enum.find(:toughness, fn id -> Rules.feat_caveats(id, ruleset) != [] end)
  end

  # --------------------------------------------------------- the source scan --

  defp source_forms do
    for path <- @sources, form <- literal_forms(path), uniq: true, do: {form, path}
  end

  # Tuple literals, as written. `{a, b}` is a two-tuple in the AST as it stands;
  # every other arity arrives as `{:{}, meta, elements}`. A variable is a
  # three-tuple whose head is its name, so it can never be mistaken for either.
  defp literal_forms(path) do
    {_ast, found} =
      path
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn node, acc ->
        case vocabulary_form(node) do
          nil -> {node, acc}
          form -> {node, [form | acc]}
        end
      end)

    found
  end

  defp vocabulary_form(node) do
    with {:ok, [head | _] = elements} <- tuple_elements(node),
         true <- is_atom(head) and vocabulary_head?(head) do
      Vocabulary.form(List.to_tuple(Enum.map(elements, &literal/1)))
    else
      _ -> nil
    end
  end

  # A head the registry already knows, or a refusal named by the convention every
  # one of them follows. ⚠ A brand-new head that is neither is invisible to the
  # scan — the run is what catches that, and inventing a *family* is a bigger
  # event than adding a form to one.
  defp vocabulary_head?(head) do
    head in Vocabulary.heads() or String.starts_with?(Atom.to_string(head), "requires_")
  end

  defp tuple_elements({:{}, meta, elements}) when is_list(meta) and is_list(elements),
    do: {:ok, elements}

  defp tuple_elements({left, right}), do: {:ok, [left, right]}
  defp tuple_elements(_node), do: :error

  # An atom stays itself; a nested tuple keeps its head, so the subject of a gap
  # survives. Anything else is a value and collapses to `:_`.
  defp literal(atom) when is_atom(atom), do: atom

  defp literal(node) do
    case tuple_elements(node) do
      {:ok, [head | _]} when is_atom(head) -> {head}
      _ -> :_
    end
  end
end
