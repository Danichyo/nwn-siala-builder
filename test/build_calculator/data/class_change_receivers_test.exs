defmodule BuildCalculator.Data.ClassChangeReceiversTest do
  alias BuildCalculator.Rules.GapReceivers

  @moduledoc """
  Сторож ручной разметки `changes[].affects` в `priv/rules/siala_41/classes.json`
  (задача 3.28, 10.08.2026).

  Повод: у заголовка конструктора стояло «126 пробелов в данных» —
  `length(ruleset.gaps)` у `siala_41`. Разбор координатором показал, что
  76 из 89 гэпов формы `{:not_modelled, {:class_change, класс, что}}` — про
  механики, которых калькулятор не считает вовсе (урон, длительность,
  иммунитеты, призывы, яды, ловушки, скорость бега, фамильяр, кастомные
  предметы), и решение Dan: такие факты не дырка в НАШЕМ ответе, потому что
  ответа мы про них и не даём.

  ⚠️ Разметка в итоге назвала не 76, а **70**, и это не расхождение: шесть
  фактов агент оставил гэпом сознательно, прочитав их цитаты (условные прибавки
  вора, `unclear` у монаха, занятая рука у священника и Гнома Защитника). Ошибка
  в сторону показа — правильная сторона, и оба числа стоят здесь именно поэтому:
  76 — оценка по разбору, 70 — то, что получилось по цитатам.

  `affects` называет ПОЛУЧАТЕЛЯ — что факт МЕНЯЕТ, а не показываем ли мы это
  в интерфейсе (`shown: false` было бы решением UI, вбитым в данные;
  `affects: ["damage"]` — утверждение о механике, которое день, когда ядро
  начнёт считать урон, само вернёт в гэпы).

  ⚠️ **Слой кода приехал в тот же день, и этот файл переписан по факту.** Здесь
  стояло «код, который читал бы это поле и резал `ruleset.gaps`, в эту задачу
  не входит» — вошёл: фильтр живёт в `BuildCalculator.Rules.GapReceivers`
  и применяется дважды, в `Data.Loader` (список данных) и в `Rules`
  (список конкретного билда). Поэтому три проверки ниже, написанные
  в условном наклонении («если бы ядро фильтровало»), стали утверждениями
  о том, что происходит. Само сравнение с разметкой осталось: сторож обязан
  ловить не только «сколько», но и «что именно» — молчаливое исчезновение
  записи опаснее, чем неверное число рядом с ней.

  Точный подсчёт (10.08.2026, `mix run` по `Data.ruleset!("siala_41")`):
  **89 фактов производили `{:not_modelled, {:class_change, …}}` до фильтра**.
  Из них **19 остались гэпом** (несут хотя бы один получатель из
  `_receivers.our`) и **70 перестали им быть** — то есть заголовок
  конструктора показывает не 126, а `126 - 70 = 56`.

  ⚠️ **Два совпадения чисел, из-за которых их легко перепутать.** Первое:
  фактов в `classes.json` 126, и гэпов у `siala_41` до фильтра было тоже 126 —
  это разные вещи (гэпы включают 7 конфликтов класс-навыков, 7 прибавок
  к навыкам, 4 отключённых фита и 19 одиночек, а гэпы порождают только 89
  фактов из 126). Второе следует из первого: «фактов с нашим получателем» =
  126 − 70 = 56 и «сколько гэпов осталось» = 126 − 70 = 56 равны **случайно**,
  из-за общего вычитаемого. Поэтому каждый тест ниже называет в имени то,
  что он проверяет.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader

  @classes "priv/rules/siala_41/classes.json" |> File.read!() |> Jason.decode!()
  @feat_skill_bonuses "priv/rules/vanilla/feat_skill_bonuses.json"
                      |> File.read!()
                      |> Jason.decode!()
  @feat_effect_receivers "priv/rules/vanilla/feat_effect_receivers.json"
                         |> File.read!()
                         |> Jason.decode!()

  defp facts do
    for class <- @classes["classes"],
        change <- class["changes"] || [],
        do: {class["id"], change["what"], change["affects"]}
  end

  defp receivers_our, do: @classes["_receivers"]["our"] |> Map.keys() |> MapSet.new()
  defp receivers_not_our, do: @classes["_receivers"]["not_our"] |> Map.keys() |> MapSet.new()

  # Получатели, названные ВТОРЫМ читателем словаря — разметкой эффекта фита
  # (`vanilla/feat_effect_receivers.json`, задача 3.93). Тот же словарь, другой
  # файл: имя, не встретившееся ни на одном факте класса, может быть живым
  # именно здесь, и список «известно неиспользуемых» ниже обязан это различать.
  defp receivers_in_feat_effects do
    for entry <- @feat_effect_receivers["feats"],
        receiver <- entry["affects"],
        into: MapSet.new(),
        do: receiver
  end

  # ---------------------------------------------------------- the vocabulary --

  describe "the closed vocabulary in _receivers" do
    test "`our` and `not_our` do not overlap" do
      assert MapSet.disjoint?(receivers_our(), receivers_not_our())
    end

    # The task's own closed list (CLAUDE.md §1 / the brief): characteristics,
    # HP, AC (naked/geared), BAB, attack bonus, attacks/round, three saves,
    # skill values, skill points and rank caps, spell slots/day, known
    # spells, feat availability (slots and prereqs), class availability,
    # class group flags. Fifteen names, not fourteen or sixteen — this is the
    # one place that vocabulary is allowed to be invented, and it must match
    # what the constructor and the build page actually print, not a superset
    # or a subset of it.
    test "`our` matches exactly what the constructor and the build page print" do
      assert receivers_our() ==
               MapSet.new(~w(
                 ability_scores hp ac bab attack_bonus attacks_per_round
                 saving_throws skill_values skill_points skill_rank_caps
                 spells_per_day spells_known feat_availability
                 class_availability class_group
               ))
    end

    test "every declared receiver has a one-line gloss" do
      for {_id, gloss} <- @classes["_receivers"]["our"],
          do: assert(is_binary(gloss) and gloss != "")

      for {_id, gloss} <- @classes["_receivers"]["not_our"],
          do: assert(is_binary(gloss) and gloss != "")
    end
  end

  # -------------------------------------------------------- every fact tagged --

  describe "every fact in changes[] carries affects" do
    test "no fact is missing the field" do
      missing = for {class, what, nil} <- facts(), do: {class, what}
      assert missing == []
    end

    test "no fact carries an empty list" do
      empty = for {class, what, []} <- facts(), do: {class, what}
      assert empty == []
    end

    test "every value used is a member of the closed vocabulary" do
      known = MapSet.union(receivers_our(), receivers_not_our())

      unknown =
        for {class, what, affects} <- facts(),
            receiver <- affects,
            receiver not in known,
            do: {class, what, receiver}

      assert unknown == []
    end

    # ⚠️ Здесь стояло 126 — пересчитано прогоном 17.08.2026, стало **124**.
    # Ответ Dan по Тайному лучнику снял ДВЕ записи: `requirements_race_clarified`
    # (её значение подтверждено и переехало внутрь применяемого `requirements`,
    # то есть отдельная запись печатала бы гэп про смоделированное) и
    # `requirements_weapon_proficiency_clarified` (отменена: она утверждала, что
    # «Владение оружием» — это НЕ Weapon Focus, а ответ называет именно его).
    # Провенанс обеих лежит в `history` уцелевшей записи, а не выброшен.
    #
    # ⚠️ 124 → 123 (17.08.2026, задача про Мастера оружия): `attack_bonus_progression`
    # и `extra_attack_bonus_past_class_level_10` слиты в одну запись — замер Dan
    # показал, что это один и тот же факт (ванильная колонка
    # `feat_attack_bonuses.json`), описанный дважды и в разное время. Провенанс
    # обеих половин (цитата со страницы «Гномий защитник» и наблюдение Дана)
    # сохранён в уцелевшей записи как `source`/`source_2`, а не выброшен.
    #
    # ⚠️ 123 → 124 (25.08.2026, задача 3.96): Пурпурный рыцарь дракон получил
    # факт `progression_table` — полную таблицу БАБ и сейвов со страницы
    # (10 строк, `affects: ["bab", "attacks_per_round", "saving_throws"]`),
    # закрывающую баг, из-за которого класс терял ВЕСЬ вклад в BAB и сейвы
    # на своих уровнях 6–10 (`Rules.Progression` смотрит класс по
    # накопительному уровню одной строкой, а таблица кончалась на пятом).
    #
    # ⚠️ 124 → 134 (27.08.2026, задача 3.129, применение находок сверки с
    # хаками — см. docs/hak_diff_classes.md): десять новых фактов,
    # `source.kind: "hak"` у каждого. Тайный лучник — Toughness на 1-м уровне
    # (десятый класс с этой выдачей, десять уже стояли в auto_feat_at_level_1)
    # и Discipline классовым навыком; Теневой танцор — Disable Trap классовым;
    # Пурпурный рыцарь дракона — Heal УБРАН из классовых (единственный
    # `removed`, разрешает конфликт `stated_by: "skill_page"` в пользу
    # страницы класса, см. запись в classes.json); шесть классов получили
    # `alignment_restriction`, который раньше был `null` (Assassin, Blackguard,
    # Champion of Torm, Dwarven Defender, Harper Scout, Pale Master).
    #
    # ⚠️ 134 → 135 (02.09.2026): Паладин получил факт `bonus_feat_pool` —
    # сиальские владения оружием в его ЭПИЧЕСКОМ бонусном слоте. Факт стоит
    # только на замере Dan: страница «Паладин» про «Систему оружия» молчит,
    # и страницы самих пяти владений паладина не называют (там Воин, Рейнджер,
    # Мастер оружия и Чемпион Торма). Молчание диффа — молчание, а не отрицание,
    # и перебивается верхней строкой ранга источников (CLAUDE.md §3).
    test "135 facts total, matching the file's own count in the format note" do
      assert length(facts()) == 135
    end
  end

  # ------------------------------------------------------------ the snapshot --

  describe "receiver counts (snapshot — a silent drift here is the bug)" do
    test "how many facts name each receiver" do
      counts =
        for {_class, _what, affects} <- facts(),
            receiver <- affects,
            reduce: %{} do
          acc -> Map.update(acc, receiver, 1, &(&1 + 1))
        end

      # ⚠️ Правка 10.08.2026 по решению Dan («да, это тоже под баффы»): под баффы
      # ушли `Rage` варвара, `Bull's strength` Чёрного стража и `Shadow Evade`
      # Теневого танцора — активируемые КЛАССОВЫЕ умения, а не только
      # заклинания и песня. Отсюда `buff` 11 → 14, `ac` 6 → 4,
      # `saving_throws` 3 → 2, а `ability_scores` пропал из таблицы вовсе:
      # эти два факта были его ЕДИНСТВЕННЫМИ носителями.
      #
      # ⚠️ Правка 13.08.2026 по ЗАМЕРУ (GAME_CHECKS.md, L2): у монаха AB одинаковый
      # безоружным, с боевым посохом и с длинным мечом, значит «сохраняется базовый
      # бонус атаки» в цитате — не про число в листе. У `weapon_bab_exceptions`
      # сняты `bab` (2 → 1) и `attack_bonus` (3 → 2); `ac` оставлен — его никто
      # не мерил, и факт остаётся гэпом через него. Снимок и должен был упасть:
      # он ловит ровно такую правку, и упал он один, а не заодно с другими.
      #
      # ⚠️ Правка 13.08.2026, третья (GAME_CHECKS.md, L2b): вторым замером
      # по монаху фраза разгадана — она про Flurry of blows (работает безоружным
      # и с посохом, с мечом нет), а Шквал активируемый, то есть по решению Dan
      # бафф. Поэтому `ac`, оставленный утром «на случай», заменён на `buff`:
      # `ac` 4 → 3, `buff` 14 → 15. У монаха не осталось ни одного факта
      # с нашим получателем — впервые за всё время.
      #
      # ⚠️ Правка 13.08.2026, вторая (GAME_CHECKS.md, L1): «Свет плута» в значение
      # навыка не идёт — вор с 4 рангами Поиска и INT 8 показывает 3, — и решением
      # Dan предмет в конструкторе не упоминается вовсе. У `rogue_light` снят
      # `skill_values`, у соседнего `trap_disarm_bonus` — по аналогии (тот же
      # используемый предмет), отсюда `skill_values` 3 → 1. У обоих остался
      # `custom_items`, то есть факты живы, а гэпами быть перестали.
      #
      # ⚠️ Правка 17.08.2026 (ответ Dan по Тайному лучнику): `class_availability`
      # 8 → 6. Двигают снимок не получатели, а сами записи — у arcane_archer
      # снято две из трёх с этим получателем (см. счётчик фактов выше), третья
      # осталась и теперь ПРИМЕНЯЕТСЯ. Ни один получатель ни у одного факта при
      # этом не переставлен, поэтому остальные 32 строки таблицы не двинулись —
      # снимок и должен был упасть ровно одной строкой.
      #
      # ⚠️ Правка 17.08.2026, вторая (решение Dan «если штрафы вору идут только
      # в режиме хайда, то мы их не показываем»): `buff` 15 → 16, а
      # `skill_values` ИСЧЕЗ ИЗ ТАБЛИЦЫ ВОВСЕ — штраф вора в скрытности был его
      # последним носителем среди классовых фактов. Две строки на одну правку,
      # потому что получатель у факта один и он переставлен, а не добавлен.
      # ⚠️ Исчезновение ключа читается как «ни один факт о классах шарда больше
      # не двигает значение навыка» — утверждение о корпусе, а не о тесте, и
      # именно поэтому ключ не оставлен с нулём: `counts` строится обходом
      # фактов, нуля в нём не бывает по построению.
      #
      # ⚠️ Правка 17.08.2026, третья (задача про Мастера оружия): `attack_bonus`
      # ИСЧЕЗ ИЗ ТАБЛИЦЫ ВОВСЕ, а `counted_elsewhere` появился с 1 — те же две
      # строки на одну правку, что и у skill_values/buff выше, и по той же
      # причине: `weapon_master` был ЕДИНСТВЕННЫМ носителем `attack_bonus`
      # среди классовых фактов (2 записи), обе слиты в одну и переставлены на
      # новый получатель. Читается так же: «ни один факт о классах шарда
      # больше не двигает бонус атаки СВОЕЙ ЗАПИСЬЮ» — он его двигает, просто
      # другой, уже применённой записью в другом файле.
      #
      # ⚠️ Правка 25.08.2026 (задача 3.96): `attacks_per_round` 2 → 3, `bab`
      # 1 → 2, `saving_throws` 2 → 3 — все три плюс один, и все три от ОДНОГО
      # нового факта (Пурпурный рыцарь дракон, `progression_table`), который
      # называет все три получателя сразу, потому что одна и та же таблица
      # несёт и BAB, и все три сейва. Три строки на одну правку — как и
      # положено, когда новый факт добавлен, а не переставлен.
      #
      # ⚠️ Правка 25.08.2026, вторая (задача 3.101): `attack_bonus` ВЕРНУЛСЯ
      # в таблицу с 1 — у факта Тайного лучника про арбалеты («Все классовые
      # умения теперь распространяются на малый и большие арбалеты») получатель
      # `special_ability` дополнен нашим. Это НЕ переезд, а добавление второго
      # получателя тому же факту, поэтому `special_ability` остался на месте
      # (13) и суммарно строк стало на одну больше. Основание — не новое чтение
      # страницы, а то, что умение, в которое факт падает (`Enchant arrow`),
      # с этой же задачи СЧИТАЕТСЯ: до неё получателя `attack_bonus` у факта
      # не было потому, что нашего числа он не двигал.
      #
      # ⚠️ Правка 27.08.2026 (задача 3.129, применение находок сверки с хаками):
      # пять строк выросли, ни одна не появилась и не исчезла — все десять новых
      # фактов легли на получателей, которые в таблице уже были.
      #   * `hp` 9 → 10 и `feat_availability` 25 → 26 — один факт, Toughness
      #     Тайного лучника (`affects: ["hp", "feat_availability"]`, тот же
      #     получатель, что у девяти уже стоявших `auto_feat_at_level_1`);
      #   * `skill_points` 3 → 6 и `skill_rank_caps` 3 → 6 — три факта
      #     `class_skills` (Discipline Тайному лучнику, Disable Trap Теневому
      #     танцору, Heal УБРАН у Пурпурного рыцаря дракона — все три меняют
      #     цену/потолок ранга одинаково, независимо от знака `added`/`removed`);
      #   * `class_availability` 6 → 12 — шесть новых `alignment_restriction`
      #     (Assassin, Blackguard, Champion of Torm, Dwarven Defender, Harper
      #     Scout, Pale Master), тот же получатель, что у Пурпурного рыцаря
      #     дракона и Паладина.
      #
      # ⚠️ Правка 02.09.2026: `feat_availability` 26 → 27 — факт
      # `bonus_feat_pool` Паладина (владения оружием в эпическом бонусном
      # слоте, замер Dan). Получатель тот же, что у трёх уже стоявших записей
      # этой формы, новых строк в таблице не появилось.
      assert counts == %{
               "ability_uses" => 3,
               "ac" => 3,
               "attack_bonus" => 1,
               "attacks_per_round" => 3,
               "bab" => 2,
               "buff" => 16,
               "class_availability" => 12,
               "class_group" => 7,
               "counted_elsewhere" => 1,
               "crafting" => 1,
               "custom_items" => 7,
               "custom_system" => 1,
               "damage" => 9,
               "domains" => 1,
               "duration" => 4,
               "familiar" => 2,
               "feat_availability" => 27,
               "healing" => 3,
               "hp" => 10,
               "immunities" => 6,
               "item_usage" => 1,
               "mounted_combat" => 2,
               "movement_speed" => 2,
               "party_dependent" => 2,
               "poisons" => 4,
               "saving_throws" => 3,
               "skill_points" => 6,
               "skill_rank_caps" => 6,
               "special_ability" => 8,
               "spell_effects" => 3,
               "summons" => 4,
               "traps" => 3,
               "weapon_armor_proficiency" => 1
             }
    end

    # `our` receivers must have shown up on at least one fact OR be one of the
    # three the file declares but never exercises today. Anything else unused
    # would mean the vocabulary invented a name nothing needs.
    #
    # ⚠ `spells_per_day` / `spells_known` were never exercised: no class-level
    # fact happens to touch either. `ability_scores` joined them on 10.08.2026 —
    # its only two carriers (`Rage`, `Bull's strength`) became `buff` by Dan's
    # decision, so no Siala class fact raises a **permanent** ability score any
    # more. Worth re-reading if one ever does: a shard fact that permanently
    # raises an ability belongs on `ability_scores`, not on `buff`.
    #
    # ⚠️ `skill_values` стал ЧЕТВЁРТЫМ 17.08.2026 — и по той же причине, что
    # `ability_scores`: его единственный носитель (штраф вора в режиме
    # скрытности) ушёл под баффы решением Dan. Читать это надо так же: если
    # у класса шарда однажды появится ПОСТОЯННАЯ прибавка к значению навыка,
    # ей место здесь, а не в `buff`. ⚠️ Слой навыков при этом получателем
    # пользуется вовсю — счёт ведётся по классовым фактам, и пустота тут
    # не значит «получатель мёртв».
    #
    # ⚠️ `attack_bonus` стал ПЯТЫМ 17.08.2026, тем же днём, третьей правкой
    # (задача про Мастера оружия): его единственный носитель — обе записи
    # `weapon_master` — слит в одну и переставлен на `counted_elsewhere`,
    # потому что бонус оказался ванильной колонкой, уже посчитанной другой
    # записью (`vanilla/feat_attack_bonuses.json`).
    # ✅ И ВЕРНУЛСЯ 25.08.2026 (задача 3.101) — ровно тем случаем, который
    # предсказывала строка «появится у шарда СВОЯ прибавка к атаке — ей место
    # здесь»: факт Тайного лучника про арбалеты расширяет ОРУЖИЕ прибавки,
    # которая с той же задачи считается. Восьми имён в списке вместо девяти.
    # ⚠️ Четыре имени ДОБАВЛЕНЫ 25.08.2026 задачей 3.93 (`save_dc`, `metamagic`,
    # `critical_hit`, `concealment`), и ни одно не мёртвое: их называет второй
    # читатель того же словаря — `vanilla/feat_effect_receivers.json`. Читать
    # это надо как `skill_values` выше: счёт здесь ведётся по фактам КЛАССОВ,
    # и пустота в нём не значит «получатель никому не нужен». Чтобы список
    # исключений не стал свалкой, соседний тест проверяет обратное — что все
    # четыре там действительно стоят.
    test "every declared receiver is either used, or one of the eight known-unused ones" do
      used =
        for {_class, _what, affects} <- facts(),
            receiver <- affects,
            into: MapSet.new(),
            do: receiver

      declared = MapSet.union(receivers_our(), receivers_not_our())
      unused = MapSet.difference(declared, used)

      assert unused ==
               MapSet.new([
                 "ability_scores",
                 "concealment",
                 "critical_hit",
                 "metamagic",
                 "save_dc",
                 "skill_values",
                 "spells_per_day",
                 "spells_known"
               ])
    end

    # Обратная половина: четыре имени, которых нет ни на одном факте класса,
    # обязаны быть живы у второго читателя словаря. Без этой строки исключение
    # выше нельзя отличить от «завели имя и забыли им воспользоваться».
    test "the four receivers no class fact names are the feat-effect layer's" do
      assert MapSet.subset?(
               MapSet.new(["concealment", "critical_hit", "metamagic", "save_dc"]),
               receivers_in_feat_effects()
             )
    end

    # И положительный контроль на сам словарь: каждое имя, которое разметка
    # эффекта фита называет, объявлено — иначе загрузчик уронил бы сборку,
    # а тест обязан ловить это сам, не полагаясь на неё.
    test "every receiver the feat-effect layer names is declared" do
      declared = MapSet.union(receivers_our(), receivers_not_our())

      assert MapSet.subset?(receivers_in_feat_effects(), declared)
    end
  end

  # --------------------------------------------------- against the live gaps --

  describe "cross-checked against today's ruleset.gaps" do
    setup do: %{siala: Data.ruleset!("siala_41")}

    defp class_change_gaps(ruleset) do
      for {:not_modelled, {:class_change, class, what}} <- ruleset.gaps, do: {class, what}
    end

    # ⚠️ Считается по ФАКТАМ, а не по парам `(класс, what)`, и это не мелочь:
    # 121 пара на 124 факта, у монаха три записи `feat_level_shift` и они
    # расходятся по `affects`. Вопрос всегда «есть ли хоть один факт с нашим
    # получателем», и таблица `%{пара => affects}` (как было написано здесь до
    # 10.08.2026) тихо отвечала бы «какой из них в файле последний».
    defp unapplied_facts(ruleset) do
      for {id, class} <- ruleset.classes,
          fact <- class.siala_unapplied,
          do: {id, fact["what"], fact}
    end

    # ⚠️ Зовёт `GapReceivers.ours?/2`, а НЕ повторяет её условие. До 21.08.2026
    # здесь стояла своя копия (`Enum.any?(list, &(&1 in our))`), и задача 3.74
    # показала, чем это кончается: правило научилось третьему входу
    # (`not_a_gap` — решение владельца, снимающее факт со счёта), копия про него
    # не знала, и тест начал сравнивать список гэпов с числом, посчитанным
    # по устаревшему правилу. Два способа посчитать одно и то же — это две
    # возможности разойтись, и здесь они разошлись молча.
    defp pairs_with(facts, our, keep?) do
      facts
      |> Enum.group_by(fn {id, what, _} -> {id, what} end, fn {_, _, fact} -> fact end)
      |> Enum.filter(fn {_pair, facts} ->
        keep?.(Enum.any?(facts, &GapReceivers.ours?(&1, our)))
      end)
      |> Enum.map(fn {pair, _} -> pair end)
      |> Enum.sort()
    end

    # ⚠️ Здесь стояло 89 — пересчитано прогоном 17.08.2026, стало **86**, и
    # ушли ТРИ, а не две: две записи Тайного лучника сняты из файла целиком,
    # а третья (`requirements`) перестала быть беспризорной — у неё появилось
    # значение, и `apply_change/2` её применяет. То есть счётчик просел по двум
    # разным причинам сразу, и обе видны в соседних тестах: 124 факта против
    # 126 (запись исчезла) и 38 применённых против 37 (запись доехала).
    #
    # ⚠️ 86 → 85 (17.08.2026, задача про Мастера оружия): `attack_bonus_progression`
    # и `extra_attack_bonus_past_class_level_10` слиты в одну запись — обе были
    # беспризорными и раньше (у `apply_change/2` нет клозы на этот `what`),
    # слились они, а не переехали в применённые, поэтому счётчик факта, а не
    # причина, из-за которой факт беспризорен.
    #
    # ⚠️ 85 → 84 (21.08.2026, задача 3.72): `extra_attacks` Тайного лучника
    # получил механический дом — `ruleset.attack_modifiers`. Это ПЕРЕЕЗД
    # в применённые (38 → 39), а не исчезновение записи: сама она на месте,
    # с той же цитатой и тем же `affects`.
    #
    # ⚠️ 84 → 82 (21.08.2026, задача 3.73): тот же переезд ещё дважды —
    # `bonus_feat_pool` Священника и Друида лёг в `bonus_for` шести эпических
    # заклинаний, то есть туда же, где живёт ванильный ответ на тот же вопрос
    # (39 → 41 применённых). Обе записи на месте с теми же цитатами.
    # ⚠️ Здесь стояло: «Две записи ТОЙ ЖЕ формы (Чемпион Торма, Рейнджер)
    # остались беспризорными сознательно: у первой источник не называет
    # ни одного уровня, у второй цитата говорит „а также на эпических фитах“,
    # и обе ждут замера (GAME_CHECKS.md, U1 и U2)».
    #
    # ⚠️ 82 → 80 (24.08.2026, задача 3.85): замеры пришли, обе записи
    # ПЕРЕЕХАЛИ в применённые (41 → 43) — форма `bonus_feat_pool` применена
    # теперь целиком, все четыре записи из четырёх. Переезд, а не пропажа:
    # `facts()` по-прежнему 123, цитаты на месте.
    # 🔴 И это переезд особого рода: пул обоих классов был верен ВСЁ ЭТО
    # ВРЕМЯ (правило приезжает со страниц самих фитов, `bonus_for`), то есть
    # беспризорная запись печатала «не смоделировано» про посчитанное.
    test "79 facts have no mechanical home — the set the filter judges", %{siala: siala} do
      assert length(unapplied_facts(siala)) == 79
    end

    # Named, not just counted: the point of the exercise was to tell apart the
    # gaps that stay ours from those that are not, and an unnamed "70" would
    # be exactly the kind of number CLAUDE.md warns against — it reads fine and
    # is unverifiable the moment someone touches the data.
    #
    # And compared against the **live** list, not just against itself: the left
    # side is what the labels say should survive, the right side is what
    # `Rules.GapReceivers` actually let through. One assertion, two claims.
    #
    # ⚠️ Здесь стояло 13 пар — стало **10** (17.08.2026, ответ Dan по Тайному
    # лучнику). Ушли все три записи Лучника про требования: две сняты из
    # данных, третья применена. У Лучника осталась ровно одна наша пара —
    # `extra_attacks`, и это положительный контроль: список просел, а не
    # обнулился по классу.
    # ⚠️ 10 → **9** (17.08.2026, решение Dan про режим скрытности): ушла пара
    # вора. ⚠️ У ВОРА ЭТО БЫЛА ЕДИНСТВЕННАЯ наша пара, то есть класс из списка
    # пропал целиком — в отличие от Лучника выше, у которого осталась одна.
    # Разница названа потому, что «класс исчез из списка» и «у класса убавилось»
    # читаются одинаково, а значат разное: у вора теперь ни один факт не про
    # наши числа, и следующая правка его данных обязана это заметить.
    #
    # ⚠️ 9 → **7** (17.08.2026, задача про Мастера оружия): ушли ОБЕ пары ВМ
    # разом — это один и тот же факт (замер Dan: ванильная колонка
    # `feat_attack_bonuses.json`, уже посчитанная), слитый в одну запись
    # и переставленный на `counted_elsewhere`. У Мастера оружия это тоже была
    # ЕДИНСТВЕННАЯ пара — класс пропадает из списка целиком, как раньше вор.
    #
    # ⚠️ 7 → **6** (21.08.2026, задача 3.72): ушла пара Тайного лучника —
    # и ушла ТРЕТЬИМ способом, отличным от обоих предыдущих. У вора и Мастера
    # оружия факт переставал быть нашим (бафф, посчитано в другом месте);
    # здесь получатель прежний (`attacks_per_round`, наш), а факт СЧИТАЕТСЯ.
    # Это единственный из трёх случаев, где список просел потому, что модель
    # научилась, а не потому, что вопрос оказался не нашим.
    # ⚠️ У Лучника это была последняя наша пара — класс уходит из списка
    # целиком, как до него вор и Мастер оружия.
    #
    # ⚠️ 6 → **4** (21.08.2026, задача 3.73), и это ТРЕТИЙ способ в четвёртый
    # раз: получатель прежний и наш (`feat_availability`), а факт СЧИТАЕТСЯ —
    # как у Тайного лучника выше. Новое здесь другое: **из четырёх записей
    # ОДНОЙ формы применены ровно две**, и оставшиеся две стоят в списке
    # рядом. Прежние правки уносили форму целиком либо класс целиком; эта
    # впервые разрезала форму пополам — по тому, называет ли источник числа.
    # ⚠️ У Друида это была единственная наша пара — класс уходит из списка
    # целиком (как вор, Мастер оружия и Лучник); у Священника осталась
    # `spellcasting_requirement`, то есть список просел, а не обнулился
    # по классу. Оба случая рядом в одном списке — это удобно и намеренно.
    #
    # 🔴 4 → **0** (24.08.2026, задача 3.85), и это первый раз, когда список
    # обнуляется ЦЕЛИКОМ: обе оставшиеся записи `bonus_feat_pool` применены
    # по замерам U1 и U2. Ни один факт о классах шарда больше не доезжает
    # до `ruleset.gaps`. ⚠️ Пустой список молчит про всё одинаково, поэтому
    # проверка ниже раздвоена: сначала синтетическая пара с нашим получателем
    # (механизм жив и срабатывает), потом реальный ноль.
    test "ни одна пара не несёт `our` получателя — и это ноль, а не поломка",
         %{siala: siala} do
      # ⚠️ `{:cleric, "spellcasting_requirement"}` стоял здесь до 21.08.2026
      # (задача 3.74) и снят **решением Dan**, а не правкой механики: символ
      # веры на Сиале вешается на само оружие, значит запрета щита у клирика
      # нет вовсе. Факт остался в данных со своим `affects: ["ac"]` — механика
      # в игре действительно про AC, — но несёт `not_a_gap` с автором, цитатой
      # и доводом, и `GapReceivers.ours?/2` читает именно его.
      # Положительный контроль ПЕРЕД утверждением о нуле: тот же вызов
      # на выдуманной паре с нашим получателем отвечает «наша». Иначе
      # `== []` зеленел бы и у `pairs_with/3`, разучившегося считать вовсе.
      probe = [{:probe_class, "probe", %{"what" => "probe", "affects" => ["hp"]}}]
      assert pairs_with(probe, receivers_our(), & &1) == [{:probe_class, "probe"}]

      expected = []

      assert pairs_with(unapplied_facts(siala), receivers_our(), & &1) == expected
      assert Enum.sort(class_change_gaps(siala)) == expected
    end

    # ⚠️ 76 → 77 (17.08.2026): пришёл штраф вора в режиме скрытности —
    # `{:rogue, "stealth_perception_penalty"}`, получатель `buff`. Это ровно
    # та пара, что ушла из списка выше: она не потерялась, а переехала,
    # и оба списка названы поимённо именно затем, чтобы переезд был виден
    # с обеих сторон, а не как «там минус один, тут плюс один».
    # ⚠️ 77 → 78 (17.08.2026, задача про Мастера оружия): пришла
    # `{:weapon_master, "attack_bonus_progression"}` — та самая пара, что
    # ушла из списка «наших» выше (обе старые пары слиты в неё одну), и она
    # названа здесь по той же причине, что и штраф вора строкой выше:
    # переезд обязан быть виден с обеих сторон.
    test "the other 80 name only receivers the calculator does not show, and none is a gap",
         %{siala: siala} do
      dropped = pairs_with(unapplied_facts(siala), receivers_our(), &(not &1))

      assert dropped == [
               {:arcane_archer, "class_ability_changed"},
               {:arcane_archer, "imbue_arrow_damage"},
               {:arcane_archer, "proficiencies"},
               {:assassin, "camouflage"},
               {:assassin, "poisons"},
               {:assassin, "profile_class_gate"},
               {:assassin, "trap_poisoning"},
               {:barbarian, "rage"},
               {:bard, "bard_song_duration_feats"},
               {:bard, "bard_song_progression"},
               {:bard, "bard_song_self_damage"},
               {:bard, "displacement_hide_bonus"},
               {:bard, "scroll_use"},
               {:bard, "spellcasting"},
               {:blackguard, "azarak_stone"},
               {:blackguard, "bulls_strength"},
               {:blackguard, "contagion_charges"},
               {:blackguard, "divine_shield_might_duration"},
               {:blackguard, "inflict_wounds_damage"},
               {:blackguard, "mounted_penalty"},
               {:blackguard, "poisons"},
               {:champion_of_torm, "divine_wrath_duration"},
               {:cleric, "domains"},
               {:cleric, "shamanism"},
               # ⚠️ Приехал сюда 21.08.2026 (задача 3.74): факт про символ веры
               # в левой руке несёт `not_a_gap` — решение Dan о том, что до
               # нашего ответа механика не доезжает. `affects` у него
               # по-прежнему `["ac"]`, потому что в игре это правда про AC.
               {:cleric, "spellcasting_requirement"},
               {:druid, "legendary_druid_cube"},
               {:druid, "spy_bird"},
               {:druid, "summons"},
               {:dwarven_defender, "group_stance"},
               # ⚠️ Приехал 21.08.2026 (задача 3.75): предмет групповой стойки
               # юзабельный, слот щита не занимает и надеть его нельзя (Dan).
               # `affects` остался `["ac"]` — механика в игре про AC, — но факт
               # несёт `not_a_gap`, и правило читает именно его.
               {:dwarven_defender, "group_stance_requirements"},
               {:harper_scout, "harper_alchemy"},
               {:monk, "hips_disabled"},
               {:monk, "instinctive_throw_usable_from"},
               {:monk, "movement_speed"},
               {:monk, "unarmed_glove_damage"},
               {:monk, "weapon_bab_exceptions"},
               {:monk, "wholeness_of_body"},
               {:paladin, "aura_of_glory"},
               {:paladin, "bless_weapon"},
               {:paladin, "divine_favor_scaling"},
               {:paladin, "divine_shield_might_duration"},
               {:paladin, "holy_sword"},
               {:paladin, "lay_on_hands"},
               {:paladin, "mounted_penalties"},
               {:paladin, "otrazhenie"},
               {:paladin, "prayer_scaling"},
               {:pale_master, "deathless_master_touch"},
               {:pale_master, "healing_received"},
               {:pale_master, "immunities"},
               {:pale_master, "summons"},
               {:purple_dragon_knight, "ability_scaling"},
               {:purple_dragon_knight, "self_buff_requires_party"},
               {:ranger, "blade_thirst"},
               {:ranger, "special_arrows"},
               {:ranger, "spy_bird"},
               {:ranger, "traps"},
               {:red_dragon_disciple, "dragon_breath"},
               {:red_dragon_disciple, "dragon_breath_counters"},
               {:red_dragon_disciple, "dragon_breath_damage"},
               {:red_dragon_disciple, "monk_interaction"},
               {:rogue, "evasion_vs_spells"},
               {:rogue, "hide_movement_speed"},
               {:rogue, "ignore_immunity_chance"},
               {:rogue, "poisons"},
               {:rogue, "rogue_light"},
               {:rogue, "sneak_attack_bonus_damage"},
               {:rogue, "stealth_perception_penalty"},
               {:rogue, "trap_disarm_bonus"},
               {:shadowdancer, "class_ability_changed"},
               {:shadowdancer, "darkness_immunity"},
               {:shadowdancer, "healing_kits"},
               {:shadowdancer, "shadow_traps"},
               {:shadowdancer, "shadowdancer_cloak"},
               {:sorcerer, "familiar"},
               {:sorcerer, "spellcasting"},
               {:weapon_master, "attack_bonus_progression"},
               {:wizard, "familiar"},
               {:wizard, "instant_teleport"},
               {:wizard, "spellcasting"}
             ]

      # Ни один из них не доехал до списка неточностей...
      gaps = class_change_gaps(siala)
      for pair <- dropped, do: refute(pair in gaps)

      # ...и положительный контроль к этому `refute`: список не пуст, и та же
      # проверка на паре с нашим получателем срабатывает.
      #
      # ⚠️ Здесь стоял `{:blackguard, "bulls_strength"}`, и 10.08.2026 он
      # перестал годиться: решением Dan факт ушёл под баффы. Контроль отработал
      # как задумано — упал и назвал причину. Пример заменён на прибавку к
      # атаке: она постоянная прогрессия класса, а не включаемое умение,
      # то есть в баффы уехать не может по построению.
      #
      # ⚠️ И ЭТОТ пример 17.08.2026 тоже перестал годиться — но по СОВСЕМ
      # другой причине, не по той, от которой его выбирали: не «стал баффом»,
      # а «оказался посчитанным в другом месте» (замер Dan про Мастера
      # оружия, см. запись выше). Контроль снова отработал как задуман — упал
      # и назвал причину, а не потерялся молча. Третий пример подряд не
      # про постоянную прогрессию класса вообще: `bonus_feat_pool` — про то,
      # какие фиты входят в бонусный пул, у него нет ни temporal-, ни
      # cross-file-стороны, и это осознанный выбор, а не удача.
      #
      # 🔴 И ЧЕТВЁРТЫЙ пример подряд перестал годиться, 24.08.2026 (задача
      # 3.85) — снова по новой причине: `bonus_feat_pool` Рейнджера применён
      # по замеру U2, и настоящих пар с нашим получателем в данных больше
      # НЕТ НИ ОДНОЙ. Четыре реальных контроля кряду, выбранных по признаку
      # «этот уж точно останется», — достаточная выборка, чтобы перестать
      # выбирать реальный: контроль ниже синтетический и проверяет механизм,
      # а не состояние `priv/`.
      probe = [{:probe_class, "probe", %{"what" => "probe", "affects" => ["hp"]}}]
      assert pairs_with(probe, receivers_our(), & &1) == [{:probe_class, "probe"}]

      # ...и сам список пуст, то есть все 80 пар выше отсеяны фильтром,
      # а не потеряны по дороге. Что снятая метка ВОЗВРАЩАЕТ гэп в
      # `ruleset.gaps`, проверяется перезагрузкой копии данных ниже
      # («факт без affects загружается и остаётся гэпом») — здесь это
      # повторить нечем: `ruleset.gaps` собирается на загрузке.
      assert gaps == []
    end

    # ⚠️ Имя теста называет, ЧТО именно 53, — из-за двойного совпадения чисел
    # (см. moduledoc). Здесь это «сколько гэпов у данных», а не «сколько
    # фактов с нашим получателем»; второе тоже 53, и случайно.
    #
    # ⚠️ И совпадение УСТОЙЧИВОЕ, а не разовое: оба числа равны `37 + N`, где
    # 37 — применённых фактов и, отдельно от них, гэпов не про классы шарда,
    # а N — гэпов про классы. Равенство этих двух 37 и есть совпадение;
    # правка данных 10.08.2026 сдвинула оба числа с 56 на 53 разом.
    test "the data gap list is 17 long: 123 minus 79 dropped, minus 27 that left, plus 0 feats, plus 0 skills, plus 0 weapon-type",
         %{siala: siala} do
      dropped = pairs_with(unapplied_facts(siala), receivers_our(), &(not &1))

      assert length(dropped) == 79

      # ⚠️ Здесь стояло `126 - 76 = 50`, и равенство держалось ровно до
      # 13.08.2026: замеры F4 и F5 убрали два гэпа ИЗ ДРУГОГО файла
      # (`vanilla/feat_skill_bonuses.json` — `bullheaded` и `improved_parry`
      # оказались не про значение навыка), а замер D1 — ещё один
      # (`deathless_vigor` посчитан). Совпадение двух чисел, о котором
      # предупреждает moduledoc, на этом и распалось: `ours` по-прежнему 50,
      # а гэпов 48. Поэтому теперь их **три** строки, а не одна арифметика.
      #
      # ⚠️ 48 → 47 (14.08.2026): ушёл `{:not_modelled, :zen_archery}` — форма
      # не из файла классов вовсе, а из хука смены характеристики атаки
      # (`overrides.json` → `formulas.attack_ability`). Правило для фита
      # заведено, значит строка «не применяем» стала ложью про посчитанное.
      #
      # ⚠️ 47 → 48 (14.08.2026, тем же днём и с другой стороны): в список
      # данных начал доезжать слой ФИТОВ — `{:not_modelled, {:feat_change,
      # :improved_evasion, "siala_note"}}`. Это ровно та же арифметика «плюс-
      # минус форма не из этого файла», что тремя абзацами выше, и записано
      # отдельным слагаемым ниже по той же причине: слитая в итог правка
      # неотличима от пропавшего факта о классе.
      #
      # ⚠️ 48 → 52 (14.08.2026, тем же днём, третьим слоем): слой НАВЫКОВ
      # получил `affects` у всех 53 фактов и добавил ЧЕТЫРЕ гэпа своей формы
      # (`{:not_modelled, {:skill_change, …}}`) — четвёртое слагаемое рядом
      # с `feat_changes`, а не растворённое в итоге, по той же причине.
      #
      # ⚠️ 52 → 51 (15.08.2026, задача 3.31): ЧЕТВЁРТЫЙ ушедший из другого
      # файла — `{:not_modelled, {:caster_advancement, :epic_spell_access}}`
      # из `vanilla/spellcasting.json`. Та же арифметика, что у `zen_archery`
      # выше: правило применено (требование шести эпических заклинаний
      # записано ключом `qualifying_class_levels`), значит «не считаем» стало
      # ложью про посчитанное. Ни одного факта о классах при этом не пропало —
      # равенство ниже это и держит.
      #
      # ⚠️ 51 → 53 (16.08.2026, задача 3.35): ДВА пришедших из ещё одного файла —
      # `siala_41/systems.json`, система оружия. Прогрессия бонуса за тип оружия
      # неизвестна (как и у расового бонуса, потому что это тот же бонус), и
      # «Вилы» дают бонус, которого не на что повесить — такого оружия нет
      # в справочнике. Оба стоят своими слагаемыми ниже, а не растворены в итоге,
      # по той же причине, что `feat_changes` и `skill_changes`.
      #
      # ⚠️ 53 → 52 (16.08.2026, задача 3.37): ПЯТЫЙ ушедший из другого файла —
      # `{:missing_data, {:hit_die, :red_dragon_disciple}}` из
      # `vanilla/classes.json`. Хит-дайс этого класса растёт с уровнем класса,
      # и схема класса такую форму теперь выражает, значит «нет хит-дайса»
      # стало ложью про прочитанное. Ни одного факта о классах ШАРДА при этом
      # не пропало — равенство ниже это и держит.
      #
      # ⚠️ 52 → 51 (16.08.2026, задача 3.42): ШЕСТОЙ ушедший из другого файла —
      # `{:not_modelled, :armor_check_penalty}`, который объявлялся прямо
      # в `Loader`, а посчитан по `overrides.json` → `gear.worn`. Та же
      # арифметика в шестой раз, и снова ни одного факта о классах шарда.
      #
      # ⚠️ 51 → 50 (16.08.2026, замер F7): СЕДЬМОЙ ушедший из другого файла —
      # `{:not_modelled, {:feat_skill_bonus, :bardic_knowledge}}` из
      # `vanilla/feat_skill_bonuses.json`. Прибавка равна сумме уровней барда
      # и Арфиста и теперь считается. ⚠️ Слой навыков этой правкой ЗАДЕТ (его
      # запись про то же умение перестала быть правилом), но ни один факт о нём
      # не пропал: запись помечена «посчитано в другом месте» и осталась
      # применённой, поэтому `skill_changes` ниже по-прежнему 4.
      #
      # ⚠️ 50 → 47 (17.08.2026, ответ Dan по Тайному лучнику): единственная
      # правка в этом ряду, которая двигает ЛЕВУЮ часть равенства, а не список
      # «ушедших из другого файла». Ушли три гэпа про классы шарда сразу, и
      # причины у них РАЗНЫЕ: два факта сняты из данных (значит уменьшилось
      # общее число, 126 → 124), а третий применён (значит вырос счётчик
      # применённых, 37 → 38). Слагаемое «minus N that left» из-за этого выросло
      # с 7 до 8 — восьмым стал сам `requirements` Лучника, единственный
      # ушедший из ЭТОГО файла, а не из чужого.
      #
      # ⚠️ 47 → 44 (17.08.2026, два решения Dan): левая часть равенства НЕ
      # тронута вовсе — ни один факт о классах шарда не пропал и не применился,
      # — а убавились ДВА отдельно названных слагаемых: `feat_changes` 1 → 0
      # (`improved_evasion`, гэп снят решением после замера H9) и
      # `skill_changes` 4 → 2 (`listen`/`spot` — штраф вора в режиме скрытности
      # объявлен баффом). Ровно затем оба и вынесены слагаемыми: правка в чужом
      # слое обязана быть видна как правка в чужом слое, а не как пропавший
      # факт о классе.
      #
      # ⚠️ 44 → 42 (17.08.2026, ещё два ответа Dan) — и вот здесь двинулись ОБЕ
      # части равенства сразу, впервые:
      #   * ЛЕВАЯ: `dropped` 76 → 77 — третья копия штрафа вора, теперь уже
      #     классовая, ушла под баффы. Ни один факт при этом не пропал и
      #     не применился, поэтому `124 - 8` справа не тронуто;
      #   * ПРАВАЯ: `skill_changes` 2 → 1 — `craft_trap / class_skills`
      #     ПРИМЕНЁН замером (оба навыка ловушек стали классовыми Теневому
      #     танцору), то есть слагаемое чужого слоя убавилось.
      # ⚠️ Итог просел на два, а слагаемые — на разное и по разным причинам:
      # одно «решили не показывать», другое «посчитали».
      #
      # ⚠️ 42 → 40 (17.08.2026, задача про Мастера оружия) — и снова двинулись
      # ОБЕ части равенства сразу, третий раз подряд, но по ЕЩЁ одной причине:
      #   * ЛЕВАЯ: `dropped` 77 → 78 — `weapon_master` перестал быть нашей
      #     парой (замер Dan: ванильная колонка, уже посчитанная в
      #     `feat_attack_bonuses.json`), обе его записи слились в одну
      #     и переставлены на `counted_elsewhere`;
      #   * ПРАВАЯ: `124 - 8` стало `123 - 8` — тот же слияние убрало ОДНУ
      #     запись из файла (124 → 123 факта, см. тест выше), а «minus 8 that
      #     left» не тронуто: слияние — событие ВНУТРИ этого файла, а не
      #     уход в другой (та восьмёрка вся про правки в ЧУЖИХ файлах).
      # `123 - 8 = 115` и `40 + 78 - 0 - 1 - 2 = 115` сходятся, как и раньше:
      # это тождество, а не совпадение — обе части всегда двигались вместе
      # ровно потому, что уменьшение `facts()` и уменьшение гэпов, вызванное
      # тем же слиянием, гасят друг друга в разности.
      #
      # ⚠️ 40 → 38 (17.08.2026, задача «пять файлов прибавок») — ВОСЬМОЙ
      # ушедший из другого файла, а если считать поштучно — сразу ДВА:
      # `vanilla/feat_skill_bonuses.json` получил поле `affects`, и тот же
      # фильтр `GapReceivers.ours?/2`, что три строки выше режет
      # `class_change`/`feat_change`/`skill_change`, впервые применён к
      # ruleset-wide циклу `feat_skill_bonus` в `Data.Loader.gaps/15`.
      # `oath_of_wrath` (affects: buff) и `small_stature` (affects:
      # special_ability) перестали быть гэпом; `stonecunning`/`trackless_step`
      # (affects: skill_values) остались — см.
      # `BuildCalculator.Data.FeatSkillBonusesTest` для разбора всех семи
      # not_modelled записей файла, не только тех двух, что тут ушли. Ни
      # facts(), ни dropped, ни feat_changes/skill_changes/weapon_type не
      # тронуты — это НЕ про classes.json вовсе, поэтому константа сдвигается
      # на те же +2, каким сдвинулась при уходе `bardic_knowledge` (51 → 50
      # выше): «8» — это остаток, покрывающий всё, что не про факты
      # ЭТОГО файла, а не единственное магическое число.
      #
      # ⚠️ 38 → 36 (18.08.2026, задача 3.49) — ДЕВЯТЫЙ и ДЕСЯТЫЙ ушедшие из
      # ДРУГИХ файлов, и снова мимо classes.json целиком: `{:assumed,
      # :hp_uses_maximum_hit_die_rolls}` и `{:assumed,
      # :skill_rank_caps_past_vanilla_cap}` были записаны безусловно всё
      # это время, хотя `character.hit_points_roll` и `skills.rank_cap_at_41`
      # (оба `source: user`, Dan, 2026-08-01) подтверждают ровно то, что
      # `Loader.Gaps` печатал допущением. `Character.hp_always_max?/1` и
      # `skill_rank_cap_extension_confirmed?/1` теперь их читают. Ни facts(),
      # ни dropped, ни feat_changes/skill_changes/weapon_type не тронуты —
      # остаток «10» вырос до «12» той же арифметикой, что «8» выросло из
      # предыдущей правки.
      # ⚠️ 36 → 35 (21.08.2026, задача 3.70): `bonus_spell_slots_from_ability`
      # ушла из `Loader.Gaps` — таблица бонусных слотов за высокую
      # характеристику каста перенесена в `vanilla/spellcasting.json`
      # и считается. Опять другой файл, опять остаток, опять ни один
      # из трёх census-слоёв не тронут: «12» стало «13».
      #
      # 🔴 33 → 32 (21.08.2026, задача 3.72) — и это ЕДИНСТВЕННАЯ правка
      # в этом длинном списке, которая идёт ИЗ ЭТОГО ФАЙЛА, а не из соседних.
      # Все предыдущие сдвиги двигали остаток, оставляя `facts()` и `dropped`
      # нетронутыми; здесь наоборот: `extra_attacks` Тайного лучника ПЕРЕЕХАЛ
      # из беспризорных в применённые (85 → 84 и 38 → 39), а `dropped`
      # не шелохнулся. Поэтому справа меняется вычитаемое (15 → 16), а не
      # константа 123: фактов о классах по-прежнему 123, просто у одного
      # появился механический дом.
      #
      # ⚠️ 32 → 30 (21.08.2026, задача 3.73) — ровно то же событие ещё дважды
      # и по той же арифметике: `bonus_feat_pool` Священника и Друида ПЕРЕЕХАЛ
      # из беспризорных в применённые (84 → 82 и 39 → 41), а `dropped`
      # не шелохнулся. Справа снова двигается вычитаемое (16 → 18),
      # а константа 123 стоит: фактов о классах по-прежнему 123.
      #
      # ⚠️ 25 → 24 (22.08.2026, задача 3.78) — и это ТРЕТИЙ род правки в списке,
      # после «ушло из другого файла» и «переехало в применённые здесь». Ушло
      # слагаемое `skill_changes` (1 → 0), то есть уменьшился ЛЕВЫЙ край
      # равенства вместе со своим вычитаемым, и обе стороны сошлись сами:
      # `24 + 80 − 0 − 0 − 2 = 102 = 123 − 21`. Ни `facts()`, ни `dropped`,
      # ни константа 123 не тронуты — этот файл (`classes.json`) в правке
      # не участвовал вовсе.
      #
      # ⚠️ 24 → 23 (22.08.2026, задача 3.79) — возврат к ПЕРВОМУ роду: ушёл
      # `{:not_modelled, :cleric_domains}`, объявленный прямо в `Loader.Gaps`,
      # то есть двенадцатый «ушедший из другого места». Остаток «21» вырос
      # до «22» ровно той же арифметикой, какой он рос из «8», «10», «12»
      # и «13» выше; `facts()`, `dropped`, `feat_changes`, `skill_changes`
      # и `weapon_type` не тронуты ни на единицу.
      # ⚠️ Повод при этом НЕ «модель научилась считать» и не «утверждение
      # сверено», а третий — **решение о границе ответа**: заклинания домена
      # выдаются автоматически, выбирать нечего, значит конструктору тут
      # делать нечего (Dan). Различать поводы обязательно: одинаковая на вид
      # «−1» у них означает разное.
      #
      # ⚠️ 23 → 22 (22.08.2026, задача 3.80): тот же первый род и тот же
      # четвёртый повод — ушла `{:not_modelled, :metamagic}`, объявленная
      # прямо в `Loader.Gaps`. Остаток «22» вырос до «23».
      #
      # ⚠️ 22 → 20 (22.08.2026, задача 3.81): ушли ДВЕ формы сразу, и они
      # ложатся в это равенство ПО-РАЗНОМУ — это надо назвать, иначе правка
      # выглядит арифметической ошибкой:
      #
      #   * `{:missing_data, :racial_bonus_progression}` — обычный первый род,
      #     ушедшая из другого места (`siala_41/races.json` через `Loader.Gaps`);
      #     левый край падает на 1, остаток растёт с «23» до «24»;
      #   * `{:missing_data, :weapon_type_bonus_progression}` — она входила
      #     в слагаемое `weapon_type` (2 → 1), поэтому уменьшает левый край
      #     и вычитаемое ОДНОВРЕМЕННО, то есть на равенство не влияет вовсе.
      #
      # Итог: `20 + 80 − 0 − 0 − 1 = 99 = 123 − 24`. `facts()`, `dropped`
      # и константа 123 не тронуты — `classes.json` в правке не участвовал.
      #
      # ⚠️ 19 → 17 (24.08.2026, задача 3.85) — ВТОРОЙ род правки, «переехало
      # в применённые здесь», и второй раз за всю историю списка: обе
      # оставшиеся записи `bonus_feat_pool` применены по замерам U1 и U2
      # (82 → 80 беспризорных, 41 → 43 применённых), `dropped` не шелохнулся.
      # Справа поэтому двигается вычитаемое (24 → 26), а константа 123 стоит:
      # фактов о классах по-прежнему 123, просто у двух появился
      # механический дом. Итог: `17 + 80 − 0 − 0 − 0 = 97 = 123 − 26`.
      #
      # ⚠️ 17 → 16 (24.08.2026, задача 3.86) — снова ПЕРВЫЙ род, «ушедшая
      # из другого места»: `{:not_modelled, :wizard_opposed_school}` объявлял
      # `vanilla/spellcasting.json` через `Loader.Spells`, а не разметка
      # классов. Вычитаемое растёт с «26» до «27», константа 123 и `dropped`
      # не тронуты. Итог: `16 + 80 − 0 − 0 − 0 = 96 = 123 − 27`.
      # ⚠️ Повод — ШЕСТОЙ в этом перечне и новый: не перенос механики,
      # не чужой получатель и не решение о границе, а **ответ вырос**. Цена
      # специализации волшебника теперь считается и печатается.
      #
      # ⚠️ 25.08.2026 (задача 3.101) — ВТОРОЙ род правки, «переехало
      # в применённые здесь», и левый край при этом НЕ ДВИНУЛСЯ ВОВСЕ:
      # `class_ability_weapons` Тайного лучника был отброшен фильтром
      # получателей (то есть гэпом не был), а стал применён. Поэтому
      # `dropped` 80 → 79, вычитаемое 27 → 28, а `length(siala.gaps)`
      # остаётся 16. Итог: `16 + 79 − 0 − 0 − 0 = 95 = 123 − 28`.
      #
      # ⚠️ 16 → 17 (25.08.2026, задача 3.104) — ПЕРВЫЙ род наоборот: гэп
      # не ушёл из другого места, а ПРИШЁЛ оттуда. `{:conflict,
      # {:skill_trained_only, :perform, :category_only}}` объявляет
      # `vanilla/skills.json` через `Loader.Gaps`, разметка классов тут ни при
      # чём. Левый край растёт на 1, поэтому вычитаемое падает: 28 → 27.
      # Константа 123 и `dropped` не тронуты.
      # Итог: `17 + 79 − 0 − 0 − 0 = 96 = 123 − 27`.
      # ⚠️ Направление тут важнее числа: до сих пор перечень двигался только
      # в сторону «стало меньше», и строка, которая умеет двигаться только
      # в одну сторону, однажды перестаёт что-либо проверять.
      assert length(siala.gaps) == 17

      # ...и потерянные названы, а не списаны в остаток: `bullheaded`,
      # `improved_parry` и `bardic_knowledge` из ДРУГОГО файла разметки
      # (`vanilla/feat_skill_bonuses.json`), `zen_archery` из формул,
      # `epic_spell_access` из `vanilla/spellcasting.json`, хит-дайс РДД
      # из `vanilla/classes.json` и штраф брони из `gear.worn`, а не пропавшие
      # факты о классах.
      # Пришедший один — тоже из другого файла
      # (`siala_41/generated/feats.json`), поэтому стоит своим слагаемым.
      # ⚠️ Ещё один замер того дня — `deathless_vigor` — сюда не входит
      # СОЗНАТЕЛЬНО: его гэп жил на БИЛДЕ, а не в данных, и появлялся только
      # у билда с Бледным мастером. Списки данных и билда — разные счётчики,
      # и путать их здесь особенно легко. Ровно по той же границе `zen_archery`
      # из данных ушёл, а на билде без оружия появилась своя оговорка.
      feat_changes = Enum.count(siala.gaps, &match?({:not_modelled, {:feat_change, _, _}}, &1))
      skill_changes = Enum.count(siala.gaps, &match?({:not_modelled, {:skill_change, _, _}}, &1))

      weapon_type =
        Enum.count(siala.gaps, fn gap -> inspect(gap) =~ "weapon_type_bonus" end)

      assert feat_changes == 0
      # ⚠️ 1 → 0 (22.08.2026, задача 3.78): `set_trap / class_skills_unchanged`
      # сверен с ванилью и применён. Явный ноль, а не удалённая строка, —
      # слагаемое обязано ловить возврат гэпа, а не исчезать вместе с ним.
      assert skill_changes == 0
      # ⚠️ 2 → 1 (22.08.2026, задача 3.81): ушла `{:missing_data,
      # :weapon_type_bonus_progression}` — решение Dan «прогрессию делать
      # не будем». Осталась `{:missing_data, {:weapon_type_bonus_weapon,
      # "Вилы"}}`, и она НЕ про величину бонуса, а про то, что оружия нет
      # в справочнике вовсе, — поэтому решение её не касается.
      assert weapon_type == 0

      # ⚠️ Ушедших стало 13 (21.08.2026, задача 3.70): к семи выше добавилась
      # `bonus_spell_slots_from_ability` — таблица бонусных слотов за высокую
      # характеристику каста перенесена в `vanilla/spellcasting.json`. Опять
      # ДРУГОЙ файл, опять не факт о классе шарда.
      #
      # ⚠️ И сразу **15** (21.08.2026, задача 3.71): в тот же день ушли ещё две,
      # и обе — **не переносом механики, а решением Dan**, то есть счёт здесь
      # уменьшился без единой новой посчитанной величины. `spell_circles`
      # описывал решённое неверными словами (шесть эпических заклинаний берутся
      # фитами, которые у нас есть), `attack_bonus_outside_weapon` складывал
      # настоящую недостачу с баффами и песней барда, выведенными из области
      # ответа ещё 10.08.2026. Обе — переучёт в баннере, а не дыра в модели.
      # ⚠️ Ушедших стало **20** (22.08.2026, задача 3.76): к восемнадцати
      # добавились `stonecunning` и `trackless_step`. Причина у них третья
      # по счёту в этой строке: не перенос механики и не чужой получатель,
      # а решение владельца о том, что условие по МЕСТНОСТИ до нашего ответа
      # не доезжает.
      # ⚠️ 20 → 21 (22.08.2026, задача 3.77): ушёл
      # `{:not_modelled, :ability_cap_penalty_interaction}` — взаимодействие
      # штрафа с потолком +12 невыразимо в нашей форме ввода (одно число
      # на характеристику, и оно означает нетто).
      # ⚠️ 21 → 22 (22.08.2026, задача 3.79): ушёл
      # `{:not_modelled, :cleric_domains}` — четвёртая причина подряд из семьи
      # «решение владельца о границе ответа», а не перенос механики: домены
      # выдают заклинания сами, выбирать нечего.
      # ⚠️ 22 → 23 (22.08.2026, задача 3.80): ушла метамагия. Повод тот же
      # четвёртого рода, что у доменов часом раньше, — решение о ГРАНИЦЕ
      # ОТВЕТА: фиты метамагии смоделированы целиком, а её применение —
      # выбор при подготовке или в бою, не при левелапе.
      # ⚠️ 23 → 24 (22.08.2026, задача 3.81): ушла `racial_bonus_progression`,
      # пятая подряд из семьи «решение владельца о границе ответа». ⚠️ Её
      # оружейная близняшка сюда НЕ добавляется, хотя ушла тем же решением
      # в тот же миг: она сидела в слагаемом `weapon_type`, то есть уменьшила
      # обе стороны равенства разом (см. разбор у `length(siala.gaps)` выше).
      # ⚠️ 24 → 26 (24.08.2026, задача 3.85): два факта ЭТОГО файла переехали
      # в применённые, см. разбор у `length(siala.gaps)` выше.
      # ⚠️ 26 → 27 (24.08.2026, задача 3.86): ушла `wizard_opposed_school` —
      # шестая причина в этом перечне и первая своего рода: наш ОТВЕТ дорос
      # до вопроса, а не граница ответа сдвинулась.
      # ⚠️ 27 → 28 (25.08.2026, задача 3.101): факт ЭТОГО файла переехал
      # в применённые, см. разбор у `length(siala.gaps)` выше.
      # ⚠️ 28 → 27 (25.08.2026, задача 3.104), и это ПЕРВОЕ движение вверх
      # у левого края за всю историю перечня: гэп ПРИШЁЛ из другого файла
      # (`vanilla/skills.json` — спор лейбла и категории про тренировку
      # Исполнения), поэтому вычитаемое обязано упасть.
      assert length(siala.gaps) + length(dropped) - feat_changes - skill_changes - weapon_type ==
               123 - 27
    end

    # ⚠️ Инвариант «факт без метки остаётся гэпом» проверяется в двух местах и
    # это не дубль: здесь — что загрузчик такой факт пропускает без падения
    # (см. describe про сторожа ниже), а в `Rules.GapReceiversTest` — что гэп
    # от него действительно появляется, на подменённом рулсете и с обратным
    # контролем. Свойство кода живёт рядом с кодом.
  end

  # ---------------------------------------------------------- сторож словаря --

  # Опечатка в получателе не имеет права означать «не показывать», поэтому
  # словарь закрыт и загрузчик падает — так же, как `Rules.Vocabulary` роняет
  # сборку на форме гэпа без русской подписи. Проверяется через `Loader.load!/1`
  # на полной копии `priv/rules`, у которой испорчен один файл: то же, что
  # делают сторожа `feat_skill_bonuses.json` и `siala_41/skills.json`.
  describe "загрузчик падает на получателе вне словаря" do
    test "чистая копия грузится — иначе `assert_raise` ниже зеленел бы впустую" do
      root = copy_rules()

      assert %{"siala_41" => siala} = Loader.load!(root)

      # 47 → 48 → 52 (14.08.2026): в список данных добавился слой фитов,
      # а тем же днём — слой навыков, см. выше.
      # 52 → 51 (15.08.2026): применено требование шести эпических заклинаний.
      # 51 → 53 (16.08.2026): бонус за тип оружия принёс две оговорки о корпусе.
      # 53 → 52 (16.08.2026): прочитан растущий хит-дайс Ученика красного дракона.
      # 52 → 51 (16.08.2026): посчитан штраф брони к навыкам (задача 3.42).
      # 51 → 50 (16.08.2026): посчитан Bardic Knowledge — сумма уровней барда
      # и Арфиста (замер F7).
      # 50 → 47 (17.08.2026): требования Тайного лучника разобраны ответом Dan —
      # две записи сняты, третья применена (см. арифметику выше).
      # 47 → 44 (17.08.2026): два решения Dan сняли гэп `Improved evasion`
      # (после замера H9) и два гэпа про штраф вора в скрытности (бафф).
      # 44 → 42 (17.08.2026): третья копия того же штрафа (классовая) тоже
      # ушла под баффы, а `craft_trap` применён замером про ловушки ШД.
      # 42 → 40 (17.08.2026, задача про Мастера оружия): обе пары ВМ слиты
      # в одну запись и переставлены на `counted_elsewhere` — ванильная
      # колонка, посчитанная в другом месте.
      # 40 → 38 (17.08.2026, задача «пять файлов прибавок»): `oath_of_wrath`
      # и `small_stature` в `vanilla/feat_skill_bonuses.json` получили
      # affects: buff / special_ability и перестали быть гэпом — см.
      # разбор арифметики в describe «cross-checked against today's
      # ruleset.gaps» выше.
      # 38 → 36 (18.08.2026, задача 3.49): `hp_uses_maximum_hit_die_rolls` и
      # `skill_rank_caps_past_vanilla_cap` перестали быть гэпом для siala_41 —
      # `character.hit_points_roll` и `skills.rank_cap_at_41` их подтверждают
      # (оба `source: user`, Dan, с 2026-08-01), и `Loader.Gaps` теперь их
      # читает — см. ту же арифметику выше.
      # 36 → 35 (21.08.2026, задача 3.70): `bonus_spell_slots_from_ability`
      # перестала быть гэпом на ОБОИХ ruleset'ах — таблица со страницы
      # `fandom:Ability modifier#Spellcasting` лежит в ванильном слое.
      # 33 → 32 (21.08.2026, задача 3.72): `extra_attacks` Тайного лучника
      # применён — условия правила стали записями данных, ядро их читает.
      # 32 → 30 (21.08.2026, задача 3.73): `bonus_feat_pool` Священника
      # и Друида применён — эпические заклинания легли в их бонусный пул.
      # Две записи той же формы (Чемпион Торма, Рейнджер) остались гэпами:
      # источник не называет у них ни уровней, ни состава.
      # 25 → 24 (22.08.2026, задача 3.78): `set_trap / class_skills_unchanged`
      # сверен с ванилью и применён. Первый раз в этом списке двигается слой
      # НАВЫКОВ, а не классов или чужой файл.
      # 24 → 23 (22.08.2026, задача 3.79): снят `{:not_modelled,
      # :cleric_domains}` — решение Dan о границе ответа, а не правка данных:
      # заклинания домена выдаются автоматически, выбирать нечего. Снова
      # мимо всех трёх слоёв разметки, как `bonus_spell_slots_from_ability`
      # и хит-дайс РДД выше.
      # 23 → 22 (22.08.2026, задача 3.80): снята `{:not_modelled, :metamagic}` —
      # то же решение о границе ответа, снова мимо всех трёх слоёв.
      # 22 → 20 (22.08.2026, задача 3.81): сняты ОБЕ формы «прогрессии нет» —
      # расовая и оружейная. Тоже решение Dan о границе ответа и тоже мимо
      # всех трёх слоёв разметки: их источники — `siala_41/races.json`
      # и `siala_41/systems.json`.
      # 20 → 17 (24.08.2026, задача 3.85): применены обе оставшиеся записи
      # `bonus_feat_pool` — замеры U1 и U2 сняли посылку, на которой стояла
      # придержанная половина 3.73. ⚠️ Здесь стояло «две записи той же формы
      # остались гэпом сознательно: источник не называет у них ни уровней,
      # ни состава» — состав называют сами фиты, а уровни назвал замер.
      # 17 → 16 (24.08.2026, задача 3.86): снят `{:not_modelled,
      # :wizard_opposed_school}` — цена специализации волшебника посчитана
      # и напечатана. Снова мимо всех трёх слоёв разметки: источник записи —
      # `vanilla/spellcasting.json`.
      # ⚠️ Здесь считается ЧИСТАЯ КОПИЯ данных, то есть число обязано совпадать
      # с боевым `Data.ruleset!("siala_41")` — этот тест и есть страховка от
      # того, что копия и оригинал разъедутся.
      assert length(siala.gaps) == 17
    end

    test "получатель, которого нет ни в our, ни в not_our" do
      root = copy_rules()
      edit_change(root, "monk", "movement_speed", &Map.put(&1, "affects", ["damge"]))

      assert_raise RuntimeError, ~r/"damge".*neither/s, fn -> Loader.load!(root) end
    end

    test "получатель с опечаткой не проходит и рядом с верным" do
      root = copy_rules()

      edit_change(
        root,
        "monk",
        "movement_speed",
        &Map.put(&1, "affects", ["hp", "movment_speed"])
      )

      assert_raise RuntimeError, ~r/movment_speed/, fn -> Loader.load!(root) end
    end

    test "affects строкой вместо списка" do
      root = copy_rules()
      edit_change(root, "monk", "movement_speed", &Map.put(&1, "affects", "movement_speed"))

      assert_raise RuntimeError, ~r/Expected a non-empty list/, fn -> Loader.load!(root) end
    end

    test "пустой affects: он ничего не утверждает, и молчать про это нельзя" do
      root = copy_rules()
      edit_change(root, "monk", "movement_speed", &Map.put(&1, "affects", []))

      assert_raise RuntimeError, ~r/Expected a non-empty list/, fn -> Loader.load!(root) end
    end

    # ⚠️ Самый опасный случай из всех: без словаря `our` пусто, и если бы код
    # просто «не нашёл нашего получателя», то ПОГАСЛИ БЫ ВСЕ 89 гэпов разом.
    test "словарь пропал, а метки остались" do
      root = copy_rules()
      edit_file(root, &Map.delete(&1, "_receivers"))

      assert_raise RuntimeError, ~r/declares no `_receivers` vocabulary/, fn ->
        Loader.load!(root)
      end
    end

    test "словарь без our-получателей" do
      root = copy_rules()
      edit_file(root, &put_in(&1, ["_receivers", "our"], %{}))

      assert_raise RuntimeError, ~r/declares no `our` receivers/, fn -> Loader.load!(root) end
    end

    test "получатель объявлен и нашим, и не нашим сразу" do
      root = copy_rules()

      edit_file(
        root,
        &put_in(
          &1,
          ["_receivers", "not_our"],
          Map.put(&1["_receivers"]["not_our"], "hp", "и наш, и не наш")
        )
      )

      assert_raise RuntimeError, ~r/both `our` and `not_our`/, fn -> Loader.load!(root) end
    end

    # ⚠️ И обратная сторона сторожа: отсутствие поля — законный случай, а не
    # порча. Загрузчик обязан не падать, а факт — остаться гэпом. Без этого
    # теста сторож заодно запретил бы единственный безопасный способ завести
    # новый факт.
    test "факт без affects загружается и остаётся гэпом" do
      root = copy_rules()
      edit_change(root, "monk", "movement_speed", &Map.delete(&1, "affects"))

      siala = Loader.load!(root)["siala_41"]

      assert {:not_modelled, {:class_change, :monk, "movement_speed"}} in siala.gaps

      # 48 → 49 → 53 (14.08.2026): база выросла вместе со слоями фитов
      # и навыков, а прибавка от снятой метки та же самая — ровно один гэп.
      # 53 → 52 (15.08.2026): база уменьшилась на применённое требование
      # эпических заклинаний, прибавка от снятой метки прежняя.
      # 52 → 54 (16.08.2026): база выросла на две оговорки бонуса за тип оружия,
      # прибавка от снятой метки по-прежнему ровно один гэп.
      # 54 → 53 (16.08.2026): база уменьшилась на прочитанный хит-дайс РДД,
      # прибавка от снятой метки прежняя.
      # 53 → 52 (16.08.2026): база уменьшилась на посчитанный штраф брони,
      # прибавка от снятой метки по-прежнему ровно один гэп.
      # 52 → 51 (16.08.2026): база уменьшилась на посчитанный Bardic Knowledge
      # (замер F7), прибавка от снятой метки прежняя.
      # 51 → 48 (17.08.2026): база уменьшилась на три гэпа Тайного лучника
      # (ответ Dan), прибавка от снятой метки по-прежнему ровно один гэп —
      # 47 + 1. Именно это тест и держит: сколько бы база ни двигалась, снятая
      # метка стоит один гэп, не два и не ноль.
      # 48 → 45 (17.08.2026): база уменьшилась ещё на три (гэп `Improved
      # evasion` плюс два про штраф вора в скрытности), прибавка та же — 44 + 1.
      # 45 → 43 (17.08.2026): база уменьшилась ещё на два — третья копия штрафа
      # вора ушла под баффы, а `craft_trap` применён замером про ловушки ШД, —
      # прибавка от снятой метки по-прежнему ровно один гэп, 42 + 1.
      # 43 → 41 (17.08.2026, задача про Мастера оружия): база уменьшилась ещё
      # на два — обе пары ВМ слиты в одну и переставлены на `counted_elsewhere`
      # — прибавка от снятой метки по-прежнему ровно один гэп, 40 + 1.
      # 41 → 39 (17.08.2026, задача «пять файлов прибавок»): база уменьшилась
      # ещё на два — `oath_of_wrath`/`small_stature` из
      # `vanilla/feat_skill_bonuses.json` перестали быть гэпом (affects: buff /
      # special_ability) — прибавка от снятой метки по-прежнему ровно один
      # гэп, 38 + 1.
      # 39 → 37 (18.08.2026, задача 3.49): база уменьшилась ещё на два —
      # `hp_uses_maximum_hit_die_rolls`/`skill_rank_caps_past_vanilla_cap`
      # теперь подтверждены данными (см. арифметику выше) — прибавка от
      # снятой метки по-прежнему ровно один гэп, 36 + 1.
      # 37 → 36 (21.08.2026, задача 3.70): база уменьшилась ещё на один —
      # `bonus_spell_slots_from_ability` посчитан — прибавка от снятой метки
      # по-прежнему ровно один гэп, 35 + 1.
      # 36 → 35 (21.08.2026, задача 3.72): база уменьшилась ещё на один —
      # `extra_attacks` Тайного лучника применён — прибавка от снятой метки
      # по-прежнему ровно один гэп, 34 + 1.
      # 35 → 33 (21.08.2026, задача 3.73): база уменьшилась ещё на два —
      # `bonus_feat_pool` Священника и Друида применён — прибавка от снятой
      # метки по-прежнему ровно один гэп, 30 + 1.
      # 26 → 25 (22.08.2026, задача 3.78): база уменьшилась на один —
      # `set_trap / class_skills_unchanged` сверен и применён — прибавка
      # от снятой метки по-прежнему ровно один гэп, 24 + 1.
      # 25 → 24 (22.08.2026, задача 3.79): база уменьшилась ещё на один —
      # `cleric_domains` снят решением Dan — прибавка от снятой метки
      # по-прежнему ровно один гэп, 23 + 1. Именно это тест и держит:
      # сколько бы база ни двигалась, снятая метка стоит РОВНО один гэп.
      # 24 → 23 (22.08.2026, задача 3.80): база уменьшилась ещё на один —
      # снята метамагия — прибавка по-прежнему ровно один гэп, 22 + 1.
      # 23 → 21 (22.08.2026, задача 3.81): база уменьшилась на ДВА — сняты
      # обе формы «прогрессии нет» — прибавка по-прежнему ровно один гэп,
      # 20 + 1. Двойное убавление базы тест не смущает: он про прибавку.
      # 21 → 19 (24.08.2026, задача 3.85): база уменьшилась ещё на два —
      # применены обе оставшиеся записи `bonus_feat_pool` (замеры U1 и U2) —
      # прибавка от снятой метки по-прежнему ровно один гэп, 17 + 1.
      # 19 → 18 (24.08.2026, задача 3.86): база уменьшилась ещё на один —
      # снят `wizard_opposed_school` — прибавка по-прежнему ровно один гэп,
      # 16 + 1.
      assert length(siala.gaps) == 18

      # Положительный контроль: на чистой копии этого гэпа нет, то есть он
      # появился от снятой метки.
      refute {:not_modelled, {:class_change, :monk, "movement_speed"}} in Loader.load!(
               copy_rules()
             )["siala_41"].gaps
    end
  end

  # --------------------------------------------------- the sibling file left --

  # ⚠️ ПЕРЕПИСАНО задачей «пять файлов прибавок», 17.08.2026 — заголовок describe
  # теперь ЛОЖЬ, а не факт: файл ТРОНУТ, и ровно так, как предсказывал
  # `_task_3_28_note` («кандидат на будущую задачу»). Старый текст ниже не
  # выброшен — трёхступенчатая история (7 → 5 → 4 имени в списке) объясняет,
  # почему список короче семи not_modelled-записей файла, и это по-прежнему
  # верно; добавлен только четвёртый шаг, тем же приёмом.
  describe "vanilla/feat_skill_bonuses.json — теперь тоже несёт affects" do
    # ⚠️ Заголовок теста был «still exactly 4 gaps… unnamed change would be a
    # silent drift», и утверждение стало ложным в буквальном смысле — гэпов
    # 2, а не 4. Дрифта тут нет: разметка сделана этой же задачей, а не
    # тихо. Подробный разбор классификации (все 7 not_modelled записей,
    # не только те, что доезжают до ruleset.gaps) — в
    # `BuildCalculator.Data.FeatSkillBonusesTest`, describe «получатели
    # факта (affects)»; здесь — только то, что касается ЭТОГО файла (данные
    # прогона `ruleset.gaps`, а не JSON).
    test "0 gaps of this form — двое ушли под свои получатели, двое решением владельца" do
      siala = Data.ruleset!("siala_41")
      ids = for {:not_modelled, {:feat_skill_bonus, id}} <- siala.gaps, do: id

      # ⚠️ Здесь стояло семь имён; 13.08.2026 их стало пять. `bullheaded`
      # и `improved_parry` ушли замерами F4 и F5 — у первого в листе видно
      # только +1 Will (это сейв, не навык), у второго прибавка живёт лишь под
      # включённым Парированием, то есть под баффом. Оба переведены
      # в `not_a_skill_bonus`: не «не посчитали», а «прибавки к значению навыка
      # тут нет вовсе».
      #
      # ⚠️ 16.08.2026 их стало четыре, и по ТРЕТЬЕЙ причине из возможных:
      # `bardic_knowledge` не «не про навык» и не «не посчитан» — он ПОСЧИТАН
      # (замер F7, прибавка равна сумме уровней барда и Арфиста). Три способа
      # потерять имя из этого списка стоит различать: запись про другое, запись
      # не считается, запись считается.
      #
      # ⚠️ 17.08.2026 их стало ДВА, и это ЧЕТВЁРТЫЙ способ потерять имя из
      # списка — не про эту запись (те три способа никуда не делись), а про
      # МЕХАНИЗМ: до этой задачи `Data.Loader.gaps/15` печатал ВЕСЬ
      # `skill_bonuses.unmodelled` безусловно, а с 17.08.2026 тот же цикл
      # фильтруется через `Rules.GapReceivers.ours?/2`, той же функцией,
      # которой уже фильтруются `class_change`/`feat_change`/`skill_change`
      # тремя строками выше в `gaps/15`. `oath_of_wrath` (affects: buff —
      # разовая цель раз в день) и `small_stature` (affects: special_ability
      # — источник прямо говорит, что это не значение навыка) ушли; у
      # `stonecunning`/`trackless_step` affects: skill_values, и они остались
      # — оба УСЛОВНЫЕ (по местности), но не ВРЕМЕННЫЕ, а фильтр разводит
      # именно эти два случая.
      # ⚠️ 2 → 0 (22.08.2026, задача 3.76): к двоим, ушедшим ПО ПОЛУЧАТЕЛЮ
      # (`oath_of_wrath` — buff, `small_stature` — special_ability), добавились
      # двое, ушедшие ПО РЕШЕНИЮ владельца. Причины разные, и различать их
      # обязательно: у последних `affects` по-прежнему `["skill_values"]`.
      assert ids == []
    end

    # ⚠️ И обратная сторона, специфичная именно для ЭТОГО файла (не ac/attack/
    # hp/ability): у vanilla ruleset'а список НЕ сузился — там по-прежнему
    # пять имён, `epic_skill_focus` включая. `gap_receivers!(:missing)` даёт
    # vanilla два пустых множества, а пустой `our` — это «фильтра нет вообще»,
    # а не «ничего не наше» (см. moduledoc `Rules.GapReceivers`, «vanilla,
    # синтетический ruleset»). Положительный контроль к тесту выше: разница
    # 4 → 2 у siala и 5 → 5 у vanilla доказывает, что сузило именно НАЛИЧИЕ
    # словаря, а не что-то ещё в загрузчике.
    test "у vanilla список не сузился — там нет словаря, значит нет и фильтра" do
      vanilla = Data.ruleset!("vanilla")
      ids = for {:not_modelled, {:feat_skill_bonus, id}} <- vanilla.gaps, do: id

      # ⚠️ 22.08.2026 (задача 3.76): пятёрка стала тройкой — `stonecunning`
      # и `trackless_step` ушли решением владельца (`not_a_gap`), которое
      # читается до проверки словаря и потому одинаково на обоих слоях.
      assert Enum.sort(ids) == [:epic_skill_focus, :oath_of_wrath, :small_stature]
    end

    test "the file records that it was reviewed, and that the review is now closed" do
      assert is_binary(@feat_skill_bonuses["_task_3_28_note"])
      assert @feat_skill_bonuses["_task_3_28_note"] =~ "3.28"
      assert @feat_skill_bonuses["_task_3_28_note"] =~ "ЗАКРЫТО"
    end
  end

  # ------------------------------------------------------------- испорченная копия --

  # Полная копия `priv/rules`, чтобы `load!/1` видел всё как обычно и отличался
  # только испорченный файл — тот же приём, что у сторожей `feat_skill_bonuses`
  # и `siala_41/skills.json`.
  defp copy_rules do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp edit_change(root, class_id, what, fun) do
    edit_file(root, fn data ->
      classes =
        Enum.map(data["classes"], fn class ->
          if class["id"] == class_id do
            changes =
              Enum.map(class["changes"], fn change ->
                if change["what"] == what, do: fun.(change), else: change
              end)

            Map.put(class, "changes", changes)
          else
            class
          end
        end)

      Map.put(data, "classes", classes)
    end)
  end

  defp edit_file(root, fun) do
    path = Path.join(root, "siala_41/classes.json")
    data = path |> File.read!() |> Jason.decode!()
    File.write!(path, Jason.encode!(fun.(data)))
  end
end
