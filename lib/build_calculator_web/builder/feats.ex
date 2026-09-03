defmodule BuildCalculatorWeb.Builder.Feats do
  @moduledoc """
  The feat picker's lists: what this level can take, and why the rest cannot.

  **Slots are not interchangeable** (CLAUDE.md §6). A level does not grant "two
  feats"; it grants, say, one general slot and one Fighter bonus slot, and the
  Fighter bonus only takes a feat that lists Fighter in its `bonus_for`.
  Counting them as one number is the classic calculator bug that produces
  illegal builds, so every decision here goes through
  `BuildCalculator.Rules.FeatSlots`.

  ## What we can honestly say, and what we cannot

  `ruleset.feats` carries a feat's type, its epic flag and the classes whose
  bonus slot accepts it — all machine-readable. Its **prerequisites are still
  prose** (`prereq_raw`, e.g. `"[[dexterity]] 15+"`), and there is no
  `Rules.validate_feat/…` to ask. So this module never claims a feat's
  prerequisites are met: it shows the wiki's own sentence, marked as unchecked,
  and the build collects a `{:missing_data, {:feat_prerequisites, id}}` gap for
  every feat taken that has one. Sorting an unverifiable requirement into
  "available" quietly would be exactly the confident lie the project is built to
  avoid.

  ## What the build already owns

  Two of the four cases end up in the blocked list with a reason, because
  hiding them would leave the player wondering where the feat went:

    * the class hands it over **on this level** — `{:granted_here, id}`
    * the character already has it **for keeps**, picked or granted —
      `{:already_taken, id}`

  The other two are warnings rather than refusals, because in both the pick is
  legal and the player may have a reason for it:

    * a class in the build grants it **later** (`free_later/3`). Taking it now
      rather than at level 35 is allowed, so the row stays available and says
      what it will cost;
    * an **item** lends it (`Rules.feat_pick_caveats/3`, task 3.3). Since
      09.08.2026 this is a warning too, and it used to be `{:already_taken, …}`:
      the item comes off and the slot does not, so refusing the permanent version
      of a borrowed feat cost the player a legal build. ⚠ `owned.before` is
      therefore `Build.feats_permanent/3` and not `Build.feats_owned/3` — the
      narrower set, on purpose. Whether the borrowed copy makes the slot pointless
      is the core's answer, not this module's: another take of `Epic toughness` is
      a real twenty hit points.

  The same fact keeps talking after the slot is spent, in a different tense:
  `free_later_text/2` is advice ("не трать слот"), `free_later_taken_text/2`
  is a statement of what already happened ("слот можно освободить") — a build
  loaded back from a saved code can have taken the feat on a level long past,
  and the picker has to say the same thing there too, past tense (HANDOFF,
  «впустую потраченный слот», решение Дана 02.08.2026).

  ## Фит, который берётся не один раз

  «Уже есть» перестало быть универсальным ответом: данные объявляют часть
  фитов повторяемыми, и повтор бывает двух видов — счётный (`Epic toughness`
  берут десять раз) и с параметром (`Spell focus` — по школе). Сколько раз
  фит уже взят, есть ли объявленный потолок и какие значения ещё свободны,
  знает ядро; этот модуль только спрашивает и раскладывает ответ по строкам
  (`choice_options/5`, `take_numbers/2`).

  ⚠️ Одно исключение веб-слой заводит сам, и оно не про правила: у домена
  может не быть справочника вовсе (`weapon`). Тогда второй пик записать нечем,
  два неотличимых `Weapon focus` слотовая модель не допускает, а ядро отказать
  не может — у него нет чем отличить второе оружие от того же самого.
  Отказ ставится здесь и называет настоящую причину (`{:choice_unrecordable,
  …}`): видимый отказ лучше невидимой нелегальности.
  """

  alias BuildCalculator.Ids
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatSlots}
  alias BuildCalculatorWeb.Builder.{Fuzzy, Labels}

  @type entry :: %{
          feat: map(),
          info: map(),
          score: integer(),
          positions: [non_neg_integer()],
          via: :en | :ru | nil,
          alias_ru: String.t() | nil,
          chosen_slot: term() | nil,
          target_slot: map() | nil,
          repeatable?: boolean(),
          takes: non_neg_integer(),
          choice_domain: atom() | nil,
          reasons: [tuple()],
          caveats: [tuple()],
          prereq: String.t() | nil,
          free_later: grant() | nil,
          taken?: boolean()
        }

  @typedoc "Where the build hands a feat over for free: character level, class and its level."
  @type grant :: %{level: pos_integer(), class: atom(), class_level: pos_integer()}

  @doc """
  Feat slots granted at `level`, each with its label, glyph, contents and —
  when the pick has art — its icon (AGENT_QUEUE.md 3.54).

  `:icon` is the picked feat's own raw filename, `nil` for an empty slot and
  for the 23 feats with no art either way (`Labels.feat_pick_icon/2`): the
  chip's glyph stays the fallback for both, exactly as `game_icon/1` already
  does everywhere else it is called.
  """
  @spec slots(map(), Build.t(), pos_integer()) :: [map()]
  def slots(ruleset, build, level) when level >= 1 do
    filled = Map.get(build.feats, level, %{})

    for slot <- FeatSlots.at(build, ruleset, level) do
      pick = Map.get(filled, slot.id)

      slot
      |> Map.put(:label, Labels.slot_label(ruleset, slot))
      |> Map.put(:glyph, Labels.slot_glyph(slot))
      |> Map.put(:feat, pick)
      |> Map.put(:icon, Labels.feat_pick_icon(ruleset, pick))
    end
  end

  def slots(_ruleset, _build, _level), do: []

  @doc """
  Фиты, которые персонаж **получает** на `level` даром — прибавка к владению,
  а не сырая выдача классового уровня.

  A different thing from a slot, and the difference is the whole point of
  showing it: a slot is a decision the player owes the level, a granted feat
  simply arrives. Ranger 1 grants three, and a player who spends a general slot
  on one of them has paid for what the build was going to hand over anyway.

  `build` is a whole build, so a hypothetical one can be passed in: the class
  card has to answer "what would *this* class give me here", not "what does the
  class already sitting on this level give me".

  Since 02.08.2026 this list is **not** shown in the progression column: the
  column answers "what did I decide", and a granted feat is not a decision
  (CLAUDE.md §6). It lives in the "Класс даёт сам" line of the feat section
  and in the view screen's guide.

  ## 🔴 Почему это прирост, а не `Build.granted_feats_at/3` (баг 1.14)

  Наблюдение Dan 10.08.2026: «если файтер дал фиты какие-то, а потом их же дал
  DD, то в реальности на момент получения DD эти фиты уже дал файтер и на DD мы
  просто ничего не получили вместо них, они уже есть». На его референсном билде
  (Воин 10 / ДД 23 / ВМ 7) уровень 10 — первый уровень Защитника — печатал шесть
  имён, а нового приносил **одно** (`Defensive stance`): три яруса брони, щит и
  `Toughness` персонаж получил ещё воином на 1-м. Пять строк из шести стояли
  шумом ровно там, где игрок ждёт сигнал.

  Числа при этом были верны и остаются: `Build.granted_feats/3` возвращает
  `MapSet`, поэтому владение дедуплицируется само, и `Toughness` считался
  один раз (`hp_breakdown.by_feat`). Врало только отображение.

  ## ⚠️ И почему это НЕ разность множеств

  Наивное `granted_feats(level) -- granted_feats(level - 1)` съело бы законное
  повторное получение: **ступени семейства живут под ОДНИМ id**, а не под
  разными. У вики одна страница на семейство, поэтому `Defensive awareness`
  I/II/III — это `:defensive_awareness` трижды, а ступень лежит отдельно, в
  `granted_feat_ranks` (`granted_named/3` ниже её и печатает). Таких мест в
  данных **87, в 13 классах, и у каждого ступень названа** — посчитано обходом
  `ruleset.classes` на обоих ruleset'ах 10.08.2026; что ни одно из них не
  дубликат, держит `Data.RepeatedGrantsTest`, а безранговый повтор загрузчик
  сам объявляет гэпом (`{:not_modelled, {:unnamed_grant_rank, …}}`).

  Отсюда правило из двух половин, и они обязаны стоять вместе:

    * **повтор в пределах ОДНОГО класса — событие**, а не дубль. Класс,
      выдающий свой же id второй раз, выдаёт следующую ступень (ДД 2/5/10,
      `Uncanny dodge` вора шесть раз, `Epic superior weapon focus` мастера
      оружия по +1 AB каждые три уровня);
    * **повтор ПОПЕРЁК источников — дубль**. `Toughness` выдают девять классов
      Сиалы, `Darkvision` — три класса плюс две расы; второй раз он не приходит
      никак.

  Владение считается по `Build.feats_permanent/3` — слот плюс выдача, без вещей.
  Вещь снимается, а классовая выдача постоянна: спрятать «класс выдал
  `Armor skin`» из-за надетого предмета значило бы потерять со экрана то, что
  у персонажа навсегда. Расовые фиты добавлены сверх этого вручную —
  `feats_permanent/3` их не знает и знать не должен (`Rules.Bonuses.held?/5`,
  `{:race_feat, …}`: расширение того множества молча изменило бы каждую проверку
  требований), но расовый фит так же постоянен, как классовый, поэтому Гном
  с уровнями Pale Master не получает `Darkvision` второй раз.
  """
  @spec granted(map(), Build.t(), pos_integer()) :: [atom()]
  def granted(ruleset, %Build{} = build, level) do
    case Build.granted_feats_at(build, ruleset, level) do
      [] ->
        []

      grants ->
        owned = owned_before(ruleset, build, level)
        step = granted_earlier_by_same_class(ruleset, build, level)

        for id <- grants,
            MapSet.member?(step, id) or not MapSet.member?(owned, id),
            do: id
    end
  end

  # Что персонаж держит НАВСЕГДА к концу предыдущего уровня. `level - 1`, а не
  # `level`: выдача этого уровня — как раз то, о чём спрашивают, и включить её
  # в «уже было» значило бы вычесть список из самого себя. Пик, сделанный на
  # этом же уровне, в счёт тоже не идёт — и не может помешать: фит, который
  # класс выдаёт здесь, ядро в слот не пускает вовсе (`{:granted_here, id}`).
  defp owned_before(ruleset, build, level) do
    build
    |> Build.feats_permanent(ruleset, level - 1)
    |> MapSet.union(racial_feats(ruleset, build))
  end

  # Тот же способ чтения, что у `Rules.Bonuses.held?({:race_feat, …})`, и
  # намеренно только чтение: расовые фиты остаются вне `Build.feats_owned/3`,
  # здесь они складываются с владением лишь на время одного вопроса про показ.
  defp racial_feats(ruleset, %Build{race: race}) do
    case Map.get(ruleset.races || %{}, race) do
      %{bonus_feats: feats} -> MapSet.new(feats)
      _ -> MapSet.new()
    end
  end

  # Id, которые класс ЭТОГО уровня выдавал на своих предыдущих классовых
  # уровнях. Считается по классовым уровням справочника, а не по персонажным:
  # класс мог браться с перерывами, и его собственная ступенчатая линейка от
  # этого не сдвигается.
  defp granted_earlier_by_same_class(ruleset, build, level) do
    with class when not is_nil(class) <- Build.class_at(build, level),
         %{granted_feats: by_level} <- Map.get(ruleset.classes, class),
         class_level when not is_nil(class_level) <- Build.class_level_at(build, level) do
      for {lv, ids} <- by_level, lv < class_level, id <- ids, into: MapSet.new(), do: id
    else
      _ -> MapSet.new()
    end
  end

  @doc """
  The same list, already named — with the rank the feat arrives at.

  One wiki page covers a whole family of ranks, so Dwarven defender hands over
  `Defensive awareness` at class levels 2, 5 and 10 under one id. Printing the
  bare name three times says nothing; `granted_feat_ranks` carries the wiki's
  own wording for each step, and `Labels.granted_feat_name/3` decides whether it
  follows the name or replaces it.

  Every surface that shows granted feats goes through this: the "Класс даёт
  сам" line and the view screen's levelling guide (`Summary.guide_rows/2`).

  ⚠️ The flat feat list of the view screen used to be a third one and is gone —
  Dan's decision of 10.08.2026, «перепись фитов можно удалить, будем их в гиде
  смотреть»: it repeated the guide feat for feat. Same rule as with the chip
  below — do not read a removed surface back into this list.

  ⚠️ The `от класса ×N` chip this doc used to mention is gone — Dan's
  decision of 02.08.2026 (CLAUDE.md §6) removed it from the class card and
  the Δ panel because a bare count named nothing. Do not read that sentence
  back in: closed history stays in HANDOFF/CLAUDE.md, not as a live claim
  here about a surface that no longer exists.
  """
  @spec granted_named(map(), Build.t(), pos_integer()) :: [
          %{id: atom(), name: String.t(), info: map()}
        ]
  def granted_named(ruleset, %Build{} = build, level) do
    ranks = granted_ranks(ruleset, build, level)

    for feat <- granted(ruleset, build, level) do
      %{
        id: feat,
        name:
          ruleset
          |> Labels.granted_feat_name(feat, Map.get(ranks, feat))
          |> with_granted_choice(ruleset, build, level, feat),
        # Same "what this does" content the picker and `guide_feats/3` carry
        # (task 3.94) — a granted `Evasion` is exactly the row the view
        # screen most needs this on, since the shard moved its own grant
        # level and the description is the only place that says what the
        # ability itself still does.
        info: Labels.feat_info(ruleset, feat)
      }
    end
  end

  # ⚠️ Выбор виден ВСЮДУ, где видно имя фита (CLAUDE.md §6) — включая выданный
  # фит: `Weapon of choice (Scimitar)` в гиде экрана просмотра отвечает на «что
  # мне качать», а голое `Weapon of choice` не отвечает ни на что. Скобки те же,
  # что у пика (`Labels.feat_pick_name/2`), потому что читателю это одна и та же
  # вещь; чем она отличается — уже сказано глифом `○`.
  defp with_granted_choice(name, ruleset, build, level, feat) do
    case Build.granted_choice(build, level, feat) do
      nil -> name
      choice -> name <> " (" <> Labels.choice_name(ruleset, feat, choice) <> ")"
    end
  end

  # Absent rather than empty when a level names no ranks — the parser does not
  # write empty objects, so a missing key is the normal case, not a fault.
  defp granted_ranks(ruleset, %Build{} = build, level) do
    with class when not is_nil(class) <- Build.class_at(build, level),
         %{granted_feat_ranks: by_level} <- Map.get(ruleset.classes, class) do
      Map.get(by_level, Build.class_level_at(build, level), %{})
    else
      _ -> %{}
    end
  end

  # ⚠️ Задача 1.10, шаг 4 (08.08.2026). Не любой префикс `weapon_proficiency_*`:
  # `_monk`/`_wizard`/`_druid`/`_rogue`/`_elf`/`_creature` — каждый свой
  # единственный фит одного класса, а не ярус общей линейки. Списки —
  # исчерпывающий перечень id, а не угадывание по имени; появится похожий
  # id за пределами этих двух семей — он просто останется отдельной строкой,
  # так же, как сегодня.
  @armor_tiers [:armor_proficiency_light, :armor_proficiency_medium, :armor_proficiency_heavy]
  @weapon_tiers [
    :weapon_proficiency_simple,
    :weapon_proficiency_martial,
    :weapon_proficiency_exotic
  ]

  @doc """
  `granted_named/3`, folded for display: same-family proficiency tiers become
  one line instead of one row each.

  Шаг 3 задачи 1.10 (08.08.2026) довёл владения до `granted_feats`, и воин
  первого уровня получил разом 7 строк вместо одной (`Toughness`) — «Класс
  даёт сам» стало самым длинным абзацем на экране первого уровня. Ни одно имя
  при этом не пропадает: считать фиты числом уже отменено решением Дана
  02.08.2026 (плашка «от класса ×N» без единого имени, CLAUDE.md §6) —
  сворачиваются только ЯРУСЫ одной линейки в одну строку, тем же способом,
  каким это делает сама вики на странице класса (`'''Proficiencies''': armor
  (light, heavy, medium), shields, weapons (martial, simple)`,
  AGENT_QUEUE §1.10, Источник 2):

      Armor proficiency (light), Armor proficiency (medium), Armor proficiency (heavy)
      → Armor proficiency (light/medium/heavy)

  Свёрнутое имя строится из уже готового `name`, а не из своего словаря
  английских слов («light», «heavy», …): уточнение в скобках — то же самое,
  что уже лежит в имени фита, просто нескольких имён сразу. Второго места,
  где эти слова хранятся, нет — значит расходиться с обычным,
  негруппированным списком строке нечем.

  Порядок — «броня → щит → оружие → всё остальное», порядок той же
  вики-строки, а не порядок данных (`granted_feats` держит для Paladin
  `heavy, light, medium` — алфавит id, не игровой смысл) и не порядок взятия.
  Он же кладёт «что можно надеть/носить» в начало строки, а классовые умения
  (`Toughness`, `Lay on hands`, …) — в конец, в их собственном порядке.
  """
  @spec granted_display(map(), Build.t(), pos_integer()) :: [String.t()]
  def granted_display(ruleset, %Build{} = build, level) do
    named = ruleset |> granted_named(build, level) |> Enum.uniq_by(& &1.id)

    equipment =
      [
        tier_group(named, @armor_tiers),
        tier_group(named, [:shield_proficiency]),
        tier_group(named, @weapon_tiers)
      ]
      |> Enum.reject(&is_nil/1)

    grouped = MapSet.new(@armor_tiers ++ @weapon_tiers ++ [:shield_proficiency])
    rest = for entry <- named, not MapSet.member?(grouped, entry.id), do: entry.name

    equipment ++ rest
  end

  # `nil` when the family is not granted at all here — the caller drops `nil`s
  # so the [броня, щит, оружие] order never depends on which of the three this
  # particular class happens to hand over.
  defp tier_group(named, tier_ids) do
    present = for id <- tier_ids, entry = Enum.find(named, &(&1.id == id)), entry, do: entry

    case present do
      [] -> nil
      [%{name: name}] -> name
      many -> combine_tiers(many)
    end
  end

  # «База (уточнение)» читается из уже готового имени, а не пересобирается
  # из своего списка слов — второй источник тех же трёх слов означал бы,
  # что они могут разойтись с обычным списком.
  defp combine_tiers(entries) do
    parsed = Enum.map(entries, &split_qualifier/1)

    case Enum.find(parsed, fn {base, _qualifier} -> is_nil(base) end) do
      nil ->
        {base, _qualifier} = List.first(parsed)
        qualifiers = Enum.map_join(parsed, "/", &elem(&1, 1))
        "#{base} (#{qualifiers})"

      _unparsed ->
        # Имя не легло в форму «база (уточнение)» — не гадаем, что имелось
        # в виду, показываем как список отдельных имён через запятую.
        Enum.map_join(entries, ", ", & &1.name)
    end
  end

  defp split_qualifier(%{name: name}) do
    case Regex.run(~r/^(.+) \(([^()]+)\)$/, name) do
      [_, base, qualifier] -> {base, qualifier}
      _no_match -> {nil, name}
    end
  end

  @doc """
  Feats the build will hand over for free *after* `level`, keyed by feat id.

  This is what powers the "получишь бесплатно на Ranger 6 — не трать слот"
  warning of CLAUDE.md §6. Spending a slot on a feat the build was going to
  grant anyway is a real and expensive mistake, and no calculator in the
  community catches it.

  The scan only looks at levels the build already has: a class the player has
  not taken yet promises nothing. The earliest grant wins, because that is the
  level the warning has to name.
  """
  @spec free_later(map(), Build.t(), non_neg_integer()) :: %{atom() => grant()}
  def free_later(ruleset, %Build{} = build, level) do
    for lv <- (level + 1)..Build.character_level(build)//1,
        feat <- Build.granted_feats_at(build, ruleset, lv),
        reduce: %{} do
      acc ->
        Map.put_new(acc, feat, %{
          level: lv,
          class: Build.class_at(build, lv),
          class_level: Build.class_level_at(build, lv)
        })
    end
  end

  @doc "Russian wording for one `free_later/3` grant, or `nil` when there is none."
  @spec free_later_text(map(), grant() | nil) :: String.t() | nil
  def free_later_text(_ruleset, nil), do: nil

  def free_later_text(ruleset, %{level: level, class: class, class_level: class_level}) do
    "получишь бесплатно на #{Labels.class_name(ruleset, class)} #{class_level} " <>
      "(уровень #{level}) — не трать слот"
  end

  @doc """
  The same grant, worded for a slot already spent on it.

  `free_later_text/2` is advice about a choice still ahead — "не трать слот".
  Once the slot is filled that advice is moot (there is nothing left not to
  spend), but the underlying fact has not gone anywhere: the class is still
  going to hand the feat over for free, and the player who took it early
  should be told the slot can be freed, not left reading a sentence that talks
  about an already-made choice as if it were still open.

  This is the machinery `HANDOFF.md` (§A.3, решение Дана 02.08.2026) asked to
  reach "the made choice, not just the offer": a build loaded back from a
  saved code can have this sitting on a level long past, and the warning has
  to survive the round-trip through the URL exactly as well as the build does.
  """
  @spec free_later_taken_text(map(), grant() | nil) :: String.t() | nil
  def free_later_taken_text(_ruleset, nil), do: nil

  def free_later_taken_text(ruleset, %{level: level, class: class, class_level: class_level}) do
    "класс выдаёт его на #{Labels.class_name(ruleset, class)} #{class_level} " <>
      "(уровень #{level}) — слот можно освободить"
  end

  @doc """
  Russian wording for one caveat the core puts on a pick it **allows**.

  `Rules.feat_pick_caveats/3` answers `{:owned_from_gear, id}` where an item
  already lends the feat and the feat cannot be taken twice: the slot changes no
  number, and the player is told rather than refused (task 3.3, revised
  09.08.2026).

  ⚠ One sentence for both tenses, unlike `free_later_text/2` and
  `free_later_taken_text/2`. Those two differ because "не трать слот" stops making
  sense once the slot is spent; this one is a statement of fact — «слот ничего не
  добавляет» — and reads the same before and after. Its second half is the reason
  the pick is legal at all and is not decoration: an item comes off, a slot does
  not, so a player who spends the slot deliberately is doing something sensible.

  Short, because the feat's name is already in the row being explained; the named
  wording for callers where it is not lives in `Labels.reason/2`, exactly as with
  `{:feat_disabled, …}`.
  """
  @spec caveat_text(tuple(), map()) :: String.t()
  def caveat_text({:owned_from_gear, _id}, _ruleset),
    do: "уже есть с вещи — слот ничего не добавляет (но снимешь предмет — фит останется)"

  def caveat_text(other, ruleset), do: reason(other, ruleset)

  @doc """
  `free_later_taken_text/2`, for a caller that only has the raw `{slot, pick}`
  the build stores rather than a ready-built `lists/4` entry.

  The progression column and the view screen both walk `build.feats` directly
  instead of going through `lists/4` (that function answers "what can THIS
  level take", not "what is already sitting on every level of the build"), so
  neither has an `entry.free_later`/`entry.taken?` pair sitting ready-made.
  This is their way in: pass `free_later/3`'s result for the pick's own level
  — computed once per level by the caller, not once per pick, since a level
  can hold more than one slot — and get back the same sentence the picker
  would show for that exact pick.

  A repeatable feat (`Epic toughness`, `Spell focus`) is never called "wasted"
  here: a class handing one over for free does not make a *second* purchase
  pointless the way it does for a feat that can only ever be owned once.

  ## Two sources of the same advice, and why only one sentence comes back

  Since task 3.3 a slot can be spent for nothing in a second way: an **item**
  lends the same feat (`Rules.feat_pick_caveats/3`). Both are checked here, and
  the class grant wins when both hold — not to save room but because it is
  strictly the stronger statement: a class grant cannot be lost, so freeing the
  slot is unambiguously right, while doing it against an item leaves the feat
  hanging on the item staying on. The weaker sentence adds nothing after the
  stronger one has been read.

  ⚠ `build` is needed for the second half and is why this takes four arguments.
  The picker does not go through here — it shows both facts as separate lines,
  where there is room for them (`caveat_text/2`).
  """
  @spec wasted_text(map(), Build.t(), %{atom() => grant()}, Build.feat_pick()) :: String.t() | nil
  def wasted_text(ruleset, %Build{} = build, later, pick) do
    id = Build.feat_id(pick)

    cond do
      repeatable?(ruleset, id) ->
        nil

      text = free_later_taken_text(ruleset, Map.get(later, id)) ->
        text

      caveat = List.first(Rules.feat_pick_caveats(build, id, ruleset)) ->
        caveat_text(caveat, ruleset)

      true ->
        nil
    end
  end

  @doc """
  Slots of the same kind collapsed into one caption with a count.

  Order is the slot order, so the general slot leads and the class bonus
  follows — same reading as the chips in the feat section.
  """
  @spec slot_labels(map(), [map()]) :: [%{label: String.t(), count: pos_integer()}]
  def slot_labels(ruleset, slots) do
    Enum.reduce(slots, [], fn slot, acc ->
      label = Labels.slot_delta_label(ruleset, slot)

      case Enum.find_index(acc, &(&1.label == label)) do
        nil -> acc ++ [%{label: label, count: 1}]
        index -> List.update_at(acc, index, &%{&1 | count: &1.count + 1})
      end
    end)
  end

  @doc """
  The slot a click on `feat` should spend.

  The narrowest one wins: a class bonus goes before a general slot, or the
  general slot ends up paying for something the bonus would have covered for
  free (CLAUDE.md §6).
  """
  @spec best_slot(map(), Build.t(), pos_integer(), atom()) :: map() | nil
  def best_slot(ruleset, build, level, feat_id) do
    open =
      for slot <- open_slots(ruleset, build, level), accepts?(ruleset, slot, feat_id), do: slot

    Enum.find(open, List.first(open), &(&1.kind == :class_bonus))
  end

  @doc "Slots at `level` that hold nothing yet."
  @spec open_slots(map(), Build.t(), pos_integer()) :: [map()]
  def open_slots(ruleset, build, level) do
    filled = Map.get(build.feats, level, %{})
    for slot <- FeatSlots.at(build, ruleset, level), not Map.has_key?(filled, slot.id), do: slot
  end

  defp accepts?(ruleset, slot, feat_id), do: FeatSlots.accepts?(ruleset, slot, feat_id)

  @doc """
  Builds the two lists the picker renders.

  Options:

    * `:query` — the fuzzy search string, matched against the English name and
      the Russian wiki alias both
    * `:type` — `"all" | "general" | "epic" | "bonus"`
    * `:slot` — a slot id to filter down to, set by clicking its chip
  """
  @spec lists(map(), Build.t(), pos_integer(), keyword()) :: %{
          available: [entry()],
          blocked: [entry()],
          blocked_total: non_neg_integer(),
          searching?: boolean()
        }
  def lists(ruleset, build, level, opts \\ []) do
    query = opts |> Keyword.get(:query, "") |> String.trim()
    type = Keyword.get(opts, :type, "all")
    slot_filter = Keyword.get(opts, :slot)
    searching? = query != ""

    all_slots = FeatSlots.at(build, ruleset, level)
    chosen = Map.get(build.feats, level, %{})

    # `feats_permanent`, not `feats_taken`: a feat the class handed over for free
    # is just as owned as one a slot was spent on, and offering it again sells the
    # player a slot for nothing (CLAUDE.md §6). Toughness on level 1 is the case
    # that matters — Siala grants it to eight classes, and it is the single most
    # common first feat in NWN.
    #
    # ⚠ And not `feats_owned` either, which additionally counts what an **item**
    # lends: an item comes off, so a feat on loan must not refuse the slot that
    # would make it permanent (09.08.2026). That case is a caveat instead — see
    # `entry/7`'s `caveats` — and the difference is exactly `Build.feats_owned/3`
    # against `Build.feats_permanent/3`.
    owned = %{
      before: Build.feats_permanent(build, ruleset, level - 1),
      here: MapSet.new(Build.granted_feats_at(build, ruleset, level)),
      later: free_later(ruleset, build, level),
      # ⚠️ По id, а не по содержимому слота: в слоте лежит либо голый атом,
      # либо пара `{фит, выбор}`, и ключ-пара не нашёлся бы по имени фита —
      # взятый `Spell focus (Evocation)` показался бы невзятым.
      chosen_by_feat: Map.new(chosen, fn {slot, pick} -> {Build.feat_id(pick), slot} end)
    }

    # Один раз на весь список, а не на фит: `distance/2` сортирует недоступные
    # «по близости», и ему нужны те же статы для всех трёхсот записей.
    stats = Rules.compute(build, ruleset)

    {available, blocked} =
      ruleset.feats
      |> Enum.filter(fn {id, feat} ->
        candidate?(ruleset, all_slots, id, feat, searching?) and passes_type?(feat, type) and
          passes_slot?(ruleset, all_slots, slot_filter, id)
      end)
      |> Enum.flat_map(fn {id, feat} ->
        case score(ruleset, feat, query) do
          nil -> []
          match -> [entry(ruleset, build, level, id, feat, match, owned)]
        end
      end)
      |> Enum.split_with(&(&1.reasons == []))

    %{
      available: sort(available, searching?, stats),
      blocked: blocked |> sort(searching?, stats) |> owned_last(),
      blocked_total: length(blocked),
      searching?: searching?
    }
  end

  # ⚠️ Список раньше резался потолком в 50 строк (задача 3.115, Dan
  # 26.08.2026: «отдельная зона под фиты со своим скроллом появилась давно,
  # смысл в ограничении отпал»). `.feat-lists` — область прокрутки
  # ФИКСИРОВАННОЙ высоты (`assets/css/app.css`), поэтому потолок больше не
  # защищает страницу ни от чего: он только прятал 19–33 строки на
  # эпических уровнях, ничего не выигрывая взамен.
  #
  # Разбиение на `owned`/`rest` при этом осталось — не как защита от
  # обрезания (обрезания больше нет), а как самостоятельное решение
  # о порядке. «Уже есть» и «класс выдаёт его здесь» — это факт о билде,
  # а не про требования фита, и ставить его в конец списка недоступных
  # осмысленно само по себе: `reason_rank/2` не даёт этой группе
  # специального места, а естественный числовой порядок случайно подмешал
  # бы её между «почти дотянулся» и «фит не существует на этом пути»
  # (`feat_disabled`/`not_slottable`/`not_selectable_at_level_up`).
  defp owned_last(blocked) do
    {owned, rest} = Enum.split_with(blocked, &owned_reason?/1)

    rest ++ owned
  end

  # ⚠️ Список расширен вместе с повторяемостью. Все эти отказы отвечают
  # на один и тот же вопрос — «а куда делся мой фит»: он уже взят, взят
  # столько раз, сколько можно, выбирать в нём больше нечего, или повтор
  # нам нечем записать. `owned_last/1` выше читает этот список, чтобы
  # отвести им конец списка недоступных — до задачи 3.115 то же разбиение
  # ещё и защищало их от обрезания потолком, которого больше нет.
  @owned_reasons [
    :granted_here,
    :already_taken,
    :max_takes,
    :choice_exhausted,
    :choice_unrecordable
  ]

  defp owned_reason?(%{reasons: [reason | _]}) when is_tuple(reason),
    do: elem(reason, 0) in @owned_reasons

  defp owned_reason?(_entry), do: false

  # Without a query the list is what this level's slots could conceivably take —
  # otherwise a general-slot level would list all 299 feats. With a query the
  # whole dictionary is fair game, because "why can't I take this?" is exactly
  # the question a search is asking.
  defp candidate?(_ruleset, _slots, _id, _feat, true), do: true

  defp candidate?(ruleset, slots, id, _feat, false) do
    Enum.any?(slots, &accepts?(ruleset, &1, id))
  end

  defp passes_type?(_feat, "all"), do: true
  defp passes_type?(feat, "general"), do: feat.type == "general" and not feat.epic?
  defp passes_type?(feat, "epic"), do: feat.epic?
  defp passes_type?(feat, "bonus"), do: MapSet.size(feat.bonus_for) > 0
  defp passes_type?(_feat, _other), do: true

  defp passes_slot?(_ruleset, _slots, nil, _id), do: true

  defp passes_slot?(ruleset, slots, slot_id, feat_id) do
    case Enum.find(slots, &(&1.id == slot_id)) do
      nil -> true
      slot -> accepts?(ruleset, slot, feat_id)
    end
  end

  # Match on the English name and on the Russian wiki spelling, keep the better
  # one. `via` records which fired: when the row came up on the alias the UI
  # says so, otherwise a Cyrillic query returning English names looks random.
  # The alias is a search aid, never a name — no single Russian translation of a
  # feat exists (CLAUDE.md §4).
  defp score(_ruleset, _feat, ""), do: %{score: 0, positions: [], via: nil}

  defp score(ruleset, feat, query) do
    en = Fuzzy.match(query, feat.name)
    ru_name = Labels.alias_ru(ruleset, feat.name)
    ru = ru_name && Fuzzy.match(query, ru_name)

    cond do
      en && (is_nil(ru) or en.score >= ru.score) -> Map.put(en, :via, :en)
      ru -> %{score: ru.score, positions: [], via: :ru}
      true -> nil
    end
  end

  defp entry(ruleset, build, level, id, feat, match, owned) do
    chosen_slot = Map.get(owned.chosen_by_feat, id)
    repeat? = repeatable?(ruleset, feat)

    # ⚠️ У повторяемого фита занятый слот НЕ гасит строку. `Epic toughness`
    # берут по десять раз, и второе взятие ничем не отличается от первого —
    # значит строка обязана остаться кнопкой «взять ещё».
    #
    # Освобождение при этом переезжает на чип слота, и это не компромисс,
    # а единственная однозначная форма: у фита, взятого трижды, «убрать»
    # не отвечает на вопрос «какое из трёх», а чип называет и слот, и уровень.
    target = if chosen_slot && not repeat?, do: nil, else: best_slot(ruleset, build, level, id)

    %{
      feat: feat,
      # "Что делает" popover content (task 3.87) — computed once per row here,
      # the same lifecycle as `prereq`/`alias_ru` below, rather than in the
      # template: `lists/4` already re-runs on every relevant build change,
      # while the template re-renders on every diff, so this is the cheaper
      # of the two places to call `Labels.feat_info/2`.
      info: Labels.feat_info(ruleset, id),
      score: match.score,
      positions: match.positions,
      via: match.via,
      alias_ru: Labels.alias_ru(ruleset, feat.name),
      chosen_slot: chosen_slot,
      target_slot: target,
      repeatable?: repeat?,
      # Тот же тест, что решает «✓ взят» против «выбрать ещё» ниже по файлу —
      # вынесен в поле, потому что веб-слою он тоже нужен: выбрать между
      # `free_later_text/2` («не трать слот») и `free_later_taken_text/2`
      # («слот можно освободить») можно только зная, потрачен ли слот именно
      # СЕЙЧАС, а не просто существует ли `free_later` вообще.
      taken?: not is_nil(chosen_slot) and not repeat?,
      # Нарастающий итог по этот уровень включительно: строка отвечает
      # на «сколько их у меня», а не «сколько я нажал здесь».
      takes: Build.feat_takes(build, id, level),
      # Домен выбора, если фит берётся С параметром. Веб по нему только
      # решает, нужен ли второй шаг; сам список значений отдаёт ядро.
      choice_domain: Rules.feat_choice_domain(id, ruleset),
      prereq: unread_prereq_text(feat),
      # Nothing to warn about once the feat is already in hand — the warning is
      # "do not pay for this", and there is nothing left to pay. It *does* stay
      # on a feat picked at this very level: that slot can still be freed.
      free_later: free_later_hint(owned, id),
      # ⚠ Caveats are **not** reasons and must never be folded into them: the row
      # stays in the available list, with the sentence beside it. `reasons != []`
      # is what sorts a row into "недоступные", so one line of carelessness here
      # would put back the false illegality this field exists to replace.
      #
      # The core decides (`Rules.feat_pick_caveats/3`), because whether a second
      # copy of a feat is worth anything is a game rule: `Epic toughness` off an
      # amulet plus a slot is two takes and forty hit points, so that row gets no
      # caveat at all.
      caveats: Rules.feat_pick_caveats(build, id, ruleset),
      # У повторяемого фита занятый слот причиной не является: строка обязана
      # дожить до настоящих проверок (потолок взятий, свободный слот), иначе
      # «взят ещё раз» предлагалось бы там, где взять уже нельзя.
      reasons:
        reasons(
          ruleset,
          build,
          level,
          id,
          feat,
          if(repeat?, do: nil, else: chosen_slot),
          target,
          owned
        )
    }
  end

  defp free_later_hint(owned, id) do
    if MapSet.member?(owned.here, id) or MapSet.member?(owned.before, id),
      do: nil,
      else: Map.get(owned.later, id)
  end

  defp reasons(_ruleset, _build, _level, _id, _feat, chosen_slot, _target, _owned)
       when not is_nil(chosen_slot),
       do: []

  defp reasons(ruleset, build, level, id, feat, _chosen, target, owned) do
    cond do
      # First, because it is the only answer that stays true whatever the build
      # does. `FeatSlots.accepts?/3` already refuses a disabled feat, so without
      # this branch the search fell through to `{:no_free_slot, id}` — formally
      # true and substantively a lie: freeing a slot would not help, the feat
      # does not exist on this shard at all.
      disabled?(feat) ->
        [{:feat_disabled, id}]

      # Beside `disabled?` for the same reason — no level, class or freed slot
      # changes it — and asked of the core, never re-derived here: «Умение нельзя
      # выбрать при росте персонажа» (`Riding Sprint`, `Smile of Death`).
      #
      # ⚠ Before `not_slottable?` below, and that ordering is the whole point of
      # the branch. Both refuse these two today, but `{:not_slottable, "special"}`
      # says «выдаётся классом или расой», which is not what their pages say at
      # all — the feat comes off an item — and it reads Fandom's type vocabulary
      # on a shard-only record, which is the mistake `Rules.FeatSlots.general?/1`
      # documents at length.
      (unpickable = Rules.feat_level_up_refusals(id, ruleset)) != [] ->
        unpickable

      # Checked before `already_taken` so the wording names the reason the
      # player can act on: the class is handing it over on this very level.
      MapSet.member?(owned.here, id) ->
        [{:granted_here, id}]

      # ⚠️ «Уже есть» — своя проверка, а не ядра, потому что она обязана
      # учитывать ВЫДАННОЕ классом (Toughness у воина на 1-м уровне), а ядро
      # считает только потраченные слоты.
      #
      # Исключение — всё, что данные объявили повторяемым. Считаются ли взятия
      # (`Epic toughness` — 10 раз) или каждое называет своё (`Spell focus`
      # по школам), решает ядро: оно знает и счёт, и потолок, и занятые значения.
      #
      # ⚠️ Кроме одного случая, и он не про правила, а про нас: у домена может
      # не быть справочника вовсе (`weapon` — оружие мы не моделируем и не будем
      # до армори). Тогда второй пик записать НЕЧЕМ, и в билд легли бы два
      # неотличимых `Weapon focus` — а взять его дважды на одно оружие нельзя
      # (`distinct?: true`). Ядро отказаться не может: у него нет справочника,
      # чтобы отличить второе оружие от того же самого, и оно честно молчит.
      # Отказать здесь — видимый отказ вместо невидимой нелегальности
      # (HANDOFF, «контракт из двух половин»), и он называет настоящую причину,
      # а не «уже есть».
      MapSet.member?(owned.before, id) and unrecordable_repeat?(ruleset, feat) ->
        [{:choice_unrecordable, id, Rules.feat_choice_domain(id, ruleset)}]

      MapSet.member?(owned.before, id) and not repeatable?(ruleset, feat) ->
        [{:already_taken, id}]

      feat.epic? and level < ruleset.epic.starts_at ->
        [{:requires_epic_level, ruleset.epic.starts_at}]

      not slottable?(feat) ->
        [{:not_slottable, feat.type}]

      # ⚠️ ПЕРЕД «нет слота», по той же причине, что и `disabled?` в начале:
      # класс этого уровня не даёт выбрать фит вовсе, и освободить слот не
      # поможет — а `{:no_free_slot, …}` именно туда и отправил бы. Формально
      # свободного слота действительно нет (ядро их все отбило), и ровно этим
      # такая причина опасна: она верна и уводит не туда.
      #
      # Причину называет ядро (`Rules.class_feat_refusals/4`), а не мы: список
      # запрещённого — правило игры, и собранный заново здесь он разошёлся бы
      # с тем, что показывают слоты.
      (forbidden = Rules.class_feat_refusals(build, level, id, ruleset)) != [] ->
        forbidden

      # ⚠️ ПЕРЕД «нет слота», по той же причине, что и `disabled?` в начале:
      # освобождение слота не поможет тому, у кого не хватает 5 ловкости, и
      # назвать причиной слот значило бы отправить игрока чинить не то.
      true ->
        (prerequisite_reasons(ruleset, build, level, id) ++
           choice_reasons(ruleset, build, level, id) ++ slot_reasons(target, id))
        |> drop_restated()
    end
  end

  # ⚠️ Выбирать нечего — это ДВЕ разные причины, и различает их ядро
  # (`Rules.feat_choice_candidates/3`). Раньше здесь стояла собственная проверка
  # «список кандидатов пуст» с одной формулировкой на оба случая, и волшебник,
  # ни разу не взявший `Spell focus`, читал, что все восемь школ у него уже
  # заняты (найдено Dan, 03.08.2026).
  #
  # ⚠️ Причина отсюда НЕ отменяет остальных: эпический фит без 21-го уровня
  # обязан сказать и про уровень тоже. Прежняя ветка стояла в `cond` выше
  # требований и глушила их все.
  defp choice_reasons(ruleset, build, level, id) do
    case Rules.feat_choice_candidates(build, %{feat: id, at: level}, ruleset) do
      {:empty, reasons} -> reasons
      _offered_or_unknowable -> []
    end
  end

  @doc """
  Убирает требование, которое рядом уже сказано точнее.

  «Нужен Spell focus» и «нужен Spell focus на ту же школу» — одно требование,
  и печатать оба значит сказать игроку одно и то же дважды. Точное побеждает,
  общее уходит; всё остальное (уровень, круг заклинаний, слот) остаётся —
  оно про другое.

  Два места, где такая пара возникает, и правило у них одно:

    * строка списка — `{:requires_feat, f}` против `{:choice_requires, …, [f], …}`
      (значение ещё не выбрано, речь про домен целиком);
    * значение на втором шаге — `{:requires_feat, f}` против
      `{:requires_same_choice, f, value}` (значение названо).
  """
  @spec drop_restated([tuple()]) :: [tuple()]
  def drop_restated(reasons) do
    precise =
      for reason <- reasons,
          id <- restated_feats(reason),
          into: MapSet.new(),
          do: id

    Enum.reject(reasons, fn
      {:requires_feat, feat} -> MapSet.member?(precise, feat)
      _other -> false
    end)
  end

  defp restated_feats({:choice_requires, _feat, required, _domain}), do: required
  defp restated_feats({:requires_same_choice, required, _choice}), do: [required]
  defp restated_feats(_other), do: []

  # ⚠️ Здесь ядро наконец спрашивают.
  #
  # Модуль этого не делал НИКОГДА: в его доке было написано «prerequisites are
  # still prose … and there is no `Rules.validate_feat/…` to ask», и это было
  # правдой в момент написания. Потом появились и разобранные требования
  # (244 фита из 277), и `Rules.validate_feat/3` — а список так и не научился
  # спрашивать. `Ambidexterity` с DEX 10 ядро отбивает, а список предлагал.
  #
  # Прикрытием служила подпись «требования по вики … — мы их не проверяем»:
  # она была ЧЕСТНОЙ ровно потому, что список не проверял. Убрав её раньше,
  # чем появилась проверка, мы на несколько часов получили список, который
  # выглядел авторитетным и не был им. Это ровно «контракт из двух половин»
  # (HANDOFF): первой закрывают ту половину, что убирает ложную легальность,
  # а не ту, что убирает оговорку.
  defp prerequisite_reasons(ruleset, build, level, id) do
    feat = Map.get(ruleset.feats, id)
    pick = %{feat: id, at: level}

    # У счётного фита спрашиваем `validate_feat_pick/3`, а не `validate_feat/3`:
    # только он знает, сколько раз фит уже взят и есть ли объявленный потолок.
    #
    # У фита С параметром — прежний вопрос: `validate_feat_pick/3` без выбора
    # ответит `{:requires_choice, …}`, то есть отобьёт строку ровно за то, что
    # игрок ещё не дошёл до второго шага. Легальность самой пары проверяется
    # на втором шаге, поимённо по каждому значению (`choice_options/4`).
    result =
      if counted?(feat),
        do: Rules.validate_feat_pick(build, pick, ruleset),
        else: Rules.validate_feat(build, pick, ruleset)

    case result do
      :ok -> []
      {:error, reasons} -> reasons
    end
  end

  # Повторяемый и БЕЗ параметра: взятия просто считаются. Отличать по наличию
  # домена, а не по имени фита, — список счётных живёт в данных.
  defp counted?(%{repeatable: %{choice: nil}}), do: true
  defp counted?(_feat), do: false

  @doc """
  Берётся ли фит повторно — по данным, а не по списку имён.

  «Повторяемый» здесь означает «второе взятие в принципе возможно и его есть
  чем записать». Домен без справочника (`weapon`) этому не удовлетворяет:
  записать нечем, см. `unrecordable_repeat?/2`.
  """
  @spec repeatable?(map(), map() | atom()) :: boolean()
  def repeatable?(ruleset, feat_id) when is_atom(feat_id),
    do: repeatable?(ruleset, Map.get(ruleset.feats, feat_id))

  def repeatable?(_ruleset, %{repeatable: %{choice: nil}}), do: true

  def repeatable?(ruleset, %{repeatable: %{choice: domain}}) when not is_nil(domain),
    do: has_dictionary?(ruleset, domain)

  def repeatable?(_ruleset, _feat), do: false

  # Данные говорят «повторяемый», а справочника под домен нет.
  defp unrecordable_repeat?(ruleset, %{repeatable: %{choice: domain}}) when not is_nil(domain),
    do: not has_dictionary?(ruleset, domain)

  defp unrecordable_repeat?(_ruleset, _feat), do: false

  defp has_dictionary?(ruleset, domain) do
    match?(%{values: %MapSet{}}, Map.get(Map.get(ruleset, :choice_domains, %{}), domain))
  end

  defp slot_reasons(nil, id), do: [{:no_free_slot, id}]
  defp slot_reasons(_target, _id), do: []

  # A feat only ever reaches a slot if it is general (the every-third-level and
  # racial slots) or lists a class in `bonus_for`. Everything else — class
  # abilities, racial feats, monster feats — is granted, not chosen.
  defp slottable?(feat), do: feat.type == "general" or MapSet.size(feat.bonus_for) > 0

  # Same defensive read as `Rules.FeatSlots`: the vanilla layer has no notion of
  # a switched-off feat, so the key is only guaranteed once Siala is loaded.
  defp disabled?(feat), do: Map.get(feat, :disabled?, false)

  defp sort(entries, true, _stats) do
    Enum.sort_by(entries, &{-&1.score, &1.feat.name})
  end

  defp sort(entries, false, stats) do
    Enum.sort_by(entries, &{reason_rank(&1.reasons, stats), &1.feat.name})
  end

  # Without a search, the blocked list leads with the near misses: "почти
  # дотянулся" is a hint to act on, the alphabet is not.
  defp reason_rank([], _stats), do: 0
  defp reason_rank([{:no_free_slot, _} | _], _stats), do: 1
  defp reason_rank([{:requires_epic_level, level} | _], _stats), do: 1 + level
  defp reason_rank([{:granted_here, _} | _], _stats), do: 99
  defp reason_rank([{:already_taken, _} | _], _stats), do: 100
  defp reason_rank([{:choice_exhausted, _, _} | _], _stats), do: 101
  defp reason_rank([{:choice_unrecordable, _, _} | _], _stats), do: 102
  defp reason_rank([{:max_takes, _, _} | _], _stats), do: 103
  # Below everything a build can act on: no level, class or slot ever unlocks it.
  defp reason_rank([{:feat_disabled, _} | _], _stats), do: 190
  # Beside it, and just above: nothing in the build unlocks this either, but the
  # feat does exist and the player has a route to it (объявить в «Вещах»), so it
  # is worth reading a line sooner than what the game does not have at all.
  defp reason_rank([{:not_selectable_at_level_up, _} | _], _stats), do: 195
  defp reason_rank([{:not_slottable, _} | _], _stats), do: 200

  # Требования ядра — по РЕАЛЬНОЙ близости, ради которой `Labels.distance/2`
  # и заведена: «не хватает 1 ловкости» должно стоять выше, чем «не хватает 12».
  # Конъюнкция закрыта не раньше самого далёкого своего требования, поэтому
  # максимум, а не минимум.
  defp reason_rank([_ | _] = reasons, stats) do
    reasons |> Enum.map(&Labels.distance(&1, stats)) |> Enum.max()
  end

  @doc """
  Каким по счёту взятием оказался пик в каждом слоте этого уровня.

  Ключ счёта — **пара «фит + выбор»**, а не фит: `Epic energy resistance` можно
  взять дважды на огонь и один раз на электричество (Дан, 02.08.2026), и это
  два взятия одного и одно другого, а не три одного. Считается по тем же
  `Build.feat_picks/2`, что и всё остальное, — за один проход и в том же
  порядке, в каком слоты показываются.
  """
  @spec take_numbers(Build.t(), pos_integer()) :: %{Build.slot_id() => pos_integer()}
  def take_numbers(%Build{} = build, level) do
    build
    |> Build.feat_picks(level)
    |> Enum.reduce({%{}, %{}}, fn {lv, slot, id, choice}, {tally, here} ->
      n = Map.get(tally, {id, choice}, 0) + 1
      {Map.put(tally, {id, choice}, n), if(lv == level, do: Map.put(here, slot, n), else: here)}
    end)
    |> elem(1)
  end

  @doc """
  Выбор для фита, который класс **выдал** на этом уровне — по строке на фит.

  `Weapon of choice` Мастер оружия получает даром на 1-м классовом уровне и всё
  равно называет оружие (Dan, 10.08.2026; задача 3.26). Слота у выдачи нет,
  поэтому и второго шага, как у пика, нет: чип пишет значение сразу, как чип
  домена клирика.

  У каждой строки — `feat`, имя, `chosen` с уже записанным значением и `values`:
  ровно то, что ядро согласно принять (`Rules.granted_feat_choice_candidates/4`),
  плюс уже выбранное. `empty_texts` — русская причина, когда предложить нечего:
  у `Weapon of choice` это «сначала нужен Weapon focus», то есть механика, а не
  «всё занято» (та же пара форм, что у второго шага пика).

  ⚠️ **Пересекается с `granted/3` намеренно**: показывается только то, что этот
  уровень и правда приносит — иначе повторная выдача того же id (баг 1.14)
  снова предложила бы выбор там, где ничего не выдаётся. Правило «что считать
  новой выдачей» остаётся в одном месте, `granted/3`, а не копируется сюда.

  ⚠️ Список **не** печатает 29 недоступных оружий с причиной, хотя §6 требует
  «недоступное — с причиной»: причина у всех одна и та же и относится не к
  значению, а к правилу («только то оружие, на которое взят `Weapon focus`»).
  Одна строка правила учит ровно тому же, а тридцать строк — это список, который
  перестают читать.
  """
  @spec granted_choice_rows(map(), Build.t(), pos_integer()) :: [map()]
  def granted_choice_rows(ruleset, %Build{} = build, level) when level >= 1 do
    arriving = MapSet.new(granted(ruleset, build, level))

    for owed <- Rules.granted_feat_choices_owed(build, ruleset, level),
        MapSet.member?(arriving, owed.feat) do
      granted_choice_row(ruleset, build, level, owed)
    end
  end

  defp granted_choice_row(ruleset, build, level, owed) do
    %{feat: feat, choice: chosen} = owed

    {values, empty_reasons} =
      case Rules.granted_feat_choice_candidates(build, ruleset, feat, level) do
        {:ok, values} -> {values, []}
        {:empty, reasons} -> {[], reasons}
        {:error, reasons} -> {[], reasons}
        :no_choice -> {[], []}
      end

    %{
      feat: feat,
      feat_name: Labels.feat_name(ruleset, feat),
      domain: owed.domain,
      chosen: chosen,
      chosen_name: chosen && Labels.choice_name(ruleset, feat, chosen),
      values: granted_choice_values(ruleset, feat, values, chosen),
      empty_texts: for(reason <- empty_reasons, do: reason(reason, ruleset))
    }
  end

  # Уже выбранное всегда в списке, даже если ядро его вычеркнуло: снять клик
  # с записанного значения игрок должен иметь возможность всегда. Сегодня ядро
  # его и не вычёркивает (`granted_candidates/4` не считает значение своим же
  # предшественником), но список, из которого нельзя убрать выбранное, был бы
  # тупиком, и держать это на чужой реализации нельзя.
  defp granted_choice_values(ruleset, feat, values, chosen) do
    ids = if chosen && chosen not in values, do: [chosen | values], else: values

    for value <- Enum.sort(ids) do
      %{
        value: value,
        name: Labels.choice_name(ruleset, feat, value),
        chosen?: value == chosen
      }
    end
  end

  @doc """
  Второй шаг выбора: что этот фит примет здесь, и почему остальное — нет.

  Возвращает `%{allowed: [...], blocked: [...], domain: atom()}`, где у каждой
  записи `%{value:, name:, reasons:}`.

  Три правила, и каждое из них — отдельное решение:

  1. **Список значений отдаёт ядро** (`Rules.feat_choice_candidates/3`). «Какие
     школы ещё свободны» и «в какой школе уже есть `Spell focus`» — правила
     игры, и собранные заново здесь они разошлись бы с ядром (CLAUDE.md §5).

  2. **Кандидат ядра — это ещё не «можно взять».** `candidates/3` отвечает
     только про повторяемость и про требование «в той же школе»; требования
     самого фита он не смотрит. У `Epic skill focus` он отдаёт все 29 навыков,
     хотя 20 рангов есть в двух, — поэтому каждое значение прогоняется через
     `Rules.validate_feat_pick/3`. Без этого кнопка молча не срабатывала бы.

  3. **Прячем только занятое ЭТИМ ЖЕ фитом** (решение Дана, CLAUDE.md §6):
     «эту школу ты уже взял» механике не учит, игрок сам это только что сделал.
     Всё остальное показывается с причиной — в том числе школа, где нет
     обычного `Spell focus`, при выборе `Greater`. Занятые ядро вычёркивает
     само; недоступные по правилам оно вычёркивает тоже, поэтому их приходится
     возвращать обратно — см. `narrowed_out/4`.
  """
  @spec choice_options(map(), Build.t(), pos_integer(), atom(), Build.slot_id() | nil) ::
          %{domain: atom() | nil, allowed: [map()], blocked: [map()]} | nil
  def choice_options(ruleset, build, level, feat_id, slot_id \\ nil) do
    # ⚠️ `slot` передаётся ядру обязательно. Без него пик, УЖЕ лежащий в этом
    # слоте, считается собственным предшественником: переоткрыв выбор у взятого
    # `Greater spell focus (Evocation)`, игрок увидел бы, что Evocation занята —
    # им же самим, в той самой строке, которую он и правит.
    pick = %{feat: feat_id, at: level, slot: slot_id}

    case Rules.feat_choice_candidates(build, pick, ruleset) do
      {:ok, values} ->
        panel(ruleset, build, level, feat_id, slot_id, pick, values)

      # Предлагать нечего — но недоступное всё равно показывается с причиной,
      # иначе панель второго шага молчала бы ровно там, где игроку нужнее
      # всего объяснение. Почему именно нечего, ядро говорит формой
      # (`{:choice_exhausted, …}` / `{:choice_requires, …}`); в панель эта
      # причина пока не выводится — см. `feat-choice-empty` в разметке.
      {:empty, _reasons} ->
        panel(ruleset, build, level, feat_id, slot_id, pick, [])

      _no_choice_or_no_dictionary ->
        nil
    end
  end

  defp panel(ruleset, build, level, feat_id, slot_id, pick, values) do
    {allowed, blocked} =
      values
      |> Enum.map(&option(ruleset, build, pick, feat_id, &1))
      |> Enum.split_with(&(&1.reasons == []))

    narrowed =
      for value <- narrowed_out(ruleset, build, level, feat_id, slot_id),
          do: option(ruleset, build, pick, feat_id, value)

    %{
      domain: Rules.feat_choice_domain(feat_id, ruleset),
      allowed: allowed,
      blocked: blocked ++ narrowed
    }
  end

  defp option(ruleset, build, pick, feat_id, value) do
    reasons =
      case Rules.validate_feat_pick(build, Map.put(pick, :choice, value), ruleset) do
        :ok -> []
        {:error, reasons} -> drop_restated(reasons)
      end

    %{value: value, name: Labels.choice_name(ruleset, feat_id, value), reasons: reasons}
  end

  # Значения, которые ядро убрало требованием «в той же школе», — их надо
  # показать с причиной, а не спрятать.
  #
  # ⚠️ Список берётся НЕ из сырого справочника. В справочнике лежат и значения,
  # которые не выбираются вообще (`universal` — «не настоящая школа»), и ворота
  # к ним — приватная механика ядра; перечислив справочник, мы бы показали
  # игроку строки, которых в игре нет, и завели вторую копию ворот.
  #
  # Вместо этого спрашиваем ядро про БАЗОВЫЙ фит: «где ещё можно взять
  # `Spell focus`» — это ровно «где его ещё нет», то есть ровно то множество,
  # которое закрыто для `Greater`. Тот же вызов, те же ворота, ни одного
  # правила заново.
  defp narrowed_out(ruleset, build, level, feat_id, slot_id) do
    for base <- same_choice_as(ruleset, feat_id),
        pick = %{feat: base, at: level, slot: slot_id},
        {:ok, values} <- [Rules.feat_choice_candidates(build, pick, ruleset)],
        value <- values,
        uniq: true,
        do: value
  end

  # Читаем поле данных, а не правило: что оно ЗНАЧИТ, по-прежнему знает только
  # ядро, и ответ про каждое значение мы берём у него. Пропадёт ключ — список
  # недоступных схлопнется в пустой, а не соврёт.
  defp same_choice_as(ruleset, feat_id) do
    prereqs = Map.get(Map.get(ruleset.feats, feat_id) || %{}, :prereqs)
    list = is_map(prereqs) && (prereqs["same_choice_as"] || prereqs[:same_choice_as])

    for id <- List.wrap(list || []),
        resolved = resolve_feat_id(ruleset, id),
        not is_nil(resolved),
        do: resolved
  end

  defp resolve_feat_id(ruleset, id) when is_atom(id),
    do: if(Map.has_key?(ruleset.feats, id), do: id, else: nil)

  defp resolve_feat_id(ruleset, id) when is_binary(id) do
    case Ids.fetch(ruleset, :feats, id) do
      {:ok, resolved} -> resolved
      :error -> nil
    end
  end

  defp resolve_feat_id(_ruleset, _id), do: nil

  @doc "Russian wording for one blocked-feat reason."
  @spec reason(term(), map()) :: String.t()
  def reason({:granted_here, _id}, _ruleset), do: "класс выдаёт его на этом уровне"
  def reason({:already_taken, _id}, _ruleset), do: "уже есть у персонажа"
  def reason({:requires_epic_level, level}, _ruleset), do: "эпический: нужен #{level}-й уровень"
  def reason({:no_free_slot, _id}, _ruleset), do: "нет подходящего свободного слота"

  # Shorter than `Labels.reason/2` deliberately: here the name is already in the
  # row being explained, and repeating it would only push the line out of the
  # card. `Labels` keeps the named wording for the places the feat is off screen.
  def reason({:feat_disabled, _id}, _ruleset), do: "на Сиале отключён"

  def reason({:not_slottable, type}, _ruleset),
    do: "выдаётся классом или расой (#{type}), слотом не берётся"

  # ⚠️ Не «выдаётся классом», и это разные вещи: фит существует, работает
  # и приходит извне лестницы. Путь к нему у игрока есть, поэтому строка его
  # называет — иначе отказ читается как «в игре такого нет».
  def reason({:not_selectable_at_level_up, _id}, _ruleset),
    do: "при росте персонажа не выбирается — только объявить в «Вещах»"

  # Не «уже есть»: взять его повторно правила РАЗРЕШАЮТ, это МЫ не можем
  # записать, с чем именно. Чинится не билдом, а появлением справочника.
  #
  # ⚠️ Слово «пока» здесь несущее, а не вежливое (решение Дана, 02.08.2026).
  # Без него игрок читает отказ как правило шарда и строит билд вокруг него —
  # а правило наше и временное. Мы уже вычищали ровно такую ошибку в обратную
  # сторону: подпись «требования не проверяем» стояла там, где их проверяли.
  # Врать про СВОИ ограничения ничем не лучше, чем про чужие.
  #
  # ⚠️ И имя домена — человеческое, а не ключ данных: `«weapon»` в строке для
  # игрока было ровно такой же протечкой внутренностей, как тапл в интерфейсе.
  def reason({:choice_unrecordable, _id, domain}, _ruleset),
    do:
      "повторно — только с другим значением (#{Labels.domain_name(domain)}), " <>
        "а справочника пока нет: запрет временный"

  # Короче, чем у `Labels`: имя фита уже стоит в строке, которую объясняют.
  def reason({:choice_exhausted, _id, domain}, _ruleset),
    do: "выбирать больше нечего: все доступные значения (#{Labels.domain_name(domain)}) уже взяты"

  def reason(other, ruleset), do: Labels.reason(other, ruleset)

  @doc """
  Every refusal this module invents itself, one example of each.

  The companion to `BuildCalculator.Rules.reason_forms/0`, and it exists for the
  same reason: a refusal nobody worded renders through `inspect/1`, and that is
  the failure nobody notices. The core's registry cannot cover these — they are
  not the core's answers. "Класс выдаёт его на этом уровне" is a fact about the
  picker's own three-way split of what the build already owns, and the core has
  no opinion on it.
  """
  @spec reason_forms() :: [tuple()]
  def reason_forms do
    [
      {:granted_here, :toughness},
      {:already_taken, :power_attack},
      {:requires_epic_level, 21},
      {:no_free_slot, :cleave},
      {:not_slottable, "class"},
      {:feat_disabled, :devastating_critical},
      {:choice_unrecordable, :weapon_focus, :weapon}
    ]
  end

  @doc """
  Gaps the feat picker owes the build.

  Every taken feat whose prerequisites exist only as prose is one — the build
  may be illegal and we would not know.

  There used to be a second, unconditional gap here: "фиты, которые класс
  выдаёт сам, в данных не размечены". It is no longer true — `granted_feats`
  now ships in `priv/rules/*/classes.json` for every class, with Siala's
  `feat_level_shift` applied on top — and a gap that is not true is worse than
  no gap at all: it trains the reader to skim the list that exists to be read.
  """
  @spec gaps(map(), Build.t()) :: [tuple()]
  def gaps(ruleset, build) do
    taken = Build.feats_taken(build, Build.character_level(build))

    for id <- Enum.sort(taken),
        feat = Map.get(ruleset.feats, id),
        feat && unread_prereq_text(feat) != nil,
        do: {:missing_data, {:feat_prerequisites, id}}
  end

  # ⚠️ Только то, что ядро прочитать НЕ смогло, — и ничего больше.
  #
  # Раньше здесь печаталась вся строка требований, если у фита вообще была проза:
  # 277 фитов из 299. Разобрано при этом полностью 244 — то есть в 88% случаев
  # строка «мы их не проверяем» была неправдой, причём вредной. У `Ambidexterity`
  # требование `dexterity 15+` лежит в `prereqs` разобранным и реально отбивает
  # выбор при DEX 14, а подпись рядом уверяла, что мы его игнорируем.
  #
  # Это зеркало ошибки, которой ядро боится с другой стороны: там «легально
  # и молча», здесь «проверено, но объявлено непроверенным». Оба конца врут
  # про одно и то же — про то, чему можно верить. Гэп, который неправда, хуже
  # отсутствующего: он приучает пролистывать список, который существует, чтобы
  # его читали.
  defp unread_prereq_text(%{prereqs: %{"unparsed" => [_ | _] = unread}}),
    do: unread |> Enum.map_join("; ", &prereq_text/1) |> presence()

  defp unread_prereq_text(_feat), do: nil

  defp presence(""), do: nil
  defp presence(text), do: text

  # Strips `[[wiki|links]]` down to their text. Presentation only — nothing here
  # tries to read a requirement out of the sentence.
  defp prereq_text(nil), do: nil
  defp prereq_text(""), do: nil

  defp prereq_text(raw) do
    raw
    |> String.replace(~r/\[\[(?:[^\]|]*\|)?([^\]]+)\]\]/, "\\1")
    |> String.replace(~r/'{2,}/, "")
    |> String.trim()
  end
end
