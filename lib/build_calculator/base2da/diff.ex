defmodule BuildCalculator.Base2da.Diff do
  @moduledoc """
  Сверка базовых `.2da` NWN:EE с ванильным ruleset'ом — `mix base2da.diff`
  (задача 4.5).

  Собирает контекст (таблицы, сопоставления id, выдачи классов, замыкания
  требований), прогоняет сравнения по областям (`CompareClasses`,
  `CompareFeats`, `CompareOther`) и классифицирует находки
  (`Classification`). Результат — список областей с числом сравнений
  и находками; печатает его `Report`.

  ⚠ Сверка **ничего не правит**. Её вывод — вход для задач на правку данных
  (4.6, 4.7 и новых), а не правка.
  """

  alias BuildCalculator.Base2da.{
    Classification,
    CompareClasses,
    CompareFeats,
    CompareOther,
    Ids,
    Source,
    Tally
  }

  alias BuildCalculator.GameFiles.TwoDA

  @doc """
  Прогоняет сверку: таблицы `source`, загруженный ruleset и каталог правил
  `rules_dir`.

  Ключи `opts` (задача 4.49 — та же сверка для Сиалы):

    * `:classify` — функция «находка → находка с видом»; по умолчанию ванильная
      `Classification.classify/1`;
    * `:row_overrides` — явные строки таблиц без имени в словаре,
      `%{"feat" => %{строка => %{label:, id:, name:, group:}}, "skills" => …}`
      (`Base2da.Ids`, moduledoc).

  Бонусный слот класса по значению выбора (`CompareClasses`, область
  `class_bonus_values`) с задачи 4.50 сверяется у обеих; ключа
  `:bonus_values`, который до неё выключал его у ванили, больше нет.
  """
  @spec run(Source.t(), map(), Path.t(), keyword()) :: %{areas: [Tally.t()]}
  def run(source, ruleset, rules_dir, opts \\ []) do
    ctx = context(source, ruleset, rules_dir, opts)
    classify = Keyword.get(opts, :classify, &Classification.classify/1)

    areas =
      (CompareClasses.run(ctx) ++ CompareFeats.run(ctx) ++ CompareOther.run(ctx))
      |> Enum.map(fn tally ->
        %{tally | findings: Enum.map(tally.findings, classify)}
      end)

    %{areas: areas}
  end

  @doc false
  def context(source, ruleset, rules_dir, opts \\ []) do
    overrides = Keyword.get(opts, :row_overrides, %{})
    feat_overrides = Map.get(overrides, "feat", %{})
    classes = Source.table(source, "classes")
    feat = Source.table(source, "feat")
    {class_rows, unmapped_classes} = Ids.classes(source, ruleset)
    {race_rows, unmapped_races} = Ids.races(source, ruleset)
    {feat_rows, unmapped_feat_rows} = Ids.feats(source, ruleset, feat_overrides)
    families = Ids.families(feat_rows)

    feat_name = fn row ->
      case feat_overrides[row] do
        %{name: name} -> name
        nil -> Source.row_name(source, "feat", row, "FEAT")
      end
    end

    class_lists = class_lists(source, classes, class_rows, feat_rows, feat_name)

    ctx = %{
      source: source,
      ruleset: ruleset,
      classes: classes,
      feat: feat,
      constants: constants(source),
      class_rows: class_rows,
      class_by_row: Map.new(class_rows, fn {id, row} -> {row, id} end),
      unmapped_classes: unmapped_classes,
      race_rows: race_rows,
      race_by_row: Map.new(race_rows, fn {id, row} -> {row, id} end),
      unmapped_races: unmapped_races,
      skill_rows: Ids.skills(source, ruleset, Map.get(overrides, "skills", %{})),
      feat_rows: feat_rows,
      unmapped_feat_rows: unmapped_feat_rows,
      # Группа строки без нашего id, названная явной таблицей сверки (у Сиалы —
      # «Дух Сиалы», строка 754): без неё строка ушла бы в группу по метке.
      unmapped_groups: for({row, %{group: group}} <- feat_overrides, into: %{}, do: {row, group}),
      feat_name: feat_name,
      families: families,
      class_lists: class_lists.lists,
      grants: class_lists.grants,
      unmapped_grants: class_lists.unmapped,
      spell_rows: Ids.spells(source, ruleset, Map.get(overrides, "spells", %{})),
      # Явные строки заклинаний (у Сиалы — 50 и 191, `SialaRows`): у них имя
      # нашей записи сверяется с меткой строки (`CompareOther`, задача 4.58).
      spell_overrides: Map.get(overrides, "spells", %{}),
      weapon_rows: Ids.weapons(source, ruleset),
      domain_rows: Ids.domains(source),
      school_rows: Ids.schools(source),
      raw_weapons: read_json(rules_dir, "vanilla/weapons.json")["weapons"],
      raw_spells: read_json(rules_dir, "vanilla/spells.json"),
      raw_epic: read_json(rules_dir, "vanilla/epic.json")
    }

    ctx
    |> Map.put(:row_label, &row_label(ctx, &1))
    |> Map.put(:choice_of_row, &choice_of_row(ctx, &1))
    |> Map.put(:feat_closure, closure_fun(ctx))
    |> Map.put(:our_closure, our_closure_fun(ruleset))
  end

  # cls_feat_* каждого класса: что перечислено (List, GrantedOnLevel) по нашим
  # id, кому что выдаётся по строкам feat.2da, и выдачи, не сопоставленные ни
  # с одним нашим id (маркеры «Epic Fighter» и т. п.).
  defp class_lists(source, classes, class_rows, feat_rows, feat_name) do
    Enum.reduce(class_rows, %{lists: %{}, grants: %{}, unmapped: %{}}, fn {id, row}, acc ->
      table = Source.table(source, TwoDA.get(classes, row, "FeatsTable"))

      Enum.reduce(TwoDA.rows(table), put_in(acc, [:lists, id], %{}), fn {_i, r}, acc ->
        feat_row = TwoDA.to_int(r["FeatIndex"])
        list = TwoDA.to_int(r["List"])
        level = TwoDA.to_int(r["GrantedOnLevel"]) || -1
        feat = feat_rows[feat_row]

        acc =
          if list == 3 and level > 0,
            do:
              update_in(
                acc,
                [:grants],
                &Map.update(&1, feat_row, [{id, level}], fn l -> l ++ [{id, level}] end)
              ),
            else: acc

        cond do
          feat ->
            update_in(
              acc,
              [:lists, id],
              &Map.update(&1, feat, [{list, level}], fn l -> l ++ [{list, level}] end)
            )

          list == 3 and level > 0 ->
            name = feat_name.(feat_row)
            label = TwoDA.get(Source.table(source, "feat"), feat_row, "LABEL")

            update_in(
              acc,
              [:unmapped],
              &Map.update(&1, id, [{level, label, name, feat_row}], fn l ->
                l ++ [{level, label, name, feat_row}]
              end)
            )

          true ->
            acc
        end
      end)
    end)
  end

  defp constants(source) do
    for {_i, row} <- TwoDA.rows(Source.table(source, "ruleset")),
        label = row["Label"],
        label != nil,
        n = TwoDA.to_int(row["Value"]),
        is_integer(n),
        into: %{},
        do: {label, n}
  end

  defp row_label(ctx, row) do
    name = ctx.feat_name.(row)
    "#{name || TwoDA.get(ctx.feat, row, "LABEL")} [feat.2da:#{row}]"
  end

  # Значение выбора строки семейства по её имени: «Weapon Focus (short sword)» →
  # :shortsword (наш id оружия).
  defp choice_of_row(ctx, row) do
    name = ctx.feat_name.(row) || ""

    case Regex.run(~r/\(([^)]+)\)\s*$/, name) do
      [_, value] ->
        n = Ids.norm(value)
        weapons = Map.keys(ctx.ruleset.weapons)

        Enum.find(weapons, &(Atom.to_string(&1) == n)) ||
          Enum.find(
            weapons,
            &(String.replace(Atom.to_string(&1), "_", "") == String.replace(n, "_", ""))
          ) ||
          value

      _ ->
        name
    end
  end

  # Замыкание требований .2da по семействам: всё, что семейство требует через
  # PREREQFEAT, транзитивно.
  defp closure_fun(ctx) do
    direct =
      Map.new(ctx.families, fn {family, rows} ->
        feats =
          for row <- rows,
              column <- ~w(PREREQFEAT1 PREREQFEAT2),
              r = TwoDA.int(ctx.feat, row, column),
              is_integer(r),
              f = ctx.feat_rows[r],
              f != nil and f != family,
              into: MapSet.new(),
              do: f

        {family, feats}
      end)

    fn family -> transitive(direct, family) end
  end

  defp our_closure_fun(ruleset) do
    direct =
      Map.new(ruleset.feats, fn {id, feat} ->
        feats = (feat.prereqs || %{})["feats"] || []
        {id, MapSet.new(feats, &String.to_existing_atom/1)}
      end)

    fn family -> transitive(direct, family) end
  end

  defp transitive(direct, start) do
    walk([start], direct, MapSet.new()) |> MapSet.delete(start)
  end

  defp walk([], _direct, seen), do: seen

  defp walk([head | rest], direct, seen) do
    next = Map.get(direct, head, MapSet.new()) |> Enum.reject(&MapSet.member?(seen, &1))
    walk(rest ++ next, direct, MapSet.union(seen, MapSet.new(next)))
  end

  defp read_json(dir, rel), do: dir |> Path.join(rel) |> File.read!() |> Jason.decode!()
end
