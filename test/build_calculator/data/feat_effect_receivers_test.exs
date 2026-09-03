defmodule BuildCalculator.Data.FeatEffectReceiversTest do
  @moduledoc """
  `priv/rules/vanilla/feat_effect_receivers.json` — метка получателя эффекта
  фита (задача 3.93, 25.08.2026).

  Файл существует ради одного: снять оговорку `{:not_modelled, {:feat_bonus,
  id}}` там, где она говорит «прибавку в статы не считаем» про механику, ради
  которой у нас нет ни одного стата. Пятнадцать повторяемых фитов из
  восемнадцати говорили именно это — про урон, ДЦ ЧУЖОГО спасброска,
  метамагию, сопротивления и маскировку.

  ⚠️ **Направление риска здесь обратное всему остальному в проекте.** Обычно
  ошибка в данных добавляет лишнюю оговорку, а тут — УБИРАЕТ: неверная метка
  делает калькулятор молчаливее, чем он вправе быть, и снаружи это неотличимо
  от «посчитали». Поэтому сторожей четыре, все роняют сборку, и все проверяются
  здесь вызовом, а не чтением кода: несуществующий фит, дубль, пустой список
  получателей, отсутствующая цитата или источник.

  ⚠️ Живой состав файла (шестнадцать записей) тоже под тестом, и не как
  «сколько строк»: проверяется, что каждая помеченная механика объявлена
  в ЗАКРЫТОМ словаре `siala_41/classes.json` → `_receivers`, что ни одна
  сегодня не наша (иначе запись ничего не гасит и стоит зря), и что два
  повторяемых фита, которые метки сознательно НЕ получили, её действительно
  не имеют.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Data.Loader.Feats
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, GapReceivers}

  @source_file "vanilla/feat_effect_receivers.json"
  @json "priv/rules/#{@source_file}" |> File.read!() |> Jason.decode!()

  # ⚠️ Здесь стояло `@still_owed [:arcane_defense, :favored_enemy]` — «два
  # повторяемых фита, у которых оговорка обязана ОСТАТЬСЯ, их судьбу решает
  # отдельная задача 3.95». 3.95 (25.08.2026) её решила: оба получили запись,
  # но гасит их не метка, а РЕШЕНИЕ ВЛАДЕЛЬЦА (`not_a_gap`, довод
  # `feat_description`), а `affects` у обоих остался честным и НАШИМ.
  #
  # 🔴 Ключей два, потому что вопроса два: метка отвечает «есть ли у нас число,
  # в которое прибавка падает», решение — «обязаны ли мы признаться, что в него
  # не кладём». Подкрутить первое ради второго значило бы соврать о природе
  # факта ради числа в баннере.
  @by_decision [:arcane_defense, :favored_enemy]

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp known_receivers(ruleset) do
    vocabulary = GapReceivers.vocabulary(ruleset)

    MapSet.union(vocabulary.our, vocabulary.not_our)
  end

  describe "файл читается и доезжает до ruleset'а" do
    test "он в списке источников загрузчика" do
      assert @source_file in Loader.source_files()
    end

    # ⚠️ Ванильный файл виден ОБОИМ ruleset'ам — факт «Weapon specialization
    # даёт урон» правда про NWN1, а не про правку шарда. Тот же довод, что
    # у семи файлов разметки прибавок рядом.
    test "метки доехали до обоих ruleset'ов", %{siala: siala, vanilla: vanilla} do
      recorded =
        for entry <- @json["feats"], into: MapSet.new(), do: String.to_atom(entry["feat"])

      assert recorded |> MapSet.size() > 0
      assert MapSet.new(Map.keys(siala.feat_effect_receivers)) == recorded
      assert MapSet.new(Map.keys(vanilla.feat_effect_receivers)) == recorded
    end

    test "каждая запись называет существующий фит", %{siala: siala} do
      for entry <- @json["feats"] do
        id = String.to_atom(entry["feat"])

        assert Map.has_key?(siala.feats, id), "#{entry["feat"]}: такого фита в справочнике нет"
      end
    end

    # Метка — утверждение о механике, и без опоры её ставить нельзя. Сторож
    # на это стоит в загрузчике; здесь — что живой файл ему соответствует.
    test "у каждой записи непустая цитата и источник со страницей" do
      for entry <- @json["feats"] do
        assert is_binary(entry["quote"]) and String.trim(entry["quote"]) != "",
               "#{entry["feat"]}: метка без цитаты"

        assert entry["source"]["page"], "#{entry["feat"]}: метка без страницы-источника"
        assert entry["source"]["revid"], "#{entry["feat"]}: метка без revid"
        assert entry["why"], "#{entry["feat"]}: не сказано, почему получатель именно этот"
      end
    end
  end

  describe "словарь получателей — тот же единственный" do
    test "каждое имя объявлено в _receivers", %{siala: siala} do
      known = known_receivers(siala)

      for entry <- @json["feats"], receiver <- entry["affects"] do
        assert receiver in known,
               "#{entry["feat"]}: получатель #{receiver} не объявлен в siala_41/classes.json"
      end
    end

    # 🔴 Запись, называющая НАШ получатель, гасит оговорку ТОЛЬКО решением
    # владельца — иначе она не гасит ничего (правило «хватает одного нашего»)
    # и стоит зря. ⚠️ Здесь стояло «сегодня ни одна запись не называет наш
    # получатель»: верно до 3.95, а теперь таких две, и обе с `not_a_gap`.
    # Проверяется поэтому не состав файла, а СВЯЗКА двух ключей.
    test "наш получатель — только вместе с решением владельца", %{siala: siala} do
      our = GapReceivers.our(siala)

      for entry <- @json["feats"] do
        ours? = Enum.any?(entry["affects"], &(&1 in our))

        assert ours? == is_map(entry["not_a_gap"]),
               "#{entry["feat"]}: получатели #{inspect(entry["affects"])} и решение " <>
                 "владельца #{inspect(entry["not_a_gap"] != nil)} не согласуются — запись " <>
                 "с нашим получателем без решения не гасит ничего, а решение " <>
                 "у записи с чужим получателем ничего не добавляет"
      end
    end
  end

  describe "что это меняет на билде" do
    # 🔴 Обязательная проверка задания 3.93, дополненная 3.95: из восемнадцати
    # оговорок про эффект повторяемого фита не осталось ни одной.
    #
    # ⚠️ Здесь стояло `assert Enum.sort(said) == @still_owed` (две оставшиеся).
    # Ноль — число опасное: от «механизм умер» его отличает только контроль
    # ниже, поэтому он в том же тесте, а не соседним.
    test "билд со всеми повторяемыми фитами не говорит ни про кого", %{siala: siala} do
      assert repeatable_feat_bonus_gaps(siala) == []
    end

    # Положительный контроль к нулю выше, и он СИНТЕТИЧЕСКИЙ: у ruleset'а
    # отобраны обе половины механизма — и метки, и решения, — а билд тот же.
    # Живой пример здесь был бы ловушкой, на которой этот файл уже стоял
    # дважды: он молча перестаёт проверять в тот день, когда запись про него
    # заводят.
    test "снять метки и решения — и все восемнадцать возвращаются", %{siala: siala} do
      naked = Map.put(siala, :feat_effect_receivers, %{})
      said = repeatable_feat_bonus_gaps(naked)

      assert length(said) == 18
      assert Enum.sort(said) == Enum.sort(Map.keys(siala.feat_effect_receivers))
    end

    # Обратная половина 3.95: у двоих запись ЕСТЬ, получатель у неё НАШ,
    # и гасит её решение владельца — с доводом, который проверяет загрузчик.
    test "два фита гасятся решением владельца, а не меткой", %{siala: siala} do
      our = GapReceivers.our(siala)

      for id <- @by_decision do
        entry = Map.fetch!(siala.feat_effect_receivers, id)

        assert Enum.any?(entry["affects"], &(&1 in our)),
               "#{id}: получатель перестал быть нашим — тогда решение владельца лишнее"

        assert entry["not_a_gap"]["basis"] == "feat_description"
        assert entry["not_a_gap"]["who"] != ""
      end
    end

    # Одни и те же восемнадцать повторяемых фитов, объявленные с вещи: ровно
    # тот билд, на котором 3.93 считала свои пятнадцать.
    defp repeatable_feat_bonus_gaps(ruleset) do
      repeatable =
        for {id, feat} <- ruleset.feats, is_map(Map.get(feat, :repeatable)), do: id

      stats =
        Build.new(
          levels: List.duplicate(:fighter, 21),
          gear: Rules.Gear.new(feats: Enum.sort(repeatable))
        )
        |> Rules.compute(ruleset)

      for {:not_modelled, {:feat_bonus, id}} <- stats.gaps, do: id
    end
  end

  # --------------------------------------------------------------------------
  # Сторожа: ошибка в метке уводит в МОЛЧАНИЕ, значит обязана ронять сборку
  # --------------------------------------------------------------------------
  describe "сторожа загрузчика" do
    # ⚠️ У обоих фитов есть ключ `description`, и у второго он ПУСТ — это
    # синтетическая пара под сторож задачи 3.95, а не пример из справочника.
    # Живой фит без описания завтра его получит, и тест молча перестанет
    # проверять; выдуманный не получит никогда.
    @feats %{
      weapon_specialization: %{
        id: :weapon_specialization,
        description: "…gains a +2 damage bonus…"
      },
      undescribed_feat: %{id: :undescribed_feat, description: nil}
    }
    @known MapSet.new(["damage", "hp"])

    # Решение владельца в форме, которую сторож принимает: все четыре поля
    # на месте, довод из закрытого словаря.
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

    defp read(entries) do
      Feats.feat_effect_receivers(%{"feats" => entries}, @feats, @known)
    end

    defp good(overrides) do
      Map.merge(
        %{
          "feat" => "weapon_specialization",
          "affects" => ["damage"],
          "quote" => "…gains a +2 damage bonus…",
          "source" => %{"wiki" => "fandom", "page" => "Weapon specialization"}
        },
        overrides
      )
    end

    test "правильная запись читается" do
      assert %{weapon_specialization: %{"affects" => ["damage"]}} = read([good(%{})])
    end

    test "фит, которого нет, роняет сборку" do
      assert_raise RuntimeError, ~r/does not exist/, fn ->
        read([good(%{"feat" => "no_such_feat"})])
      end
    end

    test "дубль роняет сборку" do
      assert_raise RuntimeError, ~r/stated twice/, fn ->
        read([good(%{}), good(%{})])
      end
    end

    test "пустой или отсутствующий список получателей роняет сборку" do
      assert_raise RuntimeError, ~r/non-empty list/, fn -> read([good(%{"affects" => []})]) end

      assert_raise RuntimeError, ~r/non-empty list/, fn ->
        read([Map.delete(good(%{}), "affects")])
      end
    end

    test "получатель вне словаря роняет сборку" do
      assert_raise RuntimeError, ~r/neither `_receivers.our` nor/, fn ->
        read([good(%{"affects" => ["damge"]})])
      end
    end

    test "метка без цитаты роняет сборку" do
      assert_raise RuntimeError, ~r/carries no quote/, fn ->
        read([Map.delete(good(%{}), "quote")])
      end

      assert_raise RuntimeError, ~r/carries no quote/, fn ->
        read([good(%{"quote" => "   "})])
      end
    end

    test "метка без источника роняет сборку" do
      assert_raise RuntimeError, ~r/carries no source/, fn ->
        read([Map.delete(good(%{}), "source")])
      end
    end

    # --- сторож решения владельца (задача 3.95) ---------------------------

    test "решение владельца читается вместе с меткой" do
      assert %{weapon_specialization: %{"not_a_gap" => %{"basis" => "feat_description"}}} =
               read([good(%{"not_a_gap" => decision()})])
    end

    # 🔴 Главный сторож задачи 3.95, и он на СИНТЕТИЧЕСКОМ фите: довод
    # «описание уже всё сказало» держится ровно на том, что описание есть.
    # У фита без него решение владельца превращается в молчание — то есть
    # в единственный исход, который весь этот механизм не имеет права
    # произвести по случайности.
    test "довод «описание» у фита без описания роняет сборку" do
      assert_raise RuntimeError, ~r/which states none/, fn ->
        read([good(%{"feat" => "undescribed_feat", "not_a_gap" => decision()})])
      end
    end

    test "решение без автора, довода, цитаты или основания роняет сборку" do
      for field <- ["who", "why", "quote", "basis"] do
        assert_raise RuntimeError, ~r/non-empty `#{field}`/, fn ->
          read([good(%{"not_a_gap" => Map.delete(decision(), field)})])
        end
      end
    end

    test "основание вне закрытого словаря роняет сборку" do
      assert_raise RuntimeError, ~r/this file knows/, fn ->
        read([good(%{"not_a_gap" => decision(%{"basis" => "потому что"})})])
      end
    end

    # Второй довод словаря на месте и описания не требует: у `world_state`
    # опора другая (условие — состояние мира), и фит без описания ему
    # не помеха. Без этой строки сторож выглядел бы правилом «описание
    # обязательно всегда».
    test "довод world_state описания не требует" do
      assert %{undescribed_feat: _} =
               read([
                 good(%{
                   "feat" => "undescribed_feat",
                   "not_a_gap" => decision(%{"basis" => "world_state"})
                 })
               ])
    end

    # ⚠️ Отсутствующий файл — не ошибка: слой поверх корпуса, и его отсутствие
    # означает «меток не объявлено», то есть все оговорки на месте. Направление
    # то же, что у семи файлов разметки рядом.
    test "отсутствующий файл читается как отсутствие меток" do
      assert Feats.feat_effect_receivers(:missing, @feats, @known) == %{}
      assert Feats.feat_effect_receivers(%{"нет такого ключа" => 1}, @feats, @known) == %{}
    end
  end
end
