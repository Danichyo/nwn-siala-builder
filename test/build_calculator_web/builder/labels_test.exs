defmodule BuildCalculatorWeb.Builder.LabelsTest do
  @moduledoc """
  Turning the core's tuples into Russian is the web layer's whole job in that
  division of labour (CLAUDE.md §8), so it gets tested like one.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Ids
  alias BuildCalculatorWeb.Builder.{Feats, Gaps, Labels}
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build

  setup do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  describe "refusals" do
    test "structural reasons become sentences a player can act on", %{ruleset: ruleset} do
      assert Labels.reason({:requires_bab, 4}, ruleset) == "нужен BAB +4"
      assert Labels.reason({:max_classes, 4}, ruleset) == "лимит 4 класса"
      assert Labels.reason({:level_cap, 41}, ruleset) == "кап 41 уровень"
      assert Labels.reason({:requires_race, [:dwarf]}, ruleset) =~ "Гном"

      # ⚠️ До 19.08.2026 здесь стояло «без вещей» — ядро по-прежнему сравнивает
      # требование с базовым значением (`GAME_CHECKS.md` S1), но решение Dan
      # 19.08.2026 (задача 3.57) убрало эти слова из подписи: «фиты никогда
      # вещи не учитывают, и можно даже не писать об этом, такие правила NWN».
      assert Labels.reason({:requires_ability, :str, 13}, ruleset) == "нужен STR 13"
    end

    test "an unmodelled requirement says so instead of pretending", %{ruleset: ruleset} do
      assert Labels.reason({:missing_data, {:class_requirements, :weapon_master}}, ruleset) =~
               "не разобраны"
    end

    test "a reason nobody worded yet is still readable, never swallowed", %{ruleset: ruleset} do
      assert Labels.reason({:something_new, 7}, ruleset) =~ "something_new"
    end

    test "the first maximum in the schema does not read like a minimum", %{ruleset: ruleset} do
      # До него в схеме были только минимумы, и «нужен 1-й уровень» здесь
      # означало бы ровно противоположное.
      assert Labels.reason({:max_character_level, 1}, ruleset) == "только на 1-м уровне"
      assert Labels.reason({:max_character_level, 5}, ruleset) =~ "только до 5"
    end

    test "a disjunction reads as «или», not as a list of musts", %{ruleset: ruleset} do
      text =
        Labels.reason(
          {:requires_any_of, [{:requires_race, [:elf]}, {:requires_class_level, :assassin, 20}]},
          ruleset
        )

      assert text =~ " или "
      assert text =~ "Assassin 20"
    end

    # ⚠️ «без вещей» пришло сюда 16.08.2026 правкой S2, теми же словами, что
    # у требования по характеристике выше, и это было одно правило, а не два
    # похожих: ядро сравнивает требование с сейвом без блока «Вещи», а панель
    # рядом показывает сейв в шмоте — у сейвов разрыв между ними до +20, то
    # есть крупнее, чем у характеристики. Убрано решением Dan 19.08.2026
    # (задача 3.57), тем же доводом, что и у характеристики: аудитория шарда
    # знает правило NWN без подсказки. Ядро продолжает считать как считало.
    # ⚠️ А вторая половина — 17.08.2026 правкой S3 — ОСТАЁТСЯ и решением 3.57
    # не отменяется: у сейвов из требования выпадают не только вещи, и без
    # имени исключённого отказ становится загадкой ровно на том билде, где
    # правило и кусает (воин 9 с Удачей видит в панели 8 при требовании 8
    # и вещей не носит вовсе). Это не общее правило NWN, а точечное
    # исключение одного источника — довод 3.57 сюда не дотягивается.
    # ⚠️ И с третьей — правкой S6 того же дня, по тому же доводу: воин 12
    # с телосложением 10 вещей не носит и Удачи не брал, а в панели у него ровно
    # требуемые 8. Обе прежние половины ему не объясняют ничего, потому что
    # обе про источники, которых у него нет; объясняет момент.
    # ⚠️ Уточнение S7b фразу НЕ удлинило, и это решение, а не забывчивость:
    # снимок теперь ещё и с прибавкой характеристики этого уровня, то есть
    # «на входе» называет момент чуть раньше того, что считает ядро. Ошибка
    # односторонняя (обещаем меньше, чем засчитываем), единственный билд,
    # которому она врёт, переложит прибавку на этом же экране и увидит фит
    # сразу, а точность стоила бы второй оговорки в строке с одной. Довод
    # целиком — у самой фразы в `Builder.Labels`.
    test "a save requirement is named the way the game and the export write it", %{
      ruleset: ruleset
    } do
      assert Labels.reason({:requires_save_bonus, :fort, 8}, ruleset) ==
               "нужен Fort +8 на входе в уровень, без Luck of heroes"

      assert Labels.reason({:requires_any_skill_ranks, 20}, ruleset) =~ "любой один"
      assert Labels.reason({:requires_spell_level, 4}, ruleset) =~ "4 круга"
    end

    # 🔴 Имя приходит ИЗ ДАННЫХ, а не написано в веб-слое: ruleset без разметки
    # сейвов печатает фразу без последней половины. То есть в день, когда признак
    # с записи снимут, имя исчезнет само — и наоборот, никакой правки здесь
    # не потребует появление второго исключения.
    #
    # ⚠️ «На входе в уровень» при этом остаётся: это правило ключа, а не запись
    # разметки, и снять его с экрана может только правка правила.
    test "исключение называется по разметке, а не по имени в коде", %{ruleset: ruleset} do
      assert Labels.reason({:requires_save_bonus, :fort, 8}, %{ruleset | save_bonuses: %{}}) ==
               "нужен Fort +8 на входе в уровень"
    end

    # ⚠️ Расстояние обязано мериться до той же черты, что и сам отказ. От сейва
    # «в шмоте» билд с вещами `+20` вечно оказывался бы «не хватает 1» и стоял бы
    # первым среди недоступных — сортировка «почти дотянулся» показывала бы ровно
    # те фиты, до которых дальше всего.
    #
    # ⚠️ Черта эта с 17.08.2026 — `saves_for_prereqs`, а не соседнее
    # `saves_naked`: у билда с `Luck of heroes` они расходятся на единицу, и
    # мерить от голого значило бы обещать «не хватает 1» там, где не хватает 2.
    # Карта нарочно несёт оба поля с разными числами — от неверного расстояние
    # вышло бы 4.
    test "расстояние до требования по сейву меряется от того же числа, что и отказ" do
      geared = %{
        saves_for_prereqs: %{fort: 3, ref: 0, will: 0},
        saves_naked: %{fort: 4, ref: 0, will: 0},
        fort: 23
      }

      assert Labels.distance({:requires_save_bonus, :fort, 8}, geared) == 5
    end

    # Баг 1.5: «нечего выбрать» бывает по двум причинам, и одна из них — ложь,
    # если сказать её вместо другой.
    test "пустой выбор объясняется двумя разными фразами", %{ruleset: ruleset} do
      exhausted = Labels.reason({:choice_exhausted, :spell_focus, :spell_school}, ruleset)

      required =
        Labels.reason(
          {:choice_requires, :greater_spell_focus, [:spell_focus], :spell_school},
          ruleset
        )

      assert exhausted =~ "Spell focus"
      assert exhausted =~ "все доступные"
      assert required =~ "сначала нужен Spell focus"
      refute required =~ "все доступные"

      # Два требуемых фита названы оба: «нужен Spell focus» у Epic spell focus
      # было бы неполной правдой — нужен ещё и Greater.
      both =
        Labels.reason(
          {:choice_requires, :epic_spell_focus, [:spell_focus, :greater_spell_focus],
           :spell_school},
          ruleset
        )

      assert both =~ "Spell focus и Greater spell focus"
    end

    # ⚠️ Сторож за словарём имён доменов. Домены приходят ИЗ ДАННЫХ
    # (`repeatable.choice`), а имена лежат в коде — значит новый домен молча
    # вернул бы свой ключ, и игрок снова прочитал бы «spell_school».
    # Ходим по обоим ruleset'ам: у `siala_41` фитов с выбором больше.
    test "у каждого домена выбора есть человеческое имя", %{ruleset: _} do
      keyed =
        for version <- Data.versions(),
            {domain, _dictionary} <- Data.ruleset!(version).choice_domains,
            Labels.domain_name(domain) == Atom.to_string(domain),
            uniq: true,
            do: {version, domain}

      assert keyed == [],
             """
             У этих доменов нет русского имени — в текст для игрока уедет ключ
             данных (ровно баг 1.5). Имя заводится в `Labels.domain_name/1`.

             #{inspect(keyed, pretty: true)}
             """
    end

    test "имя домена — подпись интерфейса, а не ключ", %{ruleset: _} do
      assert Labels.domain_name(:spell_school) == "школа магии"
      assert Labels.domain_name(:skill) == "навык"
      assert Labels.domain_name(:weapon) == "оружие"

      # Незнакомый домен всё ещё читаем — но именно на нём падает сторож выше.
      assert Labels.domain_name(:brand_new_domain) == "brand_new_domain"
    end

    test "a feat the shard switched off names itself", %{ruleset: ruleset} do
      # Читается там, где самого фита на экране нет: престиж-класс, требующий
      # выключенный фит, иначе объяснялся бы «отключён» — а какой, неизвестно.
      text = Labels.reason({:feat_disabled, :devastating_critical}, ruleset)

      assert text =~ "Devastating critical"
      assert text =~ "отключён"
    end

    # 🔴 Задача 3.228: обещание одно у всех ПЯТИ клауз, потому что поведение
    # одно — `BuilderLive.load_code/3` открывает пустой конструктор на любую
    # причину отказа. Пятая (`other`) про это молчала, то есть незнакомая
    # причина обещала меньше, чем делает. Под тестом, чтобы шестая клауза
    # не появилась молчащей.
    test "любая причина отказа ссылки обещает пустой конструктор" do
      for reason <- [
            :malformed,
            :too_long,
            :unknown_version,
            :unknown_ruleset,
            :some_reason_we_have_not_met_yet
          ] do
        assert Labels.decode_error(reason) =~ "пустой конструктор"
      end
    end
  end

  describe "names" do
    test "the shard's race name leads and the engine's name follows", %{ruleset: ruleset} do
      # The collision CLAUDE.md §4 warns about, in both directions.
      assert Labels.race_ru(ruleset, :dwarf) == "Гном"
      assert Labels.race_en(ruleset, :dwarf) == "Dwarf"
      assert Labels.race_ru(ruleset, :gnome) == "Карлик"
      assert Labels.race_en(ruleset, :gnome) == "Gnome"
    end

    test "class names are printed exactly as the wiki spells them", %{ruleset: ruleset} do
      # Fandom does not title-case, and redrawing the case would be invention.
      assert Labels.class_name(ruleset, :dwarven_defender) == "Dwarven defender"
    end

    test "a granted feat carries the rank it arrives at", %{ruleset: ruleset} do
      # Одна страница вики на всё семейство ступеней, поэтому ранг лежит рядом
      # с именем и не нормализован (CLAUDE.md §9).
      assert Labels.granted_feat_name(ruleset, :defensive_awareness, "II") ==
               "Defensive awareness II"

      assert Labels.granted_feat_name(ruleset, :deathless_vigor, "(+5HP)") ==
               "Deathless vigor (+5HP)"

      assert Labels.granted_feat_name(ruleset, :inspire_courage, "1/day") ==
               "Inspire courage 1/day"

      assert Labels.granted_feat_name(ruleset, :toughness, nil) == "Toughness"
      assert Labels.granted_feat_name(ruleset, :toughness, "") == "Toughness"
    end

    test "a rank that is itself a name replaces the feat name", %{ruleset: ruleset} do
      # Пять записей из 103 (посчитано обходом `granted_feat_ranks` на обоих
      # ruleset'ах). Дописывание дало бы «Barbarian rage greater rage».
      assert Labels.granted_feat_name(ruleset, :barbarian_rage, "greater rage (4x/day)") ==
               "Greater rage (4x/day)"

      assert Labels.granted_feat_name(ruleset, :elemental_shape, "improved elemental shape") ==
               "Improved elemental shape"

      assert Labels.granted_feat_name(
               ruleset,
               :infinite_greater_wildshape,
               "infinite humanoid shape"
             ) == "Infinite humanoid shape"
    end

    # §7, найдено 10.08.2026: шестая запись, начинающаяся с буквы, — НЕ имя
    # ступени, и на ней имя фита исчезало целиком.
    #
    # ⚠️ Обе половины обязаны стоять вместе. «Ранг с плюсом больше не съедает
    # имя» зеленеет и у функции, которая не заменяет имя НИКОГДА; «ранг-имя
    # по-прежнему заменяет» (тест выше) зеленеет и у той, что заменяет ВСЕГДА.
    # По отдельности каждая половина верна при неверной модели.
    test "римский ранг с украшением остаётся хвостом, а не съедает имя фита", %{
      ruleset: ruleset
    } do
      # `Rogue.wikitext`, строка 20-го уровня: `uncanny dodge VI+` — «VI и выше»,
      # последняя строка таблицы. Единственная такая запись из 103.
      assert Labels.granted_feat_name(ruleset, :uncanny_dodge, "VI+") == "Uncanny dodge VI+"

      # Положительный контроль: без украшения ранг вёл себя верно и раньше —
      # значит тест выше падает от самого плюса, а не от чего-то ещё.
      assert Labels.granted_feat_name(ruleset, :uncanny_dodge, "VI") == "Uncanny dodge VI"

      # И через настоящий билд, а не только через подпись: ровно то, что игрок
      # читает в «Класс даёт сам» у вора 20-го уровня.
      rogue = fn n ->
        Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:rogue, n))
      end

      assert "Uncanny dodge VI+" in Feats.granted_display(ruleset, rogue.(20), 20)
      assert "Uncanny dodge V" in Feats.granted_display(ruleset, rogue.(17), 17)
    end

    test "the ladder gets a community-style abbreviation", %{ruleset: ruleset} do
      assert Labels.class_short(ruleset, :dwarven_defender) == "DD"
      assert Labels.class_short(ruleset, :weapon_master) == "WM"
      assert Labels.class_short(ruleset, :champion_of_torm) == "CoT"
      assert Labels.class_short(ruleset, :fighter) == "Fighter"
    end

    # Задача 3.16: разбор BAB подписывает скорость роста словом рядом с классом.
    test "скорость роста BAB названа словом, а не коэффициентом", %{ruleset: _} do
      assert Labels.bab_progression("high") == "полный"
      assert Labels.bab_progression("medium") == "средний"
      assert Labels.bab_progression("low") == "низкий"

      # Класса без метки в данных сегодня нет, но подпись обязана его пережить:
      # `nil` означает «сказать нечего», и разбор просто не печатает скобку.
      assert Labels.bab_progression(nil) == nil

      # ⚠️ Ни одного множителя: `0.75 × 15` даёт 11.25, а вклад клирика — 11
      # (`Summary.bab_terms/2`), и формула «сколько стоит medium» живёт в
      # единственном месте — в загрузчике, где сверена со всеми таблицами.
      for label <- ~w(high medium low) do
        refute Labels.bab_progression(label) =~ ~r/[0-9\/]/
      end
    end

    # ⚠️ Сторож за словарём, ровно как у доменов выбора выше: метка приходит ИЗ
    # ДАННЫХ (`bab_progression`, и Сиала её уже переписывает — монаху с `medium`
    # на `high`), а слова лежат в коде. Новая метка вернулась бы сырой строкой
    # и уехала бы игроку в скобках как `three_quarters`.
    test "у каждой встречающейся в данных метки прогрессии есть слово", %{ruleset: _} do
      raw =
        for version <- Data.versions(),
            {id, class} <- Data.ruleset!(version).classes,
            label = class.bab_progression,
            is_binary(label),
            Labels.bab_progression(label) == label,
            uniq: true,
            do: {version, id, label}

      assert raw == [],
             """
             У этих значений `bab_progression` нет русского слова — в разбор BAB
             уедет сырая метка из данных. Слово заводится в
             `Labels.bab_progression/1`.

             #{inspect(raw, pretty: true)}
             """
    end

    # Задача «разбор сейвов по классам»: у сейва та же подпись рядом с классом,
    # но метки другие и их ДВЕ, не три.
    test "скорость роста сейва названа словом из источника", %{ruleset: _} do
      # source: fandom "Base save" — строки таблицы называются «High saves» и
      # «Low saves», отсюда «высокий» и «низкий».
      assert Labels.save_progression("good") == "высокий"
      assert Labels.save_progression("poor") == "низкий"
      assert Labels.save_progression(nil) == nil

      # ⚠️ Никакого множителя, и здесь его не существует в принципе: сейв растёт
      # на +2 за первый уровень класса и по +1 через уровень, то есть нелинейно
      # (`Fighter 10` даёт 7, а не 5).
      for label <- ~w(good poor) do
        refute Labels.save_progression(label) =~ ~r/[0-9\/]/
      end

      # ⚠️ И «низкий» — то же слово, что у BAB: одна мысль, одно слово в двух
      # соседних разборах одной панели. Совпадение проверяется, а не
      # предполагается — иначе оно разъедется при первой правке одной из двух.
      assert Labels.save_progression("poor") == Labels.bab_progression("low")
    end

    # ⚠️ Тот же сторож, что у BAB выше, и он нужен не меньше: метка сейва
    # приходит из данных (`save_progressions`), и `mix wiki.parse` может принести
    # третье значение — на страницах Fandom рядом с `good`/`poor` живут ещё и
    # слова «high»/«low» из таблицы, и достаточно одной страницы, написанной
    # иначе, чтобы игроку уехало «(high)» в скобках.
    test "у каждой встречающейся в данных метки сейва есть слово", %{ruleset: _} do
      raw =
        for version <- Data.versions(),
            {id, class} <- Data.ruleset!(version).classes,
            {save, label} <- class.save_progressions,
            is_binary(label),
            Labels.save_progression(label) == label,
            uniq: true,
            do: {version, id, save, label}

      assert raw == [],
             """
             У этих значений `save_progressions` нет русского слова — в разбор
             сейва уедет сырая метка из данных. Слово заводится в
             `Labels.save_progression/1`.

             #{inspect(raw, pretty: true)}
             """

      # Положительный контроль: метки вообще есть у всех 23 классов и всех трёх
      # сейвов — пустой список выше иначе означал бы «нечего проверять».
      counted =
        for version <- Data.versions(),
            {_id, class} <- Data.ruleset!(version).classes,
            {_save, label} <- class.save_progressions,
            is_binary(label),
            do: label

      assert length(counted) == 23 * 3 * length(Data.versions())
    end
  end

  describe "the registry of everything the core says" do
    # ⚠️ Пока сторожем был только тест ниже, подпись гарантировалась ровно тем
    # гэпам, что лежат в `ruleset.gaps`. Гэпы, возникающие на конкретном билде,
    # такой страховки не имели — шесть конструкторов успели прожить без подписи,
    # рендерясь через `inspect/1`. `Rules.gap_forms/0` и `Rules.reason_forms/0`
    # закрывают дыру: ходить теперь есть по чему.
    test "every gap form the core can produce has Russian wording", %{ruleset: ruleset} do
      forms = Rules.gap_forms()
      assert length(forms) > 40

      for gap <- forms do
        text = Labels.gap(gap, ruleset)

        assert text != ""
        refute text =~ ~r/^\{/, "no Russian wording for gap #{inspect(gap)}"
        refute text =~ ~r/^\[/, "no Russian wording for gap #{inspect(gap)}"
      end
    end

    test "every refusal form the core can produce has Russian wording", %{ruleset: ruleset} do
      forms = Rules.reason_forms()
      assert length(forms) > 20

      for reason <- forms do
        text = Labels.reason(reason, ruleset)

        assert text != ""
        refute text =~ ~r/^\{/, "no Russian wording for reason #{inspect(reason)}"

        # ⚠️ И не список: `{:requires_any_of, …}` несёт СПИСОК НА ВЕТКУ, и
        # ветка, попавшая в `inspect/1`, начинается с квадратной скобки, а не
        # с фигурной. Ровно так эта форма и жила незамеченной.
        refute text =~ ~r/^\[/, "a branch fell through to inspect/1: #{inspect(reason)}"
      end
    end

    test "the feat picker's own refusals are worded too", %{ruleset: ruleset} do
      # Эти формы ядро не производит, значит его реестр их не покроет.
      forms = Feats.reason_forms()
      assert length(forms) > 3

      for reason <- forms do
        text = Feats.reason(reason, ruleset)

        assert text != ""
        refute text =~ ~r/^\{/, "no Russian wording for picker reason #{inspect(reason)}"
      end
    end

    test "a refusal the core produces is worded by the picker as well", %{ruleset: ruleset} do
      # `Feats.reason/2` делегирует незнакомое в `Labels.reason/2`, поэтому
      # дыра в делегате видна только через сам делегат.
      for reason <- Rules.reason_forms() do
        text = Feats.reason(reason, ruleset)

        refute text =~ ~r/^[\{\[]/, "picker shows a tuple for #{inspect(reason)}"
      end
    end

    test "every distance is a number, so «почти дотянулся» can sort", %{ruleset: ruleset} do
      _ = ruleset

      # ⚠️ `abilities_naked` появилось здесь 16.08.2026 вместе с правкой S1:
      # расстояние до требования по характеристике меряется от базового
      # значения, потому что от него же стоит и сам отказ. Оба поля оставлены
      # намеренно — минимальные статы обязаны нести ровно то, что читает
      # `distance/2`, иначе тест перестаёт ловить пропущенную голову.
      #
      # ⚠️ `saves_naked` пришло в тот же день той же правкой (S2), и `fort`
      # рядом с ним оставлен по той же причине, что `abilities`: поле читают
      # другие места, и убрать его отсюда значило бы перестать проверять их.
      # С 17.08.2026 (S3) расстояние до требования по сейву меряется от
      # `saves_for_prereqs` — соседнего поля с другим смыслом, — и здесь стоят
      # оба: минимальные статы обязаны нести ровно то, что читает `distance/2`.
      stats = %{
        base_attack: 0,
        character_level: 1,
        abilities: %{},
        abilities_naked: %{},
        class_levels: %{},
        fort: 0,
        saves_naked: %{fort: 0, ref: 0, will: 0},
        saves_for_prereqs: %{fort: 0, ref: 0, will: 0}
      }

      for reason <- Rules.reason_forms() do
        assert is_integer(Labels.distance(reason, stats)), inspect(reason)
      end
    end
  end

  describe "gaps" do
    test "every gap the ruleset carries has Russian wording", %{ruleset: ruleset} do
      for gap <- ruleset.gaps do
        text = Labels.gap(gap, ruleset)

        assert is_binary(text) and text != ""
        # `inspect/1` is the fallback; anything hitting it needs wording.
        refute text =~ ~r/^\{/, "no Russian wording for #{inspect(gap)}"
      end
    end

    # ⚠️ Справка называет ПОСЧИТАННЫЙ вариант и тот, что ему противопоставлен, —
    # это часть признания, а не украшение (задача 3.12): «+9» без «а не базовый
    # +6» не объясняет, откуда взялось именно девять.
    #
    # 🔴 ЗДЕСЬ ПРОВЕРЯЛИСЬ ВСЕ ЧЕТЫРЕ ЧИСЛА (+6 +9 +12 +18) — снято 31.08.2026
    # по запросу Dan вместе с хвостом «Это только половина: … вместе выходит +12,
    # а у воина Сагры +18». ⚠️ Хвост был не просто длинен, он **обобщал неверно**:
    # `+12`/`+18` достижимы только с РАСОВЫМ оружием, а оно у каждой расы своё
    # (`racial_bonus.mirrors_weapon_type`). У Светлого эльфа это оружие дальнего
    # боя — Dan: «+18 получается только светлый эльф сагровик на метательное»;
    # с клинковым в руках оружейный бонус идёт в щитовой AC, а не в атаку.
    #
    # ⚠️ Четыре числа НЕ пропали из ответа — они по-прежнему отдаются справкой
    # (`stats.racial_bonus.variants`), просто не печатаются строкой в UI:
    # «люди и так знают про бонусы расы и оружия» (Dan).
    test "оговорка про расовый бонус называет посчитанный вариант и его альтернативу",
         %{ruleset: ruleset} do
      text = Labels.gap({:assumed, {:racial_bonus_variant, :half_elf, :sagra_warrior}}, ruleset)

      assert text =~ "Светлый эльф"
      assert text =~ "+9"
      assert text =~ "+6"

      # Хвост про оружейные варианты снят целиком — ни чисел, ни фразы.
      refute text =~ "+12"
      refute text =~ "+18"
      refute text =~ "только половина"
      refute text =~ "армори"
    end

    # 🔴 Третья подпись того же тапла: число известно, а бонуса нет, потому что
    # руки пусты. `variant: nil` — то же самое ФОРМА (`Vocabulary.form/1` читает
    # голову и подлежащее), поэтому четвёртой регистрации в словаре не нужно,
    # а сказать игроку надо совсем другое: он в одном движении от бонуса.
    test "оговорка про пустые руки называет причину, а не вариант", %{ruleset: ruleset} do
      text = Labels.gap({:assumed, {:racial_bonus_variant, :half_elf, nil}}, ruleset)

      assert text =~ "Светлый эльф"
      assert text =~ "оружием в руках"
      refute text =~ "посчитан базовый"
      refute text =~ "посчитан вариант"
    end

    # 🔴 Задача 3.102 (решение Dan 25.08.2026): два из трёх предложений одного
    # тапла описывали УСПЕХ и стояли под заголовком «ядро не смогло посчитать
    # N». `Labels.gap/2` их по-прежнему словами знает — иначе сторож подписей
    # (`Rules.gap_forms/0` несёт пример `{…, :gnome, :base}`) уронил бы сборку,
    # — но приезжает туда из ядра только третье, `variant: nil`. Посчитанное
    # печатает `racial_bonus_note/2`, и это ТО ЖЕ предложение, а не второе
    # написание того же: сверяется равенством строк.
    # ⚠️ **`variants` в записи появились здесь 11.09.2026 (задача 3.181), и это
    # не косметика тестовой фикстуры.** Справка печатает числа БИЛДА, а не
    # файла: с ростом по уровням это разные вещи — у 17-го уровня +4 там, где
    # в файле +9. Гэповая ветка чисел билда не несёт, поэтому сверяются они
    # на записи с числами 40-го уровня, где два источника совпадают.
    test "справка к посчитанному — то же предложение, что знал гэп", %{ruleset: ruleset} do
      for variant <- [:base, :sagra_warrior] do
        bonus = %{
          race: :half_elf,
          counted: 9,
          variant: variant,
          kind: :attack_bonus,
          variants: ruleset.racial_bonuses.by_race[:half_elf].variants
        }

        assert Labels.racial_bonus_note(ruleset, bonus) ==
                 Labels.gap({:assumed, {:racial_bonus_variant, :half_elf, variant}}, ruleset)
      end
    end

    # 🔴 И главное следствие той же правки: справка называет число ЭТОГО билда.
    # До 3.181 источник был один (файл), потому что и ответ был один — бонус
    # считался только на 40-м. Теперь у 17-го уровня свои числа, и печатать
    # ему +9 значило бы обещать вдвое больше, чем он получит.
    test "справка печатает числа билда, а не файла", %{ruleset: ruleset} do
      bonus = %{
        race: :half_elf,
        counted: 4,
        variant: :sagra_warrior,
        kind: :attack_bonus,
        variants: %{
          base: 3,
          sagra_warrior: 4,
          racial_weapon: 6,
          racial_weapon_and_sagra_warrior: 8
        }
      }

      text = Labels.racial_bonus_note(ruleset, bonus)

      assert text =~ "+4"
      assert text =~ "+3"
      refute text =~ "+9"
    end

    # 🔴 ВТОРОЕ ПРЕДЛОЖЕНИЕ про снятое удвоение (задача 3.198, замер `AN1`).
    # Без него игрок видит, что AC упал на девять очков от предмета в левой
    # руке, и читает это как баг: сама дубина ничего не отняла, она сняла
    # УДВОЕНИЕ за расовое оружие.
    #
    # ⚠️ Проверяется парой: у целого совпадения этой фразы быть не должно,
    # иначе она печаталась бы всегда и перестала бы что-либо значить.
    test "у снятого удвоения — своя вторая фраза", %{ruleset: ruleset} do
      bonus = %{
        race: :gnome,
        counted: 9,
        variant: :sagra_warrior,
        kind: :shield_ac,
        variants: ruleset.racial_bonuses.by_race[:gnome].variants
      }

      broken = Labels.racial_bonus_note(ruleset, Map.put(bonus, :weapon_match, {:broken, :mace}))
      whole = Labels.racial_bonus_note(ruleset, Map.put(bonus, :weapon_match, :matched))

      assert broken =~ "Удвоение за расовое оружие снято"
      assert broken =~ "оружие другой категории"
      assert broken =~ String.slice(whole, 0, 40)

      refute whole =~ "Удвоение"
    end

    # ⚠️ И справки НЕТ там, где говорит гэп: непосчитанный бонус (пустые руки
    # или уровень ниже 40-го) и раса без бонуса вовсе. Иначе одно и то же
    # сказалось бы дважды в двух местах экрана — ровно та ошибка, ради которой
    # 3.102 и разводила эти два предложения.
    test "у непосчитанного справки нет вовсе", %{ruleset: ruleset} do
      assert Labels.racial_bonus_note(ruleset, nil) == nil

      assert Labels.racial_bonus_note(ruleset, %{
               race: :half_elf,
               counted: nil,
               variant: nil,
               kind: :attack_bonus
             }) == nil
    end

    # ⚠️ Две РАЗНЫЕ подписи на один вид гэпа, и это главное в нём (решение Dan
    # 08.08.2026): у сагровика оговорка обязана сказать, что покровительство
    # УЖЕ учтено, а у остального билда — что не учтено и почему. Печатать «Сагру
    # в расчёт не берём» после того, как взяли, — та самая ложная
    # неопределённость наоборот (CLAUDE.md §6).
    test "оговорка называет посчитанный вариант, а не один и тот же текст", %{ruleset: ruleset} do
      sagra = Labels.gap({:assumed, {:racial_bonus_variant, :half_elf, :sagra_warrior}}, ruleset)
      base = Labels.gap({:assumed, {:racial_bonus_variant, :half_elf, :base}}, ruleset)

      assert sagra =~ "подходит под воина Сагры"
      assert sagra =~ "вариант сагровика +9"

      assert base =~ "посчитан базовый +6"
      assert base =~ "воином Сагры билд не является"

      refute base == sagra
    end

    # У каждого вида бонуса своя подпись, и у навыка называется сам навык:
    # «к навыку» без имени навыка не отвечает ни на один вопрос.
    test "оговорка про расовый бонус называет, куда он ложится", %{ruleset: ruleset} do
      human = Labels.gap({:assumed, {:racial_bonus_variant, :human, :base}}, ruleset)
      gnome = Labels.gap({:assumed, {:racial_bonus_variant, :gnome, :base}}, ruleset)

      assert human =~ "Discipline"
      assert gnome =~ "щитовой AC"

      # ⚠️ ЗДЕСЬ БЫЛ ТРЕТИЙ КЕЙС — подпись к `{:not_modelled, {:racial_bonus,
      # :dwarf, :damage_resistance}}`, где проверялось, что она называет и расу,
      # и вид бонуса. Снят задачей 3.38 (16.08.2026) вместе с формой: поглощения
      # и урона калькулятор не показывает вовсе, значит и оговорке про них
      # не место (CLAUDE.md §9, решение Dan). Ядро эту форму больше не производит
      # ни на каком билде — см. `racial_bonus_test.exs`, «Гном и Могучий человек
      # молчат»; подписи без производителя не бывает.
    end

    # ⚠️ Подписи гэпов про группы классов, и разное качество данных обязано быть
    # видно в тексте: у Адры оговорка называет ДОПУЩЕНИЕ (правило чистоты не
    # описано никем), у Сагры такой оговорки нет вовсе. Плюс запрет на намёк:
    # что даёт Адра, подпись предполагать не имеет права.
    #
    # 🔴 **С 25.08.2026 (задача 3.100) ни одну из трёх форм не производит ни
    # один билд** — решение Dan сняло признание, оставив механизм. Подписи
    # при этом обязаны жить: `Rules.Vocabulary` роняет сборку у формы без
    # русской подписи, а формы остались в словаре, потому что первая же группа
    # без метки получателя или без решения владельца вернёт свою оговорку сама.
    # Тест поэтому зовёт `Labels.gap/2` напрямую, а не через билд, и это
    # сознательно: проверяется подпись, а не то, что кто-то её сегодня печатает.
    test "оговорки про группы классов различают Сагру и Адру", %{ruleset: ruleset} do
      purity = Labels.gap({:assumed, {:class_group_purity, :adra_warriors}}, ruleset)
      adra = Labels.gap({:missing_data, {:class_group_benefits, :adra_warriors}}, ruleset)
      sagra = Labels.gap({:not_modelled, {:class_group_benefits, :sagra_warriors}}, ruleset)

      assert purity =~ "Воины Адры"
      assert purity =~ "не описано"

      assert adra =~ "Воины Адры"
      assert adra =~ "не написано"

      # ни зелий, ни точила, ни «как у Сагры» — про Адру не известно ничего
      refute adra =~ "зелья"
      refute adra =~ "Сагр"

      assert sagra =~ "Воины Сагры"
      assert sagra =~ "зелья Сагры"
      assert sagra =~ "армори"

      # 🔴 И то, чего в подписи БЫТЬ НЕ ДОЛЖНО с задачи 3.35: «усиленный бонус
      # от оружия» стоит в списке выгод на вики, но с этой задачи он посчитан
      # (`Rules.WeaponTypeBonus`), и печатать его среди непосчитанного — то же
      # враньё про посчитанное, что запрещает CLAUDE.md §6, только с другой
      # стороны. Строка обязана вместо этого сказать, что он посчитан.
      refute sagra =~ "усиленный бонус"
      assert sagra =~ "бонус за тип оружия посчитан"
    end

    test "a shard note on a feat says «учтено не полностью», not «не применено»", %{
      ruleset: ruleset
    } do
      # ⚠️ Формулировка обязана годиться и для «применено частично»: слот
      # «любимый враг» рейнджеру мы выдаём, неизвестен только его пул.
      text = Labels.gap({:not_modelled, {:feat_change, :divine_might, "siala_note"}}, ruleset)

      assert text =~ "Divine might"
      assert text =~ "не полностью"
      refute text =~ "не применено"
    end

    test "each kind of feat note is named, and an unknown one keeps its key", %{ruleset: ruleset} do
      for {what, expected} <- [
            {"siala_note", "прозой"},
            {"unlocks", "оружия"},
            {"feat_slots", "слоты"},
            {"level_table", "таблица"}
          ] do
        assert Labels.gap({:not_modelled, {:feat_change, :toughness, what}}, ruleset) =~ expected
      end

      assert Labels.gap({:not_modelled, {:feat_change, :toughness, "brand_new"}}, ruleset) =~
               "brand_new"
    end

    test "every feat note the ruleset can produce has wording", %{ruleset: ruleset} do
      # Гэпы этой формы приходят из билда, а не из `ruleset.gaps`, поэтому
      # общий тест выше их не покрывает — а без подписи они рендерятся
      # через `inspect/1`.
      whats =
        for {_id, feat} <- ruleset.feats,
            change <- Map.get(feat, :siala_unapplied, []),
            uniq: true,
            do: change["what"]

      refute whats == []

      for what <- whats do
        text = Labels.gap({:not_modelled, {:feat_change, :toughness, what}}, ruleset)
        refute text =~ ~r/^\{/, "no Russian wording for feat change #{inspect(what)}"
        refute text =~ what, "raw key #{inspect(what)} leaked into the wording"
      end
    end

    # Задача 3.11. Гэп про AC несёт голый id и НЕ несёт того, чем эта штука
    # является: источников у файла четыре (фит, класс, навык, расовая
    # склонность), а форматтеру нужно имя. `ac_bonus_name/2` перебирает три
    # словаря по очереди — и это безопасно ровно до тех пор, пока ни один id
    # не лежит в двух сразу. Проверяем, а не верим.
    test "имя для гэпа про AC разрешается однозначно у каждой записи", %{ruleset: ruleset} do
      records = ruleset.ac_bonuses.applied ++ ruleset.ac_bonuses.unmodelled
      refute records == []

      for %{id: id} <- records do
        dictionaries =
          Enum.count([ruleset.feats, ruleset.classes, ruleset.skills], &is_map_key(&1, id))

        assert dictionaries == 1,
               "#{id}: лежит в #{dictionaries} словарях, порядок перебора решает исход"

        text = Labels.ac_bonus_name(ruleset, id)
        assert is_binary(text) and text != ""
        refute text == to_string(id), "#{id}: имя не нашлось, напечатался сырой id"
      end
    end

    test "у каждой формы гэпа про AC есть русская подпись", %{ruleset: ruleset} do
      for gap <- [
            {:not_modelled, {:ac_bonus, :defensive_stance}},
            {:not_modelled, {:ac_bonus_scope, :monk_ac_bonus}},
            {:assumed, :ac_bonus_types_unstated},
            {:not_modelled, {:ac_gear_base, :shield}}
          ] do
        text = Labels.gap(gap, ruleset)

        refute text =~ ~r/^\{/, "no Russian wording for #{inspect(gap)}"
        assert text =~ "AC"
      end

      # ⚠️ Форма про базу предмета обязана назвать ТИП по-русски, а не сырым
      # id: игрок вводит числа по типам и должен узнать, про какой из них речь.
      # Имя типа — `Labels.ac_type/2`, `gettext` по id (с задачи 4.3; до неё —
      # поле данных `gear.ac_types.ru`, общее с английской ванилью).
      assert Labels.gap({:not_modelled, {:ac_gear_base, :shield}}, ruleset) =~ "Щит"
      assert Labels.gap({:not_modelled, {:ac_gear_base, :natural}}, ruleset) =~ "Природный"

      # ⚠️ Две первые формы обязаны читаться по-разному: одна значит «прибавку
      # НЕ считаем», вторая — «считаем, но она пропадает при условии». Слить
      # их значило бы соврать в одну из двух сторон.
      not_counted = Labels.gap({:not_modelled, {:ac_bonus, :expertise}}, ruleset)
      counted = Labels.gap({:not_modelled, {:ac_bonus_scope, :monk_ac_bonus}}, ruleset)

      assert not_counted =~ "не считаем"
      refute counted =~ "не считаем"

      # ⚠️ И подпись обязана быть ОБЩЕЙ, а не про монаха. С 09.08.2026 условие
      # монаха проверяется (замер Dan: ломает не вид надетого, а то, даёт ли оно
      # AC), то есть эта форма про монаха больше не приходит вовсе. Прежний текст
      # «пропадает в доспехах и со щитом» напечатался бы у следующей
      # непроверяемой оговорки — верхом, в режиме, против одного врага — и соврал
      # бы уверенно и мимо темы.
      refute counted =~ "доспех"
      assert counted =~ "условие"
    end

    test "a qualifier reads as «доступен с оговоркой», never as a refusal", %{ruleset: ruleset} do
      # До `qualifiers` такой фит не проверялся ВОВСЕ. Теперь проверен
      # настолько, насколько выразим, — и текст обязан это передавать.
      text =
        Labels.gap(
          {:not_modelled, {:feat_qualifier, :spell_focus, "in the chosen spell school"}},
          ruleset
        )

      assert text =~ "Spell focus"
      assert text =~ "проверено"
      assert text =~ "in the chosen spell school"
    end

    # source: fandom "Weapon focus" revid 70066 — «gaining a +1 [[attack roll|
    # attack]] bonus with it»; fandom "Epic weapon focus" revid 42299 — «a +2
    # bonus to all [[attack roll]]s with the chosen weapon»; fandom "Mounted
    # archery" revid 41177 — «penalty … is reduced from -4 to -2», числа
    # прибавки нет вовсе. Все три снято 01.08.2026.
    #
    # ⚠️ Подпись обязана нести ЧИСЛО: решение не считать прибавку временное
    # (`feat_attack_bonuses.json` → `_weapon_decision`), и до армори игрок
    # прибавляет её сам — но только если знает, сколько. Само число читается из
    # той же разметки, что и отказ, через `Bonuses.rejected/2`; до 09.08.2026
    # тут было инлайн-чтение внутренней формы ruleset'а, и на подпись не было
    # ни одного теста.
    test "непосчитанная прибавка к атаке называет своё число", %{ruleset: ruleset} do
      assert Labels.gap({:not_modelled, {:attack_bonus_weapon, :weapon_focus}}, ruleset) =~ "(+1)"

      assert Labels.gap({:not_modelled, {:attack_bonus_weapon, :epic_weapon_focus}}, ruleset) =~
               "(+2)"

      # Положительный контроль на обратную сторону: у записи, где числа
      # прибавки нет (снятие штрафа), скобок быть не должно — напечатать там
      # «(+0)» или «(-4)» значило бы назвать прибавкой не прибавку.
      # ⚠️ Проверяется именно форма «(+N)» / «(−N)», а не любая скобка: сама
      # подпись несёт скобочное пояснение про режим и разовое умение, и
      # `refute =~ "("` красным поймал бы его, а не отсутствие числа.
      mounted = Labels.gap({:not_modelled, {:attack_bonus, :mounted_archery}}, ruleset)

      assert mounted =~ "Mounted archery"
      refute mounted =~ ~r/\([+-]\d/
    end

    test "the flat Spellcraft save bonus is declared, not implied", %{ruleset: ruleset} do
      # Контекстность решено не моделировать (решение Дана), значит гэп —
      # единственное честное место, где об этом сказано.
      text = Labels.gap({:not_modelled, {:save_bonus_scope, :spellcraft}}, ruleset)

      assert text =~ "Spellcraft"
      assert text =~ "AOE"
    end

    test "the other new build gaps are worded too", %{ruleset: ruleset} do
      for gap <- [
            {:not_modelled, {:skill_change, :spellcraft, "save_bonus"}},
            {:not_modelled, {:class_qualifier, :assassin, "with the chosen weapon"}},
            {:missing_data, {:skill_key_ability, :alchemy}},
            {:missing_data, {:prerequisite, :save_bonus}},
            {:missing_data, {:caster_level, 3}}
          ] do
        text = Labels.gap(gap, ruleset)
        refute text =~ ~r/^\{/, "no Russian wording for #{inspect(gap)}"
      end
    end

    # ⚠️ Билд был `[:red_dragon_disciple]` и держался на его отсутствующем
    # хит-дайсе — задача 3.37 его прочитала, и группа «Данных нет» у этого
    # билда опустела. Взят светлый эльф-воин 1: у него та же группа набиралась
    # расовым бонусом, чья величина ниже 40-го уровня не была известна никому.
    #
    # 🔴 **С 11.09.2026 (задача 3.181) она известна, и группа у этого билда
    # снова опустела** — величина растёт ступенями из разбора серверных
    # скриптов. Разряд теперь набирается «Допущениями»: бонус посчитан, но
    # не включён, потому что руки пусты.
    #
    # ⚠️ Проверяется РАЗВЕДЕНИЕ двух счётчиков (гэпы корпуса против гэпов этого
    # билда), а не конкретный разряд, — поэтому кейс переписан на непустоту
    # разрядов, а не на имя одного из них: имя разряда меняется от правок
    # данных, разведение счётчиков — нет.
    test "the summary counts this build's gaps apart from the data's", %{ruleset: ruleset} do
      build = Build.new(ruleset_version: ruleset.version, race: :half_elf, levels: [:fighter])
      stats = Rules.compute(build, ruleset)
      summary = Gaps.summary(ruleset, build, stats)

      assert summary.data_count == length(ruleset.gaps)
      assert summary.build_count >= length(stats.gaps)
      assert summary.build_count > 0
      assert summary.build_groups != []
    end
  end

  # Задача 4.3: подписи типов AC и категорий надетого — из `gettext` по id,
  # а не из русских полей данных (`gear.ac_types.ru`,
  # `gear.worn.categories[].ru`), общих с английской ванилью. Данные и
  # загрузчик не тронуты — снапшоты те же, — поэтому поле данных и `msgstr`
  # теперь два места одного текста. Этот describe держит их вместе: разошлись —
  # тест назовёт, где.
  describe "типы AC и надетое — gettext по id" do
    test "под ru каждый тип AC обоих ruleset'ов назван ровно так, как в данных" do
      Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")

      for version <- Data.versions(), ruleset = Data.ruleset!(version) do
        # Положительный контроль: типы есть, иначе цикл ниже ничего не сверял.
        assert length(ruleset.gear.ac_types) == 5

        for type <- ruleset.gear.ac_types do
          assert Labels.ac_type(ruleset, type) ==
                   Map.fetch!(ruleset.gear.ac_type_names, Atom.to_string(type)),
                 "#{version}: подпись типа #{type} разошлась с данными"
        end
      end
    end

    test "под ru каждая категория надетого названа ровно так, как в данных" do
      Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")

      for version <- Data.versions(), ruleset = Data.ruleset!(version) do
        categories = BuildCalculator.Rules.Worn.categories(ruleset)
        assert Enum.map(categories, & &1.id) == [:armor, :shield]

        for category <- categories do
          assert Labels.worn_category(ruleset, category) == category.ru,
                 "#{version}: подпись категории #{category.id} разошлась с данными"
        end
      end
    end

    # Доспех и тип AC «броня» по-русски — два РАЗНЫХ слова, и у них два
    # разных msgid: один английский msgid не может нести два перевода.
    test "под en — английские имена, доспех и тип AC «броня» различимы", %{ruleset: ruleset} do
      Gettext.put_locale(BuildCalculatorWeb.Gettext, "en")

      assert Enum.map(ruleset.gear.ac_types, &Labels.ac_type(ruleset, &1)) ==
               ["Armor", "Shield", "Deflection", "Natural", "Dodge"]

      assert Enum.map(
               BuildCalculator.Rules.Worn.categories(ruleset),
               &Labels.worn_category(ruleset, &1)
             ) ==
               ["Body armor", "Shield"]
    end

    test "тип, которого интерфейс не знает, назван своим id, а не догадкой", %{ruleset: ruleset} do
      assert Labels.ac_type(ruleset, :sacred) == "sacred"

      # Категория без имени в интерфейсе называется своим типом AC, как и до 4.3.
      Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")
      assert Labels.worn_category(ruleset, %{id: :bracers, ac_type: :armor}) == "Броня"
    end
  end

  describe "alignments" do
    test "there are nine, and they resolve without creating atoms", %{ruleset: ruleset} do
      assert length(Ids.alignments()) == 9
      assert {:ok, :true_neutral} = Ids.fetch(ruleset, :alignments, "true_neutral")
      assert :error = Ids.fetch(ruleset, :alignments, "definitely_not_an_alignment")
      assert Ids.alignment_name(:lawful_good) == "Lawful Good"
    end

    test "a restriction spec reads as a sentence" do
      assert Labels.alignment_spec(%{require: ["lawful"]}) =~ "Lawful"
      assert Labels.alignment_spec(%{forbid: ["lawful"]}) =~ "не Lawful"
      assert Labels.alignment_spec(%{exact: ["lawful_good"]}) == "Lawful Good"
    end
  end

  describe "slot ids" do
    # 🔴 Обе половины ОДНИМ тестом (долг AGENT_QUEUE.md §7, закрыт 11.08.2026):
    # порознь «падает на выдуманной» зеленел бы и у стража, который валит
    # вообще всё подряд, включая объявленные формы, — а «объявленная проходит»
    # зеленел бы и у кода, который вовсе не умеет отказывать.
    #
    # `t:Build.slot_id/0` называет ровно четыре вида, а тестовые фикстуры годами
    # носили выдуманные — `{:epic_general, 21}` и `{:general, index}`.
    #
    # ⚠️ Четвёртый — `{:class_bonus, class, index}` — заведён 14.08.2026 вместе
    # с починкой «рейнджер теряет фит на 35-м классовом уровне»: уровень может
    # выдать два бонусных слота одного класса, а `build.feats[level]` — карта по
    # id слота. Индекс начинается с **двойки**, и `"class_bonus:ranger:1"`
    # отказан наравне с выдуманными формами: у первого слота ровно одно имя —
    # то, которое уже лежит в расшаренных ссылках.
    #
    # ⚠️ До правки `{:epic_general, 21}` уже падал (`FunctionClauseError` без
    # единой клаузы под 2-tuple, который не `{:class_bonus, _}`), а вот голый
    # `:epic_general` — НЕТ: старая клауза `is_atom(id)` пропускала любой атом,
    # не только `:general`/`:racial`, так что `slot_key/1` тихо возвращал
    # строку `"epic_general"`, а `fetch_slot/2` не могла прочитать её назад —
    # билд терял пик молча при следующем декоде, без единого крэша. Оба вида
    # порчи — и громкий, и молчаливый — собраны в одном списке ниже.
    test "объявленная форма slot_id переживает DOM-круг, выдуманная — падает с понятной причиной",
         %{ruleset: ruleset} do
      for slot <- [
            :general,
            :racial,
            {:class_bonus, :fighter},
            {:class_bonus, :ranger, 2},
            {:class_bonus, :ranger, 3}
          ] do
        assert {:ok, ^slot} = Ids.fetch_slot(ruleset, Ids.slot_key(slot))
      end

      for invented <- [
            {:epic_general, 21},
            {:general, 0},
            :epic_general,
            # Второе написание ПЕРВОГО слота: две строки на один вход карты
            # `build.feats[level]` — это пик, записанный дважды и прочитанный
            # один раз.
            {:class_bonus, :fighter, 1},
            {:class_bonus, :fighter, 0}
          ] do
        assert_raise ArgumentError, ~r/^not a slot id: /, fn -> Ids.slot_key(invented) end
      end
    end

    test "a bogus slot string is refused", %{ruleset: ruleset} do
      assert :error = Ids.fetch_slot(ruleset, "class_bonus:not_a_class")
      assert :error = Ids.fetch_slot(ruleset, "nonsense")
      assert :error = Ids.fetch_slot(ruleset, 42)

      # Индексная половина не резолвится ни во что, кроме целого больше единицы.
      assert :error = Ids.fetch_slot(ruleset, "class_bonus:ranger:1")
      assert :error = Ids.fetch_slot(ruleset, "class_bonus:ranger:")
      assert :error = Ids.fetch_slot(ruleset, "class_bonus:ranger:2:3")
      assert :error = Ids.fetch_slot(ruleset, "class_bonus:not_a_class:2")
    end
  end

  describe "как называются слоты фитов" do
    # Слоты НЕ взаимозаменяемы: бонусный тратится только на фит из списка
    # своего класса. Пока все они назывались одинаково, игрок не видел
    # ограничения, из-за которого потом собирается нелегальный билд (§6).
    test "общий и бонусный названы по-разному во всех трёх подписях", %{ruleset: ruleset} do
      general = %{kind: :general, class: nil, epic?: false}
      bonus = %{kind: :class_bonus, class: :fighter, epic?: false}

      assert Labels.slot_label(ruleset, general) == "Общий"
      assert Labels.slot_label(ruleset, bonus) == "Бонус Fighter"

      assert Labels.slot_ladder_label(ruleset, general) == "общий фит"
      assert Labels.slot_ladder_label(ruleset, bonus) == "фит Fighter"

      assert Labels.slot_delta_label(ruleset, general) == "общий фит"
      assert Labels.slot_delta_label(ruleset, bonus) == "бонус Fighter"
    end

    # Второй бонусный слот того же класса на том же уровне — сегодня такое место
    # ровно одно во всём корпусе: рейнджер на своём 35-м классовом («35(two bonus
    # feats)», fandom:Ranger, правка 14.08.2026). Без номера два чипа подряд
    # читаются одинаково, и пока оба пусты, игрок не понимает, в который кладёт.
    #
    # ⚠️ Номер стоит ТОЛЬКО у второго, и обе половины проверяются вместе:
    # первый слот сознательно сохранил прежний id `{:class_bonus, class}` (строка
    # «class_bonus:ranger» лежит в чужих расшаренных ссылках), и подпись повторяет
    # ту же асимметрию. Проверять только вторую строку значило бы пропустить день,
    # когда пронумеруются оба и старые ссылки перестанут совпадать со слотом.
    test "второй бонусный слот того же класса назван номером, первый — нет", %{ruleset: ruleset} do
      first = %{id: {:class_bonus, :ranger}, kind: :class_bonus, class: :ranger, epic?: true}
      second = %{id: {:class_bonus, :ranger, 2}, kind: :class_bonus, class: :ranger, epic?: true}

      assert Labels.slot_label(ruleset, first) == "Бонус Ranger · эпик"
      assert Labels.slot_label(ruleset, second) == "Бонус Ranger · эпик · 2"

      # 🔴 А сводная подпись и строка лестницы номера НЕ несут, и это проверяется
      # здесь же. Сводная группирует слоты по тексту и печатает «×2»
      # (`Builder.Feats.slot_labels/2`) — пронумеруй её, и два слота перестанут
      # схлопываться. Лестница показывает выбранный фит, номер слота там лишний.
      assert Labels.slot_ladder_label(ruleset, second) == "фит Ranger · эпик"
      assert Labels.slot_delta_label(ruleset, second) == "бонус Ranger · эпик"

      # ⚠️ Слот без `id` вовсе — законный вызов, а не порча: часть мест зовёт
      # подпись по одной лишь форме слота (см. `slot_label/2`'s doc про `epic?`).
      # Номера у такого нет, и падать он не должен.
      assert Labels.slot_label(ruleset, %{kind: :class_bonus, class: :ranger, epic?: true}) ==
               "Бонус Ranger · эпик"
    end

    # ⚠️ У эпического бонусного слота ДРУГОЙ пул: он берёт эпические фиты
    # класса, а обычный их не принимает. Раньше оба назывались «Бонус Fighter».
    test "эпический классовый слот назван эпическим везде, где он виден", %{ruleset: ruleset} do
      epic = %{kind: :class_bonus, class: :fighter, epic?: true}

      assert Labels.slot_label(ruleset, epic) == "Бонус Fighter · эпик"
      assert Labels.slot_ladder_label(ruleset, epic) == "фит Fighter · эпик"
      assert Labels.slot_delta_label(ruleset, epic) == "бонус Fighter · эпик"

      # И это та же система, которой общий слот пользовался всегда.
      assert Labels.slot_label(ruleset, %{kind: :epic_general, class: nil}) == "Общий · эпик"
    end

    # ⚠️ Баг 1.4 (Dan 03.08.2026): у общего слота пул после 20-го НЕ
    # заменяется эпическим, а РАСШИРЯЕТСЯ — `FeatSlots.candidates/2` на
    # Fighter даёт 93 обычных фита в общем слоте и 146 в эпическом общем
    # (93 из них — те же обычные, плюс 53 эпических; перепроверено
    # 04.08.2026, число не изменилось с находки 03.08.2026 несмотря на четыре
    # раунда правок данных и правил между ними). Подпись «эпический фит»
    # читалась бы как «только эпические» и сузила бы пул на экране — ровно
    # обратное тому, что происходит на самом деле. Поэтому во всех трёх
    # местах слот обязан остаться «общим» и лишь получить пометку `· эпик`,
    # как и остальные три вида слотов.
    test "эпический общий слот назван «общим» везде, где он виден, а не «эпическим»", %{
      ruleset: ruleset
    } do
      epic_general = %{kind: :epic_general, class: nil, epic?: true}

      assert Labels.slot_label(ruleset, epic_general) == "Общий · эпик"
      assert Labels.slot_ladder_label(ruleset, epic_general) == "общий фит · эпик"
      assert Labels.slot_delta_label(ruleset, epic_general) == "общий фит · эпик"

      # Ни одна из трёх подписей не говорит просто «эпический фит» — это была
      # ровно та формулировка, которую баг 1.4 нашёл вводящей в заблуждение.
      refute Labels.slot_ladder_label(ruleset, epic_general) == "эпический фит"
      refute Labels.slot_delta_label(ruleset, epic_general) == "эпический фит"
    end

    # Положительный контроль к тесту выше: до 20-го подпись остаётся прежней
    # и без пометки — иначе обе проверки зеленели бы и у реализации,
    # приписавшей «· эпик» всем общим слотам подряд, а не только эпическим.
    test "до 20-го уровня общий слот подписан без пометки «эпик»", %{ruleset: ruleset} do
      general = %{kind: :general, class: nil, epic?: false}

      refute Labels.slot_ladder_label(ruleset, general) =~ "эпик"
      refute Labels.slot_delta_label(ruleset, general) =~ "эпик"
    end

    test "глифы алфавита §6 различимы: ✦ общий, ★ эпический, ⚔ бонусный", %{ruleset: ruleset} do
      _ = ruleset

      assert Labels.slot_glyph(%{kind: :general}) == "✦"
      assert Labels.slot_glyph(%{kind: :racial}) == "✦"
      assert Labels.slot_glyph(%{kind: :epic_general}) == "★"

      # ⚠️ С селектором текстового начертания U+FE0E: без него macOS подставляет
      # цветную эмодзи, и цвет класса на глиф уже не ложится.
      assert Labels.slot_glyph(%{kind: :class_bonus, class: :fighter}) == "⚔︎"

      # Эпический бонусный остаётся ⚔: на 24-м уровне у воина эпический общий
      # и эпический бонусный стоят рядом, и одинаковый глиф вернул бы ровно ту
      # путаницу, которую всё это чинит. «Эпик» у него уезжает в текст.
      assert Labels.slot_glyph(%{kind: :class_bonus, class: :fighter, epic?: true}) == "⚔︎"
    end

    test "имя класса в лестнице короткое — там 316px", %{ruleset: ruleset} do
      slot = %{kind: :class_bonus, class: :dwarven_defender, epic?: false}

      assert Labels.slot_ladder_label(ruleset, slot) == "фит DD"
    end

    # Вызывающие, у которых на руках только форма слота (id без уровня),
    # передают карту без `epic?` — и должны получать обычную формулировку,
    # а не падение.
    test "слот без поля epic? называется обычным, а не роняет вызов", %{ruleset: ruleset} do
      assert Labels.slot_label(ruleset, %{kind: :class_bonus, class: :fighter}) ==
               "Бонус Fighter"

      assert Labels.slot_delta_label(ruleset, %{kind: :class_bonus, class: :fighter}) ==
               "бонус Fighter"
    end
  end

  describe "имя фита вместе с выбором" do
    test "пара печатается как её пишет сообщество", %{ruleset: ruleset} do
      assert Labels.feat_pick_name(ruleset, {:spell_focus, :evocation}) ==
               "Spell focus (Evocation)"

      assert Labels.feat_pick_name(ruleset, {:favored_enemy, :goblinoid}) ==
               "Favored enemy (Goblinoid)"
    end

    test "голый атом печатается ровно как раньше — скобка не дорисовывается",
         %{ruleset: ruleset} do
      assert Labels.feat_pick_name(ruleset, :toughness) == Labels.feat_name(ruleset, :toughness)
      assert Labels.feat_pick_name(ruleset, :toughness) == "Toughness"
    end

    test "имя значения берётся из справочника даже там, где блока имён нет",
         %{ruleset: ruleset} do
      # ⚠️ `skill` резолвится в словарь ruleset'а, а не в файл со списком имён,
      # и без отдельной ветки печаталось бы `(move_silently)`.
      assert Labels.feat_pick_name(ruleset, {:skill_focus, :move_silently}) ==
               "Skill focus (Move silently)"
    end

    test "значение вне справочника показывается как есть, а не выдумывается",
         %{ruleset: ruleset} do
      # Честнее придуманного написания, и сразу видно, что справочник неполон.
      assert Labels.feat_pick_name(ruleset, {:spell_focus, :nonexistent}) ==
               "Spell focus (nonexistent)"
    end

    test "счётчик появляется со второго взятия, а не с первого", %{ruleset: ruleset} do
      assert Labels.feat_pick_name(ruleset, :epic_toughness, 1) == "Epic toughness"
      assert Labels.feat_pick_name(ruleset, :epic_toughness, 3) == "Epic toughness ×3"

      assert Labels.feat_pick_name(ruleset, {:epic_energy_resistance, :fire}, 2) ==
               "Epic energy resistance (Fire) ×2"
    end

    test "выпавший из ссылки выбор назван словами, а не кортежем", %{ruleset: _ruleset} do
      text = Labels.dropped([{:unknown_choice, "spell_focus|elocution"}])

      assert text =~ "spell_focus|elocution"
      refute text =~ "unknown_choice"
    end

    # Куски мини-сетов (задача 3.185) — та же линия: сырого тапла на экране
    # быть не должно, а строка обязана быть названа ЦЕЛИКОМ, иначе игрок
    # не поймёт, что именно из ссылки выпало.
    test "выпавшие куски мини-сетов названы словами, а не кортежем" do
      text = Labels.dropped([{:unknown_mini_sets, "miniset|2,x,2"}])

      assert text =~ "miniset|2,x,2"
      refute text =~ "unknown_mini_sets"
    end

    # Прибавка с ключом 0 (задача 4.38, `Encoding.to_increases/3`).
    test "выпавшая прибавка с ключом 0 названа словами, а не кортежем" do
      text = Labels.dropped([{:unknown_increase, "0|dex"}])

      assert text == "прибавка к характеристике 0|dex"
    end

    # Задача 4.35: четыре вида, которые флеш «Из ссылки выпало: …» печатал
    # сырым `inspect` — `{:unknown_weapon, "scimitor"}`. Значения — ровно те,
    # что кладёт декодер (`encoding_test.exs`: оружие — id, остальные три —
    # строка целиком со своим ключом).
    test "выпавшее оружие названо словами" do
      assert Labels.dropped([{:unknown_weapon, "scimitor"}]) == "оружие scimitor"
    end

    test "выпавшие крафтовые вещи названы словами" do
      assert Labels.dropped([{:unknown_named_items, "nameditems|x"}]) ==
               "крафтовые вещи nameditems|x"
    end

    test "выпавшие раздельные спасы названы словами" do
      assert Labels.dropped([{:unknown_saves_specific, "savespec|2,3,x"}]) ==
               "спасы Fort / Ref / Will с экипировки savespec|2,3,x"
    end

    test "выпавшее поглощение стихии названо словами" do
      assert Labels.dropped([{:unknown_resistances, "resist|magical|15"}]) ==
               "поглощение стихии resist|magical|15"
    end

    test "флеш целиком: подпись и список через запятую" do
      assert Labels.dropped_message([
               {:unknown_weapon, "scimitor"},
               {:unknown_resistances, "resist|fyre|15"}
             ]) == "Из ссылки выпало: оружие scimitor, поглощение стихии resist|fyre|15"
    end

    # На ванили интерфейс английский (VANILLA.md §1): те же подписи — msgid.
    test "по-английски — английские подписи" do
      Gettext.put_locale(BuildCalculatorWeb.Gettext, "en")

      assert Labels.dropped_message([
               {:unknown_weapon, "longswore"},
               {:unknown_named_items, "nameditems|x"},
               {:unknown_saves_specific, "savespec|2,3,x"},
               {:unknown_resistances, "resist|fyre|15"}
             ]) ==
               "Dropped from the link: weapon longswore, crafted items nameditems|x, " <>
                 "Fort / Ref / Will from gear savespec|2,3,x, elemental resistance resist|fyre|15"
    after
      Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")
    end

    # Сторож: КАЖДЫЙ вид потери, который объявляет декодер (тип `dropped`
    # в `BuildCalculator.Encoding`), назван словами. Новый вид без подписи
    # иначе доехал бы до игрока сырым кортежем — так четыре вида и прожили
    # до задачи 4.35. Список видов — из самого типа, не переписан сюда руками.
    test "у каждого вида потери из типа `Encoding.dropped` — свои слова" do
      {:ok, types} = Code.Typespec.fetch_types(BuildCalculator.Encoding)

      [kinds] =
        for {:type, {:dropped, {:type, _, :tuple, [{:type, _, :union, atoms}, _value]}, []}} <-
              types,
            do: for({:atom, _, kind} <- atoms, do: kind)

      assert length(kinds) >= 13

      for kind <- kinds do
        text = Labels.dropped([{kind, "проба|1"}])

        assert text =~ "проба|1"
        refute text =~ Atom.to_string(kind), "#{kind}: подписи нет, печатается #{text}"
        refute text =~ "{", "#{kind}: подписи нет, печатается #{text}"
      end
    end
  end

  # 🔴 Ложная легальность НА ЭКРАНЕ, найденная 11.08.2026: `ladder_issues/2`
  # фильтрует претензии ядра белым списком `@illegal_reasons`, и трёх голов
  # семейства «фит взят там, где его взять нельзя» в нём не было ни одной.
  # `:forbidden_by_class` держит 229 пар запрета со страниц классов — то есть
  # молчали не редкие случаи, а самый массовый механизм запрета.
  #
  # ⚠️ Обе половины под ОДНИМ тестом намеренно: проверка «претензия ядра
  # доезжает до лестницы» поодиночке зеленеет и на слишком широком фильтре
  # (пропускающем `:missing_data`), а проверка «`:missing_data` не доезжает» —
  # на фильтре, не пропускающем вообще ничего. Именно этим сломанное состояние
  # и выглядело правильным.
  describe "ladder_issues/2 — претензия ядра доезжает до отметки уровня" do
    test "«фит взят на уровне, где его нельзя» помечает уровень, а `missing_data` — нет",
         %{ruleset: ruleset} do
      # Варвар 20 / воин 4. `Mighty rage` требует варвар 20 и 21-й уровень
      # персонажа — оба выполнены, — но брать его можно ТОЛЬКО на уровне
      # варвара, а 24-й взят воином. Характеристики подняты так, чтобы
      # `{:forbidden_by_class, …}` осталась ЕДИНСТВЕННОЙ претензией: иначе
      # уровень пометили бы соседние причины и тест зеленел бы впустую.
      #
      # ⚠️ Силу и телосложение до 21 добирает САМ БИЛД, а не пояс, и это правка
      # 16.08.2026 (`GAME_CHECKS.md` S1): раньше требование по характеристике
      # читало значение вместе с вещами, и фикстура опиралась на `+12/+12`
      # с предмета. Теперь требование стоит на базовом значении, поэтому раса
      # сменилась на Гнома (`Dwarf`, +2 телосложения) и разложение стало
      # ЗАКОННЫМ по поинт-баю: 18 силы (16 очков) + 17 телосложения (13) = 29
      # из 30. Вещи оставлены на месте намеренно — они больше не решают ничего,
      # и тест это показывает: `+12/+12` в билде есть, а претензия по-прежнему
      # ровно одна и не про характеристики.
      build =
        Build.new(
          race: :dwarf,
          alignment: :neutral,
          base_abilities: %{str: 18, dex: 8, con: 17, int: 8, wis: 8, cha: 8},
          levels: List.duplicate(:barbarian, 20) ++ List.duplicate(:fighter, 4),
          ability_increases: %{4 => :str, 8 => :str, 12 => :con, 16 => :con, 20 => :str},
          gear: %Rules.Gear{abilities: %{str: 12, con: 12}},
          feats: %{24 => %{general: {:mighty_rage, nil}}}
        )

      # Положительный контроль к утверждению «претензия ровно одна»: если ядро
      # начнёт называть здесь что-то ещё, тест обязан упасть, а не тихо пройти
      # за счёт чужой причины.
      assert [{24, :general, :mighty_rage, {:forbidden_by_class, :fighter}}] =
               Rules.illegal_feats(build, ruleset)

      issues = Labels.ladder_issues(ruleset, build)

      assert Map.keys(issues) == [24]
      assert [text] = issues[24]
      assert text =~ "Mighty rage"
      assert text =~ "Fighter"

      # Вторая половина, на НАСТОЯЩЕМ билде, а не на тестовом аксессоре:
      # «не смогли решить» — не нарушение, и уровень им не помечается, иначе
      # ложную легальность обменяли бы на ложную нелегальность.
      #
      # ⚠️ Носитель сменился 25.08.2026 (задача 3.104): здесь стоял `Skill focus`,
      # чьё «able to use the skill» ядро не читало и потому отбивало фит ВСЕМ.
      # Потом стоял `Extra turning` с остатком «exclusive to clerics, paladins».
      #
      # ⚠️ И сменился ещё раз 03.10.2026 (задача 4.55): остаток `Extra turning`
      # прочитан — это ограничение по уровню взятия, которое страницы классов
      # уже несли (`vanilla/feat_requirements.json`), а клирику 1 фит доступен
      # по замеру AG1. Живых носителей у СЛОТОВОГО фита больше нет: шесть
      # оставшихся `unparsed` — классовые и расовые выдачи, их не держит ни
      # один пул слотов, и ядро называет это своей причиной
      # (`{:not_slottable, …}`). Поэтому носитель синтетический — непрочитанный
      # остаток подложен общему фиту в копии ruleset'а (CLAUDE.md §9: форму без
      # живых носителей держит синтетика). Правило под тестом то же: «не смогли
      # решить» уровень не помечает.
      unread_ruleset =
        put_in(ruleset.feats[:alertness].prereqs, %{
          "unparsed" => ["a requirement nobody could read"]
        })

      unread =
        Build.new(
          race: :human,
          alignment: :neutral,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 10},
          levels: List.duplicate(:cleric, 10),
          feats: %{3 => %{general: {:alertness, nil}}}
        )

      assert [
               {3, :general, :alertness, {:missing_data, {:feat_prerequisites, :alertness}}}
             ] = Rules.illegal_feats(unread, unread_ruleset)

      assert Labels.ladder_issues(unread_ruleset, unread) == %{}

      # Положительный контроль подлога: на настоящем ruleset'е тот же билд
      # чист, то есть претензию выше дал именно подложенный остаток.
      assert Rules.illegal_feats(unread, ruleset) == []
    end

    # 🔴 Ложная легальность НА ЭКРАНЕ, найденная Dan 24.08.2026 (задача 3.84),
    # и в точности того же вида, что `:forbidden_by_class` выше: ядро молчало,
    # поэтому и лестница молчала. Сценарий дословно: поднял уровни, не заполняя
    # фиты; взял `Blind fight` на позднем уровне; вернулся к пустой строке
    # на РАННЕМ и взял его ещё раз. В лестнице поздний уровень показался как
    # `Blind fight ×2`, а фит берётся однажды.
    #
    # ⚠️ Обе половины одним тестом, по тому же доводу, что у теста выше: «дубль
    # доезжает» поодиночке зеленеет и на фильтре, пропускающем всё подряд,
    # а «пик без записанного выбора не доезжает» — на фильтре, не пропускающем
    # ничего.
    test "дубль неповторяемого фита помечает уровень, а пик без выбора — нет",
         %{ruleset: ruleset} do
      base =
        Build.new(
          race: :human,
          alignment: :lawful_good,
          base_abilities: %{str: 14, dex: 14, con: 12, int: 10, wis: 10, cha: 8},
          levels: List.duplicate(:fighter, 9)
        )

      dup =
        base
        |> Rules.Build.put_feat(6, :general, :blind_fight)
        |> Rules.Build.put_feat(3, :general, :blind_fight)

      # Положительный контроль к «претензия ровно одна»: обвинён ПОЗДНИЙ
      # уровень, и другой причины на строке нет.
      assert [{6, :general, :blind_fight, {:already_taken, :blind_fight}}] =
               Rules.illegal_feats(dup, ruleset)

      issues = Labels.ladder_issues(ruleset, dup)

      assert Map.keys(issues) == [6]
      assert [text] = issues[6]
      assert text =~ "Blind fight"
      refute text =~ "already_taken"

      # ⚠️ Вторая половина: `{:requires_choice, …}` до лестницы не доезжает —
      # ядро гасит её у поставленного пика само, потому что это про НАШУ
      # запись, а не про персонажа. Билд с `Weapon focus` без названного оружия
      # законен, и вставленный текстом он ровно такой.
      bare = Rules.Build.put_feat(base, 1, :general, :weapon_focus)

      assert Rules.illegal_feats(bare, ruleset) == []
      assert Labels.ladder_issues(ruleset, bare) == %{}
    end
  end

  # 🔴 Найдено разведкой при замере ДРУГОГО запроса Dan (размер значка
  # `.lv-illegal`, CLAUDE.md §6/§3, задача 3.117) — не заказано, но бросается
  # в глаза сразу после импорта. Игровой лог `.билд` не переносит
  # мировоззрение (решение Dan 27.08.2026), поле остаётся `nil`; класс с
  # ограничением по мировоззрению перепроверяется на КАЖДОМ своём уровне, не
  # только на первом (та же машинерия, что ловит снятую задним числом
  # характеристику, задача 1.3), и `nil` проигрывает требованию всегда.
  # У Бабуки (35 уровней Barbarian) это давало 35 одинаковых значков
  # «Barbarian: нужно не Lawful» — фразу, которая звучит как «ты выбрал не
  # то», хотя игрок не выбирал ничего.
  describe "ladder_issues/2 — невыбранное мировоззрение не повторяет один и тот же значок (задача 3.117)" do
    test "35 уровней варвара без мировоззрения дают ОДНУ отметку на 1-м уровне, а не 35", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: nil,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 8},
          levels: List.duplicate(:barbarian, 35)
        )

      # Положительный контроль к «до консолидации их было 35»: без него тест
      # ниже мог бы зеленеть и в мире, где ядро само перестало жаловаться.
      class_reasons = Rules.illegal_class_levels(build, ruleset)
      assert length(class_reasons) == 35
      assert Enum.all?(class_reasons, &match?({_, :barbarian, {:requires_alignment, _}}, &1))
      assert Rules.illegal_feats(build, ruleset) == []

      issues = Labels.ladder_issues(ruleset, build)

      assert Map.keys(issues) == [1]
      assert [text] = issues[1]
      assert text =~ "Barbarian"
      assert text =~ "не выбрано"

      # ⚠️ Старая формулировка звучит как «ты выбрал не то» — игрок не
      # выбирал ничего. Спецификация («не Lawful») остаётся в тексте как
      # полезная деталь («вот что понадобится»), поэтому проверка — на
      # СТАРУЮ фразу целиком, а не на подстроку внутри новой.
      refute text == "Barbarian: нужно не Lawful"
    end

    # Разводит «не выбрано» и «выбрано, но не подходит» — сворачивать НАСТОЯЩИЙ
    # конфликт мировоззрений в одну строку значило бы прятать нарушение
    # (CLAUDE.md §6: недоступное показывается с причиной, а не молчанием).
    test "выбранное, но несовместимое мировоззрение остаётся отдельной отметкой на каждом уровне",
         %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 8},
          levels: List.duplicate(:barbarian, 5)
        )

      issues = Labels.ladder_issues(ruleset, build)

      assert Map.keys(issues) == [1, 2, 3, 4, 5]

      for level <- 1..5 do
        assert [text] = issues[level]
        assert text =~ "нужно не Lawful"
        refute text =~ "не выбрано"
      end
    end

    # Положительный контроль ко всему разделу: то же тело билда с совместимым
    # мировоззрением не отмечает ни одного уровня вовсе.
    test "совместимое мировоззрение не отмечает ни одного уровня", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :chaotic_good,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 8},
          levels: List.duplicate(:barbarian, 5)
        )

      assert Labels.ladder_issues(ruleset, build) == %{}
    end
  end

  # Задача 4.38: блок честности экрана просмотра говорит ещё и ОТКУДА нарушения
  # берутся. Прибавку не на своём уровне оставляет не правка, а старая ссылка
  # из импорта текста, — и прежняя единственная фраза («след правки более
  # раннего решения») о ней говорила неверно.
  describe "ladder_issue_notes/1 — фраза по виду нарушения (задача 4.38)" do
    # Варвар 5: с `lawful_good` каждый уровень нарушает требование класса
    # (`:class`), с `chaotic_good` — ни один. Прибавка на 5-м, который её
    # не даёт, — `:increase`.
    defp barbarian(ruleset, alignment, increases) do
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: alignment,
        base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 8},
        levels: List.duplicate(:barbarian, 5),
        ability_increases: increases
      )
    end

    @edit "Обычно это след правки более раннего решения"
    @increase "не след правки: конструктор такую не ставит"

    test "только прибавка не на своём уровне — фраза про прибавку, не про правку",
         %{ruleset: ruleset} do
      build = barbarian(ruleset, :chaotic_good, %{4 => :str, 5 => :dex})
      entries = Labels.ladder_issue_entries(ruleset, build)

      assert [{5, :increase, _text}] = entries
      assert [{:increase, text}] = Labels.ladder_issue_notes(entries)
      assert text =~ @increase
      assert text =~ "на её уровне"
      refute text =~ @edit
    end

    test "только классы — прежняя фраза про правку, слово в слово", %{ruleset: ruleset} do
      entries =
        Labels.ladder_issue_entries(ruleset, barbarian(ruleset, :lawful_good, %{4 => :str}))

      assert Enum.all?(entries, &match?({_level, :class, _text}, &1))

      assert Labels.ladder_issue_notes(entries) == [
               {:edit,
                "Обычно это след правки более раннего решения — снятого фита, смены расы " <>
                  "или мировоззрения, — которая не задела уровни, уже стоящие в лестнице."}
             ]
    end

    test "оба вида — обе фразы, правка первой", %{ruleset: ruleset} do
      build = barbarian(ruleset, :lawful_good, %{4 => :str, 5 => :dex})
      notes = ruleset |> Labels.ladder_issue_entries(build) |> Labels.ladder_issue_notes()

      assert [{:edit, edit}, {:increase, increase}] = notes
      assert edit =~ @edit
      assert increase =~ @increase
    end

    # Записи с видом — та же прогонка, что `ladder_issues/2`, до группировки:
    # экран просмотра группирует их сам и обязан пометить те же строки.
    test "группировка записей — ровно `ladder_issues/2`; у законного билда пусто",
         %{ruleset: ruleset} do
      build = barbarian(ruleset, :lawful_good, %{4 => :str, 5 => :dex})
      entries = Labels.ladder_issue_entries(ruleset, build)

      assert Labels.group_ladder_issues(entries) == Labels.ladder_issues(ruleset, build)
      assert Map.keys(Labels.ladder_issues(ruleset, build)) == [1, 2, 3, 4, 5]

      legal = barbarian(ruleset, :chaotic_good, %{4 => :str})
      assert Labels.ladder_issue_entries(ruleset, legal) == []
      assert Labels.ladder_issue_notes([]) == []
    end
  end

  # 🔴 Задача 4.60 — та же ложная легальность на экране, что 11.08.2026
  # и 24.08.2026 выше: ядро называло у поставленного пика `feat_disabled`,
  # `not_selectable_at_level_up` и `not_slottable`, а белый список их не
  # пропускал. Экран (лестница, лента, просмотр) — `builder_closed_feat_test.exs`;
  # здесь — вид прогонки, фраза происхождения и ваниль.
  describe "ladder_issues/2 — фит, которого слотом не взять вовсе (задача 4.60)" do
    # Человек, воин 1, Mount actions в общем слоте: по правилам до 4.49
    # законно, сегодня — единственная претензия `not_selectable_at_level_up`.
    defp mount_actions(ruleset, fields \\ []) do
      Build.new(
        [
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: [:fighter],
          base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8},
          feats: %{1 => %{general: :mount_actions}}
        ] ++ fields
      )
    end

    @closed "при росте персонажа не выбирается — только объявить в «Вещах»"

    test "Сиала: уровень помечен, вид — `:feat_closed`, фраза — про старую ссылку",
         %{ruleset: ruleset} do
      build = mount_actions(ruleset)

      # Положительный контроль «претензия ровно одна»: ⚠ ставит новая голова.
      assert [{1, :general, :mount_actions, {:not_selectable_at_level_up, :mount_actions}}] =
               Rules.illegal_feats(build, ruleset)

      entries = Labels.ladder_issue_entries(ruleset, build)

      assert entries == [{1, :feat_closed, "Mount actions: " <> @closed}]
      assert Labels.ladder_issues(ruleset, build) == %{1 => ["Mount actions: " <> @closed]}

      assert [{:rules, note}] = Labels.ladder_issue_notes(entries)
      assert note =~ "не след правки"
      assert note =~ "собранные до обновления правил"
      refute note =~ "Обычно это след правки"
    end

    # Подпись одна на два места: строка выбора фитов (имя уже в строке) и
    # лестница (имя перед двоеточием). До 4.60 у `Labels` была своя, именная,
    # с «только с предмета» — о Mount actions и Mounted * это неправда.
    test "подпись `not_selectable` — путь конструктора, одна у выбора фитов и лестницы",
         %{ruleset: ruleset} do
      reason = {:not_selectable_at_level_up, :mounted_combat}

      assert Labels.reason(reason, ruleset) == @closed
      assert Feats.reason(reason, ruleset) == @closed
    end

    # ⚠️ Devastating critical — без оружия: с оружием рядом встают
    # `requires_same_choice` (нет Improved и Overwhelming critical на нём),
    # а они вида `:feat`. Законный носитель целиком, воин 22 со всей
    # цепочкой, — в `builder_closed_feat_test.exs`.
    test "у `feat_disabled` и `not_slottable` тот же вид", %{ruleset: ruleset} do
      disabled = mount_actions(ruleset, feats: %{1 => %{general: :devastating_critical}})

      assert [
               {1, :feat_closed,
                "Devastating critical: фит Devastating critical на Сиале отключён"}
             ] =
               Labels.ladder_issue_entries(ruleset, disabled)

      racial = mount_actions(ruleset, feats: %{1 => %{general: :quick_to_master}})

      assert [{1, :feat_closed, "Quick to master: выдаётся расой, слотом не берётся"}] =
               Labels.ladder_issue_entries(ruleset, racial)
    end

    # Две фразы, когда в билде оба вида: правка снятого раньше решения и пик,
    # который правила больше не держат. Порядок — правка, прибавка, правила.
    test "смешанный билд — фраза про правку и про правила", %{ruleset: ruleset} do
      build =
        mount_actions(ruleset,
          base_abilities: %{str: 12, dex: 14, con: 14, int: 10, wis: 10, cha: 8},
          levels: [:fighter, :fighter],
          feats: %{
            1 => %{general: :mount_actions, racial: :power_attack},
            2 => %{{:class_bonus, :fighter} => :cleave}
          }
        )

      notes = ruleset |> Labels.ladder_issue_entries(build) |> Labels.ladder_issue_notes()
      assert [{:edit, _}, {:rules, _}] = notes
    end

    # Ваниль: Mount actions выдаёт каждый базовый класс на 1-м, и пик в слоте
    # лестница помечала и до 4.60 (`:already_taken`). Достижим он не был:
    # выбор фитов предлагал его заблокированным, импорт клал выданное мимо
    # слотов. Новая голова добавляет вторую строку, английскую — осмысленную.
    test "ваниль: Mount actions в слоте помечен и раньше, теперь двумя строками" do
      vanilla = Data.ruleset!("vanilla")
      build = mount_actions(vanilla)

      assert Enum.sort(Rules.illegal_feats(build, vanilla)) ==
               Enum.sort([
                 {1, :general, :mount_actions, {:not_selectable_at_level_up, :mount_actions}},
                 {1, :general, :mount_actions, {:already_taken, :mount_actions}}
               ])

      Gettext.with_locale(BuildCalculatorWeb.Gettext, "en", fn ->
        assert Labels.ladder_issues(vanilla, build) == %{
                 1 => [
                   "Mount actions: not chosen on level-up — only declared in “Gear”",
                   "Mount actions: Mount actions is already taken"
                 ]
               }
      end)
    end
  end

  # 🔴 Задача 4.61 — та же ложная легальность, шагом выше: ядро не спрашивало
  # пул КОНКРЕТНОГО слота и то, даёт ли уровень слот вообще. Экран (лестница,
  # лента, просмотр) — `builder_slot_pool_test.exs`; здесь — подписи, вид
  # прогонки, фраза происхождения и ваниль.
  describe "ladder_issues/2 — слот пика не берёт фит или его нет (задача 4.61)" do
    # Человек волшебник 5, Lore 4; Brew potion в бонусном слоте волшебника.
    defp brew_potion(ruleset) do
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: List.duplicate(:wizard, 5),
        base_abilities: %{str: 8, dex: 14, con: 14, int: 18, wis: 10, cha: 8},
        skills: %{1 => %{lore: 4}},
        feats: %{5 => %{{:class_bonus, :wizard} => :brew_potion}}
      )
    end

    @pool "Brew potion: нет в списке бонусных фитов Wizard"

    test "Сиала: вид `:feat_closed`, фраза — про старую ссылку и про слот, а не «ни один»",
         %{ruleset: ruleset} do
      entries = Labels.ladder_issue_entries(ruleset, brew_potion(ruleset))

      assert entries == [{5, :feat_closed, @pool}]

      assert [{:rules, note}] = Labels.ladder_issue_notes(entries)
      assert note =~ "Фит в слоте, который по нынешним правилам его не берёт"

      # До 4.61 фраза говорила «не берёт ни один слот» — про Brew potion неправда:
      # общий слот того же уровня его берёт.
      refute note =~ "ни один слот"
    end

    test "ваниль: тот же билд законен — бонусный список Brew potion там Волшебник" do
      vanilla = Data.ruleset!("vanilla")

      assert Rules.illegal_feats(brew_potion(vanilla), vanilla) == []
      assert Labels.ladder_issues(vanilla, brew_potion(vanilla)) == %{}
    end

    test "подпись по слоту: список бонусных фитов класса — или общих", %{ruleset: ruleset} do
      assert Labels.reason({:not_in_slot_pool, {:class_bonus, :wizard}}, ruleset) ==
               "нет в списке бонусных фитов Wizard"

      assert Labels.reason({:not_in_slot_pool, {:class_bonus, :ranger, 2}}, ruleset) ==
               "нет в списке бонусных фитов Ranger"

      for slot <- [:general, :racial] do
        assert Labels.reason({:not_in_slot_pool, slot}, ruleset) == "нет в списке общих фитов"
      end

      # Выбор фитов той же фразой — делегат, своей у него нет.
      assert Feats.reason({:not_in_slot_pool, :general}, ruleset) == "нет в списке общих фитов"

      Gettext.with_locale(BuildCalculatorWeb.Gettext, "en", fn ->
        assert Labels.reason({:not_in_slot_pool, {:class_bonus, :wizard}}, ruleset) ==
                 "not on the Wizard bonus feat list"

        assert Labels.reason({:not_in_slot_pool, :general}, ruleset) ==
                 "not on the general feat list"
      end)
    end

    test "слота нет: подпись называет слот так, как его подписывает чип", %{ruleset: ruleset} do
      assert Labels.reason({:slot_not_granted, :racial}, ruleset) ==
               "этот уровень не даёт слота «Бонус расы»"

      assert Labels.reason({:slot_not_granted, {:class_bonus, :fighter}}, ruleset) ==
               "этот уровень не даёт слота «Бонус Fighter»"

      assert Labels.reason({:slot_not_granted, {:class_bonus, :ranger, 2}}, ruleset) ==
               "этот уровень не даёт слота «Бонус Ranger · 2»"

      assert Labels.reason({:slot_not_granted, :general}, ruleset) ==
               "этот уровень не даёт слота «Общий»"

      Gettext.with_locale(BuildCalculatorWeb.Gettext, "en", fn ->
        assert Labels.reason({:slot_not_granted, :racial}, ruleset) ==
                 "this level grants no “Racial” slot"
      end)
    end

    # Пропавший слот — след ПРАВКИ (смена расы), поэтому вид `:feat` и фраза
    # `:edit`, а не «старая ссылка»: та обещала бы «убрать на его уровне».
    test "слота нет — вид `:feat`, фраза про правку", %{ruleset: ruleset} do
      %Build{} = wizard = brew_potion(ruleset)
      elf = %Build{wizard | race: :elf, feats: %{1 => %{racial: :dodge}}}

      entries = Labels.ladder_issue_entries(ruleset, elf)

      assert entries == [{1, :feat, "Dodge: этот уровень не даёт слота «Бонус расы»"}]
      assert [{:edit, _}] = Labels.ladder_issue_notes(entries)
    end

    # Задача 4.62: снятый пик называется той же фразой причины, что ⚠ лестницы,
    # с уровнем и с выбором — заметка под правкой и флеш ссылки читают одно.
    test "снятый пик: уровень, фит с выбором, фраза причины лестницы", %{ruleset: ruleset} do
      assert Labels.lost_slot_pick(ruleset, {1, :racial, :dodge}) ==
               "уровень 1: Dodge — этот уровень не даёт слота «Бонус расы»"

      assert Labels.lost_slot_pick(ruleset, {4, {:class_bonus, :fighter}, {:weapon_focus, :club}}) =~
               ~r/^уровень 4: Weapon focus \(.+\) — этот уровень не даёт слота «Бонус Fighter»$/

      # Флеш ссылки: вид `:slot_not_granted` приходит словами и печатается как есть.
      text = Labels.lost_slot_pick(ruleset, {1, :racial, :dodge})

      assert Labels.dropped_message([{:unknown_weapon, "scimitor"}, {:slot_not_granted, text}]) ==
               "Из ссылки выпало: оружие scimitor, " <> text

      Gettext.with_locale(BuildCalculatorWeb.Gettext, "en", fn ->
        assert Labels.lost_slot_pick(ruleset, {1, :racial, :dodge}) ==
                 "level 1: Dodge — this level grants no “Racial” slot"
      end)
    end

    # Задача 4.63: слот известного заклинания — «N-е новое заклинание круга C»,
    # и ядро говорит, сколько их уровень даёт: ноль — «не даёт», иначе «только N».
    test "слота заклинания нет: фраза по счёту ядра, обе формы и оба языка", %{
      ruleset: ruleset
    } do
      assert Labels.reason({:spell_slot_not_granted, 0, 0}, ruleset) ==
               "этот уровень не даёт заклинаний 0 круга"

      assert Labels.reason({:spell_slot_not_granted, 0, 1}, ruleset) ==
               "этот уровень даёт только 1 заклинание 0 круга"

      assert Labels.reason({:spell_slot_not_granted, 1, 2}, ruleset) ==
               "этот уровень даёт только 2 заклинания 1 круга"

      assert Labels.reason({:spell_slot_not_granted, 1, 5}, ruleset) ==
               "этот уровень даёт только 5 заклинаний 1 круга"

      assert Labels.reason({:not_on_spell_list, :bard, 0}, ruleset) ==
               "нет в списке заклинаний 0 круга Bard"

      assert Labels.lost_spell_pick(
               ruleset,
               {1, {:circle, 0, 0}, :electric_jolt, {:spell_slot_not_granted, 0, 0}}
             ) == "уровень 1: Electric jolt — этот уровень не даёт заклинаний 0 круга"

      # Флеш ссылки: тот же вид `:slot_not_granted`, словами.
      text =
        Labels.lost_spell_pick(
          ruleset,
          {2, {:circle, 0, 3}, :daze, {:spell_slot_not_granted, 0, 1}}
        )

      assert text == "уровень 2: Daze — этот уровень даёт только 1 заклинание 0 круга"
      assert Labels.dropped_message([{:slot_not_granted, text}]) == "Из ссылки выпало: " <> text

      Gettext.with_locale(BuildCalculatorWeb.Gettext, "en", fn ->
        assert Labels.reason({:spell_slot_not_granted, 0, 0}, ruleset) ==
                 "this level grants no level 0 spells"

        assert Labels.reason({:spell_slot_not_granted, 0, 1}, ruleset) ==
                 "this level grants only 1 level 0 spell"

        assert Labels.reason({:spell_slot_not_granted, 1, 2}, ruleset) ==
                 "this level grants only 2 level 1 spells"

        assert Labels.reason({:not_on_spell_list, :bard, 0}, ruleset) ==
                 "not on the Bard level 0 spell list"

        assert Labels.lost_spell_pick(
                 ruleset,
                 {1, {:circle, 0, 0}, :electric_jolt, {:spell_slot_not_granted, 0, 0}}
               ) == "level 1: Electric jolt — this level grants no level 0 spells"
      end)
    end

    # Заклинание, которого уровень не держит, — четвёртая прогонка, вид `:spell`,
    # фраза происхождения `:edit` (оставляет его смена класса раннего уровня).
    test "заклинание не по уровню — вид `:spell`, фраза про правку", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :true_neutral,
          levels: [:bard],
          base_abilities: %{str: 8, dex: 14, con: 14, int: 10, wis: 10, cha: 18},
          spells: %{1 => %{{:circle, 0, 0} => :electric_jolt, {:circle, 1, 0} => :grease}}
        )

      entries = Labels.ladder_issue_entries(ruleset, build)

      assert entries == [
               {1, :spell, "Electric jolt: нет в списке заклинаний 0 круга Bard"},
               {1, :spell, "Grease: этот уровень не даёт заклинаний 1 круга"}
             ]

      assert [{:edit, _}] = Labels.ladder_issue_notes(entries)
    end

    # Задача 4.64: повтор известного заклинания у одного класса — у позднего
    # пика, вид `:spell`, фраза происхождения `:edit`; уровень в подписи — того
    # пика, который остаётся. Оба языка.
    test "повтор заклинания — «уже выбрано на уровне N», вид `:spell`", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :true_neutral,
          levels: [:sorcerer, :sorcerer],
          base_abilities: %{str: 8, dex: 14, con: 14, int: 10, wis: 10, cha: 18},
          spells: %{1 => %{{:circle, 0, 0} => :daze}, 2 => %{{:circle, 0, 0} => :daze}}
        )

      entries = Labels.ladder_issue_entries(ruleset, build)

      assert entries == [{2, :spell, "Daze: уже выбрано на уровне 1"}]
      assert [{:edit, _}] = Labels.ladder_issue_notes(entries)

      assert Labels.reason({:spell_already_known, :sorcerer, 2}, ruleset) ==
               "уже выбрано на уровне 2"

      Gettext.with_locale(BuildCalculatorWeb.Gettext, "en", fn ->
        assert Labels.reason({:spell_already_known, :sorcerer, 2}, ruleset) ==
                 "already chosen at level 2"
      end)
    end

    # Эпический фит в слоте неэпического персонажа — та же голова, что у
    # требования уровня из блока фита: и подпись, и вид прогонки те же.
    test "эпический фит на 18-м уровне — «нужен 21-й уровень», вид `:feat`", %{
      ruleset: ruleset
    } do
      monk =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_neutral,
          levels: List.duplicate(:monk, 18),
          base_abilities: %{str: 12, dex: 14, con: 12, int: 10, wis: 18, cha: 8},
          ability_increases: Map.new([4, 8, 12, 16], &{&1, :wis}),
          feats: %{18 => %{general: :improved_ki_strike_4}}
        )

      assert Labels.ladder_issue_entries(ruleset, monk) == [
               {18, :feat, "Improved ki strike 4: нужен 21-й уровень"}
             ]
    end
  end

  describe "feat_info/2 — «что делает фит» (задача 3.87)" do
    test "an ordinary vanilla feat carries its Fandom description, markup stripped", %{
      ruleset: ruleset
    } do
      info = Labels.feat_info(ruleset, :alertness)

      assert info.description ==
               "+2 bonus to spot and listen checks due to finely tuned senses."

      refute info.description =~ "[["
      refute info.siala_changed?
      assert info.siala_notes == []
      assert info.siala_notes_more_text == nil
      assert info.source_url == "https://nwn.fandom.com/wiki/Alertness"
      assert info.source_link_text =~ "Alertness"
      assert info.source_link_text =~ "Fandom"
    end

    # `Evasion` is one of twelve vanilla feats whose shard change carries a
    # `siala_note` (CLAUDE.md §3) — the one `what` this popover ever quotes,
    # because it is the one kind of change that is about what the feat *does*
    # rather than about who may take it or when (already shown elsewhere on
    # the same row).
    test "a feat the shard rewrote with a mechanic note is flagged and quoted", %{
      ruleset: ruleset
    } do
      info = Labels.feat_info(ruleset, :evasion)

      assert info.siala_changed?
      assert [note] = info.siala_notes
      assert note =~ "Quillfire"
      refute note =~ "[["
      assert info.siala_notes_more_text == nil
      # The vanilla description survives untouched beside the shard's note —
      # marking a feat never means inventing or discarding its Fandom text.
      assert info.description =~ "reflex save"
    end

    # `Toughness` — nine classes hand it out for free on Siala, a fact the
    # slot chip and the granted-feats line already say (CLAUDE.md §6). Its
    # `siala_changes` carry no `siala_note`, so the popover still has to flag
    # it (§3's «не молчаливое ванильное описание» covers all 83, not only
    # the twelve with a quoted mechanic) — just with nothing to quote.
    test "a feat the shard rewrote administratively (no mechanic note) is still flagged", %{
      ruleset: ruleset
    } do
      info = Labels.feat_info(ruleset, :toughness)

      assert info.siala_changed?
      assert info.siala_notes == []
      assert info.description != nil
    end

    test "the same feat is unmarked on the vanilla ruleset — the shard layer never loads there" do
      vanilla = Data.ruleset!("vanilla")
      info = Labels.feat_info(vanilla, :evasion)

      refute info.siala_changed?
      assert info.siala_notes == []
      # Fandom's own text is identical either way — only the marking differs.
      assert info.description == Labels.feat_info(Data.ruleset!("siala_41"), :evasion).description
    end

    # `Riding Sprint` — one of the eleven shard-only feats (CLAUDE.md §3, the
    # five custom weapon proficiencies plus six more). Its page is Russian
    # prose (`special_raw`), and Dan asked for it to stay empty rather than
    # translated (task 3.87) — the same call CLAUDE.md §4 already makes about
    # a shard-only page's name.
    test "a shard-only feat has no description at all", %{ruleset: ruleset} do
      assert Labels.feat_info(ruleset, :riding_sprint).description == nil
      assert Labels.feat_info(ruleset, :siala_blade_proficiency).description == nil
    end

    test "an unknown or nil id answers the same empty shape, never raises", %{ruleset: ruleset} do
      empty = %{
        description: nil,
        siala_changed?: false,
        siala_notes: [],
        siala_notes_more_text: nil,
        siala_specifics: [],
        siala_numbers_differ?: false,
        shard_page: [],
        source_url: nil,
        source_link_text: nil
      }

      assert Labels.feat_info(ruleset, nil) == empty
      assert Labels.feat_info(ruleset, :not_a_real_feat) == empty
    end

    # A synthetic record: no feat has needed the cap in the real corpus yet
    # (the busiest, `evasion`, carries exactly one `siala_note` after the
    # three `granted_at_level` facts are read on their own), but the safety
    # valve — cap the count, say how many more, the same shape
    # `Builder.Feats`'s blocked list already uses — has to hold regardless.
    test "more than four siala_note quotes are capped, with a Russian count of the rest", %{
      ruleset: ruleset
    } do
      feat = Map.fetch!(ruleset.feats, :alertness)

      changes =
        for n <- 1..6, do: %{"what" => "siala_note", "quote" => "Заметка номер #{n}"}

      info =
        Labels.feat_info(%{ruleset | feats: %{fake: %{feat | siala_changes: changes}}}, :fake)

      assert length(info.siala_notes) == 4
      assert info.siala_notes_more_text =~ "2"
    end
  end

  # Задача 4.67 (находка 4.57): у 33 страниц Сиалы «Особенности» называют
  # другие числа, чем описание Fandom, — поп-ап показывал игроку Сиалы только
  # ванильные («+1 … within 15 feet») и общее «шард фит менял». Текст шарда
  # теперь едет отдельным ключом `siala_specifics`; `siala_notes` не тронут.
  describe "feat_info/2 — текст «Особенностей» шарда (задача 4.67)" do
    test "Point blank shot на Сиале несёт текст шарда, описание Fandom — прежнее", %{
      ruleset: ruleset
    } do
      info = Labels.feat_info(ruleset, :point_blank_shot)

      assert info.siala_changed?

      assert info.siala_specifics == [
               "Персонаж, обладающий данным навыком, игнорирует штраф -4 за использование " <>
                 "оружия дальнего действия в ближнем бою и получает дополнительно +5 к атаке " <>
                 "и повреждениям стрелковым оружием, когда цель находится на расстоянии до 5 метров."
             ]

      # Описание — дословная цитата Fandom (CLAUDE.md §4), его не трогаем.
      assert info.description =~ "+1 to attack roll"
      assert info.description =~ "within 15 feet"
      # Цитаты `siala_note` у этого фита нет и не появилось.
      assert info.siala_notes == []
    end

    test "Called shot — бонус атаки +2 и штраф −3 шарда", %{ruleset: ruleset} do
      # Вторая строка — лейбл страницы вне «Особенностей» (задача 4.70).
      assert [text, _duration] = Labels.feat_info(ruleset, :called_shot).siala_specifics
      assert text =~ "с бонусом атаки +2"
      assert text =~ "штраф -3 к ловкости"
    end

    # Пять страниц «Epic energy resistance (Acid…Sonic)» ложатся на одну
    # запись, и каждая называет свою стихию — все пять на месте, без капа
    # четырёх, которым ограничены цитаты `siala_note`.
    test "Epic energy resistance — пять стихий, огонь среди них", %{ruleset: ruleset} do
      info = Labels.feat_info(ruleset, :epic_energy_resistance)

      assert length(info.siala_specifics) == 5
      assert Enum.any?(info.siala_specifics, &(&1 =~ "к урону огнем (Fire)"))
      assert Enum.all?(info.siala_specifics, &(&1 =~ "сопротивление 15"))
      assert info.siala_notes_more_text == nil
    end

    # Вики-разметка снимается так же, как у цитат `siala_note`.
    test "разметка вики из текста шарда снята", %{ruleset: ruleset} do
      assert [text, _note] = Labels.feat_info(ruleset, :rallying_cry).siala_specifics
      assert text =~ "Balagarn's iron horn"
      assert text =~ "Terrifying Rage"
      refute text =~ "[["
    end

    test "на ванили у тех же фитов текста шарда нет — как было" do
      vanilla = Data.ruleset!("vanilla")

      for id <- [:point_blank_shot, :called_shot, :epic_energy_resistance] do
        info = Labels.feat_info(vanilla, id)
        assert info.siala_specifics == [], "#{id}"
        refute info.siala_changed?, "#{id}"

        # Положительный контроль: описание есть, кружок на ванили рисуется.
        assert info.description, "#{id}"
      end
    end

    # Контроль: фит с цитатой `siala_note` (Evasion) и фит без правок шарда
    # (Alertness) — текста шарда нет, остальное прежнее. (Wholeness of body,
    # у которого «Особенности» есть, но числа совпали, стоял здесь до 4.70 —
    # теперь он носитель, см. describe ниже.)
    test "у фита с siala_note и у фита без правок шарда — без изменений", %{ruleset: ruleset} do
      evasion = Labels.feat_info(ruleset, :evasion)
      assert evasion.siala_specifics == []
      refute evasion.siala_numbers_differ?
      assert [note] = evasion.siala_notes
      assert note =~ "Quillfire"

      alertness = Labels.feat_info(ruleset, :alertness)
      assert alertness.siala_specifics == []
      refute alertness.siala_changed?
    end

    # Перепись: у каждой из 33 страниц машинного слоя с `numbers_differ: true`
    # её текст (без разметки) есть в поп-апе её записи.
    test "перепись: текст шарда появился у всех 33 страниц", %{ruleset: ruleset} do
      pages =
        "priv/rules/siala_41/generated/feats.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.fetch!("feats")
        |> Enum.filter(&(&1["numbers_differ"] == true))

      shown =
        for page <- pages,
            id = String.to_existing_atom(page["vanilla_id"] || page["id"]),
            text = Data.Loader.Reading.strip_wiki_prose(page["special_raw"]),
            text in Labels.feat_info(ruleset, id).siala_specifics,
            do: page["id"]

      assert length(pages) == 33
      assert Enum.sort(shown) == Enum.sort(Enum.map(pages, & &1["id"]))
    end
  end

  # Задача 4.70 (находки 4.67): (1) числа шарда вне «Особенностей» — другие
  # лейблы той же страницы (длительность, перезарядка, количество) — идут
  # строками после её текста, с названием лейбла, как на странице; (2) у девяти
  # страниц «Особенности» есть, а разницы чисел парсер не увидел
  # (`numbers_differ: false`) — механика всё равно шардовая, текст едет,
  # `siala_numbers_differ?` ложно, и подпись над Fandom про числа молчит.
  describe "feat_info/2 — лейблы страницы и механика шарда без разницы чисел (задача 4.70)" do
    test "Called shot — «Продолжительность: 8 секунд.» после текста шарда", %{ruleset: ruleset} do
      info = Labels.feat_info(ruleset, :called_shot)

      assert [text, "Продолжительность: 8 секунд."] = info.siala_specifics
      assert text =~ "с бонусом атаки +2"
      assert info.siala_numbers_differ?
    end

    test "Oath of wrath — длительность эффекта шарда", %{ruleset: ruleset} do
      info = Labels.feat_info(ruleset, :oath_of_wrath)

      assert [text, "Длительность эффекта: 10 + (Уровень ПДК + Мод Харизмы) * 2 секунд."] =
               info.siala_specifics

      assert text =~ "(Уровень ПДК * 10%)"
      assert info.siala_numbers_differ?
      # Описание Fandom — прежнее, дословное.
      assert info.description =~ "twice his class level"
    end

    test "у нескольких лейблов — порядок по имени, как в машинном слое", %{ruleset: ruleset} do
      assert [_text, "Количество: 1 раз за каждый уровень в классе.", "Примечание: " <> _] =
               Labels.feat_info(ruleset, :ki_damage).siala_specifics
    end

    test "Wholeness of body — Heal и Restoration шарда, числа не утверждаются", %{
      ruleset: ruleset
    } do
      info = Labels.feat_info(ruleset, :wholeness_of_body)

      assert [text] = info.siala_specifics
      assert text =~ "Лечение (Heal)"
      assert text =~ "Восстановление (Restoration)"
      assert info.siala_changed?
      refute info.siala_numbers_differ?
      assert info.siala_notes == []
      assert info.description =~ "twice her class level"
    end

    test "Weapon finesse — текст шарда, числа не утверждаются", %{ruleset: ruleset} do
      info = Labels.feat_info(ruleset, :weapon_finesse)

      assert [text] = info.siala_specifics
      assert text =~ "разного оружия"
      refute info.siala_numbers_differ?
      assert info.description =~ "light weapons"
    end

    test "Summon shadow — лейбл и у страницы без разницы чисел", %{ruleset: ruleset} do
      info = Labels.feat_info(ruleset, :summon_shadow)

      assert [_text, "Продолжительность: 1 час за уровень."] = info.siala_specifics
      refute info.siala_numbers_differ?
    end

    # «Требуется для умения» — граф пререквизитов, а не то, что фит делает.
    test "Whirlwind attack — лейбла «Требуется для умения» в поп-апе нет", %{ruleset: ruleset} do
      assert [text] = Labels.feat_info(ruleset, :whirlwind_attack).siala_specifics
      assert text =~ "в радиусе 4 футов"
    end

    # Задача 4.70, п. 3: одиночный перенос строки в исходнике MediaWiki склеивает.
    test "Epic energy resistance (Electrical) — фраза не рвётся", %{ruleset: ruleset} do
      electrical =
        ruleset
        |> Labels.feat_info(:epic_energy_resistance)
        |> Map.fetch!(:siala_specifics)
        |> Enum.find(&(&1 =~ "(Electrical)"))

      assert electrical =~ "многократно, при максимальном сопротивлении 150."
      refute electrical =~ "\n"
    end

    test "на ванили у тех же фитов — как было" do
      vanilla = Data.ruleset!("vanilla")

      for id <- [:called_shot, :oath_of_wrath, :wholeness_of_body, :weapon_finesse] do
        info = Labels.feat_info(vanilla, id)
        assert info.siala_specifics == [], "#{id}"
        refute info.siala_numbers_differ?, "#{id}"
        refute info.siala_changed?, "#{id}"
        assert info.description, "#{id}"
      end
    end

    # Пять сиальских фитов со «Особенностями», но без пары на Fandom
    # (`numbers_differ: null`): описания Fandom у них нет (3.87), и текст шарда
    # едет не здесь, а страницей — `shard_page` (задача 4.71,
    # `feat_info_shard_page_test.exs`).
    test "сиальский фит без описания Fandom — по-прежнему без описания и текста", %{
      ruleset: ruleset
    } do
      for id <- [:instinctive_throw, :riding_sprint, :teleportation] do
        info = Labels.feat_info(ruleset, id)
        assert info.description == nil, "#{id}"
        assert info.siala_specifics == [], "#{id}"
      end
    end

    # Перепись: у каждой страницы с «Особенностями» и булевым `numbers_differ`
    # в поп-апе её записи — её текст и каждый её лейбл (кроме графа).
    test "перепись: текст и лейблы у всех 42 страниц", %{ruleset: ruleset} do
      pages =
        "priv/rules/siala_41/generated/feats.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.fetch!("feats")
        |> Enum.filter(&(is_binary(&1["special_raw"]) and is_boolean(&1["numbers_differ"])))

      missing =
        for page <- pages,
            info = Labels.feat_info(ruleset, String.to_existing_atom(page["vanilla_id"])),
            line <- expected_lines(page),
            line not in info.siala_specifics,
            do: {page["id"], line}

      assert length(pages) == 42
      assert missing == []
    end
  end

  defp expected_lines(page) do
    strip = &Data.Loader.Reading.strip_wiki_prose/1

    labels =
      for {label, quote} <- Enum.sort(page["extra_labels"] || %{}),
          label != "требуется для умения" do
        {first, rest} = String.split_at(label, 1)
        String.upcase(first) <> rest <> ": " <> strip.(quote)
      end

    [strip.(page["special_raw"]) | labels]
  end
end
