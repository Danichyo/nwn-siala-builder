defmodule BuildCalculator.Data.CapSidesTest do
  @moduledoc """
  Сторона потолка +20 — **у каждой записи разметки** (`bonuses[].cap`
  в `vanilla/feat_save_bonuses.json` и `vanilla/feat_attack_bonuses.json`) и
  у трёх механизмов, у которых записи нет
  (`stat_caps.*.applies_to_sources` в `siala_41/overrides.json`).

  ⚠️ **Правило переписывали дважды за один день, 09.08.2026.** Сначала
  `applies_to: "bonuses"` читалось как «применяется ко всем бонусам», и задача
  1.12b положила прибавку от фита под кап атаки **по аналогии** с сейвами, где кап
  на классовое умение подтверждён дословно (`fandom:Uncanny dodge` — «subject to
  the +20 saving throw cap»). Dan: «Фиты не входят в кап атаки +20» — и сторона
  стала свойством ВИДА источника. Через несколько часов: «Divine grace не входит
  в кап +20, а Sacred Defence входит», а это **два классовых умения, записанные
  у нас в одной и той же форме фита**. Вид не может дать им разные ответы — значит
  признак принадлежит записи.

  Правило, которое из этого получилось, дословно:

  > **Сторона капа читается у записи. Вид источника — дефолт только для тех
  > слагаемых, у которых записи в файлах разметки нет вовсе** (вещи, расовый бонус
  > Сиалы, правило навыка).

  ⚠️ **И в третий раз — 10.08.2026 (задача 3.22).** Правило выше не тронуто, но
  сторона поменялась у последнего внутрикапного механизма атаки кроме расового:
  `gear` вышел из-под капа. Dan перечислил состав капа целиком (`GAME_CHECKS.md`
  кейс J1), и модификатора силы там нет ни из какого источника. Ошибка была
  третьего рода: сторону выбирало **происхождение** прибавки («её дал предмет»),
  а решает то, **что** прибавляется — модификатор характеристики это база, а не
  бонус. Нашлась она тем, что атака и сейвы трактовали одно правило по-разному.

  Здесь проверяется то, что человек может испортить в этих данных: что обе
  классификации доезжают до `Rules.Caps`; что применяемая запись **не может** не
  назвать сторону; что вид источника **не может** говорить про то, у чего есть
  записи; и что две копии одного факта (кап у расы и у правила навыка) не могут
  разойтись с этим блоком.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules.Caps

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp applied(ruleset, key, id),
    do: ruleset |> Map.fetch!(key) |> Map.fetch!(:applied) |> Enum.find(&(&1.id == id))

  describe "сторона капа у записи" do
    # 🔴 Само правило, числами: из 14 применяемых прибавок к сейвам внутри капа
    # РОВНО ОДНА. Список поимённый, а не «13 из 14», потому что именно поимённость
    # ловит запись, у которой сторону поменяли молча.
    test "внутри капа сейвов ровно Sacred defense, остальные поверх", %{siala: s} do
      {inside, outside} =
        s.save_bonuses.applied
        |> Enum.split_with(&Caps.covers_record?(s, :saving_throw_bonus, &1))

      assert Enum.map(inside, & &1.id) == [:sacred_defense]

      assert Enum.sort(Enum.map(outside, & &1.id)) == [
               :bullheaded,
               :dark_blessing,
               :divine_grace,
               :epic_fortitude,
               :epic_reflexes,
               :epic_will,
               :great_fortitude,
               :iron_will,
               :lightning_reflexes,
               :luck_of_heroes,
               :lucky,
               :snake_blood,
               :strong_soul
             ]
    end

    # 🔴 И то, из-за чего модель по виду источника развалилась: у двух записей
    # ОДИН И ТОТ ЖЕ вид (`{:feat, _}`), оба — классовые умения, а стороны разные.
    test "Divine grace и Sacred defense — один вид, разные стороны", %{siala: s} do
      grace = applied(s, :save_bonuses, :divine_grace)
      sacred = applied(s, :save_bonuses, :sacred_defense)

      assert elem(grace.source, 0) == :feat
      assert elem(sacred.source, 0) == :feat

      refute Caps.covers_record?(s, :saving_throw_bonus, grace)
      assert Caps.covers_record?(s, :saving_throw_bonus, sacred)
    end

    # ⚠️ До задачи 3.143 (30.08.2026) здесь проверялись ДВЕ записи —
    # `epic_prowess` и `small_stature`. `small_stature` стал `not_modelled`
    # (цитата в разметке была обрезана перед условием «когда противник крупнее
    # персонажа»), и у `not_modelled` поле `cap` запрещено вовсе — своей
    # стороны потолка у записи больше нет, а не «сторона не под капом».
    # `epic_prowess` остался единственной применяемой прибавкой файла.
    test "epic_prowess — единственная применяемая прибавка к атаке, и она поверх капа", %{
      siala: s
    } do
      refute Caps.covers_record?(s, :attack_bonus, applied(s, :attack_bonuses, :epic_prowess)),
             "epic_prowess: сторона капа атаки разошлась со словом Dan"
    end

    # ⚠️ Ни одна сторона сегодня не `assumed`, и это результат ответа Dan, а не
    # пустое место: до 09.08.2026 `Small stature`, `Lucky` и `Dark blessing`
    # стояли допущениями. Тест закрепляет именно это — печатать «не знаем» про
    # решённое запрещено так же, как молчать про незнание.
    test "допущений про сторону капа не осталось ни у одной записи", %{siala: s} do
      for {stat, key} <- [saving_throw_bonus: :save_bonuses, attack_bonus: :attack_bonuses],
          record <- Map.fetch!(s, key).applied do
        refute Caps.assumed_record?(s, stat, record),
               "#{record.id}: сторона капа помечена допущением, а Dan её назвал"
      end
    end

    test "оба ruleset'а несут одну и ту же сторону у записей", %{siala: s, vanilla: v} do
      for key <- [:save_bonuses, :attack_bonuses] do
        assert Enum.map(Map.fetch!(v, key).applied, &{&1.id, &1.cap}) ==
                 Enum.map(Map.fetch!(s, key).applied, &{&1.id, &1.cap})
      end
    end

    # У непосчитанной прибавки стороны нет вовсе — и это не забывчивость, а
    # запрет: считать нечего, а незаверяемое утверждение копило бы мусор.
    test "у not_modelled-записей стороны нет", %{siala: s} do
      for key <- [:save_bonuses, :attack_bonuses], record <- Map.fetch!(s, key).unmodelled do
        assert is_nil(record.cap), "#{record.id}: у непосчитанной прибавки объявлена сторона капа"
      end
    end
  end

  describe "сторона капа у механизма" do
    # 🔴 После второй правки здесь остались РОВНО механизмы: вещи и расовый бонус
    # у атаки, вещи и правило навыка у сейвов. Виды `feat`/`race_feat` удалены —
    # их содержимое переехало в записи.
    #
    # ⚠️ Третья запись, `skill_bonus`, добавлена 09.08.2026 задачей 3.20: до неё
    # у капа навыков +50 было ровно одно слагаемое (расовый бонус шарда), и
    # `Rules.Skills` клипал его на месте, не спрашивая сторону. С прибавкой к
    # навыку с вещей слагаемых стало два, и «клип на месте» превратился бы в две
    # половинки одного потолка — Человек унёс бы +62 при потолке 50. Обе стороны
    # названы данными, у каждой своя цитата; у вещей это «Система оружия» про
    # магический посох: «+12 к спеллкрафту … входит в кап +50».
    # 🔴 И третья правка того же правила, 10.08.2026 (задача 3.22, кейс J1):
    # `gear` у АТАКИ вынесен из-под капа. Dan назвал состав капа списком —
    # attack/enchantment bonus оружия, баффы, песня барда, расовый бонус
    # Сиалы, — и модификатора силы в нём нет ни из какого источника, включая
    # надетые вещи. ⚠️ У сейвов и навыков `gear` остался ВНУТРИ, и это не
    # разнобой: там под этим именем едет число, которое игрок вписал прямо
    # («бонус ко всем сейвам с вещей», «+12 к спеллкрафту с посоха»), а у атаки —
    # прибавка МОДИФИКАТОРА ХАРАКТЕРИСТИКИ, то есть база, а не бонус. Именно
    # разъезд атаки с сейвами по одному правилу и нашёл эту ошибку.
    # 🔴 ШЕСТАЯ правка того же правила, 16.08.2026 (задача 3.35): у капа атаки и
    # у капа навыков появился механизм `weapon_bonus` — бонус ШАРДА за ТИП
    # оружия в руках. ⚠️ Не расширение `gear_weapon` рядом, а отдельный механизм
    # с ПРОТИВОПОЛОЖНОЙ стороной: числа самого предмета вне капа (замер Q5), а
    # эта прибавка называет свой кап дословно («Бонус входит в лимита атаки
    # +20»). Одно имя не может отдать двум правилам разные стороны.
    #
    # ⚠️ И это первый момент, когда кап атаки ДОСТИЖИМ: расовый бонус +9 и
    # бонус за тип оружия +9 дают 18 из 20.
    test "названы только механизмы, и стороны такие", %{siala: s} do
      assert s.stat_cap_sources == %{
               attack_bonus: %{
                 gear: %{inside?: false, assumed?: false},
                 # 🔴 ШЕСТАЯ правка того же правила, 18.08.2026 — РЕШЕНИЕ Dan,
                 # идущее против его же замера. Дословно: «они оба по идее
                 # работают идентично и внутри капа… нам на 100% надо attack
                 # bonus засунуть внутрь капа 20».
                 #
                 # ⚠️ Пятая правка (15.08, ЗАМЕР Q5) ставила сюда `false`:
                 # светлый эльф-сагровик 40 с луком +5 показал AB 62 там, где
                 # 5 + 9 + 9 = 23 внутрикапного обязаны были срезаться до 20
                 # и дать 59. Спор НЕ разрешён — гипотеза Dan в том, что лист
                 # персонажа показывает завышенное AB, а в боевом логе было бы
                 # 59; проверяется переоткрытым кейсом Q5.
                 #
                 # 🔴 Единственное место, где мы сознательно расходимся
                 # с наблюдением. Взято слово владельца: ошибка в эту сторону
                 # (кап режет) занижает AB и видна игроку сразу, обратная —
                 # завышала бы молча.
                 gear_weapon: %{inside?: true, assumed?: false},
                 racial_bonus: %{inside?: true, assumed?: false},
                 weapon_bonus: %{inside?: true, assumed?: false}
               },
               saving_throw_bonus: %{
                 gear: %{inside?: true, assumed?: false},
                 skill_rule: %{inside?: true, assumed?: false}
               },
               skill_bonus: %{
                 gear: %{inside?: true, assumed?: false},
                 racial_bonus: %{inside?: true, assumed?: false},
                 weapon_bonus: %{inside?: true, assumed?: false}
               }
             }
    end

    test "Caps отвечает по данным, а не по имени механизма", %{siala: s} do
      # ⚠️ Один и тот же механизм с разными ответами у разных потолков — это и
      # есть проверка «по данным, а не по имени»: раньше все шесть отвечали `true`,
      # и тест зеленел бы у кода, который просто всегда говорит «внутри».
      refute Caps.covers_source?(s, :attack_bonus, :gear)
      assert Caps.covers_source?(s, :attack_bonus, :gear_weapon)
      assert Caps.covers_source?(s, :attack_bonus, :racial_bonus)

      # ⚠️ Два механизма оружия у одного потолка с разными ответами — ровно то
      # же доказательство «по данным, а не по имени», что и строка выше.
      assert Caps.covers_source?(s, :attack_bonus, :weapon_bonus)
      assert Caps.covers_source?(s, :skill_bonus, :weapon_bonus)
      assert Caps.covers_source?(s, :saving_throw_bonus, :gear)
      assert Caps.covers_source?(s, :saving_throw_bonus, :skill_rule)
      assert Caps.covers_source?(s, :skill_bonus, :gear)
      assert Caps.covers_source?(s, :skill_bonus, :racial_bonus)

      refute Caps.assumed_source?(s, :attack_bonus, :gear)
      refute Caps.assumed_source?(s, :saving_throw_bonus, :skill_rule)
      refute Caps.assumed_source?(s, :skill_bonus, :gear)
    end

    # Потолок +20 ванильный и лежит в секции, которую видят ОБА ruleset'а
    # (`@vanilla_sections` загрузчика), — значит и его область действия видна
    # обоим. ⚠️ Записано тестом, потому что правило пришло от игрока Сиалы:
    # если когда-нибудь слои разведут, разойдётся и это.
    test "оба ruleset'а несут одну и ту же классификацию", %{siala: s, vanilla: v} do
      assert v.stat_cap_sources == s.stat_cap_sources
    end

    # ⚠️ Механизм, про который данные молчат, считается ПОД капом — так читался
    # потолок до появления блока. Дефолт не несёт нагрузки ни на одном рабочем
    # ruleset'е (загрузчик роняет сборку на неназванном механизме, см. ниже),
    # но он должен быть определён: `nil` в арифметике хуже любого решения.
    test "неназванный механизм по умолчанию под капом", %{siala: s} do
      assert Caps.covers_source?(s, :attack_bonus, :something_new)
      refute Caps.assumed_source?(s, :attack_bonus, :something_new)
    end
  end

  describe "загрузчик роняет сборку на битой классификации" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      root = Path.join(dir, "rules")
      File.cp_r!("priv/rules", root)

      %{
        root: root,
        path: Path.join([root, "siala_41", "overrides.json"]),
        saves: Path.join([root, "vanilla", "feat_save_bonuses.json"]),
        attack: Path.join([root, "vanilla", "feat_attack_bonuses.json"])
      }
    end

    defp scope!(path, stat, fun) do
      overrides = path |> File.read!() |> Jason.decode!()

      overrides
      |> update_in(["stat_caps", stat, "applies_to_sources"], fun)
      |> Jason.encode!()
      |> then(&File.write!(path, &1))
    end

    defp record!(path, id, fun) do
      file = path |> File.read!() |> Jason.decode!()

      file
      |> update_in(["bonuses"], fn bonuses ->
        for entry <- bonuses do
          if entry["feat"] == id or entry["race_feat"] == id, do: fun.(entry), else: entry
        end
      end)
      |> Jason.encode!()
      |> then(&File.write!(path, &1))
    end

    # ⚠️ Положительный контроль ко всем падениям ниже: нетронутая копия обязана
    # грузиться. Без него `assert_raise` зеленел бы на копии, которая не
    # грузится вовсе.
    test "нетронутая копия грузится", %{root: root} do
      ruleset = Loader.load!(root)["siala_41"]

      refute ruleset.save_bonuses.applied
             |> Enum.find(&(&1.id == :iron_will))
             |> Map.fetch!(:cap)
             |> Map.fetch!(:inside?)
    end

    # 🔴 Главный сторож нижнего уровня: запись посчитана, а сторону капа не
    # назвала — собираться нельзя. Иначе решение «внутри или снаружи» принял бы
    # дефолт, и ровно так же незаметно, как это уже случилось дважды.
    test "применяемая запись не назвала сторону", %{root: root, saves: saves} do
      record!(saves, "iron_will", &Map.delete(&1, "cap"))

      assert_raise RuntimeError, ~r/does not state which side/, fn -> Loader.load!(root) end
    end

    test "то же у атаки", %{root: root, attack: attack} do
      record!(attack, "epic_prowess", &Map.delete(&1, "cap"))

      assert_raise RuntimeError, ~r/does not state which side/, fn -> Loader.load!(root) end
    end

    test "сторона названа не булевым", %{root: root, saves: saves} do
      record!(saves, "iron_will", &put_in(&1, ["cap", "inside_cap"], "нет"))

      assert_raise RuntimeError, ~r/no boolean cap.inside_cap/, fn -> Loader.load!(root) end
    end

    # `unclear` — это человек, который не смог решить. Правилом такая запись не
    # становится (как и у самих потолков), но и «считать по умолчанию» нельзя:
    # сборка падает, потому что решение обязан принять человек.
    test "статус записи, который не становится правилом", %{root: root, saves: saves} do
      record!(saves, "iron_will", &put_in(&1, ["cap", "status"], "unclear"))

      assert_raise RuntimeError, ~r/only \["verified", "assumed"\]/, fn -> Loader.load!(root) end
    end

    # Обратная сторона того же правила: сторона у непосчитанной прибавки не
    # «допустима на будущее», а запрещена — иначе в файле копились бы
    # утверждения, которые никто не может ни проверить, ни применить.
    test "сторона объявлена у непосчитанной записи", %{root: root, saves: saves} do
      record!(saves, "resist_poison", fn entry ->
        Map.put(entry, "cap", %{"inside_cap" => true, "status" => "verified"})
      end)

      assert_raise RuntimeError, ~r/states a `cap` side/, fn -> Loader.load!(root) end
    end

    # 🔴 Сторож верхнего уровня, и он ровно про отменённую модель: потолок больше
    # не имеет права говорить про вид, у которого есть записи. Оставь мы ключ
    # разрешённым-но-нечитаемым, на месте отменённой модели остался бы блок
    # данных, который выглядит живым и не двигает ни одного числа.
    test "вид источника, у которого есть записи", %{root: root, path: path} do
      scope!(path, "attack_bonus", &Map.put(&1, "feat", %{"inside_cap" => true}))

      assert_raise RuntimeError, ~r/belongs to each record/, fn -> Loader.load!(root) end
    end

    test "механизм ядра не назван — вещи у атаки", %{root: root, path: path} do
      scope!(path, "attack_bonus", &Map.delete(&1, "gear"))

      assert_raise RuntimeError, ~r/says nothing about \[:gear\]/, fn -> Loader.load!(root) end
    end

    test "механизм ядра не назван — правило навыка у сейвов", %{root: root, path: path} do
      scope!(path, "saving_throw_bonus", &Map.delete(&1, "skill_rule"))

      assert_raise RuntimeError, ~r/says nothing about \[:skill_rule\]/, fn ->
        Loader.load!(root)
      end
    end

    # Опечатка в имени механизма: «gears» вместо «gear». Сама по себе она
    # оставила бы источник под капом — то есть вернула бы неверное число молча.
    test "неизвестное имя механизма", %{root: root, path: path} do
      scope!(path, "attack_bonus", fn scope -> Map.put(scope, "gears", %{}) end)

      assert_raise RuntimeError, ~r/does not know/, fn -> Loader.load!(root) end
    end

    test "сторона механизма не названа", %{root: root, path: path} do
      scope!(path, "attack_bonus", &put_in(&1, ["gear", "inside_cap"], "нет"))

      assert_raise RuntimeError, ~r/no boolean inside_cap/, fn -> Loader.load!(root) end
    end

    test "статус механизма, который не становится правилом", %{root: root, path: path} do
      scope!(path, "attack_bonus", &put_in(&1, ["gear", "status"], "unclear"))

      assert_raise RuntimeError, ~r/only \["verified", "assumed"\]/, fn -> Loader.load!(root) end
    end

    # 🔴 Вторая копия факта и есть причина этого сторожа: расовый бонус называет
    # свой кап сам, на странице расы («Этот бонус входит в кап атаки +20»,
    # `siala_41/races.json` → `counts_toward_cap`). Две копии расходятся —
    # сборка падает, ровно как у `verify_stat_caps!/2`.
    #
    # ⚠️ Текст сообщения перестал цитировать кап атаки 09.08.2026: с задачи 3.20
    # расовый бонус заявляет ДВА разных капа (атаку у Светлого эльфа, навык +50
    # у Человека), сторож спрашивает per stat, и одна зашитая цитата в сообщении
    # врала бы про половину случаев. Проверяется теперь названный стат — то, что
    # в сообщении действительно переменное.
    test "расовый бонус заявляет кап, а классификация его выносит", %{root: root, path: path} do
      scope!(path, "attack_bonus", &put_in(&1, ["racial_bonus", "inside_cap"], false))

      assert_raise RuntimeError, ~r/counts towards stat_caps.attack_bonus/, fn ->
        Loader.load!(root)
      end
    end

    # Та же пара у навыков, и она новая: у Человека «Этот бонус входит в кап
    # навыка +50» (`races.json` → `counts_toward_cap.kind: "skill"`). Без этого
    # кейса generalization сторожа держалась бы на том, что его никто не пробовал
    # на втором стате.
    test "расовый бонус к навыку заявляет кап, а классификация его выносит", %{
      root: root,
      path: path
    } do
      scope!(path, "skill_bonus", &put_in(&1, ["racial_bonus", "inside_cap"], false))

      assert_raise RuntimeError, ~r/counts towards stat_caps.skill_bonus/, fn ->
        Loader.load!(root)
      end
    end

    # И механизм, который ядро применяет, но данные не назвали, — у навыков.
    test "механизм ядра не назван — вещи у навыков", %{root: root, path: path} do
      scope!(path, "skill_bonus", &Map.delete(&1, "gear"))

      assert_raise RuntimeError, ~r/says nothing about \[:gear\]/, fn -> Loader.load!(root) end
    end

    # И та же пара у сейвов: правило Spellcraft называет свой кап само
    # (`_vanilla_constants_confirmed.skill_save_bonus.rules[].counts_toward_cap`,
    # слово Dan от 01.08.2026).
    test "правило навыка заявляет кап, а классификация его выносит", %{root: root, path: path} do
      scope!(path, "saving_throw_bonus", &put_in(&1, ["skill_rule", "inside_cap"], false))

      assert_raise RuntimeError, ~r/counts towards stat_caps.saving_throw_bonus/, fn ->
        Loader.load!(root)
      end
    end

    # Обратный контроль к сторожам выше: без потолка проверять нечего, и падать
    # не на чем. ⚠️ Иначе ruleset без потолка (а `vanilla` таким и был бы, если
    # бы потолки не лежали в общей секции) не собрался бы вовсе — то есть
    # сторож требовал бы классификации для капа, которого нет.
    test "нет потолка — нет и требования его классифицировать", %{root: root, path: path} do
      overrides = path |> File.read!() |> Jason.decode!()

      overrides
      |> put_in(["stat_caps", "attack_bonus", "status"], "unclear")
      |> update_in(["stat_caps", "attack_bonus", "applies_to_sources"], &Map.delete(&1, "gear"))
      |> Jason.encode!()
      |> then(&File.write!(path, &1))

      ruleset = Loader.load!(root)["siala_41"]

      refute Map.has_key?(ruleset.stat_caps, :attack_bonus)
      assert {:missing_data, {:stat_cap, :attack_bonus}} in ruleset.gaps
    end
  end
end
