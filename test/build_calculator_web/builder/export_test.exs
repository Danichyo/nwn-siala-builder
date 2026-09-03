defmodule BuildCalculatorWeb.Builder.ExportTest do
  @moduledoc """
  The canonical text block: block order and shape, which is what other people's
  parsers depend on.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, Rules}
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.Export

  setup do
    ruleset = Data.ruleset!()

    build =
      Build.new(
        ruleset_version: ruleset.version,
        race: :dwarf,
        alignment: :lawful_good,
        base_abilities: %{str: 16, dex: 12, con: 15, int: 10, wis: 12, cha: 8},
        levels: [:fighter, :fighter, :fighter, :fighter, :dwarven_defender],
        ability_increases: %{4 => :str},
        feats: %{1 => %{:general => :toughness, {:class_bonus, :fighter} => :power_attack}},
        skills: %{1 => %{discipline: 4, spot: 2}}
      )

    %{ruleset: ruleset, build: build, stats: Rules.compute(build, ruleset)}
  end

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

  # Every `name` from `names` occurs in `line`, left to right, whatever comes
  # before each one (a glyph, nothing at all) — the format-agnostic half of
  # "export and guide agree" that both `vanilla`'s bare join and `siala_41`'s
  # glyph-prefixed items satisfy (задача 3.145).
  defp assert_names_in_order(line, names) do
    Enum.reduce(names, 0, fn name, from ->
      case :binary.match(line, name, scope: {from, byte_size(line) - from}) do
        {start, len} ->
          start + len

        :nomatch ->
          flunk("#{inspect(name)} not found in order after byte #{from} in #{inspect(line)}")
      end
    end)
  end

  test "the header names the class split and the race both ways", ctx do
    text = Export.text(ctx.build, ctx.ruleset, ctx.stats, title: "Тестовый билд")

    assert text =~ "Тестовый билд - Fighter(4), Dwarven defender(1)"
    # Races are the documented exception to English-only names (CLAUDE.md §4).
    assert text =~ "Гном (Dwarf), Lawful Good"
  end

  # ⚠️ "the blocks come in the order the guild's rules state" moved to
  # describe "vanilla — формат гильдии не меняется" below (задача 3.145):
  # `SKILL GUIDE` as its own block is a `vanilla`-only property since
  # `siala_41` merged it into `LEVELING GUIDE`'s own lines. The siala-shaped
  # equivalent lives in describe "siala_41 — гид слит в одну строку".

  test "the totals line up with the ones the panel shows", ctx do
    text = Export.text(ctx.build, ctx.ruleset, ctx.stats)

    assert text =~ "Hitpoints: #{ctx.stats.hp}"
    assert text =~ "BAB: #{ctx.stats.base_attack}"
    assert text =~ "AC (naked/mundane armor and shield): #{ctx.stats.ac_naked}/?"
  end

  # ⚠️ "the levelling guide numbers levels..." and "skills are a separate
  # SKILL GUIDE list..." moved to describe "vanilla — формат гильдии не
  # меняется" below (задача 3.145): both assert `vanilla`'s exact tail
  # format (`+1 STR, 17`, a level line with nothing but bare feat names),
  # which `siala_41` no longer prints — its own shape is asserted in
  # describe "siala_41 — гид слит в одну строку".

  test "the skill line's second number is the value, not ranks plus the ability" do
    # ⚠️ Оно и было «ранги + модификатор характеристики», и молча теряло расовые
    # склонности: у эльфа +2 к Spot. Канонический формат печатает вторым числом
    # значение навыка, и заниженное значение — это неверный лист персонажа.
    ruleset = Data.ruleset!()

    build =
      Build.new(
        ruleset_version: ruleset.version,
        race: :elf,
        base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 14, cha: 10},
        levels: [:rogue],
        skills: %{1 => %{spot: 4}}
      )

    stats = Rules.compute(build, ruleset)
    text = Export.text(build, ruleset, stats)

    # 4 ранга + 2 за WIS 14 + 2 расовых.
    assert stats.skill_values.spot.total == 8
    assert text =~ "Spot 4 (8)"
  end

  # Тот же контракт, на слагаемом, которого раньше не было вовсе: экспорт берёт
  # готовое число из ядра и не пересобирает его. Пересборка «ранги + модификатор»
  # потеряла бы прибавку фита ровно так же, как когда-то потеряла расовую.
  test "прибавка фита доезжает и до канонического блока" do
    ruleset = Data.ruleset!()

    build =
      Build.new(
        ruleset_version: ruleset.version,
        base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 14, cha: 10},
        levels: [:rogue],
        skills: %{1 => %{spot: 4}},
        feats: %{1 => %{general: :alertness}}
      )

    stats = Rules.compute(build, ruleset)

    # 4 ранга + 2 за WIS 14 + 2 от Alertness.
    assert stats.skill_values.spot.total == 8
    assert Export.text(build, ruleset, stats) =~ "Spot 4 (8)"
  end

  # ⚠️ Решение, а не недосмотр. Экран просмотра рядом со значением пишет
  # «без прибавки от Favored enemy», а канонический блок — не пишет: его читают
  # чужие парсеры, и лишний текст в строке SKILLS ломает совместимость (§3).
  # Оговорка в блоке всё равно есть — счётчиком пробелов в подвале.
  #
  # ⚠️ Носитель менялся дважды за один день. 3.92 сняла `Skill focus` — его +3
  # теперь считаются; 3.95 сняла `Favored enemy` — решением владельца, потому
  # что описание фита называет и число, и условие. Живых записей с нашим
  # получателем в разметке навыков не осталось, поэтому запись здесь
  # СИНТЕТИЧЕСКАЯ: проверяется печать строки SKILLS при неполном значении,
  # а не сегодняшний состав данных.
  test "строка SKILLS остаётся канонической, даже когда значение неполное" do
    ruleset = with_narrow_skill_bonus(Data.ruleset!())

    build =
      Build.new(
        ruleset_version: ruleset.version,
        race: :elf,
        base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 14, cha: 10},
        levels: [:ranger],
        skills: %{1 => %{spot: 4}},
        feats: %{1 => %{{:class_bonus, :ranger} => {:favored_enemy, :goblinoid}}}
      )

    stats = Rules.compute(build, ruleset)
    text = Export.text(build, ruleset, stats)

    # Значение то же самое: прибавка условная, и в безусловную строку не идёт.
    assert stats.skill_values.spot.unmodelled_feats == [:favored_enemy]
    assert Enum.any?(String.split(text, "\n"), &(&1 == "Spot 4 (8)"))
    refute text =~ "без прибавки"
  end

  test "a skill whose key ability nobody wrote down prints ?, not a confident zero" do
    # ⚠️ Раньше отказ приходил от настоящего навыка — у сиальской Алхимии
    # ключевой характеристики не называла ни одна вики. Замер Dan 17.08.2026
    # (кейс P1) её назвал, и навыков без характеристики в корпусе не осталось
    # ни одного, поэтому отказ здесь воспроизводится на ruleset'е, из которого
    # факт ВЫНУТ — ровно как у класса без хит-дайса ниже. Проверяется печать,
    # а не данные: «?» вместо числа — свойство экспорта, и без такого ruleset'а
    # оно перестало бы проверяться вовсе.
    ruleset = Data.ruleset!()
    stripped = update_in(ruleset.skills[:alchemy], &%{&1 | key_ability: nil})

    build =
      Build.new(
        ruleset_version: ruleset.version,
        levels: [:harper_scout],
        skills: %{1 => %{alchemy: 3}}
      )

    assert Export.text(build, stripped, Rules.compute(build, stripped)) =~ "Alchemy 3 (?)"

    # Положительный контроль на живых данных: тот же билд с тем же навыком
    # печатает ЧИСЛО — иначе «?» выше мог бы оказаться свойством навыка,
    # а не свойством незаполненного поля.
    assert Export.text(build, ruleset, Rules.compute(build, ruleset)) =~ "Alchemy 3 (3)"
  end

  test "a number the core refused to compute prints as ?, never as a guess", ctx do
    # ⚠️ Раньше отказ приходил от настоящего класса — у Ученика красного
    # дракона не было хит-дайса. Задача 3.37 его прочитала, и классов без
    # хит-дайса в корпусе не осталось ни одного, поэтому отказ здесь
    # воспроизводится на ruleset'е, из которого факт ВЫНУТ. Проверяется
    # печать, а не данные: «?» вместо числа — свойство экспорта, и без такого
    # ruleset'а оно перестало бы проверяться вовсе.
    ruleset = ctx.ruleset

    dieless =
      update_in(ruleset.classes[:red_dragon_disciple], fn class ->
        %{class | hit_die: nil, hit_die_by_class_level: nil}
      end)

    %Build{} = base = ctx.build
    build = %Build{base | levels: base.levels ++ [:red_dragon_disciple]}
    stats = Rules.compute(build, dieless)

    text = Export.text(build, dieless, stats)

    assert stats.hp == nil
    assert text =~ "Hitpoints: ?"
    assert text =~ "Пробелов в этом билде:"
  end

  test "an empty build still produces a block" do
    ruleset = Data.ruleset!()
    build = Build.new(ruleset_version: ruleset.version)

    text = Export.text(build, ruleset, Rules.compute(build, ruleset))

    assert text =~ "LEVELING GUIDE"
    refute text =~ "SKILL GUIDE"
  end

  # Долг §7 AGENT_QUEUE.md, «шестая пятёрка»: фиты одного уровня печатались
  # в порядке, посчитанном тремя копиями `Enum.sort_by(…, &inspect/1)` —
  # в экспорте, в гиде экрана просмотра и в `Build.feat_picks/2`. Порядок не
  # изменился, но ключ теперь один (`Build.slot_order/1`) и он не зависит
  # от Inspect-протокола.
  describe "порядок фитов одного уровня — один и тот же везде" do
    setup ctx do
      %Build{} = base = ctx.build

      three = %Build{
        base
        | feats: %{
            1 => %{
              :general => :toughness,
              :racial => :power_attack,
              {:class_bonus, :fighter} => :weapon_focus
            }
          }
      }

      %{three: three}
    end

    # Порядок назван, а не выведен: общий слот, расовый, потом классовый бонус.
    # Это внутреннее соглашение, а не правило игры — источника у него нет и быть
    # не может, поэтому оно и записано в одном месте.
    test "объявленный порядок — общий, расовый, классовый бонус", ctx do
      assert Enum.map(Build.feat_picks(ctx.three, 1), &elem(&1, 1)) ==
               [:general, :racial, {:class_bonus, :fighter}]
    end

    # ⚠️ Главная половина: экспорт и гид экрана просмотра обязаны печатать один
    # уровень одинаково. До правки это держалось на том, что три копии одной
    # сортировки случайно совпадали.
    #
    # ⚠️ Проверяется ПОРЯДОК, а не точный джойн через запятую (задача 3.145):
    # с сегодняшним (`siala_41`) ruleset'ом у каждого имени на строке есть
    # глиф (`✦ Toughness`), поэтому `line =~ "Toughness, Power attack, …"`
    # для него больше не верно — а вот то, что три имени встречаются на
    # строке в том же порядке, что и в гиде, остаётся верным для ОБОИХ
    # форматов и это ровно то свойство, ради которого тест писан. Точный
    # байт-в-байт джойн `vanilla`-формата пойман отдельно, снимком в
    # describe "vanilla — формат гильдии не меняется".
    test "экспорт и гид экрана просмотра согласны", ctx do
      guide = BuildCalculatorWeb.Builder.Summary.guide_rows(ctx.ruleset, ctx.three)
      from_guide = for f <- Enum.find(guide, &(&1.level == 1)).feats, do: f.name

      line =
        ctx.three
        |> Export.text(ctx.ruleset, Rules.compute(ctx.three, ctx.ruleset))
        |> String.split("\n")
        |> Enum.find(&String.starts_with?(&1, "01:"))

      assert from_guide == ["Toughness", "Power attack", "Weapon focus"]
      assert_names_in_order(line, from_guide)
    end

    # Положительный контроль к обоим: сортировка вообще что-то делает. Слоты
    # заданы в другом порядке — вывод обязан быть тем же.
    test "порядок записи в билд на вывод не влияет", ctx do
      %Build{} = three = ctx.three

      shuffled =
        %Build{
          three
          | feats: %{
              1 =>
                Enum.into(
                  [
                    {{:class_bonus, :fighter}, :weapon_focus},
                    {:general, :toughness},
                    {:racial, :power_attack}
                  ],
                  %{}
                )
            }
        }

      assert Enum.map(Build.feat_picks(shuffled, 1), &elem(&1, 1)) ==
               Enum.map(Build.feat_picks(three, 1), &elem(&1, 1))
    end
  end

  describe "фит с выбором" do
    test "печатается так, как его пишет сообщество", ctx do
      %Build{} = base = ctx.build

      chosen = %Build{
        base
        | feats: %{
            1 => %{
              :general => {:spell_focus, :evocation},
              {:class_bonus, :fighter} => :power_attack
            },
            3 => %{general: {:favored_enemy, :goblinoid}}
          }
      }

      text = Export.text(chosen, ctx.ruleset, Rules.compute(chosen, ctx.ruleset))

      assert text =~ "Spell focus (Evocation)"
      assert text =~ "Favored enemy (Goblinoid)"

      # Соседний фит без выбора печатается ровно как раньше — скобка
      # не дорисовывается там, где выбора не было.
      assert text =~ "Power attack"
      refute text =~ "Power attack ("
    end

    test "имя навыка берётся из справочника, а не из id", ctx do
      %Build{} = base = ctx.build
      chosen = %Build{base | feats: %{1 => %{general: {:skill_focus, :move_silently}}}}

      # ⚠️ Домен `skill` резолвится в словарь ruleset'а, у которого нет блока
      # имён, — без отдельной ветки печаталось бы `(move_silently)`.
      assert Export.text(chosen, ctx.ruleset, Rules.compute(chosen, ctx.ruleset)) =~
               "Skill focus (Move silently)"
    end
  end

  describe "билд нарушает правила (задача 1.3)" do
    # Тот же билд, что уже проверен ядром (`illegal_levels_test.exs`),
    # конструктором и экраном просмотра (`builder_live_test.exs`,
    # `build_view_live_test.exs`): Fighter 1–9 набирает все шесть фитов
    # Weapon Master плюс Intimidate 4, дальше три уровня самого класса —
    # билд легален целиком.
    #
    # ⚠️ Ruleset здесь — `"vanilla"`, а не умолчание (задача 3.145). Второй
    # тест ниже называет уровни Weapon Master пустой строкой ПОСЛЕ
    # двоеточия («10: Weapon master(1):») — это свойство `vanilla`'s
    # LEVELING GUIDE, который печатает только пики; `siala_41` с 3.145 несёт
    # на той же строке ещё и то, что класс выдал сам (`○ …`), и это не
    # регрессия, а расширение — что именно печатает `siala_41` там, где
    # что-то выдано, проверено отдельно, в describe "siala_41 — гид слит
    # в одну строку".
    defp weapon_master_export_build(ruleset) do
      Build.new(
        ruleset_version: ruleset.version,
        levels: List.duplicate(:fighter, 9) ++ List.duplicate(:weapon_master, 3),
        base_abilities: %{str: 14, dex: 14, con: 12, int: 14, wis: 10, cha: 8},
        skills: %{1 => %{intimidate: 4}},
        feats: %{
          1 => %{:general => :dodge, {:class_bonus, :fighter} => :weapon_focus},
          2 => %{{:class_bonus, :fighter} => :mobility},
          3 => %{:general => :expertise},
          4 => %{{:class_bonus, :fighter} => :spring_attack},
          6 => %{:general => :whirlwind_attack}
        }
      )
    end

    # Положительный контроль (AGENT_QUEUE, «пустые проверки»): без него тест
    # ниже мог бы зеленеть и в мире, где предупреждение печатается всегда.
    test "легальный билд не получает предупреждения в подвале" do
      ruleset = Data.ruleset!("vanilla")
      build = weapon_master_export_build(ruleset)

      text = Export.text(build, ruleset, Rules.compute(build, ruleset))

      refute text =~ "нарушением правил"
    end

    test "нарушение называется в подвале с уровнем и причиной, канонические блоки не тронуты" do
      ruleset = Data.ruleset!("vanilla")
      %Build{} = build = weapon_master_export_build(ruleset)
      without_weapon_focus = %Build{build | feats: %{build.feats | 1 => %{general: :dodge}}}
      stats = Rules.compute(without_weapon_focus, ruleset)

      text = Export.text(without_weapon_focus, ruleset, stats)

      # ⚠️ Не «на 3 уровнях» — после предлога «на» число требует предложного
      # падежа, а `Labels.level_word/1` даёт счётную форму («3 уровня»),
      # как в счётчике конструктора. Формулировка обходит предлог целиком:
      # «у билда N X» ту же форму берёт без ошибки (проверено запуском,
      # не угадано — первая версия текста была грамматически неверна).
      assert text =~ "У билда 3 уровня с нарушением правил"
      assert text =~ "открой"

      # Строго после `---`: подвал уже вне блоков, которые определяет
      # формат гильдии Epic Character Builders (CLAUDE.md §3), и лишний
      # текст обязан остаться там же, где уже живёт счётчик пробелов.
      [canonical, footer] = String.split(text, "\n---\n", parts: 2)
      refute canonical =~ "нарушением правил"
      assert footer =~ "нарушением правил"

      # ⚠️ Главная осторожность задачи: ни одна строка LEVELING GUIDE не
      # получила нового текста. Уровни 10–12 (Weapon master 1–3) ничего не
      # выбирали на этих уровнях и до, и после снятия Weapon focus — если
      # бы предупреждение просочилось в канонический блок, эти строки
      # перестали бы быть пустыми после двоеточия.
      for {level, n} <- [{10, 1}, {11, 2}, {12, 3}] do
        assert Enum.any?(
                 String.split(text, "\n"),
                 &(&1 == "#{level}: Weapon master(#{n}):")
               )
      end
    end

    # Намеренная порча (см. отчёт задачи): если бы подвал считал нарушения
    # по недедуплицированному списку `Rules.illegal_class_levels/2` вместо
    # сгруппированного по уровню `Labels.ladder_issues/2`, число в тексте
    # раздулось бы. Ломаем СРАЗУ ДВЕ причины Weapon Master (`Weapon focus`
    # и 4 ранга Intimidate — оба его СОБСТВЕННЫЕ требования, не звенья
    # чужой цепочки фитов), оставляя `Dodge`: без этой оговорки первая же
    # попытка (снять `Dodge`) заодно обрушила фиты-потомки (`Mobility`,
    # `Spring attack`, `Whirlwind attack` требуют его сами) и добавила лишние
    # уровни — что и обнаружилось прогоном, не было предусмотрено заранее.
    test "число в предупреждении — уровни, а не количество нарушенных причин" do
      ruleset = Data.ruleset!("vanilla")
      %Build{} = build = weapon_master_export_build(ruleset)

      broken = %Build{
        build
        | feats: %{build.feats | 1 => %{general: :dodge}},
          skills: %{}
      }

      raw = Rules.illegal_class_levels(broken, ruleset)

      # Две причины (Weapon focus, Intimidate) на каждом из трёх уровней
      # Weapon Master — шесть сырых записей этой формы, но ровно три
      # ЗАТРОНУТЫХ уровня. ⚠️ Считаем ИМЕННО эти две формы, а не длину
      # `raw` целиком: `vanilla` не несёт `max_classes` вовсе (это
      # сиальский `overrides.json`), поэтому каждый из 12 уровней билда
      # добавляет свой честный `{:missing_data, :max_classes}` — гэп,
      # а не нарушение, и второй позиционный аргумент задачи 3.145
      # (переключение этого describe на `"vanilla"`) не имеет права менять
      # то, что тест на самом деле хочет доказать.
      targeted =
        Enum.filter(raw, fn
          {_level, :weapon_master, {:requires_feat, :weapon_focus}} -> true
          {_level, :weapon_master, {:requires_skill_ranks, :intimidate, 4}} -> true
          _other -> false
        end)

      assert length(targeted) == 6

      text = Export.text(broken, ruleset, Rules.compute(broken, ruleset))

      assert text =~ "У билда 3 уровня с нарушением правил"
      refute text =~ "6 уровней"
    end
  end

  # Задача 3.88 (24.08.2026, решение Dan): «данную секцию с сайта уже убрал
  # бы… для пользователей я предлагаю дыры больше не показывать»; про
  # экспорт отдельно — «и с экрана просмотра и в экспорте прячем тоже».
  # Раньше фраза «Часть правил Сиалы ещё не в расчёте» печаталась в подвале
  # всегда, безусловно.
  describe "методология в подвале — под воротами data_real_count (задача 3.88)" do
    # Сегодняшний ruleset: задача 3.86 закрыла последнюю настоящую дыру
    # (`gaps_test.exs`, «today's siala_41 split is 0 real / 8 resolved /
    # 8 assumed»), значит фраза про неполноту не имеет права печататься —
    # список, который остался, целиком решения, а не дыры.
    test "с сегодняшним ruleset'ом (0 настоящих дыр) подвал не заявляет о неполноте", ctx do
      text = Export.text(ctx.build, ctx.ruleset, ctx.stats)
      [_canonical, footer] = String.split(text, "\n---\n", parts: 2)

      refute footer =~ "Часть правил Сиалы"
      refute footer =~ "ещё не в расчёте"

      # ⚠️ Легенда знака НЕ под воротами: `AC (naked/mundane armor and
      # shield)` печатает литеральный `/?` вместо номера брони на КАЖДОМ
      # билде (армори ещё нет), значит «?» в блоке гарантирован всегда,
      # и билд, вставленный в Discord как голый текст, читают без нашего
      # интерфейса — без легенды рядом со знаком «?» не значит ничего.
      assert footer =~ "«?» — то, что ядро считать отказалось."
      assert footer =~ "Посчитано Siala Build Calculator."
    end

    # ⚠️ Главный тест ворот в эту сторону — на СИНТЕТИЧЕСКОМ ruleset'е
    # с наведённой дырой, а не на живых данных: живые сегодня дают ноль,
    # и тест на них молча перестал бы что-либо проверять, если бы условие
    # сломалось в положение «всегда закрыто» (ровно та ловушка, которую
    # называет постановка задачи). `{:not_modelled, {:feat_change, …}}` —
    # существующая, зарегистрированная форма (`Labels.gap/2`), а не
    # придуманный тег: `Toughness` есть в любом ruleset'е, а третий элемент
    # (`what`) — открытый текст, `feat_change_what/1` эхом печатает
    # незнакомую строку в кавычках, как для «brand_new» в `labels_test.exs`.
    test "с наведённой настоящей дырой в данных подвал заявляет о неполноте", ctx do
      induced = {:not_modelled, {:feat_change, :toughness, "3.88 synthetic gap"}}
      ruleset = %{ctx.ruleset | gaps: [induced | ctx.ruleset.gaps]}

      text = Export.text(ctx.build, ruleset, ctx.stats)
      [_canonical, footer] = String.split(text, "\n---\n", parts: 2)

      assert footer =~ "Часть правил Сиалы ещё не в расчёте;"
      assert footer =~ "«?» — то, что ядро считать отказалось."
    end
  end

  # Вторая рука (задача 3.132) — канонический формат гильдии не называет для
  # неё слота, значит она едет в подвале, тем же приёмом, что предупреждение
  # о нелегальных уровнях: подвал уже стоит за пределами формата.
  describe "вторая рука в подвале (задача 3.132)" do
    defp with_off_hand(ruleset) do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :true_neutral,
          levels: List.duplicate(:fighter, 20),
          base_abilities: %{str: 18, dex: 14, con: 14, int: 10, wis: 10, cha: 10},
          gear:
            BuildCalculator.Rules.Gear.new(
              weapon: :katana,
              off_hand_weapon: :shortsword,
              feats: [:siala_blade_proficiency]
            )
        )

      {build, Rules.compute(build, ruleset)}
    end

    test "билд без второй руки не получает новой строки в подвале", ctx do
      text = Export.text(ctx.build, ctx.ruleset, ctx.stats)
      [_canonical, footer] = String.split(text, "\n---\n", parts: 2)

      refute footer =~ "Вторая рука"
    end

    test "билд со второй рукой называет её имя и AB в подвале, а не в каноническом блоке" do
      ruleset = Data.ruleset!("siala_41")
      {build, stats} = with_off_hand(ruleset)

      # Не выдуманное число — читаем то же поле, что печатает `Export`, и
      # только форматируем знак так же, как форматирует он сам.
      assert stats.off_hand.attack_bonus > 0
      off_ab = "+#{stats.off_hand.attack_bonus}"

      text = Export.text(build, ruleset, stats, title: "Test")
      [canonical, footer] = String.split(text, "\n---\n", parts: 2)

      assert footer =~
               "Вторая рука (Shortsword): AB #{off_ab}, атак #{stats.off_hand.attacks_per_round}."

      refute canonical =~ "Shortsword"
      refute canonical =~ "Вторая рука"

      # Каноническая строка «AB» по-прежнему называет ТОЛЬКО главную руку —
      # формат гильдии не трогается этой задачей.
      assert canonical =~ "AB: +#{stats.attack_bonus}"
    end
  end

  # Задача 3.145 (30.08.2026): просьба игрока была «добавить в экспорт, на
  # каком уровне какие скиллы брались» — и это уже было в блоке `SKILL
  # GUIDE` с первого коммита. Dan уточнил цель: «когда качаешься и
  # поднимаешь уровень сразу видеть все что надо взять при лвл апе», а
  # значит `vanilla` — формат гильдии Epic Character Builders, который
  # читают чужие парсеры форумов и Discord, — обязан остаться байт в байт,
  # и это описка блока: локальный `setup` фиксирует ruleset на `"vanilla"`
  # для каждого теста здесь, вместо умолчания модуля (`siala_41`).
  describe "vanilla — формат гильдии не меняется (задача 3.145)" do
    setup do
      ruleset = Data.ruleset!("vanilla")

      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          alignment: :lawful_good,
          base_abilities: %{str: 16, dex: 12, con: 15, int: 10, wis: 12, cha: 8},
          levels: [:fighter, :fighter, :fighter, :fighter, :dwarven_defender],
          ability_increases: %{4 => :str},
          feats: %{1 => %{:general => :toughness, {:class_bonus, :fighter} => :power_attack}},
          skills: %{1 => %{discipline: 4, spot: 2}}
        )

      %{ruleset: ruleset, build: build, stats: Rules.compute(build, ruleset)}
    end

    # Дословный перенос теста, который жил на умолчании модуля до 3.145 —
    # содержимое не менялось ни на символ, изменился только ruleset в setup.
    test "the blocks come in the order the guild's rules state", ctx do
      text = Export.text(ctx.build, ctx.ruleset, ctx.stats)
      lines = String.split(text, "\n")

      order = ["STR: 16 (17)", "Hitpoints:", "SKILLS", "LEVELING GUIDE", "SKILL GUIDE"]

      positions =
        Enum.map(order, fn needle ->
          Enum.find_index(lines, &String.starts_with?(&1, needle))
        end)

      refute Enum.any?(positions, &is_nil/1)
      assert positions == Enum.sort(positions)
    end

    test "the levelling guide numbers levels and lists feats and the stat bump", ctx do
      text = Export.text(ctx.build, ctx.ruleset, ctx.stats)

      assert text =~ "01: Fighter(1): "
      assert text =~ "Toughness"
      assert text =~ "Power attack"
      assert text =~ "04: Fighter(4): +1 STR, 17"
      assert text =~ "05: Dwarven defender(1):"
    end

    test "skills are a separate SKILL GUIDE list, not crammed into the level lines", ctx do
      text = Export.text(ctx.build, ctx.ruleset, ctx.stats)
      [_before, after_guide] = String.split(text, "SKILL GUIDE", parts: 2)

      assert after_guide =~ "01: Discipline +4 (4)"
      # Spot is cross-class for a Fighter, so the line says it cost double.
      assert after_guide =~ "Spot +2 (2) x2"
      # And the level line itself stays clean.
      assert Enum.any?(
               String.split(text, "\n"),
               &(&1 == "01: Fighter(1): Toughness, Power attack")
             )
    end

    # 🔴 Проверка сдачи 3.145, пункт 1 — байт в байт, а не «похоже на
    # прежнее». Снято прогоном ВНЕ этого файла (задача 3.145): `mix run` на
    # этом же билде дважды, один раз на закоммиченном `export.ex` (`git
    # stash`), один раз на дереве с правкой — `diff` пуст. Этот тест несёт
    # тот же снимок в CI, построчным списком (не сложенной в одну строку
    # простынёй): при расхождении ExUnit покажет, какая ИМЕННО строка
    # сдвинулась, а не «строки не равны».
    test "снимок: полный ванильный блок не сдвинулся ни на строку" do
      ruleset = Data.ruleset!("vanilla")

      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          alignment: :lawful_good,
          base_abilities: %{str: 16, dex: 12, con: 15, int: 10, wis: 12, cha: 8},
          levels: List.duplicate(:fighter, 9) ++ List.duplicate(:weapon_master, 3),
          ability_increases: %{4 => :str, 8 => :str},
          feats: %{
            1 => %{:general => :dodge, {:class_bonus, :fighter} => :weapon_focus},
            2 => %{{:class_bonus, :fighter} => :mobility},
            3 => %{:general => :expertise},
            4 => %{{:class_bonus, :fighter} => :spring_attack},
            6 => %{:general => :whirlwind_attack}
          },
          skills: %{1 => %{discipline: 4, spot: 2}, 2 => %{discipline: 1}}
        )

      stats = Rules.compute(build, ruleset)
      text = Export.text(build, ruleset, stats, title: "Snapshot")

      assert String.split(text, "\n") == [
               "Snapshot - Fighter(9), Weapon master(3)",
               "Dwarf (Dwarf), Lawful Good",
               "",
               "STR: 16 (18)",
               "DEX: 12",
               "CON: 17",
               "WIS: 12",
               "INT: 10",
               "CHA: 6",
               "",
               "Hitpoints: 156",
               "Skillpoints: 30",
               "Saving Throws (Fort/Ref/Will): +10/+7/+5",
               "BAB: 12",
               "AB: +16",
               "AC (naked/mundane armor and shield): 11/?",
               "Attacks per round: 3",
               "",
               "SKILLS",
               "Discipline 5 (9)",
               "Spot 2 (3)",
               "",
               "LEVELING GUIDE",
               "01: Fighter(1): Dodge, Weapon focus",
               "02: Fighter(2): Mobility",
               "03: Fighter(3): Expertise",
               "04: Fighter(4): Spring attack, +1 STR, 17",
               "05: Fighter(5):",
               "06: Fighter(6): Whirlwind attack",
               "07: Fighter(7):",
               "08: Fighter(8): +1 STR, 18",
               "09: Fighter(9):",
               "10: Weapon master(1):",
               "11: Weapon master(2):",
               "12: Weapon master(3):",
               "",
               "SKILL GUIDE",
               "01: Discipline +4 (4), Spot +2 (2) x2",
               "02: Discipline +1 (5)",
               "",
               "---",
               "Посчитано Siala Build Calculator. Часть правил Сиалы ещё не в расчёте; " <>
                 "«?» — то, что ядро считать отказалось. Пробелов в этом билде: 4. " <>
                 "⚠ У билда 8 уровней с нарушением правил — открой его в конструкторе, " <>
                 "там названы причины."
             ]
    end
  end

  # Что именно печатать на слитой строке уже решено CLAUDE.md §6 и обкатано
  # на экране просмотра (задача 3.24): экспорт лишь переносит то же самое
  # в текст, через `Summary.guide_rows/2`, а не собирает заново.
  describe "siala_41 — гид слит в одну строку (задача 3.145)" do
    test "фит, навык и выданное классом — на одной строке уровня, SKILL GUIDE больше нет", ctx do
      text = Export.text(ctx.build, ctx.ruleset, ctx.stats)
      lines = String.split(text, "\n")

      refute text =~ "SKILL GUIDE"

      level_01 = Enum.find(lines, &String.starts_with?(&1, "01: Fighter(1):"))
      # Пики — сначала, каждый со своим глифом.
      #
      # ⚠️ Задача 3.177: `Power attack` здесь взят в бонусный слот класса
      # (`{:class_bonus, :fighter}`, см. фикстуру `setup` выше) и печатается
      # `⚔︎`, а не `✦` — глиф решает СЛОТ (`Labels.slot_glyph/1`), не то,
      # эпичен ли сам фит. `Toughness` в общем слоте остаётся `✦`.
      assert level_01 =~ "✦ Toughness"
      assert level_01 =~ "⚔︎ Power attack"

      # Навыки — цена та же, что печатал старый отдельный SKILL GUIDE
      # (кросс-классовый Spot у Воина стоит x2, Discipline классовый — без
      # суффикса).
      assert level_01 =~ "▪ Discipline +4 (4)"
      refute level_01 =~ "Discipline +4 (4) x"
      assert level_01 =~ "▪ Spot +2 (2) x2"

      # Выданное классом — одной группой `○`, именами через запятую, ПОСЛЕ
      # пиков и навыков (CLAUDE.md §6: «сначала решения, потом выданное»).
      assert level_01 =~ "○ Armor proficiency (heavy), Armor proficiency (light)"

      assert_names_in_order(level_01, [
        "✦ Toughness",
        "▪ Discipline",
        "▪ Spot",
        "○ Armor proficiency"
      ])

      # Характеристика на своём уровне — глиф `▲`, число уже с прибавкой
      # (тот же вид, что в гиде экрана просмотра), без вычитаемого «+1».
      level_04 = Enum.find(lines, &String.starts_with?(&1, "04: Fighter(4):"))
      assert level_04 == "04: Fighter(4): ▲ STR 17"
    end

    # Легенда — то, чего у экрана просмотра не нужно (там есть
    # `#view-guide-legend` рядом), а у голого текста, вставленного в
    # Discord, нет ничего — задача 3.145 сама называет это единственным
    # открытым решением.
    test "легенда глифов стоит сразу под LEVELING GUIDE", ctx do
      lines = ctx.build |> Export.text(ctx.ruleset, ctx.stats) |> String.split("\n")
      heading_at = Enum.find_index(lines, &(&1 == "LEVELING GUIDE"))
      legend = Enum.at(lines, heading_at + 1)

      for glyph <- ~w(✦ ★ ⚔ ○ ▲ ▪ ◆) do
        assert legend =~ glyph, "легенда не называет #{glyph}: #{inspect(legend)}"
      end

      assert legend =~ "[N]"

      # Не голый msgid — перевод правда загружен, а не забыт (проект
      # переводится, задача 3.83/3.139).
      assert Regex.match?(~r/\p{Cyrillic}/u, legend)
    end

    test "известное заклинание печатается [круг] на строке своего уровня", ctx do
      build =
        Build.new(
          ruleset_version: ctx.ruleset.version,
          levels: [:sorcerer],
          spells: %{1 => %{{:circle, 1, 0} => :magic_missile}}
        )

      stats = Rules.compute(build, ctx.ruleset)
      text = Export.text(build, ctx.ruleset, stats)
      line = text |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "01:"))

      assert line =~ "[1] Magic missile"
    end

    test "выбор клирика (домены) печатается ◆ на строке своего уровня", ctx do
      build =
        Build.new(
          ruleset_version: ctx.ruleset.version,
          levels: List.duplicate(:fighter, 4) ++ List.duplicate(:cleric, 3),
          class_choices: %{cleric: [:air, :war]}
        )

      stats = Rules.compute(build, ctx.ruleset)
      text = Export.text(build, ctx.ruleset, stats)
      line = text |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "05:"))

      assert line =~ "◆"
      assert line =~ "Air"
      assert line =~ "War"
    end

    # Задача 3.170: волшебник, оставшийся универсалом, тоже печатается —
    # тем же `◆`, тем же словом, что видит игрок в игре (`General`). Гид
    # экрана просмотра и это место экспорта читают одну и ту же функцию
    # ядра (`Summary.guide_rows/2`), так что правка одна на оба места.
    test "волшебник-универсал (General) тоже печатается ◆ на строке своего уровня", ctx do
      build =
        Build.new(
          ruleset_version: ctx.ruleset.version,
          levels: List.duplicate(:fighter, 4) ++ [:wizard]
        )

      stats = Rules.compute(build, ctx.ruleset)
      text = Export.text(build, ctx.ruleset, stats)
      line = text |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "05:"))

      assert line =~ "◆"
      assert line =~ "General"
    end

    # Тот же контраст, что у гида экрана просмотра (CLAUDE.md §6): `★`
    # значит «эпический», `✦` не утверждает лишнего.
    test "эпический фит помечен ★, обычный ✦", ctx do
      %Build{} = base = ctx.build
      extended = %Build{base | levels: base.levels ++ List.duplicate(:fighter, 16)}
      build = Build.put_feat(extended, 21, :general, :epic_toughness)

      stats = Rules.compute(build, ctx.ruleset)
      lines = build |> Export.text(ctx.ruleset, stats) |> String.split("\n")

      epic_line = Enum.find(lines, &String.starts_with?(&1, "21:"))
      assert epic_line =~ "★ Epic toughness"
      refute epic_line =~ "✦ Epic toughness"
    end

    # Тот же контраст, что у ванильного блока выше: подвал печатается
    # ПОСЛЕ канонической части и её не трогает — свойство подвала не
    # изменилось от того, что канонический блок стал другим форматом.
    test "предупреждение о нелегальных уровнях остаётся в подвале, не в гиде" do
      ruleset = Data.ruleset!("siala_41")

      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 9) ++ List.duplicate(:weapon_master, 3),
          base_abilities: %{str: 14, dex: 14, con: 12, int: 14, wis: 10, cha: 8},
          feats: %{
            1 => %{:general => :dodge},
            2 => %{{:class_bonus, :fighter} => :mobility},
            3 => %{:general => :expertise},
            4 => %{{:class_bonus, :fighter} => :spring_attack},
            6 => %{:general => :whirlwind_attack}
          }
        )

      text = Export.text(build, ruleset, Rules.compute(build, ruleset))
      [canonical, footer] = String.split(text, "\n---\n", parts: 2)

      refute canonical =~ "нарушением правил"
      assert footer =~ "нарушением правил"
    end
  end

  # Задача 3.146 — жалоба игрока через Dan 30.08.2026, глядя на ровно этот
  # свежий гид (3.145): «скрыть фиты, получаемые автоматически… по дефолту
  # можно их спрятать». `opts[:show_granted_feats]` is `Export.text/4`'s
  # module-level default `true` (existing callers, including every test
  # above that does not pass the key, keep seeing what they always saw) —
  # this block is the caller that asks for `false`.
  describe "opts[:show_granted_feats] — переключатель автоматических фитов (задача 3.146)" do
    test "не переданный ключ — прежнее поведение, гранты на месте", ctx do
      text = Export.text(ctx.build, ctx.ruleset, ctx.stats)

      assert text =~ "○ Armor proficiency (heavy), Armor proficiency (light)"
    end

    test "false убирает глиф `○` из строк уровня целиком", ctx do
      text = Export.text(ctx.build, ctx.ruleset, ctx.stats, show_granted_feats: false)
      lines = String.split(text, "\n")

      refute text =~ "○"

      # Пики и навыки остаются на месте — скрывается только то, что класс
      # выдал сам, не то, что решил игрок.
      #
      # ⚠️ Задача 3.177: `⚔︎` у `Power attack` — тот же бонусный слот, что
      # и в описанном выше тесте, не следствие этого переключателя.
      assert "01: Fighter(1): ✦ Toughness, ⚔︎ Power attack, ▪ Discipline +4 (4), ▪ Spot +2 (2) x2" in lines
    end

    # CLAUDE.md §6: «○ автоматический» не идёт в колонку прогрессии
    # конструктора именно потому, что решением игрока не является — и ровно
    # то же свойство здесь означает, что уровень БЕЗ единого решения (весь
    # его контент — то, что класс дал сам) не исчезает, а печатается пустым
    # хвостом. Тот же приём, каким `vanilla` всегда печатал уровень без
    # взятого фита («05: Fighter(5):» в снимке выше).
    test "уровень, чьё единственное содержимое — гранты, остаётся пустым хвостом, а не исчезает",
         ctx do
      text = Export.text(ctx.build, ctx.ruleset, ctx.stats, show_granted_feats: false)
      lines = String.split(text, "\n")

      # Dwarven defender(1) не несёт ни пика, ни навыка, ни прибавки — только
      # гранты (`Armor proficiency (heavy)`, `Armor proficiency (light)`).
      assert "05: Dwarven defender(1):" in lines
    end

    test "легенда молчит про `○`, когда гранты скрыты, и называет остальные шесть глифов", ctx do
      lines =
        ctx.build
        |> Export.text(ctx.ruleset, ctx.stats, show_granted_feats: false)
        |> String.split("\n")

      heading_at = Enum.find_index(lines, &(&1 == "LEVELING GUIDE"))
      legend = Enum.at(lines, heading_at + 1)

      refute legend =~ "○", "легенда называет ○, хотя гид его не печатает: #{inspect(legend)}"

      for glyph <- ~w(✦ ★ ⚔ ▲ ▪ ◆) do
        assert legend =~ glyph, "легенда не называет #{glyph}: #{inspect(legend)}"
      end
    end

    test "vanilla игнорирует опцию — формат гильдии никогда не нёс гранты" do
      ruleset = Data.ruleset!("vanilla")

      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          alignment: :lawful_good,
          base_abilities: %{str: 16, dex: 12, con: 15, int: 10, wis: 12, cha: 8},
          levels: [:fighter, :fighter, :fighter, :fighter, :dwarven_defender],
          ability_increases: %{4 => :str},
          feats: %{1 => %{:general => :toughness, {:class_bonus, :fighter} => :power_attack}},
          skills: %{1 => %{discipline: 4, spot: 2}}
        )

      stats = Rules.compute(build, ruleset)

      shown = Export.text(build, ruleset, stats)
      hidden = Export.text(build, ruleset, stats, show_granted_feats: false)

      assert shown == hidden
    end
  end
end
