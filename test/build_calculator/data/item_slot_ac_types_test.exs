defmodule BuildCalculator.Data.ItemSlotAcTypesTest do
  @moduledoc """
  Тип класса брони по слоту предмета — данные задач 3.187, 3.206, 3.213.

  Нужно своду экипировки из шардовой команды `.билд+`: лог печатает `AC Bonus`
  и не печатает, какого он типа, а типы между собой ведут себя по-разному
  (уклонение складывается, остальные спорят). Правило ванильное и лежит
  в общей секции `gear` — то есть достаётся **обоим** ruleset'ам. Тот же слот
  называет, какую категорию `gear.worn` означает база доспеха `[BaseAC:n]`
  (задача 3.213).

  🔴 **Две проверки этого файла держат его честным:**

    * цитаты сверяются с закэшированной страницей **посимвольно** — тот же
      приём, что у `Data.WornTest`: опечатка в переносе иначе доехала бы
      до чисел каждого импортированного билда и не уронила бы ничего;
    * список слотов сверяется с **четырьмя логами**: слот, который печатает
      игра, обязан быть в таблице. Иначе число из него молча уехало бы
      в `unresolved`, а игрок увидел бы «мы не знаем такого слота» про слот,
      который у него надет.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader

  @page "priv/wiki_cache/fandom/Armor class.wikitext"
  @logs ~w(hnyupius.log brunna.log moxie.log bor.log)

  setup_all do
    raw =
      [File.cwd!(), "priv/rules/siala_41/overrides.json"]
      |> Path.join()
      |> File.read!()
      |> Jason.decode!()

    %{
      declared: raw["gear"]["item_slot_ac_types"],
      page: File.read!(Path.join(File.cwd!(), @page)),
      siala: Data.ruleset!("siala_41"),
      vanilla: Data.ruleset!("vanilla")
    }
  end

  describe "источник" do
    test "каждая цитата стоит на странице посимвольно", %{declared: declared, page: page} do
      for key <- ~w(quote quote_armor quote_shield quote_dodge quote_natural quote_deflection) do
        assert String.contains?(page, declared[key]), "цитата #{key} на странице не найдена"
      end
    end

    test "источник назван ревизией, и она та же, что в кэше", %{declared: declared} do
      assert declared["source"]["page"] == "Armor class"
      assert declared["source"]["in_cache"] == true

      cached =
        [File.cwd!(), "priv/wiki_cache/fandom/_index.json"]
        |> Path.join()
        |> File.read!()
        |> Jason.decode!()
        |> Enum.find(&(&1["title"] == "Armor class"))

      assert cached["revid"] == declared["source"]["revid"]
    end
  end

  describe "таблица" do
    test "одиннадцать слотов, девять с типом и два без", %{siala: ruleset} do
      table = ruleset.gear.item_slot_ac_types

      assert length(table) == 11

      {named, unnamed} = Enum.split_with(table, & &1.ac_type)

      assert length(named) == 9
      assert Enum.map(unnamed, & &1.id) == [:arms, :left_hand]
    end

    # 🔴 Оба слота без типа — не пробел разведки: источник называет в каждом
    # по два разных предмета с разными типами (наручи или перчатки; щит или
    # что угодно другое). Поэтому альтернативы названы, а не пусты.
    test "слот без типа называет, между чем не решает", %{siala: ruleset} do
      table = ruleset.gear.item_slot_ac_types

      assert Enum.find(table, &(&1.id == :arms)).ac_type_alternatives == [:armor, :deflection]

      assert Enum.find(table, &(&1.id == :left_hand)).ac_type_alternatives == [
               :shield,
               :deflection
             ]
    end

    test "слот с типом альтернатив не называет", %{siala: ruleset} do
      for row <- ruleset.gear.item_slot_ac_types, row.ac_type do
        assert row.ac_type_alternatives == []
      end
    end

    test "каждый названный тип — из тех, что предлагает поле ввода", %{siala: ruleset} do
      for row <- ruleset.gear.item_slot_ac_types,
          type <- [row.ac_type | row.ac_type_alternatives],
          not is_nil(type) do
        assert type in ruleset.gear.ac_types
      end
    end

    test "ванили достаётся та же таблица", %{siala: siala, vanilla: vanilla} do
      assert vanilla.gear.item_slot_ac_types == siala.gear.item_slot_ac_types
    end
  end

  describe "сверка с игрой" do
    test "все слоты, которые печатают четыре лога, в таблице есть", %{siala: ruleset} do
      known = MapSet.new(ruleset.gear.item_slot_ac_types, & &1.log)

      observed =
        for file <- @logs,
            line <- log_lines(file),
            match = Regex.run(~r/^\[([A-Z]+)\] /u, line),
            into: MapSet.new(),
            do: Enum.at(match, 1)

      assert MapSet.subset?(observed, known)

      # …и наоборот: таблица не описывает слотов, которых игра не печатает.
      assert MapSet.equal?(observed, known)
    end
  end

  # Сторожа загрузчика. Все четыре — про молчаливую поломку: тип, которого нет
  # в списке ввода, исчез бы из суммы; слот без типа и без альтернатив сделал бы
  # «источник не решает» неотличимым от «мы не дочитали»; повтор id или токена
  # выкинул бы один из двух слотов вместе с его числом.
  describe "загрузчик роняет сборку" do
    test "на типе, которого игрок не вводит" do
      assert_raise RuntimeError, ~r/not one the player can enter/, fn ->
        load([%{"id" => "head", "log" => "HEAD", "ac_type" => "sonic"}])
      end
    end

    test "на альтернативе, которой нет в списке типов" do
      assert_raise RuntimeError, ~r/not one the player can enter/, fn ->
        load([
          %{"id" => "arms", "log" => "ARMS", "ac_type" => nil, "ac_type_alternatives" => ["luck"]}
        ])
      end
    end

    test "на слоте без типа и без альтернатив" do
      assert_raise RuntimeError, ~r/names no alternatives/, fn ->
        load([%{"id" => "arms", "log" => "ARMS", "ac_type" => nil}])
      end
    end

    test "на слоте, который назвал и тип, и альтернативы" do
      assert_raise RuntimeError, ~r/two answers to one question/, fn ->
        load([
          %{
            "id" => "head",
            "log" => "HEAD",
            "ac_type" => "deflection",
            "ac_type_alternatives" => ["armor"]
          }
        ])
      end
    end

    test "на повторённом слоте" do
      assert_raise RuntimeError, ~r/repeats id/, fn ->
        load([
          %{"id" => "head", "log" => "HEAD", "ac_type" => "deflection"},
          %{"id" => "head", "log" => "HELMET", "ac_type" => "deflection"}
        ])
      end
    end

    test "на повторённом токене лога" do
      assert_raise RuntimeError, ~r/repeats log token/, fn ->
        load([
          %{"id" => "head", "log" => "HEAD", "ac_type" => "deflection"},
          %{"id" => "belt", "log" => "HEAD", "ac_type" => "deflection"}
        ])
      end
    end
  end

  # У слота без своего типа ответ даёт БАЗОВЫЙ ТИП предмета, и записей на это
  # ТРИ, каждая про своё: категория надетого → тип (щит → щитовой) и запасной
  # тип для всего прочего опознанного (отклонение) — у `LEFTHAND`, задача 3.206;
  # НАПЕЧАТАННОЕ ИМЯ типа → тип — у `ARMS`, задача 3.213.
  # ⚠️ Здесь стояло «обе только у `LEFTHAND`: `ARMS` базового типа не печатает
  # и во втором поколении» — устарело 18.09.2026: третье поколение печатает
  # `(Bracer) [BaseItem:78]` и `(Gauntlet) [BaseItem:36]`.
  describe "тип по базовому типу предмета (3.206, 3.213)" do
    test "у LEFTHAND: щит → щитовой, остальное → отклонение", %{siala: ruleset} do
      left = Enum.find(ruleset.gear.item_slot_ac_types, &(&1.id == :left_hand))

      assert left.ac_type == nil
      assert left.ac_type_by_worn_category == %{shield: :shield}
      assert left.ac_type_otherwise == :deflection

      # ⚠️ И НАОБОРОТ: у второй руки нет записи «по напечатанному типу» —
      # там ответ даёт опознанный ПРЕДМЕТ, а не имя его типа, и две записи
      # отвечают на разные вопросы.
      assert left.ac_type_by_base_type == %{}
    end

    # 🔴 Здесь стояло «у ARMS пары нет — тип по-прежнему не решён»: устарело
    # 18.09.2026 (задача 3.213). Третье поколение `.билд+` печатает базовый тип
    # и в этом слоте, и две записи переводят его в тип AC — ключ НОРМАЛИЗОВАН
    # (нижний регистр, один пробел), тем же способом, каким свод сверяет имя.
    test "у ARMS: наручи → броня, перчатки → отклонение", %{siala: ruleset} do
      arms = Enum.find(ruleset.gear.item_slot_ac_types, &(&1.id == :arms))

      assert arms.ac_type == nil
      assert arms.ac_type_by_base_type == %{"bracer" => :armor, "gauntlet" => :deflection}

      # Категории надетого у `ARMS` нет: наручи и перчатки — не `gear.worn`.
      assert arms.ac_type_by_worn_category == %{}
      assert arms.ac_type_otherwise == nil
    end

    # ⚠️ Оба ответа обязаны стоять среди альтернатив, которые слот печатает
    # игроку: иначе интерфейс называет одно, а число уходит в другое.
    test "каждый ответ ARMS — из его же альтернатив", %{siala: ruleset} do
      arms = Enum.find(ruleset.gear.item_slot_ac_types, &(&1.id == :arms))

      for {_type, ac_type} <- arms.ac_type_by_base_type do
        assert ac_type in arms.ac_type_alternatives
      end
    end

    test "у девяти слотов с типом все три записи пусты", %{siala: ruleset} do
      for row <- ruleset.gear.item_slot_ac_types, not is_nil(row.ac_type) do
        assert row.ac_type_by_worn_category == %{}, inspect(row.id)
        assert row.ac_type_by_base_type == %{}, inspect(row.id)
        assert row.ac_type_otherwise == nil, inspect(row.id)
      end
    end

    # 🔴 Обе цитаты — посимвольно со страницы, тем же приёмом, что у цитат
    # выше: опечатка в переносе доехала бы до числа AC каждого импортированного
    # билда и не уронила бы ничего.
    test "каждая запись ARMS несёт свою цитату, и она стоит на странице",
         %{declared: declared, page: page} do
      rows =
        declared["slots"]
        |> Enum.find(&(&1["id"] == "arms"))
        |> Map.fetch!("ac_type_by_base_type")

      assert length(rows) == 2

      for row <- rows do
        assert row["status"] == "verified"
        assert String.contains?(page, row["quote"]), "цитата #{row["base_type"]} не найдена"

        # Строка `baseitems.2da` — расписка, а не ключ: у перчаток имя сервера
        # (`Gauntlet`) и метка хака (`gloves`) расходятся, и это записано.
        assert is_integer(row["base_item"])
        assert is_binary(row["hak_label"])
      end

      assert Enum.map(rows, & &1["hak_label"]) == ["bracer", "gloves"]
    end
  end

  # ------------------------------------------------ база доспеха (3.213) --

  describe "какую категорию называет [BaseAC:n]" do
    test "только CHEST, и только категорию armor", %{siala: ruleset} do
      table = ruleset.gear.item_slot_ac_types

      assert for(
               row <- table,
               row.worn_category_by_base_ac,
               do: {row.id, row.worn_category_by_base_ac}
             ) ==
               [{:chest, :armor}]
    end

    # 🔴 Без этого число указывало бы на две строки сразу, и выбор между ними
    # был бы нашей выдумкой. Девять доспехов несут 0…8 — и это инвариант,
    # а не наблюдение: сторож загрузчика роняет сборку на повторе.
    test "внутри категории base_ac уникален и покрывает 0…8", %{siala: ruleset} do
      %{items: items} = BuildCalculator.Rules.Worn.category(ruleset, :armor)
      bases = Enum.map(items, & &1.base_ac)

      assert bases == Enum.uniq(bases)
      assert Enum.sort(bases) == Enum.to_list(0..8)
    end

    test "ванили достаётся то же самое", %{siala: siala, vanilla: vanilla} do
      assert vanilla.gear.item_slot_ac_types == siala.gear.item_slot_ac_types
    end
  end

  # Сторожа пар «базовый тип → тип AC» (3.206). Сторожа базы доспеха и записей
  # `ac_type_by_base_type` стоят на КОПИИ `priv/rules`, потому что им нужен
  # настоящий `gear.worn` рядом — `Rules.GearImportTest`, «правила свода —
  # из данных, не из кода».
  describe "загрузчик роняет сборку на паре слота" do
    test "на паре у слота с собственным типом" do
      assert_raise RuntimeError, ~r/AND ac_type_by_worn_category/, fn ->
        load([
          %{
            "id" => "head",
            "log" => "HEAD",
            "ac_type" => "deflection",
            "ac_type_by_worn_category" => %{"shield" => "shield"}
          }
        ])
      end

      assert_raise RuntimeError, ~r/AND ac_type_otherwise/, fn ->
        load([
          %{
            "id" => "head",
            "log" => "HEAD",
            "ac_type" => "deflection",
            "ac_type_otherwise" => "armor"
          }
        ])
      end
    end

    test "на категории, которой gear.worn не объявляет" do
      assert_raise RuntimeError, ~r/gear.worn does not declare/, fn ->
        load([
          %{
            "id" => "left_hand",
            "log" => "LEFTHAND",
            "ac_type" => nil,
            "ac_type_alternatives" => ["shield", "deflection"],
            "ac_type_by_worn_category" => %{"buckler" => "shield"}
          }
        ])
      end
    end

    test "на типе запасного ответа, которого игрок не вводит" do
      assert_raise RuntimeError, ~r/not one the player can enter/, fn ->
        load([
          %{
            "id" => "left_hand",
            "log" => "LEFTHAND",
            "ac_type" => nil,
            "ac_type_alternatives" => ["shield", "deflection"],
            "ac_type_otherwise" => "luck"
          }
        ])
      end
    end
  end

  defp load(slots) do
    ov = %{
      "gear" => %{
        "ac_types" => %{"value" => ~w(armor shield deflection natural dodge)},
        "item_slot_ac_types" => %{"slots" => slots}
      }
    }

    Loader.Gear.gear(ov, "siala_41")
  end

  defp log_lines(file) do
    [_header, equipped] =
      [File.cwd!(), "test/fixtures/game_logs_plus", file]
      |> Path.join()
      |> File.read!()
      |> String.split("=== Equipped", parts: 2)

    String.split(equipped, "\n")
  end
end
