defmodule BuildCalculator.Rules.FeatHpBonusesTest do
  @moduledoc """
  Прибавки к HP от фитов — задача 1.9.

  До неё калькулятор занижал HP почти у каждого боевого билда и **молчал** об
  этом: на Сиале девять классов выдают `Toughness` даром на первом уровне
  класса, а в расчёте HP фитов не было вовсе. Оговорки тоже не было —
  `{:not_modelled, {:feat_bonus, …}}` выдаётся только фитам, которые данные
  метят `repeatable`, а `Toughness` не такой.

  Источники, по которым здесь считаются ожидания:

    * `fandom:Toughness` (revid 41265) — «one bonus hit point per character
      level», ретроактивно;
    * `fandom:Epic toughness` (revid 62913) — «20 hit points … up to a maximum
      of 200»;
    * `fandom:Hit point` (revid 62785) — пол в 1 HP за уровень считается
      **после** сложения базы с бонусами того же уровня;
    * `siala:Живучесть` (revid 16727) — восемь классов, которым фит выдаётся
      сам; девятый (Гномий защитник) — ответ Dan 01.08.2026;
    * `fandom:Deathless vigor` (revid 51633) — ступени по уровню Бледного
      мастера, форма, которую ядро сознательно НЕ считает;
    * `overrides.json` → `character.spirit_of_siala` (`source: kind: user`,
      Dan, тестовый сервер, 09.08.2026, `GAME_CHECKS.md` заход A кейс A1) —
      «Дух Сиалы», флэт +20 HP каждому персонажу на Сиале, независимо от
      уровня и класса. Задача, волна 12, 09.08.2026. Ни одна вики про эту
      механику не пишет ни строки — единственный источник игрок.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp build(levels, abilities \\ %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}) do
    Build.new(levels: levels, base_abilities: abilities)
  end

  defp feat_term(stats, feat) do
    Enum.find(stats.hp_breakdown.by_feat, &(&1.feat == feat))
  end

  describe "Toughness: один хит за уровень персонажа" do
    # Граничные уровни: первый, последний доэпический, первый эпический и кап.
    # Прибавка равна уровню персонажа ровно, а не числу уровней класса,
    # который фит выдал.
    test "на 1, 20, 21 и 41 уровне прибавка равна уровню персонажа", %{ruleset: ruleset} do
      for level <- [1, 20, 21, 41] do
        stats = Rules.compute(build(List.duplicate(:fighter, level)), ruleset)

        assert feat_term(stats, :toughness) == %{
                 feat: :toughness,
                 takes: 1,
                 subtotal: level,
                 capped?: false
               }

        # d10 без модификатора CON плюс сам фит, плюс плоские +20 «Духа
        # Сиалы» (задача, волна 12, 09.08.2026) — тот же на всех четырёх
        # уровнях, что и доказывает плоскость term'ом ниже отдельно.
        assert stats.hp == 10 * level + level + 20
        assert stats.hp_breakdown.innate.amount == 20
      end
    end

    # Обязательный кейс задачи 1.9: воин 41 уровня с CON 14 — 533, а не 492.
    # Плюс 20 от «Духа Сиалы» (задача, волна 12, 09.08.2026) — 553.
    test "воин 41 с CON 14: 553, и прибавка названа в разборе поимённо", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      levels = List.duplicate(:fighter, 41)
      abilities = %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 10}
      stats = Rules.compute(build(levels, abilities), ruleset)

      # 533 (HANDOFF, задача 1.9) + 20 от «Духа Сиалы» (задача, волна 12,
      # 09.08.2026) = 553.
      assert stats.hp == 553
      assert %{feat: :toughness, subtotal: 41} = feat_term(stats, :toughness)

      # ⚠️ Положительный контроль к «прибавка приходит из данных, а не из кода»:
      # в ванильном ruleset'е воину ни фит, ни Дух Сиалы никто не выдаёт, и
      # то же самое число остаётся прежним 492.
      assert Rules.compute(build(levels, abilities), vanilla).hp == 492
    end

    # «Hit points are gained retroactively when choosing this feat» — фит,
    # взятый на 30-м уровне, платит за все 30, а не за один.
    test "взятый поздно, платит за всю лестницу", %{vanilla: vanilla} do
      levels = List.duplicate(:wizard, 30)
      naked = Rules.compute(build(levels), vanilla)
      late = Rules.compute(Build.put_feat(build(levels), 30, :general, :toughness), vanilla)

      assert late.hp - naked.hp == 30
    end

    # Мультикласс на четыре класса — лимит Сиалы. Фит приносит один класс,
    # а платит он за все уровни персонажа, включая чужие.
    test "билд из четырёх классов: платит за все 41 уровень, а не за уровни выдавшего", %{
      ruleset: ruleset
    } do
      levels =
        List.duplicate(:fighter, 2) ++
          List.duplicate(:wizard, 20) ++
          List.duplicate(:rogue, 15) ++ List.duplicate(:cleric, 4)

      assert length(levels) == 41

      stats = Rules.compute(build(levels), ruleset)

      assert map_size(stats.class_levels) == 4
      assert %{subtotal: 41, takes: 1} = feat_term(stats, :toughness)

      # 2 × d10 + 20 × d4 + 15 × d6 + 4 × d8 = 20 + 80 + 90 + 32 = 222, плюс
      # 41 от Toughness, плюс 20 от «Духа Сиалы» — один раз на весь билд из
      # четырёх классов, не по разу на класс (задача, волна 12, 09.08.2026).
      assert stats.hp == 222 + 41 + 20
      assert stats.hp_breakdown.innate.amount == 20
    end

    # ⚠️ Ловушка двойного учёта: билд, сохранённый ДО того, как класс начал
    # выдавать фит даром, держит его ещё и в слоте. Владение — множество, так
    # что прибавка одна; иначе игрок получил бы 82 хита за один фит, а
    # калькулятор — самую незаметную из возможных ошибок (число правдоподобное).
    test "выданный классом и потраченный слот — одна прибавка, а не две", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 41)
      granted = Rules.compute(build(levels), ruleset)
      also_picked = Rules.compute(Build.put_feat(build(levels), 1, :general, :toughness), ruleset)

      assert granted.hp == also_picked.hp
      assert feat_term(also_picked, :toughness).subtotal == 41
      assert length(also_picked.hp_breakdown.by_feat) == 1
    end

    # Дельта на левелапе выводится из чистого `compute` (CLAUDE.md §5), значит
    # усечённый билд обязан отвечать за свою лестницу, а не за исходную.
    test "усечённый билд считает прибавку по своей длине", %{ruleset: ruleset} do
      whole = build(List.duplicate(:fighter, 41))

      for level <- [1, 7, 20, 41] do
        stats = Rules.compute(Build.truncate(whole, level), ruleset)
        assert %{subtotal: ^level} = feat_term(stats, :toughness)
      end
    end
  end

  describe "Epic toughness: двадцать хитов за взятие, потолок 200" do
    setup %{ruleset: ruleset} do
      %{levels: List.duplicate(:fighter, 41), ruleset: ruleset}
    end

    defp with_takes(levels, count) do
      Enum.reduce(1..count//1, build(levels), fn nth, acc ->
        Build.put_feat(acc, 20 + nth, :general, :epic_toughness)
      end)
    end

    test "взятия считаются по слотам", %{levels: levels, ruleset: ruleset} do
      for takes <- [1, 3, 10] do
        stats = Rules.compute(with_takes(levels, takes), ruleset)

        assert feat_term(stats, :epic_toughness) == %{
                 feat: :epic_toughness,
                 takes: takes,
                 subtotal: takes * 20,
                 capped?: false
               }
      end
    end

    # Потолок стоит на ЭФФЕКТЕ и приходит со страницы Fandom; потолок числа
    # взятий (10) — отдельный факт со слов Dan и лежит в другом файле. Билд,
    # собранный мимо валидации (импорт чужой ссылки), упирается в первый.
    test "одиннадцатое взятие не поднимает число выше 200", %{
      levels: levels,
      ruleset: ruleset
    } do
      ten = Rules.compute(with_takes(levels, 10), ruleset)
      eleven = Rules.compute(with_takes(levels, 11), ruleset)

      assert feat_term(ten, :epic_toughness).subtotal == 200
      refute feat_term(ten, :epic_toughness).capped?

      assert feat_term(eleven, :epic_toughness) == %{
               feat: :epic_toughness,
               takes: 11,
               subtotal: 200,
               capped?: true
             }

      assert eleven.hp == ten.hp
    end

    # Потолок эффекта работает и там, где потолка взятий нет вовсе: в ванили
    # `max_takes` не задан, и билд честно несёт про это гэп — но 220 хитов
    # он всё равно не получает.
    test "в ванили потолка взятий нет, а потолок эффекта есть", %{
      levels: levels,
      vanilla: vanilla
    } do
      stats = Rules.compute(with_takes(levels, 11), vanilla)

      assert {:missing_data, {:feat_max_takes, :epic_toughness}} in stats.gaps
      assert feat_term(stats, :epic_toughness).subtotal == 200
    end

    test "складывается с обычным Toughness, а не заменяет его", %{
      levels: levels,
      ruleset: ruleset
    } do
      stats = Rules.compute(with_takes(levels, 3), ruleset)

      assert feat_term(stats, :toughness).subtotal == 41
      assert feat_term(stats, :epic_toughness).subtotal == 60

      # + 20 от «Духа Сиалы» — третье, независимое слагаемое, а не переиме-
      # нованный Toughness/Epic toughness (задача, волна 12, 09.08.2026).
      assert stats.hp == 410 + 41 + 60 + 20
    end
  end

  describe "пол в один хит за уровень" do
    # ⚠️ Место, где наивная реализация («пол отдельно, прибавка сверху») даёт
    # ДРУГОЕ число. Источник считает пол после сложения базы с бонусами того же
    # уровня, значит d4 при модификаторе CON −4 даёт один хит за уровень и с
    # Toughness, и без него.
    test "прибавка тонет в полу там, где пол и срабатывает", %{vanilla: vanilla} do
      levels = List.duplicate(:wizard, 41)
      con_3 = %{str: 10, dex: 10, con: 3, int: 10, wis: 10, cha: 10}

      naked = Rules.compute(build(levels, con_3), vanilla)

      tough =
        Rules.compute(Build.put_feat(build(levels, con_3), 1, :general, :toughness), vanilla)

      assert naked.hp == 41
      assert tough.hp == 41

      # ⚠️ Положительный контроль: на один шаг выше по CON пол уже не
      # срабатывает, и та же прибавка даёт ровно +41. Без этой половины тест
      # зеленел бы и на реализации, которая прибавку теряет всегда.
      con_4 = %{con_3 | con: 4}
      naked_4 = Rules.compute(build(levels, con_4), vanilla)

      tough_4 =
        Rules.compute(Build.put_feat(build(levels, con_4), 1, :general, :toughness), vanilla)

      assert naked_4.hp == 41
      assert tough_4.hp == 82
    end

    # Инвариант разбора: сумма названных слагаемых равна числу ТОЧНО, включая
    # остаток пола — иначе попап показывает столбик, который не сходится.
    test "слагаемые разбора сходятся с числом на любом из проверенных билдов", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      cases = [
        {List.duplicate(:fighter, 41), %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 10}},
        {List.duplicate(:wizard, 41), %{str: 10, dex: 10, con: 3, int: 10, wis: 10, cha: 10}},
        {List.duplicate(:barbarian, 20) ++ List.duplicate(:monk, 21),
         %{str: 10, dex: 10, con: 18, int: 10, wis: 10, cha: 10}}
      ]

      for {levels, abilities} <- cases, rules <- [ruleset, vanilla] do
        stats = Rules.compute(build(levels, abilities), rules)
        b = stats.hp_breakdown

        # ⚠️ `b.innate` — четвёртое слагаемое (задача, волна 12, 09.08.2026),
        # и оно обязано войти в сумму явно: `nil` под vanilla (0), карта под
        # siala_41. Забыть его здесь значило бы вернуть ровно ту тавтологию,
        # от которой предостерегает HANDOFF — «сумма частей равна итогу» не
        # проверка, если слагаемое можно молча потерять и итог всё равно
        # сойдётся за счёт floor_adjustment.
        innate_amount = if b.innate, do: b.innate.amount, else: 0

        sum =
          Enum.sum(Enum.map(b.by_class, & &1.subtotal)) +
            b.con_term +
            Enum.sum(Enum.map(b.by_feat, & &1.subtotal)) +
            innate_amount +
            b.floor_adjustment

        assert sum == stats.hp, "#{rules.version}: разбор не сходится с числом"

        # Положительный контроль ровно к этому риску: под siala_41 сумма БЕЗ
        # `innate_amount` обязана НЕ сходиться — иначе строка выше могла бы
        # зеленеть даже с забытым слагаемым.
        if rules.version == "siala_41" do
          without_innate =
            Enum.sum(Enum.map(b.by_class, & &1.subtotal)) +
              b.con_term +
              Enum.sum(Enum.map(b.by_feat, & &1.subtotal)) +
              b.floor_adjustment

          refute without_innate == stats.hp,
                 "#{inspect(Enum.uniq(levels))}: сумма сошлась и БЕЗ Духа Сиалы — контроль вакуумный"
        end
      end
    end
  end

  describe "гэпы: ушли там, где посчитали, остались там, где не смогли" do
    # ⚠️ Тест перевёрнут 04.08.2026 задачей 3.1. До неё положительным контролем
    # тут стоял `Great strength` — «прибавку к силе ядро не считает и честно
    # говорит об этом». Теперь считает, оговорка ушла, и держать её здесь
    # значило бы требовать от ядра врать. Контроль пришлось заменить на фит,
    # эффект которого действительно не посчитан.
    test "оговорка уходит у посчитанного и остаётся у непосчитанного", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 41)

      taken =
        build(levels)
        |> Build.put_feat(21, :general, :epic_toughness)
        |> Build.put_feat(24, :general, :great_strength)
        |> Build.put_feat(27, :general, :favored_enemy)

      stats = Rules.compute(taken, ruleset)

      # Хиты `Epic toughness` считаются с задачи 1.9, сила от `Great strength`
      # — с 3.1. Оговорки нет ни у одного.
      refute {:not_modelled, {:feat_bonus, :epic_toughness}} in stats.gaps
      refute {:not_modelled, {:feat_bonus, :great_strength}} in stats.gaps

      # ⚠️ Положительный контроль: механизм оговорок не умер.
      #
      # ⚠️ **ЧЕТВЁРТАЯ замена подряд, и каждая по своей причине.** Сперва стоял
      # `Epic weapon focus` — задача 3.5 (часть B) научила ядро считать его
      # прибавку к атаке. Потом `Epic weapon specialization`, и его снесла
      # задача 3.93: его эффект — УРОН, которого калькулятор не считает вовсе.
      # Потом `Favored enemy`, и его снесла задача 3.95: прибавка падает в наше
      # число, но узка по условию, а описание фита говорит об этом лучше нас.
      #
      # 🔴 После третьей замены живого носителя не осталось НИ ОДНОГО: у всех
      # восемнадцати повторяемых фитов оговорка снята — у шестнадцати меткой
      # получателя, у двух решением владельца. Поэтому контроль перевёрнут:
      # у ruleset'а отбирается решение по ОДНОМУ фиту, и оговорка обязана
      # вернуться. Пустым он стать не может — первая строка требует, чтобы
      # запись, которую снимают, действительно была.
      assert Map.has_key?(ruleset.feat_effect_receivers, :favored_enemy)

      talkative = Map.update!(ruleset, :feat_effect_receivers, &Map.delete(&1, :favored_enemy))

      assert {:not_modelled, {:feat_bonus, :favored_enemy}} in Rules.compute(taken, talkative).gaps

      refute {:not_modelled, {:feat_bonus, :favored_enemy}} in stats.gaps
    end

    # ⚠️ Тест назывался «Deathless vigor остаётся оговоркой, и только у билда
    # с Бледным мастером» и проверял ровно обратное сегодняшнему. Замер D1
    # (13.08.2026, Dan: волшебник 5 / Бледный мастер 5 с CON 10 — 73 HP в листе,
    # у нас было 70) закрыл оговорку: ступени лежали в разметке выверенными
    # с самого начала, не хватало кода. Переписан, а не удалён — исчезнувший
    # тест не сказал бы следующему читателю, что здесь поменялось.
    test "Deathless vigor считается ступенями по уровням Бледного мастера", %{
      ruleset: ruleset
    } do
      pale =
        Rules.compute(
          build(List.duplicate(:wizard, 5) ++ List.duplicate(:pale_master, 10)),
          ruleset
        )

      # Шесть ступеней по +3 на классовых уровнях 5..10.
      assert feat_term(pale, :deathless_vigor).subtotal == 18
      refute {:not_modelled, {:feat_hp_bonus, :deathless_vigor}} in pale.gaps

      # ⚠️ Ступень, а не «за уровень»: описание самого фита («+3 hit points per
      # level») дало бы 30 вместо 18, и обе половины этой пары нужны вместе —
      # порознь «18» и «не растёт до пятого» зеленеют и при неверной формуле.
      four =
        Rules.compute(
          build(List.duplicate(:wizard, 5) ++ List.duplicate(:pale_master, 4)),
          ruleset
        )

      refute feat_term(four, :deathless_vigor)

      # ⚠️ Положительный контроль: без Бледного мастера ни терма, ни оговорки —
      # `refute` выше зеленел бы и на билде, у которого этого фита нет вовсе.
      without = Rules.compute(build(List.duplicate(:wizard, 15)), ruleset)
      refute feat_term(without, :deathless_vigor)
      refute {:not_modelled, {:feat_hp_bonus, :deathless_vigor}} in without.gaps
    end

    # ⚠️ Число из замера целиком, а не только слагаемое: игрок сверяет с листом
    # итог, и ровно этим сложением он собирается (GAME_CHECKS.md, D1).
    test "волшебник 5 / Бледный мастер 5 с CON 10 даёт 73 HP, как в листе", %{ruleset: ruleset} do
      pale = build(List.duplicate(:wizard, 5) ++ List.duplicate(:pale_master, 5))

      assert Rules.compute(pale, ruleset).hp == 73
    end

    # ⚠️ Здесь стояло «у билда с РДД называются оба: и отсутствующий хит-дайс,
    # и его причина» — обе оговорки были правдой, пока растущий дайс не был
    # выражен схемой. Задача 3.37 сняла обе: дайс есть, HP считается, и запись
    # `hit_die_increase` в разметке стала `counted_elsewhere` (считает класс,
    # а не фит). Кейс оставлен и требует ТИШИНЫ — оговорка, которая перестала
    # быть правдой, обязана исчезнуть, а не остаться висеть.
    test "у билда с РДД не осталось ни одной из двух прежних оговорок", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 30) ++ List.duplicate(:red_dragon_disciple, 10)),
          ruleset
        )

      # Воин 30 × d10 = 300, РДД 10 = 6+6+6+8+8+10+10+10+10+10 = 84,
      # телосложение 12 (+2 на 7-м уровне РДД) → мод +1 × 40 = 40,
      # Toughness воина +40, «Дух Сиалы» +20.
      assert stats.hp == 300 + 84 + 40 + 40 + 20
      refute stats.hp_breakdown == nil

      refute {:missing_data, {:hit_die, :red_dragon_disciple}} in stats.gaps
      refute {:not_modelled, {:feat_hp_bonus, :hit_die_increase}} in stats.gaps
    end
  end

  # ⚠️ Проверка того, что число живёт в данных, а не в коде: подменяем величину
  # в копии `priv/rules` и требуем, чтобы изменился расчёт. Пара «ваниль vs
  # Сиала» выше доказывает, что из данных приходит ВЫДАЧА фита; это — что
  # оттуда же приходит его ВЕЛИЧИНА.
  test "величина прибавки читается из разметки, а не зашита в ядро" do
    root = rules_copy()
    path = Path.join([root, "vanilla", "feat_hp_bonuses.json"])
    markup = path |> File.read!() |> Jason.decode!()

    doubled =
      update_in(markup["bonuses"], fn entries ->
        Enum.map(entries, fn
          %{"feat" => "toughness"} = entry -> put_in(entry, ["amount", "hp"], 2)
          entry -> entry
        end)
      end)

    File.write!(path, Jason.encode!(doubled))

    ruleset = Loader.load!(root)["siala_41"]
    stats = Rules.compute(build(List.duplicate(:fighter, 41)), ruleset)

    assert feat_term(stats, :toughness).subtotal == 82

    # + 20 от «Духа Сиалы» — читается независимо, из overrides.json, а не из
    # этого файла разметки, и правка одного не задевает другое.
    assert stats.hp == 410 + 82 + 20
  end

  # Полная копия `priv/rules`, чтобы `load!/1` видел всё как обычно и отличался
  # только испорченный файл.
  defp rules_copy do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  # ⚠️ Задача 3.25: у HP-разметки появились виды источника кроме `feat`, и они
  # ЖИВЫЕ, а не украшение схемы. Проверяется единственным способом, каким это
  # можно проверить без выдуманного игрового факта: синтетическим ruleset'ом.
  # Ни одна настоящая запись файла не приходит от расы (это вывод сплошной
  # разведки, `_sweep`), поэтому тест берёт склонность, которая У РАСЫ ЕСТЬ
  # (`Small stature` у Гоблина и Карлика), и объявляет ей прибавку к HP в копии
  # данных. Никакого утверждения про игру здесь нет: величина выдумана нами,
  # и живёт она в копии, а не в `priv/rules`.
  test "вид источника race_feat у HP-записи держится расой, а не владением фитом" do
    root = rules_copy()
    path = Path.join([root, "vanilla", "feat_hp_bonuses.json"])

    added = %{
      "race_feat" => "small_stature",
      "verdict" => "applied",
      "amount" => %{"kind" => "per_character_level", "hp" => 1},
      "effect_coverage" => "hp_only",
      "quote" => "синтетическая запись теста, не факт об игре",
      "status" => "unclear",
      "source" => %{"wiki" => "fandom", "page" => "Small stature", "revid" => 65303}
    }

    markup = path |> File.read!() |> Jason.decode!()
    File.write!(path, Jason.encode!(update_in(markup["bonuses"], &[added | &1])))

    ruleset = Loader.load!(root)["siala_41"]

    goblin =
      Build.new(
        levels: List.duplicate(:rogue, 10),
        race: :halfling,
        base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
      )

    human = %{goblin | race: :human}

    # Гоблин (= Halfling) склонность имеет — прибавка есть и названа поимённо.
    assert %{feat: :small_stature, subtotal: 10} =
             feat_term(Rules.compute(goblin, ruleset), :small_stature)

    # ⚠️ Половина, без которой первая ничего не доказывает: у человека
    # склонности нет, и прибавки тоже. Гейт остался гейтом.
    refute feat_term(Rules.compute(human, ruleset), :small_stature)

    # И третья: фитом персонаж этой склонностью НЕ владеет — то есть прибавку
    # принесла раса, а не расширенный `feats_owned/3`.
    refute MapSet.member?(Build.feats_owned(goblin, ruleset, 10), :small_stature)
  end

  describe "Дух Сиалы: +20 плоско и единоразово, у КАЖДОГО персонажа (задача, волна 12, 09.08.2026)" do
    # Три замера Dan на тестовом сервере, 09.08.2026 (GAME_CHECKS.md заход A,
    # кейс A1) — прямая сверка с игрой, а не производная проверка. Сходятся
    # точно, без остатка: ни на волшебнике, ни на воине не остаётся ни
    # одного непонятного очка.
    #
    # ⚠️ Источник — `source: kind: user`: ни одна из двух вики механику не
    # упоминает вовсе (проверено: точной фразы «Дух Сиалы» нет ни в одном из
    # 282 файлов priv/wiki_cache/siala/, ни среди 66 разобранных сиальских
    # фитов generated/feats.json; положительный контроль тем же способом —
    # «Живучесть»/Toughness находится в 5 файлах сразу).
    test "воин 1 → 31, волшебник 1 → 24, волшебник 1 с Toughness → 25", %{ruleset: ruleset} do
      fighter1 = build([:fighter])
      assert Rules.compute(fighter1, ruleset).hp == 31

      wizard1 = build([:wizard])
      assert Rules.compute(wizard1, ruleset).hp == 24

      wizard1_tough = Build.put_feat(wizard1, 1, :general, :toughness)
      assert Rules.compute(wizard1_tough, ruleset).hp == 25
    end

    # Плоскость: не за уровень (иначе воин 41 читал бы 10×41 дайсов + 20×41
    # Духа Сиалы вместо +20 один раз) и не за класс (иначе мультикласс из
    # четырёх классов читал бы +80 вместо +20).
    test "величина не растёт ни с уровнем персонажа, ни с числом классов в билде", %{
      ruleset: ruleset
    } do
      for level <- [1, 20, 41] do
        stats = Rules.compute(build(List.duplicate(:fighter, level)), ruleset)

        assert stats.hp_breakdown.innate == %{id: :spirit_of_siala, ru: "Дух Сиалы", amount: 20},
               "уровень #{level}"
      end

      four_classes =
        build(
          List.duplicate(:fighter, 2) ++
            List.duplicate(:wizard, 20) ++
            List.duplicate(:rogue, 15) ++ List.duplicate(:cleric, 4)
        )

      assert Rules.compute(four_classes, ruleset).hp_breakdown.innate.amount == 20
    end

    # Сиальский слой не должен утекать в ванильный ruleset ни при каких
    # условиях — фит сиальский, страницы у него нет ни на одной вики.
    test "ванильный ruleset не тронут", %{vanilla: vanilla} do
      # Ванильный воин никогда не получал Toughness даром (это сиальская
      # выдача, siala_41/classes.json — не задевается этой задачей) —
      # 10 хит-дайса, без фита, без Духа Сиалы, ровно как и до этой задачи.
      stats = Rules.compute(build([:fighter]), vanilla)

      assert stats.hp == 10
      assert stats.hp_breakdown.innate == nil
      assert vanilla.innate_hp_bonus == nil
    end

    # Разбор: два терма, а не один задвоенный, и их имена доступны отдельно
    # от суммы — ровно то, что просит панель итогов (`Summary.hp_terms/2`).
    test "разбор называет «Дух Сиалы» и Toughness раздельными термами", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter]), ruleset)

      assert stats.hp_breakdown.innate == %{id: :spirit_of_siala, ru: "Дух Сиалы", amount: 20}

      assert feat_term(stats, :toughness) == %{
               feat: :toughness,
               takes: 1,
               subtotal: 1,
               capped?: false
             }

      # ⚠️ `innate` — НЕ элемент `by_feat`: списка длины 2 здесь быть не может,
      # это два РАЗНЫХ поля разбора, а не одна коллекция.
      assert length(stats.hp_breakdown.by_feat) == 1
      refute Enum.any?(stats.hp_breakdown.by_feat, &(&1.feat == :spirit_of_siala))
    end
  end
end
