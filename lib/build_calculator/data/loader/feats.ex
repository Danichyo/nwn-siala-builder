defmodule BuildCalculator.Data.Loader.Feats do
  @moduledoc """
  Фиты: ванильные записи, ручной слой требований поверх машинного разбора вики
  и сиальский слой (машинный плюс ручной, в этом порядке).

  Здесь же `repeatable/1,3,4` — чтение блока повторяемости фита; `Data.Loader`
  отдаёт его наружу делегатом, потому что на него ссылается `Rules.Vocabulary`.
  """

  alias BuildCalculator.Data.Loader.FactReceivers
  alias BuildCalculator.Data.Loader.NotAGap
  alias BuildCalculator.Data.Loader.Reading

  import BuildCalculator.Data.Loader.Reading

  @ability_keys Reading.ability_keys()
  @requirement_keys Reading.requirement_keys()

  # ------------------------------------------------------------------ feats --

  def build_feats(:missing), do: %{}

  def build_feats(list) do
    Map.new(list, fn f ->
      id = atom(f["id"])

      {id,
       %{
         id: id,
         name: f["name"],
         # The shard's own page title. A **search alias**, not a name (CLAUDE.md
         # §4) — except for the handful of feats that have no English name at
         # all, where it is the only name there is; see `feat_name/1`.
         ru: nil,
         # Raw Fandom filename off the `{{feat}}` template's `icon=` parameter
         # ("Ife_alertness.gif"), `nil` for the 23 feats whose page carries
         # none — one page per whole *tiered family* on Fandom (`Automatic
         # quicken spell`, `Epic skill focus`…), not a parsing gap (AGENT_QUEUE.md
         # 3.50). A presentational asset, not a rule, so nothing in `rules/`
         # ever reads this field — `BuildCalculatorWeb.Builder.Icons` resolves
         # it against `priv/rules/vanilla/icons.json` (provenance, sha1,
         # licensing) which is deliberately *not* wired into the ruleset at all.
         icon: f["icon"],
         # Fandom's own "Specifics" prose — what the feat DOES, not what it
         # takes to get it (`prereq_raw` is the separate field for that, and
         # `mix wiki.parse` never mixes the two: measured across all 299,
         # zero false positives — task 3.87). Wiki markup stripped here, not
         # at parse time, for the same reason `school_raw` keeps its markup
         # in `vanilla/spells.json` until `Loader.Spells` reads it: the JSON
         # snapshot is meant to diff against the source page byte for byte.
         # `nil` for a page that states none, which is nobody's among the
         # 299 today.
         description: strip_wiki_prose(f["description"]),
         # `type` is the raw wiki label ("general", "class", "metamagic", ...).
         # `epic?` is the reliable flag; slot acceptance uses both.
         type: f["type"],
         epic?: f["epic"] == true,
         # Switched off by the shard: it exists on Fandom and in old shared
         # builds, but no character may take it. Kept in the dictionary so its
         # name still resolves and `unlocks` can be corrected; refused by
         # `Rules.FeatSlots`, which is what "нельзя взять" means mechanically.
         disabled?: false,
         # Whether a level-up may spend a slot on it at all. `false` is the
         # shard's «Умение нельзя выбрать при росте персонажа» — a **third**
         # thing beside `disabled?` and a class's `unavailable_feats`: the feat
         # exists and works, it simply arrives on an item and never through a
         # slot (`siala_41/feats.json`, `what: "level_up_selectable"`). Never
         # touches a declaration under «Вещи» (`Rules.GearFeats`), which is the
         # only route such a feat has into a build.
         level_up_selectable?: true,
         # How the feat is used ("automatic", "selected", …) verbatim off the
         # page. Descriptive: nothing is derived from it, so a value the parser
         # could not classify costs a `use_raw` and no rule.
         use: f["use"],
         use_raw: f["use"],
         bonus_for: MapSet.new(Enum.map(f["bonus_for"] || [], &atom/1)),
         # The exception carved out of the line above, as `{class, choice}` pairs:
         # a class whose bonus slot takes this feat, except when it is taken with
         # that value. One record fills it today — «''Epic skill focus'' in ''use
         # magic device'' cannot be selected as a rogue [[bonus feat]], but
         # otherwise bonus feat availability matches [[general feat]]
         # availability» (`fandom:Epic skill focus`) — and a **pair** is the shape
         # because both halves of that sentence are narrow: the general slot on a
         # rogue level still takes it, and the rogue bonus slot still takes every
         # other skill. Read by `Rules.FeatSlots.choice_refusals/4`; filled from
         # `vanilla/feat_requirements.json`, never from a feat page's own
         # parameters, which say nothing about values.
         bonus_for_except: MapSet.new(),
         # Классы, которые выдают фит САМИ (`classN` на Fandom), — не «кому он
         # доступен». Разница не косметическая: у `Cleave` стоит `class1=monk`
         # при `special=Monks receive this feat at first level`, и правило,
         # построенное на прежнем имени `available_to`, отняло бы Cleave у всех,
         # кроме монаха. Правило на этом поле не построено ни одно, и строить
         # его без сверки с `granted_feats` класса нельзя: поле шире их на 69 пар
         # (в основном владения бронёй и оружием), потому что у класса та же
         # выдача написана прозой в `proficiencies_raw` и не разобрана.
         granted_by: MapSet.new(Enum.map(f["granted_by"] || [], &atom/1)),
         prereq_raw: f["prereq_raw"],
         # Structured prerequisites, read off the same prose by `mix wiki.parse`:
         # the keys `Rules.LevelUp` documents plus `character_level`, and an
         # `unparsed` list of the fragments the schema cannot carry. `nil` means
         # the page states none at all.
         prereqs: f["prereqs"],
         # Which feats this one is a prerequisite of — the reverse of every
         # `prereqs.feats` in the file (CLAUDE.md §6, the "→ N" badge).
         unlocks: Enum.map(f["unlocks"] || [], &atom/1),
         # `nil` for all but a handful: the feat may be taken more than once,
         # each time with a different value of `choice`. See `repeatable/2`.
         repeatable: repeatable(f["repeatable"], nil, nil, "vanilla/feats.json: #{f["id"]}"),
         # ⚠️ Здесь стояли пять полей — `skill_bonuses`, `unmodelled_skill_bonus`,
         # `hp_bonus`, `hp_bonus_covers_feat?`, `unmodelled_hp_bonus`, — в которые
         # вливались `feat_skill_bonuses.json` и `feat_hp_bonuses.json`. Задача 3.25
         # перевела оба файла на общую форму, и записи живут списками в
         # `ruleset.skill_bonuses` / `ruleset.hp_bonuses`, как у четырёх остальных
         # файлов разметки. Поля удалены, а не оставлены пустыми: разметка,
         # прочитанная двумя способами, — это два места, где вердикт может
         # разойтись с провенансом, и ровно из-за этой формы у HP и навыков не было
         # ни вида источника, ни стороны капа (см. moduledoc `Rules.FeatBonuses`).
         source: f["source"],
         # The shard layer, same contract as a class's: everything the shard's
         # page says, and the subset of it that reached no mechanical home.
         siala_only?: false,
         siala_changes: [],
         siala_unapplied: [],
         siala_source: nil
       }}
    end)
  end

  @doc """
  Normalises the optional `repeatable` block on a feat record.

      "repeatable": {"choice": "creature_type", "quote": "…", "source": {…}}
      "repeatable": {"choice": null, "quote": "…", "source": {…}}

  Absent — which is every feat until the data says otherwise — means the feat is
  taken once, exactly as before.

  ## Two kinds of repetition, and the key that tells them apart

  `"choice"` **present and null** is an answer: the parser read the page and
  found a feat that repeats while naming nothing. Sixteen of them exist and they
  are not exotic — `Epic toughness` is taken ten times on an ordinary epic build,
  and so are the six `Great …`. Their repetition is a **count**: another slot
  spent is another take, and there is no parameter to record.

  `"choice"` **missing entirely** is the opposite and stays unreadable (`nil`
  plus a gap): nothing was said about the domain, so nothing may be assumed
  about it either way.

  ## `distinct?` is a question about the domain

  It says whether two picks must differ, and defaults to **true**, which is what
  this family's pages say in as many words ("It applies to a different school of
  magic in each case"). ⚠ Not universal: `Epic energy resistance` reads «may be
  taken multiple times, to a maximum of 100 resistance to each damage type»,
  i.e. the *same* type again. So the default is recorded as an assumption and
  `"distinct": false` turns it off for the feats that stack.

  With **no** domain the question has no answer — there is nothing for two picks
  to differ in — so it is `nil` rather than a boolean nobody meant, and the
  assumption is not recorded against such a feat.

  ## `max_takes` — прочитано или сосчитано, но никогда не выдумано

  Потолок взятий почти нигде не написан во взятиях: страницы называют предел
  ЭФФЕКТА («up to a maximum of 200 hit points», «to a maximum of +10»), а эффект
  фита ядро не моделирует вовсе (см. `Rules.FeatChoices`). Правдоподобная
  десятка — ровно то число, которое CLAUDE.md §3 запрещает выдумывать, поэтому
  потолок применяется только там, где он в данных записан:

      "max_takes": {"value": 3, "status": "verified",
                    "quote": "may be taken up to three times"}
      "max_takes": {"value": 3, "status": "derived", "quote": "…",
                    "from": {"counted": "tiers",
                             "tiers": ["Automatic quicken spell I", "…II", "…III"]}}

  `verified` — число НАЗВАНО (страницей или игроком), и показывать нечего.
  `derived` — число ПОЛУЧЕНО работой, и работа обязана лежать рядом, в `from`,
  чтобы её перепроверил и человек, и машина. Всё остальное — голое число, запись
  со статусом `unclear` — не читается, и билд честно говорит, что потолок
  неизвестен (`{:missing_data, {:feat_max_takes, id}}`).

  ### `from` — тег операции плюс её работа, а не «какие-то ключи»

  ⚠ Одно имя поля несло две разные формы: этот докстринг описывал ДВА ЧИСЛА
  эффекта (`{"per_take": 20, "maximum": 200}`, потолок делением), а в данных
  лежало перечисление ступеней. Читатель, спросивший `from["per_take"]` у второй
  формы, получал бы `nil` и шёл дальше — то есть форма угадывалась по ключам.
  Теперь `from` ВСЕГДА тегирован: `counted` называет операцию из закрытого
  набора, остальные ключи — её работа, и читается это разбором по тегу
  (`max_takes_from!/2`), а не пробой ключей. Смешанная запись роняет сборку.

  Операция сегодня ровно одна — `tiers`: число равно длине перечисления
  именованных ступеней, которое страница даёт вместо числа (три
  `Automatic *_spell`). Загрузчик сам сверяет `length(tiers) == value` — иначе
  «derived» было бы словом, а не проверяемым утверждением.

  ⚠ Деление эффекта на прибавку за взятие (`200 / 20 = 10`) операцией НЕ
  заведено — сознательно, а не по недосмотру. Ни одна запись его не использует,
  а данные прямо запрещают этот вывод: «выводить взятия из эффекта мы не имеем
  права — число названо игроком прямо» (`siala_41/feats.json`,
  `epic_energy_resistance`). Абзац выше говорит то же самое. Понадобится — это
  одна ветка `max_takes_from!/2` плюс имя в `@max_takes_counted`, и вместе с
  ними придётся решить, откуда взялось право делить.
  """
  @spec repeatable(term()) :: map() | nil
  def repeatable(block), do: repeatable(block, nil, nil, nil)

  @doc """
  The same, with the provenance the hand-written layer keeps beside the value.

  A fact Дан gave from play carries its source and its status on the **change**
  rather than inside the value (`priv/rules/siala_41/feats.json`), and the block
  that comes out of it must not read as if it came off a page, nor as if a guess
  had been checked. `status` is `"verified"` — he watched it in game — or
  `"unclear"` — he said outright he was not sure; the second is applied all the
  same and reported against any build that takes the feat.
  """
  @spec repeatable(term(), term(), term()) :: map() | nil
  def repeatable(block, fallback_source, status),
    do: repeatable(block, fallback_source, status, nil)

  @doc """
  То же, плюс метка записи для сообщения сторожа.

  `where` не участвует в чтении ни одним битом — он нужен только затем, чтобы
  упавшая сборка называла запись, а не заставляла искать её по трём файлам
  фитов руками. Остальные сторожа загрузчика печатают файл и id так же.
  """
  @spec repeatable(term(), term(), term(), String.t() | nil) :: map() | nil
  def repeatable(nil, _fallback_source, _status, _where), do: nil

  def repeatable(%{} = block, fallback_source, status, where) do
    # ⚠️ Сторож зовётся ДО разбора домена, а не внутри ветки с ответом: блок
    # с нечитаемым `choice` в ruleset не едет вовсе, и битый `from` в нём иначе
    # никогда бы не всплыл — то есть проверка молчала бы ровно там, где запись
    # уже недописана.
    ceiling = max_takes!(block, where)

    case repeat_domain(block) do
      :unreadable ->
        nil

      domain ->
        %{
          choice: domain,
          distinct?: distinct(domain, block),
          distinct_stated?: is_boolean(block["distinct"]),
          max_takes: ceiling,
          quote: block["quote"],
          source: block["source"] || fallback_source,
          status: block["status"] || status
        }
    end
  end

  def repeatable(_other, _fallback_source, _status, _where), do: nil

  # `Map.fetch` and not `block["choice"]`: an absent key and a null one are two
  # different statements here and reading them the same way is what would let a
  # block nobody finished become a feat every duplicate slips through.
  defp repeat_domain(block) do
    case Map.fetch(block, "choice") do
      {:ok, choice} when is_binary(choice) and choice != "" -> atom(choice)
      {:ok, nil} -> nil
      _absent_or_malformed -> :unreadable
    end
  end

  defp distinct(nil, _block), do: nil

  defp distinct(_domain, block) do
    if is_boolean(block["distinct"]), do: block["distinct"], else: true
  end

  # Read only with a status a human put there, exactly like `stat_caps/1`: the
  # whole point of the field is that somebody decided the number, and an entry
  # still marked `unclear` is a decision nobody made.
  #
  # ⚠️ `from` проверяется независимо от того, читается ли сегодня само число:
  # запись, которую сейчас пропускают (`unclear`, голое число в `value`), завтра
  # дозреет до `verified`, и битый `from` вылез бы уже ПОСЛЕ правки статуса — за
  # которой никто не станет искать вторую ошибку. Именно так вторая форма `from`
  # и прожила незамеченной.
  defp max_takes!(%{"max_takes" => %{} = entry}, where) do
    from = max_takes_from!(entry, where)

    if is_integer(entry["value"]) and entry["value"] > 0 and
         entry["status"] in ~w(verified derived) do
      %{
        value: entry["value"],
        status: entry["status"],
        # Работа, которой получено число: разобранная и сверенная, а не
        # пронесённая сырьём. `nil` у `verified` — не пропуск, а утверждение
        # «показывать нечего, число названо».
        from: from,
        quote: entry["quote"],
        source: entry["source"]
      }
    end
  end

  # Голое число вместо блока не читается и НЕ роняет сборку — так же, как запись
  # без статуса. Это не порча формы, а недописанная запись: у неё нет ни
  # провенанса, ни цитаты, и правильный ответ на неё — «потолок неизвестен».
  defp max_takes!(_block, _where), do: nil

  # Операции, которыми потолок бывает ПОЛУЧЕН. Набор закрытый и сегодня в нём
  # одна: `from` с чужим тегом роняет сборку, а не читается наугад.
  #
  # ⚠️ Список нужен сообщениям об ошибке, а решают дело ветки
  # `read_max_takes_from!/3` — то есть имя и ветка заводятся ОДНОЙ правкой.
  # Разъехаться они могут только в безопасную сторону: имя без ветки всё равно
  # получит отказ, просто с сообщением, называющим операцию известной.
  @max_takes_counted ~w(tiers)

  # Пара «показанная работа ↔ статус» — в обе стороны, и обе половины нужны.
  # `derived` без `from` — число, полученное работой, которой никто не показал:
  # перепроверить его нечем, а статус утверждает обратное. `from` при
  # `verified` — работа под числом, которое просто прочитано со страницы, то
  # есть арифметика, которой не было. Смешанная запись роняет сборку раньше,
  # чем кто-нибудь начнёт гадать, какая из двух половин верна.
  defp max_takes_from!(entry, where) do
    case {entry["from"], entry["status"]} do
      {nil, "derived"} ->
        raise """
        #{max_takes_where(where)}: max_takes says status "derived" and shows no `from`. \
        A count worked out is a count somebody has to be able to re-check — put the work \
        beside it (#{inspect(@max_takes_counted)}), or say "verified" if the source states \
        the number outright.
        """

      {nil, _status} ->
        nil

      {%{} = from, "derived"} ->
        read_max_takes_from!(from, entry, where)

      {%{}, status} ->
        raise """
        #{max_takes_where(where)}: max_takes carries `from` at status #{inspect(status)}. \
        `from` is the arithmetic behind a "derived" number; at any other status there is no \
        arithmetic to show, and the two statements contradict each other.
        """

      {other, _status} ->
        raise """
        #{max_takes_where(where)}: max_takes carries from: #{inspect(other)}. \
        Expected an object naming the operation — {"counted": …, …}.
        """
    end
  end

  # ⚠️ Тег читается ПЕРВЫМ и целиком решает, что за ключи ниже. Прежняя форма
  # тега не несла вовсе, и её ключи приходилось угадывать — ровно то, ради чего
  # разводились формы.
  defp read_max_takes_from!(%{"counted" => "tiers"} = from, entry, where) do
    tiers = from["tiers"]
    extra = Map.keys(from) -- ~w(counted tiers)

    cond do
      extra != [] ->
        raise """
        #{max_takes_where(where)}: max_takes.from counts tiers and also carries \
        #{inspect(Enum.sort(extra))}. One record states one operation: keys of a second one \
        beside it mean nobody knows which of the two produced the number.
        """

      not tier_list?(tiers) ->
        raise """
        #{max_takes_where(where)}: max_takes.from says counted: "tiers" and carries \
        tiers: #{inspect(tiers)}. Expected the distinct, non-empty names the page lists \
        instead of a number — that list IS the arithmetic.
        """

      length(tiers) != entry["value"] ->
        raise """
        #{max_takes_where(where)}: max_takes says #{inspect(entry["value"])} and counts \
        #{length(tiers)} tiers. The work shown does not produce the number recorded — one of \
        the two is wrong, and reading either would be a guess.
        """

      true ->
        %{counted: :tiers, tiers: tiers}
    end
  end

  defp read_max_takes_from!(%{"counted" => other}, _entry, where) do
    raise """
    #{max_takes_where(where)}: max_takes.from says counted: #{inspect(other)}, which is not \
    one of #{inspect(@max_takes_counted)}. An unknown operation cannot be checked, so its \
    number cannot be trusted — add the operation to `max_takes_from!/2` together with the \
    check that re-does its arithmetic, or fix the spelling.
    """
  end

  defp read_max_takes_from!(_untagged, _entry, where) do
    raise """
    #{max_takes_where(where)}: max_takes.from names no `counted`, so which operation produced \
    the number is anybody's guess. Every `from` states its operation — see \
    #{inspect(@max_takes_counted)}.
    """
  end

  # Ступени — это подписи со страницы, а не идентификаторы, поэтому проверяется
  # только то, что перечисление годится в счёт: непустое, из непустых строк и
  # без повторов. Повтор здесь тише всего: он молча завысил бы потолок.
  defp tier_list?(tiers) do
    is_list(tiers) and tiers != [] and
      Enum.all?(tiers, &(is_binary(&1) and String.trim(&1) != "")) and
      Enum.uniq(tiers) == tiers
  end

  defp max_takes_where(nil), do: "a feat's repeatable block"
  defp max_takes_where(where), do: where

  # --------------------------------------------------- vanilla feat requirements --

  # The hand-written layer over a feat's own prerequisites
  # (`vanilla/feat_requirements.json`), mirroring `apply_class_requirements/3`
  # below: same two-guard drift protection, same three verdicts, same reason
  # for existing — a page states a restriction somewhere other than the
  # requirements block a parser can read.
  #
  # A feat has nothing to merge key by key, unlike a class: its `prereq=` is
  # one template parameter, not several labelled ones, so an entry here states
  # what the *whole* `prereqs` map becomes rather than adding one field to it.
  # `replaces` is compared against that whole value for the same reason —
  # byte for byte, guarding against the page moving under the entry and
  # against `mix wiki.parse` learning to read the prose itself.
  #
  # ## Two things an entry may state, and only one of them is a prerequisite
  #
  # `requirements` is a prerequisite: a fact about the **character**, checked by
  # `Rules.Prereqs`. `only_on_class_levels` is not — it is a fact about the
  # **level the slot sits on** («This feat can only be selected when leveling as
  # a barbarian», `fandom:Mighty rage`), and it is applied by turning it into the
  # complement: every class *not* named refuses the feat on its own levels, which
  # is exactly the `unavailable_feats` set `Rules.FeatSlots` already reads.
  #
  # ⚠ The complement is not a guess, and that is why no new reason form was
  # invented for it. Fandom states this same rule from the class side too — «These
  # general feats cannot be selected when taking a level of fighter» — for the
  # four non-epic members of the family (`divine_might`, `divine_shield`,
  # `quicken_spell`, `weapon_specialization`), and for all four the class pages'
  # bans equal the complement of the feat page's positive sentence **exactly**:
  # nothing missing, nothing extra, on both rulesets (measured 10.08.2026). The
  # epic members are invisible from the class side — the label lists ordinary
  # general feats only, so nine epic feats had no restriction at all.
  #
  # Computed against the ruleset's own class map rather than written out as a
  # 22-item ban list, which is what makes it fail **safe**: a class added later is
  # refused by default instead of quietly qualifying.
  def apply_feat_requirements(feats, :missing, _raw_feats, _raw_classes), do: {feats, []}

  def apply_feat_requirements(feats, %{"feats" => entries}, raw_feats, raw_classes)
      when is_list(entries) do
    raw = Map.new(raw_feats, fn f -> {atom(f["id"]), f["prereqs"]} end)
    classes = Map.new(List.wrap(raw_classes), fn c -> {c["id"], c} end)

    Enum.reduce(entries, {feats, []}, fn entry, {acc, facts} ->
      id = atom(entry["id"])

      feat =
        Map.get(acc, id) ||
          raise "feat_requirements.json names #{entry["id"]}, which is not a feat"

      verify_feat_replaced!(entry, Map.get(raw, id))

      case entry["verdict"] do
        "applied" ->
          verify_qualifying_class_levels!(entry)
          verify_class_level_witnesses!(entry, classes)

          applied = %{
            feat
            | prereqs: applied_feat_requirements(entry, feat),
              bonus_for_except: bonus_for_except(entry, feat)
          }

          {Map.put(acc, id, applied), facts ++ only_on_class_levels(entry, id)}

        # Same shape as a class's `not_binding`: the restriction was read and
        # checking it would change nothing, because the feat already refuses
        # everyone on a different, unrelated `prereqs.unparsed` fragment
        # (`skill_focus`, `improved_sneak_attack`). Unlike a class there is no
        # `requirements_unsupported` list to close here — a feat's gap comes
        # from `Rules.Prereqs.unread/1` reading `prereqs` at check time, not
        # from a list the loader keeps — so the only effect left is the guard
        # below and the drift check every verdict gets.
        "not_binding" ->
          refuse_witnesses_without_requirements!(entry)

          if entry["requirements"] not in [nil, %{}] do
            raise """
            feat_requirements.json: #{entry["id"]} is "not_binding" but states requirements. \
            A requirement that binds nothing has nothing to check — use "applied" if it does.
            """
          end

          {acc, facts}

        # `not_modelled`: the entry is documentation. `prereqs` stays exactly
        # what `mix wiki.parse` read.
        _not_modelled ->
          refuse_witnesses_without_requirements!(entry)
          {acc, facts}
      end
    end)
  end

  def apply_feat_requirements(feats, _other, _raw_feats, _raw_classes), do: {feats, []}

  # The classes on whose levels the feat may be picked — `[]` when the entry does
  # not state it, which is most of them. Named `only_on_class_levels` and not
  # `unavailable_for_classes` (the shard layer's key) because that is the shape
  # the **source** uses: the sentence names who may, and the complement is
  # derived here rather than transcribed by hand.
  defp only_on_class_levels(entry, id) do
    case entry["only_on_class_levels"] do
      nil ->
        []

      classes when is_list(classes) and classes != [] ->
        [{:forbid_for_all_but, id, MapSet.new(Enum.map(classes, &atom/1))}]

      other ->
        raise """
        feat_requirements.json: #{entry["id"]} states only_on_class_levels #{inspect(other)}, \
        which is not a non-empty list of class ids. An empty list would say "no level of any \
        class may pick it" — that is `level_up_selectable?`, a different fact.
        """
    end
  end

  # The sixth family, and the only one whose two keys state **the same sentence**
  # at two strengths (task 3.31): `qualifying_class_levels` inside `requirements`
  # is the exact condition (this level's class, and enough of its levels), and
  # `only_on_class_levels` beside it is its upper bound (a class that could never
  # qualify does not offer the feat in a general slot at all).
  #
  # Two keys are on purpose — see the file's `_note` — but two **lists** are not:
  # the day one is edited and the other is not, a class would be refused by the
  # coarse rule while the exact one thinks it qualifies, or the reverse. Neither
  # shows up in any number, so it raises here rather than being reported.
  defp verify_qualifying_class_levels!(entry) do
    thresholds = get_in(entry, ["requirements", "qualifying_class_levels"])
    allowed = entry["only_on_class_levels"]

    if is_map(thresholds) and is_list(allowed) do
      named = thresholds |> Map.keys() |> Enum.sort()

      unless named == Enum.sort(allowed) do
        raise """
        feat_requirements.json: #{entry["id"]} names #{inspect(named)} in \
        qualifying_class_levels and #{inspect(Enum.sort(allowed))} in only_on_class_levels. \
        Both stand for one sentence of the page ("only when gaining a level in the qualifying \
        class"), so the two lists have to be the same list — one of them was edited alone.
        """
      end
    end

    :ok
  end

  # ------------------------------------- ступень фита, переведённая в уровень --

  # СЕДЬМАЯ семья файла (задача 3.103), и единственная, у которой перевод
  # проверяется машиной, а не подписывается цитатой.
  #
  # Требование называет СТУПЕНЬ («sneak attack (+8d6)», «wild shape 6x/day»),
  # схема умеет требовать фит, но не ступень, а страница КЛАССА эту же ступень
  # печатает своей таблицей — колонкой прогрессии («Sneak attack: 8d6» на воре
  # 15) либо рангом выданного фита (`wild shape (6x/day)` на друиде 18). Запись
  # называет клетку и уровень, на котором она впервые появляется; здесь это
  # СВЕРЯЕТСЯ с таблицей, и расхождение роняет сборку.
  #
  # ⚠ Разница с `mighty_rage` и `improved_ki_strike_4` — не в доверии к записи,
  # а в том, чем она держится. Там перевод сделала ПРОЗА («This is when the feat
  # called "greater rage (6x per day)" is acquired»), и проверить его можно
  # только глазами. Здесь его делает таблица той же вики, то есть данные, —
  # значит проверку можно и нужно выполнять при каждой сборке. Число в записи
  # остаётся: выведенное на лету число не отревьюишь, а сверенное — да.
  #
  # ⚠ Сверяются ДВЕ вещи, и вторая важнее первой: клетка таблицы (не сдвинулась
  # ли колонка под записью) и то, что записанный уровень ДЕЙСТВИТЕЛЬНО стоит
  # в `requirements` как `class_levels[класс]` — сам или в ветке `any_of`. Без
  # второй половины свидетель и требование разъехались бы молча, ровно как это
  # уже умеют делать `qualifying_class_levels` и `only_on_class_levels`
  # (`verify_qualifying_class_levels!/1` рядом).
  defp verify_class_level_witnesses!(entry, classes) do
    case entry["class_level_witnesses"] do
      nil ->
        :ok

      list when is_list(list) and list != [] ->
        Enum.each(list, &verify_one_witness!(entry, &1, classes))

      other ->
        raise """
        feat_requirements.json: #{entry["id"]} states class_level_witnesses #{inspect(other)}, \
        which is not a non-empty list. An empty list would say "this translation rests on \
        nothing" — that is simply leaving the key out, and the entry then rests on its quote.
        """
    end
  end

  defp verify_one_witness!(entry, witness, classes) when is_map(witness) do
    class = witness["class"]
    level = witness["level"]
    cell = witness["cell"]

    unless is_binary(class) and is_integer(level) and level >= 1 and is_binary(cell) do
      raise """
      feat_requirements.json: #{entry["id"]} states a class_level_witness #{inspect(witness)} \
      without a class id, a positive class level and the table cell it stands for. All three \
      are the witness — one missing turns the check into a formality.
      """
    end

    raw_class =
      Map.get(classes, class) ||
        raise "feat_requirements.json: #{entry["id"]} witnesses class #{inspect(class)}, " <>
                "which vanilla/classes.json does not name"

    case entry |> witness_levels(witness, raw_class) |> Enum.sort() do
      [^level | _rest] ->
        :ok

      [] ->
        raise """
        feat_requirements.json: #{entry["id"]} says #{class}'s table reads #{inspect(cell)} \
        at class level #{level}, and #{witness_where(witness)} never reads it at all. The page \
        moved under the entry — reread it before touching the number.
        """

      [first | _rest] ->
        raise """
        feat_requirements.json: #{entry["id"]} says #{class} first reads #{inspect(cell)} \
        in #{witness_where(witness)} at class level #{level}, but the table first reads it at \
        #{first}. A threshold is the FIRST level that satisfies it, so this is a real \
        disagreement, not a matter of taste.
        """
    end

    verify_witness_used!(entry, class, level)
  end

  defp verify_one_witness!(entry, other, _classes) do
    raise "feat_requirements.json: #{entry["id"]} states a class_level_witness " <>
            "#{inspect(other)}, which is not an object"
  end

  # Каждый уровень класса, на котором названная клетка читается именно так,
  # по возрастанию. Обе таблицы — обычная и эпическая — читаются одним списком:
  # у престижных классов ступень часто доезжает до нужного числа только
  # в эпической половине (у Чёрного стража +8d6 стоит на 25-м).
  defp witness_levels(entry, %{"progression_column" => column} = witness, class)
       when is_binary(column) do
    refuse_two_witness_forms!(entry, witness)

    for row <- progression_rows(class),
        get_in(row, ["extra", column]) == witness["cell"],
        do: row["level"]
  end

  # ⚠ `granted_feat_ranks` — карта, а карта не упорядочена; сортировка здесь
  # не косметика, а само утверждение: порог — ПЕРВЫЙ уровень, на котором клетка
  # читается так, и без сортировки «первый» означал бы «какой попался».
  defp witness_levels(entry, %{"granted_feat_rank" => feat} = witness, class)
       when is_binary(feat) do
    refuse_two_witness_forms!(entry, witness)

    for {level, ranks} <- Map.get(class, "granted_feat_ranks") || %{},
        is_map(ranks),
        Map.get(ranks, feat) == witness["cell"],
        {number, ""} <- [Integer.parse(to_string(level))],
        do: number
  end

  defp witness_levels(entry, witness, _class) do
    raise """
    feat_requirements.json: #{entry["id"]} states a class_level_witness #{inspect(witness)} \
    with neither progression_column nor granted_feat_rank. Which table the cell sits in is \
    what makes the witness checkable — a witness that names no table verifies nothing.
    """
  end

  defp refuse_two_witness_forms!(entry, witness) do
    if is_binary(witness["progression_column"]) and is_binary(witness["granted_feat_rank"]) do
      raise """
      feat_requirements.json: #{entry["id"]} states a class_level_witness naming BOTH \
      progression_column and granted_feat_rank. Two addresses for one cell means one of them \
      is silently unread, and which one is an implementation detail — say the one that holds.
      """
    end
  end

  defp progression_rows(class) do
    (List.wrap(class["progression"]) ++ List.wrap(class["epic_progression"]))
    |> Enum.filter(&(is_map(&1) and is_integer(&1["level"])))
    |> Enum.sort_by(& &1["level"])
  end

  defp witness_where(%{"progression_column" => column}) when is_binary(column),
    do: "the progression column #{inspect(column)}"

  defp witness_where(%{"granted_feat_rank" => feat}) when is_binary(feat),
    do: "the granted-feat rank of #{inspect(feat)}"

  # Свидетель, которым ничего не подписано, — украшение. Уровень обязан стоять
  # в требованиях: либо прямо, либо веткой дизъюнкции.
  defp verify_witness_used!(entry, class, level) do
    stated = class_level_thresholds(entry["requirements"], class)

    unless level in stated do
      raise """
      feat_requirements.json: #{entry["id"]} witnesses #{class} #{level}, and its requirements \
      ask for #{inspect(stated)} of that class. The witness exists to hold the number in \
      `requirements` to the page's own table; a witness nobody's requirement uses holds nothing.
      """
    end
  end

  defp class_level_thresholds(%{} = block, class) do
    direct = get_in(block, ["class_levels", class])
    branches = for b <- List.wrap(block["any_of"]), is_map(b), do: b

    Enum.reject([direct | Enum.flat_map(branches, &class_level_thresholds(&1, class))], &is_nil/1)
  end

  defp class_level_thresholds(_absent, _class), do: []

  # `class_level_witnesses` под невыполняемым вердиктом — запись, которую код
  # молча не прочитает: тот же вид лжи, что `only_on_class_levels` на записи
  # `not_binding` (разбор — в самой записи `dragon_shape` до задачи 3.103).
  defp refuse_witnesses_without_requirements!(entry) do
    if entry["class_level_witnesses"] not in [nil, []] do
      raise """
      feat_requirements.json: #{entry["id"]} states class_level_witnesses under verdict \
      #{inspect(entry["verdict"])}. A witness holds a number in `requirements` to the class \
      table, and this verdict states no requirements — the record would never be read.
      """
    end
  end

  # `not_in_class_bonus_slot_for_skill` — the file's fifth family, and the only
  # one that is about a **slot** rather than about the character or the level:
  #
  #   «''Epic skill focus'' in ''use magic device'' cannot be selected as a rogue
  #   [[bonus feat]], but otherwise bonus feat availability matches [[general
  #   feat]] availability» — `fandom:Epic skill focus`, Notes.
  #
  # Written the way the source writes it (the value, then who refuses it) and
  # turned into `{class, choice}` pairs, because the pair is what is refused: the
  # general slot on a rogue level takes the same value, and the rogue bonus slot
  # takes every other skill. Both halves of that are load-bearing — a shape that
  # dropped either would ban more than the sentence does.
  #
  # ⚠ No complement is computed here, unlike `only_on_class_levels`. That one
  # names who **may** and the ban is everyone else; this one names who **may
  # not**, and inverting it would forbid the pair in the bonus slots of the four
  # other classes the feat is a bonus feat for — which the same sentence allows
  # in as many words.
  defp bonus_for_except(entry, feat) do
    case entry["not_in_class_bonus_slot_for_skill"] do
      nil ->
        feat.bonus_for_except

      %{} = by_skill when map_size(by_skill) > 0 ->
        MapSet.new(
          for {skill, classes} <- by_skill,
              class <- verified_bonus_slot_classes!(entry, skill, classes),
              do: {class, atom(skill)}
        )

      other ->
        raise """
        feat_requirements.json: #{entry["id"]} states not_in_class_bonus_slot_for_skill \
        #{inspect(other)}, which is not a non-empty map of "value" => [class ids]. \
        An empty one would state a restriction that restricts nothing.
        """
    end
  end

  # The class list of one such record. Names are checked against the finished
  # dictionaries later (`verify_choice_class_restrictions!/3`, which sees both);
  # here only the shape, because a bare string where a list belongs would
  # otherwise be silently skipped by the comprehension above.
  defp verified_bonus_slot_classes!(entry, skill, classes) do
    unless is_list(classes) and classes != [] do
      raise """
      feat_requirements.json: #{entry["id"]} states not_in_class_bonus_slot_for_skill for \
      #{skill} as #{inspect(classes)}, which is not a non-empty list of class ids. An empty \
      list would say "no class's bonus slot refuses it" — that is simply leaving the value out.
      """
    end

    Enum.map(classes, &atom/1)
  end

  defp verify_feat_replaced!(entry, actual) do
    if Map.has_key?(entry, "replaces") and entry["replaces"] != actual do
      raise """
      feat_requirements.json: #{entry["id"]} says vanilla/feats.json read #{inspect(entry["replaces"])} \
      for "prereqs", but it now reads #{inspect(actual)}. The page moved under the entry, or \
      mix wiki.parse learned to read it by itself — reread the page and rewrite or delete the entry.
      """
    end
  end

  # The replacement block goes through the same filter the machine layer's own
  # `prereq=` reading does, so a key `Rules.Prereqs` does not know cannot be
  # smuggled in under a verdict of `applied`. Feats keep string keys — unlike
  # a class's, this block is handed to `Rules.Prereqs.check/2` untouched (see
  # its moduledoc: "Keys arrive as strings from a feat").
  #
  # ⚠ An `applied` entry may state `only_on_class_levels` (or the slot exception
  # `not_in_class_bonus_slot_for_skill`) **instead of** `requirements`, and then
  # `prereqs` is left exactly as parsed.
  #
  # ⚠ Здесь стояло «nine of the thirteen feats in that family have no unread
  # prerequisite at all, only an unread restriction on which level may spend the
  # slot» — **число не воспроизводится ни в какой момент истории**, и способа
  # счёта у него названо не было. Похоже, оно устарело задачей 3.31, когда шесть
  # эпических заклинаний получили `requirements`, — но проверить это нечем,
  # потому что единица измерения не названа. Ровно тот случай, о котором
  # предупреждает CLAUDE.md §9: число без названного способа счёта не стареет,
  # оно просто перестаёт быть правдой, оставаясь на месте.
  #
  # Пересчитано 17.08.2026 обходом `vanilla/feat_requirements.json` (единица —
  # ЗАПИСИ файла, не фиты категории и не пары запрета): ключ
  # `only_on_class_levels` несут **14** записей, и **5** из них стоят
  # с ограничением и без `requirements` — `epic_weapon_specialization` плюс
  # четыре эпических фита кастера, которым замер S4/S4b/S5 дал ограничение
  # в тот же день. Раньше в этой строке стояли «10» и «одна»: числа верны для
  # состояния до той правки и приведены здесь как её след, а не как ошибка.
  #
  # Such an entry still carries `replaces` and is still held
  # to it — the drift guard is what notices the day `mix wiki.parse` learns to
  # read the prose the entry was written for.
  defp applied_feat_requirements(entry, feat) do
    block = entry["requirements"]

    cond do
      is_map(block) and map_size(block) > 0 ->
        case for {key, _} <- block, key not in @requirement_keys, do: key do
          [] ->
            block

          keys ->
            raise "feat_requirements.json: #{entry["id"]} uses unknown keys #{inspect(keys)}"
        end

      states_restriction?(entry) ->
        feat.prereqs

      true ->
        raise """
        feat_requirements.json: #{entry["id"]} is "applied" but states neither requirements \
        nor a restriction (only_on_class_levels, not_in_class_bonus_slot_for_skill). \
        An applied entry has to say what is now checked.
        """
    end
  end

  defp states_restriction?(entry) do
    (is_list(entry["only_on_class_levels"]) and entry["only_on_class_levels"] != []) or
      (is_map(entry["not_in_class_bonus_slot_for_skill"]) and
         entry["not_in_class_bonus_slot_for_skill"] != %{})
  end

  # -------------------------------------------------------- shard feat layer --

  # `priv/rules/siala_41/generated/feats.json` (66 pages, machine-parsed) with
  # `priv/rules/siala_41/feats.json` (hand-written, absent so far) applied after
  # it — `vanilla -> siala generated -> siala manual`, per the README beside the
  # files. Order is the whole mechanism: a later fact of the same `what` simply
  # overwrites, so a human record beats the parser without any special case.
  #
  # Returns the dictionary and the facts the feat pages state about **classes** —
  # `granted_at_level` and `granted_automatically_to` (what a class hands over)
  # plus `unavailable_for_classes` (whose levels may not spend a slot on it) —
  # which the caller lays onto the class map afterwards.
  def apply_feat_layer(feats, shard) do
    aliases = feat_slot_aliases(Map.get(shard, :overrides, :missing))

    entries =
      feat_entries(Map.get(shard, :feats_generated, :missing)) ++
        feat_entries(Map.get(shard, :feats_manual, :missing))

    {feats, grants} =
      Enum.reduce(entries, {feats, []}, fn entry, {acc, grants} ->
        id = feat_target_id(entry, acc)
        base = Map.get(acc, id) || new_shard_feat(id, entry)
        changes = entry["changes"] || []
        {feat, unapplied, entry_grants} = apply_feat_changes(base, id, changes, aliases)

        {Map.put(acc, id, merge_feat_entry(feat, entry, changes, unapplied)),
         grants ++ entry_grants}
      end)

    {drop_disabled_from_unlocks(feats), grants}
  end

  @doc """
  Пул бонусных слотов класса, расширенный слоем Сиалы (задача 3.73).

  Факт лежит на странице КЛАССА («Священник может выбирать умения
  с Эпическими заклинаниями»), а ответ на вопрос «что примет бонусный слот
  класса X» во всём проекте лежит в ОДНОМ месте — `bonus_for` самого фита,
  откуда его читает `Rules.FeatSlots`. Поэтому фактом класса и правится
  `bonus_for`, а не заводится вторая карта: две карты рано или поздно
  разойдутся, и `Builder.Feats` (он тоже читает `bonus_for`) читал бы не то,
  что ядро.

  Расширение ванильное по форме: у шести эпических заклинаний `bonus_for`
  уже `[pale_master, sorcerer, wizard]`, и Сиала дописывает туда Священника
  и Друида — тем же ключом, тем же смыслом.

  ## Чего расширение НЕ делает: фит, который классу недоступен вовсе

  У двух из шести эпических заклинаний собственная страница называет
  квалифицирующие классы, и ни Священника, ни Друида среди них нет:

  > «The actual prerequisite is not the ability to cast level 9 spells, but
  > being an epic **sorcerer or wizard**, or having at least 15 pale master
  > levels. Furthermore, this feat can only be chosen **when gaining a level
  > in the qualifying class**» — `fandom:Epic spell: epic mage armor`
  > (revid 64605) и `fandom:Epic spell: epic warding` (revid 70464).

  Бонусный слот Священника сидит ровно на уровне Священника, то есть это
  предложение говорит и про него. Сиала про эти два фита не говорит ничего,
  а молчание её вики — это молчание, значит правило остаётся ванильным
  (CLAUDE.md §3). Условие читается из данных (`qualifying_class_levels`,
  `vanilla/feat_requirements.json`), а не из списка id здесь.

  ⚠ И это не «сузили ниже цитаты»: цитата шарда называет семейство, а не
  перечисляет шесть штук. Положить в пул фит, которого классу не даст ни один
  уровень, значило бы показать игроку выбор, которого в игре нет, — тот же
  довод, которым `only_on_class_levels` убирает такой фит из общего слота
  («убирает недоступный фит из списка», `vanilla/feat_requirements.json` →
  `epic_spell_dragon_knight`).

  ⚠ Категория, которая не выбрала ни одного фита, роняет сборку: словарь её
  объявил, факт класса её назвал, а расширять оказалось нечем — это опечатка
  в селекторе, а не правило шарда, и молчаливое «ничего не произошло» здесь
  неотличимо от применённого факта.
  """
  @spec widen_bonus_pools(map(), map()) :: map()
  def widen_bonus_pools(feats, classes) do
    # Порядок обхода карты классов ни на что не влияет: каждое расширение
    # добавляет СВОЙ класс в `bonus_for`, а объединение множеств коммутативно.
    for {class_id, class} <- classes,
        {category, selector} <- Map.get(class, :bonus_feat_pool_adds) || %{},
        reduce: feats do
      acc -> widen_one_pool(acc, class_id, category, selector)
    end
  end

  defp widen_one_pool(feats, class_id, category, selector) do
    selected = for {id, feat} <- feats, selects?(selector, feat), do: id

    if selected == [] do
      raise """
      siala_41/classes.json: #{class_id} расширяет бонусный пул категорией
      #{inspect(category)} (#{inspect(selector)}), а под неё не подходит ни один фит
      справочника. Пустое расширение неотличимо от применённого факта, поэтому это
      падение, а не тишина: либо селектор в `_bonus_feat_pools` разошёлся с данными,
      либо категорию назвали не тем именем.
      """
    end

    Enum.reduce(selected, feats, fn id, acc ->
      Map.update!(acc, id, fn feat ->
        if qualifies?(feat, class_id),
          do: %{feat | bonus_for: MapSet.put(feat.bonus_for, class_id)},
          else: feat
      end)
    end)
  end

  defp selects?(%{feat_type: type}, feat), do: feat.type == type

  # Пять фитов владения «Системы оружия», по реестру `weapons.json` — они
  # разрешены в id ещё при чтении словаря (`Classes.bonus_feat_pools!/2`),
  # потому что справочника фитов там ещё нет, а реестр уже есть.
  defp selects?(%{feat_ids: ids}, feat), do: MapSet.member?(ids, feat.id)

  # `qualifying_class_levels` отсутствует — страница фита про классы ничего
  # не говорит, и запрещать нечем. Есть — это закрытый список, и класса вне
  # него уровень фит не даст никогда.
  defp qualifies?(feat, class_id) do
    case Map.get(feat.prereqs || %{}, "qualifying_class_levels") do
      %{} = thresholds -> Map.has_key?(thresholds, to_string(class_id))
      _absent -> true
    end
  end

  # The two slot names `apply_feat_change/4` (`what: "feat_slots"`) recognises
  # on its own — everything else is `siala_unapplied` unless `feat_slot_aliases/1`
  # says it is a synonym for one of these.
  @bonus_slot_kinds ~w(class_bonus epic_class_bonus)

  # A raw slot name a Siala feat page uses in its own words, mapped to the kind
  # it mechanically is — read off `overrides.json` → `feats.bonus_slot_aliases`,
  # not written here. Which words on a page mean "this is the class's ordinary
  # bonus slot" is a game fact, sourced and dated like any other (today: Dan's
  # observation that the Ranger's five weapon-proficiency feats sit on the same
  # slot as `Favored enemy`, CLAUDE.md §3 — a player's own observation outranks
  # the wiki), not something this module gets to decide by itself.
  defp feat_slot_aliases(overrides) do
    case dig(overrides, ["feats", "bonus_slot_aliases", "value"]) do
      map when is_map(map) ->
        Enum.each(map, fn {raw, canonical} ->
          if canonical not in @bonus_slot_kinds do
            raise """
            overrides.json: feats.bonus_slot_aliases.#{raw} points at #{inspect(canonical)}, \
            which is not one of #{inspect(@bonus_slot_kinds)} — apply_feat_change/4 would never \
            match it, and the alias would silently keep failing to model the slot it exists to fix.
            """
          end
        end)

        map

      _ ->
        %{}
    end
  end

  # ------------------------------------------- what a feat's effect lands on --

  # `vanilla/feat_effect_receivers.json` — которую механику двигает эффект фита.
  #
  # Читатель ровно один: `Rules.FeatChoices.gaps/3` перед тем, как сказать
  # «прибавку от этого фита в статы не считаем». Утверждение верно, только если
  # прибавка падает в число, которое мы печатаем (CLAUDE.md §9), а пятнадцать
  # повторяемых фитов из восемнадцати говорили это про урон, ДЦ чужого
  # спасброска, метамагию, сопротивления и маскировку.
  #
  # ⚠ Запись отдаётся СЫРОЙ, со строковыми ключами, и это не лень: её читает
  # `Rules.GapReceivers.ours?/2` — та же функция и та же форма
  # (`%{"affects" => […]}`), что у фактов шарда. Атомизировать её значило бы
  # завести второй адаптер (`bonus_ours?/2`) для того же вопроса, а два чтения
  # одного поля расходятся молча — файлы разметки это уже проходили.
  #
  # ⚠ Всё, что файл сказал и что прочитать нельзя, роняет сборку: несуществующий
  # фит, дубль, пустая цитата, отсутствующий источник. Метка ГАСИТ оговорку,
  # то есть ошибка здесь уводит в молчание, а молчание — единственный исход,
  # который этот механизм не имеет права произвести по случайности.
  def feat_effect_receivers(:missing, _feats, _known_receivers), do: %{}

  def feat_effect_receivers(%{"feats" => entries}, feats, known_receivers)
      when is_list(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      id = atom(entry["feat"])
      name = "feat_effect_receivers.json: #{entry["feat"]}"

      unless Map.has_key?(feats, id) do
        raise """
        #{name} names a feat that does not exist. A label that labels nothing is a \
        silent no-op wearing the look of a rule — and this one's job is to take a \
        caveat off the screen.\
        """
      end

      if Map.has_key?(acc, id) do
        raise """
        #{name} is stated twice. One feat has one effect; a second record would let \
        a later edit change the answer by moving a line.\
        """
      end

      # ⚠ Пустой или отсутствующий `affects` здесь РОНЯЕТ, хотя
      # `verify_bonus_affects!/4` такую запись пропускает (у файлов разметки поле
      # стоит не у всех записей, и его отсутствие там законно). Тут запись
      # существует ровно ради метки: без неё она не делает НИЧЕГО и при этом
      # выглядит сделанной работой.
      receivers = receiver_list!(name, entry["affects"])
      receiver_quote!(name, entry["quote"])
      receiver_source!(name, entry["source"])

      # ⚠ Второй способ погасить оговорку, и он НЕ дублирует метку получателя
      # (задача 3.95). Метка говорит «числа, в которое прибавка падает, у нас
      # нет вовсе»; решение владельца — «число есть, прибавка в него сознательно
      # не идёт, и сказано об этом лучше нас». Поэтому запись с НАШИМ
      # получателем и решением — законная и ожидаемая: `affects` остаётся
      # честным (`Arcane defense` правда двигает сейвы), а гасит оговорку
      # `not_a_gap`. Судит оба одна и та же `Rules.GapReceivers.ours?/2`.
      NotAGap.verify!(name, entry["not_a_gap"],
        bases: NotAGap.bases(),
        describes: {id, feats}
      )

      FactReceivers.verify_bonus_affects!(
        "feat_effect_receivers.json",
        entry["feat"],
        receivers,
        known_receivers
      )

      Map.put(acc, id, entry)
    end)
  end

  def feat_effect_receivers(_other, _feats, _known_receivers), do: %{}

  defp receiver_list!(_name, [_ | _] = receivers), do: receivers

  defp receiver_list!(name, other) do
    raise """
    #{name} carries affects: #{inspect(other)}. Expected a non-empty list of receiver \
    ids from siala_41/classes.json's `_receivers` — a record that names no receiver \
    states nothing and should be deleted instead.\
    """
  end

  defp receiver_quote!(name, text) when is_binary(text) do
    if String.trim(text) == "", do: no_quote!(name), else: :ok
  end

  defp receiver_quote!(name, _absent), do: no_quote!(name)

  defp no_quote!(name) do
    raise """
    #{name} carries no quote. A receiver label is a claim about the mechanic, and the \
    claim has to rest on the source's own words (task 3.93: «не расставляй по догадке»).\
    """
  end

  defp receiver_source!(_name, %{} = _source), do: :ok

  defp receiver_source!(name, _absent) do
    raise "#{name} carries no source — see the file's own `_schema`."
  end

  def feat_entries(:missing), do: []
  def feat_entries(%{"feats" => list}) when is_list(list), do: list
  def feat_entries(list) when is_list(list), do: list
  def feat_entries(_other), do: []

  # Which record the page belongs to. `vanilla_id` when the parser matched one —
  # note the five `Epic energy resistance (…)` pages all carry the same one, and
  # all say the same thing, so they land on the same record rather than five
  # invented ones. Otherwise the page's own id: a feat the shard added.
  defp feat_target_id(entry, feats) do
    vanilla = atom_or_nil(entry["vanilla_id"])
    if vanilla && Map.has_key?(feats, vanilla), do: vanilla, else: atom(entry["id"])
  end

  defp new_shard_feat(id, entry) do
    %{
      id: id,
      name: nil,
      ru: nil,
      # A shard-only feat has no Fandom page and so no Fandom-hosted art
      # (`priv/rules/vanilla/icons.json` only ever names things Fandom shows) —
      # `nil` here is a fact, not a placeholder waiting to be filled in.
      icon: nil,
      # A shard-only feat has no Fandom page and so no Fandom "Specifics"
      # prose either — `nil` is a fact, not a gap: task 3.87 asked for it to
      # stay empty rather than translated from the shard's Russian prose
      # (`special_raw`), the same call CLAUDE.md §4 already makes about names
      # for these pages. The feat info popover simply does not offer itself
      # for these eleven.
      description: nil,
      type: nil,
      epic?: false,
      disabled?: false,
      level_up_selectable?: true,
      use: nil,
      use_raw: nil,
      bonus_for: MapSet.new(),
      # A shard-only feat is on nobody's bonus list, so it has no exception to
      # carve out of one either — but the key is present rather than absent,
      # because `Rules.FeatSlots` reads it off every record it is handed.
      bonus_for_except: MapSet.new(),
      granted_by: MapSet.new(),
      prereq_raw: entry["requirements_raw"],
      prereqs: nil,
      unlocks: [],
      repeatable:
        repeatable(
          entry["repeatable"],
          nil,
          nil,
          "siala_41 feat layer (#{FactReceivers.feat_source_label(entry)}): #{entry["id"]}"
        ),
      source: nil,
      siala_only?: true,
      siala_changes: [],
      siala_unapplied: [],
      siala_source: nil
    }
  end

  # `uniq` because five pages land on one record: `Epic energy resistance
  # (Acid…Sonic)` all carry `vanilla_id: epic_energy_resistance` and all say the
  # same three things, so without it the feat would carry the same fact five
  # times over. Facts that genuinely differ are kept — `Разоружение` states two
  # distinct notes and both survive.
  defp merge_feat_entry(feat, entry, changes, unapplied) do
    %{
      feat
      | ru: entry["ru"] || feat.ru,
        name: feat.name || feat_name(entry),
        use_raw: entry["use_raw"] || feat.use_raw,
        prereq_raw: entry["requirements_raw"] || feat.prereq_raw,
        # The shard layer may state repeatability the Fandom record does not, and
        # wins when it does — `vanilla -> siala generated -> siala manual`. The
        # entry's own source is the fallback for the same reason it is on a
        # change: the block must carry where it came from, `user` included.
        repeatable:
          repeatable(
            entry["repeatable"],
            entry["source"],
            entry["status"],
            "siala_41 feat layer (#{FactReceivers.feat_source_label(entry)}): #{entry["id"]}"
          ) || feat.repeatable,
        siala_changes: Enum.uniq(feat.siala_changes ++ changes),
        siala_unapplied: Enum.uniq(feat.siala_unapplied ++ unapplied),
        siala_source: entry["source"] || feat.siala_source
    }
  end

  # Six shard pages have no English name at all — the five custom weapon
  # proficiencies and the spell-school family page — and for those the wiki
  # title is not a fan translation of an engine name, it *is* the shard's name,
  # exactly as with the races (CLAUDE.md §4). Where an English name exists it
  # always wins, so no translated title ever becomes a name.
  defp feat_name(entry), do: entry["name"] || entry["ru"]

  defp apply_feat_changes(feat, id, changes, aliases) do
    Enum.reduce(changes, {feat, [], []}, fn change, {acc, unapplied, grants} ->
      case apply_feat_change(change, acc, id, aliases) do
        {:ok, updated} -> {updated, unapplied, grants}
        {:ok, updated, more} -> {updated, unapplied, grants ++ more}
        {:partial, updated} -> {updated, unapplied ++ [change], grants}
        :skip -> {acc, unapplied ++ [change], grants}
      end
    end)
  end

  defp apply_feat_change(%{"what" => "type", "value" => value}, feat, _id, _aliases)
       when is_binary(value) do
    {:ok, %{feat | type: value}}
  end

  defp apply_feat_change(%{"what" => "use", "value" => value}, feat, _id, _aliases) do
    # Carried, never derived from — `use_raw` keeps the page's own sentence, so
    # a value the parser could not classify loses nothing a rule depends on.
    {:ok, %{feat | use: value || feat.use}}
  end

  # The `Требования` block on a shard page is a **restatement**, not an
  # addendum: Epic Dodge's has no 21st level, no Tumble 30 and no Improved
  # Evasion, and merging it with vanilla's would silently keep all three. So it
  # replaces. `unclear` is applied here on purpose, unlike everywhere else —
  # the parser splits the block into the fragments it read and the ones it did
  # not, `unparsed` already forces `{:missing_data, {:feat_prerequisites, id}}`,
  # and checking the readable half beats checking nothing.
  defp apply_feat_change(%{"what" => "requirements", "value" => atoms}, feat, _id, _aliases)
       when is_list(atoms) do
    {:ok, %{feat | prereqs: shard_prereqs(atoms)}}
  end

  # «Улучшенное уклонение может взять [[Вор|вор]], начиная с 35-го уровня (а не с
  # 10-го)» — the shard moving the class level from which a feat may be **picked
  # with a slot**, one branch of the requirement at a time.
  #
  # ⚠ The whole point of this `what` is that it is **not** `feat_level_shift`, and
  # the two are one wrong reading apart. That shift (`siala_41/classes.json`)
  # moves a **hand-out**: the level at which a class gives the feat away for free.
  # This moves the **right to buy**: the feat still costs a slot, only later. The
  # rogue's line was recorded as the former and became false in both directions at
  # once — a level-10 rogue could pick a feat the page had taken away from him,
  # and a level-35 rogue was handed one he is supposed to pay a slot for. Which of
  # the two a sentence states is not decided by its verb («получает» vs «может
  # взять» is a good hint and no more) but by whether the feat has a pick path at
  # all: `bonus_for` naming a class, or a general slot accepting it. Twenty-nine
  # of the thirty shifts in the class layer name feats with no pick path
  # whatsoever, so a hand-out is the only reading those sentences can carry;
  # `Improved evasion` is the single one with `bonus_for: [:rogue]`, and the
  # single one whose page says «может взять».
  #
  # It lives on the **feat** and not beside its two neighbouring sentences in
  # `siala_41/classes.json` for the same reason `unavailable_for_classes` does:
  # what changes is a field of the feat's own requirement block, not a row of the
  # rogue's table. The class layer physically cannot express it either — a class
  # change returns a class and nothing else, while a feat change already carries
  # facts the other way (`{:move, …}`, `{:auto, …}`, `{:forbid_for, …}`).
  #
  # **Replaces one branch, keeps the rest**, unlike `requirements` above: the page
  # states a delta («а не с 10-го») rather than a full block, and writing out
  # `monk 9` / `shadowdancer 10` here to satisfy a wholesale replacement would
  # copy two vanilla numbers into the shard layer, where the next `mix wiki.parse`
  # could no longer keep them honest.
  #
  # `from` is what the record claims vanilla says, and it is **checked, not
  # decoration**. A mismatch means the page moved under the record (or the record
  # was already applied once) and the level about to be overwritten is not the one
  # a human read — so the load fails loudly instead of silently rewriting an
  # unknown number, the same bargain `verify_replaced!/3` makes for class
  # requirements.
  defp apply_feat_change(
         %{"what" => "requirement_class_level", "value" => %{} = value},
         feat,
         id,
         _aliases
       ) do
    case {value["class"], value["from"], value["to"]} do
      {class, from, to} when is_binary(class) and is_integer(from) and is_integer(to) ->
        {:ok, %{feat | prereqs: move_class_level_requirement!(feat, id, class, from, to)}}

      _incomplete ->
        :skip
    end
  end

  # «замерил, skill focus - ride присутствует» — Dan, 25.08.2026,
  # `GAME_CHECKS.md` AB1. Шард **оживил** навык (Верховая езда единственная
  # такая) и вместе с ним завёл вариант фита, которого в ванили нет вовсе.
  #
  # Не требование и не его снятие: ванильная запись говорит, что ПАРЫ «фит +
  # значение» не существует (`no_feat_variant_for_skills`, `fandom:Skill
  # focus` → «There is no skill focus in [[ride]]»), а замер говорит, что
  # на шарде она существует. Поэтому и `what` называет факт игры — вариант
  # есть, — а не операцию над нашей структурой.
  #
  # ⚠ **Дельта, а не `requirements`, и это здесь главное.** Факт `what:
  # "requirements"` ЗАМЕЩАЕТ `prereqs` целиком (см. клаузу выше и запись
  # `artist`), то есть ради одной снятой строки пришлось бы переписать в
  # сиальский слой все четыре ключа ванильной записи — вторую копию одного
  # правила, которая разъедется с первой при первой же правке ванили. Ровно
  # тот дефект, которым обернулась пара `bonus_for` / `bonus_feat_pool`
  # (ложный гэп, задача 3.85). Сосед `requirement_class_level` заведён такой
  # же дельтой и по той же причине.
  #
  # ⚠ **Умолчание ванильное, и оно возвращается само:** запись отсюда исчезнет
  # — ванильный запрет снова действует, потому что снимать его будет некому.
  # Ничего не «выключено флагом», состояние по умолчанию не тронуто.
  #
  # `from`-сторож здесь — сам факт наличия значения в ванильном списке. Записи,
  # которой нечего снимать, быть не должно: либо ванильная страница переехала
  # под записью, либо запись уже применена дважды, и в обоих случаях снятие
  # запрета оказалось бы тихим no-op, а игрок — с ответом, за которым никто
  # не стоит. Тот же обмен, что делает `move_class_level_requirement!/5`.
  defp apply_feat_change(
         %{"what" => "feat_variant_exists", "value" => %{} = value},
         feat,
         id,
         _aliases
       ) do
    case {value["domain"], value["value"]} do
      {domain, member} when is_binary(domain) and is_binary(member) ->
        {:ok, %{feat | prereqs: lift_variant_ban!(feat, id, domain, member)}}

      _incomplete ->
        :skip
    end
  end

  defp apply_feat_change(%{"what" => "disabled", "value" => true}, feat, _id, _aliases) do
    {:ok, %{feat | disabled?: true}}
  end

  # «Умение нельзя выбрать при росте персонажа» — `Riding Sprint`, `Smile of
  # Death`. Не то же, что `disabled` рядом, и разница дорогая: выключенный фит
  # нельзя ни взять, ни объявить с вещи, а этот работает — он просто приходит
  # с предмета, и объявление под «Вещами» остаётся единственным его путём
  # в билд (`Rules.GearFeats`).
  #
  # ⚠ Пока правила не было, отказ существовал КАК СЛЕДСТВИЕ ТИПА: у сиального
  # фита слот читается по блоку «Возможность взятия фита», у этих двух страниц
  # блока нет, и «страница не сказала» случайно совпало с «нельзя»
  # (`Rules.FeatSlots.general?/1`). Совпадение держалось на том, что шард не
  # трогал их `Тип навыка`.
  defp apply_feat_change(
         %{"what" => "level_up_selectable", "value" => value},
         feat,
         _id,
         _aliases
       )
       when is_boolean(value) do
    {:ok, %{feat | level_up_selectable?: value}}
  end

  # Repetition as the hand-written layer states it, **replacing** the machine
  # layer's block whole rather than merging into it. Half of one source's block
  # wearing the other's name would be readable against neither page.
  #
  # Provenance travels with the value. These are Дан's answers from play
  # (`source.kind: "user"`) — the most fragile facts in the project, unverifiable
  # against any page (CLAUDE.md §3) — so where the value names no source of its
  # own it inherits the change's, and the whole change stays in `siala_changes`
  # besides. A block whose source says `user` must never read as one off a wiki.
  #
  # ⚠ `unclear` is **applied**, unlike in the class and skill layers, and for the
  # same reason `requirements` above is: there it means the parser could not pin
  # a value down, here the value is pinned and the *confidence in it* is not —
  # «не знаю, предполагаю» is still the best answer anyone has, and refusing it
  # would leave the feat single-take, which nobody claims it is. The status rides
  # on the block instead, and a build that takes such a feat is told
  # (`Rules.FeatChoices.gaps/3`). That is the CLAUDE.md §9 hole — an `unclear`
  # fact quietly becoming a rule — closed rather than reopened.
  defp apply_feat_change(
         %{"what" => "repeatable", "value" => value} = change,
         feat,
         id,
         _aliases
       ) do
    case repeatable(
           value,
           change["source"],
           change["status"],
           "siala_41 feat layer: #{id} / repeatable"
         ) do
      nil -> :skip
      block -> {:ok, %{feat | repeatable: block}}
    end
  end

  # "Уклонение перенесено со 2-го уровня вора на 30-ый". The class layer says
  # the same thing through `feat_level_shift`; both land on the same map and
  # `move_grant/4` is idempotent, so whichever arrives second changes nothing.
  defp apply_feat_change(
         %{"what" => "granted_at_level", "value" => %{} = value},
         feat,
         id,
         _aliases
       ) do
    case {atom_or_nil(value["class"]), value["vanilla_level"], value["siala_level"]} do
      {class, from, to} when not is_nil(class) and is_integer(to) ->
        {:ok, feat, [{:move, class, from, to, id}]}

      _incomplete ->
        :skip
    end
  end

  defp apply_feat_change(
         %{"what" => "granted_automatically_to", "value" => classes},
         feat,
         id,
         _aliases
       )
       when is_list(classes) do
    {:ok, feat, for(class <- classes, do: {:auto, atom(class), id})}
  end

  # Which classes take this feat off the general list for their own levels —
  # **the whole list, replacing** whatever the class pages said, exactly the way
  # `requirements` above replaces rather than merges. `[]` is therefore a real
  # value and the interesting one: "nobody forbids it".
  #
  # It exists because a Siala page that states a feat's requirements states them
  # in full, class restrictions included (CLAUDE.md §3 — Сиала переопределяет
  # ваниль). `Brew Potion` is the measured case: the shard replaced «уровень
  # заклинателя 3» with «Знание (Lore) 4», the class ban was left vanilla, and a
  # rogue with Lore 4 was refused a feat the game offers him
  # (`GAME_CHECKS.md` H1).
  #
  # ⚠ The fact belongs to the **feat**, which is why it is one record here and
  # not fifteen edits to `siala_41/classes.json`: what was measured is that this
  # feat has no class restriction, not that fifteen classes each dropped one.
  # The mirror image of `unavailable_feats` on the class side, and the same
  # reading — a property of the level being taken, never a prerequisite.
  defp apply_feat_change(
         %{"what" => "unavailable_for_classes", "value" => classes},
         feat,
         id,
         _aliases
       )
       when is_list(classes) do
    {:ok, feat, [{:forbid_for, id, MapSet.new(Enum.map(classes, &atom/1))}]}
  end

  # "Возможность взятия фита" — which slots will take this feat. `general: true`
  # is the page saying it may be picked on any level that grants a feat, which
  # is what a general feat *is*; the per-class entries name bonus slots.
  #
  # A raw slot name may be a synonym for one of the two kinds this function
  # knows rather than a third kind: the Ranger's row reads "когда выбирает
  # любимого врага" instead of "доп фитах", and the parser faithfully keeps
  # that as its own string, `favored_enemy` (`SialaFeatPage.taking_line/2`) —
  # correctly, because that is what the sentence says. Whether the sentence
  # names a *different* slot or is a wordier name for the ordinary one is a
  # game question the wiki text alone does not settle, so it is not settled
  # here: `aliases` rewrites a raw name to its canonical one exactly where
  # `overrides.json` states the equivalence (`feat_slot_aliases/1`), and
  # nowhere else — a name this loader has never been told about still lands
  # in `siala_unapplied`, same as before that fact existed.
  defp apply_feat_change(%{"what" => "feat_slots", "value" => %{} = value}, feat, _id, aliases) do
    by_class = value["by_class"] || []
    canonical = fn slots -> Enum.map(slots, &Map.get(aliases, &1, &1)) end

    bonus =
      for %{"class" => class, "slots" => slots} <- by_class,
          Enum.any?(canonical.(slots), &(&1 in @bonus_slot_kinds)),
          into: MapSet.new(),
          do: atom(class)

    updated = %{
      feat
      | type: if(value["general"] == true, do: "general", else: feat.type),
        bonus_for: MapSet.union(feat.bonus_for, bonus)
    }

    modelled? =
      Enum.all?(by_class, fn entry ->
        Enum.all?(canonical.(entry["slots"] || []), &(&1 in @bonus_slot_kinds))
      end)

    if modelled?, do: {:ok, updated}, else: {:partial, updated}
  end

  defp apply_feat_change(_change, _feat, _id, _aliases), do: :skip

  # Домены, в которых ванильная запись умеет сказать «варианта фита с таким
  # значением не существует», и ключ требований, которым она это говорит.
  # Словарь **закрытый**: домен, которого здесь нет, роняет сборку, а не
  # применяется наполовину — снятие запрета уменьшает число отказов, и опечатка
  # в домене иначе прочиталась бы как «ничего не сняли», то есть тихо.
  @variant_ban_keys %{"skill" => "no_feat_variant_for_skills"}

  # Одно значение, вычеркнутое из ванильного списка несуществующих вариантов.
  # Возвращает блок требований целиком — остальные ключи не тронуты, и в этом
  # весь смысл дельты.
  defp lift_variant_ban!(%{prereqs: prereqs} = _feat, id, domain, member) do
    key = variant_ban_key!(id, domain)

    case prereqs && Map.get(prereqs, key) do
      list when is_list(list) ->
        if member in list do
          Map.put(prereqs, key, list -- [member])
        else
          raise """
          siala_41/feats.json: #{id} / feat_variant_exists says the shard has #{inspect(member)}, \
          but vanilla's #{key} does not forbid it — it reads #{inspect(list)}. Nothing was \
          lifted, so the record is a silent no-op: either the source page moved under it, \
          or the ban it answers is already gone.
          """
        end

      _absent ->
        raise """
        siala_41/feats.json: #{id} / feat_variant_exists says the shard has #{inspect(member)}, \
        but this feat states no #{key} at all. There is no ban to lift, and a record \
        that lifts nothing reads as an applied one.
        """
    end
  end

  defp variant_ban_key!(id, domain) do
    Map.get(@variant_ban_keys, domain) ||
      raise """
      siala_41/feats.json: #{id} / feat_variant_exists names domain #{inspect(domain)}, \
      which no requirement key answers. Known: #{inspect(Map.keys(@variant_ban_keys))}.
      """
  end

  # The one branch of a requirement that names this class, moved to the level the
  # shard's page states. Whether the block is a bare `class_levels` or one branch
  # of an `any_of` is the schema's business, not the record's — the record names a
  # class and two numbers, which is all the page says.
  defp move_class_level_requirement!(%{prereqs: prereqs} = _feat, id, class, from, to)
       when is_map(prereqs) do
    case swap_class_level(prereqs, class, from, to) do
      {_same, []} ->
        raise """
        siala_41/feats.json: #{id} / requirement_class_level moves #{class}'s level from \
        #{from} to #{to}, but no requirement of this feat names #{class} at all. Nothing was \
        replaced, so the shard's rule would silently not apply.
        """

      # Every branch that names the class has to read what the record claims, not
      # just one of them: a half-moved disjunction is a requirement nobody wrote.
      {updated, found} ->
        if Enum.all?(found, &(&1 == from)) do
          updated
        else
          raise """
          siala_41/feats.json: #{id} / requirement_class_level says #{class}'s requirement reads \
          #{from}, but the dictionary now has #{Enum.join(found, ", ")}. The page moved under \
          the record (or the record has already been applied once) — reread it and rewrite it.
          """
        end
    end
  end

  defp move_class_level_requirement!(%{} = _feat, id, class, _from, _to) do
    raise """
    siala_41/feats.json: #{id} / requirement_class_level moves #{class}'s level, but the feat \
    states no requirements at all. There is no branch to move.
    """
  end

  # Returns the block with the branch rewritten, plus every level found for that
  # class — so "no such branch" and "a branch, but a different number" stay
  # different answers to the caller.
  defp swap_class_level(%{"any_of" => branches} = node, class, from, to) when is_list(branches) do
    {branches, found} =
      Enum.map_reduce(branches, [], fn branch, acc ->
        {updated, found} = swap_class_level(branch, class, from, to)
        {updated, acc ++ found}
      end)

    {rest, here} = swap_own_class_level(Map.delete(node, "any_of"), class, from, to)
    {Map.put(rest, "any_of", branches), found ++ here}
  end

  defp swap_class_level(node, class, from, to), do: swap_own_class_level(node, class, from, to)

  defp swap_own_class_level(%{"class_levels" => levels} = node, class, from, to)
       when is_map(levels) do
    case Map.fetch(levels, class) do
      {:ok, ^from} -> {Map.put(node, "class_levels", Map.put(levels, class, to)), [from]}
      {:ok, other} -> {node, [other]}
      :error -> {node, []}
    end
  end

  defp swap_own_class_level(node, _class, _from, _to), do: {node, []}

  # The shard writes a requirement block as a **list of atoms**, one per
  # comma-separated fragment, and deliberately does not say whether they are
  # joined by "и" or "или" (README, `generated/feats.json`).
  #
  # One shape cannot be a conjunction: **two different classes**. Lay on Hands
  # lists «Паладин 1, Чемпион Торма 1» with a comma, and read as "both" it would
  # demand a build nobody has — the ability is handed over by either class.
  # Reading it as "or" is a conclusion about the game, not about the punctuation,
  # which is why the parser leaves it to this layer and does not carry a second
  # copy of the rule. It used to travel in `unparsed` because the schema had no
  # disjunction; `any_of` is that disjunction, so now it is expressed.
  #
  # ⚠ The inference holds for **class-granted abilities**, which is what every
  # such block on the shard's wiki is today (`lay_on_hands` is the only one). A
  # prestige-class-style "Fighter 4 **and** Rogue 2" would be read wrong here,
  # and the day one appears the parser has to mark it.
  defp shard_prereqs(atoms) do
    {classes, plain} = Enum.split_with(atoms, &(&1["kind"] == "class_level"))
    alternatives? = classes |> Enum.map(& &1["class"]) |> Enum.uniq() |> length() > 1

    {folded, unparsed} =
      Enum.reduce(if(alternatives?, do: plain, else: atoms), {%{}, []}, &fold_prereq/2)

    {folded, unparsed} =
      if alternatives?,
        do: put_any_of(folded, unparsed, Enum.map(classes, &branch/1), classes),
        else: {folded, unparsed}

    if unparsed == [], do: folded, else: Map.put(folded, "unparsed", unparsed)
  end

  # One branch of a disjunction, folded on its own. A branch that reads only
  # partly is `:error`: dropping the unreadable half of an alternative makes the
  # requirement **stricter** than the page's, which is the one direction that
  # locks a player out of something legal.
  defp branch(atom) do
    case Enum.reduce([atom], {%{}, []}, &fold_prereq/2) do
      {map, []} when map != %{} -> {:ok, map}
      _ -> :error
    end
  end

  defp put_any_of(folded, unparsed, branches, atoms) do
    raw = Enum.map(atoms, &(&1["raw"] || inspect(&1)))

    cond do
      # Two independent disjunctions in one block would be a conjunction of two
      # of them, which `any_of` cannot express — so the second is not merged
      # into the first (that would weaken both) but named.
      Map.has_key?(folded, "any_of") -> {folded, unparsed ++ raw}
      Enum.any?(branches, &(&1 == :error)) -> {folded, unparsed ++ raw}
      true -> {Map.put(folded, "any_of", Enum.map(branches, &elem(&1, 1))), unparsed}
    end
  end

  defp fold_prereq(%{"kind" => "class_level", "class" => class, "level" => level}, {acc, un})
       when is_binary(class) and is_integer(level) do
    {Map.update(acc, "class_levels", %{class => level}, &Map.put(&1, class, level)), un}
  end

  defp fold_prereq(%{"kind" => "character_level", "level" => level}, {acc, un})
       when is_integer(level) do
    {Map.put(acc, "character_level", level), un}
  end

  # The one maximum in the schema: «умение можно взять только на 1-ом уровне».
  defp fold_prereq(%{"kind" => "max_character_level", "level" => level}, {acc, un})
       when is_integer(level) do
    {Map.put(acc, "max_character_level", level), un}
  end

  # A disjunction the page states outright — «Темный эльф (Elf) **или** Убийца
  # (Assassin) 20 уровня». Nothing is inferred here; the "или" is printed.
  defp fold_prereq(%{"kind" => "any_of", "branches" => branches} = atom, {acc, un})
       when is_list(branches) do
    put_any_of(acc, un, Enum.map(branches, &branch/1), [atom])
  end

  defp fold_prereq(%{"kind" => "bab", "value" => value}, {acc, un}) when is_integer(value) do
    {Map.put(acc, "base_attack_bonus", value), un}
  end

  defp fold_prereq(%{"kind" => "ability", "ability" => ability, "value" => value}, {acc, un})
       when is_integer(value) do
    case Map.fetch(@ability_keys, String.upcase(ability)) do
      {:ok, id} ->
        key = Atom.to_string(id)
        {Map.update(acc, "abilities", %{key => value}, &Map.put(&1, key, value)), un}

      :error ->
        {acc, un ++ [ability]}
    end
  end

  # A skill fragment with no number ("Артистизм (Perform)") states a
  # requirement without stating its size. One rank is a guess, so it is not made.
  defp fold_prereq(%{"kind" => "skill", "skill" => skill, "rank" => rank}, {acc, un})
       when is_binary(skill) and is_integer(rank) do
    {Map.update(acc, "skills", %{skill => rank}, &Map.put(&1, skill, rank)), un}
  end

  defp fold_prereq(%{"kind" => "feat", "feat" => feat}, {acc, un}) when is_binary(feat) do
    {Map.update(acc, "feats", [feat], &(&1 ++ [feat])), un}
  end

  defp fold_prereq(%{"kind" => "race", "race" => race}, {acc, un}) when is_binary(race) do
    {Map.update(acc, "race", [race], &(&1 ++ [race])), un}
  end

  defp fold_prereq(atom, {acc, un}), do: {acc, un ++ [atom["raw"] || inspect(atom)]}

  # A feat nobody may take opens nothing: on Siala `Power attack` is a gate to
  # six feats, not seven, and the "→ N" badge must not count the one the shard
  # switched off.
  defp drop_disabled_from_unlocks(feats) do
    disabled = for {id, %{disabled?: true}} <- feats, into: MapSet.new(), do: id

    if MapSet.size(disabled) == 0 do
      feats
    else
      Map.new(feats, fn {id, feat} ->
        {id, %{feat | unlocks: Enum.reject(feat.unlocks, &MapSet.member?(disabled, &1))}}
      end)
    end
  end
end
