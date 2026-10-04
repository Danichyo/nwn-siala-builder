defmodule BuildCalculatorWeb.EditionHelpers do
  @moduledoc """
  Поднять в тесте другую редакцию (задача 4.2) — и вернуть прежнюю после.

  Редакция — настройка ПРИЛОЖЕНИЯ (`config :build_calculator, :edition`),
  а не соединения: её читает каждый запрос и каждый LiveView. Поэтому тест,
  который её меняет, обязан быть синхронным (`async: false`, причина — в его
  модуледоке, CLAUDE.md §7), а менять её — только через `use_edition/1`:

    * вместе с редакцией переключается и ruleset ядра по умолчанию
      (`BuildCalculatorWeb.Edition.configure!/0` пишет
      `:default_ruleset`) — иначе сайт и ядро разошлись бы молча;
    * явные перекрытия флагов интерфейса снимаются на время теста.
      Синхронные тесты флагов (`import_ui_test.exs` и соседи) в `on_exit`
      кладут умолчание Сиалы ЯВНЫМ значением, а явное значение перекрывает
      пресет — без снятия ванильный тест видел бы флаги Сиалы в зависимости
      от порядка файлов;
    * по выходу всё возвращается ровно как было — значение на место,
      отсутствующий ключ снова отсутствует.
  """

  alias BuildCalculatorWeb.Edition

  @flags [:accounts_ui, :import_ui, :game_log_import_ui, :guide_first, :analytics]
  @keys [:edition, :default_ruleset | @flags]

  @doc "Включает редакцию `edition` до конца теста."
  @spec use_edition(atom()) :: :ok
  def use_edition(edition) when is_atom(edition) do
    snapshot = for key <- @keys, do: {key, Application.fetch_env(:build_calculator, key)}
    ExUnit.Callbacks.on_exit(fn -> restore(snapshot) end)

    Enum.each(@flags, &Application.delete_env(:build_calculator, &1))
    Application.put_env(:build_calculator, :edition, edition)
    Edition.configure!()
  end

  defp restore(snapshot) do
    for {key, value} <- snapshot do
      case value do
        {:ok, value} -> Application.put_env(:build_calculator, key, value)
        :error -> Application.delete_env(:build_calculator, key)
      end
    end

    :ok
  end
end
