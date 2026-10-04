defmodule BuildCalculator.Data.Loader.NotAGap do
  @moduledoc """
  Сторож поля `not_a_gap` — решения владельца о том, что запись пробелом не является.

  Поле снимает запись со счёта пробелов, то есть это **единственный способ
  уменьшить число, которое калькулятор показывает игроку, ничего не посчитав**.
  Без автора, цитаты и довода им можно было бы гасить неудобные записи одной
  строкой, и баннер «перенесено не полностью — N пробелов» перестал бы что-либо
  значить. Поэтому три поля обязательны везде: `who`, `why`, `quote`.

  ⚠ **Это ОДНА реализация вместо четырёх копий.** Поле читают четыре семейства
  данных, и до задачи 3.95 сторож был переписан у каждого своими словами:
  факты класса (`Loader.Classes`, задачи 3.74–3.75), записи семи файлов
  разметки (`Loader.BonusMarkup`, задача 3.76), оружие сиальской системы
  (`Loader.Races`, задача 3.82) и — с 3.95 — метки получателей эффекта
  (`Loader.Feats.feat_effect_receivers/3`). Четвёртая копия и была поводом
  свести их: четыре формулировки одного правила расходятся молча.

  ## `basis` — довод, названный машиночитаемо

  Три обязательных поля отвечают на «кто и почему», но не на «на чём это
  стоит», а стоять решение может на разном: у `Trackless step` условие —
  местность, то есть состояние мира; у условных прибавок задачи 3.95 — на том,
  что число и условие уже названы в ОПИСАНИИ фита, которое игрок видит
  в конструкторе (3.87) и на экране просмотра (3.94).

  Разница не риторическая: второй довод **проверяем**, и его надо проверять.
  Описание бывает пустым (сиальские фиты владения оружием, у которых страницы
  на Fandom нет вовсе), и у такого фита довод не объясняет ничего — оговорка
  обязана остаться. `basis: "feat_description"` роняет сборку у фита без
  описания, то есть решение не может стать ложью после правки данных.

  ⚠ **Словарь доводов объявляет ВЫЗЫВАЮЩАЯ сторона** (`bases:`), а не этот
  модуль на всех. Семейство, которое довода не объявляет, не имеет права его
  и написать: поле, которого никто не читает, выглядит сделанной работой
  и ничего не делает. Сегодня словарь объявляют два семейства из четырёх —
  разметка прибавок и метки получателей, — потому что у обоих запись знает
  свой фит и описание есть чем проверить.
  """

  # Закрытый словарь доводов. Значение — что довод утверждает; сообщение
  # Закрытый словарь доводов, в алфавитном порядке. Что каждый утверждает —
  # в `bases/0` ниже, а не значением рядом с ключом: сообщение сторожа печатает
  # только имена, и вторая копия объяснения рассыхалась бы молча.
  #
  #   * `feat_description` — прибавка реальна и узка, а её число и условие
  #     названы в описании фита, которое игрок видит в конструкторе
  #     и на экране просмотра билда (задачи 3.87 и 3.94);
  #   * `world_state` — условие описывает состояние мира или боя, а не свойство
  #     билда: местность, освещение, включённый режим.
  @bases ["feat_description", "world_state"]

  @description_basis "feat_description"

  @doc """
  Доводы, которые сторож умеет проверить, в алфавитном порядке.

  Передаётся вызывающей стороной в `bases:`, а не читается отсюда молча:
  словарь закрыт для всех, но объявляет его каждое семейство за себя.

    * `"feat_description"` — «описание фита уже назвало и число, и условие».
      Проверяем: `verify!/3` роняет сборку, если у фита описания нет;
    * `"world_state"` — «условие называет состояние мира, а не свойство билда»
      (`Trackless step`, `Stonecunning`; решение Dan 22.08.2026).
  """
  @spec bases() :: [String.t()]
  def bases, do: @bases

  @doc """
  Проверить решение владельца или ничего не делать, если его нет.

  `where` — файл и запись одной строкой (`"ac_bonuses.json: dodge"`): сообщение,
  не называющее ни файла, ни записи, заставляет искать опечатку руками, а весь
  смысл сторожа в том, что решение не может быть записано наполовину.

  Опции:

    * `:bases` — словарь доводов, которые это семейство объявляет. Есть словарь —
      поле `basis` обязательно и сверяется с ним; нет словаря — поле запрещено;
    * `:describes` — `{feat_id, словарь фитов}` там, где у записи есть свой фит.
      Нужно только доводу `feat_description`, и его отсутствие у такой записи
      само по себе роняет сборку.

  Отсутствующее или не-`map` решение — это «решения нет», и тогда сторожу нечего
  проверять. Роняет сборку ровно наполовину записанное решение.
  """
  @spec verify!(String.t(), term(), keyword()) :: :ok
  def verify!(where, decision, opts \\ [])

  def verify!(where, %{} = decision, opts) do
    for field <- ["who", "why", "quote"], do: named!(where, decision, field)

    case Keyword.fetch(opts, :bases) do
      {:ok, allowed} -> basis!(where, named!(where, decision, "basis"), allowed, opts)
      :error -> no_basis!(where, decision)
    end

    :ok
  end

  def verify!(_where, _decision, _opts), do: :ok

  defp named!(where, decision, field) do
    value = decision[field]

    if not is_binary(value) or String.trim(value) == "" do
      raise "#{where}: `not_a_gap` without a non-empty `#{field}` — a record can only " <>
              "leave the gap count with its owner, the quote and the reason named"
    end

    value
  end

  # Семейство словаря не объявило — значит поле здесь никто не читает, и
  # написанное в нём выглядело бы решением, не будучи им.
  defp no_basis!(where, decision) do
    if Map.has_key?(decision, "basis") do
      raise "#{where}: `not_a_gap` states a `basis`, and nothing reads it in this file — " <>
              "a field nobody checks looks like a decision without being one"
    end

    :ok
  end

  defp basis!(where, basis, allowed, opts) do
    unless basis in allowed do
      raise "#{where}: `not_a_gap` states basis #{inspect(basis)}; this file knows " <>
              "#{inspect(Enum.sort(allowed))}"
    end

    if basis == @description_basis, do: described!(where, opts), else: :ok
  end

  # 🔴 Довод «описание всё сказало» держится ровно на том, что описание есть.
  # У фита без него оговорка обязана остаться — иначе решение владельца
  # превращается в молчание, а молчание про непосчитанное и есть та ошибка,
  # ради которой заведён весь механизм пробелов.
  defp described!(where, opts) do
    case Keyword.get(opts, :describes) do
      {id, feats} when is_map(feats) ->
        description!(where, id, feats)

      _ ->
        raise "#{where}: `not_a_gap` stands on basis #{inspect(@description_basis)}, and this " <>
                "record names no feat whose description could be checked"
    end
  end

  # Пустой словарь — это «файл фитов не приехал», а не «фита нет»: то же
  # различение, которое делает `BonusMarkup.id!/5`, и по той же причине —
  # временно убранный справочник не имеет права обвинить разметку в опечатке.
  defp description!(_where, _id, feats) when map_size(feats) == 0, do: :ok

  defp description!(where, id, feats) do
    case Map.get(feats, id) do
      %{description: text} when is_binary(text) ->
        if String.trim(text) == "" do
          raise "#{where}: `not_a_gap` stands on the description of #{id}, which is empty"
        end

        :ok

      _ ->
        raise "#{where}: `not_a_gap` stands on the description of #{id}, which states none — " <>
                "the caveat has to stay, because there is nothing for the player to read instead"
    end
  end
end
