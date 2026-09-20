defmodule BuildCalculatorWeb.Builder.GameLogImportPanel do
  @moduledoc """
  The "here's what we read" report for the game-log import dialog.

  The socket-facing half of `BuildCalculatorWeb.Builder.GameLogImport`, split
  out the same way `BuildCalculatorWeb.Builder.ImportPanel` sits beside
  `Builder.Import`: that module is named for the parse, this one for the form,
  the summary rows and the grouped issue list `BuilderLive` renders on top of
  it.
  """

  alias BuildCalculator.Rules.{Build, Gear, GearImport, Worn}
  alias BuildCalculatorWeb.Builder.GameLogImport
  alias BuildCalculatorWeb.Builder.Labels
  alias BuildCalculatorWeb.BuilderLive

  import Phoenix.Component, only: [to_form: 2]

  # ⚠️ Единственный `gettext` в этом файле — намеренно узкий (задача 3.213,
  # п.2 постановки): три причины `GearImport.worn_reason()` идут через него,
  # весь остальной русский текст этого модуля остался сырыми литералами
  # (CLAUDE.md §4, «интерфейс переведён на gettext лишь частично»). Расширять
  # это на `gear_reason_text/2` заодно значило бы отдельную задачу на 700+
  # строк, а не правку по месту.
  use Gettext, backend: BuildCalculatorWeb.Gettext

  # ------------------------------------------------------------- the import --

  def text(%{"game_log_import" => %{"text" => text}}) when is_binary(text), do: text
  def text(_params), do: ""

  def form(text), do: to_form(%{"text" => text}, as: :game_log_import)

  def report(result, text, ruleset) do
    %{
      text: text,
      result: result,
      summary: summary(result, ruleset),
      groups: groups(result.issues, ruleset),
      issue_count: length(result.issues),
      apply?: result.read.anything?,
      # Экипировка из `.билд+` (задача 3.187, часть B) — `nil` у обычного
      # `.билд`, шестнадцать старых фикстур этого не трогают.
      gear: gear_report(result, ruleset)
    }
  end

  defp summary(%{read: read}, ruleset) do
    [
      %{id: "levels", label: "Уровни", value: "#{read.levels} из #{read.level_cap}"},
      %{id: "race", label: "Раса", value: race_value(ruleset, read.race)},
      %{id: "feats-placed", label: "Фиты в слотах", value: Integer.to_string(read.feats_placed)},
      %{
        id: "feats-auto",
        label: "Авто (класс/раса)",
        value: Integer.to_string(read.feats_auto)
      },
      %{
        id: "feats-unresolved",
        label: "Фиты не распознаны",
        value: Integer.to_string(read.feats_unresolved)
      },
      %{
        id: "feats-not-placed",
        label: "Фиты не перенесены",
        value: Integer.to_string(read.feats_not_placed)
      },
      %{
        id: "increases",
        label: "Прибавки к характеристикам",
        value: Integer.to_string(read.ability_increases)
      },
      %{id: "skills", label: "Ранги навыков", value: Integer.to_string(read.skill_ranks)}
    ]
  end

  defp race_value(_ruleset, nil), do: "не прочитана"

  defp race_value(ruleset, race),
    do: "#{Labels.race_ru(ruleset, race)} (#{Labels.race_en(ruleset, race)})"

  # Same move `Builder.ImportPanel.import_groups/2` makes: order of first
  # appearance, so the ladder's own troubles come before the footnotes.
  defp groups(issues, ruleset) do
    issues
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {issue, index}, groups ->
      kind = GameLogImport.issue_kind(issue)
      item = %{id: index, text: GameLogImport.issue_text(issue, ruleset)}

      case Enum.find_index(groups, &(&1.kind == kind)) do
        nil -> groups ++ [%{kind: kind, items: [item]}]
        at -> List.update_at(groups, at, &%{&1 | items: &1.items ++ [item]})
      end
    end)
  end

  # ------------------------------------------------------ экипировка (3.187) --
  #
  # `.билд+` печатает раздел `=== Equipped ===`, и `GameLogImport.with_equipment/4`
  # уже свёл его в `result.build.gear` — одну «сумму», а не список вещей
  # (слово Dan, `Rules.GearImport`'s own moduledoc). Здесь — только показ,
  # три части по вёдрам отчёта (`Rules.GearImport.report()`):
  #
  #   * «применено» читает СРАЗУ `result.build.gear`, а не пересчитывает
  #     сумму по строкам `report.applied` вторым проходом — та самая ловушка
  #     «два независимых описания одной суммы» (CLAUDE.md, `Summary`'s own
  #     moduledoc про `terms_caption/1`), которой этот экран не должен
  #     повторять. ⚠️ Исключение — где `applied` называет ПОЗИЦИОННЫЙ факт,
  #     а не сумму: рука/щит (`report.weapons`), доспех (`report.worn`)
  #     и с задачи 3.211 поглощение стихий (`gear_resistance_rows/2`,
  #     `report.applied` фильтром `landed: {:resistance, …}`) — там читатель
  #     не реконструирует итог по стихии (тот уже лежит в `gear.resistances`,
  #     здесь не тронут вовсе), а показывает КАЖДУЮ прочитанную строку,
  #     включая проигравшую сравнение (`entry.counted?: false`), чего сумма
  #     сама по себе не расскажет;
  #   * «не наше» — счётчик, свёрнутый список раскрывает все строки, каждая —
  #     с ПРИЧИНОЙ (`entry.reason`, `gear_reason_text/2`), не только именем
  #     предмета и сырой строкой лога;
  #   * «не сложить» — причина по-русски и пример строки лога у каждой,
  #     сгруппированные по причине, тем же приёмом, что `groups/2` выше
  #     группирует `issues`.
  defp gear_report(%{gear_report: nil}, _ruleset), do: nil

  defp gear_report(%{build: %Build{gear: gear}, gear_report: report}, ruleset) do
    %{
      applied: gear_applied(gear, report, ruleset),
      # Где шапка второго поколения и предметы разошлись и что взяло верх
      # (`report.counts.notes`, задача 3.206) — по-русски, под «применено»:
      # это не «не сложить», число легло, просто игрок должен знать, откуда.
      notes: Enum.map(report.counts.notes, &gear_note_text/1),
      not_ours_count: length(report.not_ours),
      not_ours: gear_not_ours_lines(report.not_ours, ruleset),
      unresolved_count: length(report.unresolved),
      unresolved: gear_unresolved_groups(report, ruleset)
    }
  end

  defp gear_applied(%Gear{} = gear, report, ruleset) do
    %{
      abilities: gear_number_rows(gear.abilities, &Labels.ability/1),
      saves: gear_save_rows(gear),
      ac: gear_number_rows(gear.ac, &Labels.ac_type(ruleset, &1)),
      skills: gear_number_rows(gear.skills, &Labels.skill_name(ruleset, &1)),
      feats: gear_feat_labels(gear.feats, ruleset),
      # Второе поколение печати (3.206): руки, надетое, куски, крафт.
      hands: gear_hand_rows(gear, report, ruleset),
      # Третье поколение (3.213): база доспеха из `[BaseAC:n]` — своя строка,
      # не подмешанная к рукам: щит и меч в `hands` резолвятся по ИМЕНИ
      # (лог называет то же имя, что несёт справочник), а доспех — по ЧИСЛУ,
      # и без исходного имени игрок не может проверить перевод сам.
      worn: gear_worn_rows(report, ruleset),
      mini_sets: gear_mini_set_rows(gear, report),
      named_items: gear_named_item_rows(gear, report),
      # Поглощение стихий (задача 3.211) — строка на КАЖДУЮ прочитанную
      # строку лога, не на стихию: с двух предметов на одну стихию видно
      # ОБЕ, победившую и проигравшую, а не только сумму, которая легла
      # в `gear.resistances`. `gear_number_rows/2` для этого не годится —
      # она читает уже свёрнутую сумму по стихии и не может назвать
      # проигравшую строку отдельно.
      resistances: gear_resistance_rows(report, ruleset)
    }
  end

  # Строка на руку — только когда в руке что-то ЛЕГЛО в билд (`wields`):
  # «Warhammer +5», «Tower shield». Предмет в руке, который не лёг, стоит
  # в «не сложить» со своей причиной, второй раз его здесь не называем.
  defp gear_hand_rows(%Gear{} = gear, %{weapons: weapons}, ruleset) do
    for hand <- Gear.hands(),
        weapon = Map.get(weapons, hand),
        not is_nil(weapon),
        not is_nil(weapon.wields) do
      %{label: gear_hand_label(hand), value: gear_wields_text(weapon.wields, gear, hand, ruleset)}
    end
  end

  defp gear_hand_label(:main), do: "В руке"
  defp gear_hand_label(:off), do: "Вторая рука"
  defp gear_hand_label(other), do: to_string(other)

  defp gear_wields_text({:weapon, id}, %Gear{} = gear, hand, ruleset) do
    attack = Gear.weapon_bonus(gear, :attack, hand)
    name = Labels.weapon_name(ruleset, id)
    if attack == 0, do: name, else: "#{name} #{BuilderLive.signed(attack)}"
  end

  defp gear_wields_text({:worn, category, item}, _gear, _hand, ruleset) do
    with %{items: items} <- Worn.category(ruleset, category),
         %{name: name} when is_binary(name) <- Enum.find(items, &(&1.id == item)) do
      name
    else
      _unknown -> Atom.to_string(item)
    end
  end

  # Доспех из `[BaseAC:n]` (задача 3.213) — `report.worn` несёт запись по
  # каждому слоту, у которого снапшот объявляет `worn_category_by_base_ac`
  # (сегодня один, CHEST), и `nil`, когда в этом слоте у персонажа вообще
  # ничего нет. Строка ЕСТЬ у КАЖДОГО непустого слота, включая робу с базой 0
  # («None, clothing») — она не «доспеха нет», а «доспех есть и его база
  # ноль», и это ЗНАЧИМО (CLAUDE.md §3, слово Dan 19.08.2026: нулевая база
  # НЕ гасит AC-бонусы монаха): скрыть строку значило бы стереть ровно то, что
  # монаху важно увидеть после импорта.
  #
  # ⚠️ Формат значения — «имя из лога → английское имя у нас», а не одно
  # резолвленное имя, как у оружия и щита в `hands` выше. Там сопоставление
  # идёт по ИМЕНИ (лог печатает то же имя, что несёт справочник), здесь —
  # по ЧИСЛУ (`base_ac`), и без исходного имени рядом игрок не может
  # проверить сам, что «Нагрудник Призрака» — это действительно латы,
  # а не что-то ещё с той же базой.
  defp gear_worn_rows(%{worn: worn}, ruleset) do
    for {slot, entry} <- Enum.sort_by(worn, &elem(&1, 0)), not is_nil(entry) do
      %{
        label: gear_worn_row_label(slot),
        value: gear_worn_value_text(entry, ruleset),
        note: entry.reason && gear_worn_reason_text(entry.reason)
      }
    end
  end

  defp gear_worn_row_label(:chest), do: "Доспех"
  defp gear_worn_row_label(other), do: gear_slot_label(other)

  defp gear_worn_value_text(%{wears: {:worn, category, item}, name: name}, ruleset),
    do: "#{name} → #{gear_wields_text({:worn, category, item}, nil, nil, ruleset)}"

  defp gear_worn_value_text(%{wears: nil, name: name}, _ruleset), do: name

  # «3 + 2 + 2 = 7 кусков» — группы как они легли в `Gear.mini_sets`; пусто,
  # когда кусков нет. Одна группа размером в шапку без `[SetID]` (Бор) печатает
  # просто «4 куска», а откуда взялось число — говорит `notes`.
  defp gear_mini_set_rows(%Gear{mini_sets: []}, _report), do: []

  defp gear_mini_set_rows(%Gear{mini_sets: groups}, _report) do
    total = Enum.sum(groups)

    value =
      case groups do
        [_one] -> pieces_word(total)
        many -> "#{Enum.map_join(many, " + ", &Integer.to_string/1)} = #{pieces_word(total)}"
      end

    [%{label: Labels.mini_sets_name(), value: value}]
  end

  defp gear_named_item_rows(%Gear{named_items: 0}, _report), do: []

  defp gear_named_item_rows(%Gear{named_items: count}, %{counts: %{craft_marked: marked}}) do
    names = if marked == [], do: "", else: " (#{Enum.join(marked, ", ")})"
    [%{label: "Крафтовые вещи", value: "#{count}#{names}"}]
  end

  # Поглощение стихий (задача 3.211) — строка `Damage Resistance (<стихия>)
  # N`, ОДНА НА ЗАПИСЬ ЛОГА, а не на стихию: у Хнюпиуса на мече и `Fire`,
  # и `Cold` по 15, и обе строки должны быть видны, даже если у стихии есть
  # соперник (эффект расы победил бы у обеих — см. `entry.counted?` ниже).
  #
  # ⚠️ `entry.counted?: false` — «прочитано, понято, но не вошло» (у AC того
  # же типа то же слово, `Rules.GearImport`'s own moduledoc), а не «не наше»
  # и не «не сложить»: строка остаётся среди «применено», просто с пометкой.
  defp gear_resistance_rows(%{applied: applied}, ruleset) do
    for %{landed: {:resistance, type, value}} = entry <- applied do
      %{
        label: Labels.resistance_energy_type_name(ruleset, type),
        value: Integer.to_string(value),
        note: unless(entry.counted?, do: "не вошла: на другом предмете больше")
      }
    end
  end

  defp pieces_word(n) when rem(n, 10) == 1 and rem(n, 100) != 11, do: "#{n} кусок"
  defp pieces_word(n) when rem(n, 10) in 2..4 and rem(n, 100) not in 12..14, do: "#{n} куска"
  defp pieces_word(n), do: "#{n} кусков"

  # `report.counts.notes` (задача 3.206) — по-русски, с числами обеих сторон.
  defp gear_note_text({:mini_set_groups_unverified, header, []}),
    do:
      "мини-сеты: сервер насчитал #{pieces_word(header)}, а наборы у кусков не напечатаны — " <>
        "записано одним набором, для расчёта это то же число"

  defp gear_note_text({:mini_set_groups_unverified, header, groups}),
    do:
      "мини-сеты: сервер насчитал #{pieces_word(header)}, а по номерам наборов выходит " <>
        "#{Enum.join(groups, " + ")} — записано числом сервера, одним набором"

  defp gear_note_text({:craft_marks_disagree, named, marked}),
    do:
      "крафтовые вещи: по шапке сервера #{named}, а пометок [CRAFT] у предметов #{marked} — " <>
        "записано число сервера"

  defp gear_note_text({:craft_items_below_pieces, craft, pieces}),
    do:
      "крафтовые вещи: шапка называет #{craft} при #{pieces_word(pieces)} мини-сетов — " <>
        "разность отрицательна, записан ноль"

  defp gear_note_text(other), do: inspect(other)

  defp gear_number_rows(map, label_fun) do
    for {id, value} <- Enum.sort_by(map, &elem(&1, 0)) do
      %{label: label_fun.(id), value: BuilderLive.signed(value)}
    end
  end

  defp gear_save_rows(%Gear{saves: universal, saves_specific: specific}) do
    base =
      if universal != 0, do: [%{label: "ко всем", value: BuilderLive.signed(universal)}], else: []

    extra =
      for save <- [:fort, :ref, :will],
          value = Map.get(specific, save, 0),
          value != 0,
          do: %{label: gear_save_label(save), value: BuilderLive.signed(value)}

    base ++ extra
  end

  defp gear_save_label(:fort), do: "Fort"
  defp gear_save_label(:ref), do: "Ref"
  defp gear_save_label(:will), do: "Will"

  # ------------------------------------------------- one line per zone --

  @doc """
  One line for a zone of «применено»: the zone's rows joined with a comma.

  Задача 3.215 (репорт Dan 18.09.2026, вслед за 3.214): каждая зона отчёта
  печаталась спаном на пункт БЕЗ разделителя, и «Характеристики CON +15
  DEX +6» читались раздельно только за счёт пробела внутри многострочного
  `<span>` — форматор или правка в одну строку склеили бы их так же, как
  склеились фиты («Blind fightCleaveEpic toughness»). Один разделитель на
  весь блок, явный, здесь, а не в разметке.

  Rows are `%{label, value}` (`"CON +15"`), `%{label, value, note}` (the
  note in parentheses — `"Cold 15 (не вошла: …)"`) or bare strings (feat
  names). `between:` is what stands between label and value: a space by
  default, `": "` for the hands («В руке: Bastard sword +6»).
  """
  @spec applied_line([map() | String.t()], keyword()) :: String.t()
  def applied_line(rows, opts \\ []) do
    between = Keyword.get(opts, :between, " ")
    Enum.map_join(rows, ", ", &applied_row_text(&1, between))
  end

  defp applied_row_text(name, _between) when is_binary(name), do: name

  defp applied_row_text(%{label: label, value: value} = row, between) do
    case Map.get(row, :note) do
      nil -> "#{label}#{between}#{value}"
      note -> "#{label}#{between}#{value} (#{note})"
    end
  end

  # 🔴 Одна строка на ЗАПИСЬ, а не на объявление (задача 3.224): повторное
  # объявление — это второе ВЗЯТИЕ (`Epic Toughness II`+`III` с сапог, 3.204;
  # `Epic energy resistance` со ступенью, 3.210), и печаталось оно тем же
  # именем дважды подряд («Epic toughness, Epic toughness») — читается как
  # сбой отчёта, а не как «взято два раза». Число берёт на себя `×N`, ровно
  # тем же словарём, каким его печатает блок «Вещи» (`GearPanel`) и разбор
  # резиста (`Summary.resistance_terms/3`).
  #
  # ⚠️ `Enum.uniq/1` до маппинга, а не `Enum.uniq_by/2` после: считается
  # ЗАПИСЬ (пара «фит + значение»), а не её подпись — два разных фита
  # с одинаковым именем в снапшоте слились бы в одну строку.
  defp gear_feat_labels(feats, ruleset) do
    counts = Enum.frequencies(feats)

    for entry <- Enum.uniq(feats) do
      id = Build.feat_id(entry)
      name = Labels.feat_name(ruleset, id)

      name =
        case Build.feat_choice(entry) do
          nil -> name
          choice -> "#{name} (#{Labels.choice_name(ruleset, id, choice)})"
        end

      case Map.fetch!(counts, entry) do
        1 -> name
        takes -> "#{name} ×#{takes}"
      end
    end
  end

  # 🔴 Задача 3.211, находка агента: до этой правки `reason` записи
  # печатался в отчёт ядра (`Rules.GearImport.refusal/3`), но эта функция его
  # игнорировала — «не наше» называло предмет и сырую строку, а НЕ причину,
  # хотя причина у КАЖДОЙ записи этого ведра есть всегда. Постановка 3.211,
  # п.3 просила именно причину у физического поглощения («решением не
  # считаем»), но чинить только для одного `kind` значило бы оставить ту же
  # дыру у остальных не-наших механик (`Quality`, божественный урон) — правка
  # общая, а не по одному вердикту.
  defp gear_not_ours_lines(entries, ruleset) do
    for entry <- entries,
        do: "#{entry.item}: #{entry.raw} — #{gear_reason_text(entry.reason, ruleset)}"
  end

  # Группировка по ПРИЧИНЕ (`entry.reason`'s own head), тем же приёмом, что
  # `groups/2` группирует `issues` по `issue_kind/1` — заголовок группы это
  # список доработок серверу (задача 3.187, п. 9), а не список строк.
  defp gear_unresolved_groups(%{unresolved: entries} = report, ruleset) do
    entries
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {entry, index}, groups ->
      kind = gear_reason_kind(entry.reason)
      item = %{id: index, text: gear_reason_line(entry, report.weapons, ruleset)}

      case Enum.find_index(groups, &(&1.kind == kind)) do
        nil -> groups ++ [%{kind: kind, items: [item]}]
        at -> List.update_at(groups, at, &%{&1 | items: &1.items ++ [item]})
      end
    end)
  end

  # `def`, а не `defp` — задача 3.213, п. 4: гарду
  # `GameLogImportPanelReasonLabelsTest` нужно перебрать `GearImport.
  # reason_examples/0` и убедиться, что ни одна форма не спасается фолбэком
  # «Не распознано» молча. Наружу как публичный API модуль по-прежнему
  # не заявляет — `@doc false` у обеих функций.
  @doc false
  @spec gear_reason_kind(GearImport.reason()) :: String.t()
  def gear_reason_kind({:weapon_base_type_unknown, _kind}), do: "Оружие в руки не надето"
  def gear_reason_kind({:base_type_unresolved, _text}), do: "Оружие в руки не надето"
  def gear_reason_kind({:base_type_not_a_weapon, _text}), do: "Оружие в руки не надето"
  def gear_reason_kind({:weapon_numbers_not_reconciled, _kinds}), do: "Оружие в руки не надето"
  def gear_reason_kind({:mini_set_group_unknown, nil}), do: "Мини-сеты"
  def gear_reason_kind({:named_item_flag_missing, _flag}), do: "Крафтовые вещи"
  def gear_reason_kind({:ac_type_unknown, _slot, _alts}), do: "Тип AC не назван"
  def gear_reason_kind({:feat_unknown, _}), do: "Фит не найден"
  def gear_reason_kind({:feat_repeat_not_expressible, _id}), do: "Повтор фита с вещи"
  def gear_reason_kind({:decided_not_modelled, _}), do: "Решением не считаем"
  def gear_reason_kind({:property_not_modelled, _}), do: "Не наша механика"

  # 🔴 Задача 3.221: «имя свойства не прочитано» — НЕ «не наша механика».
  # Своя группа и своя фраза именно для того, чтобы правка чужой печати была
  # видна как правка чужой печати: до неё такая строка лежала в «не нашем»
  # среди `Cast Spell` и `Regeneration`, и отличить её было нечем.
  def gear_reason_kind({:property_name_unknown, _raw}), do: "Имя свойства не распознано"
  def gear_reason_kind({:slot_unknown, _}), do: "Слот не распознан"
  def gear_reason_kind({:value_missing, _}), do: "Нет числа"

  # 🔴 Три формы, которых здесь не было до задачи 3.213 (находка агента
  # ядра): `known/3` производит их не только теоретически — `GearImport
  # ReasonExamplesTest` воспроизводит все три реальным вызовом. До этой
  # правки они тихо падали в фолбэк ниже вместе с настоящим мусором.
  def gear_reason_kind({:ability_unknown, _}), do: "Характеристика не распознана"
  def gear_reason_kind({:skill_unknown, _}), do: "Навык не распознан"
  def gear_reason_kind({:save_unknown, _}), do: "Спас не распознан"

  # Задача 3.210: имя вида урона, которого нет ни в словаре семи стихий,
  # ни в списке исключённых.
  def gear_reason_kind({:resistance_unknown, _}), do: "Вид урона не распознан"
  def gear_reason_kind(_other), do: "Не распознано"

  defp gear_reason_line(%{reason: reason, raw: raw} = entry, weapons, ruleset) do
    "#{gear_reason_text(reason, ruleset)}: #{gear_item_label(entry, weapons)} (#{raw})"
  end

  # «Меч Драконов: +6» — число берётся из СВОДКИ ядра (`report.weapons`,
  # задача 3.199), а не из этой строки лога: чисел у предмета бывает два
  # (`Attack Bonus` и `Enhancement Bonus`), и напечатать то, что стоит
  # в строке, значило бы назвать не то число, которое впишется в «Вещи».
  defp gear_item_label(%{reason: {reason, _}} = entry, weapons)
       when reason in [:weapon_base_type_unknown, :base_type_unresolved, :base_type_not_a_weapon] do
    case Enum.find_value(weapons, fn {_hand, weapon} ->
           weapon && weapon.slot == entry.slot && weapon.attack
         end) do
      nil -> entry.item
      attack -> "#{entry.item}: #{BuilderLive.signed(attack)}"
    end
  end

  defp gear_item_label(%{item: item}, _weapons), do: item

  @doc false
  @spec gear_reason_text(GearImport.reason(), map()) :: String.t()
  def gear_reason_text({:weapon_base_type_unknown, _kind}, _ruleset),
    do: "оружие в руки не надето — базовый тип оружия лог не печатает"

  # Второе поколение печати (3.206): тип напечатан, а мы его не сложили —
  # и причина у каждой строки своя, чтобы игрок знал, что чинить: справочник
  # (имени нет), руку (это не оружие для неё) или снапшот (правила свода нет).
  def gear_reason_text({:base_type_unresolved, text}, _ruleset),
    do: "оружие в руки не надето — базовый тип «#{text}» не найден в справочнике, впишите руками"

  def gear_reason_text({:base_type_not_a_weapon, text}, _ruleset),
    do: "в эту руку не надевается — «#{text}» не оружие, впишите руками"

  def gear_reason_text({:weapon_numbers_not_reconciled, _kinds}, _ruleset),
    do: "у предмета два числа атаки, а правила свода в этом ruleset'е нет — впишите одно руками"

  def gear_reason_text({:mini_set_group_unknown, nil}, _ruleset),
    do: "мини-сеты: кусок помечен, набор не назван — введите куски руками"

  def gear_reason_text({:named_item_flag_missing, _flag}, _ruleset),
    do: "крафтовые вещи: лог не помечает крафт, Quality — артефактный сет"

  def gear_reason_text({:ac_type_unknown, slot, alternatives}, ruleset) do
    alts = Enum.map_join(alternatives, "/", &Labels.ac_type(ruleset, &1))
    "AC на слоте #{gear_slot_label(slot)}: тип #{alts} не назван — впишите руками"
  end

  def gear_reason_text({:feat_unknown, {:unresolved, text}}, _ruleset),
    do: "фит «#{text}» не найден в словаре"

  def gear_reason_text({:feat_unknown, other}, _ruleset),
    do: "фит #{inspect(other)} не найден"

  # ⚠️ Задача 3.204, часть B, сузила носителей этой причины до ДВУХ (была шире
  # до правки задачи 3.204, часть A): повторяемый фит С ВЫБОРОМ
  # (`epic_energy_resistance` — повторяется ПАРА, а какую копию одалживает
  # предмет, лог не говорит) и повторяемый БЕЗ выбора, объявленный БЕЗ
  # ступени (лог не печатает номер взятия, значит различить копии нечем).
  # В обоих случаях невыразимое — это именно СОВПАДЕНИЕ значения/номера,
  # поэтому формулировка называет его прямо, а не общим «второе взятие».
  def gear_reason_text({:feat_repeat_not_expressible, id}, ruleset),
    do:
      "второе взятие «#{Labels.feat_name(ruleset, id)}» с тем же значением с вещи не выразить (3.29)"

  def gear_reason_text({:decided_not_modelled, :spell_resistance}, _ruleset),
    do: "сопротивление заклинаниям с вещей не вводится (решение Dan)"

  # 🔴 Задача 3.210: поглощение ФИЗИЧЕСКОГО урона. Получатель у него наш — это
  # те же строки `Damage Resistance (…)`, по которым считаются стихии, — и
  # именно поэтому фраза «решением не считаем», а не «не наша механика»:
  # секция заведена без физического урона по прямому слову Dan 13.09.2026
  # («поглощение стихийного урона, без физического»).
  def gear_reason_text({:decided_not_modelled, :physical}, _ruleset),
    do: "поглощение физического урона не считаем — секция «Резисты» только про стихии"

  # Имя вида урона, которого не знает ни словарь семи стихий, ни список
  # исключённых. В отличие от двух фраз выше — это НАШ вопрос, и строка
  # попадает в список доработок сервера, а не в «не наше».
  def gear_reason_text({:resistance_unknown, value}, _ruleset),
    do: "вид урона #{gear_unresolved_param(value)} не распознан"

  def gear_reason_text({:property_not_modelled, name}, _ruleset),
    do: "не наша механика (#{name})"

  # ⚠️ Сама строка лога здесь НЕ повторяется: `gear_reason_line/3` печатает её
  # следом в скобках, и до задачи 3.221 неузнанное имя попадало на экран дважды
  # («не наша механика ([3] X 4): предмет ([3] X 4)»).
  def gear_reason_text({:property_name_unknown, _raw}, _ruleset),
    do: "имя свойства не распознано — форма печати сервера могла измениться"

  def gear_reason_text({:slot_unknown, slot}, _ruleset),
    do: "слот #{inspect(slot)} не распознан"

  def gear_reason_text({:value_missing, kind}, _ruleset),
    do: "нет числа у свойства #{kind}"

  # 🔴 Три формы задачи 3.213 (см. `gear_reason_kind/1` выше): `known/3`
  # передаёт сюда либо `{:unresolved, text}` (лог назвал что-то, чего
  # `GameLog.equip_atom/2` не узнал — обычный случай), либо голый атом,
  # которого нет в списке допустимых (редкий, но тип его не исключает).
  def gear_reason_text({:ability_unknown, value}, _ruleset),
    do: "характеристика #{gear_unresolved_param(value)} не распознана"

  def gear_reason_text({:skill_unknown, value}, _ruleset),
    do: "навык #{gear_unresolved_param(value)} не распознан"

  def gear_reason_text({:save_unknown, value}, _ruleset),
    do: "спас #{gear_unresolved_param(value)} не распознан"

  def gear_reason_text(other, _ruleset), do: inspect(other)

  defp gear_unresolved_param({:unresolved, text}), do: "«#{text}»"
  defp gear_unresolved_param(other), do: inspect(other)

  # Три причины «база доспеха не легла» (`GearImport.worn_reason/0`, задача
  # 3.213). ⚠️ Единственный `gettext` в этом модуле (см. `use Gettext` в шапке
  # файла) — п. 2 постановки требовал именно эти три через него; остальной
  # текст файла остался сырыми литералами.
  @doc false
  @spec gear_worn_reason_text(GearImport.worn_reason()) :: String.t()
  def gear_worn_reason_text({:armor_base_not_printed, slot}),
    do:
      gettext(
        "the armour is worn, but the log does not print its base (an older saved log, %{slot}) — fill it in by hand",
        slot: gear_slot_label(slot)
      )

  def gear_worn_reason_text({:armor_base_unresolved, base_ac}),
    do:
      gettext(
        "armour base %{base} is not in the reference data — fill it in by hand",
        base: base_ac
      )

  def gear_worn_reason_text({:armor_base_rule_missing, slot}),
    do:
      gettext(
        "the snapshot does not name a category for this armour base (%{slot}) — fill it in by hand",
        slot: gear_slot_label(slot)
      )

  def gear_worn_reason_text(other), do: inspect(other)

  defp gear_slot_label(:arms), do: "ARMS"
  defp gear_slot_label(:left_hand), do: "LEFTHAND"
  defp gear_slot_label(:chest), do: "CHEST"
  defp gear_slot_label(other), do: other |> Atom.to_string() |> String.upcase()

  def flash([{:alignment_unavailable}]),
    do: "Билд перенесён — прочиталось всё, что лог несёт. Мировоззрение впиши вручную."

  def flash(issues),
    do:
      "Билд перенесён. Не всё легло без вопросов (#{length(issues)}) — открой окно снова, " <>
        "список на месте."
end
