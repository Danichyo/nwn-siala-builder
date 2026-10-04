defmodule BuildCalculatorWeb.BuilderSlotPoolTest do
  @moduledoc """
  Задача 4.61: пик в слоте, который его по нынешним правилам не берёт, и пик
  в слоте, которого уровень не даёт, — ⚠ на строке уровня, ⚠ у «Фитов» в ленте
  секций, строка в сводке экрана просмотра со своей фразой происхождения.

  Две головы ядра (`Rules.illegal_feats/2` → `validate_feat_pick/3`):

    * `{:not_in_slot_pool, slot_id}` — фит в каком-то пуле есть, но не в пуле
      этого слота. Носитель — Сиала, волшебник 5 с Brew potion в бонусном слоте
      волшебника: до задачи 4.49 законный билд (бонусный список Brew potion —
      Волшебник), после неё — Друид и Арфист. Прод Сиалы такие ссылки делал.
      Правка его не оставляет — вид прогонки `:feat_closed`, фраза `:rules`;
    * `{:slot_not_granted, slot_id}` — уровень такого слота не даёт. Оставляла его
      ПРАВКА: человек с расовым фитом менял расу (`pick_race` расовый пик
      не чистил) — вид `:feat`, фраза `:edit`. С задачи 4.62 конструктор такой
      пик снимает сам — и правкой, и при открытии ссылки
      (`builder_lost_slot_test.exs`); ⚠ остаётся на экране просмотра старой
      ссылки, его и проверяет вторая группа ниже.

  До задачи ядро не называло ни одну, и лестница молчала.

  Редакция — умолчательная (Сиала): у ванили Brew potion в бонусном слоте
  волшебника законен (`labels_test.exs`, тот же билд).
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.{Data, Encoding, Ids, Rules}
  alias BuildCalculator.Rules.Build

  setup do
    %{ruleset: Data.ruleset!(Data.default_version())}
  end

  # Человек волшебник 5, Lore 4 на 1-м; Brew potion в бонусном слоте волшебника
  # на 5-м. Ровно так его ставило ядро по правилам до 4.49 (`before_4_49/1`).
  defp brew_potion(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :human,
      alignment: :true_neutral,
      levels: List.duplicate(:wizard, 5),
      base_abilities: %{str: 8, dex: 14, con: 14, int: 18, wis: 10, cha: 8},
      skills: %{1 => %{lore: 4}},
      feats: %{5 => %{{:class_bonus, :wizard} => :brew_potion}}
    )
  end

  defp before_4_49(ruleset),
    do: put_in(ruleset.feats[:brew_potion].bonus_for, MapSet.new([:wizard]))

  defp open(conn, %Build{} = build, level),
    do: live(conn, ~p"/?b=#{Encoding.encode(build)}&l=#{level}")

  defp issue_text(view, level), do: render(element(view, "#level-#{level}-issue"))

  @pool "Brew potion: нет в списке бонусных фитов Wizard"

  describe "Brew potion в бонусном слоте волшебника — ссылка до 4.49" do
    test "по правилам до 4.49 законна, сегодня — одна претензия, пул слота", %{
      ruleset: ruleset
    } do
      build = brew_potion(ruleset)

      assert Rules.illegal_feats(build, before_4_49(ruleset)) == []

      assert Rules.illegal_feats(build, ruleset) == [
               {5, {:class_bonus, :wizard}, :brew_potion,
                {:not_in_slot_pool, {:class_bonus, :wizard}}}
             ]
    end

    test "⚠ на 5-м уровне и у «Фитов» в ленте; ✕ на чипе снимает пик и отметку", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = open(conn, brew_potion(ruleset), 5)

      assert has_element?(view, "#level-5[data-illegal='1']")
      assert issue_text(view, 5) =~ @pool

      for level <- 1..4 do
        refute has_element?(view, "#level-#{level}[data-illegal='1']")
      end

      assert has_element?(view, "#stage-nav-feats[data-illegal='1']")
      assert has_element?(view, "#stage-nav-feats[title^='Brew potion: ']")

      # Слот на уровне есть — пик виден на чипе и снимается обычным `clear_slot`.
      slot = Ids.slot_dom_id({:class_bonus, :wizard})
      assert has_element?(view, "#slot-chip-#{slot}[data-filled='1']")
      view |> element("#slot-clear-#{slot}") |> render_click()

      refute has_element?(view, "#level-5[data-illegal='1']")
      refute has_element?(view, "#stage-nav-list [data-illegal='1']")
    end

    test "экран просмотра: строка уровня и фраза «старая ссылка»", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(brew_potion(ruleset))}")

      assert render(element(view, "#view-illegal-5")) =~ @pool

      assert render(element(view, "#view-illegal-note-rules")) =~
               "Фит в слоте, который по нынешним правилам его не берёт"

      refute has_element?(view, "#view-illegal-note-edit")
      assert has_element?(view, "#view-guide-level-5[data-illegal='1']")
    end
  end

  describe "слот, которого уровень не даёт — расовый пик после смены расы" do
    @racial "Dodge: этот уровень не даёт слота «Бонус расы»"

    # До задачи 4.62 здесь же стоял тест «человек с Dodge в расовом слоте стал
    # эльфом — ⚠ на 1-м уровне»: смена расы правкой оставляла пик, и снять его
    # было нечем. Теперь его снимает воронка правок, ⚠ в конструкторе нет —
    # сценарий переехал в `builder_lost_slot_test.exs` с обратным ожиданием.

    test "экран просмотра той же ссылки: фраза «след правки», не «старая ссылка»", %{
      conn: conn,
      ruleset: ruleset
    } do
      elf =
        Build.new(
          ruleset_version: ruleset.version,
          race: :elf,
          alignment: :true_neutral,
          levels: [:wizard],
          base_abilities: %{str: 8, dex: 14, con: 14, int: 18, wis: 10, cha: 8},
          feats: %{1 => %{racial: :dodge}}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(elf)}")

      assert render(element(view, "#view-illegal-1")) =~ @racial
      assert has_element?(view, "#view-illegal-note-edit")
      refute has_element?(view, "#view-illegal-note-rules")
    end
  end
end
