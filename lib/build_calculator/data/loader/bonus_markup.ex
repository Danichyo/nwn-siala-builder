defmodule BuildCalculator.Data.Loader.BonusMarkup do
  @moduledoc """
  Общий хребет семи читателей разметки «что прибавляет к …».

  Семь файлов — `feat_skill_bonuses.json`, `feat_hp_bonuses.json`, `ac_bonuses.json`,
  `feat_ability_bonuses.json`, `feat_save_bonuses.json`, `feat_attack_bonuses.json`,
  `feat_spell_resistance.json` — написаны руками по одной схеме, и до задачи 3.46
  (заход 2) их читали семь копий одного скелета: `X_bonus_record`, `X_bonus_source!`,
  `X_bonus_id!`, `X_bonus_verdict!`, `X_bonus_name`, `X_bonus_amount`, `X_number!`,
  `X_steps!`. Здесь лежит ровно то, что у всех семи даёт **один и тот же ответ**:
  идентичность записи, провенанс, вердикт, имя, форма величины.

  🔴 **Схлопывания семи читателей в один здесь НЕТ и быть не должно.** Всё, где
  ответы расходятся, осталось в `Loader.Bonuses` и обязано различаться поимённо:
  тип AC (`ac_bonus_type!`), условие, отбирающее бонус монаха (`ac_bonus_scope!`),
  сторона капа у навыка (`skill_bonus_cap!`), исключение `Luck of heroes` из чужого
  требования (`save_bonus_prerequisite!`), оружие в руках (`attack_bonus_weapon!`),
  запрет потолка у HP и SR (`hp_bonus_cap_forbidden!`, `spell_resistance_cap_forbidden!`).
  Одна функция на всех не смогла бы дать им разные ответы — и попытка её написать
  была бы не упрощением, а потерей правил.

  ## Имя файла — параметр, а не догадка

  Каждая функция здесь первым аргументом берёт имя файла и ставит его в сообщение,
  вторым — имя записи. Это не украшение: сторож, не назвавший ни файл, ни запись,
  заставляет искать опечатку по семи файлам вручную, а весь смысл этого механизма
  в том, чтобы разметка не могла потерять прибавку молча.

  ⚠ **Сообщения слиты дословно там, где различались только именем файла.** Там, где
  формулировки расходились, оставлена та, что **называет запись**: у `ac_bonuses.json`
  четыре сторожа печатали `inspect(entry["feat"])` или `inspect(entry["verdict"])`
  вместо имени — то есть у записи, пришедшей от класса или расовой склонности,
  сообщение говорило `nil`. Это чинится слиянием, а не ломается им.
  """

  alias BuildCalculator.Data.Loader.Character
  alias BuildCalculator.Data.Loader.FactReceivers
  alias BuildCalculator.Data.Loader.NotAGap
  alias BuildCalculator.Data.Loader.Reading

  import BuildCalculator.Data.Loader.Reading

  @abilities Reading.abilities()

  # Какой словарь отвечает за каждый вид источника и каким словом он зовётся
  # в сообщении. Пять видов на семь файлов: `race_feat` ходит в словарь ФИТОВ
  # (расовая склонность — это фит, просто попадающий к персонажу не слотом),
  # а `race` есть только у атаки и означает саму расу.
  @source_dictionaries %{
    feat: {:feats, "feat"},
    class: {:classes, "class"},
    skill: {:skills, "skill"},
    race_feat: {:feats, "feat"},
    race: {:races, "race"}
  }

  @typedoc """
  Паспорт читателя: имя файла, поля-источники в порядке чтения и словарь вердиктов.

  `keys` служит двум вещам сразу — по нему ищется единственный источник записи
  и по нему же берётся её имя, — и это не экономия, а правило: имя записи есть
  имя её источника, и разъехаться этим двум нельзя.

  `verdicts` у каждого файла свой четвёртой строкой (`not_a_skill_bonus`,
  `not_an_ac_bonus`, …): слово, которым файл говорит «эта запись вообще не про
  мой стат». Три остальных вердикта общие.

  `guard` — необязательный сторож, которому нечего вернуть, но есть что запретить.
  Сегодня их два, оба про потолок, которого не существует (HP и SR).
  """
  @type reader :: %{
          :file => String.t(),
          :keys => [String.t()],
          :verdicts => %{String.t() => atom()},
          optional(:guard) => (map(), String.t() -> any())
        }

  # The three buckets every one of the six markup files is split into, and the
  # only place that split is written down.
  #
  # ⚠ **`counted_elsewhere` joined on 14.08.2026, and its absence was a blind
  # spot rather than a simplification.** Until then the loader kept `applied` and
  # `not_modelled` and dropped the other two verdicts on the floor, so a record
  # that said «этот факт уже учтён вот там» reached the core as *nothing at all*
  # — indistinguishable from a feat the file had never been asked about. That is
  # what made `Rules.Bonuses.whole_effect_counted?/3` blind to
  # `Weapon of choice`, and it is why flipping that record's verdict changed
  # nothing until this bucket existed.
  #
  # `not_a_*` stays dropped, and that is not the same omission: it says the
  # record is not about this stat at all, so there is nothing for a reader of
  # this stat to learn from it.
  @doc "Разложить прочитанные записи по трём корзинам, которые читает ядро."
  @spec buckets([map()]) :: %{applied: [map()], unmodelled: [map()], counted_elsewhere: [map()]}
  def buckets(records) do
    %{
      applied: for(r <- records, r.verdict == :applied, do: r),
      unmodelled: for(r <- records, r.verdict == :not_modelled, do: r),
      counted_elsewhere: for(r <- records, r.verdict == :counted_elsewhere, do: r)
    }
  end

  # Три клаузы, которые у семи читателей были буквально одинаковы. Отсутствующий
  # файл (`:missing`) и файл неожиданной формы дают ПУСТЫЕ корзины, а не падение:
  # разметка — слой поверх корпуса, и её отсутствие означает «прибавок не
  # объявлено», а не «сборка сломана». Всё, что файл ВСЁ-ТАКИ говорит и что мы
  # прочитать не можем, роняет сборку ниже по тексту.
  @doc "Прочитать файл разметки целиком: `record` разбирает одну запись."
  @spec build(map() | :missing, map(), (map(), map() -> map())) :: map()
  def build(:missing, _dictionaries, _record), do: buckets([])

  def build(%{"bonuses" => entries}, dictionaries, record) when is_list(entries) do
    entries |> Enum.map(&record.(&1, dictionaries)) |> buckets()
  end

  def build(_other, _dictionaries, _record), do: buckets([])

  @doc """
  Оболочка записи: шесть полей, которые есть у всех семи файлов, плюс доменные.

  Порядок вычисления сохранён от семи копий и важен ровно тем, ЧТО скажет сборка,
  когда сломано сразу два места: источник → вердикт → сторож файла → получатели
  (`affects`) → доменные поля → `owned_by`. Доменные поля считаются до `owned_by`
  у всех семи, поэтому и здесь считаются до него.

  Седьмого общего поля нет и не заводится: `covers_feat?` есть у шести файлов
  из семи (`ac_bonuses.json` его не несёт), и дорисовать его седьмому значило бы
  добавить в ruleset ключ, которого там никогда не было.
  """
  @spec record(reader(), map(), map(), (map(), atom(), String.t() -> map())) :: map()
  def record(reader, entry, dictionaries, domain) do
    %{file: file, keys: keys, verdicts: verdicts} = reader

    # `name/2` считается первым и не роняет сборку ничем — значит порядок
    # ПАДЕНИЙ от этого не меняется, а сообщения источника и вердикта получают,
    # чем назвать запись.
    name = name(entry, keys)
    source = source!(file, entry, keys, dictionaries)
    verdict = verdict!(file, entry, verdicts, name)

    case Map.get(reader, :guard) do
      nil -> :ok
      guard -> guard.(entry, name)
    end

    NotAGap.verify!("#{file}: #{name}", entry["not_a_gap"],
      bases: NotAGap.bases(),
      describes: describes(source, dictionaries)
    )

    FactReceivers.verify_bonus_affects!(
      file,
      name,
      entry["affects"],
      dictionaries.known_receivers
    )

    fields = domain.(entry, verdict, name)

    Map.merge(
      %{
        # The record's own name — the feat, class, skill or trait it is about.
        # What the interface prints beside the number, and what a gap carries.
        id: elem(source, 1),
        source: source,
        verdict: verdict,
        owned_by: Character.owned_by!(file, name, entry, verdict),
        why: entry["why"],
        # What the fact changes — `nil` or a list of raw JSON strings, read
        # verbatim (task «пять файлов прибавок», 17.08.2026). Kept as the
        # source spells it, not atomised: `Rules.GapReceivers.ours?/2` expects
        # exactly the `%{"affects" => […]}` shape a siala class/feat/skill fact
        # already carries, and the ruleset-wide gap loop (`Loader.Gaps`) builds
        # that shape around this field rather than teaching `GapReceivers` a
        # second one.
        affects: entry["affects"],
        # ⚠ Решение владельца о том, что запись до нашего ответа не доезжает
        # (задача 3.76). Тот же ключ и тот же смысл, что у фактов класса
        # (`siala_41/classes.json`, задачи 3.74–3.75), и читает его та же
        # `Rules.GapReceivers.ours?/2` — второго механизма для того же вопроса
        # не заводится.
        #
        # 🔴 Ось у него СВОЯ, и она не дублирует `verdict`. Вердикт говорит про
        # отношение записи к расчёту («считаем» / «считаем в другом месте» /
        # «честно не можем» / «это вовсе не прибавка к навыку»), а этот ключ —
        # про то, обязаны ли мы признаться игроку. У `trackless_step`
        # и `stonecunning` вердикт `not_modelled` остаётся ПРАВДОЙ (прибавка
        # есть, и мы её правда не считаем), и `affects: ["skill_values"]` тоже —
        # менять их значило бы соврать ради числа в баннере.
        #
        # ⚠ С задачи 3.95 решение называет и СВОЙ ДОВОД (`basis`), потому что
        # доводов стало два и второй проверяем: `feat_description` стоит на том,
        # что число и условие уже названы в описании фита, и у фита без описания
        # сборка падает. Сторож — `Loader.NotAGap`, один на четыре семейства.
        not_a_gap: entry["not_a_gap"]
      },
      fields
    )
  end

  # Фит, чьё ОПИСАНИЕ проверяет сторож довода `feat_description`
  # (`Loader.NotAGap`), — или `nil` у записи, чей источник фитом не является.
  #
  # ⚠ Вид источника читается тем же `@source_dictionaries`, что и всё
  # остальное: расовая склонность (`race_feat`) ходит в словарь ФИТОВ, то есть
  # описание у `Hardiness vs. poisons` есть ровно там же, где у `Dodge`.
  # Второй таблицы «какой вид куда ходит» здесь нет и быть не должно.
  defp describes(source, dictionaries) do
    {kind, id} = source

    case Map.get(@source_dictionaries, kind) do
      {:feats, _word} -> {id, Map.get(dictionaries, :feats, %{})}
      _other -> nil
    end
  end

  @doc """
  Единственный источник записи — фит, класс, навык, расовая склонность или раса.

  Два и больше названных источников — такая же ошибка, как ни одного: запись
  описывает одну прибавку, и по её источнику ядро решает, ЧЕМ персонаж должен
  владеть, чтобы прибавка сработала (`Rules.Bonuses.held?/5`). Два источника
  означали бы два разных ответа на этот вопрос из одной строки.
  """
  @spec source!(String.t(), map(), [String.t()], map()) :: {atom(), atom()}
  def source!(file, entry, keys, dictionaries) do
    case for(key <- keys, is_binary(entry[key]), do: {atom(key), entry[key]}) do
      [{kind, value}] ->
        {kind, id!(file, value, value, dictionaries, kind)}

      # ⚠ Единственное сообщение этого модуля, НЕ называющее запись, и назвать
      # её тут нечем: запись назвала два источника (или ни одного), то есть
      # своего единственного имени у неё как раз и нет. Печатать одно из двух
      # значило бы выбрать за автора, какое из них настоящее.
      other ->
        raise "#{file}: an entry names #{length(other)} sources, expected one"
    end
  end

  # An empty dictionary means the file has not arrived, not that the id is
  # unknown — the same distinction all seven readers used to make in seven
  # copies. The distinction is live: a temporarily removed `skills.json` must
  # not fail the build by accusing the markup of a typo.
  #
  # ⚠ До задачи 3.46 каждая копия ссылалась на соседей по именам их функций
  # («the same distinction `skill_targets/2` and `hp_class!/3` make»), и половина
  # этих имён к тому дню уже не существовала. Указатель на соседа, которого правят
  # отдельно от тебя, протухает молча — здесь его нет вовсе, потому что копия
  # осталась одна.
  @doc "Имя из разметки, приведённое к id и сверенное со своим словарём."
  @spec id!(String.t(), String.t(), String.t() | nil, map(), atom()) :: atom()
  def id!(file, record, value, dictionaries, kind) do
    {dictionary_key, word} = Map.fetch!(@source_dictionaries, kind)
    dictionary = Map.fetch!(dictionaries, dictionary_key)
    id = atom(value)

    if map_size(dictionary) > 0 and not Map.has_key?(dictionary, id) do
      raise "#{file}: #{record} names #{word} #{value}, which does not exist"
    end

    id
  end

  @doc "Вердикт записи по словарю её файла; четвёртое слово у каждого своё."
  @spec verdict!(String.t(), map(), %{String.t() => atom()}, String.t()) :: atom()
  def verdict!(file, entry, verdicts, record) do
    Map.get(verdicts, entry["verdict"]) ||
      raise "#{file}: #{record} states unknown verdict #{inspect(entry["verdict"])}"
  end

  # Имя берётся из тех же полей и в том же порядке, что и источник, поэтому
  # порядок `keys` — данные, а не оформление: запись, назвавшая и `feat`, и
  # `class`, до этой функции не доходит вовсе (`source!/4` роняет сборку), так
  # что «первое непустое» здесь не выбор из двух, а единственное непустое.
  @doc "Имя записи для сообщений — то же поле, которым она называет свой источник."
  @spec name(map(), [String.t()]) :: String.t()
  def name(entry, keys), do: Enum.find_value(keys, "an entry", &entry[&1])

  @doc """
  Величина `applied`-записи, сверенная со списком форм, которые ядро умеет считать.

  ⚠ Список форм у каждого файла **у́же**, чем то, что файл несёт, и это сторож
  вместо реализации: форма, описанная в данных, но никем не считаемая, лежит
  на отвергнутых записях как материал, а перевод такой записи в `applied` роняет
  сборку вместо того, чтобы молча прибавить ноль. Ровно так `class_level_sum`
  дождался своего читателя (замер F7), а `ability_modifier` у атаки ждёт до сих
  пор.
  """
  @spec amount!(String.t(), String.t(), atom(), [String.t()], map() | nil) :: map() | nil
  def amount!(file, name, verdict, applied_kinds, amount) do
    cond do
      verdict != :applied ->
        amount

      is_nil(amount) ->
        raise "#{file}: #{name} is `applied` but states no amount"

      to_string(amount.kind) not in applied_kinds ->
        raise "#{file}: #{name} is `applied` with amount kind #{amount.kind}, which is not " <>
                "one the rules core computes"

      true ->
        amount
    end
  end

  @doc "Целое число там, где источник называет число; `what` — что именно считается."
  @spec number!(String.t(), String.t(), term(), String.t()) :: integer()
  def number!(_file, _name, value, _what) when is_integer(value), do: value

  def number!(file, name, value, what) do
    raise "#{file}: #{name} states #{inspect(value)} where #{what} was expected"
  end

  # Закрытый список из шести характеристик — один и тот же у всех четырёх файлов,
  # которые вообще называют характеристику (AC, характеристики, сейвы, атака).
  # Здесь домена нет: «какие бывают характеристики» не зависит от того, к чему
  # прибавляется, — а вот ЧТО с ней делают, решает каждый файл сам (у сейвов
  # к ней прилагается `floor` из-за `Divine grace`, у AC — нет).
  @doc "Имя характеристики из разметки, сверенное с шестёркой листа персонажа."
  @spec ability!(String.t(), String.t(), term()) :: atom()
  def ability!(file, record, value) when is_binary(value) do
    id = atom(value)
    if id in @abilities, do: id, else: raise("#{file}: #{record} names ability #{value}")
  end

  def ability!(file, record, other) do
    raise "#{file}: #{record} states #{inspect(other)} where an ability was expected"
  end

  @doc """
  Таблица «уровень класса → значение», как её печатает колонка прогрессии.

  Читается ТОЛЬКО форма таблицы; что означают её значения — сумму шагов или
  нарастающий итог — решает каждый файл сам и говорит об этом у своего вызова.
  Разница не косметическая: `ability_at_class_level` СКЛАДЫВАЕТСЯ, а
  `ac_at_class_level`, `save_at_class_level` и `attack_at_class_level` — итоги,
  из которых берётся достигнутый.
  """
  @spec steps!(String.t(), String.t(), map() | term(), String.t(), (term() -> term())) :: map()
  def steps!(file, name, %{} = steps, _what, value) do
    Map.new(steps, fn {level, at_level} ->
      case Integer.parse(to_string(level)) do
        {class_level, ""} when class_level >= 1 ->
          {class_level, value.(at_level)}

        _ ->
          raise "#{file}: #{name} states class level #{inspect(level)}"
      end
    end)
  end

  def steps!(file, name, other, what, _value) do
    raise "#{file}: #{name} states #{inspect(other)} where a table of class level => #{what} " <>
            "was expected"
  end

  @doc """
  Запрет стороны капа там, где никакого капа не объявлено ни одним ruleset'ом.

  ⚠ Это ПРОТИВОПОЛОЖНОСТЬ тому, что делают файлы сейвов, атаки и навыков, а не
  упущение: `stat_caps` называет пять потолков, и ни один из них не про HP и не
  про сопротивление заклинаниям. Названная сторона была бы утверждением о
  потолке, которого никто не записывал.
  """
  @spec cap_forbidden!(String.t(), String.t(), map(), String.t()) :: :ok
  def cap_forbidden!(file, name, entry, stat) do
    if Map.has_key?(entry, "cap") do
      raise "#{file}: #{name} states a `cap` side, and no ruleset states a ceiling on " <>
              "#{stat} at all — see _cap_decision in the file"
    end

    :ok
  end
end
