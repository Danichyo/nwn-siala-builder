defmodule BuildCalculator.Data.Loader.Reading do
  @moduledoc """
  Примитивы чтения `priv/rules/*.json`, общие словари и справочники значений выбора.

  Сюда сведено то, что нужно **всем** остальным частям загрузчика: прочитать файл,
  привести строку к атому, спуститься по вложенным ключам, — плюс четыре словаря,
  которые читает больше чем один модуль (характеристики, трёхбуквенные ключи
  характеристик, базовый AC и ключи требований). Словари отданы функциями, а не
  атрибутами, ровно по одной причине: атрибут виден только своему модулю, а вторая
  копия словаря разошлась бы с первой на первой же правке.

  Здесь же справочники значений выбора (`choice_domains/3`): откуда фит с выбором
  берёт свои значения — из файла-словаря или из самого ruleset'а — решает одна
  функция, а не каждый читатель по-своему.
  """

  @abilities [:str, :dex, :con, :int, :wis, :cha]

  @ability_keys %{
    "STR" => :str,
    "DEX" => :dex,
    "CON" => :con,
    "INT" => :int,
    "WIS" => :wis,
    "CHA" => :cha
  }

  # Base armour class before any modifier. Not stated in any file under priv/rules/
  # and the Fandom "Armor class" page is not in the cache.
  # TODO: verify — ask data-miner to put this on record.
  @base_ac 10

  # Requirement keys the rules core knows how to read. Anything else is carried
  # into `gaps` rather than silently dropped.
  #
  # ⚠ Read off `Rules.Prereqs` and no longer written out here. The two lists
  # existed side by side and drifted: `any_of` — the one key that expresses "dwarf
  # **or** half-orc", "bard **or** sorcerer" — was added to the interpreter and
  # never to this list, so a class requirement written as a disjunction was
  # dropped before anything could check it. That is what let Pale Master be taken
  # at character level 1.
  #
  # `qualifiers` is on the list without being checkable, and deliberately: it is
  # not a requirement but a refinement of one ("in a melee weapon"), and the
  # useful part of it is the **text**. Dropping the key would leave only its name
  # in `requirements_unsupported`, so the interface could say that something was
  # unchecked but never what. `Rules.compute/2` reports it against the classes a
  # build actually took (`{:not_modelled, {:class_qualifier, …}}`), which is the
  # same contract feats get.
  @requirement_keys Enum.map(BuildCalculator.Rules.Prereqs.keys(), &Atom.to_string/1)

  @doc "Шесть характеристик, в порядке листа персонажа."
  def abilities, do: @abilities

  @doc "Трёхбуквенный ключ характеристики, каким его пишут наши собственные JSON."
  def ability_keys, do: @ability_keys

  @doc "Базовый AC до любых модификаторов."
  def base_ac, do: @base_ac

  @doc "Ключи требований, которые умеет прочитать ядро правил."
  def requirement_keys, do: @requirement_keys

  # ---------------------------------------------------------------- reading --

  def read_json(root, rel) do
    path = Path.join(root, rel)

    case File.read(path) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, data} ->
            data

          {:error, reason} ->
            raise "#{rel} is not valid JSON: #{Exception.message(reason)}"
        end

      {:error, :enoent} ->
        :missing

      {:error, reason} ->
        raise "cannot read #{path}: #{:file.format_error(reason)}"
    end
  end

  # ------------------------------------------------------- choice dictionaries --

  # Files under `vanilla/` that are rules dictionaries in their own right. What
  # is left over is a candidate choice domain.
  #
  # ⚠ `class_choices.json` is here and `domains.json` is deliberately NOT.
  # `class_choices.json`'s entries are keyed by CLASS id (`cleric`), so if
  # `domain_files/1` picked it up as a values dictionary it would offer
  # `cleric` as a pickable *value* of some domain — a silent, wrong dictionary
  # indistinguishable by eye from a real one. `domains.json` is exactly the
  # opposite: a plain `{id, name}` list, the same shape `spell_schools.json`
  # and `creature_types.json` already are, and it is meant to be found this
  # way — `choice_domains/3` resolves `:domain` to it precisely because
  # nothing excludes it. See `class_choices.json`'s own `_note`.
  @rules_files ~w(classes.json feats.json races.json skills.json spells.json epic.json
                  feat_skill_bonuses.json feat_hp_bonuses.json ac_bonuses.json
                  feat_ability_bonuses.json feat_save_bonuses.json feat_attack_bonuses.json
                  feat_spell_resistance.json
                  spellcasting.json
                  class_requirements.json feat_requirements.json class_choices.json
                  class_choice_no_selection.json
                  grant_substitutions.json feat_effect_receivers.json)

  # Every other `vanilla/*.json`, keyed by basename. Reading them all and
  # deciding later costs one directory listing and means a dictionary the shard
  # adds is picked up without this module being edited.
  def domain_files(root) do
    root
    |> Path.join("vanilla/*.json")
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) in @rules_files))
    |> Map.new(fn path ->
      {path |> Path.basename(".json") |> atom(),
       read_json(root, "vanilla/#{Path.basename(path)}")}
    end)
  end

  @doc """
  Where each choice domain's dictionary comes from — a table of *sources*.

  A feat that is taken with something names the domain it draws from
  (`repeatable.choice`), and the domain is resolved by that key alone:

    * a file under `priv/rules/vanilla/` whose basename is the domain or its
      plural — `creature_type` → `creature_types.json`;
    * a dictionary the ruleset already carries under the plural of the domain —
      `skill` → `ruleset.skills`, and nothing has to be written down twice;
    * nothing, and that is a legitimate answer. Weapons are not modelled at all
      and will not be before the armoury (CLAUDE.md §3), so `weapon` resolves to
      no dictionary — the feat stays takeable and the build says the choice went
      unchecked, rather than the calculator pretending either way.

  No race, school, skill or weapon is named anywhere in this module; only the key
  the dictionary is looked up by.

  ⚠ `extra` widens the set of domain names beyond what feats name — a class's
  one-time choice (`class_choices.json`, `Rules.ClassChoices`) names a domain
  the exact same way a repeatable feat does, and it is resolved through this
  same table on purpose: a Cleric's `domain` and a future Wizard's
  `spell_school` (task 3.10) are one mechanism, and `spell_school` is *already*
  in this map because `spell_focus` names it — building a second, parallel
  dictionary for the class side would be the "две почти одинаковые машинерии"
  AGENT_QUEUE.md §3.14 warns against.
  """
  @spec choice_domains(map(), map(), [atom()] | MapSet.t(atom())) :: %{atom() => map()}
  def choice_domains(domain_files, dictionaries, extra \\ []) do
    from_feats =
      for {_id, feat} <- Map.get(dictionaries, :feats, %{}),
          repeatable = Map.get(feat, :repeatable),
          is_map(repeatable),
          domain = Map.get(repeatable, :choice),
          not is_nil(domain),
          into: MapSet.new(),
          do: domain

    names = MapSet.union(from_feats, MapSet.new(extra))

    Map.new(names, fn domain -> {domain, resolve_domain(domain, domain_files, dictionaries)} end)
  end

  # `creature_type` → `creature_types`, `class` → `classes`. Both endings are
  # tried, and the bare name last, so a dictionary may be named either way
  # without this module knowing which domains exist.
  defp plurals(domain), do: [:"#{domain}s", :"#{domain}es", domain]

  defp resolve_domain(domain, domain_files, dictionaries) do
    names = plurals(domain)
    file = Enum.find_value(names, &Map.get(domain_files, &1))

    # An **empty** dictionary is not a dictionary: `skills` is `%{}` while
    # `skills.json` is still being written, and resolving to it would refuse
    # every value in the game rather than admit the list is not there yet.
    carried = Enum.find(names, &(map_size(Map.get(dictionaries, &1, %{})) > 0))

    cond do
      entries = domain_entries(file) ->
        entries

      carried ->
        %{
          values: MapSet.new(Map.keys(Map.fetch!(dictionaries, carried))),
          flags: %{},
          source: {:ruleset, carried}
        }

      true ->
        # Known to the data, unknown to us. Deliberately the *same* answer as a
        # domain the core has no idea about: it cannot tell the two apart, and
        # pretending otherwise would be a distinction the code cannot honour.
        %{values: nil, flags: %{}, source: nil}
    end
  end

  # A dictionary file is a list of entries with an `"id"`, either at the top
  # level or under a single wrapping key — `creature_types.json` wraps its list
  # in `"types"`. The wrapper's name is not prescribed, because prescribing it
  # would be one more thing for two files to agree on.
  #
  # Boolean fields beside the id are **per-feat gates**: `favored_enemy: false`
  # on `ooze` says that type is not selectable *for that feat*. They are indexed
  # by name, and a feat picks up the gate that carries its own id — so a file
  # that grows a second gate serves a second feat with no code change, and
  # `ooze` is refused by the data rather than by a name in a clause.
  defp domain_entries(nil), do: nil
  defp domain_entries(:missing), do: nil

  defp domain_entries(%{} = wrapped) do
    case Enum.filter(Map.values(wrapped), &is_list/1) do
      [list] -> domain_entries(list)
      _other -> nil
    end
  end

  defp domain_entries(list) when is_list(list) do
    entries = for entry <- list, id = entry_id(entry), do: {id, entry}

    if entries == [] do
      nil
    else
      %{
        values: MapSet.new(entries, &elem(&1, 0)),
        flags: entry_flags(entries),
        names: entry_names(entries),
        source: :file
      }
    end
  end

  defp domain_entries(_other), do: nil

  defp entry_id(id) when is_binary(id), do: atom(id)
  defp entry_id(%{"id" => id}) when is_binary(id), do: atom(id)
  defp entry_id(_other), do: nil

  # Имя из данных, а не собранное из id. `monstrous_humanoid` — это НАША
  # нормализация, а не то, как сущность называется на вики; разворачивать её
  # обратно в текст значило бы дорисовывать регистр, которого в источнике может
  # не быть (CLAUDE.md §3). Нет имени в файле — веб-слой покажет id как есть.
  defp entry_names(entries) do
    for {id, entry} <- entries,
        is_map(entry),
        name = entry["name"],
        is_binary(name),
        into: %{},
        do: {id, name}
  end

  @doc """
  Значения, которых у фитов ЭТОГО ruleset'а нет вовсе, — вычеркнутые из ворот домена.

  Ваниль уже умеет сказать «варианта фита с таким значением не бывает», и говорит
  это **воротами домена**: `vanilla/weapons.json` ставит посоху и лэнсу
  `selectable: false`, а страница `Weapon focus` объясняет словами — «There is no
  version of this feat for the magic staff or lance». Шард говорит то же самое
  про ещё одно значение (`overrides.json` → `weapons.no_feat_variant`), и раз
  утверждение одного вида — механизм обязан быть один и тот же.

      "no_feat_variant": {"domain": "weapon", "values": ["creature_weapon"], …}

  ⚠ Ворота **домен-широкие**, то есть значение исчезает у всей семьи фитов сразу,
  а не у названного. Так устроен сам справочник (`_chosen_by.corroborated_by`:
  семь страниц оружейных фитов перечисляют один и тот же набор), и поимённое
  исключение утверждало бы различие, которого не называет ни один источник.

  ⚠ Отказ приходит **той же формой**, что у посоха с лэнсом —
  `{:invalid_choice, фит, значение}`, — и новой заводить нельзя: две формы на одно
  утверждение разъедутся, а игроку они сказали бы одно и то же.

  ⚠ Умолчание ванильное и возвращается само: запись исчезнет — значение снова
  попадёт в предложение, потому что закрывать его будет некому. Тихим no-op запись
  при этом стать не может — `close_variant!/4` роняет сборку, если закрывать
  оказалось нечего.

  ⚠ Домен запись называет **сама**, поэтому механизм здесь ничего не знает ни
  про оружие, ни про навыки. А вот ПУТЬ к записи ведёт в сиальскую секцию
  `weapons`, и это не небрежность: `gear` лежит в `@vanilla_sections`
  загрузчика, то есть виден ОБОИМ ruleset'ам, и запись оттуда начала бы
  утверждать про ваниль то, чего никто не проверял. Ровно на этом 16.08.2026
  из ванильного списка оружия пропал лэнс.

  `feats` нужен одному сторожу — `verify_no_named_gate!/4`: именные ворота
  (`flags[feat_id]`) бьют домен-широкие, и надо знать, какое из булевых полей
  словаря вообще может оказаться воротами фита.
  """
  @spec close_feat_variants!(%{atom() => map()}, map(), map()) :: %{atom() => map()}
  def close_feat_variants!(domains, feats, ov) do
    case dig(ov, ["weapons", "no_feat_variant"]) do
      %{"domain" => domain, "values" => [_ | _] = values} = block when is_binary(domain) ->
        verify_variant_block!(block)
        Enum.reduce(values, domains, &close_variant!(&2, feats, atom(domain), atom(&1)))

      nil ->
        domains

      other ->
        raise """
        overrides.json: weapons.no_feat_variant must name a `domain` and a non-empty list of \
        `values`; it reads #{inspect(other)}. A block this loader cannot read would quietly \
        leave the variant on offer.
        """
    end
  end

  # Запись УБИРАЕТ у игрока законную на вид строку, то есть двигает ответ в сторону
  # отказа. Догадка в эту сторону — ложная нелегальность, обойти которую изнутри
  # инструмента нельзя, поэтому применяется только выверенная и только с дословной
  # цитатой наблюдения. Тот же обмен, что у `bonuses[].prerequisite` в
  # `feat_save_bonuses.json` (CLAUDE.md §6).
  defp verify_variant_block!(block) do
    quoted? = is_binary(block["quote"]) and block["quote"] != ""

    unless block["status"] == "verified" and quoted? do
      raise """
      overrides.json: weapons.no_feat_variant closes a variant off, which is a refusal the \
      player cannot work around from inside the tool. It applies only with `status: \
      "verified"` and a verbatim `quote`; it carries #{inspect(block["status"])} and \
      #{inspect(block["quote"])}.
      """
    end
  end

  defp close_variant!(domains, feats, domain, value) do
    gate = BuildCalculator.Rules.FeatChoices.domain_gate()

    case Map.get(domains, domain) do
      %{values: %MapSet{} = values, flags: %{^gate => %MapSet{} = allowed} = flags} ->
        unless MapSet.member?(values, value) do
          raise """
          overrides.json: weapons.no_feat_variant names #{inspect(value)} in domain \
          #{inspect(domain)}, whose dictionary does not carry it. The shard cannot be missing \
          a variant vanilla never had.
          """
        end

        unless MapSet.member?(allowed, value) do
          raise """
          overrides.json: weapons.no_feat_variant closes #{inspect(value)} in domain \
          #{inspect(domain)}, which the `#{gate}` gate does not open in the first place. \
          Nothing was closed, so the record reads as an applied one: either the dictionary \
          moved under it, or the variant was already gone.
          """
        end

        verify_no_named_gate!(flags, feats, domain, value)
        put_in(domains, [domain, :flags, gate], MapSet.delete(allowed, value))

      %{} ->
        raise """
        overrides.json: weapons.no_feat_variant closes a variant in domain #{inspect(domain)}, \
        which states no `#{gate}` gate at all. Every value of such a domain is on offer, and \
        a record with no gate to narrow would change nothing.
        """

      nil ->
        raise """
        overrides.json: weapons.no_feat_variant names domain #{inspect(domain)}, which no \
        dictionary answers. Known: #{inspect(Enum.sort(Map.keys(domains)))}.
        """
    end
  end

  # Именные ворота (`flags[feat_id]`) БЬЮТ домен-широкие — так `Weapon of choice`
  # получает свой более узкий список. Значит именной пропуск поверх закрытого
  # значения вернул бы его одному фиту молча, и такого состояния быть не должно:
  # запись говорит «варианта нет», а не «нет у всех, кроме одного».
  defp verify_no_named_gate!(flags, feats, domain, value) do
    named =
      for {name, %MapSet{} = set} <- flags,
          Map.has_key?(feats, name),
          MapSet.member?(set, value),
          do: name

    unless named == [] do
      raise """
      overrides.json: weapons.no_feat_variant closes #{inspect(value)} in domain \
      #{inspect(domain)}, but #{inspect(Enum.sort(named))} still name it in their own gate, \
      and a named gate beats the domain-wide one. The variant would go on being offered to \
      those feats alone.
      """
    end
  end

  defp entry_flags(entries) do
    names =
      for {_id, entry} <- entries,
          is_map(entry),
          {key, value} <- entry,
          is_boolean(value),
          uniq: true,
          do: key

    Map.new(names, fn name ->
      {atom(name), MapSet.new(for({id, entry} <- entries, entry[name] == true, do: id))}
    end)
  end

  # ---------------------------------------------------------------- helpers --

  def dig(map, keys) do
    Enum.reduce_while(keys, map, fn key, acc ->
      case acc do
        %{} -> if(Map.has_key?(acc, key), do: {:cont, Map.fetch!(acc, key)}, else: {:halt, nil})
        _ -> {:halt, nil}
      end
    end)
  end

  # A boolean override that only counts once a human has checked it. Same
  # contract as `stat_caps/1`: an entry that is still `unclear` leaves the rule
  # at `default` rather than half-applying a fact nobody verified, and a layer
  # that never mentions the key changes nothing.
  def verified_flag(ov, keys, default) do
    entry = dig(ov, keys)

    if is_map(entry) and entry["status"] == "verified" and is_boolean(entry["value"]) do
      entry["value"]
    else
      default
    end
  end

  def atom(nil), do: nil
  def atom(value) when is_atom(value), do: value
  def atom(value) when is_binary(value), do: String.to_atom(value)

  def atom_or_nil(nil), do: nil
  def atom_or_nil(value), do: atom(value)

  def slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/\(.*?\)/, "")
    |> String.trim()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
    |> String.to_atom()
  end

  # --------------------------------------------------------- wiki prose --

  # A small, fixed set — measured across the corpus that needs it (task 3.87,
  # 299 feat descriptions), not a general HTML-entity decoder. An entity not
  # in this map is left as the raw `&...;` string rather than guessed at.
  @html_entities %{"&mdash;" => "—", "&ndash;" => "–", "&nbsp;" => " "}

  # Struck-through patch history — editors record a change by striking the old
  # value rather than deleting it (`<s>will 1/2</s>`, `<del>3d6</del> ''6d6''`),
  # so a `<s>`/`<del>`/`<strike>` span is the wiki's history, never its current
  # answer, and has to be cut *before* anything else reads the string — the
  # same rule `Wiki.SialaSpellPage.strip_struck/1` applies at parse time, kept
  # here as its own copy rather than a call to it: this module builds a
  # ruleset out of the JSON `mix wiki.parse` already committed, and never
  # reaches into the mix-task modules that read live wikitext.
  @struck ~r/<\s*(s|del|strike)\s*>.*?<\s*\/\s*\1\s*>/isu
  @wiki_link ~r/\[\[(?:[^\[\]|]*\|)?([^\[\]|]*)\]\]/u
  @line_break ~r/<\s*br\s*\/?\s*>/iu
  @any_tag ~r/<[^>]*>/u

  @doc """
  Wiki prose down to plain text — feat "Specifics" (task 3.87) and the shard's
  own change quotes, the two places raw wikitext is kept on purpose (same
  reason as `prereq_raw`: stripping it in `mix wiki.parse` would make the diff
  against the source unreadable, CLAUDE.md §3) and shown to a player as
  running text rather than read as a value.

  `nil` in, `nil` out — a page that states nothing has nothing to show, not an
  empty popover. Six passes, struck-through history resolved first so nothing
  downstream reads an obsolete value as current:

    1. the handful of named entities the corpus actually uses (`&mdash;`, …);
    2. `<br />` down to a line break, not a space — a `white-space: pre-line`
       reader (the feat info popover) keeps a labelled second paragraph or a
       short list readable instead of running it into the sentence before it;
    3. struck-through spans cut whole, replaced with a space — the old value
       is gone, not "also true" (`favored_enemy`: "they do <strike>not</strike>
       improve for the Harper" reads as *do* improve once the strike is cut);
    4. `[[target|shown]]`/`[[target]]` down to display text;
    5. remaining `<...>` tags dropped (never their content — `<code>x3_dm_tool
       ##</code>` keeps its payload) and `'''`/`''` wiki emphasis removed;
    6. per line: internal whitespace collapsed, whitespace a removed struck
       span leaves before punctuation folded away ("dragon.  ." → "dragon."),
       repeated punctuation collapsed, empty lines (an entirely-struck one)
       dropped.
  """
  @spec strip_wiki_prose(String.t() | nil) :: String.t() | nil
  def strip_wiki_prose(nil), do: nil

  def strip_wiki_prose(raw) when is_binary(raw) do
    cleaned =
      raw
      |> decode_html_entities()
      |> String.replace(@line_break, "\n")
      |> String.replace(@struck, " ")
      |> String.replace(@wiki_link, "\\1")
      |> String.replace(@any_tag, " ")
      |> String.replace("'''", "")
      |> String.replace("''", "")
      |> String.split("\n")
      |> Enum.map(&tidy_wiki_prose_line/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
      |> String.trim()

    if cleaned == "", do: nil, else: cleaned
  end

  defp decode_html_entities(text) do
    Enum.reduce(@html_entities, text, fn {entity, replacement}, acc ->
      String.replace(acc, entity, replacement)
    end)
  end

  defp tidy_wiki_prose_line(line) do
    line
    |> String.replace(~r/[ \t]+/u, " ")
    |> String.replace(~r/[ \t]+([.,;:!?])/u, "\\1")
    |> String.replace(~r/([.,;:!?])\1+/u, "\\1")
    |> String.trim()
  end
end
