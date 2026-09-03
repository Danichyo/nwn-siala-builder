defmodule BuildCalculator.Rules.ClassGroupsTest do
  @moduledoc """
  Группы классов Сиалы — «Воины Сагры» и «Воины Адры» (запрос Dan 08.08.2026).

  ## Источники, дословно

  | группа | классы | правило чистоты | что даёт | страница |
  |---|---|---|---|---|
  | Воины Сагры | Fighter, Barbarian, Weapon Master, Dwarven Defender | **есть**, `verified` | зелья Сагры / Азарака, точило, множитель от оружия | `Воины Сагры`, revid 19232 |
  | Воины Адры | Fighter, Monk, Paladin, Champion of Torm | **не описано нигде** | зелья Адры — **слово владельца**, не вики (Dan, 25.08.2026) | своей страницы нет; `Воин` 16725, `Монах` 17402, `Паладин` 19703, `Чемпион Торма` 16728 |

  Правило чистоты Сагры: «Чистые классы воинов Сагры (также комбинации эти
  классов) получают покровительство бога; **любой другой класс в билде нивелирует
  преимущества**» (`Воины Сагры`, revid 19232, `verified`).

  ⚠️ **У двух групп РАЗНОЕ качество данных, и тесты обязаны это различать.** У
  Адры нет своей страницы: список классов собран по обратным ссылкам с четырёх
  страниц классов, а правило чистоты не сформулировал никто. Мы применяем правило
  Сагры и **держим это допущением** — отсюда `purity_stated?`.

  🔴 **Задача 3.100 (25.08.2026): ни одной из трёх оговорок про группы больше
  нет ни на одном билде** — ни `{:assumed, {:class_group_purity, :adra_warriors}}`,
  ни `{:missing_data, {:class_group_benefits, :adra_warriors}}`, ни
  `{:not_modelled, {:class_group_benefits, :sagra_warriors}}`. Решение Dan:
  «для нашего конструктора и итоговых значений принадлежность билда к Адре или
  нет ничего не меняет. Эта принадлежность позволяет пить зелья адры, которые мы
  не моделируем, считай баффы».

  ⚠️ **Снято ПРИЗНАНИЕ, а не механизм**, и тесты обязаны проверять разное: живые
  данные — что сегодня молчат; **синтетический** ruleset — что механизм жив и
  вернёт оговорку сам. Контроль на живой записи назавтра получает правку данных
  и молча перестаёт что-либо проверять (уроки задач 3.93 и 3.95), поэтому
  describe «механизм трёх молчаний» не читает `priv/rules` вовсе.

  ⚠️ **Само допущение при этом на месте:** `purity_required` у Адры по-прежнему
  `nil`, `purity_stated?` по-прежнему `false`, флажок по-прежнему помечен
  допущением. Записать `purity_required: true` было бы превращением допущения
  в прочитанный факт.

  ⚠️ **Fighter входит в ОБЕ группы** («Воин не изменился в своей основе, но входит
  в группу классов воинов Сагры и воинов Адры», `Воин`, revid 16725) — значит
  чистый воин одновременно сагровик и адровец. Это не краевой случай, а самый
  частый реальный билд.

  ## Независимое подтверждение обеих групп страницами билдов

  Страницы билдов — фикстуры, а не источник правил (CLAUDE.md §3), но здесь они
  подтверждают ровно то, что мы вычисляем, и с двух сторон:
  «Мастер оружия Сагровик» (revid 17916) — варвар 2 / воин 10 / мастер оружия 28,
  автор сам назвал билд сагровиком; «Паладин Адры» (revid 19670) — паладин 38 /
  монах 1 / чемпион Торма 1, и назван Адрой. У обоих состав ровно из классов своей
  группы. Оба стоят фикстурами в `test/build_calculator/reference/wiki_builds_test.exs`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, ClassGroups, GapReceivers}

  @flat %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  describe "какие группы вообще есть" do
    test "две группы, обе из данных, с именами своих страниц", %{ruleset: ruleset} do
      assert Enum.map(ClassGroups.all(ruleset), & &1.id) == [:adra_warriors, :sagra_warriors]
      assert Enum.map(ClassGroups.all(ruleset), & &1.name) == ["Воины Адры", "Воины Сагры"]
    end

    test "состав групп — ровно тот, что на вики", %{ruleset: ruleset} do
      by_id = Map.new(ClassGroups.all(ruleset), &{&1.id, &1})

      assert Enum.sort(MapSet.to_list(by_id[:sagra_warriors].classes)) ==
               [:barbarian, :dwarven_defender, :fighter, :weapon_master]

      assert Enum.sort(MapSet.to_list(by_id[:adra_warriors].classes)) ==
               [:champion_of_torm, :fighter, :monk, :paladin]

      # ⚠️ Ровно один класс в обеих группах, и это не совпадение, а строка
      # страницы «Воин»: «входит в группу классов воинов Сагры и воинов Адры».
      assert MapSet.intersection(by_id[:sagra_warriors].classes, by_id[:adra_warriors].classes) ==
               MapSet.new([:fighter])
    end

    # ⚠️ Главное различие данных, зафиксированное числом, а не словом в
    # комментарии: у Сагры правило чистоты прочитано, у Адры его нет вовсе.
    test "правило чистоты прочитано у Сагры и не прочитано у Адры", %{ruleset: ruleset} do
      by_id = Map.new(ClassGroups.all(ruleset), &{&1.id, &1})

      assert by_id[:sagra_warriors].purity_required == true
      assert by_id[:adra_warriors].purity_required == nil

      # и то же про выгоды: перечислены у одной, неизвестны у другой
      assert by_id[:sagra_warriors].benefits == [
               "зелья Сагры",
               "зелья Азарака",
               "точило",
               "усиленный бонус от оружия"
             ]

      # ⚠️ У Адры список появился 25.08.2026, и он пришёл НЕ с вики: страницы
      # у группы по-прежнему нет, ответ дал владелец. Строка ровно одна —
      # дописывать в неё точило и множитель «по аналогии с Сагрой» запрещено.
      assert by_id[:adra_warriors].benefits == ["зелья Адры"]

      # 🔴 И третье различие, заведённое задачей 3.35: какие из перечисленных
      # выгод калькулятор УЖЕ считает. У Сагры это ровно одна строка — «усиленный
      # бонус от оружия» (`Rules.WeaponTypeBonus`), — и оговорка обязана
      # перестать называть её среди непосчитанного. У Адры не посчитано ничего:
      # зелья — расходники.
      assert by_id[:sagra_warriors].benefits_counted == ["усиленный бонус от оружия"]
      assert by_id[:adra_warriors].benefits_counted == []
    end

    # 🔴 Четвёртое различие, заведённое задачей 3.100: получатель у каждой
    # выгоды — что именно она меняет. Читается тем же закрытым словарём, каким
    # судятся факты классов (`Rules.GapReceivers`), и именно он делает оговорку
    # про непосчитанное необязательной: вопроса про зелья и точило калькулятор
    # не задаёт вовсе.
    test "у каждой выгоды назван получатель, и ни один из них не наш", %{ruleset: ruleset} do
      by_id = Map.new(ClassGroups.all(ruleset), &{&1.id, &1})
      our = GapReceivers.our(ruleset)

      assert by_id[:sagra_warriors].benefit_receivers == %{
               "зелья Сагры" => ["custom_items", "buff"],
               "зелья Азарака" => ["custom_items", "buff"],
               "точило" => ["custom_items"],
               "усиленный бонус от оружия" => ["attack_bonus", "ac", "skill_values"]
             }

      assert by_id[:adra_warriors].benefit_receivers == %{
               "зелья Адры" => ["custom_items", "buff"]
             }

      # ⚠️ Непосчитанное — не наше; посчитанное — наше. Вторая половина не
      # украшение: строка, которую калькулятор считает, обязана называть
      # получателя, который он печатает, иначе разметка спорит с расчётом.
      for group <- [:sagra_warriors, :adra_warriors],
          benefit <-
            Map.fetch!(by_id, group).benefits -- Map.fetch!(by_id, group).benefits_counted do
        refute GapReceivers.record_ours?(
                 %{affects: by_id[group].benefit_receivers[benefit]},
                 our
               ),
               "#{benefit}: получатель наш, значит оговорка обязана остаться"
      end

      assert GapReceivers.record_ours?(
               %{affects: by_id[:sagra_warriors].benefit_receivers["усиленный бонус от оружия"]},
               our
             )
    end

    # ⚠️ Решение владельца лежит у Адры и не лежит у Сагры, и это не симметрия:
    # у Сагры правило чистоты ПРОЧИТАНО, поэтому решать нечего. Оба поля читает
    # `purity_gaps/2`, и подменить одно другим нельзя — `purity_required`
    # у Адры обязан остаться `nil`.
    test "решение владельца про чистоту есть у Адры и не нужно Сагре", %{ruleset: ruleset} do
      by_id = Map.new(ClassGroups.all(ruleset), &{&1.id, &1})

      assert %{"who" => "Dan"} = by_id[:adra_warriors].purity_not_a_gap
      assert by_id[:adra_warriors].purity_not_a_gap["quote"] =~ "ничего не меняет"
      assert by_id[:adra_warriors].purity_required == nil

      assert by_id[:sagra_warriors].purity_not_a_gap == nil
      assert by_id[:sagra_warriors].purity_required == true
    end

    # Пара к предыдущему, со стороны билда: членство отдаёт УЖЕ ВЫЧТЕННЫЙ список,
    # чтобы подпись не считала разность сама.
    #
    # 🔴 ⚠️ Здесь стояло «Оговорка при этом НЕ исчезает — три расходника из
    # четырёх строк остаются непосчитанными» — **пересмотрено задачей 3.100**:
    # оговорка исчезла, а список непосчитанного не сдвинулся ни на строку. Это
    # два разных утверждения, и различать их тут обязательно: «не посчитано» —
    # правда про зелья и точило, а «дырка в нашем ответе» — нет, потому что
    # вопроса про расходники калькулятор не задаёт вовсе (CLAUDE.md §9).
    test "членство отдаёт непосчитанные выгоды отдельно", %{ruleset: ruleset} do
      [sagra] =
        for membership <- ClassGroups.of(build(List.duplicate(:fighter, 41)), ruleset),
            membership.id == :sagra_warriors,
            do: membership

      assert sagra.benefits_counted == ["усиленный бонус от оружия"]
      assert sagra.benefits_uncounted == ["зелья Сагры", "зелья Азарака", "точило"]

      # ⚠️ Список непосчитанного отдаётся НЕОТФИЛЬТРОВАННЫМ — подпись отвечает
      # на «что не посчитано», а не на «где дырка», и фильтровать его по
      # получателю значило бы дать одному полю два смысла.
      refute {:not_modelled, {:class_group_benefits, :sagra_warriors}} in ClassGroups.gaps(
               build(List.duplicate(:fighter, 41)),
               ruleset
             )
    end

    # ⚠️ Групп у ванили нет вовсе — это система шарда. Проверяется и то, что
    # ядро на этом не падает: `member?/3` про несуществующую группу отвечает
    # «нет», а не бросает.
    test "у vanilla групп нет и ничего не падает", %{vanilla: vanilla} do
      build = build(List.duplicate(:fighter, 41))

      assert ClassGroups.all(vanilla) == []
      assert ClassGroups.of(build, vanilla) == []
      refute ClassGroups.member?(build, vanilla, :sagra_warriors)
      assert Rules.compute(build, vanilla).class_groups == []
      assert ClassGroups.gaps(build, vanilla) == []
    end
  end

  describe "принадлежность билда" do
    # Таблица кейсов. Каждая строка — «лестница → группы», и три из них проверяют
    # ровно правило чистоты: один чужой уровень отменяет группу целиком.
    #
    # ⚠️ Порча, от которой падает эта таблица:
    #   * убрать проверку чистоты → «воин 40 / бард 1» и «монах 20 / бард 21»
    #     получат флажки;
    #   * перепутать списки групп → варвар с мастером оружия станет адровцем,
    #     а монах с паладином сагровиком;
    #   * вернуть `true` всегда → упадут все пять отрицательных строк;
    #   * считать «хотя бы один уровень из группы» → упадут «воин 40 / бард 1»
    #     и «вор 20 / воин 21».
    @table [
      {"чистый воин 41", [{:fighter, 41}], [:adra_warriors, :sagra_warriors]},
      {"воин 1", [{:fighter, 1}], [:adra_warriors, :sagra_warriors]},
      {"воин 40 / бард 1", [{:fighter, 40}, {:bard, 1}], []},
      {"варвар 20 / мастер оружия 21", [{:barbarian, 20}, {:weapon_master, 21}],
       [:sagra_warriors]},
      {"монах 20 / паладин 21", [{:monk, 20}, {:paladin, 21}], [:adra_warriors]},
      {"монах 20 / бард 21", [{:monk, 20}, {:bard, 21}], []},
      {"вор 20 / воин 21", [{:rogue, 20}, {:fighter, 21}], []},
      {"чистый вор 41", [{:rogue, 41}], []},
      # Четыре класса, все из Сагры: лимит классов Сиалы — 4, и группа его
      # переживает. ⚠️ Единственная лестница в таблице, которую нельзя набрать
      # чистым классом, — а «комбинации эти классов» страница разрешает прямо.
      {"воин 11 / варвар 10 / ВМ 10 / ДД 10",
       [{:fighter, 11}, {:barbarian, 10}, {:weapon_master, 10}, {:dwarven_defender, 10}],
       [:sagra_warriors]},
      # И тот же четырёхклассовый билд, у которого один класс не из группы.
      {"воин 11 / варвар 10 / ВМ 10 / вор 10",
       [{:fighter, 11}, {:barbarian, 10}, {:weapon_master, 10}, {:rogue, 10}], []},
      {"пустой билд", [], []}
    ]

    test "таблица кейсов", %{ruleset: ruleset} do
      for {label, spec, expected} <- @table do
        build = ladder(spec)

        assert Enum.map(ClassGroups.of(build, ruleset), & &1.id) == expected, label

        # то же самое через `member?/3` — публичный вход, которым пользуется
        # `Rules.RacialBonus`, и он обязан отвечать так же
        for id <- [:sagra_warriors, :adra_warriors] do
          assert ClassGroups.member?(build, ruleset, id) == id in expected,
                 "#{label}: member?(#{id})"
        end

        # и результат доезжает до билда, а не живёт только в модуле
        assert Enum.map(Rules.compute(build, ruleset).class_groups, & &1.id) == expected, label
      end
    end

    # ⚠️ Дословная цитата источника, вынесенная в отдельный тест: это главное
    # правило группы, и на нём же держится расовый бонус. Один уровень барда на
    # сороковом воине — и билд перестаёт быть сагровиком.
    test "один чужой уровень отменяет обе группы", %{ruleset: ruleset} do
      pure = build(List.duplicate(:fighter, 40))
      spoiled = build(List.duplicate(:fighter, 40) ++ [:bard])

      assert Enum.map(ClassGroups.of(pure, ruleset), & &1.name) == ["Воины Адры", "Воины Сагры"]
      assert ClassGroups.of(spoiled, ruleset) == []
    end

    test "пустая лестница не член ни одной группы", %{ruleset: ruleset} do
      empty = Build.new(race: :half_elf, base_abilities: @flat)

      assert ClassGroups.of(empty, ruleset) == []

      # ⚠️ И ни одного гэпа: оговорка про группу, к которой билд не относится, —
      # шум, а пустой билд не относится ни к одной.
      assert ClassGroups.gaps(empty, ruleset) == []
      assert Rules.compute(empty, ruleset).class_groups == []
    end
  end

  describe "честность про Адру" do
    # ⚠️ Правило чистоты у Адры не описано НИКЕМ, и мы применили правило Сагры.
    # Это допущение, и оно обязано быть названо — иначе два разных по качеству
    # факта («сагровик» прочитан дословно, «адровец» выведен по аналогии)
    # выглядят на экране одинаково.
    test "флажок Адры несёт допущение, флажок Сагры — нет", %{ruleset: ruleset} do
      groups = Map.new(ClassGroups.of(build(List.duplicate(:fighter, 41)), ruleset), &{&1.id, &1})

      assert groups[:sagra_warriors].purity_stated?
      refute groups[:adra_warriors].purity_stated?

      # оба при этом ПРИМЕНЯЮТ чистоту — иначе таблица выше не сошлась бы
      assert groups[:sagra_warriors].purity_required?
      assert groups[:adra_warriors].purity_required?
    end

    # 🔴 Здесь стояло «гэпы называют обе неизвестности Адры и ни одной лишней» —
    # **пересмотрено задачей 3.100**: ни одной оговорки про группы у билда
    # больше нет, ни у Адры, ни у Сагры. Тест переписан в ту же сторону, в
    # какую поменялся ответ: он по-прежнему перечисляет все три формы поимённо,
    # только с другим знаком, — иначе снятие признания не отличить от того, что
    # его просто перестали проверять.
    test "сегодня ни одна из трёх оговорок не приезжает в билд", %{ruleset: ruleset} do
      adra = Rules.compute(ladder([{:monk, 20}, {:paladin, 21}]), ruleset)
      sagra = Rules.compute(ladder([{:barbarian, 20}, {:weapon_master, 21}]), ruleset)
      both = Rules.compute(ladder([{:fighter, 41}]), ruleset)

      for stats <- [adra, sagra, both], do: assert(group_gaps(stats) == [])

      # ⚠️ И флажки при этом на месте — снято признание, а не расчёт. Без этой
      # половины тест зеленел бы и у кода, который перестал считать членство.
      assert Enum.map(adra.class_groups, & &1.id) == [:adra_warriors]
      assert Enum.map(sagra.class_groups, & &1.id) == [:sagra_warriors]
      assert Enum.map(both.class_groups, & &1.id) == [:adra_warriors, :sagra_warriors]
    end

    # Оговорки — только про группы, к которым билд относится. Иначе они висели бы
    # почти на каждом боевом билде (у Fighter и Monk уровень есть у половины
    # лестниц) и приучили бы пролистывать список.
    test "у не-члена группы оговорок про неё нет", %{ruleset: ruleset} do
      stats = Rules.compute(ladder([{:monk, 20}, {:bard, 21}]), ruleset)

      assert group_gaps(stats) == []
    end
  end

  # 🔴 ГЛАВНЫЙ КОНТРОЛЬ ЗАДАЧИ 3.100, и он СИНТЕТИЧЕСКИЙ — ни одной строки
  # из `priv/rules`. Живых носителей у трёх форм после этой задачи не осталось,
  # а контроль на живой записи назавтра получает правку данных и молча
  # перестаёт что-либо проверять: за неделю так сгорело пять подряд (уроки
  # задач 3.93 и 3.95). Здесь ruleset — обычная мапа, и «группа без метки»
  # не может стать «группой с меткой» из-за чужого коммита.
  #
  # Проверяется ровно то, что задача снимала: **признание снято пометкой,
  # а не вычёркиванием** — то есть каждая из трёх оговорок возвращается сама,
  # как только пометки не окажется.
  describe "механизм трёх молчаний" do
    # `our` — свой, маленький и закрытый: важно не то, какие получатели есть
    # у Сиалы сегодня, а то, что правило спрашивает словарь, а не имена.
    @our MapSet.new(["hp"])
    @not_our MapSet.new(["buff"])

    @decision %{"who" => "Dan", "why" => "потому что", "quote" => "дословно"}

    @table [
      {"выгоды нет вовсе — «никто не написал»", nil, %{}, [],
       [{:missing_data, {:class_group_benefits, :test_group}}]},
      {"список пуст — то же самое", [], %{}, [],
       [{:missing_data, {:class_group_benefits, :test_group}}]},
      {"выгода без метки остаётся гэпом", ["зелье"], %{}, [],
       [{:not_modelled, {:class_group_benefits, :test_group}}]},
      {"метка не наша — молчим", ["зелье"], %{"зелье" => ["buff"]}, [], []},
      {"хватает одного нашего получателя", ["зелье", "камень"],
       %{"зелье" => ["buff"], "камень" => ["buff", "hp"]}, [],
       [{:not_modelled, {:class_group_benefits, :test_group}}]},
      {"метка есть, но не у той строки", ["зелье", "камень"], %{"зелье" => ["buff"]}, [],
       [{:not_modelled, {:class_group_benefits, :test_group}}]},
      {"посчитанное до получателя не доходит", ["зелье"], %{"зелье" => ["hp"]}, ["зелье"], []}
    ]

    test "выгоды: таблица кейсов" do
      for {label, benefits, receivers, counted, expected} <- @table do
        ruleset = ruleset(benefits: benefits, benefit_receivers: receivers, counted: counted)

        assert ClassGroups.gaps(build([:fighter]), ruleset) == expected, label
      end
    end

    # ⚠️ Словаря нет — фильтра нет вовсе: ruleset без `gap_receivers`
    # (vanilla, синтетика) обязан пере-, а не недо-сообщать.
    test "без словаря получателей молчания не бывает" do
      ruleset =
        Map.delete(
          ruleset(benefits: ["зелье"], benefit_receivers: %{"зелье" => ["buff"]}),
          :gap_receivers
        )

      assert ClassGroups.gaps(build([:fighter]), ruleset) ==
               [{:not_modelled, {:class_group_benefits, :test_group}}]
    end

    test "чистота: решение владельца молчит, его отсутствие — нет" do
      undecided = ruleset(purity_required: nil)
      decided = ruleset(purity_required: nil, purity_not_a_gap: @decision)
      stated = ruleset(purity_required: true)

      assert {:assumed, {:class_group_purity, :test_group}} in ClassGroups.gaps(
               build([:fighter]),
               undecided
             )

      refute {:assumed, {:class_group_purity, :test_group}} in ClassGroups.gaps(
               build([:fighter]),
               decided
             )

      refute {:assumed, {:class_group_purity, :test_group}} in ClassGroups.gaps(
               build([:fighter]),
               stated
             )

      # ⚠️ И решение НЕ делает вид, что правило прочитано: допущение остаётся
      # допущением, флажок остаётся помеченным. Без этой половины «снять
      # признание» было бы неотличимо от «дописать факт».
      [membership] = ClassGroups.of(build([:fighter]), decided)

      refute membership.purity_stated?
      assert membership.purity_required?
    end

    # Оговорки — только про группы, к которым билд ОТНОСИТСЯ, и это тоже часть
    # механизма: группа с самой пустой разметкой молчит про чужой билд.
    test "не-член группы не получает её оговорок" do
      ruleset = ruleset(benefits: nil, purity_required: nil)

      assert ClassGroups.gaps(build([:wizard]), ruleset) == []
    end

    defp ruleset(opts) do
      %{
        class_groups: [
          %{
            id: :test_group,
            name: "Группа для теста",
            classes: MapSet.new([:fighter]),
            purity_required: Keyword.get(opts, :purity_required, true),
            benefits: Keyword.get(opts, :benefits, nil),
            benefits_counted: Keyword.get(opts, :counted, []),
            benefit_receivers: Keyword.get(opts, :benefit_receivers, %{}),
            purity_not_a_gap: Keyword.get(opts, :purity_not_a_gap),
            known_from: :group_page
          }
        ],
        gap_receivers: %{our: @our, not_our: @not_our}
      }
    end
  end

  describe "загрузчик роняет сборку, когда три копии списка расходятся" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      root = Path.join(dir, "rules")
      File.cp_r!("priv/rules", root)

      %{
        root: root,
        systems: Path.join([root, "siala_41", "systems.json"]),
        races: Path.join([root, "siala_41", "races.json"]),
        classes: Path.join([root, "siala_41", "classes.json"])
      }
    end

    # ⚠️ Положительный контроль ко всем падениям ниже: нетронутая копия обязана
    # грузиться и давать те же две группы. Без него `assert_raise` зеленел бы и
    # на копии, которая не грузится вовсе.
    test "нетронутая копия грузится и даёт те же группы", %{root: root} do
      ruleset = Loader.load!(root)["siala_41"]

      assert Enum.map(ruleset.class_groups, & &1.name) == ["Воины Адры", "Воины Сагры"]
    end

    # Список Сагры лежит в трёх файлах. Первая пара: `systems.json` против
    # страниц классов.
    test "systems.json разошёлся со страницами классов", %{root: root, systems: path} do
      patch_fact(path, "sagra_warriors", "classes", fn classes -> classes -- ["barbarian"] end)

      assert_raise RuntimeError, ~r/Воины Сагры.*disagree/s, fn -> Loader.load!(root) end
    end

    # Вторая пара: `races.json` (у расового бонуса есть число «для сагровика»,
    # поэтому файл повторяет список) против группы.
    test "races.json разошёлся с группой по составу", %{root: root, races: path} do
      rewrite!(path, &put_in(&1, ["sagra_warrior", "classes"], ["fighter", "monk"]))

      assert_raise RuntimeError, ~r/races.json's sagra_warrior/s, fn -> Loader.load!(root) end
    end

    test "races.json разошёлся с группой по правилу чистоты", %{root: root, races: path} do
      rewrite!(path, &put_in(&1, ["sagra_warrior", "purity_required"], false))

      assert_raise RuntimeError, ~r/purity rule of Воины Сагры/s, fn -> Loader.load!(root) end
    end

    # И третья ошибка, другого рода: условие расового бонуса ссылается на
    # страницу, которую ни один класс не называет своей группой. Такое условие
    # молча никогда не выполнилось бы — то есть сагровик снова получал бы
    # базовый вариант и никто бы не заметил.
    test "условие ссылается на группу, которой нет", %{root: root, races: path} do
      rewrite!(path, &put_in(&1, ["sagra_warrior", "source", "page"], "Воины Минтры"))

      assert_raise RuntimeError, ~r/Воины Минтры/s, fn -> Loader.load!(root) end
    end

    # ⚠️ Обратный случай — не падение, а деградация в честную сторону: без записи
    # в `systems.json` группа остаётся группой (страницы классов её называют), а
    # третья копия отдаёт то, что ещё знает про неё: правило чистоты в
    # `races.json` есть, а списка выгод нет ни там, ни здесь — значит остаётся
    # ровно один гэп, про выгоды. Роняй мы сборку и здесь, неполные данные
    # ломали бы приложение целиком.
    test "группа без записи в systems.json собирается из двух других копий", %{
      root: root,
      systems: path
    } do
      rewrite!(path, fn file ->
        update_in(file["systems"], fn systems ->
          Enum.reject(systems, &(&1["id"] == "sagra_warriors"))
        end)
      end)

      ruleset = Loader.load!(root)["siala_41"]
      group = Enum.find(ruleset.class_groups, &(&1.name == "Воины Сагры"))

      # состав — со страниц классов, чистота — из races.json, выгод не знает никто
      assert Enum.sort(MapSet.to_list(group.classes)) ==
               [:barbarian, :dwarven_defender, :fighter, :weapon_master]

      assert group.purity_required == true
      assert group.benefits == nil
      assert group.known_from == :class_pages

      stats = Rules.compute(ladder([{:barbarian, 20}, {:weapon_master, 21}]), ruleset)

      refute {:assumed, {:class_group_purity, group.id}} in stats.gaps
      assert {:missing_data, {:class_group_benefits, group.id}} in stats.gaps

      # ⚠️ И главное: чистота всё ещё РАБОТАЕТ — группа, собранная из копий,
      # остаётся такой же строгой, а не превращается в «хотя бы один уровень».
      assert Rules.compute(ladder([{:barbarian, 20}, {:bard, 21}]), ruleset).class_groups == []
    end

    # 🔴 Ровно тот случай, ради которого признание снимали ПОМЕТКОЙ, а не
    # вычёркиванием: группа без своей записи в `systems.json` — то есть без
    # получателей у выгод и без решения владельца про чистоту — обязана
    # заговорить обоими гэпами снова. До задачи 3.100 в этом состоянии жила
    # сама Адра, и тест читал живые данные; теперь состояние строится правкой
    # копии, потому что живая запись перестала быть примером.
    #
    # ⚠️ Третьей копии у Адры нет и не было (в `races.json` она не упоминается),
    # так что после удаления записи про группу известно ровно членство.
    test "группа без своей записи снова несёт оба гэпа", %{root: root, systems: path} do
      rewrite!(path, fn file ->
        update_in(file["systems"], fn systems ->
          Enum.reject(systems, &(&1["id"] == "adra_warriors"))
        end)
      end)

      ruleset = Loader.load!(root)["siala_41"]
      group = Enum.find(ruleset.class_groups, &(&1.name == "Воины Адры"))
      stats = Rules.compute(ladder([{:monk, 20}, {:paladin, 21}]), ruleset)

      assert group.known_from == :class_pages
      assert group.benefit_receivers == %{}
      assert group.purity_not_a_gap == nil

      assert {:assumed, {:class_group_purity, group.id}} in stats.gaps
      assert {:missing_data, {:class_group_benefits, group.id}} in stats.gaps

      # ⚠️ И членство продолжает считаться — иначе «гэпы вернулись» ничего
      # не значило бы: у билда, который группе не принадлежит, их нет и так.
      assert Enum.map(stats.class_groups, & &1.name) == ["Воины Адры"]
    end

    # ⚠️ Метка, которая не называет ни одной выгоды, роняет сборку: она
    # выглядит сделанной работой и не делает ничего, а выгода, которую она
    # когда-то называла, молча остаётся без метки.
    test "метка, потерявшая свою выгоду, роняет сборку", %{root: root, systems: path} do
      rewrite!(path, fn file ->
        patch_benefits(file, fn fact ->
          put_in(fact["affects_by_benefit"], %{"точильный камень" => ["custom_items"]})
        end)
      end)

      assert_raise RuntimeError, ~r/affects_by_benefit/s, fn -> Loader.load!(root) end
    end

    test "получатель вне словаря роняет сборку", %{root: root, systems: path} do
      rewrite!(path, fn file ->
        patch_benefits(file, fn fact ->
          put_in(fact["affects_by_benefit"]["точило"], ["custm_items"])
        end)
      end)

      assert_raise RuntimeError, ~r/custm_items/s, fn -> Loader.load!(root) end
    end

    # ⚠️ Решение владельца — единственный способ уменьшить число, которое видит
    # игрок, ничего не посчитав, поэтому наполовину записанное решение обязано
    # ронять сборку. Сторож общий (`Loader.NotAGap`), здесь проверяется, что
    # группы классов через него ДЕЙСТВИТЕЛЬНО проходят.
    test "решение про чистоту без довода роняет сборку", %{root: root, systems: path} do
      rewrite!(path, fn file ->
        update_in(file["systems"], fn systems ->
          Enum.map(systems, fn system ->
            if system["id"] == "adra_warriors" do
              update_in(system["facts"], fn facts ->
                Enum.map(facts, fn fact ->
                  if fact["what"] == "purity_required",
                    do: update_in(fact["not_a_gap"], &Map.delete(&1, "why")),
                    else: fact
                end)
              end)
            else
              system
            end
          end)
        end)
      end)

      assert_raise RuntimeError, ~r/not_a_gap.*`why`/s, fn -> Loader.load!(root) end
    end
  end

  # ------------------------------------------------------------------ helpers --

  defp group_gaps(stats),
    do: for(gap <- stats.gaps, inspect(gap) =~ "class_group", do: gap)

  defp ladder(spec) do
    build(for {class, count} <- spec, _ <- 1..count//1, do: class)
  end

  # Раса взята без своего бонуса (Тёмный эльф) намеренно: этот файл про состав
  # билда, а не про числа расы. Что вариант расового бонуса переключается от
  # группы — проверяет `racial_bonus_test.exs`, где для этого есть числа.
  defp build(levels) do
    %Build{} = Build.new(race: :elf, levels: levels, base_abilities: @flat)
  end

  defp rewrite!(path, fun) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> fun.()
    |> Jason.encode!()
    |> then(&File.write!(path, &1))
  end

  # Правка факта `benefits` у Сагры прямо в разобранном JSON — общая часть
  # четырёх порч выше.
  defp patch_benefits(file, fun) do
    update_in(file["systems"], fn systems ->
      Enum.map(systems, fn system ->
        if system["id"] == "sagra_warriors" do
          update_in(system["facts"], fn facts ->
            Enum.map(facts, fn fact ->
              if fact["what"] == "benefits", do: fun.(fact), else: fact
            end)
          end)
        else
          system
        end
      end)
    end)
  end

  defp patch_fact(path, system_id, what, fun) do
    rewrite!(path, fn file ->
      update_in(file["systems"], fn systems ->
        Enum.map(systems, fn system ->
          if system["id"] == system_id do
            update_in(system["facts"], fn facts ->
              Enum.map(facts, fn fact ->
                if fact["what"] == what, do: update_in(fact["value"], fun), else: fact
              end)
            end)
          else
            system
          end
        end)
      end)
    end)
  end
end
