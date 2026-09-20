defmodule BuildCalculator.Rules.GearWeapon do
  @moduledoc """
  The weapon in the character's hands — one weapon per hand, one number each
  (task 3.5 part B; the second hand since task 3.132).

  Dan, 09.08.2026: «в вещах можно будет выбрать оружие, допустим „скимитар“
  с усилением атаки +5. И будем показывать в деталях об АБ значение с конкретным
  оружием». So this is deliberately **not** a matrix of "AB per weapon kind": a
  hand holds one weapon, and its attack bonus is the attack bonus with it.

  ## Two hands, and the second is not a repetition of the first

  Dan, 28.08.2026: «многие билды берут 2 оружия вместо щита или двуручки … Можем
  ввести вторую руку? с возможностью выбрать оружие вместо щита и его attack
  bonus». Every function here takes a `hand` (`:main` / `:off`, out of
  `Rules.Gear.hands/0`), and the answers genuinely differ:

    * the off hand refuses a weapon that **takes both hands**
      (`{:two_handed_in_off_hand, id}`), and refuses everything while the main
      hand holds such a weapon (`{:two_handed_weapon, id}`);
    * the off hand refuses a **ranged** weapon whatever its grip
      (`{:ranged_in_off_hand, id}`), and refuses every weapon while the main
      hand holds one (`{:ranged_in_main_hand, id}`) — task 3.142;
    * the off hand carries its **own** number off its own item.

  ⚠ The two pairs look alike and are not the same rule. Grip is a function of
  two sizes and takes the whole slot — a shield included; the ranged ban is
  keyed by a property of the weapon and keeps out a **weapon** only, which is
  why an archer with a sling still gets his shield (`Rules.Wield`, and Dan's
  measurement `GAME_CHECKS.md` AI2). Four ranged weapons are two-handed as well,
  and there the grip refusal is the one printed: it is the older statement and
  it is true of the whole slot.

  ⚠ A shield and a second weapon are mutually exclusive, and the exclusion is
  decided **in the weapon's favour** — exactly as it already was for a two-handed
  weapon since task 3.43. The shield gets the refusal, with a sentence of its
  own (`Rules.Worn`, `{:off_hand_weapon, id}`), because «занята двуручным
  оружием» and «занята вторым оружием» send the player to change different
  things. Asking it the other way round as well would close a literal loop:
  `Worn.worn/2` already asks `held/3`.

  Three things follow, and each is a rule rather than a detail.

  ## 1. The list is filtered by the proficiency feats the build has

  Dan, 10.08.2026: «можно в вещах не предлагать выбрать оружие, если нет фитов
  „владение …“. Если в билде есть владение клинковым, то мы все мечи и кинжалы
  … добавляем … Тогда будет легитимно — взял фит владения, значит можешь такое
  оружие дать персонажу».

  That is what closes the false legality task 3.5's narrowing was ready to
  accept: «машу скимитаром без владения клинковым» is now impossible, because
  the scimitar is not offered. Which feat each weapon asks for is data
  (`ruleset.weapons[id].proficiency`, out of `weapons.json`'s
  `siala_proficiency_group` and its group table) — no weapon and no feat is named
  in this module.

  ⚠ **Three answers, not two**, and the third is the one worth spelling out:

    * `:none_needed` — the magic staff. It needs no proficiency at all (measured
      in game: «некоторые маги могут ничего не брать, бегать с посохом, он не
      требует владения»), so it passes the filter **always**. Without that, a
      wizard with no proficiency feat would face an empty list while running
      around with a staff in game;
    * `{:feat, id}` — the ordinary case: the weapon is offered once the build
      owns that feat, refused with `{:requires_feat, id}` until then;
    * `:unread` — nobody wrote the requirement down. Siala names the **club** in
      none of its five proficiency categories, and that is *not* the same
      statement as "needs no proficiency". Such a weapon **is** offered, and the
      build says out loud that the requirement was never read
      (`{:missing_data, {:weapon_proficiency, id}}`).

  The third answer is a choice between two ways of being wrong, and it is made
  the way this project makes it everywhere else. Refusing the club would invent
  an illegality nobody stated; offering it silently would assert a legality
  nobody stated either. Offering it **with the caveat printed** asserts neither —
  and it matches CLAUDE.md §6's own rule, «недоступное не прячем, а показываем
  с причиной», at the one point where the honest word is not "недоступно" but
  "неизвестно". ⚠ It does *not* re-open the false legality the filter closed:
  the scimitar's group is known, so it stays hidden without the feat.

  ## 2. A weapon that lost its footing is marked, never quietly dropped

  Take the proficiency feat away and the weapon stops counting — but it stays in
  the struct, and `illegal/2` names it. Exactly the contract `Rules.GearFeats`
  keeps for a declared feat the shard has since switched off, and the same shape
  as the point-buy reset (task 1.7): silently confiscated reads as a bug, named
  reads as a rule.

  ## 3. One number, and the data says how many there are

  `gear.weapon_attack` is what the player typed off their own item. It goes
  **inside** the ceiling (`stat_caps.attack_bonus.applies_to_sources.
  gear_weapon`, `inside_cap: true`), which is what makes that ceiling reachable
  at all: the only other source under it is the shard's racial bonus at +9 out
  of +20.

  ⚠ **One number since task 3.52, two before it**, and the difference is worth
  knowing rather than forgetting. A shard item carries an *enhancement* bonus
  too — Dan named it beside the attack bonus while listing what fills the +20
  (case J1) — and the two differed in exactly one respect: an enhancement bonus
  also gives damage. Damage is computed nowhere, so the player typed two numbers
  and saw the difference nowhere either (Dan, 19.08.2026: «урон мы нигде
  не выводим и не считаем, так что надо нам от enchantment bonus просто
  отказаться»).

  ⚠ Merging them was safe for one reason, and it is not "they happen to be equal
  today": the **side of the cap is common to them always** (Dan, 19.08.2026:
  «по механике nwn attack bonus и enchantment bonus должны быть равны в плане
  капа»). Should the ceiling ever put weapon numbers outside itself, both leave
  together — which is why an old link's two numbers may be added into one
  without a scenario in which that lies.

  ⚠ And what left with it: `{:assumed, :weapon_bonuses_stack}`, the caveat that
  no page states whether the two stack. It is gone **because the question stopped
  existing**, not because it was crossed out — with one number there is nothing
  to stack. How many numbers there are is still the data's word
  (`ruleset.gear.weapon_bonus_kinds`), never a count in this module.

  ## What this module is not

  It is not the armoury. There are no items here: one weapon id out of the
  dictionary, plus the number the player reads off their own character sheet —
  the same arrangement `Rules.Gear`'s abilities, AC, saves and skills have always
  had. Damage, critical range, the shard's four unlock steps per proficiency and
  the level at which the shard lets a weapon be equipped are all deliberately
  absent (Dan: «Урон, на каком левеле … для конструктора не важно, мы это не
  показываем»).
  """

  alias BuildCalculator.Rules.{Build, Caps, Gear, Wield}

  @typedoc "Why a weapon may not be the one in the character's hands."
  @type reason ::
          {:unknown_weapon, atom()}
          | {:not_wieldable, atom()}
          | Wield.reason()
          | {:requires_feat, atom()}
          | {:two_handed_in_off_hand, atom()}
          | {:two_handed_weapon, atom()}
          | {:ranged_in_off_hand, atom()}
          | {:ranged_in_main_hand, atom()}

  @typedoc """
  One weapon as the interface offers it.

    * `reason` — `nil` when it may be chosen, the refusal otherwise. Refused
      weapons are **offered anyway**, with the reason shown (CLAUDE.md §6);
    * `caveats` — what is true about the weapon and unread. `[]` for most.
  """
  @type candidate :: %{
          id: atom(),
          name: String.t() | nil,
          reason: reason() | nil,
          caveats: [tuple()]
        }

  @typedoc """
  What the weapon in hand adds to the attack roll, one term per number typed.

  `kind` is the item property (`:attack`) as the ruleset names it, so nothing
  here decides how many numbers a weapon carries — the list had two kinds until
  task 3.52 and may have two again.
  """
  @type term_entry :: %{
          kind: atom(),
          bonus: integer(),
          under_cap?: boolean()
        }

  # Which mechanism of `Rules.compute/2` the item's own numbers belong to, for the
  # ceiling's own scope table. ⚠ Deliberately **not** `:gear`: under that name
  # rides the ability modifier an item raised, and that one is *outside* the +20
  # while these are inside it (`Rules.Caps`, task 3.22 and J1).
  @cap_source :gear_weapon

  @doc """
  The mechanism name the attack ceiling classifies these numbers under.

  Exposed so the interface can ask `Rules.Caps` which side of the +20 they fall
  on without naming the source itself — the same rule the rest of the breakdown
  follows: the side is read from the data, never decided in a caller.
  """
  @spec cap_source() :: atom()
  def cap_source, do: @cap_source

  @doc """
  Whether `weapon_id` may be the weapon in this build's hands, and if not, why.

  Takes the build, unlike `Rules.GearFeats.validate/2`: the answer depends on the
  proficiency feats the character owns, and that is the whole point of the filter.

  ⚠ Every reason is a refusal about the **weapon**, never about the numbers. A
  hand-edited link naming a creature's attack form is refused
  (`{:not_wieldable, id}`) — there is no item there to read a bonus off.
  """
  @spec validate(Build.t(), atom(), map(), atom()) :: :ok | {:error, [reason()]}
  def validate(%Build{} = build, weapon_id, ruleset, hand \\ :main)
      when is_atom(weapon_id) and is_atom(hand) do
    case refusal(build, weapon_id, ruleset, hand) do
      nil -> :ok
      reason -> {:error, [reason]}
    end
  end

  @doc """
  The weapon that actually counts — `nil` when there is none or the one recorded
  is refused.

  Same contract as `Rules.GearFeats.held/2`: the declaration stays in the struct,
  because dropping it would lose the player's statement, and `illegal/2` is what
  makes the discrepancy visible.
  """
  @spec held(Build.t(), map(), atom()) :: atom() | nil
  def held(%Build{} = build, ruleset, hand \\ :main) when is_atom(hand) do
    case Gear.weapon(build.gear, hand) do
      nil -> nil
      weapon_id -> if refusal(build, weapon_id, ruleset, hand) == nil, do: weapon_id, else: nil
    end
  end

  @doc """
  Both hands at once, as `[{hand, weapon_id}]` in `Rules.Gear.hands/0`'s order —
  only the hands holding something that counts.

  What the shard's weapon system asks for: «Используя два разных оружия персонаж
  получает два разных бонуса» (`Система оружия`, revid 20527). A caller wanting
  one hand asks `held/3`; a caller asking about the character as a whole asks
  this, and cannot forget the second hand by writing `:main` out of habit.
  """
  @spec held_all(Build.t(), map()) :: [{atom(), atom()}]
  def held_all(%Build{} = build, ruleset) do
    for hand <- Gear.hands(), weapon = held(build, ruleset, hand), do: {hand, weapon}
  end

  @doc """
  The recorded weapon this build may not hold, as `[{weapon_id, reason}]`.

  A list of at most one entry, because a build holds at most one weapon — the
  shape is `Rules.illegal_gear_feats/2`'s so the interface can print both the
  same way, and so a second hand ever gaining a weapon does not change the
  contract.
  """
  @spec illegal(Build.t(), map()) :: [{atom(), reason()}]
  def illegal(%Build{} = build, ruleset) do
    for hand <- Gear.hands(),
        weapon_id = Gear.weapon(build.gear, hand),
        reason = refusal(build, weapon_id, ruleset, hand),
        do: {weapon_id, reason}
  end

  @doc """
  Every weapon the interface may offer, in the dictionary's own order by name.

  ⚠ **Refused weapons are in the list, with their reason** — CLAUDE.md §6, so the
  block teaches the shard's rules instead of silently shortening. What is *not*
  in the list at all is what cannot be an item: a creature's attack form has no
  bonus to type and no hand to be held in.
  """
  @spec candidates(Build.t(), map(), atom()) :: [candidate()]
  def candidates(%Build{} = build, ruleset, hand \\ :main) do
    for {id, weapon} <- Enum.sort_by(weapons(ruleset), fn {id, w} -> {w.name || "", id} end),
        weapon.wieldable?,
        # Отсутствующее на шарде не предлагается вовсе — в отличие от того,
        # что предложить можно, но нельзя взять: там причина показывается.
        weapon.on_shard? do
      %{
        id: id,
        name: weapon.name,
        reason: refusal(build, id, ruleset, hand),
        caveats: caveats(weapon)
      }
    end
  end

  @doc """
  What the weapon in hand adds to the attack roll, one term per number the player
  typed. Zero numbers are left out, the same rule every other term list follows.

  A list, not a number, because how many numbers an item carries is the data's
  word (`gear.weapon_bonus_kinds`) rather than this module's — one today, two
  until task 3.52.

  **Raw, before the ceiling** — `under_cap?` says which side of it each term
  falls on, and `Rules.compute/2` does the one clip. The term answers `true`
  today, out of the data; the field is per term all the same, because a ceiling's
  scope has been rewritten three times in this project and never in code.
  """
  @spec attack_terms(Build.t(), map(), atom()) :: [term_entry()]
  def attack_terms(%Build{} = build, ruleset, hand \\ :main) when is_atom(hand) do
    case held(build, ruleset, hand) do
      nil ->
        []

      _weapon_id ->
        under_cap? = Caps.covers_source?(ruleset, :attack_bonus, @cap_source)

        for {kind, bonus} <- typed_bonuses(build, ruleset, hand),
            bonus != 0,
            do: %{kind: kind, bonus: bonus, under_cap?: under_cap?}
    end
  end

  @doc """
  The same, summed — what the weapon is worth to the attack roll before the
  ceiling. `0` with no weapon in hand, which is the honest default: nothing in
  hand adds nothing.
  """
  @spec attack_bonus(Build.t(), map(), atom()) :: integer()
  def attack_bonus(%Build{} = build, ruleset, hand \\ :main) do
    build |> attack_terms(ruleset, hand) |> Enum.reduce(0, &(&1.bonus + &2))
  end

  @doc """
  What this build owes the reader about the weapon it chose.

  Two things, and both are about a statement somebody did not make:

    * the proficiency group is **ours**, not read off a page (Dan: «пока
      допущение с гэпом, точный маппинг в вопросы ко мне сохрани, я потом
      уточню»). No shipped ruleset carries one today, and the shape is kept
      because the shard may add a weapon its own table does not list;
    * the requirement was never written down at all — the club, and every weapon
      on a ruleset whose proficiency feats do not exist.

  ⚠ There used to be a third, `{:assumed, :weapon_bonuses_stack}`: the item's two
  numbers were added and no page said they stack. Task 3.52 left the item one
  number, so the question is gone rather than answered.

  ⚠ Nothing here is reported for a build with no weapon, and nothing is reported
  about a weapon whose group is `verified`: a caveat that stands on every build
  stands for nothing.
  """
  @spec gaps(Build.t(), map()) :: [tuple()]
  def gaps(%Build{} = build, ruleset) do
    for {_hand, weapon} <- held_all(build, ruleset),
        gap <- proficiency_gaps(weapon, ruleset),
        uniq: true,
        do: gap
  end

  @doc """
  Какое владение требует это оружие — `{:feat, id}`, `:none_needed`, `:unread`
  или `:unknown_weapon` у id, которого в справочнике нет.

  Чистое чтение справочника, без единого имени оружия и фита: какая группа
  какой фит просит, знает `weapons.json` (`_siala_proficiency.groups[].siala_feat`),
  а загрузчик уже свёл это в поле записи.

  🔴 Публичное ради ВТОРОГО читателя, и у него другой вопрос
  (`Rules.Prereqs`, требование «proficiency with the chosen weapon» у
  `Weapon focus` и `Improved critical`). Общего у двух вопросов ровно это
  чтение; **ответ у них разный и обязан оставаться разным**:

    * «взять оружие в руки» — это ЭФФЕКТ, и владение, объявленное с вещи,
      его открывает (`Build.feats_owned/3`, ниже в этом модуле);
    * «взять фит» — это ПРЕРЕКВИЗИТ ФИТА, и фит с вещи его не выполняет
      (замер Dan 14.08.2026, H7). Там читается `Build.feats_permanent/3`.

  Поэтому наружу отдаётся требование, а не вердикт: свести их в одну функцию
  значило бы дать одному из двух вопросов чужой ответ.
  """
  @spec proficiency(map(), atom()) :: {:feat, atom()} | :none_needed | :unread | :unknown_weapon
  def proficiency(ruleset, weapon_id) when is_atom(weapon_id) do
    case definition(ruleset, weapon_id) do
      %{proficiency: proficiency} -> proficiency
      _absent -> :unknown_weapon
    end
  end

  @doc """
  Оговорка про владение этим оружием — `[]`, если справочник его называет.

  Та же запись и та же форма, что у оружия в руках (`gaps/2`), только по id:
  билд, взявший `Weapon focus` с оружием, чьё владение не назвал никто, обязан
  сказать об этом ровно так же, как билд, это оружие держащий.
  """
  @spec caveats_for(map(), atom()) :: [tuple()]
  def caveats_for(ruleset, weapon_id) when is_atom(weapon_id) do
    proficiency_gaps(weapon_id, ruleset)
  end

  # ------------------------------------------------------------------ private --

  defp weapons(ruleset), do: Map.get(ruleset, :weapons) || %{}

  defp definition(ruleset, weapon_id), do: ruleset |> weapons() |> Map.get(weapon_id)

  # `nil` when the weapon may be held. One reason at a time on purpose: the four
  # are not independent statements to collect, they are stages — an id that is not
  # a weapon has no wieldability, something that is not an item has no
  # proficiency, and a weapon too large for the character to hold at all has no
  # proficiency question worth asking either.
  #
  # ⚠ Размер стоит ПЕРЕД владением намеренно (задача 3.43): фитом он не
  # лечится. «Нужен фит владения клинковым» у Карлика с великим мечом было бы
  # обещанием, которого мы не можем сдержать, — оружие не станет ему по руке
  # ни с каким фитом.
  defp refusal(build, weapon_id, ruleset, hand) do
    case definition(ruleset, weapon_id) do
      nil ->
        {:unknown_weapon, weapon_id}

      # ⚠ Раньше `wieldable?`, и причина у отказа СВОЯ, потому что печатается
      # игроку: «не предмет игрока» и «на шарде такого нет» — разные фразы,
      # и вторая не должна маскироваться под первую.
      %{on_shard?: false} ->
        {:not_on_shard, weapon_id}

      %{wieldable?: false} ->
        {:not_wieldable, weapon_id}

      %{proficiency: proficiency} ->
        Wield.refusal(build, weapon_id, ruleset) ||
          hand_refusal(build, weapon_id, ruleset, hand) ||
          proficiency_refusal(build, proficiency, ruleset)
    end
  end

  # Отказы, которые есть только у ВТОРОЙ руки (задачи 3.132 и 3.142). Первые два
  # про хват, а не про сам предмет:
  #
  #   * двуручным оружием вторую руку не занять — «a two-handed weapon is a
  #     weapon whose weapon size is one category larger than its wielder», и обе
  #     руки у него заняты одним предметом;
  #   * главная рука держит двуручное — тогда второй руки нет вовсе. Форма
  #     та же, что у щита (`Rules.Worn`), потому что факт тот же: «Creatures may
  #     not simultaneously use a shield and a two-handed weapon».
  #
  # А вторые два — про СВОЙСТВО оружия, и они не следуют из хвата: праща
  # одноручная, вторая рука у неё по хвату свободна, а игра туда ничего
  # не кладёт («No ranged weapon may be wielded in the off-hand slot, nor can
  # any weapon be wielded in the off-hand when a ranged weapon is in the main
  # hand», `fandom:Ranged weapon`; замер Dan 30.08.2026, `GAME_CHECKS.md` AI2).
  #
  # ⚠ Щит здесь НЕ спрашивается, и это не пропуск: взаимное исключение решено
  # в ту же сторону, в какую оно решено у двуручного оружия с задачи 3.43 —
  # оружие в руке побеждает, а щит получает свой отказ у себя
  # (`Rules.Worn.refusals/4`, форма `{:off_hand_weapon, id}`). Спрашивать друг
  # у друга обе стороны нельзя буквально: `Worn.worn/2` уже спрашивает
  # `GearWeapon.held/3`, и вторая половина замкнула бы кольцо.
  defp hand_refusal(_build, _weapon_id, _ruleset, :main), do: nil

  defp hand_refusal(build, weapon_id, ruleset, :off) do
    cond do
      Wield.both_hands?(build, weapon_id, ruleset) -> {:two_handed_in_off_hand, weapon_id}
      Wield.barred_from_off_hand?(weapon_id, ruleset) -> {:ranged_in_off_hand, weapon_id}
      true -> main_hand_refusal(build, ruleset)
    end
  end

  # ⚠ Хват спрашивается ПЕРВЫМ, и это не порядок написания: четыре из восьми
  # дальнобойных двуручны, то есть обе причины у них верны разом. Печатается
  # хват — утверждение более старое и более широкое (оно про весь слот, а не
  # про оружие в нём), и до задачи 3.142 ровно оно эти четыре и отбивало.
  defp main_hand_refusal(build, ruleset) do
    case held(build, ruleset, :main) do
      nil ->
        nil

      weapon ->
        cond do
          Wield.both_hands?(build, weapon, ruleset) -> {:two_handed_weapon, weapon}
          Wield.bars_from_off_hand?(weapon, ruleset, :weapon) -> {:ranged_in_main_hand, weapon}
          true -> nil
        end
    end
  end

  defp proficiency_refusal(_build, :none_needed, _ruleset), do: nil

  # Требование, которого никто не написал, отказом НЕ является — оно является
  # оговоркой (см. moduledoc, третий ответ).
  defp proficiency_refusal(_build, :unread, _ruleset), do: nil

  defp proficiency_refusal(build, {:feat, feat_id}, ruleset) do
    # Владение, а не взятие слотом: фит есть фит, как бы он ни пришёл, — и с вещи
    # тоже (`Rules.GearFeats`). Если игрок объявил владение предметом, оружие ему
    # доступно ровно пока предмет надет, и это то же чтение, по которому
    # объявленный `Toughness` даёт HP.
    owned = Build.feats_owned(build, ruleset, Build.character_level(build))

    if MapSet.member?(owned, feat_id), do: nil, else: {:requires_feat, feat_id}
  end

  defp caveats(%{proficiency: :unread, id: id}), do: [{:missing_data, {:weapon_proficiency, id}}]

  defp caveats(%{proficiency_assumed?: true, id: id, proficiency_group: group}),
    do: [{:assumed, {:weapon_proficiency_group, id, group}}]

  defp caveats(_weapon), do: []

  defp proficiency_gaps(nil, _ruleset), do: []

  defp proficiency_gaps(weapon_id, ruleset) do
    case definition(ruleset, weapon_id) do
      nil -> []
      weapon -> caveats(weapon)
    end
  end

  # Числа предмета в том порядке, в котором их объявляет ruleset
  # (`gear.weapon_bonus_kinds`), и ровно те, что он объявляет: перечислять их
  # здесь значило бы держать вторую копию списка полей.
  #
  # ⚠ Вид, у которого нет поля в `Rules.Gear`, не «считается нулём» — до этого
  # места он не доходит: загрузчик роняет сборку (`Gear.weapon_bonus_field/1`
  # возвращает `nil`, и он на это падает). Иначе объявленное в данных число молча
  # не считалось бы — та самая ошибка, от которой заведена вся разметка.
  defp typed_bonuses(%Build{gear: %Gear{} = gear}, ruleset, hand) do
    for kind <- Map.get(ruleset.gear, :weapon_bonus_kinds) || [],
        do: {kind, Gear.weapon_bonus(gear, kind, hand)}
  end
end
