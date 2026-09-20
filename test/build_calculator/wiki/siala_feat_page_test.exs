defmodule BuildCalculator.Wiki.SialaFeatPageTest do
  use ExUnit.Case, async: true

  alias BuildCalculator.Wiki.SialaFeatPage

  # Only what the tests need to resolve; the real one is built from the vanilla
  # snapshot plus `siala_41/classes.json` by `mix wiki.parse`.
  @lookup %{
    classes: %{
      "shadowdancer" => "shadowdancer",
      "теневой танцор" => "shadowdancer",
      "монах" => "monk",
      "monk" => "monk",
      "вор" => "rogue",
      "воин" => "fighter",
      "рейнджер" => "ranger",
      "мастер оружия" => "weapon_master",
      "чемпион торма" => "champion_of_torm",
      # spelled with `ё` here and without it in the pages that link to it
      "черный страж" => "blackguard",
      "рыцарь пурпурного дракона" => "purple_dragon_knight"
    },
    class_ids: MapSet.new(~w(shadowdancer monk rogue fighter ranger weapon_master)),
    skill_ids: MapSet.new(~w(perform lore)),
    feat_ids: MapSet.new(~w(evasion defensive_roll bard_song)),
    race_ids: MapSet.new(~w(elf dwarf))
  }

  # A stand-in feat page carrying the shapes the 47 labelled ones mix: the colon
  # inside the bold and outside it, a value that runs on to the next line, a label
  # the module does not know, a section below the labels, and a category link at
  # the very bottom with no heading to hide behind.
  @labelled """
  '''Тип навыка:''' Классовый.

  '''Требования:''' Теневой танцор (Shadowdancer) 4 уровня.

  '''Особенности:''' Теневой танцор может использовать навык Скрытность.
  Продолжение на следующей строке.

  '''Пометка''': Использовать умение можно с 15 уровня.

  '''Использование:''' Автоматическое.

  == Ссылки ==
  *[https://nwn.fandom.com/wiki/Hide_in_plain_sight Hide in plain sight в англоязычной википедии]
  [[Категория:Фиты]]
  """

  describe "parse/2 — labels" do
    test "reads the four labels whatever punctuation the page used" do
      page = SialaFeatPage.parse(@labelled, @lookup)

      assert page.type == "class"
      assert page.type_raw == "Классовый."
      assert page.use == "automatic"
      assert page.use_raw == "Автоматическое."
      assert page.requirements_raw == "Теневой танцор (Shadowdancer) 4 уровня."
      assert page.problems == []
    end

    test "keeps a label's value that runs on to the following lines" do
      page = SialaFeatPage.parse(@labelled, @lookup)

      assert page.special_raw ==
               "Теневой танцор может использовать навык Скрытность.\nПродолжение на следующей строке."
    end

    test "keeps unrecognised labels instead of dropping them" do
      page = SialaFeatPage.parse(@labelled, @lookup)

      assert page.extra_labels == [{"пометка", "Использовать умение можно с 15 уровня."}]
    end

    test "does not let the category link leak into the last label" do
      page =
        SialaFeatPage.parse("'''Использование:''' Персональное.\n\n[[Категория:Фиты]]\n", @lookup)

      assert page.use_raw == "Персональное."
      assert page.use == "personal"
    end

    test "a bold line without a colon is not a label" do
      page =
        SialaFeatPage.parse(
          """
          '''Тип навыка:''' Основной.
          == Усиление ==
          *Формула:
           '''Усиление Тени = Уровни в классе Теневой танцор * 3'''
          """,
          @lookup
        )

      assert page.extra_labels == []
      assert page.type == "general"
    end

    test "labels below a heading are still labels" do
      page =
        SialaFeatPage.parse(
          """
          Болезнь претерпела изменения.
          == Изменения ==
          '''Радиус:''' Около 10 метров
          """,
          @lookup
        )

      assert page.extra_labels == [{"радиус", "Около 10 метров"}]
      assert page.lead_raw == "Болезнь претерпела изменения."
    end

    test "an unknown word in a known label is reported rather than coerced" do
      page =
        SialaFeatPage.parse("'''Использование:''' Посох (Unique Power). По выбору.\n", @lookup)

      assert page.use == nil
      assert page.problems == ["unknown 'Использование': Посох (Unique Power). По выбору."]
    end

    test "a qualifier after the known word is flagged, not dropped" do
      raw = "Автоматическое. Эффект срабатывает один раз в день."
      page = SialaFeatPage.parse("'''Использование:''' #{raw}\n", @lookup)

      assert page.use == "automatic"
      assert SialaFeatPage.qualified_use?(raw)
      refute SialaFeatPage.qualified_use?("Автоматическое.")
    end
  end

  describe "requirements/2" do
    test "reads a class and its level" do
      {[atom], []} =
        SialaFeatPage.requirements("Теневой танцор (Shadowdancer) 4 уровня.", @lookup)

      assert atom == %{
               kind: "class_level",
               class: "shadowdancer",
               level: 4,
               raw: "Теневой танцор (Shadowdancer) 4 уровня"
             }
    end

    test "attaches a level written as its own fragment to the class before it" do
      {[atom], []} = SialaFeatPage.requirements("Тайный Лучник (Monk), уровень 10.", @lookup)

      assert atom.kind == "class_level"
      assert atom.level == 10
    end

    test "tells a character level from a class level by the ordinal" do
      {atoms, []} = SialaFeatPage.requirements("21-й уровень, Ловкость 25+.", @lookup)

      assert atoms == [
               %{kind: "character_level", level: 21, raw: "21-й уровень"},
               %{kind: "ability", ability: "DEX", value: 25, raw: "Ловкость 25+"}
             ]
    end

    test "decides skill, feat and race by the English name in the parentheses" do
      {atoms, []} =
        SialaFeatPage.requirements(
          "Артистизм (Perform) 25, Песня барда (Bard song), Тёмный эльф (Elf).",
          @lookup
        )

      assert Enum.map(atoms, & &1.kind) == ["skill", "feat", "race"]
      assert Enum.at(atoms, 0).rank == 25
      assert Enum.at(atoms, 1).feat == "bard_song"
      assert Enum.at(atoms, 2).race == "elf"
    end

    test "reads a base attack bonus however the page words it" do
      for raw <- ["Базовый бонус к атаке +1 или выше.", "Базовый бонус атаки +1 и выше."] do
        {[atom], []} = SialaFeatPage.requirements(raw, @lookup)
        assert atom.kind == "bab"
        assert atom.value == 1
      end
    end

    test "reads a Russian class name with no English beside it" do
      {[atom], []} = SialaFeatPage.requirements("Рыцарь Пурпурного дракона 6 уровня.", @lookup)

      assert atom.class == "purple_dragon_knight"
      assert atom.level == 6
    end

    test "keeps a fragment it cannot read instead of dropping it" do
      {atoms, problems} =
        SialaFeatPage.requirements("Артистизм (Perform), какая-то небывальщина.", @lookup)

      assert [%{kind: "skill", rank: nil}, %{kind: "unparsed", raw: raw}] = atoms
      assert raw == "какая-то небывальщина"

      assert problems == ["requirement fragment not understood: какая-то небывальщина"]
    end

    # source: siala «Artist» revid 17357 — «Артистизм (Perform), умение можно
    # взять только на 1-ом уровне.» The one ceiling on these pages; everything
    # else states a floor.
    test "reads «можно взять только на N-ом уровне» as a ceiling" do
      {atoms, problems} =
        SialaFeatPage.requirements(
          "Артистизм (Perform), умение можно взять только на 1-ом уровне.",
          @lookup
        )

      assert [%{kind: "skill", rank: nil}, %{kind: "max_character_level", level: 1, raw: raw}] =
               atoms

      assert raw == "умение можно взять только на 1-ом уровне"
      assert problems == []
    end

    # source: siala «Keen sense» revid 18222 — the shard *widened* a vanilla
    # requirement, so vanilla's `race: [elf]` would refuse an assassin who
    # qualifies and a conjunction would demand both.
    test "reads a stated «или» as a choice, keeping both branches" do
      {[atom], []} =
        SialaFeatPage.requirements("Тёмный эльф (Elf) или Монах (Monk) 20 уровня.", @lookup)

      assert atom.kind == "any_of"
      assert atom.raw == "Тёмный эльф (Elf) или Монах (Monk) 20 уровня"

      assert atom.branches == [
               %{kind: "race", race: "elf", raw: "Тёмный эльф (Elf)"},
               %{kind: "class_level", class: "monk", level: 20, raw: "Монах (Monk) 20 уровня"}
             ]
    end

    test "a choice with a branch nobody could read stays prose entire" do
      {[atom], [_problem]} =
        SialaFeatPage.requirements("Тёмный эльф (Elf) или что-то ещё.", @lookup)

      assert atom.kind == "unparsed"
      assert atom.raw == "Тёмный эльф (Elf) или что-то ещё"
    end

    test "no label at all is nil, not an empty list of requirements" do
      assert SialaFeatPage.requirements(nil, @lookup) == {nil, []}
    end
  end

  # The five `Владение …` pages are a Siala invention with no vanilla counterpart,
  # and the only place the shard states what its weapons actually do.
  @weapons """
  [[Категория:Фиты]]
  == Общая информация ==
  Уникальное умение Сиалы.
  Все оружие поделено на четыре группы:

  # Кинжалы ('''2-4''' ''20/х2'' одноручное, урон - колющий) и кукри ('''1-6''' ''20/х2'' одноручное, урон - режущий). Персонаж может использовать их, начиная с 1-го уровня.
  # Посохи ('''1-12''' ''18-20/х2'' двуручное, урон - дробящий) и двусторонние булавы ('''1-8'''/'''1-8''' ''20/х2'' двустороннее, урон - дробящий). Доступны к использованию с 10-го уровня.
  # Моргенштерны (палицы) ('''3-36''' ''20/х2'' одноручное, урон - дробящий) могут быть использованы, начиная с 20-го уровня.
  # Тяжелые арбалеты ('''12-48''' ''20/х1'' двуручное/стрелковое, урон - колющий) могут быть использованы, начиная с 30-го уровня.

  == Возможность взятия фита ==
  Данный фит можно взять любому персонажу на любом уровне, на котором дается фит (каждые 3 уровня). Кроме того, этот фит могут взять:
  * [[Воин]] на своих доп фитах (на 1 уровне и каждые 2 уровня); на эпических фитах;
  * [[Рейнджер]] на уровнях, когда выбирает [http://nwn.wikia.com/wiki/Favored_enemy любимого врага];
  * [[Мастер оружия]] на эпических фитах.
  """

  describe "parse/2 — the weapon proficiency feats" do
    test "one unlock step per numbered item, in page order, with its level" do
      page = SialaFeatPage.parse(@weapons, @lookup)

      assert Enum.map(page.unlocks, & &1.level) == [1, 10, 20, 30]
      assert page.problems == []
    end

    test "reads damage, threat range, multiplier, grip and damage type" do
      page = SialaFeatPage.parse(@weapons, @lookup)
      [dagger, kukri] = hd(page.unlocks).weapons

      assert dagger.name_ru == "Кинжалы"
      assert dagger.damage == [%{min: 2, max: 4}]
      assert dagger.damage_raw == "2-4"
      assert dagger.crit == %{threat_low: 20, threat_high: 20, multiplier: 2}
      assert dagger.grip == "one_handed"
      assert dagger.damage_type == "piercing"
      assert dagger.ranged == nil

      assert kukri.name_ru == "кукри"
      assert kukri.damage_type == "slashing"
    end

    test "a threat range written as a range keeps both ends" do
      page = SialaFeatPage.parse(@weapons, @lookup)
      [staff, _mace] = Enum.at(page.unlocks, 1).weapons

      assert staff.crit == %{threat_low: 18, threat_high: 20, multiplier: 2}
      assert staff.grip == "two_handed"
    end

    test "a double weapon keeps one damage range per end" do
      page = SialaFeatPage.parse(@weapons, @lookup)
      [_staff, mace] = Enum.at(page.unlocks, 1).weapons

      assert mace.damage == [%{min: 1, max: 8}, %{min: 1, max: 8}]
      assert mace.grip == "double_sided"
    end

    test "a weapon name that itself carries a parenthesis survives" do
      page = SialaFeatPage.parse(@weapons, @lookup)
      [morningstar] = Enum.at(page.unlocks, 2).weapons

      assert morningstar.name_ru == "Моргенштерны (палицы)"
      assert morningstar.damage == [%{min: 3, max: 36}]
    end

    test "a ranged grip keeps both halves — how it is held and how it is fired" do
      page = SialaFeatPage.parse(@weapons, @lookup)
      [crossbow] = Enum.at(page.unlocks, 3).weapons

      assert crossbow.grip == "two_handed"
      assert crossbow.ranged == "projectile"
      assert crossbow.grip_raw == "двуручное/стрелковое"
    end

    test "«Возможность взятия фита» reads as slots, not as a flat list of classes" do
      page = SialaFeatPage.parse(@weapons, @lookup)

      assert page.taking.general
      assert Enum.map(page.taking.by_class, & &1.class) == ["fighter", "ranger", "weapon_master"]

      assert Enum.map(page.taking.by_class, & &1.slots) == [
               ["class_bonus", "epic_class_bonus"],
               ["favored_enemy"],
               ["epic_class_bonus"]
             ]
    end

    test "a page with no numbered weapon list has no unlocks and no slots" do
      page = SialaFeatPage.parse(@labelled, @lookup)

      assert page.unlocks == nil
      assert page.taking == nil
    end
  end

  describe "parse/2 — sentences the pages state outright" do
    test "reads 'moved from level N of X to level M'" do
      page =
        SialaFeatPage.parse(
          """
          Уклонение перенесено:
          * со 2-го уровня [[Вор|вора]] на 30-ый
          * с 1-го уровня [[Монах|монаха]] на 25-ый
          """,
          @lookup
        )

      assert page.moved == [
               %{
                 class: "rogue",
                 vanilla_level: 2,
                 siala_level: 30,
                 raw: "со 2-го уровня [[Вор|вора]] на 30-ый"
               },
               %{
                 class: "monk",
                 vanilla_level: 1,
                 siala_level: 25,
                 raw: "с 1-го уровня [[Монах|монаха]] на 25-ый"
               }
             ]
    end

    test "reads the sentence that turns a feat off" do
      assert SialaFeatPage.disabled("Этот фит на Сиале отключен, взять его нельзя. \n") ==
               "Этот фит на Сиале отключен, взять его нельзя."

      assert SialaFeatPage.disabled("Фит работает как обычно.\n") == nil
    end

    test "the free-feat list stops at the end of the bullets, `ё` and all" do
      page =
        SialaFeatPage.parse(
          """
          На Сиале некоторые классы автоматически получают этот фит на первом уровне:
          *[[Воин]]
          *[[Чёрный страж]]
          То есть вы можете взять уровень [[Теневой танцор|ШД]].
          """,
          @lookup
        )

      assert page.granted_automatically_to == ["fighter", "blackguard"]
    end
  end

  describe "fandom_links/1" do
    test "only links that say they point at the English wiki count" do
      page = """
      * [[Рейнджер]] на уровнях, когда выбирает [http://nwn.wikia.com/wiki/Favored_enemy любимого врага]
      == Ссылки ==
      * [https://nwn.fandom.com/wiki/Hide_in_plain_sight Hide in plain sight в англоязычной вики]
      """

      assert SialaFeatPage.fandom_links(page) == ["Hide in plain sight"]
    end
  end
end
