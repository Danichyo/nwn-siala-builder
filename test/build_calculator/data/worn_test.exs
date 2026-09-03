defmodule BuildCalculator.Data.WornTest do
  @moduledoc """
  Надетое как предмет — данные задач 3.41 и 3.42.

  Числа приходят с ДВУХ разных страниц Fandom, и разница между ними — не
  формальность, а причина, по которой щит не режет ловкость:

    * `Armor check penalty` — **в кэше**, таблица озаглавлена «Type of armor
      **or shield**», колонки `Base AC` и `Armor check penalty`. Обе сверяются
      здесь построчно с самим снапшотом: опечатка в одной цифре иначе доехала бы
      до чисел каждого билда и не уронила бы ничего;
    * `Maximum dexterity bonus` (revid 59855) — **в кэше НЕТ**, снята через
      `api.php`, как когда-то `Point buy` и `Ability cap`. Диффом её проверить
      нечем, и единственное, что тут можно сделать честно, — пометить это в
      данных и проверить, что пометка стоит.

  Ровно поэтому у категории `armor` три источника, а не один, и у каждого
  сказано, за какую колонку он отвечает.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader

  @cache_page "priv/wiki_cache/fandom/Armor check penalty.wikitext"

  setup_all do
    raw =
      [File.cwd!(), "priv/rules/siala_41/overrides.json"]
      |> Path.join()
      |> File.read!()
      |> Jason.decode!()

    %{
      worn: raw["gear"]["worn"],
      page: File.read!(Path.join(File.cwd!(), @cache_page)),
      siala: Data.ruleset!("siala_41"),
      vanilla: Data.ruleset!("vanilla")
    }
  end

  # Строки таблицы страницы: `|style="text-align:left"|<имя>||<база>||<штраф>`.
  # Разбирается только то, что нужно этой сверке, — колонки по порядку.
  defp page_base_ac(page), do: for({base, _penalty} <- page_rows(page), do: base)

  defp page_penalties(page), do: for({_base, penalty} <- page_rows(page), do: penalty)

  defp page_rows(page) do
    for line <- String.split(page, "\n"),
        String.starts_with?(line, ~s(|style="text-align:left"|)),
        [_name, base, penalty] = String.split(line, "||") do
      {String.trim(base) |> Integer.parse() |> elem(0), penalty_number(String.trim(penalty))}
    end
  end

  # ⚠️ У первых трёх строк в колонке штрафа стоит слово «none», а не число, и
  # читается оно нулём — «штрафа нет» и «штраф 0» это одно и то же утверждение.
  # ⚠️ Всё, что не «none» и не число, роняет сверку, а не считается нулём:
  # молча пропущенная строка — ровно та поломка, ради которой эта сверка и
  # написана.
  defp penalty_number("none"), do: 0

  defp penalty_number(text) do
    {number, ""} = Integer.parse(text)
    number
  end

  describe "база AC сверена со снапшотом страницы" do
    # 🔴 Двенадцать строк подряд, в порядке страницы: девять доспехов и три
    # щита. Именно так таблица и написана — «Type of armor **or shield**».
    test "двенадцать строк базы совпадают со страницей цифра в цифру", %{worn: worn, page: page} do
      ours =
        for category <- worn["categories"], item <- category["items"], do: item["base_ac"]

      assert ours == page_base_ac(page)
      assert ours == [0, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3]
    end

    # ⚠️ И то же число — уже после загрузчика: сверка сырого JSON со страницей
    # ничего не стоит, если до расчёта доезжает другое.
    test "загрузчик доносит те же двенадцать чисел", %{siala: siala, page: page} do
      ours =
        for category <- siala.gear.worn, item <- category.items, do: item.base_ac

      assert ours == page_base_ac(page)
    end
  end

  # Третья колонка той же таблицы (задача 3.42) — и сверяется она ровно так же,
  # построчно со снапшотом: ошибка в одной цифре уехала бы в шесть навыков
  # каждого билда и не уронила бы ничего.
  describe "штраф брони сверен со снапшотом страницы" do
    test "двенадцать строк штрафа совпадают со страницей цифра в цифру", %{
      worn: worn,
      page: page
    } do
      ours =
        for category <- worn["categories"],
            item <- category["items"],
            do: item["armor_check_penalty"]

      assert ours == page_penalties(page)

      # ⚠️ И то же число списком — чтобы сверка не зеленела на двух одинаково
      # сломанных сторонах. Первые три строки таблицы говорят «none» → 0,
      # а башенный щит отнимает больше лат: −10 против −8.
      assert ours == [0, 0, 0, -1, -2, -5, -7, -7, -8, -1, -2, -10]
    end

    test "загрузчик доносит те же двенадцать чисел", %{siala: siala, page: page} do
      ours =
        for category <- siala.gear.worn, item <- category.items, do: item.armor_check_penalty

      assert ours == page_penalties(page)
    end

    # Правило сложения — ОТДЕЛЬНОЕ предложение источника, а не колонка, поэтому
    # и цитата у него своя. Без неё «доспех и щит складываются» держалось бы
    # на памяти автора кода.
    test "цитата про сложение доспеха и щита лежит в данных", %{worn: worn, page: page} do
      quotes =
        for category <- worn["categories"],
            source <- category["sources"],
            source["where"] =~ "armor_check_penalty",
            do: source["quote"]

      assert Enum.any?(quotes, &(&1 =~ "both armor check penalties apply"))
      assert page =~ "both armor check penalties apply"
    end

    # ⚠️ Кому штраф достаётся — факт о НАВЫКЕ, и лежит он в другом файле
    # (`vanilla/skills.json`). Сверяется с тем же предложением той же страницы:
    # шесть названных поимённо, и два названных как исключение — не в их числе.
    test "шесть подверженных навыков совпадают с предложением страницы", %{
      siala: siala,
      page: page
    } do
      applied = for {id, %{armor_check_penalty: :applies}} <- siala.skills, do: id

      assert Enum.sort(applied) == [
               :hide,
               :move_silently,
               :parry,
               :pick_pocket,
               :set_trap,
               :tumble
             ]

      assert page =~
               "it applies to [[hide]], [[move silently]], [[parry]], [[pick pocket]], " <>
                 "[[set trap]], and [[tumble]]"

      # ...а исключения названы страницей отдельным предложением, и у нас они
      # не «просто не в списке», а прямо не подвержены.
      assert page =~
               "The only dexterity-based skills not on this list are " <>
                 "[[open lock]] and [[ride]]"

      for skill <- [:open_lock, :ride] do
        assert siala.skills[skill].armor_check_penalty == :none
      end
    end

    # 🔴 Здесь стояло «у Alchemy штраф неизвестен, и это сказано в данных»:
    # третий ответ `:unknown` держался на единственном навыке, про чей штраф
    # не высказалась ни одна вики. **Закрыто замером Dan 17.08.2026 (кейс P1):
    # «Штрафа нет»** — и это ровно тот случай, ради которого третий ответ
    # и заводился: ноль теперь НАЗВАН источником, а не подставлен нами.
    #
    # ⚠️ Сам третий ответ никуда не делся, просто остался без свидетеля
    # в данных. Механизм проверяется копией `priv/rules` без поля
    # (`Rules.SkillsTest`, describe «навык, про который источник не
    # высказался»), а здесь — что живые данные говорят именно «нет штрафа»,
    # и говорят это фактом с источником.
    test "у Alchemy штраф назван, и назван источником", %{siala: siala} do
      assert siala.skills[:alchemy].armor_check_penalty == :none
      refute "armor_check_penalty" in siala.skills[:alchemy].unknown_fields

      fact =
        Enum.find(siala.skills[:alchemy].siala_changes, &(&1["what"] == "armor_check_penalty"))

      assert fact["value"] == false
      assert fact["source"]["kind"] == "user"
      assert fact["status"] == "verified"
    end

    # ⚠️ И утверждение о корпусе целиком: третьего ответа в живых данных больше
    # нет ни у одного навыка ни в одном ruleset'е. Обязано упасть в тот день,
    # когда шард добавит навык без этого поля, — иначе значение посчитается
    # с нулевым штрафом молча.
    test "навыков с непрочитанным штрафом не осталось ни в одном ruleset'е", %{
      siala: siala,
      vanilla: vanilla
    } do
      for ruleset <- [siala, vanilla] do
        assert for({id, %{armor_check_penalty: :unknown}} <- ruleset.skills, do: id) == []

        # Положительный контроль: поле читается и различает две стороны, то
        # есть `== []` выше — ответ, а не пустой обход.
        assert ruleset.skills[:hide].armor_check_penalty == :applies
        assert ruleset.skills[:open_lock].armor_check_penalty == :none
      end
    end
  end

  # Сторож данных: у колонки источника пустых клеток нет ни у одной из
  # двенадцати строк, значит «поля нет» — всегда пропуск, а не «штрафа нет».
  # Проверяется через `Loader.load!/1` на копии `priv/rules` — тем же приёмом,
  # каким проверяются сторожа получателей и разметки прибавок.
  describe "загрузчик падает на предмете без штрафа и на положительном" do
    test "чистая копия грузится — иначе `assert_raise` ниже зеленел бы впустую" do
      assert %{"siala_41" => %{}} = Loader.load!(copy_rules())
    end

    test "предмет без поля роняет сборку" do
      root = edit_item(copy_rules(), "full_plate", &Map.delete(&1, "armor_check_penalty"))

      assert_raise RuntimeError, ~r/states no armor_check_penalty/, fn -> Loader.load!(root) end
    end

    # ⚠️ Положительное число под именем штрафа — это бонус к шести навыкам,
    # которого не давал никто. Знак ловится, а не подразумевается.
    test "положительный «штраф» роняет сборку" do
      root = edit_item(copy_rules(), "tower", &Map.put(&1, "armor_check_penalty", 10))

      assert_raise RuntimeError, ~r/a penalty is an integer at or below zero/, fn ->
        Loader.load!(root)
      end
    end
  end

  # Сторожа задачи 3.141: сиальские двойники общей секции. Каждый закрывает
  # свою молчаливую поломку, и все три проверяются на копии `priv/rules` —
  # тем же приёмом, что сторожа выше.
  describe "загрузчик падает на полуобъявленном сиальском слое" do
    # 🔴 Двойник без объявленной версии — это ровно тот дефект, который в этом
    # проекте ловили четыре раза за трое суток: число лежит, `status: verified`
    # стоит, а соединения с расчётом нет. Молчит оно так же, как опечатка.
    test "числа без названной версии ruleset'а роняют сборку" do
      root = edit_worn(copy_rules(), &Map.delete(&1, "siala_values_apply_to_ruleset"))

      assert_raise RuntimeError, ~r/no ruleset will ever read/, fn -> Loader.load!(root) end
    end

    # ⚠️ Половина колонки хуже её отсутствия: строка без предела читалась бы
    # как «без предела», то есть ловкость пошла бы в AC целиком.
    test "предел ловкости, названный не у всех предметов, роняет сборку" do
      root = edit_item(copy_rules(), "full_plate", &Map.delete(&1, "siala_max_dex"))

      assert_raise RuntimeError, ~r/half a column is worse than none of it/, fn ->
        Loader.load!(root)
      end
    end

    # 🔴 И то же про класс брони — но с ДРУГОЙ ценой: пропущенная строка не
    # «без класса», а «класс неизвестен», то есть оговорка на ровном месте.
    test "класс брони, названный не у всех предметов, роняет сборку" do
      root = edit_item(copy_rules(), "full_plate", &Map.delete(&1, "siala_weight_class"))

      assert_raise RuntimeError, ~r/reads like a hole in the data/, fn -> Loader.load!(root) end
    end

    # 🔴 Опечатка в классе — самая дорогая из трёх: «medum» читается как «не
    # средний», и Рейнджер молча получает бонусы, которых игра не даёт.
    test "класс вне объявленного словаря роняет сборку" do
      root = edit_item(copy_rules(), "chainmail", &Map.put(&1, "siala_weight_class", "medum"))

      assert_raise RuntimeError, ~r/does not declare/, fn -> Loader.load!(root) end
    end

    # ⚠️ И `null` тоже — потому что «поля нет» тут УЖЕ значит «слой не сказал»,
    # и второй способ сказать «ничего» с другим смыслом стоял бы в одну клавишу
    # от первого. «Типа нет вовсе» пишется словом.
    test "null под именем класса роняет сборку" do
      root = edit_item(copy_rules(), "none", &Map.put(&1, "siala_weight_class", nil))

      assert_raise RuntimeError, ~r/does not declare/, fn -> Loader.load!(root) end
    end

    # ⚠️ `unknown` — единственное слово, которое придумывает само ядро, и
    # означает оно «слой не сказал». Класс с таким именем стёр бы разницу между
    # ответом и его отсутствием.
    test "класс с именем «unknown» роняет сборку" do
      root =
        edit_worn(copy_rules(), fn worn ->
          categories =
            for category <- worn["categories"] do
              if category["id"] == "armor",
                do: Map.put(category, "siala_weight_classes", ["unknown"]),
                else: category
            end

          Map.put(worn, "categories", categories)
        end)

      assert_raise RuntimeError, ~r/the one word the core keeps/, fn -> Loader.load!(root) end
    end

    # ⚠️ И условие выдачи, потерявшее класс из своего списка, — тоже: правило,
    # которое не срабатывает ни разу, выглядит на экране как работающее.
    test "условие, теряющее выдачу на несуществующем классе, роняет сборку" do
      root = copy_rules()
      path = Path.join(root, "vanilla/feat_attack_bonuses.json")
      data = path |> File.read!() |> Jason.decode!()

      updated =
        put_in(
          data,
          ["dual_wield", "grants", Access.at(0), "condition", "lost_when_worn_armor_is_one_of"],
          ["mediumish"]
        )

      File.write!(path, Jason.encode!(updated))

      assert_raise RuntimeError, ~r/the exception would never fire/, fn -> Loader.load!(root) end
    end
  end

  defp edit_worn(root, fun) do
    path = Path.join(root, "siala_41/overrides.json")
    data = path |> File.read!() |> Jason.decode!()
    File.write!(path, Jason.encode!(put_in(data, ["gear", "worn"], fun.(data["gear"]["worn"]))))
    root
  end

  defp copy_rules do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp edit_item(root, item_id, fun) do
    path = Path.join(root, "siala_41/overrides.json")
    data = path |> File.read!() |> Jason.decode!()

    categories =
      for category <- data["gear"]["worn"]["categories"] do
        items =
          for item <- category["items"], do: if(item["id"] == item_id, do: fun.(item), else: item)

        Map.put(category, "items", items)
      end

    updated = put_in(data, ["gear", "worn", "categories"], categories)
    File.write!(path, Jason.encode!(updated))
    root
  end

  describe "предел ловкости: страницы в кэше нет, и это помечено" do
    # ⚠️ Требование задачи и уже сложившаяся практика (`_vanilla_constants_
    # confirmed.point_buy`, `gear.ability_bonus_cap`): страница, снятая через
    # `api.php`, помечается `in_cache: false`, иначе следующий, кто сверит
    # данные с кэшем, сочтёт запись выдуманной.
    test "источник предела ловкости назван ревизией и помечен как вне кэша", %{worn: worn} do
      armor = Enum.find(worn["categories"], &(&1["id"] == "armor"))
      source = Enum.find(armor["sources"], &(&1["where"] == "max_dex"))

      assert source["page"] == "Maximum dexterity bonus"
      assert source["revid"] == 59_855
      assert source["in_cache"] == false

      # Цитата про область действия лежит в данных целиком: на ней держатся три
      # числа, которые потолок НЕ трогает.
      assert source["quote"] =~ "applies only to AC"
      assert source["quote"] =~ "reflex saves"

      # ...а страница базы, наоборот, в кэше есть, и это тоже сказано.
      base = Enum.find(armor["sources"], &(&1["where"] == "base_ac"))
      assert base["in_cache"] == true
      assert File.exists?(Path.join(File.cwd!(), @cache_page))
    end

    # 🔴 У щитов колонки предела нет ВОВСЕ — не «пусто», а нет: таблица
    # источника озаглавлена «Type of armor». Сторож загрузчика роняет сборку,
    # если предмет такой категории назовёт `max_dex`; здесь проверяется само
    # состояние данных.
    test "щиты не называют предела, а доспехи называют все девять", %{worn: worn} do
      armor = Enum.find(worn["categories"], &(&1["id"] == "armor"))
      shield = Enum.find(worn["categories"], &(&1["id"] == "shield"))

      assert armor["caps_dexterity"] == true
      assert Enum.all?(armor["items"], &Map.has_key?(&1, "max_dex"))
      assert for(item <- armor["items"], do: item["max_dex"]) == [nil, 8, 6, 4, 4, 2, 1, 1, 1]

      assert shield["caps_dexterity"] == false
      refute Enum.any?(shield["items"], &Map.has_key?(&1, "max_dex"))
    end
  end

  describe "куда падает предмет" do
    # Категория обязана называть тип AC из того же списка, что предлагает поле
    # ввода: база, упавшая в несуществующий тип, исчезла бы молча. Загрузчик
    # это проверяет, здесь — что пары действительно названы.
    test "каждая категория падает в объявленный тип AC", %{siala: siala} do
      for category <- siala.gear.worn do
        assert category.ac_type in siala.gear.ac_types,
               "#{category.id} падает в тип #{category.ac_type}, которого нет в ac_types"
      end
    end

    # 🔴 `gear` — ОБЩАЯ секция обоих ruleset'ов (`@vanilla_sections`), и до
    # задачи 3.141 она раздавалась им байт в байт. Замер `AH1` это сломал: шард
    # переписал предел ловкости, а границу класса брони у ванили не выяснял
    # никто. Поэтому теперь секция общая, а два поля — нет, и проверять надо
    # ровно это: совпадает всё, кроме двух названных.
    test "у обоих ruleset'ов одни категории, одни имена и одна база", %{
      siala: siala,
      vanilla: vanilla
    } do
      refute vanilla.gear.worn == []

      assert for(c <- vanilla.gear.worn, do: c.id) == for(c <- siala.gear.worn, do: c.id)

      shape = fn worn ->
        for category <- worn, item <- category.items do
          {category.id, item.id, item.name, item.base_ac, item.armor_check_penalty}
        end
      end

      assert shape.(vanilla.gear.worn) == shape.(siala.gear.worn)
    end

    # ...и ровно два поля расходятся, каждое по своей причине.
    test "предел ловкости расходится в шести записях, класс брони — во всех", %{
      siala: siala,
      vanilla: vanilla
    } do
      caps = fn worn ->
        armor = Enum.find(worn, &(&1.id == :armor))
        for item <- armor.items, do: {item.id, item.max_dex, item.weight_class}
      end

      # Ванильные девять — Fandom «Maximum dexterity bonus» (revid 59855),
      # класса брони не знает никто.
      assert caps.(vanilla.gear.worn) == [
               {:none, nil, :unknown},
               {:padded, 8, :unknown},
               {:leather, 6, :unknown},
               {:studded_leather, 4, :unknown},
               {:chain_shirt, 4, :unknown},
               {:chainmail, 2, :unknown},
               {:splint_mail, 1, :unknown},
               {:half_plate, 1, :unknown},
               {:full_plate, 1, :unknown}
             ]

      # Сиальские девять — замер Dan 30.08.2026 (`GAME_CHECKS.md` → AH1).
      # Совпали `none`, `padded` и `full_plate`; остальные шесть переписаны.
      assert caps.(siala.gear.worn) == [
               {:none, nil, :none},
               {:padded, 8, :light},
               {:leather, 7, :light},
               {:studded_leather, 6, :light},
               {:chain_shirt, 5, :medium},
               {:chainmail, 4, :medium},
               {:splint_mail, 3, :heavy},
               {:half_plate, 2, :heavy},
               {:full_plate, 1, :heavy}
             ]
    end

    # 🔴 `:none` и `:unknown` — РАЗНЫЕ ответы, и это единственная строка, где их
    # видно рядом: «нулёвка» на Сиале типа не имеет вовсе, а у ванили класс
    # той же строки просто никем не назван.
    test "«типа нет вовсе» и «слой не сказал» не одно и то же", %{
      siala: siala,
      vanilla: vanilla
    } do
      item = fn ruleset ->
        ruleset.gear.worn
        |> Enum.find(&(&1.id == :armor))
        |> Map.fetch!(:items)
        |> Enum.find(&(&1.id == :none))
      end

      assert item.(siala).weight_class == :none
      assert item.(vanilla).weight_class == :unknown
    end

    # ⚠️ У щитов класса нет ни в одном ruleset'е, и это не пропуск: условие
    # Рейнджера говорит про доспех («medium or heavy armor»), щит в его
    # предложении не назван вовсе.
    test "щиты класса не несут ни в одном ruleset'е", %{siala: siala, vanilla: vanilla} do
      for ruleset <- [siala, vanilla] do
        shield = Enum.find(ruleset.gear.worn, &(&1.id == :shield))

        assert Enum.all?(shield.items, &(&1.weight_class == :unknown))
      end
    end

    # Имя строки — как её пишет страница, обеими половинами там, где их две.
    # ⚠️ id — ручка строки, а не имя одного доспеха: «studded leather, hide» это
    # ОДНА строка с одинаковыми числами, и выбирать между двумя именами значило
    # бы дописывать источник.
    test "имя предмета — строка страницы целиком", %{siala: siala} do
      armor = Enum.find(siala.gear.worn, &(&1.id == :armor))
      names = Map.new(armor.items, &{&1.id, &1.name})

      assert names[:studded_leather] == "Studded leather armor, Hide armor"
      assert names[:chain_shirt] == "Chain shirt, Scale mail"
      assert names[:full_plate] == "Full plate"
    end
  end
end
