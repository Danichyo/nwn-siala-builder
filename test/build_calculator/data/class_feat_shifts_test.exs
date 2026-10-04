defmodule BuildCalculator.Data.ClassFeatShiftsTest do
  @moduledoc """
  What the shard layer does to the levels a class hands its feats out on.

  Siala reshuffles class abilities across levels, and until now three classes
  recorded that as `class_ability_levels` — a list of **ability names**, which
  the loader could not apply and honestly left as
  `{:not_modelled, {:class_change, …}}`. Rewritten as `feat_level_shift`, they
  land in `granted_feats` like every other class's.

  Expected levels are read straight off the progression tables quoted in
  `priv/rules/siala_41/classes.json`; every case names its wiki source.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatSlots}

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp granted(ruleset, class) do
    ruleset.classes[class].granted_feats
    |> Map.new(fn {level, ids} -> {level, Enum.sort(ids)} end)
  end

  describe "Harper Scout" do
    # source: wiki Сиалы «Арфист-скаут» revid 19414, таблица прогрессии.
    # The whole five-level hand-out is reshuffled; Craft Harper Item moving from
    # 5 to 1 is the build-relevant one — one level of Harper now gives what used
    # to cost five.
    # AGENT_QUEUE.md §1.10 шаг 3: уровень 1 несёт ещё и владения — свою
    # `Armor proficiency (light)`, читаемую с лейбла `Proficiencies:`
    # (Источник 2) и не задетую сдвигом уровней ниже, который трогает только
    # `class_ability_levels`.
    #
    # ⚠️ `Weapon proficiency (simple)` на 1-м уровне стоит НЕ от сдвига и даже
    # не от ванильной таблицы Арфиста: шард выдаёт этот фит на классовом уровне
    # 1 каждому из 23 классов (задача 3.112, `siala_41/feats.json` →
    # `granted_automatically_to`). Ванильная половина теста ниже даёт его тому же
    # Арфисту по своей, ванильной причине — то есть строка совпала, а основания
    # у неё разные, и путать их нельзя.
    # ⚠️ Здесь стояло «тут БЫЛА и исчезла… замер H5 выключил ванильные владения»:
    # верно для martial/exotic/elf и остальных, но не для `simple` — его прочтение
    # опровергнуто игровыми логами 26.08.2026.
    test "hands its feats out on the shard's levels", %{siala: siala} do
      assert granted(siala, :harper_scout) == %{
               1 => [
                 :armor_proficiency_light,
                 :craft_harper_item,
                 :weapon_proficiency_simple
               ],
               2 => [:bardic_knowledge, :invisibility_feat],
               3 => [:deneirs_eye, :sleep_feat],
               4 => [:cats_grace_feat, :lliiras_heart],
               5 => [:eagles_splendor_feat, :tymoras_smile]
             }
    end

    test "vanilla is untouched by the shard layer", %{vanilla: vanilla} do
      assert granted(vanilla, :harper_scout) == %{
               1 => [:armor_proficiency_light, :bardic_knowledge, :weapon_proficiency_simple],
               2 => [:deneirs_eye, :sleep_feat],
               3 => [:cats_grace_feat, :tymoras_smile],
               4 => [:eagles_splendor_feat, :lliiras_heart],
               5 => [:craft_harper_item, :invisibility_feat]
             }
    end

    # Every ability on the page matched a vanilla feat, so nothing is left over
    # and the class no longer owes a gap.
    test "no longer carries an unmodelled ability list", %{siala: siala} do
      refute {:not_modelled, {:class_change, :harper_scout, "class_ability_levels"}} in siala.gaps
    end
  end

  describe "Purple Dragon Knight" do
    # source: wiki Сиалы «Пурпурный рыцарь дракон» revid 20530 — the vanilla
    # five-level hand-out stretched over ten, everything but Rallying Cry
    # arriving twice as late.
    #
    # ⚠️ 08.08.2026 (AGENT_QUEUE.md §7, волна 10): `inspire_courage` shifts
    # TWICE — 2→3 for the first daily use, 4→8 for the second. Until the
    # vanilla parser fix (`ClassPage.feat_grants/1`, the `bone_skin` bug) the
    # second use was invisible in `vanilla/classes.json` too — the class page
    # writes it as bare `inspire courage 2/day`, no link, right after the
    # linked `[[inspire courage]] 1/day` two levels earlier, and the parser
    # only followed links. Once vanilla carried both levels, the shard's own
    # `class_ability_levels` entry for it started arguing from a premise that
    # was no longer true (it quoted vanilla level 4 as empty) and was rewritten
    # as a second `feat_level_shift` pair instead — the mechanism already moves
    # one id more than once for other classes, so this is not a new shape.
    test "hands its feats out twice as late, inspire_courage on both halves", %{siala: siala} do
      assert granted(siala, :purple_dragon_knight) == %{
               1 => [:rallying_cry, :weapon_proficiency_simple],
               3 => [:heroic_shield, :inspire_courage],
               6 => [:fear_feat],
               8 => [:inspire_courage, :oath_of_wrath],
               10 => [:final_stand]
             }
    end

    # The rank travels with each half of the grant, the same way `move_grant/4`
    # already carries it for every other shifted feat (moduledoc, `deathless
    # vigor`-style families): "1/day" lands wherever the first use went, "2/day"
    # wherever the second one did — never mixed up between the two.
    test "each use-per-day rank follows its own half of the shift", %{siala: siala} do
      pdk = siala.classes[:purple_dragon_knight]

      assert pdk.granted_feat_ranks[3] == %{inspire_courage: "1/day"}
      assert pdk.granted_feat_ranks[8][:inspire_courage] == "2/day"
    end

    # No more `class_ability_levels` gap for this class: both halves of
    # Inspire Courage are now a `feat_level_shift`, and nothing else was left
    # unmodelled under that key.
    test "the second use per day is no longer an unmodelled ability", %{siala: siala} do
      refute {:not_modelled, {:class_change, :purple_dragon_knight, "class_ability_levels"}} in siala.gaps
    end
  end

  describe "Assassin" do
    # source: wiki Сиалы «Убийца» revid 20400 — the class runs to 31 on the
    # shard and gains two abilities vanilla never had, so `from` is null.
    test "gains Keen Sense at class level 20", %{siala: siala, vanilla: vanilla} do
      assert siala.classes[:assassin].granted_feats[20] == [:keen_sense]
      refute Map.has_key?(vanilla.classes[:assassin].granted_feats, 20)
    end

    # ⚠️ «Unchanged» значит «неизменно ТЕМ, что делает слой класса», а не
    # побайтово: слой ФИТОВ трогает выдачу 1-го уровня независимо, и у Убийцы
    # это `weapon_proficiency_simple`. Утверждение теста от этого не ослабло —
    # оно ровно то же самое, только про сравнимые списки; сами эти правки
    # проверяются отдельно и по имени (`siala_feat_layer_test.exs`), поэтому
    # исключение здесь ничего не прячет.
    #
    # 🔴 Здесь стояло `@switched_off_on_siala [:weapon_proficiency_simple]` —
    # «шард его выключил, и он ушёл из выдачи». Это прочтение опровергнуто
    # 26.08.2026 (задача 3.112): фит не выключен, шард выдаёт его ВСЕМ классам,
    # и у Убийцы он на месте по обе стороны. Ванильная выдача при этом совпала
    # с сиальской случайно — основания у них разные (ванильная таблица Убийцы
    # против сиальской выдачи всем), и следующий читатель не должен принять
    # совпадение за отсутствие правки.
    @granted_to_everyone_on_siala [:weapon_proficiency_simple]

    test "the vanilla hand-out below level 10 is unchanged", %{siala: siala, vanilla: vanilla} do
      for level <- 1..10 do
        assert granted(siala, :assassin)[level] == granted(vanilla, :assassin)[level],
               "assassin class level #{level}"
      end

      # Положительный контроль: строка выше сравнивает списки, в которых
      # `simple` действительно есть, а не пустое место с пустым.
      for id <- @granted_to_everyone_on_siala do
        assert id in granted(vanilla, :assassin)[1], to_string(id)
        assert id in granted(siala, :assassin)[1], to_string(id)
      end
    end

    # "Shades" is a spell in the vanilla snapshot, not a feat; the shard links it
    # as `[[Shades (feat)|Shades]]`, i.e. a feat of its own. It used to have no
    # record here, so the ability stayed a gap rather than becoming a granted id
    # nothing could resolve — the right call at the time, and it is now moot: the
    # shard's own page («Shades (feat)» revid 18248) is parsed into the feat
    # dictionary as `shades_feat`.
    #
    # ⚠ What makes the hand-out safe to write down is that the two pages agree
    # **independently**: «Убийца» says «На 15 уровней Ассасин получает
    # способность Shades», and the feat's page says «Убийца (Assassin) 15
    # уровня». Neither number was inferred from the other.
    test "Shades is handed over on class level 15, not offered for purchase", %{siala: siala} do
      assert Map.has_key?(siala.feats, :shades_feat)
      assert :shades_feat in siala.classes[:assassin].granted_feats[15]

      # ...and the vanilla misreading it guarded against stays impossible
      refute Map.has_key?(siala.feats, :shades)
    end

    # ⚠ The counter-example is the Monk's Instinctive Throw, and it shows the rule
    # is about **independent** witnesses rather than about a number appearing
    # twice: its feat page names class level 5 too, but the class page states
    # **two** levels («Условия: Монах 5 уровня» in the heading, «Использовать
    # умение можно с 15 уровня Монаха» three lines down) and the feat page merely
    # repeats one of them. Until 09.08.2026 that was the whole of the evidence and
    # no hand-out was written. What settled it was a measurement, not a page — see
    # the Monk describe below.
  end

  describe "Monk" do
    # 🔴 ЗДЕСЬ СТОЯЛО ОБРАТНОЕ, И ЭТО БЫЛА ОШИБКА В ДАННЫХ.
    #
    # Тест назывался «Wholeness of Body arrives on class level 2» и закреплял
    # сдвиг 7 → 2 по цитате со страницы Сиалы (revid 17482, «Требования: Монах
    # (Monk) 2 уровня») — единственный перенос шарда в сторону РАНЬШЕ.
    #
    # Замер Dan 28.08.2026 (`GAME_CHECKS.md`, кейс AF1): «монк получил wholeness
    # of body на 7 уровне». Страница правда так пишет — неверным было наше
    # ПРОЧТЕНИЕ: цитата описывает не уровень выдачи. Та же форма, что у
    # `instinctive_throw` ниже, где страница называет два числа (уровень выдачи
    # и уровень применения) и мы это уже один раз проходили.
    #
    # Найдено сверкой с хаками (`cls_feat_monk.2da` row 8, `GrantedOnLevel = 7`,
    # задача 3.127) — первая ошибка в наших данных, найденная машинным источником.
    # Факт помечен `status: "refuted"` и больше не применяется.
    #
    # ⚠️ Падение этого теста было ПРАВИЛЬНЫМ: он фиксировал нашу ошибку.
    test "Wholeness of Body arrives on class level 7 — как в ванили", %{
      siala: siala,
      vanilla: vanilla
    } do
      assert :wholeness_of_body in siala.classes[:monk].granted_feats[7]

      # ⚠️ Уровень 2 у монаха существует и без этого фита (там `deflect_arrows`),
      # поэтому проверяется отсутствие ИМЕНИ, а не отсутствие уровня.
      refute :wholeness_of_body in siala.classes[:monk].granted_feats[2]
      assert vanilla.classes[:monk].granted_feats[7] == [:wholeness_of_body]
    end

    # 🔴 source: Dan, тестовый сервер Сиалы, 09.08.2026 (`GAME_CHECKS.md`, заход
    # C, кейс C1). The page contradicts itself inside one section — «Условия:
    # Монах 5 уровня» in the heading against «Использовать умение можно с 15
    # уровня Монаха» three lines down — so the wiki could not settle it at all.
    # The measurement settles **one** half: the ability is handed over on class
    # level 5.
    #
    # ⚠ Both halves of the model live in ONE test on purpose, the same reason the
    # Ranger's `dual wield` pair does (`feat_slots_test.exs`): apart, each looks
    # right under a wrong model too. "It is granted" passes on a build that also
    # lets a slot pay for it, and "no slot takes it" passes on a build that never
    # grants it — which is exactly what this repository shipped until today.
    test "granted on class level 5, and no slot may be spent on it", %{siala: siala} do
      granted = siala.classes[:monk].granted_feats

      assert :instinctive_throw in granted[5]

      # Положительный контроль к строке выше: на 4-м уровне класса умения нет,
      # иначе «выдаётся» зеленело бы и при выдаче с первого уровня.
      refute :instinctive_throw in Map.get(granted, 4, [])
      assert granted[4] == [:monk_ac_bonus]

      build = Build.new(levels: List.duplicate(:monk, 9))
      assert MapSet.member?(Build.feats_owned(build, siala, 5), :instinctive_throw)
      refute MapSet.member?(Build.feats_owned(build, siala, 4), :instinctive_throw)

      # ...и вторая половина: слот на него потратить нельзя ни на одном уровне.
      # ⚠️ Механизм тут НЕ блок-лист `@granted_not_chosen` (тот читает словарь
      # типов Fandom, а фит сиальский), а сиальская ветка `FeatSlots.general?/1`:
      # у фита шарда слот открывает только «Тип навыка: general», а у этого он
      # «Классовый». Проверяется по факту отказа, а не по механизму.
      for level <- 1..9, slot <- FeatSlots.at(build, siala, level) do
        refute FeatSlots.accepts?(siala, slot, :instinctive_throw),
               "slot #{inspect(slot.id)} on level #{level} would pay for a granted ability"
      end

      # Положительный контроль к `refute` выше: те же слоты что-то принимают,
      # то есть отказ — про этот фит, а не про сломанный вызов.
      assert Enum.any?(FeatSlots.at(build, siala, 3), &FeatSlots.accepts?(siala, &1, :toughness))
    end

    # ⚠ И то, чего замер НЕ покрыл, обязано остаться видимым. Страница говорит
    # «использовать умение можно с 15 уровня Монаха», модель порога ПРИМЕНЕНИЯ
    # не выражает вовсе, и у 26 из 27 классовых умений Сиалы такое число
    # совпадает с уровнем выдачи — это единственное исключение в корпусе.
    #
    # ⚠️ Здесь стояло `assert {:not_modelled, {:class_change, :monk,
    # "instinctive_throw_usable_from"}} in siala.gaps`. Задача 3.28 (10.08.2026)
    # это изменила: факт помечен `affects: ["special_ability"]`, то есть
    # получателем, которого калькулятор не печатает, — и в список неточностей
    # больше не идёт. Нерешённость при этом никуда не делась и осталась в данных,
    # что этот тест и проверяет; ⚠️ но на экране её теперь нет, и метка — единственное,
    # на чём это держится. Вопрос владельцу вынесен отчётом задачи: право
    # ПОЛЬЗОВАТЬСЯ умением, которое мы показываем взятым с 5-го уровня, —
    # спорный кандидат в `feat_availability`.
    test "the page's second, unresolved sentence stays in the data, with its receiver named",
         %{siala: siala} do
      fact =
        Enum.find(
          siala.classes[:monk].siala_unapplied,
          &(&1["what"] == "instinctive_throw_usable_from")
        )

      assert fact["status"] == "unclear"
      assert fact["affects"] == ["special_ability"]

      refute {:not_modelled, {:class_change, :monk, "instinctive_throw_usable_from"}} in siala.gaps

      # Положительный контроль к `refute` выше: список гэпов не пуст, то есть
      # проверка про метку, а не про то, что фильтр выкосил всё.
      #
      # ⚠️ Контроль был фактом САМОГО МОНАХА (`weapon_bab_exceptions`) и переехал
      # 13.08.2026: после второго замера по монаху (GAME_CHECKS.md, L2b) фраза
      # про «базовый бонус атаки» оказалась про Flurry of blows, Шквал —
      # активируемый, то есть бафф, и у монаха не осталось НИ ОДНОГО факта
      # с нашим получателем. Контроль тем самым ослаб честно: он больше
      # не показывает, что факт монаха в принципе способен доехать до гэпов,
      # потому что сегодня такого факта нет.
      #
      # ⚠️ И переехал ВТОРОЙ раз 17.08.2026, тем же способом: контролем стоял
      # штраф вора в режиме скрытности, а Dan объявил режим скрытности баффом
      # («если штрафы вору идут только в режиме хайда, то мы их не показываем»).
      # Взята прибавка к атаке Мастера оружия — постоянная прогрессия класса,
      # то есть под баффы уехать не может по построению, в отличие от двух
      # прежних контролей подряд.
      #
      # ⚠️ И переехал ТРЕТИЙ раз, тем же днём, но по СОВСЕМ другой причине —
      # не «стал баффом», а «оказался посчитанным в другом месте»: замер Dan
      # показал, что прибавка Мастера оружия — ванильная колонка
      # `feat_attack_bonuses.json`, а не сиальское изменение, и обе записи ВМ
      # слиты в одну с получателем `counted_elsewhere`. Взято требование
      # к предмету у Гномьего защитника — оно не про временный эффект и не
      # про число, посчитанное где-то ещё, поэтому третий раз подряд уезжать
      # ему уже не от чего.
      # 🔴 И уехал ЧЕТВЁРТЫЙ раз, 21.08.2026 (задача 3.75) — при том что абзац
      # выше уверял, будто «уезжать ему уже не от чего». Причина снова новая:
      # решение Dan, что предмет групповой стойки юзабельный, слота щита
      # не занимает и надеть его нельзя, — то есть требование до нашего ответа
      # не доезжает ничем, и две половины одной механики (сама стойка и её
      # требование) наконец помечены согласованно.
      #
      # ⚠️ Урок теста, а не данных: контроль, выбранный по признаку «этот
      # уж точно останется», четырежды подряд оказывался неверным.
      #
      # 🔴 И ПЯТЫЙ раз, 24.08.2026 (задача 3.85) — при том что предыдущая
      # правка выбрала контроль как раз по признаку «уехать может только
      # вместе с ответом владельца»: взяли Рейнджера, потому что он ждал
      # замера U2. Ответ пришёл, замер показал, что модель верна, а гэп ложен
      # (правило приезжает со страниц фитов), и запись применили. То есть
      # признак «ждёт замера» защищает ничуть не лучше остальных четырёх.
      #
      # ✅ Поэтому контроль больше НЕ реальный факт, а синтетика того же класса:
      # у монаха в `siala_unapplied` появляется факт без метки получателя,
      # и он обязан доехать до гэпов билда. Такой контроль нельзя «починить»
      # правкой данных — он проверяет механизм, а не состояние `priv/`,
      # и именно это отличает его от пяти предыдущих.
      probe = %{"what" => "проверочный факт без получателя"}
      probed = put_in(siala, [:classes, :monk, :siala_unapplied], [probe])
      monk = Build.new(levels: List.duplicate(:monk, 5))

      assert {:not_modelled, {:class_change, :monk, "проверочный факт без получателя"}} in Rules.compute(
               monk,
               probed
             ).gaps

      # ...и вторая половина контроля: настоящий факт монаха тем же путём
      # до гэпов НЕ доезжает — то есть молчит метка, а не сломанный вызов.
      refute {:not_modelled, {:class_change, :monk, "instinctive_throw_usable_from"}} in Rules.compute(
               monk,
               siala
             ).gaps

      assert siala.gaps != [], "список гэпов корпуса не пуст — refute выше не про пустоту"

      assert for({:not_modelled, {:class_change, :monk, what}} <- siala.gaps, do: what) == []

      # ...и старая форма ушла вместе с применённым фактом: печатать
      # «не применено» про применённое — та же устаревшая справка, на которой
      # проект уже горел (CLAUDE.md §9).
      refute {:not_modelled, {:class_change, :monk, "instinctive_throw"}} in siala.gaps
    end

    # Выдача стоит на ЗАМЕРЕ, а не на странице, которая повторяет себя, — и это
    # свойство данных, а не комментария: пометь запись `wiki`, и разбор в этом
    # файле снова начнёт опираться на источник, которого не хватило один раз.
    test "the hand-out rests on the measurement, with what it did not cover", %{siala: siala} do
      shift =
        Enum.find(
          siala.classes[:monk].siala_changes,
          &(&1["value"] == [%{"feat" => "instinctive_throw", "from" => nil, "to" => 5}])
        )

      assert shift["source"] == %{
               "kind" => "user",
               "who" => "Dan",
               "date" => "2026-08-09",
               "where" => "тестовый сервер Сиалы"
             }

      # ⚠️ И то, чего замер не покрыл, названо словами рядом с фактом. Первый
      # пункт обязан быть про строку «с 15 уровня»: именно она осталась открытой.
      assert is_list(shift["not_covered"]) and length(shift["not_covered"]) >= 3
      assert Enum.any?(shift["not_covered"], &(&1 =~ "15 уровня"))
    end

    # source: wiki Сиалы «Монах» revid 17402 — AC bonus 1 -> 4, Evasion 1 -> 25,
    # Improved Evasion 9 -> 30. A level whose last feat moved away leaves the
    # map: `9 => []` would read as "known to grant nothing", which is the shape
    # of a level that was never in the table.
    # ⚠️ 28.08.2026: из проверки убран уровень 7. Он стоял здесь потому, что
    # сдвиг `Wholeness of body` 7 → 2 опустошал его — а сдвиг оказался нашей
    # ошибкой (кейс AF1, замер Dan: фит выдаётся на 7-м). Сам инвариант
    # «опустевший уровень исчезает, а не остаётся пустым» верен и проверяется
    # уровнем 9, который опустошает настоящий сдвиг `Improved evasion` 9 → 30.
    test "a level emptied by a shift is absent, not empty", %{siala: siala} do
      granted = siala.classes[:monk].granted_feats

      refute Map.has_key?(granted, 9)
      assert Enum.all?(granted, fn {_level, ids} -> ids != [] end)
      assert granted[4] == [:monk_ac_bonus]
      assert granted[25] == [:evasion]
      assert granted[30] == [:improved_evasion]
    end
  end

  describe "the whole layer" do
    # A shift names a feat by id; a typo would put an id in `granted_feats` that
    # resolves to nothing, and `feats_owned` would quietly grow a member no
    # prerequisite could ever match.
    test "every granted feat id exists in the dictionary", %{siala: siala, vanilla: vanilla} do
      for ruleset <- [siala, vanilla],
          {class_id, class} <- ruleset.classes,
          {level, ids} <- class.granted_feats,
          id <- ids do
        assert Map.has_key?(ruleset.feats, id),
               "#{ruleset.version}: #{class_id} grants unknown feat #{id} at class level #{level}"
      end
    end

    test "shifted feats reach a build that takes the levels", %{siala: siala} do
      build = Build.new(levels: List.duplicate(:harper_scout, 1))
      owned = Build.feats_owned(build, siala, 1)

      assert MapSet.member?(owned, :craft_harper_item)
      refute MapSet.member?(owned, :bardic_knowledge)
    end

    # source: wiki Сиалы «Волшебник» revid 20070 — «Данное умение доступно
    # персонажу с 10 уровней в классе», and the feat's own page «Teleportation»
    # revid 19569 — «Волшебник (Wizard) 10 уровня». Two pages, one number.
    #
    # ⚠ The hand-out and the mechanic are separate facts on purpose: the wizard
    # owns the ability from class level 10, and the distance it buys
    # (`5 м × уровень`, spent per jump, restored on rest) is **not** modelled and
    # keeps its own gap. Granting the feat must not be read as "the teleport is
    # implemented".
    test "a shard-only class ability is handed over, not offered", %{siala: siala} do
      assert :teleportation in siala.classes[:wizard].granted_feats[10]

      build = Build.new(levels: List.duplicate(:wizard, 10))
      assert MapSet.member?(Build.feats_owned(build, siala, 10), :teleportation)
      refute MapSet.member?(Build.feats_owned(build, siala, 9), :teleportation)

      # ⚠️ Дистанция остаётся неприменённой, но гэпом с 3.28 (10.08.2026) не
      # считается: метров калькулятор не считает вовсе, поэтому у факта
      # `affects: ["special_ability"]`. Здесь стоял `assert … in siala.gaps` —
      # проверяем то же утверждение, но по данным, а не по списку неточностей.
      distance =
        Enum.find(siala.classes[:wizard].siala_unapplied, &(&1["what"] == "instant_teleport"))

      assert distance["affects"] == ["special_ability"]
      assert distance["value"]["total_distance_m"] == "5 * wizard_level"
      refute {:not_modelled, {:class_change, :wizard, "instant_teleport"}} in siala.gaps
    end
  end

  describe "опровергнутый замером факт (status: refuted)" do
    test "монах получает Wholeness of body на 7-м уровне класса, как в ванили" do
      # 🔴 Замер Dan 28.08.2026, кейс AF1: «монк получил wholeness of body на 7
      # уровне». Страница Сиалы пишет «Требования: Монах 2 уровня» (revid 17482),
      # и наш факт стоял со статусом verified — первая ошибка в данных, найденная
      # сверкой с хаками (cls_feat_monk.2da, row 8, GrantedOnLevel = 7).
      for version <- ["siala_41", "vanilla"] do
        {:ok, ruleset} = BuildCalculator.Data.ruleset(version)

        levels =
          for {level, ids} <- ruleset.classes[:monk].granted_feats,
              :wholeness_of_body in ids,
              do: level

        assert levels == [7],
               "#{version}: ожидался 7-й уровень класса, получено #{inspect(levels)}"
      end
    end

    test "refuted не порождает оговорку — мы знаем ответ, а не «не смогли выразить»" do
      # ⚠️ Разница с `unclear`, который в оговорку уходит намеренно: там источник
      # не дал числа, здесь дал — просто неверное, и правильное нам известно.
      # Оговорка тут была бы ложной тревогой (§9 CLAUDE.md).
      {:ok, ruleset} = BuildCalculator.Data.ruleset("siala_41")

      refute Enum.any?(ruleset.gaps, fn gap ->
               match?({:not_modelled, {:class_change, :monk, "feat_level_shift"}}, gap)
             end)
    end

    test "неизвестный статус роняет сборку, а не применяется молча" do
      # Разбор фактов идёт по ключу `what`, а не по статусу: опечатка в "refuted"
      # применила бы факт вместо того, чтобы отбросить, — то есть ошибка была бы
      # направлена в сторону ложного знания.
      assert_raise RuntimeError, ~r/неизвестный status/, fn ->
        BuildCalculator.Data.Loader.Classes.verify_status_for_test!(:monk, %{
          "status" => "refuteed",
          "what" => "feat_level_shift"
        })
      end
    end
  end
end
