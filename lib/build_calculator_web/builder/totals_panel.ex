defmodule BuildCalculatorWeb.Builder.TotalsPanel do
  @moduledoc """
  The constructor's "Итого" panel — every derived stat, grouped, with its Δ.

  Split out of `BuildCalculatorWeb.BuilderLive` (задача 3.46, заход 4, marker
  "totals panel"): `assign_panel/1` is the one entry point (called from
  `BuilderLive.refresh/1`), everything else here exists only to build its rows.
  It reads the hover preview from `BuildCalculatorWeb.Builder.GearPanel` (the
  same `Rules.compute/2` shape the gear cascade reads) and hands the last step
  of its own pipeline to `GearPanel.assign_gear/1` — the "Вещи" block is the
  panel's own last section, not a separate screen.

  `number/1` (used for every plain figure in the collapsed mobile sheet)
  stayed in `BuilderLive` along with the rest of the `.heex`-facing helpers —
  see its own doc.
  """

  alias BuildCalculator.Rules.Caps
  alias BuildCalculatorWeb.Builder.{GearPanel, Labels, Summary}
  alias BuildCalculatorWeb.BuilderLive

  import Phoenix.Component, only: [assign: 3]

  # ---- totals panel ----

  def assign_panel(socket) do
    %{ruleset: ruleset, build: build, stats: stats} = socket.assigns
    preview = GearPanel.preview_stats(socket.assigns)
    capped = MapSet.new(stats.capped)
    captions = panel_captions(ruleset, stats)

    rows =
      Map.new(panel_fields(stats), fn {key, label, value, signed?, cap_key} ->
        {key,
         %{
           key: key,
           label: label,
           value: value,
           signed?: signed?,
           ghost: preview && GearPanel.diff(value, panel_value(preview, key)),
           # ⚠️ «AB второй руки» (задача 3.132) — исключение: кап у него не
           # аггрегатный `stats.capped` (тот один на СТАТ, и упёршаяся ГЛАВНАЯ
           # рука зажгла бы плашку и у второй тоже), а `off_hand.attack_capped?`
           # — своё число, посчитанное именно этой руке. `row_cap/4` решает,
           # какой из двух путей читать, по ключу строки.
           cap: row_cap(ruleset, capped, cap_key, key, stats),
           # Разбор поимённо — тем же поп-апом, что и характеристики (задача
           # 3.13, `BuilderComponents.stat_pop/1`): `nil` у строк, которые эта
           # задача не трогает (`base_attack`, `skill_points`, `skill_free`
           # остаются на старом `title`, см. разметку ниже), и настоящий список
           # термов у AB/оба AC/сейвов/HP/AB второй руки.
           terms: panel_terms(ruleset, stats, key),
           # Та же сумма текстом — используется только строками без `terms`
           # (title-подсказка) и мобильной шторкой не читается вовсе.
           from: Map.get(captions, key),
           attention: attention(key, value)
         }}
      end)

    # Значения навыков в панели итогов — идея Dan 03.08.2026 (AGENT_QUEUE
    # §3.4b): «большой мод мудрости даст много спота». `Summary.skill_totals/3`,
    # НЕ `@skill_rows` — тот ассайн уже занят построчными ПОКУПКАМИ навыка на
    # активном уровне сцены (`at_level`), другой структурой под похожим
    # именем; взять не ту значило бы молча показать дефолт текущего уровня
    # вместо итога по всему билду (см. докстроку `skill_totals/3`).
    #
    # ⚠️ Волна 10 (AGENT_QUEUE §7, «Ghost-предпросмотр не доехал до строк
    # навыков»): `ghost` дописывается той же формулой, что у HP/AB/AC/сейвов
    # выше (`skill_totals_with_ghost/4`), без единого лишнего `compute` —
    # `preview` уже полный результат `Rules.compute/2`, `skill_values` в нём
    # такая же карта, как в `stats`.
    skill_totals = skill_totals_with_ghost(ruleset, build, stats, preview)

    socket
    |> assign(:preview_stats, preview)
    # Характеристики переехали наверх панели итогов (CLAUDE.md §6, задача
    # 3.2) — единственная величина, которую раньше приходилось искать на
    # «нулевом» уровне, хотя из неё выводится всё остальное на этой панели.
    |> assign(:ability_summary, Summary.ability_summary(ruleset, build))
    |> assign(:ability_gap_note, ability_gap_note(ruleset))
    # Сагровик / адровец — запрос Dan 08.08.2026. Стоит в шапке панели, а не
    # строкой среди чисел: это не производный стат, а свойство состава билда,
    # и оно объясняет числа ниже (у сагровика расовый бонус больше), а не
    # складывается с ними. Считает ядро (`stats.class_groups`).
    |> assign(:class_group_flags, Summary.class_group_flags(ruleset, stats))
    # Справка к ПОСЧИТАННОМУ расовому бонусу (задача 3.102, решение Dan
    # 25.08.2026). До неё это предложение печаталось гэпом билда — то есть
    # под заголовком «ядро не смогло посчитать N», хотя оно ровно про то,
    # что ядро посчитало. Теперь оно стоит у самого числа: у Светлого эльфа
    # в группе «атака», у Карлика — в «живучести», у Человека — строкой под
    # значением навыка. Куда именно, решает `Summary.racial_bonus_note/2`
    # по виду бонуса из ядра, а не разметка по имени расы.
    #
    # ⚠️ Гэп при этом НЕ исчез: билд, у которого бонус не посчитан (руки
    # пусты или уровень ниже 40-го), по-прежнему говорит об этом в панели
    # пробелов — и справки у него нет, чтобы одно и то же не звучало дважды.
    |> assign(:racial_bonus_note, Summary.racial_bonus_note(ruleset, stats))
    |> assign(:panel_groups, panel_groups(rows, stats))
    |> assign(:sheet_numbers, sheet_numbers(rows, stats))
    |> assign(:preview_label, GearPanel.preview_label(socket.assigns, ruleset))
    |> assign(:delta_chips, GearPanel.preview_chips(socket.assigns, stats, preview))
    |> assign(:spell_day, spell_day_rows(ruleset, stats))
    |> assign(:skill_totals, skill_totals)
    |> GearPanel.assign_gear()
  end

  @doc """
  Печатаемое число строки — обычное форматирование (знаковое/беззнаковое,
  как решает `row.signed?`). Один хелпер на оба места шаблона (поп-ап
  и запасной план без термов), чтобы видимое число и тултип поп-апа
  не разошлись по формату.

  ⚠️ До задачи 3.133 здесь был третий путь — `row.display`, которым «Атак /
  раунд» перебивало это форматирование строкой «главная/вторая» (задача
  3.132). Dan вернул это замечанием: «показывает 4/1, но в реальности это
  4 атаки основной рукой и одна атака второй» — слеш подписи и слеш значения
  читались одним и тем же способом и означали разное. Вторая рука теперь
  своя строка (`stat-off_hand_apr`), и здесь снова ровно одно число.
  """
  @spec row_text(map()) :: String.t()
  def row_text(%{signed?: true, value: value}), do: BuilderLive.signed(value)
  def row_text(row), do: BuilderLive.number(row.value)

  # Гэпы про характеристики, которые обязаны быть видны БЕЗ клика. Список
  # читает `ruleset.gaps`, а не хардкодит текст — записи уходят из
  # `data/loader/gaps.ex` по мере того, как ядро учится считать или владелец
  # выводит вопрос из области ответа, и заметка сокращается сама, без правки
  # этого файла (печатать «не посчитано» про посчитанное запрещено,
  # CLAUDE.md §6).
  #
  # Сегодня в списке **одна** форма: прибавки от фитов (`Great strength`
  # и семья) и от классовых способностей (Red Dragon Disciple). Ни на одном
  # рабочем ruleset'е её нет — она вернётся только там, где нет разметки,
  # то есть это страховка от молчаливой потери файла, а не живая строка.
  #
  # ⚠️ **Два соседа ушли за один день, 22.08.2026, и оба решением Dan:**
  #
  #   * `{:not_modelled, :ability_cap_penalty_interaction}` — задача 3.77
  #     («штрафы понижают эффективный потолок» невыразимо в нашей форме
  #     ввода: на характеристику приходится одно число, и оно нетто).
  #     ⚠️ Форма снялась там, а СТРОКА осталась стоять здесь мёртвой —
  #     `gap in ruleset.gaps` не совпадал ни с чем и молчал. Убрана задачей
  #     3.81 попутно: это четвёртый подряд случай, когда снятая форма
  #     оставила за собой ссылку, и первый, где ссылка была кодом, а не прозой;
  #   * `{:missing_data, :racial_bonus_progression}` — задача 3.81
  #     («прогрессию делать не будем, данный пробел можно закрыть»).
  #
  # 🔴 **Следствие, которое надо знать: на обоих рабочих ruleset'ах заметки
  # под характеристиками больше НЕТ вовсе** — `<p id="stat-note-abilities">`
  # не рисуется. Это не потеря: признание про расовый бонус жило здесь
  # потому, что в панели пробелов оно тонуло за сотней «не смоделировано»
  # (задача 3.8), а теперь его нет и там — вопрос закрыт решением владельца.
  # То, что игрока в самом деле касается, никуда не делось и стоит в блоке
  # «этот билд»: билд ниже 40-го получает `{:missing_data,
  # {:racial_bonus_level, race}}` и `{:missing_data, {:weapon_type_bonus_level,
  # weapon}}` от ядра, и оба печатаются.
  defp ability_gap_note(ruleset) do
    gaps = [{:not_modelled, :ability_bonus_feats_and_class}]

    case for(gap <- gaps, gap in ruleset.gaps, do: Labels.gap(gap, ruleset)) do
      [] -> nil
      texts -> Enum.join(texts, "; ")
    end
  end

  defp panel_fields(stats) do
    [
      {:hp, "HP", stats.hp, false, nil},
      {:ac_naked, "AC голым", stats.ac_naked, false, nil},
      # ⚠️ Задача 3.6: раньше срез дожика +20 не был виден нигде на этой
      # панели — потолок нёсся в `stats.capped` (`:gear_ac`), но у AC не было
      # своего `cap_key`, и плашка ни разу не рисовалась. Только «в шмоте»
      # может упереться: «голым» вещей не считает вовсе.
      {:ac_geared, "AC в экипировке", stats.ac_geared, false, :gear_ac},
      # SR — задача 3.45, заход 2. Не signed: печатается как итоговая величина
      # («63»), тем же приёмом, что у HP и BAB, а не как модификатор к броску,
      # как AB и сейвы. `cap_key: nil` — потолка у SR не объявляет ни один
      # ruleset (`_cap_decision` в `feat_spell_resistance.json`), поэтому
      # плашки капа здесь нет и быть не может.
      # ⚠️ Строка есть в `rows` ВСЕГДА — ворота (12+ уровней монаха) отдельно
      # решает `panel_groups/2`, а не эта функция: `rows` не знает, покажет ли
      # шаблон свою строку, он просто несёт значение под каждым ключом
      # (тот же приём, что у пары AC).
      {:spell_resistance, "SR", stats.spell_resistance, false, nil},
      {:base_attack, "BAB", stats.base_attack, false, nil},
      {:attack_bonus, "AB", stats.attack_bonus, true, :attack_bonus},
      # Вторая рука (задача 3.132, Dan: «для второй руки отдельную строку,
      # мешать не надо»). `nil`, пока во второй руке ничего нет —
      # `panel_row_hidden?/2` прячет строку целиком, а не рисует «AB 0» там,
      # где второй руки у персонажа не бывает вовсе. `cap_key: nil`: у этой
      # строки СВОЙ путь к потолку, читает `row_cap/4`, а не аггрегатный
      # `stats.capped` — см. `assign_panel/1`.
      {:off_hand_ab, "AB второй руки", stats.off_hand && stats.off_hand.attack_bonus, true, nil},
      {:attacks_per_round, "Атак / раунд", stats.attacks_per_round, false, nil},
      # Атаки второй руки (задача 3.133) — своя строка, тем же приёмом,
      # что «AB второй руки» выше. До неё делила строку «Атак / раунд» через
      # слеш (задача 3.132), и Dan вернул это замечанием: слеш подписи
      # («атак **в** раунд») и слеш значения («главная **и** вторая») читались
      # одинаково и означали разное — «показывает 4/1, а в реальности это
      # 4 атаки основной рукой и одна атака второй». `nil`, пока во второй
      # руке ничего нет — `panel_row_hidden?/2` прячет строку целиком, той же
      # причиной, что и у «AB второй руки»: второй руки без оружия у персонажа
      # не бывает, и «0 атак» сообщило бы о том, чего нет.
      {:off_hand_apr, "Атак второй руки", stats.off_hand && stats.off_hand.attacks_per_round,
       false, nil},
      # ⚠️ Три разных ключа, не общий `:saving_throws` (задача 1.12a): с тех
      # пор, как источник (`Iron will`) может поднять один сейв и не тронуть
      # два других, кап тоже бьёт независимо — плашка на всех трёх при упоре
      # только в один была бы неточной ровно там, где точность и нужна.
      {:fort, "Fort", stats.fort, true, :fort_save},
      {:ref, "Ref", stats.ref, true, :ref_save},
      {:will, "Will", stats.will, true, :will_save},
      {:skill_points, "Скилл-поинты", stats.skill_points.earned, false, nil},
      {:skill_free, "Не потрачено", stats.skill_points.free, false, nil}
    ]
  end

  # Разбор термами — AB, AC×2, три сейва и HP пришли задачей 3.6, BAB по
  # классам — задачей 3.16, классовая часть сейвов — задачей «разбор сейвов
  # по классам» (у сейвов до неё был один терм «база» на всю прогрессию).
  # Без термов остались «Атак / раунд» и две строки скилл-поинтов, и у каждой
  # своя причина, а не «до них не дошли»:
  #
  #   * «Атак / раунд» — не сумма слагаемых, а поиск по таблице от BAB
  #     за засчитанные уровни (подпись собирает `Summary.stat_cards/2`):
  #     список термов, не складывающийся в стоящее рядом число, хуже подписи;
  #   * «Скилл-поинты» / «Не потрачено» — тоже не сумма: разбор, который
  #     там нужен, это `потрачено / свободно`, и он уже стоит подписью.
  #     ⚠️ Группировка по классам выглядела бы единообразно и врала бы:
  #     очки начисляются `(база класса + мод INT)` за уровень, ×4 на первом,
  #     а INT растёт по ходу билда — `Rogue 16 × 10` не перемножается
  #     в фактическую сумму ровно так же, как `0.75 × 15` не даёт 11
  #     (см. `Summary.bab_terms/2`).
  defp panel_terms(ruleset, stats, :hp), do: Summary.hp_terms(ruleset, stats)
  defp panel_terms(ruleset, stats, :ac_naked), do: Summary.ac_naked_terms(ruleset, stats)
  defp panel_terms(ruleset, stats, :ac_geared), do: Summary.ac_geared_terms(ruleset, stats)

  defp panel_terms(ruleset, stats, :spell_resistance),
    do: Summary.spell_resistance_terms(ruleset, stats)

  defp panel_terms(ruleset, stats, :base_attack), do: Summary.bab_terms(ruleset, stats)
  defp panel_terms(ruleset, stats, :attack_bonus), do: Summary.ab_terms(ruleset, stats)

  # `nil`, когда второй руки нет — та же граница, что у `Summary.
  # off_hand_ab_terms/2` само по себе держит (задача 3.132); дублировать
  # проверку здесь незачем, но и полагаться на скрытие строки нельзя: рано
  # или поздно у этого ключа появится читатель, не знающий про `panel_row_hidden?/2`.
  defp panel_terms(ruleset, stats, :off_hand_ab), do: Summary.off_hand_ab_terms(ruleset, stats)

  defp panel_terms(ruleset, stats, :fort),
    do: Summary.save_summary_terms(ruleset, stats, :fort, :con, stats.ability_modifiers.con)

  defp panel_terms(ruleset, stats, :ref),
    do: Summary.save_summary_terms(ruleset, stats, :ref, :dex, stats.ability_modifiers.dex)

  defp panel_terms(ruleset, stats, :will),
    do: Summary.save_summary_terms(ruleset, stats, :will, :wis, stats.ability_modifiers.wis)

  defp panel_terms(_ruleset, _stats, _key), do: nil

  # Смысловые группы, а не одиннадцать одинаковых строк подряд: раньше «Атак /
  # раунд» ничем не отделялось от `Fort`, все строки весили одинаково и панель
  # читалась как каша. Разделяем ГРУППЫ, а не строки — одиннадцать волосяных
  # линий и были причиной.
  #
  # Группы те же, что у плашек дельты на карточке класса (`main` / `save` /
  # `skill`), и это не совпадение: величины там ровно те же, а две разные схемы
  # заставляли бы человека учить обе.
  # ⚠️ `:spell_resistance` стоит здесь безусловно — в «живучести» рядом с HP
  # и AC, третьей защитой персонажа (от урона / от удара / от магии). Ворота
  # (12+ уровней монаха, Dan 18.08.2026) решает не список, а `panel_groups/2`
  # ниже: строка есть в макете всегда, а рисуется — не всегда.
  #
  # ⚠️ «спасы», не «сейвы» — задача 3.137, тем же словом, что у заголовка
  # секции «Вещи» (`GearPanel.save_label/1`): «Заменить надо ВЕЗДЕ, иначе
  # интерфейс заговорит двумя словами про одно» (CLAUDE.md §4 — интерфейсная
  # подпись, не игровое имя, `Fort`/`Ref`/`Will` остаются английскими).
  @panel_layout [
    {"vital", "живучесть",
     [
       :hp,
       {:pair, "ac", "AC", "голым / в экипировке", [:ac_naked, :ac_geared]},
       :spell_resistance
     ]},
    {"attack", "атака",
     [:base_attack, :attack_bonus, :off_hand_ab, :attacks_per_round, :off_hand_apr]},
    {"save", "спасы", [:fort, :ref, :will]},
    {"skill", "навыки", [:skill_points, :skill_free]}
  ]

  defp panel_groups(rows, stats) do
    for {key, label, items} <- @panel_layout do
      %{
        key: key,
        label: label,
        rows:
          items |> Enum.map(&panel_item(rows, &1)) |> Enum.reject(&panel_row_hidden?(&1, stats)),
        note: panel_note(key, stats)
      }
    end
  end

  # Единственная строка панели, которой может не быть вовсе — не «SR 0», как
  # у 95% билдов, а полное отсутствие строки (задача 3.45, заход 2). Ворота —
  # 12+ уровней МОНАХА персонажа (`Summary.spell_resistance_visible?/1`), а не
  # пустой список термов и не владение `Diamond soul`: фит можно объявить
  # с вещи, и тогда у билда без единого уровня монаха `stats.spell_resistance`
  # придёт 10 — Dan такой строки не просил.
  #
  # ⚠️ Гейт читает АКТУАЛЬНЫЕ `stats`, а не превью наведения — тот же приём,
  # что у `@spell_day`/`@skill_totals`/`@class_group_flags`: целая секция
  # появляется по факту, а не по наведению (ghost-подсветка внутри уже видимой
  # строки работает как обычно, см. `ghost:` в `assign_panel/1`).
  defp panel_row_hidden?(%{key: :spell_resistance}, stats),
    do: not Summary.spell_resistance_visible?(stats)

  # «AB второй руки» и «Атак второй руки» (задачи 3.132/3.133) — та же форма
  # скрытия, что у SR: строки нет, пока во второй руке ничего нет, а не «0»
  # — второй руки без оружия у персонажа не бывает, «есть, но ноль» сообщило
  # бы о том, чего нет. Гейт читает АКТУАЛЬНЫЕ `stats`, не превью, по тому же
  # принципу.
  defp panel_row_hidden?(%{key: key}, stats) when key in [:off_hand_ab, :off_hand_apr],
    do: is_nil(stats.off_hand)

  defp panel_row_hidden?(_row, _stats), do: false

  # «AC голым» и «AC в шмоте» — пара, а не две независимые строки: одно число
  # читают только в сравнении с другим. Один ряд с двумя числами, сноска под
  # панелью объясняет разницу и остаётся на месте.
  defp panel_item(rows, {:pair, key, label, hint, parts}) do
    parts = Enum.map(parts, &Map.fetch!(rows, &1))

    %{
      kind: :pair,
      key: key,
      label: label,
      hint: hint,
      parts: parts,
      from: Enum.find_value(parts, & &1.from),
      ghost: Enum.find_value(parts, &(&1.ghost && &1.ghost != 0 && &1.ghost))
    }
  end

  defp panel_item(rows, key), do: Map.put(Map.fetch!(rows, key), :kind, :single)

  # ⚠️ «Не потрачено» — единственное число в панели, которое требует действия.
  # Больше нуля — незавершённая работа, и читаться должно иначе; ноль — не
  # мозолить глаза. Меньше нуля означает перерасход (такое приезжает по ссылке,
  # руками этого не набрать) и должно выглядеть ошибкой, а не задачей.
  defp attention(:skill_free, free) when is_integer(free) and free > 0, do: "todo"
  defp attention(:skill_free, free) when is_integer(free) and free < 0, do: "over"
  defp attention(_key, _value), do: nil

  # 🔴 Задача 3.137 (Dan, 29.08.2026, скриншот «Итого»): «похоже вот эту
  # подсказку можно убрать, она между атакой и спасами. В целом у нас и так
  # все подписано откуда и что, в спасах видно все начисления и в АБ/БАБ».
  #
  # ⚠️ Раньше здесь стояло `defp panel_note("attack", stats), do:
  # Summary.counted_window_note(stats)` — печатала «В BAB и сейвы идут только
  # первые 20 уровней…». Довод Dan верен, но убрать её пришлось не по вкусу,
  # а по прогону: условие печати (`levels_ignored > 0`) срабатывает почти
  # на любом капнутом билде ДЛИННЕЕ 20 уровней, включая ОДНОклассовые (воин
  # 40 = BAB 30 — менять порядок нечему, а строка утверждает, что порядок
  # меняет результат). У «полноценного билда всегда 40 или 41 уровень»
  # (решение Dan) это значит «почти всегда», то есть постоянное предупреждение
  # переставало читаться.
  #
  # ⚠️ Функция-производитель (`Summary.counted_window_note/1`) НЕ удалена —
  # её всё ещё зовёт экран просмотра (`BuildViewLive`, `#view-counted-window`),
  # и Dan комментировал скриншот КОНСТРУКТОРА, а не View. Это разведённый
  # координатором фактически на два разных экрана вызов одной функции;
  # трогать View эта задача не просила, и решение оставить его как есть —
  # осознанно консервативное, а не недосмотр (см. отчёт задачи 3.137).
  defp panel_note("attack", _stats), do: nil

  # §3 требует ПОКАЗЫВАТЬ вклад Spellcraft в сейвы: игроки его не считают.
  # Строки нет, пока считать нечего; появилась она сама, без правки разметки,
  # как только ядро начало отдавать слагаемое.
  #
  # ⚠️ `save_extras_terms/1`, а не `save_terms/3` — задача 1.12a. Собственные
  # термы билда (`Iron will`, `Divine grace`…) больше не «ко всем трём»: у
  # каждого свой сейв, и групповая строка про них соврала бы про два других.
  # Они видны в разборе КАЖДОЙ строки (`panel_terms/3`), а не здесь.
  defp panel_note("save", stats) do
    case Summary.save_extras_terms(stats) do
      [] ->
        nil

      # Задача 3.6 привела термы к общему формату (`%{label:, value:}`, как у
      # `ability_terms/1` из задачи 3.13); `value` уже готовая подписанная
      # строка, второй раз знак не начисляем.
      terms ->
        "ко всем трём: " <> Enum.map_join(terms, ", ", &"#{&1.value} #{&1.label}")
    end
  end

  defp panel_note(_key, _stats), do: nil

  # Разбор берём у экрана просмотра, а не пишем второй: два места, считающие
  # одну и ту же сумму, рано или поздно разойдутся, и игроку покажут одно
  # число, а дадут другое.
  @caption_keys %{
    hp: "hp",
    ac_naked: "ac",
    ac_geared: "ac_geared",
    spell_resistance: "spell_resistance",
    base_attack: "bab",
    attack_bonus: "ab",
    attacks_per_round: "apr",
    fort: "fort",
    ref: "ref",
    will: "will",
    skill_points: "skill_points"
  }

  defp panel_captions(ruleset, stats) do
    cards = Map.new(Summary.stat_cards(ruleset, stats), &{&1.key, &1.from})
    Map.new(@caption_keys, fn {key, card} -> {key, Map.get(cards, card)} end)
  end

  # Свёрнутая мобильная шторка — представители групп развёрнутой панели
  # (CLAUDE.md §6). «Свободно» попало сюда намеренно: это единственное число,
  # которое требует действия, и на телефоне оно раньше было не видно вовсе,
  # пока шторку не откроешь.
  #
  # ⚠️ Задача 3.62 (Dan 20.08.2026, со скриншотом): «на мобильной версии внизу
  # нету АБ, только БАБ. И нету АЦ». Раньше «атака» была представлена одним
  # БАБ — числом, которое реже сверяют с листом персонажа, чем АБ. Теперь
  # ячейка называется `attack` и несёт оба через чёрточку (`AB/BAB`, в этом
  # порядке — так предложил Dan), а `vital` получила вторую ячейку, `ac`,
  # тем же числом, что и «в шмоте» развёрнутой панели (`ac_geared`): это то,
  # что игрок сверяет со своим листом, и при пустых «Вещах» оно совпадает
  # с голым.
  defp sheet_numbers(rows, stats) do
    [
      %{key: "hp", label: "HP", value: BuilderLive.number(stats.hp), attention: nil},
      %{key: "ac", label: "AC", value: BuilderLive.number(stats.ac_geared), attention: nil},
      %{
        key: "attack",
        label: "AB/BAB",
        value: "#{stats.attack_bonus}/#{stats.base_attack}",
        attention: nil
      },
      %{
        key: "saves",
        label: "saves",
        value: "#{stats.fort}/#{stats.ref}/#{stats.will}",
        attention: nil
      },
      # ⚠️ Задача 3.64: было «свободно» — единственное слово в шторке, не
      # называвшее СВОЕГО предмета («свободно» — что?), и единственная подпись,
      # расходившаяся с развёрнутой панелью, где та же строка зовётся
      # «Не потрачено». Соседи (`HP`, `AC`, `AB/BAB`, `saves`) называют стат,
      # а это — долг, и он обязан быть назван так же однозначно.
      #
      # ⚠️ ОДНО число, а не пара «не потрачено / всего» (идея Dan 20.08.2026,
      # им же помеченная как «может и не стоит»): всего заработанных очков —
      # число, на которое нельзя подействовать, а шторка существует ради
      # взгляда мельком. Пара к тому же не имеет короткой честной подписи:
      # у `AB/BAB` её задаёт сама подпись, а `68/172` читалось бы и как
      # «68 из 172 потрачено». Обе половины по-прежнему рядом в развёрнутой
      # панели, в одно касание.
      %{
        key: "free",
        label: "не потрачено",
        value: BuilderLive.number(stats.skill_points.free),
        attention: rows |> Map.fetch!(:skill_free) |> Map.get(:attention)
      }
    ]
  end

  # A number that quietly stopped growing reads as a bug in the calculator, so a
  # stat that hit one of `ruleset.stat_caps` says so next to itself. The core
  # decides *that* it was clipped (`stats.capped`); the ceiling's value is read
  # back out of the ruleset rather than written here (CLAUDE.md §6).
  defp cap_label(_ruleset, _capped, nil), do: nil

  defp cap_label(ruleset, capped, key) do
    if MapSet.member?(capped, key) do
      cap_text(ruleset, cap_stat(key))
    end
  end

  defp cap_text(ruleset, stat) do
    case Caps.cap(ruleset, stat) do
      nil -> "упёрлось в кап"
      cap -> "кап +#{cap}"
    end
  end

  # «AB второй руки» (задача 3.132) обходит `cap_label/3` целиком: аггрегатный
  # `stats.capped` знает только СТАТ («атака упёрлась»), а не РУКУ — упёрлась
  # любая из двух, значок в нём один (`DerivedStats`: «значок один, потому
  # что и стат один»). У этой строки вопрос ровно про одну руку, и ответ на
  # него ядро уже посчитало отдельно (`off_hand.attack_capped?`) — читаем
  # его напрямую, а не аггрегат, иначе главная рука подсветила бы кап и на
  # строке второй, которая его не касалась.
  defp row_cap(ruleset, _capped, _cap_key, :off_hand_ab, %{off_hand: %{attack_capped?: true}}),
    do: cap_text(ruleset, :attack_bonus)

  defp row_cap(_ruleset, _capped, _cap_key, :off_hand_ab, _stats), do: nil

  defp row_cap(ruleset, capped, cap_key, _key, _stats), do: cap_label(ruleset, capped, cap_key)

  # Three flags in `stats.capped` (task 1.12a), one ceiling — the ruleset
  # states a single `saving_throw_bonus` value that applies to Fort, Ref and
  # Will independently, not three different numbers.
  defp cap_stat(:fort_save), do: :saving_throw_bonus
  defp cap_stat(:ref_save), do: :saving_throw_bonus
  defp cap_stat(:will_save), do: :saving_throw_bonus
  # `:gear_ac` (`stats.capped`, `rules.ex`) says only THAT some AC type from
  # gear was clipped — today that can only be `dodge`, the one type
  # `Rules.Gear`'s own `@ac_type_caps` names a ceiling for (Dan, 03.08.2026:
  # the rest stack without limit). Mirroring that same pairing here rather
  # than re-deriving it keeps there being exactly one place that decides
  # which AC type has a ceiling.
  defp cap_stat(:gear_ac), do: :dodge_ac
  defp cap_stat(key), do: key

  # Slots per day are not a choice but a derived statistic, so they live here
  # rather than in the level scene (CLAUDE.md §6) — and `past_table?` is the
  # level-20 wall, said out loud in both places.
  #
  # `school_name` is the one exception: it names a *decision* (a Wizard's
  # specialization, task 3.10), not a derived number, but the number sitting
  # right below it is the derived effect of that decision — the whole point of
  # this task is that a specialist's row reads a different total than a
  # generalist's, so saying *why* belongs beside the number it explains rather
  # than making the player scroll back up to the level scene to find out.
  # ⚠️ Задача 3.125: у класса, из чьей строки потолок каста вырезал ВСЁ, здесь
  # не остаётся ни одной ячейки — паладин 4 с мудростью 10 круга не имеет вовсе,
  # и в игре у него нет книги заклинаний. Печатать имя класса над пустой лентой
  # значило бы сказать «слоты есть, просто ноль», а решение Dan — прятать, как
  # прячет игра. Строка `past_table?` уходит вместе с классом: она объясняет,
  # почему число не растёт, а числа больше нет.
  #
  # ⚠️ Фильтр стоит ЗДЕСЬ, а не в ядре: `stats.spells_per_day` несёт и строку
  # таблицы (`offered_slots`), на которой держится требование фита, и вырезать
  # запись целиком значило бы отнять у барда с харизмой 11 его измеренную
  # поблажку (задача 3.124).
  defp spell_day_rows(ruleset, stats) do
    for entry <- stats.spells_per_day, entry.slots != %{} do
      %{
        class: entry.class,
        name: Labels.class_name(ruleset, entry.class),
        class_level: entry.class_level,
        table_level: entry.table_level,
        past_table?: entry.past_table?,
        slots: Enum.sort(entry.slots),
        school_name:
          entry.specialized_school &&
            Labels.class_choice_value_name(ruleset, entry.class, entry.specialized_school),
        # Задача 3.70, тем же принципом, что `school_name` строкой выше:
        # число выросло — скажи, от чего. `nil`, когда бонуса нет вовсе
        # (модификатор 0 или ниже), потому что «+0 за CHA» объясняет пустоту,
        # а не число.
        ability_bonus: ability_bonus_label(entry)
      }
    end
  end

  # «CHA +10: +17 слотов» — характеристика, её модификатор и сумма того, что
  # он дал. Величина по кругам не печатается: строка слотов стоит прямо под
  # этой подписью, а разложить «+17» по девяти кругам значило бы повторить её
  # целиком.
  defp ability_bonus_label(%{ability_bonus: bonus}) when map_size(bonus) == 0, do: nil

  defp ability_bonus_label(entry) do
    total = Enum.sum(Map.values(entry.ability_bonus))

    "#{Labels.ability(entry.ability)} #{format_signed(entry.ability_modifier)}: " <>
      "+#{total} #{slots_word(total)}"
  end

  defp format_signed(number) when number >= 0, do: "+#{number}"
  defp format_signed(number), do: to_string(number)

  # «1 слот / 2 слота / 17 слотов». Числа тут настоящие и разные — от +1
  # у паладина с мудростью 12 до +17 у колдуна на капе, — так что одной
  # формой не обойтись. Живёт здесь, а не в `Labels`: единственный читатель.
  # Появится второй — переезжает туда вместе с тестом.
  defp slots_word(count) do
    last_two = rem(abs(count), 100)
    last = rem(last_two, 10)

    cond do
      last_two in 11..14 -> "слотов"
      last == 1 -> "слот"
      last in 2..4 -> "слота"
      true -> "слотов"
    end
  end

  defp panel_value(stats, :skill_points), do: stats.skill_points.earned
  defp panel_value(stats, :skill_free), do: stats.skill_points.free

  # ⚠️ `&&`, а не `.attack_bonus`/`.attacks_per_round` напрямую: у превью без
  # второй руки (гипотеза почти всегда верна, см. `Summary`'s moduledoc про
  # то, что вторая рука не зависит от предпросматриваемых класса/расы/стата)
  # `off_hand` тоже `nil`, и `GearPanel.diff/2` уже умеет пару `nil`/`nil` —
  # падать здесь не на чем.
  defp panel_value(stats, :off_hand_ab), do: stats.off_hand && stats.off_hand.attack_bonus

  defp panel_value(stats, :off_hand_apr),
    do: stats.off_hand && stats.off_hand.attacks_per_round

  defp panel_value(stats, key), do: Map.get(stats, key)

  # Тот же приём, что выше у HP/AB/AC/сейвов, но по КАЖДОЙ строке навыка —
  # `preview` уже полный `Rules.compute/2` кандидата, `skill_values` в нём
  # такая же карта `%{id => Skills.value()}`, как в `stats`. Ни одного
  # дополнительного пересчёта: и превью, и разбор термов (`Summary.
  # skill_totals/3`) читают ОДИН и тот же результат события — наведение на
  # карточку класса зовёт `Rules.compute/2` один раз, а не по разу на строку.
  #
  # ⚠️ Живёт в `Builder.TotalsPanel`, а не в `Summary.skill_totals/3` — тот
  # модуль общий для конструктора И экрана просмотра (его `skill_rows/3` зовут
  # оба), а «предпросмотр» есть только у сокета конструктора. Протащить
  # понятие ховера в общий модуль значило бы навязать его потребителю,
  # которому предпросмотр не нужен и не имеет смысла — там нечего наводить.
  defp skill_totals_with_ghost(ruleset, build, stats, preview) do
    for row <- Summary.skill_totals(ruleset, build, stats) do
      Map.put(row, :ghost, GearPanel.diff(row.value, preview_skill_total(preview, row.id)))
    end
  end

  defp preview_skill_total(nil, _id), do: nil

  defp preview_skill_total(preview, id) do
    case Map.get(preview.skill_values, id) do
      %{total: total} -> total
      _ -> nil
    end
  end
end
