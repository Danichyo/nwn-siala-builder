defmodule BuildCalculatorWeb.BuilderStageNavIllegalTest do
  @moduledoc """
  Задача 4.35: лента секций уровня не ставит «✓ готово» секции, чьё решение
  лестница называет нарушением правил, — ставит ⚠ (`data-illegal="1"`).

  До задачи уровень с нелегальной прибавкой (4.37–4.38) показывал в ленте
  «✓ Стат», уровень с нелегальным фитом — «✓ Фиты», с нелегальным классом —
  «✓ Класс»: ложная законность на том же экране, где лестница рядом горит ⚠.
  Отметка ставится на ту секцию, чьё решение назвала лестница
  (`Labels.ladder_issue_entries/2` — одна прогонка на обе), — не второй
  проверкой.

  Ожидание решения (`data-state`) отметка не трогает: снять нелегальное —
  не решение, которого ждёт уровень (гид к нему не ведёт).

  Редакция — умолчательная (Сиала); билды приходят ссылкой, как к игроку:
  конструктор сам такой билд не соберёт, его приносит правка более раннего
  решения или старая ссылка.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.{Data, Encoding}
  alias BuildCalculator.Rules.Build

  setup do
    %{ruleset: Data.ruleset!(Data.default_version())}
  end

  # Человек, воин 8, STR 14 / DEX 14 покупкой, прибавки на 4-м и 8-м — легален.
  defp build(ruleset, fields) do
    Build.new(
      [
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :lawful_good,
        levels: List.duplicate(:fighter, 8),
        base_abilities: %{str: 14, dex: 14, con: 12, int: 10, wis: 10, cha: 8},
        ability_increases: %{4 => :str, 8 => :str}
      ] ++ fields
    )
  end

  defp open(conn, %Build{} = build, level),
    do: live(conn, ~p"/?b=#{Encoding.encode(build)}&l=#{level}")

  defp illegal_items(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#stage-nav-list [data-illegal='1']")
    |> Enum.map(&(LazyHTML.attribute(&1, "id") |> List.first()))
  end

  test "законный билд — ни одной отметки, у сделанного галочка", %{conn: conn, ruleset: ruleset} do
    {:ok, view, _html} = open(conn, build(ruleset, []), 4)

    assert illegal_items(view) == []
    assert has_element?(view, "#stage-nav-increase[data-state='done'] .stage-nav-mark", "✓")
    refute has_element?(view, "#stage-nav-list .stage-nav-illegal")
  end

  test "прибавка не на своём уровне — ⚠ у «Стат» вместо галочки", %{conn: conn, ruleset: ruleset} do
    stray = build(ruleset, ability_increases: %{4 => :str, 5 => :dex, 8 => :str})
    {:ok, view, _html} = open(conn, stray, 5)

    assert illegal_items(view) == ["stage-nav-increase"]
    assert has_element?(view, "#stage-nav-increase .stage-nav-illegal", "⚠")
    refute has_element?(view, "#stage-nav-increase .stage-nav-mark")

    # Причина — та же фраза, что у ⚠ на строке уровня: в `title` и словами.
    assert has_element?(
             view,
             "#stage-nav-increase[title='+1 DEX: уровень 5 прибавки к характеристике не даёт']"
           )

    assert has_element?(view, "#stage-nav-increase .sr-only", "здесь нарушение правил")
    refute has_element?(view, "#stage-nav-increase .sr-only", "готово")

    # Класс уровня законен — у него по-прежнему галочка.
    assert has_element?(view, "#stage-nav-class .stage-nav-mark", "✓")

    # Сняли — секции нет, отметок в ленте нет.
    view |> element("#increase-remove") |> render_click()
    refute has_element?(view, "#stage-nav-increase")
    assert illegal_items(view) == []
  end

  test "нелегальный фит — ⚠ у «Фиты» на его уровне и только на нём", %{
    conn: conn,
    ruleset: ruleset
  } do
    # `Cleave` требует STR 13 (и `Power attack`), а покупка дала 12.
    weak =
      build(ruleset,
        base_abilities: %{str: 12, dex: 14, con: 14, int: 12, wis: 12, cha: 10},
        feats: %{
          1 => %{:general => :dodge, {:class_bonus, :fighter} => :power_attack},
          2 => %{{:class_bonus, :fighter} => :cleave}
        }
      )

    {:ok, view, _html} = open(conn, weak, 2)

    assert illegal_items(view) == ["stage-nav-feats"]
    assert has_element?(view, "#stage-nav-feats[title^='Cleave']")
    refute has_element?(view, "#stage-nav-feats .stage-nav-mark")

    # Ожидание решения отметка не трогает: слот занят — «сделано».
    assert has_element?(view, "#stage-nav-feats[data-state='done']")

    # Уровень без нарушения — без отметки.
    {:ok, view, _html} = open(conn, weak, 3)
    assert illegal_items(view) == []
  end

  test "нелегальный класс уровня — ⚠ у «Класс»", %{conn: conn, ruleset: ruleset} do
    wm = build(ruleset, levels: List.duplicate(:fighter, 4) ++ [:weapon_master])
    {:ok, view, _html} = open(conn, wm, 5)

    assert "stage-nav-class" in illegal_items(view)
    assert has_element?(view, "#stage-nav-class[title*='BAB']")
    refute has_element?(view, "#stage-nav-class .stage-nav-mark")
  end

  # Мировоззрение не выбрано, а класс его требует: лестница говорит одной
  # строкой на 1-м уровне («ещё не выбрано»), и ⚠ встаёт у «Мировоззрения»,
  # где это чинится, а не у «Класса».
  test "класс требует мировоззрения, а оно не выбрано — ⚠ у «Мировоззрение» на 1-м", %{
    conn: conn,
    ruleset: ruleset
  } do
    paladin = build(ruleset, alignment: nil, levels: [:paladin, :paladin])
    {:ok, view, _html} = open(conn, paladin, 1)

    assert illegal_items(view) == ["stage-nav-alignment"]

    # Ждёт решения по-прежнему — янтарь остаётся, ⚠ стоит поверх.
    assert has_element?(view, "#stage-nav-alignment[data-state='hold']")
    assert has_element?(view, "#stage-nav-alignment .sr-only", "здесь нужно решение")
    assert has_element?(view, "#stage-nav-alignment .sr-only", "здесь нарушение правил")
  end
end
