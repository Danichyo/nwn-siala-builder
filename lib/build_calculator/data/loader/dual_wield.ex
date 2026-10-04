defmodule BuildCalculator.Data.Loader.DualWield do
  @moduledoc """
  Штрафы боя двумя оружиями — `vanilla/feat_attack_bonuses.json` → `dual_wield`.

  Блок читается ЦЕЛИКОМ или не читается вовсе: половина таблицы штрафов хуже её
  отсутствия. Без базы (−6/−10) ступени уменьшали бы ноль, без ступеней база
  висела бы на каждом билде с двумя оружиями, и в обоих случаях число было бы
  неверным молча. Поэтому `nil` здесь означает «блока нет», и ядро говорит об
  этом гэпом (`{:missing_data, :dual_wield_rules}`), а полу-объявленный блок
  роняет сборку — тот же приём, что у `_grip` в `Loader.Gear.verify_wield!/1`.

  ⚠ Ни одного игрового числа и ни одного имени фита здесь нет: и то и другое
  приходит из файла. Что проверяется на компиляции:

    * каждый названный фит есть в справочнике — опечатка иначе означала бы
      ступень, которая молча никогда не сработает;
    * свойство оружия у `double_sided` ядро умеет прочитать
      (`Rules.Attack.weapon_property_field/1`) — тот же закрытый словарь, что
      у хука характеристики атаки и у прибавок на класс оружия;
    * условие выдачи называет свойство надетого, которое ядро умеет прочитать
      (`Rules.Worn.item_property_field/1`) — тот же закрытый словарь, тот же
      приём; имени, которого оно прочитать не умеет, загрузчик не пропустит;
    * условие обязано сказать, кто и почему решил считать выдачу там, где класс
      надетого этому слою неизвестен, и назвать ключ оговорки. Без этого решение
      владельца было бы неотличимо от забытой проверки.

  ⚠ До задачи 3.141 условие объявляло себя нечитаемым полем `readable: false`,
  и загрузчик верил файлу на слово. Теперь читаемость решает СЛОВАРЬ ЯДРА, а
  файл только называет свойство: утверждение файла о самом себе проверить было
  нечем, а имя свойства проверяется.
  """

  import BuildCalculator.Data.Loader.Reading

  alias BuildCalculator.Rules.{Attack, Worn}

  @source_file "feat_attack_bonuses.json"

  @doc """
  Таблица штрафов как машина — или `nil`, если файл её не несёт.

  `feats` и `worn` нужны только для сверки имён: правило целиком приходит из
  блока. `worn` — уже построенные категории надетого (`gear.worn`), потому что
  условие выдачи называет и категорию, и класс её предметов, и обе стороны
  проверяются об одно и то же место.
  """
  @spec build(map() | :missing, map(), [map()]) :: map() | nil
  def build(raw, feats, worn \\ [])

  def build(:missing, _feats, _worn), do: nil

  def build(raw, feats, worn) when is_map(raw) do
    case raw["dual_wield"] do
      %{} = block -> read!(block, feats, worn)
      _absent -> nil
    end
  end

  def build(_other, _feats, _worn), do: nil

  # ------------------------------------------------------------------ private --

  defp read!(block, feats, worn) do
    %{
      # База стиля: она есть у всякого, кто держит два оружия, и ничьим фитом
      # не выдана. Ровно поэтому блок не разложить на записи `bonuses` — там у
      # каждой прибавки есть источник, а у этой его нет.
      base_penalty: penalty!(block["base_penalty"], "base_penalty"),
      steps: steps!(block["steps"], feats),
      # Единственная ступень, которая не фит, а свойство ПАРЫ «оружие +
      # владелец» (`Rules.Wield.light?/3`).
      light_off_hand: penalty!(block["light_off_hand"], "light_off_hand"),
      off_hand_attacks: attacks!(block["off_hand_attacks"], feats),
      double_sided: double_sided!(block["double_sided"]),
      grants: grants!(block["grants"], feats, worn)
    }
  end

  defp penalty!(%{"main" => main, "off" => off}, _what) when is_integer(main) and is_integer(off),
    do: %{main: main, off: off}

  defp penalty!(value, what) do
    raise "#{@source_file}: dual_wield.#{what} is #{inspect(value)}, and a penalty needs both hands — " <>
            "a half-stated table would be wrong on one of them silently"
  end

  defp steps!(steps, feats) when is_list(steps) do
    for step <- steps do
      %{main: main, off: off} = penalty!(step, "steps[]")
      %{feat: feat!(step["feat"], feats, "steps[]"), main: main, off: off}
    end
  end

  defp steps!(value, _feats) do
    raise "#{@source_file}: dual_wield.steps is #{inspect(value)} — the table states its steps as a list"
  end

  # Сколько атак даёт сама вторая рука, и что к ним прибавляют фиты. ⚠ Штраф
  # второй атаки (`attack_penalty`) читается фактом и НЕ применяется: модель
  # печатает по одному AB на руку — бонус первой атаки этой руки, — ровно как
  # у главной, где вторая и следующие идут через −5 и не печатаются тоже.
  defp attacks!(%{"base" => base, "extra" => extra}, feats)
       when is_integer(base) and is_list(extra) do
    %{
      base: base,
      extra:
        for entry <- extra do
          %{
            feat: feat!(entry["feat"], feats, "off_hand_attacks.extra[]"),
            attacks: entry["attacks"],
            attack_penalty: entry["attack_penalty"]
          }
        end
    }
  end

  defp attacks!(value, _feats) do
    raise "#{@source_file}: dual_wield.off_hand_attacks is #{inspect(value)} — the block needs both " <>
            "how many attacks the off hand gives by itself and what adds to them"
  end

  # Второй способ оказаться в бою двумя оружиями: двустороннее оружие занимает
  # обе руки одним предметом. «Лёгкость» его второго конца названа СЛОВОМ
  # источника, а не посчитана по размеру, — и поле у неё поэтому своё.
  defp double_sided!(%{"weapon_must_be" => property} = block) when is_binary(property) do
    name = atom(property)

    case Attack.weapon_property_field(name) do
      nil ->
        raise "#{@source_file}: dual_wield.double_sided names property #{inspect(name)}, and the core " <>
                "cannot read it off a weapon — the rule would silently never fire"

      field ->
        %{weapon_field: field, off_hand_is_light?: block["off_hand_is_light"] == true}
    end
  end

  defp double_sided!(value) do
    raise "#{@source_file}: dual_wield.double_sided is #{inspect(value)} and names no weapon property"
  end

  defp grants!(nil, _feats, _worn), do: []

  defp grants!(grants, feats, worn) when is_list(grants) do
    for grant <- grants do
      %{
        feat: feat!(grant["feat"], feats, "grants[]"),
        benefits_of:
          MapSet.new(grant["benefits_of"] || [], &feat!(&1, feats, "grants[].benefits_of")),
        condition: condition!(grant["condition"], grant["feat"], worn)
      }
    end
  end

  defp grants!(value, _feats, _worn) do
    raise "#{@source_file}: dual_wield.grants is #{inspect(value)} — the block states its grants as a list"
  end

  # 🔴 Условие выдачи. Читается ли оно, решает СЛОВАРЬ ЯДРА, а не поле файла:
  # `kind` называет свойство надетого предмета, и `Rules.Worn.item_property_field/1`
  # либо знает, каким полем оно лежит, либо не знает — и тогда сборка падает,
  # вместо того чтобы отгрузить правило, которое молча никогда не сработает.
  #
  # 🔴 И условие, у которого есть ответ не в каждом ruleset'е, обязано сказать
  # три вещи: кто решил, почему всё-таки считаем выдачу там, где класс надетого
  # этому слою неизвестен, и каким ключом об этом сказано игроку. Без любой из
  # трёх решение владельца выглядело бы забытой проверкой — а разница между ними
  # и есть весь смысл механизма оговорок. ⚠ Сегодня такой ruleset ровно один
  # (`vanilla`: границу класса брони измеряли на Сиале, и переносить её
  # по аналогии запрещено), так что все три поля живые, а не про запас.
  defp condition!(nil, _feat, _worn), do: nil

  defp condition!(%{"kind" => kind} = condition, feat, worn) when is_binary(kind) do
    name = atom(kind)

    field =
      Worn.item_property_field(name) ||
        raise(
          "#{@source_file}: dual_wield.grants[#{inspect(feat)}].condition names #{inspect(name)}, " <>
            "and the core cannot read it off a worn item — the rule would silently never fire"
        )

    for key <- ["who", "why", "gap"] do
      value = condition[key]

      if not is_binary(value) or String.trim(value) == "" do
        raise "#{@source_file}: dual_wield.grants[#{inspect(feat)}].condition states no `#{key}` " <>
                "— a ruleset that cannot answer it counts the grant anyway, and a decision " <>
                "nobody signed is a check that was forgotten"
      end
    end

    %{
      kind: name,
      # Каким полем предмета читается ответ — именем, посчитанным ядром, а не
      # переписанным сюда: два места, называющих одно поле, разъезжаются.
      field: field,
      # При каких классах выдача ТЕРЯЕТСЯ. Названные классы обязаны быть теми,
      # которые предметы этого ruleset'а действительно носят: опечатка иначе
      # означала бы условие, не срабатывающее ни разу.
      lost_when: lost_when!(condition, worn, feat),
      counted_when_class_is_unknown?: condition["counted_when_class_is_unknown"] == true,
      gap: atom(condition["gap"]),
      # ПРО ЧТО надетое идёт условие — категориями `gear.worn`, а не «про всё
      # надетое»: источник говорит про доспех, а щит в его предложении не
      # назван. Категория, которой у ruleset'а нет, роняет сборку: оговорка,
      # привязанная к несуществующему слоту, не появилась бы никогда.
      worn_categories: worn_categories!(condition["worn_categories"], worn, feat)
    }
  end

  defp condition!(condition, feat, _worn) do
    raise "#{@source_file}: dual_wield.grants[#{inspect(feat)}] states condition #{inspect(condition)}, " <>
            "which names no `kind` — a condition the core cannot look up is one it cannot check"
  end

  # ⚠ Сверяется с классами, которые НЕСУТ предметы этого ruleset'а, а не со
  # списком из кода. У `vanilla` их нет вовсе (все `:unknown`), и там сверять
  # не с чем — молчание слоя не должно выглядеть опечаткой в условии.
  defp lost_when!(condition, worn, feat) do
    named = MapSet.new(condition["lost_when_worn_armor_is_one_of"] || [], &atom/1)

    known =
      for category <- worn,
          item <- category.items,
          item.weight_class != :unknown,
          into: MapSet.new(),
          do: item.weight_class

    strays = MapSet.difference(named, known)

    if MapSet.size(known) > 0 and MapSet.size(strays) > 0 do
      raise "#{@source_file}: dual_wield.grants[#{inspect(feat)}].condition loses the grant on " <>
              "#{inspect(MapSet.to_list(strays))}, which nothing this ruleset can wear is " <>
              "(#{inspect(Enum.sort(MapSet.to_list(known)))}) — the exception would never fire"
    end

    named
  end

  defp feat!(name, feats, where) when is_binary(name) do
    id = atom(name)

    if map_size(feats) > 0 and not Map.has_key?(feats, id) do
      raise "#{@source_file}: dual_wield.#{where} names feat #{inspect(id)}, which the feat dictionary " <>
              "has no record of — the step would never fire"
    end

    id
  end

  defp feat!(name, _feats, where) do
    raise "#{@source_file}: dual_wield.#{where} names #{inspect(name)} where a feat id was expected"
  end

  defp worn_categories!(names, worn, feat) do
    categories = for name <- names || [], do: atom(name)
    known = for category <- worn, do: category.id
    unknown = if known == [], do: [], else: categories -- known

    unless unknown == [] do
      raise "#{@source_file}: dual_wield.grants[#{inspect(feat)}].condition names worn " <>
              "categories #{inspect(unknown)}, which this ruleset has no slot for — the caveat " <>
              "would never appear"
    end

    categories
  end
end
