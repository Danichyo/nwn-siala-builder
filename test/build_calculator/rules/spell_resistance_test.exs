defmodule BuildCalculator.Rules.SpellResistanceTest do
  @moduledoc """
  Сопротивление заклинаниям (SR) — задача 3.45.

  До неё ядро SR не считало вовсе: билд «Мастер Монах» нёс на этом месте
  оговорку `{:not_modelled, {:feat_bonus, :improved_spell_resistance}}`, а его
  страница печатала **63**. Обе формулы лежали в репозитории с первого
  парсинга — прозой в `description` фитов.

  Источники, по которым здесь считаются ожидания — все дословно в
  `priv/rules/vanilla/feat_spell_resistance.json`:

    * `fandom:Diamond soul` (revid 54446) — «The monk gains spell resistance
      equal to their class level + 10», выдаётся на 12-м уровне монаха
      (`prereq=[[monk]] 12`, и это же стоит в `granted_feats` класса). Оттуда же
      случай без уровней монаха: «any character without monk levels will only
      gain spell resistance 10»;
    * `fandom:Improved spell resistance` (revid 66435) — «The character gains
      a +2 to spell resistance. This feat may be taken multiple times, to
      a maximum of +20», плюс «This feat stacks with *diamond soul*»;
    * `siala_41/feats.json` → `repeatable.max_takes` = 10 (Dan, 02.08.2026) —
      **другой** потолок, про число взятий, и живёт он в другом файле;
    * `siala:Крафт` (revid 20450) — пять ступеней предмета, «12 СР» … «28 СР»:
      довод оговорки про вещи;
    * решение Dan 18.08.2026 — «на Сиале ванильные правила в том что касается SR
      монаха… максимум ставим 71, чтоб тебе проще было и не надо было
      ограничивать».

  ⚠️ Самая сильная проверка этой задачи живёт **не здесь**, а в стенде
  регрессии: страница «Мастер Монах» (revid 17944) объявляет 63, и модель даёт
  63 — `test/build_calculator/reference/wiki_builds_test.exs`, тест «the page's
  spell resistance is the model's, number for number». Это единственное итоговое
  число вики, сравнимое напрямую: SR не даёт ни один предмет и ни один бафф
  из тех, что носят её билды.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear, SpellResistance}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @flat %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

  defp build(levels, fields \\ []) do
    Build.new([levels: levels, base_abilities: @flat, race: :human] ++ fields)
  end

  defp term(stats, id), do: Enum.find(stats.spell_resistance_terms, &(&1.id == id))

  defp with_takes(build, count) do
    Enum.reduce(1..count//1, build, fn nth, acc ->
      Build.put_feat(acc, 20 + nth, :general, :improved_spell_resistance)
    end)
  end

  @gear_caveat {:not_modelled, :spell_resistance_from_gear}

  describe "Diamond soul: уровень монаха + 10, с 12-го уровня класса" do
    # Таблица кейсов. Граница выдачи (11 против 12) — часть проверки: до неё
    # числа нет вовсе, а не «есть, но маленькое».
    #
    # source: fandom:Diamond soul revid 54446 — «spell resistance equal to their
    # class level + 10», выдаётся по `prereq=[[monk]] 12`.
    for {monk_levels, expected} <- [{11, 0}, {12, 22}, {13, 23}, {20, 30}, {21, 31}, {41, 51}] do
      test "монах #{monk_levels} → SR #{expected}", %{ruleset: ruleset} do
        stats = Rules.compute(build(List.duplicate(:monk, unquote(monk_levels))), ruleset)

        assert stats.spell_resistance == unquote(expected)
      end
    end

    # ⚠️ Фит НИКТО не берёт слотом — его выдаёт класс, и билд здесь вообще
    # без единого выбранного фита. Считай мы по `feats_taken/2`, число было бы
    # нулём на любом монахе.
    test "число приходит от выдачи класса, а не от взятого слота", %{ruleset: ruleset} do
      b = build(List.duplicate(:monk, 20))
      stats = Rules.compute(b, ruleset)

      assert b.feats == %{}
      assert MapSet.member?(Build.granted_feats(b, ruleset, 20), :diamond_soul)

      assert term(stats, :diamond_soul) == %{
               id: :diamond_soul,
               source: {:feat, :diamond_soul},
               spell_resistance: 30,
               takes: 1,
               capped?: false
             }
    end

    # ⚠️ Уровень КЛАССА, а не персонажа: у монаха 12 в билде на 41 уровень SR
    # тот же, что у чистого монаха 12. Двоякое прочтение прошло бы незаметно
    # на чистом монахе — различает только мультикласс (та же ловушка, что
    # у колонки AC монаха, кейс C5).
    test "считается от уровня класса, а не персонажа", %{ruleset: ruleset} do
      pure = Rules.compute(build(List.duplicate(:monk, 12)), ruleset)

      mixed =
        Rules.compute(build(List.duplicate(:monk, 12) ++ List.duplicate(:fighter, 29)), ruleset)

      assert pure.spell_resistance == 22
      assert mixed.spell_resistance == 22
      assert mixed.character_level == 41
    end

    # Билд из ЧЕТЫРЁХ разных классов на капе — лимит шарда, и уровней монаха
    # в нём ровно 12. Проверка не про арифметику, а про то, что чужие уровни
    # в формулу не попадают ни одним слагаемым.
    test "мультикласс на четыре класса: считаются только уровни монаха", %{ruleset: ruleset} do
      levels =
        List.duplicate(:monk, 12) ++
          List.duplicate(:fighter, 14) ++
          List.duplicate(:rogue, 10) ++ List.duplicate(:bard, 5)

      stats = Rules.compute(build(levels), ruleset)

      assert stats.character_level == 41
      assert map_size(stats.class_levels) == 4
      assert stats.spell_resistance == 22
    end

    # Дельта на левелапе выводится из чистого `compute` (CLAUDE.md §5), значит
    # усечённый билд обязан отвечать за свою лестницу, а не за исходную.
    test "усечённый билд считает SR по своей длине", %{ruleset: ruleset} do
      whole = build(List.duplicate(:monk, 41))

      for {level, expected} <- [{1, 0}, {11, 0}, {12, 22}, {20, 30}, {41, 51}] do
        stats = Rules.compute(Build.truncate(whole, level), ruleset)
        assert stats.spell_resistance == expected
      end
    end
  end

  describe "Improved spell resistance: +2 за взятие, потолок эффекта +20" do
    setup do
      %{monk: build(List.duplicate(:monk, 41))}
    end

    # source: fandom:Improved spell resistance revid 66435 — «+2 to spell
    # resistance. This feat may be taken multiple times, to a maximum of +20».
    for {takes, subtotal} <- [{1, 2}, {3, 6}, {9, 18}, {10, 20}] do
      test "#{takes} взятий → +#{subtotal}", %{ruleset: ruleset, monk: monk} do
        stats = Rules.compute(with_takes(monk, unquote(takes)), ruleset)

        assert term(stats, :improved_spell_resistance) == %{
                 id: :improved_spell_resistance,
                 source: {:feat, :improved_spell_resistance},
                 spell_resistance: unquote(subtotal),
                 takes: unquote(takes),
                 capped?: false
               }
      end
    end

    # Потолок стоит на ЭФФЕКТЕ и приходит со страницы Fandom; потолок числа
    # взятий (10) — отдельный факт со слов Dan и лежит в другом файле. Билд,
    # собранный мимо валидации (импорт чужой ссылки), упирается в первый.
    test "одиннадцатое взятие не поднимает число выше +20", %{ruleset: ruleset, monk: monk} do
      ten = Rules.compute(with_takes(monk, 10), ruleset)
      eleven = Rules.compute(with_takes(monk, 11), ruleset)

      refute term(ten, :improved_spell_resistance).capped?

      assert term(eleven, :improved_spell_resistance) == %{
               id: :improved_spell_resistance,
               source: {:feat, :improved_spell_resistance},
               spell_resistance: 20,
               takes: 11,
               capped?: true
             }

      assert eleven.spell_resistance == ten.spell_resistance
    end

    # ⚠️ Складывается с Diamond soul, а не заменяет его, и это ПРОЧИТАНО, а не
    # выведено: общее правило источника — «spell resistance does not stack», и
    # исключение названо отдельным предложением на странице самого фита.
    test "складывается с Diamond soul, а не заменяет", %{ruleset: ruleset, monk: monk} do
      stats = Rules.compute(with_takes(monk, 9), ruleset)

      assert term(stats, :diamond_soul).spell_resistance == 51
      assert term(stats, :improved_spell_resistance).spell_resistance == 18
      assert stats.spell_resistance == 69
    end

    # 🔴 Число Dan: «максимум ставим 71». Это АРИФМЕТИКА капа 41, а не
    # ограничитель — ядро его нигде не применяет, оно просто получается.
    # Fandom пишет «maximum possible spell resistance of 70» про ванильный
    # кап 40, и «починить» 71 на 70 по этой фразе было бы ошибкой.
    test "монах 41 с десятью взятиями даёт ровно 71", %{ruleset: ruleset, monk: monk} do
      assert Rules.compute(with_takes(monk, 10), ruleset).spell_resistance == 71
    end
  end

  describe "фит с вещи" do
    # ⚠️ Ровно то число, которое называет сам источник: «any character without
    # monk levels will only gain spell resistance 10». Отдельного правила под
    # этот случай в ядре нет — формула та же и при нуле уровней класса.
    test "объявленный Diamond soul у не-монаха даёт 10", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 20), gear: Gear.new(feats: [:diamond_soul])),
          ruleset
        )

      assert stats.spell_resistance == 10
    end

    # Взятие с вещи считается взятием ЭФФЕКТА (Dan, 09.08.2026: «Это будет +2»),
    # ровно как у `Epic toughness`.
    test "объявленный Improved spell resistance — ещё одно взятие", %{ruleset: ruleset} do
      monk = build(List.duplicate(:monk, 41), gear: Gear.new(feats: [:improved_spell_resistance]))

      assert Rules.compute(monk, ruleset).spell_resistance == 53
      assert Rules.compute(with_takes(monk, 9), ruleset).spell_resistance == 71
    end

    # 🔴 Различие H8 (замер 14.08.2026) не нарушено: потолок ВЗЯТИЙ считает
    # только слоты, потолок ЭФФЕКТА — оба источника. Десять слотов плюс вещь —
    # это одиннадцать взятий и всё те же +20.
    test "десять слотов плюс вещь — одиннадцать взятий и те же +20", %{ruleset: ruleset} do
      monk = build(List.duplicate(:monk, 41), gear: Gear.new(feats: [:improved_spell_resistance]))
      stats = Rules.compute(with_takes(monk, 10), ruleset)

      assert term(stats, :improved_spell_resistance) == %{
               id: :improved_spell_resistance,
               source: {:feat, :improved_spell_resistance},
               spell_resistance: 20,
               takes: 11,
               capped?: true
             }

      # …и потолок ВЗЯТИЙ при этом не сработал: девять слотов плюс вещь — это
      # десять взятий эффекта, но десятый СЛОТ игрок взять вправе. Обе половины
      # обязательны: одно только `:ok` не доказывает, что потолок вообще есть.
      pick = %{level: 41, slot: :general, feat: :improved_spell_resistance}

      assert Rules.validate_feat_pick(with_takes(monk, 9), pick, ruleset) == :ok

      assert Rules.validate_feat_pick(with_takes(monk, 10), pick, ruleset) ==
               {:error, [{:max_takes, :improved_spell_resistance, 10}]}
    end
  end

  describe "ноль — это ответ" do
    test "билд без обоих фитов: 0 и ни одного терма", %{ruleset: ruleset} do
      stats = Rules.compute(build(List.duplicate(:fighter, 41)), ruleset)

      assert stats.spell_resistance == 0
      assert stats.spell_resistance_terms == []
    end

    test "пустой билд тоже 0, а не nil", %{ruleset: ruleset} do
      stats = Rules.compute(Build.new(ruleset_version: ruleset.version), ruleset)

      assert stats.spell_resistance == 0
      assert stats.spell_resistance_terms == []
    end

    # ⚠️ И ноль этот не молчаливый: оговорки про вещи у такого билда тоже нет.
    # «Оговорка про вопрос, который не возникает, — шум» (тот же критерий, что
    # у `Bonuses.cap_side_gaps/5`).
    test "у билда без SR нет и оговорки про предметы", %{ruleset: ruleset} do
      stats = Rules.compute(build(List.duplicate(:fighter, 41)), ruleset)

      refute @gear_caveat in stats.gaps
    end
  end

  describe "оговорка про предметы" do
    # 🔴 Решение с доводом, а не умолчание: SR с предметов мы не считаем
    # (Dan: «SR с вещи добавлять не надо»), но у SR вещь не ПРИБАВЛЯЕТ,
    # а КОНКУРИРУЕТ — засчитывается наибольший. Крафт Сиалы доходит до 28 СР
    # при нашем 22 у монаха 12, то есть до монаха 17 включительно предмет наше
    # число перебивает. Правило игрок из остальной панели не выведет: везде,
    # кроме SR, вещь прибавляет.
    test "появляется ровно там, где мы печатаем число", %{ruleset: ruleset} do
      assert @gear_caveat in Rules.compute(build(List.duplicate(:monk, 12)), ruleset).gaps
      refute @gear_caveat in Rules.compute(build(List.duplicate(:monk, 11)), ruleset).gaps
    end

    # Разметка ванильная, и Diamond soul выдаётся на 12-м уровне монаха
    # в обоих ruleset'ах — значит и оговорка приходит на обоих.
    test "и на ванили тоже", %{vanilla: vanilla} do
      stats = Rules.compute(build(List.duplicate(:monk, 12)), vanilla)

      assert stats.spell_resistance == 22
      assert @gear_caveat in stats.gaps
    end

    # ⚠️ Ровно один раз, а не по одному на терм.
    test "одна строка, даже когда термов два", %{ruleset: ruleset} do
      stats = Rules.compute(with_takes(build(List.duplicate(:monk, 41)), 3), ruleset)

      assert Enum.count(stats.gaps, &(&1 == @gear_caveat)) == 1
    end
  end

  describe "оговорка «прибавку от фита не считаем» снята" do
    # 🔴 То, ради чего задача и делалась видимой: `Improved spell resistance`
    # повторяем, и до 3.45 каждый монашеский билд нёс рядом со своим SR
    # «прибавку от этого фита в статы не считаем». Оговорка, спорящая с числом
    # на экране, хуже отсутствующей (CLAUDE.md §6).
    test "у билда с взятиями её нет", %{ruleset: ruleset} do
      stats = Rules.compute(with_takes(build(List.duplicate(:monk, 41)), 3), ruleset)

      refute {:not_modelled, {:feat_bonus, :improved_spell_resistance}} in stats.gaps
      assert stats.spell_resistance == 57
    end

    # …и снята она ДАННЫМИ, а не кодом: утверждение «фит посчитан целиком»
    # приходит из `effect_coverage`, и `Diamond soul` отвечает так же, хотя
    # его об этом никто не спрашивает (он не повторяем).
    test "утверждение приходит из разметки", %{ruleset: ruleset} do
      assert SpellResistance.whole_effect_counted?(:improved_spell_resistance, ruleset)
      assert SpellResistance.whole_effect_counted?(:diamond_soul, ruleset)
      refute SpellResistance.whole_effect_counted?(:toughness, ruleset)
    end
  end

  describe "оба ruleset'а считают одинаково" do
    # Разметка лежит в ванильном слое, и это не случайность: Сиала SR монаха
    # не трогала — прямое слово Dan («на Сиале ванильные правила в том что
    # касается SR монаха»), а не наш вывод из молчания вики.
    test "монах 20 и монах 40 дают одно и то же на обоих", %{ruleset: ruleset, vanilla: vanilla} do
      for levels <- [20, 40] do
        b = build(List.duplicate(:monk, levels))

        assert Rules.compute(b, ruleset).spell_resistance ==
                 Rules.compute(b, vanilla).spell_resistance
      end
    end

    # ⚠️ Потолок ВЗЯТИЙ в ванили не объявлен вовсе, и билд честно несёт про это
    # гэп — но потолок ЭФФЕКТА всё равно держит: +22 не бывает.
    test "в ванили потолка взятий нет, а потолок эффекта есть", %{vanilla: vanilla} do
      stats = Rules.compute(with_takes(build(List.duplicate(:monk, 40)), 11), vanilla)

      assert {:missing_data, {:feat_max_takes, :improved_spell_resistance}} in stats.gaps
      assert term(stats, :improved_spell_resistance).spell_resistance == 20
    end
  end

  # ⚠️ Механизм отвергнутой половины разметки ЖИВ, хотя ни одной записи
  # с вердиктом `not_modelled` в файле нет: сплошная разведка нашла ровно два
  # источника SR, и оба посчитаны. Проверяется единственным способом, каким это
  # можно проверить без выдуманного игрового факта, — синтетическим ruleset'ом
  # на копии `priv/rules` (тот же приём, что у `feat_hp_bonuses_test.exs`).
  # Никакого утверждения про игру здесь нет: величина выдумана нами и помечена
  # `unclear` прямо в подставленной записи.
  test "запись not_modelled даёт гэп с именем источника" do
    root = rules_copy()
    path = Path.join(root, "vanilla/feat_spell_resistance.json")

    added = %{
      "feat" => "still_mind",
      "verdict" => "not_modelled",
      "why" => "синтетическая запись теста, не факт об игре",
      "quote" => "синтетическая запись теста, не факт об игре",
      "status" => "unclear",
      "source" => %{"wiki" => "fandom", "page" => "Still mind", "revid" => 41_248}
    }

    markup = path |> File.read!() |> Jason.decode!()
    File.write!(path, Jason.encode!(update_in(markup["bonuses"], &[added | &1])))

    ruleset = Loader.load!(root)["siala_41"]

    # Монах 3 держит `Still mind` (выдача класса) и не держит `Diamond soul` —
    # то есть оговорка есть, а числа нет: две половины механизма проверяются
    # порознь.
    monk = Rules.compute(build(List.duplicate(:monk, 3)), ruleset)

    assert SpellResistance.unmodelled(build(List.duplicate(:monk, 3)), ruleset, 3) == [
             :still_mind
           ]

    assert {:not_modelled, {:spell_resistance, :still_mind}} in monk.gaps
    assert monk.spell_resistance == 0

    # ⚠️ Половина, без которой первая ничего не доказывает: у воина этого
    # умения нет, и оговорки тоже.
    refute {:not_modelled, {:spell_resistance, :still_mind}} in Rules.compute(
             build(List.duplicate(:fighter, 3)),
             ruleset
           ).gaps
  end

  describe "загрузчик" do
    # ⚠️ Не формальность: `source_files/0` регистрирует КАТАЛОГ `vanilla`,
    # а его mtime двигается при добавлении файла, а не при правке. Ровно на этом
    # погорел `weapons.json` в задаче 3.5 — испорченный прогон переписал файл,
    # а скомпилированный ruleset продолжал отдавать старое. Вторая половина —
    # `@rules_files`: `vanilla/*.json`, которого никто не назвал, читается как
    # словарь значений для выбора, и появился бы домен `feat_spell_resistance`.
    test "файл назван поимённо и не считается словарём выбора" do
      assert "vanilla/feat_spell_resistance.json" in Loader.source_files()
      refute Map.has_key?(Data.ruleset!("siala_41").choice_domains, :feat_spell_resistance)
    end

    # Потолка на SR не объявляет ни один ruleset — значит сторона такого потолка
    # у записи есть утверждение ни о чём, и сборка обязана падать. Тот же сторож
    # и та же причина, что у `feat_hp_bonuses.json`.
    test "сторона несуществующего потолка роняет сборку" do
      root = rules_copy()
      path = Path.join(root, "vanilla/feat_spell_resistance.json")

      markup = path |> File.read!() |> Jason.decode!()

      broken =
        update_in(markup["bonuses"], fn records ->
          for record <- records do
            if record["feat"] == "diamond_soul",
              do: Map.put(record, "cap", %{"inside_cap" => true, "status" => "verified"}),
              else: record
          end
        end)

      File.write!(path, Jason.encode!(broken))

      assert_raise RuntimeError, ~r/states a `cap` side/, fn -> Loader.load!(root) end
    end

    # Форма величины, которой ядро не умеет считать, не имеет права молча дать
    # ноль: `applied` с неизвестным `kind` роняет сборку.
    test "неизвестная форма величины у applied роняет сборку" do
      root = rules_copy()
      path = Path.join(root, "vanilla/feat_spell_resistance.json")

      markup = path |> File.read!() |> Jason.decode!()

      broken =
        update_in(markup["bonuses"], fn records ->
          for record <- records do
            if record["feat"] == "diamond_soul",
              do: put_in(record, ["amount", "kind"], "по вкусу"),
              else: record
          end
        end)

      File.write!(path, Jason.encode!(broken))

      assert_raise RuntimeError, ~r/amount kind/, fn -> Loader.load!(root) end
    end
  end

  # Полная копия `priv/rules`, чтобы `load!/1` видел всё как обычно и отличался
  # только подменённый файл.
  defp rules_copy do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
