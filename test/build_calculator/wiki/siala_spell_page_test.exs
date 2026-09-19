defmodule BuildCalculator.Wiki.SialaSpellPageTest do
  use ExUnit.Case, async: true

  alias BuildCalculator.Wiki.SialaSpellPage

  # The label block 128 of the 129 pages open with, plus the three shapes that
  # only some of them use: a label the module does not name (`Получает усиление
  # от`), a value that runs on into a bullet list (`Существо начального уровня`,
  # every `Summon creature` page) and the description underneath.
  @spell """
  '''Уровень Заклинателя:''' Колдун / Волшебник 3

  '''Начальный Уровень:''' 3

  '''Школа:''' Разрушение (Evocation)

  '''Дескриптор(ы):''' Огонь

  '''Компонент(ы):''' Вербальные, Жестовые

  '''Расстояние до Цели:''' Большое

  '''Область Охвата / Цель:''' Огромная

  '''Продолжительность:''' Мгновенное

  '''Спасбросок:''' Рефлекс 1/2

  '''Сопротивление Заклинанию:''' Да

  '''Шаманство:''' Увеличивает ДЦ заклинания

  '''Получает усиление от:''' [[Incendiary cloud|Incendiary cloud]]

  '''Существо начального уровня:''' Древний гигант
  *Класс брони: 36
  *Бонус атаки: +47/+42

  Заклинатель выпускает горящий снаряд, нанося 1d6 единиц урона на каждый
  уровень заклинателя, до максимума 20d6.

  ===Изменение в заклинаниях===
  *кап урона 20д6
  *получает усиления от [[Incendiary cloud]]
  <blockquote>''2 категория'' кроме радиуса увеличивается кап урона до 30д6</blockquote>

  ==Ссылки==
  *[https://nwn.fandom.com/wiki/Fireball Огненный шар в англоязычной вики]
  [[Категория:Заклинания]]
  """

  describe "parse/1 — the Russian label block" do
    test "reads all ten labels the pages share, verbatim" do
      page = SialaSpellPage.parse(@spell)

      assert page.caster_level_raw == "Колдун / Волшебник 3"
      assert page.initial_level_raw == "3"
      assert page.school_raw == "Разрушение (Evocation)"
      assert page.descriptors_raw == "Огонь"
      assert page.components_raw == "Вербальные, Жестовые"
      assert page.range_raw == "Большое"
      assert page.area_raw == "Огромная"
      assert page.duration_raw == "Мгновенное"
      assert page.save_raw == "Рефлекс 1/2"
      assert page.spell_resistance_raw == "Да"
      assert page.shamanism_raw == "Увеличивает ДЦ заклинания"
      assert page.problems == []
    end

    test "keeps unnamed labels instead of dropping them" do
      page = SialaSpellPage.parse(@spell)

      assert {"получает усиление от", "[[Incendiary cloud|Incendiary cloud]]"} in page.extra_labels
    end

    # Reading the bullets as prose would drop a whole creature's stat block into
    # the description and take its +47/+42 into the numeric comparison with it.
    test "a value runs to the end of its paragraph, bullets included" do
      page = SialaSpellPage.parse(@spell)

      assert {"существо начального уровня",
              "Древний гигант\n*Класс брони: 36\n*Бонус атаки: +47/+42"} in page.extra_labels

      refute page.description_raw =~ "Древний гигант"
      refute "+47" in page.numbers
    end

    test "the description is the prose under the labels, and only that" do
      page = SialaSpellPage.parse(@spell)

      assert page.description_raw ==
               "Заклинатель выпускает горящий снаряд, нанося 1d6 единиц урона на каждый\n" <>
                 "уровень заклинателя, до максимума 20d6."

      assert page.numbers == ["1d6", "20d6"]
    end

    test "the category link does not leak into the last label" do
      page = SialaSpellPage.parse("'''Спасбросок:''' Нет\n\n[[Категория:Заклинания]]\n")

      assert page.save_raw == "Нет"
    end

    # `Evard's black tentacles` sets three of its paragraphs in bold without a
    # colon; naming a label after the first word of one would be nonsense.
    test "a bold line without a colon is not a label" do
      page =
        SialaSpellPage.parse("""
        '''Уровень Заклинателя:''' Бард 5

        '''Монстров''' тентакли бьют каждый раунд.
        """)

      assert page.extra_labels == []
      assert page.description_raw == "'''Монстров''' тентакли бьют каждый раунд."
    end

    # `Summon creature IX` writes `'''>Начальный Уровень:'''`.
    test "a stray character in front of a label name does not hide the label" do
      page = SialaSpellPage.parse("'''>Начальный Уровень:''' 9\n")

      assert page.initial_level_raw == "9"
    end

    # `Mind fog` closes two of its labels with `</c>`. The value keeps the stray
    # tag — a snapshot that quietly repairs its source stops being diffable
    # against it — and the page is reported instead.
    test "a label closed with </c> is read, kept verbatim and reported" do
      page = SialaSpellPage.parse("'''Школа:</c> Зачарование (Enchantment)\n")

      assert page.school_raw == "</c> Зачарование (Enchantment)"
      assert "label closed with </c> instead of ''': школа" in page.problems
    end

    # `Aura of Glory` opens with `== Изменения фита на Сиале ==` before saying
    # anything else, so its labels and its description are both under a heading.
    test "a label block under a heading is still the label block" do
      page =
        SialaSpellPage.parse("""
        == Изменения фита на Сиале ==

        '''Уровень Заклинателя:''' Паладин 2

        '''Спасбросок:''' Нет

        Заклинатель получает бонус харизмы +5.
        """)

      assert page.caster_level_raw == "Паладин 2"
      assert page.description_raw == "Заклинатель получает бонус харизмы +5."
    end

    test "a label the page never wrote is reported, not silently null" do
      page = SialaSpellPage.parse("'''Уровень Заклинателя:''' Колдун / Волшебник 9\n")

      assert page.duration_raw == nil
      assert "label missing: Продолжительность" in page.problems
    end
  end

  # This is the whole basis of `numeric_diff`: the two descriptions are in two
  # languages and cannot be diffed as text, but "vanilla says 10d6 and Siala says
  # 20d6" survives translation.
  describe "numbers/1" do
    test "reads the four shapes the wikis print" do
      assert SialaSpellPage.numbers("до максимума 20d6, штраф -10, шанс 15% и бонус +5") ==
               ["20d6", "15%", "+5", "-10"]
    end

    test "reads a die written with no count in front of it" do
      assert SialaSpellPage.numbers("урон d10 за каждые 10 уровней") == ["d10", "10"]
    end

    # `Fireball` writes `20d6` in its description and `20д6` in its change list.
    test "the Cyrillic д is the same die as d" do
      assert SialaSpellPage.numbers("кап урона 20д6") == ["20d6"]
      assert SialaSpellPage.numbers("6д1 + 6d11") == ["6d1", "6d11"]
    end

    test "a die does not also yield the bare die inside it" do
      assert SialaSpellPage.numbers("4d6") == ["4d6"]
    end

    test "reads a bonus written straight after a die" do
      assert SialaSpellPage.numbers("1d4+1") == ["1d4", "+1"]
    end

    # `Урон: 1-3 + 33` is a damage range, not a -3 penalty.
    test "a range is not a negative bonus" do
      assert SialaSpellPage.numbers("Урон 1-3, уровни 20-24") == ["1", "3", "20", "24"]
      assert SialaSpellPage.numbers("штраф -3") == ["-3"]
    end

    test "renders the markup away before reading — links, tags and bold" do
      assert SialaSpellPage.numbers("Creatures take 4[[d6]] [[acid damage]] and '''+2'''") ==
               ["4d6", "+2"]
    end

    # A version thread's `showtopic=21282` is not a game number.
    test "digits inside markup are not numbers" do
      wikitext =
        "[http://siala.kiev.ua/index.php?showtopic=21282 Изменения] " <>
          "{| class=\"wikitable\" style=\"width:120px\"\n|1d4\n|}"

      assert SialaSpellPage.numbers(wikitext) == ["1d4"]
    end

    # These used to be left out, on the argument that a round count and a spell
    # circle look alike once the words are gone. They do — and the shard's changes
    # are routinely written in exactly that shape: `Divine power` 1 → 3 hit points
    # per level, `Time stop` 9 → 6 seconds.
    test "a bare quantity is a number too" do
      assert SialaSpellPage.numbers("длительность 2 раунда, 9 круг") == ["2", "9"]
    end

    test "a fraction is one number, not two" do
      assert SialaSpellPage.numbers("лечит 200 единиц каждые 0,5 секунды") == ["0.5", "200"]
      assert SialaSpellPage.numbers("шанс 3,4% за уровень") == ["3.4%"]
    end

    test "deduplicated, and ordered by the numbers rather than by the string" do
      assert SialaSpellPage.numbers("10d6 4d6 4d6 20% 5% +10 +2 3 20") ==
               ["4d6", "10d6", "5%", "20%", "+2", "+10", "3", "20"]
    end

    # `[[Image:Evards_tentacles.jpg|right|thumb|160px|…]]` opens the vanilla
    # description of `Evard's black tentacles`, and 160 is a page layout, not a
    # spell.
    test "an image embed is markup, pixels and all" do
      assert SialaSpellPage.numbers(
               "[[Image:Evards_tentacles.jpg|right|thumb|160px|Evard's tentacles]] " <>
                 "10 foot long tentacles"
             ) == ["10"]
    end

    # `Storm of vengeance` on Fandom: `<del>3d6</del> ''6d6''`. Reading both is
    # comparing Siala's present against vanilla's past.
    test "struck-through patch history is vanilla's past, not its answer" do
      assert SialaSpellPage.numbers("stunned for <del>one</del> ''two'' rounds") == []
      assert SialaSpellPage.numbers("take an additional <del>3d6</del> ''6d6'' damage") == ["6d6"]
      assert SialaSpellPage.numbers("within <s>5</s> <i>6.6</i> feet") == ["6.6"]
    end

    test "an unclosed strike-out is left alone — half a span states nothing" do
      assert SialaSpellPage.numbers("урон <s>3d6 и 20 единиц") == ["3d6", "20"]
    end

    test "no text at all is no numbers" do
      assert SialaSpellPage.numbers(nil) == []
      assert SialaSpellPage.numbers("") == []
    end
  end

  # Five fields both wikis keep in a structure. Reading them is what turned
  # «спасбросок изменён» from something a human had to notice into something the
  # task prints; the point of the tests below is that a value the vocabulary does
  # not cover comes back unread rather than folded onto the nearest word.
  describe "the fields both wikis carry" do
    test "school — the English name the Siala pages print next to the Russian one" do
      assert SialaSpellPage.school("Разрушение (Evocation)") == {:ok, "evocation"}
      assert SialaSpellPage.school("[[transmutation]]") == {:ok, "transmutation"}
    end

    # `One With The Land` writes «трансмутация» with no English beside it.
    test "school — a Russian name alone still reads" do
      assert SialaSpellPage.school("трансмутация") == {:ok, "transmutation"}
    end

    # `Balagarn's iron horn` on Fandom: the school was changed by a patch and the
    # old one struck out. Both names are in the field, and only one is the answer.
    test "school — struck history is cut before the name is read" do
      assert SialaSpellPage.school("<del>[[transmutation]]</del> <ins>''[[enchantment]]''</ins>") ==
               {:ok, "enchantment"}
    end

    test "school — a value naming no school is unread, not guessed" do
      assert SialaSpellPage.school("особая") == {:error, {:unknown, "особая"}}
      assert SialaSpellPage.school(nil) == {:error, :absent}
    end

    test "save — the throws named, never the effect" do
      assert SialaSpellPage.save("[[will]] negates") == {:ok, [:will]}
      assert SialaSpellPage.save("Воля (Will)") == {:ok, [:will]}
      assert SialaSpellPage.save("[[fortitude]] and [[will]]") == {:ok, [:fortitude, :will]}
      assert SialaSpellPage.save("Рефлекс 1/2") == {:ok, [:reflex]}
    end

    # `Стойкость (Fotritude)` misspells the English; `Cтойкость (Fortitude)` opens
    # with a Latin `C`. Either half is enough on its own.
    test "save — one broken half of the value does not lose it" do
      assert SialaSpellPage.save("Стойкость (Fotritude)") == {:ok, [:fortitude]}
      assert SialaSpellPage.save("Cтойкость (Fortitude)") == {:ok, [:fortitude]}
    end

    test "save — no save is a reading; «Особый» is not" do
      assert SialaSpellPage.save("Нет") == {:ok, []}
      assert SialaSpellPage.save("none") == {:ok, []}
      assert SialaSpellPage.save("harmless") == {:ok, []}
      assert SialaSpellPage.save("Нет, Arcane defense (Divination)") == {:ok, []}
      assert SialaSpellPage.save("Особый") == {:error, {:unknown, "особый"}}
      assert SialaSpellPage.save("special") == {:error, {:unknown, "special"}}
    end

    # All four `Cure *` pages. The whole vanilla value is struck through, so
    # vanilla states nothing — which is not the same as stating "no save", and
    # calling it one manufactured four changed saving throws that never changed.
    test "save — a field that is nothing but struck history says nothing" do
      assert SialaSpellPage.save("<s>will 1/2</s>") == {:error, :struck_out}
      assert SialaSpellPage.save("<s>[[will]] negates</s> ''none''") == {:ok, []}
    end

    test "spell resistance — yes, no, and the footnote on a yes" do
      assert SialaSpellPage.spell_resistance("Да") == {:ok, true}
      assert SialaSpellPage.spell_resistance("yes*") == {:ok, true}
      assert SialaSpellPage.spell_resistance("нет") == {:ok, false}
      assert SialaSpellPage.spell_resistance("<strike>yes</strike> no") == {:ok, false}
      assert SialaSpellPage.spell_resistance("special") == {:error, {:unknown, "special"}}
    end

    test "level — a circle is read only when it is written as a number" do
      assert SialaSpellPage.level("3") == {:ok, 3}
      assert SialaSpellPage.level("<s>2</s> 3") == {:ok, 3}
      assert SialaSpellPage.level("epic") == {:error, {:unknown, "epic"}}
      assert SialaSpellPage.level("6 (''special'')") == {:error, {:unknown, "6 (special)"}}
    end

    test "circles — a class and its circle per part" do
      assert SialaSpellPage.circles("Бард 2, Священник 2, Колдун / Волшебник 2") ==
               {:ok, [bard: 2, cleric: 2, mage: 2]}

      assert SialaSpellPage.circles("[[Друид]] 2; [[Рейнджер]] 2") ==
               {:ok, [druid: 2, ranger: 2]}
    end

    # Sorcerer and wizard share one spell list on both wikis — one `magelevel` on
    # Fandom, one «Колдун / Волшебник» label on Siala — and the compound name has
    # to win over the bare one inside it.
    test "circles — «Колдун / Волшебник» is one entry, not «Колдун» and a leftover" do
      assert SialaSpellPage.circles("Колдун / Волшебник 9") == {:ok, [mage: 9]}
    end

    test "circles — an unreadable part fails the whole list" do
      assert SialaSpellPage.circles("Бард 2, Мастер оружия 3") ==
               {:error, {:unknown, "мастер оружия 3"}}

      assert SialaSpellPage.circles(nil) == {:error, :absent}
    end
  end

  describe "change_items/1" do
    test "one item per bullet, with everything underneath attached to it" do
      page = SialaSpellPage.parse(@spell)
      [section] = page.changes_raw

      assert section.title == "Изменение в заклинаниях"

      assert SialaSpellPage.change_items(section.body) == [
               "*кап урона 20д6",
               "*получает усиления от [[Incendiary cloud]]\n" <>
                 "<blockquote>''2 категория'' кроме радиуса увеличивается кап урона до 30д6</blockquote>"
             ]
    end

    test "a sub-list belongs to the bullet above it" do
      body = "*Урон 30%;\n**с малым фокусом — 35%;\n*Шаманство удваивает урон."

      assert SialaSpellPage.change_items(body) == [
               "*Урон 30%;\n**с малым фокусом — 35%;",
               "*Шаманство удваивает урон."
             ]
    end

    # `Mordenkainen's disjunction` writes the whole section as prose.
    test "a section with no bullets is one item, not none" do
      assert SialaSpellPage.change_items("\nРаботает так же, как и оригинальный спелл.\n") ==
               ["Работает так же, как и оригинальный спелл."]
    end
  end

  describe "fandom_links/1" do
    test "only links that say they point at the English wiki count" do
      wikitext = """
      *Заклинания [https://nwn.fandom.com/wiki/Shadow_shield Shadow shield] спасают цель.
      == Ссылки ==
      *[https://nwn.fandom.com/wiki/Energy_drain Energy drain в англоязычной вики]
      """

      assert SialaSpellPage.fandom_links(wikitext) == ["Energy drain"]
    end

    # `Отражение` links its counterpart both with a search query and without.
    test "a query string is not part of the page title" do
      wikitext =
        "*[https://nwn.fandom.com/wiki/Endure_elements?so=search Endure elements в англоязычной вики]"

      assert SialaSpellPage.fandom_links(wikitext) == ["Endure elements"]
    end
  end

  # `One With The Land` is the single page written as a template; its named
  # parameters carry the same fields under Russian names.
  describe "parse/1 — the template page" do
    @template """
    [[Категория:Заклинания]]
    {{Шаблон:Заклинание
    |круг=[[Друид]] 2; [[Рейнджер]] 2
    |школа=трансмутация
    |компонент=вербальный, соматический
    |диапазон=персональный
    |зона действия=заклинатель
    |продолжительность=1 час / уровень
    |спасбросок=нет
    |СР=нет
    |описание=Призывает силы природы, заклинатель получает бонусы к навыкам.
    |изменения= максимальный эффект получает только рейнджер, прибавка '''+4'''.
    |шаманство=увеличивает прибавку до '''+3'''.
    }}
    """

    test "reads the named parameters as the same fields the labels carry" do
      page = SialaSpellPage.parse(@template)

      assert page.template?
      assert page.caster_level_raw == "[[Друид]] 2; [[Рейнджер]] 2"
      assert page.school_raw == "трансмутация"
      assert page.range_raw == "персональный"
      assert page.area_raw == "заклинатель"
      assert page.spell_resistance_raw == "нет"
      assert page.shamanism_raw == "увеличивает прибавку до '''+3'''."

      assert page.description_raw ==
               "Призывает силы природы, заклинатель получает бонусы к навыкам."
    end

    test "the template has no initial level field, and says so" do
      page = SialaSpellPage.parse(@template)

      assert page.initial_level_raw == nil
      assert page.problems == ["label missing: Начальный Уровень"]
    end

    test "the changes parameter reads as a change section" do
      page = SialaSpellPage.parse(@template)

      assert page.changes_raw == [
               %{
                 title: "изменения",
                 body: "максимальный эффект получает только рейнджер, прибавка '''+4'''."
               }
             ]
    end
  end
end
