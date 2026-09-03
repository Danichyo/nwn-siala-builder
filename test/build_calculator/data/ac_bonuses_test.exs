defmodule BuildCalculator.Data.AcBonusesTest do
  @moduledoc """
  Сторож ручной разметки `priv/rules/vanilla/ac_bonuses.json` (задача 3.11).

  Файл существует потому, что связи «умение → AC» в корпусе нет ни в одном поле.
  Сплошная разведка по 507 записям девяти файлов нашла её только прозой: в
  `description` фита, в колонке таблицы прогрессии класса, в `description`
  навыка, в `skill_bonuses_prose` расы. Значит числа сюда переносил человек, и
  проверять надо ровно то, что человек может испортить: что цитата **дословна**,
  а не пересказана, и что вердикт с величиной не разъехались.

  ⚠️ Цитата сверяется не с описанием сущности, а с **кэшем страницы**: половина
  фактов здесь стоит не в описании (таблицы классов, проза расы, страницы
  Сиалы), и сверка с описанием пропустила бы их молча.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader

  @markup "priv/rules/vanilla/ac_bonuses.json" |> File.read!() |> Jason.decode!()
  @feats "priv/rules/vanilla/feats.json" |> File.read!() |> Jason.decode!()
  @classes "priv/rules/vanilla/classes.json" |> File.read!() |> Jason.decode!()
  @skills "priv/rules/vanilla/skills.json" |> File.read!() |> Jason.decode!()
  # ⚠️ ДРУГОЙ classes.json — несёт `_receivers`, словарь получателей `affects`,
  # ОДИН на весь проект (задача 3.28).
  @shard_classes "priv/rules/siala_41/classes.json" |> File.read!() |> Jason.decode!()

  @verdicts ~w(applied counted_elsewhere not_modelled not_an_ac_bonus)
  @amount_kinds ~w(flat ability_modifier ac_at_class_level per_skill_ranks)
  @sources ~w(feat class skill race_feat)

  # Какая цитата чьей страницей подтверждается. Пар несколько, потому что у
  # записи бывает до трёх разных источников: сам эффект, его тип и условие,
  # при котором он пропадает, — и они лежат на разных страницах (тип песни
  # барда назван на Fandom, а таблица — на Сиале).
  @quote_sources %{
    "quote" => "source",
    "quote_2" => "source_2",
    "quote_siala" => "source_2",
    "type_quote" => "type_source",
    "scope_quote" => "scope_source",
    "quote_stacking" => "source"
  }

  defp entries, do: @markup["bonuses"]
  defp name(entry), do: entry["feat"] || entry["class"] || entry["skill"] || entry["race_feat"]

  defp cached!(source) do
    index =
      case source["wiki"] do
        "fandom" -> "priv/wiki_cache/fandom/_index.json"
        "siala" -> "priv/wiki_cache/siala/_index.json"
      end

    file =
      index
      |> File.read!()
      |> Jason.decode!()
      |> Enum.find(&(&1["title"] == source["page"]))
      |> case do
        %{"file" => file} -> file
        nil -> flunk("страницы #{source["page"]} нет в кэше — цитату не с чем сверить")
      end

    index |> Path.dirname() |> Path.join(file) |> File.read!()
  end

  describe "цитаты" do
    # Единственная проверка, ради которой этот файл тестируется вообще. Всё
    # остальное — про схему; эта — про честность.
    test "каждая цитата дословно лежит на своей странице в кэше" do
      for entry <- entries(),
          {quote_key, source_key} <- @quote_sources,
          quote = entry[quote_key] do
        source = entry[source_key] || entry["source"]

        assert String.contains?(cached!(source), quote),
               "#{name(entry)} / #{quote_key}: цитаты нет на странице #{source["page"]}"
      end
    end

    test "у каждой записи есть источник страницы с revid" do
      for entry <- entries() do
        assert entry["source"]["wiki"] in ~w(fandom siala)
        assert is_binary(entry["source"]["page"])
        assert is_integer(entry["source"]["revid"]), "#{name(entry)}: нет revid"
      end
    end

    # Решение про складывание одинаковых типов опирается на две цитаты, и обе
    # надо уметь предъявить: одна от игрока (лежит в overrides.json), вторая
    # со страницы Сиалы. Без второй правило выглядело бы как чьё-то мнение.
    test "решение про одинаковые типы AC подтверждено страницей Сиалы" do
      decision = @markup["_stacking_decision"]
      siala = Enum.find(decision["sources"], &(&1["kind"] == "wiki"))

      assert String.contains?(cached!(siala), decision["quote_2"])
      assert siala["page"] == "Расы"

      overrides = "priv/rules/siala_41/overrides.json" |> File.read!() |> Jason.decode!()
      assert String.contains?(overrides["gear"]["ac_types"]["note"], decision["quote"])
    end
  end

  describe "схема" do
    test "вердикт у каждой записи из известного набора" do
      for entry <- entries(), do: assert(entry["verdict"] in @verdicts)
    end

    test "у записи ровно один источник, и он существует" do
      known = %{
        "feat" => MapSet.new(@feats, & &1["id"]),
        "race_feat" => MapSet.new(@feats, & &1["id"]),
        "class" => MapSet.new(@classes, & &1["id"]),
        "skill" => MapSet.new(@skills, & &1["id"])
      }

      for entry <- entries() do
        keys = for key <- @sources, is_binary(entry[key]), do: key

        assert [key] = keys, "#{name(entry)}: источников #{length(keys)}, ожидался один"

        assert MapSet.member?(known[key], entry[key]),
               "#{name(entry)}: такого #{key} нет в справочнике"
      end
    end

    # Разведка ищет по прозе, и одну и ту же страницу легко записать дважды
    # под разными ключами.
    test "запись на каждую сущность одна" do
      pairs =
        for entry <- entries(), key <- @sources, is_binary(entry[key]), do: {key, entry[key]}

      assert pairs == Enum.uniq(pairs)
    end

    # Отвергнутая запись без причины через полгода читается как чей-то
    # недосмотр — и следующая разведка «починит» мнимый пропуск.
    test "у каждого отказа названа причина" do
      for entry <- entries(), entry["verdict"] in ~w(not_modelled not_an_ac_bonus) do
        assert is_binary(entry["why"]) and entry["why"] != "",
               "#{name(entry)}: вердикт #{entry["verdict"]} без причины"
      end

      for entry <- entries(), entry["verdict"] == "counted_elsewhere" do
        assert is_binary(entry["owned_by"]), "#{name(entry)}: не сказано, кто считает вместо неё"
        assert entry["owned_by"] in Enum.map(entries(), &name/1)
      end
    end

    # ⚠️ Ключ `type` у applied обязателен и МОЖЕТ быть null — это два разных
    # утверждения. Забытый ключ читался бы как «источник тип не называет», а
    # это заявление про страницу вики, которого никто не делал.
    test "у applied ключ type присутствует, и назначенный тип подтверждён цитатой" do
      for entry <- entries(), entry["verdict"] == "applied" do
        assert Map.has_key?(entry, "type"), "#{name(entry)}: applied без ключа type"

        if entry["type"] do
          assert is_binary(entry["type_quote"]),
                 "#{name(entry)}: тип назначен, а цитаты, из которой он взят, нет"
        end
      end
    end

    # ⚠️ `scope` был СТРОКОЙ до 09.08.2026, и ядро печатало про него оговорку.
    # Замер Dan сделал условие проверяемым, и поле стало объектом с `kind`.
    # Строка теперь роняет сборку — иначе применённое правило молча вернулось бы
    # в оговорку, и число поехало бы в сторону, которая билду выгодна.
    test "условие — объект с известным kind, а не строка" do
      kinds = Map.keys(@markup["_scope_kinds"]) |> Enum.reject(&String.starts_with?(&1, "_"))
      refute kinds == []

      scoped =
        for entry <- entries(), scope = entry["scope"] do
          assert is_map(scope), "#{name(entry)}: условие строкой — форма до 09.08.2026"

          assert scope["kind"] in kinds,
                 "#{name(entry)}: kind #{inspect(scope["kind"])} не описан"

          # Условие есть только у applied: у отвергнутой записи прибавки нет
          # вовсе, и отбирать нечего.
          assert entry["verdict"] == "applied", "#{name(entry)}: условие не у applied"

          {name(entry), scope}
        end

      # Положительный контроль: условие в файле вообще есть, иначе цикл выше
      # зеленел бы на пустом списке.
      assert Enum.map(scoped, &elem(&1, 0)) == ["monk_ac_bonus", "monk"]
    end

    # ⚠️ Типы, названные условием, обязаны быть теми, которые игрок МОЖЕТ ввести.
    # Тип, которого нет в блоке вещей, — условие, которое никогда не срабатывает,
    # то есть прибавка молча становится безусловной.
    test "условие ссылается на типы AC из блока вещей" do
      known = Data.ruleset!("siala_41").gear.ac_types

      for entry <- entries(), scope = entry["scope"], scope["kind"] == "no_ac_from_worn" do
        types = scope["ac_types"]

        assert is_list(types) and types != [], "#{name(entry)}: пустой список типов"

        for type <- types do
          assert String.to_existing_atom(type) in known,
                 "#{name(entry)}: тип #{type} игрок ввести не может"
        end
      end
    end

    # Решение про условие стоит на ЗАМЕРЕ, и то, чего замер не покрыл, названо
    # словами. ⚠️ Строка про «любой щит» обязана оставаться на месте: раньше это
    # было ДОПУЩЕНИЕ (щит, дающий 0 AC, от отсутствия щита не отличить), с
    # 19.08.2026 — снятое допущение с доводом, почему оно снято. Вычеркнуть
    # его значило бы потерять и то, и другое.
    test "решение про условие названо замером, с описью непокрытого" do
      decision = @markup["_scope_decision"]

      assert decision["source"] == %{
               "kind" => "user",
               "who" => "Dan",
               "date" => "2026-08-09",
               "where" => "тестовый сервер Сиалы"
             }

      assert is_list(decision["not_covered"]) and length(decision["not_covered"]) >= 3
      assert decision["assumption"] =~ "щит"
      assert Enum.any?(decision["not_covered"], &(&1 =~ "ТИП" or &1 =~ "тип"))
    end

    # 🔴 Сужение 19.08.2026 (задача 3.59): условие читает БАЗУ выбранного
    # предмета, а не вписанное число. Записано отдельным блоком, а не правкой
    # `measured` — замер 09.08.2026 остаётся тем, чем был, и переписывать его
    # задним числом нельзя: тогда исчезнет и сам факт пересмотра, и довод,
    # почему прежнее чтение было верным для своего времени.
    test "сужение 19.08.2026 записано рядом с замером, а не вместо него" do
      narrowed = @markup["_scope_decision"]["narrowed"]

      assert narrowed["source"] == %{
               "kind" => "user",
               "who" => "Dan",
               "date" => "2026-08-19",
               "where" => "собственный персонаж в игре (монах 33 / Мастер оружия 7)"
             }

      # Дословная цитата, на которой стоит правка, — обе половины: «числа не
      # влияют» и «если доспех не роба».
      assert narrowed["quote_dan_2"] =~ "исключительно на надетый щит и доспех"
      assert narrowed["quote_dan_1"] =~ "не нулевку"

      # ...и довод, что это сужение, а не отмена: замер 09.08 остаётся верным
      # для всего, что он видел.
      assert narrowed["why_it_does_not_undo_the_measurement"] =~ "09.08.2026"

      # Замер на месте и не переписан.
      assert @markup["_scope_decision"]["measured"]["cases"] != nil
    end

    test "величина стоит только там, где ей место, и только известной формы" do
      for entry <- entries() do
        case {entry["verdict"], entry["amount"]} do
          {"applied", amount} ->
            assert is_map(amount), "#{name(entry)}: applied без величины"
            assert amount["kind"] in @amount_kinds

          {"not_modelled", amount} ->
            if is_map(amount), do: assert(amount["kind"] in @amount_kinds)

          {_rejected, amount} ->
            refute is_map(amount),
                   "#{name(entry)}: у отвергнутой записи не должно быть величины"
        end
      end
    end

    # ⚠️ Таблицы здесь — ИТОГИ на уровне класса, а не ступени (в отличие от
    # `hp_at_class_level` в соседнем файле). Монотонность — не украшение: она
    # и есть отличие итога от приращения, и падение здесь означает, что кто-то
    # переписал таблицу в другом прочтении.
    test "таблицы по уровню класса монотонны и названный класс существует" do
      class_ids = MapSet.new(@classes, & &1["id"])

      for entry <- entries(),
          amount = entry["amount"],
          is_map(amount),
          amount["kind"] == "ac_at_class_level" do
        assert MapSet.member?(class_ids, amount["class"])

        steps =
          amount["ac_at_class_level"]
          |> Enum.map(fn {level, ac} ->
            assert {parsed, ""} = Integer.parse(level)
            assert is_integer(ac)
            {parsed, ac}
          end)
          |> Enum.sort()

        assert steps == Enum.sort_by(steps, &elem(&1, 1)),
               "#{name(entry)}: таблица не монотонна — её переписали как ступени?"
      end
    end
  end

  # ⚠️ Задача «пять файлов прибавок» (17.08.2026). Как и у трёх соседей
  # (кроме feat_skill_bonuses.json), гэп {:not_modelled, {:ac_bonus, id}}
  # строит `Rules.ArmorClass` — чужая граница (CLAUDE.md §8), и поле сегодня
  # не двигает ни один гэп ни у одного билда. Лежит материалом.
  describe "получатели факта (affects)" do
    defp known_receivers do
      MapSet.union(
        MapSet.new(Map.keys(@shard_classes["_receivers"]["our"])),
        MapSet.new(Map.keys(@shard_classes["_receivers"]["not_our"]))
      )
    end

    test "метка стоит ровно у not_modelled и нигде больше" do
      for entry <- entries() do
        case entry["verdict"] do
          "not_modelled" ->
            assert is_list(entry["affects"]) and entry["affects"] != [],
                   "#{name(entry)}: not_modelled без affects"

          _other ->
            refute Map.has_key?(entry, "affects"), "#{name(entry)}: affects у #{entry["verdict"]}"
        end
      end
    end

    test "каждый получатель — из закрытого словаря siala_41/classes.json" do
      known = known_receivers()

      for entry <- entries(), receiver <- entry["affects"] || [] do
        assert receiver in known, "#{name(entry)}: получатель #{receiver} вне словаря"
      end
    end

    # Снимок делит тринадцать записей ровно так, как их делит сам
    # `_conditional_decision` в файле: включаемые режимом/способностью/песней
    # — buff, пассивные и просто узкие по смыслу — ac (наше), верховая езда —
    # свой получатель mounted_combat.
    #
    # ⚠️ Было двенадцать до задачи 3.143 (30.08.2026): `small_stature`
    # добавлена (была `applied`, цитата обрезана перед условием «когда
    # противник крупнее персонажа») — получатель `ac`, та же корзина, что
    # у `dodge`/`mobility`/`battle_training_vs_giants`.
    test "снимок классификации тринадцати not_modelled записей" do
      by_name =
        for entry <- entries(), entry["verdict"] == "not_modelled", into: %{} do
          {name(entry), entry["affects"]}
        end

      assert by_name == %{
               "defensive_stance" => ["buff"],
               "barbarian_rage" => ["buff"],
               "shadow_evade" => ["buff"],
               "expertise" => ["buff"],
               "improved_expertise" => ["buff"],
               "dodge" => ["ac"],
               "mobility" => ["ac"],
               "battle_training_vs_giants" => ["ac"],
               "divine_shield" => ["buff"],
               "mounted_combat" => ["mounted_combat"],
               "epic_spell_epic_mage_armor" => ["buff"],
               "perform" => ["buff"],
               "small_stature" => ["ac"]
             }
    end

    test "affects доезжает до ruleset без изменения формы" do
      ruleset = Data.ruleset!("siala_41")
      unmodelled = Map.new(ruleset.ac_bonuses.unmodelled, &{&1.id, &1})

      assert unmodelled[:perform].affects == ["buff"]
      assert unmodelled[:dodge].affects == ["ac"]

      applied = Map.new(ruleset.ac_bonuses.applied, &{&1.id, &1})
      refute applied[:armor_skin].affects
    end
  end

  describe "загрузчик падает на получателе вне словаря" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      root = Path.join(dir, "rules")
      File.cp_r!("priv/rules", root)

      %{root: root, path: Path.join([root, "vanilla", "ac_bonuses.json"])}
    end

    test "получатель с опечаткой", %{root: root, path: path} do
      patch(path, "dodge", &Map.put(&1, "affects", ["acc"]))

      assert_raise RuntimeError, ~r/"acc".*neither/s, fn -> Loader.load!(root) end
    end

    test "affects строкой вместо списка", %{root: root, path: path} do
      patch(path, "dodge", &Map.put(&1, "affects", "ac"))

      assert_raise RuntimeError, ~r/Expected a non-empty list/, fn -> Loader.load!(root) end
    end
  end

  describe "разведка" do
    # Шапка `_sweep` — не украшение: по ней следующий человек решает, нужно ли
    # перепроверять корпус. Разошедшийся счёт значит, что решать он будет
    # по неправде.
    test "счётчики шапки сходятся с содержимым файла" do
      sweep = @markup["_sweep"]

      assert sweep["by_verdict"] == Enum.frequencies_by(entries(), & &1["verdict"])
      assert sweep["found"] == length(entries())

      # 299 + 66 + 25 фитов, 23 + 23 класса, 28 + 29 навыков, 7 + 7 рас.
      assert sweep["records_checked"] == 507
      assert length(sweep["corpus"]) == 9
    end

    # ⚠️ Список записей без типа лежит в шапке отдельно, и он обязан сходиться
    # с содержимым: по нему читают, скольким прибавкам гэп
    # `{:assumed, :ac_bonus_types_unstated}` относится.
    test "перечень applied без типа сходится с записями" do
      untyped =
        for entry <- entries(),
            entry["verdict"] == "applied",
            is_nil(entry["type"]),
            do: name(entry)

      assert Enum.sort(untyped) == Enum.sort(@markup["_type_decision"]["untyped_today"])
    end

    # ⚠️ И перечень ОТМЕЧЕННЫХ — тоже, по той же причине и на порядок важнее:
    # по нему читают, скольким прибавкам оговорка больше не относится. Задача
    # 3.90 (25.08.2026).
    test "перечень записей с подтверждённым складыванием сходится с записями" do
      marked =
        for entry <- entries(), is_map(entry["stacking_confirmed"]), do: name(entry)

      assert Enum.sort(marked) ==
               Enum.sort(@markup["_stacking_confirmed_decision"]["today"])
    end

    # 🔴 Сегодня отмечены ВСЕ четыре, и это состояние, а не инвариант. Строка
    # стоит здесь ровно затем, чтобы новая прибавка без типа и без отметки
    # стала видимым событием: тест упадёт и заставит либо отметить её
    # с источником, либо признать, что оговорка вернулась.
    test "сегодня отмечены все applied без типа — и это состояние, а не правило" do
      untyped = @markup["_type_decision"]["untyped_today"]
      marked = @markup["_stacking_confirmed_decision"]["today"]

      assert Enum.sort(untyped) == Enum.sort(marked)
    end

    # ⚠️ Отметка — единственный способ убрать оговорку с экрана, ничего не
    # посчитав, поэтому провенанс у неё обязателен и проверяется здесь, а не
    # только загрузчиком: сторож ловит форму, тест ловит содержание.
    test "у каждой отметки названы что, почему и чей это ответ" do
      for entry <- entries(), mark = entry["stacking_confirmed"] do
        assert is_list(mark["what"]) and mark["what"] != [],
               "#{name(entry)}: отметка не называет, ЧТО подтверждено"

        assert is_binary(mark["why"]) and String.trim(mark["why"]) != ""
        assert mark["status"] == "verified"

        for field <- ~w(kind who date) do
          assert is_binary(mark["source"][field]) and mark["source"][field] != "",
                 "#{name(entry)}: у источника отметки нет #{field}"
        end
      end
    end

    # 🔴 И то, чего отметка НЕ говорит: тип. Правило записи типа задачей 3.90
    # не тронуто, и если однажды кто-то «допишет» тип отмеченной записи по
    # смыслу — упадёт здесь, а не молча сдвинет число.
    test "отметка не назначает тип: у всех отмеченных он по-прежнему null" do
      for entry <- entries(), is_map(entry["stacking_confirmed"]) do
        assert is_nil(entry["type"]),
               "#{name(entry)}: подтверждено складывание, а тип назначен — это разные вещи"
      end
    end

    # Столкновение записей этого файла между собой ровно одно, и решение
    # _stacking_decision написано именно про него. Появится второе — решение
    # придётся перечитать.
    #
    # ⚠️ Задача 3.91 разделила `collision_today` на два ключа, потому что
    # столкновения стало ДВА разных: собственное с собственным (складываются,
    # замер E5) и собственное с вписанным числом (тоже складываются — кроме
    # одного вида, который приходит НЕ из этого файла). Здесь проверяется
    # только первое: второго среди записей файла нет вовсе, и это тоже
    # проверяется — ниже.
    test "перечень столкновений по типу сходится с записями" do
      collisions =
        for entry <- entries(),
            entry["verdict"] == "applied",
            type = entry["type"],
            not is_nil(type),
            reduce: %{} do
          acc -> Map.update(acc, type, [name(entry)], &[name(entry) | &1])
        end

      colliding = for {_type, names} <- collisions, length(names) > 1, n <- names, do: n

      assert Enum.sort(colliding) ==
               Enum.sort(@markup["_stacking_decision"]["collision_today"]["own_vs_own"])
    end

    # 🔴 И вторая половина того же утверждения: ни одна запись ЭТОГО файла
    # не конкурирует с вписанным игроком числом. Конкурирующий вид объявлен
    # в overrides.json (`own_vs_gear_by_kind`), и приходит он из сиальского
    # слоя — расовый бонус и оружие, — а не отсюда.
    #
    # ⚠️ Проверяется не текстом решения, а самими записями: у applied тип
    # обязан быть либо null (ни с чем не сталкивается), либо не тем, что игрок
    # вводит (size), либо таким, где правило — сумма.
    test "ни одна запись файла не конкурирует с вписанным числом" do
      overrides = "priv/rules/siala_41/overrides.json" |> File.read!() |> Jason.decode!()
      same_type = overrides["gear"]["ac_types"]["same_type"]
      typed_types = MapSet.new(overrides["gear"]["ac_types"]["value"])
      competing_kinds = Map.keys(same_type["own_vs_gear_by_kind"] || %{})

      assert same_type["own_vs_gear"] == "sum"
      assert competing_kinds == ["shield_ac"]

      # `shield_ac` — вид СИАЛЬСКОГО бонуса (races.json / systems.json), и у
      # записей этого файла такого поля нет вовсе: источник у них ровно один
      # из четырёх (feat / class / skill / race_feat).
      for entry <- entries(), entry["verdict"] == "applied" do
        refute Map.has_key?(entry, "kind"),
               "#{name(entry)}: у записи появился вид сиальского бонуса — перечитать 3.91"
      end

      # А типы у них такие, что вписанное число либо не встречается вовсе
      # (null, size), либо встречается и СКЛАДЫВАЕТСЯ (natural).
      for entry <- entries(), entry["verdict"] == "applied", type = entry["type"] do
        assert is_nil(type) or type not in typed_types or same_type["own_vs_gear"] == "sum",
               "#{name(entry)}: тип #{type} конкурирует с вписанным — решение 3.91 перечитать"
      end
    end

    # ⚠️ Решение по капу уклонения записано в шапке и утверждает, что сегодня
    # оно ни на что не влияет. Утверждение проверяемое — проверим, а не
    # поверим: применённой записи типа dodge быть не должно.
    test "решение по капу уклонения ни на что не влияет — и это так" do
      assert @markup["_dodge_cap_decision"]["effect_today"] =~ "НИКАКОГО"

      refute Enum.any?(entries(), &(&1["verdict"] == "applied" and &1["type"] == "dodge"))
    end

    # Ровно те три расхождения с бэклогом, ради которых разведка и делалась
    # сплошной. Проверяются по данным, а не по тексту заметки: `Defensive
    # awareness` и `Heroic shield` бэклог числил среди дающих AC.
    test "три расхождения с бэклогом стоят в файле как отказы" do
      by_name = Map.new(entries(), &{name(&1), &1})

      assert by_name["defensive_awareness"]["verdict"] == "not_an_ac_bonus"
      assert by_name["heroic_shield"]["verdict"] == "not_an_ac_bonus"

      # Третье: у `bone_skin` восемь ступеней, а не две, как писал бэклог по
      # нашим же granted_feats.
      assert map_size(by_name["bone_skin"]["amount"]["ac_at_class_level"]) == 8
    end
  end

  describe "загрузчик роняет сборку на битой разметке" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      root = Path.join(dir, "rules")
      File.cp_r!("priv/rules", root)

      %{root: root, path: Path.join([root, "vanilla", "ac_bonuses.json"])}
    end

    defp rewrite!(path, fun) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> fun.()
      |> Jason.encode!()
      |> then(&File.write!(path, &1))
    end

    defp patch(path, name, fun) do
      rewrite!(path, fn markup ->
        update_in(markup["bonuses"], fn entries ->
          Enum.map(entries, fn entry ->
            if name(entry) == name, do: fun.(entry), else: entry
          end)
        end)
      end)
    end

    # ⚠️ Положительный контроль ко всем падениям ниже: нетронутая копия обязана
    # грузиться, и разметка в ней обязана доехать. Без него `assert_raise`
    # зеленел бы и на копии, которая не грузится вовсе.
    test "нетронутая копия грузится, и разметка в ней есть", %{root: root} do
      ruleset = Loader.load!(root)["siala_41"]
      applied = Map.new(ruleset.ac_bonuses.applied, &{&1.id, &1})
      unmodelled = Map.new(ruleset.ac_bonuses.unmodelled, &{&1.id, &1})

      assert applied[:monk_ac_bonus].amount == %{kind: :ability_modifier, ability: :wis}
      assert applied[:armor_skin].amount == %{kind: :flat, ac: 2}
      assert applied[:armor_skin].type == :natural
      assert applied[:tumble].source == {:skill, :tumble}

      # ⚠️ small_stature стал not_modelled задачей 3.143 (30.08.2026) — цитата
      # в разметке была обрезана перед условием «когда противник крупнее
      # персонажа», и запись считалась безусловной.
      assert unmodelled[:small_stature].source == {:race_feat, :small_stature}
      assert :defensive_stance in Enum.map(ruleset.ac_bonuses.unmodelled, & &1.id)
    end

    test "имя несуществующего фита", %{root: root, path: path} do
      rewrite!(path, fn markup ->
        update_in(markup["bonuses"], &[%{"feat" => "not_a_feat", "verdict" => "applied"} | &1])
      end)

      assert_raise RuntimeError, ~r/not_a_feat/, fn -> Loader.load!(root) end
    end

    test "два источника в одной записи", %{root: root, path: path} do
      patch(path, "armor_skin", &Map.put(&1, "class", "monk"))

      assert_raise RuntimeError, ~r/2 sources/, fn -> Loader.load!(root) end
    end

    test "applied без величины", %{root: root, path: path} do
      patch(path, "armor_skin", &Map.delete(&1, "amount"))

      assert_raise RuntimeError, ~r/states no amount/, fn -> Loader.load!(root) end
    end

    # 🔴 Здесь стояло падение: applied-запись с типом «уклонение» роняла сборку,
    # потому что ядро прибавляло её ПОСЛЕ того, как потолок +20 уже применён
    # к числу с вещей, — то есть она прошла бы мимо потолка молча. Сторож стоял
    # вместо реализации; задача 3.39 реализацию написала (потолок применяется
    # к сумме собственного и вписанного, одним клипом), и сторож снят: он
    # отказывал бы корректным данным по причине, которой больше нет.
    #
    # ⚠️ Проверка осталась, но перевёрнута: теперь такая запись обязана
    # ГРУЗИТЬСЯ и доезжать до расчёта. Само правило (сумма и один клип) — в
    # `armor_class_test.exs`, здесь только то, что относится к загрузчику.
    test "applied с типом dodge грузится, а не роняет сборку", %{root: root, path: path} do
      patch(path, "armor_skin", &Map.put(&1, "type", "dodge"))

      applied = Map.new(Loader.load!(root)["siala_41"].ac_bonuses.applied, &{&1.id, &1})

      assert applied[:armor_skin].type == :dodge
    end

    # ------------------------------------- решение владельца not_a_gap (3.95) --
    #
    # 🔴 `not_a_gap` снимает запись со счёта пробелов — то есть это единственный
    # способ уменьшить число, которое видит игрок, ничего не посчитав. Задача
    # 3.95 добавила ему ВТОРОЙ довод (`basis: "feat_description"`), и он
    # проверяем: держится он на том, что описание фита называет и число,
    # и условие. У фита без описания довод не объясняет ничего, и оговорка
    # обязана остаться, — поэтому загрузчик роняет сборку.

    defp decision(overrides \\ %{}) do
      Map.merge(
        %{
          "who" => "координатор",
          "date" => "2026-08-25",
          "basis" => "feat_description",
          "quote" => "синтетическая запись теста, не факт об игре",
          "why" => "синтетическая запись теста, не факт об игре",
          "status" => "verified"
        },
        overrides
      )
    end

    test "живая запись Dodge несёт решение и до оговорок не доезжает", %{root: root} do
      ruleset = Loader.load!(root)["siala_41"]
      record = Enum.find(ruleset.ac_bonuses.unmodelled, &(&1.id == :dodge))

      # Вердикт и получатель прежние — решение стоит на своей оси, а не вместо
      # них: прибавка есть, мы её правда не считаем, и она правда про AC.
      assert record.verdict == :not_modelled
      assert record.affects == ["ac"]
      assert record.not_a_gap["basis"] == "feat_description"
    end

    for field <- ~w(who why quote basis) do
      test "решение без `#{field}` роняет сборку", %{root: root, path: path} do
        patch(path, "dodge", &Map.put(&1, "not_a_gap", Map.delete(decision(), unquote(field))))

        assert_raise RuntimeError, ~r/non-empty `#{unquote(field)}`/, fn -> Loader.load!(root) end
      end
    end

    test "довод вне закрытого словаря роняет сборку", %{root: root, path: path} do
      patch(path, "dodge", &Map.put(&1, "not_a_gap", decision(%{"basis" => "потому что"})))

      assert_raise RuntimeError, ~r/this file knows/, fn -> Loader.load!(root) end
    end

    # Запись, у которой источник не фит вовсе (Кувырок — навык): описание
    # проверить не на чем, и довод «описание всё сказало» бессмыслен.
    test "довод «описание» у записи без фита роняет сборку", %{root: root, path: path} do
      patch(path, "tumble", &Map.put(&1, "not_a_gap", decision()))

      assert_raise RuntimeError, ~r/names no feat/, fn -> Loader.load!(root) end
    end

    # 🔴 ГЛАВНЫЙ СТОРОЖ ЗАДАЧИ 3.95, и он на СИНТЕТИЧЕСКОМ фите: описание
    # у `Dodge` вычеркнуто в КОПИИ справочника, а не найдено пустым в живой.
    # Живой фит без описания завтра его получит, и тест молча перестал бы
    # проверять; вычеркнутое не вернётся само.
    test "довод «описание» у фита с пустым описанием роняет сборку", %{root: root} do
      feats = Path.join([root, "vanilla", "feats.json"])
      markup = Path.join([root, "vanilla", "ac_bonuses.json"])

      patch(markup, "dodge", &Map.put(&1, "not_a_gap", decision()))

      rewrite!(feats, fn list ->
        Enum.map(list, fn feat ->
          if feat["id"] == "dodge", do: Map.put(feat, "description", nil), else: feat
        end)
      end)

      assert_raise RuntimeError, ~r/which states none/, fn -> Loader.load!(root) end
    end

    # И обратная сторона того же сторожа: описание из одних пробелов
    # описанием не является. ⚠️ Сообщение здесь то же, что и у отсутствующего,
    # и это не небрежность: `Reading.strip_wiki_prose/1` приводит пустую прозу
    # к `nil` ещё в загрузчике фитов, то есть до сторожа такая строка доезжает
    # уже как «описания нет». Ветка `which is empty` в `Loader.NotAGap` живёт
    # для источника, который до этой нормализации не доходит.
    test "довод «описание» при описании из пробелов роняет сборку", %{root: root} do
      feats = Path.join([root, "vanilla", "feats.json"])
      markup = Path.join([root, "vanilla", "ac_bonuses.json"])

      patch(markup, "dodge", &Map.put(&1, "not_a_gap", decision()))

      rewrite!(feats, fn list ->
        Enum.map(list, fn feat ->
          if feat["id"] == "dodge", do: Map.put(feat, "description", "   "), else: feat
        end)
      end)

      assert_raise RuntimeError, ~r/which states none/, fn -> Loader.load!(root) end
    end

    # ⚠️ Семейство, которое словаря доводов не объявляет (факты класса), поля
    # `basis` нести не имеет права: поле, которого никто не читает, выглядит
    # решением, не будучи им.
    test "`basis` там, где его никто не читает, роняет сборку", %{root: root} do
      classes = Path.join([root, "siala_41", "classes.json"])

      rewrite!(classes, fn file ->
        update_in(file["classes"], fn list ->
          Enum.map(list, fn class ->
            update_in(class["changes"], fn changes ->
              Enum.map(changes || [], fn change ->
                case change["not_a_gap"] do
                  %{} = d -> Map.put(change, "not_a_gap", Map.put(d, "basis", "world_state"))
                  _ -> change
                end
              end)
            end)
          end)
        end)
      end)

      assert_raise RuntimeError, ~r/nothing reads it/, fn -> Loader.load!(root) end
    end

    # ---------------------------------------- отметка о складывании (3.90) --
    #
    # 🔴 Отметка снимает признание в неуверенности — то есть это единственный
    # способ уменьшить число, которое калькулятор показывает игроку, НЕ посчитав
    # ничего нового. Дисциплина у неё поэтому та же, что у `not_a_gap` (задачи
    # 3.74–3.76): без провенанса ею можно было бы гасить неудобные записи одной
    # строкой, и оговорки перестали бы что-либо значить.

    defp mark(overrides \\ %{}) do
      Map.merge(
        %{
          "what" => ["складывается со всем"],
          "why" => "потому что",
          "source" => %{"kind" => "user", "who" => "Dan", "date" => "2026-08-25"},
          "status" => "verified"
        },
        overrides
      )
    end

    defp mark_on(path, name, overrides),
      do: patch(path, name, &Map.put(&1, "stacking_confirmed", mark(overrides)))

    test "нетронутая копия несёт отметки у всех четырёх записей без типа", %{root: root} do
      applied = Map.new(Loader.load!(root)["siala_41"].ac_bonuses.applied, &{&1.id, &1})

      for id <- [:monk_ac_bonus, :monk, :bone_skin, :tumble] do
        assert is_map(applied[id].stacking_confirmed), "#{id}: отметка не доехала"
        assert is_nil(applied[id].type), "#{id}: тип назначен, а не должен"
      end

      # ...и у записи с названным типом её нет — там на вопрос отвечает тип.
      assert is_nil(applied[:armor_skin].stacking_confirmed)
    end

    test "отметка без what", %{root: root, path: path} do
      mark_on(path, "tumble", %{"what" => []})

      assert_raise RuntimeError, ~r/non-empty `what`/, fn -> Loader.load!(root) end
    end

    test "отметка без why", %{root: root, path: path} do
      mark_on(path, "tumble", %{"why" => "   "})

      assert_raise RuntimeError, ~r/non-empty `why`/, fn -> Loader.load!(root) end
    end

    test "отметка со статусом не verified", %{root: root, path: path} do
      mark_on(path, "tumble", %{"status" => "unclear"})

      assert_raise RuntimeError, ~r/only "verified"/, fn -> Loader.load!(root) end
    end

    test "отметка без источника", %{root: root, path: path} do
      mark_on(path, "tumble", %{"source" => nil})

      assert_raise RuntimeError, ~r/without a `source`/, fn -> Loader.load!(root) end
    end

    # Три поля источника проверяются поимённо: «kind: user» и «kind: wiki» —
    # факты разного качества, и провенанс без автора или даты не отличает одно
    # от другого.
    test "отметка с источником без kind, who или date", %{root: root, path: path} do
      for field <- ~w(kind who date) do
        mark_on(path, "tumble", %{
          "source" => Map.delete(mark()["source"], field)
        })

        assert_raise RuntimeError, ~r/no non-empty `#{field}`/, fn -> Loader.load!(root) end
      end
    end

    test "пустая цитата хуже отсутствующей", %{root: root, path: path} do
      mark_on(path, "tumble", %{"quote" => ""})

      assert_raise RuntimeError, ~r/empty stacking_confirmed.quote/, fn ->
        Loader.load!(root)
      end
    end

    # 🔴 Отметка на записи с НАЗВАННЫМ типом не делала бы ничего — оговорка
    # висит только на прибавках без типа, — и не делала бы этого МОЛЧА. Ровно
    # тот холостой ход, ради которого сторожи этого файла и стоят.
    test "отметка на записи с названным типом", %{root: root, path: path} do
      mark_on(path, "armor_skin", %{})

      assert_raise RuntimeError, ~r/on a typed record/, fn -> Loader.load!(root) end
    end

    # ...и на записи, которую никто не считает: у прибавки, не идущей в число,
    # соседей нет и подтверждать нечего.
    test "отметка на записи, которую никто не считает", %{root: root, path: path} do
      mark_on(path, "expertise", %{})

      assert_raise RuntimeError, ~r/has no neighbours/, fn -> Loader.load!(root) end
    end

    # ⚠️ А привязка потолка к типу — та же схема и то же правило «объявленное
    # обязано существовать»: пара, указывающая на потолок, которого никто не
    # называл, оставила бы тип без потолка МОЛЧА.
    test "потолок типа указывает на несуществующий ключ stat_caps", %{root: root} do
      overrides = Path.join([root, "siala_41", "overrides.json"])

      overrides
      |> File.read!()
      |> Jason.decode!()
      |> put_in(["gear", "ac_types", "ceilings", "value"], %{"dodge" => "no_such_cap"})
      |> Jason.encode!()
      |> then(&File.write!(overrides, &1))

      assert_raise RuntimeError, ~r/no such ceiling is stated/, fn -> Loader.load!(root) end
    end

    # ...и вторая половина той же пары: потолок, повешенный на тип, которого
    # игрок ввести не может, не сработал бы никогда.
    test "потолок типа указывает на тип вне блока вещей", %{root: root} do
      overrides = Path.join([root, "siala_41", "overrides.json"])

      overrides
      |> File.read!()
      |> Jason.decode!()
      |> put_in(["gear", "ac_types", "ceilings", "value"], %{"helmet" => "dodge_ac"})
      |> Jason.encode!()
      |> then(&File.write!(overrides, &1))

      assert_raise RuntimeError, ~r/not one the player can enter/, fn -> Loader.load!(root) end
    end

    # Правило столкновения тоже объявлено данными, и опечатка в нём молча
    # превратилась бы в «складываем всё» — то есть в поведение до задачи 3.39.
    test "неизвестный режим столкновения одинаковых типов", %{root: root} do
      assert_raise RuntimeError, ~r/own_vs_gear/, fn ->
        root |> patch_same_type("own_vs_gear", "average") |> Loader.load!()
      end
    end

    # ⚠️ И обратная сторона: режим, который ЯДРО не реализует, тоже роняет
    # сборку. `own_vs_own` ядро всегда складывает (замер E5), поэтому запись
    # «max» там ничего бы не изменила — объявление, которое ничего не значит,
    # хуже отсутствующего.
    test "режим own_vs_own, которого ядро не реализует", %{root: root} do
      assert_raise RuntimeError, ~r/only implements sum/, fn ->
        root |> patch_same_type("own_vs_own", "max") |> Loader.load!()
      end
    end

    # 🔴 Исключение из правила сложения объявляется ВИДОМ сиальского бонуса
    # (задача 3.91), и вид, который до AC вообще не доезжает, объявлял бы
    # правило, не срабатывающее никогда, — то есть выглядел бы применённым
    # и не был бы им.
    test "конкурирующий вид, который не даёт AC вовсе", %{root: root} do
      assert_raise RuntimeError, ~r/no shard bonus of that shape lands in armour class/, fn ->
        root
        |> patch_same_type("own_vs_gear_by_kind", %{"attack_bonus" => "max"})
        |> Loader.load!()
      end
    end

    # И опечатка в самом режиме — той же природы, что у `own_vs_gear` выше:
    # молча она означала бы «этот вид тоже складывается», то есть отмену
    # исключения без единого следа.
    test "неизвестный режим у конкурирующего вида", %{root: root} do
      assert_raise RuntimeError, ~r/own_vs_gear_by_kind\.shield_ac/, fn ->
        root
        |> patch_same_type("own_vs_gear_by_kind", %{"shield_ac" => "average"})
        |> Loader.load!()
      end
    end

    defp patch_same_type(root, key, value) do
      overrides = Path.join([root, "siala_41", "overrides.json"])

      overrides
      |> File.read!()
      |> Jason.decode!()
      |> put_in(["gear", "ac_types", "same_type", key], value)
      |> Jason.encode!()
      |> then(&File.write!(overrides, &1))

      root
    end

    # Ключ `type` обязателен именно как ключ: `null` — это ответ, отсутствие —
    # молчание, и различить их можно только так.
    test "applied без ключа type", %{root: root, path: path} do
      patch(path, "armor_skin", &Map.delete(&1, "type"))

      assert_raise RuntimeError, ~r/states no `type` key/, fn -> Loader.load!(root) end
    end

    test "неизвестная форма величины", %{root: root, path: path} do
      patch(path, "armor_skin", &put_in(&1, ["amount", "kind"], "per_moon_phase"))

      assert_raise RuntimeError, ~r/per_moon_phase/, fn -> Loader.load!(root) end
    end

    test "нецелое число AC", %{root: root, path: path} do
      patch(path, "armor_skin", &put_in(&1, ["amount", "ac"], "два"))

      assert_raise RuntimeError, ~r/whole number/, fn -> Loader.load!(root) end
    end

    test "несуществующая характеристика", %{root: root, path: path} do
      patch(path, "monk_ac_bonus", &put_in(&1, ["amount", "ability"], "luck"))

      assert_raise RuntimeError, ~r/ability luck/, fn -> Loader.load!(root) end
    end

    # 🔴 Самое дорогое падение из добавленных: строка вместо объекта — это форма
    # поля ДО 09.08.2026, и молча она означала бы «условие снова не применяется».
    # Прибавка вернулась бы в число монаха в доспехах, а оговорка про неё — нет,
    # то есть ошибка была бы в сторону, которая билду выгодна, и без единого
    # признака на экране.
    test "условие старой формы — строкой", %{root: root, path: path} do
      patch(path, "monk_ac_bonus", &Map.put(&1, "scope", "unarmored_and_no_shield"))

      assert_raise RuntimeError, ~r/states scope/, fn -> Loader.load!(root) end
    end

    test "условие с неизвестным kind", %{root: root, path: path} do
      patch(path, "monk_ac_bonus", &put_in(&1, ["scope", "kind"], "under_a_full_moon"))

      assert_raise RuntimeError, ~r/under_a_full_moon/, fn -> Loader.load!(root) end
    end

    # Тип, которого игрок ввести не может, — условие, которое не срабатывает
    # никогда: прибавка молча становится безусловной.
    test "условие на тип AC, которого нет в блоке вещей", %{root: root, path: path} do
      patch(path, "monk_ac_bonus", &put_in(&1, ["scope", "ac_types"], ["helmet"]))

      assert_raise RuntimeError, ~r/not one the player can enter/, fn -> Loader.load!(root) end
    end

    test "условие с пустым списком типов", %{root: root, path: path} do
      patch(path, "monk_ac_bonus", &put_in(&1, ["scope", "ac_types"], []))

      assert_raise RuntimeError, ~r/non-empty list of AC types/, fn -> Loader.load!(root) end
    end

    # 🔴 Вторая половина той же проверки, и она переехала вместе с правилом
    # 19.08.2026: условие читает БАЗУ надетого предмета, значит тип, в котором
    # надеть нечего, — условие, которое не срабатывает НИКОГДА. `deflection`
    # игрок ввести может (проверка выше его пропустит), а предмета такого типа
    # нет ни одного, и прибавка молча стала бы безусловной.
    test "условие на тип AC, в котором нечего надеть", %{root: root, path: path} do
      patch(path, "monk_ac_bonus", &put_in(&1, ["scope", "ac_types"], ["deflection"]))

      assert_raise RuntimeError, ~r/nothing can be worn in/, fn -> Loader.load!(root) end
    end
  end

  describe "оба ruleset'а несут разметку" do
    # Файл ванильный и накладывается на оба: отличий по AC у шарда нет ни
    # одного (`_sweep.shard_layer`), а вот УРОВЕНЬ выдачи монашеского фита
    # шард сдвинул — и это уже не здесь, а в `siala_41/classes.json`.
    test "разметка одинакова, а уровень выдачи Monk AC bonus — нет" do
      for version <- ~w(vanilla siala_41) do
        ruleset = Data.ruleset!(version)

        # ⚠️ Было 7 / 12 до задачи 3.143 (30.08.2026): `small_stature`
        # (Карлик/Гоблин, +1 за размер) перешёл из applied в unmodelled —
        # цитата в разметке была обрезана перед условием «когда противник
        # крупнее персонажа».
        assert length(ruleset.ac_bonuses.applied) == 6
        assert length(ruleset.ac_bonuses.unmodelled) == 13
      end

      granted_at = fn version ->
        Data.ruleset!(version).classes[:monk].granted_feats
        |> Enum.find_value(fn {level, feats} -> if :monk_ac_bonus in feats, do: level end)
      end

      assert granted_at.("vanilla") == 1
      assert granted_at.("siala_41") == 4
    end
  end
end
