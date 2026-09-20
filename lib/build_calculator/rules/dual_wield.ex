defmodule BuildCalculator.Rules.DualWield do
  @moduledoc """
  Бой двумя оружиями: что он отнимает у каждой руки и сколько атак даёт второй
  (задача 3.132).

  Запрос Dan, 28.08.2026: «многие билды берут 2 оружия вместо щита или двуручки
  … Урон мы не показываем и он нас не интересует, но наличие оружия во второй
  руке влияет на АБ в главной. … Далее учитывая фиты на двуручное владение (их
  несколько), обновить АБ основной руки и левой руки тоже».

  ## Штраф, а не прибавка, и потому мимо потолков

  Всё, что здесь считается, — **отрицательное**, и через `Rules.Caps` оно
  не идёт ни одной строкой. Потолки этого проекта односторонние по построению
  («лимита атаки +20», `Caps.clamp/3` режет сверху и никогда снизу), и пропускать
  через них штраф значило бы либо не сделать ничего, либо сделать то, чего никто
  не писал. Тот же довод, по которому мимо капов идёт штраф брони к навыкам
  (`Rules.Worn.armor_check_penalty/2`).

  ## Два способа оказаться в этом бою, и второй не про вторую руку

    * **оружие во второй руке** — `Rules.Gear.off_hand_weapon`, и оно должно
      СЧИТАТЬСЯ (`Rules.GearWeapon.held/3`): оружие, которое персонаж держать
      не может, ни атаки не даёт, ни штрафа не накладывает;
    * **двустороннее оружие в главной** — «Wielding a double-sided weapon
      automatically causes one to be dual-wielding … and incurring the standard
      dual-wielding penalties» (`fandom:Double-sided weapon`, revid 68931).
      Вторая рука при этом пуста: предмет занимает обе.

  ⚠ Второй случай не «мелочь на потом»: без него билд с двулезвийным мечом
  показывал бы AB главной руки на 2 больше настоящего и молчал бы о лишней
  атаке — то есть **завышение**, которое игрок изнутри инструмента не обнаружит
  (`feat_attack_bonuses.json` → `_weapon_decision`).

  ## Лёгкая вторая рука — тоже два разных утверждения

  У настоящего второго оружия «лёгкость» считается по размерам
  (`Rules.Wield.light?/3`, «A melee weapon at least one size smaller than the
  wielder»), а у двустороннего она **названа словом** источника: «a double-sided
  weapon's off-hand end counts as a light weapon». Свести их в одно нельзя —
  двулезвийный меч `large`, и по размерному правилу он лёгким не был бы никогда.

  ## Ступени — множество ЭФФЕКТОВ, а не список взятых фитов

  Рейнджер получает `Dual-wield`, который «gives all the benefits of having the
  ambidexterity and two-weapon fighting feats», и это ТОТ ЖЕ эффект, а не второй:
  рейнджер, взявший `Two-weapon fighting` слотом, прирост второй раз не получает.
  Поэтому ступени применяются по `MapSet` эффектов, у которого повторов
  не бывает по построению.

  ⚠ Выдача рейнджера условна («While wearing medium or heavy armor they lose
  these benefits»), и у условия **три исхода, а не два**: потеряна, сохранена
  и «класс надетого этому ruleset'у неизвестен». Третий — не вежливая формула,
  а сегодняшнее состояние `vanilla`: границу лёгкая/средняя/тяжёлая измерили
  на Сиале (`GAME_CHECKS.md` AH1, задачи 3.140–3.141), а где та же линия
  проходит в ванильных правилах, не выяснял никто — и переносить её по аналогии
  запрещено, потому что на Сиале кольчужная рубаха СРЕДНЯЯ, а в D&D 3.5 лёгкая.
  Там, где класс неизвестен, выдача считается по решению владельца, записанному
  в самих данных вместе с ключом оговорки; вывести класс из `base_ac` запрещено.

  ⚠ «Класса нет вовсе» (строка «нет / одежда») и «слой про класс не сказал» —
  РАЗНЫЕ ответы, и путать их нельзя: в первом рейнджер бонусы сохраняет молча,
  во втором — сохраняет с оговоркой. Сегодня оба ведут к «бонусы есть», и ровно
  поэтому разница легко потерялась бы: она не в числе, а в том, обязаны ли мы
  об этом числе что-то сказать.

  ## Число атак второй руки — своё, а не копия главной

  «Wielding a double-sided weapon … allowing an extra attack (or two) per combat
  round»: сама вторая рука даёт одну атаку, `Improved two-weapon fighting` —
  вторую. У главной руки в это время их четыре, и путать эти два числа нельзя.

  ⚠ Штраф −5 у второй атаки второй руки **не применяется**, и это не пропуск:
  модель печатает по одному числу AB на руку — бонус ПЕРВОЙ атаки этой руки, —
  ровно как у главной руки, где вторая, третья и четвёртая атаки идут через
  −5/−10/−15 и не печатаются тоже. Применить его к руке целиком значило бы
  занизить первую атаку на 5.

  ## Ни одного игрового числа и ни одного имени фита

  База (−6/−10), ступени, лёгкая вторая рука, число атак и выдача рейнджера
  приходят из `ruleset.dual_wield` (`vanilla/feat_attack_bonuses.json` →
  `dual_wield`). Здесь нет ни `two_weapon_fighting`, ни `−6`, ни имени свойства
  двустороннего оружия: последнее приходит именем ПОЛЯ, посчитанным загрузчиком
  по закрытому словарю ядра (`Rules.Attack.weapon_property_field/1`).

  ⚠ Слово `double_sided` в файле всё же есть — **дважды и оба раза не как
  игровое имя**: ключом нашей собственной схемы данных (`ruleset.dual_wield.
  double_sided`) и меткой `source`, которой этот модуль отвечает вызывающему
  «чем вызван бой двумя оружиями». Переименуй шард свой хват — сравнение
  не сломается: оно идёт по полю справочника, а не по этому слову.
  """

  alias BuildCalculator.Rules.{Build, GearWeapon, Wield, Worn}

  @typedoc """
  Одно слагаемое штрафа, для разбора рядом с числом.

  `source` — `:base`, `{:feat, id}` или `:light_off_hand`. База в списке есть
  всегда и нулевой не бывает: без неё разбор не сходился бы со своим итогом.
  """
  @type term_entry :: %{
          source: :base | {:feat, atom()} | :light_off_hand,
          main: integer(),
          off: integer()
        }

  @typedoc """
  Бой двумя оружиями целиком.

    * `source` — чем он вызван: `:off_hand_weapon` или `:double_sided`;
    * `off_hand_weapon` — что во второй руке, `nil` у двустороннего оружия
      (предмет там один, и он в главной);
    * `light_off_hand?` — лёгкая ли вторая рука; `nil`, если сказать нельзя;
    * `penalty` — итог по каждой руке, всегда ≤ 0;
    * `terms` — из чего он собрался;
    * `off_hand_attacks` — сколько атак даёт вторая рука.
  """
  @type t :: %{
          source: :off_hand_weapon | :double_sided,
          weapon: atom() | nil,
          off_hand_weapon: atom() | nil,
          light_off_hand?: boolean() | nil,
          penalty: %{main: integer(), off: integer()},
          terms: [term_entry()],
          off_hand_attacks: non_neg_integer()
        }

  @no_penalty %{main: 0, off: 0}

  @doc """
  Бой двумя оружиями этого билда — `nil`, если персонаж бьётся одним.

  `nil` покрывает и «во второй руке пусто», и «второе оружие держать нельзя»,
  и «в правилах ruleset'а этого блока нет вовсе»: во всех трёх случаях штрафа
  нет, а сказать о последнем — дело `gaps/2`, не этого числа.
  """
  @spec of(Build.t(), map()) :: t() | nil
  def of(%Build{} = build, ruleset) do
    case {rules(ruleset), source(build, ruleset)} do
      {nil, _none} ->
        nil

      {_rules, nil} ->
        nil

      {rules, {source, weapon, off_hand}} ->
        assemble(build, ruleset, rules, source, weapon, off_hand)
    end
  end

  @doc """
  Штраф по каждой руке — `%{main: 0, off: 0}` у персонажа с одним оружием.

  Отдельно от `of/2`, чтобы `Rules.compute/2` не разбирал `nil` в трёх местах:
  «одна рука» и «две руки без штрафа» дают одно и то же число, и различать их
  здесь незачем.
  """
  @spec penalty(t() | nil) :: %{main: integer(), off: integer()}
  def penalty(nil), do: @no_penalty
  def penalty(%{penalty: penalty}), do: penalty

  @doc "Сколько атак даёт вторая рука — `0` у персонажа с одним оружием."
  @spec off_hand_attacks(t() | nil) :: non_neg_integer()
  def off_hand_attacks(nil), do: 0
  def off_hand_attacks(%{off_hand_attacks: attacks}), do: attacks

  @doc """
  Что этот бой должен сказать игроку.

  Три оговорки, и каждая отвечает на свой вопрос:

    * `{:missing_data, :dual_wield_rules}` — снапшот таблицы штрафов не несёт
      вовсе, то есть бой двумя оружиями посчитан бесплатным. Умолчание
      направлено в сторону разговора, а не молчания: посчитать штраф нечем,
      и делать вид, что его нет, было бы завышением у каждого такого билда;
    * `{:missing_data, {:light_weapon, weapon}}` — сказать про лёгкость нечем
      (у оружия нет размера, у персонажа нет расы, у снапшота нет лестницы),
      и −2 обеим рукам поэтому не сняты;
    * `{:missing_data, {:armor_weight_class, feat}}` — выдача рейнджера
      посчитана, а класса надетого этот ruleset не знает. Печатается ровно там,
      где вопрос живой: доспех записан **и** класс его неизвестен. У персонажа
      без доспеха «wearing medium or heavy armor» не выполняется по факту,
      а не по незнанию; у персонажа в доспехе с известным классом ответ есть
      и говорить не о чем — на `siala_41` оговорка поэтому исчезла целиком.

  ⚠ Третья печатается и тогда, когда владелец решил при неизвестном классе
  выдачу НЕ считать: неуверенность одна и та же, у какой бы из двух сторон
  ни оказалось умолчание, — молчать о ней можно, только имея ответ.
  """
  @spec gaps(Build.t(), map()) :: [tuple()]
  def gaps(%Build{} = build, ruleset) do
    case {rules(ruleset), source(build, ruleset)} do
      {_rules, nil} -> []
      {nil, _fighting} -> [{:missing_data, :dual_wield_rules}]
      {rules, _fighting} -> light_gaps(build, ruleset) ++ grant_gaps(build, ruleset, rules)
    end
  end

  # ------------------------------------------------------------------ private --

  defp rules(ruleset), do: Map.get(ruleset, :dual_wield)

  # Чем вызван бой двумя оружиями — и оружие, которое его вызвало.
  #
  # ⚠ Порядок веток не произволен: настоящее второе оружие рядом с двусторонним
  # в главной руке невозможно (двустороннее занимает обе руки, и `GearWeapon`
  # отказывает второй руке формой `{:two_handed_weapon, …}`), так что ветки
  # взаимоисключающи по построению, а не по очерёдности.
  defp source(build, ruleset) do
    case GearWeapon.held(build, ruleset, :off) do
      nil -> double_sided_source(build, ruleset)
      weapon -> {:off_hand_weapon, weapon, weapon}
    end
  end

  defp double_sided_source(build, ruleset) do
    with %{double_sided: %{weapon_field: field}} <- rules(ruleset),
         weapon when not is_nil(weapon) <- GearWeapon.held(build, ruleset, :main),
         %{^field => true} <- Map.get(Map.get(ruleset, :weapons) || %{}, weapon) do
      {:double_sided, weapon, nil}
    else
      _one_handed_or_unstated -> nil
    end
  end

  defp assemble(build, ruleset, rules, source, weapon, off_hand) do
    light? = light?(build, ruleset, rules, source, off_hand)
    effects = effects(build, ruleset, rules)
    terms = terms(rules, effects, light?)

    %{
      source: source,
      weapon: weapon,
      off_hand_weapon: off_hand,
      light_off_hand?: light?,
      penalty: sum(terms),
      terms: terms,
      off_hand_attacks: attacks(rules, effects)
    }
  end

  # Лёгкость второй руки — ДВА разных утверждения, см. moduledoc. У настоящего
  # второго оружия она считается по размерам, у двустороннего названа словом.
  defp light?(_build, _ruleset, rules, :double_sided, _off_hand),
    do: rules.double_sided.off_hand_is_light?

  defp light?(build, ruleset, _rules, :off_hand_weapon, off_hand),
    do: Wield.light?(build, off_hand, ruleset)

  # Множество ЭФФЕКТОВ, а не взятых фитов: выдача рейнджера даёт те же два, и
  # взявший их слотом рейнджер не получает прироста дважды.
  defp effects(build, ruleset, rules) do
    owned = Build.feats_owned(build, ruleset, Build.character_level(build))

    Enum.reduce(rules.grants, MapSet.new(owned), fn grant, acc ->
      if MapSet.member?(acc, grant.feat) and granted?(build, ruleset, grant),
        do: MapSet.union(acc, grant.benefits_of),
        else: acc
    end)
  end

  # ⚠ `build` и `ruleset` здесь с задачи 3.141, и без них функция была
  # неспособна ответить в принципе: она решала, выдан ли эффект, не имея
  # доступа к тому, что персонаж носит.
  defp granted?(_build, _ruleset, %{condition: nil}), do: true

  defp granted?(build, ruleset, %{condition: condition}) do
    case verdict(build, ruleset, condition) do
      :kept -> true
      :lost -> false
      # Решение владельца, записанное в данных вместе с доводом; чего здесь нет
      # и быть не может, так это чтения класса брони по её базовому AC.
      :unknown -> condition.counted_when_class_is_unknown?
    end
  end

  # Три исхода, и порядок веток — не вкус: ИЗВЕСТНАЯ потеря сильнее незнания.
  # Персонаж в доспехе известного класса и в чём-то ещё, про что слой молчит,
  # бонусы всё равно потерял — «мы кое-чего не знаем» не отменяет того, что
  # знаем.
  defp verdict(build, ruleset, condition) do
    classes = worn_classes(build, ruleset, condition)

    cond do
      Enum.any?(classes, &MapSet.member?(condition.lost_when, &1)) -> :lost
      Enum.any?(classes, &(&1 == :unknown)) -> :unknown
      true -> :kept
    end
  end

  # Свойство надетого, которое условие спрашивает, — ИМЕНЕМ ПОЛЯ, посчитанным
  # загрузчиком по закрытому словарю (`Rules.Worn.item_property_field/1`).
  # Ни `:weight_class`, ни `:armor` здесь не написаны.
  #
  # ⚠ Спрашивается `worn/2`, а не `recorded/2`: предмет, который персонаж носить
  # не может, ни базы не даёт, ни бонусов не отбирает — иначе башенный щит
  # Карлика, которого игра ему не даёт, обирал бы заодно и рейнджера.
  #
  # ⚠ Свойства, которого у предмета нет, достаточно, чтобы ответ стал
  # неизвестным: умолчание направлено в сторону разговора, а не тишины.
  defp worn_classes(build, ruleset, condition) do
    for {category, item} <- Worn.worn(build, ruleset),
        category.id in condition.worn_categories,
        do: Map.get(item, condition.field, :unknown)
  end

  defp terms(rules, effects, light?) do
    [%{source: :base, main: rules.base_penalty.main, off: rules.base_penalty.off}] ++
      for(
        step <- rules.steps,
        MapSet.member?(effects, step.feat),
        do: %{source: {:feat, step.feat}, main: step.main, off: step.off}
      ) ++
      if light? == true,
        do: [
          %{
            source: :light_off_hand,
            main: rules.light_off_hand.main,
            off: rules.light_off_hand.off
          }
        ],
        else: []
  end

  defp sum(terms) do
    Enum.reduce(terms, @no_penalty, fn term, acc ->
      %{main: acc.main + term.main, off: acc.off + term.off}
    end)
  end

  defp attacks(rules, effects) do
    Enum.reduce(rules.off_hand_attacks.extra, rules.off_hand_attacks.base, fn extra, total ->
      if MapSet.member?(effects, extra.feat), do: total + extra.attacks, else: total
    end)
  end

  defp light_gaps(build, ruleset) do
    case of(build, ruleset) do
      %{light_off_hand?: nil, off_hand_weapon: weapon} when not is_nil(weapon) ->
        [{:missing_data, {:light_weapon, weapon}}]

      _decided_or_moot ->
        []
    end
  end

  # ⚠ Только у выдачи, которая ДЕЙСТВИТЕЛЬНО применилась, и только там, где
  # ответа нет. У персонажа, про доспех которого игрок ничего не сказал, модель
  # носит пусто — то же соглашение, на котором держатся бонусы монаха, — и
  # «wearing medium or heavy armor» не выполняется по факту, а не по незнанию;
  # у персонажа в доспехе известного класса ответ есть, и печатать «не смогли
  # проверить» было бы той самой ложной неопределённостью наоборот, которую
  # CLAUDE.md §6 запрещает.
  defp grant_gaps(build, ruleset, rules) do
    owned = Build.feats_owned(build, ruleset, Build.character_level(build))

    for grant <- rules.grants,
        MapSet.member?(owned, grant.feat),
        condition = grant.condition,
        not is_nil(condition),
        verdict(build, ruleset, condition) == :unknown,
        do: {:missing_data, {condition.gap, grant.feat}}
  end
end
