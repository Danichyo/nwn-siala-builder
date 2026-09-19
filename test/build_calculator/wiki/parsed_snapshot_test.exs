defmodule BuildCalculator.Wiki.ParsedSnapshotTest do
  @moduledoc """
  Guards what `mix wiki.parse` committed, not how it got there.

  The task is idempotent and its output is reviewed by hand, so what is worth
  pinning here is the shape of the result: the closed vocabularies, and the
  invariants that keep a partly-read requirement from reading as a fully
  understood one. A phrase that quietly stops being recognised, or a `type` value
  the feat filter has never seen, shows up here rather than in the interface.
  """

  use ExUnit.Case, async: true

  @feats "priv/rules/vanilla/feats.json" |> File.read!() |> Jason.decode!()
  @classes "priv/rules/vanilla/classes.json" |> File.read!() |> Jason.decode!()

  @siala_feats "priv/rules/siala_41/generated/feats.json"
               |> File.read!()
               |> Jason.decode!()
               |> Map.fetch!("feats")

  @siala_spells "priv/rules/siala_41/generated/spells.json"
                |> File.read!()
                |> Jason.decode!()
                |> Map.fetch!("spells")

  defp prereqs(feat), do: feat["prereqs"] || %{}

  describe "qualifiers" do
    # The whole vocabulary `BuildCalculator.Wiki.Requirements` recognises, as it
    # actually occurs. Every entry is a weapon, a school of magic or a rank
    # inside a feat family — the three things the schema has no room for.
    #
    # The list shrank by two when `same_choice_as` arrived: a qualifier means
    # "the schema cannot say this", so once the key says it the caveat is no
    # longer merely redundant, it is untrue. Both departures were about a school,
    # which is the one domain with a dictionary behind it
    # (`spell_schools.json`) — see `BuildCalculator.Wiki.FeatChoice`. The weapon
    # phrases stay exactly where they were, because nothing checks a weapon.
    test "the phrases in the file are the ones the parser claims to know" do
      phrases =
        @feats
        |> Enum.flat_map(&(prereqs(&1)["qualifiers"] || []))
        |> Enum.uniq()
        |> Enum.sort()

      assert phrases == [
               "(chosen weapon)",
               "(weapon to be chosen)",
               "+3",
               "all in the chosen weapon",
               "in the chosen spell school",
               "proficiency with the chosen weapon",
               "with the chosen weapon"
             ]
    end

    # The other half of the sentence above: a phrase may only leave `qualifiers`
    # by being expressed, never by being dropped. Whichever feat lost one has to
    # be able to show the key that replaced it and the quote it was read from.
    test "every phrase that left qualifiers was replaced by same_choice_as" do
      superseded =
        for feat <- @feats,
            prereqs(feat)["same_choice_as"],
            do: {feat["id"], prereqs(feat)["same_choice_quote"]}

      assert {"greater_spell_focus", "(selected [[spell school]])"} in superseded
      assert {"epic_spell_focus", "in the chosen [[spell school|school]]"} in superseded

      for {id, quote} <- superseded do
        assert is_binary(quote), "#{id}: same_choice_as without the phrase it came from"
      end
    end

    # ⚠ The line between "checked, with a footnote" and "not checked at all".
    # A block whose only key is `qualifiers` states no requirement, and left
    # alone it would read as fully understood — `unparsed` is what makes the core
    # refuse, and a lone qualifier does not set it.
    test "no feat is described by a qualifier alone" do
      lone =
        for feat <- @feats,
            Map.keys(prereqs(feat)) == ["qualifiers"],
            do: feat["id"]

      assert lone == []
    end

    test "a prestige class reads the same way" do
      phrases =
        @classes
        |> Enum.flat_map(&((&1["requirements"] || %{})["qualifiers"] || []))
        |> Enum.uniq()
        |> Enum.sort()

      assert phrases == ["(requires ride 1)", "in a melee weapon"]

      lone =
        for class <- @classes,
            Map.keys(class["requirements"] || %{}) == ["qualifiers"],
            do: class["id"]

      assert lone == []
    end
  end

  # ⚠ Единственная дизъюнкция, которую страница НЕ объявляет словом: список
  # классов, выдающих фит, напечатан той же запятой, что и конъюнкция. Держится
  # вывод не на пунктуации, а на том, что шаблон печатает тот же список второй
  # раз машиночитаемыми полями `classN` (выдаёт сам) и `bonusN` (можно взять
  # бонусным) — их парсер поднимает в `granted_by` и `bonus_for`. Здесь пин
  # ровно на это равенство: страница, переставшая соглашаться сама с собой,
  # должна падать тестом, а не тихо менять прочтение.
  describe "a feat's list of granting classes" do
    defp class_choice(feat) do
      branches = prereqs(feat)["any_of"] || []

      if branches != [] and Enum.all?(branches, &(Map.keys(&1) == ["class_levels"])),
        do: branches |> Enum.flat_map(&Map.keys(&1["class_levels"])) |> Enum.sort(),
        else: nil
    end

    test "the classes it names are exactly the ones the template says grant it" do
      choices = for feat <- @feats, classes = class_choice(feat), do: {feat["id"], classes}

      # Положительный контроль: сама выборка непуста, иначе цикл ниже зеленел бы
      # ни на чём. Это все 14 фитов такой формы во всём снапшоте.
      assert length(choices) == 14
      assert {"favored_enemy", ["harper_scout", "ranger"]} in choices
      assert {"evasion", ["monk", "rogue", "shadowdancer"]} in choices

      for {id, classes} <- choices do
        feat = Enum.find(@feats, &(&1["id"] == id))
        granting = Enum.sort(Enum.uniq((feat["granted_by"] || []) ++ (feat["bonus_for"] || [])))

        assert classes == granting,
               "#{id}: prereq names #{inspect(classes)}, classN ∪ bonusN says #{inspect(granting)}"
      end
    end

    # ⚠ Половина контракта, которая убирает ЛОЖНУЮ ЛЕГАЛЬНОСТЬ: ветка выбора
    # проходит одна за всю дизъюнкцию, поэтому ветка, прочитанная наполовину,
    # пустила бы билд мимо требования. Такой список остаётся прозой целиком.
    test "a list no fragment of which reads whole stays prose" do
      uncanny = Enum.find(@feats, &(&1["id"] == "uncanny_dodge"))

      assert class_choice(uncanny) == nil
      refute Map.has_key?(prereqs(uncanny), "class_levels")
      assert length(prereqs(uncanny)["unparsed"]) == 4
    end

    # Вывод про игру, а не про запятую, и верен он для классовых умений. У фитов
    # с ОДНИМ классом запятая означает «и»: Weapon Specialization требует воина
    # И BAB +4 И Weapon Focus — и это по-прежнему конъюнкция.
    test "one class beside other requirements is not turned into a choice" do
      spec = Enum.find(@feats, &(&1["id"] == "weapon_specialization"))

      assert prereqs(spec)["class_levels"] == %{"fighter" => 1}
      assert prereqs(spec)["base_attack_bonus"] == 4
      assert class_choice(spec) == nil
    end
  end

  # ⚠ «Able to use the skill» — не порог, а условие, зависящее от того, КАКОЙ
  # навык выбран вместе с фитом; в схеме такого ключа нет. Промежуточных
  # состояний тут быть не должно: разобрал — значит проверяется, не разобрал —
  # ядро честно отказывается (`{:missing_data, {:feat_prerequisites, …}}`).
  # Правдоподобное толкование («хотя бы 1 ранг») было бы выдумыванием правила:
  # страница называет тренировку условием лишь для ЧАСТИ навыков, а для
  # animal empathy и use magic device говорит о классовом ограничении.
  test "\"able to use the skill\" is left unread rather than interpreted" do
    focus = Enum.find(@feats, &(&1["id"] == "skill_focus"))

    assert prereqs(focus) == %{"unparsed" => ["able to use the skill"]}

    # Положительный контроль: файл вообще умеет читать требования, так что
    # строка выше — решение, а не общая немота разбора.
    assert prereqs(Enum.find(@feats, &(&1["id"] == "epic_skill_focus")))["any_skill_ranks"] == 20
  end

  describe "the scalars that name a derived stat" do
    test "only the three saving throws are read as one" do
      saves =
        @feats
        |> Enum.flat_map(&Map.keys(prereqs(&1)["save_bonus"] || %{}))
        |> Enum.uniq()

      assert saves == ["fortitude"]
      assert Enum.all?(saves, &(&1 in ~w(fortitude reflex will)))
    end

    test "\"ranks in the chosen skill\" never became an entry in skills" do
      any = for feat <- @feats, ranks = prereqs(feat)["any_skill_ranks"], do: {feat["id"], ranks}

      assert any == [{"epic_skill_focus", 20}]
      refute Map.has_key?(prereqs(Enum.find(@feats, &(&1["id"] == "epic_skill_focus"))), "skills")
    end
  end

  # The list of choosable feats is filtered on `type`, so a value nobody has seen
  # is a filter nobody wrote. `[[epic spell]]` used to be in here with its markup
  # on; the rest is the vocabulary Fandom itself uses and is not folded further,
  # because the wiki draws these distinctions and we do not.
  test "the feat type vocabulary carries no wiki markup" do
    types =
      @feats |> Enum.map(& &1["type"]) |> Enum.uniq() |> Enum.reject(&is_nil/1) |> Enum.sort()

    assert types == [
             "class",
             "classrace",
             "combat",
             "defensive",
             "epic spell",
             "general",
             "instant custom",
             "item creation",
             "metamagic",
             "monster",
             "race",
             "special",
             "spell"
           ]

    refute Enum.any?(types, &String.contains?(&1, "["))
  end

  # `Категория:Фиты` on the Siala wiki also holds a page about a *family*:
  # «Фокусировки на школы магии» is Spell Focus in all eight schools at once.
  # There is no feat by that name, nothing on the page can be taken, and a list
  # of choices that offers it offers an empty pair of brackets — but its prose is
  # the shard's rules on schools of magic, so the record stays.
  describe "the Siala layer" do
    test "the one page that describes no feat is marked, and only it" do
      assert for(feat <- @siala_feats, feat["describes_feat"] == false, do: feat["id"]) ==
               ["siala_spell_school_focus"]
    end

    test "every record answers the question" do
      assert Enum.all?(@siala_feats, &is_boolean(&1["describes_feat"]))
    end

    # The five Siala-only weapon proficiencies carry no bold labels either — the
    # numbered unlock list and the «Возможность взятия фита» section are what
    # tell a real feat from a page about a family.
    test "the label-less weapon proficiencies are still feats" do
      for id <- ~w(siala_blade_proficiency siala_polearm_proficiency siala_hammer_proficiency
                   siala_axe_proficiency siala_ranged_proficiency) do
        feat = Enum.find(@siala_feats, &(&1["id"] == id))

        assert feat["type_raw"] == nil, "#{id} unexpectedly grew a label"
        assert feat["describes_feat"], "#{id} was mistaken for a family page"
      end
    end

    # ⚠ The shard writes «Паладин 1 уровня, Чемпион Торма 1 уровня» with a comma,
    # and only game knowledge — a feat's list of granting classes is never a
    # conjunction — makes that a choice. The parser states the atoms and leaves
    # that reading to `BuildCalculator.Data.Loader`, so the two class levels are
    # deliberately still two atoms here.
    test "an unstated disjunction is not invented, a stated one is read" do
      assert [%{"kind" => "class_level"}, %{"kind" => "class_level"}] =
               requirement_atoms("lay_on_hands")

      assert [%{"kind" => "any_of", "branches" => [_race, _class]}] =
               requirement_atoms("keen_sense")
    end

    test "«можно взять только на 1-ом уровне» is a ceiling in the data too" do
      assert [_perform, %{"kind" => "max_character_level", "level" => 1}] =
               requirement_atoms("artist")
    end
  end

  defp requirement_atoms(id) do
    feat = Enum.find(@siala_feats, &(&1["id"] == id))
    Enum.find_value(feat["changes"], &if(&1["what"] == "requirements", do: &1["value"]))
  end

  defp siala_feat(id), do: Enum.find(@siala_feats, &(&1["id"] == id))

  # Тот же сигнал, что у заклинаний, и заведён по той же причине: величину
  # эффекта шард держит прозой в «Особенностях», а не полем, поэтому сравнить
  # можно только НАБОРЫ напечатанных чисел. До этого «Особенности» не попадали
  # в запись вообще ничем, кроме сырого текста, и переписанная величина
  # проходила молча — на пяти `Epic energy resistance` в том числе.
  describe "the Siala feat comparison" do
    test "у каждой записи есть вердикт, и он один из трёх" do
      for feat <- @siala_feats do
        assert feat["numbers_differ"] in [true, false, nil], feat["id"]
      end
    end

    # ⚠️ Долг, ради которого сигнал и заводился. Пять страниц про сопротивление
    # называют 15 за взятие при максимуме 150, Fandom — 10 и 100.
    test "пять страниц про сопротивление показывают 10/100 против 15/150" do
      ids =
        for feat <- @siala_feats,
            String.starts_with?(feat["id"], "epic_energy_resistance"),
            do: feat["id"]

      assert length(ids) == 5

      for id <- ids do
        feat = siala_feat(id)

        assert feat["numbers_differ"] == true, id
        assert feat["numeric_diff"] == %{"vanilla" => ["10", "100"], "siala" => ["15", "150"]}, id

        # Цитата обязана лежать рядом с числами: без неё «15 и 150» — это два
        # числа без утверждения, а решает по ним человек.
        assert feat["special_raw"] =~ "15"
        assert feat["special_raw"] =~ "150"
        assert feat["vanilla_id"] == "epic_energy_resistance"
      end
    end

    # ⚠️ Кириллическая `С` в заголовке `Epic energy resistance (Сold)`: id обязан
    # остаться ASCII, иначе в данных заведётся неотличимый на глаз дубль.
    test "у сопротивления холоду id из ASCII, хотя заголовок с кириллической С" do
      cold = siala_feat("epic_energy_resistance_cold")

      assert cold["ru"] == "Epic energy resistance (Сold)"
      refute String.match?(cold["ru"], ~r/^[\x00-\x7F]*$/), "заголовок вдруг стал целиком ASCII"
      assert String.match?(cold["id"], ~r/^[a-z0-9_]+$/)
    end

    test "счётчики вердиктов" do
      counts = Enum.frequencies_by(@siala_feats, & &1["numbers_differ"])

      # 33 — то, что человеку предстоит вычитать; 9 — «числа сошлись»;
      # 24 — сравнивать не с чем (нет ванильного соответствия, нет описания
      # у ванильного фита или нет лейбла «Особенности»).
      assert counts == %{true => 33, false => 9, nil => 24}
    end

    # `null` — это «не сравнивали», и оно обязано иметь причину в самой записи,
    # а не быть просто пропуском.
    test "«сравнивать не с чем» всегда объяснимо самой записью" do
      for feat <- @siala_feats, is_nil(feat["numbers_differ"]) do
        assert feat["siala_only"] or is_nil(feat["special_raw"]) or
                 is_nil(vanilla_desc(feat["vanilla_id"])),
               "#{feat["id"]}: вердикта нет, а причина не видна"
      end
    end

    test "набор чисел прикладывается только там, где они разошлись" do
      for feat <- @siala_feats do
        case feat["numbers_differ"] do
          true -> assert is_map(feat["numeric_diff"]), feat["id"]
          _otherwise -> assert is_nil(feat["numeric_diff"]), feat["id"]
        end
      end
    end

    # Сигнал не должен зеленеть на всём подряд: страницы, где числа сошлись,
    # существуют, и это доказывает, что сравнение вообще различает случаи.
    test "есть страницы, где числа сошлись, — сигнал не тотальный" do
      agree = for feat <- @siala_feats, feat["numbers_differ"] == false, do: feat["id"]

      assert "hide_in_plain_sight" in agree
      assert "divine_grace" in agree
    end
  end

  defp vanilla_desc(nil), do: nil

  defp vanilla_desc(id) do
    feat = Enum.find(@feats, &(&1["id"] == id))
    feat && feat["description"]
  end

  # `classN` в шаблоне `{{feat}}` значит «классы, которые выдают этот фит САМИ»,
  # а не «кому он доступен» — поле раньше называлось `available_to` и читалось
  # наоборот. Проверяется не имя (имя проверил бы компилятор), а сам факт,
  # из которого имя следует, — потому что при следующем `mix wiki.parse` рухнет
  # именно факт, а имя останется красивым.
  describe "granted_by — кто выдаёт фит, а не кому он доступен" do
    test "поле называется granted_by и available_to больше нет ни у кого" do
      for feat <- @feats do
        assert Map.has_key?(feat, "granted_by"), feat["id"]
        refute Map.has_key?(feat, "available_to"), feat["id"]
      end
    end

    # ⚠️ Доказательство имени, и оно одностороннее. Каждая пара (фит, класс),
    # которую класс объявляет у себя в `granted_feats`, обязана найтись
    # в `granted_by` этого фита. Обратное неверно и не проверяется — у фитов
    # исторически было 69 пар шире: 67 владений бронёй и оружием, которые
    # `proficiencies_raw` называл прозой и никто не разбирал, плюс 2 пары
    # `favored_enemy`, которые не выдача вовсе (см. следующий тест).
    #
    # AGENT_QUEUE.md §1.10 шаг 3: владения теперь читаются
    # (`Mix.Tasks.Wiki.Parse.proficiency_grants/3`, Источники 2+3), поэтому
    # 143 выросло до 210 — ровно на 67 закрытых пар, не больше и не меньше.
    test "ни одна выдача со стороны класса не потеряна на стороне фита" do
      from_feats =
        for feat <- @feats,
            class <- feat["granted_by"],
            into: MapSet.new(),
            do: {feat["id"], class}

      from_classes =
        for class <- @classes,
            {_level, ids} <- class["granted_feats"] || %{},
            id <- ids,
            into: MapSet.new(),
            do: {id, class["id"]}

      # Положительный контроль: обе стороны непусты, иначе разность пуста
      # по причине «нечего сравнивать».
      assert MapSet.size(from_feats) == 212
      assert MapSet.size(from_classes) == 210

      assert MapSet.difference(from_classes, from_feats) |> MapSet.to_list() == [],
             "класс выдаёт фит, а фит об этом не знает — значит classN значит не «выдаёт»"
    end

    # Страница, на которой прочитывается разница между «выдаёт» и «доступен»:
    # монах Cleave получает даром, а взять его может кто угодно с СИЛОЙ 13.
    test "Cleave числится за монахом, и это выдача, а не ограничение" do
      cleave = Enum.find(@feats, &(&1["id"] == "cleave"))

      assert cleave["granted_by"] == ["monk"]
      assert cleave["type"] == "general"
      assert cleave["prereq_raw"] =~ "power attack"
    end

    # ⚠️ 08.08.2026 (задача 1.10 шаг 3): было 69, стало 2 — владения переехали
    # в `granted_feats` (тест выше), и `only_on_feats` больше не «почти все —
    # владения», а «ровно `favored_enemy` × `ranger`/`harper_scout`». Поле всё
    # равно не дубликат: эти два фита — параметризованный выбор через
    # бонусный слот (`favored_enemy.bonus_for`), а не безусловная выдача,
    # переносить их в `granted_feats` было бы новой ошибкой (см. также
    # `siala_feat_layer_test.exs`, где для рейнджера то же самое проверено
    # сквозным вызовом `FeatSlots`, а не только полем).
    test "поле шире классового на 2 пары, и это не дубликат" do
      from_feats =
        for feat <- @feats,
            class <- feat["granted_by"],
            into: MapSet.new(),
            do: {feat["id"], class}

      from_classes =
        for class <- @classes,
            {_level, ids} <- class["granted_feats"] || %{},
            id <- ids,
            into: MapSet.new(),
            do: {id, class["id"]}

      only_on_feats = MapSet.difference(from_feats, from_classes)

      assert MapSet.size(only_on_feats) == 2

      assert only_on_feats ==
               MapSet.new([{"favored_enemy", "ranger"}, {"favored_enemy", "harper_scout"}])

      proficiencies =
        Enum.count(only_on_feats, fn {id, _class} ->
          String.contains?(id, "proficiency")
        end)

      assert proficiencies == 0
    end
  end

  # Зеркало `granted_feats`: что класс, наоборот, снимает с общего списка фитов
  # на своих уровнях («These general feats cannot be selected when taking a level
  # of bard»). Числа закреплены по той же причине, что и «212/210» выше: список,
  # тихо ставший короче, выглядит как класс, который перестал что-то запрещать, —
  # то есть как разрешение, которого источник не давал.
  describe "unavailable_feats — что класс не даёт выбрать на своём уровне" do
    defp unavailable_pairs do
      for class <- @classes, feat <- class["unavailable_feats"] || [], do: {class["id"], feat}
    end

    # Числа, что печатает `mix wiki.parse` («23 of 23 take feats off the
    # general list»), и что пересчитала инвентаризация 08.08.2026 двумя
    # независимыми проходами: 240 пар со страниц КЛАССОВ (Источник 1), плюс
    # 4 со страниц самих ФИТОВ (Источник 4, AGENT_QUEUE.md §1.10) —
    # `blinding_speed`×`harper_scout`, `knockdown`×`monk`,
    # `improved_knockdown`×`monk`, `improved_two_weapon_fighting`×`ranger`.
    # Ни одна из четырёх не пересекается с исходными 240 (иначе `Enum.uniq`
    # при слиянии срезал бы её и итог остался бы 240), так что оба числа
    # растут ровно на четыре.
    test "все 23 класса, 244 пары (240 со страниц классов + 4 со страниц фитов), 22 различных фита" do
      pairs = unavailable_pairs()

      assert length(@classes) == 23
      assert Enum.count(@classes, &(&1["unavailable_feats"] not in [nil, []])) == 23
      assert length(pairs) == 244
      assert pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 22
    end

    # ⚠️ Ключ обязан быть у КАЖДОГО класса и списком: отсутствие ключа читается
    # ядром как «этот класс ничего не запрещает», то есть как разрешение.
    test "у каждого класса ключ есть и он список" do
      for class <- @classes do
        assert is_list(class["unavailable_feats"]), class["id"]
      end
    end

    # Все 240 резолвятся в существующие фиты — иначе запрет молча испарится.
    # Сам `mix wiki.parse` на нерезолвящемся имени падает; это — проверка
    # снапшота, который уже лежит в репозитории.
    test "каждое имя — настоящий фит из feats.json" do
      ids = MapSet.new(@feats, & &1["id"])

      for {class, feat} <- unavailable_pairs() do
        assert MapSet.member?(ids, feat), "#{class}: #{feat} не фит"
      end
    end

    # ⚠️ Прозу-объяснение читать нельзя: она сама содержит ссылку
    # `[[general feat]]`, и наивное «взять все ссылки» дало бы 24-й «фит»
    # у каждого класса — на страницу, которая существует, поэтому ни один
    # отчёт о нерезолвящемся имени этого бы не поймал.
    test "объяснение из значения лейбла в список не попало" do
      refute Enum.any?(unavailable_pairs(), fn {_class, feat} -> feat == "general_feat" end)

      # Положительный контроль: проза действительно лежит в сыром поле рядом,
      # то есть срезать было что.
      assert Enum.all?(@classes, &(&1["unavailable_feats_raw"] =~ "[[general feat]]"))
    end

    # ⚠️ Точка решения, а не просто проверка. Запрет объявлен про ОБЩИЕ фиты,
    # а бонусный слот класса берёт из своего списка («selected from a restricted
    # list of feats, also set forth in each class' description» — fandom
    # `Bonus feat`), поэтому ядро на бонусный слот запрет НЕ распространяет.
    # Наблюдаемой разницы сегодня нет: ни один класс не запрещает фит, который
    # взял бы его же бонусный слот. Как только это перестанет быть правдой,
    # решение придётся принимать человеку — и он узнает об этом здесь.
    test "ни один класс не запрещает фит из СВОЕГО бонусного пула" do
      overlap =
        for class <- @classes,
            feat <- @feats,
            class["id"] in (feat["bonus_for"] || []),
            feat["id"] in (class["unavailable_feats"] || []),
            do: {class["id"], feat["id"]}

      assert overlap == [],
             """
             Класс запрещает на своём уровне фит, который его же бонусный слот
             принимает. Источник про такой случай молчит: запрет объявлен про
             общие фиты, бонусный пул — отдельный список. Решать человеку, а не
             дефолтом (`Rules.FeatSlots`, «The class of the level narrows the
             general pool»).
             #{inspect(overlap)}
             """
    end

    # То же с третьей стороны: класс не может одновременно выдавать фит даром
    # и запрещать его выбирать — ЕСЛИ обе стороны читаются с ОДНОЙ страницы
    # (страницы класса). Тогда расхождение было бы противоречием источника
    # самому себе.
    #
    # ⚠️ Источник 4 (AGENT_QUEUE.md §1.10) читает запрет и со СТОРОНЫ ФИТА, и
    # для РОВНО трёх пар это намеренное, а не случайное пересечение: «Since
    # monks receive this feat automatically, it cannot be selected when
    # gaining a monk level (even prior to level 6)» говорит «выдаёт» и
    # «запрещает» ОДНИМ предложением с ОДНОЙ страницы (страницы фита, не
    # класса) — источник объявляет оба факта сразу, это не два источника,
    # разошедшихся между собой. Четвёртая пара источника 4
    # (`blinding_speed`×`harper_scout`) в выдаче класса не участвует вовсе
    # (Арфист его не дарит) и потому здесь не всплывает.
    test "выдача и запрет пересекаются РОВНО там, где источник объявляет и то и другое сразу" do
      overlap =
        for class <- @classes,
            {_level, ids} <- class["granted_feats"] || %{},
            id <- ids,
            id in (class["unavailable_feats"] || []),
            do: {class["id"], id}

      assert Enum.sort(overlap) == [
               {"monk", "improved_knockdown"},
               {"monk", "knockdown"},
               {"ranger", "improved_two_weapon_fighting"}
             ]
    end

    # ⚠️ Две стороны вики сошлись независимо, и это самое сильное подтверждение
    # правила, какое есть. `curse_song` ограничен вручную по прозе Notes своей
    # страницы (`vanilla/feat_requirements.json`: бард ИЛИ Арфист), а страницы
    # КЛАССОВ говорят то же самое с другого конца — фит стоит в `unavailable`
    # у 21 класса и не стоит ровно у этих двух. Ни один из двух текстов о другом
    # не знает.
    test "запрет curse_song совпал с ручным чтением прозы его страницы" do
      allowed =
        for class <- @classes,
            "curse_song" not in (class["unavailable_feats"] || []),
            do: class["id"]

      assert Enum.sort(allowed) == ["bard", "harper_scout"]

      curse_song = Enum.find(@feats, &(&1["id"] == "curse_song"))
      assert Enum.sort(curse_song["bonus_for"]) == ["bard", "harper_scout"]
    end

    # Единственный фит, который может взять ровно один класс, — и это тот самый
    # класс, чей бонусный список его и содержит. Держит ориентацию правила:
    # список — это «нельзя», а не «можно», и перевёрнутое чтение дало бы здесь
    # 22 класса вместо одного.
    test "weapon_specialization не запрещён только воину" do
      allowed =
        for class <- @classes,
            "weapon_specialization" not in (class["unavailable_feats"] || []),
            do: class["id"]

      assert allowed == ["fighter"]
    end

    # ⚠️ Ещё три независимых схождения, и каждое — со СВОЕЙ страницы фита,
    # а не со страниц классов. Их ценность в том, что ни один из двух текстов
    # о другом не знает: страница класса перечисляет фиты, страница фита пишет
    # требование, и сходятся они на одном и том же множестве классов.
    #
    #   extra_turning  — `prereqs.unparsed`: «exclusive to [[cleric]]s»,
    #                    «[[paladin]]s»  → ровно эти два и не запрещают;
    #   extra_music    — требует `bard_song`, который есть только у барда;
    #   divine_might   — требует `turn_undead`, а его выдают ровно три класса.
    test "разрешающие классы совпали с требованием со страницы самого фита" do
      allowed = fn id ->
        for class <- @classes, id not in (class["unavailable_feats"] || []), do: class["id"]
      end

      assert Enum.sort(allowed.("extra_turning")) == ["cleric", "paladin"]
      assert Enum.sort(allowed.("extra_music")) == ["bard"]
      assert Enum.sort(allowed.("lingering_song")) == ["bard"]

      grants_turn_undead =
        for class <- @classes,
            {_level, ids} <- class["granted_feats"] || %{},
            "turn_undead" in ids,
            uniq: true,
            do: class["id"]

      assert Enum.sort(allowed.("divine_might")) == Enum.sort(grants_turn_undead)
      assert Enum.sort(allowed.("divine_shield")) == Enum.sort(grants_turn_undead)
    end
  end

  # AGENT_QUEUE.md §1.6: `type=general` normally means "any class may take
  # it", but a page in this category says the game's own class feat lists
  # leave somebody out anyway — and, unlike `bonus_for`/`granted_by`, without
  # naming who. The category is a signal for a human to read the page
  # (`vanilla/feat_requirements.json`), not a rule the parser applies itself —
  # nothing here reads a class name out of it.
  describe "restricted_by_class_category — the signal, not the rule" do
    # Every record answers the question, the same contract `describes_feat`
    # gets on the Siala side: a boolean that is merely absent reads as
    # "unknown" to a human skimming the file, which this is not.
    test "every feat answers, with a boolean" do
      assert Enum.all?(@feats, &is_boolean(&1["restricted_by_class_category"]))
    end

    # ⚠ The signal is not total — a feat carrying no such category must read
    # `false`, or a comparison bug here would make every feat look flagged.
    test "curse_song and toughness land on opposite sides" do
      curse_song = Enum.find(@feats, &(&1["id"] == "curse_song"))
      toughness = Enum.find(@feats, &(&1["id"] == "toughness"))

      assert curse_song["restricted_by_class_category"] == true
      assert toughness["restricted_by_class_category"] == false
    end

    # The six pages AGENT_QUEUE.md §1.6 named by hand (four with `prereqs:
    # null`, two with `prereqs` reading only `unparsed`) all carry it —
    # otherwise the ticket's own premise would not have held.
    test "the six feats the ticket named all carry it" do
      for id <- ~w(curse_song two_weapon_fighting weapon_proficiency_martial
                   weapon_proficiency_simple improved_sneak_attack skill_focus) do
        feat = Enum.find(@feats, &(&1["id"] == id))
        assert feat["restricted_by_class_category"], id
      end
    end

    # Pinned so a re-fetch that gains or drops a page from either Fandom
    # category (`Category:Feats restricted by class` and its disjoint
    # epic-only twin) is seen here rather than folded into the next parse —
    # `[feats] N pages carry Category:Feats restricted by class …` at the
    # bottom of a `mix wiki.parse` run states the same three numbers.
    test "48 pages carry it, 42 of which already read a restriction some other way" do
      flagged = Enum.filter(@feats, & &1["restricted_by_class_category"])
      assert length(flagged) == 48

      already_read =
        Enum.count(flagged, fn feat ->
          prereqs = prereqs(feat)
          prereqs != %{} and Map.keys(prereqs) != ["unparsed"]
        end)

      assert already_read == 42
    end
  end

  # The signal that says "a human must read this page". It answers two different
  # questions — do the numbers in the two descriptions disagree, and do the fields
  # both wikis keep in a structure disagree — and the counts below are what a hand
  # review of all 129 pages found, field by field. They are pinned because a
  # comparison that quietly stops finding anything looks exactly like a wiki that
  # quietly stopped disagreeing.
  describe "the Siala spell comparison" do
    test "every matched page gets a verdict, and only the unmatched one goes without" do
      unanswered = for s <- @siala_spells, is_nil(s["differs_from_vanilla"]), do: s["id"]

      assert unanswered == ["stream_of_flame"]
      assert Enum.find(@siala_spells, &(&1["id"] == "stream_of_flame"))["siala_only"]
    end

    test "the fields compared, and the verdicts they come back with" do
      assert @siala_spells
             |> Enum.flat_map(&Map.keys(&1["field_diff"] || %{}))
             |> Enum.uniq()
             |> Enum.sort() ==
               ~w(circles duration initial_level save school spell_resistance)

      assert @siala_spells
             |> Enum.flat_map(&Map.values(&1["field_diff"] || %{}))
             |> Enum.map(& &1["verdict"])
             |> Enum.uniq()
             |> Enum.sort() == ~w(differs unreadable)
    end

    test "the hand review's counts, field by field" do
      assert field_counts("differs") == %{
               "school" => 8,
               "save" => 15,
               "spell_resistance" => 16,
               "circles" => 5,
               "initial_level" => 1,
               "duration" => 45
             }

      assert field_counts("unreadable") == %{
               "save" => 12,
               "spell_resistance" => 3,
               "initial_level" => 2,
               "duration" => 38
             }
    end

    # Before the fields were read at all, 75 pages carried a signal. The review
    # found 125 of the 128 matched pages changed; what is left unflagged is the
    # blind zone no parser reaches — a mechanic replaced in words, with no number
    # and no field to show for it.
    test "115 pages carry a signal, and the three the review cleared carry none" do
      assert Enum.count(@siala_spells, &(&1["differs_from_vanilla"] == true)) == 115

      quiet = for s <- @siala_spells, s["differs_from_vanilla"] == false, do: s["id"]

      assert "hold_monster" in quiet
      assert "silence_spell" in quiet
      assert "slow_spell" in quiet
      assert length(quiet) == 13
    end

    # ⚠ The trap this comparison was born with. Fandom strikes an old value out
    # instead of deleting it, and all four `Cure *` pages carry nothing but a
    # struck saving throw. Read literally that is «Will ½ → нет» on four spells
    # that never changed; read honestly it is vanilla saying nothing.
    test "a vanilla field that is only struck history is unread, not a difference" do
      for id <- ~w(cure_light_wounds cure_moderate_wounds cure_serious_wounds
                   cure_critical_wounds) do
        save = Enum.find(@siala_spells, &(&1["id"] == id))["field_diff"]["save"]

        assert save["verdict"] == "unreadable"
        assert save["reason"] =~ "зачёркнутая история патчей"
        assert save["vanilla"] =~ "<s>"
      end
    end

    test "nothing that agreed is written out, so an absent field name means agreement" do
      assert for(s <- @siala_spells, s["field_diff"] == %{}, do: s["id"]) == []
    end
  end

  defp field_counts(verdict) do
    for spell <- @siala_spells,
        {field, entry} <- spell["field_diff"] || %{},
        entry["verdict"] == verdict,
        reduce: %{} do
      counts -> Map.update(counts, field, 1, &(&1 + 1))
    end
  end
end
