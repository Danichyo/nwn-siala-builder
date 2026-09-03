defmodule BuildCalculator.Data.Loader.Races do
  @moduledoc """
  Расы: ванильные записи, сиальский слой поверх них, расовый бонус Сиалы и бонус
  за тип оружия в руках.

  Две последние системы стоят рядом не случайно: бонус за тип оружия зеркалит
  расовый число в число (CLAUDE.md §3), и обе выбирают вариант величины по одной
  и той же принадлежности билда к группе классов (`Loader.Systems`).
  """

  alias BuildCalculator.Data.Loader.NotAGap
  alias BuildCalculator.Data.Loader.Reading
  alias BuildCalculator.Data.Loader.Systems

  import BuildCalculator.Data.Loader.Reading

  @ability_keys Reading.ability_keys()

  # ------------------------------------------------------------------ races --

  def build_races(:missing), do: %{}

  def build_races(list) do
    Map.new(list, fn r ->
      id = atom(r["id"])

      {id,
       %{
         id: id,
         name: r["name"],
         ability_modifiers: ability_map(r["ability_modifiers"]),
         # %{"level" => 1, "per_level" => 1, "extra" => 4} for humans, nil otherwise
         bonus_skill_points: keyword_ints(r["bonus_skill_points"]),
         extra_feats: keyword_ints(r["extra_feats"]),
         ru: nil,
         siala: nil,
         favored_class: atom_or_nil(r["favored_class"]),
         favored_class_any?: r["favored_class_any"] == true,
         bonus_feats: Enum.map(r["bonus_feats"] || [], &atom/1),
         skill_bonuses: Map.new(r["skill_bonuses"] || %{}, fn {k, v} -> {slug(k), v} end),
         # Размер расы и её именные запреты (задача 3.44, читает задача 3.43).
         # Размер — ступень лестницы `_grip.size_order`, по которой считается
         # хват: длинный меч одноручен у человека и двуручен у Карлика.
         size: atom_or_nil(r["size"]),
         # Что раса не может носить, ИМЕНАМИ ПОЛЕЙ, а не значениями: предмет
         # в `gear.worn` указывает на поле по имени (`race_restriction`), и
         # ядро сравнивает два атома. Так ни одно имя расы и ни одно имя щита
         # не попадает в код — обе стороны названы данными.
         restrictions: race_restrictions(r),
         source: r["source"]
       }}
    end)
  end

  # Булевы поля вида `cannot_use_*`, стоящие в `true`, — как множество имён.
  #
  # ⚠ Читаются ПО ФОРМЕ ИМЕНИ, а не по списку: файл рас машинный, и запрет,
  # добавленный туда следующей волной парсера, обязан доехать сам. Ложные
  # срабатывания невозможны — на другую сторону смотрит `worn!/3`, и ключ,
  # которого не называет ни один предмет, ничего не запрещает.
  defp race_restrictions(%{} = raw) do
    for {key, true} <- raw, String.starts_with?(key, "cannot_"), into: MapSet.new(), do: atom(key)
  end

  # The shard renamed and rebuilt the races rather than translating them, so its
  # name is the primary one (CLAUDE.md §4: "Гном" is Dwarf, "Карлик" is Gnome).
  # The mechanical part of the shard layer — `racial_bonus`, tied to the custom
  # weapon system — is carried whole but not modelled.
  def apply_race_layer(races, :missing), do: races

  def apply_race_layer(races, %{"races" => entries}) do
    Enum.reduce(entries, races, fn entry, acc ->
      id = atom(entry["vanilla_id"] || entry["id"])

      case Map.fetch(acc, id) do
        :error -> acc
        {:ok, race} -> Map.put(acc, id, Map.merge(race, %{ru: entry["ru"], siala: entry}))
      end
    end)
  end

  def apply_race_layer(races, _other), do: races

  # ------------------------------------------------- shard racial bonuses --

  # The shard's own racial bonus (`siala_41/races.json` → `racial_bonus`). Not a
  # vanilla racial trait at all: it mirrors the custom weapon system — an effect
  # that lands on the character when a weapon is taken in hand — and it **grows
  # with character level** while every number on the page is stated for one
  # level.
  #
  # ⚠ Task 3.12 reverses the decision of 01.08.2026 (`_decision` in the file
  # records both). The numbers reach the calculator, and only where they are
  # true: at and above the level they are stated for, because the wiki says the
  # bonus is already maximal there. Below it nothing is counted and the build
  # says why — a fraction of the maximum would be a game number nobody wrote
  # down (CLAUDE.md §3).
  #
  # Which shapes the file may state. **Not** a list of what the core counts —
  # that is `Rules.RacialBonus`'s decision, and for the rest it answers with a
  # gap naming the race and the shape. This is a guard against a typo:
  # `shield_AC` would arrive as an unknown shape, and an unknown shape counts
  # for nothing while looking like data.
  @racial_bonus_kinds ~w(attack_bonus shield_ac skill_bonus damage_resistance damage)

  # The four numbers every such record carries. ⚠ Two of them can be counted and
  # two cannot, and the line runs exactly where the model's knowledge does:
  #
  #   * `base` — always;
  #   * `sagra_warrior` — decidable from the class list since 08.08.2026
  #     (`BuildCalculator.Rules.ClassGroups`; Dan: «сагровик получит больше
  #     бонусов, чем несагровик»);
  #   * `racial_weapon` and both together — **not**, and not for lack of trying:
  #     they depend on what is in the character's hands, and weapons are not
  #     modelled at all until the armoury (task 3.5).
  #
  # All four are carried whole anyway, so the interface can show the uncounted
  # ones as reference beside the counted one — which is what stops the smaller
  # number from reading as the whole truth.
  @racial_bonus_variants ~w(base sagra_warrior racial_weapon racial_weapon_and_sagra_warrior)

  # What each of those four numbers is stated **for**, read off the key's own
  # name: `_and_` joins two conditions and `base` names none. That naming is the
  # only machine-readable statement of the difference between the four — the page
  # itself says it in prose («для [[Воины Сагры|персонажа-сагровика]] бонус
  # увеличивается до +9») — and reading it here means a condition the core cannot
  # decide keeps its number out of the arithmetic instead of needing a list of
  # keys somebody has to remember to extend.
  defp racial_bonus_variant_conditions do
    Map.new(@racial_bonus_variants, fn
      "base" -> {atom("base"), []}
      key -> {atom(key), key |> String.split("_and_") |> Enum.map(&atom/1)}
    end)
  end

  # And what each condition *is*. One resolves today: `sagra_warrior`, whose key
  # in `races.json` is spelled exactly like the variant and whose entry cites the
  # group's own page — so the link between «the number for a sagra warrior» and
  # «the class group Воины Сагры» is two facts in the data rather than a pairing
  # written here. Everything the name mentions and this map does not carry stays
  # undecidable, and `Rules.RacialBonus` leaves such a variant uncounted.
  defp racial_bonus_conditions(layer, class_groups) do
    for {key, entry} <- Systems.class_group_conditions(layer),
        page = dig(entry, ["source", "page"]),
        group = Enum.find(class_groups, &(&1.name == page)),
        into: %{} do
      {atom(key), {:class_group, group.id}}
    end
  end

  # A `shield_ac` bonus is an armour class bonus **of the shield type**, and the
  # type has to be one the ruleset already knows: a same-type collision is what
  # stops it stacking with the shield the player typed in (`Rules.ArmorClass`).
  # Written out rather than derived from the shape's name — a stacking rule must
  # not attach to a bonus because two strings happen to share a suffix. Same
  # device as `Rules.Gear`'s `@ac_type_caps`.
  #
  # ⚠ Shared by the racial bonus and the weapon-type bonus (task 3.35), and that
  # is the point rather than a saving: the shard's own pages state the two as the
  # **same** bonus seen from two sides («Бонус идентичен бонусу от [[Владение
  # клинковым оружием]]»), so a second table could only ever be a way for them to
  # disagree.
  @shard_bonus_ac_types %{"shield_ac" => "shield"}

  @doc """
  Which shard bonus shapes land in armour class at all.

  Asked by `BuildCalculator.Data.Loader.Gear` (task 3.91): a shape may be given
  its own answer to «складывается ли эта прибавка с числом, которое игрок вписал
  под тем же типом», and a shape that lands nowhere near armour class cannot
  meaningfully have one. Naming it there would declare a rule that never fires,
  which is the silent kind of wrong the whole `!`-suffixed half of this file
  exists to prevent.

  ⚠ The one table, asked rather than copied. A second list of AC-carrying shapes
  beside `@shard_bonus_ac_types` would be a way for the two to disagree about
  the same word — exactly what the note above this attribute says about the
  racial and the weapon-type halves.
  """
  @spec shard_bonus_ac_kinds() :: [String.t()]
  def shard_bonus_ac_kinds, do: Map.keys(@shard_bonus_ac_types)

  # The ceiling a record says it counts towards, as the key `stat_caps` uses.
  # The page writes «кап навыка +50» as `skill`, and the ceiling is
  # `skill_bonus`; one spelling of one fact, mapped once here rather than twice
  # in the core.
  @racial_bonus_cap_keys %{"attack_bonus" => "attack_bonus", "skill" => "skill_bonus"}

  def racial_bonuses(:missing, _dictionaries), do: nil

  def racial_bonuses(%{} = layer, dictionaries) do
    scaling = layer["level_scaling"] || %{}

    %{
      # The level every number in the file is stated for, and the level the bonus
      # stops growing at. Both are needed and neither alone is enough: the first
      # says which number we hold, the second whether it still holds above that
      # level. See `Rules.RacialBonus.counted_at?/2`.
      stated_for_level: dig(scaling, ["numbers_are_for_level", "value"]),
      max_at_level: dig(scaling, ["max_at_level", "value"]),
      # The growth function — `null` on the wiki, which is the whole reason a
      # build below `max_at_level` gets a gap instead of a number.
      #
      # ⚠ Read by nothing since 22.08.2026 (task 3.81): the two functions that
      # read it produced the ruleset-wide «no progression» gaps, and Dan closed
      # both. Kept as the transcription it is — the page names no function, and
      # the snapshot has to keep saying so.
      formula: dig(scaling, ["formula", "value"]),
      # Which of the four numbers is stated for what, and which of those
      # conditions the core can decide. Two maps rather than one flag per
      # variant, so that «what this number is for» and «can we tell» stay
      # separate questions — see `racial_bonus_variant_conditions/0` and
      # `racial_bonus_conditions/2`.
      variant_conditions: racial_bonus_variant_conditions(),
      conditions: racial_bonus_conditions(layer, dictionaries.class_groups),
      # What switches the bonus on. The page has said since 01.08.2026 that it is
      # «эффект в момент взятия оружия в руку», but that sentence lived in prose
      # nobody read, and the core handed the bonus over unconditionally — Dan
      # measured the difference on 15.08.2026 (naked AB 29 against our 38).
      activation: racial_bonus_activation!(layer["activation"] || %{}, dictionaries.weapons),
      by_race: racial_bonus_records(layer["races"] || [], dictionaries)
    }
  end

  # `requires_weapon_in_hand` absent means "nothing switches it off" — the pre-
  # 15.08.2026 behaviour, which is also the right answer for a ruleset that
  # states no activation rule at all. Absence is not treated as `false` with a
  # warning: a layer without the field never made the claim.
  defp racial_bonus_activation!(%{} = activation, weapons) do
    %{
      switched_on_by_weapon?: dig(activation, ["activated_by_weapon_in_hand", "value"]) == true,
      non_activating:
        MapSet.new(
          racial_bonus_non_activating!(
            dig(activation, ["non_activating_weapons", "value"]),
            weapons
          )
        )
    }
  end

  defp racial_bonus_non_activating!(nil, _weapons), do: []

  defp racial_bonus_non_activating!(ids, weapons) when is_list(ids) do
    for id <- ids do
      atom = atom(id)

      # Same guard as every other name the shard layer states: a weapon renamed
      # in `weapons.json` must stop the build rather than silently switch the
      # exception off, because the failure would be invisible — the bonus would
      # simply start counting where the page says it does not.
      if weapons != %{} and not Map.has_key?(weapons, atom) do
        raise "siala_41/races.json: activation.non_activating_weapons names #{id}, " <>
                "which weapons.json does not carry"
      end

      atom
    end
  end

  defp racial_bonus_non_activating!(other, _weapons),
    do: raise("siala_41/races.json: activation.non_activating_weapons is #{inspect(other)}")

  defp racial_bonus_records(entries, dictionaries) do
    for entry <- entries,
        bonus = entry["racial_bonus"],
        is_map(bonus),
        is_binary(bonus["kind"]),
        into: %{} do
      id =
        racial_bonus_id!(entry["vanilla_id"] || entry["id"], dictionaries.races, "race", "races")

      {id, racial_bonus_record(id, bonus, dictionaries)}
    end
  end

  defp racial_bonus_record(id, bonus, dictionaries) do
    if bonus["kind"] not in @racial_bonus_kinds do
      raise "siala_41/races.json: racial_bonus kind #{inspect(bonus["kind"])} on #{id} " <>
              "is not one this loader knows"
    end

    %{
      race: id,
      kind: atom(bonus["kind"]),
      # Where an armour class bonus lands, for the shapes that are one.
      ac_type: shard_bonus_ac_type!(id, bonus["kind"], dictionaries.ac_types),
      # Which skill a `skill_bonus` lands on, checked against the dictionary.
      skill: racial_bonus_skill!(id, bonus, dictionaries.skills),
      variants: racial_bonus_variants!(id, bonus["at_level_40"]),
      # The ceiling the page says this bonus counts towards, as the stat key
      # `stat_caps` uses — so the core clamps it together with everything else
      # counting towards the same ceiling instead of giving it one of its own.
      # (`nil` where the page names none, which is not the same as "uncapped
      # everywhere": it is "this page says nothing".)
      counts_toward_cap:
        racial_bonus_cap!(id, bonus["counts_toward_cap"], dictionaries.stat_caps),
      status: bonus["status"]
    }
  end

  defp shard_bonus_ac_type!(id, kind, ac_types) do
    case Map.fetch(@shard_bonus_ac_types, kind) do
      :error ->
        nil

      {:ok, type} ->
        atom = atom(type)

        if ac_types != [] and atom not in ac_types do
          raise "siala_41: #{id}'s #{kind} lands on AC type #{type}, " <>
                  "which the ruleset does not carry"
        end

        atom
    end
  end

  defp racial_bonus_skill!(id, %{"kind" => "skill_bonus"} = bonus, skills) do
    case bonus["skill"] do
      name when is_binary(name) -> racial_bonus_id!(name, skills, "skill", "races")
      _ -> raise "siala_41/races.json: #{id}'s skill_bonus names no skill"
    end
  end

  defp racial_bonus_skill!(_id, _bonus, _skills), do: nil

  # All four variants or none: a record missing one of them is a transcription
  # that half happened, and picking the keys that are there would hide it.
  defp racial_bonus_variants!(id, %{} = at_level) do
    for key <- @racial_bonus_variants, into: %{} do
      case at_level[key] do
        value when is_integer(value) ->
          {atom(key), value}

        _ ->
          raise "siala_41/races.json: #{id}'s racial_bonus states no integer #{key}"
      end
    end
  end

  defp racial_bonus_variants!(id, _other),
    do: raise("siala_41/races.json: #{id}'s racial_bonus states no at_level_40 numbers")

  defp racial_bonus_cap!(_id, nil, _caps), do: nil

  defp racial_bonus_cap!(id, %{} = entry, caps) do
    key =
      case Map.fetch(@racial_bonus_cap_keys, entry["kind"]) do
        {:ok, key} -> atom(key)
        :error -> raise "siala_41/races.json: #{id} counts towards unknown cap #{entry["kind"]}"
      end

    # ⚠ Two writings of one number — `races.json` says «входит в кап атаки +20»
    # and `overrides.json` carries the 20 the core actually clips at. They must
    # agree, or the interface would name a ceiling the arithmetic does not use.
    # Same device and same reason as `verify_stat_caps!/2`.
    stated = entry["value"]

    case Map.fetch(caps, key) do
      {:ok, applied} when is_integer(stated) and applied != stated ->
        raise "siala_41/races.json: #{id} says the #{key} cap is #{stated}, " <>
                "overrides.json says #{applied}"

      _ ->
        key
    end
  end

  # ⚠ Здесь стояла `racial_bonus_gaps/1`, заводившая гэп ruleset'а
  # `{:missing_data, :racial_bonus_progression}` — «расовый бонус растёт
  # с уровнем персонажа, числа на вики есть только для 40-го, функции роста
  # не называет ни одна страница». **Снята 22.08.2026 решением Dan** (задача
  # 3.81): «прогрессию делать не будем, данный пробел можно закрыть».
  #
  # Это продолжение его же решения Q2 от 15.08.2026, которым добывание
  # прогрессии было закрыто: «Полноценный билд всегда идет для 40 или 41
  # уровня, поэтому промежуточные цифры не важны, главное итог в конце.
  # Я не буду производить данные замеры, могу ошибиться или перепутать».
  # Гэп — дырка в **нашем ответе** (CLAUDE.md §9), а ответ по решению
  # владельца даётся на 40–41 уровне; прогрессия ниже него перестала быть
  # чем-то, чего нашему ответу не хватает.
  #
  # 🔴 **Оговорка на КОНКРЕТНОМ билде этим не снята и сниматься не должна:**
  # `{:missing_data, {:racial_bonus_level, race}}` (`Rules.RacialBonus.gaps/2`)
  # по-прежнему приезжает каждому билду ниже 40-го, потому что бонус в игре
  # есть, а величины его не знает никто. Разница ровно в том, на какой вопрос
  # отвечает форма: снятая отвечала «насколько полны правила Сиалы у нас
  # в данных», живая — «что не посчитано в ЭТОМ числе». Замерено прогоном:
  # светлый эльф-воин 25-го уровня с луком получает AB, вдвое меньший, чем
  # на 40-м, и две эти оговорки — единственное, что говорит ему об этом.
  # Под тестом (`racial_bonus_test.exs`, «решение 3.81 сняло гэп корпуса
  # и не тронуло гэп билда»).
  #
  # ⚠ Вместе с формой ушёл и её механизм самоотмены («появится `formula` —
  # гэп исчезнет сам»). Он больше ничего не значит: формулы не будет не потому,
  # что её никто не переписал, а потому, что её решено не добывать.
  #
  # ⚠ Поле `racial_bonuses.formula` при этом ОСТАЁТСЯ и остаётся `nil` — это
  # дословный перенос `level_scaling.formula` со страницы, он виден в снимке
  # и говорит, что функции роста вики не называет. Читателя в коде у него
  # больше нет ни одного: уровень решает `RacialBonus.counted_at?/2` по паре
  # `stated_for_level` / `max_at_level`, и так было всегда — `formula` читали
  # только две снятые сегодня функции. Удалять перенос ради того, чтобы его
  # никто не читал, значило бы потерять провенанс.

  # A name checked against a dictionary that has arrived. An empty dictionary
  # means the file is missing, not that the name is wrong — the same distinction
  # `BonusMarkup.id!/5` makes.
  defp racial_bonus_id!(name, dictionary, kind, file) do
    id = atom(name)

    if map_size(dictionary) > 0 and not Map.has_key?(dictionary, id) do
      raise "siala_41/#{file}.json names #{kind} #{name}, which does not exist"
    end

    id
  end

  # -------------------------------------------- the shard's weapon-type bonus --

  # The other half of the system the racial bonus mirrors (task 3.35). Siala
  # gives a character a bonus for the **type of weapon in his hands**, and
  # `races.json` describes every racial bonus as identical to one of these
  # («Бонус идентичен бонусу от [[Владение клинковым оружием]]») — same three
  # shapes, same numbers, same level rule, and Dan measured on 15.08.2026 that
  # the two are **added**, not merged: «30 БАБ + 9 мод + 5 лук + 9 светлый эльф +
  # 9 оружие дальнего боя = ровно 62» (`GAME_CHECKS.md` Q1).
  #
  # ## Three statements are joined here and none of them is a number
  #
  #   1. `bonuses_at_level_40` — the six rows of the page, one per weapon type;
  #   2. `weapon_specific_bonus_overrides` — eight weapons whose bonuses the page
  #      states individually, and which **replace** the row above rather than
  #      adding to it (a halberd is a polearm and carries a blade's shield AC on
  #      top; a two-bladed sword's +9 is explicitly not multiplied for a warrior
  #      of Sagra);
  #   3. `bonus_application` — the join itself: the page's own key for a weapon
  #      type against the id in `weapons.json`, the two weapons the page excludes
  #      by name, the skill a «+12 дисциплины» lands on, and the class group whose
  #      page the second number of every row is stated for.
  #
  # The third is `assumed` on purpose and marked so in the data: the page writes
  # Russian prose and the dictionaries hold ids, so every pairing is ours. What is
  # **not** ours is any number — those are quoted, and this loader would rather
  # fail the build than let a row through whose group, skill or weapon it cannot
  # resolve.
  @weapon_type_bonus_kinds ~w(shield_ac discipline_skill attack_bonus damage_reduction
                              sonic_damage physical_immunity_percent
                              ignores_target_damage_resistance bleed_debuff)

  # The two numbers every row carries: the **role** the core knows them by, and
  # the key the page's transcription spells them with.
  #
  # ⚠ Translated here rather than passed through, and that is a rule rather than
  # tidiness: `sagra` is the name of a class group, i.e. a game entity, and the
  # core is not allowed to know one (CLAUDE.md §5). The role is what the core
  # actually needs — «число для члена группы» against «число для всех
  # остальных» — and which group that is arrives separately, as an id resolved
  # from the page title.
  @weapon_type_bonus_variants [base: "base", in_group: "sagra"]

  def weapon_type_bonuses(systems, dictionaries) do
    case Enum.find(systems, &(&1.id == :weapon_system)) do
      nil -> nil
      system -> weapon_type_bonus_layer(system, dictionaries)
    end
  end

  defp weapon_type_bonus_layer(system, dictionaries) do
    case Systems.system_fact(system, "bonuses_at_level_40") do
      %{} = rows ->
        application = weapon_type_bonus_fact!(system, "bonus_application")
        scaling = weapon_type_bonus_fact!(system, "bonuses_level_scaling")
        overrides = Systems.system_fact(system, "weapon_specific_bonus_overrides") || []

        %{
          # The level the numbers are stated for and the level the bonus stops
          # growing at — both required by `Rules.WeaponTypeBonus.counted_at?/2`,
          # exactly as the racial bonus requires them, and for the same reason:
          # one says which number we hold, the other whether it still holds at
          # the shard's extra level.
          stated_for_level: scaling["numbers_are_for_level"],
          max_at_level: scaling["max_at_level"],
          # `nil` on the wiki, which is the whole reason a build below
          # `max_at_level` gets a gap instead of a fraction of the maximum.
          # ⚠ Read by nothing since task 3.81, exactly like its racial twin
          # above, and kept for the same reason: it is what the page says.
          formula: scaling["formula"],
          by_group: weapon_type_bonus_by_group!(rows, application, dictionaries),
          by_weapon: weapon_type_bonus_by_weapon!(overrides, application, dictionaries),
          excluded: weapon_type_bonus_excluded!(application, dictionaries.weapons),
          # A weapon the page gives a bonus to and `weapons.json` does not carry
          # at all. Kept as the page's own name, because there is no id to key
          # it by — that is the whole content of the statement.
          #
          # ⚠ Записи с решением владельца (`not_a_gap`) сюда не попадают —
          # задача 3.82, «Вилы»: предмет в игре ЕСТЬ, но им никто не играет,
          # и Dan решил не заводить его в справочник. 🔴 Гасится РОВНО ЭТА
          # запись, а не механизм: форма параметризована именем, и завтра шард
          # может назвать второй предмет, которого у нас нет, — про него
          # промолчать нельзя. Сторож на поля решения — общий, в `Loader.Races`
          # ниже.
          unmatched:
            for(
              entry <- overrides,
              is_nil(entry["weapon_id"]),
              :ok == verify_not_a_gap!(entry["weapon_ru"], entry["not_a_gap"]),
              not is_map(entry["not_a_gap"]),
              do: entry["weapon_ru"]
            ),
          # Which class group the bigger of the two numbers is stated for. `nil`
          # when the data names none, and then every build takes the smaller one.
          class_group: weapon_type_bonus_group!(application, dictionaries.class_groups),
          # Что делать с ДВУМЯ оружиями в руках (задача 3.132). Половина цитата
          # («два разных оружия — два разных бонуса»), половина чтение (про два
          # оружия одной группы источник молчит), и ядро говорит об этом вслух
          # ровно там, где чтение кусает. ⚠ `nil` — записи нет: тогда считается
          # только главная рука, то есть поведение до задачи 3.132.
          both_hands: weapon_type_bonus_both_hands(system)
        }

      _absent ->
        nil
    end
  end

  # ⚠ НЕ `weapon_type_bonus_fact!/2`: правило про две руки появилось задачей
  # 3.132, а снапшот без него — законное состояние (так выглядели все данные
  # до неё). Отсутствие записи означает «считаем главную руку», то есть ровно
  # прежнее поведение, а не половину нового.
  @both_hands_fact "bonuses_from_both_hands"

  defp weapon_type_bonus_both_hands(system) do
    case Systems.system_fact(system, @both_hands_fact) do
      %{} = rule ->
        %{
          different_kinds: atom_or_nil(rule["different_kinds"]),
          same_kind: atom_or_nil(rule["same_kind"]),
          # 🔴 Подтверждено ли ВТОРОЕ правило («один и тот же вид не
          # удваивается») — `nil`, пока нет. Это ровно тот механизм, что
          # `stacking_confirmed` у прибавок к AC (задача 3.90): оговорка
          # снимается ОТМЕТКОЙ НА ЗАПИСИ, а не выключателем на механизме,
          # и снапшот, принёсший правило без отметки, получит её обратно сам.
          #
          # ⚠ Провенанс у двух половин записи РАЗНЫЙ, и здесь это видно:
          # `different_kinds` стоит на цитате вики, а отметка несёт своё
          # `source` со словом владельца.
          same_kind_confirmed:
            both_hands_confirmed!(
              Systems.system_fact_field(system, @both_hands_fact, "same_kind_confirmed")
            )
        }

      _absent ->
        nil
    end
  end

  # Сторож отметки — тот же по составу и по доводу, что у `stacking_confirmed`
  # (`Loader.Bonuses.stacking_mark!/2`) и у `not_a_gap` (`Loader.NotAGap`):
  # отметка убирает оговорку с экрана игрока, НИЧЕГО не посчитав, и потому она
  # обязана назвать, ЧТО подтверждено, ПОЧЕМУ это снимает оговорку, и кем и
  # когда сказано. Полу-записанная отметка роняет сборку.
  #
  # ⚠ `what` списком: у этой отметки две строки, и вторая называет ГРАНИЦУ
  # наблюдения («видели на клинковых, распространили словом владельца»).
  # Стереть её значило бы выдать наблюдение на одном виде за наблюдение
  # на всех — ровно та подмена, на которой проект горел с `spell_focus`.
  @confirmed_source ~w(kind who date)

  defp both_hands_confirmed!(nil), do: nil

  defp both_hands_confirmed!(%{} = mark) do
    cond do
      not confirmed_words?(mark["what"]) ->
        raise "siala_41/systems.json: bonuses_from_both_hands states " <>
                "`same_kind_confirmed` without a non-empty `what` — a mark that does not " <>
                "name WHAT was confirmed is «нам сказали, что всё хорошо»"

      not confirmed_word?(mark["why"]) ->
        raise "siala_41/systems.json: bonuses_from_both_hands states " <>
                "`same_kind_confirmed` without a non-empty `why`"

      mark["status"] != "verified" ->
        raise "siala_41/systems.json: bonuses_from_both_hands states " <>
                "same_kind_confirmed.status #{inspect(mark["status"])}; only \"verified\" " <>
                "takes a caveat off the player's screen"

      not is_map(mark["source"]) ->
        raise "siala_41/systems.json: bonuses_from_both_hands states " <>
                "`same_kind_confirmed` without a `source`"

      true ->
        for field <- @confirmed_source do
          unless confirmed_word?(mark["source"][field]) do
            raise "siala_41/systems.json: bonuses_from_both_hands states " <>
                    "`same_kind_confirmed` whose source has no non-empty `#{field}` — a fact " <>
                    "that removes a caveat can only do so with its kind, its author and its " <>
                    "date named"
          end
        end

        mark
    end
  end

  defp both_hands_confirmed!(other) do
    raise "siala_41/systems.json: bonuses_from_both_hands states " <>
            "same_kind_confirmed #{inspect(other)}, which is not a mark"
  end

  defp confirmed_word?(value), do: is_binary(value) and String.trim(value) != ""

  defp confirmed_words?(value),
    do: is_list(value) and value != [] and Enum.all?(value, &confirmed_word?/1)

  # The join and the level rule are **required** once the numbers are there: a
  # transcription that states six rows and no way to reach them would count for
  # nothing while looking complete, which is the one failure this whole file is
  # arranged against.
  defp weapon_type_bonus_fact!(system, what) do
    Systems.system_fact(system, what) ||
      raise "siala_41/systems.json: weapon_system states bonuses_at_level_40 and no #{what}"
  end

  defp weapon_type_bonus_by_group!(rows, application, dictionaries) do
    groups = application["groups"] || %{}

    for {page_key, row} <- rows,
        group = weapon_type_bonus_group_id!(page_key, groups, dictionaries.weapons),
        into: %{} do
      {group, [weapon_type_bonus_record!(page_key, row, application, dictionaries)]}
    end
  end

  # `nil` — a row the dictionary has no group for at all. Exactly one today, and
  # it is a finding rather than a hole: a shield is not a weapon, `weapons.json`
  # has no entry for one, and its 18 %/36 % physical immunity has no receiver in
  # a build either way. A key the join says **nothing** about is a different
  # thing and fails the build.
  defp weapon_type_bonus_group_id!(page_key, groups, weapons) do
    case Map.fetch(groups, page_key) do
      {:ok, nil} ->
        nil

      {:ok, name} when is_binary(name) ->
        id = atom(name)
        known = for {_id, weapon} <- weapons, uniq: true, do: weapon.proficiency_group

        if weapons != %{} and id not in known do
          raise "siala_41/systems.json: bonus_application.groups maps #{page_key} to " <>
                  "#{name}, and no weapon in weapons.json belongs to such a group"
        end

        id

      _absent ->
        raise "siala_41/systems.json: bonuses_at_level_40 states a bonus for #{page_key} " <>
                "and bonus_application.groups says nothing about it"
    end
  end

  defp weapon_type_bonus_by_weapon!(overrides, application, dictionaries) do
    for entry <- overrides, is_binary(entry["weapon_id"]), into: %{} do
      id = weapon_type_bonus_weapon_id!(entry["weapon_id"], dictionaries.weapons)

      records =
        for bonus <- entry["bonuses"] || [],
            do: weapon_type_bonus_record!(entry["weapon_ru"], bonus, application, dictionaries)

      {id, records}
    end
  end

  # One row of the page — a weapon type's or a single weapon's — as the core
  # reads it. The **kind** decides everything else, and it decides it the same
  # way for both, which is why there is one function and not two: two readings of
  # one vocabulary would eventually give a halberd and a spear different answers
  # about the same «+12 дисциплины».
  defp weapon_type_bonus_record!(label, row, application, dictionaries) do
    kind = row["kind"]

    unless kind in @weapon_type_bonus_kinds do
      raise "siala_41/systems.json: #{label} states a bonus of kind #{inspect(kind)}, " <>
              "which this loader does not know — an unknown kind counts for nothing"
    end

    {core_kind, skill} = weapon_type_bonus_target!(label, kind, application, dictionaries)

    %{
      kind: core_kind,
      skill: skill,
      ac_type: shard_bonus_ac_type!(label, kind, dictionaries.ac_types),
      # `nil` where the page names the *type* of bonus and no number — «Бонус к
      # классу брони (Shield bonus)» on a halberd and a greataxe. Carried as
      # `nil` rather than defaulted to the blade's 6/9, because the one weapon of
      # that section whose number the page does state turned out to be an
      # exception (a two-bladed sword's +9 is not multiplied for a warrior of
      # Sagra), so the family is not uniform and a default would be an invention.
      variants: Map.new(@weapon_type_bonus_variants, fn {role, key} -> {role, row[key]} end),
      # A variant whose number rests on a reading rather than on a sentence. One
      # today: «Данный бонус не модифицируется. Он одинаковый для всех билдов» is
      # quoted, and reading «для всех билдов» as covering a warrior of Sagra too
      # is ours (`sagra_reading_status` in the data).
      assumed_variants: weapon_type_bonus_assumed_variants(row),
      counts_toward_cap: row["counts_toward_cap"]
    }
  end

  # Which of the core's numbers a kind lands in. A kind the join names as a skill
  # bonus becomes one, with the skill checked against the dictionary; everything
  # else keeps its own name, and `Rules.WeaponTypeBonus` decides whether the
  # calculator carries such a number at all.
  defp weapon_type_bonus_target!(label, kind, application, dictionaries) do
    case Map.fetch(application["skills"] || %{}, kind) do
      {:ok, name} when is_binary(name) ->
        {atom("skill_bonus"), racial_bonus_id!(name, dictionaries.skills, "skill", "systems")}

      {:ok, other} ->
        raise "siala_41/systems.json: #{label}'s #{kind} names #{inspect(other)} as its " <>
                "skill, which is not a name"

      :error ->
        {atom(kind), nil}
    end
  end

  defp weapon_type_bonus_assumed_variants(row) do
    if row["sagra_reading_status"] == "assumed",
      do: MapSet.new([:in_group]),
      else: MapSet.new()
  end

  defp weapon_type_bonus_excluded!(application, weapons) do
    for {_page_key, ids} <- application["excluded_weapons"] || %{},
        id <- ids,
        into: MapSet.new(),
        do: weapon_type_bonus_weapon_id!(id, weapons)
  end

  # Same guard as `racial_bonus_non_activating!/2`, and the failure it prevents is
  # the same shape: a weapon renamed in `weapons.json` would silently stop being
  # excluded, i.e. would silently start carrying a bonus the page denies it.
  # ⚠ Сторож поля `not_a_gap` — задача 3.82. ⚠️ Здесь стояла ТРЕТЬЯ копия
  # проверки, дословный близнец тех, что стояли у фактов класса
  # (`Loader.Classes`) и у записей разметки (`BonusMarkup`); задача 3.95 свела
  # все четыре в `Loader.NotAGap` — четвёртая копия и была поводом. Правило
  # прежнее: поле снимает запись со счёта пробелов, то есть это единственный
  # способ уменьшить число, которое калькулятор показывает игроку, НЕ посчитав
  # ничего нового, и без автора, цитаты и довода им можно было бы гасить
  # неудобные записи одной строкой.
  #
  # ⚠ Словаря доводов (`bases:`) здесь не объявлено по той же причине, что
  # у фактов класса: у записи оружия своего фита нет, а проверяемый довод
  # `feat_description` стоит на описании фита.
  defp verify_not_a_gap!(name, %{} = decision) do
    NotAGap.verify!("siala_41/systems.json: the weapon #{name}", decision)
  end

  defp verify_not_a_gap!(_name, _decision), do: :ok

  defp weapon_type_bonus_weapon_id!(name, weapons) do
    id = atom(name)

    if weapons != %{} and not Map.has_key?(weapons, id) do
      raise "siala_41/systems.json: the weapon system names the weapon #{name}, " <>
              "which weapons.json does not carry"
    end

    id
  end

  # The group the second number of every row is stated for, found by the **page
  # title** both files cite — the same key and the same device
  # `racial_bonus_conditions/2` uses, so no group id is written down in either
  # the data of this system or the core.
  defp weapon_type_bonus_group!(application, class_groups) do
    case dig(application, ["sagra_variant", "class_group_page"]) do
      page when is_binary(page) ->
        group =
          Enum.find(class_groups, &(&1.name == page)) ||
            raise """
            siala_41/systems.json: bonus_application cites #{inspect(page)} as the group \
            the bigger number is for, and no class page says it belongs to it — the \
            variant would silently never be counted
            """

        group.id

      _unstated ->
        nil
    end
  end

  # Two copies of one number, guarded where the second copy lives — the device
  # `verify_racial_bonus_cap_agrees!/3` already uses. The page says «Бонус входит
  # в лимита атаки +20» inside the row itself, and `overrides.json` carries the
  # 20 the core actually clips at; the ceiling key is the kind's own name, which
  # is why a row claiming a ceiling for a shape that has none fails here.
  #
  # ⚠ Only where the ceiling exists at all, exactly like `verify_cap_sources!/4`:
  # a ruleset that states no ceiling clips nothing, and failing the build over a
  # disagreement with a number nobody wrote down would break it over a question
  # with no observable answer.
  def verify_weapon_type_bonus_caps!(nil, _caps), do: :ok

  def verify_weapon_type_bonus_caps!(layer, caps) do
    records = Enum.concat(Map.values(layer.by_group) ++ Map.values(layer.by_weapon))

    for %{counts_toward_cap: stated, kind: kind} <- records,
        is_integer(stated),
        applied = Map.get(caps, kind),
        is_integer(applied) do
      unless applied == stated do
        raise """
        the weapon system states that its #{kind} bonus counts towards a ceiling of \
        #{stated}, and stat_caps says #{applied}
        """
      end
    end

    :ok
  end

  # What is unknown about the weapon-type bonus as a corpus, as opposed to what is
  # unknown about one build's number. **One** statement now, and it is not about
  # numbers at all: a weapon the page gives a bonus to and the dictionary does not
  # carry («Вилы»). Not a hole in a number — no build can name that weapon at all
  # — but a hole in the answer: such a build cannot be expressed here.
  #
  # ⚠ Здесь первым стоял `{:missing_data, :weapon_type_bonus_progression}` —
  # та же дыра, что у расового бонуса, и то же чтение: бонус растёт с уровнем
  # персонажа, все числа названы для 40-го, функции роста не даёт ни одна
  # страница. **Снят 22.08.2026 решением Dan** (задача 3.81): «прогрессию делать
  # не будем, данный пробел можно закрыть» — продолжение решения Q2
  # от 15.08.2026, где добывание прогрессии было закрыто целиком («полноценный
  # билд всегда идет для 40 или 41 уровня… главное итог в конце»).
  #
  # Две формы ушли вместе не по симметрии, а потому что это буквально одна
  # система: `races.json` объявляет каждый расовый бонус тождественным бонусу
  # за тип оружия («Бонус идентичен бонусу от [[Владение клинковым оружием]]»),
  # и `max_at_level` у оружия стоит переносом с расового ровно по этой причине
  # (`systems.json` → `weapon_system`, пункт 2 заметки). Снять признание
  # у одной половины и оставить у другой значило бы сказать про одно правило
  # две разные вещи.
  #
  # 🔴 **Оговорка на КОНКРЕТНОМ билде остаётся:** `{:missing_data,
  # {:weapon_type_bonus_level, weapon}}` (`Rules.WeaponTypeBonus.gaps/3`)
  # приезжает каждому билду ниже 40-го с оружием в руках — бонус в игре есть,
  # величины не знает никто, и молчать про это нельзя. Снятая форма отвечала
  # на вопрос «полны ли правила у нас в данных», живая — на «что не посчитано
  # в этом числе»; закрыто решением только первое.
  def weapon_type_bonus_gaps(nil), do: []

  def weapon_type_bonus_gaps(layer) do
    for name <- Enum.sort(layer.unmatched),
        do: {:missing_data, {:weapon_type_bonus_weapon, name}}
  end

  defp ability_map(nil), do: %{}

  defp ability_map(map) do
    Map.new(map, fn {k, v} -> {Map.fetch!(@ability_keys, k), v} end)
  end

  defp keyword_ints(nil), do: nil
  defp keyword_ints(map), do: Map.new(map, fn {k, v} -> {atom(k), v} end)
end
