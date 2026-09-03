defmodule BuildCalculatorWeb.RacialBonusNoteTest do
  @moduledoc """
  Справка к ПОСЧИТАННОМУ расовому бонусу на обоих экранах — задача 3.102,
  решение Dan 25.08.2026.

  Форма `{:assumed, {:racial_bonus_variant, race, variant}}` несла три разных
  предложения, и два из них описывали **успех** («посчитан базовый +6»,
  «посчитан вариант сагровика +9»), стоя при этом под заголовком «Конкретно
  в этом билде ядро **не смогло посчитать** N». Решение: разделить по смыслу —
  «не посчитан, возьми оружие» остаётся пробелом билда, «посчитан такой-то»
  переезжает справкой к самому числу.

  ⚠️ **Отдельный файл, а не дописано в `builder_live_test.exs`** — тот на
  200+ КБ и его правят соседние задачи; форма взята у
  `builder_gear_weapon_test.exs`.

  ## Почему у каждой расы свой адрес и почему это надо проверять по DOM-id

  Число, в которое падает бонус, у каждой расы своё: AB у Светлого эльфа,
  щитовой AC у Карлика, значение навыка Discipline у Человека
  (`ruleset.racial_bonuses`). Одно общее место было бы неверно для двух рас
  из трёх, поэтому адрес выводит ядро, а проверяется он тем единственным
  способом, каким его видит пользователь, — куда лёг узел.

  ⚠️ **Дубина в руках — не декорация.** Расовый бонус включается оружием
  в руках (замер Dan 15.08.2026), а дубина владения не требует
  (`weapons.json`, `no_proficiency_required`) и своего бонуса за тип оружия
  не даёт — то есть включает расовый бонус и не примешивает к числам ничего
  своего. Тот же приём, что у топора в `racial_bonus_test.exs`.
  """

  use BuildCalculatorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}

  setup do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  defp build(ruleset, race, opts \\ []) do
    levels = Keyword.get(opts, :levels, List.duplicate(:fighter, 40))

    Build.new(
      ruleset_version: ruleset.version,
      race: race,
      alignment: :true_neutral,
      levels: levels,
      base_abilities: %{str: 16, dex: 14, con: 14, int: 12, wis: 10, cha: 10},
      # Ранги нужны Человеку: навык без рангов в панель не приводит собственная
      # прибавка билда (решение Dan 16.08.2026), и строки Discipline у него
      # просто не было бы.
      skills: %{1 => %{discipline: 4}},
      gear: Gear.new(weapon: Keyword.get(opts, :weapon, :club))
    )
  end

  defp constructor(conn, build), do: live(conn, ~p"/?b=#{Encoding.encode(build)}")
  defp viewer(conn, build), do: live(conn, ~p"/b/#{Encoding.encode(build)}")

  describe "справка видна на обоих экранах" do
    # ⚠️ Один узел, три возможных родителя, и родитель — это и есть проверяемое
    # утверждение: справка стоит у того числа, в которое бонус упал.
    test "конструктор: у каждой расы справка лежит у своего числа", %{
      conn: conn,
      ruleset: ruleset
    } do
      for {race, parent} <- [
            {:half_elf, "#stat-group-attack"},
            {:gnome, "#stat-group-vital"},
            {:human, "#stat-skill-discipline"}
          ] do
        {:ok, view, _html} = constructor(conn, build(ruleset, race))

        assert has_element?(view, "#{parent} #stat-note-racial-bonus"),
               "#{race}: справки нет в #{parent}"

        assert render(element(view, "#stat-note-racial-bonus")) =~ "бонус расы"
      end
    end

    test "экран просмотра: у каждой расы справка лежит у своего числа", %{
      conn: conn,
      ruleset: ruleset
    } do
      for {race, parent} <- [
            {:half_elf, "#view-stats"},
            {:gnome, "#view-stats"},
            {:human, "#view-skill-discipline"}
          ] do
        {:ok, view, _html} = viewer(conn, build(ruleset, race))

        assert has_element?(view, "#{parent} #view-racial-bonus"),
               "#{race}: справки нет в #{parent}"

        assert render(element(view, "#view-racial-bonus")) =~ "бонус расы"
      end
    end

    # ⚠️ Справка называет посчитанный вариант и тот, что ему противопоставлен.
    #
    # 🔴 ЗДЕСЬ ПРОВЕРЯЛИСЬ ВСЕ ЧЕТЫРЕ ЧИСЛА — снято 31.08.2026 по запросу Dan
    # вместе с хвостом про оружейные варианты. ⚠️ Хвост обобщал НЕВЕРНО: `+12`
    # и `+18` достижимы только с РАСОВЫМ оружием, у Светлого эльфа это оружие
    # дальнего боя («+18 получается только светлый эльф сагровик на метательное»,
    # Dan), а с клинковым оружейный бонус идёт в щитовой AC, а не в атаку.
    # Фраза «с подходящим по типу оружием» читалась как «с любым нормальным»,
    # а значила «ровно с одним видом из пяти».
    #
    # ⚠️ Числа не пропали из ОТВЕТА — `stats.racial_bonus.variants` несёт все
    # четыре по-прежнему; они не печатаются строкой в UI, и это решение Dan:
    # «люди и так знают про бонусы расы и оружия».
    test "справка называет посчитанный вариант и его альтернативу",
         %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = constructor(conn, build(ruleset, :half_elf))
      text = render(element(view, "#stat-note-racial-bonus"))

      assert text =~ "Светлый эльф"
      assert text =~ "+9"
      assert text =~ "+6"

      for gone <- ["+12", "+18", "только половина", "бонус за тип оружия"],
          do: refute(text =~ gone)
    end

    # 🔴 Две разные справки, а не одна на оба случая (решение Dan 08.08.2026):
    # у сагровика она обязана сказать, что покровительство УЖЕ учтено, а
    # у остального билда — что посчитан пол и чего билду не хватило.
    test "сагровик и не сагровик читают разное", %{conn: conn, ruleset: ruleset} do
      {:ok, sagra, _html} = constructor(conn, build(ruleset, :half_elf))

      {:ok, mixed, _html} =
        constructor(
          conn,
          build(ruleset, :half_elf, levels: List.duplicate(:fighter, 39) ++ [:bard])
        )

      assert render(element(sagra, "#stat-note-racial-bonus")) =~ "вариант сагровика +9"
      assert render(element(mixed, "#stat-note-racial-bonus")) =~ "посчитан базовый +6"
    end
  end

  describe "то, что переезд обязан был сохранить" do
    # 🔴 ГЛАВНОЕ. Билд без оружия по-прежнему говорит, что бонус не включён:
    # игрок в одном движении от +9, и это единственное из трёх предложений,
    # которое действительно про недостачу.
    test "без оружия — пробел билда, и справки нет", %{conn: conn, ruleset: ruleset} do
      bare = build(ruleset, :half_elf, weapon: nil)
      {:ok, view, _html} = constructor(conn, bare)

      refute has_element?(view, "#stat-note-racial-bonus")

      view |> element("#gaps-toggle") |> render_click()
      body = render(element(view, "#gaps-body"))
      assert body =~ "оружием в руках"
      assert body =~ "Светлый эльф"

      # и то же самое числом: оговорка ядра на месте
      assert {:assumed, {:racial_bonus_variant, :half_elf, nil}} in Rules.compute(
               bare,
               ruleset
             ).gaps
    end

    # ⚠️ Ниже 40-го оговорка остаётся ПРО УРОВЕНЬ — величины не знает никто,
    # и «возьми оружие» там было бы советом, который ничего не чинит. Справки
    # при этом нет: считать нечего.
    test "ниже 40-го — пробел про уровень, и справки нет", %{conn: conn, ruleset: ruleset} do
      below = build(ruleset, :half_elf, levels: List.duplicate(:fighter, 39))
      {:ok, view, _html} = constructor(conn, below)

      refute has_element?(view, "#stat-note-racial-bonus")

      view |> element("#gaps-toggle") |> render_click()
      assert render(element(view, "#gaps-body")) =~ "растёт с уровнем"

      assert {:missing_data, {:racial_bonus_level, :half_elf}} in Rules.compute(
               below,
               ruleset
             ).gaps
    end

    # 🔴 Положительный контроль в обратную сторону: у Гоблина и Тёмного эльфа
    # бонуса нет вовсе, и ни справки, ни оговорки там быть не должно — ложная
    # тревога на пустом месте хуже отсутствующей.
    test "Гоблин и Тёмный эльф молчат обоими способами", %{conn: conn, ruleset: ruleset} do
      for race <- [:halfling, :elf] do
        {:ok, view, _html} = constructor(conn, build(ruleset, race))
        refute has_element?(view, "#stat-note-racial-bonus"), "#{race}"

        {:ok, viewer, _html} = viewer(conn, build(ruleset, race))
        refute has_element?(viewer, "#view-racial-bonus"), "#{race}"

        gaps = Rules.compute(build(ruleset, race), ruleset).gaps
        assert Enum.filter(gaps, &(inspect(&1) =~ "racial_bonus")) == [], "#{race}"
      end
    end

    # ⚠️ Числа не сдвинулись ни на единицу — правка меняла ПРИЗНАНИЕ, а не
    # расчёт. Проверяется на самом заметном числе: AB сагровика.
    test "число под справкой то же, что и было", %{conn: conn, ruleset: ruleset} do
      stats = Rules.compute(build(ruleset, :half_elf), ruleset)
      assert stats.race_attack_bonus == 9

      {:ok, view, _html} = constructor(conn, build(ruleset, :half_elf))
      assert render(element(view, "#stat-attack_bonus")) =~ Integer.to_string(stats.attack_bonus)
    end
  end
end
