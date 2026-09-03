defmodule BuildCalculator.Rules.FeatChoices do
  @moduledoc """
  Feats that are taken **with** something, and may be taken again for something else.

  `Favored enemy` names a creature type and a ranger picks another one every five
  levels; `Spell focus` names a school, `Skill focus` a skill, `Weapon focus` a
  weapon. Storing the bare feat id cannot say which, so a slot may hold
  `{feat_id, choice}` as well as `feat_id` (`BuildCalculator.Rules.Build`), and
  this module is the rule that reads it.

  ## Nothing here knows a feat by name

  Which feats repeat, and out of what, is data:

      "repeatable": {"choice": "creature_type", "quote": "…", "source": {…}}

  No block, no repetition — which is every feat until the data says otherwise, so
  the rule this replaces ("a feat is taken once") is simply what an empty key
  means. There is no list of repeatable feats in this file and there must never
  be one: the day the shard makes a sixth feat repeatable, the answer has to come
  from the wiki, not from a clause somebody remembered to add.

  The same goes for the values. A domain resolves to a dictionary through
  `BuildCalculator.Data.Loader.choice_domains/2` — a file, or a dictionary the
  ruleset already carries — and never to a list written out here.

  ## Repetition without a parameter is a *count*

      "repeatable": {"choice": null, …}

  Sixteen feats repeat while naming nothing, and they are not exotic:
  `Epic toughness` is taken ten times on an ordinary epic build, and so are the
  six `Great …`. Another slot spent on the feat is another take, and the number
  of takes is read off the picks (`Build.feat_takes/3`) rather than kept anywhere
  — a counter beside the picks would be the same fact stated twice, and two
  statements of one fact drift.

  ⚠ `distinct?` is not consulted on this path and cannot be: with no domain there
  is nothing for two picks to differ in. The loader records it as `nil` for
  exactly that reason, and a value offered to such a feat is refused like a value
  offered to a feat that takes none.

  The pair is still the key where there *is* a domain, so a count applies to it
  too: `Epic energy resistance` may be taken twice for fire and once for
  electricity (Дан, 02.08.2026), which is two takes of one pair and one of
  another — not three of the feat.

  ## The ceiling is stated or unknown, never guessed

  Every page in this family names a ceiling and almost none of them names it in
  takes: «up to a maximum of 200 hit points», «to a maximum of +10». The number
  of takes cannot be worked out from that — a plausible ten is the sort of
  number CLAUDE.md §3 forbids inventing — so a ceiling on **takes** is enforced
  only where the data states one (`repeatable.max_takes`, see the loader), and
  where it does not the build says so: `{:missing_data, {:feat_max_takes, id}}`.
  Silence would read as "checked".

  ⚠ The ceiling on the **effect** is a separate fact and is applied separately
  (`BuildCalculator.Rules.FeatBonuses`, task 1.9): a ruleset with no take
  ceiling still cannot grow `Epic toughness` past the two hundred hit points
  its page names. Two ceilings, two provenances — the page's and Дан's — and
  neither is derived from the other.

  ⚠ They also count **different things**, and that is measured rather than
  chosen. The take ceiling counts slots only (`Build.feat_takes/3`): «брать эти
  фиты в билде также можно вплоть до 10 раз (если фит уже взят с вещи его можно
  взять при левел апе этот же фит)» — Dan, 14.08.2026, `GAME_CHECKS.md` H8. The
  effect ceiling counts what the character has, item included
  (`Build.feat_takes_owned/4`), and it is what keeps ten picks plus an amulet at
  two hundred hit points instead of two hundred and twenty: «как максимум для
  УЧЁТА там всё равно будет только 10 раз».

  ## The uniqueness key is the pair, not the choice

  `Spell focus (evocation)` uses up evocation **for `Spell focus`**. Taking
  `Greater spell focus` and then `Epic spell focus` in that same school is not
  merely allowed, it is the whole point of the family (Дан, 02.08.2026). So the
  duplicate check is scoped to one feat id, and `Build.feat_choices/3` is scoped
  the same way.

  The other direction is a requirement rather than a duplicate:
  `Greater spell focus` must be taken in a school the character already has
  `Spell focus` in. The wiki writes that as prose — `[[spell focus]] (selected
  spell school)` — which used to travel as a `qualifier`, "checked nothing, said
  so". With choices recorded it becomes checkable, and the data says which feats
  it binds:

      "prereqs": {"feats": ["spell_focus"], "same_choice_as": ["spell_focus"]}

  Absent, as it is until the parser writes it, the qualifier stays a qualifier
  and nothing here fires.

  ⚠ The two directions look alike and are answered differently on purpose, which
  is the whole of `candidates/3`'s contract: a value **this feat** already holds
  is hidden, a value the *required* feat does not hold is refused with a reason
  (решение Дана, CLAUDE.md §6). Both used to leave the list empty and the empty
  list said "exhausted" either way, so a character with no `Spell focus` at all
  was told he had used up all eight schools.

  ## Three honest answers about a domain, not two

  A domain either has a dictionary or does not, and "does not" is a legitimate
  answer rather than a hole to be filled:

    * **dictionary, value outside it** — refused, by the data. `ooze` is in
      `creature_types.json` marked `favored_enemy: false`, and that flag is what
      refuses it; no clause in this module mentions oozes. A value no feat at all
      may take is gated the same way under a reserved name — see `values/3`.
    * **no dictionary** — the feat stays takeable and the build carries
      `{:missing_data, {:choice_domain, …}}`: the player may take it, we simply
      cannot say with what. ⚠ `weapon` was the example here until task 3.5 gave
      it a dictionary of 47 (part A) and the gear block a weapon in hand (part B);
      no domain answers this way today, and the branch stays because a domain the
      data grows before its values arrive is the ordinary order of work.
    * **a domain the core cannot resolve at all** — the same answer, because it
      is the same knowledge. The core genuinely cannot tell an unmodelled domain
      from a misspelt one, and inventing a distinction it cannot honour would be
      worse than admitting there is none.

  ## What is *not* modelled

  The feat's own effect, in this module. Favored Enemy is +1 damage at ranger 1
  rising to +9 at 40, and it scales with the **class level**, not with how many
  enemies were chosen — a Harper Scout has a separate scale and the two do not
  add up (`fandom:Favored enemy`). None of that is in the data as numbers, and
  no build gets a bonus out of it here, so a repeatable feat a build takes
  reports `{:not_modelled, {:feat_bonus, id}}`: a calculator that records the
  choice and silently drops its effect looks exactly like one that counted it.

  ⚠ Since task 1.9 that is no longer true of *every* one of them. Where the
  data both states the effect and says it is the whole of what the feat does
  (`vanilla/feat_hp_bonuses.json`, `effect_coverage: "whole_feat"` — today
  `Epic toughness`), the core counts it and this caveat comes off; leaving it
  on would have the caveat argue with a term the player can see in the hit
  point breakdown. The judgement is the data's, never this module's — see
  `effect_gap/2`.

  🔴 **И с задачи 3.93 (25.08.2026) есть вторая причина, по которой оговорки
  нет, — совсем другого рода.** Первая говорит «прибавку посчитали»; вторая —
  «числа, в которое она падает, у нас нет вовсе». Пятнадцать повторяемых фитов
  из восемнадцати печатали «прибавку в статы не считаем» про урон, ДЦ ЧУЖОГО
  спасброска, метамагию, сопротивления и маскировку, то есть про механики, про
  которые калькулятор ответа не даёт, а гэп — дырка **в ответе** (CLAUDE.md §9,
  решение Dan 10.08.2026). Метку получателя несут данные
  (`vanilla/feat_effect_receivers.json`), судит её тот же `Rules.GapReceivers`
  и тот же словарь, что судит факты шарда, и умолчание прежнее: **метки нет —
  оговорка остаётся**.

  ⚠ Различать эти две причины важно при чтении диффа: снятие по первой значит
  «число появилось на экране», снятие по второй — «числа не будет, и мы
  перестали делать вид, что должны его». Сегодня по второй причине молчат
  шестнадцать фитов, а `Arcane defense` и `Favored enemy` продолжают говорить:
  их прибавка падает в наши сейвы и в наши навыки, просто сужена условием,
  которого билд не описывает.
  """

  alias BuildCalculator.Rules.{
    AbilityBonuses,
    AttackBonuses,
    Build,
    FeatBonuses,
    GapReceivers,
    GearFeats,
    GearWeapon,
    SaveBonuses,
    Skills,
    SpellResistance
  }

  @type reason ::
          {:already_taken, atom()}
          | {:not_granted, atom()}
          | {:choice_already_taken, atom(), term()}
          | {:max_takes, atom(), pos_integer()}
          | {:requires_choice, atom(), atom()}
          | {:requires_same_choice, atom(), term()}
          | {:invalid_choice, atom(), term()}
          | {:choice_exhausted, atom(), atom()}
          | {:choice_requires, atom(), [atom()], atom()}
          | {:missing_data, {:choice_domain, atom()}}

  @typedoc """
  A pick being asked about.

    * `:feat` — required
    * `:choice` — what it is taken with; `nil`/absent is "nothing recorded"
    * `:at` — the character level it is picked on; defaults to the build's last
    * `:slot` — the slot it goes in. Given, the pick already sitting there is
      **left out** of the character's history, so asking about a build that
      already contains the pick does not collide it with itself.
  """
  @type pick :: %{
          required(:feat) => atom(),
          optional(:choice) => term(),
          optional(:at) => pos_integer(),
          optional(:slot) => Build.slot_id()
        }

  @doc """
  Whether this pick is legal as far as repetition and the parameter go.

  Prerequisites are **not** checked here — that is `Rules.validate_feat/3`, and
  `Rules.validate_feat_pick/3` is the two together.
  """
  @spec validate(Build.t(), pick(), map()) :: :ok | {:error, [reason()]}
  def validate(%Build{} = build, pick, ruleset) do
    case reasons(build, pick, ruleset) do
      [] -> :ok
      reasons -> {:error, reasons}
    end
  end

  @doc """
  Every reason this pick is illegal, in a stable order (empty when it is legal).
  """
  @spec reasons(Build.t(), pick(), map()) :: [reason()]
  def reasons(%Build{} = build, pick, ruleset) do
    id = Map.fetch!(pick, :feat)
    choice = Map.get(pick, :choice)
    level = level(build, pick)
    history = history(build, pick, level)

    case Map.fetch(ruleset.feats, id) do
      :error -> [{:unknown_feat, id}]
      {:ok, feat} -> feat_reasons(history, feat, choice, level, ruleset)
    end
  end

  defp feat_reasons(history, feat, choice, level, ruleset) do
    case repeatable(feat) do
      nil ->
        single_take_reasons(history, feat, choice, level, ruleset)

      %{choice: nil} = repeatable ->
        counted_reasons(history, feat, repeatable, choice, level, ruleset)

      repeatable ->
        repeat_reasons(history, feat, repeatable, choice, level, ruleset)
    end
  end

  # Same defensive read as `disabled?` elsewhere in the core: the key arrives
  # with the data layer, and a record assembled by hand (a test fixture, an older
  # snapshot) simply has not got it. Absent is "not repeatable", which is the
  # rule as it stood.
  defp repeatable(feat) do
    case Map.get(feat, :repeatable) do
      %{} = block -> block
      _absent -> nil
    end
  end

  # The rule as it stood: one of each. Kept in the core rather than left to the
  # picker, because whether it applies at all is now a property of the data.
  #
  # ⚠ `feats_permanent/3`, **not** `feats_owned/3`, and the difference is one
  # false illegality (09.08.2026). A feat an item lends is owned — its bonus is in
  # the numbers and its requirements are satisfied (task 3.3) — but an item comes
  # off, and refusing the permanent version of a borrowed feat cost the player a
  # legal build: a wizard with `Toughness` on an amulet could not put `Toughness`
  # in a slot, while the same wizard without the amulet could. The precedent is
  # the feat a **class** hands over for free, where the calculator warns and does
  # not refuse (CLAUDE.md §6), and the argument is stronger here — a class grant
  # cannot be lost. The warning is `Rules.feat_pick_caveats/3`.
  #
  # A class grant does still refuse, because it cannot be lost either: the
  # character has the feat for the rest of the build whatever he does.
  defp single_take_reasons(history, feat, choice, level, ruleset) do
    taken? = MapSet.member?(Build.feats_permanent(history, ruleset, level), feat.id)

    List.flatten([
      if(taken?, do: [{:already_taken, feat.id}], else: []),
      # A parameter on a feat that takes none is not a harmless extra: it would
      # read as a distinguishing mark and let the feat in twice.
      if(is_nil(choice), do: [], else: [{:invalid_choice, feat.id, choice}])
    ])
  end

  # Repeatable with nothing to name. There is no duplicate to look for — every
  # pick is another take, which is what the page means — so the only two things
  # that can be wrong are a value on a feat that accepts none and a count past a
  # ceiling the data actually states.
  #
  # ⚠ `feat_takes/3` — **slots only**, and the item is not one of them (замер Dan,
  # 14.08.2026, `GAME_CHECKS.md` H8): «брать эти фиты в билде также можно вплоть
  # до 10 раз (если фит уже взят с вещи его можно взять при левел апе этот же
  # фит)». Nine picks and an amulet leave the tenth pick available.
  #
  # ⚠ This paragraph used to argue the opposite — that the ceiling had to count
  # the item or it «could be walked around by wearing the feat instead of picking
  # it». That was **our** inference, the one thing in H8 nobody had said, and it
  # was wrong. What actually closes the loophole is the ceiling on the *effect*,
  # which Dan named in the same breath: «как максимум для УЧЁТА там всё равно
  # будет только 10 раз», i.e. 200 hit points whatever the mix. That one lives in
  # `Rules.FeatBonuses` (`max_total`) and reads `feat_takes_owned/4` still, so ten
  # picks plus an amulet are 200 and not 220.
  # ⚠ `_ruleset` is kept in the signature on purpose: it is the only one of the
  # three `*_reasons` heads that needs nothing from the ruleset, and dropping the
  # argument would make the three read as three different kinds of thing.
  defp counted_reasons(history, feat, repeatable, choice, level, _ruleset) do
    List.flatten([
      # Same refusal, and for the same reason, as a value on a feat that takes no
      # parameter at all: there is no domain to check it against, and letting it
      # through would have it read as a distinguishing mark.
      if(is_nil(choice), do: [], else: [{:invalid_choice, feat.id, choice}]),
      over_max_takes(feat, repeatable, Build.feat_takes(history, feat.id, level))
    ])
  end

  # ⚠ Only ever a number the data states. Nothing is worked out from the quote:
  # «to a maximum of 200 hit points» is a ceiling on an effect this core does not
  # model, and turning it into ten takes would be arithmetic on a number nobody
  # wrote down. Where the ceiling is unknown `gaps/3` says so.
  defp over_max_takes(feat, repeatable, taken) do
    case Map.get(repeatable, :max_takes) do
      %{value: max} when is_integer(max) and taken >= max -> [{:max_takes, feat.id, max}]
      _no_stated_ceiling -> []
    end
  end

  defp repeat_reasons(history, feat, repeatable, choice, level, ruleset) do
    domain = repeatable.choice
    previous = Build.feat_choices_permanent(history, ruleset, feat.id, level)

    case {values(feat, domain, ruleset), choice} do
      # No dictionary: nothing about the value can be judged, and saying so is
      # `gaps/3`'s job. Refusing the feat outright would be the opposite lie.
      {:none, _any} ->
        []

      {{:ok, _values}, nil} ->
        [{:requires_choice, feat.id, domain}]

      {{:ok, values}, choice} ->
        List.flatten([
          invalid_choice(values, feat, choice),
          # ⚠ Only non-nil choices collide. Two picks that both recorded nothing
          # are not evidence of a duplicate, and treating them as one would
          # condemn every build made before choices were recorded at all.
          #
          # Where the picks need *not* differ, the same pair simply accumulates
          # and a stated ceiling applies to it — twice for fire and once for
          # electricity is two takes and one, never three (Дан, 02.08.2026).
          if repeatable.distinct? and choice in previous do
            [{:choice_already_taken, feat.id, choice}]
          else
            over_max_takes(feat, repeatable, Enum.count(previous, &(&1 == choice)))
          end,
          same_choice_reasons(history, feat, choice, level, ruleset)
        ])
    end
  end

  # "…in the chosen school": the named feats must already be held **with this
  # same choice**. Only fires when the pick states its choice — until the
  # interface writes choices, nothing can be compared and refusing on that basis
  # would invent an illegality out of a missing field.
  #
  # ⚠ `feat_choices_permanent/4`, so a value the **class** handed the required
  # feat over with counts too (task 3.26). No feat in either ruleset names a
  # granted feat in `same_choice_as` today — `weapon_of_choice` is on the asking
  # side, not the required side — but reading only slots here would be the same
  # half-truth this task removed from `Rules.AttackBonuses`, and it would fail
  # silently rather than loudly.
  defp same_choice_reasons(history, feat, choice, level, ruleset) do
    for required <- same_choice_as(feat),
        choice not in Build.feat_choices_permanent(history, ruleset, required, level) do
      {:requires_same_choice, required, choice}
    end
  end

  defp same_choice_as(feat) do
    prereqs = Map.get(feat, :prereqs)

    list =
      is_map(prereqs) && (Map.get(prereqs, "same_choice_as") || Map.get(prereqs, :same_choice_as))

    for id <- List.wrap(list || []), is_atom(id) or is_binary(id), do: to_atom(id)
  end

  @doc """
  Сравнивает ли ядро `same_choice_as` у этого фита — то есть работает ли ключ.

  Два условия, и второе легко проглядеть: ключ должен быть в блоке **и** фит
  должен уметь нести значение. `same_choice_reasons/4` достижим только из
  `repeat_reasons/6`, поэтому у неповторяемого фита (или у повторяемого без
  домена выбора) ключ лежит в данных, выглядит применённым и не делает ничего.

  ⚠ Ответ **зависит от ruleset'а**, и в этом весь смысл вопроса: `Epic weapon
  focus` повторяем на Сиале и не повторяем в ванили, то есть одно и то же
  требование там проверяется, а тут нет. Спрашивает `Rules.Prereqs.qualifiers/1`,
  чтобы не печатать «выбор оружия мы не проверяем» билду, у которого он
  проверен, — и наоборот, чтобы не молчать там, где не проверен.

  🔴 Функция публичная ровно ради одного читателя, и это не удобство:
  вторая реализация этого предиката разошлась бы с первой при первой же
  правке `feat_reasons/5`, и разошлась бы молча — оговорка исчезла бы
  у фита, требование которого никто не проверяет.
  """
  @spec same_choice_enforced?(map() | nil) :: boolean()
  def same_choice_enforced?(feat) when is_map(feat) do
    case repeatable(feat) do
      %{choice: domain} when not is_nil(domain) -> same_choice_as(feat) != []
      _takes_no_value -> false
    end
  end

  def same_choice_enforced?(_absent), do: false

  @doc """
  What this feat will accept here — the list the interface offers, computed once.

    * `:no_choice` — the feat takes no parameter. Which includes one that
      repeats without naming anything: there is nothing to offer, and how many
      times it may be taken is a different question (`validate_feat_pick/3`).
    * `{:ok, values}` — exactly these, sorted, and **never empty**
    * `{:empty, reasons}` — nothing to offer, and the machine reason why
    * `{:error, reasons}` — cannot be said at all, with the machine reason why

  Built in the core deliberately. `Greater spell focus` offers "the schools that
  already have `Spell focus`, less the ones that already have `Greater`" — that
  is a game rule, and an interface that reassembles it from parts is a second
  implementation of it (CLAUDE.md §5).

  ## Why an empty list is not an answer

  It used to be one — `{:ok, []}`, documented as "the feat is exhausted" — and
  that sentence was true of one of the two ways the list empties. The other is
  the precondition: `Greater spell focus` draws from *the schools that already
  have `Spell focus`*, so a character with none has an empty list before he has
  chosen anything at all. Both arrived as `[]`, the picker had one wording for
  it, and a wizard who had never taken `Spell focus` was told he had taken all
  eight schools already (найдено Dan, 03.08.2026).

  So the two are separate constructors of the same fact, and the fact that
  cannot be said at all (`weapon` has no dictionary and will not before the
  armoury) stays a third — «мы не знаем» and «нечего предложить» are different
  answers and the interface has to word them differently.
  """
  @spec candidates(Build.t(), pick(), map()) ::
          :no_choice | {:ok, [atom(), ...]} | {:empty, [reason()]} | {:error, [reason()]}
  def candidates(%Build{} = build, pick, ruleset) do
    id = Map.fetch!(pick, :feat)
    level = level(build, pick)
    history = history(build, pick, level)

    with {:ok, feat} <- Map.fetch(ruleset.feats, id),
         %{choice: domain} = repeatable when not is_nil(domain) <- repeatable(feat) do
      case values(feat, domain, ruleset) do
        :none -> {:error, [{:missing_data, {:choice_domain, domain}}]}
        {:ok, values} -> offer(values, history, feat, repeatable, domain, level, ruleset)
      end
    else
      :error -> {:error, [{:unknown_feat, id}]}
      _no_domain -> :no_choice
    end
  end

  # ------------------------------------------ the choice a CLASS GRANT owes --

  @doc """
  Feats the class taken at `level` hands over that are taken **with** a value,
  and what has been recorded for each.

  `Weapon of choice` is the one such grant in either ruleset (counted by walking
  `granted_feats` on both, 10.08.2026) and the reason this exists: the Weapon
  Master is *given* the feat at his first class level and still has to say which
  weapon it names, which is Dan's observation of 10.08.2026 and task 3.26.

  Each entry carries the feat, the domain it draws from and `choice` — the value
  recorded on this level, or `nil` when none is. `[]` for a level that grants
  nothing, or grants nothing that names a value.

  ⚠ **The raw grant list** (`Build.granted_feats_at/3`), not the display one.
  Whether a *repeat* grant is worth showing is a question about the screen, and
  it already has an answer in one place — `BuildCalculatorWeb.Builder.Feats.
  granted/3`, which subtracts what the character already owns (баг 1.14).
  Repeating that reading here would be a second copy of it; a caller that wants
  both intersects the two.
  """
  @spec granted_choices_owed(Build.t(), map(), pos_integer()) ::
          [%{feat: atom(), domain: atom(), choice: Build.feat_choice() | nil}]
  def granted_choices_owed(%Build{} = build, ruleset, level) when level >= 1 do
    for feat_id <- Build.granted_feats_at(build, ruleset, level),
        domain = domain(feat_id, ruleset),
        not is_nil(domain) do
      %{feat: feat_id, domain: domain, choice: Build.granted_choice(build, level, feat_id)}
    end
  end

  @doc """
  What the feat granted on `level` will accept — the same four answers
  `candidates/3` gives, plus one this question has and a slot pick does not.

  `{:error, [{:not_granted, feat}]}` — the level does not hand this feat over at
  all, so there is nothing to choose *for*. A hand-edited link can ask; the
  picker never does.

  Everything else is answered by exactly the machinery a slot pick goes through
  — the domain's dictionary and its gates, the values this feat already holds
  (hidden, решение Дана), the values `same_choice_as` demands (refused with a
  reason). Two implementations of «which weapons may a Weapon Master choose»
  would be one too many, and the second would be the one that drifts.
  """
  @spec granted_candidates(Build.t(), map(), atom(), pos_integer()) ::
          :no_choice | {:ok, [atom(), ...]} | {:empty, [reason()]} | {:error, [reason()]}
  def granted_candidates(%Build{} = build, ruleset, feat_id, level) when level >= 1 do
    history = granted_history(build, level, feat_id)

    with {:ok, feat} <- Map.fetch(ruleset.feats, feat_id),
         :ok <- granted_here(build, ruleset, feat_id, level),
         %{choice: domain} = repeatable when not is_nil(domain) <- repeatable(feat) do
      case values(feat, domain, ruleset) do
        :none -> {:error, [{:missing_data, {:choice_domain, domain}}]}
        {:ok, values} -> offer(values, history, feat, repeatable, domain, level, ruleset)
      end
    else
      :error -> {:error, [{:unknown_feat, feat_id}]}
      {:error, reasons} -> {:error, reasons}
      _no_domain -> :no_choice
    end
  end

  @doc """
  Every reason recording `choice` for the feat granted on `level` is illegal
  (empty when it is legal).

  The same rules as a slot pick, in the same order, and one of them is the point
  of the task: `weapon_of_choice` carries
  `prereqs.same_choice_as: ["weapon_focus"]` («[[weapon focus]] (chosen
  weapon)»), so the weapon a class hands the feat over with still has to be a
  weapon the character has `Weapon focus` in. A grant that checked nothing would
  let the picker build an illegal character, and this project is deliberately
  stricter than the engine rather than looser (CLAUDE.md §6).

  Clearing a value is never asked about — taking a pick back is always legal.
  """
  @spec granted_reasons(Build.t(), map(), atom(), Build.feat_choice(), pos_integer()) ::
          [reason()]
  def granted_reasons(%Build{} = build, ruleset, feat_id, choice, level) when level >= 1 do
    history = granted_history(build, level, feat_id)

    case Map.fetch(ruleset.feats, feat_id) do
      :error ->
        [{:unknown_feat, feat_id}]

      {:ok, feat} ->
        case granted_here(build, ruleset, feat_id, level) do
          {:error, reasons} -> reasons
          :ok -> granted_choice_reasons(history, feat, choice, level, ruleset)
        end
    end
  end

  @doc "`:ok`, or every reason `granted_reasons/5` finds."
  @spec validate_granted(Build.t(), map(), atom(), Build.feat_choice(), pos_integer()) ::
          :ok | {:error, [reason()]}
  def validate_granted(%Build{} = build, ruleset, feat_id, choice, level) do
    case granted_reasons(build, ruleset, feat_id, choice, level) do
      [] -> :ok
      reasons -> {:error, reasons}
    end
  end

  # A grant is not a slot, so the repetition rules of a *pick* do not apply to it
  # — the class hands the feat over whether or not the character already has it,
  # and `{:already_taken, …}` here would refuse the game its own grant. What is
  # left is the value: it has to belong to the domain, satisfy `same_choice_as`,
  # and differ from the values this feat is already held with where the data says
  # takes must differ.
  defp granted_choice_reasons(history, feat, choice, level, ruleset) do
    case repeatable(feat) do
      %{choice: domain} = repeatable when not is_nil(domain) ->
        granted_value_reasons(history, feat, repeatable, choice, level, ruleset)

      _no_domain ->
        # Same refusal a value on a parameterless feat gets in a slot, and for the
        # same reason: there is no domain to check it against.
        [{:invalid_choice, feat.id, choice}]
    end
  end

  defp granted_value_reasons(history, feat, repeatable, choice, level, ruleset) do
    previous = Build.feat_choices_permanent(history, ruleset, feat.id, level)

    case {values(feat, repeatable.choice, ruleset), choice} do
      {:none, _any} ->
        []

      {{:ok, _values}, nil} ->
        [{:requires_choice, feat.id, repeatable.choice}]

      {{:ok, values}, choice} ->
        List.flatten([
          invalid_choice(values, feat, choice),
          if(repeatable.distinct? and choice in previous,
            do: [{:choice_already_taken, feat.id, choice}],
            else: []
          ),
          same_choice_reasons(history, feat, choice, level, ruleset)
        ])
    end
  end

  # ----------------------------------------------- the choice an ITEM owes --

  @doc """
  What a feat declared off an **item** will accept — the same four answers
  `candidates/3` gives, and none of the fifth kind a grant has.

  The gates are deliberately **wider** than a slot's or a grant's, and every
  difference is `Rules.GearFeats`'s stated rule rather than a shortcut taken
  here:

    * **nothing about the character is asked.** An item grants what it grants,
      so a declaration is never checked against its own prerequisites — and
      `same_choice_as` is one. A worn `Greater spell focus` therefore offers all
      eight schools, where a picked one offers only the schools the character
      already has `Spell focus` in;
    * **no level**, because `Build.truncate/2` leaves gear alone on purpose:
      an item is worn whichever level is being asked about, so there is no "as
      it stood then" to cut to;
    * **no slot**, so no take is counted and no ceiling on takes applies.

  What is *not* wider: the domain's own dictionary and its per-feat gates
  (`values/3`), and the values this feat is **already declared with**, which are
  hidden exactly as a slot's are and for the same reason — «эту школу ты уже
  взял» teaches nothing (решение Дана, CLAUDE.md §6). Hidden by the **gear's**
  entries only: a school taken in a slot does not use itself up for an amulet,
  because the two are different declarations of a legal build.

  ⚠ Editing an existing declaration therefore asks about a build with that entry
  taken off — `Gear.toggle_feat/3` is what takes it off — the same trick
  `granted_candidates/4` performs internally with `put_granted_choice/4`. It
  cannot be performed internally here, because one feat may be declared off two
  items and nothing in the entry says which of them is being edited.
  """
  @spec gear_candidates(Build.t(), map(), atom()) ::
          :no_choice | {:ok, [atom(), ...]} | {:empty, [reason()]} | {:error, [reason()]}
  def gear_candidates(%Build{} = build, ruleset, feat_id) do
    with {:ok, feat} <- Map.fetch(ruleset.feats, feat_id),
         %{choice: domain} = repeatable when not is_nil(domain) <- repeatable(feat) do
      case values(feat, domain, ruleset) do
        :none ->
          {:error, [{:missing_data, {:choice_domain, domain}}]}

        {:ok, values} ->
          offer(values, feat, domain, declared(build, ruleset, feat, repeatable), [])
      end
    else
      :error -> {:error, [{:unknown_feat, feat_id}]}
      _no_domain -> :no_choice
    end
  end

  @doc """
  Every reason declaring `feat_id` off an item **with** `choice` is illegal
  (empty when it is legal).

  Two questions, and both are about the value alone:

    * the domain accepts it (`choice_reasons/3`, the one place a value meets a
      domain);
    * this feat is not already declared with it, where the data says takes must
      differ. Not a ceiling — `Gear.toggle_feat/3` cannot record the same pair
      twice anyway — but the same sentence the offer list makes by hiding it, so
      that asking and being offered agree.

  ⚠ **A `nil` choice is legal here**, which is the one place this differs from a
  slot pick and a grant: `{:requires_choice, …}` would shut every link written
  before task 3.97. What a declaration owes for saying nothing is a gap
  (`Rules.GearFeats.gaps/2`), never a refusal.

  ⚠ **Nothing about the character is checked**, `same_choice_as` included — see
  `gear_candidates/3` for why, and `Rules.GearFeats` for the measurement it
  rests on.
  """
  @spec gear_reasons(Build.t(), map(), atom(), term()) :: [reason()]
  def gear_reasons(%Build{} = build, ruleset, feat_id, choice) do
    case choice_reasons(feat_id, choice, ruleset) do
      [] -> declared_twice(build, ruleset, feat_id, choice)
      reasons -> reasons
    end
  end

  @doc "`:ok`, or every reason `gear_reasons/4` finds."
  @spec validate_gear(Build.t(), map(), atom(), term()) :: :ok | {:error, [reason()]}
  def validate_gear(%Build{} = build, ruleset, feat_id, choice) do
    case gear_reasons(build, ruleset, feat_id, choice) do
      [] -> :ok
      reasons -> {:error, reasons}
    end
  end

  # The values this feat is already declared with off items — the gear's own
  # half of `Build.feat_choices_owned/4`, and `nil`s dropped for the same reason
  # `held/4` drops them: a declaration that names nothing has used nothing up.
  defp declared(build, ruleset, feat, repeatable) do
    if repeatable.distinct? do
      build.gear
      |> GearFeats.choices(ruleset, feat.id)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()
    else
      MapSet.new()
    end
  end

  defp declared_twice(_build, _ruleset, _feat_id, nil), do: []

  defp declared_twice(build, ruleset, feat_id, choice) do
    with %{} = feat <- Map.get(ruleset.feats, feat_id),
         %{distinct?: true} = repeatable <- repeatable(feat),
         true <- MapSet.member?(declared(build, ruleset, feat, repeatable), choice) do
      [{:choice_already_taken, feat_id, choice}]
    else
      _not_a_duplicate -> []
    end
  end

  defp granted_here(build, ruleset, feat_id, level) do
    if feat_id in Build.granted_feats_at(build, ruleset, level),
      do: :ok,
      else: {:error, [{:not_granted, feat_id}]}
  end

  # The character as it stood for this decision, exactly like `history/3` does it
  # for a slot: cut to the level, with the value being replaced taken out, so
  # re-choosing what is already there is not refused as a duplicate of itself.
  defp granted_history(%Build{} = build, level, feat_id) do
    build
    |> Build.put_granted_choice(level, feat_id, nil)
    |> Build.truncate(level)
  end

  # Two filters, and which of them emptied the list is the whole answer.
  #
  #   * `used` — values this **same feat** already holds. Hidden rather than
  #     refused (решение Дана, CLAUDE.md §6): "you have taken that school"
  #     teaches nothing, the player did it himself.
  #   * `required` — «in the chosen school»: the value must be one the feats in
  #     `same_choice_as` are held with. That is mechanics, and mechanics is shown
  #     with a reason.
  #
  # `values` is never empty here — `values/3` answers `:none` for that, the same
  # as for a domain with no dictionary at all — so the third branch always has a
  # required feat to name.
  defp offer(values, history, feat, repeatable, domain, level, ruleset) do
    used =
      if repeatable.distinct?, do: held(history, ruleset, feat.id, level), else: MapSet.new()

    required = for id <- same_choice_as(feat), do: {id, held(history, ruleset, id, level)}

    offer(values, feat, domain, used, required)
  end

  # The list itself, with both filters handed in. Three routes reach it — a slot
  # pick, a class grant and an item — and they differ **only** in what they put
  # into `used` and `required`, which is the whole reason this is one function:
  # «which weapons may a Weapon Master choose» has one answer, and a second
  # implementation would be the one that drifts.
  #
  # ⚠ `required` is empty on the gear route, so the third branch cannot fire
  # there — `qualified` is then `values`, which `values/3` never returns empty.
  # That is the rule «a declaration is not checked against its own
  # prerequisites» (`Rules.GearFeats`) expressed as an argument, not as a
  # special case inside here.
  #
  # ✅ **И на гировом маршруте это правило теперь стоит на слове владельца, а не
  # на преемственности** (Dan, 25.08.2026, `GAME_CHECKS.md` Z1, `source: user`):
  # «подобные вещи бывают, бывают даже с epic spell focus. Для такого фита
  # с вещи нам не нужно требовать предыдущие фиты на focus и greater focus,
  # как мы обычно делаем». То есть предмет со `Greater`/`Epic spell focus`
  # в школе, где у носителя нет базового, на шарде существует — и объявление
  # обязано его принимать.
  #
  # ⚠ Правило унаследовано из задачи 3.3 и до 3.97 было **ненаблюдаемым**:
  # у фита с вещи не было значения, проверять было нечего. Первое же следствие,
  # которое оно дало на экране, пришлось спрашивать — и ответ подтвердил модель,
  # не сдвинув ни одного числа. Записано именно поэтому: «правило не меняется»
  # и «правило проверено» — разные вещи, и вторая наступила только сейчас.
  #
  # ⚠ Слотовый маршрут этим НЕ затронут и не должен быть: `Epic spell focus`
  # слотом по-прежнему отказан без базовых («как мы обычно делаем» — Dan).
  defp offer(values, feat, domain, used, required) do
    qualified =
      for value <- values,
          Enum.all?(required, fn {_id, choices} -> MapSet.member?(choices, value) end),
          do: value

    case qualified |> Enum.reject(&MapSet.member?(used, &1)) |> Enum.sort() do
      [_ | _] = free -> {:ok, free}
      [] when qualified != [] -> {:empty, [{:choice_exhausted, feat.id, domain}]}
      [] -> {:empty, [{:choice_requires, feat.id, unmet(required, values), domain}]}
    end
  end

  # Which of the required feats to name. The ones held with nothing this feat
  # could use — that is the ordinary case, and the one the player can act on.
  #
  # When every one of them is held with *something* usable and the list is still
  # empty, the fault is in the intersection: no single value is shared by all of
  # them. Nothing is missing on its own, so all of them are named, and the
  # sentence «нужны X и Y на одно значение» is exactly true.
  defp unmet(required, values) do
    case for {id, choices} <- required,
             not Enum.any?(values, &MapSet.member?(choices, &1)),
             do: id do
      [] -> for {id, _choices} <- required, do: id
      missing -> missing
    end
  end

  @doc """
  Why `feat_id` will not be taken **with** `choice` — the value against its
  domain, with no character in the question.

  `[]` in three cases, and they are three different facts:

    * the domain accepts the value;
    * the domain has no dictionary — nothing about the value can be judged, and
      saying so is `gaps/3`'s job rather than a refusal's;
    * `choice` is `nil`. A pick that names nothing is not an *illegal* pick, it
      is one that has not chosen yet. The routes that owe the player a second
      step say `{:requires_choice, …}`; the one that does not is an item, where
      a bare declaration is a legal, compatible state (`Rules.GearFeats`).

  Exposed because `Rules.GearFeats.validate/2` judges a declaration with no
  build at all, and the alternative — its own reading of «which values does this
  feat take» — is exactly the second implementation this module refuses to have.
  """
  @spec choice_reasons(atom(), term(), map()) :: [reason()]
  def choice_reasons(feat_id, choice, ruleset)

  def choice_reasons(_feat_id, nil, _ruleset), do: []

  def choice_reasons(feat_id, choice, ruleset) do
    case Map.fetch(ruleset.feats, feat_id) do
      :error -> [{:unknown_feat, feat_id}]
      {:ok, feat} -> stated_choice_reasons(feat, choice, ruleset)
    end
  end

  defp stated_choice_reasons(feat, choice, ruleset) do
    case repeatable(feat) do
      %{choice: domain} when not is_nil(domain) ->
        case values(feat, domain, ruleset) do
          :none -> []
          {:ok, values} -> invalid_choice(values, feat, choice)
        end

      _no_domain ->
        # Same refusal a value on a parameterless feat gets in a slot and in a
        # grant, and for the same reason: there is no domain to check it against,
        # and letting it through would have it read as a distinguishing mark.
        [{:invalid_choice, feat.id, choice}]
    end
  end

  # The membership test itself, in one place: four callers ask it and a fifth
  # would be a fifth chance to forget the domain's per-feat gates, which live in
  # `values/3` above rather than in the dictionary.
  defp invalid_choice(values, feat, choice) do
    if MapSet.member?(values, choice), do: [], else: [{:invalid_choice, feat.id, choice}]
  end

  # ⚠ `nil` is not a choice. Picks made before the interface recorded choices
  # carry none, and counting them as a held value would have one of them satisfy
  # a requirement about a value nobody wrote down.
  #
  # ⚠ Slots **and** class grants (task 3.26). An epic Weapon Master's second
  # `Weapon of choice` may not name the weapon the class already handed the first
  # one over with — reading slots only would offer it, and «additional weapons of
  # choice» says additional.
  defp held(history, ruleset, feat_id, level) do
    history
    |> Build.feat_choices_permanent(ruleset, feat_id, level)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  @doc """
  Whether the data says this feat may be taken more than once — of either kind.

  `domain/2` answers the narrower question "out of what", and cannot stand in for
  this: a counted repeatable (`Epic toughness`) names no domain, so `nil` there
  means both "takes no parameter" and "does not repeat".

  Only what the data states, exactly like `repeatable/1` inside this module: no
  block means single-take, which is the rule as it stood.
  """
  @spec repeatable?(atom(), map()) :: boolean()
  def repeatable?(feat_id, ruleset) do
    case Map.get(ruleset.feats, feat_id) do
      %{} = feat -> not is_nil(repeatable(feat))
      _unknown -> false
    end
  end

  @doc """
  The domain a feat draws its parameter from, or `nil` when it takes none.
  """
  @spec domain(atom(), map()) :: atom() | nil
  def domain(feat_id, ruleset) do
    case Map.get(ruleset.feats, feat_id) do
      %{repeatable: %{choice: choice}} -> choice
      _none -> nil
    end
  end

  @doc """
  What a build owes the reader about the repeatable feats it has.

  Four things, and all of them are the same kind of honesty the rest of the core
  keeps: the feat's own effect is not in the numbers, where the domain has no
  dictionary the recorded choice was never checked, where the same thing may be
  taken again with no ceiling in the data nobody checked how many times, and
  where the repetition rule itself is somebody's guess it is not a fact.

  ⚠ **Three of the four are slots only (`Build.feats_taken/2`), checked on
  14.08.2026** when `Rules.Attack`'s hook was moved the other way. They are
  questions about *repeating a pick*, and the ceiling on takes was measured to be
  a slots question (`GAME_CHECKS.md` H8, `Build.feat_takes/3`): an item lends a
  feat once and repeats nothing. The declaration's own caveat about the value it
  cannot name is `Rules.GearFeats.gaps/2`.

  ⚠ **The fourth is `effect_gap/2`, and it follows the feat rather than the
  slot** — closed 14.08.2026, having been named here as a sliver first. It is
  not a question about repeating anything: it says «прибавку от этого фита
  в статы не считаем», which is exactly as true of a `Self concealment` off an
  item as of one in a slot. Leaving it slots-only made the silence *worse* for
  the declaration, because a declared feat's effect is the half that **is**
  counted (Dan, 09.08.2026), so the player had every reason to assume this one
  was too.

  ⚠ **A class grant is still not here, and it is worth nothing today — measured,
  not assumed** (14.08.2026). Widening to `Build.feats_owned/3` would fold in the
  feats classes hand over, and across all 23 shard classes exactly **one** of
  those is repeatable — `Weapon of choice`, whose effect *is* counted, so it
  would produce no caveat anyway. `Favored enemy` is not a counter-example: the
  Ranger buys it in a bonus slot, so it is already here by the picked route. The
  widening is therefore neither urgent nor free of consequence later, and it
  stays a separate question.
  """
  @spec gaps(Build.t(), map(), non_neg_integer()) :: [tuple()]
  def gaps(%Build{} = build, ruleset, level) do
    picked = Build.feats_taken(build, level)
    worn = MapSet.difference(GearFeats.held(build.gear, ruleset), picked)

    pick_gaps(picked, ruleset) ++
      declaration_gaps(worn, ruleset) ++
      weapon_proficiency_gaps(build, picked, ruleset, level)
  end

  # Пятое, и оно не про повторяемость, а про требование, которое ядро
  # спрашивает у справочника и не всегда получает ответ (задача 3.99).
  #
  # `Weapon focus` и `Improved critical` требуют владения ВЫБРАННЫМ оружием.
  # Какой фит просит каждое оружие, знает `weapons.json`, и у Сиалы он называет
  # его у 42 записей из 47; у ванили — ни у одной, потому что её собственные
  # категории (simple / martial / exotic) в ruleset не поднимаются. Там, где
  # справочник молчит, требование МОЛЧИТ ТОЖЕ — отказать нечем, — и молчать
  # об этом второй раз нельзя.
  #
  # ⚠ Оговорка по КОНКРЕТНОМУ оружию, а не по фиту: у Сиалы неназванная запись
  # ровно одна (`creature_weapon`), и фраза «владение выбранным оружием
  # не проверяется» была бы там ложной 40 раз из 41. Форма та же самая, что
  # у оружия в руках (`Rules.GearWeapon.gaps/2`), и это не совпадение —
  # утверждение буквально одно и то же: «владение этим оружием не назвал никто».
  #
  # ⚠ И на Сиале эта оговорка ЛЕГАЛЬНОЙ ИГРОЙ больше не достижима (задача 3.108,
  # замер AC6): единственное оружие с непрочитанным владением, которое шард
  # предлагал, — `creature_weapon`, а его вариант фита там закрыт. Механизм при
  # этом жив и обязан жить: у ванили он кусает на 43 записях из 47, и первое же
  # выбираемое оружие вне пяти сиальских групп вернёт оговорку само. Держится
  # тестом `weapons_test.exs` — «у всего предлагаемого владение прочитано».
  #
  # ⚠ Слоты и классовая выдача, без вещей: значение с вещи требование фита
  # не выполняет вовсе (H7), значит и сказать про него нечего.
  defp weapon_proficiency_gaps(build, picked, ruleset, level) do
    for feat_id <- Enum.sort(picked),
        feat = Map.get(ruleset.feats, feat_id),
        is_map(feat),
        asks_weapon_proficiency?(feat),
        weapon <- Build.feat_choices_permanent(build, ruleset, feat_id, level),
        not is_nil(weapon),
        gap <- GearWeapon.caveats_for(ruleset, weapon),
        uniq: true do
      gap
    end
  end

  defp asks_weapon_proficiency?(feat) do
    prereqs = Map.get(feat, :prereqs)

    is_map(prereqs) and
      (Map.get(prereqs, "proficiency_with_chosen_weapon") ||
         Map.get(prereqs, :proficiency_with_chosen_weapon)) == true
  end

  defp pick_gaps(feat_ids, ruleset) do
    for feat_id <- Enum.sort(feat_ids),
        feat = Map.get(ruleset.feats, feat_id),
        is_map(feat),
        repeatable = repeatable(feat),
        not is_nil(repeatable),
        gap <-
          effect_gap(feat_id, ruleset) ++
            domain_gap(feat, repeatable, ruleset) ++
            max_takes_gap(feat_id, repeatable) ++
            unverified_gap(feat_id, repeatable),
        uniq: true do
      gap
    end
  end

  # One of the four, for the feats an item lends. The ids are disjoint from the
  # picked ones (`gaps/3` subtracts), so a feat held both ways is judged as a
  # pick and says its piece once.
  #
  # ⚠ The `repeatable` gate stays, and it is inherited rather than argued for:
  # `effect_gap/2` has only ever been asked about repeatable feats, so widening
  # it here would make a declaration *noisier* than the same feat in a slot —
  # every worn `Divine might` would start claiming an uncounted bonus that a
  # picked one does not. Same scope on both routes is the property this task was
  # for; the scope itself is a separate question.
  defp declaration_gaps(feat_ids, ruleset) do
    for feat_id <- Enum.sort(feat_ids),
        feat = Map.get(ruleset.feats, feat_id),
        is_map(feat),
        not is_nil(repeatable(feat)),
        gap <- effect_gap(feat_id, ruleset),
        uniq: true do
      gap
    end
  end

  # ⚠ The one caveat here that a **number on screen** can contradict. Since task
  # 1.9 the core counts what some feats add — `Epic toughness`'s twenty hit
  # points per take are in `hp` and named in its breakdown — and repeating
  # «прибавку от фита в статы не считаем» beside a term the player can see is
  # worse than saying nothing: it teaches him to distrust the list. So the
  # caveat is owed only while the effect is genuinely missing, and whether it
  # still is comes from the data (`effect_coverage` in the two markup files)
  # rather than from this module knowing which feats got modelled.
  #
  # ⚠ Three askers now, one per markup file, and the caveat goes only when **one
  # of them** says the whole feat is counted. Task 3.1 added the second: since
  # it, a `Great strength` on the build shows `+3` in the strength breakdown,
  # and «прибавку от фита в статы не считаем» beside it would be the same
  # contradiction `Epic toughness` was.
  #
  # ⚠ Task 3.5 part B added the third, and its own doc had been waiting for the
  # day: until then no `applied` attack-bonus record was repeatable, so this
  # function never reached one. `Weapon focus` is both now — repeatable by weapon
  # and counted, when the weapon in hand is the one it names — and the caveat
  # would have argued with a `Weapon focus +1` row in the AB breakdown.
  #
  # ⚠ It comes back on a build where the bonus is genuinely not counted, and by a
  # **different form** that says why: `{:not_modelled, {:attack_bonus_weapon, id}}`
  # («оружие в руках не назвали»). Two shapes of the same missing number would be
  # noise; the precise one is the one that stays.
  #
  # ⚠️ `/2`, а было `/3`: до задачи 3.25 первым аргументом шла карта самого фита —
  # `FeatBonuses.whole_effect_counted?/1` читала поле, которое загрузчик вливал в
  # фит. Теперь все спрашивают разметку по id, и карта здесь не нужна ни одному.
  #
  # ⚠ Задача 3.92 добавила ШЕСТОГО — `Rules.Skills`. До неё он ничего бы не менял
  # (ни одна применяемая запись файла прибавок к навыкам не была повторяемой),
  # а с ней стал обязателен: `Skill focus` и `Epic skill focus` — первые фиты,
  # которые и повторяемы, и посчитаны, и без этой строки «прибавку от фита
  # в статы не считаем» печаталась бы рядом с термом «Skill focus +3» в разборе
  # того же навыка. Ровно тот же случай, что у `Weapon focus` и `Improved spell
  # resistance` ниже.
  #
  # ⚠ Задача 3.45 добавила ПЯТОГО и заодно нашла ЧЕТВЁРТОГО, которого тут не было.
  # `Improved spell resistance` — первый повторяемый фит, чья прибавка посчитана
  # разметкой SR, и без строки ниже билд «Мастер Монах» печатал бы 63 и рядом
  # «прибавку от фита в статы не считаем». А `Rules.SaveBonuses` не спрашивали
  # вовсе, хотя его собственный moduledoc это утверждал («`effect_gap/3` — the
  # only caller that asks this question»): ни одна применённая запись сейвов
  # сегодня не повторяема, поэтому расхождение ничего не стоило и потому
  # не падало. Обе строки добавлены вместе — вторая ничего не меняет ни на одном
  # сегодняшнем билде и перестаёт быть ловушкой на день, когда повторяемая
  # запись у сейвов появится.
  #
  # ⚠ Задача 3.93 добавила ВТОРОЙ вопрос, и он другого рода, чем шесть первых.
  # Те спрашивают «посчитали ли мы прибавку»; этот — «а есть ли вообще число,
  # в которое она падает». Пятнадцать повторяемых фитов из восемнадцати
  # печатали «прибавку в статы не считаем» про урон, ДЦ ЧУЖОГО спасброска,
  # метамагию, сопротивления и маскировку — то есть про механики, которых
  # калькулятор не считает и не собирался (CLAUDE.md §9, решение Dan
  # 10.08.2026: гэп — дырка в нашем ОТВЕТЕ, а не в наших знаниях). Это ровно
  # та ложная неопределённость, которую §6 запрещает с другой стороны: пугать
  # игрока тем, чего он и не ждал, и обесценивать соседние строки, которые
  # ждать стоит.
  #
  # ⚠ Спрашивается тот же самый механизм и тот же самый словарь, что судит
  # факты шарда, — `GapReceivers.ours?/2` и `ruleset.gap_receivers`. Второго
  # механизма для «наш ли это получатель» в проекте нет и быть не должно;
  # метка лежит в `vanilla/feat_effect_receivers.json` и называет МЕХАНИКУ
  # (`damage`), а не видимость, поэтому день, когда ядро начнёт считать урон,
  # вернёт эти оговорки сам.
  #
  # ⚠ Направление ошибки прежнее — в сторону показа. Метки нет — оговорка
  # остаётся; хватает ОДНОГО нашего получателя из скольких угодно; ruleset без
  # словаря (`vanilla`) не фильтрует ничего. Сегодня без метки сознательно
  # оставлены `Arcane defense` и `Favored enemy`: их прибавка падает в наши
  # сейвы и в наши навыки и лишь сужена условием, которого билд не описывает.
  #
  # ⚠ Задача 3.98 вынесла само чтение словаря в `GapReceivers.feat_effect_ours?/2`
  # и НИЧЕГО здесь не поменяла: второй читатель того же словаря — оговорка
  # объявления с вещи (`Rules.GearFeats.gaps/2`), и она отвечала про те же фиты
  # иначе с самого дня 3.93. Приватная копия чтения и была тем, что позволяло
  # разойтись, — на это ушёл не год, а один коммит.
  #
  # 🔴 И ВТОРОЙ ВОПРОС ЭТОЙ ФУНКЦИИ ТУДА НЕ ПОЕХАЛ — `whole_effect_counted?/2`
  # спрашивается только здесь, и это не забывчивость. У двух оговорок он
  # означает ПРОТИВОПОЛОЖНОЕ: здесь «посчитали» гасит фразу «не считаем»,
  # а там посчитанный эффект — единственная причина, по которой неназванное
  # значение вообще чего-то стоит (`Skill focus` +3 некуда положить). Скопируй
  # обе строки — и у объявления погаснут ровно те пять оговорок, которые честны.
  defp effect_gap(feat_id, ruleset) do
    counted? =
      Enum.any?(
        [FeatBonuses, AbilityBonuses, AttackBonuses, SaveBonuses, Skills, SpellResistance],
        & &1.whole_effect_counted?(feat_id, ruleset)
      )

    if counted? or not GapReceivers.feat_effect_ours?(feat_id, ruleset),
      do: [],
      else: [{:not_modelled, {:feat_bonus, feat_id}}]
  end

  # ⚠ The rule itself, not its ceiling. Two of the eight repetition facts on the
  # shard are Дан's own guesses — «не знаю, предполагаю» for
  # `Epic weapon specialization`, a web search for `Resist energy` — and the data
  # says so (`status: "unclear"`). They are applied, because a guess from the
  # highest-ranked source beats leaving a feat single-take that nobody says is
  # single-take; but an applied guess that produces no caveat is exactly the
  # silence CLAUDE.md §9 calls out, so the build carries one.
  defp unverified_gap(feat_id, repeatable) do
    case Map.get(repeatable, :status) do
      "unclear" -> [{:assumed, {:feat_repeatable, feat_id}}]
      _stated_or_absent -> []
    end
  end

  defp domain_gap(_feat, %{choice: nil}, _ruleset), do: []

  defp domain_gap(feat, repeatable, ruleset) do
    case values(feat, repeatable.choice, ruleset) do
      :none -> [{:missing_data, {:choice_domain, repeatable.choice}}]
      {:ok, _values} -> []
    end
  end

  # Only where the same thing may genuinely be taken again — no domain at all, or
  # a domain whose picks need not differ. Where every pick must differ the domain
  # *is* the ceiling and there is nothing unknown to report; saying it anyway
  # would pad the list with a caveat that is not true, and a list people skim is
  # a list that has stopped working.
  defp max_takes_gap(feat_id, repeatable) do
    if repeats_the_same?(repeatable) and is_nil(Map.get(repeatable, :max_takes)),
      do: [{:missing_data, {:feat_max_takes, feat_id}}],
      else: []
  end

  defp repeats_the_same?(%{choice: nil}), do: true
  defp repeats_the_same?(repeatable), do: Map.get(repeatable, :distinct?) == false

  # The values this **feat** may draw from the domain, and there are two kinds of
  # gate because the data makes two kinds of statement.
  #
  #   * **about the value** — «universal is not truly a spell school»
  #     (`fandom:Universal`). True of every feat that chooses a school, so the
  #     gate is named `selectable` and applies to the whole domain.
  #   * **about one feat** — `creature_types.json` marks `ooze` as
  #     `favored_enemy: false`, which is a fact about that feat's list and no
  #     other. A gate named after a feat id serves that feat, and overrides the
  #     domain-wide one, so an exception stays expressible.
  #
  # ⚠ The domain-wide gate is why the per-feat one is not enough on its own. A
  # gate keyed by feat id cannot say "no feat may take this", and a family whose
  # first member carries the gate leaves the rest ungated: `spell_focus` refuses
  # `universal` while `Greater`/`Epic spell focus` would accept it. That is
  # covered today only by `same_choice_as` — the value is absent from the base
  # feat's picks, so it never reaches the derived one's list — which is cover by
  # a **different rule's side effect**, indistinguishable from working right
  # until the day a school feat arrives without one. `feat_choices_test.exs`
  # watches for exactly that day.
  #
  # Both names come out of the data (`Loader.Reading.entry_flags/1` indexes every boolean
  # field a dictionary carries); `@domain_gate` is a schema key like `distinct`
  # or `max_takes`, never the name of a school, a skill or a race.
  @domain_gate :selectable

  defp values(feat, domain, ruleset) do
    case Map.get(Map.get(ruleset, :choice_domains, %{}), domain) do
      %{values: nil} ->
        :none

      nil ->
        :none

      %{values: values, flags: flags} ->
        gated(Map.get(flags, feat.id) || Map.get(flags, @domain_gate) || values)
    end
  end

  # An **empty** list of values is not a list of values, the same rule and for
  # the same reason as `Loader.Reading.resolve_domain/3`'s ("resolving to it would refuse
  # every value in the game rather than admit the list is not there yet"). A gate
  # that lets nothing through is a hole in the data, not a fact about the
  # character, and the build says so through `{:missing_data, {:choice_domain,
  # …}}` instead of telling the player he has used everything up.
  defp gated(values) do
    if Enum.empty?(values), do: :none, else: {:ok, values}
  end

  @doc """
  The reserved flag name a dictionary uses to gate a value for **every** feat.

  Written like any other gate — the entries that *are* selectable carry
  `"selectable": true`, exactly as `creature_types.json` marks its 24 — so a
  domain that does not use it is unaffected.
  """
  @spec domain_gate() :: atom()
  def domain_gate, do: @domain_gate

  # The character as it stood for this decision: cut to the level, and with the
  # slot being filled emptied out, so a pick never counts as its own predecessor.
  defp history(%Build{} = build, pick, level) do
    case Map.get(pick, :slot) do
      nil ->
        Build.truncate(build, level)

      slot ->
        at_level = build.feats |> Map.get(level, %{}) |> Map.delete(slot)
        emptied = %Build{build | feats: Map.put(build.feats, level, at_level)}

        Build.truncate(emptied, level)
    end
  end

  defp level(build, pick) do
    case Map.get(pick, :at) do
      level when is_integer(level) and level >= 0 -> level
      _absent -> Build.character_level(build)
    end
  end

  # Same as `Prereqs`: ids in a requirement block arrive as strings from a feat's
  # raw JSON and as atoms from a class. Compiled-in data, never user input.
  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_atom(value)
end
