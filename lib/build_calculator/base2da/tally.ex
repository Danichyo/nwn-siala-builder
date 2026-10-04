defmodule BuildCalculator.Base2da.Tally do
  @moduledoc """
  Счёт одной области сверки: сколько сравнений сделано и какие разошлись
  (задача 4.5). Число сравнений печатается в отчёте рядом с числом находок —
  без него «3 расхождения» не отличить от «3 из 3».
  """

  alias BuildCalculator.Base2da.Finding

  defstruct area: nil, title: nil, checks: 0, findings: []

  @type t :: %__MODULE__{
          area: atom(),
          title: String.t(),
          checks: non_neg_integer(),
          findings: [Finding.t()]
        }

  @spec new(atom(), String.t()) :: t()
  def new(area, title), do: %__MODULE__{area: area, title: title}

  @doc """
  Одно сравнение: `base` против `ours`. Разошлись — находка с полями из `attrs`
  (`subject`, `field`, `base_at`, `ours_at`, по желанию `kind` и `note`).
  Сравнение значений — через `same`, по умолчанию `==`.
  """
  @spec check(t(), term(), term(), keyword()) :: t()
  def check(%__MODULE__{} = tally, base, ours, attrs) do
    same = Keyword.get(attrs, :same, &Kernel.==/2)
    tally = %{tally | checks: tally.checks + 1}

    if same.(base, ours) do
      tally
    else
      add(tally, base, ours, attrs)
    end
  end

  @doc "Находка без сравнения — одна сторона молчит (несопоставленное имя)."
  @spec add(t(), term(), term(), keyword()) :: t()
  def add(%__MODULE__{} = tally, base, ours, attrs) do
    {base_text, ours_text} = render(base, ours)

    finding = %Finding{
      area: tally.area,
      subject: to_string(Keyword.fetch!(attrs, :subject)),
      field: to_string(Keyword.fetch!(attrs, :field)),
      base: base_text,
      base_at: attrs[:base_at],
      ours: ours_text,
      ours_at: attrs[:ours_at],
      kind: attrs[:kind],
      note: attrs[:note]
    }

    %{tally | findings: tally.findings ++ [finding]}
  end

  # Большие множества печатаются разностью: из двадцати трёх классов важны два,
  # которых нет с другой стороны, а не весь список дважды.
  @big 8

  defp render(%MapSet{} = base, %MapSet{} = ours) do
    if MapSet.size(base) > @big or MapSet.size(ours) > @big do
      only_base = MapSet.difference(base, ours)
      only_ours = MapSet.difference(ours, base)

      {"#{MapSet.size(base)} шт.; нет у нас: #{Finding.show(only_base)}",
       "#{MapSet.size(ours)} шт.; нет в .2da: #{Finding.show(only_ours)}"}
    else
      {Finding.show(base), Finding.show(ours)}
    end
  end

  defp render(base, ours), do: {Finding.show(base), Finding.show(ours)}

  @doc "Засчитать `n` сравнений, сделанных оптом и сошедшихся."
  @spec count(t(), non_neg_integer()) :: t()
  def count(%__MODULE__{} = tally, n), do: %{tally | checks: tally.checks + n}
end
