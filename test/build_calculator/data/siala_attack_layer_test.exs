defmodule BuildCalculator.Data.SialaAttackLayerTest do
  @moduledoc """
  Сиальская половина разметки прибавок к атаке — `siala_41/feat_attack_bonuses.json`
  (задача 4.46).

  Слой несёт одну ступень: колонка «AB bonus» Мастера оружия, 31 → +8. 🔴 Это
  **решение Dan** (кейс `BC1`, 27.09.2026: «игра потолок не ограничивает»),
  **а не замер**, — и файл обязан это говорить сам: у ступени статус `assumed`,
  блок `decision` с `kind: user` и список того, что не мерено.

  С задачи 4.57 — ещё две записи, числа шарда вместо ванильных: Point blank
  shot +5 (ваниль +1) и Called shot +2 (ваниль −4). Обе `not_modelled`
  и до печатаемого не доезжают (вызовом — `siala_hak_fixes_test.exs`); здесь
  держится их опора: цитата страницы Сиалы дословно в кэше вики, строка хака
  (`ruleset.2da`, метка, значение, `sha1` выгрузки) — в выгруженной таблице,
  и довод `not_a_gap` у Point blank shot — `world_state`, а не ванильный
  `feat_description`, который на шарде ложен.

  Что здесь держится и почему каждое:

    * **цитаты дословны** — открытое правило Fandom («at 13th level and every 3
      levels afterwards») и Сиалы («за каждые 3 уровня в классе после 10го»)
      сверяются с кэшем вики. Ступень стоит на названном шаге, а не на числах
      таблицы, и без цитаты была бы выдумкой (CLAUDE.md §3);
    * **у каждой ступени слоя — свой блок опоры**, и ступень лежит за концом
      ванильной таблицы, но не дальше потолка престижа Сиалы: ступень без опоры
      или ступень, переписывающая ванильную, — уже другое утверждение;
    * **положительный контроль**: без файла слоя у Сиалы ровно ванильная
      таблица и +7 на 31-м — то есть +8 приходит из этого файла и ниоткуда
      больше;
    * опечатка в имени записи роняет сборку (`Loader.Layers`), а без ванильного
      файла слою ложиться не на что — разметка пустая, а не одна сиальская
      ступень.

  ⚠️ Загрузка копии `priv/rules` — тем же приёмом, что `resistance_layer_test.exs`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.GameFiles.TwoDA

  @layer_file "siala_41/feat_attack_bonuses.json"

  # Читается во время теста, а не компиляции: без файла (положительный
  # контроль) падают тесты, а не сборка всего сьюта.
  defp layer, do: Path.join("priv/rules", @layer_file) |> File.read!() |> Jason.decode!()

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp copy_rules do
    root = BuildCalculator.TmpDir.unique_path!()
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp wm_steps(ruleset) do
    ruleset.attack_bonuses.applied
    |> Enum.find(&(&1.id == :weapon_master))
    |> get_in([:amount, :attack_at_class_level])
  end

  defp layer_record, do: Enum.find(layer()["bonuses"], &(&1["class"] == "weapon_master"))

  defp shard_steps, do: layer_record()["amount"]["attack_at_class_level_shard_steps"]

  defp cached!(source) do
    index =
      case source["wiki"] do
        "fandom" -> "priv/wiki_cache/fandom/_index.json"
        "siala" -> "priv/wiki_cache/siala/_index.json"
      end

    entry =
      index
      |> File.read!()
      |> Jason.decode!()
      |> Enum.find(&(&1["title"] == source["page"]))

    assert entry, "страницы #{source["page"]} нет в кэше — цитату не с чем сверить"
    assert entry["revid"] == source["revid"], "#{source["page"]}: revid в кэше другой"

    index |> Path.dirname() |> Path.join(entry["file"]) |> File.read!()
  end

  defp squeeze(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  describe "ступень 31 → +8 у Сиалы, у ванили таблица не сдвинута" do
    test "Сиала — ванильная таблица плюс одна ступень; ваниль — ровно Fandom", %{
      siala: siala,
      vanilla: vanilla
    } do
      fandom = %{5 => 1, 13 => 2, 16 => 3, 19 => 4, 22 => 5, 25 => 6, 28 => 7}

      assert wm_steps(vanilla) == fandom
      assert wm_steps(siala) == Map.put(fandom, 31, 8)

      # ⚠️ Слой только дописывает: записей у Сиалы ровно те же и в том же
      # порядке. Пустой список `bonuses` в файле слоя по правилу `Layers`
      # («пустой список сверху — ответ „ничего“») заменил бы ВСЮ разметку
      # Сиалы, и это поймала бы ровно эта строка.
      for bucket <- [:applied, :unmodelled, :counted_elsewhere] do
        ids = fn rs -> rs.attack_bonuses |> Map.fetch!(bucket) |> Enum.map(& &1.id) end
        assert ids.(siala) == ids.(vanilla), "#{bucket}"
      end
    end

    # 🔴 Положительный контроль: число приходит из ЭТОГО файла. Без него у Сиалы
    # ровно ванильная колонка — и, значит, тест выше падает от удаления записи.
    test "без файла слоя у Сиалы ванильная таблица", %{vanilla: vanilla} do
      root = copy_rules()
      File.rm!(Path.join(root, @layer_file))

      assert wm_steps(Loader.load!(root)["siala_41"]) == wm_steps(vanilla)
    end

    test "опечатка в имени записи роняет сборку" do
      root = copy_rules()
      path = Path.join(root, @layer_file)

      broken =
        update_in(layer()["bonuses"], fn bonuses ->
          for b <- bonuses do
            if b["class"] == "weapon_master", do: Map.put(b, "class", "weapon_mastr"), else: b
          end
        end)

      File.write!(path, Jason.encode!(broken))

      assert_raise RuntimeError, ~r/class="weapon_mastr".*lands on nothing/s, fn ->
        Loader.load!(root)
      end
    end

    # Ложиться не на что: `Layers.merge(:missing, слой)` отдал бы одну сиальскую
    # ступень без вердикта и без колонки. Контракт отсутствующего файла
    # разметки — пустые корзины (`feat_attack_bonuses_test.exs`).
    test "без ванильного файла слою ложиться не на что — разметка пустая" do
      root = copy_rules()
      File.rm!(Path.join(root, "vanilla/feat_attack_bonuses.json"))

      assert Loader.load!(root)["siala_41"].attack_bonuses ==
               %{applied: [], unmodelled: [], counted_elsewhere: []}
    end
  end

  describe "опора ступени — решение, не замер" do
    test "у каждой ступени слоя свой блок опоры, и число в нём то же", %{vanilla: vanilla} do
      steps = layer_record()["amount"]["attack_at_class_level"]
      blocks = shard_steps()

      assert Map.keys(steps) |> Enum.sort() == Map.keys(blocks) |> Enum.sort()

      last_vanilla = vanilla |> wm_steps() |> Map.keys() |> Enum.max()
      siala_cap = Data.ruleset!("siala_41").prestige.level_cap

      for {level, value} <- steps do
        class_level = String.to_integer(level)

        # Слой не переписывает ванильные ступени — только дописывает за концом
        # таблицы, и не дальше, чем престиж-класс Сиалы вообще доходит.
        assert class_level > last_vanilla, "ступень #{level} переписывает ванильную"
        assert class_level <= siala_cap, "ступень #{level} за потолком престижа Сиалы"

        assert blocks[level]["value"] == value
      end
    end

    # 🔴 Решение владельца — не замер (data-miner: «статус не поднимай до
    # verified»). И список того, что не мерено, непуст: его отсутствие
    # выглядело бы как проверенное.
    test "статус assumed, решение Dan BC1, список непомеренного" do
      for {level, block} <- shard_steps() do
        assert block["status"] == "assumed", level

        assert %{"kind" => "user", "who" => "Dan", "date" => "2026-09-27", "case" => "BC1"} =
                 block["decision"]

        assert [_ | _] = block["not_measured"], level
      end
    end

    test "цитаты Fandom и Сиалы дословно лежат на своих страницах в кэше" do
      for {_level, block} <- shard_steps(),
          {quote_key, source_key} <- [
            {"quote", "source"},
            {"quote_2", "source_2"},
            {"quote_3", "source_3"}
          ] do
        source = block[source_key]

        assert String.contains?(squeeze(cached!(source)), squeeze(block[quote_key])),
               "#{quote_key}: цитаты нет на странице #{source["page"]}"
      end
    end
  end

  # ------------------------------------------------------- задача 4.57 --

  describe "Point blank shot и Called shot — числа шарда (задача 4.57)" do
    # feat → {число шарда, ванильное число}
    @shard_numbers %{"point_blank_shot" => {5, 1}, "called_shot" => {2, -4}}

    defp shard_record(feat), do: Enum.find(layer()["bonuses"], &(&1["feat"] == feat))

    defp unmodelled(ruleset, id),
      do: Enum.find(ruleset.attack_bonuses.unmodelled, &(&1.id == id))

    test "у Сиалы числа шарда, у ванили — Fandom; слой переписывает только своё", %{
      siala: siala,
      vanilla: vanilla
    } do
      for {feat, {shard, base}} <- @shard_numbers do
        id = String.to_existing_atom(feat)
        record = shard_record(feat)

        assert record["amount"] == %{"bonus" => shard}
        assert unmodelled(siala, id).amount == %{kind: :flat, bonus: shard}
        assert unmodelled(vanilla, id).amount == %{kind: :flat, bonus: base}

        # Слой — только отличия: вердикт, условие и получатель — ванильные.
        refute Map.has_key?(record, "verdict")
        refute Map.has_key?(record, "condition")
        refute Map.has_key?(record, "affects")
        assert record["status"] == "verified"
      end
    end

    test "цитата страницы Сиалы дословно лежит в кэше и называет число шарда" do
      for {feat, {shard, _base}} <- @shard_numbers do
        record = shard_record(feat)

        assert %{"wiki" => "siala", "kind" => "wiki"} = record["source"]

        assert String.contains?(squeeze(cached!(record["source"])), squeeze(record["quote"])),
               "#{feat}: цитаты нет на странице #{record["source"]["page"]}"

        assert record["quote"] =~ "+#{shard}"
      end
    end

    # 🔴 Довод «описание фита уже назвало число» на Сиале ложен: игрок видит
    # описание Fandom с ванильным числом. Станет описание у Сиалы своим —
    # этот тест покраснеет, и довод стоит пересмотреть обратно.
    test "довод Point blank shot у Сиалы — world_state, у ванили — feat_description", %{
      siala: siala,
      vanilla: vanilla
    } do
      assert unmodelled(siala, :point_blank_shot).not_a_gap["basis"] == "world_state"
      assert unmodelled(vanilla, :point_blank_shot).not_a_gap["basis"] == "feat_description"

      assert unmodelled(siala, :point_blank_shot).not_a_gap ==
               shard_record("point_blank_shot")["not_a_gap"]

      description = siala.feats[:point_blank_shot].description
      assert description =~ "+1 to attack roll"
      refute description =~ "+5"

      # У Called shot довода нет ни у ванили, ни у Сиалы: оговорку гасит
      # получатель `buff`, а он от числа не зависит.
      assert unmodelled(siala, :called_shot).not_a_gap == nil
      assert unmodelled(siala, :called_shot).affects == ["buff"]
    end

    # 🔴 Положительный контроль: числа приходят из ЭТОГО файла. Без двух
    # записей у Сиалы снова ванильные +1 и −4.
    test "без записей 4.57 в слое у Сиалы ванильные числа", %{vanilla: vanilla} do
      root = copy_rules()
      path = Path.join(root, @layer_file)

      stripped =
        update_in(layer()["bonuses"], fn bonuses ->
          Enum.reject(bonuses, &Map.has_key?(@shard_numbers, &1["feat"]))
        end)

      File.write!(path, Jason.encode!(stripped))
      siala = Loader.load!(root)["siala_41"]

      for {feat, _numbers} <- @shard_numbers do
        id = String.to_existing_atom(feat)
        assert unmodelled(siala, id) == unmodelled(vanilla, id)
      end
    end
  end

  describe "Point blank shot и Called shot — строки хака (задача 4.57)" do
    @hak Path.expand("../../../priv/hak/2da", __DIR__)
    @base Path.expand("../../../priv/base_2da", __DIR__)

    unless File.regular?(Path.join(@hak, "manifest.json")) and
             File.regular?(Path.join(@base, "ruleset.2da")) do
      @describetag skip:
                     "нет priv/hak или priv/base_2da (публичный репозиторий, CI) — " <>
                       "выгрузки: mix hak.extract, mix base2da.extract"
    end

    defp table!(dir), do: dir |> Path.join("ruleset.2da") |> File.read!()

    # Таблица хака сверяется с `sha1` манифеста и записи: строка, поправленная
    # руками после выгрузки, источником не является.
    test "строка хака: метка, значение и sha1 — как в выгрузке; у базы строка ванильная" do
      bytes = table!(@hak)
      sha1 = :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower)
      manifest = @hak |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()
      hak = TwoDA.parse!(bytes)
      base = TwoDA.parse!(table!(@base))

      assert manifest["tables"]["ruleset"] == sha1

      for {feat, {shard, vanilla}} <- @shard_numbers do
        %{"source_2" => source, "quote_2" => quote} = shard_record(feat)
        row = source["row"]

        assert %{"kind" => "hak", "table" => "ruleset.2da", "column" => "Value"} = source
        assert source["sha1"] == sha1, "#{feat}: sha1 записи не совпадает с выгрузкой"
        assert TwoDA.get(hak, row, "Label") == source["label"]
        assert TwoDA.get(hak, row, "Value") == source["value"]
        assert quote == "#{row} #{source["label"]} #{source["value"]}"
        assert TwoDA.to_int(source["value"]) == shard

        # Хак говорит за Сиалу только там, где отличается от базы.
        assert TwoDA.get(base, row, "Label") == source["label"]
        assert TwoDA.to_int(TwoDA.get(base, row, "Value")) == vanilla
      end
    end
  end
end
