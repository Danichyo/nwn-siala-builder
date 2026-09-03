defmodule BuildCalculator.Data.Loader.Character do
  @moduledoc """
  Числа, принадлежащие персонажу целиком, а не классу, расе или фиту: потолки
  статов, формула характеристики броска атаки, эпические прогрессии, потолки
  рангов навыков, пороги престижа, поинт-бай, врождённая прибавка HP («Дух
  Сиалы») и то, считается ли надетый интеллект при выдаче скилл-поинтов.

  Все они читаются из `overrides.json` и `epic.json` одинаковым приёмом — запись
  со `status: "verified"` применяется, любая другая оставляет правило на умолчании.
  """

  alias BuildCalculator.Data.Loader.Bonuses
  alias BuildCalculator.Data.Loader.Reading

  import BuildCalculator.Data.Loader.Reading

  @abilities Reading.abilities()

  # Attacks per round by base attack bonus.
  # source: fandom "Attacks per round" (priv/wiki_cache/fandom/Attacks per round.wikitext),
  # the BAB 0..20 column of the centertable. Kept here, in the data layer, only as a
  # fallback: as soon as `epic.json` grows `attacks_per_round.table`, that wins.
  # Recorded in `gaps` as {:assumed, :attacks_per_round_table} while the fallback is used.
  @apr_fallback %{
    0 => 1,
    1 => 1,
    2 => 1,
    3 => 1,
    4 => 1,
    5 => 1,
    6 => 2,
    7 => 2,
    8 => 2,
    9 => 2,
    10 => 2,
    11 => 3,
    12 => 3,
    13 => 3,
    14 => 3,
    15 => 3,
    16 => 4,
    17 => 4,
    18 => 4,
    19 => 4,
    20 => 4
  }

  # -------------------------------------------------------------- stat caps --

  # Siala declares no ceilings of its own; it *references* the vanilla NWN ones
  # ("Бонус входит в лимита атаки +20"). They are transcribed machine-readably in
  # `siala_41/overrides.json` because without them the calculator overstates
  # attack and skills for exactly the builds it gets opened for — the ones pushed
  # to the cap.
  #
  # Only `verified` entries become rules; anything else stays a gap instead of
  # quietly becoming a number. `max_skill_value` crossed that line on 03.08.2026
  # (confirmed by the player) — note that it is carried without anything clipping
  # against it yet, because nothing the calculator computes reaches 127 before
  # the armoury. Carried ≠ biting; see `Rules.Caps`.
  #
  # ⚠ One list, read in both places. `@stat_cap_keys` names which ceilings exist,
  # and the gap for a missing one is derived from the same list rather than
  # written out a second time — a ceiling used to be listed here and its gap
  # spelled out separately, which is the shape that produced bug 1.2 (two
  # hand-written lists of keys that drifted apart).
  @stat_cap_keys ~w(attack_bonus saving_throw_bonus skill_bonus max_skill_value dodge_ac)

  # «Читается в обоих местах» — это по-прежнему один список: второе место
  # (`Gaps`) с задачи 3.46 живёт в соседнем модуле и берёт его отсюда функцией.
  @doc "Какие потолки статов бывают — тот же список, что читает `stat_caps/1`."
  def stat_cap_keys, do: @stat_cap_keys

  def stat_caps(ov) do
    for key <- @stat_cap_keys,
        entry = dig(ov, ["stat_caps", key]),
        entry["status"] == "verified",
        is_integer(entry["value"]),
        into: %{} do
      {atom(key), entry["value"]}
    end
  end

  # Which **sources** of a bonus a ceiling covers — `applies_to_sources` beside
  # the number (09.08.2026, Dan: «Фиты не входят в кап атаки +20»).
  #
  # ⚠ The reason this exists at all is that "applies to bonuses" was read as
  # "applies to every bonus". Task 1.12b put the build's own feats under the
  # attack ceiling **by analogy** with the saves, where a class ability under the
  # +20 is quoted word for word (`fandom:Uncanny dodge`); for attack no such
  # quote exists, and the player says the analogy is wrong. So a ceiling now
  # states its scope per source instead of the core assuming one.
  #
  # ⚠ **And this level is no longer where a markup record's side is decided**
  # (09.08.2026, second correction of the same rule in one day). Dan: «Divine
  # grace не входит в кап +20, а Sacred Defence входит» — two class abilities,
  # both written in the shape of a feat, opposite answers. So a record states its
  # own side (`cap_side!/4`) and **this** block is only about the sources that
  # have no record at all: `gear`, `racial_bonus`, `skill_rule`. Naming a kind
  # that markup records own raises (`@cap_record_kinds` below) — a block of data
  # that looks live and is not is what this correction had to remove.
  #
  # `%{stat => %{source_kind => %{inside?: boolean, assumed?: boolean}}}`.
  # `assumed?` is what turns into `{:assumed, {:cap_covers_source, stat, kind}}` on
  # a build that carries such a bonus: a classification nobody can cite is applied
  # anyway — there is no neutral answer to "inside or outside" — but it says so.
  def stat_cap_sources(ov) do
    for key <- @stat_cap_keys,
        entry = dig(ov, ["stat_caps", key]),
        sources = entry["applies_to_sources"],
        is_map(sources),
        into: %{} do
      {atom(key), cap_source_scope!(key, sources)}
    end
  end

  # The vocabulary a ceiling may talk about here, and it is exactly the three
  # **mechanisms** of `Rules.compute/2` that have no record of their own: the
  # bonus gear adds to the governing ability (`gear`), the shard's racial bonus
  # (`racial_bonus`, `Rules.RacialBonus`) and a skill rule
  # (`skill_rule` — today Spellcraft's +1 per 5 ranks to every save).
  #
  # ⚠ `@cap_record_kinds` — the source fields of the markup files — are rejected
  # **by name**, and that is the whole lesson of 09.08.2026 in one guard: the side
  # of a ceiling for `Epic prowess` used to live here, under `feat`, and a kind
  # cannot tell `Divine grace` from `Sacred defense`. Leaving the key allowed but
  # unread would keep a statement that looks like a rule and moves no number,
  # which is worse than either answer.
  # ⚠ `gear_weapon` — отдельный механизм, а не расширение `gear`, и это не
  # аккуратность: у `gear` предмет разговора — прибавка МОДИФИКАТОРА
  # характеристики от введённых вещей, и она ВНЕ капа атаки, а attack/enchantment
  # bonus самого оружия — ПОД ним (Dan, кейс J1). Один источник не может отдать
  # двум правилам разные стороны, и запись `gear` в overrides.json это сама и
  # предсказала: «Они появятся с армори … и лягут СВОИМ полем с inside_cap: true».
  # ⚠ `weapon_bonus` — третий механизм оружия и снова НЕ расширение соседей
  # (задача 3.35). `gear_weapon` — числа, вписанные игроком с предмета,
  # `weapon_bonus` — прибавка, которую шард даёт за ТИП оружия в руках; у капа
  # атаки они стоят по разные стороны, и обе стороны названы одним замером Q5.
  @cap_source_kinds ~w(gear gear_weapon racial_bonus skill_rule weapon_bonus)
  @cap_record_kinds Enum.uniq(Bonuses.save_bonus_sources() ++ Bonuses.attack_bonus_sources())
  @cap_source_statuses ~w(verified assumed)

  defp cap_source_scope!(cap_key, sources) do
    for {name, entry} <- sources, not String.starts_with?(name, "_"), into: %{} do
      cond do
        name in @cap_record_kinds ->
          raise "overrides.json: stat_caps.#{cap_key}.applies_to_sources names #{inspect(name)}, " <>
                  "and that side belongs to each record of the bonus markup (its `cap` key), " <>
                  "not to the kind — «Divine grace не входит в кап +20, а Sacred Defence входит»"

        name not in @cap_source_kinds ->
          raise "overrides.json: stat_caps.#{cap_key}.applies_to_sources names the source " <>
                  "#{inspect(name)}, which the core does not know"

        not is_boolean(entry["inside_cap"]) ->
          raise "overrides.json: stat_caps.#{cap_key}.applies_to_sources.#{name} states no " <>
                  "boolean inside_cap — whether the ceiling covers it has no neutral answer"

        entry["status"] not in @cap_source_statuses ->
          raise "overrides.json: stat_caps.#{cap_key}.applies_to_sources.#{name} is " <>
                  "#{inspect(entry["status"])}; only #{inspect(@cap_source_statuses)} become a rule"

        true ->
          {atom(name), %{inside?: entry["inside_cap"], assumed?: entry["status"] == "assumed"}}
      end
    end
  end

  # Which side of its stat's ceiling **one record** of the bonus markup falls on
  # (`feat_save_bonuses.json`, `feat_attack_bonuses.json` → `bonuses[].cap`).
  #
  # ⚠ The same three keys `cap_source_scope!/2` reads a source kind with —
  # `inside_cap`, `status`, `source` — and deliberately the same, because it is the
  # same question asked at a finer grain. What changed on 09.08.2026 is only *who
  # answers*: a kind could not, because `Divine grace` and `Sacred defense` are
  # both class abilities written in the shape of a feat and Dan put one outside the
  # +20 and one inside.
  #
  # **Required on `applied`, forbidden on every other verdict.** Required, because
  # a counted bonus with no stated side would leave the core to pick one, which is
  # the silent reasonable default CLAUDE.md §3 forbids — and because promoting a
  # `not_modelled` record to `applied` now fails the build until somebody states
  # it. Forbidden elsewhere, because the side of an uncounted bonus decides
  # nothing and an unverifiable claim would only accumulate.
  #
  # Returns `%{inside?:, assumed?:}` or `nil`. `assumed?` becomes
  # `{:assumed, {:cap_covers_entry, stat, id}}` on a build that carries the bonus.
  def cap_side!(file, name, entry, verdict) do
    case {entry["cap"], verdict} do
      {nil, :applied} ->
        raise "#{file}: #{name} is `applied` but does not state which side of the stat's " <>
                "ceiling it falls on (`cap`), and there is no neutral answer to that"

      {%{} = cap, :applied} ->
        cond do
          not is_boolean(cap["inside_cap"]) ->
            raise "#{file}: #{name} states no boolean cap.inside_cap"

          cap["status"] not in @cap_source_statuses ->
            raise "#{file}: #{name} states cap.status #{inspect(cap["status"])}; only " <>
                    "#{inspect(@cap_source_statuses)} become a rule"

          true ->
            %{inside?: cap["inside_cap"], assumed?: cap["status"] == "assumed"}
        end

      {nil, _other_verdict} ->
        nil

      {_present, other_verdict} ->
        raise "#{file}: #{name} is `#{other_verdict}` and states a `cap` side; the side of a " <>
                "bonus nobody counts decides nothing, so it is not recorded"
    end
  end

  # Who accounts for this record's fact instead of it — `bonuses[].owned_by`,
  # **required** on `counted_elsewhere` and forbidden on every other verdict.
  #
  # A **string**, and deliberately not an atom: the value names either a record of
  # the same file (`weapon_master` — «два фита Мастера оружия → колонка его
  # класса»), or a mechanism of the core (`attack_ability`, `Rules.Progression`,
  # `Rules.RacialBonus`), or a file and key of the data
  # (`vanilla/races.json → skill_bonuses`), or a task (`1.12b`). Only the first
  # kind resolves to anything, and `Rules.Bonuses` resolves it by comparing with
  # the ids of the file's own `applied` records; turning prose into atoms to do
  # that would buy nothing and litter the atom table.
  #
  # ⚠ Required rather than optional because the verdict is otherwise unreadable:
  # «учтено где-то ещё» without saying where is indistinguishable from «мы решили
  # не считать», and the two have opposite consequences for the caveat a build
  # prints.
  def owned_by!(file, name, entry, verdict) do
    case {entry["owned_by"], verdict} do
      {owner, :counted_elsewhere} when is_binary(owner) and owner != "" ->
        owner

      {_absent_or_blank, :counted_elsewhere} ->
        raise "#{file}: #{name} is `counted_elsewhere` and does not say who counts the fact " <>
                "instead (`owned_by`) — a record nobody can follow says nothing at all"

      {nil, _other_verdict} ->
        nil

      {_present, other_verdict} ->
        raise "#{file}: #{name} is `#{other_verdict}` and states `owned_by`, which only a " <>
                "`counted_elsewhere` record has anywhere to point"
    end
  end

  # Every **mechanism** the core offers to a ceiling must be classified by the
  # block above — otherwise the core would have to pick a side on its own, which is
  # the silent reasonable default CLAUDE.md §3 forbids.
  #
  # Only checked where the ceiling exists at all: a ruleset that states no
  # ceiling clips nothing, and demanding a scope for a ceiling that is not there
  # would fail the build over a question with no observable answer.
  #
  # ⚠ The list per ceiling is written out and not derived, because what the core
  # adds differs per stat: attack takes gear and the shard's racial bonus, a save
  # takes gear and a skill rule (Spellcraft), a skill takes gear and the racial
  # bonus again. Records of the markup files are **not** in any of the lists —
  # since 09.08.2026 each states its own side (`cap_side!/4`), which is the level
  # a kind could never answer at.
  #
  # ⚠ `skill_bonus` joined on 09.08.2026 with task 3.20 (the skill bonuses the
  # player types under «Вещи»). Until then the +50 had exactly one addend, the
  # shard's racial bonus, and `Rules.Skills` clipped it on the spot without
  # asking whose side it was on — which was true and became a trap the moment a
  # second addend arrived: two half-clips of one ceiling would let a Human carry
  # +62 to Discipline, the same way the saves once carried +40 (CLAUDE.md §9).
  #
  # ⚠ `gear_weapon` joined on 10.08.2026 with task 3.5 part B — the first item
  # bonus genuinely **under** the attack ceiling, and the one that makes the +20
  # reachable at all: until then the only source inside it was the shard's racial
  # bonus at +9.
  #
  # ⚠ `weapon_bonus` joined on 16.08.2026 with task 3.35 — the shard's bonus for
  # the **type** of weapon in hand, which is a different mechanism from
  # `gear_weapon` beside it and falls on the opposite side of the attack ceiling:
  # the page says «Бонус входит в лимита атаки +20» about this one, and Dan's Q5
  # measurement took the item's own numbers out (two of them then, one since
  # task 3.52). It is also what makes that
  # ceiling reachable at all — the racial bonus and this one are +9 each, 18 of
  # the 20.
  @cap_mechanisms %{
    attack_bonus: [:gear, :gear_weapon, :racial_bonus, :weapon_bonus],
    saving_throw_bonus: [:gear, :skill_rule],
    skill_bonus: [:gear, :racial_bonus, :weapon_bonus]
  }

  def verify_cap_sources!(caps, scopes, racial_bonuses, skill_rules) do
    Enum.each(@cap_mechanisms, fn {stat, mechanisms} ->
      if is_integer(caps[stat]) do
        scope = Map.get(scopes, stat, %{})
        missing = Enum.sort(mechanisms -- Map.keys(scope))

        unless missing == [] do
          raise """
          stat_caps.#{stat}.applies_to_sources says nothing about #{inspect(missing)}, and the \
          core adds bonuses from #{inspect(mechanisms)}. Whether a source sits inside the \
          ceiling or on top of it is a game fact and cannot be defaulted.
          """
        end

        # The pairs of copies, each guarded where the second copy lives. The
        # racial one is asked per stat rather than for attack alone: since task
        # 3.20 two ceilings name `racial_bonus`, and a guard that knew only about
        # attack would let the Human's «входит в кап навыка +50» drift away from
        # this block unnoticed — which is the whole failure mode two copies of a
        # fact have.
        if :racial_bonus in mechanisms,
          do: verify_racial_bonus_cap_agrees!(stat, scope, racial_bonuses)

        if stat == :saving_throw_bonus,
          do: verify_skill_rule_cap_agrees!(stat, scope, skill_rules)
      end
    end)
  end

  # The second pair of copies of one fact, guarded the same way the racial bonus's
  # pair is: the save ceiling names `skill_rule` inside it, and Spellcraft's own
  # rule names the ceiling it counts towards
  # (`_vanilla_constants_confirmed.skill_save_bonus.rules[].counts_toward_cap`,
  # Dan, 01.08.2026). Neither copy is redundant — one is read while clipping, the
  # other while showing the rule — and the build fails the day they disagree.
  defp verify_skill_rule_cap_agrees!(stat, scope, skill_rules) do
    claimed = for rule <- skill_rules, rule.counts_toward_cap == stat, do: rule.skill

    if claimed != [] and get_in(scope, [:skill_rule, :inside?]) == false do
      raise """
      the skill rule(s) #{inspect(Enum.sort(claimed))} state that their bonus counts towards \
      stat_caps.#{stat}, and stat_caps.#{stat}.applies_to_sources.skill_rule says it does not
      """
    end

    :ok
  end

  # The same fact is stated twice, and on purpose: the ceiling names its sources
  # here, and each race's own page names the ceiling its bonus counts towards
  # (`siala_41/races.json` → `racial_bonus.counts_toward_cap`, quoted). Two copies
  # drift; this fails the build the day they do, which is the only reason keeping
  # both is safe — the same device as `verify_stat_caps!/2`.
  #
  # Asked per `stat`, because two ceilings name a racial bonus: the Half-elf's
  # attack «входит в кап атаки +20» and the Human's Discipline «входит в кап
  # навыка +50».
  defp verify_racial_bonus_cap_agrees!(stat, scope, racial_bonuses) do
    claimed =
      for {race, record} <- Map.get(racial_bonuses || %{}, :by_race, %{}),
          record.counts_toward_cap == stat,
          do: race

    inside? = get_in(scope, [:racial_bonus, :inside?])

    if claimed != [] and inside? == false do
      raise """
      #{inspect(Enum.sort(claimed))} state that their racial bonus counts towards \
      stat_caps.#{stat}, and stat_caps.#{stat}.applies_to_sources.racial_bonus says it does not
      """
    end

    :ok
  end

  # ---------------------------------------------------------------- formulas --

  # The third kind of feat effect (CLAUDE.md §6): not a bonus and not a
  # prerequisite, but a different term in the expression. Carried as data so the
  # hook is general — vanilla also has Zen Archery (attack from wisdom) — rather
  # than a special case wired for Weapon Finesse.
  #
  # ⚠ Four fields per rule since 14.08.2026, because the two vanilla feats of
  # this kind are not the same shape: Finesse replaces **strength** and asks
  # nothing about the weapon, Zen archery replaces **dexterity** and only fires
  # with a ranged weapon in hand. Writing the second as a copy of the first is
  # what kept it out of the data for a fortnight — and a copy would have handed
  # wisdom to a monk with a sword.
  #
  # ⚠ And since 15.08.2026 the **default** is weapon-dependent too (task 3.34,
  # `GAME_CHECKS.md` N1 — Dan: «по умолчанию для дальнобойного оружие AB
  # считается от мода ловкости, а не силы»). It is the same question the rules
  # ask, one level below them, so it reuses the same field (`weapon_must_be`)
  # rather than inventing a second vocabulary for it.
  #
  # ⚠ И с 17.08.2026 (замер S10) правило умеет называть оружие ПОИМЁННО, а не
  # только свойством: «какое оружие лёгкое» ни одна вики свойством не выражает,
  # она перечисляет предметы. Отсюда `weapon_one_of` и `weapon_not_two_handed`
  # рядом с `weapon_must_be` — три разных вопроса об одном и том же оружии
  # в руках, и ни один не выводится из другого.
  def attack_ability(ov, weapons) do
    {default, weapon_defaults} =
      attack_ability_defaults!(dig(ov, ["formulas", "attack_ability", "default"]))

    %{
      default: default,
      # Ordered, and every one of them names a weapon property. The fallback is
      # **not** in this list: it is `default` above, so a reader cannot mistake
      # file order for a game rule.
      weapon_defaults: weapon_defaults,
      rules:
        for rule <- attack_ability_rules!(ov),
            rule["status"] == "verified" do
          one_of = attack_ability_weapon_list!(rule, weapons)

          %{
            feat: atom(rule["feat"]),
            ability: attack_ability_name!(rule, "ability"),
            # Какую характеристику правило ЗАМЕНЯЕТ — та, с которой сравнивает
            # `higher_modifier`. Не названа — сравниваем с `default`, как было до
            # появления второго правила.
            instead_of: attack_ability_name!(rule, "instead_of"),
            condition: atom(rule["condition"]),
            weapon_must_be: attack_ability_weapon!(rule),
            weapon_one_of: one_of,
            weapon_not_two_handed: attack_ability_two_handed!(rule, weapons, one_of),
            assumes: atom_or_nil(rule["assumes"])
          }
        end
    }
  end

  # Объявлено ли хоть одно правило — вопрос гэпа, а не расчёта, поэтому он
  # задаётся сырым записям и разбора не требует.
  def attack_ability_rules_stated?(ov) do
    Enum.any?(attack_ability_rules!(ov), &(&1["status"] == "verified"))
  end

  # Правила хука: ванильная секция плюс сиальская накладка ПОЛЕМ ПОВЕРХ той же
  # записи (`formulas_shard`). Порядок склейки тот же, что у фитов, и по той же
  # причине: у шарда свой список финессируемого оружия (13 против 11), а
  # `formulas` объявлена ванильной и видна ОБОИМ ruleset'ам — дописать сиальскую
  # строку туда значило бы утверждать её и про ваниль.
  #
  # ⚠ Накладка может только переопределять существующее правило: имя фита,
  # которого нет в `formulas`, роняет сборку. Иначе опечатка дала бы ровно ту
  # поломку, ради которой заведены остальные падения этого блока, — запись есть,
  # а не делает ничего.
  defp attack_ability_rules!(ov) do
    base = dig(ov, ["formulas", "attack_ability", "rules"]) || []
    overlay = dig(ov, ["formulas_shard", "attack_ability", "rules"]) || []

    Enum.reduce(overlay, base, fn record, rules ->
      feat = record["feat"]

      unless Enum.any?(rules, &(&1["feat"] == feat)) do
        raise "overrides.json: formulas_shard.attack_ability.rules overrides #{inspect(feat)}, " <>
                "and formulas.attack_ability.rules states no such rule — an override that " <>
                "lands on nothing would silently do nothing"
      end

      for rule <- rules, do: if(rule["feat"] == feat, do: Map.merge(rule, record), else: rule)
    end)
  end

  # Оружие, которым правило вообще работает, — `nil`, если правило про это
  # не спрашивает (так вело себя каждое правило до 17.08.2026).
  #
  # ⚠ Пустой список и незнакомое имя роняют сборку по одной причине: правило,
  # которое не сработает никогда, — это тихое занижение, а тихое занижение здесь
  # уже стоило `Zen archery` полумесяца бездействия.
  defp attack_ability_weapon_list!(rule, weapons) do
    case rule["weapon_one_of"] do
      nil ->
        nil

      %{} = block ->
        verify_attack_ability_verified!(block, rule, "weapon_one_of")

        case attack_ability_weapon_ids!(block["weapons"], weapons, "weapon_one_of.weapons") do
          [] ->
            raise "overrides.json: formulas.attack_ability rule #{inspect(rule["feat"])} " <>
                    "names an empty weapon_one_of — the rule would never fire"

          ids ->
            MapSet.new(ids)
        end

      other ->
        raise "overrides.json: formulas.attack_ability weapon_one_of is #{inspect(other)}, " <>
                "and a block with `weapons`, a quote and a source is required"
    end
  end

  # «Двуручным не финессится» плюс поимённые исключения. Сам ХВАТ здесь не
  # вычисляется и лежать колонкой не может: он функция размера оружия И размера
  # владельца (`Rules.Wield`), поэтому данные говорят только «запрет есть» и
  # «вот кого он не касается».
  defp attack_ability_two_handed!(rule, weapons, one_of) do
    case rule["weapon_not_two_handed"] do
      nil ->
        nil

      %{} = block ->
        verify_attack_ability_verified!(block, rule, "weapon_not_two_handed")

        except =
          attack_ability_weapon_ids!(
            block["except"],
            weapons,
            "weapon_not_two_handed.except"
          )

        # Исключение из запрета для оружия, которого правило и так не берёт,
        # не сработало бы никогда — то же падение, что у пустого списка.
        for id <- except, one_of && not MapSet.member?(one_of, id) do
          raise "overrides.json: formulas.attack_ability rule #{inspect(rule["feat"])} exempts " <>
                  "#{id} from the two-handed ban, and its weapon_one_of does not carry it — " <>
                  "the exemption would never fire"
        end

        %{except: MapSet.new(except)}

      other ->
        raise "overrides.json: formulas.attack_ability weapon_not_two_handed is " <>
                "#{inspect(other)}, and a block with `except`, a quote and a source is required"
    end
  end

  defp attack_ability_weapon_ids!(names, weapons, where) do
    for name <- names || [] do
      id = atom(name)

      unless Map.has_key?(weapons, id) do
        raise "overrides.json: formulas.attack_ability #{where} names #{id}, which " <>
                "weapons.json does not carry — the condition could never be satisfied"
      end

      id
    end
  end

  # ⚠ Понижение статуса — не способ отключить условие про оружие, и падение тут
  # ровно то же, что у `default`: не применённое условие не убирает прибавку,
  # а расширяет правило на ВСЁ оружие, то есть завышает молча. Решать надо
  # в данных — снять блок целиком, а не понизить его.
  defp verify_attack_ability_verified!(block, rule, key) do
    unless block["status"] == "verified" do
      raise "overrides.json: formulas.attack_ability rule #{inspect(rule["feat"])} carries " <>
              "#{key} with status #{inspect(block["status"])} — a weapon condition cannot be " <>
              "half-applied, the rule would fire with any weapon at all"
    end
  end

  # С какой характеристики бросок атаки считается ДО того, как его тронет хоть
  # один фит, — и это свойство того, что в руках (задача 3.34): дальнобойное
  # оружие считает атаку от ловкости, всё остальное и пустые руки — от силы.
  #
  # Возвращает `{ability_для_всего_остального, [запись_по_свойству]}`.
  #
  # ⚠ Три падения вместо трёх молчаний, и все три — про число, а не про
  # прибавку. У соседнего `rules` не сработавшее правило означает «фит ничего
  # не дал», и это заметно; у дефолта не применённая запись означает «AB
  # посчитан от ДРУГОЙ характеристики», и не заметно ничего:
  #
  #   * записей с `weapon_must_be: null` не ровно одна — ноль оставил бы ядро
  #     без ответа для пустых рук (`nil`, то есть модификатор 0), две сделали бы
  #     порядок строк в файле игровым правилом;
  #   * `status` не `verified` — здесь нет безопасного «не применяем»: запись,
  #     которую человек понизил, не убрала бы слагаемое, а поменяла бы
  #     характеристику молча. Поэтому решать надо в данных, а не понижением;
  #   * свойство оружия, которого не знает `Rules.Attack` — то же падение, что
  #     у правил, и по той же причине.
  defp attack_ability_defaults!(nil), do: {nil, []}

  defp attack_ability_defaults!(records) when is_list(records) do
    parsed =
      for record <- records do
        unless record["status"] == "verified" do
          raise "overrides.json: formulas.attack_ability.default carries a record with " <>
                  "status #{inspect(record["status"])} — a default cannot be half-applied, " <>
                  "it would silently change which ability the attack comes off"
        end

        %{
          weapon_must_be: attack_ability_weapon!(record),
          ability: attack_ability_name!(record, "ability")
        }
      end

    case Enum.split_with(parsed, &(&1.weapon_must_be == nil)) do
      {[fallback], conditional} ->
        {fallback.ability, conditional}

      {fallbacks, _conditional} ->
        raise "overrides.json: formulas.attack_ability.default states #{length(fallbacks)} " <>
                "records without a weapon condition, and exactly one is required — it is the " <>
                "answer for empty hands and for a weapon no condition matched"
    end
  end

  defp attack_ability_defaults!(other) do
    raise "overrides.json: formulas.attack_ability.default is #{inspect(other)}, and a list " <>
            "of records is required since task 3.34 — the attack ability depends on the " <>
            "weapon in hand, so one bare ability name cannot state it"
  end

  # ⚠ Опечатка в имени характеристики роняет сборку, а не считается нулём:
  # `instead_of: "dexterity"` вместо `"dex"` сравнивал бы мудрость с нулём, то
  # есть правило срабатывало бы почти всегда и завышало AB. Ошибка молчаливая
  # и в сторону завышения — ровно то, что игрок обнаружит только в игре.
  defp attack_ability_name!(rule, key) do
    case rule[key] do
      nil when key == "instead_of" ->
        nil

      name when is_binary(name) ->
        id = atom(name)

        if id in @abilities,
          do: id,
          else: raise("overrides.json: formulas.attack_ability names ability #{name}")

      other ->
        raise "overrides.json: formulas.attack_ability states #{inspect(other)} as #{key}"
    end
  end

  # Свойство оружия, которое требует правило, спрашивается У ЯДРА
  # (`Rules.Attack.weapon_property_field/1`), а не перечисляется здесь второй
  # копией — тот же приём, что у `weapon_bonus_kinds!/1`. Свойство, которого ядро
  # не знает, роняет сборку: иначе правило молча не сработало бы НИКОГДА, а это
  # ровно та поломка, из-за которой `Zen archery` не делал ничего.
  defp attack_ability_weapon!(rule) do
    case rule["weapon_must_be"] do
      nil ->
        nil

      name ->
        property = atom(name)

        if BuildCalculator.Rules.Attack.weapon_property_field(property) do
          property
        else
          raise "overrides.json: formulas.attack_ability requires the weapon property " <>
                  "#{name}, and BuildCalculator.Rules.Attack cannot read it off a weapon — " <>
                  "the rule would never fire"
        end
    end
  end

  # ------------------------------------------------------------------- epic --

  def build_epic(epic, ov, level_cap) do
    vanilla_cap = Map.fetch!(epic, "character_level_cap")
    grants = dig(ov, ["epic", "level_41_behaviour", "grants"]) || %{}

    attack = cumulative_table(epic, "epic_attack_bonus")
    save = cumulative_table(epic, "epic_save_bonus")

    %{
      starts_at: Map.fetch!(epic, "epic_starts_at_character_level"),
      vanilla_level_cap: vanilla_cap,
      # Levels past the vanilla cap are extended by the shard's own statement of
      # what such a level grants (Siala: level 41 behaves like a vanilla epic
      # odd level -> +1 base attack, nothing to saves). Not hardcoded here.
      attack_bonus: extend(attack, vanilla_cap, level_cap, grants["base_attack"] || 0),
      save_bonus: extend(save, vanilla_cap, level_cap, grants["saves"] || 0),
      # Class levels taken after character level 20 contribute nothing to base
      # attack or base saves. This is the single most consequential epic rule.
      class_levels_count_up_to: Map.fetch!(epic, "epic_starts_at_character_level") - 1,
      general_feat_levels: level_set(epic, "general_feats"),
      ability_increase_levels: level_set(epic, "ability_increases"),
      # Whether the shard's own top level lets a caster pick known spells at all.
      # «На 41-м уровне нельзя выбирать заклинания» (`epic.spell_selection_at_41`,
      # wiki «41-ый уровень» revid 20387, `verified`). Vanilla states no such
      # rule, so the default is `true` and vanilla behaviour is untouched — an
      # absent statement is not a prohibition (CLAUDE.md §3).
      spell_selection_at_level_cap?: verified_flag(ov, ["epic", "spell_selection_at_41"], true),
      attacks_fixed_at_level:
        dig(epic, ["attacks_per_round", "determined_by_bab_at_character_level"]),
      epic_bonus_adds_attacks?:
        dig(epic, ["attacks_per_round", "epic_bonus_adds_attacks"]) == true
    }
  end

  defp cumulative_table(epic, key) do
    epic
    |> Map.fetch!(key)
    |> Map.fetch!("table")
    |> Map.new(fn row -> {row["character_level"], row["bonus"]} end)
  end

  defp extend(table, from_level, to_level, _per_level) when to_level <= from_level, do: table

  defp extend(table, from_level, to_level, per_level) do
    top = table |> Map.values() |> Enum.max(fn -> 0 end)

    (from_level + 1)..to_level//1
    |> Enum.reduce({table, top}, fn level, {acc, running} ->
      if per_level > 0 do
        {Map.put(acc, level, running + per_level), running + per_level}
      else
        {acc, running}
      end
    end)
    |> elem(0)
  end

  defp level_set(epic, key) do
    section = Map.fetch!(epic, key)
    MapSet.new((section["pre_epic_levels"] || []) ++ (section["epic_levels"] || []))
  end

  # --------------------------------------------------------- skill capacity --

  # `character_level + 3`, cross-class half of that rounded down — the formulas
  # are quoted in epic.json rather than tabulated for levels 1..20, so they are
  # applied here and cross-checked against the tabulated epic rows 21..40. A
  # disagreement fails the build instead of silently shipping.
  def skill_rank_caps(epic, level_cap) do
    caps =
      for level <- 1..level_cap//1, into: %{} do
        {level, %{class: level + 3, cross_class: div(level + 3, 2)}}
      end

    for row <- dig(epic, ["level_table", "rows"]) || [] do
      level = row["character_level"]
      expected = caps[level]

      if expected && row["max_skill_rank"] &&
           {row["max_skill_rank"], row["cross_class_max_rank"]} !=
             {expected.class, expected.cross_class} do
        raise """
        skill rank cap formula disagrees with epic.json level_table at level #{level}: \
        formula says #{expected.class}/#{expected.cross_class}, \
        table says #{row["max_skill_rank"]}/#{row["cross_class_max_rank"]}
        """
      end
    end

    caps
  end

  def attacks_per_round(epic) do
    case dig(epic, ["attacks_per_round", "table"]) do
      rows when is_list(rows) ->
        Map.new(rows, fn row -> {row["bab"], row["attacks"]} end)

      _ ->
        @apr_fallback
    end
  end

  # -------------------------------------------------------------- prestige --

  def build_prestige(epic, ov) do
    thresholds = Map.get(epic, "epic_thresholds", %{})
    except = dig(ov, ["classes", "prestige_level_cap", "except"]) || []
    except_caps = dig(ov, ["classes", "prestige_level_cap", "except_max_level"]) || %{}

    %{
      level_cap: dig(ov, ["classes", "prestige_level_cap", "value"]),
      # Classes the shard exempts from the raised prestige cap, each with the cap
      # the shard gives it (Siala: Purple Dragon Knight 10, Harper Scout 5). A
      # class listed without one falls back to its vanilla `max_level`.
      level_cap_exceptions: Map.new(except, fn id -> {atom(id), Map.get(except_caps, id)} end),
      pre_epic_class_level_cap: thresholds["prestige_max_class_level_through_character_level_20"],
      # null in epic.json means "no cap beyond the character level cap itself",
      # per that file's own note — not "unknown".
      epic_class_level_cap: thresholds["prestige_max_class_level_in_epics"],
      epic_from_class_level: thresholds["epic_prestige_class_from_class_level"],
      never_epic: thresholds |> Map.get("never_epic", []) |> Enum.map(&atom/1) |> MapSet.new(),
      never_epic_max_class_level: thresholds["never_epic_max_class_level"]
    }
  end

  # -------------------------------------------------------------- point buy --

  # Character creation costs. Stored cumulatively rather than as a formula so
  # there is nothing to re-derive: the steps are not uniform (1 up to 14, 2 for
  # 15 and 16, 3 for 17 and 18), and the "1 point up to 14, 2 above" shortcut
  # that used to live in the web layer priced an 18 at 14 points instead of 16.
  def point_buy(ov) do
    case dig(ov, ["_vanilla_constants_confirmed", "point_buy"]) do
      %{"cumulative_cost" => costs} = entry when is_map(costs) ->
        %{
          budget: entry["budget"],
          min_score: entry["min_score"],
          max_score: entry["max_score"],
          cost: Map.new(costs, fn {score, cost} -> {String.to_integer(score), cost} end),
          # The floor a caster's key ability may not go below. It lives *inside*
          # the table on purpose: it is spent out of this budget, and a floor
          # without a budget to take it from would be a rule with nothing to
          # apply to.
          caster_minimum: caster_minimum(ov)
        }

      _ ->
        nil
    end
  end

  # «Минимум ключевой характеристики кастера — 11, и он ИТОГОВЫЙ, то есть после
  # расовых модификаторов» (Dan, тестовый сервер, 03.08.2026). Which ability that
  # is is never listed here — it is the class's own `casting_ability`, so the set
  # of casters is derived from the data rather than written down twice.
  #
  # Both keywords have to be ones the core actually implements: a record saying
  # the floor applies to something else, or at some other level, is a rule this
  # schema cannot express, and half a rule applied silently is the failure this
  # file is arranged against. Unknown wording leaves `nil`, and `nil` reinstates
  # `{:missing_data, :caster_minimum_ability}`.
  @caster_minimum_applies_to %{"final_score" => :final_score}
  @caster_minimum_applies_when %{"class_at_character_level_1" => :first_class_level}

  def caster_minimum(ov) do
    entry = dig(ov, ["_vanilla_constants_confirmed", "caster_minimum_ability"])

    with %{"status" => "verified", "verdict" => "applied", "value" => value}
         when is_integer(value) <-
           entry,
         applies_to when not is_nil(applies_to) <-
           Map.get(@caster_minimum_applies_to, entry["applies_to"]),
         applies_when when not is_nil(applies_when) <-
           Map.get(@caster_minimum_applies_when, entry["applies_when"]) do
      %{value: value, applies_to: applies_to, applies_when: applies_when}
    else
      _ -> nil
    end
  end

  # ------------------------------- интеллект с вещей и скилл-поинты --

  # «INT с вещей скилл поинты при повышении уровня не увеличивает» (Dan,
  # 25.08.2026, `source: user` — страницы про это нет ни на одной вики).
  # `overrides.json` → `_vanilla_constants_confirmed.skill_points_gear_intelligence`.
  #
  # ⚠ Три состояния, и они не сводятся к двум: `:ignored` — правило названо
  # и говорит «не считать», `:counted` — названо и говорит обратное, `nil` —
  # не сказал никто. Первые два одинаково молчаливы, третье обязано
  # оговариваться (`{:assumed, :skill_points_ignore_gear_intelligence}` в
  # `Rules.compute/2`), потому что считать мы всё равно будем — а считать без
  # подтверждения молча и есть тот самый разумный дефолт, который CLAUDE.md §3
  # называет худшим видом ошибки.
  #
  # ⚠ `is_boolean/1`, а не `entry["value"]`: `false` здесь — ОТВЕТ, и потерять
  # его в проверке на истинность значило бы вернуть `nil`, то есть напечатать
  # оговорку про правило, которое как раз подтверждено. Ворота на `status`
  # те же, что у соседей по секции: невыверенная запись не имеет права
  # ни считать, ни снимать оговорку.
  @spec skill_points_gear_intelligence(map()) :: :counted | :ignored | nil
  def skill_points_gear_intelligence(ov) do
    case dig(ov, ["_vanilla_constants_confirmed", "skill_points_gear_intelligence"]) do
      %{"status" => "verified", "value" => true} -> :counted
      %{"status" => "verified", "value" => false} -> :ignored
      _ -> nil
    end
  end

  # ------------------------------------------- врождённая прибавка HP --

  # «Дух Сиалы» (задача, волна 12, 09.08.2026, GAME_CHECKS.md заход A кейс
  # A1): `overrides.json` → `character.spirit_of_siala`. Not a feat — no page
  # on either wiki names it, nobody picks it, no class grants it — so it does
  # not go through `apply_feat_hp_bonuses/3` and `ruleset.feats` at all; a
  # feat id would let the interface ask "does this build already have it" or
  # let a prerequisite point at it, neither of which the mechanic supports.
  # `Rules.Progression.hit_points/3` reads this straight off the ruleset,
  # unconditionally, the way it reads `ruleset.base_ac`.
  #
  # `nil` unless `status` is `"verified"`: the same gate `stat_caps/1` and
  # `verified_flag/3` use, so an entry a human has not yet signed off on
  # cannot half-apply. `ru` is required alongside `value` — a bonus with a
  # number and no name would print `spirit_of_siala` raw in the totals panel,
  # the same failure `Labels.feat_name/2`'s fallback exists to avoid for real
  # feats; this mechanic has no `ruleset.feats` entry to fall back to.
  def innate_hp_bonus(ov) do
    entry = dig(ov, ["character", "spirit_of_siala", "hp_bonus"])
    ru = dig(ov, ["character", "spirit_of_siala", "ru"])

    if is_map(entry) and entry["status"] == "verified" and is_integer(entry["value"]) and
         is_binary(ru) do
      %{id: :spirit_of_siala, ru: ru, amount: entry["value"]}
    end
  end

  # ------------------------------------------------- потолки, найденные 3.49 --

  # `Rules.Progression.hit_points/3` always rolls the maximum, on **every**
  # ruleset — that is not this function's business and does not change here.
  # What changes is whether `Loader.Gaps` gets to call the choice an
  # assumption: Siala's own `character.hit_points_roll` (`source: user`, Dan,
  # 2026-08-01) says the shard's rule genuinely **is** "always max, every
  # level" — vanilla's own wiki, by contrast, only guarantees it for character
  # levels 1-3 (`Rules.Progression.hit_points/3`'s moduledoc), so the same
  # arithmetic stays a simplification there. `character` is not one of
  # `loader.ex`'s `@vanilla_sections`, so vanilla's `ov` never carries this key
  # and this returns `false` for it unconditionally — no ruleset needs to
  # opt out, only Siala opts in.
  @spec hp_always_max?(map()) :: boolean()
  def hp_always_max?(ov) do
    match?(
      %{"status" => "verified", "value" => "always_max"},
      dig(ov, ["character", "hit_points_roll"])
    )
  end

  # `skills.rank_cap_at_41` (`source: user`, Dan, 2026-08-01) confirms the one
  # level Siala's own cap sits past vanilla's own table (41 = 40 + 1): «Кап
  # Сиалы 41… ванильная формула «уровень + 3» просто продолжается… Таблицы
  # Fandom кончаются на 40-м, поэтому подтверждение только от игрока».
  # `Character.skill_rank_caps/2` already computes `level + 3` for every level
  # unconditionally and cross-checks it against `epic.json`'s own table through
  # level 40 — this only vouches for the one level past that table, which is
  # what `{:assumed, :skill_rank_caps_past_vanilla_cap}` is about.
  @spec skill_rank_cap_extension_confirmed?(map()) :: boolean()
  def skill_rank_cap_extension_confirmed?(ov) do
    match?(
      %{"status" => "verified", "class_skill" => c, "cross_class" => x}
      when is_integer(c) and is_integer(x),
      dig(ov, ["skills", "rank_cap_at_41"])
    )
  end
end
