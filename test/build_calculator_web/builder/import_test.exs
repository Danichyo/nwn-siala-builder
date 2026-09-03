defmodule BuildCalculatorWeb.Builder.ImportTest do
  @moduledoc """
  Reading somebody else's build back out of the community's text block.

  Two properties are tested apart from each other on purpose, because they pull
  in opposite directions: **tolerance** (the block is formatted differently by
  everyone) and **honesty** (whatever did not read is reported, never guessed).

  ⚠️ Task 3.145 narrowed what this module has to read. `Export` now writes two
  shapes: `vanilla`'s unchanged two-block format, and `siala_41`'s own line
  per level (glyphs, no separate `SKILL GUIDE`) — and `Import` is **not**
  taught the second one, on purpose (Siala players move builds with the
  in-game `.билд` log, never by pasting our own export back in, CLAUDE.md
  §6). So describe "round trip" below pins `ruleset: "vanilla"` locally
  rather than the module's default (`Data.ruleset!()`, which is `siala_41`):
  round-tripping `Export.text/4`'s output through `Import.parse/2` is a
  promise this file makes about `vanilla` only. The `WikiBuildPage`-driven
  tests further down stay on the default ruleset — they build real Siala
  ladders with `feats: false` (no feat/skill tail to lose in translation),
  so a level line's *header* (`NN: ClassName(n):`, unchanged by either
  shape) is all `Import` has to read there, and it is.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, Rules, WikiBuildPage}
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.{Export, Import}

  setup do
    %{ruleset: Data.ruleset!()}
  end

  defp build(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :dwarf,
      alignment: :lawful_good,
      base_abilities: %{str: 16, dex: 12, con: 15, int: 10, wis: 12, cha: 8},
      levels: List.duplicate(:fighter, 4) ++ List.duplicate(:dwarven_defender, 6),
      ability_increases: %{4 => :str, 8 => :str},
      feats: %{
        1 => %{{:class_bonus, :fighter} => :power_attack},
        3 => %{:general => :cleave}
      },
      skills: %{1 => %{discipline: 4, spot: 2}, 2 => %{discipline: 1}}
    )
  end

  describe "round trip" do
    # ⚠️ Задача 3.145: только `vanilla` печатает то, что этот файл умеет
    # читать обратно (см. moduledoc). Переопределяет `ruleset` умолчания
    # модуля (`siala_41`) для тестов этого describe — тела тестов не
    # трогались, менялся только контекст, из которого они берут `ctx.ruleset`.
    setup do
      %{ruleset: Data.ruleset!("vanilla")}
    end

    test "our own export reads back into the same build", ctx do
      original = build(ctx.ruleset)
      stats = Rules.compute(original, ctx.ruleset)
      text = Export.text(original, ctx.ruleset, stats, title: "Тестовый билд")

      result = Import.parse(text, ctx.ruleset)

      assert result.title == "Тестовый билд"
      assert result.build.levels == original.levels
      assert result.build.race == original.race
      assert result.build.alignment == original.alignment
      # The printed scores are a character sheet — racial modifiers come back off.
      assert result.build.base_abilities == original.base_abilities
      assert result.build.ability_increases == original.ability_increases
      assert result.build.skills == original.skills
    end

    test "feats come back, even though the text never says which slot", ctx do
      original = build(ctx.ruleset)
      stats = Rules.compute(original, ctx.ruleset)
      text = Export.text(original, ctx.ruleset, stats)

      result = Import.parse(text, ctx.ruleset)

      assert Build.feats_taken(result.build, 10) == Build.feats_taken(original, 10)
    end

    test "the numbers we compute for the re-read build match the source's own", ctx do
      original = build(ctx.ruleset)
      stats = Rules.compute(original, ctx.ruleset)
      text = Export.text(original, ctx.ruleset, stats)

      result = Import.parse(text, ctx.ruleset)
      rows = Import.comparison(result, Rules.compute(result.build, ctx.ruleset))

      refute rows == []

      for row <- rows, row.label in ["Hitpoints", "BAB", "Skillpoints"] do
        assert row.source == row.ours, "#{row.label}: #{row.source} != #{row.ours}"
      end
    end
  end

  describe "tolerance" do
    test "class shorthand, lower case and missing zeroes all read", ctx do
      text = """
      1. fighter(1): power attack
      2: FIGHTER (2)
      3) Fighter(3)
      04: dwarven defender(1)
      05: DD(2)
      06: Weapon master(1)
      07: WM(2)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [
               :fighter,
               :fighter,
               :fighter,
               :dwarven_defender,
               :dwarven_defender,
               :weapon_master,
               :weapon_master
             ]
    end

    test "Discord quoting and code fences are stripped", ctx do
      text = """
      ```
      > Human, Lawful Good
      > LEVELING GUIDE
      > 01: Fighter(1)
      ```
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.race == :human
      assert result.build.alignment == :lawful_good
      assert result.build.levels == [:fighter]
    end

    test "the shard's Russian race names read, collision and all", ctx do
      # `Гном` is Dwarf and `Карлик` is Gnome — the collision CLAUDE.md §4 warns
      # about. A parser that resolves the words by looks would get both wrong.
      for {line, expected} <- [
            {"Гном, Lawful Good", :dwarf},
            {"Карлик, Lawful Good", :gnome},
            {"Гоблин, Lawful Good", :halfling},
            {"Могучий человек, Lawful Good", :half_orc},
            {"Светлый эльф, Lawful Good", :half_elf},
            {"Тёмный Эльф, Lawful Good", :elf},
            {"Темный эльф, Lawful Good", :elf},
            {"Гном (Dwarf), Lawful Good", :dwarf},
            {"Half-Orc, Lawful Good", :half_orc},
            {"half elf, Lawful Good", :half_elf}
          ] do
        assert Import.parse(line, ctx.ruleset).build.race == expected, "не прочиталось: #{line}"
      end
    end

    test "alignment reads as a name, as an id and as the community's shorthand", ctx do
      for {line, expected} <- [
            {"Human, Lawful Good", :lawful_good},
            {"Human, lawful_good", :lawful_good},
            {"Human, LG", :lawful_good},
            {"Human, CE", :chaotic_evil},
            {"Human, TN", :true_neutral},
            {"Human, Neutral", :true_neutral}
          ] do
        assert Import.parse(line, ctx.ruleset).build.alignment == expected,
               "не прочиталось: #{line}"
      end
    end

    test "the ability bump reads wherever the line puts it", ctx do
      text = """
      LEVELING GUIDE
      01: Fighter(1)
      02: Fighter(2)
      03: Fighter(3)
      04: Fighter(4): Weapon focus (longsword) +1 str, 19
      05: Fighter(5)
      06: Fighter(6)
      07: Fighter(7)
      08: Fighter(8): +1 DEX, 13
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.ability_increases == %{4 => :str, 8 => :dex}
      assert :weapon_focus in Build.feats_taken(result.build, 8)
    end

    test "feat names read by acronym and by Russian wiki alias", ctx do
      text = """
      LEVELING GUIDE
      01: Fighter(1): Живучесть
      02: Fighter(2): ITWF
      """

      result = Import.parse(text, ctx.ruleset)
      taken = Build.feats_taken(result.build, 2)

      assert :improved_two_weapon_fighting in taken
      # Toughness is granted by the class on Siala, so it is reported rather
      # than placed — but the name itself resolved, which is what is under test.
      assert :toughness in taken or
               Enum.any?(result.issues, &match?({:feat_granted_here, 1, :toughness}, &1))
    end

    test "the per-level skill guide reads even without its header", ctx do
      text = """
      LEVELING GUIDE
      01: Rogue(1)
      02: Rogue(2)
      01: Discipline +4 (4), Кувырок +2 (2) x2
      02: Discipline +1 (5)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.skills == %{1 => %{discipline: 4, tumble: 2}, 2 => %{discipline: 1}}
    end
  end

  describe "honesty" do
    test "an unknown feat is reported, never swallowed", ctx do
      text = """
      LEVELING GUIDE
      01: Fighter(1): Power Attack, Неведомый Фит
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:fighter]
      assert :power_attack in Build.feats_taken(result.build, 1)
      assert Enum.any?(result.issues, &match?({:unknown_feat, 1, "Неведомый Фит"}, &1))
    end

    test "an unreadable class stops the ladder instead of shifting it up", ctx do
      # Levels 3 and 4 are readable, but importing them would make level 3 the
      # character's second level — a different build, silently.
      text = """
      LEVELING GUIDE
      01: Fighter(1)
      02: Совершенно неизвестный класс(1)
      03: Fighter(2)
      04: Fighter(3)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:fighter]
      assert Enum.any?(result.issues, &match?({:unknown_class, 2, _}, &1))
      assert Enum.any?(result.issues, &match?({:ladder_stopped, 1}, &1))
    end

    test "a gap in the level numbers stops the ladder too", ctx do
      text = """
      LEVELING GUIDE
      01: Fighter(1)
      03: Fighter(2)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:fighter]
      assert Enum.any?(result.issues, &match?({:level_gap, 2, 3}, &1))
    end

    test "an abbreviation nobody derives is read but declared as a reading", ctx do
      result = Import.parse("LEVELING GUIDE\n01: Ftr(1)\n", ctx.ruleset)

      assert result.build.levels == [:fighter]
      assert Enum.any?(result.issues, &match?({:class_guessed, 1, "Ftr", :fighter}, &1))
    end

    test "a shorthand two classes answer to is refused, not tossed for", ctx do
      # `Pal` fits Paladin and Pale master equally well.
      result = Import.parse("LEVELING GUIDE\n01: Pal(1)\n", ctx.ruleset)

      assert result.build.levels == []
      assert Enum.any?(result.issues, &match?({:ambiguous_class, 1, "Pal", _}, &1))
    end

    test "the header's own numbers stay out of the build and are shown for comparison", ctx do
      text = """
      Сильный - Fighter(1)
      Human, Lawful Good
      Hitpoints: 764
      AB: +71
      AC (naked/mundane armor and shield): 71/80
      LEVELING GUIDE
      01: Fighter(1)
      """

      result = Import.parse(text, ctx.ruleset)
      stats = Rules.compute(result.build, ctx.ruleset)

      # One level of Fighter is nowhere near 764 hit points, and the import did
      # not pretend otherwise.
      assert stats.hp < 100

      rows = Import.comparison(result, stats)
      hp = Enum.find(rows, &(&1.label == "Hitpoints"))

      assert hp.source == "764"
      assert hp.ours == Integer.to_string(stats.hp)
    end

    test "the SKILLS totals are not imported, and the reason is said", ctx do
      text = """
      Human, Lawful Good
      LEVELING GUIDE
      01: Rogue(1)
      SKILLS
      Discipline 43 (48)
      Tumble 40 (45)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.skills == %{}
      assert length(result.source.skills) == 2
      assert Enum.any?(result.issues, &match?({:skills_not_placed, 2}, &1))
    end

    test "a header without a leveling guide produces no levels at all", ctx do
      # The split states totals, not order — and order decides base attack and
      # saves past 20 outright.
      text = """
      Каменный - Fighter(10), Dwarven defender(23), Weapon master(7)
      Гном (Dwarf), Lawful Good
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == []
      assert Enum.any?(result.issues, &match?({:no_leveling_guide}, &1))
      assert length(result.source.declared) == 3
    end

    test "the header and the ladder are checked against each other", ctx do
      text = """
      Полукровка - Fighter(3)
      Human, Lawful Good
      LEVELING GUIDE
      01: Fighter(1)
      02: Fighter(2)
      """

      result = Import.parse(text, ctx.ruleset)

      assert Enum.any?(result.issues, &match?({:split_mismatch, "Fighter", 3, 2}, &1))
    end

    test "a feat the class hands over for free does not eat a slot", ctx do
      # Siala grants Toughness at Fighter 1, so a build listing it there is
      # spending nothing — and the player is told the slot stayed open.
      text = """
      Human, Lawful Good
      LEVELING GUIDE
      01: Fighter(1): Toughness
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.feats == %{}
      assert Enum.any?(result.issues, &match?({:feat_granted_here, 1, :toughness}, &1))
    end

    test "a feat with no slot to go into is reported rather than dropped", ctx do
      text = """
      Human, Lawful Good
      LEVELING GUIDE
      01: Wizard(1)
      02: Wizard(2): Power Attack
      """

      result = Import.parse(text, ctx.ruleset)

      assert Enum.any?(result.issues, &match?({:feat_no_slot, 2, :power_attack}, &1))
    end

    test "a line nobody could classify is listed, not ignored", ctx do
      text = """
      Human, Lawful Good
      Этот билд я собрал в 2019 году
      LEVELING GUIDE
      01: Fighter(1)
      """

      result = Import.parse(text, ctx.ruleset)

      assert Enum.any?(
               result.issues,
               &match?({:ignored_line, _, "Этот билд я собрал в 2019 году"}, &1)
             )
    end

    test "nothing readable is an empty build that says so, not a crash", ctx do
      result = Import.parse("привет, как дела?", ctx.ruleset)

      refute result.read.anything?
      assert result.build.levels == []
    end

    test "junk input of every shape comes back as a result", ctx do
      for input <- ["", "   ", "\n\n\n", String.duplicate("x", 200_000), nil, 42] do
        assert %{build: %Build{}, issues: issues} = Import.parse(input, ctx.ruleset)
        assert is_list(issues)
      end
    end
  end

  describe "wording" do
    test "every issue this module can produce has Russian wording", ctx do
      assert length(Import.issue_forms()) > 20

      for issue <- Import.issue_forms() do
        text = Import.issue_text(issue, ctx.ruleset)

        assert text != ""
        # `inspect/1` is the fallback; anything hitting it needs wording.
        refute text =~ ~r/^\{/, "no Russian wording for #{inspect(issue)}"
      end
    end

    test "every issue lands in a named group" do
      for issue <- Import.issue_forms() do
        assert Import.issue_kind(issue) != ""
      end

      # The two groups that answer different questions: our dictionary came up
      # short, versus we could not tell what the line was at all.
      assert Import.issue_kind({:unknown_feat, 1, "x"}) == "Не распознано"
      assert Import.issue_kind({:ignored_line, 1, "x"}) == "Пропущенные строки"
    end
  end

  describe "фит с выбором" do
    test "скобка после имени становится выбором, а не оговоркой", ctx do
      text = """
      LEVELING GUIDE
      01: Wizard(1): Spell Focus (Evocation)
      02: Wizard(2)
      03: Wizard(3): Greater Spell Focus (Evocation)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.feats[1][:general] == {:spell_focus, :evocation}
      assert result.build.feats[3][:general] == {:greater_spell_focus, :evocation}

      # ⚠️ Положительный контроль: раньше здесь падала оговорка
      # `feat_qualifier_dropped`, и её отсутствие должно значить «выбор
      # доехал», а не «мы перестали замечать скобку».
      refute Enum.any?(result.issues, &match?({:feat_qualifier_dropped, _, _, _}, &1))
      refute Enum.any?(result.issues, &match?({:feat_choice_unknown, _, _, _}, &1))
    end

    test "тот же фит в другой школе — законный второй пик, а не дубликат", ctx do
      text = """
      LEVELING GUIDE
      01: Wizard(1): Spell Focus (Evocation)
      02: Wizard(2)
      03: Wizard(3): Spell Focus (Necromancy)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.feats[1][:general] == {:spell_focus, :evocation}
      assert result.build.feats[3][:general] == {:spell_focus, :necromancy}
      refute Enum.any?(result.issues, &match?({:feat_already_owned, _, _}, &1))
    end

    test "тот же фит в ТОЙ ЖЕ школе остаётся дубликатом", ctx do
      text = """
      LEVELING GUIDE
      01: Wizard(1): Spell Focus (Evocation)
      02: Wizard(2)
      03: Wizard(3): Spell Focus (Evocation)
      """

      result = Import.parse(text, ctx.ruleset)

      assert {:feat_already_owned, 3, :spell_focus} in result.issues
      assert result.build.feats[3] == nil
    end

    # ⚠️ ЗАДАЧА 3.5 поменяла ответ на первую половину этого теста, и в лучшую
    # сторону: у домена `weapon` появился справочник (`weapons.json`), поэтому
    # «Weapon focus (longsword)» из чужого билда теперь доезжает до нас ВЫБОРОМ,
    # а не теряется оговоркой. Раньше здесь стоял `{:feat_qualifier_dropped, …}`.
    test "уточнение из чужого билда доезжает выбором, опечатка — своей ошибкой", ctx do
      text = """
      LEVELING GUIDE
      01: Fighter(1): Weapon focus (longsword)
      02: Fighter(2)
      03: Fighter(3): Spell Focus (Evokation)
      """

      result = Import.parse(text, ctx.ruleset)

      # Слот здесь бонусный воинский, а не общий (§6: тратится самый узкий
      # подходящий), поэтому проверяется значение, а не ключ слота.
      assert Map.values(result.build.feats[1]) == [{:weapon_focus, :longsword}]
      refute Enum.any?(result.issues, &match?({:feat_qualifier_dropped, _, _, _}, &1))

      # А это другое: справочник есть, школы в нём нет. Приравнять одно
      # к другому значило бы спрятать опечатку игрока.
      assert {:feat_choice_unknown, 3, :spell_focus, "Evokation"} in result.issues
    end

    # Третий исход `resolve_choice/6` — «справочника у домена нет вовсе» — после
    # задачи 3.5 в данных не встречается: неразрешимых доменов не осталось ни
    # одного. Механизм при этом обязан работать, поэтому свидетель синтетический.
    test "справочника у домена нет — уточнение честно теряется оговоркой", ctx do
      text = """
      LEVELING GUIDE
      01: Fighter(1): Weapon focus (longsword)
      """

      blind = %{
        ctx.ruleset
        | choice_domains:
            Map.put(ctx.ruleset.choice_domains, :weapon, %{
              values: nil,
              flags: %{},
              source: nil
            })
      }

      result = Import.parse(text, blind)

      assert {:feat_qualifier_dropped, 1, :weapon_focus, "longsword"} in result.issues
      assert Map.values(result.build.feats[1]) == [:weapon_focus]
    end

    test "наш собственный экспорт с выбором читается обратно в тот же билд" do
      # ⚠️ Задача 3.145: `vanilla` явно, а не `ctx.ruleset` модуля
      # (`siala_41`) — единственный тест этого describe, гоняющий
      # `Export.text` через `Import.parse` туда-обратно, а читает наш
      # экспорт обратно только `vanilla` (см. moduledoc).
      ruleset = Data.ruleset!("vanilla")
      %Build{} = base = build(ruleset)

      # ⚠️ Фит с выбором взят НЕ `Spell Focus`, и это не косметика: 3-й уровень
      # у этой лестницы воинский, а воин `spell_focus` на своём уровне выбрать
      # не может вовсе (`unavailable_feats`, задача 1.10 шаг 2) — фикстура была
      # нелегальной, импорт теперь честно выбрасывает пик, и тест проверял бы
      # круговорот того, чего в билде быть не должно. `Skill Focus` — тот же
      # фит-с-параметром (домен `skill`), и воину он разрешён.
      original = %Build{
        base
        | feats: %{
            1 => %{{:class_bonus, :fighter} => :power_attack},
            3 => %{general: {:skill_focus, :discipline}}
          }
      }

      text = Export.text(original, ruleset, Rules.compute(original, ruleset))
      result = Import.parse(text, ruleset)

      assert result.build.feats == original.feats
    end
  end

  describe "нелегальная лестница" do
    # ⚠️ Проверяется НЕ «все отказы ядра», а подмножество, зависящее только
    # от лестницы. Импорт по контракту не переносит блок `SKILLS`, а фит может
    # не лечь в слот — включив требования фитов и рангов, отчёт получил бы
    # по шесть-семь строк на каждый вход в престиж, и все они были бы про то,
    # чего импорт не дочитал.
    defp guide(lines), do: "LEVELING GUIDE\n" <> Enum.join(lines, "\n") <> "\n"

    defp levels(class, from, to, class_from) do
      for n <- from..to, do: "#{n}: #{class}(#{n - from + class_from})"
    end

    test "потолок уровней престиж-класса ловится — по одной строке на каждую причину", ctx do
      # Мастер оружия на Сиале идёт до 31-го уровня класса; 32-й нелегален.
      #
      # ⚠️ Эта же лестница (ВМ с 10-го уровня персонажа) ЗАОДНО нарушает и
      # правило «11-й уровень престижа требует 20-й уровень персонажа» —
      # и это не огрех синтетики, а числовой факт устройства Сиалы: потолок
      # престиж-класса 31 в точности равен `41 (кап) − 11 (самый ранний
      # безопасный старт) + 1`, то есть максимуму уровней, который класс
      # может набрать, ни разу не взяв 11-й уровень раньше положенного.
      # Значит превысить 31 в принципе нельзя, не начав раньше 11-го уровня
      # персонажа, — то есть не нарушив заодно и второе правило. Оба отказа
      # верны одновременно, и белый список обязан показать оба, а не один.
      text = guide(levels("Fighter", 1, 9, 1) ++ levels("Weapon master", 10, 41, 1))

      result = Import.parse(text, ctx.ruleset)
      illegal = Enum.filter(result.issues, &match?({:illegal_level, _, _, _}, &1))

      assert [
               {:illegal_level, 10, :weapon_master, {:class_level_cap, :weapon_master, 31}},
               {:illegal_level, 20, :weapon_master, {:requires_character_level, 20}}
             ] == illegal

      assert Enum.all?(illegal, &(Import.issue_text(&1, ctx.ruleset) =~ "Weapon master"))
    end

    test "⚠️ легальный билд с непрочитанными фитами и навыками молчит", ctx do
      # Положительный контроль ко всему разделу: у этого билда ядро отбивает
      # вход в престиж по шести фитам и рангам, которых импорт не переносит, —
      # и именно эти отказы в отчёт попасть НЕ должны. Иначе тест выше зеленел
      # бы вместе с отчётом, который никто не станет читать.
      text = guide(levels("Fighter", 1, 10, 1) ++ levels("Weapon master", 11, 41, 1))

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels |> Enum.uniq() == [:fighter, :weapon_master]
      assert Enum.filter(result.issues, &match?({:illegal_level, _, _, _}, &1)) == []

      # Доказательство, что предмет проверки вообще попал в поле зрения:
      # ядро на этом же билде отказы ДАЁТ, просто не из нашего подмножества.
      assert {:error, reasons} =
               Rules.validate_level_up(
                 result.build,
                 %{class: :weapon_master, at: 11},
                 ctx.ruleset
               )

      assert Enum.any?(reasons, &match?({:requires_feat, _}, &1))
      refute Enum.any?(reasons, &match?({:class_level_cap, _, _}, &1))
    end

    # ⚠️ Пин ПЕРЕВЁРНУТ вместе с решением, а не обойдён (волна 4 починила
    # ядро). Здесь стоял тест, закреплявший баг ядра: `prestige_pre_epic/4`
    # считал уровни престижа по билду целиком, а уровень персонажа — по
    # моменту, и на готовой лестнице обвинял легального «Воина 10 / Мастера
    # оружия 31», то есть ровно ту форму билда, что лежит на вики. Теперь
    # обе половины считаются на решаемом уровне, и отказа нет.
    #
    # Волна 5: форма `{:requires_character_level, …}` включена в белый список
    # `@ladder_reasons` — причина исключения (баг ядра) закрыта, значит и
    # само исключение больше не нужно. Тест ниже проверяет уже не только ядро
    # напрямую (как было), но и то, что это доезжает до `result.issues` —
    # ради чего белый список и расширяли.
    test "уровень персонажа для престижа больше не обвиняет легальную лестницу", ctx do
      text = guide(levels("Fighter", 1, 10, 1) ++ levels("Weapon master", 11, 41, 1))
      result = Import.parse(text, ctx.ruleset)

      assert {:error, reasons} =
               Rules.validate_level_up(
                 result.build,
                 %{class: :weapon_master, at: 11},
                 ctx.ruleset
               )

      # 11-й уровень ВМ берётся на 21-м уровне персонажа — правило не нарушено.
      refute {:requires_character_level, 20} in reasons

      # ⚠️ До волны 5 эта строка была верна тривиально: форма была исключена
      # из белого списка, и пустой список ничего не доказывал бы про саму
      # лестницу. Теперь форма включена, и пустота — содержательная проверка:
      # легальный «Сагровик» её не получает.
      assert Enum.filter(result.issues, &match?({:illegal_level, _, _, _}, &1)) == []

      # Положительный контроль: `refute` выше зеленел бы и в мире, где правило
      # не работает вовсе. Та же лестница на уровень раньше — 11-й уровень ВМ
      # падает на 20-й уровень персонажа, и ядро отказывает.
      early = guide(levels("Fighter", 1, 9, 1) ++ levels("Weapon master", 10, 40, 1))
      early_result = Import.parse(early, ctx.ruleset)
      early_build = early_result.build

      assert {:error, early_reasons} =
               Rules.validate_level_up(
                 early_build,
                 %{class: :weapon_master, at: 20},
                 ctx.ruleset
               )

      assert {:requires_character_level, 20} in early_reasons

      # И тот же положительный контроль на уровне самого импорта, а не только
      # ядра напрямую: белый список обязан пропустить именно эту форму, и
      # именно на том уровне, где правило нарушено (31 уровень ВМ здесь ещё
      # не превышен — только правило раннего входа, поэтому строка ровно одна).
      assert Enum.filter(early_result.issues, &match?({:illegal_level, _, _, _}, &1)) ==
               [{:illegal_level, 20, :weapon_master, {:requires_character_level, 20}}]
    end

    test "ванильный ruleset не сыплет «нет данных» на каждый уровень", ctx do
      _ = ctx
      vanilla = Data.ruleset!("vanilla")
      text = guide(levels("Fighter", 1, 20, 1))

      result = Import.parse(text, vanilla)

      # Под ванилью overrides нет, и `max_classes` пришёл бы как
      # `{:missing_data, …}` двадцать раз подряд. Белый список форм это
      # отсекает — не фильтром «кроме missing_data», а тем, что таких форм
      # в нём просто нет.
      assert Enum.filter(result.issues, &match?({:illegal_level, _, _, _}, &1)) == []
    end

    # ⚠️ Отрицательный контроль на ПОЛНОЙ доступной выборке, а не на одном
    # билде. В этом проекте вывод по одному-двум примерам разваливался уже
    # несколько раз за один день (HANDOFF.md, «Выводы по недостаточной
    # выборке — трижды за день»), поэтому «Сагровика» одного недостаточно.
    #
    # Восемь готовых лестниц вики (`WikiBuildPage`, `priv/wiki_cache/siala/`)
    # — единственные реальные, легальные билды в репозитории, а не билды,
    # придуманные для теста. Каждый проходит через настоящий Export → Import
    # (наш собственный экспорт, прочитанный нашим же импортом) — ровно тот
    # путь, на котором баг ядра проявлялся: готовая лестница целиком, а не
    # билд, растущий по уровню в конструкторе (там `whole` и есть текущий
    # момент, и половины не могли разойтись).
    test "ни одна из восьми лестниц вики не получает requires_character_level после экспорта-импорта",
         ctx do
      titles = WikiBuildPage.discover()

      # Страж от «пустой проверки»: если вдруг найдётся 0 или 1 страница
      # (кэш пуст, дискавери сломан), `for` ниже пройдёт по пустому списку
      # и ничего не докажет — тест обязан заметить это раньше, чем смолчать.
      assert length(titles) >= 8, "ожидалась полная выборка, а не срез: #{inspect(titles)}"

      for title <- titles do
        page = WikiBuildPage.load!(title)
        build = WikiBuildPage.to_build(page, ctx.ruleset)
        stats = Rules.compute(build, ctx.ruleset)
        text = Export.text(build, ctx.ruleset, stats)

        result = Import.parse(text, ctx.ruleset)

        # Доказательство, что билд реально прочитался обратно целиком, а не
        # молчит пустым импортом: иначе пустой `hits` ниже не доказывал бы
        # ничего — ровно ловушка «пустой проверки» (AGENT_QUEUE, уроки дня).
        assert length(result.build.levels) == length(build.levels),
               "#{title}: лестница прочиталась не целиком (#{length(result.build.levels)} " <>
                 "из #{length(build.levels)}) — #{inspect(result.issues)}"

        hits =
          Enum.filter(
            result.issues,
            &match?({:illegal_level, _, _, {:requires_character_level, _}}, &1)
          )

        assert hits == [],
               "#{title}: неожиданный отказ requires_character_level: #{inspect(hits)}"
      end
    end

    # Волна 6: `{:requires_race, …}` и `{:requires_alignment, …}` включены
    # в `@ladder_reasons` тем же способом. Отрицательный контроль повторяет
    # схему выше — полная выборка, а не одна страница, — а положительные
    # проверяют оба класса, у которых требование расы вообще существует
    # (`arcane_archer`, `dwarven_defender`), и оба ПУТИ, которыми в ядро
    # приходит требование мировоззрения (`requirements.alignment` и
    # отдельное поле `alignment_restriction`, см. комментарий у
    # `@ladder_reasons`).
    test "ни одна из восьми лестниц вики не получает requires_race или requires_alignment после экспорта-импорта",
         ctx do
      titles = WikiBuildPage.discover()

      assert length(titles) >= 8, "ожидалась полная выборка, а не срез: #{inspect(titles)}"

      for title <- titles do
        page = WikiBuildPage.load!(title)
        build = WikiBuildPage.to_build(page, ctx.ruleset)
        stats = Rules.compute(build, ctx.ruleset)
        text = Export.text(build, ctx.ruleset, stats)

        result = Import.parse(text, ctx.ruleset)

        assert length(result.build.levels) == length(build.levels),
               "#{title}: лестница прочиталась не целиком (#{length(result.build.levels)} " <>
                 "из #{length(build.levels)}) — #{inspect(result.issues)}"

        # ⚠️ Раса и мировоззрение обязаны доехать до билда БУКВАЛЬНО теми же
        # значениями, что на странице вики, — иначе пустой `hits` ниже не
        # доказывал бы ничего: билд с нечитаемой расой не может получить
        # `requires_race`, он получил бы `unknown_race` и НЕ прошёл бы это
        # утверждение раньше, чем дошёл бы до сравнения отказов.
        assert result.build.race == build.race,
               "#{title}: раса прочиталась не так (#{inspect(build.race)} -> " <>
                 "#{inspect(result.build.race)}) — #{inspect(result.issues)}"

        assert result.build.alignment == build.alignment,
               "#{title}: мировоззрение прочиталось не так (#{inspect(build.alignment)} -> " <>
                 "#{inspect(result.build.alignment)}) — #{inspect(result.issues)}"

        hits =
          Enum.filter(result.issues, fn
            {:illegal_level, _, _, {:requires_race, _}} -> true
            {:illegal_level, _, _, {:requires_alignment, _}} -> true
            _ -> false
          end)

        assert hits == [],
               "#{title}: неожиданный отказ по расе/мировоззрению: #{inspect(hits)}"
      end
    end

    test "расовое требование: чужая раса — отказ, и коллизия имён не путает результат", ctx do
      # `Карлик` = Gnome, не Dwarf — ровно та коллизия имён, о которой
      # предупреждает CLAUDE.md §4 (`Гном` = Dwarf, `Карлик` = Gnome). Если бы
      # парсер перепутал направление, этот билд ошибочно прошёл бы расовое
      # требование Dwarven Defender вместо того, чтобы получить отказ.
      text = """
      Карлик, Lawful Good
      LEVELING GUIDE
      01: Fighter(1)
      02: Fighter(2)
      03: Fighter(3)
      04: Fighter(4)
      05: Dwarven defender(1)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.race == :gnome
      assert {:illegal_level, 5, :dwarven_defender, {:requires_race, [:dwarf]}} in result.issues
    end

    test "расовое требование: своя раса — легальный вход, та же коллизия в обратную сторону",
         ctx do
      # Обратная сторона коллизии: `Гном` = Dwarf, и билд с ней ОБЯЗАН пройти
      # расовое требование Dwarven Defender — единственного класса на этой
      # выборке, для которого коллизия могла бы дать ложный отказ.
      text = """
      Гном, Lawful Good
      LEVELING GUIDE
      01: Fighter(1)
      02: Fighter(2)
      03: Fighter(3)
      04: Fighter(4)
      05: Dwarven defender(1)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.race == :dwarf
      refute Enum.any?(result.issues, &match?({:illegal_level, _, _, {:requires_race, _}}, &1))
    end

    test "расовое требование ловится и у второго класса, не только у Dwarven Defender", ctx do
      # Ни один из восьми готовых билдов вики не берёт Arcane Archer, так что
      # отрицательный контроль выше его вообще не касается — нужен свой
      # положительный контроль, а не расширение выборки задним числом.
      text = """
      Human, Lawful Good
      LEVELING GUIDE
      01: Fighter(1)
      02: Fighter(2)
      03: Fighter(3)
      04: Fighter(4)
      05: Arcane archer(1)
      """

      result = Import.parse(text, ctx.ruleset)

      assert {:illegal_level, 5, :arcane_archer, {:requires_race, [:elf, :half_elf]}} in result.issues
    end

    test "требование мировоззрения: чужое мировоззрение — отказ", ctx do
      text = """
      Гном, Chaotic Good
      LEVELING GUIDE
      01: Fighter(1)
      02: Fighter(2)
      03: Fighter(3)
      04: Fighter(4)
      05: Dwarven defender(1)
      """

      result = Import.parse(text, ctx.ruleset)

      assert {:illegal_level, 5, :dwarven_defender, {:requires_alignment, %{require: ["lawful"]}}} in result.issues
    end

    test "требование мировоззрения приходит и вторым путём ядра — Purple Dragon Knight", ctx do
      # ⚠️ Находка, сделанная при подготовке этой волны: у Purple Dragon
      # Knight шард ЦЕЛИКОМ заменил `requirements` своим блоком (BAB +4,
      # четыре навыка), и в новой карте ключа `alignment` больше нет —
      # `ruleset.classes[:purple_dragon_knight].requirements.alignment ==
      # nil` в рантайме (проверено). Но шард отдельно объявляет
      # `alignment_restriction: "any lawful"` (страница класса: «Характер:
      # Любой Законопослушный»), и её проверяет ВТОРАЯ, независимая ветка —
      # `Rules.LevelUp.alignment_restriction/2`, тот же механизм, что несёт
      # ограничение Monk/Barbarian (CLAUDE.md §9). На выходе та же форма
      # причины, и белый список ловит её независимо от того, из какого поля
      # ядра она взялась — поэтому здесь отдельный тест, а не полагание на
      # то, что «раса и мировоззрение работают одинаково у всех классов».
      text = """
      Human, Chaotic Good
      LEVELING GUIDE
      01: Fighter(1)
      02: Fighter(2)
      03: Fighter(3)
      04: Fighter(4)
      05: Purple dragon knight(1)
      """

      result = Import.parse(text, ctx.ruleset)

      assert {:illegal_level, 5, :purple_dragon_knight,
              {:requires_alignment, %{require: ["lawful"]}}} in result.issues
    end

    test "нераспознанные раса и мировоззрение не маскируются под нарушение требования", ctx do
      # ⚠️ Если импорт не смог прочитать расу или мировоззрение, ядро видит
      # `nil`, который не входит ни в один список допустимых значений, и
      # честно отказывает — но это суждение о ТЕКСТЕ, а не о билде. Отчёт
      # обязан нести собственную оговорку рядом (`unknown_race` /
      # `unknown_alignment`), иначе отказ выглядит как «билд нелегален»,
      # хотя на деле «мы не поняли, что было написано».
      unresolved_race = """
      Зыфх, Lawful Good
      LEVELING GUIDE
      01: Fighter(1)
      02: Fighter(2)
      03: Fighter(3)
      04: Fighter(4)
      05: Dwarven defender(1)
      """

      race_result = Import.parse(unresolved_race, ctx.ruleset)

      assert race_result.build.race == nil
      assert {:unknown_race, "Зыфх"} in race_result.issues

      # Отказ по расе действительно появляется (nil не входит в [:dwarf]) —
      # и он ОБЯЗАН быть виден рядом со своей оговоркой, а не вместо неё.
      assert {:illegal_level, 5, :dwarven_defender, {:requires_race, [:dwarf]}} in race_result.issues

      unresolved_alignment = """
      Гном, Мирно-Пофигистичное
      LEVELING GUIDE
      01: Fighter(1)
      02: Fighter(2)
      03: Fighter(3)
      04: Fighter(4)
      05: Dwarven defender(1)
      """

      alignment_result = Import.parse(unresolved_alignment, ctx.ruleset)

      assert alignment_result.build.alignment == nil
      assert {:unknown_alignment, "Мирно-Пофигистичное"} in alignment_result.issues

      assert {:illegal_level, 5, :dwarven_defender, {:requires_alignment, %{require: ["lawful"]}}} in alignment_result.issues
    end

    # Волна 8: `{:requires_class_level, …}` и `{:max_character_level, …}`
    # включены в `@ladder_reasons` (AGENT_QUEUE.md §7). Реальных данных,
    # где эти формы всплывают ГОЛЫМИ (не внутри `any_of`), в справочниках
    # нет — см. следующий тест и комментарий у `@ladder_reasons` — поэтому
    # положительная половина проверяется синтетическим классом, а не одним
    # из двенадцати престиж-классов ruleset'а.
    test "requires_class_level и max_character_level доезжают до пользователя; requires_feat/requires_skill_ranks — по-прежнему нет",
         ctx do
      # `class_levels` у настоящих классов (Pale Master/Arcane Archer/Red
      # Dragon Disciple) лежит ТОЛЬКО внутри `any_of` (следующий тест), а
      # `max_character_level` не стоит ни у одного класса вовсе — только
      # у фитов. Без синтетического класса включение было бы недоказуемо
      # тестом, только чтением исходников.
      probe_class = %{
        Map.fetch!(ctx.ruleset.classes, :dwarven_defender)
        | id: :probe_class,
          name: "Probe class",
          prestige?: false,
          requirements: %{
            "class_levels" => %{"fighter" => 4},
            "max_character_level" => 1,
            "feats" => ["dodge"],
            "skills" => %{"discipline" => 99}
          },
          requirements_raw: nil,
          alignment_restriction: nil,
          alignment_restriction_raw: nil
      }

      ruleset = %{ctx.ruleset | classes: Map.put(ctx.ruleset.classes, :probe_class, probe_class)}

      text = """
      Human, Lawful Good
      LEVELING GUIDE
      01: Fighter(1)
      02: Probe class(1)
      """

      result = Import.parse(text, ruleset)
      illegal = Enum.filter(result.issues, &match?({:illegal_level, _, _, _}, &1))

      # Включённые формы доехали до пользователя.
      assert {:illegal_level, 2, :probe_class, {:requires_class_level, :fighter, 4}} in illegal
      assert {:illegal_level, 2, :probe_class, {:max_character_level, 1}} in illegal

      # Положительный контроль на срез: ядро на ЭТОМ ЖЕ уровне видит и
      # `requires_feat`, и `requires_skill_ranks` — список не «пропускает
      # всё», он именно фильтрует.
      core = Rules.illegal_class_levels(result.build, ruleset)
      assert Enum.any?(core, &match?({2, :probe_class, {:requires_feat, :dodge}}, &1))

      assert Enum.any?(
               core,
               &match?({2, :probe_class, {:requires_skill_ranks, :discipline, 99}}, &1)
             )

      # ...а до пользователя они по-прежнему не доезжают.
      refute Enum.any?(illegal, &match?({:illegal_level, _, _, {:requires_feat, _}}, &1))

      refute Enum.any?(
               illegal,
               &match?({:illegal_level, _, _, {:requires_skill_ranks, _, _}}, &1)
             )
    end

    test "Red Dragon Disciple без арканового каста теперь отмечен — any_of читается рекурсивно",
         ctx do
      # ⚠️ Здесь стояло «по-прежнему не отмечены» — это документировало
      # ГРАНИЦУ волны 8: она включила голую форму `:requires_class_level`,
      # но не голову `:requires_any_of`, под которой эта форма и приходит
      # у всех трёх классов, что её несут (`class_levels` в
      # `priv/rules/vanilla/class_requirements.json` стоит только ВНУТРИ
      # дизъюнкции — Pale Master принимает Барда, Соркерера ИЛИ Мага,
      # `Prereqs` не разворачивает ветки наружу).
      #
      # ЗАКРЫТО задачей от 17.08.2026 (AGENT_QUEUE.md §7, «`Builder.Import`
      # не ловит „нужен уровень другого класса“»): `ladder_reason?/1`
      # разворачивает дизъюнкцию рекурсивно по каждой причине каждой ветки,
      # и претензия долетает до пользователя той же формой, какую видит
      # ядро.
      text = """
      Human, Chaotic Good
      LEVELING GUIDE
      01: Fighter(1)
      02: Red dragon disciple(1)
      """

      result = Import.parse(text, ctx.ruleset)

      any_of_reason =
        {:requires_any_of,
         [
           [{:requires_class_level, :bard, 1}],
           [{:requires_class_level, :sorcerer, 1}]
         ]}

      assert {:error, reasons} =
               Rules.validate_level_up(
                 result.build,
                 %{class: :red_dragon_disciple, at: 2},
                 ctx.ruleset
               )

      # Ядро видит претензию (завёрнутую в дизъюнкцию по двум классам).
      assert any_of_reason in reasons

      # И теперь она же доезжает до пользователя — тем же уровнем, той же
      # формой причины, а не пересказанной своими словами.
      assert {:illegal_level, 2, :red_dragon_disciple, any_of_reason} in result.issues

      # Печать не потребовала своей фразы: `issue_text/2` зовёт тот же
      # `Labels.reason/2`, что уже печатает эту форму у конструктора и
      # экрана просмотра — «или» соединяет альтернативы, а не перечисление
      # без объяснения, что это варианты одного отказа.
      printed =
        Import.issue_text({:illegal_level, 2, :red_dragon_disciple, any_of_reason}, ctx.ruleset)

      assert printed =~ "нужен Bard 1 или нужен Sorcerer 1"
    end

    test "Pale Master без арканового каста отмечен — та же дизъюнкция, другой класс, три ветки",
         ctx do
      text = """
      Human, True Neutral
      LEVELING GUIDE
      01: Fighter(1)
      02: Pale master(1)
      """

      result = Import.parse(text, ctx.ruleset)

      assert {:illegal_level, 2, :pale_master,
              {:requires_any_of,
               [
                 [{:requires_class_level, :bard, 3}],
                 [{:requires_class_level, :sorcerer, 3}],
                 [{:requires_class_level, :wizard, 3}]
               ]}} in result.issues
    end

    test "Pale Master с тремя уровнями волшебника закрывает дизъюнкцию — легальный вход не отмечен",
         ctx do
      # Положительный контроль к предыдущему тесту: любая из трёх веток
      # удовлетворяет дизъюнкцию целиком, и волшебник — одна из них.
      # Мировоззрение то же (True Neutral, «any non-good»), чтобы билд не
      # падал по отдельному требованию Pale Master и претензия по любому
      # `:illegal_level` означала бы именно провал дизъюнкции.
      text = """
      Human, True Neutral
      LEVELING GUIDE
      01: Wizard(1)
      02: Wizard(2)
      03: Wizard(3)
      04: Pale master(1)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:wizard, :wizard, :wizard, :pale_master]
      assert Enum.filter(result.issues, &match?({:illegal_level, _, _, _}, &1)) == []
    end

    test "оба ruleset'а видят одну и ту же дизъюнкцию у Arcane Archer — сиальский слой заменяет requirements целиком, но не форму any_of" do
      # ⚠️ Не дублирует тесты про Pale Master/RDD выше: у `arcane_archer`
      # (и только у него из трёх) сиальский слой ЗАМЕНЯЕТ `requirements`
      # целиком (`siala_41/classes.json` → `what: "requirements"`), а не
      # добавляет к ванильным. Если бы замена когда-нибудь потеряла форму
      # дизъюнкции — сузила её до одной ветки, заменила на голый
      # `class_levels` — этот файл узнал бы об этом только отсюда: другого
      # теста на форму именно этого класса под обоими ruleset'ами нет.
      #
      # Раса взята из числа разрешённых (`half_elf`), чтобы `{:requires_race,
      # …}` не заслонял собой проверяемую претензию; BAB и фит `Weapon focus`
      # намеренно НЕ удовлетворены — обе формы вне `@ladder_reasons`
      # (см. комментарий у списка), поэтому собирать под них билд незачем:
      # они не создадут лишней строки, даже оставшись неудовлетворёнными.
      text = """
      Half-elf, Lawful Good
      LEVELING GUIDE
      01: Fighter(1)
      02: Arcane archer(1)
      """

      for ruleset_name <- ["vanilla", "siala_41"] do
        ruleset = Data.ruleset!(ruleset_name)
        result = Import.parse(text, ruleset)

        assert {:illegal_level, 2, :arcane_archer,
                {:requires_any_of,
                 [
                   [{:requires_class_level, :bard, 1}],
                   [{:requires_class_level, :sorcerer, 1}],
                   [{:requires_class_level, :wizard, 1}]
                 ]}} in result.issues,
               "#{ruleset_name}: #{inspect(result.issues)}"
      end
    end

    test "дизъюнкция с непроверяемой веткой молчит целиком — защита от ложного обвинения", ctx do
      # ⚠️ Ровно тот случай, ради которого проверка рекурсивная, а не по
      # одной голове `:requires_any_of`. Одна ветка читаема (`class_levels`),
      # другая — нет (`skills`: блок `SKILLS` импорт не переносит, а ранг
      # ложится на потолок того уровня, на котором куплен, — угадать его
      # по шапке нельзя). Ядро видит претензию по обеим веткам сразу,
      # а импорт обязан промолчать ВСЮ дизъюнкцию: билд мог закрыть
      # альтернативу как раз той половиной, которую мы не читаем, и
      # обвинить его по прочитанной значило бы обвинить без права на ответ.
      probe_class = %{
        Map.fetch!(ctx.ruleset.classes, :dwarven_defender)
        | id: :probe_class,
          name: "Probe class",
          prestige?: false,
          requirements: %{
            "any_of" => [
              %{"class_levels" => %{"fighter" => 4}},
              %{"skills" => %{"discipline" => 99}}
            ]
          },
          requirements_raw: nil,
          alignment_restriction: nil,
          alignment_restriction_raw: nil
      }

      ruleset = %{ctx.ruleset | classes: Map.put(ctx.ruleset.classes, :probe_class, probe_class)}

      text = """
      Human, Lawful Good
      LEVELING GUIDE
      01: Fighter(1)
      02: Probe class(1)
      """

      result = Import.parse(text, ruleset)

      # Доказательство, что предмет проверки в поле зрения: ядро претензию
      # видит, обе ветки не закрыты.
      core = Rules.illegal_class_levels(result.build, ruleset)

      assert Enum.any?(
               core,
               &match?(
                 {2, :probe_class,
                  {:requires_any_of,
                   [
                     [{:requires_class_level, :fighter, 4}],
                     [{:requires_skill_ranks, :discipline, 99}]
                   ]}},
                 &1
               )
             )

      # ...а до пользователя не доезжает НИ ОДНОЙ строки об этом уровне.
      assert Enum.filter(result.issues, &match?({:illegal_level, _, _, _}, &1)) == []
    end

    test "вложенная дизъюнкция читается рекурсивно, а не только на один уровень", ctx do
      # Ветка дизъюнкции сама может оказаться дизъюнкцией — сегодня в данных
      # такого нет ни разу (все три реальных `any_of` плоские, см. комментарий
      # у `@ladder_reasons`), но предикат обязан быть готов к структуре,
      # а не только к частному случаю. Обе вложенные альтернативы здесь
      # читаемы, поэтому претензия обязана долететь так же, как долетает
      # плоская дизъюнкция в тестах выше, — и без зависания на вложенности.
      probe_class = %{
        Map.fetch!(ctx.ruleset.classes, :dwarven_defender)
        | id: :probe_class,
          name: "Probe class",
          prestige?: false,
          requirements: %{
            "any_of" => [
              %{"class_levels" => %{"fighter" => 10}},
              %{
                "any_of" => [
                  %{"class_levels" => %{"wizard" => 2}},
                  %{"class_levels" => %{"sorcerer" => 2}}
                ]
              }
            ]
          },
          requirements_raw: nil,
          alignment_restriction: nil,
          alignment_restriction_raw: nil
      }

      ruleset = %{ctx.ruleset | classes: Map.put(ctx.ruleset.classes, :probe_class, probe_class)}

      text = """
      Human, Lawful Good
      LEVELING GUIDE
      01: Fighter(1)
      02: Probe class(1)
      """

      result = Import.parse(text, ruleset)

      assert {:illegal_level, 2, :probe_class,
              {:requires_any_of,
               [
                 [{:requires_class_level, :fighter, 10}],
                 [
                   {:requires_any_of,
                    [
                      [{:requires_class_level, :wizard, 2}],
                      [{:requires_class_level, :sorcerer, 2}]
                    ]}
                 ]
               ]}} in result.issues
    end

    test "ни одна из восьми лестниц вики не получает requires_class_level или max_character_level после экспорта-импорта",
         ctx do
      # Тот же отрицательный контроль на полной выборке, что у волн 5 и 6:
      # обе формы сегодня нигде не встречаются голыми (см. комментарий у
      # `@ladder_reasons`), так что список должен остаться пустым — но
      # проверка дешёвая и ловит будущую регрессию данных, а не только
      # сегодняшнее состояние.
      titles = WikiBuildPage.discover()

      assert length(titles) >= 8, "ожидалась полная выборка, а не срез: #{inspect(titles)}"

      for title <- titles do
        page = WikiBuildPage.load!(title)
        build = WikiBuildPage.to_build(page, ctx.ruleset)
        stats = Rules.compute(build, ctx.ruleset)
        text = Export.text(build, ctx.ruleset, stats)

        result = Import.parse(text, ctx.ruleset)

        assert length(result.build.levels) == length(build.levels),
               "#{title}: лестница прочиталась не целиком (#{length(result.build.levels)} " <>
                 "из #{length(build.levels)}) — #{inspect(result.issues)}"

        hits =
          Enum.filter(result.issues, fn
            {:illegal_level, _, _, {:requires_class_level, _, _}} -> true
            {:illegal_level, _, _, {:max_character_level, _}} -> true
            _ -> false
          end)

        assert hits == [],
               "#{title}: неожиданный отказ requires_class_level/max_character_level: #{inspect(hits)}"
      end
    end
  end
end
