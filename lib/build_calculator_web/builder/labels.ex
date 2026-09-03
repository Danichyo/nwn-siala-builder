defmodule BuildCalculatorWeb.Builder.Labels do
  @moduledoc """
  Wording for everything the core says in tuples, translated through gettext
  (task 3.83) with a Russian `msgstr` for every `msgid` — the interface
  default stays `ru` (config.exs), so nothing here reads as English today.

  The split is deliberate (CLAUDE.md §8): the rules core answers
  `{:requires_bab, 7}` and never a sentence, so it stays language-free and
  testable, and this is the single place that turns those tuples into
  «нужен BAB +7». Game entities keep their English names (§4) — `Fighter`,
  `Power Attack`, `HP`, `Fort` — because that is what the game, the wiki
  redirects and the community build format all call them, and they never go
  through `gettext/1,2`: a translated class name would be exactly the
  fan-made translation §4 forbids.

  Names come out of the data exactly as the wiki spells them ("Dwarven
  defender", not "Dwarven Defender"): Fandom does not title-case, and
  redrawing the case would be invention just like a number would be.

  Anything this module has not seen falls back to `inspect/1` rather than being
  swallowed. A gap nobody worded yet must still be visible.

  ⚠️ **Concatenated fragments do not translate** (task 3.83): a suffix built by
  one clause and appended to a sentence built by another travels its own word
  order, its own agreement, its own comma — all language-specific. Every place
  that used to glue a base sentence to a conditional tail (`save_prereq_exceptions/1`,
  `forced_floor_text/2`'s `race` fragment) is now two whole `gettext/2` calls,
  one per branch, so a translator sees a full sentence rather than a puzzle
  piece. Race display (`race_ru/2`, `race_en/2`) is untouched on purpose — the
  shard's own name for a race is not an interface label (§4), and its fate
  belongs to the upcoming vanilla/Siala split, not to this pass.
  """

  use Gettext, backend: BuildCalculatorWeb.Gettext

  alias BuildCalculator.Data.Loader.Reading
  alias BuildCalculator.Ids
  alias BuildCalculator.Rules.Abilities
  alias BuildCalculator.Rules.Bonuses
  alias BuildCalculator.Rules.Build
  alias BuildCalculator.Rules.Caps
  alias BuildCalculator.Rules.SaveBonuses
  alias BuildCalculatorWeb.Builder.PointBuy

  @abilities %{
    str: "STR",
    dex: "DEX",
    con: "CON",
    int: "INT",
    wis: "WIS",
    cha: "CHA"
  }

  @doc "Ability shorthand as players and the export format write it."
  @spec ability(atom()) :: String.t()
  def ability(id), do: Map.get(@abilities, id, to_string(id))

  # STR/DEX/CON/WIS/INT/CHA — the order the character sheet, the community
  # posting format and our own export (`Export.abilities/2`, task 3.145) all
  # show abilities in, and NOT `Rules.Abilities.keys/0`'s STR/DEX/CON/INT/WIS/CHA
  # (task 3.156). That order is real and stays exactly where it is — it is the
  # book's own, and `Abilities.breakdown/2`'s internal map iterates it however
  # it likes because a map has no order to leak. This one is a display order,
  # so it belongs to the web layer: two live players read the wrong number off
  # the point-buy row before this existed (CLAUDE.md's task 3.156), one column
  # having drifted from the other. Every place a player sees a *list* of
  # abilities — the point-buy table, the "+1 at level 4" cards, the race
  # card's modifiers, the gear panel, the totals panel's breakdown, the
  # exported text — reads this single list rather than each keeping (or
  # copying) its own, so they cannot drift from each other again.
  @ability_order [:str, :dex, :con, :wis, :int, :cha]

  @doc "Ability display order — the game's, not the book's (see `@ability_order` above)."
  @spec ability_order() :: [atom()]
  def ability_order, do: @ability_order

  @doc """
  Why the point-buy budget is what it is, or `nil` when there is nothing to say.

  A caster's key ability cannot end below 11 and the game buys the points for
  it, so a human caster has 27 to spend and a half-orc one 25 (Dan, тестовый
  сервер, 03.08.2026). **A budget that quietly shrank reads as a broken
  calculator**, which is the same reason a ceiling that clipped a number has to
  name itself (CLAUDE.md §6) — so the missing points say who took them.

  Four states, and they are four on purpose:

    * the floor applies — say whose it is, what it costs and what is left;
    * no first class yet — say the budget is **not final**, because it is not:
      printing «30» flat here is the lie by default this note exists against;
    * a first class that does not cast — nothing to explain, the whole budget is
      free;
    * a ruleset that carries no such rule (`vanilla` has no overrides file) —
      nothing is claimed here at all, and `{:missing_data,
      :caster_minimum_ability}` says so in the gaps panel instead.
  """
  @spec point_buy_floor(map(), Build.t()) :: String.t() | nil
  def point_buy_floor(ruleset, %Build{} = build) do
    case {Abilities.creation_minimum(ruleset), PointBuy.forced(ruleset, build),
          Build.class_at(build, 1)} do
      {nil, _forced, _class} ->
        nil

      {_rule, %{} = forced, _class} ->
        forced_floor_text(ruleset, forced)

      {%{value: minimum}, nil, nil} ->
        gettext(
          "First-level class is not chosen yet, so the budget is not final: " <>
            "a caster's key ability cannot end below %{minimum} after everything is applied, " <>
            "and some points will be spent on it by force.",
          minimum: minimum
        )

      {_rule, nil, _non_caster} ->
        nil
    end
  end

  # «Списано: 3 из 30» вместо «3 очка»: число тут переменное, а согласование
  # («3 очка» / «5 очков») стоило бы своего склонятора ради одной строки.
  #
  # ⚠️ Две ветки, а не одна строка с приклеенным хвостом (task 3.83): `race`
  # раньше собирался отдельно и приклеивался `<>` — то есть был ровно тем
  # склеенным фрагментом, который module doc запрещает. Обе ветки — целые
  # предложения со своим набором `%{...}`, а не общая рыба с необязательным
  # куском.
  defp forced_floor_text(ruleset, forced) do
    class = class_name(ruleset, forced.class)
    ability = ability(forced.ability)
    budget = PointBuy.budget(ruleset)

    if forced.racial == 0 do
      gettext(
        "%{class} casts from %{ability} — the final score cannot end below %{minimum}. " <>
          "Forced spend: %{cost} of %{budget}, %{free} left free.",
        class: class,
        ability: ability,
        minimum: forced.minimum,
        cost: forced.cost,
        budget: budget,
        free: forced.free
      )
    else
      gettext(
        "%{class} casts from %{ability} — the final score cannot end below %{minimum}, " <>
          "and the race gives %{racial} — %{base} is bought. " <>
          "Forced spend: %{cost} of %{budget}, %{free} left free.",
        class: class,
        ability: ability,
        minimum: forced.minimum,
        racial: signed(forced.racial),
        base: forced.base,
        cost: forced.cost,
        budget: budget,
        free: forced.free
      )
    end
  end

  defp signed(value) when value >= 0, do: "+#{value}"
  defp signed(value), do: "−#{abs(value)}"

  @doc "English name of an alignment — the format the community writes."
  @spec alignment_name(atom() | nil) :: String.t() | nil
  defdelegate alignment_name(id), to: Ids

  @doc "Class name straight out of the ruleset."
  @spec class_name(map(), atom() | nil) :: String.t()
  def class_name(_ruleset, nil), do: "—"

  def class_name(ruleset, id) do
    case ruleset.classes do
      %{^id => %{name: name}} when is_binary(name) -> name
      _ -> to_string(id)
    end
  end

  @doc """
  Как называется скорость роста BAB у класса: «полный», «средний», «низкий».

  Одно слово на одно значение `bab_progression` из ruleset'а (задача 3.16) —
  подпись интерфейса, поэтому русская и поэтому живёт в коде, а не в
  `priv/rules/` (та же причина, что у `domain_name/1`: у русской подписи нет
  источника, нечего проставлять в `source`, а всякий незнакомый файл в
  `priv/rules/vanilla/` загрузчик считает справочником значений).

  ⚠️ **Словом, а не коэффициентом — и это решение, а не вкус.** Идея Dan
  (04.08.2026) звучала как `0.75 × cleric × 15`, и она бьёт в цель: коэффициент
  объясняет, почему клирик отстаёт. Но напечатать его здесь значило бы сделать
  две запрещённые вещи сразу. Во-первых, `3/4` — это **формула**, а не поле
  данных: в данных лежит строка `"medium"`, а во что она превращается,
  знает ровно одно место — `Data.Loader.Classes.bab_from_label/2`, где формула сверена
  со всеми 330 ванильными клетками таблиц; второй экземпляр той же формулы в
  вебе разошёлся бы с первым молча. Во-вторых, `0.75 × 15 = 11.25`, а вклад
  клирика — **11**: рядом с числом из таблицы множитель печатал бы сумму,
  которая не равна своим слагаемым, то есть ровно то, чего разбор делать
  не должен.

  Почему «полный», а не «высокий», при том что метка — `high`: «полный БАБ» —
  то, как это называют русскоязычные игроки, и вики Сиалы описывает `high`
  ровно этим смыслом («Боевой прирост БАБ: +1 за уровень», страницы Монаха,
  ПДК и Тайного лучника). «Средний» и «низкий» переводятся буквально —
  своих слов у шарда для них нет, и выдумывать их не за чем.

  ⚠️ Незнакомая метка возвращается **как есть**, а не `nil` и не «неизвестно»:
  значение приходит из данных, и новое может появиться с очередным
  `mix wiki.parse`. Сырое `"three_quarters"` в скобках — плохой, но заметный
  ответ; сторожем стоит тест, который проходит по всем классам обоих
  ruleset'ов и требует слова для каждого (`labels_test.exs`).
  """
  @spec bab_progression(String.t() | nil) :: String.t() | nil
  def bab_progression(nil), do: nil
  def bab_progression("high"), do: gettext("full")
  def bab_progression("medium"), do: gettext("medium BAB")
  def bab_progression("low"), do: gettext("low BAB")
  def bab_progression(label) when is_binary(label), do: label

  @doc """
  Как называется скорость роста одного сейва у класса: «высокий», «низкий».

  То же, что `bab_progression/1`, но метки другие, и их **две, а не три**: сейв
  либо основной для класса, либо нет (`save_progressions` в ruleset'е — 35
  значений `good` и 34 `poor` на 23 класса, третьего в корпусе нет).

  ⚠️ **Слова взяты из источника, а не переведены с ключа.** В данных лежат
  `good`/`poor` — это подписи инфобокса класса («Primary saving throw(s)»), — но
  страница, которая правило описывает, называет строки своей таблицы **«High
  saves»** и **«Low saves»** (`fandom:Base save`: «primary saving throws (high
  saves) go up +2 at class level 1 and +1 at each even class level, while other
  saving throws (low saves) go up +1 every third class level»). Отсюда «высокий»
  и «низкий»: это описание роста, то есть ровно то, что подпись объясняет.

  «Хороший»/«плохой» отвергнуты сознательно, хотя ключ читается именно так: это
  оценка класса, а не описание прогрессии, и рядом с числом из таблицы она
  ничего не добавляет. Заодно «низкий» здесь совпадает с «низким» у BAB — одно
  слово на одну и ту же мысль в двух соседних разборах одной панели.

  ⚠️ Коэффициента нет по той же причине, что у BAB, и здесь она даже строже:
  рост сейва **не линеен** (+2 на первом уровне класса, потом +1 через уровень),
  поэтому множителя не существует вовсе — `Fighter 10` даёт 7 к Fort, а не 5,
  и именно из-за этой «+2 на первом» мультикласс даёт сейвы ВЫШЕ, чем один
  класс на 20 уровней (`fandom:Base save`, раздел Multiclassing benefits).

  ⚠️ Незнакомая метка возвращается как есть — тот же контракт и тот же сторож
  в `labels_test.exs`, что у `bab_progression/1`.
  """
  @spec save_progression(String.t() | nil) :: String.t() | nil
  def save_progression(nil), do: nil
  def save_progression("good"), do: gettext("high save")
  def save_progression("poor"), do: gettext("low save")
  def save_progression(label) when is_binary(label), do: label

  @doc """
  Community shorthand for the level ladder: `DD`, `WM`, `CoT`.

  Derived mechanically from the name — initials of the significant words — so
  no per-class table has to be invented and a new class in the data gets a
  sensible label for free. Single-word names are left alone; the ladder
  ellipsises them.
  """
  @spec class_short(map(), atom() | nil) :: String.t()
  def class_short(ruleset, id) do
    name = class_name(ruleset, id)

    case String.split(name, ~r/\s+/, trim: true) do
      [_single] ->
        name

      words ->
        Enum.map_join(words, fn word ->
          initial = String.first(word)
          if String.length(word) > 2, do: String.upcase(initial), else: String.downcase(initial)
        end)
    end
  end

  @doc """
  How a race is shown: the shard's name first, the engine's name underneath.

  The shard rebuilt the races rather than translating them, so its name is the
  real one for a Siala player (CLAUDE.md §4) — and mind the collision, `Гном` is
  Dwarf while `Карлик` is Gnome.
  """
  @spec race_ru(map(), atom() | nil) :: String.t()
  def race_ru(_ruleset, nil), do: "не выбрана"

  def race_ru(ruleset, id) do
    case ruleset.races do
      %{^id => %{ru: ru}} when is_binary(ru) -> ru
      %{^id => %{name: name}} when is_binary(name) -> name
      _ -> to_string(id)
    end
  end

  @doc "The engine's name for a race — the subtitle under `race_ru/2`."
  @spec race_en(map(), atom() | nil) :: String.t()
  def race_en(_ruleset, nil), do: ""

  def race_en(ruleset, id) do
    case ruleset.races do
      %{^id => %{name: name}} when is_binary(name) -> name
      _ -> to_string(id)
    end
  end

  @doc "Feat name straight out of the ruleset."
  @spec feat_name(map(), atom() | nil) :: String.t()
  def feat_name(_ruleset, nil), do: "—"

  def feat_name(ruleset, id) do
    case ruleset.feats do
      %{^id => %{name: name}} when is_binary(name) -> name
      _ -> to_string(id)
    end
  end

  @doc """
  Raw Fandom icon filename for a feat, or `nil` — same contract as `feat_name/2`,
  and the same two reasons `nil` shows up (AGENT_QUEUE.md 3.50/3.54): 23 feats
  carry no `icon` at all, and an unknown id has nothing to look up. Not a
  servable path — call site still runs it through
  `BuildCalculatorWeb.Builder.Icons.feat_path/1`, exactly as `entry.feat.icon`
  does everywhere a feat is already the whole ruleset record.
  """
  @spec feat_icon(map(), atom() | nil) :: String.t() | nil
  def feat_icon(_ruleset, nil), do: nil

  def feat_icon(ruleset, id) do
    case ruleset.feats do
      %{^id => %{icon: icon}} -> icon
      _ -> nil
    end
  end

  # Cap, not a filter: a feat with more than four `siala_note` quotes has
  # never happened (`evasion`'s combined note is one entry, not several), but
  # a popover is not the place to find out what the ceiling should have been.
  #
  # ⚠️ Not the same shape as the blocked feat list any more — that one's own
  # cap was removed by task 3.115 (26.08.2026, Dan: the list has had its own
  # fixed-height scroll area for a long time, so a length limit no longer
  # protects anything). A notes popover is a different problem: `.feat-lists`
  # scrolls, a popover does not, so this cap stays and is not read back as
  # evidence the other one should have too.
  @feat_info_notes_limit 4

  @doc """
  Everything the feat info popover shows (task 3.87, Dan 24.08.2026): the
  Fandom page's own "Specifics" prose, plus — when the shard rewrote the
  feat — a caution and the shard's own words beside it, never blended into
  the same string.

  `description` is never run through `gettext/1,2`, unlike everything else in
  this module (moduledoc, top): it is a direct quote of the source, not our
  interface copy, and translating it would both invent wording and complicate
  the project's CC-BY-SA attribution (CLAUDE.md §4, revised 24.08.2026 for
  exactly this field).

  ## Why the shard's own quotes are filtered to `siala_note`

  `siala_changes` carries every fact the shard layer applied — type, use,
  requirements, granted level, repeatability, disabled — and most of those
  are already shown elsewhere on the same row (the slot chip, the "нужен…"
  reason, the granted-feats line). Dan asked this popover to show what a feat
  *does* and named the one thing it must not repeat: «я не хочу показывать
  у фитов, что импрув эвейжен доступен вору с ХХ-го уровня, это мы и так
  показываем уже сейчас». `siala_note` is the one `what` that carries exactly
  that — the mechanic itself, in the page's own words (`Evasion`'s extra
  chance to dodge eight named spells, not the three levels it now arrives
  at) — so it is the only kind whose quote is printed as the changed feat's
  content. Measured against all 83 vanilla feats the shard touched: twelve
  carry a `siala_note`, the rest only administrative facts already shown
  elsewhere.

  A feat with `siala_changes` but no `siala_note` still has to be flagged —
  CLAUDE.md §3's «не молчаливое ванильное описание» covers all 83, not only
  the twelve with a mechanic quoted in the shard's own words — so
  `siala_changed?` and `siala_notes` answer separate questions, and the
  caller (`BuilderComponents.feat_info/1`) shows a plain caution when the
  second is empty rather than nothing at all.

  `siala_only?` feats (the five custom weapon proficiencies, task 3.87)
  answer `description: nil` here exactly as `ruleset.feats` already does —
  their Russian prose (`special_raw`) is not translated to fill this field,
  the same call CLAUDE.md §4 already makes about a shard-only page's name.

  All strings the caller does not have to build itself are composed here,
  through `gettext/ngettext`, so `BuilderComponents.feat_info/1` never mixes
  a hardcoded Russian literal into the JS that renders the panel (the same
  reason the trigger's own `aria-label` is built in this module and not
  beside the `<span>`).
  """
  @spec feat_info(map(), atom() | nil) :: %{
          description: String.t() | nil,
          siala_changed?: boolean(),
          siala_notes: [String.t()],
          siala_notes_more_text: String.t() | nil,
          source_url: String.t() | nil,
          source_link_text: String.t() | nil
        }
  def feat_info(_ruleset, nil), do: empty_feat_info()

  def feat_info(ruleset, id) do
    case Map.get(ruleset.feats, id) do
      nil -> empty_feat_info()
      feat -> feat_info_from(feat)
    end
  end

  defp empty_feat_info do
    %{
      description: nil,
      siala_changed?: false,
      siala_notes: [],
      siala_notes_more_text: nil,
      source_url: nil,
      source_link_text: nil
    }
  end

  defp feat_info_from(feat) do
    notes =
      feat.siala_changes
      |> Enum.filter(&(&1["what"] == "siala_note"))
      |> Enum.map(&Reading.strip_wiki_prose(&1["quote"]))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    more = max(length(notes) - @feat_info_notes_limit, 0)
    source_url = fandom_source_url(feat.source)

    %{
      description: feat.description,
      siala_changed?: feat.siala_changes != [],
      siala_notes: Enum.take(notes, @feat_info_notes_limit),
      siala_notes_more_text: notes_more_text(more),
      source_url: source_url,
      source_link_text: source_link_text(source_url, feat.source)
    }
  end

  defp notes_more_text(0), do: nil

  defp notes_more_text(n),
    do: ngettext("…and %{n} more note", "…and %{n} more notes", n, n: n)

  defp source_link_text(nil, _source), do: nil

  defp source_link_text(_url, %{"page" => page}),
    do: gettext("Source: %{page} (Fandom)", page: page)

  # `String.replace/3` before `URI.encode/1`: MediaWiki's pretty `/wiki/`
  # path uses underscores for spaces, and encoding first would percent-escape
  # the space into `%20`, a technically-valid but ugly link Fandom itself
  # never prints. Everything else (parens in "Epic energy resistance
  # (Fire)", apostrophes) goes through `URI.encode/1` for a link guaranteed
  # valid rather than one that merely looks right on the pages seen so far.
  defp fandom_source_url(%{"wiki" => "fandom", "page" => page}) when is_binary(page) do
    "https://nwn.fandom.com/wiki/" <> URI.encode(String.replace(page, " ", "_"))
  end

  defp fandom_source_url(_source), do: nil

  @doc """
  Name of whatever an AC gap is about — a feat, a class or a skill.

  The gaps of `vanilla/ac_bonuses.json` carry an id and not what kind of thing
  it is, because four kinds of source produce them and one id is what a
  formatter needs. So all three dictionaries are tried, in the order the file's
  own records go: no id in that file appears in two of them, and
  `summary_test.exs` walks every record to keep it that way rather than trusting
  the sentence.
  """
  @spec ac_bonus_name(map(), atom()) :: String.t()
  def ac_bonus_name(ruleset, id) do
    cond do
      is_map_key(ruleset.feats, id) -> feat_name(ruleset, id)
      is_map_key(ruleset.classes, id) -> class_name(ruleset, id)
      is_map_key(ruleset.skills, id) -> skill_name(ruleset, id)
      true -> to_string(id)
    end
  end

  @doc """
  Name of one value a feat's choice can take — a school of magic, a creature type.

  Имя берётся **из данных** и не собирается из id: `monstrous_humanoid` — наша
  нормализация, а не то, как сущность называется на вики, и разворачивать её
  в текст значило бы дорисовывать регистр, которого в источнике может не быть
  (CLAUDE.md §3). Нет имени в справочнике — показываем id как есть: это честнее
  придуманного написания, и сразу видно, что справочник неполон.

  Имена здесь английские намеренно: школа магии и раса-враг — игровые сущности,
  а у них имя английское (§4). По-русски вокруг них только подписи интерфейса.
  """
  @spec choice_name(map(), atom(), atom() | nil) :: String.t()
  def choice_name(_ruleset, _feat, nil), do: "—"

  def choice_name(ruleset, feat, choice) do
    with domain when not is_nil(domain) <- choice_domain(ruleset, feat),
         %{} = dictionary <- Map.get(ruleset.choice_domains || %{}, domain) do
      domain_value_name(ruleset, dictionary, choice)
    else
      _ -> to_string(choice)
    end
  end

  # Два вида справочника, и у второго имён нет вовсе.
  #
  # Файл (`spell_schools.json`, `creature_types.json`) несёт `names` — берём
  # оттуда. А домен `skill` резолвится не в файл, а **в словарь самого ruleset'а**
  # (`Loader.Reading.resolve_domain/3`, `source: {:ruleset, :skills}`), и `names` у него
  # пустой — так что `Skill focus` печатался как `Skill focus (move_silently)`.
  # Имя у навыка есть, просто лежит в его собственной записи, и `skill_name/2`
  # читает его уже давно. Это не дорисовка регистра, запрещённая §3, а тот же
  # самый источник — просто добытый через ту дверь, которую домен сам называет.
  defp domain_value_name(ruleset, dictionary, choice) do
    case dictionary do
      %{names: %{^choice => name}} ->
        name

      %{source: {:ruleset, kind}} ->
        case Map.get(Map.get(ruleset, kind, %{}), choice) do
          %{name: name} when is_binary(name) -> name
          _ -> to_string(choice)
        end

      _ ->
        to_string(choice)
    end
  end

  defp choice_domain(ruleset, feat) do
    case ruleset.feats do
      %{^feat => %{repeatable: %{choice: domain}}} -> domain
      _ -> nil
    end
  end

  @doc """
  Name of a weapon, English as every other game entity (§4).

  Read from `ruleset.weapons`, the same dictionary that feeds the `weapon` choice
  domain — one set of ids and one set of names, because the weapon a focus was
  taken with and the weapon in the character's hands are the same thing (task
  3.5). An id the dictionary does not know shows as the id, like everywhere else.
  """
  @spec weapon_name(map(), atom() | nil) :: String.t()
  def weapon_name(_ruleset, nil), do: "—"

  def weapon_name(ruleset, id) do
    case Map.get(ruleset, :weapons) || %{} do
      %{^id => %{name: name}} when is_binary(name) -> name
      _ -> to_string(id)
    end
  end

  @doc """
  Name of one value a class's own choice can take — a Cleric domain, English
  as every other game entity (§4). Same lookup as `choice_name/3`, sourcing
  the domain from `BuildCalculator.Rules.ClassChoices` instead of a feat's
  `repeatable.choice` — the two read the same `ruleset.choice_domains` table.
  """
  @spec class_choice_value_name(map(), atom(), atom() | nil) :: String.t()
  def class_choice_value_name(_ruleset, _class, nil), do: "—"

  def class_choice_value_name(ruleset, class, value) do
    with domain when not is_nil(domain) <-
           BuildCalculator.Rules.ClassChoices.domain(class, ruleset),
         %{} = dictionary <- Map.get(ruleset.choice_domains || %{}, domain) do
      domain_value_name(ruleset, dictionary, value)
    else
      _ -> to_string(value)
    end
  end

  @doc """
  Name of a school of magic, English as every other game entity (§4).

  Read out of the very dictionary the choice is drawn from
  (`ruleset.choice_domains.spell_school`), so the school printed on a spell in
  the picker and the school on a specialization chip are one word from one
  place. ⚠ Before task 3.86 the picker printed `spell.school` **raw** — that
  field is wikitext, and `Clarity` really did render as
  `<del>abjuration</del> <i>necromancy</i>` on screen.
  """
  @spec spell_school_name(map(), atom() | nil) :: String.t() | nil
  def spell_school_name(_ruleset, nil), do: nil

  def spell_school_name(ruleset, school) do
    case Map.get(ruleset.choice_domains || %{}, :spell_school) do
      %{} = dictionary -> domain_value_name(ruleset, dictionary, school)
      _no_dictionary -> to_string(school)
    end
  end

  @doc """
  What a class's own choice gives — one sentence for the whole picker.

  `nil` for a class whose choice has no arithmetic behind it (a Cleric's
  domains, whose powers and spells the model does not touch at all), so their
  panel looks exactly as it did.

  🔴 Задача 3.86, решение Dan. До неё специализация волшебника показывала игроку
  **только выгоду**: `+1` слот на каждый круг считался и печатался, а цена —
  потеря противоположной школы — не называлась нигде, хотя выбор делается
  в нашем же интерфейсе. Теперь на экране обе половины: выгода одной строкой
  над чипами (она у всех восьми школ одинаковая), цена — на каждом чипе своя
  (`specialization_cost/2`). Числа обе берут у ядра
  (`Rules.Spells.specialization/2` и `specialization_costs/2`), здесь только
  слова.
  """
  @spec specialization_gain(map() | nil) :: String.t() | nil
  def specialization_gain(nil), do: nil

  # ⚠️ «+1 к слотам», а не «+1 слот»: `bonus_per_circle` — число из данных,
  # и «+2 слот» по-русски не читается вовсе.
  def specialization_gain(%{bonus_per_circle: bonus, min_circle: 0}),
    do: gettext("+%{n} to the slots of every circle", n: bonus)

  # ⚠️ Круг, с которого прибавка начинается, назван потому, что он и правда
  # не нулевой: `min_circle: 1` значит, что заговоры её не получают (измерено
  # Dan 09.08.2026), а «каждого круга» без оговорки было бы на один круг щедрее
  # правды.
  def specialization_gain(%{bonus_per_circle: bonus, min_circle: min}),
    do: gettext("+%{n} to the slots of every circle from circle %{min}", n: bonus, min: min)

  def specialization_gain(_no_rule), do: nil

  @doc """
  What one value of that choice costs — the school it closes and how much of the
  list goes with it (`Rules.Spells.specialization_costs/2`).

  ⚠️ Счёт ПОЖИЗНЕННЫЙ, а не по кругам, до которых персонаж дорос: школа
  называется один раз и навсегда, значит и цена у неё одна на весь билд
  (решение Dan).

  ⚠️ Знаменатель печатается вместе с числом, а не подразумевается: «закрывает
  Conjuration — 27 заклинаний» не отвечает на «27 из скольких», а разница между
  27 из 179 и 27 из 40 — это разница между «дорого» и «билд не собрать».
  """
  @spec specialization_cost(map(), map() | nil) :: String.t() | nil
  def specialization_cost(_ruleset, nil), do: nil

  # ⚠️ `ngettext/3` — настоящее место склонения: «21 заклинание», «22 заклинания»,
  # «27 заклинаний». Сегодня все восемь чисел попадают в третью форму, и это
  # ровно тот случай, когда захардкоженная форма выглядела бы верной до первой
  # правки данных.
  def specialization_cost(ruleset, %{school: school, spells: spells, list_size: total}) do
    gettext("closes %{school} — %{count} of %{total}",
      school: spell_school_name(ruleset, school),
      count: ngettext("%{n} spell", "%{n} spells", spells, n: spells),
      total: total
    )
  end

  @doc """
  Имя того, что лежит в слоте, — с выбором, если он записан.

  `Spell focus (Evocation)` — это написание сообщества, и оно же уходит
  в канонический экспорт, так что в интерфейсе и в тексте для форума фит
  выглядит одинаково. Регистр имени не трогаем: на Fandom его не приводят
  к Title Case, а дорисовывать его — такая же выдумка, как число (§3).

  Принимает то, что реально лежит в билде, — голый атом или пару, — потому что
  ровно это и читают все места, где видно имя фита. Разбирать пару у каждого
  из них по отдельности значило бы пять раз повторить одно правило.
  """
  @spec feat_pick_name(map(), BuildCalculator.Rules.Build.feat_pick() | nil) :: String.t()
  def feat_pick_name(_ruleset, nil), do: "—"

  def feat_pick_name(ruleset, pick) do
    id = BuildCalculator.Rules.Build.feat_id(pick)

    case BuildCalculator.Rules.Build.feat_choice(pick) do
      nil -> feat_name(ruleset, id)
      choice -> "#{feat_name(ruleset, id)} (#{choice_name(ruleset, id, choice)})"
    end
  end

  @doc """
  То же имя со счётчиком взятий: `Epic toughness ×3`.

  ⚠️ Счётчик — **нарастающий итог**, а не «сколько раз я нажал здесь». Взятия
  разбросаны по уровням (десять `Epic toughness` — это десять уровней), и
  вопрос, на который отвечает строка лестницы, — «сколько их у меня к этому
  моменту». Первое взятие счётчика не получает: `×1` пришлось бы читать на
  каждом фите билда, а значит не читать вовсе.
  """
  @spec feat_pick_name(map(), BuildCalculator.Rules.Build.feat_pick() | nil, non_neg_integer()) ::
          String.t()
  def feat_pick_name(ruleset, pick, takes) when takes > 1,
    do: feat_pick_name(ruleset, pick) <> " ×#{takes}"

  def feat_pick_name(ruleset, pick, _takes), do: feat_pick_name(ruleset, pick)

  @doc """
  Same as `feat_icon/2`, but reads a slot's pick — a bare feat id or
  `{feat_id, choice}` (AGENT_QUEUE.md 3.54). The art belongs to the *feat*, not
  to the choice made with it — `Spell focus (Evocation)` and `Spell focus
  (Necromancy)` share one icon — so this only ever peels the id off the pair,
  the same split `feat_pick_name/2` already does for the name.
  """
  @spec feat_pick_icon(map(), BuildCalculator.Rules.Build.feat_pick() | nil) :: String.t() | nil
  def feat_pick_icon(_ruleset, nil), do: nil
  def feat_pick_icon(ruleset, pick), do: feat_icon(ruleset, Build.feat_id(pick))

  @doc """
  Имя домена выбора по-русски: «школа магии», «навык», «оружие».

  ⚠️ Раньше здесь стояло `to_string(domain)` с обоснованием «домен — игровое имя,
  канонического перевода нет». Обоснование было ошибкой: игровое имя — это
  **значение** (`Evocation`, `Tumble`), а домен — категория, то есть подпись
  интерфейса, и подписи у нас русские (CLAUDE.md §4). Наружу от этого уезжал
  наш собственный ключ данных: игрок читал «всё из «spell_school» уже взято»
  (найдено Dan, 03.08.2026).

  Словарь живёт в коде, а не в `priv/rules/`, и это решение, а не лень. Русская
  подпись интерфейса — не игровой факт: у неё нет источника, нечего проставлять
  в `source`, и ревьюер данных о ней ничего сказать не может. К тому же
  `priv/rules/vanilla/` переписывается `mix wiki.parse`, а всякий незнакомый файл
  в этой папке загрузчик считает **справочником значений** (`domain_files/1`), —
  то есть подписи пришлось бы регистрировать в двух местах, чтобы они не стали
  фальшивым доменом.

  ⚠️ Цена такого решения — молчаливый провал на домене, которого здесь нет:
  вернулся бы ключ, и мы получили бы ровно тот же баг. Поэтому сторожем стоит
  тест, который проходит по **всем** доменам обоих ruleset'ов и требует имени
  для каждого (`labels_test.exs`), а не глаз ревьюера.
  """
  @spec domain_name(atom() | nil) :: String.t()
  def domain_name(:spell_school), do: gettext("school of magic")
  def domain_name(:skill), do: gettext("skill")
  def domain_name(:weapon), do: gettext("weapon")

  # Клирик выбирает домены при взятии класса (задача 3.14) — тот же справочник
  # `ruleset.choice_domains`, что обслуживает фиты с выбором, а не отдельная
  # таблица (`BuildCalculator.Rules.ClassChoices`).
  def domain_name(:domain), do: gettext("domain")

  # `creature_types.json`: «The 25 racial **types** a Favored enemy is chosen
  # from», и сама вики называет их расами («24 favored enemy races available»).
  # Домен сегодня обслуживает один фит, и «раса-враг» — то, как его называет
  # игрок; появится второй фит с этим доменом — имя придётся пересмотреть,
  # и это ровно тот случай, когда данные обязаны попасть человеку на стол
  # (см. `_note` в справочнике).
  def domain_name(:creature_type), do: gettext("favored enemy race")

  # `energy_types.json`: acid / cold / electrical / fire / sonic. «Вид энергии»
  # точнее по букве источника, «стихия» — то слово, которым это называют игроки;
  # выбрано второе, потому что подпись интерфейса адресована им.
  #
  # ✅ Вопрос закрыт Dan 03.08.2026, не переоткрывать: «можем звук к стихии
  # отнести, да, только потому что в nwn sonic так распространён». То есть
  # натяжка со звуком осознанная, и держится она не на букве источника,
  # а на том, что звуковой урон в NWN игроку привычен.
  def domain_name(:energy_type), do: gettext("element")

  # ⚠️ Не «на всякий случай»: домены приходят из данных (`repeatable.choice`),
  # и новый может появиться с очередным `mix wiki.parse`. Ключ как есть —
  # плохой, но ЗАМЕТНЫЙ ответ, и тест-сторож падает раньше, чем его увидит игрок.
  def domain_name(domain), do: to_string(domain)

  @doc """
  Heading for a class's own choice section — «Домены», а не производное от
  `domain_name/1` в множественном числе.

  ⚠️ Русская форма множественного числа не выводится программно: «домен» →
  «домены», а «школа магии» (будущий выбор волшебника, задача 3.10) должна
  остаться в единственном числе, потому что там выбирается ОДНО значение —
  «школы магии» читалось бы как несколько. Автоматическое склонение по
  `count` из данных решало бы не ту задачу и для двух разных грамматик
  потребовало бы двух разных неправильных эвристик; значит слово — здесь,
  вручную, по классу (то же решение, что уже принято для `domain_name/1`).
  """
  @spec class_choice_heading(atom()) :: String.t()
  def class_choice_heading(:cleric), do: gettext("Domains")

  # Задача 3.10 — ровно то единственное число, о котором предупреждает
  # комментарий выше: у волшебника выбирается ОДНА школа, не «школы».
  def class_choice_heading(:wizard), do: gettext("School of magic")

  def class_choice_heading(class_id),
    do: gettext("Choice for class «%{class}»", class: class_id)

  @doc """
  Lower-case noun for «что ждёт» sentences (`hold_note/4`): «домены (1)», не
  заголовок секции. Отдельная функция, а не `String.downcase(class_choice_heading(...))` —
  строчная форма многословного заголовка по-русски не выводится механически.

  ⚠️ Падеж — винительный, а не именительный, хотя выглядит как подпись.
  `hold_note/4` (`class_choice_note/3`) не читает эту функцию вовсе для
  необязательного выбора: она гейтится на `required?: true`, а у клирика
  «домены» им и остаётся что в именительном, что в винительном (неодушевлённое
  множественное число по-русски их не различает). Второй читатель —
  `ladder_class_choice/5` — строит `"выбрать " <> pending_text`, и это
  ЕДИНСТВЕННОЕ место, куда доедет `:wizard`: «выбрать школу магии», а не
  «выбрать школа магии». Заведёшь класс с ОБЯЗАТЕЛЬНЫМ выбором и
  неодушевлённым не-множественным доменом — проверь оба места, падежи разойдутся.
  """
  @spec class_choice_pending_text(atom()) :: String.t()
  def class_choice_pending_text(:cleric), do: gettext("domains")

  # ⚠️ Свой msgid, а не переиспользование `domain_name(:spell_school)`
  # («школа магии»): падеж другой (винительный, см. doc выше), и один msgid
  # не может нести два разных msgstr для одной и той же локали. Английский
  # текст поэтому тоже другой ("a school of magic", не "school of magic") —
  # так у двух msgid остаётся два разных ключа, хотя по-английски падежей нет.
  def class_choice_pending_text(:wizard), do: gettext("a school of magic")
  def class_choice_pending_text(class_id), do: gettext("class choice «%{class}»", class: class_id)

  @doc """
  Name of a feat a class hands over, carrying the rank it arrives at.

  The wiki keeps one page per *family* of ranks, so `Defensive awareness` is one
  id handed over at Dwarven defender 2, 5 and 10. Without the rank the player
  reads the same line three times and learns nothing (CLAUDE.md §9). The rank
  is the wiki's own wording, unnormalised: `"II"`, `"(+5HP)"`, `"1/day"`.

  ⚠️ Five of the 103 ranks are not a suffix but **the step's own name**
  (`barbarian_rage` at 15, 16 and 20 → `"greater rage (4x/day)"` … `"(6x/day)"`,
  `elemental_shape` at 20 → `"improved elemental shape"`,
  `infinite_greater_wildshape` at 13 → `"infinite humanoid shape"`). Two of them
  have no suffix at all, so the parser had nothing else to tell the levels apart
  with. Those replace the feat name rather than follow it — appending would read
  "Barbarian rage greater rage (4x/day)".

  The two are told apart by shape: a rank marker is a Roman numeral or starts
  with a sign, a digit or a bracket, while a name starts with a word. Fandom
  does not title-case, so the word arrives lowercase.

  ⚠️ **A Roman numeral may carry decoration, and the strict test used to lose the
  feat name over it** (§7, найдено 10.08.2026). `Rogue.wikitext` writes the last
  step of `uncanny dodge` as `VI+` — «VI and above», the table's last row — and
  `^[IVXLCDM]+$` does not match a trailing plus, so вор 20 printed `"VI+"` with
  no feat name at all, while вор 17 printed `"Uncanny dodge V"`. `VI+` is the
  **only** such record (посчитано обходом `granted_feat_ranks` на обоих
  ruleset'ах: 6 из 103 записей начинаются с буквы и не являются строгим римским
  числом, и пять из шести — те самые имена ступеней выше). Hence the numeral test
  tolerates a non-letter tail, and the discriminator stays «имя ступени — это
  слово», not «строка начинается с буквы».
  """
  @spec granted_feat_name(map(), atom() | nil, String.t() | nil) :: String.t()
  def granted_feat_name(ruleset, id, nil), do: feat_name(ruleset, id)

  def granted_feat_name(ruleset, id, rank) when is_binary(rank) do
    case String.trim(rank) do
      "" -> feat_name(ruleset, id)
      trimmed -> apply_rank(feat_name(ruleset, id), trimmed)
    end
  end

  defp apply_rank(name, rank) do
    if step_name?(rank), do: capitalize_first(rank), else: name <> " " <> rank
  end

  defp step_name?(rank) do
    String.match?(rank, ~r/^\p{L}/u) and not rank_numeral?(rank)
  end

  # A Roman numeral, optionally decorated: `VI+` is the rank «VI and above», not
  # a step whose name is «VI+». The tail is allowed to be anything WITHOUT
  # letters — a second word (`IX days`) would mean the wiki wrote prose there,
  # and prose is a name, not a marker.
  defp rank_numeral?(rank), do: String.match?(rank, ~r/^[IVXLCDM]+[^\p{L}]*$/u)

  # Only the first letter, `String.capitalize/1` would lower-case the rest and
  # turn "infinite humanoid shape (II)" into something the wiki never wrote.
  defp capitalize_first(<<first::utf8, rest::binary>>),
    do: String.upcase(<<first::utf8>>) <> rest

  @doc "Skill name straight out of the ruleset."
  @spec skill_name(map(), atom() | nil) :: String.t()
  def skill_name(_ruleset, nil), do: "—"

  def skill_name(ruleset, id) do
    case ruleset.skills do
      %{^id => %{name: name}} when is_binary(name) -> name
      _ -> to_string(id)
    end
  end

  @doc "Spell name straight out of the ruleset."
  @spec spell_name(map(), atom() | nil) :: String.t()
  def spell_name(_ruleset, nil), do: "—"

  def spell_name(ruleset, id) do
    case ruleset.spells do
      %{^id => %{name: name}} when is_binary(name) -> name
      _ -> to_string(id)
    end
  end

  @doc """
  Raw Fandom icon filename for a spell, or `nil` — same contract as
  `spell_name/2` and as `feat_icon/2` (AGENT_QUEUE.md 3.54). 9 of 303 spells
  carry no `icon`; there is no epic/general fallback glyph to reach for
  instead, on purpose (task 3.50 — the circle badge already answers "what is
  this", so a `<.game_icon>` with a `nil` path here prints an empty box, never
  an invented symbol).
  """
  @spec spell_icon(map(), atom() | nil) :: String.t() | nil
  def spell_icon(_ruleset, nil), do: nil

  def spell_icon(ruleset, id) do
    case ruleset.spells do
      %{^id => %{icon: icon}} -> icon
      _ -> nil
    end
  end

  @doc "Russian alias for an English entity name, from the wiki redirects."
  @spec alias_ru(map(), String.t()) :: String.t() | nil
  def alias_ru(ruleset, name), do: Map.get(ruleset.name_map, name)

  @doc """
  Russian name of an armour class type, as the ruleset spells it.

  The list of types and their wording both live in the data
  (`ruleset.gear.ac_types` / `ac_type_names`) — a type nobody named falls back
  to its id rather than to a guess.
  """
  @spec ac_type(map(), atom()) :: String.t()
  def ac_type(ruleset, type) do
    Map.get(ruleset.gear.ac_type_names, Atom.to_string(type), Atom.to_string(type))
  end

  @doc """
  Label for a feat slot chip: what kind of slot it is, in Russian.

  Every kind that changes past level 20 says `· эпик`, and it says it the same
  way — the epic class bonus slot used to be called plain «Бонус Fighter»,
  exactly like the level-2 one, though its pool is a different list: an epic
  bonus slot takes the class's *epic* feats and the ordinary one refuses them.
  Two different pools under one caption is the same mistake as calling a general
  and a bonus slot both «фит» (CLAUDE.md §6).

  `epic?` is read with `Map.get/3` on purpose: callers that only have a slot's
  shape (an id, no level) pass a map without it, and for them the plain wording
  is the correct answer rather than a crash.
  """
  @spec slot_label(map(), map()) :: String.t()
  def slot_label(ruleset, slot) do
    case slot.kind do
      :general ->
        gettext("General")

      :epic_general ->
        gettext("General") <> epic_badge()

      :racial ->
        gettext("Race bonus")

      :class_bonus ->
        gettext("Bonus %{class}", class: class_name(ruleset, slot.class)) <>
          epic_suffix(slot) <> index_suffix(slot)
    end
  end

  # ⚠️ « · эпик» concatenates onto a class name freely (task 3.83) — unlike
  # `save_prereq_exceptions/1` below, this is a badge appended after a game
  # entity name, not a clause continuing a sentence's grammar: word order,
  # comma and agreement never come into it, English says «Bonus Fighter ·
  # epic» in exactly the same order. Considered folding it into a whole-phrase
  # `gettext/2` per slot kind and rejected — that would have meant four near
  # duplicate msgids differing only by this one badge.
  defp epic_badge, do: " · " <> gettext("epic")
  defp epic_suffix(slot), do: if(Map.get(slot, :epic?, false), do: epic_badge(), else: "")

  # Порядковый номер слота, когда класс даёт на уровне НЕ ОДИН бонусный фит.
  # Сегодня такое место ровно одно во всём корпусе — рейнджер на своём 35-м
  # классовом уровне («35(two bonus feats)», fandom:Ranger, правка 14.08.2026),
  # и без номера два чипа подряд читаются одинаково: «Бонус Ranger · эпик»
  # дважды. Пока оба пусты, игрок не понимает, в который кладёт.
  #
  # ⚠️ Номер печатается ТОЛЬКО у второго и далее, и это не небрежность,
  # а следствие формы `slot_id`: первый слот сознательно сохранил прежний вид
  # `{:class_bonus, class}` — строка «class_bonus:ranger» лежит в чужих
  # расшаренных ссылках, и переименовать её значило бы уронить пик у всех
  # существующих билдов. Подпись повторяет ту же асимметрию: без номера —
  # тот, что был всегда.
  #
  # ⚠️ Функция читает `id`, а не считает слоты уровня: `slot_label/2` получает
  # ОДИН слот и про соседей не знает вовсе. Считать их здесь значило бы завести
  # второй источник правды о том, сколько их, — а он уже есть, в `FeatSlots`.
  #
  # 🔴 И номер добавляется ТОЛЬКО к подписи чипа (`slot_label/2`), а НЕ к сводной
  # (`slot_delta_label/2`) и не к строке лестницы (`slot_ladder_label/2`) — это
  # проверено падением теста, а не выбрано из вкуса. Сводная подпись группирует
  # слоты ПО ТЕКСТУ и показывает «бонус Ranger · эпик ×2»; пронумеруй её — и два
  # слота перестанут схлопываться, а вместо честного «×2» игрок получит две
  # строки об одном и том же. Лестница же печатает выбранный фит, и там номер
  # слота не отвечает ни на один вопрос.
  #
  # Разделение труда получается такое: сводная говорит СКОЛЬКО их, чип —
  # КОТОРЫЙ из них, и ни одна из подписей не пытается сказать оба.
  defp index_suffix(slot) do
    case Map.get(slot, :id) do
      {:class_bonus, _class, index} when is_integer(index) -> " · " <> Integer.to_string(index)
      _one_of_a_kind -> ""
    end
  end

  @doc """
  Glyph for a feat slot: `✦` общий, `★` эпический, `⚔` бонусный (CLAUDE.md §6).

  ⚠️ Three glyphs, four pools. `general`/`epic_general` and ordinary/epic class
  bonus are four different lists of feats, and §6 warns the column's alphabet
  (`✦` фит, `▲` стат, `▪` навык) is dense enough already — so a fourth glyph is
  not the answer. The axis that stays on the glyph is the one that has to be
  readable at a glance in a column of 41 rows: **whose list is it**. `⚔` in the
  class's own colour therefore stays on a class bonus slot whether or not the
  level is epic, and the epic half of that slot travels as text
  (`slot_label/2`, `slot_ladder_label/2`).

  The alternative — `★` on every epic slot — was tried on paper and rejected:
  at level 24 a Fighter holds an epic general *and* an epic class bonus at once,
  and giving both the same glyph brings back the very confusion this is fixing.
  """
  @spec slot_glyph(map()) :: String.t()
  def slot_glyph(%{kind: :class_bonus}), do: "⚔︎"
  def slot_glyph(%{kind: :epic_general}), do: "★"
  def slot_glyph(_slot), do: "✦"

  @doc """
  How an *unfilled* slot reads in the progression column.

  The shortest wording that still names the pool, because the column is 316px
  wide by default and a caption on every slot would push the ladder the same way
  a Sorcerer's six spell rows once did (CLAUDE.md §6). So: «фит Fighter», never
  «выбрать бонусный фит класса Fighter» — the class colour on the glyph already
  says whose slot it is, and the name only has to confirm it.

  The verb is gone on purpose. «Не выбрано» is carried by italics and by the
  amber `--todo`, which is precisely the job §6 gives them; spending the line on
  «выбрать» instead of on *which* slot is what made a Fighter's first level read
  as «✦ выбрать фит» three times over.

  Class names come out short (`DD`, `WM`, `CoT`) — the abbreviations the
  community already writes (§4).

  ⚠️ The `:general` / `:epic_general` cases used to be one clause with one
  guard, printing one wording for both — a Fighter's level 18 and level 21
  general slot read identically, and the glyph was the only thing telling them
  apart (bug 1.4, Dan 03.08.2026). Splitting the clause does not rename the
  epic slot to "epic feat": its pool only grows past level 20 (93 ordinary
  feats stay inside the 146 an epic-general slot takes — see the count in
  `slot_delta_label/2`'s doc), so it keeps its name and gains the same
  `· эпик` suffix the class-bonus clause below has always had.
  """
  @spec slot_ladder_label(map(), map()) :: String.t()
  def slot_ladder_label(_ruleset, %{kind: :general}), do: general_feat_ladder_word()

  def slot_ladder_label(_ruleset, %{kind: :epic_general}),
    do: general_feat_ladder_word() <> epic_badge()

  def slot_ladder_label(_ruleset, %{kind: :racial}), do: gettext("race feat")

  def slot_ladder_label(ruleset, %{kind: :class_bonus, class: class} = slot),
    do: gettext("feat %{class}", class: class_short(ruleset, class)) <> epic_suffix(slot)

  defp general_feat_ladder_word, do: gettext("general feat")

  @doc """
  Slot wording for a delta chip: «общий фит», «бонус Fighter».

  Longer than `slot_label/2` on purpose, because it is read in a different
  place. A chip in the feat section sits under its own glyph with its contents
  beside it, so «Общий» cannot be misread; a delta chip stands alone in a row of
  numbers on a class card and has to name the thing being promised.

  And it names the *kind*, never just "фит": a class bonus slot is only ever
  spent on a feat from its own class's list, and showing both kinds with the
  same word hides the restriction that later produces an illegal build
  (CLAUDE.md §6). «общий» / «бонус» are interface words and stay Russian; the
  class name stays English like every other game entity (§4).

  ⚠️ Past level 20 the epic-general and epic class-bonus branches used to read
  «эпический фит» / «эпический бонус Fighter» (bug 1.4, found by Dan
  03.08.2026). That wording is a lie by omission: the slot does not swap to a
  smaller epic-only pool past level 20, it **grows** — `FeatSlots.candidates/2`
  on a Fighter still counts the 93 ordinary feats inside the 146 an
  epic-general slot takes, and the 37 ordinary bonus feats inside the 47 an
  epic class-bonus slot takes (re-measured 04.08.2026, unchanged from the
  original 93/146/53 finding despite four rounds of data and rule changes in
  between). A chip that says "epic feat" would have promised 93 fewer options
  than the slot actually offers, steering a player away from the ordinary
  feats still sitting in it — the same "confident lie" this module exists to
  avoid, just spoken about a slot instead of a number.

  So both branches keep the ordinary name and add the same `· эпик` suffix
  `slot_label/2` and the class-bonus branch of `slot_ladder_label/2` already
  use for the identical change of pool — one formula for one fact, not three
  different sentences about it.
  """
  @spec slot_delta_label(map(), map()) :: String.t()
  def slot_delta_label(_ruleset, %{kind: :general}), do: general_feat_ladder_word()

  def slot_delta_label(_ruleset, %{kind: :epic_general}),
    do: general_feat_ladder_word() <> epic_badge()

  def slot_delta_label(_ruleset, %{kind: :racial}), do: gettext("race feat")

  def slot_delta_label(ruleset, %{kind: :class_bonus, class: class} = slot),
    do: gettext("bonus %{class}", class: class_name(ruleset, class)) <> epic_suffix(slot)

  # ------------------------------------------------- level-up refusal reasons --

  @doc """
  A machine reason from `Rules.validate_level_up/3`, in Russian.

  A locked class is shown with its reason rather than hidden — that is how the
  tool teaches the rules instead of merely refusing (CLAUDE.md §6).
  """
  @spec reason(term(), map()) :: String.t()
  def reason({:level_cap, cap}, _ruleset), do: gettext("level cap %{cap}", cap: cap)

  # ⚠️ `ngettext/3`, а не интерполяция в одну форму: `n` — предел классов
  # ruleset'а, сегодня всегда 4, но «класса»/«класс»/«классов» — три разные
  # формы, и текст обязан пережить любое будущее значение честно, а не только
  # то, что уже наблюдалось.
  def reason({:max_classes, n}, _ruleset),
    do: ngettext("limit %{n} class", "limit %{n} classes", n, n: n)

  def reason({:class_level_cap, class, cap}, ruleset),
    do: gettext("ceiling %{class}: %{cap}", class: class_name(ruleset, class), cap: cap)

  def reason({:requires_character_level, level}, _ruleset),
    do: gettext("requires character level %{level}", level: level)

  # --- оружие в руках (задача 3.5, часть B) ---
  #
  # ⚠️ Третьей причины здесь нет намеренно: «нет фита владения» печатается общей
  # формой `{:requires_feat, …}` выше. Своя формулировка отличалась бы от неё
  # только местом, где её произвели, а фраза «нужен фит Владение клинковым
  # оружием» и так говорит игроку ровно то, что нужно.
  def reason({:unknown_weapon, weapon}, ruleset),
    do: gettext("%{weapon} is not in the reference data", weapon: weapon_name(ruleset, weapon))

  def reason({:not_wieldable, weapon}, ruleset),
    do:
      gettext("%{weapon} is not an item, it is a creature attack",
        weapon: weapon_name(ruleset, weapon)
      )

  # ⚠️ Отдельная фраза от соседней сверху, и разница смысловая: там предмета
  # не существует как вещи вообще (форма атаки существа), а здесь вещь обычная,
  # просто на шарде её нет. Наблюдение Dan 16.08.2026: «Lance вроде как
  # не используется вообще, нет такого на Сиале».
  def reason({:not_on_shard, weapon}, ruleset),
    do: gettext("%{weapon} does not occur on Siala", weapon: weapon_name(ruleset, weapon))

  # --- размер (задача 3.43) ---
  #
  # ⚠️ «Не по руке», а НЕ «двуручное»: двуручное взять можно, просто без щита,
  # а это — нельзя вовсе («cannot be wielded at all»). Раса названа, потому что
  # это её свойство: тот же меч человеку по руке.
  def reason({:weapon_too_large, race}, ruleset),
    do: gettext("too large for race %{race}", race: race_ru(ruleset, race))

  def reason({:weapon_too_small, race}, ruleset),
    do: gettext("too small for race %{race}", race: race_ru(ruleset, race))

  # --- надетое (задача 3.43) ---
  #
  # Две причины на щит, и они разные: одна про расу, другая про то, что в руках.
  def reason({:not_usable_by_race, race}, ruleset),
    do: gettext("race %{race} does not wear this", race: race_ru(ruleset, race))

  def reason({:two_handed_weapon, weapon}, ruleset),
    do: gettext("%{weapon} takes both hands", weapon: weapon_name(ruleset, weapon))

  # 🔴 И третья причина той же руке, с ДРУГОЙ фразой (задача 3.132): «занята
  # двуручным оружием» и «занята вторым оружием» — разные факты, и игрок по ним
  # идёт менять разные вещи. Одна фраза на два факта отправила бы половину
  # не туда.
  def reason({:off_hand_weapon, weapon}, ruleset),
    do:
      gettext("the off hand holds %{weapon}",
        weapon: weapon_name(ruleset, weapon)
      )

  # И зеркальная — самому второму оружию.
  def reason({:two_handed_in_off_hand, weapon}, ruleset),
    do:
      gettext("%{weapon} takes both hands and cannot go in the off hand",
        weapon: weapon_name(ruleset, weapon)
      )

  # 🔴 И ещё две про ту же руку, но про ДРУГОЕ (задача 3.142): не «сколько рук
  # занимает», а «в какой руке может оказаться». Обе фразы обязаны отличаться
  # и от пары про хват, и друг от друга: у пары про хват вместе с рукой уходит
  # щит, а здесь он остаётся, и игрок, прочитавший «занимает обе руки» про
  # пращу, пошёл бы искать несуществующую двуручность.
  def reason({:ranged_in_off_hand, weapon}, ruleset),
    do:
      gettext("%{weapon} is a ranged weapon and does not go in the off hand",
        weapon: weapon_name(ruleset, weapon)
      )

  # ⚠️ Вторая половина того же предложения источника, и она про ГЛАВНУЮ руку.
  # «Щит при этом можно» в подпись не вынесено намеренно: строка печатается
  # у второго ОРУЖИЯ, а про щит рядом никто не спрашивал — обещание в чужой
  # строке читается как разрешение сделать что-то здесь.
  def reason({:ranged_in_main_hand, weapon}, ruleset),
    do:
      gettext("the main hand holds %{weapon}, a ranged weapon — no second weapon with it",
        weapon: weapon_name(ruleset, weapon)
      )

  def reason({:requires_bab, bab}, _ruleset), do: gettext("requires BAB +%{bab}", bab: bab)

  def reason({:requires_race, races}, ruleset),
    do: gettext("only %{races}", races: Enum.map_join(races, ", ", &race_ru(ruleset, &1)))

  def reason({:requires_feat, feat}, ruleset),
    do: gettext("requires feat %{feat}", feat: feat_name(ruleset, feat))

  # ⚠️ «нужен фит X **на одно из**», а не «нужен фит X»: строка адресована тому,
  # у кого фит УЖЕ есть, просто взят на другое оружие. Без второй половины она
  # отправляла бы игрока искать в списке фит, который у него стоит.
  #
  # Значения печатаются поимённо и все: их четыре, они и есть ответ на вопрос
  # «а на что тогда брать», а «одно из четырёх» без имён — это отказ без
  # подсказки. Имена берутся из справочника домена (`choice_name/3`), поэтому
  # ни одного имени оружия здесь нет — §4 и §3 разом.
  def reason({:requires_feat_choice, feat, values}, ruleset) do
    gettext("requires feat %{feat} with one of: %{values}",
      feat: feat_name(ruleset, feat),
      values: Enum.map_join(values, ", ", &choice_name(ruleset, feat, &1))
    )
  end

  # ⚠️ Требование к значению, названное СВОЙСТВОМ, а не списком: «weapon focus
  # **in a melee weapon**». Печатать вместо этого 39 имён оружия было бы
  # не подсказкой, а вываленным словарём, поэтому у формы своя фраза —
  # и она называет то же самое, что источник.
  #
  # ⚠️ Ни одного имени оружия здесь нет: свойство приходит атомом из данных,
  # а превращает его в слова тот же `weapon_property_ru/1`, что подписывает
  # характеристику атаки (§4).
  # ⚠️ Целое предложение на ветку, а не голова со склеенным хвостом: gettext
  # не переводит приклеенный кусок фразы, а падеж хвоста от языка к языку
  # разный (CLAUDE.md §9, урок захода 3.83).
  def reason({:requires_feat_choice_property, feat, :ranged, false}, ruleset),
    do: gettext("requires feat %{feat} in a melee weapon", feat: feat_name(ruleset, feat))

  def reason({:requires_feat_choice_property, feat, :ranged, true}, ruleset),
    do: gettext("requires feat %{feat} in a ranged weapon", feat: feat_name(ruleset, feat))

  def reason({:requires_feat_choice_property, feat, _property, _value}, ruleset),
    do: gettext("requires feat %{feat} with a suitable value", feat: feat_name(ruleset, feat))

  # ⚠️ Обратная полярность соседей: не «нужно вот такое значение», а «вот это
  # не засчитывается». Значения печатаются поимённо и все — их сегодня одно
  # (`Unarmed strike`), и оно и есть ответ на вопрос «а почему класс закрыт,
  # фит же взят». Имя приходит из справочника домена (`choice_name/3`), поэтому
  # ни одного имени оружия здесь нет (§4 и §3 разом).
  #
  # ⚠️ Фраза зеркалит соседнюю («с одним из: …») и не согласуется с числом
  # ни в одном языке — «с любым, кроме: X» верно и про одно значение, и про
  # пять. `ngettext/3` тут был бы лишним: согласовывать нечего.
  def reason({:requires_feat_choice_other_than, feat, values}, ruleset) do
    gettext("requires feat %{feat} with anything but: %{values}",
      feat: feat_name(ruleset, feat),
      values: Enum.map_join(values, ", ", &choice_name(ruleset, feat, &1))
    )
  end

  def reason({:requires_skill_ranks, skill, n}, ruleset),
    do: gettext("requires %{n} r. %{skill}", n: n, skill: skill_name(ruleset, skill))

  def reason({:requires_class_level, class, n}, ruleset),
    do: gettext("requires %{class} %{n}", class: class_name(ruleset, class), n: n)

  # ⚠️ До 19.08.2026 здесь печаталось «нужен STR 25 без вещей» — эти два слова
  # завела правка S1 (`GAME_CHECKS.md`, 16.08.2026) ровно затем, чтобы отказ
  # не читался рядом с панелью итогов как ошибка калькулятора: ядро сравнивает
  # требование с базовым значением (поинт-бай + раса + прибавки уровней +
  # постоянные прибавки билда), а панель показывает статы в шмоте.
  #
  # ⚠️ Убрано решением Dan 19.08.2026 (задача 3.57): «фиты никогда вещи
  # не учитывают, и можно даже не писать об этом, такие правила NWN» —
  # аудитория шарда знает это без подсказки. Правило ядра не меняется —
  # требование по-прежнему считается от базового значения, меняется только
  # подпись.
  def reason({:requires_ability, ability_id, n}, _ruleset),
    do: gettext("requires %{ability} %{n}", ability: ability(ability_id), n: n)

  # ⚠️ До 19.08.2026 здесь тоже стояло «без вещей», теми же словами и по той же
  # причине, что у требования по характеристике выше (`GAME_CHECKS.md` S2,
  # 16.08.2026): ядро сравнивает требование с сейвом персонажа без блока
  # «Вещи», а в панели рядом написан сейв в шмоте, и разрыв между ними у сейвов
  # **крупнее** — вещи дают до +20 против +12 у характеристики, да ещё
  # и через модификатор. Убрано тем же решением Dan 19.08.2026 (задача 3.57)
  # и по той же причине: это одно правило («вещи не открывают фит»), аудитория
  # шарда знает его без подсказки, а ядро продолжает считать как считало.
  #
  # ⚠️ «Без Luck of heroes» ОСТАЁТСЯ — решение 3.57 её не отменяет. Довод
  # Dan («такие правила NWN, игрок и так знает») на эту фразу не распространяется:
  # то, что Удача не засчитывается в требование, не общее правило NWN, а
  # точечное исключение из `fandom:Resist energy`, подтверждённое отдельным
  # замером (`GAME_CHECKS.md` S3, 17.08.2026). Без неё отказ становится
  # неразрешимой загадкой: воин 9 с Удачей видит в панели ровно 8 при
  # требовании 8, вещей у него нет вовсе — то есть без этой фразы отказ ему
  # НИЧЕГО не объясняет.
  # ⚠️ И «на входе в уровень» тоже остаётся, по той же логике — замер
  # `GAME_CHECKS.md` S6, 17.08.2026: воин 12 с телосложением 10 вещей не носит
  # и Удачи не брал, а в панели у него ровно требуемые 8. Восьмёрка приехала
  # вместе с этим самым уровнем, а требование смотрит на вход в него.
  #
  # ⚠️ Слова «на входе в уровень» взяты из таблицы замера дословно, чтобы
  # экран и `GAME_CHECKS.md` называли один момент одинаково.
  #
  # ⚠️ И с 17.08.2026 они **не совсем точны, и это сознательно** (уточнение
  # S7b): снимок, с которым ядро сравнивает требование, — это вход в уровень
  # ПЛЮС прибавка характеристики, записанная на самом уровне. Фраза называет
  # момент чуть более ранний, чем тот, что мы считаем. Оставлено короткой
  # неточностью, а не удлинено, по трём доводам:
  #
  #   * ошибка **односторонняя и в безопасную сторону**: строка обещает меньше,
  #     чем ядро засчитывает, а не больше. Обратное («мы считаем больше, чем
  #     считаем») отправляло бы игрока собирать билд, который не соберётся;
  #   * единственный билд, которому она врёт, — тот, у кого прибавка этого
  #     уровня ещё не вложена в нужную характеристику. Но выбирает он её
  #     на **этом же экране**, и список пересчитывается сразу: фит появится
  #     в тот момент, когда игрок переложит прибавку. На «а если я подниму
  #     телосложение прямо сейчас?» интерфейс отвечает делом, и лучше слов;
  #   * точная формулировка стала бы **второй** оговоркой в строке, где уже
  #     одна («без Luck of heroes»). Строка отвечает на один вопрос —
  #     «почему в панели 8, а фит серый», — и лишние придаточные превращают
  #     ответ в юридический текст, который не дочитывают.
  #
  # ⚠️ Отвергнуто: печатать само число («у тебя на входе было 7»). Это второй
  # полный `Rules.compute/2` на каждую отбитую строку списка из 310 — цена
  # заметная, а вопрос «сколько именно» игрок закрывает одним взглядом
  # на предыдущий уровень лестницы.
  # 🔴 Флагманский пример «сцепленной строки» из задачи 3.83 (см. module doc):
  # раньше здесь стояло `"нужен … на входе в уровень" <> save_prereq_exceptions(ruleset)`,
  # где хвост — отдельная функция, приклеивающая ", без …" или "" через `<>`.
  # Через gettext такой хвост не переводится: у двух веток разный порядок слов,
  # разная пунктуация, и склеенный кусок никогда не виден переводчику целиком.
  # Поэтому теперь это ДВЕ ветки, и у каждой — целое предложение своим `gettext/2`.
  def reason({:requires_save_bonus, save, n}, ruleset) do
    case SaveBonuses.not_counted_for_prerequisites(ruleset) do
      [] ->
        gettext("requires %{save} +%{n} entering the level", save: save_name(save), n: n)

      ids ->
        gettext(
          "requires %{save} +%{n} entering the level, not counting %{excluded}",
          save: save_name(save),
          n: n,
          excluded: Enum.map_join(ids, ", ", &ac_bonus_name(ruleset, &1))
        )
    end
  end

  # Первый МАКСИМУМ в схеме требований — до сих пор были только минимумы, и
  # формулировка обязана это показывать: «нужен 1-й уровень» здесь означало бы
  # ровно противоположное.
  def reason({:max_character_level, 1}, _ruleset), do: gettext("only at level 1")
  def reason({:max_character_level, n}, _ruleset), do: gettext("only up to level %{n}", n: n)

  def reason({:requires_spell_level, n}, _ruleset),
    do: gettext("requires casting circle %{n} spells", n: n)

  # Дизъюнкция: до неё валидатор был чистой конъюнкцией, и «или» в тексте —
  # единственное, что отличает её от списка обязательных требований.
  #
  # ⚠️ Ядро отдаёт **список на ветку**, а не плоский список причин: «дварф» и
  # «Pale master 3» — альтернативы друг другу, а внутри ветки требования всё ещё
  # конъюнкция. Раньше здесь ветка попадала в `reason/2` целиком, не матчилась
  # ни одной клаузой и печаталась через `inspect/1` — то есть на экране стояло
  # `[{:requires_race, [:dwarf]}]`. Нашёл сторож по `Rules.reason_forms/0`.
  #
  # ⚠️ Не «сцепленная строка» в смысле module doc: каждая ветка — уже целое,
  # само по себе переведённое предложение (`branch_reason/2` зовёт `reason/2`),
  # а соединяет их только служебное слово-разделитель — та же форма, что
  # у списка через запятую в `requires_race` выше, просто со своим словом.
  def reason({:requires_any_of, branches}, ruleset),
    do: Enum.map_join(branches, gettext(" or "), &branch_reason(&1, ruleset))

  # «Любой один», а не «любой»: ранги разных навыков не складываются, и без
  # этого слова требование читается как сумма по всем навыкам.
  def reason({:requires_any_skill_ranks, n}, _ruleset),
    do: gettext("requires any one skill with %{n} r.", n: n)

  def reason({:requires_alignment, spec}, _ruleset),
    do: gettext("requires %{spec}", spec: alignment_spec(spec))

  # --- фиты с выбором (школа магии, раса-враг, навык, стихия) ---
  #
  # Формулировки различают четыре РАЗНЫЕ вещи, которые легко слить в одно «нельзя»:
  # фит уже есть целиком; фит есть с этим же значением (а с другим — можно);
  # значение не выбрано вовсе; значение выбрано, но нелегально. Игрок по тексту
  # должен понимать, что ему делать дальше, а не только что ему отказали.
  def reason({:already_taken, feat}, ruleset),
    do: gettext("%{feat} is already taken", feat: feat_name(ruleset, feat))

  def reason({:choice_already_taken, feat, choice}, ruleset),
    do:
      gettext("%{feat} is already taken: %{choice}",
        feat: feat_name(ruleset, feat),
        choice: choice_name(ruleset, feat, choice)
      )

  # Выбор для ВЫДАННОГО фита (задача 3.26): уровень этот фит не выдаёт, значит и
  # выбирать нечего. Доехать сюда можно только правленой руками ссылкой — список
  # чипов рисуется по самой выдаче, — но причина без слов печатается таплом.
  def reason({:not_granted, feat}, ruleset),
    do: gettext("%{feat} is not granted at this level", feat: feat_name(ruleset, feat))

  def reason({:requires_choice, _feat, domain}, _ruleset),
    do: gettext("choose one: %{domain}", domain: domain_name(domain))

  # Ровно тот случай, ради которого затевалась модель выбора: Greater Spell Focus
  # берётся только по школе, где уже есть обычный Spell Focus.
  def reason({:requires_same_choice, feat, choice}, ruleset),
    do:
      gettext("requires %{feat}: %{choice}",
        feat: feat_name(ruleset, feat),
        choice: choice_name(ruleset, feat, choice)
      )

  def reason({:invalid_choice, feat, choice}, ruleset),
    do: gettext("%{choice} does not fit here", choice: choice_name(ruleset, feat, choice))

  # ⚠️ Две причины, а не одна, и различать их обязательно (баг 1.5, найден Dan
  # 03.08.2026). Ядро отдавало пустой список кандидатов в обоих случаях, и
  # волшебнику без единого `Spell focus` писали, что все восемь школ у него уже
  # заняты. «Израсходовано» — про то, что игрок сделал сам; «сначала нужен» —
  # про механику, которой его и надо научить.
  def reason({:choice_exhausted, feat, domain}, ruleset),
    do:
      gettext("%{feat} is already taken for every available value (%{domain})",
        feat: feat_name(ruleset, feat),
        domain: domain_name(domain)
      )

  def reason({:choice_requires, _feat, [required], domain}, ruleset),
    do:
      gettext("requires %{feat} with the same choice first (%{domain})",
        feat: feat_name(ruleset, required),
        domain: domain_name(domain)
      )

  def reason({:choice_requires, _feat, required, domain}, ruleset),
    do:
      gettext("requires %{feats} with the same choice first (%{domain})",
        feats: Enum.map_join(required, gettext(" and "), &feat_name(ruleset, &1)),
        domain: domain_name(domain)
      )

  # Не «ошибка», а честное «проверить нечем»: оружие мы не моделируем вовсе
  # (CLAUDE.md §3), поэтому фит берётся, а выбор остаётся непроверенным.
  #
  # ⚠️ Эта же форма обслуживает и выбор класса (`BuildCalculator.Rules.
  # ClassChoices`) — домен один и тот же справочник (`ruleset.choice_domains`)
  # что у фитов, что у классов, и формулировка про «нет справочника» верна
  # для обоих одинаково: она не называет ни фит, ни класс, только домен.
  def reason({:missing_data, {:choice_domain, domain}}, _ruleset),
    do:
      gettext("choice (%{domain}) is not checked — no reference data",
        domain: domain_name(domain)
      )

  # --- выбор класса (домены клирика, задача 3.14; школа волшебника, 3.10) ---
  #
  # Свои формы, а не переиспользование `invalid_choice`/`choice_exhausted`:
  # те читают ФИТ через `choice_name/3`, а здесь на месте фита — класс, и
  # `ruleset.feats` его просто не найдёт (класс и фит — разные словари).
  def reason({:no_choice, class}, ruleset),
    do: gettext("%{class} has no choice on taking a level", class: class_name(ruleset, class))

  def reason({:invalid_class_choice, class, value}, ruleset),
    do:
      gettext("%{value} does not fit %{class}",
        value: class_choice_value_name(ruleset, class, value),
        class: class_name(ruleset, class)
      )

  def reason({:class_choice_full, class, n}, ruleset),
    do:
      gettext("%{class}: %{n} already chosen — drop one first",
        class: class_name(ruleset, class),
        n: n
      )

  # Счётчик, а не выбор: `Epic toughness` берут по 10 раз, и потолок — свойство
  # фита, а не слота. Формулировка называет предел, а не «уже взят»: игроку
  # важно, сколько ещё осталось, а не то, что он вообще его брал.
  #
  # ⚠️ Числу здесь оставлена та же единственная форма «раз», что и в оригинале,
  # а не `ngettext`: у оригинала не было деклонации по `n` вовсе (слово
  # «раз» совпадает у форм 1 и 5+, а данные сегодня не дают ни одного `n`
  # в форме 2–4), так что честная замена — интерполяция в одну форму, а не
  # додуманная тремя формами грамматика, которой в исходнике не было.
  def reason({:max_takes, _feat, n}, _ruleset),
    do: gettext("cannot take more than %{n} times", n: n)

  # Не то же, что `requires_skill_ranks`: там ранги нужны в НАЗВАННОМ навыке,
  # здесь — в том, который игрок выбирает этим же фитом. `Epic skill focus`
  # раньше проходил проверку «любой один навык с 20 рангами», то есть его можно
  # было взять на навык с нулём вложений.
  def reason({:requires_chosen_skill_ranks, skill, n}, ruleset),
    do:
      gettext("requires %{n} r. in the chosen skill (%{skill})",
        n: n,
        skill: skill_name(ruleset, skill)
      )

  # ⚠️ Называет РАЗРЕШЁННЫЕ классы, а не запрещённый, и это не вкус: ограничение
  # висит на выбранном значении, поэтому «на уровне Fighter не выбрать» было бы
  # неправдой — тот же фит на том же уровне берётся с другим навыком. Игроку
  # нужен ответ «на чьём уровне это брать», и он же единственный, который у нас
  # есть: источник пишет положительный список.
  def reason({:requires_leveling_as, classes}, ruleset),
    do:
      gettext("only at a level of %{classes}",
        classes: Enum.map_join(classes, " / ", &class_name(ruleset, &1))
      )

  # ⚠️ Соседняя форма и НЕ то же самое: та про уровень, эта про слот. Отказ висит
  # на паре «слот + значение», поэтому формулировка обязана назвать и слот
  # («бонус Rogue» — так он подписан в чипах и в дельте), и то, что дело
  # в значении: с другим навыком тот же слот его примет, а этот навык примет
  # общий слот того же уровня. Без второй половины строка читалась бы как
  # «фит вору недоступен», что неправда.
  def reason({:not_in_class_bonus_slot, class}, ruleset),
    do:
      gettext("this value cannot go into the %{class} bonus — needs a general slot",
        class: class_name(ruleset, class)
      )

  def reason({:missing_data, {:class_requirements, _class}}, _ruleset),
    do: gettext("requirements are not parsed from the wiki")

  def reason({:missing_data, {:alignment_restriction, _class}}, _ruleset),
    do: gettext("the alignment restriction is not parsed")

  def reason({:missing_data, :alignment_requirement}, _ruleset),
    do: gettext("the alignment requirement is not parsed")

  def reason({:missing_data, :max_classes}, _ruleset),
    do: gettext("the class limit is not set in the data")

  def reason({:unknown_class, _class}, _ruleset), do: gettext("the class is not in the data")

  # Требование ссылается на фит, которого у нас нет вовсе — `shades` ассасина
  # есть на Сиале и отсутствует в ванильном словаре. Это не «требование не
  # выполнено», а «проверить нечем», и формулировка обязана это различать.
  def reason({:unknown_feat, _feat}, _ruleset),
    do: gettext("the required feat is not in the reference data")

  # Требование есть, прочитать его нечем — три соседние формы, и все три раньше
  # печатались через `inspect/1` в списке выбора фитов: подпись была только
  # у гэпа, а у причины отказа нет.
  def reason({:missing_data, {:feat_prerequisites, feat}}, ruleset),
    do:
      gettext("%{feat}'s requirements are prose — we did not check them",
        feat: feat_name(ruleset, feat)
      )

  def reason({:missing_data, {:caster_level, n}}, _ruleset),
    do: gettext("requires caster level %{n}, which we do not compute", n: n)

  def reason({:missing_data, {:prerequisite, field}}, _ruleset),
    do: gettext("requirement «%{field}» cannot be read by machine", field: field)

  # Вторая половина «умеет накладывать заклинания N круга»: класс кастует, а от
  # какой характеристики — не сказано ни на одной вики. Это не отказ по существу,
  # и формулировка обязана это показывать.
  def reason({:missing_data, {:casting_ability, class}}, ruleset),
    do:
      gettext("class %{class}'s casting ability is not named anywhere",
        class: class_name(ruleset, class)
      )

  def reason({:missing_data, {:caster_advancement, class}}, ruleset),
    do:
      gettext(
        "%{class} advances a slot table, but whose is not determined: two casters at the same level",
        class: class_name(ruleset, class)
      )

  # Named, because this reason is read where the feat is *not* on screen: a
  # prestige class asking for a feat the shard switched off can never be
  # unlocked, and «отключён на Сиале» alone would not say which feat that was.
  # The feat picker has its own shorter wording — see `Builder.Feats.reason/2`.
  def reason({:feat_disabled, feat}, ruleset),
    do: gettext("feat %{feat} is disabled on Siala", feat: feat_name(ruleset, feat))

  # ⚠️ «На уровне этого класса», а не «этому классу нельзя»: запрет привязан
  # к уровню, а не к персонажу. Тот же фит берётся на уровне другого класса,
  # и уже взятый на законном уровне никуда не девается — формулировка обязана
  # звать игрока сменить УРОВЕНЬ выбора, а не считать фит недостижимым.
  def reason({:forbidden_by_class, class}, ruleset),
    do: gettext("cannot choose this feat at a %{class} level", class: class_name(ruleset, class))

  # Третья форма того же семейства, и все три говорят РАЗНОЕ: `feat_disabled` —
  # «шард убрал фит совсем», `forbidden_by_class` — «не на уровне этого класса»,
  # а это — «не на чьём угодно уровне, фит приходит с предмета».
  #
  # ⚠️ Формулировка обязана назвать путь. Отказ без него читается как «в игре
  # такого нет», а фит есть и работает: объявить его в «Вещах» законно, и это
  # единственный способ, которым он вообще попадает в билд.
  def reason({:not_selectable_at_level_up, feat}, ruleset),
    do:
      gettext("%{feat} is not chosen on level-up — only from an item",
        feat: feat_name(ruleset, feat)
      )

  # Не отказ, а оговорка к РАЗРЕШЁННОМУ выбору (`Rules.feat_pick_caveats/3`):
  # фит уже есть с вещи, второй раз он не берётся, значит слот не меняет ни
  # одного числа. Запрещать нельзя — предмет снимается, слот нет, — а молчать
  # тем более: впустую потраченный слот ловим ровно для этого (CLAUDE.md §6).
  #
  # Именная формулировка; короткую, для строки, где имя фита уже стоит рядом,
  # держит `Builder.Feats.caveat_text/2`.
  def reason({:owned_from_gear, feat}, ruleset),
    do:
      gettext("%{feat} is already owned from an item — the slot adds nothing",
        feat: feat_name(ruleset, feat)
      )

  def reason(other, _ruleset), do: inspect(other)

  # Кого источник исключил из требований по сейву — **вопрос к ядру**, а не
  # список в вебе: `Rules.SaveBonuses` читает признак с записи разметки
  # (`feat_save_bonuses.json` → `bonuses[].prerequisite`), а `reason/2` выше
  # только зовёт его и оборачивает в слова. Снимут признак — короткая ветка
  # начнёт срабатывать всегда, и никакой правки в этом файле для этого
  # не понадобится.
  #
  # ⚠️ Печатается ВСЕГДА при непустом списке, а не только когда у этого билда
  # реально есть исключённый источник: `reason/2` статов не видит и не знает,
  # держит ли билд Luck of heroes. Условная подпись молчала бы ровно там, где
  # игрок её и ждёт, потому что появиться она могла бы только вместе со
  # статами, которых у этой функции нет.
  # ⚠️ Имя английское (CLAUDE.md §4) и берётся из ruleset'а, а не пишется здесь.
  # ⚠️ С 19.08.2026 (задача 3.57) вторая ветка звучит «…, без X», а не
  # «… и без X»: союз был рассчитан на предшествующее «без вещей», которое
  # решение Dan убрало из базовой строки — второе «без» осталось единственным.
  # Английский msgid читает это как "not counting %{excluded}" — русский
  # msgstr не обязан быть его дословным переводом (msgid ведь тоже не «переводит»
  # русский текст обратно), он обязан только звучать по-русски как «без X».

  @doc """
  How far a refusal is from being satisfied, for sorting "almost there" first.

  Alphabetical order is useless in a list of locked things; «не хватает 1» is a
  hint to act on (CLAUDE.md §6). Reasons with no numeric distance sort last.
  """
  @spec distance(term(), map()) :: integer()
  def distance({:requires_bab, bab}, stats), do: max(bab - stats.base_attack, 1)

  def distance({:requires_character_level, level}, stats),
    do: max(level - stats.character_level, 1)

  # ⚠️ Считается от `abilities_naked`, а не от того, что в листе: с 16.08.2026
  # требование стоит на базовом значении (`GAME_CHECKS.md` S1), и расстояние
  # обязано мериться до той же черты. От одетого значения билд с поясом `+12`
  # вечно оказывался бы «не хватает 1» и стоял бы первым среди недоступных —
  # то есть сортировка «почти дотянулся» показывала бы ровно те фиты, до
  # которых дальше всего.
  def distance({:requires_ability, id, n}, stats),
    do: max(n - Map.get(stats.abilities_naked, id, 0), 1)

  def distance({:requires_class_level, class, n}, stats),
    do: max(n - Map.get(stats.class_levels, class, 0), 1)

  def distance({:requires_epic_level, level}, stats), do: max(level - stats.character_level, 1)

  # Сейв мы считаем, значит расстояние настоящее, а не «прочее»: «не хватает 2»
  # — подсказка к действию, ради которой сортировка по близости и заведена.
  #
  # ⚠️ От `saves_for_prereqs`, а не от того, что в листе: с 16.08.2026 требование
  # стоит на сейве без вещей (`GAME_CHECKS.md` S2), а с 17.08.2026 — ещё и без
  # прибавок, исключённых источником (S3). Мерить расстояние надо до той же
  # черты, до какой его меряет правило: иначе билд с вещами `+20` вечно
  # оказывался бы «не хватает 1» и стоял бы первым среди недоступных, то есть
  # сортировка «почти дотянулся» показывала бы ровно те фиты, до которых дальше
  # всего. Та же правка, что у `{:requires_ability, …}` выше, и по той же
  # причине.
  #
  # ⚠️ Соседнее `saves_naked` сюда не годится, хотя и выглядит подходящим:
  # у билда с `Luck of heroes` оно на единицу больше того, что засчитает
  # требование, и расстояние вышло бы короче настоящего — то есть подсказка
  # «не хватает 1» врала бы там же, где врал сам отказ до правки S3.
  #
  # ⚠️ А вот ПО МОМЕНТУ расстояние с 17.08.2026 меряется не совсем до той же
  # черты, что отказ (S6): отказ смотрит на сейв **на входе** в уровень, а здесь
  # берётся сейв этого уровня. Расходятся они ровно на базовую прогрессию сейва
  # этого уровня — прибавка характеристики с уточнением S7b стоит по обе стороны
  # и разницы не даёт, — то есть на 0 или 1. Ошибка односторонняя, а величина
  # всё равно зажата снизу единицей: видно её только как «не хватает 1» вместо
  # «не хватает 2». Считать точно значило бы второй полный `Rules.compute/2`
  # на каждую строку списка из 310 записей ради ключа СОРТИРОВКИ; названо,
  # а не сделано.
  def distance({:requires_save_bonus, save, n}, stats),
    do: max(n - Map.get(stats.saves_for_prereqs, save, 0), 1)

  # Ближе всех своих веток: дизъюнкцию закрывает самая дешёвая из них, а не все.
  # Внутри ветки — наоборот, максимум: ветка это конъюнкция, и закрыта она не
  # раньше, чем закрыто самое далёкое её требование.
  def distance({:requires_any_of, branches}, stats),
    do: branches |> Enum.map(&branch_distance(&1, stats)) |> Enum.min(fn -> 90 end)

  def distance({:requires_skill_ranks, _skill, _n}, _stats), do: 20

  # Ровно как `requires_feat`, потому что это оно и есть: причина вытесняет
  # `{:requires_feat, …}` из строки (см. `Builder.Feats.drop_restated/1`), и если
  # бы расстояние отличалось, фит переезжал бы в списке недоступных при том, что
  # не хватает ему того же самого.
  def distance({:choice_requires, _feat, _required, _domain}, _stats), do: 30

  # Дороже конкретного навыка: тот докупается ранг за рангом, а этот требует
  # выбрать, КАКОЙ навык качать до 20 — решение, а не добор.
  def distance({:requires_any_skill_ranks, _n}, _stats), do: 25
  def distance({:requires_feat, _feat}, _stats), do: 30

  # Ровно как `requires_feat`, и по той же причине, что у `choice_requires`
  # выше: не хватает того же самого — слота под фит, — просто взят он не на то
  # значение. Другое число двигало бы строку в списке недоступных при том, что
  # цена одна и та же.
  def distance({:requires_feat_choice, _feat, _values}, _stats), do: 30

  # Ровно как `requires_feat_choice` рядом и по той же причине: не хватает
  # того же самого слота под фит, просто взят он на значение не с тем свойством.
  def distance({:requires_feat_choice_property, _feat, _property, _value}, _stats), do: 30

  # И третья форма про значение — тем же числом и по тому же доводу: цена
  # одна и та же, слот под фит, просто взят он на не засчитываемое значение.
  def distance({:requires_feat_choice_other_than, _feat, _values}, _stats), do: 30

  # Дальний конец, но НЕ дно: ничто на этом уровне запрет не снимет, поэтому
  # «почти дотянулся» здесь неправда, — и всё же уровень другого класса его
  # снимает, поэтому это не `feat_disabled`, у которого дна нет вовсе.
  # Значение совпадает с общим хвостом намеренно: решение записано, а не выбрано.
  def distance({:forbidden_by_class, _class}, _stats), do: 90

  # Рядом с `forbidden_by_class` и по той же причине: уровень другого класса
  # запрет снимает, значит это не дно, — а «почти дотянулся» здесь неправда.
  def distance({:requires_leveling_as, _classes}, _stats), do: 90

  # Тот же дальний конец, и число совпадает с хвостом намеренно — решение
  # записано, а не выбрано по умолчанию. Ближе быть не может: запрет снимается
  # не добором чего-либо, а другим слотом; дном тоже не является — другой слот
  # на том же уровне пару принимает.
  def distance({:not_in_class_bonus_slot, _class}, _stats), do: 90
  def distance(_other, _stats), do: 90

  # Обе половины дизъюнкции терпят и старую плоскую форму, и ветку списком:
  # ветку отдаёт ядро, плоскую пишут вручную в тестах и в вызовах из веб-слоя.
  #
  # ⚠️ Тот же разделитель, что у `choice_requires` выше — каждый элемент уже
  # целое переведённое предложение (`reason/2`), соединяет их только служебное
  # слово, и это не сцепленная строка в смысле module doc: порядок и пунктуация
  # внутри каждого предложения не меняются оттого, что их несколько.
  defp branch_reason(branch, ruleset) when is_list(branch),
    do: Enum.map_join(branch, gettext(" and "), &reason(&1, ruleset))

  defp branch_reason(single, ruleset), do: reason(single, ruleset)

  defp branch_distance(branch, stats) when is_list(branch),
    do: branch |> Enum.map(&distance(&1, stats)) |> Enum.max(fn -> 90 end)

  defp branch_distance(single, stats), do: distance(single, stats)

  @doc "An alignment requirement spec (`%{require: […]}`)."
  @spec alignment_spec(term()) :: String.t()
  def alignment_spec(%{} = spec) do
    [
      case Map.get(spec, :exact) do
        nil -> nil
        names -> Enum.map_join(names, " / ", &(Ids.alignment_name(word_atom(&1)) || &1))
      end,
      case Map.get(spec, :require, []) do
        [] ->
          nil

        words ->
          gettext("any %{words}",
            words: Enum.map_join(words, gettext(" and "), &String.capitalize/1)
          )
      end,
      case Map.get(spec, :forbid, []) do
        [] ->
          nil

        words ->
          gettext("not %{words}",
            words: Enum.map_join(words, gettext(" and not "), &String.capitalize/1)
          )
      end
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
    |> case do
      "" -> gettext("any")
      text -> text
    end
  end

  def alignment_spec(:any), do: gettext("any")
  def alignment_spec(other), do: inspect(other)

  # `exact` holds strings like "lawful_good"; turn one into the atom the
  # alignment list uses without ever creating a new atom.
  defp word_atom(name) do
    Enum.find_value(Ids.alignments(), fn {id, _} -> if Atom.to_string(id) == name, do: id end)
  end

  # --------------------------------------------------- ladder replay (1.3) --

  # Задача 1.3: какие формы `Rules.illegal_class_levels/2` и
  # `Rules.illegal_feats/2` стоит показать отметкой — на строке лестницы
  # конструктора и на строке гида экрана просмотра, теми же словами. Список
  # жил в `BuilderLive` до сих пор; переехал сюда, потому что у экрана
  # просмотра встал ТОТ ЖЕ вопрос по ТОЙ ЖЕ полноте состояния, и третья
  # ручная копия — это уже история бага 1.2 (`Prereqs.keys()` против
  # `@requirement_keys` загрузчика, два списка, расходящихся молча).
  #
  # Список ШИРОКИЙ, а не узкий, как у `Builder.Import.@ladder_reasons`: и
  # конструктор, и экран просмотра держат ПОЛНЫЙ билд (фиты в именованных
  # слотах, ранги по уровням, характеристики с учётом вещей) — оба читают
  # одну и ту же кодировку `Builder.Encoding`, ту же, что пишет конструктор.
  # У импорта состояние текстовое: он не читает блок `SKILLS` и не знает,
  # ляжет ли фит в слот, поэтому `:requires_feat` и `:requires_skill_ranks`
  # там по-прежнему исключены — не потому что не нужны, а потому что честно
  # проверить нечем (см. комментарий в `import.ex`, список там свой).
  #
  # `:missing_data` и его семья остаются СНАРУЖИ: «не смогли решить» — это
  # не то же самое, что «билд нарушает правило», и пометить уровень
  # нелегальным за неразобранное требование значило бы обменять ложную
  # легальность, ради которой всё затевалось, на ложную нелегальность
  # (HANDOFF, «контракт из двух половин»). `:level_cap`/`:max_classes` тоже
  # снаружи — свойства билда целиком; там, где решается НОВЫЙ уровень, они
  # уже показаны как причина отказа на карточке класса, а отмечать ими ещё
  # и каждый прошлый уровень значило бы повторить одну претензию сорок раз.
  @illegal_reasons [
    :class_level_cap,
    :requires_character_level,
    :max_character_level,
    :requires_race,
    :requires_alignment,
    :requires_feat,
    :requires_skill_ranks,
    :requires_any_skill_ranks,
    :requires_chosen_skill_ranks,
    :requires_bab,
    :requires_class_level,
    :requires_ability,
    :requires_save_bonus,
    :requires_spell_level,
    :requires_any_of,
    # ⚠️ Три головы «фит взят там, где его взять нельзя», добавлены 11.08.2026.
    # До этого их не было ни одной, и это была ЛОЖНАЯ ЛЕГАЛЬНОСТЬ НА ЭКРАНЕ —
    # ровно то, ради чего весь список и заведён. Замерено: билд «варвар 20 /
    # воин 4» с `Mighty rage`, взятым на 24-м (ВОИНСКОМ) уровне и со всеми
    # пререквизитами выполненными, давал `Rules.illegal_feats/2` →
    # `[{24, :general, :mighty_rage, {:forbidden_by_class, :fighter}}]`,
    # а `ladder_issues/2` → `%{}`. Уровень не помечался вовсе.
    #
    # Критерию списка все три отвечают: это нарушение НА КОНКРЕТНОМ УРОВНЕ,
    # а не свойство билда целиком (`:level_cap`/`:max_classes`) и не «не смогли
    # решить» (`:missing_data`). Незамеченным `:forbidden_by_class` оставался
    # долго: он держит 229 пар запрета со страниц классов, и ни одна не
    # доезжала до отметки ⚠ на прошлом уровне — только до отказа на карточке
    # при выборе НОВОГО.
    :forbidden_by_class,
    :requires_leveling_as,
    :not_in_class_bonus_slot,
    # ⚠️ Две головы «фит есть, но взят не на то значение», добавлены 25.08.2026
    # (задача 3.99). Вторая заведена этой задачей («weapon focus **in a melee
    # weapon**» у Мастера оружия и Чемпиона Торма), а ПЕРВАЯ жила без отметки
    # с задачи 3.72 — требование Тайного лучника к оружию фокуса отказывало
    # на карточке при выборе НОВОГО уровня и не помечало прошлый, если игрок
    # менял выбор оружия задним числом. Ровно та же форма ложной легальности,
    # что у `:forbidden_by_class` выше, и найдена она так же — по соседству
    # с правкой, а не отдельным заходом.
    :requires_feat_choice,
    :requires_feat_choice_property,
    # ⚠️ Пять голов слотовой бухгалтерии, добавлены 24.08.2026 (задача 3.84).
    # До этого `Rules.illegal_feats/2` их не отдавал вовсе — он спрашивал одни
    # пререквизиты, — и это была ЛОЖНАЯ ЛЕГАЛЬНОСТЬ РОВНО ТОГО ЖЕ ВИДА, что
    # `:forbidden_by_class` тремя строками выше. Нашёл Dan обычным
    # редактированием: поднял уровни, не заполняя фиты, взял `Blind fight`
    # на позднем уровне, потом вернулся к пустой строке на раннем и взял его
    # ещё раз. Лестница печатала `Blind fight ×2` у фита, который берётся
    # однажды, и не помечала ни одного уровня:
    # `Rules.illegal_feats/2` → `[]`, `ladder_issues/2` → `%{}`.
    #
    # Критерию списка все пять отвечают: нарушение НА КОНКРЕТНОМ УРОВНЕ (ядро
    # обвиняет ПОЗДНИЙ из двух — на раннем фит игре ещё предлагался), а не
    # свойство билда целиком, и не «не смогли решить». Шестая голова того же
    # семейства, `:requires_choice`, сюда не попадает и попасть не может:
    # ядро её у поставленного пика гасит само (`placed_pick_exemptions/1`) —
    # это про НАШУ запись, а не про персонажа.
    :already_taken,
    :choice_already_taken,
    :max_takes,
    :invalid_choice,
    :requires_same_choice
  ]

  defp illegal_reason?(reason), do: is_tuple(reason) and elem(reason, 0) in @illegal_reasons

  @doc """
  Replays `build`'s own ladder against itself, right now, and words every
  offending level in Russian: `level => [text, …]`.

  One function for both web entry points that hold a full, decoded
  `Build.t()` — `BuildCalculatorWeb.BuilderLive` and
  `BuildCalculatorWeb.BuildViewLive` — so the whitelist above and the wording
  it drives exist exactly once. `BuildCalculatorWeb.Builder.Export` calls it
  too, for the same reason, to word its own footer note.
  `BuildCalculatorWeb.Builder.Import` does not: it replays text it parsed,
  not a decoded build, and keeps its own narrower list next to the code that
  needs it.

  Grouped by level, not by class or feat: a caller marks a ROW, and a level
  where both a class and a feat broke at once must not earn two marks
  answering the same question.

  ⚠️ **One exception to "a caller marks a row": an unset `build.alignment`.**
  Alignment never varies level to level, so `illegal_class_levels/2` (correctly
  replaying every level's requirement block, the same machinery a genuinely
  level-dependent BAB threshold needs) reports the identical `{:requires_alignment,
  spec}` on every level a class holds — a 35-level barbarian import (task 3.117;
  game-log imports never carry alignment, `{:alignment_unavailable}` already
  says so once, at import time) produced 35 identical rows reading "Barbarian:
  нужно не Lawful", text that accuses a choice nobody made. `alignment_notice/2`
  below collapses those to one line per affected class, worded "not chosen"
  rather than "needs not-X", pinned to level 1 — `go_to_level/2` treats levels 0
  and 1 as the same `active` (the unified race/alignment/class-1/stats editor),
  so the badge's own click already lands where the fix is. An alignment that
  *is* chosen and merely wrong for the class keeps the per-level replay as-is:
  that is a real, distinct violation on every one of those levels, not one fact
  repeated, and "нужно не X" is the correct thing to say about it.
  """
  @spec ladder_issues(map(), BuildCalculator.Rules.Build.t()) :: %{
          pos_integer() => [String.t()]
        }
  def ladder_issues(ruleset, build) do
    {alignment_reasons, class_reasons} =
      build
      |> BuildCalculator.Rules.illegal_class_levels(ruleset)
      |> Enum.filter(fn {_level, _class, reason} -> illegal_reason?(reason) end)
      |> Enum.split_with(&unselected_alignment_issue?(&1, build))

    class_issues =
      for {level, class, reason} <- class_reasons do
        {level, class_name(ruleset, class) <> ": " <> reason(reason, ruleset)}
      end

    feat_issues =
      for {level, _slot, feat, reason} <- BuildCalculator.Rules.illegal_feats(build, ruleset),
          illegal_reason?(reason) do
        {level, feat_name(ruleset, feat) <> ": " <> reason(reason, ruleset)}
      end

    (class_issues ++ alignment_notice(alignment_reasons, ruleset) ++ feat_issues)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {level, texts} -> {level, Enum.uniq(texts)} end)
  end

  defp unselected_alignment_issue?({_level, _class, {:requires_alignment, _spec}}, %{
         alignment: nil
       }),
       do: true

  defp unselected_alignment_issue?(_issue, _build), do: false

  # One line per affected class, not per occurrence — see the ⚠️ above
  # `ladder_issues/2`. `Enum.uniq_by` keeps the earliest level's tuple per
  # class, but the level it carries is discarded: every occurrence shares the
  # same `spec` (the class's own requirement block, unchanged level to level),
  # and the ONE line is pinned to level 1 regardless of which levels the class
  # actually occupies, so the click always reaches the alignment picker.
  defp alignment_notice(alignment_reasons, ruleset) do
    alignment_reasons
    |> Enum.uniq_by(fn {_level, class, _reason} -> class end)
    |> Enum.map(fn {_level, class, {:requires_alignment, spec}} ->
      {1, class_name(ruleset, class) <> ": " <> alignment_unset_reason(spec)}
    end)
  end

  defp alignment_unset_reason(spec),
    do: gettext("alignment not chosen yet (needs %{spec})", spec: alignment_spec(spec))

  @doc """
  Declension of the word "level" for a count: «1 уровень», «3 уровня», «5 уровней».

  ⚠️ **`ngettext/3`, not a hand-rolled `cond` — a genuine plural-form site**
  (task 3.83), unlike `max_takes`'s «раз» below, which never had per-count
  declension to preserve. Russian's three plural buckets (one / few / many)
  are exactly what `ru/LC_MESSAGES/default.po`'s `Plural-Forms` header already
  encodes (`n%10==1 && n%100!=11 ? 0 : n%10 in 2..4 && n%100 not in 12..14 ? 1
  : 2`) — word for word the same rule this `cond` used to hand-roll, so the
  rewrite is a straight port, not a new formula.

  The return contract is unchanged on purpose: callers (`BuilderLive`,
  `BuildViewLive`, `Builder.Export`) all build `"\#{n} " <> level_word(n)`
  themselves, so this still returns the bare declined word, never the count.
  `ngettext/3` supports that — nothing requires the msgid text to embed
  `%{count}`.
  """
  @spec level_word(integer()) :: String.t()
  def level_word(n) do
    ngettext("level", "levels", n)
  end

  # ------------------------------------------------------------------- gaps --

  @doc """
  A gap — from `stats.gaps`, `ruleset.gaps` or the web layer — in Russian.

  This is the honesty mechanism of the whole project (CLAUDE.md §9): what the
  core could not work out honestly comes back as a tuple instead of a
  plausible-looking number, and if the interface does not show it, the mechanism
  does not exist.
  """
  @spec gap(term(), map()) :: String.t()
  def gap({:missing_data, {:hit_die, class}}, ruleset),
    do:
      gettext("no hit die for %{class} — HP cannot be computed",
        class: class_name(ruleset, class)
      )

  def gap({:missing_data, {:class_progression, class, level}}, ruleset),
    do:
      gettext("no progression row for %{class} at level %{level}",
        class: class_name(ruleset, class),
        level: level
      )

  def gap({:missing_data, {:class_requirements, class}}, ruleset),
    do:
      gettext("%{class}'s requirements are prose, not parsed by machine",
        class: class_name(ruleset, class)
      )

  def gap({:missing_data, {:alignment_restriction, class}}, ruleset),
    do:
      gettext("%{class}'s alignment restriction is not parsed", class: class_name(ruleset, class))

  def gap({:missing_data, {:requirement, class, key}}, ruleset),
    do:
      gettext("the core cannot check requirement «%{key}» for %{class}",
        key: key,
        class: class_name(ruleset, class)
      )

  def gap({:missing_data, {:skill, skill}}, ruleset),
    do:
      gettext("skill %{skill} is mentioned by a class but is not in the reference data",
        skill: skill_name(ruleset, skill)
      )

  def gap({:missing_data, {:feat_prerequisites, feat}}, ruleset),
    do:
      gettext("feat %{feat}'s requirements are prose — we did not check them",
        feat: feat_name(ruleset, feat)
      )

  # --- фиты с выбором ---
  def gap({:missing_data, {:choice_domain, domain}}, _ruleset),
    do:
      gettext("no reference data for «%{domain}» — such feats' choices are not checked",
        domain: domain_name(domain)
      )

  def gap({:missing_data, {:feat_repeatable, feat}}, ruleset),
    do:
      gettext("whether %{feat} can be taken again is not parsed — assumed no",
        feat: feat_name(ruleset, feat)
      )

  # Страница называет потолок эффекта («to a maximum of 200 hit points»), а не
  # число взятий. Пересчитать одно в другое можно, только если она называет
  # и прибавку за раз; пока не названа — предела нет, и молчать об этом нельзя.
  def gap({:missing_data, {:feat_max_takes, feat}}, ruleset),
    do:
      gettext("how many times %{feat} can be taken is not derivable from the data",
        feat: feat_name(ruleset, feat)
      )

  # ⚠️ Отличается от `{:missing_data, {:feat_repeatable, …}}` тем, ЧЬЁ это
  # незнание. Там молчат данные; здесь факт есть, но он от игрока и помечен
  # ненадёжным — у `resist_energy` это «я погуглил», а не игровое наблюдение.
  # Слить их в одну подпись значило бы потерять разницу между «не знаем» и
  # «знаем со слов, которые нечем перепроверить».
  def gap({:assumed, {:feat_repeatable, feat}}, ruleset),
    do:
      gettext("%{feat} can be taken again — from the player's word, the wiki does not say so",
        feat: feat_name(ruleset, feat)
      )

  def gap({:not_modelled, {:feat_bonus, feat}}, ruleset),
    do: gettext("%{feat}'s bonus is not added to the stats", feat: feat_name(ruleset, feat))

  # ⚠️ Отдельно от строки выше, и разница не косметическая: та про фит, чей
  # эффект не разобран вовсе, эта — про фит, у которого прибавка к КОНКРЕТНОМУ
  # навыку названа на странице, но взять её в число нельзя (условие на местность,
  # выбор игрока, отсутствующее число). Слить их значило бы потерять то, что
  # известно: какой именно навык недосчитан.
  def gap({:not_modelled, {:feat_skill_bonus, feat}}, ruleset),
    do:
      gettext("%{feat}'s skill bonus is not counted — it is conditional",
        feat: feat_name(ruleset, feat)
      )

  # ⚠️ Отдельно от двух строк выше, и снова не косметически: HP — одно
  # конкретное число на экране, и эта строка говорит, чего именно ему не
  # хватает. Сами прибавки Toughness и Epic toughness с задачи 1.9 считаются
  # и названы в разборе; сюда попадает только то, что честно посчитать нельзя.
  # ⚠️ Здесь стояли два примера — «ступени по уровню класса у Deathless vigor,
  # растущий хит-дайс у РДД», — и оба устарели: первый посчитан замером D1
  # (13.08.2026), второй перестал быть прибавкой фита вовсе (задача 3.37,
  # 16.08.2026 — дайс лежит у класса). Сегодня подпись не печатается ни на
  # одном билде, и это свойство ДАННЫХ, а не кода: заведут запись
  # с вердиктом `not_modelled` — строка вернётся.
  def gap({:not_modelled, {:feat_hp_bonus, feat}}, ruleset),
    do: gettext("%{feat}'s HP bonus is not counted", feat: feat_name(ruleset, feat))

  # ⚠️ Про фит с вещи — и НЕ про его прибавку: она считается, как у любого
  # другого фита (`Rules.GearFeats`). Речь о параметре: вещь не говорит, с чем
  # именно фит взят, и следствие у этого своё и видимое — `Greater spell focus`
  # не предложит школу, хотя `Spell focus` у персонажа есть.
  def gap({:not_modelled, {:gear_feat_choice, feat}}, ruleset),
    do:
      gettext("%{feat} from an item: the item does not say what it was taken with",
        feat: feat_name(ruleset, feat)
      )

  # ⚠️ Две строки про оружие в руках (задача 3.5, часть B), и ни одна не про
  # число: число игрок вписал сам. Обе — про утверждение, которого никто
  # не сделал. ⚠️ Третьей была «бонус атаки и усиление складываем, а страницы
  # про это нет ни на одной вики»; задача 3.52 оставила предмету ОДНО число,
  # и складывать стало нечего — вопрос исчез, а не остался без ответа.
  #
  # Первая: категорию владения этому оружию назначили МЫ. Сиала заменила
  # ванильную систему владения пятью своими и перечисляет их состав только
  # по-русски прозой.
  #
  # ✅ **В данных на этой форме больше нет ни одной записи** (Dan сверил перевод
  # имён 16.08.2026). ⚠️ Здесь стояло «поэтому у 31 назначения из 47 статус
  # `assumed`» — устарело в тот же день. Строка остаётся живой формой, а не
  # мёртвым кодом: шард добавит оружие, которого нет в сводной таблице
  # «Система оружия», и оговорка вернётся сама. Держится тестом
  # `gear_weapon_test.exs` («механизм оговорки жив») на копии `priv/rules`.
  def gap({:assumed, {:weapon_proficiency_group, weapon, _group}}, ruleset),
    do:
      gettext(
        "which proficiency group %{weapon} belongs to is not stated on the Siala wiki — we assigned it ourselves",
        weapon: weapon_name(ruleset, weapon)
      )

  # Вторая: требования не написал никто. ⚠️ Это НЕ то же, что «владения не
  # требует» (посох): там ответ известен, здесь его нет, и оружие всё равно
  # предлагается — запретить значило бы выдумать запрет, а промолчать — выдумать
  # разрешение.
  def gap({:missing_data, {:weapon_proficiency, weapon}}, ruleset),
    do:
      gettext(
        "whether %{weapon} requires a proficiency feat is not stated on any wiki — we offer it, but do not check it",
        weapon: weapon_name(ruleset, weapon)
      )

  # Задача 3.43, и обе строки про ХВАТ — то есть про то, свободна ли вторая рука
  # под щит. Первая: у этого оружия хвата не называет ни Сиала (его нет в её
  # таблице), ни Fandom (у него нет размера), поэтому вывести двуручность не из
  # чего. Печатается только рядом с надетым щитом: там это решает число.
  def gap({:missing_data, {:weapon_grip, weapon}}, ruleset),
    do:
      gettext(
        "whether %{weapon} is one- or two-handed is not stated anywhere — a shield next to it is counted as entered",
        weapon: weapon_name(ruleset, weapon)
      )

  # Вторая: снапшот вовсе не назвал лестницу размеров, а без неё «на категорию
  # крупнее владельца» посчитать нечем. Ни один поставляемый ruleset этого не
  # производит — на полу-объявленном правиле сборка падает.
  def gap({:missing_data, :weapon_size_rules}, _ruleset),
    do:
      gettext(
        "weapon and race sizes are not described in the data — two-handedness and small-race bans are not checked"
      )

  # ⚠️ Четыре строки про AC, и они отвечают на четыре разных вопроса — слить
  # их значило бы потерять, чего именно не хватает числу на экране.
  #
  # Первая: умение AC даёт, но включается режимом, способностью или песней,
  # либо работает против одного вида врагов. Постоянного числа у него нет,
  # поэтому в «Итого» оно не идёт — но называется поимённо.
  def gap({:not_modelled, {:ac_bonus, id}}, ruleset),
    do:
      gettext("%{source}'s AC bonus is not counted — it is conditional",
        source: ac_bonus_name(ruleset, id)
      )

  # Вторая: прибавка ПОСЧИТАНА, но в игре пропадает при условии, которое ядро
  # проверить не может. Прецедент Spellcraft: показываем как есть, оговорку
  # печатаем.
  #
  # ⚠️ Подпись переписана 09.08.2026 и обязана остаться общей. Здесь стояло
  # «пропадает в доспехах и со щитом» — ровно условие монаха, — а оно с этого дня
  # ПРОВЕРЯЕТСЯ (замер Dan: ломает не вид надетого, а то, даёт ли оно AC), значит
  # эта форма про монаха больше не приходит вовсе. Оставить прежний текст значило
  # бы, что следующая непроверяемая оговорка — верхом, в режиме, против одного
  # врага — напечаталась бы как «в доспехах и со щитом», то есть соврала бы
  # уверенно и мимо темы.
  def gap({:not_modelled, {:ac_bonus_scope, id}}, ruleset),
    do:
      gettext("%{source}: the AC bonus is counted, but we do not check its condition",
        source: ac_bonus_name(ruleset, id)
      )

  # То же самое, но про сами характеристики (задача 3.1): ярость, стойка,
  # право сотворить заклинание. Формулировка «пока идёт» вместо «условная»
  # намеренно — у AC условие про обстановку («против великанов», «в режиме»),
  # здесь про время: умение включается на несколько раундов.
  def gap({:not_modelled, {:ability_bonus, id}}, ruleset),
    do:
      gettext(
        "%{source}'s ability score bonus is not counted — it only applies while the ability is active",
        source: ac_bonus_name(ruleset, id)
      )

  # То же самое, но про сейвы (задача 1.12a): ярость, активируемая стойка,
  # прибавка, работающая только против одной угрозы (яда, страха, выбранной
  # школы магии). Формулировка объединяет оба случая одной фразой намеренно —
  # деление «пока идёт умение» / «против не всего» уже видно в самих данных
  # (`vanilla/feat_save_bonuses.json` → why у конкретной записи), а здесь
  # игроку важнее сам факт «не в числе», чем причина.
  def gap({:not_modelled, {:save_bonus, id}}, ruleset),
    do:
      gettext(
        "%{source}'s saving throw bonus is not counted — it is not always on and not against everything",
        source: ac_bonus_name(ruleset, id)
      )

  # И про атаку (задача 1.12b) — ДВЕ строки про прибавку, потому что у атаки два
  # разных «не считаем», и разница видна игроку. Третья, ниже, не про прибавку
  # вовсе, а про характеристику, от которой считается бросок.
  #
  # Первая — то же, что у трёх статов выше: боевой режим, разовое умение,
  # прибавка против одного вида врагов или в одной местности.
  def gap({:not_modelled, {:attack_bonus, id}}, ruleset),
    do:
      gettext(
        "%{source}'s attack bonus is not counted — it is not permanent (a mode, a one-time ability or a narrow target)",
        source: ac_bonus_name(ruleset, id)
      )

  # Вторая — про оружие, и с задачи 3.5 (часть B) она про ЭТОТ БИЛД, а не про
  # калькулятор: оружие моделируется, прибавка считается, когда оно совпало
  # с выбором фита. Строка остаётся ровно для трёх состояний, в которых сказать
  # нечего: оружие в вещах не назвали; выбор фита не записан (фит пришёл с вещи
  # или выдан классом); фокусов несколько, и какой из них эпический — неизвестно.
  #
  # ⚠️ Здесь стояло «пока не считаем … оружие мы не моделируем» — после этой
  # задачи неправда, и хуже, чем неправда: игрок, вписавший оружие, прочитал бы,
  # что его ввод ничего не изменил. Число в подписи оставлено намеренно: игрок
  # может прибавить его сам.
  def gap({:not_modelled, {:attack_bonus_weapon, id}}, ruleset),
    do:
      gettext(
        "the attack bonus from %{source}%{amount} is not counted: it only works with a specific weapon, and which one is in hand is not stated",
        source: ac_bonus_name(ruleset, id),
        amount: attack_bonus_amount(ruleset, id)
      )

  # И третья строка про атаку — про ХАРАКТЕРИСТИКУ, а не про прибавку (`Zen
  # archery`, 14.08.2026): фит переключает бросок атаки на мудрость, но только
  # с дальнобойным оружием в руках. Оружие не названо — правило не применяем,
  # и это единственное, чего билду не хватает; строка прямо говорит, что делать.
  #
  # ⚠️ Требование берётся из самого правила (`ruleset.attack_ability`), а не
  # зашито здесь словом «дальнобойное»: сегодня свойство одно, и веб-слой не то
  # место, где заводить второе.
  def gap({:not_modelled, {:attack_ability_weapon, id}}, ruleset),
    do:
      gettext(
        "%{source}: not applying attack from %{ability} — needs %{weapon_property} in hand, and no weapon is chosen in «Items»",
        source: ac_bonus_name(ruleset, id),
        ability: attack_ability_of(ruleset, id),
        weapon_property: attack_ability_weapon_ru(ruleset, id)
      )

  # И четвёртая — про ту же несказанную вещь, но на уровень ниже фитов (задача
  # 3.34): от какой характеристики бросок атаки считается ИЗНАЧАЛЬНО, решает
  # оружие в руках, а билд его не назвал. Обе характеристики и обе стороны
  # берутся из ruleset'а — здесь не названо ни одной.
  #
  # ⚠️ Строка обязана называть посчитанное, а не только непосчитанное: игрок,
  # прочитавший «атаку от ловкости не применяем», не узнает, что у него на
  # экране число ближнего боя, — а оно может быть и БОЛЬШЕ настоящего.
  # ⚠️ «Оружия в руках у билда нет», а не «не выбрано в „Вещах“»: выбранное,
  # но недоступное по владению оружие в руки не идёт тоже (`GearWeapon.held/2`),
  # и про него у экрана есть своя строка — отказ с причиной.
  def gap({:not_modelled, {:attack_ability_default, property}}, ruleset),
    do:
      gettext(
        "the weapon in hand decides the attack roll's ability, and the build has none: melee is counted, from %{default_ability} — %{weapon_property} would count from %{weapon_ability}",
        default_ability: ability(attack_ability_default(ruleset)),
        weapon_property: weapon_property_ru(property),
        weapon_ability: ability(attack_ability_default(ruleset, property))
      )

  # Третья: у части посчитанных прибавок источник не назвал ТИП бонуса. Значит
  # мы их ни с чем не сталкиваем и не режем потолком уклонения.
  def gap({:assumed, :ac_bonus_types_unstated}, _ruleset),
    do:
      gettext(
        "some AC bonuses' type is not named on the wiki — we assume they stack with everything"
      )

  # Четвёртая: на этом типе вписанное игроком число столкнулось с собственной
  # прибавкой билда, и правило применено — берётся большее (задача 3.39).
  # ⚠️ Строка говорит не про правило, а про то, чего правило НЕ может: база
  # предмета (щит 1/2/3) складывается всегда, а из одного введённого числа её
  # не вычесть. То есть наше число может быть занижено ровно на неё, и молчать
  # об этом нельзя. ⚠️ Здесь стояло «две прибавки к AC одного типа сложены —
  # в игре одинаковые типы не складываются»: это про снятую оговорку, а не про
  # эту, и повторять её было бы неправдой в обе стороны сразу.
  def gap({:not_modelled, {:ac_gear_base, type}}, ruleset),
    do:
      gettext(
        "%{type}: what is entered for items does not stack with the build's own bonus, the larger wins — but an item's own base always stacks and cannot be separated from the entered number, so AC may be underestimated by it",
        type: ac_type(ruleset, type)
      )

  # ⚠️ Это допущение, а не правило: у семейства focus источник говорит «можно,
  # но эффекты не складываются», а у `Epic energy resistance` — наоборот, повтор
  # по тому же типу урона законен и копится до 100. Пока данные не сказали
  # `distinct` явно, ядро запрещает повтор с тем же значением, и это надо
  # называть вслух, а не выдавать за прочитанное правило.
  def gap({:assumed, :repeatable_choices_must_differ}, _ruleset),
    do:
      gettext("we assume a repeated choice must differ — the wiki does not say so for every feat")

  def gap({:missing_data, :max_classes}, _ruleset),
    do: gettext("the class limit is not set in the data")

  # «Дух Сиалы» (task, волна 12, 09.08.2026) — сторож для siala_41, а не
  # копия соседнего: у лимита классов гэп стоит и на ванили (открытый
  # вопрос), а здесь nil на ванили — подтверждённый факт («такой механики в
  # NWN1 нет»), не гэп вовсе. Строка ниже видна только если факт сломан
  # ИМЕННО под siala_41, где он обязан быть verified.
  def gap({:missing_data, :innate_hp_bonus}, _ruleset),
    do:
      gettext(
        "«Spirit of Siala» (+20 HP for every character) is not set in the data — not counted"
      )

  def gap({:missing_data, :alignment_requirement}, _ruleset),
    do: gettext("the alignment requirement is written as prose outside the dictionary")

  def gap({:missing_file, file}, _ruleset), do: gettext("no data file %{file}", file: file)

  def gap({:missing_data, {:stat_cap, :max_skill_value}}, _ruleset),
    do:
      gettext(
        "the skill value ceiling of 127 is not derived into a rule from the wiki — not applied"
      )

  def gap({:missing_data, {:stat_cap, :ac}}, _ruleset),
    do: gettext("no source names an AC ceiling of its own — not limited")

  def gap({:missing_data, {:stat_cap, stat}}, _ruleset),
    do:
      gettext("ceiling «%{stat}» is not set in the data — the number is not limited", stat: stat)

  def gap({:missing_data, :spell_lists}, _ruleset),
    do: gettext("which spell list each class reads from is not set")

  def gap({:missing_data, :attack_ability_rules}, _ruleset),
    do: gettext("feats that change the attack formula are not described in the data")

  def gap({:missing_data, :point_buy_costs}, _ruleset),
    do: gettext("point-buy prices are not set in the data")

  # ⚠️ Строка сменилась 03.08.2026 вместе с правилом: минимум измерен в игре
  # и применяется, поэтому гэп теперь значит «этот ruleset правила не несёт»
  # (`vanilla` не имеет overrides.json вовсе), а не «мы не знаем правила».
  # Продолжать печатать «не применяем» про применённое запрещено (CLAUDE.md §6).
  def gap({:missing_data, :caster_minimum_ability}, _ruleset),
    do:
      gettext(
        "the caster's key ability minimum is not set in the data — point-buy has no floor, and a caster will end up several points above what the game gives"
      )

  # ⚠️ Не путать с соседом сверху: тот про поинт-бай («сколько очков осталось»),
  # этот — про сам каст («хватает ли характеристики на круг»). Формулировки
  # разведены нарочно, иначе два разных пробела читаются как повтор.
  def gap({:missing_data, :casting_ability_minimum}, _ruleset),
    do:
      gettext(
        "the ability minimum for a spell circle (10 + circle) is not set in the data — we only check whether the class table grants slots of that circle"
      )

  # ⚠️ Не про «сколько нужно характеристики», а про то, КОМУ этот минимум
  # вообще задают: спонтанному кастеру (Бард, Соркерер) требование фита его
  # не задаёт вовсе. Без записи исключение не достаётся никому, то есть бард
  # получает отказ там, где игра фит даёт.
  def gap({:missing_data, :spontaneous_casters}, _ruleset),
    do:
      gettext(
        "the data does not say which casters are spontaneous — a Bard or a Sorcerer will be refused a metamagic feat the game does hand him"
      )

  def gap({:missing_data, {:casting_ability, class}}, ruleset),
    do:
      gettext(
        "class %{class} has spell slots, but its casting ability is not named anywhere — we do not check the second half of the requirement",
        class: class_name(ruleset, class)
      )

  def gap({:missing_data, {:caster_advancement, class}}, ruleset),
    do:
      gettext(
        "%{class} advances someone else's slot table, but whose exactly is not determined: two casters at the same level, and the source says «highest»",
        class: class_name(ruleset, class)
      )

  # ⚠️ Не «мы не досмотрели», а «источник говорит одно, а печатает другое».
  # Строка обязана называть обе стороны: иначе игрок прочитает её как нашу
  # недоработку и не поймёт, что отказ может быть ложным.
  def gap({:not_modelled, {:caster_advancement, :epic_spell_access}}, _ruleset),
    do:
      gettext(
        "epic spells carry a different requirement in Fandom's notes than in the requirement line itself: «an epic cleric/druid/sorcerer/wizard or 15 levels of Pale Master». The schema expresses only half of it, so we check what is printed — a refusal on circle 9 for a build with Pale Master may be false"
      )

  def gap({:not_modelled, {:caster_advancement, what}}, _ruleset),
    do:
      gettext("casting advancement rule «%{what}» is recorded in the data but not applied",
        what: what
      )

  # ⚠️ Здесь стояла подпись к `{:not_modelled, :cleric_domains}` — «выбор двух
  # доменов клирика записывается и виден в прогрессии, но их особые способности
  # и добавленные заклинания в расчёт не идут». Снята 22.08.2026 вместе с самой
  # формой (задача 3.79, решение Dan): ни одна из трёх частей пробела до нашего
  # ответа не доезжает — активные умения доменов баффы, пассивные калькулятор
  # не считает вовсе, а заклинания домена выдаются автоматически, то есть
  # выбирать нечего. ⚠️ Выбор двух доменов при этом на месте и виден в лестнице
  # ровно как раньше — ушла строка признания, а не механика.

  # ⚠️ Здесь стояла подпись к `{:not_modelled, :wizard_opposed_school}` —
  # «специализация волшебника даёт +1 слот на круг (считаем), но запрет каста
  # заклинаний противоположной школы, включая свитки, не проверяется». Снята
  # 24.08.2026 вместе с формой (задача 3.86, решение Dan): цена выбора теперь
  # НАЗВАНА в том месте, где выбор и делается, — на чипе школы
  # (`class_choice_value_note/3` ниже) стоит «закрывает Conjuration —
  # 27 заклинаний из 179». Признание сменилось ответом, а не молчанием.
  #
  # ⚠️ Хвост той подписи («в том числе для Spell Focus») снимался отдельно
  # и раньше, замером W1 (Dan, 24.08.2026): волшебник-некромант видит
  # `Spell Focus (Divination)` и берёт его — запрета в игре нет вовсе.
  # Две разные правки одного дня, и вторая не отменяет первую: сначала
  # выяснилось, что часть признания была выдумкой, потом — что остаток
  # можно посчитать.

  # ⚠️ Здесь стояла подпись к `{:not_modelled, :bonus_spell_slots_from_ability}`
  # («бонусные слоты за высокую характеристику не считаем — таблицы в данных
  # нет»). Задача 3.70 таблицу принесла, слоты считаются, форма снята. Ниже —
  # то же утверждение, но проверяемое: оно печатается ровно тогда, когда
  # таблицы в данных и правда нет.
  def gap({:missing_data, :bonus_spell_slots}, _ruleset),
    do:
      gettext(
        "bonus slots for a high casting ability are not counted — the data has no «modifier → slots per circle» table"
      )

  # ⚠️ С задачи 3.1 этот гэп возникает только там, где нет разметки
  # (`vanilla/feat_ability_bonuses.json`) — на обоих рабочих ruleset'ах его
  # нет. Текст от этого не меняется: он описывает следствие («не входят в
  # число»), а оно верно ровно тогда, когда гэп есть.
  def gap({:not_modelled, :ability_bonus_feats_and_class}, _ruleset),
    do:
      gettext(
        "ability score bonuses from feats (Great strength and family) and from class abilities (Red Dragon Disciple) are not counted yet — they are not in the number below"
      )

  # Сопротивление заклинаниям (задача 3.45), первая из двух подписей: источник
  # SR, который персонаж держит, а модель считать отказывается. ⚠️ Сегодня
  # не печатается ни на одном билде — записей с вердиктом `not_modelled` в файле
  # разметки нет вовсе, — и это свойство ДАННЫХ, а не кода: та же ситуация, что
  # у прибавки к HP строкой выше.
  def gap({:not_modelled, {:spell_resistance, id}}, ruleset),
    do: gettext("%{source}'s SR bonus is not counted", source: ac_bonus_name(ruleset, id))

  # ⚠️ Подпись называет ПРАВИЛО, а не отсутствующее число, и это не стилистика.
  # У всех прочих статов вещь прибавляет, поэтому «вещи не посчитаны» читается
  # как «у тебя не меньше». У SR вещь не прибавляется, а конкурирует: в игре
  # засчитывается наибольший источник, и предмет шарда доходит до 28 при нашем 22
  # у монаха 12. Без второй половины фразы игрок сравнил бы наше число со своим
  # листом и счёл расхождение багом (задача 3.45).
  def gap({:not_modelled, :spell_resistance_from_gear}, _ruleset),
    do:
      gettext(
        "SR from items is not counted — and it does not stack with the monk's: the game counts the larger of the two"
      )

  # ⚠️ Здесь стояла подпись к `{:not_modelled, :armor_check_penalty}` — «штраф
  # брони к навыкам не считаем: он зависит от надетого доспеха». Снята
  # 16.08.2026 задачей 3.42 вместе с самой формой: доспех и щит стали предметами
  # (3.41), штраф считается и назван термом в разборе навыка. Оговорка про
  # посчитанное — та же ложь, что молчание про непосчитанное, только наоборот
  # (CLAUDE.md §6). То, что от штрафа может остаться неизвестным, — «отнимает ли
  # он у ЭТОГО навыка» — живёт формой
  # `{:missing_data, {:skill_armor_check_penalty, …}}` ниже и приходит от билда,
  # а не от ruleset'а. ⚠️ Единственным её адресатом была `Alchemy`, и 17.08.2026
  # Dan ответил «Штрафа нет» (кейс P1): подпись осталась ради следующего навыка
  # шарда, сегодня её не производит ни один ruleset.
  # ⚠️ Здесь стояла строка про `{:not_modelled, :zen_archery}` — «не применяем:
  # атака от WIS завязана на тип оружия, а оружие мы не моделируем». Снята
  # 14.08.2026 вместе с самой формой: правило заведено и применяется, а печатать
  # «не считаем» про посчитанное запрещено ровно так же прямо, как обратное
  # (CLAUDE.md §6). То, что у фита осталось непосчитанным, зависит от билда
  # и живёт формой `{:not_modelled, {:attack_ability_weapon, …}}` выше.
  # ⚠️ Подпись переписана 17.08.2026 вместе со смыслом формы (замер S10). Здесь
  # стояло «считаем, что оружие лёгкое — в игре рапира финессится не у всех
  # рас», и это была правда про КАЖДЫЙ билд с фитом. Теперь список оружия
  # и хват проверяются, и оговорка остаётся только там, где оружие не названо, —
  # значит и подпись обязана звать назвать его, а не пересказывать правило.
  # ⚠️ «Не задано», а не «не названо»: в это же состояние попадает билд,
  # назвавший оружие, которое персонаж держать не может, — там своя строка
  # с отказом, и вторая, спорящая с ней про «не названо», путала бы.
  def gap({:assumed, :finessable_weapon}, _ruleset),
    do:
      gettext(
        "Weapon Finesse: no weapon in hand is set — we assume it is suitable. Name a weapon in «Items», and we will check it against the list"
      )

  # ⚠️ Подпись НЕ переписана задачей 3.105, и это решение, а не забывчивость:
  # смысл оговорки не сдвинулся ни на слово. Она всегда значила «правило никто
  # не назвал, поэтому считаем от собственного интеллекта» — просто до
  # 25.08.2026 это было верно всегда, а теперь только на ruleset'е, у которого
  # нет записи `skill_points_gear_intelligence` (Dan назвал правило, оговорка
  # молчит). Ни `siala_41`, ни `vanilla` её сегодня не печатают.
  def gap({:assumed, :skill_points_ignore_gear_intelligence}, _ruleset),
    do:
      gettext(
        "skill points are counted from INT without items: we have no history of when it was worn"
      )

  def gap({:not_modelled, :spellcasting}, _ruleset),
    do: gettext("spells are not counted: the slot progression sits as raw wikitext")

  # ⚠️ Здесь стояла подпись к `{:missing_data, :racial_bonus_progression}` —
  # «расовый бонус Сиалы растёт с уровнем персонажа, а числа на вики есть только
  # для 40-го». Снята 22.08.2026 вместе с самой формой (задача 3.81, решение
  # Dan: «прогрессию делать не будем, данный пробел можно закрыть»).
  #
  # 🔴 **Это НЕ значит, что игрок перестал слышать про непосчитанный бонус.**
  # Подпись к `{:missing_data, {:racial_bonus_level, race}}` стоит ниже
  # и печатается каждому билду ниже 40-го. Ушла строка про полноту наших
  # ДАННЫХ («таблицы роста у нас нет»), осталась строка про конкретное ЧИСЛО
  # («бонус растёт с уровнем — точное число появится на 40-м»), и вторая
  # для игрока и есть та, что двигает его AB.

  # ⚠️ ЗДЕСЬ СТОЯЛА ПОДПИСЬ К `{:not_modelled, {:racial_bonus, race, kind}}` —
  # «бонус расы Гном (поглощение урона) в производные статы не идёт». Снята
  # задачей 3.38 (16.08.2026) вместе с самой формой: поглощения и урона
  # калькулятор не показывает вовсе, значит и дырки в ответе там нет
  # (CLAUDE.md §9; Dan: «мы это не показываем, оговорку игнорируем, не показываем
  # лишней информации»). Гном и Могучий человек молчат так же, как Гоблин
  # и Тёмный эльф, у которых бонуса нет вовсе.
  #
  # ⚠️ `racial_bonus_kind/1` при этом ЖИВ — его зовут разбор расового бонуса
  # и подпись оружейного (`weapon_type_bonus_kind/1`).

  # ⚠️ Строка называет УРОВЕНЬ, а не число, и это поправка Dan 15.08.2026.
  # Первая редакция предлагала назвать конечную величину («вырастет к 40-му
  # до +9») — соблазнительно и НЕВЕРНО: +9 это вариант воина Сагры, а сагровик
  # билд или нет, решает его ФИНАЛЬНЫЙ состав классов. На 25-м уровне чистый
  # воин сагровик, но один уровень барда на 30-м это отменяет, и обещание
  # оказалось бы враньём задним числом. Dan: «мы до 40/41 уровня не знаем,
  # сагровик это будет или нет».
  #
  # ⚠️ Отсюда же и то, чего строка НЕ делает: не называет ни одного из четырёх
  # чисел, даже базового. Назвать «+6» значило бы то же самое с другой стороны —
  # выдать пол за ответ. Уровень известен точно, число — нет; говорим то, что знаем.
  def gap({:missing_data, {:racial_bonus_level, race}}, ruleset),
    do:
      gettext("race %{race}'s bonus grows with level — the exact number will appear at level 40",
        race: race_ru(ruleset, race)
      )

  # ⚠️ И тут же справка про остальные варианты числа — она обязана стоять рядом
  # с посчитанным, а не вместо него: посчитанный вариант НЕ самый большой из
  # четырёх (два требуют оружия в руках), и «+9» без этой строки читается как вся
  # правда (задача 3.12, пересмотрено 08.08.2026).
  #
  # 🔴 **Гэпом сюда приезжает ровно ОДНА из трёх веток — `variant: nil`**
  # (задача 3.102, 25.08.2026). Две другие описывают УСПЕХ («посчитан базовый»,
  # «посчитан вариант сагровика»), а весь список гэпов билда печатается под
  # заголовком «ядро не смогло посчитать N» — то есть строка спорила с шапкой
  # над собой. Решение Dan: посчитанное переезжает справкой к самому числу
  # (`Summary.racial_bonus_note/2` → `racial_bonus_note/2` ниже), текст при этом
  # не переписан ни на букву — тот же `racial_bonus_variant_sentence/5`.
  #
  # ⚠️ Ветка остаётся принимать ЛЮБОЙ вариант, и это не мёртвый код: сторож
  # подписей ходит по `Rules.gap_forms/0`, а зарегистрированный там пример —
  # `{:assumed, {:racial_bonus_variant, :gnome, :base}}` (форма у всех трёх одна,
  # `Vocabulary.form/1` читает голову и подлежащее). Оставить ветку без слов
  # значило бы уронить сборку на первом же прогоне сторожа.
  def gap({:assumed, {:racial_bonus_variant, race, variant}}, ruleset),
    do: racial_bonus_variants_note(ruleset, race, variant)

  # ---- бонус за ТИП оружия в руках (задача 3.35) -----------------------------
  #
  # ⚠️ Та же система, что расовый бонус выше, и подписи обязаны это показывать:
  # игрок видит два числа по +9 и должен понять, что это не одно, посчитанное
  # дважды. Поэтому здесь везде говорится «за тип оружия», а там — «бонус расы».
  #
  # ⚠️ Первой здесь стояла подпись к `{:missing_data,
  # :weapon_type_bonus_progression}` — снята 22.08.2026 вместе с расовой
  # (задача 3.81, то же решение Dan и то же основание: это одна система,
  # и две разные фразы про её половины были бы хуже, чем ни одной).
  # 🔴 Подпись к `{:missing_data, {:weapon_type_bonus_level, weapon}}` ниже
  # жива — она и говорит игроку с луком, что его число не окончательное.

  # Оружие, которого нет в справочнике вовсе («Вилы»). Дырка не в числе, а в том,
  # что такой билд у нас не выразить: величину бонуса страница как раз называет.
  def gap({:missing_data, {:weapon_type_bonus_weapon, name}}, _ruleset),
    do:
      gettext(
        "weapon «%{name}» gives a bonus on Siala, but it is not in the weapon reference data — it cannot be chosen in «Items», so there is nothing to count the bonus on",
        name: name
      )

  # ⚠️ Тип бонуса назван, число — нет. Подставить сюда 6/9 клинкового оружия было
  # бы выдумкой: у двулезвийного меча тот же «Shield bonus» оказался явным
  # исключением со своим числом, то есть семейство неоднородно.
  def gap({:missing_data, {:weapon_type_bonus_amount, weapon, kind}}, ruleset),
    do:
      gettext(
        "%{weapon}: the page names the bonus «%{kind}», but not its amount — nothing to count, and a number cannot be borrowed from a similar weapon",
        weapon: weapon_name(ruleset, weapon),
        kind: weapon_type_bonus_kind(kind)
      )

  # ⚠️ Строка называет УРОВЕНЬ, а не число, и по той же причине, что у расового
  # бонуса: сагровик билд или нет, решает его финальный состав классов, поэтому
  # обещать «+9 на 40-м» до 40-го значило бы соврать задним числом.
  def gap({:missing_data, {:weapon_type_bonus_level, weapon}}, ruleset),
    do:
      gettext(
        "the weapon-type bonus (%{weapon}) grows with level — the exact number will appear at level 40",
        weapon: weapon_name(ruleset, weapon)
      )

  # Посчитано, и число варианта — наше чтение фразы, а не сама фраза.
  def gap({:assumed, {:weapon_type_bonus_variant, weapon, _variant}}, ruleset),
    do:
      gettext(
        "%{weapon}: «the bonus is not modified, it is the same for every build» — we read this as «for a Sagra warrior too», meaning there is no group's one-and-a-half bonus here. Checked in the game: a level 40 Sagra warrior with this weapon",
        weapon: weapon_name(ruleset, weapon)
      )

  # 🔴 Один и тот же вид бонуса пришёл из ОБЕИХ рук, и посчитан он один раз
  # (задача 3.132). Половина правила — цитата, половина — чтение, и подпись
  # обязана назвать именно вторую: складывать или не складывать здесь двигает
  # число на 6, а источник про две руки одной группы молчит.
  def gap({:assumed, {:weapon_type_bonus_both_hands, kind}}, _ruleset),
    do:
      gettext(
        "both weapons give the same bonus («%{kind}») — we count it once, not twice: the page says «two different weapons give two different bonuses» and says nothing about two weapons of one group",
        kind: weapon_type_bonus_kind(kind)
      )

  # ---- бой двумя оружиями (задача 3.132) --------------------------------------

  # Таблицы штрафов нет в снапшоте вовсе — то есть бой двумя оружиями посчитан
  # бесплатным. На поставляемых данных не производится никогда.
  def gap({:missing_data, :dual_wield_rules}, _ruleset),
    do:
      gettext(
        "the rules snapshot carries no two-weapon fighting penalties, so the second weapon costs this build nothing — in the game it costs both hands up to −6 and −10"
      )

  # Лёгкость второй руки сказать нечем — значит −2 обеим рукам не сняты.
  def gap({:missing_data, {:light_weapon, weapon}}, ruleset),
    do:
      gettext(
        "%{weapon}: it cannot be told whether this is a light weapon, so the −2 a light off hand takes off both hands is not counted",
        weapon: weapon_name(ruleset, weapon)
      )

  # 🔴 Условие Рейнджера по броне. Подпись обязана назвать и то, что посчитано,
  # и цену ошибки: иначе игрок в тяжёлой броне не узнает, что его число на 2 и 6
  # выше настоящего.
  #
  # ⚠️ Здесь стояло «класс тяжести брони НИГДЕ не назван в наших данных» — верно
  # до задачи 3.141 и неверно после: на `siala_41` он измерен (`GAME_CHECKS.md`
  # AH1) и эта строка там не печатается вовсе. Не назван он в ВАНИЛЬНЫХ
  # правилах — границу мерили на Сиале, а переносить её по аналогии запрещено, —
  # и подпись теперь говорит именно это. Разница не косметическая: «данных нет
  # ни у кого» звучит как наш недосмотр, «эти правила его не называют» — как
  # то, что и есть.
  def gap({:missing_data, {:armor_weight_class, feat}}, ruleset),
    do:
      gettext(
        "%{feat} works only in light armour, and these rules state no weight class for armour — the bonus is counted as if the armour were light",
        feat: feat_name(ruleset, feat)
      )

  # ⚠️ Правило чистоты у Адры не описано НИГДЕ — своей страницы у группы нет, а
  # четыре страницы классов только сообщают о членстве. Мы применили правило
  # Сагры, и это допущение, а не прочитанное: подпись обязана назвать его так,
  # иначе два разных по качеству факта («сагровик» прочитан дословно, «адровец»
  # выведен по аналогии) на экране выглядят одинаково.
  def gap({:assumed, {:class_group_purity, group}}, ruleset),
    do:
      gettext(
        "%{group}: the build purity rule is not described on the wiki — we apply the same one as Sagra Warriors (one level of an outside class cancels the group)",
        group: class_group_name(ruleset, group)
      )

  # Что даёт группа — неизвестно. ⚠️ Ни намёка на выгоды: про Адру не написано
  # ничего, и «вероятно, как у Сагры» здесь было бы выдумыванием игровых правил.
  def gap({:missing_data, {:class_group_benefits, group}}, ruleset),
    do:
      gettext(
        "%{group}: what the group gives is not written on any page, so nothing goes into the count besides membership itself",
        group: class_group_name(ruleset, group)
      )

  # А здесь наоборот: перечислено, но не считается. Расовый бонус группы мы с
  # 08.08.2026 считаем — про него врать нельзя, — а зелья, точило и множитель
  # от оружия остаются армори.
  def gap({:not_modelled, {:class_group_benefits, group}}, ruleset),
    do: class_group_benefits_note(ruleset, group)

  def gap({:not_modelled, {:class_change, class, what}}, ruleset),
    do:
      gettext("Siala's change «%{what}» for %{class} is not applied",
        what: what,
        class: class_name(ruleset, class)
      )

  # ⚠️ «Учтено не полностью», а не «не применено»: у части этих 26 фактов
  # применено ровно столько, сколько выражается числом, и неучтён остаток.
  # Слот «любимый враг» рейнджеру мы выдаём — неизвестен только его пул;
  # ступени Divine Might считаем по вики — не смоделирован рост от уровня
  # класса. Сказать «не применено» значило бы соврать в другую сторону.
  def gap({:not_modelled, {:feat_change, feat, what}}, ruleset),
    do:
      gettext("%{feat}: %{what} is on the wiki, but only partly accounted for",
        feat: feat_name(ruleset, feat),
        what: feat_change_what(what)
      )

  # ⚠️ Читается как «доступен с оговоркой», а не как отказ. Требование мы
  # проверили — фит на месте; неучтено только уточнение, которое схема выразить
  # не может. Слово «нельзя» тут было бы враньём в обратную сторону: раньше
  # такой фит не проверялся вовсе, теперь проверен настолько, насколько выразим.
  def gap({:not_modelled, {:feat_qualifier, feat, qualifier}}, ruleset),
    do:
      gettext(
        "%{feat}: the requirement is checked, but we do not check the qualifier «%{qualifier}» — the match is on you",
        feat: feat_name(ruleset, feat),
        qualifier: qualifier
      )

  def gap({:not_modelled, {:skill_change, skill, what}}, ruleset),
    do:
      gettext("Siala's change «%{what}» for skill %{skill} is not applied",
        what: what,
        skill: skill_name(ruleset, skill)
      )

  # Прибавка показана плоской сознательно (решение Дана): в ванили она работает
  # только против заклинаний, на Сиале ещё и не против AOE. Контекстность в UI
  # не тянем, но и молчать про допущение нельзя — гэп и есть честная замена.
  def gap({:not_modelled, {:save_bonus_scope, :spellcraft}}, _ruleset),
    do:
      gettext(
        "the Spellcraft save bonus is shown flat: in the game it does not work against AOE, and in vanilla it only works against spells"
      )

  def gap({:not_modelled, {:save_bonus_scope, source}}, _ruleset),
    do:
      gettext(
        "the save bonus from «%{source}» is shown flat — we do not model its conditions",
        source: source
      )

  # ⚠️ Сторона капа читается из ruleset'а, а не вписана словом: данные могут
  # решить и наоборот, и подпись, разошедшаяся с расчётом, здесь хуже отсутствия
  # подписи. Две формы, потому что данные отвечают на двух уровнях: вид источника
  # (у механизмов) и отдельная запись разметки (у всего остального). Про то,
  # у чего сторона названа Dan'ом, гэпа НЕТ и быть не должно — там правило,
  # а не допущение (09.08.2026).
  def gap({:assumed, {:cap_covers_source, stat, source}}, ruleset) do
    gettext(
      "%{source}: whether this source counts toward %{cap} is not stated on any page — %{side}, we cannot change the number without a source",
      source: attack_cap_source(source),
      cap: cap_name(stat),
      side: cap_side(Caps.covers_source?(ruleset, stat, source))
    )
  end

  def gap({:assumed, {:cap_covers_entry, stat, id}}, ruleset) do
    inside? =
      ruleset
      |> Bonuses.applied(cap_records_key(stat))
      |> Enum.find(&(&1.id == id))
      |> case do
        nil -> true
        record -> Caps.covers_record?(ruleset, stat, record)
      end

    gettext(
      "%{feat}: whether this bonus counts toward %{cap} is not stated on any page — %{side}, we cannot change the number without a source",
      feat: feat_name(ruleset, id),
      cap: cap_name(stat),
      side: cap_side(inside?)
    )
  end

  def gap({:missing_data, {:skill_key_ability, skill}}, ruleset),
    do:
      gettext(
        "skill %{skill}'s key ability is not named on any wiki — substituting one would be invention",
        skill: skill_name(ruleset, skill)
      )

  # ⚠️ Подпись называет ровно то, чего не хватает, — «отнимает ли», а не «сколько
  # отнимает»: величину надетого мы знаем точно (она у всех навыков одна), не
  # названо только, попадает ли этот навык под штраф. Появляется, лишь пока
  # надето что-то штрафующее: голым персонажем ответ один при любом чтении.
  def gap({:missing_data, {:skill_armor_check_penalty, skill}}, ruleset),
    do:
      gettext(
        "nowhere is it said whether worn armor takes from skill %{skill} — we cannot show a value, and counting the penalty as zero would be invention",
        skill: skill_name(ruleset, skill)
      )

  def gap({:not_modelled, {:class_qualifier, class, qualifier}}, ruleset),
    do:
      gettext(
        "%{class}: the requirements are checked, but we do not check qualifier «%{qualifier}»",
        class: class_name(ruleset, class),
        qualifier: qualifier
      )

  # Требование есть, а прочитать его нечем: это не «требования нет».
  def gap({:missing_data, {:prerequisite, field}}, _ruleset),
    do:
      gettext("requirement «%{field}» is written so it cannot be read by machine — not checked",
        field: field
      )

  def gap({:missing_data, {:caster_level, n}}, _ruleset),
    do:
      gettext(
        "requires caster level %{n}, which we do not compute: the data has neither the identity «caster level = class level» nor a multiclass rule",
        n: n
      )

  # Ranked abilities share one wiki page, so the level shows the family name
  # rather than the rank: barbarian 15 is Greater Rage, not another Rage.
  def gap({:not_modelled, {:unnamed_grant_rank, class, level, feat}}, ruleset),
    do:
      gettext(
        "%{class} %{level}: rank «%{feat}» is named by the family's shared name — the wiki has one page for the whole family",
        class: class_name(ruleset, class),
        level: level,
        feat: feat_name(ruleset, feat)
      )

  def gap({:conflict, {:class_skill, class, skill, where}}, ruleset),
    do:
      gettext(
        "sources disagree on whether %{skill} is a class skill for %{class} (%{where}) — taken as a class skill",
        skill: skill_name(ruleset, skill),
        class: class_name(ruleset, class),
        where: conflict_side(where)
      )

  # ⚠️ Подпись обязана назвать И спор, И то, как он решён: у гэпа этого разряда
  # («Источники спорят») читатель приходит за вторым не меньше, чем за первым.
  # Решение — лейбл страницы, довод у него источниковый
  # (`fandom:Untrained skill check`: «NWNWiki uses the former»), и живёт он
  # в `Data.Loader.Skills.build_skills/1` рядом с самим чтением.
  def gap({:conflict, {:skill_trained_only, skill, where}}, ruleset),
    do:
      gettext(
        "sources disagree on whether %{skill} requires training (%{where}) — the page label is taken",
        skill: skill_name(ruleset, skill),
        where: trained_conflict_side(where)
      )

  def gap({:skill_over_cap, skill, level, ranks, cap}, ruleset),
    do:
      gettext("%{skill}: %{ranks} r. at level %{level} with a ceiling of %{cap}",
        skill: skill_name(ruleset, skill),
        level: level,
        ranks: ranks,
        cap: cap
      )

  def gap({:derived, :class_skills, :union_of_class_and_skill_pages}, _ruleset),
    do: gettext("class skills are gathered as the union of the class page and the skill page")

  def gap({:derived, :class_skills, :from_class_skills_raw}, _ruleset),
    do: gettext("class skills are taken only from class pages")

  # ⚠️ Задача 3.49 (18.08.2026): у обеих раньше стояла подпись «страницы про
  # это нет ни на одной вики» / «формулы на вики нет» — и это оказалось
  # неправдой, страницы нашлись по подсказке Dan (`fandom:Armor class`,
  # `fandom:Ability modifier`, обе — общие правила, вне категорий, по которым
  # ходит `mix wiki.fetch`). Гэп, утверждающий отсутствие источника, который
  # существует, хуже отсутствующего гэпа — поэтому подпись теперь читает
  # источник из данных (`constant_source/2` в `Loader.Gaps`), а не повторяет
  # старый текст. Второй clause — честный откат на случай, если запись в
  # `_vanilla_constants_confirmed` когда-нибудь потеряет source: тогда подпись
  # обязана вернуться к «страницы нет», а не соврать в другую сторону.
  def gap({:assumed, :base_ac, value, nil}, _ruleset),
    do: gettext("base AC is taken as %{value}: no page on any wiki states this", value: value)

  def gap({:assumed, :base_ac, value, source}, _ruleset),
    do:
      gettext("base AC is taken as %{value} — confirmed by page %{source}",
        value: value,
        source: source
      )

  def gap({:assumed, :ability_modifier_formula, formula, nil}, _ruleset),
    do:
      gettext("the ability modifier is computed as %{formula} — the wiki has no formula",
        formula: formula
      )

  def gap({:assumed, :ability_modifier_formula, formula, source}, _ruleset),
    do:
      gettext(
        "the ability modifier is computed as %{formula} — confirmed by page %{source}",
        formula: formula,
        source: source
      )

  def gap({:assumed, :attacks_per_round_table, source}, _ruleset),
    do:
      gettext("the attacks-per-round table is taken from %{source}, the shard's rules have none",
        source: source
      )

  def gap({:assumed, :hp_uses_maximum_hit_die_rolls}, _ruleset),
    do: gettext("HP is counted at the hit die maximum for every level")

  def gap({:assumed, :skill_rank_caps_past_vanilla_cap}, _ruleset),
    do: gettext("rank ceilings past level 40 continue with the formula «level + 3»")

  # ⚠️ Две разные подписи, и путать их нельзя: первая означает «правило применено,
  # но по ванильному источнику», вторая — «применять нечего, значит разрешено всё».
  def gap({:assumed, :class_unavailable_feats_vanilla}, _ruleset),
    do:
      gettext(
        "which feats a class does not grant a choice of at its level — the lists are vanilla: the Siala wiki is silent about this"
      )

  def gap({:missing_data, :class_unavailable_feats}, _ruleset),
    do: gettext("classes have no lists of forbidden feats in the data — the ban is not checked")

  # ⚠️ Подпись обязана назвать, что выключение здесь ВЫВЕДЕНО, а не измерено:
  # у измеренных выключений гэпа нет вовсе, и печатать одно и то же про оба
  # значило бы стереть разницу (`GAME_CHECKS.md` H5).
  def gap({:assumed, {:feat_disabled, feat}}, ruleset),
    do:
      gettext(
        "we consider %{feat} disabled on Siala by inference, not by observation: the feat is granted by exactly one class, and a granted feat is not shown in the game's list",
        feat: feat_name(ruleset, feat)
      )

  def gap({:assumed, :point_buy_costs}, _ruleset),
    do: gettext("point-buy prices (30 points, 8–18, pricier past 14) do not live in the data")

  def gap({:unknown_class, class}, _ruleset),
    do: gettext("class %{class} is not found in the data", class: class)

  def gap(other, _ruleset), do: inspect(other)

  defp conflict_side(:class_page_only), do: gettext("only on the class page")
  defp conflict_side(:skill_page_only), do: gettext("only on the skill page")
  defp conflict_side(other), do: to_string(other)

  # ⚠️ Свои две ветки, а не `conflict_side/1` выше: там спорят ДВЕ СТРАНИЦЫ,
  # здесь — страница и её собственная категория, и «только на странице навыка»
  # про этот спор было бы неправдой (страница у него ровно одна).
  defp trained_conflict_side(:label_only), do: gettext("only the page label says so")
  defp trained_conflict_side(:category_only), do: gettext("only the category says so")
  defp trained_conflict_side(other), do: to_string(other)

  # Механизм, дающий прибавку, названный тем, что игрок про него знает.
  # ⚠️ Записи разметки сюда не приходят — у них своя подпись по имени фита
  # (`cap_covers_entry`), потому что «прибавка от фита» не отличает Divine grace
  # от Sacred defense, а сторона капа у них разная (Dan, 09.08.2026).
  defp attack_cap_source(:gear), do: gettext("an ability bonus from items")
  defp attack_cap_source(:racial_bonus), do: gettext("Siala's racial bonus")
  defp attack_cap_source(:skill_rule), do: gettext("a bonus from skill ranks")
  defp attack_cap_source(other), do: gettext("bonus «%{other}»", other: other)

  # Кап называется тем, что игрок видит в панели, а не ключом ruleset'а.
  #
  # ⚠️ «+20» здесь — то же самое число, что печаталось всегда, не новое
  # магическое число этого захода: task 3.83 меняет обёртку в gettext, а
  # не вычисляет заново, что показывать. Числа в этих двух подписях уже
  # были литералами до правки (`GAME_CHECKS.md`, CLAUDE.md §9, потолки +20) —
  # заводить их как параметр ruleset'а вместо msgid текста было бы отдельной
  # задачей дальше границ этого захода.
  defp cap_name(:attack_bonus), do: gettext("the attack cap +20")
  defp cap_name(:saving_throw_bonus), do: gettext("the save cap +20")
  defp cap_name(other), do: gettext("cap «%{other}»", other: other)

  defp cap_side(true), do: gettext("counted INSIDE the cap, as before")
  defp cap_side(false), do: gettext("counted ON TOP OF the cap")

  # ⚠️ Связка «стат → файл разметки» здесь ВТОРАЯ в проекте, и это не копия по
  # недосмотру: `Rules.Bonuses` сознательно не выводит ключ из стата, а требует
  # его аргументом, — но форма гэпа `{:assumed, {:cap_covers_entry, stat, id}}`
  # несёт только стат, поэтому веб-слою больше нечего спросить. Искать запись по
  # id сразу во всех файлах взамен нельзя: четыре id лежат и в атаке, и в сейвах
  # (`divine_wrath`, `epic_prowess`, `superior_weapon_focus`, `terrifying_rage`),
  # причём `epic_prowess` в одном `applied`, а в другом `counted_elsewhere` —
  # поиск выбрал бы не ту сторону капа. То есть отображение необходимо, и убрать
  # его можно только одним способом: положив ключ разметки в саму форму гэпа
  # (правка ядра и `Rules.Vocabulary`, не веб-слоя).
  #
  # ⚠️ Третья ветвь СЕГОДНЯ НЕДОСТИЖИМА, проверено вызовом: `cap_side_gaps/5`
  # зовётся из `Rules.compute/2` ровно дважды, с `:attack_bonus` и
  # `:saving_throw_bonus`. Она остаётся, потому что подпись не имеет права
  # падать на незнакомом стате, но её ответ — молчаливое «внутри капа» (через
  # `nil -> true` выше), и это худший из возможных ответов. Появится третий
  # потолок с записями — ключ добавить ЗДЕСЬ, а не полагаться на ветвь.
  defp cap_records_key(:attack_bonus), do: :attack_bonuses
  defp cap_records_key(:saving_throw_bonus), do: :save_bonuses
  defp cap_records_key(_other), do: :none

  # The four kinds the shard's feat pages actually produce, named by what the
  # player would have to go and read. An unknown kind keeps its raw key rather
  # than getting a guessed translation — a wrong name is worse than a key.
  defp feat_change_what("siala_note"), do: gettext("a shard rule in prose")
  defp feat_change_what("unlocks"), do: gettext("a weapon table by level")
  defp feat_change_what("feat_slots"), do: gettext("the slots the feat grants")
  defp feat_change_what("level_table"), do: gettext("a table by level")
  defp feat_change_what("repeatable"), do: gettext("whether it can be taken again")
  defp feat_change_what(other), do: gettext("change «%{other}»", other: other)

  # Виды расового бонуса Сиалы, названные тем, куда бонус ложится. Подписи
  # русские, а не английские: это описание механики, а не имя сущности, которое
  # печатает движок (CLAUDE.md §4). Незнакомый вид оставляет свой ключ — угаданный
  # перевод хуже ключа.
  #
  # ⚠️ Не `@racial_bonus_kinds` module-словарь с готовыми строками, как было —
  # module-атрибут вычисляется ОДИН РАЗ на компиляции, а `gettext/1` обязан
  # читать локаль каждого запроса заново. Словарь со значениями-`gettext(...)`
  # запёк бы перевод компилятора в атрибут навсегда. Форма та же, что у
  # `domain_name/1`: клаузы функции, а не `Map.get/3`.
  defp racial_bonus_kind(:attack_bonus), do: gettext("to attack")
  defp racial_bonus_kind(:shield_ac), do: gettext("shield AC")
  defp racial_bonus_kind(:skill_bonus), do: gettext("to a skill")
  defp racial_bonus_kind(:damage_resistance), do: gettext("elemental damage resistance")
  defp racial_bonus_kind(:damage), do: gettext("to damage")
  defp racial_bonus_kind(kind), do: to_string(kind)

  # Виды бонуса за тип оружия — тот же словарь, что у расового бонуса, потому что
  # на вики это одна и та же система: у расы бонус «идентичен бонусу от [[Владение
  # клинковым оружием]]». Держать два словаря значило бы позволить им разойтись
  # в подписи к одному и тому же числу.
  defp weapon_type_bonus_kind(kind), do: racial_bonus_kind(kind)

  @doc """
  Справка к ПОСЧИТАННОМУ расовому бонусу — та, что печатается рядом с самим
  числом, а не в списке пробелов билда (задача 3.102, решение Dan 25.08.2026).

  Принимает запись ядра целиком (`stats.racial_bonus`), потому что вариант,
  раса и вид бонуса лежат в ней вместе; `nil` — когда говорить нечего:

    * расы с бонусом нет вовсе (Гоблин, Тёмный эльф) — запись `nil`;
    * бонус не посчитан (`counted: nil`) — это либо уровень ниже 40-го, либо
      пустые руки, и об этом говорит ГЭП, а не справка. Печатать здесь второй
      голос про то же самое значило бы сказать одно и то же дважды в двух
      разных местах экрана.

  ⚠️ Текст не свой — тот же `racial_bonus_variant_sentence/5`, что и у гэпа,
  и ни одно из четырёх чисел здесь не написано второй раз (они читаются из
  ruleset'а). Задача 3.102 меняла МЕСТО вывода, а не слова: обе ветки прошли
  i18n заходом 1 задачи 3.83, где склейки специально разобраны в целые
  предложения по ветке.
  """
  @spec racial_bonus_note(map(), map() | nil) :: String.t() | nil
  def racial_bonus_note(ruleset, bonus)

  def racial_bonus_note(ruleset, %{race: race, counted: counted, variant: variant})
      when is_integer(counted) and not is_nil(variant),
      do: racial_bonus_variants_note(ruleset, race, variant)

  def racial_bonus_note(_ruleset, _bonus), do: nil

  # ⚠️ Справка про остальные варианты числа, и она обязательна: посчитанный
  # здесь — НЕ самый большой из четырёх, и «+9» без этой строки читается как вся
  # правда (задача 3.12).
  #
  # ⚠️ **Хвост переписан 16.08.2026 (задача 3.35), и переписан по правилу, а не
  # по вкусу.** Он говорил «бонус за тип оружия мы пока не считаем» — с этой
  # задачи считаем, и печатать «не считаем» про посчитанное запрещено ровно так
  # же прямо, как обратное (CLAUDE.md §6). Два оставшихся варианта расового
  # бонуса — это СУММЫ двух независимых термов (замер Dan, `GAME_CHECKS.md` Q1:
  # «+9 светлый эльф + 9 оружие дальнего боя»), поэтому подпись теперь обещает не
  # доработку, а арифметику: возьми оружие своей группы — и вторая половина
  # появится в «Итого» сама, отдельной строкой.
  #
  # ⚠️ Две разные подписи, потому что это два разных признания. У базового
  # варианта справка обязана назвать, ЧЕГО билду не хватило (он не сагровик, и
  # это исправляется составом классов); у сагровского — что покровительство уже
  # учтено (решение Dan 08.08.2026), иначе игрок пойдёт искать недосчёт, которого
  # больше нет. Печатать «Сагру в расчёт не берём» после того, как взяли, — ровно
  # та ложная неопределённость наоборот, которую запрещает CLAUDE.md §6.
  #
  # Числа берутся из ruleset'а, а не из тапла гэпа: ядро уже отдало их
  # (`stats.racial_bonus.variants`, `ruleset.racial_bonuses`), и второе написание
  # тех же четырёх чисел разошлось бы с первым.
  defp racial_bonus_variants_note(ruleset, race, variant) do
    case racial_bonus_record(ruleset, race) do
      %{variants: v} = record ->
        racial_bonus_variant_sentence(ruleset, race, record, v, variant)

      nil ->
        gettext("the racial bonus is not counted at its largest of the four variants")
    end
  end

  # 🔴 Флагманский пример «сцепленной строки» из задачи 3.83 (см. module doc).
  # Раньше здесь стоял общий хвост «Это только половина: …», приклеенный `<>`
  # к результату отдельной функции с четырьмя ветками — ровно та форма, которую
  # через gettext перевести нельзя: у каждой ветки свой порядок слов внутри
  # тела, и переводчик никогда не видел предложение целиком. Поэтому здесь одна
  # функция с ЧЕТЫРЬМЯ полными предложениями, каждое своим `gettext/2`.
  #
  # ⚠️ Хвост подписи говорил «оружие мы не моделируем, это армори» — снято
  # 15.08.2026 как неверное дважды: оружие в билде есть с задачи 3.5, а замер Dan
  # показал, что два числа СКЛАДЫВАЮТСЯ, то есть `racial_weapon` — это сумма
  # расового и оружейного, а не отдельный вариант «надел расовое».
  #
  # 🔴 ВТОРОЙ ХВОСТ СНЯТ 31.08.2026 (запрос Dan), и он был НЕТОЧЕН, а не просто
  # длинен. Говорил: «с подходящим по типу оружием сверху ложится ещё и бонус
  # за тип оружия — вместе выходит +12, а у воина Сагры +18». Dan: «+18 получается
  # только светлый эльф сагровик НА МЕТАТЕЛЬНОЕ».
  #
  # ⚠️ Почему обобщение было ложным: `racial_weapon` — это сумма расового бонуса
  # и бонуса за РАСОВОЕ оружие, а расовое у каждой расы своё
  # (`siala_41/races.json` → `racial_bonus.mirrors_weapon_type`). У Светлого эльфа
  # это оружие ДАЛЬНЕГО БОЯ; с клинковым в руках оружейный бонус идёт в щитовой
  # AC, а не в атаку, и никаких +12 к AB не выходит. Фраза «с подходящим по типу»
  # звучала как «с любым нормальным», а значила «ровно с одним видом из пяти».
  #
  # ⚠️ Решение Dan — убрать, а не уточнить: «в целом люди и так знают про бонусы
  # расы и оружия, не обязательно давать такие длинные подсказки в UI».
  # 🔴 Осталось НАЗЫВАНИЕ ПОСЧИТАННОГО ВАРИАНТА — его снимать нельзя (CLAUDE.md §3):
  # «оговорка обязана называть посчитанный вариант… печатать "Сагру в расчёт
  # не берём" после того, как взяли, — ложная неопределённость наоборот».
  # Четыре числа по-прежнему отдаются справкой (`stats.racial_bonus.variants`).
  defp racial_bonus_variant_sentence(ruleset, race, record, v, :sagra_warrior) do
    gettext(
      "race %{race} bonus %{target}: the build fits a Sagra warrior, so the Sagra warrior variant %{sagra_warrior} is counted, not the base %{base}.",
      race: race_ru(ruleset, race),
      target: racial_bonus_target(ruleset, record),
      sagra_warrior: signed(v.sagra_warrior),
      base: signed(v.base)
    )
  end

  defp racial_bonus_variant_sentence(ruleset, race, record, v, :base) do
    gettext(
      "race %{race} bonus %{target}: the base %{base} is counted — the build is not a Sagra warrior, which would get %{sagra_warrior}.",
      race: race_ru(ruleset, race),
      target: racial_bonus_target(ruleset, record),
      base: signed(v.base),
      sagra_warrior: signed(v.sagra_warrior)
    )
  end

  # Третье состояние: число на этом уровне известно, а бонуса нет, потому что
  # включать его нечем. Замер Dan 15.08.2026: голый светлый эльф-сагровик 40
  # показывает в игре AB 29, с мечом — 43. Сказать тут «посчитан базовый» было бы
  # прямой неправдой, а промолчать — спрятать то, что игрок чинит одним движением.
  defp racial_bonus_variant_sentence(ruleset, race, record, v, nil) do
    gettext(
      "race %{race} bonus %{target}: not counted — the bonus is activated by a weapon in hand, and the hands hold either nothing or a weapon that does not activate it. With a weapon %{base}, for a Sagra warrior %{sagra_warrior}.",
      race: race_ru(ruleset, race),
      target: racial_bonus_target(ruleset, record),
      base: signed(v.base),
      sagra_warrior: signed(v.sagra_warrior)
    )
  end

  defp racial_bonus_variant_sentence(ruleset, race, record, v, variant) do
    gettext(
      "race %{race} bonus %{target}: variant «%{variant}» %{value} is counted.",
      race: race_ru(ruleset, race),
      target: racial_bonus_target(ruleset, record),
      variant: variant,
      value: signed(Map.get(v, variant, 0))
    )
  end

  # Что группа даёт помимо расового бонуса. Список берём из данных
  # (`ruleset.class_groups`), а не пишем вторым написанием: он на вики
  # перечислен, и разойдись два списка — подпись назвала бы не то, что лежит
  # в данных.
  #
  # ⚠️ **Перечисляются только НЕПОСЧИТАННЫЕ строки, и это правка 16.08.2026
  # (задача 3.35).** Раньше подпись печатала весь список и добавляла «в расчёт
  # не идут»; в списке Сагры стоит «усиленный бонус от оружия», а он с этой
  # задачи считается — то есть подпись обвиняла бы в непосчитанном ровно то, что
  # посчитано. Вычитание сделано ядром (`ClassGroups.membership.benefits_uncounted`),
  # а не здесь: какие строки доезжают до чисел — вопрос данных, а не вёрстки.
  defp class_group_benefits_note(ruleset, group) do
    name = class_group_name(ruleset, group)

    case class_group(ruleset, group) do
      %{benefits: [_ | _]} = record ->
        uncounted = Map.get(record, :benefits) -- (Map.get(record, :benefits_counted) || [])

        gettext(
          "%{name} also give %{benefits} — not counted: these are consumables and armory. The group's racial bonus and its weapon-type bonus are counted.",
          name: name,
          benefits: Enum.join(uncounted, ", ")
        )

      _ ->
        gettext("%{name}: what the group gives is not counted", name: name)
    end
  end

  @doc """
  Русское имя группы классов — то есть заголовок её страницы на вики Сиалы.

  ⚠️ **По-русски, и это не нарушение §4.** «Воины Сагры» — не игровая сущность,
  которую печатает движок (класс, фит, заклинание), а название группы со
  страницы шарда: английского имени у неё не существует ни в игре, ни на Fandom,
  и придумать его было бы ровно тем фанатским переводом, который §4 запрещает.
  Имена самих классов внутри пояснения остаются английскими.

  Читается из данных; незнакомая группа отдаёт свой id, а не угаданный перевод.
  """
  @spec class_group_name(map(), atom()) :: String.t()
  def class_group_name(ruleset, group) do
    case class_group(ruleset, group) do
      %{name: name} when is_binary(name) -> name
      _ -> to_string(group)
    end
  end

  defp class_group(ruleset, group) do
    ruleset |> Map.get(:class_groups) |> List.wrap() |> Enum.find(&(&1.id == group))
  end

  defp racial_bonus_record(ruleset, race) do
    case Map.get(ruleset, :racial_bonuses) do
      %{by_race: by_race} -> Map.get(by_race, race)
      _ -> nil
    end
  end

  defp racial_bonus_target(ruleset, %{kind: :skill_bonus, skill: skill}),
    do: gettext("to skill %{skill}", skill: skill_name(ruleset, skill))

  defp racial_bonus_target(_ruleset, %{kind: kind}), do: racial_bonus_kind(kind)

  # ⚠️ Число рядом с непосчитанной прибавкой к атаке — « (+1)», « (+2)», « (+7)».
  # Она нужна ровно потому, что решение НЕ считать прибавку осознанное и
  # временное (`vanilla/feat_attack_bonuses.json` → `_weapon_decision`): пока
  # оружия нет в модели, игрок может прибавить число сам — но только если знает
  # его. «Не считаем» без числа заставляет идти на вики; «не считаем +2»
  # закрывает вопрос на месте.
  #
  # Берётся из тех же данных, что и отказ, а не из отдельного словаря: две
  # копии числа разошлись бы. Форма, у которой числа нет вовсе (таблица по
  # уровням класса, модификатор характеристики) или которая его не называет
  # (`Mounted archery` — снятие штрафа), печатается без скобок.
  # ⚠️ Ищет и среди отвергнутых, и среди ПОСЧИТАННЫХ записей. С задачи 3.5
  # (часть B) `Weapon focus` лежит в `applied`, а гэп про него всё равно бывает —
  # у билда, который оружие не назвал, — и подпись без числа потеряла бы ровно
  # то, ради чего она есть: игрок может прибавить +1 сам.
  defp attack_bonus_amount(ruleset, id) do
    (Bonuses.rejected(ruleset, :attack_bonuses) ++ Bonuses.applied(ruleset, :attack_bonuses))
    |> Enum.find(&(&1.id == id))
    |> case do
      %{amount: %{kind: :flat, bonus: bonus}} when bonus > 0 -> " (+#{bonus})"
      %{amount: %{kind: :flat, bonus: bonus}} when bonus < 0 -> " (#{bonus})"
      _ -> ""
    end
  end

  # Правило смены характеристики атаки — то самое, из-за которого билд получил
  # оговорку. Читается из ruleset'а по фиту: и характеристика, и требуемое
  # оружие лежат там, а не здесь, иначе подпись разъехалась бы с расчётом ровно
  # в тот день, когда шард поправит правило.
  defp attack_ability_rule(ruleset, id) do
    ruleset
    |> Map.get(:attack_ability, %{})
    |> Map.get(:rules, [])
    |> Enum.find(&(&1.feat == id))
  end

  defp attack_ability_of(ruleset, id) do
    case attack_ability_rule(ruleset, id) do
      %{ability: ability} -> ability(ability)
      _none -> gettext("a different ability")
    end
  end

  # Единственное свойство оружия, которое сегодня умеет требовать правило. Общая
  # ветка — не заглушка «на всякий случай», а честный ответ для правила, чьё
  # требование этот словарь ещё не выучил: назвать его словом нельзя, а промолчать
  # про причину — хуже.
  defp attack_ability_weapon_ru(ruleset, id) do
    case attack_ability_rule(ruleset, id) do
      %{weapon_must_be: property} when not is_nil(property) -> weapon_property_ru(property)
      _none -> gettext("a suitable weapon")
    end
  end

  defp weapon_property_ru(:ranged), do: gettext("a ranged weapon")
  defp weapon_property_ru(_other), do: gettext("a suitable weapon")

  # Характеристика атаки ДО фитов: та, что считается с пустыми руками, и та,
  # что дало бы оружие названного свойства. Обе лежат в ruleset'е (задача 3.34)
  # — здесь только слово, которым их зовут по-русски.
  defp attack_ability_default(ruleset),
    do: ruleset |> Map.get(:attack_ability, %{}) |> Map.get(:default)

  defp attack_ability_default(ruleset, property) do
    ruleset
    |> Map.get(:attack_ability, %{})
    |> Map.get(:weapon_defaults, [])
    |> Enum.find_value(fn record ->
      if record.weapon_must_be == property, do: record.ability
    end)
  end

  # Сейвы, как их пишет игра и формат экспорта (CLAUDE.md §4).
  defp save_name(:fort), do: "Fort"
  defp save_name(:fortitude), do: "Fort"
  defp save_name(:ref), do: "Ref"
  defp save_name(:reflex), do: "Ref"
  defp save_name(:will), do: "Will"
  defp save_name(other), do: to_string(other)

  @doc "Short name of a gap family, for grouping the list."
  @spec gap_kind(term()) :: String.t()
  def gap_kind({:missing_data, _}), do: gettext("No data")
  def gap_kind({:missing_file, _}), do: gettext("No data")
  def gap_kind({:not_modelled, _}), do: gettext("Not modelled")
  def gap_kind({:conflict, _}), do: gettext("Sources disagree")
  # ⚠️ Оба `{:assumed, _, _}` и `{:assumed, _, _, _}` нужны отдельно: Elixir
  # сопоставляет по АРНОСТИ, а не «начинается с :assumed» (задача 3.49 завела
  # 4-элементные `:assumed, id, value, source` для base_ac и
  # ability_modifier_formula, чтобы подпись несла источник).
  def gap_kind({:assumed, _, _, _}), do: gettext("Assumptions")
  def gap_kind({:assumed, _, _}), do: gettext("Assumptions")
  def gap_kind({:assumed, _}), do: gettext("Assumptions")
  def gap_kind({:derived, _, _}), do: gettext("Derived, not read")
  def gap_kind({:skill_over_cap, _, _, _, _}), do: gettext("The build breaks a rule")
  def gap_kind(_other), do: gettext("Other")

  # Получатели факта шарда (`changes[].affects`, задача 3.28) — коротко,
  # в том порядке, в каком их печатают списком. Порядок — решение интерфейса,
  # поэтому список id, а не карта: у множества из ядра порядок алфавитный
  # по английскому id, и «характеристики, AC, бонус атаки» читалось бы как
  # случайная выборка.
  #
  # ⚠️ Список обязан покрывать ОБА множества `ruleset.gap_receivers` целиком —
  # это под тестом (`SourcesLive` печатает и наши получатели, и не наши). Сам
  # список закрыт в данных, и загрузчик падает на получателе вне него, так что
  # незакрытым остаётся ровно один зазор: получатель, законно добавленный
  # в данные и не названный здесь. На него сторож и стоит.
  #
  # ⚠️ **id и подпись разведены на список плюс функцию, а не единый
  # module-словарь `{id, msgstr}`, как было до задачи 3.83.** `gettext/1`
  # обязан читать локаль каждого запроса заново, а module-атрибут вычисляется
  # ОДИН РАЗ на компиляции — словарь со значениями-`gettext(...)` запёк бы
  # перевод в атрибут навсегда. Та же причина, что развела `@racial_bonus_kinds`
  # на функцию `racial_bonus_kind/1` чуть выше.
  @receiver_ids ~w(
    ability_scores hp ac bab attack_bonus attacks_per_round saving_throws
    skill_values skill_points skill_rank_caps spells_per_day spells_known
    feat_availability class_availability class_group
    damage critical_hit save_dc metamagic concealment
    duration immunities summons familiar poisons traps movement_speed
    custom_items buff healing spell_effects ability_uses special_ability
    mounted_combat party_dependent crafting custom_system domains item_usage
    weapon_armor_proficiency counted_elsewhere
  )

  @doc """
  Short name of a shard fact's receiver (`changes[].affects`).

  Falls back to the raw id, the way everything else here does: an unworded
  receiver has to be visible, not swallowed.
  """
  @spec gap_receiver(String.t()) :: String.t()
  def gap_receiver(id), do: receiver_name(id)

  @doc """
  The receivers of a set, worded and in display order.

  Order comes from this module's own list rather than from the set, which is
  alphabetical by English id — see `@receiver_ids`.
  """
  @spec gap_receivers(Enumerable.t()) :: [String.t()]
  def gap_receivers(ids) do
    ids = MapSet.new(ids)

    for id <- @receiver_ids, MapSet.member?(ids, id), do: receiver_name(id)
  end

  # то, что калькулятор печатает
  #
  # ⚠️ `hp`/`ac`/`bab` остаются литералами, не идут через `gettext/1`: это
  # английские аббревиатуры статов (CLAUDE.md §4), а не интерфейсные подписи —
  # тот же класс решений, что у `ability/1` и `save_name/1` выше.
  defp receiver_name("ability_scores"), do: gettext("ability scores")
  defp receiver_name("hp"), do: "HP"
  defp receiver_name("ac"), do: "AC"
  defp receiver_name("bab"), do: "BAB"
  defp receiver_name("attack_bonus"), do: gettext("attack bonus")
  defp receiver_name("attacks_per_round"), do: gettext("attacks per round")
  defp receiver_name("saving_throws"), do: gettext("saving throws")
  defp receiver_name("skill_values"), do: gettext("skill values")
  defp receiver_name("skill_points"), do: gettext("skill points")
  defp receiver_name("skill_rank_caps"), do: gettext("skill rank ceilings")
  defp receiver_name("spells_per_day"), do: gettext("spell slots per day")
  defp receiver_name("spells_known"), do: gettext("known spells")
  defp receiver_name("feat_availability"), do: gettext("feat availability")
  defp receiver_name("class_availability"), do: gettext("class availability")
  defp receiver_name("class_group"), do: gettext("class groups")
  # то, чего не печатает вовсе
  defp receiver_name("damage"), do: gettext("damage")
  defp receiver_name("critical_hit"), do: gettext("critical hits")
  defp receiver_name("save_dc"), do: gettext("the target's saving throw DC")
  defp receiver_name("metamagic"), do: gettext("metamagic")
  defp receiver_name("concealment"), do: gettext("concealment")
  defp receiver_name("duration"), do: gettext("effect duration")
  defp receiver_name("immunities"), do: gettext("immunities and resistances")
  defp receiver_name("summons"), do: gettext("summons")
  defp receiver_name("familiar"), do: gettext("familiar")
  defp receiver_name("poisons"), do: gettext("poisons")
  defp receiver_name("traps"), do: gettext("traps")
  defp receiver_name("movement_speed"), do: gettext("movement speed")
  defp receiver_name("custom_items"), do: gettext("class items")
  defp receiver_name("buff"), do: gettext("buffs (spells and the bard's song)")
  defp receiver_name("healing"), do: gettext("healing")
  defp receiver_name("spell_effects"), do: gettext("changed spells")
  defp receiver_name("ability_uses"), do: gettext("number of ability uses")
  defp receiver_name("special_ability"), do: gettext("abilities with no number to show")
  defp receiver_name("mounted_combat"), do: gettext("mounted combat")
  defp receiver_name("party_dependent"), do: gettext("effects from nearby allies")
  defp receiver_name("crafting"), do: gettext("crafting items and potions")
  defp receiver_name("custom_system"), do: gettext("the shard's own systems")
  defp receiver_name("domains"), do: gettext("Cleric domains")
  defp receiver_name("item_usage"), do: gettext("item use thresholds")
  defp receiver_name("weapon_armor_proficiency"), do: gettext("weapon and armor proficiency")
  defp receiver_name("counted_elsewhere"), do: gettext("already counted elsewhere")
  defp receiver_name(id), do: id

  @doc "Why a shared link could not be opened."
  @spec decode_error(atom()) :: String.t()
  def decode_error(:malformed),
    do: gettext("The link is broken — the build code cannot be read. An empty builder is open.")

  def decode_error(:too_long),
    do: gettext("The build code is too long. An empty builder is open.")

  def decode_error(:unknown_version),
    do:
      gettext(
        "This link was made by a different encoding version that is not here anymore. An empty builder is open."
      )

  def decode_error(:unknown_ruleset),
    do: gettext("This link points to a ruleset that no longer exists. An empty builder is open.")

  def decode_error(other),
    do: gettext("Could not open the link (%{reason}).", reason: inspect(other))

  @doc """
  Why a short link could not be issued.

  Every wording is required to say the build is not lost: the long link stays
  on screen and works, the short one is only a convenience.
  """
  @spec short_link_error(atom()) :: String.t()
  def short_link_error(:invalid_code),
    do:
      gettext(
        "Could not issue a short link: the build code cannot be read. The long link above works."
      )

  def short_link_error(:unavailable),
    do: gettext("Could not issue a short link. Try again — the long link above works.")

  def short_link_error(:too_many),
    do:
      gettext(
        "Too many short links were made in one session. The long link above works and is not going anywhere."
      )

  def short_link_error(other),
    do: gettext("Could not issue a short link (%{reason}).", reason: inspect(other))

  @doc "What was thrown out of a decoded link."
  @spec dropped(list()) :: String.t()
  def dropped(entries) do
    entries
    |> Enum.map(fn
      {:unknown_class, name} -> gettext("class %{name}", name: name)
      {:unknown_feat, name} -> gettext("feat %{name}", name: name)
      {:unknown_skill, name} -> gettext("skill %{name}", name: name)
      {:unknown_spell, name} -> gettext("spell %{name}", name: name)
      {:unknown_slot, name} -> gettext("slot %{name}", name: name)
      # Надетое (задача 3.41): в коде стоял доспех или щит, которого в справочнике
      # больше нет. Названо целиком парой «категория|предмет» — без категории
      # непонятно, что именно потерялось.
      {:unknown_worn, name} -> gettext("worn item %{name}", name: name)
      # Фит вместе с выбором: в коде стояла школа/раса, которой в справочнике
      # больше нет. Пик выпал целиком — см. `Encoding.resolve_feat/2`.
      {:unknown_choice, name} -> gettext("feat with a choice %{name}", name: name)
      other -> inspect(other)
    end)
    |> Enum.join(", ")
  end
end
