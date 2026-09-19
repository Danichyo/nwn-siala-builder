defmodule BuildCalculatorWeb.BuilderLoadCodeResetTest do
  @moduledoc """
  Задача 3.226, часть A: билд, пришедший ИЗ АДРЕСА, обязан забывать уровневое
  UI-состояние прежнего билда так же полно, как его забывают клик по лестнице
  (`go_to_level/2`) и применённый импорт (`apply_imported/5`).

  Путь достижим в живой сессии без единой нашей правки: `handle_params/3` зовёт
  `load_code/3` всякий раз, когда `b` в адресе разошёлся с `@code` — «Назад» /
  «Вперёд» браузера и переход по другой ссылке `?b=` в той же вкладке. В тесте
  ровно это и есть `render_patch/2`.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.Build

  setup do
    %{ruleset: Data.ruleset!(Data.default_version())}
  end

  # ⚠️ Раса и мировоззрение НЕ названы намеренно: без них `level_ceiling/2`
  # держит `active` на уже взятом уровне (задача 3.69), то есть и открытая
  # ссылка, и патч приземляются на последний уровень билда, где слоты фитов
  # есть. С расой оба уехали бы на `taken + 1` — пустой уровень без класса,
  # без слотов и без карточки, и предмет проверки исчез бы с экрана.
  defp build(ruleset, levels) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: levels,
      base_abilities: %{str: 13, dex: 15, con: 10, int: 10, wis: 10, cha: 10}
    )
  end

  describe "чип слота фита" do
    # Воин 1 → воин 1-2: бонусный слот Воина есть на ОБОИХ уровнях, значит
    # тот же самый узел DOM остаётся на экране, и подсветку можно спросить
    # у него напрямую, а не по её отсутствию.
    test "подсветка не переезжает на билд из адреса", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter]))}")

      view |> element("#slot-filter-class_bonus-fighter") |> render_click()
      assert has_element?(view, "#slot-chip-class_bonus-fighter[data-focused='1']")
      assert has_element?(view, "#slot-filter-hint")

      render_patch(view, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter, :fighter]))}")

      assert has_element?(view, "#slot-chip-class_bonus-fighter")
      refute has_element?(view, "#slot-chip-class_bonus-fighter[data-focused='1']")
      refute has_element?(view, "#slot-filter-hint")
    end

    # Хуже того: слота, которым отфильтрован список, на новом уровне может
    # не быть вовсе. Волшебник 1 бонусного слота не имеет — подсказка
    # «показаны только фиты, которые примет этот слот» указывала бы на чип,
    # которого на экране нет, а список фитов оставался бы урезанным.
    test "фильтр снимается, даже если такого слота у нового билда нет", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter]))}")

      view |> element("#slot-filter-class_bonus-fighter") |> render_click()
      assert has_element?(view, "#slot-filter-hint")

      render_patch(view, ~p"/?b=#{Encoding.encode(build(ruleset, [:wizard]))}")

      refute has_element?(view, "#slot-chip-class_bonus-fighter")
      refute has_element?(view, "#slot-filter-hint")

      # Положительный контроль: общий слот 1-го уровня на экране есть и
      # ничем не подсвечен — то есть чипы рисуются, просто фильтр снят.
      assert has_element?(view, "#slot-chip-general")
      refute has_element?(view, "#slot-chip-general[data-focused='1']")
    end
  end

  describe "превью (призрачные +N)" do
    test "наведение прежнего билда не переезжает на билд из адреса", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter]))}")

      render_hook(view, "preview", %{"kind" => "class", "id" => "fighter"})
      assert has_element?(view, "#delta-box[data-live='1']")

      render_patch(view, ~p"/?b=#{Encoding.encode(build(ruleset, [:wizard]))}")

      assert has_element?(view, "#delta-box[data-live='0']")
    end

    # Вторая форма превью — наведение на РАСУ; она живёт в том же ассайне,
    # но приходит с карточки уровня 1, то есть с другого места экрана.
    test "наведение на расу снимается тем же патчем", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build(ruleset, [:fighter]))}")

      render_hook(view, "preview", %{"kind" => "race", "id" => "human"})
      assert has_element?(view, "#delta-box[data-live='1']")

      render_patch(view, ~p"/?b=#{Encoding.encode(build(ruleset, [:wizard]))}")

      assert has_element?(view, "#delta-box[data-live='0']")
    end
  end
end
