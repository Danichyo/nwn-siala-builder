defmodule BuildCalculator.Rules.BonusesTest do
  @moduledoc """
  Общий плумбинг разметки прибавок — задачи 3.21 и 3.25.

  Шесть статов читали шесть файлов одной схемы шестью копиями одного кода. 3.21
  свела пять, 3.25 — шестую (её пришлось начинать с правки ДАННЫХ: у HP и навыков
  схема записи отличалась, см. `_migration` в обоих файлах). Этот
  файл проверяет **саму общую часть**, а не то, что каждый стат считает верно
  (это делают `ability_bonuses_test.exs`, `armor_class_test.exs`,
  `save_bonuses_test.exs`, `attack_bonuses_test.exs`,
  `feat_hp_bonuses_test.exs`, `skills_test.exs` — ни один из них не тронут).

  ⚠ **Общий код опаснее шести копий ровно тем, что ошибка в нём бьёт по всем
  статам сразу.** Поэтому здесь же стоит проверка обратного свойства: порча
  одной ветки плумбинга обязана уронить **один** стат, а не «всё вообще», —
  иначе тесты не различают поломки, и по красному прогону нельзя понять, что
  сломано.

  Источники ожиданий — сами файлы разметки, дословно:

    * `priv/rules/vanilla/feat_save_bonuses.json` — 14 применённых записей, у
      `Sacred defense` таблица по уровням класса Чемпиона Торма
      (`fandom:Sacred defense`, revid 41213);
    * `priv/rules/vanilla/ac_bonuses.json` — `Armor skin` +2 плоско,
      `Tumble` +1 за 5 рангов, таблица монаха по уровням класса;
    * `priv/rules/vanilla/feat_ability_bonuses.json` — `Great strength`
      `per_take` с потолком эффекта, `Dragon abilities` — ступени,
      **суммируемые**;
    * `priv/rules/vanilla/feat_attack_bonuses.json` — `Epic prowess` и
      `Small stature`, оба поверх капа (Dan, 09.08.2026).
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{AbilityBonuses, Bonuses, Build, Gear}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @flat %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

  defp build(levels, fields \\ []) do
    # ⚠ `fields` идёт ПОСЛЕ умолчаний, и это несущий порядок: `Build.new/1` кладёт
    # список в `Map.new/1`, где при повторе ключа побеждает ПОСЛЕДНИЙ. Поменяй
    # порядок — и `race: :halfling` в аргументе молча проиграет умолчанию, то есть
    # тест про расовую склонность зеленел бы на человеке.
    Build.new([levels: levels, base_abilities: @flat, race: :human] ++ fields)
  end

  describe "чтение половин разметки" do
    # Вердиктов четыре, а половин две: `counted_elsewhere` и `not_a_*` не
    # попадают ни в одну. Это не дыра — отвергнутые пишутся в данные С
    # вердиктом именно чтобы следующий читатель не «дочинил» пропуск.
    test "applied/2 и rejected/2 возвращают только свои вердикты", %{ruleset: ruleset} do
      for markup <- [:ac_bonuses, :ability_bonuses, :save_bonuses, :attack_bonuses] do
        applied = Bonuses.applied(ruleset, markup)
        rejected = Bonuses.rejected(ruleset, markup)

        assert applied != [], "#{markup}: применённых записей нет вовсе"
        assert Enum.all?(applied, &(&1.verdict == :applied))
        assert Enum.all?(rejected, &(&1.verdict == :not_modelled))
      end
    end

    # Отсутствие файла — это «нет таких прибавок», а не ошибка: ruleset без
    # слоя разметки обязан считаться, а не падать.
    test "ruleset без разметки даёт пустые половины, а не падает" do
      for markup <- [:ac_bonuses, :ability_bonuses, :save_bonuses, :attack_bonuses] do
        assert Bonuses.applied(%{}, markup) == []
        assert Bonuses.rejected(%{}, markup) == []
        assert Bonuses.applied(%{markup => nil}, markup) == []
      end
    end

    # Порядок — как в данных, и это часть контракта: разбор в панели печатает
    # термы в том порядке, в котором их назвал человек, писавший файл.
    test "порядок записей — как в файле", %{ruleset: ruleset} do
      ids = for r <- Bonuses.applied(ruleset, :save_bonuses), do: r.id

      assert Enum.take(ids, 3) == [:divine_grace, :dark_blessing, :sacred_defense]
    end
  end

  describe "held?/5 — пять видов источника" do
    test "фит считается по ВЛАДЕНИЮ, а не по взятию слотом", %{ruleset: ruleset} do
      # Paladin получает Divine grace выдачей класса на 4-м (Сиала перенесла
      # с 1-го), слот на него никто не тратит.
      paladin = build(List.duplicate(:paladin, 4))
      owned = Build.feats_owned(paladin, ruleset, 4)

      assert Bonuses.held?({:feat, :divine_grace}, paladin, ruleset, owned, 4)

      short = build(List.duplicate(:paladin, 3))

      refute Bonuses.held?(
               {:feat, :divine_grace},
               short,
               ruleset,
               Build.feats_owned(short, ruleset, 3),
               3
             )
    end

    test "фит с вещи держится так же, как взятый слотом", %{ruleset: ruleset} do
      geared = build([:wizard], gear: Gear.new(feats: [:armor_skin]))
      owned = Build.feats_owned(geared, ruleset, 1)

      assert Bonuses.held?({:feat, :armor_skin}, geared, ruleset, owned, 1)
    end

    test "класс — по своим уровням, набранным К этому уровню", %{ruleset: ruleset} do
      # Первые 10 уровней — монах, дальше воин; на 5-м монах есть, на 0-м нет.
      mixed = build(List.duplicate(:monk, 10) ++ List.duplicate(:fighter, 10))
      none = MapSet.new()

      assert Bonuses.held?({:class, :monk}, mixed, ruleset, none, 5)
      assert Bonuses.held?({:class, :monk}, mixed, ruleset, none, 20)
      refute Bonuses.held?({:class, :fighter}, mixed, ruleset, none, 10)
      assert Bonuses.held?({:class, :fighter}, mixed, ruleset, none, 11)
    end

    test "навык — как только куплен ранг, и тоже с учётом уровня", %{ruleset: ruleset} do
      b = build(List.duplicate(:rogue, 5), skills: %{3 => %{tumble: 2}})
      none = MapSet.new()

      refute Bonuses.held?({:skill, :tumble}, b, ruleset, none, 2)
      assert Bonuses.held?({:skill, :tumble}, b, ruleset, none, 3)
    end

    # Расовая склонность читается от расы и НИКОГДА от `feats_owned/3`:
    # расовых бонусных фитов там нет, а расширить эту функцию значило бы молча
    # изменить каждую проверку требований в приложении.
    test "расовая склонность — от расы, а не из владения фитами", %{ruleset: ruleset} do
      halfling = Build.new(levels: [:fighter], race: :halfling, base_abilities: @flat)
      human = Build.new(levels: [:fighter], race: :human, base_abilities: @flat)
      owned = Build.feats_owned(halfling, ruleset, 1)

      assert Bonuses.held?({:race_feat, :lucky}, halfling, ruleset, owned, 1)
      refute MapSet.member?(owned, :lucky), "склонность не должна быть во владении фитами"
      refute Bonuses.held?({:race_feat, :lucky}, human, ruleset, owned, 1)
    end

    test "раса — просто эта раса", %{ruleset: ruleset} do
      gnome = Build.new(levels: [:fighter], race: :gnome, base_abilities: @flat)
      none = MapSet.new()

      assert Bonuses.held?({:race, :gnome}, gnome, ruleset, none, 1)
      refute Bonuses.held?({:race, :dwarf}, gnome, ruleset, none, 1)
    end

    test "билд без расы не падает на расовых видах", %{ruleset: ruleset} do
      raceless = Build.new(levels: [:fighter], base_abilities: @flat)
      none = MapSet.new()

      refute Bonuses.held?({:race_feat, :lucky}, raceless, ruleset, none, 1)
      refute Bonuses.held?({:race, :gnome}, raceless, ruleset, none, 1)
    end

    # ⚠ Без catch-all СОЗНАТЕЛЬНО: несовпавший вид — сломанная сборка (какие
    # виды бывают, проверяет загрузчик на компиляции), а не живой запрос.
    # Ветка-заглушка `false` превратила бы это в прибавку, которая молча не
    # считается, — ровно ту поломку, от которой вся разметка и заведена.
    test "неизвестный вид источника падает, а не отвечает false", %{ruleset: ruleset} do
      b = build([:fighter])

      # Собирается на рантайме: литерал вывел бы тайпчекер на предупреждение
      # о несовпадении, а проверяется здесь именно поведение в рантайме.
      unknown = List.to_tuple([:deity, :tyr])

      assert_raise FunctionClauseError, fn ->
        Bonuses.held?(unknown, b, ruleset, MapSet.new(), 1)
      end
    end
  end

  describe "held/4 — записи, которые персонаж держит" do
    test "у голого воина 1-го уровня применённых записей сейвов нет", %{ruleset: ruleset} do
      assert Bonuses.held(build([:fighter]), ruleset, :save_bonuses, 1) == []
    end

    test "у паладина 4 — ровно Divine grace", %{ruleset: ruleset} do
      records = Bonuses.held(build(List.duplicate(:paladin, 4)), ruleset, :save_bonuses, 4)

      assert for(r <- records, do: r.id) == [:divine_grace]
    end

    test "уровень обрезает: тот же билд на 3-м уровне держит меньше", %{ruleset: ruleset} do
      paladin = build(List.duplicate(:paladin, 4))

      assert Bonuses.held(paladin, ruleset, :save_bonuses, 3) == []
      assert Bonuses.held(paladin, ruleset, :save_bonuses, 4) != []
    end
  end

  describe "rejected_ids/5" do
    # 🔴 ЗАПИСЬ СИНТЕТИЧЕСКАЯ — и это конец истории из трёх замен подряд.
    # Живой пример тут менялся 10.08.2026 (колонка Мастера оружия стала
    # `applied`), 17.08.2026 (Ярость и три умения монаха оказались баффами)
    # и 25.08.2026 (задача 3.95 сняла оговорки об условных прибавках решением
    # владельца). Каждый раз падал тест, проверяющий ПЛУМБИНГ, из-за правки
    # ДАННЫХ, — то есть пример был не тем, что проверяется.
    #
    # ⚠️ Синтетическая тут только сама запись разметки. Всё, ради чего этот
    # describe написан, остаётся живым: настоящий билд, настоящий
    # `Build.feats_owned/3`, настоящий гейт владения и настоящий словарь
    # получателей ruleset'а.
    @narrow_ac %{
      id: :made_up_narrow_ac_bonus,
      source: {:feat, :dodge},
      verdict: :not_modelled,
      type: nil,
      amount: nil,
      affects: ["ac"]
    }

    @narrow_attack %{
      id: :made_up_narrow_attack_bonus,
      source: {:race_feat, :battle_training_vs_orcs},
      verdict: :not_modelled,
      condition: nil,
      amount: nil,
      affects: ["attack_bonus"]
    }

    defp with_record(ruleset, markup, record) do
      Map.put(ruleset, markup, %{applied: [], unmodelled: [record], counted_elsewhere: []})
    end

    # Фит приходит с ВЕЩИ — значит выборка не зависит ни от одного слота.
    test "называет отвергнутые записи, которые персонаж держит", %{ruleset: ruleset} do
      geared = build([:barbarian], gear: Gear.new(feats: [:dodge]))
      rs = with_record(ruleset, :ac_bonuses, @narrow_ac)
      ids = Bonuses.rejected_ids(geared, rs, :ac_bonuses, 1)

      assert ids == [:made_up_narrow_ac_bonus]

      # И тот же ruleset на билде БЕЗ вещи: гейт владения живой, а не всегда
      # истинный.
      assert Bonuses.rejected_ids(build([:barbarian]), rs, :ac_bonuses, 1) == []
    end

    # Гном держит источник РАСОЙ, то есть без слотов и без вещей.
    test "фильтр — на запись, а не на id", %{ruleset: ruleset} do
      dwarf = build(List.duplicate(:fighter, 20), race: :dwarf)
      rs = with_record(ruleset, :attack_bonuses, @narrow_attack)

      all = Bonuses.rejected_ids(dwarf, rs, :attack_bonuses, 20)
      none = Bonuses.rejected_ids(dwarf, rs, :attack_bonuses, 20, filter: fn _ -> false end)

      assert all == [:made_up_narrow_attack_bonus]
      assert none == []

      # Человек ту же запись не держит — расовый маршрут проверяется, а не
      # обходится.
      assert Bonuses.rejected_ids(build(List.duplicate(:fighter, 20)), rs, :attack_bonuses, 20) ==
               []
    end

    test "uniq? по умолчанию сворачивает повторы", %{ruleset: ruleset} do
      rs = with_record(ruleset, :ac_bonuses, @narrow_ac)
      geared = build(List.duplicate(:barbarian, 41), gear: Gear.new(feats: [:dodge]))
      ids = Bonuses.rejected_ids(geared, rs, :ac_bonuses, 41)

      assert Enum.uniq(ids) == ids
    end

    # `gaps/6` — та же выборка, обёрнутая формой стата; форма живёт у стата,
    # потому что «прибавка от фита» у AC и у сейвов называется по-разному, а
    # `Rules.Vocabulary` регистрирует именно её.
    test "gaps/6 оборачивает те же id формой стата", %{ruleset: ruleset} do
      b = build([:barbarian], gear: Gear.new(feats: [:dodge]))
      rs = with_record(ruleset, :ac_bonuses, @narrow_ac)

      ids = Bonuses.rejected_ids(b, rs, :ac_bonuses, 1)
      gaps = Bonuses.gaps(b, rs, :ac_bonuses, 1, &{:not_modelled, {:ac_bonus, &1}})

      assert gaps == for(id <- ids, do: {:not_modelled, {:ac_bonus, id}})
      assert gaps != []
    end
  end

  # Второй гейт `held_rejected/4`, заведённый 17.08.2026: «держит ли персонаж
  # запись» и «печатаем ли мы то, что она меняет» — разные вопросы, и до этой
  # правки задавался только первый у четырёх статов из шести (разметка была, её
  # никто не читал). Правило и его сторона ошибки — `Rules.GapReceivers`.
  describe "гэп — дырка в ОТВЕТЕ, а не в знаниях" do
    # 🔴 Ярость — тот самый случай, ради которого фильтр и заведён: Dan закрыл
    # баффы 10.08.2026 («то, что включается и кончается, — не наше»), а варвар
    # продолжал получать три оговорки про неё — по характеристике, по AC и по
    # сейвам.
    test "варвар держит Ярость, но оговорки про неё больше не получает", %{ruleset: ruleset} do
      barbarian = build(List.duplicate(:barbarian, 20))
      owned = Build.feats_owned(barbarian, ruleset, 20)

      # Держит — гейт владения не тронут, менялся не он.
      assert Bonuses.held?({:feat, :barbarian_rage}, barbarian, ruleset, owned, 20)

      # И запись на месте, с вердиктом: фильтр не выбрасывает её из данных,
      # он отвечает на другой вопрос.
      rage = Enum.find(Bonuses.rejected(ruleset, :ac_bonuses), &(&1.id == :barbarian_rage))
      assert rage.verdict == :not_modelled
      assert rage.affects == ["buff"]

      refute :barbarian_rage in Bonuses.rejected_ids(barbarian, ruleset, :ac_bonuses, 20)
      refute :barbarian_rage in Bonuses.rejected_ids(barbarian, ruleset, :ability_bonuses, 20)
    end

    # Положительный контроль к нему же: фильтр не выкосил оговорки целиком.
    #
    # 🔴 Носитель СИНТЕТИЧЕСКИЙ, и это его четвёртая версия: `stonecunning`
    # (ушёл решением Dan, 3.76), `skill_focus` (стал посчитанным, 3.92),
    # `favored_enemy` (ушёл решением, 3.95). Три замены подряд означают, что
    # живой пример здесь проверяет не то: вопрос — про ПРАВИЛО фильтра,
    # а не про сегодняшний состав данных.
    #
    # ⚠️ Маршрут владения остаётся живым: фит настоящий, берётся слотом,
    # и `Build.feats_owned/3` его действительно находит.
    test "запись с нашим получателем оговоркой остаётся", %{ruleset: ruleset} do
      record = %{
        id: :made_up_narrow_skill_bonus,
        source: {:feat, :favored_enemy},
        verdict: :not_modelled,
        skills: [:listen],
        amount: nil,
        affects: ["skill_values"]
      }

      rs = Map.put(ruleset, :skill_bonuses, %{applied: [], unmodelled: [record]})

      rogue =
        build([:rogue, :rogue, :rogue], feats: %{3 => %{general: {:favored_enemy, :goblinoid}}})

      assert Bonuses.rejected_ids(rogue, rs, :skill_bonuses, 3) == [:made_up_narrow_skill_bonus]
    end

    # 🔴 Отрицательный контроль, без которого тест выше зеленел бы и на модели,
    # которая выбросила оговорки вообще. ⚠️ ДО 18.08.2026 здесь стоял живой
    # пример: `feat_save_bonuses.json` был шестым файлом семейства, и
    # разметку 17.08.2026 получили только пять — у той же Ярости оговорка по
    # сейвам оставалась непомеченной. Задача про шестой файл разметила и его
    # (`barbarian_rage` там теперь тоже `affects: ["buff"]`), так что живого
    # немаркированного примера в данных больше нет ни одного — правило «нет
    # метки — значит гэп» само по себе от этого не изменилось, и держать его
    # под тестом всё ещё нужно, поэтому запись здесь СИНТЕТИЧЕСКАЯ, тем же
    # приёмом, что и «словарь есть, метки нет» ниже.
    test "запись БЕЗ метки получателя оговоркой остаётся", %{ruleset: ruleset} do
      barbarian = build(List.duplicate(:barbarian, 20))

      unlabelled = %{
        id: :barbarian_rage,
        source: {:feat, :barbarian_rage},
        verdict: :not_modelled,
        saves: [:will],
        amount: %{kind: :flat, bonus: 2}
      }

      synthetic = Map.put(ruleset, :save_bonuses, %{applied: [], unmodelled: [unlabelled]})

      assert :barbarian_rage in Bonuses.rejected_ids(barbarian, synthetic, :save_bonuses, 20)
    end

    # ⚠️ Ruleset без словаря получателей не фильтрует НИЧЕГО, и ваниль — именно
    # такой: сиальского слоя у неё нет вовсе. Направление отказа то же, что у
    # всего механизма: молчать нельзя, лишняя оговорка дешевле пропавшей.
    test "у ванили словаря нет — фильтр не действует", %{vanilla: vanilla} do
      barbarian = build(List.duplicate(:barbarian, 20))

      assert MapSet.size(BuildCalculator.Rules.GapReceivers.our(vanilla)) == 0
      assert :barbarian_rage in Bonuses.rejected_ids(barbarian, vanilla, :ac_bonuses, 20)
      assert :barbarian_rage in Bonuses.rejected_ids(barbarian, vanilla, :ability_bonuses, 20)
    end

    # Тот же вопрос на синтетическом ruleset'е — чтобы правило держалось и без
    # живых данных: словарь есть, метки у записи нет.
    test "словарь есть, метки нет — запись остаётся", %{ruleset: ruleset} do
      unlabelled = %{
        id: :made_up,
        source: {:race, :human},
        verdict: :not_modelled,
        skills: [],
        amount: nil
      }

      synthetic =
        ruleset
        |> Map.put(:skill_bonuses, %{applied: [], unmodelled: [unlabelled]})

      ids = Bonuses.rejected_ids(build([:fighter]), synthetic, :skill_bonuses, 1)

      assert ids == [:made_up]

      # И тот же ruleset, где метка есть и она не наша, — записи нет.
      labelled = Map.put(unlabelled, :affects, ["damage"])
      dropped = Map.put(synthetic, :skill_bonuses, %{applied: [], unmodelled: [labelled]})

      assert Bonuses.rejected_ids(build([:fighter]), dropped, :skill_bonuses, 1) == []
    end
  end

  describe "whole_effect_counted?/3" do
    # Утверждение — данных (`effect_coverage`), и никогда не выводится из
    # того, что прибавка применена: `Snake blood` применён и всё равно
    # `partial`, потому что второй его эффект (против яда) не считает никто.
    test "whole_feat против partial", %{ruleset: ruleset} do
      assert Bonuses.whole_effect_counted?(ruleset, :ability_bonuses, :great_strength)
      assert Bonuses.whole_effect_counted?(ruleset, :save_bonuses, :iron_will)
      refute Bonuses.whole_effect_counted?(ruleset, :save_bonuses, :snake_blood)
      refute Bonuses.whole_effect_counted?(ruleset, :attack_bonuses, :small_stature)
    end

    test "фит, которого в этом файле нет, — false", %{ruleset: ruleset} do
      refute Bonuses.whole_effect_counted?(ruleset, :save_bonuses, :toughness)
    end

    # 🔴 Слепое пятно, закрытое 14.08.2026. Загрузчик выбрасывал записи
    # `counted_elsewhere` вовсе, поэтому фит, чей эффект посчитан НЕ своей
    # записью, был неотличим от фита, про который файл не спрашивали.
    # `Weapon of choice` числа не даёт сам — он назначает оружие колонке
    # «AB bonus» Мастера оружия, — и без этого чтения у каждого билда с ним
    # висела оговорка «прибавку от фита в статы не считаем» рядом
    # с посчитанным термом `weapon_master`.
    test "counted_elsewhere засчитывается, когда owned_by указывает на applied-запись", %{
      ruleset: ruleset
    } do
      assert Bonuses.whole_effect_counted?(ruleset, :attack_bonuses, :weapon_of_choice)

      # Положительный контроль к самому механизму: запись действительно лежит
      # во ВТОРОЙ половине, а не переехала в `applied` (иначе тест доказал бы
      # не то, что называет).
      applied_ids = for r <- Bonuses.applied(ruleset, :attack_bonuses), do: r.id
      elsewhere = Bonuses.counted_elsewhere(ruleset, :attack_bonuses)

      refute :weapon_of_choice in applied_ids
      assert :weapon_of_choice in Enum.map(elsewhere, & &1.id)
      assert :weapon_master in applied_ids
    end

    # ⚠️ Отрицательный контроль: указатель в МЕХАНИЗМ ядра или в задачу
    # не резолвится и оговорку не снимает. `Weapon finesse` и `Zen archery`
    # помечены `owned_by: "attack_ability"` — это смена характеристики,
    # а не запись этого файла, и проверить её отсюда нечем.
    test "owned_by в механизм ядра оговорку не снимает", %{ruleset: ruleset} do
      for id <- [:weapon_finesse, :zen_archery] do
        refute Bonuses.whole_effect_counted?(ruleset, :attack_bonuses, id), to_string(id)
      end
    end

    # ⚠️ И второе утверждение остаётся раздельным: вердикт говорит «эффект
    # доезжает», `effect_coverage` — «доезжает ЦЕЛИКОМ». Запись без покрытия
    # оговорку не снимает, даже когда её `owned_by` резолвится.
    test "counted_elsewhere без объявленного покрытия оговорку не снимает", %{ruleset: ruleset} do
      stripped =
        update_in(ruleset, [Access.key!(:attack_bonuses), :counted_elsewhere], fn records ->
          for r <- records, do: %{r | covers_feat?: false}
        end)

      refute Bonuses.whole_effect_counted?(stripped, :attack_bonuses, :weapon_of_choice)
    end
  end

  describe "class_level/2 и /3" do
    test "две арности отвечают на один вопрос в двух охватах", %{ruleset: _ruleset} do
      b = build(List.duplicate(:monk, 10) ++ List.duplicate(:fighter, 31))

      assert Bonuses.class_level(b, :monk) == 10
      assert Bonuses.class_level(b, :fighter) == 31
      assert Bonuses.class_level(b, :fighter, 10) == 0
      assert Bonuses.class_level(b, :fighter, 15) == 5
      assert Bonuses.class_level(b, :cleric) == 0
    end
  end

  describe "total_at_step/2 — «в таблице итоги»" do
    # `Sacred defense` печатает нарастающий итог: +1 на 2-м уровне класса,
    # +2 на 4-м. Это +2, а не +3 (`fandom:Champion of Torm`, revid 71573).
    @table %{2 => 1, 4 => 2, 6 => 3, 30 => 15}

    test "значение высшей достигнутой ступени" do
      assert Bonuses.total_at_step(@table, 1) == 0
      assert Bonuses.total_at_step(@table, 2) == 1
      assert Bonuses.total_at_step(@table, 3) == 1
      assert Bonuses.total_at_step(@table, 6) == 3
    end

    test "за последней ступенью держится последнее названное значение" do
      # Таблицы вики кончаются на 30-м или 40-м уровне класса, а кап Сиалы 41:
      # продолжать прогрессию значило бы выдумать число.
      assert Bonuses.total_at_step(@table, 41) == 15
    end

    test "пустая таблица — ноль, а не падение" do
      assert Bonuses.total_at_step(%{}, 41) == 0
    end

    # ⚠ Противоположное чтение — тоже настоящее, и живёт у характеристик:
    # `Dragon abilities` ступени СУММИРУЕТ. Проверяется через `compute`, чтобы
    # тест ловил именно то, что два чтения не слились в одно.
    test "у характеристик ступени суммируются, а не берутся по высшей", %{ruleset: ruleset} do
      rdd = build(List.duplicate(:red_dragon_disciple, 10))
      stats = Rules.compute(rdd, ruleset)

      strength = for t <- AbilityBonuses.terms(rdd, ruleset, 10), t.ability == :str, do: t.bonus

      assert stats.abilities_naked.str > @flat.str
      assert strength != []

      # Ступени 2/4/6/8/10 по +2 суммируются в +8; чтение «по высшей ступени»
      # дало бы +2, и именно это различие проверяется.
      assert Enum.sum(strength) == 8
    end
  end

  describe "sum/2 и group_sum/3" do
    test "sum/2 складывает по названному ключу" do
      assert Bonuses.sum([], :ac) == 0
      assert Bonuses.sum([%{ac: 2}, %{ac: -1}, %{ac: 5}], :ac) == 6
      assert Bonuses.sum([%{bonus: 3}, %{bonus: 4}], :bonus) == 7
    end

    # Цель, которую никто не поднял, ОТСУТСТВУЕТ, а не равна нулю: «здесь
    # ничего» и «вообще ничего» — разные утверждения.
    test "group_sum/3 не выдумывает нулевых целей" do
      terms = [
        %{save: :will, bonus: 2},
        %{save: :will, bonus: 4},
        %{save: :fort, bonus: 1}
      ]

      assert Bonuses.group_sum(terms, :save, :bonus) == %{will: 6, fort: 1}
      assert Bonuses.group_sum([], :save, :bonus) == %{}
    end

    # Ключ, которого у терма нет, — сломанный вызов, а не ноль: `Map.fetch!/2`
    # падает, потому что молча просуммированный нуль и есть та прибавка,
    # которая исчезает без следа.
    test "отсутствующий ключ падает, а не считается нулём" do
      assert_raise KeyError, fn -> Bonuses.sum([%{bonus: 1}], :ac) end
      assert_raise KeyError, fn -> Bonuses.group_sum([%{bonus: 1}], :save, :bonus) end
    end
  end

  describe "clip/3 — единственный клип потолка в ядре" do
    setup %{ruleset: ruleset} do
      %{tight: put_in(ruleset, [:stat_caps, :attack_bonus], 5)}
    end

    test "клип ОДИН по сумме, а не по каждому источнику", %{tight: tight} do
      # Три источника по 4 внутри капа: сумма 12, потолок 5. Клип по каждому
      # дал бы 12 (никто не превысил), и это ровно баг «фактически +40 при
      # потолке +20» (CLAUDE.md §9).
      sides = [{true, 4}, {true, 4}, {true, 4}]

      assert Bonuses.clip(tight, :attack_bonus, sides) ==
               %{total: 5, clipped: -7, capped?: true}
    end

    test "слагаемые поверх капа прибавляются ПОСЛЕ клипа", %{tight: tight} do
      # +1 от фита на билде, уже стоящем на потолке, — это +1, а не ничто
      # (Dan, 09.08.2026: «Фиты не входят в кап атаки +20»).
      assert Bonuses.clip(tight, :attack_bonus, [{true, 20}, {false, 1}]) ==
               %{total: 6, clipped: -15, capped?: true}
    end

    test "не укусивший потолок ничего не забирает", %{tight: tight} do
      assert Bonuses.clip(tight, :attack_bonus, [{true, 3}, {false, 2}]) ==
               %{total: 5, clipped: 0, capped?: false}
    end

    # У потолка одна сторона: все источники говорят про ПОТОЛОК бонуса, ни
    # один не называет пола. Отзеркалить +20 в −20 значило бы выдумать
    # игровое число.
    test "отрицательная сумма проходит нетронутой", %{tight: tight} do
      assert Bonuses.clip(tight, :attack_bonus, [{true, -7}]) ==
               %{total: -7, clipped: 0, capped?: false}
    end

    test "ruleset без потолка не клипает", %{ruleset: ruleset} do
      uncapped = put_in(ruleset, [:stat_caps, :attack_bonus], nil)

      assert Bonuses.clip(uncapped, :attack_bonus, [{true, 999}]) ==
               %{total: 999, clipped: 0, capped?: false}
    end

    test "пустой список — нулевой вклад", %{ruleset: ruleset} do
      assert Bonuses.clip(ruleset, :attack_bonus, []) ==
               %{total: 0, clipped: 0, capped?: false}
    end
  end

  describe "cap_side_gaps/5" do
    # Сегодня НИ ОДНА форма не появляется, и это результат работы, а не дыра:
    # 09.08.2026 три записи были `assumed`, и список Dan закрыл все три.
    test "на живых данных ни одного допущения про сторону капа", %{ruleset: ruleset} do
      assert Bonuses.cap_side_gaps(
               ruleset,
               :attack_bonus,
               :attack_bonuses,
               [gear: 5, racial_bonus: 1],
               [%{id: :epic_prowess, source: {:feat, :epic_prowess}, bonus: 1}]
             ) == []
    end

    test "запись с невыясненной стороной называет себя", %{ruleset: ruleset} do
      assumed =
        update_in(ruleset, [Access.key!(:attack_bonuses), :applied], fn records ->
          for r <- records do
            if r.id == :epic_prowess, do: put_in(r, [:cap, :assumed?], true), else: r
          end
        end)

      term = %{id: :epic_prowess, source: {:feat, :epic_prowess}, bonus: 1}

      assert Bonuses.cap_side_gaps(assumed, :attack_bonus, :attack_bonuses, [], [term]) ==
               [{:assumed, {:cap_covers_entry, :attack_bonus, :epic_prowess}}]
    end

    # Оговорка про вопрос, который не возникает, — шум: нулевой вклад
    # оговорки не стоит.
    test "нулевой терм оговорки не получает", %{ruleset: ruleset} do
      assumed =
        update_in(ruleset, [Access.key!(:attack_bonuses), :applied], fn records ->
          for r <- records do
            if r.id == :epic_prowess, do: put_in(r, [:cap, :assumed?], true), else: r
          end
        end)

      term = %{id: :epic_prowess, source: {:feat, :epic_prowess}, bonus: 0}

      assert Bonuses.cap_side_gaps(assumed, :attack_bonus, :attack_bonuses, [], [term]) == []
    end

    test "механизм с невыясненной стороной называет вид источника", %{ruleset: ruleset} do
      assumed =
        put_in(ruleset, [:stat_cap_sources, :attack_bonus, :gear], %{
          inside?: true,
          assumed?: true
        })

      assert Bonuses.cap_side_gaps(assumed, :attack_bonus, :attack_bonuses, [gear: 5], []) ==
               [{:assumed, {:cap_covers_source, :attack_bonus, :gear}}]
    end
  end

  # ⚠️ Здесь стоял блок про `owned_feat_fields/4` — «вторую форму, в которой
  # разметка приходит в ядро»: загрузчик вливал `feat_hp_bonuses.json` и
  # `feat_skill_bonuses.json` в поля фита. Задача 3.25 привела схему обоих файлов
  # к общей, второй формы больше нет, и функция удалена. Её место занял блок ниже:
  # шестой и пятый статы теперь ходят через тот же `held/4`, что и остальные.
  describe "held/4 и held_rejected/4 на двух переселённых статах (задача 3.25)" do
    test "HP: применённая запись приходит списком, с видом источника", %{ruleset: ruleset} do
      # Воину Сиала выдаёт Toughness на 1-м уровне класса даром.
      held = Bonuses.held(build([:fighter]), ruleset, :hp_bonuses, 1)

      assert for(r <- held, do: {r.id, r.source}) == [{:toughness, {:feat, :toughness}}]
    end

    test "HP: уровень обрезает выборку", %{ruleset: ruleset} do
      assert Bonuses.held(build([:fighter]), ruleset, :hp_bonuses, 0) == []
    end

    test "HP: фит с вещи держится так же, как выданный классом", %{ruleset: ruleset} do
      wizard = build([:wizard], gear: Gear.new(feats: [:toughness]))

      assert for(r <- Bonuses.held(wizard, ruleset, :hp_bonuses, 1), do: r.id) == [:toughness]
    end

    # ⚠️ Порядок — данных, а не алфавита, и это изменилось задачей 3.25: обход по
    # полям фита шёл по возрастанию id, поэтому в разборе HP `Epic toughness`
    # стоял ПЕРЕД `Toughness`. Теперь термы печатаются в том порядке, в котором
    # их назвал человек, писавший файл, — это контракт `applied/2`.
    test "HP: порядок как в файле, а не по алфавиту", %{ruleset: ruleset} do
      b = build(List.duplicate(:fighter, 21), feats: %{21 => %{general: :epic_toughness}})
      ids = for r <- Bonuses.held(b, ruleset, :hp_bonuses, 21), do: r.id

      assert ids == [:toughness, :epic_toughness]
      refute ids == Enum.sort(ids)
    end

    # 🔴 Регрессия на саму дыру задачи 3.25. Расовая склонность не бывает во
    # `feats_owned`, поэтому запись, помеченная `feat`, не доезжала ни до кого;
    # с видом `race_feat` она держится РАСОЙ.
    #
    # ⚠️ Раса поменялась 17.08.2026 с Гоблина на Гнома: `small_stature` получила
    # получателя `special_ability` и оговоркой быть перестала (её +4 к четырём
    # навыкам источник сам выносит за пределы значения навыка). `Stonecunning`
    # проверяет ровно тот же маршрут — расовая склонность Гнома, вид источника
    # `race_feat`, — и остаётся нашей: получатель `skill_values`.
    test "навыки: отвергнутая запись расовой склонности держится расой", %{ruleset: ruleset} do
      dwarf = build([:rogue], race: :dwarf)
      human = build([:rogue], race: :human)

      # ⚠️ 22.08.2026 (задача 3.76) проверка стала ТОЧНЕЕ прежней, а не слабее.
      # Раньше здесь стояло `assert :stonecunning in dwarf_ids` — но запись
      # получила `not_a_gap` решением Dan, и из оговорок ушла. Сегодня тест
      # разделяет два разных вопроса, которые прежняя формулировка смешивала:
      # ДЕРЖИТ ли персонаж источник (расовый маршрут) и ДОЛЖНЫ ли мы про него
      # признаваться (решение владельца).
      record = Enum.find(ruleset.skill_bonuses.unmodelled, &(&1.id == :stonecunning))

      # Вид источника действительно расовый, и склонность НЕ фит — иначе весь
      # маршрут `{:race_feat, id}` проверялся бы вхолостую.
      assert record.source == {:race_feat, :stonecunning}
      refute MapSet.member?(Build.feats_owned(dwarf, ruleset, 1), :stonecunning)

      # Гном источник ДЕРЖИТ, человек — нет. Это и есть расовый маршрут,
      # и он живёт независимо от того, признаёмся ли мы в записи.
      owned = Build.feats_owned(dwarf, ruleset, 1)
      assert Bonuses.held?(record.source, dwarf, ruleset, owned, 1)
      refute Bonuses.held?(record.source, human, ruleset, Build.feats_owned(human, ruleset, 1), 1)

      # А в оговорки не попадает НИ У КОГО — и ровно из-за решения владельца,
      # а не из-за получателя: `affects` у записи по-прежнему `["skill_values"]`.
      assert record.affects == ["skill_values"]
      refute :stonecunning in Bonuses.rejected_ids(dwarf, ruleset, :skill_bonuses, 1)
    end

    # `held_rejected/4` отдаёт ЗАПИСИ, а `rejected_ids/5` — имена, и второй
    # выражен через первый: одна выборка, две формы ответа.
    #
    # 🔴 Носитель СИНТЕТИЧЕСКИЙ, и это третья его смена подряд: `stonecunning`
    # (ушёл решением Dan, 3.76), `skill_focus` (стал посчитанным, 3.92),
    # `favored_enemy` (ушёл решением, 3.95). Каждый раз падал тест про
    # ПЛУМБИНГ из-за правки ДАННЫХ. Живых записей с нашим получателем
    # в разметке навыков сегодня не осталось ни одной, и завести пример заново
    # значило бы назначить четвёртую жертву.
    test "rejected_ids/5 — те же записи, только именами", %{ruleset: ruleset} do
      record = %{
        id: :made_up_narrow_skill_bonus,
        source: {:race_feat, :stonecunning},
        verdict: :not_modelled,
        skills: [:search],
        amount: nil,
        affects: ["skill_values"]
      }

      rs = Map.put(ruleset, :skill_bonuses, %{applied: [], unmodelled: [record]})
      dwarf = build([:rogue, :rogue, :rogue], race: :dwarf)

      records = for r <- Bonuses.held_rejected(dwarf, rs, :skill_bonuses, 3), do: r.id
      ids = Bonuses.rejected_ids(dwarf, rs, :skill_bonuses, 3)

      assert Enum.sort(ids) == Enum.sort(Enum.uniq(records))

      # ⚠️ Непустота проверяется отдельно и обязательна: без этой строки
      # равенство выше зеленело бы на двух ПУСТЫХ списках, то есть ничего
      # не проверяло.
      assert ids == [:made_up_narrow_skill_bonus]
    end
  end

  describe "ruleset версионируется — плумбинг читает тот, который дали" do
    # Один и тот же билд по двум ruleset'ам держит разные записи: Сиала
    # перенесла Divine grace с 1-го уровня паладина на 4-й.
    test "vanilla и siala_41 отвечают по-разному на одном билде", %{
      ruleset: siala,
      vanilla: vanilla
    } do
      paladin = build([:paladin])

      vanilla_ids = for r <- Bonuses.held(paladin, vanilla, :save_bonuses, 1), do: r.id
      siala_ids = for r <- Bonuses.held(paladin, siala, :save_bonuses, 1), do: r.id

      assert :divine_grace in vanilla_ids
      assert siala_ids == []
    end
  end
end
