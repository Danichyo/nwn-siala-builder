defmodule BuildCalculatorWeb.EnGuardTest do
  @moduledoc """
  en-сторож — храповик кириллицы в английской редакции (задача 4.3,
  VANILLA.md §4.3).

  Ванильная редакция говорит по-английски, а интерфейс переведён на `gettext`
  лишь частично: остальное — сырые русские литералы, их переведут заходы
  4.11+ по файлу. Этот тест МЕРИТ, сколько русского ещё видит игрок ванили,
  по зонам, и не даёт числу ни расти, ни незаметно стоять на месте:

    * **число на каждую зону записано здесь** (`@ceilings`);
    * **выросло** — тест падает и перечисляет новое: русский текст в английскую
      редакцию не добавляется, его заводят через `gettext` (английский msgid,
      русский `msgstr`);
    * **уменьшилось** — тест падает с просьбой опустить число: так каждый заход
      перевода обязан сдвинуть храповик, а откатиться незаметно нельзя.

  ## Что считается

  Кириллические СЛОВА (`\\p{Cyrillic}+`) в том, что увидит игрок ванили:

    * `builder_empty`, `builder_typical` — отрисовка конструктора: пустой билд
      и типичный (Fighter 20 / Weapon Master 20, легальный на ванили);
    * `builder_gear` — блок «Вещи» того же билда, открытый (`#gear-panel`);
    * `view` — экран просмотра того же билда;
    * `sources` — `/sources`;
    * `export` — текст экспорта (`Export.text/4`);
    * `gap_labels` — подписи всех форм гэпов (`Rules.gap_forms/0` через
      `Labels.gap/2`) с заголовком их группы; у всех трёх каталогов — кроме
      форм шарда (`@siala_only_forms`, задача 4.18): ваниль их не производит;
    * `reason_labels` — все формы причин отказа (`Rules.reason_forms/0` через
      `Labels.reason/2`);
    * `feat_reason_labels` — собственные причины выбора фитов
      (`Builder.Feats.reason_forms/0`);
    * `import_issues` — все замечания импорта текста (`Import.issue_forms/0`):
      на ванили импорт виден (VANILLA.md §1). Образцы чужого ввода в формах
      с задачи 4.53 английские, как сама вставка ECB: эхо вставленного — не
      текст сайта, и считаться здесь не должно;
    * `import_window` — окно импорта ПОСЛЕ вставки (задача 4.34): сводка
      прочитанного (`ImportPanel`), итоги источника рядом с нашими
      (`Import.comparison/2`, «голым» у AC), строка «прочиталось всё» и флеш
      принятия. Две синтетические вставки по образцу строк ECB — полная, с
      итогами, и скудная, где раса, мировоззрение и лист не прочитаны, а фит
      не узнан. Слова самих замечаний — зона `import_issues`, здесь их нет.
      До этой зоны окно не видела ни одна: оно рисуется только после вставки.

  Отрисовка — вся разметка LiveView, атрибуты включительно: `title`,
  `aria-label`, `placeholder` и JSON поп-апов игрок тоже читает, а скрытый
  диалог — открывает. Корневой макет (`root.html.heex`) не считается: из
  видимого там только заголовок вкладки, его стережёт `edition_test.exs`.

  ## Опись — чтобы «перечисляет новое» было правдой

  Одно число не знает, ЧТО прибавилось. Поэтому рядом с числом лежит опись
  зоны — `test/fixtures/en_guard/<зона>.txt`, строка «сколько раз⇥фраза»
  (фраза — кириллические слова подряд, разделённые только пробелами и знаками
  препинания). По ней тест называет, какие фразы прибавились или ушли.
  Сравнение описи с отрисовкой идёт по МУЛЬТИМНОЖЕСТВУ слов, а не по фразам:
  порядок перечислений, собранных из карт, от сборки к сборке законно
  плавает, и фраза «А · Б» может стать «Б · А» — слова от этого не меняются.

  Когда храповик сдвинулся, в одном коммите меняются двое: число
  в `@ceilings` — руками (тест называет, на какое), и опись — командой
  (`git diff test/fixtures/en_guard` после неё показывает, что именно
  переведено):

      EN_GUARD_WRITE=1 mix test test/build_calculator_web/live/en_guard_test.exs

  Опись, не переписанная вместе с числом, роняет тест сама: её сумма слов
  обязана равняться числу.

  ## Два контроля

    * **положительный** — английский текст на месте: бренд, подписи этой
      задачи (`Copied`, группы итогов, типы AC). Без него ноль кириллицы
      у пустой страницы выглядел бы победой;
    * **сторож не слепой** — на сиальской редакции тот же счёт по тем же зонам
      видит много кириллицы: в каждой зоне не меньше, чем записано у ванили.

  ## Второй сторож — ни Сиалы, ни шарда (задача 4.4)

  Не храповик, а ноль: слова «Сиал…», «Siala», «шард…», «shard» игрок ванили
  не видит нигде. Проверяется на всём, что ванильный сайт рисует сам:

    * **зоны-отрисовки** выше (`builder_*`, `view`, `sources`, `export`) и
      замечания импорта (импорт текста на ванили виден, любое его замечание
      достижимо вставкой) — строго ноль;
    * **две поверхности сверх зон** — то, что 4.4 правила и что зоны не
      открывают: панель пробелов конструктора раскрытой (`#gaps-body`) и билд,
      упёршийся в потолок (подсказка `.capped`);
    * **каталоги форм** (`gap_labels`, `reason_labels`, `feat_reason_labels`)
      — не отрисовка, а подписи ВСЕХ форм, и часть форм производят только
      данные шарда. Их подписи называют Сиалу законно, но список таких форм
      закрыт (`@siala_only_forms`, у каждой — почему ваниль её не производит,
      и сверка ванильных данных). Единственная утечка, известная с 4.4, —
      оговорка про Spellcraft против AOE, которую ставила и ваниль, — закрыта
      задачей 4.23 и переехала в этот список со сверкой: на ванили тот же
      билд её не получает, на Сиале получает.

  Мостик, открытый чужой ссылкой, в поверхности не входит: он и должен
  назвать чужие правила по имени. Положительный контроль — на Сиале те же
  `sources` и билд у потолка называют Сиалу.

  ⚠️ `async: false` — `use_edition/1` меняет редакцию ПРИЛОЖЕНИЯ
  (`Application.put_env/3`); параллельный сосед в той же VM увидел бы чужой
  сайт (CLAUDE.md §7).
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BuildCalculatorWeb.EditionHelpers

  alias BuildCalculator.{AccountsFixtures, Data, Encoding, LibraryFixtures, Rules}
  alias BuildCalculator.Rules.{Build, Gear, Skills}
  alias BuildCalculatorWeb.Builder.{Export, Feats, Gaps, Import, Labels}
  alias BuildCalculatorWeb.Edition

  # Храповик: кириллических слов в зоне ванильной редакции, не больше и не
  # меньше. Двигается только вниз — вместе с описью в `@inventory_dir`.
  @ceilings %{
    builder_empty: 0,
    builder_typical: 0,
    builder_gear: 0,
    view: 0,
    sources: 0,
    export: 0,
    gap_labels: 0,
    reason_labels: 0,
    feat_reason_labels: 0,
    import_issues: 0,
    import_window: 0
  }

  @zones [
    :builder_empty,
    :builder_typical,
    :builder_gear,
    :view,
    :sources,
    :export,
    :gap_labels,
    :reason_labels,
    :feat_reason_labels,
    :import_issues,
    :import_window
  ]

  @inventory_dir "test/fixtures/en_guard"
  @write_env "EN_GUARD_WRITE"
  @command "EN_GUARD_WRITE=1 mix test test/build_calculator_web/live/en_guard_test.exs"

  @word ~r/\p{Cyrillic}+/u
  @phrase ~r/\p{Cyrillic}+(?:[\s\p{P}]+\p{Cyrillic}+)*/u

  # Между подписями в зонах-списках: `|` — математический символ, не знак
  # препинания, и фразу описи рвёт. Через перевод строки соседние подписи
  # слиплись бы в одну «фразу», и опись не назвала бы, какая из них новая.
  @label_separator "\n|\n"

  # Две вставки окна импорта (задача 4.34), синтетические, по образцу строк ECB:
  # полная — с листом и итогами, прочитанная вся (окно сравнения, «прочиталось
  # всё»); скудная — одна лестница с неузнанным фитом (сводка «не прочитано»,
  # флеш с числом непрочитанного). Имена — английские: русское в зоне — только
  # то, что пишет сам сайт.
  @import_full """
  Whirling Blade - Fighter(4)
  Human, Lawful Neutral
  STR/DEX/CON/WIS/INT/CHA: 16/14/14/10/14/8 (17/14/14/10/14/8)
  Hitpoints: 46
  Skillpoints: 32
  Saving Throws (Fort/Ref/Will): 6/3/1
  BAB: 4
  AB: 7
  AC (naked/mundane): 12/20

  SKILLS:
  Intimidate 7 (7)

  LEVELING GUIDE
  01: Fighter(1): Dodge, Weapon Focus: Longsword, Intimidate(4)
  02: Fighter(2): Mobility, Intimidate(1)
  03: Fighter(3): Expertise, Intimidate(1)
  04: Fighter(4): STR+1, Spring Attack, (STR=17), Intimidate(1)
  """

  @import_sparse """
  01: Fighter(1): Dodge, Mystic Strike
  02: Fighter(2): Mobility
  """

  # Задача 4.47: синтетический лог `.билд+` по образцу настоящих, английский
  # целиком — кириллица в окне после его вставки могла бы прийти только из
  # нашего текста. Три уровня (их сводка), Dodge в слоте, предмет в руке,
  # свойство «не наше» (Cast Spell) и свойство, имени которого мы не знаем
  # («не сложить без сервера»); мировоззрения в логе нет — замечание.
  @game_log """
  ------------------------------------------------
      CHARACTER BUILD: Probe
      Current: 3 FTR
  ------------------------------------------------

  CURRENT ABILITIES: STR 16 DEX 14 CON 14 INT 14 WIS 10 CHA 8
  COMBAT STATS: AB 5 AC 12 Fort 5 Refl 3 Will 1
  SKILLS WITH RANKS:
    Discipline 6

  (WHITE) ABILITIES: STR 16 DEX 14 CON 14 INT 14 WIS 10 CHA 8
  RACE: Human

  ------------------------------------------------
  LEVEL 1: FIGHTER
    FEATS: Dodge
    SKILLS: Discipline +4
  ------------------------------------------------
  LEVEL 2: FIGHTER
    SKILLS: Discipline +1
  ------------------------------------------------
  LEVEL 3: FIGHTER
    SKILLS: Discipline +1
  === Equipped: Probe ===
  MINI SET PIECES: 0
  CRAFT ITEMS: 0
  [RIGHTHAND] Fine Sword (Longsword) [BaseItem:1]
    [1] Attack Bonus (0) 2
    [2] Cast Spell (Light) 1
  [HEAD] Helm
    [1] Frobnicate (0) 3
  """

  # ---- второй сторож: ни Сиалы, ни шарда (задача 4.4) -----------------------

  @siala_word ~r/сиал\p{L}*|siala\p{L}*|шард\p{L}*|shard\p{L}*/iu

  # То, что ванильный сайт рисует сам, и замечания импорта (любое достижимо
  # вставкой текста) — строго ноль.
  @siala_free_zones [
    :builder_empty,
    :builder_typical,
    :builder_gear,
    :view,
    :sources,
    :export,
    :import_issues,
    :import_window
  ]

  @catalog_zones [:gap_labels, :reason_labels, :feat_reason_labels]

  # Формы, которые производят ТОЛЬКО данные шарда: их подпись называет Сиалу
  # законно. Сэмплы — те же, что в `Rules.gap_forms/0` / `reason_forms/0` /
  # `Feats.reason_forms/0`. Почему ваниль формы не производит — у каждой;
  # сверка по ванильным данным — тест «формы шарда ваниль не производит».
  @siala_only_forms %{
    gap_labels: [
      # «Дух Сиалы» — запись `character.spirit_of_siala` есть только у шарда.
      {:missing_data, :innate_hp_bonus},
      # Бонус за тип оружия — система оружия шарда (`systems.json`).
      {:missing_data, {:weapon_type_bonus_weapon, "Вилы"}},
      # Ставит только слой шарда, у ванили `ruleset.gaps` её не несёт.
      {:assumed, :class_unavailable_feats_vanilla},
      # Фит, выключенный шардом по выводу: у ванили выключенных фитов нет.
      {:assumed, {:feat_disabled, :weapon_proficiency_monk}},
      # Замещение у ванили процитировано, оговорки нет (`Rules.Resistances`).
      {:assumed, :resist_energy_superseded_by_epic},
      # Факты шарда о классе, фите, навыке (`siala_changes`): у ванили их ноль.
      {:not_modelled, {:class_change, :weapon_master, "attack_bonus_progression"}},
      {:not_modelled, {:feat_change, :improved_evasion, "siala_note"}},
      {:not_modelled, {:skill_change, :spellcraft, "save_bonus"}},
      # Сужение области Spellcraft (не против AOE) — только в слое шарда
      # (`scope_excludes`); у ванили `nil` с задачи 4.1, и с задачи 4.23 ядро
      # спрашивает оговорку у сужения, а не у области. До 4.23 — утечка.
      {:not_modelled, {:save_bonus_scope, :spellcraft}},
      # Категория владения, назначенная нами оружию шарда (`proficiency_assumed?`).
      {:assumed, {:weapon_proficiency_group, :scimitar, :blade}}
    ],
    reason_labels: [
      {:feat_disabled, :devastating_critical},
      {:not_on_shard, :lance}
    ],
    feat_reason_labels: [
      {:feat_disabled, :devastating_critical}
    ]
  }

  describe "ванильная редакция (en): ни Сиалы, ни шарда" do
    setup do
      use_edition(:vanilla)
      Gettext.put_locale(BuildCalculatorWeb.Gettext, Edition.locale())
      :ok
    end

    for zone <- @siala_free_zones do
      test "#{zone}", %{conn: conn} do
        assert_siala_free!(unquote(zone), zone_text(unquote(zone), conn))
      end
    end

    # ⚠️ Посылка сменилась в задаче 4.7: здесь стояло «в панели блок дыр
    # в данных — у ванили одна настоящая дыра, заголовок блока английский».
    # Дыру закрыл выбор навыка у `Epic skill focus` (таблица игры), и блок
    # данных у ванили закрыт теми же воротами (`data_real_count > 0`), что
    # у Сиалы; раскрытая панель несёт пробелы билда, и они проверяются так же.
    test "панель пробелов конструктора раскрыта", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{typical_code()}")
      view |> element("#gaps-toggle") |> render_click()

      assert has_element?(view, "#gaps-body")
      refute has_element?(view, "#gaps-data")

      assert_siala_free!(:gaps_panel, view |> element("#gaps-body") |> render())
    end

    test "число у потолка: подсказка без имени правил", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{capped_code()}")

      assert has_element?(
               view,
               ~s(#stat-ability-str .capped[title="The number hit the cap of the rules — it goes no higher"])
             )

      assert_siala_free!(:capped, render(view))
    end

    test "каталоги форм: Сиалу называют только формы шарда" do
      for zone <- @catalog_zones do
        named = siala_named_forms(zone)
        declared = Map.get(@siala_only_forms, zone, [])

        assert Enum.sort(named) == Enum.sort(declared), """
        #{zone}: Сиалу или шард называют подписи форм #{inspect(named -- declared)},
        которых нет в @siala_only_forms, или список отстал
        (#{inspect(declared -- named)} больше Сиалу не называют).

        Новая подпись с Сиалой: если форму производит и ваниль — сделай английский
        msgid нейтральным (русский msgstr — прежний литерал); если только данные
        шарда — внеси её в @siala_only_forms с причиной и сверкой данных.
        """
      end
    end

    test "формы шарда ваниль не производит — сверка данных" do
      ruleset = ruleset()

      # Ни одна форма-исключение не стоит в `ruleset.gaps` ванили.
      exempt = @siala_only_forms |> Map.values() |> List.flatten()
      exempt_forms = BuildCalculator.Rules.Vocabulary.forms(exempt)

      assert MapSet.disjoint?(BuildCalculator.Rules.Vocabulary.forms(ruleset.gaps), exempt_forms)

      # Данные, из которых эти формы берутся, у ванили пусты.
      assert Gaps.shard_facts?(ruleset) == false
      assert ruleset.innate_hp_bonus == nil
      refute Enum.any?(ruleset.feats, fn {_id, feat} -> Map.get(feat, :disabled?, false) end)
      refute Enum.any?(ruleset.weapons, fn {_id, w} -> Map.get(w, :on_shard?) == false end)

      refute Enum.any?(ruleset.weapons, fn {_id, w} ->
               Map.get(w, :proficiency_assumed?, false)
             end)

      # Замещение Resist energy эпическим у ванили процитировано — оговорки нет;
      # тот же билд на Сиале её получает (контроль, что билд её вообще вызывает).
      supersede = fn version ->
        build =
          Build.new(
            ruleset_version: version,
            race: :human,
            alignment: :true_neutral,
            levels: List.duplicate(:fighter, 21),
            feats: %{
              1 => %{:general => {:resist_energy, :fire}},
              21 => %{:epic_general => {:epic_energy_resistance, :fire}}
            }
          )

        {:assumed, :resist_energy_superseded_by_epic} in Rules.compute(
          build,
          Data.ruleset!(version)
        ).gaps
      end

      refute supersede.(ruleset.version)
      assert supersede.("siala_41")

      # Сужения области Spellcraft (не против AOE) у ванили нет — оговорку
      # о нём ядро не ставит (задача 4.23; до неё ставило, это была утечка 4.4).
      # Тот же билд на Сиале её получает — контроль, что билд её вызывает;
      # сама прибавка «против заклинаний» при этом есть на обоих.
      refute Enum.any?(ruleset.skill_rules.save_bonus, &Skills.unmodelled_scope?/1)

      spellcraft_scope = fn version ->
        build =
          Build.new(
            ruleset_version: version,
            race: :human,
            alignment: :true_neutral,
            levels: [:wizard, :wizard, :wizard],
            skills: %{1 => %{spellcraft: 4}, 2 => %{spellcraft: 1}, 3 => %{spellcraft: 1}}
          )

        stats = Rules.compute(build, Data.ruleset!(version))
        assert stats.conditional_save_bonus == %{fort: 1, ref: 1, will: 1}
        {:not_modelled, {:save_bonus_scope, :spellcraft}} in stats.gaps
      end

      refute spellcraft_scope.(ruleset.version)
      assert spellcraft_scope.("siala_41")
    end
  end

  describe "контроль: сторож Сиалы не слепой" do
    setup do
      use_edition(:siala)
      Gettext.put_locale(BuildCalculatorWeb.Gettext, Edition.locale())
      :ok
    end

    test "на Сиале те же поверхности называют Сиалу и шард", %{conn: conn} do
      assert siala_words(zone_text(:sources, conn)) > 0

      {:ok, view, _html} = live(conn, ~p"/?b=#{capped_code()}")
      assert has_element?(view, "#stat-ability-str .capped")
      assert siala_words(render(view)) > 0
    end
  end

  describe "ванильная редакция (en): храповик кириллицы по зонам" do
    setup do
      use_edition(:vanilla)
      Gettext.put_locale(BuildCalculatorWeb.Gettext, Edition.locale())
      :ok
    end

    for zone <- @zones do
      test "#{zone}", %{conn: conn} do
        check_ratchet!(unquote(zone), zone_text(unquote(zone), conn))
      end
    end

    test "положительный контроль: английский текст на месте", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{typical_code()}")

      # Бренд редакции.
      assert text(view, "#builder-header .brand b") == "Build Calculator"

      # Подписи этой задачи: подпись `.CopyLink`, группы панели итогов (до 4.3 —
      # модульный атрибут, застывший бы на русском).
      assert has_element?(view, ~s(#copy-link[data-label-copied="Copied"]))
      assert text(view, "#stat-group-vital .sgroup-h") == "Defense"
      assert text(view, "#stat-group-save .sgroup-h") == "Saves"

      # Навыки 1-го уровня: бюджет согласован по-английски (`ngettext`).
      # ⚠️ Подпись — первый `<span>` рядом с числом, поэлементно: текст всего
      # `#skill-budget` склеивает «12» и «points» (HANDOFF.md, 4.2, п. 3).
      view |> element("#level-1") |> render_click()
      assert text(view, "#skill-budget-free") == "12"
      assert view |> texts("#skill-budget > span") |> hd() == "points free"
      assert text(view, "#section-skills") =~ "12 points unspent"

      # «Вещи»: типы AC и надетое — из gettext по id, не из русских полей данных.
      view |> element("#gear-toggle") |> render_click()
      assert text(view, "#gear-ac-armor .gear-k") == "Armor"
      assert text(view, "#gear-ac-dodge .gear-k") == "Dodge"
      assert text(view, "#gear-worn-armor .gear-k") == "Body armor"

      # Разряды гэпов не зависят от языка (до 4.3 под en настоящих групп было
      # четыре). ⚠️ Здесь стояло «у ванили одна настоящая группа, и её
      # заголовок английский»: задача 4.7 закрыла последнюю настоящую дыру
      # ванили, раздела нет, как у Сиалы, а английские заголовки проверяет
      # решённый разряд ниже. Язык разрядов при настоящей дыре держит
      # `gaps_test.exs` синтетикой.
      {:ok, sources, _html} = live(conn, ~p"/sources")

      refute has_element?(sources, "#sources-gaps-real")

      assert sources
             |> texts("#sources-gaps-resolved h4")
             |> Enum.map(&String.replace(&1, ~r/ · \d+$/, "")) ==
               ["Derived, not read", "Sources disagree"]
    end

    # Задача 4.53: окно импорта текста — последняя зона нарезки. Ноль кириллицы
    # в `import_window` и `import_issues` без английского текста рядом был бы
    # победой и у пустого окна. Сводка, окно сравнения («naked» у AC), замечание
    # с образцом чужого ввода и флеш принятия — английские.
    test "положительный контроль: окно импорта текста", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#import-button") |> render_click()

      assert text(view, "#import-title") == "Import a build from text"
      assert text(view, "#import-parse") == "Read the build"

      view |> form("#import-form", %{"import" => %{"text" => @import_full}}) |> render_submit()

      assert texts(view, "#import-read-levels > span, #import-read-levels > b") ==
               ["Levels", "4 of 40"]

      assert texts(view, "#import-read-abilities > span, #import-read-abilities > b") ==
               ["Abilities", "read"]

      assert "12 naked" in texts(view, "#import-compare .import-cmp-r b")
      assert text(view, "#import-clean") == "Everything the format carries was read."

      view |> form("#import-form", %{"import" => %{"text" => @import_sparse}}) |> render_submit()

      assert texts(view, "#import-read-race > span, #import-read-race > b") ==
               ["Race", "not read"]

      assert text(view, "#import-issues") =~ "level 1: no feat “Mystic Strike” in our list"

      view |> element("#import-apply") |> render_click()
      assert text(view, "#flash-info") =~ "Build imported. Not read:"
    end

    # Задача 4.47: окно лога `.билд` есть только на Сиале (на ванили флаг
    # выключен, VANILLA.md §1), но его текст тоже через gettext — английский
    # msgid нужен, даже если его сегодня никто не видит (CLAUDE.md §4). Флаг
    # включён на время теста (`use_edition/1` вернёт его сам). Ноль кириллицы
    # в окне без английского текста рядом был бы победой и у пустого окна:
    # заголовок, сводка, замечание, экипировка по вёдрам и флеш — английские.
    test "положительный контроль: окно лога .билд (флаг включён)", %{conn: conn} do
      Application.put_env(:build_calculator, :game_log_import_ui, true)
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#game-log-import-button") |> render_click()

      assert text(view, "#game-log-import-title") == "Import a build from the game log"
      assert text(view, "#game-log-import-parse") == "Read the build"

      assert text(view, "#game-log-import-encoding-notice") =~
               "must use the windows-1251 encoding for the chat log"

      view
      |> form("#game-log-import-form", %{"game_log_import" => %{"text" => @game_log}})
      |> render_submit()

      assert texts(view, "#game-log-import-read-levels > span, #game-log-import-read-levels > b") ==
               ["Levels", "3 of 40"]

      assert texts(
               view,
               "#game-log-import-read-feats-placed > span, #game-log-import-read-feats-placed > b"
             ) == ["Feats in slots", "1"]

      assert text(view, "#game-log-import-issues") =~
               "the log doesn't show the character's alignment — set it by hand"

      assert text(view, "#game-log-import-gear-applied-hands") =~ "Main hand: Longsword +2"
      assert text(view, "#game-log-import-gear-not-ours summary") == "Not ours (1)"

      assert text(view, "#game-log-import-gear-unresolved") =~
               "property name not recognized — the server may have changed how it prints"

      assert words(view |> element("#game-log-import-dialog") |> render()) == 0

      view |> element("#game-log-import-apply") |> render_click()

      assert text(view, "#flash-info") =~
               "Build imported — everything the log carries was read. Set the alignment by hand."
    end

    # Подписи видимости (до 4.3 — модульный атрибут `@visibilities`, застывший
    # бы на русском). Форма живёт по прямому адресу и под спрятанными
    # аккаунтами (`build_form_live_test.exs`), поэтому проверяется и здесь.
    test "положительный контроль: форма сохранения, подписи видимости", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      {:ok, form, _html} = live(conn, ~p"/builds/new?b=#{typical_code()}")

      assert texts(form, "#build-visibility option") == [
               "Private — only I can see it",
               "Public — in the shared feed",
               "Group — visible to group members"
             ]
    end

    # Задача 4.48: библиотека, группы, форма сохранения, вход, регистрация,
    # подтверждение и настройки. Аккаунты спрятаны флагом в обеих редакциях,
    # но текст идёт через gettext (CLAUDE.md §4), и английский msgid нужен уже
    # сегодня. Флаг включён на время теста (`use_edition/1` вернёт его сам).
    # Ноль кириллицы на странице без английского текста рядом был бы победой
    # и у пустой страницы: у каждой — заголовок, подписи, кнопки и флеш
    # по-английски, плюс ошибки форм из домена `errors`.
    test "положительный контроль: библиотека и аккаунты (флаг включён)", %{conn: guest} do
      Application.put_env(:build_calculator, :accounts_ui, true)
      %{conn: conn, scope: scope, user: user} = register_and_log_in_user(%{conn: guest})
      group = AccountsFixtures.group_fixture(scope, %{name: "Guild"})
      vanilla = ruleset().version

      LibraryFixtures.build_fixture(scope, %{
        name: "Bare",
        visibility: :public,
        code: LibraryFixtures.build_code(ruleset_version: vanilla, race: nil, levels: [])
      })

      # Лента: заголовок, раздел, фильтры, подсказка, карточка «голого» билда.
      {:ok, library, _html} = live(guest, ~p"/library")
      assert text(library, "#library-title") == "Public builds"
      assert text(library, "#section-public") == "Public"
      assert text(library, "#clear-filters") == "Clear filters"

      assert text(library, "#filters-hint") ==
               "“From / to” counts character levels; pick a class to count its levels instead."

      assert texts(library, "#builds .bcard-total") == ["0 lv."]
      assert texts(library, "#builds .bcard-race") == ["no race picked"]
      assert texts(library, "#builds .bcard-empty") == ["no classes picked"]
      assert texts(library, "#builds .bcard-vis") == ["public"]

      {:ok, empty, _html} = live(guest, ~p"/library?q=zzzz")

      assert text(empty, "#builds-empty") ==
               "Nothing here. No public builds match these filters."

      {:ok, mine, _html} = live(conn, ~p"/library/mine")
      assert text(mine, "#library-title") == "My builds"
      assert text(mine, "#section-mine") == "Mine"

      {:ok, feed, _html} = live(conn, ~p"/library/group/#{group}")
      assert text(feed, "#library-title") == "Group builds · Guild"

      assert text(feed, "#builds-empty") ==
               "Nothing here. Nobody has shared a build with the group yet."

      # Группы: список, страница группы, отказ по коду.
      {:ok, groups, _html} = live(conn, ~p"/groups")
      assert text(groups, "#group-#{group.id} .grow-role") == "owner"
      assert text(groups, "#create-group-submit") == "Create"
      assert text(groups, "#join-group-submit") == "Join"

      groups
      |> form("#join-group-form", %{"join" => %{"invite_code" => "nope"}})
      |> render_submit()

      assert text(groups, "#flash-error") =~ "That invite code doesn't exist."

      {:ok, page, _html} = live(conn, ~p"/groups/#{group}")
      assert text(page, "#group-feed") == "Group builds"
      assert "Group builds · you're the owner" in texts(page, "#group-page .page-sub")
      assert text(page, "#member-#{user.id} .grow-role") == "owner"
      assert text(page, "#rotate-code") == "Change code"
      assert text(page, "#leave-group") == "Leave group"

      # Форма сохранения: заголовок, уровни, группа без выбора — ошибка
      # домена `errors` (до 4.48 — русский литерал в контексте).
      {:ok, form, _html} = live(conn, ~p"/builds/new?b=#{typical_code()}")
      assert text(form, "#build-form-page .page-title") == "Save build"
      assert text(form, "#build-preview .bcard-total") == "40 lv."
      assert text(form, "#build-cancel") == "Cancel"

      render_hook(form, "save", %{"build" => %{"name" => "X", "visibility" => "group"}})

      assert text(form, "#build-group-error") ==
               "Pick a group: a build with “group” visibility has to name one."

      # Вход, регистрация, подтверждение, настройки.
      {:ok, login, _html} = live(guest, ~p"/users/log-in")
      assert text(login, "#login-magic-submit") == "Email me a log-in link"
      assert text(login, "#to-register") == "Sign up"
      assert text(login, "#login-password-once") == "Log in only this time"

      {:ok, register, _html} = live(guest, ~p"/users/register")
      assert text(register, "#registration-submit") == "Create account"
      assert text(register, "#to-log-in") == "Log in"

      register
      |> form("#registration-form", %{"user" => %{"email" => "bad address"}})
      |> render_change()

      assert text(register, "#registration-form") =~ "must have the @ sign and no spaces"

      unconfirmed = AccountsFixtures.unconfirmed_user_fixture()
      {token, _hashed} = AccountsFixtures.generate_user_magic_link_token(unconfirmed)
      {:ok, confirm, _html} = live(guest, ~p"/users/log-in/#{token}")
      assert text(confirm, "#confirmation-page .page-title") == "Hello, #{unconfirmed.email}"
      assert text(confirm, "#confirm-and-stay") == "Confirm and remember me"

      {:ok, settings, _html} = live(conn, ~p"/users/settings")
      assert text(settings, "#settings-page .page-title") == "Account settings"
      assert text(settings, "#password-submit") == "Save password"

      for view <-
            [library, empty, mine, feed, groups, page, form, login, register] ++
              [confirm, settings] do
        assert words(render(view)) == 0
      end

      # Флеши контроллеров — по-английски тоже.
      wrong =
        post(guest, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "wrong password!"}
        })

      assert Phoenix.Flash.get(wrong.assigns.flash, :error) == "Invalid email or password"

      missing = get(guest, ~p"/s/nope")
      assert Phoenix.Flash.get(missing.assigns.flash, :error) == "We don't have that short link."
    end
  end

  describe "контроль: сторож не слепой" do
    setup do
      use_edition(:siala)
      Gettext.put_locale(BuildCalculatorWeb.Gettext, Edition.locale())
      :ok
    end

    # Тот же счёт тех же зон на сиальской (русской) редакции. Если бы счётчик
    # не видел кириллицу или зона отрисовывалась пустой, ноль у ванили был бы
    # ложной победой.
    test "на сиальской редакции в каждой зоне кириллицы не меньше, чем у ванили", %{conn: conn} do
      counts = Map.new(@zones, &{&1, words(zone_text(&1, conn))})

      for zone <- @zones do
        assert counts[zone] > 0, "#{zone}: на сиальской редакции ни одного русского слова"

        assert counts[zone] >= @ceilings[zone],
               "#{zone}: у Сиалы #{counts[zone]} слов, у ванили записано #{@ceilings[zone]}"
      end

      # Зоны, где подписи уже идут через gettext, — сравнение, ради которого
      # контроль и заведён: по-русски там сотни слов, по-английски — единицы.
      assert counts.gap_labels > 1000
      assert counts.reason_labels > 200
    end
  end

  # ---- зоны ------------------------------------------------------------------

  # Типичный билд: Fighter 20 → Weapon Master 20, требования мастера оружия
  # набраны воином (как в `illegal_levels_test.exs`), прибавки — в силу.
  # Легален на ванили целиком (`illegal_class_levels/2` и `illegal_feats/2`
  # пусты), так что отрисовка — это обычный билд, а не список претензий.
  defp typical_build(version) do
    Build.new(
      ruleset_version: version,
      race: :human,
      alignment: :lawful_neutral,
      base_abilities: %{str: 16, dex: 14, con: 14, int: 14, wis: 10, cha: 8},
      levels: List.duplicate(:fighter, 20) ++ List.duplicate(:weapon_master, 20),
      ability_increases: Map.new([4, 8, 12, 16, 20, 24, 28, 32, 36, 40], &{&1, :str}),
      skills: %{1 => %{intimidate: 4}},
      feats: %{
        1 => %{:general => :dodge, {:class_bonus, :fighter} => {:weapon_focus, :longsword}},
        2 => %{{:class_bonus, :fighter} => :mobility},
        3 => %{:general => :expertise},
        4 => %{{:class_bonus, :fighter} => :spring_attack},
        6 => %{:general => :whirlwind_attack}
      }
    )
  end

  defp zone_text(:builder_empty, conn) do
    {:ok, view, _html} = live(conn, ~p"/")
    render(view)
  end

  defp zone_text(:builder_typical, conn) do
    {:ok, view, _html} = live(conn, ~p"/?b=#{typical_code()}")
    render(view)
  end

  defp zone_text(:builder_gear, conn) do
    {:ok, view, _html} = live(conn, ~p"/?b=#{typical_code()}")
    view |> element("#gear-toggle") |> render_click()
    view |> element("#gear-panel") |> render()
  end

  defp zone_text(:view, conn) do
    {:ok, view, _html} = live(conn, ~p"/b/#{typical_code()}")
    render(view)
  end

  defp zone_text(:sources, conn) do
    {:ok, view, _html} = live(conn, ~p"/sources")
    render(view)
  end

  defp zone_text(:export, _conn) do
    ruleset = ruleset()
    build = typical_build(ruleset.version)
    Export.text(build, ruleset, Rules.compute(build, ruleset))
  end

  # Каталоги форм — без `@siala_only_forms` (задача 4.18): их не производят
  # ванильные данные (тест «формы шарда ваниль не производит» ниже), и игрок
  # ванили их не увидит. Последним русским словом зоны `gap_labels` было
  # «Вилы» — имя оружия шарда из ДАННЫХ в образце `{:weapon_type_bonus_weapon,
  # "Вилы"}` (`Rules.Vocabulary`), то есть эхо данных Сиалы, а не текст сайта
  # (тот же довод, что у образцов `issue_forms/0`, 4.53). Свой текст у этих форм
  # английский по построению: msgid — через `gettext`, кириллицу в исходниках
  # стережёт `cyrillic_source_test.exs` жёстким нулём.
  defp zone_text(:gap_labels, _conn) do
    ruleset = ruleset()

    Enum.map_join(vanilla_forms(:gap_labels, Rules.gap_forms()), @label_separator, fn gap ->
      Labels.gap_family_name(Gaps.family(gap)) <> ": " <> Labels.gap(gap, ruleset)
    end)
  end

  defp zone_text(:reason_labels, _conn) do
    ruleset = ruleset()

    Enum.map_join(
      vanilla_forms(:reason_labels, Rules.reason_forms()),
      @label_separator,
      &Labels.reason(&1, ruleset)
    )
  end

  defp zone_text(:feat_reason_labels, _conn) do
    ruleset = ruleset()

    Enum.map_join(
      vanilla_forms(:feat_reason_labels, Feats.reason_forms()),
      @label_separator,
      &Feats.reason(&1, ruleset)
    )
  end

  defp zone_text(:import_issues, _conn) do
    ruleset = ruleset()

    Enum.map_join(Import.issue_forms(), @label_separator, fn issue ->
      Import.issue_kind(issue) <> ": " <> Import.issue_text(issue, ruleset)
    end)
  end

  defp zone_text(:import_window, conn) do
    Enum.map_join([@import_full, @import_sparse], @label_separator, &import_window(conn, &1))
  end

  defp ruleset, do: Data.ruleset!(Edition.ruleset())

  defp vanilla_forms(zone, forms), do: forms -- Map.fetch!(@siala_only_forms, zone)
  defp typical_code, do: Encoding.encode(typical_build(Edition.ruleset()))

  # Вставить, разобрать, принять — и собрать то, что окно и флеш сказали
  # по-русски. Окно импорта на Сиале спрятано флагом (задача 3.89): для
  # контроля «сторож не слепой» флаг включается на время зоны и возвращается.
  defp import_window(conn, text) do
    before = Application.fetch_env(:build_calculator, :import_ui)
    Application.put_env(:build_calculator, :import_ui, true)

    try do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#import-button") |> render_click()
      view |> form("#import-form", %{"import" => %{"text" => text}}) |> render_submit()

      report =
        for selector <- ["#import-summary", "#import-compare", "#import-clean"],
            has_element?(view, selector),
            do: view |> element(selector) |> render()

      view |> element("#import-apply") |> render_click()
      Enum.join(report ++ [view |> element("#flash-info") |> render()], @label_separator)
    after
      case before do
        {:ok, value} -> Application.put_env(:build_calculator, :import_ui, value)
        :error -> Application.delete_env(:build_calculator, :import_ui)
      end
    end
  end

  # Билд у потолка (задача 4.4): +20 STR с вещей при потолке прибавки
  # с вещей +12 — у обоих ruleset'ов подсказка `.capped` у STR.
  defp capped_code do
    build = typical_build(Edition.ruleset())
    Encoding.encode(%{build | gear: Gear.new(abilities: %{str: 20})})
  end

  # ---- ни Сиалы, ни шарда -------------------------------------------------------

  defp siala_words(text), do: @siala_word |> Regex.scan(text) |> length()

  defp assert_siala_free!(surface, text) do
    # Тот же `@siala_word`, с контекстом вокруг — чтобы сообщение называло место.
    hits =
      ".{0,60}(?:#{Regex.source(@siala_word)}).{0,60}"
      |> Regex.compile!("iu")
      |> Regex.scan(text)
      |> Enum.map(fn [hit] -> "  … " <> String.replace(hit, ~r/\s+/u, " ") <> " …" end)

    assert hits == [], """
    #{surface}: игрок ванили видит Сиалу или шард (#{length(hits)}):
    #{Enum.join(hits, "\n")}

    Поверхность либо гаснет сама по данным (`Gaps.shard_facts?/1`, ворота
    по признаку в данных), либо говорит от имени редакции или нейтрально:
    английский msgid без имени, русский msgstr — прежний литерал.
    """
  end

  defp siala_named_forms(zone) do
    ruleset = ruleset()

    forms =
      case zone do
        :gap_labels -> Rules.gap_forms()
        :reason_labels -> Rules.reason_forms()
        :feat_reason_labels -> Feats.reason_forms()
      end

    label = fn form ->
      case zone do
        :gap_labels -> Labels.gap(form, ruleset)
        :reason_labels -> Labels.reason(form, ruleset)
        :feat_reason_labels -> Feats.reason(form, ruleset)
      end
    end

    Enum.filter(forms, &Regex.match?(@siala_word, label.(&1)))
  end

  # ---- храповик --------------------------------------------------------------

  defp words(text), do: @word |> Regex.scan(text) |> length()

  defp word_multiset(inventory) do
    Enum.reduce(inventory, %{}, fn {phrase, count}, acc ->
      @word
      |> Regex.scan(phrase)
      |> Enum.reduce(acc, fn [word], acc -> Map.update(acc, word, count, &(&1 + count)) end)
    end)
  end

  defp inventory(text) do
    @phrase
    |> Regex.scan(text)
    |> Enum.map(fn [phrase] -> String.replace(phrase, ~r/\s+/u, " ") end)
    |> Enum.frequencies()
  end

  defp inventory_path(zone), do: Path.join(@inventory_dir, "#{zone}.txt")

  defp read_inventory(zone) do
    case File.read(inventory_path(zone)) do
      {:ok, contents} ->
        for line <- String.split(contents, "\n", trim: true), into: %{} do
          [count, phrase] = String.split(line, "\t", parts: 2)
          {phrase, String.to_integer(count)}
        end

      {:error, :enoent} ->
        nil
    end
  end

  defp write_inventory!(zone, inventory) do
    File.mkdir_p!(@inventory_dir)

    lines =
      for {phrase, count} <- Enum.sort(inventory), do: "#{count}\t#{phrase}\n"

    File.write!(inventory_path(zone), lines)
  end

  defp check_ratchet!(zone, text) do
    current = inventory(text)
    count = words(text)
    ceiling = Map.fetch!(@ceilings, zone)
    recorded = read_inventory(zone)

    # Перечень перемен — всегда против ЗАПИСАННОЙ описи, даже когда она
    # сейчас перепишется: иначе сообщение о числе не назвало бы, что сдвинулось.
    changes = changes(recorded || %{}, current)

    # В режиме записи опись переписывается, и дальше сверяется уже она —
    # не сойтись с отрисовкой может только число в `@ceilings`.
    baseline =
      if System.get_env(@write_env) in ["1", "true"] do
        write_inventory!(zone, current)
        current
      else
        recorded
      end

    cond do
      count > ceiling ->
        flunk("""
        #{zone}: кириллических слов #{count}, храповик #{ceiling} — стало больше на #{count - ceiling}.

        В английскую редакцию русский текст не добавляется: заведи строку через
        gettext (английский msgid, русский msgstr — байт в байт прежний литерал).
        Если рост законен, подними число в @ceilings и перепиши опись:
          #{@command}

        #{changes}
        """)

      count < ceiling ->
        flunk("""
        #{zone}: кириллических слов #{count}, храповик #{ceiling} — меньше на #{ceiling - count}.

        Храповик обязан идти за переводом: опусти число в @ceilings до #{count}
        и перепиши опись:
          #{@command}

        #{changes}
        """)

      is_nil(baseline) ->
        flunk("#{zone}: нет описи #{inventory_path(zone)} — перепиши её:\n  #{@command}")

      word_multiset(baseline) |> Map.values() |> Enum.sum() != ceiling ->
        flunk("""
        #{zone}: опись #{inventory_path(zone)} не сходится с числом #{ceiling} в @ceilings —
        её не переписали вместе с числом:
          #{@command}
        """)

      word_multiset(baseline) != word_multiset(current) ->
        flunk("""
        #{zone}: число прежнее (#{count}), а состав русского текста другой —
        перепиши опись:
          #{@command}

        #{changes}
        """)

      true ->
        :ok
    end
  end

  # Что прибавилось и что ушло по фразам — для сообщения, а не для решения.
  defp changes(baseline, current) do
    phrases = Enum.uniq(Map.keys(baseline) ++ Map.keys(current))

    diffs =
      for phrase <- Enum.sort(phrases),
          before = Map.get(baseline, phrase, 0),
          now = Map.get(current, phrase, 0),
          before != now,
          do: {phrase, before, now}

    added =
      for {phrase, before, now} <- diffs, now > before, do: "  + «#{phrase}» #{before} → #{now}"

    gone =
      for {phrase, before, now} <- diffs, now < before, do: "  − «#{phrase}» #{before} → #{now}"

    Enum.join(
      [
        if(added != [], do: "Прибавилось:\n" <> Enum.join(added, "\n")),
        if(gone != [], do: "Ушло:\n" <> Enum.join(gone, "\n"))
      ]
      |> Enum.reject(&is_nil/1),
      "\n\n"
    )
  end

  # ---- разметка --------------------------------------------------------------

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp texts(view, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(fn node ->
      node |> LazyHTML.text() |> String.replace(~r/\s+/u, " ") |> String.trim()
    end)
  end
end
