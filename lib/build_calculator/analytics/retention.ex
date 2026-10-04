defmodule BuildCalculator.Analytics.Retention do
  @moduledoc """
  Срок хранения строк посещений `analytics.visits` (задача 4.75) — команда,
  а не расписание.

  **Удаление данных — решение Dan**, поэтому само приложение не удаляет
  ничего и никогда: строки уходят только по явному вызову, с числом дней,
  которое назвал человек. Два входа, один текст:

    * `mix analytics.prune --keep-days N [--dry-run]` — на машине разработчика;
    * релиз: `bin/build_calculator eval "BuildCalculator.Release.analytics_prune(N)"`
      (`analytics_prune(N, true)` — только посчитать).

  `N` — сколько последних дней UTC оставить, включая сегодняшний (как
  `--days` у `mix analytics.report`): удаляются строки с `day` раньше
  `сегодня − (N − 1)`. Представления `analytics.daily_*` считаются из этих
  строк, поэтому Grafana после удаления видит историю только за `N` дней.

  ## Почему только `visits`

  В `visits` — хеш посетителя, единственное поле, похожее на персональное
  (необратимое и несравнимое между днями — соль дня, `Analytics.Salt`).
  В `analytics.events` — день, редакция, имя события и ruleset: удалять там
  нечего ради приватности, а места строки событий почти не занимают.

  ## Свёртка — не сделана

  Можно было бы перед удалением сворачивать старые дни в счётчики (визиты
  и уникальные по дню, странице, источнику) и хранить их вечно. Это новая
  таблица и новые представления для Grafana — решение о форме истории,
  а не техника; без слова Dan не заводится.
  """

  import Ecto.Query

  alias BuildCalculator.Analytics.Visit
  alias BuildCalculator.Repo

  @typedoc "Что сделала (или сделала бы) команда."
  @type result :: %{
          keep_days: pos_integer(),
          cutoff: Date.t(),
          before: non_neg_integer(),
          oldest: Date.t() | nil,
          older: non_neg_integer(),
          deleted: non_neg_integer(),
          after: non_neg_integer(),
          dry_run?: boolean()
        }

  @doc """
  Удаляет строки посещений старше последних `keep_days` дней UTC
  (`dry_run: true` — только считает). `today` — для теста.
  """
  @spec prune_visits(pos_integer(), keyword()) :: result()
  def prune_visits(keep_days, opts \\ []) when is_integer(keep_days) and keep_days >= 1 do
    dry_run? = Keyword.get(opts, :dry_run, false)
    today = Keyword.get(opts, :today, Date.utc_today())
    cutoff = Date.add(today, -(keep_days - 1))
    older = from(v in Visit, where: v.day < ^cutoff)

    before = Repo.aggregate(Visit, :count, log: false)
    oldest = Repo.one(from(v in Visit, select: min(v.day)), log: false)
    count = Repo.aggregate(older, :count, log: false)

    deleted =
      if dry_run? do
        0
      else
        {deleted, _} = Repo.delete_all(older, log: false)
        deleted
      end

    %{
      keep_days: keep_days,
      cutoff: cutoff,
      before: before,
      oldest: oldest,
      older: count,
      deleted: deleted,
      after: Repo.aggregate(Visit, :count, log: false),
      dry_run?: dry_run?
    }
  end

  @doc "Текст для консоли — что было, что удалено, что осталось."
  @spec text(result()) :: String.t()
  def text(result) do
    action =
      if result.dry_run?,
        do: "would delete #{result.older} (dry run: nothing deleted)",
        else: "deleted #{result.deleted}"

    [
      "analytics.visits: keep the last #{result.keep_days} days (day >= #{result.cutoff}, UTC)",
      "rows before: #{result.before}, oldest day: #{result.oldest || "-"}",
      "rows older than the cutoff: #{result.older}; #{action}",
      "rows after: #{result.after}",
      "analytics.events is not touched"
    ]
    |> Enum.join("\n")
  end
end
