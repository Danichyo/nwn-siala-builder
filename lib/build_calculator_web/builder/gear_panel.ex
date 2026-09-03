defmodule BuildCalculatorWeb.Builder.GearPanel do
  @moduledoc """
  The "Вещи" block: typed-in equipment totals, and the hover preview.

  Split out of `BuildCalculatorWeb.BuilderLive` (задача 3.46, заход 4, marker
  "gear"): not an armoury (CLAUDE.md §6) — the player types what their
  equipment gives, and the cascade (`assign_gear/1`) is ours to work out. The
  preview functions (`preview_stats/1` and friends) live in the same file
  because the totals panel's hover preview and the gear cascade read the same
  `Rules.compute/2` shape; splitting them further would not remove a
  dependency, only hide it behind another module.

  `chip_rows/1` stayed behind in `BuilderLive` — the `.heex` template calls it
  bare, and a formatting one-liner is not worth an `import` just to keep it
  here. `signed/1` (used for every "+N"/"-N" in this file) and
  `gear_input_limit/0` (the `input_min` boundary shared with
  `BuilderLive.gear_number/1`) stayed there for the same kind of reason —
  see their own docs.
  """

  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Caps, FeatSlots, Gear, Worn}
  alias BuildCalculatorWeb.Builder.{Feats, Fuzzy, Icons, Labels, Palette, Summary}
  alias BuildCalculatorWeb.BuilderLive

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4]

  # ---- gear ----

  # Not an armoury: the player types the totals their equipment gives, and the
  # cascade is ours to work out (CLAUDE.md §6). The point of the whole block is
  # that `+12 CON` is not "+12 CON" — it is +6 to the modifier, which is +6 hit
  # points on **every** level and +246 on a level 41 build. That is the sum
  # players get wrong by hand, so it is spelled out as `было → стало` instead of
  # being left to be noticed in the panel above.
  def assign_gear(socket) do
    %{ruleset: ruleset, build: %Build{gear: gear} = build, stats: stats} = socket.assigns
    %{gear_feat_choice_query: choice_query} = socket.assigns
    ability_cap = ruleset.gear.ability_bonus_cap
    save_cap = Caps.cap(ruleset, :saving_throw_bonus)
    applied = stats.gear_ability_bonuses

    abilities =
      for ability <- Labels.ability_order() do
        typed = Map.get(gear.abilities, ability, 0)

        %{
          id: ability,
          label: Labels.ability(ability),
          value: typed,
          capped?: typed != Map.get(applied, ability, typed),
          # Тот же оттенок, что у карточки характеристики в «Итого» (CLAUDE.md
          # §6/3.47): цвет дублирует подпись «STR» рядом с числом, не несёт
          # смысл в одиночку, поэтому это не новый язык, а повтор уже принятого.
          hue: Palette.ability_hue(ability),
          # Задача 3.47 (жалоба Dan: «восемнадцать одинаковых нулей, не видно,
          # что я вообще ввёл»). Ноль и нетронутое поле неотличимы по данным
          # билда (оба ничего не меняют в расчёте), поэтому «заполнено» здесь
          # значит буквально «отлично от нуля» — честно и для введённого нуля,
          # и для нетронутого поля: оба выглядят как «нечего показать».
          filled?: typed != 0
        }
      end

    # ⚠️ В поле показывается ВВЕДЁННОЕ число, а в расчёт идёт срезанное
    # (`stats.ac_by_type`). Поле ввода, которое молча переписывает набранное
    # игроком, читается как поломка — та же развязка, что у характеристик выше.
    # Потолок сегодня есть ровно у одного типа, «уклонения»; остальные четыре
    # проходят как есть, и тогда два числа просто совпадают.
    capped_ac = MapSet.new(stats.ac_capped_types)

    # 🔴 И вторая причина, по которой введённое число может не доехать до итога
    # (задача 3.39): внутри одного типа вписанное не складывается с собственной
    # прибавкой билда, а конкурирует с ней — берётся большее. Молча съеденное
    # число читается как поломка ровно так же, как молча срезанное, поэтому
    # у него своя строка рядом.
    superseded_ac = MapSet.new(stats.ac_superseded_types)

    # База выбранного предмета по типам — чтобы строка «вписанное не доехало»
    # не противоречила выросшему числу: у типа с предметом +N всё-таки пришло,
    # просто не из введённого числа.
    ac_base = Map.new(stats.ac_types_resolved, &{&1.type, &1.base})

    ac_types =
      for {type, applied_value} <- stats.ac_by_type do
        typed = Map.get(gear.ac, type, 0)

        %{
          id: type,
          label: Labels.ac_type(ruleset, type),
          value: typed,
          applied: applied_value,
          base: Map.get(ac_base, type, 0),
          capped?: MapSet.member?(capped_ac, type),
          superseded?: MapSet.member?(superseded_ac, type),
          # Тот же принцип «заполнено = не ноль», что у характеристик выше.
          filled?: typed != 0
        }
      end

    # Надетое как ПРЕДМЕТ (задача 3.41): тип доспеха и размер щита. Категории,
    # их предметы и оба числа предмета — из ruleset'а; ни одного имени доспеха
    # в вёрстке и в этом модуле нет, ровно как у оружия.
    #
    # ⚠️ Причины отказа — из ЯДРА (`Rules.worn_candidates/3`, задача 3.43), а не
    # собранные здесь: «щит нельзя с двуручным» и «Карлик не носит башенный» —
    # игровые правила, и вторая их копия в вебе разошлась бы с первой.
    # Недоступный предмет из списка НЕ прячется, а показывается с причиной
    # (CLAUDE.md §6) — так блок заодно учит правилу.
    worn =
      for category <- Worn.categories(ruleset) do
        %{
          id: category.id,
          label: category.ru || Labels.ac_type(ruleset, category.ac_type),
          value: Gear.worn(gear, category.id),
          items: gear_worn_items(build, ruleset, category),
          # Выбор, а не число: «заполнено» здесь значит «предмет назван»,
          # тем же принципом, что у характеристик и AC выше.
          filled?: not is_nil(Gear.worn(gear, category.id))
        }
      end

    # Что записано в билде и носить нельзя — строкой с причиной, а не молча
    # вычтенным из чисел. Та же форма, что у оружия без владения и у фита,
    # который шард выключил: молча отобранное читается как поломка.
    worn_illegal =
      for {category_id, item_id, reason} <- Rules.illegal_worn(build, ruleset) do
        %{
          id: "#{category_id}-#{item_id}",
          # Задача 3.133: категория отдельным полем, а не только внутри `id` —
          # сводка предупреждений (`gear_issues/2`) ведёт клик к СЕЛЕКТУ этой
          # категории (`gear-worn-input-#{category}`), а разбирать `id` строкой
          # обратно значило бы завести вторую копию того же факта.
          category: category_id,
          # ⚠️ СЫРОЙ тапл, не только переведённая строка ниже — по нему
          # `weapon_blocks_worn_note/3` (задача 3.133, замечание 2) узнаёт,
          # какое ИМЕННО оружие вытеснило этот предмет, чтобы поставить
          # зеркальную пометку у него самого, «на обе стороны конфликта».
          cause: reason,
          name: gear_worn_name(ruleset, category_id, item_id),
          reason: Labels.reason(reason, ruleset)
        }
      end

    skills = gear_skill_rows(socket.assigns)
    picks = gear_feat_picks(socket.assigns)
    weapons = gear_weapon_options(socket.assigns, :main)

    # Вторая рука (задача 3.132, Dan: «можем ввести вторую руку? с
    # возможностью выбрать оружие вместо щита») — тот же пул и тот же фильтр
    # по фитам владения, только своя рука: `Rules.gear_weapon_candidates/3`
    # уже принимает её третьим аргументом, вторая копия правила не заводится.
    off_weapons = gear_weapon_options(socket.assigns, :off)

    gear_map =
      assign_gear_map(
        ruleset,
        build,
        gear,
        abilities,
        skills,
        stats,
        worn,
        worn_illegal,
        ac_types,
        save_cap,
        ability_cap,
        choice_query
      )

    socket
    # Список фитов — стрим, как оба списка секции фитов: словарь фитов это ровно
    # та коллекция в сотни строк, которую AGENTS.md велит не держать в ассайне.
    # `reset: true` на каждый `BuilderLive.refresh/1` не украшение: без него
    # строки прошлого запроса остаются в DOM (стрим сам ничего не убирает),
    # а контейнер, убранный из DOM и вернувшийся, оказался бы пустым — сервер
    # отданное не помнит.
    |> stream(:gear_feat_options, picks.shown, reset: true)
    |> assign(:gear_feat_shown, length(picks.shown))
    |> assign(:gear_feat_total, picks.total)
    # Список оружия — тоже стрим, и по той же причине: 42 строки в узкой колонке,
    # каждая со своей причиной отказа.
    |> stream(:gear_weapon_options, weapons.shown, reset: true)
    |> assign(:gear_weapon_shown, length(weapons.shown))
    |> assign(:gear_weapon_total, weapons.total)
    # Свой стрим у второй руки — списки не смешиваются: у каждой руки свой
    # хват и свои отказы (двуручное во вторую руку не берётся, а главная
    # рука с двуручным отбирает вторую целиком).
    |> stream(:gear_off_weapon_options, off_weapons.shown, reset: true)
    |> assign(:gear_off_weapon_shown, length(off_weapons.shown))
    |> assign(:gear_off_weapon_total, off_weapons.total)
    |> assign(:gear_skill_chips, gear_skill_chips(socket.assigns, skills))
    |> assign(:gear, Map.put(gear_map, :issues, gear_issues(ruleset, gear_map)))
  end

  # ⚠️ Литерал карты `@gear` переехал в переменную ДО пайплайна ровно ради
  # одного: `issues` (сводка предупреждений, задача 3.133) обязана читать уже
  # СОБРАННЫЕ числа `@gear`, а не считать те же самые вторым проходом — та же
  # ловушка «два независимых описания одной суммы», уже стоившая этому
  # экрану расхождения (см. `Summary.terms_caption/1`'s moduledoc). Раньше
  # карта строилась прямо внутри `assign(:gear, %{...})`; содержимое ниже —
  # то же самое, просто с именем.
  defp assign_gear_map(
         ruleset,
         build,
         gear,
         abilities,
         skills,
         stats,
         worn,
         worn_illegal,
         ac_types,
         save_cap,
         ability_cap,
         choice_query
       ) do
    %{
      any?: Gear.any?(gear),
      summary: gear_summary(abilities, skills, stats, gear, worn),
      skills: skills,
      # Потолок берётся из ruleset'а, как и у сейвов: 50 в разметке было бы
      # игровым числом в вёрстке. ⚠️ И подпись говорит «общий», потому что в те
      # же +50 входит расовый бонус Сиалы — обещание «максимум +50 со шмота»
      # стало бы неправдой ровно у Человека с дисциплиной.
      skill_cap: Caps.cap(ruleset, :skill_bonus),
      feats: gear_feat_rows(ruleset, build, choice_query),
      # Граница формы, а не правило игры: у `min` полей она обязана совпадать
      # с тем, что `BuilderLive.gear_number/1` реально принимает, иначе браузер
      # обещает одно, а расчёт делает другое.
      input_min: -BuilderLive.gear_input_limit(),
      ability_cap: ability_cap,
      ability_label: cap_hint("Характеристики", ability_cap, "на каждую"),
      abilities: abilities,
      abilities_capped?: :gear_abilities in stats.capped,
      ac_types: ac_types,
      worn: worn,
      worn_illegal: worn_illegal,
      # Ловкость под потолком надетого доспеха. ⚠️ В строке итога печатается
      # ДОШЕДШЕЕ число, иначе она перестала бы сходиться со своим же итогом
      # у любого, кто надел латы.
      ac_dex: stats.ac_dexterity,
      ac: %{
        base: ruleset.base_ac,
        dex: stats.ac_dexterity.counted,
        # ⚠️ Что реально ДОШЛО с вещей, а не что вписано: с задачи 3.39 вписанное
        # может проиграть собственной прибавке билда, а с 3.41 к нему добавляется
        # база предмета. Строка обязана сходиться со своим итогом — иначе она
        # объясняет число, которого нет.
        gear: Enum.reduce(stats.ac_by_type, 0, fn {_type, value}, sum -> sum + value end),
        # И собственные прибавки билда — их в этой строке не было вовсе с задачи
        # 3.11, то есть у монаха она не сходилась.
        #
        # ⚠️ ИМЕНОВАННЫМИ, а не одним числом (задача 3.59B): раньше здесь лежала
        # сумма `ac_own_bonus_geared + ac_cap_clipped`, и Dan принял её на своём
        # билде за монашескую колонку — а это был Кувырок, та же арифметика
        # («+1 за каждые 5»), другой источник. Сумма из ассайна убрана, а не
        # оставлена рядом: ключ, который никто не читает, через месяц читается
        # как «строка считается вот этим». Итог сходится терм за термом —
        # срезанное капом типа входит в список отдельным термом.
        own_terms: Summary.ac_own_cascade_terms(ruleset, stats),
        total: stats.ac_geared
      },
      save_cap: save_cap,
      save_label: save_label(save_cap),
      save_value: gear.saves,
      save_filled?: gear.saves != 0,
      # ⚠️ Любой из трёх (задача 1.12a), не общий `:saving_throws`: поле ввода
      # одно на все три сейва, а капнуть теперь может не все три сразу —
      # индикатору у ЭТОГО поля достаточно, что упёрлось хоть куда-то.
      saves_capped?: Enum.any?([:fort_save, :ref_save, :will_save], &(&1 in stats.capped)),
      # ⚠️ Потолок +20 — ОДИН на два источника: вещи и Spellcraft вместе.
      # Раньше срезались только вещи, и подпись объясняла срез введённым
      # числом. Теперь ввести можно и меньше потолка, а срежет всё равно —
      # поэтому подпись обязана назвать вторую половину.
      save_from_skill: Map.get(stats, :skill_save_bonus, 0) || 0,
      # Оружие в руках и два его числа (задача 3.5, часть B). `weapon` — `nil`,
      # пока игрок ничего не выбрал; строка с причиной появляется, когда оружие
      # в билде есть, а держать его нельзя (снят фит владения) — молча отобранное
      # читается как баг, названное как правило (та же форма, что у сброса
      # поинт-бая).
      weapon: gear_weapon_row(ruleset, build, :main, worn_illegal),
      weapon_attack: gear.weapon_attack,
      weapon_attack_filled?: gear.weapon_attack != 0,
      # Подпись поля: кап +20 общий на это число И на расовый бонус Сиалы, поэтому
      # обещать «максимум +20 с оружия» нельзя — ровно тот же довод, что у сейвов.
      weapon_cap: Caps.cap(ruleset, :attack_bonus),
      weapon_label: weapon_label(Caps.cap(ruleset, :attack_bonus)),
      weapon_capped?: :attack_bonus in stats.capped,
      # Вторая рука (задача 3.132) — та же форма, что у главной, своим полем
      # билда. ⚠️ Кап читается НЕ из общего `stats.capped` (тот один на СТАТ,
      # а не на руку — `DerivedStats`, «значок один, потому что и стат один»),
      # а из `stats.off_hand.attack_capped?` — своего, посчитанного этой руке:
      # иначе главная рука показывала бы «упёрлось», когда упёрлась только
      # вторая, и наоборот.
      off_weapon: gear_weapon_row(ruleset, build, :off, worn_illegal),
      off_weapon_attack: gear.off_hand_weapon_attack,
      off_weapon_attack_filled?: gear.off_hand_weapon_attack != 0,
      off_weapon_capped?: !!(stats.off_hand && stats.off_hand.attack_capped?),
      cascade: gear_cascade(build, ruleset, stats)
    }
  end

  @doc """
  Сводка предупреждений «Вещей» (задача 3.133).

  Dan, 28.08.2026 (замечание 2 к задаче 3.132): «у меня был выбран щит и это
  не помешало мне выбрать второе оружие. Щит перестал считаться… но опять же
  не очень понятно, что именно щит не работает, для этого надо лезть
  в итоговые цифры». Решение (то же обсуждение): «блокировать не обязательно,
  просто предупреждение более явно выводить… можно где-то сверху в одном
  месте выводить все вонинги один за одним списком».

  ## Указатель, а не дубль

  Каждый разбросанный `.gear-capped`/`.gear-feat-bad` остаётся на месте —
  он отвечает «что не так ЗДЕСЬ», у своего органа управления (CLAUDE.md §6:
  недоступное показываем с причиной, а не молчанием, и уж тем более не
  переносим её в единственное место). Эта функция не пересчитывает те же
  числа второй раз (см. `assign_gear_map/12`'s комментарий выше про ловушку
  «два независимых описания одной суммы») — она читает уже собранную карту
  `@gear` и добавляет к каждой находке `target`: id элемента, к которому
  ведёт клик (`jump_to_gear_issue`, `BuilderLive`).

  ## Два разряда, а не один список с одной формулировкой

  «Ввёл больше, чем допускает потолок — посчитано ПО ПОТОЛКУ» и «то, что
  записано, вообще НЕ СЧИТАЕТСЯ» — разные факты о вводе, и смешивать их
  в одну фразу нельзя (замер координатора на живом проде: билд со щитом,
  вытесненным второй рукой, и двумя превышениями потолка даёт три
  предупреждения, а формулировка у них не может быть одной). `refused` —
  то, что не считается вовсе (вытесненное надетое, оружие без владения);
  `capped` — то, что считано, но урезано потолком правил Сиалы.

  ## Ворота — снаружи, здесь только счёт

  Пустой список — обычный случай (у билда без конфликтов оба списка `[]`),
  и решает, рисовать ли блок вообще, разметка (`@gear.issues.count > 0`),
  тем же приёмом, что у `#builder-notice`/`#gaps-data` (задача 3.88):
  постоянная плашка «проблем нет» была бы тем самым ложным спокойствием,
  которое то решение уже убрало с этого экрана.
  """
  @spec gear_issues(map(), map()) :: %{
          refused: [map()],
          capped: [map()],
          count: non_neg_integer()
        }
  def gear_issues(ruleset, gear) do
    refused = worn_issues(gear) ++ weapon_issues(ruleset, gear)
    capped = capped_issues(gear)
    %{refused: refused, capped: capped, count: length(refused) + length(capped)}
  end

  # Вытесненное надетое (щит убран двуручным или вторым оружием, Карлик не
  # носит башенный щит и т.п.) — `@gear.worn_illegal` уже несёт готовое
  # русское `reason` (см. `assign_gear_map/12`), поэтому здесь только состав
  # предложения и цель клика — СЕЛЕКТ этой категории, а не сообщение о ней:
  # Dan просил «где-то сверху» именно как указатель на орган управления.
  defp worn_issues(gear) do
    for row <- gear.worn_illegal do
      %{
        id: "worn-#{row.id}",
        text: "#{row.name}: #{row.reason}",
        target: "gear-worn-input-#{row.category}"
      }
    end
  end

  # Оружие в руках (обе руки), которое держать нельзя — снятый фит владения.
  # `weapon.reason`/`off_weapon.reason` хранятся СЫРЫМ таплом (как и печатает
  # их разметка через `Labels.reason/2` в шаблоне, `#gear-weapon-bad`);
  # переводим здесь той же функцией, а не второй копией текста.
  defp weapon_issues(ruleset, gear) do
    [{gear.weapon, "gear-weapon"}, {gear.off_weapon, "gear-off-weapon"}]
    |> Enum.filter(fn {row, _target} -> row && row.reason end)
    |> Enum.map(fn {row, target} ->
      %{id: target, text: "#{row.name}: #{Labels.reason(row.reason, ruleset)}", target: target}
    end)
  end

  # Всё, что срезано потолком правил Сиалы. Числа и формулировки — те же,
  # что у соответствующей `.gear-capped` строки в разметке (`@gear.
  # ability_cap`, `@gear.save_cap`, `@gear.skill_cap`, `@gear.weapon_cap`,
  # `row.applied` у типа AC) — сводка не вводит ни одного нового числа,
  # только короче формулирует уже посчитанное.
  defp capped_issues(gear) do
    [
      capped_issue(
        gear.abilities_capped?,
        "abilities",
        "Характеристики: срезано до потолка +#{gear.ability_cap}",
        "gear-abilities-capped"
      ),
      capped_issue(
        gear.ac_dex.capped?,
        "ac-dex",
        "Ловкость к AC: доспех режет бонус до +#{gear.ac_dex.cap}",
        "gear-ac-dex-capped"
      ),
      capped_issue(
        gear.saves_capped?,
        "saves",
        "Спасы: срезано до потолка +#{gear.save_cap}",
        "gear-saves-capped"
      ),
      capped_issue(
        gear.weapon_capped?,
        "weapon",
        "AB главной руки (вещи): срезано до потолка +#{gear.weapon_cap}",
        "gear-weapon-capped"
      ),
      capped_issue(
        gear.off_weapon_capped?,
        "off-weapon",
        "AB второй руки (вещи): срезано до потолка +#{gear.weapon_cap}",
        "gear-off-weapon-capped"
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Kernel.++(ac_type_capped_issues(gear))
    |> Kernel.++(skill_capped_issues(gear))
  end

  defp capped_issue(false, _id, _text, _target), do: nil
  defp capped_issue(true, id, text, target), do: %{id: id, text: text, target: target}

  # По типу AC срезает сегодня ровно один тип («уклонение», `Rules.Gear`'s
  # `@ac_type_caps`), но цикл общий — заведёт ruleset второй, сводка узнает
  # его сама, без правки этого файла. Цель — уже существующий id САМОЙ этой
  # строки в разметке (`gear-ac-capped-#{row.id}`), а не общий `gear-ac-capped`:
  # у него он есть с задачи 3.39, специально под несколько срезанных типов разом.
  defp ac_type_capped_issues(gear) do
    for row <- gear.ac_types, row.capped? do
      %{
        id: "ac-#{row.id}",
        text: "AC (#{row.label}): срезано до +#{row.applied}",
        target: "gear-ac-capped-#{row.id}"
      }
    end
  end

  # Симметрично — по каждому срезанному навыку, целью в его собственную
  # строку (`gear-skill-capped-#{row.id}`, задача 3.35).
  defp skill_capped_issues(gear) do
    for row <- gear.skills, row.capped? do
      %{
        id: "skill-#{row.id}",
        text: "#{row.label}: срезано до потолка +#{gear.skill_cap}",
        target: "gear-skill-capped-#{row.id}"
      }
    end
  end

  # Предметы одной категории с причинами отказа. ⚠️ Причина берётся у ядра
  # и переводится здесь: ядро говорит таплами, русский текст рисует веб (§8).
  defp gear_worn_items(build, ruleset, category) do
    reasons =
      Map.new(Rules.worn_candidates(build, ruleset, category.id), &{&1.id, &1.reasons})

    for item <- category.items do
      Map.put(
        item,
        :reasons,
        for(reason <- Map.get(reasons, item.id, []), do: Labels.reason(reason, ruleset))
      )
    end
  end

  # Имя предмета по паре «категория/предмет» — из справочника, а не из разметки.
  defp gear_worn_name(ruleset, category_id, item_id) do
    with %{items: items} <- Worn.category(ruleset, category_id),
         %{name: name} <- Enum.find(items, &(&1.id == item_id)) do
      name || Atom.to_string(item_id)
    else
      _unknown -> Atom.to_string(item_id)
    end
  end

  # Строка выбранного оружия: имя, число и причина, если держать его нельзя.
  # `nil`, когда для ЭТОЙ руки оружие не выбрано — тогда в вёрстке стоит
  # только кнопка выбора. Одна функция на обе руки (задача 3.132): `hand` —
  # `:main` или `:off`, `Rules.Gear.weapon/2` уже умеет отдать оружие любой.
  #
  # `worn_illegal` — задача 3.133, замечание 2 («на обе стороны конфликта»):
  # если ИМЕННО это оружие в этой руке вытеснило надетое (щит — двуручным
  # в главной или вторым в этой руке), `blocks_worn_note` называет его —
  # зеркально тому, что уже говорит сам щит («Large shield в расчёт не идёт:
  # Mace занимает вторую руку»). Раньше это было сказано только на
  # ПРОИГРАВШЕЙ стороне; Dan наткнулся на пропажу щита именно в момент
  # выбора оружия, а не на щите.
  defp gear_weapon_row(ruleset, %Build{} = build, hand, worn_illegal) do
    case Gear.weapon(build.gear, hand) do
      nil ->
        nil

      id ->
        reason = weapon_hand_reason(build, ruleset, id, hand)

        %{
          id: id,
          name: Labels.weapon_name(ruleset, id),
          reason: reason,
          # Задача 3.135: перевод уже готов — `<.picked_item>` (общий
          # компонент «выбрано + снять», `BuilderComponents`) `Labels` не
          # знает и не должен (CLAUDE.md §5, перевод причины — веб-слой, но
          # не сам общий компонент). `reason` выше остаётся СЫРЫМ таплом —
          # его читает `weapon_issues/2` (сводка «Вещей», задача 3.133),
          # переводя ещё раз своей же функцией; два поля, а не одно, чтобы
          # у каждого читателя было то, что ему нужно.
          reason_text: reason && Labels.reason(reason, ruleset),
          blocks_worn_note: weapon_blocks_worn_note(worn_illegal, id, blocks_worn_cause(hand))
        }
    end
  end

  # Какой ТАПЛ причины у `Rules.Worn.illegal/2` называет ИМЕННО эту руку
  # виновником: главная рука вытесняет щит, только будучи двуручной,
  # вторая — самим фактом, что в ней вообще что-то есть (`Rules.Worn`'s
  # moduledoc, «the off hand holds a weapon»).
  defp blocks_worn_cause(:main), do: :two_handed_weapon
  defp blocks_worn_cause(:off), do: :off_hand_weapon

  # `nil`, если это оружие в этой руке ничего не вытеснило — самый частый
  # случай (щита нет вовсе, или он и так легален). Сравниваем по ПАРЕ
  # (тип причины + id этого же оружия), а не по факту «щит нелегален»:
  # щит может быть недоступен расе (`{:not_usable_by_race, …}`) — это уже
  # не про оружие, и приписывать оружию чужую причину значило бы соврать.
  defp weapon_blocks_worn_note(worn_illegal, weapon_id, cause_kind) do
    case Enum.find(worn_illegal, &(&1.cause == {cause_kind, weapon_id})) do
      nil -> nil
      row -> "#{row.name} в расчёт не идёт."
    end
  end

  # 🔴 ПРАВКА 3.132: раньше причина бралась ПЕРВЫМ элементом общего
  # `Rules.illegal_gear_weapon/2` — а с задачи 3.132 этот список обходит ОБЕ
  # руки и не помечает запись рукой (`[{weapon_id, reason}]`, до двух
  # элементов). У билда с ДВУМЯ незаконными оружиями «первый» иногда был
  # причиной ДРУГОЙ руки: главная легальна, а список из-за незаконной второй
  # не пуст, и главная строка показывала бы чужой отказ («катана недоступна»,
  # когда мешает булава).
  #
  # Спрашиваем `Rules.validate_gear_weapon/4` ПРЯМО ПО ЭТОЙ РУКЕ — ровно тот
  # вызов, ради которого он и принимает `hand`: «занята двуручным оружием»
  # у главной и «эта рука сама двуручная» у второй — разные вопросы, и
  # только `validate_gear_weapon/4` отвечает на них порознь.
  defp weapon_hand_reason(build, ruleset, id, hand) do
    case Rules.validate_gear_weapon(build, id, ruleset, hand) do
      :ok -> nil
      {:error, [reason | _]} -> reason
    end
  end

  # Сколько строк выдачи оружия отдаём разом. Не игровое число, а граница списка:
  # справочник 47 записей, из них 42 надеваемых, и все они в узкой колонке
  # читаются хуже, чем отфильтрованные поиском. Хвост назван вслух.
  @gear_weapon_limit 24

  # Пул оружия — из ЯДРА (`Rules.gear_weapon_candidates/3`), а не собранный здесь:
  # фильтр по фитам владения это игровое правило (Dan 10.08.2026), и вторая его
  # копия в вебе разошлась бы с первой. Одна функция на обе руки (задача 3.132):
  # `hand` решает, какой ассайн добавления/запроса читать и какое поле билда
  # сравнивать на «уже в руках» — ядро уже принимает `hand` третьим аргументом
  # у `gear_weapon_candidates/3`, второй копии правила заводить не пришлось.
  #
  # ⚠️ Недоступное НЕ прячется, а показывается с причиной (CLAUDE.md §6) — так
  # блок заодно учит правилу «взял фит владения, значит можешь дать оружие».
  defp gear_weapon_options(assigns, hand) do
    if weapon_add?(assigns, hand) do
      weapon_options(assigns, hand)
    else
      %{shown: [], total: 0}
    end
  end

  defp weapon_add?(assigns, :main), do: assigns.gear_weapon_add?
  defp weapon_add?(assigns, :off), do: assigns.gear_off_weapon_add?

  defp weapon_query(assigns, :main), do: assigns.gear_weapon_query
  defp weapon_query(assigns, :off), do: assigns.gear_off_weapon_query

  # `<.pick_list>`'s row-level dynamic `phx-value-*` (задача 3.135, see that
  # component's own moduledoc): both hands fire `phx-value-weapon`, only the
  # EVENT differs (`pick_gear_weapon` vs `pick_gear_off_weapon`,
  # `BuilderLive`, untouched by this task). Every key here is a literal atom
  # in this module's own source — `"phx-value-weapon": id` is sugar for
  # `:"phx-value-weapon" => id` — never one built from a runtime string, so
  # this is not `String.to_atom/1` on anything (AGENTS.md).
  defp weapon_pick_attrs(:main, id), do: ["phx-click": "pick_gear_weapon", "phx-value-weapon": id]

  defp weapon_pick_attrs(:off, id),
    do: ["phx-click": "pick_gear_off_weapon", "phx-value-weapon": id]

  defp weapon_options(assigns, hand) do
    %{ruleset: ruleset, build: %Build{gear: gear} = build} = assigns
    query = weapon_query(assigns, hand)

    rows =
      for candidate <- Rules.gear_weapon_candidates(build, ruleset, hand),
          match = weapon_match(candidate, query) do
        %{
          id: candidate.id,
          name: candidate.name || Atom.to_string(candidate.id),
          score: match.score,
          segments:
            Fuzzy.segments(candidate.name || Atom.to_string(candidate.id), match.positions),
          chosen?: Gear.weapon(gear, hand) == candidate.id,
          reason: candidate.reason,
          # Задача 3.135: `<.pick_list>` (общий компонент «кнопка → поиск →
          # стрим») печатает готовую строку, `Labels` не знает — перевод
          # остаётся здесь, тем же приёмом, что у `reason_text` в
          # `gear_weapon_row/4` выше.
          reason_text: candidate.reason && Labels.reason(candidate.reason, ruleset),
          # Оговорки — те же гэпы, что ядро повесит на билд, если это оружие
          # выбрать. Печатаются рядом с именем: «требование владения не описано»
          # игрок обязан прочитать ДО выбора, а не в панели пробелов после.
          # Переведены здесь же, а не в компоненте — по той же причине.
          caveats: Enum.map(candidate.caveats, &Labels.gap(&1, ruleset)),
          alias_note: nil,
          icon_path: nil,
          icon_glyph: nil,
          icon_epic?: false,
          pick_attrs: weapon_pick_attrs(hand, candidate.id)
        }
      end
      # Недоступное — в конец, как в секции фитов: показать надо, но первым оно
      # быть не должно. ⚠️ Этот сорт решает, КАКИЕ 24 из 41 попадут в срез
      # (хвост назван вслух — «…и ещё N»), и по имени он остаётся нарочно:
      # первая версия правки сортировала отбор по тексту причины, чтобы
      # сгруппировать пять повторяющихся предложений (жалоба Dan 16.08.2026),
      # но при 24-строчном срезе это МЕНЯЕТ, какие 24 видны без поиска —
      # прогон показал 18 других позиций, и Battleaxe/Greataxe/Dart (ровно то,
      # что было на скриншоте жалобы) из среза ВЫПАДАЮТ, потому что их причины
      # («топорами», «оружием дальнего боя») алфавитно позже остальных трёх.
      # Отбор и порядок ПОКАЗА — разные решения, см. `arrange_for_display/3`.
      |> Enum.sort_by(&{&1.reason != nil, -&1.score, &1.name})

    shown = rows |> Enum.take(@gear_weapon_limit) |> arrange_for_display(query, ruleset)

    %{shown: shown, total: length(rows)}
  end

  # Порядок ПОКАЗА уже отобранного среза — отдельный шаг от отбора выше.
  #
  # Без активного поиска строки перегруппированы так, чтобы одинаковые причины
  # стояли подряд (жалоба Dan 16.08.2026: 38 из 41 строки повторяют всего пять
  # предложений, и вразнобой по имени список читается как рваная проза —
  # «Battleaxe» и «Dagger» с одинаковой причиной оказываются в разных концах).
  # Группировка ничего не прячет и не изобретает новую таксономию: ключ — ровно
  # та строка, что и так печатается в `.feat-why`, поэтому глаз никогда не
  # увидит кластер, который расходится с подписью внутри него. И это НЕ меняет
  # состав среза (см. предупреждение выше) — только то, в каком порядке те же
  # 24 строки лежат на экране.
  #
  # ⚠️ При активном запросе порядок остаётся строго по релевантности — это
  # самая вероятная ловушка задачи, и вот почему группировка тут выключена:
  # у результатов поиска РАЗНЫЙ `score`, лучшее совпадение обязано быть первым,
  # а перегруппировка по причине сдвинула бы его вниз ради кластера с более
  # ранней по алфавиту причиной. Пустая строка — не единственный случай «поиска
  # нет»: `String.trim/1`, а не точное сравнение, чтобы запрос из одних
  # пробелов (для `Fuzzy.match/2` тоже пустой) не притворился активным поиском.
  defp arrange_for_display(shown, query, ruleset) do
    if String.trim(query) == "" do
      Enum.sort_by(shown, &{&1.reason != nil, reason_cluster_key(&1.reason, ruleset), &1.name})
    else
      shown
    end
  end

  # Пустая строка — не факт «причины нет», а нейтральный тай-брейк: у доступных
  # первый ключ кортежа (`&1.reason != nil`) уже развёл их в начало списка,
  # этот ключ на них не влияет. У недоступных он и кластерует одинаковые
  # причины подряд.
  defp reason_cluster_key(nil, _ruleset), do: ""
  defp reason_cluster_key(reason, ruleset), do: Labels.reason(reason, ruleset)

  # Нечёткий поиск по английскому имени — русских имён у оружия нет вовсе
  # (справочник строится только по Fandom, решение Dan), поэтому второй половины,
  # как у фитов, здесь нет и алиас показывать нечего.
  defp weapon_match(_candidate, ""), do: %{score: 0, positions: []}

  defp weapon_match(candidate, query), do: Fuzzy.match(query, candidate.name || "")

  # ⚠️ Задача 3.47 (жалоба Dan: секция «Вещи» набита плотно, все восемь
  # подзаголовков переносятся на две строки). Правило было ВКЛЕЕНО прямо
  # в заголовок: «Характеристики — максимум +12 на каждую» не влезает
  # в 292px. Возвращаем пару `%{title:, rule:}` вместо одной строки —
  # заголовок остаётся коротким и не переносится никогда, а правило уходит
  # тихой подписью под ним, обычным регистром (самая нечитаемая форма
  # набора — капслок с разрядкой — теперь стоит один раз на группу, а не
  # на каждой из восьми). Прятать правило за «?» нельзя — Dan просил ничего
  # не прятать, поэтому оно просто заняло свою строку, а не исчезло.
  defp cap_hint(what, nil, _each), do: %{title: what, rule: "потолок в данных не задан"}
  defp cap_hint(what, cap, each), do: %{title: what, rule: "максимум +#{cap} #{each}"}

  # Не «максимум со шмота»: в те же +20 входит прибавка от Spellcraft, и
  # обещание «максимум +20 со шмота» стало бы неправдой ровно у тех билдов,
  # ради которых потолок и существует.
  #
  # ⚠️ «Спасы», не «Сейвы» — задача 3.137, Dan 29.08.2026: «я бы "сейвы"
  # переименовал в "спасы", т.е. спасброски, на Сиале распространённое
  # сокращение». Интерфейсная подпись (CLAUDE.md §4), не игровое имя —
  # `Fort`/`Ref`/`Will` остаются английскими и этой правки не касаются.
  defp save_label(nil), do: cap_hint("Спасы", nil, nil)
  defp save_label(cap), do: %{title: "Спасы", rule: "общий потолок +#{cap} ко всем трём"}

  # Не «максимум с оружия»: в те же +20 входит расовый бонус Сиалы, и обещание
  # «максимум +20 с оружия» стало бы неправдой ровно у светлого эльфа-сагровика —
  # того самого билда, ради которого потолок и существует.
  defp weapon_label(nil), do: cap_hint("Оружие", nil, nil)

  # ⚠️ «Число», а не «числа»: поле одно с задачи 3.52. Было два — второе
  # (усиление) отличалось только уроном, которого модель не считает.
  # ⚠️ Заголовок называет ГРУППУ, а не число: в блоке не только поле, но и кнопка
  # выбора оружия. Само число подписано в ячейке игровым именем `Attack bonus`
  # (решение Dan 26.08.2026: «не совсем понятно что это именно такое»).
  # ⚠️ Здесь стояло «Число оружия» — наше выдуманное слово, которого нет ни в игре,
  # ни на вики; §4 требует показывать имя из игры, а оно у свойства предмета есть.
  defp weapon_label(cap), do: %{title: "Оружие", rule: "общий потолок атаки +#{cap}"}

  # Знак берётся из числа, а не дописывается плюсом: со штрафом жёсткий «+»
  # печатал `CON +-2`, и свёрнутый блок врал про знак ровно там, где знак —
  # единственное, что в нём есть.
  # Объявленные фиты — именами, а не счётчиком: имя отвечает и на «что у меня
  # есть», и на «почему в разборе стоит эта строка», а «×2» ни на что из этого
  # (тот же довод, по которому с карточки класса убрали плашку «от класса ×N»).
  # Английские имена, как у всех игровых сущностей (CLAUDE.md §4).
  #
  # ⚠️ Задача 3.53: `:icon`/`:epic?` читаются отдельным `Map.get`, не через
  # `Labels.feat_name/2` — тот уже занят именем и намеренно не отдаёт всю
  # запись целиком (id может не найтись в ruleset'е, `feat_name/2` тогда
  # печатает `to_string(id)` и не падает). `feat` здесь тоже может быть `nil`
  # по той же причине, и оба новых поля тогда просто `nil`/`false`.
  #
  # ⚠️ Запись объявления бывает парой `{feat_id, choice}` с задачи 3.97
  # (заход 1), и один фит может быть объявлен НЕСКОЛЬКО раз с разными
  # значениями — «два `Skill focus`, на Discipline и на Spot, законны и дают
  # обе прибавки» (решение Дана). Поэтому строка теперь — не одна на id
  # (`Enum.uniq`), а ГРУППА: одна строка на фит, внутри которой перечислены
  # все его записи. Это и держит DOM-id стабильным для фита без выбора
  # (`#gear-feat-toughness` не меняется этой задачей ни на символ — заход 1
  # уже проверил это тестом на паре `skill_focus`), и даёт место паре записей
  # одного фита, не сталкивая их id.
  #
  # ⚠️ Причина читается ПО ЗАПИСИ (`Rules.validate_gear_feat/2` с целой парой),
  # а не по агрегату `Rules.illegal_gear_feats/2`: у последнего `{feat_id,
  # reason}` схлопывает записи одного id в Map, и `{:invalid_choice, id,
  # плохое}` от ОДНОЙ записи присвоился бы и легальной соседней с ДРУГИМ
  # значением. `validate_gear_feat/2` берёт целую запись именно затем, чтобы
  # это различать (заход 1, moduledoc `GearFeats`).
  defp gear_feat_rows(ruleset, %Build{gear: %Gear{feats: feats}} = build, choice_query) do
    feats
    |> Enum.group_by(&Build.feat_id/1)
    |> Enum.map(fn {id, entries} ->
      gear_feat_group(ruleset, build, id, entries, choice_query)
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp gear_feat_group(ruleset, build, id, entries, choice_query) do
    feat = Map.get(ruleset.feats, id)
    domain = Rules.feat_choice_domain(id, ruleset)

    rows =
      for entry <- entries do
        choice = Build.feat_choice(entry)

        %{
          key: gear_feat_entry_key(id, choice),
          choice: choice,
          choice_name: choice && Labels.choice_name(ruleset, id, choice),
          reason: gear_feat_entry_reason(entry, ruleset),
          pending:
            if(is_nil(choice) and not is_nil(domain),
              do:
                gear_feat_pending(
                  ruleset,
                  build,
                  id,
                  domain,
                  Map.get(choice_query, id, "")
                )
            )
        }
      end

    reason = hd(rows).reason

    %{
      id: id,
      name: Labels.feat_name(ruleset, id),
      icon: feat && feat.icon,
      epic?: !!(feat && feat.epic?),
      domain: domain,
      # Для фита БЕЗ выбора запись всегда одна (`Gear.toggle_feat/3` держит
      # голую запись переключателем, а не счётчиком), поэтому у разметки
      # плоского случая (`row.domain == nil`) есть готовое поле верхнего
      # уровня — как было до этой задачи, байт в байт по DOM-id. `hd/1`, а не
      # защита от пустого списка: `entries` не бывает пустым — `group_by`
      # не заводит группу без единого элемента.
      reason: reason,
      # Задача 3.135: перевод для `<.picked_item>` (общий компонент
      # «выбрано + снять», `BuilderComponents`) — читает только НЕдоменные
      # строки (`row.domain == nil`), у доменных выбор остаётся своей
      # неизменённой веткой в шаблоне. `reason` выше — по-прежнему СЫРОЙ
      # тапл, вторых читателей у него сегодня нет, но заводить два разных
      # представления одного факта без причины не стоит.
      reason_text: reason && Labels.reason(reason, ruleset),
      entries: rows
    }
  end

  defp gear_feat_entry_key(id, nil), do: Atom.to_string(id)
  defp gear_feat_entry_key(id, choice), do: "#{id}-#{choice}"

  defp gear_feat_entry_reason(entry, ruleset) do
    case Rules.validate_gear_feat(entry, ruleset) do
      :ok -> nil
      {:error, [reason | _]} -> reason
    end
  end

  # Второй шаг: что примет ГОЛАЯ запись фита с вещи здесь — построено ровно
  # тем же вызовом, что решает `pick_gear_feat_choice` (CLAUDE.md §5, одно
  # чтение правила). ⚠️ Список НЕ фильтруется по базовым фитам семейства
  # (подтверждено Dan, кейс Z1: «для такого фита с вещи нам не нужно
  # требовать предыдущие фиты на focus и greater focus») — `same_choice_as`
  # ядро здесь и не спрашивает, `gear_candidates/3` зовёт `offer/5` с пустым
  # `required` всегда, так что список — это домен целиком минус уже занятое
  # ЭТИМ ЖЕ фитом (когда `distinct?`).
  defp gear_feat_pending(ruleset, build, id, domain, query) do
    {values, reasons} =
      case Rules.gear_feat_choice_candidates(build, ruleset, id) do
        {:ok, values} -> {values, []}
        {:empty, reasons} -> {[], reasons}
        {:error, reasons} -> {[], reasons}
        :no_choice -> {[], []}
      end

    rows =
      for value <- values,
          name = Labels.choice_name(ruleset, id, value),
          match = Fuzzy.match(query, name),
          not is_nil(match) do
        %{
          value: value,
          name: name,
          segments: Fuzzy.segments(name, match.positions),
          score: match.score,
          reason: gear_choice_value_reason(build.gear, id, value)
        }
      end

    {allowed, blocked} = Enum.split_with(rows, &(&1.reason == nil))

    %{
      domain: domain,
      hint: Labels.reason({:requires_choice, id, domain}, ruleset),
      allowed: Enum.sort_by(allowed, &{-&1.score, &1.name}),
      blocked: Enum.sort_by(blocked, & &1.name),
      empty_texts: for(reason <- reasons, do: Labels.reason(reason, ruleset)),
      query: query
    }
  end

  # ⚠️ Не про игровое правило, а про ФОРМУ ХРАНЕНИЯ: `gear.feats` уникален по
  # паре (`Gear.toggle_feat/3`, задача 3.97), значит повторный выбор ТОГО ЖЕ
  # значения тем же фитом не добавит вторую запись, а СНИМЕТ первую. Ядро эту
  # пару не запрещает — у `epic_energy_resistance` `distinct?: false`
  # специально разрешает то же значение снова (до потолка взятий), — так что
  # предупредить обязан веб-слой, а не молчать и не отдавать кнопку, клик по
  # которой втихую стирает уже объявленную прибавку. Оговорка переиспользует
  # готовую форму `{:choice_already_taken, …}` — по смыслу это она и есть.
  defp gear_choice_value_reason(%Gear{feats: feats}, id, value) do
    if {id, value} in feats, do: {:choice_already_taken, id, value}
  end

  # Сколько строк выдачи отдаём разом. Не игровое число, а граница списка:
  # словарь фитов — сотни записей, и все они в узкой колонке (а на телефоне —
  # в шторке) читаются не лучше, чем ни одна. Хвост назван вслух («…и ещё N»),
  # ровно как у недоступных фитов на сцене.
  @gear_feat_limit 24

  # Пул фитов с вещи, и он НЕ такой, как у слота (`Rules.GearFeats`).
  #
  # ⚠️ Фильтр — только по существованию фита в ruleset'е: слота объявление не
  # занимает, требований персонажа не проверяет и не обязано быть общим фитом.
  # `Riding Sprint` и `Smile of Death` слотом не берутся ни у кого
  # (`{:not_selectable_at_level_up, …}`) и обязаны предлагаться ЗДЕСЬ — это
  # единственный путь, которым они попадают в билд вообще. Пул, собранный
  # «что примет слот», был бы неверен именно на них.
  #
  # ⚠️ Отбитое ядром (`{:feat_disabled, …}` — `Devastating critical`) не
  # прячется, а показывается с причиной: CLAUDE.md §6, «недоступное показываем
  # с причиной» — так инструмент заодно учит правилам шарда.
  defp gear_feat_picks(%{gear_feat_add?: false}), do: %{shown: [], total: 0}

  defp gear_feat_picks(assigns) do
    %{ruleset: ruleset, build: %Build{gear: gear}, gear_feat_query: query} = assigns

    # По id, а не по записи: с задачи 3.97 запись бывает парой, а «уже
    # объявлен» — вопрос про фит. Выбор второй записи того же фита — заход 2.
    declared = MapSet.new(gear.feats, &Build.feat_id/1)

    rows =
      ruleset.feats
      |> Enum.flat_map(fn {id, feat} ->
        case gear_feat_match(ruleset, feat, query) do
          nil ->
            []

          match ->
            reason = gear_feat_reason(ruleset, id)
            alias_ru = Labels.alias_ru(ruleset, feat.name)

            [
              %{
                id: id,
                name: feat.name,
                score: match.score,
                segments: Fuzzy.segments(feat.name, match.positions),
                chosen?: MapSet.member?(declared, id),
                reason: reason,
                # Задача 3.135: перевод и `🔒`-префикс живут в `<.pick_list>`
                # (`BuilderComponents`) — компонент читает готовую строку,
                # `Feats`/`Labels` он не вызывает ни разу (CLAUDE.md §5).
                # `Feats.reason/2`, а не `Labels.reason/2` (как у оружия):
                # имя фита уже стоит на строке, короткая формулировка его
                # не повторяет — как было в шаблоне до этой задачи.
                reason_text: reason && Feats.reason(reason, ruleset),
                caveats: [],
                alias_note: if(match.via == :ru, do: "нашлось по «#{alias_ru}» — написание вики"),
                icon_path: Icons.feat_path(feat.icon),
                icon_glyph: if(feat.epic?, do: "★", else: "✦"),
                icon_epic?: feat.epic?,
                pick_attrs: ["phx-click": "toggle_gear_feat", "phx-value-feat": id]
              }
            ]
        end
      end)
      # Без запроса — по алфавиту (искать глазами в словаре можно только так),
      # с запросом — по релевантности, как в секции фитов. Отбитое ядром падает
      # в конец: показать его надо, но первым оно быть не должно.
      |> Enum.sort_by(&{&1.reason != nil, -&1.score, &1.name})

    %{shown: Enum.take(rows, @gear_feat_limit), total: length(rows)}
  end

  # Тот же приём, что в `Builder.Feats`: совпадение по английскому имени и по
  # русскому написанию вики, берём лучшее. `via` запоминает, что сработало, —
  # иначе кириллический запрос, вернувший латинские имена, выглядит случайным
  # (CLAUDE.md §4: алиас — подсказка поиска, а не название).
  defp gear_feat_match(_ruleset, _feat, ""), do: %{score: 0, positions: [], via: nil}

  defp gear_feat_match(ruleset, feat, query) do
    en = Fuzzy.match(query, feat.name)
    ru_name = Labels.alias_ru(ruleset, feat.name)
    ru = ru_name && Fuzzy.match(query, ru_name)

    cond do
      en && (is_nil(ru) or en.score >= ru.score) -> Map.put(en, :via, :en)
      ru -> %{score: ru.score, positions: [], via: :ru}
      true -> nil
    end
  end

  defp gear_feat_reason(ruleset, id) do
    case Rules.validate_gear_feat(id, ruleset) do
      :ok -> nil
      {:error, [reason | _]} -> reason
    end
  end

  # Строки навыков с вещи: вписанные числа плюс строки, которые игрок только что
  # открыл и ещё не заполнил (`gear_skill_open`).
  #
  # `capped?` и бонусы шарда берутся из `stats.skill_values` — ЯДРО уже
  # посчитало, срезал ли потолок пул бонусов, и второе вычисление того же
  # разошлось бы с первым. Своего числа веб-слой здесь не считает.
  #
  # ⚠️ Слагаемых пула ДВА (задача 3.35): расовый бонус Сиалы и её бонус за ТИП
  # оружия в руках. Здесь они складываются в одно число только для подписи про
  # срез — поимённо их печатает разбор значения навыка. Печатать одно из них
  # значило бы объяснять срез не тем источником у билда с древковым оружием.
  defp gear_skill_rows(%{ruleset: ruleset, build: %Build{gear: gear}} = assigns) do
    %{stats: stats, gear_skill_open: open} = assigns

    ids =
      for {id, bonus} <- gear.skills, bonus != 0, into: open, do: id

    for id <- ids, Map.has_key?(ruleset.skills, id) do
      value = Map.get(stats.skill_values, id)

      %{
        id: id,
        label: Labels.skill_name(ruleset, id),
        value: Gear.skill_bonus(gear, id),
        capped?: !!value && value.bonus_capped?,
        shard_bonus:
          ((value && value.shard_race_bonus) || 0) + ((value && value.weapon_type_bonus) || 0)
      }
    end
    |> Enum.sort_by(& &1.label)
  end

  # «+ добавить навык» — тот же список чипов, что в секции навыков сцены
  # (CLAUDE.md §6: показываем только то, во что билд вкладывается). Сеткой на
  # все навыки разом блок «Вещи» превратился бы в простыню.
  #
  # ⚠️ Цены и потолка ранга здесь нет и быть не должно: это не покупка ранга
  # за очки уровня, а прибавка с предмета — те числа отвечали бы на чужой
  # вопрос.
  defp gear_skill_chips(%{gear_skill_add?: false}, _shown), do: []

  defp gear_skill_chips(%{ruleset: ruleset, gear_skill_query: query}, shown) do
    already = MapSet.new(shown, & &1.id)

    ruleset.skills
    |> Enum.reject(fn {id, _skill} -> MapSet.member?(already, id) end)
    |> Enum.flat_map(fn {id, skill} ->
      case Fuzzy.match(query, skill.name) do
        nil ->
          []

        match ->
          [
            %{
              id: id,
              name: skill.name,
              segments: Fuzzy.segments(skill.name, match.positions),
              score: match.score
            }
          ]
      end
    end)
    |> Enum.sort_by(&{-&1.score, &1.name})
  end

  defp gear_summary(abilities, skills, stats, gear, worn) do
    [
      case Enum.filter(abilities, &(&1.value != 0)) do
        [] -> nil
        rows -> Enum.map_join(rows, " ", &"#{&1.label} #{BuilderLive.signed(&1.value)}")
      end,
      # Надетое — именем предмета, а не счётчиком: свёрнутая шапка отвечает на
      # «что у меня надето», и «латы» отвечают на это точнее, чем «+8».
      # ⚠️ Без фильтра по базе: одежда даёт 0 AC и всё-таки является ответом —
      # именно ею игрок говорит «я без доспеха», и на этом висят бонусы монаха.
      case Enum.filter(worn, & &1.value) do
        [] -> nil
        rows -> Enum.map_join(rows, ", ", &worn_item_name(&1))
      end,
      if(stats.ac_gear_bonus != 0, do: "AC #{BuilderLive.signed(stats.ac_gear_bonus)}"),
      if(gear.saves != 0, do: "спасы #{BuilderLive.signed(gear.saves)}"),
      # Именами и числами, как характеристики выше, а не счётчиком «навыки: 3»:
      # «дисциплина +50» — это и есть содержание прибавки, и свёрнутая шапка
      # обязана отвечать на «что у меня надето», а не только на «сколько строк».
      #
      # ⚠️ Тот же фильтр `value != 0`, что у характеристик, и по новой причине:
      # у навыков строка может существовать БЕЗ числа (игрок открыл её и ещё не
      # набрал, `gear_skill_open`). Свёрнутая шапка, печатающая «Discipline +0»,
      # обещала бы надетое там, где не надето ничего.
      case Enum.filter(skills, &(&1.value != 0)) do
        [] -> nil
        rows -> Enum.map_join(rows, " ", &"#{&1.label} #{BuilderLive.signed(&1.value)}")
      end,
      case gear.feats do
        [] -> nil
        feats -> "фиты: #{length(feats)}"
      end
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
    |> case do
      "" -> "не задано"
      text -> text
    end
  end

  # Имя предмета так, как его пишет источник; `id` — только если справочник
  # такой строки не знает (правленая руками ссылка). Гадать за источник тут
  # нечего, а печатать пустоту — значит потерять выбор игрока с экрана.
  defp worn_item_name(%{items: items, value: id}) do
    case Enum.find(items, &(&1.id == id)) do
      %{name: name} when is_binary(name) -> name
      _unknown -> Atom.to_string(id)
    end
  end

  # «Было» is a full `Rules.compute` with an empty gear set — the same way every
  # other delta in this file is computed. Two implementations of the same
  # subtraction would eventually disagree, and the player would be shown one
  # number while being given another.
  defp gear_cascade(%Build{gear: gear} = build, ruleset, stats) do
    if Gear.any?(gear) do
      naked = Rules.compute(%Build{build | gear: %Gear{}}, ruleset)

      for {key, label, was, now} <- [
            {:hp, "HP", naked.hp, stats.hp},
            {:ab, "AB", naked.attack_bonus, stats.attack_bonus},
            {:fort, "Fort", naked.fort, stats.fort},
            {:ref, "Ref", naked.ref, stats.ref},
            {:will, "Will", naked.will, stats.will}
          ],
          was != now,
          do: %{key: key, label: label, was: was, now: now, delta: diff(was, now)}
    else
      []
    end
  end

  def preview_stats(%{preview: nil}), do: nil

  def preview_stats(%{preview: {:class, id}, build: %Build{} = build} = assigns) do
    %{ruleset: ruleset, active: level} = assigns

    levels =
      if level > length(build.levels),
        do: build.levels ++ [id],
        else: List.replace_at(build.levels, level - 1, id)

    Rules.compute(%Build{build | levels: levels}, ruleset)
  end

  def preview_stats(%{preview: {:race, id}, build: %Build{} = build, ruleset: ruleset}) do
    Rules.compute(%Build{build | race: id}, ruleset)
  end

  def preview_stats(%{preview: {:increase, id}, build: %Build{} = build} = assigns) do
    %{ruleset: ruleset, active: level} = assigns
    increases = Map.put(build.ability_increases, level, id)
    Rules.compute(%Build{build | ability_increases: increases}, ruleset)
  end

  # Панель Δ говорит ровно то же, что карточка, и той же формой: наведя на
  # класс, игрок должен видеть не «фит», а какой именно слот и что класс выдаст
  # сам. Кандидат подставляется на активный уровень целиком — так же, как в
  # `preview_stats/1`, чтобы числа и слоты описывали один и тот же билд.
  def preview_chips(_assigns, _stats, nil), do: []

  def preview_chips(%{preview: {:class, id}} = assigns, stats, preview) do
    %{ruleset: ruleset, build: build, active: level} = assigns
    candidate = Build.replace_level(build, level, id)

    delta_chips(stats, preview) ++ choice_chips(ruleset, candidate, level)
  end

  def preview_chips(_assigns, stats, preview), do: delta_chips(stats, preview)

  def preview_label(%{preview: nil}, _ruleset), do: nil

  def preview_label(%{preview: {:class, id}}, ruleset), do: Labels.class_name(ruleset, id)
  def preview_label(%{preview: {:race, id}}, ruleset), do: Labels.race_ru(ruleset, id)
  def preview_label(%{preview: {:increase, id}}, _ruleset), do: "+1 " <> Labels.ability(id)

  # Плашки раскладываются СМЫСЛОВЫМИ строками, а не в порядке следования полей.
  # Раньше `Fort` оказывался рядом с `HP`, а `Will` рядом с `СП`, и карточка
  # читалась как случайный набор чисел. Четыре ряда — «основное» (то, ради чего
  # берут уровень), «сейвы», «навыки», «выбор» — и каждый со своим цветом, так
  # что глазу не нужно читать подписи, чтобы понять, про что прибавка.
  def delta_chips(before, next) do
    [
      chip("HP", diff(before.hp, next.hp), "main"),
      chip("BAB", diff(before.base_attack, next.base_attack), "main"),
      chip("AC", diff(before.ac_naked, next.ac_naked), "main"),
      if before.attacks_per_round != next.attacks_per_round do
        %{text: "атаки/р", value: to_string(next.attacks_per_round), kind: "up", row: "main"}
      end,
      chip("Fort", diff(before.fort, next.fort), "save"),
      chip("Ref", diff(before.ref, next.ref), "save"),
      chip("Will", diff(before.will, next.will), "save"),
      chip("СП", diff(before.skill_points.earned, next.skill_points.earned), "skill")
    ]
    |> Enum.reject(&is_nil/1)
  end

  # Раньше здесь стоял бюджет в семь плашек: карточка была 158px, и лишняя
  # плашка выталкивала маркеры «фит» и «+1 к стату» — то есть сами РЕШЕНИЯ
  # уровня, а не их последствия (наступали на Monk с тремя хорошими сейвами).
  # Со строками резать больше нечего: «выбор» — отдельная строка, она не может
  # выпасть из-за длинного ряда чисел, а карточка расширена до 196px.
  def card_chips(numeric, markers), do: numeric ++ markers

  # Не безликое «фит», а какой именно: общий, эпический, бонус класса. Разница
  # не косметическая: бонусный слот тратится ТОЛЬКО на фит из списка своего
  # класса. Строка отвечает на «что мне тут РЕШАТЬ».
  #
  # ⚠️ Плашки «от класса ×N» здесь больше нет — решение Дана, 02.08.2026.
  # Она называла количество, но не называла ни одного имени (имена лежали
  # в `title`, то есть на мобильном не существовали вовсе), а место занимала
  # наравне со слотом, который игрок обязан потратить. «×4» без имён не отвечает
  # ни на «что я получу», ни на «что мне решать» — а карточка отвечает именно
  # на второе. Имена выданного остались там, где они и читаются: строкой
  # «Класс даёт сам: …» в секции фитов и глифом `○` в гиде экрана просмотра.
  #
  # ⚠️ Плашки «к стату +1» здесь тоже больше нет — решение Дана, 03.08.2026.
  # Причина другая, чем у «от класса»: прибавка к характеристике даётся раз
  # в 4 уровня ПЕРСОНАЖА, любым классом, — то есть она ОДИНАКОВА у всех карточек
  # на этом уровне и не различает их вообще. Карточка отвечает на «чем этот
  # класс отличается от соседнего», а строка, стоящая одинаково у всех, на этот
  # вопрос ответить не может по построению — не «прибавка не важна», а именно
  # «она ничего не различает». В колонке прогрессии (`▲`) плашка остаётся:
  # там вопрос другой — «что я решаю на этом уровне», и характеристику игрок
  # обязан выбрать сам, форма §6 CLAUDE.md её не отменяет.
  #
  # Если модель когда-нибудь разберёт КЛАССОВУЮ прибавку к характеристике
  # (у Red Dragon Disciple она есть в игре, но сейчас спрятана за неразобранным
  # фитом `dragon_abilities`) — показывать такую прибавку на карточке будет
  # снова осмысленно: она как раз отличает один класс от другого.
  #
  # `candidate` — гипотетический билд с рассматриваемым классом на этом уровне.
  def choice_chips(ruleset, candidate, level) do
    for %{label: label, count: count} <-
          Feats.slot_labels(ruleset, FeatSlots.at(candidate, ruleset, level)) do
      # ⚠️ Вид плашки — `slot`, а НЕ `feat`, и это не вкусовщина (найдено
      # 14.08.2026 по снимку Dan с телефона). Плашка рендерится как
      # `class="d feat"`, а в `app.css` есть самостоятельное правило `.feat` —
      # это кнопка-строка списка фитов, с `display: grid`, `width: 100%`
      # и `padding: 7px 11px`. Специфичность у `.d` и `.feat` одинаковая (0-1-0),
      # `.feat` стоит ниже по файлу (1246 против 916) и потому выигрывала:
      # плашка выбора надевала костюм строки списка и растягивалась во всю
      # ширину карточки. `.d.feat` (0-2-0) перебивала только цвет, границу и фон,
      # поэтому баг выглядел «дизайном», а не поломкой.
      #
      # Имя `slot` вернее и по смыслу: плашка называет СЛОТ («общий фит»,
      # «бонус Fighter»), а не фит. Соседние виды (`up`, `down`) самостоятельных
      # правил в CSS не имеют, так что столкновение было ровно одно.
      %{
        text: label,
        value: if(count > 1, do: "×#{count}"),
        kind: "slot",
        row: "choice"
      }
    end
  end

  defp chip(_label, nil, _row), do: nil
  defp chip(_label, 0, _row), do: nil

  defp chip(label, delta, row) do
    %{
      text: label,
      value: BuilderLive.signed(delta),
      kind: if(delta > 0, do: "up", else: "down"),
      row: row
    }
  end

  def diff(nil, _), do: nil
  def diff(_, nil), do: nil
  def diff(before, next), do: next - before
end
