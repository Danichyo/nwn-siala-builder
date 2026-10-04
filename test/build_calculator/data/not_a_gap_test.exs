defmodule BuildCalculator.Data.NotAGapTest do
  @moduledoc """
  `BuildCalculator.Data.Loader.NotAGap` — сторож решения владельца о том, что
  запись пробелом не является (задачи 3.74–3.76, 3.82; сведён в один модуль
  задачей 3.95).

  ⚠️ **Направление риска здесь обратное всему остальному в проекте.** Обычно
  ошибка в данных добавляет лишнюю оговорку, а `not_a_gap` её УБИРАЕТ: это
  единственный способ уменьшить число, которое калькулятор показывает игроку,
  ничего не посчитав. Поэтому проверяется не «как это работает», а «что́ роняет
  сборку».

  Живые данные тут не участвуют вовсе — все четыре семейства проверяют своего
  сторожа своими файлами (`ac_bonuses_test.exs`, `feat_effect_receivers_test.exs`
  и соседи). Здесь — правило само по себе, чтобы оно не зависело от того, какие
  записи лежат в `priv/rules` сегодня.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data.Loader.NotAGap

  @described %{dodge: %{id: :dodge, description: "+1 dodge bonus to AC against…"}}

  defp decision(overrides \\ %{}) do
    Map.merge(
      %{
        "who" => "координатор",
        "why" => "синтетическая запись теста, не факт об игре",
        "quote" => "синтетическая запись теста, не факт об игре",
        "basis" => "feat_description"
      },
      overrides
    )
  end

  describe "решения нет — сторожу нечего проверять" do
    # Отсутствие решения — норма: его несут единицы записей из сотен.
    test "nil и не-map проходят молча" do
      assert NotAGap.verify!("файл: запись", nil) == :ok
      assert NotAGap.verify!("файл: запись", "почему бы и нет") == :ok
      assert NotAGap.verify!("файл: запись", []) == :ok
    end
  end

  describe "три поля обязательны всегда" do
    for field <- ~w(who why quote) do
      test "без `#{field}` сборка падает" do
        broken = Map.delete(decision(), unquote(field))

        assert_raise RuntimeError, ~r/non-empty `#{unquote(field)}`/, fn ->
          NotAGap.verify!("файл: запись", broken,
            bases: NotAGap.bases(),
            describes: {:dodge, @described}
          )
        end
      end

      test "пробелы вместо `#{field}` сборку тоже роняют" do
        broken = Map.put(decision(), unquote(field), "   ")

        assert_raise RuntimeError, ~r/non-empty `#{unquote(field)}`/, fn ->
          NotAGap.verify!("файл: запись", broken,
            bases: NotAGap.bases(),
            describes: {:dodge, @described}
          )
        end
      end
    end

    # Сообщение обязано называть и файл, и запись: сторож, не назвавший ни того,
    # ни другого, заставляет искать опечатку руками по семи файлам.
    test "сообщение называет файл и запись" do
      assert_raise RuntimeError, ~r/ac_bonuses\.json: dodge/, fn ->
        NotAGap.verify!("ac_bonuses.json: dodge", Map.delete(decision(), "who"),
          bases: NotAGap.bases(),
          describes: {:dodge, @described}
        )
      end
    end
  end

  describe "`basis` — довод, названный машиночитаемо" do
    test "словарь закрыт и сегодня в нём два довода" do
      assert NotAGap.bases() == ["feat_description", "world_state"]
    end

    test "довод вне словаря роняет сборку" do
      assert_raise RuntimeError, ~r/this file knows/, fn ->
        NotAGap.verify!("файл: запись", decision(%{"basis" => "потому что"}),
          bases: NotAGap.bases(),
          describes: {:dodge, @described}
        )
      end
    end

    # ⚠️ Семейство объявляет свой словарь само (`bases:`). Не объявило — поле
    # писать нельзя: поле, которого никто не читает, выглядит сделанной
    # работой и ничего не делает.
    test "семейство без словаря `basis` не принимает" do
      assert_raise RuntimeError, ~r/nothing reads it/, fn ->
        NotAGap.verify!("файл: запись", decision())
      end

      # ...а решение без него у такого семейства законно — ровно так живут
      # факты класса и запись оружия сиальской системы.
      assert NotAGap.verify!("файл: запись", Map.delete(decision(), "basis")) == :ok
    end

    test "семейство со словарём требует `basis` явно" do
      assert_raise RuntimeError, ~r/non-empty `basis`/, fn ->
        NotAGap.verify!("файл: запись", Map.delete(decision(), "basis"), bases: NotAGap.bases())
      end
    end
  end

  describe "довод `feat_description` держится на описании" do
    test "описание есть — решение принимается" do
      assert NotAGap.verify!("файл: запись", decision(),
               bases: NotAGap.bases(),
               describes: {:dodge, @described}
             ) == :ok
    end

    # 🔴 Главный сторож задачи 3.95. Довод говорит «описание уже всё сказало»;
    # у фита без описания он не объясняет ничего, и оговорка обязана остаться.
    test "описания нет — сборка падает" do
      assert_raise RuntimeError, ~r/which states none/, fn ->
        NotAGap.verify!("файл: запись", decision(),
          bases: NotAGap.bases(),
          describes: {:mute, %{mute: %{id: :mute, description: nil}}}
        )
      end
    end

    # ⚠️ Ветка, до которой живые данные не доходят: `strip_wiki_prose/1`
    # приводит пустую прозу к `nil` ещё в загрузчике фитов. Она здесь ради
    # источника, который однажды придёт мимо этой нормализации, — и без этого
    # теста была бы мёртвым кодом, о котором никто не знает.
    test "описание из одних пробелов описанием не считается" do
      assert_raise RuntimeError, ~r/which is empty/, fn ->
        NotAGap.verify!("файл: запись", decision(),
          bases: NotAGap.bases(),
          describes: {:blank, %{blank: %{id: :blank, description: "  \n "}}}
        )
      end
    end

    test "фита нет в словаре — сборка падает" do
      assert_raise RuntimeError, ~r/which states none/, fn ->
        NotAGap.verify!("файл: запись", decision(),
          bases: NotAGap.bases(),
          describes: {:no_such_feat, @described}
        )
      end
    end

    # ⚠️ Пустой словарь — это «файл фитов не приехал», а не «фита нет»: то же
    # различение, которое делает `BonusMarkup.id!/5`, и та же причина —
    # временно убранный справочник не имеет права обвинить разметку в опечатке.
    test "словаря фитов нет вовсе — сторож молчит" do
      assert NotAGap.verify!("файл: запись", decision(),
               bases: NotAGap.bases(),
               describes: {:dodge, %{}}
             ) == :ok
    end

    test "запись без своего фита довода `feat_description` нести не может" do
      assert_raise RuntimeError, ~r/names no feat/, fn ->
        NotAGap.verify!("файл: запись", decision(), bases: NotAGap.bases())
      end
    end

    # Второй довод словаря описания не требует: у `world_state` опора другая —
    # условие называет состояние мира, а не свойство билда.
    test "`world_state` описания не требует" do
      assert NotAGap.verify!("файл: запись", decision(%{"basis" => "world_state"}),
               bases: NotAGap.bases()
             ) == :ok
    end
  end
end
