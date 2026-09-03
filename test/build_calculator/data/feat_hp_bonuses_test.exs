defmodule BuildCalculator.Data.FeatHpBonusesTest do
  @moduledoc """
  Сторож ручной разметки `priv/rules/vanilla/feat_hp_bonuses.json` (задача 1.9).

  Файл существует потому, что связи «фит → HP» в корпусе нет ни в одном поле:
  все 299 записей `feats.json` держат её только английской прозой в
  `description`, а машиночитаемое рядом (`repeatable`) говорит про число взятий,
  а не про величину. Значит числа сюда переносил человек, и проверять надо ровно
  то, что человек может испортить: что цитата **дословна**, а не пересказана,
  и что вердикт с величиной не разъехались.

  ⚠️ Цитата сверяется не с `description`, а с **кэшем страницы**: половина
  фактов здесь стоит не в описании фита, а в примечаниях (`Deathless vigor`)
  или на странице класса. Сверка с описанием пропустила бы их молча, а сверка
  с кэшем ловит и пересказ, и опечатку в имени страницы.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader

  @markup "priv/rules/vanilla/feat_hp_bonuses.json" |> File.read!() |> Jason.decode!()
  @feats "priv/rules/vanilla/feats.json" |> File.read!() |> Jason.decode!()
  @classes "priv/rules/vanilla/classes.json" |> File.read!() |> Jason.decode!()
  # Словарь получателей `affects` — ОДИН на весь проект (задача 3.28).
  @shard_classes "priv/rules/siala_41/classes.json" |> File.read!() |> Jason.decode!()

  @verdicts ~w(applied counted_elsewhere not_modelled not_a_hp_bonus)
  @amount_kinds ~w(per_character_level per_take per_class_level)

  # Виды величины, которые ядро действительно считает. ⚠️ Здесь стояло
  # `~w(per_character_level per_take)` с оговоркой «`per_class_level` описан
  # в файле, но не применяется — это семейство классовых умений, задача 3.11».
  # Замер D1 (13.08.2026) показал, что у волшебника 5 / Бледного мастера 5
  # в игре 73 HP, а у нас 70, и форму пришлось научиться считать — ступени
  # к тому моменту уже лежали в файле выверенными.
  @applied_kinds ~w(per_character_level per_take per_class_level)

  defp entries, do: @markup["bonuses"]
  defp feat(id), do: Enum.find(@feats, &(&1["id"] == id))

  # Одна применённая запись разметки, как она доезжает до ядра — списком под
  # `ruleset.hp_bonuses`, а не полем фита (задача 3.25).
  defp record(ruleset, id), do: Enum.find(ruleset.hp_bonuses.applied, &(&1.id == id))

  defp cache_path(%{"wiki" => "fandom", "page" => page}), do: "priv/wiki_cache/fandom/#{page}"
  defp cache_path(%{"wiki" => "siala", "page" => page}), do: "priv/wiki_cache/siala/#{page}"

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

    source |> cache_path() |> Path.dirname() |> Path.join(file) |> File.read!()
  end

  describe "цитаты" do
    # Единственная проверка, ради которой этот файл тестируется вообще. Всё
    # остальное — про схему; это — про честность.
    test "каждая цитата дословно лежит на своей странице в кэше" do
      for entry <- entries() ++ @markup["_sweep"]["shard_layer_rejected"] do
        text = cached!(entry["source"])

        assert String.contains?(text, entry["quote"]),
               "#{entry["feat"]}: цитата не найдена на странице #{entry["source"]["page"]}"
      end
    end

    # Решение про пол — тоже факт со страницы, и цитата у него та же по
    # требованиям: наивный вариант («пол отдельно, прибавка сверху») даёт
    # другое число, и оправдание у выбранного — вот эта фраза.
    test "решение про поуровневый пол опирается на дословную цитату" do
      floor = @markup["_floor_decision"]

      assert String.contains?(cached!(floor["source"]), floor["quote"])
      assert floor["source"]["revid"] == 62_785
    end

    test "у каждой записи есть источник страницы с revid" do
      for entry <- entries() do
        assert entry["source"]["wiki"] in ~w(fandom siala)
        assert is_binary(entry["source"]["page"])
        assert is_integer(entry["source"]["revid"])
      end
    end
  end

  describe "схема" do
    test "вердикт у каждой записи из известного набора" do
      for entry <- entries(), do: assert(entry["verdict"] in @verdicts)
    end

    test "фит существует и упомянут не больше одного раза" do
      ids = Enum.map(entries(), & &1["feat"])

      assert ids == Enum.uniq(ids)

      for id <- ids, do: assert(feat(id), "#{id}: такого фита нет в vanilla/feats.json")
    end

    # Отвергнутая запись без причины через полгода читается как чей-то
    # недосмотр — и следующая разведка «починит» мнимый пропуск.
    test "у каждого отказа названа причина" do
      for entry <- entries(), entry["verdict"] in ~w(not_modelled not_a_hp_bonus) do
        assert is_binary(entry["why"]) and entry["why"] != "",
               "#{entry["feat"]}: вердикт #{entry["verdict"]} без причины"
      end
    end

    test "величина стоит только там, где ей место, и только известной формы" do
      for entry <- entries() do
        case {entry["verdict"], entry["amount"]} do
          {"applied", amount} ->
            assert is_map(amount), "#{entry["feat"]}: applied без величины"
            assert amount["kind"] in @applied_kinds

          {"not_modelled", amount} ->
            # Величина здесь необязательна, но если записана — та же схема.
            if is_map(amount), do: assert(amount["kind"] in @amount_kinds)

          {_rejected, amount} ->
            refute is_map(amount),
                   "#{entry["feat"]}: у отвергнутой записи не должно быть величины"
        end
      end
    end

    test "числа в величине целые, а названный класс существует" do
      class_ids = MapSet.new(@classes, & &1["id"])

      for entry <- entries(), amount = entry["amount"], is_map(amount) do
        for key <- ~w(hp max_total), value = amount[key], not is_nil(value) do
          assert is_integer(value), "#{entry["feat"]}: #{key} не целое"
        end

        if amount["kind"] == "per_class_level" do
          assert MapSet.member?(class_ids, amount["class"])

          for {level, hp} <- amount["hp_at_class_level"] do
            assert {_, ""} = Integer.parse(level)
            assert is_integer(hp)
          end
        end
      end
    end
  end

  # ⚠️ Задача «пять файлов прибавок» (17.08.2026). У ЭТОГО файла — единственного
  # из пяти — сегодня НЕТ ни одной записи `not_modelled` (задача 3.37,
  # 16.08.2026: `hit_die_increase` стал `counted_elsewhere`), значит и метку
  # ставить некуда. Проверяется тремя способами: что `affects` действительно
  # пуст по факту у всех записей, что схема тем не менее его описывает (на
  # случай, если not_modelled когда-нибудь появится), и что загрузчик готов
  # принять и проверить метку, если она появится, — заведённая, а не мёртвая,
  # инфраструктура.
  describe "получатели факта (affects)" do
    test "ни одна запись сегодня не несёт affects — not_modelled пуст" do
      assert Enum.all?(entries(), &is_nil(&1["affects"]))
      assert Enum.all?(entries(), &(&1["verdict"] != "not_modelled"))
    end

    test "схема описывает поле на будущее" do
      assert is_binary(@markup["_schema"]["affects"])
      assert @markup["_schema"]["affects"] =~ "_receivers"
    end

    # Положительный контроль инфраструктуры: загрузчик умеет читать affects у
    # ЭТОГО файла и роняет сборку на опечатке, хотя сегодня поле не занято
    # никем. Доказывает, что молчание файла — состояние данных, а не пробел
    # в загрузчике.
    test "загрузчик проверяет affects этого файла, если его добавить" do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      path = Path.join([root, "vanilla", "feat_hp_bonuses.json"])

      path
      |> File.read!()
      |> Jason.decode!()
      |> update_in(["bonuses"], fn entries ->
        Enum.map(entries, fn
          %{"feat" => "toughness"} = entry -> Map.put(entry, "affects", ["hp_typo"])
          entry -> entry
        end)
      end)
      |> Jason.encode!()
      |> then(&File.write!(path, &1))

      assert_raise RuntimeError, ~r/"hp_typo".*neither/s, fn -> Loader.load!(root) end
    end

    # Тот же словарь, что у четырёх соседей — не заведён здесь заново.
    test "словарь получателей общий с четырьмя соседями" do
      assert Map.has_key?(@shard_classes["_receivers"], "our")
      assert Map.has_key?(@shard_classes["_receivers"], "not_our")
      assert "hp" in Map.keys(@shard_classes["_receivers"]["our"])
    end
  end

  describe "разведка" do
    # Шапка `_sweep` — не украшение: по ней следующий человек решает, нужно ли
    # перепроверять корпус. Разошедшийся счёт значит, что решать он будет
    # по неправде.
    test "счётчики шапки сходятся с содержимым файла" do
      sweep = @markup["_sweep"]
      rejected = sweep["shard_layer_rejected"]
      by_verdict = Map.delete(sweep["by_verdict"], "_note")

      # Пустая категория считается нулём, а не отсутствует: шапка обязана
      # называть все четыре вердикта, иначе «в этой категории ничего нет»
      # и «эту категорию забыли посчитать» выглядят одинаково.
      # ⚠️ Пустая сегодня — `not_modelled`, а до 16.08.2026 была
      # `counted_elsewhere` (задача 3.37 поменяла их местами), поэтому нули
      # берутся из словаря `_verdicts`, а не из имени одной категории.
      empty = Map.new(Map.keys(@markup["_verdicts"]), &{&1, 0})

      counted =
        (entries() ++ rejected)
        |> Enum.frequencies_by(& &1["verdict"])
        |> then(&Map.merge(empty, &1))

      assert by_verdict == counted
      assert sweep["found"] == length(entries()) + length(rejected)

      # 299 ванильных + 66 машинных сиальских + 25 ручных сиальских.
      assert sweep["records_checked"] == 390
    end

    # Ровно тот факт, ради которого задача заведена: на Сиале фит выдаётся
    # даром десяти классам, значит недосчитывал HP почти каждый боевой билд.
    # ⚠️ Число проверяется по ruleset'у, а не по странице: восемь имён стоят
    # на вики, девятое (Гномий защитник) — ответ Dan от 01.08.2026.
    # ⚠️ 27.08.2026 (задача 3.127/3.129): десятый — Тайный лучник, найден
    # сверкой с хаками (`cls_feat_archer.2da`, `Free_Toughness`), не вики —
    # собственная страница класса о Toughness не говорит ни слова, источник
    # молчал полностью, а не расходился. `source.kind: "hak"` в
    # `siala_41/classes.json`.
    test "Toughness выдают десять классов, и в ванили — ни один" do
      siala = Data.ruleset!("siala_41")
      vanilla = Data.ruleset!("vanilla")

      granting = fn ruleset ->
        for {id, class} <- ruleset.classes,
            Enum.any?(Map.get(class, :granted_feats, %{}), fn {_lvl, feats} ->
              :toughness in feats
            end),
            into: MapSet.new(),
            do: id
      end

      assert granting.(siala) ==
               MapSet.new([
                 :arcane_archer,
                 :barbarian,
                 :blackguard,
                 :champion_of_torm,
                 :druid,
                 :dwarven_defender,
                 :fighter,
                 :paladin,
                 :ranger,
                 :weapon_master
               ])

      assert granting.(vanilla) == MapSet.new()
    end
  end

  describe "загрузчик роняет сборку на битой разметке" do
    setup do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      %{root: root, path: Path.join([root, "vanilla", "feat_hp_bonuses.json"])}
    end

    defp rewrite!(path, fun) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> fun.()
      |> Jason.encode!()
      |> then(&File.write!(path, &1))
    end

    # ⚠️ Положительный контроль ко всем трём падениям ниже: нетронутая копия
    # обязана грузиться. Без него `assert_raise` зеленел бы и на копии,
    # которая не грузится вовсе.
    test "нетронутая копия грузится, и прибавка в ней есть", %{root: root} do
      ruleset = Loader.load!(root)["siala_41"]

      # ⚠️ Записи лежат СПИСКОМ, а не полями фита — задача 3.25. До неё это было
      # `ruleset.feats[:toughness].hp_bonus`, и ровно из-за той формы у HP не было
      # ни вида источника, ни вердикта на записи.
      assert record(ruleset, :toughness).amount == %{kind: :per_character_level, hp: 1}
      assert record(ruleset, :epic_toughness).amount.max_total == 200
      # ⚠️ Здесь стояло `unmodelled` — до 13.08.2026 `deathless_vigor` был
      # непосчитанной оговоркой. Замер D1 его закрыл, и запись переехала
      # в применённые; проверяется вместе с величиной, иначе «переехала»
      # зеленело бы и у пустой ступеньки.
      vigor = record(ruleset, :deathless_vigor)
      assert vigor.amount.kind == :per_class_level
      assert vigor.amount.class == :pale_master
      assert vigor.amount.hp_at_class_level[5] == 3
      refute Enum.any?(ruleset.hp_bonuses.unmodelled, &(&1.id == :deathless_vigor))
    end

    # ⚠️ Потолка на HP не объявляет ни один ruleset (`stat_caps` называет пять, и
    # ни один из них не про хиты), поэтому сторона капа у записи — утверждение
    # ни о чём, и загрузчик её не пускает. Обратная сторона правила у навыков и
    # сейвов: там `cap` ОБЯЗАТЕЛЕН у applied.
    test "cap на записи роняет сборку — потолка на HP никто не объявлял", %{
      root: root,
      path: path
    } do
      rewrite!(path, fn markup ->
        update_in(markup["bonuses"], fn entries ->
          Enum.map(entries, fn
            %{"feat" => "toughness"} = entry ->
              Map.put(entry, "cap", %{"inside_cap" => false, "status" => "verified"})

            entry ->
              entry
          end)
        end)
      end)

      assert_raise RuntimeError, ~r/no ruleset states a ceiling on hit points/, fn ->
        Loader.load!(root)
      end
    end

    test "имя несуществующего фита", %{root: root, path: path} do
      rewrite!(path, fn markup ->
        update_in(markup["bonuses"], &[%{"feat" => "not_a_feat", "verdict" => "applied"} | &1])
      end)

      assert_raise RuntimeError, ~r/not_a_feat/, fn -> Loader.load!(root) end
    end

    # Самое дорогое из падений: без него запись `applied` с формой, которой
    # ядро не считает, дала бы молчаливый ноль — ровно та тишина, ради которой
    # весь файл и заведён.
    #
    # ⚠️ Ловушкой здесь стоял `deathless_vigor`, переведённый в `applied`, —
    # и 13.08.2026 это перестало быть ловушкой: замер D1 (волшебник 5 /
    # Бледный мастер 5 показывает 73, а не 70) заставил научить ядро форме
    # `per_class_level`, и запись стала законно применённой. Живого примера
    # «форма известна схеме, но ядру не по силам» в корпусе больше нет:
    # все три известные формы считаются.
    #
    # Поэтому сторож проверяется с ДРУГОЙ стороны — незнакомой формой. Защита
    # та же и та же по смыслу: форма, которой никто не научил, обязана уронить
    # сборку, а не превратиться в ноль. А инвариант «известное = применимое»,
    # который сегодня делает первую ловушку непостроимой, проверяется строкой
    # ниже — сломается он ровно в тот день, когда в схему добавят форму
    # и забудут про ядро.
    test "форма, которой загрузчик не знает", %{root: root, path: path} do
      rewrite!(path, fn markup ->
        update_in(markup["bonuses"], fn entries ->
          Enum.map(entries, fn
            %{"feat" => "toughness"} = entry ->
              put_in(entry, ["amount", "kind"], "per_moon_phase")

            entry ->
              entry
          end)
        end)
      end)

      assert_raise RuntimeError, ~r/per_moon_phase/, fn -> Loader.load!(root) end
    end

    test "сегодня каждая известная схеме форма ядру по силам" do
      assert Enum.sort(@amount_kinds) == Enum.sort(@applied_kinds)
    end

    test "applied без величины", %{root: root, path: path} do
      rewrite!(path, fn markup ->
        update_in(markup["bonuses"], fn entries ->
          Enum.map(entries, fn
            %{"feat" => "toughness"} = entry -> Map.delete(entry, "amount")
            entry -> entry
          end)
        end)
      end)

      assert_raise RuntimeError, ~r/states no amount/, fn -> Loader.load!(root) end
    end

    test "нецелое число хитов", %{root: root, path: path} do
      rewrite!(path, fn markup ->
        update_in(markup["bonuses"], fn entries ->
          Enum.map(entries, fn
            %{"feat" => "epic_toughness"} = entry ->
              put_in(entry, ["amount", "hp"], "двадцать")

            entry ->
              entry
          end)
        end)
      end)

      assert_raise RuntimeError, ~r/whole number/, fn -> Loader.load!(root) end
    end
  end
end
