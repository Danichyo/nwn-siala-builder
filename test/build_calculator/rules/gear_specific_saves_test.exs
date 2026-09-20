defmodule BuildCalculator.Rules.GearSpecificSavesTest do
  @moduledoc """
  Раздельные спасы с экипировки — задача 3.187, часть A.

  Слово Dan 11.09.2026: «мы показываем только +universal, т.е. увеличение сразу
  всех трех, а на экипировке еще есть спасброски отдельные, например
  +fortitude, +reflex, +will. Предлагаю в экипировку ввести помимо universal
  еще раздельные спас броски, **но общее правило то же — +20 — это кап**».

  🔴 **Последняя фраза прочитана как «в кап +20 у сейва входит всё вещевое
  вместе», и это чтение ПОДТВЕРЖДЕНО ПЕЧАТЬЮ ДВИЖКА.** У Хнюпиуса
  (`test/fixtures/game_logs_plus/hnyupius.log`) надето 16 universal и 12
  к Стойкости — 28 при потолке 20, — и игра печатает Стойкость **59**: ровно
  столько даёт модель с ОДНИМ клипом, тогда как чтение «у каждого поля свой
  +20» дало бы 67. Сквозная сверка живёт в
  `BuildCalculatorWeb.Builder.GearImportEngineTest`; здесь — та же арифметика
  на синтетических билдах, где каждое слагаемое видно по отдельности.

  ⚠️ Два клипа по +20 — ровно та ошибка «по половинке», из-за которой билд
  однажды носил +40 на сейве (CLAUDE.md §9).
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  defp fighter(gear), do: Build.new(levels: List.duplicate(:fighter, 20), gear: gear)

  describe "прибавка к одному сейву" do
    test "universal идёт во все три, раздельная — только в свой", %{ruleset: ruleset} do
      gear = %Gear{saves: 5, saves_specific: %{fort: 12}}
      stats = Rules.compute(fighter(gear), ruleset)

      assert stats.save_bonus == %{fort: 17, ref: 5, will: 5}
      assert stats.gear_save_bonuses == %{fort: 17, ref: 5, will: 5}

      # ⚠️ Прежнее поле не сменило смысла: это по-прежнему «сколько игрок
      # вписал в поле „все три“», и разбор обязан читать мапу выше.
      assert stats.gear_save_bonus == 5
    end

    test "число на экране двигается ровно на эту прибавку", %{ruleset: ruleset} do
      naked = Rules.compute(fighter(%Gear{}), ruleset)
      geared = Rules.compute(fighter(%Gear{saves_specific: %{will: 4}}), ruleset)

      assert geared.will - naked.will == 4
      assert geared.fort == naked.fort
      assert geared.ref == naked.ref
    end

    test "штраф проходит насквозь, как и у universal", %{ruleset: ruleset} do
      stats = Rules.compute(fighter(%Gear{saves_specific: %{ref: -3}}), ruleset)

      assert stats.save_bonus.ref == -3
    end
  end

  describe "потолок один на сейв" do
    # 🔴 Главное число задачи: 15 + 10 = 25 просят, 20 дают, и клип ОДИН.
    # Два клипа по +20 (у поля universal свой, у раздельного свой) дали бы
    # 15 + 10 = 25 — ровно та ошибка, ради которой потолок и заведён.
    test "universal и раздельная режутся вместе, а не по половинке", %{ruleset: ruleset} do
      gear = %Gear{saves: 15, saves_specific: %{fort: 10}}
      stats = Rules.compute(fighter(gear), ruleset)

      assert Gear.save_bonus(gear, :fort) == 25
      assert stats.save_bonus == %{fort: 20, ref: 15, will: 15}
      assert stats.save_cap_clipped.fort == -5
      assert stats.save_cap_clipped.ref == 0
      assert :fort_save in stats.capped
      refute :ref_save in stats.capped
      refute :will_save in stats.capped
    end

    # Тот же потолок продолжает покрывать Spellcraft: три источника, один клип.
    #
    # ⚠️ **ЗДЕСЬ СТОЯЛО `%{fort: 20, ref: 13, will: 13}`** — до задачи 3.197,
    # пока прибавка от рангов лежала в самом сейве. С замера `AQ1` в листе
    # остаются одни вещи (Стойкость 25 → 20 по потолку, остальные по 5),
    # а прибавка стоит рядом: к Стойкости она не добавляет ничего (там уже
    # потолок), к Реакции и Воле — все восемь. Клип по-прежнему ОДИН на сейв,
    # и именно это здесь и видно — по разным ответам в разных сейвах.
    test "Spellcraft под тем же потолком", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:wizard, 20),
          skills: %{20 => %{spellcraft: 40}},
          gear: %Gear{saves: 5, saves_specific: %{fort: 20}}
        )

      stats = Rules.compute(build, ruleset)

      assert stats.skill_save_bonus == 8
      assert stats.save_bonus == %{fort: 20, ref: 5, will: 5}
      assert stats.conditional_save_bonus == %{fort: 0, ref: 8, will: 8}
    end
  end

  describe "что раздельные спасы НЕ делают" do
    # «Голым» значит «без вещей вообще» — второй проход по билду с пустым
    # блоком, а не вычитание (задача S2).
    test "в «голый» сейв не попадают", %{ruleset: ruleset} do
      stats = Rules.compute(fighter(%Gear{saves: 5, saves_specific: %{fort: 12}}), ruleset)

      assert stats.saves_naked.fort == stats.fort - 17
    end

    # Замер S1/S2 (Dan 16.08.2026): «вещи на спасы также не откроют фит».
    # Раздельная прибавка — та же вещь, и другого ответа у неё быть не может.
    test "требование фита по сейву не выполняют", %{ruleset: ruleset} do
      gear = %Gear{saves_specific: %{fort: 20}}
      stats = Rules.compute(fighter(gear), ruleset)

      # Эффект есть…
      assert stats.fort == stats.saves_naked.fort + 20
      # …а требование его не видит.
      assert stats.saves_for_prereqs.fort == stats.saves_naked.fort
    end
  end

  describe "совместимость" do
    # Всякая уже расшаренная ссылка открывается билдом без этого поля, и ни
    # одно его число не имеет права сдвинуться.
    test "билд без раздельных спасов считается ровно как раньше", %{ruleset: ruleset} do
      old = Rules.compute(fighter(%Gear{saves: 7}), ruleset)
      same = Rules.compute(fighter(%Gear{saves: 7, saves_specific: %{}}), ruleset)

      assert Map.from_struct(old) == Map.from_struct(same)
      assert old.save_bonus == %{fort: 7, ref: 7, will: 7}
      assert old.gear_save_bonuses == %{fort: 7, ref: 7, will: 7}
    end

    # Нули — то же самое, что пустая мапа: «вписал и стёр» и «не вписывал»
    # у всех полей этой структуры один ответ.
    test "нули ничего не двигают", %{ruleset: ruleset} do
      zeros = %Gear{saves_specific: %{fort: 0, ref: 0, will: 0}}

      assert Rules.compute(fighter(zeros), ruleset).save_bonus == %{fort: 0, ref: 0, will: 0}
      refute Gear.any?(zeros)
    end

    # А непустая прибавка — это ввод игрока, и блок «Вещи» обязан считать себя
    # заполненным: иначе «голым» и «в экипировке» напечатали бы одно число.
    test "раздельная прибавка делает блок «Вещи» непустым" do
      assert Gear.any?(%Gear{saves_specific: %{will: 2}})
    end
  end
end
