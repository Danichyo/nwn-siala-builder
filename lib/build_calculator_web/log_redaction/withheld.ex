defmodule BuildCalculatorWeb.LogRedaction.Withheld do
  @moduledoc """
  Пометка на месте значения, снятого из события лога
  (`BuildCalculatorWeb.LogRedaction`): что там было — вид и размер,
  без содержимого. Печатается `#Withheld<map, 37 keys>`.
  """
  @enforce_keys [:what]
  defstruct [:what]

  @type t :: %__MODULE__{what: String.t()}

  defimpl Inspect do
    def inspect(%{what: what}, _opts), do: "#Withheld<" <> what <> ">"
  end
end
