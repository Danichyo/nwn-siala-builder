defmodule BuildCalculator.Base2da.Ids do
  @moduledoc """
  Сопоставление строк базовых `.2da` с нашими id (задача 4.5).

  🔴 **Сопоставляем по имени, которое печатает игра** (`dialog.tlk`), а не по колонке
  `Constant` или `LABEL`: наши id выведены из заголовков страниц Fandom, а те
  повторяют игровые имена. `Constant` не угадывается по шаблону у каждого
  десятого фита (`FEAT_PDK_RALLY`, `HARPER_SLEEP`) — ровно на этом споткнулась
  ручная сверка хаков 3.126.

  Имя нормализуется так же, как id: нижний регистр, апостроф выбрасывается,
  всё прочее не буквенно-цифровое — `_`. Семейства фитов (ступени и выборы)
  сворачиваются в один наш id снятием хвоста: `(longsword)`, `: Dwarves`,
  римская цифра, `+3`, число. Одиннадцать строк, чьё имя не похоже на имя
  семейства («Greater Rage» — ступень `barbarian_rage`), названы ниже поимённо.
  Что не сопоставилось — не выдумывается, а уходит в отчёт списком.

  ## Строки без имени в словаре — явная таблица сверки (задача 4.49)

  У хака шарда часть имён — из его собственного `.tlk`, которого в выгрузке нет
  (`Base2da.Source`, moduledoc). Строку, которой нет и в базовой таблице
  (кастомные фиты Сиалы 2001–2027, навык Алхимии), сопоставляет только явная
  таблица `row_overrides` у сверки: `%{строка => %{label:, id:, name:}}`.
  Метка проверяется — шард сдвинул строку, и сверка падает, а не сопоставляет
  чужую строку; `id: nil` — строка намеренно без нашего id (у Сиалы строка 754:
  «Дух Сиалы», в хаке подписанный `FEAT_EPIC_TOUGHNESS_1`, решение Dan 4.52).
  """

  alias BuildCalculator.Base2da.Source
  alias BuildCalculator.GameFiles.TwoDA

  # Ступени семейств, чьё имя в игре не похоже на имя семейства.
  @feat_labels %{
    "BarbarianRage5" => :barbarian_rage,
    "BarbarianRage6" => :barbarian_rage,
    "BarbarianRage7" => :barbarian_rage,
    "ElementalShape4" => :elemental_shape,
    "FEAT_EPIC_SHIFTER_INFINITE_HUMANOID_SHAPE" => :infinite_greater_wildshape,
    "DamageReduction" => :damage_reduction_barbarian,
    "DamageReduction2" => :damage_reduction_barbarian,
    "DamageReduction3" => :damage_reduction_barbarian,
    "DamageReduction4" => :damage_reduction_barbarian,
    "RangerDual" => :dual_wield_feat
  }

  # Заклинания, чьё имя в игре не похоже на заголовок страницы Fandom.
  @spell_labels %{
    "Restoration_Others" => :restoration_others,
    "SHADOW_CON_Summon_Shadow" => :summon_shadow_shadow_conjuration
  }

  @roman ~r/\s+(?:I|II|III|IV|V|VI|VII|VIII|IX|X|XI|XII|XIII|XIV|XV|XVI|XVII|XVIII|XIX|XX)\+?$/

  @doc "Имя → вид нашего id."
  @spec norm(String.t()) :: String.t()
  def norm(name) do
    name
    |> String.downcase()
    |> String.replace(["'", "’"], "")
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  @doc "Играбельные классы: `%{class_id => строка classes.2da}` и несопоставленные строки."
  @spec classes(Source.t(), map()) :: {%{atom() => non_neg_integer()}, [String.t()]}
  def classes(source, ruleset) do
    playable(source, ruleset.classes, "classes", "PlayerClass")
  end

  @doc "Играбельные расы: `%{race_id => строка racialtypes.2da}` и несопоставленные."
  @spec races(Source.t(), map()) :: {%{atom() => non_neg_integer()}, [String.t()]}
  def races(source, ruleset) do
    playable(source, ruleset.races, "racialtypes", "PlayerRace")
  end

  defp playable(source, ours, table_name, flag) do
    table = Source.table(source, table_name)
    ids = id_index(ours)

    Enum.reduce(TwoDA.rows(table), {%{}, []}, fn {index, row}, {found, missing} ->
      name = Source.row_name(source, table_name, index, "Name")

      cond do
        row[flag] != "1" -> {found, missing}
        id = name && Map.get(ids, norm(name)) -> {Map.put(found, id, index), missing}
        true -> {found, missing ++ ["#{table_name}.2da:#{index} #{row["Label"]} (#{name})"]}
      end
    end)
  end

  @doc "Навыки: `%{строка skills.2da => skill_id}`."
  @spec skills(Source.t(), map(), map()) :: %{non_neg_integer() => atom()}
  def skills(source, ruleset, overrides \\ %{}) do
    ids = id_index(ruleset.skills)
    table = Source.table(source, "skills")

    for {index, _row} <- TwoDA.rows(table),
        id = overridden(table, index, overrides, "skills") || by_skill_name(source, index, ids),
        id not in [nil, :none],
        into: %{},
        do: {index, id}
  end

  defp by_skill_name(source, index, ids) do
    case Source.row_name(source, "skills", index, "Name") do
      nil -> nil
      name -> first_id(ids, [norm(name), norm(name) <> "_skill"])
    end
  end

  # Явная строка таблицы сверки: id (или `:none` — намеренно без id), если строка
  # названа; `nil`, если нет. Метка сверяется — иначе шард сдвинул строку.
  defp overridden(table, index, overrides, table_name) do
    case Map.get(overrides, index) do
      nil ->
        nil

      %{label: label} = entry ->
        actual = Enum.find_value(~w(LABEL Label label), &TwoDA.get(table, index, &1))

        if actual != label do
          raise "#{table_name}.2da:#{index} — ждали метку #{inspect(label)}, в таблице " <>
                  "#{inspect(actual)}: шард сдвинул строку, перепроверь row_overrides"
        end

        entry.id || :none
    end
  end

  @doc """
  Фиты: `%{строка feat.2da => feat_id}` для сопоставленных строк. Несопоставленные
  строки с именем — вторым элементом, для отчёта.
  """
  @spec feats(Source.t(), map(), map()) ::
          {%{non_neg_integer() => atom()}, [{non_neg_integer(), String.t()}]}
  def feats(source, ruleset, overrides \\ %{}) do
    ids = id_index(ruleset.feats)
    by_name = name_index(ruleset.feats)
    table = Source.table(source, "feat")

    TwoDA.rows(table)
    |> Enum.reduce({%{}, []}, fn {index, row}, {found, missing} ->
      case overridden(table, index, overrides, "feat") do
        :none ->
          {found, [{index, overrides[index].name} | missing]}

        nil ->
          name = Source.row_name(source, "feat", index, "FEAT")

          case feat_id(row["LABEL"], name, ids, by_name) do
            nil when is_binary(name) -> {found, [{index, name} | missing]}
            nil -> {found, missing}
            id -> {Map.put(found, index, id), missing}
          end

        id ->
          unless Map.has_key?(ruleset.feats, id) do
            raise "row_overrides: feat.2da:#{index} → #{inspect(id)}, такого фита в ruleset нет"
          end

          {Map.put(found, index, id), missing}
      end
    end)
    |> then(fn {found, missing} -> {found, Enum.reverse(missing)} end)
  end

  defp feat_id(label, name, ids, by_name) do
    cond do
      Map.has_key?(@feat_labels, label) and Map.has_key?(ids, Atom.to_string(@feat_labels[label])) ->
        @feat_labels[label]

      is_nil(name) ->
        nil

      String.starts_with?(name, "Energy Resistance, ") ->
        Map.get(ids, "epic_energy_resistance")

      Regex.match?(~r/^Resist \w+ Energy$/, name) ->
        Map.get(ids, "resist_energy")

      String.starts_with?(name, "DM Tool") ->
        Map.get(ids, "dm_tool")

      String.starts_with?(name, "Player Tool") ->
        Map.get(ids, "player_tool")

      true ->
        name
        |> feat_candidates()
        |> Enum.find_value(fn candidate ->
          n = norm(candidate)
          first_id(ids, [n, n <> "_feat"]) || Map.get(by_name, n)
        end)
    end
  end

  defp feat_candidates(name) do
    base = String.replace(name, ~r/\s*\(.*\)\s*$/, "")

    Enum.uniq(
      [name, base] ++
        Enum.flat_map([name, base], fn x ->
          [
            String.replace(x, @roman, ""),
            String.replace(x, ~r/\s*\+\d+$/, ""),
            String.replace(x, ~r/\s+\d+$/, ""),
            String.replace(x, ~r/:.*$/, "")
          ]
        end)
    )
  end

  @doc "Семейства: `%{feat_id => [строки feat.2da по возрастанию]}`."
  @spec families(%{non_neg_integer() => atom()}) :: %{atom() => [non_neg_integer()]}
  def families(feat_rows) do
    feat_rows
    |> Enum.group_by(fn {_row, id} -> id end, fn {row, _id} -> row end)
    |> Map.new(fn {id, rows} -> {id, Enum.sort(rows)} end)
  end

  @doc """
  Заклинания: `%{spell_id => строка spells.2da}`. Когда имя носят несколько строк
  (копия как умение класса, `Bull's Strength` у Чёрного стража), берётся строка,
  у которой есть круг хотя бы у одного класса, из них — первая.
  """
  @spec spells(Source.t(), map(), map()) :: %{atom() => non_neg_integer()}
  def spells(source, ruleset, overrides \\ %{}) do
    ids = id_index(ruleset.spells)
    by_name = name_index(ruleset.spells)
    table = Source.table(source, "spells")
    class_columns = ~w(Bard Cleric Druid Paladin Ranger Wiz_Sorc)

    TwoDA.rows(table)
    |> Enum.flat_map(fn {index, row} ->
      name = Source.row_name(source, "spells", index, "Name")

      id =
        case overridden(table, index, overrides, "spells") do
          nil -> spell_id(row, name, ids, by_name)
          :none -> nil
          id -> id
        end

      if id, do: [{id, index, Enum.any?(class_columns, &(row[&1] != nil))}], else: []
    end)
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {id, candidates} ->
      {_id, index, _} =
        Enum.find(candidates, &elem(&1, 2)) || Enum.min_by(candidates, &elem(&1, 1))

      {id, index}
    end)
  end

  defp spell_id(row, name, ids, by_name) do
    ((Map.has_key?(@spell_labels, row["Label"]) and
        Map.has_key?(ids, Atom.to_string(@spell_labels[row["Label"]]))) &&
       @spell_labels[row["Label"]]) ||
      (name &&
         Enum.find_value([name, String.replace(name, ~r/^Epic Spell: /, "")], fn candidate ->
           n = norm(candidate)
           first_id(ids, [n, n <> "_spell"]) || Map.get(by_name, n)
         end))
  end

  @doc """
  Оружие: `%{weapon_id => строка baseitems.2da}` — только предметы с типом урона.
  Имя сравнивается и без пробелов: `Short Sword` — наш `shortsword`.
  """
  @spec weapons(Source.t(), map()) :: %{atom() => non_neg_integer()}
  def weapons(source, ruleset) do
    ids = id_index(ruleset.weapons)
    squeezed = Map.new(ids, fn {k, v} -> {String.replace(k, "_", ""), v} end)

    for {index, row} <- TwoDA.rows(Source.table(source, "baseitems")),
        TwoDA.to_int(row["WeaponType"]) not in [nil, 0],
        row["label"] != "DELETED",
        name = Source.row_name(source, "baseitems", index, "Name"),
        name != nil,
        n = norm(name),
        id = Map.get(ids, n) || Map.get(squeezed, String.replace(n, "_", "")),
        id != nil,
        into: %{},
        do: {id, index}
  end

  @doc "Домены: `%{\"air\" => строка domains.2da}` — id строкой, как в `spells.json`."
  @spec domains(Source.t()) :: %{String.t() => non_neg_integer()}
  def domains(source) do
    for {index, _row} <- TwoDA.rows(Source.table(source, "domains")),
        name = Source.row_name(source, "domains", index, "Name"),
        name != nil,
        into: %{},
        do: {String.replace(norm(name), ~r/_domain$/, ""), index}
  end

  @doc "Школы: `%{строка spellschools.2da => \"abjuration\"}` — id строкой."
  @spec schools(Source.t()) :: %{non_neg_integer() => String.t()}
  def schools(source) do
    for {index, row} <- TwoDA.rows(Source.table(source, "spellschools")),
        label = row["Label"],
        label != nil,
        into: %{},
        do: {index, norm(label)}
  end

  defp id_index(records) do
    Map.new(records, fn {id, _record} -> {Atom.to_string(id), id} end)
  end

  defp name_index(records) do
    for {id, record} <- records,
        name = Map.get(record, :name),
        is_binary(name),
        into: %{},
        do: {norm(name), id}
  end

  defp first_id(ids, candidates), do: Enum.find_value(candidates, &Map.get(ids, &1))
end
