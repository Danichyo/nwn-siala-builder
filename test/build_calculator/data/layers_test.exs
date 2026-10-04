defmodule BuildCalculator.Data.LayersTest do
  @moduledoc """
  Правило наложения рукописных слоёв — `Data.Loader.Layers.merge/3` (задача 4.1).

  `siala_41/overrides.json` кладётся поверх `vanilla/rules.json` по тем же ключам,
  и от того, КАК именно, зависят числа Сиалы: предел ловкости девяти доспехов
  приходит записью списка, сужение Spellcraft — записью другого списка. Поэтому
  правило проверяется здесь на синтетике, по пункту на строку moduledoc'а
  модуля, а на живых данных — ниже, одним прогоном: тем, что сиальский
  `ruleset` с задачи 4.1 не сдвинулся ни в одном поле
  (`test/snapshots/ruleset_siala_41.snap`, `RulesetSnapshotTest`).
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader.Layers

  describe "карты и скаляры" do
    test "карты сливаются по ключам, рекурсивно; скаляр верхнего слоя заменяет нижний" do
      base = %{"a" => %{"x" => 1, "y" => 2}, "b" => 3}
      overlay = %{"a" => %{"y" => 20, "z" => 30}, "c" => 4}

      assert Layers.merge(base, overlay) ==
               %{"a" => %{"x" => 1, "y" => 20, "z" => 30}, "b" => 3, "c" => 4}
    end

    # `null` сверху — это ответ («значения нет»), а не «слой молчит».
    test "null верхнего слоя заменяет значение нижнего" do
      assert Layers.merge(%{"a" => 1}, %{"a" => nil}) == %{"a" => nil}
    end

    test "отсутствующий слой — это «слоя нет», а не пустая карта поверх" do
      assert Layers.merge(%{"a" => 1}, :missing) == %{"a" => 1}
      assert Layers.merge(:missing, %{"a" => 1}) == %{"a" => 1}
      assert Layers.merge(:missing, :missing) == %{}
    end

    # 🔴 Провенанс записи не сливается: верхний слой, назвавший свой источник или
    # цитату, приходит со своим провенансом целиком. Иначе сиальские 4 класса
    # (`character.max_classes`, слово Dan) несли бы ванильную цитату Fandom про
    # три, а источник, слитый по полям, — `kind: user` сверху и `page`/`revid`
    # Fandom снизу.
    test "провенанс записи не сливается: ни по полям, ни с чужими цитатами" do
      base = %{
        "fact" => %{
          "value" => 3,
          "quote" => "with up to three classes allowed",
          "source" => %{"kind" => "wiki", "wiki" => "fandom", "page" => "P", "revid" => 1},
          "quote_2" => "the limit is set to three by default",
          "source_2" => %{"kind" => "wiki", "page" => "Q"},
          "nested" => %{"kept" => true},
          "status" => "verified"
        }
      }

      overlay = %{
        "fact" => %{
          "value" => 4,
          "source" => %{"kind" => "user", "who" => "Dan"},
          "nested" => %{"added" => 1}
        }
      }

      assert Layers.merge(base, overlay)["fact"] == %{
               "value" => 4,
               "source" => %{"kind" => "user", "who" => "Dan"},
               # прочие поля записи сливаются как обычно...
               "nested" => %{"kept" => true, "added" => 1},
               "status" => "verified"
               # ...а ванильных `quote`, `quote_2`, `source_2` у сиального числа нет
             }
    end

    # Запись, которая провенанса не называет, его и не трогает: сверху
    # дописывается поле, а число и его источник остаются нижними.
    test "запись без своего провенанса не трогает нижний" do
      base = %{"fact" => %{"value" => "spells", "quote" => "Q", "source" => %{"page" => "P"}}}
      overlay = %{"fact" => %{"excludes" => "AOE"}}

      assert Layers.merge(base, overlay)["fact"] ==
               %{
                 "value" => "spells",
                 "quote" => "Q",
                 "source" => %{"page" => "P"},
                 "excludes" => "AOE"
               }
    end
  end

  describe "списки" do
    test "список без имён записей заменяется целиком" do
      assert Layers.merge(%{"l" => [1, 2, 3]}, %{"l" => [4]}) == %{"l" => [4]}

      assert Layers.merge(%{"l" => [%{"a" => 1}]}, %{"l" => [%{"b" => 2}]}) ==
               %{"l" => [%{"b" => 2}]}
    end

    test "пустой список сверху — ответ «ничего», он заменяет нижний" do
      assert Layers.merge(%{"l" => [%{"id" => "x"}]}, %{"l" => []}) == %{"l" => []}
    end

    test "записи сливаются по id, в порядке нижнего слоя; неназванные остаются" do
      base = %{
        "items" => [
          %{"id" => "a", "n" => 1, "keep" => true},
          %{"id" => "b", "n" => 2},
          %{"id" => "c", "n" => 3}
        ]
      }

      overlay = %{"items" => [%{"id" => "c", "n" => 30}, %{"id" => "a", "n" => 10, "new" => 1}]}

      assert Layers.merge(base, overlay)["items"] == [
               %{"id" => "a", "n" => 10, "keep" => true, "new" => 1},
               %{"id" => "b", "n" => 2},
               %{"id" => "c", "n" => 30}
             ]
    end

    # Правило Spellcraft записано по навыку, правило смены характеристики —
    # по фиту: у таких записей своего `id` нет, и имя — поле, о котором запись.
    test "имя записи — skill или feat, если id нет" do
      base = %{"rules" => [%{"skill" => "spellcraft", "bonus" => 1}]}
      overlay = %{"rules" => [%{"skill" => "spellcraft", "scope" => %{"excludes" => "AOE"}}]}

      assert Layers.merge(base, overlay)["rules"] ==
               [%{"skill" => "spellcraft", "bonus" => 1, "scope" => %{"excludes" => "AOE"}}]

      base = %{"rules" => [%{"feat" => "weapon_finesse", "ability" => "dex"}]}
      overlay = %{"rules" => [%{"feat" => "weapon_finesse", "ability" => "str"}]}

      assert Layers.merge(base, overlay)["rules"] ==
               [%{"feat" => "weapon_finesse", "ability" => "str"}]
    end

    # 🔴 Опечатка в имени записи иначе выглядела бы применённым фактом.
    test "запись с именем, которого внизу нет, роняет сборку" do
      assert_raise RuntimeError, ~r/lands on nothing/, fn ->
        Layers.merge(%{"items" => [%{"id" => "a"}]}, %{"items" => [%{"id" => "b"}]})
      end
    end

    test "имя, повторённое в одном слое дважды, роняет сборку" do
      assert_raise RuntimeError, ~r/twice/, fn ->
        Layers.merge(
          %{"items" => [%{"id" => "a"}]},
          %{"items" => [%{"id" => "a"}, %{"id" => "a"}]}
        )
      end

      assert_raise RuntimeError, ~r/twice/, fn ->
        Layers.merge(%{"items" => [%{"id" => "a"}, %{"id" => "a"}]}, %{
          "items" => [%{"id" => "a"}]
        })
      end
    end

    # Заменить список целиком значило бы молча выбросить всё, что лежало внизу.
    test "именованные записи сверху на неименованный список снизу роняют сборку" do
      assert_raise RuntimeError, ~r/drop everything/, fn ->
        Layers.merge(%{"l" => [%{"name" => "a"}]}, %{"l" => [%{"id" => "a"}]})
      end
    end
  end

  # Задача 4.46: разметка прибавок (`bonuses` файлов `*_bonuses.json`) называет
  # записи РАЗНЫМИ полями — колонка Мастера оружия `class`, `Epic prowess` —
  # `feat`. Общего ключа у такого списка нет, и до 4.46 запись `class` сверху
  # молча заменяла бы весь список, а запись `feat` сверху роняла сборку.
  describe "записи разметки — по паре «поле-источник = значение»" do
    @markup %{
      "bonuses" => [
        %{"feat" => "epic_prowess", "amount" => %{"bonus" => 1}},
        %{
          "class" => "weapon_master",
          "amount" => %{"kind" => "steps", "steps" => %{"5" => 1, "28" => 7}},
          "source" => %{"page" => "Weapon master"},
          "quote" => "AB bonus"
        },
        %{"race" => "half_elf", "verdict" => "counted_elsewhere"}
      ]
    }

    test "запись `class` ложится на свою, карта ступеней сливается по уровням" do
      overlay = %{
        "bonuses" => [
          %{
            "class" => "weapon_master",
            "amount" => %{"steps" => %{"31" => 8}, "steps_shard" => %{"31" => %{"by" => "Dan"}}}
          }
        ]
      }

      assert Layers.merge(@markup, overlay)["bonuses"] == [
               %{"feat" => "epic_prowess", "amount" => %{"bonus" => 1}},
               %{
                 "class" => "weapon_master",
                 "amount" => %{
                   "kind" => "steps",
                   "steps" => %{"5" => 1, "28" => 7, "31" => 8},
                   "steps_shard" => %{"31" => %{"by" => "Dan"}}
                 },
                 # Своего `source`/`quote` на уровне записи слой не назвал —
                 # провенанс нижней записи остаётся.
                 "source" => %{"page" => "Weapon master"},
                 "quote" => "AB bonus"
               },
               %{"race" => "half_elf", "verdict" => "counted_elsewhere"}
             ]
    end

    test "запись `feat` поверх смешанного списка сливается, а не роняет сборку" do
      overlay = %{"bonuses" => [%{"feat" => "epic_prowess", "amount" => %{"bonus" => 2}}]}

      assert [%{"feat" => "epic_prowess", "amount" => %{"bonus" => 2}}, _, _] =
               Layers.merge(@markup, overlay)["bonuses"]
    end

    # 🔴 Пара — это поле И значение: `class=weapon_master` не ложится на
    # запись `feat=weapon_master`, даже если такая была бы.
    test "пары, которой внизу нет, — сборка падает" do
      assert_raise RuntimeError, ~r/class="weapon_mastr".*lands on nothing/s, fn ->
        Layers.merge(@markup, %{"bonuses" => [%{"class" => "weapon_mastr"}]})
      end

      assert_raise RuntimeError, ~r/feat="weapon_master".*lands on nothing/s, fn ->
        Layers.merge(@markup, %{"bonuses" => [%{"feat" => "weapon_master"}]})
      end
    end

    test "пара, повторённая в одном слое дважды, — сборка падает" do
      assert_raise RuntimeError, ~r/class="weapon_master" twice/, fn ->
        Layers.merge(@markup, %{
          "bonuses" => [%{"class" => "weapon_master"}, %{"class" => "weapon_master"}]
        })
      end
    end

    # Запись, назвавшая два поля-источника, пары не имеет (у разметки это
    # ошибка сама по себе — `BonusMarkup.source!/4`), и список не назван.
    test "запись `class` поверх списка без пар — сборка падает, а не заменяет его" do
      assert_raise RuntimeError, ~r/drop everything/, fn ->
        Layers.merge(%{"l" => [%{"name" => "a"}]}, %{"l" => [%{"class" => "a"}]})
      end
    end

    test "общий ключ по-прежнему первым: список, названный `feat` целиком, — по `feat`" do
      base = %{"l" => [%{"feat" => "a", "class" => "x", "n" => 1}]}
      overlay = %{"l" => [%{"feat" => "a", "n" => 2}]}

      # У нижней записи два поля-источника — пары у неё нет, и слить её можно
      # только по общему ключу, как до задачи 4.46.
      assert Layers.merge(base, overlay)["l"] == [%{"feat" => "a", "class" => "x", "n" => 2}]
    end

    # Список полей — тот же, что у читателей разметки: поле, которого здесь
    # нет, дало бы записи без пары, и слой на такой файл молча заменил бы список.
    test "поля-источники — те же, что у читателя разметки" do
      assert MapSet.new(Layers.source_keys()) ==
               MapSet.new(BuildCalculator.Data.Loader.Bonuses.attack_bonus_sources())

      assert MapSet.subset?(
               MapSet.new(BuildCalculator.Data.Loader.Bonuses.save_bonus_sources()),
               MapSet.new(Layers.source_keys())
             )
    end
  end

  describe "живые данные" do
    # Сиальский слой несёт только отличия (VANILLA.md §2, принцип 1): четыре
    # секции, которые до задачи 4.1 раздавались ванили из сиальского файла,
    # лежат теперь в ванильном слое, а сиальский файл держит от них только свои
    # половины.
    test "ванильные секции живут в ванильном слое, у Сиалы — только её половины" do
      rules = "priv/rules/vanilla/rules.json" |> File.read!() |> Jason.decode!()
      overrides = "priv/rules/siala_41/overrides.json" |> File.read!() |> Jason.decode!()

      for section <- ~w(character stat_caps gear formulas _vanilla_constants_confirmed _receivers) do
        assert Map.has_key?(rules, section), section
      end

      # С задачи 4.6 у Сиалы есть и своя половина потолков: её собственные
      # цитаты и классификация трёх её механизмов (расовый бонус, бонус за тип
      # оружия, мини-сеты). ЧИСЕЛ потолков в ней нет — они ванильные.
      assert Map.keys(overrides["stat_caps"]) |> Enum.sort() ==
               ["_note", "attack_bonus", "max_skill_value", "skill_bonus"]

      for {name, entry} <- overrides["stat_caps"], not String.starts_with?(name, "_") do
        refute Map.has_key?(entry, "value"), name
      end

      refute Map.has_key?(overrides, "formulas")
      refute Map.has_key?(overrides, "_receivers")

      assert Map.keys(overrides["gear"]) |> Enum.sort() == ["_note", "worn"]

      assert Map.keys(overrides["_vanilla_constants_confirmed"]) |> Enum.sort() ==
               ["_note", "skill_save_bonus"]

      # Двойников с префиксом `siala_` в ванильных секциях больше нет.
      refute rules |> Map.take(~w(gear _vanilla_constants_confirmed)) |> Jason.encode!() =~
               ~r/"siala_(max_dex|weight_class|weight_classes|values_apply_to_ruleset|excludes|exception)"/
    end

    # Правило наложения даёт Сиале ровно то, что она измерила, а ванили —
    # ровно Fandom: на тех же девяти доспехах и том же правиле Spellcraft.
    test "слияние на живых данных даёт числа своего ruleset'а" do
      vanilla = Data.ruleset!("vanilla")
      siala = Data.ruleset!("siala_41")

      max_dex = fn ruleset ->
        armor = Enum.find(ruleset.gear.worn, &(&1.id == :armor))
        for item <- armor.items, do: item.max_dex
      end

      assert max_dex.(vanilla) == [nil, 8, 6, 4, 4, 2, 1, 1, 1]
      assert max_dex.(siala) == [nil, 8, 7, 6, 5, 4, 3, 2, 1]

      [vanilla_rule] = vanilla.skill_rules.save_bonus
      [siala_rule] = siala.skill_rules.save_bonus

      assert vanilla_rule.scope == "spells"
      assert vanilla_rule.scope_excludes == nil
      assert siala_rule.scope_excludes == "AOE"
      assert Map.delete(vanilla_rule, :scope_excludes) == Map.delete(siala_rule, :scope_excludes)
    end
  end
end
