defmodule BuildCalculatorWeb.HighlightTest do
  @moduledoc """
  Подсветка нечёткого поиска не имеет права разрывать слово.

  ⚠️ Это единственное место в тестах, где проверяется СЫРОЙ HTML, а не `element/2`
  (AGENTS.md, CLAUDE.md §7). Оговорка сознательная: проверяемое здесь — именно
  лишний пробел в разметке, то есть ровно то, чего в разобранном DOM уже не видно.
  Селектором такой дефект не поймать по построению.

  ⚠️ **Инвариант — «текст собирается обратно», а НЕ «между тегами нет пробела».**
  Первая редакция проверяла `refute html =~ ~r|</span>\s+<span|` и **зеленела
  на сломанной разметке**: там пробелы лежали ВНУТРИ обёртки, между `<span>`
  и `<mark>`, а не между обёртками. Классическая пустая проверка
  (`AGENT_QUEUE.md`: «`refute` зеленеет и там, где проверяемое не попало в поле
  зрения»). Проверено намеренной порчей: на старой разметке падает только
  сборка текста. Регулярку «нет пробела между тегами» вернуть нельзя и по второй
  причине — сегмент-промах бывает ровно пробелом («Power Attack», совпали `r`
  и `A`), и такая проверка ругалась бы на законную выдачу.

  История: жалоба Dan 15.08.2026 — «Dodge» при поиске «dod» читался как
  «Dod» «ge». Причина была в переносах строк внутри `<%= if %>`: каждый
  становился текстовым узлом. Чинилось дважды, и первый раз мимо — сняли
  `padding` у `.hl`, а зазор остался.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculatorWeb.BuilderComponents

  defp mark(segments) do
    render_component(&BuilderComponents.highlight/1, segments: segments)
  end

  describe "highlight/1" do
    test "жалоба Dan: «Uncanny dodge» не разрывается на «dod» и «ge»" do
      text =
        [{:miss, "Uncanny "}, {:hit, "dod"}, {:miss, "ge"}]
        |> mark()
        |> String.replace(~r/<[^>]*>/, "")

      assert text == "Uncanny dodge"
    end

    test "слово собирается обратно буква в букву" do
      text =
        [{:miss, "Sha"}, {:hit, "do"}, {:miss, "w "}, {:hit, "d"}, {:miss, "aze"}]
        |> mark()
        |> String.replace(~r/<[^>]*>/, "")

      assert text == "Shadow daze"
    end

    test "совпавшее помечено классом, остальное — нет" do
      html = mark([{:miss, "Rapi"}, {:hit, "d"}])

      assert html =~ ~s(class="hl")

      # Положительный контроль: не всё подряд получило класс.
      assert html |> String.split(~s(class="hl")) |> length() == 2
    end
  end
end
