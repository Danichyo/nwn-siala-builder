defmodule BuildCalculator.Data.Loader.Layers do
  @moduledoc """
  Слоение рукописных правил: `vanilla/rules.json` снизу, `siala_41/overrides.json`
  сверху, **по тем же ключам** (задача 4.1, VANILLA.md §2, принцип 1).

  До 25.09.2026 было наоборот: ванильные секции лежали в сиальском файле и раздавались
  ванили списком `@vanilla_sections`, а сиальские значения тех же полей жили рядом
  двойниками с префиксом `siala_` и сравнением версии ruleset'а в загрузчике. Теперь
  ваниль самодостаточна, а шард несёт только отличия — и правило наложения одно, без
  единого имени секции:

    * **карта на карту** — сливаются по ключам, рекурсивно;
    * **список записей на список записей** — сливаются по ИМЕНИ записи: первое из
      `#{inspect(~w(id skill feat))}`, которое есть строкой у каждой записи верхнего
      слоя. Порядок — нижнего слоя; запись верхнего сливается с записью нижнего
      с тем же именем, остальные записи нижнего остаются как были;
    * **записи разметки прибавок** (список `bonuses` файлов `*_bonuses.json`) называют
      себя не одним полем на весь список, а КАЖДАЯ своим — ровно одним из
      `#{inspect(~w(feat class skill race_feat race))}` (`Loader.BonusMarkup.source!/4`):
      колонка Мастера оружия — `class`, `Epic prowess` — `feat`. У такого списка имя
      записи — ПАРА «поле = значение», и сливаются записи по паре. Правило включается,
      только когда так названы ОБА списка и предыдущее правило не нашло ключа, которым
      названы оба (задача 4.46: до неё слой Сиалы мог лечь только на файл, где все
      записи названы одним полем, — `feat_resistance_bonuses.json`; колонка Мастера
      оружия — запись `class` среди записей `feat`);
    * **всё остальное** — значение верхнего слоя заменяет нижнее целиком: скаляры,
      списки без имён (`sources`, `weapons`, `ac_types.value`), `null`;
    * **провенанс не сливается.** Если запись верхнего слоя называет свой источник
      или цитату (`source`, `source_2`…, `quote`, `quote_2`…), все такие ключи
      нижней записи отбрасываются, прежде чем слить остальное. Иначе сиальские
      4 класса (`character.max_classes`, слово Dan) унесли бы с собой ванильную
      цитату Fandom про три — источник, слитый по полям или склеенный с чужими
      цитатами, цитировал бы страницу за число, которого она не печатала.
      Прочие поля записи (`applies_to_sources` у потолка, вложенные факты)
      по-прежнему сливаются по ключам.

  ## Что роняет сборку

  Три случая, и все три — про запись верхнего слоя, которая иначе молча не сделала бы
  ничего или сделала бы не то:

    * запись с именем, которого у нижнего слоя нет, — «переопределение, которое
      ни на что не легло» (тот же довод, что у `formulas_shard`,
      `Loader.Character`: опечатка в имени иначе выглядела бы применённой);
    * имя, повторённое в одном слое дважды, — непонятно, с какой записью сливать;
    * верхний слой называет записи по имени, а нижний — нет (или другим ключом,
      и пары «поле-источник = значение» нет у обоих): заменить список целиком
      значило бы молча выбросить всё, что лежало внизу.

  Удалить запись нижнего слоя верхний не может — такого отличия у шарда пока нет;
  появится — это решение формы данных, а не этого модуля.
  """

  @identity_keys ~w(id skill feat)

  # Поля, которыми запись разметки прибавок называет свой источник, — все пять
  # видов `Loader.BonusMarkup` (у атаки все пять, у соседей четыре). Сверяется
  # с читателями тестом (`layers_test.exs`): поле, которого здесь нет, дало бы
  # записи без пары, и слой на такой файл молча заменил бы список целиком.
  @source_keys ~w(feat class skill race_feat race)

  @doc "Ключи, по которым сливаются записи двух списков, в порядке предпочтения."
  @spec identity_keys() :: [String.t()]
  def identity_keys, do: @identity_keys

  @doc "Поля-источники записи разметки: имя такой записи — пара «поле = значение»."
  @spec source_keys() :: [String.t()]
  def source_keys, do: @source_keys

  @doc """
  Кладёт `overlay` поверх `base`. `:missing` с любой стороны — «слоя нет»: остаётся
  другой, а если нет обоих — пустая карта.

  `labels` — имена двух файлов для текста падения.
  """
  @spec merge(map() | :missing, map() | :missing, {String.t(), String.t()}) :: map()
  def merge(base, overlay, labels \\ {"нижний слой", "верхний слой"})

  def merge(:missing, :missing, _labels), do: %{}
  def merge(base, :missing, _labels) when is_map(base), do: base
  def merge(:missing, overlay, _labels) when is_map(overlay), do: overlay

  def merge(base, overlay, labels) when is_map(base) and is_map(overlay),
    do: merge_maps(base, overlay, [], labels)

  defp merge_maps(base, overlay, path, labels) do
    base =
      if Enum.any?(Map.keys(overlay), &provenance_key?/1),
        do: Map.reject(base, fn {key, _value} -> provenance_key?(key) end),
        else: base

    Map.merge(base, overlay, fn key, below, above ->
      merge_value(below, above, [key | path], labels)
    end)
  end

  defp merge_value(below, above, path, labels) when is_map(below) and is_map(above),
    do: merge_maps(below, above, path, labels)

  defp merge_value(below, above, path, labels) when is_list(below) and is_list(above),
    do: merge_lists(below, above, path, labels)

  defp merge_value(_below, above, _path, _labels), do: above

  # `source`, `source_2` …, `quote`, `quote_2` … — то, на чём держится число записи.
  @provenance_key ~r/\A(source|quote)(_\d+)?\z/

  defp provenance_key?(key) when is_binary(key), do: Regex.match?(@provenance_key, key)
  defp provenance_key?(_key), do: false

  defp merge_lists(below, above, path, labels) do
    case naming(below, above, path, labels) do
      nil ->
        above

      name_of ->
        above_by_name = index!(above, name_of, path, elem(labels, 1))
        below_names = index!(below, name_of, path, elem(labels, 0))

        for {name, _record} <- above_by_name, not Map.has_key?(below_names, name) do
          raise """
          #{elem(labels, 1)}: #{render(path)} names the record #{render_name(name)}, and \
          #{elem(labels, 0)} has no such record there — an override that lands on nothing \
          would silently do nothing \
          (known: #{below_names |> Map.keys() |> Enum.map(&render_name/1) |> Enum.sort() |> inspect()})
          """
        end

        for record <- below do
          name = name_of.(record)

          case Map.fetch(above_by_name, name) do
            {:ok, over} -> merge_maps(record, over, [path_name(name) | path], labels)
            :error -> record
          end
        end
    end
  end

  # Как назвать записи пары списков: функция «запись → имя» или `nil` — имён нет,
  # и верхний слой заменяет нижний целиком. Имя — всегда пара `{поле, значение}`:
  # у первого правила поле одно на весь список, у второго — своё у каждой записи.
  #
  #   1. Общий ключ из `@identity_keys`, который несёт строкой КАЖДАЯ запись
  #      верхнего слоя, — если его несёт и каждая запись нижнего.
  #   2. Иначе — пара «поле-источник = значение», если так названа каждая запись
  #      ОБОИХ слоёв (разметка прибавок, где у соседних записей поля разные).
  #   3. Верхний слой назван (по первому правилу или парами), а нижний не назван
  #      ни так, ни так, — сборка падает: заменить список значило бы выбросить
  #      нижний слой.
  #   4. Иначе имён нет.
  #
  # ⚠ Пункт 2 стоит ПОСЛЕ пункта 1 и ничего у него не отнимает: списки, которые
  # до задачи 4.46 сливались по общему ключу, сливаются по нему же. Меняются два
  # случая, и оба раньше были бедой: запись `feat` поверх смешанной разметки
  # роняла сборку («drop everything»), а запись `class` поверх неё молча
  # заменяла список целиком. Проверено прогоном 02.10.2026 на живых слоях до
  # появления `siala_41/feat_attack_bonuses.json`: ни пункт 2, ни вторая ветка
  # пункта 3 не срабатывали ни разу, то есть ни один существующий слой
  # наложение не сменил.
  defp naming(below, above, path, labels) do
    key = identity_key(above)

    cond do
      key != nil and named_by?(below, key) ->
        &{key, Map.fetch!(&1, key)}

      source_named?(above) and source_named?(below) ->
        &source_name/1

      key != nil ->
        raise_unnamed_below!(path, labels, "`#{key}`")

      source_named?(above) ->
        raise_unnamed_below!(path, labels, "one of #{inspect(@source_keys)} each")

      true ->
        nil
    end
  end

  defp raise_unnamed_below!(path, labels, named_by) do
    raise """
    #{elem(labels, 1)}: #{render(path)} states records named by #{named_by}, and the list in \
    #{elem(labels, 0)} is not a list of such records — replacing it whole would silently \
    drop everything the lower layer states there
    """
  end

  # Имя записи — первый ключ, который несёт строкой КАЖДАЯ запись верхнего слоя.
  # Пустой список имени не имеет: «ничего» заменяет нижний слой целиком, это ответ.
  defp identity_key([]), do: nil
  defp identity_key(list), do: Enum.find(@identity_keys, &named_by?(list, &1))

  defp named_by?(list, key), do: Enum.all?(list, &(is_map(&1) and is_binary(Map.get(&1, key))))

  # Пустой список парой не назван — по той же причине, что и выше.
  defp source_named?([]), do: false
  defp source_named?(list), do: Enum.all?(list, &match?([_one], source_keys_of(&1)))

  defp source_keys_of(record) when is_map(record),
    do: Enum.filter(@source_keys, &is_binary(Map.get(record, &1)))

  defp source_keys_of(_other), do: []

  defp source_name(record) do
    [key] = source_keys_of(record)
    {key, Map.fetch!(record, key)}
  end

  defp index!(records, name_of, path, label) do
    Enum.reduce(records, %{}, fn record, acc ->
      name = name_of.(record)

      if Map.has_key?(acc, name) do
        raise "#{label}: #{render(path)} names the record #{render_name(name)} twice — " <>
                "there is no telling which of the two the other layer is about"
      end

      Map.put(acc, name, record)
    end)
  end

  defp render_name({key, value}), do: "#{key}=#{inspect(value)}"
  defp path_name({key, value}), do: "#{key}=#{value}"

  defp render(path), do: path |> Enum.reverse() |> Enum.join(".")
end
