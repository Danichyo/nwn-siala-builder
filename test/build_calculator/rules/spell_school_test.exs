defmodule BuildCalculator.Rules.SpellSchoolTest do
  @moduledoc """
  Школа заклинания как СЧИТАЕМОЕ поле — и цена специализации волшебника.

  До 24.08.2026 (задача 3.86) школа до ответа не доезжала вовсе: она лежала
  сырым викитекстом в `spell.school`, печаталась в пикере как есть и ни на одно
  число не влияла. Поэтому специализация показывала игроку **одну выгоду**
  (`+1` слот на круг, считается с задачи 3.10), а её цену — потерю
  противоположной школы — не называла нигде, хотя выбор делается в нашем же
  интерфейсе.

  Теперь цена — число: сколько заклинаний СОБСТВЕННОГО списка волшебника уносит
  противоположная школа. Отсюда два требования, которые этот файл и держит:

    * **школа читается**, а не печатается: три из 304 ванильных записей несут
      зачёркнутую историю патчей (`"<del>abjuration</del> <i>necromancy</i>"`),
      одна написана с заглавной. Читает их `Wiki.SialaSpellPage.school/1` —
      тот же закрытый словарь, которым `mix wiki.parse` сравнивает две вики,
      второй реализации нет;
    * **считается СИАЛЬСКАЯ школа**, а не ванильная. Шард переносит восемь
      заклинаний, шесть из них одним махом из Разрушения в Зачарование, и
      по ванильной колонке цена Иллюзии вышла бы 16 вместо 20 — ошибка
      на четверть, молчаливая и неотличимая от правды.

  ⚠️ Счёт ПОЖИЗНЕННЫЙ (решение Dan): школа называется один раз и навсегда,
  значит и цена у неё одна на весь билд, а не «сколько заклинаний закрыто
  на этом уровне».
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules.Spells

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  # Восемь школ, у каждой своя противоположная — `opposed_schools` в
  # `vanilla/spellcasting.json`, со страницы `fandom:Wizard`. Числа — счёт
  # по списку волшебника (`ruleset.spell_lists[:wizard] == :mage`) в СВОЁМ
  # ruleset'е, посчитанный прогоном 24.08.2026 и здесь закреплённый.
  @vanilla [
    {:abjuration, :conjuration, 27},
    {:conjuration, :transmutation, 27},
    {:divination, :illusion, 15},
    {:enchantment, :illusion, 15},
    {:evocation, :conjuration, 27},
    {:illusion, :enchantment, 16},
    {:necromancy, :divination, 12},
    {:transmutation, :conjuration, 27}
  ]

  # ⚠️ Отличаются РОВНО ДВЕ строки, и обе — от переноса восьми заклинаний
  # шардом: `transmutation` +1 (`balagarns_iron_horn` пришёл), `enchantment`
  # +4 (пять «рук» Бигби пришли, `balagarns_iron_horn` ушёл; шестое
  # заклинание переноса, `Dirge`, у волшебника в списке не значится вовсе —
  # у него только колонка барда). Пары «кто кого закрывает» не меняются
  # ни одной: Сиала переписала заклинания, а не механику специализации.
  @siala [
    {:abjuration, :conjuration, 27},
    {:conjuration, :transmutation, 28},
    {:divination, :illusion, 15},
    {:enchantment, :illusion, 15},
    {:evocation, :conjuration, 27},
    {:illusion, :enchantment, 20},
    {:necromancy, :divination, 12},
    {:transmutation, :conjuration, 27}
  ]

  describe "цена специализации по школам" do
    test "siala_41: восемь пар «школа → что закроется и на сколько»", %{siala: siala} do
      costs = Spells.specialization_costs(siala, :wizard)

      for {school, opposed, spells} <- @siala do
        assert %{school: ^opposed, spells: ^spells} = Map.get(costs, school),
               "#{school}: ожидалось «закрывает #{opposed}, #{spells}», " <>
                 "пришло #{inspect(Map.get(costs, school))}"
      end

      assert map_size(costs) == length(@siala)
    end

    # ⚠️ Второй ruleset — своя правда, и это половина смысла таблицы выше:
    # ваниль обязана остаться ванильной. Правка школы лежит в сиальском слое
    # (`siala_41/spells.json`); уедь она в общий, ванильные числа поехали бы
    # вместе с ней и никто бы этого не заметил.
    test "vanilla: те же восемь пар, но ванильными числами", %{vanilla: vanilla} do
      costs = Spells.specialization_costs(vanilla, :wizard)

      for {school, opposed, spells} <- @vanilla do
        assert %{school: ^opposed, spells: ^spells} = Map.get(costs, school),
               "#{school}: ожидалось «закрывает #{opposed}, #{spells}», " <>
                 "пришло #{inspect(Map.get(costs, school))}"
      end
    end

    # Положительный контроль к обеим таблицам: два ruleset'а расходятся ровно
    # там, где шард двигал заклинания, и совпадают везде ещё. Без этой строки
    # «ваниль ванильная» и «Сиала сиальская» прошли бы и у реализации, которая
    # просто вернула одну и ту же таблицу дважды.
    test "расходятся ровно две строки из восьми", %{siala: siala, vanilla: vanilla} do
      s = Spells.specialization_costs(siala, :wizard)
      v = Spells.specialization_costs(vanilla, :wizard)

      differing = for {school, cost} <- s, Map.get(v, school) != cost, do: school

      assert Enum.sort(differing) == [:conjuration, :illusion]
    end

    test "знаменатель едет вместе с числом", %{siala: siala} do
      costs = Spells.specialization_costs(siala, :wizard)
      list_size = length(Spells.list_for(siala, :wizard))

      assert list_size == 179
      assert Enum.all?(costs, fn {_school, cost} -> cost.list_size == list_size end)
    end

    # У класса без записи специализации цены нет вовсе — не ноль, а пусто.
    # Ноль читался бы как «эта школа не стоит ничего».
    test "у клирика специализации нет — пустая карта, а не нули", %{siala: siala} do
      assert Spells.specialization_costs(siala, :cleric) == %{}
      assert Spells.specialization(siala, :cleric) == nil
    end
  end

  describe "перенос восьми заклинаний шардом" do
    # Шесть страниц Сиалы называют «Зачарование (Enchantment)» там, где Fandom
    # пишет `[[evocation]]`. Пять из них — заклинания волшебника, шестое
    # (`Dirge`) только бардовское; поэтому Разрушение теряет ровно пять,
    # а Зачарование ровно пять получает.
    @moved_to_enchantment [
      :bigbys_clenched_fist,
      :bigbys_crushing_hand,
      :bigbys_forceful_hand,
      :bigbys_grasping_hand,
      :bigbys_interposing_hand,
      :dirge
    ]

    test "шесть заклинаний уходят из evocation в enchantment", %{siala: s, vanilla: v} do
      for id <- @moved_to_enchantment do
        assert v.spells[id].school == :evocation, "ваниль: #{id}"
        assert s.spells[id].school == :enchantment, "Сиала: #{id}"
      end
    end

    # ⚠️ Обе половины под одним тестом: «пять в списке волшебника» и «одно
    # не в нём» поодиночке выглядят правильными и при сломанном фильтре.
    test "в списке волшебника из этих шести пять, Dirge — бардовское", %{siala: s} do
      in_list = for %{id: id} <- Spells.list_for(s, :wizard), id in @moved_to_enchantment, do: id

      assert Enum.sort(in_list) == Enum.sort(@moved_to_enchantment -- [:dirge])
      assert Map.has_key?(s.spells[:dirge].levels, :bard)
      refute Map.has_key?(s.spells[:dirge].levels, :mage)
    end

    # ⚠️ Два одиночных переноса, и у обоих Сиала называет ровно то значение,
    # которое Fandom у себя ВЫЧЕРКНУЛ. Различить «шард оставил старую школу»
    # и «страницу Сиалы писали с более старой ревизии» нечем — взято значение
    # Сиалы по рангу источников (CLAUDE.md §3), и это записано в самих данных.
    test "balagarns_iron_horn и clarity — сиальские значения, а не ванильные", %{
      siala: s,
      vanilla: v
    } do
      assert v.spells[:balagarns_iron_horn].school == :enchantment
      assert s.spells[:balagarns_iron_horn].school == :transmutation

      assert v.spells[:clarity].school == :necromancy
      assert s.spells[:clarity].school == :abjuration
    end

    # 🔴 Числовое следствие переноса, ради которого он и поднят в слой:
    # специализация на Иллюзии закрывает 20 заклинаний, а не 16.
    test "цена Иллюзии выросла с ванильных 16 до сиальских 20", %{siala: s, vanilla: v} do
      assert Spells.specialization_costs(v, :wizard).illusion.spells == 16
      assert Spells.specialization_costs(s, :wizard).illusion.spells == 20
    end
  end

  describe "чтение поля школы" do
    # 🔴 Сторож против молчаливого недосчёта. Заклинание с нечитаемой школой
    # не попадает ни в одну корзину (`school: nil`, строка остаётся
    # в `school_raw`), то есть цена молча оказалась бы меньше правды. Здесь
    # это падение теста, а не число на экране.
    test "у каждого заклинания списка волшебника школа прочитана", %{siala: s, vanilla: v} do
      for ruleset <- [s, v] do
        unreadable =
          for %{id: id, spell: spell} <- Spells.list_for(ruleset, :wizard),
              is_nil(spell.school),
              do: {id, spell.school_raw}

        assert unreadable == [], "нечитаемая школа у #{inspect(unreadable)}"

        counts = Spells.school_counts(ruleset, :wizard)
        assert Enum.sum(Map.values(counts)) == length(Spells.list_for(ruleset, :wizard))
      end
    end

    # Три записи с зачёркнутой историей патчей и одна с заглавной буквы —
    # ровно те, на которых наивное чтение поля сломалось бы. Сырое значение
    # при этом не выброшено: `school_raw` рядом, как `levels_raw` у круга.
    test "зачёркнутая история срезана, а сырое значение сохранено", %{vanilla: v} do
      assert v.spells[:clarity].school == :necromancy
      assert v.spells[:clarity].school_raw == "<del>abjuration</del> <i>necromancy</i>"

      assert v.spells[:balagarns_iron_horn].school == :enchantment

      assert v.spells[:balagarns_iron_horn].school_raw ==
               "<del>transmutation</del> <ins>''enchantment''</ins>"
    end

    test "заглавная буква — не девятая школа", %{siala: s} do
      assert s.spells[:stream_of_flame].school == :evocation
      assert s.spells[:stream_of_flame].school_raw == "Evocation"
    end
  end
end
