defmodule BuildCalculator.Repo.Migrations.CreateAnalytics do
  @moduledoc """
  Задача 4.54: счётчик посещений и событий калькулятора (`BuildCalculator.Analytics`).

  🔴 Ни одного билда в этих таблицах — главный сторож задачи. Страница пишется
  шаблоном маршрута (`/b/:code`, а не код), query отбрасывается кроме `utm_*`,
  источник — только хост, событие — только имя (и редакция с ruleset'ом). Сырой
  IP и User-Agent не хранятся: посетитель — 16 байт хеша с солью дня, соль живёт
  только в памяти (`BuildCalculator.Analytics.Salt`).

  ## Своя схема Postgres, а не таблицы рядом с билдами

  Grafana читает эти таблицы напрямую ролью только на чтение (VANILLA.md 4.54).
  Отдельная схема `analytics` делает границу роли структурной: `USAGE` на схему
  и `SELECT` на всё в ней — и роль физически не видит `builds`, `short_links`
  и `users` в `public`. Список таблиц в `GRANT` не протухает: новая таблица
  аналитики попадает под `ALTER DEFAULT PRIVILEGES` той же схемы.

  ## Сырые строки, а не дневные счётчики

  Уникальных посетителей по дню и странице счётчик с upsert не даёт: «уникальный»
  требует хранить хеши посетителей так или иначе. Строка на посещение — около
  сотни байт, сотни–тысячи строк в день; Grafana считает `count(DISTINCT visitor)`
  сама. Представления `daily_*` ниже — готовые срезы для панелей.

  ## Длины — вторая линия против «кода в строке»

  Значения режутся в приложении (`BuildCalculatorWeb.Analytics.Client`); `CHECK`
  на длину здесь не даёт ни одной колонке принять код билда целиком даже при
  ошибке в коде: код длинного билда — сотни знаков (`Encoding`), а самая
  длинная колонка — хост на 253.
  """
  use Ecto.Migration

  @schema "analytics"

  def up do
    execute "CREATE SCHEMA #{@schema}"

    create table(:visits, prefix: @schema) do
      # День соли (UTC): уникальный посетитель различим только внутри него.
      add :day, :date, null: false
      add :edition, :text, null: false

      # Шаблон маршрута из роутера (`Phoenix.Router.route_info/4`), не путь.
      add :page, :text, null: false
      # Первые 16 байт SHA-256(соль дня, IP, User-Agent).
      add :visitor, :binary, null: false
      add :referrer_host, :text
      add :utm_source, :text
      add :utm_medium, :text
      add :utm_campaign, :text
      add :utm_term, :text
      add :utm_content, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:visits, [:day, :page], prefix: @schema)

    create constraint(:visits, :visits_lengths,
             prefix: @schema,
             check: """
             char_length(edition) <= 32 AND char_length(page) <= 64
             AND octet_length(visitor) = 16
             AND (referrer_host IS NULL OR char_length(referrer_host) <= 253)
             AND (utm_source IS NULL OR char_length(utm_source) <= 64)
             AND (utm_medium IS NULL OR char_length(utm_medium) <= 64)
             AND (utm_campaign IS NULL OR char_length(utm_campaign) <= 64)
             AND (utm_term IS NULL OR char_length(utm_term) <= 64)
             AND (utm_content IS NULL OR char_length(utm_content) <= 64)
             """
           )

    create table(:events, prefix: @schema) do
      add :day, :date, null: false
      add :edition, :text, null: false
      # Имя из закрытого списка `BuildCalculator.Analytics.events/0`.
      add :name, :text, null: false

      # Версия ruleset'а билда (`siala_41`, `vanilla`) — где событие о билде.
      add :ruleset, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:events, [:day, :name], prefix: @schema)

    create constraint(:events, :events_lengths,
             prefix: @schema,
             check: """
             char_length(edition) <= 32 AND char_length(name) <= 64
             AND (ruleset IS NULL OR char_length(ruleset) <= 32)
             """
           )

    # Срезы для панелей Grafana: время панели — `day::timestamp AS time`.
    # Уникальные по дню считаются в каждом срезе заново — сумма уникальных
    # по страницам не равна уникальным за день.
    execute """
    CREATE VIEW #{@schema}.daily_totals AS
    SELECT day, edition, count(*) AS visits, count(DISTINCT visitor) AS visitors
    FROM #{@schema}.visits
    GROUP BY day, edition
    """

    execute """
    CREATE VIEW #{@schema}.daily_pages AS
    SELECT day, edition, page, count(*) AS visits, count(DISTINCT visitor) AS visitors
    FROM #{@schema}.visits
    GROUP BY day, edition, page
    """

    execute """
    CREATE VIEW #{@schema}.daily_sources AS
    SELECT day, edition, referrer_host, utm_source, utm_medium, utm_campaign,
           utm_term, utm_content,
           count(*) AS visits, count(DISTINCT visitor) AS visitors
    FROM #{@schema}.visits
    WHERE referrer_host IS NOT NULL OR utm_source IS NOT NULL OR utm_medium IS NOT NULL
       OR utm_campaign IS NOT NULL OR utm_term IS NOT NULL OR utm_content IS NOT NULL
    GROUP BY day, edition, referrer_host, utm_source, utm_medium, utm_campaign,
             utm_term, utm_content
    """

    execute """
    CREATE VIEW #{@schema}.daily_events AS
    SELECT day, edition, name, ruleset, count(*) AS events
    FROM #{@schema}.events
    GROUP BY day, edition, name, ruleset
    """
  end

  def down do
    execute "DROP VIEW #{@schema}.daily_events"
    execute "DROP VIEW #{@schema}.daily_sources"
    execute "DROP VIEW #{@schema}.daily_pages"
    execute "DROP VIEW #{@schema}.daily_totals"

    drop table(:events, prefix: @schema)
    drop table(:visits, prefix: @schema)

    # Без CASCADE: чужой объект в схеме — повод остановиться, а не снести его молча.
    execute "DROP SCHEMA #{@schema}"
  end
end
