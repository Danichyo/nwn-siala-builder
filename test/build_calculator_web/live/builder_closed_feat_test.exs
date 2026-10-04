defmodule BuildCalculatorWeb.BuilderClosedFeatTest do
  @moduledoc """
  Задача 4.60: фит, которого по нынешним правилам не берёт ни один слот, —
  ⚠ на строке его уровня, ⚠ у «Фитов» в ленте секций, строка в сводке экрана
  просмотра со своей фразой происхождения.

  Три отказа ядра одного семейства (`Rules.illegal_feats/2`):

    * `{:not_selectable_at_level_up, id}` — Mount actions, Mounted combat
      и Mounted archery Сиалы закрыла задача 4.49; прод Сиалы до неё ставил их
      в слоты, и такие ссылки уже есть;
    * `{:feat_disabled, id}` — шард выключает фит позже, чем собрана ссылка;
    * `{:not_slottable, type}` — обновление данных уводит фит из всех пулов
      (4.55 так увела Craft harper item).

  До задачи ядро их называло, а лестница молчала: белый список
  `Labels.@illegal_reasons` их не содержал.

  Билды приходят ССЫЛКОЙ, как к игроку: конструктор и оба импорта кладут фит
  в слот только через `FeatSlots.accepts?/3`, а он отбивает все три. Чтобы
  ссылка была настоящей, а не придуманной, у каждой из двух первых тест
  проверяет, что по ПРЕЖНИМ правилам — тот же ruleset с откатом ровно того
  флага, который сменился, — билд законен целиком (`Rules.illegal_feats/2`
  → `[]`): значит, ⚠ ставит именно новая голова, а не соседняя причина.

  Редакция — умолчательная (Сиала): все три достижимы только там. У ванили
  выключенных фитов нет, Mount actions выдан каждому базовому классу на 1-м
  (`:already_taken` помечал его в слоте и раньше), а 4.55 фиты в пулы только
  добавила — см. `labels_test.exs`, «фит, которого слотом не взять вовсе».
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.{Data, Encoding, Ids, Rules}
  alias BuildCalculator.Rules.Build

  setup do
    %{ruleset: Data.ruleset!(Data.default_version())}
  end

  # Человек, воин 1, Ride 4: Mount actions в общем слоте, Mounted combat
  # в расовом, Mounted archery в бонусном слоте воина. Ровно так их разложило
  # ядро по правилам до задачи 4.49 (подбор слотов `FeatSlots.accepts?/3`
  # и `validate_feat_pick/3` с откатанным флагом, журнал задачи).
  @mounted [:mount_actions, :mounted_combat, :mounted_archery]

  defp mounted(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :human,
      alignment: :lawful_good,
      levels: [:fighter],
      base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8},
      skills: %{1 => %{ride: 4}},
      feats: %{
        1 => %{
          :general => :mount_actions,
          :racial => :mounted_combat,
          {:class_bonus, :fighter} => :mounted_archery
        }
      }
    )
  end

  defp before_4_49(ruleset),
    do:
      Enum.reduce(@mounted, ruleset, fn id, acc ->
        put_in(acc.feats[id].level_up_selectable?, true)
      end)

  # Полуорк, воин 22, сила 18 + пять прибавок = 25: Devastating critical
  # (club) в бонусном слоте воина на 22-м, со всей цепочкой пререквизитов
  # на том же оружии. Законен, пока фит включён.
  defp devastating(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :half_orc,
      alignment: :lawful_neutral,
      levels: List.duplicate(:fighter, 22),
      base_abilities: %{str: 18, dex: 13, con: 14, int: 10, wis: 10, cha: 8},
      ability_increases: Map.new([4, 8, 12, 16, 20], &{&1, :str}),
      feats: %{
        1 => %{:general => :power_attack, {:class_bonus, :fighter} => :cleave},
        4 => %{{:class_bonus, :fighter} => :great_cleave},
        8 => %{{:class_bonus, :fighter} => {:improved_critical, :club}},
        21 => %{general: {:overwhelming_critical, :club}},
        22 => %{{:class_bonus, :fighter} => {:devastating_critical, :club}}
      }
    )
  end

  defp open(conn, %Build{} = build), do: live(conn, ~p"/?b=#{Encoding.encode(build)}")

  defp open(conn, %Build{} = build, level),
    do: live(conn, ~p"/?b=#{Encoding.encode(build)}&l=#{level}")

  defp issue_text(view, level), do: render(element(view, "#level-#{level}-issue"))

  @not_selectable "при росте персонажа не выбирается — только объявить в «Вещах»"

  describe "фит, который больше не выбирается при росте персонажа (Сиала после 4.49)" do
    test "ссылка законна по правилам до 4.49, сегодня ядро называет все три пика",
         %{ruleset: ruleset} do
      build = mounted(ruleset)

      assert Rules.illegal_feats(build, before_4_49(ruleset)) == []

      assert Enum.sort(Rules.illegal_feats(build, ruleset)) ==
               Enum.sort([
                 {1, :general, :mount_actions, {:not_selectable_at_level_up, :mount_actions}},
                 {1, :racial, :mounted_combat, {:not_selectable_at_level_up, :mounted_combat}},
                 {1, {:class_bonus, :fighter}, :mounted_archery,
                  {:not_selectable_at_level_up, :mounted_archery}}
               ])
    end

    test "⚠ на строке 1-го уровня, каждый фит назван с причиной", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = open(conn, mounted(ruleset))

      assert has_element?(view, "#level-1[data-illegal='1']")

      # Задача 4.40, пункт 17: одна причина — одна строка, три имени через запятую.
      assert issue_text(view, 1) =~
               "Mount actions, Mounted combat, Mounted archery: #{@not_selectable}"

      assert render(element(view, "#spine-illegal")) =~ "1 уровень с нарушением правил"
    end

    test "лента секций: ⚠ у «Фитов» вместо галочки; снял все три — отметок нет", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = open(conn, mounted(ruleset), 1)

      assert has_element?(view, "#stage-nav-feats[data-illegal='1']")
      assert has_element?(view, "#stage-nav-feats .stage-nav-illegal", "⚠")
      refute has_element?(view, "#stage-nav-feats .stage-nav-mark")
      assert has_element?(view, "#stage-nav-feats[title^='Mount actions, Mounted combat, ']")

      # Задача 4.40, пункт 1: причина — словами в секции фитов, по строке на слот,
      # не только в `title` (на телефоне его нет).
      for {slot, label, name} <- [
            {:general, "Общий", "Mount actions"},
            {:racial, "Бонус расы", "Mounted combat"},
            {{:class_bonus, :fighter}, "Бонус Fighter", "Mounted archery"}
          ] do
        dom = Ids.slot_dom_id(slot)
        assert has_element?(view, "#slot-chip-#{dom}[data-illegal='1']")

        assert render(element(view, "#slot-issue-#{dom}")) =~
                 "#{label} · #{name}: #{@not_selectable}"
      end

      # Снятие — обычное `clear_slot`, ядро не спрашивается: иначе билд
      # из старой ссылки было бы не починить.
      for slot <- [:general, :racial, {:class_bonus, :fighter}] do
        view |> element("#slot-clear-#{Ids.slot_dom_id(slot)}") |> render_click()
      end

      refute has_element?(view, "#stage-nav-list [data-illegal='1']")
      refute has_element?(view, "#slot-issues")
      refute has_element?(view, "#level-1[data-illegal='1']")
      refute has_element?(view, "#level-1-issue")
      refute has_element?(view, "#spine-illegal")
    end

    test "экран просмотра: строка уровня и фраза «старая ссылка», а не «след правки»", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(mounted(ruleset))}")

      assert render(element(view, "#view-illegal")) =~ "1 уровень с нарушением правил"

      assert render(element(view, "#view-illegal-1")) =~
               "Mount actions, Mounted combat, Mounted archery: #{@not_selectable}"

      assert render(element(view, "#view-illegal-note-rules")) =~
               "собранные до обновления правил"

      refute has_element?(view, "#view-illegal-note-edit")
      refute has_element?(view, "#view-illegal-note-increase")

      assert has_element?(view, "#view-guide-level-1[data-illegal='1']")
    end
  end

  describe "фит, выключенный шардом позже, чем собрана ссылка" do
    test "по правилам с включённым фитом билд законен; сегодня — `feat_disabled`", %{
      ruleset: ruleset
    } do
      build = devastating(ruleset)
      enabled = put_in(ruleset.feats[:devastating_critical].disabled?, false)

      assert Rules.illegal_feats(build, enabled) == []

      assert Rules.illegal_feats(build, ruleset) == [
               {22, {:class_bonus, :fighter}, :devastating_critical,
                {:feat_disabled, :devastating_critical}}
             ]
    end

    test "⚠ ровно на 22-м уровне, в ленте — у «Фитов»", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = open(conn, devastating(ruleset))

      assert has_element?(view, "#level-22[data-illegal='1']")

      assert issue_text(view, 22) =~
               "Devastating critical: фит Devastating critical на Сиале отключён"

      for level <- [1, 4, 8, 21] do
        refute has_element?(view, "#level-#{level}[data-illegal='1']")
      end

      {:ok, view, _html} = open(conn, devastating(ruleset), 22)
      assert has_element?(view, "#stage-nav-feats[data-illegal='1']")
      assert has_element?(view, "#stage-nav-class .stage-nav-mark", "✓")
    end
  end

  describe "фит, которого не держит ни один пул слотов" do
    # Живого носителя, достижимого без ручной правки, у этой головы нет:
    # Craft harper item, которого 4.55 увела из пулов, всегда отбивался ещё
    # и `:already_taken` (Арфист выдаёт его на своём 1-м уровне) или
    # `:requires_class_level` — пикер его не предлагал, импорт не ставил,
    # а ссылку, собранную руками, лестница помечала и до 4.60. Голова закрыта
    # заранее, под обновление данных той же формы; носитель теста — расовый
    # фит человека в общем слоте, у которого `:not_slottable` — единственный
    # отказ (расовых фитов в `Build.feats_owned/3` нет намеренно, «уже взят»
    # не срабатывает).
    test "Quick to master в общем слоте — ⚠ с причиной «выдаётся расой»", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 3),
          base_abilities: %{str: 16, dex: 14, con: 14, int: 12, wis: 12, cha: 10},
          feats: %{3 => %{general: :quick_to_master}}
        )

      assert Rules.illegal_feats(build, ruleset) == [
               {3, :general, :quick_to_master, {:not_slottable, "race"}}
             ]

      {:ok, view, _html} = open(conn, build)

      assert has_element?(view, "#level-3[data-illegal='1']")
      assert issue_text(view, 3) =~ "Quick to master: выдаётся расой, слотом не берётся"
    end

    test "Craft harper item в слоте помечался и раньше — теперь обе причины", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :neutral_good,
          levels: List.duplicate(:bard, 6),
          base_abilities: %{str: 10, dex: 14, con: 12, int: 14, wis: 10, cha: 16},
          feats: %{6 => %{general: :craft_harper_item}}
        )

      assert Enum.sort(Rules.illegal_feats(build, ruleset)) ==
               Enum.sort([
                 {6, :general, :craft_harper_item, {:not_slottable, "class"}},
                 {6, :general, :craft_harper_item, {:requires_class_level, :harper_scout, 1}}
               ])

      {:ok, view, _html} = open(conn, build)

      assert has_element?(view, "#level-6[data-illegal='1']")
      assert issue_text(view, 6) =~ "Craft harper item: нужен Harper scout 1"
      assert issue_text(view, 6) =~ "Craft harper item: выдаётся классом, слотом не берётся"
    end
  end
end
