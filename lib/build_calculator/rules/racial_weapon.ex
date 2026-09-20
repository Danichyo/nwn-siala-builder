defmodule BuildCalculator.Rules.RacialWeapon do
  @moduledoc """
  Совпало ли оружие в руках с расой — и не сломала ли это вторая рука.

  Это условие, которое скрипты шарда зовут `RaceBonus` и по которому величина
  бонуса **удваивается** (`if R, B = 2B` — арифметика всех восьми
  исполнителей, `siala_41/systems.json` → `bonuses_level_tiers`). Условий у него
  два, и второе до 12.09.2026 не было записано нигде:

      1. в руках есть оружие КАТЕГОРИИ, которую зеркалит раса;
      2. в другой руке нет оружия ДРУГОЙ категории.

  > «The matching multiplier requires the other hand not to contain a different
  > weapon category; torches, wands, rods, and shields do not count as a
  > conflict» (`sl_s_wp_inc.nss:516-539`, разбор серверных скриптов
  > 11.09.2026).

  ## Замер, ради которого модуль и появился

  Dan 12.09.2026 (`GAME_CHECKS.md`, кейс `AN1`): «карлик 15 уровня, по дефолту
  AC = 12… С клинковым в руке AC вырастает до 18, если взять дубину в левую
  руку, то AC падает до 15, но я получаю урон соником от дубины. Получается
  второе оружие другого вида убирает удвоенный бонус AC».

  Арифметика сходится точка в точку: тир 2 (уровень 15) × 3/2 (чистый класс
  Сагры) = 3, ×2 за расовое оружие = 6 → AC 18; без удвоения 3 → AC 15.

  ## Что здесь НЕ решается

  Какой из наших двух термов гасится, когда удвоения нет, — вопрос
  `Rules.WeaponTypeBonus`, не этот. Здесь только ответ про руки, и он же
  печатается в справке к расовому бонусу (`Rules.RacialBonus.of/2` → поле
  `weapon_match`).

  ## Четыре ответа, и четвёртый — не ошибка, а честность

    * `:none` — спрашивать нечего: ruleset без этой системы (ваниль), раса
      без расового оружия (Гоблин и Тёмный эльф), пустые руки или оружие
      не той категории вовсе. Удвоения нет и не было бы;
    * `:matched` — совпадение засчитано, удвоение стоит;
    * `{:broken, weapon}` — совпадение есть, но другая рука держит оружие
      другой категории, и удвоение снято. `weapon` называет виновника, потому
      что справка обязана назвать, что именно снять с руки;
    * `{:unknown, weapon}` — другая рука держит оружие, **категории которого
      не знает ни один источник**. Сегодня это рукопашный удар: «Система
      оружия» описывает бонус перчаток, но ни одного оружия к этому типу
      не приписывает. Считаем как раньше (удвоение остаётся) и говорим об этом
      гэпом: молча снять — занизить, молча оставить — завысить, а выбирать
      между двумя ошибками по вкусу нельзя.

  ## Ни одного имени расы, оружия и группы здесь нет

  Какую категорию зеркалит раса — данные (`racial_bonuses.by_race[race]
  .mirrors_group`, прочитано из фразы «Бонус идентичен бонусу от ношения
  клинков» и независимо подтверждено таблицей `GetHasRaceWeapon` 5 из 5).
  Какая категория у оружия — тоже данные (`weapon_type_bonuses.categories`).
  Мешает ли своя категория — данные (`same_category_breaks?`, `false`
  по замеру `AH2`). Отсутствие любого из трёх означает `:none`, то есть
  поведение до задачи 3.198.
  """

  alias BuildCalculator.Rules.{Build, GearWeapon}

  @typedoc "Состояние расового совпадения у этого билда."
  @type match :: :none | :matched | {:broken, atom()} | {:unknown, atom()}

  @doc """
  Состояние расового совпадения — см. четыре ответа в описании модуля.

  ⚠ Спрашивает `Rules.GearWeapon.held_all/2`, то есть оружие, которое билд
  **действительно держит**: записанное, но отвергнутое (нет владения, не тот
  хват, дальнобойное во второй руке) ни совпадения не даёт, ни его не ломает.
  """
  @spec match(Build.t(), map()) :: match()
  def match(%Build{} = build, ruleset) do
    with %{breaks_on_different_category?: true} = rule <- rule(ruleset),
         group when not is_nil(group) <- mirrored_group(build, ruleset),
         categories = categories(ruleset),
         held = [_ | _] <- GearWeapon.held_all(build, ruleset),
         {hand, _weapon} <- Enum.find(held, &same_category?(&1, categories, group)) do
      other_hands(held, hand, categories, group, rule)
    else
      _nothing_to_answer -> :none
    end
  end

  @doc """
  Категория этого оружия у движка — `nil`, если её не называет ни один
  источник.

  Отдаётся наружу, потому что об этом спрашивает не только правило удвоения:
  строка справки обязана уметь сказать, ПОЧЕМУ оружие считается чужим, а
  «категория неизвестна» и «категория другая» — разные фразы.
  """
  @spec category(map(), atom()) :: atom() | {:own_type, atom()} | nil
  def category(ruleset, weapon) when is_atom(weapon), do: Map.get(categories(ruleset), weapon)

  # Руки, кроме той, где лежит расовое оружие. Первый найденный нарушитель
  # важнее любого другого — их и не бывает больше одного, пока рук две, — а
  # «категории не знаю» уступает «категория другая»: неизвестность стоит
  # называть только там, где она осталась единственным, что мешает ответить.
  defp other_hands(held, hand, categories, group, rule) do
    others = for {other, weapon} <- held, other != hand, do: weapon

    broken = Enum.find(others, &different_category?(&1, categories, group, rule))
    unknown = Enum.find(others, &is_nil(Map.get(categories, &1)))

    cond do
      not is_nil(broken) -> {:broken, broken}
      not is_nil(unknown) -> {:unknown, unknown}
      true -> :matched
    end
  end

  defp same_category?({_hand, weapon}, categories, group),
    do: Map.get(categories, weapon) == group

  defp different_category?(weapon, categories, group, rule) do
    case Map.get(categories, weapon) do
      nil -> false
      ^group -> rule.same_category_breaks?
      _other -> true
    end
  end

  defp rule(ruleset) do
    case Map.get(ruleset, :racial_bonuses) do
      %{weapon_match: %{} = rule} -> rule
      _absent -> nil
    end
  end

  defp mirrored_group(%Build{race: race}, ruleset) when not is_nil(race) do
    case Map.get(ruleset, :racial_bonuses) do
      %{by_race: %{^race => %{mirrors_group: group}}} -> group
      _absent -> nil
    end
  end

  defp mirrored_group(_build, _ruleset), do: nil

  defp categories(ruleset) do
    case Map.get(ruleset, :weapon_type_bonuses) do
      %{categories: %{} = categories} -> categories
      _absent -> %{}
    end
  end
end
