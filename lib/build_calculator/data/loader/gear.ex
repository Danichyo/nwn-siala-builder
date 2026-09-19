defmodule BuildCalculator.Data.Loader.Gear do
  @moduledoc """
  Вещи, оружие и правила хвата: что игрок вводит руками, справочник оружия
  и то, чем оружие можно держать.
  """

  import BuildCalculator.Data.Loader.Reading

  # ------------------------------------------------------------------- gear --

  # Not the armoury: the player types the totals their equipment gives, and the
  # core works out the cascade (CLAUDE.md §6). `+12 CON` is not "+12 CON", it is
  # +6 to the modifier, which is +6 HP on *every* level.
  # `version` — какой ruleset строится сейчас. Нужен ровно одному месту (`worn!/3`),
  # и там он не сравнивается ни с какой строкой из кода: версию, которой принадлежат
  # сиальские двойники общей ванильной секции, называет сама секция.
  def gear(ov, version) do
    ac_types = ov |> dig(["gear", "ac_types", "value"]) |> Kernel.||([]) |> Enum.map(&atom/1)

    %{
      ability_bonus_cap: dig(ov, ["gear", "ability_bonus_cap", "value"]),
      ac_types: ac_types,
      ac_type_names: dig(ov, ["gear", "ac_types", "ru"]) || %{},
      # Which AC type has a ceiling of its own, and which `stat_caps` key holds
      # it. Exactly one has one today (dodge, +20), and the pairing is **stated**
      # rather than derived from the type's name: a ceiling must not appear on a
      # type because somebody added a similarly named key next door. ⚠ It used to
      # live in `Rules.Gear` as a module attribute, which put the one game word
      # `dodge` inside the rules core; task 3.39 moved it here, where every other
      # AC type name already lives. Cross-checked against `Character.stat_caps/1`
      # (one module over since task 3.46, not further down).
      ac_type_ceilings: ac_type_ceilings!(ov, ac_types),
      # What happens to two bonuses of **one** type — four statements of
      # different provenance, which is why they are four fields and not one
      # (tasks 3.39 and 3.91; `gear.ac_types.same_type` in the file states all
      # four with their quotes).
      ac_same_type: ac_same_type!(ov, ac_types),
      # В какой из этих типов ложится свойство «AC Bonus», надетое в тот или
      # иной слот (задача 3.187). Нужно ровно одному читателю — своду
      # экипировки из игрового лога (`Rules.GearImport`), где предметов
      # несколько и тип у каждого свой; ручного ввода это не касается вовсе,
      # там тип называет игрок.
      item_slot_ac_types: item_slot_ac_types!(ov, ac_types),
      # No source names a ceiling on armour class, so there is none here.
      ac_cap: dig(ov, ["gear", "ac_cap", "value"]),
      # Which numbers a weapon in hand carries — `[:attack]` (task 3.5 part B,
      # narrowed by task 3.52). Two of them until 19.08.2026, because Dan named
      # them separately while listing what fills the +20 («attack bonus или
      # enchantment bonus оружия») and because an enhancement bonus also gives
      # damage. Damage is computed nowhere, so the second field was the same
      # arithmetic under a second name and the player saw no difference anywhere
      # (Dan: «надо нам от enchantment bonus просто отказаться»).
      #
      # ⚠ Still read from the data rather than fixed here, and still guarded:
      # a kind the file declares without a field in `Rules.Gear` fails the build
      # instead of counting as zero.
      weapon_bonus_kinds: weapon_bonus_kinds!(ov),
      # Что делать, когда у ОДНОГО предмета оказались оба его числа атаки
      # (`Attack Bonus` и `Enhancement Bonus`), а поле выше держит одно
      # (task 3.199). Нужно ровно своду надетого из игрового лога
      # (`Rules.GearImport`) — при ручном вводе игрок вписывает одно число сам,
      # и встретиться двум негде. Режим называет файл, как и у AC
      # (`ac_same_type.gear_vs_gear`); `nil` — «файл не сказал», и тогда свод
      # два числа не сводит вовсе и говорит об этом, а не берёт одно наугад.
      weapon_import_rule: weapon_import_rule!(ov),
      # Сколько взятий даёт один и тот же фит, объявленный с вещей несколько раз
      # (задача 3.204, `gear.feats.takes` в файле несёт оба слова Dan целиком).
      # `:per_declaration` — каждая запись есть взятие; `nil` — снапшот об этом
      # правиле молчит, и тогда ответ прежний, «предмет одалживает фит, а не
      # число его копий». Направление умолчания — в сторону занижения, а не
      # выдумывания: билд, собранный против такого снапшота, обязан открываться
      # тем же числом, каким открывался.
      feat_takes: feat_takes!(ov),
      # И КАКИЕ фиты так считаются (задача 3.210). `:without_choice` — те,
      # у кого выбора нет вовсе (`repeatable.choice == null`, прежнее и узкое
      # чтение); `:same_value` — плюс те, кому источник РАЗРЕШАЕТ повторить
      # одно и то же значение (`repeatable.distinct? == false`; сегодня такой
      # один — `Epic energy resistance`). Ни одного имени фита ни здесь, ни
      # в файле: «ровно на него» получается из данных о самом фите.
      # `nil` — ключа нет, действует узкое чтение, то есть занижение.
      feat_takes_applies_to: feat_takes_applies_to!(ov),
      # What the character **wears**, as an item with a size rather than as one
      # typed number (task 3.41): the type of armour and the size of shield. Two
      # numbers come off the choice — the item's base armour class, which always
      # stacks, and the ceiling it puts on the dexterity bonus to AC. Both are
      # vanilla and both are quoted in the file; which AC type each category
      # lands in is stated there too, so no type name reaches the rules core.
      worn: worn!(ov, ac_types, version)
    }
  end

  # Ванильное поле и его сиальский двойник — пара имён, названная ОДИН раз.
  # Больше нигде в коде префикса `siala_` нет: какой версии ruleset'а двойники
  # принадлежат, говорит сама секция (`@shard_layer_field`), а не литерал здесь.
  @max_dex "max_dex"
  @shard_max_dex "siala_max_dex"
  @weight_class "siala_weight_class"
  @weight_classes "siala_weight_classes"
  @shard_layer_field "siala_values_apply_to_ruleset"

  # `:unknown` — единственное слово, которое ядро придумывает само, и означает
  # оно «этот слой про класс не сказал». Класс с таким именем в данных сделал бы
  # «нет ответа» неотличимым от ответа (`Rules.Worn.weight_class`).
  @unknown_class "unknown"

  # Категории надетого и их предметы. Шесть проверок, и каждая закрывает свою
  # молчаливую поломку:
  #
  #   * категория обязана называть тип AC из того же списка, что предлагает поле
  #     ввода, — иначе база предмета попала бы в тип, которого нет, и исчезла;
  #   * предел ловкости может называть только категория, которая объявила
  #     `caps_dexterity` — таблица источника озаглавлена «Type of armor», щитов
  #     в ней нет вовсе, и щит, начавший резать ловкость, был бы выдуманным
  #     игровым правилом;
  #   * и наоборот: категория, объявившая `caps_dexterity`, обязана назвать
  #     предел у КАЖДОГО предмета — «поле отсутствует» и «предела нет» иначе
  #     выглядели бы одинаково, а это разные утверждения. `null` — законное
  #     значение и означает «без предела» (строка «нет / одежда»);
  #   * то же самое отдельно про сиальский двойник предела: назвал его один
  #     предмет — обязаны назвать все. Пропущенная строка читалась бы как «без
  #     предела», то есть ловкость в AC пошла бы целиком (задача 3.141);
  #   * штраф брони обязан назвать КАЖДЫЙ предмет, и он обязан быть штрафом
  #     (целое ≤ 0). У колонки источника пустых клеток нет ни у одной из
  #     двенадцати строк, поэтому «поля нет» здесь всегда ошибка, а не
  #     «неизвестно»; а положительное число под именем штрафа — это бонус,
  #     который молча поднял бы шесть навыков (задача 3.42);
  #   * класс веса предмета обязан быть одним из объявленных категорией
  #     (`weight_classes!/3`) — опечатка иначе читалась бы как «не средний»
  #     и молча вернула бы Рейнджеру бонусы, которых игра не даёт.
  defp worn!(ov, ac_types, version) do
    block = dig(ov, ["gear", "worn"]) || %{}
    shard? = shard_values?(block, version)

    for category <- block["categories"] || [] do
      id = atom(category["id"])
      ac_type = atom(category["ac_type"])
      caps? = category["caps_dexterity"] == true
      items = category["items"] || []
      classes = weight_classes!(id, category, items)

      if ac_types != [] and ac_type not in ac_types do
        raise "overrides.json: gear.worn category #{id} lands in AC type #{ac_type}, " <>
                "which is not one the player can enter (#{inspect(ac_types)})"
      end

      verify_all_or_none!(id, items, @shard_max_dex)

      %{
        id: id,
        ru: category["ru"],
        ac_type: ac_type,
        caps_dexterity?: caps?,
        # Занимает ли эта категория ВТОРУЮ РУКУ (задача 3.43). Свойство
        # категории, а не предмета: вторую руку занимает любой щит, какого бы
        # размера он ни был. Что именно занимает ОБЕ руки — не здесь: это хват
        # оружия, он в `weapons.json` → `_grip.grips_using_both_hands`, и для
        # малой расы пересчитывается по размерам (`Rules.Wield`).
        occupies_off_hand?: category["occupies_off_hand"] == true,
        items: for(item <- items, do: worn_item!(id, item, caps?, shard?, classes))
      }
    end
  end

  # Достаются ли сиальские двойники ЭТОМУ ruleset'у. Версию называет сама
  # секция, а не код: `gear.worn` лежит в `@vanilla_sections` и раздаётся обоим
  # ruleset'ам байт в байт, поэтому «чьё это число» обязано быть свойством
  # данных — иначе сиальский предел ловкости уехал бы в ваниль, у которой свой
  # источник (Fandom «Maximum dexterity bonus») и своя, никем не добытая
  # граница класса брони.
  #
  # 🔴 Двойники БЕЗ объявленной версии роняют сборку: это ровно тот дефект,
  # который в этом проекте ловили четыре раза за трое суток, — правило разобрано,
  # число лежит со `status: verified`, а соединения с расчётом нет, и молчит оно
  # так же, как молчала бы опечатка.
  defp shard_values?(block, version) do
    declared = block[@shard_layer_field]

    cond do
      is_binary(declared) ->
        declared == version

      shard_values_stated?(block) ->
        raise "overrides.json: gear.worn states #{@shard_max_dex}/#{@weight_class} on its items " <>
                "and no `#{@shard_layer_field}` — values no ruleset will ever read look exactly " <>
                "like values that are being read"

      true ->
        false
    end
  end

  defp shard_values_stated?(block) do
    Enum.any?(block["categories"] || [], fn category ->
      Enum.any?(
        category["items"] || [],
        &(Map.has_key?(&1, @shard_max_dex) or Map.has_key?(&1, @weight_class))
      )
    end)
  end

  # Закрытый словарь классов веса — и он принадлежит КАТЕГОРИИ, а не ядру: какие
  # слова бывают, сказала игра устами замера (`GAME_CHECKS.md` AH1), а не эта
  # функция. `nil` означает «категория классов не различает» (щиты — про них
  # условие Рейнджера не говорит вовсе).
  defp weight_classes!(category, raw, items) do
    declared = raw[@weight_classes]
    stated = for item <- items, Map.has_key?(item, @weight_class), do: item[@weight_class]

    cond do
      is_nil(declared) and stated != [] ->
        raise "overrides.json: gear.worn category #{category} states #{@weight_class} on its " <>
                "items and declares no `#{@weight_classes}` — a class checked against nothing " <>
                "is a class a typo passes"

      is_nil(declared) ->
        nil

      not (is_list(declared) and declared != [] and Enum.all?(declared, &is_binary/1)) ->
        raise "overrides.json: gear.worn category #{category} states #{@weight_classes} " <>
                "#{inspect(declared)} — the vocabulary is a non-empty list of names"

      @unknown_class in declared ->
        raise "overrides.json: gear.worn category #{category} declares a weight class named " <>
                "#{inspect(@unknown_class)}, which is the one word the core keeps for «this " <>
                "layer did not say» — an answer and the absence of one would stop being " <>
                "distinguishable"

      length(stated) != length(items) ->
        raise "overrides.json: gear.worn category #{category} states #{@weight_class} on " <>
                "#{length(stated)} of its #{length(items)} items — a row without one prints a " <>
                "caveat that reads like a hole in the data rather than an unstated row"

      true ->
        case Enum.reject(stated, &(&1 in declared)) do
          [] ->
            declared

          strays ->
            raise "overrides.json: gear.worn category #{category} states weight classes " <>
                    "#{inspect(strays)}, which #{@weight_classes} does not declare " <>
                    "(#{inspect(declared)}) — «medum» would read as «not medium» and hand the " <>
                    "benefits back silently"
        end
    end
  end

  # Поле, которое называет часть предметов категории, обязано называть все: у
  # пропущенной строки нет своего значения, есть только чужое умолчание.
  defp verify_all_or_none!(category, items, field) do
    stated = for item <- items, Map.has_key?(item, field), do: item

    unless stated == [] or length(stated) == length(items) do
      raise "overrides.json: gear.worn category #{category} states #{field} on " <>
              "#{length(stated)} of its #{length(items)} items — half a column is worse than " <>
              "none of it, because the rows without it fall back to another source without " <>
              "saying so"
    end

    :ok
  end

  defp worn_item!(category, item, caps_dexterity?, shard?, classes) do
    id = atom(item["id"])
    stated? = Map.has_key?(item, @max_dex)
    shard_stated? = Map.has_key?(item, @shard_max_dex)

    cond do
      caps_dexterity? and not stated? ->
        raise "overrides.json: gear.worn item #{category}/#{id} states no max_dex, and its " <>
                "category caps dexterity — «нет поля» и «без предела» не одно и то же " <>
                "(пиши null)"

      not caps_dexterity? and (stated? or shard_stated?) ->
        raise "overrides.json: gear.worn item #{category}/#{id} states max_dex, and its " <>
                "category does not cap dexterity — the source's table is «Type of armor» " <>
                "and names no shields"

      true ->
        %{
          id: id,
          category: category,
          name: item["en"],
          base_ac: item["base_ac"] || 0,
          # ОДНО поле у предмета и две записи в файле: ruleset получает предел
          # СВОЕГО слоя и ничего не знает о существовании второго. Сиальский
          # двойник берётся, только если он и объявлен, и адресован этой версии;
          # молчание шарда означает ванильное число, как и всюду в этом файле.
          max_dex: if(shard? and shard_stated?, do: item[@shard_max_dex], else: item[@max_dex]),
          # Класс веса — `:unknown` везде, где слой про него не сказал, и это
          # НЕ то же самое, что `:none` («типа нет вовсе», строка «нет / одежда»).
          # У ванили он неизвестен у всех девяти доспехов: границу измерили
          # на Сиале, а где та же линия проходит в ванильных правилах, не
          # выяснял никто, и дорисовать её по аналогии запрещено — на Сиале
          # кольчужная рубаха средняя, а в D&D 3.5 лёгкая.
          weight_class: weight_class(item, shard?, classes),
          armor_check_penalty: armor_check_penalty!(category, id, item),
          # Какое ИМЕННОЕ поле расы запрещает этот предмет — `nil` у тех, кого
          # не запрещает никто. Указатель по имени, а не значение: раса говорит
          # «Cannot use tower shields» о себе, предмет говорит «я тот самый», и
          # ядро сравнивает два атома, не зная ни расы, ни щита. Ключ, которого
          # не объявляет ни одна раса, роняет сборку (`verify_worn_restrictions!/2`).
          race_restriction: atom_or_nil(item["race_restriction"])
        }
    end
  end

  defp weight_class(item, true = _shard?, classes) when is_list(classes),
    do: atom(item[@weight_class])

  defp weight_class(_item, _shard?, _classes), do: :unknown

  # Указатель предмета на поле расы обязан во что-то указывать.
  #
  # ⚠ Направление проверки — только это: раса, у которой запрет стоит, а предмета
  # под него нет, законна (ванильный снапшот без «Вещей» — ровно такой), а вот
  # предмет, запрещённый полем, которого никто не объявляет, запрещён никому —
  # то есть разрешён всем, молча.
  def verify_worn_restrictions!(worn, races) do
    declared =
      for {_id, race} <- races, key <- race.restrictions, into: MapSet.new(), do: key

    for category <- worn,
        item <- category.items,
        key = item.race_restriction,
        not MapSet.member?(declared, key) do
      raise """
      overrides.json: gear.worn item #{category.id}/#{item.id} says it is refused by \
      `#{key}`, and no race in this ruleset declares such a field (they declare \
      #{inspect(Enum.sort(declared))}). A restriction nobody claims refuses nobody, which \
      reads exactly like «this item is fine for everyone».
      """
    end

    :ok
  end

  # ⚠ Никакого `|| 0`: ноль здесь — законное значение трёх строк источника
  # («none»), и подставить его вместо отсутствующего поля значило бы стереть
  # разницу между «штрафа нет» и «никто не сказал». Отсутствие роняет сборку.
  defp armor_check_penalty!(category, id, item) do
    case Map.fetch(item, "armor_check_penalty") do
      {:ok, penalty} when is_integer(penalty) and penalty <= 0 ->
        penalty

      {:ok, other} ->
        raise "overrides.json: gear.worn item #{category}/#{id} states armor_check_penalty " <>
                "#{inspect(other)} — a penalty is an integer at or below zero; a positive " <>
                "number under that name is a bonus to six skills nobody wrote down"

      :error ->
        raise "overrides.json: gear.worn item #{category}/#{id} states no armor_check_penalty " <>
                "— the source's column has no empty cell in any of its twelve rows, so a " <>
                "missing field is an omission and not «no penalty» (пиши 0)"
    end
  end

  # A ceiling may only be pinned to a type the player can actually enter — a
  # pairing naming anything else is a ceiling that never fires, which is the
  # silent kind of wrong this file exists to prevent.
  defp ac_type_ceilings!(ov, ac_types) do
    for {type, stat} <- dig(ov, ["gear", "ac_types", "ceilings", "value"]) || %{}, into: %{} do
      type = atom(type)

      if ac_types != [] and type not in ac_types do
        raise "overrides.json: gear.ac_types.ceilings pins a ceiling on AC type #{type}, " <>
                "which is not one the player can enter (#{inspect(ac_types)})"
      end

      {type, atom(stat)}
    end
  end

  # Слоты предмета и тип класса брони, в который попадает его «AC Bonus».
  # Ванильное правило с цитатой (`fandom:Armor class`, revid 71718), лежит
  # в общей секции `gear` и достаётся обоим ruleset'ам.
  #
  # Четыре проверки, и каждая закрывает свою молчаливую поломку:
  #
  #   * тип обязан быть одним из тех, что предлагает поле ввода, — иначе число
  #     уехало бы в тип, которого нет, и исчезло из суммы;
  #   * то же отдельно про альтернативы у слота без ответа: они печатаются
  #     игроку («щит → shield, иначе deflection»), и выдуманный тип в этой
  #     фразе был бы выдуманным игровым правилом;
  #   * слот БЕЗ типа обязан назвать альтернативы, а слот С типом — не называть
  #     их. Иначе «источник не решает, какой из двух» и «мы не дочитали
  #     источник» выглядели бы одинаково, а это разные утверждения;
  #   * повторяющийся `id` или повторяющийся токен лога — опечатка, которая
  #     молча выкинула бы один из двух слотов (и вместе с ним его число);
  #   * рука (`hand`, задача 3.199) обязана быть одной из тех, что у модели
  #     есть (`Rules.Gear.hands/0`), названа не больше одного раза и — если
  #     названа хоть одна — названы все. Половинный список молча потерял бы
  #     число второй руки, а выдуманное имя руки не совпало бы ни с чем
  #     и не сработало бы никогда.
  defp item_slot_ac_types!(ov, ac_types) do
    slots = dig(ov, ["gear", "item_slot_ac_types", "slots"]) || []
    raw_categories = dig(ov, ["gear", "worn", "categories"]) || []
    worn_categories = for category <- raw_categories, do: atom(category["id"])

    table =
      for slot <- slots do
        id = atom(slot["id"])
        type = slot["ac_type"] && atom(slot["ac_type"])
        alternatives = for name <- slot["ac_type_alternatives"] || [], do: atom(name)
        by_category = ac_type_by_worn_category!(slot, id, type, ac_types, worn_categories)
        by_base_type = ac_type_by_base_type!(slot, id, type, ac_types, alternatives)
        otherwise = ac_type_otherwise!(slot, id, type, ac_types)
        worn_by_base_ac = worn_category_by_base_ac!(slot, id, raw_categories)

        for named <- [type | alternatives], not is_nil(named), ac_types != [] do
          unless named in ac_types do
            raise "overrides.json: gear.item_slot_ac_types slot #{id} names AC type " <>
                    "#{named}, which is not one the player can enter (#{inspect(ac_types)})"
          end
        end

        case {type, alternatives} do
          {nil, []} ->
            raise "overrides.json: gear.item_slot_ac_types slot #{id} has no AC type and " <>
                    "names no alternatives — «источник не решает» and «мы не дочитали» " <>
                    "would look the same"

          {nil, _} ->
            :ok

          {_, []} ->
            :ok

          {_, _} ->
            raise "overrides.json: gear.item_slot_ac_types slot #{id} names AC type #{type} " <>
                    "AND alternatives #{inspect(alternatives)} — that is two answers to one " <>
                    "question"
        end

        %{
          id: id,
          log: slot["log"],
          ac_type: type,
          ac_type_alternatives: alternatives,
          # Чем разрешается слот без своего типа, когда лог называет БАЗОВЫЙ
          # ТИП предмета (второе поколение `.билд+`, задача 3.206): категория
          # надетого → тип AC (щит → щитовой) и тип для любого другого
          # опознанного предмета (`deflection`). Обе записи — только у слота
          # с `ac_type: null`, и обе пустые у слота, который источник решает
          # сам; читает их только свод лога (`Rules.GearImport`).
          ac_type_by_worn_category: by_category,
          # Напечатанный БАЗОВЫЙ ТИП предмета → тип AC (задача 3.213, третье
          # поколение `.билд+`): наручи дают `armor`, перчатки `deflection`,
          # и обе записи стоят с дословными цитатами той же страницы. Ключ —
          # имя, как печатает сервер; строка `baseitems.2da` лежит рядом
          # распиской и в ruleset не едет (у перчаток имя и метка хака
          # расходятся: `Gauntlet` против `gloves`).
          ac_type_by_base_type: by_base_type,
          ac_type_otherwise: otherwise,
          # Какую категорию `gear.worn` называет число `[BaseAC:n]` этого
          # слота — `nil` у десяти слотов из одиннадцати. Читает свод лога:
          # у доспеха сервер печатает не тип, а БАЗУ, и строку по ней ищет
          # `Rules.GearImport` в той категории, которую называет здесь файл.
          worn_category_by_base_ac: worn_by_base_ac,
          # Какой РУКЕ модели соответствует слот, и `nil` у девяти слотов
          # из одиннадцати. Читает свод надетого из лога (`Rules.GearImport`):
          # ему надо знать, в какую руку легло число атаки предмета, а имя
          # токена движка (`RIGHTHAND`) этого не говорит — говорит `wiki_slot`
          # той же строки («main hand slot»).
          hand: slot["hand"] && atom(slot["hand"])
        }
      end

    verify_unique!(table, & &1.id, "id")
    verify_unique!(table, & &1.log, "log token")
    verify_hands!(table)

    table
  end

  # `ac_type_by_worn_category` — категория `gear.worn` → тип AC, у слота, чей
  # тип источник не решает (`ac_type: null`). Категория обязана существовать,
  # тип — быть вводимым; у слота с собственным типом запись — второй ответ
  # на один вопрос, и сборка падает.
  defp ac_type_by_worn_category!(slot, id, type, ac_types, worn_categories) do
    pairs = slot["ac_type_by_worn_category"] || %{}

    if pairs != %{} and not is_nil(type) do
      raise "overrides.json: gear.item_slot_ac_types slot #{id} names AC type #{type} " <>
              "AND ac_type_by_worn_category — that is two answers to one question"
    end

    for {category, ac_type} <- pairs, into: %{} do
      category = atom(category)
      ac_type = atom(ac_type)

      unless category in worn_categories do
        raise "overrides.json: gear.item_slot_ac_types slot #{id} maps worn category " <>
                "#{category}, which gear.worn does not declare (#{inspect(worn_categories)})"
      end

      unless ac_types == [] or ac_type in ac_types do
        raise "overrides.json: gear.item_slot_ac_types slot #{id} maps category #{category} " <>
                "to AC type #{ac_type}, which is not one the player can enter"
      end

      {category, ac_type}
    end
  end

  # `ac_type_by_base_type` — НАПЕЧАТАННЫЙ базовый тип предмета → тип AC,
  # у слота, чей тип источник не решает (задача 3.213, `ARMS`: наручи или
  # перчатки). Пять сторожей, и каждый закрывает свою молчаливую поломку:
  #
  #   * запись у слота с собственным типом — второй ответ на один вопрос;
  #   * имя базового типа обязано быть непустой строкой: пустое не совпало бы
  #     ни с чем и правило не сработало бы никогда;
  #   * повторённое имя выкинуло бы одну из двух записей молча;
  #   * тип обязан быть вводимым игроком — иначе число уехало бы в тип,
  #     которого нет, и исчезло из суммы;
  #   * 🔴 и тип обязан стоять среди АЛЬТЕРНАТИВ этого слота: альтернативы
  #     печатаются игроку («наручи → броня, перчатки → отклонение»), и ответ,
  #     которого нет в этой фразе, означал бы, что мы считаем одно, а называем
  #     другое.
  defp ac_type_by_base_type!(slot, id, type, ac_types, alternatives) do
    rows = slot["ac_type_by_base_type"] || []

    if rows != [] and not is_nil(type) do
      raise "overrides.json: gear.item_slot_ac_types slot #{id} names AC type #{type} " <>
              "AND ac_type_by_base_type — that is two answers to one question"
    end

    table =
      for row <- rows, into: %{} do
        name = row["base_type"]
        ac_type = atom(row["ac_type"])

        unless is_binary(name) and String.trim(name) != "" do
          raise "overrides.json: gear.item_slot_ac_types slot #{id} maps base type " <>
                  "#{inspect(name)} — a nameless base type matches nothing the log ever " <>
                  "prints, so the rule would never fire"
        end

        unless ac_types == [] or ac_type in ac_types do
          raise "overrides.json: gear.item_slot_ac_types slot #{id} maps base type " <>
                  "#{name} to AC type #{ac_type}, which is not one the player can enter"
        end

        unless alternatives == [] or ac_type in alternatives do
          raise "overrides.json: gear.item_slot_ac_types slot #{id} maps base type #{name} " <>
                  "to AC type #{ac_type}, and the slot names alternatives " <>
                  "#{inspect(alternatives)} — the player is told one answer and the number " <>
                  "goes into another"
        end

        {normalize_base_type(name), ac_type}
      end

    if map_size(table) != length(rows) do
      raise "overrides.json: gear.item_slot_ac_types slot #{id} maps the same base type " <>
              "twice — one of the two rows would be lost silently"
    end

    table
  end

  # Имя базового типа сверяется так же, как его сверяет свод лога
  # (`Rules.GearImport.normalize_name/1`): регистр и лишние пробелы печати
  # не должны решать, узнали мы предмет или нет.
  defp normalize_base_type(name),
    do: name |> String.trim() |> String.downcase() |> String.replace(~r/\s+/u, " ")

  # `worn_category_by_base_ac` — какую категорию `gear.worn` называет число
  # `[BaseAC:n]`, напечатанное у предмета этого слота (задача 3.213). Два
  # сторожа, оба про молчаливую поломку:
  #
  #   * категория обязана существовать — иначе число указывало бы в пустоту
  #     и доспех молча оставался бы ненадетым;
  #   * 🔴 внутри категории `base_ac` обязан быть УНИКАЛЕН: число указывает
  #     на строку, и две строки с одной базой сделали бы выбор между ними
  #     нашей выдумкой (девять доспехов несут 0…8 без повторов).
  defp worn_category_by_base_ac!(slot, id, raw_categories) do
    case slot["worn_category_by_base_ac"] do
      nil ->
        nil

      named ->
        category = atom(named)

        raw =
          Enum.find(raw_categories, &(atom(&1["id"]) == category)) ||
            raise "overrides.json: gear.item_slot_ac_types slot #{id} sends its [BaseAC:n] " <>
                    "to worn category #{category}, which gear.worn does not declare — a number " <>
                    "pointing at nothing leaves the armour unworn without a word"

        bases = for item <- raw["items"] || [], do: item["base_ac"] || 0

        if bases != Enum.uniq(bases) do
          raise "overrides.json: gear.worn category #{category} repeats base_ac " <>
                  "#{inspect(bases -- Enum.uniq(bases))}, and gear.item_slot_ac_types slot " <>
                  "#{id} identifies its armour BY that number — two rows sharing one base " <>
                  "would make the choice between them ours to invent"
        end

        category
    end
  end

  # `ac_type_otherwise` — тип AC для опознанного предмета второй руки, который
  # ни в одну названную категорию не попал (оружие, факел): «deflection bonus —
  # provided by all other items». Те же два сторожа, что у пары выше.
  defp ac_type_otherwise!(slot, id, type, ac_types) do
    case slot["ac_type_otherwise"] do
      nil ->
        nil

      _named when not is_nil(type) ->
        raise "overrides.json: gear.item_slot_ac_types slot #{id} names AC type #{type} " <>
                "AND ac_type_otherwise — that is two answers to one question"

      named ->
        ac_type = atom(named)

        unless ac_types == [] or ac_type in ac_types do
          raise "overrides.json: gear.item_slot_ac_types slot #{id} names ac_type_otherwise " <>
                  "#{ac_type}, which is not one the player can enter"
        end

        ac_type
    end
  end

  # Руки: названы либо все, либо ни одной, и каждая не больше раза.
  #
  # ⚠ «Ни одной» — законное состояние, а не пропуск: слоты предмета нужны
  # только своду надетого из лога, и снапшот без этого раздела вовсе просто
  # не сводит экипировку. А вот НАЗВАННАЯ половина — всегда ошибка: число
  # второй руки исчезло бы молча, и отличить это от пустой руки было бы нечем.
  defp verify_hands!(table) do
    named = for row <- table, not is_nil(row.hand), do: row.hand
    hands = BuildCalculator.Rules.Gear.hands()

    case {named, Enum.uniq(named)} do
      {[], _} ->
        :ok

      {named, unique} when named != unique ->
        raise "overrides.json: gear.item_slot_ac_types names the same hand twice " <>
                "(#{inspect(named)}) — one of the two slots would be lost silently"

      {named, _} ->
        unless Enum.sort(named) == Enum.sort(hands) do
          raise "overrides.json: gear.item_slot_ac_types names hands #{inspect(named)}, " <>
                  "and the model has #{inspect(hands)} — a hand named nowhere is a weapon " <>
                  "number dropped without a word, and one named wrongly never fires"
        end

        :ok
    end
  end

  defp verify_unique!(table, read, what) do
    duplicates =
      table
      |> Enum.frequencies_by(read)
      |> Enum.filter(&(elem(&1, 1) > 1))
      |> Enum.map(&elem(&1, 0))

    if duplicates != [] do
      raise "overrides.json: gear.item_slot_ac_types repeats #{what} #{inspect(duplicates)}"
    end

    :ok
  end

  # And the other half of the same check, run once `stat_caps` is built: a
  # pairing pointing at a ceiling nobody stated would leave the type uncapped in
  # silence, which reads exactly like "this type has no ceiling".
  def verify_ac_type_ceilings!(gear, caps) do
    Enum.each(gear.ac_type_ceilings, fn {type, stat} ->
      unless Map.has_key?(caps, stat) do
        raise "overrides.json: gear.ac_types.ceilings sends AC type #{type} to " <>
                "stat_caps.#{stat}, and no such ceiling is stated"
      end
    end)

    :ok
  end

  # Modes two bonuses of one type can meet in. Declared in the data because the
  # rule is the shard's, not ours: «обычно не стакаются АЦ с вещей и баффов, там
  # берется максимальный. АЦ с фитов всегда стакаются все, ну dodge АЦ еще
  # стакается до капа в 20» (Dan, 25.08.2026).
  #
  # ⚠ That sentence **narrows** the one that stood here before it («никакое АЦ
  # не складывается, когда дело касается вещей», 16.08.2026): the wide reading
  # made the build's own feats compete with the number the player typed, and the
  # narrow one says what the wide one was about — gear and buffs meeting each
  # other, of which the model holds neither (one typed number per type, no buffs
  # at all).
  @ac_same_type_modes %{"sum" => :sum, "max" => :max}

  # ⚠ The mode the core actually implements for the build's own bonuses meeting
  # each other. `Rules.ArmorClass`'s `own_by_type/1` sums them, which is what Dan
  # measured on 16.08.2026 (`GAME_CHECKS.md` E5 — `Draconic armor` beside `Armor
  # skin`, +2 exactly). The field is declared beside its opposite because the
  # opposite is what the shard's page says about the *other* pairing, and the two
  # are one sentence apart; but a file switching this one to `max` would change
  # no number at all, so it raises rather than passing through.
  @ac_own_vs_own_implemented :sum

  defp ac_same_type!(ov, ac_types) do
    declared = dig(ov, ["gear", "ac_types", "same_type"]) || %{}
    own = ac_same_type_mode!(declared, "own_vs_own")

    unless own == @ac_own_vs_own_implemented do
      raise "overrides.json: gear.ac_types.same_type.own_vs_own is #{own}, and the rules " <>
              "core only implements #{@ac_own_vs_own_implemented} there " <>
              "(Rules.ArmorClass's own_by_type/1) — the setting would change nothing"
    end

    %{
      own: own,
      gear: ac_same_type_mode!(declared, "own_vs_gear"),
      # Третья пара, и она про ДВА ПРЕДМЕТА одного типа (задача 3.187). Нужна
      # ровно своду экипировки из игрового лога: при ручном вводе игрок даёт
      # по одному числу на тип, и предметам негде встретиться. Читается так же,
      # как остальные две, — режим называет файл, а не код.
      gear_vs_gear: ac_same_type_mode!(declared, "gear_vs_gear"),
      gear_by_kind: ac_same_type_by_kind!(declared),
      cumulative: ac_cumulative_types!(declared, ac_types)
    }
  end

  # ⚠ `:sum` when the file says nothing, and that default is not a reading of the
  # game: a ruleset with no `gear` section has no AC types either
  # (`ac_types: []`), so nothing the player types is counted and there is nothing
  # for a rule to decide. An unknown mode raises rather than falling back —
  # a typo silently turning into "add everything" is the one outcome that would
  # change a number without anybody noticing.
  defp ac_same_type_mode!(declared, key) do
    case Map.fetch(declared, key) do
      :error -> :sum
      {:ok, name} -> ac_mode!(name, key)
    end
  end

  defp ac_mode!(name, where) do
    Map.get(@ac_same_type_modes, name) ||
      raise "overrides.json: gear.ac_types.same_type.#{where} is #{inspect(name)}; expected " <>
              "one of #{inspect(Map.keys(@ac_same_type_modes))}"
  end

  # Which **kinds** of the build's own bonus answer the question differently from
  # `own_vs_gear` (task 3.91). Keyed by the shard bonus shape — `shield_ac` — and
  # deliberately not by the AC type and not by the kind of source:
  #
  #   * by AC type would make a shield-typed **feat** compete too, and «АЦ с
  #     фитов всегда стакаются все» (Dan, 25.08.2026);
  #   * by kind of source would put `Divine grace` and `Sacred defense` on one
  #     side of a rule that treats them differently — the mistake CLAUDE.md §9
  #     records about the save ceiling, made once already.
  #
  # 🔴 The rule this replaces was the same mistake in the same place: «не
  # складывается» came off the «Расы» page, which says it about the Gnome's
  # racial shield bonus and nothing else, and we spread it over every bonus the
  # build earns. It cost up to 8 points of armour class on a Red Dragon
  # Disciple, silently and in the direction nobody complains about.
  #
  # A shape that lands nowhere near armour class fails the build rather than
  # sitting there as a rule that never fires — the list comes from
  # `Loader.Races`, which is where the one table of AC-carrying shapes lives.
  defp ac_same_type_by_kind!(declared) do
    known = BuildCalculator.Data.Loader.Races.shard_bonus_ac_kinds()

    for {kind, name} <- Map.get(declared, "own_vs_gear_by_kind") || %{}, into: %{} do
      unless kind in known do
        raise "overrides.json: gear.ac_types.same_type.own_vs_gear_by_kind names " <>
                "#{inspect(kind)}, and no shard bonus of that shape lands in armour class " <>
                "at all (#{inspect(known)}) — the mode would never fire"
      end

      {atom(kind), ac_mode!(name, "own_vs_gear_by_kind.#{kind}")}
    end
  end

  defp ac_cumulative_types!(declared, ac_types) do
    for name <- Map.get(declared, "cumulative_types") || [] do
      type = atom(name)

      if ac_types != [] and type not in ac_types do
        raise "overrides.json: gear.ac_types.same_type.cumulative_types names #{type}, " <>
                "which is not one the player can enter (#{inspect(ac_types)})"
      end

      type
    end
  end

  # ⚠ Каждый объявленный вид числа обязан иметь поле в `Rules.Gear`, и это
  # спрашивается У ЯДРА (`Gear.weapon_bonus_field/2`), а не перечисляется здесь
  # второй копией. Объявленное в данных число без поля молча считалось бы нулём —
  # ровно та поломка, от которой заведена вся разметка прибавок.
  #
  # ⚠ Спрашивается по КАЖДОЙ руке (задача 3.132), и список рук тоже приходит
  # из ядра: вид, у которого поле есть только у главной руки, во второй руке
  # молча считался бы нулём — та же поломка, просто на одну руку позже.
  defp weapon_bonus_kinds!(ov) do
    kinds = for name <- dig(ov, ["gear", "weapon", "bonus_fields", "value"]) || [], do: atom(name)

    unknown =
      for kind <- kinds,
          hand <- BuildCalculator.Rules.Gear.hands(),
          is_nil(BuildCalculator.Rules.Gear.weapon_bonus_field(kind, hand)),
          uniq: true,
          do: {kind, hand}

    unless unknown == [] do
      raise "overrides.json: gear.weapon.bonus_fields names #{inspect(unknown)}, and " <>
              "BuildCalculator.Rules.Gear has no field for them — the number would count as zero"
    end

    kinds
  end

  # Единственный режим, который ядро умеет, — максимум (слово Dan 12.09.2026,
  # `gear.weapon.import_rule` в файле несёт цитату целиком). Словарь из одного
  # значения, а не `String.to_atom/1`: «sum» в этом ключе подняло бы бонус
  # атаки у каждого импортированного билда с таким предметом, и увидеть это
  # можно было бы только сверкой с игрой — значит сборка обязана упасть, а не
  # молча посчитать одно число дважды под двумя именами.
  @weapon_import_rules %{"max" => :max}

  defp weapon_import_rule!(ov) do
    case dig(ov, ["gear", "weapon", "import_rule", "value"]) do
      nil ->
        nil

      name ->
        Map.get(@weapon_import_rules, name) ||
          raise "overrides.json: gear.weapon.import_rule is #{inspect(name)}; the rules core " <>
                  "implements only #{inspect(Map.keys(@weapon_import_rules))}"
    end
  end

  # Режим счёта взятий фита с вещей. Словарь из одного значения, как и у
  # `import_rule` выше, и по той же причине: незнакомое слово в этом ключе
  # означало бы «считаем как-то иначе», а увидеть это можно было бы только
  # сверкой с игрой — значит сборка обязана упасть, а не выбрать режим наугад.
  @feat_takes_modes %{"per_declaration" => :per_declaration}

  defp feat_takes!(ov) do
    case dig(ov, ["gear", "feats", "takes", "value"]) do
      nil ->
        nil

      name ->
        Map.get(@feat_takes_modes, name) ||
          raise "overrides.json: gear.feats.takes is #{inspect(name)}; the rules core " <>
                  "implements only #{inspect(Map.keys(@feat_takes_modes))}"
    end
  end

  # Каким фитам режим выше достаётся (задача 3.210). Тот же приём и та же
  # причина, что у `feat_takes!/1`: два слова, закрытый словарь, незнакомое
  # роняет сборку.
  #
  # 🔴 Умолчание — УЗКОЕ чтение, а не широкое, и это направление выбрано
  # сознательно: снапшот, который про расширение молчит, обязан считать так,
  # как считал до 18.09.2026 (одно взятие у фита с выбором). Занижение видно
  # игроку в числе, а молчаливое расширение — нет.
  @feat_takes_scopes %{
    "repeatable_without_choice" => :without_choice,
    "repeatable_with_same_value" => :same_value
  }

  defp feat_takes_applies_to!(ov) do
    case dig(ov, ["gear", "feats", "takes", "applies_to", "value"]) do
      nil ->
        nil

      name ->
        Map.get(@feat_takes_scopes, name) ||
          raise "overrides.json: gear.feats.takes.applies_to is #{inspect(name)}; the rules " <>
                  "core implements only #{inspect(Map.keys(@feat_takes_scopes))}"
    end
  end

  # ---------------------------------------------------------------- weapons --

  # The weapon dictionary as the **rules** need it, beside the choice domain the
  # same file already feeds (`choice_domains/3` reads it as a values dictionary
  # for `Weapon focus` and its family, task 3.5 part A).
  #
  # ⚠ Two roles, one set of ids, and that is a requirement rather than a
  # convenience: the id `Weapon focus (Scimitar)` was taken with and the id of the
  # weapon in the character's hands have to be the same string, or the feat and
  # the item cannot be matched at all (task 3.5 part B).
  #
  # What the core needs and the choice domain cannot carry: whether the weapon is
  # an item a character can hold at all, and which proficiency it asks for. The
  # domain's `flags` are booleans only (`entry_flags/1`), and the proficiency
  # group is a string.
  #
  # ## Проверка владения — три разных ответа, а не два
  #
  # Dan 10.08.2026: «можно в вещах не предлагать выбрать оружие, если нет фитов
  # „владение …“. Если в билде есть владение клинковым, то мы все мечи и кинжалы
  # … добавляем». Значит у каждого оружия ровно один из трёх ответов:
  #
  #   * `:none_needed` — владения не требует вовсе. Полноценное шестое значение
  #     категории, а не примечание: у волшебника без единого фита владения список
  #     иначе оказался бы **пуст**, а он в игре бегает с посохом (замер Dan);
  #   * `{:feat, id}` — требует названный фит владения;
  #   * `:unread` — требования никто не написал. Дубину Сиала не относит ни к
  #     одной из пяти своих категорий, и это НЕ то же самое, что «владения не
  #     требует» (`Rules.GearWeapon` предлагает такое оружие и говорит вслух, что
  #     требование не прочитано).
  #
  # ⚠ `:unread` приходит и вторым путём — у ruleset'а, в котором названного фита
  # нет вовсе. Ванильный именно такой: пять сиальских фитов владения живут в
  # слое шарда, а ванильная система владения на Сиале выключена целиком
  # (`GAME_CHECKS.md` H5). Оба пути ведут к одному ответу сознательно: ядро их не
  # различает, и делать вид, что различает, значило бы обещать проверку, которой
  # нет.
  def weapons(raw, ov, feats) do
    entries = weapon_entries(raw)
    groups = weapon_groups(raw)
    not_wieldable = not_wieldable_weapons!(ov, entries)
    absent = absent_weapons!(ov, entries)

    verify_proficiency_feats!(groups, feats)

    Map.new(entries, fn entry ->
      id = atom(entry["id"])
      group = atom_or_nil(entry["siala_proficiency_group"])

      {id,
       %{
         id: id,
         name: entry["name"],
         wieldable?: id not in not_wieldable,
         # На шарде такого предмета нет вовсе — не «не предмет», а «отсутствует».
         # У ванильного ruleset'а список пуст, и лэнс там остаётся.
         on_shard?: not MapSet.member?(absent, id),
         # ⚠ Дальнобойность — единственное свойство самого оружия, которое читает
         # ядро правил (`Rules.Attack`: `Zen archery` меняет характеристику атаки
         # на мудрость только «when firing ranged weapons»). Берётся полем
         # справочника, а не выводится из имени или категории: собственная
         # таксономия оружия здесь была бы такой же выдумкой, как у групп
         # владения. Метательное входит сюда ПО ИСТОЧНИКУ, а не по нашему
         # толкованию: «Ranged weapons either can be missile weapons … or can be
         # throwing weapons» (`fandom:Ranged weapon`).
         ranged?: entry["ranged"] == true,
         # ⚠ Метательное — не то же самое, что дальнобойное: лук дальнобойный
         # и НЕ метательный, дротик и то и другое. Различие читает
         # `Rules.Wield`: у метательного «двуручное» из колонки Сиалы вторую
         # руку не занимает (замер Dan 16.08.2026, кейс R5).
         thrown?: entry["thrown"] == true,
         # ⚠ И третье свойство, которое читает ядро: двустороннее оружие
         # (двулезвийный меч, двусторонний топор, двусторонняя булава).
         # `fandom:Double-sided weapon`: «Wielding a double-sided weapon
         # automatically causes one to be dual-wielding … a double-sided
         # weapon's off-hand end counts as a light weapon». То есть это
         # ВТОРОЙ способ оказаться в бою двумя оружиями, и вторая рука при
         # нём лёгкая по слову источника, а не по размеру (задача 3.132).
         double_sided?: entry["double_sided"] == true,
         # Размер оружия — вторая половина хвата (задача 3.43). ⚠ Это то, что
         # утверждает источник, а не хват: хват — функция ДВУХ размеров, и
         # считает его `Rules.Wield` по лестнице `_grip.size_order`.
         size: atom_or_nil(entry["size"]),
         # А это ХВАТ, названный страницей Сиалы прямо — и только для персонажа
         # обычного размера (`_siala_grip.stated_for_size`). `nil` у девяти
         # записей, которых в таблице нет вовсе; тогда остаётся вывод по
         # размерам, и это разные утверждения, а не одно с пропуском.
         stated_grip: atom_or_nil(entry["siala_grip"]),
         proficiency: weapon_proficiency(group, groups, feats),
         proficiency_group: group,
         # ✅ `assumed` в справочнике больше НЕТ ни у одной записи (Dan сверил
         # перевод имён 16.08.2026 — «Я глянул, вроде перевод подходит»; группу
         # Сиала называла сама всё это время, пятью страницами фитов и колонкой
         # «Тип оружия» сводной таблицы). ⚠️ Здесь стояло «стоит у 31 назначения
         # из 47… Билд, выбравший такое оружие, говорит об этом сам».
         #
         # ⚠️ Флаг ОСТАЁТСЯ, и читать его как мёртвый код нельзя: шард добавит
         # оружие, которого нет в сводной таблице, — и оговорка обязана вернуться
         # сама. Живым его держит тест `gear_weapon_test.exs` («механизм оговорки
         # жив») на копии `priv/rules` с возвращённым статусом.
         proficiency_assumed?: entry["siala_proficiency_group_status"] == "assumed"
       }}
    end)
  end

  defp weapon_entries(raw) do
    case raw |> Map.get(:domain_files, %{}) |> Map.get(:weapons) do
      %{"weapons" => list} when is_list(list) -> for entry <- list, is_map(entry), do: entry
      _other -> []
    end
  end

  @doc """
  Пять фитов владения кастомной «Системы оружия», множеством id.

  Тот же реестр, что читает `weapons/3` (`_siala_proficiency.groups[].siala_feat`),
  и читается он здесь ради второго читателя: словарь `_bonus_feat_pools`
  в `siala_41/classes.json` называет это семейство именем категории
  (`weapon_proficiency_feats`), когда страница класса говорит «на дополнительных
  фитах может брать владение типом оружия».

  ⚠ Отдельной функцией, а не списком в словаре пулов: пять id уже названы одним
  местом, и вторая копия рано или поздно разошлась бы с первой — та самая
  ошибка, из-за которой эта задача и существует (две записи об одном правиле,
  и вторая не знает, что первая сработала).

  У ванильного ruleset'а фитов этих нет вовсе, а реестр общий — множество
  вернётся то же, и пустым оно не будет; применять его там нечему, потому что
  словарь пулов живёт в слое шарда.
  """
  @spec proficiency_feat_ids(map()) :: MapSet.t(atom())
  def proficiency_feat_ids(raw) do
    raw |> weapon_groups() |> Map.values() |> Enum.reject(&is_nil/1) |> MapSet.new()
  end

  # `%{group => feat_id | nil}` — какой фит владения требует каждая группа.
  # `no_proficiency_required` объявляет `siala_feat: null`, и это ответ, а не
  # пропуск.
  defp weapon_groups(raw) do
    case raw |> Map.get(:domain_files, %{}) |> Map.get(:weapons) do
      %{"_siala_proficiency" => %{"groups" => %{} = groups}} ->
        Map.new(groups, fn {name, spec} -> {atom(name), atom_or_nil(spec["siala_feat"])} end)

      _other ->
        %{}
    end
  end

  # ------------------------------------------------------------------ wield --

  # Правило хвата как машина (задача 3.43), из `weapons.json` → `_grip` и
  # `_siala_grip.stated_for_size`.
  #
  # ⚠ **Хват — функция ДВУХ размеров**, и это единственная причина, по которой
  # блок существует отдельно от справочника. Колонка Сиалы (`stated_grip`
  # у записи) верна для владельца ОДНОГО размера — `stated_for_size`; всем
  # остальным хват считается шагом по лестнице `size_order`, и ровно это
  # отличает Карлика с длинным мечом (двуручно, щит нельзя) от человека с ним же
  # (одноручно, щит можно) — замер Dan 16.08.2026, кейс R2b.
  #
  # ⚠ Ни одного размера, хвата и предмета ЗДЕСЬ НЕ НАЗВАНО: `size_order`,
  # `steps` и `grips_using_both_hands` целиком приходят из файла, а сборка падает
  # ниже, если лестница пуста, а правило при этом объявлено.
  def wield(raw) do
    grip = weapons_block(raw, "_grip")
    order = for size <- grip["size_order"] || [], do: atom(size)
    steps = grip["wieldable_steps"] || %{}

    rule = %{
      size_order: order,
      # Смещение по лестнице (размер оружия минус размер владельца) → хват на
      # нём, и окно, вне которого оружие не взять вовсе. ⚠ Само слово «хват»
      # тоже приходит из файла: ядро сравнивает атомы и ни одного из них
      # не называет.
      grip_by_step:
        Map.new(grip["grip_by_step"] || %{}, fn {step, name} ->
          {String.to_integer(step), atom(name)}
        end),
      grip_otherwise: atom_or_nil(grip["grip_otherwise"]),
      # «Лёгкое ли оно» — ВТОРОЕ предложение того же абзаца источника, и шаг
      # у него свой: «at least one size smaller», то есть смещение не больше
      # −1. Читает `Rules.Wield.light?/3`, а нужен ответ штрафу боя двумя
      # оружиями (задача 3.132): лёгкое оружие во второй руке снимает по 2
      # с обеих рук.
      #
      # ⚠ До 28.08.2026 правило лежало в файле ПРОЗОЙ (`light_when`) и не
      # читалось никем — пятый случай той же формы дефекта, что `Zen archery`
      # и активация расового бонуса (CLAUDE.md §9).
      light_at_most_step: grip["light_at_most_step"],
      # И вторая половина ТОГО ЖЕ предложения: «A **melee** weapon at least one
      # size smaller…». Про дальнобойное источник не утверждает ничего, поэтому
      # оно лёгким не считается — расширить предложение за его собственные
      # слова значило бы повторить ошибку 3.122 («применили шире, чем сказано»).
      #
      # ⚠ Имя свойства приходит из файла, а полем справочника его делает ОДИН
      # закрытый словарь ядра — тот же, которым пользуются хук характеристики
      # атаки и прибавки на класс оружия. Свойство, которого он прочитать
      # не умеет, роняет сборку: правило, которое молча никогда не сработает,
      # и есть тот дефект, ради которого заведена вся эта стража.
      light_excludes_field:
        weapon_property_field!(grip["light_excludes_property"], "_grip.light_excludes_property"),
      wieldable_from: steps["from"],
      wieldable_to: steps["to"],
      both_hands_grips: MapSet.new(grip["grips_using_both_hands"] || [], &atom/1),
      stated_grip_size: atom_or_nil(weapons_block(raw, "_siala_grip")["stated_for_size"]),
      # Свойство оружия, при котором объявленный хват вторую руку НЕ занимает.
      # `nil` — такого свойства нет, то есть хват решает один.
      off_hand_free_when:
        atom_or_nil(weapons_block(raw, "_siala_grip")["both_hands_excludes_when"]),
      # 🔴 КАКАЯ рука, а не сколько рук (задача 3.142) — и потому `nil`, а не
      # ключи россыпью: у этого правила своя полнота, и она не имеет ничего
      # общего с полнотой лестницы размеров. Снапшот вправе объявить лестницу
      # и промолчать про вторую руку — тогда правило не запрещает ничего,
      # ровно как молчащий `off_hand_free_when` выше ничего не исключает.
      off_hand: off_hand_rule!(weapons_block(raw, "_off_hand"))
    }

    verify_wield!(rule)
  end

  # Запрет второй руки по СВОЙСТВУ оружия — `_off_hand` целиком или `nil`.
  #
  # Два независимых запрета одного предложения источника («No ranged weapon may
  # be wielded in the off-hand slot, nor can any weapon be wielded in the
  # off-hand when a ranged weapon is in the main hand»), и второй из первого
  # не следует: праща одноручная, и по хвату вторая рука у неё свободна.
  #
  # ⚠ Занятие второй руки (`bars`) — слово ИСТОЧНИКА («any **weapon**»), а не
  # наше обобщение, и список закрыт со стороны ядра: занятие, которое ядро вне
  # второй руки удержать не умеет, роняет сборку. Ровно поэтому щит лучника
  # не отбирается молча — «weapon» в списке есть, «worn» нет, и добавить его
  # не получится, пока `Rules.Worn` не научится спрашивать.
  defp off_hand_rule!(block) when block == %{}, do: nil

  defp off_hand_rule!(block) do
    %{
      field: weapon_property_field!(property!(block), "_off_hand.property"),
      barred?: barred_from_off_hand!(block),
      bars: bars_from_off_hand!(block)
    }
  end

  defp property!(%{"property" => property}) when is_binary(property), do: property

  defp property!(block) do
    raise "weapons.json: `_off_hand` states #{inspect(Enum.sort(Map.keys(block)))} and no " <>
            "`property` — the ban is keyed by a property of the weapon, and there is no " <>
            "property to key it by"
  end

  # Половина первая: можно ли этому оружию БЫТЬ во второй руке. Булево и только
  # булево — обе половины правила источник называет отдельно, и «не сказано»
  # среди ответов нет.
  defp barred_from_off_hand!(%{"barred_from_off_hand" => barred}) when is_boolean(barred),
    do: barred

  defp barred_from_off_hand!(block) do
    raise "weapons.json: `_off_hand.barred_from_off_hand` is " <>
            "#{inspect(block["barred_from_off_hand"])} — the two halves of the rule are " <>
            "stated separately on purpose, and «not stated» is not one of the answers"
  end

  # Половина вторая: кого это оружие, будучи в ГЛАВНОЙ руке, держит из второй.
  # Список закрыт со стороны ядра, и это единственное, что мешает запрету
  # молча никогда не сработать.
  defp bars_from_off_hand!(block) do
    known = MapSet.new(BuildCalculator.Rules.Wield.off_hand_occupants())
    bars = MapSet.new(block["bars_from_off_hand"] || [], &atom/1)

    case Enum.sort(MapSet.to_list(MapSet.difference(bars, known))) do
      [] ->
        bars

      unknown ->
        raise "weapons.json: `_off_hand.bars_from_off_hand` names #{inspect(unknown)}, and " <>
                "this core keeps only #{inspect(Enum.sort(MapSet.to_list(known)))} out of " <>
                "the off hand — the ban would silently never fire"
    end
  end

  # Полу-объявленное правило опаснее необъявленного: без лестницы «на категорию
  # крупнее» посчитать нечем, и молча получилось бы «щит можно всегда».
  # Поэтому либо блока нет вовсе (снапшот без `_grip` — ядро тогда размеров не
  # знает и говорит об этом гэпом), либо он полон.
  # ⚠ Ключи, которых полнота лестницы не касается: сама лестница и запрет
  # по СВОЙСТВУ оружия (задача 3.142). Второй сюда не входит, потому что он
  # не про размер вовсе — у него свой блок, свой источник и свой сторож
  # (`off_hand_rule!/1`), и требовать его вместе с лестницей значило бы связать
  # два независимых утверждения одной проверкой.
  @wield_outside_ladder [:size_order, :off_hand]

  defp verify_wield!(rule) do
    filled =
      for {key, value} <- rule,
          key not in @wield_outside_ladder,
          not is_nil(value),
          value not in [MapSet.new(), %{}],
          do: key

    cond do
      rule.size_order == [] and filled == [] ->
        rule

      rule.size_order == [] ->
        raise "weapons.json: `_grip` states #{inspect(Enum.sort(filled))} and no `size_order` " <>
                "— «one category larger» is a step along an order, and there is no order to " <>
                "step along"

      length(filled) < map_size(rule) - length(@wield_outside_ladder) ->
        raise "weapons.json: `_grip` carries a size ladder and leaves " <>
                "#{inspect(Enum.sort(Map.keys(rule) -- (@wield_outside_ladder ++ filled)))} " <>
                "unstated"

      rule.stated_grip_size not in rule.size_order ->
        raise "weapons.json: `_siala_grip.stated_for_size` is " <>
                "#{inspect(rule.stated_grip_size)}, which is not a rung of " <>
                "#{inspect(rule.size_order)}"

      true ->
        rule
    end
  end

  # Свойство справочника по имени — или падение сборки, если ядро такого
  # свойства прочитать не умеет. `nil` на входе означает «правило свойства
  # не называет», и это законно: сторож блока решает, можно ли ему быть
  # неполным (`verify_wield!/1` у лестницы, `property!/1` у второй руки).
  #
  # ⚠ Ключ передаётся строкой ради сообщения об ошибке: читателей два
  # (`_grip.light_excludes_property` и `_off_hand.property`), и назвать
  # в падении чужой ключ значило бы отправить чинить не тот блок.
  defp weapon_property_field!(nil, _key), do: nil

  defp weapon_property_field!(property, key) do
    name = atom(property)

    case BuildCalculator.Rules.Attack.weapon_property_field(name) do
      nil ->
        raise "weapons.json: `#{key}` names #{inspect(name)}, and the " <>
                "core cannot read that property off a weapon — the rule would silently " <>
                "never fire"

      field ->
        field
    end
  end

  # Имя поля расы, которым она сама говорит, что большое оружие ей не по руке.
  # Стоит ЗДЕСЬ, а не в правиле: ядро этим полем не пользуется вовсе — оно
  # считает по размерам, — и всё, чем поле полезно, это ВТОРОЕ независимое
  # чтение того же факта. Дословно `fandom:Weapon size`: «(For playable races,
  # this only excludes large weapons from gnomes and halflings.)»
  @large_weapon_ban :cannot_use_large_weapons

  # Правило размеров и расовый флаг обязаны говорить одно и то же.
  #
  # ⚠ Проверяется не «у кого стоит флаг», а «кому правило что-то запрещает»:
  # перевёрнутая лестница (`large` первым) отняла бы у средних рас крохотное
  # оружие вместо крупного, флаги при этом остались бы на месте, и единственное,
  # что расхождение показало бы, — эта проверка.
  def verify_large_weapon_bans!(%{size_order: []}, _races, _weapons), do: :ok

  def verify_large_weapon_bans!(wield, races, weapons) do
    for {id, race} <- Enum.sort(races), not is_nil(race.size) do
      unless race.size in wield.size_order do
        raise "vanilla/races.json: #{id} is #{inspect(race.size)}, which is not a rung of the " <>
                "size ladder #{inspect(wield.size_order)} weapons.json states"
      end

      refused =
        for {_wid, weapon} <- weapons,
            not is_nil(weapon.size),
            step(wield, weapon.size, race.size) > wield.wieldable_to,
            uniq: true,
            do: weapon.size

      stated? = MapSet.member?(race.restrictions, @large_weapon_ban)

      unless stated? == (refused != []) do
        raise """
        races/weapons disagree about #{id}: `#{@large_weapon_ban}` is #{stated?}, and the size \
        rule refuses it weapons of #{inspect(Enum.sort(refused))}. The same fact is written \
        twice on purpose — the rule is what the core computes, the field is what the race's own \
        page says — and a build that let the two drift would offer a greatsword to a halfling.
        """
      end
    end

    :ok
  end

  # На сколько ступеней оружие крупнее владельца. Обе стороны уже проверены на
  # принадлежность лестнице, поэтому `Enum.find_index/2` здесь не может вернуть
  # `nil`.
  defp step(wield, weapon_size, wielder_size) do
    Enum.find_index(wield.size_order, &(&1 == weapon_size)) -
      Enum.find_index(wield.size_order, &(&1 == wielder_size))
  end

  defp weapons_block(raw, key) do
    case raw |> Map.get(:domain_files, %{}) |> Map.get(:weapons) do
      %{^key => %{} = block} -> block
      _other -> %{}
    end
  end

  @no_weapon_proficiency :no_proficiency_required

  defp weapon_proficiency(@no_weapon_proficiency, _groups, _feats), do: :none_needed

  defp weapon_proficiency(group, groups, feats) do
    case Map.get(groups, group) do
      feat when is_atom(feat) and not is_nil(feat) ->
        if Map.has_key?(feats, feat), do: {:feat, feat}, else: :unread

      _nil_or_missing ->
        :unread
    end
  end

  # Оружие, которое предметом игрока не является: у Fandom в шаблоне `{{Weapon}}`
  # у него `proficiency=creature`, а собственная заметка справочника говорит это
  # словами («Creature weapon, not a player's item»). В домене выбора фитов оно
  # остаётся — `Weapon focus (creature weapon)` законный выбор оборотня, — а в
  # блоке «Вещи» ему не место: усиление атаки вводится С ПРЕДМЕТА.
  #
  # ⚠ Факт записан в данных ДВАЖДЫ: значением ванильного владения и списком id
  # (`overrides.json` → `gear.weapon.not_wieldable`). Расхождение роняет сборку —
  # приём и довод те же, что у `verify_racial_bonus_cap_agrees!/3`: две копии
  # разъезжаются, и падение на компиляции это единственное, что делает вторую
  # копию безопасной. Шестая запись с `proficiency=creature` в справочнике
  # потребует осознанной правки списка, а не всплывёт у игрока.
  # Оружие, которого на шарде НЕТ вовсе (задача-наблюдение Dan 16.08.2026: лэнс).
  # ⚠ Отдельно от `not_wieldable`: тот говорит «это не предмет игрока», а здесь
  # предмет обычный, просто отсутствующий. Причина у отказа своя, потому что
  # печатается она игроку.
  defp absent_weapons!(ov, entries) do
    # ⚠ Секция `weapons`, а НЕ `gear`: `gear` лежит в @vanilla_sections, то есть
    # виден ОБОИМ ruleset'ам, и лэнс исчез бы и у ванили — а это утверждение,
    # что его нет в NWN вообще. Ошибку сделали и поймали прогоном 16.08.2026:
    # у ванильного списка оружия стало 41 вместо 42.
    stated =
      for id <- dig(ov, ["weapons", "absent_on_shard", "weapons"]) || [], do: atom(id)

    known = MapSet.new(entries, &atom(&1["id"]))

    for id <- stated, not MapSet.member?(known, id) do
      raise "overrides.json: weapons.absent_on_shard names #{id}, which weapons.json " <>
              "does not carry — the shard cannot be missing what vanilla never had."
    end

    MapSet.new(stated)
  end

  defp not_wieldable_weapons!(ov, entries) do
    stated = for id <- dig(ov, ["gear", "weapon", "not_wieldable", "weapons"]) || [], do: atom(id)
    proficiency = dig(ov, ["gear", "weapon", "not_wieldable", "vanilla_proficiency"])

    computed =
      if is_binary(proficiency) do
        for entry <- entries,
            proficiency in (entry["proficiency"] || []),
            do: atom(entry["id"])
      else
        stated
      end

    unless Enum.sort(stated) == Enum.sort(computed) do
      raise """
      overrides.json: gear.weapon.not_wieldable names #{inspect(Enum.sort(stated))}, and \
      weapons.json states proficiency #{inspect(proficiency)} for \
      #{inspect(Enum.sort(computed))}. The same fact is written twice on purpose; a build \
      that let the two disagree would silently offer a creature's attack form as an item.
      """
    end

    stated
  end

  # Либо все пять фитов владения этого ruleset'а на месте, либо ни одного.
  #
  # ⚠ Проверка сформулирована так, а не «фит обязан существовать», ровно потому,
  # что у ванильного ruleset'а его законно нет: пять сиальских фитов владения
  # приходят слоем шарда. Опечатка в одном имени при этом всё равно ловится —
  # у шарда окажется четыре из пяти, — а вот проверка «обязан существовать»
  # уронила бы ванильную сборку, и её пришлось бы отключать по имени версии.
  defp verify_proficiency_feats!(groups, feats) do
    named = for {_group, feat} <- groups, not is_nil(feat), do: feat
    missing = Enum.sort(Enum.reject(named, &Map.has_key?(feats, &1)))

    if missing != [] and length(missing) < length(named) do
      raise """
      weapons.json: _siala_proficiency.groups names the proficiency feats \
      #{inspect(Enum.sort(named))}, and this ruleset carries every one of them except \
      #{inspect(missing)}. Either the whole system is absent (as it is on vanilla) or a name \
      is misspelt — and a misspelt one would quietly stop filtering the weapon list.
      """
    end

    :ok
  end
end
