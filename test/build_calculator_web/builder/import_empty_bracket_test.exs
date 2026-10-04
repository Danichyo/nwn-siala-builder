defmodule BuildCalculatorWeb.Builder.ImportEmptyBracketTest do
  @moduledoc """
  Задача 4.40, заход 3, пункт 22: пустая скобка читается одинаково — с пробелом
  внутри и без.

  `LevelTail.drop_scores/1` снимает итог, вписанный в скобку (`(=25)`), и от
  скобки остаётся пустая — `( )`. Читатель фитов (`FeatList`) читал `( )` как
  скобку значения, где значения нет, и имя перед ней целиком, а `()` — нет: имя
  с двоеточием делилось по нему, и `EF:Great Strength II ()` становилось
  Epic Fortitude с отброшенным «Great Strength II ()», а `( )` — незнакомым
  именем, каким оно и было (пост ECB 170330). На этой разнице держалось
  снятие итога: первая версия правки 4.40 оставляла `()`, и стенд поймал два
  поста, прочитанных иначе. Теперь `bracketed_qualifier/1` читает и пустую
  скобку, а `resolve_feat/6` читает имя с закрытыми пустыми скобками и печатает
  его игроку как написано.

  Синтетика по форме строк корпуса: текст постов в git не кладём
  (`tools/vanilla_recon/README.md`). Перебор 3000 форм — `tmp/4.40c/p22_sweep.exs`
  (вне git): разница была в 12 из 70 рукописных форм и в 4 из 3000 перебора,
  стала 0 и 0.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculatorWeb.Builder.Import

  setup_all do
    %{rulesets: [Data.ruleset!("vanilla"), Data.ruleset!("siala_41")]}
  end

  # Лестница воина до `level`, на последнем уровне — `item`.
  defp read(ruleset, level, item) do
    ladder =
      for l <- 1..level, do: if(l == level, do: "#{l} Fighter - #{item}", else: "#{l} Fighter")

    result =
      Import.parse("Human, Lawful Good\nLevel Class Feat\n" <> Enum.join(ladder, "\n"), ruleset)

    issues = for issue <- result.issues, tuple_size(issue) > 1, elem(issue, 1) == level, do: issue

    {result.build.feats[level], Map.get(result.build.ability_increases, level), issues}
  end

  # Чтение без самой скобки в тексте замечаний: сравнивается ЧТО прочитано.
  defp reading(ruleset, level, item) do
    {feats, increase, issues} = read(ruleset, level, item)
    {feats, increase, issues |> inspect() |> String.replace(~r/\(\s*\)|\[\s*\]/u, "<>")}
  end

  # Формы, где пробел в пустой скобке менял чтение до правки (рукописный набор,
  # `tmp/4.40c/p22_forms.exs`), и соседние, где не менял.
  @forms [
    "STR+1=24, EF:Great Strength II <>",
    "EF:Great Strength II <>",
    "Epic Weapon Focus: Longsword <>",
    "Graet CHA II <>",
    "EWF: Longsword <>",
    "Epic Skill Focus: Discipline <>",
    "Weapon <> Focus Longsword",
    "Great Strength II <>",
    "+1 CHA <>",
    "<>, Epic Prowess",
    "Epic Prowess <>",
    "Epic Weapon Focus (Longsword) <>",
    "Dodge <>"
  ]

  test "`( )` и `()`, `[ ]` и `[]` читаются одинаково", %{rulesets: rulesets} do
    for ruleset <- rulesets, level <- [21, 24], form <- @forms do
      spaced = reading(ruleset, level, String.replace(form, "<>", "( )"))
      tight = reading(ruleset, level, String.replace(form, "<>", "()"))
      assert spaced == tight, "#{ruleset.version} L#{level} #{form}"

      spaced = reading(ruleset, level, String.replace(form, "<>", "[ ]"))
      tight = reading(ruleset, level, String.replace(form, "<>", "[]"))
      assert spaced == tight, "#{ruleset.version} L#{level} #{form} (квадратные)"
    end
  end

  # Чтение — то, что было у `( )` до правки: корпус не сдвинут (стенд
  # `import_equivalence.exs`), а `()` теперь читается так же.
  test "остаток скобки итога читается, как читался", %{rulesets: [vanilla | _]} do
    for bracket <- ["( )", "()", "(=25)"] do
      written = if bracket == "(=25)", do: "( )", else: bracket

      assert read(vanilla, 24, "STR+1=24, EF:Great Strength II #{bracket}") ==
               {nil, :str, [{:unknown_feat, 24, "EF:Great Strength II #{written}"}]}

      assert {%{general: :great_charisma}, nil, []} =
               read(vanilla, 30, "Graet CHA II #{bracket}")
    end
  end

  # Положительный контроль: без пустой скобки двоеточие делит имя, как всегда
  # (тег `EF:` читается аббревиатурой Epic Fortitude — давний дефект, не этой
  # правки), — проверка выше не пустая.
  test "без скобки имя с двоеточием делится по нему", %{rulesets: [vanilla | _]} do
    assert {%{general: :epic_fortitude}, :str,
            [{:feat_qualifier_dropped, 24, :epic_fortitude, "Great Strength II"}]} =
             read(vanilla, 24, "STR+1=24, EF:Great Strength II")
  end

  # Печать — как написано: имя с пустой скобкой доходит до замечания тем же
  # текстом, а не с закрытой скобкой.
  test "незнакомое имя печатается как написано", %{rulesets: [vanilla | _]} do
    assert {nil, nil, [{:unknown_feat, 21, "Mystic ( ) Strike"}]} =
             read(vanilla, 21, "Mystic ( ) Strike")

    assert {nil, nil, [{:unknown_feat, 21, "Mystic () Strike"}]} =
             read(vanilla, 21, "Mystic () Strike")
  end

  # Пустая скобка между словами имени: `()` читалась Weapon Focus, `( )` —
  # незнакомым именем (перебор, 4 формы из 3000). Теперь обе — Weapon Focus.
  test "пустая скобка посреди имени", %{rulesets: rulesets} do
    for ruleset <- rulesets, bracket <- ["( )", "()"] do
      assert {%{general: {:weapon_focus, :longsword}}, nil, []} =
               read(ruleset, 21, "Weapon #{bracket} Focus Longsword")
    end
  end
end
