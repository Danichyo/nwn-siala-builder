defmodule BuildCalculator.Rules.Wield do
  @moduledoc """
  How a weapon is held — and whether it can be held at all (task 3.43).

  🔴 **Grip is a function of TWO sizes**, and everything here follows from that
  one sentence. `fandom:Two-handed weapon`: «a weapon whose weapon size is one
  category larger than **its wielder**». A longsword is one-handed for a human
  and two-handed for a Карлик; a greatsword is two-handed for a human and cannot
  be wielded by a Карлик at all. Reading a grip off a single column would be right for
  five races out of seven and wrong for the two that matter — which is why
  `weapons.json` keeps the rule in `_grip` and the *value* Siala states in
  `siala_grip`, and why they are composed here rather than in the data.

  ## Two statements, and the derived one may only make the grip heavier

  The dictionary carries a grip stated outright by Siala's «Система оружия», and
  that column is true **for a wielder of one size** — `wield.stated_grip_size`.
  For anybody else the size rule is applied on top, and it may only take a hand
  away, never give one back:

    * a light crossbow is `two_handed` on that page while being a *small* weapon,
      so a Карлик (small) would get it back to one hand by the size rule alone —
      and every bow and crossbow with it. The size rule says what makes a weapon
      two-handed; it does not say that everything else is one-handed;
    * a longsword is `one_handed` there and *medium*, so a Карлик gets it as
      two-handed — which is exactly the measurement this task was written for
      (Dan, 16.08.2026, `GAME_CHECKS.md` R2b: у Карлика кинжал и короткий меч
      берутся со щитом, длинный меч — нет).

  ⚠ The stated column is read on **both** rulesets, vanilla included, and that is
  a deliberate choice rather than an oversight: it is the only per-weapon grip
  either wiki states at all, and dropping it on vanilla would hand a bow-wielding
  human a shield. What is genuinely vanilla — the ladder and the two thresholds —
  is applied on both as well.

  ## What is refused, and by whom

  Two different refusals, and the difference is the whole reason the third one
  exists at all:

    * **more than one category larger — cannot be wielded at all**, which is
      *not* «двуручно». `fandom:Two-handed weapon`: «Weapons more than one size
      category larger than the wielder are not considered two-handed weapons
      because they cannot be wielded at all». That is this module's
      `refusal/3`, and it lands on the **weapon**;
    * **exactly one category larger — two-handed**, and then the off hand is
      taken. That refusal lands on the **shield**, not on the weapon, and so it
      lives in `BuildCalculator.Rules.Worn` beside the thing being refused.

  ## A third question, and it is not about size at all (task 3.142)

  «Сколькими руками» is not «в какой руке». `fandom:Ranged weapon` (revid
  70660): «No ranged weapon may be wielded in the off-hand slot, nor can any
  weapon be wielded in the off-hand when a ranged weapon is in the main hand.
  That is, dual-wielding is not an option with ranged weapons.» That is **two**
  bans in one sentence, keyed by a **property** of the weapon rather than by its
  size, and the second does not follow from the first: a sling is one-handed, so
  by grip alone its off hand is free.

  ⚠ **The second ban keeps out a `weapon`, and the source says so in that
  word.** The neighbouring two-handed rule is worded wider on the same wiki —
  «they also block equipping **anything** in the off-hand slot» — and the gap
  between «weapon» and «anything» is exactly the archer's shield: with a sling
  in hand he keeps it (Dan, 30.08.2026, `GAME_CHECKS.md` AI2). So the ruleset
  names *what* is kept out, out of `off_hand_occupants/0`, and a scope this core
  cannot enforce fails the build instead of never firing.

  ⚠ Until 30.08.2026 neither ban existed here, and four ranged weapons went into
  the off hand while the other four were turned away by an unrelated refusal
  (they are two-handed) — a coincidence of outcome rather than a rule.

  ## Nothing here knows a size, a grip, a race or a weapon

  The ladder (`size_order`), the window a weapon has to fall inside
  (`wieldable_steps`), which step makes which grip (`grip_by_step`,
  `grip_otherwise`) and which grips take both hands all come out of
  `ruleset.wield`; the wielder's size comes off the race record and the weapon's
  off its own. There is no `:medium`, no `:large` and no `:two_handed` in this
  file — grip words are compared, never written — the same way `Rules.Worn` holds
  no tower shield and `Rules.RacialBonus` no race.

  A ruleset whose snapshot states no ladder answers `nil` to every question here
  rather than «allowed»: the loader reports `{:missing_data, :weapon_size_rules}`
  and refuses a half-stated block outright.
  """

  alias BuildCalculator.Rules.Build

  @typedoc """
  Why a weapon may not be in this character's hands at all.

  ⚠ Two forms for the two halves of one sentence («up to one size larger … and
  down to two sizes smaller»). Only the first is reachable on the shipped data —
  four rungs and two playable sizes leave nothing more than two categories
  smaller than anyone — and the second is written anyway, because a refusal that
  cannot be worded is worse than one that never fires, and because the ladder is
  data and may grow a rung.
  """
  @type reason :: {:weapon_too_large, atom()} | {:weapon_too_small, atom()}

  @doc """
  The size rules this ruleset states — `%{}` when its snapshot states none.

  Exposed so callers can tell «no ladder» from «nothing refused» without reading
  the ruleset's shape themselves.
  """
  @spec rules(map()) :: map()
  def rules(ruleset), do: Map.get(ruleset, :wield) || %{}

  @doc "Whether this ruleset states the size ladder every rule here steps along."
  @spec known?(map()) :: boolean()
  def known?(ruleset), do: ladder(ruleset) != []

  @doc """
  The size of the character himself — `nil` when no race is chosen, or when the
  snapshot states no size for it.

  Read off the **race**, never off a feat: `Small stature` is a feat gnomes and
  halflings happen to carry, and nobody ever stated that the two are the same
  fact (задача 3.44).
  """
  @spec wielder_size(Build.t(), map()) :: atom() | nil
  def wielder_size(%Build{race: nil}, _ruleset), do: nil

  def wielder_size(%Build{race: race}, ruleset) do
    case Map.get(races(ruleset), race) do
      %{size: size} -> size
      _unknown -> nil
    end
  end

  @doc """
  How `weapon_id` is held by **this** character — `nil` when nothing can be said.

  `nil` covers the three ways the answer is genuinely unknown and they are one
  answer on purpose: the weapon states no grip and no size (the unarmed strike),
  the character has no race yet, or the snapshot has no ladder. All three mean
  the same thing to a caller — do not refuse anything on this ground — and the
  caveat that says so belongs where the number is (`Rules.Worn.gaps/2`).

  ⚠ A weapon too large to be wielded also answers `nil`: it is not held in any
  number of hands. `refusal/3` is what says so.
  """
  @spec grip(Build.t(), atom(), map()) :: atom() | nil
  def grip(%Build{} = build, weapon_id, ruleset) do
    weapon = Map.get(weapons(ruleset), weapon_id)
    stated = weapon && Map.get(weapon, :stated_grip)

    compose(rules(ruleset), stated, step(build, weapon, ruleset))
  end

  @doc """
  Whether the weapon leaves the off hand free.

  `false` when the grip is unknown — an unknown is not a refusal, and a shield
  taken away on a guess would be exactly the silent confiscation this project
  treats as a bug.
  """
  @spec both_hands?(Build.t(), atom(), map()) :: boolean()
  def both_hands?(%Build{} = build, weapon_id, ruleset) do
    rule = rules(ruleset)
    grips = Map.get(rule, :both_hands_grips) || MapSet.new()

    MapSet.member?(grips, grip(build, weapon_id, ruleset)) and
      not off_hand_free?(rule, Map.get(weapons(ruleset), weapon_id))
  end

  # 🔴 Оружие, чей объявленный хват вторую руку НЕ занимает, хотя и назван
  # двуручным. Сегодня свойство ровно одно — `thrown`, и оно ИЗМЕРЕНО
  # (Dan 16.08.2026, `GAME_CHECKS.md` кейс R5): колонка Сиалы зовёт дротик
  # «двуручное/метательное», а щит с ним в игре остаётся. Значит «двуручное»
  # там про БРОСОК, а не про занятую руку.
  #
  # ⚠ До правки мы отбирали щит у КАЖДОГО метателя, и на обоих ruleset'ах —
  # то есть ошибка была не про малую расу и не про Сиалу, а общая.
  #
  # ⚠ Имя свойства приходит из данных (`_siala_grip.both_hands_excludes_when`),
  # и в этом модуле его нет: `thrown` — такое же игровое слово, как имя размера.
  # Свойства нет в правиле — значит хват решает один, как и было.
  defp off_hand_free?(_rule, nil), do: false

  defp off_hand_free?(rule, weapon) do
    case Map.get(rule, :off_hand_free_when) do
      nil -> false
      property -> Map.get(weapon, :"#{property}?") == true
    end
  end

  # Свойство, при котором предложение источника про лёгкое оружие про это
  # оружие не сказано вовсе («A **melee** weapon…»). Имя поля посчитал
  # загрузчик по закрытому словарю ядра; правило, которое свойства не называет,
  # не исключает ничего.
  defp excluded_from_light?(_rule, nil), do: true

  defp excluded_from_light?(rule, weapon) do
    case Map.get(rule, :light_excludes_field) do
      nil -> false
      field -> Map.get(weapon, field) == true
    end
  end

  @doc """
  Whether `weapon_id` is a **light weapon** for this character — `nil` when
  nothing can be said.

  The second sentence of the same paragraph the grip comes from
  (`fandom:Weapon size`, revid 59292): «A melee weapon at least one size smaller
  than the wielder is considered a light weapon». So it is the same step along
  the same ladder, compared against the threshold the ruleset states
  (`_grip.light_at_most_step`) rather than against a number written here.

  ⚠ **The «melee» in that sentence is carried, not dropped.** A ranged weapon is
  not *said* to be light, and answering `true` for it would widen a quoted rule
  past its own words — the mistake task 3.124 had to undo one file over. Which
  property disqualifies a weapon is the ruleset's word too
  (`_grip.light_excludes_property`, resolved to a field the core can read).

  ⚠ **The grip does not answer this and cannot.** A light weapon is still
  one-handed, so `grip/3` says nothing about it: «сколько рук» and «лёгкое ли
  оно» are two sentences of the source and two keys of the data.

  `nil` means the same three things it means for `grip/3` — no size on the
  weapon, no race on the character, no ladder in the snapshot — and one more:
  the ruleset states no threshold. All four are «нельзя сказать», and the caller
  owes the player a caveat rather than a number (`Rules.DualWield.gaps/2`).

  ⚠ Until 28.08.2026 the rule was prose in `weapons.json` and nothing read it,
  which is the fifth time this project found that shape of defect (`Zen
  archery`, the racial bonus's activation, the base score a feat's prerequisite
  reads, `casts_spell_level` — CLAUDE.md §9). It reaches a number now: the
  two-weapon penalty drops by 2 on **both** hands when the off-hand weapon is
  light.
  """
  @spec light?(Build.t(), atom(), map()) :: boolean() | nil
  def light?(%Build{} = build, weapon_id, ruleset) do
    rule = rules(ruleset)
    weapon = Map.get(weapons(ruleset), weapon_id)

    case {Map.get(rule, :light_at_most_step), step(build, weapon, ruleset)} do
      {nil, _step} -> nil
      {_threshold, nil} -> nil
      {threshold, step} -> step <= threshold and not excluded_from_light?(rule, weapon)
    end
  end

  @doc """
  What this core is able to keep out of the off hand — the closed list a ruleset
  states its ban against.

  Asked by the loader, so a snapshot naming something nobody enforces fails the
  build rather than producing a ban that silently never fires — the same
  arrangement `Rules.Attack.weapon_property_field/1` has with weapon properties.

  ⚠ `:worn` is deliberately **absent**, and that absence is the archer's shield.
  The source keeps a *weapon* out of the off hand and says nothing about a
  shield; the day a snapshot claims otherwise, the build stops instead of
  quietly confiscating one.
  """
  @spec off_hand_occupants() :: [atom()]
  def off_hand_occupants, do: [:weapon]

  @doc """
  Whether this weapon may not be held in the off hand at all.

  `false` when the ruleset states no such ban — a rule that names no property
  excludes nothing, the same default `off_hand_free?/2` above keeps.

  ⚠ Takes no build: unlike the grip, this is a property of the **weapon** and
  not of the pair. A sling is barred from a halfling's off hand and from a
  human's alike.
  """
  @spec barred_from_off_hand?(atom(), map()) :: boolean()
  def barred_from_off_hand?(weapon_id, ruleset) do
    case Map.get(rules(ruleset), :off_hand) do
      %{barred?: true, field: field} -> property?(ruleset, weapon_id, field)
      _no_ban -> false
    end
  end

  @doc """
  Whether this weapon, held in the **main** hand, keeps `occupant` out of the
  other one.

  The second half of the same sentence, and a separate question from the first:
  a sling may not go in the off hand *and* leaves no off hand for a dagger,
  while being one-handed throughout.

  `occupant` is one of `off_hand_occupants/0`. Anything else answers `false`
  rather than raising: the loader is where an unenforceable scope stops the
  build, and by the time a build is being computed the list has already been
  checked.
  """
  @spec bars_from_off_hand?(atom(), map(), atom()) :: boolean()
  def bars_from_off_hand?(weapon_id, ruleset, occupant) when is_atom(occupant) do
    case Map.get(rules(ruleset), :off_hand) do
      %{bars: bars, field: field} ->
        MapSet.member?(bars, occupant) and property?(ruleset, weapon_id, field)

      _no_ban ->
        false
    end
  end

  @doc """
  Why this character may not wield `weapon_id` at all — `nil` when he may.

  ⚠ **Not «two-handed»**: this is «cannot be wielded at all», the sentence a
  greatsword gets from a halfling. The two were separate statements on the source
  page and stay separate here — one refuses the weapon, the other refuses the
  shield beside it.
  """
  @spec refusal(Build.t(), atom(), map()) :: reason() | nil
  def refusal(%Build{} = build, weapon_id, ruleset) do
    rule = rules(ruleset)
    weapon = Map.get(weapons(ruleset), weapon_id)

    case step(build, weapon, ruleset) do
      nil -> nil
      step when step > rule.wieldable_to -> {:weapon_too_large, build.race}
      step when step < rule.wieldable_from -> {:weapon_too_small, build.race}
      _within_the_window -> nil
    end
  end

  # ------------------------------------------------------------------ private --

  defp races(ruleset), do: Map.get(ruleset, :races) || %{}

  # Свойство справочника по ИМЕНИ ПОЛЯ, посчитанному загрузчиком. Ни `ranged`,
  # ни любого другого игрового слова в этом модуле нет — как нет здесь размера,
  # хвата и расы.
  defp property?(ruleset, weapon_id, field) do
    case Map.get(weapons(ruleset), weapon_id) do
      %{^field => true} -> true
      _absent_or_false -> false
    end
  end

  defp weapons(ruleset), do: Map.get(ruleset, :weapons) || %{}
  defp ladder(ruleset), do: Map.get(rules(ruleset), :size_order) || []

  # На сколько ступеней оружие крупнее владельца — `nil`, если размера не знает
  # хотя бы одна из сторон или лестницы нет вовсе.
  defp step(build, weapon, ruleset) do
    with ladder when ladder != [] <- ladder(ruleset),
         weapon_size when not is_nil(weapon_size) <- weapon && Map.get(weapon, :size),
         wielder_size when not is_nil(wielder_size) <- wielder_size(build, ruleset),
         weapon_at when not is_nil(weapon_at) <- Enum.find_index(ladder, &(&1 == weapon_size)),
         wielder_at when not is_nil(wielder_at) <- Enum.find_index(ladder, &(&1 == wielder_size)) do
      weapon_at - wielder_at
    else
      _unknown -> nil
    end
  end

  # Правило может сделать хват ТЯЖЕЛЕЕ и никогда легче — см. moduledoc про
  # арбалет. Отсюда порядок веток:
  #
  #   * вне окна — ответа нет вовсе (оружие не держат ни в скольких руках);
  #   * колонка, которая уже занимает обе руки, остаётся как есть. Иначе
  #     двустороннее оружие («двустороннее» — своё, третье значение справочника)
  #     у человека превращалось бы в обычное двуручное просто потому, что оно
  #     крупнее его на категорию, то есть правило стирало бы более точное
  #     утверждение источника;
  #   * иначе шаг по лестнице перебивает колонку, а её отсутствие — значение
  #     по умолчанию. Все три имени хвата приходят из данных
  #     (`_grip.grip_by_step`, `_grip.grip_otherwise`).
  defp compose(_rule, stated, nil), do: stated

  defp compose(rule, stated, step) do
    cond do
      step > rule.wieldable_to or step < rule.wieldable_from ->
        nil

      MapSet.member?(rule.both_hands_grips, stated) ->
        stated

      true ->
        Map.get(rule.grip_by_step, step) || stated || rule.grip_otherwise
    end
  end
end
