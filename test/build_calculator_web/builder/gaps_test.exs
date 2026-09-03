defmodule BuildCalculatorWeb.Builder.GapsTest do
  @moduledoc """
  Задача 3.49 (18.08.2026): `ruleset.gaps` печатается тремя раздельными
  блоками — настоящие дыры, решённые расхождения источников, принятые
  допущения (`Gaps.tier/1`, разбор в moduledoc `Gaps`). Держит инварианты, из-за
  отсутствия которых баннер «38 неперенесённых правил» год считал половину
  списка не тем, чем она была: сумма трёх счётчиков обязана сходиться
  с общим, и ни одна запись не смеет провалиться сквозь классификацию тихо.

  Плюс regression на сами находки задачи: `base_ac` и формула модификатора
  характеристики перестали утверждать отсутствие источника, которого на самом
  деле нашли (Fandom, `Armor class` и `Ability modifier`), а
  `hp_uses_maximum_hit_die_rolls` / `skill_rank_caps_past_vanilla_cap` — те же
  допущения, только оказавшиеся ПОДТВЕРЖДЁННЫМИ данными Сиалы задним числом
  (`character.hit_points_roll`, `skills.rank_cap_at_41`, оба `source: user`,
  и оба были записаны с 01.08.2026 — просто их никто не читал до этой задачи).
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.{Gaps, Labels}

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp summary_for(ruleset) do
    build = Build.new(ruleset_version: ruleset.version)
    stats = Rules.compute(build, ruleset)
    Gaps.summary(ruleset, build, stats)
  end

  describe "tier/1" do
    test "sorts each of the five kinds gap_kind/1 produces" do
      assert Gaps.tier(%{kind: "Данных нет"}) == :real
      assert Gaps.tier(%{kind: "Не смоделировано"}) == :real
      assert Gaps.tier(%{kind: "Билд нарушает правила"}) == :real
      assert Gaps.tier(%{kind: "Источники спорят"}) == :resolved
      assert Gaps.tier(%{kind: "Выведено, не прочитано"}) == :resolved
      assert Gaps.tier(%{kind: "Допущения"}) == :assumed
    end

    # ⚠️ Направление ошибки — в сторону показа (CLAUDE.md §9): вид, для
    # которого `Labels.gap_kind/1` когда-нибудь вернёт что-то новое и не
    # перечисленное в `Gaps`'s tier-словарях ("Прочее" сегодня — производится
    # только заглушкой, ничем в корпусе), обязан попасть в НАСТОЯЩИЕ дыры,
    # а не незаметно осесть в тихом блоке допущений.
    test "an unrecognised kind sorts as real, not as quietly assumed" do
      assert Gaps.tier(%{kind: "Прочее"}) == :real
      assert Gaps.tier(%{kind: "что угодно новое"}) == :real
    end
  end

  describe "summary/3 — three tiers add up to the standing total" do
    test "for both rulesets, real + resolved + assumed == data_count", %{
      siala: siala,
      vanilla: vanilla
    } do
      for ruleset <- [siala, vanilla] do
        summary = summary_for(ruleset)

        assert summary.data_count == length(ruleset.gaps)

        assert summary.data_real_count + summary.data_resolved_count +
                 summary.data_assumed_count == summary.data_count

        assert summary.data_real_count == Enum.sum_by(summary.data_groups_real, & &1.total)

        assert summary.data_resolved_count ==
                 Enum.sum_by(summary.data_groups_resolved, & &1.total)

        assert summary.data_assumed_count == Enum.sum_by(summary.data_groups_assumed, & &1.total)
      end
    end

    # ⚠️ Ровно то, ради чего задача открыта: банер звал их «38 неперенесённых
    # правил», а настоящих дыр в этом числе — 20. Число посчитано прогоном
    # (`length(ruleset.gaps)` по трём tier-группам), а не переписано глазами —
    # если оно устареет, этот тест назовёт новое значение первым.
    # ⚠️ Стояло «20 real / 36 всего» — задача 3.70 (21.08.2026) закрыла
    # `{:not_modelled, :bonus_spell_slots_from_ability}`: бонусные слоты за
    # высокую характеристику каста теперь считаются, и «не считаем» про них
    # печатать больше нельзя.
    # ⚠️ 17 → 16 (21.08.2026, задача 3.72): закрыт
    # `{:not_modelled, {:class_change, :arcane_archer, "extra_attacks"}}` —
    # у Тайного лучника считаются дополнительные атаки. Двигается только
    # `real`: `resolved` и `assumed` эта правка не касается вовсе, и то, что
    # они стоят на месте, — половина утверждения.
    # ⚠️ 16 → 14 (21.08.2026, задача 3.73): закрыты
    # `{:not_modelled, {:class_change, :cleric, "bonus_feat_pool"}}` и то же
    # у Друида — эпические заклинания легли в их бонусный пул. Снова
    # двигается только `real`, и снова ровно на столько, сколько записей
    # применено: ДВЕ записи той же формы (Чемпион Торма, Рейнджер) остались
    # гэпами, потому что источник не называет у них ни уровней, ни состава
    # (GAME_CHECKS.md, U1 и U2). «Баннер просел на 4» означало бы, что
    # правка ушла шире цитаты.
    # ⚠️ 9 → 8 (22.08.2026, задача 3.78): закрыт
    # `{:not_modelled, {:skill_change, :set_trap, "class_skills_unchanged"}}` —
    # факт утверждал СОВПАДЕНИЕ с ванилью, загрузчик теперь это совпадение
    # сверяет. Снова двигается только `real`, и это важно назвать: правка
    # ничего не посчитала заново, она сняла оговорку про правило, которое
    # у игрока на экране считалось всё это время.
    # ⚠️ 8 → 7 (22.08.2026, задача 3.79): снят `{:not_modelled,
    # :cleric_domains}` — решение Dan, «домены клерика дают ему новые
    # заклинания, но выбирать их не надо, они выдаются автоматически».
    # Снова двигается только `real`, и это снова стоит назвать: правка ничего
    # не посчитала заново и ничего не отняла у игрока — выбор двух доменов
    # на месте и по-прежнему держит уровень незакрытым, ушла строка признания
    # про то, чего наш ответ не касается вовсе.
    # ⚠️ 6 → 4 (22.08.2026, задача 3.81): сняты `{:missing_data,
    # :racial_bonus_progression}` и `{:missing_data,
    # :weapon_type_bonus_progression}` — решение Dan, «прогрессию делать
    # не будем, данный пробел можно закрыть». Снова двигается только `real`,
    # и на этот раз важно назвать не только это: **баннер просел на 2, а гэпы
    # БИЛДА не тронуты ни одним**. Билд ниже 40-го по-прежнему несёт
    # `{:missing_data, {:racial_bonus_level, race}}` и
    # `{:missing_data, {:weapon_type_bonus_level, weapon}}` — это под тестом
    # в `racial_bonus_test.exs` («решение 3.81 сняло гэп корпуса и не тронуло
    # гэп билда»), и без той половины эта выглядела бы как «убрали признание
    # про непосчитанный бонус», чем она не является.
    # 🔴 3 → 1 (24.08.2026, задача 3.85): сняты обе оставшиеся записи формы
    # `bonus_feat_pool` — Чемпион Торма и Рейнджер. **Шестой род правки
    # в этом списке, и самый неприятный: гэп был ЛОЖНЫМ.** Правило про пять
    # сиальских владений в бонусном слоте приезжает со страниц самих фитов
    # («Возможность взятия фита» → `bonus_for`) и работало всё это время;
    # запись на стороне класса при этом печатала «не смоделировано». То есть
    # мы применяли правило и одновременно говорили игроку, что не применяем.
    # Замеры U1 и U2 (Dan, 24.08.2026) сняли посылку, на которой держалась
    # придержанная половина 3.73, и записи применены — гэпы ушли
    # ПОСЧИТАННЫМИ, а не замолчанными: список кандидатов бонусного слота
    # у обоих классов не сдвинулся ни на один id (`bonus_feat_pool_test.exs`,
    # «пул не сдвинулся ни на один id»).
    # 🔴 1 → 0 (24.08.2026, задача 3.86): снят `{:not_modelled,
    # :wizard_opposed_school}` — последняя запись РЕАЛЬНОГО разряда. Седьмой
    # род правки в этом списке и первый такой: гэп ушёл не решением о границе
    # ответа и не переносом механики, а тем, что мы **ответили** — цена
    # специализации волшебника считается и печатается на самом чипе школы
    # (`Rules.Spells.specialization_costs/2`).
    # ⚠️ Ноль здесь — про ЭТОТ список и ни про что больше. Дыры данных из
    # CLAUDE.md §9 и оговорки конкретного билда — другие счётчики.
    # ⚠️ Здесь стояло «`build_count` рядом остаётся ненулевым у любого живого
    # билда» — с 25.08.2026 (задача 3.102) это неверно: посчитанный расовый
    # бонус перестал быть гэпом, и минимальный сагровик 40 с оружием в руках
    # доходит до `build_count == 0`. Восемь референсных билдов вики при этом
    # несут по 1–3 (`wiki_builds_test.exs`), потому что оружия ни один из них
    # не называет. Ноль у билда — состояние законное и предусмотренное: кнопка
    # печатает «пробелов в этом билде нет» (`#gaps-toggle[data-clean]`).
    # ⚠️ На экране просмотра — с 31.08.2026 (задача 3.148) — при
    # `data_real_count == 0` И `build_count == 0` одновременно `#view-gaps`
    # не остаётся вовсе: раньше его держала на экране безусловная строка
    # («Числа ниже — база билда, без экипировки» + ссылка на «Источники»),
    # теперь у самого блока свой гейт `data_real_count > 0 or build_count >
    # 0`, и пустой рамки без единой строки текста больше не бывает.
    # ⚠️ 16 → 17 и 8 → 9 в разряде «решённых» 25.08.2026 (задача 3.104): Fandom
    # спорит сам с собой о том, требует ли Исполнение тренировки (лейбл против
    # категории), и с этой задачи спор впервые двигает ответ — читает признак
    # `Rules.Prereqs`. Разряд «настоящих» не сдвинулся и не мог: `{:conflict, …}`
    # — это «источник спорит, и вот как мы выбрали», а не дыра.
    test "today's siala_41 split is 0 real / 9 resolved / 8 assumed", %{siala: siala} do
      summary = summary_for(siala)

      assert summary.data_count == 17
      assert summary.data_real_count == 0
      assert summary.data_resolved_count == 9
      assert summary.data_assumed_count == 8
    end

    test "no group in the real tier is a resolved dispute or an accepted assumption", %{
      siala: siala
    } do
      summary = summary_for(siala)

      real_kinds = MapSet.new(summary.data_groups_real, & &1.kind)
      refute MapSet.member?(real_kinds, "Источники спорят")
      refute MapSet.member?(real_kinds, "Выведено, не прочитано")
      refute MapSet.member?(real_kinds, "Допущения")

      resolved_kinds = MapSet.new(summary.data_groups_resolved, & &1.kind)

      assert MapSet.subset?(
               resolved_kinds,
               MapSet.new(["Источники спорят", "Выведено, не прочитано"])
             )

      assert MapSet.new(summary.data_groups_assumed, & &1.kind) == MapSet.new(["Допущения"])
    end
  end

  # Задача 3.88 (24.08.2026): методология (решённые споры источников,
  # принятые допущения) переехала на `/sources` целиком, полными списками —
  # `summary/3` для сайдбар-панели по-прежнему режет каждый вид до
  # `@per_data_group` (3) примеров, а `/sources` таким ограничением места
  # не связан.
  describe "data_tiers/1 — методология без выборки, для /sources" do
    test "тот же счёт по разрядам, что у summary/3, для обоих ruleset'ов", %{
      siala: siala,
      vanilla: vanilla
    } do
      for ruleset <- [siala, vanilla] do
        summary = summary_for(ruleset)
        tiers = Gaps.data_tiers(ruleset)

        assert MapSet.new(tiers.real, & &1.kind) ==
                 MapSet.new(summary.data_groups_real, & &1.kind)

        assert MapSet.new(tiers.resolved, & &1.kind) ==
                 MapSet.new(summary.data_groups_resolved, & &1.kind)

        assert MapSet.new(tiers.assumed, & &1.kind) ==
                 MapSet.new(summary.data_groups_assumed, & &1.kind)

        assert Enum.sum_by(tiers.real, & &1.total) == summary.data_real_count
        assert Enum.sum_by(tiers.resolved, & &1.total) == summary.data_resolved_count
        assert Enum.sum_by(tiers.assumed, & &1.total) == summary.data_assumed_count
      end
    end

    # ⚠️ Ровно то, ради чего функция заведена: у «Источники спорят» total 8,
    # а сайдбар-панель показывает только 3 (`@per_data_group`). Если бы
    # `/sources` читал `summary/3`, "Pick pocket у Harper scout" мог бы
    # оказаться среди урезанных и не попасть на страницу вовсе.
    test "items не урезаны — каждая группа несёт все total записей, а не выборку", %{
      siala: siala
    } do
      tiers = Gaps.data_tiers(siala)

      for group <- tiers.resolved ++ tiers.assumed ++ tiers.real do
        assert length(group.items) == group.total,
               "#{group.kind}: items короче total (#{length(group.items)} из #{group.total})"
      end

      disputed = Enum.find(tiers.resolved, &(&1.kind == "Источники спорят"))
      assert disputed.total == 8
      assert length(disputed.items) == 8
      assert Enum.any?(disputed.items, &(&1 =~ "Pick pocket"))
    end

    # Синтетический индуцированный гэп (тот же приём, что в `export_test.exs`)
    # проверяет положительный случай ворот: сегодня `real` пуст, и без этого
    # теста «real всегда пуст» и «real считается правильно» неотличимы.
    test "наведённая настоящая дыра попадает в real, а не в другой разряд", %{siala: siala} do
      induced = {:not_modelled, {:feat_change, :toughness, "3.88 synthetic gap"}}
      ruleset = %{siala | gaps: [induced | siala.gaps]}

      tiers = Gaps.data_tiers(ruleset)

      assert tiers.real != []
      assert Enum.any?(tiers.real, fn group -> Enum.any?(group.items, &(&1 =~ "Toughness")) end)
    end
  end

  describe "base_ac and the ability-modifier formula stop lying about their source" do
    test "both cite a real Fandom page now, for either ruleset", %{siala: siala, vanilla: vanilla} do
      for ruleset <- [siala, vanilla] do
        base_ac_gap = Enum.find(ruleset.gaps, &match?({:assumed, :base_ac, _, _}, &1))

        formula_gap =
          Enum.find(ruleset.gaps, &match?({:assumed, :ability_modifier_formula, _, _}, &1))

        refute is_nil(base_ac_gap), "no base_ac gap on #{ruleset.version}"
        refute is_nil(formula_gap), "no ability_modifier_formula gap on #{ruleset.version}"

        base_ac_text = Labels.gap(base_ac_gap, ruleset)
        formula_text = Labels.gap(formula_gap, ruleset)

        refute base_ac_text =~ "страницы про это нет"
        assert base_ac_text =~ "fandom:Armor class"

        refute formula_text =~ "формулы на вики нет"
        assert formula_text =~ "fandom:Ability modifier"
      end
    end
  end

  describe "hp_uses_maximum_hit_die_rolls and skill_rank_caps_past_vanilla_cap" do
    test "siala_41 no longer carries either — its own data confirms both", %{siala: siala} do
      refute Enum.any?(siala.gaps, &match?({:assumed, :hp_uses_maximum_hit_die_rolls}, &1))
      refute Enum.any?(siala.gaps, &match?({:assumed, :skill_rank_caps_past_vanilla_cap}, &1))
    end

    # ⚠️ Ваниль не задета намеренно: `character.hit_points_roll` живёт вне
    # `@vanilla_sections` (`loader.ex`), и `skills.rank_cap_at_41` не имеет
    # смысла на ruleset'е, у которого нет кап 41 вовсе. Оба гэпа для ванили —
    # настоящие допущения, а не непрочитанные факты.
    test "vanilla still carries hp_uses_maximum_hit_die_rolls — nothing confirms it there", %{
      vanilla: vanilla
    } do
      assert {:assumed, :hp_uses_maximum_hit_die_rolls} in vanilla.gaps
      refute Enum.any?(vanilla.gaps, &match?({:assumed, :skill_rank_caps_past_vanilla_cap}, &1))
    end
  end
end
