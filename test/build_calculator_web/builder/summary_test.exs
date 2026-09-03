defmodule BuildCalculatorWeb.Builder.SummaryTest do
  @moduledoc """
  Разбор сейва — место, куда §3 требует вывести вклад Spellcraft.

  Число считает ядро; здесь проверяется, что подпись **сходится сама с собой**.
  Разбор, который не складывается в стоящее рядом значение, хуже отсутствующего:
  он выглядит как ошибка калькулятора ровно у тех билдов, ради которых
  калькулятор и открывают.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, Rules}
  alias BuildCalculator.Rules.{Build, Gear}
  alias BuildCalculatorWeb.Builder.{Feats, Labels, Summary}

  setup_all do
    ruleset = Data.ruleset!()

    %Build{} =
      build =
      Build.new(
        ruleset_version: ruleset.version,
        levels: List.duplicate(:fighter, 10),
        base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
      )

    %{ruleset: ruleset, build: build}
  end

  defp caption(ruleset, stats, key) do
    ruleset
    |> Summary.stat_cards(stats)
    |> Enum.find(&(&1.key == key))
    |> Map.fetch!(:from)
  end

  describe "save_terms/3" do
    # ⚠️ Задача 3.6 привела формат к общему: `%{label:, value:}`, как у
    # `ability_terms/1` (задача 3.13), а не `{value, label}` — раньше это была
    # единственная функция разбора, отдававшая тюплы для сентенции в `title`.
    #
    # ⚠️ Задача 1.12a добавила третий аргумент — `save` (`:fort`/`:ref`/
    # `:will`): собственные термы билда (`Iron will`, `Divine grace`…) больше
    # не «ко всем трём» одинаково, и без него разбор не знал бы, какой из
    # трёх сейвов показывает. Билды этого файла не берут ни одного такого
    # фита, поэтому выбор конкретного сейва в каждом тесте — тот, что уже
    # проверяет соседняя подпись (`caption(ruleset, stats, "fort")` и т.п.),
    # а не произвольный.
    test "без прибавок разбор кончается на эпике", %{ruleset: ruleset, build: build} do
      stats = Rules.compute(build, ruleset)

      assert Summary.save_terms(ruleset, stats, :fort) == []

      # Эпик == 0 у этого билда — молчит, тем же правилом «нулевое слагаемое
      # не несёт информации», что и у `ability_summary/2`.
      #
      # ⚠️ Классовая часть — терм на класс, а не «база 7»: до задачи «разбор
      # сейвов по классам» здесь стояло `"база 7 + CON +0"`.
      assert caption(ruleset, stats, "fort") == "Fighter 10 (высокий) 7 + CON +0"
    end

    test "прибавка с вещей названа, а не растворяется в числе", %{
      ruleset: ruleset,
      build: %Build{} = build
    } do
      # Раньше подпись обрывалась на эпике: сейв показывал +12, а сумма под ним
      # давала +7 — то есть арифметика на экране не сходилась сама с собой.
      stats = Rules.compute(%Build{build | gear: %Gear{saves: 5}}, ruleset)

      assert Summary.save_terms(ruleset, stats, :fort) == [%{label: "вещи", value: "+5"}]
      assert caption(ruleset, stats, "fort") =~ "вещи +5"
    end

    test "вклад Spellcraft назван поимённо — его игроки не считают", %{ruleset: ruleset} do
      # Sorcerer со Spellcraft: +1 ко всем трём сейвам за каждые 5 рангов.
      # Это та самая прибавка, которую §3 требует показывать, а не сворачивать
      # в общее число.
      stats = spellcraft_build(ruleset)

      assert %{label: "Spellcraft", value: value} =
               Enum.find(Summary.save_terms(ruleset, stats, :fort), &(&1.label == "Spellcraft"))

      assert {bonus, ""} = Integer.parse(value)
      assert bonus > 0

      for save <- ~w(fort ref will) do
        assert caption(ruleset, stats, save) =~ "Spellcraft #{value}"
      end
    end

    test "потолок один на вещи и Spellcraft, и разбор это признаёт", %{ruleset: ruleset} do
      # ⚠️ Потолок +20 общий на оба источника. Если бы слагаемые печатались
      # как есть, подпись обещала бы сумму больше той, что стоит рядом.
      stats = spellcraft_build(ruleset, %Gear{saves: 20})

      terms = Summary.save_terms(ruleset, stats, :will)
      %{label: "сверх капа", value: over_text} = List.last(terms)
      {over, ""} = Integer.parse(over_text)

      assert over < 0

      # Сумма слагаемых после среза равна тому, что ядро реально применило
      # к ЭТОМУ сейву.
      assert Enum.sum(Enum.map(terms, &(&1.value |> Integer.parse() |> elem(0)))) ==
               stats.save_bonus.will

      assert caption(ruleset, stats, "will") =~ "сверх капа #{over}"
    end

    test "штраф с вещей — такое же слагаемое, только со знаком", %{
      ruleset: ruleset,
      build: %Build{} = build
    } do
      # Разбор обязан сходиться и в минус: слагаемое печатается со своим знаком,
      # а «сверх капа» не появляется — срезать нечего, потолок описан для бонуса.
      stats = Rules.compute(%Build{build | gear: %Gear{saves: -3}}, ruleset)

      assert Summary.save_terms(ruleset, stats, :fort) == [%{label: "вещи", value: "-3"}]
      assert caption(ruleset, stats, "fort") =~ "вещи -3"
      refute caption(ruleset, stats, "fort") =~ "сверх капа"
      assert stats.fort == stats.base_fort - 3
    end

    test "новое слагаемое ядра появляется без правки разметки", %{
      ruleset: ruleset,
      build: build
    } do
      # Контракт: разметка про имена слагаемых ничего не знает, поэтому поле,
      # которого в `DerivedStats` ещё нет, читается нулём и просто не выводится —
      # а появившееся выводится само.
      stats = Rules.compute(build, ruleset)
      appeared = %{stats | skill_save_bonus: 3, save_bonus: %{fort: 3, ref: 3, will: 3}}

      assert Summary.save_terms(ruleset, stats, :fort) == []
      assert Summary.save_terms(ruleset, appeared, :fort) == [%{label: "Spellcraft", value: "+3"}]

      # Поля вовсе нет — читается нулём, а не роняет разбор.
      assert Summary.save_terms(ruleset, Map.delete(appeared, :skill_save_bonus), :fort) == []
    end
  end

  describe "save_summary_terms/5" do
    # Тот же контракт, что у `ability_summary/2` (CLAUDE.md §6): разбор
    # обязан сходиться с числом, которое он объясняет, классовая часть
    # открывает список, а нулевой эпик молчит.
    #
    # ⚠️ Раньше классовая часть была одним термом «база», и аргументов у функции
    # было шесть: `база` выводилась вычитанием эпика из `stats.base_fort`.
    # Теперь термы приходят из ядра (`stats.save_breakdown`), и лишний аргумент
    # снят.
    #
    # Sorcerer 40 уже эпический (уровни 21+) — `epic_save_bonus` у него
    # ненулевой, так что термин «эпик» есть чем проверить.
    test "классы, эпик и характеристика — сходятся с fort/ref/will", %{ruleset: ruleset} do
      stats = spellcraft_build(ruleset)
      assert stats.epic_save_bonus > 0
      mods = stats.ability_modifiers

      for {save, ability, modifier, value} <- [
            {:fort, :con, mods.con, stats.fort},
            {:ref, :dex, mods.dex, stats.ref},
            {:will, :wis, mods.wis, stats.will}
          ] do
        terms = Summary.save_summary_terms(ruleset, stats, save, ability, modifier)

        assert sum_terms(terms) == value, "#{inspect(terms)} ≠ #{value}"
        assert %{label: "Sorcerer 20 из 40 (" <> _, value: _} = hd(terms)
        assert %{label: "эпик", value: _} = Enum.find(terms, &(&1.label == "эпик"))
      end
    end

    test "эпик молчит, когда билд не эпический — нулевое слагаемое не несёт информации", %{
      ruleset: ruleset,
      build: build
    } do
      stats = Rules.compute(build, ruleset)

      terms =
        Summary.save_summary_terms(ruleset, stats, :fort, :con, stats.ability_modifiers.con)

      refute Enum.any?(terms, &(&1.label == "эпик"))
      assert sum_terms(terms) == stats.fort
    end
  end

  # Задача «разбор сейвов по классам». ⚠️ Списки термов сравниваются ЦЕЛИКОМ,
  # а не по вхождению, и по той же причине, что у `bab_terms/2`: половина термов
  # тут законно равна нулю («Rogue 0 из 16»), а нулевой терм суммы не меняет,
  # поэтому `sum_terms/1` не заметит ни его исчезновения, ни его удвоения.
  # Плюс у сейва три числа на строку — два из них можно перепутать между собой,
  # и все три посейвовые суммы всё равно сойдутся.
  describe "разбор сейва по классам" do
    # source: fandom "Fighter" revid 71988 — Fort основной («good»), Ref и Will
    # нет; таблица «Base save»: 20 уровней основного сейва дают +12, неосновного
    # +6. epic.json — чётные 22…40 дают +1 всем трём, на 41-м (нечётном) сейвам
    # ничего, поэтому эпик тут +10, а у BAB того же билда +11.
    test "у билда шире окна названы и класс, и отброшенные уровни", %{ruleset: ruleset} do
      stats = compute(ruleset, List.duplicate(:fighter, 41))

      assert save_breakdown_terms(ruleset, stats, :fort) == [
               %{label: "Fighter 20 из 41 (высокий)", value: "12"},
               %{label: "эпик", value: "+10"},
               %{label: "CON", value: "+0"}
             ]

      assert save_breakdown_terms(ruleset, stats, :will) == [
               %{label: "Fighter 20 из 41 (низкий)", value: "6"},
               %{label: "эпик", value: "+10"},
               %{label: "WIS", value: "+0"}
             ]

      for save <- [:fort, :ref, :will] do
        assert sum_terms(save_breakdown_terms(ruleset, stats, save)) == Map.fetch!(stats, save)
      end
    end

    # 🔴 Тот самый билд, ради которого задача заведена: у сейвов до неё стояло
    # одно число «база», и `Волшебник 20 → Воин 20` не показывал, что сейвы у
    # него волшебника, а двадцать уровней воина дали ноль.
    test "класс, чьи уровни не в счёт, назван нулём на каждом из трёх сейвов", %{
      ruleset: ruleset
    } do
      stats = compute(ruleset, List.duplicate(:wizard, 20) ++ List.duplicate(:fighter, 20))

      assert save_breakdown_terms(ruleset, stats, :fort) == [
               %{label: "Wizard 20 (низкий)", value: "6"},
               %{label: "Fighter 0 из 20 (высокий)", value: "0"},
               %{label: "эпик", value: "+10"},
               %{label: "CON", value: "+0"}
             ]

      assert save_breakdown_terms(ruleset, stats, :will) == [
               %{label: "Wizard 20 (высокий)", value: "12"},
               %{label: "Fighter 0 из 20 (низкий)", value: "0"},
               %{label: "эпик", value: "+10"},
               %{label: "WIS", value: "+0"}
             ]

      # ⚠️ Зеркало: тот же набор уровней в другом порядке — и Fort становится
      # воиновым. Без второй половины первая выглядела бы правильной и при
      # модели, которая порядок игнорирует вовсе.
      mirror = compute(ruleset, List.duplicate(:fighter, 20) ++ List.duplicate(:wizard, 20))

      assert save_breakdown_terms(ruleset, mirror, :fort) == [
               %{label: "Fighter 20 (высокий)", value: "12"},
               %{label: "Wizard 0 из 20 (низкий)", value: "0"},
               %{label: "эпик", value: "+10"},
               %{label: "CON", value: "+0"}
             ]
    end

    # Тот же билд, на котором задача 3.16 показывала BAB 28: два разбора одной
    # панели обязаны читаться одинаково, иначе разница выглядит багом.
    test "три класса, у вора нулевой — и порядок термов тот же, что у BAB", %{ruleset: ruleset} do
      stats =
        compute(
          ruleset,
          List.duplicate(:fighter, 10) ++
            List.duplicate(:cleric, 15) ++ List.duplicate(:rogue, 16)
        )

      assert save_breakdown_terms(ruleset, stats, :will) == [
               %{label: "Fighter 10 (низкий)", value: "3"},
               %{label: "Cleric 10 из 15 (высокий)", value: "7"},
               %{label: "Rogue 0 из 16 (низкий)", value: "0"},
               %{label: "эпик", value: "+10"},
               %{label: "WIS", value: "+0"}
             ]

      # Классы в том же порядке и с теми же счётчиками уровней, что в разборе
      # BAB, — обе подписи читает один игрок в одной панели. Сравниваются имена
      # без слова прогрессии: слова у BAB и у сейва разные намеренно, а вот
      # «Cleric 10 из 15» обязано читаться одинаково в обеих строках.
      assert class_prefixes(save_breakdown_terms(ruleset, stats, :will)) ==
               class_prefixes(Summary.bab_terms(ruleset, stats))

      assert class_prefixes(save_breakdown_terms(ruleset, stats, :will)) ==
               ["Fighter 10", "Cleric 10 из 15", "Rogue 0 из 16"]
    end

    # ⚠️ Метки у сейва свои, и их две, а не три: подставить сюда слова BAB
    # («полный»/«средний») невозможно молча — они бы просто не совпали.
    test "прогрессия — слово из двух возможных, а не коэффициент", %{ruleset: ruleset} do
      stats = compute(ruleset, List.duplicate(:cleric, 15))

      labels =
        for save <- [:fort, :ref, :will],
            t <- save_breakdown_terms(ruleset, stats, save),
            do: t.label

      assert "Cleric 15 (высокий)" in labels
      assert "Cleric 15 (низкий)" in labels
      refute Enum.any?(labels, &(&1 =~ "средний"))
      refute Enum.any?(labels, &(&1 =~ ~r/[0-9]\/[0-9]|×|0\.5/))
    end

    # `subtotals: nil` у класса, чью строку таблицы прочитать нечем: печатается
    # «?», а не молчаливый нуль, — и на всех трёх сейвах сразу, потому что
    # непрочитанная строка это три неизвестных, а не одно.
    test "непрочитанная строка таблицы печатается «?» на всех трёх сейвах", %{ruleset: ruleset} do
      stats = compute(ruleset, List.duplicate(:weapon_master, 15))

      for {save, word} <- [{:fort, "низкий"}, {:ref, "высокий"}, {:will, "низкий"}] do
        assert hd(save_breakdown_terms(ruleset, stats, save)) ==
                 %{label: "Weapon master 15 (#{word})", value: "?"}
      end
    end

    # ⚠️ Четыре разных слагаемых поверх классовой части сразу: эпик, CHA через
    # `Divine grace`, классовая таблица `Sacred defense`, вещи — и срез капа
    # +20 последним. Разбор обязан сойтись со ВСЕМИ ними, а не только
    # с классовой частью.
    test "паладин с харизмой и вещами: разбор сходится со всем, включая кап", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels:
            List.duplicate(:paladin, 20) ++
              List.duplicate(:champion_of_torm, 10) ++ List.duplicate(:monk, 11),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 18},
          gear: %Gear{saves: 20}
        )

      stats = Rules.compute(build, ruleset)

      # ⚠️ **Порядок термов = сторона капа** (правка 09.08.2026): сначала то, что
      # потолок режет (`Sacred defense` — единственная запись разметки под капом,
      # и вещи), потом срез, и только потом то, что лежит ПОВЕРХ него
      # (`Divine grace`). Иначе строка «сверх капа −5» стоит под именем фита,
      # который ничего не потерял, — то есть разбор обвиняет невиновного.
      assert save_breakdown_terms(ruleset, stats, :fort) == [
               %{label: "Paladin 20 (высокий)", value: "12"},
               %{label: "Champion of Torm 0 из 10 (высокий)", value: "0"},
               %{label: "Monk 0 из 11 (высокий)", value: "0"},
               %{label: "эпик", value: "+10"},
               %{label: "CON", value: "+0"},
               %{label: "Sacred defense", value: "+5"},
               %{label: "вещи", value: "+20"},
               %{label: "сверх капа", value: "-5"},
               %{label: "Divine grace (CHA)", value: "+4"}
             ]

      # ⚠️ И это не только «список красивый»: сумма всех девяти обязана равняться
      # числу, которое стоит рядом, — иначе подпись противоречит значению.
      for save <- [:fort, :ref, :will] do
        assert sum_terms(save_breakdown_terms(ruleset, stats, save)) == Map.fetch!(stats, save)
      end

      # Положительный контроль к «сверх капа»: кап действительно сработал, и
      # ядро об этом говорит само.
      assert :fort_save in stats.capped

      # ⚠️ Классовая часть в кап НЕ входит: 12 базовых плюс эпик остаются целыми,
      # срезано только то, что выше +20 прибавок ПОД капом, а `Divine grace`
      # прибавляется сверх среза (Dan, 09.08.2026: «У сейвов тоже фиты не входят
      # в кап +20»).
      assert stats.fort == 12 + 10 + 20 + 4
    end

    test "у пустого билда классовых термов нет, а характеристика остаётся", %{ruleset: ruleset} do
      stats = compute(ruleset, [])

      assert save_breakdown_terms(ruleset, stats, :fort) == [%{label: "CON", value: "+0"}]
    end
  end

  describe "ab_terms/2" do
    test "BAB, characteristic and gear sum to attack_bonus", %{ruleset: ruleset, build: build} do
      stats = Rules.compute(build, ruleset)
      terms = Summary.ab_terms(ruleset, stats)

      assert sum_terms(terms) == stats.attack_bonus
      assert %{label: "BAB", value: _} = hd(terms)
    end

    # ⚠️ Задача 3.6, найденный баг: подпись на экране просмотра раньше писала
    # «BAB + STR» БЕЗУСЛОВНО, даже когда Weapon finesse переключает атаку на
    # DEX — то есть врала ровно у тех билдов, ради которых Finesse и берут.
    test "Weapon finesse называет DEX, а не зашитый STR", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          base_abilities: %{str: 10, dex: 16, con: 10, int: 10, wis: 10, cha: 10},
          feats: %{1 => %{general: :weapon_finesse}}
        )

      stats = Rules.compute(build, ruleset)
      terms = Summary.ab_terms(ruleset, stats)

      # Предпосылка теста: правило и вправду сработало (DEX +3 выше STR +0).
      assert stats.attack_ability == :dex

      assert %{label: "DEX", value: "+3"} in terms
      refute Enum.any?(terms, &(&1.label == "STR"))
      assert sum_terms(terms) == stats.attack_bonus
    end

    # ⚠️ Не только «нет термина «с вещей»»: список сравнивается ЦЕЛИКОМ, а не
    # по одному отсутствующему лейблу — иначе гэп-подобный терм с нулевым или
    # текстовым значением («фиты на оружие: не считаем») мог бы просочиться
    # в поп-ап никем не замеченным (порча в отчёте задачи 3.6 это подтвердила:
    # терм с value «+0» ни одну из прежних проверок этого блока не ловил).
    test "положительный контроль: без вещей термина «с вещей» нет, список закрыт", %{
      ruleset: ruleset,
      build: build
    } do
      stats = Rules.compute(build, ruleset)
      # Билд из `setup_all`: 10 уровней Fighter (BAB 1:1), STR 10 без вещей.
      assert stats.base_attack == 10

      assert Summary.ab_terms(ruleset, stats) == [
               %{label: "BAB", value: "+10"},
               %{label: "STR", value: "+0"}
             ]
    end

    # 🔴 Задача 3.22: прибавка от вещей входит В ТЕРМ ХАРАКТЕРИСТИКИ, а не стоит
    # рядом с ним вторым числом. Запрос Dan 10.08.2026: «В билде + вещах у меня
    # 42 STR, логичнее было бы показать в итого „STR +16“, чем „STR +10“,
    # „вещи +6“». Довод сильнее вкуса: сейвы и «AC в шмоте» печатали модификатор
    # с вещами одним термом всегда, AB был единственным исключением, и `STR +10`
    # не соответствовал ни одной цифре на экране.
    #
    # ⚠️ Список сравнивается ЦЕЛИКОМ: терм «вещи» с тем же значением сумму не
    # двинул бы, и «сходится ли итог» подмену не поймало бы.
    test "прибавка с вещей входит в терм характеристики, своей строки нет", %{
      ruleset: ruleset,
      build: %Build{} = build
    } do
      stats = Rules.compute(%Build{build | gear: Gear.new(abilities: %{str: 4})}, ruleset)
      terms = Summary.ab_terms(ruleset, stats)

      # Билд из `setup_all`: 10 уровней Fighter, STR 10 (голый модификатор +0),
      # вещи +4 к силе дают +2 к модификатору.
      assert stats.ability_modifiers_naked.str == 0
      assert stats.gear_attack_bonus == 2

      assert terms == [
               %{label: "BAB", value: "+10"},
               %{label: "STR", value: "+2"}
             ]

      assert sum_terms(terms) == stats.attack_bonus
    end

    # ⚠️ Ruleset без правил характеристики атаки (`{:missing_data,
    # :attack_ability_rules}` в его гэпах): терма характеристики нет вовсе, и
    # слияние ничего не уносит — прибавка от вещей у такого билда сама ноль,
    # потому что она разность двух модификаторов ОДНОЙ характеристики.
    test "без правил характеристики атаки терма нет, и сумма всё равно сходится", %{
      ruleset: ruleset,
      build: %Build{} = build
    } do
      # ⚠️ `weapon_defaults` в этой синтетике с 15.08.2026 (задача 3.34): у хука
      # три поля, и ruleset без дефолта обязан быть пустым во всех трёх, а не
      # уронить `Rules.Attack` на отсутствующем ключе.
      no_ability =
        put_in(ruleset, [Access.key!(:attack_ability)], %{
          default: nil,
          weapon_defaults: [],
          rules: []
        })

      geared = %Build{build | gear: Gear.new(abilities: %{str: 12})}
      stats = Rules.compute(geared, no_ability)

      assert stats.attack_ability == nil
      assert stats.gear_attack_bonus == 0

      terms = Summary.ab_terms(no_ability, stats)

      assert terms == [%{label: "BAB", value: "+10"}]
      assert sum_terms(terms) == stats.attack_bonus

      # Положительный контроль: на настоящем ruleset'е тот же билд терм несёт,
      # и он слитый.
      assert %{label: "STR", value: "+6"} in Summary.ab_terms(
               ruleset,
               Rules.compute(geared, ruleset)
             )
    end

    # 🔴 Референсный билд Dan теми же числами, что он назвал: Воин 10 / Дварфийский
    # защитник 23 / Мастер оружия 7, STR 30 голой и 42 в вещах, `Epic prowess`.
    # Просил он ровно `BAB +30 · STR +16 · Epic prowess +1`, и до 10.08.2026 здесь
    # стояло `BAB +30 · STR +10 · вещи +6 · Epic prowess +1`.
    test "референсный билд: BAB +30 · STR +16 · Epic prowess +1", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels:
            List.duplicate(:fighter, 10) ++
              List.duplicate(:dwarven_defender, 23) ++ List.duplicate(:weapon_master, 7),
          base_abilities: %{str: 30, dex: 13, con: 16, int: 14, wis: 8, cha: 6},
          race: :dwarf,
          gear: Gear.new(abilities: %{str: 12, con: 12, dex: 12}),
          feats: %{21 => %{general: :epic_prowess}}
        )

      stats = Rules.compute(build, ruleset)

      # Предпосылка: в панели у него стоит STR 42, то есть модификатор +16, —
      # и именно это число обязано стоять рядом с именем `STR`.
      assert stats.abilities.str == 42
      assert stats.ability_modifiers.str == 16
      assert stats.ability_modifiers_naked.str == 10

      assert Summary.ab_terms(ruleset, stats) == [
               %{label: "BAB", value: "+30"},
               %{label: "STR", value: "+16"},
               %{label: "Epic prowess", value: "+1"}
             ]

      assert sum_terms(Summary.ab_terms(ruleset, stats)) == stats.attack_bonus
      assert stats.attack_bonus == 47
    end

    # ⚠️ Тождество, на котором держится слияние: `gear_attack_bonus` в ядре и есть
    # разность двух модификаторов, поэтому «голый + вещи» — это ровно
    # `ability_modifiers[attack_ability]`. Проверяется на НЕСКОЛЬКИХ билдах, включая
    # отрицательную прибавку с вещей: сумма термов обязана точно равняться
    # `attack_bonus` в каждом.
    test "слитый терм = голый модификатор + вещи, и сумма сходится всюду", %{ruleset: ruleset} do
      abilities = %{str: 14, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

      gears = [
        Gear.new(),
        Gear.new(abilities: %{str: 1}),
        Gear.new(abilities: %{str: 12}),
        Gear.new(abilities: %{str: -4}),
        Gear.new(abilities: %{str: 12}, saves: 5)
      ]

      for levels <- [[:fighter], List.duplicate(:fighter, 41), List.duplicate(:wizard, 41)],
          race <- [:human, :half_elf, :gnome],
          gear <- gears do
        build =
          Build.new(
            ruleset_version: ruleset.version,
            levels: levels,
            base_abilities: abilities,
            race: race,
            gear: gear
          )

        stats = Rules.compute(build, ruleset)
        terms = Summary.ab_terms(ruleset, stats)
        where = "#{race} #{length(levels)} #{inspect(gear.abilities)}"

        assert %{label: "STR", value: signed(stats.ability_modifiers.str)} in terms, where

        assert stats.ability_modifiers.str ==
                 stats.ability_modifiers_naked.str + stats.gear_attack_bonus,
               where

        assert sum_terms(terms) == stats.attack_bonus, where
      end
    end

    # Задача 3.12: расовый бонус Сиалы — второе слагаемое сверх базы и
    # характеристики. ⚠️ Список сравнивается ЦЕЛИКОМ по той же причине, что
    # у положительного контроля выше: терм со значением `+0` сумму не двинул бы,
    # и «сходится ли итог» такую поломку не поймало бы.
    #
    # ⚠️ +9, а не +6: лестница из 40 уровней ВОИНА — это чистый воин Сагры, и
    # с 08.08.2026 ему считается свой вариант числа (решение Dan). Парный кейс
    # с нарушенной чистотой — сразу ниже, иначе тест зеленел бы и у кода,
    # который берёт вариант сагровика всегда.
    test "расовый бонус Сиалы назван своим термом", %{ruleset: ruleset} do
      stats = Rules.compute(half_elf_40(ruleset), ruleset)

      assert Summary.ab_terms(ruleset, stats) == [
               %{label: "BAB", value: "+30"},
               %{label: "STR", value: "+0"},
               %{label: "раса", value: "+9"}
             ]

      assert sum_terms(Summary.ab_terms(ruleset, stats)) == stats.attack_bonus
    end

    test "у билда без чистоты тот же терм базовый", %{ruleset: ruleset} do
      %Build{} = build = half_elf_40(ruleset)
      mixed = %Build{build | levels: List.duplicate(:fighter, 39) ++ [:bard]}
      terms = Summary.ab_terms(ruleset, Rules.compute(mixed, ruleset))

      assert %{label: "раса", value: "+6"} in terms
      refute %{label: "раса", value: "+9"} in terms
    end

    # Положительный контроль к предыдущему: на 39-м уровне терма нет вовсе —
    # величина бонуса ниже 40-го неизвестна, и печатать там «раса +0» значило бы
    # утверждать, что бонуса нет.
    test "на 39-м уровне расового терма нет", %{ruleset: ruleset} do
      %Build{} = build = half_elf_40(ruleset)
      stats = Rules.compute(%Build{build | levels: List.duplicate(:fighter, 39)}, ruleset)

      assert Summary.ab_terms(ruleset, stats) == [
               %{label: "BAB", value: "+30"},
               %{label: "STR", value: "+0"}
             ]
    end

    # Задача 1.12b: собственные термы билда названы ПОИМЁННО, а не строкой
    # «фиты». ⚠️ Список сравнивается целиком и по той же причине, что у двух
    # контролей выше: терм со значением `+0` сумму не двинул бы, и «сходится ли
    # итог» такую поломку не поймало бы.
    test "собственный терм билда назван своим именем", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 21),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          race: :human,
          feats: %{21 => %{general: :epic_prowess}}
        )

      stats = Rules.compute(build, ruleset)

      assert Summary.ab_terms(ruleset, stats) == [
               %{label: "BAB", value: "+21"},
               %{label: "STR", value: "+0"},
               %{label: "Epic prowess", value: "+1"}
             ]

      assert sum_terms(Summary.ab_terms(ruleset, stats)) == stats.attack_bonus
    end

    # ⚠️ Порядок не косметика: он и ЕСТЬ утверждение о том, кого срезал потолок.
    # Сначала база (BAB и характеристика — под кап она не попадает вовсе, потому
    # что это не бонус), затем то, что кап покрывает (с 10.08.2026 это один
    # расовый бонус Сиалы), затем сам срез, затем лежащее поверх капа — прибавка
    # от фита (Dan, 09.08.2026: «Фиты не входят в кап атаки +20»).
    #
    # ⚠️ До 09.08.2026 порядок был обратным, и тогда он был ВЕРНЫМ: кап резал
    # все три источника, и срез обязан был идти последним. Здесь ровно то место,
    # где правка правила переворачивает требование к разбору, — иначе строка
    # «сверх капа −7» стоит под именем фита, который ничего не потерял.
    test "срезаемое, срез, несрезаемое — в этом порядке", %{ruleset: ruleset} do
      %Build{} = build = half_elf_40(ruleset)
      tight = %{ruleset | stat_caps: Map.put(ruleset.stat_caps, :attack_bonus, 8)}

      stats =
        Rules.compute(
          %Build{
            build
            | gear: armed_gear(abilities: %{str: 12}),
              feats: %{21 => %{general: :epic_prowess}}
          },
          tight
        )

      terms = Summary.ab_terms(tight, stats)

      assert Enum.map(terms, & &1.label) == ["BAB", "STR", "раса", "сверх капа", "Epic prowess"]

      # Вещи +6 доехали внутри терма характеристики, а не потерялись: срез (−1)
      # относится к расе, потому что она единственная под капом.
      assert %{label: "STR", value: "+6"} in terms
      assert %{label: "сверх капа", value: "-1"} in terms
      assert sum_terms(terms) == stats.attack_bonus
    end

    # 🔴 ПОРЧА задачи 3.22, обратная прежней: вернули вещи ПОД кап — терм обязан
    # разъехаться на два, `STR` голым и «вещи» перед срезом. Это ровно тот вид,
    # что был до 10.08.2026, и он остаётся правильным для ruleset'а, который
    # кладёт вещи внутрь капа: терм, половина которого срезана, а половина нет,
    # поставить некуда.
    #
    # ⚠️ Сравнивается список ЦЕЛИКОМ, а не сумма: сумма в обоих видах равна
    # `attack_bonus`, и «сходится ли итог» подмену не поймало бы вовсе.
    test "порча: вещи вернули под кап — терм разъехался на два", %{ruleset: ruleset} do
      %Build{} = build = half_elf_40(ruleset)

      as_before =
        %{ruleset | stat_caps: Map.put(ruleset.stat_caps, :attack_bonus, 8)}
        |> put_in([Access.key!(:stat_cap_sources), :attack_bonus, :gear, :inside?], true)

      stats =
        Rules.compute(
          %Build{
            build
            | gear: armed_gear(abilities: %{str: 12}),
              feats: %{21 => %{general: :epic_prowess}}
          },
          as_before
        )

      terms = Summary.ab_terms(as_before, stats)

      assert Enum.map(terms, & &1.label) ==
               ["BAB", "STR", "вещи", "раса", "сверх капа", "Epic prowess"]

      assert %{label: "STR", value: "+0"} in terms
      assert %{label: "вещи", value: "+6"} in terms
      assert sum_terms(terms) == stats.attack_bonus
    end

    # Собственный терм на одном билде поверх капа: `Epic prowess`, по слову Dan
    # (09.08.2026) он лежит ПОВЕРХ капа. Список сравнивается целиком.
    #
    # ⚠️ До 09.08.2026 `Epic prowess` стоял ДО среза, потому что его сторона
    # была объявленным допущением по виду источника (`feat`). Dan назвал его
    # в списке — допущение закрылось словом владельца, и строка переехала.
    #
    # ⚠️ **До 30.08.2026 (задача 3.143) тут стояло «оба собственных терма» —
    # у Карлика вторым был `Small stature` (+1 за размер).** Запись оказалась
    # applied по обрезанной цитате (условие «когда противник крупнее персонажа»
    # обрывалось до самого условия) и перестала считаться. У Карлика своих
    # applied-термов атаки сегодня не осталось вовсе (никакого оружия в руках
    # нет, а `Epic prowess` не расовый и не зависит от расы) — эта раса в тесте
    # больше ничего не доказывает, но переписывать билд не стали: важно само
    # число, а не то, что персонаж — Карлик.
    #
    # ⚠️ **Кап 4 в тесте (задача 3.22).** У Карлика под капом атаки не осталось
    # НИЧЕГО: расового бонуса к атаке у него не бывает, а вещи с 10.08.2026
    # наружу. Значит на настоящих сторонах среза нет вовсе, и «терм стоит ПОСЛЕ
    # среза» проверить нечем — искусственный кап возвращает вещи под него, чтобы
    # срез появился. Без него тест зеленел бы и при неверной модели.
    test "собственный терм стоит после среза", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 41),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          race: :gnome,
          gear: Gear.new(abilities: %{str: 12}),
          feats: %{21 => %{general: :epic_prowess}}
        )

      tight = %{ruleset | stat_caps: Map.put(ruleset.stat_caps, :attack_bonus, 4)}
      stats = Rules.compute(build, tight)
      terms = Summary.ab_terms(tight, stats)

      # Карлик: STR 8 голыми (−1) и 20 в вещах (+5) — слитый терм называет
      # второе, вещи внутри него, среза нет.
      assert terms == [
               %{label: "BAB", value: "+31"},
               %{label: "STR", value: "+5"},
               %{label: "Epic prowess", value: "+1"}
             ]

      assert sum_terms(terms) == stats.attack_bonus

      # Вернули вещи под кап — срез появился, и собственный терм стоит
      # ПОСЛЕ него. Ровно тот вид, что был до 10.08.2026.
      as_before =
        put_in(tight, [Access.key!(:stat_cap_sources), :attack_bonus, :gear, :inside?], true)

      before_stats = Rules.compute(build, as_before)
      before_terms = Summary.ab_terms(as_before, before_stats)

      assert before_terms == [
               %{label: "BAB", value: "+31"},
               %{label: "STR", value: "-1"},
               %{label: "вещи", value: "+6"},
               %{label: "сверх капа", value: "-2"},
               %{label: "Epic prowess", value: "+1"}
             ]

      assert sum_terms(before_terms) == before_stats.attack_bonus
    end

    # ⚠️ Потолок ОДИН на всё, что он покрывает, поэтому при срезе слагаемые
    # перестают складываться в стоящее рядом число — и отрицательный «сверх капа»
    # идёт отдельным термом, ровно как у сейвов. Подпись, противоречащая
    # значению, которое она объясняет, — единственное, чего разбор делать
    # не имеет права.
    #
    # ⚠️ С 10.08.2026 под капом атаки одна раса, поэтому срез относится к ней:
    # прибавка от вещей едет внутри терма характеристики и не режется.
    test "срез общего потолка признан отдельным слагаемым", %{ruleset: ruleset} do
      %Build{} = build = half_elf_40(ruleset)
      tight = %{ruleset | stat_caps: Map.put(ruleset.stat_caps, :attack_bonus, 8)}
      stats = Rules.compute(%Build{build | gear: armed_gear(abilities: %{str: 12})}, tight)

      terms = Summary.ab_terms(tight, stats)

      assert %{label: "STR", value: "+6"} in terms
      assert %{label: "раса", value: "+9"} in terms
      assert List.last(terms) == %{label: "сверх капа", value: "-1"}
      assert sum_terms(terms) == stats.attack_bonus

      # Положительный контроль: без искусственного потолка (настоящие 20)
      # среза нет вовсе, а термы те же.
      loose =
        Summary.ab_terms(
          ruleset,
          Rules.compute(%Build{build | gear: armed_gear(abilities: %{str: 12})}, ruleset)
        )

      refute Enum.any?(loose, &(&1.label == "сверх капа"))
      assert %{label: "раса", value: "+9"} in loose
    end

    # 🔴 Оружие в руках (задача 3.5, часть B). Dan: «будем показывать в деталях
    # об АБ значение с конкретным оружием» — то есть числа предмета названы
    # ИМЕНЕМ ОРУЖИЯ, а фиты на него стоят рядом своими именами.
    #
    # ⚠️ И порядок термов здесь — утверждение о капе. 🔴 **Он переворачивался
    # ТРИЖДЫ на одном и том же билде**, и все три записаны, чтобы четвёртый
    # читатель не решил, что кто-то ошибся:
    #
    #   10.08 (слово, J1)   — оружие ПОД капом → идёт ДО фитов
    #   15.08 (ЗАМЕР, Q5)   — снаружи → идёт ПОСЛЕ фитов
    #   18.08 (решение Dan) — снова под капом → снова ДО фитов
    #
    # Спор не разрешён: Dan решил, что «attack bonus оружия ВНУТРИ капа, инфа
    # 100%», и предположил, что в его замере лист персонажа показывал завышенное
    # AB. Проверяется переоткрытым Q5. Список сравнивается целиком, потому что
    # сумма во всех порядках одна — а порядок и есть проверяемое утверждение.
    test "число оружия названо именем оружия и стоит по свою сторону капа", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 41),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          race: :human,
          feats: %{
            1 => %{
              {:class_bonus, :fighter} => :siala_blade_proficiency,
              :general => {:weapon_focus, :scimitar}
            },
            21 => %{general: :epic_weapon_focus}
          },
          gear: Gear.new(weapon: :scimitar, weapon_attack: 5)
        )

      stats = Rules.compute(build, ruleset)
      terms = Summary.ab_terms(ruleset, stats)

      assert terms == [
               %{label: "BAB", value: "+31"},
               %{label: "STR", value: "+0"},
               %{label: "Scimitar", value: "+5"},
               %{label: "Weapon focus", value: "+1"},
               %{label: "Epic weapon focus", value: "+2"}
             ]

      assert sum_terms(terms) == stats.attack_bonus

      # Вторая половина того же утверждения: на срезающем потолке числа оружия
      # стоят ДО строки среза (они под капом, решение Dan 18.08.2026), а фокусы
      # после неё. Раса меняется на светлого эльфа, чтобы под капом было
      # не одно слагаемое, а два — иначе кейс не отличал бы «клип один на всех»
      # от «клип на каждого».
      tight = %{ruleset | stat_caps: Map.put(ruleset.stat_caps, :attack_bonus, 6)}
      elf = %Build{build | race: :half_elf}
      tight_terms = Summary.ab_terms(tight, Rules.compute(elf, tight))

      assert Enum.map(tight_terms, & &1.label) == [
               "BAB",
               "STR",
               "Scimitar",
               "раса",
               "сверх капа",
               "Weapon focus",
               "Epic weapon focus"
             ]

      # −8, а не −3: под капом теперь ДВА слагаемых (5 оружие, 9 раса = 14),
      # искусственный потолок 6 срезает 8. Прежние −3 считались от одного
      # расового +9, когда числа оружия стояли снаружи; −11 стояло здесь, пока
      # у предмета было второе число (задача 3.52 убрала усиление +3).
      assert %{label: "сверх капа", value: "-8"} in tight_terms
      assert sum_terms(tight_terms) == Rules.compute(elf, tight).attack_bonus
    end

    # Отрицательный контроль: без оружия в руках ни одного терма про оружие нет,
    # и фокусы в разбор тоже не попадают — они условны, и условие не выполнено.
    test "без оружия в руках термов про оружие нет вовсе", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 41),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          race: :human,
          feats: %{1 => %{general: {:weapon_focus, :scimitar}}}
        )

      stats = Rules.compute(build, ruleset)

      assert Summary.ab_terms(ruleset, stats) == [
               %{label: "BAB", value: "+31"},
               %{label: "STR", value: "+0"}
             ]
    end
  end

  # Вторая рука (задача 3.132, Dan: «наличие оружия во второй руке влияет
  # на АБ в главной … обновить АБ основной руки и левой руки тоже»).
  describe "off_hand_ab_terms/2, off_hand_apr_cards и штраф стиля (задачи 3.132/3.133)" do
    defp dual_wield_build(fields \\ []) do
      Build.new(
        [
          ruleset_version: Data.default_version(),
          race: :human,
          levels: List.duplicate(:fighter, 20),
          base_abilities: %{str: 18, dex: 14, con: 14, int: 10, wis: 10, cha: 10},
          gear:
            Gear.new(
              weapon: :katana,
              off_hand_weapon: :mace,
              feats: [:siala_blade_proficiency, :siala_hammer_proficiency]
            )
        ] ++ fields
      )
    end

    test "нет второй руки — нет термина «стиль боя», и карточки «Атак второй руки» нет", %{
      ruleset: ruleset,
      build: build
    } do
      stats = Rules.compute(build, ruleset)

      refute Enum.any?(Summary.ab_terms(ruleset, stats), &(&1.label == "бой двумя оружиями"))
      assert Summary.off_hand_ab_terms(ruleset, stats) == nil
      refute Enum.any?(Summary.stat_cards(ruleset, stats), &(&1.key == "off_hand_apr"))
    end

    # 🔴 Главный контракт задачи: разбор ГЛАВНОЙ руки обязан сходиться со своим
    # же итогом. Ядро уже складывает штраф в `stats.attack_bonus`
    # (`dual_wield_penalty.main`, `rules.ex`); без термина «стиль боя» сумма
    # термов расходилась бы с числом, которое они объясняют, — ровно то, чего
    # разбору делать нельзя.
    test "штраф стиля — последний терм главной руки, разбор сходится с attack_bonus", %{
      ruleset: ruleset
    } do
      build = dual_wield_build()
      stats = Rules.compute(build, ruleset)
      terms = Summary.ab_terms(ruleset, stats)

      assert List.last(terms) == %{label: "бой двумя оружиями", value: "-4"}
      assert sum_terms(terms) == stats.attack_bonus
    end

    # И вторая рука — своим разбором, своим итогом, своим (бОльшим) штрафом.
    test "разбор второй руки — тот же язык, своя сумма", %{ruleset: ruleset} do
      build = dual_wield_build()
      stats = Rules.compute(build, ruleset)
      terms = Summary.off_hand_ab_terms(ruleset, stats)

      assert %{label: "BAB", value: "+20"} in terms
      assert %{label: "STR", value: "+4"} in terms
      assert List.last(terms) == %{label: "бой двумя оружиями", value: "-8"}
      assert sum_terms(terms) == stats.off_hand.attack_bonus

      # Числа рук не совпадают — иначе тест не отличал бы «своя сумма» от
      # «скопировали главную».
      refute stats.off_hand.attack_bonus == stats.attack_bonus
    end

    # 🔴 Задача 3.133 (замечание 1, Dan: «показывает 4/1, но в реальности это
    # 4 атаки основной рукой и одна атака второй» — до этой задачи оба числа
    # печатались одной карточкой через слеш). Теперь у второй руки своя
    # карточка со своим числом, а не подмешанный хвост главной.
    test "атаки второй руки — своя карточка, число не копия главной", %{
      ruleset: ruleset
    } do
      one = Rules.compute(dual_wield_build(), ruleset)

      with_improved_twf =
        dual_wield_build(feats: %{1 => %{general: :improved_two_weapon_fighting}})

      two = Rules.compute(with_improved_twf, ruleset)

      apr_one = Enum.find(Summary.stat_cards(ruleset, one), &(&1.key == "apr"))
      off_apr_one = Enum.find(Summary.stat_cards(ruleset, one), &(&1.key == "off_hand_apr"))

      assert one.off_hand.attacks_per_round == 1
      assert apr_one.value == to_string(one.attacks_per_round)
      refute apr_one.value =~ "/"
      assert off_apr_one.value == "1"

      apr_two = Enum.find(Summary.stat_cards(ruleset, two), &(&1.key == "apr"))
      off_apr_two = Enum.find(Summary.stat_cards(ruleset, two), &(&1.key == "off_hand_apr"))

      assert two.off_hand.attacks_per_round == 2
      assert apr_two.value == to_string(two.attacks_per_round)
      assert off_apr_two.value == "2"

      # Главная рука не сдвинулась — число второй руки не подмешалось в первое.
      assert one.attacks_per_round == two.attacks_per_round
      assert apr_one.value == apr_two.value
    end
  end

  describe "ac_naked_terms/2 и ac_geared_terms/2" do
    test "«голым» сходится с ac_naked", %{ruleset: ruleset, build: build} do
      stats = Rules.compute(build, ruleset)
      assert sum_terms(Summary.ac_naked_terms(ruleset, stats)) == stats.ac_naked
    end

    test "«в шмоте» сходится с ac_geared и называет каждый ненулевой тип поимённо", %{
      ruleset: ruleset,
      build: %Build{} = build
    } do
      stats = Rules.compute(%Build{build | gear: Gear.new(ac: %{armor: 8, shield: 2})}, ruleset)
      terms = Summary.ac_geared_terms(ruleset, stats)

      assert sum_terms(terms) == stats.ac_geared
      assert %{label: "Броня", value: "+8"} in terms
      assert %{label: "Щит", value: "+2"} in terms

      # Положительный контроль: не введённый тип не попадает в разбор пустым,
      # и список сравнивается ЦЕЛИКОМ — счётчик длины не поймал бы терм
      # с нулевым значением, подмешанный ВМЕСТО одного из ожидаемых.
      refute Enum.any?(terms, &(&1.label == "Отклонение"))

      assert terms == [
               %{label: "база", value: "10"},
               %{label: "DEX", value: "+0"},
               %{label: "Броня", value: "+8"},
               %{label: "Щит", value: "+2"}
             ]
    end

    test "положительный контроль: без вещей в разборе только база и DEX", %{
      ruleset: ruleset,
      build: build
    } do
      stats = Rules.compute(build, ruleset)
      terms = Summary.ac_geared_terms(ruleset, stats)

      assert sum_terms(terms) == stats.ac_geared
      assert terms == [%{label: "база", value: "10"}, %{label: "DEX", value: "+0"}]
    end

    # 🔴 Задача 3.41: в разборе печатается ДОШЕДШАЯ ловкость, а не модификатор.
    # Иначе у любого в латах разбор перестаёт сходиться со своим же итогом —
    # ровно то, что этот describe и проверяет суммой.
    test "в латах терм DEX — срезанный, и сумма по-прежнему сходится", %{
      ruleset: ruleset,
      build: %Build{} = build
    } do
      nimble = %Build{
        build
        | base_abilities: %{str: 10, dex: 20, con: 10, int: 10, wis: 10, cha: 10}
      }

      bare = Rules.compute(nimble, ruleset)
      plate = Rules.compute(%Build{nimble | gear: Gear.new(worn: %{armor: :full_plate})}, ruleset)

      assert %{label: "DEX", value: "+5"} in Summary.ac_geared_terms(ruleset, bare)
      assert %{label: "DEX", value: "+1"} in Summary.ac_geared_terms(ruleset, plate)

      # ...и база предмета названа своим типом, а не подмешана в ловкость.
      assert %{label: "Броня", value: "+8"} in Summary.ac_geared_terms(ruleset, plate)
      assert sum_terms(Summary.ac_geared_terms(ruleset, plate)) == plate.ac_geared

      # ⚠️ А «голым» — по-прежнему полный модификатор: предела там нет
      # по построению, вещей в том проходе нет вовсе.
      assert %{label: "DEX", value: "+5"} in Summary.ac_naked_terms(ruleset, plate)
    end

    # 🔴 «Вписал число» перестало быть ответом на «одет ли»: латы без единой
    # цифры дают +8, а карточка печатала «?» и «посчитает армори».
    test "карточка «AC в шмоте» не печатает «?» у билда в выбранном доспехе", %{
      ruleset: ruleset,
      build: %Build{} = build
    } do
      dressed =
        Rules.compute(%Build{build | gear: Gear.new(worn: %{armor: :full_plate})}, ruleset)

      card = ruleset |> Summary.stat_cards(dressed) |> Enum.find(&(&1.key == "ac_geared"))

      assert card.value == "18"
      refute card.value == "?"

      # Положительный контроль: у голого билда «?» на месте — карточка не
      # разучилась его печатать.
      bare = Rules.compute(build, ruleset)
      bare_card = ruleset |> Summary.stat_cards(bare) |> Enum.find(&(&1.key == "ac_geared"))

      assert bare_card.value == "?"
    end

    # Задача 3.11: собственные прибавки билда названы поимённо, и список
    # сравнивается ЦЕЛИКОМ — «сумма сходится» здесь не проверка, потому что
    # терм с нулём её не сдвинет (HANDOFF, «сумма частей равна итогу»).
    #
    # ⚠️ У фита и у колонки таблицы класса РАЗНЫЕ подписи, хотя оба про монаха:
    # первое — «Monk AC bonus» (мудрость), второе — «Monk (класс)» (+1 за
    # каждые 5 уровней). Одно имя на две строки с разными числами читалось бы
    # как ошибка.
    #
    # ⚠️ До задачи 3.143 (30.08.2026) у Карлика тут был ещё терм `Small stature`
    # (+1 за размер): applied по обрезанной цитате, теперь not_modelled.
    test "«голым» называет собственные прибавки билда поимённо", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:monk, 20),
          race: :gnome,
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 16, cha: 10}
        )

      stats = Rules.compute(build, ruleset)
      terms = Summary.ac_naked_terms(ruleset, stats)

      assert terms == [
               %{label: "база", value: "10"},
               %{label: "DEX", value: "+0"},
               %{label: "Monk AC bonus (WIS)", value: "+3"},
               %{label: "Monk (класс)", value: "+4"}
             ]

      assert sum_terms(terms) == stats.ac_naked
    end

    # Каскад: мудрость с вещей поднимает монашеский AC, и в «голом» разборе её
    # быть не должно. Пара строк сравнивается целиком, потому что различие
    # ровно в одном числе.
    test "«в шмоте» считает прибавку монаха от одетой мудрости", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:monk, 4),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          gear: Gear.new(abilities: %{wis: 12})
        )

      stats = Rules.compute(build, ruleset)

      refute Enum.any?(Summary.ac_naked_terms(ruleset, stats), &(&1.label == "Monk AC bonus"))

      assert %{label: "Monk AC bonus (WIS)", value: "+6"} in Summary.ac_geared_terms(
               ruleset,
               stats
             )

      assert sum_terms(Summary.ac_geared_terms(ruleset, stats)) == stats.ac_geared
    end

    # Задача 3.12: щитовой бонус расы Карлика подписан ИМЕНЕМ РАСЫ.
    # ⚠️ Своя ветка подписи, а не хвост общей: `{:race_feat, id}` несёт id ФИТА
    # (`Small stature`), а `{:race, id}` — id самой расы, и общая ветка искала бы
    # `gnome` в словаре фитов и напечатала бы «gnome» — неизвестный id этот
    # справочник отдаёт как есть, то есть молча и правдоподобно.
    # ⚠️ Разбор берётся у «в шмоте», а не у «голым», и это правка 15.08.2026:
    # расовый бонус включается оружием в руках (замер Dan), а голое число
    # считается по билду с пустыми вещами — значит расового терма там нет
    # и быть не должно. Обе половины проверяются здесь же.
    #
    # 🔴 **И с задачи 3.35 щитовых терма ДВА**, что и делает этот кейс главным
    # доказательством правила про подписи: у Карлика с длинным мечом рядом стоят
    # «Карлик +9» (бонус расы) и «Longsword +9» (бонус за тип оружия). Числа
    # одинаковые, источники разные, и без двух разных имён это читалось бы как
    # одно число, напечатанное дважды по ошибке.
    #
    # ⚠️ До задачи 3.143 (30.08.2026) у Карлика тут был ещё терм `Small stature`
    # (+1 за размер, третий по счёту): applied по обрезанной цитате, теперь
    # not_modelled — своего терма не даёт ни «в шмоте», ни голым.
    test "щитовой бонус расы подписан именем расы, а не её id", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 40),
          race: :gnome,
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          gear: armed_gear([])
        )

      stats = Rules.compute(build, ruleset)
      terms = Summary.ac_geared_terms(ruleset, stats)

      assert terms == [
               %{label: "база", value: "10"},
               %{label: "DEX", value: "+0"},
               %{label: "Карлик", value: "+9"},
               %{label: "Longsword", value: "+9"}
             ]

      assert sum_terms(terms) == stats.ac_geared

      # Голым того же билда расового терма нет — оружие это вещь.
      assert Summary.ac_naked_terms(ruleset, stats) == [
               %{label: "база", value: "10"},
               %{label: "DEX", value: "+0"}
             ]

      refute Enum.any?(terms, &(&1.label == "gnome"))
    end
  end

  describe "hp_terms/2" do
    test "хит-дайсы по классам и CON сходятся с hp", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 10),
          base_abilities: %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 10}
        )

      stats = Rules.compute(build, ruleset)
      terms = Summary.hp_terms(ruleset, stats)

      assert sum_terms(terms) == stats.hp

      # CON 14 -> модификатор +2, за все 10 уровней: +20, не +2. Список
      # сравнён целиком: счётчик длины пропустил бы терм с нулевым значением,
      # добавленный третьим (порча в отчёте задачи 3.6 это подтвердила).
      #
      # Третья строка — «Дух Сиалы», флэт +20 у каждого персонажа на Сиале
      # (задача, волна 12, 09.08.2026); четвёртая — Toughness, который Сиала
      # выдаёт воину даром на первом уровне (задача 1.9). Обе названы именем,
      # а не свёрнуты в «фиты»: число рядом с именем игрок может проверить.
      assert terms == [
               %{label: "Fighter 10 (d10)", value: "100"},
               %{label: "CON × 10 ур.", value: "+20"},
               %{label: "Дух Сиалы", value: "+20"},
               %{label: "Toughness", value: "+10"}
             ]
    end

    # Взятия печатаются числом (`×3`), потому что 60 без него выглядит как
    # чужая цифра, а упор в потолок эффекта подписывается — иначе строка
    # «×11 +200» читается как ошибка сложения.
    test "Epic toughness показывает число взятий, а на потолке — что это потолок", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 41),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      thrice =
        Enum.reduce([21, 24, 27], build, &Build.put_feat(&2, &1, :general, :epic_toughness))

      terms = Summary.hp_terms(ruleset, Rules.compute(thrice, ruleset))

      assert %{label: "Epic toughness ×3", value: "+60"} in terms
      assert sum_terms(terms) == Rules.compute(thrice, ruleset).hp

      # ⚠️ Положительный контроль к подписи потолка: на трёх взятиях её нет.
      refute Enum.any?(terms, &(&1.label =~ "потолок"))

      capped = Enum.reduce(21..31, build, &Build.put_feat(&2, &1, :general, :epic_toughness))
      capped_terms = Summary.hp_terms(ruleset, Rules.compute(capped, ruleset))

      assert %{label: "Epic toughness ×11 (потолок)", value: "+200"} in capped_terms
    end

    test "минимум 1 HP/уровень называет себя, только когда действительно сработал", %{
      ruleset: ruleset
    } do
      normal =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      # d4 минус модификатор CON −4: без пола вышло бы 0 очков за уровень.
      floored =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:wizard, 3),
          base_abilities: %{str: 10, dex: 10, con: 3, int: 10, wis: 10, cha: 10}
        )

      # Положительный контроль: обычный билд термина не несёт вовсе — список
      # сравнён целиком, а не только по отсутствующему лейблу.
      #
      # Сумма сходится с GAME_CHECKS.md A1 буквально: 10 + 0 + 20 + 1 = 31 —
      # это ровно тот воин 1 CON 10, которого Dan снял с листа персонажа
      # 09.08.2026 (задача, волна 12).
      normal_stats = Rules.compute(normal, ruleset)
      normal_terms = Summary.hp_terms(ruleset, normal_stats)
      refute Enum.any?(normal_terms, &(&1.label =~ "минимум"))

      assert normal_terms == [
               %{label: "Fighter 1 (d10)", value: "10"},
               %{label: "CON × 1 ур.", value: "+0"},
               %{label: "Дух Сиалы", value: "+20"},
               %{label: "Toughness", value: "+1"}
             ]

      floored_stats = Rules.compute(floored, ruleset)
      floored_terms = Summary.hp_terms(ruleset, floored_stats)

      assert sum_terms(floored_terms) == floored_stats.hp

      # «Дух Сиалы» стоит ПОСЛЕ CON и ПЕРЕД полом — он ложится после пола
      # арифметически (Progression.hit_points/3), а не «где попало» в списке.
      assert floored_terms == [
               %{label: "Wizard 3 (d4)", value: "12"},
               %{label: "CON × 3 ур.", value: "-12"},
               %{label: "Дух Сиалы", value: "+20"},
               %{label: "минимум 1 HP/уровень", value: "+3"}
             ]
    end

    # ⚠️ На ruleset'е, из которого хит-дайс ВЫНУТ: задача 3.37 прочитала
    # растущий дайс Ученика красного дракона, и классов без хит-дайса
    # в корпусе не осталось. Свойство «непосчитанному нечем открывать поп-ап»
    # от этого никуда не делось, а проверять его стало не на чем.
    test "nil, когда сам hp — nil: непосчитанному нечем открывать поп-ап", %{ruleset: ruleset} do
      dieless =
        update_in(ruleset.classes[:red_dragon_disciple], fn class ->
          %{class | hit_die: nil, hit_die_by_class_level: nil}
        end)

      build =
        Build.new(ruleset_version: ruleset.version, levels: [:sorcerer, :red_dragon_disciple])

      stats = Rules.compute(build, dieless)

      assert stats.hp == nil
      assert Summary.hp_terms(dieless, stats) == nil
    end

    # Задача 3.37: у класса с растущим хит-дайсом подпись обязана называть все
    # дайсы, которые билд прошёл, — одно число рядом с `subtotal`, на которое
    # тот не делится, читалось бы как ошибка калькулятора.
    test "растущий хит-дайс печатается лестницей дайсов, а не одним числом", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:bard, 6) ++ List.duplicate(:red_dragon_disciple, 7),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      terms = Summary.hp_terms(ruleset, Rules.compute(build, ruleset))

      assert %{label: "Red dragon disciple 7 (d6×3 + d8×2 + d10×2)", value: "54"} in terms

      # У класса с одним дайсом подпись прежняя — список из одной записи
      # печатается тем же «d6», что и раньше.
      assert %{label: "Bard 6 (d6)", value: "36"} in terms
    end
  end

  # Задача 3.16. ⚠️ Все списки термов сравниваются ЦЕЛИКОМ, а не по вхождению:
  # у этого разбора половина термов может законно равняться нулю («Rogue 0 из
  # 16»), а нулевой терм суммы не меняет — `sum_terms/1` его пропустит, даже
  # если он исчезнет или удвоится.
  describe "bab_terms/2" do
    # source: fandom "Fighter" revid 71988 (high, +1/уровень); epic.json —
    # нечётные 21…41 дают +1 к атаке, на 41-м всего +11.
    test "у билда внутри окна разбор — один класс и эпик", %{ruleset: ruleset} do
      stats = compute(ruleset, List.duplicate(:fighter, 41))

      assert Summary.bab_terms(ruleset, stats) == [
               %{label: "Fighter 20 из 41 (полный)", value: "20"},
               %{label: "эпик", value: "+11"}
             ]

      assert sum_terms(Summary.bab_terms(ruleset, stats)) == stats.base_attack
    end

    # 🔴 Тот самый билд, ради которого задача заведена: BAB 28, а вклад вора —
    # ноль, и его строка обязана стоять в разборе, а не пропасть.
    test "класс, чьи уровни не в счёт, назван нулём, а не выброшен", %{ruleset: ruleset} do
      stats =
        compute(
          ruleset,
          List.duplicate(:fighter, 10) ++
            List.duplicate(:cleric, 15) ++ List.duplicate(:rogue, 16)
        )

      assert stats.base_attack == 28

      assert Summary.bab_terms(ruleset, stats) == [
               %{label: "Fighter 10 (полный)", value: "10"},
               # ⚠️ «10 из 15», а не «15»: пять уровней клирика в BAB не пошли.
               %{label: "Cleric 10 из 15 (средний)", value: "7"},
               %{label: "Rogue 0 из 16 (средний)", value: "0"},
               %{label: "эпик", value: "+11"}
             ]

      assert sum_terms(Summary.bab_terms(ruleset, stats)) == stats.base_attack
    end

    # ⚠️ Ни одного множителя, хотя идея Dan звучала как `0.75 × cleric × 15`:
    # `0.75 × 15 = 11.25`, а вклад клирика — 11. Прогрессия названа словом.
    test "прогрессия — слово, а не коэффициент", %{ruleset: ruleset} do
      labels =
        ruleset
        |> Summary.bab_terms(compute(ruleset, List.duplicate(:cleric, 15)))
        |> Enum.map(& &1.label)

      assert labels == ["Cleric 15 (средний)"]
      refute Enum.any?(labels, &(&1 =~ "0.75"))
      refute Enum.any?(labels, &(&1 =~ "3/4"))
      refute Enum.any?(labels, &(&1 =~ "×"))
    end

    test "эпик молчит на нуле, но печатается, как только появился", %{ruleset: ruleset} do
      assert Summary.bab_terms(ruleset, compute(ruleset, List.duplicate(:fighter, 20))) == [
               %{label: "Fighter 20 (полный)", value: "20"}
             ]

      # Положительный контроль: 21-й уровень нечётный, +1 к атаке — и терм есть.
      assert Summary.bab_terms(ruleset, compute(ruleset, List.duplicate(:fighter, 21))) == [
               %{label: "Fighter 20 из 21 (полный)", value: "20"},
               %{label: "эпик", value: "+1"}
             ]
    end

    # Сиальский монах — `medium → high` в данных. Разбор обязан объяснять число
    # по тому ruleset'у, по которому оно посчитано, а не по ванильной таблице.
    test "сиальский монах подписан «полный», ванильный — «средний»", %{ruleset: ruleset} do
      vanilla = Data.ruleset!("vanilla")
      levels = List.duplicate(:monk, 20)

      assert Summary.bab_terms(ruleset, compute(ruleset, levels)) == [
               %{label: "Monk 20 (полный)", value: "20"}
             ]

      assert Summary.bab_terms(vanilla, compute(vanilla, levels)) == [
               %{label: "Monk 20 (средний)", value: "15"}
             ]
    end

    # `subtotal: nil` у класса, чью строку таблицы прочитать нечем: значение
    # печатается «?», а не молчаливым нулём — то же правило, что у `alchemy`.
    test "непрочитанная строка таблицы печатается «?», а не нулём", %{ruleset: ruleset} do
      terms = Summary.bab_terms(ruleset, compute(ruleset, List.duplicate(:weapon_master, 15)))

      assert terms == [%{label: "Weapon master 15 (полный)", value: "?"}]
    end
  end

  describe "counted_window_note/1" do
    test "правило называется словами у билда, которого оно касается", %{ruleset: ruleset} do
      note = Summary.counted_window_note(compute(ruleset, List.duplicate(:fighter, 41)))

      assert note =~ "первые 20 уровней"
      assert note =~ "порядок взятия классов"

      # Про сейвы — тоже: правило одно и то же, а у сейвов разбор задачи 3.6
      # сворачивает всю классовую прогрессию в один терм «база».
      assert note =~ "спасы"
    end

    # ⚠️ Положительный контроль к тесту выше: строка не висит всегда. До 20-го
    # уровня правило ничего не отнимает, и печатать его там значило бы шуметь.
    test "у билда внутри окна строки нет вовсе", %{ruleset: ruleset} do
      assert Summary.counted_window_note(compute(ruleset, List.duplicate(:fighter, 20))) == nil
      assert Summary.counted_window_note(compute(ruleset, [])) == nil
    end
  end

  # 🔴 Задача 3.102 (решение Dan 25.08.2026). Предложение про ПОСЧИТАННЫЙ
  # расовый бонус печаталось гэпом билда — то есть под заголовком «ядро не
  # смогло посчитать N», хотя оно ровно про то, что ядро посчитало. Здесь
  # проверяется вторая половина правки: справка нашла себе адрес.
  #
  # ⚠️ Адрес у каждой расы СВОЙ, и это и есть содержание функции: бонус
  # Светлого эльфа падает в AB (группа «атака»), Карлика — в щитовой AC
  # («живучесть»), Человека — в значение навыка Discipline, у которого своя
  # строка панели и своя карточка. Одно общее место было бы неверно для двух
  # из трёх.
  describe "racial_bonus_note/2 (задача 3.102)" do
    test "у каждого вида бонуса свой получатель", %{ruleset: ruleset} do
      for {race, group, skill} <- [
            {:half_elf, "attack", nil},
            {:gnome, "vital", nil},
            {:human, nil, :discipline}
          ] do
        note = Summary.racial_bonus_note(ruleset, armed_40(ruleset, race))

        assert %{group: ^group, skill: ^skill} = note, "#{race}"
        assert note.text =~ "бонус расы", "#{race}"
      end
    end

    # ⚠️ Текст — тот же самый, что печатался гэпом до правки, слово в слово:
    # задача двигала МЕСТО вывода, а не слова (они прошли i18n заходом 1
    # задачи 3.83). Сверяется прямым сравнением с `Labels.gap/2`, а не
    # переписыванием предложения сюда: второе написание разошлось бы с первым.
    test "текст не переписан — тот же, что у гэпа", %{ruleset: ruleset} do
      note = Summary.racial_bonus_note(ruleset, armed_40(ruleset, :half_elf))

      assert note.text ==
               Labels.gap({:assumed, {:racial_bonus_variant, :half_elf, :sagra_warrior}}, ruleset)

      # и вариант выбран составом билда, а не прибит: один уровень барда
      # отменяет группу, и справка обязана сказать другое
      mixed =
        Summary.racial_bonus_note(
          ruleset,
          compute(ruleset, List.duplicate(:fighter, 39) ++ [:bard],
            race: :half_elf,
            weapon: :club
          )
        )

      assert mixed.text =~ "посчитан базовый"
      refute mixed.text == note.text
    end

    # 🔴 Положительный контроль в обратную сторону, и он держит ГЛАВНОЕ, что
    # правка обязана была сохранить: там, где бонус НЕ посчитан, справки нет
    # вовсе — про это говорит гэп, и два голоса об одном на одном экране были
    # бы хуже одного. Три «нет»: раса без бонуса, пустые руки, уровень ниже
    # того, для которого числа названы.
    test "у непосчитанного справки нет — говорит гэп", %{ruleset: ruleset} do
      assert Summary.racial_bonus_note(ruleset, armed_40(ruleset, :elf)) == nil
      assert Summary.racial_bonus_note(ruleset, armed_40(ruleset, :halfling)) == nil

      bare = compute(ruleset, List.duplicate(:fighter, 40), race: :half_elf)
      assert Summary.racial_bonus_note(ruleset, bare) == nil
      assert {:assumed, {:racial_bonus_variant, :half_elf, nil}} in bare.gaps

      below = compute(ruleset, List.duplicate(:fighter, 39), race: :half_elf, weapon: :club)
      assert Summary.racial_bonus_note(ruleset, below) == nil
      assert {:missing_data, {:racial_bonus_level, :half_elf}} in below.gaps
    end

    # ⚠️ Виды бонуса без получателя (поглощение урона Гнома, урон Могучего
    # человека) молчат по той же причине, что и молчит гэп: калькулятор про
    # них не отвечает вовсе (CLAUDE.md §9, решение Dan 16.08.2026).
    test "вид бонуса, которого мы не считаем, справки не печатает", %{ruleset: ruleset} do
      for race <- [:dwarf, :half_orc] do
        assert Summary.racial_bonus_note(ruleset, armed_40(ruleset, race)) == nil, "#{race}"
      end
    end
  end

  describe "подпись «Атак / раунд» (задача 3.16)" do
    test "называет BAB за засчитанные уровни и то, что эпик атак не даёт", %{ruleset: ruleset} do
      caption = apr_caption(ruleset, List.duplicate(:wizard, 20) ++ List.duplicate(:fighter, 20))

      # Волшебник первым: атаки фиксируются BAB 10, а не 20 воина, взятого
      # в эпике, — и не итоговыми 20 (CLAUDE.md §3).
      assert caption == "от BAB 10 за первые 20 уровней; эпик (+10) атак не добавляет"
    end

    # ⚠️ Обе оговорки печатаются только там, где они что-то значат. Старая
    # подпись у воина 1-го уровня выдавала «от BAB 1 **на 20-м уровне**» —
    # уровень, которого у персонажа нет.
    test "у билда внутри окна ни про окно, ни про эпик не говорится", %{ruleset: ruleset} do
      assert apr_caption(ruleset, [:fighter]) == "от BAB 1"
      assert apr_caption(ruleset, List.duplicate(:fighter, 20)) == "от BAB 20"
    end

    # ⚠️ Здесь стоял сторож «ни один модификатор атак пока не применяется —
    # иначе подпись неполна»: подпись описывала ровно табличный поиск по BAB,
    # и это было честно, пока правило Тайного лучника лежало прозой. Задача
    # 3.72 его применила — сторож упал ровно так, как обещал, и его требование
    # («подпись обязана назвать второе слагаемое») выполнено ниже.
    #
    # На его место встал тест того же назначения, но с обратным знаком: терм
    # обязан быть НАЗВАН, а не просто существовать. Молчаливая разница между
    # напечатанным числом и подписью под ним читается как ошибка калькулятора.
    test "модификатор атак назван в подписи, а не растворён в числе", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 10) ++ List.duplicate(:arcane_archer, 20)
      stats = compute(ruleset, levels)
      card = Enum.find(Summary.stat_cards(ruleset, stats), &(&1.key == "apr"))

      # BAB 20 на 20-м уровне даёт 4 атаки по таблице, 20 уровней класса — ещё 2
      assert stats.attacks_per_round == 6
      assert card.value == "6"
      assert card.from =~ "от BAB 20"
      assert card.from =~ "Arcane archer +2"
    end

    # Обратная половина: билду без такого класса лишнего слова не печатается.
    test "у билда без модификаторов подпись остаётся прежней", %{ruleset: ruleset} do
      assert apr_caption(ruleset, List.duplicate(:fighter, 20)) == "от BAB 20"
    end

    # ⚠️ И сторож на ЯЗЫК подписи, а не на её сегодняшний текст: каждый
    # применимый модификатор обоих ruleset'ов обязан уметь назваться. Заведут
    # второй такой класс — тест назовёт его сам, без правки разметки.
    test "каждый модификатор обоих ruleset'ов умеет назвать себя" do
      for version <- Data.versions(),
          modifier <- Map.get(Data.ruleset!(version), :attack_modifiers, []) do
        assert match?({:class, class} when is_atom(class), modifier.source),
               """
               У модификатора атак источник не `{:class, id}`, а подпись
               «Атак / раунд» умеет называть только класс.

               #{inspect({version, modifier}, pretty: true)}
               """
      end
    end
  end

  describe "stat_cards/2 — подписи AB и HP" do
    # Тот же баг, что и в `ab_terms/2` выше, но проверен на пути, которым его
    # реально показывает экран просмотра (`Summary.stat_cards/2`, откуда
    # берёт подпись `card.from`).
    test "подпись AB называет DEX под Weapon finesse, а не зашитый STR", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          base_abilities: %{str: 10, dex: 16, con: 10, int: 10, wis: 10, cha: 10},
          feats: %{1 => %{general: :weapon_finesse}}
        )

      stats = Rules.compute(build, ruleset)

      assert caption(ruleset, stats, "ab") =~ "DEX"
      refute caption(ruleset, stats, "ab") =~ "STR"
    end

    test "подпись HP — реальные числа по классам, а не общая формула", %{
      ruleset: ruleset,
      build: build
    } do
      stats = Rules.compute(build, ruleset)

      assert caption(ruleset, stats, "hp") =~ "Fighter 10 (d10)"
      refute caption(ruleset, stats, "hp") =~ "макс. хит-дайс"
    end

    # ⚠️ Тоже на ruleset'е без хит-дайса (задача 3.37) — оговорка живая,
    # а класса, который её вызывает, в корпусе больше нет.
    test "подпись HP — честная оговорка, когда посчитать нельзя", %{ruleset: ruleset} do
      dieless =
        update_in(ruleset.classes[:red_dragon_disciple], fn class ->
          %{class | hit_die: nil, hit_die_by_class_level: nil}
        end)

      build =
        Build.new(ruleset_version: ruleset.version, levels: [:sorcerer, :red_dragon_disciple])

      stats = Rules.compute(build, dieless)

      assert caption(dieless, stats, "hp") =~ "нет хит-дайса"
    end
  end

  describe "skill_rows/3" do
    test "ранги и значение — два разных числа, и поля их не путают", %{ruleset: ruleset} do
      # Эльф, 8 рангов Spot: значение = 8 рангов + WIS +2 + расовые +2 = 12.
      # Поля раньше назывались `total` (в нём лежали ранги) и `bonus` (в нём
      # лежало всё значение) — то есть оба имени врали.
      row = row(ruleset, elf_build(ruleset), :spot)

      assert row.ranks == 8
      assert row.value == 12
      refute row.unknown?
    end

    test "разбор сходится с числом, которое он объясняет", %{ruleset: ruleset} do
      # Тот же контракт, что у разбора сейва: подпись, которая не складывается
      # в стоящее рядом значение, читается как ошибка калькулятора.
      for row <-
            Summary.skill_rows(ruleset, elf_build(ruleset), stats(ruleset, elf_build(ruleset))) do
        assert sum(row.from) == row.value, "#{row.name}: «#{row.from}» ≠ #{row.value}"
      end
    end

    test "штраф шарда — такое же слагаемое, только со знаком", %{ruleset: ruleset} do
      # Билд из четырёх классов теряет по 1 за каждый уровень непрофильного
      # класса. Слагаемое названо обобщённо: ядро отдаёт число без происхождения.
      build = four_class_build(ruleset)
      row = row(ruleset, build, :hide)

      assert row.from =~ "правила шарда -10"
      assert sum(row.from) == row.value
    end

    # ⚠️ Прибавка от фита обязана быть НАЗВАНА, а не просто прибавлена: число
    # выросло на 2, и без имени в подписи это выглядит как ошибка калькулятора.
    # Обобщённое «фиты +2» тут не годится — ядро отдаёт происхождение, в отличие
    # от штрафа шарда выше.
    test "прибавку фита подпись называет по имени", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:rogue, 3),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 14, wis: 10, cha: 10},
          skills: %{1 => %{spot: 15}},
          feats: %{1 => %{general: :alertness}}
        )

      row = row(ruleset, build, :spot)

      assert row.value == 17
      assert row.from =~ "Alertness +2"
      assert sum(row.from) == row.value
    end

    test "прибавку от класса подпись называет классом", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:rogue, 5) ++ List.duplicate(:harper_scout, 5),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 14, wis: 10, cha: 10},
          skills: %{1 => %{lore: 12}}
        )

      row = row(ruleset, build, :lore)

      assert row.value == 19
      assert row.from =~ "Harper scout +5"
      assert sum(row.from) == row.value
    end

    # 🔴 Здесь стояло «у alchemy значения нет, и разбор объясняет отсутствие»:
    # ключевую характеристику навыка не называла ни одна вики. **Замер Dan
    # 17.08.2026 (кейс P1) её назвал** — мудрость, — и кейс распался на два.
    # Этот про число: у навыка шарда разбор такой же, как у любого другого.
    test "у alchemy есть значение, и разбор называет мудрость", %{ruleset: ruleset} do
      row = row(ruleset, alchemy_build(ruleset), :alchemy)

      assert row.value == 7
      refute row.unknown?
      assert row.ranks == 5
      assert row.from =~ "5 р."
      assert row.from =~ "WIS +2"
      refute row.from =~ "характеристика не названа"
    end

    # ...а этот про «?» — печать отказа. ⚠️ Проверяется на ruleset'е, из
    # которого характеристика ВЫНУТА: ни один поставляемый ruleset её больше
    # не теряет (последним был `alchemy`), и без такой копии свойство экрана
    # перестало бы проверяться вовсе. Приём тот же, что у `export_test.exs`
    # с классом без хит-дайса; утверждения про игру здесь нет — испорчена
    # копия ruleset'а в памяти.
    test "навык без ключевой характеристики печатает «?» и говорит почему", %{ruleset: ruleset} do
      stripped = update_in(ruleset.skills[:alchemy], &%{&1 | key_ability: nil})
      row = row(stripped, alchemy_build(ruleset), :alchemy)

      assert row.value == nil
      assert row.unknown?

      # Ранги известны и показываются — отказ касается только значения.
      assert row.ranks == 5
      assert row.from =~ "5 р."
      assert row.from =~ "характеристика не названа"
    end

    # ⚠️ ТЕСТ РАЗДЕЛЁН НАДВОЕ 25.08.2026 (задача 3.92), и это не переименование.
    # Здесь стояло «фит, взятый на этот навык, назван — и значения он не меняет»
    # про `Skill focus`, у которого «прибавки нет ни в одном поле данных». Второе
    # было неверно — число лежало в разметке с дословной цитатой, — и решением
    # Dan оно теперь считается. Значит про один и тот же экран стало два разных
    # утверждения, и оба обязаны быть под тестом.
    test "посчитанный фит меняет значение и назван термом", %{ruleset: ruleset} do
      %Build{} = without = four_class_build(ruleset)

      with_feat = %Build{without | feats: %{1 => %{general: {:skill_focus, :hide}}}}

      plain = row(ruleset, without, :hide)
      marked = row(ruleset, with_feat, :hide)

      # source: fandom "Skill focus" revid 72101 — «+3 bonus on all checks».
      assert marked.value == plain.value + 3
      refute marked.from =~ "без прибавки"

      terms = Summary.skill_value_terms(ruleset, stats(ruleset, with_feat).skill_values.hide)
      assert %{label: "Skill focus", value: "+3"} in terms
    end

    # ⚠️ А непосчитанная прибавка по-прежнему называется, и число по-прежнему
    # не трогается: иначе разница с листом персонажа в игре выглядит как наша
    # арифметическая ошибка. `Favored enemy` условен — только против выбранного
    # типа существ (fandom, revid 63601).
    test "непосчитанный фит назван — и значения он не меняет", %{ruleset: ruleset} do
      %Build{} = base = four_class_build(ruleset)
      without = %Build{base | skills: %{1 => %{hide: 20, spot: 20}}}

      with_feat = %Build{
        without
        | feats: %{1 => %{general: {:favored_enemy, :goblinoid}}}
      }

      narrow = with_narrow_skill_bonus(ruleset)
      plain = row(narrow, without, :spot)
      marked = row(narrow, with_feat, :spot)

      assert marked.value == plain.value
      assert marked.from =~ "без прибавки от Favored enemy"
      refute plain.from =~ "без прибавки"

      # 🔴 А на ЖИВЫХ данных оговорки нет: `Favored enemy` её лишился задачей
      # 3.95 (решение владельца — описание фита называет и число, и условие).
      # Число при этом не сдвинулось, что и проверяется первой строкой.
      live = row(ruleset, with_feat, :spot)
      assert live.value == plain.value
      refute live.from =~ "без прибавки"
    end

    # ⚠️ Spellcraft живёт в двух местах сразу: своим значением в листе навыков
    # и прибавкой +1 ко всем сейвам за каждые 5 рангов. Это РАЗНЫЕ числа, и
    # ни одно из них не должно просочиться в другое.
    test "вклад Spellcraft в сейвы не подмешивается в значение навыка", %{ruleset: ruleset} do
      build = spellcraft_sheet(ruleset)
      stats = stats(ruleset, build)
      row = row(ruleset, build, :spellcraft)

      # 40 рангов + INT 14 (+2) — и ничего больше: прибавка к сейвам сюда
      # не приезжает, хотя посчитана и лежит рядом.
      assert row.value == 42
      assert row.from == "40 р. · INT +2"

      # Положительный контроль: прибавка к сейвам существует и названа — ровно
      # один раз и только на своей стороне.
      assert stats.skill_save_bonus == 8

      assert Enum.count(Summary.save_terms(ruleset, stats, :fort), &(&1.label == "Spellcraft")) ==
               1
    end

    # Задача 3.12: расовый бонус Сиалы к навыку подписан ИМЕНЕМ РАСЫ и стоит
    # своим слагаемым. ⚠️ Отдельно от «раса» — это два разных факта: «раса» это
    # ванильная склонность (`vanilla/races.json`), а этот — прибавка шарда
    # (`siala_41/races.json`), и у человека ванильной склонности нет вовсе.
    # Сложи их в одну строку, и «+12» стояло бы под подписью, которая обещает
    # ванильную склонность.
    test "расовый бонус Сиалы к навыку подписан именем расы", %{ruleset: ruleset} do
      build = human_discipline_40(ruleset)

      row = row(ruleset, build, :discipline)
      terms = Summary.skill_value_terms(ruleset, stats(ruleset, build).skill_values.discipline)

      # ⚠️ +18, а не +12: лестница из 40 уровней воина — это воин Сагры, и ему
      # считается свой вариант числа (решение Dan 08.08.2026).
      assert row.value == 22
      assert row.from == "4 р. · STR +0 · Человек +18"
      assert sum(row.from) == row.value

      # И тот же терм в поп-апе панели итогов — список целиком, чтобы терм
      # с нулевым значением не просочился (HANDOFF, «сумма частей равна итогу»).
      assert terms == [
               %{label: "ранги", value: "4"},
               %{label: "STR", value: "+0"},
               %{label: "Человек", value: "+18"}
             ]
    end

    # Положительный контроль: на 39-м уровне терма нет ни в подписи, ни в поп-апе.
    test "на 39-м уровне расового терма у навыка нет", %{ruleset: ruleset} do
      %Build{} = build = human_discipline_40(ruleset)
      below = %Build{build | levels: List.duplicate(:fighter, 39)}

      row = row(ruleset, below, :discipline)

      assert row.value == 4
      assert row.from == "4 р. · STR +0"
      refute row.from =~ "Человек"
    end

    # ============ прибавка к навыку с вещей (задача 3.20) ====================
    #
    # Запрос Dan 09.08.2026: «дисциплина +50 … чтобы в „Итого“ увидеть финальную
    # картинку по скиллам». ⚠️ Термы сравниваются СПИСКОМ, а не по вхождению:
    # терм со значением `+0` итог не меняет, и проверка «сумма сходится» пропустит
    # его, а игрок увидит строку «вещи +0».
    test "вписанное число стоит своим термом и в подписи, и в поп-апе", %{ruleset: ruleset} do
      %Build{} = build = human_discipline_40(ruleset)
      typed = %Build{build | gear: armed_gear(skills: %{discipline: 30})}

      row = row(ruleset, typed, :discipline)
      terms = Summary.skill_value_terms(ruleset, stats(ruleset, typed).skill_values.discipline)

      # 4 ранга + STR +0 + Человек +18 + вещи 30 = 52; потолок 50 не тронут
      # (18 + 30 = 48), поэтому строки среза нет ни в одном из двух разборов.
      assert row.value == 52
      assert row.from == "4 р. · STR +0 · Человек +18 · вещи +30"
      assert sum(row.from) == row.value

      assert terms == [
               %{label: "ранги", value: "4"},
               %{label: "STR", value: "+0"},
               %{label: "Человек", value: "+18"},
               %{label: "вещи", value: "+30"}
             ]
    end

    # 🔴 Срез потолка +50 назван СВОЕЙ строкой, а не пометкой у расового бонуса:
    # клип один на пул, и «Человек +18 (потолок)» обвинял бы расовый бонус в
    # потере, которую устроило вписанное игроком число.
    test "срез потолка +50 — отдельная строка, а не пометка у расы", %{ruleset: ruleset} do
      %Build{} = build = human_discipline_40(ruleset)
      typed = %Build{build | gear: armed_gear(skills: %{discipline: 50})}

      row = row(ruleset, typed, :discipline)
      terms = Summary.skill_value_terms(ruleset, stats(ruleset, typed).skill_values.discipline)

      # 4 + 0 + 18 + 50 − 18 = 54, и разбор обязан сойтись с этим числом
      assert row.value == 54
      assert row.from == "4 р. · STR +0 · Человек +18 · вещи +50 · сверх капа бонусов -18"
      assert sum(row.from) == row.value

      assert terms == [
               %{label: "ранги", value: "4"},
               %{label: "STR", value: "+0"},
               %{label: "Человек", value: "+18"},
               %{label: "вещи", value: "+50"},
               %{label: "сверх капа бонусов", value: "-18"}
             ]

      # ⚠️ И пометки «(потолок)» у расового терма больше нет — иначе о срезе
      # сказано дважды и в одном из двух мест не тем.
      refute row.from =~ "потолок)"
    end

    # Навык без единого ранга, но с вписанным числом, — строка законная: ровно
    # ради неё поле и заводилось. Условие живёт в ядре (`Skills.values/3`),
    # поэтому здесь проверяется, что панель его СЛУШАЕТ, а не повторяет.
    test "навык без рангов печатается, если игрок вписал прибавку", %{ruleset: ruleset} do
      %Build{} = build = human_discipline_40(ruleset)
      typed = %Build{build | skills: %{}, gear: Gear.new(skills: %{hide: 40})}

      row = row(ruleset, typed, :hide)

      assert row.ranks == 0
      assert row.value == 40
      assert row.from == "0 р. · DEX +0 · вещи +40"

      # положительный контроль: без вписанного числа строки нет вовсе
      %Build{} = bare = %Build{typed | gear: %Gear{}}
      assert row(ruleset, bare, :hide) == nil
      assert Summary.skill_rows(ruleset, bare, stats(ruleset, bare)) == []
    end

    # ============ штраф брони (задача 3.42) =================================
    #
    # 🔴 Требование задачи: штраф НАЗВАН своим термом в обоих разборах, а не
    # растворён в итоге, и разбор сходится со своим числом.
    test "штраф брони стоит своим термом и в подписи, и в поп-апе", %{ruleset: ruleset} do
      build = plated_rogue(ruleset, %{armor: :full_plate, shield: :tower})

      row = row(ruleset, build, :hide)
      terms = Summary.skill_value_terms(ruleset, stats(ruleset, build).skill_values.hide)

      # 8 рангов + DEX 14 (+2) − 18 штрафа = −8, и подпись обязана дать это же.
      assert row.value == -8
      assert row.from == "8 р. · DEX +2 · штраф брони -18"
      assert sum(row.from) == row.value

      assert terms == [
               %{label: "ранги", value: "8"},
               %{label: "DEX", value: "+2"},
               %{label: "штраф брони", value: "-18"}
             ]
    end

    # Положительный контроль: без надетого терма нет ВОВСЕ — нулевой терм не
    # печатаем, как у всех соседей. Сравнение списком, а не вхождением: строка
    # «штраф брони +0» прошла бы проверку «сумма сходится».
    test "без надетого терма штрафа нет ни в подписи, ни в поп-апе", %{ruleset: ruleset} do
      build = plated_rogue(ruleset, %{})

      row = row(ruleset, build, :hide)
      terms = Summary.skill_value_terms(ruleset, stats(ruleset, build).skill_values.hide)

      assert row.value == 10
      assert row.from == "8 р. · DEX +2"
      refute row.from =~ "брони"
      assert terms == [%{label: "ранги", value: "8"}, %{label: "DEX", value: "+2"}]
    end

    # ...и надетое БЕЗ штрафа ведёт себя так же: граница проходит по числу,
    # а не по слову «надето».
    test "кожаный доспех терма не создаёт", %{ruleset: ruleset} do
      build = plated_rogue(ruleset, %{armor: :leather})

      assert row(ruleset, build, :hide).from == "8 р. · DEX +2"
    end

    # ⚠️ Навык из исключений источника у того же билда — терма не получает.
    # Без этой строки тест зеленел бы и у кода, штрафующего все навыки подряд.
    test "Открытый замок штрафа не получает даже в латах с башенным щитом", %{ruleset: ruleset} do
      build = plated_rogue(ruleset, %{armor: :full_plate, shield: :tower})
      terms = Summary.skill_value_terms(ruleset, stats(ruleset, build).skill_values.open_lock)

      assert row(ruleset, build, :open_lock).from == "8 р. · DEX +2"
      refute Enum.any?(terms, &(&1.label == "штраф брони"))
    end
  end

  describe "ability_summary/2" do
    # Тот же контракт, что у сейва и у навыка: разбор, который не складывается
    # в стоящее рядом значение, читается как ошибка калькулятора — задача 3.2
    # переносит характеристики в панель итогов именно ради того, чтобы связь
    # «база → раса → уровни → вещи» была видна, а не жила в голове игрока.
    #
    # ⚠️ С задачи 3.13 (Dan 03.08.2026) `terms` — список `%{label:, value:}`,
    # не строка: разбор переехал в поп-ап `stat_pop/1`, и там термы стоят
    # друг под другом. Первый терм называется «база», не «покупка» — слово
    # менее корявое и не создаёт ловушки слова «старт» (на экране создания
    # персонажа так называют значение уже вместе с расой).
    test "разбор каждой характеристики сходится с её score", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          levels: List.duplicate(:fighter, 8),
          base_abilities: %{str: 14, dex: 10, con: 12, int: 10, wis: 10, cha: 8},
          ability_increases: %{4 => :str, 8 => :str},
          gear: Gear.new(abilities: %{con: 4})
        )

      for row <- Summary.ability_summary(ruleset, build) do
        assert sum_terms(row.terms) == row.score,
               "#{row.label}: «#{inspect(row.terms)}» ≠ #{row.score}"
      end
    end

    test "«база» открывает список даже без расы, уровней и вещей", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          base_abilities: %{str: 15, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      [str_row] = Enum.filter(Summary.ability_summary(ruleset, build), &(&1.id == :str))

      assert str_row.terms == [%{label: "база", value: "15"}]
      assert str_row.score == 15
      refute str_row.cap
    end

    test "раса, уровни и вещи названы поимённо, когда они есть", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          levels: List.duplicate(:fighter, 8),
          base_abilities: %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 8},
          ability_increases: %{4 => :con, 8 => :con},
          gear: Gear.new(abilities: %{con: 3})
        )

      [con_row] = Enum.filter(Summary.ability_summary(ruleset, build), &(&1.id == :con))

      assert con_row.terms == [
               %{label: "база", value: "14"},
               %{label: "раса", value: "+2"},
               %{label: "уровни", value: "+2"},
               %{label: "вещи", value: "+3"}
             ]

      assert con_row.score == 21
    end

    test "нулевые слагаемые молчат — «раса +0» не несёт информации", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          levels: [:fighter],
          base_abilities: %{str: 12, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      [str_row] = Enum.filter(Summary.ability_summary(ruleset, build), &(&1.id == :str))
      labels = Enum.map(str_row.terms, & &1.label)

      refute "раса" in labels
      refute "уровни" in labels
      refute "вещи" in labels
    end

    test "упёршийся в кап +12 показан плашкой, а не молча обрезан", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          gear: Gear.new(abilities: %{str: 30})
        )

      [str_row] = Enum.filter(Summary.ability_summary(ruleset, build), &(&1.id == :str))

      assert str_row.cap == "кап +12"

      # И разбор при этом называет уже применённые (обрезанные) +12, а не 30 —
      # иначе сумма термов разошлась бы со `score` прямо рядом с плашкой капа.
      assert %{label: "вещи", value: "+12"} in str_row.terms
      refute %{label: "вещи", value: "+30"} in str_row.terms

      # Положительный контроль: билд без вещей плашки не несёт вовсе.
      bare = Build.new(ruleset_version: ruleset.version, levels: [:fighter])
      [bare_str] = Enum.filter(Summary.ability_summary(ruleset, bare), &(&1.id == :str))
      refute bare_str.cap
    end

    test "у каждой характеристики свой оттенок из Palette", %{ruleset: ruleset} do
      build = Build.new(ruleset_version: ruleset.version, levels: [:fighter])

      hues = for row <- Summary.ability_summary(ruleset, build), do: {row.id, row.hue}

      assert {:str, 4} in hues
      assert {:con, 30} in hues

      # Шесть разных характеристик — шесть разных оттенков, ни одного nil:
      # цвет здесь несёт узор «куда качали», а не украшение.
      assert hues |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 6
    end
  end

  describe "ability_view_rows/2" do
    # Задача «Разбор характеристик на экране ПРОСМОТРА» (AGENT_QUEUE §7):
    # экран просмотра не может позволить себе поп-ап конструктора (задача
    # 3.13) — там нечего наводить и ничего не выбирается (moduledoc
    # `BuildViewLive`), так что разбор едет готовой строкой, тем же приёмом,
    # что у AB/AC/сейвов/HP этого же экрана (`terms_caption/1`, задача 3.6).
    test "у Ученика красного дракона видно, откуда взялись очки силы", %{ruleset: ruleset} do
      # Тот же факт, что и в AGENT_QUEUE §3.1: таблица РДД на 10-м уровне
      # класса даёт +8 STR (ступени 2/4/10: +2+2+4), плюс CON/INT/CHA.
      # До этой задачи экран печатал голое «12 → 20» и не объяснял ни цифры.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          levels: List.duplicate(:sorcerer, 2) ++ List.duplicate(:red_dragon_disciple, 10),
          base_abilities: %{str: 12, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      [str_row] = Enum.filter(Summary.ability_view_rows(ruleset, build), &(&1.id == :str))

      assert str_row.score == 20
      assert str_row.from == "база 12 + Dragon abilities +8"

      # Инвариант — списком термов, а не только по итогу: «сумма сходится»
      # ловит меньше половины порчи, если один из термов остаточный (HANDOFF).
      # Здесь оба терма названы поимённо строкой выше, так что это не
      # тавтологичная проверка, а такая, которую подменённое число не пройдёт.
      assert sum_terms(str_row.terms) == str_row.score
    end

    test "«база» в одиночку не печатает разбор — нечего объяснять сверх числа рядом", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          levels: [:fighter],
          base_abilities: %{str: 14, dex: 12, con: 10, int: 10, wis: 10, cha: 10}
        )

      rows = Summary.ability_view_rows(ruleset, build)

      # DEX у дварфа ничем не тронут — раса даёт только CON/CHA, уровней и
      # вещей у билда нет: единственный терм «база», и подпись под карточкой
      # пуста, а не «база 12» под уже напечатанными «12».
      [dex_row] = Enum.filter(rows, &(&1.id == :dex))
      assert dex_row.terms == [%{label: "база", value: "12"}]
      assert dex_row.from == nil

      # Положительный контроль: у CON (раса дала +2) подпись есть — иначе
      # «пусто» можно было бы заподозрить в том, что оно пусто ВСЕГДА.
      [con_row] = Enum.filter(rows, &(&1.id == :con))
      assert con_row.from == "база 10 + раса +2"
    end

    test "раса, уровни и вещи читаются той же готовой строкой, что термы поп-апа конструктора",
         %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          levels: List.duplicate(:fighter, 8),
          base_abilities: %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 8},
          ability_increases: %{4 => :con, 8 => :con},
          gear: Gear.new(abilities: %{con: 3})
        )

      [con_row] = Enum.filter(Summary.ability_view_rows(ruleset, build), &(&1.id == :con))

      assert con_row.from == "база 14 + раса +2 + уровни +2 + вещи +3"
      assert con_row.score == 21
    end
  end

  describe "guide_rows/2" do
    # HANDOFF §B.1 / волна 6: раньше `guide_feats/3` отдавал в строке гида
    # только готовое имя — сопоставить «слот потрачен зря» можно было бы
    # только по строке `name`, а не по атому id, то самое «работает по
    # случайной причине» из ловушек проекта. Этот тест — контракт для
    # `build_view_live.ex`: он зовёт `Feats.wasted_text/3` с `feat.id` из
    # каждой строки `row.feats`, и без `id` там нечего было бы передавать.
    test "у фита в гиде есть id, а не только готовое имя", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          feats: %{1 => %{general: :toughness}}
        )

      [row] = Summary.guide_rows(ruleset, build)

      assert [%{id: :toughness, name: name}] = row.feats

      # Положительный контроль: имя не пропало — `id` добавлен рядом,
      # а не вместо того, что уже показывалось.
      assert name =~ "Toughness"
    end

    test "у фита с выбором id — это фит, а не пара {feat, choice}", %{ruleset: ruleset} do
      # `Build.feat_id/1` обязан развернуть пару: `wasted_text/3` дальше сам
      # вызывает `Build.feat_id/1` на своём аргументе, и если сюда попадёт
      # уже развёрнутый атом — двойного разворачивания быть не должно.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:wizard],
          feats: %{1 => %{general: {:skill_focus, :spellcraft}}}
        )

      [row] = Summary.guide_rows(ruleset, build)

      assert [%{id: :skill_focus}] = row.feats
    end

    # Задача 3.169: `class_name` — полное имя, а не `short` ещё раз. У
    # многословного класса эти две строки обязаны РАЗОЙТИСЬ (`short` —
    # инициалы, `class_name` — целиком), иначе `title` на `.cls`
    # (build_view_live.ex) не отвечал бы ни на один вопрос сверх видимого
    # текста. Оба поля — с одним и тем же guard'ом «только на run-start
    # строке» (CLAUDE.md §6: колонка называет класс только там, где он
    # сменился), поэтому проверяются рядом, а не в отдельных тестах.
    test "у строки есть class_name — полное имя, отдельное от сокращения `short`", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 2) ++ [:weapon_master]
        )

      [lvl1, lvl2, lvl3] = Summary.guide_rows(ruleset, build)

      assert lvl1.short == "Fighter"
      assert lvl1.class_name == "Fighter"

      # Не run-start — оба поля молчат, а не повторяют прошлую строку.
      assert lvl2.short == nil
      assert lvl2.class_name == nil

      assert lvl3.short == "WM"
      assert lvl3.class_name == "Weapon master"
      assert lvl3.class_name != lvl3.short
    end

    # Задача 3.170: волшебник, оставшийся универсалом (`class_choice(build,
    # :wizard) == []`) — уже легальный и завершённый финал
    # (`ClassChoices.complete?/3`), а раньше `row.domains` для него был `nil`,
    # неотличимый от «билд не закрыт». Теперь строка называет то же слово,
    # что печатает сам клиент игры (`General`, скриншот Dan 02.09.2026).
    test "волшебник без выбранной школы — гид называет её General, не молчит", %{
      ruleset: ruleset
    } do
      build = Build.new(ruleset_version: ruleset.version, levels: [:wizard])

      [row] = Summary.guide_rows(ruleset, build)

      assert row.domains == %{label: "Школа магии", names: ["General"]}
    end

    # Положительный контроль: выбранная школа по-прежнему называется собой,
    # а не General — «General» это слово ПУСТОГО выбора, а не Волшебника
    # вообще.
    test "волшебник с выбранной школой — гид называет школу, а не General", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:wizard],
          class_choices: %{wizard: [:evocation]}
        )

      [row] = Summary.guide_rows(ruleset, build)

      assert row.domains == %{label: "Школа магии", names: ["Evocation"]}
    end

    # И клирик — положительный контроль на весь механизм: его выбор
    # ОБЯЗАТЕЛЕН, `no_selection_name` для него не заполняется
    # (`Loader.Classes.build_class_choice_no_selection/2` роняет сборку,
    # если данные попробуют сказать обратное), и незакрытый билд гид
    # по-прежнему пропускает молча — то же поведение, что было до 3.170.
    test "клирик без выбранных доменов — гид по-прежнему молчит", %{ruleset: ruleset} do
      build = Build.new(ruleset_version: ruleset.version, levels: [:cleric])

      [row] = Summary.guide_rows(ruleset, build)

      assert row.domains == nil
    end

    # Задача 3.176. Раньше строка гида не несла `kind` вовсе, и
    # `build_view_live.ex` красил глиф ПО ФИТУ (`ruleset.feats[id].epic?`),
    # а лестница конструктора (`Feats.slots/3`) — ПО СЛОТУ
    # (`Labels.slot_glyph/1`, CLAUDE.md §6: `✦` общий, `★` эпический, `⚔`
    # бонусный). Разница видна ровно там, где слот и фит расходятся:
    # НЕэпический фит в ЭПИЧЕСКОМ общем слоте (пул слота шире своих
    # эпических записей, `slot_delta_label/2`) получал бы `✦` по старому
    # правилу и `★` по новому, а ЛЮБОЙ фит в бонусном слоте класса красится
    # по слоту всегда, эпичен ли сам уровень бонуса или нет.
    test "kind у фита в гиде — это kind СЛОТА, а не эпичность самого фита", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          # Человек — единственная раса с расовым слотом фита
          # (`extra_feats.level == 1`), нужен для случая `:racial`.
          race: :human,
          levels: List.duplicate(:fighter, 24),
          feats: %{
            1 => %{
              # Общий слот, неэпический уровень.
              :general => :toughness,
              # Расовый слот Человека.
              :racial => :alertness,
              # Бонусный слот Fighter'а — Power attack сам не эпический,
              # а слот всё равно `:class_bonus`.
              {:class_bonus, :fighter} => :power_attack
            },
            # 21 — общий И эпический уровень разом (`general_feat_levels`
            # содержит 21, `epic.starts_at == 21`). `Iron will` сам НЕ
            # эпический — ключевой случай правки.
            21 => %{general: :iron_will},
            # 24 — тоже общий эпический уровень, и здесь же у Fighter'а
            # открыт ЕГО собственный эпический бонусный слот
            # (`epic_bonus_feat_levels` содержит 24). Одна строка гида,
            # два слота, два независимых правила: `Epic toughness` в общем
            # слоте — положительный контроль (сам эпический, слот тоже),
            # `Cleave` в бонусном слоте — снова `:class_bonus`, несмотря
            # на то, что слот на эпическом уровне.
            24 => %{:general => :epic_toughness, {:class_bonus, :fighter} => :cleave}
          }
        )

      rows_by_level = Summary.guide_rows(ruleset, build) |> Map.new(&{&1.level, &1})

      assert feat_kind(rows_by_level, 1, :toughness) == :general
      assert feat_kind(rows_by_level, 1, :alertness) == :racial
      assert feat_kind(rows_by_level, 1, :power_attack) == :class_bonus
      assert feat_kind(rows_by_level, 21, :iron_will) == :epic_general
      assert feat_kind(rows_by_level, 24, :epic_toughness) == :epic_general
      assert feat_kind(rows_by_level, 24, :cleave) == :class_bonus
    end

    # ⚠️ Тот же билд, но проверка ДРУГИМ способом — не «я знаю, что тут
    # должно быть», а прямое сравнение с тем, что уже показывает лестница
    # конструктора (`Feats.slots/3`, тот же читатель `Labels.slot_glyph/1`).
    # Это и есть «сверено с конструктором прогоном, а не глазами»: если
    # `guide_feat_kind/3` когда-нибудь разойдётся с `FeatSlots.at/3` на
    # новой форме слота, этот тест упадёт сам, без обновления списка
    # ожидаемых значений выше.
    test "прогон: глиф фита в гиде совпадает с глифом ТОГО ЖЕ фита на лестнице конструктора", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          levels: List.duplicate(:fighter, 24),
          feats: %{
            1 => %{
              :general => :toughness,
              :racial => :alertness,
              {:class_bonus, :fighter} => :power_attack
            },
            21 => %{general: :iron_will},
            24 => %{:general => :epic_toughness, {:class_bonus, :fighter} => :cleave}
          }
        )

      rows_by_level = Summary.guide_rows(ruleset, build) |> Map.new(&{&1.level, &1})

      checked =
        for level <- 1..24, feat <- Map.fetch!(rows_by_level, level).feats do
          ladder_glyph =
            ruleset
            |> Feats.slots(build, level)
            |> Enum.find(&(&1.feat && Build.feat_id(&1.feat) == feat.id))
            |> Map.fetch!(:glyph)

          assert Labels.slot_glyph(feat) == ladder_glyph,
                 "уровень #{level}, фит #{feat.id}: у гида #{inspect(Labels.slot_glyph(feat))}, у лестницы #{inspect(ladder_glyph)}"

          feat.id
        end

      # Положительный контроль: цикл выше не мог молча проверить ноль
      # фитов — иначе тест зеленел бы, ничего не сравнив. Шесть, а не пять:
      # Toughness/Alertness/Power attack на 1-м, Iron will на 21-м,
      # Epic toughness И Cleave на 24-м (два слота одной строки).
      assert length(checked) == 6
    end
  end

  defp feat_kind(rows_by_level, level, feat_id) do
    rows_by_level
    |> Map.fetch!(level)
    |> Map.fetch!(:feats)
    |> Enum.find(&(&1.id == feat_id))
    |> Map.fetch!(:kind)
  end

  defp spellcraft_sheet(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :human,
      levels: List.duplicate(:wizard, 40),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 14, wis: 10, cha: 10},
      skills: %{40 => %{spellcraft: 40}}
    )
  end

  defp stats(ruleset, build), do: Rules.compute(build, ruleset)

  # 🔴 Узкая запись разметки навыков — СИНТЕТИЧЕСКАЯ (задача 3.95, 25.08.2026).
  # Живых записей с нашим получателем в `feat_skill_bonuses.json` не осталось
  # ни одной: `trackless_step` и `stonecunning` ушли решением Dan (3.76),
  # `skill_focus` стал посчитанным (3.92), `favored_enemy` ушёл решением
  # владельца (3.95). Проверяется ПЕЧАТЬ оговорки, а не сегодняшний состав
  # данных, — фит настоящий, маршрут владения настоящий, запись выдуманная.
  defp with_narrow_skill_bonus(ruleset) do
    record = %{
      id: :favored_enemy,
      source: {:feat, :favored_enemy},
      verdict: :not_modelled,
      skills: [:spot, :listen, :taunt],
      amount: %{kind: :flat, bonus: 1},
      counted_for_classes: [],
      affects: ["skill_values"]
    }

    %{ruleset | skill_bonuses: %{ruleset.skill_bonuses | unmodelled: [record]}}
  end

  defp row(ruleset, build, id) do
    ruleset
    |> Summary.skill_rows(build, stats(ruleset, build))
    |> Enum.find(&(&1.id == id))
  end

  # Билд из одной лестницы классов, без статов и вещей — всё, что нужно разбору
  # BAB: базовая атака от характеристик не зависит вовсе (задача 3.16).
  defp compute(ruleset, levels, opts \\ []) do
    build =
      Build.new(
        ruleset_version: ruleset.version,
        levels: levels,
        race: Keyword.get(opts, :race),
        # Ранги нужны ровно одному кейсу — Человеку: навык без рангов в панель
        # не приводит собственная прибавка билда (решение Dan 16.08.2026),
        # то есть строки Discipline у него просто не было бы.
        skills: %{1 => %{discipline: 4}},
        gear: Gear.new(weapon: Keyword.get(opts, :weapon))
      )

    Rules.compute(build, ruleset)
  end

  # Сорок уровней воина с дубиной в руках: воин — класс Сагры, а дубина
  # владения не требует и своего бонуса за тип не даёт (`weapons.json`,
  # `no_proficiency_required`), то есть включает расовый бонус и не примешивает
  # к числам ничего своего.
  defp armed_40(ruleset, race),
    do: compute(ruleset, List.duplicate(:fighter, 40), race: race, weapon: :club)

  # Подпись «Атак / раунд» читается там, где её показывает экран просмотра, —
  # через `stat_cards/2`, а не из приватной функции: два места, считающие одну
  # подпись, рано или поздно разойдутся.
  defp apr_caption(ruleset, levels), do: caption(ruleset, compute(ruleset, levels), "apr")

  # Полный разбор одного сейва — с той же характеристикой, с какой его зовут
  # и панель, и экран просмотра. ⚠️ Имя нарочно НЕ `save_terms/3`: так зовётся
  # публичная функция, отдающая только ХВОСТ разбора (вещи, Spellcraft, свои
  # термы), и путать их значило бы проверять не то, что показано игроку.
  @save_abilities %{fort: :con, ref: :dex, will: :wis}

  defp save_breakdown_terms(ruleset, stats, save) do
    ability = Map.fetch!(@save_abilities, save)

    Summary.save_summary_terms(
      ruleset,
      stats,
      save,
      ability,
      Map.fetch!(stats.ability_modifiers, ability)
    )
  end

  # Имя класса со счётчиками уровней, без слова прогрессии: у BAB и у сейва слова
  # разные намеренно, а вот «Cleric 10 из 15» обязано читаться одинаково.
  defp class_prefixes(terms) do
    for %{label: label} <- terms,
        [_, prefix] <- [Regex.run(~r/^(.*?) \((?:полный|средний|низкий|высокий)\)$/, label) || []],
        do: prefix
  end

  # Все числа подписи, сложенные как есть. Знак читается из самой строки,
  # поэтому «-10» приходит отрицательным.
  defp sum(from) do
    ~r/[+-]?\d+/
    |> Regex.scan(from)
    |> Enum.map(fn [n] -> String.to_integer(n) end)
    |> Enum.sum()
  end

  # Как `sum/1`, но для `ability_summary/2`'s `terms` (задача 3.13): список
  # `%{label:, value:}`, а не строка через « · », поэтому и складывать нечего
  # регуляркой — `value` уже чистое `signed/1`-число само по себе.
  defp sum_terms(terms) do
    terms
    |> Enum.map(fn %{value: v} -> v |> Integer.parse() |> elem(0) end)
    |> Enum.sum()
  end

  # Знаковая запись числа — та же, что печатает `Summary`. Нужна там, где
  # ожидаемое значение считается из `stats`, а не написано строкой руками
  # (задача 3.22: терм характеристики равен модификатору С ВЕЩАМИ).
  defp signed(value) when value >= 0, do: "+#{value}"
  defp signed(value), do: Integer.to_string(value)

  # Вещи вместе с оружием: кейсы, которым нужны и вписанные числа, и включённый
  # расовый бонус. Без домешанного меча `Gear.new/1` затирал бы руки, бонус
  # выключался, и кейс зеленел бы по другой причине (замер Dan 15.08.2026).
  defp armed_gear(fields),
    do: Gear.new(Keyword.merge([weapon: :longsword, feats: [:siala_blade_proficiency]], fields))

  # Светлый эльф (Half-elf) на 40-м уровне: ровно тот уровень, на котором числа
  # расового бонуса Сиалы известны (`siala_41/races.json`, revid 16292).
  #
  # ⚠️ Меч в руках — условие самого бонуса (замер Dan 15.08.2026,
  # `GAME_CHECKS.md` Q1/Q4): голым его нет ни в игре, ни у нас, и без оружия
  # все кейсы про расовый терм проверяли бы отсутствующее слагаемое.
  defp half_elf_40(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :half_elf,
      levels: List.duplicate(:fighter, 40),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
      gear: Gear.new(weapon: :longsword, feats: [:siala_blade_proficiency])
    )
  end

  # Человек на 40-м с 4 рангами Discipline: +12 от расового бонуса Сиалы.
  # Меч — по той же причине, что у `half_elf_40/1` выше.
  defp human_discipline_40(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :human,
      levels: List.duplicate(:fighter, 40),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
      skills: %{1 => %{discipline: 4}},
      gear: Gear.new(weapon: :longsword, feats: [:siala_blade_proficiency])
    )
  end

  # Вор 10-го уровня с DEX 14 (+2), 8 рангами Скрытности и Открытого замка и
  # выбранным надетым. Ранги по одному на уровень — потолок уровня не мешает.
  defp plated_rogue(ruleset, worn) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:rogue, 10),
      base_abilities: %{str: 10, dex: 14, con: 10, int: 10, wis: 10, cha: 10},
      skills: for(level <- 1..8, into: %{}, do: {level, %{hide: 1, open_lock: 1}}),
      gear: Gear.new(worn: worn)
    )
  end

  # Эльф: +2 к Listen/Search/Spot (`vanilla/races.json`, Skill Affinity).
  defp elf_build(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :elf,
      levels: List.duplicate(:rogue, 10),
      base_abilities: %{str: 10, dex: 14, con: 10, int: 14, wis: 14, cha: 10},
      skills: %{1 => %{spot: 8, hide: 8}}
    )
  end

  defp four_class_build(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :human,
      levels:
        List.duplicate(:rogue, 20) ++
          List.duplicate(:shadowdancer, 10) ++
          List.duplicate(:fighter, 6) ++ List.duplicate(:wizard, 4),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 14, wis: 10, cha: 10},
      skills: %{1 => %{hide: 20}}
    )
  end

  # ⚠️ WIS 14 не для красоты: с 17.08.2026 у Алхимии есть ключевая
  # характеристика (замер Dan, кейс P1), и с десяткой модификатор был бы нулём —
  # то есть разбор «5 р. · WIS +0» зеленел бы и у реализации, которая
  # характеристику потеряла.
  defp alchemy_build(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :human,
      levels: List.duplicate(:bard, 10),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 14, wis: 14, cha: 10},
      skills: %{1 => %{alchemy: 5}}
    )
  end

  # 43 ранга Spellcraft у чистого заклинателя — как раз тот случай из §3,
  # где сейвы уезжают на восемь пунктов и игрок этого не ждёт.
  defp spellcraft_build(ruleset, gear \\ %Gear{}) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:sorcerer, 40),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 14, wis: 10, cha: 16},
      skills: Map.new(1..40, &{&1, %{spellcraft: if(&1 == 1, do: 4, else: 1)}}),
      gear: gear
    )
    |> Rules.compute(ruleset)
  end
end
