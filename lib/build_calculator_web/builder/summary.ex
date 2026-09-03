defmodule BuildCalculatorWeb.Builder.Summary do
  @moduledoc """
  The read-only view of a build: totals **with their arithmetic shown**.

  The view screen answers a different question from the constructor — not "what
  do I press" but "what is this build and is it any good" (CLAUDE.md §6). Since
  nothing is being chosen, the space goes into explaining where each number came
  from: `BAB +28` under a caption reading
  `Fighter 10 (полный) 10 + Cleric 10 из 15 (средний) 7 + Rogue 0 из 16 (средний) 0
  + эпик +11`, `Fort +24` under
  `Fighter 10 (высокий) 7 + Cleric 10 из 15 (высокий) 7 + Rogue 0 из 16 (низкий) 0
  + эпик +10 + CON +0`, `Атак/раунд 4` under `от BAB 17 за первые 20 уровней;
  эпик (+11) атак не добавляет`.

  ⚠️ Классовая часть у сейвов разложена так же и теми же счётчиками уровней, что
  у BAB, но своими метками («высокий»/«низкий», их две) и своим эпиком (+10
  против +11 на капе 41). Два разбора одной панели обязаны читаться как один
  язык — расхождение выглядело бы багом, — но одинаковыми они не являются.

  That breakdown is the point of the screen. Without it a shared build is a list
  of digits, and nobody can tell why a level 40 wizard swings twice and a
  fighter four times — which is a rule, not a quirk, and this is where the tool
  teaches it.

  Every part of every caption is a field `Rules.compute/2` already returns
  (`base_attack_at_20`, `epic_attack_bonus`, `epic_save_bonus`, `base_fort`
  and friends). Nothing here re-derives a game number; a stat the core refused
  to compute keeps its `nil` and prints as `?`.
  """

  alias BuildCalculator.Rules.{
    Abilities,
    Bonuses,
    Build,
    Caps,
    ClassChoices,
    DerivedStats,
    Epic,
    Skills
  }

  alias BuildCalculatorWeb.Builder.{Feats, Labels, Palette}

  @doc "The build's headline: the class split, or a placeholder for an empty build."
  @spec title(map(), Build.t(), map()) :: String.t()
  def title(ruleset, %Build{} = build, stats) do
    case Enum.uniq(build.levels) do
      [] ->
        "Пустой билд"

      classes ->
        Enum.map_join(classes, " · ", fn class ->
          "#{Labels.class_name(ruleset, class)} #{Map.get(stats.class_levels, class, 0)}"
        end)
    end
  end

  @typedoc """
  One totals card: the number as a string, plus the sum it came out of.

  `hero?` marks the number the screen leads with, `unknown?` the ones the core
  refused to compute. Both are read by the markup, so both belong in the type —
  the spec used to name only the first four keys, which is exactly why dialyzer
  called it disjoint from what the function actually returns.

  `terms` — те же слагаемые **списком**, когда разбор из них и состоит, иначе
  `nil` (у «Атак / раунд» и скилл-поинтов подпись — предложение, а не сумма).
  Заведено по просьбе Dan 10.08.2026 (§3.24, дефект 1): «смотрится не очень…
  может, список использовать, в конструкторе лучше выглядит». Прозой у `Ref`
  восемь слагаемых занимали **десять строк** переноса в карточке 170px.

  ⚠️ `from` при этом остаётся и остаётся ЕДИНСТВЕННОЙ строкой — он собирается
  из этого же списка (`terms_caption/1`), а не пишется рядом второй раз. Два
  независимых описания одной суммы уже расходились на этом экране (см. коммент
  к `terms_caption/1`), и заводить второе ради вида было бы тем же самым.
  """
  @type card :: %{
          key: String.t(),
          label: String.t(),
          value: String.t(),
          from: String.t() | nil,
          terms: [%{label: String.t(), value: String.t()}] | nil,
          hero?: boolean(),
          unknown?: boolean()
        }

  @doc """
  The totals grid: value plus the sum it came out of.

  `value` is already a string (`"+30"`, `"?"`); `from` is the caption, or `nil`
  when there is nothing honest to say; `terms` is the same sum as a list when it
  is a sum at all.
  """
  @spec stat_cards(map(), map()) :: [card()]
  def stat_cards(ruleset, stats) do
    mods = stats.ability_modifiers

    # SR — не карточка среди прочих, а список из нуля или одной: строки нет
    # вовсе ниже 12 уровней монаха (task 3.45, заход 2). Стоит рядом с AC,
    # третьей защитой персонажа (от урона / от удара / от магии), а не
    # в хвосте списка — тот же порядок, что у панели итогов конструктора
    # (`BuilderLive`'s `@panel_layout`, группа «живучесть»).
    [
      card("hp", "HP", number(stats.hp), hp_card_terms(ruleset, stats)),
      card("ac", "AC голым", number(stats.ac_naked), ac_naked_terms(ruleset, stats)),
      # The second AC of the canonical format needs equipment. Until the armoury
      # exists, the only equipment there is is what the player typed by hand — so
      # this is a number when they typed one and a "?" when they did not. An
      # invented number here would be the worst kind.
      ac_geared_card(ruleset, stats)
    ] ++
      spell_resistance_cards(ruleset, stats) ++
      [
        card("bab", "BAB", signed(stats.base_attack), bab_terms(ruleset, stats), hero: true),
        card("ab", "AB", signed(stats.attack_bonus), ab_terms(ruleset, stats))
      ] ++
      off_hand_ab_cards(ruleset, stats) ++
      [
        # Frozen by the level-20 base attack: the epic bonus raises the numbers but
        # never adds a swing (CLAUDE.md §3).
        #
        # ⚠️ Задача 3.133 (Dan, замечание 1 к задаче 3.132): «вижу АБ с обеими
        # руками… далее атак/раунд… показывает 4/1, но в реальности это 4
        # атаки основной рукой и одна атака второй». Слеш подписи значит «на»
        # (атак **в** раунд), слеш значения значил «и» — читатель применял
        # к значению то же прочтение, что и к подписи, и терял вторую руку
        # в дроби. Число второй руки больше НЕ подмешивается сюда слешем —
        # у него своя карточка ниже (`off_hand_apr_cards/2`), тем же приёмом,
        # что уже развёл AB и «AB второй руки» (задача 3.132, «отдельную
        # строку, мешать не надо» — то же решение, просто выполненное и здесь).
        card(
          "apr",
          "Атак / раунд",
          number(stats.attacks_per_round),
          apr_caption(ruleset, stats)
        )
      ] ++
      off_hand_apr_cards(ruleset, stats) ++
      [
        card(
          "fort",
          "Fort",
          signed(stats.fort),
          save_card_terms(ruleset, stats, :fort, :con, mods.con)
        ),
        card(
          "ref",
          "Ref",
          signed(stats.ref),
          save_card_terms(ruleset, stats, :ref, :dex, mods.dex)
        ),
        card(
          "will",
          "Will",
          signed(stats.will),
          save_card_terms(ruleset, stats, :will, :wis, mods.wis)
        ),
        card(
          "skill_points",
          "Скилл-поинты",
          number(stats.skill_points.earned),
          "потрачено #{stats.skill_points.spent}, свободно #{stats.skill_points.free}"
        )
      ]
  end

  # AB второй руки (задача 3.132) — не карточка среди прочих, а список из
  # нуля или одной, тем же приёмом, что у SR: строки нет вовсе, пока во
  # второй руке ничего нет (`stats.off_hand == nil`), а не «AB 0» — второй
  # руки без оружия у персонажа не бывает вовсе, и печатать её как «есть, но
  # ноль» значило бы сообщить о том, чего нет. Решение Dan 28.08.2026: «для
  # второй руки отдельную строку, мешать не надо».
  defp off_hand_ab_cards(_ruleset, %{off_hand: nil}), do: []

  defp off_hand_ab_cards(ruleset, %{off_hand: off_hand} = stats) do
    [
      card(
        "off_hand_ab",
        "AB второй руки",
        signed(off_hand.attack_bonus),
        off_hand_ab_terms(ruleset, stats)
      )
    ]
  end

  # Атаки ВТОРОЙ руки — своя карточка, тем же приёмом, что у
  # `off_hand_ab_cards/2` выше (задача 3.133). До неё оба числа делил слеш
  # одной карточки (задача 3.132: «атаки — главная/вторая», форма — «как
  # тебе или агенту будет виднее»), и Dan вернул это замечанием 1:
  # «вижу АБ с обеими руками… далее атак/раунд… показывает 4/1, но
  # в реальности это 4 атаки основной рукой и одна атака второй». Слеш
  # подписи значит «на» (атак **в** раунд), слеш значения значил «и» — два
  # разных прочтения одного символа подряд. Разбора у числа нет осознанно,
  # той же причиной, что у главной руки: это счётчик по эффектам
  # (`Rules.DualWield`), а не сумма, которую стоило бы раскладывать термами.
  #
  # У второй руки СВОЁ число атак (`stats.off_hand.attacks_per_round`), а не
  # копия главной: сама вторая рука в бою двумя оружиями даёт одну атаку,
  # `Improved two-weapon fighting` — вторую, а у главной руки в это время их
  # фиксированные BAB'ом четыре.
  defp off_hand_apr_cards(_ruleset, %{off_hand: nil}), do: []

  defp off_hand_apr_cards(_ruleset, %{off_hand: off_hand}) do
    [card("off_hand_apr", "Атак второй руки", number(off_hand.attacks_per_round), nil)]
  end

  # ⚠️ «Вписал число» — не единственный способ одеться с задачи 3.41: игрок
  # может выбрать латы и не вписать ни цифры, и тогда `ac_gear_bonus` ноль, а
  # AC в шмоте на восемь больше голого. Спрашивать надо про ОБА утверждения,
  # иначе карточка печатает «?» рядом с посчитанным числом.
  defp ac_geared_card(ruleset, stats) do
    if gear_ac?(stats),
      do:
        card(
          "ac_geared",
          "AC в экипировке",
          number(stats.ac_geared),
          ac_geared_terms(ruleset, stats)
        ),
      else: card("ac_geared", "AC в экипировке", "?", "посчитает армори, её ещё нет")
  end

  # Есть ли у билда AC с вещей вообще: вписанное число ИЛИ выбранный предмет
  # с базой. ⚠️ `Map.get/2` со своим дефолтом — этот модуль зовут и с
  # сохранёнными наборами статов, у которых поля может не быть.
  defp gear_ac?(stats) do
    stats.ac_gear_bonus != 0 or
      Enum.any?(Map.get(stats, :ac_types_resolved) || [], &(Map.get(&1, :base, 0) != 0))
  end

  # A term list, printed as the same one-line sentence every caption on this
  # screen already used before task 3.6 — `"LABEL value + LABEL value"` — so
  # the view screen's captions and the constructor's popup (`ab_terms/2`,
  # `ac_naked_terms/2`, `ac_geared_terms/2`, `hp_terms/2` below) read off the
  # exact same list rather than two hand-written strings that can disagree
  # about what `attack_bonus` or `hp` add up to. That disagreement already
  # happened once: this screen's old "AB" caption read `"BAB + STR …"`
  # unconditionally, which was simply wrong the moment Weapon Finesse moved
  # the attack ability to DEX — a caption built from a second, independent
  # description of the same sum instead of from the sum's own terms.
  defp terms_caption(terms), do: Enum.map_join(terms, " + ", &"#{&1.label} #{&1.value}")

  # Четвёртый аргумент — либо СПИСОК слагаемых, либо готовое предложение. Разница
  # настоящая: у «Атак / раунд» разбора нет и быть не может (это поиск по таблице,
  # а не сумма — `apr_caption/1`), у «AC в шмоте» без вещей нет вовсе числа. Такие
  # карточки печатают подпись прозой, и в список её ломать нечего.
  #
  # ⚠️ `from` у карточки-суммы собирается ИЗ ЭТОГО ЖЕ списка, а не пишется рядом
  # второй раз: одна сумма — одно описание. Второе описание той же суммы на этом
  # экране уже расходилось с первым (см. коммент к `terms_caption/1` выше).
  defp card(key, label, value, from_or_terms, opts \\ [])

  defp card(key, label, value, terms, opts) when is_list(terms),
    do: build_card(key, label, value, terms_caption(terms), terms, opts)

  defp card(key, label, value, prose, opts),
    do: build_card(key, label, value, prose, nil, opts)

  defp build_card(key, label, value, from, terms, opts) do
    %{
      key: key,
      label: label,
      value: value,
      from: from,
      terms: terms,
      hero?: Keyword.get(opts, :hero, false),
      unknown?: value == "?"
    }
  end

  # `skill_save_bonus`, а не `spellcraft_save_bonus`: правило читается из данных,
  # и имя навыка в поле структуры было бы той самой игровой константой в коде,
  # которой в проекте не место. Сегодня источник ровно один — Spellcraft, +1 ко
  # всем трём сейвам за каждые 5 рангов, — поэтому подпись называет его прямо.
  #
  # Оба слагаемых по-прежнему save-agnostic (вещи и Spellcraft бьют во все три
  # сейва одинаково) — в отличие от собственных термов билда (задача 1.12a),
  # у каждого из которых свой save, поэтому им нужен свой список, а не запись
  # в этой паре.
  # ⚠️ Третий элемент — ИМЯ МЕХАНИЗМА, которым ruleset называет сторону капа
  # (`stat_caps.saving_throw_bonus.applies_to_sources`). То же, что у `@ab_extras`,
  # и по той же причине: с 09.08.2026 кап сейвов покрывает вещи и Spellcraft, но
  # почти ничего из собственных прибавок билда, и разбор обязан ставить их ПОСЛЕ
  # строки среза, а не перед ней.
  @save_extras [
    {:gear_save_bonus, "вещи", :gear},
    {:skill_save_bonus, "Spellcraft", :skill_rule}
  ]

  @doc """
  Save addends beyond «база + характеристика + эпик» — собственные термы
  билда, вещи, Spellcraft, срез капа — as `%{label:, value:}` (task 3.6: the
  same term shape every popup-and-caption pair on this screen now shares,
  `ability_terms/1`'s shape from task 3.13 carried over rather than a second
  one invented here).

  `save` picks which of `stats.own_save_terms` (task 1.12a — `Iron will`,
  `Divine grace`, `Sacred defense`…) belong in **this** breakdown: a term
  from `Rules.SaveBonuses` names a single save, and `Divine grace` shows up
  in all three of Fort's, Ref's and Will's lists as three separate terms
  rather than once with nowhere obvious to put it.

  Each extra names a field of `DerivedStats` and is read with a default of
  `0`, so a term the core does not report simply does not appear. That is
  what let **+1 to all three saves per 5 ranks of Spellcraft** show up in the
  view screen's caption and in the totals panel the moment the skills layer
  started returning it, without a line of markup changing.

  Showing it is the point (CLAUDE.md §3): it is a sizeable bonus players do not
  count for themselves — a Sorcerer 40 with 43 ranks goes 18/18/22 → 26/26/30 —
  and a save quietly eight points above the arithmetic beside it reads as a bug
  in the calculator.

  ⚠️ **The +20 ceiling is one ceiling per save, and it does NOT cover every term
  here** (09.08.2026, Dan: «У сейвов тоже фиты не входят в кап +20 … и потом ещё
  с вещей набрать +20»). Вещи и Spellcraft под ним; из собственных прибавок билда
  под ним ровно одна — `Sacred defense`, — а остальные тринадцать лежат поверх.
  Клип при этом по-прежнему ОДИН на сейв (CLAUDE.md §9, `_cap_decision`
  в `vanilla/feat_save_bonuses.json`), и когда он срабатывает, напечатанные
  слагаемые больше не сходятся в число на экране — поэтому срез стоит отдельным
  отрицательным термом. Без него подпись противоречила бы значению, которое
  объясняет, — единственное, чего разбор делать не имеет права.

  ⚠️ **Порядок термов = сторона капа, и это не косметика.** Сначала то, что
  потолок режет, потом сам срез, потом то, что лежит поверх него — ровно как
  у `ab_terms/2`. Иначе строка «сверх капа −5» стоит под именем `Luck of heroes`,
  который ничего не потерял, то есть разбор обвиняет невиновного.

  This is the extras only — «база», the governing ability and «эпик» are
  `save_summary_terms/6`, which every save's popup uses and which this
  function feeds the tail of.
  """
  @spec save_terms(map(), map(), DerivedStats.save()) :: [map()]
  def save_terms(ruleset, stats, save) do
    own =
      for term <- Map.get(stats, :own_save_terms, []),
          term.save == save,
          do: {term.bonus, own_save_label(ruleset, term), Map.get(term, :under_cap?, true)}

    # Сторона капа: у собственных термов — у самой записи (её несёт терм),
    # у вещей и Spellcraft — у вида источника, потому что записи у них нет вовсе
    # (`Rules.Caps`). Ни то, ни другое не решается здесь.
    extras =
      for {value, label, source} <- save_extras(stats),
          do: {value, label, Caps.covers_source?(ruleset, :saving_throw_bonus, source)}

    {under_cap, over_cap} =
      Enum.split_with(own ++ extras, fn {_value, _label, under?} -> under? end)

    drop_flag = fn terms -> for {value, label, _under?} <- terms, do: {value, label} end

    (drop_flag.(under_cap) ++ save_clipped(stats, save) ++ drop_flag.(over_cap))
    |> Enum.map(fn {value, label} -> %{label: label, value: signed(value)} end)
  end

  @doc """
  The two save-agnostic extras alone — вещи, Spellcraft — for the panel's
  GROUP note (`Builder.TotalsPanel.panel_note/2`), which used to be `save_terms/1`'s
  whole job before task 1.12a. ⚠ Deliberately narrower than `save_terms/3`
  now: the build's own terms (`Iron will`, `Divine grace`…) are no longer
  "ко всем трём" — a save-specific bonus summarised at group level would say
  something untrue about the other two saves — and neither is the clip
  amount, because which save (if any) actually hits +20 depends on those
  same terms and can now differ save by save. Both belong in `save_terms/3`,
  read once per row, not once for the group.
  """
  @spec save_extras_terms(map()) :: [map()]
  def save_extras_terms(stats) do
    for {value, label, _source} <- save_extras(stats),
        do: %{label: label, value: signed(value)}
  end

  # Само слагаемое плюс ИМЯ МЕХАНИЗМА, которым ruleset называет его сторону капа.
  # Сторону здесь не решают и не спрашивают: групповой подписи она не нужна
  # (там нет среза, значит нечего расставлять по сторонам), а `save_terms/3`
  # спрашивает её сам.
  defp save_extras(stats) do
    for {field, label, source} <- @save_extras,
        value = extra_value(stats, field, 0),
        value != 0,
        do: {value, label, source}
  end

  # Именем источника, а не «фиты +6»: число рядом с `Divine grace` игрок может
  # проверить, число рядом с «фиты» — только принять на веру (тот же приём,
  # что у `own_ac_label/2` и `feat_terms/2`).
  #
  # ⚠️ У ability_modifier-термов характеристика дописана в скобках
  # (`Divine grace (CHA)`) — без неё «+6» рядом с именем фита не объясняет,
  # ПОЧЕМУ бонус именно такой: он растёт и падает с харизмой, а не фиксирован,
  # как у `Iron will`, и это разница, которую подпись обязана показывать.
  defp own_save_label(ruleset, %{source: {:class, id}}),
    do: "#{Labels.class_name(ruleset, id)} (класс)"

  defp own_save_label(ruleset, %{source: {:skill, id}}), do: Labels.skill_name(ruleset, id)

  defp own_save_label(ruleset, %{source: {_feat_or_race, id}}),
    do: "#{Labels.feat_name(ruleset, id)}#{save_ability_hint(ruleset, id)}"

  defp save_ability_hint(ruleset, id) do
    ruleset
    |> Bonuses.applied(:save_bonuses)
    |> Enum.find(&(&1.id == id))
    |> case do
      %{amount: %{kind: :ability_modifier, ability: ability}} -> " (#{Labels.ability(ability)})"
      _ -> ""
    end
  end

  # Сколько отняли потолком — берём у ядра (`save_cap_clipped`), а не вычитаем
  # сами. ⚠️ Раньше здесь стояла разность `save_bonus` и суммы всех напечатанных
  # термов, и с 09.08.2026 это неверно по той же причине, что у атаки: кап
  # покрывает не все источники, поэтому разность включила бы прибавки от фитов,
  # которые никто не резал. Отсутствие поля означает «не срезано», а не «срезано
  # всё».
  defp save_clipped(stats, save) do
    case stats |> Map.get(:save_cap_clipped, %{}) |> Map.get(save, 0) do
      0 -> []
      over -> [{over, "сверх капа"}]
    end
  end

  # `Map.get/3` rather than a struct field: the whole point is to tolerate a
  # field the core does not carry.
  defp extra_value(stats, field, default), do: Map.get(stats, field, default) || default

  @doc """
  One save's full breakdown — **по классам**, эпик, характеристика и прибавки
  из `save_terms/3` — for the totals panel's popup (task 3.6, the same
  `BuilderComponents.stat_pop/1` mechanism task 3.13 built).

  🔴 **Классовая часть больше не один терм «база».** До этой задачи разбор
  сейва открывался строкой `база 6`, и это был единственный крупный разбор
  панели, сворачивавший всю классовую прогрессию в одно число: `Волшебник 20 →
  Воин 20` показывал `база 6` к Fort и молчал о том, что шесть — волшебниковы,
  а двадцать уровней воина дали ноль. Теперь терм на каждый класс, включая
  нулевой, — ровно то же решение и ровно та же форма, что у `bab_terms/2`
  (задача 3.16): расхождение двух разборов в одной панели читалось бы как баг.

  Порядок термов тот же, что у BAB: классы, потом эпик, — и лишь затем
  характеристика и прибавки. Классы плюс эпик и есть «базовый сейв», и
  разрывать их характеристикой значило бы прятать эту границу.

  ⚠️ **Эпический терм у сейвов не тот, что у атаки.** Эпические прибавки к
  сейвам идут на **чётных** уровнях персонажа (22, 24 … 40), а к атаке — на
  нечётных, поэтому на капе 41 у сейвов `+10`, а у BAB `+11` (CLAUDE.md §3).
  Число берётся из `stats.epic_save_bonus`, а не собирается здесь.

  Аргумент `total_with_epic` этой функции больше не нужен и снят: «база»
  выводилась из него вычитанием эпика, а классовые термы приходят посчитанными
  из ядра (`stats.save_breakdown`).
  """
  @spec save_summary_terms(map(), map(), DerivedStats.save(), atom(), integer()) :: [map()]
  def save_summary_terms(ruleset, %{save_breakdown: breakdown} = stats, save, ability, modifier) do
    class_terms = for term <- breakdown.by_class, do: save_class_term(ruleset, term, save)

    (class_terms ++
       [
         term_row("эпик", stats.epic_save_bonus),
         %{label: Labels.ability(ability), value: signed(modifier)}
       ])
    |> Enum.reject(&is_nil/1)
    |> Kernel.++(save_terms(ruleset, stats, save))
  end

  # ⚠️ Разбор читается **строго**, в отличие от прибавок ниже (`@save_extras`
  # с дефолтом `0`), и это не разнобой: слагаемое, которого ядро не отдаёт,
  # честно отсутствует, а вот классовая часть — это ОСНОВА числа. Не будь её,
  # подпись сложилась бы в «CON +0» под значением 22, то есть противоречила бы
  # тому, что объясняет. Та же строгость, что у `bab_terms/2`.
  #
  # ⚠️ Нулевой классовый терм печатается, а нулевой эпик — нет, и это не
  # непоследовательность: «Rogue 0 из 16» отвечает на вопрос «куда делись
  # шестнадцать уровней», а «эпик 0» не отвечает ни на что. То же правило
  # и та же пара, что у `bab_class_term/2`.
  defp save_class_term(ruleset, term, save) do
    %{
      label: save_class_label(ruleset, term, save),
      value: number(Map.fetch!(term.subtotals, save))
    }
  end

  defp save_class_label(ruleset, term, save) do
    name = Labels.class_name(ruleset, term.class)

    counted =
      if term.levels_ignored > 0,
        do: "#{term.levels_counted} из #{term.levels_taken}",
        else: "#{term.levels_counted}"

    case Labels.save_progression(Map.get(term.progressions, save)) do
      nil -> "#{name} #{counted}"
      word -> "#{name} #{counted} (#{word})"
    end
  end

  # The view screen's sentence, built from the exact list its popup twin
  # uses — see `terms_caption/1`'s note on why that matters.
  # Список, а не готовая строка: `card/5` соберёт из него и подпись, и разбор
  # списком. Имя оставлено близким к прежнему `save_from/5`, чтобы `git log`
  # по строке нашёлся, но возвращаемое изменилось — отсюда `_terms` в имени.
  defp save_card_terms(ruleset, stats, save, ability, modifier),
    do: save_summary_terms(ruleset, stats, save, ability, modifier)

  @doc """
  BAB по классам плюс эпик — разбор идеи Dan 04.08.2026 (AGENT_QUEUE.md §3.16):
  «показывать сумму классов? типа если у тебя 20 уровней воина, то
  `1 × fighter × 20`, а если какие-то уровни клерика, то `0.75 × cleric × 15`».

  До этой задачи у BAB была единственная строка `20 на 20-м + 10 эпических` —
  единственное крупное число панели без разбора по слагаемым, и **именно то,
  у которого разбор нужнее всех**: у мультикласса «какой класс сколько дал» и
  есть главный вопрос.

  🔴 **Печатаются ЗАСЧИТАННЫЕ уровни, а не взятые.** Классовые уровни после
  20-го в базовую атаку не идут вообще (CLAUDE.md §3, `Rules.Epic` правило 2),
  поэтому у `Воин 10 / Клирик 15 / Вор 16` при BAB 28 вклад вора — **ноль**, и
  строка «Rogue × 16» была бы прямым враньём: сумма разбора не сошлась бы
  со стоящим рядом числом. Отброшенные уровни при этом **названы вслух**
  (`Cleric 10 из 15`, `Rogue 0 из 16`), а не пропущены молча, — в этом и весь
  смысл разбора. Порядок взятия классов необратимо меняет результат, это самая
  дорогая ловушка мультикласса в NWN, а панель до сих пор печатала одно число
  и молчала.

  ⚠️ **Множителя тут нет, и это не упрощение.** `0.75` в данных не существует:
  у класса лежит метка `bab_progression`, а величина берётся из таблицы
  прогрессии. Плюс `0.75 × 15 = 11.25`, а вклад клирика — 11. Поэтому число —
  из таблицы (`term.subtotal`, посчитано ядром), а прогрессия — **словом рядом**,
  как пояснение: `Cleric 10 из 15 (средний)`. Слово выбирает
  `Labels.bab_progression/1`, там же записано, почему не коэффициент.

  ⚠️ Сиальские особенности видны сами: у монаха на шарде `bab_progression`
  переписан `medium → high` (`siala_41/classes.json`), и разбор печатает
  «(полный) 20», потому что читает **посчитанное по этому ruleset'у**, а не
  ванильную таблицу.

  Читает `stats.bab_breakdown` и только форматирует его: сумма живёт в
  `Rules.Progression.base/2`, где она и группируется по классам, — здесь
  не заводится ни одной новой арифметики (та же граница, что у `hp_terms/2`).
  """
  @spec bab_terms(map(), map()) :: [map()]
  def bab_terms(ruleset, %{bab_breakdown: breakdown}) do
    class_terms = for term <- breakdown.by_class, do: bab_class_term(ruleset, term)

    Enum.reject(class_terms ++ [term_row("эпик", breakdown.epic_term)], &is_nil/1)
  end

  # Эпик молчит на нуле — то же правило «нулевое слагаемое не несёт информации»,
  # что у всех остальных разборов панели. ⚠️ Классовые термы, наоборот, печатаются
  # И на нуле: «Rogue 0 из 16» — единственное, что объясняет, куда делись
  # шестнадцать уровней, и подавить его значило бы вернуть ту самую тишину,
  # ради которой задача и делалась.
  defp bab_class_term(ruleset, term) do
    %{label: bab_class_label(ruleset, term), value: number(term.subtotal)}
  end

  defp bab_class_label(ruleset, term) do
    name = Labels.class_name(ruleset, term.class)

    counted =
      if term.levels_ignored > 0,
        do: "#{term.levels_counted} из #{term.levels_taken}",
        else: "#{term.levels_counted}"

    case Labels.bab_progression(term.progression) do
      nil -> "#{name} #{counted}"
      word -> "#{name} #{counted} (#{word})"
    end
  end

  @doc """
  Правило «уровни после 20-го в BAB и сейвы не идут» — словами, для тех билдов,
  у которых оно сработало (задача 3.16).

  `nil`, пока у билда нет ни одного отброшенного уровня: у лестницы короче окна
  правило ничего не отнимает, и печатать его там значило бы шуметь. Разбор BAB
  (`bab_terms/2`) и разбор сейва (`save_summary_terms/5`) называют, **у кого**
  уровни отброшены; эта строка называет **правило**.

  ⚠️ **Единственный вызывающий — экран просмотра** (`BuildViewLive`,
  `#view-counted-window`), не конструктор. Задача 3.137 (Dan, 29.08.2026)
  убрала вызов из `Builder.TotalsPanel.panel_note("attack", …)`: там строка
  печаталась почти на каждом капнутом билде (включая одноклассовые, которым
  нечего сравнивать по порядку взятия классов) и переставала читаться,
  а разборы BAB/сейвов рядом и так называют отброшенные уровни поимённо.
  На экране просмотра тот же довод не действует — его открывает не только
  автор билда: «пришедший по ссылке не знает, почему у 40-уровневого мага
  2 атаки» (`BuildViewLive.mount/3`), и там разбор прячется за поп-ап, которого
  на экране просмотра вовсе нет (правило самого экрана — видно сразу, без
  наведения). Функцию не удаляли и не сужали — сузился только список мест,
  которые её зовут.
  """
  @spec counted_window_note(map()) :: String.t() | nil
  def counted_window_note(%{bab_breakdown: breakdown} = stats) do
    if levels_dropped?(stats) do
      "В BAB и спасы идут только первые #{breakdown.counted_levels} уровней персонажа — " <>
        "взятые позже не дают ни того, ни другого, поэтому порядок взятия классов " <>
        "меняет результат."
    end
  end

  # «Окно что-то отняло у этого билда» — один вопрос, одно место. Его задают и
  # строка про правило, и подпись атак/раунд, и обе обязаны молчать на одних
  # и тех же билдах: две копии условия разошлись бы, и правило печаталось бы
  # там, где подпись про него уже не говорит.
  defp levels_dropped?(%{bab_breakdown: breakdown}),
    do: Enum.any?(breakdown.by_class, &(&1.levels_ignored > 0))

  # «Атак / раунд» — не сумма слагаемых, а поиск по таблице от BAB, набранного
  # за засчитанные уровни, поэтому у строки остаётся подпись, а не поп-ап
  # с термами: список термов, который не складывается в стоящее рядом число,
  # был бы хуже подписи (`Fighter 10 + Cleric 7 + Rogue 0` даёт 17, а атак 4).
  #
  # ⚠️ Раньше подпись читалась «от BAB 17 на 20-м уровне» и умалчивала главное:
  # почему не от 28, которые написаны строкой выше. Эпик атак не добавляет
  # (CLAUDE.md §3, подтверждено тремя независимыми страницами Fandom) — и теперь
  # это сказано вслух, потому что именно на этом игрок теряет полбилда.
  #
  # ⚠️ И обе оговорки печатаются только там, где они что-то значат. У воина
  # 1-го уровня старая подпись выдавала «от BAB 1 **на 20-м уровне**» — фразу
  # про уровень, которого у персонажа нет; у билда короче окна засчитано всё,
  # и говорить про «первые 20» нечего.
  # ⚠️ И третий терм с 21.08.2026 (задача 3.72): у Сиалы есть класс, который
  # ванильное «атаки фиксируются BAB'ом на 20-м» ломает — Тайный лучник, +1
  # атака за каждые 10 уровней класса. Такой билд показывает число БОЛЬШЕ
  # табличного, и без второго терма подпись «от BAB 20» рядом с шестью атаками
  # читалась бы как ошибка калькулятора. Терм приходит из ядра
  # (`stats.attacks_per_round_terms`), а не собирается здесь по имени класса:
  # завтра шард допишет такое же правило другому классу, и подпись поедет сама.
  defp apr_caption(ruleset, stats) do
    from = "от BAB #{stats.base_attack_at_20}"

    from =
      if levels_dropped?(stats),
        do: "#{from} за первые #{stats.bab_breakdown.counted_levels} уровней",
        else: from

    from = from <> apr_extra_caption(ruleset, stats.attacks_per_round_terms)

    # «эпик (+11) атак не добавляет», а не «эпические +11 атак» — число тут
    # любое, а согласование с числительным в русском ломается на каждом
    # втором («+1 атак», «+22 атак»); в скобках оно ни с чем не согласуется.
    case stats.epic_attack_bonus do
      0 -> from
      epic -> "#{from}; эпик (+#{epic}) атак не добавляет"
    end
  end

  defp apr_extra_caption(_ruleset, []), do: ""

  defp apr_extra_caption(ruleset, terms),
    do:
      " + " <>
        Enum.map_join(terms, " + ", fn %{source: {:class, class}, attacks: attacks} ->
          "#{Labels.class_name(ruleset, class)} +#{attacks}"
        end)

  # Прибавки к атаке помимо базы и характеристики, каждая своим полем ядра и
  # с дефолтом `0`, — тот же приём, что у `@save_extras`: терм, которого ядро
  # не отдаёт, просто не появляется, и новый источник прибавки доезжает до
  # экрана без правки разметки.
  #
  # ⚠️ Собственных прибавок билда (`Epic prowess`, размерный модификатор мелкой
  # расы — задача 1.12b) здесь НЕТ намеренно: они приходят списком термов, у
  # каждого своё имя, и складывать их в безымянные «фиты +2» значило бы
  # выбросить единственное, что игрок может проверить. Тот же приём, что у
  # собственных термов сейвов и AC.
  #
  # ⚠️ `gear_attack_bonus` печатается отдельным термом **не всегда** — см.
  # `ab_terms/2`: у атаки этот механизм означает ровно прибавку модификатора
  # характеристики от вещей, и когда ядро говорит, что он вне капа, он входит
  # в терм самой характеристики, а не стоит рядом с ней вторым числом.
  #
  # ⚠️ Третья строка с 16.08.2026 (задача 3.35) — бонус ШАРДА за ТИП оружия
  # в руках. Он НЕ то же самое, что числа самого предмета (`weapon_terms/2`
  # рядом): те игрок вписывает и они вне капа, а этот шард даёт за то, что
  # в руках дальнобойное оружие, и он внутри капа. Подпись поэтому не «оружие»,
  # а «тип оружия» — иначе две строки читались бы как одно число, посчитанное
  # дважды. И это первый случай, когда кап +20 вообще достижим: раса +9 и тип
  # оружия +9 дают 18 из 20.
  @ab_extras [
    {:gear_attack_bonus, "вещи", :gear},
    {:race_attack_bonus, "раса", :racial_bonus},
    {:weapon_type_attack_bonus, "тип оружия", :weapon_bonus}
  ]

  @doc """
  AB, term by term: BAB, the governing ability's modifier — **named**,
  because `Weapon finesse` can move it to DEX and an attack bonus that
  quietly starts coming off a different ability looks like a bug unless the
  interface says so (CLAUDE.md §6) — the shard's racial bonus, and the build's
  own feats and class abilities by name.

  Reads exactly the fields `Rules.compute/2` already sums
  (`attack_bonus = base_attack + <ability modifier, naked> + attack_extra_bonus`,
  `rules.ex`) and nothing else, so there is exactly one place that formula
  lives. ⚠️ The **split** printed here is not the core's split term for term: what
  gear added to the ability rides inside the ability's own term (see below). The
  sum is identical, because the one is the difference of the other two.

  ## 🔴 Модификатор характеристики — ОДИН терм, вместе с вещами (задача 3.22)

  Наблюдение Dan 10.08.2026: в вещах стоит `STR +12`, и разбор печатал
  `STR +10` (голый модификатор) плюс отдельную строку `вещи +6`. Дословно:
  «В билде + вещах у меня 42 STR, логичнее было бы показать в итого „STR +16“,
  чем „STR +10“, „вещи +6“. Как бы оба бонуса от силы и надо бы их сплюсовать».

  ⚠️ **Довод сильнее вкуса: AB был единственным из трёх, кто так делал.** Сейвы
  зовут `save_summary_terms/5` с `stats.ability_modifiers` (не `..._naked`) и
  печатают `DEX +7` одним термом; `ac_geared_terms/2` — `база 10 · DEX +7`. И по
  правилу разбора «число рядом с именем игрок может проверить» прежний вид был
  хуже всего: `STR +10` не соответствовал **ни одной** цифре на экране — в панели
  стоит `STR 42`, то есть модификатор `+16`.

  Сумма при этом не меняется ни на единицу: `gear_attack_bonus` в ядре и есть
  разность двух модификаторов (`modifier(modifiers, ability) -
  modifier(naked_modifiers, ability)`, `rules.ex`), поэтому «голый + вещи» —
  это ровно `ability_modifiers[attack_ability]`.

  ⚠️ **Слить можно только пока вещи ВНЕ капа, и сторону мы спрашиваем у ядра**
  (`Caps.covers_source?/3`), а не решаем здесь. Порядок термов в этом разборе
  и ЕСТЬ утверждение о том, кого срезал потолок; терм, половина которого под
  капом, а половина поверх, поставить некуда, и слитая подпись стала бы врать
  о срезе. Поэтому у ruleset'а, кладущего вещи внутрь капа, разбор возвращается
  к двум термам — `STR` голым и `вещи` перед срезом. Это не мёртвая ветка:
  ровно так эта функция и работала до 10.08.2026.

  ⚠️ **Три прибавки, и потолок покрывает НЕ ВСЕ** (задачи 3.12, 1.12b, правки
  09.08 и 10.08.2026). Внутри капа остался ровно один источник — расовый бонус
  Сиалы («Этот бонус входит в кап атаки +20» на странице Светлого эльфа);
  прибавка от фита лежит поверх («Фиты не входят в кап атаки +20», Dan
  09.08.2026), и с 10.08.2026 поверх лежат вещи — Dan назвал состав капа
  списком, в котором модификатора силы нет ни из какого источника (`GAME_CHECKS.md`
  кейс J1). Всё внутрикапное печатается ДО среза, а сам срез стоит отдельным
  отрицательным термом «сверх капа» — ровно как у сейвов, и по той же причине:
  со срезанным итогом внутри одного из термов подпись не смогла бы сказать,
  сколько потерял каждый источник.

  ⚠️ **Порядок термов = сторона капа, и это не косметика.** Сначала БАЗА (BAB и
  характеристика — под кап она не попадает вовсе, потому что это не бонус: ровно
  этим и обосновано слияние выше), затем то, что потолок режет, затем сам срез,
  затем лежащее поверх него. Иначе строка «сверх капа −7» стоит под именем фита,
  который ничего не потерял, — то есть разбор обвиняет невиновного. До 09.08.2026
  порядок был обратный, и тогда он был верным: кап резал всё, и срез обязан был
  идти последним.

  ⚠️ Собственные термы названы **поимённо** (`Epic prowess +1`), а не строкой
  «фиты». Число рядом с именем игрок может проверить по вики; число рядом со
  «фиты» — только принять на веру. Тот же приём, что у `own_save_label/2`
  и `own_ac_label/2`.

  Whatever capped the total prints as the row's badge, the same way it
  already does for saves — the badge says *that* a ceiling bit, the last term
  says by how much (task 3.13's rule, CLAUDE.md §6).

  ## 🔴 Оружие в руках — с задачи 3.5 (часть B) это ТЕРМЫ, а не гэп

  ⚠️ Здесь стояло «Weapons are not modelled»: прибавка «выбранным оружием»
  (`Weapon focus`, `Epic weapon focus`, колонка Мастера оружия) не была термом
  вовсе, потому что `attack_bonus` её не складывал. Теперь складывает — в вещах
  выбирается оружие, и прибавка считается, когда оно совпадает с выбором фита.
  Плюс собственное число предмета: `Scimitar +5`. ⚠️ Их было два до задачи 3.52
  (`Scimitar (усиление) +3` рядом): усиление в игре у предмета есть, но
  отличалось оно только уроном, которого модель не считает.

  ⚠️ **Число оружия ВНУТРИ капа, а фиты на оружие — поверх**, и путать их нельзя:
  Dan назвал состав капа +20 списком, где attack/enchantment bonus оружия стоят
  первыми, а фиты не входят вовсе (`GAME_CHECKS.md` J1). Порядок термов это и
  печатает — число оружия ДО среза, фокусы ПОСЛЕ, — и сторону обоих читает ядро.

  ⚠️ Гэп никуда не делся, он стал **условным**: билд, не назвавший оружие (или
  назвавший, но с двумя фокусами, которым оружие однозначно не приписать),
  по-прежнему несёт `{:not_modelled, {:attack_bonus_weapon, id}}`. И
  `{:not_modelled, :attack_bonus_outside_weapon}` остался про то, чего поля нет
  вовсе: бонус к атаке с ДРУГИХ предметов, баффы и песня барда — в игре они
  наполняют тот же кап.

  ## 🔴 Штраф стиля боя — ПОСЛЕДНИЙ терм и МИМО капа (задача 3.132)

  «Многие билды берут 2 оружия вместо щита или двуручки … наличие оружия во
  второй руке влияет на АБ в главной» (Dan, 28.08.2026). Ядро уже складывает
  этот штраф в САМ `stats.attack_bonus` (`rules.ex`: `attack_bonus = base_attack
  + <ability modifier> + attack_extra_bonus + dual_wield_penalty.main`), а
  разбор до этой задачи о нём не знал ни строкой — то есть на любом билде
  с двумя оружиями сумма термов расходилась со своим же итогом на величину
  штрафа. Термы обязаны сходиться с числом, которое объясняют, поэтому здесь —
  ровно то слагаемое, которое рулесет добавляет: `stats.dual_wield.penalty.main`.

  ⚠️ Печатается только когда штраф не нулевой (`nil`/`0` — «одна рука», термов
  не прибавилось ни на один, старые билды выглядят как выглядели). И он не
  «под капом»/«над капом» — оба этих слова про `Rules.Caps`, а штраф стиля мимо
  него идёт по построению (`Rules.DualWield`: «потолки этого проекта
  односторонние… пропускать через них штраф значило бы либо не сделать ничего,
  либо сделать то, чего никто не писал»), поэтому стоит СНАРУЖИ и `terms_around_cap/3`,
  и всего, что знает о капе.
  """
  @spec ab_terms(map(), map()) :: [map()]
  def ab_terms(ruleset, stats), do: attack_terms(ruleset, stats, stats, style_penalty(stats))

  @doc """
  Разбор AB ВТОРОЙ руки — тем же языком, что у главной, просто источник
  термов — `stats.off_hand`, а не сам `stats` (задача 3.132). `nil`, когда
  второй руки нет вовсе — панель прячет строку целиком раньше, чем спросить
  разбор (`Builder.TotalsPanel`'s `panel_row_hidden?/2`), но функция не
  падает и сама, отвечая тем же `nil`, каким отвечает любой другой пробел.

  Читает `Rules.compute/2`'s `stats.off_hand` буквально: у него ЕСТЬ
  `own_attack_terms`, `weapon`/`weapon_attack_terms`, `gear_attack_bonus`,
  `race_attack_bonus`, `weapon_type_attack_bonus` и `attack_cap_clipped` —
  ровно те же имена полей, что у `stats` самого, — поэтому большая часть
  этой функции (`weapon_terms/2`, `@ab_extras`-цикл, `ab_clipped/1`) читает
  их ОДНОЙ и той же функцией для обеих рук: два имени поля, не два тела
  функции. Единственное, чего у второй руки НЕТ СВОЕГО, — общий на персонажа
  BAB (`stats.base_attack`) и общие модификаторы характеристик
  (`stats.ability_modifiers`/`_naked`, которые она может читать по СВОЕЙ
  `attack_ability`, но не своя пара чисел), поэтому они читаются у `stats`,
  а не у `stats.off_hand`.

  ⚠️ Штраф стиля здесь — `off_hand.style_penalty`, СВОЁ число: у второй руки
  он не обязан совпадать с главным (у `−4/−8` они разные, у `−2/−2` равны, и
  это арифметика конкретной ступени, а не правило).
  """
  @spec off_hand_ab_terms(map(), map()) :: [map()] | nil
  def off_hand_ab_terms(_ruleset, %{off_hand: nil}), do: nil

  def off_hand_ab_terms(ruleset, %{off_hand: off_hand} = stats),
    do: attack_terms(ruleset, stats, off_hand, off_hand.style_penalty)

  # Общее тело обеих рук. `source` несёт «свои» термы (главной руки — сам
  # `stats`, второй — `stats.off_hand`); `stats` передаётся отдельно, потому
  # что BAB и модификаторы характеристик общие на персонажа, а не на руку.
  defp attack_terms(ruleset, stats, source, style_penalty) do
    # Одним термом или двумя — решает СТОРОНА КАПА, и её знает ядро. Вне капа
    # прибавка от вещей неотличима по судьбе от голого модификатора, значит их
    # можно назвать одним числом; внутри капа — нельзя, см. ⚠️ в `ab_terms/2`.
    merged_gear? = not Caps.covers_source?(ruleset, :attack_bonus, :gear)

    own =
      for term <- Map.get(source, :own_attack_terms, []),
          do: {term.bonus, own_attack_label(ruleset, term), Map.get(term, :under_cap?, true)}

    # Сторону каждого механизма читаем у ядра, а не решаем здесь
    # (`Rules.Caps.covers_source?/3` через сами данные ruleset'а).
    extras =
      own ++
        weapon_terms(ruleset, source) ++
        for {field, label, cap_source} <- @ab_extras,
            not (merged_gear? and field == :gear_attack_bonus),
            value = extra_value(source, field, 0),
            value != 0,
            do: {value, label, Caps.covers_source?(ruleset, :attack_bonus, cap_source)}

    {under_cap, over_cap} = Enum.split_with(extras, fn {_value, _label, under?} -> under? end)

    ([
       %{label: "BAB", value: signed(stats.base_attack)},
       attack_ability_term(source, stats, merged_gear?)
     ] ++
       for(
         {value, label} <- terms_around_cap(source, under_cap, over_cap),
         do: %{label: label, value: signed(value)}
       ) ++
       style_penalty_term(style_penalty))
    |> Enum.reject(&is_nil/1)
  end

  # Штраф боя двумя оружиями главной руки — `0` у персонажа с одним оружием
  # (`stats.dual_wield == nil`, `Rules.DualWield`'s собственное умолчание).
  defp style_penalty(%{dual_wield: nil}), do: 0
  defp style_penalty(%{dual_wield: %{penalty: %{main: penalty}}}), do: penalty

  # Последний терм разбора, и печатается он, только когда что-то СНЯЛ —
  # «одна рука» и «стиль без штрафа» неотличимы по числу, и заводить
  # печатаемый нулевой терм значило бы шуметь на подавляющем большинстве
  # билдов, у которых оружие в руках вообще одно. Список из нуля или одного —
  # не `nil`/карта, потому что `attack_terms/4` дописывает его через `++`.
  #
  # ⚠️ Подпись — «бой двумя оружиями», а не «стиль боя» (запрос Dan 30.08.2026:
  # «может переименуем, чтобы название явно указывало, что минус идет из-за
  # оружий в обеих руках?»). Прежнее имя называло КАТЕГОРИЮ механики, а игроку
  # нужна ПРИЧИНА его числа: «стиль боя» одинаково подходит и к двуручному
  # хвату, и к стрельбе, то есть не отвечает на вопрос «почему у меня минус».
  defp style_penalty_term(0), do: []

  defp style_penalty_term(penalty),
    do: [%{label: "бой двумя оружиями", value: signed(penalty)}]

  # Срезаемое, срез, несрезаемое — в этом порядке, см. ⚠️ в `ab_terms/2`.
  defp terms_around_cap(source, under_cap, over_cap) do
    drop_flag = fn terms -> for {value, label, _under?} <- terms, do: {value, label} end

    drop_flag.(under_cap) ++ ab_clipped(source) ++ drop_flag.(over_cap)
  end

  # Числа оружия — терм на каждое вписанное, и подписаны они ИМЕНЕМ ОРУЖИЯ:
  # «Scimitar +5». Не «оружие +5», потому что игрок вписал число у конкретного
  # предмета и обязан узнать его обратно (то же правило, по которому собственные
  # термы названы поимённо, а не «фиты»). ⚠️ Терм на КАЖДОЕ число, а не одно на
  # оружие: сколько их, объявляют данные, и до задачи 3.52 их было два.
  #
  # ⚠ Сторона капа берётся у ТЕРМА, а не спрашивается здесь второй раз: ядро уже
  # прочитало её у данных (`Rules.GearWeapon`), и второе чтение — это вторая копия
  # решения о том, кого срезал потолок.
  #
  # ⚠ `source` — ровно то, что несёт `ab_terms/2`/`off_hand_ab_terms/2`: у
  # обеих рук поля называются одинаково (`weapon`, `weapon_attack_terms`), так
  # что вторая рука читается этой же функцией, без второго тела.
  defp weapon_terms(ruleset, source) do
    name = Labels.weapon_name(ruleset, Map.get(source, :weapon))
    terms = Map.get(source, :weapon_attack_terms, [])

    for term <- terms do
      {term.bonus, weapon_term_label(name, term.kind, length(terms)),
       Map.get(term, :under_cap?, true)}
    end
  end

  # ⚠️ Суффикс появляется РОВНО ТОГДА, когда чисел у предмета больше одного,
  # и ни имени вида, ни их количества здесь не зашито: и то, и другое объявляют
  # данные (`gear.weapon_bonus_kinds`). До задачи 3.52 видов было два, и второй
  # печатался как «Scimitar (усиление)»; сегодня вид один и голое имя
  # однозначно. Заведёт шард второй — обе строки подпишутся своим ключом, а не
  # сольются в две одинаковые «Scimitar».
  defp weapon_term_label(name, _kind, 1), do: name
  defp weapon_term_label(name, kind, _several), do: "#{name} (#{kind})"

  # Имя источника, не «фиты». Класс подписан словом — колонка таблицы класса и
  # фит этого класса читаются иначе; всё остальное (фит, расовая склонность,
  # навык) называется своим именем из ruleset'а.
  defp own_attack_label(ruleset, %{source: {:class, id}}),
    do: "#{Labels.class_name(ruleset, id)} (класс)"

  defp own_attack_label(ruleset, %{source: {:skill, id}}), do: Labels.skill_name(ruleset, id)

  defp own_attack_label(ruleset, %{source: {_feat_or_race, id}}),
    do: Labels.feat_name(ruleset, id)

  # Сколько отняли потолком — берём у ядра (`attack_cap_clipped`), а не вычитаем
  # сами. ⚠️ Раньше здесь стояла разность `attack_extra_bonus` и суммы всех
  # напечатанных термов, и с 09.08.2026 это было бы неверно: кап покрывает не все
  # источники, поэтому разность включила бы прибавку от фита, которую никто не
  # резал. Отсутствие поля означает «не срезано», а не «срезано всё».
  #
  # ⚠ Читает `source` — у второй руки СВОЁ `attack_cap_clipped` (задача 3.132),
  # не то же, что у главной: усиление оружия у рук разное, и кап может кусать
  # одну руку там, где не кусает другую.
  defp ab_clipped(source) do
    case extra_value(source, :attack_cap_clipped, 0) do
      0 -> []
      over -> [{over, "сверх капа"}]
    end
  end

  # `nil` only when the ruleset states no default ability at all
  # (`{:missing_data, :attack_ability_rules}` in `ruleset.gaps` says so) — the
  # modifier such a build gets is 0 either way (`rules.ex`'s own `modifier/2`
  # fallback), so leaving the term out keeps the sum honest without a special
  # case here. ⚠️ И прибавка от вещей у такого билда тоже ноль — она сама
  # разность двух модификаторов той же характеристики, — поэтому слитый терм
  # ничего не уносит с экрана.
  defp attack_ability_term(%{attack_ability: nil}, _stats, _merged_gear?), do: nil

  # Слитый терм читает модификатор **с вещами** — то самое число, что стоит
  # у характеристики в панели (STR 42 → +16). Голый читается только тогда, когда
  # вещи обязаны стоять отдельным термом перед срезом (задача 3.22).
  #
  # ⚠ `source` называет ХАРАКТЕРИСТИКУ (своя у каждой руки — задача 3.132, Zen
  # archery меняет её только там, где в руках дальнобойное), а МОДИФИКАТОРЫ
  # читаются у `stats`: характеристики персонажа общие на обе руки, второй
  # копии `ability_modifiers` у `off_hand` нет и не должно быть.
  defp attack_ability_term(%{attack_ability: ability}, stats, merged_gear?) do
    modifiers =
      if merged_gear?, do: stats.ability_modifiers, else: stats.ability_modifiers_naked

    %{label: Labels.ability(ability), value: signed(Map.get(modifiers, ability, 0))}
  end

  @doc """
  «AC голым» — no gear at all, dexterity included (`ac_naked = base_ac +
  <dex, naked>`, `rules.ex`) — so "голым" keeps meaning naked.

  What the build earns by itself is here too, named one by one (task 3.11): a
  Monk's wisdom and class table, a Pale Master's `Bone skin`, `Armor skin`,
  Tumble's ranks. ⚠ They belong in the **naked** number and not only in the
  geared one — a class ability is not equipment, and leaving them out would
  make "голым" mean "with nothing at all".

  ⚠ A small race's size modifier was named here too until task 3.143
  (30.08.2026): its condition ("when dealing with larger creatures") had been
  read off a quote truncated one clause short, and the fix moved it to
  `not_modelled` — it earns no term at all now, naked or geared.

  What is still short has a gap of its own (`{:not_modelled, {:ac_bonus, …}}`
  and friends, shown outside this popup) rather than a silently absent term:
  combat modes, activated abilities, bonuses against one kind of enemy.
  """
  @spec ac_naked_terms(map(), map()) :: [map()]
  def ac_naked_terms(ruleset, stats) do
    [
      %{label: "база", value: Integer.to_string(ruleset.base_ac)},
      %{label: "DEX", value: signed(stats.ability_modifiers_naked.dex)}
    ] ++ own_ac_terms(ruleset, stats.ac_own_terms)
  end

  # Имя источника, а не «классовое +12»: число рядом с `Monk AC bonus` игрок
  # может проверить, число рядом с «классовое» — только принять на веру. Ровно
  # то же решение, что у разбора HP по фитам (`feat_terms/2`).
  #
  # ⚠️ Форма — ровно `%{label:, value:}`, и это чужой контракт: список
  # уезжает клиенту как JSON в `data-pop-terms` (`BuilderComponents.stat_pop/1`,
  # задача 3.13), и лишний ключ там не декорация, а лишний байт на КАЖДОЙ из
  # семи строк панели итогов на КАЖДОМ рендере. `ac_own_cascade_terms/2`
  # (задача 3.59B), которому нужен стабильный `id` для DOM, строит СВОЙ список
  # из тех же самых термов, а не расширяет этот.
  defp own_ac_terms(ruleset, terms) do
    for term <- terms, do: %{label: own_ac_label(ruleset, term), value: signed(term.ac)}
  end

  # У классовой таблицы монаха своё имя: фит `Monk AC bonus` даёт мудрость, а
  # колонка таблицы — «+1 за каждые 5 уровней», и это две разные строки. Назвать
  # обе именем фита значило бы напечатать одно имя дважды с разными числами.
  defp own_ac_label(ruleset, %{source: {:class, id}}),
    do: "#{Labels.class_name(ruleset, id)} (класс)"

  defp own_ac_label(ruleset, %{source: {:skill, id}}), do: Labels.skill_name(ruleset, id)

  # ⚠️ Раса — своя ветка, а не хвост общей. `{:race_feat, id}` несёт id ФИТА
  # (`Small stature`), а `{:race, id}` — id САМОЙ расы, и `feat_name/2` напечатал
  # бы для него `gnome`: неизвестный id этот справочник отдаёт как есть.
  # Это бонус расы Сиалы (задача 3.12), и подписан он именем расы.
  defp own_ac_label(ruleset, %{source: {:race, id}}), do: Labels.race_ru(ruleset, id)

  # И то же самое со стороны оружия (задача 3.35): щитовой AC за КЛИНКОВОЕ
  # оружие в руках. Подписан именем оружия — у Карлика с мечом на экране две
  # строки щитового AC по +9, и без имён они читались бы как один бонус,
  # напечатанный дважды.
  defp own_ac_label(ruleset, %{source: {:weapon, id}}), do: Labels.weapon_name(ruleset, id)

  # ⚠️ Характеристика дописана в скобках («Monk AC bonus (WIS)»), тем же
  # приёмом, что и у сейвов (`save_ability_hint/2` рядом, «Divine grace (CHA)»,
  # задача 3.59B). Без неё «+4» рядом с именем фита не объясняет, откуда взялась
  # четвёрка: игрок, наведший на класс ради AC от мудрости, видит английское имя
  # фита и число, а не то, что оно и есть его мод WIS.
  defp own_ac_label(ruleset, %{source: {_feat_or_race, id}}),
    do: "#{Labels.feat_name(ruleset, id)}#{ac_ability_hint(ruleset, id)}"

  defp ac_ability_hint(ruleset, id) do
    ruleset
    |> Bonuses.applied(:ac_bonuses)
    |> Enum.find(&(&1.id == id))
    |> case do
      %{amount: %{kind: :ability_modifier, ability: ability}} -> " (#{Labels.ability(ability)})"
      _ -> ""
    end
  end

  @doc """
  «AC в шмоте» — the same base and DEX (this time with gear's contribution
  to it), plus what every AC type the player typed under "Вещи" actually
  **contributed** (`ac_by_type`).

  ⚠ Contributed, not typed, and since task 3.39 the two differ: inside one type
  a typed number does not add to what the build earns itself, it competes with
  it and the larger wins. So a type the player typed and lost on prints no row
  at all — the same `value != 0` filter that already hid an untouched type — and
  the losing side is named outside this popup, in the gap
  `{:not_modelled, {:ac_gear_base, …}}` and in the gear block's own row. A row
  showing the number typed while the total does not contain it would be a
  breakdown that disagrees with its own answer.

  A capped type prints its clipped value here; the row's own badge (wired the
  same way AB's and the saves' already are) is what says a ceiling was hit, not
  a term in this list (task 3.13's rule — see `ab_terms/2`'s note).

  The build's own bonuses are terms here too, and recomputed against the
  **geared** ability scores rather than reused from the naked list: `Monk AC
  bonus` is worth whatever wisdom is worth, so `+12 WIS` off items is `+6`
  here and not in the line above.

  ⚠ A term the naked list carried and this one does not print as a **zero
  row**, not as nothing (task 3.59B): a Monk in a leather jerkin loses both
  his own terms to `Rules.ArmorClass`'s `no_ac_from_worn` scope, and «AC в
  шмоте» coming out *lower* than «AC голым» with no line saying why reads as
  the calculator being wrong rather than as the shard's own rule. See
  `lost_own_ac_terms/2`.
  """
  @spec ac_geared_terms(map(), map()) :: [map()]
  def ac_geared_terms(ruleset, stats) do
    [
      %{label: "база", value: Integer.to_string(ruleset.base_ac)},
      # ⚠️ Дошедшая ловкость, а не сам модификатор (задача 3.41): надетый доспех
      # ставит потолок бонусу ловкости **к AC**, и разбор обязан печатать то, что
      # в число вошло, — иначе он не сойдётся со своим итогом ровно у того, кто
      # надел латы. Строка «почему меньше» стоит рядом с полем ввода в блоке
      # «Вещи», а не здесь: тут термы, а не объяснения.
      %{label: "DEX", value: signed(ac_dexterity(stats))}
    ] ++
      own_ac_terms(ruleset, stats.ac_own_terms_geared) ++
      lost_own_ac_terms(ruleset, stats) ++
      for {type, value} <- stats.ac_by_type, value != 0 do
        %{label: Labels.ac_type(ruleset, type), value: signed(value)}
      end ++ ac_clipped(stats)
  end

  @doc """
  The same «own» terms `ac_geared_terms/2` folds into its popup, exposed
  separately for the narrower cascade line under «Вещи» (task 3.59B,
  `#gear-ac-total`).

  That line used to print one summed number — `{signed(own)} своих` — and Dan
  mistook it for the Monk's own column on his own build: it was Tumble, 40
  ranks at +1 per 5, the same arithmetic shape the Monk's class table uses («+1
  за каждые 5»), and a bare sum cannot tell the two apart. Named per source,
  the same way the popup already is, the line stops needing to be decoded.

  Unlike `own_ac_terms/2`'s own shape, every term here also carries `id` — the
  cascade line renders as static markup rather than travelling through a hook's
  JSON, and each term needs a DOM id of its own (`gear-ac-own-N-\#{id}`) so a
  test — or a future reader — can address «this is the Monk's, that one is
  Tumble's» rather than the paragraph as a whole.

  ⚠ The clip term (`stats.ac_cap_clipped`, `0` on every ruleset that ships
  today) is built here rather than borrowed from `ac_clipped/1`: that helper's
  contract belongs to the popup, and giving it an `id` too would be the same
  mistake `own_ac_terms/2`'s doc warns against — widening a shape a different
  reader already depends on. A list that stopped summing to its own total the
  day a `dodge`-typed applied bonus arrives would be a worse bug than the one
  this task is fixing, so the clip rides along regardless.
  """
  @spec ac_own_cascade_terms(map(), map()) :: [map()]
  def ac_own_cascade_terms(ruleset, stats) do
    own =
      for term <- stats.ac_own_terms_geared,
          do: %{id: term.id, label: own_ac_label(ruleset, term), value: signed(term.ac)}

    case Map.get(stats, :ac_cap_clipped, 0) do
      0 -> own
      over -> own ++ [%{id: :ac_cap_clip, label: "сверх капа", value: signed(over)}]
    end
  end

  # Собственные термы, которые «AC голым» видел, а «AC в шмоте» — нет:
  # `Rules.ArmorClass` не занизил их до нуля, а не положил в список вовсе
  # (`terms/3`'s own doc), потому что надетое нарушило scope `no_ac_from_worn`.
  #
  # ⚠ Веб-слой здесь не ПРОВЕРЯЕТ условие заново — это была бы вторая копия
  # правила, которую CLAUDE.md запрещает, — а только НАЗЫВАЕТ то, что ядро уже
  # решило: сверяет id термов из голого списка с id термов из одетого и, для
  # пропавших, читает саму запись разметки (`Bonuses.applied(ruleset,
  # :ac_bonuses)`, та же, что уже читает `ac_ability_hint/2` выше).
  #
  # ⚠ Отличить эту причину пропажи от другой (столкновение типов, задача 3.39 —
  # уже названо строкой `#gear-ac-superseded`) можно без всякой хитрости: у
  # обоих монашеских термов `type: nil` (`_type_decision` в `ac_bonuses.json`),
  # а собственные бонусы БЕЗ типа со столкновением `own_by_type/1` в ядре
  # вообще не сталкивает — значит пропасть они могут только через scope.
  # Проверка `blocked != []` — не костыль под этот факт, а её собственное
  # необходимое и достаточное условие: `in_scope?/3` возвращает false ровно
  # тогда, когда надетое хотя бы одного из названных типов несёт базу — то
  # самое число, которое здесь читается из `stats.ac_types_resolved`
  # (`Rules.Worn.base_ac/2`, уже посчитанное ядром), а не пересчитывается заново.
  defp lost_own_ac_terms(ruleset, stats) do
    scoped =
      for record <- Bonuses.applied(ruleset, :ac_bonuses),
          match?(%{kind: :no_ac_from_worn}, record.scope),
          do: record

    still_counted = MapSet.new(stats.ac_own_terms_geared, & &1.id)
    worn_base = Map.new(stats.ac_types_resolved, &{&1.type, &1.base})

    for record <- scoped,
        record.id not in still_counted,
        naked_term = Enum.find(stats.ac_own_terms, &(&1.id == record.id)),
        not is_nil(naked_term),
        blocked =
          for(
            type <- record.scope.ac_types,
            Map.get(worn_base, type, 0) > 0,
            do: Labels.ac_type(ruleset, type)
          ),
        blocked != [] do
      why = "не работает (надето: #{Enum.join(blocked, ", ")})"
      %{label: "#{own_ac_label(ruleset, naked_term)} — #{why}", value: "0"}
    end
  end

  # Ловкость, дошедшая до «AC в шмоте». `Map.get/3` со своим дефолтом, как и
  # у `ac_cap_clipped` ниже: этот модуль зовут и с сохранёнными наборами статов,
  # у которых поля может не быть.
  defp ac_dexterity(stats) do
    case Map.get(stats, :ac_dexterity) do
      %{counted: counted} -> counted
      _absent -> stats.ability_modifiers.dex
    end
  end

  # Сколько потолок ТИПА отнял у собственной стороны билда — берётся у ядра
  # (`ac_cap_clipped`), как и у атаки, а не вычитается здесь разностью.
  # ⚠️ Сегодня это всегда 0: применяемых прибавок капнутого типа в данных нет
  # ни одной. Строка стоит не «на будущее», а чтобы разбор не разошёлся со своим
  # итогом молча в тот день, когда такая запись появится, — ровно то, ради чего
  # ядро несёт это число отдельным полем.
  defp ac_clipped(stats) do
    case Map.get(stats, :ac_cap_clipped, 0) do
      0 -> []
      over -> [%{label: "сверх капа", value: signed(over)}]
    end
  end

  @doc """
  HP, by class, plus CON — for the totals panel's popup, `nil` exactly when
  `stats.hp` itself is (a class with no hit die in the data, `progression.ex`).

  Reads `stats.hp_breakdown` and only formats it: `Rules.Progression.hit_points/3`
  is where the actual sum lives, grouped by class already, term by term
  guaranteed to add up to `hp` (see its own doc — this function invents no
  arithmetic of its own, only names each field).

  ⚠️ **Mini-sets add +15…+91% to HP and are not modelled at all** (CLAUDE.md
  §3) — comparing this breakdown's total against a wiki build's HP only ever
  works against the "голым" number, and there is no term here for the
  difference because there is no honest one to name.

  Feats that add hit points **are** in the total and are named here one by one
  (task 1.9): `Toughness` at one per character level — handed out free by nine
  classes on Siala, so it is on almost every martial build — and `Epic
  toughness` at twenty per take. What is still missing has a gap of its own
  (`{:not_modelled, {:feat_hp_bonus, …}}`, shown outside this popup) rather
  than a silently absent term. ⚠ Here stood two examples — `Deathless vigor`
  and the Red Dragon Disciple's growing die — and both are counted now (D1 on
  13.08.2026, task 3.37 on 16.08.2026), so nothing is missing from this popup
  on any build today. That is a fact about the data, not about this function.

  So is «Дух Сиалы» (task, волна 12, 09.08.2026) — a flat +20 every character
  on Siala carries, right after CON and before any feat term: it is not a
  feat (`breakdown.innate`, never `breakdown.by_feat`), so `innate_term/1`
  reads its name straight off the ruleset fact rather than through
  `Labels.feat_name/2`. Absent (and therefore silent here) under the vanilla
  ruleset, where `breakdown.innate` is `nil`.
  """
  @spec hp_terms(map(), map()) :: [map()] | nil
  def hp_terms(_ruleset, %{hp_breakdown: nil}), do: nil

  def hp_terms(ruleset, %{hp_breakdown: breakdown} = stats) do
    by_class =
      for entry <- breakdown.by_class do
        %{
          label: "#{Labels.class_name(ruleset, entry.class)} #{entry.levels} (#{dice(entry)})",
          value: Integer.to_string(entry.subtotal)
        }
      end

    con_term = %{label: "CON × #{stats.character_level} ур.", value: signed(breakdown.con_term)}

    by_class ++
      [con_term] ++
      innate_term(breakdown.innate) ++
      feat_terms(ruleset, breakdown) ++ floor_term(breakdown.floor_adjustment)
  end

  # `d10`, или `d6×3 + d8×2 + d10×5` там, где хит-дайс класса растёт с его
  # уровнем (`red dragon disciple`, задача 3.37). Печатать у него одно число
  # нельзя ни одно из четырёх: `subtotal` рядом ни на одно из них не делится,
  # а разбор, не сходящийся со своим итогом, хуже отсутствующего (CLAUDE.md §6).
  # Число уровней на каждом дайсе названо, потому что без него `d6 + d8 + d10`
  # выглядит как сумма трёх бросков, а не как форма лестницы.
  defp dice(%{hit_dice: [%{die: die}]}), do: "d#{die}"

  defp dice(%{hit_dice: dice}) do
    Enum.map_join(dice, " + ", fn %{die: die, levels: levels} -> "d#{die}×#{levels}" end)
  end

  # «Дух Сиалы» carries its own Russian name in the ruleset fact — the same
  # reason a race's `ru` name is shown as printed rather than looked up
  # (CLAUDE.md §4): the mechanic has no `ruleset.feats` entry to resolve
  # through `Labels.feat_name/2`, and giving it one would let the interface
  # treat a bonus nobody picks as a feat somebody could. `[]` when there is
  # none — vanilla, or (structurally impossible here, since `hp_breakdown` is
  # `nil` on a level-less build) no character at all.
  defp innate_term(nil), do: []
  defp innate_term(%{ru: ru, amount: amount}), do: [%{label: ru, value: signed(amount)}]

  # Именем фита, а не «фиты +61»: число рядом с `Toughness` игрок может
  # проверить, число рядом с «фиты» — только принять на веру. Число взятий
  # печатается там, где оно есть (`Epic toughness ×3`), потому что без него
  # 60 выглядит как чужая цифра.
  defp feat_terms(ruleset, breakdown) do
    for entry <- Map.get(breakdown, :by_feat, []) do
      takes = if entry.takes > 1, do: " ×#{entry.takes}", else: ""
      cap = if entry.capped?, do: " (потолок)", else: ""

      %{
        label: "#{Labels.feat_name(ruleset, entry.feat)}#{takes}#{cap}",
        value: signed(entry.subtotal)
      }
    end
  end

  # 0 on every build that was not deliberately pushed onto the one-hit-point
  # floor (`Rules.Progression.hit_points/3`'s own doc) — named only when it
  # actually fired, the same zero-suppression every other term list here
  # already uses.
  defp floor_term(0), do: []
  defp floor_term(n), do: [%{label: "минимум 1 HP/уровень", value: signed(n)}]

  # Прозой, а не списком: складывать нечего — у одного из классов нет
  # хит-дайса, и числа нет вовсе. ⚠ С 16.08.2026 (задача 3.37) такого класса
  # в корпусе нет: у Ученика красного дракона хит-дайс есть, растущий. Ветка
  # живёт, потому что живёт отказ `Progression.hit_points/3`, и проверяется
  # на ruleset'е с вынутым фактом (`summary_test.exs`).
  defp hp_card_terms(_ruleset, %{hp_breakdown: nil}),
    do: "нет хит-дайса у одного из классов — см. пробелы ниже"

  defp hp_card_terms(ruleset, stats), do: hp_terms(ruleset, stats)

  @doc """
  Ворота показа SR — 12+ уровней МОНАХА персонажа, а не пустой список термов
  и не владение `Diamond soul` (задача 3.45, заход 2; Dan 18.08.2026: «Чисто
  SR выводим для билдов с 12+ уровнями монаха и на этом все»).

  Единственное место, которое это решает — обе панели (итоги конструктора,
  `stat_cards/2` экрана просмотра) зовут её, чтобы ворота не разъехались.
  `Rules.SpellResistance` отдаёт число и термы ВСЕГДА (задача 3.45, заход 1):
  видимость строки — вопрос интерфейса, не ядра.

  ⚠️ Не «термов не пусто»: фит можно объявить владением с вещи
  (`Rules.GearFeats`), и тогда билд без единого уровня монаха несёт терм
  `Diamond soul` и `spell_resistance: 10` — источник называет это число сам
  («any character without monk levels will only gain spell resistance 10»),
  а строку про него на этом экране Dan не просил.
  """
  @spec spell_resistance_visible?(map()) :: boolean()
  def spell_resistance_visible?(stats), do: Map.get(stats.class_levels, :monk, 0) >= 12

  @doc """
  Разбор SR по слагаемым — та же форма и та же грамматика, что у `feat_terms/2`
  внутри `hp_terms/2` выше: `Diamond soul +45`, `Improved spell resistance ×9
  +18`, и `(потолок)` там, где сработал потолок ЭФФЕКТА одной прибавки
  (не потолок стата — его у SR нет ни на одном ruleset'е, `_cap_decision`
  в `priv/rules/vanilla/feat_spell_resistance.json`).

  ⚠️ Терм не несёт имени класса и его уровня («Монах 35 → 45») — сознательное
  решение ядра (задача 3.45, заход 1) ради единой грамматики панели итогов;
  захочет веб такую строку — это поле `Rules.SpellResistance.term_entry()`,
  а не вывод из `stats.class_levels` здесь.
  """
  @spec spell_resistance_terms(map(), map()) :: [map()]
  def spell_resistance_terms(ruleset, stats) do
    for entry <- Map.get(stats, :spell_resistance_terms, []) do
      takes = if entry.takes > 1, do: " ×#{entry.takes}", else: ""
      cap = if entry.capped?, do: " (потолок)", else: ""

      %{
        label: "#{Labels.feat_name(ruleset, entry.id)}#{takes}#{cap}",
        value: signed(entry.spell_resistance)
      }
    end
  end

  # Не карточка «SR 0» / «SR ?», а НИ ОДНОЙ карточки, пока билд не набрал
  # 12 уровней монаха (`spell_resistance_visible?/1`) — список, а не `if`
  # внутри `card/5`, тем же приёмом, что уже решает `ac_geared_card/2` ДО
  # вызова `card/5`, а не внутри него. `++` в `stat_cards/2` ниже — тот же
  # приём, что уже склеивает подсписки термов в `hp_terms/2`.
  defp spell_resistance_cards(ruleset, stats) do
    if spell_resistance_visible?(stats) do
      [
        card(
          "spell_resistance",
          "SR",
          number(stats.spell_resistance),
          spell_resistance_terms(ruleset, stats)
        )
      ]
    else
      []
    end
  end

  @doc """
  Группы классов Сиалы, к которым относится билд — «Воины Сагры», «Воины Адры»
  (запрос Dan 08.08.2026).

  Отвечает на вопрос, которым игроки шарда думают о билдах: не «сколько у меня
  BAB», а «сагровик я или нет». Считает не веб-слой — ядро
  (`stats.class_groups`, `BuildCalculator.Rules.ClassGroups`); здесь только
  подписи.

  Отдаёт `%{id:, name:, title:, assumed?:}`:

    * `name` — имя группы **по-русски**, из данных (заголовок её страницы).
      Это не игровая сущность в смысле §4, а название группы со страницы шарда:
      английского имени у неё не существует нигде, и выдумать его нельзя;
    * `title` — почему флажок стоит: имена классов группы **по-английски**
      (§4 — их печатает движок) и правило чистоты словами;
    * `assumed?` — правило чистоты у этой группы **не написано никем**, и мы
      применили правило Сагры. ⚠️ Обязано доезжать до экрана: «сагровик»
      прочитан дословно и `verified`, «адровец» выведен по аналогии, и показать
      два разных по качеству факта одинаково значило бы соврать про второй.

  ⚠️ Что группа **даёт**, тут не печатается ни словом, и это не изменилось
  25.08.2026, когда выгоды Адры перестали быть неизвестными (Dan: «позволяет
  пить зелья адры»). Здесь стояло «про Адру — ничего, и намёк на выгоды был бы
  выдумыванием игровых правил»: довод устарел, решение — нет. Печатать нечего
  по другой причине — и у Сагры, и у Адры это расходники, то есть механика,
  про которую калькулятор не отвечает вовсе; Dan просил оставить сам флажок,
  а не рассказ о выгодах.

  ⚠️ Гэпов про группы у билда с 25.08.2026 не бывает ни одного
  (`Rules.ClassGroups.gaps/2`), то есть эта функция осталась единственным
  местом, где группа вообще попадает на экран.
  """
  @spec class_group_flags(map(), map()) :: [map()]
  def class_group_flags(ruleset, stats) do
    for group <- Map.get(stats, :class_groups, []) do
      %{
        id: group.id,
        name: group.name || to_string(group.id),
        title: class_group_title(ruleset, group),
        assumed?: not group.purity_stated?
      }
    end
  end

  # Имена классов — английские и через « · », как в лестнице уровней. Правило
  # чистоты названо словами того файла, из которого прочитано: «любой другой
  # класс в билде нивелирует преимущества».
  defp class_group_title(ruleset, group) do
    classes = Enum.map_join(group.classes, " · ", &Labels.class_name(ruleset, &1))

    rule =
      if group.purity_required?,
        do: "Все уровни билда — из этих классов; один уровень любого другого отменяет группу.",
        else: "Достаточно хотя бы одного уровня из этих классов."

    assumed =
      if group.purity_stated?,
        do: "",
        else: " ⚠ Правило чистоты у этой группы на вики не описано — применяем правило Сагры."

    "#{classes}. #{rule}#{assumed}"
  end

  @doc """
  Справка к посчитанному расовому бонусу — и **куда именно её вешать**
  (задача 3.102, решение Dan 25.08.2026).

  Возвращает `%{text:, group:, skill:}` или `nil`. `text` — предложение
  (`Labels.racial_bonus_note/2`, слово в слово то же, что печаталось гэпом
  до этой задачи); `group` и `skill` называют получателя, и ровно один из них
  не `nil`:

    * `group` — ключ группы панели итогов (`TotalsPanel`'s `@panel_layout`),
      в которой стоит число: `"attack"` у бонуса к атаке Светлого эльфа,
      `"vital"` у щитового AC Карлика;
    * `skill` — id навыка, у Человека это Discipline. Своя строка панели
      и своя карточка, а не одна из групп выше.

  ## Почему не терм разбора и не поп-ап

  ⚠️ **Не терм.** Форма терма — ровно `%{label:, value:}`, и это чужой
  контракт: список уезжает клиенту как JSON в `data-pop-terms`
  (`BuilderComponents.stat_pop/1`), а рисует его `renderTerms` двумя узлами,
  подпись и число. Предложение на 300 знаков там негде поставить, не
  расширив ни форму, ни хук.

  ⚠️ **И не поп-ап целиком, даже расширенный.** Хук `.StatPop` навешивается
  только выше порога `matchMedia("(max-width: 940px)")` — на телефоне он
  не монтируется вовсе, то есть справка исчезла бы с мобильного экрана
  начисто. Мобильный обязателен наравне с десктопом (CLAUDE.md §1), поэтому
  справка печатается строкой и видна без наведения — тем же приёмом, каким
  уже печатаются `.sgroup-note` (вклад Spellcraft в сейвы) и `.skill-note`
  (`без прибавки от Skill focus`).

  ⚠️ Получатель берётся у `kind` записи ядра, а не угадывается по расе: какая
  раса что получает — данные (`ruleset.racial_bonuses`), и второе написание
  этого факта разошлось бы с первым ровно так же, как разошлись бы два
  описания одной суммы.
  """
  @spec racial_bonus_note(map(), map()) ::
          %{text: String.t(), group: String.t() | nil, skill: atom() | nil} | nil
  def racial_bonus_note(ruleset, stats) do
    bonus = Map.get(stats, :racial_bonus)

    case {Labels.racial_bonus_note(ruleset, bonus), bonus} do
      {nil, _bonus} -> nil
      {text, %{kind: :skill_bonus, skill: skill}} -> note(text, nil, skill)
      {text, %{kind: :shield_ac}} -> note(text, "vital", nil)
      {text, %{kind: :attack_bonus}} -> note(text, "attack", nil)
      # Вид бонуса, который ядро считает, а панель ещё не знает, куда положить.
      # Сегодня таких нет — `Rules.RacialBonus`'s `@modelled_kinds` перечисляет
      # ровно три, — и ветка не декоративная: она отдаёт справку БЕЗ адреса,
      # а не роняет её, чтобы новый вид бонуса не исчез с экрана молча.
      {text, _other} -> note(text, "vital", nil)
    end
  end

  defp note(text, group, skill), do: %{text: text, group: group, skill: skill}

  @doc """
  Финальные характеристики для сводки панели итогов — разбор по источникам,
  поимённо, тем же приёмом, каким `skill_rows/3` уже разбирает значение
  навыка (CLAUDE.md §6, задача 3.2): «база → раса → уровни → вещи», в
  порядке каскада, а не одним свёрнутым числом.

  Читает `Abilities.breakdown/2` и только форматирует то, что оно уже
  посчитало — сумма термов и есть `score`, просто не свёрнутая в одно число.
  ⚠️ Задача 3.1 добавила пятое слагаемое — прибавки, которые билд заработал
  сам (`Great strength` и семья, таблица Ученика красного дракона), — и оно
  печатается **поимённо**, по терму на источник, а не одной строкой «фиты»:
  список для того и был списком термов, чтобы это не потребовало менять его
  форму.

  ⚠️ `terms` — список `%{label:, value:}`, а не готовая строка (задача 3.13,
  Dan 03.08.2026): разбор печатается не в карточке, а в поп-апе
  `BuilderComponents.stat_pop/1`, и там термы стоят друг под другом, а не
  через « · » — плоская строка потеряла бы моноширинное выравнивание
  значений (`tabular-nums`, CLAUDE.md §6) и не выдержала бы пяти-шести
  термов, которые добавит 3.1.

  ⚠️ Первый терм называется «база», не «покупка» и не «старт» (Dan
  03.08.2026): «покупка» звучало коряво, а «старт» на экране создания
  персонажа уже значит «поинт-бай ВМЕСТЕ с расой» — назвать так одну лишь
  `row.point_buy` было бы тем же словом с другим смыслом. Раса остаётся
  отдельным термом, а не сворачивается в «старт» вместе с базой: это тот же
  принцип «поимённо», что не даёт `Abilities.breakdown/2` схлопывать свои
  четыре поля в одно (см. его модульную документацию) — и та же причина,
  по которой она видна здесь, а не только на карточке расы, где раса
  выбирается: панель итогов — единственное место, которое объясняет каскад
  целиком, не заставляя искать половину объяснения в другом экране.
  """
  @spec ability_summary(map(), Build.t()) :: [map()]
  def ability_summary(ruleset, %Build{} = build) do
    breakdown = Abilities.breakdown(build, ruleset)

    for ability <- Labels.ability_order() do
      row = Map.fetch!(breakdown, ability)

      %{
        id: ability,
        label: Labels.ability(ability),
        hue: Palette.ability_hue(ability),
        score: row.score,
        modifier: row.modifier,
        terms: ability_terms(ruleset, row),
        cap: ability_cap_label(ruleset, row)
      }
    end
  end

  # «База» открывает список абсолютным числом — ей не с чем быть слагаемым,
  # это то, с чего каскад начинается. Дальше — те же слагаемые, что несёт
  # `Abilities.breakdown/2`, тем же приёмом, каким собран разбор навыка:
  # нулевое слагаемое молчит («раса +0» не говорит того, чего уже не сказал
  # сам факт отсутствия строки).
  defp ability_terms(ruleset, row) do
    ([
       %{label: "база", value: Integer.to_string(row.point_buy)},
       term_row("раса", row.race_bonus),
       term_row("уровни", row.level_bonus)
     ] ++
       own_terms(ruleset, row) ++ [term_row("вещи", row.gear_bonus)])
    |> Enum.reject(&is_nil/1)
  end

  # Прибавки, которые билд заработал сам (задача 3.1) — поимённо и по одному
  # терму на источник, тем же приёмом, что `feat_terms/2` у HP выше: «+3»
  # рядом с `Great strength ×3` игрок может проверить, «+3» рядом со словом
  # «фиты» — только принять на веру.
  #
  # ⚠️ Стоят между «уровнями» и «вещами», и это порядок каскада, а не вкус:
  # источник делит слагаемые ровно здесь — поинт-бай, раса, уровни и фиты
  # собирают BASE score, а вещи идут дальше и со своим капом
  # (`_order_decision` в `vanilla/feat_ability_bonuses.json`).
  #
  # ⚠️ Отдельным термом, а не внутри «уровней», хотя таблица РДД растёт именно
  # по уровням класса: «уровни +8» у Ученика дракона было бы верной суммой и
  # неверным объяснением — игрок решил бы, что потратил на силу восемь
  # прибавок каждого четвёртого уровня, которых у него всего десять на билд.
  defp own_terms(ruleset, row) do
    for term <- Map.get(row, :own_terms, []) do
      takes = if term.takes > 1, do: " ×#{term.takes}", else: ""
      cap = if term.capped?, do: " (потолок)", else: ""

      %{label: "#{own_term_name(ruleset, term.source)}#{takes}#{cap}", value: signed(term.bonus)}
    end
  end

  # Имя берётся по ВИДУ источника, который терм несёт сам, а не поиском id по
  # всем справочникам: у ядра фит и класс — разные ключи записи, и подпись
  # обязана спрашивать то же, что спрашивало ядро.
  defp own_term_name(ruleset, {:feat, id}), do: Labels.feat_name(ruleset, id)
  defp own_term_name(ruleset, {:class, id}), do: Labels.class_name(ruleset, id)

  # Как `term/2` ниже, но термом структуры `stat_pop/1`, а не куском строки —
  # два формата нужны параллельно: сейвы и навыки разбираются одной строкой
  # в `title`, а характеристики с задачи 3.13 — списком термов в поп-апе.
  defp term_row(_label, 0), do: nil
  defp term_row(label, value), do: %{label: label, value: signed(value)}

  # Кап показываем той же плашкой, что у AB и сейвов (`row.cap` в панели
  # итогов) — не текстом внутри разбора: игрок уже знает этот визуальный
  # язык с других строк, а разбор остаётся коротким предложением, а не
  # предложением с оговоркой внутри.
  defp ability_cap_label(_ruleset, %{gear_capped?: false}), do: nil
  defp ability_cap_label(ruleset, _row), do: "кап +#{ruleset.gear.ability_bonus_cap}"

  @doc """
  То же самое, что `ability_summary/2` уже строит, плюс готовая подпись «из
  чего собралось» для экрана ПРОСМОТРА (AGENT_QUEUE.md §7, «Разбор
  характеристик на экране ПРОСМОТРА»). Там характеристики печатались как
  «старт → финал» без единого слагаемого, и после задачи 3.1 у Ученика
  красного дракона `12 → 20` не объяснялось ничем — восемь очков силы
  появлялись из воздуха, хотя ядро их уже считало и называло поимённо
  (`own_terms`, задача 3.1).

  ⚠️ **Строкой, а не поп-апом** — сознательное расхождение с конструктором
  (задача 3.13), а не недосмотр. Поп-ап там существует потому, что панель
  итогов — узкая колонка рядом с органами управления, которыми игрок
  пользуется прямо сейчас, и место в дефиците. Экран просмотра устроен
  наоборот: ничего не выбирается (см. moduledoc этого модуля и
  `BuildViewLive`), органов управления, конкурирующих за место, нет, —
  и CLAUDE.md §6 уже решил тот же вопрос для КАЖДОГО ДРУГОГО числа этого
  экрана: AB, оба AC, все три сейва и HP печатают свою сумму строкой под
  значением, всегда и без клика (`stat_cards/2`, задача 3.6). Характеристика
  не становится особым случаем только потому, что для неё когда-то первой
  завели поп-ап — это ещё одно число, которому этот экран должен объяснение,
  как и всем остальным.

  `from` — `nil`, когда терм ровно один («база»): единственное слагаемое,
  равное самому числу рядом, не говорит того, чего число уже не сказало —
  тот же принцип, что глушит нулевые термы внутри разбора
  (`Abilities.breakdown/2`, `term_row/2` выше), доведённый на шаг дальше:
  подпись из одного слагаемого настолько же пуста, как подпись из нуля.
  У человека без расовых модификаторов, прибавок уровня, фитов и вещей на
  данной характеристике — обычный случай для большинства из шести у самого
  простого билда — строки не будет вовсе, а не «база 14» под уже
  напечатанным значением «14».
  """
  @spec ability_view_rows(map(), Build.t()) :: [map()]
  def ability_view_rows(ruleset, %Build{} = build) do
    for row <- ability_summary(ruleset, build) do
      Map.put(row, :from, ability_view_from(row.terms))
    end
  end

  defp ability_view_from([_single_term]), do: nil
  defp ability_view_from(terms), do: terms_caption(terms)

  @doc """
  Every skill the build invested in: its ranks, its value, and the sum behind it.

  **`ranks` and `value` are two different numbers and the row keeps them apart.**
  Ranks are what was bought; the value is what the character rolls with — ranks
  plus the key ability modifier plus the racial affinity plus the feats that add
  to it, the class abilities that add to it, and the shard's modifiers. They are
  the two numbers the community's posting format prints side
  by side (`SKILLS: <скилл> <база> (<с модификаторами>)`), and the fields used to
  be called `total` and `bonus`, which named neither: `total` held the ranks and
  `bonus` held the whole value.

  The value comes from `stats.skill_values` and is never assembled here. It used
  to be `ranks + ability modifier`, which silently dropped three things: the
  racial affinities (an Elf's +2 Spot, a Dwarf's +2 Lore), the shard's stealth
  penalty on a four-class build, and — worst — it printed `ranks + 0` for a skill
  whose key ability nobody had written down. Claiming an ability contributes zero
  is exactly the confident lie a `nil` exists to prevent, so a skill without one
  carries `value: nil` and prints as `?`. ⚠ The one skill that was in that state
  (`alchemy`) is not any more — Dan measured its ability on 17.08.2026 — and the
  branch stays for the next skill the shard adds.

  `from` is the sum spelled out, the same way every stat card on this screen
  spells its own out. Two numbers with nothing between them are a riddle — the
  screen exists to answer «что это за билд», not to be decoded — and the caption
  is also where the value admits what it is *missing*: a feat taken for this
  skill whose bonus is prose on a wiki page and no number anywhere.

  ## Какие навыки печатаются — решает ядро, не этот фильтр

  ⚠️ Строка появляется у навыка, про который **ядро что-то посчитало**
  (`stats.skill_values`), а не у навыка с рангами. До задачи 3.20 это было одно и
  то же; теперь «дисциплина +50» без единого ранга — законная строка, и ровно
  ради неё поле заводилось («чтобы в „Итого“ увидеть финальную картинку по
  скиллам», Dan). Условие «во что билд вложился» живёт в `Rules.Skills.values/3`
  в единственном экземпляре: два фильтра — рано или поздно два разных ответа, а
  расходятся они молча.

  `ranks` при этом остаётся числом рангов и у такой строки равен нулю: это
  первое из двух чисел канонического формата, и подменять его значением было бы
  той самой путаницей, из-за которой поля когда-то назывались `total` и `bonus`.
  """
  @spec skill_rows(map(), Build.t(), map()) :: [map()]
  def skill_rows(ruleset, %Build{} = build, stats) do
    level = Build.character_level(build)

    rows =
      for {id, skill} <- ruleset.skills,
          Map.has_key?(stats.skill_values, id) do
        ranks = Build.skill_ranks(build, id, level)
        value = Map.get(stats.skill_values, id)
        total = value && value.total

        %{
          id: id,
          name: skill.name,
          ranks: ranks,
          value: total,
          from: skill_from(ruleset, value, ranks),
          unknown?: is_nil(total),
          # Cross-class for the *build*: no class it ever took has this skill, so
          # every rank cost two and no level offered the class ceiling. ⚠ Not the
          # ceiling rule itself — that reads the class of one level at a time
          # (`Skills.rank_cap/4`) — but the only statement about class-ness a
          # finished character can be summed up with in one word.
          cross?: not Skills.class_skill_by?(build, ruleset, id, level)
        }
      end

    Enum.sort_by(rows, & &1.name)
  end

  @doc """
  То же самое, что `skill_rows/3` уже собирает, плюс термы для поп-апа
  панели итогов — «значение навыка с разбором по слагаемым», идея Dan
  03.08.2026 (AGENT_QUEUE.md §3.4b): «тёмный эльф-клирик может залить много
  эпической мудрости, большой мод мудрости даст много спота».

  ⚠️ **Не переименование `skill_rows/3` и не тот `@skill_rows`, что уже есть
  у конструктора.** У `BuilderLive` под этим именем живёт СОВСЕМ ДРУГАЯ
  структура — построчные ПОКУПКИ навыка на активном уровне сцены
  (`at_level`, собирается в `builder_live.ex` рядом со степперами), а не
  итог по всему билду. Одно русское слово «навыки», две формы данных;
  взять не ту значило бы молча подсунуть панели итогов дефолт текущего
  уровня вместо суммы всей лестницы — правдоподобная чушь, а не баг,
  который бросится в глаза. Поэтому у панели итогов — третье имя, а не
  повтор одного из двух занятых.

  Построена НАД `skill_rows/3`, а не рядом: тот же фильтр «во что билд
  вложился» (`ranks > 0`), та же сортировка по имени, тот же `cross?` —
  одно место решает, что считать «вложенным навыком», а не два, которые
  рано или поздно разойдутся. Это добавляет `terms` — для того же поп-апа,
  что уже разбирает характеристики, AB, AC и сейвы (`BuilderComponents.
  stat_pop/1`, задачи 3.13/3.6): третью машинерию заводить прямо запрещено
  заданием, а четвёртого потребителя одного и того же механизма достаточно,
  чтобы показать, что он общий, а не привязан к характеристикам исторически.
  И `note` — то единственное, чему в поп-апе не место (см. `skill_value_terms/2`).
  """
  @spec skill_totals(map(), Build.t(), map()) :: [map()]
  def skill_totals(ruleset, %Build{} = build, stats) do
    for row <- skill_rows(ruleset, build, stats) do
      case Map.get(stats.skill_values, row.id) do
        nil ->
          Map.merge(row, %{terms: nil, note: nil})

        value ->
          Map.merge(row, %{
            terms: skill_value_terms(ruleset, value),
            note: feats_term(ruleset, value.unmodelled_feats)
          })
      end
    end
  end

  @doc """
  Значение навыка термами — «ранги → характеристика → раса → фит(ы) →
  класс(ы) → правила шарда» — для поп-апа панели итогов. Тот же каскад,
  что `skill_from/3` уже печатает строкой на экране просмотра (оба читают
  ровно те поля, что собрал `Skills.value/4`), не вторая независимая
  формула — та же причина, по которой `ab_terms/2` и «AB» на экране
  просмотра читают один список, а не два похожих.

  ⚠️ **`unmodelled_feats` сюда намеренно НЕ идёт термом.** Это не слагаемое
  суммы, а дыра в ней (`Rules.Skills`, «the opposite kind of entry») — и
  правило поп-апа «признание в непосчитанном не имеет права требовать,
  чтобы его сначала нашли» (`stat_pop/1`, задача 3.13) касается его ничуть
  не меньше, чем общих `ruleset.gaps`, хоть оно и специфично для одной
  строки, а не для всего билда. Поэтому оно едет `note` у строки
  `skill_totals/3`, печатается СНАРУЖИ поп-апа и видно без наведения —
  тем же приёмом, что уже показывает кап «упёрлось в потолок» рядом
  со значением, а не внутри разбора.
  """
  @spec skill_value_terms(map(), Skills.value()) :: [map()]
  def skill_value_terms(ruleset, value) do
    [
      %{label: "ранги", value: Integer.to_string(value.ranks)},
      skill_ability_term(value),
      term_row("раса", value.race_bonus),
      shard_race_term(ruleset, value),
      # ⚠️ Своей строкой рядом с расовым бонусом, а не внутри него, хотя число
      # то же и источник тот же шард: это два независимых терма, и Человек-
      # сагровик с древковым оружием получает к Дисциплине +18 и ещё +18 (замер
      # Dan, задача 3.35). Слитые в одну строку, они выглядели бы как +36
      # непонятно откуда.
      weapon_type_term(ruleset, value),
      # ⚠️ Своей строкой, а не внутри чужой. У навыка нет типов прибавки, как у
      # AC, поэтому объявленный фитом с вещи `Stealthy` (+2 Hide) и вписанное
      # «Hide +50» просто складываются — запретить это нечем, оба утверждения
      # игрока верны по отдельности. Единственная защита от двойного счёта в том,
      # что видно ДВЕ строки: «Stealthy +2» и «вещи +50».
      term_row("вещи", value.gear_bonus),
      skill_named_term(value.feat_bonus, value.feat_bonus_from, &Labels.feat_name(ruleset, &1)),
      skill_named_term(
        value.class_bonus,
        value.class_bonus_from,
        &Labels.class_name(ruleset, &1)
      ),
      # Штраф брони (задача 3.42) — своей строкой, и подписан ПРАВИЛОМ, а не
      # предметом: число одно, а собрано оно из доспеха и щита сразу («both
      # armor check penalties apply»), и «доспех −18» у персонажа в латах
      # с башенным щитом было бы неправдой ровно наполовину.
      armor_penalty_term(value),
      term_row("правила шарда", value.shard_modifier),
      # Два потолка, две разные строки, и обе после своих слагаемых: сначала
      # срез пула бонусов (+50 на расовый бонус шарда и вещи вместе), потом срез
      # итога (127). ⚠️ Именно поэтому ядро несёт остаток полем: сумма термов
      # минус итог обвинила бы фит, который никто не клипал (тот же довод, что
      # у `ab_terms/2` и `save_summary_terms/5`).
      skill_cap_term("сверх капа бонусов", value.bonus_clipped),
      skill_cap_term("сверх капа навыка", value.value_clipped)
    ]
    |> Enum.reject(&is_nil/1)
  end

  # Срез потолка — отрицательным термом «сверх капа», тем же словом, каким его
  # печатают AB и сейвы. ⚠️ Двух потолков у одного числа больше нигде нет,
  # поэтому подпись обязана называть, КАКОЙ именно: «бонусов» (+50 на пул) или
  # «навыка» (127 на итог). Само число потолка в подпись не идёт — разбор
  # складывается в стоящее рядом значение, и лишнее число в строке ломало бы
  # ровно эту проверку; величины стоят там, где им место: у поля ввода в блоке
  # «Вещи» и у заметки секции.
  defp skill_cap_term(_label, 0), do: nil
  defp skill_cap_term(label, clipped), do: %{label: label, value: signed(clipped)}

  # Штраф брони. ⚠️ `nil` — «не сказано, отнимает ли у этого навыка», и терма
  # тогда НЕТ вовсе: ровно так же ведёт себя строка характеристики соседней
  # функцией. Строка «штраф брони ?» была бы вторым голосом о том, что уже
  # сказано гэпом, а значение у такого навыка и так печатается «?».
  # Ноль отсекает `term_row/2`, как у всех соседей: нулевой терм не печатаем.
  defp armor_penalty_term(%{armor_penalty: nil}), do: nil
  defp armor_penalty_term(%{armor_penalty: penalty}), do: term_row("штраф брони", penalty)

  # `nil` только когда ключевую характеристику не назвал никто (в данных таких
  # навыков сегодня нет — `alchemy` закрыт замером Dan 17.08.2026, кейс P1;
  # ветка про следующий навык шарда): `total` у такого навыка тоже `nil`
  # (`Skills.assemble/5`), и значение печатается «?» — молчаливого
  # «характеристика +0» тут быть не должно, это был бы придуманный факт.
  defp skill_ability_term(%{ability: nil}), do: nil

  defp skill_ability_term(%{ability: ability, ability_modifier: modifier}),
    do: %{label: Labels.ability(ability), value: signed(modifier)}

  defp skill_named_term(0, _sources, _name), do: nil
  defp skill_named_term(_bonus, [], _name), do: nil

  defp skill_named_term(bonus, sources, name),
    do: %{label: Enum.map_join(sources, ", ", name), value: signed(bonus)}

  # Расовый бонус Сиалы к навыку (задача 3.12) — своим термом, а не внутри
  # «раса». ⚠️ Это два разных факта: «раса» — ванильная склонность
  # (`vanilla/races.json`, +2 Spot у эльфа), а этот — прибавка шарда
  # (`siala_41/races.json`, +12 дисциплины у человека), и она есть только на
  # 40–41 уровне. Сложить их в одну строку значило бы напечатать «+12» под
  # подписью, которая обещает ванильную склонность.
  #
  # Подписан именем расы, а не словом «Сиала»: имя игрок может проверить.
  #
  # ⚠️ Пометка «(потолок)» с этой строки **снята** (задача 3.20). До неё потолок
  # +50 стоял на расовом бонусе персонально, и назвать срез его именем было
  # верно; теперь в тот же пул входит прибавка с вещей, клип один на сумму — и
  # подпись «Человек +12 (потолок)» обвиняла бы расовый бонус в потере, которую
  # устроило вписанное игроком число. Срез теперь своя строка
  # (`skill_cap_term/2`), как у AB и сейвов.
  defp shard_race_term(_ruleset, %{shard_race_bonus: 0}), do: nil

  defp shard_race_term(ruleset, value) do
    %{
      label: Labels.race_ru(ruleset, race_of(ruleset, value)),
      value: signed(value.shard_race_bonus)
    }
  end

  # Бонус за тип оружия в руках (задача 3.35). Подпись та же, что у этого терма
  # в разборе AB, — «тип оружия», а не имя предмета: она обязана отличать его от
  # соседней строки расового бонуса, у которой ровно то же число и тот же
  # источник. Терм с нулём не печатается — то же правило, что у всех соседей.
  defp weapon_type_term(_ruleset, %{weapon_type_bonus: 0}), do: nil

  defp weapon_type_term(_ruleset, value),
    do: %{label: "тип оружия", value: signed(value.weapon_type_bonus)}

  # Чья это раса — спрашиваем у ruleset'а по навыку, а не тащим id расы через
  # структуру значения навыка: ядро уже знает, у какой расы бонус к какому
  # навыку, и второе написание того же факта разошлось бы с первым.
  defp race_of(ruleset, %{skill: skill}) do
    case Map.get(ruleset, :racial_bonuses) do
      %{by_race: by_race} ->
        Enum.find_value(by_race, fn {race, record} -> record.skill == skill && race end)

      _ ->
        nil
    end
  end

  # A skill the core returned no value for at all — it has ranks but no record in
  # the ruleset. Different failure, already reported as `{:missing_data, {:skill,
  # id}}`; here it just means there is nothing to spell out but the ranks.
  defp skill_from(_ruleset, nil, ranks), do: "#{ranks} р."

  defp skill_from(ruleset, value, _ranks) do
    [
      "#{value.ranks} р.",
      ability_term(value),
      term("раса", value.race_bonus),
      # Отдельным слагаемым и с именем расы — см. `shard_race_term/2`: ванильная
      # склонность и бонус расы Сиалы это два разных факта.
      shard_race_sentence_term(ruleset, value),
      # И третий отдельный терм рядом с ними — вписанное игроком число. Тот же
      # довод, что в `skill_value_terms/2`: у навыка нет типов, поэтому от
      # двойного счёта защищает только раздельная строка.
      term("вещи", value.gear_bonus),
      # Named, unlike the shard modifier below, because the core hands over the
      # provenance with the number: which feats and which classes produced it.
      # `Alertness` adding two points to Spot without saying so would be the same
      # unexplained growth that made these two terms worth adding in the first
      # place — the number moved and nothing on screen said why.
      sources_term(value.feat_bonus, value.feat_bonus_from, &Labels.feat_name(ruleset, &1)),
      sources_term(value.class_bonus, value.class_bonus_from, &Labels.class_name(ruleset, &1)),
      # Тот же терм, что в поп-апе конструктора, и с той же подписью
      # (`armor_penalty_term/1`): экран просмотра печатает разбор строкой,
      # а не поп-апом, но говорит то же самое и теми же словами.
      armor_penalty_sentence_term(value),
      # Named generically on purpose. The core hands over a number and no
      # provenance, and today exactly one rule produces it (the four-class
      # stealth penalty) — writing that rule's name here would be the web layer
      # asserting which rule fired, which it does not know.
      term("правила шарда", value.shard_modifier),
      # Оба потолка — теми же двумя строками, что и в поп-апе конструктора
      # (`skill_cap_term/2`): экран просмотра печатает разбор подписью, а не
      # поп-апом, но говорит то же самое.
      cap_sentence_term("сверх капа бонусов", value.bonus_clipped),
      cap_sentence_term("сверх капа навыка", value.value_clipped),
      feats_term(ruleset, value.unmodelled_feats)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  # ⚠️ Тот самый `?`, сказанный словами: у навыка, чью ключевую характеристику
  # никто не назвал, число не собирается, и подпись говорит почему, а не
  # оставляет пустое место без причины.
  #
  # ⚠️ Единственным её адресатом была сиальская `Alchemy`, и 17.08.2026 Dan
  # ответил на кейс P1 («ее атрибут - мудрость») — в поставляемых ruleset'ах
  # ветка больше не срабатывает. Она остаётся, потому что остаётся случай:
  # навык шарда без ванильной основы приходит без этого поля. Проверяется
  # на ruleset'е с вынутым полем (`summary_test.exs`).
  defp ability_term(%{ability: nil}), do: "характеристика не названа ни на одной вики"

  defp ability_term(%{ability: ability, ability_modifier: modifier}),
    do: "#{Labels.ability(ability)} #{signed(modifier)}"

  defp term(_label, 0), do: nil
  defp term(label, value), do: "#{label} #{signed(value)}"

  defp armor_penalty_sentence_term(value) do
    case armor_penalty_term(value) do
      nil -> nil
      term -> "#{term.label} #{term.value}"
    end
  end

  # Те же две строки про потолки, что `skill_cap_term/2`, но куском строки.
  defp cap_sentence_term(label, clipped) do
    case skill_cap_term(label, clipped) do
      nil -> nil
      term -> "#{term.label} #{term.value}"
    end
  end

  # Тот же терм, что `shard_race_term/2`, но куском строки: у экрана просмотра
  # разбор печатается подписью, а не поп-апом (см. `ability_view_rows/2`).
  defp shard_race_sentence_term(ruleset, %{shard_race_bonus: 0}) do
    _ = ruleset
    nil
  end

  defp shard_race_sentence_term(ruleset, value) do
    term = shard_race_term(ruleset, value)

    "#{term.label} #{term.value}"
  end

  # A term whose label is the list of things that produced it. `0` never gets a
  # row: "no feat adds to this skill" and "a feat adds zero" are the same number
  # and not the same statement, and only the first is true here.
  defp sources_term(0, _sources, _name), do: nil
  defp sources_term(_bonus, [], _name), do: nil

  defp sources_term(bonus, sources, name),
    do: "#{Enum.map_join(sources, ", ", name)} #{signed(bonus)}"

  # `Skill focus` is +3 and `Epic skill focus` +10, and both numbers are English
  # prose on a Fandom page. The value is short by them; this says by what, so the
  # gap between our number and the one in the player's character sheet has a name
  # instead of looking like arithmetic we got wrong.
  defp feats_term(_ruleset, []), do: nil

  defp feats_term(ruleset, feats),
    do: "без прибавки от " <> Enum.map_join(feats, ", ", &Labels.feat_name(ruleset, &1))

  @doc """
  A skill's value out of `stats.skill_values`, or `nil` when it has none.

  `nil` covers both cases honestly: a skill nobody bought ranks in is absent
  from the map, and a skill whose key ability the wiki never states carries
  `total: nil` of its own.
  """
  @spec skill_value(map(), atom()) :: integer() | nil
  def skill_value(stats, id) do
    case Map.get(stats.skill_values, id) do
      %{total: total} -> total
      _ -> nil
    end
  end

  @doc """
  The whole levelling guide, split into two reading columns.

  The build has to be visible all at once — this is the window people keep open
  beside the game — so it is two columns of consecutive levels rather than one
  long scroll.
  """
  @spec guide_columns(map(), Build.t()) :: [[map()]]
  def guide_columns(ruleset, %Build{} = build) do
    rows = guide_rows(ruleset, build)
    half = rows |> length() |> Kernel./(2) |> Float.ceil() |> trunc()

    case Enum.split(rows, max(half, 1)) do
      {left, []} -> [left]
      {left, right} -> [left, right]
    end
  end

  @doc "One line per character level: class, feats, the stat bump, skills bought."
  @spec guide_rows(map(), Build.t()) :: [map()]
  def guide_rows(ruleset, %Build{} = build) do
    for level <- 1..max(Build.character_level(build), 0)//1 do
      class = Build.class_at(build, level)
      run_start? = level == 1 or Build.class_at(build, level - 1) != class

      %{
        level: level,
        class: class,
        # Named only where it changes: repeating it on every line is noise.
        short: if(run_start?, do: Labels.class_short(ruleset, class)),
        # Задача 3.169: `Labels.class_short/2` ellipsises single-word names
        # ONLY on the constructor's ladder — that half of its own contract
        # ("the ladder ellipsises them", moduledoc) never reached the guide,
        # and «Shadowdancer» spilled text over the next column at every
        # width ≥621px (the 74px track fits none of it — see `app.css`,
        # `.v-g .cls`). The guide now clips too, and this backs the clip up
        # as a `title`: same guard as `short`, nil where nothing prints.
        class_name: if(run_start?, do: Labels.class_name(ruleset, class)),
        run_start?: run_start?,
        feats: guide_feats(ruleset, build, level),
        # Marked `○` and kept apart from the picked ones: the guide is read as
        # documentation, so it says what arrived as well as what was chosen —
        # but it never lets the two look like the same decision (CLAUDE.md §6).
        #
        # ⚠️ «Arrived» здесь буквально: `Feats.granted_named/3` — прирост
        # владения, а не выдача классового уровня (баг 1.14). Гид, который на
        # первом уровне второго класса печатал шесть строк вместо одной, врал
        # ровно в том месте, ради которого его и читают.
        granted: Enum.uniq_by(Feats.granted_named(ruleset, build, level), & &1.id),
        # A known spell is a decision of the level like a feat, so the guide
        # carries it too — with the circle as a badge rather than a new glyph
        # (CLAUDE.md §6). The circle is part of the slot id, so no lookup.
        spells:
          for {{:circle, circle, _index}, spell} <-
                Enum.sort(Map.get(build.spells, level, %{})) do
            %{circle: circle, name: Labels.spell_name(ruleset, spell)}
          end,
        increase: guide_increase(ruleset, build, level),
        # A class's own one-time choice (a Cleric's two domains, задача
        # 3.14) — on its own first class level, same rule the constructor's
        # ladder uses (`ladder_class_choice/3`), so the two never disagree
        # about which row this is. `nil` covers both "this class has none"
        # and "an old link never recorded one" — the guide shows what was
        # chosen and stays silent otherwise, the same way `guide_increase/3`
        # already does for an unfilled ability bump.
        domains: guide_domains(ruleset, build, level),
        skills: guide_skills(ruleset, build, level)
      }
    end
  end

  # `id` едет рядом с готовым именем — волна 5 остановилась ровно тут
  # (HANDOFF §B.1): без него сопоставить пикшлот с «слот потрачен зря» можно
  # было бы только по строке `name`, а это «работает по случайной причине»
  # из списка ловушек проекта (совпало написание — просто повезло). С `id`
  # гид зовёт тот же `Feats.wasted_text/3`, что и плоский список фитов и
  # колонка прогрессии, — один и тот же атом, одна и та же проверка.
  #
  # ⚠️ Задача 3.176: `kind` — по той же причине, что и `id` выше, только для
  # ГЛИФА, а не для пометки «впустую». Раньше строка не несла его вовсе, и
  # `build_view_live.ex` красил глиф ПО ФИТУ (`ruleset.feats[id].epic?`), а
  # конструктор — ПО СЛОТУ (`Labels.slot_glyph(slot)`, CLAUDE.md §6: `✦`
  # общий, `★` эпический, `⚔` бонусный). Это не только «в просмотре нет
  # ⚔» — это ДВА разных правила, и они расходятся: обычный (не эпический)
  # фит, положенный в эпический общий слот («96 фитов остаются в пуле
  # эпического общего слота сверх своих 53 эпических», `slot_delta_label/2`),
  # у конструктора получал `★` (слот эпический), а у просмотра — `✦` (сам
  # фит не эпический). `kind` несёт РЕШЕНИЕ слота, а не свойство фита, и
  # `Labels.slot_glyph/1` — тот же читатель, что уже красит лестницу
  # конструктора — теперь читает и эту карту, повторяя её приоритет, а не
  # изобретая свой.
  defp guide_feats(ruleset, build, level) do
    takes = Feats.take_numbers(build, level)

    slots = Enum.sort_by(Map.get(build.feats, level, %{}), &Build.slot_order(elem(&1, 0)))

    for {slot, pick} <- slots do
      id = Build.feat_id(pick)

      %{
        id: id,
        name: Labels.feat_pick_name(ruleset, pick, Map.get(takes, slot, 1)),
        # "Что делает" popover content (task 3.94) — same call, same shape as
        # the constructor's picker (`Feats.entry/6`): the view screen is where
        # a link lands on someone who never built this and cannot hover a
        # class card to find out what a rewritten `Evasion` now does.
        info: Labels.feat_info(ruleset, id),
        kind: guide_feat_kind(slot, ruleset, level)
      }
    end
  end

  # Тот же разбор слота, что `BuildCalculator.Rules.FeatSlots.at/3` уже даёт
  # конструктору — только в обратную сторону: там ядро строит слот и кладёт
  # в него пик, здесь у нас уже есть RAW-ключ карты `build.feats[level]`
  # (`:general`, `:racial`, `{:class_bonus, class}` или
  # `{:class_bonus, class, index}` — см. `Build.slot_order/1`, тот же список
  # форм) и нужно узнать его `kind` заново, без похода в `FeatSlots` за целым
  # списком слотов уровня.
  #
  # ⚠️ `:general` — ОДИН И ТОТ ЖЕ атом что для обычного, что для эпического
  # общего слота (`FeatSlots.at/3`'s `general_slot/4`: `id: :general` всегда,
  # разнится только `kind`) — поэтому эпичность здесь решает не сам ключ,
  # а `Epic.epic_level?/2` того же уровня, которым слот и был открыт.
  #
  # Catch-all на неизвестную форму ключа возвращает `:general`, а не падает:
  # старая расшаренная ссылка не обязана падать 500-й от того, что будущая
  # правка формата слота не научила эту функцию новой форме — тем же путём,
  # каким `Labels.slot_glyph/1` сама отвечает `"✦"` любой карте без
  # знакомого `kind` (CLAUDE.md: битая ссылка не роняет LiveView).
  defp guide_feat_kind(:general, ruleset, level) do
    if Epic.epic_level?(ruleset, level), do: :epic_general, else: :general
  end

  defp guide_feat_kind(:racial, _ruleset, _level), do: :racial
  defp guide_feat_kind({:class_bonus, _class}, _ruleset, _level), do: :class_bonus
  defp guide_feat_kind({:class_bonus, _class, _index}, _ruleset, _level), do: :class_bonus
  defp guide_feat_kind(_other, _ruleset, _level), do: :general

  # Со своим оттенком: та же машинерия, что у классов, поэтому обе темы
  # работают сами. Гид читают целиком, и узор из одного-двух цветов отвечает
  # на «куда качали» раньше, чем глаз доберётся до подписей (CLAUDE.md §6).
  defp guide_increase(ruleset, build, level) do
    case Map.get(build.ability_increases, level) do
      nil ->
        nil

      ability ->
        score = build |> Abilities.scores_at(ruleset, level) |> Map.get(ability, 0)

        %{
          label: "#{Labels.ability(ability)} #{score}",
          hue: Palette.ability_hue(ability)
        }
    end
  end

  # `nil` unless this level is a class's own first AND there is a word for
  # it — either something was chosen, or nothing was and the ruleset names
  # the state anyway (a Wizard's `General`, task 3.170). An empty pick with
  # no such word (a Cleric mid-build, or an old link) reads as "nothing to
  # say" here, not as a todo: the guide is documentation of a build somebody
  # else made, not an editor.
  #
  # ⚠ Before task 3.170 this required `[_ | _] = chosen` unconditionally, so
  # a Wizard who stayed general printed no line at all — indistinguishable
  # on this screen from a build somebody never finished. `ClassChoices.
  # complete?/3` already calls that state legal and complete; the guide had
  # simply never been told what word to print for it.
  defp guide_domains(ruleset, build, level) do
    with class when not is_nil(class) <- Build.class_at(build, level),
         1 <- Build.class_level_at(build, level),
         %{} <- ClassChoices.spec(class, ruleset) do
      chosen = Build.class_choice(build, class)

      # `ClassChoices.no_selection_name/2`, not the raw `spec` map here —
      # the same `Map.get/2` safety it already documents applies to every
      # caller, not only itself.
      names =
        case chosen do
          [] -> List.wrap(ClassChoices.no_selection_name(class, ruleset))
          chosen -> Enum.map(chosen, &Labels.class_choice_value_name(ruleset, class, &1))
        end

      case names do
        [] -> nil
        names -> %{label: Labels.class_choice_heading(class), names: names}
      end
    else
      _ -> nil
    end
  end

  defp guide_skills(ruleset, build, level) do
    build.skills
    |> Map.get(level, %{})
    |> Enum.sort_by(fn {id, ranks} -> {-ranks, Labels.skill_name(ruleset, id)} end)
    |> Enum.map(fn {id, ranks} ->
      %{
        # `id` travels alongside the printed name — task 3.145, the canonical
        # text export's per-level line needs it to price the rank itself
        # (`Skills.rank_cost/4`, the ×2 a cross-class skill costs) without a
        # second pass over `build.skills` that could sort differently from
        # this one.
        id: id,
        name: Labels.skill_name(ruleset, id),
        ranks: ranks,
        total: Build.skill_ranks(build, id, level)
      }
    end)
  end

  defp number(nil), do: "?"
  defp number(value), do: Integer.to_string(value)

  defp signed(nil), do: "?"
  defp signed(value) when value >= 0, do: "+#{value}"
  defp signed(value), do: Integer.to_string(value)
end
