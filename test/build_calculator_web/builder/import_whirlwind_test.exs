defmodule BuildCalculatorWeb.Builder.ImportWhirlwindTest do
  @moduledoc """
  Задача 4.40, заход 3, пункт 23: «Whirlwind» без «attack» — Whirlwind attack.

  Перепись корпуса ECB (2027 первых постов, `tmp/4.40c/p23_census.exs` вне git):
  голое «Whirlwind» в лестнице пишут 17 постов, и у всех это Whirlwind attack —
  после Spring attack и Expertise, часто рядом с «Intimidate 4» (требование
  Weapon Master; пост 186693: «12 Paladin Whirlwind (Intimidate = 4)», WM на
  13-м). До правки имя было незнакомым во всех семнадцати (и ещё в одном, 117355,
  строка «--- Whirlwind» под уровнем пропускалась), и лестница теряла фит, без
  которого следующий престиж-класс незаконен. «Improved whirlwind» — тем же
  сокращением Improved whirlwind attack (117411). Стенд `import_equivalence.exs`
  против `3438be9`: 19 постов на каждом ruleset'е, группа `whirlwind_shorthand`.

  Сокращение живёт в индексе имён (`Names.indexes/1`), а не в словаре
  токенизатора: там «whirlwind» встало бы в начале «Whirlwind Atk» и оставило
  «Atk» незнакомым именем.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculatorWeb.Builder.Import
  alias BuildCalculatorWeb.Builder.Import.Names

  setup_all do
    %{rulesets: [Data.ruleset!("vanilla"), Data.ruleset!("siala_41")]}
  end

  defp read(ruleset, item, level \\ 21) do
    ladder =
      for l <- 1..level, do: if(l == level, do: "#{l} Fighter #{item}", else: "#{l} Fighter")

    result =
      Import.parse("Human, Lawful Good\nLevel Class Feat\n" <> Enum.join(ladder, "\n"), ruleset)

    issues = for issue <- result.issues, tuple_size(issue) > 1, elem(issue, 1) == level, do: issue
    guessed = for {:feats_guessed, list} <- result.issues, entry <- list, do: entry

    {result.build.feats[level], issues, guessed}
  end

  test "«Whirlwind» — Whirlwind attack, как его пишут посты", %{rulesets: rulesets} do
    for ruleset <- rulesets, item <- ["Whirlwind", "WhirlWind", "whirlwind."] do
      assert {%{general: :whirlwind_attack}, [], []} == read(ruleset, item), item
    end
  end

  test "строка поста 186693: фит прочитан, «Intimidate» названа", %{rulesets: rulesets} do
    for ruleset <- rulesets do
      assert {%{general: :whirlwind_attack},
              [{:feat_qualifier_dropped, 21, :whirlwind_attack, "Intimidate"}], []} ==
               read(ruleset, "Whirlwind (Intimidate = 4)")
    end
  end

  test "«Improved whirlwind» — Improved whirlwind attack, а не Whirlwind attack", %{
    rulesets: rulesets
  } do
    for ruleset <- rulesets, item <- ["Improved Whirlwind", "improved whirlwind"] do
      assert {%{general: :improved_whirlwind_attack}, [], []} == read(ruleset, item), item
    end

    # Полное имя — по-прежнему своё.
    for ruleset <- rulesets do
      assert {%{general: :improved_whirlwind_attack}, [], []} ==
               read(ruleset, "Improved Whirlwind Attack")
    end
  end

  # Чтение соседних написаний не сдвинулось: сокращение не в словаре
  # токенизатора — «Whirlwind Atk» читается целиком, догадкой, о которой игроку
  # сказано, а не фитом и незнакомым «Atk».
  test "соседние написания — как до правки", %{rulesets: rulesets} do
    for ruleset <- rulesets do
      assert {%{general: :whirlwind_attack}, [], [{"Whirlwind Atk", :whirlwind_attack, 21}]} ==
               read(ruleset, "Whirlwind Atk")

      assert {%{general: :improved_whirlwind_attack}, [],
              [{"Improv Whirlwind Atk", :improved_whirlwind_attack, 21}]} ==
               read(ruleset, "Improv Whirlwind Atk")

      assert {nil, [{:unknown_feat, 21, "Whirlwind strike"}], []} ==
               read(ruleset, "Whirlwind strike")

      assert {nil, [{:unknown_feat, 21, "imp whirlwind"}], []} == read(ruleset, "imp whirlwind")
    end
  end

  # Сокращение, на которое уже отвечает другой фит, не отдаётся ни одному из
  # них, а называется неоднозначным — как любое имя индекса (`put_key/3`).
  test "сокращение, занятое другим фитом, — отказ, а не выбор", %{rulesets: [vanilla | _]} do
    assert Names.resolve(Names.indexes(vanilla).feats, "Whirlwind") == {:ok, :whirlwind_attack}

    taken =
      put_in(vanilla, [:feats, :dodge, :name], "Whirlwind")

    assert {:ambiguous, ids} = Names.resolve(Names.indexes(taken).feats, "Whirlwind")
    assert Enum.sort(ids) == [:dodge, :whirlwind_attack]
  end
end
