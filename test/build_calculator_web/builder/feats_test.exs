defmodule BuildCalculatorWeb.Builder.FeatsTest do
  @moduledoc """
  The feat picker's slot arithmetic, away from the DOM.

  Everything here is about the one distinction the whole feat model rests on
  (CLAUDE.md §6): a slot is a decision the level owes, a granted feat simply
  arrives, and a class bonus slot is not the same thing as a general one.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules.{Build, FeatSlots, Gear}
  alias BuildCalculatorWeb.Builder.Feats

  # Свой список, а не читаем приватные атрибуты `Feats` — тест сверяет
  # РЕЗУЛЬТАТ группировки, а не заглядывает во внутреннее разбиение модуля.
  @tier_ids [
    :armor_proficiency_light,
    :armor_proficiency_medium,
    :armor_proficiency_heavy,
    :weapon_proficiency_simple,
    :weapon_proficiency_martial,
    :weapon_proficiency_exotic
  ]

  setup_all do
    # ⚠️ Оба ruleset'а, и второй здесь не для симметрии. Замер H5
    # (`GAME_CHECKS.md`, Dan 09.08.2026) выключил на Сиале все восемь ванильных
    # `Weapon proficiency (*)`, поэтому оружейной линейки в выдаче siala_41 нет
    # вовсе — а свёртка ярусов ОРУЖИЯ остаётся живым кодом и обязана быть
    # проверенной. Единственное место, где её сегодня видно, — ванильный ruleset,
    # где выдачи на месте.
    %{ruleset: Data.ruleset!(), vanilla: Data.ruleset!("vanilla")}
  end

  defp build(fields), do: Build.new(fields)

  defp captions(ruleset, build, level) do
    ruleset
    |> Feats.slot_labels(FeatSlots.at(build, ruleset, level))
    |> Enum.map(fn %{label: label, count: count} -> {label, count} end)
  end

  describe "slot_labels/2" do
    test "разные слоты названы по-разному, а не одним словом «фит»", %{ruleset: ruleset} do
      # Бонусный слот тратится ТОЛЬКО на фит из списка своего класса; показать
      # оба словом «фит» — значит спрятать ограничение, из-за которого потом
      # собирается нелегальный билд.
      assert captions(ruleset, build(levels: [:fighter]), 1) ==
               [{"общий фит", 1}, {"бонус Fighter", 1}]
    end

    test "у класса без бонусного слота остаётся только общий", %{ruleset: ruleset} do
      assert captions(ruleset, build(levels: [:cleric]), 1) == [{"общий фит", 1}]
    end

    test "расовый слот человека виден отдельной подписью", %{ruleset: ruleset} do
      human = build(race: :human, levels: [:fighter])
      dwarf = build(race: :dwarf, levels: [:fighter])

      assert {"фит расы", 1} in captions(ruleset, human, 1)
      refute {"фит расы", 1} in captions(ruleset, dwarf, 1)
    end

    # ⚠️ Баг 1.4 (Dan 03.08.2026): пул общего слота после 20-го не заменяется
    # эпическим, а расширяется — «эпический фит» без слова «общий» читался бы
    # как «только эпические» и сузил бы пул, который на самом деле вырос
    # (CLAUDE.md §6, `FeatSlots.candidates/2` на Fighter — 93 обычных фита
    # внутри 146 доступных здесь).
    test "за 20-м уровнем общий слот сохраняет имя и получает пометку «эпик»", %{
      ruleset: ruleset
    } do
      epic = build(levels: List.duplicate(:fighter, 21))

      assert captions(ruleset, epic, 21) == [{"общий фит · эпик", 1}]
    end

    test "слоты одного рода схлопываются в счётчик", %{ruleset: ruleset} do
      slots = [
        %{kind: :general, class: nil},
        %{kind: :class_bonus, class: :fighter},
        %{kind: :class_bonus, class: :fighter}
      ]

      assert Feats.slot_labels(ruleset, slots) == [
               %{label: "общий фит", count: 1},
               %{label: "бонус Fighter", count: 2}
             ]
    end

    test "уровень без слотов не даёт подписей", %{ruleset: ruleset} do
      assert captions(ruleset, build(levels: [:fighter, :fighter]), 2) |> Enum.empty?() == false
      assert Feats.slot_labels(ruleset, []) == []
    end

    # Тот же счётчик, но не на выдуманных слотах, а на настоящем уровне:
    # 35-й классовый уровень рейнджера выдаёт ДВА бонусных слота
    # (`Rules.FeatSlots`, починка 14.08.2026), и подпись обязана назвать два.
    test "рейнджер 35: два бонусных слота схлопываются в «×2», а не в один слот", %{
      ruleset: ruleset
    } do
      ranger = build(race: :human, levels: List.duplicate(:ranger, 41))

      assert captions(ruleset, ranger, 35) == [{"бонус Ranger · эпик", 2}]
      assert captions(ruleset, ranger, 38) == [{"бонус Ranger · эпик", 1}]
    end
  end

  describe "второй бонусный слот уровня доезжает до чипов (рейнджер 35)" do
    # 🔴 Чипы рисуются из `Feats.slots/3`, а их DOM-id — из `Ids.slot_dom_id/1`
    # по id слота. Одинаковый id у двух слотов уровня означал бы два элемента
    # с одним id в разметке И один вход карты `build.feats[35]` на два пика:
    # второй выбор молча затирал бы первый. Поэтому проверяются оба —
    # и что слотов два, и что различает их именно id.
    test "их два, у каждого свой DOM-id, и каждый несёт свой пик", %{ruleset: ruleset} do
      ranger =
        build(race: :human, levels: List.duplicate(:ranger, 41))
        |> Build.put_feat(35, {:class_bonus, :ranger}, :epic_prowess)
        |> Build.put_feat(35, {:class_bonus, :ranger, 2}, :epic_toughness)

      slots = Feats.slots(ruleset, ranger, 35)

      assert length(slots) == 2
      assert Enum.map(slots, & &1.feat) == [:epic_prowess, :epic_toughness]

      dom_ids = Enum.map(slots, &BuildCalculator.Ids.slot_dom_id(&1.id))
      assert dom_ids == ["class_bonus-ranger", "class_bonus-ranger-2"]
      assert dom_ids == Enum.uniq(dom_ids)
    end

    # Клик по фиту тратит «самый узкий подходящий» слот, и когда бонусный один
    # занят, свободным должен остаться ВТОРОЙ бонусный, а не общий: иначе общий
    # слот уходит на то, что бонусный покрыл бы бесплатно (CLAUDE.md §6).
    test "занятый первый бонусный не закрывает второй для следующего выбора", %{
      ruleset: ruleset
    } do
      ranger =
        build(race: :human, levels: List.duplicate(:ranger, 41))
        |> Build.put_feat(35, {:class_bonus, :ranger}, :epic_prowess)

      assert Enum.map(Feats.open_slots(ruleset, ranger, 35), & &1.id) == [
               {:class_bonus, :ranger, 2}
             ]

      assert %{id: {:class_bonus, :ranger, 2}} =
               Feats.best_slot(ruleset, ranger, 35, :epic_toughness)
    end
  end

  describe "granted/3" do
    # AGENT_QUEUE.md §1.10 шаг 3: 1-й уровень Cleric несёт ещё и владения
    # (лейбл `Proficiencies:`, Источники 2/3 в `wiki.parse.ex`) — список
    # ниже полный, не только `turn_undead`.
    #
    # ⚠️ `weapon_proficiency_simple` в списке ЕСТЬ — и не по ванильной причине.
    # Здесь стояло «БОЛЬШЕ НЕТ: замер H5 — на Сиале фит выключен»; прочтение
    # замера опровергнуто 26.08.2026 (задача 3.112) тремя игровыми логами
    # `.билд`: шард фит не выключил, а выдаёт его на классовом уровне 1
    # ВСЕМ 23 классам. Обе стороны под тестом в `siala_feat_layer_test.exs`.
    @cleric_level_1 [
      :armor_proficiency_heavy,
      :armor_proficiency_light,
      :armor_proficiency_medium,
      :shield_proficiency,
      :turn_undead,
      :weapon_proficiency_simple
    ]

    test "класс выдаёт свои фиты сам, слот на них не тратится", %{ruleset: ruleset} do
      # Сиала выдаёт Toughness бесплатно на 1-м уровне восьми классам.
      assert :toughness in Feats.granted(ruleset, build(levels: [:fighter]), 1)
      assert Feats.granted(ruleset, build(levels: [:cleric]), 1) == @cleric_level_1
    end

    test "считается уровень КЛАССА, а не персонажа", %{ruleset: ruleset} do
      # Второй уровень персонажа, но первый уровень Cleric.
      mixed = build(levels: [:fighter, :cleric])

      # ⚠️ Список короче `@cleric_level_1` на пять владений, и это баг 1.14,
      # а не потеря: воин отдал броню, щит и `Weapon proficiency (simple)` ещё
      # на 1-м уровне, так что клирик приносит здесь ровно `Turn undead`.
      # Утверждение теста от этого не пострадало — считался бы уровень
      # ПЕРСОНАЖА, вышло бы `[]`: на своём втором классовом уровне клирик
      # не выдаёт ничего.
      assert Feats.granted(ruleset, mixed, 2) == [:turn_undead]

      # Положительный контроль к строке выше: сырая выдача ядра осталась полной,
      # то есть фильтруется показ, а не данные.
      assert Build.granted_feats_at(mixed, ruleset, 2) == @cleric_level_1

      # А второй уровень Fighter не выдаёт ничего.
      assert Feats.granted(ruleset, build(levels: [:fighter, :fighter]), 2) == []
    end

    test "уровня без класса просто нет", %{ruleset: ruleset} do
      assert Feats.granted(ruleset, build(levels: []), 1) == []
      assert Feats.granted(ruleset, build(levels: [:fighter]), 0) == []
    end

    test "переносы Сиалы применены: Monk получает AC-бонус на 4-м, а не на 1-м", %{
      ruleset: ruleset
    } do
      # `feat_level_shift`: Monk AC-бонус 1 → 4, Evasion 1 → 25 (CLAUDE.md §3).
      # Ванильный список на 1-м уровне был бы на два фита длиннее.
      refute :monk_ac_bonus in Feats.granted(ruleset, build(levels: [:monk]), 1)
      assert :monk_ac_bonus in Feats.granted(ruleset, build(levels: List.duplicate(:monk, 4)), 4)
    end
  end

  describe "прирост владения, а не сырая выдача класса (баг 1.14)" do
    # 🔴 Наблюдение Dan 10.08.2026: «если файтер дал фиты какие-то, а потом их же
    # дал DD, то в реальности на момент получения DD эти фиты уже дал файтер и на
    # DD мы просто ничего не получили вместо них, они уже есть».
    #
    # ⚠️ ОБЕ половины правила стоят в ОДНОМ тесте намеренно. Поодиночке каждая
    # зеленеет и при неверной модели: «дубль не печатается» проходит на голой
    # разности множеств, которая заодно съедает законные ступени, а «ступень
    # печатается» проходит на сырой выдаче, которая и есть починяемый баг. Так
    # уже наступали с `dual wield` рейнджера и повторили с `instinctive_throw`
    # (AGENT_QUEUE §1.14, CLAUDE.md §9).
    test "дубль другого класса уходит, ступень ТОГО ЖЕ класса остаётся", %{ruleset: ruleset} do
      # Начало референсного билда Dan, уровень в уровень: Fighter 1–9,
      # Dwarven defender 10–19. ⚠️ Считано из его кода, а не из подписи
      # «Воин 10 / ДД 23 / ВМ 7»: лестница там НЕ монотонна (воин добирает
      # десятый уровень на 21-м, защитник — вторым куском с 28-го), а первый
      # уровень защитника стоит именно на десятом.
      dan =
        build(
          race: :dwarf,
          levels: List.duplicate(:fighter, 9) ++ List.duplicate(:dwarven_defender, 10)
        )

      # Половина первая. Уровень 10 — первый уровень Защитника: класс «выдаёт»
      # три яруса брони, щит, `Toughness` и `Weapon proficiency (simple)`,
      # которые воин отдал ещё на 1-м. Из семи имён новое ровно одно.
      #
      # ✅ И ровно так же печатает движок: в `hnyupius.log` на
      # `LEVEL 10: DWARVEN DEFENDER` стоит один `Defensive Stance` — тот же
      # референсный билд, тот же уровень.
      assert Feats.granted(ruleset, dan, 10) == [:defensive_stance]

      # Положительный контроль: сырая выдача ядра по-прежнему называет все семь,
      # то есть уходит именно повтор, а не половина списка по случайной причине.
      raw = Build.granted_feats_at(dan, ruleset, 10)
      assert :toughness in raw
      assert :armor_proficiency_heavy in raw
      assert :weapon_proficiency_simple in raw
      assert length(raw) == 7

      # Половина вторая. `Defensive awareness` I/II/III — это ОДИН id трижды
      # (одна страница вики на семейство), ступень лежит в `granted_feat_ranks`.
      # Разность множеств не показала бы вторую и третью, а они — настоящие
      # события, а не дубли.
      for level <- [11, 14, 19] do
        assert Feats.granted(ruleset, dan, level) == [:defensive_awareness],
               "уровень #{level}: ступень Defensive Awareness пропала"
      end

      # И каждая ступень называет себя — иначе три одинаковые строки.
      assert ["Defensive awareness I", "Defensive awareness II", "Defensive awareness III"] ==
               for(level <- [11, 14, 19], do: hd(Feats.granted_named(ruleset, dan, level)).name)
    end

    test "расовый фит — такой же дубль: Гном не получает Darkvision второй раз", %{
      ruleset: ruleset
    } do
      # Shadowdancer 2 выдаёт `Darkvision` и `Uncanny dodge`. У Гнома (Dwarf)
      # темнозрение расовое с рождения, поэтому класс приносит здесь одно.
      dwarf = build(race: :dwarf, levels: List.duplicate(:shadowdancer, 2))
      elf = build(race: :elf, levels: List.duplicate(:shadowdancer, 2))

      assert Feats.granted(ruleset, dwarf, 2) == [:uncanny_dodge]

      # Положительный контроль расой, а не пустым экраном: у Тёмного эльфа
      # темнозрения нет (у него `low_light_vision`), и класс отдаёт оба.
      assert Enum.sort(Feats.granted(ruleset, elf, 2)) == [:darkvision, :uncanny_dodge]
      assert :darkvision in ruleset.races[:dwarf].bonus_feats
      refute :darkvision in ruleset.races[:elf].bonus_feats
    end

    test "уровень, где вся выдача — дубль, не приносит ничего", %{ruleset: ruleset} do
      # Weapon master 1 выдаёт `Ki damage` и `Toughness`; у воина `Toughness`
      # уже есть. А второй уровень мастера оружия не выдаёт ничего вовсе —
      # на нём сравнивать нечего, и это разные ответы на разные вопросы,
      # а не один и тот же пустой список.
      #
      # ⚠️ Здесь в выдаче стоял ещё и `Weapon of choice`, и он ушёл 14.08.2026
      # замером M2: у ЭПИЧЕСКОГО персонажа (а этот взял Мастера оружия 21-м
      # уровнем) фит не выдаётся, а предлагается слотом наравне с эпическими
      # бонусными фитами класса. Строка ниже про неэпического — там выдача
      # осталась ванильной, и обе половины стоят рядом не случайно: порознь
      # каждая зеленела бы и при правиле, применённом ко всем подряд.
      wm = build(levels: List.duplicate(:fighter, 20) ++ List.duplicate(:weapon_master, 2))

      assert Feats.granted(ruleset, wm, 21) == [:ki_damage]
      assert Feats.granted(ruleset, wm, 22) == []
      assert :toughness in Build.granted_feats_at(wm, ruleset, 21)

      # ⚠️ Здесь стояло «неэпический Мастер оружия: выдача на месте, слота нет»
      # — правило гейтили на эпичность, пока Dan не спросил про уровни до 20-го
      # (M2b). Ответ: слот есть и там, выдачи нет нигде. Строка оставлена
      # перевёрнутой, а не удалена: она сторожит, чтобы гейт не вернулся.
      low = build(levels: List.duplicate(:fighter, 5) ++ [:weapon_master])
      refute :weapon_of_choice in Build.granted_feats_at(low, ruleset, 6)
    end

    test "пик слотом тоже считается владением", %{ruleset: ruleset} do
      # Волшебник `Toughness` даром не получает и берёт его слотом; воин,
      # взятый 21-м уровнем, выдаёт `Toughness` сам — и приносить его второй
      # раз нечем. Владение считается по `Build.feats_permanent/3`, то есть
      # слот наравне с выдачей: игроку всё равно, откуда фит уже пришёл.
      levels = List.duplicate(:wizard, 20) ++ [:fighter]

      picked = build(levels: levels, feats: %{1 => %{general: :toughness}})
      without = build(levels: levels)

      refute :toughness in Feats.granted(ruleset, picked, 21)

      # Положительный контроль двойной: то, что воин действительно приносит,
      # на месте у обоих, а без пика `Toughness` называется — значит ушёл
      # именно повтор, а не строка целиком.
      assert :shield_proficiency in Feats.granted(ruleset, picked, 21)
      assert :toughness in Feats.granted(ruleset, without, 21)
    end
  end

  describe "granted_named/3" do
    test "ступень выдачи стоит рядом с именем — иначе строка повторяется", %{ruleset: ruleset} do
      # Defensive awareness выдаётся Защитнику на 2, 5 и 10 уровнях класса.
      # Без ступени игрок трижды читает одно и то же (CLAUDE.md §9).
      for {class_level, expected} <- [{2, "Defensive awareness I"}, {5, "Defensive awareness II"}] do
        named =
          Feats.granted_named(
            ruleset,
            build(levels: List.duplicate(:dwarven_defender, class_level)),
            class_level
          )

        assert expected in Enum.map(named, & &1.name)
      end
    end

    test "ступень, у которой своё имя, ЗАМЕНЯЕТ имя фита, а не дописывается", %{
      ruleset: ruleset
    } do
      # Пять записей из 103 несут не хвост, а имя ступени со страницы (посчитано
      # обходом `granted_feat_ranks` на обоих ruleset'ах 10.08.2026; было
      # «три из 26» — устарело молча). Наивное склеивание дало бы
      # «Barbarian rage greater rage (4x/day)».
      cases = [
        {:barbarian, 15, "Greater rage (4x/day)"},
        {:barbarian, 16, "Greater rage (5x/day)"},
        {:barbarian, 20, "Greater rage (6x/day)"},
        {:shifter, 13, "Infinite humanoid shape"},
        {:druid, 20, "Improved elemental shape"}
      ]

      for {class, class_level, expected} <- cases do
        named =
          Feats.granted_named(
            ruleset,
            build(levels: List.duplicate(class, class_level)),
            class_level
          )

        assert expected in Enum.map(named, & &1.name)
      end
    end

    # §7, найдено 10.08.2026: шестая запись, начинающаяся с буквы, — ранг `VI+`
    # («VI и выше», `Rogue.wikitext`, строка 20-го уровня), и на ней имя фита
    # исчезало целиком: вор 20 читал «VI+», вор 17 — «Uncanny dodge V».
    #
    # ⚠️ Проверять обязательно ВМЕСТЕ с тестом выше: «имя не съедено» зеленеет и
    # у функции, которая не заменяет имя никогда, а «имя ступени заменяет» —
    # у той, что заменяет всегда.
    test "ранг, украшенный плюсом, остаётся хвостом — имя фита не исчезает", %{ruleset: ruleset} do
      rogue = fn n -> build(levels: List.duplicate(:rogue, n)) end

      named = fn n -> Enum.map(Feats.granted_named(ruleset, rogue.(n), n), & &1.name) end

      assert "Uncanny dodge VI+" in named.(20)
      refute "VI+" in named.(20)

      # Положительный контроль на тот же фит уровнем раньше: там ранг без
      # украшения и подпись работала всегда — значит первое утверждение падает
      # именно от плюса.
      assert "Uncanny dodge V" in named.(17)
    end

    test "без ступени остаётся чистое имя фита", %{ruleset: ruleset} do
      # Парсер не пишет пустых объектов, поэтому у большинства уровней ключа нет.
      named = Feats.granted_named(ruleset, build(levels: [:dwarven_defender]), 1)

      assert "Toughness" in Enum.map(named, & &1.name)
      assert "Defensive stance" in Enum.map(named, & &1.name)
    end

    test "id остаётся ванильным — по нему считаются владение и слоты", %{ruleset: ruleset} do
      named = Feats.granted_named(ruleset, build(levels: List.duplicate(:barbarian, 15)), 15)

      assert Enum.map(named, & &1.id) ==
               Feats.granted(ruleset, build(levels: List.duplicate(:barbarian, 15)), 15)
    end
  end

  describe "granted_display/3" do
    # Задача 1.10 шаг 4 (08.08.2026): шаг 3 довёл владения до `granted_feats`,
    # и «Класс даёт сам» на воине 1-го уровня стало сплошным абзацем из семи
    # имён через запятую. Свёртка ярусов — тем же способом, каким сама вики
    # называет их одной строкой (`'''Proficiencies''': armor (light, heavy,
    # medium), shields, weapons (martial, simple)`, AGENT_QUEUE §1.10).
    test "три яруса брони сворачиваются в одну строку", %{ruleset: ruleset} do
      # ⚠️ Строк четыре из шести сырых имён. Здесь стояло «три из пяти: замер H5
      # выключил владения ОРУЖИЕМ, и двух сырых имён (simple, martial) в выдаче
      # больше нет» — верно только про `martial`: `simple` вернулся 26.08.2026
      # (задача 3.112), потому что шард его не выключал, а выдаёт всем. Ярус
      # у линейки оружия теперь ровно один, поэтому скобка не собирается — это
      # тот же случай, что `Armor proficiency (light)` у вора ниже.
      assert Feats.granted_display(ruleset, build(levels: [:fighter]), 1) == [
               "Armor proficiency (light/medium/heavy)",
               "Shield proficiency",
               "Weapon proficiency (simple)",
               "Toughness"
             ]
    end

    # ⚠️ Свёртка ярусов ОРУЖИЯ (двух и более в одну скобку) видна только на
    # ванили: на Сиале из линейки simple/martial/exotic выдаётся ровно один
    # ярус, `simple`, и скобка из одного не собирается. Без этого теста ветка
    # «много ярусов» осталась бы непроверенной вовсе, и сломать её можно было бы
    # молча.
    test "ярусы оружия сворачиваются так же — проверено там, где выдача осталась",
         %{vanilla: vanilla} do
      assert Feats.granted_display(vanilla, build(levels: [:fighter]), 1) == [
               "Armor proficiency (light/medium/heavy)",
               "Shield proficiency",
               "Weapon proficiency (simple/martial)"
             ]
    end

    test "худший случай в данных (Paladin, 9 сырых имён) сворачивается", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      # Девять сырых имён ванильного паладина сворачиваются до пяти строк.
      # `Divine grace` тут есть, а на Сиале его нет: шард перенёс его с 1-го
      # уровня на 4-й (CLAUDE.md §3).
      assert Feats.granted_display(vanilla, build(levels: [:paladin]), 1) == [
               "Armor proficiency (light/medium/heavy)",
               "Shield proficiency",
               "Weapon proficiency (simple/martial)",
               "Divine grace",
               "Divine health",
               "Lay on hands"
             ]

      # На Сиале тот же паладин — той же длины, но состав другой: без
      # `Divine grace` (перенесён на 4-й), с бесплатным `Toughness`, и линейка
      # оружия сузилась до одного `simple` (шард выдаёт его всем, а `martial`
      # выключил).
      assert Feats.granted_display(ruleset, build(levels: [:paladin]), 1) == [
               "Armor proficiency (light/medium/heavy)",
               "Shield proficiency",
               "Weapon proficiency (simple)",
               "Divine health",
               "Lay on hands",
               "Toughness"
             ]
    end

    test "два яруса из трёх — свёртка только по факту выданного, не «все доспехи»",
         %{ruleset: ruleset} do
      # Друид получает light+medium, но НЕ heavy — свёрнутая строка обязана
      # называть ровно два яруса, а не подразумевать третий (задание прямо
      # предупреждает: «разворачивать „все доспехи“ можно только если класс
      # действительно выдаёт все три яруса»).
      display = Feats.granted_display(ruleset, build(levels: [:druid]), 1)

      assert "Armor proficiency (light/medium)" in display
      refute Enum.any?(display, &(&1 =~ "heavy"))
    end

    test "единственный ярус остаётся своим именем — скобки не собираются из одного", %{
      ruleset: ruleset
    } do
      # У Rogue только light: не «Armor proficiency (light)» → ещё какая-то
      # скобка, а буквально то же имя, что и без свёртки. То же и с оружием —
      # `simple` один, и скобка из одного не собирается.
      assert Feats.granted_display(ruleset, build(levels: [:rogue]), 1) == [
               "Armor proficiency (light)",
               "Weapon proficiency (simple)",
               "Sneak attack"
             ]
    end

    # ⚠️ Проверяется на ВАНИЛИ, и это не обход неудобного результата: на Сиале
    # `weapon_proficiency_wizard` выключен по выводу (замер H5 — фит выдаётся
    # ровно одним классом, а в СПИСКЕ ВЫБОРА выданное не печатается, поэтому там
    # наблюдать его нельзя), и в выдаче его нет. Правило же, которое тест
    # держит, — про свёртку, а не про Сиалу: проверять его надо там, где обе
    # строки существуют.
    test "именное оружие класса (monk/wizard/druid/rogue) в свёртку НЕ входит", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      # `weapon_proficiency_wizard` — не ярус общей линейки simple/martial/
      # exotic, а свой единственный фит; включить его в группу значило бы
      # придумать вики-факт, которого источник не называет.
      assert Feats.granted_display(vanilla, build(levels: [:wizard]), 1) == [
               "Scribe scroll",
               "Summon familiar",
               "Weapon proficiency (wizard)"
             ]

      # А на Сиале его в выдаче нет вовсе — и это тоже под тестом, иначе
      # изменение выше выглядело бы как потеря строки. Общий `simple` при этом
      # стоит первым: он ЯРУС линейки, то есть попадает в группу снаряжения,
      # а именной `wizard` в неё не попадал и стоял в общем хвосте.
      assert Feats.granted_display(ruleset, build(levels: [:wizard]), 1) == [
               "Weapon proficiency (simple)",
               "Scribe scroll",
               "Summon familiar"
             ]
    end

    # ⚠️ Проверяется на ВАНИЛИ с 26.08.2026, и причина — сама правка 3.112:
    # на Сиале `Weapon proficiency (simple)` выдаётся ВСЕМ 23 классам, то есть
    # класса без единого ярусного владения там больше не осталось ни одного,
    # и ветка «группировать нечего» на сиальских данных недостижима вовсе.
    # Ванильный монах её держит: брони и щита он не получает, а его
    # `weapon_proficiency_monk` — именной фит, а не ярус линейки.
    test "без единой брони/щита/оружия порядок остаётся исходным", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      named = Feats.granted_named(vanilla, build(levels: [:monk]), 1)

      assert Feats.granted_display(vanilla, build(levels: [:monk]), 1) ==
               Enum.map(named, & &1.name)

      # Отрицательный контроль к абзацу выше: на Сиале тот же монах группу
      # снаряжения уже имеет, и она встаёт ПЕРЕД остальным — то есть ветка
      # действительно сменилась, а не просто перестала проверяться.
      assert Feats.granted_display(ruleset, build(levels: [:monk]), 1) == [
               "Weapon proficiency (simple)",
               "Cleave",
               "Flurry of blows",
               "Improved unarmed strike",
               "Stunning fist"
             ]
    end

    test "ни один ярус не пропадает — только сворачивается", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      # Решение Дана 02.08.2026 (плашка «от класса ×N» без имён) остаётся
      # в силе: у свёрнутого списка меньше строк, но не меньше упомянутых
      # ярусов. Сравнение по «уточнению в скобках», а не по целому имени —
      # у комбинированной строки своей закрывающей скобки после «light» уже
      # нет («light/medium/heavy»), так что сверять пришлось бы не имя
      # целиком, а именно то, что легло внутрь скобок.
      #
      # ⚠️ Оба ruleset'а: на Сиале инвариант проверяется только на броне
      # (оружие выключено замером H5 и в выдачу не попадает), и без ванильной
      # половины оружейная линейка проверялась бы ПУСТЫМ циклом — то есть
      # никак. Ровно та «пустая проверка», от которой лечит HANDOFF.
      for {version, rs} <- [{"siala_41", ruleset}, {"vanilla", vanilla}],
          class <- [:fighter, :paladin, :blackguard, :dwarven_defender, :druid, :ranger] do
        build = build(levels: [class])
        raw = Feats.granted_named(rs, build, 1)
        display = Enum.join(Feats.granted_display(rs, build, 1), " | ")

        for %{id: id, name: name} <- raw, id in @tier_ids do
          [_, qualifier] = Regex.run(~r/\(([^()]+)\)$/, name)

          assert display =~ qualifier,
                 "#{version}/#{class}: ярус #{qualifier} потерялся из #{display}"
        end
      end

      # И сторож против того, чтобы ванильная половина цикла тоже опустела:
      # именно она проверяет свёртку оружия.
      assert Feats.granted_named(vanilla, build(levels: [:fighter]), 1)
             |> Enum.count(&(&1.id in [:weapon_proficiency_simple, :weapon_proficiency_martial])) ==
               2
    end
  end

  describe "free_later/3" do
    test "видит только уже выбранные уровни билда", %{ruleset: ruleset} do
      # Ranger 9 выдаёт Improved two-weapon fighting сам.
      nine = build(levels: List.duplicate(:ranger, 9))

      assert %{level: 9, class: :ranger, class_level: 9} =
               Feats.free_later(ruleset, nine, 1)[:improved_two_weapon_fighting]

      # У билда из одного уровня впереди ничего нет — обещать нечего.
      assert Feats.free_later(ruleset, build(levels: [:ranger]), 1) == %{}
    end

    test "называет самую раннюю выдачу — на неё и смотрит игрок", %{ruleset: ruleset} do
      # Monk 6 выдаёт Knockdown, Monk 2 — Deflect arrows.
      monk = build(levels: List.duplicate(:monk, 6))
      later = Feats.free_later(ruleset, monk, 1)

      assert later[:deflect_arrows].level == 2
      assert later[:knockdown].level == 6

      # Уровень, на котором стоим, в счёт не идёт: это отказ, а не подсказка.
      refute Map.has_key?(Feats.free_later(ruleset, monk, 2), :deflect_arrows)
    end

    test "фраза называет класс, его уровень и уровень персонажа", %{ruleset: ruleset} do
      text = Feats.free_later_text(ruleset, %{level: 12, class: :ranger, class_level: 6})

      assert text =~ "Ranger 6"
      assert text =~ "уровень 12"
      assert Feats.free_later_text(ruleset, nil) == nil
    end
  end

  describe "free_later_taken_text/2 — тот же грант, после взятия" do
    # HANDOFF §A.3 (решение Дана 02.08.2026): до взятия — совет «не трать
    # слот», после — констатация «слот можно освободить». Один и тот же
    # текст постфактум звучал бы неверно — слот уже потрачен, «не трать»
    # ему больше нечего посоветовать.
    test "тоже называет класс, оба уровня — но говорит «слот можно освободить»",
         %{ruleset: ruleset} do
      grant = %{level: 12, class: :ranger, class_level: 6}
      text = Feats.free_later_taken_text(ruleset, grant)

      assert text =~ "Ranger 6"
      assert text =~ "уровень 12"
      assert text =~ "слот можно освободить"
      assert Feats.free_later_taken_text(ruleset, nil) == nil
    end

    test "текст РЕАЛЬНО другой, а не тот же с опечаткой — «не трать» тут не встречается",
         %{ruleset: ruleset} do
      grant = %{level: 12, class: :ranger, class_level: 6}

      refute Feats.free_later_taken_text(ruleset, grant) =~ "не трать"

      # Положительный контроль: у предложения ДО взятия «не трать» есть —
      # без него `refute` выше зеленел бы и если бы обе фразы совпадали.
      assert Feats.free_later_text(ruleset, grant) =~ "не трать"
    end
  end

  describe "wasted_text/4 — та же подсказка для лестницы и экрана просмотра" do
    # Колонка прогрессии и экран просмотра идут по `build.feats` напрямую,
    # а не через `lists/4` — у них нет готового `entry`, только `{slot, pick}`
    # из билда. `wasted_text/4` — их вход в ту же машинерию.
    test "фит, положенный в слот, который класс отдаст даром позже — текст с классом и советом",
         %{ruleset: ruleset} do
      # Тот же билд, что и в тесте «несёт предупреждение» выше: Ranger 9
      # выдаёт `Improved two-weapon fighting` сам.
      build = build(levels: List.duplicate(:ranger, 9))
      later = Feats.free_later(ruleset, build, 1)

      text = Feats.wasted_text(ruleset, build, later, :improved_two_weapon_fighting)

      assert text =~ "Ranger 9"
      assert text =~ "слот можно освободить"
    end

    test "у пика без будущей бесплатной выдачи — nil (положительный контроль рядом)",
         %{ruleset: ruleset} do
      build = build(levels: List.duplicate(:ranger, 9))
      later = Feats.free_later(ruleset, build, 1)

      # `Power attack` этот билд никому даром не даёт — `later` для него пуст.
      assert Feats.wasted_text(ruleset, build, later, :power_attack) == nil
    end

    test "повторяемый фит не бывает «потрачен впустую», даже если формально в later",
         %{ruleset: ruleset} do
      # ⚠️ Собранный вручную `later`, а не билд: смысл теста — что
      # ПОВТОРЯЕМОСТЬ гасит предупреждение раньше, чем оно дошло бы до
      # текста, а не что у реального билда так совпало. `Spell focus` берут
      # по школе много раз — вторая покупка не «впустую», даже если класс
      # где-то и выдаёт такой же фит бесплатно.
      later = %{spell_focus: %{level: 5, class: :wizard, class_level: 5}}

      assert Feats.repeatable?(ruleset, :spell_focus)
      assert Feats.wasted_text(ruleset, build(levels: [:wizard]), later, :spell_focus) == nil
    end

    # Вторая половина той же подсказки, заведённая волной 14: слот потрачен
    # на фит, который уже лежит на надетой вещи (задача 3.3). Предупреждать
    # обязаны оба экрана, потому что билд открывается по ссылке уже со всем,
    # что в нём есть, — и совет «освободить слот» тут слабее классового, что
    # текст и говорит.
    test "фит, который уже есть с вещи, — предупреждение про вещь", %{ruleset: ruleset} do
      %Build{} = plain = build(levels: List.duplicate(:wizard, 5))
      geared = %Build{plain | gear: Gear.new(feats: [:alertness])}

      # Отрицательный контроль ПЕРВЫМ: без объявления подсказки нет вовсе,
      # то есть текст ниже приносит именно вещь, а не что-нибудь ещё.
      assert Feats.wasted_text(ruleset, plain, %{}, :alertness) == nil

      text = Feats.wasted_text(ruleset, geared, %{}, :alertness)
      assert text =~ "с вещи"
      assert text =~ "снимешь предмет"
    end

    # ⚠️ Обе половины парного правила — одним тестом: «слот потратить можно»
    # и «а числа он не меняет» по отдельности зеленеют и при неверной модели.
    test "повторяемый фит с вещи подсказки НЕ получает — второе взятие не впустую", %{
      ruleset: ruleset
    } do
      %Build{} = plain = build(levels: List.duplicate(:wizard, 21))
      geared = %Build{plain | gear: Gear.new(feats: [:epic_toughness])}

      # Неповторяемый рядом — положительный контроль, что вызов вообще работает
      # на этом билде и на этом объявлении.
      both = %Build{plain | gear: Gear.new(feats: [:epic_toughness, :alertness])}
      assert Feats.wasted_text(ruleset, both, %{}, :alertness) =~ "с вещи"

      assert Feats.wasted_text(ruleset, geared, %{}, :epic_toughness) == nil
    end
  end

  describe "lists/4 и то, что билд уже даёт даром" do
    defp ids(entries), do: MapSet.new(entries, & &1.feat.id)

    defp reasons_for(lists, id) do
      Enum.find_value(lists.blocked, [], &if(&1.feat.id == id, do: &1.reasons))
    end

    test "фит, выданный на этом же уровне, к покупке не предлагается", %{ruleset: ruleset} do
      # Самый частый первый фит в NWN, и Сиала выдаёт его восьми классам даром.
      lists = Feats.lists(ruleset, build(levels: [:fighter]), 1)

      refute :toughness in ids(lists.available)
      assert reasons_for(lists, :toughness) == [{:granted_here, :toughness}]
    end

    test "выданное классом раньше считается «уже есть», как и купленное", %{ruleset: ruleset} do
      lists = Feats.lists(ruleset, build(levels: List.duplicate(:fighter, 3)), 3)

      refute :toughness in ids(lists.available)
      assert reasons_for(lists, :toughness) == [{:already_taken, :toughness}]
    end

    # ⚠️ Ищем в обоих списках, и это не послабление. С тех пор как список
    # спрашивает ядро про требования, `Deflect arrows` у монаха с базовыми
    # статами лежит в недоступных — DEX 10 не набирает требуемых 13. Но
    # предупреждение «получишь бесплатно на Monk 2» относится к ФИТУ,
    # а не к его сегодняшней доступности: игрок, который дотянет требования,
    # должен узнать про бесплатную выдачу до того, как потратит слот.
    #
    # ⚠️ Было `Improved two-weapon fighting` у Ranger 9 — источник 4
    # (AGENT_QUEUE.md §1.10) добавил `improved_two_weapon_fighting` в
    # `ranger.unavailable_feats` («cannot be selected when gaining a ranger
    # level, even prior to receiving it automatically» — страница фита прямо
    # запрещает то, что этот тест проверял): фит пропал из ОБОИХ списков
    # (`Feats.lists/4` его больше не предлагает вовсе, ни доступным, ни
    # заблокированным), и `entry` стал `nil`. Заменено на `Deflect arrows` /
    # `Monk 2` — тот же паттерн («заблокирован требованиями, но предупреждение
    # есть»), монах его не запрещает (`monk.unavailable_feats` фита не
    # содержит), сверено вызовом `Feats.lists/4` напрямую.
    test "фит, который придёт даром позже, несёт предупреждение", %{ruleset: ruleset} do
      lists = Feats.lists(ruleset, build(levels: List.duplicate(:monk, 9)), 1)

      entry = Enum.find(lists.available ++ lists.blocked, &(&1.feat.id == :deflect_arrows))

      assert entry.free_later == %{level: 2, class: :monk, class_level: 2}

      # На предложении — ещё не «взят»: слот под него никто не тратил.
      # HANDOFF §A.3 — именно эта половина работала и раньше; вторая
      # («взят» тоже видит `free_later`) проверена ниже отдельным тестом.
      refute entry.taken?
    end

    test "на том, что уже в руках, предупреждения нет", %{ruleset: ruleset} do
      lists = Feats.lists(ruleset, build(levels: List.duplicate(:ranger, 9)), 1)

      assert Enum.all?(lists.available ++ lists.blocked, fn entry ->
               entry.feat.id != :toughness or is_nil(entry.free_later)
             end)
    end

    # ⚠️ HANDOFF §A.3: билд, УЖЕ сохранённый с фитом в слоте, который класс
    # всё равно выдаст даром позже, раньше показывался просто «✓ взят» —
    # предупреждение работало только до взятия. `taken?` — то, что отличает
    # этот случай от предыдущих двух тестов: слот занят ИМЕННО этим пиком
    # на ЭТОМ уровне, а не выдан классом и не куплен раньше.
    #
    # ⚠️ Тот же перенос на `Deflect arrows` / `Monk`, что и выше, и по той же
    # причине: `Improved two-weapon fighting` у Ranger теперь запрещён вообще
    # (источник 4), `Build.put_feat` кладёт слот, а `Feats.lists/4` его для
    # этого класса больше не находит ни в одном списке.
    test "фит, положенный в слот вручную — «взят», и ядро это видит, а не только шаблон",
         %{ruleset: ruleset} do
      build =
        Build.put_feat(build(levels: List.duplicate(:monk, 9)), 1, :general, :deflect_arrows)

      lists = Feats.lists(ruleset, build, 1)
      entry = Enum.find(lists.available, &(&1.feat.id == :deflect_arrows))

      assert entry.taken?
      assert entry.free_later == %{level: 2, class: :monk, class_level: 2}
      assert entry.chosen_slot == :general
    end

    # ⚠️ Волна 14 (09.08.2026). До неё фит, лежащий на ВЕЩИ, уезжал
    # в «Недоступные» с причиной `{:already_taken, …}` — замерено вызовом:
    # волшебник 5 с `Toughness` на вещи получал `{:blocked, [already_taken:
    # :toughness]}`, а без вещи `{:available, []}`. Предмет снимается, слот нет,
    # поэтому это была ложная нелегальность: отказ ПОЯВЛЯЛСЯ от объявления.
    test "фит с вещи остаётся доступным и несёт оговорку, а не отказ", %{ruleset: ruleset} do
      %Build{} = plain = build(levels: List.duplicate(:wizard, 5))
      geared = %Build{plain | gear: Gear.new(feats: [:toughness])}

      # Отрицательный контроль ПЕРВЫМ: без вещи строка тоже доступна и оговорки
      # не несёт — значит ниже проверяется вклад объявления, а не то, что фит
      # доступен всегда.
      before = Enum.find(Feats.lists(ruleset, plain, 3).available, &(&1.feat.id == :toughness))
      assert before.caveats == []

      lists = Feats.lists(ruleset, geared, 3)
      entry = Enum.find(lists.available, &(&1.feat.id == :toughness))

      assert entry, "фит с вещи не должен уезжать в «Недоступные»"
      assert entry.reasons == []
      assert entry.caveats == [{:owned_from_gear, :toughness}]
      refute :toughness in ids(lists.blocked)

      # Оговорка подписана по-русски и говорит обе вещи: слот ничего не даст,
      # но предмет можно снять.
      text = Feats.caveat_text({:owned_from_gear, :toughness}, ruleset)
      assert text =~ "с вещи"
      assert text =~ "снимешь предмет"
    end

    # У повторяемого — ни отказа, ни оговорки: второе взятие стоит настоящих
    # 20 HP (проверено в `gear_feats_test.exs`), и «слот ничего не добавит»
    # было бы ложью.
    test "повторяемый фит с вещи оговорки не несёт", %{ruleset: ruleset} do
      %Build{} = plain = build(levels: List.duplicate(:wizard, 21))
      geared = %Build{plain | gear: Gear.new(feats: [:epic_toughness, :alertness])}

      lists = Feats.lists(ruleset, geared, 21, query: "toughness")
      entry = Enum.find(lists.available, &(&1.feat.id == :epic_toughness))

      assert entry.reasons == []
      assert entry.caveats == []

      # Положительный контроль на том же билде и в том же вызове: неповторяемый
      # `Alertness` оговорку получает, значит механизм включён.
      alertness = Feats.lists(ruleset, geared, 21, query: "alertness")
      entry = Enum.find(alertness.available, &(&1.feat.id == :alertness))
      assert entry.caveats == [{:owned_from_gear, :alertness}]
    end

    # Третья форма отказа, волна 14. Раньше в этой строке стояло
    # `{:not_slottable, "special"}` — «выдаётся классом или расой», чего
    # страница не говорит: фит приходит с предмета.
    test "фит, который нельзя выбрать при росте персонажа, назван своей причиной", %{
      ruleset: ruleset
    } do
      for feat <- [:riding_sprint, :smile_of_death] do
        lists =
          Feats.lists(ruleset, build(levels: List.duplicate(:fighter, 21)), 21,
            query: String.replace(Atom.to_string(feat), "_", " ")
          )

        refute feat in ids(lists.available)
        assert reasons_for(lists, feat) == [{:not_selectable_at_level_up, feat}]

        text = Feats.reason({:not_selectable_at_level_up, feat}, ruleset)
        assert text =~ "не выбирается"
        refute text =~ "классом или расой"
      end
    end

    test "отключённый на шарде фит объясняется отключением, а не слотом", %{ruleset: ruleset} do
      # `Devastating critical` на Сиале выключен целиком. Пустой слот его
      # не вернёт, поэтому «нет подходящего свободного слота» — формально
      # правда, а по сути ложь: искать свободный слот бессмысленно.
      lists =
        Feats.lists(ruleset, build(levels: List.duplicate(:fighter, 21)), 21,
          query: "devastating"
        )

      refute :devastating_critical in ids(lists.available)

      assert reasons_for(lists, :devastating_critical) ==
               [{:feat_disabled, :devastating_critical}]

      assert Feats.reason({:feat_disabled, :devastating_critical}, ruleset) =~ "отключён"
    end

    test "классовые способности берутся только своим бонусным слотом", %{ruleset: ruleset} do
      # `type: "class"` — 124 записи из 299. Общим слотом их взять нельзя…
      general = Feats.lists(ruleset, build(levels: [:fighter]), 1)
      refute Enum.any?(general.available, &(&1.feat.type == "class"))

      # …а бонусным слотом вора — можно и нужно: спецспособности Rogue 10 это
      # выбор из списка, а не выдача.
      rogue = Feats.lists(ruleset, build(levels: List.duplicate(:rogue, 10)), 10)
      assert :opportunist in ids(rogue.available)
      assert :crippling_strike in ids(rogue.available)
    end
  end

  describe "gaps/2" do
    # ⚠️ Пробел ставится по НЕПРОЧИТАННОМУ остатку, а не по наличию прозы.
    # Раньше здесь стоял `power_attack`, и тест проходил — но проходил зря:
    # его `strength 13+` давно разобран и реально отбивает выбор. Пробел на нём
    # означал «мы это не проверяли» про проверенное. Нужен фит, у которого
    # в `prereqs` действительно остался `unparsed`.
    #
    # ⚠️ Носитель сменился 25.08.2026 (задача 3.104): здесь стоял `skill_focus`
    # с его «able to use the skill», и эта фраза теперь ПРОЧИТАНА — четырьмя
    # ключами. Взят `Extra turning`, у которого остаток настоящий и подавлен
    # намеренно: «exclusive to clerics, paladins» — список выдающих классов,
    # а не порог. Настоящих сырых остатков в справочнике не осталось ни одного,
    # и все семь оставшихся носителей — того же рода, что этот.
    test "фит с НЕДОчитанными требованиями остаётся пробелом", %{ruleset: ruleset} do
      taken = build(levels: [:cleric], feats: %{1 => %{general: :extra_turning}})

      assert {:missing_data, {:feat_prerequisites, :extra_turning}} in Feats.gaps(ruleset, taken)
    end

    test "фит с полностью разобранными требованиями пробелом НЕ становится", %{ruleset: ruleset} do
      taken =
        build(
          levels: [:fighter],
          feats: %{1 => %{{:class_bonus, :fighter} => :power_attack}}
        )

      refute {:missing_data, {:feat_prerequisites, :power_attack}} in Feats.gaps(ruleset, taken)
    end

    test "«фиты классов не размечены» больше не пробел — данные есть", %{ruleset: ruleset} do
      assert Feats.gaps(ruleset, build(levels: [:fighter])) == []
    end
  end

  describe "второй шаг: choice_options/5" do
    defp wizard(feats \\ %{}) do
      build(
        race: :human,
        levels: [:wizard, :wizard, :wizard],
        base_abilities: %{str: 10, dex: 12, con: 12, int: 16, wis: 10, cha: 8},
        feats: feats
      )
    end

    defp values(options), do: Enum.map(options.allowed, & &1.value)
    defp blocked_values(options), do: Enum.map(options.blocked, & &1.value)

    test "фит без параметра второго шага не требует", %{ruleset: ruleset} do
      assert Feats.choice_options(ruleset, wizard(), 1, :toughness, :general) == nil

      # Положительный контроль: счётный фит — тоже без второго шага, но по
      # другой причине (называть нечего), и это не должно перепутаться
      # с «фит не повторяем».
      assert Feats.choice_options(ruleset, wizard(), 1, :epic_toughness, :general) == nil
      assert Feats.repeatable?(ruleset, :epic_toughness)
    end

    test "фит с параметром отдаёт список от ядра", %{ruleset: ruleset} do
      options = Feats.choice_options(ruleset, wizard(), 1, :spell_focus, :general)

      assert options.domain == :spell_school
      assert :evocation in values(options)

      # `universal` — «не настоящая школа», её отсекают ворота справочника.
      # Мы их не повторяем, поэтому значение не должно всплыть ни в одном
      # из двух списков.
      refute :universal in values(options)
      refute :universal in blocked_values(options)
    end

    test "занятое ЭТИМ ЖЕ фитом значение прячется, а не показывается с причиной",
         %{ruleset: ruleset} do
      taken = wizard(%{1 => %{general: {:spell_focus, :evocation}}})
      options = Feats.choice_options(ruleset, taken, 2, :spell_focus, :general)

      # Решение Дана (§6): «эту школу ты уже взял» механике не учит.
      refute :evocation in values(options)
      refute :evocation in blocked_values(options)

      # Положительный контроль: без этого взятия школа в списке есть — иначе
      # оба `refute` зеленели бы и на пустом списке.
      assert :evocation in values(
               Feats.choice_options(ruleset, wizard(), 2, :spell_focus, :general)
             )
    end

    test "недоступное ПО ПРАВИЛАМ показывается с причиной, а не прячется",
         %{ruleset: ruleset} do
      taken = wizard(%{1 => %{general: {:spell_focus, :evocation}}})
      options = Feats.choice_options(ruleset, taken, 3, :greater_spell_focus, :general)

      # Единственная школа, где есть базовый Spell focus.
      assert values(options) == [:evocation]

      # Остальные семь — не спрятаны: у них механическая причина, и она названа.
      assert :necromancy in blocked_values(options)
      necromancy = Enum.find(options.blocked, &(&1.value == :necromancy))
      assert {:requires_same_choice, :spell_focus, :necromancy} in necromancy.reasons
      assert Feats.reason(hd(necromancy.reasons), ruleset) =~ "Spell focus"

      assert length(necromancy.reasons) == 1
    end

    test "требования самого фита проверяются по каждому значению", %{ruleset: ruleset} do
      # ⚠️ Кандидат ядра — это ещё не «можно взять»: `candidates/3` смотрит
      # только повторяемость и «в той же школе», а `Epic skill focus` хочет
      # 20 рангов В ВЫБРАННОМ навыке. Без поимённой проверки кнопка молча
      # не срабатывала бы.
      epic =
        build(
          race: :human,
          levels: List.duplicate(:fighter, 21),
          base_abilities: %{str: 16, dex: 12, con: 14, int: 12, wis: 10, cha: 8},
          skills: %{1 => %{discipline: 24}}
        )

      options = Feats.choice_options(ruleset, epic, 21, :epic_skill_focus, :general)

      assert values(options) == [:discipline]
      assert :tumble in blocked_values(options)
    end

    test "имя значения берётся из данных, в том числе у домена без файла имён",
         %{ruleset: ruleset} do
      options = Feats.choice_options(ruleset, wizard(), 1, :skill_focus, :general)
      tumble = Enum.find(options.allowed ++ options.blocked, &(&1.value == :tumble))

      # `skill` резолвится не в файл, а в словарь ruleset'а, и `names` у него
      # пуст — имя приходится брать из самой записи навыка. Иначе игрок видел
      # бы `move_silently` вместо `Move silently`.
      assert tumble.name == "Tumble"
    end
  end

  describe "повторяемость" do
    test "повторяемый фит остаётся доступным после первого взятия", %{ruleset: ruleset} do
      taken =
        build(
          race: :human,
          levels: List.duplicate(:fighter, 24),
          base_abilities: %{str: 16, dex: 12, con: 14, int: 12, wis: 10, cha: 8},
          feats: %{21 => %{general: :epic_toughness}}
        )

      row = row_for(ruleset, taken, 24, :epic_toughness)

      assert row.reasons == []
      assert row.takes == 1
      assert row.repeatable?
    end

    test "неповторяемый фит после взятия отбивается «уже есть»", %{ruleset: ruleset} do
      taken =
        build(
          race: :human,
          levels: List.duplicate(:fighter, 24),
          base_abilities: %{str: 16, dex: 12, con: 14, int: 12, wis: 10, cha: 8},
          feats: %{1 => %{general: :alertness}}
        )

      assert [{:already_taken, :alertness}] == row_for(ruleset, taken, 24, :alertness).reasons
    end

    test "потолок взятий из данных отбивает лишнее", %{ruleset: ruleset} do
      # `Epic toughness` — 10 взятий по данным (Дан, 02.08.2026). Слоты
      # заполняются НАСТОЯЩИЕ, через `best_slot/4`: билд, в котором пик лежит
      # в несуществующем слоте, доказывал бы правило на персонаже, которого
      # не бывает.
      epic =
        build(
          race: :human,
          levels: List.duplicate(:fighter, 41),
          base_abilities: %{str: 16, dex: 12, con: 14, int: 12, wis: 10, cha: 8}
        )

      {ten, 10} = take_repeatedly(ruleset, epic, :epic_toughness, 10)
      {nine, 9} = take_repeatedly(ruleset, epic, :epic_toughness, 9)

      # Спрашиваем поиском: на 41-м уровне слотов нет вовсе (общий даётся
      # каждый третий), а вопрос «почему нельзя ещё раз» игрок задаёт именно
      # поиском — и ответ обязан быть про потолок, а не про отсутствие слота.
      assert {:max_takes, :epic_toughness, 10} in row_for(
               ruleset,
               ten,
               41,
               :epic_toughness,
               "epic toughness"
             ).reasons

      # Положительный контроль: на девяти взятиях потолок молчит, то есть
      # `assert` выше проверяет число, а не сам факт повторяемости.
      refute Enum.any?(
               row_for(ruleset, nine, 39, :epic_toughness, "epic toughness").reasons,
               &match?({:max_takes, _, _}, &1)
             )
    end

    defp take_repeatedly(ruleset, build, feat_id, times) do
      Enum.reduce(1..41, {build, 0}, fn level, acc ->
        Enum.reduce(1..4, acc, fn _slot_attempt, {build, taken} ->
          slot = taken < times && Feats.best_slot(ruleset, build, level, feat_id)

          if slot,
            do: {Build.put_feat(build, level, slot.id, feat_id), taken + 1},
            else: {build, taken}
        end)
      end)
    end

    # ⚠️ Раньше этот тест стоял на настоящих данных: у домена `weapon`
    # справочника не было, и второй `Weapon focus` записать было нечем.
    # ЗАДАЧА 3.5 закрыла эту дыру — `weapons.json` есть, и после неё
    # неразрешимых доменов в обоих ruleset'ах не осталось НИ ОДНОГО.
    # Механизм при этом никуда не делся и обязан продолжать работать: домен
    # без справочника заведётся снова в тот день, когда данные назовут новый.
    # Поэтому свидетель теперь синтетический — тот же приём, что
    # `without_same_choice/1` в `choice_domain_gate_test.exs`.
    test "повтор без справочника отбивается своей причиной, а не «уже есть»",
         %{ruleset: ruleset} do
      taken =
        build(
          race: :human,
          levels: List.duplicate(:fighter, 6),
          base_abilities: %{str: 16, dex: 12, con: 14, int: 12, wis: 10, cha: 8},
          feats: %{1 => %{general: :weapon_focus}}
        )

      blind = without_dictionary(ruleset, :weapon)
      row = row_for(blind, taken, 6, :weapon_focus)

      assert [{:choice_unrecordable, :weapon_focus, :weapon}] == row.reasons
      assert Feats.reason(hd(row.reasons), blind) =~ "справочника"
      refute Feats.repeatable?(blind, :weapon_focus)

      # Положительный контроль: первое взятие ничем не отбито.
      %Build{} = taken_struct = taken
      fresh = %Build{taken_struct | feats: %{}}
      assert row_for(blind, fresh, 6, :weapon_focus).reasons == []

      # ⚠️ И положительный контроль ко всему приёму: на НАСТОЯЩИХ данных
      # повтор законен, потому что второе оружие теперь есть чем назвать.
      # Без этой половины тест выше зеленел бы и с потерянным справочником.
      assert Feats.repeatable?(ruleset, :weapon_focus)
      assert row_for(ruleset, taken, 6, :weapon_focus).reasons == []
    end

    # Настоящий ruleset, у которого у одного домена отобран справочник —
    # ровно то состояние, в котором `weapon` жил до задачи 3.5.
    defp without_dictionary(ruleset, domain) do
      blinded = %{values: nil, flags: %{}, source: nil}
      %{ruleset | choice_domains: Map.put(ruleset.choice_domains, domain, blinded)}
    end

    defp row_for(ruleset, build, level, feat_id, query \\ "") do
      lists = Feats.lists(ruleset, build, level, query: query, type: "all")

      Enum.find(lists.available ++ lists.blocked, &(&1.feat.id == feat_id))
    end
  end

  # Баг 1.5, найден Dan 03.08.2026: у `Greater spell focus` и `Arcane defense`
  # в списке стояло «выбирать больше нечего: всё из «spell_school» уже взято
  # этим фитом» — у персонажа, который не брал `Spell focus` ни разу.
  #
  # Цепочка школ проверяется на ТРЁХ ступенях (`Spell focus` → `Greater` →
  # `Epic`), потому что предусловие у них разной длины: у `Epic` требуемых
  # фитов два, и «нужен один» с «нужны оба» — разные предложения.
  describe "почему выбирать нечего — две разные причины" do
    defp caster(feats, levels \\ 30) do
      build(
        race: :human,
        alignment: :true_neutral,
        levels: List.duplicate(:wizard, levels),
        base_abilities: %{str: 10, dex: 12, con: 12, int: 20, wis: 10, cha: 8},
        feats: feats
      )
    end

    defp reasons_for(ruleset, build, level, feat_id) do
      row_for(ruleset, build, level, feat_id, "focus").reasons
    end

    defp texts_for(ruleset, build, level, feat_id) do
      for reason <- reasons_for(ruleset, build, level, feat_id),
          do: Feats.reason(reason, ruleset)
    end

    test "без базового фита причина — «сначала нужен», а не «уже взято»",
         %{ruleset: ruleset} do
      empty = caster(%{})

      assert [{:choice_requires, :greater_spell_focus, [:spell_focus], :spell_school}] ==
               reasons_for(ruleset, empty, 30, :greater_spell_focus)

      text = hd(texts_for(ruleset, empty, 30, :greater_spell_focus))

      assert text =~ "Spell focus"
      assert text =~ "школа магии"

      # ⚠️ Именно та фраза, которой баг и врал. («уже» подстрокой не искать:
      # оно сидит внутри слова «нужен».)
      refute text =~ "уже взят"
      refute text =~ "нечего"
    end

    # ⚠️ `Arcane defense` — второй фит из находки Дана, и он ВАЖЕН отдельно:
    # повторяемость ему дал ручной слой Сиалы (`siala_41/feats.json`), а
    # `same_choice_as` пришёл машинно из ванили. Проверять только
    # `Greater spell focus` значило бы проверять одну половину данных.
    test "то же самое у Arcane defense — фит собран из двух слоёв данных",
         %{ruleset: ruleset} do
      empty = caster(%{})
      row = row_for(ruleset, empty, 30, :arcane_defense, "arcane defense")

      assert [{:choice_requires, :arcane_defense, [:spell_focus], :spell_school}] == row.reasons
    end

    test "израсходованное называется израсходованным", %{ruleset: ruleset} do
      taken =
        caster(%{
          1 => %{general: {:spell_focus, :evocation}},
          3 => %{general: {:greater_spell_focus, :evocation}}
        })

      assert [{:choice_exhausted, :greater_spell_focus, :spell_school}] ==
               reasons_for(ruleset, taken, 30, :greater_spell_focus)

      assert hd(texts_for(ruleset, taken, 30, :greater_spell_focus)) =~ "нечего"
    end

    # ⚠️ Положительный контроль: без него оба теста выше зеленели бы и у
    # реализации, которая просто запретила фит во всех случаях.
    test "школа, где базовый фит есть, а производный нет, — фит доступен",
         %{ruleset: ruleset} do
      taken =
        caster(%{
          1 => %{general: {:spell_focus, :evocation}},
          3 => %{general: {:spell_focus, :abjuration}},
          6 => %{general: {:greater_spell_focus, :evocation}}
        })

      assert [] == reasons_for(ruleset, taken, 30, :greater_spell_focus)

      options = Feats.choice_options(ruleset, taken, 30, :greater_spell_focus, :general)
      assert Enum.map(options.allowed, & &1.value) == [:abjuration]
    end

    test "третья ступень называет оба недостающих фита", %{ruleset: ruleset} do
      empty = caster(%{})

      assert [
               {:choice_requires, :epic_spell_focus, [:spell_focus, :greater_spell_focus],
                :spell_school}
             ] == reasons_for(ruleset, empty, 30, :epic_spell_focus)

      # Взят базовый — остаётся назвать один, а не оба.
      with_base = caster(%{1 => %{general: {:spell_focus, :evocation}}})

      assert [{:choice_requires, :epic_spell_focus, [:greater_spell_focus], :spell_school}] ==
               reasons_for(ruleset, with_base, 30, :epic_spell_focus)

      # Положительный контроль третьей ступени.
      full =
        caster(%{
          1 => %{general: {:spell_focus, :evocation}},
          3 => %{general: {:greater_spell_focus, :evocation}}
        })

      assert [] == reasons_for(ruleset, full, 30, :epic_spell_focus)
    end

    # `{:choice_requires, …}` — то же требование, что и `{:requires_feat, …}`,
    # сказанное точнее. Печатать оба значит сказать игроку одно дважды.
    test "точная причина вытесняет общую, но только её", %{ruleset: ruleset} do
      young = caster(%{}, 9)

      refute {:requires_feat, :spell_focus} in reasons_for(
               ruleset,
               young,
               9,
               :greater_spell_focus
             )

      # ⚠️ …и ничего сверх неё: у эпического фита требование по уровню обязано
      # остаться. Прежняя ветка стояла в `cond` выше требований и глушила их все.
      assert {:requires_epic_level, ruleset.epic.starts_at} in reasons_for(
               ruleset,
               young,
               9,
               :epic_spell_focus
             )
    end

    # ⚠️ Второй шаг тоже говорил дважды, и увидеть это можно ТОЛЬКО у того, кто
    # базовый фит не брал вовсе: рядом с точным «нужен Spell focus: Necromancy»
    # стояло общее «нужен фит Spell focus». У персонажа, который `Spell focus`
    # уже взял, общего требования нет вовсе — и проверка на нём зеленеет, ничего
    # не проверив (так и вышло с первой версией этого теста, поймала порча).
    test "во втором шаге требование не повторяется общей формой", %{ruleset: ruleset} do
      options = Feats.choice_options(ruleset, caster(%{}), 30, :greater_spell_focus, :general)

      assert options.allowed == []
      assert length(options.blocked) == 8

      for option <- options.blocked do
        assert [{:requires_same_choice, :spell_focus, _}] = option.reasons
      end
    end

    # Третий честный ответ, и он обязан отличаться от двух первых: домен назван,
    # справочника нет. «Не проверяем» — не то же самое, что «нечего выбрать».
    #
    # ⚠️ После задачи 3.5 неразрешимых доменов в данных нет, поэтому справочник
    # отбирается у копии ruleset'а — механизм проверяется, а не дыра в данных.
    test "домен без справочника — своя причина, не «нечего выбрать»",
         %{ruleset: ruleset} do
      fighter =
        build(
          race: :human,
          levels: List.duplicate(:fighter, 10),
          base_abilities: %{str: 16, dex: 12, con: 14, int: 12, wis: 10, cha: 8},
          feats: %{1 => %{general: :weapon_focus}}
        )

      blind = without_dictionary(ruleset, :weapon)
      reasons = row_for(blind, fighter, 10, :weapon_focus, "weapon focus").reasons

      assert [{:choice_unrecordable, :weapon_focus, :weapon}] == reasons
      refute Enum.any?(reasons, &match?({:choice_exhausted, _, _}, &1))
      refute Enum.any?(reasons, &match?({:choice_requires, _, _, _}, &1))

      # Положительный контроль: со справочником та же строка проходит, то есть
      # причина выше — про отсутствие словаря, а не про фит.
      assert row_for(ruleset, fighter, 10, :weapon_focus, "weapon focus").reasons == []
    end

    # ⚠️ Сплошной проход, а не два фита из скриншота: домен может опустеть
    # по предусловию у любого фита с выбором, и машинный ключ в тексте — тоже
    # свойство не фита, а домена. Проверяются ОБА ruleset'а: `siala_41`
    # добавляет к ванильным девяти ещё шесть фитов с параметром.
    test "ни один фит с выбором не печатает машинный ключ", %{ruleset: _} do
      for version <- Data.versions(), {id, feat} <- Data.ruleset!(version).feats do
        ruleset = Data.ruleset!(version)
        domain = get_in(feat, [Access.key(:repeatable), Access.key(:choice)])

        if domain do
          for reason <- [
                {:choice_exhausted, id, domain},
                {:choice_requires, id, [:spell_focus], domain},
                {:choice_unrecordable, id, domain},
                {:requires_choice, id, domain},
                {:missing_data, {:choice_domain, domain}}
              ] do
            text = Feats.reason(reason, ruleset)

            refute text =~ Atom.to_string(domain),
                   "#{version}: у #{id} в тексте машинный ключ домена: #{text}"

            refute text =~ ~r/^[\{\[]/, "#{version}: #{id} печатается через inspect/1: #{text}"
          end
        end
      end
    end
  end

  describe "take_numbers/2" do
    test "счётчик — нарастающий итог по паре «фит + выбор»", %{ruleset: ruleset} do
      _ = ruleset

      taken =
        build(
          levels: List.duplicate(:fighter, 30),
          feats: %{
            21 => %{general: :epic_toughness},
            24 => %{general: :epic_toughness},
            27 => %{general: {:epic_energy_resistance, :fire}},
            30 => %{general: {:epic_energy_resistance, :cold}}
          }
        )

      assert Feats.take_numbers(taken, 21) == %{general: 1}
      assert Feats.take_numbers(taken, 24) == %{general: 2}

      # ⚠️ Ключ счёта — ПАРА, а не фит: два взятия на огонь и одно на холод —
      # это два и один, а не три (Дан, 02.08.2026).
      assert Feats.take_numbers(taken, 27) == %{general: 1}
      assert Feats.take_numbers(taken, 30) == %{general: 1}
    end

    test "два взятия на одном уровне нумеруются по порядку слотов", %{ruleset: ruleset} do
      _ = ruleset

      taken =
        build(
          levels: List.duplicate(:fighter, 21),
          feats: %{
            21 => %{:general => :epic_toughness, {:class_bonus, :fighter} => :epic_toughness}
          }
        )

      # Порядок — тот же, в каком слоты показываются везде: `Build.feat_picks/2`
      # сортирует по `inspect(slot_id)`, а `":general"` идёт раньше `"{…}"`.
      assert Feats.take_numbers(taken, 21) == %{:general => 1, {:class_bonus, :fighter} => 2}
    end
  end

  describe "список недоступных без потолка (задача 3.115)" do
    # ⚠️ До 26.08.2026 `lists/4` резала недоступные `@blocked_limit`-строкой
    # (50): нужна была защита от бесконечно длинной страницы, пока список
    # фитов рендерился прямо на ней. `.feat-lists` давно стала своей зоной
    # прокрутки ФИКСИРОВАННОЙ высоты (`assets/css/app.css`), и потолок
    # перестал что-либо защищать — только прятал 19–33 строки на эпических
    # уровнях. Dan попросил убрать (26.08.2026).
    test "воин 21 — недоступных больше полусотни, и список отдаёт их ВСЕ", %{ruleset: ruleset} do
      fighter21 = build(race: :human, levels: List.duplicate(:fighter, 21))
      lists = Feats.lists(ruleset, fighter21, 21)

      # Положительный контроль: это ДЕЙСТВИТЕЛЬНО билд, на котором прежний
      # потолок резал бы список, а не билд, где потолок просто не кусал.
      assert lists.blocked_total > 50

      # Главная проверка: длина списка равна полному числу недоступных —
      # никакого среза не осталось.
      assert length(lists.blocked) == lists.blocked_total
    end

    # 🔴 Защита `owned` — «уже есть» / «класс выдаёт здесь» не должны
    # потеряться, когда список показывается целиком. До задачи 3.115 их
    # оберегал сам потолок (`Enum.take(rest, 50) ++ owned` выносила owned за
    # пределы обрезаемой части); после — `owned_last/1` делает то же самое
    # без обрезания. Доказано поимённым сравнением, а не рассуждением:
    # все шесть «уже есть» воина 1-го уровня на месте и стоят единым
    # блоком в САМОМ КОНЦЕ списка — сорок девять «почти дотянулся» и
    # «фит не существует на этом пути» их не разбавляют.
    test "«уже есть» — единым блоком в конце списка, ничего не потеряно", %{ruleset: ruleset} do
      fighter21 = build(race: :human, levels: List.duplicate(:fighter, 21))
      lists = Feats.lists(ruleset, fighter21, 21)

      already_taken_ids =
        lists.blocked
        |> Enum.filter(&match?([{:already_taken, _} | _], &1.reasons))
        |> Enum.map(& &1.feat.id)
        |> Enum.sort()

      # Воин 21-го — «уже есть» ровно на том, что дал сам класс на 1-м уровне.
      assert already_taken_ids ==
               Enum.sort([
                 :armor_proficiency_heavy,
                 :armor_proficiency_light,
                 :armor_proficiency_medium,
                 :shield_proficiency,
                 :toughness,
                 :weapon_proficiency_simple
               ])

      tail_ids =
        lists.blocked |> Enum.take(-length(already_taken_ids)) |> Enum.map(& &1.feat.id)

      assert Enum.sort(tail_ids) == already_taken_ids
    end

    # Отрицательный контроль: поиск и раньше проходил мимо потолка реже
    # (кандидатов на запрос обычно меньше полусотни), но на широком запросе
    # он тоже резался, и после правки резаться перестал — тем же способом.
    test "поиск тоже отдаёт список целиком, без обрезания", %{ruleset: ruleset} do
      fighter21 = build(race: :human, levels: List.duplicate(:fighter, 21))
      lists = Feats.lists(ruleset, fighter21, 21, query: "a")

      assert lists.blocked_total > 50
      assert length(lists.blocked) == lists.blocked_total
    end
  end
end
