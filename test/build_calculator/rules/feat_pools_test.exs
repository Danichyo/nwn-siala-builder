defmodule BuildCalculator.Rules.FeatPoolsTest do
  @moduledoc """
  Какой фит не держит ни один пул слотов — `Rules.FeatSlots.pool_refusals/2`,
  и что лежит в пуле общих фитов — `Rules.FeatSlots.general_feat?/2` (задача 4.55).

  До 4.55 на первый вопрос было ДВА ответа: ядро (`accepts?/3`, тип Fandom вне
  `granted_not_chosen/0`) и выбор фитов на экране (`type == "general"` или
  непустой `bonus_for`). Второй был уже первого на два фита — `Extra turning`
  (`special`) и `Scribe scroll` (`item creation`), — и на экране оба стояли
  «слотом не берётся», хотя ядро и таблицы игры их берут. Здесь — что ответ
  один, на чём он стоит и где проходят его границы.

  Источники у строк таблиц — в комментариях; общие для всего файла:

    * `fandom:Class feat` — «a type of "class" … means the feat is not a general
      feat»; `fandom:Racial feat`; `fandom:General feat` — «the feats available
      for selection at these levels», и `Category:General feats` (кэш
      `priv/wiki_cache/fandom/_index.json`);
    * `feat.2da` (`ALLCLASSESCANUSE`) и `cls_feat_*.2da` (List 0/1 — общим
      слотом, 2 — только бонусным, 3 — выдача) базовой игры 89.8193.37-17
      и хака Сиалы — сверки `mix base2da.diff` / `mix hak2da.diff`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatSlots}

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp both(%{vanilla: vanilla, siala: siala}), do: [{"vanilla", vanilla}, {"siala_41", siala}]

  # Все слоты, какие бывают, без билда: эпический общий (берёт и эпические,
  # и обычные фиты) и эпический бонусный слот каждого класса. `taken_with: nil` —
  # класс уровня ничего не сужает: вопрос про пул, а не про уровень.
  defp every_slot(ruleset) do
    general = %{id: :general, kind: :epic_general, class: nil, taken_with: nil, epic?: true}

    bonus =
      for class <- Map.keys(ruleset.classes) do
        %{
          id: {:class_bonus, class},
          kind: :class_bonus,
          class: class,
          taken_with: class,
          epic?: true
        }
      end

    [general | bonus]
  end

  describe "pool_refusals/2 — один ответ с accepts?/3" do
    # Инвариант, ради которого функция и заведена: «ни один пул не держит» —
    # ровно «ни один слот не берёт», кроме фитов, которым отказано раньше и
    # сильнее (выключен шардом, не выбирается при левелапе). Два прочтения
    # одного правила — то, что разошлось на экране; здесь они сверены по ВСЕМУ
    # справочнику обоих ruleset'ов, а не по выборке.
    test "отказ стоит ровно там, где ни один слот не берёт фит", ctx do
      for {name, ruleset} <- both(ctx), {id, feat} <- ruleset.feats do
        slots = every_slot(ruleset)
        accepted? = Enum.any?(slots, &FeatSlots.accepts?(ruleset, &1, id))
        stronger? = feat.disabled? or not feat.level_up_selectable?

        expected = if accepted? or stronger?, do: [], else: [{:not_slottable, feat.type}]

        assert FeatSlots.pool_refusals(ruleset, id) == expected,
               "#{name}: #{id} (type #{inspect(feat.type)})"
      end
    end

    test "незнакомый фит отказа о пуле не получает — про него скажет `unknown_feat`", ctx do
      for {_name, ruleset} <- both(ctx) do
        assert FeatSlots.pool_refusals(ruleset, :no_such_feat) == []
        refute FeatSlots.general_feat?(ruleset, :no_such_feat)
      end
    end

    # Таблица: фит → ответ на обоих ruleset'ах (`:both`) или на каждом своём.
    @cases [
      # `fandom:Extra turning` (revid 60735): «A custom class must have this feat
      # in their feat list, or that class will not be able to select it as a
      # general feat»; `Category:General feats`; feat.2da:13 ALLCLASSESCANUSE 0,
      # cls_feat_cler.2da и cls_feat_pal.2da — List 0. Замер AG1 (Сиала): клирику
      # 1 доступен.
      {:extra_turning, :both, []},
      # `fandom:Scribe scroll` (revid 70359): «a character must level up in a
      # class with a spellbook or in shifter»; `Category:General feats`;
      # feat.2da:945, List 0 у семи cls_feat_*, у волшебника — List 3 (выдача).
      {:scribe_scroll, :both, []},
      # `fandom:Craft harper item` (revid 43318): `type=class`. Сиала: «Тип
      # навыка: Создание предметов (Классовый)» (revid 20548); хак — feat.2da:440
      # ALLCLASSESCANUSE 0, единственная строка cls_feat_* — List 3 у Арфиста.
      {:craft_harper_item, :both, [{:not_slottable, "class"}]},
      # `fandom:Lay on hands` — классовое умение паладина и Чемпиона Торма.
      {:lay_on_hands, :both, [{:not_slottable, "class"}]},
      # `fandom:Stonecunning` — расовый фит дварфа.
      {:stonecunning, :both, [{:not_slottable, "race"}]},
      # `fandom:Darkvision` — и раса, и уровни классов, `use=automatic`.
      {:darkvision, :both, [{:not_slottable, "classrace"}]},
      # `fandom:Blindsight, 60 foot radius` — «only available for NPCs by default».
      {:blindsight_60_foot_radius, :both, [{:not_slottable, "monster"}]},
      # `fandom:DM tool` — «All DM characters start with this instant feat».
      {:dm_tool, :both, [{:not_slottable, "instant custom"}]},
      # Страница Сиалы «Фокусировки на школы магии» описывает семью, а не фит,
      # и блока «Возможность взятия фита» не несёт: тип не назван — `nil`.
      {:siala_spell_school_focus, %{"siala_41" => [{:not_slottable, nil}]}, nil},
      # «Умение нельзя выбрать при росте персонажа» — сильнее, чем «ни в одном
      # пуле», и одна фраза вместо двух (`{:not_selectable_at_level_up, id}`).
      {:riding_sprint, %{"siala_41" => []}, nil},
      {:smile_of_death, %{"siala_41" => []}, nil},
      # Выключен шардом — `{:feat_disabled, id}` сильнее; тип `class`, пула нет.
      {:weapon_proficiency_monk, %{"siala_41" => [], "vanilla" => [{:not_slottable, "class"}]},
       nil},
      # Обычные общие фиты — для положительного контроля.
      {:power_attack, :both, []},
      {:empower_spell, :both, []}
    ]

    test "таблица с источниками", ctx do
      for {feat, where, answer} <- @cases, {name, ruleset} <- both(ctx) do
        expected =
          case where do
            :both -> {:ok, answer}
            per_ruleset -> Map.fetch(per_ruleset, name)
          end

        with {:ok, want} <- expected do
          assert Map.has_key?(ruleset.feats, feat), "#{name}: нет #{feat} в справочнике"
          assert FeatSlots.pool_refusals(ruleset, feat) == want, "#{name}: #{feat}"
        end
      end
    end
  end

  describe "general_feat?/2 — пул общих фитов" do
    # `Category:General feats` на Fandom — список самой вики, и его
    # НЕэпическая половина совпадает с нашим пулом фит в фит: 87 = 87 у ванили.
    # Это третий независимый источник рядом со страницами классов и таблицами:
    # категорию никто не писал по типу, а `type` в ней — у 76 из 87.
    test "ваниль: неэпический пул общих фитов = Category:General feats", %{vanilla: ruleset} do
      ours =
        for {id, feat} <- ruleset.feats,
            not feat.epic?,
            FeatSlots.general_feat?(ruleset, id),
            into: MapSet.new(),
            do: id

      category = general_feats_category(ruleset)

      assert MapSet.size(category) == 87
      assert ours == category

      # Те, кого прежний фильтр «Общие» прятал (`type == "general"`): ровно
      # одиннадцать, и среди них оба фита этой задачи.
      by_type = for id <- ours, ruleset.feats[id].type == "general", into: MapSet.new(), do: id

      assert MapSet.size(by_type) == 76

      assert MapSet.difference(ours, by_type) ==
               MapSet.new([
                 :brew_potion,
                 :craft_wand,
                 :empower_spell,
                 :extend_spell,
                 :extra_turning,
                 :maximize_spell,
                 :quicken_spell,
                 :scribe_scroll,
                 :silent_spell,
                 :still_spell,
                 :weapon_specialization
               ])
    end

    # У Сиалы сверху — пять сиальских владений оружием: страниц Fandom у них
    # нет, а блок «Возможность взятия фита» на странице Сиалы их общим слотом
    # называет (`FeatSlots.general?/1`, ветка `siala_only?`).
    test "Сиала: та же категория плюс пять владений шарда", %{siala: ruleset} do
      ours =
        for {id, feat} <- ruleset.feats,
            not feat.epic?,
            FeatSlots.general_feat?(ruleset, id),
            into: MapSet.new(),
            do: id

      assert MapSet.difference(ours, general_feats_category(ruleset)) ==
               MapSet.new([
                 :siala_axe_proficiency,
                 :siala_blade_proficiency,
                 :siala_hammer_proficiency,
                 :siala_polearm_proficiency,
                 :siala_ranged_proficiency
               ])

      assert MapSet.subset?(general_feats_category(ruleset), ours)
    end

    test "Rules.general_feat?/2 — тот же ответ", ctx do
      for {_name, ruleset} <- both(ctx), id <- Map.keys(ruleset.feats) do
        assert Rules.general_feat?(id, ruleset) == FeatSlots.general_feat?(ruleset, id)
      end
    end
  end

  describe "validate_feat/3 и illegal_feats/2 называют пул" do
    # Ссылка, в слот которой руками положен классовый фит, больше не читается
    # как законная: тот же контракт «проиграть то, что уже в билде», что
    # у `{:not_selectable_at_level_up, …}` (`gear_feats_test.exs`).
    test "классовый фит в общем слоте — нелегальный пик", ctx do
      for {name, ruleset} <- both(ctx) do
        bad =
          Build.new(levels: List.duplicate(:paladin, 3))
          |> Build.put_feat(3, :general, :lay_on_hands)

        assert {3, :general, :lay_on_hands, {:not_slottable, "class"}} in Rules.illegal_feats(
                 bad,
                 ruleset
               ),
               name

        assert {:error, reasons} =
                 Rules.validate_feat(bad, %{feat: :lay_on_hands, at: 3}, ruleset)

        assert {:not_slottable, "class"} in reasons
        assert Rules.feat_pool_refusals(:lay_on_hands, ruleset) == [{:not_slottable, "class"}]
      end
    end

    # Отказ «с предмета» одной фразой, без второй про пул (граница — выше).
    test "фит с вещи назван одной причиной, а не двумя", %{siala: ruleset} do
      base = Build.new(levels: List.duplicate(:fighter, 3))

      assert Rules.validate_feat(base, %{feat: :riding_sprint, at: 3}, ruleset) ==
               {:error, [{:not_selectable_at_level_up, :riding_sprint}]}
    end
  end

  # Неэпические фиты справочника, чья страница Fandom стоит в `Category:General
  # feats`. Страница — из `source.page` фита (у переименованных она своя),
  # иначе по имени.
  defp general_feats_category(ruleset) do
    index =
      "priv/wiki_cache/fandom/_index.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.new(&{&1["title"], &1["categories"] || []})

    for {id, feat} <- ruleset.feats,
        not feat.epic?,
        page = page(feat),
        "Category:General feats" in Map.get(index, page, []),
        into: MapSet.new(),
        do: id
  end

  defp page(feat) do
    source = Map.get(feat, :source) || %{}
    source[:page] || source["page"] || feat.name
  end
end
