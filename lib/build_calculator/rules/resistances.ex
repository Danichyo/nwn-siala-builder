defmodule BuildCalculator.Rules.Resistances do
  @moduledoc """
  Поглощение стихийного урона — сколько его у персонажа по каждой стихии
  и из чего оно собрано (задача 3.210).

  Просьба Dan 13.09.2026, с которой всё началось: «Есть ещё бонусы дварфа
  и топора, которые дают поглоты от элементов. Они же усиляются мини-сетами …
  плюс фит обычный и эпический, а эпический ещё стакается. Наверное могли бы
  добавить новую секцию с резистами для начала от стихийного урона, без
  физического».

  ## Формула, и почему она не сумма трёх слагаемых, а сумма двух

      резист(стихия) = фиты(стихия) + max(эффект расы/топоров, вещь)

  Три источника и **два** действия между ними, и оба названы источниками,
  а не выведены:

    * **фит СКЛАДЫВАЕТСЯ с нефитовым** — названо трижды независимо: обе
      страницы фитов («This feat does stack with — and is applied before —
      other (non-feat) sources of damage resistance») и отдельная страница
      `fandom:Damage resistance`, называющая оба фита поимённо. Сиала
      подтверждает своими словами и числом на примере: «Если у вас одет предмет
      с сопротивлением −15 к урону кислотой и так же имеется умение Epic energy
      resistance (Acid I), то общий показатель сопротивления составит −30»;
    * **эффект расы/топоров КОНКУРИРУЕТ с вещью, и побеждает наибольшее** —
      слово Dan 13.09.2026 («эффект расы и топора с вещью не складывается,
      а берётся наибольшее») и ✅ **замер `AV1` 18.09.2026**.

  ## ✅ Оба действия ИЗМЕРЕНЫ на живом персонаже, до реализации

  Кейс `AV1`, Dan 18.09.2026: «У Хнюпиуса действительно 45 от огня и 30
  от всего остального. 30 идет от расы дварфа + 7 мини-сетов, а еще 15 от фита
  epic energy resistance - fire». Хнюпиус — Гном-сагровик 40 с полуторным мечом
  (не топором!), семью кусками мини-сетов, `Energy Resistance, Fire I` на 39-м
  и `Damage Resistance (Fire) 15` / `(Cold) 15` на самом мече:

      эффект = 2·тир6 = 12  →  ×3/2 сагровику = 18  →  += floor(18·7/10) = 30
      огонь  = 15 (фит) + max(30, вещь 15) = 45
      холод  =            max(30, вещь 15) = 30

  🔴 **Замер убил ОБА конкурирующих чтения сразу.** «Эффект плюс вещь» дал бы
  60 на огне и 45 на холоде; «вещь вместо фита» дал бы 30 на огне. Сошлись
  ровно эти две операции и ровно в этом порядке.

  ⚠ Чего замер **не** покрывает, и что поэтому остаётся синтетикой в тестах:
  внутренний кап 36, удвоение топором у Гнома, бонус топоров у не-Гнома,
  `Resist energy` и его замещение эпическим, случай «вещь больше эффекта»,
  негативная и позитивная энергия по отдельности («всё остальное 30» — словами,
  стихии поимённо не перечислены).

  ## Здесь нет ни одной стихии и ни одного числа

  Семь стихий, которые эта секция показывает, — данные
  (`ruleset.resistance_energy_types`, пять из домена выбора фитов плюс
  негативная и позитивная энергия, которые фитом не выбираются, но
  поглощаются расой и топорами). Величины фитов — `ruleset.resistance_bonuses`
  (+5 у `Resist energy`; 15 за взятие при потолке 150 на Сиале, 10/100
  в ваниле). Арифметика эффекта — `ruleset.shard_bonus_scaling`
  (`Rules.RacialBonus`, `Rules.WeaponTypeBonus`, `Rules.MiniSets`). Правило
  максимума — `ruleset.resistance_stacking`.

  ## Три потолка, и ни один не является потолком другого

    * **`max_total` фита** — 150 на стихию на Сиале, 100 в ваниле, со страницы
      самого фита. Считает **сумму слотов и вещей**, как у `Epic toughness`
      (слово Dan 14.08.2026: «как максимум для УЧЁТА там всё равно будет
      только 10 раз, учитывая СУММУ того, что взяли в билде, и того, что
      набрали с вещей»). ⚠ Потолок ВЗЯТИЙ (`repeatable.max_takes`, 10) — другое
      число и другой счёт, его проверяет `Rules.FeatChoices`;
    * **внутренний кап исполнителя** — 36, принадлежит скрипту шарда
      (`sl_s_wp_set_res.nss`) и режет только эффект расы и топоров, уже после
      усиления кусками (`Rules.MiniSets`);
    * **`ruleset.stat_caps`** — поглощения не называет **ни один** ruleset,
      и загрузчик запрещает `cap` у записей этого файла разметки. То есть
      у итога общего потолка нет вовсе, и 150 + 36 = 186 — арифметика,
      а не пропущенный клип.

  ## Стихия без единого источника в мапе ОТСУТСТВУЕТ

  Не ноль. «Здесь ничего» и «вообще ничего» — разные утверждения, и вызывающий
  обязан различать их, не сравнивая с нулём (та же линия, что у
  `Rules.Bonuses.group_sum/3` и у `skill_values`, где нет строк на навыки без
  рангов). Практическое следствие: у Гнома в мапе все семь стихий, у эльфа
  с одним `Epic energy resistance (Fire)` — одна, у билда без всего — мапа
  пуста, и секцию печатать не из чего.
  """

  alias BuildCalculator.Rules.{Bonuses, Build, Gear, MiniSets}

  @markup :resistance_bonuses

  @typedoc """
  Вклад одного фита в поглощение ОДНОЙ стихии.

    * `id` / `source` — чей это вклад, для разбора и для гэпов
    * `takes` — сколько взятий ПАРЫ `{фит, стихия}` за ним стоит (слоты плюс
      вещи, `Rules.Build.feat_takes_owned/5`); `1` у неповторяемого
    * `bonus` — величина после потолка эффекта этого же фита
    * `capped?` — потолок со страницы фита сработал (150 на Сиале)
  """
  @type feat_term :: %{
          id: atom(),
          source: {atom(), atom()},
          takes: pos_integer(),
          bonus: pos_integer(),
          capped?: boolean()
        }

  @typedoc """
  Поглощение одной стихии целиком.

    * `energy_type` — стихия, id из `ruleset.resistance_energy_types`
    * `feats` / `feat_terms` — прибавка от фитов, суммой и по слагаемым
    * `effect` / `effect_term` — эффект расы и топоров после усиления кусками
      и внутреннего капа. `effect_term` — тот же получатель, что в
      `stats.mini_sets` (`Rules.MiniSets.receiver/0`): в нём и сумма наших
      двух термов (`base`), и прибавка кусков (`added`), и то, что снял кап
      (`clipped`). `nil`, когда ни раса, ни оружие поглощения не дают
    * `gear` — то, что игрок вписал по этой стихии в «Вещах»
    * `rule` — как `effect` и `gear` сведены (`:max` / `:sum`, из данных)
    * `superseded` — который из двух **проиграл сравнение**: `:gear`, когда
      вписанное число не вошло, `:effect`, когда не вошёл эффект, `nil`, когда
      сравнивать было нечего (один из двух ноль) или правило — сумма.
      ⚠ При РАВЕНСТВЕ двух ненулевых стоит `:gear`, и это выбор, а не
      случайность: не вошло именно то число, которое игрок вписал сам
      и будет искать глазами, — подпись обязана объяснить его отсутствие
    * `counted` — итог: `feats + свёрнутое`
  """
  @type entry :: %{
          energy_type: atom(),
          feats: non_neg_integer(),
          feat_terms: [feat_term()],
          effect: non_neg_integer(),
          effect_term: MiniSets.receiver() | nil,
          gear: integer(),
          rule: :max | :sum,
          superseded: :gear | :effect | nil,
          counted: integer()
        }

  @doc """
  Поглощение этого билда по стихиям — мапа, в которой есть только стихии,
  у которых **что-то** есть.

  Пустая мапа — честный полный ответ «поглощения нет»: источников ровно четыре
  (два фита, раса Гнома, группа топоров), и ни один из них у такого билда
  не сработал. `nil` здесь не бывает вовсе — «честно посчитать нельзя»
  у этого стата не случается: недостача данных снимает не число, а слагаемое,
  и говорит об этом гэпом (`gaps/4`).

  ⚠ `level` не украшение: дельта считается как разность двух полных `compute`
  по обрезанным билдам, поэтому «держит ли фит» и «сколько взятий» — всегда
  вопрос про **тот** уровень. Эффект расы и оружия при этом уровнем
  не обрезается, ровно как не обрезается он у AC и атаки: вещи и раса
  не принадлежат уровню.
  """
  @spec of(Build.t(), map(), non_neg_integer()) :: %{atom() => entry()}
  def of(%Build{} = build, ruleset, level) do
    # Эффект один на все семь стихий, и считается он ОДИН раз: в движке это
    # один эффект, наложенный на персонажа, а не семь независимых.
    effect_term = build |> MiniSets.damage_resistance(ruleset) |> List.first()
    records = Bonuses.held(build, ruleset, @markup, level)
    rule = stacking_rule(ruleset)

    for %{id: type} <- energy_types(ruleset),
        entry = entry(build, ruleset, level, type, records, effect_term, rule),
        entry.counted != 0 or entry.feats != 0 or entry.gear != 0,
        into: %{} do
      {type, entry}
    end
  end

  @doc """
  Поглощение одной стихии — `0`, если её нет в мапе.

  Геттер, а не второй расчёт: у читателей числа больше, чем у разбора, и
  спрашивать «сколько у него огня» через `Map.get(…, %{}) |> Map.get(…)`
  каждому пришлось бы самому.
  """
  @spec total(%{atom() => entry()}, atom()) :: integer()
  def total(resistances, energy_type) do
    case Map.get(resistances, energy_type) do
      %{counted: counted} -> counted
      nil -> 0
    end
  end

  @doc """
  Чего этот билд не говорит за себя про поглощение.

  Три формы, и каждая про своё:

    * `{:not_modelled, {:resistance_bonus, id}}` — источник поглощения, который
      персонаж держит, а модель считать отказывается (вердикт `not_modelled`
      в разметке). ⚠ **Сегодня её не производит ни один билд**, и это
      проверенный факт, а не догадка: в `vanilla/feat_resistance_bonuses.json`
      таких записей нет — сплошной проход нашёл ровно два источника-фита, и оба
      посчитаны. Механизм при этом жив и нужен, ровно как у сопротивления
      заклинаниям: запись, добавленная в файл завтра, придёт к игроку
      подписанной, а не сырым таплом;
    * `{:assumed, :resist_energy_superseded_by_epic}` — «эпический замещает
      обычный на той же стихии» на Сиале **перенесено с Fandom**: ни одна
      из пяти сиальских страниц `Epic energy resistance (…)` не упоминает
      `Resist energy` вовсе. Статус лежит в данных по ruleset'ам
      (`superseded_by.status_siala`), у ванили правило процитировано дословно
      и оговорки нет. ⚠ Только у билда, у которого замещение **действительно
      сработало**: оговорка про вопрос, который не возникает, — шум;
    * `{:assumed, :resistance_effect_vs_gear}` — сведение эффекта с вещью
      принято чтением, а не процитировано. Сегодня носителей нет: правило
      `verified` (слово Dan плюс замер `AV1`). Форму держит снапшот, у которого
      правила нет вовсе либо оно помечено непроверенным, — и тогда ядро берёт
      **максимум**, то есть нижнюю границу обоих чтений, и говорит об этом.
      ⚠ Тоже только там, где сравнение состоялось: оба слагаемых ненулевые.

  ⚠ `resistances` приходит аргументом, а не считается заново, ровно по той же
  причине, что у `Rules.SpellResistance.gaps/4`: «печатаем ли мы число»
  и «оговариваем ли мы его» не должны иметь возможности разойтись.
  """
  @spec gaps(Build.t(), map(), non_neg_integer(), %{atom() => entry()}) :: [tuple()]
  def gaps(%Build{} = build, ruleset, level, resistances) do
    Bonuses.gaps(build, ruleset, @markup, level, &{:not_modelled, {:resistance_bonus, &1}}) ++
      supersede_gaps(build, ruleset, level, resistances) ++
      stacking_gaps(ruleset, resistances)
  end

  @doc """
  Источники поглощения, которые этот билд держит, а модель их не считает —
  идентификаторы, по порядку данных.

  Тот же контракт, что у `Rules.SpellResistance.unmodelled/3`, и та же
  сегодняшняя пустота: ни одной записи с вердиктом `not_modelled` в файле нет.
  """
  @spec unmodelled(Build.t(), map(), non_neg_integer()) :: [atom()]
  def unmodelled(%Build{} = build, ruleset, level) do
    Bonuses.rejected_ids(build, ruleset, @markup, level)
  end

  @doc """
  Посчитана ли **вся** прибавка этого фита — тот же контракт, что
  у `Rules.SpellResistance.whole_effect_counted?/2` и её сестёр.

  Утверждение — данных (`effect_coverage: "whole_feat"`), и никогда не
  выводится из того, что прибавка применена.

  🔴 Спрашивает это `Rules.FeatChoices.gaps/3`, и до 18.09.2026 у каждого билда
  с `Resist energy` или `Epic energy resistance` рядом с посчитанной секцией
  висело бы «прибавку от фита в статы не считаем»: оба фита стали носителями
  этой оговорки 18.09.2026 задачей 3.209, которая дала им нашего получателя
  (`damage_resistance`), а считать их начала уже эта задача. Оговорка снята
  не вычёркиванием, а тем, что вернёт её само — эта функция отвечает `false`
  у любой записи, чей `effect_coverage` перестанет объявлять полноту.
  """
  @spec whole_effect_counted?(atom(), map()) :: boolean()
  def whole_effect_counted?(feat_id, ruleset) do
    Bonuses.whole_effect_counted?(ruleset, @markup, feat_id)
  end

  # ------------------------------------------------------------------ private --

  defp energy_types(ruleset), do: Map.get(ruleset, :resistance_energy_types) || []

  defp entry(build, ruleset, level, type, records, effect_term, rule) do
    terms = feat_terms(build, ruleset, level, type, records)
    feats = Bonuses.sum(terms, :bonus)
    effect = effect_of(effect_term)
    gear = Gear.resistance(build.gear, type)

    %{
      energy_type: type,
      feats: feats,
      feat_terms: terms,
      effect: effect,
      effect_term: effect_term,
      gear: gear,
      rule: rule,
      superseded: superseded(effect, gear, rule),
      counted: feats + combine(effect, gear, rule)
    }
  end

  # Эффект отрицательным быть не может — кап режет только сверху, — но `total`
  # приходит из чужого модуля, и `max(…, 0)` здесь стоит затем, чтобы
  # «поглощение −3» не смогло появиться на экране, если арифметика соседа
  # однажды уйдёт в минус.
  defp effect_of(%{total: total}), do: max(total, 0)
  defp effect_of(nil), do: 0

  defp combine(effect, gear, :sum), do: effect + gear
  defp combine(effect, gear, :max), do: max(effect, gear)

  # Кто проиграл сравнение — и `nil` там, где сравнения не было. ⚠ При равенстве
  # проигравшим назван ВПИСАННЫЙ игроком, см. @typedoc.
  defp superseded(_effect, _gear, :sum), do: nil
  defp superseded(effect, gear, :max) when effect <= 0 or gear <= 0, do: nil
  defp superseded(effect, gear, :max) when gear <= effect, do: :gear
  defp superseded(_effect, _gear, :max), do: :effect

  # Правило сведения — из данных; `nil` у снапшота без него читается как
  # **максимум**, потому что максимум есть нижняя граница и суммы, и максимума,
  # а билд об этом говорит (`stacking_gaps/2`). Умолчание в сторону меньшего
  # числа плюс оговорка — та же линия, что у всей этой части ядра.
  defp stacking_rule(ruleset) do
    case Map.get(ruleset, :resistance_stacking) do
      %{effect_vs_gear: rule} -> rule
      _absent -> :max
    end
  end

  # Слагаемые «фиты» одной стихии: сперва взятия у каждой записи, потом
  # замещение, и только потом отбрасывание нулей.
  #
  # 🔴 Порядок обязателен. Замещение — отношение ДВУХ записей («эпический
  # отменяет обычный на той же стихии»), поэтому решить его можно только когда
  # посчитаны обе; отбрось нули раньше — и запись, которая замещает, исчезнет
  # вместе со своим правом замещать.
  defp feat_terms(build, ruleset, level, type, records) do
    counted =
      for record <- records, do: {record, feat_term(record, build, ruleset, level, type)}

    for {record, term} <- counted,
        term.bonus != 0,
        not superseded?(record, counted),
        do: term
  end

  # Замещает ли эту запись другая, названная её собственным `superseded_by`,
  # — и только если та другая на ЭТОЙ стихии что-то даёт. Имени фита здесь нет:
  # называет его сама запись.
  defp superseded?(%{superseded_by: %{feat: other}}, counted) do
    Enum.any?(counted, fn {record, term} -> record.id == other and term.bonus != 0 end)
  end

  defp superseded?(_record, _counted), do: false

  # ⚠ Две ветки и никакого catch-all, сознательно — тот же сторож, что
  # у `Rules.SpellResistance`: какие формы величины вообще могут дойти
  # до `applied`-записи, проверяет загрузчик (`@applied_resistance_kinds`,
  # падает на КОМПИЛЯЦИИ). Ветка-заглушка с нулём превратила бы сломанную
  # сборку в прибавку, которая молча не считается.

  # `Resist energy`: +5 к выбранной стихии, и число взятий на него не влияет
  # вовсе — второй раз на тот же вид урона фит не берётся (замер `AA1`).
  defp feat_term(
         %{id: id, source: source, amount: %{kind: :flat, bonus: bonus}},
         build,
         ruleset,
         level,
         type
       ) do
    takes = Build.feat_takes_owned(build, ruleset, id, level, type)

    %{
      id: id,
      source: source,
      takes: takes,
      bonus: if(takes > 0, do: bonus, else: 0),
      capped?: false
    }
  end

  # `Epic energy resistance`: за каждое взятие ПАРЫ, с потолком эффекта
  # на той же паре.
  #
  # ⚠ Матчится по `source: {:feat, id}`, а не по одному id, и это сторож,
  # а не педантизм — та же строка, что у `Rules.SpellResistance`: взятия это
  # свойство ФИТА, и запись этой формы, ключёванная таблицей класса или
  # расовой склонностью, взятий бы не имела.
  defp feat_term(
         %{source: {:feat, id}, amount: %{kind: :per_take, bonus: bonus, max_total: max_total}},
         build,
         ruleset,
         level,
         type
       ) do
    takes = Build.feat_takes_owned(build, ruleset, id, level, type)
    total = takes * bonus

    %{
      id: id,
      source: {:feat, id},
      takes: takes,
      bonus: min(total, max_total),
      capped?: total > max_total
    }
  end

  # Замещение сработало И перенесено, а не процитировано, — одна оговорка
  # на билд, а не на стихию: правило одно, и семь его копий читались бы как
  # семь разных недостач.
  defp supersede_gaps(build, ruleset, level, resistances) do
    if Enum.any?(
         energy_types(ruleset),
         &assumed_supersede?(build, ruleset, level, &1.id, resistances)
       ),
       do: [{:assumed, :resist_energy_superseded_by_epic}],
       else: []
  end

  defp assumed_supersede?(build, ruleset, level, type, resistances) do
    Enum.any?(Bonuses.applied(ruleset, @markup), fn record ->
      case record do
        %{superseded_by: %{feat: other, assumed?: true}} ->
          held_on?(build, ruleset, level, record, type) and
            Enum.any?(Map.get(resistances, type, %{feat_terms: []}).feat_terms, &(&1.id == other))

        _not_superseded ->
          false
      end
    end)
  end

  # Держит ли персонаж саму замещаемую запись на этой стихии — иначе замещать
  # было нечего, и оговорка описывала бы правило, которое не сработало.
  defp held_on?(build, ruleset, level, %{id: id}, type),
    do: Build.feat_takes_owned(build, ruleset, id, level, type) > 0

  # Сведение принято чтением — там, где сравнение вообще состоялось.
  defp stacking_gaps(ruleset, resistances) do
    assumed? =
      case Map.get(ruleset, :resistance_stacking) do
        %{effect_vs_gear_assumed?: assumed?} -> assumed?
        _absent -> true
      end

    compared? = Enum.any?(resistances, fn {_type, e} -> e.effect > 0 and e.gear > 0 end)

    if assumed? and compared?, do: [{:assumed, :resistance_effect_vs_gear}], else: []
  end
end
