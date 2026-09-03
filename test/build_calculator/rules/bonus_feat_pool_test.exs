defmodule BuildCalculator.Rules.BonusFeatPoolTest do
  @moduledoc """
  Пул бонусных фитов, расширенный шардом: Священник и Друид кладут в свой
  бонусный слот эпические заклинания (задача 3.73, 21.08.2026).

  Источник — страницы классов на вики Сиалы, дословно
  (`priv/rules/siala_41/classes.json`, оба факта `status: verified`):

      На уровнях с бонусными умениями Священник может выбирать умения
      с Эпическими заклинаниями (23, 26, 29, 32, 35 и 38 уровни в классе).

      #На уровнях с бонусными умениями Друид может выбирать умения
      с Эпическими заклинаниями (24, 28, 32, 36 и 40 уровни в классе).

  ⚠️ **Меняются не уровни, а состав пула.** Перечисления в скобках — это
  ванильные `epic_bonus_feat_levels` этих двух классов, слово в слово; ни одного
  нового бонусного уровня факт не заводит. Поэтому и применяется он только там,
  где названные уровни РАВНЫ бонусным уровням класса.

  🔴 **Зачем это вообще нужно игроку.** Эпические заклинания на Сиале берутся
  ТОЛЬКО фитами и слотов обычных кругов не тратят (Dan, 21.08.2026), то есть
  бонусный слот — единственный путь, которым Священник и Друид их получают
  сверх общего слота.

  ## Половина задачи была придержана СОЗНАТЕЛЬНО — и закрыта замером

  ⚠️ Здесь стояло: «Записей формы `bonus_feat_pool` в данных четыре, применены
  две. У Чемпиона Торма источник не называет ни одного уровня, у Рейнджера
  цитата говорит „а также на эпических фитах“ — оба ждут замера, и оба обязаны
  остаться гэпом».

  **Замеры пришли 24.08.2026** (`GAME_CHECKS.md`, U1 и U2), и применены все
  четыре записи из четырёх. Dan видел все пять сиальских владений оружием
  в бонусном слоте Чемпиона Торма на ЧТ 2 и на ЧТ 14 (обычная и эпическая
  пачки) и в бонусном слоте Рейнджера на его 1-м и 5-м уровнях.

  🔴 **И замер вскрыл дефект крупнее собственного вопроса: гэп был ЛОЖНЫМ.**
  Пул обоих классов был верен всё это время — правило приезжает со страниц
  самих фитов («Возможность взятия фита» → `bonus_for`), — а запись на стороне
  класса продолжала печатать `{:not_modelled, {:class_change, …,
  "bonus_feat_pool"}}`. То есть мы применяли правило и одновременно говорили
  игроку, что не применяем; ложная неопределённость запрещена так же, как
  ложная уверенность.

  Поэтому **главный тест задачи 3.85 — не «пул расширился», а «пул НЕ сдвинулся
  ни на один id»**: правка снимает гэп, а не добавляет фиты (`describe
  "две записи об одном правиле"`).

  ## Уровни называются двумя способами

  `class_levels` — числа, которые называет источник (`null` у Чемпиона Торма:
  он не называет ни одного). `also_on` — имя набора уровней самого класса из
  закрытого словаря: `epic_bonus_feat_levels` у Рейнджера (дословный хвост его
  цитаты) и `all_bonus_feat_levels` у Чемпиона Торма (прочтение фразы
  «На дополнительных фитах», подтверждённое замером обеих пачек). Применяется
  запись, только если объединение равно всем бонусным уровням класса.

  ## Где живёт расширение

  В `bonus_for` самих фитов — там же, где на тот же вопрос отвечает ваниль
  (у шести эпических заклинаний это `[pale_master, sorcerer, wizard]`).
  Второй карты «что примет бонусный слот» не заведено: `Rules.FeatSlots`
  и `BuildCalculatorWeb.Builder.Feats` читают `bonus_for` и только его, и две
  карты рано или поздно разошлись бы.

  ⚠️ **Билды здесь собираются левелапами через `validate_level_up/3`**, а не
  списком классов в `Build.new/1`: клирик 23 и друид 24 — эпические уровни,
  и лестницу надо пройти честно (ловушка CLAUDE.md §3).
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatSlots}

  # Шесть записей справочника с `type: "epic spell"`. Перечислены здесь, а не
  # выведены фильтром по тому же полю: тест, который спрашивает данные тем же
  # способом, каким их читает код, сойдётся и при неверном ответе.
  @epic_spells ~w(epic_spell_dragon_knight epic_spell_epic_mage_armor
                  epic_spell_epic_warding epic_spell_greater_ruin
                  epic_spell_hellball epic_spell_mummy_dust)a

  # Четыре из шести, которые Священник и Друид могут взять вообще: у двух
  # оставшихся собственная страница называет квалифицирующие классы, и обоих
  # там нет — «being an epic sorcerer or wizard, or having at least 15 pale
  # master levels» (`fandom:Epic spell: epic mage armor`, revid 64605;
  # `fandom:Epic spell: epic warding`, revid 70464).
  @arcane_only ~w(epic_spell_epic_mage_armor epic_spell_epic_warding)a
  @divine_too @epic_spells -- @arcane_only

  # Пять фитов владения кастомной «Системы оружия» — вторая категория словаря
  # `_bonus_feat_pools` (задача 3.85). Перечислены здесь по той же причине,
  # что и шесть эпических заклинаний выше: спросить данные тем же способом,
  # каким их читает код (реестр `weapons.json`), значит сойтись и при неверном
  # ответе.
  @weapon_proficiencies ~w(siala_axe_proficiency siala_blade_proficiency
                           siala_hammer_proficiency siala_polearm_proficiency
                           siala_ranged_proficiency)a

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  # Чистая лестница одного класса, пройденная левелап за левелапом. Ранги
  # Spellcraft — по одному за уровень: классовый потолок `уровень + 3`, значит
  # покупка законна на каждом, а к 23-му их 22 — хватает на `mummy dust` (15)
  # и `dragon knight` (22) и не хватает на `greater ruin` (25) и `hellball` (32).
  # Ровно этот разрыв и нужен: он показывает, что отказ у оставшихся двух —
  # честное «нужно N рангов», а не отсутствие в пуле.
  defp pure(ruleset, class, levels, opts \\ []) do
    base =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: Keyword.get(opts, :alignment, :true_neutral),
        base_abilities: %{str: 10, dex: 10, con: 12, int: 14, wis: 16, cha: 10},
        skills: Keyword.get(opts, :skills, %{}),
        feats: Keyword.get(opts, :feats, %{})
      )

    Enum.reduce(1..levels, base, fn _i, build ->
      assert Rules.validate_level_up(build, %{class: class}, ruleset) == :ok,
             "#{class} на уровне #{length(build.levels) + 1} — билд собран нелегально"

      Build.add_level(build, class)
    end)
  end

  defp spellcraft(upto), do: Map.new(1..upto, fn level -> {level, %{spellcraft: 1}} end)

  defp slot(ruleset, build, level, id) do
    Enum.find(FeatSlots.at(build, ruleset, level), &(&1.id == id))
  end

  defp epic_spells_in(ruleset, slot) do
    ruleset |> FeatSlots.candidates(slot) |> Enum.filter(&(&1 in @epic_spells)) |> Enum.sort()
  end

  describe "бонусный слот Священника и Друида принимает эпические заклинания" do
    # source: siala_41/classes.json → cleric → bonus_feat_pool (verified)
    test "клирик 23: четыре фита в бонусном слоте", %{siala: siala} do
      build = pure(siala, :cleric, 23)

      assert epic_spells_in(siala, slot(siala, build, 23, {:class_bonus, :cleric})) ==
               @divine_too
    end

    # Отрицательный контроль по УРОВНЮ: 22 не входит в список источника, и
    # бонусного слота там нет вовсе — то есть правка не завела нового уровня.
    test "клирик 22: бонусного слота нет вовсе", %{siala: siala} do
      build = pure(siala, :cleric, 23)

      assert slot(siala, build, 22, {:class_bonus, :cleric}) == nil
      assert FeatSlots.at(build, siala, 22) == []
    end

    # source: siala_41/classes.json → druid → bonus_feat_pool (verified)
    test "друид 24: те же четыре; 23 и 25 — слота нет", %{siala: siala} do
      build = pure(siala, :druid, 25)

      assert epic_spells_in(siala, slot(siala, build, 24, {:class_bonus, :druid})) == @divine_too
      assert slot(siala, build, 23, {:class_bonus, :druid}) == nil
      assert slot(siala, build, 25, {:class_bonus, :druid}) == nil
    end

    # ⚠️ Не «шесть», и это утверждение источника, а не наша осторожность:
    # `Epic mage armor` и `Epic warding` — аркановые, и их собственные страницы
    # называют квалифицирующие классы поимённо. Сиала про них не говорит ничего,
    # молчание её вики — молчание, значит правило остаётся ванильным (§3).
    test "два аркановых в пул НЕ попали — ни у Священника, ни у Друида", %{siala: siala} do
      for id <- @arcane_only, class <- [:cleric, :druid] do
        refute MapSet.member?(siala.feats[id].bonus_for, class),
               "#{id} не должен быть в бонусном пуле #{class}"
      end

      for id <- @divine_too, class <- [:cleric, :druid] do
        assert MapSet.member?(siala.feats[id].bonus_for, class)
      end
    end

    # …и они не исчезают молча: отказ назван, и он называет квалифицирующие
    # классы — то есть игрок узнаёт, почему фита нет, а не гадает.
    test "у аркановых отказ ЕСТЬ и он поимённый", %{siala: siala} do
      build = pure(siala, :cleric, 23, skills: spellcraft(22))

      assert {:error, reasons} = Rules.validate_feat(build, :epic_spell_epic_mage_armor, siala)
      assert {:requires_leveling_as, [:pale_master, :sorcerer, :wizard]} in reasons
    end
  end

  describe "отказ у четырёх — по рангам, а не по отсутствию в пуле" do
    # Разрыв нарочный: 22 ранга Spellcraft к 23-му уровню.
    test "клирик 23 с 22 рангами: два берутся, два отбиты по рангам", %{siala: siala} do
      build = pure(siala, :cleric, 23, skills: spellcraft(22))

      assert Rules.validate_feat(build, :epic_spell_mummy_dust, siala) == :ok
      assert Rules.validate_feat(build, :epic_spell_dragon_knight, siala) == :ok

      assert Rules.validate_feat(build, :epic_spell_greater_ruin, siala) ==
               {:error, [{:requires_skill_ranks, :spellcraft, 25}]}

      assert Rules.validate_feat(build, :epic_spell_hellball, siala) ==
               {:error, [{:requires_skill_ranks, :spellcraft, 32}]}
    end

    # Полный круг: фит, положенный в бонусный слот, билд держит — то есть
    # правка доезжает не только до списка кандидатов, но и до проверки уже
    # сделанного выбора.
    test "выбранный фит остаётся законным в билде", %{siala: siala} do
      build =
        pure(siala, :cleric, 23,
          skills: spellcraft(22),
          feats: %{23 => %{{:class_bonus, :cleric} => :epic_spell_mummy_dust}}
        )

      assert Rules.illegal_feats(build, siala) == []
    end
  end

  describe "чего правка не задела" do
    # 🔴 Главный отрицательный контроль задачи: правка про КЛАССОВЫЙ БОНУСНЫЙ
    # пул, а общий слот берёт из общего списка и `bonus_for` не читает вовсе.
    # Число 130 замерено на клирике 21 ДО правки и совпало ПОСЛЕ.
    #
    # ⚠️ 130 → 129 (25.08.2026, задача 3.103) — и это не подгонка под правку,
    # а ДРУГАЯ правка того же дня: `dragon_shape` получил рабочий
    # `only_on_class_levels: [druid, shifter]`, то есть выпал из общего списка
    # клирика, как выпадают 39 остальных фитов с этим ключом. Утверждение теста
    # («расширение бонусного пула общий слот не двигает») этим не задето вовсе —
    # его держит структурная половина соседним тестом ниже, и она не менялась.
    #
    # ⚠️ 129 → 130 (26.08.2026, задача 3.112) — третья такая же чужая правка:
    # `weapon_proficiency_simple` перестал быть выключенным, и общий список
    # им пополнился. ⚠️ Кандидатом он стал ЧЕСТНО: `FeatSlots.candidates/2`
    # отвечает про слот и пул, билда у неё нет, а «фит уже выдан» — вопрос
    # билда. В самом конструкторе он игроку не показывается вовсе, ровно как
    # `toughness` у воина, — это проверяет `siala_feat_layer_test.exs`.
    test "общий эпический слот на уровне клирика — тот же", %{siala: siala} do
      build = pure(siala, :cleric, 23)
      general = slot(siala, build, 21, :general)

      assert general.kind == :epic_general
      assert length(FeatSlots.candidates(siala, general)) == 130
      refute :dragon_shape in FeatSlots.candidates(siala, general)

      # Четыре эпических заклинания стояли в общем слоте и до правки: ваниль
      # разрешает их клирику, просто не бонусным слотом.
      assert epic_spells_in(siala, general) == @divine_too
    end

    # …и то же самое механизмом, а не числом: расширение `bonus_for` не имеет
    # права двигать общий список ВООБЩЕ. Проверяется синтетикой — в `bonus_for`
    # каждого фита дописан клирик, и общий слот обязан не заметить.
    test "общий слот не читает bonus_for — структурно", %{siala: siala} do
      build = pure(siala, :cleric, 23)
      general = slot(siala, build, 21, :general)

      widened =
        update_in(siala.feats, fn feats ->
          Map.new(feats, fn {id, feat} ->
            {id, %{feat | bonus_for: MapSet.put(feat.bonus_for, :cleric)}}
          end)
        end)

      assert FeatSlots.candidates(widened, general) == FeatSlots.candidates(siala, general)
    end

    # Чужой класс: у воина бонусных слотов больше всех, и ни одного эпического
    # заклинания в них не появилось.
    test "воин: бонусный слот прежний", %{siala: siala} do
      build = pure(siala, :fighter, 24)

      assert epic_spells_in(siala, slot(siala, build, 22, {:class_bonus, :fighter})) == []
      assert epic_spells_in(siala, slot(siala, build, 24, {:class_bonus, :fighter})) == []
    end

    # 🔴 Придержанная половина задачи 3.73, закрытая замерами 24.08.2026.
    # ⚠️ Здесь стояло «Чемпион Торма и Рейнджер не тронуты, и их гэпы
    # на месте»: `bonus_feat_pool_adds == %{}` и гэп в списке. Обе записи
    # применены; проверяется теперь ровно то, что от той половины осталось
    # верным, — **эпические заклинания в их пул не попали**. Категории две,
    # и перепутать их значило бы выдать Рейнджеру `Hellball`.
    test "у Чемпиона Торма и Рейнджера СВОЯ категория, а не эпические заклинания",
         %{siala: siala} do
      for class <- [:champion_of_torm, :ranger] do
        assert Map.keys(siala.classes[class].bonus_feat_pool_adds) == [
                 "weapon_proficiency_feats"
               ]

        refute {:not_modelled, {:class_change, class, "bonus_feat_pool"}} in siala.gaps

        for id <- @epic_spells do
          refute MapSet.member?(siala.feats[id].bonus_for, class)
        end
      end

      # ...и зеркало: у Священника с Друидом нет сиальских владений в пуле.
      for class <- [:cleric, :druid], id <- @weapon_proficiencies do
        refute MapSet.member?(siala.feats[id].bonus_for, class)
      end
    end

    # 🔴 Инвариант, который эта правка могла сломать одним лишним фитом,
    # и его нынешний сторож её бы НЕ поймал: `parsed_snapshot_test.exs`
    # («ни один класс не запрещает фит из СВОЕГО бонусного пула») читает
    # сырой JSON, а расширение живёт слоем выше — в загруженном ruleset'е.
    # Поэтому тот же вопрос задаётся ещё раз и уже загруженным словарям.
    #
    # Ставка ровно та: положи мы в пул все ШЕСТЬ эпических заклинаний, здесь
    # появились бы четыре пары (клирик и друид × два аркановых), потому что
    # `only_on_class_levels` запрещает их этим классам с другой стороны.
    # `Rules.FeatSlots` на бонусный слот запрет не распространяет сознательно —
    # значит две карты сказали бы противоположное про один и тот же фит,
    # и решать пришлось бы человеку (moduledoc `Rules.FeatSlots`).
    test "загруженный ruleset: класс не запрещает фит из своего бонусного пула", %{
      siala: siala,
      vanilla: vanilla
    } do
      overlap = fn ruleset ->
        for {class_id, class} <- ruleset.classes,
            feat <- MapSet.to_list(class.unavailable_feats),
            MapSet.member?(ruleset.feats[feat].bonus_for, class_id),
            do: {class_id, feat}
      end

      assert overlap.(siala) == []
      assert overlap.(vanilla) == []
    end

    test "у ванили пулы прежние — слоя Сиалы там нет вовсе", %{vanilla: vanilla} do
      for id <- @epic_spells do
        assert Enum.sort(vanilla.feats[id].bonus_for) == [:pale_master, :sorcerer, :wizard]
      end

      for {_id, class} <- vanilla.classes do
        assert class.bonus_feat_pool_adds == %{}
      end
    end

    # ⚠️ Здесь стояло «гэпов формы bonus_feat_pool осталось два из четырёх»
    # с перечислением `[:champion_of_torm, :ranger]`. С 24.08.2026 применены
    # все четыре, гэпов этой формы не осталось ни одного.
    #
    # ⚠️ Записей стало ПЯТЬ 02.09.2026: Паладин, замер Dan (см. describe ниже).
    #
    # Ноль утверждается ДВУМЯ способами сразу, потому что пустой список молчит
    # про всё одинаково: сначала — что записей формы в данных по-прежнему
    # пять (не «исчезли из файла»), потом — что ни одна не висит гэпом.
    test "все пять записей bonus_feat_pool применены, гэпов формы ноль", %{siala: siala} do
      applied =
        for {id, class} <- siala.classes,
            class.bonus_feat_pool_adds != %{},
            do: id

      assert Enum.sort(applied) == [:champion_of_torm, :cleric, :druid, :paladin, :ranger]

      pools =
        for {:not_modelled, {:class_change, class, "bonus_feat_pool"}} <- siala.gaps,
            do: class

      assert pools == []
    end
  end

  # ------------------------------- две записи об одном правиле (задача 3.85) --

  # 🔴 Главный инвариант правки: она снимает ЛОЖНЫЙ гэп и не добавляет
  # в бонусный слот ни одного фита. Пять сиальских владений лежали в пуле
  # обоих классов и до неё — их кладут туда сами страницы фитов
  # («Возможность взятия фита» → `bonus_for`), — а запись на стороне класса
  # печатала «не смоделировано». Теперь обе записи об одном правиле сходятся
  # на одной карте, и вторая служит сверкой.
  describe "две записи об одном правиле" do
    # Билд Чемпиона Торма собирается ПО ОДНОМУ ЛЕВЕЛАПУ: одиннадцатый уровень
    # престиж-класса требует 20-го уровня персонажа, поэтому лестница
    # «воин 7 → ЧТ 10 → воин 3 → ЧТ 4» — единственный способ добраться до ЧТ 14,
    # и `Build.new(levels: …)` тут не годится (ловушка CLAUDE.md §3).
    #
    # Точки — ровно те, что мерил Dan (U1): ЧТ 2 (уровень персонажа 9,
    # первый обычный бонусный) и ЧТ 14 (уровень 24, первый эпический).
    test "Чемпион Торма: все пять владений в бонусном слоте на ОБЕИХ пачках",
         %{siala: siala} do
      build = champion(siala)

      for level <- [9, 24] do
        slot = slot(siala, build, level, {:class_bonus, :champion_of_torm})

        refute is_nil(slot), "на уровне #{level} нет бонусного слота вовсе"

        assert Enum.sort(
                 Enum.filter(FeatSlots.candidates(siala, slot), &(&1 in @weapon_proficiencies))
               ) ==
                 Enum.sort(@weapon_proficiencies)
      end

      # ...и «обе пачки» — не два раза одно и то же: пачки различимы по тому,
      # что эпический слот берёт эпические фиты, а доэпический нет. Без этой
      # строки оба прохода выше могли бы проверять одну и ту же половину.
      pre_epic = slot(siala, build, 9, {:class_bonus, :champion_of_torm})
      epic = slot(siala, build, 24, {:class_bonus, :champion_of_torm})

      refute FeatSlots.accepts?(siala, pre_epic, :epic_prowess)
      assert FeatSlots.accepts?(siala, epic, :epic_prowess)
    end

    # U2, обе измеренные точки плюс первый эпический бонусный уровень (23),
    # который Dan сознательно не мерил: он назван источником прямо
    # («а также на эпических фитах»), а сам механизм эпического бонусного слота
    # измерен в тот же день на Чемпионе Торма.
    test "Рейнджер: те же пять на 1, 5 и 23", %{siala: siala} do
      build = pure(siala, :ranger, 25)

      for level <- [1, 5, 23] do
        slot = slot(siala, build, level, {:class_bonus, :ranger})

        refute is_nil(slot), "на уровне #{level} нет бонусного слота вовсе"

        for id <- @weapon_proficiencies do
          assert FeatSlots.accepts?(siala, slot, id),
                 "#{id} не принят бонусным слотом рейнджера на уровне #{level}"
        end
      end
    end

    # 🔴 И то, ради чего весь describe: список кандидатов бонусного слота
    # ТОТ ЖЕ, что у ruleset'а, в котором записи класса нет вовсе. Сдвинься он
    # хоть на один id — правка добавила бы фиты, а не сняла гэп.
    #
    # ⚠️ Сравнение с настоящим слепком «до», а не с числом: число легко
    # подогнать, а список — нет.
    #
    # «До» получается копией данных, у которой обе записи НЕ ПРИМЕНЯЮТСЯ —
    # `adds` указывает на категорию вне словаря. Именно это и было состоянием
    # до 24.08.2026: факт в данных есть, читается, применён быть не может
    # и висит гэпом. Вырезать факт совсем было бы неверно — тогда исчез бы
    # и гэп, то есть исчезла бы половина того, что сравнивается.
    test "пул не сдвинулся ни на один id — сверка с данными, где запись не применена",
         %{siala: siala} do
      root = copy_rules()
      for id <- ["champion_of_torm", "ranger"], do: unapply_pool_fact(root, id)
      before = Loader.load!(root)["siala_41"]

      # Контроль самой копии: без факта класса записи не применены...
      for class <- [:champion_of_torm, :ranger] do
        assert before.classes[class].bonus_feat_pool_adds == %{}
        assert {:not_modelled, {:class_change, class, "bonus_feat_pool"}} in before.gaps
      end

      # ...а пул при этом ТОТ ЖЕ, потому что его наполняют страницы фитов.
      for id <- @weapon_proficiencies do
        assert before.feats[id].bonus_for == siala.feats[id].bonus_for
      end

      champion = champion(siala)
      ranger = pure(siala, :ranger, 25)

      for {build, class, levels} <- [
            {champion, :champion_of_torm, [9, 24]},
            {ranger, :ranger, [1, 5, 23]}
          ],
          level <- levels do
        slot = slot(siala, build, level, {:class_bonus, class})

        assert FeatSlots.candidates(before, slot) == FeatSlots.candidates(siala, slot),
               "список кандидатов #{class} на уровне #{level} сдвинулся"
      end
    end
  end

  # ------------------------------ владения оружием у Паладина (задача 3.168) --

  # 🔴 ЗЕРКАЛО `describe "две записи об одном правиле"` выше, и в этом вся его
  # ценность. Там правка снимала ЛОЖНЫЙ гэп и не двигала пул НИ НА ОДИН id:
  # правило уже приезжало со страниц самих фитов. Здесь наоборот — страницы
  # фитов паладина НЕ НАЗЫВАЮТ («Возможность взятия фита» перечисляет Воина,
  # Рейнджера, Мастера оружия и Чемпиона Торма), поэтому пул обязан сдвинуться
  # ровно на ПЯТЬ id. Сдвинься он на ноль — факт не применён; сдвинься больше —
  # категория выбрала лишнее.
  #
  # Источник — замер Dan 02.09.2026 на тестовом сервере: в эпическом бонусном
  # слоте паладина видны все пять сиальских владений. Вики молчит с ОБЕИХ
  # сторон (страница класса про «Систему оружия» не говорит ничего), то есть
  # это не спор источников, а молчание диффа, перебитое верхней строкой ранга
  # (CLAUDE.md §3; прецедент — фит `Artist`, кейс F8).
  describe "Паладин: владения оружием в эпическом бонусном слоте" do
    # source: siala_41/classes.json → paladin → bonus_feat_pool (verified,
    # source_confirmation kind: user, Dan 02.09.2026)
    test "все пять владений на обоих эпических бонусных уровнях", %{siala: siala} do
      build = paladin(siala)

      for level <- [23, 26] do
        slot = slot(siala, build, level, {:class_bonus, :paladin})

        refute is_nil(slot), "на уровне #{level} нет бонусного слота вовсе"

        assert Enum.sort(
                 Enum.filter(FeatSlots.candidates(siala, slot), &(&1 in @weapon_proficiencies))
               ) == Enum.sort(@weapon_proficiencies)
      end
    end

    # 🔴 Отрицательный контроль ПО УРОВНЮ, и у паладина он сильнее, чем у
    # Чемпиона Торма с Рейнджером: доэпических бонусных слотов у класса нет
    # ВОВСЕ (`bonus_feat_levels: []`), то есть запись не имела права завести
    # ни одного нового уровня. Ровно поэтому `also_on` у неё названо
    # `epic_bonus_feat_levels`, а не `all_bonus_feat_levels`.
    test "доэпических бонусных слотов у паладина нет — правка их не завела", %{siala: siala} do
      build = paladin(siala)

      assert MapSet.to_list(siala.classes[:paladin].bonus_feat_levels) == []

      for level <- 1..22 do
        assert slot(siala, build, level, {:class_bonus, :paladin}) == nil,
               "на уровне #{level} появился бонусный слот паладина, которого нет в игре"
      end
    end

    # Полный круг: положенное в слот владение билд держит — то есть правка
    # доезжает не только до списка кандидатов, но и до проверки уже сделанного
    # выбора (`Rules.illegal_feats/2` переспрашивает полную проверку пика).
    test "выбранное владение остаётся законным в билде", %{siala: siala} do
      build =
        paladin(siala,
          feats: %{23 => %{{:class_bonus, :paladin} => :siala_blade_proficiency}}
        )

      assert Rules.illegal_feats(build, siala) == []
    end

    # 🔴 Главный инвариант правки, зеркальный тесту 3.85: пул сдвинулся РОВНО
    # на пять id, а общий слот на том же уровне — ни на один.
    #
    # ⚠️ Сравнение со слепком «до», а не с числом: число легко подогнать под
    # ответ, список — нет. «До» получается копией данных, где запись читается,
    # но применена быть не может (категория вне словаря), — то есть ровно тем
    # состоянием, в котором класс был бы, промолчи замер.
    test "пул сдвинулся ровно на пять id, общий слот — ни на один", %{siala: siala} do
      root = copy_rules()
      unapply_pool_fact(root, "paladin")
      before = Loader.load!(root)["siala_41"]

      # Контроль самой копии: без применённого факта запись висит гэпом —
      # то есть сравнивается «наш ответ до» с «нашим ответом после», а не
      # с данными, из которых факт вырезан вовсе.
      assert before.classes[:paladin].bonus_feat_pool_adds == %{}
      assert {:not_modelled, {:class_change, :paladin, "bonus_feat_pool"}} in before.gaps

      build = paladin(siala)

      for level <- [23, 26] do
        slot = slot(siala, build, level, {:class_bonus, :paladin})

        assert Enum.sort(FeatSlots.candidates(siala, slot) -- FeatSlots.candidates(before, slot)) ==
                 Enum.sort(@weapon_proficiencies)

        assert FeatSlots.candidates(before, slot) -- FeatSlots.candidates(siala, slot) == []
      end

      # ...а общий слот на уровне паладина правка не трогает вовсе: владения
      # стояли в нём и до замера («Данный фит можно взять любому персонажу
      # на любом уровне, на котором дается фит»).
      general = slot(siala, build, 24, :general)

      assert general.kind == :epic_general
      assert FeatSlots.candidates(before, general) == FeatSlots.candidates(siala, general)

      for id <- @weapon_proficiencies do
        assert FeatSlots.accepts?(before, general, id)
      end
    end

    # 🔴 ГРАНИЦА ЗАМЕРА, записанная тестом, а не только заметкой в данных.
    # Dan смотрел ОДИН класс. Если владения найдутся и у остальных, правило
    # не «паладин тоже», а «эпический бонусный слот берёт владения» — и форма
    # записи будет совсем другой. До ответа (кейс AK2 в GAME_CHECKS.md) ни один
    # из шестнадцати факта не получает, и этот тест упадёт, если кто-нибудь
    # раздаст его «для единообразия».
    #
    # Список перечислен, а не выведен фильтром по тому же полю, которое читает
    # код: тест, спрашивающий данные их же способом, сойдётся и при неверном
    # ответе.
    test "остальные шестнадцать классов с эпическими бонусами владений не получили",
         %{siala: siala} do
      unmeasured = ~w(arcane_archer assassin barbarian bard blackguard cleric druid
                      dwarven_defender monk pale_master red_dragon_disciple rogue
                      shadowdancer shifter sorcerer wizard)a

      for class <- unmeasured do
        assert MapSet.size(siala.classes[class].epic_bonus_feat_levels) > 0,
               "#{class} без эпических бонусных слотов — список устарел, а не проверяет границу"

        for id <- @weapon_proficiencies do
          refute MapSet.member?(siala.feats[id].bonus_for, class),
                 "#{id} попал в бонусный пул #{class}, которого никто не мерил"
        end
      end

      # Положительный контроль тем же способом: пятеро, у кого владения есть,
      # — четверо со страниц самих фитов плюс паладин с замера.
      for id <- @weapon_proficiencies do
        assert Enum.sort(MapSet.to_list(siala.feats[id].bonus_for)) ==
                 [:champion_of_torm, :fighter, :paladin, :ranger, :weapon_master]
      end
    end
  end

  # ------------------------------------------------------------- сторож данных --

  # Словарь `_bonus_feat_pools` закрыт, и у него две разные стороны, которые
  # нельзя путать: **форма** селектора — расхождение данных с кодом, оно роняет
  # сборку; **имя** категории, которого в словаре нет, — это шард сказал то,
  # чего мы не формализовали, и оно обязано доехать до игрока гэпом, а не
  # упасть (CLAUDE.md §3). Ровно на этой границе держатся две придержанные
  # записи, поэтому она под тестом.
  describe "словарь бонусных пулов" do
    test "чистая копия применяет все четыре — иначе проверки ниже зеленели бы впустую" do
      siala = Loader.load!(copy_rules())["siala_41"]

      assert siala.classes[:cleric].bonus_feat_pool_adds == %{
               "epic_spell_feats" => %{feat_type: "epic spell"}
             }

      assert MapSet.member?(siala.feats[:epic_spell_hellball].bonus_for, :cleric)

      # Вторая категория — своя форма селектора, и она обязана разрешиться
      # в те же пять фитов, что называет `weapons.json`.
      assert siala.classes[:ranger].bonus_feat_pool_adds == %{
               "weapon_proficiency_feats" => %{
                 feat_ids: MapSet.new(@weapon_proficiencies)
               }
             }
    end

    # ⚠️ Реестр пяти фитов живёт в `vanilla/weapons.json`, а не в словаре
    # пулов, — вторая копия разошлась бы с первой. Опустеет реестр — сборка
    # обязана упасть, а не расширить пул молча ничем.
    test "пустой реестр фитов владения роняет сборку" do
      root = copy_rules()
      path = Path.join(root, "vanilla/weapons.json")
      data = path |> File.read!() |> Jason.decode!()

      groups =
        Map.new(data["_siala_proficiency"]["groups"], fn {name, spec} ->
          {name, Map.put(spec, "siala_feat", nil)}
        end)

      File.write!(
        path,
        Jason.encode!(put_in(data["_siala_proficiency"]["groups"], groups))
      )

      assert_raise RuntimeError, ~r/ни одного фита владения/, fn -> Loader.load!(root) end
    end

    test "селектор неизвестной формы роняет сборку" do
      root = copy_rules()
      edit_pools(root, fn _ -> %{"epic_spell_feats" => %{"feat_kind" => "epic spell"}} end)

      assert_raise RuntimeError, ~r/категория бонусного пула/, fn -> Loader.load!(root) end
    end

    test "селектор, под который не подходит ни один фит, роняет сборку" do
      root = copy_rules()
      edit_pools(root, fn _ -> %{"epic_spell_feats" => %{"feat_type" => "такого типа нет"}} end)

      assert_raise RuntimeError, ~r/не подходит ни один фит/, fn -> Loader.load!(root) end
    end

    test "категория вне словаря не падает, а остаётся гэпом" do
      root = copy_rules()
      edit_pool_fact(root, "cleric", &put_in(&1["value"]["adds"], "чего-то там"))

      siala = Loader.load!(root)["siala_41"]

      assert siala.classes[:cleric].bonus_feat_pool_adds == %{}
      assert {:not_modelled, {:class_change, :cleric, "bonus_feat_pool"}} in siala.gaps
      refute MapSet.member?(siala.feats[:epic_spell_hellball].bonus_for, :cleric)

      # Положительный контроль: Друида правка не касалась, он применён.
      assert MapSet.member?(siala.feats[:epic_spell_hellball].bonus_for, :druid)
    end

    # ⚠️ Здесь стояло «лишний ключ значения оставляет факт гэпом» и в качестве
    # лишнего ключа подставлялся `also_on` — «ровно форма записи Рейнджера».
    # С 24.08.2026 `also_on` ключ ЗАКОННЫЙ, поэтому проверка разделилась
    # надвое: неизвестный ключ и неизвестное ЗНАЧЕНИЕ известного ключа.
    # Оба оставляют факт гэпом, и оба — про значение факта, а не про форму
    # словаря, поэтому сборку не роняют (границу см. в комментарии describe).
    test "неизвестный ключ значения оставляет факт гэпом" do
      root = copy_rules()

      edit_pool_fact(
        root,
        "cleric",
        &Map.put(&1, "value", Map.put(&1["value"], "на глазок", "…"))
      )

      siala = Loader.load!(root)["siala_41"]

      assert siala.classes[:cleric].bonus_feat_pool_adds == %{}
      assert {:not_modelled, {:class_change, :cleric, "bonus_feat_pool"}} in siala.gaps
    end

    test "неизвестное имя набора уровней в also_on оставляет факт гэпом" do
      root = copy_rules()

      edit_pool_fact(
        root,
        "cleric",
        &Map.put(&1, "value", Map.put(&1["value"], "also_on", "эпические фиты"))
      )

      siala = Loader.load!(root)["siala_41"]

      assert siala.classes[:cleric].bonus_feat_pool_adds == %{}
      assert {:not_modelled, {:class_change, :cleric, "bonus_feat_pool"}} in siala.gaps
    end

    # 🔴 Половина правила по-прежнему хуже отсутствующего, и правка 3.85 этого
    # не отменила: если у Рейнджера убрать `also_on`, названными останутся
    # только доэпические уровни — то есть запись скажет про пул, зависящий
    # от уровня, а такой формы у модели нет.
    test "запись, называющая ЧАСТЬ бонусных уровней, остаётся гэпом" do
      root = copy_rules()
      edit_pool_fact(root, "ranger", &Map.put(&1, "value", Map.delete(&1["value"], "also_on")))

      siala = Loader.load!(root)["siala_41"]

      assert siala.classes[:ranger].bonus_feat_pool_adds == %{}
      assert {:not_modelled, {:class_change, :ranger, "bonus_feat_pool"}} in siala.gaps

      # Положительный контроль: Чемпиона Торма правка не касалась — применён.
      assert siala.classes[:champion_of_torm].bonus_feat_pool_adds != %{}
    end

    # ...и обратная крайность: запись, не называющая уровней ВООБЩЕ. Пустое
    # утверждение сравнялось бы с пустым множеством у класса без бонусных
    # уровней и «применилось» бы, не сказав ничего.
    test "запись без чисел и без имени набора остаётся гэпом" do
      root = copy_rules()

      edit_pool_fact(
        root,
        "champion_of_torm",
        &Map.put(&1, "value", Map.delete(&1["value"], "also_on"))
      )

      siala = Loader.load!(root)["siala_41"]

      assert siala.classes[:champion_of_torm].bonus_feat_pool_adds == %{}

      assert {:not_modelled, {:class_change, :champion_of_torm, "bonus_feat_pool"}} in siala.gaps
    end

    # И вторая половина того же: перечисление в скобках обязано быть бонусными
    # уровнями класса. Не равны — значит источник говорит про пул, зависящий
    # от уровня, а такой формы у нас нет.
    test "уровни, не равные бонусным уровням класса, оставляют факт гэпом" do
      root = copy_rules()
      edit_pool_fact(root, "cleric", &put_in(&1["value"]["class_levels"], [23, 26]))

      siala = Loader.load!(root)["siala_41"]

      assert siala.classes[:cleric].bonus_feat_pool_adds == %{}
      assert {:not_modelled, {:class_change, :cleric, "bonus_feat_pool"}} in siala.gaps
    end
  end

  # Лестница «воин 7 → ЧТ 10 → воин 3 → ЧТ 4», собранная левелап за левелапом.
  # `Weapon focus` на длинный меч берётся бонусным слотом воина на 1-м уровне:
  # без него Чемпион Торма не берётся вовсе (требование класса).
  defp champion(ruleset) do
    base =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :lawful_good,
        base_abilities: %{str: 16, dex: 14, con: 14, int: 12, wis: 12, cha: 12},
        feats: %{1 => %{{:class_bonus, :fighter} => {:weapon_focus, :longsword}}}
      )

    ladder =
      List.duplicate(:fighter, 7) ++
        List.duplicate(:champion_of_torm, 10) ++
        List.duplicate(:fighter, 3) ++ List.duplicate(:champion_of_torm, 4)

    Enum.reduce(ladder, base, fn class, build ->
      assert Rules.validate_level_up(build, %{class: class}, ruleset) == :ok,
             "#{class} на уровне #{length(build.levels) + 1} — билд собран нелегально"

      Build.add_level(build, class)
    end)
  end

  # Чистый паладин 26 уровней, левелап за левелапом. Мировоззрение — Lawful
  # Good: класс требует его на КАЖДОМ своём уровне, и `true_neutral` из `pure/4`
  # отбил бы первый же.
  #
  # 26, а не 23: нужны ДВЕ точки эпической пачки (23 и 26), иначе «на обоих
  # уровнях» проверяет одну и ту же половину дважды.
  defp paladin(ruleset, opts \\ []) do
    pure(ruleset, :paladin, 26, Keyword.put(opts, :alignment, :lawful_good))
  end

  # Запись остаётся в данных и читается, но применена быть не может: категория
  # вне словаря — «шард сказал то, чего мы не формализовали». Ровно состояние
  # обеих записей до 24.08.2026.
  defp unapply_pool_fact(root, class_id) do
    edit_pool_fact(root, class_id, &put_in(&1["value"]["adds"], "не формализовано"))
  end

  defp copy_rules do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp edit_pools(root, fun) do
    edit_file(root, fn data ->
      Map.put(data, "_bonus_feat_pools", fun.(data["_bonus_feat_pools"]))
    end)
  end

  defp edit_pool_fact(root, class_id, fun) do
    edit_file(root, fn data ->
      classes =
        Enum.map(data["classes"], fn class ->
          if class["id"] == class_id do
            changes =
              Enum.map(class["changes"], fn change ->
                if change["what"] == "bonus_feat_pool", do: fun.(change), else: change
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
