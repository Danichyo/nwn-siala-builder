defmodule BuildCalculatorWeb.Builder.LevelPicks do
  @moduledoc """
  What the current level offers to pick: known-spell rows and the feat lists.

  Split out of `BuildCalculatorWeb.BuilderLive` (задача 3.46, заход 4, marker
  "spells"): both streams answer the same question — "what can this level's
  slots be spent on" — one for `spells_known` classes, the other for feats.
  Neither reads anything the other does not; the marker just happened to bundle
  the two.
  """

  alias BuildCalculator.Ids
  alias BuildCalculator.Rules.{Build, FeatSlots, Spells}
  alias BuildCalculatorWeb.Builder.{Feats, Fuzzy, Labels}

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4]

  # ---- spells ----

  # Known spells are the same slot model as feats: "new spells this level" is the
  # difference between two rows of the class's `spells_known` table, so a
  # Sorcerer's seventh level offers one circle 1, one circle 2 and one circle 3
  # (CLAUDE.md §6). The list only ever offers circles that still have a free
  # slot, and never a spell the character already knows — there is no relearning
  # in the constructor, by decision.
  #
  # 🔴 **Заблокированный круг остаётся ВИДИМЫМ, и это не наш вкус, а замер**
  # (задача 3.125, Dan 31.08.2026 на барде 5 с харизмой 11): «видит 2 круг,
  # но не может выбрать на нем заклинания, он как бы заблокирован, это на этапе
  # лвл апа так. При этом в самой игре если нажать B — spellbook, то там второй
  # круг не отображается вообще». Два места, два разных ответа игры — и панель
  # итогов (аналог книги) круг прячет, а этот список показывает его с причиной,
  # ровно как §6 велит поступать со всем недоступным.
  def assign_spells(socket) do
    %{ruleset: ruleset, build: build, active: level} = socket.assigns
    class = Build.class_at(build, level)
    definition = class && Map.get(ruleset.classes, class)

    if definition && map_size(definition.spells_known) > 0 do
      slots = Spells.slots_at(build, ruleset, level)
      chosen = Map.get(build.spells, level, %{})
      class_level = Build.class_level_at(build, level)
      catalogue = Spells.list_for(ruleset, class)
      blocked = blocked_circles(build, ruleset, class, slots, level)
      open = for slot <- slots, not Map.has_key?(chosen, slot.id), do: slot.circle

      rows = spell_rows(socket.assigns, catalogue, MapSet.new(open), chosen, level, blocked)

      socket
      |> assign(:spell_class, class)
      |> assign(:spell_class_level, class_level)
      |> assign(:spell_circles, Map.new(catalogue, &{&1.id, &1.circle}))
      |> assign(:spell_slots, spell_slot_chips(ruleset, slots, chosen, blocked))
      |> assign(:spell_note, spell_note(ruleset, definition, class_level, slots))
      |> assign(:spell_count, length(rows))
      |> stream(:spells, rows, reset: true)
    else
      stream(socket, :spells, [], reset: true)
    end
  end

  @doc """
  Круги этого уровня, на которые персонажу не хватает характеристики каста.

  `%{круг => «нужен CHA 12»}`. Пусто у всех, кому хватает, и пусто там, где
  правило не прочитано, — ядро в обоих случаях отвечает одинаково, и подпись
  берётся из той же `Labels.reason/2`, которой подписан отказ фита: причина
  одна и та же (`{:requires_ability, …}`), значит и фраза обязана быть одна.
  """
  @spec blocked_circles(Build.t(), map(), atom(), [map()], pos_integer()) ::
          %{non_neg_integer() => String.t()}
  def blocked_circles(build, ruleset, class, slots, level) do
    circles = slots |> Enum.map(& &1.circle) |> Enum.uniq()

    build
    |> Spells.unmet_circles(ruleset, class, circles, level)
    |> Map.new(fn {circle, reason} -> {circle, Labels.reason(reason, ruleset)} end)
  end

  # ⚠️ Задача 3.54: `:icon` — сырое имя файла выбранного заклинания, а не
  # готовый путь (`Icons.spell_path/1` вызывается в шаблоне, как и у остальных
  # трёх мест с иконкой). `nil` у пустого слота и у 9 заклинаний без арта не
  # различаются — оба дают пустой бокс, запасного глифа заклинанию нарочно
  # не полагается (круг уже назван цифрой бейджа, CLAUDE.md §6).
  defp spell_slot_chips(ruleset, slots, chosen, blocked) do
    for slot <- slots do
      spell_id = Map.get(chosen, slot.id)

      %{
        id: slot.id,
        key: Ids.spell_slot_key(slot.id),
        dom_id: Ids.spell_slot_dom_id(slot.id),
        circle: slot.circle,
        spell: spell_id,
        name: Labels.spell_name(ruleset, spell_id),
        icon: Labels.spell_icon(ruleset, spell_id),
        # ⚠️ У ЗАПОЛНЕННОГО слота причина не печатается: заклинание в нём уже
        # стоит (пришло по ссылке или характеристику опустили после выбора),
        # и «нужен CHA 12» рядом с выбранным именем читалось бы как «этого
        # заклинания у тебя нет». Пик мы не отбираем — это была бы ложная
        # нелегальность, — а место отказа ровно одно: клик по списку.
        blocked: spell_id == nil && Map.get(blocked, slot.circle)
      }
    end
  end

  defp spell_rows(assigns, catalogue, open_circles, chosen, level, blocked) do
    %{ruleset: ruleset, build: build, spell_query: query} = assigns
    known = Spells.known(build, level - 1)
    here = chosen |> Map.values() |> MapSet.new()

    catalogue
    |> Enum.filter(&MapSet.member?(open_circles, &1.circle))
    |> Enum.flat_map(fn entry ->
      alias_ru = Labels.alias_ru(ruleset, entry.spell.name)

      case spell_score(query, entry.spell.name, alias_ru) do
        nil ->
          []

        match ->
          [
            %{
              id: entry.id,
              circle: entry.circle,
              name: entry.spell.name,
              # ⚠️ Имя школы из справочника, а не поле заклинания: `spell.school`
              # до задачи 3.86 печаталось сырьём, и `Clarity` выводил на экран
              # `<del>abjuration</del> <i>necromancy</i>` буквально. Теперь поле
              # — атом, а имя приходит оттуда же, откуда имя школы на чипе
              # специализации (`ruleset.choice_domains.spell_school`).
              school: Labels.spell_school_name(ruleset, entry.spell.school),
              icon: entry.spell.icon,
              alias_ru: alias_ru,
              via: match.via,
              segments: Fuzzy.segments(entry.spell.name, match.positions),
              score: match.score,
              known?: MapSet.member?(known, entry.id) or MapSet.member?(here, entry.id),
              # Причина на КАЖДОЙ строке, а не одна на список: круги этого
              # уровня бывают разной доступности сразу (колдун 8 с харизмой 11
              # выбирает 1-й круг и не выбирает 4-й), и подпись у строки — то
              # единственное место, где игрок видит, какого числа не хватает.
              blocked: Map.get(blocked, entry.circle)
            }
          ]
      end
    end)
    |> Enum.sort_by(&{-&1.score, &1.circle, &1.name})
  end

  # Bilingual like the feat list (CLAUDE.md §4): the English name is the name, the
  # Russian spelling from the wiki redirects is only a search aid. Highlighting is
  # dropped on a Russian hit — the positions belong to the alias, not to the name
  # being shown, and painting them onto the English word would be nonsense.
  defp spell_score("", _name, _alias), do: %{score: 0, positions: [], via: nil}

  defp spell_score(query, name, alias_ru) do
    en = Fuzzy.match(query, name)
    ru = alias_ru && Fuzzy.match(query, alias_ru)

    cond do
      en && (is_nil(ru) or en.score >= ru.score) -> Map.put(en, :via, :en)
      ru -> %{score: ru.score, positions: [], via: :ru}
      true -> nil
    end
  end

  # ⚠ The wall nobody warns about: both spell tables stop at class level 20, so
  # Sorcerer 41 knows exactly what Sorcerer 20 knows. This is the mistake on
  # which a player loses half a build, so it is said out loud rather than shown
  # as an empty list (CLAUDE.md §6).
  defp spell_note(_ruleset, definition, class_level, []) do
    max = definition.spell_table_max_class_level

    if is_integer(max) and class_level > max do
      "#{definition.name} #{class_level}: таблица кончается на #{max}-м уровне класса — " <>
        "дальше не растут ни известные заклинания, ни слоты в день. Уровни класса после " <>
        "#{max}-го дают только HP, спасы и фиты."
    else
      "#{definition.name} #{class_level}: на этом уровне класс новых заклинаний не даёт."
    end
  end

  defp spell_note(_ruleset, _definition, _class_level, _slots), do: nil

  def assign_feat_streams(socket) do
    %{ruleset: ruleset, build: build, active: level} = socket.assigns

    lists =
      Feats.lists(ruleset, build, level,
        query: socket.assigns.feat_query,
        type: socket.assigns.feat_type,
        slot: socket.assigns.feat_slot
      )

    # `chosen_slot` travels as a bare id, and an id cannot tell an epic class
    # bonus from an ordinary one — that lives on the slot the level actually
    # granted. Looking the real slot up beats rebuilding its shape from the id:
    # a rebuilt shape silently lost `epic?` and labelled level 24's bonus slot
    # exactly like level 2's.
    by_id = Map.new(FeatSlots.at(build, ruleset, level), &{&1.id, &1})

    socket
    |> assign(:available_count, length(lists.available))
    |> assign(:blocked_total, lists.blocked_total)
    |> assign(:searching?, lists.searching?)
    |> stream(:feats_available, Enum.map(lists.available, &decorate(&1, ruleset, by_id)),
      reset: true
    )
    |> stream(:feats_blocked, Enum.map(lists.blocked, &decorate(&1, ruleset, by_id)), reset: true)
  end

  defp decorate(entry, ruleset, by_id) do
    entry
    |> Map.put(:segments, Fuzzy.segments(entry.feat.name, entry.positions))
    |> Map.put(:reason_texts, Enum.map(entry.reasons, &Feats.reason(&1, ruleset)))
    |> Map.put(:target_label, entry.target_slot && Labels.slot_label(ruleset, entry.target_slot))
    # ⚠️ Два разных предложения про один и тот же факт, а не одно на оба
    # случая: до взятия это совет («не трать слот»), после — констатация
    # («слот можно освободить»). Тот же текст постфактум звучал бы неверно —
    # слот уже потрачен, «не трать» ему больше нечего посоветовать
    # (HANDOFF §A.3, решение Дана 02.08.2026). `entry.taken?` — тот же тест,
    # что красит строку в «✓ взят» ниже по шаблону.
    |> Map.put(
      :free_later_text,
      if(entry.taken?,
        do: Feats.free_later_taken_text(ruleset, entry.free_later),
        else: Feats.free_later_text(ruleset, entry.free_later)
      )
    )
    # ⚠️ Отдельной строкой, а не внутри `reason_texts`: это оговорка к
    # РАЗРЕШЁННОМУ выбору (`Rules.feat_pick_caveats/3`) — фит уже есть с вещи,
    # слот ничего не добавит, но потратить его можно и иногда нужно (предмет
    # снимается, слот нет). Попади она в причины — строка уехала бы
    # в «Недоступные», то есть вернулась бы ложная нелегальность, которую эта
    # задача и убрала.
    #
    # Склейкой, а не списком строк: оговорка сегодня ровно одна, но перечисление
    # через `:for` потребовало бы индекса в DOM-id, а склейка ничего не теряет,
    # если форм станет две (`Enum.map_join` на пустом списке даёт `""`, поэтому
    # `presence/1` — иначе шаблон печатал бы пустую строку как «есть текст»).
    |> Map.put(
      :caveat_text,
      entry.caveats |> Enum.map_join(" · ", &Feats.caveat_text(&1, ruleset)) |> presence()
    )
    |> Map.put(
      :chosen_label,
      entry.chosen_slot && Labels.slot_label(ruleset, slot_shape(by_id, entry.chosen_slot))
    )
  end

  defp presence(""), do: nil
  defp presence(text), do: text

  defp slot_shape(by_id, id) do
    case Map.fetch(by_id, id) do
      {:ok, slot} -> slot
      :error -> fallback_shape(id)
    end
  end

  defp fallback_shape({:class_bonus, class}), do: %{kind: :class_bonus, class: class}
  defp fallback_shape({:class_bonus, class, _index}), do: %{kind: :class_bonus, class: class}
  defp fallback_shape(:racial), do: %{kind: :racial, class: nil}
  defp fallback_shape(id), do: %{kind: id, class: nil}
end
