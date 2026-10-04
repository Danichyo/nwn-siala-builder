defmodule BuildCalculatorWeb.BuilderFeatReasonsTest do
  @moduledoc """
  Задача 4.40, заход 2 — причины в конструкторе:

    * (1) секция фитов называет нелегальный пик словами, по строке на слот
      (`#slot-issues`, `#slot-issue-<слот>`), а не только в `title` лестницы;
    * (14) «нужен общий слот» не печатается рядом с «только на уровне Bard»:
      общий слот уровня Убийцы это значение тоже не берёт;
    * (15) фронтир (уровень без класса) — список фитов ждёт класса
      (`#feats-await-class`), `pick_feat` там отбивается;
    * (16) эпический фит до 21-го — одна фраза в выборе фитов и на лестнице;
    * (6) «Класс даёт сам» называет ступень, которую список выдач не называет.

  Пункт (17) — группировка причин уровня — держат `builder_lost_spell_test.exs`
  и `builder_closed_feat_test.exs` (точные строки), здесь — только (1)–(16) и (6).

  Билды собраны по одному левелапу с проверкой ядра (CLAUDE.md §3) и открыты
  ссылкой, как у игрока. Редакция — умолчательная (Сиала); ванильные числа
  тех же правил держит `class_steps_test.exs` на уровне ядра.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.{Data, Encoding, Ids, Rules}
  alias BuildCalculator.Rules.{Build, Skills}

  setup do
    %{ruleset: Data.ruleset!(Data.default_version())}
  end

  defp open(conn, %Build{} = build, level),
    do: live(conn, ~p"/?b=#{Encoding.encode(build)}&l=#{level}")

  defp code(view) do
    [value] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#share-link")
      |> LazyHTML.attribute("value")

    value
  end

  # Левелап за левелапом, каждый проверен ядром; навыки из списка докупаются
  # до потолка уровня, пока хватает очков (`Skills.rank_room/4`, `budget/3`).
  defp ladder(build, ruleset, classes, skills \\ []) do
    Enum.reduce(classes, build, fn class, acc ->
      assert Rules.validate_level_up(acc, class, ruleset) == :ok,
             "#{class} на #{Build.character_level(acc) + 1}-м уровне отказан"

      acc = Build.add_level(acc, class)
      level = Build.character_level(acc)

      Enum.reduce(skills, acc, fn skill, acc ->
        room = Skills.rank_room(acc, ruleset, skill, level)
        cost = Skills.rank_cost(acc, ruleset, skill, level)
        n = min(room, div(Skills.budget(acc, ruleset, level).free || 0, cost))

        if n > 0,
          do: %{
            acc
            | skills: Map.update(acc.skills, level, %{skill => n}, &Map.put(&1, skill, n))
          },
          else: acc
      end)
    end)
  end

  defp put_feat(build, ruleset, level, slot, feat, choice \\ nil) do
    pick = %{feat: feat, at: level, slot: slot}
    pick = if choice, do: Map.put(pick, :choice, choice), else: pick
    assert Rules.validate_feat_pick(build, pick, ruleset) == :ok, "#{feat} на #{level}-м"
    Build.put_feat(build, level, slot, feat, choice)
  end

  defp fighter(ruleset, levels) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :human,
      alignment: :lawful_neutral,
      base_abilities: %{str: 16, dex: 13, con: 14, int: 10, wis: 10, cha: 10}
    )
    |> ladder(ruleset, List.duplicate(:fighter, levels))
  end

  # ------------------------------------------------------------ пункт (1) --

  describe "(1) секция фитов называет нелегальный пик словами" do
    # Воин 2: Power attack в общем слоте 1-го, Cleave в бонусном слоте 2-го.
    # Сняли Power attack — Cleave на 2-м уровне остался без требования: правка,
    # а не ссылка, то есть игроку это достижимо.
    test "снятый пререквизит: строка под чипами, чип помечен; контроль — до снятия пусто", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        ruleset
        |> fighter(2)
        |> put_feat(ruleset, 1, :general, :power_attack)
        |> put_feat(ruleset, 2, {:class_bonus, :fighter}, :cleave)

      assert Rules.illegal_feats(build, ruleset) == []

      {:ok, view, _html} = open(conn, build, 2)
      bonus = Ids.slot_dom_id({:class_bonus, :fighter})

      # Положительный контроль: законный билд — ни строки, ни пометки.
      refute has_element?(view, "#slot-issues")
      refute has_element?(view, "#slot-chip-#{bonus}[data-illegal]")

      view |> element("#level-1") |> render_click()
      view |> element("#slot-clear-general") |> render_click()
      view |> element("#level-2") |> render_click()

      assert has_element?(view, "#level-2[data-illegal='1']")
      assert has_element?(view, "#slot-chip-#{bonus}[data-illegal='1']")

      assert render(element(view, "#slot-issue-#{bonus}")) =~
               "Бонус Fighter · Cleave: нужен фит Power attack"

      # Слоты без нарушения своей строки не получают.
      refute has_element?(view, "#slot-issue-general")
    end
  end

  # ----------------------------------------------------------- пункт (14) --

  describe "(14) Epic skill focus в бонусном слоте Убийцы — одна правдивая причина" do
    setup %{ruleset: ruleset} do
      assassin =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :neutral_evil,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 10, cha: 10}
        )
        |> ladder(
          ruleset,
          List.duplicate(:rogue, 10) ++ List.duplicate(:assassin, 14),
          [:hide, :move_silently, :use_magic_device]
        )

      %{assassin: assassin, bonus: Ids.slot_dom_id({:class_bonus, :assassin})}
    end

    test "второй шаг: UMD — только «на уровне Bard / Rogue / Shadowdancer»; Tumble — слот", %{
      conn: conn,
      assassin: assassin,
      bonus: bonus
    } do
      {:ok, view, _html} = open(conn, assassin, 24)

      view |> element("#slot-filter-#{bonus}") |> render_click()
      view |> element("#feat-ok-epic_skill_focus") |> render_click()

      umd = render(element(view, "#feat-choice-no-use_magic_device"))
      assert umd =~ "только на уровне Bard / Rogue / Shadowdancer"
      refute umd =~ "нужен общий слот"

      for skill <- ~w(animal_empathy perform) do
        refute render(element(view, "#feat-choice-no-#{skill}")) =~ "нужен общий слот"
      end

      # Положительный контроль: значение, которое общий слот того же уровня
      # берёт, по-прежнему отправляет туда.
      assert render(element(view, "#feat-choice-no-tumble")) =~
               "с этим значением в бонус Assassin нельзя — нужен общий слот"
    end

    # Старая ссылка (до задачи 4.50 Убийца брал Epic skill focus с любым навыком):
    # лестница называет ту же одну причину.
    test "лестница: старая ссылка с UMD в бонусе Убийцы — без «нужен общий слот»", %{
      conn: conn,
      ruleset: ruleset,
      assassin: assassin
    } do
      stale =
        Build.put_feat(
          assassin,
          24,
          {:class_bonus, :assassin},
          :epic_skill_focus,
          :use_magic_device
        )

      reasons = for {24, _slot, _feat, reason} <- Rules.illegal_feats(stale, ruleset), do: reason
      assert {:not_in_class_bonus_slot, :assassin} in reasons
      assert Enum.any?(reasons, &match?({:requires_leveling_as, _}, &1))

      {:ok, view, _html} = open(conn, stale, 24)

      issue = render(element(view, "#level-24-issue"))
      assert issue =~ "Epic skill focus: только на уровне Bard / Rogue / Shadowdancer"
      refute issue =~ "нужен общий слот"
    end
  end

  # ----------------------------------------------------------- пункт (15) --

  describe "(15) фронтир: список фитов ждёт класса уровня" do
    setup %{ruleset: ruleset} do
      bard =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :true_neutral,
          base_abilities: %{str: 10, dex: 14, con: 14, int: 12, wis: 10, cha: 16}
        )
        |> ladder(ruleset, List.duplicate(:bard, 20))

      %{bard: bard}
    end

    test "бард 20, уровень 21: ни списка, ни причин от имени Bard; клик по фиту отбит", %{
      conn: conn,
      bard: bard
    } do
      {:ok, view, _html} = open(conn, bard, 21)

      # Слот у уровня есть (эпический общий), секция на месте — список ждёт класса.
      assert has_element?(view, "#section-feats")
      assert has_element?(view, "#slot-chip-general")
      assert has_element?(view, "#feats-await-class")
      refute has_element?(view, "#feat-lists")
      refute has_element?(view, "#feat-search-form")

      before = code(view)
      render_click(view, "pick_feat", %{"feat" => "great_intelligence"})
      assert code(view) == before

      # Класс выбран — список появился, и от имени Bard он больше не говорит.
      view |> element("#class-card-fighter") |> render_click()

      refute has_element?(view, "#feats-await-class")
      assert has_element?(view, "#feat-lists")
      view |> element("#feat-search-form") |> render_change(%{"q" => "divine might"})
      refute render(element(view, "#feat-lists")) =~ "на уровне Bard"
    end

    test "контроль: на взятом уровне барда причина от его класса остаётся", %{
      conn: conn,
      bard: bard
    } do
      {:ok, view, _html} = open(conn, bard, 18)

      refute has_element?(view, "#feats-await-class")
      view |> element("#feat-search-form") |> render_change(%{"q" => "divine might"})

      assert render(element(view, "#feat-no-divine_might")) =~
               "на уровне Bard этот фит не выбрать"
    end
  end

  # ----------------------------------------------------------- пункт (16) --

  describe "(16) эпический фит до 21-го — одна фраза в выборе и на лестнице" do
    test "выбор фитов на 9-м и ⚠ старой ссылки на 9-м говорят «нужен 21-й уровень»", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = fighter(ruleset, 10)
      {:ok, view, _html} = open(conn, build, 9)

      view |> element("#feat-search-form") |> render_change(%{"q" => "great strength"})

      # Причина — ровно фраза лестницы; «эпический» строка и так говорит своей
      # меткой (`.feat-epic-tag`), прежняя причина «эпический: …» его повторяла.
      assert has_element?(view, "#feat-no-great_strength .feat-epic-tag", "эпический")

      assert view
             |> element("#feat-no-great_strength .feat-why")
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.text() == "нужен 21-й уровень"

      stale = Build.put_feat(build, 9, :general, :great_strength)
      {:ok, view, _html} = open(conn, stale, 9)

      assert render(element(view, "#level-9-issue")) =~ "Great strength: нужен 21-й уровень"
      refute render(element(view, "#level-9-issue")) =~ "эпический"
    end
  end

  # ------------------------------------------------------------ пункт (6) --

  describe "(6) «Класс даёт сам» называет выросшую ступень" do
    # Воин 6 / волшебник 1 / Тайный лучник 3 — Enchant arrow +2 на 3-м уровне
    # лучника: выдан на 1-м, на 3-м растёт, списком выдач не назван.
    test "Тайный лучник 3: Enchant arrow +2; контроль — лучник 2 говорит своё", %{
      conn: conn,
      ruleset: ruleset
    } do
      archer =
        Build.new(
          ruleset_version: ruleset.version,
          race: :elf,
          alignment: :true_neutral,
          base_abilities: %{str: 10, dex: 14, con: 10, int: 16, wis: 10, cha: 10},
          feats: %{1 => %{general: {:weapon_focus, :longbow}}, 3 => %{general: :point_blank_shot}}
        )
        |> ladder(
          ruleset,
          List.duplicate(:fighter, 6) ++ [:wizard] ++ List.duplicate(:arcane_archer, 3)
        )

      {:ok, view, _html} = open(conn, archer, 10)
      assert render(element(view, "#granted-note")) =~ "Enchant arrow +2"

      {:ok, view, _html} = open(conn, archer, 9)
      note = render(element(view, "#granted-note"))
      assert note =~ "Imbue arrow"
      refute note =~ "Enchant arrow"

      # Уровень выдачи — словами страницы класса, без ранга ступени.
      {:ok, view, _html} = open(conn, archer, 8)
      note = render(element(view, "#granted-note"))
      assert note =~ "Enchant arrow"
      refute note =~ "Enchant arrow +"
    end
  end
end
