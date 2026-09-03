defmodule BuildCalculator.Data.Loader.ClassFeatFacts do
  @moduledoc """
  То, что говорят о классах **страницы фитов**: сдвиги выдач, запреты по классу,
  сверка имён в требованиях и снятие выдач у фита, отключённого шардом.

  Приходит оно с другой стороны, чем сами классы (`Loader.Classes`), а ложится
  на ту же карту классов, поэтому и живёт рядом с ней.
  """

  alias BuildCalculator.Data.Loader.Classes
  alias BuildCalculator.Rules.Attack

  import BuildCalculator.Data.Loader.Reading

  # ------------------------------- what the feat pages say about classes --

  # ⚠ Живёт здесь, а не рядом с читателями прибавок, и это правка задачи 3.46
  # (заход 2), а не изначальное место. Разрезание загрузчика по разделам
  # (заход 1) утащило эти шесть функций в `Bonuses` за маркером «what adds to
  # the attack roll», под которым они стояли, — механический перенос не имеет
  # права судить о содержимом. К прибавкам они не относятся ничем: правят
  # карту классов и снимают выдачи отключённого фита.

  # What the feat pages say about classes, laid onto the class map. All four
  # shapes are idempotent, so a fact the class layer already applied lands on the
  # same value rather than doubling it.
  #
  # Two of them touch **every** class rather than a named one, and they are not
  # the same statement:
  #
  #   * `:forbid_for` names the whole set of classes that refuse the feat, so the
  #     classes absent from that set are as much part of the statement as the ones
  #     in it — it **replaces**, and a shard page saying "nobody forbids this"
  #     therefore lifts a vanilla ban (see `apply_feat_change/4`'s
  #     `unavailable_for_classes`);
  #   * `:forbid_for_all_but` names the classes that **may**, off a feat page's
  #     own «only when leveling as …» sentence, and bans the rest. It **unions**,
  #     because it says nothing at all about the classes it allows: the class page
  #     of an allowed class remains free to state its own ban, and the two would
  #     then be a real contradiction rather than an override — hence the raise
  #     rather than a silent delete.
  def apply_feat_class_facts(classes, facts) do
    Enum.reduce(facts, classes, fn
      {:move, class_id, from, to, feat_id}, acc ->
        update_class(acc, class_id, &Classes.move_grant(&1, from, to, feat_id))

      {:auto, class_id, feat_id}, acc ->
        update_class(acc, class_id, &Classes.grant_feat(&1, 1, feat_id))

      {:forbid_for, feat_id, class_ids}, acc ->
        Map.new(acc, fn {id, class} ->
          bans =
            if MapSet.member?(class_ids, id),
              do: MapSet.put(class.unavailable_feats, feat_id),
              else: MapSet.delete(class.unavailable_feats, feat_id)

          {id, %{class | unavailable_feats: bans}}
        end)

      {:forbid_for_all_but, feat_id, allowed}, acc ->
        verify_allowed_classes!(acc, feat_id, allowed)

        Map.new(acc, fn {id, class} ->
          bans =
            if MapSet.member?(allowed, id),
              do: class.unavailable_feats,
              else: MapSet.put(class.unavailable_feats, feat_id)

          {id, %{class | unavailable_feats: bans}}
        end)
    end)
  end

  # `only_on_class_levels_for_skill` — the same family's fourth shape, keyed by the
  # value the feat is taken with («*Epic skill focus* in [[perform]] can be taken
  # only when gaining a [[bard]] level»). Read by `Rules.Prereqs`, so unlike
  # `only_on_class_levels` there is no complement to compute and nothing here to
  # apply — only the names to check, and **both** sides fail silently without this:
  #
  #   * a misspelt **skill** key makes the restriction match nothing, so the
  #     illegal pick goes back to being legal — the very hole the entry closes;
  #   * a misspelt **class** makes the allowed list short, so a legal pick becomes
  #     illegal on a level that should take it.
  #
  # Neither shows up in any number, which is why this raises instead of reporting.
  def verify_choice_class_restrictions!(feats, skills, classes) do
    for {id, feat} <- feats,
        by_skill = Map.get(feat.prereqs || %{}, "only_on_class_levels_for_skill"),
        is_map(by_skill),
        {skill, allowed} <- by_skill do
      unless map_size(skills) == 0 or Map.has_key?(skills, atom(skill)) do
        raise "feat_requirements.json: #{id} restricts #{skill}, which is not a skill"
      end

      unless is_list(allowed) and allowed != [] do
        raise """
        feat_requirements.json: #{id} states only_on_class_levels_for_skill for #{skill} as \
        #{inspect(allowed)}, which is not a non-empty list of class ids. An empty list would \
        say "no level of any class may take it with this value" — nothing in the corpus says \
        that, and it would read as a parsing accident rather than a rule.
        """
      end

      case Enum.reject(allowed, &Map.has_key?(classes, atom(&1))) do
        [] ->
          :ok

        unknown ->
          raise "feat_requirements.json: #{id} allows #{inspect(unknown)} for #{skill}, which are not classes"
      end
    end

    verify_bonus_slot_exceptions!(feats, skills)
    verify_qualifying_class_names!(feats, classes)

    :ok
  end

  # `feat_choices` — требование не к фиту, а к ЗНАЧЕНИЮ, с которым он взят
  # («Weapon Focus: короткий лук, длинный лук, малый или большой арбалет» у
  # Тайного лучника на Сиале). Читает `Rules.Prereqs`; здесь, как и у соседа
  # выше, применять нечего — только сверить имена, потому что каждая ошибка
  # в них молчит и молчит **в сторону разрешения**:
  #
  #   * имя фита с опечаткой — записанных значений не найдётся никогда,
  #     а «значение не записано» правило трактует как «не проверяем»
  #     (`Rules.Prereqs`, раздел про незаписанный выбор). То есть требование
  #     исчезает целиком, не оставив следа ни в одном числе;
  #   * фит без домена выбора — сравнивать записанное будет не с чем, и тот же
  #     исход;
  #   * значение, которого нет в домене, — просто никогда не совпадёт, то есть
  #     сузит требование молча и не так, как написано в источнике.
  #
  # ⚠ Проверяется принадлежность домену, а НЕ то, что значение выбираемо
  # (`selectable`): «какие значения игрок может выбрать» — правило самого фита
  # и его слота, и повторять его здесь значило бы держать две копии одного
  # ограничения. Требование же говорит только о том, какое значение годится.
  def verify_class_feat_choices!(classes, feats, domains) do
    for {id, class} <- classes,
        by_feat = Map.get(class.requirements || %{}, :feat_choices),
        is_map(by_feat),
        {feat, allowed} <- by_feat do
      feat_id = atom(feat)
      definition = Map.get(feats, feat_id)

      unless map_size(feats) == 0 or definition do
        raise "#{id} requires a choice of #{feat}, which is not a feat"
      end

      domain = choice_domain_of(definition)

      unless is_nil(definition) or domain do
        raise """
        #{id} requires a choice of #{feat}, but that feat takes no choice at all. \
        A requirement about a value only means something where a value is recorded.
        """
      end

      unless is_list(allowed) and allowed != [] do
        raise """
        #{id} states feat_choices for #{feat} as #{inspect(allowed)}, which is not a \
        non-empty list of values. An empty list would say "no value of this feat will do", \
        and no source says that — it reads as an unfinished entry, and an unfinished entry \
        here drops the requirement silently.
        """
      end

      # ⚠ Пустой справочник домена — это НЕ «значений нет», а «словарь ещё не
      # подключён» (тот же случай, что `map_size(feats) == 0` выше). Падать на
      # нём значило бы ронять сборку у того, кто временно убрал файл словаря.
      case unknown_values(allowed, Map.get(domains, domain)) do
        [] -> :ok
        unknown -> raise "#{id} requires #{feat} in #{inspect(unknown)}, not in domain #{domain}"
      end
    end

    :ok
  end

  @doc """
  Тот же сторож для `feat_choice_properties` — требования к СВОЙСТВУ значения
  («weapon focus **in a melee weapon**», задача 3.99).

  ⚠ Проверяются три вещи, и каждая ошибка молчит **в сторону разрешения**,
  ровно как у `feat_choices` выше: имя фита, наличие у него домена выбора
  и то, что свойство ядро умеет прочитать с записи справочника
  (`Rules.Attack.weapon_property_field/1`). Свойство, которого ядро не знает,
  даёт `{:missing_data, …}` на каждом билде — это громко, но громко **у
  игрока**, а не у того, кто ошибся в записи.
  """
  @spec verify_class_feat_choice_properties!(map(), map()) :: :ok
  def verify_class_feat_choice_properties!(classes, feats) do
    for {id, class} <- classes,
        by_feat = Map.get(class.requirements || %{}, :feat_choice_properties),
        is_map(by_feat),
        {feat, properties} <- by_feat do
      feat_id = atom(feat)
      definition = Map.get(feats, feat_id)

      unless map_size(feats) == 0 or definition do
        raise "#{id} requires a property of #{feat}'s choice, which is not a feat"
      end

      unless is_nil(definition) or choice_domain_of(definition) do
        raise """
        #{id} requires a property of #{feat}'s choice, but that feat takes no choice         at all. A requirement about a value only means something where a value is recorded.
        """
      end

      unless is_map(properties) and map_size(properties) > 0 do
        raise """
        #{id} states feat_choice_properties for #{feat} as #{inspect(properties)}, which is         not a non-empty map. An empty map would say "any value will do", and a requirement         that requires nothing drops silently.
        """
      end

      for {property, _value} <- properties,
          is_nil(Attack.weapon_property_field(atom(property))) do
        raise "#{id} requires #{feat} with property #{inspect(property)}, which the core " <>
                "cannot read off a weapon record (Rules.Attack.weapon_property_field/1). " <>
                "A property nobody can answer turns the requirement into " <>
                "{:missing_data, …} on every build."
      end
    end

    :ok
  end

  @doc """
  Тот же сторож для `feat_choice_excludes` — значений, которые требование
  НЕ ЗАСЧИТЫВАЕТ («this focus does not satisfy the "weapon focus in a melee
  *weapon*" requirement», `fandom:Unarmed strike`, задача 3.107).

  ⚠ Проверяется то же, что у `feat_choices`, и каждая ошибка молчит в **ту же**
  сторону — в сторону разрешения: опечатка в имени фита или значение вне домена
  не совпадут ни с чем, исключение не сработает, и класс откроется тому, кому
  в игре он закрыт. Ровно та ложная легальность, ради снятия которой ключ
  и заведён.
  """
  @spec verify_class_feat_choice_excludes!(map(), map(), map()) :: :ok
  def verify_class_feat_choice_excludes!(classes, feats, domains) do
    for {id, class} <- classes,
        by_feat = Map.get(class.requirements || %{}, :feat_choice_excludes),
        is_map(by_feat),
        {feat, excluded} <- by_feat do
      feat_id = atom(feat)
      definition = Map.get(feats, feat_id)

      unless map_size(feats) == 0 or definition do
        raise "#{id} excludes a choice of #{feat}, which is not a feat"
      end

      domain = choice_domain_of(definition)

      unless is_nil(definition) or domain do
        raise """
        #{id} excludes a choice of #{feat}, but that feat takes no choice at all. \
        A requirement about a value only means something where a value is recorded.
        """
      end

      unless is_list(excluded) and excluded != [] do
        raise """
        #{id} states feat_choice_excludes for #{feat} as #{inspect(excluded)}, which is not a \
        non-empty list of values. An empty list says "nothing is excluded", and that is the \
        absence of the key rather than a key — an unfinished entry here drops the rule \
        silently and the class opens to everybody again.
        """
      end

      case unknown_values(excluded, Map.get(domains, domain)) do
        [] -> :ok
        unknown -> raise "#{id} excludes #{feat} in #{inspect(unknown)}, not in domain #{domain}"
      end
    end

    :ok
  end

  defp choice_domain_of(%{repeatable: %{choice: domain}}), do: domain
  defp choice_domain_of(_no_choice), do: nil

  # ⚠ `Enum.empty?/1`, а не `map_size/1`: `values` — это `MapSet`, то есть
  # структура, и `map_size` считал бы её ПОЛЯ (всегда 2), а не значения. Ветка
  # «словарь пуст» не срабатывала бы никогда.
  defp unknown_values(allowed, %{values: values}) do
    if Enum.empty?(values), do: [], else: Enum.reject(allowed, &(atom(&1) in values))
  end

  defp unknown_values(_allowed, _no_dictionary), do: []

  # The sixth family's names and numbers, checked against the finished class
  # dictionary and for the same reason as the fourth's: every way of getting the
  # record wrong is silent. A misspelt class simply never matches the level's
  # class, so the feat is refused on every level of every class — a false
  # illegality with no visible cause — and a threshold that is not a number turns
  # the whole requirement into `{:missing_data, …}` for everybody.
  defp verify_qualifying_class_names!(feats, classes) do
    for {id, feat} <- feats,
        thresholds = Map.get(feat.prereqs || %{}, "qualifying_class_levels"),
        is_map(thresholds),
        {class, required} <- thresholds do
      unless map_size(classes) == 0 or Map.has_key?(classes, atom(class)) do
        raise "feat_requirements.json: #{id} qualifies on #{class}, which is not a class"
      end

      unless is_integer(required) and required > 0 do
        raise """
        feat_requirements.json: #{id} states #{class} qualifies at #{inspect(required)}, \
        which is not a level count. The number is what "epic" means for that class \
        (21 for a base class, 11 for a prestige one, 15 for the pale master this rule names) \
        and it has to come off the page, never from a default.
        """
      end
    end

    :ok
  end

  # The fifth family's names, checked against the same finished dictionaries and
  # for the same reason: every way of getting this record wrong is silent.
  #
  #   * a misspelt **value** matches no pick, so the refused pair goes back to
  #     being legal — the hole the record closes;
  #   * a class whose bonus slot never takes the feat at all makes the exception
  #     dead weight. It is not merely useless: `bonus_for` is what the exception
  #     is carved out of, so a name outside it means either a typo here or a
  #     `bonus_for` the re-parse has since dropped — and in the second case the
  #     entry's whole reading needs rereading, not patching.
  #
  # ⚠ Checked against the **finished** feats, after the shard layer, because that
  # layer may widen `bonus_for` (it unions, never subtracts). A class the shard
  # added to the bonus list is therefore a legal target for an exception, and one
  # only Fandom named still is.
  defp verify_bonus_slot_exceptions!(feats, skills) do
    for {id, feat} <- feats,
        {class, choice} <- Map.get(feat, :bonus_for_except) || MapSet.new() do
      unless map_size(skills) == 0 or Map.has_key?(skills, choice) do
        raise "feat_requirements.json: #{id} excludes #{choice}, which is not a skill"
      end

      unless MapSet.member?(feat.bonus_for, class) do
        raise """
        feat_requirements.json: #{id} keeps #{choice} out of #{class}'s bonus slot, but \
        #{class} is not on that feat's bonus list at all (`bonus_for` is \
        #{inspect(Enum.sort(feat.bonus_for))}), so the exception excludes nothing. Either the \
        class id is misspelt, or the bonus list moved under the entry — reread the page.
        """
      end
    end

    :ok
  end

  # Both halves of "the allowed list is trustworthy", and each catches a different
  # way of getting it wrong: a misspelt class id would silently *ban* the class it
  # meant to allow (the complement is computed, so a name that matches nothing
  # widens the ban), and a class that already refuses the feat off its own page
  # means the two sides of the wiki disagree — which is a finding, not something
  # to resolve by whichever file the loader happens to read second.
  defp verify_allowed_classes!(classes, feat_id, allowed) do
    case Enum.reject(allowed, &Map.has_key?(classes, &1)) do
      [] ->
        :ok

      unknown ->
        raise "feat_requirements.json: #{feat_id} allows #{inspect(unknown)}, which are not classes"
    end

    banned =
      for id <- allowed,
          class = Map.get(classes, id),
          MapSet.member?(class.unavailable_feats, feat_id),
          do: id

    if banned != [] do
      raise """
      feat_requirements.json: #{feat_id} says it may be taken on a level of #{inspect(banned)}, \
      but #{inspect(banned)} already refuses it («These general feats cannot be selected when \
      taking a level of …», read off the class page). The feat page and the class page disagree \
      — reread both, do not pick one.
      """
    end
  end

  def update_class(classes, id, fun) do
    case Map.fetch(classes, id) do
      {:ok, class} -> Map.put(classes, id, fun.(class))
      :error -> classes
    end
  end

  # A feat the shard switched off is handed over by nobody, whatever the route it
  # arrived by — and the two routes are the class progression table
  # (`granted_feats`) and a racial trait (`race.bonus_feats`).
  #
  # ⚠ Gated **here** rather than in the JSON, and that is the point: those files
  # are Fandom's snapshot, where the grants are true, and `mix wiki.parse` owns
  # them. The shard's own statement is one `{"what": "disabled"}` record per
  # feat, and everything that follows from it — no `○ класс даёт сам` glyph, no
  # membership in `Build.feats_owned/3`, no bonus keyed by `{:feat, id}` or
  # `{:race_feat, id}` — follows in one place instead of twenty-six edits
  # scattered across two layers.
  #
  # Vanilla is untouched by construction: nothing there is disabled, so the
  # early return below is the whole of it.
  def drop_disabled_grants(classes, feats) do
    disabled = disabled_ids(feats)

    if MapSet.size(disabled) == 0 do
      classes
    else
      Map.new(classes, fn {id, class} -> {id, drop_grants(class, disabled)} end)
    end
  end

  defp drop_grants(class, disabled) do
    granted =
      class.granted_feats
      |> Map.new(fn {level, ids} -> {level, Enum.reject(ids, &MapSet.member?(disabled, &1))} end)
      |> Map.reject(fn {_level, ids} -> ids == [] end)

    ranks =
      class.granted_feat_ranks
      |> Map.new(fn {level, by_feat} ->
        {level, Map.reject(by_feat, fn {id, _rank} -> MapSet.member?(disabled, id) end)}
      end)
      |> Map.reject(fn {_level, by_feat} -> by_feat == %{} end)

    %{class | granted_feats: granted, granted_feat_ranks: ranks}
  end

  # ⚠ Единственная функция этого модуля, правящая РАСЫ, и стоит она здесь не по
  # недосмотру: правило одно («отключённый фит не выдаёт никто»), маршрутов у него
  # два, и `disabled_ids/1` у обоих общий. Разведи их по `Classes` и `Races` —
  # и объяснение над `drop_disabled_grants/2`, которое называет оба маршрута
  # в одном предложении, окажется верным только для половины.
  def drop_disabled_race_feats(races, feats) do
    disabled = disabled_ids(feats)

    if MapSet.size(disabled) == 0 do
      races
    else
      Map.new(races, fn {id, race} ->
        {id, %{race | bonus_feats: Enum.reject(race.bonus_feats, &MapSet.member?(disabled, &1))}}
      end)
    end
  end

  defp disabled_ids(feats),
    do: for({id, %{disabled?: true}} <- feats, into: MapSet.new(), do: id)
end
