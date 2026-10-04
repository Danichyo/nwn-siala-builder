defmodule BuildCalculatorWeb.VanillaWithoutSialaTest do
  @moduledoc """
  Сиальское на ванили — задача 4.4 (VANILLA.md §4.4): то, что ванильный сайт
  говорит ВМЕСТО сиальского, по поверхностям, которые 4.4 правила. Что слов
  «Сиал…» / «шард…» на ванили нет вовсе, стережёт `en_guard_test.exs`
  («ни Сиалы, ни шарда»); здесь — положительная сторона: ваниль говорит своё,
  а у Сиалы на тех же селекторах всё прежнее.

    * экспорт подписан именем ванильного продукта (`Edition.export_name/0`),
      гид — в формате гильдии (`Edition.export_guide/1`), раса одним именем;
    * `/sources` без раздела о фактах шарда, оговорки — ванильные
      (`Gaps.shard_facts?/1`);
    * карточка расы — одно имя, а не «Dwarf / Dwarf» (`Labels.race_engine_name/2`);
    * пометка о дырах в данных — английская, согласованная по числу, без фразы
      о «кастомных системах шарда». ⚠️ С задачи 4.7 настоящих дыр в данных
      у ванили нет (последнюю закрыл выбор навыка у `Epic skill focus`), и
      баннер, пометка просмотра и раздел `/sources` закрыты теми же воротами,
      что у Сиалы; английская фраза подвала проверяется синтетической дырой.

  ⚠️ `async: false` — `use_edition/1` меняет редакцию ПРИЛОЖЕНИЯ через
  `Application.put_env/3`; параллельный сосед в той же VM увидел бы чужой
  сайт (CLAUDE.md §7).
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BuildCalculatorWeb.EditionHelpers

  alias BuildCalculator.{Data, Encoding, Rules}
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.{Export, Gaps, Import, Labels}
  alias BuildCalculatorWeb.Edition

  defp use_site(edition) do
    use_edition(edition)
    Gettext.put_locale(BuildCalculatorWeb.Gettext, Edition.locale())
    :ok
  end

  defp dwarf_fighter(version) do
    Build.new(
      ruleset_version: version,
      race: :dwarf,
      alignment: :lawful_good,
      base_abilities: %{str: 16, dex: 12, con: 15, int: 10, wis: 12, cha: 8},
      levels: [:fighter, :fighter],
      feats: %{1 => %{:general => :dodge}},
      skills: %{1 => %{discipline: 4}}
    )
  end

  defp export(build) do
    ruleset = Data.ruleset!(build.ruleset_version)
    Export.text(build, ruleset, Rules.compute(build, ruleset))
  end

  defp footer(text), do: text |> String.split("\n---\n") |> List.last()

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  describe "ванильная редакция" do
    setup do
      use_site(:vanilla)
    end

    test "экспорт: подпись ванили, формат гильдии, раса одним именем" do
      text = export(dwarf_fighter(Edition.ruleset()))
      lines = String.split(text, "\n")

      assert Enum.at(lines, 1) == "Dwarf, Lawful Good"
      assert "LEVELING GUIDE" in lines
      assert "SKILL GUIDE" in lines
      assert Edition.export_guide(Edition.ruleset()) == :ecb

      # ⚠️ Здесь стояло «у ванили настоящая дыра в данных одна, и подвал
      # говорит о ней». Задача 4.7 закрыла её (выбор навыка у `Epic skill
      # focus` из таблицы игры), и подвал ванили, как у Сиалы, фразы
      # о неполноте не несёт — но подписан ванильным продуктом, по-английски.
      assert Gaps.data_tiers(Data.ruleset!(Edition.ruleset())).real == []

      assert footer(text) =~
               ~s(Calculated by NWN Build Calculator. "?" marks a number we could not work out.)

      # Фраза о неполноте — за воротами, и открывается сама, когда настоящая
      # дыра есть: синтетикой, той самой дырой, что стояла у ванили до 4.7.
      build = dwarf_fighter(Edition.ruleset())
      ruleset = Data.ruleset!(build.ruleset_version)

      holed = %{
        ruleset
        | gaps: [{:not_modelled, {:feat_skill_bonus, :epic_skill_focus}} | ruleset.gaps]
      }

      assert footer(Export.text(build, holed, Rules.compute(build, holed))) =~
               ~s(Calculated by NWN Build Calculator. We can't calculate part of the rules yet; "?" marks a number we could not work out.)
    end

    test "/sources: раздела о фактах шарда нет, оговорки — ванильные", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")

      refute has_element?(view, "#sources-shard-heading")
      refute has_element?(view, "#sources-shard-facts")
      refute has_element?(view, "#sources-shard-not-ours")

      assert text(view, "#sources-intro") =~ "adapts them to the rules it computes"

      assert text(view, "#sources-changed") ==
               "The material has been changed: we parsed the articles' prose into structured data — so this is a derivative work, not a copy of the original text."

      assert text(view, "#sources-disclaimer") =~
               "This project is not affiliated with BioWare, Beamdog, Wizards of the Coast or Fandom."

      # ⚠️ Здесь стоял и заголовок раздела настоящих дыр («Rules not yet
      # carried into the calculation»): у ванили такая дыра была одна, и задача
      # 4.7 её закрыла — раздела нет, как у Сиалы.
      refute has_element?(view, "#sources-gaps-real")
      assert text(view, "#sources-gaps-resolved h3") == "How source disagreements were resolved"
      assert text(view, "#sources-gaps-assumed h3") == "Accepted assumptions and constants"

      # Атрибуция Fandom CC BY-SA — обеим редакциям (CLAUDE.md §3).
      assert has_element?(view, ~s(a#sources-fandom-link[href="https://nwn.fandom.com/"]))
      assert has_element?(view, "#sources-license-link")
    end

    test "карточка расы — одно имя, без второй подписи", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert text(view, "#race-card-dwarf .card-name") == "Dwarf"
      refute has_element?(view, "#race-card-dwarf .card-en")
      refute has_element?(view, "#race-cards .card-en")
    end

    test "просмотр: пометка о дырах английская, без фразы о системах шарда", %{conn: conn} do
      code = Encoding.encode(dwarf_fighter(Edition.ruleset()))
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      # ⚠️ Здесь стояла пометка «We can't calculate part of the rules yet —
      # 1 gap in the data.»: настоящая дыра в данных у ванили была одна, и
      # задача 4.7 её закрыла. Ворота фразы те же, что у Сиалы
      # (`data_real_count`); сам блок остаётся ради пробела ЭТОГО билда
      # (без оружия в руках дальний бой не посчитан), и фразы о «кастомных
      # системах шарда» в нём нет.
      assert has_element?(view, "#view-gaps")
      refute has_element?(view, "#view-gaps > b")
      refute text(view, "#view-gaps") =~ "Среди них"

      # Поэлементно: текст всего `#view-subtitle` склеивает соседние спаны
      # (HANDOFF.md, ловушки редакции 4.2, п. 3).
      assert text(view, "#view-subtitle > span:first-child") == "Dwarf"
    end

    test "подписи, которые ваниль порождает сама: без имени правил" do
      vanilla = Data.ruleset!("vanilla")

      # Гэп таблицы атак ставит и ваниль (`ruleset.gaps`).
      assert {:assumed, :attacks_per_round_table, "fandom:Attacks per round"} in vanilla.gaps

      assert Labels.gap({:assumed, :attacks_per_round_table, "fandom:Attacks per round"}, vanilla) ==
               "the attacks-per-round table is taken from fandom:Attacks per round"

      # Импорт текста на ванили виден; лимит — ванильный, форма — по числу.
      assert Import.issue_text({:too_many_classes, 4, 3}, vanilla) ==
               "the build has 4 classes, the limit is 3 — the rules do not allow such a build"

      assert Labels.capped_title() == "The number hit the cap of the rules — it goes no higher"

      # Переключатель выданных фитов в экспорте — только там, где текст их печатает.
      refute Export.shows_granted_feats?(vanilla)
      refute Gaps.shard_facts?(vanilla)
    end

    # ⚠️ Здесь стояло «баннер о дырах — английский и по числу»: у ванили была
    # одна настоящая дыра, и баннер говорил «1 gap». Задача 4.7 её закрыла —
    # ворота `data_real_count > 0` те же, что у Сиалы, и баннера нет. Что
    # в нём не будет кириллицы, когда он вернётся, стережёт `en_guard_test.exs`
    # (зоны конструктора), а фраза с числом — msgid самого шаблона.
    test "конструктор: баннера о дырах нет — дыр в данных нет", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert Gaps.data_tiers(Data.ruleset!(Edition.ruleset())).real == []
      refute has_element?(view, "#builder-notice")
      assert has_element?(view, "#gaps-toggle")
    end
  end

  # Положительный контроль: те же селекторы на Сиале — прежним текстом.
  describe "Сиала — те же поверхности прежние" do
    setup do
      use_site(:siala)
    end

    test "экспорт: «Посчитано Siala Build Calculator», гид одной строкой, «Гном (Dwarf)»" do
      text = export(dwarf_fighter(Edition.ruleset()))
      lines = String.split(text, "\n")

      assert Enum.at(lines, 1) == "Гном (Dwarf), Lawful Good"
      refute "SKILL GUIDE" in lines
      assert Edition.export_guide(Edition.ruleset()) == :merged

      assert footer(text) =~
               "Посчитано Siala Build Calculator. «?» — то, что ядро считать отказалось."
    end

    test "/sources: раздел о фактах шарда и сиальские оговорки на месте", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")

      assert text(view, "#sources-shard-heading") == "Правила шарда"
      assert has_element?(view, "#sources-shard-facts")

      assert text(view, "#sources-intro") ==
               "Игровые данные и часть описаний калькулятор берёт с вики NWN на Fandom и " <>
                 "перерабатывает под правила Сиалы. Эта страница — атрибуция, которой " <>
                 "требует лицензия этих текстов."

      assert text(view, "#sources-changed") =~
               "скорректировали числа под правила приватного сервера, на который заточен этот калькулятор"

      assert text(view, "#sources-disclaimer") =~
               "Fandom или администрацией шарда, на который он заточен."

      assert text(view, "#sources-gaps-resolved h3") == "Как решены расхождения источников"
      assert text(view, "#sources-gaps-assumed h3") == "Принятые допущения и константы"
    end

    test "карточка расы — имя Сиалы и движковое подписью", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert text(view, "#race-card-dwarf .card-name") == "Гном"
      assert text(view, "#race-card-dwarf .card-en") == "Dwarf"
    end

    test "подписи — прежние русские, байт в байт" do
      siala = Data.ruleset!("siala_41")

      assert Labels.gap({:assumed, :attacks_per_round_table, "fandom:Attacks per round"}, siala) ==
               "таблица атак за раунд взята из fandom:Attacks per round, в правилах шарда её нет"

      assert Import.issue_text({:too_many_classes, 5, 4}, siala) ==
               "в билде 5 классов при лимите 4 — на Сиале такой билд не собрать"

      assert Labels.capped_title() == "Число упёрлось в потолок правил Сиалы — дальше не растёт"

      assert Export.shows_granted_feats?(siala)
      assert Gaps.shard_facts?(siala)
    end

    test "подписи двух имён: общий хелпер", _ctx do
      siala = Data.ruleset!("siala_41")
      vanilla = Data.ruleset!("vanilla")

      assert Labels.race_label(siala, :dwarf) == "Гном (Dwarf)"
      assert Labels.race_label(siala, :human) == "Человек (Human)"
      assert Labels.race_label(vanilla, :half_elf) == "Half-elf"
      assert Labels.race_engine_name(vanilla, :dwarf) == nil
      assert Labels.race_engine_name(siala, :gnome) == "Gnome"

      # Без расы — без пустых скобок (задача 4.18; до неё «не выбрана ()»).
      assert Labels.race_label(siala, nil) == "не выбрана"
      assert Labels.race_engine_name(siala, nil) == nil
    end
  end
end
