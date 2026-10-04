defmodule BuildCalculator.Data.Provenance do
  @moduledoc """
  Провенанс ванили — задача 4.6 (`VANILLA.md` §3.3, §4.6).

  Ваниль — отдельный продукт, и её число не должно молча держаться на странице
  вики Сиалы или на замере с сервера Сиалы. Модуль обходит всё, из чего
  собирается ванильный ruleset, — `priv/rules/vanilla/*.json` (задача 4.1:
  ваниль не читает ни одного файла шарда), — находит каждую **запись
  с источником** и отвечает про неё на три вопроса.

  1. **Какого вида её источники** (`kinds`): ванильные — `:fandom`
     (страница Fandom), `:base_2da` (строка базовой таблицы игры,
     `priv/base_2da/`, задача 4.5) и `:manual` (официальное руководство игры
     BioWare 2002 года, `kind: "manual"` со страницей PDF, задача 4.28);
     сиальские — `:siala_wiki`, `:siala_quote`
     (ключ `quote_siala`), `:hak`, `:server_script`, `:game_log` (фикстура лога
     `.билд`); `:user` — замер или слово Dan; `:derived` — наш вывод из соседних
     фактов.
  2. **Решает ли она число ванильного билда** (`decides`). Пять ответов:
       * `:number` — загрузчик читает запись, и от неё зависит число, которое
         печатает ванильный билд (или законность его левелапа);
       * `:caveat` — запись решает оговорку, а не число: непосчитанная запись
         разметки (`verdict` не `applied`), отметка «складывается —
         подтверждено» (`stacking_confirmed`), метка получателя, решение
         показа владельца (`display_decisions/0`, задача 4.20);
       * `:import_only` — запись читает только импорт игрового лога `.билд`,
         а его у ванили нет (флаг редакции, задача 4.4);
       * `:label` — надпись клиента, а не число;
       * `:unread` — из-под её ключа в ruleset не доезжает ничего: блоки
         `siala`, подтверждения игрока, разбор под ключами с подчёркиванием
         и несколько ключей, названных поимённо (`unread_keys/0`). Это
         **проверено мутацией**: `provenance_test.exs` вырезает все такие узлы
         из копии данных и сверяет загруженные ruleset'ы с настоящими, а новые
         кандидаты находит `mix provenance.audit --probe`.
  3. **Вердикт** (`verdict`):
       * `:vanilla_source` — среди источников есть ванильный (Fandom или
         `.2da`). Сиальский источник рядом остаётся подтверждением: «где
         ванильный источник подтверждает сиальский замер — оставь оба»;
       * `:engine_measurement` — источник только `kind: "user"`, и у каждого
         стоит **пометка «замер движка»** с доводом, почему шард механику не
         трогает (`engine: %{"basis" => …, "untouched_by_shard" => …}`);
       * `:derived` — наш вывод из соседних фактов, с названным `from`;
       * `:not_deciding` — запись числа не решает (см. выше);
       * `:pending` — спор, который решает не данные, а замер или другая
         задача; список закрытый и поимённый (`pending/0`);
       * `:violation` — всё остальное: решает число и держится на Сиале.

  🔴 **Нарушений быть не должно** — это сторож
  (`test/build_calculator/data/provenance_test.exs`), и отчёт
  `mix provenance.audit` печатает их списком.

  ## Что такое «запись с источником»

  Карта JSON, у которой есть хотя бы один ключ провенанса: `source`,
  `source_2`…, `sources`, `sources_extra`, `source_cap` и прочие `…source…`,
  `measured` (если это карта с `kind`), `quote_siala`. Ключ вида
  `<поле>_source` рядом с полем `<поле>` — провенанс **этого поля**, и он
  становится отдельной записью с путём `…/<поле>`: у `only_on_class_levels`
  фита источник свой, и смешать его с источником требований фита значило бы
  засчитать полю чужой Fandom. Строковое значение источником не считается
  (`hit_die_source: "class taken at that level"` — данные, а не ссылка).

  ## Чистый модуль

  Файлы читает `read_vanilla!/1`, а всё остальное работает с уже прочитанными
  картами — сторож подкладывает запись в память, не трогая диска.
  """

  @typedoc "Вид одного источника."
  @type kind ::
          :fandom
          | :base_2da
          | :manual
          | :siala_wiki
          | :siala_quote
          | :hak
          | :server_script
          | :game_log
          | :user
          | :derived
          | :none
          | :unknown

  @typedoc "Что запись решает для ванильного билда."
  @type decides :: :number | :caveat | :import_only | :label | :unread

  @typedoc "Вердикт по записи."
  @type verdict ::
          :vanilla_source
          | :engine_measurement
          | :derived
          | :not_deciding
          | :pending
          | :violation

  @type entry :: %{
          file: String.t(),
          path: [String.t() | non_neg_integer()],
          kinds: [kind()],
          unmarked_users: non_neg_integer(),
          derived_without_from: non_neg_integer(),
          decides: decides(),
          decides_why: String.t(),
          verdict: verdict(),
          verdict_why: String.t()
        }

  # `:manual` — задача 4.28: хват луков («You need at least two hands to use a
  # bow, regardless of size») на Fandom не назван ни одной страницей, и
  # единственный ванильный документ, который его называет, — руководство самой
  # игры. Сиальского в нём нет по построению: это книга, вышедшая с игрой.
  @vanilla_kinds [:fandom, :base_2da, :manual]
  @siala_kinds [:siala_wiki, :siala_quote, :hak, :server_script, :game_log]

  @doc "Виды источников, которые годятся ванили сами по себе."
  @spec vanilla_kinds() :: [kind()]
  def vanilla_kinds, do: @vanilla_kinds

  @doc "Виды источников, принадлежащие шарду."
  @spec siala_kinds() :: [kind()]
  def siala_kinds, do: @siala_kinds

  # ---------------------------------------------------------------- reading --

  @doc """
  Все `*.json` ванильного слоя под `root` (каталог `priv/rules`), прочитанные
  в карту `%{"rules.json" => decoded, …}`.
  """
  @spec read_vanilla!(Path.t()) :: %{String.t() => term()}
  def read_vanilla!(root) do
    root
    |> Path.join("vanilla/*.json")
    |> Path.wildcard()
    |> Map.new(fn path -> {Path.basename(path), path |> File.read!() |> Jason.decode!()} end)
  end

  # ----------------------------------------------------------------- walking --

  @doc """
  Записи с источником во всех файлах, по файлу и по пути, с ответами
  на все три вопроса.
  """
  @spec records(%{String.t() => term()}) :: [entry()]
  def records(files) do
    files
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {file, json} -> walk(json, file, [], []) end)
    |> Enum.map(&classify/1)
  end

  @doc "Записи с вердиктом `:violation`."
  @spec violations([entry()]) :: [entry()]
  def violations(records), do: Enum.filter(records, &(&1.verdict == :violation))

  @doc """
  Записи, у которых рядом с ванильным источником стоит сиальский или `user`.
  Сторож их пропускает; покрывает ли ванильная цитата решающий факт — вопрос
  к человеку, и этот список — то, что ему смотреть.
  """
  @spec mixed([entry()]) :: [entry()]
  def mixed(records) do
    Enum.filter(records, fn r ->
      Enum.any?(r.kinds, &(&1 in @vanilla_kinds)) and
        Enum.any?(r.kinds, &(&1 not in @vanilla_kinds))
    end)
  end

  defp walk(%{} = node, file, path, ancestors) do
    roles = for {key, value} <- node, role = role(key, value, node), do: {key, role, value}

    own =
      for {_key, :source, value} <- roles, kind <- kinds(value), do: {kind, value}

    # `quotes: [%{text, source}, …]` — цитаты записи со своими источниками:
    # это провенанс самой записи, а не отдельные записи.
    own =
      own ++
        for {_key, :quotes, quotes} <- roles,
            quote <- quotes,
            {key, value} <- quote,
            role(key, value, quote) == :source,
            kind <- kinds(value),
            do: {kind, value}

    own = own ++ for({_key, :siala_quote, _value} <- roles, do: {:siala_quote, nil})

    fields =
      roles
      |> Enum.filter(&match?({_key, {:field, _field}, _value}, &1))
      |> Enum.group_by(fn {_key, {:field, field}, _value} -> field end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {field, entries} ->
        sources = for {_key, _role, value} <- entries, kind <- kinds(value), do: {kind, value}
        record(file, path ++ [field], sources, [node | ancestors])
      end)

    here = if own == [], do: [], else: [record(file, path, own, [node | ancestors])]
    skip = MapSet.new(roles, &elem(&1, 0))

    children =
      node
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reject(fn {key, _value} -> MapSet.member?(skip, key) end)
      |> Enum.flat_map(fn {key, value} ->
        walk(value, file, path ++ [key], [node | ancestors])
      end)

    here ++ fields ++ children
  end

  defp walk(list, file, path, ancestors) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} -> walk(value, file, path ++ [index], ancestors) end)
  end

  defp walk(_scalar, _file, _path, _ancestors), do: []

  defp record(file, path, sources, ancestors) do
    %{
      file: file,
      path: path,
      kinds: sources |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort(),
      unmarked_users:
        Enum.count(sources, fn {kind, value} -> kind == :user and not engine_marked?(value) end),
      derived_without_from:
        Enum.count(sources, fn {kind, value} -> kind == :derived and not derivation?(value) end),
      ancestors: ancestors
    }
  end

  # ------------------------------------------------------------- source keys --

  # `source`, `source_2`, `sources`, `sources_extra`, `source_cap`,
  # `source_damage_resistance`, `second_source`, `covers_source`,
  # `last_two_source`… — всё, где слово `source` стоит целым словом имени.
  @source_key ~r/\A(?:[a-z0-9_]+_)?sources?(?:_[a-z0-9_]+)?\z/
  @field_source_key ~r/\A([a-z0-9_]+?)_source(?:_\d+)?\z/

  # Имена со словом `source`, которые провенансом НЕ являются: область действия
  # потолка по видам источников прибавки и прямое «это не источник».
  @not_source_keys ~w(applies_to_sources external_corroboration_not_a_source)

  # Роль ключа в карте: источник всей карты, источник одного её поля, цитата
  # Сиалы, список цитат со своими источниками или ничего. Строка источником не
  # бывает: `modifier_source: "modified"` и `hit_die_source: "class taken at
  # that level"` — данные, а `_schema.source` — описание поля.
  defp role("quote_siala", value, _node) when is_binary(value), do: :siala_quote
  defp role("measured", %{"kind" => _} = _value, _node), do: :source

  defp role("quotes", [_ | _] = value, _node) do
    if Enum.all?(value, &is_map/1), do: :quotes
  end

  defp role(_key, value, _node) when is_binary(value) or is_number(value) or is_boolean(value),
    do: nil

  defp role(key, value, node) when is_binary(key) do
    cond do
      key in @not_source_keys ->
        nil

      not Regex.match?(@source_key, key) ->
        nil

      not (is_map(value) or is_list(value) or is_nil(value)) ->
        nil

      is_list(value) and not Enum.all?(value, &is_map/1) ->
        nil

      field = field_of(key, node) ->
        {:field, field}

      true ->
        :source
    end
  end

  defp role(_key, _value, _node), do: nil

  defp field_of(key, node) do
    case Regex.run(@field_source_key, key) do
      [_, field] -> if Map.has_key?(node, field), do: field
      _ -> nil
    end
  end

  @doc false
  @spec kinds(term()) :: [kind()]
  def kinds(nil), do: [:none]
  def kinds(list) when is_list(list), do: Enum.flat_map(list, &kinds/1)
  def kinds(%{"wiki" => "fandom"}), do: [:fandom]
  def kinds(%{"wiki" => "siala"}), do: [:siala_wiki]

  def kinds(%{"kind" => kind}) do
    case kind do
      "2da" -> [:base_2da]
      "manual" -> [:manual]
      "user" -> [:user]
      "hak" -> [:hak]
      "server_script" -> [:server_script]
      "fixture" -> [:game_log]
      "derived" -> [:derived]
      _ -> [:unknown]
    end
  end

  # Источник, записанный отдельной записью: `{note, quote, source}` —
  # `totals_energy_types.first_five_source`. Вид — вид его собственного источника.
  def kinds(%{} = nested) do
    case for({key, value} <- nested, role(key, value, nested) == :source, do: kinds(value)) do
      [] -> [:unknown]
      found -> List.flatten(found)
    end
  end

  def kinds(_other), do: []

  # ------------------------------------------------------------- engine mark --

  @engine_bases ~w(measurement game_log)

  @doc """
  Основания, с которыми `kind: "user"` годится ванили: `measurement` — замер
  в игре на сервере Сиалы, `game_log` — печать движка командой `.билд+`.
  Слово без наблюдения («так работает, я знаю») пометкой не становится:
  ему нужен ванильный источник.
  """
  @spec engine_bases() :: [String.t()]
  def engine_bases, do: @engine_bases

  @doc """
  Стоит ли на источнике `kind: "user"` пометка «замер движка на сервере
  Сиалы; шард механику не трогает» с доводом:

      "engine": {"basis": "measurement", "untouched_by_shard": "…довод…"}
  """
  @spec engine_marked?(term()) :: boolean()
  def engine_marked?(%{"engine" => %{"basis" => basis, "untouched_by_shard" => why}})
      when basis in @engine_bases and is_binary(why),
      do: String.trim(why) != ""

  def engine_marked?(_source), do: false

  defp derivation?(%{"from" => from}) when is_binary(from), do: String.trim(from) != ""
  defp derivation?(_source), do: false

  # -------------------------------------------------------- what it decides --

  # Ключи, из-под которых в ruleset не доезжает ничего. `siala` — подтверждение
  # или молчание Сиалы у ванильного правила; `confirmed_by_player`,
  # `siala_confirmed`, `siala_confirmation` — то же словами игрока; `hak` —
  # строка хака шарда, из которой когда-то вывели правку; остальные — разбор
  # рядом с правилом, которое ядро читает из соседнего поля:
  #
  #   * `measured_ranks_not_value` — замер R4 у Кувырка (правило — `amount`);
  #   * `expected_but_not_measured` — ожидание Dan у пола заклинателя;
  #   * `cap_reading` — наше чтение капа у Spellcraft (арифметика — в ядре);
  #   * `saving_throw_bonus_cap` — вторая запись капа спасов в `gear`
  #     (кап читается из `stat_caps.saving_throw_bonus`);
  #   * `applied_elsewhere` — сверка «правило применено в другом файле»:
  #     загрузчик её проверяет и ничего из неё не берёт.
  #
  # ⚠️ Список сверен пробой (`mix provenance.audit --probe`) и стережётся
  # мутацией в `provenance_test.exs`: всё, что под этими ключами, вырезается
  # из копии данных, и оба ruleset'а обязаны совпасть с настоящими.
  @unread_keys ~w(siala confirmed_by_player siala_confirmed siala_confirmation hak
                  measured_ranks_not_value expected_but_not_measured cap_reading
                  saving_throw_bonus_cap applied_elsewhere)

  # Ключи с подчёркиванием, которые загрузчик ЧИТАЕТ. Всё остальное с
  # подчёркиванием — разбор, решения и история, которые читает человек.
  # ⚠️ Список сверен мутацией (`provenance_test.exs`), а не памятью:
  # вырезанные узлы не должны сдвигать ни одного поля ruleset'а.
  # ⚠️ `_siala_grip` и `_siala_proficiency` стояли здесь до задачи 4.28: они
  # жили в ванильном `weapons.json`. Теперь это слой Сиалы
  # (`siala_41/generated/weapons.json`), и ванильные файлы их не несут.
  @read_underscore_keys ~w(_vanilla_constants_confirmed _receivers _grip _off_hand)

  @doc "Ключи, под которыми загрузчик ничего не читает (без ключей с подчёркиванием)."
  @spec unread_keys() :: [String.t()]
  def unread_keys, do: @unread_keys

  @doc "Ключи с подчёркиванием, которые загрузчик читает."
  @spec read_underscore_keys() :: [String.t()]
  def read_underscore_keys, do: @read_underscore_keys

  @doc "Не читает ли загрузчик узел под этим ключом."
  @spec unread_key?(term()) :: boolean()
  def unread_key?(key) when is_binary(key),
    do:
      key in @unread_keys or
        (String.starts_with?(key, "_") and key not in @read_underscore_keys)

  def unread_key?(_key), do: false

  # Записи, которые читает только импорт игрового лога `.билд` (Сиала): свод
  # надетого из лога сводит AC по слотам, числа атаки предмета и строки
  # поглощения. У ванили импорта нет — флаг редакции (задача 4.4).
  @import_only [
    {"rules.json", ["gear", "item_slot_ac_types"]},
    {"rules.json", ["gear", "weapon", "import_rule"]},
    {"feat_resistance_bonuses.json", ["totals_energy_types", "excluded"]}
  ]

  # 🔴 Решения ПОКАЗА — что калькулятор печатает там, где у игры одного числа
  # нет (задача 4.20). Это не факт об игре, и ванильный источник им взять
  # неоткуда: их источник — слово владельца (`kind: "user"` без пометки
  # «замер движка», потому что ничего не мерили). Число они не двигают —
  # ядро считает то же самое с записью и без, — а решают оговорку: та же роль,
  # что у `stacking_confirmed`. Список закрытый и поимённый, как `@pending`:
  # сторож падает, если строка перестала совпадать с живой записью, и мутацией
  # проверяет, что вырезанная запись сдвигает в ruleset'е ТОЛЬКО список
  # оговорок (`provenance_test.exs`). Решение, которое двинуло бы число,
  # отсюда уходит в нарушения — ему нужен источник об игре.
  @display_decisions [
    {"rules.json", ["character", "hit_points_shown"],
     "решение показа (Dan 02.10.2026, задача 4.20): HP — максимум кости на каждом уровне; снимает оговорку, числа не двигает"}
  ]

  @doc "Решения показа: `{файл, путь, что решает}` — записи, решающие оговорку, а не число."
  @spec display_decisions() :: [{String.t(), [String.t()], String.t()}]
  def display_decisions, do: @display_decisions

  # Файлы, где решается оговорка, а не число.
  @caveat_files %{
    "feat_effect_receivers.json" =>
      "метка получателя: решает, печатать ли оговорку про фит, а не число"
  }

  @label_files %{
    "class_choice_no_selection.json" => "надпись клиента на невыбранной школе, а не число"
  }

  # Вердикты, при которых запись двигает число: `applied` — посчитана,
  # `confirmed_absent` — «у класса нет заклинаний», то есть ноль слотов.
  # Остальные (`not_modelled`, `counted_elsewhere`, `not_a_*`, `not_binding`)
  # решают оговорку или не решают ничего.
  @number_verdicts ~w(applied confirmed_absent)

  defp decides(%{file: file, path: path, ancestors: ancestors}) do
    cond do
      Enum.any?(path, &unread_key?/1) ->
        {:unread, "под ключом, который загрузчик не читает (#{unread_in(path)})"}

      prefix?(@import_only, file, path) ->
        {:import_only, "читает только импорт лога .билд, у ванили его нет"}

      decision = display_decision(file, path) ->
        {:caveat, elem(decision, 2)}

      why = @caveat_files[file] ->
        {:caveat, why}

      why = @label_files[file] ->
        {:label, why}

      List.last(path) == "stacking_confirmed" ->
        {:caveat, "отметка «складывается — подтверждено» снимает оговорку, числа не двигает"}

      verdict = nearest_verdict(ancestors) ->
        if verdict in @number_verdicts,
          do: {:number, "вердикт #{verdict}: запись применяется"},
          else: {:caveat, "вердикт #{verdict}: запись решает оговорку, а не число"}

      true ->
        {:number, "загрузчик читает запись"}
    end
  end

  defp unread_in(path), do: path |> Enum.filter(&unread_key?/1) |> Enum.join(", ")

  # Точное совпадение пути, а не префикс: решение — одна запись, и всё, что
  # когда-нибудь ляжет под неё со своим источником, судится как обычно.
  defp display_decision(file, path),
    do: Enum.find(@display_decisions, fn {f, p, _why} -> f == file and p == path end)

  defp prefix?(entries, file, path) do
    Enum.any?(entries, fn {f, prefix} -> f == file and List.starts_with?(path, prefix) end)
  end

  # Вердикт ближайшей записи с полем `verdict` — сама запись или её предок.
  # `false`, если вердикта нет ни у кого: обычная запись правил.
  defp nearest_verdict(ancestors) do
    Enum.find_value(ancestors, false, fn
      %{"verdict" => verdict} when is_binary(verdict) -> verdict
      _ -> nil
    end)
  end

  # ----------------------------------------------------------------- pending --

  # 🔴 Закрытый поимённый список споров, которые решает не эта задача. Каждая
  # строка называет, КТО и ЧЕМ её закроет, — и сторож падает, если строка
  # перестала совпадать хоть с одной записью (устаревшее исключение хуже
  # отсутствующего).
  #
  # ⚠ Сегодня список ПУСТ, и механизм оставлен для следующего спора. Последняя
  # строка — `rules.json` → `gear/ac_types/same_type` (⏸ E5/X1: складываются ли
  # собственный AC и вещь одного типа на ванили) — снята задачей 4.44: кейс AX1
  # закрыт словом Dan 27.09.2026 («правила AC на Сиале не менялись»), и запись
  # получила вердикт `:vanilla_source` по общим правилам — её цитаты Fandom
  # («Dodge», «Armor skin», «Draconic armor») стоят парами с источниками
  # (`quote_3` ↔ `source_3` …) и сверяются с кэшем дословно
  # (`provenance_test.exs`).
  @pending []

  @doc "Споры, которые решает не данные этой задачи: `{файл, путь, кто и чем закроет}`."
  @spec pending() :: [{String.t(), [String.t()], String.t()}]
  def pending, do: @pending

  # ---------------------------------------------------------------- verdict --

  defp classify(record) do
    {decides, decides_why} = decides(record)
    {verdict, verdict_why} = verdict(record, decides)

    record
    |> Map.drop([:ancestors])
    |> Map.merge(%{
      decides: decides,
      decides_why: decides_why,
      verdict: verdict,
      verdict_why: verdict_why
    })
  end

  defp verdict(record, decides) do
    kinds = record.kinds
    vanilla = Enum.filter(kinds, &(&1 in @vanilla_kinds))
    pending = Enum.find(@pending, fn {f, p, _why} -> f == record.file and p == record.path end)

    # ⚠️ Спор проверяется ПЕРВЫМ: у записи из нескольких фактов ванильный
    # источник может подпирать один из них и молчать про спорный (так было
    # у `same_type` до задачи 4.44: Fandom «Dodge» — про уклонение, а спорным
    # было природное против вещевого).
    cond do
      pending && decides == :number ->
        {:pending, elem(pending, 2)}

      vanilla != [] ->
        {:vanilla_source, "ванильный источник: #{Enum.join(vanilla, ", ")}"}

      decides != :number ->
        {:not_deciding, "не решает число: #{decides}"}

      kinds != [] and Enum.all?(kinds, &(&1 in [:user, :derived])) and
        record.unmarked_users == 0 and record.derived_without_from == 0 and :user in kinds ->
        {:engine_measurement, "замер движка на сервере Сиалы, пометка с доводом"}

      kinds == [:derived] and record.derived_without_from == 0 ->
        {:derived, "наш вывод из соседних фактов"}

      true ->
        {:violation, violation_why(record)}
    end
  end

  defp violation_why(record) do
    siala = Enum.filter(record.kinds, &(&1 in @siala_kinds))

    [
      siala != [] && "сиальский источник: #{Enum.join(siala, ", ")}",
      record.unmarked_users > 0 &&
        "kind: user без пометки «замер движка» (#{record.unmarked_users})",
      record.derived_without_from > 0 && "вывод без from",
      :unknown in record.kinds && "источник непонятной формы",
      :none in record.kinds && "источник null"
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> "нет ванильного источника"
      reasons -> Enum.join(reasons, "; ")
    end
  end

  # ------------------------------------------------------------------ census --

  @doc """
  Сводка: всего записей, по вердикту, по тому, что решают, и по видам
  источников среди записей, решающих число.
  """
  @spec census([entry()]) :: map()
  def census(records) do
    deciding = Enum.filter(records, &(&1.decides == :number))

    %{
      total: length(records),
      by_verdict: Enum.frequencies_by(records, & &1.verdict),
      by_decides: Enum.frequencies_by(records, & &1.decides),
      deciding_with_siala:
        Enum.count(deciding, fn r -> Enum.any?(r.kinds, &(&1 in @siala_kinds)) end),
      deciding_with_user: Enum.count(deciding, &(:user in &1.kinds)),
      deciding_without_vanilla:
        Enum.count(deciding, fn r -> not Enum.any?(r.kinds, &(&1 in @vanilla_kinds)) end),
      # Ванильный источник рядом с сиальским или `user`: сторож такую запись
      # пропускает, но ПОКРЫВАЕТ ли ванильная цитата решающий факт, видит только
      # человек — `--list` печатает их, чтобы было что проверять глазами.
      deciding_mixed: length(mixed(deciding)),
      by_file: Enum.frequencies_by(records, & &1.file)
    }
  end

  @doc """
  Та же карта файла без узла по пути `path` — для проверки «читает ли
  загрузчик эту запись»: вырезать и сравнить загруженные ruleset'ы.
  Элемент списка удаляется целиком (индексы соседей сдвигаются — это и есть
  другое содержимое списка).
  """
  @spec delete_at(term(), [String.t() | non_neg_integer()]) :: term()
  def delete_at(%{} = map, [key]), do: Map.delete(map, key)
  def delete_at(list, [index]) when is_list(list), do: List.delete_at(list, index)

  def delete_at(%{} = map, [key | rest]) do
    case Map.fetch(map, key) do
      {:ok, child} -> Map.put(map, key, delete_at(child, rest))
      :error -> map
    end
  end

  def delete_at(list, [index | rest]) when is_list(list) and is_integer(index),
    do: List.update_at(list, index, &delete_at(&1, rest))

  def delete_at(other, _path), do: other

  @doc "Путь записи одной строкой: `stat_caps/attack_bonus`, `bonuses/[3]/cap`."
  @spec render_path([String.t() | non_neg_integer()]) :: String.t()
  def render_path(path) do
    Enum.map_join(path, "/", fn
      index when is_integer(index) -> "[#{index}]"
      key -> key
    end)
  end
end
