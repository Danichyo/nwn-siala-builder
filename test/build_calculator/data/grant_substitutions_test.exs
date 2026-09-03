defmodule BuildCalculator.Data.GrantSubstitutionsTest do
  @moduledoc """
  `priv/rules/vanilla/grant_substitutions.json` — классовый уровень, который
  по таблице ВЫДАЁТ фит, а на деле даёт ВЫБОР из бонусного списка класса.

  Заведено 14.08.2026 двумя замерами подряд (`GAME_CHECKS.md`, M2 и M2b).

  **M2, персонаж 21-го уровня.** Dan взял 20 уровней воина и первый уровень
  Мастера оружия: слотов оказалось два — общий и классовый, — а в классовом
  рядом с `Weapon of choice` лежали `Armor skin`, `Epic prowess`,
  `Epic toughness`, `Epic weapon focus`. Дословно: «Получается я могу и не брать
  weapon of choice!»

  **M2b, персонаж 7-го уровня.** Первая редакция этого файла называлась
  `epic_grant_substitutions.json` и гейтила правило на эпичность — потому что
  замер был снят на 21-м, а цитата Fandom читается как условие («If an **epic
  character** takes weapon master level 1…»). Вопрос задал сам Dan («а нам
  не стоит weapon of choice проверить до 20 уровня?»), и ответ снял гейт: на
  воине 6 → Мастере оружия 1 слот тоже есть, и в нём шесть фитов. «Epic»
  в цитате описывает **следствие**, а не условие: альтернативы проходят свои
  требования только у эпического персонажа.

  ⚠️ Ошибка была **двойной и в разные стороны**: мы навязывали фит, который игра
  позволяет не брать, и прятали слот, который игра даёт. Поэтому здесь каждая
  проверка идёт парой «слот появился» + «выдача исчезла»: поодиночке каждая
  зеленеет и при половинчатой правке, а половинчатая — это фит, который
  одновременно выдан и выбираем.

  ⚠️ Неэпический пул совпал с наблюдением **точно, 6 из 6** — то есть пул был
  верен всё это время, а неверно было только отсутствие слота. Имена проверяются
  ниже поимённо: пул, отличающийся составом, — это другая механика, и заметить
  её можно только по именам.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules.{Build, FeatSlots}

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp wm_at(character_level) do
    fillers = character_level - 1
    Build.new(race: :human, levels: List.duplicate(:fighter, fillers) ++ [:weapon_master])
  end

  defp slots(build, ruleset, level),
    do: build |> FeatSlots.at(ruleset, level) |> Enum.map(& &1.kind)

  defp granted?(build, ruleset, level, feat),
    do: feat in Build.granted_feats_at(build, ruleset, level)

  describe "первый уровень Мастера оружия у эпического персонажа" do
    test "слот появляется, а выдача исчезает — обе половины разом", %{siala: siala} do
      epic = wm_at(21)

      assert slots(epic, siala, 21) == [:epic_general, :class_bonus]
      refute granted?(epic, siala, 21, :weapon_of_choice)
    end

    test "в слоте лежит и сам Weapon of choice, и всё, что Dan увидел рядом", %{siala: siala} do
      epic = wm_at(21)
      slot = epic |> FeatSlots.at(siala, 21) |> Enum.find(&(&1.kind == :class_bonus))
      pool = FeatSlots.candidates(siala, slot)

      # ⚠️ Пять имён из замера, а не «пул непустой»: слот, принимающий что-то
      # своё, но не принимающий `weapon_of_choice`, — это другая механика,
      # и отличить её можно только по именам.
      for feat <- [
            :weapon_of_choice,
            :armor_skin,
            :epic_prowess,
            :epic_toughness,
            :epic_weapon_focus
          ] do
        assert feat in pool, "слот не принимает #{feat}, а Dan его в списке видел"
      end
    end

    test "соседние две выдачи того же уровня не тронуты", %{siala: siala} do
      epic = wm_at(21)

      # Цитата говорит про альтернативы `weapon of choice`, и только про них.
      assert granted?(epic, siala, 21, :ki_damage)
      assert granted?(epic, siala, 21, :toughness)
    end
  end

  describe "тот же уровень у НЕэпического персонажа — правило то же" do
    # ⚠️ Здесь несколько часов 14.08.2026 стояло обратное утверждение («выдача
    # на месте, классового слота нет») с доводом от формы цитаты. Замер M2b его
    # снял. Тест оставлен именно на этом месте: он теперь сторожит не ваниль,
    # а то, что гейт не вернётся «по здравому смыслу».
    test "слот есть и здесь, выдачи нет", %{siala: siala} do
      low = wm_at(7)

      assert slots(low, siala, 7) == [:class_bonus]
      refute granted?(low, siala, 7, :weapon_of_choice)
    end

    test "в слоте ровно те шесть фитов, которые Dan перечислил", %{siala: siala} do
      low = wm_at(7)
      slot = low |> FeatSlots.at(siala, 7) |> Enum.find(&(&1.kind == :class_bonus))

      # ⚠️ Здесь сравнение ПОЛНЫМ составом, а не вхождением, — в отличие
      # от эпического слота выше. Причина в самом замере: эпический список Dan
      # назвал примерами («ещё другие эпик фиты: …»), а неэпический — целиком
      # («на выбор у меня тут 5 владений оружием … и шестой фит»). Проверять
      # надо ровно то, что сказано, и не больше.
      assert Enum.sort(FeatSlots.candidates(siala, slot)) == [
               :siala_axe_proficiency,
               :siala_blade_proficiency,
               :siala_hammer_proficiency,
               :siala_polearm_proficiency,
               :siala_ranged_proficiency,
               :weapon_of_choice
             ]
    end

    # 🔴 Побочное следствие, важнее самой записи: страницы пяти сиальских фитов
    # владения пишут «Мастер оружия НА ЭПИЧЕСКИХ ФИТАХ», а в неэпическом слоте
    # они все пятеро есть. Источник здесь неточен — перечисление называет
    # эпические слоты и молчит про первый уровень класса.
    test "сиальские владения лежат и в неэпическом слоте, вопреки своим страницам", %{
      siala: siala
    } do
      low = wm_at(7)
      slot = low |> FeatSlots.at(siala, 7) |> Enum.find(&(&1.kind == :class_bonus))

      assert :siala_blade_proficiency in FeatSlots.candidates(siala, slot)
    end
  end

  describe "правило одинаково на обоих ruleset'ах" do
    # Шард про это не пишет ничего, значит по §3 действует ваниль — и здесь это
    # проверяется, а не подразумевается: слой Сиалы `granted_feats` переписывает,
    # и подстановка могла бы разъехаться с ним незаметно.
    test "и у vanilla слот появляется, и выдача исчезает", %{vanilla: vanilla} do
      epic = wm_at(21)

      assert :class_bonus in slots(epic, vanilla, 21)
      refute granted?(epic, vanilla, 21, :weapon_of_choice)
    end
  end

  describe "загрузчик роняет сборку на битой разметке" do
    setup do
      root = Path.join(System.tmp_dir!(), "gs-#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root, path: Path.join(root, "vanilla/grant_substitutions.json")}
    end

    test "нетронутая копия грузится — иначе падения ниже зеленели бы впустую", %{root: root} do
      assert %{"siala_41" => siala} = Loader.load!(root)
      assert Map.has_key?(siala.grant_substitutions, {:weapon_master, 1})
    end

    test "имя несуществующего класса", %{root: root, path: path} do
      write!(path, %{
        "class" => "not_a_class",
        "class_level" => 1,
        "feats" => [],
        "when" => "always"
      })

      assert_raise RuntimeError, ~r/no such class/, fn -> Loader.load!(root) end
    end

    # Самое дорогое из падений: снятие выдачи, которой на этом уровне нет,
    # молча не делает ничего и при этом выглядит правилом.
    test "фит, которого класс на этом уровне не выдаёт", %{root: root, path: path} do
      write!(path, %{
        "class" => "weapon_master",
        "class_level" => 1,
        "feats" => ["epic_prowess"],
        "when" => "always"
      })

      assert_raise RuntimeError, ~r/does not grant/, fn -> Loader.load!(root) end
    end

    test "незнакомое условие", %{root: root, path: path} do
      write!(path, %{
        "class" => "weapon_master",
        "class_level" => 1,
        "feats" => ["weapon_of_choice"],
        "when" => "on_a_tuesday"
      })

      assert_raise RuntimeError, ~r/unknown condition/, fn -> Loader.load!(root) end
    end

    defp write!(path, entry),
      do: File.write!(path, Jason.encode!(%{"substitutions" => [entry]}))
  end
end
