defmodule BuildCalculator.Data.SialaFeatRepeatableTest do
  @moduledoc """
  `priv/rules/siala_41/feats.json` — ручной слой повторяемости фитов с выбором.

  Восемь фитов, которые в игре берутся несколько раз с параметром. Ни Fandom, ни
  вики Сиалы про повторное взятие семи из них не говорят ничего: на Fandom у них
  только `repeatable_raw`, то есть цитата описания эффекта, из которой машина
  ничего не вывела. Ответы дал Дан 02.08.2026, и это единственный источник —
  значит проверять надо не «совпало ли с вики», а **дошло ли записанное до
  ruleset'а**. Файл, который лежит и не читается, хуже отсутствующего.

  Второе, что здесь проверяется, — что разные по надёжности виды факта не
  слиплись в один. У самого правила повторяемости их три: значение с Fandom,
  которое игрок подтвердил; наблюдение игрока; догадка игрока. У потолка взятий
  — тоже три, и они ДРУГИЕ: страница называет число прямо; число назвал игрок;
  число получено пересчётом перечисленных на странице ступеней. Всё это доезжает
  до расчёта одинаково, но выглядеть в данных обязано по-разному, иначе через
  полгода их не отличить.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatChoices}

  @manual_file "siala_41/feats.json"

  # Дословно то, что записано в файле: {домен выбора, distinct, статус факта}.
  # Таблица продублирована здесь намеренно — тест, который читает ожидания из
  # проверяемого файла, зеленеет и на пустом файле.
  @recorded %{
    arcane_defense: {:spell_school, true, "verified"},
    epic_energy_resistance: {:energy_type, false, "verified"},
    epic_skill_focus: {:skill, true, "verified"},
    epic_spell_focus: {:spell_school, true, "verified"},
    # Единственный без выбора: домена нет, различаться нечему, взятия просто
    # считаются. `distinct` у такой записи — `nil`, а не `false`: вопроса
    # не существует, и ответ «нет» был бы утверждением, которого никто не делал.
    epic_toughness: {nil, nil, "verified"},
    epic_weapon_focus: {:weapon, true, "verified"},
    epic_weapon_specialization: {:weapon, true, "verified"},
    favored_enemy: {:creature_type, true, "verified"},
    resist_energy: {:energy_type, true, "verified"},
    # ⚠️ Заведён ради того, чтобы СНЯТЬ допущение, а не добавить механику.
    # Без явного `distinct` загрузчик подставлял `true` сам и вешал
    # `{:assumed, :repeatable_choices_must_differ}` на весь ruleset — из-за
    # одной этой записи. Статус `derived`, а не `verified`: прямой фразы
    # «оружие должно быть разным» на странице нет, вывод сделан из соседних
    # фактов («additional weapons», `distinct` у `weapon_focus`).
    weapon_of_choice: {:weapon, true, "derived"}
  }

  # Потолки взятий. Страницы почти везде пишут предел в единицах ЭФФЕКТА
  # («to a maximum of 200 hit points», «+10», «50% concealment»), а эффект фита
  # ядро не моделирует вовсе — значит число взятий из него не выводится, и его
  # назвал игрок. ⚠️ У `epic_energy_resistance` потолок НА ПАРУ {фит, тип урона}:
  # десять раз против огня и ещё десять против молнии — законно.
  @ceilings_from_dan %{
    epic_toughness: 10,
    epic_energy_resistance: 10,
    great_strength: 10,
    great_dexterity: 10,
    great_constitution: 10,
    great_intelligence: 10,
    great_wisdom: 10,
    great_charisma: 10,
    self_concealment: 5,
    improved_sneak_attack: 10,
    improved_spell_resistance: 10,
    improved_stunning_fist: 10
  }

  # ⚠️ Эти две страница называет во ВЗЯТИЯХ, а не в эффекте, — значит это
  # перенос с вики, а не факт от игрока, и провенанс обязан их различать.
  # Лежат в ручном слое только потому, что парсер `max_takes` пока не извлекает;
  # когда научится, записи надо снять, а не оставить тенью поверх машинной.
  @ceilings_from_wiki %{great_smiting: 10, epic_damage_reduction: 3}

  # ⚠️ Третий провенанс, и он не сводится ни к одному из двух выше. Числа 3 на
  # странице нет вообще: там перечислены три ИМЕНОВАННЫЕ ступени
  # (`Automatic quicken spell I / II / III`), и потолок — их количество.
  # Открывший страницу за числом его там не найдёт — значит это не «страница
  # называет»; но считать умеет кто угодно, а слова игрока перепроверить нечем —
  # значит это и не «со слов игрока». Отсюда `status: "derived"`, и он —
  # единственное место, где разница записана машинно, а не прозой примечания.
  @ceilings_from_counting %{
    automatic_quicken_spell: 3,
    automatic_silent_spell: 3,
    automatic_still_spell: 3
  }

  @ceilings_stated Map.merge(@ceilings_from_dan, @ceilings_from_wiki)
  @ceilings Map.merge(@ceilings_stated, @ceilings_from_counting)

  # Догадка Дана и его же результат поиска в интернете. Ни то, ни другое не
  # наблюдение в игре, и ядро обязано говорить об этом у билда, который такой
  # фит взял.
  # ⚠️ ПУСТ С 25.08.2026, и это не забывчивость. Здесь стояли
  # `[:epic_weapon_specialization, :resist_energy]` — последние два `unclear`
  # в семействе; оба закрыты замерами Dan (`GAME_CHECKS.md`, заход `AA`), оба
  # подтвердили модель и подняли статус до `verified`, не сдвинув ни одного
  # значения. Догадок в слое повторяемости больше нет ни одной.
  #
  # 🔴 Список оставлен пустым, а не удалён вместе с тестом: механизм «применённая
  # догадка обязана дать оговорку» живой, и первая же новая запись со `status:
  # "unclear"` обязана его разбудить. Сам механизм проверяется СИНТЕТИКОЙ ниже —
  # урок 3.93/3.95: контроль на живой записи назавтра получает подтверждение
  # и молча перестаёт что-либо проверять. За неделю так сгорело пять подряд.
  @guessed []

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  describe "файл читается и говорит то, что записано" do
    test "он в списке источников загрузчика" do
      assert @manual_file in Loader.source_files()
    end

    test "каждый факт доехал до записи фита", %{siala: s} do
      for {id, _expected} <- @recorded do
        assert repeatable_change(s, id),
               "у #{id} нет факта what: \"repeatable\" — ручной слой до него не дошёл"
      end
    end

    # Ровно то, ради чего эти записи заводились: их нельзя перепроверить по
    # источнику, поэтому в данных обязано быть видно, чьи они и когда сняты.
    test "все восемь помечены как слова игрока, а не как страница вики", %{siala: s} do
      for {id, _expected} <- @recorded do
        source = repeatable_change(s, id)["source"]

        assert source["kind"] == "user", "#{id}: провенанс не user"
        assert source["who"] == "Dan"

        # ⚠️ Две даты, а не одна, с 25.08.2026: семь записей сняты разговором
        # 02.08.2026, а `resist_energy` и `epic_weapon_specialization` получили
        # свою дату вместе с замером (заход `AA`). Провенанс ЗНАЧЕНИЯ у них
        # не сменился — сменился провенанс УВЕРЕННОСТИ, и дата идёт за ней.
        assert source["date"] in ["2026-08-02", "2026-08-25"],
               "#{id}: дата не из известных"
      end
    end

    test "статус каждого факта — тот, что записан", %{siala: s} do
      for {id, {_domain, _distinct, status}} <- @recorded do
        assert repeatable_change(s, id)["status"] == status, "#{id}: не тот статус"
      end
    end

    # `epic_weapon_specialization` — догадка Дана, `resist_energy` — результат
    # его поиска в интернете. Оба unclear, но неуверенны по-разному, и примечание
    # обязано это объяснять, а не просто стоять непустым.
    test "у неуверенных фактов сказано, чем именно они неуверенны", %{siala: s} do
      assert repeatable_change(s, :epic_weapon_specialization)["note"] =~ "предполагаю"
      assert repeatable_change(s, :resist_energy)["note"] =~ "погуглил"
    end

    test "цитаты нет ни у одного, и это законно — цитировать нечего", %{siala: s} do
      for {id, _expected} <- @recorded do
        assert repeatable_change(s, id)["quote"] == nil
      end
    end

    # Потолок обязан доехать до ruleset'а, а не остаться строкой в файле:
    # без него ядро отвечает `{:missing_data, {:feat_max_takes, id}}`, то есть
    # честно говорит «не знаю», — и билд с десятым `Epic toughness` выглядел бы
    # так же, как билд с тридцатым.
    test "потолки взятий доехали до ядра", %{siala: s} do
      for {id, expected} <- @ceilings do
        assert s.feats[id].repeatable.max_takes.value == expected, "#{id}: не тот потолок"
      end

      # Статус потолка — это способ, каким число получено, и он обязан отличать
      # чтение от счёта: `verified` там, где число НАЗВАНО (страницей или
      # игроком), `derived` там, где его пришлось получить самим.
      for {id, _value} <- @ceilings_stated do
        assert s.feats[id].repeatable.max_takes.status == "verified", "#{id}: потолок не назван"
      end

      for {id, _value} <- @ceilings_from_counting do
        assert s.feats[id].repeatable.max_takes.status == "derived", "#{id}: потолок не выведен"
      end

      # ⚠️ Не через `ruleset.gaps`: гэп про потолок билд-скоупный, и проверка
      # по ruleset'у зеленела бы, даже если бы потолка не было вовсе. Спрашиваем
      # то, что спросит конструктор, — про билд, который фит взял.
      for {id, class} <-
            [epic_toughness: :fighter] ++
              Enum.map(Map.keys(@ceilings_from_counting), &{&1, :sorcerer}) do
        stats =
          class
          |> List.duplicate(41)
          |> then(&Build.new(levels: &1))
          |> Build.put_feat(21, :general, id)
          |> Rules.compute(s)

        # ⚠️ Положительный контроль, без которого `refute` ниже ничего не стоит:
        # он зеленеет и на билде, который фит вовсе не взял, и на пустом списке
        # гэпов. У `Epic toughness` доказательством служит само число: прибавка
        # посчитана и стоит именем в разборе HP.
        #
        # ⚠️ **У трёх `Automatic *_spell` контроль сменился 25.08.2026 (задача
        # 3.93), и это уже ЧЕТВЁРТАЯ такая замена в проекте.** Здесь стояло
        # «эффект по-прежнему не посчитан, и оговорка `{:not_modelled,
        # {:feat_bonus, id}}` на месте» — оговорка снята: эффект этих фитов
        # целиком метамагия, а её конструктор не считает и не собирался
        # (решение Dan 22.08.2026, задача 3.80). Держать прежний контроль
        # значило бы требовать от ядра говорить про дырку в ответе, которого
        # мы не даём.
        #
        # ⚠️ Новый контроль СИЛЬНЕЕ старого и отвечает ровно на заголовок теста:
        # взяв фит `max` раз, следующее взятие ядро обязано отказать числом
        # из данных. Билд у такого фита сегодня не несёт вообще ни одного гэпа
        # (проверено прогоном), так что оговорка контролем быть перестала.
        if id == :epic_toughness do
          assert Enum.any?(stats.hp_breakdown.by_feat, &(&1.feat == id)),
                 "#{id}: взятие не доехало до расчёта HP вовсе"

          refute {:not_modelled, {:feat_bonus, id}} in stats.gaps,
                 "#{id}: прибавка посчитана, а билд всё ещё говорит, что нет"
        end

        max = s.feats[id].repeatable.max_takes.value
        at_ceiling = takes(class, id, max)
        below = takes(class, id, max - 1)

        assert {:max_takes, id, max} in FeatChoices.reasons(at_ceiling, %{feat: id}, s),
               "#{id}: взятий уже #{max}, а ядро пускает ещё одно"

        refute {:max_takes, id, max} in FeatChoices.reasons(below, %{feat: id}, s),
               "#{id}: взятий #{max - 1}, а ядро уже отказывает — контроль вакуумный"

        refute {:missing_data, {:feat_max_takes, id}} in stats.gaps,
               "#{id}: потолок известен, а билд всё ещё говорит, что нет"
      end
    end

    # Билд, взявший `feat` ровно `count` раз, по одному слоту на эпический
    # уровень. Слоты здесь не проверяются — вопрос теста в том, считает ли ядро
    # ВЗЯТИЯ, а не в том, откуда они взялись.
    defp takes(class, feat, count) do
      levels = List.duplicate(class, 41)

      Enum.reduce(1..count//1, Build.new(levels: levels), fn n, build ->
        Build.put_feat(build, 20 + n, :general, feat)
      end)
    end

    # Таблица теста дублирует файл, значит она обязана покрывать его целиком:
    # девятая запись, добавленная без строки здесь, иначе просто не проверялась
    # бы — и это было бы незаметно.
    # ⚠️ Отрицательный результат разведки — такой же факт, как положительный, и
    # обязан лежать в файле: без него следующий человек увидит на странице билда
    # «27 / 30 / 33», решит, что у ступеней разные пороги Spellcraft, и пойдёт
    # искать заново. В ядро он НЕ едет и не должен — применять нечего,
    # требование одно на весь фит и уже разобрано машинно.
    test "у трёх automatic *_spell записано, что пороги по ступеням искали и не нашли", %{
      siala: s,
      vanilla: v
    } do
      for id <- Map.keys(@ceilings_from_counting) do
        entry = Enum.find(file_entries(), &(&1["id"] == Atom.to_string(id)))
        searched = entry["per_step_requirements"]

        assert searched["value"] == nil, "#{id}: у отрицательного результата появилось значение"
        assert searched["searched_on"] == "2026-08-02"
        assert searched["source"]["kind"] == "user"
        assert searched["source"]["who"] == "Dan"

        # Решающая улика, без которой запись была бы просто мнением: те же три
        # ступени у «Шамана Друида» стоят на 28/32/36, а Spellcraft у него один
        # и равен 30 — значит 27/30/33 со страниц билдов это уровни персонажа,
        # а не пороги навыка, потому что порога, дающего оба ряда, не бывает.
        assert searched["note"] =~ "28/32/36", "#{id}: в записи нет того, чем вопрос закрыт"

        # И главное: разведка ничего не изменила в требованиях. Они машинные,
        # верны и обязаны совпадать с ванильными до буквы.
        assert s.feats[id].prereqs == v.feats[id].prereqs, "#{id}: в требования всё-таки залезли"
      end
    end

    # ⚠️ Сторож обязан оставаться ПОЛНЫМ по файлу, а не по теме: если сузить его
    # до записей с `what: "repeatable"`, любая запись другого рода уедет в файл
    # непокрытой. Поэтому у него два списка, и второй — с адресом теста, который
    # запись реально проверяет.
    #
    # Волна 13 (09.08.2026) завела в файл вторую и третью темы: снятие запрета по
    # классу (`brew_potion`) и выключение ванильных владений оружием (восемь
    # `weapon_proficiency_*`), плюс запись `lingering_song` вообще без `changes` —
    # зафиксированное решение НЕ править. Все они живут в
    # `siala_feat_layer_test.exs`, потому что там же лежит `Devastating critical`
    # — тот же механизм `what: "disabled"`.
    # ⚠️ 27.08.2026 (задача 3.130): `Devastating critical` тоже получил запись
    # в ЭТОМ ручном файле, а не только в машинном — не второе прочтение факта,
    # а машинное ПОДТВЕРЖДЕНИЕ уже применённого (`source.kind: "hak"`,
    # сверка с `feat.2da`), идемпотентно повторяющее то же `disabled: true`.
    # Проверяется там же, в `siala_feat_layer_test.exs`, вместе со своим
    # машинным близнецом.
    #
    # Волна 14 (09.08.2026) — четвёртая тема: `what: "level_up_selectable"` со
    # значением `false` у `riding_sprint` и `smile_of_death` («Умение нельзя
    # выбрать при росте персонажа»). Проверяются в
    # `test/build_calculator/rules/gear_feats_test.exs`, где уже лежит вся
    # механика «фит приходит с вещи», — это ровно та же тема с другой стороны.
    # Волна 15 (14.08.2026) — пятая тема: `what: "requirement_class_level"`
    # у `improved_evasion`, перенос уровня, с которого фит можно КУПИТЬ слотом
    # («Улучшенное уклонение может взять вор, начиная с 35-го уровня»). Живёт
    # в `siala_feat_layer_test.exs` рядом с двумя соседними предложениями той же
    # страницы, которые применены как выдача, — только вместе они и показывают,
    # что выдача и право купить не одно и то же.
    # Волна задачи 3.103 (25.08.2026) — шестая тема: `what: "requirements"`
    # у `artist`, перевод требования к НАВЫКУ в требование к составу билда
    # («Артистизм (Perform)» → «в билде есть уровень барда»). Живёт
    # в `siala_feat_layer_test.exs` рядом с ванильным близнецом: без записи
    # здесь ванильная правка до `siala_41` не доезжала вовсе — блок «Требования»
    # шардовой страницы замещает `prereqs` целиком.
    # Волна задачи 3.106 (25.08.2026) — седьмая тема: `what:
    # "feat_variant_exists"` у `skill_focus`, СУЩЕСТВОВАНИЕ варианта фита,
    # которого ванильная страница не знает вовсе («There is no skill focus
    # in ride», а шард навык оживил — замер `GAME_CHECKS.md` AB1). Живёт
    # в `siala_feat_layer_test.exs` рядом с механизмом и его сторожами.
    # ⚠️ `epic_skill_focus` в этот список НЕ переехал и не должен — но уже
    # по ДРУГОЙ причине, чем 25.08.2026. Здесь стояло «у него в файле
    # по-прежнему ровно факт повторяемости, а ванильный запрет на `ride`
    # с его собственной страницы остаётся в силе»: замер AB2 (26.08.2026,
    # задача 3.108) снял и его, и вторая тема седьмого рода лежит теперь
    # у этой же записи. Список исключений про ПОВТОРЯЕМОСТЬ, а её факт
    # у `epic_skill_focus` на месте и проверяется здесь; соседний факт
    # проверяет `feat_requirements_test.exs` — «каждый из двух фитов снят
    # СВОЕЙ записью».
    @covered_elsewhere ~w(
      artist
      brew_potion devastating_critical lingering_song
      improved_evasion
      riding_sprint skill_focus smile_of_death
      weapon_proficiency_martial weapon_proficiency_simple
      weapon_proficiency_exotic weapon_proficiency_elf
      weapon_proficiency_monk weapon_proficiency_druid
      weapon_proficiency_rogue weapon_proficiency_wizard
    )

    test "в файле нет записи, которой нет в таблице теста" do
      entries = file_entries()

      known =
        @recorded
        |> Map.keys()
        |> Kernel.++(Map.keys(@ceilings))
        |> Enum.uniq()
        |> Enum.map(&Atom.to_string/1)
        |> Kernel.++(@covered_elsewhere)
        |> Enum.sort()

      assert entries |> Enum.map(& &1["id"]) |> Enum.sort() == known
    end

    # И обратная половина того же сторожа: запись из `@covered_elsewhere` не
    # должна тихо приобрести факт повторяемости — иначе он не будет проверен
    # ни здесь (id в списке исключений), ни там (тот файл про повторяемость
    # не знает).
    test "запись, покрытая другим тестом, не несёт факта повторяемости" do
      for entry <- file_entries(), entry["id"] in @covered_elsewhere do
        whats = for change <- entry["changes"] || [], do: change["what"]

        refute "repeatable" in whats,
               "#{entry["id"]}: появился факт повторяемости — заведи его в @recorded/@ceilings"
      end
    end

    # У `epic_energy_resistance` есть страница на вики Сиалы, и ссылка на неё с
    # revid — единственный способ проверить машинную половину записи. Ручной слой
    # не должен её затирать: `merge_feat_entry` берёт `siala_source` с уровня
    # записи, поэтому у записей этого файла его нет вовсе.
    test "ссылка на страницу вики Сиалы не затёрта пользовательским фактом", %{siala: s} do
      source = s.feats[:epic_energy_resistance].siala_source

      assert source["wiki"] == "siala"
      assert source["revid"]
    end

    test "ваниль не тронута", %{vanilla: v} do
      assert v.feats[:epic_spell_focus].repeatable == nil
      assert v.feats[:epic_skill_focus].repeatable == nil
      assert v.feats[:arcane_defense].repeatable == nil
      assert v.feats[:resist_energy].repeatable == nil
      refute v.feats[:favored_enemy].repeatable.distinct_stated?
    end
  end

  describe "ручной слой применён к ruleset'у" do
    test "у каждого фита стоит записанный домен и записанное distinct", %{siala: s} do
      for {id, {domain, distinct, _status}} <- @recorded do
        block = s.feats[id].repeatable

        assert is_map(block), "#{id}: фит остался неповторяемым"
        assert block.choice == domain, "#{id}: не тот домен"
        assert block.distinct? == distinct, "#{id}: не то distinct"
      end
    end

    # Смысл того, что distinct проставлен явно у всех восьми: без него загрузчик
    # подставляет true сам и вешает на ruleset допущение. Ответ есть — значит
    # допущения быть не должно.
    # `epic_toughness` исключён не ради зелени: у фита нет домена, различаться
    # нечему, и `distinct` там `nil` — вопрос не задан, а не оставлен без ответа.
    # Требовать от него «явно указан» значило бы требовать ответа на несуществующий
    # вопрос, а допущение на ruleset он и так не вешает (проверено ниже).
    test "distinct нигде не остался допущением", %{siala: s} do
      for {id, {domain, _distinct, _status}} <- @recorded, not is_nil(domain) do
        assert s.feats[id].repeatable.distinct_stated?, "#{id}: distinct читается как допущение"
      end

      assert s.feats[:epic_toughness].repeatable.distinct? == nil
    end

    test "ни один факт файла не остался неприменённым", %{siala: s} do
      for {id, _expected} <- @recorded do
        refute "repeatable" in Enum.map(s.feats[id].siala_unapplied, & &1["what"]),
               "#{id}: факт уехал в siala_unapplied"
      end
    end

    # Догадка доезжает до расчёта наравне с наблюдением — и обязана быть от него
    # отличима не только в JSON, но и в самом блоке, иначе ядру нечем объяснить
    # разницу.
    test "неуверенность едет вместе со значением, а не остаётся в файле", %{siala: s} do
      for {id, {_domain, _distinct, status}} <- @recorded do
        assert s.feats[id].repeatable.status == status, "#{id}: статус не доехал до блока"
      end
    end

    # Провенанс блока — это провенанс ЗНАЧЕНИЯ, а не разговора о нём. У семи
    # фитов значение известно только со слов игрока; у `epic_energy_resistance`
    # и `epic_toughness` сама повторяемость написана на Fandom, а от игрока
    # пришёл только потолок взятий — и он живёт внутри `max_takes`, отдельно.
    # Записать в блок игрока значило бы занизить уверенность, а это такое же
    # искажение провенанса, как и завысить.
    # У `weapon_of_choice` — то же разделение, но проходит по другой линии:
    # сама повторяемость на странице написана («additional weapons of choice»),
    # а от игрока пришло только СОГЛАСИЕ с чтением. Согласие не делает факт
    # наблюдением, поэтому источник блока остаётся вики, а `derived` в статусе
    # честно говорит, что `distinct` выведен, а не прочитан.
    @from_wiki [:epic_energy_resistance, :epic_toughness, :weapon_of_choice]

    test "блок называет источник самого значения", %{siala: s} do
      for {id, _expected} <- Map.drop(@recorded, @from_wiki) do
        assert s.feats[id].repeatable.source["kind"] == "user", "#{id}: не тот источник блока"
      end

      for id <- @from_wiki do
        assert s.feats[id].repeatable.source["wiki"] == "fandom", "#{id}: не тот источник блока"
      end

      assert s.feats[:epic_energy_resistance].repeatable.source["revid"] == 41047

      # Потолок — отдельный факт со своим провенансом, и он виден в самой
      # цитате, а не в примечании рядом. Двенадцать назвал игрок; две страница
      # называет во взятиях сама, и путать их нельзя: первые перепроверить
      # нечем, вторые — открыть и прочитать.
      for {id, _value} <- @ceilings_from_dan do
        assert s.feats[id].repeatable.max_takes.quote =~ "Дан", "#{id}: потолок не от игрока"
      end

      for {id, _value} <- @ceilings_from_wiki do
        refute s.feats[id].repeatable.max_takes.quote =~ "Дан", "#{id}: потолок приписан игроку"
        assert s.feats[id].repeatable.max_takes.quote =~ "times"
      end
    end

    # Третья категория потолка. От «страница называет число» она отличается тем,
    # что числа в цитате нет — есть список, который надо пересчитать; от «число
    # назвал игрок» — тем, что цитата со страницы, а не из разговора. Обе
    # разницы проверяются здесь, потому что в примечании они бы просто стёрлись.
    test "потолок, полученный счётом, не выдаёт себя ни за прочитанный, ни за услышанный", %{
      siala: s
    } do
      for {id, value} <- @ceilings_from_counting do
        max_takes = s.feats[id].repeatable.max_takes

        # Не «со слов игрока»: цитата со страницы Fandom, а не из разговора.
        refute max_takes.quote =~ "Дан", "#{id}: пересчёт приписан игроку"

        # И не «страница называет число»: страница говорит «multiple», а сколько
        # именно — показывает списком. Так пишут обе записи @ceilings_from_wiki
        # («up to a maximum of 10 times», «up to three times»), и вот этой формы
        # тут быть не должно.
        assert max_takes.quote =~ "may be taken multiple times:"

        refute max_takes.quote =~ ~r/\b(one|two|three|four|five|ten|\d+)\s+times\b/i,
               "#{id}: число, оказывается, названо на странице — тогда это verified, а не derived"

        # Работа приложена рядом и ПРОВЕРЯЕТСЯ, а не декларируется: `from` несёт
        # то, что считали, длина списка обязана сойтись с потолком, и каждая
        # ступень обязана найтись в цитате — иначе «derived» было бы словом.
        #
        # ⚠️ Спрашивается пара «тег + нагрузка» одним матчем, а не два ключа
        # подряд: `from` раньше нёс две разные формы под одним именем, и читать
        # его ключами значило угадывать, какая пришла. Сверку длины с числом
        # теперь делает и сам загрузчик — здесь она остаётся потому, что
        # проверяет ДАННЫЕ, а не сторожа (`data_test.exs` держит сторожа).
        assert %{counted: :tiers, tiers: tiers} = max_takes.from
        assert length(tiers) == value, "#{id}: арифметика не сходится"

        for tier <- tiers do
          assert String.contains?(max_takes.quote, tier), "#{id}: ступени #{tier} нет в цитате"
        end

        # Провенанс ЗНАЧЕНИЯ — вики, а не игрок: и повторяемость, и сами ступени
        # написаны на странице Fandom, от игрока пришло только решение, как их
        # моделировать. Записать сюда user значило бы занизить проверяемость —
        # то же искажение, что и завысить.
        assert s.feats[id].repeatable.source["wiki"] == "fandom", "#{id}: не тот источник блока"
        assert s.feats[id].repeatable.source["revid"], "#{id}: блок без revid — не перепроверить"
        assert repeatable_change(s, id)["source"]["kind"] == "wiki", "#{id}: факт приписан игроку"
      end
    end

    # ⚠️ Перепись по ВСЕМУ словарю фитов, а не по таблицам выше. Таблица знает
    # только те записи, которые кто-то в неё вписал, и запись с новой формой
    # `from` проехала бы мимо неё молча — а именно так под одним именем и
    # завелись две формы. Спрашиваются оба ruleset'а: у ванильного записей
    # `max_takes` нет вовсе, и это тоже утверждение, а не отсутствие проверки.
    test "у каждого потолка форма ровно одна, и она названа тегом", %{siala: s, vanilla: v} do
      counted =
        for ruleset <- [s, v],
            {id, feat} <- ruleset.feats,
            is_map(feat.repeatable),
            max_takes = feat.repeatable.max_takes,
            is_map(max_takes),
            reduce: MapSet.new() do
          acc ->
            case max_takes.from do
              # Работы нет — значит число НАЗВАНО, и статус обязан говорить ровно
              # это. `verified` без `from` и `derived` с `from` — единственные две
              # законные комбинации, всё между ними противоречиво.
              nil ->
                assert max_takes.status == "verified",
                       "#{id}: статус #{max_takes.status} без показанной работы"

                acc

              # Тег и нагрузка спрашиваются ОДНИМ матчем: прочитать нагрузку,
              # не спросив операцию, теперь нельзя даже случайно.
              %{counted: :tiers, tiers: tiers} ->
                assert max_takes.status == "derived", "#{id}: счёт выдаётся за чтение"
                assert length(tiers) == max_takes.value, "#{id}: арифметика не сходится"
                MapSet.put(acc, id)

              other ->
                flunk(
                  "#{id}: у потолка форма #{inspect(other)}, которой не знает ни один читатель"
                )
            end
        end

      # И обратная сторона переписи: показанная работа сегодня ровно у трёх
      # записей. Появится четвёртая — таблица файла обязана узнать о ней здесь,
      # а не через полгода.
      assert counted == MapSet.new(Map.keys(@ceilings_from_counting))
    end

    # Единственная запись файла, которая ничего не меняет: Fandom и игрок
    # говорят одно и то же. Проверяется именно это — что подтверждение не
    # превратилось в правку.
    test "epic_energy_resistance подтверждён, а не изменён", %{siala: s, vanilla: v} do
      assert s.feats[:epic_energy_resistance].repeatable.choice ==
               v.feats[:epic_energy_resistance].repeatable.choice

      assert s.feats[:epic_energy_resistance].repeatable.distinct? ==
               v.feats[:epic_energy_resistance].repeatable.distinct?

      refute v.feats[:epic_energy_resistance].repeatable.distinct?
    end

    test "favored_enemy сохранил домен Fandom и перестал быть допущением", %{
      siala: s,
      vanilla: v
    } do
      assert s.feats[:favored_enemy].repeatable.choice ==
               v.feats[:favored_enemy].repeatable.choice

      refute v.feats[:favored_enemy].repeatable.distinct_stated?
      assert s.feats[:favored_enemy].repeatable.distinct_stated?
    end
  end

  describe "что из этого следует в расчёте" do
    # Сценарий Дана дословно: взяты большой фокус на Evocation и Necromancy,
    # эпический уже взят на Evocation → в выборе остаётся только Necromancy.
    # Здесь сходятся оба правила сразу: distinct убирает Evocation, а требование
    # «в той же школе» (машинное, same_choice_as) убирает все остальные школы.
    test "эпический фокус предлагает только школу, где он ещё не взят", %{siala: s} do
      build =
        caster()
        |> Build.put_feat(1, :general, :spell_focus, :evocation)
        |> Build.put_feat(3, :general, :greater_spell_focus, :evocation)
        |> Build.put_feat(6, :general, :spell_focus, :necromancy)
        |> Build.put_feat(9, :general, :greater_spell_focus, :necromancy)
        |> Build.put_feat(21, :general, :epic_spell_focus, :evocation)

      assert FeatChoices.candidates(build, %{feat: :epic_spell_focus, at: 24}, s) ==
               {:ok, [:necromancy]}
    end

    test "второй раз на ту же школу — отказ с машинной причиной", %{siala: s} do
      build = Build.put_feat(caster(), 21, :general, :epic_spell_focus, :evocation)

      assert {:choice_already_taken, :epic_spell_focus, :evocation} in FeatChoices.reasons(
               build,
               %{feat: :epic_spell_focus, choice: :evocation, at: 24},
               s
             )
    end

    test "а на другую школу повтор законен", %{siala: s} do
      build = Build.put_feat(caster(), 21, :general, :epic_spell_focus, :evocation)

      refute Enum.any?(
               FeatChoices.reasons(
                 build,
                 %{feat: :epic_spell_focus, choice: :necromancy, at: 24},
                 s
               ),
               &match?({:choice_already_taken, _, _}, &1)
             )
    end

    # Та же пара, что в данных, но уже в поведении: эпическое сопротивление
    # настакивается на один и тот же вид урона, обычное — нет. Ровно эту пару
    # проще всего склеить по ошибке, поэтому она проверяется целиком.
    test "эпическое сопротивление берётся дважды на один вид урона", %{siala: s} do
      build = Build.put_feat(caster(), 21, :general, :epic_energy_resistance, :fire)

      refute Enum.any?(
               FeatChoices.reasons(
                 build,
                 %{feat: :epic_energy_resistance, choice: :fire, at: 24},
                 s
               ),
               &match?({:choice_already_taken, _, _}, &1)
             )
    end

    test "обычное — не берётся", %{siala: s} do
      build = Build.put_feat(caster(), 9, :general, :resist_energy, :fire)

      assert {:choice_already_taken, :resist_energy, :fire} in FeatChoices.reasons(
               build,
               %{feat: :resist_energy, choice: :fire, at: 12},
               s
             )
    end

    # Применённая догадка, о которой билд молчит, — это та самая тишина, из-за
    # которой «пусто в gaps» перестаёт значить «всё посчитано» (CLAUDE.md §9).
    test "билд, взявший фит с догадкой, получает оговорку", %{siala: s} do
      for id <- @guessed do
        build = Build.put_feat(caster(), 21, :general, id, :fire)

        assert {:assumed, {:feat_repeatable, id}} in Rules.compute(build, s).gaps,
               "#{id}: догадка применена молча"
      end
    end

    # 🔴 МЕХАНИЗМ, а не носитель. `@guessed` пуст с 25.08.2026 — значит тест выше
    # сегодня не проверяет ничего, и без этого он бы молча зеленел на пустом
    # списке. Здесь `status: "unclear"` подставляется СИНТЕТИЧЕСКИ, и оговорка
    # обязана появиться независимо от того, что лежит в `priv/rules`.
    test "механизм жив: синтетический unclear даёт оговорку", %{siala: s} do
      id = :epic_energy_resistance
      guessed = put_in(s.feats[id].repeatable.status, "unclear")
      build = Build.put_feat(caster(), 21, :general, id, :fire)

      refute {:assumed, {:feat_repeatable, id}} in Rules.compute(build, s).gaps
      assert {:assumed, {:feat_repeatable, id}} in Rules.compute(build, guessed).gaps
    end

    test "а взявший подтверждённый — не получает", %{siala: s} do
      build = Build.put_feat(caster(), 21, :general, :epic_energy_resistance, :fire)

      refute {:assumed, {:feat_repeatable, :epic_energy_resistance}} in Rules.compute(
               build,
               s
             ).gaps
    end

    # ⚠️ ЗАДАЧА 3.5 поменяла ответ здесь целиком, и это буквально то, ради чего
    # её просили. Dan: «Если взял обычный фокус на условный длинный меч, то
    # сможешь взять потом эпик фокус». Раньше здесь стояло
    # `{:error, [{:missing_data, {:choice_domain, :weapon}}]}` — «домена нет,
    # значение не проверяем»; теперь `weapons.json` есть, `epic_weapon_focus`
    # повторяем на Сиале (Dan, 02.08.2026), и `same_choice_as` наконец работает.
    test "эпический фокус берётся ровно в том оружии, где взят обычный", %{siala: s} do
      assert FeatChoices.domain(:epic_weapon_focus, s) == :weapon
      assert FeatChoices.domain(:epic_weapon_specialization, s) == :weapon

      # Без обычного фокуса выбирать нечего — и причина именно эта, а не
      # «всё уже взято» (§6: два способа опустеть, две разные формулировки).
      assert FeatChoices.candidates(caster(), %{feat: :epic_weapon_focus, at: 24}, s) ==
               {:empty, [{:choice_requires, :epic_weapon_focus, [:weapon_focus], :weapon}]}

      fighter = %Build{race: :human, levels: List.duplicate(:fighter, 24)}
      took = Build.put_feat(fighter, 1, {:class_bonus, :fighter}, :weapon_focus, :longsword)

      # Ровно то оружие, и только оно.
      assert FeatChoices.candidates(took, %{feat: :epic_weapon_focus, at: 24}, s) ==
               {:ok, [:longsword]}

      assert FeatChoices.reasons(took, %{feat: :epic_weapon_focus, choice: :longsword, at: 24}, s) ==
               []

      # Положительный контроль к строке выше: другое оружие отбивается, то есть
      # пустой список отказов — заслуга совпадения, а не отсутствия проверки.
      assert {:requires_same_choice, :weapon_focus, :rapier} in FeatChoices.reasons(
               took,
               %{feat: :epic_weapon_focus, choice: :rapier, at: 24},
               s
             )
    end

    # Дан 02.08.2026 дословно: «для II нужен I и для других automatic_*_*
    # аналогично, нужен базовый, он даёт право на I, а если взял I, то можешь
    # взять II, а потом только III». В требования из этого не дописано НИЧЕГО,
    # и вот проверка, почему это законно: порядок держится самой моделью
    # счётных взятий, а не отдельным правилом.
    #
    # ⚠️ Связь неочевидна и потому проверяется явно: кто разнесёт три ступени на
    # три отдельных фита (соблазнительно — у них разные описания и разные
    # диапазоны кругов), молча потеряет гарантию порядка и обязан будет завести
    # правило взамен. Этот тест — то место, где такая правка покраснеет.
    test "порядок ступеней держит модель, а не правило", %{siala: s} do
      for id <- Map.keys(@ceilings_from_counting) do
        # Ступень нельзя даже НАЗВАТЬ: домена у фита нет, и ядро отвергает любое
        # значение выбора. Значит «взять III, не взяв I и II» — это не
        # запрещённый билд, а билд, которого нечем записать.
        assert {:invalid_choice, id, :iii} in FeatChoices.reasons(
                 caster(),
                 %{feat: id, choice: :iii, at: 21},
                 s
               )

        # Взятие — это счёт пиков одного id, поэтому «второе» определено только
        # как «после первого»: на пустом билде их ноль, и никакой пик не может
        # оказаться вторым в обход первого.
        assert Build.feat_takes(caster(), id, 41) == 0

        once = Build.put_feat(caster(), 21, :general, id)
        assert Build.feat_takes(once, id, 41) == 1
        assert FeatChoices.reasons(once, %{feat: id, at: 24}, s) == []

        # А потолок при этом настоящий: четвёртое взятие отказывается машинной
        # причиной, а не молча считается четвёртой ступенью, которой нет.
        thrice = once |> Build.put_feat(24, :general, id) |> Build.put_feat(27, :general, id)

        assert Build.feat_takes(thrice, id, 41) == 3
        assert {:max_takes, id, 3} in FeatChoices.reasons(thrice, %{feat: id, at: 30}, s)
      end
    end
  end

  defp caster, do: Build.new(levels: List.duplicate(:sorcerer, 41))

  # Файл, а не ruleset: часть записанного в него намеренно НЕ едет в ядро
  # (отрицательный результат разведки применять нечему), а сторож полноты
  # таблицы обязан видеть все записи, включая те, что ядро проигнорировало.
  defp file_entries do
    path = Path.join(Application.app_dir(:build_calculator, "priv"), "rules/#{@manual_file}")
    %{"feats" => entries} = path |> File.read!() |> Jason.decode!()
    entries
  end

  defp repeatable_change(ruleset, id) do
    ruleset.feats[id].siala_changes
    |> Enum.filter(&(&1["what"] == "repeatable"))
    |> case do
      [change] -> change
      [] -> nil
      many -> flunk("у #{id} #{length(many)} фактов repeatable, ожидался один")
    end
  end
end
